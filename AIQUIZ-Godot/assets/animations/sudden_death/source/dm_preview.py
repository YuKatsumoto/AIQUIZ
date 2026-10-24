"""Workbench stills of baked SD_* clips for checking (run after dm_lib.py / dm_clips.py).

    ns["preview"]("SD_Jump_Basic_A", info, [0.0, 0.2, 0.4], out_dir)   # -> list of PNG paths

The armature object is moved along the clip's root (drop_moves.json) so the stills show the path:
a box for the ramp ends at the edge; landing clips get the podium floor 4 m below.
"""
import bpy
from mathutils import Vector

PREVIEW = "DM_Preview"


def _preview_collection():
    sc = scene()
    coll = bpy.data.collections.get(PREVIEW)
    if coll is None:
        coll = bpy.data.collections.new(PREVIEW)
        sc.collection.children.link(coll)
    return coll


def _box(name, center, size, color):
    coll = _preview_collection()
    obj = bpy.data.objects.get(name)
    if obj is None:
        mesh = bpy.data.meshes.new(name)
        import bmesh
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        coll.objects.link(obj)
    obj.location = Vector(center)
    obj.scale = Vector(size)
    obj.color = (*color, 1.0)
    obj.hide_render = False
    return obj


def _camera():
    coll = _preview_collection()
    cam = bpy.data.objects.get("DM_Cam")
    if cam is None:
        cam = bpy.data.objects.new("DM_Cam", bpy.data.cameras.new("DM_Cam"))
        coll.objects.link(cam)
    scene().camera = cam
    return cam


def _look(obj, eye, target):
    obj.location = Vector(eye)
    obj.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()


def _setup_render(path):
    sc = scene()
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "OBJECT"
    sc.display.shading.show_shadows = False
    sc.render.resolution_x = 420
    sc.render.resolution_y = 420
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path


def root_at(info, t):
    root = info["root"]
    f = max(0.0, min(t * FPS, len(root) - 1))
    i = int(f)
    j = min(i + 1, len(root) - 1)
    a, b = Vector(root[i]), Vector(root[j])
    return a.lerp(b, f - i)


def preview(name, info, times, out_dir, mode="track", tag=""):
    sc = scene()
    action = bpy.data.actions[name]
    ad = rig.animation_data or rig.animation_data_create()
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    ad.action = action
    if len(action.slots):
        ad.action_slot = action.slots[0]
    sc.frame_set(0)
    p0 = (rig.matrix_world.inverted() @ rig.matrix_world @ rig.pose.bones["pelvis"].head).copy()
    rig.color = (0.95, 0.55, 0.2, 1.0)
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.parent == rig:
            obj.color = (0.95, 0.55, 0.2, 1.0)
    mesh = bpy.data.objects.get("Mannequin")
    if mesh is not None:
        mesh.color = (0.95, 0.55, 0.2, 1.0)
    edge = info.get("edge")
    floor = None
    if edge is not None:
        front = p0.y - edge
        _box("DM_Ramp", (0, front + 3.0, -0.1), (2.2, 6.0, 0.2), (0.55, 0.58, 0.62))
        if info.get("kind") == "land":
            floor = _box("DM_Floor", (0, front - 6.0, -LAND_DROP - 0.1), (8.0, 16.0, 0.2), (0.35, 0.6, 0.4))
    else:
        _box("DM_Ramp", (0, 0, -0.1), (4.0, 8.0, 0.2), (0.55, 0.58, 0.62))
    if floor is None and bpy.data.objects.get("DM_Floor"):
        bpy.data.objects["DM_Floor"].hide_render = True
    if info.get("kind") == "box":
        bpy.data.objects["DM_Ramp"].hide_render = True
    cam = _camera()
    cam.data.lens = 35
    paths = []
    for i, t in enumerate(times):
        f = t * FPS
        sc.frame_set(int(f), subframe=f - int(f))
        r = root_at(info, t)
        pa = rig.pose.bones["pelvis"].head
        rig.location = Vector((p0.x + r.x - pa.x, p0.y - r.z - pa.y, r.y))
        bpy.context.view_layer.update()
        pw = rig.matrix_world @ rig.pose.bones["pelvis"].head
        if mode == "track":
            _look(cam, pw + Vector((3.4, -2.2, 1.0)), pw + Vector((0, 0, -0.1)))
        elif mode == "front":
            _look(cam, pw + Vector((0.6, -4.0, 0.6)), pw)
        elif mode == "top":
            _look(cam, pw + Vector((0.01, 1.2, 4.0)), pw)
        else:
            _look(cam, Vector((7.5, -1.5, 0.2)), Vector((0, -1.5, -1.0)))
        path = "%s/%s%s_%02d.png" % (out_dir, name, tag, i)
        _setup_render(path)
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    rig.location = Vector((0, 0, 0))
    ad.action = None
    return paths
