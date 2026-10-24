"""スカイゲートの体積雲（レイマーチ）の素を焼く：雲の形の濃さ（3D）6 つ・細かいノイズ（3D）・海に落とす影の形（2D）。

参考：ユーザーが示した UE の体積雲（fab.com の VolumeCloud-Using RayMarching。Houdini の体積マップを
レイマーチで描く）と同じ考え。形は「積雲のもくもく（大きな球の上に小さな球が重なる）」を符号付き距離の
なめらかな和で作り、低い周波数のノイズで形をゆがめ、底を平らにする。細かいふちの崩れ（ちぎれ・すじ）は
Godot のシェーダーが細かいノイズ（Perlin-Worley）で削る。

    python assets/sudden_death/sky_fx/source/clouds/bake_cloud_volumes.py

書くもの：
  source/clouds/cloud_shapes.bin・cloud_detail.bin・cloud_volumes.json（Godot の変換スクリプトが読む）
  assets/sudden_death/sky_fx/sky_fx_cloud_shadows.png（形ごとの真上から見た濃さ。海の影の板が使う）
  source/previews/clouds_*.png（形の確認：横と真上から見た濃さ）
変換：Godot で scripts/world/sudden_death/sky_fx/tools/sky_fx_cloud_import.gd を実行すると、
  assets/sudden_death/sky_fx/sky_fx_cloud_shapes.res・sky_fx_cloud_detail.res（ImageTexture3D）ができる。
座標：箱の中の位置（x 右、y 上、z 手前）。形ごとの箱の縦横比 aspect は json に書く（Godot はこの比で箱を伸ばす）。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
ASSET = SOURCE.parent
PREVIEWS = SOURCE / "previews"

NX, NY, NZ = 96, 64, 96       # 形 1 つの格子（x, y, z）
PAD = 2                       # 形と形の間の空の層（線形の補間がとなりの形ににじまないように）
DN = 64                       # 細かいノイズの格子（くり返し）
EDGE = 0.05                   # ふちの柔らかさ（箱の幅に対する比）

# 形：名前・箱の縦横比（x, y, z）・作り方
SHAPES = [
    {"name": "tower", "aspect": [1.0, 0.85, 1.0], "kind": "cumulus", "core": 6, "spread": 0.2, "lift": 0.34, "levels": 3, "seed": 11},
    {"name": "cumulus", "aspect": [1.0, 0.6, 1.0], "kind": "cumulus", "core": 7, "spread": 0.26, "lift": 0.16, "levels": 3, "seed": 23},
    {"name": "deck_a", "aspect": [1.0, 0.32, 1.0], "kind": "deck", "core": 16, "spread": 0.36, "lift": 0.0, "levels": 2, "seed": 37},
    {"name": "deck_b", "aspect": [1.0, 0.3, 1.0], "kind": "deck", "core": 13, "spread": 0.34, "lift": 0.0, "levels": 2, "seed": 41},
    {"name": "small", "aspect": [1.0, 0.6, 1.0], "kind": "cumulus", "core": 3, "spread": 0.14, "lift": 0.08, "levels": 2, "seed": 53},
    {"name": "wisp", "aspect": [1.0, 0.45, 1.0], "kind": "wisp", "core": 14, "spread": 0.34, "lift": 0.0, "levels": 2, "seed": 67},
]


# ------------------------------------------------------------------ ノイズ
def gradient_noise(p: np.ndarray, period: int, seed: int) -> np.ndarray:
    """くり返す Perlin のノイズ（およそ -1..1）。p は (..., 3)、格子の単位。"""
    rng = np.random.default_rng(seed)
    g = rng.normal(size=(period, period, period, 3))
    g /= np.linalg.norm(g, axis=-1, keepdims=True)
    i0 = np.floor(p).astype(np.int64)
    f = p - i0
    u = f * f * f * (f * (f * 6 - 15) + 10)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                idx = (i0 + np.array([dx, dy, dz])) % period
                grad = g[idx[..., 0], idx[..., 1], idx[..., 2]]
                d = f - np.array([dx, dy, dz])
                dot = np.sum(grad * d, axis=-1)
                w = (u[..., 0] if dx else 1 - u[..., 0]) * (u[..., 1] if dy else 1 - u[..., 1]) * (u[..., 2] if dz else 1 - u[..., 2])
                out = out + w * dot
    return out * 1.6


def worley(p: np.ndarray, cells: int, seed: int) -> np.ndarray:
    """くり返す Worley（いちばん近い点までの距離、0..約1）。p は (..., 3)、格子の単位（0..cells）。"""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, cells, 3))
    c0 = np.floor(p).astype(np.int64)
    best = np.full(p.shape[:-1], 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                off = np.array([dx, dy, dz])
                c = c0 + off
                cw = c % cells
                feat = c + pts[cw[..., 0], cw[..., 1], cw[..., 2]]
                d = np.linalg.norm(p - feat, axis=-1)
                best = np.minimum(best, d)
    return np.clip(best, 0.0, 1.0)


def fbm_noise(p: np.ndarray, base: int, octaves: int, seed: int) -> np.ndarray:
    v = 0.0
    a = 0.5
    tot = 0.0
    for o in range(octaves):
        per = base * (2 ** o)
        v = v + a * gradient_noise(p * per, per, seed + o * 17)
        tot += a
        a *= 0.5
    return v / tot


def worley_fbm(p: np.ndarray, base: int, seed: int) -> np.ndarray:
    return (worley(p * base, base, seed) * 0.625 + worley(p * base * 2, base * 2, seed + 1) * 0.25
            + worley(p * base * 4, base * 4, seed + 2) * 0.125)


def remap(v, lo, hi, nlo, nhi):
    return nlo + (v - lo) / (hi - lo) * (nhi - nlo)


# ------------------------------------------------------------------ 形
def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def make_balls(spec, rng):
    """球の並び（x, y, z, r）。箱の物理の座標（x, z は ±0.5×aspect、y は ±0.5×aspect_y）。"""
    ax, ay, az = spec["aspect"]
    base = -0.5 * ay + 0.06 * ay
    balls = []
    kind = spec["kind"]
    spread = spec["spread"]
    for i in range(spec["core"]):
        a = rng.uniform(0, 2 * math.pi)
        rr = spread * math.sqrt(rng.uniform(0.0, 1.0))
        x, z = math.cos(a) * rr * ax, math.sin(a) * rr * az
        if kind == "deck":
            r = rng.uniform(0.09, 0.14) * ax
            y = base + r * rng.uniform(0.35, 0.8)
        elif kind == "wisp":
            r = rng.uniform(0.05, 0.09) * ax
            y = base + ay * rng.uniform(0.15, 0.5)
        else:
            r = rng.uniform(0.15, 0.22) * ax * (1.15 - rr / max(spread, 1e-3) * 0.45)
            # 真ん中ほど高く盛り上がる（積雲の頭）
            y = base + r * 0.7 + spec["lift"] * ay * (1.0 - rr / max(spread, 1e-3)) * 1.6
        balls.append([x, y, z, r])
    # もくもく：上を向いた面に小さな球を重ねる（3 段）
    for level in range(spec["levels"]):
        new = []
        for x, y, z, r in balls:
            n = 3 if kind != "wisp" else 2
            for _ in range(n):
                th = rng.uniform(0, 2 * math.pi)
                el = rng.uniform(0.25, 1.35) if kind != "deck" else rng.uniform(0.15, 0.9)
                d = np.array([math.cos(th) * math.cos(el), math.sin(el), math.sin(th) * math.cos(el)])
                cr = r * rng.uniform(0.42, 0.6)
                c = np.array([x, y, z]) + d * r * rng.uniform(0.62, 0.82)
                new.append([c[0], c[1], c[2], cr])
        balls += new
    b = np.array(balls)
    # 箱にいっぱいに広げる：横の広がりを 0.44×幅、上を 0.46×高さに（丸さを保って一様に）
    ext = max(np.max(np.abs(b[:, 0]) + b[:, 3]) / ax, np.max(np.abs(b[:, 2]) + b[:, 3]) / az)
    top = np.max(b[:, 1] + b[:, 3])
    s = min(0.45 / ext, (0.46 * ay - base) / max(top - base, 1e-6))
    b[:, 0] *= s
    b[:, 2] *= s
    b[:, 1] = base + (b[:, 1] - base) * s
    b[:, 3] *= s
    return b, base


def shape_density(spec, P, warp):
    rng = np.random.default_rng(spec["seed"])
    balls, base = make_balls(spec, rng)
    ax, ay, az = spec["aspect"]
    # 形をゆがめる（自然な不ぞろい）
    Q = P + warp * np.array([0.05 * ax, 0.035 * ay, 0.05 * az])
    sdf = np.full(P.shape[:-1], 9.0)
    k = 0.03 * ax
    for x, y, z, r in balls:
        d = np.linalg.norm(Q - np.array([x, y, z]), axis=-1) - r
        sdf = smin(sdf, d, k)
    # 底を平らに（なめらかに切る）
    sdf = smax(sdf, base - Q[..., 1], 0.02 * ay)
    if spec["kind"] == "wisp":
        # ちぎれ雲：ノイズで大きく削る
        sdf = sdf + 0.012 * ax * (warp[..., 0] + 0.3)
    dens = np.clip(-sdf / (EDGE * ax), 0.0, 1.0)
    # 箱のふちは必ず 0（箱の外とつなぐ）
    m = 0.03
    bx = np.clip((0.5 * ax - np.abs(P[..., 0])) / (m * ax), 0, 1)
    by = np.clip((0.5 * ay - np.abs(P[..., 1])) / (m * ay), 0, 1)
    bz = np.clip((0.5 * az - np.abs(P[..., 2])) / (m * az), 0, 1)
    dens *= bx * by * bz
    return dens, len(balls)


def main():
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    # 格子の点（形ごとに物理の比で）
    gx = (np.arange(NX) + 0.5) / NX - 0.5
    gy = (np.arange(NY) + 0.5) / NY - 0.5
    gz = (np.arange(NZ) + 0.5) / NZ - 0.5
    shapes_bytes = bytearray()
    shadow_cols = []
    meta_shapes = []
    for si, spec in enumerate(SHAPES):
        ax, ay, az = spec["aspect"]
        X, Y, Z = np.meshgrid(gx * ax, gy * ay, gz * az, indexing="ij")
        P = np.stack([X, Y, Z], axis=-1)
        U = np.stack([X / ax + 0.5, Y / ay + 0.5, Z / az + 0.5], axis=-1)
        warp = np.stack([fbm_noise(U + 0.13 * k, 2, 3, spec["seed"] * 7 + k) for k in range(3)], axis=-1)
        dens, nballs = shape_density(spec, P, warp)
        d8 = np.clip(dens * 255.0 + 0.5, 0, 255).astype(np.uint8)          # [x, y, z]
        empty = np.zeros((NZ, NX), dtype=np.uint8)
        for _ in range(PAD):
            shapes_bytes += empty.tobytes()
        for y in range(NY):
            shapes_bytes += np.ascontiguousarray(d8[:, y, :].T).tobytes()  # 行＝z、列＝x
        for _ in range(PAD):
            shapes_bytes += empty.tobytes()
        # 真上から見た光学的な厚さ → 影の濃さ（0..1）
        tau = dens.sum(axis=1) / NY * ay * 6.0                              # [x, z]
        shadow = 1.0 - np.exp(-tau)
        shadow_cols.append(np.clip(shadow.T * 255.0, 0, 255).astype(np.uint8))  # 行＝z、列＝x
        # 確認の画：横（z へ積む）と真上
        side = 1.0 - np.exp(-dens.sum(axis=2) / NZ * az * 8.0)              # [x, y]
        top = shadow.T
        side_img = Image.fromarray((np.flipud(side.T) * 255).astype(np.uint8)).resize((NX * 3, NY * 3), Image.BILINEAR)
        top_img = Image.fromarray((top * 255).astype(np.uint8)).resize((NX * 2, NZ * 2), Image.BILINEAR)
        sheet = Image.new("L", (NX * 3 + NX * 2 + 8, max(NY * 3, NZ * 2)), 30)
        sheet.paste(side_img, (0, 0))
        sheet.paste(top_img, (NX * 3 + 8, 0))
        sheet.save(PREVIEWS / f"clouds_shape_{si}_{spec['name']}.png")
        fill = float((dens > 0.5).mean())
        meta_shapes.append({"index": si, "name": spec["name"], "aspect": spec["aspect"], "balls": nballs,
                            "fill": round(fill, 4), "edge_max": float(max(dens[0].max(), dens[-1].max(), dens[:, :, 0].max(), dens[:, :, -1].max()))})
        print(f"shape {si} {spec['name']}: balls {nballs} fill {fill:.3f}")
    (HERE / "cloud_shapes.bin").write_bytes(bytes(shapes_bytes))
    Image.fromarray(np.concatenate(shadow_cols, axis=1)).save(ASSET / "sky_fx_cloud_shadows.png")

    # 細かいノイズ（くり返す）：R＝Perlin-Worley（大きめのこぶ）、G＝Worley の重ね（細かいちぎれ）
    g = (np.arange(DN) + 0.5) / DN
    X, Y, Z = np.meshgrid(g, g, g, indexing="ij")
    P = np.stack([X, Y, Z], axis=-1)
    perlin = fbm_noise(P, 4, 4, 101) * 0.5 + 0.5
    wf_low = worley_fbm(P, 4, 201)
    r = np.clip(remap(perlin, 1.0 - wf_low * 0.9 - 0.1, 1.0, 0.0, 1.0), 0.0, 1.0)       # Perlin-Worley
    gch = 1.0 - worley_fbm(P, 8, 301)
    rgb = np.stack([r, gch], axis=-1)
    d8 = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)              # [x, y, z, 2]
    detail = bytearray()
    for y in range(DN):
        detail += np.ascontiguousarray(d8[:, y, :, :].transpose(1, 0, 2)).tobytes()
    (HERE / "cloud_detail.bin").write_bytes(bytes(detail))
    Image.fromarray((np.concatenate([r[:, DN // 2, :], gch[:, DN // 2, :]], axis=1) * 255).astype(np.uint8)).save(PREVIEWS / "clouds_detail_slice.png")

    meta = {
        "note": "スカイゲートの体積雲。bake_cloud_volumes.py が書く。形は ImageTexture3D（幅＝x、高さ＝z、奥行き＝y を形ごとに PAD をはさんで積む）",
        "shape_size": [NX, NY, NZ], "pad": PAD, "edge": EDGE,
        "shapes": meta_shapes,
        "detail_size": DN,
        "shadow_atlas": {"file": "res://assets/sudden_death/sky_fx/sky_fx_cloud_shadows.png", "cell": [NX, NZ], "count": len(SHAPES)},
    }
    (HERE / "cloud_volumes.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    (ASSET / "sky_fx_cloud_volumes.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print("ok", len(shapes_bytes), len(detail))


if __name__ == "__main__":
    main()
