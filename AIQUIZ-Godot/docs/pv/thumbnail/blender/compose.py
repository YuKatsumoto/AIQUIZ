"""サムネイルの合成：Blender（Cycles）で描き直した 3 層を、ゲームで撮った背景に重ねる（t2・t5）。

層（<shot>_thumbnail.blend の view layer。render_layers.py が .npy に書き出す。どれも線形の光の量、アルファは乗算済み）:
  VL_chars  2 人（帽子つき）。壁と床は穴（holdout）
  VL_p2trail 吹っ飛ぶプレイヤーの残像の尾（長いモーションブラー）。くっきりした本体（VL_chars）の下に重ねる（あるときだけ）
  VL_wall   壁・扉・破片・看板・文字の板。床は穴、2 人は影と照り返しだけ（indirect only）
  VL_deck   コンベアの床・枠・レール。2 人と壁は影と照り返しだけ
  VL_depth  壁と床までのカメラからの奥行き（m）。ぼかしの量を決める
背景：ゲームの同じ瞬間を、前景を隠して撮ったもの（plate_dof.png。ゲームの被写界深度つき）。
粒（t5）：ゲームの粒だけの絵（fx_nodof.png、アルファつき）を最後に重ねる。前景の後ろに隠れた粒は、
  全体の絵（full_nodof）と粒を隠した全体の絵（full_nofx_nodof）が変わらない所なので、そこは重ねない。

ゲームとそろえること:
  - 色の変換はゲームと同じ ACES（Godot 4 の tonemap_aces、white 6.0、露出 1.0）→ sRGB → コントラスト 1.04
  - 床と壁のぼけはゲームの被写界深度と同じ決め方（奥行きがぼけ始めから幅のあいだで、半径 0 → ぼけきる半径）。
    ぼけきったときの半径は、背景の絵（ぼけあり・なし）を比べて求める（calibrate）

  python docs/pv/thumbnail/blender/compose.py <shot> calibrate                       # ぼけの半径を求める
  python docs/pv/thumbnail/blender/compose.py <shot> <tag> [出力名] [final] [nonear]   # 合成して out/<出力名>.png
      層は artifacts/pv_capture/thumb_<shot>_blender/<tag>_<層>.npy（layers=<フォルダ> で変えられる）。
      final を付けると ../finish.py と同じ仕上げとロゴで final/<shot>_blender.png・.jpg も書く
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / "out"
W, H = 1920, 1080
TONEMAP_WHITE = 6.0
CONTRAST = 1.04

# dof_start・dof_range：ぼけ始めの奥行きとぼけきるまでの幅（m）。dof_radius：ぼけきったときの半径（1920 幅の px）。
# near：手前のぼけ（ゲームには無い。レンズらしさのため、いちばん手前の床だけをわずかにぼかす）＝（これより近い所から, 幅, 最大の半径）。
# calib_box：calibrate で比べる、背景の絵のぼけきった所（行, 列）
SHOTS = {
    # ゲームのぼけ始めは 11.65 m。扉の「56」（奥行き 12.4 m）までくっきり見せるため、サムネイルでは 12.9 m からにした
    "t2": {"dof_start": 12.9, "dof_range": 10.0, "dof_radius": 14.5, "near": (4.5, 1.5, 3.0),
           "calib_box": ((330, 560), (40, 820))},
    # ぼけはゲームのまま（壁より 4 m 奥の 18.05 m からぼけ始め、12 m でぼけきる）。半径は空の雲で求めた。
    # trail_gain：吹っ飛ぶプレイヤーの残像の尾（VL_p2trail）の濃さ。アルファ a を 1 − (1 − a)^gain にする（薄い所ほど強める）
    "t5": {"dof_start": 18.046, "dof_range": 12.0, "dof_radius": 11.5, "near": (4.5, 1.5, 3.0),
           "calib_box": ((20, 300), (40, 1880)), "trail_gain": 2.0},
    # t7（絵コンテ gen/t2_side.png の再現。真横の超望遠）：背景はゲームの同じ瞬間の背景だけの絵（plate_nodof。観客席・高層ビル・
    # 島は撮影台本で絵コンテに寄せて置き直してある）を、円でぼかし（plate_blur、線形の光で。絵コンテの強いぼけに寄せて 6.5 px）、流し撮りのように横にも流す
    # （plate_streak px、plate_streak_mix の割合）。絵コンテの空と海は濃いので、背景の絵だけ色を足す（plate_look）。
    # 2 人より奥の壁と床は奥行きで少しぼかす。手前の床（45 m より近い所）もわずかに。最後にスピード線（speed_lines）
    "t7": {"dof_start": 66.0, "dof_range": 20.0, "dof_radius": 3.0, "near": (45.0, 8.0, 2.5), "calib_box": ((20, 300), (40, 1880)),
           "plate": "artifacts/pv_capture/thumb_t7_export/export/plate_nodof.png", "plate_blur": 6.5,
           "plate_streak": 24, "plate_streak_mix": 0.55,
           "plate_look": {"saturation": 1.35, "sky_deep": (0.20, 0.47, 0.92), "sky_amount": 0.75, "horizon": 0.56,
                          "sea": {"from": 0.567, "to": 0.75, "near": (0.50, 0.82, 0.93), "deep": (0.02, 0.50, 0.78),
                                  "contrast": 2.2, "amount": 0.8}},
           # (y, 左端 x, 右端 x, 太さ px, 濃さ)：画面の割合。右端（走る向きの先）ほど濃く太い
           # P1 の胸・腰・脚のうしろ（地平線 0.565 の線とは重ねない）と、P1 と P2 のあいだ
           "speed_lines": [(0.600, 0.36, 0.525, 3.0, 0.85), (0.640, 0.33, 0.515, 3.5, 0.9), (0.682, 0.38, 0.50, 2.5, 0.75),
                           (0.722, 0.40, 0.472, 2.5, 0.7), (0.775, 0.33, 0.425, 2.5, 0.65), (0.622, 0.60, 0.70, 3.0, 0.8),
                           (0.662, 0.615, 0.703, 2.5, 0.75), (0.578, 0.63, 0.718, 2.0, 0.6)]},
}


def export_dir(shot: str) -> Path:
    return ROOT / f"artifacts/pv_capture/thumb_{shot}_export/export"


# ------------------------------------------------------------------ 色

def srgb_encode(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def srgb_decode(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.04045, x / 12.92, np.power((x + 0.055) / 1.055, 2.4))


# Godot 4 の tonemap_aces（servers/rendering/renderer_rd/shaders/effects/tonemap.glsl）。行列は行ごと
_BIAS = 1.8
_RRT = np.array([[0.59719, 0.35458, 0.04823], [0.07600, 0.90834, 0.01566], [0.02840, 0.13383, 0.83777]]) * _BIAS
_ODT = np.array([[1.60475, -0.53108, -0.07367], [-0.10208, 1.10813, -0.00605], [-0.00327, -0.07276, 1.07602]])


def _aces_curve(x):
    a, b, c, d, e = 0.0245786, 0.000090537, 0.983729, 0.432951, 0.238081
    return (x * (x + a) - b) / (x * (c * x + d) + e)


def tonemap(rgb: np.ndarray, white: float = TONEMAP_WHITE, exposure: float = 1.0) -> np.ndarray:
    """線形の光の量 → ゲームと同じ sRGB（0〜1）"""
    x = (rgb * exposure) @ _RRT.T
    y = _aces_curve(x) @ _ODT.T
    y = y / _aces_curve(white * _BIAS)
    s = srgb_encode(y)
    return np.clip(0.5 + (s - 0.5) * CONTRAST, 0.0, 1.0)


# ------------------------------------------------------------------ ぼかし（円の形。FFT で畳み込む）

def disk_kernel(radius: float) -> np.ndarray:
    r = max(radius, 0.0)
    n = int(np.ceil(r)) + 1
    yy, xx = np.mgrid[-n:n + 1, -n:n + 1]
    dist = np.sqrt(xx * xx + yy * yy)
    k = np.clip(r + 0.5 - dist, 0.0, 1.0)          # 縁を 1 px でなめらかに
    return k / k.sum()


def blur(img: np.ndarray, radius: float) -> np.ndarray:
    """img: H x W x C。端は端の値で延ばす"""
    if radius < 0.35:
        return img.copy()
    k = disk_kernel(radius)
    pad = k.shape[0] // 2 + 2
    padded = np.pad(img, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
    ph, pw = padded.shape[:2]
    fk = np.fft.rfft2(k, s=(ph, pw))
    out = np.empty_like(padded)
    for ch in range(img.shape[2]):
        out[..., ch] = np.fft.irfft2(np.fft.rfft2(padded[..., ch]) * fk, s=(ph, pw))
    kc = k.shape[0] // 2
    out = np.roll(out, (-kc, -kc), axis=(0, 1))
    return out[pad:pad + img.shape[0], pad:pad + img.shape[1]]


def coc_px(depth: np.ndarray, cfg: dict, near: bool) -> np.ndarray:
    """奥行き → ぼけの半径（px）。奥はゲームの被写界深度と同じ決め方、手前は near のときだけ"""
    far = np.clip((depth - cfg["dof_start"]) / cfg["dof_range"], 0.0, 1.0) * cfg["dof_radius"]
    if not near:
        return far
    n_start, n_range, n_radius = cfg["near"]
    close = np.clip((n_start - depth) / n_range, 0.0, 1.0) * n_radius
    return np.maximum(far, close)


def depth_dof(rgba: np.ndarray, depth: np.ndarray, cfg: dict, near: bool = False, levels: int = 12) -> np.ndarray:
    """乗算済みの RGBA を、半径を何段かに分けてぼかし、画素ごとに奥行きで選ぶ（となりの 2 段を直線でつなぐ）"""
    coc = coc_px(depth, cfg, near)
    top = max(cfg["dof_radius"], cfg["near"][2] if near else 0.0)
    step = top / levels
    pos = coc / step
    out = np.zeros_like(rgba)
    for i in range(levels + 1):
        w = np.clip(1.0 - np.abs(pos - i), 0.0, 1.0)[..., None]
        if w.max() > 0.0:
            out += blur(rgba, i * step) * w
    return out


# ------------------------------------------------------------------ 読み込み

def load_layer(folder: Path, tag: str, name: str) -> np.ndarray:
    arr = np.load(folder / f"{tag}_{name}.npy").astype(np.float64)
    if arr.shape[1] != W:                            # 4K で描いたものは 2x2 の平均で 1920 に（乗算済みのまま）
        f = arr.shape[1] // W
        arr = arr.reshape(H, f, W, f, 4).mean(axis=(1, 3))
    return arr


def load_depth(folder: Path, tag: str) -> np.ndarray:
    arr = np.load(folder / f"{tag}_VL_depth.npy").astype(np.float64)
    if arr.shape[1] != W:
        f = arr.shape[1] // W
        a = arr[..., 3].reshape(H, f, W, f).mean(axis=(1, 3))
        d = (arr[..., 0] * arr[..., 3]).reshape(H, f, W, f).mean(axis=(1, 3))
        depth = np.where(a > 1e-4, d / np.maximum(a, 1e-4), 1e4)
    else:
        a = arr[..., 3]
        depth = np.where(a > 1e-4, arr[..., 0] / np.maximum(a, 1e-4), 1e4)
    # 何も無い画素（空）は遠く
    return depth


def load_srgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0


# ------------------------------------------------------------------ 合成

def to_display(rgba: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """乗算済みの線形 RGBA → ゲームと同じ sRGB（乗算前）とアルファ"""
    a = np.clip(rgba[..., 3], 0.0, 1.0)
    rgb = np.where(a[..., None] > 1e-5, rgba[..., :3] / np.maximum(a[..., None], 1e-5), 0.0)
    return tonemap(rgb), a


def over(dst: np.ndarray, src_rgb: np.ndarray, src_a: np.ndarray) -> np.ndarray:
    return src_rgb * src_a[..., None] + dst * (1.0 - src_a[..., None])


def fx_layer(shot: str) -> tuple[np.ndarray, np.ndarray] | None:
    """ゲームの粒：見えている所のアルファ a と、乗算済みの色 P（ゲームの全体の絵から、粒の後ろの色を引いて求める）。
    粒のほかで差が出る所（ゲームの画面上の陰影 SSAO が粒で少し暗くなる所）は使わない"""
    ex = export_dir(shot)
    if not (ex / "fx_nodof.png").exists() or not (ex / "full_nofx_nodof.png").exists():
        return None
    fx = np.asarray(Image.open(ex / "fx_nodof.png").convert("RGBA"), dtype=np.float64) / 255.0
    full = load_srgb(ex / "full_nodof.png")
    nofx = load_srgb(ex / "full_nofx_nodof.png")
    diff = np.abs(full - nofx).max(axis=2) * 255.0
    seen = np.clip((diff - 1.5) / 4.5, 0.0, 1.0)            # 差が 1.5 段以下は隠れている、6 段以上は見えている
    a = fx[..., 3] * seen
    color = full - nofx * (1.0 - a[..., None])              # 乗算済みの粒の色（ゲームの見え方のまま）
    return np.clip(color, 0.0, 1.0) * (a[..., None] > 0), a


def background(shot: str, plate: str) -> np.ndarray:
    """背景の絵（sRGB）。plate があれば別に撮った絵を使い、plate_blur の半径の円でぼかし、plate_streak px だけ横にも流す
    （どちらも線形の光で）。plate_look で色を足す"""
    cfg = SHOTS[shot]
    if "plate" not in cfg:
        return load_srgb(export_dir(shot) / plate)
    img = load_srgb(ROOT / cfg["plate"])
    lin = srgb_decode(img)
    if cfg.get("plate_blur", 0.0) > 0.0:
        lin = blur(lin, cfg["plate_blur"])
    if cfg.get("plate_streak", 0) > 0:
        n = int(cfg["plate_streak"])
        k = np.ones(n) / n
        streak = np.stack([np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, lin[..., c]) for c in range(3)], -1)
        m = cfg.get("plate_streak_mix", 1.0)
        lin = lin * (1.0 - m) + streak * m
    img = srgb_encode(lin)
    look = cfg.get("plate_look")
    if look:
        lum = (img @ np.array([0.2126, 0.7152, 0.0722]))[..., None]
        img = np.clip(lum + (img - lum) * look.get("saturation", 1.0), 0.0, 1.0)
        # 空：地平線より上ほど、深い青へ寄せる（青みの強い所だけ。白い雲や白い建物はそのまま）
        v = (np.arange(H, dtype=np.float64) / H)[:, None]
        w = np.clip(1.0 - v / look.get("horizon", 0.55), 0.0, 1.0) ** 1.4 * look.get("sky_amount", 0.0)
        blue = np.clip((img[..., 2] - img[..., 0] - 0.08) / 0.3, 0.0, 1.0)
        w = (w * blue)[..., None]
        deep = np.array(look.get("sky_deep", (0.25, 0.5, 0.95)))
        img = np.clip(img * (1.0 - w) + img * (deep / deep.max()) * 1.12 * w, 0.0, 1.0)
        if look.get("sea"):
            img = sea_look(img, look["sea"])
    return img


def sea_look(img: np.ndarray, sea: dict) -> np.ndarray:
    """海（地平線 from から to までの、青緑の所だけ）を、地平線の明るい水色（near）から手前の深い青（deep）へ塗り直す。
    波の明暗は、その行の平均に対する明るさの比を contrast 乗して残す（白い柱や観客席は青緑でないので変えない）"""
    v = (np.arange(H, dtype=np.float64) / H)[:, None]
    rows = np.clip((v - sea["from"]) / 0.03, 0.0, 1.0)              # 地平線のもやからゆっくり効かせる
    t = np.clip((v - sea["from"]) / (sea["to"] - sea["from"]), 0.0, 1.0)
    cyan = np.clip((img[..., 2] - img[..., 0] - 0.06) / 0.18, 0.0, 1.0)
    w = rows * cyan
    lum = img @ np.array([0.2126, 0.7152, 0.0722])
    weight = (w > 0.5).astype(np.float64)
    mean = (lum * weight).sum(1, keepdims=True) / np.maximum(weight.sum(1, keepdims=True), 1.0)
    ratio = np.clip(np.clip(lum / np.maximum(mean, 1e-3), 0.0, 3.0) ** sea.get("contrast", 1.0), 0.0, 1.8)
    near, deep = np.array(sea["near"]), np.array(sea["deep"])
    color = near * (1.0 - t[..., None]) + deep * t[..., None]
    new = np.clip(color * ratio[..., None], 0.0, 1.0)
    a = (w * sea.get("amount", 1.0))[..., None]
    return img * (1.0 - a) + new * a


def speed_lines(img: np.ndarray, lines: list) -> np.ndarray:
    """白いスピード線を描く。lines：(y, 左端 x, 右端 x, 太さ px, 濃さ) を画面の割合で。右端（先）ほど濃く太い"""
    out = img.copy()
    for y, x0, x1, th, a in lines:
        cy = y * H
        xa, xb = int(x0 * W), int(x1 * W)
        ya, yb = int(cy - 3 * th - 2), int(cy + 3 * th + 3)
        xs = np.arange(xa, xb)
        t = (xs - xa) / max(xb - xa - 1, 1)
        alpha = a * np.clip(t, 0, 1) ** 1.3 * np.clip((1.0 - t) / 0.06, 0, 1)      # 先はすこし丸める
        half = th * 0.5 * (0.35 + 0.65 * t)
        ys = np.arange(ya, yb)[:, None]
        prof = np.exp(-0.5 * ((ys - cy) / np.maximum(half, 0.4)) ** 2)
        m = (prof * alpha[None, :])[..., None]
        region = out[ya:yb, xa:xb]
        out[ya:yb, xa:xb] = region * (1.0 - m) + np.array([0.98, 0.99, 1.0]) * m
    return out


def compose(shot: str, folder: Path, tag: str, plate: str = "plate_dof.png", near: bool = True, dof: bool = True) -> dict:
    cfg = SHOTS[shot]
    out = background(shot, plate)
    depth = load_depth(folder, tag)
    layers = {}
    deck = load_layer(folder, tag, "VL_deck")
    wall = load_layer(folder, tag, "VL_wall")
    if dof:
        deck = depth_dof(deck, depth, cfg, near)
        wall = depth_dof(wall, depth, cfg, near)
    chars = load_layer(folder, tag, "VL_chars")
    stack = [("deck", deck, 1.0), ("wall", wall, 1.0)]
    if (folder / f"{tag}_VL_p2trail.npy").exists():   # 吹っ飛ぶプレイヤーの残像の尾は、くっきりした本体の下に
        stack.append(("trail", load_layer(folder, tag, "VL_p2trail"), cfg.get("trail_gain", 1.0)))
    stack.append(("chars", chars, 1.0))
    for name, rgba, gain in stack:
        rgb, a = to_display(rgba)
        if gain != 1.0:
            a = 1.0 - (1.0 - a) ** gain
        layers[name] = (rgb, a)
        out = over(out, rgb, a)
    fx = fx_layer(shot)
    if fx is not None:
        color, a = fx
        out = color + out * (1.0 - a[..., None])
        layers["fx"] = fx
    if cfg.get("speed_lines"):
        out = speed_lines(out, cfg["speed_lines"])
    return {"image": out, "layers": layers, "depth": depth}


def save(img: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(path)
    print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path)


def calibrate(shot: str) -> None:
    """背景の絵で、ぼけきった遠い所を、ぼけなしの絵を円でぼかしたものと比べ、いちばん近い半径を探す"""
    ex = export_dir(shot)
    sharp = srgb_decode(load_srgb(ex / "plate_nodof.png"))
    soft = srgb_decode(load_srgb(ex / "plate_dof.png"))
    (r0, r1), (c0, c1) = SHOTS[shot]["calib_box"]
    box = (slice(r0, r1), slice(c0, c1))
    best = None
    for r in np.arange(3.0, 22.1, 0.5):
        b = blur(sharp, r)
        err = float(np.abs(b[box] - soft[box]).mean())
        if best is None or err < best[1]:
            best = (float(r), err)
        print(f"r={r:5.1f}  err={err:.5f}")
    print("best", best)


def finish_thumbnail(shot: str, img: np.ndarray, dst_stem: Path) -> None:
    """docs/pv/thumbnail/finish.py と同じ仕上げ（そのショットの設定）：色、周辺、ロゴの下、輪郭、ロゴ"""
    sys.path.insert(0, str(HERE.parent))
    import finish as F
    from PIL import ImageFilter
    cfg = F.SHOTS[shot]
    # 8 bit にするときに ±0.5 段のディザを入れる（空のなめらかな色の変化に縞が出ないように）
    dither = np.random.default_rng(7).uniform(-0.5, 0.5, img.shape)
    im = Image.fromarray(np.clip(img * 255.0 + 0.5 + dither, 0, 255).astype(np.uint8))
    im = F.grade(im)
    im = F.calm_title_zone(im, cfg["zone_blur"], cfg["zone_shade"], cfg["zone_end"])
    im = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=25, threshold=3))   # 4K から縮めたので弱め
    im = F.put_logo(im, cfg.get("logo_x", F.LOGO_X), cfg.get("logo_w", F.LOGO_W))
    dst_stem.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst_stem.with_suffix(".png"))
    im.save(dst_stem.with_suffix(".jpg"), quality=95, optimize=True, subsampling=0)
    for suffix in (".png", ".jpg"):
        p = dst_stem.with_suffix(suffix)
        print(f"{p.relative_to(ROOT)}  {p.stat().st_size / 1024:.0f} KB")


def main() -> None:
    args = sys.argv[1:]
    shot = args[0]
    if args[1:2] == ["calibrate"]:
        calibrate(shot)
        return
    tag = args[1]
    rest = args[2:]
    opts = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in rest if "=" in a}
    flags = [a for a in rest if "=" not in a]
    name = flags[0] if flags and flags[0] not in ("final", "nonear") else f"{shot}_{tag}"
    folder = Path(opts["layers"]) if "layers" in opts else ROOT / f"artifacts/pv_capture/thumb_{shot}_blender"
    res = compose(shot, folder, tag, near="nonear" not in flags)
    save(res["image"], OUT / f"{name}.png")
    if "final" in flags:
        finish_thumbnail(shot, res["image"], HERE.parent / "final" / f"{shot}_blender")


if __name__ == "__main__":
    main()
