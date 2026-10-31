"""ハテナの乗る雲（両者脱落のあと、投げ縄でプレイヤーをゴールへ運ぶ演出）をライブの Blender で作って書き出す。

開いている .blend は変えずに、別のシーン MASCOT_Cloud で作る（Higgsfield の Blender 連携 bl_execute から runpy）：
  import runpy, sys
  sys.argv = ["blender", "--"]          # 書き出さないなら ["blender", "--", "--no-export"]
  runpy.run_path(r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_mascot_cloud.py", run_name="__main__")

作るもの：
  ../mascot_cloud.glb   雲のメッシュ 1 つ（HERO_MascotCloud、6,000 三角形。球をボクセルで 1 枚につなぎ、ふくらみの境に浅い谷）。頂点色 Col の R に「ふくらみの間の陰」
                        （半球の遮り）、G に高さ（底 0 → 上 1）を入れる。材質は Godot のシェーダー（mascot_cloud.gdshader）。
  mascot_cloud.blend    このシーン（雲・確かめ用のハテナ・カメラ）だけを書き出した原本（bpy.data.libraries.write。
                        開いている .blend のパスと中身はそのまま。作業が済んだら MASCOT_Cloud のシーンは消してよい）。

大きさ（メートル、Blender の Z 上・前 -Y。原点はハテナの足の裏）：
  幅約 3.0 × 奥行き 2.5 × 高さ約 1.4。底 z ≈ -0.64、ハテナの立つ真ん中の上面 z ≈ 0.51（脚が隠れ、体の玉の下が少し埋まる）、
  うしろと左右のふちは z ≈ 0.79 まで盛り上がり、前は低くして顔とお腹を見せる。
最後の行 MASCOT_CLOUD {...} に結果。
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ASSET = HERE.parent
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_EXPORT = "--no-export" not in ARGS
SCENE_NAME = "MASCOT_Cloud"
OBJ_NAME = "HERO_MascotCloud"
REF_NAME = "REF_Hatena"
VOXEL = 0.022
TARGET_TRIS = 6000
SMOOTH_ITERATIONS = 5

# (x, y, z, 半径, (x, y, z の伸び)) — x は左右（+ がハテナの左）、y は前後（- が前）、z は上。球を 1 つにつないで（ボクセル）
# ふくらみの境に浅い谷を残す。真ん中の上面はハテナの体の玉の下を少し隠す高さ（z ≈ 0.47）。
PUFFS = [
    # 芯：平たい楕円の土台
    (0.00, 0.05, 0.09, 1.0, (0.92, 0.78, 0.42)),
    (0.00, 0.05, -0.18, 1.0, (1.02, 0.84, 0.32)),
    # 胴まわりの大きなふくらみ（左右とうしろを高く、前は低くして顔とお腹を見せる）
    (0.86, 0.05, 0.12, 0.47, (1.0, 1.0, 1.0)),
    (-0.86, 0.05, 0.12, 0.47, (1.0, 1.0, 1.0)),
    (0.60, -0.58, 0.00, 0.41, (1.0, 1.0, 0.95)),
    (-0.60, -0.58, 0.00, 0.41, (1.0, 1.0, 0.95)),
    (0.02, -0.76, -0.06, 0.40, (1.08, 1.0, 0.92)),
    (0.56, 0.64, 0.18, 0.47, (1.0, 1.0, 1.0)),
    (-0.56, 0.64, 0.18, 0.47, (1.0, 1.0, 1.0)),
    (0.00, 0.80, 0.24, 0.45, (1.05, 1.0, 1.0)),
    # ふちの上の小さなふくらみ
    (0.80, 0.40, 0.44, 0.29, (1.0, 1.0, 1.0)),
    (-0.80, 0.40, 0.44, 0.29, (1.0, 1.0, 1.0)),
    (0.30, 0.86, 0.52, 0.27, (1.0, 1.0, 1.0)),
    (-0.34, 0.84, 0.50, 0.25, (1.0, 1.0, 1.0)),
    (0.88, -0.26, 0.34, 0.24, (1.0, 1.0, 1.0)),
    (-0.88, -0.26, 0.34, 0.24, (1.0, 1.0, 1.0)),
    # 外の小さなふくらみ（輪郭に変化をつける）
    (1.22, -0.18, -0.06, 0.27, (1.0, 1.0, 1.0)),
    (-1.20, 0.10, -0.04, 0.29, (1.0, 1.0, 1.0)),
    (1.12, 0.46, 0.06, 0.25, (1.0, 1.0, 1.0)),
    (-1.08, -0.44, 0.02, 0.24, (1.0, 1.0, 1.0)),
    (0.34, 1.04, 0.02, 0.27, (1.0, 1.0, 1.0)),
    (-0.40, 1.00, 0.10, 0.25, (1.0, 1.0, 1.0)),
    (-0.32, -0.98, -0.12, 0.24, (1.0, 1.0, 1.0)),
    (0.44, -0.94, -0.10, 0.22, (1.0, 1.0, 1.0)),
    (0.98, -0.62, -0.10, 0.22, (1.0, 1.0, 1.0)),
    (-1.00, 0.68, -0.08, 0.23, (1.0, 1.0, 1.0)),
    # 底のふくらみ（丸い底を小さく波打たせる）
    (0.50, 0.25, -0.36, 0.36, (1.15, 1.05, 0.78)),
    (-0.50, 0.18, -0.36, 0.36, (1.15, 1.05, 0.78)),
    (0.00, -0.40, -0.34, 0.34, (1.15, 1.05, 0.78)),
    (0.04, 0.62, -0.32, 0.33, (1.15, 1.05, 0.78)),
    (0.92, -0.18, -0.26, 0.27, (1.0, 1.0, 0.85)),
    (-0.92, -0.10, -0.26, 0.27, (1.0, 1.0, 0.85)),
]


def _scene() -> bpy.types.Scene:
    scene = bpy.data.scenes.get(SCENE_NAME)
    if scene is None:
        scene = bpy.data.scenes.new(SCENE_NAME)
    scene.unit_settings.system = "METRIC"
    scene.render.engine = "BLENDER_EEVEE_NEXT" if hasattr(bpy.types, "EEVEE_NEXT") else scene.render.engine
    return scene


def _clear_objects(scene: bpy.types.Scene, names: list[str]) -> None:
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.MetaBall):
                bpy.data.metaballs.remove(data)


def _sphere_union(scene: bpy.types.Scene) -> bpy.types.Object:
    """ふくらみの球（楕円体）を 1 つのメッシュに集める。つなぎ目は次のボクセルの作り直しで 1 枚の面になる。"""
    bm = bmesh.new()
    rng = random.Random(7)
    for x, y, z, r, s in PUFFS:
        ret = bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=20, radius=r)
        verts = ret["verts"]
        wobble = 1.0 + rng.uniform(-0.03, 0.03)
        for v in verts:
            v.co = Vector((x + v.co.x * s[0] * wobble, y + v.co.y * s[1] * wobble, z + v.co.z * s[2]))
    mesh = bpy.data.meshes.new(OBJ_NAME)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(OBJ_NAME, mesh)
    scene.collection.objects.link(obj)
    return obj


def _apply_modifier_stack(obj: bpy.types.Object) -> None:
    remesh = obj.modifiers.new("Remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = VOXEL
    remesh.adaptivity = 0.0
    smooth = obj.modifiers.new("Smooth", "CORRECTIVE_SMOOTH")
    smooth.factor = 0.5
    smooth.iterations = SMOOTH_ITERATIONS
    smooth.smooth_type = "LENGTH_WEIGHTED"
    smooth.use_only_smooth = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    mesh.name = OBJ_NAME
    bpy.data.meshes.remove(old)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    ratio = min(1.0, TARGET_TRIS / max(1, tris))
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = ratio
    dec.use_collapse_triangulate = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh2 = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh2
    mesh2.name = OBJ_NAME
    bpy.data.meshes.remove(old)
    for poly in mesh2.polygons:
        poly.use_smooth = True


def _shade_attributes(obj: bpy.types.Object) -> dict:
    """頂点色 Col：R = 半球の遮り（ふくらみの間の陰。1 = 開けている）、G = 高さ（底 0 → 上 1）、B = 1。"""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    rng = random.Random(3)
    dirs = []
    for i in range(28):
        u, v = rng.random(), rng.random()
        r, phi = math.sqrt(u), math.tau * v
        dirs.append(Vector((r * math.cos(phi), r * math.sin(phi), math.sqrt(max(0.0, 1.0 - u)))))
    zs = [v.co.z for v in bm.verts]
    z_min, z_max = min(zs), max(zs)
    ao = []
    for vert in bm.verts:
        n = vert.normal.normalized()
        t = n.orthogonal().normalized()
        b = n.cross(t)
        hits = 0.0
        origin = vert.co + n * 0.012
        for d in dirs:
            world = t * d.x + b * d.y + n * d.z
            loc, _normal, _idx, dist = tree.ray_cast(origin, world, 0.9)
            if loc is not None:
                hits += 1.0 - (dist / 0.9) ** 0.5
        ao.append(max(0.0, 1.0 - hits / len(dirs) * 1.6))
    # 隣どうしでならして、ざらつきを消す
    for _ in range(2):
        smoothed = []
        for vert in bm.verts:
            acc, cnt = ao[vert.index], 1
            for edge in vert.link_edges:
                acc += ao[edge.other_vert(vert).index]
                cnt += 1
            smoothed.append(acc / cnt)
        ao = smoothed
    bm.free()
    if "Col" in mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes["Col"])
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, vert in enumerate(mesh.vertices):
        h = (vert.co.z - z_min) / max(1e-4, z_max - z_min)
        col.data[i].color = (ao[i], h, 1.0, 1.0)
    mesh.color_attributes.active_color = col
    return {"ao_min": round(min(ao), 3), "ao_mean": round(sum(ao) / len(ao), 3), "z_min": round(z_min, 3), "z_max": round(z_max, 3)}


def _material(obj: bpy.types.Object) -> None:
    mat = bpy.data.materials.get("MAT_MascotCloud") or bpy.data.materials.new("MAT_MascotCloud")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    sep = nodes.new("ShaderNodeSeparateColor")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.62, 0.68, 0.86, 1.0)
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(attr.outputs["Color"], sep.inputs["Color"])
    links.new(sep.outputs["Red"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def _reference(scene: bpy.types.Scene) -> list[str]:
    """確かめ用のハテナ（書き出さない）。mascot_model.glb を読み込んで REF_ コレクションに入れる。"""
    coll = bpy.data.collections.get("REF_CloudReview")
    if coll is None:
        coll = bpy.data.collections.new("REF_CloudReview")
    if coll.name not in scene.collection.children:
        scene.collection.children.link(coll)
    if coll.objects:
        return [o.name for o in coll.objects]
    before = set(bpy.data.objects)
    window = bpy.context.window
    prev_scene = window.scene
    window.scene = scene
    bpy.ops.import_scene.gltf(filepath=str(ASSET / "mascot_model.glb"))
    window.scene = prev_scene
    added = [o for o in bpy.data.objects if o not in before]
    kept = []
    for o in added:
        if o.type == "MESH" and o.parent is None:
            # 骨の表示用の形（glTF の取り込みが作る）。確かめには要らない。
            data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if data.users == 0:
                bpy.data.meshes.remove(data)
            continue
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        o.name = REF_NAME + ("Rig" if o.type == "ARMATURE" else "Mesh")
        kept.append(o.name)
    return kept


def _camera(scene: bpy.types.Scene) -> None:
    cam = bpy.data.objects.get("CAM_CloudReview")
    if cam is None:
        cam = bpy.data.objects.new("CAM_CloudReview", bpy.data.cameras.new("CAM_CloudReview"))
        scene.collection.objects.link(cam)
    cam.location = (3.6, -5.2, 2.4)
    direction = Vector((0.0, 0.0, 0.55)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 40
    scene.camera = cam
    sun = bpy.data.objects.get("LGT_CloudSun")
    if sun is None:
        sun = bpy.data.objects.new("LGT_CloudSun", bpy.data.lights.new("LGT_CloudSun", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(30))
    if scene.world is None:
        scene.world = bpy.data.worlds.new("WLD_CloudReview")
    scene.world.color = (0.45, 0.62, 0.9)


def _write_blend(scene: bpy.types.Scene) -> str:
    """開いている .blend を変えずに、このシーン（と使うデータ）だけを mascot_cloud.blend に書き出す。"""
    path = HERE / "mascot_cloud.blend"
    bpy.data.libraries.write(str(path), {scene}, path_remap="RELATIVE_ALL", fake_user=True)
    return str(path)


def _export(obj: bpy.types.Object) -> int:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = ASSET / "mascot_cloud.glb"
    # use_active_scene：ほかのシーン（開いている .blend の本来のシーン）で選ばれている物を混ぜない。
    kwargs = dict(filepath=str(path), export_format="GLB", use_selection=True, use_active_scene=True,
                  export_apply=True, export_yup=True,
                  export_cameras=False, export_lights=False, export_materials="EXPORT", export_normals=True,
                  export_texcoords=False, export_animations=False, export_skins=False, export_morph=False)
    try:
        bpy.ops.export_scene.gltf(**kwargs, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs, export_colors=True)
    return path.stat().st_size


def main() -> dict:
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    scene = _scene()
    window = bpy.context.window
    window.scene = scene
    _clear_objects(scene, [OBJ_NAME, "TMP_CloudBalls"])
    obj = _sphere_union(scene)
    bpy.context.view_layer.update()
    _apply_modifier_stack(obj)
    shade = _shade_attributes(obj)
    _material(obj)
    refs = _reference(scene)
    _camera(scene)
    dims = [round(d, 3) for d in obj.dimensions]
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    size = _export(obj) if DO_EXPORT else 0
    blend = _write_blend(scene) if DO_EXPORT else ""
    result = {"object": obj.name, "dims": dims, "tris": tris, "verts": len(obj.data.vertices), "shade": shade,
              "refs": refs, "glb": size, "blend": blend}
    print("MASCOT_CLOUD " + json.dumps(result, ensure_ascii=False))
    return result


if __name__ == "__main__":
    RESULT = main()
