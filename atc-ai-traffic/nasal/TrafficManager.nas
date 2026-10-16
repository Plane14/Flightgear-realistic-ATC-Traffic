#=== atc-ai-traffic : traffic orchestrator ===============================
# One shared namespace symbol: TrafficManager (its main() is driven by
# addon-main.nas). Ties together AIAircraft + Behavior + TrafficParser +
# AdsbSource + Sounds + Config, and drives everything from a single update
# timer. Three interchangeable sources (Config 'source'):
#   fg-traffic : ATTACH to aircraft created by FlightGear's own traffic
#                manager (under /ai/models/aircraft[*]) to add sound + ATC.
#                Never removes or moves them - fully cooperative.
#   generator  : SPAWN our own generic traffic in a ring around the user
#                and steer it through controls/flight/* (endless legs).
#   adsb       : OPTIONAL live real-world traffic from adsb.lol.
# Also runs proximity engine/flap sounds and feeds ATC + HUD each tick.
#
# NASAL notes honoured here: foreach (x; vec) uses a SEMICOLON; hashes are
# pruned by rebuilding + reassigning (no delete operator). All reaches are
# nil-guarded.
#=======================================================================

var TrafficManager = {

    _timer: nil,
    _list: {},          # key -> AIAircraft instance
    _src: nil,
    _pools: nil,        # harvested {models,regs,airlines}
    _lastPoll: -1.0,
    _attached: {},      # fg-traffic: ai index -> 1
    _seed: 0,
    _frames: 0,

    # --- tiny deterministic PRNG (Nasal has no math.random) --------------
    _rnd: func() {
        TrafficManager._seed = (TrafficManager._seed * 1103515245 + 12345) % 2147483648;
        return TrafficManager._seed / 2147483648.0;
    },
    _rndInt: func(lo, hi) {
        return lo + int(TrafficManager._rnd() * (hi - lo + 1));
    },
    _rndCategory: func() {
        var r = TrafficManager._rnd();
        if (r < 0.42) return 'jet';
        if (r < 0.62) return 'heavy_jet';
        if (r < 0.80) return 'turboprop';
        if (r < 0.92) return 'piston';
        return 'helicopter';
    },

    # --- lifecycle -------------------------------------------------------
    start: func() {
        Config.setup();
        var t = getprop("/sim/time/elapsed-sec");
        if (t == nil or t == 0) t = 1;
        TrafficManager._seed = int(t * 131072.0) % 2147483647;
        if (TrafficManager._seed < 1) TrafficManager._seed = 1;
        TrafficManager._src = Config.getString('source', 'fg-traffic');
        TrafficManager._list = {};
        TrafficManager._attached = {};
        TrafficManager._lastPoll = -1.0;
        if (TrafficManager._timer != nil) TrafficManager._timer.stop();
        TrafficManager._timer = maketimer(0.5, TrafficManager.update);
        TrafficManager._timer.simulatedTime = 1;
        TrafficManager._timer.start();
        Utils.logInfo("TrafficManager started, source=" ~ TrafficManager._src);
    },

    stop: func() {
        if (TrafficManager._timer != nil) TrafficManager._timer.stop();
        TrafficManager._list = {};
        TrafficManager._attached = {};
    },

    setSource: func(s) {
        if (s == nil) return;
        var n = props.globals.getNode(Config._ppath('source'), 1);
        if (n != nil) n.setValue(s);
    },

    getSource: func() {
        return TrafficManager._src;
    },

    getAircraft: func() {
        var v = [];
        foreach (var k; keys(TrafficManager._list)) append(v, TrafficManager._list[k]);
        return v;
    },

    stats: func() {
        var total = 0; var owned = 0;
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            total += 1;
            if (ac != nil and ac.owned == 1) owned += 1;
        }
        return {total: total, owned: owned, source: TrafficManager._src};
    },

    reload: func() {
        TrafficManager.stop();
        TrafficManager.start();
    },

    # rebuild _list keeping only entries for which keep(key,ac) is truthy.
    # Dropped entries have remove() called so their property-tree nodes
    # and 3D models are cleaned up (prevents leaks, esp. on source switch).
    _rebuildList: func(keep) {
        var h = {};
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            if (keep(k, ac)) h[k] = ac;
            else if (ac != nil) ac.remove();
        }
        TrafficManager._list = h;
    },

    # --- main tick -------------------------------------------------------
    update: func() {
        TrafficManager._frames += 1;
        if (Config.getBool('enabled') == 0) return;
        var s = Config.getString('source', TrafficManager._src or 'fg-traffic');
        if (s != TrafficManager._src) {
            TrafficManager._rebuildList(func(k, ac) { return ac.owned == 1 ? 0 : 1; });
            TrafficManager._src = s;
        }
        if (TrafficManager._src == 'generator') TrafficManager._tickGenerator();
        elsif (TrafficManager._src == 'adsb') TrafficManager._tickAdsb();
        else TrafficManager._tickFgTraffic();

        TrafficManager._steerOwned();
        TrafficManager._soundTick();
        ATC.update(TrafficManager);
        if (HUD != nil) HUD.refresh(TrafficManager);
    },

    # --- source: attach to FlightGear's own traffic ----------------------
    _tickFgTraffic: func() {
        var aiRoot = props.globals.getNode("ai/models", 1);
        if (aiRoot == nil) return;
        # reset attached tracking at the start so recycled FG aircraft
        # indices get re-attached instead of being skipped as stale.
        TrafficManager._attached = {};
        var ck = Config.getInt('max-aircraft'); if (ck < 1) ck = 60;
        var n = 0;
        while (n < ck) {
            var node = aiRoot.getChild("aircraft", n, 0);
            if (node == nil) break;
            if (TrafficManager._attached[n] == nil) {
                TrafficManager._attached[n] = 1;
                var ac = AIAircraft.new({});
                if (ac.attach(n) == 1) TrafficManager._list[n] = ac;
            }
            n += 1;
        }
        # drop references whose AI node disappeared
        TrafficManager._rebuildList(func(k, ac) { return ac.node == nil ? 0 : 1; });
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            if (ac != nil and ac.owned == 0) TrafficManager._attached[ac.aiIndex] = 1;
        }
    },

    # --- source: generic generator ---------------------------------------
    _tickGenerator: func() {
        var maxA = Config.getInt('max-aircraft'); if (maxA < 1) maxA = 1;
        var st = TrafficManager.stats();
        if (st.owned < maxA) TrafficManager._genSpawn();
        var range = Config.getInt('radius-nm'); if (range < 5) range = 60;
        # remove owned aircraft that flew far outside the region
        var far = {};
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            if (ac == nil or ac.owned == 0) continue;
            var d = ac.distToUser();
            if (d != nil and d > (range * 2.0 + 60)) far[k] = 1;
        }
        foreach (var k; keys(far)) {
            var ac = TrafficManager._list[k];
            if (ac != nil) ac.remove();
        }
        TrafficManager._rebuildList(func(k, ac) { return far[k] == nil ? 1 : 0; });
    },

    _genSpawn: func() {
        var p = Utils.acPos();
        if (p == nil) return;
        if (TrafficManager._pools == nil)
            TrafficManager._pools = TrafficParser.pools(TrafficParser.harvest());
        var pools = TrafficManager._pools;
        var range = Config.getInt('radius-nm'); if (range < 5) range = 60;

        var cat = TrafficManager._rndCategory();
        var modelPath = nil;
        var reg = ""; var airline = "";
        if (pools != nil and pools.models != nil and size(pools.models) > 0) {
            modelPath = pools.models[TrafficManager._rndInt(0, size(pools.models) - 1)];
            cat = 'jet';
            if (size(pools.regs) > 0) reg = pools.regs[TrafficManager._rndInt(0, size(pools.regs) - 1)];
            if (size(pools.airlines) > 0) airline = pools.airlines[TrafficManager._rndInt(0, size(pools.airlines) - 1)];
        } else {
            modelPath = Models.pickModelPath(cat);
        }
        var cs = (airline != "") ? (airline ~ TrafficManager._rndInt(100, 999))
                                 : ((reg != "") ? (reg ~ TrafficManager._rndInt(1, 9)) : ("AI" ~ TrafficManager._rndInt(1000, 9999)));

        var brg = TrafficManager._rndInt(0, 359);
        var d0 = range + TrafficManager._rndInt(15, 80);
        var d1 = range + TrafficManager._rndInt(15, 80);
        var start = Utils.destLatLon(p.lat, p.lon, brg, d0);
        var dest = Utils.destLatLon(p.lat, p.lon, (brg + 180) % 360, d1);
        var altFt = Behavior.cruiseFlToFt(Config.getInt('cruise-fl'));
        if (cat == 'piston' or cat == 'turboprop' or cat == 'helicopter') {
            if (altFt > 10000.0) altFt = 10000.0;
        }
        var hdgOut = Utils.bearingDeg(start.lat, start.lon, dest.lat, dest.lon);

        var inst = AIAircraft.new({
            callsign: cs, hex: "", category: cat,
            perfClass: Models.performanceClass(cat),
            modelPath: modelPath, lat: start.lat, lon: start.lon,
            altFt: altFt, hdg: hdgOut, spd: Behavior.cruiseSpeed(cat),
            registration: reg, airline: airline, phase: 'cruise',
        });
        if (inst.spawn() == 1) {
            inst._plan = {dLat: dest.lat, dLon: dest.lon, altFt: altFt};
            TrafficManager._list[cs] = inst;
        }
    },

    # --- source: adsb.lol live traffic -----------------------------------
    _tickAdsb: func() {
        if (AdsbSource.available() == 0) { Config.dbg("adsb http unavailable"); return; }
        var now = getprop("/sim/time/elapsed-sec") or 0;
        var interval = Config.getInt('adsb.poll-interval-sec'); if (interval < 10) interval = 30;
        if (TrafficManager._lastPoll >= 0 and (now - TrafficManager._lastPoll) < interval) return;
        TrafficManager._lastPoll = now;
        AdsbSource.fetch(func(data) { TrafficManager._adsbApply(data); },
                         func(reason) { Config.dbg("adsb fetch failed: " ~ reason); });
    },

    _adsbApply: func(data) {
        var acs = AdsbSource.aircraft(data);
        if (acs == nil) return;
        var seen = {};
        var maxA = Config.getInt('max-aircraft'); if (maxA < 1) maxA = 1;
        var added = 0;
        foreach (var rec; acs) {
            var d = AdsbSource.describe(rec);
            if (d == nil or d.onGround == 1 or d.hex == "") continue;
            seen[d.hex] = 1;
            var inst = TrafficManager._list[d.hex];
            if (inst == nil) {
                if (added >= maxA) continue;
                inst = AIAircraft.new({
                    callsign: d.callsign, hex: d.hex, category: Models.categoryFor(d.type),
                    perfClass: Models.performanceClass(d.type),
                    modelPath: Models.pickModelPath(d.type),
                    lat: d.lat, lon: d.lon, altFt: d.altFt,
                    hdg: d.hdg, spd: d.spd, phase: 'cruise',
                });
                if (inst.spawn() == 1) { TrafficManager._list[d.hex] = inst; added += 1; }
                else continue;
            }
            inst._rt = d;
        }
        # retire owned aircraft not seen in this poll
        var stale = {};
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            if (ac != nil and ac.owned == 1 and seen[k] == nil) {
                ac.remove();
                stale[k] = 1;
            }
        }
        TrafficManager._rebuildList(func(k, ac) { return stale[k] == nil ? 1 : 0; });
    },

    # --- steering for aircraft we own (generator + adsb) -----------------
    _steerOwned: func() {
        var ks = keys(TrafficManager._list);
        foreach (var k; ks) {
            var ac = TrafficManager._list[k];
            if (ac == nil) continue;

            # default-traffic aircraft (attached, not owned): upgrade them with
            # cooperative ATC guidance (approach / departure) near the user.
            if (ac.owned == 0) {
                var g = nil;
                if (ATC != nil and Config.getBool('upgrade.enabled')) {
                    var rangeN = Config.getDouble('upgrade.range-nm'); if (rangeN < 5) rangeN = 14;
                    var d = ac.distToUser();
                    if (d != nil and d <= rangeN)
                        g = ATC.guidance(ac);
                }
                ac.update(g);
                continue;
            }

            var s = ac.getState(); if (s == nil) continue;

            if (ac._rt != nil) {                       # adsb: follow the real track
                var rt = ac._rt;
                ac.update({targetHdg: rt.hdg, targetAlt: rt.altFt, targetSpd: rt.spd, phase: 'cruise'});
                continue;
            }
            if (ac._plan != nil) {                     # generator: fly to destination
                var pl = ac._plan;
                var distRem = Utils.distNm(s.lat, s.lon, pl.dLat, pl.dLon);
                if (distRem < 25.0) {
                    var p = Utils.acPos();
                    if (p != nil) {
                        var b = TrafficManager._rndInt(0, 359);
                        var dd = (Config.getInt('radius-nm') or 60) + TrafficManager._rndInt(15, 120);
                        var nd = Utils.destLatLon(p.lat, p.lon, b, dd);
                        pl.dLat = nd.lat; pl.dLon = nd.lon;
                    }
                }
                var hdg = Utils.bearingDeg(s.lat, s.lon, pl.dLat, pl.dLon);
                ac.update({targetHdg: hdg, targetAlt: pl.altFt,
                           targetSpd: Behavior.cruiseSpeed(ac.category), phase: 'cruise'});
                continue;
            }
            ac.update(nil);
        }
    },

    # --- proximity sound -------------------------------------------------
    _soundTick: func() {
        if (Config.getBool('sound.enabled') == 0) return;
        if (Config.getBool('sound.proximity-enabled') == 0) return;
        var maxD = Config.getDouble('sound.max-distance-nm'); if (maxD <= 0) maxD = 8;
        var rank = [];
        foreach (var k; keys(TrafficManager._list)) {
            var ac = TrafficManager._list[k];
            if (ac == nil) continue;
            var d = ac.distToUser();
            if (d == nil or d > maxD) continue;
            append(rank, [d, k]);
        }
        if (size(rank) == 0) return;
        # insertion sort ascending by distance
        var i = 1;
        while (i < size(rank)) {
            var j = i; var item = rank[i];
            while (j > 0 and rank[j - 1][0] > item[0]) { rank[j] = rank[j - 1]; j -= 1; }
            rank[j] = item; i += 1;
        }
        var now = getprop("/sim/time/elapsed-sec") or 0;
        var lim = 6; if (size(rank) < lim) lim = size(rank);
        var idx = 0;
        while (idx < lim) {
            var ac = TrafficManager._list[rank[idx][1]];
            var d = rank[idx][0];
            var ratio = 1.0 - (d / maxD); if (ratio < 0) ratio = 0;
            if (ac._engT == nil) ac._engT = 0;
            if (now - ac._engT > 1.4) {
                ac._engT = now;
                if (ratio < 0.12) Sounds.playScaled('gear', ratio);
                else Sounds.playScaled('engine', ratio);
            }
            if (ac._flyT == nil) ac._flyT = 0;
            if (d < 2.5 and now - ac._flyT > 6.0) {
                var st = ac.getState();
                var sp = (st != nil) ? st.spd : 0;
                if (sp > 60) { ac._flyT = now; Sounds.playScaled('flyby', 1.0 - d / 3.0); }
            }
            idx += 1;
        }
    },
};
