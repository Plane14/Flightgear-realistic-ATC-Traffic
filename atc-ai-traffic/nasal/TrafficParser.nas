#=== atc-ai-traffic : default FlightGear traffic-file harvester ===========
# One shared namespace symbol: TrafficParser. Reads the classic
# Traffic-Manager-II XML files that ship under $FG_ROOT/AI/Traffic/<letter>/
# to harvest REAL model paths, liveries, registrations and airline codes so
# the generator/adsb sources reuse assets that already exist in the user's
# FlightGear install. Never modifies the stock files. Peer Utils used by
# name at call time; all IO is nil-guarded.
#=======================================================================

var TrafficParser = {

    _count: 0,

    # Public entry: returns a vector of aircraft-definition hashes, capped at
    # maxFiles files scanned. Each def: {model,livery,registration,airline,
    # actype,homePort}.
    harvest: func(maxFiles) {
        if (maxFiles == nil) maxFiles = 80;
        if (maxFiles < 1) maxFiles = 1;
        TrafficParser._count = 0;
        var out = [];
        var root = getprop("/sim/fg-root") ~ "/AI/Traffic";
        TrafficParser._scan(root, maxFiles, out);
        return out;
    },

    _scan: func(dir, maxFiles, out) {
        var entries = directory(dir);
        if (entries == nil) return;
        foreach (var e; entries) {
            if (e == "." or e == "..") continue;
            var full = dir ~ "/" ~ e;
            var L = Utils.strLen(e);
            var ext = "";
            if (L > 4) ext = substr(e, L - 4, 4);
            if (ext == ".xml") {
                if (TrafficParser._count >= maxFiles) return;
                TrafficParser._read(full, out);
                TrafficParser._count += 1;
            } else {
                # assume a sub-directory (letter buckets)
                TrafficParser._scan(full, maxFiles, out);
            }
        }
    },

    _read: func(path, out) {
        var nd = nil;
        nd = io.read_properties(path);
        if (nd == nil) return;
        var n = 0;
        while (n < 400) {
            var a = nd.getChild("aircraft", n, 0);
            if (a == nil) break;
            var def = {};
            def.model = TrafficParser._s(a, "model");
            def.livery = TrafficParser._s(a, "livery");
            def.registration = TrafficParser._s(a, "registration");
            def.airline = TrafficParser._s(a, "airline");
            def.actype = TrafficParser._s(a, "actype");
            def.homePort = TrafficParser._s(a, "home-port");
            if (def.model != "")
                append(out, def);
            n += 1;
        }
    },

    _s: func(node, child) {
        if (node == nil) return "";
        var x = node.getChild(child, 0);
        if (x == nil) return "";
        var v = x.getValue();
        if (v == nil) return "";
        return v ~ "";
    },

    # Compile a vector of defs into ~pools the generator can draw from.
    # Returns {models:[...], regs:[...], airlines:[...]} unique, non-empty.
    pools: func(defs) {
        var m = {}; var r = {}; var a = {};
        var models = []; var regs = []; var airlines = [];
        foreach (var d; defs) {
            if (d == nil) continue;
            if (d.model != nil and d.model != "" and m[d.model] == nil) { m[d.model] = 1; append(models, d.model); }
            if (d.registration != nil and d.registration != "" and r[d.registration] == nil) { r[d.registration] = 1; append(regs, d.registration); }
            if (d.airline != nil and d.airline != "" and a[d.airline] == nil) { a[d.airline] = 1; append(airlines, d.airline); }
        }
        return {models: models, regs: regs, airlines: airlines};
    },
};
