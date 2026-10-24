// PV S23（ロゴとキャッチコピー、3 小節）＋ S24（作品情報、2 小節）: builds comp PV_S23_S24 in a NEW After Effects project.
// Run: node tools/title_logo_ae/ae_run.mjs docs/pv/previz/ae/build_s23_s24.jsx
// The open project must be saved (the script refuses to close a project with unsaved changes). Saved as TESTOPIA_PV_S23_S24.aep.
//
// Background: the main menu's harbour with every UI hidden (tests/pv_capture/pv_s23_runtime.gd, take s23, merged to
// artifacts/pv_capture/s23_frames). The logo is the game's own title intro rendered by Godot to transparent PNGs:
//   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/pv_capture/pv_logo_capture.gd
//       -- tag=s23 zoom=2.6 top=359 t0=0.35 speed=1.6 frames=563
// 128 BPM, 1 beat = 0.46875 s.
//   S23 beat 1     the background dims to 45 %, the yellow line deploys (the game's intro at 1.6x)
//   S23 beat 7     BURST: the door block bursts, T and E pop out (white flash, zoom punch)
//   S24 beat 1     the background dims to 72 % and blurs; the logo moves up and shrinks
// No line under the logo (2026-10-19: the catch copy was dropped from S23-S24; set CATCH to bring it back)
//   S24 +0.35 s    the work information and the credits rise in, one line after another; held to the end
var ROOT = "G:/AIQUIZ-Main/AIQUIZ-Godot/";
var BG_FIRST = ROOT + "artifacts/pv_capture/s23_frames/pv_0001.jpg";
var LOGO_DIR = ROOT + "artifacts/pv_capture/logo_s23/";
var SAVE_AS = ROOT + "docs/pv/previz/ae/TESTOPIA_PV_S23_S24.aep";
var W = 1920, H = 1080, FPS = 60, BEAT = 60 / 128;
var T_S24 = 12 * BEAT, DUR = 20 * BEAT;                              // 5.625 s + 3.75 s
var CATCH = "";                                                      // e.g. "AIが出す。[キミが走る。]" (empty = none)
var INFO = ["Windows ／ 小学生向け 3Dクイズランナー", "ゲームクリエイター甲子園2026 応募作品"];
var CREDIT = "効果音：OtoLogic（CC BY 4.0）ほか ／ 3Dモデル：Poly Pizza（CC BY 3.0）ほか ／ 詳しくは作品説明へ";

function readText(path) {
    var f = new File(path);
    f.encoding = "UTF-8";
    if (!f.open("r")) throw new Error("cannot open " + path);
    var s = f.read();
    f.close();
    return s;
}
eval(readText(ROOT + "docs/pv/previz/ae/pv_telop.jsxinc"));
var R = JSON.parse(readText(LOGO_DIR + "report.json"));
var HR = R.holder_rect;                                              // [x, y, w, h] of the letters on screen
var LOGO_CX = HR[0] + HR[2] / 2, LOGO_CY = HR[1] + HR[3] / 2;
var BELT_BOTTOM = HR[1] + (R.belt_rect_logical[1] + R.belt_rect_logical[3]) * R.zoom;
function mt(name) { return (R.markers[name].pv_frame - 1) / FPS; }
var T_HIT = mt("BURST"), T_CATCH = 8 * BEAT;

