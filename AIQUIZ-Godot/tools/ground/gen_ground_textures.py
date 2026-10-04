#!/usr/bin/env python3
"""Generate the conveyor-belt detail textures for the ground (main game) stage.

Outputs (1024 x 1024, fully seamless, deterministic for a given seed):

    assets/environment/conveyor_stage/textures/belt_detail_albedo.png   grey detail MULTIPLIER, not a colour
    assets/environment/conveyor_stage/textures/belt_detail_normal.png   OpenGL (+Y) normal map (hint_normal)
    assets/environment/conveyor_stage/textures/belt_detail_orm.png      R = AO, G = roughness, B = wear mask
                                                                        (rubbed streaks; the rubber is never metallic)

Run (numpy + Pillow only, no Blender, no Godot, ~10 s):

    python tools/ground/gen_ground_textures.py                  # textures + numeric verification
    python tools/ground/gen_ground_textures.py --preview        # + 3x3 tiling previews in
                                                                #   artifacts/ground_quality/
    python tools/ground/gen_ground_textures.py --seed 7 --out some/dir --no-verify

Re-running with the same seed reproduces the same PNGs. The textures are not imported by this
script; Godot (re)imports them from the hand-written *.png.import files that sit next to them.

Design
------
* The belt colour is user-configurable (shader base_color / stripe_color), so the albedo is a grey
  MULTIPLIER, applied as ``ALBEDO = belt_col * texture(albedo).rgb`` (gain 1.0, source_color).
  8-bit data cannot exceed 1.0, so it only darkens: its mean in linear light is calibrated to
  ``TARGET_LINEAR_MEAN`` (0.94) and the generator prints the exact value / the gain (1/mean) that
  restores a mean of exactly 1.0 if wanted.
* Every field is built either analytically on a period that divides the tile (the plain weave) or
  by FFT filtering of white noise (periodic by construction), so left/right and top/bottom edges
  join exactly. Nothing is cropped or blended to hide a seam.
* One tile is nominally 2.5 m (1 px = 2.44 mm): weave thread pitch 8 px = 1.95 cm (one weave
  repeat = 3.9 cm), micro grain ~1 cm, scuffs and grime 10-60 cm.
* Direction convention: image X = across the belt (world X), image Y = belt travel (world Z).
  Scuffs, scratches and grime streaks are elongated along image Y.
* Nothing larger than ~0.5 m is put in the texture: a big blotch would repeat every tile in the
  same shape. Metre-scale grime and wear come from world-space noise in the belt shader.
* Normal: tangent-space OpenGL, n = normalize(-dh/dx, +dh/drow, 1) (rows run downward, +Y is up).
"""
from __future__ import annotations

import argparse
import hashlib
import math
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------- configuration
SEED = 20261003
N = 1024                      # texture size (px)
TILE_M = 2.5                  # nominal metres per tile
CELL = 8                      # weave thread pitch (px); must divide N and N // CELL must be even
NC = N // CELL

TARGET_LINEAR_MEAN = 0.94     # albedo mean in linear light (multiplier; 1.0 = no change)
NORMAL_STRENGTH = 1.0         # slope multiplier (height is expressed in pixels)
ROUGH_MIN, ROUGH_MAX = 0.70, 0.90

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "assets" / "environment" / "conveyor_stage" / "textures"
PREVIEW_DIR = REPO / "artifacts" / "ground_quality"

_FX = np.fft.fftfreq(N)[None, :]
_FY = np.fft.fftfreq(N)[:, None]


# --------------------------------------------------------------------------- periodic helpers
def stream(seed: int, name: str) -> np.random.Generator:
    """Independent RNG per feature, so editing one feature never shifts the others."""
    return np.random.default_rng([seed, zlib.crc32(name.encode("utf-8"))])


