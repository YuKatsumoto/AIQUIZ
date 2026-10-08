// Queues the PV for rendering and writes the thumbnail (run after build_pv.jsx, same bridge):
//   node assets/aiquiz_menu_stage/source/ae/ae_run.mjs tools/pv/ae/queue_pv.jsx artifacts/pv/ae_queue.json
//   "G:/adobe/Adobe After Effects 2026/Support Files/aerender.exe" -project C:/AIQUIZ/AIQUIZ-Godot/tools/pv/ae/AIQUIZ_PV.aep
//
// PV_Master goes into the render queue alone (best settings, the "High Quality" output module with
// audio) as artifacts/pv/final/AIQUIZ3D_PV_master_ae.mov; tools/pv/finalize.py turns it into the
// submission mp4. PV_Thumb is saved as artifacts/pv/final/AIQUIZ3D_thumbnail.png, and a few
// PV_Master frames go to artifacts/pv/review/ae/ for a quick look. The project is saved.

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var OUT_MOV = ROOT + "artifacts/pv/final/AIQUIZ3D_PV_master_ae.mov";
var OUT_THUMB = ROOT + "artifacts/pv/final/AIQUIZ3D_thumbnail.png";
var REVIEW = ROOT + "artifacts/pv/review/ae/";
var CHECK_TIMES = [1.5, 4.5, 9.0, 11.6, 14.0, 17.0, 20.5, 25.0, 29.5, 33.5, 37.5, 40.5, 44.0, 48.0, 52.0, 56.0, 59.5];

function comp(name) {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === name) return it;
  }
  throw new Error("no comp " + name);
}

function pick(list, wanted) {
  for (var w = 0; w < wanted.length; w++)
    for (var i = 0; i < list.length; i++) if (list[i] === wanted[w]) return list[i];
  throw new Error("none of " + wanted.join(", ") + " in " + list.join(", "));
}

var master = comp("PV_Master");
var thumb = comp("PV_Thumb");
var rq = app.project.renderQueue;
while (rq.numItems > 0) rq.item(1).remove();

var item = rq.items.add(master);
item.applyTemplate(pick(item.templates, ["最良設定", "Best Settings"]));
var om = item.outputModule(1);
om.applyTemplate(pick(om.templates, ["高品質", "High Quality"]));
om.setSettings({ "Output Audio": "On" });
var mov = new File(OUT_MOV);
if (mov.exists) mov.remove();
om.file = mov;

new Folder(REVIEW).create();
thumb.saveFrameToPng(0, new File(OUT_THUMB));
var frames = [];
for (var c = 0; c < CHECK_TIMES.length; c++) {
  var name = REVIEW + "pv_" + ("0" + Math.floor(CHECK_TIMES[c])).slice(-2) + "_" + Math.round((CHECK_TIMES[c] % 1) * 10) + ".png";
  master.saveFrameToPng(CHECK_TIMES[c], new File(name));
  frames.push(name);
}

app.project.save(new File(ROOT + "tools/pv/ae/AIQUIZ_PV.aep"));
var s = om.getSettings(GetSettingsFormat.STRING);
return { queued: rq.numItems, file: om.file.fsName, format: s["Format"], video: s["Video Output"], audio: s["Output Audio"],
         codec: s["Video Codec"] || null, thumb: OUT_THUMB, frames: frames.length };
