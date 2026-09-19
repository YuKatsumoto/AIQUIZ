"""Rebuild the existing shark's deform rig and independently playable clips.

Run in Blender's Text Editor or with --python. The current shark source must
be open. Geometry, UVs, texture, saddle and mount socket are retained.
"""
import bpy
import math
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
FPS = 30


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def body_weights(x):
    stations = [(-3.65, 'tail_03'), (-2.45, 'tail_02'),
                (-1.12, 'tail_01'), (0.30, 'body_02'),
                (1.75, 'body_01'), (3.05, 'head')]
    if x <= stations[0][0]:
        return {stations[0][1]: 1.0}
    for (a, na), (b, nb) in zip(stations, stations[1:]):
        if x <= b:
            t = smooth(a, b, x)
            return {na: 1.0 - t, nb: t}
    return {'head': 1.0}


def build_rig():
    rig = bpy.data.objects['shark_armature']
    mesh = bpy.data.objects['SK_Shark.001']
    assert len(mesh.data.vertices) == 5505, 'Unexpected source mesh'
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    # Keep the legacy body rest matrices, so existing rider clips and the
    # bone-parented mount socket retain their coordinate contract.
    legacy = [(b.name, b.head_local.copy(), b.tail_local.copy(),
               b.matrix_local.copy(), b.parent.name if b.parent else None)
              for b in rig.data.bones if b.name in ('root', 'body_01', 'body_02', 'tail_01', 'tail_02', 'tail_03')]
    old_data = rig.data
    rig.data = bpy.data.armatures.new('SharkDeformRig')
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    bones = rig.data.edit_bones
    for name, head, tail, matrix, parent in legacy:
        b = bones.new(name)
        b.head, b.tail = head, tail
        b.matrix = matrix
        b.length = (tail - head).length
        if parent:
            b.parent = bones[parent]
    definitions = [
        ('head', (2.65, 0, -0.32), (4.50, 0, -0.32), 'body_01'),
        ('jaw', (2.78, 0, -0.63), (3.78, 0, -0.63), 'head'),
        ('pectoral.L', (1.66, 0.54, -0.60), (0.95, 1.72, -1.51), 'body_01'),
        ('pectoral.R', (1.66, -0.54, -0.60), (0.95, -1.72, -1.51), 'body_01'),
    ]
    for name, head, tail, parent in definitions:
        b = bones.new(name)
        b.head, b.tail, b.roll = head, tail, 0.0
        b.parent = bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    if old_data.users == 0:
        bpy.data.armatures.remove(old_data)
    rig.data.display_type = 'STICK'
    rig.show_in_front = True
    rig.data.show_names = True
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.matrix_basis.identity()
    for group in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(group)
    groups = {b.name: mesh.vertex_groups.new(name=b.name) for b in rig.data.bones}
    for v in mesh.data.vertices:
        x, y, z = v.co
        weights = body_weights(x)
        fin = smooth(0.65, 1.3, abs(y)) * (1 - smooth(-0.7, -0.35, z))
        if fin > 0:
            weights = {n: w * (1 - fin) for n, w in weights.items()}
            weights['pectoral.L' if y > 0 else 'pectoral.R'] = fin
        weights = {n: w for n, w in weights.items() if w > 0.00001}
        total = sum(weights.values())
        for name, weight in weights.items():
            groups[name].add([v.index], weight / total, 'REPLACE')
    # Keep the saddle rigid at the shoulder; its original skin blended across
    # three bending bones and could shear the handles during a tail stroke.
    for obj in bpy.context.scene.objects:
        if obj.name.startswith('SharkSaddle_'):
            for group in list(obj.vertex_groups):
                obj.vertex_groups.remove(group)
            obj.vertex_groups.new(name='body_01').add(
                list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    rig['rig_version'] = 2
    rig['mouth_animation'] = 'disabled; original closed mouth retained'
    rig['animation_notes'] = 'SharkSwim: 1-49 loop; SharkBite: 1-13 closed-mouth strike/recover'
    return rig, mesh


def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def create_action(rig, name, frames, pose_func, loop=False):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old, do_unlink=True)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame in frames:
        pose = pose_func(frame)
        for bone in rig.pose.bones:
            bone.location = (0, 0, 0)
            bone.scale = (1, 1, 1)
            bone.rotation_euler = tuple(math.radians(v) for v in pose.get(bone.name, (0, 0, 0)))
            bone.keyframe_insert('rotation_euler', frame=frame, group=bone.name)
    action.use_frame_range = True
    action.frame_start, action.frame_end = min(frames), max(frames)
    action.use_cyclic = loop
    for fc in curves(action):
        for key in fc.keyframe_points:
            key.interpolation = 'BEZIER'
            key.handle_left_type = key.handle_right_type = 'AUTO_CLAMPED'
        if loop:
            fc.modifiers.new('CYCLES')
    return action


