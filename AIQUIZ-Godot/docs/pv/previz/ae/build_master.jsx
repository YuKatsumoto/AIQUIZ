// PV の通し（TESTOPIA、絵コンテ v1.2 の S01〜S23、182 拍 = 85.3 秒）：計画 docs/pv/previz/v6/master_plan.json
// （tools/pv/pv_master.py plan が書く）から、新しいプロジェクトにコンポ TESTOPIA_PV_master を組んで TESTOPIA_PV_master.aep に保存する。
//   python tools/pv/pv_master.py ae      （= node tools/title_logo_ae/ae_run.mjs docs/pv/previz/ae/build_master.jsx）
// - S01〜S05 は AIQUIZ_PV_S01_S07.aep の PV_S01_S07、S23 は TESTOPIA_PV_S23_S24.aep の PV_S23_S24 を読み込んで使う（元のファイルは変えない）。
//   PV_S01_S07 は S01〜S03 だけ使う。中の S04〜S07（artifacts/pv_capture/s04_s05_frames・s06_s07_frames）は通しでテイクから組み直すので、
//   読み込んだらすぐ外す（AE が撮り直し中の連番をつかまないように）。
// - S03 → S04 と S05 → S06 のワイプ（黄色い斜めの帯と白い先端）：右から覆うのは PV_S03_T の WIPE_TO_S04、左へ抜けるのは
//   build_s04_s07.jsx の S04_WIPE_OUT と同じ形・色・動き。
// - 撮影の連番・仮置きの画像・S18 の録画は計画のとおりに置く。テロップ・S07 の教科名・シャッターの光・「仮」の札も計画から。
// - 音（PV_full_audio.wav）は確認用に一番下に置くだけ（書き出しの音は pv_master.py が ffmpeg でつける）。
// - 開いているプロジェクトに保存していない変更があれば何もしない（他人の作業を消さない）。保存したら閉じて、前に開いていた
//   プロジェクトを開き直す（無題だったなら新しい空のプロジェクト）。AE がほかのレーンの連番をつかんだままにしないため。
// - このプロジェクトは毎回作り直すので、手で直さない（直すのは計画を作る pv_master.py とこのファイル）。
// 注意：ExtendScript は a ? b : c ? d : e を (a ? b : c) ? d : e と読むので、入れ子の三項演算子には括弧を付ける。
var ROOT = "G:/AIQUIZ-Main/AIQUIZ-Godot/";
var PLAN = ROOT + "docs/pv/previz/v6/master_plan.json";
function readText(p) { var f = new File(p); f.encoding = "UTF-8"; if (!f.open("r")) throw new Error("cannot open " + p); var s = f.read(); f.close(); return s; }
function norm(p) { return String(p).replace(/\\/g, "/").toLowerCase(); }
eval(readText(ROOT + "docs/pv/previz/ae/pv_telop.jsxinc"));
var P = JSON.parse(readText(PLAN));
var FPS = P.fps, W = P.width, H = P.height;
var SAVE_AS = new File(ROOT + P.aep);
function T(f) { return f / FPS; }

// --- いま開いているプロジェクト
var before = app.project;
var prevPath = before && before.file ? before.file.fsName : null;
var isMaster = prevPath && norm(prevPath) === norm(SAVE_AS.fsName);
if (before && before.dirty && before.numItems > 0) {
    return { error: "AE で開いているプロジェクトに保存していない変更がある（" + (prevPath || "無題") + "）。保存するか閉じてから流し直す" };
}

app.beginSuppressDialogs();
var proj = app.newProject();
var missing = [], removed = [];

function folder(name) {
    for (var i = 1; i <= proj.numItems; i++) if (proj.item(i) instanceof FolderItem && proj.item(i).name === name) return proj.item(i);
    return proj.items.addFolder(name);
}
function itemIds() { var ids = {}; for (var i = 1; i <= proj.numItems; i++) ids[proj.item(i).id] = true; return ids; }

