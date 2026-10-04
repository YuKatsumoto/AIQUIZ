"""設定ホール「連結チップソー講座」のセットと登場人物を Blender で組み立て、GLB に書き出す（SCENE_PASSPORT.md）。

ユーザーのライブ Blender 上で実行する（Higgsfield の Blender 連携 bl_execute 経由、例:
    import runpy, sys; sys.argv = ["blender", "--", "--no-render"]
    runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/settings_hall/source/blender/build_lecture_set.py", run_name="__main__")
）。開いているファイルは切り替えない。専用シーン LectureSet_Build を作り直し、小道具と 5 体のゴドーくんを作って
assets/settings_hall/*.glb へ書き出し、作業シーンを source/blender/lecture_set.blend へ書く（開いているファイルは保存しない）。
引数: --no-render（確認レンダーを省く）、--only-renders（組み立てずにレンダーだけ）。
"""
from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
for name in list(sys.modules):
    if name.startswith("lsb_"):
        del sys.modules[name]

import lsb_anim as AN  # noqa: E402
import lsb_godotkun as GK  # noqa: E402
import lsb_props as PR  # noqa: E402
from lsb_common import (ASSET, BLEND_OUT, COL_CAST, COL_PROPS, COL_REVIEW, PREVIEW, REPORT, SCENE_NAME, collection,  # noqa: E402
                        export_glb, fresh_scene, g2b, render_still, triangle_count, write_blend)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
ONLY_RENDERS = "--only-renders" in ARGS

# 配置（Godot のセットのローカル座標、lecture_set.gd の定数と同じ）。正面: 生徒・練習生 +Z、講師 -Z。
CAST = [
    # name, variant, godot (x, z), yaw_deg (Blender Z、0 = 正面 -Y = Godot +Z), clip
    ("lecturer", "lecturer", (3.4, 6.5), 180.0, "teach"),
    ("student_notes", "notes", (-2.3, PR.STOOL_Z), 0.0, "notes"),
    ("student_hand", "hand", (0.0, PR.STOOL_Z), 0.0, "hand"),
    ("student_doze", "doze", (2.3, PR.STOOL_Z), 0.0, "doze"),
    ("trainee", "trainee", (-4.4, 1.2), 0.0, "practice"),
]
REVIEW_FRAMES = (0, 56, 100, 150, 204)


def build_review_camera(scene):
    col = collection(COL_REVIEW)
    cam_data = bpy.data.cameras.new("CAM_Review")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(42.0)
    cam_data.clip_start = 0.05
    cam_data.clip_end = 300.0
    cam = bpy.data.objects.new("CAM_Review", cam_data)
    col.objects.link(cam)
    eye = g2b(5.8, 6.6, -12.0)
    aim_at = g2b(3.2, 1.6, 1.0)
    cam.location = eye
    cam.rotation_euler = (aim_at - eye).to_track_quat("-Z", "Y").to_euler()
    cast_data = bpy.data.cameras.new("CAM_Cast")
    cast_data.sensor_fit = "VERTICAL"
    cast_data.angle_y = math.radians(34.0)
    cast = bpy.data.objects.new("CAM_Cast", cast_data)
    col.objects.link(cast)
    eye2 = g2b(3.2, 2.1, -4.0)
    aim2 = g2b(0.2, 1.0, 1.4)
    cast.location = eye2
    cast.rotation_euler = (aim2 - eye2).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    # 確認用のライト（ゲームの KeyLight / Fill / Rim と同じ向き）
    for name, kind, godot_from, godot_aim, energy, color in (
            ("LGT_LS_Key", "SPOT", (3.5, 4.8, -3.0), (0.0, 0.8, 3.0), 1800.0, (1.0, 0.93, 0.82)),
            ("LGT_LS_Fill", "SPOT", (-4.0, 3.6, -2.5), (0.0, 0.5, -0.5), 500.0, (0.8, 0.86, 1.0)),
            ("LGT_LS_Rim", "SPOT", (-2.0, 5.0, 7.5), (0.0, 0.6, 1.0), 900.0, (0.95, 0.97, 1.0)),
            ("LGT_LS_Board", "AREA", (0.0, 3.6, 5.0), (0.0, 2.0, 8.6), 300.0, (1.0, 1.0, 1.0))):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == "SPOT":
            data.spot_size = math.radians(70.0)
            data.spot_blend = 0.6
            data.shadow_soft_size = 0.4
        else:
            data.size = 3.0
        light = bpy.data.objects.new(name, data)
        col.objects.link(light)
        src = g2b(*godot_from)
        dst = g2b(*godot_aim)
        light.location = src
        light.rotation_euler = (dst - src).to_track_quat("-Z", "Y").to_euler()
    return cam, cast


