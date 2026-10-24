// PV S03 ロゴ（TESTOPIA）: builds comp PV_S03_T in a NEW After Effects project.
// Run: node tools/title_logo_ae/ae_run.mjs docs/pv/previz/ae/build_s03_t.jsx
// The open project must be saved (the script refuses to close a project with unsaved changes).
// Saved as s03_c_bg.json "save_as" (AIQUIZ_PV_S01_S03_v3.aep), which build_s01_s03_v3.jsx then opens.
//
// The logo itself is NOT rebuilt in AE: it is the game's own title intro (TitleLogoIntro, TESTOPIA on the belt, the door
// block bursting into T and E), rendered by Godot to transparent PNGs with the same shapes, belt, outline and supersampling:
//   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/pv_capture/pv_logo_capture.gd
//       -- tag=s03 zoom=4 top=120 t0=0.35 speed=1.92 frames=225
// 2 bars at 128 BPM = 3.75 s. The intro runs at 1.92x from DEPLOY, so that
//   beat 1      the yellow line deploys and opens into the belt (the game's motion)
//   bar 2 head  ALL SEATED (+0.03 s): every piece clicks in, a small pulse
//   beat 6      BURST: the door block bursts, T and E pop out; PV accents: white flash, light streaks, diagonal slashes,
//               zoom punch (107%)
//   beats 6-7   hold: slow push-in to 104%, sparkles, camera flashes in the stands (right)
//   beat 8      the belt carries the logo out to the left, a yellow diagonal band wipes to S04 (last frame fully yellow;
//               build_s04_s07.jsx continues the band)
// Background: the Godot capture continues under the logo, NOT blurred or dimmed (PV frames 957-, s03_c_bg.json).
// 長さ・ロゴの連番・保存先を変えるとき（10/20 夜の S03 20 拍）は、$.global.S03_T_CFG に
//   { frames: コンポのフレーム数, logo_dir: "artifacts/pv_capture/logo_…/", bg_first, bg_start_frame, save_as, close_after: true }
// を置いてからこのファイルを流す（build_s03_t_long.jsx）。最後の 1 拍でワイプ（T_OUT = 長さ − 1 拍）は長さに合わせて動く。
// 置かなければ今までどおり（2 小節・logo_s03・AIQUIZ_PV_S01_S03_v3.aep）。
var ROOT = "G:/AIQUIZ-Main/AIQUIZ-Godot/";
var LOGO_DIR = ROOT + "artifacts/pv_capture/logo_s03/";
var BG_FIRST = ROOT + "artifacts/pv_capture/v3_frames/pv_0001.jpg";
var BG_START_FRAME = 957;
var SAVE_AS = ROOT + "docs/pv/previz/ae/AIQUIZ_PV_S01_S03_v3.aep";
var W = 1920, H = 1080, FPS = 60, BEAT = 60 / 128, DUR = 8 * BEAT;  // 3.75 s
var YELLOW = [1.0, 0.88, 0.25];                                      // TitleLogoIntro.BAR_COLOR (the belt's yellow edge)

function readJson(path) {
    var f = new File(path);
    f.encoding = "UTF-8";
    if (!f.open("r")) throw new Error("cannot open " + path);
    var s = f.read();
    f.close();
    return JSON.parse(s);
}
var CFG = new File(ROOT + "docs/pv/previz/ae/s03_c_bg.json");
if (CFG.exists) {
    var cfg = readJson(CFG.fsName);
    if (cfg.bg_first) BG_FIRST = cfg.bg_first;
    if (cfg.bg_start_frame) BG_START_FRAME = cfg.bg_start_frame;
    if (cfg.save_as) SAVE_AS = cfg.save_as;
}
var OPT = $.global.S03_T_CFG || null;
$.global.S03_T_CFG = null;
if (OPT) {
    if (OPT.logo_dir) LOGO_DIR = ROOT + OPT.logo_dir;
    if (OPT.bg_first) BG_FIRST = ROOT + OPT.bg_first;
    if (OPT.bg_start_frame) BG_START_FRAME = OPT.bg_start_frame;
    if (OPT.save_as) SAVE_AS = ROOT + OPT.save_as;
    if (OPT.frames) DUR = OPT.frames / FPS;
}
var R = readJson(LOGO_DIR + "report.json");
var HR = R.holder_rect;                                              // [x, y, w, h] of the logo (letters) on screen
var LOGO_L = HR[0], LOGO_R = HR[0] + HR[2], YT = HR[1], LOGO_H = HR[3];
var BELT_TOP = YT + R.belt_rect_logical[1] * R.zoom, BELT_H = R.belt_rect_logical[3] * R.zoom;
function mt(name) { return (R.markers[name].pv_frame - 1) / FPS; }   // marker -> comp seconds
var T_SEAT = mt("ALL SEATED"), T_HIT = mt("BURST"), T_END = mt("END"), T_OUT = DUR - BEAT;   // 2 小節なら 7 拍目
var seed = 20261019;
function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

