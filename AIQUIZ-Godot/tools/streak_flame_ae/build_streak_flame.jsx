// AIQUIZ streak flame -- After Effects builder (ExtendScript ES3, ASCII only).
//
// Builds assets/ui/streak_flame/source/AIQUIZ_Streak_Flame.aep in the RUNNING After Effects
// (refuses to run when the open project has unsaved changes; the open project is closed):
//   node tools/title_logo_ae/ae_run.mjs tools/streak_flame_ae/build_streak_flame.jsx
// Then render_streak_flame.jsx renders the loop frames and the badge preview, and writes motion.json.
//
// Comps
//   Streak_Flame_Loop    256 x 320, 30 fps, exactly 1.0 s, seamless. Flame base at (128, 282).
//     CTRL          sliders: Turbulence, Wave Height, Glow (edit these first)
//     Outer/Mid/Core Shape   flame silhouettes: 4 path poses + wrap keys (-0.25 / 1.25) keep the
//                            velocity continuous across the loop seam
//     Outer/Mid Color        Gradient Ramp solids, alpha-matted by their shapes
//     Tongue A/B    small licks leaving the tip (0.5 s cycle), Ember 1-3 (1 s cycle)
//     Heat Halo     soft warm aura; Bloom adjustment layer (Glow)
//   Streak_Badge_Events  400 x 200 at 60 fps = the 188 x 80 duo card row at 2x.
//     Ignite 0.30-0.78 s, count pop 1.40-1.74 s, extinguish 3.00-3.40 s. Sampled into motion.json.

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var AEP = ROOT + "assets/ui/streak_flame/source/AIQUIZ_Streak_Flame.aep";
var W = 256, H = 320, BX = 128, BY = 282;
var TAU = "(2*Math.PI)";

if (app.project.dirty && app.project.file) throw new Error("The open project has unsaved changes; save it first.");
app.beginSuppressDialogs();
app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
app.newProject();
app.project.bitsPerChannel = 16;

// ---------- helpers ----------
function tr(layer) { return layer.property("ADBE Transform Group"); }
function fxParade(layer) { return layer.property("ADBE Effect Parade"); }
function addFx(layer, matchName, values) {
  var fx = fxParade(layer).addProperty(matchName);
  var idx = fx.propertyIndex;
  for (var k in values) {
    if (values.hasOwnProperty(k)) fxParade(layer).property(idx).property(matchName + "-" + k).setValue(values[k]);
  }
  return idx;
}
function fxProp(layer, idx, matchName, n) { return fxParade(layer).property(idx).property(matchName + "-" + n); }

// Flame silhouette: main tip, right notch, right sub-tip, right bulge, rounded base and the
// mirrored left side. Origin = flame base. The sub-tips flicker in alternation between poses.
function flameShape(p, s) {
  function v(a) { return [a[0] * s, a[1] * s]; }
  var sh = new Shape();
  sh.vertices = [v(p.t), v(p.nr), v(p.sr), v(p.br), v([0, 10]), v(p.bl), v(p.sl), v(p.nl)];
  sh.inTangents = [v([-6, 46]), v([-10, -4]), v([-6, 26]), v([6, -56]), v([46, 0]), v([0, 44]), v([-8, 30]), v([-12, 6])];
  sh.outTangents = [v([6, 46]), v([12, -6]), v([8, 30]), v([0, 44]), v([-46, 0]), v([-6, -56]), v([6, 26]), v([10, -4])];
  sh.closed = true;
  return sh;
}
var POSES = [
  { t: [0, -250], nr: [24, -150], sr: [58, -188], br: [78, -66], bl: [-78, -66], sl: [-54, -170], nl: [-22, -140] },
  { t: [14, -232], nr: [28, -146], sr: [62, -162], br: [80, -62], bl: [-72, -70], sl: [-60, -196], nl: [-18, -150] },
  { t: [-6, -262], nr: [20, -156], sr: [52, -198], br: [74, -70], bl: [-80, -64], sl: [-50, -160], nl: [-24, -136] },
  { t: [-16, -236], nr: [26, -142], sr: [60, -172], br: [76, -68], bl: [-76, -68], sl: [-58, -188], nl: [-20, -148] }
];

