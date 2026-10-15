// PV ロゴ案 A の A2（ロゴが組み上がった瞬間）の 1 枚テスト：実機の背景 + Blender のロゴ + 光。
// Run: node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/logo_a/ae/build_a2.jsx
// 注意：この PC の AE 2026 は、1 回書き出すと同じ起動のうちの次の書き出しが「予期しないエラー」か空の画像になる。
// 書き出し直すときは AE を終了・起動し直してから実行する（起動しきる前に送るとスクリプトの機能が無いというダイアログが出る）。
// 背景 artifacts/pv_capture/logo_a_bg/pv_0430.png（PV 撮影をロゴ用の低いカメラで撮ったフレーム 430。撮り方は build_logo_a.py の先頭）
// ロゴ docs/pv/logo_a/render/logo_a2_rgba.png（docs/pv/logo_a/build_logo_a.py、同じカメラで描いた透過 PNG）
// ロゴの画面上の範囲は x 287〜1633・y 113〜374 px、P1 は y 482 px より下（Blender で投影して確かめた値）。
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var BG = ROOT + "artifacts/pv_capture/logo_a_bg/pv_0430.png";
var LOGO = ROOT + "docs/pv/logo_a/render/logo_a2_rgba.png";
var SAVE_AS = ROOT + "docs/pv/logo_a/ae/AIQUIZ_PV_LogoA_A2.aep";
var OUT = ROOT + "docs/pv/logo_a/render/a2_composite_[#].tif";   // この AE には PNG の出力テンプレートが無いので TIFF（PNG へは make_compare.py で変換）
var W = 1920, H = 1080, FPS = 60, DUR = 1 / FPS;
var CX = 960, CY = 243;                       // ロゴの中心
var FLASH = [945, 222];                       // 閃光の芯（Q と U の間の少し上。Blender の LGT_flash_back の位置）
var MASK_BOTTOM = 470;                         // 閃光はここから下を消す（P1 の帽子は y≈515）

app.beginUndoGroup("PV LogoA A2");
var proj = app.project;
proj.bitsPerChannel = 16;
function findComp(name) {
    for (var i = 1; i <= proj.numItems; i++) {
        var it = proj.item(i);
        if (it instanceof CompItem && it.name === name) return it;
    }
    return null;
}
function importOnce(path) {
    var f = new File(path);
    for (var i = 1; i <= proj.numItems; i++) {
        var it = proj.item(i);
        if (it instanceof FootageItem && it.file && it.file.fsName === f.fsName) { it.replace(f); return it; }
    }
    return proj.importFile(new ImportOptions(f));
}
function setProp(group, matchName, value) {
    try { group.property(matchName).setValue(value); return true; } catch (e) { return false; }
}
function addFx(layer, matchName) { return layer.property("ADBE Effect Parade").addProperty(matchName); }
function shapeLayer(comp, name, pos) {
    var L = comp.layers.addShape();
    L.name = name;
    L.property("ADBE Transform Group").property("ADBE Position").setValue(pos);
    return L;
}
function addGroup(L) {
    var g = L.property("ADBE Root Vectors Group").addProperty("ADBE Vector Group");
    return g.property("ADBE Vectors Group");
}
function addFill(gc, color, opacity) {
    var fl = gc.addProperty("ADBE Vector Graphic - Fill");
    fl.property("ADBE Vector Fill Color").setValue(color);
    if (opacity !== undefined) fl.property("ADBE Vector Fill Opacity").setValue(opacity);
}
function addStroke(gc, color, width) {
    var st = gc.addProperty("ADBE Vector Graphic - Stroke");
    st.property("ADBE Vector Stroke Color").setValue(color);
    st.property("ADBE Vector Stroke Width").setValue(width);
}
// 柔らかい光の玉：画面いっぱいの平面に、ぼかした楕円のマスク（シェイプにぼかしをかけると自分の範囲の四角で切れるため）
function ellipse(comp, name, pos, size, color, blur, opacity) {
    var L = comp.layers.addSolid(color, name, W, H, 1.0, DUR);
    var m = L.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
    var rx = size[0] / 2, ry = size[1] / 2, k = 0.5523;
    var sh = new Shape();
    sh.vertices = [[pos[0] + rx, pos[1]], [pos[0], pos[1] + ry], [pos[0] - rx, pos[1]], [pos[0], pos[1] - ry]];
    sh.inTangents = [[0, -ry * k], [rx * k, 0], [0, ry * k], [-rx * k, 0]];
    sh.outTangents = [[0, ry * k], [-rx * k, 0], [0, -ry * k], [rx * k, 0]];
    sh.closed = true;
    m.property("ADBE Mask Shape").setValue(sh);
    m.property("ADBE Mask Feather").setValue([blur * 1.6, blur * 1.6]);
    L.property("ADBE Transform Group").property("ADBE Opacity").setValue(opacity);
    L.blendingMode = BlendingMode.ADD;
    return L;
}
function ring(comp, name, pos, size, width, color, blur, opacity) {
    var L = shapeLayer(comp, name, pos);
    var gc = addGroup(L);
    gc.addProperty("ADBE Vector Shape - Ellipse").property("ADBE Vector Ellipse Size").setValue(size);
    addStroke(gc, color, width);
    if (blur) addFx(L, "ADBE Gaussian Blur 2").property(1).setValue(blur);
    L.property("ADBE Transform Group").property("ADBE Opacity").setValue(opacity);
    L.blendingMode = BlendingMode.ADD;
    return L;
}
function star(gc, pos, outer, inner, rot) {
    var s = gc.addProperty("ADBE Vector Shape - Star");
    s.property("ADBE Vector Star Type").setValue(1);
    s.property("ADBE Vector Star Points").setValue(4);
    s.property("ADBE Vector Star Outer Radius").setValue(outer);
    s.property("ADBE Vector Star Inner Radius").setValue(inner);
    s.property("ADBE Vector Star Rotation").setValue(rot || 0);
    s.property("ADBE Vector Star Position").setValue(pos);
}
function glow(layer, threshold, radius, intensity) {
    var g = addFx(layer, "ADBE Glo2");
    setProp(g, "ADBE Glo2-0002", threshold);
    setProp(g, "ADBE Glo2-0003", radius);
    setProp(g, "ADBE Glo2-0004", intensity);
    return g;
}
// 乱数（毎回同じ配置）
var seed = 20261014;
function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

