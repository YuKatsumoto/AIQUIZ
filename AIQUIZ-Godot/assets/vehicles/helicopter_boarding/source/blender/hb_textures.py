"""デカールのアトラス（source/textures/hb_decals.png、2048²、RGBA、sRGB の値・ストレートのアルファ）を numpy で描く。

Decal / DecalNumber / ScreenGlow の 3 つの材質が 1 枚を使う。GLB には 1 枚だけ入る。
  外（上半分 y 1024〜2047）：ロゴ（濃紺に白い縁・白だけ）、機体番号（AQ-01 / AQ-02、上下に 256 px ずつ）、ハテナの紋章、
                            黄黒の縞（つなげて使うタイル）、細い線の帯
  コックピット（下半分 y 0〜1023）：多機能画面 4 枚・計器の文字盤 4 つ・無線の窓 3 つ・警告灯の列・不透明のマス・透明のマス
外の領域は 2 のべき乗にそろえたマスの中に置き、まわりに 32 px 以上の透明なすき間をとる（遠くで縮小しても隣がにじまない）。
つなげて使うタイル（黄黒・細い線）は、マスの横いっぱいに同じ模様を続ける（縮小してもつなぎ目が出ない）。

画像は毎回作り直してファイルに書き、.blend に詰める（pack）。材質へは Image をそのまま渡す（パスからは読まない）。
文字は Blender の文字のカーブ（resources/fonts/NotoSansJP-Bold.otf）をメッシュにして、輪郭の辺から偶奇で塗る。
ロゴは assets/aiquiz_menu_stage/led/led_logo.png のアルファ。紋章の形は aiquiz_mascot の build_hatena.py の数値を写した（読み込まない）。
座標は Blender の画像の向き（左下が原点）。UV = px / 2048。
"""
from __future__ import annotations

import hashlib
import json
import math

import bpy
import numpy as np

import hb_common as K

SIZE = 2048
IMAGE_NAME = "hb_decals"
PNG = K.TEXTURES / "hb_decals.png"
REGIONS_JSON = K.TEXTURES / "hb_decals_regions.json"
LOGO_PNG = K.ROOT / "assets" / "aiquiz_menu_stage" / "led" / "led_logo.png"
FONT_PATH = K.ROOT / "resources" / "fonts" / "NotoSansJP-Bold.otf"
NUMBERS = ["AQ-01", "AQ-02"]
GUTTER = 32          # マスの内側の透明なふち（隣のマスの中身まで 64 px 以上）
BLEED = 8            # 透明な画素へ色を広げる幅

# マス（x, y, 幅, 高さ）。中身の四角（REGIONS）は build_atlas が描きながら決める
CELLS = {
    "LOGO_KEY": (0, 1536, 1024, 512),
    "LOGO_MASK": (0, 1024, 1024, 512),
    "NUM_0": (1024, 1792, 512, 256),
    "NUM_1": (1024, 1536, 512, 256),
    "EMBLEM": (1536, 1536, 512, 512),
    "HAZARD": (1024, 1280, 512, 256),
    "PIN": (1536, 1408, 256, 128),
    "MFD_0": (0, 768, 256, 256), "MFD_1": (256, 768, 256, 256), "MFD_2": (512, 768, 256, 256), "MFD_3": (768, 768, 256, 256),
    "DIAL_0": (0, 640, 128, 128), "DIAL_1": (128, 640, 128, 128), "DIAL_2": (256, 640, 128, 128), "DIAL_3": (384, 640, 128, 128),
    "RADIO_0": (0, 576, 256, 64), "RADIO_1": (256, 576, 256, 64), "RADIO_2": (512, 576, 256, 64),
    "ANNUN": (768, 576, 256, 64),
    "UI_SOLID": (1024, 960, 64, 64),
    "TRANSPARENT": (1088, 960, 64, 64),
}
REGIONS: dict[str, tuple] = {}     # 名前 → 中身の四角 (x, y, 幅, 高さ)（px、左下が原点）
INFO: dict = {}                    # 使った字体・ロゴの縦横比など（ビルドのレポートへ）


def _rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


