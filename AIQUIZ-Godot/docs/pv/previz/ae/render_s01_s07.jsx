// Render PV_S01_S07 (video only; the sound is mixed by tools/pv/mix_s01_s07.py and muxed with ffmpeg).
// Run in a FRESH After Effects session (on this PC AE 2026 fails on the second render of a session).
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/v4/PV_S01-S07_video.mp4";
function pick(list, tests) {
    for (var t = 0; t < tests.length; t++) for (var i = 0; i < list.length; i++) if (tests[t](list[i])) return list[i];
    return null;
}
var aep = new File("C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/ae/AIQUIZ_PV_S01_S07.aep");
if (!app.project.file || app.project.file.fsName !== aep.fsName) app.open(aep);
var comp = null;
for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === "PV_S01_S07") comp = app.project.item(i);
if (!comp) throw new Error("PV_S01_S07 not found");
app.beginSuppressDialogs();
var rq = app.project.renderQueue;
while (rq.numItems > 0) rq.item(1).remove();
var item = rq.items.add(comp);
var rs = pick(item.templates, [function (n) { return n.indexOf("\u6700\u826f") >= 0; }, function (n) { return n.indexOf("Best") >= 0; }]);
if (rs) item.applyTemplate(rs);
var om = item.outputModule(1);
var tpl = pick(om.templates, [function (n) { return n.indexOf("H.264") >= 0 && n.indexOf("40") >= 0; }, function (n) { return n.indexOf("H.264") >= 0; }]);
if (!tpl) throw new Error("no H.264 output module template");
om.applyTemplate(tpl);
var f = new File(OUT);
if (!f.parent.exists) f.parent.create();
om.file = f;
rq.render();
var st = String(item.status);
item.remove();
app.endSuppressDialogs(false);
return { file: OUT, template: tpl, settings: rs, status: st };