def swim_pose(frame):
    t = (frame - 1) / 48 * math.tau
    pose = {}
    # Relative joint angles accumulate down this rig. Keep the forebody
    # quiet and let a modest travelling wave grow toward the caudal fin.
    # Reference observations and measured mesh excursion: docs/shark_locomotion.md.
    for name, amplitude, delay in [('body_01', 0.65, 0), ('body_02', 1.8, 0.55),
                                    ('tail_01', 3.6, 1.2), ('tail_02', 5.5, 1.9),
                                    ('tail_03', 8.0, 2.5)]:
        pose[name] = (0, 0, amplitude * math.sin(t - delay))
    pose['head'] = (0, 0, -0.55 * math.sin(t))
    pose['pectoral.L'] = (0.35 * math.sin(t - 0.4), 0, 0)
    pose['pectoral.R'] = (-0.35 * math.sin(t - 0.4), 0, 0)
    return pose


BITE = {
    1: (0, 0, 0, 0),
    3: (0, 4, -3, -12),
    5: (0, 5, -4, -16),
    7: (0, -3, 2, 18),
    10: (0, 1, 1, -6),
    13: (0, 0, 0, 0),
}


def bite_pose(frame):
    jaw, head, body, tail = BITE[frame]
    return {'jaw': (jaw, 0, 0), 'head': (head, 0, 0),
            'body_01': (-body, 0, 0), 'body_02': (body * 0.5, 0, tail * 0.15),
            'tail_01': (0, 0, tail * 0.4), 'tail_02': (0, 0, tail * 0.65),
            'tail_03': (0, 0, tail),
            'pectoral.L': (-abs(head), 0, 0), 'pectoral.R': (abs(head), 0, 0)}


def build_actions(rig):
    swim = create_action(rig, 'SharkSwim', list(range(1, 50, 2)), swim_pose, True)
    bite = create_action(rig, 'SharkBite', list(BITE), bite_pose)
    # Retain all existing ghost actions. Explicit neutral tracks for the new
    # bones prevent stale head/jaw/fin poses after a runtime clip switch.
    for action in list(bpy.data.actions):
        if not action.name.startswith('Ghost'):
            continue
        rig.animation_data.action = action
        for fc in list(curves(action)):
            if 'pose.bones["jaw"]' in fc.data_path:
                for layer in action.layers:
                    for strip in layer.strips:
                        for bag in strip.channelbags:
                            if fc in bag.fcurves.values():
                                bag.fcurves.remove(fc)
                                break
        for name in ['head', 'jaw', 'pectoral.L', 'pectoral.R']:
            pb = rig.pose.bones[name]
            pb.rotation_euler = (0, 0, 0)
            pb.keyframe_insert('rotation_euler', frame=action.frame_start, group=name)
            pb.keyframe_insert('rotation_euler', frame=action.frame_end, group=name)
        action.use_fake_user = True
    rig.animation_data.action = swim
    return swim, bite


def export_runtime(rig):
    scene = bpy.context.scene
    scene.render.fps = FPS
    actions = [bpy.data.actions[n] for n in ['SharkSwim', 'SharkBite',
               'GhostRendezvousIdle', 'GhostMountReceive', 'GhostDeparture']]
    rig.animation_data.action = None
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
    for a in actions:
        t = rig.animation_data.nla_tracks.new()
        t.name = a.name
        # Export the rebuilt clips from time zero, without a one-frame hold
        # at each swim loop. Keep the legacy ghost clip timing unchanged.
        start = 0 if a.name in ('SharkSwim', 'SharkBite') else int(a.frame_start)
        s = t.strips.new(a.name, start, a)
        s.extrapolation = 'NOTHING'
    bpy.ops.object.select_all(action='DESELECT')
    selected = [rig] + [o for o in scene.objects if o.parent == rig]
    visibility = {o: (o.hide_get(), o.hide_render) for o in selected}
    for o in selected:
        o.hide_set(False)
        o.hide_render = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(HERE.parent / 'shark_swim.glb'), export_format='GLB',
        use_selection=True, use_active_scene=True, export_animations=True, export_skins=True,
        export_animation_mode='NLA_TRACKS', export_merge_animation='NLA_TRACK',
        export_force_sampling=True, export_frame_range=False,
        export_apply=False, export_yup=True)
    for obj, (hidden, hidden_render) in visibility.items():
        obj.hide_set(hidden)
        obj.hide_render = hidden_render
    # Saved Blender source plays ONE action, with no overlapping NLA tracks.
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
    rig.animation_data.action = actions[0]
    scene.frame_start, scene.frame_end = 1, 48
    scene.frame_set(1)


def main():
    mesh = bpy.data.objects['SK_Shark.001']
    original = bpy.data.meshes.get('SharkOriginalMesh_PreLipSplit')
    if original is None:
        original = mesh.data.copy()
        original.name = 'SharkOriginalMesh_PreLipSplit'
        original.use_fake_user = True
    else:
        mesh.data = original.copy()
    rig, mesh = build_rig()
    mouth = {'original_topology_preserved': True, 'opening_disabled': True}
    build_actions(rig)
    export_runtime(rig)
    bpy.context.scene['shark_preview_help'] = 'Action Editor: SharkSwim (1-48), SharkBite (1-13). Space to play.'
    return {'bones': list(rig.data.bones.keys()), 'vertices': len(mesh.data.vertices), 'mouth': mouth,
            'actions': [(a.name, list(a.frame_range)) for a in bpy.data.actions],
            'glb': str(HERE.parent / 'shark_swim.glb')}


if __name__ == '__main__':
    result = main()
    print(json.dumps(result))
