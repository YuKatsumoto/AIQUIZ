// TESTOPIA main-menu title intro -- After Effects builder (ExtendScript ES3, ASCII only).
//
// Builds tools/title_logo_ae/TESTOPIA_TitleLogo.aep from scratch in the RUNNING After Effects
// (the open project is closed WITHOUT saving -- save your work first):
//   node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/build_title_logo.jsx
// Input: tools/title_logo_ae/layout.json (export_layout.gd: piece shapes and colours, slots, belt, bar, door block).
// Then sample_title_logo.jsx writes the motion Godot plays (TitleLogoIntro).
//
// Comp "TitleLogo_Intro": 60 fps. One comp pixel = 1/K logical pixel of the menu (K = 4);
// comp (0,0) is logical (OX, OY) of the TitleLogo holder.
//   CTRL        null with sliders Form (0 bar .. 1 conveyor) and Travel (belt distance, logical px)
//   BELT        the conveyor, drawn by expressions from CTRL (TitleLogoIntro._draw does the same maths)
//   M_<key>     null at the piece's baseline point: falls, rides the belt (X/Y separated), tilts
//   L_<key>     the piece (shape paths from the layout); squash & stretch around the baseline
//               L_door is the grey quiz-wall block with the blue and red doors that carries T and E;
//               it shakes, then bursts: L_shard<n> fly off (ballistic expressions), L_t1 / L_e pop out
//   DUST_<n>    landing puffs (under the letters)   FX_PUFF_<n>  burst smoke (over the letters)
//   BG_Preview  backdrop for previews only (Godot ignores it)
// The pieces fall fast from far above (off the top of the screen). The intro ends on the belt; when a mode is chosen
// Godot flattens the letters to 2D and puts the belt away by playing the Form deploy backwards (TitleLogoIntro.set_stowed).

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var AEP = ROOT + "tools/title_logo_ae/TESTOPIA_TitleLogo.aep";
var LAYOUT = ROOT + "tools/title_logo_ae/layout.json";
var FPS = 60, K = 4, OX = -60, OY = -150, CW = 2080, CH = 1040;

// ---------- timing (seconds) ----------
var T = {
  deploy: 0.35, deployPeak: 1.08, deployEnd: 1.34, deployOver: 1.04,
  beltStart: 0.95, beltRamp: 0.60, speed: 150,          // logical px / s
  firstLand: 2.15, fall: 0.50, height: 270,              // logical px above the belt: off the top of the screen; a fast drop
  stopRamp: 0.75,
  burstDelay: 0.85, shake: 0.30,                         // after the door block (the last piece) settles (TitleLogoIntro.REST_BEFORE_OUT)
  popTime: 0.32, shardLife: 1.15,
  tail: 0.15
};
// shards: speed out of the block (logical px / s per px from its centre), lift, gravity (logical px / s^2)
var SHARD = { spread: 7.5, lift: -250, liftPerPx: 4, gravity: 1400, fadeStart: 0.60, fadeTime: 0.50 };
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
var folder = proj.items.addFolder("TESTOPIA_TitleLogo");

// ---------- schedule: left piece first (the door block); every piece lands with its RIGHT edge on the belt's landing
// spot (the right end, A's right edge) and the belt carries it LEFT (2026-10-19; before that it dropped at the left end
// and flowed right) ----------
var pieces = {};
for (var p = 0; p < L.pieces.length; p++) pieces[L.pieces[p].key] = L.pieces[p];
var V = T.speed;
var maxDist = 0;
for (var i0 = 0; i0 < L.order.length; i0++) {
  var r0 = pieces[L.order[i0]];
  maxDist = Math.max(maxDist, L.landing_right - (r0.slot[0] + r0.size[0] * 0.5));
}
var stopAt = T.firstLand + maxDist / V;
var sched = [];
for (var i = 0; i < L.order.length; i++) {
  var pc = pieces[L.order[i]];
  var dist = L.landing_right - (pc.slot[0] + pc.size[0] * 0.5);
  var land = stopAt - dist / V;
  var tilt = pc.key === L.door.key ? -9 : ((i % 2 === 0) ? 17 : -15);
  sched.push({ key: pc.key, piece: pc, land: land, drop: land - T.fall, seat: stopAt, tilt: tilt,
               landX: L.landing_right - pc.size[0] * 0.5 });
}
var stopEnd = stopAt + T.stopRamp;
var burst = Math.round((stopAt + T.burstDelay) * FPS) / FPS;   // on a frame: Godot samples the shards from here
var DUR = Math.ceil((burst + T.shardLife + T.tail) * FPS) / FPS;

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
var sl = sliders(ctrl, ["Form", "Travel"]);
var form = sl.Form, travel = sl.Travel;

