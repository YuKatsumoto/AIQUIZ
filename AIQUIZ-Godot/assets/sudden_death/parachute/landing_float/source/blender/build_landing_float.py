"""着地台（landing_float）を作る。仕様：SCENE_PASSPORT.md（このフォルダ）と docs/sudden_death_v2/parachute.md 6.5節。

ライブの Blender（Higgsfield の Blender 連携）で実行する。ヘッドレスで代替しない（AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-render" で確認レンダーを出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/parachute/landing_float/source/blender/build_landing_float.py", run_name="__main__")
先に python assets/sudden_death/parachute/landing_float/source/make_float_textures.py でテクスチャを描いておく。

座標：Blender の Z が上、メートル。原点＝浮き台の中心 × 喫水線（水面 z = 0）。Godot では (x, z, -y)。
管の上の位置は (theta, phi) で表す：theta＝輪のまわりの角度（+X から反時計回り）、phi＝管の断面の角度（0＝外側の赤道、90°＝真上、180°＝内側の赤道）。
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
ASSET = SOURCE.parent
TEX = SOURCE / "textures"
PREVIEWS = SOURCE / "previews"
GLB = ASSET / "landing_float.glb"
LAYOUT = ASSET / "landing_float_layout.json"
REPORT = SOURCE / "build_report.json"
BLEND = HERE / "landing_float.blend"

# ---------------------------------------------------------------- 寸法（make_float_textures.py と同じ値）
RING_R = 3.55
TUBE_R = 0.52
TUBE_Z = 0.28
CHAMBERS = 12
SEG_PER_CHAMBER = 20
TUBE_V = 40
PINCH = 0.03          # 部屋の境目のくびれ（管の半径に対する割合）
PINCH_W = 0.07        # くびれの幅（m）
PAD_R = 3.15
PAD_TOP = 0.56
PAD_BOTTOM = 0.36
PAD_TEX_R = 3.2
CUSHION_R = 1.15
## 2026-10-18：中心の盛り上がったクッションはやめた（シンプルに）。0 で平らなマット。
CUSHION_H = 0.0
HULL_R = 3.5
HULL_Z = -0.18

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS


# ---------------------------------------------------------------- 管の上の位置

def tube_radius(theta):
    """部屋の境目でくびれる管の半径。"""
    chamber = theta / (2 * math.pi) * CHAMBERS
    frac = chamber - math.floor(chamber)
    dist = min(frac, 1 - frac) * (2 * math.pi * RING_R / CHAMBERS)
    return TUBE_R * (1 - PINCH * math.exp(-(dist / PINCH_W) ** 2))


def e_r(theta):
    return Vector((math.cos(theta), math.sin(theta), 0.0))


def e_t(theta):
    return Vector((-math.sin(theta), math.cos(theta), 0.0))


def tube_point(theta, phi, off=0.0):
    c = e_r(theta) * RING_R + Vector((0, 0, TUBE_Z))
    n = e_r(theta) * math.cos(phi) + Vector((0, 0, math.sin(phi)))
    return c + n * (tube_radius(theta) + off)


def tube_normal(theta, phi):
    return (e_r(theta) * math.cos(phi) + Vector((0, 0, math.sin(phi)))).normalized()


def tube_frame(theta, phi, off=0.0):
    """管の上の 1 点の向き：x＝輪に沿う向き、y＝管の断面を上へ回る向き、z＝外向きの法線。"""
    n = tube_normal(theta, phi)
    t = e_t(theta)
    b = n.cross(t).normalized() * -1.0
    return Matrix((t, b, n)).transposed().to_4x4() @ Matrix.Identity(4), tube_point(theta, phi, off)


def place(theta, phi, off=0.0):
    rot, pos = tube_frame(theta, phi, off)
    m = rot.copy()
    m.translation = pos
    return m


# ---------------------------------------------------------------- メッシュの道具

class Builder:
    """1 つのオブジェクトの bmesh。uv があれば UV を書く。"""

    def __init__(self, name, material, smooth=True):
        self.name = name
        self.material = material
        self.smooth = smooth
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def grid(self, pts, closed_u=False, closed_v=False, uvs=None):
        """pts[i][j] の格子を面にする。閉じた向きは最後と最初をつなぐ。uvs[i][j] は閉じた向きの 1 つ先（i = len）も持つ。"""
        nu, nv = len(pts), len(pts[0])
        verts = [[self.bm.verts.new(p) for p in row] for row in pts]
        iu = nu if closed_u else nu - 1
        iv = nv if closed_v else nv - 1
        for i in range(iu):
            for j in range(iv):
                i2, j2 = (i + 1) % nu, (j + 1) % nv
                f = self.bm.faces.new((verts[i][j], verts[i2][j], verts[i2][j2], verts[i][j2]))
                f.smooth = self.smooth
                if uvs is not None:
                    for loop, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                        loop[self.uv].uv = uvs[a][b]
        return verts

    def add_bm(self, other_bm, matrix=None):
        if matrix is not None:
            bmesh.ops.transform(other_bm, matrix=matrix, verts=other_bm.verts)
        me = bpy.data.meshes.new("_tmp")
        other_bm.to_mesh(me)
        other_bm.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def cylinder(self, matrix, r1, r2, depth, segs=16, caps=True):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
        for f in bm.faces:
            f.smooth = self.smooth
        self.add_bm(bm, matrix)

    def sphere(self, matrix, r, segs=16, rings=8, hemisphere=False):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        if hemisphere:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-5], context="VERTS")
        for f in bm.faces:
            f.smooth = True
        self.add_bm(bm, matrix)

    def box(self, matrix, size, bevel=0.0, segs=2):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES", profile=0.5)
        for f in bm.faces:
            f.smooth = bevel > 0
        self.add_bm(bm, matrix)

    def torus(self, matrix, major, minor, segs=24, sides=8, arc=2 * math.pi):
        closed = arc >= 2 * math.pi - 1e-6
        n = segs if closed else segs + 1
        pts = []
        for i in range(n):
            a = arc * i / segs
            c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
            d = Vector((math.cos(a), math.sin(a), 0))
            pts.append([matrix @ (c + d * math.cos(2 * math.pi * j / sides) * minor + Vector((0, 0, math.sin(2 * math.pi * j / sides) * minor)))
                        for j in range(sides)])
        self.grid(pts, closed_u=closed, closed_v=True)

    def sweep(self, path, radius, sides=10, caps=True):
        """点の列に沿った丸い管（平行移動の枠）。radius は数か、点ごとの列。"""
        radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(path)
        tangents = []
        for i in range(len(path)):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            tangents.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
        u = tangents[0].cross(ref).normalized()
        rows = []
        for i, p in enumerate(path):
            t = tangents[i]
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u).normalized()
            rows.append([p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radii[i] for k in range(sides)])
        verts = self.grid(rows, closed_u=False, closed_v=True)
        if caps:
            for row in (verts[0], verts[-1]):
                f = self.bm.faces.new(row if row is verts[-1] else list(reversed(row)))
                f.smooth = False

    def finish(self, collection):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new("PRT_" + self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(MAT[self.material])
        obj = bpy.data.objects.new("PRT_" + self.name, me)
        collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------- 材質

MAT = {}


def image(name):
    path = TEX / name
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(str(path))
    else:
        img.filepath = str(path)
        img.reload()
    return img


def principled(name, color, rough=0.6, metal=0.0, emit=None, strength=0.0, tex=None, orm=None, alpha_clip=False, double=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-300, 0)
    out.location = (0, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if tex:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = image(tex)
        t.location = (-800, 120)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_clip:
            nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    if orm:
        t2 = nt.nodes.new("ShaderNodeTexImage")
        t2.image = image(orm)
        t2.image.colorspace_settings.name = "Non-Color"
        t2.location = (-800, -200)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-520, -200)
        nt.links.new(t2.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.use_backface_culling = not double
    MAT[name] = mat
    return mat


def build_materials():
    principled("LF_Tube", (1, 1, 1), 0.55, tex="lf_tube.png", orm="lf_tube_orm.png")
    principled("LF_Pad", (1, 1, 1), 0.82, tex="lf_pad.png", orm="lf_pad_orm.png")
    principled("LF_Rubber", (0.045, 0.048, 0.055), 0.72)
    principled("LF_SeamTape", (0.62, 0.60, 0.55), 0.6)
    principled("LF_Piping", (0.06, 0.065, 0.07), 0.6)
    principled("LF_Metal", (0.78, 0.79, 0.80), 0.28, metal=1.0)
    principled("LF_Rope", (0.07, 0.075, 0.08), 0.9)
    principled("LF_Webbing", (0.09, 0.095, 0.10), 0.8)
    principled("LF_Pole", (0.92, 0.92, 0.90), 0.35)
    principled("LF_Accent", (0.92, 0.38, 0.06), 0.45)
    principled("LF_LampAmber", (1.0, 0.62, 0.12), 0.25, emit=(1.0, 0.58, 0.1), strength=3.0)
    principled("LF_Plastic", (0.70, 0.71, 0.73), 0.45)
    principled("LF_CameraBody", (0.035, 0.037, 0.042), 0.42)
    principled("LF_LensGlass", (0.01, 0.012, 0.016), 0.05)
    principled("LF_TallyRed", (1.0, 0.06, 0.04), 0.3, emit=(1.0, 0.05, 0.03), strength=4.0)


# ---------------------------------------------------------------- 部品

def chamber_thetas():
    out = []
    for k in range(CHAMBERS):
        for j in range(SEG_PER_CHAMBER):
            t = 0.5 - 0.5 * math.cos(math.pi * j / SEG_PER_CHAMBER)
            out.append((k + t) / CHAMBERS * 2 * math.pi)
    return out


def build_tube(col):
    b = Builder("Tube", "LF_Tube")
    thetas = chamber_thetas()
    phis = [-math.pi / 2 + 2 * math.pi * j / TUBE_V for j in range(TUBE_V)]
    pts = [[tube_point(th, ph) for ph in phis] for th in thetas]
    nu = len(thetas)
    uvs = []
    for i in range(nu + 1):
        u = (thetas[i] if i < nu else 2 * math.pi) / (2 * math.pi)
        uvs.append([(u, j / TUBE_V) for j in range(TUBE_V + 1)])
    b.grid(pts, closed_u=True, closed_v=True, uvs=uvs)
    return b.finish(col)


def pad_height(r):
    z = PAD_TOP + 0.012 * (1 - (r / PAD_R) ** 2)
    s = 1.0 - min(1.0, max(0.0, (r - 0.95) / (CUSHION_R + 0.02 - 0.95)))
    s = s * s * (3 - 2 * s)
    z += CUSHION_H * s
    if r < CUSHION_R and CUSHION_H > 0.0:
        z += 0.025 * (1 - (r / CUSHION_R) ** 2)
    return z


def build_pad(col):
    b = Builder("Pad", "LF_Pad")
    segs = 128
    radii = [0.03 + (PAD_R - 0.03) * (i / 44) for i in range(45)]
    # クッションの肩に輪を足す
    radii = sorted(set([round(r, 4) for r in radii] + [0.95, 1.0, 1.05, 1.1, 1.13, 1.15, 1.17]))
    rows = []
    uvs = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rows.append([Vector((math.cos(a) * r, math.sin(a) * r, pad_height(r))) for r in radii]
                    + [Vector((math.cos(a) * PAD_R, math.sin(a) * PAD_R, PAD_BOTTOM))])
    for i in range(segs + 1):
        a = 2 * math.pi * i / segs
        uvs.append([(0.5 + math.cos(a) * r / (2 * PAD_TEX_R), 0.5 + math.sin(a) * r / (2 * PAD_TEX_R)) for r in radii + [PAD_R]])
    verts = b.grid(rows, closed_u=True, closed_v=False, uvs=uvs)
    center = b.bm.verts.new(Vector((0, 0, pad_height(0))))
    for i in range(segs):
        i2 = (i + 1) % segs
        f = b.bm.faces.new((center, verts[i2][0], verts[i][0]))
        f.smooth = True
        for loop in f.loops:
            co = loop.vert.co
            loop[b.uv].uv = (0.5 + co.x / (2 * PAD_TEX_R), 0.5 + co.y / (2 * PAD_TEX_R))
    return b.finish(col)


def build_hull(col):
    b = Builder("Hull", "LF_Rubber")
    b.cylinder(Matrix.Translation((0, 0, HULL_Z)), HULL_R, HULL_R, 0.08, segs=96)
    # 底と管をつなぐスカート（水の中）
    b.cylinder(Matrix.Translation((0, 0, (HULL_Z + 0.2) / 2)), RING_R + 0.05, RING_R + 0.05, 0.36, segs=96, caps=False)
    return b.finish(col)


def build_strake(col):
    """こすれ止めの帯：外側の赤道の少し下。溝 3 本は厚さの波で付ける。"""
    b = Builder("RubStrake", "LF_Rubber")
    thetas = chamber_thetas()
    nv = 13
    phis = [math.radians(-16 + 16 * j / (nv - 1)) for j in range(nv)]
    pts = []
    for th in thetas:
        row = []
        for j, ph in enumerate(phis):
            rib = 0.018 - (0.006 if j in (3, 6, 9) else 0.0)
            if j in (0, nv - 1):
                rib = 0.002
            row.append(tube_point(th, ph, rib))
        pts.append(row)
    b.grid(pts, closed_u=True, closed_v=False)
    return b.finish(col)


def build_seams(col):
    """部屋の境目の溶着テープ（管をひと回り）。"""
    b = Builder("SeamTape", "LF_SeamTape")
    sides = 48
    for k in range(CHAMBERS):
        th0 = k / CHAMBERS * 2 * math.pi
        dth = 0.025 / RING_R
        rows = []
        for w in (-1.0, -0.6, 0.6, 1.0):
            th = th0 + w * dth
            off = 0.0015 if abs(w) == 1.0 else 0.0045
            rows.append([tube_point(th, -math.pi / 2 + 2 * math.pi * j / sides, off) for j in range(sides)])
        b.grid(rows, closed_u=False, closed_v=True)
    return b.finish(col)


def ring_points(count, offset_frac):
    return [((k + offset_frac) / count) * 2 * math.pi for k in range(count)]


def build_grab_line(col):
    """外側の当て布・D リング 24 か所と、間を垂れたロープ。"""
    patch = Builder("GrabPatches", "LF_Rubber", smooth=True)
    rings = Builder("GrabRings", "LF_Metal")
    rope = Builder("GrabRope", "LF_Rope")
    phi = math.radians(18)
    anchors = []
    for th in ring_points(24, 0.25):
        # 当て布：管の面に沿う 0.16 × 0.12 の板（ふちを薄く）
        rows = []
        for i in range(7):
            dth = (i / 6 - 0.5) * 0.16 / (RING_R + TUBE_R)
            rows.append([tube_point(th + dth, phi + (j / 4 - 0.5) * 0.12 / TUBE_R, 0.004 if 0 < i < 6 and 0 < j < 4 else 0.0005)
                         for j in range(5)])
        patch.grid(rows)
        # D リング：外へ立つ半円
        m = place(th, phi, 0.006)
        ring_m = m @ Matrix.Rotation(math.pi / 2, 4, "X")
        rings.torus(ring_m, 0.035, 0.0065, segs=14, sides=6, arc=math.pi)
        anchors.append(m @ Vector((0, 0, 0.04)))
    for i in range(len(anchors)):
        a, c = anchors[i], anchors[(i + 1) % len(anchors)]
        path = []
        for s in range(17):
            t = s / 16
            p = a.lerp(c, t)
            # 管の外へ少し逃がしてから垂らす
            outward = (p - Vector((0, 0, p.z))).normalized()
            p += outward * 0.05 * math.sin(math.pi * t)
            p.z -= 0.10 * math.sin(math.pi * t)
            path.append(p)
        rope.sweep(path, 0.011, sides=8, caps=False)
    return [patch.finish(col), rings.finish(col), rope.finish(col)]


def build_valves(col):
    rubber = Builder("ValveFlanges", "LF_Rubber")
    plastic = Builder("ValveCaps", "LF_Plastic")
    for th in (math.radians(15), math.radians(135), math.radians(255)):
        m = place(th, math.radians(62), 0.0)
        rubber.cylinder(m @ Matrix.Translation((0, 0, 0.006)), 0.058, 0.054, 0.014, segs=20)
        plastic.cylinder(m @ Matrix.Translation((0, 0, 0.026)), 0.036, 0.034, 0.026, segs=18)
        plastic.cylinder(m @ Matrix.Translation((0, 0, 0.044)), 0.030, 0.028, 0.012, segs=18)
        # ふたのひも（輪）
        plastic.torus(m @ Matrix.Translation((0.05, 0, 0.012)), 0.022, 0.004, segs=12, sides=5)
    return [rubber.finish(col), plastic.finish(col)]


def build_handles(col):
    """内側の上の取っ手（帯の輪）8 か所。"""
    web = Builder("Handles", "LF_Webbing", smooth=False)
    phi = math.radians(128)
    for th in ring_points(8, 0.12):
        rows = []
        for s in range(13):
            t = s / 12
            dth = (t - 0.5) * 0.30 / (RING_R - TUBE_R)
            lift = 0.055 * math.sin(math.pi * t) + 0.004
            c = tube_point(th + dth, phi, lift)
            n = tube_normal(th + dth, phi)
            side = e_r(th + dth) * -math.sin(phi) + Vector((0, 0, math.cos(phi)))
            rows.append([c - side * 0.02, c + side * 0.02, c + side * 0.02 + n * 0.005, c - side * 0.02 + n * 0.005])
        web.grid(rows, closed_u=False, closed_v=True)
    return web.finish(col)


def build_lamps(col):
    bases = Builder("LampBases", "LF_Rubber")
    domes = Builder("Lamps", "LF_LampAmber")
    guards = Builder("LampGuards", "LF_Metal")
    # 2026-10-18：8 つから 4 つに減らした（斜め 45° の 4 か所。+Y の中継カメラとははしごとも重ならない）。
    for th in ring_points(4, 0.5):
        m = place(th, math.radians(86), 0.0)
        bases.cylinder(m @ Matrix.Translation((0, 0, 0.016)), 0.058, 0.052, 0.032, segs=18)
        domes.sphere(m @ Matrix.Translation((0, 0, 0.032)), 0.042, segs=16, rings=8, hemisphere=True)
        for a in range(4):
            guards.torus(m @ Matrix.Translation((0, 0, 0.032)) @ Matrix.Rotation(a * math.pi / 4, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
                         0.050, 0.003, segs=12, sides=4, arc=math.pi)
        guards.torus(m @ Matrix.Translation((0, 0, 0.034)), 0.050, 0.0035, segs=20, sides=4)
    return [bases.finish(col), domes.finish(col), guards.finish(col)]


def build_ladders(col):
    rails = Builder("Ladders", "LF_Metal")
    markers = []
    for th in (0.0, math.pi):
        t = e_t(th)
        for side in (-0.22, 0.22):
            path = []
            for s in range(25):
                ph = math.radians(150 - (150 + 38) * s / 24)
                path.append(tube_point(th, ph, 0.055) + t * side)
            last = path[-1]
            for s in range(1, 8):
                path.append(last + Vector((0.0, 0.0, -0.1 * s)) + e_r(th) * 0.004 * s)
            rails.sweep(path, 0.017, sides=10)
        # 外側の踏み板（水の中に 2 段）と、管の上の手がかり
        foot = tube_point(th, math.radians(-38), 0.055)
        for z in (-0.28, -0.58):
            m = Matrix.Translation(Vector((foot.x, foot.y, foot.z + z)) + e_r(th) * 0.01) @ Matrix.Rotation(th, 4, "Z")
            rails.box(m, (0.06, 0.48, 0.022), bevel=0.006)
        markers.append(("MK_Ladder_%s" % ("PX" if th == 0 else "NX"), tube_point(th, math.radians(90), 0.08)))
    return [rails.finish(col)], markers


def build_ladder_pads(col):
    """はしごの手すりと管の間の当て物（手すりごとに 3 つ）。"""
    pads = Builder("LadderStandoffs", "LF_Rubber")
    for th in (0.0, math.pi):
        for side in (-0.22, 0.22):
            for ph in (130, 60, -10):
                m = place(th, math.radians(ph), 0.0)
                m = Matrix.Translation(e_t(th) * side) @ m
                pads.cylinder(m @ Matrix.Translation((0, 0, 0.028)), 0.026, 0.03, 0.056, segs=10)
    return pads.finish(col)


def build_tv_camera(col):
    """+Y の管の上の中継カメラ。中心へ向き、20° 下を見る。"""
    th = math.pi / 2
    base = place(th, math.radians(92), 0.0)
    body = Builder("TvCamera", "LF_CameraBody")
    metal = Builder("TvCameraMetal", "LF_Metal")
    glass = Builder("TvCameraLens", "LF_LensGlass")
    tally = Builder("Tally", "LF_TallyRed")
    # クランプ（管をはさむ U 字）
    clamp = []
    for s in range(15):
        ph = math.radians(60 + 64 * s / 14)
        clamp.append(tube_point(th, ph, 0.03))
    metal.sweep(clamp, 0.012, sides=8)
    top = tube_point(th, math.radians(92), 0.0)
    metal.box(Matrix.Translation(top + Vector((0, 0, 0.03))), (0.16, 0.16, 0.05), bevel=0.01)
    # 柱
    mast_top = top + Vector((0, 0, 0.62))
    metal.sweep([top + Vector((0, 0, 0.05)), mast_top], 0.022, sides=12)
    # 雲台
    body.cylinder(Matrix.Translation(mast_top + Vector((0, 0, 0.03))), 0.05, 0.045, 0.06, segs=18)
    yoke = Matrix.Translation(mast_top + Vector((0, 0, 0.11)))
    for side in (-0.085, 0.085):
        body.box(yoke @ Matrix.Translation((side, 0, 0)), (0.02, 0.06, 0.14), bevel=0.006)
    # 本体（中心＝-Y を向き、20° 下を見る）
    aim = Matrix.Translation(mast_top + Vector((0, 0, 0.13))) @ Matrix.Rotation(math.radians(-20), 4, "X")
    body.box(aim @ Matrix.Translation((0, 0.03, 0)), (0.15, 0.24, 0.13), bevel=0.018, segs=3)
    body.box(aim @ Matrix.Translation((0, 0.06, 0.085)), (0.05, 0.10, 0.03), bevel=0.008)   # 取っ手の台
    metal.sweep([aim @ Vector((0, 0.13, 0.08)), aim @ Vector((0, 0.13, 0.115)), aim @ Vector((0, -0.01, 0.115)), aim @ Vector((0, -0.01, 0.08))], 0.008, sides=6)
    lens = aim @ Matrix.Translation((0, -0.09, 0)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    body.cylinder(lens @ Matrix.Translation((0, 0, 0.0)), 0.048, 0.046, 0.08, segs=24)
    body.cylinder(lens @ Matrix.Translation((0, 0, 0.065)), 0.052, 0.06, 0.05, segs=24, caps=False)   # フード
    metal.torus(lens @ Matrix.Translation((0, 0, 0.035)), 0.049, 0.004, segs=24, sides=5)
    glass.cylinder(lens @ Matrix.Translation((0, 0, 0.041)), 0.040, 0.040, 0.002, segs=24)
    tally.sphere(aim @ Matrix.Translation((0.05, -0.05, 0.068)), 0.012, segs=10, rings=5)
    # ケーブル（本体の後ろから柱に沿って管へ）
    back = aim @ Vector((0, 0.15, -0.02))
    cable = [back, back + Vector((0, 0.04, -0.06)), mast_top + Vector((0.03, 0.03, -0.05)), mast_top + Vector((0.03, 0.03, -0.35)),
             top + Vector((0.035, 0.03, 0.08)), tube_point(th, math.radians(70), 0.012) + Vector((0.035, 0, 0)),
             tube_point(th, math.radians(30), 0.012) + Vector((0.05, 0, 0))]
    body.sweep(smooth_path(cable, 6), 0.008, sides=6)
    marker = ("MK_TvCamera", aim @ Vector((0, -0.13, 0)))
    return [body.finish(col), metal.finish(col), glass.finish(col), tally.finish(col)], [marker]


def smooth_path(points, sub):
    """カトマル・ロムの曲線で点を足す。"""
    out = []
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(sub):
            t = s / sub
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(points[-1])
    return out


def build_cleats(col):
    """係留の金具 2 つ（±Y から 30° ずらした管の上）と、巻いたロープ・海へ下りる係留ロープ。"""
    metal = Builder("Cleats", "LF_Metal")
    rope = Builder("MooringRope", "LF_Rope")
    for th in (math.radians(-60), math.radians(240)):
        m = place(th, math.radians(78), 0.0)
        metal.box(m @ Matrix.Translation((0, 0, 0.012)), (0.20, 0.07, 0.024), bevel=0.008)          # 台座
        for side in (-0.05, 0.05):
            metal.cylinder(m @ Matrix.Translation((side, 0, 0.045)), 0.012, 0.014, 0.05, segs=10)    # 脚
        metal.box(m @ Matrix.Translation((0, 0, 0.074)), (0.26, 0.032, 0.022), bevel=0.01, segs=3)  # 角
        # 金具の横に巻いたロープ（平たいらせん 5 周）
        coil_c = m @ Vector((0.0, 0.17, 0.02))
        n = m.to_3x3() @ Vector((0, 0, 1))
        u = (m.to_3x3() @ Vector((1, 0, 0))).normalized()
        v = n.cross(u).normalized()
        path = []
        for s in range(5 * 24 + 1):
            a = 2 * math.pi * s / 24
            r = 0.055 + 0.011 * s / 24
            path.append(coil_c + (u * math.cos(a) + v * math.sin(a)) * r + n * (0.012 + 0.002 * math.sin(a * 3)))
        rope.sweep(path, 0.0085, sides=6)
        # 金具から外へ、管をなでて海へ下りる係留ロープ
        start = m @ Vector((0.11, 0, 0.074))
        path = [start]
        for s in range(1, 13):
            ph = math.radians(78 - (78 + 60) * s / 12)
            path.append(tube_point(th + 0.02, ph, 0.02))
        bottom = path[-1]
        path.append(bottom + e_r(th) * 0.25 + Vector((0, 0, -0.5)))
        path.append(bottom + e_r(th) * 0.6 + Vector((0, 0, -1.4)))
        rope.sweep(smooth_path(path, 3), 0.011, sides=8)
    return [metal.finish(col), rope.finish(col)]


def build_lifebuoy(col):
    """中継カメラの柱に掛けた救命浮き輪（白とオレンジ 4 つずつ、ロープ付き）。"""
    th = math.pi / 2
    top = tube_point(th, math.radians(92), 0.0)
    center = top + Vector((-0.20, -0.02, 0.36))
    m = Matrix.Translation(center) @ Matrix.Rotation(math.radians(90), 4, "Y") @ Matrix.Rotation(math.radians(8), 4, "X")
    white = Builder("BuoyWhite", "LF_Pole")
    orange = Builder("BuoyOrange", "LF_Accent")
    rope = Builder("BuoyRope", "LF_Rope")
    for k in range(8):
        part = white if k % 2 == 0 else orange
        part.torus(m @ Matrix.Rotation(k * math.pi / 4, 4, "Z"), 0.17, 0.05, segs=6, sides=10, arc=math.pi / 4)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 8
        p0 = m @ Vector((math.cos(a) * 0.222, math.sin(a) * 0.222, 0))
        a1 = a + math.pi / 2
        p1 = m @ Vector((math.cos(a1) * 0.222, math.sin(a1) * 0.222, 0))
        mid = (p0 + p1) / 2 + (((p0 + p1) / 2) - center).normalized() * 0.05
        rope.sweep(smooth_path([p0, mid, p1], 4), 0.006, sides=5)
    # 掛けるフック
    rope.sweep([top + Vector((0.0, 0.0, 0.52)), top + Vector((-0.12, -0.02, 0.52)), center + Vector((0, 0, 0.2))], 0.006, sides=5)
    return [white.finish(col), orange.finish(col), rope.finish(col)]


def build_trim(col):
    piping = Builder("Piping", "LF_Piping")
    piping.torus(Matrix.Translation((0, 0, pad_height(3.10) + 0.012)), 3.10, 0.026, segs=160, sides=8)
    grommets = Builder("Grommets", "LF_Metal")
    for k in range(12):
        a = (k + 0.5) / 12 * 2 * math.pi
        r = 2.97
        grommets.torus(Matrix.Translation((math.cos(a) * r, math.sin(a) * r, pad_height(r) + 0.004)), 0.022, 0.006, segs=16, sides=6)
    return [piping.finish(col), grommets.finish(col)]


# ---------------------------------------------------------------- シーン

def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    for obj in list(col.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return col


def purge_meshes():
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def build_review(col):
    # 海面（確認用）
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    sea = bpy.context.active_object
    sea.name = "REF_Sea"
    for c in sea.users_collection:
        c.objects.unlink(sea)
    col.objects.link(sea)
    mat = principled("REF_SeaWater", (0.012, 0.07, 0.09), 0.16)
    sea.data.materials.clear()
    sea.data.materials.append(mat)
    # 大きさ比較のプレイヤー（高さ 2.05 の箱と頭）
    pmat = principled("REF_Player", (0.95, 0.55, 0.2), 0.6)
    for name, size, loc in (("REF_PlayerBody", (0.5, 0.3, 1.45), (1.5, -0.9, pad_height(1.6) + 0.725)),
                            ("REF_PlayerHead", (0.42, 0.42, 0.42), (1.5, -0.9, pad_height(1.6) + 1.45 + 0.21))):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        o = bpy.context.active_object
        o.name = name
        o.scale = size
        for c in o.users_collection:
            c.objects.unlink(o)
        col.objects.link(o)
        o.data.materials.append(pmat)


def build_lighting(col):
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    # Blender 5 の物理的な空（旧 Nishita）。太陽の円盤は光源（LGT_key）に任せて消す
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = False
    sky.sun_elevation = math.radians(38)
    sky.sun_rotation = math.radians(215)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.09
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    sun_data = bpy.data.lights.get("LGT_key") or bpy.data.lights.new("LGT_key", "SUN")
    sun_data.energy = 2.6
    sun_data.angle = math.radians(1.5)
    sun = bpy.data.objects.new("LGT_key", sun_data)
    col.objects.link(sun)
    sun.rotation_euler = (math.radians(52), 0.0, math.radians(215 - 180))


def add_camera(col, name, eye, target, lens):
    cam_data = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_start = 0.05
    cam = bpy.data.objects.new(name, cam_data)
    col.objects.link(cam)
    cam.location = eye
    direction = Vector(target) - Vector(eye)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam


def build_cameras(col):
    return {
        "lf_01_hero": add_camera(col, "CAM_Hero", (3.4, -9.4, 2.4), (0.0, 0.2, 0.45), 35),
        "lf_02_top": add_camera(col, "CAM_Top", (0.0, -0.001, 15.0), (0.0, 0.0, 0.0), 35),
        "lf_03_ladder": add_camera(col, "CAM_Ladder", (6.2, -2.6, 1.3), (3.9, 0.0, 0.25), 45),
        "lf_04_tvcam": add_camera(col, "CAM_TvCam", (1.2, 1.4, 1.75), (0.0, 3.0, 1.35), 40),
        "lf_05_side": add_camera(col, "CAM_Side", (-7.6, -6.2, 1.2), (-2.0, -1.0, 0.45), 40),
        "lf_06_deck": add_camera(col, "CAM_Deck", (2.6, -3.4, 2.4), (0.0, 0.4, 0.5), 28),
        "lf_07_cleat": add_camera(col, "CAM_Cleat", (2.6, -4.9, 1.35), (1.78, -3.08, 0.78), 40),
    }


def join_by_material(parts, export_col, root):
    """部品を材質ごとに 1 つのメッシュにまとめて書き出し用に置く（部品はそのまま残す）。"""
    keep_separate = {"Lamps", "Tally"}
    groups = {}
    for obj in parts:
        base = obj.name.removeprefix("PRT_")
        key = base if base in keep_separate else obj.data.materials[0].name
        groups.setdefault(key, []).append(obj)
    out = []
    for key, objs in groups.items():
        bm = bmesh.new()
        for o in objs:
            bm.from_mesh(o.data)
        name = key if key in keep_separate else key.replace("LF_", "")
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(objs[0].data.materials[0])
        obj = bpy.data.objects.new(name, me)
        export_col.objects.link(obj)
        obj.parent = root
        out.append(obj)
    return out


def render_previews(cameras):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "Standard"
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, cam in cameras.items():
        scene.camera = cam
        scene.render.filepath = str(PREVIEWS / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    scene.camera = cameras["lf_01_hero"]
    return paths


def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError("別の .blend が開いている：" + bpy.data.filepath)
    build_materials()
    parts_col = collection("LF_PARTS")
    export_col = collection("LF_EXPORT")
    review_col = collection("REF_Review")
    cam_col = collection("CAMERAS")
    light_col = collection("LIGHTING")
    purge_meshes()

    parts = [build_tube(parts_col), build_pad(parts_col), build_hull(parts_col), build_strake(parts_col), build_seams(parts_col)]
    parts += build_grab_line(parts_col)
    parts += build_valves(parts_col)
    parts.append(build_handles(parts_col))
    parts += build_lamps(parts_col)
    ladder_parts, ladder_markers = build_ladders(parts_col)
    parts += ladder_parts
    parts.append(build_ladder_pads(parts_col))
    cam_parts, cam_markers = build_tv_camera(parts_col)
    parts += cam_parts
    parts += build_trim(parts_col)
    parts += build_cleats(parts_col)
    parts += build_lifebuoy(parts_col)

    root = bpy.data.objects.new("LandingFloatRoot", None)
    export_col.objects.link(root)
    exported = join_by_material(parts, export_col, root)
    markers_root = bpy.data.objects.new("Markers", None)
    export_col.objects.link(markers_root)
    markers_root.parent = root
    markers = [("MK_LandCenter", Vector((0, 0, pad_height(0)))), ("MK_PadEdge", Vector((0, -3.0, pad_height(3.0))))]
    markers += ladder_markers + cam_markers
    for name, pos in markers:
        e = bpy.data.objects.new(name, None)
        export_col.objects.link(e)
        e.parent = markers_root
        e.location = pos
        e.empty_display_size = 0.15
    parts_col.hide_render = True
    parts_col.hide_viewport = True

    build_review(review_col)
    build_lighting(light_col)
    cameras = build_cameras(cam_col)

    # 報告
    tris = 0
    per = {}
    for o in exported:
        n = sum(len(p.vertices) - 2 for p in o.data.polygons)
        per[o.name] = n
        tris += n
    report = {
        "triangles": tris,
        "objects": per,
        "materials": sorted({o.data.materials[0].name for o in exported}),
        "dimensions": [round(v, 3) for v in next(o for o in exported if o.name == "Tube").dimensions],
        "markers": {name: [round(pos.x, 4), round(pos.z, 4), round(-pos.y, 4)] for name, pos in markers},
    }

    if DO_EXPORT:
        bpy.ops.object.select_all(action="DESELECT")
        for o in [root, markers_root] + exported + list(markers_root.children):
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_extras=False, export_cameras=False, export_lights=False)
        LAYOUT.write_text(json.dumps({
            "note": "着地台のマーカー。Godot の座標（x, y 上, z）。原点＝浮き台の中心 × 喫水線。build_landing_float.py が書く",
            "markers": report["markers"],
            "pad_top": round(pad_height(0.7), 4),
            "pad_radius": PAD_R,
            "outer_radius": RING_R + TUBE_R,
            "tube_top": TUBE_Z + TUBE_R,
            "waterline": 0.0,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    report["previews"] = render_previews(cameras) if DO_RENDER else []
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return report


if __name__ == "__main__":
    RESULT = main()
