// Render PV_S03_C (案 C のロゴ) to docs/pv/previz/frames_s03/s03_c.mp4 (H.264) for review.
// Run after build_s03_c.jsx, in a FRESH After Effects session (see the note in build_s03_c.jsx).
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/frames_s03/s03_c.mp4";
function pick(list, tests) {
    for (var t = 0; t < tests.length; t++) for (var i = 0; i < list.length; i++) if (tests[t](list[i])) return list[i];
    return null;
}
var aep = new File("C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/ae/AIQUIZ_PV_S03_C.aep");
if (!app.project.file || app.project.file.fsName !== aep.fsName) app.open(aep);
var comp = null;
for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === "PV_S03_C") comp = app.project.item(i);
if (!comp) throw new Error("PV_S03_C not found");
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
