#=== atc-ai-traffic : adsb.lol live-traffic source ========================
# One shared namespace symbol: AdsbSource. OPTIONAL live real-world traffic.
# Feature-detects the FlightGear Nasal http module; if absent, degrades to
# "unavailable" (the addon still works with the built-in traffic manager and
# the generic generator).
#
# adsb.lol public API, no key required:
#   GET {api-base}/v2/lat/{lat}/lon/{lon}/dist/{nm}
#   -> {"ac":[ {hex,flight,r,t,lat,lon,alt_baro,gs,track,baro_rate,...}, ... ]}
# radius (nm) is capped at 250 by the service; be respectful - the manager
# enforces a poll interval (default 30 s). Peers JSON/Utils/Config/Models
# reached by bare name at call time.
#=======================================================================

var AdsbSource = {

    available: func() {
        if (!defined(http)) return 0;
        if (http == nil) return 0;
        if (http.load == nil) return 0;
        return 1;
    },

    # Fetch aircraft near the user. onDone(dataHash) on success,
    # onFail(reasonString) on any failure. Returns 1 if a request was started.
    fetch: func(onDone, onFail) {
        if (AdsbSource.available() == 0) {
            if (onFail != nil) onFail("http-unavailable");
            return 0;
        }
        var p = Utils.acPos();
        if (p == nil) {
            if (onFail != nil) onFail("no-position");
            return 0;
        }
        var base = Config.getString('adsb.api-base', 'https://api.adsb.lol');
        var rad = Config.getInt('radius-nm');
        if (rad < 1) rad = 50;
        if (rad > 250) rad = 250;
        var url = base ~ "/v2/lat/" ~ p.lat ~ "/lon/" ~ p.lon ~ "/dist/" ~ rad;
        Config.dbg("adsb fetch " ~ url);
        http.load(url).done(func(r) {
            if (r == nil or r.response == nil) {
                if (onFail != nil) onFail("empty");
                return;
            }
            var data = JSON.parse(r.response);
            if (data == nil) {
                if (onFail != nil) onFail("parse");
                return;
            }
            if (onDone != nil) onDone(data);
        }).fail(func() {
            if (onFail != nil) onFail("network");
        });
        return 1;
    },

    # Normalise one adsb.lol "ac" entry into a spawn descriptor hash:
    #   {callsign, hex, type, lat, lon, altFt, spd, hdg, vsFpm, onGround}
    # Returns nil for unusable entries (e.g. on the ground with no position).
    describe: func(ac) {
        if (ac == nil) return nil;
        var lat = ac['lat']; var lon = ac['lon'];
        if (lat == nil or lon == nil) return nil;
        var altBaro = ac['alt_baro'];
        var altFt = 0;
        var onGround = 0;
        if (altBaro == nil or altBaro == 'ground') { onGround = 1; altFt = 0; }
        else { altFt = altBaro + 0.0; }
        var cs = ac['flight'];
        if (cs == nil) cs = ac['r'];            # fall back to registration
        if (cs == nil) cs = ac['hex'];
        cs = Utils.stripQuotes(Utils.trimSafe(cs));
        if (cs == "") cs = "UNKNOWN";
        var spd = ac['gs']; if (spd == nil) spd = ac['tas']; if (spd == nil) spd = 0;
        var hdg = ac['track']; if (hdg == nil) hdg = ac['true_heading']; if (hdg == nil) hdg = 0;
        var vs = ac['baro_rate']; if (vs == nil) vs = 0;
        return {
            callsign: cs,
            hex: (ac['hex'] == nil) ? "" : (ac['hex'] ~ ""),
            type: (ac['t'] == nil) ? "" : (ac['t'] ~ ""),
            lat: lat + 0.0,
            lon: lon + 0.0,
            altFt: altFt + 0.0,
            spd: spd + 0.0,
            hdg: hdg + 0.0,
            vsFpm: vs + 0.0,
            onGround: onGround,
        };
    },

    # Extract the "ac" array from a parsed response (or nil).
    aircraft: func(data) {
        if (data == nil) return nil;
        if (data['ac'] == nil) return nil;
        return data['ac'];
    },
};
