// PV S04-S07: the Godot captures (tests/pv_capture/pv_s04_s05_runtime.gd, pv_s06_s07_runtime.gd, merged by
// tools/pv/merge_subframes.py) with the telops, the S07 subject tags and shutter flashes, and the master comp
// PV_S01_S07 = PV_S01_S03_v3 + PV_S04_S07. Order (docs/pv/capture.md "S04〜S07"):
//   1. node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx
//   2. node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s01_s03_v3.jsx
//   3. node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s04_s07.jsx   (this file; saves AIQUIZ_PV_S01_S07.aep)
//   4. restart AE, then node ... docs/pv/previz/ae/render_s01_s07.jsx
// Times are in PV frames of the segment (1 = the head of S04, 60 fps, 1 beat = 28.125 frames). S04 starts right after
// the v3 part (1180 frames), 1.25 frames before the ideal beat 42 of the 128 BPM grid.
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
function readText(p) { var f = new File(p); f.encoding = "UTF-8"; if (!f.open("r")) throw new Error("cannot open " + p); var s = f.read(); f.close(); return s; }
eval(readText(ROOT + "docs/pv/previz/ae/pv_telop.jsxinc"));
var L = JSON.parse(readText(ROOT + "tools/title_logo_ae/layout.json"));
var YELLOW = [L.belt.bar_color[0], L.belt.bar_color[1], L.belt.bar_color[2]];

var FPS = 60, BEAT = 60 / 128, W = 1920, H = 1080;
var V3_FRAMES = 1180;
// S04 and S05 are 2 bars each (v0.9.1: more time to take them in), S06 and S07 2 bars each
var S04 = 1, S05 = 226, S06 = 451, S07 = 676, END = 901;          // segment frames (S06/S07 = frames 1/226 of their take)
var SEG_FRAMES = END - 1;                                          // 900
var S04_S05_FIRST = ROOT + "artifacts/pv_capture/s04_s05_frames/pv_0001.jpg";
var S06_S07_FIRST = ROOT + "artifacts/pv_capture/s06_s07_frames/pv_0001.jpg";
var SAVE_AS = ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S01_S07.aep";
function bf(b) { return Math.round(b * BEAT * FPS) + 1; }
function T(frame) { return (frame - 1) / FPS; }                   // segment frame -> comp seconds

// S04: zoom slowly into the settings panel until "ゲーム開始" is pressed, then hold (the UI drops and the helicopter comes)
var PANEL_CENTER = [410, 440];
var S04_ZOOM = 112;
var PRESS = bf(5.5);                                               // 156, tests/pv_capture/pv_s04_s05_runtime.gd PRESS_BEAT
var S04_TELOP_END = bf(6.5);                                       // 184: the UI has dropped away
// S07: [tag, take-local beat]
var S07_TAGS = [["算数 4年", 0], ["国語 6年", 1.5], ["理科 3年", 3], ["社会 6年", 4.5], ["英語 3年", 6]];

