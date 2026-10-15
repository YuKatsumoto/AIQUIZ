"""乗り込めるヘリ（helicopter_boarding）のビルダーの共通部分：数値の読み込み、座標の変換、メッシュの組み立て、材質。

数値は source/heli_pilot_spec.json から読む（設計図 artifacts/heli_blueprint の make_blueprint.py が書き出す写し。
artifacts/ は git の管理外なので、写しをこの素材のフォルダに置く）。設計図を直したら
`python artifacts/heli_blueprint/make_blueprint.py spec` で JSON を書き直してから、このビルダーを流す。

座標：形は Godot の座標で書く（x 右、y 上、機首 -z、m）。y は地面（スキッドの下面）基準の値で書き、
P() で GLB の原点（ローター軸 × 地面から ORIGIN_Y）基準の Blender 座標へ変える：Godot (x, y, z) → Blender (x, -z, y - ORIGIN_Y)。
glTF の書き出し（export_yup）で Blender (x, y, z) → glTF (x, z, -y) になり、Godot の座標に戻る。

メッシュ（GMesh）は面ごとに材質・なめらかさ・溶接の名前と、角ごとの UV・頂点色・法線を持つ。
なめらかにする面は必ず溶接の名前を付ける（付けないと頂点を共有せず、陰影がカクカクになる。smooth_unwelded() で数える）。
"""
from __future__ import annotations

import itertools
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
TEXTURES = SRC / "textures"
BACKUPS = HERE / "backups"
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


def G(v_b):
    """Blender の座標 → Godot の座標（地面基準）。P() の逆。"""
    return Vector((v_b[0], v_b[2] + ORIGIN_Y, -v_b[1]))


def GD(v_b):
    """Blender の向き → Godot の向き。D() の逆。"""
    return Vector((v_b[0], v_b[2], -v_b[1]))


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


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


BP = SPEC["body_profile"]


def body_params(z):
    """z での胴体（外形）の断面：上端・下端・いちばん太い高さ・半幅・丸み。"""
    t = min(max((z - BP["z"][0]) / (-1.60 - BP["z"][0]), 0.0), 1.0)
    return dict(top=pchip(BP["z"], BP["top"], z), bottom=pchip(BP["z"], BP["bottom"], z), belt=pchip(BP["z"], BP["belt"], z),
                a=pchip(BP["z"], BP["half_width"], z), n_top=BP["n_top"][0] + (BP["n_top"][1] - BP["n_top"][0]) * t, n_bot=BP["n_bottom"])


def section_point(p, theta, wall=0.0):
    """断面の上の点（θ は +x から反時計回り）。wall だけ内側の面（内張り）。負の wall は外へ浮かす。"""
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


def belly_y(z, x=0.0):
    """胴体の下面の高さ（外形、x での値）。"""
    p = body_params(z)
    r = abs(x) / p["a"]
    if r >= 1:
        return None
    return p["belt"] - (p["belt"] - p["bottom"]) * (1 - r ** p["n_bot"]) ** (1 / p["n_bot"])


# ---------------------------------------------------------------- メッシュの組み立て（Godot の座標で書く）

WHITE = (1.0, 1.0, 1.0, 1.0)
_WELD_SEQ = itertools.count()
DEFAULT_UV: dict[str, tuple] = {}       # 材質 → UV を渡さない面の UV（アトラスの透明・不透明のマス。既定は (0.5, 0.5)）
ANALYTIC_NORMALS = False                # True にすると、GMesh の nor（角ごとの法線）をカスタム法線として書く
VALIDATE_LOG: dict[str, bool] = {}      # 部品名 → me.validate() が直したか（直したら面が黙って消えている）


def new_weld(tag):
    """溶接（同じ位置の点を 1 つにする）の名前。ビルドごとにモジュールを読み直すので、番号は毎回同じになる。"""
    return f"{tag}#{next(_WELD_SEQ)}"


def frame_from(normal, along=None):
    """normal（Godot）に直交する 2 本 (u, w)。along を渡すと u をその向きにそろえる。"""
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


def _newell(pts):
    """多角形の法線（Newell の方法）。先頭の点が重なっていても向きが出る。"""
    n = Vector((0.0, 0.0, 0.0))
    k = len(pts)
    for i in range(k):
        a, b = pts[i], pts[(i + 1) % k]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


def _uniform(a):
    return a is not None and len(a) > 0 and isinstance(a[0], (int, float))


