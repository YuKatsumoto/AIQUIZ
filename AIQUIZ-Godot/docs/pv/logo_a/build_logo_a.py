"""PV ロゴ案 A（破片が集まってロゴに）の A2 テスト：ロゴの立方体・床の破片・カメラ・光を組む。

開いている Blender（docs/pv/logo_a/logo_a.blend）の中で実行する（ヘッドレスでは動かさない）:
    exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/docs/pv/logo_a/build_logo_a.py", encoding="utf-8").read())
何度実行しても、コレクション PV_LogoA・PV_LogoA_floor の中身を作り直すだけ。設計は PASSPORT.md。

背景は PV 撮影（tests/pv_capture）をロゴ用のカメラで撮ったフレーム 430:
    Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60
      --script res://tests/pv_capture/pv_capture_bootstrap.gd -- quality=ultra only=430 png tag=logo_a_bg
      "logo_cam=0,-0.7,8.5,0,3.2,-10.0,58"
カメラはその report.json の logo_cam から読む。Godot (x, y, z) Y-up → Blender (x, -z, y) Z-up。画角は縦で合わせる。
"""
import json
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

ROOT = "C:/AIQUIZ/AIQUIZ-Godot/"
LOGO_PNG = ROOT + "assets/branding/logo/aiquiz_logo.png"
BG_DIR = ROOT + "artifacts/pv_capture/logo_a_bg/"
BG_FRAME = 430
BG_PNG = BG_DIR + "pv_%04d.png" % BG_FRAME
COLLECTION = "PV_LogoA"
FLOOR_COLLECTION = "PV_LogoA_floor"
RES = (1920, 1080)


def g2b(x, y, z):
    return Vector((x, -z, y))


def _load_capture():
    with open(BG_DIR + "report.json", encoding="utf-8") as f:
        report = json.load(f)
    cam = report["logo_cam"][str(BG_FRAME)]
    wall_z = None
    for e in report["trace"]:
        if e["f"] <= BG_FRAME:
            wall_z = e["wall_z"]
            p1 = e["p1"]
    return g2b(*cam["eye"]), g2b(*cam["target"]), cam["fov"], wall_z, p1


EYE, TARGET, FOV_V_DEG, WALL_Z, P1_XZ = _load_capture()
FLOOR_Y = -1.2                                   # StageConstants.FLOOR_TOP_Y

## ロゴ：画面の上寄りに横 70%。カメラから LOGO_DIST m の所に立てる
LOGO_COLS = 120
LOGO_SCREEN = (0.5, 0.215)                       # 中心（画面の左上が 0,0）
LOGO_SCREEN_W = 0.70
LOGO_DIST = 13.0
LAYERS = 3
LOGO_TILT_DEG = 6.0   # 上を奥へ少し倒す（見上げたとき底の面が見えて立体に見える）
SEED = 11

BLUE_DARK = (0.008, 0.110, 0.700, 1.0)
BLUE_LIGHT = (0.030, 0.320, 1.000, 1.0)
EDGE_GLOW = (0.55, 0.85, 1.0, 1.0)


# ------------------------------------------------------------------ camera helpers
def cam_basis():
    fwd = (TARGET - EYE).normalized()
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    tan_v = math.tan(math.radians(FOV_V_DEG) / 2)
    tan_h = tan_v * RES[0] / RES[1]
    return fwd, right, up, tan_v, tan_h


def screen_point(u, v, dist):
    """画面の (u, v)（左上 0,0・右下 1,1）を通る視線上で、カメラから dist m（視線方向の奥行き）の点。"""
    fwd, right, up, tan_v, tan_h = cam_basis()
    return EYE + dist * (fwd + right * ((2 * u - 1) * tan_h) + up * ((1 - 2 * v) * tan_v))


def to_screen(p):
    fwd, right, up, tan_v, tan_h = cam_basis()
    d = p - EYE
    z = d.dot(fwd)
    return ((d.dot(right) / (z * tan_h) + 1) / 2, (1 - d.dot(up) / (z * tan_v)) / 2, z)


