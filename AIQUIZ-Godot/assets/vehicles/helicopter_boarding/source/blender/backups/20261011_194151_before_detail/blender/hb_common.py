"""乗り込めるヘリ（helicopter_boarding）のビルダーの共通部分：数値の読み込み、座標の変換、メッシュの組み立て、材質。

数値は source/heli_pilot_spec.json から読む（設計図 artifacts/heli_blueprint の make_blueprint.py が書き出す写し。
artifacts/ は git の管理外なので、写しをこの素材のフォルダに置く）。設計図を直したら
`python artifacts/heli_blueprint/make_blueprint.py spec` で JSON を書き直してから、このビルダーを流す。

座標：形は Godot の座標で書く（x 右、y 上、機首 -z、m）。y は地面（スキッドの下面）基準の値で書き、
P() で GLB の原点（ローター軸 × 地面から ORIGIN_Y）基準の Blender 座標へ変える：Godot (x, y, z) → Blender (x, -z, y - ORIGIN_Y)。
glTF の書き出し（export_yup）で Blender (x, y, z) → glTF (x, z, -y) になり、Godot の座標に戻る。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
ASSET = SRC.parent
ROOT = ASSET.parents[2]
SPEC_PATH = SRC / "heli_pilot_spec.json"   # 設計図（artifacts/heli_blueprint、git の管理外）が書き出す写し
REFS_PATH = ROOT / "artifacts" / "heli_blueprint" / "data" / "review_refs.json"   # 確認用の人物（なくても作れる）
BLEND = HERE / "helicopter_boarding.blend"
GLB = ASSET / "helicopter_boarding.glb"
LAYOUT_JSON = ASSET / "helicopter_boarding_layout.json"
PREVIEW = SRC / "previews"
REPORT = SRC / "build_report.json"
SCENE_NAME = "HB_HelicopterBoarding"

SPEC = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
ORIGIN_Y = SPEC["origin_y"]

# Blender の座標へ（P は位置、D は向き）
_C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def P(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y - ORIGIN_Y))


def D(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def basis_g2b(m3: Matrix) -> Matrix:
    """Godot の座標での回転（列＝基底）を Blender の回転へ。"""
    return _C @ m3 @ _C.inverted()


# ---------------------------------------------------------------- 補間

def pchip(xk, yk, x):
    """単調な 3 次補間（Fritsch–Carlson）。設計図（heli_design.py）と同じ式。"""
    n = len(xk)
    h = [xk[i + 1] - xk[i] for i in range(n - 1)]
    d = [(yk[i + 1] - yk[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    m[0], m[-1] = d[0], d[-1]
    x = min(max(x, xk[0]), xk[-1])
    i = 0
    while i < n - 2 and x > xk[i + 1]:
        i += 1
    t = (x - xk[i]) / h[i]
    h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
    h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
    return h00 * yk[i] + h10 * h[i] * m[i] + h01 * yk[i + 1] + h11 * h[i] * m[i + 1]


BP = SPEC["body_profile"]


def body_params(z):
    """z での胴体（外形）の断面：上端・下端・いちばん太い高さ・半幅・丸み。"""
    t = min(max((z - BP["z"][0]) / (-1.60 - BP["z"][0]), 0.0), 1.0)
    return dict(top=pchip(BP["z"], BP["top"], z), bottom=pchip(BP["z"], BP["bottom"], z), belt=pchip(BP["z"], BP["belt"], z),
                a=pchip(BP["z"], BP["half_width"], z), n_top=BP["n_top"][0] + (BP["n_top"][1] - BP["n_top"][0]) * t, n_bot=BP["n_bottom"])


def section_point(p, theta, wall=0.0):
    """断面の上の点（θ は +x から反時計回り）。wall だけ内側の面（内張り）。"""
    a, top, bottom, belt = p["a"] - wall, p["top"] - wall, p["bottom"] + wall, p["belt"]
    c, s = math.cos(theta), math.sin(theta)
    n = p["n_top"] if s >= 0 else p["n_bot"]
    h = (top - belt) if s >= 0 else (belt - bottom)
    x = a * math.copysign(abs(c) ** (2 / n), c)
    y = belt + h * math.copysign(abs(s) ** (2 / n), s)
    return x, y


def section_extent(z, x=None, y=None, inner=False):
    p = body_params(z)
    wall = BP["wall"] if inner else 0.0
    a, top, bottom, belt = p["a"] - wall, p["top"] - wall, p["bottom"] + wall, p["belt"]
    if x is not None:
        r = abs(x) / a
        return None if r >= 1 else belt + (top - belt) * (1 - r ** p["n_top"]) ** (1 / p["n_top"])
    if y >= belt:
        r, n = (y - belt) / (top - belt), p["n_top"]
    else:
        r, n = (belt - y) / (belt - bottom), p["n_bot"]
    return 0.0 if r >= 1 else a * (1 - r ** n) ** (1 / n)


# ---------------------------------------------------------------- メッシュの組み立て（Godot の座標で書く）

WHITE = (1.0, 1.0, 1.0, 1.0)


class GMesh:
    """面ごとに材質キーを持つメッシュ。点は Godot の座標（地面基準）で渡し、Blender の座標で持つ。"""

    def __init__(self):
        self.v: list[Vector] = []
        self.f: list[tuple] = []
        self.mat: list[str] = []
        self.smooth: list[bool] = []
        self._weld: dict = {}

    def face(self, pts, mat, smooth=False, convert=True, weld=None):
        """weld に名前を渡すと、同じ名前の面どうしで同じ位置の点を 1 つにする（なめらかな陰影がつながる）。"""
        idx = []
        for p in pts:
            v = P(p) if convert else Vector(p)
            if weld is not None:
                key = (weld, round(v.x, 5), round(v.y, 5), round(v.z, 5))
                i = self._weld.get(key)
                if i is None:
                    i = len(self.v)
                    self.v.append(v)
                    self._weld[key] = i
            else:
                i = len(self.v)
                self.v.append(v)
            if not idx or idx[-1] != i:
                idx.append(i)
        if len(idx) > 1 and idx[0] == idx[-1]:
            idx.pop()
        if len(set(idx)) < 3:
            return
        self.f.append(tuple(idx))
        self.mat.append(mat)
        self.smooth.append(smooth)

    def box(self, center, size, mat, rot: Matrix | None = None, faces="all", chamfer=0.0):
        """Godot の座標の箱。rot は Godot の座標での回転（3x3）。chamfer > 0 なら角を落とす（8 角を面取り）。"""
        cx, cy, cz = center
        sx, sy, sz = (s / 2 for s in size)
        rot = rot or Matrix.Identity(3)
        c = Vector(center)

        def q(x, y, z):
            return tuple(c + rot @ Vector((x, y, z)))

        if chamfer <= 0:
            p = [q(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
            spec = {"-x": (0, 1, 3, 2), "+x": (4, 6, 7, 5), "-y": (0, 4, 5, 1), "+y": (2, 3, 7, 6), "-z": (0, 2, 6, 4), "+z": (1, 5, 7, 3)}
            for key, idx in spec.items():
                if faces == "all" or key in faces:
                    self.face([p[i] for i in idx], mat)
            return
        e = chamfer
        # 面取りの箱：各面を内側に縮めた四角＋辺の帯＋角の三角
        for axis in range(3):
            for sign in (-1, 1):
                pts = []
                u, w = [a for a in range(3) if a != axis]
                half = [sx, sy, sz]
                for du, dw in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    v = [0.0, 0.0, 0.0]
                    v[axis] = sign * half[axis]
                    v[u] = du * (half[u] - e)
                    v[w] = dw * (half[w] - e)
                    pts.append(q(*v))
                if sign < 0:
                    pts.reverse()
                n = Vector((0, 0, 0))
                n[axis] = sign
                self._oriented(pts, rot @ n, mat)
        half = [sx, sy, sz]
        for a in range(3):
            b, cc = [i for i in range(3) if i != a]
            for sb in (-1, 1):
                for sc in (-1, 1):
                    pts = []
                    for sa in (-1, 1):
                        v1 = [0.0] * 3
                        v1[a] = sa * (half[a] - e)
                        v1[b] = sb * half[b]
                        v1[cc] = sc * (half[cc] - e)
                        v2 = [0.0] * 3
                        v2[a] = sa * (half[a] - e)
                        v2[b] = sb * (half[b] - e)
                        v2[cc] = sc * half[cc]
                        pts += [q(*v1), q(*v2)]
                    n = Vector((0, 0, 0))
                    n[b], n[cc] = sb, sc
                    self._oriented([pts[0], pts[1], pts[3], pts[2]], rot @ n, mat)
        for sx_ in (-1, 1):
            for sy_ in (-1, 1):
                for sz_ in (-1, 1):
                    pts = [q(sx_ * sx, sy_ * (sy - e), sz_ * (sz - e)), q(sx_ * (sx - e), sy_ * sy, sz_ * (sz - e)), q(sx_ * (sx - e), sy_ * (sy - e), sz_ * sz)]
                    self._oriented(pts, rot @ Vector((sx_, sy_, sz_)), mat)

    def _oriented(self, pts, normal_g, mat, smooth=False):
        a, b, c = (Vector(p) for p in pts[:3])
        n = (b - a).cross(c - a)
        if n.dot(Vector(normal_g)) < 0:
            pts = list(reversed(pts))
        self.face(pts, mat, smooth)

    def tube(self, a, b, r, mat, n=10, caps=True, r1=None, smooth=True):
        a, b = Vector(a), Vector(b)
        d = (b - a)
        if d.length < 1e-9:
            return
        d.normalize()
        up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        w = d.cross(u).normalized()
        r1 = r if r1 is None else r1
        ring_a = [a + r * (math.cos(t) * u + math.sin(t) * w) for t in (2 * math.pi * k / n for k in range(n))]
        ring_b = [b + r1 * (math.cos(t) * u + math.sin(t) * w) for t in (2 * math.pi * k / n for k in range(n))]
        for k in range(n):
            j = (k + 1) % n
            self._oriented([ring_a[k], ring_a[j], ring_b[j], ring_b[k]], (ring_a[k] + ring_a[j]) / 2 - a, mat, smooth)
        if caps:
            self._oriented(list(reversed(ring_a)), -d, mat)
            self._oriented(ring_b, d, mat)

    def polyline_tube(self, pts, r, mat, n=10):
        """折れ線にそった管（つなぎ目に球のかわりの小さな輪を置かず、端だけふさぐ）。"""
        for i in range(len(pts) - 1):
            self.tube(pts[i], pts[i + 1], r, mat, n, caps=(i == 0 or i == len(pts) - 2))

    def extrude_x(self, poly_zy, x0, x1, mat, bevel_side=None):
        """z-y 平面の凸でない多角形（時計回り・反時計回りどちらでも）を x0〜x1 に押し出す。上下の面は扇で張る（凸に近い形に使う）。"""
        pts = [(z, y) for z, y in poly_zy]
        cz = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            (z0, y0), (z1, y1) = pts[i], pts[j]
            side = [(x0, y0, z0), (x0, y1, z1), (x1, y1, z1), (x1, y0, z0)]
            mid = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
            self._oriented(side, mid - Vector(((x0 + x1) / 2, cy, cz)), mat)
            self._oriented([(x0, cy, cz), (x0, y0, z0), (x0, y1, z1)], (-1, 0, 0), mat)
            self._oriented([(x1, cy, cz), (x1, y1, z1), (x1, y0, z0)], (1, 0, 0), mat)

    def extend(self, other: "GMesh"):
        base = len(self.v)
        self._weld.update({k: i + base for k, i in other._weld.items()})
        self.v.extend(other.v)
        self.f.extend(tuple(i + base for i in f) for f in other.f)
        self.mat.extend(other.mat)
        self.smooth.extend(other.smooth)

    def triangles(self):
        return sum(len(f) - 2 for f in self.f)


def create_object(name, mesh: GMesh, materials: dict, collection, parent=None):
    me = bpy.data.meshes.get(name)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in mesh.v], [], mesh.f)
    keys = []
    for k in mesh.mat:
        if k not in keys:
            keys.append(k)
    for k in keys:
        me.materials.append(materials[k])
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    uv = me.uv_layers.new(name="UVMap")
    for poly, key, sm in zip(me.polygons, mesh.mat, mesh.smooth):
        poly.material_index = keys.index(key)
        poly.use_smooth = bool(sm)
        for li in poly.loop_indices:
            col.data[li].color = WHITE
            uv.data[li].uv = (0.5, 0.5)
    me.color_attributes.active_color = col
    me.validate(clean_customdata=False)
    me.update()
    obj = bpy.data.objects.new(name, me)
    collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


# ---------------------------------------------------------------- 材質（名前は Godot のコードが探す名前）

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, alpha=1.0):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (alpha,)


def lin(rgb, alpha=1.0):
    """設計図の色（Godot の Color＝sRGB の値）を線形へ。"""
    return tuple(srgb_to_linear(c) for c in rgb) + (alpha,)


MATERIAL_SPECS = {
    # 名前: (色（線形 RGBA）, 粗さ, 金属, 発光の強さ, 両面, 透明)
    "BodyPaint": (lin(SPEC["colors"]["body_paint"]), 0.42, 0.0, 0.0, False, False),
    "Trim": (hexcol("#F4F3EE"), 0.5, 0.0, 0.0, False, False),
    "Windows": (lin(SPEC["colors"]["glass"], 0.34), 0.06, 0.08, 0.0, True, True),
    "Charcoal": (hexcol("#2B3038"), 0.55, 0.25, 0.0, False, False),
    "Rubber": (hexcol("#1C1E22"), 0.85, 0.0, 0.0, False, False),
    "Interior": (hexcol("#A7AEB8"), 0.75, 0.0, 0.0, False, False),
    "Floor": (hexcol("#5E6670"), 0.85, 0.0, 0.0, False, False),
    "SeatFabric": (hexcol("#3A4C70"), 0.9, 0.0, 0.0, False, False),
    "DashDark": (hexcol("#33373F"), 0.6, 0.0, 0.0, False, False),
    "ScreenGlow": (hexcol("#5ED8F2"), 0.3, 0.0, 2.2, False, False),
    "NavRed": (hexcol("#FF3A2E"), 0.3, 0.0, 3.0, False, False),
    "NavGreen": (hexcol("#33E06A"), 0.3, 0.0, 3.0, False, False),
    "LampWhite": (hexcol("#FFF6DC"), 0.3, 0.0, 3.0, False, False),
    "DropHatchInterior": (hexcol("#5A5650"), 0.8, 0.0, 0.0, False, False),
    "JetGlow": (hexcol("#FF9A3C"), 0.3, 0.0, 4.0, False, False),   # ジェットの噴射口の奥（Godot が強さを変える）
}


def make_materials():
    mats = {}
    for name, (rgba, rough, metal, emit, double, alpha) in MATERIAL_SPECS.items():
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.name = "Principled BSDF"
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emit
        if alpha:
            bsdf.inputs["Alpha"].default_value = rgba[3]
            mat.surface_render_method = "BLENDED"
        mat.use_backface_culling = not double
        mat.diffuse_color = rgba
        mats[name] = mat
    return mats


def collection(name, parent=None):
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if coll.name not in [c.name for c in parent.children]:
        parent.children.link(coll)
    return coll


def empty(name, coll, location=(0, 0, 0), parent=None, display="PLAIN_AXES", size=0.25):
    obj = bpy.data.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, None)
        coll.objects.link(obj)
    obj.empty_display_type = display
    obj.empty_display_size = size
    obj.location = location
    if parent is not None:
        obj.parent = parent
    return obj


def set_pivot(obj, pivot_b: Vector, rot_b: Matrix | None = None):
    """メッシュをそのままの位置に保ったまま、原点を pivot_b（Blender の座標）へ、向きを rot_b（3x3）へ。"""
    m = Matrix.Translation(pivot_b) @ (rot_b.to_4x4() if rot_b is not None else Matrix.Identity(4))
    obj.data.transform(m.inverted())
    obj.data.update()
    obj.matrix_basis = m
