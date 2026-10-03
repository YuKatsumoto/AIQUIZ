"""AIQUIZ STADIUM ビルダーの形状と材質の道具。

面ごとに「色（頂点色、線形 RGBA）」「材質キー」「UV」を持つ頂点・面リストを組み立て、最後に 1 つのメッシュオブジェクトにする。
- 色は面に 1 色（col）か、角ごとの色（ccol）。角ごとの色は島の地形・木の陰影のようななめらかな変化に使う
- UV は画像を貼る面だけ（uv）。2 つ目の UV（uv2）は帆の揺れの重みのような、シェーダーへ渡す値に使う
- smooth=True の面はなめらかに陰影をつける（帆・島・木）。箱はフラット
材質キー：
  paint  頂点色の塗装（AQS_Painted）
  night  夜だけ光る灯（AQS_NightGlow、強さはノード "NightStrength" で切り替え）
  その他  画像材質や帆の布など。Materials.add() で登録する
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h: str, alpha: float = 1.0):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (alpha,)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k, c[3])


class Mesh:
    BACK_OFFSET = 0.02   # 両面の裏を法線の逆へずらす量。同じ位置に重ねると影が自分に落ちる

    def __init__(self):
        self.v: list[tuple] = []
        self.f: list[tuple] = []
        self.col: list[tuple] = []
        self.ccol: list = []
        self.mat: list[str] = []
        self.uv: list = []
        self.uv2: list = []
        self.smooth: list[bool] = []

    # --- 基本 -------------------------------------------------------------
    def add_face(self, pts, col, mat="paint", uv=None, uv2=None, smooth=False, ccol=None):
        base = len(self.v)
        self.v.extend(tuple(p) for p in pts)
        self.f.append(tuple(range(base, base + len(pts))))
        self.col.append(col)
        self.ccol.append(ccol)
        self.mat.append(mat)
        self.uv.append(uv)
        self.uv2.append(uv2)
        self.smooth.append(smooth)

    def add_grid(self, rows, col, mat="paint", uv_rows=None, uv2_rows=None, smooth=True, ccol_rows=None, flip=False):
        """行ごとの点列（rows[i][j]）を四角形（または縮退した三角形）で張る。"""
        for i in range(len(rows) - 1):
            for j in range(len(rows[i]) - 1):
                idx = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
                if flip:
                    idx = list(reversed(idx))
                pts = [rows[a][b] for a, b in idx]
                uv = [uv_rows[a][b] for a, b in idx] if uv_rows else None
                uv2 = [uv2_rows[a][b] for a, b in idx] if uv2_rows else None
                cc = [ccol_rows[a][b] for a, b in idx] if ccol_rows else None
                # 縮退（同じ点が 2 つ）した四角形は三角形にする
                keep = [k for k in range(4) if (Vector(pts[k]) - Vector(pts[(k + 1) % 4])).length > 1e-7]
                if len(keep) < 3:
                    continue
                self.add_face([pts[k] for k in keep], col, mat, [uv[k] for k in keep] if uv else None,
                              [uv2[k] for k in keep] if uv2 else None, smooth, [cc[k] for k in keep] if cc else None)

    @staticmethod
    def _back(pts, eps):
        a, b, c = (Vector(p) for p in pts[:3])
        n = (b - a).cross(c - a)
        if n.length < 1e-9:
            return [tuple(p) for p in pts]
        n.normalize()
        return [tuple(Vector(p) - n * eps) for p in pts]

    def quad2(self, a, b, c, d, col, mat="paint", uv=None, uv_back=None):
        """両面の四角形（裏面は巻き順を逆にし、BACK_OFFSET だけ裏へずらす）。"""
        self.add_face([a, b, c, d], col, mat, uv)
        ba, bb, bc, bd = self._back([a, b, c, d], self.BACK_OFFSET)
        self.add_face([bd, bc, bb, ba], col, mat, uv_back if uv_back else (list(reversed(uv)) if uv else None))

    def tri2(self, a, b, c, col, mat="paint", smooth=False):
        self.add_face([a, b, c], col, mat, smooth=smooth)
        ba, bb, bc = self._back([a, b, c], self.BACK_OFFSET)
        self.add_face([bc, bb, ba], col, mat, smooth=smooth)

    def box_lohi(self, lo, hi, col, mat="paint", top=None, faces="all"):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        if z1 < z0:
            z0, z1 = z1, z0
        p = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        tcol = top or col
        spec = {
            "bottom": ([3, 2, 1, 0], shade(col, 0.8)),
            "top": ([4, 5, 6, 7], tcol),
            "-y": ([0, 1, 5, 4], col),
            "+x": ([1, 2, 6, 5], col),
            "+y": ([2, 3, 7, 6], col),
            "-x": ([3, 0, 4, 7], col),
        }
        for key, (idx, c) in spec.items():
            if faces != "all" and key not in faces:
                continue
            self.add_face([p[i] for i in idx], c, mat)

    def box(self, center, size, col, mat="paint", top=None, faces="all"):
        cx, cy, cz = center
        sx, sy, sz = size
        self.box_lohi((cx - sx / 2, cy - sy / 2, cz - sz / 2), (cx + sx / 2, cy + sy / 2, cz + sz / 2), col, mat, top, faces)

    def beam(self, a, b, w, col, mat="paint", h=None, up=(0, 0, 1), caps=True):
        """a→b に沿う角材（断面 w×h）。"""
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            return
        t = d.normalized()
        upv = Vector(up)
        if abs(t.dot(upv)) > 0.95:
            upv = Vector((1, 0, 0))
        s = t.cross(upv).normalized()
        u = t.cross(s).normalized()      # s × u = t（断面を反時計回りに並べると面が外を向く）
        hw, hh = w / 2, (h if h else w) / 2
        corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
        ring_a = [a + s * cx + u * cy for cx, cy in corners]
        ring_b = [b + s * cx + u * cy for cx, cy in corners]
        for i in range(4):
            j = (i + 1) % 4
            self.add_face([ring_a[i], ring_a[j], ring_b[j], ring_b[i]], col, mat)
        if caps:
            self.add_face(list(reversed(ring_a)), col, mat)
            self.add_face(ring_b, col, mat)

    def tube(self, a, b, r, col, mat="paint", n=6, smooth=True, caps=False):
        """丸い棒（ロープ・マスト）。"""
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            return
        t = d.normalized()
        upv = Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))
        s = t.cross(upv).normalized()
        u = t.cross(s).normalized()
        ring_a = [a + (s * math.cos(2 * math.pi * i / n) + u * math.sin(2 * math.pi * i / n)) * r for i in range(n)]
        ring_b = [p + d for p in ring_a]
        for i in range(n):
            j = (i + 1) % n
            self.add_face([ring_a[i], ring_a[j], ring_b[j], ring_b[i]], col, mat, smooth=smooth)
        if caps:
            self.add_face(list(reversed(ring_a)), col, mat)
            self.add_face(ring_b, col, mat)

    def prism(self, cx, cy, z0, z1, r0, r1, n, col, mat="paint", top=None, cap_top=True, cap_bottom=True,
              phase=0.0, sx=1.0, sy=1.0, smooth=False):
        """n 角柱・円錐台（楕円は sx, sy）。"""
        ring0, ring1 = [], []
        for i in range(n):
            a = phase + 2 * math.pi * i / n
            ring0.append((cx + r0 * sx * math.cos(a), cy + r0 * sy * math.sin(a), z0))
            ring1.append((cx + r1 * sx * math.cos(a), cy + r1 * sy * math.sin(a), z1))
        for i in range(n):
            j = (i + 1) % n
            k = 1.0 if smooth else 0.85 + 0.15 * math.cos(phase + 2 * math.pi * (i + 0.5) / n - 2.3)
            self.add_face([ring0[i], ring0[j], ring1[j], ring1[i]], shade(col, k), mat, smooth=smooth)
        if cap_bottom:
            self.add_face(list(reversed(ring0)), shade(col, 0.8), mat)
        if cap_top and r1 > 1e-4:
            self.add_face(ring1, top or col, mat)

    def cone(self, cx, cy, z0, z1, r, n, col, mat="paint", phase=0.0):
        apex = (cx, cy, z1)
        ring = [(cx + r * math.cos(phase + 2 * math.pi * i / n), cy + r * math.sin(phase + 2 * math.pi * i / n), z0) for i in range(n)]
        for i in range(n):
            j = (i + 1) % n
            self.add_face([ring[i], ring[j], apex], shade(col, 0.88 + 0.12 * math.cos(2 * math.pi * i / n)), mat)
        self.add_face(list(reversed(ring)), shade(col, 0.8), mat)

    def dome(self, cx, cy, z0, r, h, n, rings, col, mat="paint", smooth=False):
        prev = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z0) for i in range(n)]
        for k in range(1, rings + 1):
            t = k / rings
            rr = r * math.cos(t * math.pi / 2)
            zz = z0 + h * math.sin(t * math.pi / 2)
            cur = [(cx + rr * math.cos(2 * math.pi * i / n), cy + rr * math.sin(2 * math.pi * i / n), zz) for i in range(n)]
            for i in range(n):
                j = (i + 1) % n
                if k == rings:
                    self.add_face([prev[i], prev[j], cur[0]], shade(col, 1.0 if smooth else 0.95), mat, smooth=smooth)
                else:
                    self.add_face([prev[i], prev[j], cur[j], cur[i]], shade(col, 1.0 if smooth else 0.9 + 0.1 * t), mat, smooth=smooth)
            prev = cur

    def blob(self, c, rx, ry, rz, col_top, col_bottom, mat="paint", seg=8, rings=5, squash_bottom=0.55):
        """丸い塊（木の茂み・岩）。上から下へ色がなめらかに変わる。"""
        cx, cy, cz = c
        rows, cc = [], []
        for k in range(rings + 1):
            t = k / rings                              # 0＝下、1＝上
            phi = -math.pi / 2 + math.pi * t
            z = math.sin(phi) * (rz if phi > 0 else rz * squash_bottom)
            rr = math.cos(phi)
            if k in (0, rings):
                row = [(cx, cy, cz + z)] * (seg + 1)
            else:
                row = [(cx + rx * rr * math.cos(2 * math.pi * i / seg), cy + ry * rr * math.sin(2 * math.pi * i / seg), cz + z)
                       for i in range(seg + 1)]
            rows.append(row)
            cc.append([mix(col_bottom, col_top, min(1.0, max(0.0, 0.15 + 0.85 * t)))] * (seg + 1))
        self.add_grid(rows, col_top, mat, smooth=True, ccol_rows=cc)

    def extrude_poly(self, pts, z0, z1, col, mat="paint", top=None, bottom=True):
        """星形の多角形（中心から見て凸）を押し出す。上面・下面は中心から扇状に。"""
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            a, b = pts[i], pts[j]
            self.add_face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)],
                          shade(col, 0.85 + 0.15 * math.sin(i)), mat)
            self.add_face([(cx, cy, z1), (a[0], a[1], z1), (b[0], b[1], z1)], top or col, mat)
            if bottom:
                self.add_face([(cx, cy, z0), (b[0], b[1], z0), (a[0], a[1], z0)], shade(col, 0.7), mat)

    def transformed(self, m: Matrix) -> "Mesh":
        out = Mesh()
        out.v = [tuple(m @ Vector(p)) for p in self.v]
        out.f, out.col, out.mat, out.uv = list(self.f), list(self.col), list(self.mat), list(self.uv)
        out.uv2, out.smooth, out.ccol = list(self.uv2), list(self.smooth), list(self.ccol)
        return out

    def extend(self, other: "Mesh"):
        base = len(self.v)
        self.v.extend(other.v)
        self.f.extend(tuple(i + base for i in face) for face in other.f)
        for name in ("col", "mat", "uv", "uv2", "smooth", "ccol"):
            getattr(self, name).extend(getattr(other, name))

    def triangles(self) -> int:
        return sum(len(face) - 2 for face in self.f)


def rounded_rect(x0, y0, x1, y1, r, seg=3):
    """角を丸めた長方形の外周（反時計回り）。"""
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# --- 材質 -------------------------------------------------------------------
def _principled(mat, cull=True):
    if mat.node_tree is None:
        mat.use_nodes = True
    # 面はすべて外向きにそろえてある。片面にしておくと glTF の doubleSided が false になり、Godot で裏面を描かない
    mat.use_backface_culling = cull
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf is None:
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.name = "Principled BSDF"
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf


def vertex_colour_material(name, roughness=0.72, emission=0.0, night=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    if emission or night:
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        if night:
            val = nt.nodes.new("ShaderNodeValue")
            val.name = "NightStrength"
            val.outputs[0].default_value = emission
            nt.links.new(val.outputs[0], bsdf.inputs["Emission Strength"])
        else:
            bsdf.inputs["Emission Strength"].default_value = emission
    mat["aqs_role"] = "night" if night else ("glow" if emission else "paint")
    return mat


def flat_material(name, rgba, roughness=0.6, emission=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = rgba
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = rgba
    return mat


def load_image(path: Path, non_color=False):
    img = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def image_material(name, path: Path, emission=0.0, roughness=0.5, vertex_tint=False, night_path: Path | None = None):
    """画像を基本色に。vertex_tint=True なら頂点色を掛ける。night_path があれば夜の発光（NightStrength で切り替え）。"""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = load_image(path)
    tex.interpolation = "Linear"
    col_out = tex.outputs["Color"]
    if vertex_tint:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs[0].default_value = 1.0
        nt.links.new(tex.outputs["Color"], mul.inputs[6])
        nt.links.new(attr.outputs["Color"], mul.inputs[7])
        col_out = mul.outputs[2]
    nt.links.new(col_out, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    if night_path is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = load_image(night_path)
        nt.links.new(ntex.outputs["Color"], bsdf.inputs["Emission Color"])
        val = nt.nodes.new("ShaderNodeValue")
        val.name = "NightStrength"
        val.outputs[0].default_value = 0.0
        nt.links.new(val.outputs[0], bsdf.inputs["Emission Strength"])
    elif emission:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


class Materials:
    def __init__(self):
        self.by_key = {
            "paint": vertex_colour_material("AQS_Painted", 0.72),
            "night": vertex_colour_material("AQS_NightGlow", 0.4, emission=0.0, night=True),
        }
        self.night_ratio = {"night": 1.0}

    def add(self, key, mat, night_ratio=None):
        self.by_key[key] = mat
        if night_ratio is not None:
            self.night_ratio[key] = night_ratio

    def set_night(self, strength: float):
        for key, ratio in self.night_ratio.items():
            node = self.by_key[key].node_tree.nodes.get("NightStrength")
            if node is not None:
                node.outputs[0].default_value = strength * ratio


def create_object(name, mesh: Mesh, materials: Materials, collection, location=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mesh.v, [], mesh.f)
    keys = []
    for k in mesh.mat:
        if k not in keys:
            keys.append(k)
    for k in keys:
        me.materials.append(materials.by_key[k])
    colours = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    uvl = me.uv_layers.new(name="UVMap")
    has_uv2 = any(u is not None for u in mesh.uv2)
    uvl2 = me.uv_layers.new(name="UV2") if has_uv2 else None
    for poly, col, cc, key, uv, uv2, sm in zip(me.polygons, mesh.col, mesh.ccol, mesh.mat, mesh.uv, mesh.uv2, mesh.smooth):
        poly.material_index = keys.index(key)
        poly.use_smooth = bool(sm)
        for n, li in enumerate(poly.loop_indices):
            colours.data[li].color = cc[n] if cc else col
            uvl.data[li].uv = uv[n] if uv else (0.5, 0.5)
            if uvl2 is not None:
                uvl2.data[li].uv = uv2[n] if uv2 else (0.0, 0.0)
    me.color_attributes.active_color = colours
    me.uv_layers.active = uvl
    uvl.active_render = True
    me.validate(clean_customdata=False)
    me.update()
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    collection.objects.link(obj)
    return obj


def collection(name, parent=None):
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if coll.name not in [c.name for c in parent.children]:
        parent.children.link(coll)
    return coll


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def translate(x, y, z):
    return Matrix.Translation((x, y, z))
