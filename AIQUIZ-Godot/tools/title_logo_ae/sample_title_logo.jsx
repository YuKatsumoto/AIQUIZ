// Sample the title intro for Godot (ExtendScript ES3, run via ae_run.mjs after build_title_logo.jsx).
// Writes res://assets/ui/title_logo/title_logo_motion.json for TitleLogoIntro:
//   controls  CTRL sliders (Form, Travel, Reveal): value at 0 s and 60 fps samples between the first and last key
//   layers    every layer except BG_Preview / BELT: parent, in/out points, anchor, position (X/Y separated or not),
//             scale, rotation, opacity (base value + 60 fps samples between first and last key);
//             DUST_<n> / FX_<name> also carry their shape (ellipse or rounded rect: size, fill, stroke)
// After Effects stays the source of truth: change keys in the AEP, run this again (no Godot code change).

var COMP = "TitleLogo_Intro";
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/ui/title_logo/title_logo_motion.json";
var FPS = 60, K = 4, OX = -30, OY = -140;  // same as build_title_logo.jsx
var SKIP = { "BG_Preview": true, "BELT": true };

function r(v, n) { var m = Math.pow(10, n); return Math.round(v * m) / m; }
function arr(v, n) {
  if (v instanceof Array) { var o = []; for (var i = 0; i < Math.min(v.length, 2); i++) o.push(r(v[i], n)); return o; }
  return r(v, n);
}
function findComp(name) {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === name) return it;
  }
  return null;
}
function range(props, comp) {
  var first = Infinity, last = -Infinity;
  for (var i = 0; i < props.length; i++) {
    var p = props[i];
    if (p.expressionEnabled && p.expression !== "") return [0, Math.round(comp.duration * FPS)];
    if (p.numKeys > 0) {
      first = Math.min(first, Math.floor(p.keyTime(1) * FPS));
      last = Math.max(last, Math.ceil(p.keyTime(p.numKeys) * FPS));
    }
  }
  if (first === Infinity) return null;
  return [Math.max(0, first), Math.min(Math.round(comp.duration * FPS), last)];
}
// value(t) of a transform key, combining separated X/Y position
function track(layer, keyName, comp, digits) {
  var t = layer.property("ADBE Transform Group");
  var props, get;
  if (keyName === "position" && t.property("ADBE Position").dimensionsSeparated) {
    var px = t.property("ADBE Position_0"), py = t.property("ADBE Position_1");
    props = [px, py];
    get = function (time) { return [px.valueAtTime(time, false), py.valueAtTime(time, false)]; };
  } else {
    var map = { position: "ADBE Position", scale: "ADBE Scale", rotation: "ADBE Rotate Z",
                opacity: "ADBE Opacity", anchor: "ADBE Anchor Point" };
    var p = t.property(map[keyName]);
    props = [p];
    get = function (time) { return p.valueAtTime(time, false); };
  }
  var out = { base: arr(get(0), digits) };
  var span = range(props, comp);
  if (span) {
    var values = [];
    for (var f = span[0]; f <= span[1]; f++) values.push(arr(get(f / FPS), digits));
    out.track = { start: span[0], values: values };
  }
  return out;
}

var comp = findComp(COMP);
if (!comp) throw new Error(COMP + " not found (run build_title_logo.jsx first)");
var controls = {};
var fx = comp.layer("CTRL").property("ADBE Effect Parade");
for (var e = 1; e <= fx.numProperties; e++) {
  var sp = fx.property(e).property(1);
  var rec = { value: r(sp.valueAtTime(0, false), 4) };
  var span = range([sp], comp);
  if (span) {
    var vals = [];
    for (var f = span[0]; f <= span[1]; f++) vals.push(r(sp.valueAtTime(f / FPS, false), 4));
    rec.track = { start: span[0], values: vals };
  }
  controls[fx.property(e).name] = rec;
}
var layers = {};
var digits = { position: 2, scale: 2, rotation: 2, opacity: 1, anchor: 2 };
for (var i = 1; i <= comp.numLayers; i++) {
  var layer = comp.layer(i);
  if (SKIP[layer.name] || layer.name === "CTRL") continue;
  var rec2 = { parent: layer.parent ? layer.parent.name : null, inPoint: r(layer.inPoint, 4), outPoint: r(layer.outPoint, 4),
               base: {}, tracks: {} };
  var keys = ["position", "scale", "rotation", "opacity", "anchor"];
  for (var k = 0; k < keys.length; k++) {
    var tr = track(layer, keys[k], comp, digits[keys[k]]);
    rec2.base[keys[k]] = tr.base;
    if (tr.track) rec2.tracks[keys[k]] = tr.track;
  }
  if (layer.name.indexOf("DUST_") === 0 || layer.name.indexOf("FX_") === 0) {
    var g = layer.property("ADBE Root Vectors Group").property(1).property("ADBE Vectors Group");
    var shape = {};
    for (var q = 1; q <= g.numProperties; q++) {
      var pr = g.property(q);
      if (pr.matchName === "ADBE Vector Shape - Ellipse") {
        shape.kind = "ellipse";
        shape.size = arr(pr.property("ADBE Vector Ellipse Size").value, 2);
      } else if (pr.matchName === "ADBE Vector Shape - Rect") {
        shape.kind = "rect";
        shape.size = arr(pr.property("ADBE Vector Rect Size").value, 2);
        shape.radius = r(pr.property("ADBE Vector Rect Roundness").value, 2);
      } else if (pr.matchName === "ADBE Vector Graphic - Fill") {
        var fc = pr.property("ADBE Vector Fill Color").value;
        shape.fill = [r(fc[0], 4), r(fc[1], 4), r(fc[2], 4)];
        shape.fillOpacity = r(pr.property("ADBE Vector Fill Opacity").value, 1);
      } else if (pr.matchName === "ADBE Vector Graphic - Stroke") {
        var sc = pr.property("ADBE Vector Stroke Color").value;
        shape.stroke = [r(sc[0], 4), r(sc[1], 4), r(sc[2], 4)];
        shape.strokeWidth = r(pr.property("ADBE Vector Stroke Width").value, 2);
      }
    }
    rec2.shape = shape;
  }
  layers[layer.name] = rec2;
}
var data = { version: 1, source: "After Effects " + app.version + " / tools/title_logo_ae/AIQUIZ_TitleLogo.aep (" + COMP + ")",
             fps: FPS, scale: K, origin: [OX, OY], size: [comp.width, comp.height], duration: r(comp.duration, 4),
             controls: controls, layers: layers };
var dir = new Folder("C:/AIQUIZ/AIQUIZ-Godot/assets/ui/title_logo");
if (!dir.exists) dir.create();
var file = new File(OUT);
file.encoding = "UTF-8";
file.open("w");
file.write(JSON.stringify(data));
file.close();
var names = [];
for (var n in layers) names.push(n);
return { bytes: file.length, duration: data.duration, controls: controls ? (function () { var o = []; for (var c in controls) o.push(c); return o; })() : [], layers: names.length };
