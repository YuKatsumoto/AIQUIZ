// AIQUIZ VISION — the main menu LED programme (After Effects 2026, ExtendScript ES3).
// Run through ae_run.mjs (eval.run function body). Idempotent: every item this script
// owns lives in the project folder "AIQUIZ_MenuLED" and is rebuilt.
//
// Canvas 1296x588 (6 px per LED of the 216x98 screen), 60 fps. The screen is only about
// 280x127 px on a 1440p menu, so every segment carries one message in big type.
//
// Motion language: bold round-capped strokes (Trim Paths on straight paths) that sweep
// across and leave colour echoes, after the shape-animation transition in Putti Monkey
// Wrench's "トランジションについて学ぼう -シェイプアニメーション編-": rows of thick
// strokes grow from the left and cover the screen in cream, their tails run off to the
// right to reveal the next scene, and gold / orange / blue copies chase them.
//
//   WIPE_Strokes   the transition between segments (0..0.45 covers, 0.45..1.0 reveals);
//                  Godot plays it over every seam, the segments carry no wipe
//   CUT_Strokes    thin strokes and a flash that hide a cut inside the replay (swap 0.24)
//   BG_Ambient     persistent backdrop (Godot loops one copy under everything)
//   LED_Sting      title card ("HIGHLIGHTS" / "RECORDS"; Godot fills the words)
//   REPLAY_Frame   the replay's corner bugs (REPLAY n/m, fast-forward, match, progress)
//   REPLAY_Caption the moment's name, swept in bottom-left at the moment and out again
//   CLIP_Media     stand-in for the captured frames (Godot draws the clip there)
//   LED_Versus     last local 2P match: panels with speed lines, count-up, WIN burst
//   LED_Solo       last 1P match: score + streak / time card
//   LED_History    four recent matches per page (Godot fills rows, pages through)
//   LED_Stats      all-time: matches, most correct, accuracy ring
//   LED_Logo       AIQUIZ logo on the orange / blue stripes; LED_LogoLoop continues it
//                  seamlessly (8 s cycle) for the minutes the logo stays up
//   LED_Empty      shown until the first match is recorded
//   REPLAY_Demo, LED_ProgramPreview   review only (Godot does not read them)
//
// Helper nulls carry timing Godot reads back: CountProgress / VerdictProgress opacity
// 0..100 is the count-up / verdict progress. Godot reads everything through sample_led.jsx.

var FOLDER = "AIQUIZ_MenuLED";
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var LOGO_PATH = ROOT + "assets/aiquiz_menu_stage/led/led_logo.png";
var CLIP_PATH = ROOT + "assets/aiquiz_menu_stage/source/ae/media/clip_placeholder.jpg";
var SAVE_PATH = ROOT + "assets/aiquiz_menu_stage/source/ae/AIQUIZ_MenuLED.aep";
var W = 1296, H = 588, CX = 648, CY = 294, FPS = 60;
var FONT = "NotoSansJP-Bold";
var LED_BG = [0.055, 0.086, 0.173];
var INK = [0.043, 0.071, 0.125];
var INK2 = [0.098, 0.145, 0.259];
var TRACK = [0.141, 0.2, 0.333];
var PALE = [0.961, 0.969, 1.0];
var MUTED = [0.66, 0.71, 0.81];
var GOLD = [1.0, 0.824, 0.29];
var ORANGE = [0.949, 0.549, 0.2];
var BLUE = [0.2, 0.651, 0.902];
var CREAM = [0.992, 0.976, 0.925];
var RED = [0.937, 0.267, 0.267];
var LEAN = 20; // degrees, the brand's diagonal (top leans right)
var SEAM = 0.45; // WIPE_Strokes: fully covered here
var WIPE_DUR = 1.0;

// ---------------------------------------------------------------- project items

function ownFolder() {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof FolderItem && it.name === FOLDER) return it;
  }
  return app.project.items.addFolder(FOLDER);
}

function clearFolder(f) {
  var comps = [], other = [];
  for (var i = 1; i <= f.numItems; i++) (f.item(i) instanceof CompItem ? comps : other).push(f.item(i));
  for (var c = 0; c < comps.length; c++) { try { comps[c].remove(); } catch (e) {} }
  for (var o = 0; o < other.length; o++) { try { other[o].remove(); } catch (e2) {} }
  for (var i2 = app.project.numItems; i2 >= 1; i2--) {
    var it = app.project.item(i2);
    if (it instanceof FootageItem && it.mainSource instanceof SolidSource && it.usedIn.length === 0 &&
        / \(null\)$/.test(it.name)) it.remove();
  }
  for (var i3 = app.project.numItems; i3 >= 1; i3--) {
    var fo = app.project.item(i3);
    if (fo instanceof FolderItem && fo.name === "Solids" && fo.numItems === 0) fo.remove();
  }
}

function makeComp(f, name, dur, w, h) {
  var c = app.project.items.addComp(name, w || W, h || H, 1, dur, FPS);
  c.parentFolder = f;
  c.bgColor = LED_BG;
  c.motionBlur = false; // Godot draws no motion blur; keep the AE preview faithful
  return c;
}

function importImage(f, path) {
  var item = app.project.importFile(new ImportOptions(new File(path)));
  item.parentFolder = f;
  return item;
}

// ---------------------------------------------------------------- layers