function ease(e, dims) {
    var a = [];
    var sp = e ? e[0] : 0, inf = e ? e[1] : 33.33;
    for (var i = 0; i < dims; i++) a.push(new KeyframeEase(sp, inf));
    return a;
}
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
// text centred on (x, y) (the box's centre), rising in at t0 like the telops (0.2 s, from 34 px lower)
function centeredText(comp, name, marked, size, stroke, x, y, t0) {
    var l = telTextLayer(comp, name, marked, size, TEL.WHITE, stroke);
    var doc = l.property("ADBE Text Properties").property("ADBE Text Document").value;
    doc.justification = ParagraphJustification.CENTER_JUSTIFY;
    l.property("ADBE Text Properties").property("ADBE Text Document").setValue(doc);
    if (stroke > 0) telShadow(l, TEL.cq(0.35), 0.4);
    telAnchor(l, 0.5, 0.5, t0 + 0.5);
    var p = tr(l).property("ADBE Position"), o = tr(l).property("ADBE Opacity");
    key(p, t0, [x, y + TEL.RISE], null, [0, 20]);
    key(p, t0 + TEL.IN, [x, y], [0, 75], null);
    key(o, t0, 0, null, null);
    key(o, t0 + TEL.IN * 0.6, 100, null, null);
    l.inPoint = t0;
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
logoFoot.mainSource.alphaMode = AlphaMode.PREMULTIPLIED;
logoFoot.mainSource.premulColor = [0, 0, 0];

var comp = proj.items.addComp("PV_S23_S24", W, H, 1.0, DUR, FPS);
comp.bgColor = [0.05, 0.08, 0.15];
comp.motionBlur = true;
comp.shutterAngle = 180;

// 1) background: the menu's harbour (no UI); dims under the logo, darker and blurred for the information
var bg = comp.layers.add(bgFoot);
bg.name = "BG_menu (take s23)";
bg.startTime = 0;
bg.inPoint = 0; bg.outPoint = DUR;
var blur = fx(bg, "ADBE Gaussian Blur 2");
var blurR = blur.property("ADBE Gaussian Blur 2-0001");
key(blurR, T_S24, 0, null, [0, 33.33]);
key(blurR, T_S24 + 0.45, 18, [0, 70], null);
setP(blur, "ADBE Gaussian Blur 2-0003", 1);              // repeat edge pixels
var dim = comp.layers.addSolid([0.02, 0.04, 0.10], "DIM", W, H, 1.0, DUR);
var dop = tr(dim).property("ADBE Opacity");
key(dop, 0, 0, null, [0, 33.33]);
key(dop, 0.4, 45, [0, 70], null);
key(dop, T_S24, 45, null, [0, 33.33]);
key(dop, T_S24 + 0.45, 72, [0, 70], null);

// 2) the logo (the game's intro); moves up and shrinks for the information
var logo = comp.layers.add(logoFoot);
logo.name = "LOGO_TESTOPIA (Godot)";
logo.inPoint = 0; logo.outPoint = DUR;
tr(logo).property("ADBE Anchor Point").setValue([LOGO_CX, LOGO_CY]);
var LOGO_UP_Y = 285, LOGO_SMALL = 74;
var lp = tr(logo).property("ADBE Position"), ls = tr(logo).property("ADBE Scale");
key(lp, T_S24, [LOGO_CX, LOGO_CY], null, [0, 45]);
key(lp, T_S24 + 0.5, [LOGO_CX, LOGO_UP_Y], [0, 80], null);
key(ls, T_S24, [100, 100], null, [0, 45]);
key(ls, T_S24 + 0.5, [LOGO_SMALL, LOGO_SMALL], [0, 80], null);

// 3) camera: zoom punch at the burst (everything below)
var cam = comp.layers.addSolid([1, 1, 1], "CAM_punch (adjustment)", W, H, 1.0, DUR);
cam.adjustmentLayer = true;
var xf = fx(cam, "ADBE Geometry2");
setP(xf, "ADBE Geometry2-0001", [LOGO_CX, LOGO_CY]);
setP(xf, "ADBE Geometry2-0002", [LOGO_CX, LOGO_CY]);
var xfs = xf.property("ADBE Geometry2-0003");
key(xfs, T_HIT, 100, null, [0, 20]);
key(xfs, T_HIT + 3 / FPS, 104, [0, 50], [0, 50]);
key(xfs, T_HIT + 0.24, 100, [0, 60], null);
setP(xf, "ADBE Geometry2-0009", 0);
setP(xf, "ADBE Geometry2-0010", 180);
cam.outPoint = T_S24;

var flash = comp.layers.addSolid([1, 1, 1], "BURST_FLASH", W, H, 1.0, DUR);
flash.blendingMode = BlendingMode.ADD;
var fo = tr(flash).property("ADBE Opacity");
key(fo, T_HIT - 1 / FPS, 0, null, null);
key(fo, T_HIT, 30, null, [0, 20]);
key(fo, T_HIT + 0.2, 0, [0, 70], null);
flash.inPoint = T_HIT - 1 / FPS; flash.outPoint = T_HIT + 0.21;

// 4) the catch copy under the logo; follows the logo up
var CATCH_Y = Math.round(H * 0.68);
var catchL = null;
if (CATCH !== "") {
    catchL = centeredText(comp, "CATCH", CATCH, TEL.cq(4.8), TEL.cq(0.55) * 2, W / 2, CATCH_Y, T_CATCH);
    var CATCH_UP_Y = LOGO_UP_Y + (BELT_BOTTOM - LOGO_CY) * LOGO_SMALL / 100 + 78;
    var cp = tr(catchL).property("ADBE Position"), cs = tr(catchL).property("ADBE Scale");
    key(cp, T_S24, [W / 2, CATCH_Y], null, [0, 45]);
    key(cp, T_S24 + 0.5, [W / 2, CATCH_UP_Y], [0, 80], null);
    key(cs, T_S24, [100, 100], null, [0, 45]);
    key(cs, T_S24 + 0.5, [78, 78], [0, 80], null);
}

// 5) S24: the work information and the credits
var infoLayers = [];
var y0 = Math.round(H * 0.52);
for (var i = 0; i < INFO.length; i++) {
    infoLayers.push(centeredText(comp, "INFO_" + (i + 1), INFO[i], TEL.cq(2.4), TEL.cq(0.3) * 2, W / 2, y0 + i * TEL.cq(4.0), T_S24 + 0.35 + i * 0.15));
}
var credit = centeredText(comp, "CREDIT", CREDIT, TEL.cq(1.15), 0, W / 2, Math.round(H * 0.91), T_S24 + 0.35 + INFO.length * 0.15);
var co = tr(credit).property("ADBE Opacity");
co.setValueAtKey(co.numKeys, 80);

// layer order (top to bottom): flash, credit, info, catch, camera, logo, dim, background
flash.moveToBeginning();
credit.moveAfter(flash);
var last = credit;
for (var k = infoLayers.length - 1; k >= 0; k--) { infoLayers[k].moveAfter(last); last = infoLayers[k]; }
if (catchL) { catchL.moveAfter(last); last = catchL; }
cam.moveAfter(last);
logo.moveAfter(cam);
dim.moveAfter(logo);
bg.moveToEnd();

var mk = comp.markerProperty;
var marks = [[0, "S23: logo (game intro x" + R.speed + ")"], [T_HIT, "BURST"],
             [T_S24, "S24: work information"]];
for (var m = 0; m < marks.length; m++) mk.setValueAtTime(marks[m][0], new MarkerValue(marks[m][1]));

comp.openInViewer();
proj.save(new File(SAVE_AS));
app.endSuppressDialogs(false);
return { comp: comp.name, layers: comp.numLayers, duration: DUR, burst: T_HIT, catchAt: T_CATCH, s24: T_S24,
         catchColored: catchL ? catchL.__colored : null, logoFrames: Math.round(logoFoot.duration * FPS), bgFrames: Math.round(bgFoot.duration * FPS),
         saved: proj.file ? proj.file.fsName : null };