def _per_corner(a, keep):
    """面の属性：None、全部の角に同じ値（数の並び）、または角ごとの並び。残った角（keep）だけ取る。"""
    if a is None:
        return None
    if _uniform(a):
        return tuple(tuple(a) for _ in keep)
    return tuple(tuple(a[k]) for k in keep)


class GMesh:
    """面ごとに材質キーを持つメッシュ。点は Godot の座標（地面基準）で渡し、Blender の座標で持つ。
    面ごとに、角の UV・頂点色・法線（なければ None）と、溶接の名前を持つ。"""

    def __init__(self):
        self.v: list[Vector] = []
        self.f: list[tuple] = []
        self.mat: list[str] = []
        self.smooth: list[bool] = []
        self.uv: list = []
        self.col: list = []
        self.nor: list = []
        self.weld_of: list = []
        self._weld: dict = {}
        self.weld_groups: dict[str, int] = {}   # 溶接の名前 → 予定の頂点の数（sweep / lathe_axis が書く）
        self.rejected = 0                       # 同じ点を 2 度通る面（溶接で起きる）を捨てた数

    def face(self, pts, mat, smooth=False, convert=True, weld=None, uv=None, col=None, nor=None):
        """weld に名前を渡すと、同じ名前の面どうしで同じ位置の点を 1 つにする（なめらかな陰影がつながる）。
        uv は角ごとの (u, v)、col は 1 色（RGBA）か角ごとの色、nor は角ごとの法線（Godot の向き）。"""
        idx, keep = [], []
        for k, p in enumerate(pts):
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
                keep.append(k)
        if len(idx) > 1 and idx[0] == idx[-1]:
            idx.pop()
            keep.pop()
        if len(set(idx)) < 3:
            return
        if len(set(idx)) != len(idx):
            self.rejected += 1
            return
        self.f.append(tuple(idx))
        self.mat.append(mat)
        self.smooth.append(smooth)
        self.uv.append(_per_corner(uv, keep))
        self.col.append(_per_corner(col, keep))
        n = _per_corner(nor, keep)
        self.nor.append(tuple(tuple((D(q) if convert else Vector(q)).normalized()) for q in n) if n is not None else None)
        self.weld_of.append(weld)

    def box(self, center, size, mat, rot: Matrix | None = None, faces="all", chamfer=0.0, col=None):
        """Godot の座標の箱。rot は Godot の座標での回転（3x3）。chamfer > 0 なら角を落とす（8 角を面取り）。"""
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
                    self.face([p[i] for i in idx], mat, col=col)
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
                self._oriented(pts, rot @ n, mat, col=col)
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
                    self._oriented([pts[0], pts[1], pts[3], pts[2]], rot @ n, mat, col=col)
        for sx_ in (-1, 1):
            for sy_ in (-1, 1):
                for sz_ in (-1, 1):
                    pts = [q(sx_ * sx, sy_ * (sy - e), sz_ * (sz - e)), q(sx_ * (sx - e), sy_ * sy, sz_ * (sz - e)), q(sx_ * (sx - e), sy_ * (sy - e), sz_ * sz)]
                    self._oriented(pts, rot @ Vector((sx_, sy_, sz_)), mat, col=col)

    def box_between(self, a, b, w, h, mat, up=(0, 1, 0), chamfer=0.0, col=None):
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
        self.box(tuple((a + b) / 2), (w, h, d.length), mat, rot=Matrix((ex, ey, ez)).transposed(), chamfer=chamfer, col=col)

    def _oriented(self, pts, normal_g, mat, smooth=False, weld=None, uv=None, col=None, nor=None):
        """面の向きを normal_g（Godot）にそろえて足す。属性の並びも一緒に裏返す。"""
        if _newell([Vector(p) for p in pts]).dot(Vector(normal_g)) < 0:
            pts = list(reversed(pts))
            uv = list(reversed(uv)) if uv is not None else None
            nor = list(reversed(nor)) if nor is not None else None
            if col is not None and not _uniform(col):
                col = list(reversed(col))
        self.face(pts, mat, smooth, weld=weld, uv=uv, col=col, nor=nor)

    def sweep(self, pts, radii, mat, n=10, caps=("flat", "flat"), smooth=True, weld=None, crease_deg=60.0, col=None):
        """折れ線にそった 1 本の管。つなぎ目の輪は両側の筒の切り口（斜めに切る）で、ねじれない（平行移動の枠）。
        折れが crease_deg を超える所は陰影を分ける（溶接の名前を変える）。caps："flat"（溶接しない平らなふた）/
        "round"（丸いふた）/ None（開けたまま）。返り値は (輪の並び, 枠の並び)。"""
        P_, R_ = [], []
        for p, r in zip(pts, radii):
            v = Vector(p)
            if P_ and (v - P_[-1]).length < 1e-9:
                continue
            P_.append(v)
            R_.append(float(r))
        m = len(P_)
        if m < 2:
            return None
        d = [(P_[i + 1] - P_[i]).normalized() for i in range(m - 1)]
        up = Vector((0, 1, 0)) if abs(d[0].y) < 0.9 else Vector((1, 0, 0))
        u = d[0].cross(up).normalized()
        rings, frames = [], []
        for i in range(m):
            if i == 0:
                t = d[0]
            elif i == m - 1:
                t = d[-1]
            else:
                t = d[i - 1] + d[i]
                t = t.normalized() if t.length > 1e-9 else d[i]
            if i > 0:
                u = u - t * u.dot(t)
                u.normalize()
            w = t.cross(u)
            mitre = None
            if 0 < i < m - 1:
                phi = math.acos(max(-1.0, min(1.0, d[i - 1].dot(d[i]))))
                if phi > 1e-4:
                    mitre = ((d[i] - d[i - 1]).normalized(), 1.0 / math.cos(phi / 2))
            ring = []
            for k in range(n):
                a = 2 * math.pi * k / n
                v = R_[i] * (math.cos(a) * u + math.sin(a) * w)
                if mitre is not None:
                    b, sc = mitre
                    v = v + (sc - 1.0) * v.dot(b) * b
                ring.append(P_[i] + v)
            rings.append(ring)
            frames.append((t, u.copy(), w))
        base = weld or new_weld("sweep")
        sec = 0
        sections = {0: set()}
        for i in range(m - 1):
            if i > 0:
                phi = math.acos(max(-1.0, min(1.0, d[i - 1].dot(d[i]))))
                if phi > math.radians(crease_deg):
                    sec += 1
                    sections[sec] = set()
            sections[sec].update((i, i + 1))
            wname = f"{base}:{sec}" if smooth else None
            ra, rb = rings[i], rings[i + 1]
            axis_mid = (P_[i] + P_[i + 1]) / 2
            for k in range(n):
                j = (k + 1) % n
                quad = [ra[k], ra[j], rb[j], rb[k]]
                mid = (quad[0] + quad[1] + quad[2] + quad[3]) / 4
                self._oriented([tuple(q) for q in quad], tuple(mid - axis_mid), mat, smooth, weld=wname, col=col)
        extra = {s: 0 for s in sections}
        for end, kind in ((0, caps[0]), (m - 1, caps[1])):
            if kind is None:
                continue
            ring = rings[end]
            c = P_[end]
            t = -d[0] if end == 0 else d[-1]
            if kind == "flat" or R_[end] < 1e-9:
                if R_[end] >= 1e-9:
                    self._oriented([tuple(p) for p in ring], tuple(t), mat, col=col)
                continue
            s_end = 0 if end == 0 else sec
            wname = f"{base}:{s_end}" if smooth else None
            prev = ring
            for ang in (45.0, 75.0):
                a = math.radians(ang)
                cur = [c + (p - c) * math.cos(a) + t * R_[end] * math.sin(a) for p in ring]
                for k in range(n):
                    j = (k + 1) % n
                    quad = [prev[k], prev[j], cur[j], cur[k]]
                    mid = (quad[0] + quad[1] + quad[2] + quad[3]) / 4
                    self._oriented([tuple(q) for q in quad], tuple(mid - c), mat, smooth, weld=wname, col=col)
                prev = cur
            pole = c + t * R_[end]
            for k in range(n):
                j = (k + 1) % n
                tri = [prev[k], prev[j], pole]
                self._oriented([tuple(q) for q in tri], tuple((tri[0] + tri[1] + tri[2]) / 3 - c), mat, smooth, weld=wname, col=col)
            extra[s_end] += 2 * n + 1
        if smooth:
            for s, idxs in sections.items():
                self.weld_groups[f"{base}:{s}"] = sum(1 if R_[i] < 1e-9 else n for i in idxs) + extra[s]
        return rings, frames

    def tube(self, a, b, r, mat, n=10, caps=True, r1=None, smooth=True, weld=None, col=None):
        if (Vector(b) - Vector(a)).length < 1e-9:
            return
        cap = "flat" if caps else None
        self.sweep([a, b], [r, r if r1 is None else r1], mat, n=n, caps=(cap, cap), smooth=smooth, weld=weld or new_weld("tube"), col=col)

    def polyline_tube(self, pts, r, mat, n=10, caps=True, weld=None, col=None):
        """折れ線にそった 1 本の管（端だけふさぐ）。"""
        cap = "flat" if caps else None
        self.sweep(pts, [r] * len(pts), mat, n=n, caps=(cap, cap), weld=weld or new_weld("poly"), col=col)

    def lathe_axis(self, origin, axis, stations, mat, ref=None, n=16, arc=None, outward=True, smooth=True, weld=None,
                   crease_deg=35.0, mats=None, cols=None, cap0=None, cap1=None):
        """軸にそった回転体。stations は [(軸の上の距離 s, 半径 r)]。ref は角度 0 の向き。arc=(φ0, φ1) で開いた回転体。
        outward=False で内向きの面（筒の内側）。輪郭の折れが crease_deg を超える所は陰影を分ける。
        mats は区間ごとの材質、cols は輪ごとの頂点色。cap0 / cap1 = "flat" で端をふさぐ（閉じた回転体だけ）。"""
        o = Vector(origin)
        ax = Vector(axis).normalized()
        if ref is None:
            ref = (1, 0, 0) if abs(ax.x) < 0.9 else (0, 1, 0)
        e1 = Vector(ref)
        e1 = (e1 - ax * e1.dot(ax)).normalized()
        e2 = ax.cross(e1)
        closed = arc is None
        if closed:
            step = 2 * math.pi / n
            phis = [step * k for k in range(n)]
        else:
            step = (arc[1] - arc[0]) / n
            phis = [arc[0] + step * k for k in range(n + 1)]
        nr = len(phis)
        rings = [[o + ax * s + r * (math.cos(p) * e1 + math.sin(p) * e2) for p in phis] for s, r in stations]
        base = weld or new_weld("lathe")
        sec = 0
        sections = {0: set()}
        prev_a = None
        for i in range(len(stations) - 1):
            (s0, r0), (s1, r1) = stations[i], stations[i + 1]
            a_i = math.atan2(r1 - r0, s1 - s0)
            if prev_a is not None and abs(a_i - prev_a) > math.radians(crease_deg):
                sec += 1
                sections[sec] = set()
            prev_a = a_i
            sections[sec].update((i, i + 1))
            wname = f"{base}:{sec}" if smooth else None
            mat_i = mats[i] if mats else mat
            ra, rb = rings[i], rings[i + 1]
            for k in range(n):
                j = (k + 1) % nr if closed else k + 1
                pm = phis[k] + step / 2
                er = math.cos(pm) * e1 + math.sin(pm) * e2
                hint = er * (s1 - s0) - ax * (r1 - r0)
                if hint.length < 1e-9:
                    hint = er
                if not outward:
                    hint = -hint
                fc = None if cols is None else [cols[i], cols[i], cols[i + 1], cols[i + 1]]
                self._oriented([tuple(ra[k]), tuple(ra[j]), tuple(rb[j]), tuple(rb[k])], tuple(hint), mat_i, smooth, weld=wname, col=fc)
        if closed:
            for idx, kind in ((0, cap0), (len(stations) - 1, cap1)):
                if kind == "flat" and stations[idx][1] > 1e-9:
                    out = -ax if idx == 0 else ax
                    if not outward:
                        out = -out
                    cap_mat = mat if not mats else mats[0 if idx == 0 else -1]
                    fc = None if cols is None else cols[idx]
                    self._oriented([tuple(p) for p in rings[idx]], tuple(out), cap_mat, col=fc)
        if smooth:
            for s, idxs in sections.items():
                self.weld_groups[f"{base}:{s}"] = sum(1 if stations[i][1] < 1e-9 else nr for i in idxs)
        return rings

    def loft(self, rings, mat, closed=True, smooth=True, weld=None, hint_fn=None, mats=None, cols=None):
        """輪（同じ点の数）の並びを張る。hint_fn(i, k) で面の外向きの手がかり（なければ輪の中心から外）。
        mats(i, k) / cols[i][k] で面ごとの材質・角ごとの色。"""
        base = weld or new_weld("loft")
        wname = base if smooth else None
        n = len(rings[0])
        for i in range(len(rings) - 1):
            ra, rb = rings[i], rings[i + 1]
            ca = sum((Vector(p) for p in ra), Vector()) / n
            cb = sum((Vector(p) for p in rb), Vector()) / n
            for k in range(n if closed else n - 1):
                j = (k + 1) % n
                quad = [ra[k], ra[j], rb[j], rb[k]]
                mid = sum((Vector(p) for p in quad), Vector()) / 4
                hint = hint_fn(i, k) if hint_fn else mid - (ca + cb) / 2
                fc = None if cols is None else [cols[i][k], cols[i][j], cols[i + 1][j], cols[i + 1][k]]
                self._oriented([tuple(q) for q in quad], tuple(hint), mats(i, k) if mats else mat, smooth, weld=wname, col=fc)
        if smooth:
            self.weld_groups[base] = n * len(rings)

    def stud(self, center, normal, r, h, mat, n=6, col=None):
        """小さな頭（リベット・ボルト）：n 角の台形の側面（なめらか）＋平らな頭。center は面の上、normal へ h だけ出る。"""
        c = Vector(center)
        nn = Vector(normal).normalized()
        self.lathe_axis(c, nn, [(-0.002, r), (h, r * 0.55)], mat, n=n, cols=None if col is None else [col] * 2, cap1="flat")

    def prism_y(self, poly_xz, y0, y1, mat, col=None):
        """x-z 平面の凸な多角形を y0〜y1 に押し出す（上下はふさぐ）。"""
        pts = list(poly_xz)
        n = len(pts)
        cx = sum(p[0] for p in pts) / n
        cz = sum(p[1] for p in pts) / n
        for i in range(n):
            (xa, za), (xb, zb) = pts[i], pts[(i + 1) % n]
            self._oriented([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], ((xa + xb) / 2 - cx, 0, (za + zb) / 2 - cz), mat, col=col)
        self._oriented([(x, y1, z) for x, z in pts], (0, 1, 0), mat, col=col)
        self._oriented([(x, y0, z) for x, z in pts], (0, -1, 0), mat, col=col)

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
        self.uv.extend(other.uv)
        self.col.extend(other.col)
        self.nor.extend(other.nor)
        self.weld_of.extend(other.weld_of)
        for k, c in other.weld_groups.items():
            self.weld_groups[k] = self.weld_groups.get(k, 0) + c
        self.rejected += other.rejected

    def triangles(self):
        return sum(len(f) - 2 for f in self.f)

    def smooth_unwelded(self):
        """なめらかにしたいのに溶接していない面（頂点を共有しないので、陰影がカクカクになる）の数。"""
        return sum(1 for s, w in zip(self.smooth, self.weld_of) if s and w is None)

    def weld_mismatch(self):
        """予定の頂点の数と、溶接でできた頂点の数が違う溶接の名前（丸めのずれで点が割れると出る）。"""
        got: dict[str, int] = {}
        for key in self._weld:
            got[key[0]] = got.get(key[0], 0) + 1
        return {k: (want, got.get(k, 0)) for k, want in self.weld_groups.items() if got.get(k, 0) != want}


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
    index_of = {k: i for i, k in enumerate(keys)}
    cols, uvs = [], []
    for f, key, fc, fu in zip(mesh.f, mesh.mat, mesh.col, mesh.uv):
        du = DEFAULT_UV.get(key, (0.5, 0.5))
        for k in range(len(f)):
            cols.extend(fc[k] if fc is not None else WHITE)
            uvs.extend(fu[k] if fu is not None else du)
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    col.data.foreach_set("color", cols)
    uv = me.uv_layers.new(name="UVMap")
    uv.data.foreach_set("uv", uvs)
    me.polygons.foreach_set("material_index", [index_of[k] for k in mesh.mat])
    me.polygons.foreach_set("use_smooth", [bool(s) for s in mesh.smooth])
    me.color_attributes.active_color = col
    changed = me.validate(clean_customdata=False)
    VALIDATE_LOG[name] = bool(changed)
    if ANALYTIC_NORMALS and not changed and any(n is not None for n in mesh.nor):
        normals = []
        for f, fn in zip(mesh.f, mesh.nor):
            for k in range(len(f)):
                normals.append(tuple(fn[k]) if fn is not None else (0.0, 0.0, 0.0))
        me.normals_split_custom_set(normals)
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


