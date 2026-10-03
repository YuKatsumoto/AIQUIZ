"""部位シート用の下敷き（ブロックアウト）画像を作る。

make_guides.py の Z バッファ描画を使い、無地 #D8D8D8 の背景に部位の外形を塗り分けて描く。
3/4 アンカー用の透視図と、正投影面用の平行投影の両方を出す。Higgsfield には
「2枚目＝寸法・数・配置を厳守」として渡す。寸法は game_constants.json と DESIGN（暫定値）から。

    python assets/aiquiz_stadium/source/guides/make_underlays.py
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

import make_guides as G

HERE = Path(__file__).resolve().parent
BG = (216, 216, 216)
WATER = (188, 196, 204)
D = G.DESIGN


class Ortho:
    """平行投影。view: 'front'（-Z から +Z を見る）/'side'（+X から -X）/'top'（上から）"""

    def __init__(self, view, center, span_w, W=G.W, H=G.H):
        self.view, self.center, self.W, self.H = view, center, W, H
        self.s = W / span_w

    def cam(self, p):
        x, y, z = (p[0] - self.center[0], p[1] - self.center[1], p[2] - self.center[2])
        if self.view == "front":  # -Z 側から +Z を見る（ゲームカメラと同じ向き、+X が画面左）
            return (-x, y, 1000.0 + z)
        if self.view == "side":   # +X 側から -X を見る（画面右＝-Z）
            return (-z, y, 1000.0 - x)
        if self.view == "from_minus_x":  # 走路側（-X）から +X を見る。画面右＝+Z
            return (z, y, 1000.0 + x)
        return (-x, z, 1000.0 - y)  # top: 画面上＝+Z

    def px(self, c):
        return (self.W / 2 + c[0] * self.s, self.H / 2 - c[1] * self.s)


def render_plain(cam, sc, W=G.W, H=G.H, ortho=False):
    if ortho:
        W, H = cam.W, cam.H
    rgb = np.full((H, W, 3), BG, dtype=np.uint8)
    zbuf = np.zeros((H, W))
    old = (G.W, G.H)
    G.W, G.H = W, H
    for pts, col, _ in sc.polys:
        cp = [cam.cam(p) for p in pts] if ortho else G.clip_poly([cam.cam(p) for p in pts])
        if len(cp) < 3:
            continue
        scr = [(*cam.px(c), 1.0 / c[2]) for c in cp]
        for i in range(1, len(scr) - 1):
            G.raster_triangle(rgb, zbuf, scr[0], scr[i], scr[i + 1], col)
    G.W, G.H = old
    return Image.fromarray(rgb)


def water_plane(sc, x0, x1, z0, z1):
    sc.quad([(x0, G.SEA_Y, z0), (x1, G.SEA_Y, z0), (x1, G.SEA_Y, z1), (x0, G.SEA_Y, z1)], WATER)


def stand_blocks(nblocks=2):
    """右スタンド（+X）の nblocks ブロックを、走路側を手前にしてワールド座標で置く。"""
    sc = G.Scene()
    z0, z1 = 0.0, G.BLOCK * nblocks
    G.add_stand(sc, 1, z0, z1, neutral=True)
    water_plane(sc, G.world_x(1, -3), G.world_x(1, D["stand_back_x"] + 3), z0 - 3, z1 + 3)
    sc.box(G.world_x(1, 0.3) - 0.3, G.world_x(1, 0.3) + 0.3, 0.22, 2.02, 3.0, 3.6, (70, 70, 80))
    return sc, (G.world_x(1, 5.0), 0.0, z1 / 2)


def runway_span(length=20.0):
    sc = G.Scene()
    G.add_runway(sc, G.BACK_Z + length)
    # add_runway は BACK_Z から始まる。見やすいよう 0 起点に置き直す
    shifted = G.Scene()
    for pts, col, o in sc.polys:
        shifted.quad([(p[0], p[1], p[2] - G.BACK_Z) for p in pts], col, o)
    water_plane(shifted, -16, 16, -3, length + 3)
    shifted.box(3.0 - 0.3, 3.0 + 0.3, G.DECK_Y, G.DECK_Y + 1.8, 6.0, 6.6, (70, 70, 80))
    return shifted, (0.0, G.DECK_Y - 3.0, length / 2)


def goal_gate():
    sc = G.Scene()
    sc.box(-G.HALF_W, G.HALF_W, G.DECK_Y - 1.0, G.DECK_Y, -4, 8, G.COL["deck"])
    gh = D["gate_height"]
    for sgn in (1, -1):
        sc.box(sgn * 11.8 - 0.3, sgn * 11.8 + 0.3, G.DECK_Y, G.DECK_Y + gh, -0.3, 0.3, G.COL["gate"])
    sc.box(-12.1, 12.1, G.DECK_Y + gh - 0.9, G.DECK_Y + gh, -0.3, 0.3, G.COL["gate"])
    sc.box(-4.0, 4.0, G.DECK_Y + gh - 0.8, G.DECK_Y + gh - 0.1, -0.35, -0.3, G.COL["sign"])  # 文字なしの板
    sc.box(1.0, 1.6, G.DECK_Y, G.DECK_Y + 1.8, -3.0, -2.4, (70, 70, 80))
    return sc, (0.0, G.DECK_Y + 2.5, 0.0)


def goal_stand():
    """ゴール観客席（layout JSON の外形）。走路側（-Z）を向く。原点＝ゴール観客席前面の中心、デッキ上面。"""
    sc = G.Scene()
    L = G.LAYOUT
    w = L["width"] / 2
    y = G.DECK_Y
    tiers = L["tiers"]
    sc.box(-w, w, y - 1.8, y + 0.0, 0.0, L["back_y"], G.COL["goal_stand"])
    # 段：floor_z の高さ、立ち位置 stand_y を中心に奥行き 1.35m（goal_stand/README.md）。通路は spans の隙間
    for t in tiers:
        for a, b in t["spans"]:
            sc.box(a, b, y, y + t["floor_z"], t["stand_y"] - 0.67, t["stand_y"] + 0.68, G.COL["stand_top"])
    sc.box(-w, w, y, y + L["parapet_top"], -0.3, 0.0, G.COL["stand_face"])
    sc.box(-w, w, y, y + L["back_top"], L["back_y"] - 0.3, L["back_y"], G.COL["stand_face"])
    sb = L["scoreboard"]
    sc.box(-sb["width"] / 2, sb["width"] / 2, y + 3.25, y + sb["top"], sb["screen_y"], sb["screen_y"] + 1.0, G.COL["scoreboard"])
    for lx in (-4.1, 4.1):
        sc.box(lx - 0.25, lx + 0.25, y - 1.8, y + 3.25, sb["screen_y"] + 0.3, sb["screen_y"] + 0.8, G.COL["gate"])
    water_plane(sc, -w - 4, w + 4, -6, L["back_y"] + 6)
    sc.box(-0.3, 0.3, y + 1.45, y + 3.25, 3.0, 3.6, (70, 70, 80))
    return sc, (0.0, y + 3.0, 2.5)


def prism(sc, cx, cz, r0, r1, y0, y1, color, n=12):
    """テーパー付きの n 角柱（円塔の近似）。"""
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        p = [(cx + r0 * math.cos(a0), y0, cz + r0 * math.sin(a0)), (cx + r0 * math.cos(a1), y0, cz + r0 * math.sin(a1)),
             (cx + r1 * math.cos(a1), y1, cz + r1 * math.sin(a1)), (cx + r1 * math.cos(a0), y1, cz + r1 * math.sin(a0))]
        sc.quad(p, G.shade(color, 0.8 + 0.2 * abs(math.cos(a0 - 2.3))))
    sc.quad([(cx + r1 * math.cos(2 * math.pi * i / n), y1, cz + r1 * math.sin(2 * math.pi * i / n)) for i in range(n)], color)


def lighthouse():
    """灯台（原本の比率：看板幅 W に対し塔の高さ 1.3W、塔径 0.2〜0.28W、看板 2.5:1 を回廊の直下）。原点＝土台の中心、海面。"""
    W = 52.0
    sea = G.SEA_Y
    sc = G.Scene()
    prism(sc, 0, 0, 34, 26, sea - 1, sea + 8, G.COL["sand"], n=10)           # 岩の小島
    prism(sc, 0, 0, 16, 15, sea + 8, sea + 11, G.COL["lighthouse"], n=16)    # 台座
    top = sea + 11 + 1.3 * W
    prism(sc, 0, 0, 0.14 * W, 0.10 * W, sea + 11, top, G.COL["lighthouse"], n=16)   # 塔
    prism(sc, 0, 0, 0.15 * W, 0.15 * W, top, top + 1.2, G.COL["stand_top"], n=16)    # 回廊
    prism(sc, 0, 0, 0.07 * W, 0.07 * W, top + 1.2, top + 6, (255, 236, 176), n=12)   # 灯室
    prism(sc, 0, 0, 0.08 * W, 0.01, top + 6, top + 9, G.COL["lighthouse"], n=12)     # ドーム
    sh = W / 2.5
    sy1 = top - 2.0
    sy0 = sy1 - sh
    zf = -0.10 * W - 2.0
    sc.box(-W / 2, W / 2, sy0, sy1, zf - 1.2, zf, G.COL["sign"])
    for bx in (-0.35 * W, 0.0, 0.35 * W):                                     # 看板の支持トラス（目安）
        sc.box(bx - 0.4, bx + 0.4, sy0 - 4, sy0, zf - 0.8, -0.05 * W, G.COL["gate"])
    water_plane(sc, -60, 60, -60, 60)
    sc.box(20.0, 20.8, sea + 8, sea + 9.8, -20.0, -19.2, (70, 70, 80))       # 1.8m 人形
    return sc, (0.0, (sea + top) / 2 + 4, 0.0)


def cross_section():
    """コース方向に見た全幅の断面（1ブロック分の奥行き）。+X（P1）が画面左。"""
    sc = G.Scene()
    for side in (1, -1):
        G.add_stand(sc, side, 0.0, G.BLOCK, neutral=True)
    rw = G.Scene()
    G.add_runway(rw, G.BACK_Z + G.BLOCK)
    for pts, col, o in rw.polys:
        sc.quad([(p[0], p[1], p[2] - G.BACK_Z) for p in pts], col, o)
    water_plane(sc, -60, 60, -5, 25)
    return sc


def ortho_views():
    views = {}
    sc = cross_section()
    views["X01_cross_section"] = (Ortho("front", (0.0, 0.5, 10.0), 92.0, 2520, 1080), sc)
    sc, tgt = stand_blocks(2)
    views["P01_runway_side_elev"] = (Ortho("from_minus_x", (tgt[0], 2.0, 20.0), 46.0, 1920, 1080), sc)
    views["P01_end_elev"] = (Ortho("front", (G.world_x(1, 5.0), 1.5, 20.0), 26.0, 1440, 1080), sc)
    views["P01_top"] = (Ortho("top", (G.world_x(1, 5.0), 0.0, 20.0), 46.0, 1920, 1080), sc)
    sc, tgt = runway_span(20.0)
    views["P04_section"] = (Ortho("front", (0.0, -4.5, 10.0), 32.0, 1920, 1080), sc)
    views["P04_side_elev"] = (Ortho("side", (0.0, -4.5, 10.0), 26.0, 1920, 1080), sc)
    sc, tgt = lighthouse()
    views["P05_front_elev"] = (Ortho("front", (0.0, tgt[1] - 4, 0.0), 80.0, 1080, 1620), sc)
    views["P05_side_elev"] = (Ortho("side", (0.0, tgt[1] - 4, 0.0), 80.0, 1080, 1620), sc)
    sc, tgt = goal_gate()
    views["P06_front_elev"] = (Ortho("front", (0.0, 1.5, 0.0), 30.0, 1920, 1080), sc)
    sc, tgt = goal_stand()
    views["P07_front_elev"] = (Ortho("front", (0.0, 4.0, 2.5), 32.0, 1920, 1080), sc)
    views["P07_section"] = (Ortho("side", (0.0, 4.0, 2.5), 20.0, 1920, 1080), sc)
    from PIL import ImageDraw
    for name, (cam, scene) in views.items():
        img = render_plain(cam, scene, ortho=True)
        if cam.view != "top":  # 水面は暗い細線1本で示す
            y = cam.H / 2 - (G.SEA_Y - cam.center[1]) * cam.s
            ImageDraw.Draw(img).line([(0, y), (cam.W, y)], fill=(70, 80, 95), width=3)
        img.save(HERE / f"underlay_{name}.png")
        print(name, cam.W, cam.H, round(cam.s, 3), "px/m")


def three_quarter(target, dist, yaw_deg, pitch_deg, fov=35.0):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    eye = (target[0] + dist * math.cos(pitch) * math.sin(yaw), target[1] + dist * math.sin(pitch),
           target[2] - dist * math.cos(pitch) * math.cos(yaw))
    return G.Camera(eye, target, fov)


def main():
    out = {}
    sc, tgt = stand_blocks(2)
    # 走路側・手前左から見下ろす 3/4（スタンドは +X 側、走路側＝-X から見る）
    out["P01_stand_anchor"] = render_plain(three_quarter(tgt, 62, -58, 24), sc)
    sc, tgt = runway_span(20.0)
    out["P04_runway_anchor"] = render_plain(three_quarter(tgt, 58, -40, 26), sc)
    sc, tgt = goal_gate()
    out["P06_gate_anchor"] = render_plain(three_quarter(tgt, 40, -32, 14), sc)
    sc, tgt = goal_stand()
    out["P07_goal_stand_anchor"] = render_plain(three_quarter(tgt, 48, -34, 20), sc)
    sc, tgt = lighthouse()
    out["P05_lighthouse_anchor"] = render_plain(three_quarter(tgt, 190, -30, 12, fov=40), sc)
    ortho_views()
    for name, img in out.items():
        if img is not None:
            img.save(HERE / f"underlay_{name}.png")
            print(name)


if __name__ == "__main__":
    main()
