// PV S03 ロゴ（案 C：今の 2D の登場演出を強化）: builds comp PV_S03_C in a NEW After Effects project.
// Run: node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx
//      node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/render_s03_c.jsx
// The open project is closed WITHOUT saving. Saved as docs/pv/previz/ae/AIQUIZ_PV_S03_C.aep.
// Storyboard: docs/pv/storyboard_s01_s03_v2/s01_s03_storyboard_v3.png (C1-C6). 2 bars at 128 BPM = 3.75 s:
//   C1 0-1 beat   a thin yellow line shoots across (white hot tip)
//   C2 1-2        the line opens into the conveyor belt (ribs start to scroll)
//   C3 to bar 2   the letters drop and ride exactly like the menu title intro (2x speed): right letter first, tilted,
//                 land at A's spot with a squash and two hops, the belt carries them to their slots
//   C4 bar 2 head the belt stops = all letters seated: flash, light streaks, diagonal slashes, zoom punch;
//                 then the A-Q bar shoots out of Q into A's foot (as in the menu)
//   C5 2 beats    hold: slow 4% push-in, sparkles, camera flashes in the stands
//   C6 last beat  belt + logo slide out left, a yellow diagonal band wipes to S04 (frame is fully yellow at the end)
// Letters, belt colours and the shadow come from tools/title_logo_ae/layout.json (the menu title logo).
// Background: the Godot capture continues under the logo, NOT blurred or dimmed (PV frames 338-562).
// Note (this PC, AE 2026): after one render, the next render in the same AE session can fail or come out empty.
// Restart AE (and wait until it is fully up) before rendering again.
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var LAYOUT = ROOT + "tools/title_logo_ae/layout.json";
var BG_FIRST = ROOT + "artifacts/pv_capture/s01_s03/pv_0001.jpg";   // numbered sequence pv_0001..pv_0562
var BG_START_FRAME = 338;                                            // PV frame shown at comp time 0
var SAVE_AS = ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S03_C.aep";
var W = 1920, H = 1080, FPS = 60, BEAT = 60 / 128, DUR = 8 * BEAT;  // 3.75 s
var S = 4.8;                                                         // screen px per logical px of the menu logo
var YT = 70;                                                         // top of the letters (P1 stays below the belt)
var BELT_X0 = 60, BELT_X1 = 1860;                                    // belt ends (nearly full width)

var T_OPEN = BEAT, T_RIDE = 2 * BEAT, T_HIT = 4 * BEAT, T_HOLD = 5 * BEAT, T_OUT = 7 * BEAT;

function readJson(path) {
    var f = new File(path);
    f.encoding = "UTF-8";
    if (!f.open("r")) throw new Error("cannot open " + path);
    var s = f.read();
    f.close();
    return JSON.parse(s);
}
var L = readJson(LAYOUT);
// Optional background override (the v3 flow writes it: docs/pv/previz/ae/s03_c_bg.json)
//   {"bg_first": "<first frame of the numbered sequence>", "bg_start_frame": <PV frame at comp time 0>, "save_as": "<aep>"}
var CFG = new File(ROOT + "docs/pv/previz/ae/s03_c_bg.json");
if (CFG.exists) {
    var cfg = readJson(CFG.fsName);
    if (cfg.bg_first) BG_FIRST = cfg.bg_first;
    if (cfg.bg_start_frame) BG_START_FRAME = cfg.bg_start_frame;
    if (cfg.save_as) SAVE_AS = cfg.save_as;
}
var X0 = W / 2 - L.logo_center[0] * S;                               // logo centred horizontally
function P(x, y) { return [X0 + x * S, YT + y * S]; }
var BELT_TOP = YT + L.belt_rect[1] * S, BELT_H = L.belt.height * S, BELT_CY = BELT_TOP + BELT_H / 2;
var LOGO_L = X0, LOGO_R = X0 + L.logo_size[0] * S;
var seed = 20261015;
function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

