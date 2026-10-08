"""Fit the generated カモメ船長 mesh onto the 16-bone mascot rig and export mascot_model.glb.

The mesh comes from Higgsfield (Meshy multi-image to 3D) built from four generated views
(concept_front/left/back/right.png, kept next to this file) and is saved here as
generated_meshy_multiview.glb. Run inside the live Blender (Higgsfield bridge), with
aiquiz_mascot.blend open, one stage per call:

    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/fit_generated.py',
              encoding='utf-8').read(), {'fit_stage': 'skin'})

  'skin'    GEN_Raw (the import, centred at the origin, front -Y) is copied to HERO_Mascot, lifted
            so the feet stand on z=0, weighted to the rig and parented to 'Rig'
  'export'  ../mascot_model.glb (Rig + HERO_Mascot, no animations)

At scale 1 the generated wings already hang where the rig's arms are (wing tips at x 0.88,
z 0.59 against the hand bone tip at 0.87 / 0.57), so the mesh is only lifted. Weights:
  wings  vertices clearly outside the body ellipsoid (and beyond |x| 0.55) between z 0.40 and
         1.05 follow the arm chain (upper arm / forearm / hand by their x along the chain),
         blended into the body over the wing root so the body side never follows the wing;
  legs   below the body: shin, foot under z 0.12, toe in front of y -0.15;
  body   everything else (hat, face, scarf, tail) blends DEF-hips -> DEF-head between z 0.74
         and 0.88, so a nod bends the body as the old plush did.
"""
import bpy, os
from mathutils import Vector, Matrix

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
ASSET = ROOT + '/assets/characters/aiquiz_mascot'
STAGE = globals().get('fit_stage', 'skin')
LIFT = 0.95
BODY_C = Vector((0.0, 0.0, 0.875))
BODY_R = Vector((0.585, 0.61, 0.58))
# Arm chain in x (the wings hang in the x/z plane): shoulder, elbow, wrist, hand tip.
CHAIN = ((0.52, 'DEF-upper_arm'), (0.649, 'DEF-forearm'), (0.760, 'DEF-hand'))
JOINT_BLEND = 0.035


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def body_weights(z):
    t = smooth(0.74, 0.88, z)
    return {'DEF-head': t, 'DEF-hips': 1.0 - t}


def arm_weights(x, side):
    """Bone weights along the arm chain for |x| = x, blending at the elbow and wrist."""
    w = {}
    names = [n for _, n in CHAIN]
    starts = [s for s, _ in CHAIN]
    for i, name in enumerate(names):
        lo = starts[i]
        hi = starts[i + 1] if i + 1 < len(starts) else 99.0
        a = 1.0 if i == 0 else smooth(lo - JOINT_BLEND, lo + JOINT_BLEND, x)
        b = 1.0 if i + 1 == len(starts) else 1.0 - smooth(hi - JOINT_BLEND, hi + JOINT_BLEND, x)
        v = a * b
        if v > 1e-4:
            w[name + '.' + side] = v
    total = sum(w.values()) or 1.0
    return {k: v / total for k, v in w.items()}


def weights_for(p):
    side = 'L' if p.x >= 0 else 'R'
    ax = abs(p.x)
    d = p - BODY_C
    e = ((d.x / BODY_R.x) ** 2 + (d.y / BODY_R.y) ** 2 + (d.z / BODY_R.z) ** 2) ** 0.5
    body = body_weights(p.z)
    if ax > 0.45 and 0.40 < p.z < 1.05:
        # only the flap outside the round body moves; the body side under it stays put
        arm = smooth(1.03, 1.12, e) * smooth(0.55, 0.65, ax)
        if arm > 0:
            out = {k: v * (1 - arm) for k, v in body.items()}
            for k, v in arm_weights(ax, side).items():
                out[k] = out.get(k, 0.0) + v * arm
            return out
    if p.z < 0.36 and ax < 0.45:
        legness = smooth(0.32, 0.26, p.z) if e < 1.02 else 1.0
        if p.z < 0.12:
            toe = smooth(-0.11, -0.17, p.y)
            leg = {'DEF-foot.' + side: 1 - toe}
            if toe > 0:
                leg['DEF-toe.' + side] = toe
        else:
            foot = smooth(0.17, 0.11, p.z)
            leg = {'DEF-shin.' + side: 1 - foot}
            if foot > 0:
                leg['DEF-foot.' + side] = foot
        out = {k: v * (1 - legness) for k, v in body.items()}
        for k, v in leg.items():
            out[k] = out.get(k, 0.0) + v * legness
        return out
    return body


def stage_skin():
    raw = bpy.data.objects['GEN_Raw']
    rig = bpy.data.objects['Rig']
    final = bpy.data.collections.get('MASCOT_Final')
    old = bpy.data.objects.get('HERO_Mascot')
    if old is not None:
        if old.data.name.startswith('HERO_Mascot') and 'generated' not in old:
            old.name = 'HERO_Mascot_Handmade'
            old.data.name = 'HERO_Mascot_Handmade'
        else:
            bpy.data.objects.remove(old, do_unlink=True)
    me = raw.data.copy()
    me.name = 'HERO_Mascot'
    me.transform(raw.matrix_world)
    me.transform(Matrix.Translation((0, 0, LIFT)))
    ob = bpy.data.objects.new('HERO_Mascot', me)
    ob['generated'] = True
    final.objects.link(ob)
    if rig.name not in final.objects:
        final.objects.link(rig)
    groups = {b.name: ob.vertex_groups.new(name=b.name) for b in rig.data.bones}
    counts = {}
    for v in me.vertices:
        for name, w in weights_for(v.co).items():
            if w > 1e-4:
                groups[name].add([v.index], w, 'REPLACE')
                counts[name] = counts.get(name, 0) + 1
    ob.parent = rig
    ob.matrix_parent_inverse = rig.matrix_world.inverted()
    ob.modifiers.new('Armature', 'ARMATURE').object = rig
    bad = sum(1 for v in me.vertices if abs(sum(g.weight for g in v.groups) - 1.0) > 0.02)
    zs = [v.co.z for v in me.vertices]
    return {'verts': len(me.vertices), 'bad_weights': bad, 'z_range': [round(min(zs), 3), round(max(zs), 3)],
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


result = {'skin': stage_skin, 'export': stage_export}[STAGE]()
