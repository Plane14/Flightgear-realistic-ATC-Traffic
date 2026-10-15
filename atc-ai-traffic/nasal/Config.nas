#=== atc-ai-traffic : configuration module ==============================
# One shared namespace symbol: Config. Peers (Sounds, TrafficManager, ...)
# and this module are reached by bare name at call time.
#
# Config OWNS the runtime configuration property tree rooted at
#   /sim/atc-ai-traffic/
# DEFAULTS mirror addon-config.xml; setup() only materialises nodes that
# are still missing so addon-config.xml / user overrides always win.
# Dotted keys (e.g. "sound.master-volume") map to nested nodes
# (/sim/atc-ai-traffic/sound/master-volume) via split()/string.join().
# No regex, no try/catch: every reach is nil-guarded.
#=======================================================================

var Config = {

    _base: nil,        # resolved addon base dir (lazy, cached)
    _DEFAULTS: {
        'enabled': 1,
        'source': 'fg-traffic',
        'max-aircraft': 60,
        'radius-nm': 120,
        'debug': 0,
        'cruise-fl': 180,
        'spawn-alt-ft': 8000,
        'min-sep-nm': 3.0,
        'adsb.enabled': 0,
        'adsb.api-base': 'https://api.adsb.lol',
        'adsb.poll-interval-sec': 30,
        'upgrade.enabled': 1,
        'upgrade.assist-approach': 1,
        'upgrade.assist-departure': 0,
        'upgrade.range-nm': 14.0,
        'atc.enabled': 1,
        'atc.volume': 0.8,
        'atc.advisory-range-nm': 10,
        'atc.callsign': 'SHRIMP',
        'sound.enabled': 1,
        'sound.master-volume': 0.7,
        'sound.proximity-enabled': 1,
        'sound.max-distance-nm': 8.0,
    },

    ROOT: func() {
        return "/sim/atc-ai-traffic";
    },

    # Convert a dotted key ("sound.master-volume") into a property path
    # ("/sim/atc-ai-traffic/sound/master-volume") without regex.
    _ppath: func(key) {
        if (key == nil)
            return Config.ROOT();
        var parts = split(".", key ~ "");
        return Config.ROOT() ~ "/" ~ string.join("/", parts);
    },

    # Materialise any missing default node (never overwrite existing values).
    setup: func() {
        foreach (var k; keys(Config._DEFAULTS)) {
            var path = Config._ppath(k);
            if (props.globals.getNode(path) == nil) {
                var n = props.globals.getNode(path, 1);
                if (n != nil)
                    n.setValue(Config._DEFAULTS[k]);
            }
        }
    },

    # Absolute addon base dir (owner of addon-metadata.xml). Resolve once.
    addonBase: func() {
        if (Config._base != nil)
            return Config._base;
        var p = getprop("/addons/by-id/org.flightgear.atcai/path");
        if (p == nil)
            p = getprop("/sim/fg-root");
        if (p != nil)
            Config._base = p;
        return Config._base;
    },

    version: func() {
        return "1.0.0";
    },

    # Generic typed accessor with a caller-supplied fallback.
    getOr: func(key, def) {
        var n = props.globals.getNode(Config._ppath(key));
        if (n == nil)
            return def;
        return n.getValue();
    },

    # Returns 1 or 0.
    getBool: func(key) {
        var v = Config.getOr(key, Config._DEFAULTS[key]);
        if (v == nil)
            return 0;
        if (v == 0)
            return 0;
        return 1;
    },

    getInt: func(key) {
        return int(Config.getOr(key, Config._DEFAULTS[key]) or 0);
    },

    getDouble: func(key) {
        return (Config.getOr(key, Config._DEFAULTS[key]) or 0.0) + 0.0;
    },

    getString: func(key, def) {
        var v = Config.getOr(key, def);
        if (v == nil)
            return def;
        return v ~ "";
    },

    isDebug: func() {
        return Config.getBool('debug');
    },

    dbg: func(msg) {
        if (Config.isDebug())
            logprint(2, "[ATCAI] " ~ msg ~ "\n");
    },
};
