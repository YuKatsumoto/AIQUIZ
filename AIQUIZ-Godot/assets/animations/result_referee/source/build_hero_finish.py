"""Editable hero finish, evaluated in the connected Blender scene.

Geometry, materials, other scenes and old action datablocks are retained.
Run build() after the pre-edit recovery checkpoint. export_hero_finish.py
exports evaluated referee, loser and carrier motion for Godot. The winning
player's equipped FBX supplies the dance in Godot, on this forward carrier.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix, Euler, Quaternion

ROOT = Path('C:/AIQUIZ/AIQUIZ-Godot')
SOURCE = ROOT / 'assets/animations/result_referee/source'
OUT = ROOT / 'artifacts/result_ceremony/hero_low_angle_20260924'
FPS = 60
HIT, RELEASE, BURST, FREEZE = 6.68, 6.76, 7.58, 9.10
C = Matrix.Rotation(math.pi / 2, 4, 'X')
CI = C.inverted()


def curves(ob):
    if not ob.animation_data or not ob.animation_data.action:
        return []
    action = ob.animation_data.action
    slot = ob.animation_data.action_slot.handle
    return [fc for layer in action.layers for strip in layer.strips
            for cb in strip.channelbags if cb.slot_handle == slot for fc in cb.fcurves]


def preserve_clear(ob):
    if ob.animation_data and ob.animation_data.action:
        ob.animation_data.action.use_fake_user = True
    ob.animation_data_clear()


def key(ob, prop, samples):
    for seconds, value in samples:
        setattr(ob, prop, value)
        ob.keyframe_insert(data_path=prop, frame=seconds * FPS, group=getattr(ob, 'name', 'Motion'))


def smooth(ob):
    for fc in curves(ob):
        for point in fc.keyframe_points:
            point.interpolation = 'BEZIER'
            point.handle_left_type = point.handle_right_type = 'AUTO_CLAMPED'


def bone(rig, name, samples):
    p = rig.pose.bones[name]
    p.rotation_mode = 'XYZ'
    key(p, 'rotation_euler', [(t, tuple(math.radians(v) for v in a)) for t, a in samples])


def joint(prefix, name, samples):
    ob = bpy.data.objects[prefix + name]
    ob.rotation_mode = 'QUATERNION'
    values = []
    previous = None
    for t, angles in samples:
        q = (C @ Euler(tuple(math.radians(v) for v in angles), 'YXZ').to_matrix().to_4x4() @ CI).to_quaternion()
        if previous is not None and previous.dot(q) < 0:
            q.negate()
        values.append((t, q))
        previous = q
    key(ob, 'rotation_quaternion', values)


def blend(a, b, x):
    x = max(0, min(1, x))
    return a + (b - a) * (x * x * (3 - 2 * x))


def empty(scene, name):
    ob = bpy.data.objects.get(name)
    if ob is None:
        ob = bpy.data.objects.new(name, None)
        scene.collection.objects.link(ob)
        ob.empty_display_size = .1
    return ob


def foot_path(start, finish, time, depart, land, lift=.12):
    u = max(0, min(1, (time - depart) / (land - depart)))
    p = start.lerp(finish, u * u * (3 - 2 * u))
    p.z += math.sin(math.pi * u) ** 2 * lift
    return p


def solve_player_feet(prefix, root_pos, yaw, feet, rest):
    """Two rigid 45 cm links. Plant world ankles, with a forward knee pole."""
    root = bpy.data.objects[prefix + 'Actor']
    qroot = Quaternion((0, 0, 1), yaw)
    hip_local = {side: Vector(rest[prefix + side + '_hip']['location']) + Vector(rest[prefix + 'pelvis']['location']) for side in ('l', 'r')}
    # Lower the pelvis only as much as required to keep both limbs in reach.
    for side in ('l', 'r'):
        hp = root_pos + qroot @ hip_local[side]
        horizontal = Vector((hp.x - feet[side].x, hp.y - feet[side].y, 0)).length
        max_height = math.sqrt(max(.01, .894 ** 2 - horizontal ** 2))
        root_pos.z = min(root_pos.z, feet[side].z + max_height - hip_local[side].z)
    root.location = root_pos
    root.rotation_mode = 'QUATERNION'
    root.rotation_quaternion = qroot
    for side in ('l', 'r'):
        target = qroot.inverted() @ (feet[side] - root_pos)
        delta = target - hip_local[side]
        distance = min(.899, max(.1, delta.length))
        axis = delta.normalized()
        pole = qroot.inverted() @ Vector((0, -1, 0))
        bend = (pole - axis * pole.dot(axis)).normalized()
        knee = hip_local[side] + axis * distance * .5 + bend * math.sqrt(max(0, .45 ** 2 - (distance * .5) ** 2))
        upper_q = Vector((0, 0, -1)).rotation_difference((knee - hip_local[side]).normalized())
        lower_q = Vector((0, 0, -1)).rotation_difference(upper_q.inverted() @ (target - knee).normalized())
        ankle_q = (qroot @ upper_q @ lower_q).inverted()
        for suffix, q in [('_hip', upper_q), ('_knee', lower_q), ('_ankle', ankle_q)]:
            ob = bpy.data.objects[prefix + side + suffix]
            ob.rotation_mode = 'QUATERNION'
            ob.rotation_quaternion = q


def build():
    scene = bpy.data.scenes['AIQUIZ_RefereeFinish_v2']
    assert bpy.context.scene == scene
    rest = json.loads((SOURCE / 'hero_rest_pose.json').read_text(encoding='utf-8'))
    rig, bat, cam = [bpy.data.objects[n] for n in ('RIG_Referee', 'PRP_Bat', 'CAM_Result')]
    owned = [o for o in scene.objects if o.name.startswith(('WIN_', 'LOSE_', 'CTRL_Foot_'))] + [rig, bat, cam, cam.data]
    for ob in owned:
        preserve_clear(ob)
    for name, pose in rest.items():
        bpy.data.objects[name].matrix_basis = Matrix(pose['matrix'])
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    rig.location = (0, 0, 0)
    rig.rotation_mode = 'XYZ'
    rig.rotation_euler = (0, 0, 0)
    rig.scale = (1, 1, 1)
    scene.frame_start, scene.frame_end, scene.render.fps = 0, 600, FPS

    # The bat is visibly carried behind the plush from the first entrance.
    # Parenting to the rig object keeps it with the travelling body; the
    # non-stretch hand IK follows its grip continuously through retrieval.
    bat.parent = rig
    bat.matrix_parent_inverse = Matrix.Identity(4)
    bat.scale = (1, 1, 1)
    grip = bpy.data.objects['CTRL_Grip_L']
    grip.location = (0, 0, 0)
    hand_ik = rig.pose.bones['DEF-hand.L'].constraints.get('Bat grip L')
    hand_ik.target = grip
    hand_ik.chain_count = 3
    hand_ik.use_stretch = False
    hand_ik.influence = 1
    for p in rig.pose.bones:
        p.ik_stretch = 0

    # Six short steps, alternating world-space support feet. The foot bones
    # retain a level sole instead of sliding with a translating root.
    foot_controls = {}
    for side in ('L', 'R'):
        ctrl = empty(scene, 'CTRL_Foot_' + side)
        ctrl.parent = None
        ctrl.rotation_mode = 'QUATERNION'
        ctrl.rotation_quaternion = rig.data.bones['DEF-foot.' + side].matrix_local.to_quaternion()
        shin = rig.pose.bones['DEF-shin.' + side]
        ik = shin.constraints.get('Hero grounded ankle') or shin.constraints.new('IK')
        ik.name = 'Hero grounded ankle'
        ik.target, ik.chain_count, ik.use_stretch = ctrl, 2, False
        foot = rig.pose.bones['DEF-foot.' + side]
        orientation = foot.constraints.get('Hero level sole') or foot.constraints.new('COPY_ROTATION')
        orientation.name = 'Hero level sole'
        orientation.target = ctrl
        orientation.target_space = orientation.owner_space = 'WORLD'
        foot_controls[side] = ctrl
    for frame in range(601):
        t = frame / FPS
        walk_u = max(0, min(1, (t - .45) / 1.32))
        ry = .96 * (1 - walk_u)
        step_x = blend(0, .78, (t - 5.86) / .66)
        root_z = -.035 * math.sin(math.pi * walk_u * 6) ** 2 - .018 * math.sin(math.pi * max(0, min(1, (t - 6) / 1.3))) ** 2
        rig.location = (step_x, ry + blend(0, .12, (t - 5.86) / .66), root_z)
        rig.keyframe_insert('location', frame=frame)
        for side, sign, first in [('L', 1, 0), ('R', -1, 1)]:
            pos = Vector((sign * .186427, .97069, .177652))
            for step in range(first, 6, 2):
                start = .45 + step * .22
                end = start + .22
                destination = Vector((pos.x, .97069 - min(.96, (step + 1) * .16 + .08), .177652))
                if t >= end:
                    pos = destination
                elif t > start:
                    pos = foot_path(pos, destination, t, start, end, .075)
                    break
            turns = [((.18,-.16,.177652),5.86,6.05,28),((.63,-.09,.177652),6.17,6.37,83)] if side=='R' else [((.40,.25,.177652),6.01,6.20,58),((.87,.34,.177652),6.32,6.52,105)]
            foot_yaw = 0
            for destination, depart, land, yaw_degrees in turns:
                pos = foot_path(pos, Vector(destination), t, depart, land, .065)
                foot_yaw = blend(foot_yaw, math.radians(yaw_degrees), (t-depart)/(land-depart))
            settle = ((.845,-.06,.177652),6.77,7.05) if side=='R' else ((.715,.30,.177652),7.03,7.25)
            pos = foot_path(pos, Vector(settle[0]), t, settle[1], settle[2], .05)
            foot_yaw = blend(foot_yaw, math.radians(110), (t-settle[1])/(settle[2]-settle[1]))
            ctrl = foot_controls[side]
            ctrl.location = pos
            ctrl.rotation_quaternion = Quaternion((0,0,1),foot_yaw) @ rig.data.bones['DEF-foot.'+side].matrix_local.to_quaternion()
            ctrl.keyframe_insert('location', frame=frame)
            ctrl.keyframe_insert('rotation_quaternion', frame=frame)

    # Establish eye/body direction first; then coil and unwind through impact.
    key(rig,'rotation_euler',[(0,(0,0,0)),(5.86,(0,0,0)),(6.06,(0,0,math.radians(45))),
        (6.23,(0,0,math.radians(83))),(6.43,(0,0,math.radians(62))),
        (6.51,(0,0,math.radians(67))),(6.58,(0,0,math.radians(84))),
        (HIT,(0,0,math.radians(105))),(RELEASE,(0,0,math.radians(105))),
        (6.96,(0,0,math.radians(133))),(7.40,(0,0,math.radians(110))),
        (FREEZE,(0,0,math.radians(110))),(10,(0,0,math.radians(110)))])

    key(bat, 'location', [(0,(.70,.20,.62)), (1.90,(.70,.20,.62)), (2.18,(.66,.26,.77)),
        (2.45,(.74,.10,.91)), (2.72,(.78,-.10,.82)), (3.08,(.73,-.18,.62)),
        (6,(.73,-.18,.62)), (6.23,(.65,.04,.77)), (6.43,(.53,.22,.94)),
        (6.51,(.53,.22,.94)), (6.58,(.61,.03,.92)), (6.63,(.57,-.28,.85)),
        (HIT,(.52,-.32,.79)), (RELEASE,(.52,-.32,.79)), (6.94,(.32,-.24,.85)),
        (7.22,(.42,-.23,.77)), (7.70,(.64,-.18,.61)), (FREEZE,(.64,-.18,.61)), (10,(.64,-.18,.61))])
    directions = [(0,(-.16,.86,.50)), (1.9,(-.16,.86,.50)), (2.18,(-.1,.72,.70)),
        (2.45,(.12,.40,1)), (2.72,(.25,-.1,1)), (3.08,(.22,0,1)),
        (6,(.22,0,1)), (6.23,(.22,.25,1)), (6.43,(-.69,.76,.40)),
        (6.51,(-.69,.76,.40)), (6.58,(-1.0,0,.45)), (6.63,(-1.16,-.59,.35)),
        (HIT,(-.92,-1.0,.35)), (RELEASE,(-.92,-1.0,.35)), (6.94,(.39,-.98,.28)),
        (7.22,(-.7,.1,.7)), (7.70,(-.22,0,1)), (FREEZE,(-.22,0,1)), (10,(-.22,0,1))]
    bat.rotation_mode = 'QUATERNION'
    qs, previous = [], None
    for t, direction in directions:
        q = Vector(direction).to_track_quat('X','Z')
        if previous is not None and previous.dot(q) < 0: q.negate()
        qs.append((t,q.copy())); previous=q
    key(bat, 'rotation_quaternion', qs)
    bone(rig, 'DEF-head', [(0,(0,0,0)),(.45,(0,-5,-2)),(1.3,(0,4,2)),(1.9,(0,0,0)),
        (2.18,(0,12,3)),(2.45,(0,8,0)),(3.08,(0,0,0)),(4.0,(0,-8,0)),(4.7,(0,8,0)),(5.6,(0,0,0)),
        (6,(0,0,0)),(6.23,(0,0,0)),(6.43,(0,21,3)),(6.51,(0,16,3)),(6.58,(0,-1,1)),(6.63,(0,-14,-2)),
        (HIT,(0,-22,-3)),(RELEASE,(0,-22,-3)),(6.94,(0,-49,-2)),(7.7,(0,-27,0)),(FREEZE,(0,-27,0))])
    bone(rig, 'DEF-hips', [(0,(0,0,0)),(6,(0,0,0)),(6.43,(0,4,0)),
        (HIT,(0,-3,0)),(RELEASE,(0,-3,0)),(6.94,(0,-4,0)),(7.7,(0,0,0)),(FREEZE,(0,0,0))])
    bone(rig, 'DEF-upper_arm.R', [(0,(0,0,0)),(.55,(12,0,-8)),(.85,(-12,0,8)),(1.1,(12,0,-8)),
        (1.35,(-12,0,8)),(1.8,(0,0,0)),(2.35,(0,0,-12)),(3.1,(0,0,0)),
        (5.8,(0,0,0)),(6.1,(0,0,-24)),(6.43,(0,0,-30)),(6.51,(0,0,-30)),
        (6.63,(0,0,-12)),(HIT,(0,0,8)),(RELEASE,(0,0,8)),(6.94,(0,0,20)),(7.7,(0,0,-28)),(FREEZE,(0,0,-28))])
    bone(rig, 'DEF-forearm.R', [(0,(0,0,0)),(6,(0,0,0)),(6.23,(15,0,-15)),(6.51,(15,0,-15)),
        (HIT,(0,0,12)),(RELEASE,(0,0,12)),(6.94,(0,0,16)),(7.7,(15,0,-25)),(FREEZE,(15,0,-25))])

    # Player roots and supports. Before the cast handoff they match the
    # existing walk destination; only the torso/arms settle after handoff.
    for prefix, x in [('WIN_',-2.2),('LOSE_',2.2)]:
        root = bpy.data.objects[prefix+'Actor']
        root.location=(x,0,1.34)
        root.rotation_mode='QUATERNION';root.rotation_quaternion=Quaternion()
        key(root,'location',[(0,root.location.copy()),(6,root.location.copy())])
        key(root,'rotation_quaternion',[(0,Quaternion()),(6,Quaternion())])
        for side, sign in [('l',-1),('r',1)]:
            joint(prefix,side+'_shoulder',[(0,(0,0,sign*6)),(2,(0,0,sign*6)),(2.2,(-3,0,sign*7)),(2.6,(0,0,sign*6)),(6,(0,0,sign*6))])
        joint(prefix,'head_pivot',[(0,(0,0,0)),(2,(0,0,0)),(3.05,(0,(-10 if x<0 else 10),0)),(4.2,(0,0,0)),(5.6,(0,0,-3 if x<0 else 3)),(6,(0,0,0))])

    for frame in range(360, 601):
        t=frame/FPS
        wx=blend(-2.2,-2.25,(t-6.05)/1.18)
        wy=blend(0,-1.65,(t-6.05)/1.18)
        # Godot's equipped emote retargets limbs and plants its actual contact
        # geometry while this carrier advances. No canned victory pose there.
        bpy.data.objects['WIN_Actor'].location=(wx,wy,1.34)
        targets=[bpy.data.objects['WIN_Actor']]
        for ob in targets:
            if ob.name=='WIN_Actor':ob.keyframe_insert('location',frame=frame)
            ob.keyframe_insert('rotation_quaternion',frame=frame)
        if t<=RELEASE+1/FPS:
            local_t=min(t,HIT) if t>=HIT else t
            yaw=blend(0,math.pi/2,(local_t-6.06)/.40)
            lfeet={side:foot_path(Vector((2.2+sign*.22,0,.14)),Vector((2.2,sign*.24,.14)),local_t,*window,.10)
                   for side,sign,window in [('l',-1,(6.04,6.32)),('r',1,(6.24,6.48))]}
            solve_player_feet('LOSE_',Vector((2.2,0,1.34)),yaw,lfeet,rest)
            for ob in [bpy.data.objects['LOSE_Actor']]+[bpy.data.objects['LOSE_'+side+'_'+part] for side in ('l','r') for part in ('hip','knee','ankle')]:
                if ob.name=='LOSE_Actor':ob.keyframe_insert('location',frame=frame)
                ob.keyframe_insert('rotation_quaternion',frame=frame)

    joint('WIN_','spine',[(0,(0,0,0)),(6,(0,0,0)),(6.22,(8,0,-4)),(6.72,(-7,0,4)),(7.18,(-3,0,2)),(FREEZE,(-3,0,2))])
    joint('WIN_','r_shoulder',[(0,(0,0,6)),(6,(0,0,6)),(6.23,(-25,0,35)),(6.62,(-15,0,150)),(6.84,(-12,0,158)),(7.12,(-12,0,148)),(FREEZE,(-12,0,148))])
    joint('WIN_','r_elbow',[(0,(0,0,0)),(6,(0,0,0)),(6.23,(-80,0,0)),(6.62,(-55,0,0)),(7.12,(-50,0,0)),(FREEZE,(-50,0,0))])
    joint('WIN_','l_shoulder',[(0,(0,0,-6)),(6,(0,0,-6)),(6.28,(-20,0,-12)),(6.8,(-15,0,-28)),(7.15,(-15,0,-23)),(FREEZE,(-15,0,-23))])
    joint('WIN_','l_elbow',[(0,(0,0,0)),(6,(0,0,0)),(6.32,(-80,0,0)),(7.1,(-65,0,0)),(FREEZE,(-65,0,0))])
    joint('WIN_','head_pivot',[(0,(0,0,0)),(3,(0,-10,0)),(5.8,(0,0,-3)),(6.2,(-5,4,0)),(7.1,(-5,4,-4)),(FREEZE,(-5,4,-4))])
    for side in ('l','r'):
        for finger in ('index','middle','ring','pinky'):
            for segment,angle in [('prox',-72),('mid',-88),('dist',-50)]:
                joint('WIN_',f'{side}_{finger}_{segment}',[(0,(0,0,0)),(6,(0,0,0)),(6.34,(angle,0,0)),(FREEZE,(angle,0,0))])

    joint('LOSE_','spine',[(0,(0,0,0)),(6,(0,0,0)),(6.22,(12,0,0)),(6.48,(22,0,0)),(HIT,(26,0,0)),(RELEASE,(26,0,0)),(7.08,(-18,0,-8)),(BURST,(-24,0,-13)),(FREEZE,(-24,0,-13))])
    joint('LOSE_','head_pivot',[(0,(0,0,0)),(3,(0,10,0)),(5.8,(0,0,3)),(6.4,(-5,-60,0)),(HIT,(-5,-65,0)),(RELEASE,(-5,-65,0)),(7.1,(12,-20,10)),(BURST,(8,-8,-8)),(FREEZE,(8,-8,-8))])
    for side,sign in [('l',-1),('r',1)]:
        joint('LOSE_',side+'_shoulder',[(0,(0,0,sign*6)),(6,(0,0,sign*6)),(6.35,(-30,0,sign*15)),(HIT,(-48,0,sign*18)),(RELEASE,(-48,0,sign*18)),(7.10,(-25,0,sign*95)),(BURST,(-10,0,sign*120)),(FREEZE,(-10,0,sign*120))])
        joint('LOSE_',side+'_elbow',[(0,(0,0,0)),(6,(0,0,0)),(6.4,(-65,0,0)),(HIT,(-65,0,0)),(RELEASE,(-65,0,0)),(7.12,(-15,0,0)),(BURST,(-25,0,0)),(FREEZE,(-25,0,0))])

    loser=bpy.data.objects['LOSE_Actor']
    # Instant release velocity, deterministic ballistic arc into scene depth.
    launch_z=1.33
    for frame in range(math.ceil(RELEASE*FPS), 601):
        t=frame/FPS
        u=max(0,min(BURST-RELEASE,t-RELEASE))
        at_burst=Vector((2.2+2.8*u,4.5*u,launch_z+6.0*u-2.7*u*u))
        settle=max(0,min(1,(t-BURST)/(FREEZE-BURST)))
        p=at_burst+Vector((.20,.48,-.10))*(1-(1-settle)**3)
        loser.location=p
        loser.rotation_mode='QUATERNION'
        loser.rotation_quaternion=Euler((blend(0,.20,u/.82),blend(0,-.55,u/.82),blend(math.pi/2,.48,u/.82)),'XYZ').to_quaternion()
        loser.keyframe_insert('location',frame=frame)
        loser.keyframe_insert('rotation_quaternion',frame=frame)
    for side,sign in [('l',-1),('r',1)]:
        for part,angles in [('hip',(20*sign,0,sign*20)),('knee',(45,0,0)),('ankle',(-15,0,0))]:
            ob=bpy.data.objects['LOSE_'+side+'_'+part]
            # Keep the solved release pose, then trail the flying body.
            scene.frame_set(round(HIT*FPS))
            initial=ob.rotation_quaternion.copy()
            q=(C@Euler(tuple(math.radians(v) for v in angles),'YXZ').to_matrix().to_4x4()@CI).to_quaternion()
            key(ob,'rotation_quaternion',[(HIT,initial),(RELEASE,initial),(7.17,q),(FREEZE,q)])
    for name,offset in [('head_pivot',(0,0,.65)),('l_shoulder',(-.60,0,.24)),('r_shoulder',(.60,0,.23)),('l_hip',(-.44,0,-.25)),('r_hip',(.44,0,-.22))]:
        ob=bpy.data.objects['LOSE_'+name]
        base=Vector(rest[ob.name]['location'])
        key(ob,'location',[(0,base),(BURST,base),(8.1,base+Vector(offset)*.80),(FREEZE,base+Vector(offset)),(10,base+Vector(offset))])

    # Hips turn above two fixed supports. Lower the body to the reachable
    # two-link envelope rather than letting an IK endpoint lift off the floor.
    for frame in range(601):
        scene.frame_set(frame)
        dg=bpy.context.evaluated_depsgraph_get()
        evaluated=rig.evaluated_get(dg)
        correction=0.0
        for side in ('L','R'):
            hip=evaluated.matrix_world@evaluated.pose.bones['DEF-thigh.'+side].head
            target=foot_controls[side].matrix_world.translation
            horizontal=Vector((hip.x-target.x,hip.y-target.y,0)).length
            vertical_limit=math.sqrt(max(.001,.354**2-horizontal**2))
            correction=max(correction,hip.z-target.z-vertical_limit)
        if correction>0:
            rig.location.z-=correction
            rig.keyframe_insert('location',frame=frame)

    # Perspective camera: wide readable score shot -> fast low hero reveal.
    cam.data.type='PERSP';cam.data.sensor_fit='HORIZONTAL';cam.data.sensor_width=36;cam.data.clip_start=.05
    shots=[(0,(.65,-7.8,2.55),(0,0,1.25),27.5),(6,(.65,-7.8,2.55),(0,0,1.25),27.5),
           (6.50,(.45,-7.6,2.2),(.1,0,1.25),28),(HIT,(.45,-7.6,2.2),(.1,0,1.25),28),
           (RELEASE,(-.8,-6.4,1.4),(-.1,.15,1.65),25),
           (7.18,(-2.65,-4.10,.20),(-.4,.4,2.72),15.2),
           (7.36,(-2.7,-3.95,.16),(-.4,.4,2.8),14.8),
           (FREEZE,(-2.7,-3.95,.16),(-.4,.4,2.8),14.8),(10,(-2.7,-3.95,.16),(-.4,.4,2.8),14.8)]
    cam.rotation_mode='QUATERNION'
    for t,eye,target,lens in shots:
        cam.location=eye
        cam.rotation_quaternion=(Vector(target)-cam.location).to_track_quat('-Z','Y')
        cam.data.lens=lens
        cam.keyframe_insert('location',frame=t*FPS)
        cam.keyframe_insert('rotation_quaternion',frame=t*FPS)
        cam.data.keyframe_insert('lens',frame=t*FPS)
    scene.camera=cam
    for ob in owned+[*foot_controls.values()]:
        smooth(ob)
        if ob.animation_data and ob.animation_data.action:
            ob.animation_data.action.name='HeroFinish_'+ob.name
    # Sampled IK and ballistic carrier motion must not acquire easing per frame.
    for ob in [rig,*foot_controls.values(),bpy.data.objects['WIN_Actor'],loser]:
        for fc in curves(ob):
            if ob in [rig,*foot_controls.values()] or fc.data_path=='location':
                for point in fc.keyframe_points:
                    if len(fc.keyframe_points)>100: point.interpolation='LINEAR'
    for marker in list(scene.timeline_markers):
        scene.timeline_markers.remove(marker)
    for name,t in [('Entrance',.45),('Retrieve bat',2.18),('Ready',3.08),('Verdict',6),('Load',6.43),('Contact',HIT),('Release',RELEASE),('Low hero',7.36),('Background burst',BURST),('Final hold',FREEZE),('Interactive',10)]:
        scene.timeline_markers.new(name,frame=round(t*FPS))
    scene['hero_finish_version']=3
    scene['hero_finish_reference']='hero_low_angle_reference_20260924.png'
    scene.frame_set(500)
    return {'scene':scene.name,'version':3,'frames':[0,600],'contact':HIT,'release':RELEASE,'burst':BURST,'freeze':FREEZE,'camera':cam.name}


if __name__ == '__main__':
    result=build()
