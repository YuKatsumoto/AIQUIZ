// Sample the menu LED programme for Godot (ExtendScript ES3, run via ae_run.mjs).
// Writes res://assets/aiquiz_menu_stage/led/led_motion.json:
//   every comp Godot plays (layers bottom -> top: rectangles, ellipses and straight
//   stroked paths, text, images, precomps, nulls, parents, in/out points, precomp start
//   offsets) and 60 fps samples of every animated transform and Trim Paths Start / End,
//   trimmed to its first..last key (whole comp when an expression drives it).
// After Effects stays the source of truth: edit keys/layout in the AEP, re-run this.

var FOLDER = "AIQUIZ_MenuLED";
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/aiquiz_menu_stage/led/led_motion.json";
var FPS = 60;
var NAMES = ["BG_Ambient", "WIPE_Strokes", "CUT_Strokes", "CLIP_Media", "REPLAY_Frame", "REPLAY_Caption",
             "LED_Sting", "LED_Versus", "LED_Solo", "LED_History", "LED_Stats", "LED_Logo", "LED_LogoLoop",
             "LED_Empty", "LOGO_StripesL", "LOGO_StripesR", "LOOP_StripesL", "LOOP_StripesR"];

function r(v, n) { var m = Math.pow(10, n); return Math.round(v * m) / m; }
function arr(v, n) {
  if (v instanceof Array) { var o = []; for (var i = 0; i < v.length; i++) o.push(r(v[i], n)); return o; }
  return r(v, n);
}

function findComp(name) {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === name && it.parentFolder.name === FOLDER) return it;
  }
  return null;
}

function tprop(layer, key) {
  var map = { position: "ADBE Position", scale: "ADBE Scale", rotation: "ADBE Rotate Z",
              opacity: "ADBE Opacity", anchor: "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[key]);
}

function flat2(v) { return (v instanceof Array && v.length > 2) ? [v[0], v[1]] : v; }

function sampleProp(prop, comp, digits) {
  var driven = prop.expressionEnabled && prop.expression !== "";
  if (prop.numKeys < 1 && !driven) return null;
  var first = driven ? 0 : Math.max(0, Math.floor(prop.keyTime(1) * FPS));
  var end = Math.round(comp.duration * FPS);
  var last = driven ? end : Math.min(end, Math.ceil(prop.keyTime(prop.numKeys) * FPS));
  var values = [];
  for (var f = first; f <= last; f++) values.push(arr(flat2(prop.valueAtTime(f / FPS, false)), digits));
  return { start: first, values: values };
}

function shapeInfo(layer, comp) {
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
    } else if (p.matchName === "ADBE Vector Shape - Group") {
      info.kind = "line";
      var verts = p.property("ADBE Vector Shape").value.vertices;
      info.points = [arr(verts[0], 2), arr(verts[verts.length - 1], 2)];
    } else if (p.matchName === "ADBE Vector Graphic - Stroke") {
      info.stroke = arr(p.property("ADBE Vector Stroke Color").value.slice(0, 3), 4);
      info.strokeWidth = r(p.property("ADBE Vector Stroke Width").value, 2);
      info.cap = p.property("ADBE Vector Stroke Line Cap").value === 2 ? "round" : "butt";
    } else if (p.matchName === "ADBE Vector Filter - Trim") {
      var start = p.property("ADBE Vector Trim Start"), end = p.property("ADBE Vector Trim End");
      info.trim = { start: r(start.valueAtTime(0, false), 2), end: r(end.valueAtTime(0, false), 2),
                    offset: r(p.property("ADBE Vector Trim Offset").value, 2) };
      var endTrack = sampleProp(end, comp, 2);
      if (endTrack) info.trim.track = endTrack;
      var startTrack = sampleProp(start, comp, 2);
      if (startTrack) info.trim.startTrack = startTrack;
    }
  }
  return info;
}

function textInfo(layer) {
  var d = layer.property("ADBE Text Properties").property("ADBE Text Document").value;
  var just = "center";
  if (d.justification === ParagraphJustification.LEFT_JUSTIFY) just = "left";
  if (d.justification === ParagraphJustification.RIGHT_JUSTIFY) just = "right";
  var t = { string: d.text, font: d.font, size: r(d.fontSize, 2), fill: arr(d.fillColor, 4),
            justification: just, tracking: r(d.tracking, 1) };
  if (d.applyStroke) { t.stroke = arr(d.strokeColor, 4); t.strokeWidth = r(d.strokeWidth, 2); }
  return t;
}

function layerRecord(layer, comp) {
  var rec = { name: layer.name, index: layer.index, enabled: layer.enabled,
              parent: layer.parent ? layer.parent.name : null,
              start: r(layer.startTime, 3), inPoint: r(layer.inPoint, 3), outPoint: r(layer.outPoint, 3) };
  if (layer instanceof TextLayer) { rec.type = "text"; rec.text = textInfo(layer); }
  else if (layer instanceof ShapeLayer) { rec.type = "shape"; rec.shape = shapeInfo(layer, comp); }
  else if (layer.nullLayer) rec.type = "null";
  else if (layer.source && layer.source instanceof CompItem) { rec.type = "precomp"; rec.source = layer.source.name; }
  else if (layer.source && layer.source.mainSource && layer.source.mainSource.file) {
    rec.type = "image";
    rec.image = { file: layer.source.mainSource.file.name, size: [layer.source.width, layer.source.height] };
  } else rec.type = "other";
  var keys = ["position", "scale", "rotation", "opacity", "anchor"];
  var digits = { position: 2, scale: 2, rotation: 2, opacity: 1, anchor: 2 };
  rec.base = {};
  rec.tracks = {};
  for (var i = 0; i < keys.length; i++) {
    var p = tprop(layer, keys[i]);
    rec.base[keys[i]] = arr(flat2(p.valueAtTime(0, false)), digits[keys[i]]);
    var s = sampleProp(p, comp, digits[keys[i]]);
    if (s) rec.tracks[keys[i]] = s;
  }
  return rec;
}

function compRecord(comp) {
  var layers = [];
  for (var i = comp.numLayers; i >= 1; i--) layers.push(layerRecord(comp.layer(i), comp));
  return { size: [comp.width, comp.height], duration: r(comp.duration, 3), fps: comp.frameRate, layers: layers };
}

var comps = {};
var missing = [];
for (var n = 0; n < NAMES.length; n++) {
  var c = findComp(NAMES[n]);
  if (c) comps[NAMES[n]] = compRecord(c); else missing.push(NAMES[n]);
}
var data = { version: 1, source: "After Effects " + app.version + " / " + FOLDER + " (source/ae/build_led.jsx)",
             fps: FPS, canvas: [1296, 588], comps: comps };
var file = new File(OUT);
file.encoding = "UTF-8";
file.open("w");
file.write(JSON.stringify(data));
file.close();
return { bytes: file.length, comps: NAMES.length - missing.length, missing: missing };
