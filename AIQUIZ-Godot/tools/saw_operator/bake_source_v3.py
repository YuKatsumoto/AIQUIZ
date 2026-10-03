"""Bake the Godot-evaluated v3 operator motion into the GodotConsole_V3 workbench.

Run tests/saw_operator_export_poses.gd first, then in the live Blender:
    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_operator/bake_source_v3.py', encoding='utf-8').read(),
         {'bake_from': 1, 'bake_to': 400})   # then 401-800, ... (keeps each call short)
Keys the REF plush rig, the console controls and the deck slide/drop at 30fps with
timeline markers per motion. The runtime GLB stays unanimated: Godot evaluates it.
"""
import bpy, json
from mathutils import Matrix

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
scene = bpy.data.scenes['GodotConsole_V3']
bpy.context.window.scene = scene
data = json.load(open(ROOT + '/assets/hazards/saw_operator/source/evaluated_poses_v3.json', encoding='utf-8'))
poses = data['poses']
FIRST = globals().get('bake_from', 1)
LAST = min(globals().get('bake_to', len(poses)), len(poses))
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Godot Y-up -> Blender Z-up
rig = bpy.data.objects['REF_Rig']
movers = [bpy.data.objects['ConsoleV3'], bpy.data.objects['REF_OperatorStation']]
controls = {name: bpy.data.objects[name] for name in poses[0]['controls'] if name in bpy.data.objects}
if FIRST == 1:
    for o in movers + [rig] + list(controls.values()):
        o.animation_data_clear()
        o.rotation_mode = 'XYZ' if o.type != 'ARMATURE' else o.rotation_mode
for bone in rig.pose.bones:
    bone.rotation_mode = 'QUATERNION'
scene.render.fps = int(data['fps'])
scene.frame_start, scene.frame_end = 1, poses[-1]['frame']
for row in poses[FIRST - 1:LAST]:
    f = row['frame']
    for o in movers:
        o.location = (0, 2.25 * row['extension'], -.628274 * row['lowering'])
        o.keyframe_insert('location', frame=f)
    for name, o in controls.items():
        o.matrix_basis = C @ Matrix(row['controls'][name]) @ C.inverted()
        o.keyframe_insert('location', frame=f)
        o.keyframe_insert('rotation_euler', frame=f)
    # glTF bones keep their longitudinal local Y axis; only the world basis changes.
    for bone in rig.pose.bones:
        desired = C @ Matrix(row['bones'][bone.name])
        if bone.parent:
            parent_desired = C @ Matrix(row['bones'][bone.parent.name])
            bone.matrix_basis = bone.bone.matrix_local.inverted() @ bone.parent.bone.matrix_local @ parent_desired.inverted() @ desired
        else:
            bone.matrix_basis = bone.bone.matrix_local.inverted() @ desired
        bone.keyframe_insert('location', frame=f)
        bone.keyframe_insert('rotation_quaternion', frame=f)
scene.timeline_markers.clear()
for name, frame in sorted(data['markers'].items(), key=lambda kv: kv[1]):
    scene.timeline_markers.new(name, frame=frame)
scene.frame_set(data['markers'].get('Start: slam', 1))
result = {'baked': [FIRST, LAST], 'total': len(poses), 'controls': sorted(controls), 'markers': len(scene.timeline_markers)}
