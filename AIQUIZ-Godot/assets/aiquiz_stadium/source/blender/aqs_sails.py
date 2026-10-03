"""帆（布）と帆まわり（ブーム・灯・索具）。

原本（source/master）の帆は、スタンドを横切る面に張った三角帆。ヘッドはマストの頂、タックはマストの根元（ブームの付け根）、
クリューはブームの先（走路側の客席の上）。コースのカメラからは帆の面が正面に見え、ゴール側にある太陽の光が布を透ける。

- 帆はスタンドのブロックと分けて、左右別のメッシュ（AQS_SailRig_R / AQS_SailRig_L）にする。
  ブロックは左右で同じメッシュを 180° 回して使うが、帆は左右ともゴール側（Godot の +Z）へふくらませたいので、ふくらむ向きだけが違う
- 帆の縁は内側へ弓なりにカット（リーチ・フット）、面はふくらみ（キャンバー）とわずかなねじれを持つ
- UV  ：u＝ラフ（マスト側）→リーチ、v＝フット→ヘッド。布のテクスチャ（縫い目・縁の補強）をこの向きで貼る
- UV2 ：x＝揺れの重み（縁で 0、中央で 1）、y＝高さ v。Godot の帆のシェーダーが風の揺れと夜の明るさに使う
"""
from __future__ import annotations

import math

from mathutils import Vector

from aqs_geom import Mesh, hexcol, mix, shade

WHITE = (1.0, 1.0, 1.0, 1.0)


def coons_sail(H, T, K, leech_sag, foot_sag, luff_sag, nu, nv):
    """三角帆の平面（縁は内側へ弓なり）。行 v＝0（フット）→1（ヘッド）、列 u＝0（ラフ）→1（リーチ）。"""
    H, T, K = Vector(H), Vector(T), Vector(K)
    plane_n = (K - T).cross(H - T).normalized()

    def inward(a, b, toward):
        d = (b - a).normalized()
        n = plane_n.cross(d).normalized()
        return n if n.dot(toward - (a + b) / 2) > 0 else -n

    n_foot = inward(T, K, H)
    n_leech = inward(K, H, T)
    n_luff = inward(T, H, K)

    def foot(u):
        return T.lerp(K, u) + n_foot * foot_sag * 4 * u * (1 - u)

    def leech(v):
        return K.lerp(H, v) + n_leech * leech_sag * 4 * v * (1 - v)

    def luff(v):
        return T.lerp(H, v) + n_luff * luff_sag * 4 * v * (1 - v)

    rows = []
    for i in range(nv + 1):
        v = i / nv
        row = []
        for j in range(nu + 1):
            u = j / nu
            p = ((1 - v) * foot(u) + v * H + (1 - u) * luff(v) + u * leech(v)
                 - ((1 - u) * (1 - v) * T + u * (1 - v) * K + (1 - u) * v * H + u * v * H))
            row.append(p)
        rows.append(row)
    return rows


def sail_rig(S, sign: float):
    """帆の一式。S は dimensions.json の sail_rig。sign はふくらむ向き（ブロック座標の Y）。"""
    m = Mesh()
    H, T, K = Vector(S["head"]), Vector(S["tack"]), Vector(S["clew"])
    K.y = sign * S["clew_offset_y"]
    nu, nv = S["grid"]
    rows = coons_sail(H, T, K, S["leech_sag"], S["foot_sag"], S["luff_sag"], nu, nv)
    depth = S["camber_depth"]
    uv_rows, uv2_rows = [], []
    for i, row in enumerate(rows):
        v = i / nv
        urow, u2row = [], []
        for j, p in enumerate(row):
            u = j / nu
            up = u ** 0.85
            f = 4 * up * (1 - up) * math.sin(math.pi * v ** 0.85)
            # ふくらみ：上ほど少し深く（ねじれ）、向きはブロック座標の ±Y
            p.y += sign * depth * f * (0.8 + 0.4 * v)
            urow.append((u, v))
            u2row.append((max(0.0, f), v))
        uv_rows.append(urow)
        uv2_rows.append(u2row)
    rows_t = [[tuple(p) for p in row] for row in rows]
    # 表（ゴール側から見た面）を外向きに。裏は両面の材質で描く
    m.add_grid(rows_t, WHITE, "sail", uv_rows=uv_rows, uv2_rows=uv2_rows, smooth=True, flip=sign > 0)

    wood, rope, steel = hexcol("#7A5A3C"), hexcol("#5A4E44"), hexcol("#C8CDD2")
    lamp = hexcol("#FFE2A8")
    b0 = Vector(S["boom_root"])
    b1 = Vector(S["boom_end"])
    b1.y = sign * S["clew_offset_y"]
    m.tube(b0, b1, S["boom_diameter"] / 2, wood, n=8, caps=True)
    # ブームの先の金具とクリューをつなぐ
    m.box(tuple(b1 + Vector((-0.12, 0, 0))), (0.3, 0.22, 0.22), steel)
    m.tube(b1, K, 0.035, rope, n=5)
    # ブームの下の灯（夜に帆を下から照らす）
    for t in S["boom_lamps_t"]:
        c = b0.lerp(b1, t) - Vector((0, 0, S["boom_diameter"] / 2 + 0.09))
        m.box(tuple(c), (0.34, 0.2, 0.14), shade(steel, 0.8))
        m.box(tuple(c - Vector((0, 0, 0.08))), (0.26, 0.14, 0.03), lamp, "night")
    # トッピングリフト（マストの頂→ブームの先）とヘッドの留め具
    mast_top = Vector((S["mast_x"], 0.0, S["mast_top_z"] - 0.15))
    m.tube(mast_top, b1 + Vector((0, 0, 0.05)), 0.03, rope, n=5)
    m.box(tuple(H + Vector((0.08, 0, 0.05))), (0.2, 0.2, 0.2), steel)
    m.box(tuple(T + Vector((0.08, 0, -0.08))), (0.2, 0.2, 0.2), steel)
    return m