// ---------------------------------------------------------------- footage
var bgFoot = importOnce(BG);
var logoFoot = importOnce(LOGO);
logoFoot.mainSource.alphaMode = AlphaMode.STRAIGHT;   // Blender の PNG はストレート

var old = findComp("PV_LogoA_A2");
if (old) old.remove();
var oldFlash = findComp("PV_LogoA_A2_flash");
if (oldFlash) oldFlash.remove();
var comp = proj.items.addComp("PV_LogoA_A2", W, H, 1.0, DUR, FPS);
comp.bgColor = [0.05, 0.08, 0.15];

// 1) 背景（実機）。少しだけ鮮やかに
var bg = comp.layers.add(bgFoot);
bg.name = "BG_godot_pv0450";
var vib = addFx(bg, "ADBE Vibrance");
try { vib.property(1).setValue(18); } catch (e) {}

// 2) 閃光・光線・衝撃波はプリコンポにまとめ、下をぼかしたマスクで切って P1 にかけない（スクリーンで重ねる）
var flash = proj.items.addComp("PV_LogoA_A2_flash", W, H, 1.0, DUR, FPS);
ellipse(flash, "FLASH_bloom", [CX, CY + 10], [1500, 520], [0.78, 0.90, 1.0], 180, 70);
ellipse(flash, "FLASH_core", FLASH, [640, 340], [1.0, 1.0, 1.0], 90, 100);
ellipse(flash, "FLASH_hot", FLASH, [220, 140], [1.0, 1.0, 1.0], 30, 100);
var rays = shapeLayer(flash, "FLASH_rays", FLASH);
var rgc = addGroup(rays);
var N = 48;
for (var r = 0; r < N; r++) {
    var a = (r + rnd() * 0.7) / N * Math.PI * 2;
    var len = 450 + rnd() * 700;
    var half = 0.006 + rnd() * 0.008;
    var p = rgc.addProperty("ADBE Vector Shape - Group");
    var sh = new Shape();
    sh.vertices = [[0, 0], [Math.cos(a - half) * len, Math.sin(a - half) * len], [Math.cos(a + half) * len, Math.sin(a + half) * len]];
    sh.closed = true;
    p.property("ADBE Vector Shape").setValue(sh);
}
addFill(rgc, [0.90, 0.97, 1.0]);
addFx(rays, "ADBE Gaussian Blur 2").property(1).setValue(6);
rays.property("ADBE Transform Group").property("ADBE Scale").setValue([100, 60]);   // 横長に（ロゴの形に合わせる）
rays.property("ADBE Transform Group").property("ADBE Opacity").setValue(38);
rays.blendingMode = BlendingMode.ADD;
// 破片が光の筋を引いて飛ぶ（中心から外へ向かう短い線）
var streaks = shapeLayer(flash, "SPARK_streaks", FLASH);
var sgc0 = addGroup(streaks);
for (var q = 0; q < 54; q++) {
    var aa = rnd() * Math.PI * 2;
    var r0 = 240 + rnd() * 720;
    var ln = 40 + rnd() * 120;
    var path = sgc0.addProperty("ADBE Vector Shape - Group");
    var sh2 = new Shape();
    sh2.vertices = [[Math.cos(aa) * r0, Math.sin(aa) * r0 * 0.62], [Math.cos(aa) * (r0 + ln), Math.sin(aa) * (r0 + ln) * 0.62]];
    sh2.closed = false;
    path.property("ADBE Vector Shape").setValue(sh2);
}
addStroke(sgc0, [1.0, 1.0, 1.0], 2.5);
glow(streaks, 20, 10, 1.0);
streaks.property("ADBE Transform Group").property("ADBE Opacity").setValue(85);
streaks.blendingMode = BlendingMode.ADD;
// 3) 衝撃波の輪（2 本。下の端が P1 の頭より上に収まる平たい輪）
ring(flash, "SHOCK_ring_outer", [CX, CY + 6], [2000, 500], 6, [0.80, 0.95, 1.0], 4, 70);
ring(flash, "SHOCK_ring_inner", [CX, CY + 4], [1450, 380], 3, [1.0, 1.0, 1.0], 2, 45);
var fl = comp.layers.add(flash);
fl.name = "FLASH (precomp)";
fl.blendingMode = BlendingMode.SCREEN;
var fm = fl.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
var fms = new Shape();
fms.vertices = [[-200, -200], [W + 200, -200], [W + 200, MASK_BOTTOM], [-200, MASK_BOTTOM]];
fms.closed = true;
fm.property("ADBE Mask Shape").setValue(fms);
fm.property("ADBE Mask Feather").setValue([0, 110]);

