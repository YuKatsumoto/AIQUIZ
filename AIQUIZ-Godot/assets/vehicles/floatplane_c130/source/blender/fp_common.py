"""サドンデスの水上機 C-130（floatplane_c130）のビルダーの共通部分：寸法の読み込み、座標の変換、メッシュの組み立て、材質。

寸法は source/c130_design.py（artifacts/sudden_death_v2/c130_float/c130_design.py の写し）から読む。
形は設計の座標で考える：u＝機首の先から後ろへ（m）、v＝海面からの高さ（m）、x＝左右（機体の右が +）。

座標の約束（docs/sudden_death_v2/skygate_build_plan.md 4.2）：
  Godot（GLB）の座標 = (x, v, u − 6.6)。原点は海面 × 機体の中心線 × 主翼の翼弦の中央（機首から 6.6 m）。+Y が上、機首が −Z。
  Blender の座標 = Godot (x, y, z) → (x, −z, y)。glTF の書き出し（export_yup）で Godot の座標に戻る。
  W(u, v, x) は設計の座標 → Godot の座標。P() は Godot → Blender。

メッシュ（GMesh）は面ごとに材質・なめらかさを持つ。なめらかな面は溶接の名前（weld）を付けて頂点を共有する
（付けないと陰影がカクカクになる）。胴体のような格子は grid() で番号をじかに組む。
"""
from __future__ import annotations

import importlib.util
import itertools
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
ASSET = SRC.parent
ROOT = ASSET.parents[2]
BLEND = HERE / "floatplane_c130.blend"
GLB = ASSET / "floatplane_c130.glb"
LAYOUT_JSON = ASSET / "floatplane_c130_layout.json"
PREVIEW = SRC / "previews"
REPORT = SRC / "build_report.json"
BACKUPS = HERE / "backups"
DESIGN_PATH = SRC / "c130_design.py"
DESIGN_ORIGINAL = ROOT / "artifacts" / "sudden_death_v2" / "c130_float" / "c130_design.py"
SCENE_NAME = "FP_FloatplaneC130"


def _load_design():
    spec = importlib.util.spec_from_file_location("fp_c130_design", DESIGN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


C = _load_design()
U0 = 0.5 * (C.WING_U[0] + C.WING_U[1])   # 6.6：原点の u（主翼の翼弦の中央）

# Blender の座標へ（P は位置、D は向き）
_C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def W(u, v, x=0.0):
    """設計の座標（u, v, x）→ Godot の座標（x, y, z）。"""
    return Vector((x, v, u - U0))


def P(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def D(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def G(v_b):
    """Blender の座標 → Godot の座標。P() の逆。"""
    return Vector((v_b[0], v_b[2], -v_b[1]))


def basis_g2b(m3: Matrix) -> Matrix:
    return _C @ m3 @ _C.inverted()


# ---------------------------------------------------------------- 補間

def pchip(xk, yk, x):
    return C.pchip(xk, yk, x)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def clamp(x, a, b):
    return min(max(x, a), b)


# ---------------------------------------------------------------- 色（線形の RGBA）

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, alpha=1.0):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (alpha,)


WHITE = (1.0, 1.0, 1.0, 1.0)


# ---------------------------------------------------------------- メッシュの組み立て（Godot の座標で書く）

_WELD_SEQ = itertools.count()


def new_weld(tag):
    return f"{tag}#{next(_WELD_SEQ)}"


def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    k = len(pts)
    for i in range(k):
        a, b = pts[i], pts[(i + 1) % k]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


def frame_from(normal, along=None):
    n = Vector(normal).normalized()
    if along is not None:
        a = Vector(along)
        u = a - n * a.dot(n)
        if u.length > 1e-6:
            u.normalize()
            return u, n.cross(u)
    up = Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))
    u = n.cross(up).normalized()
    return u, n.cross(u)


