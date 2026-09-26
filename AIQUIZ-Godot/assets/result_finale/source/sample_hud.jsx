// Sample the Score Tower Finale HUD for Godot (ExtendScript ES3, run via ae_run.mjs).
// Writes res://assets/result_finale/hud_motion.json:
//   layouts of every HUD_* precomp (shape/text/precomp layers, colours, text metrics)
//   and 60 fps samples of every animated transform, trimmed to its first..last key.
// After Effects stays the source of truth: edit keys/layout in the AEP, re-run this.

var FOLDER = "AIQUIZ_ScoreTowerFinale";
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/result_finale/hud_motion.json";
var FPS = 60;

function r(v, n) { var m = Math.pow(10, n); return Math.round(v * m) / m; }
function arr(v, n) {
  if (v instanceof Array) { var o = []; for (var i = 0; i < v.length; i++) o.push(r(v[i], n)); return o; }
  return r(v, n);
}

function findItem(name) {
  for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === name) return app.project.item(i);
  return null;
}

function tprop(layer, key) {
  var map = { position: "ADBE Position", scale: "ADBE Scale", rotation: "ADBE Rotate Z",
              opacity: "ADBE Opacity", anchor: "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[key]);
}

function shapeInfo(layer) {
  var root = layer.property("ADBE Root Vectors Group");
  if (!root || root.numProperties < 1) return null;
  var group = root.property(1).property("ADBE Vectors Group");
  var info = {};
  for (var i = 1; i <= group.numProperties; i++) {
    var p = group.property(i);
    if (p.matchName === "ADBE Vector Shape - Rect") {
      info.kind = "rect";
      info.size = arr(p.property("ADBE Vector Rect Size").value, 2);
      info.radius = r(p.property("ADBE Vector Rect Roundness").value, 2);
    } else if (p.matchName === "ADBE Vector Shape - Ellipse") {
      info.kind = "ellipse";
      info.size = arr(p.property("ADBE Vector Ellipse Size").value, 2);
    } else if (p.matchName === "ADBE Vector Graphic - Fill") {
      info.fill = arr(p.property("ADBE Vector Fill Color").value.slice(0, 3), 4);
      info.fillOpacity = r(p.property("ADBE Vector Fill Opacity").value, 2);
    } else if (p.matchName === "ADBE Vector Graphic - Stroke") {
      info.stroke = arr(p.property("ADBE Vector Stroke Color").value.slice(0, 3), 4);
      info.strokeWidth = r(p.property("ADBE Vector Stroke Width").value, 2);
    }
  }
  return info;
}

function textInfo(layer, comp) {
  var d = layer.property("ADBE Text Properties").property("ADBE Text Document").value;
  var just = "center";
  if (d.justification === ParagraphJustification.LEFT_JUSTIFY) just = "left";
  if (d.justification === ParagraphJustification.RIGHT_JUSTIFY) just = "right";
  var b = layer.sourceRectAtTime(comp.duration - comp.frameDuration, false);
  var t = { string: d.text, font: d.font, size: r(d.fontSize, 2), fill: arr(d.fillColor, 4),
            justification: just, tracking: r(d.tracking, 1), bounds: [r(b.left, 2), r(b.top, 2), r(b.width, 2), r(b.height, 2)] };
  if (d.applyStroke) { t.stroke = arr(d.strokeColor, 4); t.strokeWidth = r(d.strokeWidth, 2); }
  return t;
}

function sampleProp(prop, comp, digits) {
  if (prop.numKeys < 1) return null;
  var first = Math.max(0, Math.floor(prop.keyTime(1) * FPS));
  var last = Math.min(Math.round(comp.duration * FPS), Math.ceil(prop.keyTime(prop.numKeys) * FPS));
  var values = [];
  for (var f = first; f <= last; f++) {
    var v = prop.valueAtTime(f / FPS, false);
    if (v instanceof Array && v.length > 2) v = [v[0], v[1]];
    values.push(arr(v, digits));
  }
  return { start: first, values: values };
}

function layerRecord(layer, comp) {
  var rec = { name: layer.name, index: layer.index, enabled: layer.enabled,
              parent: layer.parent ? layer.parent.name : null,
              start: r(layer.startTime, 3), inPoint: r(layer.inPoint, 3), outPoint: r(layer.outPoint, 3),
              blend: layer.blendingMode === BlendingMode.ADD ? "add" : "normal" };
  if (layer instanceof TextLayer) { rec.type = "text"; rec.text = textInfo(layer, comp); }
  else if (layer instanceof ShapeLayer) { rec.type = "shape"; rec.shape = shapeInfo(layer); }
  else if (layer.source && layer.source instanceof CompItem) { rec.type = "precomp"; rec.source = layer.source.name; }
  else rec.type = "other";
  var keys = ["position", "scale", "rotation", "opacity", "anchor"];
  var digits = { position: 2, scale: 2, rotation: 2, opacity: 1, anchor: 2 };
  rec.base = {};
  rec.tracks = {};
  for (var i = 0; i < keys.length; i++) {
    var p = tprop(layer, keys[i]);
    var v = p.valueAtTime(0, false);
    if (v instanceof Array && v.length > 2) v = [v[0], v[1]];
    rec.base[keys[i]] = arr(v, digits[keys[i]]);
    var s = sampleProp(p, comp, digits[keys[i]]);
    if (s) rec.tracks[keys[i]] = s;
  }
  return rec;
}

function compRecord(comp) {
  var layers = [];
  for (var i = comp.numLayers; i >= 1; i--) layers.push(layerRecord(comp.layer(i), comp)); // bottom -> top
  return { size: [comp.width, comp.height], duration: r(comp.duration, 3), fps: comp.frameRate, layers: layers };
}

var comps = {};
var names = ["HUD_Title", "HUD_Rule", "HUD_CardP1", "HUD_CardP2", "HUD_WinTag", "HUD_VerdictWin", "HUD_VerdictDraw",
             "HUD_Actions", "FINALE_HUD_Win", "FINALE_HUD_Draw"];
for (var n = 0; n < names.length; n++) {
  var c = findItem(names[n]);
  if (c) comps[names[n]] = compRecord(c);
}
var data = { version: 1, source: "After Effects " + app.version + " / " + FOLDER + " (source/build_hud.jsx)",
             fps: FPS, canvas: [1280, 720], comps: comps };
var json = (typeof JSON !== "undefined" && JSON.stringify) ? JSON.stringify(data) : data.toSource();
var file = new File(OUT);
file.encoding = "UTF-8";
file.open("w");
file.write(json);
file.close();
return { bytes: file.length, comps: names.length };
