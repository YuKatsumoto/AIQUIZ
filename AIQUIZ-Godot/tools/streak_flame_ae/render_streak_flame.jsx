// AIQUIZ streak flame -- render + sample (ExtendScript ES3, ASCII only).
// Run with AIQUIZ_Streak_Flame.aep open (build_streak_flame.jsx leaves it open):
//   node tools/title_logo_ae/ae_run.mjs tools/streak_flame_ae/render_streak_flame.jsx
// Output
//   artifacts/streak_flame/frames/flame_00.tif .. flame_29.tif  Streak_Flame_Loop, RGBA (TIFF with alpha)
//   artifacts/streak_flame/ae_badge_preview.mp4                 Streak_Badge_Events (H.264)
//   assets/ui/streak_flame/motion.json                          event curves sampled at 60 Hz
// pack_streak_flame.py then turns the frames into assets/ui/streak_flame/flame_sheet.png.

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var FRAMES = ROOT + "artifacts/streak_flame/frames/";
var PREVIEW = ROOT + "artifacts/streak_flame/ae_badge_preview.mp4";
var MOTION = ROOT + "assets/ui/streak_flame/motion.json";
var FS = 15.6; // flame scale (percent) at rest inside Streak_Badge_Events

function find(name) {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === name) return it;
  }
  throw new Error(name + " not found (open AIQUIZ_Streak_Flame.aep)");
}
function pick(list, tests) {
  for (var t = 0; t < tests.length; t++) for (var i = 0; i < list.length; i++) if (tests[t](list[i])) return list[i];
  return null;
}
function ensureFolder(path) { var f = new Folder(path); if (!f.exists) f.create(); }

var loop = find("Streak_Flame_Loop");
var ev = find("Streak_Badge_Events");
for (var li = 1; li <= ev.numLayers; li++) ev.layer(li).selected = false;
for (var lj = 1; lj <= loop.numLayers; lj++) loop.layer(lj).selected = false;

// ---------- motion.json ----------
function tr(layer) { return layer.property("ADBE Transform Group"); }
function sample(prop, t0, dur, dim, div) {
  var out = [];
  var n = Math.round(dur * 60);
  for (var i = 0; i <= n; i++) {
    var v = prop.valueAtTime(t0 + i / 60, false);
    if (dim >= 0) v = v[dim];
    out.push(Math.round(v / div * 100000) / 100000);
  }
  return { duration: dur, values: out };
}
var flame = ev.layer("Flame"), count = ev.layer("Count"), ring = ev.layer("Ignite Ring");
var tracks = {
  ignite_scale: sample(tr(flame).property("ADBE Scale"), 0.30, 0.48, 0, FS),
  ignite_alpha: sample(tr(flame).property("ADBE Opacity"), 0.30, 0.48, -1, 100),
  ring_scale: sample(tr(ring).property("ADBE Scale"), 0.30, 0.45, 0, 100),
  ring_alpha: sample(tr(ring).property("ADBE Opacity"), 0.30, 0.45, -1, 100),
  count_in_scale: sample(tr(count).property("ADBE Scale"), 0.30, 0.42, 0, 100),
  pop_scale: sample(tr(flame).property("ADBE Scale"), 1.40, 0.34, 0, FS),
  count_pop_scale: sample(tr(count).property("ADBE Scale"), 1.40, 0.32, 0, 100),
  out_scale_x: sample(tr(flame).property("ADBE Scale"), 3.00, 0.40, 0, FS),
  out_scale_y: sample(tr(flame).property("ADBE Scale"), 3.00, 0.40, 1, FS),
  out_alpha: sample(tr(flame).property("ADBE Opacity"), 3.00, 0.40, -1, 100)
};
var json = {
  source: "Adobe After Effects " + app.version + " (tools/streak_flame_ae)",
  composition: "Streak_Badge_Events",
  fps: 60,
  loop: { composition: "Streak_Flame_Loop", fps: loop.frameRate, frames: Math.round(loop.duration * loop.frameRate),
    width: loop.width, height: loop.height, base: [128, 282] },
  tracks: tracks
};
var mf = new File(MOTION);
mf.encoding = "UTF-8";
mf.lineFeed = "Unix";
mf.open("w");
mf.write(JSON.stringify(json, null, 1));
mf.close();

// ---------- renders ----------
app.beginSuppressDialogs();
ensureFolder(ROOT + "artifacts/streak_flame");
ensureFolder(FRAMES);
var old = new Folder(FRAMES).getFiles("*.tif");
for (var o = 0; o < old.length; o++) old[o].remove();
var rq = app.project.renderQueue;
while (rq.numItems > 0) rq.item(1).remove();
var best = function (n) { return n.indexOf("\u6700\u826f") >= 0 || n.indexOf("Best") >= 0; };

var a = rq.items.add(loop);
var rsA = pick(a.templates, [best]);
if (rsA) a.applyTemplate(rsA);
var omA = a.outputModule(1);
var tif = pick(omA.templates, [function (n) { return n.indexOf("TIFF") >= 0; }]);
if (!tif) throw new Error("no TIFF output template");
omA.applyTemplate(tif);
omA.file = new File(FRAMES + "flame_[##].tif");

var b = rq.items.add(ev);
var rsB = pick(b.templates, [best]);
if (rsB) b.applyTemplate(rsB);
var omB = b.outputModule(1);
var h264 = pick(omB.templates, [function (n) { return n.indexOf("H.264") >= 0 && n.indexOf("40") >= 0; }, function (n) { return n.indexOf("H.264") >= 0; }]);
omB.applyTemplate(h264);
omB.file = new File(PREVIEW);

rq.render();
while (rq.numItems > 0) rq.item(1).remove();
app.project.save();
app.endSuppressDialogs(false);
return { frames: new Folder(FRAMES).getFiles("*.tif").length, preview: PREVIEW, motion: MOTION, tiff: tif, h264: h264 };