// --- 撮影済みのプロジェクトを読み込む（読み込む前後のアイテムの差で、その .aep から来たものを見分ける）
var aeps = {};
function aepComp(rel, compName) {
    if (!aeps[rel]) {
        var f = new File(ROOT + rel);
        if (!f.exists) throw new Error("missing " + rel);
        var seen = itemIds();
        var io = new ImportOptions(f);
        io.importAs = ImportAsType.PROJECT;
        proj.importFile(io);
        aeps[rel] = [];
        for (var j = proj.numItems; j >= 1; j--) {
            var it = proj.item(j);
            if (seen[it.id]) continue;
            // 旧 S04〜S07 の連番は使わない（撮り直して上書きされる。AE につかませない）
            if (it instanceof FootageItem && it.mainSource instanceof FileSource && it.mainSource.file &&
                /\/(s04_s05|s06_s07)_frames\//.test(norm(it.mainSource.file.fsName))) {
                removed.push(it.name);
                it.remove();
                continue;
            }
            aeps[rel].push(it);
        }
    }
    for (var i = 0; i < aeps[rel].length; i++) {
        var c = aeps[rel][i];
        if (c instanceof CompItem && c.name === compName) return c;
    }
    throw new Error(compName + " not found in " + rel);
}

// --- 連番・画像・動画
var feet = {};
function footage(rel, seq, bin) {
    var key = (seq ? "seq:" : "file:") + rel;
    if (feet[key]) return feet[key];
    var f = new File(ROOT + rel);
    if (!f.exists) { missing.push(rel); return null; }
    var io = new ImportOptions(f);
    if (seq) io.sequence = true;
    var foot = proj.importFile(io);
    if (seq) foot.mainSource.conformFrameRate = FPS;
    foot.parentFolder = folder(bin);
    feet[key] = foot;
    return foot;
}

var comp = null;
try {
comp = proj.items.addComp(P.comp, W, H, 1.0, T(P.frames), FPS);
comp.bgColor = [0.05, 0.08, 0.15];
comp.motionBlur = true;                 // ワイプの帯だけ（ほかのレイヤーはモーションブラーの切り替えを入れない）
comp.shutterAngle = 180;
var L45 = JSON.parse(readText(ROOT + "tools/title_logo_ae/layout.json"));
var YELLOW = [L45.belt.bar_color[0], L45.belt.bar_color[1], L45.belt.bar_color[2]];

function cover(l, src, zoom) {
    var s = Math.max(W / src.width, H / src.height) * 100;
    var sc = l.property("ADBE Transform Group").property("ADBE Scale");
    if (zoom) {
        sc.setValueAtTime(l.inPoint, [s * zoom[0] / 100, s * zoom[0] / 100]);
        sc.setValueAtTime(l.outPoint, [s * zoom[1] / 100, s * zoom[1] / 100]);
        for (var k = 1; k <= sc.numKeys; k++) sc.setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR);
    } else if (Math.abs(s - 100) > 0.01) {
        sc.setValue([s, s]);
    }
}

// テイクの一部（crop：テイクの画素 [x0, y0, x1, y1]）を、画面の dest（[x0, y0, x1, y1]）へ置く（S20 の左右に分けた画面）。
// 縦横は同じ倍率（crop と dest は同じ縦横比にしておく）。crop の外はマスクで切る
function cropTo(l, crop, dest) {
    var k = (dest[2] - dest[0]) / (crop[2] - crop[0]) * 100;
    var lt = l.property("ADBE Transform Group");
    lt.property("ADBE Anchor Point").setValue([(crop[0] + crop[2]) / 2, (crop[1] + crop[3]) / 2]);
    lt.property("ADBE Position").setValue([(dest[0] + dest[2]) / 2, (dest[1] + dest[3]) / 2]);
    lt.property("ADBE Scale").setValue([k, k]);
    var m = l.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
    var sh = new Shape();
    sh.vertices = [[crop[0], crop[1]], [crop[2], crop[1]], [crop[2], crop[3]], [crop[0], crop[3]]];
    sh.closed = true;
    m.property("ADBE Mask Shape").setValue(sh);
}