// 4) ロゴ：うしろに淡い光の縁（空から切り離す）→ 本体 + 光のにじみ
var halo = comp.layers.add(logoFoot);
halo.name = "LOGO_halo";
var fill = addFx(halo, "ADBE Fill");
setProp(fill, "ADBE Fill-0002", [0.75, 0.92, 1.0]);
addFx(halo, "ADBE Gaussian Blur 2").property(1).setValue(18);
halo.property("ADBE Transform Group").property("ADBE Opacity").setValue(7);
halo.blendingMode = BlendingMode.SCREEN;
var logo = comp.layers.add(logoFoot);
logo.name = "LOGO_blender";
var lvib = addFx(logo, "ADBE Vibrance");
try { lvib.property(1).setValue(0); lvib.property(2).setValue(15); } catch (e) {}
glow(logo, 86, 12, 0.18);

// 5) 観客席のカメラのフラッシュ（右のスタンド）と、ロゴのまわりのきらめき
var flashes = shapeLayer(comp, "CROWD_flashes", [0, 0]);
var fgc = addGroup(flashes);
var crowd = [[18, 668], [46, 700], [12, 728], [1490, 676], [1548, 650], [1606, 688], [1662, 642], [1720, 676], [1778, 650], [1836, 690], [1890, 660], [1640, 710], [1872, 724]];
for (var c = 0; c < crowd.length; c++) star(fgc, crowd[c], 16 + rnd() * 16, 2.2, rnd() * 20);
addFill(fgc, [1, 1, 1]);
glow(flashes, 30, 16, 0.9);
flashes.blendingMode = BlendingMode.ADD;
var spark = shapeLayer(comp, "SPARKLES", [0, 0]);
var sgc = addGroup(spark);
var sp = [[230, 90], [300, 400], [640, 60], [1250, 48], [1560, 80], [1700, 300], [1640, 420], [210, 260], [760, 420], [1180, 420], [470, 30], [1420, 410], [880, 30], [1050, 410]];
for (var s2 = 0; s2 < sp.length; s2++) star(sgc, sp[s2], 7 + rnd() * 16, 1.4, rnd() * 15);
addFill(sgc, [0.92, 0.98, 1.0]);
glow(spark, 30, 12, 0.7);
spark.blendingMode = BlendingMode.ADD;

// 6) 全体に弱い光のにじみ
var adj = comp.layers.addSolid([1, 1, 1], "ADJ_bloom", W, H, 1.0, DUR);
adj.adjustmentLayer = true;
glow(adj, 95, 40, 0.1);

app.endUndoGroup();
proj.save(new File(SAVE_AS));

// 書き出し（1 フレーム）
var rq = proj.renderQueue;
for (var j = rq.numItems; j >= 1; j--) rq.item(j).remove();
var item = rq.items.add(comp);
var om = item.outputModule(1);
var tpl = null, names = om.templates;
for (var k = 0; k < names.length && !tpl; k++) { if (/PNG/i.test(names[k])) tpl = names[k]; }
for (var k2 = 0; k2 < names.length && !tpl; k2++) { if (/TIFF/i.test(names[k2])) tpl = names[k2]; }
if (tpl) om.applyTemplate(tpl);
om.file = new File(OUT);
rq.render();
return { comp: comp.name, layers: comp.numLayers, template: tpl, status: String(item.status), saved: proj.file ? proj.file.fsName : null };
