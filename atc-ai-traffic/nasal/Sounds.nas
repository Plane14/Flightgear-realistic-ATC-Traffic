#=== atc-ai-traffic : sound playback module ==========================
# One shared namespace symbol: Sounds. Refer to peers (Config, Utils,
# Sounds, ...) by bare name at call time. Core globals used here:
#   getprop()          -> read /sim/sound/enabled user gate
#   props.Node.new()   -> build the fgcommand parameter node
#   fgcommand()        -> execute play-audio-sample
# All sounds are standard 16-bit PCM MONO .wav in Config.addonBase()~"/Sounds".
# NOTE: core Nasal has no try/catch, so every external reach is nil-guarded;
# play()/playScaled() therefore return 0 quietly instead of throwing on a
# missing token, an unset master volume, or an unresolvable Sounds dir.
#====================================================================

var Sounds = {

    _hints: "",          # last human-readable diagnostic string
    _masterVol: nil,     # nil = "unset -> follow config"

    # Token -> {file, volume, queue} description table. Keys match the
    # .wav basenames bundled in Sounds/ (see Tools/generate_sounds.py).
    samples: func() {
        return {
            "ui-click":   ["ui-click.wav",   0.6, "instant"],
            "squelch":    ["squelch.wav",    0.5, "chatter"],
            "call-tone":  ["call-tone.wav",  0.7, "chatter"],
            "chatter":    ["chatter.wav",    0.9, "chatter"],
            "engine":     ["engine.wav",     0.8, "instant"],
            "flyby":      ["flyby.wav",      0.9, "instant"],
            "gear":       ["gear.wav",       0.8, "instant"],
            "stall":      ["stall.wav",      0.8, "instant"],
            "alarm":      ["alarm.wav",      0.9, "instant"],
            "beacon":     ["beacon.wav",     0.7, "chatter"],
        };
    },

    # Absolute Sounds directory (Config is resolved lazily at call time).
    _dir: func() {
        var b = Config.addonBase();
        if (b == nil)
            return nil;
        return b ~ "/Sounds";
    },

    # 1 if the Sounds directory actually contains at least one .wav sample.
    # (In this repo the .wav files are generated artifacts, so they may be
    #  absent until someone runs the generator.) Never throws.
    _hasWavs: func() {
        var d = Sounds._dir();
        if (d == nil) return 0;
        var entries = directory(d);
        if (entries == nil) return 0;
        foreach (var e; entries) {
            if (e == nil) continue;
            var s = e ~ "";
            if (Utils.strLen(s) > 4 and substr(s, Utils.strLen(s) - 4, 4) == ".wav") return 1;
        }
        return 0;
    },

    # Effective volume: master-volume * (setMaster override or 1) * sampleVol,
    # clamped to 0..1. Returns 0 when sound is disabled in settings.
    _vol: func(sampleVol) {
        if (Config.getBool('sound.enabled') == 0)
            return 0.0;
        var master = Config.getDouble('sound.master-volume');
        if (master == nil)
            master = 1.0;
        if (master < 0.0) master = 0.0;
        if (master > 1.0) master = 1.0;
        var mv = (Sounds._masterVol == nil) ? 1.0 : Sounds._masterVol;
        var v = master * mv * sampleVol;
        if (v < 0.0) v = 0.0;
        if (v > 1.0) v = 1.0;
        return v;
    },

    # 1 only if sound.enabled AND /sim/sound/enabled AND dir resolves;
    # otherwise record a hint and return 0.
    enabled: func() {
        if (Config.getBool('sound.enabled') == 0) {
            Sounds._hints = "sound disabled in settings";
            return 0;
        }
        if (getprop('/sim/sound/enabled') == nil or getprop('/sim/sound/enabled') == 0) {
            Sounds._hints = "user sound muted (/sim/sound/enabled off)";
            return 0;
        }
        if (Sounds._dir() == nil) {
            Sounds._hints = "Sounds dir not resolvable";
            return 0;
        }
        if (Sounds._hasWavs() == 0) {
            if (Sounds._warnedNoWavs != 1) {
                Sounds._warnedNoWavs = 1;
                var d = Sounds._dir();
                logprint(1, "[ATCAI] No .wav samples found in " ~ d ~ " - generate them once with: " ~
                             "node Tools/generate_sounds.js   (or: python3 Tools/generate_sounds.py)\n");
            }
            Sounds._hints = "no sound samples present - run Tools/generate_sounds.js";
            return 0;
        }
        Sounds._hints = "sound ready";
        return 1;
    },

    # Fire one sample by token. Returns 1 on success, 0 otherwise (never throws).
    play: func(token) {
        if (token == nil or Sounds.enabled() == 0)
            return 0;
        var v = Sounds.samples()[token];
        if (v == nil)
            return 0;
        var dir = Sounds._dir();
        if (dir == nil)
            return 0;
        var params = props.Node.new({
            queue:  v[2],
            path:   dir,
            file:   v[0],
            volume: Sounds._vol(v[1]),
        });
        fgcommand("play-audio-sample", params);
        return 1;
    },

    # Like play(), but volume is further scaled by clamp(ratio01,0,1).
    # Used by the proximity engine for distance attenuation.
    playScaled: func(token, ratio01) {
        if (token == nil or Sounds.enabled() == 0)
            return 0;
        var r = ratio01;
        if (r == nil) r = 0.0;
        if (r < 0.0) r = 0.0;
        if (r > 1.0) r = 1.0;
        var v = Sounds.samples()[token];
        if (v == nil)
            return 0;
        var dir = Sounds._dir();
        if (dir == nil)
            return 0;
        var vol = Sounds._vol(v[1]) * r;
        if (vol < 0.0) vol = 0.0;
        if (vol > 1.0) vol = 1.0;
        var params = props.Node.new({
            queue:  v[2],
            path:   dir,
            file:   v[0],
            volume: vol,
        });
        fgcommand("play-audio-sample", params);
        return 1;
    },

    # Programmatic master override. nil -> follow config; else clamp 0..1.
    setMasterVolume: func(v) {
        if (v == nil) v = 0.0;
        if (v < 0.0) v = 0.0;
        if (v > 1.0) v = 1.0;
        Sounds._masterVol = v;
    },

    # Return the last diagnostic string.
    hints: func() {
        return Sounds._hints;
    },
};
