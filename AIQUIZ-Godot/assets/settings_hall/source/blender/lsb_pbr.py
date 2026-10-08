"""講義セットの実写の材質（手続き的な PBR）。Cycles で画像に焼いて glTF に運ぶ（lsb_bake.py）。

材質はすべて `LSP_` で始まり、同じ作りを持つ:
  プリンシプル BSDF ─┐
                     ├─ BAKE_MIX（Mix Shader、係数 = 値ノード BAKE_SWITCH）─ 出力
  BAKE_EMIT（放射）──┘
- 金属度は必ず `LSB_METAL`（Math ADD）を通してプリンシプルへ入れる。焼くときは LSB_METAL を BAKE_EMIT の色へ
  つないで BAKE_SWITCH = 1 にし、EMIT で焼く（lsb_bake.metal_mode）。
- 座標はオブジェクト座標（小道具はワールドの位置でメッシュを作るので、メートル単位でワールドと同じ）。
- Pointiness（凸の縁）は Cycles でしか効かないが、焼くのは Cycles なので使ってよい。
ノード名は UI の言語で変わるので、作ったノードは自分で名前を付けて探す。
"""
from __future__ import annotations

import bpy

PREFIX = "LSP_"
P_DUST = (0.86, 0.85, 0.82, 1.0)  # チョークの粉（線形）


def srgb(code: str):
    code = code.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