def M(color, rough, metal=0.0, emit=0.0, double=False, blend=False, coat=0.0, coat_rough=0.1, image=False, alpha_from_image=False):
    return {"color": color, "rough": rough, "metal": metal, "emit": emit, "double": double, "blend": blend,
            "coat": coat, "coat_rough": coat_rough, "image": image, "alpha_from_image": alpha_from_image}


NAVY_HEX = "#1D2F5C"       # 帯より下・尾翼の濃紺（世界の看板と同じ。Godot の BRAND_NAVY と同じ値）
LIVERY = {"NAVY": NAVY_HEX}
# 頂点色で塗る色（材質を増やさない）。線形の RGBA
HAZARD_RED = hexcol("#D8352B")
HAZARD_YELLOW = hexcol("#F2C230")
HAZARD_BLACK = hexcol("#22252A")
HEAT_BLUE = hexcol("#5B5FA8")
HEAT_BRONZE = hexcol("#9A6A3C")
HEAT_STRAW = hexcol("#D9C38E")
NAVY = hexcol(NAVY_HEX)
SKY = hexcol("#33A6E6")
HATENA_ORANGE = hexcol("#FFAD3F")

MATERIAL_SPECS = {
    "BodyPaint": M(lin(SPEC["colors"]["body_paint"]), 0.32, coat=0.5, coat_rough=0.08),
    "BodyAccent": M(hexcol(NAVY_HEX), 0.32, coat=0.5, coat_rough=0.08),      # 色替えしない濃紺
    "Trim": M(hexcol("#F4F3EE"), 0.36, coat=0.3),
    "Windows": M(lin(SPEC["colors"]["glass"], 0.30), 0.06, 0.08, double=True, blend=True),
    "Charcoal": M(hexcol("#2B3038"), 0.62, 0.10),
    "Rubber": M(hexcol("#1C1E22"), 0.85),
    "Metal": M(hexcol("#9EA6B0"), 0.30, 0.85),
    "Interior": M(hexcol("#A7AEB8"), 0.75),
    "Floor": M(hexcol("#5E6670"), 0.85),
    "SeatFabric": M(hexcol("#3A4C70"), 0.9),
    "DashDark": M(hexcol("#33373F"), 0.70),
    "ScreenGlow": M(hexcol("#5ED8F2"), 0.3, emit=2.2),
    "NavRed": M(hexcol("#FF3A2E"), 0.3, emit=3.0),
    "NavGreen": M(hexcol("#33E06A"), 0.3, emit=3.0),
    "LampWhite": M(hexcol("#FFF6DC"), 0.3, emit=3.0),
    "DropHatchInterior": M(hexcol("#5A5650"), 0.8),
    "JetGlow": M(hexcol("#FF9A3C"), 0.3, emit=4.0),   # ジェットの噴射口の奥（Godot が強さを変える）
}