// ---------- keyframe helpers (same as build_s03_c.jsx) ----------
function ease(e, dims) {
    var a = [];
    var sp = e ? e[0] : 0, inf = e ? e[1] : 33.33;
    for (var i = 0; i < dims; i++) a.push(new KeyframeEase(sp, inf));
    return a;
}
// key(prop, t, value, inEase, outEase); ease = [speed, influence] or null (= [0, 33.33])
function key(prop, t, value, inE, outE) {
    prop.setValueAtTime(t, value);
    var i = prop.nearestKeyIndex(t);
    prop.setInterpolationTypeAtKey(i, KeyframeInterpolationType.BEZIER, KeyframeInterpolationType.BEZIER);
    var dims = prop.keyInTemporalEase(i).length;
    prop.setTemporalContinuousAtKey(i, false);
    if (inE !== undefined || outE !== undefined) {
        try { prop.setTemporalEaseAtKey(i, ease(inE === undefined ? null : inE, dims), ease(outE === undefined ? null : outE, dims)); } catch (e) {}
    }
    if (prop.isSpatial) { prop.setSpatialAutoBezierAtKey(i, false); prop.setSpatialContinuousAtKey(i, false); }
}
function tr(layer) { return layer.property("ADBE Transform Group"); }
function fx(layer, matchName) { return layer.property("ADBE Effect Parade").addProperty(matchName); }
function setP(group, matchName, value) { try { group.property(matchName).setValue(value); return true; } catch (e) { return false; } }
function glow(layer, threshold, radius, intensity) {
    var g = fx(layer, "ADBE Glo2");
    setP(g, "ADBE Glo2-0002", threshold);
    setP(g, "ADBE Glo2-0003", radius);
    setP(g, "ADBE Glo2-0004", intensity);
    return g;
}
function group(root, name) {
    var g = root.addProperty("ADBE Vector Group");
    g.name = name;
    return g;
}
function contents(g) { return g.property("ADBE Vectors Group"); }
function fill(c, rgb, opacity) {
    var f = c.addProperty("ADBE Vector Graphic - Fill");
    f.property("ADBE Vector Fill Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
    if (opacity !== undefined) f.property("ADBE Vector Fill Opacity").setValue(opacity);
    return f;
}
function stroke(c, rgb, width) {
    var s = c.addProperty("ADBE Vector Graphic - Stroke");
    s.property("ADBE Vector Stroke Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
    s.property("ADBE Vector Stroke Width").setValue(width);
    return s;
}
function poly(c, verts, closed) {
    var p = c.addProperty("ADBE Vector Shape - Group");
    var sh = new Shape();
    sh.vertices = verts;
    sh.closed = closed !== false;
    p.property("ADBE Vector Shape").setValue(sh);
    return p;
}
function star(c, pos, outer, inner, rot) {
    var s = c.addProperty("ADBE Vector Shape - Star");
    s.property("ADBE Vector Star Type").setValue(1);
    s.property("ADBE Vector Star Points").setValue(4);
    s.property("ADBE Vector Star Outer Radius").setValue(outer);
    s.property("ADBE Vector Star Inner Radius").setValue(inner);
    s.property("ADBE Vector Star Rotation").setValue(rot || 0);
    s.property("ADBE Vector Star Position").setValue(pos);
    return s;
}
function shapeLayer(comp, name, pos) {
    var l = comp.layers.addShape();
    l.name = name;
    tr(l).property("ADBE Anchor Point").setValue([0, 0]);
    tr(l).property("ADBE Position").setValue(pos || [0, 0]);
    return l;
}

// ---------- project ----------
if (app.project && app.project.dirty) throw new Error("the open project has unsaved changes: save or close it first (" +
    (app.project.file ? app.project.file.fsName : "untitled") + ")");
app.beginSuppressDialogs();
if (app.project) app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
app.newProject();
var proj = app.project;
proj.bitsPerChannel = 16;
function importSeq(first) {
    var io = new ImportOptions(new File(first));
    io.sequence = true;
    var foot = proj.importFile(io);
    foot.mainSource.conformFrameRate = FPS;
    return foot;
}
var bgFoot = importSeq(BG_FIRST);
var logoFoot = importSeq(LOGO_DIR + "l_0001.png");
logoFoot.name = "TESTOPIA title intro (Godot, x" + R.speed + ")";
// Godot's frame buffer: colour already multiplied by alpha
logoFoot.mainSource.alphaMode = AlphaMode.PREMULTIPLIED;
logoFoot.mainSource.premulColor = [0, 0, 0];

var comp = proj.items.addComp("PV_S03_T", W, H, 1.0, DUR, FPS);
comp.bgColor = [0.05, 0.08, 0.15];
comp.motionBlur = true;
comp.shutterAngle = 180;

// 1) background: the capture continues under the logo
var bg = comp.layers.add(bgFoot);
bg.name = "BG_capture (PV " + BG_START_FRAME + "-)";
bg.startTime = -(BG_START_FRAME - 1) / FPS;
bg.inPoint = 0; bg.outPoint = DUR;
tr(bg).property("ADBE Scale").setValue([W / bgFoot.width * 100, W / bgFoot.width * 100]);

// 2) the logo (the game's intro); the belt carries it out to the left on the last beat
var logo = comp.layers.add(logoFoot);
logo.name = "LOGO_TESTOPIA (Godot)";
logo.startTime = 0;
logo.inPoint = 0; logo.outPoint = DUR;
var lp = tr(logo).property("ADBE Position");
key(lp, T_OUT, [W / 2, H / 2], null, [0, 60]);
key(lp, DUR, [W / 2 - 2700, H / 2], [7000, 40], null);
logo.motionBlur = true;

// 3) the burst (BURST): diagonal slashes, light streaks, white flash
var slash = shapeLayer(comp, "BURST_SLASHES", [W / 2, YT + LOGO_H / 2]);
var sroot = slash.property("ADBE Root Vectors Group");
var LL = LOGO_L - W / 2, RR = LOGO_R - W / 2;   // logo ends, relative to the layer (logo centre)
var SL = [  // [x, y, length, thickness, colour] around the logo, all at -60 degrees
    [LL - 30, -50, 620, 60, YELLOW], [LL + 80, 60, 380, 22, [1, 1, 1]],
    [RR + 30, -40, 660, 64, YELLOW], [RR - 80, 70, 400, 22, [1, 1, 1]],
    [-260, -190, 440, 24, [1, 1, 1]], [300, 200, 480, 30, YELLOW]
];
for (var k = 0; k < SL.length; k++) {
    var a = SL[k];
    var sgc = contents(group(sroot, "Slash" + k));
    var dx = Math.cos(-60 * Math.PI / 180) * a[2] / 2, dy = Math.sin(-60 * Math.PI / 180) * a[2] / 2;
    poly(sgc, [[a[0] - dx - a[3] / 2, a[1] - dy], [a[0] - dx + a[3] / 2, a[1] - dy], [a[0] + dx + a[3] / 2, a[1] + dy], [a[0] + dx - a[3] / 2, a[1] + dy]], true);
    fill(sgc, a[4]);
}
var sls = tr(slash).property("ADBE Scale");
key(sls, T_HIT, [60, 60], null, [0, 20]);
key(sls, T_HIT + 0.07, [104, 104], [0, 50], [0, 50]);
key(sls, T_HIT + 0.45, [112, 112], [0, 50], null);
var slo = tr(slash).property("ADBE Opacity");
key(slo, T_HIT, 100, null, null);
key(slo, T_HIT + 0.30, 100, null, [0, 50]);
key(slo, T_HIT + 0.48, 0, [0, 50], null);
slash.inPoint = T_HIT; slash.outPoint = T_HIT + 0.5;

var streak = shapeLayer(comp, "BURST_STREAKS", [0, 0]);
var stc = contents(group(streak.property("ADBE Root Vectors Group"), "Streaks"));
for (var s2 = 0; s2 < 14; s2++) {
    var yy = YT + (0.1 + rnd() * 0.8) * LOGO_H;
    var left = s2 % 2 === 0;
    var l0 = 40 + rnd() * 100, l1 = l0 + 420 + rnd() * 700;
    if (left) poly(stc, [[LOGO_L - l0, yy], [LOGO_L - l1, yy]], false);
    else poly(stc, [[LOGO_R + l0, yy], [LOGO_R + l1, yy]], false);
}
stroke(stc, [1, 1, 1], 6);
var trim3 = stc.addProperty("ADBE Vector Filter - Trim");
var t3s = trim3.property("ADBE Vector Trim Start"), t3e = trim3.property("ADBE Vector Trim End");
key(t3e, T_HIT, 0, null, [0, 15]);
key(t3e, T_HIT + 0.12, 100, [0, 60], null);
key(t3s, T_HIT + 0.08, 0, null, [0, 20]);
key(t3s, T_HIT + 0.42, 100, [0, 60], null);
glow(streak, 30, 18, 1.3);
streak.inPoint = T_HIT; streak.outPoint = T_HIT + 0.45;

var flash = comp.layers.addSolid([1, 1, 1], "BURST_FLASH", W, H, 1.0, DUR);
flash.blendingMode = BlendingMode.ADD;
var fo = tr(flash).property("ADBE Opacity");
key(fo, T_HIT - 1 / FPS, 0, null, null);
key(fo, T_HIT, 40, null, [0, 20]);
key(fo, T_HIT + 0.2, 0, [0, 70], null);
flash.inPoint = T_HIT - 1 / FPS; flash.outPoint = T_HIT + 0.21;

// 4) hold: sparkles around the logo, camera flashes in the stands (right)
var spark = shapeLayer(comp, "HOLD_SPARKLES", [0, 0]);
var sproot = spark.property("ADBE Root Vectors Group");
var SPK = [[LOGO_L - 40, YT + 30], [LOGO_L + 300, YT - 30], [W / 2 + 80, YT - 40], [LOGO_R - 120, YT - 20], [LOGO_R + 50, YT + 120],
           [LOGO_R - 40, BELT_TOP + 80], [W / 2 - 220, BELT_TOP + 90], [LOGO_L + 120, BELT_TOP + 70], [W / 2 + 330, YT + 110], [LOGO_L + 640, YT + 20]];
for (var q = 0; q < SPK.length; q++) {
    var sg2 = group(sproot, "Spark" + q);
    var sgt = sg2.property("ADBE Vector Transform Group");
    sgt.property("ADBE Vector Position").setValue(SPK[q]);
    var c2 = contents(sg2);
    star(c2, [0, 0], 14 + rnd() * 16, 2.0, rnd() * 15);
    fill(c2, [1, 1, 1]);
    var t0 = T_HIT + 0.18 + rnd() * (T_OUT - T_HIT - 0.4);
    var gsc = sgt.property("ADBE Vector Scale");
    key(gsc, t0, [0, 0], null, [0, 40]);
    key(gsc, t0 + 0.12, [110, 110], [0, 50], [0, 50]);
    key(gsc, t0 + 0.30, [0, 0], [0, 60], null);
}
glow(spark, 30, 14, 1.0);
spark.inPoint = T_HIT; spark.outPoint = T_OUT + 0.3;

var crowd = shapeLayer(comp, "HOLD_CROWD_FLASHES", [0, 0]);
var croot = crowd.property("ADBE Root Vectors Group");
for (var cf = 0; cf < 14; cf++) {
    var cg = group(croot, "Flash" + cf);
    var cgt = cg.property("ADBE Vector Transform Group");
    cgt.property("ADBE Vector Position").setValue([1630 + rnd() * 270, 400 + rnd() * 120]);
    var c3 = contents(cg);
    star(c3, [0, 0], 10 + rnd() * 10, 1.6, rnd() * 20);
    fill(c3, [1, 1, 1]);
    var t1 = T_HIT + 0.1 + rnd() * (T_OUT - T_HIT - 0.2);
    var fop = cgt.property("ADBE Vector Group Opacity");
    key(fop, t1 - 1 / FPS, 0, null, null);
    key(fop, t1, 100, null, null);
    key(fop, t1 + 4 / FPS, 0, null, null);
}
glow(crowd, 20, 12, 1.4);
crowd.blendingMode = BlendingMode.ADD;
crowd.inPoint = T_HIT; crowd.outPoint = T_OUT + 0.2;

// 5) camera: a small pulse when every piece clicks in, a zoom punch at the burst, slow 4% push-in while holding
var cam = comp.layers.addSolid([1, 1, 1], "CAM_pulse_punch_push (adjustment)", W, H, 1.0, DUR);
cam.adjustmentLayer = true;
var xf = fx(cam, "ADBE Geometry2");
setP(xf, "ADBE Geometry2-0001", [W / 2, YT + LOGO_H / 2]);   // anchor: the logo centre
setP(xf, "ADBE Geometry2-0002", [W / 2, YT + LOGO_H / 2]);
var xfs = xf.property("ADBE Geometry2-0003");                // Scale (uniform)
key(xfs, T_SEAT, 100, null, [0, 20]);
key(xfs, T_SEAT + 3 / FPS, 101.6, [0, 50], [0, 50]);
key(xfs, T_SEAT + 0.16, 100, [0, 60], null);
key(xfs, T_HIT, 100, null, [0, 20]);
key(xfs, T_HIT + 3 / FPS, 107, [0, 50], [0, 50]);
key(xfs, T_HIT + 0.24, 100.5, [0, 60], [0, 33.33]);
key(xfs, T_OUT, 104, null, [0, 33.33]);
setP(xf, "ADBE Geometry2-0009", 0);                          // use the comp shutter: off
setP(xf, "ADBE Geometry2-0010", 180);

// 6) wipe to S04: a big yellow diagonal band from the right, with a white leading edge (build_s04_s07.jsx continues it)
var wipe = shapeLayer(comp, "WIPE_TO_S04", [W + 500, 0]);
var wroot = wipe.property("ADBE Root Vectors Group");
var edge = contents(group(wroot, "Edge"));
poly(edge, [[-70, -100], [-10, -100], [-410, H + 100], [-470, H + 100]], true);
fill(edge, [1, 1, 1]);
var band = contents(group(wroot, "Band"));
poly(band, [[0, -100], [2600, -100], [2200, H + 100], [-400, H + 100]], true);
fill(band, YELLOW);
var wp = tr(wipe).property("ADBE Position");
key(wp, T_OUT, [W + 520, 0], null, [0, 60]);
key(wp, DUR, [-120, 0], [5200, 40], null);
wipe.inPoint = T_OUT; wipe.outPoint = DUR;
wipe.motionBlur = true;

// layer order (top to bottom): wipe, camera, flash, streaks, slashes, sparkles, crowd, logo, background
wipe.moveToBeginning();
cam.moveAfter(wipe);
flash.moveAfter(cam);
streak.moveAfter(flash);
slash.moveAfter(streak);
spark.moveAfter(slash);
crowd.moveAfter(spark);
logo.moveAfter(crowd);
bg.moveToEnd();

var mk = comp.markerProperty;
var marks = [[0, "DEPLOY: the yellow line (game intro x" + R.speed + ")"], [T_SEAT, "ALL SEATED (bar 2 head)"], [T_HIT, "BURST: T and E pop out"],
             [T_END, "intro ends"], [T_OUT, "belt carries the logo out + wipe to S04"]];
for (var m = 0; m < marks.length; m++) mk.setValueAtTime(marks[m][0], new MarkerValue(marks[m][1]));

if (!(OPT && OPT.close_after)) comp.openInViewer();
proj.save(new File(SAVE_AS));
// 結果は閉じる前に作る（閉じたあとはコンポやフッテージのオブジェクトが無効になる）
var result = { comp: comp.name, layers: comp.numLayers, duration: DUR, logo: [LOGO_L, LOGO_R, YT, LOGO_H], belt: [BELT_TOP, BELT_H],
               seat: T_SEAT, burst: T_HIT, end: T_END, out: T_OUT, logoFrames: Math.round(logoFoot.duration * FPS),
               bgFrames: Math.round(bgFoot.duration * FPS), frames: Math.round(DUR * FPS), saved: proj.file ? proj.file.fsName : null };
if (OPT && OPT.close_after) {        // AE に連番をつかませたままにしない（通しの組み立てから流すとき）
    proj.close(CloseOptions.DO_NOT_SAVE_CHANGES);
    app.newProject();
}
app.endSuppressDialogs(false);
return result;
