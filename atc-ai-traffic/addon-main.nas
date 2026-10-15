#=== atc-ai-traffic : ADDON ENTRY POINT ==================================
# FlightGear loads this addon-main.nas into the namespace
#   __addon[org.flightgear.atcai]__
# and calls main(addon). Here we load every library module into the shared
# namespace "ATCAI", pre-seed the addon base path, and (on first FDM
# initialisation) start the TrafficManager.
#
# Module files reference each other by BARE name (they all share ATCAI), so
# load order is irrelevant as long as every file is loaded before start();
# TrafficManager.update() is the first thing that uses the peers, and it
# only runs after start() which we defer to fdm-initialised.
#=======================================================================

var main = func(addon) {
    # ---- resolve this addon's base directory --------------------------
    var base = nil;
    if (addon != nil) {
        var bp = addon.basePath;
        if (bp != nil)
            base = callable(bp) ? bp() : bp;
    }
    if (base == nil) base = getprop("/addons/by-id/org.flightgear.atcai/path");
    if (base == nil) base = getprop("/sim/fg-root") ~ "/addons/org.flightgear.atcai";

    # ---- module load order (defensive: files must exist) ---------------
    var files = [
        "nasal/Config.nas",
        "nasal/Utils.nas",
        "nasal/JSON.nas",
        "nasal/Models.nas",
        "nasal/Sounds.nas",
        "nasal/AIAircraft.nas",
        "nasal/Behavior.nas",
        "nasal/TrafficParser.nas",
        "nasal/AdsbSource.nas",
        "nasal/Procedures.nas",
        "nasal/ATC.nas",
        "nasal/HUD.nas",
        "nasal/TrafficManager.nas",
    ];

    var ok = 1;
    foreach (var f; files) {
        var path = base ~ "/" ~ f;
        io.load_nasal(path, "ATCAI");
    }

    # ---- pre-seed the addon base so Sounds can resolve its WAV dir ----
    if (ATCAI.Config != nil)
        ATCAI.Config._base = base;

    logprint(2, "[ATCAI] " ~ (ok ? "" : "loaded with issues ") ~
            "modules loaded (base=" ~ base ~ ")\n");

    # ---- start the system on first flight-dynamics init ---------------
    setlistener("sim/signals/fdm-initialized", func() {
        if (ATCAI.TrafficManager != nil) {
            ATCAI.Config.setup();
            ATCAI.TrafficManager.start();
        }
    });
};
