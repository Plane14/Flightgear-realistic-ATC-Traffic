#=== atc-ai-traffic : aircraft model resolution module ==================
# One shared namespace symbol: Models. Peers (Config, Utils, ...) and this
# module itself are reached by bare name at call time.
#
# MODEL PATHS are RELATIVE TO $FG_ROOT (e.g. "AI/Aircraft/738/738-Default.xml"),
# never to the addon base. A wrong/nonexistent path does not crash FlightGear;
# the object is simply not rendered. The ordered _fallbacks chain guarantees a
# non-empty path is always returned.
#
# Core Nasal constraints honoured here: no string.match/regex (use string.index
# / substr); membership tested with contains(); keys()/size()/string.uc/
# string.trim only. Every external reach is nil-guarded. pickModelPath()
# therefore NEVER returns nil or "".
#========================================================================

var Models = {

    # ICAO type designator (UPPERCASE) -> model path relative to $FG_ROOT.
    # 147 entries across airliners, regional jets, turboprops, GA/twin,
    # helicopters and military/special airframes.
    table: {
        # ---- airliners ----
        'A319': 'AI/Aircraft/A320/A320-Default.xml',
        'A320': 'AI/Aircraft/A320/A320-Default.xml',
        'A321': 'AI/Aircraft/A320/A320-Default.xml',
        'A20N': 'AI/Aircraft/A320/A320-Default.xml',
        'A21N': 'AI/Aircraft/A320/A320-Default.xml',
        'B733': 'AI/Aircraft/737/737-Default.xml',
        'B734': 'AI/Aircraft/737/737-Default.xml',
        'B735': 'AI/Aircraft/737/737-Default.xml',
        'B736': 'AI/Aircraft/737/737-Default.xml',
        'B737': 'AI/Aircraft/737/737-Default.xml',
        'B738': 'AI/Aircraft/738/738-Default.xml',
        'B739': 'AI/Aircraft/737/737-Default.xml',
        'B38M': 'AI/Aircraft/737/737-MAX8-Default.xml',
        'B742': 'AI/Aircraft/747/747-Default.xml',
        'B743': 'AI/Aircraft/747/747-Default.xml',
        'B744': 'AI/Aircraft/747/747-Default.xml',
        'B748': 'AI/Aircraft/747/747-Default.xml',
        'B752': 'AI/Aircraft/757/757-Default.xml',
        'B753': 'AI/Aircraft/757/757-Default.xml',
        'B762': 'AI/Aircraft/767/767-Default.xml',
        'B763': 'AI/Aircraft/767/767-Default.xml',
        'B764': 'AI/Aircraft/767/767-Default.xml',
        'B772': 'AI/Aircraft/777/777-200-Default.xml',
        'B773': 'AI/Aircraft/777/777-300-Default.xml',
        'B77L': 'AI/Aircraft/777/777-300ER-Default.xml',
        'B77W': 'AI/Aircraft/777/777-300ER-Default.xml',
        'B788': 'AI/Aircraft/787/787-8-Default.xml',
        'B789': 'AI/Aircraft/787/787-9-Default.xml',
        'B78X': 'AI/Aircraft/787/787-10-Default.xml',
        'A332': 'AI/Aircraft/A330/A330-200-Default.xml',
        'A333': 'AI/Aircraft/A330/A330-300-Default.xml',
        'A339': 'AI/Aircraft/A330/A330-900neo-Default.xml',
        'A342': 'AI/Aircraft/A340/A340-200-Default.xml',
        'A343': 'AI/Aircraft/A340/A340-300-Default.xml',
        'A345': 'AI/Aircraft/A340/A340-500-Default.xml',
        'A346': 'AI/Aircraft/A340/A340-600-Default.xml',
        'A359': 'AI/Aircraft/A350/A350-900-Default.xml',
        'A35K': 'AI/Aircraft/A350/A350-1000-Default.xml',
        'MD11': 'AI/Aircraft/MD11/MD11-Default.xml',
        'MD82': 'AI/Aircraft/MD80/MD80-Default.xml',
        'MD83': 'AI/Aircraft/MD80/MD80-Default.xml',
        'MD88': 'AI/Aircraft/MD80/MD80-Default.xml',
        'MD90': 'AI/Aircraft/MD90/MD90-Default.xml',
        '717' : 'AI/Aircraft/717/717-Default.xml',
        # ---- regional jets ----
        'E135': 'AI/Aircraft/ERJ135/ERJ135-Default.xml',
        'E145': 'AI/Aircraft/ERJ145/ERJ145-Default.xml',
        'E170': 'AI/Aircraft/ERJ170/ERJ170-Default.xml',
        'E175': 'AI/Aircraft/ERJ175/ERJ175-Default.xml',
        'E190': 'AI/Aircraft/ERJ190/ERJ190-Default.xml',
        'E195': 'AI/Aircraft/ERJ195/ERJ195-Default.xml',
        'CRJ1': 'AI/Aircraft/CRJ100/CRJ100-Default.xml',
        'CRJ2': 'AI/Aircraft/CRJ200/CRJ200-Default.xml',
        'CRJ7': 'AI/Aircraft/CRJ700/CRJ700-Default.xml',
        'CRJ9': 'AI/Aircraft/CRJ900/CRJ900-Default.xml',
        'CRJX': 'AI/Aircraft/CRJ1000/CRJ1000-Default.xml',
        # ---- turboprops ----
        'AT43': 'AI/Aircraft/ATR42/ATR42-Default.xml',
        'AT44': 'AI/Aircraft/ATR42/ATR42-Default.xml',
        'AT45': 'AI/Aircraft/ATR42/ATR42-Default.xml',
        'AT72': 'AI/Aircraft/ATR72/ATR72-Default.xml',
        'AT75': 'AI/Aircraft/ATR72/ATR72-Default.xml',
        'AT76': 'AI/Aircraft/ATR72/ATR72-Default.xml',
        'DH8A': 'AI/Aircraft/Dash8/Dash8-Default.xml',
        'DH8B': 'AI/Aircraft/Dash8/Dash8-Default.xml',
        'DH8C': 'AI/Aircraft/Dash8/Dash8-Default.xml',
        'DH8D': 'AI/Aircraft/Dash8/Dash8-Default.xml',
        'SF34': 'AI/Aircraft/Saab340/Saab340-Default.xml',
        'DHC6': 'AI/Aircraft/DHC6/DHC6-Default.xml',
        'JS31': 'AI/Aircraft/Jetstream/Jetstream-Default.xml',
        'JS32': 'AI/Aircraft/Jetstream/Jetstream-Default.xml',
        'JS41': 'AI/Aircraft/Jetstream/Jetstream-Default.xml',
        'AN24': 'AI/Aircraft/AN24/AN24-Default.xml',
        'AN26': 'AI/Aircraft/AN24/AN24-Default.xml',
        'C130': 'AI/Aircraft/C130/C130-Default.xml',
        'BE20': 'AI/Aircraft/Kingair/Kingair-Default.xml',
        'BE30': 'AI/Aircraft/Kingair/Kingair-Default.xml',
        'BE99': 'AI/Aircraft/Beech99/Beech99-Default.xml',
        'PC12': 'AI/Aircraft/PilatusPC12/PC12-Default.xml',
        'TBM7': 'AI/Aircraft/TBM850/TBM850-Default.xml',
        'TBM8': 'AI/Aircraft/TBM850/TBM850-Default.xml',
        'C208': 'AI/Aircraft/C208/C208-Default.xml',
        'D328': 'AI/Aircraft/D328/D328-Default.xml',
        # ---- GA / twin ----
        'C150': 'AI/Aircraft/C150/C150-Default.xml',
        'C152': 'AI/Aircraft/C152/C152-Default.xml',
        'C172': 'AI/Aircraft/c172/c-fgfs.xml',
        'C182': 'AI/Aircraft/C182/C182-Default.xml',
        'C206': 'AI/Aircraft/C206/C206-Default.xml',
        'PA28': 'AI/Aircraft/PA28/PA28-Default.xml',
        'PA32': 'AI/Aircraft/PA32/PA32-Default.xml',
        'PA34': 'AI/Aircraft/PA34/PA34-Default.xml',
        'PA44': 'AI/Aircraft/PA44/PA44-Default.xml',
        'SR20': 'AI/Aircraft/SR20/SR20-Default.xml',
        'SR22': 'AI/Aircraft/SR22/SR22-Default.xml',
        'B350': 'AI/Aircraft/Beech350/Beech350-Default.xml',
        'BE35': 'AI/Aircraft/Bonanza/Bonanza-Default.xml',
        'BE36': 'AI/Aircraft/Bonanza/Bonanza-Default.xml',
        'BE55': 'AI/Aircraft/Baron/Baron-Default.xml',
        'BE58': 'AI/Aircraft/Baron/Baron-Default.xml',
        'DA40': 'AI/Aircraft/DA40/DA40-Default.xml',
        'DA42': 'AI/Aircraft/DA42/DA42-Default.xml',
        'M20P': 'AI/Aircraft/Mooney/Mooney-Default.xml',
        # ---- helicopters ----
        'R22' : 'AI/Aircraft/R22/R22-Default.xml',
        'R44' : 'AI/Aircraft/R44/R44-Default.xml',
        'R66' : 'AI/Aircraft/R66/R66-Default.xml',
        'H60' : 'AI/Aircraft/uh-60/uh-60.xml',
        'EC35': 'AI/Aircraft/EC135/EC135-Default.xml',
        'EC30': 'AI/Aircraft/EC130/EC130-Default.xml',
        'EC45': 'AI/Aircraft/EC145/EC145-Default.xml',
        'AS32': 'AI/Aircraft/AS332/AS332-Default.xml',
        'AS50': 'AI/Aircraft/AS350/AS350-Default.xml',
        'S61' : 'AI/Aircraft/S61/S61-Default.xml',
        'S76' : 'AI/Aircraft/S76/S76-Default.xml',
        'B412': 'AI/Aircraft/Bell412/Bell412-Default.xml',
        'B407': 'AI/Aircraft/Bell407/Bell407-Default.xml',
        'B429': 'AI/Aircraft/Bell429/Bell429-Default.xml',
        'UH1' : 'AI/Aircraft/UH1/UH1-Default.xml',
        'UH60': 'AI/Aircraft/uh-60/uh-60.xml',
        'MI8' : 'AI/Aircraft/Mi8/Mi8-Default.xml',
        # ---- military / tanker / special ----
        'KC10': 'AI/Aircraft/KC10/KC10-Default.xml',
        'KC135': 'AI/Aircraft/KC135/KC135-Default.xml',
        'C17' : 'AI/Aircraft/C17/C17-Default.xml',
        'C5M' : 'AI/Aircraft/C5/C5-Default.xml',
        'B1'  : 'AI/Aircraft/B1/B1-Default.xml',
        'B2'  : 'AI/Aircraft/B2/B2-Default.xml',
        'B52' : 'AI/Aircraft/B52/B52-Default.xml',
        'F15' : 'AI/Aircraft/F15/F15-Default.xml',
        'F16' : 'AI/Aircraft/F16/F16-Default.xml',
        'F18' : 'AI/Aircraft/F18/F18-Default.xml',
        'FA18': 'AI/Aircraft/F18/F18-Default.xml',
        'EUFI': 'AI/Aircraft/Eurofighter/Eurofighter-Default.xml',
        'SU27': 'AI/Aircraft/Su27/Su27-Default.xml',
        'SU30': 'AI/Aircraft/Su30/Su30-Default.xml',
        'SU35': 'AI/Aircraft/Su35/Su35-Default.xml',
        'MIG29': 'AI/Aircraft/MiG29/MiG29-Default.xml',
        'MIG31': 'AI/Aircraft/MiG31/MiG31-Default.xml',
        'T38' : 'AI/Aircraft/T38/T38-Default.xml',
        'V22' : 'AI/Aircraft/V22/V22-Default.xml',
        'P3'  : 'AI/Aircraft/P3/P3-Default.xml',
        'E2'  : 'AI/Aircraft/E2/E2-Default.xml',
        'E3'  : 'AI/Aircraft/B707/B707-Default.xml',
        'GLF6': 'AI/Aircraft/Gulfstream/Gulfstream-Default.xml',
        'CL60': 'AI/Aircraft/Challenger/Challenger-Default.xml',
        'F2TH': 'AI/Aircraft/Falcon/Falcon-Default.xml',
        'LJ'  : 'AI/Aircraft/Learjet/Learjet-Default.xml',
        'C25A': 'AI/Aircraft/Citation/Citation-Default.xml',
        'C25B': 'AI/Aircraft/Citation/Citation-Default.xml',
        'PRM1': 'AI/Aircraft/PilatusPC12/PC12-Default.xml',
        'SW'  : 'AI/Aircraft/Saab340/Saab340-Default.xml'
    },

    # Ordered best-first fallback paths; last item is the neutral generic glider.
    _fallbacks: ['AI/Aircraft/738/738-Default.xml',
                 'AI/Aircraft/A320/A320-Default.xml',
                 'AI/Aircraft/c172/c-fgfs.xml',
                 'Models/Geometry/glider.ac'],

    # Per-category membership sets (hashes, tested with contains()).
    _HEAVY: {'A332':1,'A333':1,'A339':1,'A342':1,'A343':1,'A345':1,'A346':1,
             'A359':1,'A35K':1,'B744':1,'B748':1,'B762':1,'B763':1,'B764':1,
             'B77L':1,'B77W':1,'B772':1,'B773':1,'B788':1,'B789':1,'B78X':1},

    _JET: {'A319':1,'A320':1,'A321':1,'A20N':1,'A21N':1,
           'B733':1,'B734':1,'B735':1,'B736':1,'B737':1,'B738':1,'B739':1,'B38M':1,
           'B752':1,'B753':1,
           'E135':1,'E145':1,'E170':1,'E175':1,'E190':1,'E195':1,
           'CRJ1':1,'CRJ2':1,'CRJ7':1,'CRJ9':1,'CRJX':1,
           'MD11':1,'MD82':1,'MD83':1,'MD88':1,'MD90':1,'717':1,
           'F15':1,'F16':1,'F18':1,'FA18':1,'EUFI':1,'SU27':1,'MIG29':1,
           'C25A':1,'C25B':1},

    _TURBOPROP: {'AT43':1,'AT44':1,'AT45':1,'AT72':1,'AT75':1,'AT76':1,
                 'DH8A':1,'DH8B':1,'DH8C':1,'DH8D':1,'SF34':1,'DHC6':1,
                 'JS31':1,'JS32':1,'JS41':1,'AN24':1,'AN26':1,'C130':1,
                 'BE20':1,'PC12':1,'PRM1':1,'TBM7':1,'TBM8':1,'C208':1,'D328':1},

    _TWINPROP: {'BE35':1,'BE36':1,'BE55':1,'BE58':1,'PA44':1,'PA34':1,
                'DA42':1,'M20P':1,'B350':1},

    _PISTON: {'C150':1,'C152':1,'C172':1,'C182':1,'C206':1,
              'PA28':1,'PA32':1,'SR20':1,'SR22':1,'DA40':1},

    _HELICOPTER: {'R22':1,'R44':1,'R66':1,'H60':1,'H64':1,'EC35':1,'EC30':1,'EC45':1,
                  'AS32':1,'AS50':1,'S61':1,'S76':1,'B412':1,'B407':1,'B429':1,
                  'UH1':1,'UH60':1,'MI8':1},

    _MILITARY: {'KC10':1,'KC135':1,'C17':1,'C5M':1,'B1':1,'B2':1,'B52':1,
                'F15':1,'F16':1,'F18':1,'FA18':1,'EUFI':1,'SU27':1,'SU30':1,
                'SU35':1,'MIG29':1,'MIG31':1,'T38':1,'V22':1,'P3':1,'E2':1,'E3':1},

    _PERF: {'heavy_jet':'heavy','jet':'jet_transport','turboprop':'twin_prop',
            'twin_prop':'twin_prop','piston':'ga','helicopter':'helicopter',
            'military':'jet_transport','unknown':'ga'},

    # True when c is one ASCII digit (no regex).
    _isDigit: func(c) {
        if (c == nil or c == "")
            return 0;
        return (string.index("0123456789", c) != nil);
    },

    # Uppercase + trim; nil-safe.
    prepareIcao: func(icao) {
        if (icao == nil)
            return "";
        return string.uc(string.trim(icao ~ ""));
    },

    # Always returns a non-empty model path string.
    pickModelPath: func(icao) {
        var t = Models.prepareIcao(icao);
        if (t == "")
            return Models._fallbacks[0];
        if (contains(Models.table, t)) {
            var p = Models.table[t];
            if (p != nil and p != "")
                return p;
        }
        # generic family key: first 4 chars, then first 3 chars.
        var k4 = substr(t, 0, 4);
        var k3 = substr(t, 0, 3);
        if (k4 != "" and contains(Models.table, k4)) {
            var p4 = Models.table[k4];
            if (p4 != nil and p4 != "")
                return p4;
        }
        if (k3 != "" and contains(Models.table, k3)) {
            var p3 = Models.table[k3];
            if (p3 != nil and p3 != "")
                return p3;
        }
        var c0 = substr(t, 0, 1);
        if (c0 == 'B' or c0 == 'A')
            return Models._fallbacks[0];
        return Models._fallbacks[size(Models._fallbacks) - 1];
    },

    # One of: heavy_jet jet turboprop twin_prop piston helicopter military unknown.
    categoryFor: func(icao) {
        var t = Models.prepareIcao(icao);
        if (t == "")
            return 'unknown';
        if (contains(Models._HEAVY, t)) return 'heavy_jet';
        if (contains(Models._JET, t)) return 'jet';
        if (contains(Models._TURBOPROP, t)) return 'turboprop';
        if (contains(Models._TWINPROP, t)) return 'twin_prop';
        if (contains(Models._PISTON, t)) return 'piston';
        if (contains(Models._HELICOPTER, t)) return 'helicopter';
        if (contains(Models._MILITARY, t)) return 'military';
        # heuristics (substr only)
        var c0 = substr(t, 0, 1);
        var c1 = substr(t, 1, 1);
        var p2 = substr(t, 0, 2);
        if (c0 == 'H' and Models._isDigit(c1)) return 'helicopter';
        if (p2 == 'UH' or p2 == 'MH') return 'helicopter';
        if (c0 == 'C' and Models._isDigit(c1)) return 'piston';
        if (p2 == 'DH') return 'turboprop';
        return 'unknown';
    },

    # category -> FlightGear AI performance class string.
    performanceClass: func(icao) {
        var c = Models.categoryFor(icao);
        if (contains(Models._PERF, c))
            return Models._PERF[c];
        return 'ga';
    }
};
