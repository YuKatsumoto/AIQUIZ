"""観客船（spectator_boats）を作る。仕様：SCENE_PASSPORT.md（このフォルダ）と docs/sudden_death_v2/sky_gate.md 第9章。

ライブの Blender（Higgsfield の Blender 連携）で実行する。ヘッドレスで代替しない（AGENTS.md）。
    import runpy, sys
    sys.argv = ["blender", "--"]      # "--no-export" で書き出さない、"--no-render" で確認レンダーを出さない、"--no-save" で保存しない
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/sudden_death/sky_gate/spectator_boats/source/blender/build_spectator_boats.py", run_name="__main__")

座標：Blender の Z が上、メートル。原点＝船の中心 × 喫水線（水面 z = 0）。船首は +X、観客は −Y を向く。Godot では (x, z, -y)。
船は 2 種類：観覧船 SB_Launch（白い船体・ベンチ 2 列）とパーティー船 SB_Pontoon（浮き筒 2 本・柵・ベンチ 2 列）。
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
PREVIEWS = SOURCE / "previews"
GLB = ASSET / "spectator_boats.glb"
LAYOUT = ASSET / "spectator_boats_layout.json"
REPORT = SOURCE / "build_report.json"
BLEND = HERE / "spectator_boats.blend"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
DO_RENDER = "--no-render" not in ARGS
DO_SAVE = "--no-save" not in ARGS

# ---------------------------------------------------------------- 座る人の寸法（goal_stand_spectator.glb の骨から）
## 座面の高さ（床から）。もも 0.40・すね 0.43・足 0.10 で、座った人の足の裏がちょうど床に着く。
SEAT_H = 0.50
SEAT_DEPTH = 0.42
SEAT_PITCH = 0.85
## 腰は座面の中心より 0.06 後ろ（GrandstandCrowd.HIP_BEHIND_SEAT と同じ）。
HIP_BEHIND = 0.06

# ---------------------------------------------------------------- 観覧船（SB_Launch）の船体
X_STERN = -4.8
X_BOW = 4.5          # 船首の付け根（キールの高さ）。上は傾き RAKE で前へ出る
HB_STERN = 1.66
HB_MAX = 1.80
DECK_Z = 0.80
WALL = 0.07          # 舷の厚さ
STATIONS = 48
## 断面（上から）：(幅の割合, 高さ)。高さの "zs" は舷の上、"zk" はキール。帯ごとの材質は BANDS。
BANDS = ["SB_HullWhite", "SB_Stripe", "SB_HullWhite", "SB_HullWhite", "SB_Stripe", "SB_Bottom", "SB_Bottom", "SB_Bottom"]


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def launch_hb(u):
    if u < 0.42:
        return HB_STERN + (HB_MAX - HB_STERN) * smoothstep(0.0, 0.42, u)
    return HB_MAX * max(math.cos(math.pi / 2 * (u - 0.42) / 0.58), 0.0) ** 0.75


def launch_zs(u):
    return 1.0 + 0.32 * u ** 2.2


def launch_zk(u):
    return -0.42 + 0.30 * smoothstep(0.62, 1.0, u)


def launch_rake(u):
    return 0.55 * smoothstep(0.70, 1.0, u)


def launch_x(u, z):
    return X_STERN + (X_BOW - X_STERN) * u + launch_rake(u) * (z - launch_zk(u))


def launch_profile(u):
    zs, zk = launch_zs(u), launch_zk(u)
    return [(0.985, zs), (1.0, zs - 0.07), (1.0, zs - 0.20), (0.99, 0.48), (0.955, 0.12), (0.935, 0.04),
            (0.87, -0.06), (0.42, zk + 0.11 * (1.0 - u)), (0.0, zk)]


# ---------------------------------------------------------------- メッシュの道具

class Builder:
    """1 つのオブジェクトの bmesh。材質は名前の列（面ごとに material_index）。"""

    def __init__(self, name, material, smooth=True):
        self.name = name
        self.materials = [material] if isinstance(material, str) else list(material)
        self.smooth = smooth
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.flip_check = None

    def face(self, pts, mat=0, smooth=None, uvs=None, colors=None):
        verts = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f.smooth = self.smooth if smooth is None else smooth
        if uvs is not None:
            for loop, uv in zip(f.loops, uvs):
                loop[self.uv].uv = uv
        if colors is not None:
            layer = self.bm.loops.layers.color.get("Col") or self.bm.loops.layers.color.new("Col")
            for loop, c in zip(f.loops, colors):
                loop[layer] = c
        return f

    def grid(self, pts, closed_u=False, closed_v=False, mat=0):
        nu, nv = len(pts), len(pts[0])
        verts = [[self.bm.verts.new(p) for p in row] for row in pts]
        iu = nu if closed_u else nu - 1
        iv = nv if closed_v else nv - 1
        for i in range(iu):
            for j in range(iv):
                i2, j2 = (i + 1) % nu, (j + 1) % nv
                f = self.bm.faces.new((verts[i][j], verts[i2][j], verts[i2][j2], verts[i][j2]))
                f.smooth = self.smooth
                f.material_index = mat
        return verts

    def add_bm(self, other_bm, matrix=None, mat=0):
        if matrix is not None:
            bmesh.ops.transform(other_bm, matrix=matrix, verts=other_bm.verts)
        for f in other_bm.faces:
            f.material_index = mat
        me = bpy.data.meshes.new("_tmp")
        other_bm.to_mesh(me)
        other_bm.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def cylinder(self, matrix, r1, r2, depth, segs=16, caps=True, mat=0):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
        for f in bm.faces:
            f.smooth = self.smooth
        self.add_bm(bm, matrix, mat)

    def sphere(self, matrix, r, segs=16, rings=8, mat=0):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        for f in bm.faces:
            f.smooth = True
        self.add_bm(bm, matrix, mat)

    def box(self, center, size, bevel=0.0, segs=2, rot=None, mat=0):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES", profile=0.5)
        for f in bm.faces:
            f.smooth = bevel > 0
        m = (rot.to_4x4() if rot is not None else Matrix.Identity(4))
        m.translation = Vector(center)
        self.add_bm(bm, m, mat)

    def torus(self, matrix, major, minor, segs=24, sides=8, mat=0):
        pts = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
            d = Vector((math.cos(a), math.sin(a), 0))
            pts.append([matrix @ (c + d * math.cos(2 * math.pi * j / sides) * minor + Vector((0, 0, math.sin(2 * math.pi * j / sides) * minor)))
                        for j in range(sides)])
        self.grid(pts, closed_u=True, closed_v=True, mat=mat)

    def sweep(self, path, radius, sides=10, caps=True, mat=0, closed=False):
        """点の列に沿った丸い管（平行移動の枠）。radius は数か、点ごとの列。"""
        radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(path)
        n = len(path)
        tangents = []
        for i in range(n):
            if closed:
                a, b = path[(i - 1) % n], path[(i + 1) % n]
            else:
                a, b = path[max(i - 1, 0)], path[min(i + 1, n - 1)]
            tangents.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
        u = tangents[0].cross(ref).normalized()
        rows = []
        for i, p in enumerate(path):
            t = tangents[i]
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u).normalized()
            rows.append([p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radii[i] for k in range(sides)])
        verts = self.grid(rows, closed_u=closed, closed_v=True, mat=mat)
        if caps and not closed:
            for row in (verts[0], verts[-1]):
                f = self.bm.faces.new(row if row is verts[-1] else list(reversed(row)))
                f.smooth = False
                f.material_index = mat

    def finish(self, collection, recalc=True, weld=0.0):
        if weld > 0.0:
            bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=weld)
            bmesh.ops.dissolve_degenerate(self.bm, edges=self.bm.edges, dist=weld)
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        if self.flip_check is not None:
            for f in self.bm.faces:
                if self.flip_check(f):
                    f.normal_flip()
        # 角ばったところ（35° より急な折れ）は硬い線にする（ハードサーフェスの面がぼやけないように）
        self.bm.normal_update()
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(35):
                e.smooth = False
        me = bpy.data.meshes.new("PRT_" + self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.materials:
            me.materials.append(MAT[m])
        obj = bpy.data.objects.new("PRT_" + self.name, me)
        collection.objects.link(obj)
        return obj


def rot_between(a, b):
    return Vector(a).rotation_difference(Vector(b)).to_matrix()


def at(pos, rot=None):
    m = (rot.to_4x4() if rot is not None else Matrix.Identity(4))
    m.translation = Vector(pos)
    return m


def rod(b, p0, p1, r, segs=10, mat=0, caps=True):
    """p0 から p1 への丸い棒。"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    b.cylinder(at((p0 + p1) * 0.5, rot_between((0, 0, 1), d)), r, r, d.length, segs=segs, caps=caps, mat=mat)


