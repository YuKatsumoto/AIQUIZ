// AIQUIZ online battle "VS" cut-in -- render both variants with the AE render queue (H.264).
// Run inside the RUNNING After Effects with AIQUIZ_VS_Cutin.aep open (build_vs_cutin.jsx leaves it open):
//   "G:\adobe\Adobe After Effects 2026\Support Files\AfterFX.exe" -r C:\AIQUIZ\AIQUIZ-Godot\tools\online_cutin_ae\render_vs_cutin.jsx
// Output: artifacts/online_cutin_ae/VS_Cutin_host.mp4  (CTRL > Guest View = 0 : left orange / right blue)
//         artifacts/online_cutin_ae/VS_Cutin_guest.mp4 (CTRL > Guest View = 1 : left blue / right orange)
// The comp is left in the host state and the project is saved afterwards.
// Problems are reported as project folders "_render_log/..." (never as modal dialogs).
(function () {
    var OUT = "C:/AIQUIZ/AIQUIZ-Godot/artifacts/online_cutin_ae/";
    var AEP = "C:/AIQUIZ/AIQUIZ-Godot/tools/online_cutin_ae/AIQUIZ_VS_Cutin.aep";
    var LOG = [];
    function log(s) { LOG.push(String(s)); }
    function errText(e) { try { return String(e.message) + (e.line ? " @line " + e.line : ""); } catch (x) { return "error"; } }
    function find(name) {
        for (var i = 1; i <= app.project.numItems; i++) {
            var it = app.project.item(i);
            if (it instanceof CompItem && it.name === name) { return it; }
        }
        return null;
    }
    function pick(list, tests) {
        for (var t = 0; t < tests.length; t++) {
            for (var i = 0; i < list.length; i++) { if (tests[t](list[i])) { return list[i]; } }
        }
        return null;
    }

    app.beginSuppressDialogs();
    try {
        var comp = find("VS_Cutin");
        if (!comp) { throw new Error("VS_Cutin not found (open AIQUIZ_VS_Cutin.aep first)"); }
        var guest = comp.layer("CTRL").property("ADBE Effect Parade").property("Guest View").property(1);
        var rq = app.project.renderQueue;
        while (rq.numItems > 0) { rq.item(1).remove(); }

        function render(guestValue, fileName) {
            guest.setValue(guestValue);
            var item = rq.items.add(comp);
            item.timeSpanStart = 0;
            item.timeSpanDuration = comp.duration;
            var rs = pick(item.templates, [
                function (n) { return n.indexOf("\u6700\u826f") >= 0; },      // "Best Settings" (Japanese UI)
                function (n) { return n.indexOf("Best") >= 0; }
            ]);
            if (rs) { item.applyTemplate(rs); }
            var om = item.outputModule(1);
            var tpl = pick(om.templates, [
                function (n) { return n.indexOf("H.264") >= 0 && n.indexOf("40") >= 0; },
                function (n) { return n.indexOf("H.264") >= 0; }
            ]);
            if (!tpl) { throw new Error("no H.264 output module template"); }
            om.applyTemplate(tpl);
            om.file = new File(OUT + fileName);
            rq.render();
            log("rendered " + fileName + " rs=" + rs + " om=" + tpl);
            item.remove();
        }
        render(0, "VS_Cutin_host.mp4");
        render(1, "VS_Cutin_guest.mp4");
        guest.setValue(0);
        app.project.save(new File(AEP));
    } catch (e) {
        log("RENDER FAILED: " + errText(e));
    }
    var bad = false;
    for (var i = 0; i < LOG.length; i++) { if (LOG[i].indexOf("FAILED") >= 0) { bad = true; } }
    if (bad) {
        var f = app.project.items.addFolder("_render_log");
        for (var j = 0; j < LOG.length; j++) { app.project.items.addFolder(String(j) + " " + LOG[j].substring(0, 230)).parentFolder = f; }
    }
    app.endSuppressDialogs(false);
})();
