#!/usr/bin/env python3
"""Generate the painted-steel panel textures of the quiz walls, answer doors and goal props.

Outputs (3072 x 1536, fully seamless, deterministic for a given seed):

    assets/environment/conveyor_stage/textures/wall_panel_albedo.png   grey MULTIPLIER of albedo_color
    assets/environment/conveyor_stage/textures/wall_panel_normal.png   OpenGL (+Y) normal map
    assets/environment/conveyor_stage/textures/wall_panel_orm.png      R = AO, G = roughness, B = metallic (0)

Run (numpy + Pillow only, no Blender, no Godot, ~1 min):

    python tools/ground/gen_wall_textures.py               # textures + numeric verification
    python tools/ground/gen_wall_textures.py --preview     # + previews in artifacts/ground_quality/
    python tools/ground/gen_wall_textures.py --seed 7 --out some/dir --no-verify

Re-running with the same seed reproduces the same PNGs. The textures are not imported by this
script; Godot (re)imports them from the hand-written *.png.import files next to them (albedo / orm
BC7, normal BC5; the orm's roughness/mode=Green with roughness/src_normal = the normal map, so its
roughness mips widen where the joints and rivets average out). After regenerating, let the editor
rescan (a full filesystem scan; a single-file update did not pick up the new PNGs) and check that the
source_md5 in .godot/imported/wall_panel_*.md5 matches the new files. VRAM: 3 x 6.3 MB with mips.

Design
------
* Mapped by scripts/world/wall_materials.gd with OBJECT-SPACE triplanar (uv1_triplanar, not world):
  the walls slide along the belt, so world-space mapping would swim. One tile is 9.0 m x 4.4 m of a
  part's own coordinates (uv1_scale = 1/9, 1/4.4, 1/9) and every BoxMesh is centred on its node, so
  the offsets in wall_materials.gd put a part's centre on the middle of a panel.
* Layout of one tile (image X = part-local x, image rows = part-local y from +2.2 m down to -2.2 m):
    - 3 panels of 3.0 m. The vertical seams sit at x = 0, 3, 6 m (columns 0, 1024, 2048), so with the
      part centred mid-panel they fall at +-1.5 m: the 4-choice doors (2.9 m) show no seam, the 2-choice
      doors (3.6 m) get a 0.3 m frame strip on each side, the narrow 4-choice pillars show none.
    - Horizontal seams at y = +-2.2 m (the top/bottom edges of every pillar and door: the door head
      line, row 0) and at y = BASE_SEAM_Y = -1.137 m. -1.137 m is minus half the standard question
      beam height (2.274 m), so the same shared material also puts a seam exactly on the beam's lower
      edge: the beam/pillar junction above the doors shows a full groove with rivet rows either side.
      On pillars and doors the base seam runs 0.243 m above the belt (the belt top is y = -1.38 m).
    - Below the base seam is a dirtier kick band (only 0.24 m of it is above the belt on pillars; tall
      boss / 2P-enlarged beams show more of it as a lintel band above the doors).
* The albedo is a grey MULTIPLIER (R = G = B) of the material's albedo_color, which stays the original
  wall / door colour (game code reads albedo_color for debris and fades). 8-bit data cannot exceed 1.0,
  so it only darkens; its linear mean is calibrated to TARGET_LINEAR_MEAN and printed.
* Everything is periodic (FFT-filtered noise, seams on the tile grid, stamps wrapped), so left/right and
  top/bottom edges join exactly. The texture is statistically homogeneous on purpose: every part samples
  the region around its own centre, so a distinctive blotch would repeat on every pillar and door.
* Normal: tangent-space OpenGL, n = normalize(-dh/dx, +dh/drow, 1) with h in metres and the slopes in
  metres per metre (rows run downward, +Y is up).
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
SEED = 20261004
W, H = 3072, 1536                  # texture size (px)
TILE_W_M, TILE_H_M = 9.0, 4.4      # metres per tile (x, y)
PPM_X, PPM_Y = W / TILE_W_M, H / TILE_H_M   # 341.3 / 349.1 px per metre
PANEL_W_M = 3.0
TOP_Y = 2.2                        # part-local y of row 0 (pillar / door top edge)
BASE_SEAM_Y = -1.137               # = -(standard question-beam height 2.274 m) / 2
FLOOR_Y = -1.38                    # belt top in pillar / door local coordinates

# False: one continuous painted sheet. No panel joints (grooves), no rivet rows, no per-panel tone or
# tilt steps, no kick-band step: nothing on the wall draws a line (the quiz walls are meant to read as
# one wall, and a joint every 3 m cut it into slabs). True brings back the 3 m panels of the first version.
JOINTS = False

TARGET_LINEAR_MEAN = 0.94          # albedo multiplier mean in linear light
TARGET_ROUGH_MEAN = 0.60           # the original wall / door roughness
ROUGH_MIN, ROUGH_MAX = 0.32, 0.92
PANEL_TILT = 0.022                 # rms slope of a whole sheet (~1.3 deg)

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "assets" / "environment" / "conveyor_stage" / "textures"
PREVIEW_DIR = REPO / "artifacts" / "ground_quality"
NAMES = ("wall_panel_albedo.png", "wall_panel_normal.png", "wall_panel_orm.png")

_FX = np.fft.fftfreq(W)[None, :]
_FY = np.fft.fftfreq(H)[:, None]

XS = (np.arange(W) + 0.5) / PPM_X                 # 0 .. 9 m
YS = TOP_Y - (np.arange(H) + 0.5) / PPM_Y         # +2.2 .. -2.2 m (part-local y)
X, Y = np.meshgrid(XS, YS)


# --------------------------------------------------------------------------- periodic helpers
def stream(seed: int, name: str) -> np.random.Generator:
    """Independent RNG per feature, so editing one feature never shifts the others."""
    return np.random.default_rng([seed, zlib.crc32(name.encode("utf-8"))])


def blur_px(a: np.ndarray, sx: float, sy: float) -> np.ndarray:
    """Gaussian blur with periodic boundaries (sigma in px per axis)."""
    g = np.exp(-2.0 * math.pi ** 2 * ((_FX * sx) ** 2 + (_FY * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def blur_m(a: np.ndarray, sx_m: float, sy_m: float | None = None) -> np.ndarray:
    sy_m = sx_m if sy_m is None else sy_m
    return blur_px(a, sx_m * PPM_X, sy_m * PPM_Y)


def gnoise(rng: np.random.Generator, sx_m: float, sy_m: float | None = None) -> np.ndarray:
    """Periodic Gaussian noise, zero mean, unit std; feature sigma in metres (anisotropic ok)."""
    a = blur_m(rng.standard_normal((H, W)), sx_m, sy_m)
    a -= a.mean()
    return a / a.std()


def fbm(rng: np.random.Generator, sigmas_m, weights) -> np.ndarray:
    out = np.zeros((H, W))
    for s, w in zip(sigmas_m, weights):
        out += w * gnoise(rng, s)
    return out / math.sqrt(sum(w * w for w in weights))


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def srgb_encode(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def srgb_decode(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def row_of(y_m: float) -> float:
    return (TOP_Y - y_m) * PPM_Y


# --------------------------------------------------------------------------- geometry
def seam_fields() -> dict[str, np.ndarray]:
    """Distances (m) to the vertical and horizontal seams, and panel / band ids."""
    sx = np.mod(X + PANEL_W_M * 0.5, PANEL_W_M) - PANEL_W_M * 0.5          # signed, seams at x = 0, 3, 6
    d_vert = np.abs(sx)
    d_top = np.minimum(TOP_Y - Y, Y + TOP_Y)                                 # seam at +2.2 == -2.2 (row 0)
    d_base = np.abs(Y - BASE_SEAM_Y)
    d_horz = np.minimum(d_top, d_base)
    panel = np.floor(X / PANEL_W_M).astype(np.int64) % 3
    band = (Y < BASE_SEAM_Y).astype(np.int64)                                 # 1 = kick band below the base seam
    if not JOINTS:
        far = np.full_like(d_vert, 1.0e3)                                      # no joint anywhere
        return {"d_vert": far, "d_horz": far, "d_seam": far, "d_top": far, "d_base": far,
                "panel": np.zeros_like(panel), "band": np.zeros_like(band)}
    return {"d_vert": d_vert, "d_horz": d_horz, "d_seam": np.minimum(d_vert, d_horz),
            "d_top": d_top, "d_base": d_base, "panel": panel, "band": band}


def seam_height(d: np.ndarray, half_groove: float = 0.0080, chamfer: float = 0.0120, depth: float = 0.0045) -> np.ndarray:
    """Cross-section of a panel joint: flat-bottomed groove, then a rounded chamfer up to the panel face."""
    t = np.clip((d - half_groove) / chamfer, 0.0, 1.0)
    return -depth * (1.0 - t) ** 2


def rivet_positions() -> list[tuple[float, float]]:
    """(x, y) in metres of every round-head rivet of one tile."""
    pts: list[tuple[float, float]] = []
    inset, end_gap = 0.07, 0.16
    for k in range(3):
        seam_x = k * PANEL_W_M
        # two columns along each vertical seam, in the main panel and in the kick band
        for zone_top, zone_bottom, pitch in ((TOP_Y, BASE_SEAM_Y, 0.28), (BASE_SEAM_Y, -TOP_Y, 0.26)):
            span = (zone_top - zone_bottom) - 2.0 * end_gap
            n = max(1, int(round(span / pitch)) + 1)
            for i in range(n):
                y = zone_top - end_gap - span * i / max(1, n - 1)
                pts.append((seam_x + inset, y))
                pts.append((seam_x - inset, y))
        # rows along the horizontal seams, inside each panel
        span = PANEL_W_M - 2.0 * end_gap
        n = int(round(span / 0.27)) + 1
        for row_y in (TOP_Y - inset, BASE_SEAM_Y + inset, BASE_SEAM_Y - inset, -TOP_Y + inset):
            for i in range(n):
                pts.append((seam_x + end_gap + span * i / (n - 1), row_y))
    return pts


def stamp_rivets(pts, radius: float = 0.0115, height: float = 0.0042) -> tuple[np.ndarray, np.ndarray]:
    """Dome heights (m) and a 'ring' field (1 at the dome rim, fading out over 6 mm) for the rivets."""
    h = np.zeros((H, W))
    ring = np.zeros((H, W))
    rx, ry = int(math.ceil((radius + 0.008) * PPM_X)) + 1, int(math.ceil((radius + 0.008) * PPM_Y)) + 1
    oy, ox = np.mgrid[-ry:ry + 1, -rx:rx + 1]
    for (x, y) in pts:
        cx, cy = x * PPM_X - 0.5, (TOP_Y - y) * PPM_Y - 0.5            # pixel-centre coordinates
        ix, iy = int(math.floor(cx)), int(math.floor(cy))
        dx = (ox + ix - cx) / PPM_X
        dy = (oy + iy - cy) / PPM_Y
        r = np.sqrt(dx * dx + dy * dy)
        dome = height * np.clip(1.0 - (r / radius) ** 2, 0.0, None) ** 0.55
        rim = np.exp(-np.maximum(r - radius * 0.9, 0.0) / 0.003) * (r > radius * 0.6)
        rows = (oy + iy) % H
        cols = (ox + ix) % W
        h[rows, cols] = np.maximum(h[rows, cols], dome)
        ring[rows, cols] = np.maximum(ring[rows, cols], rim)
    # a touch of blur: the stamps are point-sampled
    return blur_px(h, 0.45, 0.45), np.clip(blur_px(ring, 0.6, 0.6), 0.0, 1.0)


def make_scratches(seed: int, count: int) -> np.ndarray:
    """Thin scuffs and scratches, mostly near-horizontal, denser low on the wall. 0..~1 coverage."""
    r = stream(seed, "scratches")
    acc = np.zeros((H, W))
    for _ in range(count):
        x0 = r.uniform(0.0, TILE_W_M)
        # denser towards the belt: y drawn from a skewed distribution over the visible range
        y0 = FLOOR_Y + 0.05 + (TOP_Y - FLOOR_Y - 0.1) * r.beta(1.3, 2.4)
        length = float(np.clip(np.exp(r.normal(-2.2, 0.6)), 0.02, 0.45))
        ang = r.normal(0.0, math.radians(18.0)) if r.random() < 0.75 else r.uniform(-1.4, 1.4)
        amp = float(np.clip(np.exp(r.normal(-0.5, 0.5)), 0.2, 1.0))
        t = np.arange(0.0, length, 0.5 / PPM_X)
        env = np.sin(math.pi * t / length) ** 0.5
        xx = x0 + math.cos(ang) * t
        yy = y0 + math.sin(ang) * t + 0.002 * np.sin(t / 0.03 + r.uniform(0, 6.3))
        cols = np.round(xx * PPM_X - 0.5).astype(np.int64) % W
        rows = np.round((TOP_Y - yy) * PPM_Y - 0.5).astype(np.int64) % H
        np.add.at(acc, (rows, cols), amp * env * 0.6)
    return np.clip(blur_px(acc, 0.55, 0.55), 0.0, None) * 1.4


# --------------------------------------------------------------------------- composition
def build(seed: int) -> dict[str, np.ndarray]:
    r = stream(seed, "fields")
    sf = seam_fields()
    d_vert, d_horz, d_seam = sf["d_vert"], sf["d_horz"], sf["d_seam"]
    panel, band = sf["panel"], sf["band"]

    rivet_h, rivet_ring = stamp_rivets(rivet_positions() if JOINTS else [])
    scratches = np.clip(make_scratches(seed, 900), 0.0, 1.0)

    # ---- noise fields (all periodic)
    mottle = fbm(r, (0.70, 0.30, 0.12), (1.0, 0.8, 0.5))            # paint mottling / fading
    grain = gnoise(r, 0.0022)                                         # fine paint grain
    peel = gnoise(r, 0.0030)                                          # orange peel (height)
    wavy = fbm(r, (0.22, 0.10), (1.0, 0.45))                          # oil-canning of the sheets
    streak_n = gnoise(r, 0.006, 0.30)                                 # rain / grime runs (vertical)
    streak_n2 = gnoise(r, 0.012, 0.55)
    grime_n = fbm(r, (0.20, 0.08, 0.03), (1.0, 0.7, 0.5))             # dirt patches
    splash_n = gnoise(r, 0.008)                                       # mud splashes near the belt
    chip_n = gnoise(r, 0.0035)                                        # paint chips
    wear_n = fbm(r, (0.10, 0.04), (1.0, 0.6))                         # rubbed / worn paint

    weather_n = fbm(r, (0.45, 0.18), (1.0, 0.5))                     # soft weathered / faded patches

    # ---- masks
    seam_near = np.exp(-np.maximum(d_seam - 0.008, 0.0) / 0.020)     # 1 at the joint, ~0 by 8 cm
    in_main = (band == 0).astype(np.float64)
    above_floor = Y - FLOOR_Y                                         # metres above the belt (negative = hidden)
    # Only tall beams (boss / 2P text) and the start barrier ever show the kick band below y = -1.6 m:
    # let its dirt fade out there, so the wrap at the top seam joins clean paint to clean paint.
    wrap_fade = smoothstep(-2.15, -1.70, Y)
    # dirt rising from the belt: strongest in the kick band, a short fade above the base seam
    if JOINTS:
        low_dirt = np.where(band == 1, (0.62 + 0.38 * smoothstep(0.30, -0.05, above_floor)) * wrap_fade,
                            0.55 * np.exp(-(Y - BASE_SEAM_Y) / 0.18))
    else:
        low_dirt = np.clip(0.55 * np.exp(-(Y - BASE_SEAM_Y) / 0.18), 0.0, 1.0) * wrap_fade
    # streaks start under the joints (the top seam, the rivet rows) and fade downwards
    below_top = TOP_Y - Y
    if JOINTS:
        streak_src = in_main * (0.35 + 0.65 * np.exp(-below_top / 1.1)) + (1.0 - in_main) * 0.45 * wrap_fade
    else:
        streak_src = (0.35 + 0.65 * np.exp(-below_top / 1.1)) * wrap_fade
    streaks = np.clip(0.65 * streak_n + 0.35 * streak_n2 - 1.0, 0.0, None) * streak_src
    streaks = np.clip(streaks / 1.1, 0.0, 1.0)
    weather = smoothstep(0.2, 1.6, weather_n)
    chips = smoothstep(2.25, 2.9, chip_n) * np.clip(seam_near * 1.4 + 0.6 * rivet_ring, 0.0, 1.0)
    chips += smoothstep(3.2, 3.7, chip_n) * 0.6                       # a few stray chips anywhere
    chips = np.clip(chips, 0.0, 1.0)
    wear = smoothstep(1.2, 2.4, wear_n) * (0.35 + 0.65 * smoothstep(1.4, -0.6, Y))   # rubbed low on the wall
    splash = smoothstep(1.6, 2.6, splash_n) * smoothstep(0.55, 0.0, above_floor) * smoothstep(-0.25, 0.0, above_floor)
    groove = (d_seam < 0.0080).astype(np.float64)
    groove_soft = blur_px(groove, 0.7, 0.7)

    # ---- height (m) -> normal
    peel_h = 0.00009 * peel * (1.0 - 0.6 * wear)
    wavy_h = 0.0024 * wavy * smoothstep(0.0, 0.25, d_seam)           # sheets are pinned at the joints
    pillow = 0.0007 * smoothstep(0.0, 0.35, d_seam)                   # slightly proud between joints
    height = (
        np.minimum(seam_height(d_vert), seam_height(d_horz))
        + rivet_h + wavy_h + pillow + peel_h
        - 0.00012 * scratches
        - 0.00015 * chips
    )
    dhdx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * PPM_X       # m per m
    dhdr = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * PPM_Y
    # Every sheet sits a degree or two off true (it is bolted at its edges, not ground flat), so the
    # sheets catch the sky and the sun a little differently: a per-sheet slope, released at the joints.
    tilt = stream(seed, "sheet_tilt").normal(0.0, PANEL_TILT, size=(2, 3, 2))
    tilt[0, 0] *= 0.5                                                   # the panel on every part's centre stays calm
    release = smoothstep(0.004, 0.06, d_seam)
    if JOINTS:
        dhdx += tilt[band, panel, 0] * release
        dhdr += tilt[band, panel, 1] * release
    nrm = np.stack([-dhdx, dhdr, np.ones_like(height)], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)

    # ---- albedo multiplier (linear light, <= 1)
    if JOINTS:
        panel_tone = np.where(band == 0, np.array([0.000, 0.060, 0.030])[panel], np.array([0.060, 0.075, 0.055])[panel])
    else:
        panel_tone = np.full_like(X, 0.030)
    dark = (
        panel_tone
        + 0.016 * mottle
        + 0.020 * weather                                             # soft faded / weathered patches
        + 0.006 * grain
        + 0.028 * smoothstep(2.0, -1.1, Y) * (in_main if JOINTS else wrap_fade)   # each sheet darkens towards its foot (clean again at the wrap)
        + 0.100 * streaks
        + 0.100 * low_dirt * (0.65 + 0.35 * np.tanh(grime_n))
        + 0.090 * splash
        + 0.045 * seam_near                                           # grime collects along the joints
        + 0.420 * groove_soft                                         # dirt packed into the groove
        + 0.150 * rivet_ring                                          # dirt ring around the rivet heads
        + 0.330 * chips                                               # chipped paint shows dark primer
        + 0.035 * np.clip(scratches, 0.0, 1.0) * (scratches > 0.35)   # deep scuffs
        - 0.012 * np.clip(scratches, 0.0, 1.0) * (scratches <= 0.35)  # light scuffs read paler
        - 0.010 * wear                                                # rubbed paint is a touch paler
    )

    def knee(x: np.ndarray, e: float = 0.012) -> np.ndarray:
        """Soft rectifier ~max(x, 0), so the brightest paint keeps a little texture."""
        return 0.5 * (x + np.sqrt(x * x + e * e))

    lo, hi = -0.3, 0.3
    for _ in range(60):                        # solve the offset so the linear mean hits the target
        mid = 0.5 * (lo + hi)
        if np.clip(1.0 - knee(dark + mid), 0.0, 1.0).mean() > TARGET_LINEAR_MEAN:
            lo = mid
        else:
            hi = mid
    offset = 0.5 * (lo + hi)
    albedo_lin = np.clip(1.0 - knee(dark + offset), 0.0, 1.0)

    # ---- ORM
    ao = (1.0 - 0.62 * groove_soft - 0.18 * seam_near * (1.0 - groove_soft)
          - 0.30 * rivet_ring - 0.10 * low_dirt - 0.15 * chips)
    ao = np.clip(ao, 0.25, 1.0)
    rough_raw = (
        0.555
        + 0.030 * mottle
        + 0.030 * weather
        + 0.015 * peel
        + 0.160 * low_dirt * (0.6 + 0.4 * np.tanh(grime_n))
        + 0.060 * streaks
        + 0.300 * groove_soft
        + 0.120 * splash
        + 0.050 * seam_near
        - 0.150 * chips                                               # bare steel in the chips is smoother
        - 0.090 * wear
        - 0.060 * (rivet_h > 0.0025)                                  # rubbed rivet heads
        - 0.050 * np.clip(scratches, 0.0, 1.0)
    )
    lo, hi = -0.2, 0.2
    mid_r, half = 0.5 * (ROUGH_MIN + ROUGH_MAX), 0.5 * (ROUGH_MAX - ROUGH_MIN)
    for _ in range(50):
        mid = 0.5 * (lo + hi)
        rr = mid_r + half * np.tanh((rough_raw + mid - mid_r) / (half * 0.95))
        if rr.mean() < TARGET_ROUGH_MEAN:
            lo = mid
        else:
            hi = mid
    rough = mid_r + half * np.tanh((rough_raw + 0.5 * (lo + hi) - mid_r) / (half * 0.95))
    metal = np.zeros_like(ao)

    return {"albedo_lin": albedo_lin, "normal": nrm, "ao": ao, "rough": rough, "metal": metal,
            "offset": np.array(offset), "height": height, "streaks": streaks, "chips": chips}


def to_images(f: dict[str, np.ndarray]) -> dict[str, Image.Image]:
    g8 = np.round(srgb_encode(f["albedo_lin"]) * 255.0).astype(np.uint8)
    albedo = Image.fromarray(np.dstack([g8, g8, g8]), "RGB")
    n8 = np.round((f["normal"] * 0.5 + 0.5) * 255.0).astype(np.uint8)
    normal = Image.fromarray(n8, "RGB")
    orm8 = np.round(np.dstack([f["ao"], f["rough"], f["metal"]]) * 255.0).astype(np.uint8)
    orm = Image.fromarray(orm8, "RGB")
    return dict(zip(NAMES, (albedo, normal, orm)))


# --------------------------------------------------------------------------- verification
def _seam_stats(a: np.ndarray) -> dict[str, float]:
    """Mean |neighbour difference| across the wrap seam vs interior neighbours, per axis.

    The left/right wrap is also a vertical panel joint and the top/bottom wrap is the top seam, so the
    wrap pair is compared with the same joint inside the tile (columns 1023|1024 and 2047|2048 for
    left/right; for top/bottom the base seam rows) as well as with all interior pairs.
    """
    a = a.astype(np.float64)
    out = {}
    d_lr = np.abs(np.diff(a, axis=1)).mean(axis=0)
    out["LR_seam"] = float(np.abs(a[:, 0] - a[:, -1]).mean())
    out["LR_all"] = float(d_lr.mean())
    out["LR_joint"] = float(0.5 * (d_lr[1023] + d_lr[2047]))
    d_tb = np.abs(np.diff(a, axis=0)).mean(axis=1)
    out["TB_seam"] = float(np.abs(a[0, :] - a[-1, :]).mean())
    out["TB_all"] = float(d_tb.mean())
    base_row = int(round(row_of(BASE_SEAM_Y) - 0.5))
    out["TB_joint"] = float(d_tb[base_row - 2:base_row + 2].max())        # the pair that straddles the base seam
    return out


def verify(out_dir: Path, fields: dict[str, np.ndarray]) -> bool:
    ok = True
    load = lambda name: np.asarray(Image.open(out_dir / name))
    alb, nor, orm = (load(n) for n in NAMES)
    print("--- verification (from the written PNG files) ---")
    for name, a in zip(("albedo", "normal", "orm"), (alb, nor, orm)):
        print(f"{name:7s} shape={a.shape} dtype={a.dtype}")
    lin = srgb_decode(alb[..., 0] / 255.0)
    mean_lin = float(lin.mean())
    print(f"albedo: R==G==B: {bool((alb[..., 0] == alb[..., 1]).all() and (alb[..., 1] == alb[..., 2]).all())}")
    print(f"albedo: sRGB8 mean={alb[..., 0].mean():.1f} min={alb.min()} max={alb.max()} "
          f"p1={np.percentile(alb[..., 0], 1):.0f} p50={np.percentile(alb[..., 0], 50):.0f} p99={np.percentile(alb[..., 0], 99):.0f}")
    print(f"albedo: linear mean={mean_lin:.4f} (target {TARGET_LINEAR_MEAN}) std={lin.std():.4f} "
          f"min={lin.min():.3f} max={lin.max():.3f} median={np.median(lin):.4f} gain_to_unity={1.0 / mean_lin:.4f}")
    vis = (YS > FLOOR_Y)[:, None] & np.ones((1, W), bool)
    print(f"albedo: linear mean of the part above the belt on pillars/doors (rows < {row_of(FLOOR_Y):.0f}) "
          f"= {float(lin[vis].mean()):.4f}; main panel faces only (2 cm off the joints) = "
          f"{float(lin[(seam_fields()['d_seam'] > 0.02) & vis & (Y > BASE_SEAM_Y)].mean()):.4f}")
    ok &= 0.90 <= mean_lin <= 1.0

    n = nor.astype(np.float64) / 255.0 * 2.0 - 1.0
    ln = np.linalg.norm(n, axis=-1)
    print(f"normal: |n| mean={ln.mean():.4f} min={ln.min():.4f} max={ln.max():.4f}; "
          f"mean xyz=({n[..., 0].mean():+.4f}, {n[..., 1].mean():+.4f}, {n[..., 2].mean():+.4f}); "
          f"std x={n[..., 0].std():.3f} y={n[..., 1].std():.3f}; max tilt={math.degrees(math.acos(min(1.0, n[..., 2].min()))):.1f} deg")
    ok &= abs(ln.mean() - 1.0) < 0.01 and ln.min() > 0.96 and ln.max() < 1.04

    o = orm.astype(np.float64) / 255.0
    for i, nm in enumerate(("AO   (R)", "rough(G)", "metal(B)")):
        print(f"orm {nm}: min={o[..., i].min():.3f} mean={o[..., i].mean():.4f} max={o[..., i].max():.3f}")
    ok &= ROUGH_MIN - 0.01 <= o[..., 1].min() and o[..., 1].max() <= ROUGH_MAX + 0.01 and o[..., 2].max() == 0.0
    ok &= abs(o[..., 1].mean() - TARGET_ROUGH_MEAN) < 0.01

    print("seam continuity: mean |diff| of neighbouring pixels across the wrap vs the interior")
    chans = {"albedo": alb[..., 0], "normal.x": nor[..., 0], "normal.y": nor[..., 1], "orm.ao": orm[..., 0], "orm.rough": orm[..., 1]}
    for nm, a in chans.items():
        st = _seam_stats(a)
        parts = []
        for tag in ("LR", "TB"):
            r_all = st[tag + "_seam"] / max(st[tag + "_all"], 1e-9)
            r_joint = st[tag + "_seam"] / max(st[tag + "_joint"], 1e-9)
            parts.append(f"{tag} wrap {st[tag + '_seam']:6.3f} | x{r_all:.2f} of all pairs, x{r_joint:.2f} of the same joint inside")
            ok &= r_joint <= 1.35 or st[tag + "_seam"] < 1.0      # below one 8-bit level the ratio means nothing
        print(f"  {nm:10s} " + " || ".join(parts))
    print(f"albedo offset solved: {float(fields['offset']):+.4f}")
    print("RESULT:", "OK" if ok else "CHECK FAILED")
    return ok


# --------------------------------------------------------------------------- previews
def _shade(albedo_lin, nrm, rough, ao, base_rgb, sun_dir, sun=1.0, sky=0.35, sky_rgb=(0.55, 0.68, 0.95)):
    """Tiny lit preview: Lambert sun + a hemispherical sky (up = image up) + Blinn-Phong spec."""
    L = np.array(sun_dir, dtype=np.float64)
    L /= np.linalg.norm(L)
    ndl = np.clip(nrm @ L, 0.0, 1.0)
    hemi = 0.5 + 0.5 * nrm[..., 1]                                    # facing up = more sky
    half = L + np.array([0.0, 0.0, 1.0])
    half /= np.linalg.norm(half)
    ndh = np.clip(nrm @ half, 0.0, 1.0)
    shin = 2.0 / np.maximum(rough ** 4, 1e-3) - 2.0
    spec = ((shin + 2.0) / 8.0) * ndh ** shin * 0.04 * ndl
    base = albedo_lin[..., None] * np.asarray(base_rgb)[None, None, :]
    col = base * (sun * ndl[..., None] + sky * np.asarray(sky_rgb) * (0.35 + 0.65 * hemi[..., None]) * ao[..., None]) + spec[..., None] * sun
    return np.round(srgb_encode(np.clip(col, 0.0, 1.0)) * 255.0).astype(np.uint8)


def write_previews(fields: dict[str, np.ndarray], images: dict[str, Image.Image]) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    lit = _shade(fields["albedo_lin"], fields["normal"], fields["rough"], fields["ao"], (0.5, 0.5, 0.5), (-0.45, 0.55, 0.70))
    # 3x3 tiling of the lit tile at 1/3 scale (one tile = 1024 x 512 here): repetition / seams check
    small = Image.fromarray(lit, "RGB").resize((1024, 512), Image.LANCZOS)
    sheet = Image.fromarray(np.tile(np.asarray(small), (3, 3, 1)), "RGB")
    sheet.save(PREVIEW_DIR / "wall_panel_preview.png")
    # the three maps side by side (1/3 scale) and a 1:1 crop of a joint crossing
    maps = Image.new("RGB", (3 * 1024, 512))
    for i, key in enumerate(NAMES):
        maps.paste(images[key].resize((1024, 512), Image.LANCZOS), (i * 1024, 0))
    maps.save(PREVIEW_DIR / "wall_panel_preview_maps.png")
    r0 = int(row_of(BASE_SEAM_Y)) - 160
    crop = [np.asarray(images[NAMES[0]])[r0:r0 + 320, 1024 - 240:1024 + 240], lit[r0:r0 + 320, 1024 - 240:1024 + 240],
            np.asarray(images[NAMES[1]])[r0:r0 + 320, 1024 - 240:1024 + 240], np.asarray(images[NAMES[2]])[r0:r0 + 320, 1024 - 240:1024 + 240]]
    z = Image.new("RGB", (4 * 480, 320))
    for i, c in enumerate(crop):
        z.paste(Image.fromarray(np.ascontiguousarray(c), "RGB"), (i * 480, 0))
    z.save(PREVIEW_DIR / "wall_panel_preview_joint.png")
    write_wall_mock(fields)
    print("previews ->", PREVIEW_DIR)


def write_wall_mock(fields: dict[str, np.ndarray], ppm: float = 60.0) -> None:
    """Front view of the 2-choice and 4-choice walls as the game maps them (object space, part-centred,
    the same offsets as wall_materials.gd), at ~60 px/m (the 04 view) plus a 1:1 crop of a door edge."""
    lit = _shade(fields["albedo_lin"], fields["normal"], fields["rough"], fields["ao"], (1.0, 1.0, 1.0), (0.0, 0.35, 0.94), sun=0.25, sky=0.8)
    lit_lin = srgb_decode(lit / 255.0)
    floor_y, door_top, wall_top = -1.2, 2.38, 4.654
    width = 23.8

    def part(img, x0, x1, y0, y1, cx, cy, rgb, slot):
        # sample texture for world x in [x0, x1], y in [y0, y1] using local coords around (cx, cy)
        ox, oy = 1.0 / 6.0 + slot / 3.0, -0.5
        px0, px1 = int(round((x0 + width / 2) * ppm)), int(round((x1 + width / 2) * ppm))
        py0, py1 = int(round((wall_top - y1) * ppm)), int(round((wall_top - y0) * ppm))
        xs = (np.arange(px0, px1) + 0.5) / ppm - width / 2 - cx
        ys = wall_top - (np.arange(py0, py1) + 0.5) / ppm - cy
        u = np.mod(xs / TILE_W_M + ox, 1.0)
        v = np.mod(-(ys / TILE_H_M + oy), 1.0)
        cols = (u * W).astype(np.int64) % W
        rows = (v * H).astype(np.int64) % H
        tex = lit_lin[rows[:, None], cols[None, :]]
        img[py0:py1, px0:px1] = tex * np.asarray(rgb)[None, None, :]

    out = []
    for layout in (2, 4):
        img = np.zeros((int(round((wall_top - floor_y) * ppm)), int(round(width * ppm)), 3))
        grey = (0.5, 0.5, 0.5)
        part(img, -width / 2, width / 2, door_top, wall_top, 0.0, door_top + (wall_top - door_top) / 2, grey, 0)  # beam
        if layout == 2:
            doors = [(-3.5, 1.8, (0.90, 0.15, 0.10), 1), (3.5, 1.8, (0.10, 0.60, 0.95), 0)]
        else:
            doors = [(-5.8, 1.45, (0.10, 0.55, 0.95), 0), (-1.95, 1.45, (0.15, 0.75, 0.30), 1),
                     (1.95, 1.45, (0.95, 0.60, 0.10), 2), (5.8, 1.45, (0.90, 0.15, 0.15), 3)]
        cur = -width / 2
        for (dx, hw, _c, _s) in sorted(doors):
            if dx - hw > cur:
                part(img, cur, dx - hw, floor_y, door_top, (cur + dx - hw) / 2, 0.18, grey, 0)
            cur = dx + hw
        part(img, cur, width / 2, floor_y, door_top, (cur + width / 2) / 2, 0.18, grey, 0)
        for (dx, hw, c, s) in doors:
            part(img, dx - hw, dx + hw, floor_y, door_top, dx, 0.18, c, (s + 1) % 3)
        # the game camera looks along +Z at the -Z faces, where +X is on the left
        out.append(np.round(srgb_encode(np.clip(img[:, ::-1], 0, 1)) * 255).astype(np.uint8))
    gap = np.full((12, out[0].shape[1], 3), 255, np.uint8)
    Image.fromarray(np.vstack([out[0], gap, out[1]]), "RGB").save(PREVIEW_DIR / "wall_panel_mock.png")


# --------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output directory for the three PNGs")
    ap.add_argument("--preview", action="store_true", help="write previews to artifacts/ground_quality/")
    ap.add_argument("--no-verify", action="store_true", help="skip the numeric verification")
    args = ap.parse_args(argv)

    fields = build(args.seed)
    images = to_images(fields)
    args.out.mkdir(parents=True, exist_ok=True)
    for name, img in images.items():
        img.save(args.out / name, optimize=False, compress_level=9)        # no metadata -> byte-reproducible
        digest = hashlib.sha1((args.out / name).read_bytes()).hexdigest()[:12]
        print(f"wrote {args.out / name}  ({W}x{H}, sha1 {digest})")
    if args.preview:
        write_previews(fields, images)
    if not args.no_verify:
        return 0 if verify(args.out, fields) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
