"""ママチャリ（シークレットスキンの乗り物）をライブの Blender で組み立てる。

使い方（Blender の Python から。ヘッドレスでは使わない）:
    exec(open(r"<このファイル>", encoding="utf-8").read())
    result = build()            # コレクション MAMACHARI を作り直す（何度流しても同じ結果）
    export_glb(r"<出力.glb>")   # Godot 用に書き出す

SCENE PASSPORT（要点）
- intent: ゲーム用の乗り物アセット（主役の小道具）。fidelity = detailed。
- units: メートル。Blender は Z が上。自転車の前 = -Y、乗り手の左 = +X。
  glTF（Y 上）へ書き出すと 前 = +Z になり、Godot の箱人形（つま先が +Z）と向きがそろう。
- 原点: BB（クランク軸）の真下の地面。
- 寸法（実寸）: 26インチ（タイヤ外径 0.664）、軸距 1.10、BB 高 0.275、ヘッド角・シート角 68°、
  フォークオフセット 0.055、クランク長 0.165、サドル上面 約0.84（いちばん下げた状態）、グリップ高 約1.03。
- 動く部品は別オブジェクト（原点＝回転の中心）:
    Steer（原点＝フォーククラウン、ローカル Z＝ステア軸）
      ├ FrontWheel（前輪の軸） ├ FenderFront ├ Basket ├ BrakeLeverL / BrakeLeverR（レバーの支点）
    RearWheel（後輪の軸）  Crank（BB） ├ PedalL / PedalR（ペダル軸）
    Stand（後輪の軸。モデルの姿勢は「上げた」状態）  Saddle（シートポストの頭）
    Frame / FenderRear / ChainCase は動かない（凹みを付けるので別オブジェクト）。
- dynamic: いいえ（ゲーム側のコードで動かす。Blender ではアニメーションを付けない）。
- LOOK: テクスチャなしの PBR（glTF でそのまま届く値だけ）。フレームはワインレッドの塗装、
  泥よけ・リムはステンレス、かごは亜鉛めっきの針金、サドル・グリップ・タイヤは黒。
- ACCEPTANCE: 寸法が上の値と合う／部品が浮かない・めり込まない／横から見てママチャリと分かる／
  三角形 9万以下／材質スロットが全部つながっている。
"""

import bpy
import bmesh
from math import sin, cos, pi, radians, atan2, acos, sqrt
from mathutils import Vector, Matrix

COLL_NAME = "MAMACHARI"
PREVIEW_NAME = "MAMACHARI_PREVIEW"
ROOT_NAME = "Mamachari"

# ---------------------------------------------------------------------------
# 寸法（メートル）
# ---------------------------------------------------------------------------
R_TIRE = 0.332          # タイヤの外半径（26 x 1-3/8）
TIRE_R = 0.0185         # タイヤ断面の半径
RC_TIRE = R_TIRE - TIRE_R
R_FENDER = 0.3525       # 泥よけの外半径
WB = 1.10               # 軸距
BB_F, BB_U = 0.455, 0.275
HEAD_DEG = 68.0
SEAT_DEG = 68.0
RAKE = 0.055
FORK_LEN = 0.385
CRANK_LEN = 0.165
# サドルを下げる量（シートチューブに沿って）。いちばん下まで下げた状態（ばねが荷台のすぐ上）。
# 大柄な箱人形の足が下死点のペダルに届くように低くしてある。
SADDLE_DROP = 0.06
SEAT_POST_TOP = 0.60 - SADDLE_DROP

X = Vector((1.0, 0.0, 0.0))     # 乗り手の左
FWD = Vector((0.0, -1.0, 0.0))  # 前
UP = Vector((0.0, 0.0, 1.0))


def P(f, u, s=0.0):
    """自転車の座標（前 f・上 u・左 s）→ Blender の座標。f は後輪の軸を 0 とする。"""
    return Vector((s, -(f - BB_F), u))


US = (-cos(radians(HEAD_DEG)), sin(radians(HEAD_DEG)))   # ステア軸（上向き）の (f, u)
NS = (sin(radians(HEAD_DEG)), cos(radians(HEAD_DEG)))    # ステア軸に直角で前向き
QF, QU = WB - RAKE * NS[0], R_TIRE - RAKE * NS[1]
CF, CU = QF + FORK_LEN * US[0], QU + FORK_LEN * US[1]    # フォーククラウン


def SA(a, b=0.0, s=0.0):
    """ステア軸に沿った座標。a = クラウンから軸に沿って上、b = 軸に直角で前。"""
    return P(CF + a * US[0] + b * NS[0], CU + a * US[1] + b * NS[1], s)


ST = (-cos(radians(SEAT_DEG)), sin(radians(SEAT_DEG)))


def SEAT(d, off=0.0, s=0.0):
    """シートチューブに沿った座標。d = BB から上、off = 直角で前。"""
    return P(BB_F + d * ST[0] + off * ST[1], BB_U + d * ST[1] - off * ST[0], s)


def WP(axle_f, deg, r, s=0.0):
    """車輪のまわりの点。deg は前向き水平を 0、上を 90 とする。"""
    a = radians(deg)
    return P(axle_f + r * cos(a), R_TIRE + r * sin(a), s)


# ---------------------------------------------------------------------------
# 材質（テクスチャなし。glTF でそのまま届く値だけを使う）
# ---------------------------------------------------------------------------
MATERIALS = {
    # name: (base color, metallic, roughness, coat)
    "PAINT": ((0.30, 0.022, 0.040), 0.25, 0.32, 0.8),
    "PAINT_WHITE": ((0.86, 0.86, 0.83), 0.0, 0.35, 0.5),
    "CHROME": ((0.86, 0.87, 0.89), 1.0, 0.14, 0.0),
    "STAINLESS": ((0.74, 0.75, 0.77), 1.0, 0.30, 0.0),
    "ZINC": ((0.62, 0.63, 0.65), 1.0, 0.42, 0.0),
    "BRASS": ((0.85, 0.62, 0.22), 1.0, 0.25, 0.0),
    "RUBBER_TIRE": ((0.022, 0.022, 0.024), 0.0, 0.86, 0.0),
    "RUBBER_GRIP": ((0.035, 0.035, 0.037), 0.0, 0.70, 0.0),
    "BLACK_PLASTIC": ((0.030, 0.030, 0.034), 0.0, 0.42, 0.0),
    "SADDLE": ((0.045, 0.040, 0.038), 0.0, 0.50, 0.0),
    "REFLECTOR_RED": ((0.72, 0.015, 0.015), 0.0, 0.12, 0.0),
    "REFLECTOR_ORANGE": ((0.95, 0.33, 0.02), 0.0, 0.12, 0.0),
    "LENS": ((0.92, 0.92, 0.86), 0.0, 0.05, 0.0),
    "STICKER": ((0.95, 0.78, 0.08), 0.0, 0.55, 0.0),
}


