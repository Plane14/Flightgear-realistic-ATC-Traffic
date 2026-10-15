#=== atc-ai-traffic : AI aircraft entity ================================
# One shared namespace symbol: AIAircraft. Peers (Config, Utils, Models,
# Sounds, JSON) reached by bare name at call time.
#
# Two construction modes:
#   * spawn()  - create a brand-new interactive AI aircraft from scratch
#                (a /models/model[i] visual bound to a /ai/models/aircraft[i]
#                controller) and drive it through controls/flight/*.
#   * attach() - bind to an aircraft[*] already created by FlightGear's own
#                traffic manager so we can read its state (for sound/ATC).
#
# High index bases (/models/model[128+], /ai/models/aircraft[128+]) keep our
# spawned objects clear of the low indices the built-in traffic manager uses.
# Every Property Tree reach is guarded; a failure yields nil, never a throw.
#=======================================================================

var AIAircraft = {

    _MODEL_BASE: 128,
    _AI_BASE: 128,

    # static: safe double read -> 0.0 when node/child absent.
    _d: func(node, path) {
        if (node == nil)
            return 0.0;
        var x = node.getNode(path, 0);
        if (x == nil)
            return 0.0;
        return x.getDoubleValue();
    },

    # static: node string read -> "" when absent.
    _s: func(node, path) {
        if (node == nil)
            return "";
        var x = node.getNode(path, 0);
        if (x == nil)
            return "";
        var v = x.getValue();
        if (v == nil)
            return "";
        return v ~ "";
    },

    new: func(o) {
        if (o == nil) o = {};
        var me = { parents: [AIAircraft] };
        me.callsign = (o.callsign != nil) ? (o.callsign ~ "") : "AI000";
        me.hex = (o.hex != nil) ? (o.hex ~ "") : "";
        me.category = (o.category != nil) ? (o.category ~ "") : "unknown";
        me.perfClass = (o.perfClass != nil) ? (o.perfClass ~ "") : "jet_transport";
        me.modelPath = o.modelPath;            # may be nil -> picked at spawn
        me.lat = o.lat or 0;
        me.lon = o.lon or 0;
        me.altFt = o.altFt or 0;
        me.hdg = o.hdg or 0;
        me.spdKt = o.spd or 0;
        me.aiIndex = nil;
        me.modelIndex = nil;
        me.node = nil;                         # /ai/models/aircraft[i] logic
        me.mnode = nil;                        # /models/model[i] visual
        me.owned = 0;                          # 1 when we control it
        me.phase = (o.phase != nil) ? (o.phase ~ "") : "cruise";
        me.airline = (o.airline != nil) ? (o.airline ~ "") : "";
        me.registration = (o.registration != nil) ? (o.registration ~ "") : "";
        me._lastAltFt = me.altFt;
        me._lastT = 0.0;
        me.vsFpm = 0.0;
        return me;
    },

    # ---- construction ----------------------------------------------------
    spawn: func() {
        var mp = me.modelPath;
        if (mp == nil or mp == "")
            mp = Models.pickModelPath(me.category);
        me.modelPath = mp;

        var aiRoot = props.globals.getNode("ai/models", 1);
        if (aiRoot == nil) return 0;
        var ai = AIAircraft._AI_BASE;
        while (aiRoot.getChild("aircraft", ai, 0) != nil) ai += 1;
        var ain = aiRoot.getChild("aircraft", ai, 1);
        if (ain == nil) { me.node = nil; return 0; }
        me.aiIndex = ai;
        me.node = ain;

        ain.getNode("valid", 1).setBoolValue(1);
        ain.getNode("callsign", 1).setValue(me.callsign);
        if (me.perfClass != "") ain.getNode("class", 1).setValue(me.perfClass);
        ain.getNode("position/latitude-deg", 1).setDoubleValue(me.lat);
        ain.getNode("position/longitude-deg", 1).setDoubleValue(me.lon);
        ain.getNode("position/altitude-ft", 1).setDoubleValue(me.altFt);
        ain.getNode("orientation/true-heading-deg", 1).setDoubleValue(me.hdg);
        ain.getNode("orientation/pitch-deg", 1).setDoubleValue(0);
        ain.getNode("orientation/roll-deg", 1).setDoubleValue(0);
        ain.getNode("velocities/true-airspeed-kt", 1).setDoubleValue(me.spdKt);
        ain.getNode("velocities/vertical-speed-fps", 1).setDoubleValue(0);

        var cf = ain.getNode("controls/flight", 1);
        cf.getNode("lateral-mode", 1).setValue("hdg");
        cf.getNode("vertical-mode", 1).setValue("alt");
        cf.getNode("target-hdg", 1).setDoubleValue(me.hdg);
        cf.getNode("target-alt", 1).setDoubleValue(me.altFt);
        cf.getNode("target-spd", 1).setDoubleValue(me.spdKt);

        var mRoot = props.globals.getNode("models", 1);
        if (mRoot != nil) {
            var mi = AIAircraft._MODEL_BASE;
            while (mRoot.getChild("model", mi, 0) != nil) mi += 1;
            me.modelIndex = mi;
            var mn = mRoot.getChild("model", mi, 1);
            if (mn != nil) {
                me.mnode = mn;
                mn.getNode("path", 1).setValue(mp);
                mn.getNode("latitude-deg-prop", 1).setValue(ain.getNode("position/latitude-deg", 0).getPath());
                mn.getNode("longitude-deg-prop", 1).setValue(ain.getNode("position/longitude-deg", 0).getPath());
                mn.getNode("elevation-ft-prop", 1).setValue(ain.getNode("position/altitude-ft", 0).getPath());
                mn.getNode("heading-deg-prop", 1).setValue(ain.getNode("orientation/true-heading-deg", 0).getPath());
                mn.getNode("pitch-deg-prop", 1).setValue(ain.getNode("orientation/pitch-deg", 0).getPath());
                mn.getNode("roll-deg-prop", 1).setValue(ain.getNode("orientation/roll-deg", 0).getPath());
                mn.getNode("load", 1).remove();
            }
        }
        me.owned = 1;
        Config.dbg("spawned " ~ me.callsign ~ " ai=" ~ ai ~ " model=" ~ mp);
        return 1;
    },

    # Bind to an existing /ai/models/aircraft[idx] (owned by FG traffic mgr).
    attach: func(idx) {
        var ain = props.globals.getNode("ai/models/aircraft[" ~ idx ~ "]", 0);
        if (ain == nil) return 0;
        me.node = ain;
        me.aiIndex = idx;
        me.owned = 0;
        var cs = ain.getNode("callsign", 0);
        if (cs != nil and cs.getValue() != nil) me.callsign = cs.getValue() ~ "";
        return 1;
    },

    # ---- state -----------------------------------------------------------
    getState: func() {
        if (me.node == nil) return nil;
        var n = me.node;
        var s = {};
        s.callsign = me.callsign;
        s.hex = me.hex;
        s.category = me.category;
        s.airline = me.airline;
        s.registration = me.registration;
        s.phase = me.phase;
        s.lat = AIAircraft._d(n, "position/latitude-deg");
        s.lon = AIAircraft._d(n, "position/longitude-deg");
        s.altFt = AIAircraft._d(n, "position/altitude-ft");
        s.hdg = AIAircraft._d(n, "orientation/true-heading-deg");
        s.spd = AIAircraft._d(n, "velocities/true-airspeed-kt");
        s.vsFpm = AIAircraft._d(n, "velocities/vertical-speed-fps") * 60.0;
        # live target for display
        s.tAlt = AIAircraft._d(n, "controls/flight/target-alt");
        s.tSpd = AIAircraft._d(n, "controls/flight/target-spd");
        s.tHdg = AIAircraft._d(n, "controls/flight/target-hdg");
        return s;
    },

    # ---- control (any aircraft we choose to guide) ----------------------
    update: func(st) {
        if (me.node == nil) return;
        if (st != nil) {
            var cf = me.node.getNode("controls/flight", 1);
            if (cf != nil) {
                # steer in hdg/alt modes for realistic air-traffic guidance
                if (st.targetHdg != nil) cf.getNode("lateral-mode", 1).setValue("hdg");
                if (st.targetAlt != nil) cf.getNode("vertical-mode", 1).setValue("alt");
                if (st.targetHdg != nil)
                    cf.getNode("target-hdg", 1).setDoubleValue(Utils.normdeg(st.targetHdg));
                if (st.targetAlt != nil)
                    cf.getNode("target-alt", 1).setDoubleValue(st.targetAlt);
                if (st.targetSpd != nil)
                    cf.getNode("target-spd", 1).setDoubleValue(st.targetSpd);
            }
            if (st.phase != nil) me.phase = st.phase ~ "";
        }
        # vertical-speed estimate from altitude change over wall-ish dt
        var n = me.node;
        var alt = AIAircraft._d(n, "position/altitude-ft");
        var t = getprop("/sim/time/elapsed-sec") or 0;
        if (me._lastT > 0 and t > me._lastT) {
            var d = (alt - me._lastAltFt) / (t - me._lastT) * 60.0;
            me.vsFpm = d;
        }
        me._lastAltFt = alt;
        me._lastT = t;
    },

    # ---- relative geometry to the user -----------------------------------
    distToUser: func() {
        var p = Utils.acPos();
        var s = me.getState();
        if (p == nil or s == nil) return nil;
        return Utils.distNm(p.lat, p.lon, s.lat, s.lon);
    },

    bearingFromUser: func() {
        var p = Utils.acPos();
        var s = me.getState();
        if (p == nil or s == nil) return nil;
        return Utils.bearingDeg(p.lat, p.lon, s.lat, s.lon);
    },

    remove: func() {
        if (me.mnode != nil) { me.mnode.remove(); me.mnode = nil; }
        if (me.node != nil) { me.node.remove(); me.node = nil; }
        me.owned = 0;
    },
};