function tr(layer, name) {
  var map = { "Position": "ADBE Position", "Scale": "ADBE Scale", "Rotation": "ADBE Rotate Z",
              "Opacity": "ADBE Opacity", "Anchor Point": "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[name]);
}

function shapeGroup(comp, name) {
  var l = comp.layers.addShape();
  l.name = name;
  var g = l.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  g.name = "Body";
  return l;
}

function vectorsOf(layer) {
  return layer.property("ADBE Root Vectors Group").property(1).property("ADBE Vectors Group");
}

function paint(vectors, fill, fillOpacity, stroke, strokeWidth, cap) {
  if (stroke) {
    var s = vectors.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue(stroke);
    s.property("ADBE Vector Stroke Width").setValue(strokeWidth);
    if (cap) s.property("ADBE Vector Stroke Line Cap").setValue(cap); // 1 butt, 2 round
  }
  if (fill) {
    var fl = vectors.addProperty("ADBE Vector Graphic - Fill");
    fl.property("ADBE Vector Fill Color").setValue(fill);
    fl.property("ADBE Vector Fill Opacity").setValue(fillOpacity == null ? 100 : fillOpacity);
  }
}

// o: {radius, fill, fillOpacity, stroke, strokeWidth, rotation, anchor}
function rect(comp, name, w, h, pos, o) {
  o = o || {};
  var l = shapeGroup(comp, name);
  var v = vectorsOf(l);
  var r = v.addProperty("ADBE Vector Shape - Rect");
  r.property("ADBE Vector Rect Size").setValue([w, h]);
  r.property("ADBE Vector Rect Roundness").setValue(o.radius || 0);
  paint(v, o.fill, o.fillOpacity, o.stroke, o.strokeWidth);
  if (o.anchor) tr(l, "Anchor Point").setValue(o.anchor);
  if (o.rotation) tr(l, "Rotation").setValue(o.rotation);
  tr(l, "Position").setValue(pos);
  return l;
}

// o: {fill, stroke, strokeWidth, trim}
function ellipse(comp, name, d, pos, o) {
  o = o || {};
  var l = shapeGroup(comp, name);
  var v = vectorsOf(l);
  var e = v.addProperty("ADBE Vector Shape - Ellipse");
  e.property("ADBE Vector Ellipse Size").setValue([d, d]);
  if (o.trim) v.addProperty("ADBE Vector Filter - Trim");
  paint(v, o.fill, null, o.stroke, o.strokeWidth, o.cap);
  tr(l, "Position").setValue(pos);
  return l;
}

// A straight open path p0 -> p1 in layer space, stroked with round caps and trimmed.
// The layer sits at the comp origin unless o.pos is given. o: {cap, opacity, pos, rotation}
function line(comp, name, p0, p1, width, colour, o) {
  o = o || {};
  var l = shapeGroup(comp, name);
  var v = vectorsOf(l);
  var path = v.addProperty("ADBE Vector Shape - Group");
  var s = new Shape();
  s.vertices = [p0, p1];
  s.inTangents = [[0, 0], [0, 0]];
  s.outTangents = [[0, 0], [0, 0]];
  s.closed = false;
  path.property("ADBE Vector Shape").setValue(s);
  v.addProperty("ADBE Vector Filter - Trim");
  paint(v, null, null, colour, width, o.cap || 2);
  tr(l, "Anchor Point").setValue([0, 0]);
  tr(l, "Position").setValue(o.pos || [0, 0]);
  if (o.rotation) tr(l, "Rotation").setValue(o.rotation);
  if (o.opacity != null) tr(l, "Opacity").setValue(o.opacity);
  var trim = v.property("ADBE Vector Filter - Trim");
  trim.property("ADBE Vector Trim End").setValue(0);
  return l;
}

function trimProp(layer, which) {
  return vectorsOf(layer).property("ADBE Vector Filter - Trim")
    .property(which === "start" ? "ADBE Vector Trim Start" : "ADBE Vector Trim End");
}

// A stroke that draws on (end 0 -> 100) and, when `out` is given, runs off (start 0 -> 100).
// grow/out: [t0, t1]. The ease leaves fast and lands soft, as the reference strokes do.
function sweep(layer, grow, out) {
  var end = trimProp(layer, "end");
  end.setValueAtTime(grow[0], 0);
  end.setValueAtTime(grow[1], 100);
  setEase(end, 1, 0.1, 55);
  setEase(end, 2, 80, 0.1);
  if (out) {
    var start = trimProp(layer, "start");
    start.setValueAtTime(out[0], 0);
    start.setValueAtTime(out[1], 100);
    setEase(start, 1, 0.1, 55);
    setEase(start, 2, 80, 0.1);
  }
  layer.motionBlur = true;
}

// A stroke segment travelling along its path (head and tail on the same in-out curve).
function chase(layer, head, tail) {
  var end = trimProp(layer, "end"), start = trimProp(layer, "start");
  end.setValueAtTime(head[0], 0);
  end.setValueAtTime(head[1], 100);
  start.setValueAtTime(tail[0], 0);
  start.setValueAtTime(tail[1], 100);
  smooth(end, 55);
  smooth(start, 55);
}

// o: {just: "left"|"center"|"right", tracking, stroke, strokeWidth}
function text(comp, name, str, size, color, pos, o) {
  o = o || {};
  var l = comp.layers.addText(str);
  l.name = name;
  var p = l.property("ADBE Text Properties").property("ADBE Text Document");
  var d = p.value;
  d.resetCharStyle();
  d.resetParagraphStyle();
  d.font = FONT;
  d.fontSize = size;
  d.fillColor = color;
  d.applyFill = true;
  d.justification = o.just === "left" ? ParagraphJustification.LEFT_JUSTIFY
    : (o.just === "right" ? ParagraphJustification.RIGHT_JUSTIFY : ParagraphJustification.CENTER_JUSTIFY);
  d.tracking = o.tracking || 0;
  if (o.stroke) {
    d.applyStroke = true;
    d.strokeColor = o.stroke;
    d.strokeWidth = o.strokeWidth;
    d.strokeOverFill = false;
  } else {
    d.applyStroke = false;
  }
  p.setValue(d);
  // Pivot on the visual centre line: point text sits on its baseline, ~0.36 em below it.
  tr(l, "Anchor Point").setValue([0, -size * 0.36]);
  tr(l, "Position").setValue(pos);
  return l;
}

function nullAt(comp, name, pos) {
  var l = comp.layers.addNull();
  l.name = name;
  l.source.name = name + " (null)";
  l.source.parentFolder = comp.parentFolder; // rebuilt with the folder, not left in "Solids"
  tr(l, "Anchor Point").setValue([0, 0]);
  tr(l, "Position").setValue(pos || [0, 0]);
  return l;
}

function precomp(comp, source, name, start, pos) {
  var l = comp.layers.add(source);
  l.name = name;
  l.startTime = start || 0;
  if (pos) tr(l, "Position").setValue(pos);
  return l;
}

// Parent keeping the child's own values (they are already in the parent's space).
function under(parent, children) {
  for (var i = 0; i < children.length; i++) children[i].setParentWithJump(parent);
}

// ---------------------------------------------------------------- keys and easing

function arity(prop) {
  try {
    var T = PropertyValueType;
    if (prop.propertyValueType === T.TwoD || prop.propertyValueType === T.ThreeD) return prop.value.length;
  } catch (e) {}
  return 1; // OneD, colour and the spatial Position take one ease
}

function setEase(prop, k, inInf, outInf, inSpeed, outSpeed) {
  var n = arity(prop), a = [], b = [];
  for (var d = 0; d < n; d++) {
    a.push(new KeyframeEase(inSpeed || 0, inInf));
    b.push(new KeyframeEase(outSpeed || 0, outInf));
  }
  prop.setInterpolationTypeAtKey(k, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
  prop.setTemporalEaseAtKey(k, a, b);
}

// House settle: leave the first key with pace (out 22), arrive soft at the last (in 75).
function settle(prop) {
  var n = prop.numKeys;
  for (var k = 1; k <= n; k++) setEase(prop, k, k === 1 ? 0.1 : (k === n ? 75 : 60), k === n ? 0.1 : (k === 1 ? 22 : 60));
}

function smooth(prop, inf) {
  for (var k = 1; k <= prop.numKeys; k++) setEase(prop, k, inf, inf);
}

function linear(prop) {
  for (var k = 1; k <= prop.numKeys; k++)
    prop.setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR, KeyframeInterpolationType.LINEAR);
}

// Pop: fast out of the first key, overshoot, settle (focal elements only).
function pop(prop) {
  setEase(prop, 1, 0.1, 12);
  for (var k = 2; k < prop.numKeys; k++) setEase(prop, k, 55, 45);
  setEase(prop, prop.numKeys, 75, 0.1);
}

function straightPath(prop) {
  for (var k = 1; k <= prop.numKeys; k++) {
    try { prop.setSpatialAutoBezierAtKey(k, false); prop.setSpatialContinuousAtKey(k, false); } catch (e) {}
    try { prop.setSpatialTangentsAtKey(k, [0, 0], [0, 0]); } catch (e2) {}
  }
}

// list: [[t, value], ...]; ease: settle | smooth | linear | pop | function(prop)
function keys(layer, name, list, ease) {
  var prop = tr(layer, name);
  for (var i = 0; i < list.length; i++) prop.setValueAtTime(list[i][0], list[i][1]);
  if (name === "Position" || name === "Anchor Point") straightPath(prop);
  (ease || settle)(prop);
  return prop;
}

// The house entrance: rise, 95 -> 100 %, fade in 0.21 s after the move starts.
function reveal(layer, t0, rise, dur) {
  rise = (rise == null ? 32 : rise);
  dur = dur || 0.7;
  var p = tr(layer, "Position").value, s = tr(layer, "Scale").value;
  keys(layer, "Position", [[t0, [p[0], p[1] + rise]], [t0 + dur, [p[0], p[1]]]]);
  keys(layer, "Scale", [[t0, [s[0] * 0.95, s[1] * 0.95]], [t0 + dur, [s[0], s[1]]]]);
  fadeIn(layer, t0 + 0.21, 0.12);
  layer.motionBlur = true;
}

function fadeIn(layer, t0, dur) {
  keys(layer, "Opacity", [[t0, 0], [t0 + (dur || 0.12), 100]], function (p) { smooth(p, 40); });
}

// Scale pop of a focal element from `from` % to 100 via an overshoot.
function popIn(layer, t0, from, over) {
  var s = tr(layer, "Scale").value;
  over = over || 106;
  keys(layer, "Scale", [[t0, [s[0] * from / 100, s[1] * from / 100]], [t0 + 0.2, [s[0] * over / 100, s[1] * over / 100]],
                        [t0 + 0.36, [s[0], s[1]]]], pop);
  fadeIn(layer, t0, 0.08);
  layer.motionBlur = true;
}

// A short scale beat (count landed, verdict).
function pulse(layer, t0, amount) {
  var s = tr(layer, "Scale").value;
  keys(layer, "Scale", [[t0, s], [t0 + 0.12, [s[0] * amount / 100, s[1] * amount / 100]], [t0 + 0.32, s]], function (p) {
    setEase(p, 1, 0.1, 40); setEase(p, 2, 50, 50); setEase(p, 3, 75, 0.1);
  });
}

// Two thin strokes streaking in the direction of an entrance (speed lines).
function speedLines(comp, name, fromX, toX, ys, t0, colours) {
  var made = [];
  for (var i = 0; i < ys.length; i++) {
    var l = line(comp, name + (i + 1), [fromX, ys[i]], [toX, ys[i]], i === 0 ? 16 : 10, colours[i % colours.length]);
    sweep(l, [t0 + i * 0.04, t0 + 0.32 + i * 0.04], [t0 + 0.16 + i * 0.04, t0 + 0.52 + i * 0.04]);
    made.push(l);
  }
  return made;
}

// ---------------------------------------------------------------- shared pieces

// Slow diagonal bands on the LED navy; one 8 s cycle moves them exactly one spacing.
function buildAmbient(f) {
  var dur = 8.0, spacing = 432;
  var c = makeComp(f, "BG_Ambient", dur);
  rect(c, "Base", W, H, [CX, CY], { fill: LED_BG });
  for (var i = 0; i < 6; i++) {
    var x = -432 + i * spacing;
    var band = rect(c, "Band" + (i + 1), 190, 1100, [x, CY], { fill: INK2, fillOpacity: 42, rotation: LEAN });
    keys(band, "Position", [[0, [x, CY]], [dur, [x + spacing, CY]]], linear);
  }
  return c;
}

// Six rows of 108 px round-capped strokes (the rows are 98 px apart, so neighbours
// overlap). Cream heads grow left -> right, staggered per row, and cover the screen by
// SEAM; their tails then run off to the right while gold, orange and blue echoes chase
// them. Everything has left the screen by WIPE_DUR.
function buildWipe(f) {
  var c = makeComp(f, "WIPE_Strokes", WIPE_DUR);
  var lag = [0.0, 0.05, 0.015, 0.075, 0.03, 0.06];
  var echoes = [GOLD, ORANGE, BLUE];
  for (var r = 0; r < 6; r++) {
    var y = 49 + r * 98, d = lag[r];
    var cover = line(c, "Cover" + (r + 1), [-90, y], [1386, y], 108, CREAM);
    sweep(cover, [d * 1.2, 0.40]);
    // The cream tail and its echoes share one in-out curve: the echoes are short
    // capsules right behind the tail, each copy 0.035 s behind the last.
    var tail = trimProp(cover, "start");
    tail.setValueAtTime(SEAM + d * 0.4, 0);
    tail.setValueAtTime(0.8 + d * 0.4, 100);
    smooth(tail, 55);
    for (var k = 0; k < echoes.length; k++) {
      var e = 0.02 + 0.035 * k + d * 0.4;
      var echo = line(c, "Echo" + (r + 1) + "_" + (k + 1), [-90, y], [1386, y], k === 1 ? 108 : 92, echoes[k]);
      chase(echo, [SEAM + e, 0.8 + e], [SEAM + e + 0.05, Math.min(0.85 + e, WIPE_DUR - 0.005)]);
    }
  }
  return c;
}

// Hides a cut inside the replay: four strokes of different weights zip across and a
// cream flash peaks at the swap (0.24 s).
function buildCut(f) {
  var c = makeComp(f, "CUT_Strokes", 0.6);
  var flash = rect(c, "Flash", W, H, [CX, CY], { fill: CREAM });
  keys(flash, "Opacity", [[0.14, 0], [0.24, 42], [0.42, 0]], function (p) { smooth(p, 45); });
  var rows = [[118, 34, GOLD, 0.0], [252, 72, CREAM, 0.04], [382, 26, BLUE, 0.02], [486, 50, ORANGE, 0.06]];
  for (var i = 0; i < rows.length; i++) {
    var l = line(c, "Zip" + (i + 1), [-80, rows[i][0]], [1376, rows[i][0]], rows[i][1], rows[i][2]);
    sweep(l, [rows[i][3], 0.28 + rows[i][3]], [0.12 + rows[i][3], 0.5 + rows[i][3]]);
  }
  return c;
}

function header(comp, str, t0) {
  var pill = rect(comp, "HeaderPill", 520, 76, [CX, 64], { radius: 38, fill: INK2 });
  var label = text(comp, "HeaderText", str, 44, PALE, [CX, 64], { tracking: 40 });
  var accent = line(comp, "HeaderAccent", [CX - 240, 106], [CX + 240, 106], 6, GOLD);
  sweep(accent, [t0 + 0.2, t0 + 0.6]);
  reveal(pill, t0, -24);
  reveal(label, t0 + 0.06, -24);
}

// ---------------------------------------------------------------- segments

function buildSting(f, ambient) {
  var dur = 2.4;
  var c = makeComp(f, "LED_Sting", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  // Two bold strokes cross behind the title from opposite sides, echoes riding with them.
  sweep(line(c, "SwipeA", [-120, 232], [1416, 232], 120, ORANGE), [0.04, 0.40], [0.26, 0.68]);
  sweep(line(c, "SwipeAEcho", [-120, 186], [1416, 186], 18, GOLD), [0.10, 0.44], [0.30, 0.70]);
  sweep(line(c, "SwipeB", [1416, 356], [-120, 356], 120, BLUE), [0.10, 0.46], [0.32, 0.74]);
  sweep(line(c, "SwipeBEcho", [1416, 404], [-120, 404], 14, CREAM), [0.16, 0.50], [0.36, 0.78]);
  var title = text(c, "TitleText", "HIGHLIGHTS", 150, CREAM, [CX, 258], { tracking: 20 });
  popIn(title, 0.36, 70, 107);
  var left = line(c, "UnderlineL", [CX - 8, 352], [CX - 300, 352], 16, ORANGE);
  var right = line(c, "UnderlineR", [CX + 8, 352], [CX + 300, 352], 16, BLUE);
  sweep(left, [0.58, 0.96]);
  sweep(right, [0.58, 0.96]);
  var pill = rect(c, "SubPill", 300, 68, [CX, 446], { radius: 34, fill: GOLD });
  var sub = text(c, "SubText", "ハイライト", 44, INK, [CX, 446], { tracking: 60 });
  reveal(pill, 0.66, 28);
  reveal(sub, 0.72, 28);
  return c;
}

// Corner bugs over the full-bleed clip. Nothing crosses the picture: the old full-width
// caption band hid the runners. The dot pulses once a second (Godot loops this comp).
function buildReplayFrame(f) {
  var dur = 6.0;
  var c = makeComp(f, "REPLAY_Frame", dur);
  var group = nullAt(c, "ReplayGroup", [0, 0]);
  var pill = rect(c, "ReplayPill", 280, 60, [40, 60], { radius: 30, fill: INK, fillOpacity: 86, anchor: [-140, 0] });
  var dot = ellipse(c, "ReplayDot", 22, [76, 60], { fill: RED });
  var word = text(c, "ReplayText", "REPLAY  2/5", 34, CREAM, [98, 60], { just: "left", tracking: 60 });
  under(group, [pill, dot, word]);
  var beat = [];
  for (var t = 0; t <= dur + 0.001; t += 0.5) beat.push([t, (Math.round(t * 2) % 2) === 0 ? 100 : 20]);
  keys(dot, "Opacity", beat, function (p) { smooth(p, 50); });
  var fast = nullAt(c, "FastGroup", [0, 0]);
  var fastPill = rect(c, "FastPill", 152, 60, [336, 60], { radius: 30, fill: GOLD, anchor: [-76, 0] });
  var fastText = text(c, "FastText", "▶▶ 2x", 32, INK, [412, 60], { tracking: 20 });
  under(fast, [fastPill, fastText]);
  var info = rect(c, "InfoPill", 336, 60, [1256, 60], { radius: 30, fill: INK, fillOpacity: 86, anchor: [168, 0] });
  var infoText = text(c, "InfoText", "9/29  10問バトル", 32, PALE, [1232, 60], { just: "right" });
  rect(c, "ProgressTrack", W, 8, [CX, 584], { fill: INK, fillOpacity: 70 });
  rect(c, "Progress", W, 8, [0, 584], { fill: GOLD, anchor: [-W / 2, 0] });
  return c;
}

// The moment's name: a band in the player's colour grows from the left edge
// (bottom-left, clear of the runners), the words slide in, then the band's tail runs
// off to the right. Godot lengthens the band to fit the words.
function buildCaption(f) {
  var dur = 2.8;
  var c = makeComp(f, "REPLAY_Caption", dur);
  var band = line(c, "CapBand", [-80, 520], [540, 520], 88, ORANGE);
  sweep(band, [0.0, 0.3], [2.32, 2.74]);
  var over = line(c, "CapEchoTop", [-80, 464], [390, 464], 12, GOLD);
  sweep(over, [0.07, 0.36], [2.24, 2.62]);
  var below = line(c, "CapEchoBottom", [-80, 576], [290, 576], 8, CREAM);
  sweep(below, [0.11, 0.4], [2.28, 2.66]);
  var words = text(c, "CapText", "3連続正解！", 56, INK, [36, 520], { just: "left" });
  keys(words, "Position", [[0.14, [0, 520]], [0.5, [36, 520]]]);
  keys(words, "Opacity", [[0.16, 0], [0.24, 100], [2.3, 100], [2.4, 0]], function (p) { smooth(p, 40); });
  words.motionBlur = true;
  return c;
}

function buildClipMedia(f, clipFootage) {
  var media = makeComp(f, "CLIP_Media", 6.0);
  var plate = media.layers.add(clipFootage);
  plate.name = "ClipPlaceholder";
  var fit = Math.max(W / clipFootage.width, H / clipFootage.height) * 100;
  tr(plate, "Scale").setValue([fit, fit]);
  tr(plate, "Position").setValue([CX, CY]);
  return media;
}

// Review only: the replay as Godot composes it (clip, corner bugs, a caption, a cut).
function buildReplayDemo(f, ambient, media, frame, caption, cut) {
  var c = makeComp(f, "REPLAY_Demo", 6.0);
  precomp(c, ambient, "BG_Ambient", 0);
  var clip = precomp(c, media, "ClipMedia", 0);
  keys(clip, "Scale", [[0, [100, 100]], [6, [104, 104]]], function (p) { smooth(p, 60); });
  precomp(c, frame, "Frame", 0);
  precomp(c, caption, "Caption", 1.2);
  precomp(c, cut, "Cut", 5.0);
  return c;
}

function playerPanel(c, index, x, colour, score) {
  var name = "P" + index;
  // Speed lines first, so they run beneath the panel along its top and bottom edges.
  var edge = index === 1 ? [-80, 700] : [1376, 596];
  speedLines(c, name + "Speed", edge[0], edge[1], [150, 542], 0.3, [index === 1 ? GOLD : CREAM, colour]);
  var group = nullAt(c, name + "Group", [0, 0]);
  var panel = rect(c, name + "Panel", 552, 380, [x, 346], { radius: 24, fill: colour });
  var label = text(c, name + "Label", name, 64, INK, [x, 208], { tracking: 40 });
  var value = text(c, name + "Score", score, 176, CREAM, [x, 352], { stroke: INK, strokeWidth: 10 });
  var detail = text(c, name + "Detail", "正解 5", 48, INK, [x, 484]);
  under(group, [panel, label, value, detail]);
  var from = index === 1 ? -700 : 700, over = index === 1 ? 14 : -14;
  keys(group, "Position", [[0.3, [from, 0]], [0.82, [over, 0]], [1.02, [0, 0]]]);
  group.motionBlur = true;
  pulse(value, 2.6, 112);
  return group;
}

function buildVersus(f, ambient) {
  var dur = 5.6;
  var c = makeComp(f, "LED_Versus", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  playerPanel(c, 1, 324, ORANGE, "12.5");
  playerPanel(c, 2, 972, BLUE, "8.0");
  header(c, "前回の対戦", 0.4);
  var vs = nullAt(c, "VsGroup", [CX, 346]);
  var disk = ellipse(c, "VsDisk", 136, [0, 0], { fill: INK });
  var ring = ellipse(c, "VsRing", 150, [0, 0], { stroke: CREAM, strokeWidth: 6, trim: true, cap: 2 });
  var word = text(c, "VsText", "VS", 56, CREAM, [0, 0], { tracking: 20 });
  under(vs, [disk, ring, word]);
  keys(vs, "Scale", [[0.85, [0, 0]], [1.02, [112, 112]], [1.16, [100, 100]]], pop);
  var ringEnd = trimProp(ring, "end");
  ringEnd.setValueAtTime(0.95, 0);
  ringEnd.setValueAtTime(1.35, 100);
  settle(ringEnd);
  // Winner badge on the winner panel's top-right corner (Godot moves it to P2's or, for
  // a draw, to the centre); a burst of short gold strokes flies out of it.
  var win = nullAt(c, "WinGroup", [548, 168]);
  tr(win, "Rotation").setValue(8);
  var parts = [];
  for (var i = 0; i < 10; i++) {
    var a = i / 10 * Math.PI * 2;
    var ray = line(c, "Burst" + (i + 1), [Math.cos(a) * 118, Math.sin(a) * 60], [Math.cos(a) * 190, Math.sin(a) * 104], 8, i % 2 ? CREAM : GOLD);
    sweep(ray, [3.02, 3.22], [3.14, 3.42]);
    parts.push(ray);
  }
  parts.push(rect(c, "WinPill", 208, 72, [0, 0], { radius: 36, fill: GOLD, stroke: INK, strokeWidth: 6 }));
  parts.push(text(c, "WinText", "WIN!", 48, INK, [0, 0], { tracking: 60 }));
  under(win, parts);
  keys(win, "Scale", [[3.0, [0, 0]], [3.16, [116, 116]], [3.32, [100, 100]]], pop);
  var count = nullAt(c, "CountProgress", [0, 0]);
  keys(count, "Opacity", [[1.0, 0], [2.6, 100]]);
  var verdict = nullAt(c, "VerdictProgress", [0, 0]);
  keys(verdict, "Opacity", [[2.95, 0], [3.25, 100]], function (p) { smooth(p, 50); });
  return c;
}

function buildSolo(f, ambient) {
  var dur = 5.2;
  var c = makeComp(f, "LED_Solo", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  header(c, "前回のプレイ", 0.4);
  speedLines(c, "ScoreSpeed", -80, 700, [236, 470], 0.3, [GOLD, ORANGE]);
  var label = text(c, "ScoreLabel", "正解", 52, GOLD, [380, 184]);
  var score = text(c, "ScoreText", "8/10", 200, CREAM, [380, 336]);
  var sub = text(c, "ScoreSub", "10問チャレンジ", 44, PALE, [380, 500]);
  reveal(label, 0.45, 24);
  popIn(score, 0.55, 78, 104);
  pulse(score, 2.4, 110);
  reveal(sub, 0.7, 24);
  var card = rect(c, "StatCard", 560, 360, [948, 346], { radius: 24, fill: INK2 });
  reveal(card, 0.6, 36);
  var rows = [["Row1", "最大連続", "5", 262], ["Row2", "プレイ時間", "84秒", 430]];
  for (var i = 0; i < rows.length; i++) {
    var y = rows[i][3];
    var l = text(c, rows[i][0] + "Label", rows[i][1], 44, MUTED, [708, y], { just: "left" });
    var v = text(c, rows[i][0] + "Value", rows[i][2], 96, CREAM, [1188, y], { just: "right" });
    reveal(l, 0.78 + i * 0.15, 20);
    reveal(v, 0.84 + i * 0.15, 20);
  }
  sweep(line(c, "StatRule", [708, 346], [1188, 346], 4, TRACK), [0.9, 1.3]);
  var count = nullAt(c, "CountProgress", [0, 0]);
  keys(count, "Opacity", [[1.0, 0], [2.4, 100]]);
  return c;
}

// Four recent matches. Each row slides in from the right behind a gold streak along its
// lower edge; Godot fills the rows (hidden when fewer matches) and plays the comp again
// for a second page.
function buildHistory(f, ambient) {
  var dur = 6.6;
  var c = makeComp(f, "LED_History", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  header(c, "勝負の記録", 0.34);
  for (var r = 1; r <= 4; r++) {
    var y = 176 + (r - 1) * 112, t0 = 0.46 + (r - 1) * 0.12, n = "R" + r;
    var streak = line(c, n + "Streak", [1376, y + 50], [40, y + 50], 6, GOLD);
    sweep(streak, [t0 - 0.06, t0 + 0.28], [t0 + 0.1, t0 + 0.46]);
    var group = nullAt(c, n + "Group", [0, 0]);
    var parts = [
      rect(c, n + "Box", 1200, 96, [CX, y], { radius: 20, fill: INK2 }),
      rect(c, n + "Accent", 12, 64, [78, y], { radius: 6, fill: GOLD }),
      text(c, n + "Date", "9/29", 40, MUTED, [104, y], { just: "left" }),
      rect(c, n + "ModePill", 256, 56, [214, y], { radius: 28, fill: TRACK, anchor: [-128, 0] }),
      text(c, n + "ModeText", "10問バトル", 30, PALE, [234, y], { just: "left" }),
      ellipse(c, n + "P1Chip", 52, [570, y], { fill: ORANGE }),
      text(c, n + "P1ChipText", "P1", 24, INK, [570, y]),
      text(c, n + "P1Val", "28.0", 56, CREAM, [740, y], { just: "right" }),
      text(c, n + "Vs", "VS", 28, MUTED, [782, y], { tracking: 20 }),
      text(c, n + "P2Val", "13.5", 56, CREAM, [824, y], { just: "left" }),
      ellipse(c, n + "P2Chip", 52, [996, y], { fill: BLUE }),
      text(c, n + "P2ChipText", "P2", 24, INK, [996, y]),
      rect(c, n + "ResultPill", 176, 60, [1236, y], { radius: 30, fill: GOLD, anchor: [88, 0] }),
      text(c, n + "ResultText", "P1 WIN", 32, INK, [1148, y], { tracking: 20 })
    ];
    under(group, parts);
    keys(group, "Position", [[t0, [180, 0]], [t0 + 0.6, [0, 0]]]);
    group.motionBlur = true;
    for (var p = 0; p < parts.length; p++) fadeIn(parts[p], t0 + 0.08, 0.14);
  }
  return c;
}

function buildStats(f, ambient) {
  var dur = 6.0;
  var c = makeComp(f, "LED_Stats", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  header(c, "これまでの記録", 0.36);
  var tiles = [
    { x: 232, accent: ORANGE, label: "あそんだ回数", value: "24", unit: "回" },
    { x: 648, accent: GOLD, label: "最多正解", value: "9", unit: "問" },
    { x: 1064, accent: BLUE, label: "正答率", value: "78%", ring: true }
  ];
  var ring = null;
  for (var i = 0; i < tiles.length; i++) {
    var t = tiles[i], n = "T" + (i + 1), t0 = 0.42 + i * 0.15;
    var group = nullAt(c, n + "Group", [t.x, 350]);
    var box = rect(c, n + "Box", 368, 360, [0, 0], { radius: 24, fill: INK2 });
    var bar = line(c, n + "Bar", [-160, -156], [160, -156], 10, t.accent);
    sweep(bar, [t0 + 0.3, t0 + 0.72]);
    var parts = [box, bar, text(c, n + "Label", t.label, 44, MUTED, [0, -104])];
    var value;
    if (t.ring) {
      parts.push(ellipse(c, n + "RingTrack", 196, [0, 36], { stroke: TRACK, strokeWidth: 24 }));
      ring = ellipse(c, n + "Ring", 196, [0, 36], { stroke: t.accent, strokeWidth: 24, trim: true, cap: 2 });
      parts.push(ring);
      value = text(c, n + "Value", t.value, 72, CREAM, [0, 36]);
    } else {
      value = text(c, n + "Value", t.value, 144, CREAM, [0, 22]);
      parts.push(text(c, n + "Unit", t.unit, 44, PALE, [0, 132]));
    }
    parts.push(value);
    under(group, parts);
    keys(group, "Position", [[t0, [t.x, 350 + 36]], [t0 + 0.7, [t.x, 350]]]);
    keys(group, "Scale", [[t0, [95, 95]], [t0 + 0.7, [100, 100]]]);
    group.motionBlur = true;
    for (var p = 0; p < parts.length; p++) if (parts[p] !== bar) fadeIn(parts[p], t0 + 0.21, 0.12);
    pulse(value, 2.3, 110);
  }
  speedLines(c, "TileSpeed", -80, 1376, [150, 548], 0.34, [GOLD, CREAM]);
  var end = trimProp(ring, "end");
  end.setValueAtTime(0.95, 0);
  end.setValueAtTime(2.3, 100);
  settle(end);
  var count = nullAt(c, "CountProgress", [0, 0]);
  keys(count, "Opacity", [[0.95, 0], [2.3, 100]]);
  return c;
}

// Seven stripes 170 px apart in a half-width comp; `shift` moves them over the comp's
// duration, so the intro and the loop continue each other (8 s per spacing).
function stripes(f, name, colour, dur, from, to) {
  var c = makeComp(f, name, dur, W / 2, H);
  c.bgColor = LED_BG;
  for (var i = 0; i < 7; i++) {
    var x = -340 + i * 170;
    var bar = rect(c, "Bar" + (i + 1), 84, 900, [x + from, CY], { fill: colour, rotation: LEAN });
    keys(bar, "Position", [[0, [x + from, CY]], [dur, [x + to, CY]]], linear);
  }
  return c;
}

function logoLayers(c, f, logoFootage, dur, from, to, prefix) {
  precomp(c, stripes(f, prefix + "StripesL", ORANGE, dur, from, to), "StripesL", 0, [W / 4, CY]);
  precomp(c, stripes(f, prefix + "StripesR", BLUE, dur, -from, -to), "StripesR", 0, [W * 3 / 4, CY]);
  // A navy diagonal gap over the vertical seam between the two stripe halves.
  rect(c, "CentreGap", 240, 900, [CX, CY], { fill: LED_BG, rotation: LEAN });
  var plate = rect(c, "Plate", 900, 320, [CX, CY], { radius: 24, fill: LED_BG, stroke: CREAM, strokeWidth: 8 });
  var logo = c.layers.add(logoFootage);
  logo.name = "Logo";
  tr(logo, "Position").setValue([CX, CY]);
  var s = 700 / logoFootage.width * 100;
  tr(logo, "Scale").setValue([s, s]);
  return { plate: plate, logo: logo, scale: s };
}

// Life for the long logo hold: inside the plate a gold stroke runs under the logo
// left -> right while a cream one runs over it right -> left, then both run off.
function glint(c, t0) {
  sweep(line(c, "GlintLow", [CX - 380, CY + 118], [CX + 380, CY + 118], 10, GOLD), [t0, t0 + 0.5], [t0 + 0.34, t0 + 0.86]);
  sweep(line(c, "GlintHigh", [CX + 380, CY - 118], [CX - 380, CY - 118], 6, CREAM), [t0 + 0.08, t0 + 0.58], [t0 + 0.42, t0 + 0.94]);
}

function buildLogo(f, ambient, logoFootage) {
  var dur = 3.2;
  var c = makeComp(f, "LED_Logo", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  var parts = logoLayers(c, f, logoFootage, dur, 0, 170 * dur / 8, "LOGO_");
  reveal(parts.plate, 0.2, 0);
  var s = parts.scale;
  keys(parts.logo, "Scale", [[0.4, [s * 0.9, s * 0.9]], [0.47, [s * 0.92, s * 0.92]], [0.67, [s * 1.05, s * 1.05]],
                             [0.8, [s, s]]]);
  fadeIn(parts.logo, 0.4, 0.14);
  sweep(line(c, "LogoSwipe", [-120, 470], [1416, 470], 40, GOLD), [0.3, 0.7], [0.5, 0.95]);
  sweep(line(c, "LogoSwipe2", [1416, 118], [-120, 118], 26, CREAM), [0.36, 0.76], [0.56, 1.0]);
  glint(c, 1.5);
  return c;
}

// Continues LED_Logo without a seam and loops on itself: Godot repeats it for the
// minutes the logo stays up after a round.
function buildLogoLoop(f, ambient, logoFootage) {
  var dur = 8.0;
  var c = makeComp(f, "LED_LogoLoop", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  var from = 170 * 3.2 / 8;
  logoLayers(c, f, logoFootage, dur, from, from + 170, "LOOP_");
  glint(c, 3.4);
  return c;
}

function buildEmpty(f, ambient) {
  var dur = 4.4;
  var c = makeComp(f, "LED_Empty", dur);
  precomp(c, ambient, "BG_Ambient", 0);
  sweep(line(c, "SwipeA", [-120, 170], [1416, 170], 18, GOLD), [0.1, 0.46], [0.3, 0.72]);
  sweep(line(c, "SwipeB", [1416, 440], [-120, 440], 14, CREAM), [0.16, 0.52], [0.36, 0.78]);
  var title = text(c, "EmptyTitle", "まだ記録がないよ", 96, CREAM, [CX, 240]);
  var sub = text(c, "EmptySub", "あそぶと ここにハイライトがうつるよ！", 48, GOLD, [CX, 368]);
  popIn(title, 0.36, 80, 104);
  reveal(sub, 0.56, 24);
  return c;
}

// The whole programme as Godot plays it (one clip, one history page), with the wipe on
// every seam, for review in AE only.
function buildPreview(f, parts, wipe) {
  var total = 0;
  for (var i = 0; i < parts.length; i++) total += parts[i].duration;
  var c = makeComp(f, "LED_ProgramPreview", total);
  var t = 0;
  for (var j = 0; j < parts.length; j++) {
    var l = c.layers.add(parts[j]);
    l.startTime = t;
    l.moveToBeginning();
    t += parts[j].duration;
    var seamless = j + 1 < parts.length && parts[j].name === "LED_Logo" && parts[j + 1].name === "LED_LogoLoop";
    if (j + 1 < parts.length && !seamless) {
      var w = c.layers.add(wipe);
      w.name = "Wipe" + (j + 1);
      w.startTime = t - SEAM;
      w.moveToBeginning();
    }
  }
  return c;
}

// ---------------------------------------------------------------- build

app.beginUndoGroup("AIQUIZ Menu LED");
var f = ownFolder();
clearFolder(f);
var logoFootage = importImage(f, LOGO_PATH);
var clipFootage = importImage(f, CLIP_PATH);
var ambient = buildAmbient(f);
var wipe = buildWipe(f);
var cut = buildCut(f);
var sting = buildSting(f, ambient);
var frame = buildReplayFrame(f);
var caption = buildCaption(f);
var media = buildClipMedia(f, clipFootage);
var replayDemo = buildReplayDemo(f, ambient, media, frame, caption, cut);
var versus = buildVersus(f, ambient);
var solo = buildSolo(f, ambient);
var history = buildHistory(f, ambient);
var stats = buildStats(f, ambient);
var logo = buildLogo(f, ambient, logoFootage);
var logoLoop = buildLogoLoop(f, ambient, logoFootage);
var empty = buildEmpty(f, ambient);
buildPreview(f, [sting, replayDemo, sting, versus, history, stats, logo, logoLoop], wipe);
app.endUndoGroup();
app.project.save(new File(SAVE_PATH));
var out = {};
for (var i = 1; i <= f.numItems; i++) {
  var it = f.item(i);
  if (it instanceof CompItem) out[it.name] = { layers: it.numLayers, duration: it.duration };
}
return { saved: SAVE_PATH, comps: out };