// ---------- keyframe helpers ----------
function ease(e, dims) {
    var a = [];
    var sp = e ? e[0] : 0, inf = e ? e[1] : 33.33;
    for (var i = 0; i < dims; i++) a.push(new KeyframeEase(sp, inf));
    return a;
}
// key(prop, t, value, inEase, outEase); ease = [speed, influence] or null (= [0, 33.33]); "lin" = linear
function key(prop, t, value, inE, outE) {
    prop.setValueAtTime(t, value);
    var i = prop.nearestKeyIndex(t);
    if (inE === "lin" || outE === "lin") {
        prop.setInterpolationTypeAtKey(i, inE === "lin" ? KeyframeInterpolationType.LINEAR : KeyframeInterpolationType.BEZIER,
            outE === "lin" ? KeyframeInterpolationType.LINEAR : KeyframeInterpolationType.BEZIER);
        if (inE === "lin") inE = undefined;
        if (outE === "lin") outE = undefined;
    } else {
        prop.setInterpolationTypeAtKey(i, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
    }
    var dims = prop.keyInTemporalEase(i).length;
    prop.setTemporalContinuousAtKey(i, false);
    if (inE !== undefined || outE !== undefined) {
        try { prop.setTemporalEaseAtKey(i, ease(inE === undefined ? null : inE, dims), ease(outE === undefined ? null : outE, dims)); } catch (e) {}
    }
    if (prop.isSpatial) { prop.setSpatialAutoBezierAtKey(i, false); prop.setSpatialContinuousAtKey(i, false); }
}
function tr(layer) { return layer.property("ADBE Transform Group"); }
function fx(layer, matchName) { return layer.property("ADBE Effect Parade").addProperty(matchName); }
function setP(group, matchName, value) { try { group.property(matchName).setValue(value); return true; } catch (e) { return false; } }
function glow(layer, threshold, radius, intensity) {
    var g = fx(layer, "ADBE Glo2");
    setP(g, "ADBE Glo2-0002", threshold);
    setP(g, "ADBE Glo2-0003", radius);
    setP(g, "ADBE Glo2-0004", intensity);
    return g;
}
function group(root, name) {
    var g = root.addProperty("ADBE Vector Group");
    g.name = name;
    return g;
}
function contents(g) { return g.property("ADBE Vectors Group"); }
function fill(c, rgb, opacity) {
    var f = c.addProperty("ADBE Vector Graphic - Fill");
    f.property("ADBE Vector Fill Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
    if (opacity !== undefined) f.property("ADBE Vector Fill Opacity").setValue(opacity);
    return f;
}
function stroke(c, rgb, width) {
    var s = c.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
    s.property("ADBE Vector Stroke Width").setValue(width);
    return s;
}
function rect(c, size, pos, roundness) {
    var r = c.addProperty("ADBE Vector Shape - Rect");
    r.property("ADBE Vector Rect Size").setValue(size);
    r.property("ADBE Vector Rect Position").setValue(pos);
    if (roundness) r.property("ADBE Vector Rect Roundness").setValue(roundness);
    return r;
}
function poly(c, verts, closed) {
    var p = c.addProperty("ADBE Vector Shape - Group");
    var sh = new Shape();
    sh.vertices = verts;
    sh.closed = closed !== false;
    p.property("ADBE Vector Shape").setValue(sh);
    return p;
}
function star(c, pos, outer, inner, rot) {
    var s = c.addProperty("ADBE Vector Shape - Star");
    s.property("ADBE Vector Star Type").setValue(1);
    s.property("ADBE Vector Star Points").setValue(4);
    s.property("ADBE Vector Star Outer Radius").setValue(outer);
    s.property("ADBE Vector Star Inner Radius").setValue(inner);
    s.property("ADBE Vector Star Rotation").setValue(rot || 0);
    s.property("ADBE Vector Star Position").setValue(pos);
    return s;
}
function shapeLayer(comp, name, pos) {
    var l = comp.layers.addShape();
    l.name = name;
    tr(l).property("ADBE Anchor Point").setValue([0, 0]);
    tr(l).property("ADBE Position").setValue(pos || [0, 0]);
    return l;
}
function col(c) { return [c[0], c[1], c[2]]; }
var YELLOW = col(L.belt.bar_color), BELT_C = col(L.belt.belt_color), BOTTOM_C = col(L.belt.bottom_color);
var RIB_C = col(L.belt.rib_color), ROLLER_C = col(L.belt.roller_color);

// ---------- project ----------
app.beginSuppressDialogs();
if (app.project) app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
app.newProject();
var proj = app.project;
proj.bitsPerChannel = 16;
var io = new ImportOptions(new File(BG_FIRST));
io.sequence = true;
var bgFoot = proj.importFile(io);
bgFoot.mainSource.conformFrameRate = FPS;
var comp = proj.items.addComp("PV_S03_C", W, H, 1.0, DUR, FPS);
comp.bgColor = [0.05, 0.08, 0.15];
comp.motionBlur = true;
comp.shutterAngle = 180;

// 1) background: the capture keeps running (no blur, no dim)
var bg = comp.layers.add(bgFoot);
bg.name = "BG_capture (PV " + BG_START_FRAME + "-)";
bg.startTime = -(BG_START_FRAME - 1) / FPS;
bg.inPoint = 0; bg.outPoint = DUR;
tr(bg).property("ADBE Scale").setValue([W / bgFoot.width * 100, W / bgFoot.width * 100]);

// 2) the logo's carrier for the slide-out (C6): every letter hangs from this null. x = 960 + offset
var ride = comp.layers.addNull(DUR);
ride.name = "LOGO_RIDE";
tr(ride).property("ADBE Anchor Point").setValue([0, 0]);
tr(ride).property("ADBE Position").setValue([W / 2, H / 2]);
var rp = tr(ride).property("ADBE Position");
rp.dimensionsSeparated = true;
var rx = tr(ride).property("ADBE Position_0");
key(rx, T_OUT, W / 2, null, [0, 85]);
key(rx, DUR, W / 2 - 2700, [7000, 40], null);
ride.motionBlur = true;

// The letters move exactly like the menu's title intro (tools/title_logo_ae/build_title_logo.jsx, TitleLogoIntro in Godot):
// dropped right letter first at A's spot, tilted, land on the belt with a squash and two settling hops, ride the belt to
// their slots and click in; then the A-Q bar shoots out of Q into A's foot. Played at KSPD x speed (like the old S03),
// timed so that the belt stops (all letters seated) on the head of bar 2 = T_HIT.
var G = { speed: 125, firstLand: 1.95, fall: 0.60, height: 105, gap: 8, beltStart: 0.95, beltRamp: 0.60, stopRamp: 0.75,
          bridgeDelay: 0.55, bridgeTime: 0.50 };
var KSPD = 2.0;
var PC = {};
for (var pi = 0; pi < L.pieces.length; pi++) PC[L.pieces[pi].key] = L.pieces[pi];
var sched = [];
var landT = G.firstLand;
for (var oi = 0; oi < L.order.length; oi++) {
    var opc = PC[L.order[oi]];
    if (oi > 0) {
        var prv = PC[L.order[oi - 1]];
        landT += (prv.size[0] * 0.5 + opc.size[0] * 0.5 + G.gap) / G.speed;
    }
    var seatT = landT + Math.max(0, opc.slot[0] - L.landing_x) / G.speed;
    sched.push({ key: opc.key, piece: opc, land: landT, drop: landT - G.fall, seat: seatT, tilt: (oi % 2 === 0) ? 17 : -15 });
}
var stopAt = 0;
for (var si = 0; si < sched.length; si++) stopAt = Math.max(stopAt, sched[si].seat);
function tm(tg) { return T_HIT + (tg - stopAt) / KSPD; }      // game time -> comp time
function dt(d) { return d / KSPD; }
var CTRL = comp.layers.addNull(DUR);
CTRL.name = "CTRL";
var slp = CTRL.property("ADBE Effect Parade");
slp.addProperty("ADBE Slider Control").name = "Travel";      // belt travel, logical px (the ribs and rollers run with it)
CTRL.property("ADBE Effect Parade").addProperty("ADBE Slider Control").name = "Reveal";   // A-Q bar 0..1
var travel = CTRL.property("ADBE Effect Parade").property("Travel").property(1);
var reveal = CTRL.property("ADBE Effect Parade").property("Reveal").property(1);
var VG = G.speed * KSPD;                                       // logical px per comp second
var fullT = G.beltStart + G.beltRamp;
var dRamp = 0.5 * G.speed * G.beltRamp;
var dStop = dRamp + G.speed * (stopAt - fullT);
key(travel, tm(G.beltStart), 0, null, [0, 33.33]);
key(travel, tm(fullT), dRamp, [VG, 33.33], [VG, 33.33]);
key(travel, tm(stopAt), dStop, [VG, 33.33], [VG, 30]);
key(travel, tm(stopAt) + dt(G.stopRamp), dStop + 0.42 * G.speed * G.stopRamp, [0, 62], null);
var bridgeStart = stopAt + G.bridgeDelay, bridgeEnd = bridgeStart + G.bridgeTime;
key(reveal, tm(bridgeStart), 0, null, [0.45 / dt(G.bridgeTime), 33.33]);
key(reveal, tm(bridgeEnd), 1, [1.9 / dt(G.bridgeTime), 33.33], null);
var TRAVEL_PX = "(thisComp.layer('CTRL').effect('Travel')(1) * " + S + ")";
var RIDE_OFF = "(thisComp.layer('LOGO_RIDE').transform.xPosition - " + (W / 2) + ")";

// 3) the yellow line (C1): a stroked path revealed by Trim Paths, white hot tip in front
var line = shapeLayer(comp, "C1_LINE", [0, 0]);
var lg = group(line.property("ADBE Root Vectors Group"), "Line");
var lc = contents(lg);
poly(lc, [[-40, BELT_CY], [W + 40, BELT_CY]], false);
stroke(lc, YELLOW, 10);
var trim = lc.addProperty("ADBE Vector Filter - Trim");
trim.name = "TrimLine";   // named: the default name is localised (Japanese AE)
var tEnd = trim.property("ADBE Vector Trim End");
key(tEnd, 0, 0, null, [0, 70]);
key(tEnd, 0.30, 100, [380, 40], null);
var hot = group(line.property("ADBE Root Vectors Group"), "HotTrail");
var hc = contents(hot);
poly(hc, [[-40, BELT_CY], [W + 40, BELT_CY]], false);
stroke(hc, [1, 1, 1], 6);
var trim2 = hc.addProperty("ADBE Vector Filter - Trim");
trim2.property("ADBE Vector Trim End").expression = "thisLayer.content('Line').content('TrimLine').end";
trim2.property("ADBE Vector Trim Start").expression = "Math.max(thisLayer.content('Line').content('TrimLine').end - 14, 0)";
glow(line, 40, 22, 1.4);
var lo = tr(line).property("ADBE Opacity");
key(lo, T_OPEN, 100, null, [0, 33.33]);
key(lo, T_OPEN + 0.12, 0, null, null);
line.inPoint = 0; line.outPoint = T_OPEN + 0.13;

var tip = shapeLayer(comp, "C1_TIP", [-40, BELT_CY]);
var tg = contents(group(tip.property("ADBE Root Vectors Group"), "Spark"));
tg.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue([70, 34]);
fill(tg, [1, 1, 1]);
glow(tip, 20, 40, 2.2);
var tpx = tr(tip).property("ADBE Position");
tpx.expression = "var L = thisComp.layer('C1_LINE').content('Line').content('TrimLine').end / 100; [-40 + L * " + (W + 80) + ", value[1]]";
var to = tr(tip).property("ADBE Opacity");
key(to, 0.30, 100, null, [0, 33.33]);
key(to, 0.40, 0, null, null);
tip.inPoint = 0; tip.outPoint = 0.41;
tip.motionBlur = true;

// 4) the belt (C2 on): opens from the line with a small overshoot, ribs and rollers run with CTRL Travel
var belt = shapeLayer(comp, "BELT", [W / 2, BELT_CY]);
var broot = belt.property("ADBE Root Vectors Group");
var BW = BELT_X1 - BELT_X0, R = BELT_H / 2, SP = L.belt.rib_spacing * S;
// contents: first added = drawn on top
var rollers = group(broot, "Rollers");
var rlc = contents(rollers);
var ends = [-BW / 2 + R, BW / 2 - R];
for (var e = 0; e < 2; e++) {
    var rg = group(rlc, e === 0 ? "RollerL" : "RollerR");
    var rgt = rg.property("ADBE Vector Transform Group");
    rgt.property("ADBE Vector Position").setValue([ends[e], 0]);
    rgt.property("ADBE Vector Rotation").expression = TRAVEL_PX + " / " + (R - 2 * S) + " * 180 / Math.PI";
    var rgc = contents(rg);
    var cross = contents(group(rgc, "Cross"));
    rect(cross, [(R - 2 * S) * 2, 1.4 * S], [0, 0]);
    rect(cross, [1.4 * S, (R - 2 * S) * 2], [0, 0]);
    fill(cross, YELLOW);
    var hub = contents(group(rgc, "Hub"));
    hub.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue([(R - 2 * S) * 2, (R - 2 * S) * 2]);
    fill(hub, ROLLER_C);
}
var top = contents(group(broot, "TopEdge"));
rect(top, [BW - 2 * R, 2 * S], [0, -R + S]);
fill(top, YELLOW);
var ribs = group(broot, "Ribs");
var ribc = contents(ribs);
var nRibs = Math.floor((BW - 2 * R) / SP);
rect(ribc, [1.4 * S, BELT_H - 5.5 * S], [-BW / 2 + R + SP * 0.5, 0.25 * S]);
fill(ribc, RIB_C);
var rep = ribc.addProperty("ADBE Vector Filter - Repeater");
rep.property("ADBE Vector Repeater Copies").setValue(nRibs);
rep.property("ADBE Vector Repeater Transform").property("ADBE Vector Repeater Position").setValue([SP, 0]);
// the ribs move with the belt surface: same offset as the letters while they ride (modulo the spacing)
ribs.property("ADBE Vector Transform Group").property("ADBE Vector Position").expression =
    "var d = " + TRAVEL_PX + "; [((d % " + SP + ") + " + SP + ") % " + SP + " - " + SP / 2 + ", 0]";
var bot = contents(group(broot, "Bottom"));
rect(bot, [BW - 2 * R, 2 * S], [0, R - S]);
fill(bot, BOTTOM_C);
var body = contents(group(broot, "Body"));
rect(body, [BW, BELT_H], [0, 0], R);
fill(body, BELT_C);
var shadow = group(broot, "Shadow");
var shc = contents(shadow);
rect(shc, [BW, BELT_H], [L.shadow.offset[0] * S, L.shadow.offset[1] * S], R);
fill(shc, [0, 0, 0], 45);
// open: from a 7 px yellow line to the belt (overshoot), the colour comes from the line fading out on top
var bs = tr(belt).property("ADBE Scale");
key(bs, T_OPEN, [100, 7 / BELT_H * 100], null, [0, 20]);
key(bs, T_OPEN + 0.13, [100, 122], [0, 50], [0, 50]);
key(bs, T_OPEN + 0.21, [100, 93], [0, 50], [0, 50]);
key(bs, T_OPEN + 0.28, [100, 100], [0, 60], null);
var bo = tr(belt).property("ADBE Opacity");
key(bo, T_OPEN - 1 / FPS, 0, null, null);
key(bo, T_OPEN, 100, null, null);
bo.setInterpolationTypeAtKey(1, KeyframeInterpolationType.HOLD, KeyframeInterpolationType.HOLD);
// jolt at the stop, then slides out with the logo (C6)
var bpos = tr(belt).property("ADBE Position");
key(bpos, T_HIT, [W / 2, BELT_CY], null, [0, 33.33]);
key(bpos, T_HIT + 2 / FPS, [W / 2 - 6, BELT_CY + 7], [0, 50], [0, 50]);
key(bpos, T_HIT + 0.16, [W / 2, BELT_CY], [0, 60], null);
bpos.expression = "var o = " + RIDE_OFF + "; [value[0] + (time > " + T_OUT + " ? Math.min(o, 0) : 0), value[1]]";
belt.inPoint = T_OPEN - 1 / FPS;
belt.motionBlur = true;

// 5) letters (shapes from the menu logo): the game's drop / land / hop / ride / click-in, and the A-Q bar
function glyph(name, piece, anchorY) {
    var gl = comp.layers.addShape();
    gl.name = name;
    var gg = contents(group(gl.property("ADBE Root Vectors Group"), "Glyph"));
    for (var o = 0; o < piece.outlines.length; o++) {
        var pts = piece.outlines[o], verts = [];
        for (var v = 0; v < pts.length; v++) verts.push([pts[v][0] * S, pts[v][1] * S]);
        poly(gg, verts, true);
    }
    fill(gg, [1, 1, 1]);
    tr(gl).property("ADBE Anchor Point").setValue([0, anchorY]);
    var ds = fx(gl, "ADBE Drop Shadow");
    ds.property("ADBE Drop Shadow-0001").setValue([0, 0, 0, 1]);
    var dop = ds.property("ADBE Drop Shadow-0002");
    dop.setValue(dop.maxValue > 100 ? L.shadow.alpha * 255 : L.shadow.alpha * 100);
    ds.property("ADBE Drop Shadow-0003").setValue(135);
    ds.property("ADBE Drop Shadow-0004").setValue(Math.sqrt(2) * L.shadow.offset[0] * S);
    ds.property("ADBE Drop Shadow-0005").setValue(0);
    gl.motionBlur = true;
    return gl;
}
var glyphs = [];
var landX = P(L.landing_x, 0)[0] - W / 2;                 // relative to LOGO_RIDE
var restY = YT + L.baseline * S - H / 2;                   // every letter's baseline
var vK = G.speed * S * KSPD;                               // px per comp second
var DROP = G.height * S;
for (var n = 0; n < sched.length; n++) {
    var Sc = sched[n], pc = Sc.piece;
    var baseOff = (L.baseline - pc.slot[1]) * S;
    var restX = P(pc.slot[0], 0)[0] - W / 2;
    var M = comp.layers.addNull(DUR);
    M.name = "M_" + Sc.key;
    M.parent = ride;
    tr(M).property("ADBE Anchor Point").setValue([0, 0]);
    tr(M).property("ADBE Position").dimensionsSeparated = true;
    var mx = tr(M).property("ADBE Position_0"), my = tr(M).property("ADBE Position_1");
    var mr = tr(M).property("ADBE Rotate Z");
    var gl = glyph("L_" + Sc.key, pc, baseOff);
    gl.parent = M;
    tr(gl).property("ADBE Position").setValue([0, 0]);
    var tDrop = tm(Sc.drop), tLand = tm(Sc.land), tSeat = tm(Sc.seat), ridden = Sc.seat - Sc.land;
    gl.inPoint = tDrop;
    // X: falls straight at A's spot, rides the belt at belt speed, clicks into its slot
    key(mx, tDrop, landX, null, [0, 33.33]);
    if (ridden > 0.001) {
        key(mx, tLand, landX, [0, 33.33], [vK, 33.33]);
        key(mx, tSeat, restX, [vK, 33.33], [vK, 40]);
        key(mx, tSeat + dt(0.06), restX + 2.6 * S, [0, 45], [0, 40]);
        key(mx, tSeat + dt(0.32), restX, [0, 72], null);
    } else {
        key(mx, tLand, landX, [0, 33.33], [0.5 * vK, 40]);
        key(mx, tLand + dt(0.07), landX + 1.4 * S, [0, 45], [0, 40]);
        key(mx, tLand + dt(0.32), landX, [0, 72], null);
    }
    // Y: gravity, lands, two settling hops
    var impact = 2 * DROP / dt(G.fall), h1 = 6 * S, h2 = 1.6 * S;
    key(my, tDrop, restY - DROP, null, [0, 33.33]);
    key(my, tLand, restY, [impact, 33.33], [-2 * h1 / dt(0.14), 33.33]);
    key(my, tLand + dt(0.14), restY - h1, [0, 50], [0, 50]);
    key(my, tLand + dt(0.28), restY, [2 * h1 / dt(0.14), 33.33], [-2 * h2 / dt(0.08), 33.33]);
    key(my, tLand + dt(0.36), restY - h2, [0, 50], [0, 50]);
    key(my, tLand + dt(0.44), restY, [2 * h2 / dt(0.08), 40], null);
    // tilted while falling, straightens as it lands, a small wobble
    key(mr, tDrop, Sc.tilt, null, [0, 33.33]);
    key(mr, tLand, 0, [0, 62], [0, 40]);
    var w = Sc.tilt > 0 ? -1 : 1;
    key(mr, tLand + dt(0.12), 3.5 * w, [0, 50], [0, 50]);
    key(mr, tLand + dt(0.27), -1.2 * w, [0, 50], [0, 50]);
    key(mr, tLand + dt(0.42), 0, [0, 60], null);
    // fade in at the top of the fall; squash on landing, stretch at the top of the hop; a firm squash in the slot
    var go = tr(gl).property("ADBE Opacity"), gs = tr(gl).property("ADBE Scale");
    key(go, tDrop, 0, null, [0, 33.33]);
    key(go, tDrop + dt(0.10), 100, [0, 33.33], null);
    key(gs, tLand - 1 / FPS, [100, 100], null, null);
    key(gs, tLand + dt(0.06), [111, 86], [0, 40], [0, 40]);
    key(gs, tLand + dt(0.15), [97, 104], [0, 45], [0, 45]);
    key(gs, tLand + dt(0.27), [100, 100], [0, 45], [0, 45]);
    key(gs, tLand + dt(0.31), [103, 96], [0, 45], [0, 45]);
    key(gs, tLand + dt(0.39), [100, 100], [0, 50], null);
    if (ridden >= 0.45) {
        key(gs, tSeat, [100, 100], null, [0, 40]);
        key(gs, tSeat + dt(0.05), [104, 93], [0, 45], [0, 45]);
        key(gs, tSeat + dt(0.22), [100, 100], [0, 60], null);
    }
    glyphs.push(gl);
    glyphs.push(M);
    // dust: two puffs to each side of the landing foot
    for (var side = -1; side <= 1; side += 2) {
        for (var j = 0; j < 2; j++) {
            var dl = comp.layers.addShape();
            dl.name = "DUST_" + Sc.key + "_" + (side < 0 ? "L" : "R") + j;
            var dc = contents(group(dl.property("ADBE Root Vectors Group"), "Puff"));
            var radius = (1.8 + rnd() * 1.2) * S;
            dc.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue([radius * 2, radius * 2]);
            fill(dc, [0.95, 0.96, 1.0]);
            var life = dt(0.38 + rnd() * 0.14);
            var sx = P(L.landing_x + side * pc.size[0] * 0.4, 0)[0], sy = YT + (L.belt_rect[1] - 1) * S;
            var ex = sx + side * (9 + rnd() * 8) * S, ey = sy - (3 + rnd() * 4) * S;
            dl.inPoint = tLand; dl.outPoint = tLand + life;
            var dp = tr(dl).property("ADBE Position");
            key(dp, tLand, [sx, sy], null, [1.8 * Math.abs(ex - sx) / life, 20]);
            key(dp, tLand + life, [ex, ey], [0, 75], null);
            var dsc = tr(dl).property("ADBE Scale");
            key(dsc, tLand, [70, 70], null, [0, 20]);
            key(dsc, tLand + life, [140, 140], [0, 70], null);
            var dop2 = tr(dl).property("ADBE Opacity");
            key(dop2, tLand, 75, null, [0, 33.33]);
            key(dop2, tLand + life, 0, [0, 25], null);
            glyphs.push(dl);
        }
    }
}
// the A-Q bar: fixed in its slot, uncovered by a mask from Q towards A's foot (CTRL Reveal)
var BR = L.bridge, bpc = PC[BR.key];
var bridge = glyph("L_" + BR.key, bpc, 0);
bridge.parent = ride;
var bslot = P(bpc.slot[0], bpc.slot[1]);
tr(bridge).property("ADBE Position").setValue([bslot[0] - W / 2, bslot[1] - H / 2]);
bridge.inPoint = tm(bridgeStart);
var bmask = bridge.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
bmask.name = "Reveal";
bmask.property("ADBE Mask Shape").expression = [
    "var rv = thisComp.layer('CTRL').effect('Reveal')(1).value;",
    "var K = " + S + ", ax = [" + BR.axis[0] + ", " + BR.axis[1] + "];",
    "var cut = (" + BR.max + " + (" + BR.min + " - " + BR.max + ") * rv) * K;",
    "var px = -ax[1], py = ax[0], big = 4000, ox = ax[0] * cut, oy = ax[1] * cut;",
    "createPath([[ox + px * big, oy + py * big], [ox - px * big, oy - py * big],",
    "  [ox - px * big + ax[0] * big, oy - py * big + ax[1] * big], [ox + px * big + ax[0] * big, oy + py * big + ax[1] * big]], [], [], true);"
].join("\n");
glyphs.unshift(bridge);

// 6) the stop (C4): diagonal slashes, light streaks, white flash
var slash = shapeLayer(comp, "C4_SLASHES", [W / 2, YT + L.logo_size[1] * S / 2]);
var sroot = slash.property("ADBE Root Vectors Group");
var LL = LOGO_L - W / 2, RR = LOGO_R - W / 2;   // logo ends, relative to the layer (logo centre)
var SL = [  // [x, y, length, thickness, colour] around the logo, all at -60 degrees
    [LL - 30, -50, 620, 60, YELLOW], [LL + 80, 60, 380, 22, [1, 1, 1]],
    [RR + 30, -40, 660, 64, YELLOW], [RR - 80, 70, 400, 22, [1, 1, 1]],
    [-260, -190, 440, 24, [1, 1, 1]], [300, 200, 480, 30, YELLOW]
];
for (var k = 0; k < SL.length; k++) {
    var a = SL[k];
    var sg = group(sroot, "Slash" + k);
    var sgc = contents(sg);
    var dx = Math.cos(-60 * Math.PI / 180) * a[2] / 2, dy = Math.sin(-60 * Math.PI / 180) * a[2] / 2;
    poly(sgc, [[a[0] - dx - a[3] / 2, a[1] - dy], [a[0] - dx + a[3] / 2, a[1] - dy], [a[0] + dx + a[3] / 2, a[1] + dy], [a[0] + dx - a[3] / 2, a[1] + dy]], true);
    fill(sgc, a[4]);
}
var sls = tr(slash).property("ADBE Scale");
key(sls, T_HIT, [60, 60], null, [0, 20]);
key(sls, T_HIT + 0.07, [104, 104], [0, 50], [0, 50]);
key(sls, T_HIT + 0.45, [112, 112], [0, 50], null);
var slo = tr(slash).property("ADBE Opacity");
key(slo, T_HIT, 100, null, null);
key(slo, T_HIT + 0.30, 100, null, [0, 50]);
key(slo, T_HIT + 0.48, 0, [0, 50], null);
slash.inPoint = T_HIT; slash.outPoint = T_HIT + 0.5;

var streak = shapeLayer(comp, "C4_STREAKS", [0, 0]);
var stc = contents(group(streak.property("ADBE Root Vectors Group"), "Streaks"));
for (var s2 = 0; s2 < 14; s2++) {
    var yy = YT + (0.1 + rnd() * 0.8) * L.logo_size[1] * S;
    var left = s2 % 2 === 0;
    var l0 = 40 + rnd() * 100, l1 = l0 + 420 + rnd() * 700;
    if (left) poly(stc, [[LOGO_L - l0, yy], [LOGO_L - l1, yy]], false);
    else poly(stc, [[LOGO_R + l0, yy], [LOGO_R + l1, yy]], false);
}
stroke(stc, [1, 1, 1], 6);
var trim3 = stc.addProperty("ADBE Vector Filter - Trim");
var t3s = trim3.property("ADBE Vector Trim Start"), t3e = trim3.property("ADBE Vector Trim End");
key(t3e, T_HIT, 0, null, [0, 15]);
key(t3e, T_HIT + 0.12, 100, [0, 60], null);
key(t3s, T_HIT + 0.08, 0, null, [0, 20]);
key(t3s, T_HIT + 0.42, 100, [0, 60], null);
glow(streak, 30, 18, 1.3);
streak.inPoint = T_HIT; streak.outPoint = T_HIT + 0.45;

var flash = comp.layers.addSolid([1, 1, 1], "C4_FLASH", W, H, 1.0, DUR);
flash.blendingMode = BlendingMode.ADD;
var fo = tr(flash).property("ADBE Opacity");
key(fo, T_HIT - 1 / FPS, 0, null, null);
key(fo, T_HIT, 40, null, [0, 20]);
key(fo, T_HIT + 0.2, 0, [0, 70], null);
flash.inPoint = T_HIT - 1 / FPS; flash.outPoint = T_HIT + 0.21;

// 7) hold (C5): sparkles around the logo, camera flashes in the stands (right)
var spark = shapeLayer(comp, "C5_SPARKLES", [0, 0]);
var sproot = spark.property("ADBE Root Vectors Group");
var SPK = [[LOGO_L - 40, YT + 30], [LOGO_L + 300, YT - 30], [W / 2 + 80, YT - 40], [LOGO_R - 120, YT - 20], [LOGO_R + 50, YT + 120],
           [LOGO_R - 40, BELT_TOP + 80], [W / 2 - 220, BELT_TOP + 90], [LOGO_L + 120, BELT_TOP + 70], [W / 2 + 330, YT + 110], [LOGO_L + 640, YT + 20]];
for (var q = 0; q < SPK.length; q++) {
    var sg2 = group(sproot, "Spark" + q);
    var sgt = sg2.property("ADBE Vector Transform Group");
    sgt.property("ADBE Vector Position").setValue(SPK[q]);
    var c2 = contents(sg2);
    star(c2, [0, 0], 14 + rnd() * 16, 2.0, rnd() * 15);
    fill(c2, [1, 1, 1]);
    var t0 = T_HIT + 0.18 + rnd() * (T_OUT - T_HIT - 0.5);
    var gsc = sgt.property("ADBE Vector Scale");
    key(gsc, t0, [0, 0], null, [0, 40]);
    key(gsc, t0 + 0.12, [110, 110], [0, 50], [0, 50]);
    key(gsc, t0 + 0.30, [0, 0], [0, 60], null);
}
glow(spark, 30, 14, 1.0);
spark.inPoint = T_HIT; spark.outPoint = T_OUT + 0.3;

var crowd = shapeLayer(comp, "C5_CROWD_FLASHES", [0, 0]);
var croot = crowd.property("ADBE Root Vectors Group");
for (var cf = 0; cf < 14; cf++) {
    var cg = group(croot, "Flash" + cf);
    var cgt = cg.property("ADBE Vector Transform Group");
    cgt.property("ADBE Vector Position").setValue([1630 + rnd() * 270, 400 + rnd() * 120]);
    var c3 = contents(cg);
    star(c3, [0, 0], 10 + rnd() * 10, 1.6, rnd() * 20);
    fill(c3, [1, 1, 1]);
    var t1 = T_HIT + 0.1 + rnd() * (T_OUT - T_HIT - 0.2);
    var fop = cg.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity");
    key(fop, t1 - 1 / FPS, 0, null, null);
    key(fop, t1, 100, null, null);
    key(fop, t1 + 4 / FPS, 0, null, null);
}
glow(crowd, 20, 12, 1.4);
crowd.blendingMode = BlendingMode.ADD;
crowd.inPoint = T_HIT; crowd.outPoint = T_OUT + 0.2;

// 8) camera: zoom punch at the stop, slow 4% push-in while holding (Transform effect on an adjustment layer)
var cam = comp.layers.addSolid([1, 1, 1], "CAM_punch_push (adjustment)", W, H, 1.0, DUR);
cam.adjustmentLayer = true;
var xf = fx(cam, "ADBE Geometry2");
var xfs = xf.property("ADBE Geometry2-0003");          // Scale (uniform)
key(xfs, T_HIT, 100, null, [0, 20]);
key(xfs, T_HIT + 3 / FPS, 107, [0, 50], [0, 50]);
key(xfs, T_HIT + 0.24, 100.5, [0, 60], [0, 33.33]);
key(xfs, T_OUT, 104, null, [0, 33.33]);
setP(xf, "ADBE Geometry2-0009", 0);                     // use the comp shutter: off
setP(xf, "ADBE Geometry2-0010", 180);

// 9) wipe to S04 (C6): a big yellow diagonal band from the right, with a white leading edge
var wipe = shapeLayer(comp, "C6_WIPE", [W + 500, 0]);
var wroot = wipe.property("ADBE Root Vectors Group");
var edge = contents(group(wroot, "Edge"));
poly(edge, [[-70, -100], [-10, -100], [-410, H + 100], [-470, H + 100]], true);
fill(edge, [1, 1, 1]);
var band = contents(group(wroot, "Band"));
poly(band, [[0, -100], [2600, -100], [2200, H + 100], [-400, H + 100]], true);
fill(band, YELLOW);
var wp = tr(wipe).property("ADBE Position");
key(wp, T_OUT, [W + 520, 0], null, [0, 60]);
key(wp, DUR, [-120, 0], [5200, 40], null);
wipe.inPoint = T_OUT; wipe.outPoint = DUR;
wipe.motionBlur = true;

// layer order (top to bottom): wipe, camera, flash, streaks, slashes, sparkles/crowd, A-Q bar, letters + dust, belt, line+tip, nulls, background
wipe.moveToBeginning();
cam.moveAfter(wipe);
flash.moveAfter(cam);
streak.moveAfter(flash);
slash.moveAfter(streak);
spark.moveAfter(slash);
crowd.moveAfter(spark);
var last = crowd;
for (var gi = 0; gi < glyphs.length; gi++) { glyphs[gi].moveAfter(last); last = glyphs[gi]; }
belt.moveAfter(last);
tip.moveAfter(belt);
line.moveAfter(tip);
ride.moveAfter(line);
CTRL.moveAfter(ride);
bg.moveToEnd();

var mk = comp.markerProperty;
var marks = [[0, "C1 line (bar 4 of the PV)"], [T_OPEN, "C2 belt opens"], [tm(sched[0].drop), "C3 letters drop (game motion x" + KSPD + ")"],
             [T_HIT, "C4 STOP: all seated (bar 5 head)"], [tm(bridgeStart), "A-Q bar"], [T_HOLD, "C5 hold"], [T_OUT, "C6 slide out + wipe to S04"]];
for (var m = 0; m < marks.length; m++) mk.setValueAtTime(marks[m][0], new MarkerValue(marks[m][1]));

// expression check
var errors = [];
function scan(g, path) {
    for (var z = 1; z <= g.numProperties; z++) {
        var pr = g.property(z);
        if (pr.propertyType === PropertyType.PROPERTY) {
            if (pr.canSetExpression && pr.expression !== "" && pr.expressionError !== "") errors.push(path + "/" + pr.name + ": " + pr.expressionError);
        } else scan(pr, path + "/" + pr.name);
    }
}
for (var li = 1; li <= comp.numLayers; li++) scan(comp.layer(li), comp.layer(li).name);

comp.openInViewer();
proj.save(new File(SAVE_AS));
app.endSuppressDialogs(false);
var times = [];
for (var tq = 0; tq < sched.length; tq++) times.push([sched[tq].key, Math.round(tm(sched[tq].drop) * 1000) / 1000, Math.round(tm(sched[tq].land) * 1000) / 1000, Math.round(tm(sched[tq].seat) * 1000) / 1000]);
return { comp: comp.name, layers: comp.numLayers, duration: DUR, logo: [LOGO_L, LOGO_R], belt: [BELT_TOP, BELT_TOP + BELT_H],
         drop_land_seat: times, bridge: [tm(bridgeStart), tm(bridgeEnd)], errors: errors, saved: proj.file ? proj.file.fsName : null };
