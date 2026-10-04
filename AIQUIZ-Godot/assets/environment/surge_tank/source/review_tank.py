"""Review cameras and renders of the surge tank (LIVE Blender, Cycles).

    ns = {"__name__": "tank_review"}
    exec(open(".../source/review_tank.py", encoding="utf-8").read(), ns)
    ns["render"]("official", samples=64)       # -> source/previews/review_<name>.png

Cameras are given in Godot space (eye, target, vertical fov), trench floor y = 0, x = -v, z = 132.8 - u, and
match the reference photographs listed in docs/surge_tank_reproduction.md as closely as the survey allows.
"""
import math

import bpy
from mathutils import Vector

_ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/tank_common.py", encoding="utf-8").read(), _ns)
C = type("C", (), _ns)

VIEWS = {
    # name: (eye, target, vertical fov deg[, shift_y, (res_x, res_y)])
    # the official photo itself, matched: level camera, perspective-corrected (horizon at 463 of 540 px), f = 400 px
    "official_match": ((0.0, 1.6, -32.9), (0.0, 1.6, 30.0), 68.0, 0.357, (505, 540)),
    # official photo (gaikaku.jp): from the visitor area toward the pumps along the centre line, pillars of the
    # odd lines on the axis, lamps hanging from the transverse beams
    "official": ((0.0, 1.6, -27.0), (0.0, 7.0, 30.0), 62.0),
    # Street View 2007 style: eye level in the trench between two lines, along the rows
    "aisle": ((7.0, 1.6, 7.0), (7.0, 2.6, 60.0), 75.0),
    # the shaft-side end: openings, pier, fence, the shaft wall lit from above (slider_02)
    "shaft_end": ((0.0, 1.7, -20.0), (0.0, 6.0, -60.0), 58.0),
    # the four intake channels at the pump end ("altars")
    "pump_end": ((0.0, 1.7, 105.0), (0.0, 6.5, 135.0), 68.0),
    # visitor access: walkway and steel stair from the trench
    "stairs": ((-6.0, 1.7, -4.0), (-30.0, 4.0, -19.0), 62.0),
    # along the shelf and the side wall catwalk
    "shelf": ((-30.0, 6.7, -8.0), (-31.0, 9.0, 60.0), 70.0),
    # coffers and lamps overhead
    "overhead": ((10.0, 1.6, 20.0), (10.0, 16.0, 34.0), 80.0),
    # the trench edge: slope, shelf, pillars on the crest
    "trench_edge": ((3.0, 1.6, 35.0), (-24.0, 3.5, 50.0), 64.0),
}


def camera(name="official"):
    eye, target, fov = VIEWS[name][:3]
    shift = VIEWS[name][3] if len(VIEWS[name]) > 3 else 0.0
    cam_data = bpy.data.cameras.get("CAM_Review") or bpy.data.cameras.new("CAM_Review")
    cam = bpy.data.objects.get("CAM_Review") or bpy.data.objects.new("CAM_Review", cam_data)
    col = bpy.data.collections.get("TK_Review") or bpy.data.collections.new("TK_Review")
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    if cam.name not in col.objects:
        for c in list(cam.users_collection):
            c.objects.unlink(cam)
        col.objects.link(cam)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle = math.radians(fov)
    cam_data.shift_x = 0.0
    cam_data.shift_y = shift
    cam_data.clip_start = 0.05
    cam_data.clip_end = 800.0
    e = C.g2b(eye)
    t = C.g2b(target)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(name="official", samples=64, res=(1280, 720)):
    bns = {"__name__": "tank_bake_review"}
    exec(open(C.SOURCE + "/bake_tank.py", encoding="utf-8").read(), bns)
    bns["_hall_mode"]()
    camera(name)
    if len(VIEWS[name]) > 4:
        res = VIEWS[name][4]
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = "PNG"
    path = "%s/review_%s.png" % (C.PREVIEWS, name)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return {"file": path}