def make_materials(atlas=None):
    """MATERIAL_SPECS の材質を作り直す。image の材質は atlas（bpy の Image）を貼る（パスからは読まない）。"""
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
        if spec["coat"] > 0:
            for key, val in (("Coat Weight", spec["coat"]), ("Coat Roughness", spec["coat_rough"])):
                sock = bsdf.inputs.get(key)
                if sock is not None:
                    sock.default_value = val
        if spec["image"] and atlas is not None:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.name = "Atlas"
            tex.image = atlas
            tex.interpolation = "Linear"
            tex.extension = "EXTEND"
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            if spec["emit"]:
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            if spec["alpha_from_image"]:
                nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if spec["emit"]:
            if not (spec["image"] and atlas is not None):
                bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = spec["emit"]
        if spec["blend"]:
            if not spec["alpha_from_image"]:
                bsdf.inputs["Alpha"].default_value = rgba[3]
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


def set_pivot(obj, pivot_b: Vector, rot_b: Matrix | None = None):
    """メッシュをそのままの位置に保ったまま、原点を pivot_b（Blender の座標）へ、向きを rot_b（3x3）へ。"""
    m = Matrix.Translation(pivot_b) @ (rot_b.to_4x4() if rot_b is not None else Matrix.Identity(4))
    obj.data.transform(m.inverted())
    obj.data.update()
    obj.matrix_basis = m
