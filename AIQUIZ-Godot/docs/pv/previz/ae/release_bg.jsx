// Removes the captured image sequence from the open AE project so Godot can overwrite the frames
// (AE keeps the files locked while the footage is in the project). Run before a new capture:
//   node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/release_bg.jsx
var removed = [];
for (var i = app.project.numItems; i >= 1; i--) {
    var it = app.project.item(i);
    if (it instanceof FootageItem && (it.name.indexOf("pv_[") === 0 || it.name === "pv_0337.jpg")) {
        removed.push(it.name);
        it.remove();
    }
}
app.purge(PurgeTarget.ALL_CACHES);
if (app.project.file) app.project.save();
return { removed: removed };
