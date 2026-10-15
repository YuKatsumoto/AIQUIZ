// PV S01-S03 (new flow, storyboard v3): joins the Godot capture (01-09) and the logo (案 C) into comp PV_S01_S03_v3.
// Order (see docs/pv/capture.md "S01〜S03 v3"):
//   1. node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx      (reads s03_c_bg.json:
//      background = artifacts/pv_capture/v3_frames from PV frame 957, saved as AIQUIZ_PV_S01_S03_v3.aep)
//   2. node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s01_s03_v3.jsx  (this file)
//   3. restart AE, then node ... docs/pv/previz/ae/render_s01_s03_v3.jsx
// The capture sequence is shared with PV_S03_C (the same footage item).
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var FPS = 60, FRAMES = 1180, LOGO_FRAME = 957;
var W = 1920, H = 1080;
var SHOTS = [[1, "01 2 人がコンベアの前に"], [114, "02 壁が落ちてくる"], [226, "03 寄る・青い扉を見る"], [339, "04 前から：赤・青・赤"],
             [451, "05 P2 が先に決める"], [507, "06 踊りながら、まちがいへ"], [620, "07 ゴツン"],
             [662, "07b 煽る（746 で P2 が爆散）"], [774, "08 P1 が青い扉へ"], [840, "09 踊りながら突き破る（突破 846）"], [957, "ロゴ（案 C）"]];

var proj = app.project;
if (!proj || !proj.file || proj.file.name.indexOf("AIQUIZ_PV_S01_S03_v3") < 0) {
    proj = app.open(new File(ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S01_S03_v3.aep"));
}
var logo = null, bgFoot = null;
for (var i = 1; i <= proj.numItems; i++) {
    var it = proj.item(i);
    if (it instanceof CompItem && it.name === "PV_S03_C") logo = it;
    if (it instanceof FootageItem && it.mainSource instanceof FileSource && !it.mainSource.isStill) bgFoot = it;
}
if (!logo || !bgFoot) throw new Error("run build_s03_c.jsx first (PV_S03_C / capture sequence missing)");
for (var j = proj.numItems; j >= 1; j--) if (proj.item(j) instanceof CompItem && proj.item(j).name === "PV_S01_S03_v3") proj.item(j).remove();

app.beginUndoGroup("PV S01-S03 v3");
var comp = proj.items.addComp("PV_S01_S03_v3", W, H, 1.0, FRAMES / FPS, FPS);
comp.bgColor = [0.05, 0.08, 0.15];
var tLogo = (LOGO_FRAME - 1) / FPS;
var bg = comp.layers.add(bgFoot);
bg.name = "Godot capture 01-09 (PV 1-" + (LOGO_FRAME - 1) + ")";
bg.startTime = 0;
bg.inPoint = 0;
bg.outPoint = tLogo;
var lg = comp.layers.add(logo);
lg.name = "PV_S03_C (logo, PV " + LOGO_FRAME + "-)";
lg.startTime = tLogo;
lg.moveToBeginning();
for (var s = 0; s < SHOTS.length; s++) comp.markerProperty.setValueAtTime((SHOTS[s][0] - 1) / FPS, new MarkerValue(SHOTS[s][1]));
app.endUndoGroup();
proj.save();
return { comp: comp.name, frames: Math.round(comp.duration * FPS), bg: bgFoot.name, bgFrames: Math.round(bgFoot.duration * FPS),
         logoAt: tLogo, saved: proj.file.fsName };
