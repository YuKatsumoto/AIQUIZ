// Score Tower Finale — HUD and FX compositions (After Effects 2026, ExtendScript ES3).
// Run through ae_run.mjs (eval.run function body). Idempotent: every item this script
// owns lives in the project folder "AIQUIZ_ScoreTowerFinale" and is rebuilt.
//
// Structure (1280x720, 60 fps):
//   FINALE_HUD_Win / FINALE_HUD_Draw   master comps, keys at real ceremony seconds
//     HUD_Title, HUD_Rule, HUD_CardP1, HUD_CardP2, HUD_WinTag, HUD_VerdictWin|Draw,
//     HUD_Actions, FX_Burst (preview only)
//   Precomps hold static native art (text + rect/ellipse shapes); card reveals
//   (correct -> HP -> total) are keyed inside the card precomps.
//   FX_Burst / FX_LockRing are white-on-alpha effects rendered to PNG for Godot.
// Godot reads everything back through sample_hud.jsx (transforms, layout, colours).

var FOLDER = "AIQUIZ_ScoreTowerFinale";
var FONT = "NotoSansJP-Bold";
var FPS = 60;
var INK = [0.043, 0.071, 0.125];
var INK2 = [0.086, 0.125, 0.227];
var PALE = [0.961, 0.969, 1.0];
var MUTED = [0.604, 0.655, 0.761];
var GOLD = [1.0, 0.824, 0.29];
var P1 = [0.95, 0.55, 0.20];
var P2 = [0.20, 0.65, 0.90];
var WHITE = [1, 1, 1];

function folder() {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof FolderItem && it.name === FOLDER) return it;
  }
  return app.project.items.addFolder(FOLDER);
}

function removeOwned(f) {
  // remove comps inside our folder (children first so nothing references them)
  var list = [];
  for (var i = 1; i <= f.numItems; i++) list.push(f.item(i));
  for (var j = 0; j < list.length; j++) {
    try { list[j].remove(); } catch (e) {}
  }
}

function makeComp(f, name, w, h, dur, fps) {
  var c = app.project.items.addComp(name, w, h, 1, dur, fps || FPS);
  c.parentFolder = f;
  c.bgColor = [0.12, 0.16, 0.22];
  return c;
}