def catenary(p0, p1, sag, n):
    p0, p1 = Vector(p0), Vector(p1)
    return [p0.lerp(p1, i / n) - Vector((0, 0, sag * 4.0 * (i / n) * (1.0 - i / n))) for i in range(n + 1)]


# ---------------------------------------------------------------- 材質

MAT = {}


def principled(name, color, rough=0.6, metal=0.0, emit=None, strength=0.0, double=False, vertex_color=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-300, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if vertex_color:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        vc.location = (-600, 0)
        nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.use_backface_culling = not double
    MAT[name] = mat
    return mat


def build_materials():
    principled("SB_HullWhite", (0.86, 0.87, 0.86), 0.32)
    principled("SB_Stripe", (0.035, 0.085, 0.20), 0.38)
    principled("SB_Bottom", (0.30, 0.07, 0.05), 0.75)
    principled("SB_Deck", (0.56, 0.57, 0.56), 0.85)
    principled("SB_Teak", (0.36, 0.20, 0.09), 0.62)
    principled("SB_Cushion", (0.80, 0.77, 0.70), 0.8)
    principled("SB_Steel", (0.80, 0.81, 0.82), 0.25, metal=1.0)
    principled("SB_Alu", (0.70, 0.71, 0.72), 0.36, metal=1.0)
    principled("SB_Trim", (0.035, 0.037, 0.04), 0.6)
    principled("SB_Glass", (0.02, 0.03, 0.035), 0.06)
    principled("SB_Canvas", (0.05, 0.11, 0.22), 0.85, double=True)
    principled("SB_Tube", (0.48, 0.30, 0.15), 0.8)
    principled("SB_TubeCap", (0.70, 0.08, 0.06), 0.7)
    principled("SB_Crate", (0.10, 0.20, 0.13), 0.7)
    principled("SB_Accent", (0.92, 0.38, 0.06), 0.45)
    principled("SB_Rope", (0.78, 0.76, 0.70), 0.9)
    principled("SB_Fender", (0.90, 0.90, 0.88), 0.5)
    principled("SB_LampRed", (1.0, 0.08, 0.05), 0.3, emit=(1.0, 0.06, 0.04), strength=2.5)
    principled("SB_LampGreen", (0.1, 1.0, 0.25), 0.3, emit=(0.08, 1.0, 0.2), strength=2.5)
    principled("SB_Flags", (1.0, 1.0, 1.0), 0.7, double=True, vertex_color=True)


FLAG_COLORS = [(0.95, 0.42, 0.06), (0.92, 0.92, 0.90), (0.10, 0.40, 0.85), (0.96, 0.78, 0.12), (0.85, 0.12, 0.10),
               (0.12, 0.66, 0.36)]


# ---------------------------------------------------------------- 観覧船（SB_Launch）

def launch_hull(col):
    """白い船体：断面をロフトした外板（色の帯ごとに材質）、船尾の板、舷の内側、舷の縁、甲板。"""
    b = Builder("Launch_Hull", BANDS[:1] + ["SB_Stripe", "SB_Bottom", "SB_Deck"])
    mat_of = {"SB_HullWhite": 0, "SB_Stripe": 1, "SB_Bottom": 2}
    rings = []
    for i in range(STATIONS + 1):
        u = i / STATIONS
        hb = launch_hb(u)
        prof = launch_profile(u)
        port = [Vector((launch_x(u, z), f * hb, z)) for f, z in prof]
        star = [Vector((launch_x(u, z), -f * hb, z)) for f, z in prof]
        rings.append(port + list(reversed(star[:-1])))
    n_prof = len(launch_profile(0.0))
    count = len(rings[0])

    def prof_index(r):
        return r if r < n_prof else 2 * (n_prof - 1) - r

    for i in range(STATIONS):
        for r in range(count - 1):
            band = min(prof_index(r), prof_index(r + 1))
            quad = [rings[i][r], rings[i + 1][r], rings[i + 1][r + 1], rings[i][r + 1]]
            b.face(quad, mat=mat_of[BANDS[band]])
    # 船尾の板（平ら。断面の順のまま −X を向く）
    b.face(rings[0], mat=0, smooth=False)
    # 舷の内側・舷の縁・甲板
    inner_top, inner_bot = [], []
    for i in range(STATIONS + 1):
        u = i / STATIONS
        hb_in = max(launch_hb(u) * 0.985 - WALL, 0.0)
        zs = launch_zs(u)
        x_top = launch_x(u, zs) + (WALL if i == 0 else 0.0)
        x_bot = launch_x(u, DECK_Z) + (WALL if i == 0 else 0.0)
        inner_top.append((x_top, hb_in, zs))
        inner_bot.append((x_bot, hb_in, DECK_Z))
    for side in (1.0, -1.0):
        for i in range(STATIONS):
            t0, t1 = inner_top[i], inner_top[i + 1]
            d0, d1 = inner_bot[i], inner_bot[i + 1]
            wall = [Vector((t0[0], side * t0[1], t0[2])), Vector((d0[0], side * d0[1], d0[2])),
                    Vector((d1[0], side * d1[1], d1[2])), Vector((t1[0], side * t1[1], t1[2]))]
            if wall[0].y != wall[3].y or wall[0].y != 0.0:
                b.face(wall if side > 0 else list(reversed(wall)), mat=0)
            o0, o1 = rings[i][0] if side > 0 else rings[i][-1], rings[i + 1][0] if side > 0 else rings[i + 1][-1]
            i0, i1 = Vector((t0[0], side * t0[1], t0[2])), Vector((t1[0], side * t1[1], t1[2]))
            b.face([o0, i0, i1, o1] if side > 0 else [o0, o1, i1, i0], mat=0, smooth=False)
    # 船尾の内側の壁と縁
    t0, d0 = inner_top[0], inner_bot[0]
    b.face([Vector((t0[0], -t0[1], t0[2])), Vector((d0[0], -d0[1], d0[2])), Vector((d0[0], d0[1], d0[2])), Vector((t0[0], t0[1], t0[2]))],
           mat=0, smooth=False)
    b.face([rings[0][-1], Vector((t0[0], -t0[1], t0[2])), Vector((t0[0], t0[1], t0[2])), rings[0][0]], mat=0, smooth=False)
    # 甲板（滑り止めのグレー）
    deck = [Vector((x, y, DECK_Z)) for x, y, _ in inner_bot if y > 0.004]
    deck += [Vector((inner_bot[-1][0], 0.0, DECK_Z))]
    deck += [Vector((x, -y, DECK_Z)) for x, y, _ in reversed(inner_bot) if y > 0.004]
    b.face(list(reversed(deck)), mat=3, smooth=False)
    # 面の向きは巻き方で決めてある（外板は外、甲板と縁は上、内側の壁は中）。開いた形は recalc が迷うので使わない
    obj = b.finish(col, recalc=False, weld=1e-4)
    return obj, rings


def launch_trim(col, rings):
    """こすれ止め（舷の縁の黒いゴム）：左舷の船尾から船首を回って右舷の船尾まで 1 本。"""
    b = Builder("Launch_RubRail", "SB_Trim")
    path = []
    for i in range(STATIONS + 1):
        u = i / STATIONS
        p = rings[i][1]
        path.append(Vector((p.x, p.y + 0.028 * (1.0 if launch_hb(u) > 0.02 else 0.0), p.z + 0.03)))
    star = []
    for i in range(STATIONS, -1, -1):
        u = i / STATIONS
        p = rings[i][-2]
        star.append(Vector((p.x, p.y - 0.028 * (1.0 if launch_hb(u) > 0.02 else 0.0), p.z + 0.03)))
    full = path + star[1:]
    clean = [full[0]]
    for p in full[1:]:
        if (p - clean[-1]).length > 0.02:
            clean.append(p)
    b.sweep(clean, 0.034, sides=8)
    return [b.finish(col)]


def inner_rail_line(u, side, inset=0.04):
    hb_in = max(launch_hb(u) * 0.985 - WALL - inset, 0.0)
    zs = launch_zs(u)
    return Vector((launch_x(u, zs), side * hb_in, zs))


def launch_railing(col):
    """手すり：支柱 0.9 m おき、上の手すり（縁の 0.62 上）と中の手すり（0.32 上）。船首で左右がつながり、船尾は横に渡す。"""
    steel = Builder("Launch_Rail", "SB_Steel")
    us = [i / 120 for i in range(4, 119)]
    for h in (0.62, 0.32):
        path = [inner_rail_line(u, 1.0) + Vector((0, 0, h)) for u in us]
        path += [inner_rail_line(0.995, 0.0) + Vector((0, 0, h))]
        path += [inner_rail_line(u, -1.0) + Vector((0, 0, h)) for u in reversed(us)]
        steel.sweep(path, 0.019 if h > 0.5 else 0.014, sides=8)
        # 船尾を横に渡す
        a = inner_rail_line(us[0], 1.0) + Vector((0, 0, h))
        c = inner_rail_line(us[0], -1.0) + Vector((0, 0, h))
        steel.sweep([a, c], 0.019 if h > 0.5 else 0.014, sides=8)
    # 支柱（弧の長さで 0.9 m おき）
    for side in (1.0, -1.0):
        dist = 0.0
        prev = inner_rail_line(us[0], side)
        posts = [prev]
        for u in us[1:]:
            p = inner_rail_line(u, side)
            dist += (p - prev).length
            prev = p
            if dist >= 0.9:
                posts.append(p)
                dist = 0.0
        for p in posts:
            rod(steel, p, p + Vector((0, 0, 0.62)), 0.017, segs=8)
            steel.cylinder(at(p + Vector((0, 0, 0.01))), 0.035, 0.03, 0.02, segs=10)
    return [steel.finish(col)]


def bench_row(teak, cushion, x0, x1, y_center, floor_z, facing=-1.0):
    """1 列のベンチ（観客は facing の向きを向く）。座面の上がちょうど floor_z + SEAT_H。"""
    top = floor_z + SEAT_H
    back_y = y_center - facing * (SEAT_DEPTH * 0.5)
    length = x1 - x0
    xc = (x0 + x1) * 0.5
    # 座面の板とクッション
    teak.box((xc, y_center, top - 0.085), (length, SEAT_DEPTH, 0.05), bevel=0.01)
    seats = []
    n = int(round(length / SEAT_PITCH))
    for k in range(n):
        x = x0 + SEAT_PITCH * (k + 0.5)
        cushion.box((x, y_center, top - 0.03), (SEAT_PITCH - 0.06, SEAT_DEPTH - 0.04, 0.06), bevel=0.025, segs=3)
        seats.append((x, y_center, top))
    # 背もたれ（板 3 枚、少し後ろへ傾く）
    tilt = Matrix.Rotation(math.radians(10.0 * facing), 3, "X")
    for j, h in enumerate((0.12, 0.25, 0.38)):
        off = tilt @ Vector((0, 0, h))
        teak.box((xc, back_y + 0.02 * -facing + off.y, top + off.z), (length, 0.035, 0.09), bevel=0.008, rot=tilt)
    # 脚（台座）
    legs = max(2, int(length / 1.7) + 1)
    for k in range(legs):
        x = x0 + 0.12 + (length - 0.24) * k / (legs - 1)
        teak.box((x, y_center, (floor_z + top - 0.11) * 0.5), (0.07, SEAT_DEPTH - 0.08, top - 0.11 - floor_z), bevel=0.008)
        rod(teak, (x, back_y - 0.01 * facing, top - 0.06), (x, back_y + 0.06 * -facing, top + 0.44), 0.02, segs=6)
    return seats


def launch_seating(col):
    teak = Builder("Launch_Teak", "SB_Teak")
    cushion = Builder("Launch_Cushion", "SB_Cushion")
    deck = Builder("Launch_Platform", "SB_Deck", smooth=False)
    # 後ろの列の台（甲板から 0.38 上がる）と前のふちのチーク
    deck.box((-0.85, 0.25, DECK_Z + 0.19), (5.3, 1.46, 0.38))
    teak.box((-0.85, -0.47, DECK_Z + 0.37), (5.32, 0.06, 0.03), bevel=0.008)
    x0, x1 = -3.4, 1.7
    front = bench_row(teak, cushion, x0, x1, -0.80, DECK_Z)
    back = bench_row(teak, cushion, x0, x1, 0.25, DECK_Z + 0.38)
    return [teak.finish(col), cushion.finish(col), deck.finish(col)], front, back


def launch_helm(col):
    """船尾の操舵台：白い箱・黒い計器盤・風防・ハンドル、T トップの屋根と柱、アンテナ、旗の柱。"""
    white = Builder("Launch_Console", "SB_HullWhite")
    trim = Builder("Launch_Dash", "SB_Trim")
    glass = Builder("Launch_Glass", "SB_Glass", smooth=False)
    steel = Builder("Launch_HelmSteel", "SB_Steel")
    canvas = Builder("Launch_Canvas", "SB_Canvas")
    cx, cy = -4.1, 0.75
    white.box((cx, cy, DECK_Z + 0.47), (0.62, 0.92, 0.94), bevel=0.04, segs=3)
    # 計器盤（船尾の側の傾いた面）
    tilt = Matrix.Rotation(math.radians(-35), 3, "Y")
    trim.box((cx - 0.28, cy, DECK_Z + 0.88), (0.06, 0.8, 0.34), bevel=0.01, rot=tilt)
    # ハンドル
    wheel_rot = Matrix.Rotation(math.radians(90), 3, "Y") @ Matrix.Rotation(math.radians(30), 3, "Y")
    trim.torus(at((cx - 0.36, cy, DECK_Z + 0.98), wheel_rot), 0.17, 0.014, segs=24, sides=6)
    rod(trim, (cx - 0.33, cy, DECK_Z + 0.95), (cx - 0.25, cy, DECK_Z + 0.90), 0.02)
    # 風防（前の上、傾く）
    g = Matrix.Rotation(math.radians(28), 3, "Y")
    glass.box((cx + 0.33, cy, DECK_Z + 1.12), (0.02, 0.88, 0.36), rot=g)
    steel.sweep([Vector((cx + 0.26, cy - 0.45, DECK_Z + 0.95)), Vector((cx + 0.43, cy - 0.45, DECK_Z + 1.28)),
                 Vector((cx + 0.43, cy + 0.45, DECK_Z + 1.28)), Vector((cx + 0.26, cy + 0.45, DECK_Z + 0.95))], 0.012, sides=6)
    # T トップ：柱 4 本と紺の屋根
    roof_z = 2.95
    for px in (cx - 0.55, cx + 0.42):
        for py in (cy - 0.55, cy + 0.55):
            rod(steel, (px, py, DECK_Z), (px, py, roof_z - 0.04), 0.024)
    steel.sweep([Vector((cx - 0.6, cy - 0.6, roof_z - 0.05)), Vector((cx + 0.47, cy - 0.6, roof_z - 0.05)),
                 Vector((cx + 0.47, cy + 0.6, roof_z - 0.05)), Vector((cx - 0.6, cy + 0.6, roof_z - 0.05))], 0.02, sides=6, closed=True)
    canvas.box((cx - 0.06, cy, roof_z), (1.22, 1.3, 0.06), bevel=0.03, segs=3)
    # アンテナと旗の綱の柱
    rod(steel, (cx - 0.5, cy + 0.5, roof_z + 0.03), (cx - 0.5, cy + 0.5, roof_z + 1.2), 0.008, segs=6)
    pole_top = Vector((cx - 0.45, cy - 0.5, roof_z + 1.0))
    rod(steel, (cx - 0.45, cy - 0.5, roof_z + 0.03), pole_top, 0.02, segs=8)
    return [white.finish(col), trim.finish(col), glass.finish(col), steel.finish(col), canvas.finish(col)], pole_top


def mortar_crate(col, prefix, center, floor_z, rows=2, cols=3, yaw=0.0):
    """打ち上げ筒の箱（濃い緑の木箱に紙の筒が 2×3 本）。返り値は筒の口（Blender の座標）。"""
    crate = Builder(prefix + "_Crate", "SB_Crate")
    tube = Builder(prefix + "_Tubes", "SB_Tube")
    cap = Builder(prefix + "_TubeCaps", "SB_TubeCap")
    cx, cy = center
    w, d, h = 0.36 * cols + 0.08, 0.36 * rows + 0.08, 0.40
    r = Matrix.Rotation(yaw, 3, "Z")
    crate.box((cx, cy, floor_z + h * 0.5), (w, d, h), bevel=0.015, rot=r)
    # 縁の帯（木箱の補強）
    for z in (floor_z + 0.06, floor_z + h - 0.06):
        crate.box((cx, cy, z), (w + 0.02, d + 0.02, 0.05), bevel=0.006, rot=r)
    mouths = []
    for i in range(rows):
        for j in range(cols):
            local = Vector(((j - (cols - 1) * 0.5) * 0.36, (i - (rows - 1) * 0.5) * 0.36, 0.0))
            base = Vector((cx, cy, floor_z + 0.05)) + r @ local
            # 外へ少し開く（花火が重ならないように）
            lean = r @ Vector((local.x * 0.25, local.y * 0.35, 1.0))
            top = base + lean.normalized() * 0.58
            rod(tube, base, top, 0.075, segs=14)
            cap.cylinder(at(top + lean.normalized() * 0.005, rot_between((0, 0, 1), lean)), 0.077, 0.077, 0.012, segs=14)
            mouths.append(top)
    return [crate.finish(col), tube.finish(col), cap.finish(col)], mouths


def bunting(col, prefix, p0, p1, sag, count, phase=0):
    """旗の綱：p0 から p1 へ垂れた綱と、三角の小旗（頂点の色。UV の v が付け根 0 → 先 1 で、Godot ではためかせる）。"""
    rope = Builder(prefix + "_FlagLine", "SB_Rope")
    flags = Builder(prefix + "_Flags", "SB_Flags", smooth=False)
    pts = catenary(p0, p1, sag, 40)
    rope.sweep(pts, 0.006, sides=5)
    line = catenary(p0, p1, sag, count * 2 + 1)
    for k in range(count):
        a = line[2 * k + 1]
        c = line[2 * k + 2]
        mid = (a + c) * 0.5
        tip = mid + Vector((0, 0, -0.40))
        color = FLAG_COLORS[(k + phase) % len(FLAG_COLORS)]
        cols = [(*color, 1.0)] * 3
        flags.face([a, c, tip], uvs=[(0.0, 0.0), (1.0, 0.0), (0.5, 1.0)], colors=cols)
    return [rope.finish(col), flags.finish(col, recalc=False)]


def launch_details(col, pole_top):
    steel = Builder("Launch_DeckSteel", "SB_Steel")
    fender = Builder("Launch_Fenders", "SB_Fender")
    rope = Builder("Launch_Ropes", "SB_Rope")
    accent = Builder("Launch_LifeRing", "SB_Accent")
    white = Builder("Launch_LifeRingTape", "SB_HullWhite")
    red = Builder("Launch_LampRed", "SB_LampRed", smooth=False)
    green = Builder("Launch_LampGreen", "SB_LampGreen", smooth=False)
    trim = Builder("Launch_Cleats", "SB_Trim")
    # 船首のマスト（旗の綱の前の端）
    mast_base = Vector((3.95, 0.0, DECK_Z))
    mast_top = Vector((3.95, 0.0, 4.5))
    rod(steel, mast_base, mast_top, 0.04, segs=12)
    steel.cylinder(at(mast_base + Vector((0, 0, 0.03))), 0.09, 0.07, 0.06, segs=12)
    steel.sphere(at(mast_top), 0.055, segs=10, rings=6)
    # フェンダー（観客の側の舷に 3 つ）
    for x in (-2.5, -0.2, 2.0):
        u = (x - X_STERN) / (X_BOW - X_STERN)
        hb = launch_hb(u)
        top = inner_rail_line(u, -1.0) + Vector((0, 0, 0.32))
        c = Vector((x, -(hb + 0.13), 0.52))
        fender.cylinder(at(c), 0.11, 0.11, 0.42, segs=14)
        fender.sphere(at(c + Vector((0, 0, 0.21))), 0.11, segs=14, rings=7)
        fender.sphere(at(c + Vector((0, 0, -0.21))), 0.11, segs=14, rings=7)
        rope.sweep([c + Vector((0, 0, 0.3)), Vector((x, -(hb + 0.05), launch_zs(u) + 0.05)), top], 0.008, sides=5, caps=False)
    # 救命浮き輪（船尾の手すり、外向き）
    ring_c = Vector((X_STERN - 0.02, 1.0, 1.35))
    ring_rot = Matrix.Rotation(math.radians(90), 3, "Y")
    accent.torus(at(ring_c, ring_rot), 0.26, 0.065, segs=28, sides=10)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        p = ring_c + ring_rot @ Vector((math.cos(a) * 0.26, math.sin(a) * 0.26, 0.0))
        white.box(p, (0.15, 0.14, 0.14), bevel=0.02, rot=ring_rot @ Matrix.Rotation(a, 3, "Z"))
    # 航海灯（左舷が赤・右舷が緑）と船尾の白
    u = 0.86
    for side, b in ((1.0, red), (-1.0, green)):
        p = Vector((launch_x(u, launch_zs(u)), side * launch_hb(u) * 0.99, launch_zs(u) + 0.06))
        b.box(p, (0.14, 0.05, 0.07))
    # クリート（舷の縁）
    for x, side in ((-4.4, 1.0), (-4.4, -1.0), (3.6, 1.0), (3.6, -1.0)):
        u = (x - X_STERN) / (X_BOW - X_STERN)
        p = Vector((x, side * (launch_hb(u) * 0.985 - WALL * 0.5), launch_zs(u) + 0.02))
        trim.box(p, (0.22, 0.04, 0.04), bevel=0.012)
        trim.box(p - Vector((0, 0, 0.01)), (0.06, 0.05, 0.05), bevel=0.01)
    parts = [steel.finish(col), fender.finish(col), rope.finish(col), accent.finish(col), white.finish(col), red.finish(col),
             green.finish(col), trim.finish(col)]
    return parts, mast_top


# ---------------------------------------------------------------- パーティー船（SB_Pontoon）

P_DECK_TOP = 0.56
P_HALF_W = 1.30
P_HALF_L = 3.70


def pontoon_hull(col):
    alu = Builder("Pontoon_Tubes", "SB_Alu")
    deck = Builder("Pontoon_Deck", "SB_Deck", smooth=False)
    trim = Builder("Pontoon_Trim", "SB_Trim")
    for y in (-0.95, 0.95):
        path, radii = [], []
        for k in range(14):
            x = -3.6 + 6.7 * k / 13
            path.append(Vector((x, y, 0.06)))
            radii.append(0.32)
        for k in range(1, 9):
            s = k / 8
            path.append(Vector((3.1 + 0.68 * s, y, 0.06 + 0.26 * s * s)))
            radii.append(0.32 * (1.0 - s) ** 0.8 + 0.05 * s)
        alu.sweep(path, radii, sides=20)
        # 浮き筒と甲板をつなぐ金具
        for x in (-3.0, -1.5, 0.0, 1.5, 2.9):
            alu.box((x, y, 0.40), (0.12, 0.36, 0.06), bevel=0.01)
    deck.box((0.0, 0.0, P_DECK_TOP - 0.07), (P_HALF_L * 2, P_HALF_W * 2, 0.14))
    ring = [Vector((-P_HALF_L - 0.03, -P_HALF_W - 0.03, P_DECK_TOP - 0.07)), Vector((P_HALF_L + 0.03, -P_HALF_W - 0.03, P_DECK_TOP - 0.07)),
            Vector((P_HALF_L + 0.03, P_HALF_W + 0.03, P_DECK_TOP - 0.07)), Vector((-P_HALF_L - 0.03, P_HALF_W + 0.03, P_DECK_TOP - 0.07))]
    trim.sweep(ring, 0.04, sides=8, closed=True)
    return [alu.finish(col), deck.finish(col), trim.finish(col)]


def pontoon_fence(col):
    """柵：船首・船尾・後ろ（+Y）は白い板に色帯、観客の前（−Y）は手すりだけ。上の手すりは全周。"""
    steel = Builder("Pontoon_Rail", "SB_Steel")
    panel = Builder("Pontoon_Panels", "SB_HullWhite", smooth=False)
    stripe = Builder("Pontoon_Stripe", "SB_Stripe", smooth=False)
    inset = 0.06
    xl, xr = -P_HALF_L + inset, P_HALF_L - inset
    yf, yb = -P_HALF_W + inset, P_HALF_W - inset
    top_z = P_DECK_TOP + 0.80
    corners = [Vector((xl, yf, 0)), Vector((xr, yf, 0)), Vector((xr, yb, 0)), Vector((xl, yb, 0))]
    steel.sweep([c + Vector((0, 0, top_z)) for c in corners], 0.024, sides=8, closed=True)
    # 観客の前（−Y）の中の手すり
    steel.sweep([Vector((xl, yf, P_DECK_TOP + 0.42)), Vector((xr, yf, P_DECK_TOP + 0.42))], 0.016, sides=8)
    # 支柱
    def posts(a, b, n):
        return [a.lerp(b, k / n) for k in range(n + 1)]
    sides = [(corners[0], corners[1], 6, False), (corners[1], corners[2], 2, True), (corners[2], corners[3], 6, True),
             (corners[3], corners[0], 2, True)]
    for a, b, n, solid in sides:
        pts = posts(a, b, n)
        for p in pts:
            rod(steel, p + Vector((0, 0, P_DECK_TOP)), p + Vector((0, 0, top_z - 0.02)), 0.02, segs=8)
        if not solid:
            continue
        d = (b - a).normalized()
        normal = Vector((d.y, -d.x, 0))
        for k in range(n):
            p0, p1 = pts[k], pts[k + 1]
            mid = (p0 + p1) * 0.5
            length = (p1 - p0).length - 0.05
            rot = Matrix.Rotation(math.atan2(d.y, d.x), 3, "Z")
            panel.box((mid.x, mid.y, P_DECK_TOP + 0.43), (length, 0.025, 0.66), rot=rot)
            stripe.box((mid.x + normal.x * 0.018, mid.y + normal.y * 0.018, P_DECK_TOP + 0.50), (length, 0.012, 0.13), rot=rot)
    return [steel.finish(col), panel.finish(col), stripe.finish(col)]


def pontoon_seating(col):
    teak = Builder("Pontoon_Teak", "SB_Teak")
    cushion = Builder("Pontoon_Cushion", "SB_Cushion")
    deck = Builder("Pontoon_Platform", "SB_Deck", smooth=False)
    deck.box((0.0, 0.55, P_DECK_TOP + 0.175), (5.3, 1.34, 0.35))
    teak.box((0.0, -0.13, P_DECK_TOP + 0.34), (5.32, 0.06, 0.03), bevel=0.008)
    front = bench_row(teak, cushion, -2.55, 2.55, -0.45, P_DECK_TOP)
    back = bench_row(teak, cushion, -2.55, 2.55, 0.62, P_DECK_TOP + 0.35)
    return [teak.finish(col), cushion.finish(col), deck.finish(col)], front, back


def pontoon_details(col):
    white = Builder("Pontoon_Console", "SB_HullWhite")
    trim = Builder("Pontoon_Dash", "SB_Trim")
    glass = Builder("Pontoon_Glass", "SB_Glass", smooth=False)
    steel = Builder("Pontoon_Poles", "SB_Steel")
    cx, cy = 3.25, 0.72
    white.box((cx, cy, P_DECK_TOP + 0.45), (0.5, 0.7, 0.9), bevel=0.04, segs=3)
    tilt = Matrix.Rotation(math.radians(-35), 3, "Y")
    trim.box((cx - 0.22, cy, P_DECK_TOP + 0.84), (0.05, 0.6, 0.3), bevel=0.01, rot=tilt)
    wheel_rot = Matrix.Rotation(math.radians(120), 3, "Y")
    trim.torus(at((cx - 0.31, cy, P_DECK_TOP + 0.95), wheel_rot), 0.15, 0.013, segs=22, sides=6)
    glass.box((cx + 0.22, cy, P_DECK_TOP + 1.06), (0.02, 0.66, 0.3), rot=Matrix.Rotation(math.radians(25), 3, "Y"))
    # 旗の綱の柱（船首と船尾の後ろの角）
    tops = []
    for x in (P_HALF_L - 0.12, -P_HALF_L + 0.12):
        base = Vector((x, P_HALF_W - 0.12, P_DECK_TOP))
        top = Vector((x, P_HALF_W - 0.12, 3.9))
        rod(steel, base, top, 0.03, segs=10)
        steel.sphere(at(top), 0.045, segs=10, rings=6)
        tops.append(top)
    return [white.finish(col), trim.finish(col), glass.finish(col), steel.finish(col)], tops


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


def join_by_material(parts, export_col, root, prefix):
    """部品を材質ごとに 1 つのメッシュにまとめる（部品はそのまま残す）。材質が 2 つ以上の部品（船体）と旗は別のまま。"""
    groups = {}
    for obj in parts:
        mats = [m.name for m in obj.data.materials]
        if len(mats) > 1:
            key = "Hull"
        elif mats[0] == "SB_Flags":
            key = "Flags"
        else:
            key = mats[0].replace("SB_", "")
        groups.setdefault(key, []).append(obj)
    out = []
    for key, objs in groups.items():
        bm = bmesh.new()
        mats = []
        for o in objs:
            remap = []
            for m in o.data.materials:
                if m not in mats:
                    mats.append(m)
                remap.append(mats.index(m))
            tmp = bmesh.new()
            tmp.from_mesh(o.data)
            for f in tmp.faces:
                f.material_index = remap[f.material_index]
            me_tmp = bpy.data.meshes.new("_join")
            tmp.to_mesh(me_tmp)
            tmp.free()
            bm.from_mesh(me_tmp)
            bpy.data.meshes.remove(me_tmp)
        me = bpy.data.meshes.new(prefix + "_" + key)
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(m)
        obj = bpy.data.objects.new(prefix + "_" + key, me)
        export_col.objects.link(obj)
        obj.parent = root
        out.append(obj)
    return out


def godot(p):
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


def seat_records(rows):
    out = []
    for row_index, seats in enumerate(rows, start=1):
        for x, y, z in seats:
            out.append(godot((x, y, z)) + [row_index])
    return out


def build_review(col, boats):
    """確認用の海面と、座席に座った人の箱（胴・頭・もも・すね）。"""
    bpy.ops.mesh.primitive_plane_add(size=160, location=(0, 0, 0))
    sea = bpy.context.active_object
    sea.name = "REF_Sea"
    for c in sea.users_collection:
        c.objects.unlink(sea)
    col.objects.link(sea)
    sea.data.materials.clear()
    sea.data.materials.append(principled("REF_SeaWater", (0.012, 0.07, 0.09), 0.16))
    people = {}
    for name, info in boats.items():
        b = Builder("REF_People_" + name, "REF_Person")
        for x, y, z in info["seats_blender"]:
            hip = Vector((x, y + HIP_BEHIND, z + 0.09))
            b.box(hip + Vector((0, 0, 0.30)), (0.40, 0.24, 0.62), bevel=0.02)
            b.box(hip + Vector((0, -0.02, 0.86)), (0.32, 0.30, 0.34), bevel=0.03)
            b.box(hip + Vector((0, -0.20, -0.04)), (0.36, 0.42, 0.15), bevel=0.02)
            b.box(hip + Vector((0, -0.40, -0.28)), (0.32, 0.12, 0.42), bevel=0.02)
            b.box(hip + Vector((0, -0.46, -0.55)), (0.30, 0.24, 0.07), bevel=0.01)
        people[name] = b.finish(col)
    return sea, people


def build_lighting(col):
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = False
    sky.sun_elevation = math.radians(40)
    sky.sun_rotation = math.radians(250)
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
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(-25))