NAVY = _rgb(K.NAVY_HEX)
WHITE = _rgb("#F4F3EE")
HATENA_WHITE = _rgb("#F7F4ED")
SKY = _rgb("#33A6E6")
ORANGE = _rgb("#FFAD3F")
EYE = _rgb("#1C1D24")
MOUTH = _rgb("#5A2A22")
YELLOW = _rgb("#F2C230")
BLACK = _rgb("#22252A")
SCREEN_BG = _rgb("#0A1626")
CYAN = _rgb("#5ED8F2")
GREEN = _rgb("#4CE08A")
AMBER = _rgb("#F2B33D")
RED = _rgb("#E8483C")
MAGENTA = _rgb("#E05CD8")
SKY_SCREEN = _rgb("#2E76BA")
GROUND_SCREEN = _rgb("#7A5230")


# ---------------------------------------------------------------- 描く道具（buf は (高さ, 幅, 4) の float32。行 0 が下）

def _grid(w, h):
    """画素の中心の座標（左下が (0.5, 0.5)）。"""
    x = np.arange(w, dtype=np.float32) + 0.5
    y = np.arange(h, dtype=np.float32) + 0.5
    return np.meshgrid(x, y)


def _cov(d, aa=1.0):
    """符号付きの距離（px、内側が負）→ 覆う割合。"""
    return np.clip(0.5 - d / aa, 0.0, 1.0)


def _over(view, rgb, a):
    """ストレートのアルファで、view（buf の一部）の上へ色 rgb を割合 a で重ねる。"""
    a = a.astype(np.float32)
    da = view[..., 3]
    oa = a + da * (1.0 - a)
    safe = np.where(oa > 1e-6, oa, 1.0)
    for c in range(3):
        col = rgb[c] if np.ndim(rgb) == 1 else rgb[..., c]
        view[..., c] = (col * a + view[..., c] * da * (1.0 - a)) / safe
    view[..., 3] = oa


def _sd_circle(X, Y, cx, cy, r):
    return np.hypot(X - cx, Y - cy) - r