class GMesh:
    """面ごとに材質キーを持つメッシュ。点は Godot の座標で渡し、Blender の座標で持つ。"""

    def __init__(self):
        self.v: list[Vector] = []
        self.vg: list[Vector] = []      # 同じ点の Godot の座標（向きをそろえるのに使う）
        self.f: list[tuple] = []
        self.mat: list[str] = []
        self.smooth: list[bool] = []
        self.uv: list = []              # 面ごとの角の UV（None なら 0, 0）
        self._weld: dict = {}
        self.rejected = 0

    # -------- 頂点をじかに足す（格子用）
    def vert(self, p_g) -> int:
        self.v.append(P(p_g))
        self.vg.append(Vector(p_g))
        return len(self.v) - 1

    def face_idx(self, idx, mat, smooth=False, hint=None, uv=None):
        """番号で面を足す。hint（Godot の向き）を渡すと、面の表をその向きにそろえる。uv は角ごとの (u, v)。"""
        out, ouv = [], []
        for k, i in enumerate(idx):
            if not out or out[-1] != i:
                out.append(i)
                ouv.append(uv[k] if uv is not None else None)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
            ouv.pop()
        if len(set(out)) < 3 or len(set(out)) != len(out):
            self.rejected += 1
            return
        if hint is not None and _newell([self.vg[i] for i in out]).dot(Vector(hint)) < 0:
            out.reverse()
            ouv.reverse()
        self.f.append(tuple(out))
        self.mat.append(mat)
        self.smooth.append(smooth)
        self.uv.append(tuple(ouv) if uv is not None else None)

    # -------- 点の並びから面を足す
    def face(self, pts, mat, smooth=False, weld=None, uv=None):
        idx = []
        for p in pts:
            v = P(p)
            if weld is not None:
                key = (weld, round(v.x, 5), round(v.y, 5), round(v.z, 5))
                i = self._weld.get(key)
                if i is None:
                    i = len(self.v)
                    self.v.append(v)
                    self.vg.append(Vector(p))
                    self._weld[key] = i
            else:
                i = len(self.v)
                self.v.append(v)
                self.vg.append(Vector(p))
            idx.append(i)
        self.face_idx(idx, mat, smooth, uv=uv)

    def oriented(self, pts, normal_g, mat, smooth=False, weld=None, uv=None):
        """面の向きを normal_g（Godot）にそろえて足す。"""
        if _newell([Vector(p) for p in pts]).dot(Vector(normal_g)) < 0:
            pts = list(reversed(pts))
            uv = list(reversed(uv)) if uv is not None else None
        self.face(pts, mat, smooth, weld=weld, uv=uv)

    MAX_CELL = 0.45                 # 箱の面をこの大きさ以下の格子に分ける（頂点に焼く AO が長い面でも効くように）

    def box(self, center, size, mat, rot: Matrix | None = None, faces="all"):
        """Godot の座標の箱。rot は Godot の座標での回転（3x3）。長い面は MAX_CELL 以下の格子に分ける。"""
        half = [s_ / 2 for s_ in size]
        rot = rot or Matrix.Identity(3)
        c = Vector(center)

        def q(v3):
            return tuple(c + rot @ Vector(v3))

        spec = {"-x": (0, -1, 1, 2), "+x": (0, 1, 2, 1), "-y": (1, -1, 2, 0), "+y": (1, 1, 0, 2), "-z": (2, -1, 0, 1), "+z": (2, 1, 1, 0)}
        for key, (ax, sg, b, cc) in spec.items():
            if faces != "all" and key not in faces:
                continue
            nb = max(1, int(math.ceil(size[b] / self.MAX_CELL - 1e-9)))
            nc = max(1, int(math.ceil(size[cc] / self.MAX_CELL - 1e-9)))
            n = [0.0, 0.0, 0.0]
            n[ax] = sg
            normal = tuple(rot @ Vector(n))
            for i in range(nb):
                for j in range(nc):
                    pts = []
                    for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                        v3 = [0.0, 0.0, 0.0]
                        v3[ax] = sg * half[ax]
                        v3[b] = -half[b] + size[b] * (i + di) / nb
                        v3[cc] = -half[cc] + size[cc] * (j + dj) / nc
                        pts.append(q(v3))
                    self.oriented(pts, normal, mat)

    def box_between(self, a, b, w, h, mat, up=(0, 1, 0)):
        """a → b の向きに長い箱（幅 w・高さ h）。up は高さの向きの手がかり。"""
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-9:
            return
        ez = d.normalized()
        ex = Vector(up).cross(ez)
        if ex.length < 1e-6:
            ex = Vector((1, 0, 0)).cross(ez)
        ex.normalize()
        ey = ez.cross(ex)
        self.box(tuple((a + b) / 2), (w, h, d.length), mat, rot=Matrix((ex, ey, ez)).transposed())

    def sweep(self, pts, radii, mat, n=10, caps=("flat", "flat"), smooth=True, weld=None, crease_deg=60.0, closed=False):
        """折れ線にそった 1 本の管（平行移動の枠でねじれない）。closed=True で輪（最後と最初をつなぐ）。"""
        P_, R_ = [], []
        for p, r in zip(pts, radii):
            v = Vector(p)
            if P_ and (v - P_[-1]).length < 1e-9:
                continue
            P_.append(v)
            R_.append(float(r))
        if closed and (P_[0] - P_[-1]).length < 1e-9:
            P_.pop()
            R_.pop()
        m = len(P_)
        if m < 2:
            return None
        if closed:
            d = [(P_[(i + 1) % m] - P_[i]).normalized() for i in range(m)]
        else:
            d = [(P_[i + 1] - P_[i]).normalized() for i in range(m - 1)]
        up = Vector((0, 1, 0)) if abs(d[0].y) < 0.9 else Vector((1, 0, 0))
        u = d[0].cross(up).normalized()
        rings = []
        for i in range(m):
            if closed:
                din, dout = d[i - 1], d[i]
            else:
                din = d[i - 1] if i > 0 else d[0]
                dout = d[i] if i < m - 1 else d[-1]
            t = din + dout
            t = t.normalized() if t.length > 1e-9 else dout
            u = u - t * u.dot(t)
            u.normalize()
            w = t.cross(u)
            mitre = None
            phi = math.acos(max(-1.0, min(1.0, din.dot(dout))))
            if phi > 1e-4:
                mitre = ((dout - din).normalized(), 1.0 / math.cos(phi / 2))
            ring = []
            for k in range(n):
                ang = 2 * math.pi * k / n
                v = R_[i] * (math.cos(ang) * u + math.sin(ang) * w)
                if mitre is not None:
                    bb, sc = mitre
                    v = v + (sc - 1.0) * v.dot(bb) * bb
                ring.append(P_[i] + v)
            rings.append(ring)
        base = weld or new_weld("sweep")
        segs = m if closed else m - 1
        for i in range(segs):
            j1 = (i + 1) % m
            wname = base if smooth else None
            if not closed and i > 0:
                phi = math.acos(max(-1.0, min(1.0, d[i - 1].dot(d[i]))))
                if phi > math.radians(crease_deg):
                    base = new_weld("sweep")
                    wname = base if smooth else None
            ra, rb = rings[i], rings[j1]
            axis_mid = (P_[i] + P_[j1]) / 2
            for k in range(n):
                kk = (k + 1) % n
                quad = [ra[k], ra[kk], rb[kk], rb[k]]
                mid = (quad[0] + quad[1] + quad[2] + quad[3]) / 4
                self.oriented([tuple(q) for q in quad], tuple(mid - axis_mid), mat, smooth, weld=wname)
        if not closed:
            for end, kind in ((0, caps[0]), (m - 1, caps[1])):
                if kind is None or R_[end] < 1e-9:
                    continue
                t = -d[0] if end == 0 else d[-1]
                self.oriented([tuple(p) for p in rings[end]], tuple(t), mat)
        return rings

    TUBE_SEG = 0.25                 # 長い管はこの長さごとに輪を入れる（頂点の AO のため）

    def tube(self, a, b, r, mat, n=10, caps=True, r1=None, smooth=True):
        a, b = Vector(a), Vector(b)
        L = (b - a).length
        if L < 1e-9:
            return
        cap = "flat" if caps else None
        k = max(1, int(math.ceil(L / self.TUBE_SEG)))
        r1 = r if r1 is None else r1
        pts = [tuple(a + (b - a) * (i / k)) for i in range(k + 1)]
        radii = [r + (r1 - r) * (i / k) for i in range(k + 1)]
        self.sweep(pts, radii, mat, n=n, caps=(cap, cap), smooth=smooth)

    def polyline_tube(self, pts, r, mat, n=8, caps=True, closed=False):
        cap = "flat" if caps else None
        self.sweep(pts, [r] * len(pts), mat, n=n, caps=(cap, cap), closed=closed)

    def lathe(self, origin, axis, stations, mat, ref=None, n=16, smooth=True, crease_deg=35.0, mats=None, cap0=None, cap1=None):
        """軸にそった回転体。stations は [(軸の上の距離 s, 半径 r)]。mats は区間ごとの材質。cap0/cap1 = "flat" で端をふさぐ。"""
        o = Vector(origin)
        ax = Vector(axis).normalized()
        if ref is None:
            ref = (1, 0, 0) if abs(ax.x) < 0.9 else (0, 1, 0)
        e1 = Vector(ref)
        e1 = (e1 - ax * e1.dot(ax)).normalized()
        e2 = ax.cross(e1)
        phis = [2 * math.pi * k / n for k in range(n)]
        rings = [[o + ax * s + r * (math.cos(p) * e1 + math.sin(p) * e2) for p in phis] for s, r in stations]
        base = new_weld("lathe")
        prev_a = None
        for i in range(len(stations) - 1):
            (s0, r0), (s1, r1) = stations[i], stations[i + 1]
            a_i = math.atan2(r1 - r0, s1 - s0)
            if prev_a is not None and abs(a_i - prev_a) > math.radians(crease_deg):
                base = new_weld("lathe")
            prev_a = a_i
            wname = base if smooth else None
            mat_i = mats[i] if mats else mat
            ra, rb = rings[i], rings[i + 1]
            for k in range(n):
                j = (k + 1) % n
                pm = phis[k] + math.pi / n
                er = math.cos(pm) * e1 + math.sin(pm) * e2
                hint = er * (s1 - s0) - ax * (r1 - r0)
                if hint.dot(er) < 0:
                    hint = -hint         # いつも軸から外へ（s が減る並びでも同じ）
                if hint.length < 1e-9:
                    hint = er
                self.oriented([tuple(ra[k]), tuple(ra[j]), tuple(rb[j]), tuple(rb[k])], tuple(hint), mat_i, smooth, weld=wname)
        for idx, kind in ((0, cap0), (len(stations) - 1, cap1)):
            if kind == "flat" and stations[idx][1] > 1e-9:
                out = -ax if idx == 0 else ax
                cap_mat = mat if not mats else mats[0 if idx == 0 else -1]
                self.oriented([tuple(p) for p in rings[idx]], tuple(out), cap_mat)
        return rings

    def loft(self, rings, mat, closed=True, smooth=True, weld=None, mats=None, cap0=False, cap1=False, hint_fn=None):
        """輪（同じ点の数）の並びを張る。mats(i, k) で面ごとの材質。cap0/cap1 で端の輪をふさぐ（中心の点へ扇）。"""
        base = weld or new_weld("loft")
        wname = base if smooth else None
        n = len(rings[0])
        cents = [sum((Vector(p) for p in r), Vector()) / n for r in rings]
        for i in range(len(rings) - 1):
            ra, rb = rings[i], rings[i + 1]
            for k in range(n if closed else n - 1):
                j = (k + 1) % n
                quad = [ra[k], ra[j], rb[j], rb[k]]
                mid = sum((Vector(p) for p in quad), Vector()) / 4
                hint = hint_fn(i, k) if hint_fn else mid - (cents[i] + cents[i + 1]) / 2
                self.oriented([tuple(q) for q in quad], tuple(hint), mats(i, k) if mats else mat, smooth, weld=wname)
        for idx, on in ((0, cap0), (len(rings) - 1, cap1)):
            if not on:
                continue
            r = rings[idx]
            c = cents[idx]
            other = cents[1] if idx == 0 else cents[-2]
            out = c - other
            m_ = mats(idx if idx == 0 else idx - 1, 0) if mats else mat
            for k in range(n if closed else n - 1):
                j = (k + 1) % n
                self.oriented([tuple(r[k]), tuple(r[j]), tuple(c)], tuple(out), m_, smooth=False)

    def prism(self, poly, axis_from, axis_to, mat, side_mat=None):
        """凸な多角形 poly（3D の点、平面）を axis_from → axis_to のずれで押し出す。"""
        a = [Vector(p) for p in poly]
        off = Vector(axis_to) - Vector(axis_from)
        b = [p + off for p in a]
        n = len(a)
        cen = sum(a, Vector()) / n + off / 2
        for i in range(n):
            j = (i + 1) % n
            mid = (a[i] + a[j] + b[i] + b[j]) / 4
            self.oriented([tuple(a[i]), tuple(a[j]), tuple(b[j]), tuple(b[i])], tuple(mid - cen), side_mat or mat)
        self.oriented([tuple(p) for p in a], tuple(-off), mat)
        self.oriented([tuple(p) for p in b], tuple(off), mat)

    def extend(self, other: "GMesh"):
        base = len(self.v)
        self.v.extend(other.v)
        self.vg.extend(other.vg)
        self.f.extend(tuple(i + base for i in f) for f in other.f)
        self.mat.extend(other.mat)
        self.smooth.extend(other.smooth)
        self.uv.extend(other.uv)
        self.rejected += other.rejected

    def triangles(self):
        return sum(len(f) - 2 for f in self.f)