app.beginSuppressDialogs();
var proj = app.project;
if (!proj || !proj.file || proj.file.name.indexOf("AIQUIZ_PV_S01_S0") < 0) {
    proj = app.open(new File(ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S01_S03_v3.aep"));
}
var v3 = null;
for (var i = 1; i <= proj.numItems; i++) if (proj.item(i) instanceof CompItem && proj.item(i).name === "PV_S01_S03_v3") v3 = proj.item(i);
if (!v3) throw new Error("run build_s01_s03_v3.jsx first (PV_S01_S03_v3 missing)");
for (var j = proj.numItems; j >= 1; j--) {
    var it = proj.item(j);
    if (it instanceof CompItem && (it.name === "PV_S04_S07" || it.name === "PV_S01_S07")) it.remove();
    else if (it instanceof FootageItem && it.mainSource instanceof FileSource && it.mainSource.file &&
             /s04_s05_frames|s06_s07_frames/.test(it.mainSource.file.fsName.replace(/\\/g, "/"))) it.remove();
}
function importSeq(first) {
    var io = new ImportOptions(new File(first));
    io.sequence = true;
    var foot = proj.importFile(io);
    foot.mainSource.conformFrameRate = FPS;
    return foot;
}
var footA = importSeq(S04_S05_FIRST);
var footB = importSeq(S06_S07_FIRST);

app.beginUndoGroup("PV S04-S07");
var comp = proj.items.addComp("PV_S04_S07", W, H, 1.0, SEG_FRAMES / FPS, FPS);
comp.bgColor = [0.05, 0.08, 0.15];

// --- footage ---------------------------------------------------------------------------------------------
// startTime = the comp time of the take's frame 1 (take s04_s05 starts at segment frame 1, take s06_s07 at S06)
function footLayer(foot, name, startTime, t0, t1) {
    var l = comp.layers.add(foot);
    l.name = name;
    l.startTime = startTime;
    l.inPoint = t0;
    l.outPoint = t1;
    return l;
}
var s04 = footLayer(footA, "S04 settings (take s04_s05 1-225)", 0, T(S04), T(S05));
var s05 = footLayer(footA, "S05 helicopter (take s04_s05 226-450)", 0, T(S05), T(S06));
var s06 = footLayer(footB, "S06 walls drop (take s06_s07 1-225)", T(S06), T(S06), T(S07));
var s07 = footLayer(footB, "S07 five subjects (take s06_s07 226-450)", T(S06), T(S07), T(END));

var s04t = s04.property("ADBE Transform Group");
s04t.property("ADBE Anchor Point").setValue(PANEL_CENTER);
s04t.property("ADBE Position").setValue(PANEL_CENTER);
var s04s = s04t.property("ADBE Scale");
s04s.setValueAtTime(T(S04), [100, 100]);
s04s.setValueAtTime(T(PRESS), [S04_ZOOM, S04_ZOOM]);
var zdims = s04s.keyInTemporalEase(2).length, zin = [], zout = [];
for (var zd = 0; zd < zdims; zd++) { zin.push(new KeyframeEase(0, 60)); zout.push(new KeyframeEase(0, 33.33)); }
s04s.setTemporalEaseAtKey(2, zin, zout);
var s07s = s07.property("ADBE Transform Group").property("ADBE Scale");
s07s.setValueAtTime(T(S07), [100, 100]);
s07s.setValueAtTime(T(END), [103, 103]);
for (var k = 1; k <= s07s.numKeys; k++) s07s.setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR);

// --- S03 -> S04: the yellow band from the end of PV_S03_C keeps moving left and uncovers S04 ----------------
var wipe = comp.layers.addShape();
wipe.name = "S04_WIPE_OUT (continues C6_WIPE)";
var wt = wipe.property("ADBE Transform Group");
wt.property("ADBE Anchor Point").setValue([0, 0]);
var wroot = wipe.property("ADBE Root Vectors Group");
function band(name, verts, rgb) {
    var g = wroot.addProperty("ADBE Vector Group");
    g.name = name;
    var c = g.property("ADBE Vectors Group");
    var p = c.addProperty("ADBE Vector Shape - Group");
    var sh = new Shape();
    sh.vertices = verts;
    sh.closed = true;
    p.property("ADBE Vector Shape").setValue(sh);
    var f = c.addProperty("ADBE Vector Graphic - Fill");
    f.property("ADBE Vector Fill Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
}
band("Edge", [[-70, -100], [-10, -100], [-410, H + 100], [-470, H + 100]], [1, 1, 1]);
band("Band", [[0, -100], [2600, -100], [2200, H + 100], [-400, H + 100]], YELLOW);
var wp = wt.property("ADBE Position");
wp.setValueAtTime(0, [-120, 0]);
wp.setValueAtTime(0.32, [-3300, 0]);
wp.setTemporalEaseAtKey(1, [new KeyframeEase(0, 33.33)], [new KeyframeEase(5200, 40)]);
wp.setTemporalEaseAtKey(2, [new KeyframeEase(14000, 40)], [new KeyframeEase(0, 33.33)]);
wipe.inPoint = 0;
wipe.outPoint = 0.34;
wipe.motionBlur = true;
comp.motionBlur = true;
comp.shutterAngle = 180;

// --- telops (storyboard "編集で足す文字") -------------------------------------------------------------------
var tel = [];
tel = tel.concat(telop(comp, "S04", "教科と学年を、[えらぶだけ]", T(S04), T(S04_TELOP_END), { pos: "br" }));
tel = tel.concat(telop(comp, "S06", "AIが、[毎回ちがう問題]をつくる", T(S06), T(S07),
                       { sub: "つくった問題は、別のAIがチェック", subFrom: T(S06 + bf(4) - 1) }));
tel = tel.concat(telop(comp, "S07", "5教科 × [6学年]", T(S07), T(END), { pos: "tc", sub: "学年に合わせた問題を、AIがつくる" }));

// --- S07: subject tags (switch with the wall) and a shutter flash on every switch -----------------------
var tags = [];
for (var q = 0; q < S07_TAGS.length; q++) {
    var f0 = S07 + bf(S07_TAGS[q][1]) - 1;
    var f1 = q + 1 < S07_TAGS.length ? S07 + bf(S07_TAGS[q + 1][1]) - 1 : END;
    tags = tags.concat(telSubjectTag(comp, S07_TAGS[q][0], T(f0), T(f1)));
    var flash = comp.layers.addSolid([1, 1, 1], "S07_FLASH " + S07_TAGS[q][0], W, H, 1.0, 0.2);
    flash.startTime = T(f0);
    flash.inPoint = T(f0);
    flash.outPoint = T(f0) + 0.2;
    var fo = flash.property("ADBE Transform Group").property("ADBE Opacity");
    fo.setValueAtTime(T(f0), q === 0 ? 45 : 70);
    fo.setValueAtTime(T(f0) + 0.13, 0);
    flash.blendingMode = BlendingMode.ADD;
}

// layer order (top to bottom): wipe, telops/tags, flashes, footage
for (var a = tags.length - 1; a >= 0; a--) tags[a].moveToBeginning();   // [text, plate, ...]: text above its plate
for (var b = tel.length - 1; b >= 0; b--) tel[b].moveToBeginning();
wipe.moveToBeginning();
s04.moveToEnd(); s05.moveToEnd(); s06.moveToEnd(); s07.moveToEnd();

var mk = comp.markerProperty;
var marks = [[S04, "S04 教科と学年をえらぶ（押す 156）"], [S05, "S05a ヘリが来て、飛びつく（つかまる 367）"], [bf(13), "S05b 見上げ（打ち上がり 409）"],
             [S06, "S06 問題の壁が落ちる"], [S07, "S07 5教科×6学年"]];
for (var m = 0; m < marks.length; m++) mk.setValueAtTime(T(marks[m][0]), new MarkerValue(marks[m][1]));

// --- master: S01-S07 --------------------------------------------------------------------------------------
var master = proj.items.addComp("PV_S01_S07", W, H, 1.0, (V3_FRAMES + SEG_FRAMES) / FPS, FPS);
master.bgColor = [0.05, 0.08, 0.15];
var lv3 = master.layers.add(v3);
lv3.name = "PV_S01_S03_v3 (1-1180)";
lv3.startTime = 0;
var lseg = master.layers.add(comp);
lseg.name = "PV_S04_S07 (1181-2080)";
lseg.startTime = V3_FRAMES / FPS;
lseg.moveToBeginning();
var mm = master.markerProperty;
var mmarks = [[0, "S01"], [V3_FRAMES / FPS, "S04"], [(V3_FRAMES + S05 - 1) / FPS, "S05"], [(V3_FRAMES + S06 - 1) / FPS, "S06"],
              [(V3_FRAMES + S07 - 1) / FPS, "S07"]];
for (var n = 0; n < mmarks.length; n++) mm.setValueAtTime(mmarks[n][0], new MarkerValue(mmarks[n][1]));
app.endUndoGroup();

var colored = [];
for (var c = 0; c < tel.length; c++) if (tel[c].__plain) colored.push(tel[c].name + ":" + tel[c].__colored);
proj.save(new File(SAVE_AS));
app.endSuppressDialogs(false);
return { comp: comp.name, frames: Math.round(comp.duration * FPS), master: master.name,
         masterFrames: Math.round(master.duration * FPS), footA: footA.name + " " + Math.round(footA.duration * FPS),
         footB: footB.name + " " + Math.round(footB.duration * FPS), layers: comp.numLayers, colored: colored, saved: proj.file.fsName };