def blur(a: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    """Gaussian blur with periodic boundaries (sigma in px; sy defaults to sx)."""
    sy = sx if sy is None else sy
    g = np.exp(-2.0 * math.pi ** 2 * ((_FX * sx) ** 2 + (_FY * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def gnoise(rng: np.random.Generator, sx: float, sy: float | None = None) -> np.ndarray:
    """Periodic Gaussian noise, zero mean, unit std. sx/sy = feature sigma in px (anisotropic ok)."""
    a = blur(rng.standard_normal((N, N)), sx, sy)
    a -= a.mean()
    return a / a.std()


def fbm(rng: np.random.Generator, sigmas, weights, aniso: float = 1.0) -> np.ndarray:
    """Sum of periodic noises. aniso > 1 stretches every octave along image Y (belt travel)."""
    out = np.zeros((N, N))
    for s, w in zip(sigmas, weights):
        out += w * gnoise(rng, s, s * aniso)
    return out / math.sqrt(sum(w * w for w in weights))


def unit(a: np.ndarray, lo: float = 1.0, hi: float = 99.0) -> np.ndarray:
    p0, p1 = np.percentile(a, [lo, hi])
    return np.clip((a - p0) / (p1 - p0), 0.0, 1.0)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def impulses(rng: np.random.Generator, count: int, amp_sigma: float = 0.5) -> np.ndarray:
    """Sparse random impulse field, lognormal amplitudes (clamped to [0.25, 1])."""
    f = np.zeros((N, N))
    ys = rng.integers(0, N, count)
    xs = rng.integers(0, N, count)
    amp = np.clip(np.exp(rng.normal(-0.3, amp_sigma, count)), 0.25, 1.0)
    np.add.at(f, (ys, xs), amp)
    return f


def srgb_encode(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def srgb_decode(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


# --------------------------------------------------------------------------- feature layers
def make_weave(seed: int) -> tuple[np.ndarray, np.ndarray]:
    """Plain-weave fabric imprint. Returns (height in 0..~1, fiber-modulated height).

    Each cell (CELL x CELL px) is one thread crossing; warp threads run along image Y, weft along
    X. A thread is a rounded ridge across its width whose elevation alternates over/under from
    cell to cell, and the two ridge fields are merged with a p-norm (soft max) so crossings are
    rounded. Domain warping makes the threads waver by a pixel or two like a stretched rubber skin.
    """
    r = stream(seed, "weave")
    X, Y = np.meshgrid(np.arange(N) + 0.5, np.arange(N) + 0.5)
    xs = X + 1.7 * gnoise(r, 34.0) + 0.5 * gnoise(r, 9.0)
    ys = Y + 1.7 * gnoise(r, 34.0) + 0.5 * gnoise(r, 9.0)

    cx, cy = xs / CELL, ys / CELL
    ii, jj = np.floor(cx), np.floor(cy)
    u, v = cx - ii, cy - jj
    im, jm = ii.astype(np.int64) % NC, jj.astype(np.int64) % NC

    amp_w = np.clip(1.0 + 0.10 * r.standard_normal(NC), 0.7, 1.3)    # per-thread height jitter
    amp_f = np.clip(1.0 + 0.10 * r.standard_normal(NC), 0.7, 1.3)

    q = 1.15
    prof_w = np.sin(math.pi * u) ** q                                 # across a warp thread
    prof_f = np.sin(math.pi * v) ** q                                 # across a weft thread
    z_w = np.cos(math.pi * (cy - 0.5 + ii))                           # +1 over / -1 under, along the thread
    z_f = -np.cos(math.pi * (cx - 0.5 + jj))
    h_w = prof_w * (0.55 + 0.45 * z_w) * amp_w[im]
    h_f = prof_f * (0.55 + 0.45 * z_f) * amp_f[jm]
    p = 3.0
    h = (h_w ** p + h_f ** p) ** (1.0 / p)

    # slow variation of how pronounced the imprint is (rubber is not stamped evenly)
    h *= 0.88 + 0.12 * gnoise(r, 70.0)

    # filaments: fine streaks that follow the thread that is on top
    fib_w = gnoise(r, 0.55, 6.0)                                      # along Y
    fib_f = gnoise(r, 6.0, 0.55)                                      # along X
    top = np.where(h_w >= h_f, fib_w, fib_f)
    h_fiber = h + 0.075 * top * np.clip(h, 0.0, 1.0)

    return blur(h, 0.45), blur(h_fiber, 0.45)


def make_scratches(seed: int, count: int = 300) -> np.ndarray:
    """Thin abrasion lines, mostly along belt travel (image Y). Returns 0..~1 coverage."""
    r = stream(seed, "scratches")
    acc = np.zeros((N, N))
    for _ in range(count):
        x0, y0 = r.uniform(0, N, 2)
        length = float(np.clip(np.exp(r.normal(4.9, 0.55)), 25.0, 520.0))
        ang = r.normal(0.0, math.radians(5.0)) if r.random() < 0.85 else r.uniform(-1.1, 1.1)
        amp = float(np.clip(np.exp(r.normal(-0.4, 0.5)), 0.2, 1.0))
        t = np.arange(0.0, length, 0.5)
        env = np.sin(math.pi * t / length) ** 0.6
        x = x0 + math.sin(ang) * t + 1.5 * np.sin(t / 37.0 + r.uniform(0, 6.3))
        y = y0 + math.cos(ang) * t
        np.add.at(acc, (np.round(y).astype(np.int64) % N, np.round(x).astype(np.int64) % N), amp * env * 0.5)
    return np.clip(blur(acc, 0.75), 0.0, None) * 1.6


def make_pits(seed: int) -> np.ndarray:
    """Small round nicks / pits of three sizes. 0..1 (unit peak per pit, overlapping adds, clipped)."""
    r = stream(seed, "pits")
    out = np.zeros((N, N))
    for sigma, count in ((1.3, 260), (2.4, 50), (4.2, 8)):
        f = blur(impulses(r, count), sigma) * (2.0 * math.pi * sigma * sigma)
        out += f
    return np.clip(out, 0.0, 1.0)


def elongated_marks(r: np.random.Generator, layers) -> np.ndarray:
    """Sum of soft elliptical marks stretched along image Y: layers = ((sigma_x, sigma_y, count), ...).
    Each mark peaks at its (lognormal) amplitude; overlaps add."""
    acc = np.zeros((N, N))
    for sx, sy, count in layers:
        acc += blur(impulses(r, count, 0.45), sx, sy) * (2.0 * math.pi * sx * sy)
    return acc


def make_polish(seed: int) -> np.ndarray:
    """Abraded / polished streaks along belt travel (image Y), 0..1: rubbed rubber is a little lighter
    and smoother and its weave is flattened. Many small marks and a few longer ones, no large blotch,
    so the 2.5 m repeat has no landmark. Written to ORM blue; the shader lightens with it."""
    r = stream(seed, "polish")
    acc = elongated_marks(r, ((3.0, 34.0, 150), (6.0, 80.0, 55), (10.0, 150.0, 12)))
    acc = 1.0 - np.exp(-1.7 * acc)                                    # soft saturation where marks overlap
    fine = 0.5 + 0.5 * np.tanh(1.3 * gnoise(r, 0.9, 14.0))            # made of fine rub lines
    return np.clip(acc * (0.5 + 0.7 * fine), 0.0, 1.0)


def make_skids(seed: int) -> np.ndarray:
    """Short dark marks of rubber and dirt dragged along travel, 0..1."""
    r = stream(seed, "skids")
    acc = elongated_marks(r, ((1.8, 16.0, 80), (3.5, 34.0, 28)))
    fine = 0.5 + 0.5 * np.tanh(gnoise(r, 0.8, 9.0))
    return np.clip(acc * (0.6 + 0.6 * fine), 0.0, 1.0)


# --------------------------------------------------------------------------- composition
def build(seed: int) -> dict[str, np.ndarray]:
    r = stream(seed, "fields")
    weave, weave_fiber = make_weave(seed)
    hn = unit(weave, 0.5, 99.5)                                       # 0 valley .. 1 ridge top
    scratches = make_scratches(seed)
    pits = make_pits(seed)

    # wear: streaks along travel where the belt has been rubbed smooth (weave flattened, glossier,
    # lighter in the shader via ORM blue). Larger-scale dirt and wear are left to the shader's world
    # noise: anything big in here would repeat every tile.
    wear = make_polish(seed)
    skids = make_skids(seed)
    # grime: fine dirt, plus streaks of transferred dirt along travel
    grime = unit(fbm(r, (20.0, 9.0, 4.0), (1.0, 0.8, 0.5)), 2, 98)
    streaks = unit(fbm(r, (4.0, 10.0), (1.0, 0.7), aniso=18.0), 2, 98)
    mottle = gnoise(r, 2.6)                                           # fine mottling of the rubber
    undul = fbm(r, (120.0, 55.0, 24.0), (1.0, 0.6, 0.3))              # gentle surface undulation
    grain = gnoise(r, 0.8)                                            # micro grain

    # ---- height (px units) -> normal
    height = (
        1.05 * weave_fiber * (1.0 - 0.55 * wear)
        + 0.55 * undul
        + 0.075 * grain * (1.0 - 0.35 * wear)
        - 0.60 * scratches
        - 1.00 * pits
        - 0.25 * skids
    )
    dhdx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5
    dhdr = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5
    nrm = np.stack([-dhdx * NORMAL_STRENGTH, dhdr * NORMAL_STRENGTH, np.ones_like(height)], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)

    # ---- albedo multiplier (linear light, <= 1)
    valley = (1.0 - hn) ** 1.2
    dark = (
        0.130 * valley * (1.0 - 0.40 * wear)       # dirt packed into the weave
        + 0.014 * grime                            # fine grime
        + 0.050 * smoothstep(0.45, 0.85, streaks)  # transferred dirt along travel
        + 0.070 * skids                            # dragged rubber / dirt marks
        + 0.040 * (0.5 + 0.5 * np.tanh(mottle))    # fine mottling
        + 0.200 * pits                             # nicks are dark
        - 0.020 * wear                             # rubbed areas read cleaner
        - 0.060 * np.clip(scratches, 0, 1)         # fresh scratches show lighter rubber
    )
    def knee(x: np.ndarray, e: float = 0.03) -> np.ndarray:
        """Soft rectifier: ~max(x, 0) with a rounded corner, so near-white areas keep a little detail."""
        return 0.5 * (x + np.sqrt(x * x + e * e))

    lo, hi = -0.4, 0.6
    for _ in range(60):                            # solve the offset so the linear mean hits the target
        mid = 0.5 * (lo + hi)
        if np.clip(1.0 - knee(dark + mid), 0.0, 1.0).mean() > TARGET_LINEAR_MEAN:
            lo = mid
        else:
            hi = mid
    offset = 0.5 * (lo + hi)
    albedo_lin = np.clip(1.0 - knee(dark + offset), 0.0, 1.0)

    # ---- ORM
    ao = 1.0 - 0.50 * valley ** 1.5 * (1.0 - 0.30 * wear) - 0.40 * pits - 0.03 * grime
    ao = np.clip(ao, 0.30, 1.0)
    rough_raw = (0.835 - 0.030 * hn + 0.020 * grime - 0.020 * mottle * 0.5 - 0.085 * wear
                 + 0.020 * np.clip(scratches, 0, 1) + 0.015 * skids)
    mid_r, half = 0.5 * (ROUGH_MIN + ROUGH_MAX), 0.5 * (ROUGH_MAX - ROUGH_MIN)
    rough = mid_r + half * np.tanh((rough_raw - mid_r) / (half * 0.9))   # soft clamp strictly inside [min, max]
    # The rubber is not metallic: blue carries the wear (polish) mask instead.
    polish = np.clip(wear, 0.0, 1.0)

    return {
        "albedo_lin": albedo_lin, "normal": nrm, "ao": ao, "rough": rough, "polish": polish,
        "offset": np.array(offset), "wear": wear, "hn": hn,
    }


def to_images(f: dict[str, np.ndarray]) -> dict[str, Image.Image]:
    g8 = np.round(srgb_encode(f["albedo_lin"]) * 255.0).astype(np.uint8)
    albedo = Image.fromarray(np.dstack([g8, g8, g8]), "RGB")
    n8 = np.round((f["normal"] * 0.5 + 0.5) * 255.0).astype(np.uint8)
    normal = Image.fromarray(n8, "RGB")
    orm8 = np.round(np.dstack([f["ao"], f["rough"], f["polish"]]) * 255.0).astype(np.uint8)
    orm = Image.fromarray(orm8, "RGB")
    return {"belt_detail_albedo.png": albedo, "belt_detail_normal.png": normal, "belt_detail_orm.png": orm}


# --------------------------------------------------------------------------- verification
def _seam_stats(a: np.ndarray) -> dict[str, float]:
    """Mean |neighbour difference| across the wrap seam vs interior neighbours, per axis.

    The seam pair is also a weave cell boundary (N % CELL == 0), and thread boundaries differ
    statistically from thread centres, so besides the plain interior mean the seam is compared with
    the interior pairs of the same weave phase (columns/rows 8k-1 | 8k).
    """
    a = a.astype(np.float64)
    out = {}
    for ax, tag in ((1, "LR"), (0, "TB")):
        d = np.abs(np.diff(a, axis=ax)).mean(axis=0 if ax == 1 else 1)        # length N-1, index i = pair (i, i+1)
        seam = float(np.abs(np.take(a, 0, axis=ax) - np.take(a, N - 1, axis=ax)).mean())
        same_phase = d[CELL - 1::CELL]                                          # pairs (8k-1, 8k)
        out[tag + "_seam"] = seam
        out[tag + "_all"] = float(d.mean())
        out[tag + "_phase_mean"] = float(same_phase.mean())
        out[tag + "_phase_max"] = float(same_phase.max())
    return out


def verify(out_dir: Path, fields: dict[str, np.ndarray]) -> bool:
    ok = True
    load = lambda name: np.asarray(Image.open(out_dir / name))
    alb, nor, orm = load("belt_detail_albedo.png"), load("belt_detail_normal.png"), load("belt_detail_orm.png")
    print("--- verification (from the written PNG files) ---")
    for name, a in (("albedo", alb), ("normal", nor), ("orm", orm)):
        print(f"{name:7s} shape={a.shape} dtype={a.dtype}")

    lin = srgb_decode(alb[..., 0] / 255.0)
    mean_lin = float(lin.mean())
    print(f"albedo: R==G==B: {bool((alb[..., 0] == alb[..., 1]).all() and (alb[..., 1] == alb[..., 2]).all())}")
    print(f"albedo: sRGB8 mean={alb[..., 0].mean():.1f} min={alb.min()} max={alb.max()} "
          f"p1={np.percentile(alb[..., 0], 1):.0f} p99={np.percentile(alb[..., 0], 99):.0f}")
    print(f"albedo: linear mean={mean_lin:.4f} (target {TARGET_LINEAR_MEAN}, accepted 0.90..1.10) "
          f"std={lin.std():.4f} min={lin.min():.3f} max={lin.max():.3f} "
          f"clipped(>=0.999)={(lin >= 0.999).mean() * 100:.1f}% gain_to_unity={1.0 / mean_lin:.3f}")
    ok &= 0.90 <= mean_lin <= 1.10

    n = nor.astype(np.float64) / 255.0 * 2.0 - 1.0
    ln = np.linalg.norm(n, axis=-1)
    print(f"normal: |n| mean={ln.mean():.4f} min={ln.min():.4f} max={ln.max():.4f}; "
          f"mean xyz=({n[..., 0].mean():+.4f}, {n[..., 1].mean():+.4f}, {n[..., 2].mean():+.4f}); "
          f"std x={n[..., 0].std():.3f} y={n[..., 1].std():.3f}; min z={n[..., 2].min():.3f}; "
          f"max tilt={math.degrees(math.acos(n[..., 2].min())):.1f} deg")
    ok &= abs(ln.mean() - 1.0) < 0.01 and ln.min() > 0.97 and ln.max() < 1.03

    o = orm.astype(np.float64) / 255.0
    for i, nm in enumerate(("AO   (R)", "rough(G)", "wear (B)")):
        print(f"orm {nm}: min={o[..., i].min():.3f} mean={o[..., i].mean():.3f} max={o[..., i].max():.3f}")
    print(f"orm wear(B): area > 0.5 = {(o[..., 2] > 0.5).mean() * 100:.1f}%")
    ok &= 0.695 <= o[..., 1].min() and o[..., 1].max() <= 0.905 and 0.02 <= o[..., 2].mean() <= 0.4

    print("seam continuity: mean |diff| of neighbouring pixels across the wrap seam vs the interior")
    print("  (interior = all neighbour pairs / only pairs at the same weave phase as the seam)")
    chans = {"albedo": alb[..., 0], "normal.x": nor[..., 0], "normal.y": nor[..., 1],
             "orm.ao": orm[..., 0], "orm.rough": orm[..., 1], "orm.wear": orm[..., 2]}
    for nm, a in chans.items():
        st = _seam_stats(a)
        parts = []
        for tag in ("LR", "TB"):
            r_all = st[tag + "_seam"] / max(st[tag + "_all"], 1e-9)
            r_ph = st[tag + "_seam"] / max(st[tag + "_phase_mean"], 1e-9)
            mx = st[tag + "_seam"] / max(st[tag + "_phase_max"], 1e-9)
            parts.append(f"{tag} seam {st[tag + '_seam']:6.3f} | x{r_all:.2f} all, x{r_ph:.2f} same-phase, x{mx:.2f} of same-phase max")
            ok &= r_ph <= 1.3 and mx <= 1.15
        print(f"  {nm:10s} " + " || ".join(parts))
    print(f"worn area fraction (wear>0.5): {(fields['wear'] > 0.5).mean() * 100:.1f}%; "
          f"albedo offset solved: {float(fields['offset']):+.4f}")
    print("RESULT:", "OK" if ok else "CHECK FAILED")
    return ok


# --------------------------------------------------------------------------- previews
def write_previews(fields: dict[str, np.ndarray], images: dict[str, Image.Image]) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    # Lit 3x3: albedo multiplier x a typical belt colour, normal-mapped Lambert + Blinn-Phong, top-down.
    belt = np.array([0.40, 0.41, 0.42])                    # shader default base_color (linear)
    nrm = fields["normal"]
    light = np.array([-0.55, 0.45, 0.70])
    light /= np.linalg.norm(light)
    ndl = np.clip(nrm @ light, 0.0, 1.0)
    half = light + np.array([0.0, 0.0, 1.0])
    half /= np.linalg.norm(half)
    ndh = np.clip(nrm @ half, 0.0, 1.0)
    shin = 2.0 / np.maximum(fields["rough"] ** 4, 1e-3) - 2.0
    spec = ((shin + 2.0) / 8.0) * ndh ** shin * 0.04 * ndl
    ao = fields["ao"]
    col = fields["albedo_lin"][..., None] * belt * (0.22 * ao[..., None] + 1.35 * ndl[..., None] * ao[..., None] ** 0.5) \
        + spec[..., None] * ao[..., None]
    lit = np.round(srgb_encode(np.clip(col, 0.0, 1.0)) * 255.0).astype(np.uint8)
    tile3 = np.tile(lit, (3, 3, 1))
    Image.fromarray(tile3, "RGB").save(PREVIEW_DIR / "texture_preview.png", optimize=False, compress_level=6)

    # Seam close-up of the lit 3x3: the crossing of four tiles, 4x nearest.
    c = N
    seam = tile3[c - 128:c + 128, c - 128:c + 128]
    Image.fromarray(seam, "RGB").resize((1024, 1024), Image.NEAREST).save(PREVIEW_DIR / "texture_seam_zoom.png")

    # Plain maps, 3x3 each, scaled to 1024 per sheet column.
    def tiled(img: Image.Image) -> Image.Image:
        a = np.tile(np.asarray(img), (3, 3, 1))
        return Image.fromarray(a, "RGB").resize((1024, 1024), Image.LANCZOS)

    sheet = Image.new("RGB", (3 * 1024, 1024))
    for i, key in enumerate(("belt_detail_albedo.png", "belt_detail_normal.png", "belt_detail_orm.png")):
        sheet.paste(tiled(images[key]), (i * 1024, 0))
    sheet.save(PREVIEW_DIR / "texture_preview_maps.png")

    # 1:1 and 4x crop of the weave, albedo | lit | normal | orm side by side.
    y0, x0 = 380, 380
    crops = []
    for arr in (np.asarray(images["belt_detail_albedo.png"]), lit, np.asarray(images["belt_detail_normal.png"]),
                np.asarray(images["belt_detail_orm.png"])):
        crops.append(Image.fromarray(np.ascontiguousarray(arr[y0:y0 + 128, x0:x0 + 128]), "RGB").resize((512, 512), Image.NEAREST))
    z = Image.new("RGB", (4 * 512, 512))
    for i, cimg in enumerate(crops):
        z.paste(cimg, (i * 512, 0))
    z.save(PREVIEW_DIR / "texture_detail_zoom.png")
    print("previews ->", PREVIEW_DIR)


# --------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output directory for the three PNGs")
    ap.add_argument("--preview", action="store_true", help="write 3x3 tiling previews to artifacts/ground_quality/")
    ap.add_argument("--no-verify", action="store_true", help="skip the numeric verification")
    args = ap.parse_args(argv)

    fields = build(args.seed)
    images = to_images(fields)
    args.out.mkdir(parents=True, exist_ok=True)
    for name, img in images.items():
        img.save(args.out / name, optimize=False, compress_level=9)       # no metadata -> byte-reproducible
        digest = hashlib.sha1((args.out / name).read_bytes()).hexdigest()[:12]
        print(f"wrote {args.out / name}  ({N}x{N}, sha1 {digest})")
    if args.preview:
        write_previews(fields, images)
    if not args.no_verify:
        return 0 if verify(args.out, fields) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