def create_object(name, mesh: GMesh, materials: dict, coll, parent=None, sharp_deg=None):
    old = bpy.data.objects.get(name)
    if old is not None:
        data = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)
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
    index_of = {k: i for i, k in enumerate(keys)}
    if any(u is not None for u in mesh.uv):
        uvs = []
        for f, fu in zip(mesh.f, mesh.uv):
            for k in range(len(f)):
                uvs.extend(fu[k] if fu is not None else (0.0, 0.0))
        layer = me.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", uvs)
    me.polygons.foreach_set("material_index", [index_of[k] for k in mesh.mat])
    me.polygons.foreach_set("use_smooth", [bool(s) for s in mesh.smooth])
    me.validate(clean_customdata=False)
    if sharp_deg is not None:
        try:
            me.set_sharp_from_angle(angle=math.radians(sharp_deg))
        except Exception:   # noqa: BLE001
            pass
    me.update()
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


# ---------------------------------------------------------------- 材質（名前は Godot のコードが探す名前）

def Mspec(color, rough, metal=0.0, emit=0.0, double=False, alpha=1.0):
    return {"color": color, "rough": rough, "metal": metal, "emit": emit, "double": double, "alpha": alpha}


NAVY_HEX = "#1D2F5C"     # 世界の看板と同じ濃紺（BRAND_NAVY）
MATERIAL_SPECS = {
    # 外板（計画書 4.2 の名前）
    "FP_Paint": Mspec(hexcol("#F4F5F2"), 0.30),
    "FP_Navy": Mspec(hexcol(NAVY_HEX), 0.32),
    "FP_StripeOrange": Mspec(hexcol("#F28A1E"), 0.34),
    "FP_StripeBlue": Mspec(hexcol("#2F8FE0"), 0.34),
    "FP_Glass": Mspec(hexcol("#9FD4F0", 0.30), 0.05, double=True, alpha=0.30),
    # 外の部品
    "FP_Metal": Mspec(hexcol("#B9C0C8"), 0.22, 0.9),
    "FP_Dark": Mspec(hexcol("#2C3139"), 0.55, 0.15),
    "FP_PropBlade": Mspec(hexcol("#3A3F47"), 0.45, 0.2),
    "FP_PropTip": Mspec(hexcol("#F5C527"), 0.40),
    "FP_Spinner": Mspec(hexcol("#F28A1E"), 0.30),
    "FP_HazardYellow": Mspec(hexcol("#F2C230"), 0.55),
    "FP_HazardBlack": Mspec(hexcol("#24272C"), 0.60),
    # 灯（計画書 4.2 の名前。降下のランプは Godot が光らせ方を変える）
    "FP_LightRed": Mspec(hexcol("#FF3A2E"), 0.25, emit=2.5),
    "FP_LightGreen": Mspec(hexcol("#33E06A"), 0.25, emit=2.5),
    "FP_LightWhite": Mspec(hexcol("#FFF4D8"), 0.25, emit=2.5),
    # 機内（A：実機ふう。赤い布の座席・網・むき出しの骨組み・灰色のリブの壁・暖かい照明）
    "FP_InteriorWall": Mspec(hexcol("#AEB3B8"), 0.78),
    "FP_InteriorFrame": Mspec(hexcol("#B4BAAE"), 0.58, 0.0),     # 骨組み（塗った下塗りの灰緑。金属の映り込みはない）
    "FP_InteriorFloor": Mspec(hexcol("#5A6068"), 0.72, 0.35),
    "FP_InteriorDark": Mspec(hexcol("#2E3238"), 0.70),
    "FP_InteriorMetal": Mspec(hexcol("#C7CCD2"), 0.28, 0.9),
    "FP_InteriorYellow": Mspec(hexcol("#F2B81E"), 0.50),
    "FP_InteriorNet": Mspec(hexcol("#7A7448"), 0.90),
    "FP_InteriorLamp": Mspec(hexcol("#FFE2B0"), 0.40, emit=3.0),
    "FP_InteriorSeat": Mspec(hexcol("#22355F"), 0.65),
    "FP_InteriorScreen": Mspec(hexcol("#6FE3F5"), 0.30, emit=1.6),
    "FP_InteriorGauge": Mspec(hexcol("#F2F4F0"), 0.40, emit=0.6),
    "FP_InteriorKnob": Mspec(hexcol("#F28A1E"), 0.35),
    "FP_SeatWebbing": Mspec(hexcol("#C8352B"), 0.85),
    # 2026-10-18 実機ふうの作り込みで足した材質
    "FP_SeatFabric": Mspec(hexcol("#B8302A"), 0.88),          # 座面の赤いナイロンの布
    "FP_InteriorBlanket": Mspec(hexcol("#A7AE9B"), 0.92),     # 灰緑のキルティングの断熱材
    "FP_InteriorDuct": Mspec(hexcol("#C7B489"), 0.70),        # 空調ダクト（黄土色）
    "FP_InteriorTrim": Mspec(hexcol("#E9E8E2"), 0.45),        # 丸窓の白い縁・灯の器具
    "FP_InteriorLampAmber": Mspec(hexcol("#FFB531"), 0.40, emit=2.5),
    "FP_InteriorOxygen": Mspec(hexcol("#4E8A4F"), 0.40, 0.3), # 酸素の管（緑）
    "FP_InteriorRed": Mspec(hexcol("#C22A22"), 0.35),         # 消火器
    "FP_InteriorOlive": Mspec(hexcol("#5F6247"), 0.85),       # 袋・救急箱
    "FP_InteriorDoor": Mspec(hexcol("#8E9590"), 0.55, 0.2),   # 乗員の扉の板
    "FP_InteriorBelt": Mspec(hexcol("#6A6A58"), 0.80),        # 腰のベルト（灰緑）
    "FP_InteriorTread": Mspec(hexcol("#7D838A"), 0.45, 0.6),  # 段・操縦席の床の縞鋼板
    "FP_InteriorDecal": Mspec(hexcol("#FFFFFF"), 0.80),       # 機内のステンシル（アトラス、アルファ）
    "FP_InteriorPanel": Mspec(hexcol("#FFFFFF"), 0.45),       # 操縦席の計器・スイッチの盤面（アトラス）
    "FP_Decal": Mspec(hexcol("#FFFFFF"), 0.40),               # 外板の文字（アトラス、アルファ）
    "FP_Rubber": Mspec(hexcol("#202225"), 0.90),              # フロートの通路の滑り止め
    # 2026-10-22 クオリティーを上げたときに足した材質
    "FP_Exhaust": Mspec(hexcol("#4A3F36"), 0.42, 0.85),       # 排気口（熱で焼けた金属）
    "FP_WingEdge": Mspec(hexcol("#CDD2D7"), 0.30, 0.55),      # 主翼の前の縁（磨いた金属の帯）
    "FP_Slime": Mspec(hexcol("#6CCB86"), 0.35, emit=0.25),    # 編隊灯（薄い緑の帯の灯）
    "FP_WindowDark": Mspec(hexcol("#1E2A38"), 0.08),          # 小さな窓（中の見えない暗いガラス）
    "FP_Lens": Mspec(hexcol("#E8EEF2"), 0.06, 0.3),           # 着陸灯などのレンズ
    "FP_KnobBlack": Mspec(hexcol("#17191C"), 0.42),           # 操縦席のつまみ・計器の縁（黒い樹脂）
    "FP_Glareshield": Mspec(hexcol("#1C1E21"), 0.95),         # 計器盤の日よけ（黒い布張り）
}


def make_materials():
    mats = {}
    for name, spec in MATERIAL_SPECS.items():
        rgba = spec["color"]
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.name = "Principled BSDF"
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = spec["rough"]
        bsdf.inputs["Metallic"].default_value = spec["metal"]
        if spec["emit"]:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = spec["emit"]
        if spec["alpha"] < 1.0:
            bsdf.inputs["Alpha"].default_value = spec["alpha"]
            mat.surface_render_method = "BLENDED"
        mat.use_backface_culling = not spec["double"]
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


def set_pivot(obj, pivot_b: Vector):
    """メッシュをそのままの位置に保ったまま、原点を pivot_b（Blender の座標）へ（向きは世界のまま）。"""
    m = Matrix.Translation(pivot_b)
    obj.data.transform(m.inverted())
    obj.data.update()
    obj.matrix_basis = m
