#=== atc-ai-traffic : minimal JSON parser ===============================
# One shared namespace symbol: JSON. Used by the adsb.lol live-traffic
# source to decode the API response (an array of flat objects). Recursive
# descent with a shared cursor in module vars _s / _i. No regex, no
# try/catch: malformed input simply yields nil. parse() is the important
# one; encode() is a small best-effort helper (booleans are not
# distinguishable from ints in Nasal, so 1/0 encode as true/false).
#=======================================================================

var JSON = {

    _s: "",
    _i: 0,
    _skip: " \t\n\r",

    parse: func(str) {
        if (str == nil)
            return nil;
        JSON._s = str ~ "";
        JSON._i = 0;
        JSON._ws();
        var v = JSON._val();
        return v;
    },

    _len: func() {
        return Utils.strLen(JSON._s);
    },

    _ws: func() {
        var n = JSON._len();
        while (JSON._i < n) {
            var c = substr(JSON._s, JSON._i, 1);
            if (string.index(JSON._skip, c) != nil)
                JSON._i += 1;
            else
                break;
        }
    },

    _peek: func() {
        return substr(JSON._s, JSON._i, 1);
    },

    _val: func() {
        JSON._ws();
        var c = substr(JSON._s, JSON._i, 1);
        if (c == "{") return JSON._obj();
        if (c == "[") return JSON._arr();
        if (c == '"') return JSON._str();
        if (c == "t") return JSON._litTrue();
        if (c == "f") return JSON._litFalse();
        if (c == "n") return JSON._litNull();
        if (c == "-") return JSON._num();
        if (string.index("0123456789", c) != nil) return JSON._num();
        return nil;
    },

    _litTrue: func() {
        if (substr(JSON._s, JSON._i, 4) == "true") { JSON._i += 4; return 1; }
        return nil;
    },

    _litFalse: func() {
        if (substr(JSON._s, JSON._i, 5) == "false") { JSON._i += 5; return 0; }
        return nil;
    },

    _litNull: func() {
        if (substr(JSON._s, JSON._i, 4) == "null") { JSON._i += 4; return nil; }
        return nil;
    },

    _num: func() {
        var start = JSON._i;
        var n = JSON._len();
        while (JSON._i < n) {
            var c = substr(JSON._s, JSON._i, 1);
            if (c == "")
                break;
            if (string.index("-+0123456789.eE", c) != nil)
                JSON._i += 1;
            else
                break;
        }
        var s = substr(JSON._s, start, JSON._i - start);
        if (s == "" or s == "-" or s == "+" or s == ".")
            return nil;
        return s + 0.0;
    },

    _str: func() {
        JSON._i += 1;               # skip opening quote
        var out = "";
        var n = JSON._len();
        while (JSON._i < n) {
            var c = substr(JSON._s, JSON._i, 1);
            if (c == '"') { JSON._i += 1; return out; }
            if (c == "\\") {
                var e = substr(JSON._s, JSON._i + 1, 1);
                JSON._i += 2;
                if (e == "n") out = out ~ "\n";
                elsif (e == "t") out = out ~ "\t";
                elsif (e == "r") out = out ~ "\r";
                elsif (e == "/") out = out ~ "/";
                elsif (e == "b") out = out ~ " ";
                elsif (e == "u") { JSON._i += 4; out = out ~ "?"; }
                elsif (e == "") break;
                else out = out ~ e;
            } else {
                out = out ~ c;
                JSON._i += 1;
            }
        }
        return out;
    },

    _arr: func() {
        JSON._i += 1;               # skip '['
        var v = [];
        JSON._ws();
        if (JSON._peek() == "]") { JSON._i += 1; return v; }
        while (1) {
            append(v, JSON._val());
            JSON._ws();
            var c = substr(JSON._s, JSON._i, 1);
            if (c == ",") { JSON._i += 1; continue; }
            if (c == "]") { JSON._i += 1; break; }
            break;                  # malformed - stop leniently
        }
        return v;
    },

    _obj: func() {
        JSON._i += 1;               # skip '{'
        var h = {};
        JSON._ws();
        if (JSON._peek() == "}") { JSON._i += 1; return h; }
        while (1) {
            JSON._ws();
            var key = JSON._str();
            if (key == nil) break;
            JSON._ws();
            if (JSON._peek() == ":") JSON._i += 1;
            var val = JSON._val();
            h[key] = val;
            JSON._ws();
            var c = substr(JSON._s, JSON._i, 1);
            if (c == ",") { JSON._i += 1; continue; }
            if (c == "}") { JSON._i += 1; break; }
            break;                  # malformed - stop leniently
        }
        return h;
    },

    # Best-effort encoder: nil->null, 1->true, 0->false, else stringify.
    encode: func(val) {
        if (val == nil)
            return "null";
        if (val == 1)
            return "true";
        if (val == 0)
            return "false";
        return val ~ "";
    },
};
