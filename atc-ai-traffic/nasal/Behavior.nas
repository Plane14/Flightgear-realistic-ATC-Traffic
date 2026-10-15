#=== atc-ai-traffic : realistic flight behavior profiles ==================
# One shared namespace symbol: Behavior. Stateless helpers the
# TrafficManager uses to pick realistic target headings / altitudes / speeds
# per aircraft category and phase. The AI FDM (driven by attack
# controls/flight/target-*) does the actual turn / climb dynamics; here we
# only choose sane TARGET numbers, which is what makes the motion realistic.
# Peer Utils reached by bare name at call time.
#=======================================================================

var Behavior = {

    category: {
        HEAVY:  "heavy_jet",
        JET:    "jet",
        TURB:   "turboprop",
        PISTON: "piston",
        HELI:   "helicopter",
        MIL:    "military",
    },

    cruiseSpeed: func(cat) {
        if (cat == 'heavy_jet') return 470;
        if (cat == 'jet') return 440;
        if (cat == 'military') return 450;
        if (cat == 'turboprop' or cat == 'twin_prop') return 270;
        if (cat == 'piston') return 115;
        if (cat == 'helicopter') return 120;
        return 200;
    },

    approachSpeed: func(cat) {
        if (cat == 'heavy_jet') return 150;
        if (cat == 'jet') return 145;
        if (cat == 'military') return 150;
        if (cat == 'turboprop' or cat == 'twin_prop') return 110;
        if (cat == 'piston') return 70;
        if (cat == 'helicopter') return 70;
        return 120;
    },

    climbRate: func(cat) {
        if (cat == 'heavy_jet') return 2600;
        if (cat == 'jet' or cat == 'military') return 2800;
        if (cat == 'turboprop' or cat == 'twin_prop') return 1800;
        if (cat == 'piston') return 700;
        if (cat == 'helicopter') return 500;
        return 1500;
    },

    descentRate: func(cat) {
        if (cat == 'heavy_jet') return 2200;
        if (cat == 'jet' or cat == 'military') return 2000;
        if (cat == 'turboprop' or cat == 'twin_prop') return 1500;
        return 1200;
    },

    ceilingFt: func(cat) {
        if (cat == 'heavy_jet') return 41000;
        if (cat == 'jet' or cat == 'military') return 39000;
        if (cat == 'turboprop' or cat == 'twin_prop') return 25000;
        if (cat == 'piston') return 14000;
        if (cat == 'helicopter') return 10000;
        return 12000;
    },

    # ---------------------------------------------------------------------
    # 3-degree (or gsDeg) glideslope altitude above a threshold elevation:
    #   alt = fieldElev + distance * tan(gsDeg) * 6076.11549  (ft per nm ~318)
    # ---------------------------------------------------------------------
    glideslopeAltFt: func(fieldElevFt, distToTouchNm, gsDeg) {
        if (gsDeg == nil) gsDeg = 3.0;
        var tan = math.tan(gsDeg * Utils.RAD);
        var a = (fieldElevFt or 0) + distToTouchNm * tan * 6076.11549;
        if (a < 0) a = 0;
        return a;
    },

    # Desired altitude for a phase. 'approach' follows the glideslope; 'cruise'
    # holds the cruise FL; 'climb'/'depart' blend toward cruise ceiling.
    targetAltFt: func(cat, phase, distToDestNm, destAltFt) {
        var cruise = Behavior.cruiseFlToFt(Config.getInt('cruise-fl'));
        if (phase == 'cruise') return cruise;
        if (phase == 'approach') {
            if (distToDestNm == nil) distToDestNm = 0;
            return Behavior.glideslopeAltFt(destAltFt, distToDestNm, 3.0);
        }
        if (phase == 'depart' or phase == 'climb') return cruise;
        return cruise;
    },

    targetSpd: func(cat, phase) {
        if (phase == 'approach') return Behavior.approachSpeed(cat);
        if (phase == 'depart' or phase == 'climb') return Behavior.approachSpeed(cat) * 1.2;
        return Behavior.cruiseSpeed(cat);
    },

    cruiseFlToFt: func(fl) {
        if (fl == nil) fl = 180;
        return fl * 100.0;
    },

    # Steer heading to a destination coordinate.
    hdgTo: func(fromLat, fromLon, toLat, toLon) {
        return Utils.bearingDeg(fromLat, fromLon, toLat, toLon);
    },

    # Limit a heading change so we never command an unphysical instant turn;
    # the AI FDM already smooths turns but bounding targets keeps it tidy.
    turnToward: func(curHdg, wantHdg, maxDelta) {
        var cur = Utils.normdeg(curHdg);
        var want = Utils.normdeg(wantHdg);
        var diff = want - cur;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        if (diff > maxDelta) diff = maxDelta;
        if (diff < -maxDelta) diff = -maxDelta;
        return Utils.normdeg(cur + diff);
    },
};
