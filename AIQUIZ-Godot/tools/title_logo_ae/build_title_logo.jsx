// AIQUIZ main-menu title intro -- After Effects builder (ExtendScript ES3, ASCII only).
//
// Builds tools/title_logo_ae/AIQUIZ_TitleLogo.aep from scratch in the RUNNING After Effects
// (the open project is closed WITHOUT saving -- save your work first):
//   node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/build_title_logo.jsx
// Input: tools/title_logo_ae/layout.json (export_layout.gd: letter shapes, slots, belt, bar).
// Then sample_title_logo.jsx writes the motion Godot plays (TitleLogoIntro).
//
// Comp "TitleLogo_Intro": 60 fps. One comp pixel = 1/K logical pixel of the menu (K = 4);
// comp (0,0) is logical (OX, OY) of the TitleLogo holder.
//   CTRL      null with sliders Form (0 bar .. 1 conveyor), Travel (belt distance, logical px), Reveal (A-Q bar 0..1)
//   BELT      the conveyor, drawn by expressions from CTRL (TitleLogoIntro._draw does the same maths)
//   M_<key>   null at the letter's baseline point: falls, rides the belt (X/Y separated), tilts
//   L_<key>   the letter (shape paths from the logo); squash & stretch around the baseline
//   L_d1      the A-Q bar; a mask (expression of Reveal) uncovers it from Q down to A's foot
//   DUST_<n>  landing puffs
//   BG_Preview  backdrop for previews only (Godot ignores it)
// Motion notes: everything is slower than the old procedural version. Letters fall tilted, land with a squash and
// two small settling hops, and click into their slots; nothing hops at the end. The A-Q bar shoots out of Q and keeps accelerating
// smoothly into A's foot (Reveal keys: 0.45x the average speed out of Q, 1.9x into A); no sparks, no shake.

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var AEP = ROOT + "tools/title_logo_ae/AIQUIZ_TitleLogo.aep";
var LAYOUT = ROOT + "tools/title_logo_ae/layout.json";
var FPS = 60, K = 4, OX = -30, OY = -140, CW = 1240, CH = 960;

// ---------- timing (seconds) ----------
var T = {
  deploy: 0.35, deployPeak: 1.08, deployEnd: 1.34, deployOver: 1.04,
  beltStart: 0.95, beltRamp: 0.60, speed: 125,          // logical px / s
  firstLand: 1.95, fall: 0.60, height: 105, gap: 8,
  stopRamp: 0.75,
  bridgeDelay: 0.55, bridgeTime: 0.50,
  collapseDelay: 0.45, collapseTime: 0.95, tail: 0.12
};

function readJson(path) {
  var f = new File(path);
  f.encoding = "UTF-8";
  if (!f.open("r")) throw new Error("cannot open " + path);
  var s = f.read();
  f.close();
  return JSON.parse(s);
}

var L = readJson(LAYOUT);
function cx(x) { return (x - OX) * K; }
function cy(y) { return (y - OY) * K; }
function rnd(seed) { var s = seed; return function () { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; }; }

