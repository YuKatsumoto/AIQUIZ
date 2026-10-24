"""スカイゲートの空の演出（W7）の素材を作る：見下ろしの島（環礁・緑の島・小島）・桟橋と小舟・帆船。
雲は作らない（2026-10-19 ユーザー指示「雲はやっぱりいらない」。前の版の雲の塊 SFC_Puff* と sky_fx_clouds.glb はやめた）。
仕様：docs/sudden_death_v2/sky_fx.md と skygate_build_plan.md 4.8節。

ライブの Blender（Higgsfield の Blender 連携）で実行する。ヘッドレスで代替しない（AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-render" で確認レンダーを出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/sky_fx/source/blender/build_sky_fx.py", run_name="__main__")

島の作りはスタジアムの遠景（assets/aiquiz_stadium/source/blender/aqs_backdrop.py）の道具をそのまま使う
（尾根と谷の地形・すき間なく覆う樹冠・ヤシ・水際の岩・砂浜）。読むだけで、スタジアムのファイルは書き換えない。
見下ろしで近づくので、樹冠の間隔を細かくし、礁湖（浅い砂の棚）・礁の白波・サンゴの塊を足した。

座標：Blender の Z が上、メートル。島の原点＝着地台の中心 × 海面。Godot では (x, z, -y)：+X 右、+Y 上、−Z 奥（画面の上）。
  島は高い所で見る軽い作り（*_Lo）と、近づいたときの細かい作り（*_Hi）の 2 つ。白波はすべての島で 1 つ（SFI_Surf_All、描く回数を減らす）。
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
ASSET = SOURCE.parent
ROOT = ASSET.parents[2]
PREVIEWS = SOURCE / "previews"
STADIUM_BLENDER = ROOT / "assets" / "aiquiz_stadium" / "source" / "blender"
ISLANDS_GLB = ASSET / "sky_fx_islands.glb"
BOATS_GLB = ASSET / "sky_fx_boats.glb"
LAYOUT = ASSET / "sky_fx_layout.json"
REPORT = SOURCE / "build_report.json"
BLEND = HERE / "sky_fx.blend"

if str(STADIUM_BLENDER) not in sys.path:
    sys.path.insert(0, str(STADIUM_BLENDER))
for _name in [m for m in sys.modules if m.startswith("aqs_")]:
    del sys.modules[_name]
import aqs_backdrop as AB  # noqa: E402
import aqs_geom as AG  # noqa: E402
from aqs_geom import Mesh, hexcol, mix, shade  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS

smoothstep = AB.smoothstep
fbm = AB.fbm

# ---------------------------------------------------------------- 色（線形）
SAND, SAND_WET = AB.SAND, AB.SAND_WET
SAND_UNDER = hexcol("#E4EBCF")          # 礁湖の底の白い砂（ゲームの海越しに明るい水色になる）
LAGOON_SAND = hexcol("#D2E2C4")
SEAGRASS = hexcol("#5E8C70")
CORAL_DARK = hexcol("#4E6B58")
CORAL_WARM = hexcol("#8C7A62")
CORAL_PINK = hexcol("#B98C86")
REEF_CREST = hexcol("#CBD3B4")
DROP = hexcol("#5C7F78")
FOAM = (1.0, 1.0, 1.0, 1.0)
DEEP_CUT = -64.0
DROP_HI, DROP_LO = 90.0, 110.0       # 礁の外の落ち込みの幅（細かい作り・軽い作り）
DECK, DECK_DARK, POST = hexcol("#C9A27A"), hexcol("#9A7656"), hexcol("#6E5440")
ROOF, ROOF_DARK = hexcol("#B3643F"), hexcol("#7E4129")
HULL_WHITE, HULL_TRIM, SEAT = hexcol("#F4F4F0"), hexcol("#2B4E86"), hexcol("#E2CFA6")

# ---------------------------------------------------------------- 島の並び（Godot の座標で書く：x 右、z 手前。着地台＝原点）
# lagoon：礁湖が広がる向き（度、Godot の +X から −Z へ反時計回り）と、海岸からの広さ（m）・広がりの幅（度）。
# base_shelf：まわりの浅瀬の幅（m）。lod_far：これより遠いと軽い作り（カメラから島の中心まで、m）。
ISLANDS = [
    {"name": "Main", "style": "lush", "center": (-250.0, -60.0), "width": 300.0, "depth": 230.0, "height": 38.0, "seed": 71,
     "lagoon": {"dir": 0.0, "extra": 64.0, "spread": 70.0}, "base_shelf": 22.0, "lod_far": 380.0, "pier": True},
    {"name": "Green", "style": "rocky", "center": (330.0, 250.0), "width": 220.0, "depth": 160.0, "height": 58.0, "seed": 83,
     "lagoon": {"dir": 140.0, "extra": 40.0, "spread": 60.0}, "base_shelf": 18.0, "lod_far": 340.0},
    {"name": "West", "style": "lush", "center": (-540.0, -560.0), "width": 170.0, "depth": 130.0, "height": 30.0, "seed": 97,
     "lagoon": {"dir": -30.0, "extra": 34.0, "spread": 55.0}, "base_shelf": 16.0, "lod_far": 300.0},
    {"name": "IsletA", "style": "islet", "center": (130.0, -240.0), "width": 54.0, "depth": 42.0, "height": 9.0, "seed": 11,
     "lagoon": {"dir": 200.0, "extra": 18.0, "spread": 80.0}, "base_shelf": 12.0, "lod_far": 240.0},
    {"name": "IsletB", "style": "islet", "center": (-140.0, 270.0), "width": 72.0, "depth": 56.0, "height": 11.0, "seed": 23,
     "lagoon": {"dir": 60.0, "extra": 22.0, "spread": 70.0}, "base_shelf": 12.0, "lod_far": 240.0},
    {"name": "IsletC", "style": "islet", "center": (-460.0, 210.0), "width": 62.0, "depth": 50.0, "height": 10.0, "seed": 37,
     "lagoon": {"dir": 300.0, "extra": 16.0, "spread": 70.0}, "base_shelf": 10.0, "lod_far": 240.0},
    {"name": "IsletD", "style": "islet", "center": (620.0, 10.0), "width": 48.0, "depth": 40.0, "height": 8.0, "seed": 41,
     "lagoon": {"dir": 180.0, "extra": 14.0, "spread": 80.0}, "base_shelf": 10.0, "lod_far": 240.0},
]
ATOLL = {"name": "Atoll", "center": (440.0, -480.0), "radius": 230.0, "ring": 44.0, "seed": 59, "lod_far": 520.0}

# 帆船の通り道（Godot の座標、着地台から）。Godot が動かす（sky_fall_islands.gd）。
SAIL_ROUTES = [
    {"from": (-120.0, -420.0), "to": (260.0, -150.0), "boat": "SFB_Sail", "speed": 3.0},
    {"from": (520.0, 420.0), "to": (120.0, 120.0), "boat": "SFB_Sail", "speed": 2.6},
    {"from": (-620.0, 60.0), "to": (-300.0, 420.0), "boat": "SFB_Sail", "speed": 2.8},
    {"from": (40.0, 480.0), "to": (-260.0, 160.0), "boat": "SFB_Motor", "speed": 7.0},
    {"from": (700.0, -260.0), "to": (300.0, -40.0), "boat": "SFB_Motor", "speed": 6.0},
]


def b_from_g(x, z, y=0.0):
    """Godot の (x, z) と高さ y → Blender の位置。"""
    return Vector((x, -z, y))


def g_from_b(v):
    return [round(v[0], 3), round(v[2], 3), round(-v[1], 3)]


# ---------------------------------------------------------------- 島
class SkyIsland(AB.Island):
    """スタジアムの島に、見下ろしで見える礁湖（浅い砂の棚）と礁の縁を足したもの。"""

    def __init__(self, spec):
        super().__init__(spec, spec["seed"], lambda x, y: True)
        self.spec = spec
        lag = spec.get("lagoon", {})
        # Godot の角度（+X から −Z へ反時計回り）→ Blender の角度（+X から +Y へ反時計回り）は同じ値
        self.lag_dir = math.radians(lag.get("dir", 0.0))
        self.lag_extra = lag.get("extra", 0.0)
        self.lag_spread = math.radians(lag.get("spread", 60.0))
        self.base_shelf = spec.get("base_shelf", 16.0)
        self.R = (self.W + self.D) / 4
        # 礁の外の落ち込みの幅（m）。なだらかに（はじめはゆっくり、深くなってから急に）落とす。
        # ゲームの海は「水面とその奥に見える面の高さの差」で透け方を決めるので、急な崖を作ると海面近くの
        # 低い視点（着地台の画）から崖と面の切れ目が海越しにまっすぐな線に見える（W4 の画で見つかった）。
        # 落ち込みの底（DEEP_CUT）より深い所は面を張らない。水深 4 m から先を 1 - exp(-0.08 × (深さ - 4)) で
        # 濃くするので、約 60 m より深ければ面があってもなくても同じ色に見える
        self.drop = DROP_HI

    def shelf_width(self, th):
        """海岸から礁の縁までの幅（m）。礁湖の向きで広い。"""
        d = math.atan2(math.sin(th - self.lag_dir), math.cos(th - self.lag_dir))
        lobe = math.exp(-(d / self.lag_spread) ** 2 * 1.6)
        wob = 0.18 * fbm(math.cos(th) * 2.2, math.sin(th) * 2.2, self.off[1], 2)
        return (self.base_shelf + self.lag_extra * lobe) * (1.0 + wob)

    def beyond(self, x, y):
        """海岸線の外へ何 m か（おおよそ）と、向き。"""
        e = self.edge(x, y)
        q = max(1.0 - e, 0.0) ** (1 / 2.3)
        th = math.atan2(y, x)
        rdir = math.hypot(x, y) / max(q, 1e-6)
        return (q - 1.0) * rdir, th

    def sample(self, x, y):
        e = self.edge(x, y)
        if e >= -0.04:
            return super().sample(x, y)
        d, th = self.beyond(x, y)
        w = self.shelf_width(th)
        if d > w + self.drop:
            return DEEP_CUT, 0.0, e, 1.0
        # 礁湖：海岸近くは浅く、真ん中は深め、縁（礁の頭）で浅くなり、外は急に落ちる
        z = -2.6 - 0.9 * smoothstep(0.0, 0.55 * w, d)
        z += 2.3 * math.exp(-((d - w) / 3.2) ** 2)
        if d > w:
            t = (d - w) / self.drop
            z -= (-DEEP_CUT - 1.0) * t * t
        z += 0.35 * fbm(x / 26.0, y / 26.0, self.off[0], 3)
        return min(z, -0.35), 0.0, e, 1.0

    def colour_under(self, x, y, z):
        d, th = self.beyond(x, y)
        w = self.shelf_width(th)
        p = fbm(x / 34.0, y / 34.0, self.off[2], 3)
        c = mix(SAND_UNDER, LAGOON_SAND, smoothstep(0.0, 0.6 * w, d))
        c = mix(c, SEAGRASS, smoothstep(0.08, 0.45, p) * 0.55 * smoothstep(4.0, 12.0, d))
        crest = math.exp(-((d - w) / 3.0) ** 2)
        c = mix(c, REEF_CREST, crest * 0.8)
        c = mix(c, CORAL_WARM, smoothstep(0.55, 1.0, crest) * 0.35 * (0.5 + 0.5 * p))
        if d > w:
            c = mix(c, DROP, smoothstep(0.0, self.drop * 0.45, d - w))
        return c


def island_mesh(spec, hi):
    """地形・森・ヤシ・岩・サンゴの塊。hi=False は軽い作り（粗い地形と大きめの樹冠だけ）。"""
    isl = SkyIsland(spec)
    isl.drop = DROP_HI if hi else DROP_LO
    st = isl.style
    rnd = random.Random(spec["seed"] * (3 if hi else 7))
    m = Mesh()
    W, D, H = isl.W, isl.D, isl.H
    # 格子の外枠で面が切れないように（切れると低い視点からまっすぐな線に見える）、礁湖のゆらぎ（最大 +18%）の分も含める
    reach = (isl.base_shelf + isl.lag_extra) * 1.25 + isl.drop + 12.0
    step = (3.2 if W > 120 else 2.2) if hi else (11.0 if W > 120 else 6.0)
    x0, x1 = -W * 0.66 - reach, W * 0.66 + reach
    y0, y1 = -D * 0.66 - reach, D * 0.66 + reach
    nx, ny = max(4, int((x1 - x0) / step)), max(4, int((y1 - y0) / step))
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    ys = [y0 + (y1 - y0) * j / ny for j in range(ny + 1)]
    S = [[isl.sample(x, y) for x in xs] for y in ys]
    dx, dy = xs[1] - xs[0], ys[1] - ys[0]
    pts, cols = [], []
    for j, y in enumerate(ys):
        prow, crow = [], []
        for i, x in enumerate(xs):
            z, rock, e, r = S[j][i]
            if z < -0.3:
                c = isl.colour_under(x, y, z)
            else:
                zl, zr = S[j][max(i - 1, 0)][0], S[j][min(i + 1, nx)][0]
                zd, zu = S[max(j - 1, 0)][i][0], S[min(j + 1, ny)][i][0]
                c = AB.ground_colour(isl, x, y, z, rock, e, r, math.hypot((zr - zl) / dx / 2, (zu - zd) / dy / 2))
                if z > 1.3:
                    lap = (zl + zr - 2 * z) / (dx * dx) + (zd + zu - 2 * z) / (dy * dy)
                    c = shade(c, 1.0 - 0.34 * smoothstep(0.004, 0.05, lap) + 0.1 * smoothstep(0.004, 0.05, -lap))
                if not hi and z > 3.4 and rock < 0.42:
                    # 軽い作りは樹冠が少ないので、森の床を樹冠の緑に寄せる（遠くからは森に見える）
                    c = mix(c, AB.CANOPY[2], 0.55)
            prow.append((x, y, z))
            crow.append(c)
        pts.append(prow)
        cols.append(crow)
    for j in range(ny):
        for i in range(nx):
            corners = ((j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i))
            if all(S[a][b][0] <= DEEP_CUT + 1.0 for a, b in corners):
                continue
            quad = [pts[a][b] for a, b in corners]
            m.add_face(quad, cols[j][i], "isle", smooth=True, ccol=[cols[a][b] for a, b in corners])

    def slope_at(x, y):
        return math.hypot(isl.z(x + 2, y) - isl.z(x - 2, y), isl.z(x, y + 2) - isl.z(x, y - 2)) / 4

    # --- 森：見下ろしで木の 1 本ずつが見える間隔（hi）。軽い作りは大きな塊を少し
    cs = (6.4 if hi else st["crown_m"] * 1.5)
    gx, gy = int(W / cs) + 1, int(D / cs) + 1
    for j in range(gy):
        for i in range(gx):
            x = -W / 2 + (i + rnd.uniform(0.1, 0.9)) * cs
            y = -D / 2 + (j + rnd.uniform(0.1, 0.9)) * cs
            z, rock, e, r = isl.sample(x, y)
            if z < 3.2 or rock > 0.42 or e < 0.13:
                continue
            clearing = fbm(x / 70.0, y / 70.0, isl.off[3], 2)
            if rnd.random() > st["canopy"] * (1.0 if clearing > -0.25 else 0.35):
                continue
            if slope_at(x, y) > st["cliff"] * 1.1:
                continue
            emergent = rnd.random() < 0.12
            rad = cs * rnd.uniform(0.55, 0.8) * (1.3 if emergent else 1.0)
            col = AB.weighted(rnd, AB.CANOPY, AB.CANOPY_W)
            sun = smoothstep(0.1 * H, 0.9 * H, z) * 0.35 + (r - 1.0) * 0.15
            col = mix(col, AB.CANOPY_SUN, max(0.0, min(0.45, sun)))
            k = rnd.uniform(0.9, 1.07)
            top = shade(mix(col, AB.CANOPY_SUN, 0.2), k)
            bot = shade(col, 0.42 * k)
            AB.crown(m, (x, y, z + rad * 0.3), rad, rad * rnd.uniform(0.74, 0.9), top, bot, rnd,
                     seg=9 if hi else 8, rings=4 if hi else 3, mat="isle")
            if hi and (emergent or rnd.random() < 0.18):
                a = rnd.uniform(0, 6.283)
                rr = rad * rnd.uniform(0.5, 0.7)
                AB.crown(m, (x + math.cos(a) * rad * 0.45, y + math.sin(a) * rad * 0.45, z + rad * 0.8), rr, rr * 0.8,
                         shade(top, 1.05), shade(bot, 1.1), rnd, seg=6, mat="isle")
    if not hi:
        return m, isl

    # --- ヤシ：砂浜の後ろに群れで。海へ傾ける
    ph = 11.0 if W > 120 else 9.0
    placed = 0
    for _ in range(st["palm_groups"] * 8):
        if placed >= st["palm_groups"] * (2 if W > 120 else 1):
            break
        th = rnd.uniform(0, 2 * math.pi)
        p = isl.shore_point(th, 1.6)
        inward = -Vector((p.x / (W / 2) ** 2, p.y / (D / 2) ** 2, 0)).normalized()
        base = p + inward * rnd.uniform(2.0, 12.0)
        if isl.sample(base.x, base.y)[1] > 0.3:
            continue
        placed += 1
        for _ in range(rnd.randint(3, 7)):
            q = base + Vector((rnd.uniform(-9, 9), rnd.uniform(-9, 9), 0))
            z, rock, e, r = isl.sample(q.x, q.y)
            if not (1.0 < z < 7.5) or rock > 0.3:
                continue
            out = -inward
            lean = (out.x * rnd.uniform(0.12, 0.3) + rnd.uniform(-0.08, 0.08), out.y * rnd.uniform(0.12, 0.3) + rnd.uniform(-0.08, 0.08))
            AB.palm(m, (q.x, q.y, z - 0.5), ph * rnd.uniform(0.75, 1.15), lean, rnd, mat="isle")

    # --- 水際の岩場
    rock_c = hexcol(st["rock"])
    rb = max(2.2, W * 0.012)
    for _ in range(st["rock_groups"]):
        th = rnd.uniform(0, 2 * math.pi)
        p = isl.shore_point(th, 0.0)
        for _ in range(rnd.randint(3, 7)):
            q = p + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * rb * 2.2
            rad = rb * rnd.uniform(0.45, 1.3)
            k = rnd.uniform(0.85, 1.1)
            AB.crown(m, (q.x, q.y, -0.6 + rad * 0.15), rad, rad * rnd.uniform(0.5, 0.8), shade(rock_c, 1.12 * k),
                     shade(rock_c, 0.62 * k), rnd, seg=6, rings=3, smooth=False, squash=0.9, mat="isle")

    # --- サンゴの塊：礁湖の底のまだら（海越しに暗い点々に見える）。礁の縁に多い
    n_patch = int((isl.lag_extra + isl.base_shelf) * (W + D) / 2600.0) + 1
    for _ in range(n_patch):
        th = rnd.uniform(0, 2 * math.pi)
        w = isl.shelf_width(th)
        p = isl.shore_point(th, 0.0)
        nrm = Vector((p.x / (W / 2) ** 2, p.y / (D / 2) ** 2, 0)).normalized()
        d = w * (1.0 - rnd.random() ** 1.7)
        if d < 6.0:
            continue
        centre = p + nrm * d
        spread = rnd.uniform(4.0, 9.0)
        for _ in range(rnd.randint(4, 11)):
            q = centre + Vector((rnd.gauss(0, spread), rnd.gauss(0, spread), 0))
            z = isl.sample(q.x, q.y)[0]
            if z > -0.6 or z < -6.0:
                continue
            rad = rnd.uniform(0.8, 2.0)
            base_c = AB.weighted(rnd, [CORAL_DARK, CORAL_WARM, CORAL_PINK, SEAGRASS], [0.55, 0.2, 0.05, 0.2])
            AB.crown(m, (q.x, q.y, z + rad * 0.2), rad, rad * 0.45, shade(base_c, 1.1), shade(base_c, 0.7), rnd,
                     seg=9, rings=2, mat="isle", squash=0.6)
    return m, isl


def surf_mesh(isl: SkyIsland, n=None):
    """白波：波打ち際の帯と礁の縁の帯。UV の u＝帯に沿った長さ（m ÷ 20）、v＝帯を横切る 0..1。頂点色の A＝強さ。"""
    m = Mesh()
    W, D = isl.W, isl.D
    n = n or max(90, int((W + D) * 1.6 / 5.0))
    ring = []
    for i in range(n + 1):
        th = 2 * math.pi * i / n
        p = isl.shore_point(th, 0.0)
        nrm = Vector((p.x / (W / 2) ** 2, p.y / (D / 2) ** 2, 0)).normalized()
        ring.append((p, nrm, th))
    bands = [
        # (内の距離, 外の距離, 高さ, 切れる閾値, ノイズの向き)
        (lambda th: -1.2, lambda th: 3.8, 0.32, -0.55, 0),
        (lambda th: isl.shelf_width(th) - 2.6, lambda th: isl.shelf_width(th) + 2.2, 0.28, -0.25, 1),
    ]
    for d0f, d1f, z_, keep, k in bands:
        o = isl.off[k]
        u = 0.0
        prev = None
        for i in range(n):
            (p0, n0, th0), (p1, n1, th1) = ring[i], ring[i + 1]
            a0, a1 = p0 + n0 * d0f(th0), p1 + n1 * d0f(th1)
            b0, b1 = p0 + n0 * d1f(th0), p1 + n1 * d1f(th1)
            seg = (a1 - a0).length
            s0 = noise.noise(Vector((math.cos(th0) * 6 + o[0], math.sin(th0) * 6 + o[1], o[2])), noise_basis="PERLIN_NEW")
            s1 = noise.noise(Vector((math.cos(th1) * 6 + o[0], math.sin(th1) * 6 + o[1], o[2])), noise_basis="PERLIN_NEW")
            if prev is None:
                prev = s0
            al0 = smoothstep(keep, keep + 0.35, s0)
            al1 = smoothstep(keep, keep + 0.35, s1)
            if al0 > 0.01 or al1 > 0.01:
                uv = [(u / 20.0, 0.0), (u / 20.0, 1.0), ((u + seg) / 20.0, 1.0), ((u + seg) / 20.0, 0.0)]
                cc = [(1, 1, 1, al0), (1, 1, 1, al0), (1, 1, 1, al1), (1, 1, 1, al1)]
                m.add_face([(a0.x, a0.y, z_), (b0.x, b0.y, z_), (b1.x, b1.y, z_), (a1.x, a1.y, z_)], FOAM, "surf", uv=uv, ccol=cc)
            u += seg
    return m


class AtollIsland:
    """環礁：輪の礁（ほとんど水面のすぐ下）と、ところどころの小島（モツ）。内側は浅い礁湖。"""

    def __init__(self, spec):
        self.R0, self.w = spec["radius"], spec["ring"]
        rnd = random.Random(spec["seed"])
        self.off = [(rnd.uniform(-900, 900), rnd.uniform(-900, 900), rnd.uniform(0, 60)) for _ in range(4)]
        self.rnd = rnd
        self.ph = [rnd.uniform(0, 6.283) for _ in range(4)]
        self.drop = DROP_HI

    def ring_r(self, th):
        return self.R0 * (1 + 0.08 * math.sin(2 * th + self.ph[0]) + 0.05 * math.sin(3 * th + self.ph[1])
                          + 0.04 * fbm(math.cos(th) * 2.5, math.sin(th) * 2.5, self.off[0], 2))

    def motu(self, th):
        """0..1：小島になる度合い。"""
        v = fbm(math.cos(th) * 3.4, math.sin(th) * 3.4, self.off[1], 2) + 0.18 * math.sin(5 * th + self.ph[2])
        return smoothstep(0.12, 0.32, v)

    def sample(self, x, y):
        r = math.hypot(x, y)
        th = math.atan2(y, x)
        rr = self.ring_r(th)
        s = r - rr                         # 輪の中心線から外へ
        w = self.w * (0.85 + 0.3 * fbm(math.cos(th) * 4, math.sin(th) * 4, self.off[2], 2))
        if s > w * 0.5 + self.drop:
            return DEEP_CUT, s, th
        if s < -w * 0.5:
            # 礁湖：浅い砂（中ほどで少し深い）とパッチ礁
            t = smoothstep(-w * 0.5, -w * 0.5 - rr * 0.5, s)
            z = -1.4 - 2.4 * t + 0.4 * fbm(x / 40.0, y / 40.0, self.off[3], 3)
            pr = fbm(x / 28.0, y / 28.0, self.off[2], 2)
            z += 1.4 * smoothstep(0.32, 0.5, pr)
            return min(z, -0.5), s, th
        k = max(0.0, 1.0 - (abs(s) / (w * 0.5)) ** 2)
        mo = self.motu(th)
        z = -0.7 + 0.5 * k + mo * (k ** 0.6) * 4.2
        if s > w * 0.5 - 1.0:
            t = (s - w * 0.5 + 1.0) / self.drop
            z -= (-DEEP_CUT) * t * t
        z += 0.2 * fbm(x / 18.0, y / 18.0, self.off[0], 2)
        return z, s, th

    def colour(self, x, y, z, s, th):
        if z > 1.3:
            p = fbm(x / 30.0, y / 30.0, self.off[3], 2)
            c = mix(AB.SCRUB, AB.GROUND_MID, smoothstep(1.6, 3.6, z))
            return mix(c, AB.CANOPY[1], 0.35 * smoothstep(-0.2, 0.4, p))
        if z > -0.45:
            return mix(SAND_WET, SAND, smoothstep(-0.4, 1.0, z))
        if s < -self.w * 0.5:
            p = fbm(x / 28.0, y / 28.0, self.off[2], 2)
            c = mix(SAND_UNDER, LAGOON_SAND, smoothstep(-self.w * 0.5, -self.w * 0.5 - 60.0, s))
            c = mix(c, CORAL_DARK, smoothstep(0.32, 0.5, p) * 0.7)
            return c
        if s > self.w * 0.5 - 1.0:
            return mix(REEF_CREST, DROP, smoothstep(0.0, self.drop * 0.45, s - self.w * 0.5 + 1.0))
        p = fbm(x / 14.0, y / 14.0, self.off[1], 2)
        return mix(REEF_CREST, CORAL_WARM, smoothstep(-0.1, 0.5, p) * 0.45)


def atoll_mesh(spec, hi):
    at = AtollIsland(spec)
    at.drop = DROP_HI if hi else DROP_LO
    rnd = random.Random(spec["seed"] * (3 if hi else 7))
    m = Mesh()
    R = at.R0 * 1.15 + at.w + at.drop + 10.0
    step = 4.6 if hi else 13.0
    n = int(2 * R / step)
    xs = [-R + 2 * R * i / n for i in range(n + 1)]
    S = [[at.sample(x, y) for x in xs] for y in xs]
    pts = [[(x, y, S[j][i][0]) for i, x in enumerate(xs)] for j, y in enumerate(xs)]
    cols = [[at.colour(x, y, *S[j][i]) for i, x in enumerate(xs)] for j, y in enumerate(xs)]
    for j in range(n):
        for i in range(n):
            corners = ((j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i))
            if all(S[a][b][0] <= DEEP_CUT + 1.0 for a, b in corners):
                continue
            m.add_face([pts[a][b] for a, b in corners], cols[j][i], "isle", smooth=True, ccol=[cols[a][b] for a, b in corners])
    # モツのヤシと茂み
    for k in range(260 if hi else 70):
        th = rnd.uniform(0, 2 * math.pi)
        if at.motu(th) < 0.5:
            continue
        rr = at.ring_r(th) + rnd.uniform(-0.25, 0.25) * at.w
        x, y = math.cos(th) * rr, math.sin(th) * rr
        z = at.sample(x, y)[0]
        if z < 1.5:
            continue
        if hi and rnd.random() < 0.55:
            AB.palm(m, (x, y, z - 0.5), rnd.uniform(8.0, 11.0), (rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2)), rnd, mat="isle")
        else:
            rad = rnd.uniform(3.0, 5.5) * (1.0 if hi else 1.6)
            col = AB.weighted(rnd, AB.CANOPY, AB.CANOPY_W)
            AB.crown(m, (x, y, z + rad * 0.3), rad, rad * 0.8, shade(mix(col, AB.CANOPY_SUN, 0.2), 1.0), shade(col, 0.45), rnd,
                     seg=6 if hi else 5, rings=3, mat="isle")
    return m, at


def atoll_surf(at: AtollIsland, n=300):
    m = Mesh()
    u = 0.0
    o = at.off[2]
    for i in range(n):
        th0, th1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        r0 = at.ring_r(th0) + at.w * 0.5 - 2.0
        r1 = at.ring_r(th1) + at.w * 0.5 - 2.0
        a0 = Vector((math.cos(th0), math.sin(th0), 0))
        a1 = Vector((math.cos(th1), math.sin(th1), 0))
        p0, p1 = a0 * (r0 - 2.6), a1 * (r1 - 2.6)
        q0, q1 = a0 * (r0 + 2.4), a1 * (r1 + 2.4)
        seg = (p1 - p0).length
        s0 = noise.noise(Vector((math.cos(th0) * 7 + o[0], math.sin(th0) * 7 + o[1], o[2])), noise_basis="PERLIN_NEW")
        s1 = noise.noise(Vector((math.cos(th1) * 7 + o[0], math.sin(th1) * 7 + o[1], o[2])), noise_basis="PERLIN_NEW")
        al0, al1 = smoothstep(-0.35, 0.0, s0), smoothstep(-0.35, 0.0, s1)
        if al0 > 0.01 or al1 > 0.01:
            uv = [(u / 20.0, 0.0), (u / 20.0, 1.0), ((u + seg) / 20.0, 1.0), ((u + seg) / 20.0, 0.0)]
            cc = [(1, 1, 1, al0), (1, 1, 1, al0), (1, 1, 1, al1), (1, 1, 1, al1)]
            m.add_face([(p0.x, p0.y, 0.28), (q0.x, q0.y, 0.28), (q1.x, q1.y, 0.28), (p1.x, p1.y, 0.28)], FOAM, "surf", uv=uv, ccol=cc)
        u += seg
    return m


# ---------------------------------------------------------------- 桟橋と小舟
def motorboat(length=6.5):
    m = Mesh()
    L, B = length, length * 0.36
    stations = []
    for k in range(9):
        t = k / 8
        x = -L / 2 + L * t
        half = B / 2 * (1 - (max(0.0, t - 0.5) / 0.5) ** 1.6)
        sheer = 0.7 + 0.2 * t * t
        keel = -0.3 * math.sin(math.pi * min(1.0, t * 1.2)) - 0.05
        stations.append([(x, -half, sheer), (x, -half * 0.75, keel * 0.4), (x, 0.0, keel), (x, half * 0.75, keel * 0.4), (x, half, sheer)])
    m.add_grid(stations, HULL_WHITE, mat="boat", smooth=True)
    for k in range(8):
        a, b = stations[k], stations[k + 1]
        m.add_face([a[0], b[0], b[4], a[4]], SEAT if 2 <= k <= 5 else HULL_WHITE, "boat")
        m.beam(a[0], b[0], 0.07, HULL_TRIM, mat="boat")
        m.beam(a[4], b[4], 0.07, HULL_TRIM, mat="boat")
    m.box((L * 0.06, 0, 1.05), (L * 0.16, B * 0.7, 0.5), hexcol("#3B5470"), mat="boat", top=hexcol("#7FA7C8"))
    return m


def build_pier(isl: SkyIsland):
    """桟橋（板・杭・先の東屋）を、礁湖の向きの海岸から沖へ。返り値：メッシュと、小舟をつなぐ位置（島の座標）。"""
    m = Mesh()
    th = isl.lag_dir + 0.25
    p = isl.shore_point(th, 0.6)
    nrm = Vector((p.x / (isl.W / 2) ** 2, p.y / (isl.D / 2) ** 2, 0)).normalized()
    side = Vector((-nrm.y, nrm.x, 0))
    start = p - nrm * 7.0
    length = 46.0
    width = 3.2
    deck_z = 1.5
    end = start + nrm * length
    # 板（2 m ごとに色を少し変える）
    nseg = int(length / 2.0)
    for k in range(nseg):
        a = start + nrm * (k * 2.0)
        b = start + nrm * (k * 2.0 + 1.9)
        c = DECK if k % 3 else shade(DECK, 0.9)
        quad = [a - side * width / 2, b - side * width / 2, b + side * width / 2, a + side * width / 2]
        m.add_face([(q.x, q.y, deck_z) for q in quad], c, "boat")
    # 縁の梁と杭
    for s in (-1, 1):
        m.beam(start + side * s * width / 2 + Vector((0, 0, deck_z - 0.12)), end + side * s * width / 2 + Vector((0, 0, deck_z - 0.12)),
               0.22, DECK_DARK, mat="boat")
        for k in range(0, int(length / 4.0) + 1):
            q = start + nrm * (k * 4.0) + side * s * (width / 2 - 0.1)
            m.prism(q.x, q.y, -2.5, deck_z + 0.6, 0.16, 0.16, 6, POST, mat="boat", smooth=True)
    # 先の広い床と東屋
    plat = end + nrm * 3.0
    pw = 8.0
    quad = [plat - nrm * 4 - side * pw / 2, plat + nrm * 4 - side * pw / 2, plat + nrm * 4 + side * pw / 2, plat - nrm * 4 + side * pw / 2]
    m.add_face([(q.x, q.y, deck_z) for q in quad], DECK, "boat")
    for sx in (-1, 1):
        for sy in (-1, 1):
            q = plat + nrm * sx * 2.6 + side * sy * 2.6
            m.prism(q.x, q.y, -2.5, deck_z + 3.0, 0.18, 0.18, 6, POST, mat="boat", smooth=True)
    roof_c = [plat + nrm * sx * 3.6 + side * sy * 3.6 for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    apex = (plat.x, plat.y, deck_z + 5.4)
    for i in range(4):
        a, b = roof_c[i], roof_c[(i + 1) % 4]
        m.add_face([(a.x, a.y, deck_z + 3.0), (b.x, b.y, deck_z + 3.0), apex], ROOF if i % 2 else ROOF_DARK, "boat")
    moor = [start + nrm * 18.0 + side * (width / 2 + 2.0), start + nrm * 32.0 - side * (width / 2 + 2.0)]
    return m, moor, nrm


# ---------------------------------------------------------------- Blender の道具
def material(name, color=(1, 1, 1, 1), vertex=True, double=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.85
    if vertex:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = color
    mat.use_backface_culling = not double
    mat.diffuse_color = color
    return mat


MATS = {}


def build_materials():
    MATS["isle"] = material("SFI_Painted")
    MATS["surf"] = material("SFI_Surf")
    MATS["boat"] = material("SFB_Painted")
    MATS["sail"] = material("SFB_Sail", double=True)


class _Mats:
    def __init__(self):
        self.by_key = {"isle": MATS["isle"], "surf": MATS["surf"], "boat": MATS["boat"], "paint": MATS["boat"],
                       "sail": MATS["sail"], "bg": MATS["isle"]}


def collection(name, parent=None):
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if coll.name not in [c.name for c in parent.children]:
        parent.children.link(coll)
    return coll


def clear_collection(coll):
    for o in list(coll.objects):
        data = o.data
        bpy.data.objects.remove(o)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)


def mesh_object(name, mesh: Mesh, coll, location=(0, 0, 0)):
    """頂点・面のリストから 1 つのオブジェクトに。同じ位置の頂点はつなぐ（なめらかな陰影と、書き出しの大きさを減らす）。"""
    obj = AG.create_object(name, mesh, _Mats(), coll, location)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kwargs = dict(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                  export_extras=False, export_cameras=False, export_lights=False, export_animations=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True, **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)
    bpy.ops.object.select_all(action="DESELECT")
    return {"file": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": path.stat().st_size}


def render_previews(cam_col, islands_root):
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    shading.show_shadows = False
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.02, 0.18, 0.35)
    shots = {
        "bl_islands_top": ((0.0, 120.0, 1250.0), (0.0, 60.0, 0.0), 32.0),
        "bl_main_near": ((-120.0, 40.0, 220.0), (-180.0, 60.0, 0.0), 30.0),
        "bl_atoll": ((440.0, 300.0, 520.0), (440.0, 480.0, 0.0), 32.0),
    }
    out = []
    for name, (eye, target, lens) in shots.items():
        cam_data = bpy.data.cameras.get("CAM_" + name) or bpy.data.cameras.new("CAM_" + name)
        cam = bpy.data.objects.get("CAM_" + name) or bpy.data.objects.new("CAM_" + name, cam_data)
        if cam.name not in cam_col.objects:
            cam_col.objects.link(cam)
        cam_data.lens = lens
        cam_data.clip_end = 6000.0
        cam.location = eye
        d = Vector(target) - Vector(eye)
        # 上の向き：見下ろす画は +Y（Godot の奥）を画面の上に
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        if abs(d.normalized().z) > 0.9:
            cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0.0, math.atan2(-d.x, d.y) if math.hypot(d.x, d.y) > 1e-3 else 0.0)
        scene.camera = cam
        scene.render.filepath = str(PREVIEWS / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        out.append(str((PREVIEWS / (name + ".png")).relative_to(ROOT)).replace("\\", "/"))
    return out


# ---------------------------------------------------------------- main
def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError("別の .blend が開いている：" + bpy.data.filepath)
    build_materials()
    old_clouds = bpy.data.collections.get("SF_CLOUDS")       # 前の版の雲の塊（もう作らない）
    if old_clouds is not None:
        clear_collection(old_clouds)
        bpy.data.collections.remove(old_clouds)
    old_mat = bpy.data.materials.get("SFC_Cloud")
    if old_mat is not None and old_mat.users == 0:
        bpy.data.materials.remove(old_mat)
    isl_col = collection("SF_ISLANDS")
    boat_col = collection("SF_BOATS")
    cam_col = collection("SF_CAMERAS")
    for c in (isl_col, boat_col):
        clear_collection(c)
    report = {"triangles": {}, "files": []}

    # --- 島
    root = bpy.data.objects.new("SkyFxIslands", None)
    isl_col.objects.link(root)
    isl_objs = [root]
    layout_islands = []
    pier_info = None
    surf_all = Mesh()
    for spec in ISLANDS:
        loc = b_from_g(*spec["center"])
        entry = {"name": spec["name"], "center": [spec["center"][0], 0.0, spec["center"][1]],
                 "radius": round(max(spec["width"], spec["depth"]) * 0.66 + spec["base_shelf"] + spec["lagoon"]["extra"], 1),
                 "lod_far": spec["lod_far"], "hi": f"SFI_{spec['name']}_Hi", "lo": f"SFI_{spec['name']}_Lo"}
        for hi in (True, False):
            mesh, isl = island_mesh(spec, hi)
            o = mesh_object(f"SFI_{spec['name']}_{'Hi' if hi else 'Lo'}", mesh, isl_col, loc)
            o.parent = root
            isl_objs.append(o)
            report["triangles"][o.name] = tri_count(o)
            if hi:
                surf_all.extend(surf_mesh(isl).transformed(Matrix.Translation(loc)))
                if spec.get("pier"):
                    pm, moor, nrm = build_pier(isl)
                    po = mesh_object(f"SFI_{spec['name']}_Pier", pm, isl_col, loc)
                    po.parent = root
                    isl_objs.append(po)
                    report["triangles"][po.name] = tri_count(po)
                    entry["pier"] = po.name
                    # 桟橋の向き（Godot の Y 回り。船の +X を桟橋の沖の向きへ回す角度）
                    yaw = math.degrees(math.atan2(nrm.y, nrm.x))
                    pier_info = {"moorings": [g_from_b(loc + q) for q in moor], "yaw_deg": round(yaw, 2)}
        layout_islands.append(entry)
    # 環礁
    loc = b_from_g(*ATOLL["center"])
    at = None
    for hi in (True, False):
        mesh, at = atoll_mesh(ATOLL, hi)
        o = mesh_object(f"SFI_Atoll_{'Hi' if hi else 'Lo'}", mesh, isl_col, loc)
        o.parent = root
        isl_objs.append(o)
        report["triangles"][o.name] = tri_count(o)
    surf_all.extend(atoll_surf(at).transformed(Matrix.Translation(loc)))
    s = mesh_object("SFI_Surf_All", surf_all, isl_col, (0.0, 0.0, 0.0))
    s.parent = root
    isl_objs.append(s)
    report["triangles"][s.name] = tri_count(s)
    layout_islands.append({"name": "Atoll", "center": [ATOLL["center"][0], 0.0, ATOLL["center"][1]],
                           "radius": round(ATOLL["radius"] * 1.15 + ATOLL["ring"], 1), "lod_far": ATOLL["lod_far"],
                           "hi": "SFI_Atoll_Hi", "lo": "SFI_Atoll_Lo"})

    # --- 小舟と帆船（原点＝船の真ん中 × 水面、Blender の +X が船首 → Godot の +X）
    boats = []
    for name, mesh in (("SFB_Motor", motorboat(6.5)), ("SFB_Sail", AB.sailboat(9.0, "white", 3))):
        o = mesh_object(name, mesh, boat_col, (0.0, 0.0, 0.0))
        boats.append(o)
        report["triangles"][o.name] = tri_count(o)

    layout = {
        "note": "スカイゲートの空の演出の島の並び。Godot の座標（x 右, y 上, z 手前）、原点＝着地台の中心 × 海面。build_sky_fx.py が書く",
        "islands": layout_islands,
        "surf": "SFI_Surf_All",
        "pier": pier_info,
        "sail_routes": [{"from": [r["from"][0], 0.0, r["from"][1]], "to": [r["to"][0], 0.0, r["to"][1]], "boat": r["boat"],
                         "speed": r["speed"]} for r in SAIL_ROUTES],
    }
    report["layout"] = layout
    report["triangles_total_hi"] = sum(v for k, v in report["triangles"].items() if not k.endswith("_Lo"))

    if DO_EXPORT:
        report["files"].append(export(isl_objs, ISLANDS_GLB))
        report["files"].append(export(boats, BOATS_GLB))
        LAYOUT.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_RENDER:
        report["previews"] = render_previews(cam_col, root)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return {"triangles_total_hi": report["triangles_total_hi"], "triangles": report["triangles"], "files": report["files"]}


if __name__ == "__main__":
    RESULT = main()
