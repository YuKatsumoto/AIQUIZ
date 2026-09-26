"""Review renders for the Goal Stand build (EEVEE, preview camera and lights only).

    pv = {}; exec(open(".../preview.py", encoding="utf-8").read(), pv)
    pv["render_pose"]("Short", "SPEC_Cheer", 12, "C:/.../out.png")
"""
import math
import os

import bpy
from mathutils import Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)
REVIEW = "C:/AIQUIZ/AIQUIZ-Godot/artifacts/goal_stand/blender"


def ensure_preview():
    sc = G.scene()
    coll = G.collection("GS_Preview")
    cam = bpy.data.objects.get("CAM_Preview")
    if cam is None:
        cam = bpy.data.objects.new("CAM_Preview", bpy.data.cameras.new("CAM_Preview"))
        coll.objects.link(cam)
    sun = bpy.data.objects.get("LGT_PreviewSun")
    if sun is None:
        data = bpy.data.lights.new("LGT_PreviewSun", "SUN")
        data.energy = 3.2
        sun = bpy.data.objects.new("LGT_PreviewSun", data)
        coll.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    if sc.world is None or sc.world.name != "GS_PreviewWorld":
        world = bpy.data.worlds.get("GS_PreviewWorld") or bpy.data.worlds.new("GS_PreviewWorld")
        world.use_nodes = True
        nt = world.node_tree
        bg = nt.nodes.get("Background") or nt.nodes.new("ShaderNodeBackground")
        out = nt.nodes.get("World Output") or nt.nodes.new("ShaderNodeOutputWorld")
        nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
        bg.inputs["Color"].default_value = (0.62, 0.74, 0.86, 1.0)
        bg.inputs["Strength"].default_value = 0.9
        sc.world = world
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 720
    sc.render.resolution_y = 720
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    return cam


def aim(cam, eye, target, lens=50.0):
    cam.location = Vector(eye)
    direction = Vector(target) - Vector(eye)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


def show_body(style, props=()):
    for obj in bpy.data.objects:
        if obj.name.startswith(("SPEC_Body_", "GSP_")) and obj.parent is not None and obj.parent.name == G.RIG:
            visible = obj.name == "SPEC_Body_" + style or obj.name in props
            obj.hide_viewport = not visible
            obj.hide_render = not visible


def set_pose(action_name, frame):
    sc = G.scene()
    rig = bpy.data.objects[G.RIG]
    if rig.animation_data is None:
        rig.animation_data_create()
    if action_name:
        action = bpy.data.actions[action_name]
        rig.animation_data.action = action
        if hasattr(rig.animation_data, "action_slot") and len(action.slots):
            rig.animation_data.action_slot = action.slots[0]
    else:
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
    sc.frame_set(int(frame))


def render(path):
    sc = G.scene()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def render_pose(style, action_name, frame, path, props=(), eye=(1.6, -3.4, 1.5), target=(0, 0, 1.0), lens=45.0):
    cam = ensure_preview()
    aim(cam, eye, target, lens)
    show_body(style, props)
    set_pose(action_name, frame)
    return render(path)