def add_camera(col, name, eye, target, lens):
    cam_data = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_start = 0.05
    cam_data.clip_end = 500.0
    cam = bpy.data.objects.new(name, cam_data)
    col.objects.link(cam)
    cam.location = eye
    direction = Vector(target) - Vector(eye)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam


def build_cameras(col):
    return {
        "sb_01_launch_hero": (add_camera(col, "CAM_Hero", (7.0, -11.5, 3.2), (-0.4, 0.0, 1.5), 32), "SB_Launch"),
        "sb_02_launch_far": (add_camera(col, "CAM_Far", (9.0, -34.0, 3.0), (0.0, 0.0, 1.8), 50), "SB_Launch"),
        "sb_03_launch_top": (add_camera(col, "CAM_Top", (0.0, -0.001, 21.0), (0.0, 0.0, 0.0), 35), "SB_Launch"),
        "sb_04_launch_detail": (add_camera(col, "CAM_Detail", (-1.0, -5.0, 3.6), (2.6, 0.0, 1.3), 30), "SB_Launch"),
        "sb_05_launch_stern": (add_camera(col, "CAM_Stern", (-11.0, 5.5, 3.4), (-2.0, 0.0, 1.6), 32), "SB_Launch"),
        "sb_06_pontoon_hero": (add_camera(col, "CAM_Pontoon", (6.5, -10.0, 3.0), (0.0, 0.0, 1.3), 32), "SB_Pontoon"),
        "sb_07_pontoon_back": (add_camera(col, "CAM_PontoonBack", (-7.0, 8.5, 3.6), (0.0, 0.0, 1.2), 32), "SB_Pontoon"),
    }