function tr(layer, name) {
  var map = { "Position": "ADBE Position", "Scale": "ADBE Scale", "Rotation": "ADBE Rotate Z",
              "Opacity": "ADBE Opacity", "Anchor Point": "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[name]);
}

function rectLayer(comp, name, w, h, radius, pos, fill, fillOpacity, stroke, strokeWidth) {
  var l = comp.layers.addShape();
  l.name = name;
  var g = l.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  g.name = "Box";
  var v = g.property("ADBE Vectors Group");
  var r = v.addProperty("ADBE Vector Shape - Rect");
  r.property("ADBE Vector Rect Size").setValue([w, h]);
  r.property("ADBE Vector Rect Roundness").setValue(radius);
  if (stroke) {
    var s = v.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue(stroke);
    s.property("ADBE Vector Stroke Width").setValue(strokeWidth);
  }
  if (fill) {
    var fl = v.addProperty("ADBE Vector Graphic - Fill");
    fl.property("ADBE Vector Fill Color").setValue(fill);
    fl.property("ADBE Vector Fill Opacity").setValue(fillOpacity == null ? 100 : fillOpacity);
  }
  tr(l, "Position").setValue(pos);
  return l;
}

function ellipseLayer(comp, name, d, pos, fill, stroke, strokeWidth) {
  var l = comp.layers.addShape();
  l.name = name;
  var g = l.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  g.name = "Ring";
  var v = g.property("ADBE Vectors Group");
  var e = v.addProperty("ADBE Vector Shape - Ellipse");
  e.property("ADBE Vector Ellipse Size").setValue([d, d]);
  if (stroke) {
    var s = v.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue(stroke);
    s.property("ADBE Vector Stroke Width").setValue(strokeWidth);
  }
  if (fill) {
    var fl = v.addProperty("ADBE Vector Graphic - Fill");
    fl.property("ADBE Vector Fill Color").setValue(fill);
  }
  tr(l, "Position").setValue(pos);
  return l;
}

function textLayer(comp, name, str, size, color, pos, strokeColor, strokeWidth, tracking) {
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
  d.justification = ParagraphJustification.CENTER_JUSTIFY;
  d.tracking = tracking || 0;
  if (strokeColor) {
    d.applyStroke = true;
    d.strokeColor = strokeColor;
    d.strokeWidth = strokeWidth;
    d.strokeOverFill = false;
  } else {
    d.applyStroke = false;
  }
  p.setValue(d);
  // Pivot on the visual centre: point text sits on its baseline, ~0.36 em below it.
  l.property("ADBE Transform Group").property("ADBE Anchor Point").setValue([0, -size * 0.36]);
  tr(l, "Position").setValue(pos);
  return l;
}

function arity(prop) {
  try {
    if (prop.propertyValueType === PropertyValueType.TwoD || prop.propertyValueType === PropertyValueType.ThreeD) {
      return prop.value.length;
    }
  } catch (e) {}
  return 1;
}

// keys: [[t, value, inInfluence, outInfluence, hold], ...]; influences default 75/22 (settle)
function keys(layer, propName, list) {
  var prop = tr(layer, propName);
  for (var i = 0; i < list.length; i++) prop.setValueAtTime(list[i][0], list[i][1]);
  var n = arity(prop);
  for (var k = 0; k < list.length; k++) {
    var idx = prop.nearestKeyIndex(list[k][0]);
    if (list[k][4]) {
      prop.setInterpolationTypeAtKey(idx, KeyframeInterpolationType.HOLD, KeyframeInterpolationType.HOLD);
      continue;
    }
    prop.setInterpolationTypeAtKey(idx, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
    var inf = list[k][2] == null ? 75 : list[k][2];
    var outf = list[k][3] == null ? 22 : list[k][3];
    var a = [], b = [];
    for (var d = 0; d < n; d++) { a.push(new KeyframeEase(0, inf)); b.push(new KeyframeEase(0, outf)); }
    try { prop.setTemporalEaseAtKey(idx, a, b); } catch (e) {}
  }
  return prop;
}

function addPre(parent, child, pos, name) {
  var l = parent.layers.add(child);
  l.name = name || child.name;
  l.startTime = 0;
  tr(l, "Position").setValue(pos);
  return l;
}

function glow(layer, radius, intensity) {
  var fx = layer.property("ADBE Effect Parade").addProperty("ADBE Glo2");
  try { fx.property("ADBE Glo2-0002").setValue(60); } catch (e) {}      // threshold %
  try { fx.property("ADBE Glo2-0003").setValue(radius); } catch (e) {}  // radius
  try { fx.property("ADBE Glo2-0004").setValue(intensity); } catch (e) {} // intensity
  return fx;
}

// ------------------------------------------------------------------ precomps

function buildTitle(f) {
  var c = makeComp(f, "HUD_Title", 560, 96, 13, FPS);
  rectLayer(c, "TitlePill", 480, 64, 32, [280, 48], INK, 92, GOLD, 3);
  textLayer(c, "TitleText", "スコアタワー", 32, PALE, [280, 48], null, 0, 80);
  ellipseLayer(c, "TitleStarL", 12, [88, 48], GOLD, null, 0);
  ellipseLayer(c, "TitleStarR", 12, [472, 48], GOLD, null, 0);
  return c;
}

function buildRule(f) {
  var c = makeComp(f, "HUD_Rule", 400, 48, 13, FPS);
  rectLayer(c, "RuleChip", 352, 36, 18, [200, 24], INK, 80, null, 0);
  textLayer(c, "RuleText", "正解数 × 残りHP で勝負！", 16, PALE, [200, 24], null, 0, 20);
  return c;
}

function buildCard(f, index) {
  var color = index === 1 ? P1 : P2;
  var c = makeComp(f, "HUD_CardP" + index, 480, 176, 13, FPS);
  rectLayer(c, "CardBody", 456, 128, 12, [240, 112], INK, 92, color, 2);
  rectLayer(c, "CardAccent", 400, 4, 2, [240, 52], color, 100, null, 0);
  rectLayer(c, "Badge", 56, 32, 16, [60, 104], color, 100, null, 0);
  textLayer(c, "BadgeText", "P" + index, 18, INK, [60, 104], null, 0, 0);
  var capCorrect = textLayer(c, "CaptionCorrect", "正解", 14, MUTED, [150, 78], null, 0, 40);
  var capHp = textLayer(c, "CaptionHp", "残りHP", 14, MUTED, [262, 78], null, 0, 20);
  var capTotal = textLayer(c, "CaptionTotal", "合計", 14, color, [398, 78], null, 0, 40);
  var correct = textLayer(c, "CorrectValue", "8", 40, PALE, [150, 122], null, 0, 0);
  var times = textLayer(c, "TimesOp", "×", 28, color, [206, 122], null, 0, 0);
  var hp = textLayer(c, "HpValue", "3", 40, PALE, [262, 122], null, 0, 0);
  var equals = textLayer(c, "EqualsOp", "=", 28, color, [318, 122], null, 0, 0);
  var total = textLayer(c, "TotalValue", "24", 56, color, [398, 120], null, 0, 0);
  // staged formula: correct -> x HP -> = total (same seconds for both cards)
  var dim = 35;
  keys(capCorrect, "Opacity", [[2.30, dim, 1, 1], [2.50, 100, 60, 1]]);
  keys(capHp, "Opacity", [[3.10, dim, 1, 1], [3.30, 100, 60, 1]]);
  keys(capTotal, "Opacity", [[3.90, dim, 1, 1], [4.10, 100, 60, 1]]);
  var pops = [[correct, 2.50], [times, 3.30], [hp, 3.36], [equals, 4.10], [total, 4.16]];
  for (var i = 0; i < pops.length; i++) {
    var l = pops[i][0], t = pops[i][1];
    keys(l, "Opacity", [[t, 0, 1, 1], [t + 0.06, 100, 60, 1]]);
    keys(l, "Scale", [[t, [40, 40], 1, 60], [t + 0.12, [114, 114], 60, 40], [t + 0.26, [100, 100], 75, 1]]);
  }
  return c;
}

function buildWinTag(f) {
  var c = makeComp(f, "HUD_WinTag", 120, 40, 13, FPS);
  rectLayer(c, "TagPill", 104, 32, 16, [60, 20], GOLD, 100, INK, 3);
  textLayer(c, "TagText", "WIN", 18, INK, [60, 20], null, 0, 120);
  return c;
}

function buildVerdict(f, draw) {
  var c = makeComp(f, draw ? "HUD_VerdictDraw" : "HUD_VerdictWin", 720, 260, 13, FPS);
  if (!draw) {
    rectLayer(c, "PlayerChip", 120, 72, 36, [118, 116], P1, 100, INK, 5);
    textLayer(c, "PlayerChipText", "P1", 44, INK, [118, 116], null, 0, 0);
    textLayer(c, "VerdictWord", "WIN!", 136, GOLD, [410, 118], INK, 12, 20);
    var sub = textLayer(c, "VerdictSub", "おめでとう！", 26, PALE, [410, 222], INK, 6, 60);
  } else {
    textLayer(c, "VerdictWord", "DRAW!", 128, PALE, [360, 118], INK, 12, 20);
    var sub = textLayer(c, "VerdictSub", "いい勝負！", 26, GOLD, [360, 222], INK, 6, 60);
  }
  keys(sub, "Opacity", [[7.22, 0, 1, 1], [7.34, 100, 60, 1]]);
  keys(sub, "Position", [[7.22, [draw ? 360 : 410, 236], 1, 22], [7.62, [draw ? 360 : 410, 222], 75, 1]]);
  return c;
}

function buildActions(f) {
  var c = makeComp(f, "HUD_Actions", 760, 64, 13, FPS);
  var specs = [["BtnRetry", "もう一度", 132, GOLD, INK, null], ["BtnHistory", "履歴", 380, INK, PALE, [0.55, 0.62, 0.75]],
               ["BtnMenu", "メニュー", 628, INK, PALE, [0.55, 0.62, 0.75]]];
  for (var i = 0; i < specs.length; i++) {
    var s = specs[i];
    var box = rectLayer(c, s[0], 232, 48, 24, [s[2], 32], s[3], i === 0 ? 100 : 94, s[5], s[5] ? 2 : 0);
    var label = textLayer(c, s[0] + "Text", s[1], 20, s[4], [s[2], 32], null, 0, 40);
    var t0 = 11.20 + i * 0.06;
    for (var j = 0; j < 2; j++) {
      var l = j === 0 ? box : label;
      var p = tr(l, "Position").value;
      keys(l, "Position", [[t0, [p[0], p[1] + 14], 1, 22], [t0 + 0.5, [p[0], p[1]], 75, 1]]);
      keys(l, "Scale", [[t0, [95, 95], 1, 22], [t0 + 0.5, [100, 100], 75, 1]]);
      keys(l, "Opacity", [[t0 + 0.08, 0, 1, 1], [t0 + 0.2, 100, 60, 1]]);
    }
  }
  return c;
}

// ------------------------------------------------------------------ FX (rendered)

function buildBurst(f) {
  var c = makeComp(f, "FX_Burst", 512, 512, 0.8, 30);
  c.bgColor = [0, 0, 0];
  var centre = [256, 256];
  // radial rays: thin rect shapes rotated around the centre, scaling outward
  for (var i = 0; i < 16; i++) {
    var len = i % 2 === 0 ? 150 : 104;
    var ray = rectLayer(c, "Ray" + (i < 10 ? "0" : "") + i, 10, len, 5, centre, WHITE, 100, null, 0);
    tr(ray, "Anchor Point").setValue([0, len * 0.5 + 40]);
    tr(ray, "Rotation").setValue(i * 22.5);
    keys(ray, "Scale", [[0.0, [60, 20], 1, 80], [0.30, [100, 100], 70, 20], [0.8, [70, 115], 60, 1]]);
    keys(ray, "Opacity", [[0.0, 100, 1, 1], [0.35, 90, 40, 20], [0.75, 0, 60, 1]]);
  }
  var ring = ellipseLayer(c, "ShockRing", 120, centre, null, WHITE, 28);
  keys(ring, "Scale", [[0.0, [30, 30], 1, 85], [0.5, [360, 360], 80, 1]]);
  var ringStroke = ring.property("ADBE Root Vectors Group").property(1).property("ADBE Vectors Group").property("ADBE Vector Graphic - Stroke").property("ADBE Vector Stroke Width");
  ringStroke.setValueAtTime(0.0, 28);
  ringStroke.setValueAtTime(0.5, 2);
  keys(ring, "Opacity", [[0.0, 100, 1, 1], [0.25, 100, 40, 40], [0.5, 0, 60, 1]]);
  var flash = ellipseLayer(c, "CoreFlash", 160, centre, WHITE, null, 0);
  keys(flash, "Scale", [[0.0, [20, 20], 1, 90], [0.12, [120, 120], 70, 30], [0.4, [60, 60], 60, 1]]);
  keys(flash, "Opacity", [[0.0, 100, 1, 1], [0.12, 100, 40, 40], [0.4, 0, 60, 1]]);
  // sparkles: small diamonds flying outward
  for (var s = 0; s < 10; s++) {
    var ang = (s * 36 + 18) * Math.PI / 180;
    var sp = rectLayer(c, "Spark" + s, 16, 16, 0, centre, WHITE, 100, null, 0);
    tr(sp, "Rotation").setValue(45);
    var dist = s % 2 === 0 ? 220 : 170;
    keys(sp, "Position", [[0.04, centre, 1, 85], [0.6, [256 + Math.cos(ang) * dist, 256 + Math.sin(ang) * dist], 80, 1]]);
    keys(sp, "Scale", [[0.04, [20, 20], 1, 60], [0.2, [110, 110], 60, 30], [0.7, [0, 0], 60, 1]]);
  }
  for (var k = 1; k <= c.numLayers; k++) glow(c.layer(k), 18, 0.8);
  return c;
}

function buildLockRing(f) {
  var c = makeComp(f, "FX_LockRing", 256, 256, 0.5, 30);
  c.bgColor = [0, 0, 0];
  var centre = [128, 128];
  var ring = ellipseLayer(c, "LockRing", 80, centre, null, WHITE, 14);
  keys(ring, "Scale", [[0.0, [50, 50], 1, 85], [0.4, [260, 260], 80, 1]]);
  keys(ring, "Opacity", [[0.0, 100, 1, 1], [0.15, 100, 40, 40], [0.4, 0, 60, 1]]);
  for (var i = 0; i < 8; i++) {
    var len = 34;
    var dash = rectLayer(c, "Dash" + i, 6, len, 3, centre, WHITE, 100, null, 0);
    tr(dash, "Anchor Point").setValue([0, 52]);
    tr(dash, "Rotation").setValue(i * 45 + 22.5);
    keys(dash, "Scale", [[0.0, [100, 10], 1, 80], [0.18, [100, 100], 70, 20], [0.45, [60, 10], 60, 1]]);
    keys(dash, "Anchor Point", [[0.0, [0, 40], 1, 80], [0.45, [0, 96], 70, 1]]);
  }
  for (var k = 1; k <= c.numLayers; k++) glow(c.layer(k), 10, 0.7);
  return c;
}

// ------------------------------------------------------------------ masters

function buildMaster(f, draw, pre) {
  var m = makeComp(f, draw ? "FINALE_HUD_Draw" : "FINALE_HUD_Win", 1280, 720, 13, FPS);
  m.bgColor = [0.30, 0.42, 0.56];
  // Added bottom -> top: the verdict smash sits above everything, its burst just behind it.
  var actions = addPre(m, pre.actions, [640, 664], "Actions");
  var card2 = addPre(m, pre.card2, [1004, 600], "CardP2");
  var card1 = addPre(m, pre.card1, [276, 600], "CardP1");
  var winTag = draw ? null : addPre(m, pre.winTag, [240, 30], "WinTag");
  var rule = addPre(m, pre.rule, [640, 120], "Rule");
  var title = addPre(m, pre.title, [640, 60], "Title");
  // The smash lands high so it never covers the winner's face in the Blender shot.
  var burst = addPre(m, pre.burst, draw ? [640, 196] : [690, 196], "BurstPreview");
  burst.startTime = 6.90;
  burst.blendingMode = BlendingMode.ADD;
  var verdict = addPre(m, draw ? pre.verdictDraw : pre.verdictWin, [640, 196], "Verdict");

  // Title and rule: lift in, leave upward at the hush.
  keys(title, "Position", [[2.05, [640, 30], 1, 22], [2.75, [640, 60], 75, 1], [6.24, [640, 60], 1, 60], [6.54, [640, 28], 60, 1]]);
  keys(title, "Scale", [[2.05, [95, 95], 1, 22], [2.75, [100, 100], 75, 1]]);
  keys(title, "Opacity", [[2.26, 0, 1, 1], [2.38, 100, 60, 1], [6.30, 100, 1, 1], [6.50, 0, 60, 1]]);
  keys(rule, "Position", [[2.20, [640, 146], 1, 22], [2.90, [640, 120], 75, 1], [6.20, [640, 120], 1, 60], [6.50, [640, 96], 60, 1]]);
  keys(rule, "Opacity", [[2.41, 0, 1, 1], [2.53, 100, 60, 1], [6.24, 100, 1, 1], [6.44, 0, 60, 1]]);

  // Cards slide in from their own sides.
  keys(card1, "Position", [[2.10, [-250, 600], 1, 80], [2.62, [276, 600], 75, 1]]);
  keys(card2, "Position", [[2.16, [1530, 600], 1, 80], [2.68, [1004, 600], 75, 1]]);
  keys(card1, "Opacity", [[2.10, 0, 1, 1], [2.20, 100, 60, 1]]);
  keys(card2, "Opacity", [[2.16, 0, 1, 1], [2.26, 100, 60, 1]]);

  // Verdict smash: overshoot on scale only, then park.
  var vp = draw ? [640, 94] : [1052, 94];
  var vs = draw ? 58 : 54;
  keys(verdict, "Opacity", [[6.90, 0, 1, 1], [6.95, 100, 60, 1]]);
  keys(verdict, "Scale", [[6.90, [170, 170], 1, 90], [7.06, [92, 92], 70, 40], [7.16, [104, 104], 60, 40], [7.28, [100, 100], 75, 1],
                          [7.50, [100, 100], 1, 60], [8.06, [vs, vs], 75, 1]]);
  keys(verdict, "Rotation", [[6.90, -10, 1, 90], [7.16, 2, 60, 40], [7.28, 0, 75, 1]]);
  keys(verdict, "Position", [[7.50, [640, 196], 1, 60], [8.06, vp, 75, 1]]);
  keys(burst, "Opacity", [[6.90, 100, 1, 1]]);

  if (!draw) {
    // Winner card pulses and wins a tag; loser card dims. Both park beside the title.
    keys(card1, "Scale", [[6.90, [100, 100], 1, 60], [7.02, [107, 107], 60, 40], [7.18, [100, 100], 75, 1],
                          [7.56, [100, 100], 1, 60], [8.16, [60, 60], 75, 1]]);
    keys(card2, "Scale", [[7.60, [100, 100], 1, 60], [8.20, [60, 60], 75, 1]]);
    keys(card2, "Opacity", [[6.92, 100, 1, 1], [7.20, 55, 60, 1]]);
    keys(card1, "Position", [[7.56, [276, 600], 1, 60], [8.16, [1100, 206], 75, 1]]);
    keys(card2, "Position", [[7.60, [1004, 600], 1, 60], [8.20, [1100, 282], 75, 1]]);
    winTag.parent = card1;
    tr(winTag, "Position").setValue([400, 30]);
    keys(winTag, "Opacity", [[7.00, 0, 1, 1], [7.06, 100, 60, 1]]);
    keys(winTag, "Scale", [[7.00, [30, 30], 1, 70], [7.14, [115, 115], 60, 40], [7.26, [100, 100], 75, 1]]);
  } else {
    keys(card1, "Scale", [[7.56, [100, 100], 1, 60], [8.16, [60, 60], 75, 1]]);
    keys(card2, "Scale", [[7.56, [100, 100], 1, 60], [8.16, [60, 60], 75, 1]]);
    keys(card1, "Position", [[7.56, [276, 600], 1, 60], [8.16, [180, 206], 75, 1]]);
    keys(card2, "Position", [[7.56, [1004, 600], 1, 60], [8.16, [1100, 206], 75, 1]]);
  }
  return m;
}

var f = folder();
removeOwned(f);
var pre = {};
pre.title = buildTitle(f);
pre.rule = buildRule(f);
pre.card1 = buildCard(f, 1);
pre.card2 = buildCard(f, 2);
pre.winTag = buildWinTag(f);
pre.verdictWin = buildVerdict(f, false);
pre.verdictDraw = buildVerdict(f, true);
pre.actions = buildActions(f);
pre.burst = buildBurst(f);
pre.lock = buildLockRing(f);
var win = buildMaster(f, false, pre);
var draw = buildMaster(f, true, pre);
return { items: f.numItems, win: win.numLayers, draw: draw.numLayers };