LOGO_CENTER = screen_point(LOGO_SCREEN[0], LOGO_SCREEN[1], LOGO_DIST)
LOGO_WIDTH = LOGO_SCREEN_W * 2 * LOGO_DIST * cam_basis()[4]


# ------------------------------------------------------------------ helpers
def ensure_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    for ob in list(col.objects):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
    return col


def link(col, ob):
    col.objects.link(ob)
    return ob


def logo_mask():
    """ロゴの PNG の不透明な所を、横 LOGO_COLS マスの格子に落とす（行は上から）。"""
    img = bpy.data.images.load(LOGO_PNG, check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    alpha = px.reshape(h, w, 4)[::-1, :, 3]  # 上から
    ys = np.where(alpha.max(axis=1) > 0.5)[0]
    xs = np.where(alpha.max(axis=0) > 0.5)[0]
    alpha = alpha[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1]
    bh, bw = alpha.shape
    cell = bw / LOGO_COLS
    rows = int(round(bh / cell))
    mask = np.zeros((rows, LOGO_COLS), dtype=bool)
    for j in range(rows):
        y0, y1 = int(j * cell), int(min(bh, (j + 1) * cell))
        for i in range(LOGO_COLS):
            x0, x1 = int(i * cell), int(min(bw, (i + 1) * cell))
            if y1 > y0 and x1 > x0 and alpha[y0:y1, x0:x1].mean() > 0.45:
                mask[j, i] = True
    return mask


def logo_frame():
    """ロゴの向き：X＝画面の右、Y＝奥（カメラから離れる向き）、Z＝上。立てたまま横だけカメラへ向け、上を少し奥へ倒す。"""
    d = LOGO_CENTER - EYE
    f = Vector((d.x, d.y, 0.0)).normalized()
    right = f.cross(Vector((0, 0, 1))).normalized()
    tilt = Matrix.Rotation(math.radians(-LOGO_TILT_DEG), 3, right)
    f = tilt @ f
    up = right.cross(f).normalized()
    return Matrix((
        (right.x, f.x, up.x, LOGO_CENTER.x),
        (right.y, f.y, up.y, LOGO_CENTER.y),
        (right.z, f.z, up.z, LOGO_CENTER.z),
        (0, 0, 0, 1),
    ))


def shard_material():
    mat = bpy.data.materials.get("MAT_logo_shard") or bpy.data.materials.new("MAT_logo_shard")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_type = "GEOMETRY"
    attr.attribute_name = "shard_rand"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = BLUE_DARK
    ramp.color_ramp.elements[1].color = BLUE_LIGHT
    whiten = nt.nodes.new("ShaderNodeMix")
    whiten.data_type = "RGBA"
    whiten.blend_type = "MIX"
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    edge_pow = nt.nodes.new("ShaderNodeMath")
    edge_pow.operation = "POWER"
    edge_pow.inputs[1].default_value = 2.5
    edge_mul = nt.nodes.new("ShaderNodeMath")
    edge_mul.operation = "MULTIPLY"
    edge_mul.inputs[1].default_value = 0.8

    nt.links.new(attr.outputs["Fac"], ramp.inputs["Fac"])
    # 立方体ごとに白へ 0〜12%（ゲームのドアの破片と同じ考え方）
    rand_white = nt.nodes.new("ShaderNodeMath")
    rand_white.operation = "MULTIPLY"
    rand_white.inputs[1].default_value = 0.12
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    scale7 = nt.nodes.new("ShaderNodeMath")
    scale7.operation = "MULTIPLY"
    scale7.inputs[1].default_value = 7.31
    nt.links.new(attr.outputs["Fac"], scale7.inputs[0])
    nt.links.new(scale7.outputs[0], frac.inputs[0])
    nt.links.new(frac.outputs[0], rand_white.inputs[0])
    nt.links.new(rand_white.outputs[0], whiten.inputs[0])     # Factor（RGBA の Mix は同名のソケットが複数ある）
    nt.links.new(ramp.outputs["Color"], whiten.inputs[6])   # A (RGBA)
    whiten.inputs[7].default_value = (1, 1, 1, 1)            # B (RGBA)
    nt.links.new(whiten.outputs[2], bsdf.inputs["Base Color"])

    bsdf.inputs["Roughness"].default_value = 0.32
    bsdf.inputs["Coat Weight"].default_value = 0.6
    bsdf.inputs["Coat Roughness"].default_value = 0.04
    bsdf.inputs["Specular IOR Level"].default_value = 0.4
    bsdf.inputs["Emission Color"].default_value = EDGE_GLOW
    nt.links.new(lw.outputs["Facing"], edge_pow.inputs[0])
    nt.links.new(edge_pow.outputs[0], edge_mul.inputs[0])
    nt.links.new(edge_mul.outputs[0], bsdf.inputs["Emission Strength"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add_cube(bm, rand_layer, matrix, rand_value):
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)
    faces = set()
    for v in ret["verts"]:
        faces.update(v.link_faces)
    for f in faces:
        f[rand_layer] = rand_value


def bevel(ob, width):
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = 2
    mod.limit_method = "ANGLE"
    mod.use_clamp_overlap = True
    return mod


# ------------------------------------------------------------------ build
def build():
    rng = random.Random(SEED)
    scene = bpy.context.scene
    col = ensure_collection(COLLECTION)
    floor_col = ensure_collection(FLOOR_COLLECTION)
    mat = shard_material()
    mask = logo_mask()
    rows, cols = mask.shape
    cell = LOGO_WIDTH / cols
    frame = logo_frame()

    def cell_local(i, j, k):
        return Vector(((i + 0.5 - cols / 2) * cell, (k + 0.5) * cell, (rows / 2 - j - 0.5) * cell))

    # 大きな立方体：3×3、次に 2×2 のマスが全部文字の中で空いていれば 1 個にまとめ（奥行きも同じマス数）、
    # 残りのマスだけ小さい粒にする。文字の輪郭は小さい粒で形を保ち、中はゴロッとした大きなブロックに見える
    used = np.zeros_like(mask)
    big = []   # (i, j, n)
    for n_size in (3, 2):
        for j in range(rows - n_size + 1):
            for i in range(cols - n_size + 1):
                blk = (slice(j, j + n_size), slice(i, i + n_size))
                if mask[blk].all() and not used[blk].any() and rng.random() < 0.9:
                    big.append((i, j, n_size))
                    used[blk] = True
    small = [(i, j) for j in range(rows) for i in range(cols) if mask[j, i] and not used[j, i]]
    arriving = set(rng.sample(small, 10))

    mesh = bpy.data.meshes.new("LOGO_shards")
    bm = bmesh.new()
    rand_layer = bm.faces.layers.float.new("shard_rand")
    count_big = count_small = 0
    for (i, j, n_size) in big:
        half = n_size / 2
        p = Vector(((i + half - cols / 2) * cell, half * cell, (rows / 2 - j - half) * cell))
        p += Vector((rng.uniform(-0.04, 0.04), 0, rng.uniform(-0.04, 0.04))) * cell
        if rng.random() < 0.3:
            p.y -= rng.uniform(0.1, 0.4) * cell  # 少し手前に出たブロック
        rot = Euler([math.radians(rng.uniform(-3.0, 3.0)) for _ in range(3)]).to_matrix().to_4x4()
        s = n_size * cell * rng.uniform(0.95, 0.98)
        add_cube(bm, rand_layer, Matrix.Translation(p) @ rot @ Matrix.Diagonal((s, s, s, 1)), rng.random())
        count_big += 1
        for k in range(n_size, LAYERS):       # 2×2 のブロックの奥の層
            for dj in range(n_size):
                for di in range(n_size):
                    q = cell_local(i + di, j + dj, k)
                    s2 = cell * 0.95
                    add_cube(bm, rand_layer, Matrix.Translation(q) @ Matrix.Diagonal((s2, s2, s2, 1)), rng.random())
                    count_small += 1
    for (i, j) in small:
        for k in range(LAYERS):
            if k == 0 and (i, j) in arriving:
                continue
            p = cell_local(i, j, k)
            p += Vector((rng.uniform(-0.012, 0.012), rng.uniform(-0.05, 0.05), rng.uniform(-0.012, 0.012))) * cell
            rot = Euler([math.radians(rng.uniform(-1.5, 1.5)) for _ in range(3)]).to_matrix().to_4x4()
            s = cell * rng.uniform(0.94, 0.98)
            add_cube(bm, rand_layer, Matrix.Translation(p) @ rot @ Matrix.Diagonal((s, s, s, 1)), rng.random())
            count_small += 1
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    logo = link(col, bpy.data.objects.new("LOGO_shards", mesh))
    logo.matrix_world = frame
    logo.data.materials.append(mat)
    bevel(logo, cell * 0.14)

    unit = bpy.data.meshes.get("FRAG_unit") or _unit_cube_mesh()

    # 空きマスへ飛び込む途中の破片（フレーム 0→2 で 1.6 m×2 進む。フレーム 1 を動きのブレ付きで描く）
    for n, (i, j) in enumerate(sorted(arriving)):
        slot = frame @ cell_local(i, j, 0)
        outward = (slot - LOGO_CENTER)
        outward = Vector((outward.x, outward.y * 0.3, outward.z)).normalized()
        start = slot + (outward + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.9, -0.2), rng.uniform(-0.3, 0.6)))).normalized() * rng.uniform(1.4, 3.2)
        ob = link(col, bpy.data.objects.new(f"FRAG_arrive_{n:02d}", unit))
        _frag_setup(ob, mat, cell * rng.uniform(0.92, 1.0), rng)
        v = (slot - start).normalized() * 1.6
        ob.location = start - v
        ob.keyframe_insert("location", frame=0)
        ob.location = start + v
        ob.keyframe_insert("location", frame=2)
        _linear(ob)

    # ロゴのまわりの宙に止まった破片
    placed = 0
    rows_h = rows * cell
    while placed < 30:
        off = Vector((rng.uniform(-LOGO_WIDTH * 0.72, LOGO_WIDTH * 0.72), rng.uniform(-3.5, 3.0), rng.uniform(-rows_h * 1.1, rows_h * 1.6)))
        if abs(off.x) < LOGO_WIDTH / 2 + 0.3 and abs(off.z) < rows_h / 2 + 0.3:
            continue
        p = LOGO_CENTER + off
        if to_screen(p)[1] > 0.40:               # P1 と床の上には浮かせない
            continue
        ob = link(col, bpy.data.objects.new(f"FRAG_float_{placed:02d}", unit))
        _frag_setup(ob, mat, rng.uniform(0.12, 0.34), rng)
        ob.location = p
        placed += 1

    # カメラの近くの大きな破片（画面の端・ぼける）
    fwd, right, up, tan_v, tan_h = cam_basis()
    for n, (nx, ny, d, s) in enumerate([(0.03, 0.14, 1.9, 0.30), (0.97, 0.86, 2.1, 0.34), (0.92, 0.06, 2.8, 0.24)]):
        ob = link(col, bpy.data.objects.new(f"FRAG_near_{n}", unit))
        _frag_setup(ob, mat, s, rng)
        ob.location = screen_point(nx, ny, d)

    rubble = _floor_rubble(col, floor_col, mat, unit, rng)
    _camera(col)
    _lights(col)
    _world()
    _render_settings(scene)
    return {"big": count_big, "small": count_small, "rows": rows, "cols": cols, "cell_m": round(cell, 4),
            "logo_width_m": round(LOGO_WIDTH, 2), "logo_center_b": [round(c, 2) for c in LOGO_CENTER],
            "rubble": rubble, "wall_z": WALL_Z, "objects": len(col.objects) + len(floor_col.objects)}


