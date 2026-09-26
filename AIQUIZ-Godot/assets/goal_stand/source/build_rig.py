"""Turn the imported Quaternius UAL mannequin (CC0, assets/animations/cc0_quaternius)
into RIG_Spectator: the 23-bone body skeleton without fingers, T-pose rest,
facing -Y.  Idempotent: re-running only re-imports when the rig is missing.
"""
import bpy

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)

UAL = ["C:/AIQUIZ/AIQUIZ-Godot/assets/animations/cc0_quaternius/UAL1_Standard.glb",
       "C:/AIQUIZ/AIQUIZ-Godot/assets/animations/cc0_quaternius/UAL2_Standard.glb"]


def _import_ual(sc):
    """Import both UAL packs into GS_Source; keep their actions, drop their meshes."""
    src = G.collection("GS_Source")
    layer = bpy.context.view_layer.layer_collection.children[src.name]
    bpy.context.view_layer.active_layer_collection = layer
    rig = None
    for index, path in enumerate(UAL):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for obj in [o for o in bpy.data.objects if o not in before]:
            if obj.type == "ARMATURE" and index == 0:
                rig = obj
                continue
            if obj.type == "ARMATURE" and obj.animation_data:
                for track in obj.animation_data.nla_tracks:
                    for strip in track.strips:
                        if strip.action:
                            strip.action.use_fake_user = True
            bpy.data.objects.remove(obj, do_unlink=True)
    return rig


def build():
    sc = G.scene()
    rig = bpy.data.objects.get(G.RIG)
    if rig is None:
        rig = bpy.data.objects.get("Armature") if bpy.data.objects.get("Armature") in list(sc.objects) else None
        if rig is None:
            rig = _import_ual(sc)
        rig.name = G.RIG
        rig.data.name = G.RIG + "Data"
    # Keep every UAL clip alive for baking; the rig itself holds no NLA.
    if rig.animation_data:
        for track in list(rig.animation_data.nla_tracks):
            for strip in track.strips:
                if strip.action:
                    strip.action.use_fake_user = True
            rig.animation_data.nla_tracks.remove(track)
        rig.animation_data.action = None
    # Leftover UAL meshes / second armature / Mixamo probes in this scene only.
    for obj in list(sc.objects):
        if obj == rig or obj.parent == rig and obj.name.startswith("SPEC_"):
            continue
        if obj.name.startswith(("Mannequin", "UAL2_", "ICO", "Alpha_", "Armature")):
            if obj.type == "ARMATURE" and obj.animation_data and obj.animation_data.action:
                obj.animation_data.action.use_fake_user = True
            bpy.data.objects.remove(obj, do_unlink=True)
    # Drop fingers and leaf bones.
    for other in list(bpy.context.selected_objects):
        other.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    removed = 0
    with bpy.context.temp_override(active_object=rig, object=rig, selected_objects=[rig]):
        bpy.ops.object.mode_set(mode="EDIT")
        for bone in list(rig.data.edit_bones):
            if bone.name not in G.KEEP_BONES:
                rig.data.edit_bones.remove(bone)
                removed += 1
        bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
    rig.scale = (1, 1, 1)
    rig.data.pose_position = "POSE"
    rig.show_in_front = True
    coll = G.collection("GS_Spectator")
    if rig.name not in coll.objects:
        for c in list(rig.users_collection):
            c.objects.unlink(rig)
        coll.objects.link(rig)
    return {"rig": rig.name, "bones": [b.name for b in rig.data.bones], "removed": removed}


result = build()