def _sd_ellipse(X, Y, cx, cy, rx, ry):
    """楕円の符号付きの距離（近似：k0 (k0 - 1) / k1）。"""
    px, py = (X - cx) / rx, (Y - cy) / ry
    k0 = np.sqrt(px * px + py * py)
    k1 = np.sqrt((px / rx) ** 2 + (py / ry) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def _sd_polyline(X, Y, pts, r0, r1=None):
    """折れ線の太い線（半径は始点 r0 → 終点 r1）の符号付きの距離。"""
    r1 = r0 if r1 is None else r1
    lens = [0.0]
    for a, b in zip(pts[:-1], pts[1:]):
        lens.append(lens[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = max(lens[-1], 1e-9)
    d = np.full(X.shape, 1e9, np.float32)
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        ex, ey = bx - ax, by - ay
        L2 = max(ex * ex + ey * ey, 1e-12)
        h = np.clip(((X - ax) * ex + (Y - ay) * ey) / L2, 0.0, 1.0)
        ra = r0 + (r1 - r0) * lens[i] / total
        rb = r0 + (r1 - r0) * lens[i + 1] / total
        di = np.hypot(X - ax - h * ex, Y - ay - h * ey) - (ra + (rb - ra) * h)
        d = np.minimum(d, di)
    return d


def _sd_box(X, Y, cx, cy, hw, hh, r=0.0):
    qx = np.abs(X - cx) - (hw - r)
    qy = np.abs(Y - cy) - (hh - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def _resample(mask, w, h, ss=2):
    """マスク（行 0 が下）を幅 w・高さ h へ（ss × ss の点の平均、双線形）。"""
    H, W = mask.shape
    xs = (np.arange(w * ss, dtype=np.float32) + 0.5) / (w * ss) * W - 0.5
    ys = (np.arange(h * ss, dtype=np.float32) + 0.5) / (h * ss) * H - 0.5
    x0 = np.clip(np.floor(xs).astype(int), 0, W - 1)
    y0 = np.clip(np.floor(ys).astype(int), 0, H - 1)
    x1 = np.clip(x0 + 1, 0, W - 1)
    y1 = np.clip(y0 + 1, 0, H - 1)
    fx = np.clip(xs - x0, 0, 1)[None, :]
    fy = np.clip(ys - y0, 0, 1)[:, None]
    a = mask[np.ix_(y0, x0)] * (1 - fx) + mask[np.ix_(y0, x1)] * fx
    b = mask[np.ix_(y1, x0)] * (1 - fx) + mask[np.ix_(y1, x1)] * fx
    big = a * (1 - fy) + b * fy
    return big.reshape(h, ss, w, ss).mean(axis=(1, 3))


def _dilate(mask, r):
    """円の形で r px 太らせる（ずらした写しの最大）。"""
    out = mask.copy()
    H, W = mask.shape
    pad = np.pad(mask, r)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            out = np.maximum(out, pad[r + dy:r + dy + H, r + dx:r + dx + W])
    return out


def _bleed(buf, iters=BLEED):
    """透明な画素へ、となりの色をしみ出させる（縮小したときに縁が暗くならない）。アルファは変えない。"""
    rgb = buf[..., :3]
    a = buf[..., 3]
    filled = a > 0.01
    for _ in range(iters):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            src = np.roll(np.roll(rgb, dy, 0), dx, 1)
            acc += src * sh[..., None]
            cnt += sh
        grow = (~filled) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        filled = filled | grow


# ---------------------------------------------------------------- 文字・ロゴ

def _load_font():
    try:
        font = bpy.data.fonts.load(str(FONT_PATH), check_existing=True)
        INFO["font"] = FONT_PATH.name
        return font, True
    except Exception as e:      # noqa: BLE001
        INFO["font"] = f"<builtin>（{e}）"
        return bpy.data.fonts.load("<builtin>"), False


def _text_edges(text, shear=0.0):
    """文字のカーブをメッシュにし、輪郭の辺（面 1 つだけの辺）を (E, 2, 2) で返す（字の単位、y 上向き）。"""
    font, loaded = _load_font()
    cu = bpy.data.curves.new("hb_tmp_text", type="FONT")
    cu.body = text
    cu.font = font
    cu.size = 1.0
    cu.shear = shear
    cu.resolution_u = 16
    cu.fill_mode = "BOTH"
    obj = bpy.data.objects.new("hb_tmp_text", cu)
    bpy.context.scene.collection.objects.link(obj)
    try:
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        count = {}
        for poly in me.polygons:
            vs = list(poly.vertices)
            for i in range(len(vs)):
                e = tuple(sorted((vs[i], vs[(i + 1) % len(vs)])))
                count[e] = count.get(e, 0) + 1
        co = [(v.co.x, v.co.y) for v in me.vertices]
        edges = np.array([[co[a], co[b]] for (a, b), c in count.items() if c == 1], np.float64)
        ev.to_mesh_clear()
    finally:
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.curves.remove(cu)
        if loaded and font.users == 0:
            bpy.data.fonts.remove(font)
    if len(edges) == 0:
        raise RuntimeError(f"文字 {text!r} の輪郭が取れない")
    return edges


def _fill_edges(edges, w, h, ss=4):
    """輪郭の辺（px、y 上向き、行 0 が下）を偶奇で塗る。ss × ss の点の平均で縁をなめらかに。"""
    W, H = w * ss, h * ss
    e = edges * ss
    x0, y0, x1, y1 = e[:, 0, 0], e[:, 0, 1], e[:, 1, 0], e[:, 1, 1]
    xs = np.arange(W) + 0.5
    out = np.zeros((H, W), np.float32)
    for row in range(H):
        y = row + 0.5
        hit = ((y0 <= y) & (y < y1)) | ((y1 <= y) & (y < y0))
        if not hit.any():
            continue
        xa = x0[hit] + (y - y0[hit]) * (x1[hit] - x0[hit]) / (y1[hit] - y0[hit])
        xa.sort()
        out[row] = (np.searchsorted(xa, xs) % 2).astype(np.float32)
    return out.reshape(h, ss, w, ss).mean(axis=(1, 3))


def _text_mask(text, w, h, shear=0.0, margin=0.04):
    """文字を幅 w・高さ h の中へ、縦横比を保ってまん中に。"""
    edges = _text_edges(text, shear)
    lo = edges.reshape(-1, 2).min(axis=0)
    hi = edges.reshape(-1, 2).max(axis=0)
    size = hi - lo
    s = min(w * (1 - 2 * margin) / size[0], h * (1 - 2 * margin) / size[1])
    off = np.array([w, h]) / 2 - (lo + hi) / 2 * s
    return _fill_edges(edges * s + off, w, h)


def _logo_alpha():
    """ロゴの PNG のアルファ（字の外形で切り抜く）。行 0 が下。"""
    img = bpy.data.images.load(str(LOGO_PNG), check_existing=False)
    try:
        w, h = img.size
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
    finally:
        bpy.data.images.remove(img)
    a = px.reshape(h, w, 4)[..., 3]
    ys, xs = np.nonzero(a > 0.02)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    INFO["logo_px"] = [int(a.shape[1]), int(a.shape[0])]
    return a


# ---------------------------------------------------------------- 外の領域

def _cell_view(buf, name):
    x, y, w, h = CELLS[name]
    return buf[y:y + h, x:x + w]


def _paint_logos(buf):
    a = _logo_alpha()
    aspect = a.shape[1] / a.shape[0]
    outline = 12
    lw = 1024 - 2 * GUTTER - 2 * outline - 16          # 字の幅（px）
    lh = int(round(lw / aspect))
    rw, rh = lw + 2 * outline, lh + 2 * outline
    mask = _resample(a, lw, lh)
    INFO["logo_aspect"] = round(aspect, 4)
    for name in ("LOGO_KEY", "LOGO_MASK"):
        cx, cy, cw, ch = CELLS[name]
        x0 = cx + (cw - rw) // 2
        y0 = cy + (ch - rh) // 2
        REGIONS[name] = (x0, y0, rw, rh)
        view = buf[y0:y0 + rh, x0:x0 + rw]
        full = np.zeros((rh, rw), np.float32)
        full[outline:outline + lh, outline:outline + lw] = mask
        if name == "LOGO_KEY":
            _over(view, WHITE, _dilate(full, outline))
            _over(view, NAVY, full)
        else:
            _over(view, WHITE, full)


def _paint_numbers(buf):
    for k, text in enumerate(NUMBERS):
        name = f"NUM_{k}"
        cx, cy, cw, ch = CELLS[name]
        rw, rh = cw - 2 * GUTTER, 141                     # 尾翼の四角（0.318 × 0.10 m）と同じ縦横比
        x0, y0 = cx + GUTTER, cy + (ch - rh) // 2
        REGIONS[name] = (x0, y0, rw, rh)
        mask = _text_mask(text, rw, rh, shear=0.12, margin=0.06)
        _over(buf[y0:y0 + rh, x0:x0 + rw], WHITE, mask)


# ハテナ（build_hatena.py の正面の形。x 右・z 上、単位は m）
HATENA = {
    "body_c": (0.0, 1.03), "body_r": (0.56, 0.55),
    "eye_c": (0.173, 1.106), "eye_r": (0.057, 0.09),
    "hi_big": (0.019, 0.037, 0.022, 0.028), "hi_small": (-0.021, -0.038, 0.014, 0.014),
    "smile_c": (0.0, 1.001), "smile_w": 0.066, "smile_d": 0.03, "smile_r": 0.022,
    "crest_c": (0.0, 1.835), "crest_r": 0.135, "crest_stroke": 0.062, "crest_join": -40.0, "crest_end": 212.0,
    "ball_off": (-0.012, -0.018), "ball_r": 0.082,
    "collar_z": 1.572, "collar_half": 0.086, "collar_r": 0.024,
}


def _crest_path():
    H = HATENA
    cx, cz = H["crest_c"]
    r = H["crest_r"]
    p0 = np.array([0.0, 1.50])
    aj = math.radians(H["crest_join"])
    p3 = np.array([cx + r * math.cos(aj), cz + r * math.sin(aj)])
    tan3 = np.array([-math.sin(aj), math.cos(aj)])
    p1 = p0 + np.array([0.0, 0.09])
    p2 = p3 - tan3 * 0.07
    pts = []
    for i in range(14):
        t = i / 14
        q = p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + p3 * t ** 3
        pts.append((float(q[0]), float(q[1])))
    ae = math.radians(H["crest_end"])
    for i in range(41):
        a = aj + (ae - aj) * i / 40
        pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def paint_hatena(view, cx, cy, scale, z_mid, outline_px=6.0):
    """view の (cx, cy)（px）をハテナの (0, z_mid) にして、scale px/m で描く。"""
    X, Y = _grid(view.shape[1], view.shape[0])

    def to_px(x, z):
        return cx + x * scale, cy + (z - z_mid) * scale

    crest = [to_px(x, z) for x, z in _crest_path()]
    stroke = HATENA["crest_stroke"] * scale
    end = _crest_path()[-1]
    bx, bz = to_px(end[0] + HATENA["ball_off"][0], end[1] + HATENA["ball_off"][1])
    br = HATENA["ball_r"] * scale
    c0 = to_px(-HATENA["collar_half"], HATENA["collar_z"])
    c1 = to_px(HATENA["collar_half"], HATENA["collar_z"])
    crr = HATENA["collar_r"] * scale
    bcx, bcy = to_px(*HATENA["body_c"])
    brx, bry = HATENA["body_r"][0] * scale, HATENA["body_r"][1] * scale
    d_crest = np.minimum(_sd_polyline(X, Y, crest, stroke), _sd_circle(X, Y, bx, bz, br))
    d_collar = _sd_polyline(X, Y, [c0, c1], crr)
    d_body = _sd_ellipse(X, Y, bcx, bcy, brx, bry)
    _over(view, NAVY, _cov(d_crest - outline_px))
    _over(view, ORANGE, _cov(d_crest))
    _over(view, NAVY, _cov(d_body - outline_px))
    _over(view, HATENA_WHITE, _cov(d_body))
    _over(view, NAVY, _cov(d_collar - outline_px * 0.8))
    _over(view, ORANGE, _cov(d_collar))
    for s in (-1, 1):
        ex, ey = to_px(s * HATENA["eye_c"][0], HATENA["eye_c"][1])
        _over(view, EYE, _cov(_sd_ellipse(X, Y, ex, ey, HATENA["eye_r"][0] * scale, HATENA["eye_r"][1] * scale)))
        for key in ("hi_big", "hi_small"):
            dx, dz, rx, rz = HATENA[key]
            _over(view, np.array([1.0, 1.0, 1.0], np.float32), _cov(_sd_ellipse(X, Y, ex + dx * scale, ey + dz * scale, rx * scale, rz * scale)))
    sc = HATENA["smile_c"]
    w, dd = HATENA["smile_w"], HATENA["smile_d"]
    smile = [to_px(sc[0] + u, sc[1] + dd * (u / w) ** 2 - dd) for u in np.linspace(-w, w, 13)]
    _over(view, MOUTH, _cov(_sd_polyline(X, Y, smile, HATENA["smile_r"] * scale)))


def _paint_emblem(buf):
    cx0, cy0, cw, ch = CELLS["EMBLEM"]
    rw = cw - 2 * GUTTER
    x0, y0 = cx0 + GUTTER, cy0 + GUTTER
    REGIONS["EMBLEM"] = (x0, y0, rw, rw)
    view = buf[y0:y0 + rw, x0:x0 + rw]
    X, Y = _grid(rw, rw)
    R = rw / 2 - 1.5
    c = rw / 2
    d = _sd_circle(X, Y, c, c, R)
    _over(view, WHITE, _cov(d))
    _over(view, SKY, _cov(_sd_circle(X, Y, c, c, 0.92 * R)))
    # ハテナ：高さ（帽子の先〜体の下）を内側の円の 76 % に
    top = HATENA["crest_c"][1] + HATENA["crest_r"] + HATENA["crest_stroke"]
    bottom = HATENA["body_c"][1] - HATENA["body_r"][1]
    scale = 0.76 * 2 * 0.92 * R / (top - bottom)
    inner = np.zeros_like(view)
    paint_hatena(inner, c, c, scale, (top + bottom) / 2)
    clip = _cov(_sd_circle(X, Y, c, c, 0.92 * R))
    _over(view, inner[..., :3], inner[..., 3] * clip)


def _paint_hazard(buf):
    """45° の黄黒の縞。周期 128 px（0.10 m）、タイルは 256 × 128（0.20 × 0.10 m）。マスの横いっぱいに続ける。"""
    cx, cy, cw, ch = CELLS["HAZARD"]
    rh = 128
    y0 = cy + (ch - rh) // 2
    REGIONS["HAZARD"] = (cx + (cw - 256) // 2, y0, 256, rh)
    view = buf[y0:y0 + rh, cx:cx + cw]
    X, Y = _grid(cw, rh)
    X = X + cx
    Y = Y + y0
    f = np.mod(X + Y, 128.0)
    d = np.minimum(np.abs(f - 0.0), np.abs(f - 128.0))
    d = np.minimum(d, np.abs(f - 64.0)) / math.sqrt(2)      # 縞の境目までの距離（px）
    yellow = np.where(f < 64.0, 1.0, 0.0)
    k = np.clip(d / 1.0, 0.0, 1.0)
    w_y = yellow * k + 0.5 * (1 - k)
    rgb = YELLOW[None, None, :] * w_y[..., None] + BLACK[None, None, :] * (1 - w_y[..., None])
    view[..., :3] = rgb
    view[..., 3] = 1.0


def _paint_pin(buf):
    """細い線：中身の縦のまん中 44 % が不透明（縁は 1.5 px でぼかす）。白（色は頂点色）。横いっぱいに続ける。"""
    cx, cy, cw, ch = CELLS["PIN"]
    rh = ch - 2 * GUTTER
    y0 = cy + GUTTER
    REGIONS["PIN"] = (cx + GUTTER, y0, cw - 2 * GUTTER, rh)
    view = buf[y0:y0 + rh, cx:cx + cw]
    _, Y = _grid(cw, rh)
    d = np.abs(Y - rh / 2) - 0.22 * rh
    view[..., :3] = 1.0
    view[..., 3] = _cov(d, 1.5)


# ---------------------------------------------------------------- コックピットの画面

def _ui_rect(name, w, h):
    cx, cy, cw, ch = CELLS[name]
    x0, y0 = cx + (cw - w) // 2, cy + (ch - h) // 2
    REGIONS[name] = (x0, y0, w, h)
    return x0, y0


def _paint_ui(buf):
    # 多機能画面（0.20 × 0.15 m → 224 × 168）
    w, h = 224, 168
    for k in range(4):
        x0, y0 = _ui_rect(f"MFD_{k}", w, h)
        view = buf[y0:y0 + h, x0:x0 + w]
        view[..., :3] = SCREEN_BG
        view[..., 3] = 1.0
        X, Y = _grid(w, h)
        frame = _sd_box(X, Y, w / 2, h / 2, w / 2 - 3, h / 2 - 3, 6)
        if k == 0:      # 姿勢：空と地面（少し傾けた水平線）、はしご、飛行機の印
            ang = math.radians(-6.0)
            side = (Y - h * 0.48) * math.cos(ang) - (X - w / 2) * math.sin(ang)
            _over(view, SKY_SCREEN, _cov(-side) * _cov(frame))
            _over(view, GROUND_SCREEN, _cov(side) * _cov(frame))
            _over(view, WHITE, _cov(np.abs(side) - 1.6) * _cov(frame))
            for p in (-2, -1, 1, 2):
                yy = h * 0.48 + p * 22
                L = 26 if p % 2 == 0 else 14
                seg = [(w / 2 - L, yy), (w / 2 + L, yy)]
                _over(view, WHITE, _cov(_sd_polyline(X, Y, seg, 1.4)))
            wing = [(w / 2 - 46, h * 0.48), (w / 2 - 16, h * 0.48), (w / 2, h * 0.48 - 12), (w / 2 + 16, h * 0.48), (w / 2 + 46, h * 0.48)]
            _over(view, YELLOW, _cov(_sd_polyline(X, Y, wing, 3.2)))
        elif k == 1:    # 地図：距離の輪・道すじ・通る点・自分の印
            cxp, cyp = w / 2, 34
            for r in (50, 100, 150):
                _over(view, CYAN * 0.7, _cov(np.abs(_sd_circle(X, Y, cxp, cyp, r)) - 0.9) * (Y > cyp))
            route = [(cxp, cyp), (cxp + 18, 70), (cxp - 10, 112), (cxp + 30, 150), (cxp + 70, 166)]
            _over(view, MAGENTA, _cov(_sd_polyline(X, Y, route, 2.2)))
            for px_, py_ in route[1:-1]:
                _over(view, WHITE, _cov(_sd_box(X, Y, px_, py_, 5, 5, 1)))
            tri = [(cxp - 9, cyp - 6), (cxp, cyp + 12), (cxp + 9, cyp - 6), (cxp - 9, cyp - 6)]
            _over(view, YELLOW, _cov(_sd_polyline(X, Y, tri, 2.2)))
            for gx in range(5):
                _over(view, GREEN * 0.45, _cov(_sd_box(X, Y, 30 + gx * 40, 120 + 8 * math.sin(gx), 10, 4, 2)))
        elif k == 2:    # エンジン：縦の棒と円弧のメーター
            for i, (lvl, col) in enumerate(((0.72, GREEN), (0.64, GREEN), (0.86, AMBER))):
                bx = 34 + i * 34
                _over(view, CYAN * 0.35, _cov(_sd_box(X, Y, bx, 84, 9, 62, 2)))
                _over(view, col, _cov(_sd_box(X, Y, bx, 22 + 62 * lvl, 7, 62 * lvl, 1)))
            cxp, cyp, r = 170, 90, 38
            ang = np.arctan2(Y - cyp, X - cxp)
            ring = np.abs(_sd_circle(X, Y, cxp, cyp, r)) - 3.5
            arc_ok = (ang > math.radians(-30)) & (ang < math.radians(210))
            _over(view, GREEN, _cov(ring) * arc_ok * (ang > math.radians(60)))
            _over(view, AMBER, _cov(ring) * arc_ok * (ang <= math.radians(60)) * (ang > math.radians(20)))
            _over(view, RED, _cov(ring) * arc_ok * (ang <= math.radians(20)))
            needle = [(cxp, cyp), (cxp + r * 0.85 * math.cos(math.radians(100)), cyp + r * 0.85 * math.sin(math.radians(100)))]
            _over(view, WHITE, _cov(_sd_polyline(X, Y, needle, 2.0)))
            _over(view, CYAN * 0.8, _cov(_sd_box(X, Y, 170, 30, 30, 2, 1)))
        else:           # クイズ：ハテナの紋章と、答えの棒
            sub = np.zeros((h, w, 4), np.float32)
            Xs, Ys = _grid(w, h)
            _over(sub, SKY, _cov(_sd_circle(Xs, Ys, 62, 84, 48)))
            paint_hatena(sub, 62, 84, 52.0, 1.26, outline_px=2.0)
            _over(view, sub[..., :3], sub[..., 3])
            for i, (L, col) in enumerate(((84, GREEN), (60, CYAN), (72, CYAN), (40, AMBER))):
                _over(view, col, _cov(_sd_box(X, Y, 128 + L / 2, 134 - i * 30, L / 2, 8, 3)))
        inside = _cov(frame)[..., None]
        view[..., :3] = view[..., :3] * inside + SCREEN_BG * (1.0 - inside)
        _over(view, CYAN * 0.55, _cov(np.abs(frame) - 1.2))
    # 計器の文字盤（96²）：目盛りと緑の弧（針は形で作ってある）
    for k in range(4):
        x0, y0 = _ui_rect(f"DIAL_{k}", 96, 96)
        view = buf[y0:y0 + 96, x0:x0 + 96]
        view[..., :3] = SCREEN_BG
        view[..., 3] = 1.0
        X, Y = _grid(96, 96)
        ang = np.arctan2(Y - 48, X - 48)
        for i in range(12):
            a = math.radians(225 - i * 22.5)
            long = 0.70 if i % 3 == 0 else 0.80
            seg = [(48 + 44 * long * math.cos(a), 48 + 44 * long * math.sin(a)), (48 + 43 * math.cos(a), 48 + 43 * math.sin(a))]
            _over(view, WHITE, _cov(_sd_polyline(X, Y, seg, 1.6 if i % 3 == 0 else 1.0)))
        ring = np.abs(_sd_circle(X, Y, 48, 48, 34)) - 2.0
        lo, hi = ((150, 60), (120, 20), (200, 90), (100, -10))[k]
        _over(view, GREEN, _cov(ring) * (ang < math.radians(lo)) * (ang > math.radians(hi)))
    # 無線の窓（128 × 32）：数字なしの光る区切り
    for k in range(3):
        x0, y0 = _ui_rect(f"RADIO_{k}", 128, 32)
        view = buf[y0:y0 + 32, x0:x0 + 128]
        view[..., :3] = SCREEN_BG * 0.6
        view[..., 3] = 1.0
        X, Y = _grid(128, 32)
        col = (GREEN, AMBER, CYAN)[k]
        for i, L in enumerate((18, 10, 22, 14)):
            _over(view, col, _cov(_sd_box(X, Y, 12 + i * 30 + L / 2, 16, L / 2, 6, 1.5)))
    # 警告灯の列（192 × 24）
    x0, y0 = _ui_rect("ANNUN", 192, 24)
    view = buf[y0:y0 + 24, x0:x0 + 192]
    view[..., :3] = SCREEN_BG * 0.5
    view[..., 3] = 1.0
    X, Y = _grid(192, 24)
    for i, col in enumerate((GREEN, GREEN, AMBER, GREEN, RED * 0.5, CYAN)):
        _over(view, col, _cov(_sd_box(X, Y, 16 + i * 32, 12, 13, 8, 2)))
    # 既定の UV のマス
    x0, y0 = _ui_rect("UI_SOLID", 32, 32)
    buf[y0:y0 + 32, x0:x0 + 32, :3] = CYAN
    buf[y0:y0 + 32, x0:x0 + 32, 3] = 1.0
    x0, y0 = _ui_rect("TRANSPARENT", 32, 32)
    buf[y0:y0 + 32, x0:x0 + 32] = 0.0


# ---------------------------------------------------------------- UV

def uv_rect(name, inset_u=2.0, inset_v=2.0):
    """中身の四角の UV (u0, v0, u1, v1)（Blender の向き）。縁から inset 画素だけ内へ。"""
    x, y, w, h = REGIONS[name]
    return ((x + inset_u) / SIZE, (y + inset_v) / SIZE, (x + w - inset_u) / SIZE, (y + h - inset_v) / SIZE)


def uv_center(name):
    x, y, w, h = REGIONS[name]
    return ((x + w / 2) / SIZE, (y + h / 2) / SIZE)


def _corners(name, inset=1.0):
    u0, v0, u1, v1 = uv_rect(name, inset, inset)
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def number_uv_step():
    """機体番号の行の差（Godot の uv1_offset の v。glTF は v を上下に返すので、Blender の行の差がそのまま + になる）。"""
    return [0.0, (REGIONS["NUM_0"][1] - REGIONS["NUM_1"][1]) / SIZE]


# ---------------------------------------------------------------- 作る

def build_atlas():
    """アトラスを描いて PNG に書き、画像（bpy の Image、.blend に詰める）を返す。UV の表（hb_cockpit.UI_RECTS、DEFAULT_UV）も入れる。"""
    import hb_cockpit
    REGIONS.clear()
    INFO.clear()
    buf = np.zeros((SIZE, SIZE, 4), np.float32)
    _paint_logos(buf)
    _paint_numbers(buf)
    _paint_emblem(buf)
    _paint_hazard(buf)
    _paint_pin(buf)
    _paint_ui(buf)
    for font in [f for f in bpy.data.fonts if f.filepath and FONT_PATH.name in f.filepath and f.users == 0]:
        bpy.data.fonts.remove(font)
    _bleed(buf)
    np.clip(buf, 0.0, 1.0, out=buf)
    old = bpy.data.images.get(IMAGE_NAME)
    if old is not None:
        bpy.data.images.remove(old, do_unlink=True)
    img = bpy.data.images.new(IMAGE_NAME, SIZE, SIZE, alpha=True)
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(buf.ravel())
    K.TEXTURES.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(PNG)
    img.file_format = "PNG"
    img.save()
    img.pack()
    img.colorspace_settings.name = "sRGB"
    # 表
    hb_cockpit.UI_RECTS.clear()
    for k in range(4):
        hb_cockpit.UI_RECTS[f"mfd{k}"] = _corners(f"MFD_{k}")
        hb_cockpit.UI_RECTS[f"dial{k}"] = _corners(f"DIAL_{k}")
    for k in range(3):
        hb_cockpit.UI_RECTS[f"radio{k}"] = _corners(f"RADIO_{k}")
    hb_cockpit.UI_RECTS["annunciator"] = _corners("ANNUN")
    K.DEFAULT_UV.clear()
    K.DEFAULT_UV["ScreenGlow"] = uv_center("UI_SOLID")
    K.DEFAULT_UV["Decal"] = uv_center("TRANSPARENT")
    K.DEFAULT_UV["DecalNumber"] = uv_center("TRANSPARENT")
    data = {"size": SIZE, "image": IMAGE_NAME, "png": PNG.name, "origin": "bottom-left (Blender)", "cells": CELLS,
            "regions": {k: list(v) for k, v in REGIONS.items()}, "numbers": NUMBERS, "number_uv_step": number_uv_step(), "info": INFO}
    REGIONS_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    return img


def atlas_md5_match(img):
    """詰めた画像のバイト列と、ディスクの PNG が同じか（古い画像を詰めたままにしていないか）。"""
    if img is None or img.packed_file is None or not PNG.exists():
        return False, {}
    packed = hashlib.md5(bytes(img.packed_file.data)).hexdigest()
    disk = hashlib.md5(PNG.read_bytes()).hexdigest()
    return packed == disk, {"packed": packed[:12], "disk": disk[:12]}
