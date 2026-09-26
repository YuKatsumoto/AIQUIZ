"""Export the Goal Stand GLBs and the clip metadata Godot reads.

goal_stand.glb             GS_Stand (banner texture embedded)
goal_stand_spectator.glb   RIG_Spectator + SPEC_Body_* + GSP_* hand props, SPEC_* clips
goal_stand_props.glb       loose GSP_EggProjectile / GSP_ShellShard
goal_stand_clips.json      clip lengths, loop flags, throw release time

Only this scene's objects are selected and only SPEC_* actions are pushed to NLA
tracks, so nothing from other scenes in the session reaches the files.
"""
import json

import bpy

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)

ONE_SHOT = {"SPEC_Throw"}
THROW_RELEASE = 9           # frame measured by bake_ual.py (fastest forward hand speed)


def _select(objects):
    sc = G.scene()
    for obj in sc.objects:
        obj.select_set(False)
    for obj in objects:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def _gltf(path, **extra):
    options = dict(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_apply=False, export_yup=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_extras=False, export_cameras=False, export_lights=False,
    )
    options.update(extra)
    bpy.ops.export_scene.gltf(**options)


def spectator_clips():
    return sorted(a.name for a in bpy.data.actions if a.name.startswith("SPEC_") and a.library is None)


def export_spectator():
    rig = bpy.data.objects[G.RIG]
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = None
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    clips = {}
    for name in spectator_clips():
        action = bpy.data.actions[name]
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, action)
        if hasattr(strip, "action_slot") and len(action.slots):
            strip.action_slot = action.slots[0]
        start, end = action.frame_range
        clips[name] = {"frames": int(round(end - start)), "seconds": round((end - start) / G.FPS, 4),
                       "loop": name not in ONE_SHOT}
    clips["SPEC_Throw"]["release"] = round(THROW_RELEASE / G.FPS, 4)
    rig.data.pose_position = "POSE"
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    objects = [rig] + [o for o in bpy.data.objects if o.parent == rig and o.name.startswith(("SPEC_Body_", "GSP_"))]
    _select(objects)
    _gltf(G.OUT + "/goal_stand_spectator.glb", export_animations=True, export_animation_mode="NLA_TRACKS",
          export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True,
          export_anim_single_armature=True, export_reset_pose_bones=True, export_skins=True,
          export_all_influences=False, export_def_bones=False, export_rest_position_armature=True,
          export_image_format="AUTO")
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    return clips, [o.name for o in objects]


def export_stand():
    stand = bpy.data.objects["GS_Stand"]
    _select([stand])
    _gltf(G.OUT + "/goal_stand.glb", export_animations=False, export_skins=False, export_image_format="JPEG",
          export_jpeg_quality=88)


def export_loose():
    objs = [bpy.data.objects["GSP_EggProjectile"], bpy.data.objects["GSP_ShellShard"]]
    _select(objs)
    _gltf(G.OUT + "/goal_stand_props.glb", export_animations=False, export_skins=False, export_image_format="AUTO")
    for o in objs:
        o.hide_render = True


def export_all():
    clips, spectator_objects = export_spectator()
    export_stand()
    export_loose()
    meta = {"fps": G.FPS, "clips": clips, "roles": {"skin": 0, "shirt": 1, "pants": 2, "hair": 3, "shoes": 4,
            "dark": 5, "accent": 6, "white": 7, "blush": 8, "egg": 9, "carton": 10, "wood": 11}, "role_count": G.ROLE_COUNT}
    with open(G.OUT + "/goal_stand_clips.json", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=1)
    return {"clips": len(clips), "spectator_objects": spectator_objects}


result = export_all()