def place(obj, godot_xz, yaw_deg):
    obj.location = g2b(godot_xz[0], 0.0, godot_xz[1])
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))


def build():
    t0 = time.time()
    scene = fresh_scene()
    props = PR.build_all_props(collection(COL_PROPS))
    cast_col = collection(COL_CAST)
    cast = []
    for name, variant, godot_xz, yaw, clip in CAST:
        entry = GK.build_godotkun(name, variant, cast_col)
        place(entry["arm"], godot_xz, yaw)
        entry["name"] = name
        entry["clip"] = clip
        cast.append(entry)
    # 座った生徒: 胴の底を座面へ（ぬいぐるみの脚は短いので、足は床から浮く）
    seat_lift = PR.STOOL_TOP - GK.BODY_BOTTOM
    # アニメーション
    clip_reports = {}
    for entry in cast:
        arm = entry["arm"]
        if entry["clip"] == "teach":
            clip_reports[entry["name"]] = AN.clip_teach(arm)
        elif entry["clip"] == "notes":
            clip_reports[entry["name"]] = AN.clip_take_notes(arm, seat_lift)
        elif entry["clip"] == "hand":
            clip_reports[entry["name"]] = AN.clip_raise_hand(arm, seat_lift)
        elif entry["clip"] == "doze":
            clip_reports[entry["name"]] = AN.clip_doze(arm, seat_lift)
        elif entry["clip"] == "practice":
            clip_reports[entry["name"]] = AN.clip_practice(arm, GK.RAIL_Y0, GK.RAIL_Y1, GK.BLADE_R)
    GK.release_template()
    scene.frame_set(0)
    cam, cast_cam = build_review_camera(scene)
    scene.frame_set(0)
    return scene, props, cast, clip_reports, cam, cast_cam, time.time() - t0


def export_all(scene, props, cast):
    """小道具はセットの座標のまま 1 本に。人物は足元を原点・正面 -Y に戻して書き出す（配置は Godot の
    lecture_set.gd が足す。シーン上の配置は確認レンダー用なので、書き出し後に元へ戻す）。"""
    out = {}
    out["lecture_set_props.glb"] = export_glb(scene, ASSET / "lecture_set_props.glb", props, animations=False)
    for entry in cast:
        arm = entry["arm"]
        placed = (arm.location.copy(), arm.rotation_euler.copy())
        arm.location = (0.0, 0.0, 0.0)
        arm.rotation_euler = (0.0, 0.0, 0.0)
        file_name = f"godotkun_{entry['name']}.glb"
        try:
            out[file_name] = export_glb(scene, ASSET / file_name, [arm, entry["mesh"], entry["gear"]], animations=True)
        finally:
            arm.location, arm.rotation_euler = placed
    return out


