"""Build drop_moves.glb + drop_moves.json from scratch in the LIVE Blender (Higgsfield connector; never headless).

    exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/animations/sudden_death/source/build_drop_moves.py", encoding="utf-8").read())

Steps: (1) if the scene has no RIG_Drop, import the Quaternius UAL mannequin and both UAL packs (their actions
are the sources for the run / walk / sit / roll), (2) bake every SD_* clip (dm_clips.py), (3) export the rig,
the mannequin mesh and only the SD_* actions as NLA tracks, (4) write the clip table Godot reads.
Save the .blend afterwards (drop_moves.blend next to this file).
"""
import json

import bpy

SRC = "C:/AIQUIZ/AIQUIZ-Godot/assets/animations/sudden_death/source"
UAL = ["C:/AIQUIZ/AIQUIZ-Godot/assets/animations/cc0_quaternius/UAL1_Standard.glb",
       "C:/AIQUIZ/AIQUIZ-Godot/assets/animations/cc0_quaternius/UAL2_Standard.glb"]


def import_rig():
    sc = bpy.data.scenes.get("SD_DropMoves") or bpy.data.scenes[0]
    sc.name = "SD_DropMoves"
    sc.render.fps = 30
    sc.render.fps_base = 1.0
    if bpy.data.objects.get("RIG_Drop") is not None:
        return
    rig = None
    for index, path in enumerate(UAL):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for obj in [o for o in bpy.data.objects if o not in before]:
            if obj.type == "ARMATURE" and index == 0:
                rig = obj
                continue
            if index == 0 and obj.name.startswith("Mannequin"):
                continue
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in bpy.data.actions:
        action.use_fake_user = True
    rig.name = "RIG_Drop"
    rig.data.name = "RIG_DropData"
    ad = rig.animation_data
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    ad.action = None


import_rig()
ns = {}
for _f in ("dm_lib.py", "dm_clips.py"):
    exec(open(SRC + "/" + _f, encoding="utf-8").read(), ns)


def export(infos):
    rig = ns["rig"]
    sc = ns["scene"]()
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = None
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    for name in sorted(infos):
        action = bpy.data.actions[name]
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, action)
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    rig.location = (0, 0, 0)
    mesh = bpy.data.objects["Mannequin"]
    for obj in sc.objects:
        obj.select_set(False)
    for obj in (rig, mesh):
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=ns["OUT"] + "/drop_moves.glb", export_format="GLB", use_selection=True, use_active_scene=True,
        export_apply=False, export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT",
        export_extras=False, export_cameras=False, export_lights=False,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
        export_optimize_animation_size=False, export_anim_single_armature=True, export_reset_pose_bones=True,
        export_skins=True, export_all_influences=False, export_def_bones=False, export_rest_position_armature=True,
        export_image_format="AUTO")
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    meta = {
        "version": 1,
        "fps": ns["FPS"],
        "frame": "Godot: +Z forward, +Y up, +X the body's left; origin = the floor under the pelvis at the clip start",
        "source": "assets/animations/sudden_death/source/build_drop_moves.py (Blender " + bpy.app.version_string + ")",
        "settle_limit": ns["SETTLE_LIMIT"],
        "speeds": {"run_out": round(ns["RUN_SPEED"], 4), "run_up": round(ns["RUN_UP_SPEED"], 4), "walk": round(ns["WALK_SPEED"], 4)},
        "clips": infos,
    }
    # one clip per line (the root arrays stay compact)
    clips = meta.pop("clips")
    head = json.dumps(meta, indent=1, ensure_ascii=False)[:-2]
    rows = ['  "%s": %s' % (k, json.dumps(clips[k], ensure_ascii=False, separators=(",", ":"))) for k in sorted(clips)]
    with open(ns["OUT"] + "/drop_moves.json", "w", encoding="utf-8") as fh:
        fh.write(head + ',\n "clips": {\n' + ",\n".join(rows) + "\n }\n}\n")
    return {"clips": len(infos)}


INFOS = ns["build"]()
for _name, _info in INFOS.items():
    if _info.get("kind") == "jump":
        delay = _info["settle"] - _info["leave"]
        assert delay <= ns["SETTLE_LIMIT"] + 1e-6, (_name, delay)
result = export(INFOS)