function shapeLayer(comp, name, pos) {
  var layer = comp.layers.addShape();
  layer.name = name;
  tr(layer).property("ADBE Position").setValue(pos);
  var grp = layer.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  grp.name = name;
  return layer;
}
function group(layer) { return layer.property("ADBE Root Vectors Group").property(1).property("ADBE Vectors Group"); }
function addFill(layer, color) {
  group(layer).addProperty("ADBE Vector Graphic - Fill");
  var fills = group(layer);
  fills.property(fills.numProperties).property("ADBE Vector Fill Color").setValue(color);
}

// Path poses with wrap keys so auto-Bezier velocity matches on both sides of the loop seam.
function flameLayer(comp, name, pos, scale, order) {
  var layer = shapeLayer(comp, name, pos);
  group(layer).addProperty("ADBE Vector Shape - Group");
  var path = group(layer).property(1).property("ADBE Vector Shape");
  var times = [-0.25, 0, 0.25, 0.5, 0.75, 1.0, 1.25];
  var poseAt = [3, 0, 1, 2, 3, 0, 1];
  for (var i = 0; i < times.length; i++) path.setValueAtTime(times[i], flameShape(POSES[order[poseAt[i]]], scale));
  for (var k = 1; k <= path.numKeys; k++) {
    path.setInterpolationTypeAtKey(k, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
    path.setTemporalContinuousAtKey(k, true);
    path.setTemporalAutoBezierAtKey(k, true);
  }
  addFill(layer, [1, 1, 1, 1]);
  return layer;
}

function warp(layer, seed, amountSlider, waveSlider, waveWidth, phase, blur) {
  var td = addFx(layer, "ADBE Turbulent Displace", { "0003": 34, "0005": 1.3, "0008": 1, "0009": 1, "0010": seed });
  fxProp(layer, td, "ADBE Turbulent Displace", "0002").expression = 'thisComp.layer("CTRL").effect("Turbulence")("ADBE Slider Control-0001")*' + amountSlider;
  fxProp(layer, td, "ADBE Turbulent Displace", "0006").expression = "time*360";
  var ww = addFx(layer, "ADBE Wave Warp", { "0003": waveWidth, "0004": 0, "0005": 1, "0006": 9, "0007": phase });
  fxProp(layer, ww, "ADBE Wave Warp", "0002").expression = 'thisComp.layer("CTRL").effect("Wave Height")("ADBE Slider Control-0001")*' + waveSlider;
  addFx(layer, "ADBE Gaussian Blur 2", { "0001": blur, "0003": 0 });
}

function rampSolid(comp, name, bottomColor, topColor, topY) {
  var solid = comp.layers.addSolid([1, 1, 1], name, W, H, 1);
  addFx(solid, "ADBE Ramp", { "0001": [BX, BY + 4], "0002": bottomColor, "0003": [BX, topY], "0004": topColor, "0005": 1 });
  return solid;
}

function slider(layer, name, value) {
  var s = fxParade(layer).addProperty("ADBE Slider Control");
  s.name = name;
  fxParade(layer).property(name).property(1).setValue(value);
}

// ---------- Streak_Flame_Loop ----------
var loop = app.project.items.addComp("Streak_Flame_Loop", W, H, 1, 1.0, 30);
loop.bgColor = [0, 0, 0];

var ctrl = loop.layers.addNull();
ctrl.name = "CTRL";
slider(ctrl, "Turbulence", 20);
slider(ctrl, "Wave Height", 5);
slider(ctrl, "Glow", 0.6);
ctrl.enabled = false;

// Heat halo (bottom of stack).
var halo = shapeLayer(loop, "Heat Halo", [BX, BY - 88]);
group(halo).addProperty("ADBE Vector Shape - Ellipse");
group(halo).property(1).property("ADBE Vector Ellipse Size").setValue([176, 226]);
addFill(halo, [1.0, 0.40, 0.05, 1]);
addFx(halo, "ADBE Gaussian Blur 2", { "0001": 46, "0003": 0 });
tr(halo).property("ADBE Opacity").expression = "26 + 5*Math.sin(time*" + TAU + "*2)";

// Outer flame: gradient solid matted by the warped silhouette.
var outerShape = flameLayer(loop, "Outer Shape", [BX, BY], 1.0, [0, 1, 2, 3]);
warp(outerShape, 7, 1.0, 1.0, 120, 0, 2.5);
var outerColor = rampSolid(loop, "Outer Color", [1.0, 0.64, 0.10], [1.0, 0.27, 0.07], 40);
outerColor.moveBefore(outerShape);
outerColor.setTrackMatte(outerShape, TrackMatteType.ALPHA);
outerShape.enabled = false;

// Licks that leave the tip twice per loop (0.5 s cycle each, opposite phase).
function tongue(name, off, dx, sway) {
  var t = flameLayer(loop, name, [BX, BY], 0.16, [0, 1, 2, 3]);
  var fills = group(t);
  fills.property(fills.numProperties).property("ADBE Vector Fill Color").setValue([1.0, 0.50, 0.10, 1]);
  addFx(t, "ADBE Gaussian Blur 2", { "0001": 1.5, "0003": 0 });
  tr(t).property("ADBE Position").expression =
    "var p = (time*2 + " + off + ") % 1;\n[" + (BX + dx) + " + " + sway + "*Math.sin(p*" + TAU + "), " + (BY - 196) + " - 64*p];";
  tr(t).property("ADBE Scale").expression =
    "var p = (time*2 + " + off + ") % 1;\nvar s = 100*Math.min(p/0.25, 1)*(1 - 0.8*p);\n[s*0.8, s];";
  tr(t).property("ADBE Opacity").expression =
    "var p = (time*2 + " + off + ") % 1;\n85*Math.min(p/0.12, 1)*Math.pow(1 - p, 1.6);";
  return t;
}
tongue("Tongue A", 0.0, 10, 7);
tongue("Tongue B", 0.5, -12, -6);

// Mid flame.
var midShape = flameLayer(loop, "Mid Shape", [BX, BY - 4], 0.68, [2, 3, 0, 1]);
warp(midShape, 19, 0.8, 0.8, 90, 120, 3.5);
var midColor = rampSolid(loop, "Mid Color", [1.0, 0.96, 0.60], [1.0, 0.60, 0.12], 110);
midColor.moveBefore(midShape);
midColor.setTrackMatte(midShape, TrackMatteType.ALPHA);
midShape.enabled = false;

// Hot core.
var core = flameLayer(loop, "Core Shape", [BX, BY - 8], 0.34, [1, 2, 3, 0]);
var cf = group(core);
cf.property(cf.numProperties).property("ADBE Vector Fill Color").setValue([1.0, 0.97, 0.80, 1]);
warp(core, 31, 0.5, 0.5, 70, 240, 5);

// Embers (1 s cycle, staggered).
var EMBERS = [{ off: 0.0, dx: -26, sway: 9, size: 9 }, { off: 0.36, dx: 24, sway: -8, size: 8 }, { off: 0.7, dx: 2, sway: 11, size: 7 }];
for (var e = 0; e < EMBERS.length; e++) {
  var em = EMBERS[e];
  var ember = shapeLayer(loop, "Ember " + (e + 1), [BX, BY]);
  group(ember).addProperty("ADBE Vector Shape - Ellipse");
  group(ember).property(1).property("ADBE Vector Ellipse Size").setValue([em.size, em.size]);
  addFill(ember, [1.0, 0.80, 0.36, 1]);
  tr(ember).property("ADBE Position").expression =
    "var p = (time + " + em.off + ") % 1;\n[" + (BX + em.dx) + " + " + em.sway + "*Math.sin(p*" + TAU + "*1.5)*p, " + (BY - 110) + " - 168*p];";
  tr(ember).property("ADBE Scale").expression = "var p = (time + " + em.off + ") % 1;\nvar s = 100*(1 - 0.7*p);\n[s, s];";
  tr(ember).property("ADBE Opacity").expression = "var p = (time + " + em.off + ") % 1;\n100*Math.min(p/0.15, 1)*Math.pow(1 - p, 1.2);";
}

// Bloom over the whole flame.
var bloom = loop.layers.addSolid([1, 1, 1], "Bloom", W, H, 1);
bloom.adjustmentLayer = true;
var glow = addFx(bloom, "ADBE Glo2", { "0002": 196, "0003": 16 });
fxProp(bloom, glow, "ADBE Glo2", "0004").expression = 'thisComp.layer("CTRL").effect("Glow")("ADBE Slider Control-0001")';
ctrl.moveToBeginning();

// ---------- Streak_Badge_Events (2x duo card row, sampled by render_streak_flame.jsx) ----------
var ev = app.project.items.addComp("Streak_Badge_Events", 400, 200, 1, 4.2, 60);
ev.bgColor = [0.06, 0.08, 0.12];
var INK = [0.027, 0.047, 0.082];

function evRect(name, x, y, w, h, r, color) {
  var l = shapeLayer(ev, name, [x + w / 2, y + h / 2]);
  group(l).addProperty("ADBE Vector Shape - Rect");
  group(l).property(1).property("ADBE Vector Rect Size").setValue([w, h]);
  group(l).property(1).property("ADBE Vector Rect Roundness").setValue(r);
  addFill(l, color);
  return l;
}
function evText(name, value, x, y, size, color, font) {
  var l = ev.layers.addText(value);
  l.name = name;
  var st = l.property("ADBE Text Properties").property("ADBE Text Document");
  var d = st.value;
  d.resetCharStyle();
  d.font = font;
  d.fontSize = size;
  d.fillColor = color;
  d.applyFill = true;
  d.applyStroke = false;
  d.justification = ParagraphJustification.LEFT_JUSTIFY;
  st.setValue(d);
  tr(l).property("ADBE Position").setValue([x, y]);
  return l;
}
function key(prop, t, v, inf) {
  prop.setValueAtTime(t, v);
  var i = prop.nearestKeyIndex(t);
  var dims = prop.keyInTemporalEase(i).length;
  var a = [];
  for (var d = 0; d < dims; d++) a.push(new KeyframeEase(0, inf || 50));
  prop.setTemporalEaseAtKey(i, a, a);
}

evRect("Card Surface", 12, 20, 376, 160, 24, [INK[0], INK[1], INK[2], 1]);
evRect("Divider", 32, 98, 336, 2, 0, [0.22, 0.30, 0.39, 1]);
evRect("Badge", 32, 40, 60, 44, 12, [0.95, 0.55, 0.20, 1]);
evText("Badge Text", "P1", 44, 72, 26, INK, "Arial-BoldMT");
evText("Score", "5", 112, 82, 50, [0.96, 0.975, 1.0], "Arial-BoldMT");
evText("Score Unit", "\u6B63\u89E3", 144, 80, 20, [0.63, 0.70, 0.80], "YuGothic-Bold");

var flame = ev.layers.add(loop);
flame.name = "Flame";
flame.timeRemapEnabled = true;
flame.property("ADBE Time Remapping").expression = "time % 1";
flame.outPoint = ev.duration;
tr(flame).property("ADBE Anchor Point").setValue([BX, BY]);
tr(flame).property("ADBE Position").setValue([212, 82]);
var FS = 15.6; // 320 comp px -> 50 px at 2x (the 20 x 25 logical-pixel slot)
var sc = tr(flame).property("ADBE Scale");
key(sc, 0.30, [0, 0], 70);
key(sc, 0.42, [FS * 1.22, FS * 1.22], 40);
key(sc, 0.54, [FS * 0.92, FS * 0.92], 45);
key(sc, 0.66, [FS * 1.04, FS * 1.04], 45);
key(sc, 0.78, [FS, FS], 60);
key(sc, 1.40, [FS, FS], 60);
key(sc, 1.48, [FS * 1.14, FS * 1.14], 40);
key(sc, 1.62, [FS * 0.97, FS * 0.97], 45);
key(sc, 1.74, [FS, FS], 60);
key(sc, 3.00, [FS, FS], 40);
key(sc, 3.08, [FS * 1.08, FS * 1.08], 35);
key(sc, 3.40, [0, FS * 0.35], 80);
var op = tr(flame).property("ADBE Opacity");
key(op, 0.30, 0, 50);
key(op, 0.38, 100, 50);
key(op, 3.14, 100, 50);
key(op, 3.40, 0, 60);

var ring = shapeLayer(ev, "Ignite Ring", [212, 60]);
group(ring).addProperty("ADBE Vector Shape - Ellipse");
group(ring).property(1).property("ADBE Vector Ellipse Size").setValue([64, 64]);
group(ring).addProperty("ADBE Vector Graphic - Stroke");
group(ring).property(2).property("ADBE Vector Stroke Color").setValue([1.0, 0.72, 0.28, 1]);
group(ring).property(2).property("ADBE Vector Stroke Width").setValue(3);
var rs = tr(ring).property("ADBE Scale");
key(rs, 0.30, [20, 20], 20);
key(rs, 0.75, [130, 130], 85);
var ro = tr(ring).property("ADBE Opacity");
key(ro, 0.30, 0, 30);
key(ro, 0.36, 100, 30);
key(ro, 0.75, 0, 70);

var count = evText("Count", "2", 240, 82, 36, [1.0, 0.80, 0.34], "Arial-BoldMT");
var cst = count.property("ADBE Text Properties").property("ADBE Text Document");
cst.setValueAtTime(0, cst.value);
var d3 = cst.value;
d3.text = "3";
cst.setValueAtTime(1.40, d3);
var cr = count.sourceRectAtTime(0, false);
tr(count).property("ADBE Anchor Point").setValue([cr.left + cr.width / 2, cr.top + cr.height / 2]);
tr(count).property("ADBE Position").setValue([240 + cr.left + cr.width / 2, 82 + cr.top + cr.height / 2]);
var cs = tr(count).property("ADBE Scale");
key(cs, 0.30, [0, 0], 70);
key(cs, 0.46, [128, 128], 40);
key(cs, 0.60, [96, 96], 45);
key(cs, 0.72, [100, 100], 60);
key(cs, 1.40, [100, 100], 60);
key(cs, 1.47, [138, 138], 40);
key(cs, 1.60, [94, 94], 45);
key(cs, 1.72, [100, 100], 60);
key(cs, 3.00, [100, 100], 40);
key(cs, 3.40, [0, 0], 80);
var co = tr(count).property("ADBE Opacity");
key(co, 0.30, 0, 50);
key(co, 0.40, 100, 50);
key(co, 3.14, 100, 50);
key(co, 3.40, 0, 60);
var unit = evText("Count Unit", "\u9023\u7D9A", 266, 80, 18, [0.98, 0.70, 0.36], "YuGothic-Bold");
var uo = tr(unit).property("ADBE Opacity");
key(uo, 0.30, 0, 50);
key(uo, 0.40, 100, 50);
key(uo, 3.14, 100, 50);
key(uo, 3.40, 0, 60);

// A script-created text layer left selected makes the Properties panel raise
// "internal verification failure (no current context)", which blocks later scripts.
var comps = [loop, ev];
for (var c = 0; c < comps.length; c++) for (var li = 1; li <= comps[c].numLayers; li++) comps[c].layer(li).selected = false;
ev.openInViewer();
var f = new File(AEP);
if (!f.parent.exists) f.parent.create();
app.project.save(f);
app.endSuppressDialogs(false);
return { saved: AEP, loopLayers: loop.numLayers, eventLayers: ev.numLayers };