def _p1_screen_box():
    """背景の P1（踊っている体）が画面で占める範囲。その後ろには床の破片を置かない（AE で上に重なってしまう）。"""
    x, z = P1_XZ
    pts = [to_screen(g2b(x + dx, y, z + dz)) for dx in (-0.95, 0.95) for y in (FLOOR_Y, 1.3) for dz in (-0.5, 0.5)]
    return (min(p[0] for p in pts) - 0.02, min(p[1] for p in pts) - 0.02, max(p[0] for p in pts) + 0.02, max(p[1] for p in pts) + 0.02)


def _floor_rubble(col, floor_col, mat, unit, rng):
    """突破で散った小さな青い破片を床に置く（穴の足元に多め、手前へ散らす）。床は影だけ受け取る。"""
    box = _p1_screen_box()
    p1_dist = (g2b(P1_XZ[0], 0, P1_XZ[1]) - EYE).length
    hole_x = 3.5
    placed = 0
    tries = 0
    while placed < 46 and tries < 4000:
        tries += 1
        if placed < 22:   # 穴の足元
            gx, gz = rng.gauss(hole_x, 1.3), WALL_Z + abs(rng.gauss(0.0, 1.4)) + 0.35
        else:             # 手前へ散ったもの
            gx, gz = rng.uniform(-2.0, 9.0), rng.uniform(WALL_Z + 1.0, P1_XZ[1] + 4.0)
        s = rng.uniform(0.12, 0.34) if placed % 5 else rng.uniform(0.35, 0.55)
        p = g2b(gx, FLOOR_Y + s * 0.5, gz)
        sx, sy, sd = to_screen(p)
        if not (0.0 < sx < 1.0 and 0.0 < sy < 1.0) or sd < 2.0:
            continue
        if box[0] < sx < box[2] and box[1] < sy < box[3] and (p - EYE).length > p1_dist - 0.3:
            continue  # P1 の後ろ
        ob = link(col, bpy.data.objects.new(f"RUBBLE_{placed:02d}", unit))   # 光を受けるのでロゴと同じコレクション
        _frag_setup(ob, mat, s, rng)
        ob.rotation_euler = Euler((0.0, 0.0, rng.uniform(0, math.tau)))   # 床に寝かせる
        ob.location = p
        placed += 1
    # 影を受ける床（影だけを透過 PNG に描く）
    me = bpy.data.meshes.new("FLOOR_catcher")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    bm.to_mesh(me)
    bm.free()
    floor = link(floor_col, bpy.data.objects.new("FLOOR_catcher", me))
    floor.location = g2b(0.0, FLOOR_Y, (WALL_Z + P1_XZ[1] + 9.0) / 2)
    floor.scale = (13.0, (P1_XZ[1] + 9.0 - WALL_Z) / 2, 1.0)
    floor.is_shadow_catcher = True
    return placed


