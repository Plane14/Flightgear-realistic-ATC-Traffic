#=== atc-ai-traffic : math / geometry / formatting utilities ============
# One shared namespace symbol: Utils. Peers referenced by bare name at call
# time. Pure functions - no Property Tree writes (except read-only acPos).
#
# Spherical earth model: R = 3440.065 nautical miles. Distances returned in
# nautical miles, angles in degrees. No regex, no try/catch; nil-guarded.
# JSON PARSING is in its own module (JSON), not here.
#=======================================================================

var Utils = {

    DEG: 180.0 / 3.141592653589793,
    RAD: 3.141592653589793 / 180.0,
    FT_PER_NM: 6076.11549,
    M_PER_FT: 0.3048,
    EARTH_NM: 3440.065,

    normdeg: func(d) {
        if (d == nil)
            return 0;
        d = d % 360.0;
        if (d < 0.0)
            d += 360.0;
        return d;
    },

    clamp: func(x, lo, hi) {
        if (x == nil)
            return lo;
        if (x < lo)
            return lo;
        if (x > hi)
            return hi;
        return x;
    },

    lerp: func(a, b, t) {
        if (a == nil) a = 0.0;
        if (b == nil) b = 0.0;
        if (t == nil) t = 0.0;
        return a + (b - a) * t;
    },

    deg2rad: func(d) {
        if (d == nil)
            return 0;
        return d * Utils.RAD;
    },

    rad2deg: func(r) {
        if (r == nil)
            return 0;
        return r * Utils.DEG;
    },

    # Great-circle distance in nautical miles (haversine).
    distNm: func(lat1, lon1, lat2, lon2) {
        if (lat1 == nil or lon1 == nil or lat2 == nil or lon2 == nil)
            return 0;
        var dlat = (lat2 - lat1) * Utils.RAD;
        var dlon = (lon2 - lon1) * Utils.RAD;
        var s1 = math.sin(dlat / 2.0);
        var s2 = math.sin(dlon / 2.0);
        var a = s1 * s1 + math.cos(lat1 * Utils.RAD) * math.cos(lat2 * Utils.RAD) * s2 * s2;
        if (a < 0.0) a = 0.0;
        if (a > 1.0) a = 1.0;
        var c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
        return Utils.EARTH_NM * c;
    },

    # Initial true bearing (degrees 0..360) from point 1 to point 2.
    bearingDeg: func(lat1, lon1, lat2, lon2) {
        if (lat1 == nil or lon1 == nil or lat2 == nil or lon2 == nil)
            return 0;
        var p1 = lat1 * Utils.RAD;
        var p2 = lat2 * Utils.RAD;
        var dl = (lon2 - lon1) * Utils.RAD;
        var y = math.sin(dl) * math.cos(p2);
        var x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
        return Utils.normdeg(math.atan2(y, x) * Utils.DEG);
    },

    # Destination {lat, lon} from a start, bearing (deg) and distance (nm).
    destLatLon: func(lat, lon, brg, dist) {
        if (lat == nil or lon == nil or brg == nil or dist == nil)
            return {lat: 0.0, lon: 0.0};
        var R = Utils.EARTH_NM;
        var d = dist / R;
        var b = brg * Utils.RAD;
        var p1 = lat * Utils.RAD;
        var l1 = lon * Utils.RAD;
        var sin_p2 = math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b);
        if (sin_p2 > 1.0) sin_p2 = 1.0;
        if (sin_p2 < -1.0) sin_p2 = -1.0;
        var p2 = math.asin(sin_p2);
        var l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1),
                                 math.cos(d) - math.sin(p1) * math.sin(p2));
        return {lat: p2 * Utils.DEG, lon: l2 * Utils.DEG};
    },

    cardinal: func(d) {
        d = Utils.normdeg(d);
        var idx = int((d + 22.5) / 45.0);
        var dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
        if (idx > 7)
            idx = 0;
        if (idx < 0)
            idx = 0;
        return dirs[idx];
    },

    round: func(x, n) {
        if (x == nil)
            return 0;
        var sc = math.pow(10.0, (n == nil ? 0 : n));
        return math.round(x * sc) / sc;
    },

    # String length via substr overrun (no len() builtin).
    strLen: func(s) {
        if (s == nil)
            return 0;
        s = s ~ "";
        var n = 0;
        while (substr(s, n, 1) != "")
            n += 1;
        return n;
    },

    trimSafe: func(s) {
        if (s == nil)
            return "";
        return string.trim(s ~ "");
    },

    stripQuotes: func(s) {
        s = Utils.trimSafe(s);
        var L = Utils.strLen(s);
        if (L >= 2 and substr(s, 0, 1) == '"' and substr(s, L - 1, 1) == '"')
            s = substr(s, 1, L - 2);
        return s;
    },

    fmtAlt: func(ft) {
        if (ft == nil) ft = 0;
        return (math.round(ft / 100.0) * 100) ~ " ft";
    },

    fmtSpd: func(kt) {
        if (kt == nil) kt = 0;
        return math.round(kt) ~ " kt";
    },

    fmtVs: func(fpm) {
        if (fpm == nil) fpm = 0;
        return math.round(fpm) ~ " fpm";
    },

    logInfo: func(m) { logprint(4, "[ATCAI] " ~ m ~ "\n"); },
    logWarn: func(m) { logprint(3, "[ATCAI] " ~ m ~ "\n"); },
    logErr: func(m)  { logprint(1, "[ATCAI] " ~ m ~ "\n"); },

    # Snapshot of the USER aircraft (alt in feet, hdg deg, ground speed kt).
    acPos: func() {
        var pos = geo.aircraft_position();
        if (pos == nil)
            return nil;
        return {
            lat: pos.lat(),
            lon: pos.lon(),
            altFt: pos.alt() / Utils.M_PER_FT,
            hdgDeg: getprop("/orientation/heading-deg") or 0,
            spdKt: getprop("/velocities/groundspeed-kt") or 0,
        };
    },
};
