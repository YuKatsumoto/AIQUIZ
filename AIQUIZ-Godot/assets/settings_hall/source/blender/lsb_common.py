"""設定ホール「講義セット」ビルダーの共通部: パス、座標変換、材質、bmesh の部品づくり、書き出し。

ライブ Blender（5.1）で build_lecture_set.py から使う。開いているファイルは切り替えず、専用シーン
LectureSet_Build の中だけを作り直す（LS_ / PRP_ / HERO_ / RIG_ / GK_ の名前のデータだけを扱う）。
座標: Blender は Z 上。Godot のセットのローカル (x, y, z) = Blender (x, -z, y)。人物の正面は Blender -Y。
"""
from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
ASSET = SRC.parent
ROOT = ASSET.parents[1]
PREVIEW = SRC / "previews"
BLEND_OUT = HERE / "lecture_set.blend"
REPORT = SRC / "build_report.json"

SCENE_NAME = "LectureSet_Build"
COL_PROPS = "LS_Props"
COL_CAST = "LS_Cast"
COL_REVIEW = "LS_Review"
FPS = 24
OUR_PREFIXES = ("LS_", "PRP_", "HERO_", "RIG_", "GK_", "CAM_Review", "CAM_Cast", "LGT_LS_", "ACT_")


def g2b(x: float, y: float, z: float) -> Vector:
    """Godot のセットのローカル座標 → Blender。"""
    return Vector((x, -z, y))


