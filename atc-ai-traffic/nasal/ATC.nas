#=== atc-ai-traffic : ATC controller (upgrades the default system) ========
# One shared namespace symbol: ATC. This is a COOPERATIVE, read-only ATC
# overlay that upgrades FlightGear's built-in traffic: it determines the
# active runway from live wind, reads real tower/ground/APP/ATIS frequencies
# from airportinfo(), and issues realistic guidance that the TrafficManager
# applies to the default-traffic aircraft (approach down the localizer +
# glideslope; realistic departure climbs). It never touches the user's own
# aircraft. Also produces plain-language TRAFFIC advisories and separation
# alerts, and an ATIS-style line for the HUD.
#
# Peers Procedures/Utils/Behavior/Config/Sounds + the AIAircraft instances
# passed in are reached by bare name at call time.
#=======================================================================

var ATC = {

    _t: 0,
    _aptId: "",
    _aptName: "",
    _apt: nil,
    _fieldElevFt: 0,
    _active: nil,          # Procedures.activeRunway() result
    _apprPath: nil,        # cached approach legs for the HUD
    _log: [],
    _lastAdv: 0,
    _lastAmb: 0,
    _lastAtis: 0,
    _freqs: {},

    # ---- airport + wind refresh ---------------------------------------
    _refreshAirport: func() {
        ATC._apt = nil; ATC._aptId = ""; ATC._aptName = "";
        ATC._active = nil; ATC._apprPath = nil; ATC._freqs = {};
        var apt = nil;
        apt = airportinfo();
        if (apt == nil or apt.id == nil) return;
        ATC._apt = apt;
        ATC._aptId = apt.id ~ "";
        if (apt.name != nil) ATC._aptName = apt.name ~ "";
        if (apt.elevation != nil) ATC._fieldElevFt = apt.elevation / 0.3048;
        ATC._active = Procedures.activeRunway(apt);
        ATC._freqs = {
            tower: Procedures.commFreq(apt, "tower"),
            ground: Procedures.commFreq(apt, "ground"),
            approach: Procedures.commFreq(apt, "approach"),
            atis: (Procedures.commFreq(apt, "atis") or Procedures.commFreq(apt, "awos")),
        };
        if (ATC._active != nil)
            ATC._apprPath = Procedures.approachPath(apt, ATC._active.id);
    },

    # ---- guidance for the DEFAULT-traffic aircraft --------------------
    approachGuidance: func(ac) {
        var s = ac.getState(); if (s == nil) return nil;
        var a = ATC._active; if (a == nil or a.lat == nil) return nil;
        if (ATC._apt == nil) return nil;
        var r = a;
        var distNm = Utils.distNm(s.lat, s.lon, r.lat, r.lon);
        var rangeN = Config.getDouble('upgrade.range-nm'); if (rangeN < 5) rangeN = 14;
        if (distNm > rangeN) return nil;
        var agl = s.altFt - a.elevFt;
        var vs = (s.vsFpm == nil) ? 0 : s.vsFpm;
        var descending = (vs < -150);
        var lowFinal = (agl < 3000);
        # only bias an aircraft that is clearly arriving
        if (!(descending or lowFinal)) return nil;

        var crs = r.heading + 0.0;
        var targetAlt = Behavior.glideslopeAltFt(a.elevFt, distNm, 3.0);
        # don't arrest above/through the glide until short of the threshold
        if (targetAlt < a.elevFt + 120 and distNm > 0.8) targetAlt = a.elevFt + 120;
        var targetSpd = Behavior.approachSpeed(s.category);
        if (distNm < 3.5) targetSpd -= 15;
        if (distNm < 1.0) targetSpd -= 25;
        if (targetSpd < 65) targetSpd = 65;

        var ff = Procedures.finalFrom(r, s.lat, s.lon);
        if (ff == nil) return nil;
        # fly the extended centreline once established, else steer to the fix
        var established = (abs(ff.offDeg) < 20) or (distNm < 2.5);
        var hdg = established ? crs : ff.brg;
        return {
            targetHdg: Utils.normdeg(hdg),
            targetAlt: targetAlt,
            targetSpd: targetSpd,
            phase: 'approach',
            _dist: distNm,
        };
    },

    departureGuidance: func(ac) {
        var s = ac.getState(); if (s == nil) return nil;
        var a = ATC._active; if (a == nil or a.lat == nil) return nil;
        var r = a;
        var distNm = Utils.distNm(s.lat, s.lon, r.lat, r.lon);
        var rangeN = Config.getDouble('upgrade.range-nm'); if (rangeN < 5) rangeN = 14;
        if (distNm > rangeN) return nil;
        var agl = s.altFt - a.elevFt;
        var vs = (s.vsFpm == nil) ? 0 : s.vsFpm;
        if (!(vs > 100 and agl > 50 and agl < 9000)) return nil;    # fresh low departure
        var targetAlt = math.min(a.elevFt + 5000.0, Behavior.cruiseFlToFt(Config.getInt('cruise-fl')));
        var targetSpd = Behavior.approachSpeed(s.category) * 1.6;
        return {
            targetHdg: Utils.normdeg(r.heading),
            targetAlt: targetAlt,
            targetSpd: targetSpd,
            phase: 'climb',
            _dist: distNm,
        };
    },

    # ---- advisories / separation / ATIS -------------------------------
    _clock: func(relBrg) {
        var c = int((Utils.normdeg(relBrg) + 15.0) / 30.0) % 12;
        if (c == 0) c = 12;
        return c;
    },

    _push: func(msg) {
        if (msg == nil or msg == "") return;
        append(ATC._log, msg);
        if (size(ATC._log) > 7) ATC._log = [];
    },

    _separation: func(list, p) {
        # crude conflict scan among nearby AI: <5nm horizontal AND <1000ft vertical
        var worst = nil; var worstV = 1e9;
        var n = 0; var total = size(list);
        while (n < total) {
            var m = n + 1;
            while (m < total) {
                var a = list[n]; var b = list[m];
                if (a != nil and b != nil) {
                    var sa = a.getState(); var sb = b.getState();
                    if (sa != nil and sb != nil) {
                        var h = Utils.distNm(sa.lat, sa.lon, sb.lat, sb.lon);
                        var v = (sa.altFt - sb.altFt); if (v < 0) v = -v;
                        if (h < 5.0 and v < 1000.0) {
                            var score = h + v / 1000.0;
                            if (score < worstV) {
                                worstV = score;
                                worst = {a: sa.callsign, b: sb.callsign,
                                          d: math.round(h * 10) / 10.0, v: math.round(v)};
                            }
                        }
                    }
                }
                m += 1;
            }
            n += 1;
        }
        return worst;
    },

    update: func(tm) {
        var now = getprop("/sim/time/elapsed-sec") or 0;
        if (Config.getBool('atc.enabled') == 0) { ATC._status = nil; return; }
        var p = Utils.acPos();
        if (tm == nil) return;
        # refresh airport / runways / freqs every ~6s
        if (now - ATC._t > 6.0) {
            ATC._t = now;
            ATC._refreshAirport();
        }

        var advR = Config.getInt('atc.advisory-range-nm'); if (advR < 1) advR = 12;
        var list = tm.getAircraft();

        # nearest-first within advisory range
        var near = [];
        foreach (var ac; list) {
            if (ac == nil) continue;
            var d = ac.distToUser();
            if (d == nil or d > advR) continue;
            var brg = ac.bearingFromUser();
            var clock = (brg == nil) ? 12 : ATC._clock((brg - (p == nil ? 0 : p.hdgDeg)));
            var s = ac.getState(); if (s == nil) continue;
            var altRel = (p == nil) ? 0 : (s.altFt - p.altFt);
            append(near, [d, s.callsign, clock, altRel, s.category, ac]);
        }
        var i = 1;
        while (i < size(near)) {
            var j = i; var it = near[i];
            while (j > 0 and near[j - 1][0] > it[0]) { near[j] = near[j - 1]; j -= 1; }
            near[j] = it; i += 1;
        }

        # primary TRAFFIC advisory at a human cadence
        if (size(near) > 0 and now - ATC._lastAdv > 3.0) {
            ATC._lastAdv = now;
            var nd = near[0];
            var vert = "same altitude";
            if (nd[3] > 300) vert = (math.round(nd[3] / 100.0) * 100) ~ " ft above";
            if (nd[3] < -300) vert = (math.round(-nd[3] / 100.0) * 100) ~ " ft below";
            # classify phase from geometry
            var tag = "traffic";
            if (ATC._active != nil) {
                var s2 = (nd[5] != nil) ? nd[5].getState() : nil;
                if (s2 != nil) {
                    var dd = Utils.distNm(s2.lat, s2.lon, ATC._active.lat, ATC._active.lon);
                    if (dd < 14 and s2.vsFpm < -150) tag = "arrival";
                    if (dd < 14 and nd[3] > 200) tag = "departure";
                }
            }
            ATC._push("TRAFFIC " ~ nd[2] ~ " o'clock, " ~ math.round(nd[0]) ~ " nm, " ~ vert ~ ", " ~ tag ~ " " ~ nd[1]);
        }

        # separation alert (only meaningful with >=2 craft)
        var sep = nil;
        if (Config.getBool('upgrade.enabled') and size(near) >= 2) {
            var closeAcs = [];
            foreach (var e; near) append(closeAcs, e[5]);
            sep = ATC._separation(closeAcs, p);
        }
        if (sep != nil and now - ATC._lastAdv > 1.0)
            ATC._push("SEPARATION: " ~ sep.a ~ " / " ~ sep.b ~ "  " ~ sep.d ~ " nm, " ~ sep.v ~ " ft");

        # ATIS-style readout (throttled so the log isn't a wall of text)
        if (ATC._aptId != "" and now - ATC._lastAtis > 25.0) {
            ATC._lastAtis = now;
            var m = Procedures.meteo();
            var w = Procedures.wind();
            var rwyTxt = (ATC._active != nil) ? ATC._active.id : "N/A";
            ATC._push(ATC._aptId ~ " ATIS: arr rwy " ~ rwyTxt ~
                      ", wind " ~ Utils.cardinal(w.dir) ~ " " ~ math.round(w.kt) ~
                      " kt, QNH " ~ math.round(m.qnh * 100) ~ ", TEMP " ~ math.round(m.tempC));
        }

        # brief radio ambience near an ATC airport
        if (ATC._aptId != "" and Sounds.enabled() and now - ATC._lastAmb > 14.0) {
            ATC._lastAmb = now;
            Sounds.play('squelch');
            Sounds.play('chatter');
        }

        ATC._status = {
            aptId: ATC._aptId,
            aptName: ATC._aptName,
            fieldElevFt: ATC._fieldElevFt,
            active: ATC._active,
            apprPath: ATC._apprPath,
            freqs: ATC._freqs,
            count: size(near),
            pos: p,
            log: ATC._log,
            sep: sep,
        };
    },

    status: func() { return ATC._status; },
    guidance: func(ac) {
        if (Config.getBool('upgrade.enabled') == 0) return nil;
        if (Config.getBool('upgrade.assist-approach')) {
            var g = ATC.approachGuidance(ac);
            if (g != nil) return g;
        }
        if (Config.getBool('upgrade.assist-departure')) {
            var g2 = ATC.departureGuidance(ac);
            if (g2 != nil) return g2;
        }
        return nil;
    },
};