// ---------- keyframe helpers ----------
// key(prop, t, value, inEase, outEase); ease = [speed, influence] (speed in property units / s) or null (= [0, 33.33]).
function ease(e, dims) {
  var a = [];
  var sp = e ? e[0] : 0, inf = e ? e[1] : 33.33;
  for (var i = 0; i < dims; i++) a.push(new KeyframeEase(sp, inf));
  return a;
}
function key(prop, t, value, inE, outE) {
  prop.setValueAtTime(t, value);
  var i = prop.nearestKeyIndex(t);
  prop.setInterpolationTypeAtKey(i, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
  var dims = prop.keyInTemporalEase(i).length;
  prop.setTemporalContinuousAtKey(i, false);
  prop.setTemporalEaseAtKey(i, ease(inE, dims), ease(outE, dims));
  if (prop.isSpatial) { prop.setSpatialAutoBezierAtKey(i, false); prop.setSpatialContinuousAtKey(i, false); }
}

function tr(layer) { return layer.property("ADBE Transform Group"); }
// add every slider first: adding an effect invalidates references to the earlier ones
function sliders(layer, names) {
  var parade = layer.property("ADBE Effect Parade");
  for (var i = 0; i < names.length; i++) parade.addProperty("ADBE Slider Control").name = names[i];
  var out = {};
  for (var j = 0; j < names.length; j++) out[names[j]] = layer.property("ADBE Effect Parade").property(names[j]).property(1);
  return out;
}

function addRect(group, name) {
  var g = group.addProperty("ADBE Vector Group"); g.name = name;
  var c = g.property("ADBE Vectors Group");
  var r = c.addProperty("ADBE Vector Shape - Rect");
  return { group: g, contents: c, shape: r };
}
function addFill(contents, rgb, name) {
  var f = contents.addProperty("ADBE Vector Graphic - Fill");
  if (name) f.name = name;
  f.property("ADBE Vector Fill Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
  return f;
}

app.beginSuppressDialogs();
if (app.project) app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
app.newProject();
var proj = app.project;
proj.bitsPerChannel = 16;
var folder = proj.items.addFolder("AIQUIZ_TitleLogo");

// ---------- schedule (same rules as before: drop right letter first, keep a gap on the belt) ----------
var pieces = {};
for (var p = 0; p < L.pieces.length; p++) pieces[L.pieces[p].key] = L.pieces[p];
var V = T.speed;
var landing = L.landing_x;
var full = T.beltStart + T.beltRamp;
var sched = [];
var land = T.firstLand;
for (var i = 0; i < L.order.length; i++) {
  var pc = pieces[L.order[i]];
  if (i > 0) {
    var prev = pieces[L.order[i - 1]];
    land += (prev.size[0] * 0.5 + pc.size[0] * 0.5 + T.gap) / V;
  }
  var seat = land + Math.max(0, pc.slot[0] - landing) / V;
  sched.push({ key: pc.key, piece: pc, land: land, drop: land - T.fall, seat: seat, tilt: (i % 2 === 0) ? 17 : -15 });
}
var lastSeat = 0;
for (var s2 = 0; s2 < sched.length; s2++) lastSeat = Math.max(lastSeat, sched[s2].seat);
var stopAt = lastSeat;
var stopEnd = stopAt + T.stopRamp;
var bridgeStart = stopAt + T.bridgeDelay;
var bridgeEnd = bridgeStart + T.bridgeTime;
var collapse = bridgeEnd + T.collapseDelay;
var collapseEnd = collapse + T.collapseTime;
var DUR = Math.ceil((collapseEnd + T.tail) * FPS) / FPS;

var comp = proj.items.addComp("TitleLogo_Intro", CW, CH, 1, DUR, FPS);
comp.parentFolder = folder;
comp.bgColor = [0.12, 0.16, 0.24];
comp.motionBlur = false;

// ---------- backdrop (preview only) ----------
var bg = comp.layers.addSolid([0.30, 0.42, 0.58], "BG_Preview", CW, CH, 1, DUR);
var bgFx = bg.property("ADBE Effect Parade").addProperty("ADBE Ramp");
bgFx.property("ADBE Ramp-0001").setValue([CW / 2, 0]);
bgFx.property("ADBE Ramp-0002").setValue([0.36, 0.52, 0.70, 1]);
bgFx.property("ADBE Ramp-0003").setValue([CW / 2, CH]);
bgFx.property("ADBE Ramp-0004").setValue([0.16, 0.22, 0.34, 1]);
bg.locked = true;

// ---------- controls ----------
var ctrl = comp.layers.addNull(DUR);
ctrl.name = "CTRL";
ctrl.label = 9;
var sl = sliders(ctrl, ["Form", "Travel", "Reveal"]);
var form = sl.Form, travel = sl.Travel, reveal = sl.Reveal;

// Form: the yellow bar stretches, thickens and lifts into the conveyor (small overshoot), and back at the end.
key(form, T.deploy, 0, null, [0, 45]);
key(form, T.deployPeak, T.deployOver, [0, 55], [0, 40]);
key(form, T.deployEnd, 1, [0, 60], null);
key(form, collapse, 1, null, [0, 62]);
key(form, collapseEnd, 0, [0, 78], null);

// Travel: constant acceleration up to V, constant speed while letters ride, long soft stop.
var dRamp = 0.5 * V * T.beltRamp;
var dStop = dRamp + V * (stopAt - full);
key(travel, T.beltStart, 0, null, [0, 33.33]);
key(travel, full, dRamp, [V, 33.33], [V, 33.33]);
key(travel, stopAt, dStop, [V, 33.33], [V, 30]);
key(travel, stopEnd, dStop + 0.42 * V * T.stopRamp, [0, 62], null);

// Reveal: one long, smooth S-curve -- starts gently out of Q, glides, and settles into A's foot.
// Reveal: shoots out of Q's notch at once (0.45x the average speed), keeps accelerating smoothly and hits
// A's foot at full speed (1.9x the average speed). Hermite influences (33.33 %) keep the speed curve smooth.
key(reveal, bridgeStart, 0, null, [0.45 / T.bridgeTime, 33.33]);
key(reveal, bridgeEnd, 1, [1.9 / T.bridgeTime, 33.33], null);

// ---------- belt (expressions mirror TitleLogoIntro._draw) ----------
var bar = L.bar_rect, beltR = L.belt_rect, B = L.belt;
var PRE = [
  "var C = thisComp.layer('CTRL');",
  "var f = C.effect('Form')(1).value, dist = C.effect('Travel')(1).value;",
  "var K = " + K + ", OX = " + OX + ", OY = " + OY + ";",
  "function cl(x, a, b) { return Math.min(Math.max(x, a), b); }",
  "function ss(a, b, x) { var t = cl((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }",
  "function lp(a, b, t) { return a + (b - a) * t; }",
  "function P(x, y) { return [(x - OX) * K, (y - OY) * K]; }",
  "var ex = ss(0, 1, cl(f / 0.6, 0, 1)), ey = Math.max((f - 0.35) / 0.65, 0);",
  "var x0 = lp(" + bar[0] + ", " + beltR[0] + ", ex), x1 = lp(" + (bar[0] + bar[2]) + ", " + (beltR[0] + beltR[2]) + ", ex);",
  "var y0 = lp(" + bar[1] + ", " + beltR[1] + ", ss(0, 1, Math.min(ey, 1))), h = lp(" + bar[3] + ", " + B.height + ", ey);",
  "var belt = ss(0.25, 0.75, f), r = h * 0.5 * belt;",
  ""
].join("\n");
function col(c) { return "[" + c[0] + ", " + c[1] + ", " + c[2] + "]"; }
var MIX = "function mix(a, b, t) { return [lp(a[0], b[0], t), lp(a[1], b[1], t), lp(a[2], b[2], t), 1]; }\n";

var beltLayer = comp.layers.addShape();
beltLayer.name = "BELT";
beltLayer.label = 11;
tr(beltLayer).property("ADBE Position").setValue([0, 0]);
tr(beltLayer).property("ADBE Anchor Point").setValue([0, 0]);
var root = beltLayer.property("ADBE Root Vectors Group");

// stadium = middle rect + two round ends (or one plain rect while r <= 0.25), like _draw_stadium
function stadium(name, dx, dy, fillExpr, opacityExpr) {
  var g = root.addProperty("ADBE Vector Group"); g.name = name;
  var c = g.property("ADBE Vectors Group");
  var off = "var dx = " + dx + ", dy = " + dy + ";\n";
  var mid = c.addProperty("ADBE Vector Shape - Rect"); mid.name = "Mid";
  mid.property("ADBE Vector Rect Size").expression = PRE + off + "var w = r <= 0.25 ? x1 - x0 : Math.max(x1 - x0 - 2 * r, 0); [w * K, h * K];";
  mid.property("ADBE Vector Rect Position").expression = PRE + off + "P((x0 + x1) / 2 + dx, y0 + h / 2 + dy);";
  var names = ["EndL", "EndR"];
  for (var e = 0; e < 2; e++) {
    var el = c.addProperty("ADBE Vector Shape - Ellipse"); el.name = names[e];
    el.property("ADBE Vector Ellipse Size").expression = PRE + "var d = r <= 0.25 ? 0 : 2 * Math.min(r, h / 2) * K; [d, d];";
    el.property("ADBE Vector Ellipse Position").expression = PRE + off + "P(" + (e === 0 ? "x0 + r" : "x1 - r") + " + dx, y0 + h / 2 + dy);";
  }
  var fill = c.addProperty("ADBE Vector Graphic - Fill");
  fill.property("ADBE Vector Fill Color").expression = PRE + MIX + fillExpr;
  g.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + opacityExpr;
  return g;
}
// contents are drawn bottom-up from the LAST group, so add top-most first
var top = addRect(root, "TopEdge");
top.shape.property("ADBE Vector Rect Size").expression = PRE + "[Math.max(x1 - x0 - 2 * r, 0) * K, 2 * K];";
top.shape.property("ADBE Vector Rect Position").expression = PRE + "P((x0 + x1) / 2, y0 + 1);";
addFill(top.contents, B.bar_color);
top.group.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + "(belt > 0 && x1 - x0 > r * 2) ? 100 : 0;";

var rollers = root.addProperty("ADBE Vector Group"); rollers.name = "Rollers";
rollers.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression =
  PRE + "var hub = Math.max(r - 2, 0) * ss(0.55, 1, f); (belt > 0 && hub > 0.3) ? 100 : 0;";
var rc = rollers.property("ADBE Vectors Group");
var HUB = "var hub = Math.max(r - 2, 0) * ss(0.55, 1, f);\n";
var rnames = ["RollerL", "RollerR"];
for (var rr = 0; rr < 2; rr++) {
  var rg = rc.addProperty("ADBE Vector Group"); rg.name = rnames[rr];
  var rgt = rg.property("ADBE Vector Transform Group");
  rgt.property("ADBE Vector Position").expression = PRE + "P(" + (rr === 0 ? "x0 + r" : "x1 - r") + ", y0 + h / 2);";
  rgt.property("ADBE Vector Rotation").expression = PRE + "dist / Math.max(r, 1) * 180 / Math.PI;";
  var rgc = rg.property("ADBE Vectors Group");
  var dot = rgc.addProperty("ADBE Vector Group"); dot.name = "Dot";
  var de = dot.property("ADBE Vectors Group").addProperty("ADBE Vector Shape - Ellipse");
  de.property("ADBE Vector Ellipse Size").expression = PRE + HUB + "[hub * 0.7 * K, hub * 0.7 * K];";
  addFill(dot.property("ADBE Vectors Group"), B.bar_color);
  var cross = rgc.addProperty("ADBE Vector Group"); cross.name = "Cross";
  var cc = cross.property("ADBE Vectors Group");
  var ca = cc.addProperty("ADBE Vector Shape - Rect");
  ca.property("ADBE Vector Rect Size").expression = PRE + HUB + "[hub * 2 * K, 1.2 * K];";
  var cb = cc.addProperty("ADBE Vector Shape - Rect");
  cb.property("ADBE Vector Rect Size").expression = PRE + HUB + "[1.2 * K, hub * 2 * K];";
  addFill(cc, B.bar_color);
  var hubG = rgc.addProperty("ADBE Vector Group"); hubG.name = "Hub";
  var he = hubG.property("ADBE Vectors Group").addProperty("ADBE Vector Shape - Ellipse");
  he.property("ADBE Vector Ellipse Size").expression = PRE + HUB + "[hub * 2 * K, hub * 2 * K];";
  addFill(hubG.property("ADBE Vectors Group"), B.roller_color);
}

var ribs = addRect(root, "Ribs");
var RIB0 = "var xs = x0 + r + (((dist % " + B.rib_spacing + ") + " + B.rib_spacing + ") % " + B.rib_spacing + ");\n";
ribs.shape.property("ADBE Vector Rect Size").expression = PRE + "[1.4 * K, Math.max(h - 5.5, 0) * K];";
ribs.shape.property("ADBE Vector Rect Position").expression = PRE + RIB0 + "P(xs, y0 + 3 + (h - 5.5) / 2);";
addFill(ribs.contents, B.rib_color);
var rep = ribs.contents.addProperty("ADBE Vector Filter - Repeater");
rep.property("ADBE Vector Repeater Copies").expression =
  PRE + RIB0 + "xs < x1 - r ? Math.floor((x1 - r - xs) / " + B.rib_spacing + " - 1e-6) + 1 : 0;";
rep.property("ADBE Vector Repeater Transform").property("ADBE Vector Repeater Position").setValue([B.rib_spacing * K, 0]);
ribs.group.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression =
  PRE + "belt > 0 ? ss(0.6, 1, f) * 100 : 0;";

var bottom = addRect(root, "Bottom");
bottom.shape.property("ADBE Vector Rect Size").expression = PRE + "[(x1 - x0 - r * 2) * K, 2 * K];";
bottom.shape.property("ADBE Vector Rect Position").expression = PRE + "P((x0 + x1) / 2, y0 + h - 1);";
var bf = bottom.contents.addProperty("ADBE Vector Graphic - Fill");
bf.property("ADBE Vector Fill Color").expression = PRE + MIX + "mix(" + col(B.bar_color) + ", " + col(B.bottom_color) + ", belt);";
bottom.group.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + "belt > 0 ? 100 : 0;";

stadium("Body", 0, 0, "mix(" + col(B.bar_color) + ", " + col(B.belt_color) + ", belt);", "100;");
stadium("Shadow", L.shadow.offset[0], L.shadow.offset[1], "[0, 0, 0, 1];", "45 * belt;");

// ---------- letters ----------
function glyphLayer(name, piece, anchorY) {
  var layer = comp.layers.addShape();
  layer.name = name;
  layer.label = 1;
  var g = layer.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  g.name = "Glyph";
  var c = g.property("ADBE Vectors Group");
  for (var o = 0; o < piece.outlines.length; o++) {
    var pts = piece.outlines[o], verts = [];
    for (var v = 0; v < pts.length; v++) verts.push([pts[v][0] * K, pts[v][1] * K]);
    var sh = new Shape();
    sh.vertices = verts;
    sh.closed = true;
    var path = c.addProperty("ADBE Vector Shape - Group");
    path.name = "Part " + (o + 1);
    path.property("ADBE Vector Shape").setValue(sh);
  }
  addFill(c, [1, 1, 1], "White");
  tr(layer).property("ADBE Anchor Point").setValue([0, anchorY]);
  // the 2D logo's shadow: 3 px down-right, black 75 %, hard (Godot draws its own, without overlaps)
  var ds = layer.property("ADBE Effect Parade").addProperty("ADBE Drop Shadow");
  ds.property("ADBE Drop Shadow-0001").setValue([0, 0, 0, 1]);
  var op = ds.property("ADBE Drop Shadow-0002");
  op.setValue(op.maxValue > 100 ? 0.75 * 255 : 75);
  ds.property("ADBE Drop Shadow-0003").setValue(135);
  ds.property("ADBE Drop Shadow-0004").setValue(Math.sqrt(2) * L.shadow.offset[0] * K);
  ds.property("ADBE Drop Shadow-0005").setValue(0);
  return layer;
}

// the A-Q bar: fixed in place, uncovered by a mask from Q towards A's foot
var BR = L.bridge;
var bridgePiece = pieces[BR.key];
var bridge = glyphLayer("L_" + BR.key, bridgePiece, 0);
tr(bridge).property("ADBE Position").setValue([cx(bridgePiece.slot[0]), cy(bridgePiece.slot[1])]);
bridge.inPoint = bridgeStart;
var mask = bridge.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
mask.name = "Reveal";
mask.property("ADBE Mask Shape").expression = [
  "var rv = thisComp.layer('CTRL').effect('Reveal')(1).value;",
  "var K = " + K + ", ax = [" + BR.axis[0] + ", " + BR.axis[1] + "];",
  "var cut = (" + BR.max + " + (" + BR.min + " - " + BR.max + ") * rv) * K;",
  "var px = -ax[1], py = ax[0], big = 4000, ox = ax[0] * cut, oy = ax[1] * cut;",
  "createPath([[ox + px * big, oy + py * big], [ox - px * big, oy - py * big],",
  "  [ox - px * big + ax[0] * big, oy - py * big + ax[1] * big], [ox + px * big + ax[0] * big, oy + py * big + ax[1] * big]], [], [], true);"
].join("\n");

var dustSeed = rnd(20261012);
var dustIndex = 0;
var markers = [];
for (var n = 0; n < sched.length; n++) {
  var S = sched[n], P = S.piece;
  var baseOff = L.baseline - P.slot[1];           // baseline below the piece centre (logical)
  var restX = cx(P.slot[0]), restY = cy(P.slot[1] + baseOff);
  var landX = cx(landing);
  var M = comp.layers.addNull(DUR);
  M.name = "M_" + S.key;
  M.label = 2;
  tr(M).property("ADBE Anchor Point").setValue([0, 0]);
  var mp = tr(M).property("ADBE Position");
  mp.dimensionsSeparated = true;
  var mx = tr(M).property("ADBE Position_0"), my = tr(M).property("ADBE Position_1");
  var mr = tr(M).property("ADBE Rotate Z");
  var G = glyphLayer("L_" + S.key, P, baseOff * K);
  G.parent = M;
  tr(G).property("ADBE Position").setValue([0, 0]);
  G.inPoint = S.drop;
  var gs = tr(G).property("ADBE Scale"), go = tr(G).property("ADBE Opacity");
  var vK = V * K, ride = S.seat - S.land;

  // X: falls straight at the landing spot, rides the belt at belt speed, clicks into its slot
  key(mx, S.drop, landX, null, [0, 33.33]);
  if (ride > 0.001) {
    key(mx, S.land, landX, [0, 33.33], [vK, 33.33]);
    key(mx, S.seat, restX, [vK, 33.33], [vK, 40]);
    key(mx, S.seat + 0.06, restX + 2.6 * K, [0, 45], [0, 40]);
    key(mx, S.seat + 0.32, restX, [0, 72], null);
  } else {
    key(mx, S.land, landX, [0, 33.33], [0.5 * vK, 40]);
    key(mx, S.land + 0.07, landX + 1.4 * K, [0, 45], [0, 40]);
    key(mx, S.land + 0.32, landX, [0, 72], null);
  }
  // Y: gravity (speed grows linearly), lands, two settling hops
  var H = T.height * K, impact = 2 * H / T.fall;
  key(my, S.drop, restY - H, null, [0, 33.33]);
  key(my, S.land, restY, [impact, 33.33], [-2 * 6 * K / 0.14, 33.33]);
  key(my, S.land + 0.14, restY - 6 * K, [0, 50], [0, 50]);
  key(my, S.land + 0.28, restY, [2 * 6 * K / 0.14, 33.33], [-2 * 1.6 * K / 0.08, 33.33]);
  key(my, S.land + 0.36, restY - 1.6 * K, [0, 50], [0, 50]);
  key(my, S.land + 0.44, restY, [2 * 1.6 * K / 0.08, 40], null);
  // tilt while falling, straightens as it lands, a small wobble
  key(mr, S.drop, S.tilt, null, [0, 33.33]);
  key(mr, S.land, 0, [0, 62], [0, 40]);
  var w = S.tilt > 0 ? -1 : 1;
  key(mr, S.land + 0.12, 3.5 * w, [0, 50], [0, 50]);
  key(mr, S.land + 0.27, -1.2 * w, [0, 50], [0, 50]);
  key(mr, S.land + 0.42, 0, [0, 60], null);
  // fade in at the top of the fall
  key(go, S.drop, 0, null, [0, 33.33]);
  key(go, S.drop + 0.10, 100, [0, 33.33], null);
  // squash on impact, stretch at the top of the hop; a firm squash when it clicks into the slot
  key(gs, S.land - 1 / FPS, [100, 100, 100], null, null);
  key(gs, S.land + 0.06, [111, 86, 100], [0, 40], [0, 40]);
  key(gs, S.land + 0.15, [97, 104, 100], [0, 45], [0, 45]);
  key(gs, S.land + 0.27, [100, 100, 100], [0, 45], [0, 45]);
  key(gs, S.land + 0.31, [103, 96, 100], [0, 45], [0, 45]);
  key(gs, S.land + 0.39, [100, 100, 100], [0, 50], null);
  if (ride >= 0.45) {
    key(gs, S.seat, [100, 100, 100], null, [0, 40]);
    key(gs, S.seat + 0.05, [104, 93, 100], [0, 45], [0, 45]);
    key(gs, S.seat + 0.22, [100, 100, 100], [0, 60], null);
  }
  markers.push([S.land, "LAND " + S.key.toUpperCase()]);

  // dust: two puffs to each side of the landing foot
  for (var side = -1; side <= 1; side += 2) {
    for (var j = 0; j < 2; j++) {
      var d = comp.layers.addShape();
      d.name = "DUST_" + (dustIndex++);
      d.label = 14;
      var dg = d.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
      dg.name = "Puff";
      var dc = dg.property("ADBE Vectors Group");
      var radius = 1.8 + dustSeed() * 1.2;
      dc.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue([radius * 2 * K, radius * 2 * K]);
      addFill(dc, [0.95, 0.96, 1.0]);
      var life = 0.38 + dustSeed() * 0.14;
      var sx = cx(landing + side * P.size[0] * 0.4), sy = cy(L.belt_rect[1] - 1);
      var ex = sx + side * (9 + dustSeed() * 8) * K, ey = sy - (3 + dustSeed() * 4) * K;
      d.inPoint = S.land;
      d.outPoint = S.land + life;
      var dp = tr(d).property("ADBE Position");
      key(dp, S.land, [sx, sy], null, [1.8 * Math.abs(ex - sx) / life, 20]);
      key(dp, S.land + life, [ex, ey], [0, 75], null);
      var dsc = tr(d).property("ADBE Scale");
      key(dsc, S.land, [70, 70, 100], null, [0, 20]);
      key(dsc, S.land + life, [140, 140, 100], [0, 70], null);
      var dop = tr(d).property("ADBE Opacity");
      key(dop, S.land, 75, null, [0, 33.33]);
      key(dop, S.land + life, 0, [0, 25], null);
    }
  }
}

ctrl.moveToBeginning();

markers.push([T.deploy, "DEPLOY"], [stopAt, "ALL SEATED / BELT STOPS"], [bridgeStart, "A-Q BAR"], [bridgeEnd, "BAR DONE"],
             [collapse, "COLLAPSE"], [collapseEnd, "LOGO"]);
var mk = comp.markerProperty;
for (var m = 0; m < markers.length; m++) mk.setValueAtTime(markers[m][0], new MarkerValue(markers[m][1]));

// expression check
var errors = [];
function scan(group, path) {
  for (var q = 1; q <= group.numProperties; q++) {
    var pr = group.property(q);
    if (pr.propertyType === PropertyType.PROPERTY) {
      if (pr.canSetExpression && pr.expression !== "" && pr.expressionError !== "") errors.push(path + "/" + pr.name + ": " + pr.expressionError);
    } else scan(pr, path + "/" + pr.name);
  }
}
for (var li = 1; li <= comp.numLayers; li++) scan(comp.layer(li), comp.layer(li).name);

comp.openInViewer();
proj.save(new File(AEP));
app.endSuppressDialogs(false);
return { duration: DUR, stopAt: stopAt, bridge: [bridgeStart, bridgeEnd], collapse: [collapse, collapseEnd],
         land: (function () { var o = []; for (var z = 0; z < sched.length; z++) o.push([sched[z].key, Math.round(sched[z].land * 1000) / 1000, Math.round(sched[z].seat * 1000) / 1000]); return o; })(),
         layers: comp.numLayers, errors: errors };