// S01・S02 の画面の揺れ（計画の shakes：[{t 秒, amp 横の振れ幅 px, dur 収まるまでの秒}]）。乱数を使わない決まった揺れ：
// 減衰（(1 − u)²）する 2 つのサイン波の和。縦は横の 0.75 倍。端が見えないよう、その瞬間の振れ幅に合わせて拡大する。
// add() を使うのは、AE の JavaScript の式では配列の + が文字列のつなぎになるため。
function shakeExpr(kind) {
    var ev = [];
    for (var i = 0; i < (P.shakes || []).length; i++) {
        var e = P.shakes[i];
        ev.push("[" + e.t + "," + e.amp + "," + e.dur + "," + (i * 1.7).toFixed(2) + "]");
    }
    // 改行は fromCharCode で（スクリプトを AE へ送る経路で、文字列の中の「\」＋「n」が本物の改行に化けるため）
    var lines = [
        "var ev = [" + ev.join(",") + "];",
        "var ox = 0, oy = 0, m = 0;",
        "for (var i = 0; i < ev.length; i++) {",
        "  var tt = time - ev[i][0], u = tt / ev[i][2];",
        "  if (u < 0 || u >= 1) continue;",
        "  var a = ev[i][1] * (1 - u) * (1 - u), ph = ev[i][3];",
        "  ox += a * (0.65 * Math.sin(2 * Math.PI * 12 * tt + 1.2 + ph) + 0.35 * Math.sin(2 * Math.PI * 19 * tt + 0.4 + ph));",
        "  oy += 0.75 * a * (0.65 * Math.sin(2 * Math.PI * 14 * tt + 2.1 + ph) + 0.35 * Math.sin(2 * Math.PI * 8 * tt + 0.9 + ph));",
        "  m += a;",
        "}"
    ];
    if (kind === "position") lines.push("add(value, [ox, oy]);");
    else lines.push("var k = 1 + 1.5 * m / 1080 * 1.06;", "[value[0] * k, value[1] * k];");
    return lines.join(String.fromCharCode(10));
}

var nVideo = 0, exprErrors = [];
for (var i = 0; i < P.layers.length; i++) {
    var L = P.layers[i], l = null, src = null;
    if (L.kind === "comp") {
        src = aepComp(L.aep, L.comp);
        l = comp.layers.add(src);
        l.startTime = T(L.start - L.src_in);
    } else if (L.kind === "seq") {
        src = footage(L.first, true, "撮影（連番）");
        if (!src) continue;
        l = comp.layers.add(src);
        l.startTime = T(L.start - L.src_in);
    } else if (L.kind === "still") {
        src = footage(L.file, false, L.placeholder ? "仮（絵コンテの画像）" : "撮影（止めるコマ）");
        if (!src) continue;
        l = comp.layers.add(src);
        l.startTime = T(L.start);
    } else if (L.kind === "video") {
        src = footage(L.file, false, "録画");
        if (!src) continue;
        l = comp.layers.add(src);
        l.startTime = T(L.start) - L.src_in_sec;
        if (l.hasAudio) l.audioEnabled = false;
    } else {
        continue;
    }
    l.name = L.name;
    if (L.shake && P.shakes && P.shakes.length) {
        var tg = l.property("ADBE Transform Group");
        tg.property("ADBE Position").expression = shakeExpr("position");
        tg.property("ADBE Scale").expression = shakeExpr("scale");
        var pe = tg.property("ADBE Position").expressionError, se = tg.property("ADBE Scale").expressionError;
        if (pe || se) exprErrors.push(L.name + ": " + (pe || se));
    }
    l.inPoint = T(L.start);
    l.outPoint = T(L.start + L.frames);
    if (L.crop && L.dest) cropTo(l, L.crop, L.dest);
    else if (L.kind !== "comp") cover(l, src, L.scale);
    if (L.anchor) {
        var lt = l.property("ADBE Transform Group");
        lt.property("ADBE Anchor Point").setValue(L.anchor);
        lt.property("ADBE Position").setValue(L.anchor);
    }
    if (L.scale_keys) {                 // [[フレーム, 倍率, 着地をゆるめるか]]（S04：ゲーム開始まで設定パネルへ寄る）
        var sk = l.property("ADBE Transform Group").property("ADBE Scale");
        for (var q = 0; q < L.scale_keys.length; q++) {
            var kq = L.scale_keys[q];
            sk.setValueAtTime(T(kq[0]), [kq[1], kq[1]]);
            if (kq[2]) {
                var ki = sk.nearestKeyIndex(T(kq[0])), kd = sk.keyInTemporalEase(ki).length, ein = [], eout = [];
                for (var dd = 0; dd < kd; dd++) { ein.push(new KeyframeEase(0, 60)); eout.push(new KeyframeEase(0, 33.33)); }
                sk.setTemporalEaseAtKey(ki, ein, eout);
            }
        }
    }
    nVideo++;
}