def _unit_cube_mesh():
    mesh = bpy.data.meshes.new("FRAG_unit")
    bm = bmesh.new()
    rand_layer = bm.faces.layers.float.new("shard_rand")
    add_cube(bm, rand_layer, Matrix.Identity(4), 0.5)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def _frag_setup(ob, mat, size, rng):
    if not ob.data.materials:
        ob.data.materials.append(mat)
    ob.scale = (size, size, size)
    ob.rotation_euler = Euler([rng.uniform(0, math.tau) for _ in range(3)])
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.11
    mod.segments = 2
    mod.limit_method = "ANGLE"
    mod.use_clamp_overlap = True


def _linear(ob):
    ad = ob.animation_data
    if ad is None or ad.action is None:
        return
    for fc in _fcurves(ad.action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def _fcurves(action):
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


def _camera(col):
    data = bpy.data.cameras.new("CAM_godot_match")
    data.sensor_fit = "VERTICAL"
    data.sensor_height = 24.0
    data.lens = 12.0 / math.tan(math.radians(FOV_V_DEG) / 2)
    data.clip_start = 0.05
    data.clip_end = 500.0
    data.dof.use_dof = True
    data.dof.focus_distance = (LOGO_CENTER - EYE).length
    data.dof.aperture_fstop = 1.4
    img = bpy.data.images.load(BG_PNG, check_existing=True)
    data.show_background_images = True
    bg = data.background_images.new()
    bg.image = img
    bg.alpha = 1.0
    bg.display_depth = "BACK"
    cam = link(col, bpy.data.objects.new("CAM_godot_match", data))
    cam.location = EYE
    cam.rotation_euler = (TARGET - EYE).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def _aim(ob, direction):
    ob.rotation_euler = direction.normalized().to_track_quat("-Z", "Y").to_euler()


def _lights(col):
    # 光は床（影を受けるだけの面）を照らさない：ロゴの影が P1 の足元に落ちないように。
    # 床の破片の接地の影は、空の光（world）がつくる柔らかい影だけにする
    receivers = col
    # 太陽：実機と同じく壁の向こう・右上から（P1 の影がカメラ側・少し左へ落ちている）
    sun = bpy.data.lights.new("LGT_sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(1.5)
    sun.color = (1.0, 0.97, 0.92)
    ob = link(col, bpy.data.objects.new("LGT_sun", sun))
    _aim(ob, Vector((-0.25, -0.55, -0.80)))
    ob["purpose"] = "実機の太陽に合わせた逆光。立方体の上の面と縁に光を乗せる"
    ob.light_linking.receiver_collection = receivers
    # 正面の大きな面光源：ロゴの正面を読ませる
    key = bpy.data.lights.new("LGT_key_front", "AREA")
    key.shape = "RECTANGLE"
    key.size = 10.0
    key.size_y = 5.0
    key.energy = 500.0
    key.color = (0.92, 0.96, 1.0)
    ob = link(col, bpy.data.objects.new("LGT_key_front", key))
    ob.location = EYE + Vector((0.0, -2.0, 6.0))
    _aim(ob, LOGO_CENTER - ob.location)
    ob["purpose"] = "スタジアムの照明のつもりの正面の光。ロゴの面の青と艶を見せる"
    ob.light_linking.receiver_collection = receivers
    # ロゴの後ろの閃光：立方体の縁と隙間を強く光らせる（AE の閃光と同じ位置）
    flash = bpy.data.lights.new("LGT_flash_back", "POINT")
    flash.energy = 4000.0
    flash.shadow_soft_size = 0.8
    flash.color = (0.85, 0.94, 1.0)
    ob = link(col, bpy.data.objects.new("LGT_flash_back", flash))
    ob.location = LOGO_CENTER + (LOGO_CENTER - EYE).normalized() * 1.8
    ob["purpose"] = "完成の閃光。立方体の縁と隙間を後ろから光らせる（AE の白い光と同じ位置）"
    ob.light_linking.receiver_collection = receivers


def _world():
    world = bpy.data.worlds.get("WORLD_sky") or bpy.data.worlds.new("WORLD_sky")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.42
    ramp.color_ramp.elements[0].color = (0.10, 0.12, 0.17, 1.0)   # 下（灰色の床）。立方体の底の面を濃くして立体に見せる
    horizon = ramp.color_ramp.elements.new(0.52)
    horizon.color = (0.62, 0.74, 0.86, 1.0)                       # 地平線（海と白いスタンド）
    ramp.color_ramp.elements[2].position = 0.85
    ramp.color_ramp.elements[2].color = (0.18, 0.42, 0.95, 1.0)   # 天頂の青
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.0
    mr.inputs["From Max"].default_value = 1.0
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def _render_settings(scene):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 0, 2
    scene.frame_set(1)
    scene.render.film_transparent = True
    scene.render.use_motion_blur = True
    scene.render.motion_blur_shutter = 0.5
    scene.cycles.samples = 192
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.view_settings.view_transform = "Standard"  # 実機の画（ACES）と同じくらい鮮やかに
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    prefs = bpy.context.preferences.addons.get("cycles")
    if prefs is not None:
        cp = prefs.preferences
        for dev_type in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
            try:
                cp.compute_device_type = dev_type
                cp.get_devices()
                if any(d.type == dev_type for d in cp.devices):
                    for d in cp.devices:
                        d.use = d.type == dev_type
                    scene.cycles.device = "GPU"
                    break
            except TypeError:
                continue


result = build()