def render_previews(cameras, roots, people, show_people):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "Standard"
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, (cam, boat) in cameras.items():
        for key, root in roots.items():
            hide = key != boat
            for o in [root] + list(root.children_recursive):
                o.hide_render = hide
            people[key].hide_render = hide or not show_people
        scene.camera = cam
        scene.render.filepath = str(PREVIEWS / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    for key, root in roots.items():
        for o in [root] + list(root.children_recursive):
            o.hide_render = False
        people[key].hide_render = True
    scene.camera = cameras["sb_01_launch_hero"][0]
    return paths


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            for i in range(3):
                lo[i] = min(lo[i], v.co[i])
                hi[i] = max(hi[i], v.co[i])
    return lo, hi


def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != BLEND.resolve():
        raise RuntimeError("別の .blend が開いている：" + bpy.data.filepath)
    # 起動時の箱・光・カメラは隠すだけ（消さない）
    for name in ("Cube", "Light", "Camera"):
        o = bpy.data.objects.get(name)
        if o is not None:
            o.hide_render = True
            o.hide_viewport = True
    build_materials()
    principled("REF_Person", (0.95, 0.55, 0.2), 0.6)
    launch_col = collection("SB_PARTS_Launch")
    pontoon_col = collection("SB_PARTS_Pontoon")
    export_col = collection("SB_EXPORT")
    review_col = collection("REF_Review")
    cam_col = collection("CAMERAS")
    light_col = collection("LIGHTING")
    purge_meshes()

    # 観覧船
    hull, rings = launch_hull(launch_col)
    parts = [hull] + launch_trim(launch_col, rings) + launch_railing(launch_col)
    seat_parts, l_front, l_back = launch_seating(launch_col)
    parts += seat_parts
    helm_parts, pole_top = launch_helm(launch_col)
    parts += helm_parts
    detail_parts, mast_top = launch_details(launch_col, pole_top)
    parts += detail_parts
    crate_parts, l_mouths = mortar_crate(launch_col, "Launch", (2.95, 0.0), DECK_Z)
    parts += crate_parts
    parts += bunting(launch_col, "Launch", mast_top - Vector((0, 0, 0.08)), pole_top, 0.32, 18)
    parts += bunting(launch_col, "LaunchFore", mast_top - Vector((0, 0, 0.08)),
                     Vector((launch_x(0.995, launch_zs(0.995)), 0.0, launch_zs(0.995) + 0.05)), 0.10, 4, phase=3)
    launch_root = bpy.data.objects.new("SB_Launch", None)
    export_col.objects.link(launch_root)
    launch_exported = join_by_material(parts, export_col, launch_root, "Launch")

    # パーティー船
    p_parts = pontoon_hull(pontoon_col) + pontoon_fence(pontoon_col)
    p_seat_parts, p_front, p_back = pontoon_seating(pontoon_col)
    p_parts += p_seat_parts
    p_detail_parts, p_tops = pontoon_details(pontoon_col)
    p_parts += p_detail_parts
    p_crate_parts, p_mouths = mortar_crate(pontoon_col, "Pontoon", (-3.15, -0.15), P_DECK_TOP, rows=2, cols=2)
    p_parts += p_crate_parts
    p_parts += bunting(pontoon_col, "Pontoon", p_tops[0] - Vector((0, 0, 0.06)), p_tops[1] - Vector((0, 0, 0.06)), 0.30, 16, phase=1)
    pontoon_root = bpy.data.objects.new("SB_Pontoon", None)
    export_col.objects.link(pontoon_root)
    pontoon_exported = join_by_material(p_parts, export_col, pontoon_root, "Pontoon")

    for col in (launch_col, pontoon_col):
        col.hide_render = True
        col.hide_viewport = True

    boats = {
        "SB_Launch": {"seats_blender": l_front + l_back, "rows": [l_front, l_back], "mouths": l_mouths, "objects": launch_exported,
                      "deck": DECK_Z},
        "SB_Pontoon": {"seats_blender": p_front + p_back, "rows": [p_front, p_back], "mouths": p_mouths, "objects": pontoon_exported,
                       "deck": P_DECK_TOP},
    }
    sea, people = build_review(review_col, boats)
    build_lighting(light_col)
    cameras = build_cameras(cam_col)

    report = {"boats": {}}
    layout = {"note": "観客船の座席（座面の上の中心）と打ち上げ筒の口。Godot の座標（x, y 上, z）。原点＝船の中心 × 喫水線。"
                      "観客は +Z を向く（座る人の腰は座面の中心より 0.06 後ろ）。build_spectator_boats.py が書く",
              "seat_height": SEAT_H, "hip_behind": HIP_BEHIND, "boats": {}}
    for name, info in boats.items():
        objs = info["objects"]
        tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs}
        lo, hi = bounds(objs)
        report["boats"][name] = {"triangles": sum(tris.values()), "objects": tris,
                                 "materials": sorted({m.name for o in objs for m in o.data.materials}),
                                 "size": [round(hi[i] - lo[i], 3) for i in range(3)], "seats": len(info["seats_blender"])}
        layout["boats"][name] = {
            "seats": seat_records(info["rows"]),
            "launch": [godot(p) for p in info["mouths"]],
            "deck": info["deck"],
            "aabb": [godot((lo.x, hi.y, lo.z)), godot((hi.x, lo.y, hi.z))],
        }

    if DO_EXPORT:
        bpy.ops.object.select_all(action="DESELECT")
        for o in [launch_root, pontoon_root] + launch_exported + pontoon_exported:
            o.hide_viewport = False
            o.select_set(True)
        bpy.context.view_layer.objects.active = launch_root
        kwargs = dict(filepath=str(GLB), export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                      export_extras=False, export_cameras=False, export_lights=False)
        try:
            bpy.ops.export_scene.gltf(export_vertex_color="MATERIAL", **kwargs)
        except TypeError:
            bpy.ops.export_scene.gltf(**kwargs)
        LAYOUT.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    report["previews"] = render_previews(cameras, {"SB_Launch": launch_root, "SB_Pontoon": pontoon_root}, people, True) if DO_RENDER else []
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    return report


if __name__ == "__main__":
    RESULT = main()