def get_material(name):
    color, metallic, roughness, coat = MATERIALS[name]
    mat_name = "MMC_" + name
    mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = coat
            bsdf.inputs["Coat Roughness"].default_value = 0.08
    mat.diffuse_color = (*color, 1.0)
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


# ---------------------------------------------------------------------------
# 形を作る道具
# ---------------------------------------------------------------------------
def spline(ctrl, per=6):
    """Catmull-Rom で制御点をなめらかにつなぐ。"""
    ctrl = [Vector(c) for c in ctrl]
    c = [ctrl[0]] + ctrl + [ctrl[-1]]
    pts = []
    for i in range(1, len(c) - 2):
        p0, p1, p2, p3 = c[i - 1], c[i], c[i + 1], c[i + 2]
        for k in range(per):
            t = k / per
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    pts.append(ctrl[-1])
    return pts


def rrect(center, au, av, hu, hv, rad, k=4):
    """角の丸い長方形の輪（閉じた点の列）。"""
    pts = []
    for su, sv, a0 in ((1, 1, 0.0), (-1, 1, pi / 2), (-1, -1, pi), (1, -1, 3 * pi / 2)):
        corner = center + au * (su * (hu - rad)) + av * (sv * (hv - rad))
        for i in range(k + 1):
            a = a0 + (pi / 2) * i / k
            pts.append(corner + au * (rad * cos(a)) + av * (rad * sin(a)))
    return pts


def resample_closed(pts, n):
    """閉じた点の列を、長さが等しい n 点に取り直す。"""
    loop = pts + [pts[0]]
    seg = [(loop[i + 1] - loop[i]).length for i in range(len(pts))]
    total = sum(seg)
    out = []
    for k in range(n):
        target = total * k / n
        acc = 0.0
        for i, length in enumerate(seg):
            if acc + length >= target or i == len(seg) - 1:
                t = 0.0 if length < 1e-9 else (target - acc) / length
                out.append(loop[i].lerp(loop[i + 1], min(max(t, 0.0), 1.0)))
                break
            acc += length
    return out


def hull2(a, ra, b, rb, na=20, nb=10):
    """2つの円を包む輪郭（(f, u) の列）。点の数は半径によらず同じ。"""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = sqrt(dx * dx + dy * dy)
    phi = atan2(dy, dx)
    al = acos(max(-1.0, min(1.0, (ra - rb) / length)))
    pts = []
    for i in range(na + 1):
        t = phi + al + (2 * pi - 2 * al) * i / na
        pts.append((a[0] + ra * cos(t), a[1] + ra * sin(t)))
    for i in range(nb + 1):
        t = phi - al + (2 * al) * i / nb
        pts.append((b[0] + rb * cos(t), b[1] + rb * sin(t)))
    return pts


