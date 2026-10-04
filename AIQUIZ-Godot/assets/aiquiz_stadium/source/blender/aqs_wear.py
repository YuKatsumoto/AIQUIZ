"""地上ステージの質感の底上げ：スタンド・GOAL ゲート・ゴール観客席の頂点色へ AO・水際の汚れ・低周波のムラを焼き込む。

ゲームの材質は頂点色だけの StandardMaterial3D（AQS_Painted）なので、頂点色（COLOR_0）がそのまま面の色になる。
実行時の負荷は 0 のまま、焼き込みだけで見た目を上げる。

- 乗算するだけ：新しい色 = 元の色 × 倍率（倍率の下限は WEAR["floor"]、既定 0.55）。頂点・面・UV・法線・材質は変えない
- 対象は材質 AQS_Painted の面だけ。AQS_NightGlow は頂点色が「灯の色」（shaders/aiquiz_vertex_glow.gdshader が
  ALBEDO と EMISSION の両方に COLOR.rgb を使う）なので触らない。画像の面（IMG_WHITE の頂点色）も触らない。
  GLB の COLOR_0 は RGB の 3 成分（アルファなし）で、アルファは使われていない
- 倍率 = AO（細かい隅 × 広い範囲）× 水際の汚れ × ムラ
    AO     角ごとに法線の半球へ光線を飛ばし、近さで暗くする。細かい方（半径 1 m）は隅・床と壁の接合部・段の裏・座席の下、
           広い方（半径 5 m、弱い）は面の大きい所（デッキの裏・奥まった段）の大づかいな陰
    汚れ   水面（water_z）から高いほど薄い指数。水面より下は最大。暗くして少し緑／茶に寄せる
    ムラ   低周波のノイズ（周期 WEAR["noise_period"] m）の ±数 %。面ごとの単調さを崩す
- 書き出した GLB の頂点数を変えない：同じ（位置・法線・元の色）の角は同じ新しい色にそろえる
  （glTF の書き出しは同じ属性の角を 1 頂点にまとめるので、色が割れると頂点が増える）。頂点・面は増やさない
- 冪等ではない（2 回焼くと 2 回掛かる）。メッシュのカスタムプロパティ aqs_wear_version で二重に焼くのを止める
"""
from __future__ import annotations

import math

import bpy  # noqa: F401  (Blender 内でだけ読み込む)
from mathutils import Vector
from mathutils import noise as mnoise
from mathutils.bvhtree import BVHTree

WEAR_VERSION = 1
PAINT_MATERIALS = ("AQS_Painted",)

WEAR = {
    # 細かい AO（隅・接合部・座席の下）
    "ao_rays": 24,            # 角ごとの光線の数（余弦重みの半球）
    "ao_radius": 1.0,         # この距離（m）より遠い物は影を作らない
    "ao_gain": 1.4,           # 遮蔽率の増幅（隅の遮蔽率は 0.3〜0.5 程度なので、0〜1 に伸ばす）
    "ao_bias": 0.25,          # この遮蔽率（増幅後）までは暗くしない。開けた面の周囲の雑多な遮蔽を無視する
    "ao_strength": 0.42,      # 完全に塞がれた角の暗さ（倍率 1 - 0.42 = 0.58）
    "ao_gamma": 0.9,
    "ao_skip_backface": True,    # 面の裏への当たりを数えない（段が重なる所の、箱の中に隠れた角で暗くしない）
    # 広い AO（大きい面の大づかいな陰）
    "wide_rays": 16,
    "wide_radius": 5.0,
    "wide_gain": 1.5,
    "wide_bias": 0.45,
    "wide_strength": 0.08,
    "ray_lift": 0.04,         # 光線の始点を面から浮かす量と、面の中心へ寄せる量（同一平面の接合部で当たりを取りこぼさない）
    # 水際の汚れ
    "dirt_scale_m": 1.6,      # 水面から上へ汚れが薄くなる距離（指数の 1/e）
    "dirt_strength": 0.90,    # 水面での汚れの強さ
    "dirt_tint": (0.58, 0.63, 0.48),   # 汚れの色（線形、掛ける値）。暗く、少し緑／茶
    # ムラ
    "noise_amp": 0.05,        # ムラの振れ幅
    "noise_period": 6.0,      # ムラの周期（m）
    "floor": 0.55,            # 倍率の下限（各チャンネル）
    "ceil": 1.04,             # 倍率の上限（ムラで少しだけ明るくなる）
}

# 側面スタンドのブロックは 20 m ごとに並ぶ。隣のブロックの影を受けるため、隣の位置に自分の複製を置いて光線を飛ばす
# （ブロックの局所座標：走路に沿う向きが Blender の Y。cap_start は +Y 側、cap_end は -Y 側にだけ隣がある）
BLOCK_LENGTH = 20.0
STAND_TILES = {
    "bay": ((0.0, -BLOCK_LENGTH, 0.0), (0.0, BLOCK_LENGTH, 0.0)),
    "cap_start": ((0.0, BLOCK_LENGTH, 0.0),),
    "cap_end": ((0.0, -BLOCK_LENGTH, 0.0),),
}