def hexcol(code: str, alpha: float = 1.0):
    code = code.lstrip("#")
    srgb = [int(code[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (lin[0], lin[1], lin[2], alpha)


# ------------------------------------------------------------------ materials

_MATERIALS: dict[str, bpy.types.Material] = {}


def mat(name: str, color: str, roughness: float = 0.6, metallic: float = 0.0,
        emission: str | None = None, emission_strength: float = 0.0) -> bpy.types.Material:
    """Principled のフラットな材質（glTF で運べる範囲）。同じ名前は使い回す。
    ノード名は UI の言語でローカライズされる（日本語 UI では「プリンシプルBSDF」）ので型で探す。
    ノードの削除や出力の切り替えはしない（Blender 5.1 でクラッシュした）。"""
    cached = _MATERIALS.get(name)
    if cached is not None and cached.name == name:
        return cached
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    elif not m.use_nodes:
        m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = next((n for n in nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    out = next((n for n in nodes if n.bl_idname == "ShaderNodeOutputMaterial"), None)
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    if out is None:
        out = nodes.new("ShaderNodeOutputMaterial")
    if not any(l.from_node is bsdf and l.to_node is out for l in m.node_tree.links):
        m.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = hexcol(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = hexcol(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    m.diffuse_color = hexcol(color)
    m.roughness = roughness
    m.metallic = metallic
    _MATERIALS[name] = m
    return m


PALETTE = {
    # ゴドーくん
    "GK_Blue": ("#478CBF", 0.45, 0.0),
    "GK_Navy": ("#1E3A5A", 0.5, 0.0),
    "GK_White": ("#F4F7FA", 0.35, 0.0),
    "GK_Silver": ("#AEB7C2", 0.35, 0.9),
    "GK_Red": ("#D63B3B", 0.5, 0.0),
    "GK_Yellow": ("#F2C230", 0.5, 0.0),
    "GK_Green": ("#4CAF50", 0.55, 0.0),
    "GK_Black": ("#15181C", 0.7, 0.0),
    "GK_Pink": ("#F19CB2", 0.6, 0.0),
    "GK_Orange": ("#F07F1F", 0.55, 0.0),
    "GK_Cream": ("#F2E9D0", 0.6, 0.0),
    # 小道具
    "LS_WoodA": ("#8B5A2B", 0.7, 0.0),
    "LS_WoodB": ("#9C6A38", 0.7, 0.0),
    "LS_WoodC": ("#7A4F26", 0.7, 0.0),
    "LS_WoodDark": ("#4F321A", 0.65, 0.0),
    "LS_Steel": ("#6E7680", 0.4, 0.85),
    "LS_DarkSteel": ("#3A4048", 0.45, 0.8),
    "LS_Board": ("#10291E", 0.9, 0.0),
    "LS_Paper": ("#F2F0E6", 0.8, 0.0),
    "LS_Cloth": ("#1F2E52", 0.9, 0.0),
    "LS_HazardYellow": ("#F4C500", 0.6, 0.0),
    "LS_HazardBlack": ("#141414", 0.6, 0.0),
    "LS_Cone": ("#F26A1B", 0.55, 0.0),
    "LS_White": ("#F5F5F2", 0.5, 0.0),
    "LS_Red": ("#C62828", 0.5, 0.0),
    "LS_Rubber": ("#1C1E22", 0.85, 0.0),
    "LS_BinderA": ("#2E6FBF", 0.6, 0.0),
    "LS_BinderB": ("#C8463A", 0.6, 0.0),
    "LS_BinderC": ("#3C9A5F", 0.6, 0.0),
    "LS_BinderD": ("#E0A52A", 0.6, 0.0),
    "LS_Brass": ("#B8923C", 0.35, 0.9),
}
EMISSIVE = {
    "GK_Glow": ("#7FE7FF", "#7FE7FF", 3.0),
    "GK_Zzz": ("#CFE8FF", "#CFE8FF", 1.5),
    "LS_Chalk": ("#EDEDE4", "#EDEDE4", 0.6),
    "LS_ChalkYellow": ("#F0E29A", "#F0E29A", 0.6),
    "LS_ChalkPink": ("#F2BFD2", "#F2BFD2", 0.6),
}


def palette_material(name: str) -> bpy.types.Material:
    if name in PALETTE:
        color, rough, metal = PALETTE[name]
        return mat(name, color, rough, metal)
    if name in EMISSIVE:
        color, emit, strength = EMISSIVE[name]
        return mat(name, color, 0.6, 0.0, emit, strength)
    raise KeyError(name)


# ------------------------------------------------------------------ geometry

def _xform(translate=(0, 0, 0), rotation: Matrix | None = None, scale=(1, 1, 1)) -> Matrix:
    m = Matrix.Translation(Vector(translate))
    if rotation is not None:
        m = m @ rotation.to_4x4()
    return m @ Matrix.Diagonal(Vector(scale).to_4d())


def aim_matrix(direction: Vector) -> Matrix:
    """+Z を direction に向ける回転。"""
    d = Vector(direction)
    if d.length < 1e-9:
        return Matrix.Identity(3)
    return Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix()


class MeshBuilder:
    """1 つのメッシュオブジェクトを bmesh で組み立てる。部品ごとに材質と頂点グループ（ボーン名）を持てる。"""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.grp_layer = self.bm.verts.layers.int.new("ls_group")
        self.groups: list[str] = []
        self.materials: list[str] = []

    # --- bookkeeping
    def _mat_index(self, material: str) -> int:
        if material not in self.materials:
            self.materials.append(material)
        return self.materials.index(material)

    def _grp_index(self, group: str | None) -> int:
        if group is None:
            return -1
        if group not in self.groups:
            self.groups.append(group)
        return self.groups.index(group)

    def _finish(self, verts, material: str, group: str | None, smooth: bool | str, matrix: Matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)
        mi = self._mat_index(material)
        gi = self._grp_index(group)
        faces = set()
        for v in verts:
            v[self.grp_layer] = gi
            for f in v.link_faces:
                faces.add(f)
        for f in faces:
            f.material_index = mi
            if smooth == "sides":
                f.smooth = len(f.verts) == 4
            else:
                f.smooth = bool(smooth)
        return list(faces)

    # --- primitives (all centred at `at`, in metres)
    def box(self, size, at, material: str, group: str | None = None, rotation: Matrix | None = None):
        geom = bmesh.ops.create_cube(self.bm, size=1.0)
        return self._finish(geom["verts"], material, group, False, _xform(at, rotation, size))

    def cylinder(self, radius: float, depth: float, at, material: str, group: str | None = None,
                 rotation: Matrix | None = None, segments: int = 24, radius2: float | None = None,
                 smooth: bool | str = "sides", cap: bool = True):
        geom = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=segments,
                                     radius1=radius, radius2=radius if radius2 is None else radius2, depth=depth)
        return self._finish(geom["verts"], material, group, smooth, _xform(at, rotation, (1, 1, 1)))

    def cylinder_between(self, p1, p2, radius: float, material: str, group: str | None = None,
                         radius2: float | None = None, segments: int = 20):
        p1 = Vector(p1)
        p2 = Vector(p2)
        axis = p2 - p1
        return self.cylinder(radius, axis.length, (p1 + p2) * 0.5, material, group, aim_matrix(axis),
                             segments=segments, radius2=radius2)

    def sphere(self, radius: float, at, material: str, group: str | None = None, scale=(1, 1, 1),
               segments: int = 24, rings: int = 14, rotation: Matrix | None = None):
        geom = bmesh.ops.create_uvsphere(self.bm, u_segments=segments, v_segments=rings, radius=radius)
        return self._finish(geom["verts"], material, group, True, _xform(at, rotation, scale))

    def cone(self, radius: float, depth: float, at, material: str, group: str | None = None,
             segments: int = 24, rotation: Matrix | None = None, smooth: bool | str = "sides"):
        geom = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments,
                                     radius1=radius, radius2=0.0, depth=depth)
        return self._finish(geom["verts"], material, group, smooth, _xform(at, rotation, (1, 1, 1)))

    def torus(self, major: float, minor: float, at, material: str, group: str | None = None,
              rotation: Matrix | None = None, segments: int = 24, rings: int = 10, sweep: float = math.tau):
        """輪（sweep < 2π なら弧）。+Z を軸に、XY 平面に置く。"""
        bm = self.bm
        closed = sweep >= math.tau - 1e-6
        count = segments if closed else segments + 1
        loops = []
        for i in range(count):
            a = sweep * i / segments
            ca, sa = math.cos(a), math.sin(a)
            ring = []
            for j in range(rings):
                b = math.tau * j / rings
                r = major + minor * math.cos(b)
                ring.append(bm.verts.new((r * ca, r * sa, minor * math.sin(b))))
            loops.append(ring)
        verts = [v for ring in loops for v in ring]
        pairs = list(range(count - 1)) + ([count - 1] if closed else [])
        for i in pairs:
            n = loops[(i + 1) % count]
            c = loops[i]
            for j in range(rings):
                bm.faces.new((c[j], n[j], n[(j + 1) % rings], c[(j + 1) % rings]))
        return self._finish(verts, material, group, True, _xform(at, rotation, (1, 1, 1)))

    def prism(self, points_xy, depth: float, at, material: str, group: str | None = None,
              rotation: Matrix | None = None):
        """XY の多角形を Z 方向に押し出した柱（看板の三角など）。"""
        bm = self.bm
        bottom = [bm.verts.new((x, y, -depth * 0.5)) for x, y in points_xy]
        top = [bm.verts.new((x, y, depth * 0.5)) for x, y in points_xy]
        bm.faces.new(bottom[::-1])
        bm.faces.new(top)
        n = len(points_xy)
        for i in range(n):
            bm.faces.new((bottom[i], bottom[(i + 1) % n], top[(i + 1) % n], top[i]))
        return self._finish(bottom + top, material, group, False, _xform(at, rotation, (1, 1, 1)))

    # --- finish
    def build(self, collection: bpy.types.Collection, bevel: float = 0.0, bevel_segments: int = 2):
        mesh = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for name in self.materials:
            mesh.materials.append(palette_material(name))
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        if self.groups:
            attr = mesh.attributes.get("ls_group")
            if attr is not None:
                ids = [d.value for d in attr.data]
                for gi, gname in enumerate(self.groups):
                    vg = obj.vertex_groups.new(name=gname)
                    members = [i for i, g in enumerate(ids) if g == gi]
                    if members:
                        vg.add(members, 1.0, "REPLACE")
                mesh.attributes.remove(attr)
        else:
            attr = mesh.attributes.get("ls_group")
            if attr is not None:
                mesh.attributes.remove(attr)
        if bevel > 0.0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = bevel_segments
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(40.0)
            mod.harden_normals = False
        return obj


# ------------------------------------------------------------------ scene

def main_window():
    wm = bpy.context.window_manager
    return wm.windows[0] if wm and wm.windows else None


def fresh_scene() -> bpy.types.Scene:
    """自分のシーンとデータだけを作り直す。開いているファイルの他のシーンには触れない。
    先に新しい（空の）シーンを作ってウィンドウをそこへ切り替えてから古いものを消す: 巨大な元シーンがアクティブな
    まま大量のデータを消すと、削除のたびに依存グラフが組み直されて何分も止まる。"""
    old = bpy.data.scenes.get(SCENE_NAME)
    if old is not None:
        old.name = SCENE_NAME + "_old"
    scene = bpy.data.scenes.new(SCENE_NAME)
    win = main_window()
    if win is not None:
        win.scene = scene
    if old is not None:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        for col in list(old.collection.children):
            bpy.data.collections.remove(col)
        bpy.data.scenes.remove(old)
    _MATERIALS.clear()
    for blocks in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials,
                   bpy.data.cameras, bpy.data.lights, bpy.data.collections, bpy.data.worlds):
        for block in list(blocks):
            if not block.name.startswith(OUR_PREFIXES):
                continue
            if getattr(block, "use_fake_user", False):
                block.use_fake_user = False
            if block.users == 0:
                blocks.remove(block)
    scene.render.fps = FPS
    scene.unit_settings.system = "METRIC"
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.frame_start = 0
    scene.frame_end = 288
    scene.frame_set(0)
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    world = bpy.data.worlds.get("LS_World") or bpy.data.worlds.new("LS_World")
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
    if bg is not None:
        bg.inputs["Color"].default_value = (0.02, 0.022, 0.026, 1.0)
        bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    for name in (COL_PROPS, COL_CAST, COL_REVIEW):
        col = bpy.data.collections.get(name)
        if col is None:
            col = bpy.data.collections.new(name)
        if col.name not in scene.collection.children:
            scene.collection.children.link(col)
    return scene


def collection(name: str) -> bpy.types.Collection:
    return bpy.data.collections[name]


# ------------------------------------------------------------------ export

def export_glb(scene: bpy.types.Scene, path: Path, objects, animations: bool) -> int:
    """選んだオブジェクトだけを GLB に書き出す（修正子を適用、Y 上、アクションごとのアニメーション）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    win = main_window()
    layer = scene.view_layers[0]
    with bpy.context.temp_override(window=win, scene=scene, view_layer=layer):
        for obj in scene.objects:
            obj.select_set(False)
        for obj in objects:
            obj.select_set(True)
        layer.objects.active = objects[0]
        kwargs = dict(filepath=str(path), export_format="GLB", use_selection=True, use_active_scene=True,
                      export_apply=True, export_yup=True, export_animations=animations,
                      export_animation_mode="NLA_TRACKS", export_frame_range=False, export_frame_step=1,
                      export_bake_animation=False, export_skins=True, export_morph=False, export_lights=False,
                      export_cameras=False, export_optimize_animation_size=True)
        try:
            bpy.ops.export_scene.gltf(**kwargs)
        except TypeError:
            for key in ("export_optimize_animation_size", "export_bake_animation", "export_frame_step", "export_yup"):
                kwargs.pop(key, None)
            bpy.ops.export_scene.gltf(**kwargs)
        for obj in objects:
            obj.select_set(False)
    return path.stat().st_size


def write_blend(path: Path, scene: bpy.types.Scene) -> int:
    """作業シーンとその依存データだけを別の .blend に書く（開いているファイルのパスは変えない）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(path), {scene}, fake_user=False)
    return path.stat().st_size


def render_still(scene: bpy.types.Scene, camera: bpy.types.Object, frame: int, path: Path,
                 resolution=(1600, 900), samples: int = 32) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    win = main_window()
    scene.camera = camera
    scene.frame_set(frame)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    try:
        scene.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    with bpy.context.temp_override(window=win, scene=scene, view_layer=scene.view_layers[0]):
        bpy.ops.render.render(write_still=True)
    return path


def triangle_count(obj: bpy.types.Object) -> int:
    if obj.type != "MESH":
        return 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(depsgraph)
    mesh = ev.to_mesh()
    mesh.calc_loop_triangles()
    count = len(mesh.loop_triangles)
    ev.to_mesh_clear()
    return count
