// AIQUIZ online battle "VS" cut-in -- After Effects builder (ExtendScript, ASCII only).
//
// Rebuilds the whole AE project from scratch and saves it as
//   tools/online_cutin_ae/AIQUIZ_VS_Cutin.aep
// Run it inside the RUNNING After Effects (it closes the current project WITHOUT saving):
//   "G:\adobe\Adobe After Effects 2026\Support Files\AfterFX.exe" -r C:\AIQUIZ\AIQUIZ-Godot\tools\online_cutin_ae\build_vs_cutin.jsx
//
// Source of truth for the design: docs/online_match_staging/spec.md (S8 / S9 / S10, 7, 16),
// scripts/ui/online/cutin/online_cutin.gd, shaders/online_cutin_*.gdshader,
// scripts/world/online_staging/online_staging_timeline.gd (CUTIN / SEAM_POINTS / CUTIN_POSES).
// Footage: artifacts/online_cutin_ae/chars/*.png (tests/online_cutin_ae/capture_cutin_chars.gd)
//          artifacts/online_cutin_ae/plates/*.png (placeholder 3D plates)
//
// Errors never reach a modal dialog: everything is wrapped and reported as project folders
// named "_build_log/..." (the project is only saved when the build finished without an exception).

(function () {
    var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
    var AEP = ROOT + "tools/online_cutin_ae/AIQUIZ_VS_Cutin.aep";
    var CHAR_DIR = ROOT + "artifacts/online_cutin_ae/chars/";
    var PLATE_DIR = ROOT + "artifacts/online_cutin_ae/plates/";

    var FPS = 60, W = 1920, H = 1080;
    // Timeline (seconds). IN = CUTIN_IN (0.90 s), HOLD = settle 0.30 s + one seamless 2.40 s loop, REVEAL = 3.20 s.
    var T_HOLD = 0.9, T_LOOP = 1.2, LOOP = 2.4, T_REVEAL = 3.6, REVEAL = 3.2, T_END = T_REVEAL + REVEAL, DUR = Math.round((T_END + 0.2) * 60) / 60;
    // S10 v1.6 reveal (seconds from the REVEAL marker; same numbers as SceneTransition.VERSUS_SPLIT_FX x 3.20 s):
    // STRIKE 0-0.50, CHARGE 0.40-0.75, BURST 0.75. The halves then jolt 5 % open, grind slowly apart while each one
    // vibrates on its own (4 px, 38 Hz) and sheds sparks from its torn edge, and finally slide out fast (gone at 3.04).
    // The stage behind pushes in at the same pace (the game camera dollies in). Light wall gone by 1.95.
    var REV = {
        strike: 0.50, charge: 0.40, burst: 0.75, fly: 2.29, jolt: 0.05, joltK: 0.10, openPow: 1.7,
        flyX: 0.62 * 1920, tilt: 5, flyScale: 10, crack: 2,
        tremble: 3, shake: 6, shakeDur: 0.18, grind: 4, grindHz: 38, grindEnd: 0.80,
        wallEnd: 1.95, raysEnd: 1.70, sparksEnd: 2.00, grindSparks: 150, grindLife: 0.75, push: 12
    };
    // Shift for the light / bolt fades that were authored against the v1.4 burst (0.62 s)
    var LS = REV.burst - 0.62;
    var STAR_SPIN = 12.5;     // deg/s : 30 deg per 2.4 s loop -> seamless on a 12-point star
    var DASH_SIGN = -1;       // sign of stroke-dash offset that makes dashes travel toward the path END
    var FONT_BOLD = "NotoSansJP-Bold", FONT_BLACK = "NotoSansJP-Black";

    var NAVY = [27 / 255, 42 / 255, 65 / 255];
    var STAR_YELLOW = [1, 210 / 255, 63 / 255];
    var STAR_ORANGE = [1, 138 / 255, 0];
    var P1_BODY = [0.95, 0.55, 0.20];   // PlayerController.P1_BODY (slot 1, host, orange)
    var P2_BODY = [0.20, 0.65, 0.90];   // PlayerController.P2_BODY (slot 2, guest, blue)

    var TXT = {
        leftName: "\u3054\u6a5f\u5acc\u306a\u925b\u7b46",
        leftTag: "\u3058\u3076\u3093",
        rightName: "\u30c6\u30b9\u30c8\u306e \u3042\u3044\u3066",
        rightTag: "\u3042\u3044\u3066",
        rules: "\u3055\u3093\u3059\u3046 \u30fb 3\u5e74 \u30fb \u3075\u3064\u3046",
        gauge: "\u3058\u3085\u3093\u3073 \u3061\u3085\u3046",
        dot: "\uff0e"
    };

    // OnlineStagingTimeline.SEAM_POINTS (fractions of the screen)
    var SEAM_F = [[0.535, -0.02], [0.475, 0.20], [0.548, 0.36], [0.462, 0.58], [0.540, 0.76], [0.488, 1.02]];

    var LOG = [];
    function log(s) { LOG.push(String(s)); }
    function errText(e) {
        try {
            if (e === null || e === undefined) { return "unknown"; }
            var m = (e.message !== undefined) ? String(e.message) : String(e);
            if (e.line !== undefined) { m += " @line " + e.line; }
            return m;
        } catch (x) { return "error"; }
    }

    var proj = null;

    // ------------------------------------------------------------------ geometry
    function seamPts(dx, dy) {
        var a = [];
        for (var i = 0; i < SEAM_F.length; i++) { a.push([SEAM_F[i][0] * W + (dx || 0), SEAM_F[i][1] * H + (dy || 0)]); }
        return a;
    }
    function seamLength() {
        var p = seamPts(0, 0), L = 0;
        for (var i = 0; i < p.length - 1; i++) {
            var dx = p[i + 1][0] - p[i][0], dy = p[i + 1][1] - p[i][1];
            L += Math.sqrt(dx * dx + dy * dy);
        }
        return L;
    }
    function leftPoly(ox, oy) {
        var s = seamPts(ox, oy);
        var v = [[-2600 + ox, -400 + oy], [s[0][0], -400 + oy]];
        for (var i = 0; i < s.length; i++) { v.push(s[i]); }
        v.push([s[s.length - 1][0], H + 400 + oy]);
        v.push([-2600 + ox, H + 400 + oy]);
        return v;
    }
    function rightPoly(ox, oy) {
        var s = seamPts(ox, oy);
        var v = [[s[0][0], -400 + oy], [W + 2600 + ox, -400 + oy], [W + 2600 + ox, H + 400 + oy], [s[s.length - 1][0], H + 400 + oy]];
        for (var i = s.length - 1; i >= 0; i--) { v.push(s[i]); }
        return v;
    }
    // dense copy of the seam polyline (every ~step px, keeps the corners), arc length and unit normals (+ = toward the right team)
    function seamDense(step) {
        var P = seamPts(0, 0), B = [P[0]], S = [0], acc = 0, i, k;
        for (i = 0; i < P.length - 1; i++) {
            var dx = P[i + 1][0] - P[i][0], dy = P[i + 1][1] - P[i][1], len = Math.sqrt(dx * dx + dy * dy);
            var n = Math.max(1, Math.round(len / step));
            for (k = 1; k <= n; k++) { B.push([P[i][0] + dx * k / n, P[i][1] + dy * k / n]); S.push(acc + len * k / n); }
            acc += len;
        }
        var N = [];
        for (i = 0; i < B.length; i++) {
            var a0 = B[Math.max(0, i - 1)], b0 = B[Math.min(B.length - 1, i + 1)];
            var tx = b0[0] - a0[0], ty = b0[1] - a0[1], l = Math.sqrt(tx * tx + ty * ty) || 1;
            N.push([ty / l, -tx / l]);
        }
        return { B: B, S: S, N: N, L: acc };
    }
    function pointAt(SD, s) {
        for (var i = 1; i < SD.B.length; i++) {
            if (SD.S[i] >= s) {
                var f = (s - SD.S[i - 1]) / (SD.S[i] - SD.S[i - 1]);
                return [SD.B[i - 1][0] + (SD.B[i][0] - SD.B[i - 1][0]) * f, SD.B[i - 1][1] + (SD.B[i][1] - SD.B[i - 1][1]) * f];
            }
        }
        return SD.B[SD.B.length - 1];
    }
    function seamXAt(y) {
        var p = seamPts(0, 0);
        for (var i = 0; i < p.length - 1; i++) {
            if (y <= p[i + 1][1]) { return p[i][0] + (p[i + 1][0] - p[i][0]) * (y - p[i][1]) / (p[i + 1][1] - p[i][1]); }
        }
        return p[p.length - 1][0];
    }
    var SEED = 20261012;
    // S10 v1.6 open curve, k = 0..1 over the fly time (same as SceneTransition._split_open_curve)
    function smooth01(a, b, x) { var t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); }
    function openCurve(k) {
        var j = Math.min(Math.max(k / REV.joltK, 0), 1);
        return REV.jolt * (1 - (1 - j) * (1 - j)) + (1 - REV.jolt) * Math.pow(smooth01(REV.joltK * 0.5, 1, k), REV.openPow);
    }
    function rnd() { SEED = (SEED * 16807) % 2147483647; return SEED / 2147483647; }
    function rr(a, b) { return a + (b - a) * rnd(); }
    function fmt(v, d) { var m = Math.pow(10, d); return String(Math.round(v * m) / m); }
    function jsPts(a, d) { var o = []; for (var i = 0; i < a.length; i++) { o.push("[" + fmt(a[i][0], d) + "," + fmt(a[i][1], d) + "]"); } return "[" + o.join(",") + "]"; }
    function jsNums(a, d) { var o = []; for (var i = 0; i < a.length; i++) { o.push(fmt(a[i], d)); } return "[" + o.join(",") + "]"; }
    // Path expression for the strike: the bolt grows along the seam at constant speed (arc length) from the top edge
    // (REVEAL + 0) to the bottom edge (REVEAL + strike). Offsets follow the seam normal:
    //   off (fixed side offset) + sign * amp * sin(2 pi s / lam - twist phase) (braided strands) + jitter (re-drawn 30x per second).
    // Everything converges to the seam within "conv" px of the tip, so the strands meet in the spark-ball head.
    function boltExpr(SD, o) {
        return 'var R=' + T_REVEAL + ', D=' + REV.strike + ', L=' + fmt(SD.L, 2) + ';\n' +
            'var B=' + jsPts(SD.B, 1) + ';\n' +
            'var S=' + jsNums(SD.S, 1) + ';\n' +
            'var N=' + jsPts(SD.N, 3) + ';\n' +
            'var OFF=' + o.off + ', A=' + o.amp + ', LAM=' + o.lam + ', SG=' + o.sign + ', J=' + o.jit + ', CV=' + o.conv + ';\n' +
            'var t=time-R; var tip=Math.min(Math.max(t/D,0),1)*L;\n' +
            'seedRandom(' + o.seed + '+Math.floor(time*30), true);\n' +
            'var ph=t*2*Math.PI*' + o.twist + ';\n' +
            'var pts=[];\n' +
            'for (var i=0;i<B.length;i++){\n' +
            '  if (S[i]>tip){ if (i>0){ var f=(tip-S[i-1])/(S[i]-S[i-1]); pts.push([B[i-1][0]+(B[i][0]-B[i-1][0])*f, B[i-1][1]+(B[i][1]-B[i-1][1])*f]); } break; }\n' +
            '  var env=Math.min(1,(tip-S[i])/CV);\n' +
            '  var w=OFF*env + SG*A*env*Math.sin(2*Math.PI*S[i]/LAM-ph) + (random()-0.5)*2*J*env;\n' +
            '  pts.push([B[i][0]+N[i][0]*w, B[i][1]+N[i][1]*w]);\n' +
            '}\n' +
            'if (pts.length<2) { pts=[B[0],[B[0][0],B[0][1]+0.1]]; }\n' +
            'createPath(pts, [], [], false);';
    }
    function headExpr(SD) {
        return 'var R=' + T_REVEAL + ', D=' + REV.strike + ', L=' + fmt(SD.L, 2) + ';\n' +
            'var B=' + jsPts(SD.B, 1) + ';\n' +
            'var S=' + jsNums(SD.S, 1) + ';\n' +
            'var tip=Math.min(Math.max((time-R)/D,0),1)*L; var p=B[B.length-1];\n' +
            'for (var i=1;i<B.length;i++){ if (S[i]>=tip){ var f=(tip-S[i-1])/(S[i]-S[i-1]); p=[B[i-1][0]+(B[i][0]-B[i-1][0])*f, B[i-1][1]+(B[i][1]-B[i-1][1])*f]; break; } }\n' +
            'p';
    }
    function polyShape(verts) { var s = new Shape(); s.vertices = verts; s.closed = true; return s; }
    function ellipseShape(cx, cy, rx, ry) {
        var k = 0.5523;
        var s = new Shape();
        s.vertices = [[cx, cy - ry], [cx + rx, cy], [cx, cy + ry], [cx - rx, cy]];
        s.inTangents = [[-rx * k, 0], [0, -ry * k], [rx * k, 0], [0, ry * k]];
        s.outTangents = [[rx * k, 0], [0, ry * k], [-rx * k, 0], [0, -ry * k]];
        s.closed = true;
        return s;
    }

    // ------------------------------------------------------------------ project helpers
    function newComp(name, w, h, dur, folder) {
        var c = proj.items.addComp(name, w, h, 1, dur, FPS);
        c.parentFolder = folder;
        c.bgColor = [0, 0, 0];
        c.motionBlur = true;
        c.shutterAngle = 180;
        c.shutterPhase = -90;
        try { c.motionBlurSamplesPerFrame = 16; c.motionBlurAdaptiveSampleLimit = 128; } catch (e) { }
        return c;
    }
    function importImage(path, folder) {
        var io = new ImportOptions(new File(path));
        io.sequence = false;
        io.importAs = ImportAsType.FOOTAGE;
        var it = proj.importFile(io);
        it.parentFolder = folder;
        return it;
    }
    function tf(l, mn) { return l.property("ADBE Transform Group").property(mn); }
    var POS = "ADBE Position", SCL = "ADBE Scale", ROT = "ADBE Rotate Z", OPA = "ADBE Opacity", ANC = "ADBE Anchor Point";

    function arity(prop) {
        try {
            var T = PropertyValueType;
            if (prop.propertyValueType === T.TwoD || prop.propertyValueType === T.ThreeD) {
                var v = prop.value;
                return (v && typeof v.length === "number") ? v.length : 1;
            }
        } catch (e) { }
        return 1;
    }
    // ks: [[time, value, inInfluence, outInfluence, "hold"|"linear"]]
    // Influences are temporal ease influences (%). A key without influences gets 33/33.
    function anim(prop, ks) {
        var i, k;
        for (i = 0; i < ks.length; i++) { prop.setValueAtTime(ks[i][0], ks[i][1]); }
        var n = arity(prop);
        for (i = 0; i < ks.length; i++) {
            k = prop.nearestKeyIndex(ks[i][0]);
            var inI = (ks[i].length > 2 && ks[i][2] !== null && ks[i][2] !== undefined) ? ks[i][2] : 33;
            var outI = (ks[i].length > 3 && ks[i][3] !== null && ks[i][3] !== undefined) ? ks[i][3] : 33;
            var mode = (ks[i].length > 4) ? ks[i][4] : "";
            if (mode === "linear") {
                prop.setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR, KeyframeInterpolationType.LINEAR);
                continue;
            }
            prop.setInterpolationTypeAtKey(k, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
            var a = [], b = [];
            for (var d = 0; d < n; d++) {
                a.push(new KeyframeEase(0, Math.max(0.1, inI)));
                b.push(new KeyframeEase(0, Math.max(0.1, outI)));
            }
            try { prop.setTemporalEaseAtKey(k, a, b); } catch (e) { log("ease " + prop.name + ": " + errText(e)); }
            if (mode === "hold") {
                prop.setInterpolationTypeAtKey(k, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.HOLD);
            }
        }
        if (prop.isSpatial) {
            for (var j = 1; j <= prop.numKeys; j++) {
                try {
                    prop.setSpatialAutoBezierAtKey(j, false);
                    prop.setSpatialContinuousAtKey(j, false);
                    var z = (prop.keyValue(j).length === 3) ? [0, 0, 0] : [0, 0];
                    prop.setSpatialTangentsAtKey(j, z, z);
                } catch (e2) { }
            }
        }
    }

    // ---- shape layers
    function shapeLayer(comp, name) {
        var l = comp.layers.addShape();
        l.name = name;
        tf(l, ANC).setValue([0, 0]);
        tf(l, POS).setValue([0, 0]);
        return l;
    }
    function RV(l) { return l.property("ADBE Root Vectors Group"); }
    function GC(l, g) { return RV(l).property(g).property("ADBE Vectors Group"); }
    function GT(l, g) { return RV(l).property(g).property("ADBE Vector Transform Group"); }
    function addGroup(l, g) { var x = RV(l).addProperty("ADBE Vector Group"); x.name = g; return g; }
    function addPath(l, g, verts, closed) {
        var p = GC(l, g).addProperty("ADBE Vector Shape - Group");
        var s = new Shape(); s.vertices = verts; s.closed = !!closed;
        p.property("ADBE Vector Shape").setValue(s);
    }
    function addRect(l, g, size, pos, round) {
        var p = GC(l, g).addProperty("ADBE Vector Shape - Rect");
        p.property("ADBE Vector Rect Size").setValue(size);
        p.property("ADBE Vector Rect Position").setValue(pos || [0, 0]);
        p.property("ADBE Vector Rect Roundness").setValue(round || 0);
    }
    function rectOf(l, g) { return GC(l, g).property("ADBE Vector Shape - Rect"); }
    function addEllipse(l, g, size, pos) {
        var p = GC(l, g).addProperty("ADBE Vector Shape - Ellipse");
        p.property("ADBE Vector Ellipse Size").setValue(size);
        p.property("ADBE Vector Ellipse Position").setValue(pos || [0, 0]);
    }
    function addStar(l, g, pts, outer, inner, pos) {
        var p = GC(l, g).addProperty("ADBE Vector Shape - Star");
        p.property("ADBE Vector Star Type").setValue(1);
        p.property("ADBE Vector Star Points").setValue(pts);
        p.property("ADBE Vector Star Outer Radius").setValue(outer);
        p.property("ADBE Vector Star Inner Radius").setValue(inner);
        if (pos) { p.property("ADBE Vector Star Position").setValue(pos); }
    }
    function addFill(l, g, col, opa) {
        var f = GC(l, g).addProperty("ADBE Vector Graphic - Fill");
        f.property("ADBE Vector Fill Color").setValue(col);
        f.property("ADBE Vector Fill Opacity").setValue(opa === undefined || opa === null ? 100 : opa);
    }
    function fillOf(l, g) { return GC(l, g).property("ADBE Vector Graphic - Fill"); }
    function addStroke(l, g, col, w, opa, cap, join) {
        var s = GC(l, g).addProperty("ADBE Vector Graphic - Stroke");
        s.property("ADBE Vector Stroke Color").setValue(col);
        s.property("ADBE Vector Stroke Width").setValue(w);
        s.property("ADBE Vector Stroke Opacity").setValue(opa === undefined || opa === null ? 100 : opa);
        if (cap) { s.property("ADBE Vector Stroke Line Cap").setValue(cap); }     // 1 butt, 2 round, 3 projecting
        if (join) { s.property("ADBE Vector Stroke Line Join").setValue(join); }  // 1 miter, 2 round, 3 bevel
    }
    function strokeOf(l, g) { return GC(l, g).property("ADBE Vector Graphic - Stroke"); }
    function dashesOf(l, g) { return strokeOf(l, g).property("ADBE Vector Stroke Dashes"); }
    function addDashes(l, g, dash, gap, offsetExpr) {
        dashesOf(l, g).addProperty("ADBE Vector Stroke Dash 1");
        dashesOf(l, g).property("ADBE Vector Stroke Dash 1").setValue(dash);
        dashesOf(l, g).addProperty("ADBE Vector Stroke Gap 1");
        dashesOf(l, g).property("ADBE Vector Stroke Gap 1").setValue(gap);
        // The Offset property exists but stays hidden until it is explicitly added.
        try { dashesOf(l, g).addProperty("ADBE Vector Stroke Offset"); } catch (eo) { }
        var off = dashesOf(l, g).property("ADBE Vector Stroke Offset");
        if (offsetExpr) { off.expression = offsetExpr; }
    }
    function addTaper(l, g, startLen, endLen) {
        var tp = strokeOf(l, g).property("ADBE Vector Stroke Taper");
        if (startLen !== null && startLen !== undefined) { tp.property("ADBE Vector Taper Start Length").setValue(startLen); }
        if (endLen !== null && endLen !== undefined) { tp.property("ADBE Vector Taper End Length").setValue(endLen); }
    }
    function addTrim(l, g) {
        GC(l, g).addProperty("ADBE Vector Filter - Trim");
        return GC(l, g).property("ADBE Vector Filter - Trim");
    }
    function addRepeater(l, g, copies, pos, rot, anchor) {
        var r = GC(l, g).addProperty("ADBE Vector Filter - Repeater");
        r.property("ADBE Vector Repeater Copies").setValue(copies);
        var t = r.property("ADBE Vector Repeater Transform");
        if (anchor) { t.property("ADBE Vector Repeater Anchor").setValue(anchor); }
        t.property("ADBE Vector Repeater Position").setValue(pos || [0, 0]);
        t.property("ADBE Vector Repeater Rotation").setValue(rot || 0);
    }
    function groupPivot(l, g, pivot, rot) {
        var t = GT(l, g);
        t.property("ADBE Vector Anchor").setValue(pivot);
        t.property("ADBE Vector Position").setValue(pivot);
        t.property("ADBE Vector Rotation").setValue(rot || 0);
    }

    // ---- effects (all parameters by match name: works in any AE UI language)
    function addFx(l, mn, name) {
        var e = l.property("ADBE Effect Parade").addProperty(mn);
        if (name) { e.name = name; }
        return e;
    }
    function FX(l, name) { return l.property("ADBE Effect Parade").property(name); }
    function addBlur(l, amount) {
        var b = addFx(l, "ADBE Gaussian Blur 2", "Blur");
        b.property("ADBE Gaussian Blur 2-0001").setValue(amount);
        b.property("ADBE Gaussian Blur 2-0003").setValue(0);   // Repeat Edge Pixels OFF
    }
    function addGlow(l, thresholdPct, radius, intensity) {
        var e = addFx(l, "ADBE Glo2", "Glow");
        e.property("ADBE Glo2-0002").setValue(thresholdPct * 2.55);
        e.property("ADBE Glo2-0003").setValue(radius);
        e.property("ADBE Glo2-0004").setValue(intensity);
    }

    // ---- text
    function addText(comp, name, str, font, size, fill, stroke, sw) {
        var l = comp.layers.addText(str);
        l.name = name;
        var tp = l.property("ADBE Text Properties").property("ADBE Text Document");
        var td = tp.value;
        try { td.resetCharStyle(); td.resetParagraphStyle(); } catch (e) { }
        td.text = str;
        td.font = font;
        td.fontSize = size;
        td.applyFill = true;
        td.fillColor = fill;
        if (stroke) {
            td.applyStroke = true;
            td.strokeColor = stroke;
            td.strokeWidth = sw;
            td.strokeOverFill = false;
        } else {
            td.applyStroke = false;
        }
        td.justification = ParagraphJustification.CENTER_JUSTIFY;
        td.tracking = 0;
        tp.setValue(td);
        return l;
    }
    function srcText(l) { return l.property("ADBE Text Properties").property("ADBE Text Document"); }

    // ---- expressions shared by every layer (controls live on VS_Cutin > CTRL)
    var CT = 'comp("VS_Cutin").layer("CTRL")';
    function colX(side, mode, k) {
        var c = 'var c=' + CT + '.effect("' + side + ' Color")(1); ';
        if (mode === "white") { return c + '[c[0]+(1-c[0])*' + k + ', c[1]+(1-c[1])*' + k + ', c[2]+(1-c[2])*' + k + ', 1]'; }
        if (mode === "scale") { return c + '[c[0]*' + k + ', c[1]*' + k + ', c[2]*' + k + ', 1]'; }
        if (mode === "warm") { return c + '[c[0]*(1-' + k + ')+' + k + ', c[1]*(1-' + k + ')+0.97*' + k + ', c[2]*(1-' + k + ')+0.85*' + k + ', 1]'; }
        return c + '[c[0], c[1], c[2], 1]';
    }
    var ANCHOR_CENTER = 'var r=sourceRectAtTime(time,false); [r.left+r.width/2, r.top+r.height/2]';
    function holderExpr(name) { return 'var s=comp("VS_Cutin").layer("' + name + '").text.sourceText; "" + s'; }

    // =================================================================== BUILD
    function build() {
        if (app.project) { app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES); }
        app.newProject();
        proj = app.project;
        try { proj.bitsPerChannel = 16; } catch (e0) { }
        try { proj.expressionEngine = "javascript-1.0"; } catch (e1) { }

        var fMain = proj.items.addFolder("01_Main");
        var fPre = proj.items.addFolder("02_Precomps");
        var fFoot = proj.items.addFolder("03_Footage");
        var fChars = proj.items.addFolder("chars"); fChars.parentFolder = fFoot;
        var fPlates = proj.items.addFolder("plates"); fPlates.parentFolder = fFoot;

        // ---------------- footage
        var charItems = {};
        var s, p, side;
        for (s = 1; s <= 2; s++) {
            for (p = 0; p < 4; p++) {
                for (var si = 0; si < 2; si++) {
                    side = si === 0 ? "L" : "R";
                    var key = "slot" + s + "_pose" + p + "_" + side;
                    charItems[key] = importImage(CHAR_DIR + key + ".png", fChars);
                }
            }
        }
        var formationItem = importImage(PLATE_DIR + "formation_plate.png", fPlates);
        var stageItem = importImage(PLATE_DIR + "stage_plate.png", fPlates);

        // ---------------- main comp + controls first (every expression points here)
        var main = newComp("VS_Cutin", W, H, DUR, fMain);
        var ctrl = main.layers.addNull(DUR);
        ctrl.name = "CTRL";
        var e;
        e = addFx(ctrl, "ADBE Checkbox Control", "Guest View"); e.property(1).setValue(0);
        e = addFx(ctrl, "ADBE Color Control", "Slot1 Color"); e.property(1).setValue([P1_BODY[0], P1_BODY[1], P1_BODY[2], 1]);
        e = addFx(ctrl, "ADBE Color Control", "Slot2 Color"); e.property(1).setValue([P2_BODY[0], P2_BODY[1], P2_BODY[2], 1]);
        e = addFx(ctrl, "ADBE Color Control", "Left Color");
        e.property(1).expression = 'effect("Guest View")(1) == 1 ? effect("Slot2 Color")(1) : effect("Slot1 Color")(1)';
        e = addFx(ctrl, "ADBE Color Control", "Right Color");
        e.property(1).expression = 'effect("Guest View")(1) == 1 ? effect("Slot1 Color")(1) : effect("Slot2 Color")(1)';
        e = addFx(ctrl, "ADBE Slider Control", "Left Pose"); e.property(1).setValue(0);
        e = addFx(ctrl, "ADBE Slider Control", "Right Pose"); e.property(1).setValue(1);
        e = addFx(ctrl, "ADBE Checkbox Control", "Show Gauge"); e.property(1).setValue(1);
        e = addFx(ctrl, "ADBE Slider Control", "Gauge Progress");
        anim(FX(ctrl, "Gauge Progress").property(1), [[T_HOLD, 0, 33, 40], [T_REVEAL - 0.15, 100, 60, 33]]);
        e = addFx(ctrl, "ADBE Slider Control", "Breath Period"); e.property(1).setValue(2.4);
        e = addFx(ctrl, "ADBE Slider Control", "Spark Period"); e.property(1).setValue(1.2);

        // editable text sources (guide layers: never rendered, read by expressions)
        var holders = [
            ["LEFT_NAME", TXT.leftName], ["LEFT_TAG", TXT.leftTag],
            ["RIGHT_NAME", TXT.rightName], ["RIGHT_TAG", TXT.rightTag],
            ["RULES", TXT.rules]
        ];
        var holderLayers = [];
        for (var hi = 0; hi < holders.length; hi++) {
            var hl = addText(main, holders[hi][0], holders[hi][1], FONT_BOLD, 40, [1, 1, 1], null, 0);
            hl.guideLayer = true;
            tf(hl, POS).setValue([360 + (hi % 3) * 600, 1180 + Math.floor(hi / 3) * 70]);
            holderLayers.push(hl);
        }

        // ---------------- P_Panel_L / P_Panel_R : team panel (gradient, light rays, halftone, speed lines)
        function buildPanel(sideName) {
            var isL = sideName === "Left";
            var c = newComp("P_Panel_" + (isL ? "L" : "R"), 2400, 1240, DUR, fPre);
            var cx = (isL ? 0.24 : 0.76) * W + 240, cy = 0.42 * H + 80;

            var base = c.layers.addSolid([0.5, 0.5, 0.5], "BASE", 2400, 1240, 1, DUR);
            var r = addFx(base, "ADBE Ramp", "Panel Ramp");
            r.property("ADBE Ramp-0001").setValue([cx, cy]);
            r.property("ADBE Ramp-0003").setValue([cx + 1000, cy]);
            r.property("ADBE Ramp-0005").setValue(2);
            r.property("ADBE Ramp-0002").expression = colX(sideName, "warm", 0.36);
            r.property("ADBE Ramp-0004").expression = colX(sideName, "scale", 0.66);

            var cg = shapeLayer(c, "CORE_GLOW");
            addGroup(cg, "g"); addEllipse(cg, "g", [760, 820], [cx, cy - 10]); addFill(cg, "g", [1, 1, 1], 100);
            fillOf(cg, "g").property("ADBE Vector Fill Color").expression = colX(sideName, "white", 0.6);
            addBlur(cg, 200);
            cg.blendingMode = BlendingMode.SCREEN;
            anim(tf(cg, OPA), [[0.30, 22, 33, 10], [0.36, 55, 10, 40], [0.80, 28, 60, 10]]);

            var rays = shapeLayer(c, "RAYS");
            tf(rays, POS).setValue([cx, cy]);
            addGroup(rays, "g"); addStar(rays, "g", 12, 1700, 42, [0, 0]); addFill(rays, "g", [1, 1, 1], 100);
            fillOf(rays, "g").property("ADBE Vector Fill Color").expression = colX(sideName, "white", 0.75);
            tf(rays, ROT).expression = 'time*' + (isL ? STAR_SPIN : -STAR_SPIN);
            rays.blendingMode = BlendingMode.ADD;
            anim(tf(rays, OPA), [[0.30, 8, 33, 10], [0.36, 22, 10, 30], [0.80, 9, 60, 10]]);
            anim(tf(rays, SCL), [[0.30, [70, 70], 33, 10], [0.62, [100, 100], 70, 10]]);

            var ht = shapeLayer(c, "HALFTONE");
            addGroup(ht, "g");
            var x0 = isL ? 100 : 1100;
            addEllipse(ht, "g", [8, 8], [x0, 70]); addFill(ht, "g", [1, 1, 1], 100);
            addRepeater(ht, "g", 69, [18, 0], 0);
            addRepeater(ht, "g", 62, [0, 18], 0);
            tf(ht, OPA).setValue(18);
            ht.blendingMode = BlendingMode.ADD;

            function speedLayer(name, dashes, widths, speed, rotBase, opa) {
                var sl = shapeLayer(c, name);
                for (var k = 0; k < 6; k++) {
                    var g = "L" + k;
                    addGroup(sl, g);
                    var r0 = 250 + 45 * (k % 3);
                    addPath(sl, g, [[cx, cy - r0], [cx, cy - 1600]], false);
                    addStroke(sl, g, [1, 1, 1], widths[k], 100, 2, 2);
                    addDashes(sl, g, dashes[k], 360 - dashes[k], DASH_SIGN + '*time*' + speed + ' + ' + (k * 67));
                    addTaper(sl, g, 45, 0);
                    addRepeater(sl, g, 6, [0, 0], 60, [cx, cy]);
                    groupPivot(sl, g, [cx, cy], rotBase + k * 10 + (k % 2) * 3);
                }
                sl.blendingMode = BlendingMode.ADD;
                anim(tf(sl, OPA), [[0, 0, 33, 10], [0.18, opa, 60, 33]]);
                return sl;
            }
            speedLayer("SPEED_LINES", [150, 110, 180, 130, 160, 120], [5, 4, 6, 4, 5, 4], 300, 0, 18);
            speedLayer("SPEED_LINES_FINE", [60, 40, 80, 50, 70, 45], [2.5, 2, 3, 2, 2.5, 2], 450, 5, 12);

            var mt = c.layers.addSolid([0, 0, 0], "RAMP_MATTE", 2400, 1240, 1, DUR);
            var r2 = addFx(mt, "ADBE Ramp", "Matte Ramp");
            r2.property("ADBE Ramp-0001").setValue([cx, cy]);
            r2.property("ADBE Ramp-0003").setValue([cx + 1150, cy]);
            r2.property("ADBE Ramp-0005").setValue(2);
            r2.property("ADBE Ramp-0002").setValue([1, 1, 1, 1]);
            r2.property("ADBE Ramp-0004").setValue([0, 0, 0, 1]);
            rays.setTrackMatte(mt, TrackMatteType.LUMA);
            ht.setTrackMatte(mt, TrackMatteType.LUMA_INVERTED);
            mt.enabled = false;
            return c;
        }
        var panelL = buildPanel("Left");
        var panelR = buildPanel("Right");

        // ---------------- P_Char_L / P_Char_R : captured game characters, switched by CTRL (slot + pose)
        function buildChar(sideKey) {
            var c = newComp("P_Char_" + sideKey, 1170, 1000, DUR, fPre);
            var sideName = sideKey === "L" ? "Left" : "Right";
            var slotExpr = sideKey === "L" ? "g ? 2 : 1" : "g ? 1 : 2";
            for (var s2 = 1; s2 <= 2; s2++) {
                for (var p2 = 0; p2 < 4; p2++) {
                    var l = c.layers.add(charItems["slot" + s2 + "_pose" + p2 + "_" + sideKey]);
                    l.name = "slot" + s2 + "_pose" + p2;
                    tf(l, SCL).setValue([50, 50]);
                    tf(l, POS).setValue([585, 500]);
                    tf(l, OPA).expression = 'var C=' + CT + '; var g=C.effect("Guest View")(1)==1; var slot=' + slotExpr +
                        '; var p=Math.round(C.effect("' + sideName + ' Pose")(1)); (slot==' + s2 + ' && p==' + p2 + ') ? 100 : 0';
                }
            }
            return c;
        }
        var charL = buildChar("L");
        var charR = buildChar("R");

        // ---------------- P_Seam : lightning seam (team glows, white core, branches, sparks)
        var SEAM_LEN = seamLength();
        function buildSeam() {
            var c = newComp("P_Seam", W, H, DUR, fPre);
            function seamLayer(name, dx, colExpr, width, opa, blur) {
                var l = shapeLayer(c, name);
                addGroup(l, "g");
                addPath(l, "g", seamPts(dx, 0), false);
                var tr = addTrim(l, "g");
                anim(tr.property("ADBE Vector Trim End"), [[0.24, 0, 33, 10], [0.32, 100, 60, 33]]);
                addStroke(l, "g", [1, 1, 1], width, opa, 2, 2);
                if (colExpr) { strokeOf(l, "g").property("ADBE Vector Stroke Color").expression = colExpr; }
                if (blur) { addBlur(l, blur); }
                l.blendingMode = BlendingMode.ADD;
                return l;
            }
            seamLayer("GLOW_OUT_L", -14, colX("Left", "white", 0.15), 46, 75, 30);
            seamLayer("GLOW_OUT_R", 14, colX("Right", "white", 0.15), 46, 75, 30);
            seamLayer("GLOW_IN_L", -6, colX("Left", "white", 0.15), 16, 100, 8);
            seamLayer("GLOW_IN_R", 6, colX("Right", "white", 0.15), 16, 100, 8);

            var br = shapeLayer(c, "BRANCHES");
            var branches = [
                [[912, 216], [860, 186], [828, 214], [760, 170], [730, 182]],
                [[1052, 389], [1102, 366], [1134, 394], [1196, 352]],
                [[887, 626], [840, 660], [806, 640], [742, 690], [716, 684]],
                [[1037, 821], [1086, 848], [1120, 830], [1186, 876]]
            ];
            for (var b = 0; b < branches.length; b++) {
                var g = "B" + b;
                addGroup(br, g);
                addPath(br, g, branches[b], false);
                var tb = addTrim(br, g);
                anim(tb.property("ADBE Vector Trim End"), [[0.26 + 0.012 * b, 0, 33, 10], [0.31 + 0.012 * b, 100, 60, 33]]);
                addStroke(br, g, [1, 1, 1], 4, 100, 2, 2);
                addTaper(br, g, 0, 70);
            }
            addGlow(br, 40, 18, 1.5);
            br.blendingMode = BlendingMode.ADD;
            anim(tf(br, OPA), [[0.32, 100, 33, 10], [0.46, 0, 60, 33]]);

            var core = seamLayer("CORE", 0, null, 7, 100, 0);
            core.blendingMode = BlendingMode.NORMAL;
            addGlow(core, 50, 14, 1.0);

            function sparkLayer(name, dash, width, phase, col) {
                var l = shapeLayer(c, name);
                addGroup(l, "g");
                addPath(l, "g", seamPts(0, 0), false);
                addStroke(l, "g", col, width, 100, 2, 2);
                var lane = SEAM_LEN / 5;
                addDashes(l, "g", dash, lane - dash,
                    DASH_SIGN + '*(time/' + CT + '.effect("Spark Period")(1))*' + lane.toFixed(4) + ' + ' + phase.toFixed(2));
                addGlow(l, 10, 40, 2.4);
                l.blendingMode = BlendingMode.NORMAL;
                anim(tf(l, OPA), [[T_HOLD, 0, 33, 30], [T_LOOP, 100, 30, 33]]);
                return l;
            }
            sparkLayer("SPARKS", 46, 20, 0, [1, 0.84, 0.32]);
            sparkLayer("SPARKS_SMALL", 4, 12, SEAM_LEN / 10, [1, 0.97, 0.8]);
            return c;
        }
        var seamComp = buildSeam();

        // ---------------- P_VS : 12-point star badge + "VS" + impact ring / streaks
        function buildVS() {
            var c = newComp("P_VS", 1000, 900, DUR, fPre);
            var C = [500, 450];

            var bg = shapeLayer(c, "VS_BACKGLOW");
            addGroup(bg, "g"); addEllipse(bg, "g", [470, 470], C); addFill(bg, "g", [1, 0.97, 0.9], 100);
            addBlur(bg, 60);
            bg.blendingMode = BlendingMode.SCREEN;
            anim(tf(bg, OPA), [[0.56, 0, 33, 10], [0.62, 75, 10, 30], [1.0, 30, 60, 33]]);

            var sw = shapeLayer(c, "SHOCKWAVE");
            tf(sw, POS).setValue(C);
            addGroup(sw, "g"); addEllipse(sw, "g", [360, 360], [0, 0]); addStroke(sw, "g", [1, 0.97, 0.82], 22, 100);
            anim(strokeOf(sw, "g").property("ADBE Vector Stroke Width"), [[0.60, 26, 33, 10], [0.86, 2, 60, 33]]);
            anim(tf(sw, SCL), [[0.60, [55, 55], 33, 5], [0.86, [240, 240], 80, 33]]);
            anim(tf(sw, OPA), [[0.58, 0, 33, 33, "hold"], [0.60, 100, 33, 10], [0.86, 0, 60, 33]]);
            sw.motionBlur = true;

            var st = shapeLayer(c, "STREAKS");
            tf(st, POS).setValue(C);
            addGroup(st, "g");
            addPath(st, "g", [[0, -185], [0, -345]], false);
            var ts = addTrim(st, "g");
            anim(ts.property("ADBE Vector Trim End"), [[0.60, 0, 33, 10], [0.66, 100, 60, 33]]);
            anim(ts.property("ADBE Vector Trim Start"), [[0.63, 0, 33, 10], [0.76, 100, 40, 33]]);
            addStroke(st, "g", [1, 0.95, 0.6], 10, 100, 2, 2);
            addRepeater(st, "g", 12, [0, 0], 30, [0, 0]);
            GT(st, "g").property("ADBE Vector Rotation").setValue(15);
            addGlow(st, 40, 12, 1.2);
            st.blendingMode = BlendingMode.ADD;

            var sn = c.layers.addNull(DUR);
            sn.name = "STAR_CTRL";
            tf(sn, ANC).setValue([0, 0]);
            tf(sn, POS).setValue(C);
            anim(tf(sn, SCL), [[0.56, [100, 100], 33, 10], [0.64, [116, 116], 60, 40], [0.71, [96, 96], 50, 50], [0.78, [100, 100], 60, 33]]);

            function star(name, outer, inner, col, strokeW, pos, opa) {
                var l = shapeLayer(c, name);
                l.parent = sn;
                tf(l, POS).setValue(pos || [0, 0]);
                addGroup(l, "g");
                addStar(l, "g", 12, outer, inner, [0, 0]);
                addFill(l, "g", col, 100);
                if (strokeW) { addStroke(l, "g", NAVY, strokeW, 100, 1, 2); }
                tf(l, ROT).expression = 'time*' + STAR_SPIN;
                if (opa !== undefined && opa !== null) { tf(l, OPA).setValue(opa); }
                return l;
            }
            star("STAR_RIM", 168, 118, STAR_ORANGE, 8, null, null);
            star("STAR_FACE", 150, 104, STAR_YELLOW, 0, null, null);
            star("STAR_HI", 128, 90, [1, 0.95, 0.62], 0, [0, -8], 60);

            var vn = c.layers.addNull(DUR);
            vn.name = "VS_CTRL";
            tf(vn, ANC).setValue([0, 0]);
            tf(vn, POS).setValue([C[0], C[1] - 8]);
            anim(tf(vn, SCL), [[0.58, [100, 100], 33, 10], [0.61, [114, 86], 20, 40], [0.66, [95, 106], 50, 50],
                [0.72, [101, 99], 50, 50], [0.78, [100, 100], 60, 33]]);

            var vt = addText(c, "VS_TEXT", "VS", FONT_BLACK, 178, [1, 1, 1], NAVY, 24);
            vt.parent = vn;
            tf(vt, POS).setValue([0, 0]);
            tf(vt, ANC).expression = ANCHOR_CENTER;
            var ds = addFx(vt, "ADBE Drop Shadow", "Shadow");
            ds.property("ADBE Drop Shadow-0001").setValue([NAVY[0], NAVY[1], NAVY[2], 1]);
            ds.property("ADBE Drop Shadow-0002").setValue(140);
            ds.property("ADBE Drop Shadow-0003").setValue(180);
            ds.property("ADBE Drop Shadow-0004").setValue(9);
            ds.property("ADBE Drop Shadow-0005").setValue(4);

            var vs2 = addText(c, "VS_SHADE", "VS", FONT_BLACK, 178, [1, 0.86, 0.42], null, 0);
            vs2.parent = vn;
            tf(vs2, POS).setValue([0, 0]);
            tf(vs2, ANC).expression = ANCHOR_CENTER;
            var rr = vs2.sourceRectAtTime(0, false);
            var yTop = rr.top + rr.height * 0.56, yBot = rr.top + rr.height + 40;
            var m = vs2.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
            m.maskMode = MaskMode.ADD;
            m.property("ADBE Mask Shape").setValue(polyShape([[rr.left - 40, yTop], [rr.left + rr.width + 40, yTop], [rr.left + rr.width + 40, yBot], [rr.left - 40, yBot]]));
            m.property("ADBE Mask Feather").setValue([16, 16]);
            return c;
        }
        var vsComp = buildVS();

        // ---------------- P_Plate_L / P_Plate_R : name band (560x84) + tag pill
        function buildPlate(sideName) {
            var isL = sideName === "Left";
            var key = isL ? "L" : "R";
            var c = newComp("P_Plate_" + key, 720, 220, DUR, fPre);
            var BC = [360, 140];

            var sh = shapeLayer(c, "BAND_SHADOW");
            addGroup(sh, "g"); addRect(sh, "g", [560, 84], [BC[0], BC[1] + 8], 18); addFill(sh, "g", NAVY, 100);
            tf(sh, OPA).setValue(35);
            addBlur(sh, 6);

            var band = shapeLayer(c, "BAND");
            addGroup(band, "g");
            addRect(band, "g", [554, 78], BC, 15);
            addStroke(band, "g", [1, 1, 1], 6, 100, 1, 2);       // stroke first = drawn above the fill
            addFill(band, "g", [1, 1, 1], 92);
            strokeOf(band, "g").property("ADBE Vector Stroke Color").expression = colX(sideName, "base", 0);

            var nt = addText(c, "NAME_TEXT", isL ? TXT.leftName : TXT.rightName, FONT_BOLD, 46, NAVY, null, 0);
            srcText(nt).expression = holderExpr(isL ? "LEFT_NAME" : "RIGHT_NAME");
            tf(nt, ANC).expression = ANCHOR_CENTER;
            tf(nt, POS).setValue(BC);
            // spec: names longer than 9 characters shrink (46 -> 32 px). Here: fit the text into the band.
            tf(nt, SCL).expression = 'var w=sourceRectAtTime(time,false).width; var s=(w>510)?(51000/w):100; [s,s]';

            var tagT = isL ? 0.64 : 0.67;
            var pill = shapeLayer(c, "TAG_PILL");
            tf(pill, ANC).setValue([102, 98]);
            tf(pill, POS).setValue([102, 98]);
            addGroup(pill, "g");
            addRect(pill, "g", [120, 40], [162, 78], 20);
            addFill(pill, "g", [1, 1, 1], 100);
            rectOf(pill, "g").property("ADBE Vector Rect Size").expression = 'var r=thisComp.layer("TAG_TEXT").sourceRectAtTime(time,false); [r.width+36, 40]';
            rectOf(pill, "g").property("ADBE Vector Rect Position").expression = 'var r=thisComp.layer("TAG_TEXT").sourceRectAtTime(time,false); [102+(r.width+36)/2, 78]';
            fillOf(pill, "g").property("ADBE Vector Fill Color").expression = colX(sideName, "scale", 0.9);
            anim(tf(pill, SCL), [[tagT, [0, 0], 33, 10], [tagT + 0.09, [108, 108], 50, 50], [tagT + 0.16, [100, 100], 60, 33]]);

            var tt = addText(c, "TAG_TEXT", isL ? TXT.leftTag : TXT.rightTag, FONT_BOLD, 26, [1, 1, 1], null, 0);
            srcText(tt).expression = holderExpr(isL ? "LEFT_TAG" : "RIGHT_TAG");
            tt.parent = pill;
            tf(tt, ANC).expression = ANCHOR_CENTER;
            tf(tt, POS).expression = 'var r=sourceRectAtTime(time,false); [102+(r.width+36)/2, 79]';
            return c;
        }
        var plateL = buildPlate("Left");
        var plateR = buildPlate("Right");

        // ---------------- CUTIN_GRAPHICS : the whole 2D cut-in layer (what the game captures at SWAP)
        var g = newComp("CUTIN_GRAPHICS", W, H, DUR, fPre);
        var shaken = [];

        var pL = g.layers.add(panelL); pL.name = "PANEL_L";
        var pR = g.layers.add(panelR); pR.name = "PANEL_R";
        var panels = [[pL, -1, leftPoly(240, 80)], [pR, 1, rightPoly(240, 80)]];
        for (var pi = 0; pi < 2; pi++) {
            var pl = panels[pi][0], sg = panels[pi][1];
            tf(pl, ANC).setValue([1200, 620]);
            var mk = pl.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
            mk.maskMode = MaskMode.ADD;
            mk.property("ADBE Mask Shape").setValue(polyShape(panels[pi][2]));
            // S8: panels slide in by 1.2 screen widths and overshoot (ease-out-back 1.2 ~ +5.3 % of travel)
            anim(tf(pl, POS), [[0.0, [960 + sg * 2304, 540], 33, 0.1], [0.19, [960 - sg * 122, 540], 55, 45], [0.30, [960, 540], 65, 33]]);
            pl.motionBlur = true;
            shaken.push(pl);
        }

        var vig = g.layers.addSolid([0, 0, 0], "VIGNETTE", W, H, 1, DUR);
        var vm = vig.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
        vm.maskMode = MaskMode.ADD;
        vm.inverted = true;
        vm.property("ADBE Mask Shape").setValue(ellipseShape(960, 540, 756, 756));
        vm.property("ADBE Mask Feather").setValue([760, 760]);
        anim(tf(vig, OPA), [[0, 0, 33, 20], [0.18, 30, 60, 33]]);

        function charLayer(comp, name, x, sideName, sgn) {
            var l = g.layers.add(comp);
            l.name = name;
            tf(l, ANC).setValue([585, 902]);
            // entry flash: a pastel team-colour silhouette that resolves to the real colours (not a screen flash)
            var f = addFx(l, "ADBE Tint", "Entry Flash");
            f.property("ADBE Tint-0002").setValue([1, 1, 1, 1]);
            f.property("ADBE Tint-0001").expression = colX(sideName, "white", 0.55);
            anim(FX(l, "Entry Flash").property("ADBE Tint-0003"), [[0.30, 100, 33, 10], [0.50, 0, 60, 33]]);
            var d1 = addFx(l, "ADBE Drop Shadow", "Rim Glow");
            d1.property("ADBE Drop Shadow-0002").setValue(235);
            d1.property("ADBE Drop Shadow-0004").setValue(0);
            d1.property("ADBE Drop Shadow-0005").setValue(34);
            FX(l, "Rim Glow").property("ADBE Drop Shadow-0001").expression = colX(sideName, "white", 0.5);
            var d2 = addFx(l, "ADBE Drop Shadow", "Cast Shadow");
            d2.property("ADBE Drop Shadow-0001").setValue([NAVY[0], NAVY[1], NAVY[2], 1]);
            d2.property("ADBE Drop Shadow-0002").setValue(120);
            d2.property("ADBE Drop Shadow-0003").setValue(sgn < 0 ? 225 : 135);
            d2.property("ADBE Drop Shadow-0004").setValue(20);
            d2.property("ADBE Drop Shadow-0005").setValue(40);
            // S8: 0.30-0.60 scale 0.85 -> 1.05 -> 1.0 (base scale 90 %), slides in 70 px from the outside
            anim(tf(l, SCL), [[0.30, [76.5, 76.5], 33, 10], [0.48, [94.5, 94.5], 55, 45], [0.60, [90, 90], 70, 33]]);
            anim(tf(l, OPA), [[0.30, 0, 33, 33], [0.375, 100, 33, 33]]);
            anim(tf(l, POS), [[0.30, [x + sgn * 70, 900], 33, 10], [0.48, [x, 900], 75, 33]]);
            // S9: breathing, vertical +-1.2 % (left and right in opposite phase, like the game)
            tf(l, SCL).expression = 'var C=' + CT + '; var P=C.effect("Breath Period")(1); var t=time-' + T_HOLD +
                '; var b=(t>0)?Math.sin(2*Math.PI*t/P)*1.2*(' + (sgn < 0 ? 1 : -1) + '):0; [value[0], value[1]*(1+b/100)]';
            l.motionBlur = true;
            shaken.push(l);
            return l;
        }
        charLayer(charL, "CHAR_L", 480, "Left", -1);
        charLayer(charR, "CHAR_R", 1440, "Right", 1);

        var seam = g.layers.add(seamComp);
        seam.name = "SEAM";
        var td2 = addFx(seam, "ADBE Turbulent Displace", "Bolt Crackle");
        td2.property("ADBE Turbulent Displace-0003").setValue(48);
        anim(FX(seam, "Bolt Crackle").property("ADBE Turbulent Displace-0002"), [[0.24, 46, 33, 10], [0.30, 28, 40, 40], [0.44, 0, 60, 33]]);
        FX(seam, "Bolt Crackle").property("ADBE Turbulent Displace-0006").expression = 'time*900';
        shaken.push(seam);

        var RULES_Y = 672;
        var rp = shapeLayer(g, "RULES_PILL");
        tf(rp, ANC).setValue([960, RULES_Y]);
        tf(rp, POS).setValue([960, RULES_Y]);
        addGroup(rp, "g");
        addRect(rp, "g", [400, 56], [960, RULES_Y], 28);
        addFill(rp, "g", NAVY, 78);
        rectOf(rp, "g").property("ADBE Vector Rect Size").expression = 'var r=thisComp.layer("RULES_TEXT").sourceRectAtTime(time,false); [r.width+64, 56]';
        anim(tf(rp, SCL), [[0.70, [0, 100], 33, 20], [0.80, [100, 100], 75, 33]]);
        shaken.push(rp);

        var rt = addText(g, "RULES_TEXT", TXT.rules, FONT_BOLD, 30, [1, 1, 1], NAVY, 10);
        srcText(rt).expression = holderExpr("RULES");
        tf(rt, ANC).expression = ANCHOR_CENTER;
        anim(tf(rt, POS), [[0.74, [960, RULES_Y + 12], 33, 20], [0.90, [960, RULES_Y], 75, 33]]);
        anim(tf(rt, OPA), [[0.74, 0, 33, 33], [0.86, 100, 33, 33]]);
        shaken.push(rt);

        var vs = g.layers.add(vsComp);
        vs.name = "VS";
        tf(vs, ANC).setValue([500, 450]);
        // S8: 0.42-0.68 scale 2.2 -> 0.92 -> 1.0, rotation -12 -> 0 (impact at 0.602 = 70 % of the window)
        // the badge rests at VS_SIZE % (the spec ratios 2.2 -> 0.92 -> 1.0 are applied to it)
        var VS_SIZE = 115;
        anim(tf(vs, SCL), [[0.42, [2.2 * VS_SIZE, 2.2 * VS_SIZE], 33, 55], [0.602, [0.92 * VS_SIZE, 0.92 * VS_SIZE], 5, 50], [0.68, [VS_SIZE, VS_SIZE], 60, 33]]);
        anim(tf(vs, ROT), [[0.42, -12, 33, 40], [0.615, 2.5, 40, 40], [0.68, 0, 60, 33]]);
        anim(tf(vs, OPA), [[0.42, 0, 33, 33], [0.47, 100, 33, 33]]);
        tf(vs, POS).setValue([960, 432]);
        // S9: VS pulses +-2 % (1.2 s period = two pulses per loop)
        tf(vs, SCL).expression = 'var t=time-' + T_HOLD + '; var m=(t>0)?1+0.02*Math.sin(2*Math.PI*t/1.2):1; [value[0]*m, value[1]*m]';
        var sweep = addFx(vs, "CC Light Sweep", "Shine");
        sweep.property("CC Light Sweep-0002").setValue(-25);
        sweep.property("CC Light Sweep-0003").setValue(2);
        sweep.property("CC Light Sweep-0004").setValue(60);
        sweep.property("CC Light Sweep-0005").setValue(70);
        sweep.property("CC Light Sweep-0006").setValue(0);
        FX(vs, "Shine").property("CC Light Sweep-0001").expression =
            'var p=((time-0.62)%' + LOOP + '+' + LOOP + ')%' + LOOP + '; var u=p/0.5; var x=(u<1)?(-250+1500*u*u*(3-2*u)):1400; [x, 450]';
        vs.motionBlur = true;
        shaken.push(vs);

        function plateLayer(comp, name, x, t0) {
            var l = g.layers.add(comp);
            l.name = name;
            tf(l, ANC).setValue([360, 140]);
            // S8: name bands rise +40 px -> 0 with opacity 0 -> 1 (0.55-0.85)
            anim(tf(l, POS), [[t0, [x, 982], 33, 15], [0.85, [x, 942], 75, 33]]);
            anim(tf(l, OPA), [[t0, 0, 33, 33], [t0 + 0.15, 100, 33, 33]]);
            anim(tf(l, SCL), [[t0, [95, 95], 33, 20], [0.85, [100, 100], 75, 33]]);
            l.motionBlur = true;
            shaken.push(l);
            return l;
        }
        plateLayer(plateL, "PLATE_L", 480, 0.55);
        plateLayer(plateR, "PLATE_R", 1440, 0.58);

        // S9 gauge (game-driven progress: CTRL > Gauge Progress is a demo; CTRL > Show Gauge hides it)
        var gaugeOpa = 'var C=' + CT + '; var a=Math.min(Math.max((time-' + T_HOLD + ')/0.2,0),1); 100*a*C.effect("Show Gauge")(1)';
        var gb = shapeLayer(g, "GAUGE_BACK");
        addGroup(gb, "g"); addRect(gb, "g", [604, 20], [960, 1040], 10); addFill(gb, "g", NAVY, 75);
        tf(gb, OPA).expression = gaugeOpa;
        shaken.push(gb);
        var gf = shapeLayer(g, "GAUGE_FILL");
        addGroup(gf, "g"); addRect(gf, "g", [596, 12], [960, 1040], 6); addFill(gf, "g", STAR_YELLOW, 100);
        rectOf(gf, "g").property("ADBE Vector Rect Size").expression = 'var p=' + CT + '.effect("Gauge Progress")(1)/100; [Math.max(596*p, 0.01), 12]';
        rectOf(gf, "g").property("ADBE Vector Rect Position").expression = 'var p=' + CT + '.effect("Gauge Progress")(1)/100; [662+596*p/2, 1040]';
        tf(gf, OPA).expression = gaugeOpa;
        shaken.push(gf);
        var gl = addText(g, "GAUGE_LABEL", TXT.gauge, FONT_BOLD, 28, [1, 1, 1], NAVY, 10);
        srcText(gl).expression = 'var t=Math.max(time-' + T_HOLD + ',0); var n=Math.floor(t/0.6)%4; var s="' + TXT.gauge + '"; for (var i=0;i<n;i++) s+="' + TXT.dot + '"; s';
        tf(gl, ANC).expression = 'var r=sourceRectAtTime(time,false); [r.left, r.top+r.height/2]';
        tf(gl, POS).expression = 'var r=thisLayer.sourceRectAtTime(' + (T_HOLD + 0.01) + ',false); [960 - r.width/2, 1006]';
        tf(gl, OPA).expression = gaugeOpa;
        shaken.push(gl);

        var shake = g.layers.addNull(DUR);
        shake.name = "SHAKE";
        tf(shake, ANC).setValue([0, 0]);
        tf(shake, POS).setValue([0, 0]);
        for (var si2 = 0; si2 < shaken.length; si2++) { shaken[si2].parent = shake; }
        // S8 / 16: 2D shake +-6 px for 0.18 s at the VS impact only
        tf(shake, POS).expression = 'var t=time-0.60, d=0.18, a=6; (t>=0 && t<d) ? add(value, mul([Math.sin(t*97), Math.cos(t*83)], a*(1-t/d))) : value';

        // ---------------- P_Reveal_FX : S10 v1.4 light of the reveal (strike bolt, charge, burst wall / rays / sparks)
        var SD = seamDense(8);
        var R0 = T_REVEAL, TB = T_REVEAL + REV.burst;
        function buildRevealFX() {
            var c = newComp("P_Reveal_FX", W, H, DUR, fPre);

            // BURST: vertical wall of mixed light along the seam, expanding sideways, gone by REVEAL + 1.60
            function wall(name, sideName, col, w0, w1, dx, peak, tEnd, blur) {
                var l = shapeLayer(c, name);
                addGroup(l, "g");
                addPath(l, "g", seamPts(0, 0), false);
                addStroke(l, "g", col, w0, 100, 2, 2);
                if (sideName) { strokeOf(l, "g").property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.12); }
                anim(strokeOf(l, "g").property("ADBE Vector Stroke Width"), [[TB, w0, 33, 4], [tEnd, w1, 85, 33]]);
                if (dx) { anim(GT(l, "g").property("ADBE Vector Position"), [[TB, [0, 0], 33, 4], [tEnd, [dx, 0], 85, 33]]); }
                anim(tf(l, OPA), [[TB - 0.01, 0, 33, 33, "hold"], [TB, peak, 33, 10], [tEnd, 0, 45, 33]]);
                addBlur(l, blur);
                l.blendingMode = BlendingMode.ADD;
                return l;
            }
            wall("WALL_L", "Left", [1, 1, 1], 40, 760, -380, 62, R0 + REV.wallEnd, 60);
            wall("WALL_R", "Right", [1, 1, 1], 40, 760, 380, 62, R0 + REV.wallEnd, 60);
            wall("WALL_CORE", null, [1, 0.97, 0.9], 24, 220, 0, 45, R0 + 1.10 + LS + 0.2, 28);

            // BURST: light rays fanning out from the seam (left colour to the left, right colour to the right)
            function rays(name, side, sideName) {
                var l = shapeLayer(c, name);
                for (var i = 0; i < 12; i++) {
                    var g = "R" + i;
                    addGroup(l, g);
                    var y = 40 + i * (1000 / 11) + rr(-25, 25);
                    var x = seamXAt(y);
                    var a = ((y - 540) / 540 * 28 + rr(-7, 7)) * Math.PI / 180;
                    var len = rr(520, 1050);
                    addPath(l, g, [[x, y], [x + side * Math.cos(a) * len, y + Math.sin(a) * len]], false);
                    addStroke(l, g, [1, 1, 1], rr(12, 30), 100, 2, 2);
                    strokeOf(l, g).property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.2);
                    addTaper(l, g, 0, 100);
                }
                RV(l).addProperty("ADBE Vector Filter - Trim");
                anim(RV(l).property("ADBE Vector Filter - Trim").property("ADBE Vector Trim End"), [[TB, 0, 33, 5], [TB + 0.18, 100, 80, 33]]);
                anim(tf(l, OPA), [[TB - 0.01, 0, 33, 33, "hold"], [TB, 70, 33, 10], [R0 + 0.85 + LS, 70, 33, 33], [R0 + REV.raysEnd, 0, 50, 33]]);
                addBlur(l, 4);
                addGlow(l, 40, 20, 1.0);
                l.blendingMode = BlendingMode.ADD;
            }
            rays("RAYS_L", -1, "Left");
            rays("RAYS_R", 1, "Right");

            // STRIKE + CHARGE: the seam behind the head stays lit; swells 0.40-0.62; hands over to the wall after the burst
            function pathFromExpr(l, g, expr) {
                addPath(l, g, [[0, 0], [0, 1]], false);
                GC(l, g).property("ADBE Vector Shape - Group").property("ADBE Vector Shape").expression = expr;
            }
            function chargeGlow(name, sideName, off, seed) {
                var l = shapeLayer(c, name);
                addGroup(l, "g");
                pathFromExpr(l, "g", boltExpr(SD, { off: off, amp: 0, lam: 200, sign: 1, jit: 2, seed: seed, twist: 0, conv: 40 }));
                addStroke(l, "g", [1, 1, 1], 26, 100, 2, 2);
                strokeOf(l, "g").property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.2);
                anim(strokeOf(l, "g").property("ADBE Vector Stroke Width"), [[R0 + REV.charge, 26, 33, 40], [TB, 72, 60, 33]]);
                anim(tf(l, OPA), [[R0 + REV.charge, 60, 33, 40], [TB, 100, 60, 10], [R0 + 0.80 + LS, 0, 40, 33]]);
                addBlur(l, 16);
                l.blendingMode = BlendingMode.ADD;
            }
            chargeGlow("CHARGE_GLOW_L", "Left", -10, 11);
            chargeGlow("CHARGE_GLOW_R", "Right", 10, 23);

            // STRIKE: two braided strands (left / right team colour) twisting around the seam; additive -> white-hot where they cross
            var bs = shapeLayer(c, "BOLT_SHADOW");
            addGroup(bs, "g");
            pathFromExpr(bs, "g", boltExpr(SD, { off: 0, amp: 0, lam: 200, sign: 1, jit: 2, seed: 404, twist: 0, conv: 30 }));
            addStroke(bs, "g", NAVY, 46, 100, 2, 2);
            addBlur(bs, 10);
            anim(tf(bs, OPA), [[TB, 45, 33, 10], [R0 + 0.76 + LS, 0, 40, 33]]);
            function strand(name, sideName, sign, seed) {
                var l = shapeLayer(c, name);
                addGroup(l, "g");
                pathFromExpr(l, "g", boltExpr(SD, { off: 0, amp: 19, lam: 210, sign: sign, jit: 3, seed: seed, twist: 2.2, conv: 70 }));
                addStroke(l, "g", [1, 1, 1], 8, 100, 2, 2);
                strokeOf(l, "g").property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.12);
                addGlow(l, 55, 16, 1.0);
                anim(tf(l, OPA), [[TB, 100, 33, 10], [R0 + 0.76 + LS, 0, 40, 33]]);
            }
            strand("STRAND_L", "Left", -1, 101);
            strand("STRAND_R", "Right", 1, 202);

            var core = shapeLayer(c, "BOLT_CORE");
            addGroup(core, "g");
            pathFromExpr(core, "g", boltExpr(SD, { off: 0, amp: 0, lam: 200, sign: 1, jit: 2, seed: 303, twist: 0, conv: 30 }));
            addStroke(core, "g", [1, 1, 1], 4, 100, 2, 2);
            anim(strokeOf(core, "g").property("ADBE Vector Stroke Width"), [[R0 + REV.charge, 4, 33, 40], [TB, 11, 60, 33]]);
            addGlow(core, 45, 16, 1.2);
            anim(tf(core, OPA), [[TB, 100, 33, 10], [R0 + 0.78 + LS, 0, 40, 33]]);

            // STRIKE: short side forks spawning just behind the head (left forks in the left colour, right forks in the right colour)
            var forkL = shapeLayer(c, "FORKS_L"), forkR = shapeLayer(c, "FORKS_R");
            for (var k = 0; k < 12; k++) {
                var side = (k % 2 === 0) ? -1 : 1;
                var fl2 = side < 0 ? forkL : forkR;
                var sk = SD.L * (0.06 + 0.075 * k);
                var p0 = pointAt(SD, sk);
                var pts = [p0], cur = [p0[0], p0[1]];
                var ang = rr(48, 72) * Math.PI / 180;
                for (var sg = 0; sg < 3; sg++) {
                    var ln = rr(28, 52);
                    cur = [cur[0] + side * Math.sin(ang) * ln + rr(-8, 8), cur[1] + Math.cos(ang) * ln + rr(-10, 10)];
                    pts.push(cur);
                }
                var kg = "K" + k;
                addGroup(fl2, kg);
                addPath(fl2, kg, pts, false);
                var tk = R0 + REV.strike * (sk / SD.L) + 0.015;
                var trk = addTrim(fl2, kg);
                anim(trk.property("ADBE Vector Trim End"), [[tk, 0, 33, 10], [tk + 0.03, 100, 60, 33]]);
                addStroke(fl2, kg, [1, 1, 1], 3.5, 100, 2, 2);
                addTaper(fl2, kg, 0, 80);
                anim(GT(fl2, kg).property("ADBE Vector Group Opacity"), [[tk - 0.001, 0, 33, 33, "hold"], [tk, 100, 33, 33], [tk + 0.05, 100, 33, 33], [tk + 0.15, 0, 40, 33]]);
            }
            var forkPairs = [[forkL, "Left"], [forkR, "Right"]];
            for (var fp = 0; fp < 2; fp++) {
                var ff = addFx(forkPairs[fp][0], "ADBE Fill", "Tint");
                ff.property("ADBE Fill-0002").expression = colX(forkPairs[fp][1], "white", 0.55);
                addGlow(forkPairs[fp][0], 30, 14, 1.6);
                forkPairs[fp][0].blendingMode = BlendingMode.ADD;
            }

            // STRIKE: spark-ball head at the leading tip (steady brightness, gone as it leaves the bottom edge)
            var hg = shapeLayer(c, "HEAD_GLOW");
            addGroup(hg, "halo"); addEllipse(hg, "halo", [170, 170], [0, 0]); addFill(hg, "halo", [1, 0.96, 0.86], 70);
            addGroup(hg, "tintL"); addEllipse(hg, "tintL", [120, 120], [-16, 0]); addFill(hg, "tintL", [1, 1, 1], 80);
            fillOf(hg, "tintL").property("ADBE Vector Fill Color").expression = colX("Left", "white", 0.2);
            addGroup(hg, "tintR"); addEllipse(hg, "tintR", [120, 120], [16, 0]); addFill(hg, "tintR", [1, 1, 1], 80);
            fillOf(hg, "tintR").property("ADBE Vector Fill Color").expression = colX("Right", "white", 0.2);
            addBlur(hg, 34);
            hg.blendingMode = BlendingMode.ADD;
            var hc = shapeLayer(c, "HEAD_CORE");
            addGroup(hc, "g"); addEllipse(hc, "g", [30, 30], [0, 0]); addFill(hc, "g", [1, 1, 1], 100);
            addGlow(hc, 40, 20, 1.5);
            var heads = [hg, hc];
            for (var hh = 0; hh < 2; hh++) {
                tf(heads[hh], POS).expression = headExpr(SD);
                anim(tf(heads[hh], OPA), [[R0 + 0.45, 100, 33, 10], [R0 + 0.52, 0, 40, 33]]);
            }

            // BURST: team-coloured sparks / embers from along the seam (left ones fly left, right ones right), gone by REVEAL + 1.80
            function sparks(name, side, sideName, n) {
                var l = shapeLayer(c, name);
                for (var i = 0; i < n; i++) {
                    var g = "S" + i;
                    addGroup(l, g);
                    var d = rr(7, 17);
                    addEllipse(l, g, [d, d], [0, 0]);
                    addFill(l, g, [1, 1, 1], 100);
                    var y0 = rr(10, 1070), x0 = seamXAt(y0) + side * rr(0, 10);
                    var t0 = TB + rr(0, 0.06);
                    var life = Math.min(rr(0.55, 1.1), R0 + REV.sparksEnd - t0);
                    var vx = side * rr(450, 1900), vy = rr(-480, 240), kk = rr(1.8, 3.0);
                    var T0 = fmt(t0, 4);
                    GT(l, g).property("ADBE Vector Position").expression =
                        'var t=time-' + T0 + '; var k=' + fmt(kk, 3) + '; var e=(t>0)?(1-Math.exp(-k*t))/k:0; var u=Math.max(t,0); [' +
                        fmt(x0, 1) + '+(' + fmt(vx, 1) + ')*e, ' + fmt(y0, 1) + '+(' + fmt(vy, 1) + ')*e+0.5*650*u*u]';
                    GT(l, g).property("ADBE Vector Group Opacity").expression =
                        'var t=time-' + T0 + '; (t<0)?0:Math.max(0,100*(1-t/' + fmt(life, 3) + '))';
                    GT(l, g).property("ADBE Vector Scale").expression =
                        'var t=time-' + T0 + '; var s=(t<0)?0:100*(1-0.6*Math.min(t/' + fmt(life, 3) + ',1)); [s,s]';
                }
                var f2 = addFx(l, "ADBE Fill", "Tint");
                f2.property("ADBE Fill-0002").expression = colX(sideName, "white", 0.08);
                addGlow(l, 50, 16, 1.0);
                l.motionBlur = true;
                l.blendingMode = BlendingMode.ADD;
            }
            sparks("SPARKS_L", -1, "Left", 34);
            sparks("SPARKS_R", 1, "Right", 34);

            // OPEN (v1.6): sparks shed from each half's torn edge while it grinds open (the game's VersusGrindSparks).
            // Each spark is born on the edge where that half is at its birth time, flies into the gap with drag and
            // gravity, and is drawn as a tapered streak along its velocity (white-hot -> team colour).
            function grindSparks(name, side, sideName, n) {
                var l = shapeLayer(c, name);
                var ax = side < 0 ? 480 : 1440;
                for (var i = 0; i < n; i++) {
                    var g = "G" + i;
                    addGroup(l, g);
                    var kb = rr(0, REV.grindEnd);
                    var t0 = TB + kb * REV.fly;
                    var e0 = openCurve(kb);
                    var y = rr(20, 1060), x = seamXAt(y);
                    var a0 = side * REV.tilt * e0 * Math.PI / 180, sc = 1 + REV.flyScale / 100 * e0;
                    var dx = (x - ax) * sc, dy = (y - 540) * sc;
                    var x0 = ax + side * (REV.crack + REV.flyX * e0) + dx * Math.cos(a0) - dy * Math.sin(a0);
                    var y0 = 540 + dx * Math.sin(a0) + dy * Math.cos(a0);
                    var ang = Math.atan2(-0.55, -side) + rr(-38, 38) * Math.PI / 180;
                    var sp = rr(260, 980), kk = rr(1.6, 3.2), life = rr(0.4, REV.grindLife);
                    var vx = Math.cos(ang) * sp, vy = Math.sin(ang) * sp, len = rr(28, 64);
                    addPath(l, g, [[0, 0], [0, -len]], false);
                    addStroke(l, g, [1, 1, 1], rr(4, 7), 100, 2, 2);
                    addTaper(l, g, 0, 100);
                    var T0 = fmt(t0, 4), K = fmt(kk, 3), VX = fmt(vx, 1), VY = fmt(vy, 1), LF = fmt(life, 3);
                    GT(l, g).property("ADBE Vector Position").expression =
                        'var t=time-' + T0 + '; var k=' + K + '; var e=(t>0)?(1-Math.exp(-k*t))/k:0; var u=Math.max(t,0); [' +
                        fmt(x0, 1) + '+(' + VX + ')*e, ' + fmt(y0, 1) + '+(' + VY + ')*e+0.5*1500*u*u]';
                    GT(l, g).property("ADBE Vector Rotation").expression =
                        'var t=Math.max(time-' + T0 + ',0); var d=Math.exp(-' + K + '*t); var vx=(' + VX + ')*d, vy=(' + VY + ')*d+1500*t;' +
                        ' Math.atan2(-vx, vy)*180/Math.PI';
                    GT(l, g).property("ADBE Vector Group Opacity").expression =
                        'var t=time-' + T0 + '; (t<0||t>' + LF + ')?0:100*(1-t/' + LF + ')';
                    GT(l, g).property("ADBE Vector Scale").expression =
                        'var t=time-' + T0 + '; var s=(t<0)?0:100*(1-0.65*Math.min(t/' + LF + ',1)); [s,s]';
                }
                var f3 = addFx(l, "ADBE Fill", "Tint");
                f3.property("ADBE Fill-0002").expression = colX(sideName, "white", 0.45);
                addGlow(l, 40, 14, 1.2);
                l.blendingMode = BlendingMode.ADD;
            }
            grindSparks("GRIND_SPARKS_L", -1, "Left", REV.grindSparks);
            grindSparks("GRIND_SPARKS_R", 1, "Right", REV.grindSparks);
            return c;
        }
        var revealComp = buildRevealFX();

        // ---------------- VS_Cutin : 3D plate + cut-in + split reveal + flash
        var stage = main.layers.add(stageItem);
        stage.name = "STAGE_PLATE";
        stage.inPoint = T_REVEAL;
        stage.outPoint = DUR;
        // v1.6: the game camera dollies in as the halves open (same smoothstep over the open time). The plate is a still,
        // so the push-in is a scale-up from 100 % to 100 + push %.
        tf(stage, SCL).expression = 'var t=time-' + TB + '; var k=Math.min(Math.max(t/' + REV.fly + ',0),1); var s=100+' + REV.push + '*k*k*(3-2*k); [s,s]';

        var form = main.layers.add(formationItem);
        form.name = "FORMATION_PLATE";
        form.outPoint = T_REVEAL;

        var fl = shapeLayer(main, "FOCUS_LINES");
        for (var fk = 0; fk < 3; fk++) {
            var fg = "F" + fk;
            addGroup(fl, fg);
            addPath(fl, fg, [[960, 540 - 430 - fk * 70], [960, 540 - 1300]], false);
            addStroke(fl, fg, [1, 1, 1], [7, 5, 4][fk], 100, 1, 2);
            addTaper(fl, fg, 100, 0);
            addRepeater(fl, fg, 12, [0, 0], 30, [960, 540]);
            groupPivot(fl, fg, [960, 540], fk * 10 + 4);
        }
        anim(tf(fl, OPA), [[0, 0, 33, 10], [0.18, 28, 60, 33]]);
        fl.outPoint = T_HOLD;

        var cut = main.layers.add(g);
        cut.name = "CUTIN";
        cut.outPoint = T_REVEAL;

        // S10 v1.4/v1.6: every 2D layer of the reveal hangs on SPLIT_SHAKE.
        // CHARGE tremble (0.40-0.62, amplitude ramps to 3 px) and BURST shake (+-6 px, decaying over 0.18 s from 0.62).
        var ss = main.layers.addNull(DUR);
        ss.name = "SPLIT_SHAKE";
        tf(ss, ANC).setValue([0, 0]);
        tf(ss, POS).setValue([0, 0]);
        tf(ss, POS).expression = 'var t=time-' + T_REVEAL + '; var o=[0,0];\n' +
            'if (t>=' + REV.charge + ' && t<' + REV.burst + ') { var a=' + REV.tremble + '*(t-' + REV.charge + ')/' + fmt(REV.burst - REV.charge, 3) + '; o=[Math.sin(t*173)*a, Math.cos(t*151)*a]; }\n' +
            'var u=t-' + REV.burst + '; if (u>=0 && u<' + REV.shakeDur + ') { var k=1-u/' + REV.shakeDur + '; o=[Math.sin(u*97)*' + REV.shake + '*k, Math.cos(u*83)*' + REV.shake + '*k]; }\n' +
            'add(value, o)';

        // CHARGE: light leaking through the hairline crack (under the halves)
        var cl = shapeLayer(main, "CRACK_LIGHT");
        var crackParts = [["glowL", -6, "Left", 26], ["glowR", 6, "Right", 26], ["core", 0, null, 8]];
        for (var cp = 0; cp < crackParts.length; cp++) {
            var cg2 = crackParts[cp][0];
            addGroup(cl, cg2);
            addPath(cl, cg2, seamPts(crackParts[cp][1], 0), false);
            addStroke(cl, cg2, [1, 1, 1], crackParts[cp][3], 100, 2, 2);
            if (crackParts[cp][2]) { strokeOf(cl, cg2).property("ADBE Vector Stroke Color").expression = colX(crackParts[cp][2], "white", 0.3); }
        }
        addGlow(cl, 30, 24, 1.4);
        anim(tf(cl, OPA), [[R0 + REV.charge, 0, 33, 40], [TB, 100, 60, 10], [R0 + 1.0 + LS, 0, 50, 33]]);
        cl.blendingMode = BlendingMode.ADD;
        cl.inPoint = T_REVEAL;
        cl.outPoint = T_END;
        cl.parent = ss;

        // S10 v1.6 halves. Closed form (same as the game):
        //   crack c = smoothstep((t-0.40)/0.35)                  -> each half moves 2 px outward (4 px hairline gap)
        //   open  e = 0.05*(1-(1-j)^2) + 0.95*smoothstep(0.05,1,k)^1.7, j = k/0.10, k = (t-0.75)/2.29 clamped
        //         -> a 5 % jolt at the burst, a slow grind, then a fast slide out (gone at 3.04 s)
        //   x = rest +- (2c + 0.62*1920 e), rotation = -+5 e deg (left CCW, right CW), scale = 100 + 10 e %
        //   grind: each half vibrates on its own (4 px, 38 Hz), fading in as the burst shake fades out and out by k = 0.80
        var CORE_T = 'var t=time-' + T_REVEAL + '; var c=Math.min(Math.max((t-' + REV.charge + ')/' + fmt(REV.burst - REV.charge, 3) + ',0),1); c=c*c*(3-2*c);' +
            ' var k=Math.min(Math.max((t-' + REV.burst + ')/' + REV.fly + ',0),1);' +
            ' var j=Math.min(k/' + REV.joltK + ',1); var q=Math.min(Math.max((k-' + (REV.joltK * 0.5) + ')/' + (1 - REV.joltK * 0.5) + ',0),1);' +
            ' var e=' + REV.jolt + '*(1-(1-j)*(1-j))+' + (1 - REV.jolt) + '*Math.pow(q*q*(3-2*q),' + REV.openPow + ');\n' +
            ' var u=t-' + REV.burst + '; var st=Math.min(Math.max(u/' + REV.shakeDur + ',0),1); var ge=Math.min(Math.max((k-' + (REV.grindEnd - 0.2) + ')/0.2,0),1);' +
            ' var gr=(u>=0)?' + REV.grind + '*st*(1-ge*ge*(3-2*ge))*0.66:0; var w=' + REV.grindHz + '*2*Math.PI;\n';
        // per-half vibration (the game's shake_l / shake_r)
        var GRIND = {
            "-1": '[(Math.sin(t*w)+0.5*Math.sin(t*w*1.73+1.1))*gr, 0.6*Math.cos(t*w*0.91+0.4)*gr]',
            "1": '[(Math.sin(t*w*1.07+2.3)+0.5*Math.sin(t*w*1.61))*gr, 0.6*Math.cos(t*w*0.87+1.9)*gr]'
        };
        function splitLayer(name, poly, ax, side) {
            var l = main.layers.add(g);
            l.name = name;
            l.inPoint = T_REVEAL;
            var m2 = l.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
            m2.maskMode = MaskMode.ADD;
            m2.property("ADBE Mask Shape").setValue(polyShape(poly));
            l.parent = ss;
            tf(l, ANC).setValue([ax, 540]);
            tf(l, POS).setValue([ax, 540]);
            tf(l, POS).expression = CORE_T + 'add([' + ax + '+(' + side + ')*(' + REV.crack + '*c+' + REV.flyX + '*e), 540], ' + GRIND[String(side)] + ')';
            tf(l, ROT).expression = CORE_T + '(' + side + ')*' + REV.tilt + '*e';
            tf(l, SCL).expression = CORE_T + 'var s=100+' + REV.flyScale + '*e; [s,s]';
            l.motionBlur = true;
            return l;
        }
        var splitR = splitLayer("CUTIN_SPLIT_R", rightPoly(0, 0), 1440, 1);
        var splitL = splitLayer("CUTIN_SPLIT_L", leftPoly(0, 0), 480, -1);

        // BURST: the torn inner edges glow in their own team colour (children of the halves)
        function edgeGlow(name, parentLayer, side, sideName) {
            var l = shapeLayer(main, name);
            l.parent = parentLayer;
            tf(l, ANC).setValue([0, 0]);
            tf(l, POS).setValue([0, 0]);
            addGroup(l, "wide"); addPath(l, "wide", seamPts(side * 7, 0), false); addStroke(l, "wide", [1, 1, 1], 34, 55, 2, 2);
            strokeOf(l, "wide").property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.1);
            addGroup(l, "core"); addPath(l, "core", seamPts(side * 3, 0), false); addStroke(l, "core", [1, 1, 1], 8, 100, 2, 2);
            strokeOf(l, "core").property("ADBE Vector Stroke Color").expression = colX(sideName, "white", 0.3);
            var td3 = addFx(l, "ADBE Turbulent Displace", "Torn");
            td3.property("ADBE Turbulent Displace-0002").setValue(7);
            td3.property("ADBE Turbulent Displace-0003").setValue(16);
            addGlow(l, 45, 24, 0.9);
            anim(tf(l, OPA), [[TB - 0.02, 0, 33, 33, "hold"], [TB, 100, 33, 33]]);
            l.blendingMode = BlendingMode.ADD;
            l.inPoint = T_REVEAL;
            l.outPoint = T_REVEAL + REV.burst + REV.fly;
            l.motionBlur = true;
            return l;
        }
        edgeGlow("EDGE_GLOW_R", splitR, 1, "Right");
        edgeGlow("EDGE_GLOW_L", splitL, -1, "Left");

        var rfx = main.layers.add(revealComp);
        rfx.name = "REVEAL_FX";
        rfx.inPoint = T_REVEAL;
        rfx.outPoint = T_END;
        rfx.parent = ss;

        // S8 / 16: one white flash, 45 %, 3 frames at 60 fps = 0.05 s (<= 0.06 s). The reveal has no full-screen flash.
        var flash = main.layers.addSolid([1, 1, 1], "FLASH", W, H, 1, DUR);
        anim(tf(flash, OPA), [[0, 0, 33, 33, "hold"], [19 / FPS, 45, 33, 33, "hold"], [22 / FPS, 0, 33, 33, "hold"]]);

        // controls and text sources on top
        for (var hj = holderLayers.length - 1; hj >= 0; hj--) { holderLayers[hj].moveToBeginning(); }
        ctrl.moveToBeginning();

        // markers
        function marker(t, label, dur) {
            var mv = new MarkerValue(label);
            mv.duration = dur;
            main.markerProperty.setValueAtTime(t, mv);
        }
        marker(0, "IN", T_HOLD);
        marker(T_HOLD, "HOLD", T_REVEAL - T_HOLD);
        marker(T_LOOP, "LOOP", LOOP);
        marker(T_REVEAL, "REVEAL", REVEAL);
        marker(T_REVEAL + REV.charge, "CHARGE", REV.burst - REV.charge);
        marker(T_REVEAL + REV.burst, "BURST", REV.fly);
        marker(T_END, "END", DUR - T_END);
        main.workAreaStart = 0;
        main.workAreaDuration = main.duration;
        main.time = 2.0;

        return main;
    }

    function scanExpressions() {
        var errs = [];
        function walk(p, path) {
            for (var k = 1; k <= p.numProperties; k++) {
                var q;
                try { q = p.property(k); } catch (e) { continue; }
                if (!q) { continue; }
                if (q.propertyType === PropertyType.PROPERTY) {
                    try {
                        if (q.canSetExpression && q.expression !== "") {
                            try { q.valueAtTime(2.0, false); } catch (e2) { }
                            if (q.expressionError && q.expressionError !== "") { errs.push(path + "/" + q.name + ": " + q.expressionError); }
                        }
                    } catch (e3) { }
                } else {
                    walk(q, path + "/" + q.name);
                }
            }
        }
        for (var i = 1; i <= proj.numItems; i++) {
            var it = proj.item(i);
            if (!(it instanceof CompItem)) { continue; }
            for (var j = 1; j <= it.numLayers; j++) { walk(it.layer(j), it.name + "/" + it.layer(j).name); }
        }
        return errs;
    }

    function flushLog() {
        if (LOG.length === 0 || !proj) { return; }
        var f = proj.items.addFolder("_build_log");
        for (var i = 0; i < LOG.length && i < 40; i++) {
            var x = proj.items.addFolder(String(i) + " " + LOG[i].substring(0, 230));
            x.parentFolder = f;
        }
    }

    app.beginSuppressDialogs();
    var ok = false;
    try {
        build();
        var errs = scanExpressions();
        for (var ei = 0; ei < errs.length; ei++) { log("EXPR " + errs[ei]); }
        ok = true;
    } catch (e) {
        log("BUILD FAILED: " + errText(e));
    }
    if (ok) {
        flushLog();
        try { proj.save(new File(AEP)); } catch (es) { log("SAVE FAILED: " + errText(es)); flushLog(); }
    } else {
        flushLog();
    }
    app.endSuppressDialogs(false);
})();
