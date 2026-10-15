#=== atc-ai-traffic : airport / procedure data access =====================
# One shared namespace symbol: Procedures. Thin, DEFENSIVE wrappers around
# FlightGear's own navigation data (airportinfo(), the NavCache procedures,
# and environment wind), used by the ATC layer to UPGRADE the default
# traffic system rather than fight it. Every reach is nil-guarded and
# version tolerant: ghosts vary between FlightGear releases, so any missing
# field simply yields a sensible fallback.
#
# These are read-only helpers; nothing here touches /ai/models.
#=======================================================================

var Procedures = {

    # Live wind direction (FROM) and speed.
    wind: func() {
        var dir = getprop("/environment/wind-from-deg")
                or getprop("/environment/wind-direction-deg")
                or 0;
        var kt = getprop("/environment/wind-speed-kt")
              or getprop("/environment/wind-speed-kt-surface")
              or 0;
        return {dir: dir + 0.0, kt: kt + 0.0};
    },

    # Ambient pressure (inHg) and outside-air temperature (degC), best effort.
    meteo: func() {
        var qnh = getprop("/environment/pressure-inHg")
                or getprop("/environment/sea-level-pressure-inHg")
                or getprop("/environment/pressure-sea-level-inhg")
                or 29.92;
        var t = getprop("/environment/temperature-degc")
              or getprop("/environment/temperature-surface-degc")
              or 15;
        return {qnh: qnh + 0.0, tempC: t + 0.0};
    },

    # Runway table id -> {lat, lon, heading, lengthM, elevFt}.
    runwayList: func(apt) {
        var out = {};
        if (apt == nil or apt.runways == nil) return out;
        var fieldElevFt = 0;
        if (apt.elevation != nil) fieldElevFt = apt.elevation / 0.3048;
        foreach (var id; keys(apt.runways)) {
            var r = apt.runways[id];
            if (r == nil) continue;
            var h = r.heading; var la = r.lat; var lo = r.lon;
            if (h == nil or la == nil or lo == nil) continue;
            out[id] = {
                lat: la + 0.0, lon: lo + 0.0, heading: h + 0.0,
                lengthM: (r.length == nil) ? 0 : (r.length + 0.0),
                elevFt: fieldElevFt,
                ils: (r.ils != nil),
            };
        }
        return out;
    },

    # Choose the active runway: best headwind, tie-broken by least crosswind.
    # Returns {id, heading, lat, lon, elevFt, list, wind, headwind, crosswind}
    # or nil for an airport with no runways.
    activeRunway: func(apt) {
        var list = Procedures.runwayList(apt);
        if (size(keys(list)) == 0) return nil;
        var w = Procedures.wind();
        var bestId = nil; var bestScore = -1e9; var bestHw = 0; var bestXw = 0; var bestHd = 0;
        foreach (var id; keys(list)) {
            var r = list[id];
            var ang = (w.dir - r.heading) * 0.017453292519943295;
            var head = math.cos(ang) * w.kt;
            var cross = math.sin(ang) * w.kt; if (cross < 0) cross = -cross;
            var score = head - cross * 1.5;          # headwind good, crosswind bad
            if (score > bestScore) {
                bestScore = score; bestId = id; bestHw = head; bestXw = cross; bestHd = r.heading;
            }
        }
        var rb = list[bestId];
        return {
            id: bestId, heading: rb.heading, lat: rb.lat, lon: rb.lon,
            elevFt: rb.elevFt, lengthM: rb.lengthM, headwind: bestHw, crosswind: bestXw,
            list: list, wind: w, ils: rb.ils,
        };
    },

    # Airport comm frequency of a given type ("tower","ground","approach",
    # "atis","awos"). Returns a formatted string like "118.70" or nil.
    commFreq: func(apt, type) {
        if (apt == nil or apt.comms == nil) return nil;
        var list = nil;
        list = apt.comms(type);
        if (list == nil or size(list) == 0) {
            # some versions want comms() then filter by ident
            if (apt.comms() != nil) {
                foreach (var c; apt.comms()) {
                    var ident = string.lc(c.ident ~ "");
                    if (string.index(ident, type) != nil) { list = [c.frequency]; break; }
                }
            }
        }
        if (list == nil or size(list) == 0) return nil;
        var f = list[0] + 0.0;
        var s = sprintf("%.3f", f);          # e.g. "118.700"
        var L = Utils.strLen(s);
        while (L > 0 and substr(s, L - 1, 1) == "0") { s = substr(s, 0, L - 1); L -= 1; }
        if (L > 0 and substr(s, L - 1, 1) == ".") s = substr(s, 0, L - 1);
        return s;
    },

    # Approach geometry as an ordered vector of {lat, lon, name} legs,
    # best-effort from the NavCache procedures (ILS-style preferred). nil if
    # the airport publishes no procedures.
    approachPath: func(apt, rwyId) {
        if (apt == nil) return nil;
        var ids = nil;
        if (apt.getApproachList != nil) ids = apt.getApproachList();
        if (ids == nil or size(ids) == 0) return nil;
        var id = ids[0];
        foreach (var a; ids) {
            if (string.index(a, "ILS") != nil) { id = a; break; }
        }
        var proc = nil;
        if (apt.getApproach != nil) proc = apt.getApproach(id);
        if (proc == nil and apt.getIAP != nil) proc = apt.getIAP(id);
        if (proc == nil or proc.route == nil) return nil;
        var pts = proc.route(rwyId);
        if (pts == nil) return nil;
        var out = [];
        foreach (var leg; pts) {
            var ll = Procedures._legLL(leg);
            if (ll != nil)
                append(out, {lat: ll[0], lon: ll[1], name: (leg.wp_name == nil) ? "" : (leg.wp_name ~ "")});
        }
        if (size(out) < 1) return nil;
        return out;
    },

    _legLL: func(leg) {
        if (leg == nil) return nil;
        var lat = leg.lat; if (lat == nil) lat = leg.wp_lat;
        var lon = leg.lon; if (lon == nil) lon = leg.wp_lon;
        if (lat == nil or lon == nil) return nil;
        return [lat + 0.0, lon + 0.0];
    },

    # Localizer + glideslope deviation of a position from a runway, in
    # human-friendly units. Returns {distNm, brgToThr, crosstrackNm,
    # alongNm, onFinal}.
    finalFrom: func(rwy, lat, lon) {
        if (rwy == nil) return nil;
        var dist = Utils.distNm(lat, lon, rwy.lat, rwy.lon) or 0;
        var brg = Utils.bearingDeg(lat, lon, rwy.lat, rwy.lon);
        var crs = rwy.heading;
        var off = brg - crs; if (off > 180) off -= 360; if (off < -180) off += 360;
        var crossNm = math.sin(off * 0.017453292519943295) * dist;
        var alongNm = math.cos(off * 0.017453292519943295) * dist;
        return {distNm: dist, brg: brg, crosstrackNm: crossNm,
                alongNm: alongNm, offDeg: off, onFinal: (abs(off) < 8 and crossNm > -0.3)};
    },
};
