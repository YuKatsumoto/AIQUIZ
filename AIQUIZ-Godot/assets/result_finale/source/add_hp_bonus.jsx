// Score Tower Finale — survival bonus "+0.5" on the HP value (After Effects 2026,
// ExtendScript ES3, run via ae_run.mjs). Incremental and idempotent: it edits the
// existing HUD_CardP1/HUD_CardP2 precomps in place (build_hud.jsx would rebuild every
// comp and drop hand tuning), then saves the project. Re-run sample_hud.jsx afterwards.
//
// Card-local seconds (same clock as the ceremony):
//   3.36  HP value pops (build_hud.jsx)
//   3.50  gold "+0.5" chip rises in under the HP value
//   3.80  chip flies up into the HP value and fades (last key 3.92 = merge)
//   3.92  HP value re-pops (Godot switches "2" -> "2.5" here) and a gold ring expands
// Godot hides the three bonus layers on an eliminated player's card.

var FONT = "NotoSansJP-Bold";
var INK = [0.043, 0.071, 0.125];
var GOLD = [1.0, 0.824, 0.29];
var HP = [262, 122];
var CHIP_REST = [262, 154];
var OWNED = ["HpBonusRing", "HpBonusText", "HpBonusChip"];
var MERGE = 3.92;

function findComp(name) {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === name) return it;
  }
  return null;
}

function tr(layer, name) {
  var map = { "Position": "ADBE Position", "Scale": "ADBE Scale", "Opacity": "ADBE Opacity", "Anchor Point": "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[name]);
}

function arity(prop) {
  try {
    if (prop.propertyValueType === PropertyValueType.TwoD || prop.propertyValueType === PropertyValueType.ThreeD) return prop.value.length;
  } catch (e) {}
  return 1;
}

// keys: [[t, value, inInfluence, outInfluence], ...] (same easing convention as build_hud.jsx)
function keys(layer, propName, list) {
  var prop = tr(layer, propName);
  for (var i = 0; i < list.length; i++) prop.setValueAtTime(list[i][0], list[i][1]);
  var n = arity(prop);
  for (var k = 0; k < list.length; k++) {
    var idx = prop.nearestKeyIndex(list[k][0]);
    prop.setInterpolationTypeAtKey(idx, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
    var inf = list[k][2] == null ? 75 : list[k][2];
    var outf = list[k][3] == null ? 22 : list[k][3];
    var a = [], b = [];
    for (var d = 0; d < n; d++) { a.push(new KeyframeEase(0, inf)); b.push(new KeyframeEase(0, outf)); }
    try { prop.setTemporalEaseAtKey(idx, a, b); } catch (e) {}
  }
  return prop;
}

function shapeLayer(comp, name, kind, size, radius, pos, fill, stroke, strokeWidth) {
  var l = comp.layers.addShape();
  l.name = name;
  var g = l.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
  g.name = kind === "rect" ? "Box" : "Ring";
  var v = g.property("ADBE Vectors Group");
  if (kind === "rect") {
    var r = v.addProperty("ADBE Vector Shape - Rect");
    r.property("ADBE Vector Rect Size").setValue(size);
    r.property("ADBE Vector Rect Roundness").setValue(radius);
  } else {
    v.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue(size);
  }
  if (stroke) {
    var s = v.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue(stroke);
    s.property("ADBE Vector Stroke Width").setValue(strokeWidth);
  }
  if (fill) {
    var f = v.addProperty("ADBE Vector Graphic - Fill");
    f.property("ADBE Vector Fill Color").setValue(fill);
    f.property("ADBE Vector Fill Opacity").setValue(100);
  }
  tr(l, "Position").setValue(pos);
  return l;
}

function textLayer(comp, name, str, size, color, pos) {
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
  d.applyStroke = false;
  d.justification = ParagraphJustification.CENTER_JUSTIFY;
  d.tracking = 0;
  p.setValue(d);
  tr(l, "Anchor Point").setValue([0, -size * 0.36]);
  tr(l, "Position").setValue(pos);
  return l;
}

function removeNamed(comp, names) {
  for (var i = comp.numLayers; i >= 1; i--) {
    for (var n = 0; n < names.length; n++) {
      if (comp.layer(i).name === names[n]) { comp.layer(i).remove(); break; }
    }
  }
}

function layerNamed(comp, name) {
  for (var i = 1; i <= comp.numLayers; i++) if (comp.layer(i).name === name) return comp.layer(i);
  return null;
}

function addHpBonus(card) {
  removeNamed(card, OWNED);
  var hp = layerNamed(card, "HpValue");
  // Drop an earlier re-pop so the script can run again.
  var hpScale = tr(hp, "Scale");
  for (var k = hpScale.numKeys; k >= 1; k--) if (hpScale.keyTime(k) > 3.7) hpScale.removeKey(k);
  keys(hp, "Scale", [[MERGE, [100, 100], 1, 60], [MERGE + 0.08, [120, 120], 60, 40], [MERGE + 0.22, [100, 100], 75, 1]]);

  // Added bottom -> top above the card art: ring, chip, label.
  var ring = shapeLayer(card, "HpBonusRing", "ellipse", [44, 44], 0, HP, null, GOLD, 4);
  var chip = shapeLayer(card, "HpBonusChip", "rect", [68, 30], 15, CHIP_REST, GOLD, INK, 2);
  var label = textLayer(card, "HpBonusText", "+0.5", 22, INK, CHIP_REST);
  var start = [CHIP_REST[0], CHIP_REST[1] + 12];
  var pieces = [chip, label];
  for (var i = 0; i < pieces.length; i++) {
    var l = pieces[i];
    keys(l, "Opacity", [[3.50, 0, 1, 1], [3.56, 100, 60, 1], [3.84, 100, 1, 60], [MERGE, 0, 60, 1]]);
    keys(l, "Position", [[3.50, start, 1, 80], [3.70, CHIP_REST, 75, 1], [3.80, CHIP_REST, 1, 70], [MERGE, [HP[0], HP[1] + 2], 80, 1]]);
    keys(l, "Scale", [[3.50, [40, 40], 1, 60], [3.62, [112, 112], 60, 40], [3.74, [100, 100], 75, 1],
                      [3.80, [100, 100], 1, 60], [MERGE, [55, 55], 60, 1]]);
  }
  keys(ring, "Opacity", [[MERGE - 0.02, 0, 1, 1], [MERGE, 100, 60, 1], [MERGE + 0.32, 0, 40, 1]]);
  keys(ring, "Scale", [[MERGE - 0.02, [60, 60], 1, 85], [MERGE + 0.32, [320, 320], 80, 1]]);
  // Park the ring layer under the value so the number stays readable.
  ring.moveAfter(hp);
  return card.numLayers;
}

app.beginUndoGroup("AIQUIZ HP survival bonus");
var report = { strayRemoved: 0, cards: {} };
// A full HUD_CardP2 precomp had been dropped into the rule chip; it is not part of the design.
var rule = findComp("HUD_Rule");
if (rule) {
  for (var i = rule.numLayers; i >= 1; i--) {
    var l = rule.layer(i);
    if (l.source && l.source instanceof CompItem && l.source.name.indexOf("HUD_Card") === 0) { l.remove(); report.strayRemoved++; }
  }
}
var names = ["HUD_CardP1", "HUD_CardP2"];
for (var n = 0; n < names.length; n++) {
  var card = findComp(names[n]);
  if (card) report.cards[names[n]] = addHpBonus(card);
}
app.endUndoGroup();
app.project.save();
return report;
