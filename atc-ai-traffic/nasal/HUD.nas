#=== atc-ai-traffic : Canvas radar HUD ===================================
# One shared namespace symbol: HUD. OPTIONAL top-down traffic radar drawn
# with FlightGear's Canvas, plus a text block of ATC advisories. Hidden by
# default; opened/closed from the menubar so it can never affect the sim
# unless the user asks for it. Peers Utils/Config/Sounds/ATC/TrafficManager
# reached by bare name at call time.
#
# Uses the documented canvas.new({...}) + canvas.Window.new(...) window API.
# Text colours are passed to setColor() as numeric R,G,B (0..1) because that
# signature works across FlightGear versions; path fill/stroke use CSS hex.
# Every external reach is guarded; if Window/canvas is unavailable show()
# quietly declines and refresh() stays a no-op.
#=======================================================================

var HUD = {

    _window: nil,
    _canvas: nil,
    _root: nil,
    _grp: nil,
    _shown: 0,
    _W: 700,
    _H: 520,

    available: func() {
        if (canvas == nil) return 0;
        if (canvas.Window == nil) return 0;
        return 1;
    },

    show: func() {
        if (HUD._shown) return 1;
        if (HUD.available() == 0) { Utils.logWarn("HUD: canvas unavailable"); return 0; }
        var W = HUD._W; var H = HUD._H;
        var c = nil;
        c = canvas.new({
            "name": "ATCAI-radar",
            "size": [W, H],
            "view": [W, H],
        });
        if (c == nil) { Utils.logWarn("HUD: canvas.new failed"); return 0; }
        c.set("background", "#0b1014");
        HUD._canvas = c;
        HUD._root = c.createGroup();
        if (HUD._root == nil) { Utils.logWarn("HUD: createGroup failed"); return 0; }
        HUD._grp = HUD._root.createGroup();

        var win = canvas.Window.new([W + 8, H + 8], "ATCAI Traffic Radar");
        if (win == nil) { Utils.logWarn("HUD: Window.new failed"); return 0; }
        win.setCanvas(c);
        HUD._window = win;
        win.show();
        HUD._shown = 1;
        Sounds.play('ui-click');
        return 1;
    },

    hide: func() {
        HUD._shown = 0;
        if (HUD._window != nil) { HUD._window.hide(); }
    },

    toggle: func() {
        if (HUD._shown) { HUD.hide(); return 0; }
        return HUD.show();
    },

    destroy: func() {
        if (HUD._window != nil) { HUD._window.del(); HUD._window = nil; }
        if (HUD._canvas != nil) { HUD._canvas.del(); HUD._canvas = nil; }
        HUD._root = nil; HUD._grp = nil; HUD._shown = 0;
    },

    # col is a numeric [r,g,b] vector (0..1)
    _txt: func(x, y, str, size, col) {
        var t = HUD._grp.createChild("text");
        t.setText(str);
        if (size != nil) t.setFontSize(size, 1.0);
        if (col != nil)
            t.setColor(col[0], col[1], col[2]);
        t.setTranslation(x, y);
        return t;
    },

    _ring: func(cx, cy, r, color, width) {
        var p = HUD._grp.createChild("path");
        p.set("stroke", color);
        p.set("stroke-width", width);
        p.addCircle(cx, cy, r, 0);
        return p;
    },

    _blip: func(cx, cy, r, fill, stroke) {
        var p = HUD._grp.createChild("path");
        p.set("fill", fill);
        p.set("stroke", stroke);
        p.set("stroke-width", 1);
        p.addCircle(cx, cy, r, 0);
        return p;
    },

    # polyline through a vector of [x,y] points
    _poly: func(pts, color, width) {
        if (pts == nil or size(pts) < 2) return nil;
        var p = HUD._grp.createChild("path");
        p.set("stroke", color);
        p.set("stroke-width", width);
        var first = pts[0];
        p.moveTo(first[0], first[1]);
        for (var i = 1; i < size(pts); i += 1)
            p.lineTo(pts[i][0], pts[i][1]);
        return p;
    },

    _colorFor: func(cat) {
        if (cat == 'heavy_jet') return "#ff8a4c";
        if (cat == 'jet') return "#9fe0ff";
        if (cat == 'turboprop' or cat == 'twin_prop') return "#bff58a";
        if (cat == 'piston') return "#fff88a";
        if (cat == 'helicopter') return "#ff9ae0";
        if (cat == 'military') return "#ff5a5a";
        return "#dddddd";
    },

    refresh: func(tm) {
        if (HUD._shown == 0 or HUD._grp == nil or tm == nil) return;
        HUD._grp.removeChildren();

        var W = HUD._W; var H = HUD._H;
        var cx = W / 2; var cy = H / 2 + 12;
        var range = Config.getInt('radius-nm'); if (range < 15) range = 40; if (range > 60) range = 60;
        var scale = (H / 2 - 46) / range;

        var st = ATC.status();
        var p = nil;
        if (st != nil and st.pos != nil) p = st.pos;
        if (p == nil) p = Utils.acPos();

        # project a lat/lon to radar pixels
        var proj = func(la, lo) {
            if (p == nil) return nil;
            var d = Utils.distNm(p.lat, p.lon, la, lo);
            var b = Utils.bearingDeg(p.lat, p.lon, la, lo);
            var rad = b * 0.017453292519943295;
            return [cx + d * math.sin(rad) * scale, cy - d * math.cos(rad) * scale, d];
        };

        # range rings + cardinal labels
        HUD._ring(cx, cy, scale * range / 3.0, "#12331c", 1.0);
        HUD._ring(cx, cy, scale * range * 2 / 3.0, "#12331c", 1.0);
        HUD._ring(cx, cy, scale * range, "#1d6b33", 1.5);
        HUD._txt(cx + 5, cy - 12, "N", 14, [0.49, 1.0, 0.63]);
        HUD._txt(cx + 5, cy + H / 2 - 34, "S", 14, [0.49, 1.0, 0.63]);
        HUD._txt(cx - 18, cy - 6, "W", 14, [0.49, 1.0, 0.63]);
        HUD._txt(cx + scale * range + 4, cy - 6, "E " ~ range ~ "nm", 12, [0.49, 1.0, 0.63]);

        # active runway strip + approach centreline + procedure track
        if (st != nil and st.active != nil and st.active.lat != nil) {
            var r = st.active;
            var lenNm = (r.lengthM == nil ? 0.6 : (r.lengthM / 1852.0));
            var farApp = Utils.destLatLon(r.lat, r.lon, r.heading + 180.0, range * 0.9);
            var farRwy = Utils.destLatLon(r.lat, r.lon, r.heading, lenNm);
            var thr = proj(r.lat, r.lon);
            var ap = proj(farApp.lat, farApp.lon);
            var fe = proj(farRwy.lat, farRwy.lon);
            if (thr != nil and ap != nil) HUD._poly([ap, thr], "#1d6b33", 1.5);
            if (thr != nil and fe != nil) HUD._poly([thr, fe], "#2f7fd0", 2.5);
            if (thr != nil) HUD._txt(thr[0] + 7, thr[1] + 6, r.id, 11, [0.4, 0.8, 1.0]);
        }
        if (st != nil and st.apprPath != nil) {
            var pts = [];
            foreach (var fx; st.apprPath) {
                var pr = proj(fx.lat, fx.lon);
                if (pr != nil) append(pts, [pr[0], pr[1]]);
            }
            HUD._poly(pts, "#7aa2ff", 1.0);
        }

        # user aircraft at center (triangle pointing up)
        var up = HUD._grp.createChild("path");
        up.set("fill", "#ffffff");
        up.set("stroke", "#000000");
        up.moveTo(cx, cy - 9);
        up.lineTo(cx - 6, cy + 7);
        up.lineTo(cx + 6, cy + 7);
        up.close();

        # traffic blips
        var list = tm.getAircraft();
        foreach (var ac; list) {
            if (ac == nil) continue;
            var s = ac.getState(); if (s == nil) continue;
            var d = ac.distToUser();
            var b = ac.bearingFromUser();
            if (d == nil or b == nil) continue;
            var dx = d * math.sin(b * 0.017453292519943295);
            var dy = d * math.cos(b * 0.017453292519943295);
            var px = cx + dx * scale;
            var py = cy - dy * scale;
            if (px < 0 or px > W or py < 0 or py > 60) continue;
            HUD._blip(px, py, 5.0, HUD._colorFor(s.category), "#000000");
            if (d < range * 0.7)
                HUD._txt(px + 8, py - 4, s.callsign ~ " " ~ (math.round(s.altFt / 100) * 100), 10, [0.81, 0.91, 0.84]);
        }

        # header + frequencies + advisories
        var okt = (Config.getBool('upgrade.enabled')) ? "on" : "off";
        HUD._txt(12, 15, "ATCAI  " ~ tm.getSource() ~ "   upgrade:" ~ okt ~
                 "   in range:" ~ ((st != nil) ? st.count : 0), 14, [0.62, 0.88, 1.0]);
        if (st != nil) {
            var rwyTxt = (st.active != nil) ? st.active.id : "----";
            var aptLine = (st.aptId == "") ? "no airport nearby" : (st.aptId ~ "  active rwy " ~ rwyTxt);
            var f = st.freqs;
            if (f != nil) {
                var ftxt = "";
                if (f.tower != nil) ftxt = ftxt ~ "TWR " ~ f.tower ~ "  ";
                if (f.ground != nil) ftxt = ftxt ~ "GND " ~ f.ground ~ "  ";
                if (f.approach != nil) ftxt = ftxt ~ "APP " ~ f.approach;
                if (ftxt != "") aptLine = aptLine ~ "   " ~ ftxt;
            }
            HUD._txt(12, 33, aptLine, 12, [0.55, 0.9, 0.75]);
        }
        if (st != nil and st.log != nil) {
            var yy = 52;
            foreach (var line; st.log) {
                if (yy > H - 44) break;
                HUD._txt(12, yy, line, 11, [1.0, 0.81, 0.42]);
                yy += 14;
            }
        }
        HUD._txt(12, H - 12, "Tools > ATC-AI-Traffic: source | upgrade | radar | sound", 10, [0.33, 0.48, 0.39]);
    },
};
