"""Contact sheet of crowd clips: one posed copy of RIG_Spectator per cell (EEVEE).

Copies live in GS_PreviewSheet (never exported). Each cell is
(label, action, frame, hair, props, offset) and pair cells can share a row:

    pv = {}; exec(open(".../preview_crowd_extras.py", encoding="utf-8").read(), pv)
    pv["sheet"]([("Gasp", "SPEC_Gasp", 8, "Short", (), None), ...], "C:/.../sheet.png")
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

ns = {}
exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
G = type("G", (), ns)
SHEET = "GS_PreviewSheet"
SCENE_FRAME = 200
CELL_X = 1.75
CELL_Z = 2.55


def clear():
    coll = bpy.data.collections.get(SHEET)
    if coll is None:
        return
    for obj in list(coll.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def _copy_rig(name):
    src = bpy.data.objects[G.RIG]
    rig = src.copy()
    rig.name = name
    rig.animation_data_clear()
    bpy.data.collections[SHEET].objects.link(rig)
    rig.show_in_front = False
    rig.hide_render = True
    return rig


def _copy_mesh(src_name, rig, name):
    src = bpy.data.objects[src_name]
    obj = src.copy()
    obj.name = name
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    for mod in obj.modifiers:
        if mod.type == "ARMATURE":
            mod.object = rig
    obj.hide_viewport = False
    obj.hide_render = False
    bpy.data.collections[SHEET].objects.link(obj)
    return obj


def _pose(rig, action_name, frame):
    ad = rig.animation_data or rig.animation_data_create()
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    ad.action = None
    if not action_name:
        return
    action = bpy.data.actions[action_name]
    track = ad.nla_tracks.new()
    strip = track.strips.new(action_name, int(SCENE_FRAME - frame), action)
    if hasattr(strip, "action_slot") and len(action.slots):
        strip.action_slot = action.slots[0]
    strip.extrapolation = "HOLD"


def _label(text, location):
    curve = bpy.data.curves.new("PRV_Label_" + text, "FONT")
    curve.body = text
    curve.size = 0.16
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new("PRV_Label_" + text, curve)
    obj.location = location
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.data.collections[SHEET].objects.link(obj)
    return obj


KID_SCALE = 0.62


def kid_matrix(carrier, seat):
    """The kid follows the carrier's neck as if skinned to it: the neck's deform
    (pose @ rest^-1) applied to a seat point given in the carrier's rest space."""
    pb = carrier.pose.bones["neck_01"]
    deform = pb.matrix @ pb.bone.matrix_local.inverted()
    return carrier.matrix_world @ deform @ Matrix.Translation(seat) @ Matrix.Diagonal((KID_SCALE,) * 3 + (1.0,))


def sheet(cells, path, columns=5, lens_scale=1.0, eye_y=-12.0):
    """cells: (label, action, frame, hair, props, attach) where attach is None, or
    ("pair", dx) to stand dx metres right of the previous cell, or
    ("kid", carrier_label) to sit on the carrier's neck (kid scale)."""
    sc = G.scene()
    G.collection(SHEET)
    clear()
    placed = {}
    col = row = 0
    rigs = []
    kids_pending = []
    for label, action_name, frame, hair, props, attach in cells:
        rig = _copy_rig("PRV_Rig_" + label)
        if attach is not None and attach[0] == "pair":
            prev = rigs[-1]
            rig.location = prev.location + Vector((attach[1], 0, 0))
        elif attach is not None and attach[0] == "kid":
            # Placed after posing (kids()), like GoalStand does in Godot.
            rig.location = Vector((0, 0, 0))
            kids_pending.append((rig, placed[attach[1]], Vector(attach[2])))
        else:
            rig.location = Vector((col * CELL_X, 0.0, -row * CELL_Z))
            col += 1
            if col >= columns:
                col = 0
                row += 1
        _copy_mesh("SPEC_Body_" + hair, rig, "PRV_Body_" + label)
        for prop in props:
            _copy_mesh(prop, rig, "PRV_" + prop + "_" + label)
        _pose(rig, action_name, frame)
        if attach is None or attach[0] == "pair":
            _label(label, rig.location + Vector((0, 0, -0.22)))
        placed[label] = rig
        rigs.append(rig)
    sc.frame_set(SCENE_FRAME)
    bpy.context.view_layer.update()
    for kid, carrier, seat in kids_pending:
        kid.matrix_world = kid_matrix(carrier, seat)
    bpy.context.view_layer.update()
    # Orthographic front camera around every placed rig (characters face -Y).
    xs = [r.matrix_world.translation.x for r in rigs]
    zs = [r.matrix_world.translation.z for r in rigs]
    cam = bpy.data.objects.get("CAM_PreviewSheet")
    if cam is None:
        cam = bpy.data.objects.new("CAM_PreviewSheet", bpy.data.cameras.new("CAM_PreviewSheet"))
        bpy.data.collections[SHEET].objects.link(cam)
    elif cam.name not in bpy.data.collections[SHEET].objects:
        bpy.data.collections[SHEET].objects.link(cam)
    width = max(xs) - min(xs) + CELL_X
    height = max(zs) - min(zs) + CELL_Z
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, height * 1.0) * 1.04 * lens_scale
    centre = Vector(((max(xs) + min(xs)) / 2.0, eye_y, (max(zs) + min(zs)) / 2.0 + 0.95))
    cam.location = centre
    cam.rotation_euler = (math.radians(90), 0, 0)
    sun = bpy.data.objects.get("LGT_PreviewSheetSun")
    if sun is None:
        data = bpy.data.lights.new("LGT_PreviewSheetSun", "SUN")
        data.energy = 3.0
        sun = bpy.data.objects.new("LGT_PreviewSheetSun", data)
        bpy.data.collections[SHEET].objects.link(sun)
    sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
    if sc.world is None:
        world = bpy.data.worlds.get("GS_PreviewWorld") or bpy.data.worlds.new("GS_PreviewWorld")
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        if bg is not None:
            bg.inputs["Color"].default_value = (0.62, 0.74, 0.86, 1.0)
            bg.inputs["Strength"].default_value = 0.9
        sc.world = world
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    aspect = width / max(height, 0.1)
    sc.render.resolution_x = 1400 if aspect >= 1.0 else int(1400 * aspect)
    sc.render.resolution_y = int(1400 / aspect) if aspect >= 1.0 else 1400
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    # Hide the source rig's own meshes while rendering the sheet.
    hidden = []
    for obj in bpy.data.objects:
        if obj.parent is not None and obj.parent.name == G.RIG and not obj.hide_render:
            obj.hide_render = True
            hidden.append(obj)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for obj in hidden:
        obj.hide_render = False
    return path