// Form: the yellow bar stretches, thickens and lifts into the conveyor (small overshoot). It stays a conveyor.
key(form, T.deploy, 0, null, [0, 45]);
key(form, T.deployPeak, T.deployOver, [0, 55], [0, 40]);
key(form, T.deployEnd, 1, [0, 60], null);

// Travel: constant acceleration up to V, constant speed while pieces ride, long soft stop.
var full = T.beltStart + T.beltRamp;
var dRamp = 0.5 * V * T.beltRamp;
var dStop = dRamp + V * (stopAt - full);
key(travel, T.beltStart, 0, null, [0, 33.33]);
key(travel, full, dRamp, [V, 33.33], [V, 33.33]);
key(travel, stopAt, dStop, [V, 33.33], [V, 30]);
key(travel, stopEnd, dStop + 0.42 * V * T.stopRamp, [0, 62], null);

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
  // the top face recedes up-right (the letters' depth goes the same way): depth tp, back offset bk
  "var tp = " + B.top_depth + " * belt, bk = [tp * " + B.skew + ", -tp];",
  "var detail = ss(0.6, 1, f);",
  ""
].join("\n");
// polygon helpers (TitleLogoIntro._stadium_points / _belt_body: the same points and the convex hull)
var GEO = [
  "function stadPts(X0, X1, Y, H, R, dx, dy) {",
  "  if (R <= 0.25) return [[X0 + dx, Y + dy], [X1 + dx, Y + dy], [X1 + dx, Y + H + dy], [X0 + dx, Y + H + dy]];",
  "  var o = [], rr = Math.min(R, H / 2), cy = Y + H / 2 + dy, i, a;",
  "  for (i = 0; i <= 12; i++) { a = -Math.PI / 2 + Math.PI * i / 12; o.push([X1 - R + dx + Math.cos(a) * rr, cy + Math.sin(a) * rr]); }",
  "  for (i = 0; i <= 12; i++) { a = Math.PI / 2 + Math.PI * i / 12; o.push([X0 + R + dx + Math.cos(a) * rr, cy + Math.sin(a) * rr]); }",
  "  return o;",
  "}",
  "function cross(o, a, b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }",
  "function hull(p) {",
  "  p = p.slice().sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });",
  "  var lo = [], up = [], i;",
  "  for (i = 0; i < p.length; i++) { while (lo.length >= 2 && cross(lo[lo.length - 2], lo[lo.length - 1], p[i]) <= 0) lo.pop(); lo.push(p[i]); }",
  "  for (i = p.length - 1; i >= 0; i--) { while (up.length >= 2 && cross(up[up.length - 2], up[up.length - 1], p[i]) <= 0) up.pop(); up.push(p[i]); }",
  "  lo.pop(); up.pop(); return lo.concat(up);",
  "}",
  "function poly(pts, sx, sy) { var q = []; for (var i = 0; i < pts.length; i++) q.push(P(pts[i][0] + sx, pts[i][1] + sy)); return createPath(q, [], [], true); }",
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

// stadium = middle rect + two round ends (or one plain rect while SR <= 0.25), like _draw_stadium.
// geom defines SX0, SX1 (left/right), SY (top), SH (height), SR (radius) in logical px.
function stadium(name, geom, fillExpr, opacityExpr) {
  var g = root.addProperty("ADBE Vector Group"); g.name = name;
  var c = g.property("ADBE Vectors Group");
  var G = PRE + geom + "\n";
  var mid = c.addProperty("ADBE Vector Shape - Rect"); mid.name = "Mid";
  mid.property("ADBE Vector Rect Size").expression = G + "var w = SR <= 0.25 ? SX1 - SX0 : Math.max(SX1 - SX0 - 2 * SR, 0); [w * K, SH * K];";
  mid.property("ADBE Vector Rect Position").expression = G + "P((SX0 + SX1) / 2, SY + SH / 2);";
  var names = ["EndL", "EndR"];
  for (var e = 0; e < 2; e++) {
    var el = c.addProperty("ADBE Vector Shape - Ellipse"); el.name = names[e];
    el.property("ADBE Vector Ellipse Size").expression = G + "var d = SR <= 0.25 ? 0 : 2 * Math.min(SR, SH / 2) * K; [d, d];";
    el.property("ADBE Vector Ellipse Position").expression = G + "P(" + (e === 0 ? "SX0 + SR" : "SX1 - SR") + ", SY + SH / 2);";
  }
  var fill = c.addProperty("ADBE Vector Graphic - Fill");
  fill.property("ADBE Vector Fill Color").expression = PRE + MIX + fillExpr;
  g.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = G + opacityExpr;
  return g;
}
// a filled path group: pathExpr returns a path (poly(...)); colour is an [r, g, b] or a fill expression string
function pathGroup(rootG, name, pre, pathExpr, colour, opacityExpr) {
  var g = rootG.addProperty("ADBE Vector Group"); g.name = name;
  var c = g.property("ADBE Vectors Group");
  var path = c.addProperty("ADBE Vector Shape - Group");
  path.property("ADBE Vector Shape").expression = pre + pathExpr;
  var fill = c.addProperty("ADBE Vector Graphic - Fill");
  if (typeof colour === "string") fill.property("ADBE Vector Fill Color").expression = PRE + MIX + colour;
  else fill.property("ADBE Vector Fill Color").setValue([colour[0], colour[1], colour[2], 1]);
  g.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = pre + opacityExpr;
  return { group: g, contents: c };
}
function repeat(contents, countExpr, step) {
  var rp = contents.addProperty("ADBE Vector Filter - Repeater");
  rp.property("ADBE Vector Repeater Copies").expression = countExpr;
  rp.property("ADBE Vector Repeater Transform").property("ADBE Vector Repeater Position").setValue([step * K, 0]);
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
  rgt.property("ADBE Vector Rotation").expression = PRE + "-dist / Math.max(r, 1) * 180 / Math.PI;";   // the belt flows left
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

// the front face is a steel frame: a lit line under the yellow lip and fixed rivets (the belt moves on the top face)
var SP = B.rib_spacing, RS = B.rivet_spacing;
var RIB0 = "var xs = x0 + r + ((((-dist) % " + SP + ") + " + SP + ") % " + SP + ");\n";
var RV0 = "var xr = x0 + r + " + (RS * 0.5) + ";\n";
var rivets = root.addProperty("ADBE Vector Group"); rivets.name = "Rivets";
var rvc = rivets.property("ADBE Vectors Group");
var rve = rvc.addProperty("ADBE Vector Shape - Ellipse");
rve.property("ADBE Vector Ellipse Size").setValue([1.8 * K, 1.8 * K]);
rve.property("ADBE Vector Ellipse Position").expression = PRE + RV0 + "P(xr, y0 + h / 2);";
addFill(rvc, B.rivet_color);
repeat(rvc, PRE + RV0 + "xr < x1 - r - 1 ? Math.floor((x1 - r - 1 - xr) / " + RS + " - 1e-6) + 1 : 0;", RS);
rivets.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + "belt > 0 ? detail * 100 : 0;";

var shine = addRect(root, "FrameShine");
shine.shape.property("ADBE Vector Rect Size").expression = PRE + "[Math.max(x1 - x0 - 2 * r, 0) * K, 0.8 * K];";
shine.shape.property("ADBE Vector Rect Position").expression = PRE + "P((x0 + x1) / 2, y0 + 2.4);";
addFill(shine.contents, B.frame_highlight_color);
shine.group.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + "belt > 0 ? detail * 100 : 0;";

var bottom = addRect(root, "Bottom");
bottom.shape.property("ADBE Vector Rect Size").expression = PRE + "[(x1 - x0 - r * 2) * K, 2 * K];";
bottom.shape.property("ADBE Vector Rect Position").expression = PRE + "P((x0 + x1) / 2, y0 + h - 1);";
var bf = bottom.contents.addProperty("ADBE Vector Graphic - Fill");
bf.property("ADBE Vector Fill Color").expression = PRE + MIX + "mix(" + col(B.bar_color) + ", " + col(B.bottom_color) + ", belt);";
bottom.group.property("ADBE Vector Transform Group").property("ADBE Vector Group Opacity").expression = PRE + "belt > 0 ? 100 : 0;";

stadium("Body", "var SX0 = x0, SX1 = x1, SY = y0, SH = h, SR = r;",
        "mix(" + col(B.bar_color) + ", " + col(B.belt_color) + ", belt);", "100;");

// the top face recedes up-right like the letters' depth; slats (a groove and the lit plate corner) flow left,
// the back edge is lit. The letters stand on it (TitleLogoIntro.BELT_STAND_MARGIN behind the yellow lip).
var TOP = "var tl = [x0 + r, y0], tr = [x1 - r, y0];\n";
pathGroup(root, "TopBackEdge", PRE + GEO + TOP,
  "poly([[tl[0] + bk[0], tl[1] + bk[1]], [tr[0] + bk[0], tr[1] + bk[1]], [tr[0] + bk[0], tr[1] + bk[1] + 0.8], [tl[0] + bk[0], tl[1] + bk[1] + 0.8]], 0, 0);",
  B.top_edge_color, "tp > 0.25 ? 100 : 0;");
var slatLight = pathGroup(root, "SlatLight", PRE + GEO + RIB0,
  "poly([[xs + 0.5, y0], [xs + 1.3, y0], [xs + 1.3 + bk[0], y0 + bk[1]], [xs + 0.5 + bk[0], y0 + bk[1]]], 0, 0);",
  B.slat_light_color, "tp > 0.25 ? detail * 100 : 0;");
repeat(slatLight.contents, PRE + RIB0 + "xs + 1.3 < x1 - r ? Math.floor((x1 - r - 1.3 - xs) / " + SP + " - 1e-6) + 1 : 0;", SP);
var slatGroove = pathGroup(root, "SlatGroove", PRE + GEO + RIB0,
  "poly([[xs - 0.5, y0], [xs + 0.5, y0], [xs + 0.5 + bk[0], y0 + bk[1]], [xs - 0.5 + bk[0], y0 + bk[1]]], 0, 0);",
  B.slat_color, "tp > 0.25 ? detail * 100 : 0;");
repeat(slatGroove.contents, PRE + RIB0 + "xs < x1 - r ? Math.floor((x1 - r - xs) / " + SP + " - 1e-6) + 1 : 0;", SP);
pathGroup(root, "TopFace", PRE + GEO + TOP,
  "poly([tl, tr, [tr[0] + bk[0], tr[1] + bk[1]], [tl[0] + bk[0], tl[1] + bk[1]]], 0, 0);",
  B.top_color, "tp > 0.25 ? 100 : 0;");
// the side: the front face swept back to the back offset (right end, and where the belt wraps the rollers)
var BODY = "var body = hull(stadPts(x0, x1, y0, h, r, 0, 0).concat(stadPts(x0, x1, y0, h, r, bk[0], bk[1])));\n";
pathGroup(root, "Side", PRE + GEO + BODY, "poly(body, 0, 0);",
  "mix(" + col(B.bar_color) + ", " + col(B.side_color) + ", belt);", "belt > 0 ? 100 : 0;");
pathGroup(root, "Shadow", PRE + GEO + BODY, "poly(body, " + L.shadow.offset[0] + ", " + L.shadow.offset[1] + ");",
  [0, 0, 0], "40 * belt;");

// ---------- pieces ----------
// One path per outline. White letters share one fill; coloured pieces (door block, shards) get a group per colour.
function pieceLayer(name, piece, anchorY) {
  var layer = comp.layers.addShape();
  layer.name = name;
  layer.label = 1;
  var rootG = layer.property("ADBE Root Vectors Group");
  var colors = piece.colors || [];
  var white = true;
  for (var wc = 0; wc < colors.length; wc++) if (colors[wc][0] < 0.999 || colors[wc][1] < 0.999 || colors[wc][2] < 0.999) white = false;
  if (white) {
    var g = rootG.addProperty("ADBE Vector Group");
    g.name = "Glyph";
    var c = g.property("ADBE Vectors Group");
    for (var o = 0; o < piece.outlines.length; o++) addPath(c, piece.outlines[o], "Part " + (o + 1));
    addFill(c, [1, 1, 1], "White");
  } else {
    // groups are drawn bottom-up from the last one: add the top-most outline first
    for (var o2 = piece.outlines.length - 1; o2 >= 0; o2--) {
      var g2 = rootG.addProperty("ADBE Vector Group");
      g2.name = "Part " + (o2 + 1);
      var c2 = g2.property("ADBE Vectors Group");
      addPath(c2, piece.outlines[o2], "Path");
      addFill(c2, colors[o2]);
    }
  }
  // under the face: the depth (non-flat parts; navy for letters, grey for the door block), then the dark navy
  // outline around face + depth (TitleLogoIntro draws the same: DEPTH_* / WALL_DEPTH_* and LETTER_OUTLINE_*). Shards have neither.
  if (L.depth && piece.depth) {
    var dOff = [L.depth.offset[0] * K, L.depth.offset[1] * K];
    var dLen = Math.sqrt(dOff[0] * dOff[0] + dOff[1] * dOff[1]);
    var steps = Math.max(3, Math.ceil(dLen / 0.9));
    var step = [dOff[0] / steps, dOff[1] / steps];
    // the copy nearest the face is a lighter navy edge; the rest of the steps are the depth colour
    var edge = depthGroup(rootG, "DepthEdge", piece, piece.depth_edge_color, step, 1, step);
    var body = depthGroup(rootG, "Depth", piece, piece.depth_color, [step[0] * 2, step[1] * 2], steps - 1, step);
    if (L.outline && piece.outline) {
      var og = rootG.addProperty("ADBE Vector Group");
      og.name = "Outline";
      var oc = og.property("ADBE Vectors Group");
      for (var oo = 0; oo < piece.outlines.length; oo++) addPath(oc, piece.outlines[oo], "Part " + (oo + 1));
      var st = oc.addProperty("ADBE Vector Graphic - Stroke");
      st.property("ADBE Vector Stroke Color").setValue([L.outline.color[0], L.outline.color[1], L.outline.color[2], 1]);
      st.property("ADBE Vector Stroke Width").setValue(L.outline.width * 2 * K);
      st.property("ADBE Vector Stroke Line Join").setValue(2);  // round, like Godot's outline shader
      addFill(oc, L.outline.color);
      var orp = oc.addProperty("ADBE Vector Filter - Repeater");
      orp.property("ADBE Vector Repeater Copies").setValue(steps + 1);
      orp.property("ADBE Vector Repeater Transform").property("ADBE Vector Repeater Position").setValue(step);
    }
  }
  tr(layer).property("ADBE Anchor Point").setValue([0, anchorY]);
  if (piece.shadow) {
    // the 2D logo's shadow: 3 px down-right, black 75 %, hard (Godot draws its own, without overlaps)
    var ds = layer.property("ADBE Effect Parade").addProperty("ADBE Drop Shadow");
    ds.property("ADBE Drop Shadow-0001").setValue([0, 0, 0, 1]);
    var op = ds.property("ADBE Drop Shadow-0002");
    op.setValue(op.maxValue > 100 ? 0.75 * 255 : 75);
    ds.property("ADBE Drop Shadow-0003").setValue(135);
    ds.property("ADBE Drop Shadow-0004").setValue(Math.sqrt(2) * L.shadow.offset[0] * K);
    ds.property("ADBE Drop Shadow-0005").setValue(0);
  }
  return layer;
}
// copies of the non-flat outlines, `copies` times `step` apart, starting at `start` (the depth of the block)
function depthGroup(rootG, name, piece, rgb, start, copies, step) {
  var g = rootG.addProperty("ADBE Vector Group");
  g.name = name;
  var c = g.property("ADBE Vectors Group");
  var flat = piece.flat || [];
  for (var o = 0; o < piece.outlines.length; o++) {
    if (!flat[o]) addPath(c, piece.outlines[o], "Part " + (o + 1));
  }
  addFill(c, rgb);
  var rp = c.addProperty("ADBE Vector Filter - Repeater");
  rp.property("ADBE Vector Repeater Copies").setValue(copies);
  rp.property("ADBE Vector Repeater Transform").property("ADBE Vector Repeater Position").setValue(step);
  g.property("ADBE Vector Transform Group").property("ADBE Vector Position").setValue(start);
  return g;
}
function addPath(contents, pts, name) {
  var verts = [];
  for (var v = 0; v < pts.length; v++) verts.push([pts[v][0] * K, pts[v][1] * K]);
  var sh = new Shape();
  sh.vertices = verts;
  sh.closed = true;
  var path = contents.addProperty("ADBE Vector Shape - Group");
  path.name = name;
  path.property("ADBE Vector Shape").setValue(sh);
}

var dustSeed = rnd(20261017);
var dustIndex = 0;
var markers = [];
var doorLayer = null;
for (var n = 0; n < sched.length; n++) {
  var S = sched[n], P = S.piece;
  var baseOff = L.baseline - P.slot[1];           // baseline below the piece centre (logical)
  var restX = cx(P.slot[0]), restY = cy(P.slot[1] + baseOff);
  var landX = cx(S.landX);
  var isDoor = P.key === L.door.key;
  var M = comp.layers.addNull(DUR);
  M.name = "M_" + S.key;
  M.label = 2;
  tr(M).property("ADBE Anchor Point").setValue([0, 0]);
  var mp = tr(M).property("ADBE Position");
  mp.dimensionsSeparated = true;
  var mx = tr(M).property("ADBE Position_0"), my = tr(M).property("ADBE Position_1");
  var mr = tr(M).property("ADBE Rotate Z");
  if (L.contact_shadow) {
    var cs = comp.layers.addShape();
    cs.name = "CS_" + S.key;
    cs.label = 8;
    tr(cs).property("ADBE Position").setValue([0, 0]);
    tr(cs).property("ADBE Anchor Point").setValue([0, 0]);
    cs.inPoint = S.drop;
    var CSPRE = PRE + GEO +
      "var Mp = thisComp.layer('M_" + S.key + "').transform.position;\n" +
      "var fx = Mp[0] / K + OX, fy = Mp[1] / K + OY;\n" +
      "var ca = " + L.contact_shadow.alpha + " * Math.pow(cl(1 - (" + L.baseline + " - fy) / " + L.contact_shadow.fade + ", 0, 1), 2);\n" +
      "var yb = " + (L.belt_rect[1] - B.stand_margin) + ", bx = " + (L.depth.offset[0] * 1.4) + ", by = " + (L.depth.offset[1] * 1.4) +
      ", w = " + P.size[0] + ";\n";
    var specs = [[1.0, 0.5, 1.0], [2.5, 1.0, 0.45]];   // narrow + dark on top of wide + light
    for (var sp = 0; sp < specs.length; sp++) {
      pathGroup(cs.property("ADBE Root Vectors Group"), "Shadow " + (sp + 1),
        CSPRE + "var pad = " + specs[sp][0] + ", y = yb + " + specs[sp][1] + ", l = fx - w / 2 - pad, rt = fx + w / 2 + pad;\n",
        "poly([[l, y], [rt, y], [rt + bx, y + by], [l + bx, y + by]], 0, 0);",
        [0, 0, 0], "tp > 0.25 ? ca * " + specs[sp][2] + " * 100 : 0;");
    }
    cs.moveBefore(beltLayer);
  }
  var G = pieceLayer("L_" + S.key, P, baseOff * K);
  G.parent = M;
  tr(G).property("ADBE Position").setValue([0, 0]);
  G.inPoint = S.drop;
  if (isDoor) { G.outPoint = burst; doorLayer = G; }
  var gs = tr(G).property("ADBE Scale"), go = tr(G).property("ADBE Opacity");
  var vK = V * K, ride = S.seat - S.land;

  // X: falls straight at the landing spot, rides the belt LEFT at belt speed, clicks into its slot
  // (the speeds are negative: X decreases; the small overshoot goes on to the left)
  key(mx, S.drop, landX, null, [0, 33.33]);
  if (ride > 0.001) {
    key(mx, S.land, landX, [0, 33.33], [-vK, 33.33]);
    key(mx, S.seat, restX, [-vK, 33.33], [-vK, 40]);
    key(mx, S.seat + 0.06, restX - 2.6 * K, [0, 45], [0, 40]);
    key(mx, S.seat + 0.32, restX, [0, 72], null);
  } else {
    key(mx, S.land, landX, [0, 33.33], [-0.5 * vK, 40]);
    key(mx, S.land + 0.07, landX - 1.4 * K, [0, 45], [0, 40]);
    key(mx, S.land + 0.32, landX, [0, 72], null);
  }
  // Y: gravity (speed grows linearly), lands, two settling hops (the heavy block hops lower)
  var H = T.height * K, impact = 2 * H / T.fall, hop = isDoor ? 4 : 6, hop2 = isDoor ? 1.0 : 1.6;
  key(my, S.drop, restY - H, null, [0, 33.33]);
  key(my, S.land, restY, [impact, 33.33], [-2 * hop * K / 0.14, 33.33]);
  key(my, S.land + 0.14, restY - hop * K, [0, 50], [0, 50]);
  key(my, S.land + 0.28, restY, [2 * hop * K / 0.14, 33.33], [-2 * hop2 * K / 0.08, 33.33]);
  key(my, S.land + 0.36, restY - hop2 * K, [0, 50], [0, 50]);
  key(my, S.land + 0.44, restY, [2 * hop2 * K / 0.08, 40], null);
  // tilt while falling, straightens as it lands, a small wobble
  key(mr, S.drop, S.tilt, null, [0, 33.33]);
  key(mr, S.land, 0, [0, 62], [0, 40]);
  var w = S.tilt > 0 ? -1 : 1;
  key(mr, S.land + 0.12, (isDoor ? 2 : 3.5) * w, [0, 50], [0, 50]);
  key(mr, S.land + 0.27, -1.2 * w, [0, 50], [0, 50]);
  key(mr, S.land + 0.42, 0, [0, 60], null);
  // no fade: the piece is already moving when it enters the screen
  go.setValue(100);  // already opaque: it comes in from off screen
  // squash on impact, stretch at the top of the hop; a firm squash when it clicks into the slot
  key(gs, S.land - 1 / FPS, [100, 100, 100], null, null);
  key(gs, S.land + 0.06, isDoor ? [108, 89, 100] : [111, 86, 100], [0, 40], [0, 40]);
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
      var sx = cx(S.landX + side * P.size[0] * 0.4), sy = cy(L.belt_rect[1] - B.stand_margin - 1);
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

// ---------- the door block: shakes and swells, then bursts ----------
var SHAKE = "var k = Math.min(Math.max((time - " + (burst - T.shake) + ") / " + T.shake + ", 0), 1);\n";
tr(doorLayer).property("ADBE Position").expression = SHAKE + "[value[0] + Math.sin(time * 95) * 2.4 * " + K + " * k, value[1]];";
tr(doorLayer).property("ADBE Scale").expression = SHAKE + "[value[0] * (1 + 0.05 * k), value[1] * (1 + 0.05 * k)];";

// T and E pop out of the block, scaling around their centres
for (var li = 0; li < L.door.letters.length; li++) {
  var lp = pieces[L.door.letters[li]];
  var LL = pieceLayer("L_" + lp.key, lp, 0);
  tr(LL).property("ADBE Position").setValue([cx(lp.slot[0]), cy(lp.slot[1])]);
  LL.inPoint = burst;
  var ls = tr(LL).property("ADBE Scale");
  key(ls, burst, [55, 55, 100], null, [0, 40]);
  key(ls, burst + T.popTime * 0.55, [110, 110, 100], [0, 50], [0, 50]);
  key(ls, burst + T.popTime, [100, 100, 100], [0, 60], null);
}

// shards: the block cut into a grid; each flies out from the centre, spins, falls and fades
var DR = L.door.rect, dcx = DR[0] + DR[2] / 2, dcy = DR[1] + DR[3] / 2;
var J = [[-30, 20, 6], [25, -30, -8], [-10, 40, 9], [35, 10, -5], [-25, -15, 7], [15, 35, -9],
         [-35, 5, 4], [30, -20, -7], [-5, 30, 8], [20, 15, -6], [-20, -35, 5], [10, 25, -4]];
var shardCount = L.door.cols * L.door.rows;
for (var s = 0; s < shardCount; s++) {
  var sp = pieces[L.door.shard_prefix + s];
  var px = sp.slot[0] - dcx, py = sp.slot[1] - dcy, jj = J[s % 12], sg = s < 12 ? 1 : -1;
  var vx = px * SHARD.spread + jj[0] * 3 * sg, vy = SHARD.lift + (py + DR[3] / 2) * SHARD.liftPerPx + jj[1] * 2;
  var SL = pieceLayer("L_" + sp.key, sp, 0);
  SL.inPoint = burst;
  SL.outPoint = burst + T.shardLife;
  var TT = "var t = Math.max(time - " + burst + ", 0);\n";
  tr(SL).property("ADBE Position").expression = TT +
    "[" + cx(sp.slot[0]) + " + " + (vx * K) + " * t, " + cy(sp.slot[1]) + " + " + (vy * K) + " * t + " + (0.5 * SHARD.gravity * K) + " * t * t];";
  tr(SL).property("ADBE Rotate Z").expression = TT + (jj[2] * sg * 180 / Math.PI) + " * t;";
  tr(SL).property("ADBE Opacity").expression = TT + "100 * (1 - Math.min(Math.max((t - " + SHARD.fadeStart + ") / " + SHARD.fadeTime + ", 0), 1));";
}

// burst smoke over the letters
for (var k2 = 0; k2 < 7; k2++) {
  var fxl = comp.layers.addShape();
  fxl.name = "FX_PUFF_" + k2;
  fxl.label = 14;
  var fg = fxl.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  fg.name = "Puff";
  var fc = fg.property("ADBE Vectors Group");
  fc.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue([12 * K, 12 * K]);
  addFill(fc, [0.88, 0.91, 0.95]);
  var an = k2 / 7 * Math.PI * 2, life2 = 0.45, rd0 = 12, rd1 = 12 + life2 * 120;
  fxl.inPoint = burst;
  fxl.outPoint = burst + life2;
  var fp = tr(fxl).property("ADBE Position");
  key(fp, burst, [cx(dcx + Math.cos(an) * rd0 * 1.3), cy(dcy + Math.sin(an) * rd0 * 0.6)], null, [0, 30]);
  key(fp, burst + life2, [cx(dcx + Math.cos(an) * rd1 * 1.3), cy(dcy + Math.sin(an) * rd1 * 0.6)], [0, 70], null);
  var fs = tr(fxl).property("ADBE Scale");
  key(fs, burst, [100, 100, 100], null, [0, 30]);
  key(fs, burst + life2, [295, 295, 100], [0, 60], null);
  var fo = tr(fxl).property("ADBE Opacity");
  key(fo, burst, 50, null, [0, 33.33]);
  key(fo, burst + life2, 0, [0, 40], null);
}

ctrl.moveToBeginning();

markers.push([T.deploy, "DEPLOY"], [stopAt, "ALL SEATED"], [burst - T.shake, "SHAKE"], [burst, "BURST"],
             [DUR, "END"]);
var mk = comp.markerProperty;
for (var m = 0; m < markers.length; m++) mk.setValueAtTime(Math.min(markers[m][0], DUR - 1 / FPS), new MarkerValue(markers[m][1]));

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
for (var lj = 1; lj <= comp.numLayers; lj++) scan(comp.layer(lj), comp.layer(lj).name);

comp.openInViewer();
proj.save(new File(AEP));
app.endSuppressDialogs(false);
return { duration: DUR, stopAt: stopAt, burst: burst,
         land: (function () { var o = []; for (var z = 0; z < sched.length; z++) o.push([sched[z].key, Math.round(sched[z].land * 1000) / 1000]); return o; })(),
         layers: comp.numLayers, errors: errors };
