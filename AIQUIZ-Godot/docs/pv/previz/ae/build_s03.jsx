// PV S03 "logo" (2 bars): builds comp PV_S03 in the open AE project.
// Run: node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03.jsx
// The title logo AEP is imported (not opened), so the original file is untouched.
// Background: the Godot capture keeps running under the logo (frames 338-562 of
// artifacts/pv_capture/s01_s03: P1 dances in front of the broken door while the belt carries the wall away).
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var LOGO_AEP = ROOT + "tools/title_logo_ae/AIQUIZ_TitleLogo.aep";
var BG_FIRST = ROOT + "artifacts/pv_capture/s01_s03/pv_0001.jpg";   // numbered sequence pv_0001..pv_0562
var BG_START_FRAME = 338;                                            // PV frame shown at comp time 0
var SAVE_AS = ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S03.aep";
var FPS = 60, DUR = 3.75;                                            // 2 bars at 128 BPM
var SRC_IN = 0.35, SRC_OUT = 4.622, SPEED = 2.0;                     // deploy -> A-Q bar done, at 2x
var T_DONE = (SRC_OUT - SRC_IN) / SPEED;                             // = 2.136 s, then hold
var LOGO_Y = 335;                                                    // belt ends ~470 px; the S03 camera keeps the runners in the lower half
var BLUR = 14, DIM = 38;

app.beginUndoGroup("PV S03");
var proj = app.project;
function findComp(name) {
    for (var i = 1; i <= proj.numItems; i++) {
        var it = proj.item(i);
        if (it instanceof CompItem && it.name === name) return it;
    }
    return null;
}
// 1) title logo project (imported once)
var logo = findComp("TitleLogo_Intro");
if (!logo) {
    proj.importFile(new ImportOptions(new File(LOGO_AEP)));
    logo = findComp("TitleLogo_Intro");
}
if (!logo) throw new Error("TitleLogo_Intro not found after import");
for (var l = 1; l <= logo.numLayers; l++) {
    if (logo.layer(l).name === "BG_Preview") logo.layer(l).enabled = false;
}
// 2) background: the capture as a 60 fps image sequence (old stills removed)
for (var i2 = proj.numItems; i2 >= 1; i2--) {
    var it2 = proj.item(i2);
    if (it2 instanceof FootageItem && (it2.name === "pv_0337.jpg" || it2.name.indexOf("pv_[") === 0)) it2.remove();
}
var io = new ImportOptions(new File(BG_FIRST));
io.sequence = true;
var bgFoot = proj.importFile(io);
bgFoot.mainSource.conformFrameRate = FPS;
// 3) comp
var old = findComp("PV_S03");
if (old) old.remove();
var comp = proj.items.addComp("PV_S03", 1920, 1080, 1.0, DUR, FPS);
comp.bgColor = [0.04, 0.07, 0.14];
var bg = comp.layers.add(bgFoot);
bg.name = "BG_capture (PV " + BG_START_FRAME + "-)";
bg.startTime = -(BG_START_FRAME - 1) / FPS;
bg.inPoint = 0; bg.outPoint = DUR;
var sx = 1920 / bgFoot.width * 100 * 1.03;                              // a little overscan hides blur edges
bg.property("Transform").property("Scale").setValue([sx, sx]);
var blur = bg.property("Effects").addProperty("ADBE Gaussian Blur 2");
blur.property(1).setValue(BLUR);
try { blur.property("ADBE Gaussian Blur 2-0003").setValue(1); } catch (e) {}  // repeat edge pixels
var dim = comp.layers.addSolid([0.03, 0.06, 0.14], "DIM", 1920, 1080, 1.0, DUR);
dim.property("Transform").property("Opacity").setValue(DIM);
dim.moveBefore(bg);
// 4) logo with time remap: the authored motion at 2x, then hold
var lg = comp.layers.add(logo);
lg.name = "TitleLogo_Intro (2x)";
lg.moveToBeginning();
var tr = lg.property("Transform");
tr.property("Anchor Point").setValue([603.5, 672]);
tr.property("Position").setValue([960, LOGO_Y]);
lg.timeRemapEnabled = true;
var rm = lg.property("ADBE Time Remapping");
rm.setValueAtTime(0, SRC_IN);
rm.setValueAtTime(T_DONE, SRC_OUT);
rm.setValueAtTime(DUR, SRC_OUT);
for (var kk = rm.numKeys; kk >= 1; kk--) {
    if (rm.keyTime(kk) > DUR + 0.0001) rm.removeKey(kk);
}
for (var k = 1; k <= rm.numKeys; k++) {
    rm.setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR, KeyframeInterpolationType.LINEAR);
}
lg.outPoint = DUR;
var sc = tr.property("Scale");
sc.setValueAtTime(T_DONE, [100, 100]);
sc.setValueAtTime(DUR, [104, 104]);
var e = new KeyframeEase(0, 33);
sc.setTemporalEaseAtKey(1, [e, e, e], [e, e, e]);
comp.markerProperty.setValueAtTime(0, new MarkerValue("S03 start (bar 4)"));
comp.markerProperty.setValueAtTime(T_DONE, new MarkerValue("logo complete -> hold"));
comp.markerProperty.setValueAtTime(DUR / 2, new MarkerValue("bar 5"));
app.endUndoGroup();
proj.save(new File(SAVE_AS));
return { comp: comp.name, frames: Math.round(comp.duration * comp.frameRate), t_done: T_DONE, bg: bgFoot.name, bgFrames: Math.round(bgFoot.duration * FPS), saved: proj.file ? proj.file.fsName : null };