_ORIGINAL: dict[str, list[float]] = {}     # 確認用：焼く前の頂点色（メッシュ名 → 平らな RGBA の並び）


def _hammersley_cosine(n: int):
    """余弦重みの半球の方向（局所座標、+Z が法線）。決定的。"""
    out = []
    for i in range(n):
        u = (i + 0.5) / n
        bits, v, f = i, 0.0, 0.5
        while bits:
            if bits & 1:
                v += f
            f *= 0.5
            bits >>= 1
        r = math.sqrt(u)
        phi = 2.0 * math.pi * v
        out.append((r * math.cos(phi), r * math.sin(phi), math.sqrt(max(0.0, 1.0 - u))))
    return out


def _frame(n: Vector):
    a = Vector((0.0, 0.0, 1.0)) if abs(n.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    t = n.cross(a)
    t.normalize()
    return t, n.cross(t)


def _luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _occluder_bvh(obj, tile_shifts, extra):
    verts, tris = [], []

    def add(src, shift):
        me = src.data
        me.calc_loop_triangles()
        base = len(verts)
        off = Vector(shift)
        verts.extend(tuple(v.co + off) for v in me.vertices)
        tris.extend((base + t.vertices[0], base + t.vertices[1], base + t.vertices[2]) for t in me.loop_triangles)

    for src in (obj, *extra):
        add(src, (0.0, 0.0, 0.0))
    for shift in tile_shifts:
        add(obj, shift)
    return BVHTree.FromPolygons(verts, tris, all_triangles=True)


def _occlusion(bvh, pos: Vector, nrm: Vector, centre: Vector, dirs_fine, dirs_wide, p):
    """pos の角（法線 nrm）の遮蔽率 (細かい, 広い)、それぞれ 0..1。始点は面から浮かして、面の中心へ少し寄せる。"""
    n = nrm.normalized()
    t, b = _frame(n)
    lift = p["ray_lift"]
    inward = centre - pos
    inward -= n * inward.dot(n)
    if inward.length > 1e-6:
        inward.normalize()
    else:
        inward = Vector((0.0, 0.0, 0.0))
    origin = pos + n * lift + inward * lift
    skip_back = p["ao_skip_backface"]
    out = []
    for dirs, radius in ((dirs_fine, p["ao_radius"]), (dirs_wide, p["wide_radius"])):
        total = 0.0
        for dx, dy, dz in dirs:
            direction = t * dx + b * dy + n * dz
            hit = bvh.ray_cast(origin, direction, radius)
            if hit[0] is not None:
                if skip_back and hit[1].dot(direction) > 0.0:
                    continue       # 面の裏に当たった＝始点は別の箱の中（段が重なる所の隠れた角）。隠れた角で暗くしない
                total += 1.0 - hit[3] / radius
        out.append(total / len(dirs))
    return out[0], out[1]


def _shaped(occ, gain, bias, gamma=1.0):
    return min(1.0, max(0.0, occ * gain - bias) / (1.0 - bias)) ** gamma


def _multiplier(pos: Vector, occ_fine: float, occ_wide: float, water_z: float, p):
    """角の倍率（R, G, B）。"""
    ao = 1.0 - p["ao_strength"] * _shaped(occ_fine, p["ao_gain"], p["ao_bias"], p["ao_gamma"])
    ao *= 1.0 - p["wide_strength"] * _shaped(occ_wide, p["wide_gain"], p["wide_bias"])
    h = pos.z - water_z
    dirt_amount = p["dirt_strength"] * (1.0 if h <= 0.0 else math.exp(-h / p["dirt_scale_m"]))
    tint = p["dirt_tint"]
    q = pos / p["noise_period"]
    n1 = mnoise.noise(q)
    n2 = mnoise.noise(q * 2.3 + Vector((11.7, 3.1, 7.9)))
    warm = mnoise.noise(q * 0.7 + Vector((5.1, 9.3, 1.7)))
    lum = 0.7 * n1 + 0.3 * n2
    amp = p["noise_amp"]
    noise_rgb = (1.0 + amp * (lum + 0.5 * warm), 1.0 + amp * lum, 1.0 + amp * (lum - 0.5 * warm))
    return tuple(min(p["ceil"], max(p["floor"], ao * (1.0 + (tint[i] - 1.0) * dirt_amount) * noise_rgb[i])) for i in range(3))


def bake_wear(obj, water_z: float, tile_shifts=(), extra=(), params=None, materials=PAINT_MATERIALS, keep_original=False):
    """obj の頂点色 "Col" へ AO・汚れ・ムラを乗算で焼く。返り値は検算用の統計。

    water_z      obj の局所座標での水面の高さ（スタンド −9.2、ゲートとゴール観客席は床の上面が原点なので −8.0）
    tile_shifts  隣のブロックの位置（STAND_TILES）。自分の複製を置いて、ブロックの継ぎ目の AO を連続にする
    extra        同じ局所座標にある、影だけを落とす別のオブジェクト
    """
    p = dict(WEAR)
    p.update(params or {})
    me = obj.data
    if me.get("aqs_wear_version") == WEAR_VERSION:
        return {"object": obj.name, "skipped": "already baked"}
    attr = me.color_attributes.get("Col")
    assert attr is not None and attr.domain == "CORNER" and attr.data_type == "FLOAT_COLOR", f"{obj.name}: 頂点色 Col（角・FLOAT_COLOR）がない"
    assert obj.matrix_world.is_identity, f"{obj.name}: 局所座標で焼くので、変換は単位行列のこと"
    bvh = _occluder_bvh(obj, tile_shifts, extra)
    dirs_fine = _hammersley_cosine(p["ao_rays"])
    dirs_wide = _hammersley_cosine(p["wide_rays"])
    n_loops = len(me.loops)
    cols = [0.0] * (n_loops * 4)
    attr.data.foreach_get("color", cols)
    if keep_original:
        _ORIGINAL[me.name] = list(cols)
    verts = [v.co.copy() for v in me.vertices]
    targets = {i for i, m in enumerate(me.materials) if m is not None and m.name in materials}
    groups: dict[tuple, list] = {}     # 同じ（位置・法線・元の色）の角 → [(角, 細かい遮蔽率, 広い遮蔽率)]
    positions: dict[tuple, Vector] = {}
    for poly in me.polygons:
        if poly.material_index not in targets:
            continue
        centre = poly.center
        for li in poly.loop_indices:
            pos = verts[me.loops[li].vertex_index]
            nrm = me.corner_normals[li].vector
            key = (round(pos.x, 4), round(pos.y, 4), round(pos.z, 4), round(nrm.x, 3), round(nrm.y, 3), round(nrm.z, 3),
                   round(cols[4 * li], 5), round(cols[4 * li + 1], 5), round(cols[4 * li + 2], 5))
            groups.setdefault(key, []).append((li, *_occlusion(bvh, pos, nrm, centre, dirs_fine, dirs_wide, p)))
            positions[key] = pos
    lum_before = lum_after = 0.0
    count = 0
    mult_min = [9.0, 9.0, 9.0]
    mult_sum = 0.0
    by_class = {"up": [0, 0.0], "side": [0, 0.0], "down": [0, 0.0]}      # 法線の向き別の（角の数、倍率の合計）
    visible_mults = []
    for key, members in groups.items():
        occ_fine = sum(m[1] for m in members) / len(members)
        occ_wide = sum(m[2] for m in members) / len(members)
        mult = _multiplier(positions[key], occ_fine, occ_wide, water_z, p)
        nz = key[5]
        cls = by_class["up" if nz > 0.5 else ("down" if nz < -0.5 else "side")]
        if nz >= -0.5:
            visible_mults.append(sum(mult) / 3.0)
        for member in members:
            li = member[0]
            r, g, b = cols[4 * li], cols[4 * li + 1], cols[4 * li + 2]
            nr, ng, nb = r * mult[0], g * mult[1], b * mult[2]
            lum_before += _luminance(r, g, b)
            lum_after += _luminance(nr, ng, nb)
            cols[4 * li], cols[4 * li + 1], cols[4 * li + 2] = nr, ng, nb      # アルファ（cols[4*li+3]）はそのまま
            count += 1
            m = sum(mult) / 3.0
            mult_sum += m
            cls[0] += 1
            cls[1] += m
            for c in range(3):
                mult_min[c] = min(mult_min[c], mult[c])
    attr.data.foreach_set("color", cols)
    me["aqs_wear_version"] = WEAR_VERSION
    me.update()
    seen = by_class["up"][0] + by_class["side"][0]
    seen_sum = by_class["up"][1] + by_class["side"][1]
    visible_mults.sort()
    pct = {f"p{q}": round(visible_mults[min(len(visible_mults) - 1, int(len(visible_mults) * q / 100))], 3) for q in (5, 25, 50, 75, 95)} if visible_mults else {}
    return {"object": obj.name, "corners": count, "unique_corners": len(groups), "loops_total": n_loops,
            "mean_luminance_before": round(lum_before / max(count, 1), 4), "mean_luminance_after": round(lum_after / max(count, 1), 4),
            "mean_multiplier": round(mult_sum / max(count, 1), 4), "min_multiplier_rgb": [round(v, 3) for v in mult_min],
            # 下向きの面（デッキの裏・底）は上から見えないので、見える向き（上・横）の平均と分布も出す
            "mean_multiplier_visible_up_side": round(seen_sum / max(seen, 1), 4), "multiplier_percentiles_visible": pct,
            "mean_multiplier_by_normal": {k: round(v[1] / max(v[0], 1), 4) for k, v in by_class.items()}}


def restore_original(obj):
    """確認用：焼く前の頂点色へ戻す（bake_wear(keep_original=True) で焼いたとき）。"""
    me = obj.data
    cols = _ORIGINAL.get(me.name)
    if cols is None:
        return False
    me.color_attributes["Col"].data.foreach_set("color", cols)
    if "aqs_wear_version" in me:
        del me["aqs_wear_version"]
    me.update()
    return True