def _evaluated_coords(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(depsgraph)
    mesh = ev.to_mesh()
    coords = [v.co.copy() for v in mesh.vertices]
    ev.to_mesh_clear()
    return coords


def _group_members(mesh_obj, names):
    idx = {mesh_obj.vertex_groups[n].index for n in names if n in mesh_obj.vertex_groups}
    return {v.index for v in mesh_obj.data.vertices if any(g.group in idx and g.weight > 0.5 for g in v.groups)}


def _blade_clearance(scene, entry):
    """跳躍の間、ぬいぐるみ（レールと刃以外）の頂点が刃の円盤（歯を含む半径）にどれだけ近づくか。
    円盤は x = 0 の面にあるので、|x| < 0.06 の頂点だけを、刃の中心からの YZ 距離で見る。"""
    gear = entry["gear"]
    blade = _group_members(gear, ["Blade"])
    rail = _group_members(gear, ["Rail"])
    worn = [i for i in range(len(gear.data.vertices)) if i not in blade and i not in rail]
    reach = GK.BLADE_R + 0.06
    worst = None
    for frame in range(28, 76):
        scene.frame_set(frame)
        gear_coords = _evaluated_coords(gear)
        hub = [gear_coords[i] for i in blade]
        cy = sum(p.y for p in hub) / len(hub)  # 刃は y だけ動く（中心の高さは一定）
        cz = GK.RAIL_Z + GK.BLADE_R
        for p in _evaluated_coords(entry["mesh"]) + [gear_coords[i] for i in worn]:
            if abs(p.x) > 0.06:
                continue
            gap = math.hypot(p.y - cy, p.z - cz) - reach
            if worst is None or gap < worst[0]:
                worst = (gap, frame)
    scene.frame_set(0)
    return {"min_gap_to_blade": round(worst[0], 3), "frame": worst[1]} if worst else None


def audit(scene, props, cast):
    report = {"props": {}, "cast": {}}
    total_props = 0
    for obj in props:
        tris = triangle_count(obj)
        total_props += tris
        report["props"][obj.name] = {"tris": tris, "materials": [m.name for m in obj.data.materials]}
    report["props_total_tris"] = total_props
    for entry in cast:
        arm = entry["arm"]
        mesh = entry["mesh"]
        gear = entry["gear"]
        scene.frame_set(0)
        tris = triangle_count(mesh) + triangle_count(gear)
        groups = {vg.name for vg in mesh.vertex_groups} | {vg.name for vg in gear.vertex_groups}
        bones = {b.name for b in arm.data.bones}
        clearance = _blade_clearance(scene, entry) if entry["name"] == "trainee" else None
        seated = None
        if entry["variant"] in ("notes", "hand", "doze"):
            scene.frame_set(0)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            ev = arm.evaluated_get(depsgraph)
            body = ev.matrix_world @ ev.pose.bones["Body"].head
            seated = {"body_bottom_z": round(body.z, 3), "stool_top": PR.STOOL_TOP}
        # 頭と胴（DEF-head / DEF-hips）は曲げない: 全フレームで休止のまま
        bent = []
        if arm.animation_data:
            for track in arm.animation_data.nla_tracks:
                for strip in track.strips:
                    act = strip.action
                    for layer in getattr(act, "layers", []):
                        for st in layer.strips:
                            for cb in st.channelbags:
                                bent += [fc.data_path for fc in cb.fcurves
                                         if '"DEF-head"' in fc.data_path or '"DEF-hips"' in fc.data_path]
        report["cast"][entry["name"]] = {
            "tris": tris, "bones": len(bones), "vertex_groups_not_bones": sorted(groups - bones),
            "bones_without_groups": sorted(bones - groups), "missing_weights": entry["missing_weights"],
            "action": [t.name for t in arm.animation_data.nla_tracks] if arm.animation_data else None,
            "head_or_hips_keyed": sorted(set(bent)), "clearance": clearance, "seated": seated,
            "materials": [m.name for m in mesh.data.materials] + [m.name for m in gear.data.materials],
            "plush_custom_normals": mesh.data.has_custom_normals, "gear_custom_normals": gear.data.has_custom_normals,
        }
    duplicates = [m.name for m in bpy.data.materials if m.name.startswith(("GK_", "LS_")) and ".0" in m.name]
    report["duplicate_materials"] = duplicates
    return report


def render_previews(scene, cam, cast_cam):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    paths = []
    for frame in REVIEW_FRAMES:
        paths.append(str(render_still(scene, cam, frame, PREVIEW / f"review_f{frame:03d}.png", (1600, 900), 24)))
    for frame in (0, 56, 100):
        paths.append(str(render_still(scene, cast_cam, frame, PREVIEW / f"cast_f{frame:03d}.png", (1600, 900), 24)))
    scene.camera = cam
    scene.frame_set(0)
    return paths


def main():
    if ONLY_RENDERS:
        scene = bpy.data.scenes[SCENE_NAME]
        cam = bpy.data.objects["CAM_Review"]
        cast_cam = bpy.data.objects["CAM_Cast"]
        paths = render_previews(scene, cam, cast_cam)
        print({"renders": paths})
        return {"renders": paths}
    scene, props, cast, clip_reports, cam, cast_cam, build_seconds = build()
    exports = export_all(scene, props, cast)
    report = audit(scene, props, cast)
    report["clips"] = clip_reports
    report["exports_bytes"] = exports
    report["build_seconds"] = round(build_seconds, 2)
    report["blend_bytes"] = write_blend(BLEND_OUT, scene)
    report["blender"] = bpy.app.version_string
    report["live_file"] = bpy.data.filepath
    renders = []
    if DO_RENDER:
        renders = render_previews(scene, cam, cast_cam)
    report["renders"] = renders
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    scene.frame_set(0)
    return report


if __name__ == "__main__":
    RESULT = main()