class Mat:
    """1 つの LSP_ 材質を組み立てる。n() でノードを作り、ln() でつなぐ。"""

    def __init__(self, name: str):
        self.name = PREFIX + name
        old = bpy.data.materials.get(self.name)
        if old is not None:
            bpy.data.materials.remove(old)
        m = bpy.data.materials.new(self.name)
        m.use_nodes = True
        self.m = m
        self.nt = m.node_tree
        for node in list(self.nt.nodes):
            if node.bl_idname != "ShaderNodeOutputMaterial":
                self.nt.nodes.remove(node)
        self.out = next(n for n in self.nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial")
        self.out.location = (900, 0)
        self.bsdf = self.n("ShaderNodeBsdfPrincipled", "BSDF", (500, 0))
        self.emit = self.n("ShaderNodeEmission", "BAKE_EMIT", (500, -650))
        self.mixer = self.n("ShaderNodeMixShader", "BAKE_MIX", (720, 0))
        self.switch = self.n("ShaderNodeValue", "BAKE_SWITCH", (500, 200))
        self.switch.outputs[0].default_value = 0.0
        self.ln(self.switch.outputs[0], self.mixer.inputs[0])
        self.ln(self.bsdf.outputs[0], self.mixer.inputs[1])
        self.ln(self.emit.outputs[0], self.mixer.inputs[2])
        self.ln(self.mixer.outputs[0], self.out.inputs["Surface"])
        self.metal = self.n("ShaderNodeMath", "LSB_METAL", (300, -300))
        self.metal.operation = "ADD"
        self.metal.inputs[0].default_value = 0.0
        self.metal.inputs[1].default_value = 0.0
        self.ln(self.metal.outputs[0], self.bsdf.inputs["Metallic"])
        tc = self.n("ShaderNodeTexCoord", "COORD", (-1400, 0))
        self.obj = tc.outputs["Object"]
        self.uv = tc.outputs["UV"]
        geo = self.n("ShaderNodeNewGeometry", "GEOMETRY", (-1400, -300))
        self.normal = geo.outputs["Normal"]
        self.pointiness = geo.outputs["Pointiness"]
        self.position = geo.outputs["Position"]
        self._x = -1100
        self._y = 300
        self.bsdf.inputs["Roughness"].default_value = 0.5
        m["lsp"] = True

    # --- plumbing
    def n(self, kind: str, name: str | None = None, at=None):
        node = self.nt.nodes.new(kind)
        if name:
            node.name = name
            node.label = name
        if at is None:
            at = (self._x, self._y)
            self._y -= 180
            if self._y < -1400:
                self._y = 300
                self._x += 220
        node.location = at
        return node

    def ln(self, a, b):
        self.nt.links.new(a, b)

    @staticmethod
    def sock(node, name_or_index, default=None):
        s = node.inputs[name_or_index]
        if default is not None:
            s.default_value = default
        return s

    def value(self, v: float):
        node = self.n("ShaderNodeValue")
        node.outputs[0].default_value = v
        return node.outputs[0]

    def rgb(self, color):
        node = self.n("ShaderNodeRGB")
        node.outputs[0].default_value = color if len(color) == 4 else (*color, 1.0)
        return node.outputs[0]

    # --- textures (all on object coordinates unless `vector` is given)
    def mapping(self, scale=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), vector=None):
        node = self.n("ShaderNodeMapping")
        node.inputs["Location"].default_value = loc
        node.inputs["Rotation"].default_value = rot
        node.inputs["Scale"].default_value = scale
        self.ln(vector if vector is not None else self.obj, node.inputs["Vector"])
        return node.outputs[0]

    def noise(self, scale=5.0, detail=4.0, rough=0.55, distortion=0.0, vector=None, dims="3D", w=0.0):
        node = self.n("ShaderNodeTexNoise")
        node.noise_dimensions = dims
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Distortion"].default_value = distortion
        if dims == "4D":
            node.inputs["W"].default_value = w
        self.ln(vector if vector is not None else self.obj, node.inputs["Vector"])
        return node.outputs["Fac"], node.outputs["Color"]

    def voronoi(self, scale=5.0, feature="F1", metric="EUCLIDEAN", vector=None, randomness=1.0):
        node = self.n("ShaderNodeTexVoronoi")
        node.feature = feature
        node.distance = metric
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = randomness
        self.ln(vector if vector is not None else self.obj, node.inputs["Vector"])
        return node

    def wave(self, scale=5.0, distortion=0.0, detail=2.0, kind="BANDS", direction="X", profile="SIN", vector=None,
             detail_scale=1.0, phase=0.0):
        node = self.n("ShaderNodeTexWave")
        node.wave_type = kind
        if kind == "BANDS":
            node.bands_direction = direction
        else:
            node.rings_direction = direction
        node.wave_profile = profile
        node.inputs["Scale"].default_value = scale
        node.inputs["Distortion"].default_value = distortion
        node.inputs["Detail"].default_value = detail
        node.inputs["Detail Scale"].default_value = detail_scale
        node.inputs["Phase Offset"].default_value = phase
        self.ln(vector if vector is not None else self.obj, node.inputs["Vector"])
        return node.outputs["Fac"]

    def image(self, path: str, vector=None, non_color=False, extension="CLIP", interpolation="Linear"):
        node = self.n("ShaderNodeTexImage")
        img = bpy.data.images.load(path, check_existing=True)
        img.reload()
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        node.image = img
        node.extension = extension
        node.interpolation = interpolation
        if vector is not None:
            self.ln(vector, node.inputs["Vector"])
        return node.outputs["Color"], node.outputs["Alpha"]

    # --- math
    def math(self, op: str, a, b=None, c=None, clamp=False):
        node = self.n("ShaderNodeMath")
        node.operation = op
        node.use_clamp = clamp
        for i, v in enumerate((a, b, c)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                node.inputs[i].default_value = float(v)
            else:
                self.ln(v, node.inputs[i])
        return node.outputs[0]

    def remap(self, v, a0, a1, b0, b1, clamp=True):
        """値 v を a0..a1 → b0..b1 へ。b0 > b1（反転）でも正しく動くよう、Map Range ではなく式で作る。"""
        t = self.math("SUBTRACT", v, a0)
        t = self.math("DIVIDE", t, max(1e-6, a1 - a0) if a1 > a0 else (a1 - a0))
        if clamp:
            t = self.math("MINIMUM", self.math("MAXIMUM", t, 0.0), 1.0)
        return self.math("ADD", self.math("MULTIPLY", t, b1 - b0), b0)

    def smooth(self, v, edge0, edge1):
        node = self.n("ShaderNodeMapRange")
        node.interpolation_type = "SMOOTHSTEP"
        node.clamp = True
        self.ln(v, node.inputs["Value"])
        node.inputs["From Min"].default_value = edge0
        node.inputs["From Max"].default_value = edge1
        node.inputs["To Min"].default_value = 0.0
        node.inputs["To Max"].default_value = 1.0
        return node.outputs["Result"]

    def mix(self, fac, a, b, blend="MIX"):
        """色の混合（a → b を fac で）。Mix ノード（RGBA）の入力は番号で指定（同名のソケットが複数ある）。"""
        node = self.n("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = blend
        node.clamp_factor = True
        for idx, v in ((0, fac), (6, a), (7, b)):
            if isinstance(v, (int, float)):
                node.inputs[idx].default_value = float(v)
            elif isinstance(v, tuple):
                node.inputs[idx].default_value = v
            else:
                self.ln(v, node.inputs[idx])
        return node.outputs[2]

    def mixf(self, fac, a, b):
        """スカラーの混合。"""
        node = self.n("ShaderNodeMix")
        node.data_type = "FLOAT"
        node.clamp_factor = True
        for idx, v in ((0, fac), (2, a), (3, b)):
            if isinstance(v, (int, float)):
                node.inputs[idx].default_value = float(v)
            else:
                self.ln(v, node.inputs[idx])
        return node.outputs[0]

    def bw(self, color):
        node = self.n("ShaderNodeRGBToBW")
        self.ln(color, node.inputs[0])
        return node.outputs[0]

    def sep(self, vec):
        node = self.n("ShaderNodeSeparateXYZ")
        self.ln(vec, node.inputs[0])
        return node.outputs[0], node.outputs[1], node.outputs[2]

    def comb(self, x, y, z=0.0):
        node = self.n("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            if isinstance(v, (int, float)):
                node.inputs[i].default_value = float(v)
            else:
                self.ln(v, node.inputs[i])
        return node.outputs[0]

    def bump(self, height, strength=0.1, distance=0.01, normal=None, invert=False):
        node = self.n("ShaderNodeBump")
        node.invert = invert
        node.inputs["Strength"].default_value = strength
        node.inputs["Distance"].default_value = distance
        self.ln(height, node.inputs["Height"])
        if normal is not None:
            self.ln(normal, node.inputs["Normal"])
        return node.outputs["Normal"]

    def planar(self, origin, u_axis, v_axis, u_len, v_len):
        """オブジェクト座標の平面 → (u, v, 0)。origin は u = v = 0 の点、軸は単位ベクトル、長さは 1 になる距離。"""
        rel = self.n("ShaderNodeVectorMath")
        rel.operation = "SUBTRACT"
        self.ln(self.obj, rel.inputs[0])
        rel.inputs[1].default_value = origin
        du = self.n("ShaderNodeVectorMath")
        du.operation = "DOT_PRODUCT"
        self.ln(rel.outputs[0], du.inputs[0])
        du.inputs[1].default_value = tuple(c / u_len for c in u_axis)
        dv = self.n("ShaderNodeVectorMath")
        dv.operation = "DOT_PRODUCT"
        self.ln(rel.outputs[0], dv.inputs[0])
        dv.inputs[1].default_value = tuple(c / v_len for c in v_axis)
        return self.comb(du.outputs["Value"], dv.outputs["Value"], 0.0)

    def facing(self, axis=(0.0, 0.0, 1.0)):
        """面の法線（オブジェクト空間の近似としてワールド法線）と軸の内積。"""
        dot = self.n("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        self.ln(self.normal, dot.inputs[0])
        dot.inputs[1].default_value = axis
        return dot.outputs["Value"]

    # --- outputs
    def base(self, color):
        if isinstance(color, tuple):
            self.bsdf.inputs["Base Color"].default_value = color
        else:
            self.ln(color, self.bsdf.inputs["Base Color"])

    def rough(self, v):
        if isinstance(v, (int, float)):
            self.bsdf.inputs["Roughness"].default_value = float(v)
        else:
            self.ln(v, self.bsdf.inputs["Roughness"])

    def metallic(self, v):
        if isinstance(v, (int, float)):
            self.metal.inputs[0].default_value = float(v)
        else:
            self.ln(v, self.metal.inputs[0])

    def normal_out(self, n):
        self.ln(n, self.bsdf.inputs["Normal"])

    def spec(self, ior=1.5):
        self.bsdf.inputs["IOR"].default_value = ior

    def coat(self, weight=0.3, roughness=0.08):
        self.bsdf.inputs["Coat Weight"].default_value = weight
        self.bsdf.inputs["Coat Roughness"].default_value = roughness

    def done(self):
        return self.m


# ------------------------------------------------------------------ helpers shared by materials

def _tint(M: Mat, color, amount=0.06, scale=2.0, seed=0.0):
    """大きな色むら（ロットの違い）: 明るさを ±amount。"""
    fac, _ = M.noise(scale, 2.0, 0.5, vector=M.mapping(loc=(seed, seed * 0.7, seed * 1.3)))
    k = M.remap(fac, 0.3, 0.7, 1.0 - amount, 1.0 + amount)
    return _scale_color(M, color, k)


def _scale_color(M: Mat, color, k):
    node = M.n("ShaderNodeVectorMath")
    node.operation = "SCALE"
    if isinstance(color, tuple):
        node.inputs[0].default_value = color[:3]
    else:
        M.ln(color, node.inputs[0])
    M.ln(k, node.inputs["Scale"])
    return node.outputs[0]


def _edges(M: Mat, lo=0.52, hi=0.58):
    """凸の縁（0..1）。Pointiness の狭い帯。"""
    return M.smooth(M.pointiness, lo, hi)


# ------------------------------------------------------------------ library

def enamel_board(name: str, art_path: str | None, plane: dict | None) -> bpy.types.Material:
    """ホーロー（スチール）黒板の面。深緑の艶消し、細かなむら、焼き付いたチョークのもや。art_path は
    lsb_chalkart が描いた RGBA（アルファ = チョークの濃さ）。plane = planar() の引数。"""
    M = Mat(name)
    base = _tint(M, srgb("#1C3A2E"), 0.05, 1.5, 3.1)
    speck, _ = M.noise(900.0, 2.0, 0.6)
    base = _scale_color(M, base, M.remap(speck, 0.35, 0.65, 0.96, 1.04))
    rough = M.remap(M.noise(40.0, 3.0, 0.6)[0], 0.3, 0.7, 0.70, 0.82)
    if art_path:
        uv = M.planar(**plane)
        col, alpha = M.image(art_path, uv)
        base = M.mix(alpha, base, col)
        rough = M.mixf(alpha, rough, 0.93)
    M.base(base)
    M.rough(rough)
    M.metallic(0.0)
    M.normal_out(M.bump(M.noise(260.0, 4.0, 0.65)[0], 0.04, 0.002))
    return M.done()


def aluminum(name: str, color="#C7CBCF", rough=0.30, brushed_axis="X", anodized=False, dust=0.0) -> bpy.types.Material:
    """アルミの押し出し材。ヘアライン（brushed_axis 方向の筋）で粗さと法線が揺れる。
    dust > 0: 上を向いた面にチョークの粉が積もる（チョーク受け）。"""
    M = Mat(name)
    stretch = {"X": (3.0, 300.0, 300.0), "Y": (300.0, 3.0, 300.0), "Z": (300.0, 300.0, 3.0)}[brushed_axis]
    streak, _ = M.noise(1.0, 6.0, 0.7, vector=M.mapping(scale=stretch))
    base = _tint(M, srgb(color), 0.03, 3.0, 1.7)
    base = _scale_color(M, base, M.remap(streak, 0.3, 0.7, 0.97, 1.03))
    r = M.remap(streak, 0.3, 0.7, rough - 0.06, rough + 0.06)
    smudge, _ = M.noise(6.0, 3.0, 0.6)
    r = M.math("ADD", r, M.remap(smudge, 0.55, 0.8, 0.0, 0.12))
    metal = 0.85 if anodized else 1.0
    if dust > 0.0:
        up = M.smooth(M.facing((0.0, 0.0, 1.0)), 0.6, 0.9)
        blot, _ = M.noise(35.0, 5.0, 0.65)
        fine, _ = M.noise(400.0, 2.0, 0.5)
        # 全体にうっすら積もり（0.5）、溜まった所ほど厚い（〜0.9）
        density = M.remap(M.math("ADD", blot, M.math("MULTIPLY", fine, 0.25)), 0.3, 0.8, 0.5, 0.92)
        powder = M.math("MINIMUM", M.math("MULTIPLY", M.math("MULTIPLY", up, density), dust), 0.95)
        base = M.mix(powder, base, P_DUST)
        r = M.mixf(powder, r, 0.95)
        metal = M.mixf(powder, metal, 0.0)
    M.base(base)
    M.rough(r)
    M.metallic(metal)
    M.normal_out(M.bump(streak, 0.06, 0.001))
    return M.done()


def powder_coat(name: str, color: str, rough=0.5, wear=0.6) -> bpy.types.Material:
    """粉体塗装の鋼。ゆず肌の凹凸、縁の塗装はがれ（下地の鋼が出る）。"""
    M = Mat(name)
    paint = _tint(M, srgb(color), 0.05, 2.0, 5.3)
    edge = _edges(M, 0.53, 0.6)
    chips, _ = M.noise(18.0, 5.0, 0.7)
    worn = M.math("MULTIPLY", edge, M.smooth(chips, 0.45, 0.6))
    worn = M.math("MULTIPLY", worn, wear)
    steel = srgb("#8C8F92")
    base = M.mix(worn, paint, steel)
    M.base(base)
    M.rough(M.mixf(worn, M.remap(M.noise(30.0, 3.0, 0.5)[0], 0.3, 0.7, rough - 0.05, rough + 0.05), 0.35))
    M.metallic(M.math("MULTIPLY", worn, 1.0))
    peel, _ = M.noise(140.0, 2.0, 0.5)
    M.normal_out(M.bump(peel, 0.05, 0.002))
    return M.done()


def rubber(name: str, color="#1B1C1E") -> bpy.types.Material:
    M = Mat(name)
    base = _tint(M, srgb(color), 0.08, 4.0, 2.2)
    M.base(base)
    M.rough(M.remap(M.noise(60.0, 3.0, 0.6)[0], 0.3, 0.7, 0.78, 0.92))
    M.metallic(0.0)
    M.normal_out(M.bump(M.noise(300.0, 2.0, 0.5)[0], 0.08, 0.001))
    return M.done()


def chalk(name: str, color: str) -> bpy.types.Material:
    """石膏チョーク: 粉っぽい艶消し、細かいくぼみ、白い粉の付き。"""
    M = Mat(name)
    base = _tint(M, srgb(color), 0.04, 30.0, 0.9)
    pits = M.voronoi(220.0, "F1")
    pit = M.smooth(pits.outputs["Distance"], 0.0, 0.25)
    dust, _ = M.noise(80.0, 3.0, 0.6)
    base = M.mix(M.remap(dust, 0.55, 0.8, 0.0, 0.35), base, srgb("#F4F2EA"))
    M.base(base)
    M.rough(0.96)
    M.metallic(0.0)
    M.normal_out(M.bump(pit, 0.25, 0.0008))
    return M.done()


def felt(name: str, color: str, dust_up_axis=(0.0, 0.0, -1.0)) -> bpy.types.Material:
    """黒板消しのフェルト: 繊維の筋、重ねた層の縞（高さ方向）、拭く面にチョークの粉。"""
    M = Mat(name)
    fiber, _ = M.noise(1.0, 8.0, 0.75, vector=M.mapping(scale=(900.0, 900.0, 90.0)))
    layers = M.wave(140.0, 1.5, 2.0, "BANDS", "Z", "SIN")
    base = _scale_color(M, srgb(color), M.remap(layers, 0.0, 1.0, 0.86, 1.06))
    base = _scale_color(M, base, M.remap(fiber, 0.35, 0.65, 0.9, 1.08))
    face = M.facing(dust_up_axis)
    blot, _ = M.noise(25.0, 4.0, 0.6)
    dust = M.math("MULTIPLY", M.smooth(face, 0.6, 0.9), M.remap(blot, 0.3, 0.7, 0.65, 1.0))
    side, _ = M.noise(40.0, 3.0, 0.6)
    dust = M.math("MAXIMUM", dust, M.math("MULTIPLY", M.smooth(side, 0.6, 0.75), 0.35))
    base = M.mix(dust, base, srgb("#E9E7E0"))
    M.base(base)
    M.rough(0.98)
    M.metallic(0.0)
    M.normal_out(M.bump(fiber, 0.35, 0.002))
    return M.done()


def plastic(name: str, color: str, rough=0.38, scratches=0.5, label_path: str | None = None,
            label_plane: dict | None = None) -> bpy.types.Material:
    """成形プラスチック: わずかなむら、細かい擦り傷（粗さ）、縁の白っぽい擦れ。"""
    M = Mat(name)
    base = _tint(M, srgb(color), 0.03, 5.0, 4.4)
    scratch = M.voronoi(60.0, "DISTANCE_TO_EDGE", vector=M.mapping(scale=(1.0, 6.0, 1.0)))
    lines = M.math("SUBTRACT", 1.0, M.smooth(scratch.outputs["Distance"], 0.0, 0.03))
    r = M.math("ADD", rough, M.math("MULTIPLY", lines, 0.18 * scratches))
    edge = _edges(M, 0.54, 0.62)
    base = M.mix(M.math("MULTIPLY", edge, 0.25), base, srgb("#FFFFFF"))
    if label_path:
        col, alpha = M.image(label_path, M.planar(**label_plane))
        base = M.mix(alpha, base, col)
    M.base(base)
    M.rough(r)
    M.metallic(0.0)
    M.normal_out(M.bump(M.noise(400.0, 2.0, 0.5)[0], 0.02, 0.001))
    return M.done()


def paper(name: str, color="#F3F1E8", rough=0.82, label_path: str | None = None, label_plane: dict | None = None,
          fiber=1.0) -> bpy.types.Material:
    """紙・厚紙。繊維、汚れの薄いむら、印刷（label）。"""
    M = Mat(name)
    base = _tint(M, srgb(color), 0.03, 8.0, 6.2)
    fib, _ = M.noise(500.0, 6.0, 0.7)
    base = _scale_color(M, base, M.remap(fib, 0.3, 0.7, 1.0 - 0.04 * fiber, 1.0 + 0.03 * fiber))
    if label_path:
        col, alpha = M.image(label_path, M.planar(**label_plane))
        base = M.mix(alpha, base, col)
    M.base(base)
    M.rough(rough)
    M.metallic(0.0)
    M.normal_out(M.bump(fib, 0.06 * fiber, 0.0008))
    return M.done()


def painted_print(name: str, label_path: str, label_plane: dict, under="#FFFFFF", rough=0.3) -> bpy.types.Material:
    """印刷した面（時計の文字盤など）。下地の色の上に label を重ねる。"""
    M = Mat(name)
    base = _tint(M, srgb(under), 0.015, 6.0, 7.7)
    col, alpha = M.image(label_path, M.planar(**label_plane))
    M.base(M.mix(alpha, base, col))
    M.rough(rough)
    M.metallic(0.0)
    M.normal_out(M.bump(M.noise(300.0, 2.0, 0.5)[0], 0.01, 0.0005))
    return M.done()


def striped(name: str, color_a: str, color_b: str, period: float, axis="Z", rough=0.25) -> bpy.types.Material:
    """縞の樹脂（ストローなど）。axis 方向に period（m）ごとの帯。"""
    M = Mat(name)
    bands = M.wave(1.0 / period, 0.0, 0.0, "BANDS", axis, "SAW")
    t = M.smooth(bands, 0.48, 0.52)
    M.base(M.mix(t, srgb(color_a), srgb(color_b)))
    M.rough(rough)
    M.metallic(0.0)
    M.normal_out(M.bump(M.noise(300.0, 2.0, 0.5)[0], 0.01, 0.0005))
    return M.done()


def magnet(name: str, color: str) -> bpy.types.Material:
    return plastic(name, color, rough=0.25, scratches=0.4)


def wood(name: str, color_a="#B98A55", color_b="#8A5E33", ring_scale=7.0, grain_axis="X", rough=0.55,
         varnish=0.0, worn=0.3, per_island=0.0) -> bpy.types.Material:
    """木目（板目）: 年輪の帯を雑音でゆがめ、繊維の細い筋と導管の点。varnish でクリアの艶。
    per_island > 0: 板 1 枚（メッシュの島）ごとに明るさと木目の位置を変える（床板）。"""
    M = Mat(name)
    island = None
    if per_island > 0.0:
        geo = M.nt.nodes["GEOMETRY"]
        island = geo.outputs["Random Per Island"]
    axis_scale = {"X": (0.15, 1.0, 1.0), "Y": (1.0, 0.15, 1.0), "Z": (1.0, 1.0, 0.15)}[grain_axis]
    v = M.mapping(scale=axis_scale)
    if island is not None:
        shift = M.n("ShaderNodeVectorMath")
        shift.operation = "ADD"
        M.ln(v, shift.inputs[0])
        M.ln(M.comb(M.math("MULTIPLY", island, 37.0), M.math("MULTIPLY", island, 11.0), 0.0), shift.inputs[1])
        v = shift.outputs[0]
    warp, _ = M.noise(1.5, 3.0, 0.5, vector=v)
    rings = M.wave(ring_scale, 6.0, 3.0, "RINGS", {"X": "X", "Y": "Y", "Z": "Z"}[grain_axis], "SAW", vector=v,
                   detail_scale=1.5)
    t = M.math("POWER", rings, 1.6)
    t = M.math("ADD", M.math("MULTIPLY", t, 0.75), M.math("MULTIPLY", warp, 0.25))
    base = M.mix(t, srgb(color_a), srgb(color_b))
    fine_v = M.mapping(scale=tuple(a * 60.0 for a in axis_scale))
    fine, _ = M.noise(4.0, 6.0, 0.7, vector=fine_v)
    base = _scale_color(M, base, M.remap(fine, 0.3, 0.7, 0.9, 1.08))
    pores = M.voronoi(1.0, "F1", vector=M.mapping(scale=tuple(a * 600.0 for a in axis_scale)))
    pore = M.math("SUBTRACT", 1.0, M.smooth(pores.outputs["Distance"], 0.0, 0.12))
    base = _scale_color(M, base, M.remap(pore, 0.0, 1.0, 1.0, 0.85))
    base = _tint(M, base, 0.06, 0.8, 9.1)
    if island is not None:
        base = _scale_color(M, base, M.remap(island, 0.0, 1.0, 1.0 - per_island, 1.0 + per_island * 0.6))
    edge = _edges(M, 0.53, 0.6)
    base = M.mix(M.math("MULTIPLY", edge, worn), base, srgb("#D9B88A"))
    r = M.remap(fine, 0.3, 0.7, rough - 0.06, rough + 0.06)
    r = M.math("ADD", r, M.math("MULTIPLY", pore, 0.08))
    M.base(base)
    M.rough(r)
    M.metallic(0.0)
    if varnish > 0.0:
        M.coat(varnish, 0.12)
    M.normal_out(M.bump(M.math("ADD", M.math("MULTIPLY", fine, 0.6), M.math("MULTIPLY", pore, 0.4)), 0.08, 0.001))
    return M.done()


def ceramic(name: str, color: str, glaze_rough=0.08) -> bpy.types.Material:
    """釉薬の陶器: 艶、釉だまりの色の濃淡、細かな貫入の筋。"""
    M = Mat(name)
    pool, _ = M.noise(6.0, 4.0, 0.6)
    base = _scale_color(M, srgb(color), M.remap(pool, 0.3, 0.7, 0.9, 1.08))
    craze = M.voronoi(90.0, "DISTANCE_TO_EDGE")
    crack = M.math("SUBTRACT", 1.0, M.smooth(craze.outputs["Distance"], 0.0, 0.015))
    base = _scale_color(M, base, M.remap(crack, 0.0, 1.0, 1.0, 0.9))
    M.base(base)
    M.rough(M.math("ADD", glaze_rough, M.math("MULTIPLY", crack, 0.1)))
    M.metallic(0.0)
    M.normal_out(M.bump(pool, 0.02, 0.002))
    return M.done()


def cloth(name: str, color: str, weave_scale=900.0) -> bpy.types.Material:
    """織物（テーブルクロス・雑巾）: 平織りの縦横、毛羽。"""
    M = Mat(name)
    warp = M.wave(weave_scale, 0.0, 0.0, "BANDS", "X", "SIN")
    weft = M.wave(weave_scale, 0.0, 0.0, "BANDS", "Y", "SIN")
    weave = M.math("MULTIPLY", M.math("ADD", warp, weft), 0.5)
    fuzz, _ = M.noise(200.0, 6.0, 0.7)
    base = _tint(M, srgb(color), 0.06, 3.0, 2.8)
    base = _scale_color(M, base, M.remap(weave, 0.0, 1.0, 0.88, 1.05))
    base = _scale_color(M, base, M.remap(fuzz, 0.3, 0.7, 0.93, 1.05))
    M.base(base)
    M.rough(0.95)
    M.metallic(0.0)
    M.bsdf.inputs["Sheen Weight"].default_value = 0.4
    M.normal_out(M.bump(weave, 0.3, 0.001))
    return M.done()


def flat(name: str, color: str, rough=0.5, metal=0.0) -> bpy.types.Material:
    """小さく見えない部品用（ねじの頭の裏など）。"""
    M = Mat(name)
    M.base(srgb(color))
    M.rough(rough)
    M.metallic(metal)
    return M.done()