// --- 上に重ねるもの（下から：シャッターの光 → 教科名 → テロップ → 仮の札）
function flash(o) {
    var s = comp.layers.addSolid([1, 1, 1], "S07_FLASH " + o.t, W, H, 1.0, 0.2);
    s.startTime = T(o.t);
    s.inPoint = T(o.t);
    s.outPoint = T(o.t) + 0.2;
    var op = s.property("ADBE Transform Group").property("ADBE Opacity");
    op.setValueAtTime(T(o.t), o.opacity);
    op.setValueAtTime(T(o.t) + 0.13, 0);
    s.blendingMode = BlendingMode.ADD;
}
function placeholderLabel(o) {
    var size = TEL.cq(1.45);
    var tl = telTextLayer(comp, "PH " + o.text, "仮　" + o.text, size, TEL.WHITE, 0);
    var b = telAnchor(tl, 1, 0, T(o.t0));
    var padX = TEL.cq(0.9), padY = TEL.cq(0.45);
    var x = W - TEL.cq(1.6), y = TEL.cq(1.1);
    tl.property("ADBE Transform Group").property("ADBE Position").setValue([x - padX, y + padY]);
    var plate = comp.layers.addShape();
    plate.name = "PH " + o.text + " plate";
    var g = plate.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group").property("ADBE Vectors Group");
    var pw = b.width + padX * 2, ph = b.height + padY * 2;
    var rc = g.addProperty("ADBE Vector Shape - Rect");
    rc.property("ADBE Vector Rect Size").setValue([pw, ph]);
    rc.property("ADBE Vector Rect Position").setValue([-pw / 2, ph / 2]);
    rc.property("ADBE Vector Rect Roundness").setValue(TEL.cq(0.35));
    g.addProperty("ADBE Vector Graphic - Fill").property("ADBE Vector Fill Color").setValue([0.82, 0.12, 0.16, 1]);
    plate.property("ADBE Transform Group").property("ADBE Anchor Point").setValue([0, 0]);
    plate.property("ADBE Transform Group").property("ADBE Position").setValue([x, y]);
    plate.property("ADBE Transform Group").property("ADBE Opacity").setValue(88);
    plate.moveAfter(tl);
    tl.inPoint = plate.inPoint = T(o.t0);
    tl.outPoint = plate.outPoint = T(o.t1);
}
// ワイプの帯（PV_S03_T の WIPE_TO_S04 と同じ形）。左上を原点に、x を動かす
function wipeBand(name) {
    var w = comp.layers.addShape();
    w.name = name;
    w.property("ADBE Transform Group").property("ADBE Anchor Point").setValue([0, 0]);
    var root = w.property("ADBE Root Vectors Group");
    function band(nm, verts, rgb) {
        var g = root.addProperty("ADBE Vector Group");
        g.name = nm;
        var c = g.property("ADBE Vectors Group");
        var sh = new Shape();
        sh.vertices = verts;
        sh.closed = true;
        c.addProperty("ADBE Vector Shape - Group").property("ADBE Vector Shape").setValue(sh);
        c.addProperty("ADBE Vector Graphic - Fill").property("ADBE Vector Fill Color").setValue([rgb[0], rgb[1], rgb[2], 1]);
    }
    band("Edge", [[-70, -100], [-10, -100], [-410, H + 100], [-470, H + 100]], [1, 1, 1]);
    band("Band", [[0, -100], [2600, -100], [2200, H + 100], [-400, H + 100]], YELLOW);
    w.motionBlur = true;
    return w;
}
// 仕切りの線（S20 の左右の境目）：帯と同じ黄色の縦の長方形。x は線の真ん中
function bar(o) {
    var s = comp.layers.addShape();
    s.name = o.name || "BAR";
    var g = s.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group").property("ADBE Vectors Group");
    var rc = g.addProperty("ADBE Vector Shape - Rect");
    rc.property("ADBE Vector Rect Size").setValue([o.w, o.h || H]);
    rc.property("ADBE Vector Rect Position").setValue([0, 0]);
    g.addProperty("ADBE Vector Graphic - Fill").property("ADBE Vector Fill Color").setValue([YELLOW[0], YELLOW[1], YELLOW[2], 1]);
    s.property("ADBE Transform Group").property("ADBE Anchor Point").setValue([0, 0]);
    s.property("ADBE Transform Group").property("ADBE Position").setValue([o.x, o.y || H / 2]);
    s.inPoint = T(o.t0);
    s.outPoint = T(o.t1);
}
// 右から覆う：止まった状態からゆるく出て、最後は 5200 px/秒で全面を覆う（WIPE_TO_S04）
function wipeIn(o) {
    var w = wipeBand(o.name || "WIPE_IN");
    var wp = w.property("ADBE Transform Group").property("ADBE Position");
    wp.setValueAtTime(T(o.t0), [W + 520, 0]);
    wp.setValueAtTime(T(o.t1), [-120, 0]);
    wp.setTemporalEaseAtKey(1, [new KeyframeEase(0, 33.33)], [new KeyframeEase(0, 60)]);
    wp.setTemporalEaseAtKey(2, [new KeyframeEase(5200, 40)], [new KeyframeEase(0, 33.33)]);
    w.inPoint = T(o.t0);
    w.outPoint = T(o.t1);
}
// 左へ抜ける：覆った帯がそのまま 0.32 秒で左へ抜けて次のカットを見せる（S04_WIPE_OUT）
function wipeOut(o) {
    var w = wipeBand(o.name || "WIPE_OUT");
    var wp = w.property("ADBE Transform Group").property("ADBE Position");
    wp.setValueAtTime(T(o.t), [-120, 0]);
    wp.setValueAtTime(T(o.t) + 0.32, [-3300, 0]);
    wp.setTemporalEaseAtKey(1, [new KeyframeEase(0, 33.33)], [new KeyframeEase(5200, 40)]);
    wp.setTemporalEaseAtKey(2, [new KeyframeEase(14000, 40)], [new KeyframeEase(0, 33.33)]);
    w.inPoint = T(o.t);
    w.outPoint = T(o.t) + 0.34;
}
var order = ["flash", "bar", "tag", "telop", "label", "wipe_in", "wipe_out"], nOver = 0, colored = [];
for (var k = 0; k < order.length; k++) {
    for (var j = 0; j < P.overlays.length; j++) {
        var o = P.overlays[j];
        if (o.kind !== order[k]) continue;
        if (o.kind === "flash") flash(o);
        else if (o.kind === "bar") bar(o);
        else if (o.kind === "tag") telSubjectTag(comp, o.text, T(o.t0), T(o.t1), o.x);
        else if (o.kind === "label") placeholderLabel(o);
        else if (o.kind === "wipe_in") wipeIn(o);
        else if (o.kind === "wipe_out") wipeOut(o);
        else {
            var opt = { pos: o.pos };
            if (o.bottom) opt.bottom = o.bottom;
            if (o.sub) { opt.sub = o.sub; if (o.subFrom !== null && o.subFrom !== undefined) opt.subFrom = T(o.subFrom); }
            var tl = telop(comp, o.label, o.text, T(o.t0), T(o.t1), opt);
            if (/\[/.test(o.text)) colored.push(o.label + ":" + tl[0].__colored);
        }
        nOver++;
    }
}

// --- 音（確認用）とマーカー
var audioFile = new File(ROOT + P.audio_file);
if (audioFile.exists) {
    var af = proj.importFile(new ImportOptions(audioFile));
    af.parentFolder = folder("音");
    var al = comp.layers.add(af);
    al.name = "音（確認用。書き出しの音は pv_master.py の mux）";
    al.startTime = 0;
    al.moveToEnd();
} else {
    missing.push(P.audio_file);
}
for (var m = 0; m < P.markers.length; m++) comp.markerProperty.setValueAtTime(T(P.markers[m][0]), new MarkerValue(P.markers[m][1]));
comp.workAreaStart = 0;
comp.workAreaDuration = comp.duration;

} catch (err) {
    // 作りかけ（このスクリプトが作った無題のプロジェクト）は保存せずに閉じ、前の状態に戻す
    var msg = String(err) + (err.line ? " (line " + err.line + ")" : "");
    proj.close(CloseOptions.DO_NOT_SAVE_CHANGES);
    if (prevPath && !isMaster && new File(prevPath).exists) app.open(new File(prevPath)); else app.newProject();
    app.endSuppressDialogs(false);
    return { error: msg };
}

proj.save(SAVE_AS);
var result = { comp: comp.name, frames: Math.round(comp.duration * FPS), layers: comp.numLayers, video: nVideo, overlays: nOver,
               colored: colored, removed: removed, missing: missing, exprErrors: exprErrors, saved: proj.file.fsName };
// 閉じて、前の状態に戻す
if (prevPath && !isMaster && new File(prevPath).exists) {
    app.open(new File(prevPath));
    result.reopened = prevPath;
} else {
    app.newProject();
    result.reopened = "（新しい空のプロジェクト）";
}
app.endSuppressDialogs(false);
return result;
