"""AIQUIZ ONLINE HELIPORT のテクスチャ（手続き。numpy の距離場で描き、PNG に書き出す）。

どれも決まった乱数の種で描くので、作り直しても同じ画像になる。色は sRGB の値で描いて、そのまま 8bit の PNG にする。
- ohp_pad_deck.png  パッドの床（2048²、外接円の直径 2 × PAD_R を覆う）：アルミの床板の溝、塗装、滑り止め、タイヤ跡、
                    外周の白線、黄色の接地円、白い H（足を機体の前後にそろえる）。標示の塗装は少し剥げる
- ohp_net.png       安全ネット（512²、1m 四方で繰り返す。網の目だけ不透明）
v1 のハブの床・渡り廊下のグレーチングは、パッド 1 つにしたので描かない。
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
import numpy as np

import ohp_common as K


def _rgb(h: str):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def _grid(n: int, half: float, cx=0.0, cy=0.0):
    """画素の中心の座標（m）。行 0 が下（Blender の画像の並び）。"""
    s = ((np.arange(n, dtype=np.float32) + 0.5) / n * 2.0 - 1.0) * half
    x, y = np.meshgrid(s + cx, s + cy)
    return x, y


def _cover(sd, aa):
    """符号付き距離（内側が負）→ 被覆率（アンチエイリアス幅 aa）。"""
    return np.clip(0.5 - sd / aa, 0.0, 1.0)


def _box(x, y, cx, cy, hx, hy):
    dx = np.abs(x - cx) - hx
    dy = np.abs(y - cy) - hy
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0)


def _octagon(x, y, apothem):
    d = None
    for k in range(8):
        a = k * math.pi / 4
        v = x * math.cos(a) + y * math.sin(a) - apothem
        d = v if d is None else np.maximum(d, v)
    return d


def _value_noise(n: int, cells: int, rng, octaves=1):
    """繰り返しのある値ノイズ（0〜1）。cells は 1 辺のセル数。"""
    out = np.zeros((n, n), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = rng.random((c, c)).astype(np.float32)
        t = (np.arange(n, dtype=np.float32) + 0.5) / n * c
        i0 = np.floor(t).astype(int) % c
        i1 = (i0 + 1) % c
        f = t - np.floor(t)
        f = f * f * (3 - 2 * f)
        rows = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
        rows1 = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
        out += amp * (rows * (1 - f)[:, None] + rows1 * f[:, None])
        total += amp
        amp *= 0.5
    return out / total


def _save(path: Path, rgb, alpha=None):
    h, w = rgb.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb, 0, 1)
    if alpha is not None:
        rgba[..., 3] = np.clip(alpha, 0, 1)
    name = "_ohp_tmp_" + path.stem
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, w, h, alpha=alpha is not None, float_buffer=False)
    img.pixels.foreach_set(rgba.ravel())
    path.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return str(path)


def _lay(base, colour, cover):
    return base * (1 - cover[..., None]) + colour[None, None, :] * cover[..., None]


# --- パッドの床 --------------------------------------------------------------------
def pad_deck(path: Path, size=2048):
    rng = np.random.default_rng(20261010)
    half = K.PAD_R
    px = 2 * half / size
    aa = px * 1.5
    x, y = _grid(size, half)
    base = _rgb("#3B4743")
    img = np.broadcast_to(base, (size, size, 3)).copy()
    # 大きなムラ（塗り直しの跡）と細かい滑り止めの粒
    mottle = _value_noise(size, 6, rng, octaves=3)
    img *= (0.93 + 0.12 * mottle)[..., None]
    grain = rng.random((size, size)).astype(np.float32)
    img *= (0.96 + 0.08 * grain)[..., None]
    speck = (rng.random((size, size)) > 0.992).astype(np.float32) * 0.35
    img = _lay(img, _rgb("#9AA39F"), speck)
    # アルミの床板：X 方向に走る溝（0.30m おき）と、6m おきにずらした継ぎ目
    plank = 0.30
    gy = np.abs(((y + 50.0) % plank) - plank / 2) - (plank / 2 - 0.012)
    groove = _cover(-gy, aa) * 0.55
    img = _lay(img, _rgb("#242C2A"), groove)
    row = np.floor((y + 50.0) / plank).astype(int)
    joint_x = ((x + 50.0 + (row % 3) * 2.0) % 6.0)
    joint = _cover(np.abs(joint_x - 3.0) - 0.006, aa) * 0.5 * (1 - groove)
    img = _lay(img, _rgb("#1E2524"), joint)
    # 溝の縁のわずかな光（床板の丸み）
    edge_hi = _cover(np.abs(np.abs(((y + 50.0) % plank) - plank / 2) - (plank / 2 - 0.02)) - 0.004, aa) * 0.12
    img = _lay(img, _rgb("#6F7B77"), edge_hi)
    # タイヤ跡（接地点のまわりの長い楕円の汚れ）
    for _ in range(9):
        cx, cy = rng.uniform(-2.6, 2.6), rng.uniform(-2.6, 2.6)
        ang = rng.uniform(0, math.pi)
        a, b = rng.uniform(0.9, 2.2), rng.uniform(0.06, 0.14)
        u = (x - cx) * math.cos(ang) + (y - cy) * math.sin(ang)
        v = -(x - cx) * math.sin(ang) + (y - cy) * math.cos(ang)
        d = np.sqrt((u / a) ** 2 + (v / b) ** 2)
        img = _lay(img, _rgb("#141817"), np.clip(1.0 - d, 0, 1) ** 1.5 * rng.uniform(0.18, 0.32))
    # 油じみ（中央の H の周り）
    stain = np.clip(1.0 - np.hypot(x, y) / 4.2, 0, 1) * (_value_noise(size, 10, rng, 2) > 0.62)
    img = _lay(img, _rgb("#202725"), stain.astype(np.float32) * 0.25)
    # 標示：塗装の剥げ（細かいノイズ）
    chip = _value_noise(size, 150, rng, 2)
    wear = 1.0 - np.clip((chip - 0.60) * 5.0, 0, 1) * 0.45
    apothem = K.PAD_FLAT / 2
    outer = _octagon(x, y, apothem - (K.PAD_RIM_W + 0.06))
    inner = _octagon(x, y, apothem - (K.PAD_RIM_W + 0.06 + 0.30))
    line = _cover(np.maximum(outer, -inner), aa) * wear
    img = _lay(img, _rgb("#E9E6DD"), line)
    # 接地の輪と H（ヘリの真下。H の 2 本の足は機体の向きにそろえる：K.HELI_YAW_DEG）
    hx0, hy0 = K.gxz(K.h2g_xz(0.0, 0.0))
    hx0 -= K.gxz(K.PAD)[0]
    hy0 -= K.gxz(K.PAD)[1]
    r = np.hypot(x - hx0, y - hy0)
    ring = _cover(np.abs(r - K.TD_RING_R) - K.TD_RING_W / 2, aa) * wear
    img = _lay(img, _rgb("#F2C230"), ring)
    # 機体の前後の軸（Blender の床の上）：H の z 軸（機首が -z）を回したもの
    nose = K.gxz(K.h2g_xz(0.0, -1.0))
    ox, oy = K.gxz(K.h2g_xz(0.0, 0.0))
    ax, ay = nose[0] - ox, nose[1] - oy
    u = (x - hx0) * ax + (y - hy0) * ay           # 機体の前後
    v = -(x - hx0) * ay + (y - hy0) * ax          # 機体の左右
    half_leg = K.H_LEG_LEN / 2
    h_sd = np.minimum(np.minimum(_box(u, v, 0.0, -K.H_LEG_GAP, half_leg, K.H_BAR_W / 2),
                                 _box(u, v, 0.0, K.H_LEG_GAP, half_leg, K.H_BAR_W / 2)),
                      _box(u, v, 0.0, 0.0, K.H_BAR_W / 2, K.H_LEG_GAP))
    img = _lay(img, _rgb("#ECE9E2"), _cover(h_sd, aa) * wear)
    return _save(path, img)


# --- ネット ----------------------------------------------------------------------
def net(path: Path, size=512):
    x, y = _grid(size, 0.5, 0.5, 0.5)
    aa = 1.0 / size * 1.5
    pitch = 1.0 / 8
    a = np.abs(((x + y) % pitch) - pitch / 2) * math.sqrt(0.5)
    b = np.abs(((x - y) % pitch) - pitch / 2) * math.sqrt(0.5)
    edge = pitch / 2 * math.sqrt(0.5)
    line_a = _cover(edge - a - 0.0055, aa)
    line_b = _cover(edge - b - 0.0055, aa)
    line = np.maximum(line_a, line_b)
    rgb = np.broadcast_to(_rgb("#2E3338"), (size, size, 3)).copy()
    rgb = _lay(rgb, _rgb("#4A5258"), line_a * line_b * 0.8)     # 結び目を少し明るく
    return _save(path, rgb, line)


def build_all():
    K.TEX.mkdir(parents=True, exist_ok=True)
    return {
        "pad": pad_deck(K.TEX / "ohp_pad_deck.png"),
        "net": net(K.TEX / "ohp_net.png"),
    }
