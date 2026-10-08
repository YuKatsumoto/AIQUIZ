"""Put ハテナ (HATENA_Parts, built by build_hatena.py) on the 16-bone mascot rig and export
mascot_model.glb.

ハテナ is the quiz spirit whose round body is the dot of an orange "?". Its parts are built at
the rig's rest proportions, so they are only weighted and joined here.
Run inside the live Blender (Higgsfield bridge), with aiquiz_mascot.blend open, one stage per call:

    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/fit_hatena.py',
              encoding='utf-8').read(), {'fit_stage': 'build'})

  'build'   the parts are baked to meshes (modifiers applied), weighted per part, joined into
            HERO_Mascot (in MASCOT_Final) and parented to 'Rig'; the previous HERO_Mascot (カモメ船長)
            is kept hidden as HERO_Mascot_Kamome
  'export'  ../mascot_model.glb (Rig + HERO_Mascot, no animations)

Weights, by part:
  body      DEF-hips -> DEF-head between z 0.78 and 0.95, so the face height follows the head
  face, "?" crest and its collar  DEF-head
  arms      shoulder ball DEF-upper_arm; upper arm / forearm blended at the elbow by x along the
            chain; elbow ball DEF-forearm; hand and thumb DEF-hand
  legs      hip ball DEF-thigh; thigh / shin blended at the knee (z 0.384); knee ball DEF-shin;
            shoe, sole and cuff DEF-foot, the shoe front DEF-toe
Each joint ball is centred on its bone's head, so it turns in place.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
ASSET = ROOT + '/assets/characters/aiquiz_mascot'
STAGE = globals().get('fit_stage', 'build')
PARTS = 'HATENA_Parts'
KNEE_Z = 0.384
ELBOW_X = 0.649
JOINT_BLEND = 0.035
SHARP_ANGLE = math.radians(40)


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def part_weights(part, p):
    """Bone weights for a vertex at p (rig space) of the concept part named part."""
    side = 'L' if p.x >= 0 else 'R'
    if part == 'Body':
        t = smooth(0.78, 0.95, p.z)
        return {'DEF-head': t, 'DEF-hips': 1.0 - t}
    if part in ('Eye', 'EyeHi', 'EyeHi2', 'Cheek', 'Mouth', 'Crest', 'CrestBall', 'CrestCollar'):
        return {'DEF-head': 1.0}
    if part == 'Shoulder':
        return {'DEF-upper_arm.' + side: 1.0}
    if part in ('UpperArm', 'Forearm'):
        t = smooth(ELBOW_X - JOINT_BLEND, ELBOW_X + JOINT_BLEND, abs(p.x))
        return {'DEF-upper_arm.' + side: 1.0 - t, 'DEF-forearm.' + side: t}
    if part == 'Elbow':
        return {'DEF-forearm.' + side: 1.0}
    if part in ('Hand', 'Thumb'):
        return {'DEF-hand.' + side: 1.0}
    if part == 'HipBall':
        return {'DEF-thigh.' + side: 1.0}
    if part in ('Thigh', 'Shin'):
        t = smooth(KNEE_Z + JOINT_BLEND, KNEE_Z - JOINT_BLEND, p.z)
        return {'DEF-thigh.' + side: 1.0 - t, 'DEF-shin.' + side: t}
    if part == 'Knee':
        return {'DEF-shin.' + side: 1.0}
    if part in ('Sole', 'Collar'):
        return {'DEF-foot.' + side: 1.0}
    if part == 'Shoe':
        toe = smooth(-0.11, -0.17, p.y)
        return {'DEF-foot.' + side: 1.0 - toe, 'DEF-toe.' + side: toe}
    raise ValueError('unknown part ' + part)


def part_of(name):
    # H_UpperArm.L -> UpperArm
    return name[2:].split('.')[0]


def bake(ob):
    """The evaluated object as a new mesh in rig space (the rig sits at the origin)."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(ob.matrix_world)
    return me


def sharpen(me):
    """Smooth shading with hard edges only where faces meet at more than SHARP_ANGLE (shoe and
    cylinder caps), the same split the glTF exporter keeps."""
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > SHARP_ANGLE:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()


def stage_build():
    rig = bpy.data.objects['Rig']
    final = bpy.data.collections['MASCOT_Final']
    src = bpy.data.collections[PARTS]
    old = bpy.data.objects.get('HERO_Mascot')
    if old is not None:
        if old.get('hatena'):
            bpy.data.objects.remove(old, do_unlink=True)
        else:
            keep = 'HERO_Mascot_Kamome' if old.get('generated') else 'HERO_Mascot_Prev'
            stale = bpy.data.objects.get(keep)
            if stale is not None:
                bpy.data.objects.remove(stale, do_unlink=True)
            old.name = keep
            old.data.name = keep
            old.hide_set(True)
            old.hide_render = True
    bone_names = [b.name for b in rig.data.bones]
    pieces = []
    counts = {}
    for ob in sorted(src.objects, key=lambda o: o.name):
        if ob.type != 'MESH':
            continue
        part = part_of(ob.name)
        me = bake(ob)
        piece = bpy.data.objects.new('HERO_part_' + ob.name[2:], me)
        final.objects.link(piece)
        groups = {n: piece.vertex_groups.new(name=n) for n in bone_names}
        for v in me.vertices:
            for name, w in part_weights(part, v.co).items():
                if w > 1e-4:
                    groups[name].add([v.index], w, 'REPLACE')
                    counts[name] = counts.get(name, 0) + 1
        pieces.append(piece)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for p in pieces:
        p.select_set(True)
    hero = pieces[0]
    bpy.context.view_layer.objects.active = hero
    bpy.ops.object.join()
    hero.name = 'HERO_Mascot'
    hero.data.name = 'HERO_Mascot'
    hero['hatena'] = True
    sharpen(hero.data)
    hero.parent = rig
    hero.matrix_parent_inverse = rig.matrix_world.inverted()
    hero.modifiers.new('Armature', 'ARMATURE').object = rig
    me = hero.data
    bad = sum(1 for v in me.vertices if abs(sum(g.weight for g in v.groups) - 1.0) > 0.02)
    xs = [v.co.x for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    return {'verts': len(me.vertices), 'tris': sum(len(p.vertices) - 2 for p in me.polygons), 'bad_weights': bad,
            'x_range': [round(min(xs), 3), round(max(xs), 3)], 'z_range': [round(min(zs), 3), round(max(zs), 3)],
            'per_bone': counts, 'materials': [m.name for m in me.materials]}


def stage_export():
    rig = bpy.data.objects['Rig']
    hero = bpy.data.objects['HERO_Mascot']
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in (rig, hero):
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = ASSET + '/mascot_model.glb'
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_skins=True,
                              export_animations=False, export_morph=False, export_apply=False,
                              export_yup=True, export_cameras=False, export_lights=False,
                              export_image_format='AUTO')
    return {'glb': path, 'bytes': os.path.getsize(path)}


result = {'build': stage_build, 'export': stage_export}[STAGE]()