def _frames(pts, closed):
    n = len(pts)
    tangents = []
    for i in range(n):
        if closed:
            t = (pts[(i + 1) % n] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        elif i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        tangents.append(t.normalized())
    t0 = tangents[0]
    ref = X if abs(t0.x) < 0.9 else UP
    normal = (ref - t0 * ref.dot(t0)).normalized()
    frames = []
    for t in tangents:
        normal = normal - t * normal.dot(t)
        if normal.length < 1e-8:
            ref = X if abs(t.x) < 0.9 else UP
            normal = ref - t * ref.dot(t)
        normal.normalize()
        frames.append((normal.copy(), t.cross(normal)))
    return frames


class Part:
    """1つのオブジェクトになる形の集まり。pivot がオブジェクトの原点と向き。"""

    def __init__(self, name, pivot=None):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.pivot = pivot.copy() if pivot is not None else Matrix.Identity(4)
        self.flat_faces = []

    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def loft(self, rings, mat, close_ring=True, wrap=False, cap0=False, cap1=False, flat=False):
        bm = self.bm
        index = self.mi(mat)
        verts = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(verts)
        m = len(verts[0])
        faces = []
        for i in range(n if wrap else n - 1):
            a, b = verts[i], verts[(i + 1) % n]
            for j in range(m if close_ring else m - 1):
                j2 = (j + 1) % m
                faces.append(bm.faces.new((a[j], a[j2], b[j2], b[j])))
        if cap0 and not wrap:
            faces.append(bm.faces.new(verts[0]))
        if cap1 and not wrap:
            faces.append(bm.faces.new(list(reversed(verts[-1]))))
        for face in faces:
            face.material_index = index
        if flat:
            self.flat_faces.extend(faces)

    def tube(self, pts, r, mat, segs=8, caps=True, closed=False, flat=False):
        """点の列に沿って円を掃く。r は 数・(始, 終)・点ごとの列 のどれか。"""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        if isinstance(r, (int, float)):
            radii = [float(r)] * n
        elif len(r) == n and n != 2:
            radii = [float(v) for v in r]
        else:
            lengths = [0.0]
            for i in range(1, n):
                lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
            total = lengths[-1] or 1.0
            radii = [r[0] + (r[1] - r[0]) * (v / total) for v in lengths]
        frames = _frames(pts, closed)
        rings = []
        for p, (normal, binormal), radius in zip(pts, frames, radii):
            rings.append([p + (normal * cos(2 * pi * j / segs) + binormal * sin(2 * pi * j / segs)) * radius
                          for j in range(segs)])
        self.loft(rings, mat, True, closed, caps and not closed, caps and not closed, flat)

    def lathe(self, prof, origin, axis, ref, mat, segs=32, a0=0.0, a1=2 * pi, ref2=None,
              closed=False, caps=False, flat=False):
        """(半径, 軸方向) の断面を軸のまわりに回す。"""
        axis = axis.normalized()
        ref = ref.normalized()
        if ref2 is None:
            ref2 = axis.cross(ref)
        full = abs((a1 - a0) - 2 * pi) < 1e-6
        rings = []
        for i in range(segs if full else segs + 1):
            a = a0 + (a1 - a0) * i / segs
            d = ref * cos(a) + ref2 * sin(a)
            rings.append([origin + axis * ax + d * rad for rad, ax in prof])
        self.loft(rings, mat, closed, full, caps and not full, caps and not full, flat)

    def box(self, center, ax, ay, az, sx, sy, sz, mat):
        ax, ay, az = ax.normalized() * (sx / 2), ay.normalized() * (sy / 2), az.normalized() * (sz / 2)
        ring0 = [center - az + ax * i + ay * j for i, j in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        ring1 = [center + az + ax * i + ay * j for i, j in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        self.loft([ring0, ring1], mat, True, False, True, True)

    def finish(self, collection, parent=None):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for face in bm.faces:
            face.smooth = True
        for face in self.flat_faces:
            if face.is_valid:
                face.smooth = False
        limit = radians(62.0)
        for edge in bm.edges:
            if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > limit:
                edge.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.transform(self.pivot.inverted())
        for name in self.mats:
            mesh.materials.append(get_material(name))
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent[0]
            obj.matrix_parent_inverse = Matrix.Identity(4)
            obj.matrix_basis = parent[1].inverted() @ self.pivot
        else:
            obj.matrix_basis = self.pivot
        return obj, self.pivot


def translation(point):
    return Matrix.Translation(point)


# ---------------------------------------------------------------------------
# 部品
# ---------------------------------------------------------------------------
def build_frame():
    p = Part("Frame")
    PA, CH, BK = "PAINT", "CHROME", "BLACK_PLASTIC"
    # ヘッドチューブとヘッドセット
    p.tube([SA(0.02), SA(0.19)], 0.017, PA, 16)
    p.tube([SA(0.004), SA(0.02)], 0.0205, CH, 16)
    p.tube([SA(0.19), SA(0.204)], 0.0205, CH, 16)
    # シートチューブと BB
    p.tube([SEAT(0.0), SEAT(0.44)], 0.0143, PA, 14)
    p.tube([P(BB_F, BB_U, -0.034), P(BB_F, BB_U, 0.034)], 0.020, PA, 16)
    p.tube([P(BB_F, BB_U, 0.034), P(BB_F, BB_U, 0.041)], 0.0165, CH, 16)
    # U字の主管と、その上を並んで走る細い管（またぎやすい低いフレーム）
    p.tube(spline([P(0.878, 0.722), P(0.80, 0.56), P(0.71, 0.42), P(0.60, 0.33), P(0.50, 0.288),
                   P(0.468, 0.279)], 8), 0.0175, PA, 14)
    p.tube(spline([P(0.842, 0.818), P(0.78, 0.68), P(0.70, 0.545), P(0.60, 0.46), P(0.50, 0.415),
                   P(0.412, 0.392)], 8), 0.0125, PA, 12)
    for sg in (-1, 1):
        # チェーンステーとシートステー
        p.tube(spline([P(0.44, 0.275, sg * 0.030), P(0.30, 0.291, sg * 0.052), P(0.14, 0.312, sg * 0.062),
                       P(0.012, 0.331, sg * 0.0625)], 6), (0.0095, 0.007), PA, 10)
        p.tube(spline([P(0.300, 0.655, sg * 0.016), P(0.255, 0.60, sg * 0.040), P(0.15, 0.49, sg * 0.058),
                       P(0.010, 0.342, sg * 0.0625)], 6), (0.007, 0.006), PA, 10)
        # 後ろのエンド（車軸を受ける板）とナット
        p.box(P(0.004, 0.336, sg * 0.0645), FWD, UP, X, 0.05, 0.036, 0.004, PA)
        p.tube([P(0.0, R_TIRE, sg * 0.0668), P(0.0, R_TIRE, sg * 0.0748)], 0.0085, CH, 6, flat=True)
        # 荷台の脚（2本ずつ）と、前のつなぎ
        p.tube([P(-0.19, 0.713, sg * 0.075), P(-0.10, 0.53, sg * 0.078), P(-0.004, 0.352, sg * 0.070)], 0.005, CH, 8)
        p.tube([P(0.06, 0.713, sg * 0.075), P(0.03, 0.53, sg * 0.076), P(-0.004, 0.352, sg * 0.070)], 0.005, CH, 8)
        p.tube([P(0.19, 0.715, sg * 0.05), P(0.262, 0.628, sg * 0.034)], 0.004, CH, 6)
        p.tube([P(-0.295, 0.715, sg * 0.025), P(0.195, 0.715, sg * 0.025)], 0.004, CH, 6)
    # ブリッジ（泥よけを留める横の管）
    p.tube([P(0.263, 0.606, -0.038), P(0.263, 0.606, 0.038)], 0.006, PA, 8)
    p.tube([P(0.385, 0.283, -0.036), P(0.385, 0.283, 0.036)], 0.007, PA, 8)
    # シートポストと締め具
    p.tube([SEAT(0.40), SEAT(SEAT_POST_TOP)], 0.0127, CH, 14)
    p.tube([SEAT(0.425), SEAT(0.445)], 0.0178, CH, 14)
    p.tube([SEAT(0.435, -0.021, -0.022), SEAT(0.435, -0.021, 0.024)], 0.004, CH, 6, flat=True)
    # 後ろの車軸とバンドブレーキ（左）
    p.tube([P(0.0, R_TIRE, -0.099), P(0.0, R_TIRE, 0.099)], 0.005, CH, 8)
    p.tube([P(0.0, R_TIRE, 0.037), P(0.0, R_TIRE, 0.058)], 0.046, CH, 20)
    p.tube([P(0.0, R_TIRE, 0.0585), P(0.0, R_TIRE, 0.061)], 0.030, BK, 16)
    p.box(P(0.075, 0.318, 0.060), P(1, 0.09) - P(0, 0), UP, X, 0.11, 0.012, 0.003, CH)
    p.tube([P(0.0, R_TIRE, 0.060), P(0.030, 0.355, 0.062), P(0.045, 0.326, 0.062)], 0.0035, CH, 6)
    # スタンドのばね（左のチェーンステーの下）
    spring = []
    for i in range(49):
        t = i / 48
        ang = 2 * pi * 12 * t
        base = P(0.045, 0.300, 0.080).lerp(P(0.185, 0.292, 0.070), t)
        spring.append(base + UP * (0.006 * cos(ang)) + X * (0.006 * sin(ang)))
    p.tube(spring, 0.0013, CH, 5)
    # 荷台（角の丸い枠・横棒・ばねのクリップ）
    p.tube(rrect(P(-0.05, 0.715), FWD, X, 0.25, 0.075, 0.03, 4), 0.005, CH, 8, closed=True)
    p.tube([P(-0.05, 0.715, -0.075), P(-0.05, 0.715, 0.075)], 0.004, CH, 6)
    p.box(P(-0.03, 0.7245), FWD, X, UP, 0.33, 0.05, 0.0025, CH)
    p.tube([P(0.14, 0.726, -0.03), P(0.14, 0.726, 0.03)], 0.005, CH, 8)
    # 馬蹄錠（後輪をまたぐ輪の鍵）
    er = (cos(radians(46.2)), sin(radians(46.2)))
    lock = []
    for i in range(21):
        psi = radians(-125.0 + 250.0 * i / 20)
        lock.append(P(0.217 + 0.052 * cos(psi) * er[0], 0.558 + 0.052 * cos(psi) * er[1], 0.052 * sin(psi)))
    p.tube(lock, 0.009, BK, 8)
    p.box(P(0.217, 0.558, 0.060), P(er[0], er[1]) - P(0, 0), P(-er[1], er[0]) - P(0, 0), X, 0.05, 0.034, 0.024, BK)
    p.tube([P(0.217, 0.558, 0.072), P(0.217, 0.558, 0.080)], 0.006, CH, 8)
    # 防犯登録のシール（シートチューブの左）とヘッドバッジ
    axis = SEAT(1.0) - SEAT(0.0)
    p.lathe([(0.0144, 0.0), (0.0150, 0.0), (0.0150, 0.05), (0.0144, 0.05)], SEAT(0.20), axis, X, "STICKER",
            10, radians(-55), radians(55), closed=True, caps=True)
    p.box(SA(0.125, 0.0176), X, SA(1.0) - SA(0.0), SA(0.0, 1.0) - SA(0.0), 0.020, 0.030, 0.0016, "BRASS")
    # 後ブレーキのワイヤー（ヘッドチューブの前から主管に沿って後ろへ）
    p.tube(spline([P(0.935, 0.855, 0.03), P(0.87, 0.70, 0.024), P(0.79, 0.535, 0.024), P(0.70, 0.40, 0.024),
                   P(0.60, 0.315, 0.024), P(0.50, 0.262, 0.030), P(0.30, 0.283, 0.062), P(0.10, 0.31, 0.068),
                   P(0.045, 0.326, 0.062)], 8), 0.0025, BK, 6)
    return p


def fender_section(radius=R_FENDER, half=0.029, crown=0.011, thick=0.0015, n=9):
    outer = []
    for i in range(n):
        s = -half + 2 * half * i / (n - 1)
        outer.append((radius - crown * (s / half) ** 2, s))
    return outer + [(r - thick, s) for r, s in reversed(outer)]


def build_fender_rear():
    p = Part("FenderRear")
    axle = P(0.0, R_TIRE)
    p.lathe(fender_section(), axle, X, FWD, "STAINLESS", 27, radians(8), radians(170), ref2=UP, closed=True, caps=True)
    p.lathe(fender_section(), axle, X, FWD, "PAINT_WHITE", 5, radians(170), radians(200), ref2=UP, closed=True, caps=True)
    for sg in (-1, 1):
        for deg in (150, 197):
            p.tube([P(-0.006, 0.346, sg * 0.067), WP(0.0, deg, 0.342, sg * 0.031)], 0.002, "CHROME", 5)
    # 赤い反射板
    a = radians(187)
    radial = P(cos(a), sin(a)) - P(0, 0)
    tangent = P(-sin(a), cos(a)) - P(0, 0)
    p.box(WP(0.0, 187, R_FENDER + 0.007), tangent, X, radial, 0.030, 0.044, 0.012, "REFLECTOR_RED")
    p.box(WP(0.0, 187, R_FENDER + 0.001), tangent, X, radial, 0.036, 0.050, 0.004, "BLACK_PLASTIC")
    return p


def build_chain_case():
    p = Part("ChainCase")
    a, b = (BB_F, BB_U), (0.0, R_TIRE)
    ra, rb = 0.108, 0.066

    def ring(da, db, s, k=1.0):
        return [P(f, u, s) for f, u in hull2(a, max((ra - da) * k, 0.002), b, max((rb - db) * k, 0.002))]

    rings = [ring(0, 0, -0.036), ring(0, 0, -0.068), ring(0.006, 0.006, -0.074), ring(0.016, 0.014, -0.074),
             ring(0.019, 0.017, -0.0715), ring(0.019, 0.017, -0.0715, 0.66), ring(0.019, 0.017, -0.0715, 0.33),
             ring(0.019, 0.017, -0.0715, 0.02)]
    p.loft(rings, "PAINT", True, False, True, True)
    # クランク軸のふくらみと、後ろの点検ふた
    p.tube([P(BB_F, BB_U, -0.0715), P(BB_F, BB_U, -0.0805)], 0.021, "PAINT", 16)
    p.tube([P(0.0, R_TIRE, -0.0715), P(0.0, R_TIRE, -0.0765)], 0.027, "CHROME", 16)
    # 飾りの帯（メーカー名が入る銀の板）と、留めねじ
    along = (P(b[0], b[1]) - P(a[0], a[1])).normalized()
    across = X.cross(along).normalized()
    p.box(P(0.215, 0.305, -0.0722), along, across, X, 0.20, 0.020, 0.0016, "CHROME")
    for f, u in ((0.335, 0.262), (0.335, 0.318), (0.075, 0.300), (0.075, 0.345)):
        p.tube([P(f, u, -0.0715), P(f, u, -0.0745)], 0.0045, "CHROME", 6, flat=True)
    return p


def build_saddle(pivot):
    p = Part("Saddle", pivot)
    cf, cu = 0.215, 0.872
    # (前後の位置, 半分の幅, 上面の高さ, 上のふくらみ, 下のふくらみ)。いちばん広い所を低くして、横が垂れた形にする。
    stations = [(-0.132, 0.058, 0.016, 0.020, 0.008), (-0.122, 0.098, 0.020, 0.034, 0.012),
                (-0.085, 0.112, 0.022, 0.040, 0.014), (-0.035, 0.106, 0.014, 0.038, 0.014),
                (0.015, 0.082, 0.006, 0.034, 0.012), (0.065, 0.048, 0.002, 0.030, 0.011),
                (0.105, 0.030, 0.002, 0.026, 0.010), (0.135, 0.020, 0.000, 0.018, 0.008)]
    rings = []
    count = 20
    for df, half, top, bulge_top, bulge_bottom in stations:
        ring = []
        for j in range(count):
            phi = 2 * pi * j / count
            c, s = cos(phi), sin(phi)
            side = half * (abs(c) ** 0.55) * (1 if c >= 0 else -1)
            height = bulge_top * (abs(s) ** 0.9) if s >= 0 else -bulge_bottom * (abs(s) ** 0.5)
            ring.append(P(cf + df, cu + top - bulge_top + height, side))
        rings.append(ring)
    p.loft(rings, "SADDLE", True, False, True, True)
    # うしろの取っ手（自転車を持ち上げるときにつかむ輪）
    p.tube(spline([P(0.105, 0.843, -0.070), P(0.075, 0.846, -0.066), P(0.060, 0.848, -0.040), P(0.057, 0.849, 0.0),
                   P(0.060, 0.848, 0.040), P(0.075, 0.846, 0.066), P(0.105, 0.843, 0.070)], 4), 0.004, "CHROME", 8)
    for sg in (-1, 1):
        # うしろのコイルばね
        helix = []
        for i in range(55):
            t = i / 54
            ang = 2 * pi * 4.5 * t
            helix.append(P(0.110 + 0.015 * cos(ang), 0.795 + 0.047 * t, sg * 0.060 + 0.015 * sin(ang)))
        p.tube(helix, 0.0028, "CHROME", 6)
        # レール（ばねの下から前の先まで）
        p.tube(spline([P(0.110, 0.795, sg * 0.060), P(0.16, 0.808, sg * 0.034), P(0.215, 0.816, sg * 0.022),
                       P(0.29, 0.832, sg * 0.016), P(0.335, 0.846, sg * 0.006)], 5), 0.0035, "CHROME", 6)
    p.tube([P(0.110, 0.843, -0.060), P(0.110, 0.843, 0.060)], 0.0035, "CHROME", 6)
    # やぐら（シートポストの頭でレールをはさむ金具）
    p.tube([SEAT(0.60, 0.0, -0.030), SEAT(0.60, 0.0, 0.030)], 0.011, "CHROME", 10)
    p.tube([SEAT(0.60, 0.0, 0.030), SEAT(0.60, 0.0, 0.038)], 0.008, "CHROME", 6, flat=True)
    # ここまでは標準の高さで作ってある。まとめてシートチューブに沿って下げる。
    bmesh.ops.translate(p.bm, verts=p.bm.verts[:], vec=SEAT(SEAT_POST_TOP) - SEAT(0.60))
    return p


def build_stand(pivot):
    p = Part("Stand", pivot)
    path = [P(0.0, 0.325, 0.092)] + spline(
        [P(-0.30, 0.3525, 0.092), P(-0.355, 0.357, 0.086), P(-0.38, 0.36, 0.062), P(-0.385, 0.36, 0.03),
         P(-0.385, 0.36, -0.03), P(-0.38, 0.36, -0.062), P(-0.355, 0.357, -0.086), P(-0.30, 0.3525, -0.092)],
        4) + [P(0.0, 0.325, -0.092)]
    p.tube(path, 0.008, "CHROME", 10)
    for sg in (-1, 1):
        p.tube([P(0.0, R_TIRE, sg * 0.086), P(0.0, R_TIRE, sg * 0.097)], 0.021, "CHROME", 14)
        # 地面に付く足の板
        p.box(P(-0.372, 0.3545, sg * 0.086), FWD, X, UP, 0.045, 0.026, 0.006, "BLACK_PLASTIC")
    return p


def build_wheel(name, axle_f, rear):
    origin = P(axle_f, R_TIRE)
    p = Part(name, translation(origin))
    # タイヤ（接地面に溝を3本）
    angles = [-135, -120, -105, -90, -75, -62.5] + [-50 + 5 * i for i in range(21)] + [62.5, 75, 90, 105, 120, 135]
    prof = []
    for deg in angles:
        rho = TIRE_R
        if abs(deg) <= 50 and (round((deg + 50) / 5) % 5) in (2,):
            rho -= 0.0013
        a = radians(deg)
        prof.append((RC_TIRE + rho * cos(a), rho * sin(a)))
    p.lathe(prof, origin, X, FWD, "RUBBER_TIRE", 64, ref2=UP, closed=True)
    # リム
    rim = [(0.3062, 0.0125), (0.289, 0.0105), (0.2865, 0.006), (0.2865, -0.006), (0.289, -0.0105),
           (0.3062, -0.0125), (0.3062, -0.0105), (0.297, -0.009), (0.297, 0.009), (0.3062, 0.0105)]
    p.lathe(rim, origin, X, FWD, "STAINLESS", 64, ref2=UP, closed=True)
    # ハブ
    fr, fs = (0.024, 0.030) if rear else (0.019, 0.033)
    hub = [(0.0008, -fs - 0.005), (0.009, -fs - 0.005), (0.009, -fs - 0.002), (fr, -fs - 0.002), (fr, -fs + 0.002),
           (0.0115, -fs + 0.006), (0.0115, fs - 0.006), (fr, fs - 0.002), (fr, fs + 0.002), (0.009, fs + 0.002),
           (0.009, fs + 0.005), (0.0008, fs + 0.005)]
    p.lathe(hub, origin, X, FWD, "CHROME", 20, ref2=UP)
    # スポーク 36本（3本組み）とニップル
    for side in (-1, 1):
        offset = 0.0 if side < 0 else 10.0
        for k in range(18):
            hub_deg = 20.0 * k + offset
            rim_deg = hub_deg + (60.0 if k % 2 == 0 else -60.0)
            lateral = side * (fs + (0.0025 if k % 2 == 0 else -0.0025))
            a, b = radians(hub_deg), radians(rim_deg)
            start = origin + X * lateral + (FWD * cos(a) + UP * sin(a)) * (fr - 0.004)
            end = origin + X * (side * 0.002) + (FWD * cos(b) + UP * sin(b)) * 0.2872
            p.tube([start, end], 0.0011, "ZINC", 5, caps=False)
            p.tube([end + (start - end).normalized() * 0.012, end], 0.0024, "ZINC", 6, caps=False)
    # バルブと、スポークの反射板
    valve = radians(95.0)
    vd = FWD * cos(valve) + UP * sin(valve)
    p.tube([origin + vd * 0.287, origin + vd * 0.255], 0.003, "ZINC", 6)
    p.tube([origin + vd * 0.255, origin + vd * 0.247], 0.004, "BLACK_PLASTIC", 6)
    ref = radians(275.0)
    rd = FWD * cos(ref) + UP * sin(ref)
    p.box(origin + rd * 0.205, rd.cross(X), rd, X, 0.085, 0.030, 0.007, "REFLECTOR_ORANGE")
    return p


def build_crank(pivot):
    p = Part("Crank", pivot)
    p.tube([P(BB_F, BB_U, -0.096), P(BB_F, BB_U, 0.086)], 0.008, "CHROME", 10)
    for sg, direction in ((-1, 1), (1, -1)):   # 右（-X）は前、左は後ろ
        s0 = -0.088 if sg < 0 else 0.078
        end = (BB_F + direction * CRANK_LEN, BB_U)

        def ring(da, s, k=1.0):
            return [P(f, u, s) for f, u in hull2((BB_F, BB_U), max((0.0175 - da) * k, 0.001), end,
                                                 max((0.0125 - da) * k, 0.001), 10, 8)]

        rings = [ring(0, s0 - 0.0065, 0.02), ring(0.0015, s0 - 0.0065), ring(0, s0 - 0.005), ring(0, s0 + 0.005),
                 ring(0.0015, s0 + 0.0065), ring(0, s0 + 0.0065, 0.02)]
        p.loft(rings, "CHROME", True, False, True, True)
        # 軸のボルトと、ペダルの軸
        p.tube([P(BB_F, BB_U, s0 + sg * 0.0065), P(BB_F, BB_U, s0 + sg * 0.011)], 0.008, "CHROME", 6, flat=True)
        p.tube([P(end[0], end[1], s0), P(end[0], end[1], s0 + sg * 0.062)], 0.0045, "CHROME", 8)
    return p


def build_pedal(name, sg, direction):
    s0 = (-0.088 if sg < 0 else 0.078) + sg * 0.062
    center = P(BB_F + direction * CRANK_LEN, BB_U, s0)
    p = Part(name, translation(center))
    p.tube([center - X * 0.046, center + X * 0.046], 0.009, "BLACK_PLASTIC", 10)
    for fore in (-1, 1):
        # ふむ面のゴム（前後2本）と、だいだい色の反射板
        p.box(center + FWD * (fore * 0.027), X, FWD, UP, 0.092, 0.018, 0.026, "RUBBER_GRIP")
        p.box(center + FWD * (fore * 0.0375), X, FWD, UP, 0.056, 0.004, 0.013, "REFLECTOR_ORANGE")
        # 滑り止めのひだ（上下の面に3本ずつ）
        for face in (-1, 1):
            for k in (-1, 0, 1):
                p.box(center + FWD * (fore * 0.027) + UP * (face * 0.0138) + X * (k * 0.028), X, FWD, UP,
                      0.014, 0.016, 0.0022, "RUBBER_GRIP")
    for end in (-1, 1):
        p.box(center + X * (end * 0.047), X, FWD, UP, 0.004, 0.074, 0.022, "CHROME")
    return p


def steer_pivot():
    z = (SA(1.0) - SA(0.0)).normalized()
    x = X.copy()
    y = z.cross(x).normalized()
    m = Matrix.Identity(4)
    for i, axis in enumerate((x, y, z)):
        m[0][i], m[1][i], m[2][i] = axis.x, axis.y, axis.z
    origin = SA(0.0)
    m[0][3], m[1][3], m[2][3] = origin.x, origin.y, origin.z
    return m


def bar_path(sg):
    return [P(0.853, 0.950, sg * 0.06), P(0.848, 0.965, sg * 0.12), P(0.825, 1.005, sg * 0.185),
            P(0.77, 1.030, sg * 0.235), P(0.705, 1.0348, sg * 0.2575), P(0.585, 1.030, sg * 0.265)]


def build_steer(pivot):
    p = Part("Steer", pivot)
    PA, CH, BK = "PAINT", "CHROME", "BLACK_PLASTIC"
    # フォーククラウンと肩
    p.tube([SA(-0.004, 0.0, -0.060), SA(-0.004, 0.0, 0.060)], 0.014, PA, 12)
    p.tube([SA(-0.024), SA(0.0)], 0.0185, PA, 14)
    p.tube([SA(0.0), SA(0.004)], 0.020, CH, 16)
    for sg in (-1, 1):
        # フォークの足（下で前へ曲がる）と、先のエンド・ナット
        p.tube(spline([SA(-0.004, 0.0, sg * 0.050), SA(-0.10, 0.0, sg * 0.050), SA(-0.20, 0.0, sg * 0.050),
                       SA(-0.28, 0.008, sg * 0.051), SA(-0.34, 0.028, sg * 0.052), SA(-0.385, 0.055, sg * 0.052)],
                      6), (0.0125, 0.0075), PA, 10)
        p.box(P(WB, R_TIRE - 0.002, sg * 0.0535), FWD, UP, X, 0.024, 0.032, 0.004, PA)
        p.tube([P(WB, R_TIRE, sg * 0.056), P(WB, R_TIRE, sg * 0.064)], 0.0085, CH, 6, flat=True)
        # かごの支え（ステムの根元から後ろの壁へ／底から前輪の軸へ）
        p.tube([SA(0.21, 0.012, sg * 0.018), P(0.90, 0.865, sg * 0.03), P(0.948, 0.80, sg * 0.05)], 0.004, CH, 6)
        p.tube([P(1.085, 0.735, sg * 0.118), P(1.095, 0.55, sg * 0.085), P(WB, R_TIRE + 0.004, sg * 0.0605)],
               0.003, CH, 6)
        # 前ブレーキ（キャリパー）のうでとゴム
        p.tube(spline([SA(-0.004, 0.030, 0.0), SA(0.0, 0.032, sg * 0.03), SA(-0.03, 0.03, sg * 0.043),
                       P(0.9515, 0.5892, sg * 0.027)], 5), 0.0045, CH, 6)
        p.box(P(0.9515, 0.5892, sg * 0.0195), P(0.866, 0.5) - P(0, 0), X, P(-0.5, 0.866) - P(0, 0), 0.045, 0.010,
              0.012, BK)
        # グリップ（ゴム。ひだ付き）とつば
        g0, g1 = P(0.705, 1.0348, sg * 0.2575), P(0.585, 1.030, sg * 0.265)
        stations = [g0.lerp(g1, i / 16) for i in range(17)]
        radii = [0.0165 if i % 2 == 0 else 0.0152 for i in range(17)]
        radii[-1] = 0.0165
        # 先を丸く閉じる（ハンドルの管の端がグリップの外へ出ないように）
        stations.append(g1 + (g1 - g0).normalized() * 0.006)
        radii.append(0.0115)
        p.tube(stations, radii, "RUBBER_GRIP", 12)
        p.tube([g0, g0.lerp(g1, 0.05)], 0.0215, "RUBBER_GRIP", 12)
        # ブレーキレバーの台座
        p.tube([P(0.731, 1.0338, sg * 0.2525), P(0.717, 1.0344, sg * 0.2553)], 0.0148, BK, 10)
        p.box(P(0.741, 1.020, sg * 0.243), FWD, X, UP, 0.030, 0.016, 0.022, BK)
    p.tube([P(WB, R_TIRE, -0.066), P(WB, R_TIRE, 0.066)], 0.0045, CH, 8)
    # ステム（突き出し）とハンドル
    p.tube([SA(0.204), SA(0.214)], 0.019, CH, 6, flat=True)
    p.tube([SA(0.214), SA(0.315)], 0.0111, CH, 12)
    p.tube([SA(0.315), SA(0.322)], 0.006, CH, 6, flat=True)
    p.tube(spline([SA(0.300), P(0.800, 0.958), P(0.830, 0.955), P(0.853, 0.950)], 4), (0.0118, 0.013), CH, 10)
    p.tube([P(0.853, 0.950, -0.017), P(0.853, 0.950, 0.017)], 0.0165, CH, 12)
    bar = list(reversed(bar_path(-1))) + bar_path(1)
    p.tube(spline(bar, 5), 0.0111, CH, 12)
    # ベル（左）
    bell = P(0.800, 1.028, 0.208)
    p.lathe([(0.0008, 0.030), (0.010, 0.029), (0.019, 0.024), (0.025, 0.015), (0.027, 0.004), (0.027, 0.0),
             (0.0008, 0.0)], bell, UP, FWD, CH, 20)
    p.tube([P(0.800, 1.016, 0.208), bell], 0.008, BK, 8)
    p.box(P(0.772, 1.034, 0.214), FWD, X, UP, 0.022, 0.008, 0.004, BK)
    p.tube([SA(-0.004, 0.014), SA(-0.004, 0.036)], 0.004, CH, 6)
    # ブレーキのワイヤー（右レバー→前ブレーキ、左レバー→フレームのワイヤーへ）
    p.tube(spline([P(0.745, 1.02, -0.240), P(0.86, 1.03, -0.19), P(0.915, 0.95, -0.10), P(0.915, 0.80, -0.045),
                   P(0.932, 0.69, -0.030)], 12), 0.0025, BK, 6)
    p.tube(spline([P(0.745, 1.02, 0.240), P(0.86, 1.03, 0.19), P(0.915, 0.96, 0.10), P(0.925, 0.90, 0.05),
                   P(0.935, 0.855, 0.03)], 12), 0.0025, BK, 6)
    # ブロックダイナモとライト（右）
    a = radians(116.0)
    radial = P(cos(a), sin(a)) - P(0, 0)
    roller = P(WB + 0.320 * cos(a), R_TIRE + 0.320 * sin(a), -0.027)
    top = roller + radial * 0.062 + X * -0.022
    axis = (top - roller).normalized()
    p.tube([roller - axis * 0.006, roller + axis * 0.006], 0.009, CH, 10)
    p.tube([roller + axis * 0.010, top], 0.014, BK, 12)
    p.tube([top, top + axis * 0.004], 0.011, CH, 10)
    lamp = P(0.995, 0.665, -0.055)
    p.lathe([(0.0008, -0.030), (0.016, -0.028), (0.027, -0.012), (0.031, 0.010), (0.031, 0.018)], lamp, FWD, UP,
            BK, 20)
    p.lathe([(0.031, 0.018), (0.033, 0.019), (0.033, 0.023), (0.029, 0.024)], lamp, FWD, UP, CH, 20)
    p.lathe([(0.029, 0.024), (0.018, 0.028), (0.0008, 0.030)], lamp, FWD, UP, "LENS", 20)
    p.tube([SA(-0.045, 0.0, -0.058), P(0.965, 0.655, -0.060), lamp + UP * -0.020], 0.004, CH, 6)
    p.tube([SA(-0.045, 0.0, -0.058), roller + axis * 0.03], 0.004, CH, 6)
    return p


def build_brake_lever(name, sg):
    pivot = P(0.745, 1.012, sg * 0.236)
    p = Part(name, translation(pivot))
    path = spline([pivot, P(0.705, 0.997, sg * 0.262), P(0.62, 0.993, sg * 0.279)], 6)
    p.tube(path, (0.0058, 0.0042), "CHROME", 8)
    p.tube([path[-1], path[-1] + (path[-1] - path[-2]).normalized() * 0.006], 0.006, "CHROME", 8)
    return p


def build_fender_front(steer_m):
    p = Part("FenderFront", steer_m)
    axle = P(WB, R_TIRE)
    p.lathe(fender_section(), axle, X, FWD, "STAINLESS", 29, radians(42), radians(215), ref2=UP, closed=True, caps=True)
    p.lathe(fender_section(half=0.031, crown=0.008, thick=0.003), axle, X, FWD, "RUBBER_GRIP", 3, radians(215),
            radians(232), ref2=UP, closed=True, caps=True)
    for sg in (-1, 1):
        p.tube([P(WB + 0.004, R_TIRE - 0.010, sg * 0.058), WP(WB, 198, 0.342, sg * 0.031)], 0.002, "CHROME", 5)
    # クラウンに留める金具
    p.box(WP(WB, 120.1, R_FENDER + 0.009), X, P(0.866, 0.5) - P(0, 0), P(-0.5, 0.866) - P(0, 0), 0.016, 0.014,
          0.018, "CHROME")
    return p


def build_basket():
    bottom_c, top_c = P(1.085, 0.735), P(1.100, 0.975)
    p = Part("Basket", translation(bottom_c))
    wires = 44

    def level(t, n):
        center = bottom_c.lerp(top_c, t)
        loop = rrect(center, FWD, X, 0.130 + 0.035 * t, 0.150 + 0.040 * t, 0.030 + 0.010 * t, 5)
        return resample_closed(loop, n)

    # 上のふち（太い）・途中の輪・底のふち
    p.tube(level(1.0, 56), 0.0032, "ZINC", 6, closed=True)
    for t in (0.25, 0.5, 0.75):
        p.tube(level(t, 56), 0.0016, "ZINC", 5, closed=True)
    p.tube(level(0.0, 56), 0.0022, "ZINC", 5, closed=True)
    # たての針金
    low, high = level(0.0, wires), level(1.0, wires)
    for a, b in zip(low, high):
        p.tube([a.lerp(b, i / 6) for i in range(7)], 0.0016, "ZINC", 5, caps=False)
    # 底の格子
    hu, hv, rad = 0.130, 0.150, 0.030

    def half_width(d, along, across):
        if abs(d) <= along - rad:
            return across
        return across - rad + sqrt(max(rad * rad - (abs(d) - (along - rad)) ** 2, 0.0))

    for i in range(-4, 5):
        d = i * 0.03
        w = half_width(d, hu, hv)
        p.tube([bottom_c + FWD * d + X * (-w + 2 * w * k / 8) for k in range(9)], 0.0016, "ZINC", 5, caps=False)
    for i in range(-4, 5):
        d = i * 0.032
        w = half_width(d, hv, hu)
        p.tube([bottom_c + X * d + FWD * (-w + 2 * w * k / 8) for k in range(9)], 0.0016, "ZINC", 5, caps=False)
    return p


# ---------------------------------------------------------------------------
# 組み立て
# ---------------------------------------------------------------------------
def _clear(collection):
    for obj in list(collection.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)


def _collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def build():
    coll = _collection(COLL_NAME)
    _clear(coll)
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_size = 0.1
    coll.objects.link(root)
    root_ref = (root, Matrix.Identity(4))

    built = {}

    def add(part, parent=root_ref):
        built[part.name] = part.finish(coll, parent)
        return built[part.name]

    add(build_frame())
    add(build_fender_rear())
    add(build_chain_case())
    add(build_saddle(translation(SEAT(SEAT_POST_TOP))))
    add(build_stand(translation(P(0.0, R_TIRE))))
    add(build_wheel("RearWheel", 0.0, True))
    crank = add(build_crank(translation(P(BB_F, BB_U))))
    add(build_pedal("PedalR", -1, 1), crank)
    add(build_pedal("PedalL", 1, -1), crank)
    steer_m = steer_pivot()
    steer = add(build_steer(steer_m))
    add(build_fender_front(steer_m), steer)
    add(build_basket(), steer)
    add(build_wheel("FrontWheel", WB, False), steer)
    add(build_brake_lever("BrakeLeverL", 1), steer)
    add(build_brake_lever("BrakeLeverR", -1), steer)

    bpy.context.view_layer.update()
    report = {"objects": {}, "tris": 0}
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for name, (obj, _pivot) in built.items():
        mesh = obj.data
        tris = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        report["objects"][name] = {"tris": tris, "materials": [m.name for m in mesh.materials],
                                   "parent": obj.parent.name if obj.parent else None}
        report["tris"] += tris
        for v in mesh.vertices:
            w = obj.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    report["bounds_min"] = [round(v, 4) for v in lo]
    report["bounds_max"] = [round(v, 4) for v in hi]
    report["size_xyz"] = [round(hi[i] - lo[i], 4) for i in range(3)]
    return report


def setup_preview():
    """確認用の床・光・カメラ（コレクション MAMACHARI_PREVIEW。書き出しには入らない）。

    LGT_key  : 右前の上からの太陽。形と影の向きを決める主光。
    LGT_fill : 左からの大きな面光。影の側のフレームと車輪を読めるようにする。
    空（World）: 屋外の空。クロームとステンレスの映り込みを作る。
    """
    scene = bpy.context.scene
    coll = _collection(PREVIEW_NAME)
    _clear(coll)

    ground_mesh = bpy.data.meshes.new("ENV_ground")
    half = 6.0
    ground_mesh.from_pydata([(-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("ENV_ground", ground_mesh)
    ground_mat = bpy.data.materials.get("MMC_PREVIEW_GROUND") or bpy.data.materials.new("MMC_PREVIEW_GROUND")
    ground_mat.use_nodes = True
    bsdf = next((n for n in ground_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.20, 0.205, 0.21, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.75
    ground_mesh.materials.append(ground_mat)
    coll.objects.link(ground)

    key_data = bpy.data.lights.new("LGT_key", "SUN")
    key_data.energy = 1.9
    key_data.angle = radians(3.0)
    key = bpy.data.objects.new("LGT_key", key_data)
    key.rotation_euler = (radians(52), 0.0, radians(-145))
    coll.objects.link(key)

    fill_data = bpy.data.lights.new("LGT_fill", "AREA")
    fill_data.energy = 45.0
    fill_data.size = 3.0
    fill = bpy.data.objects.new("LGT_fill", fill_data)
    fill.location = (3.2, -0.6, 1.8)
    fill.rotation_euler = (radians(62), 0.0, radians(82))
    coll.objects.link(fill)

    cam_data = bpy.data.cameras.new("CAM_main")
    cam_data.lens = 70.0
    cam = bpy.data.objects.new("CAM_main", cam_data)
    cam.location = (-3.3, -3.0, 1.25)
    coll.objects.link(cam)
    target = Vector((0.0, -0.09, 0.52))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    background = next((n for n in nodes if n.type == "BACKGROUND"), None)
    if background is not None:
        sky = next((n for n in nodes if n.type == "TEX_SKY"), None) or nodes.new("ShaderNodeTexSky")
        try:
            sky.sun_elevation = radians(40)
            sky.sun_rotation = radians(215)
        except Exception:
            pass
        world.node_tree.links.new(sky.outputs[0], background.inputs["Color"])
        background.inputs["Strength"].default_value = 0.16
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.resolution_percentage = 100
    try:
        scene.eevee.use_raytracing = True
    except Exception:
        pass
    return {"camera": cam.name, "engine": scene.render.engine, "view_transform": scene.view_settings.view_transform}


def export_glb(path):
    """コレクション MAMACHARI だけを Godot 用の .glb に書き出す。"""
    coll = bpy.data.collections[COLL_NAME]
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        obj.select_set(False)
    for obj in coll.objects:
        obj.hide_set(False)
        obj.select_set(True)
    view_layer.objects.active = coll.objects[ROOT_NAME]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_materials="EXPORT",
                              export_normals=True, export_tangents=False, export_cameras=False,
                              export_lights=False)
    return path
