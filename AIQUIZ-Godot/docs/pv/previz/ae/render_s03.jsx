// Render PV_S03 to a PNG sequence for review.
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/frames_s03/s03_[####].png";
var comp = null;
for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof CompItem && it.name === "PV_S03") comp = it;
}
if (!comp) throw new Error("PV_S03 missing");
var rq = app.project.renderQueue;
for (var j = rq.numItems; j >= 1; j--) rq.item(j).remove();
var item = rq.items.add(comp);
var om = item.outputModule(1);
var tpl = null, names = om.templates;
for (var k = 0; k < names.length; k++) { if (/PNG/i.test(names[k])) { tpl = names[k]; break; } }
if (tpl) om.applyTemplate(tpl);
new Folder("C:/AIQUIZ/AIQUIZ-Godot/docs/pv/previz/frames_s03").create();
om.file = new File(OUT);
rq.render();
return { template: tpl, status: String(item.status), templates: names.join(" | ") };
