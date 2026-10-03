"""Wall speed tab stow v2 for the linked chip saw carriage: four corner davit towers.

Built in the live Blender 5.1 session (Higgsfield Bridge) inside
assets/hazards/linked_saw_carriage_source/linked_saw_carriage.blend:

    STAGE = 'bones'
    exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_stow/build_stow.py', encoding='utf-8').read())

Every stage is idempotent; run them in order (details: assets/hazards/linked_saw_carriage_source/README.md):
    cleanup   remove the v1 stow (Boom/Head/PostUp/PostDn/Mast/Hinge bones and parts, v1 action)
    bones     ram, davit, knuckle, fly and jaw bones; the rest pose is the folded tower
    blockout  blockout meshes parented to the new bones in REST pose (superseded by detail)
    detail    hard-surface parts: lofted sections, bevels, weighted normals, boolean holes
    rig       controls, load path, Follow Path, IK drivers, ram drivers, Child Of blade hand-off
    motion    Stow and Deploy timelines: S-curve F-curves on the controls and bones, pose markers
    dynamics  rigid-body springs for tower sway, pick-up sag and blade rocking, fed back by drivers
    bake      simulate each clip in its own forward time and bake every bone (NLA tracks)
    export    GLB with the baked clips; the stow parts join into one skinned mesh
    sidecar   assets/hazards/linked_saw_carriage_stow.json (events, wall/chair spans, speed curves)
    audit     BVH interference, clearance and speed (AUDIT_CLIP='Stow'/'Deploy' = baked clip)
    verify    v1 hashes and rests unchanged, clip ends exact, Stow(p) vs Deploy(L - p)
    transport stowed towers against the service vessel (tests/saw_stow_dock_export.gd first)
    review / frames   renders from the review cameras (artifacts/saw_stow/v2/blender/)
Never start background Blender with --factory-startup: it drops the extension wheels here.

Carriage space: x across the belt, y travel, z up, belt surface z = 0.
New bones point along +Y with roll 0, so each bone's local axes match the world axes
at rest: luff/fold/tilt rotate about local Y, stages slide along local Z, jaws along local Y.
Godot samples the baked Stow/Deploy clips (SawChaseController); the rig here stays editable.
"""
import bpy, bmesh, math, json, os, time
from mathutils import Matrix, Vector

ROOT = 'C:/AIQUIZ/AIQUIZ-Godot'
OUT = ROOT + '/artifacts/saw_stow/v2/blender'
SCENE = 'CUTLINE | 8-blade carriage'
FPS = 24 # Spin_Loop is 80 frames = 3.333 s at 24 fps; the scene must stay at 24 fps.
ARM, COLL, RIG_COLL = 'Carriage_Motion_Rig', 'SAW_Import', 'CTL_StowRig'

# Blades and drive modules.
X0 = [-10.5 + 3.0 * i for i in range(8)]
X1 = [-10.5, -9.65, -8.8, -7.95, 7.95, 8.8, 9.65, 10.5] # racked module x, pitch 0.85 m
SIDE = [-1, -1, -1, -1, 1, 1, 1, 1]
RANK = [3, 2, 1, 0, 0, 1, 2, 3] # lift/tilt ripple from the centre outward
A_HUB = 0.1075 # tilt pin -> blade centre (spindle stub)
RAM_BASE_Z = 0.13 # ram base inside the sealed bearing housing (top z 0.334)
PIV0, PIV1 = 0.2525, 2.20 # tilt pin height at rest / lifted (upright blade bottom 0.75)
CLEVIS_DROP = 0.11 # pin -> clevis underside, where ram stage C ends
RAM_R = (0.080, 0.064, 0.050) # stage A/B/C tube radii
RAM_LAP = 0.06 # overlap of consecutive ram stages
RAM_REST_LEN = (PIV0 - CLEVIS_DROP - RAM_BASE_Z + 2 * RAM_LAP) / 3 # 0.044, hidden in the housing

# Davit towers: corner, side s (x sign), end e (y sign).
CORNERS = (('LF', -1, 1), ('LA', -1, -1), ('RF', 1, 1), ('RA', 1, -1))
# The service vessel's lift-bay corner posts stand at |x| >= 12.275, |y| 1.14..1.66 and reach z 0.605 once
# the lift is up: the carriage rises between them and then rolls past them. Every stowed tower part stays
# inside |x| 12.26 there, and outside the walls (|x| 11.9) everywhere (transport audit: stage 'transport').
PIV_X, PIV_Y, PIV_Z = 12.10, 1.76, 0.68
KNEE_IN = 12.04 # knee bracket plate on the bogie's outboard spine (x 12.03..12.21, y 1.602..1.61)
DRUM_R = 0.125 # luff rotary actuator; the base stage starts inside it at the pivot
N_STAGE = 6
STAGE_LEN, STAGE_LIP, S1_BELOW, STAGE_LAP = 0.95, 0.035, 0.0, 0.20
STAGE_SEC = [(0.24 - 0.014 * k, 0.17 - 0.014 * k) for k in range(N_STAGE)] # (x, y) outer section, 2 mm running gap
COLLAR_STEP, STAGE_WALL = 0.008, 0.005 # head collar proud of the body; wall to the cavity
TIP_REST = STAGE_LEN - S1_BELOW + STAGE_LIP * (N_STAGE - 1) # 1.005 collapsed tip above the pivot
PIN_BELOW_TIP = 0.12
PIN_REST = TIP_REST - PIN_BELOW_TIP # 0.885 knuckle pin above the pivot (z 1.635)
EXT_MAX = (STAGE_LEN - STAGE_LAP) * (N_STAGE - 1) # 3.75 total telescoping
BEAM_Y, BEAM_D, BEAM_H = 1.55, 0.14, 0.22 # beam centre |y|, depth (y), height
BODY_LEN, FLY_LEN, FLY_EXT = 1.0, 0.92, 0.715
JAW_IN, JAW_OUT = 0.425, 1.275 # jaw offsets along the beam (body / fly tips extended)
JAW_TIP, JAW_REACH, JAW_FINGER = 1.47, 0.15, 0.15 # retracted fingertip |y|; grips the blade face at |y| 1.32-1.45

# Load path of the knuckle pin (= rack centre at hub height), right side; mirrored by s.
XC_PICK = (X1[4] + X1[7]) / 2 + A_HUB # 9.3325
XC_PARK = XC_PICK + 6.0 # 15.3325: parked hubs x 14.0575..16.6075
HUB_OVER, HUB_PARK = 3.85, -1.90 # blade bottoms 2.40 over the station, tops 0.45 below the belt
XC_CLEAR_IN = 10.72 # rack reaches the operator station box from here outward
LIFT_OFF = 0.30 # vertical lift-off before the rise arc
Q_REST = (PIV_X, PIV_Z + PIN_REST)

# Motion limits (m, s) and timeline anchors. The user asked for a ~12 s stow, so the two long
# moves (gather, carry) peak at 4.5 m/s; everything else stays at or below 3 m/s.
BRAKE = 1.30 # blade spin-down (Godot integrates 1 - S(p / brake)); blade motion interlocked after it
LIM_LIFT = (2.0, 3.0, 14.0) # V, A, J of the ram lift
TILT_START_PIN = 0.70 # the blade tilts while it rises; its lowest edge stays >= 0.7 m
LIM_TILT = (math.radians(130), math.radians(320), math.radians(1600))
LIM_GATHER = (4.5, 4.5, 25.0)
GATHER_SLACK = [0.0, 0.0, 0.7, 0.7, 0.7, 0.7, 0.0, 0.0] # s before a blade must be >= 60 deg once the gather starts
LIM_DAVIT = (1.8, 1.6, 6.0, 2.0) # V, A, J, lateral accel of the tower deploy
LIM_CARRY = (4.5, 4.5, 25.0, 4.0) # V, A, J, lateral accel
LIM_DESCENT = (4.5, 4.5, 25.0)

MAT = {'yellow': 'End caps | safety amber', 'charcoal': 'Frame | charcoal powder coat', 'chrome': '02 | machined edge steel',
       'alu': 'Hardware | satin aluminum', 'black': 'Recesses | black oxide', 'rubber': 'Rollers | graphite rubber'}
LEGACY_PREFIX = ('Mast_', 'Hinge_', 'Boom_', 'Head_', 'PostUp_', 'PostDn_')

REPORT = {}

def scene():
    s = bpy.data.scenes[SCENE]
    if bpy.context.window: bpy.context.window.scene = s
    elif bpy.context.scene != s: raise RuntimeError(f'background session must open with {SCENE!r} active')
    return s

def rig():
    return bpy.data.objects[ARM]

def sname(s): return 'L' if s < 0 else 'R'

def ensure_collection(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or scene().collection).children.link(c)
    return c

def set_mode(obj, mode):
    vl = bpy.context.view_layer
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in vl.objects: o.select_set(False)
    vl.objects.active = obj; obj.select_set(True)
    if mode != 'OBJECT': bpy.ops.object.mode_set(mode=mode)

class RestPose:
    """Evaluate world matrices in the armature REST pose (bone-parented placement)."""
    def __enter__(self):
        self.a = rig(); self.prev = self.a.data.pose_position
        self.a.data.pose_position = 'REST'; bpy.context.view_layer.update()
    def __exit__(self, *exc):
        self.a.data.pose_position = self.prev; bpy.context.view_layer.update()

# ---------------------------------------------------------------- cleanup
def stage_cleanup():
    a = rig()
    removed = []
    for o in list(bpy.data.objects):
        if o.name.startswith(LEGACY_PREFIX) and o.name != ARM:
            me = o.data if o.type == 'MESH' else None
            removed.append(o.name); bpy.data.objects.remove(o)
            if me and me.users == 0: bpy.data.meshes.remove(me)
    set_mode(a, 'EDIT')
    eb = a.data.edit_bones
    gone = [b.name for b in eb if b.name.startswith(LEGACY_PREFIX)]
    for n in gone: eb.remove(eb[n])
    set_mode(a, 'OBJECT')
    ad = a.animation_data
    for tr in [t for t in ad.nla_tracks if t.name in ('Stow', 'Deploy')]: ad.nla_tracks.remove(tr)
    for n in ('Stow', 'Deploy'):
        act = bpy.data.actions.get(n)
        if act and act.get('stow_v2_baked') is None: bpy.data.actions.remove(act)
    REPORT['cleanup'] = {'objects': len(removed), 'bones': gone}

# ---------------------------------------------------------------- bones
def bone_specs():
    specs = []
    for i, x in enumerate(X0):
        k = f'{i + 1:02d}'
        specs.append((f'Ram_{k}', f'Slide_{k}', (x, 0, RAM_BASE_Z)))
        for st in 'ABC': specs.append((f'Ram{st}_{k}', f'Ram_{k}', (x, 0, RAM_BASE_Z)))
        specs.append((f'Hinge_{k}', f'Ram_{k}', (x, 0, PIV0)))
        specs.append((f'Tilt_{k}', f'Hinge_{k}', (x, 0, PIV0)))
    for c, s, e in CORNERS:
        px, py = s * PIV_X, e * PIV_Y
        specs.append((f'Davit_{c}', 'Carriage', (px, py, PIV_Z)))
        prev = f'Davit_{c}'
        for n in range(2, N_STAGE + 1):
            specs.append((f'DavitS{n}_{c}', prev, (px, py, PIV_Z - S1_BELOW + STAGE_LIP * (n - 1))))
            prev = f'DavitS{n}_{c}'
        pin = (px, e * BEAM_Y, PIV_Z + PIN_REST)
        specs.append((f'Knuckle_{c}', prev, pin))
        specs.append((f'BeamFlyP_{c}', f'Knuckle_{c}', pin))
        specs.append((f'BeamFlyN_{c}', f'Knuckle_{c}', pin))
        for j, (host, off) in enumerate(jaw_hosts(c)):
            specs.append((f'Jaw_{c}_{j + 1}', host, (px, e * JAW_TIP, PIV_Z + PIN_REST + off)))
    return specs

def jaw_hosts(c):
    """(parent bone, rest offset along the folded beam = world z) for jaws 1..4."""
    rest_out = JAW_OUT - FLY_EXT
    return ((f'BeamFlyN_{c}', -rest_out), (f'Knuckle_{c}', -JAW_IN), (f'Knuckle_{c}', JAW_IN), (f'BeamFlyP_{c}', rest_out))

def stage_bones():
    a = rig()
    set_mode(a, 'EDIT')
    eb = a.data.edit_bones
    made = []
    for name, parent, head in bone_specs():
        b = eb.get(name) or eb.new(name)
        b.head = head; b.tail = Vector(head) + Vector((0, 0.2, 0)); b.roll = 0.0
        b.parent, b.use_connect = eb[parent], False
        b.use_deform = True # the exported stow parts are one mesh skinned rigidly to these bones
        b.inherit_scale = 'FULL'
        made.append(name)
    eb['Carriage'].use_deform = True
    set_mode(a, 'OBJECT')
    for name in made:
        pb = a.pose.bones[name]
        pb.rotation_mode = 'XYZ'
        pb.location = (0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
    REPORT['bones'] = {'count': len(made), 'total': len(a.data.bones)}

# ---------------------------------------------------------------- geometry helpers
def bm_box(bm, mn, mx):
    t = bmesh.new(); bmesh.ops.create_cube(t, size=1.0)
    for v in t.verts: v.co = Vector([(mn[i] + mx[i]) / 2 + v.co[i] * (mx[i] - mn[i]) for i in range(3)])
    _merge(bm, t)

def bm_cyl(bm, r, z0, z1, seg=24, axis='Z', at=(0, 0, 0)):
    t = bmesh.new()
    bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=z1 - z0)
    bmesh.ops.translate(t, verts=t.verts, vec=Vector((0, 0, (z0 + z1) / 2)))
    if axis == 'Y': bmesh.ops.rotate(t, verts=t.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    if axis == 'X': bmesh.ops.rotate(t, verts=t.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    bmesh.ops.translate(t, verts=t.verts, vec=Vector(at))
    _merge(bm, t)

def _merge(dst, src):
    me = bpy.data.meshes.new('_tmp'); src.to_mesh(me); src.free(); dst.from_mesh(me); bpy.data.meshes.remove(me)

def part(name, bone, bm, mat, world_origin, tag='stow_v2'):
    """Mesh object with vertices given in world (rest) coordinates, parented to a bone."""
    me = bpy.data.meshes.get(name) or bpy.data.meshes.new(name)
    bmesh.ops.translate(bm, verts=bm.verts, vec=-Vector(world_origin))
    bm.to_mesh(me); bm.free()
    me.materials.clear(); me.materials.append(bpy.data.materials[MAT[mat]] if mat in MAT else bpy.data.materials[mat])
    o = bpy.data.objects.get(name)
    if o is None:
        o = bpy.data.objects.new(name, me); bpy.data.collections[COLL].objects.link(o)
    o.data = me
    a = rig()
    o.parent, o.parent_type, o.parent_bone = a, 'BONE', bone
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.matrix_world = Matrix.Translation(world_origin)
    o['saw_src'] = True; o[tag] = True
    for p in me.polygons: p.use_smooth = False
    return o

# ---------------------------------------------------------------- blockout
def stage_blockout():
    made = []
    with RestPose():
        for i, x in enumerate(X0):
            k = f'{i + 1:02d}'
            base = (x, 0, RAM_BASE_Z)
            for st, r in zip('ABC', RAM_R):
                bm = bmesh.new(); bm_cyl(bm, r, 0.0, RAM_REST_LEN, 28, at=base)
                bm_cyl(bm, r + 0.009, RAM_REST_LEN * 0.94, RAM_REST_LEN, 28, at=base) # gland lip at the tube top
                made.append(part(f'Ram{st}_{k} | chrome tube', f'Ram{st}_{k}', bm, 'chrome', base).name)
            pin = (x, 0, PIV0)
            bm = bmesh.new() # clevis block under the pin + two cheeks clearing the 0.079 m shaft
            bm_box(bm, (x - 0.065, -0.11, PIV0 - 0.11), (x + 0.065, 0.11, PIV0 - 0.085))
            bm_box(bm, (x - 0.065, 0.086, PIV0 - 0.085), (x + 0.065, 0.11, PIV0 + 0.065))
            bm_box(bm, (x - 0.065, -0.11, PIV0 - 0.085), (x + 0.065, -0.086, PIV0 + 0.065))
            made.append(part(f'Hinge_{k} | clevis block', f'Hinge_{k}', bm, 'charcoal', pin).name)
            bm = bmesh.new(); bm_cyl(bm, 0.026, -0.1225, 0.1225, 20, 'Y', at=pin)
            made.append(part(f'Tilt_{k} | trunnion pin', f'Tilt_{k}', bm, 'alu', pin).name)
            bm = bmesh.new(); bm_cyl(bm, 0.032, 0.1225, 0.1325, 20, 'Y', at=pin); bm_cyl(bm, 0.032, -0.1325, -0.1225, 20, 'Y', at=pin)
            made.append(part(f'Tilt_{k} | pin caps', f'Tilt_{k}', bm, 'yellow', pin).name)
        for c, s, e in CORNERS:
            px, py = s * PIV_X, e * PIV_Y
            pv = (px, py, PIV_Z)
            # Fixed knee bracket from the bogie spine end to the luff drum, and the drum housing.
            bm = bmesh.new()
            ylo, yhi = sorted((e * 1.605, e * 1.835))
            bm_box(bm, (min(s * KNEE_IN, s * (PIV_X + 0.12)), ylo, 0.36), (max(s * KNEE_IN, s * (PIV_X + 0.12)), yhi, 0.52))
            bm_box(bm, (min(s * (PIV_X - 0.10), s * (PIV_X + 0.12)), ylo, 0.52), (max(s * (PIV_X - 0.10), s * (PIV_X + 0.12)), yhi, 0.66))
            made.append(part(f'DavitBase_{c} | knee bracket', 'Carriage', bm, 'charcoal', pv).name)
            bm = bmesh.new(); bm_cyl(bm, 0.115, -0.075, 0.075, 32, 'Y', at=pv)
            made.append(part(f'DavitBase_{c} | luff drum', 'Carriage', bm, 'yellow', pv).name)
            for n in range(1, N_STAGE + 1):
                sx, sy = STAGE_SEC[n - 1]
                z0 = PIV_Z - S1_BELOW + STAGE_LIP * (n - 1)
                bm = bmesh.new(); bm_box(bm, (px - sx / 2, py - sy / 2, z0), (px + sx / 2, py + sy / 2, z0 + STAGE_LEN))
                bone = f'Davit_{c}' if n == 1 else f'DavitS{n}_{c}'
                made.append(part(f'{bone} | mast stage', bone, bm, 'yellow' if n % 2 else 'charcoal', (px, py, z0)).name)
            pin = (px, e * BEAM_Y, PIV_Z + PIN_REST)
            bm = bmesh.new() # side plate on the top stage carries the knuckle pin beside the beam
            ylo, yhi = sorted((e * (BEAM_Y + BEAM_D / 2 + 0.005), e * (PIV_Y + 0.02)))
            bm_box(bm, (px - 0.08, ylo, pin[2] - 0.08), (px + 0.08, yhi, pin[2] + 0.12))
            made.append(part(f'DavitS{N_STAGE}_{c} | knuckle plate', f'DavitS{N_STAGE}_{c}', bm, 'charcoal', pin).name)
            bm = bmesh.new() # beam body, folded vertical at rest (long axis = z)
            bm_box(bm, (px - BEAM_H / 2, e * BEAM_Y - BEAM_D / 2, pin[2] - BODY_LEN / 2), (px + BEAM_H / 2, e * BEAM_Y + BEAM_D / 2, pin[2] + BODY_LEN / 2))
            made.append(part(f'Knuckle_{c} | beam body', f'Knuckle_{c}', bm, 'yellow', pin).name)
            for fly, sign, dx in ((f'BeamFlyP_{c}', 1, 0.05), (f'BeamFlyN_{c}', -1, -0.05)):
                bm = bmesh.new()
                z_tip = pin[2] + sign * BODY_LEN / 2
                zlo, zhi = sorted((z_tip, z_tip - sign * FLY_LEN))
                bm_box(bm, (px + dx - 0.045, e * BEAM_Y - 0.05, zlo), (px + dx + 0.045, e * BEAM_Y + 0.05, zhi))
                made.append(part(f'{fly} | fly section', fly, bm, 'charcoal', pin).name)
            for j, (host, off) in enumerate(jaw_hosts(c)):
                jz = pin[2] + off
                bm = bmesh.new() # C jaw: two fingers straddling the blade plane + slide block in the beam
                ylo, yhi = sorted((e * JAW_TIP, e * (JAW_TIP + JAW_FINGER)))
                for fz in (-0.048, 0.048):
                    bm_box(bm, (px - 0.12, ylo, jz + fz - 0.013), (px + 0.12, yhi, jz + fz + 0.013))
                yb0, yb1 = sorted((e * (JAW_TIP + JAW_FINGER), e * (JAW_TIP + 0.20)))
                bm_box(bm, (px - 0.12, yb0, jz - 0.061), (px + 0.12, yb1, jz + 0.061))
                made.append(part(f'Jaw_{c}_{j + 1} | plate clamp', f'Jaw_{c}_{j + 1}', bm, 'black', (px, e * JAW_TIP, jz)).name)
            bm = bmesh.new() # beacon on the mast tip
            tip = (px + s * 0.06, py, PIV_Z + TIP_REST)
            bm_cyl(bm, 0.05, 0.0, 0.03, 20, at=tip); bm_cyl(bm, 0.042, 0.03, 0.12, 20, at=tip)
            made.append(part(f'DavitS{N_STAGE}_{c} | beacon', f'DavitS{N_STAGE}_{c}', bm, 'yellow', tip).name)
    REPORT['blockout'] = {'parts': len(made)}

# ---------------------------------------------------------------- detail (hard surface)
def chamfer_rect(w, d, c):
    a, b = w / 2, d / 2
    return [(a, -b + c), (a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c), (-a + c, -b), (a - c, -b)]

def circle(r, n=24):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]

def loft(bm, frame, stations, cap0=True, cap1=True):
    """Bridge equal-count profiles (u, v) at axial stations w along frame (origin, U, V, W)."""
    o, U, V, W = (Vector(x) for x in frame)
    rings = [[bm.verts.new(o + U * u + V * v + W * w) for u, v in prof] for w, prof in stations]
    n = len(rings[0])
    faces = []
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            if (r0[i].co - r1[i].co).length > 1e-7 or (r0[j].co - r1[j].co).length > 1e-7:
                faces.append(bm.faces.new((r0[i], r0[j], r1[j], r1[i])))
    if cap0: faces.append(bm.faces.new(list(reversed(rings[0]))))
    if cap1: faces.append(bm.faces.new(rings[-1]))
    # A left-handed frame (e.g. X, Z, Y) winds every face inward: the part renders inside out and its
    # back faces z-fight with whatever touches them (knuckle plate vs pin boss).
    if U.cross(V).dot(W) < 0.0: bmesh.ops.reverse_faces(bm, faces=faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    return bm

def tube_along(bm, path, r, n=10):
    """Hose: circles swept along a polyline of Vectors."""
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        a = t.orthogonal().normalized(); b = t.cross(a).normalized()
        rings.append([bm.verts.new(p + r * (math.cos(2 * math.pi * k / n) * a + math.sin(2 * math.pi * k / n) * b)) for k in range(n)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]))
    return bm

def hard_surface(o, width=0.006, segments=2, smooth=True):
    """Non-destructive bevel + weighted normals; applied only in the export copy."""
    for m in list(o.modifiers):
        if m.name in ('Bevel', 'WeightedNormal'): o.modifiers.remove(m)
    bv = o.modifiers.new('Bevel', 'BEVEL'); bv.width = width; bv.segments = segments
    bv.limit_method = 'ANGLE'; bv.angle_limit = math.radians(35); bv.harden_normals = True
    o.modifiers.new('WeightedNormal', 'WEIGHTED_NORMAL').keep_sharp = True
    for p in o.data.polygons: p.use_smooth = smooth
    return o

def beacon_material():
    m = bpy.data.materials.get('MAT_BeaconLens') or bpy.data.materials.new('MAT_BeaconLens')
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED') # node names follow the UI language
    bsdf.inputs['Base Color'].default_value = (1.0, 0.42, 0.03, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.18
    bsdf.inputs['Emission Color'].default_value = (1.0, 0.45, 0.04, 1.0)
    bsdf.inputs['Emission Strength'].default_value = 2.5
    return m

def remove_stow_parts():
    for o in [o for o in bpy.data.objects if o.get('stow_v2') or o.get('stow_cutter')]:
        me = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)

def cutter(name, bone, bm, world_origin):
    """Boolean cutter riding on the same bone; kept in the rig collection and never exported."""
    o = part(name, bone, bm, 'black', world_origin, tag='stow_cutter')
    del o['saw_src']
    for c in list(o.users_collection): c.objects.unlink(o)
    ensure_collection(RIG_COLL).objects.link(o)
    o.display_type = 'WIRE'; o.hide_render = True
    return o

def y_boss(bm, r, length, at, e, seg=8):
    """Cylinder along y growing outward (away from the carriage centre) from at."""
    lo, hi = sorted((0.0, e * length))
    bm_cyl(bm, r, lo, hi, seg, 'Y', at=at)

def stage_detail():
    remove_stow_parts()
    MAT['lens'] = beacon_material().name
    made = []
    def add(o):
        made.append(o.name); return o
    X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
    with RestPose():
        for i, x in enumerate(X0):
            k = f'{i + 1:02d}'
            base = (x, 0, RAM_BASE_Z)
            for st, r in zip('ABC', RAM_R):
                bm = bmesh.new(); bm_cyl(bm, r, 0.0, RAM_REST_LEN * 0.955, 32, at=base)
                add(part(f'Ram{st}_{k} | chrome tube', f'Ram{st}_{k}', bm, 'chrome', base))
                bm = bmesh.new(); bm_cyl(bm, r + 0.010, RAM_REST_LEN * 0.955, RAM_REST_LEN, 32, at=base)
                add(part(f'Ram{st}_{k} | gland wiper', f'Ram{st}_{k}', bm, 'black', base))
            pin = (x, 0, PIV0)
            bm = bmesh.new()
            loft(bm, ((x, 0, PIV0 - 0.11), X, Y, Z), [(0.0, chamfer_rect(0.13, 0.22, 0.012)), (0.025, chamfer_rect(0.13, 0.22, 0.012))])
            for sy in (-1, 1):
                loft(bm, ((x, sy * 0.098, PIV0 - 0.085), X, Y, Z), [(0.0, chamfer_rect(0.13, 0.024, 0.006)), (0.15, chamfer_rect(0.13, 0.024, 0.006))])
            add(hard_surface(part(f'Hinge_{k} | clevis block', f'Hinge_{k}', bm, 'charcoal', pin), 0.003))
            bm = bmesh.new()
            for sy in (-1, 1):
                for dx in (-0.04, 0.04): y_boss(bm, 0.009, 0.012, (x + dx, sy * 0.11, PIV0 - 0.10), sy)
            add(part(f'Hinge_{k} | clevis bolts', f'Hinge_{k}', bm, 'alu', pin))
            bm = bmesh.new(); bm_cyl(bm, 0.026, -0.1225, 0.1225, 24, 'Y', at=pin)
            add(part(f'Tilt_{k} | trunnion pin', f'Tilt_{k}', bm, 'alu', pin))
            bm = bmesh.new(); bm_cyl(bm, 0.032, 0.1225, 0.1325, 24, 'Y', at=pin); bm_cyl(bm, 0.032, -0.1325, -0.1225, 24, 'Y', at=pin)
            add(part(f'Tilt_{k} | pin caps', f'Tilt_{k}', bm, 'yellow', pin))
        for c, s, e in CORNERS:
            px, py = s * PIV_X, e * PIV_Y
            pv = (px, py, PIV_Z)
            x_in, x_out = sorted((s * KNEE_IN, s * (PIV_X + 0.12)))
            y_plate = sorted((e * 1.605, e * 1.625))
            y_shelf = sorted((e * 1.625, e * 1.672))
            y_cheek = sorted((e * 1.645, e * 1.672))
            # knee bracket: plate bolted to the bogie's outboard spine, shelf and one inboard cheek carrying the
            # drum on a stub axle. Nothing sits under the drum inside the mast's y span (|y| 1.675..1.845): at
            # deployed rest the tower hangs straight down past it (SawChaseController lays it there).
            bm = bmesh.new()
            bm_box(bm, (min(s * KNEE_IN, s * 12.20), y_plate[0], 0.36), (max(s * KNEE_IN, s * 12.20), y_plate[1], 0.54))
            bm_box(bm, (x_in, y_shelf[0], 0.36), (x_out, y_shelf[1], 0.40))
            bm_box(bm, (x_in, y_cheek[0], 0.40), (x_out, y_cheek[1], PIV_Z + 0.05))
            add(hard_surface(part(f'DavitBase_{c} | knee bracket', 'Carriage', bm, 'charcoal', pv), 0.004))
            bm = bmesh.new()
            lo_, hi_ = sorted((e * 1.655, e * (PIV_Y - 0.07)))
            bm_cyl(bm, 0.045, lo_, hi_, 24, 'Y', at=(px, 0, PIV_Z))
            add(part(f'DavitBase_{c} | drum stub axle', 'Carriage', bm, 'alu', pv))
            bm = bmesh.new()
            for xx in (12.08, 12.17): # on the plate, over the outboard spine
                for zz in (0.40, 0.50): y_boss(bm, 0.011, 0.018, (s * xx, e * 1.621, zz), e) # shank starts in the plate
            add(part(f'DavitBase_{c} | bracket bolts', 'Carriage', bm, 'alu', pv))
            ylo, yhi = sorted((e * (PIV_Y - 0.075), e * (PIV_Y + 0.075)))
            bm = bmesh.new()
            loft(bm, ((px, ylo, PIV_Z), X, Z, Y), [(0.0, circle(DRUM_R - 0.008, 40)), (0.008, circle(DRUM_R, 40)),
                                                   (yhi - ylo - 0.008, circle(DRUM_R, 40)), (yhi - ylo, circle(DRUM_R - 0.008, 40))])
            add(hard_surface(part(f'DavitBase_{c} | luff drum', 'Carriage', bm, 'yellow', pv), 0.003))
            bm = bmesh.new()
            bm_cyl(bm, DRUM_R - 0.03, ylo - 0.008, ylo, 32, 'Y', at=(px, 0, PIV_Z))
            bm_cyl(bm, DRUM_R - 0.03, yhi, yhi + 0.008, 32, 'Y', at=(px, 0, PIV_Z))
            add(part(f'DavitBase_{c} | drum caps', 'Carriage', bm, 'black', pv))
            bm = bmesh.new()
            for n in range(8):
                a_ = 2 * math.pi * n / 8
                for yy, sg in ((ylo, -1), (yhi, 1)):
                    lo_, hi_ = sorted((yy, yy + sg * 0.008))
                    bm_cyl(bm, 0.008, lo_, hi_, 8, 'Y', at=(px + 0.105 * math.cos(a_), 0, PIV_Z + 0.105 * math.sin(a_)))
            add(part(f'DavitBase_{c} | drum bolts', 'Carriage', bm, 'alu', pv))
            # telescopic mast stages: lofted box sections, proud head collar with cavity, wear pads
            for n in range(1, N_STAGE + 1):
                sx, sy_ = STAGE_SEC[n - 1]
                z0 = PIV_Z - S1_BELOW + STAGE_LIP * (n - 1)
                bone = f'Davit_{c}' if n == 1 else f'DavitS{n}_{c}'
                fr = ((px, py, z0), X, Y, Z)
                ch_ = 0.018
                bm = bmesh.new()
                loft(bm, fr, [(0.0, chamfer_rect(sx, sy_, ch_)), (STAGE_LEN - STAGE_LIP, chamfer_rect(sx, sy_, ch_))])
                add(hard_surface(part(f'{bone} | mast stage', bone, bm, 'yellow', (px, py, z0)), 0.004))
                bm = bmesh.new()
                wo, do = sx + COLLAR_STEP, sy_ + COLLAR_STEP
                wi, di = sx - 2 * STAGE_WALL, sy_ - 2 * STAGE_WALL
                loft(bm, fr, [(STAGE_LEN - STAGE_LIP, chamfer_rect(wo, do, ch_)), (STAGE_LEN, chamfer_rect(wo, do, ch_)),
                              (STAGE_LEN, chamfer_rect(wi, di, ch_ * 0.7)), (STAGE_LEN - 0.10, chamfer_rect(wi, di, ch_ * 0.7))])
                add(hard_surface(part(f'{bone} | head collar', bone, bm, 'charcoal', (px, py, z0)), 0.003))
                if n < N_STAGE:
                    bm = bmesh.new() # wear pads in the running gap around the next stage
                    nx, ny = STAGE_SEC[n]
                    zc = z0 + STAGE_LEN - 0.004
                    for u, v, hu, hv in ((nx / 2 + 0.001, 0, 0.001, ny * 0.35), (-nx / 2 - 0.001, 0, 0.001, ny * 0.35),
                                         (0, ny / 2 + 0.001, nx * 0.35, 0.001), (0, -ny / 2 - 0.001, nx * 0.35, 0.001)):
                        bm_box(bm, (px + u - hu, py + v - hv, zc - 0.02), (px + u + hu, py + v + hv, zc + 0.004))
                    add(part(f'{bone} | wear pads', bone, bm, 'black', (px, py, z0)))
                bm = bmesh.new()
                zc = z0 + STAGE_LEN - STAGE_LIP / 2
                for u in (-0.3, 0.3):
                    for side in (-1, 1):
                        lo_, hi_ = sorted((side * (sx + COLLAR_STEP) / 2, side * ((sx + COLLAR_STEP) / 2 + 0.006)))
                        bm_cyl(bm, 0.006, lo_, hi_, 8, 'X', at=(px, py + u * sy_, zc))
                add(part(f'{bone} | collar bolts', bone, bm, 'alu', (px, py, z0)))
            # Hose pair on the base stage's outboard face, into a bulkhead fitting 0.55 m up the stage:
            # luffed down to the park that face points at the belt's edge lights, so it stays short.
            bm = bmesh.new()
            sx0, sy0 = STAGE_SEC[0]
            for dy in (-0.035, 0.035):
                pts_ = [Vector((px + s * (sx0 / 2 + 0.016), py + dy, PIV_Z + 0.10 + 0.15 * i_)) for i_ in range(4)]
                tube_along(bm, pts_, 0.012, 8)
                lo_, hi_ = sorted((px + s * sx0 / 2, px + s * (sx0 / 2 + 0.022)))
                bm_cyl(bm, 0.019, lo_, hi_, 12, 'X', at=(0, py + dy, PIV_Z + 0.56))
            add(part(f'Davit_{c} | mast hoses', f'Davit_{c}', bm, 'rubber', pv))
            bm = bmesh.new() # hose clamps
            for zz in (PIV_Z + 0.22, PIV_Z + 0.45):
                lo_, hi_ = sorted((s * (sx0 / 2), s * (sx0 / 2 + 0.034)))
                bm_box(bm, (px + lo_, py - 0.06, zz - 0.012), (px + hi_, py + 0.06, zz + 0.012))
            add(part(f'Davit_{c} | hose clamps', f'Davit_{c}', bm, 'charcoal', pv))
            # knuckle: lug from the beam into the top stage, pin boss through the beam. The lug is narrower than
            # the stage and ends inside it: a face flush with any mast face z-fights (nested stages are 7 mm apart).
            pin = (px, e * BEAM_Y, PIV_Z + PIN_REST)
            sx6, sy6 = STAGE_SEC[-1]
            y0p, y1p = sorted((e * (BEAM_Y + BEAM_D / 2 + 0.006), e * (PIV_Y - sy6 / 2 + 0.01)))
            bm = bmesh.new()
            loft(bm, ((px, y0p, pin[2]), X, Z, Y), [(0.0, chamfer_rect(sx6 - 0.02, 0.22, 0.03)), (y1p - y0p, chamfer_rect(sx6 - 0.02, 0.22, 0.03))])
            add(hard_surface(part(f'DavitS{N_STAGE}_{c} | knuckle plate', f'DavitS{N_STAGE}_{c}', bm, 'charcoal', pin), 0.004))
            ylo, yhi = sorted((e * (BEAM_Y - BEAM_D / 2 - 0.008), e * (BEAM_Y + BEAM_D / 2 + 0.006)))
            bm = bmesh.new(); bm_cyl(bm, 0.045, ylo, yhi, 24, 'Y', at=(px, 0, pin[2]))
            add(part(f'Knuckle_{c} | pin boss', f'Knuckle_{c}', bm, 'alu', pin))
            # beam body: lofted box section along the folded beam axis (world z at rest), lightening holes
            bm = bmesh.new()
            loft(bm, ((px, e * BEAM_Y, pin[2] - BODY_LEN / 2), X, Y, Z),
                 [(0.0, chamfer_rect(BEAM_H, BEAM_D, 0.02)), (BODY_LEN, chamfer_rect(BEAM_H, BEAM_D, 0.02))])
            body = add(hard_surface(part(f'Knuckle_{c} | beam body', f'Knuckle_{c}', bm, 'yellow', pin), 0.005))
            bm = bmesh.new()
            for zz in (-0.21, 0.0, 0.21):
                bm_cyl(bm, 0.042, -BEAM_D, BEAM_D, 24, 'Y', at=(px, e * BEAM_Y, pin[2] + zz))
            cut = cutter(f'Knuckle_{c} | hole cutter', f'Knuckle_{c}', bm, pin)
            bo = body.modifiers.new('Holes', 'BOOLEAN'); bo.object = cut; bo.operation = 'DIFFERENCE'; bo.solver = 'EXACT'
            bo.show_viewport = False # EXACT re-solves every frame; renders and ExportState turn it on
            body.modifiers.move(body.modifiers.find('Holes'), 0)
            for fly, sign, dx in ((f'BeamFlyP_{c}', 1, 0.05), (f'BeamFlyN_{c}', -1, -0.05)):
                z_tip = pin[2] + sign * BODY_LEN / 2
                bm = bmesh.new()
                loft(bm, ((px + dx, e * BEAM_Y, z_tip - sign * FLY_LEN), X, Y, (0, 0, sign)), # end sunk in the tip plate
                     [(0.0, chamfer_rect(0.09, 0.10, 0.01)), (FLY_LEN + 0.004, chamfer_rect(0.09, 0.10, 0.01))])
                add(hard_surface(part(f'{fly} | fly section', fly, bm, 'chrome', pin), 0.003))
                tip = Vector((px + dx, e * BEAM_Y, z_tip))
                bm = bmesh.new() # end plate on the fly tip, yellow with three black hazard bars
                lo_, hi_ = sorted((0.0, sign * 0.008))
                bm_box(bm, (tip.x - 0.06, tip.y - 0.07, tip.z + lo_), (tip.x + 0.06, tip.y + 0.07, tip.z + hi_))
                add(part(f'{fly} | tip plate', fly, bm, 'yellow', pin))
                bm = bmesh.new()
                lo_, hi_ = sorted((sign * 0.008, sign * 0.010))
                for q_ in (-0.04, 0.0, 0.04):
                    bm_box(bm, (tip.x + q_ - 0.011, tip.y - 0.07, tip.z + lo_), (tip.x + q_ + 0.011, tip.y + 0.07, tip.z + hi_))
                add(part(f'{fly} | tip stripes', fly, bm, 'black', pin))
            for j, (host, off) in enumerate(jaw_hosts(c)):
                jz = pin[2] + off
                ylo, yhi = sorted((e * JAW_TIP, e * (JAW_TIP + JAW_FINGER + 0.01))) # fingers end inside the back block
                bm = bmesh.new() # C jaw: two fingers straddle the blade plane; the back block rides in the beam
                for fz in (-0.048, 0.048):
                    bm_box(bm, (px - 0.12, ylo, jz + fz - 0.013), (px + 0.12, yhi, jz + fz + 0.013))
                # The back block overlaps the fingers so neither end lies flush with the beam face (y |1.62|).
                yb0, yb1 = sorted((e * (JAW_TIP + JAW_FINGER - 0.004), e * (JAW_TIP + 0.185)))
                bm_box(bm, (px - 0.12, yb0, jz - 0.061), (px + 0.12, yb1, jz + 0.061))
                add(hard_surface(part(f'Jaw_{c}_{j + 1} | plate clamp', f'Jaw_{c}_{j + 1}', bm, 'black', (px, e * JAW_TIP, jz)), 0.003))
                bm = bmesh.new() # rubber grip pads on the finger faces, set back from the fingertips
                py0, py1 = sorted((e * (JAW_TIP + 0.016), e * (JAW_TIP + JAW_FINGER - 0.026))) # inside the beam face (|y| 1.48) at rest
                for fz, sg in ((-0.048, 1), (0.048, -1)):
                    zf = jz + fz + sg * 0.013
                    lo_, hi_ = sorted((zf, zf + sg * 0.004))
                    bm_box(bm, (px - 0.10, py0, lo_), (px + 0.10, py1, hi_))
                add(part(f'Jaw_{c}_{j + 1} | grip pads', f'Jaw_{c}_{j + 1}', bm, 'rubber', (px, e * JAW_TIP, jz)))
            # beacon on the mast tip, outboard of the knuckle plate
            tip = (px + s * 0.04, py + e * 0.01, PIV_Z + TIP_REST)
            bm = bmesh.new(); bm_cyl(bm, 0.05, 0.0, 0.025, 24, at=tip); bm_cyl(bm, 0.03, 0.11, 0.13, 20, at=tip)
            add(part(f'DavitS{N_STAGE}_{c} | beacon base', f'DavitS{N_STAGE}_{c}', bm, 'black', tip))
            bm = bmesh.new()
            loft(bm, (tip, X, Y, Z), [(0.025, circle(0.042, 20)), (0.095, circle(0.042, 20)), (0.11, circle(0.03, 20))])
            add(part(f'DavitS{N_STAGE}_{c} | beacon lens', f'DavitS{N_STAGE}_{c}', bm, 'lens', tip))
    REPORT['detail'] = {'parts': len(made)}

# ---------------------------------------------------------------- rig
PATH_RES = 128

def path_controls(s):
    """Bezier points (co, left, right) of the knuckle load path in carriage space for side s.

    rest pin -> pick standby beside the rack (deploy) | lift-off -> rise arc -> traverse over the
    bogie and operator station at hub 3.85 -> stop -> vertical descent to the park (carry)."""
    a, b, k = XC_CLEAR_IN - XC_PICK, HUB_OVER - (PIV1 + LIFT_OFF), 0.5523
    # The path runs 0.3 m past both ends: Follow Path clamps its spline interpolation at the
    # curve ends, which would put a kink into the last centimetres of the park and the first of the rest.
    pts = [
        ((PIV_X, Q_REST[1] - 0.3), (PIV_X, Q_REST[1] - 0.4), (PIV_X, Q_REST[1] - 0.2)),
        ((PIV_X, Q_REST[1]), (PIV_X, Q_REST[1] - 0.1), (PIV_X, Q_REST[1] + 1.2)),
        ((XC_PICK, PIV1), (XC_PICK + 1.5, PIV1 + 0.8), (XC_PICK, PIV1 + LIFT_OFF / 3)),
        ((XC_PICK, PIV1 + LIFT_OFF), (XC_PICK, PIV1 + LIFT_OFF * 2 / 3), (XC_PICK, PIV1 + LIFT_OFF + k * b)),
        ((XC_CLEAR_IN, HUB_OVER), (XC_CLEAR_IN - k * a, HUB_OVER), (XC_CLEAR_IN + 1.5, HUB_OVER)),
        ((XC_PARK, HUB_OVER), (XC_PARK - 1.5, HUB_OVER), (XC_PARK, HUB_OVER - 1.9)),
        ((XC_PARK, HUB_PARK), (XC_PARK, HUB_PARK + 1.9), (XC_PARK, HUB_PARK - 0.1)),
        ((XC_PARK, HUB_PARK - 0.3), (XC_PARK, HUB_PARK - 0.2), (XC_PARK, HUB_PARK - 0.4)),
    ]
    m = lambda p: Vector((s * p[0], 0.0, p[1]))
    return [(m(c), m(l), m(r)) for c, l, r in pts]

def ctl_object():
    coll = ensure_collection(RIG_COLL)
    ctl = bpy.data.objects.get('CTL_Stow')
    if ctl is None:
        ctl = bpy.data.objects.new('CTL_Stow', None); coll.objects.link(ctl)
        ctl.empty_display_type, ctl.empty_display_size = 'ARROWS', 0.6
        ctl.location = (0, 3.2, 3.0)
    for key in ('path', 'fold', 'fly', 'jaw', 'sway', 'rock', 'sag'):
        if key not in ctl: ctl[key] = 0.0
        lo = -1.0 if key == 'sag' else 0.0
        ctl.id_properties_ui(key).update(min=lo, max=1.0, soft_min=lo, soft_max=1.0)
    return ctl

def drive(owner, path, index, expr, variables):
    try: owner.driver_remove(path, index)
    except TypeError: pass
    fc = owner.driver_add(path, index)
    d = fc.driver; d.type = 'SCRIPTED'
    for name, kind, target, spec in variables:
        v = d.variables.new(); v.name = name
        if kind == 'loc':
            v.type = 'TRANSFORMS'; t = v.targets[0]; t.id = target; t.transform_type = spec; t.transform_space = 'WORLD_SPACE'
        else:
            v.type = 'SINGLE_PROP'; t = v.targets[0]; t.id_type = 'OBJECT'; t.id = target; t.data_path = spec
    d.expression = expr
    for m in list(fc.modifiers): fc.modifiers.remove(m)
    return fc

def stage_rig():
    a = rig(); ctl = ctl_object(); coll = ensure_collection(RIG_COLL)
    for s in (-1, 1):
        n = sname(s)
        cu = bpy.data.curves.get(f'CTL_RackPath_{n}') or bpy.data.curves.new(f'CTL_RackPath_{n}', 'CURVE')
        cu.dimensions, cu.resolution_u, cu.use_path = '3D', PATH_RES, True
        cu.splines.clear()
        sp = cu.splines.new('BEZIER'); pts = path_controls(s)
        sp.bezier_points.add(len(pts) - 1)
        for bp, (co, l, r) in zip(sp.bezier_points, pts):
            bp.handle_left_type = bp.handle_right_type = 'FREE'
            bp.co, bp.handle_left, bp.handle_right = co, l, r
        po = bpy.data.objects.get(f'CTL_RackPath_{n}')
        if po is None: po = bpy.data.objects.new(f'CTL_RackPath_{n}', cu); coll.objects.link(po)
        po.data = cu; po.matrix_world = Matrix.Identity(4); po.hide_render = True
        tg = bpy.data.objects.get(f'CTL_RackTarget_{n}')
        if tg is None:
            tg = bpy.data.objects.new(f'CTL_RackTarget_{n}', None); coll.objects.link(tg)
            tg.empty_display_type, tg.empty_display_size = 'SPHERE', 0.18
        tg.location = (0, 0, 0)
        fp = tg.constraints.get('Follow Path') or tg.constraints.new('FOLLOW_PATH')
        fp.name = 'Follow Path'; fp.target = po; fp.use_fixed_location = True; fp.use_curve_follow = False
        drive(tg, 'constraints["Follow Path"].offset_factor', -1, 'p', [('p', 'prop', ctl, '["path"]')])
    bone = lambda b: f'pose.bones["{b}"]'
    for c, s, e in CORNERS:
        tg = bpy.data.objects[f'CTL_RackTarget_{sname(s)}']
        tv = [('tx', 'loc', tg, 'LOC_X'), ('tz', 'loc', tg, 'LOC_Z')]
        u, w = f'({s}*tx-{PIV_X})', f'(tz-{PIV_Z})'
        drive(a, bone(f'Davit_{c}') + '.rotation_euler', 1, f'{s}*atan2({u},{w})', tv)
        for n in range(2, N_STAGE + 1):
            drive(a, bone(f'DavitS{n}_{c}') + '.location', 2, f'(sqrt({u}*{u}+{w}*{w})-{PIN_REST})/{N_STAGE - 1}', tv)
        drive(a, bone(f'Knuckle_{c}') + '.rotation_euler', 1, f'fold*({-s}*pi/2-{s}*atan2({u},{w}))',
              tv + [('fold', 'prop', ctl, '["fold"]')])
        drive(a, bone(f'BeamFlyP_{c}') + '.location', 2, f'fly*{FLY_EXT}', [('fly', 'prop', ctl, '["fly"]')])
        drive(a, bone(f'BeamFlyN_{c}') + '.location', 2, f'-fly*{FLY_EXT}', [('fly', 'prop', ctl, '["fly"]')])
        for j in range(1, 5):
            drive(a, bone(f'Jaw_{c}_{j}') + '.location', 1, f'{-e}*jaw*{JAW_REACH}', [('jaw', 'prop', ctl, '["jaw"]')])
    for i in range(8):
        k = f'{i + 1:02d}'
        hv = [('h', 'prop', a, bone(f'Hinge_{k}') + '.location[2]')]
        la = f'(({PIV0}+h)-{CLEVIS_DROP}-{RAM_BASE_Z}+{2 * RAM_LAP})/3'
        for st, mult in (('A', 0), ('B', 1), ('C', 2)):
            drive(a, bone(f'Ram{st}_{k}') + '.scale', 2, f'{la}/{RAM_REST_LEN}', hv)
            if mult: drive(a, bone(f'Ram{st}_{k}') + '.location', 2, f'{mult}*({la}-{RAM_REST_LEN})', hv)
        pb = a.pose.bones[f'Spin_{k}']
        c1 = pb.constraints.get('Carry_Tilt') or pb.constraints.new('CHILD_OF'); c1.name = 'Carry_Tilt'
        c1.target, c1.subtarget = a, f'Tilt_{k}'
        c1.inverse_matrix = a.data.bones[f'Tilt_{k}'].matrix_local.inverted()
        c2 = pb.constraints.get('Carry_Beam') or pb.constraints.new('CHILD_OF'); c2.name = 'Carry_Beam'
        c2.target, c2.subtarget = a, f'Knuckle_{sname(SIDE[i])}F'
        c1.influence, c2.influence = 1.0, 0.0
    REPORT['rig'] = {'drivers': len(a.animation_data.drivers) if a.animation_data else 0}

# ---------------------------------------------------------------- motion
def scurve_points(d, V, A, J):
    """Jerk-limited (7-phase) move of length d >= 0 from rest to rest: [(t, p, v)] at phase boundaries."""
    if d <= 1e-9: return [(0.0, 0.0, 0.0)]
    def prof(v):
        if v * J < A * A: tj = math.sqrt(v / J); return tj, 0.0, J * tj
        tj = A / J; return tj, v / A - tj, A
    tj, ta, _ = prof(V)
    if V * (2 * tj + ta) <= d: v = V
    else:
        lo, hi = 0.0, V
        for _ in range(80):
            m = (lo + hi) / 2; t1, t2, _ = prof(m)
            lo, hi = (m, hi) if m * (2 * t1 + t2) <= d else (lo, m)
        v = lo; tj, ta, _ = prof(v)
    tv = max(0.0, (d - v * (2 * tj + ta)) / v)
    t = p = vel = acc = 0.0; out = [(0.0, 0.0, 0.0)]
    for dur, j in ((tj, J), (ta, 0.0), (tj, -J), (tv, 0.0), (tj, -J), (ta, 0.0), (tj, J)):
        if dur <= 1e-9: continue
        p += vel * dur + acc * dur * dur / 2 + j * dur ** 3 / 6
        vel += acc * dur + j * dur * dur / 2
        acc += j * dur; t += dur
        out.append((t, p, vel))
    k = d / out[-1][1]
    return [(tt, pp * k, vv * k) for tt, pp, vv in out]

def smooth_points(d, T):
    """S-curve of length d lasting exactly T (tj = ta = T/6, no cruise)."""
    return scurve_points(d, 2 * d / T, 6 * d / T ** 2, 36 * d / T ** 3)

def hermite(p0, v0, p1, v1, h, u):
    return (2*u**3 - 3*u**2 + 1)*p0 + (u**3 - 2*u**2 + u)*h*v0 + (-2*u**3 + 3*u**2)*p1 + (u**3 - u**2)*h*v1

def time_at(points, p):
    """First time a (t, p, v) profile reaches position p (monotonic)."""
    for (t0, p0, v0), (t1, p1, v1) in zip(points, points[1:]):
        if p1 >= p:
            lo, hi = t0, t1
            for _ in range(60):
                m = (lo + hi) / 2
                lo, hi = (m, hi) if hermite(p0, v0, p1, v1, t1 - t0, (m - t0) / (t1 - t0)) < p else (lo, m)
            return lo
    return points[-1][0]

class Channel:
    """Key list (t, value, velocity) written as Bezier keys; cubic Hermite segments are exact."""
    def __init__(self): self.keys = {}
    def hold(self, t, v): self.keys.setdefault(round(t, 6), (v, 0.0))
    def move(self, t0, v0, v1, pts):
        sgn = 1.0 if v1 >= v0 else -1.0
        for t, p, vel in pts: self.keys[round(t0 + t, 6)] = (v0 + sgn * p, sgn * vel)
        return t0 + pts[-1][0]
    def write(self, fc, interp='BEZIER'):
        fc.keyframe_points.clear()
        ks = sorted(self.keys.items())
        fc.keyframe_points.add(len(ks))
        for i, (t, (v, vel)) in enumerate(ks):
            kp = fc.keyframe_points[i]
            f = t * FPS
            kp.co = (f, v); kp.interpolation = interp
            kp.handle_left_type = kp.handle_right_type = 'FREE'
            din = (t - ks[i - 1][0]) / 3 if i else 1 / FPS
            dout = (ks[i + 1][0] - t) / 3 if i + 1 < len(ks) else 1 / FPS
            kp.handle_left = (f - din * FPS, v - vel * din)
            kp.handle_right = (f + dout * FPS, v + vel * dout)
        fc.update()

def path_table(s):
    """Blender's own evaluated load path: points, cumulative length, and length at each control point."""
    po = bpy.data.objects[f'CTL_RackPath_{sname(s)}']
    dg = bpy.context.evaluated_depsgraph_get()
    ev = po.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [po.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    cum = [0.0]
    for p0, p1 in zip(pts, pts[1:]): cum.append(cum[-1] + (p1 - p0).length)
    q = [cum[min(i * PATH_RES, len(cum) - 1)] for i in range(len(path_controls(s)))]
    return pts, cum, q

def point_at(pts, cum, sd):
    import bisect
    i = max(1, min(len(cum) - 1, bisect.bisect_left(cum, sd)))
    u = (sd - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-9)
    return pts[i - 1].lerp(pts[i], min(max(u, 0.0), 1.0))

def plan_path(pts, cum, s0, s1, lim):
    """Curvature-limited, jerk-smoothed speed plan along [s0, s1]: [(t, s, v)] every 1/240 s."""
    V, A, J, ALAT = lim
    n = max(5, int((s1 - s0) / 0.005) + 1)
    ss = [s0 + (s1 - s0) * i / (n - 1) for i in range(n)]
    P = [point_at(pts, cum, sd) for sd in ss]
    kap = [0.0] * n
    for i in range(2, n - 2):
        a_, b_, c_ = P[i - 2], P[i], P[i + 2]
        ab, bc, ca = (b_ - a_).length, (c_ - b_).length, (a_ - c_).length
        kap[i] = 2 * (b_ - a_).cross(c_ - a_).length / max(ab * bc * ca, 1e-9)
    w = 20 # curvature envelope over +-0.1 m
    kmax = [max(kap[max(0, i - w):i + w + 1]) for i in range(n)]
    v = [min(V, math.sqrt(ALAT / k) if k > 1e-6 else V) for k in kmax]
    v[0] = v[-1] = 0.0
    ds = (s1 - s0) / (n - 1)
    for i in range(1, n): v[i] = min(v[i], math.sqrt(v[i - 1] ** 2 + 2 * A * ds))
    for i in range(n - 2, -1, -1): v[i] = min(v[i], math.sqrt(v[i + 1] ** 2 + 2 * A * ds))
    t = [0.0]
    for i in range(1, n): t.append(t[-1] + ds / max((v[i] + v[i - 1]) / 2, 1e-3))
    dt = 1 / 240
    m = int(t[-1] / dt) + 1
    vt, j = [], 0
    for q in range(m):
        tq = q * dt
        while j + 1 < n and t[j + 1] < tq: j += 1
        if j + 1 >= n: vt.append(0.0); continue
        u = (tq - t[j]) / max(t[j + 1] - t[j], 1e-9)
        vt.append(v[j] + (v[j + 1] - v[j]) * u)
    win = max(1, int(A / J / dt / 2)) # jerk smoothing half-window
    pad = [0.0] * win + vt + [0.0] * win
    acc_ = [0.0]
    for x in pad: acc_.append(acc_[-1] + x)
    sm = [(acc_[min(len(pad), i + win + 1)] - acc_[max(0, i - win)]) / (2 * win + 1) for i in range(len(pad))]
    sd, out = 0.0, []
    for q, vv in enumerate(sm):
        out.append((q * dt, sd, vv)); sd += vv * dt
    k = (s1 - s0) / sd
    return [(tq, s0 + sq * k, vq * k) for tq, sq, vq in out]

def action_for(idb, name):
    ad = idb.animation_data or idb.animation_data_create()
    act = bpy.data.actions.get(name) or bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    return act

def fcurve(act, idb, path, index, group):
    return act.fcurve_ensure_for_datablock(idb, path, index=index, group_name=group)

def build_timeline(s_side=1):
    """Stow schedule (seconds) and its kinematic channels; settle overshoot and sway come later."""
    pts, cum, q = path_table(s_side)
    total = cum[-1]
    s_rest, s_pick, s_stop, s_park = q[1], q[2], q[5], q[6] # q[0] and q[7] are the run-out ends
    T = {}
    ch = {k: Channel() for k in ('path', 'fold', 'fly', 'jaw')}
    for k in ('fold', 'fly', 'jaw'): ch[k].hold(0.0, 0.0)
    ch['path'].hold(0.0, s_rest / total)
    T['horn'] = 0.05
    def key_plan(t0, plan, s_end):
        for tq, sq, vq in plan[10::10]: ch['path'].keys[round(t0 + tq, 6)] = (sq / total, vq / total)
        ch['path'].keys[round(t0 + plan[-1][0], 6)] = (s_end / total, 0.0)
        return t0 + plan[-1][0]
    ch['path'].hold(0.30, s_rest / total)
    T['davit_end'] = key_plan(0.30, plan_path(pts, cum, s_rest, s_pick, LIM_DAVIT), s_pick)
    ch['fold'].move(0.85, 0.0, 1.0, smooth_points(1.0, max(0.6, T['davit_end'] - 0.85 - 0.25)))
    ch['fly'].move(T['davit_end'] - 0.9, 0.0, 1.0, smooth_points(1.0, 0.8))
    blades, tilt_60 = [], []
    for i in range(8):
        t0 = BRAKE + 0.05 + 0.05 * RANK[i]
        lift = scurve_points(PIV1 - PIV0, *LIM_LIFT)
        t_tilt = t0 + time_at(lift, TILT_START_PIN - PIV0)
        tilt = scurve_points(math.pi / 2, *LIM_TILT)
        blades.append({'lift0': t0, 'lift': lift, 'tilt0': t_tilt, 'tilt': tilt})
        tilt_60.append(t_tilt + time_at(tilt, math.radians(60)) - GATHER_SLACK[i])
    g0 = max(tilt_60) + 0.02
    arrive = []
    for i in range(8):
        g = scurve_points(abs(X1[i] - X0[i]), *LIM_GATHER)
        blades[i]['gather0'], blades[i]['gather'] = g0, g
        arrive.append(g0 + g[-1][0])
    T['gather0'], T['gather_end'] = g0, max(arrive)
    T['jaw'] = T['gather_end'] + 0.08
    jaw = smooth_points(1.0, 0.32)
    ch['jaw'].move(T['jaw'], 0.0, 1.0, jaw)
    T['clamp'] = T['jaw'] + jaw[-1][0]
    T['release'] = T['clamp'] + 0.08
    c0 = T['release'] + 0.05
    ch['path'].hold(c0, s_pick / total)
    T['traverse_end'] = key_plan(c0, plan_path(pts, cum, s_pick, s_stop, LIM_CARRY), s_stop)
    d0 = T['traverse_end'] + 0.05
    desc = scurve_points(s_park - s_stop, *LIM_DESCENT)
    ch['path'].move(d0, s_stop / total, s_park / total, [(tt, pp / total, vv / total) for tt, pp, vv in desc])
    T['park'] = d0 + desc[-1][0]
    T['lock'] = T['park'] + 0.15
    T['end'] = T['park'] + 0.40
    for c in ch.values(): c.hold(T['end'], c.keys[max(c.keys)][0])
    return T, ch, blades, (pts, cum, q)

OVERSHOOT = {'lift': (0.012, 0.11), 'tilt': (math.radians(1.3), 0.13)} # hydraulic settle: amplitude, half period
SWAY = dict(f=2.4, zeta=0.22) # tower + rack deflection (Hz, damping ratio)
ROCK = dict(f=1.8, zeta=0.20, h=2.0) # blade rocking on its ram, pivot to hub height
SAG = 0.025 # load pick-up dip of the towers, recovered by the hydraulics
PHYS_COLL = 'CTL_StowPhysics'

def mirror(ch, L):
    m = Channel()
    for t, (v, vel) in ch.keys.items(): m.keys[round(L - t, 6)] = (v, -vel)
    return m

def with_overshoot(ch, amp, half):
    """Each move ending away from rest passes its target, peaks after `half` and rings back once."""
    out = Channel(); out.keys = dict(ch.keys)
    ks = sorted(ch.keys.items()); start = None
    for (t0, (v0, _)), (t1, (v1, vel1)) in zip(ks, ks[1:]):
        if abs(v1 - v0) > 1e-9 and start is None: start = v0
        if start is not None and abs(vel1) < 1e-12 and abs(v1 - v0) > 1e-9:
            d = math.copysign(1.0, v1 - start)
            if abs(v1) > 1e-6:
                out.keys[round(t1, 6)] = (v1, d * amp * math.pi / (2 * half))
                out.keys[round(t1 + half, 6)] = (v1 + d * amp, 0.0)
                out.keys[round(t1 + 2 * half, 6)] = (v1 - d * amp * 0.3, 0.0)
                out.keys[round(t1 + 3 * half, 6)] = (v1, 0.0)
            start = None
    return out

def gain(points):
    """Channel of eased 0..1 gain steps: [(t_start, duration, value_after)] from 0."""
    c = Channel(); c.hold(0.0, 0.0); v = 0.0
    for t, dur, to in points:
        c.move(t, v, to, smooth_points(abs(to - v), dur)) if abs(to - v) > 1e-9 else c.hold(t, v); v = to
    return c

def clip_channels(kind):
    """Controls, bone keys, gains, hand-off and events of one clip in its own forward time."""
    T, ch, blades, path = build_timeline()
    L = T['end']
    bones = {}
    for i in range(8):
        k, s, b = f'{i + 1:02d}', SIDE[i], blades[i]
        up = b['lift'][-1][0]
        lift, tilt, slide = Channel(), Channel(), Channel()
        for c in (lift, tilt, slide): c.hold(0.0, 0.0)
        if kind == 'Stow':
            # the empty clevis waits until the rack has lifted clear, then retracts: the exact mirror of
            # Deploy readying it early, so Stow(p) and Deploy(L - p) agree and a reversal only cross-fades sway
            lift.move(b['lift0'], 0.0, PIV1 - PIV0, b['lift'])
            lift.move(T['release'] + 0.55, PIV1 - PIV0, 0.0, scurve_points(PIV1 - PIV0, *LIM_LIFT))
            tilt.move(b['tilt0'], 0.0, s * math.pi / 2, b['tilt'])
            tilt.move(T['release'] + 0.75, s * math.pi / 2, 0.0, smooth_points(math.pi / 2, 0.9))
            slide.move(b['gather0'], 0.0, X1[i] - X0[i], b['gather'])
        else:
            th = L - T['release']
            # rams re-extend and the trunnion turns upright well before the rack comes down onto them
            ret = scurve_points(PIV1 - PIV0, *LIM_LIFT)
            lift.move(th - 0.55 - ret[-1][0], 0.0, PIV1 - PIV0, ret)
            lift.move(L - b['lift0'] - up, PIV1 - PIV0, 0.0, b['lift'])
            tilt.move(th - 0.75 - 0.9, 0.0, s * math.pi / 2, smooth_points(math.pi / 2, 0.9))
            tilt.move(L - b['tilt0'] - b['tilt'][-1][0], s * math.pi / 2, 0.0, b['tilt'])
            g = b['gather']
            slide.move(L - b['gather0'] - g[-1][0], X1[i] - X0[i], 0.0, g) if len(g) > 1 else slide.hold(0.0, 0.0)
            if len(g) <= 1: slide.keys = {0.0: (0.0, 0.0)}
        for c, end_v in ((lift, 0.0), (tilt, 0.0), (slide, (X1[i] - X0[i]) if kind == 'Stow' else 0.0)):
            c.hold(L, end_v)
        if kind == 'Deploy' and abs(X1[i] - X0[i]) > 1e-9: slide.keys[0.0] = (X1[i] - X0[i], 0.0)
        bones[(f'pose.bones["Hinge_{k}"].location', 2, f'Hinge_{k}')] = with_overshoot(lift, *OVERSHOOT['lift'])
        bones[(f'pose.bones["Tilt_{k}"].rotation_euler', 1, f'Tilt_{k}')] = with_overshoot(tilt, *OVERSHOOT['tilt'])
        bones[(f'pose.bones["Slide_{k}"].location', 0, f'Slide_{k}')] = slide
    if kind == 'Deploy':
        ch = {k: mirror(c, L) for k, c in ch.items()}
        th = L - T['release']; arrive = L - (T['release'] + 0.05)
        gains = {'sway': gain([(0.0, 0.30, 1.0), (arrive - 0.40, 0.35, 0.0), (th + 0.10, 0.70, 1.0), (L - 0.36, 0.35, 0.0)]),
                 'rock': gain([(L - T['gather_end'] - 0.10, 0.20, 1.0), (L - T['gather0'] + 0.50, 0.30, 0.0)]),
                 'sag': Channel()}
        gains['sag'].hold(0.0, 0.0); gains['sag'].move(th, 0.0, 1.0, smooth_points(1.0, 0.06)); gains['sag'].move(th + 0.08, 1.0, 0.0, smooth_points(1.0, 0.80))
        handoff, infl = th, {'Carry_Tilt': (0.0, 1.0), 'Carry_Beam': (1.0, 0.0)}
        events = [(0.05, 'horn'), (0.12, 'unlock'), (th - 0.05, 'latch'), (L - T['clamp'] + 0.02, 'unclamp'), (L - 0.12, 'lock')]
    else:
        th = T['release']
        gains = {'sway': gain([(0.0, 0.30, 1.0), (L - 0.36, 0.35, 0.0)]),
                 'rock': gain([(T['gather0'] - 0.10, 0.20, 1.0), (T['jaw'] - 0.35, 0.30, 0.0)]),
                 'sag': Channel()}
        gains['sag'].hold(0.0, 0.0); gains['sag'].move(th, 0.0, -1.0, smooth_points(1.0, 0.06)); gains['sag'].move(th + 0.08, -1.0, 0.0, smooth_points(1.0, 0.80))
        handoff, infl = th, {'Carry_Tilt': (1.0, 0.0), 'Carry_Beam': (0.0, 1.0)}
        events = [(0.05, 'horn'), (T['clamp'], 'clamp'), (T['release'], 'release'), (T['lock'], 'lock')]
    for c in gains.values(): c.hold(L, 0.0)
    return {'kind': kind, 'T': T, 'L': L, 'ctl': ch, 'gains': gains, 'bones': bones, 'handoff': handoff,
            'infl': infl, 'events': events, 'path': path}

def write_clip(clip):
    """Source actions of one clip: <kind>_ctl on CTL_Stow, <kind>_src on the rig."""
    a, ctl = rig(), ctl_object()
    kind = clip['kind']
    actc = action_for(ctl, f'{kind}_ctl')
    for k, c in list(clip['ctl'].items()) + list(clip['gains'].items()):
        c.write(fcurve(actc, ctl, f'["{k}"]', -1, kind))
    for m in list(actc.pose_markers): actc.pose_markers.remove(m)
    for t, name in clip['events'] + [(clip['L'], 'end')]:
        mk = actc.pose_markers.new(name); mk.frame = int(round(t * FPS))
    acta = action_for(a, f'{kind}_src')
    for (path, idx, group), c in clip['bones'].items():
        c.write(fcurve(acta, a, path, idx, group))
    fr = int(round(clip['handoff'] * FPS))
    for i in range(8):
        k = f'{i + 1:02d}'
        for cname, (before, after) in clip['infl'].items():
            fc = fcurve(acta, a, f'pose.bones["Spin_{k}"].constraints["{cname}"].influence', -1, f'Spin_{k}')
            fc.keyframe_points.clear(); fc.keyframe_points.add(2)
            for kp, (f, v) in zip(fc.keyframe_points, ((0, before), (fr, after))):
                kp.co = (f, v); kp.interpolation = 'CONSTANT'
            fc.update()
    return actc, acta

def use_clip(kind):
    """Assign a clip's source actions (the rig keeps its drivers and constraints)."""
    a, ctl = rig(), ctl_object()
    for tr in a.animation_data.nla_tracks: tr.mute = True
    ctl.animation_data.action = bpy.data.actions[f'{kind}_ctl']
    a.animation_data.action = bpy.data.actions[f'{kind}_src']
    sc = scene(); sc.frame_start, sc.frame_end = 0, int(math.ceil(clip_length() * FPS))

def clip_length():
    return bpy.data.actions['Stow_ctl'].pose_markers['end'].frame / FPS

def stage_motion():
    sc = scene(); a = rig()
    for tr in a.animation_data.nla_tracks: tr.mute = True
    out = {}
    for kind in ('Stow', 'Deploy'):
        clip = clip_channels(kind)
        write_clip(clip)
        out[kind] = {'handoff': round(clip['handoff'], 3), 'events': [(round(t, 3), n) for t, n in clip['events']]}
        if kind == 'Stow': T, L = clip['T'], clip['L']
    use_clip('Stow')
    set_handoff_inverse(int(round(T['release'] * FPS)))
    REPORT['motion'] = {k: round(v, 3) for k, v in T.items()}
    REPORT['motion']['frames'] = sc.frame_end
    REPORT['motion']['clips'] = out

def set_handoff_inverse(fr):
    """Carry_Beam inverse so each Spin bone keeps its pose when the beam takes the blade at frame fr."""
    sc = scene(); a = rig()
    sc.frame_set(fr); bpy.context.view_layer.update()
    for i in range(8):
        k = f'{i + 1:02d}'
        pb = a.pose.bones[f'Spin_{k}']
        c1, c2 = pb.constraints['Carry_Tilt'], pb.constraints['Carry_Beam']
        spin = a.pose.bones[f'Tilt_{k}'].matrix @ c1.inverse_matrix @ a.data.bones[f'Spin_{k}'].matrix_local
        knuckle = a.pose.bones[c2.subtarget].matrix
        c2.inverse_matrix = knuckle.inverted() @ spin @ a.data.bones[f'Spin_{k}'].matrix_local.inverted()
    sc.frame_set(0)

# ---------------------------------------------------------------- dynamics (rigid body springs)
def rb_mesh(name, loc, coll):
    me = bpy.data.meshes.get(name)
    if me is None:
        me = bpy.data.meshes.new(name); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=0.06); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.get(name)
    if o is None: o = bpy.data.objects.new(name, me); coll.objects.link(o)
    o.location = loc; o.hide_render = True; o.display_type = 'WIRE'
    return o

def with_active(o, op, **kw):
    vl = bpy.context.view_layer
    for x in vl.objects: x.select_set(False)
    vl.objects.active = o; o.select_set(True)
    op(**kw)

def rb_pair(tag, loc, axes, f, zeta, layer, coll, pivot=None):
    """Kinematic anchor + unit mass joined by a Generic Spring (SPRING2) free only along `axes`.

    The constraint pivot must sit at the bodies' rest position: a pivot far from them (e.g. the
    world origin for a Follow Path anchor) turns the locked angular axes into a lever and the
    spring lags by metres."""
    anchor, mass = rb_mesh(f'RB_{tag}_Anchor', loc, coll), rb_mesh(f'RB_{tag}_Mass', loc, coll)
    for o, kind in ((anchor, 'PASSIVE'), (mass, 'ACTIVE')):
        if o.rigid_body is None: with_active(o, bpy.ops.rigidbody.object_add, type=kind)
        rb = o.rigid_body; rb.type = kind; rb.mass = 1.0; rb.collision_shape = 'BOX'
        rb.kinematic = kind == 'PASSIVE'; rb.linear_damping = 0.0; rb.angular_damping = 0.0
        rb.use_deactivation = False
        rb.collision_collections = [i == layer for i in range(20)]
    cn = bpy.data.objects.get(f'RB_{tag}_Spring')
    if cn is None: cn = bpy.data.objects.new(f'RB_{tag}_Spring', None); coll.objects.link(cn)
    cn.location = pivot or loc; cn.hide_render = True
    if cn.rigid_body_constraint is None: with_active(cn, bpy.ops.rigidbody.constraint_add, type='GENERIC_SPRING')
    c = cn.rigid_body_constraint
    c.type = 'GENERIC_SPRING'; c.object1, c.object2 = anchor, mass
    c.disable_collisions = True; c.spring_type = 'SPRING2'
    k = (2 * math.pi * f) ** 2; d = 2 * zeta * math.sqrt(k)
    for ax in 'xyz':
        on = ax in axes
        setattr(c, f'use_limit_lin_{ax}', not on); setattr(c, f'limit_lin_{ax}_lower', 0.0); setattr(c, f'limit_lin_{ax}_upper', 0.0)
        setattr(c, f'use_spring_{ax}', on); setattr(c, f'spring_stiffness_{ax}', k); setattr(c, f'spring_damping_{ax}', d)
        setattr(c, f'use_limit_ang_{ax}', True); setattr(c, f'limit_ang_{ax}_lower', 0.0); setattr(c, f'limit_ang_{ax}_upper', 0.0)
    return anchor, mass

def stage_dynamics():
    """Rigid-body springs for tower/rack deflection, pick-up sag and blade rocking; drivers feed them back."""
    sc = scene(); a = rig(); ctl = ctl_object()
    coll = ensure_collection(PHYS_COLL)
    if sc.rigidbody_world is None: bpy.ops.rigidbody.world_add()
    w = sc.rigidbody_world
    w.enabled = True; w.substeps_per_frame = 20; w.solver_iterations = 30
    w.effector_weights.gravity = 0.0
    w.point_cache.frame_start = 0; w.point_cache.frame_end = 400
    bone = lambda b: f'pose.bones["{b}"]'
    sc.frame_set(0)
    for s in (-1, 1):
        n = sname(s)
        anchor, mass = rb_pair(f'Rack{n}', (0, 0, 0), 'xz', SWAY['f'], SWAY['zeta'], 10 + (s > 0), coll,
                               pivot=(s * PIV_X, 0.0, PIV_Z + PIN_REST))
        fp = anchor.constraints.get('Follow Path') or anchor.constraints.new('FOLLOW_PATH')
        fp.name = 'Follow Path'; fp.target = bpy.data.objects[f'CTL_RackPath_{n}']; fp.use_fixed_location = True
        drive(anchor, 'constraints["Follow Path"].offset_factor', -1, 'p', [('p', 'prop', ctl, '["path"]')])
        anchor.location = (0, 0, 0)
        drive(anchor, 'location', 2, f'{SAG}*sag', [('sag', 'prop', ctl, '["sag"]')])
        bpy.context.view_layer.update()
        mass.location = anchor.matrix_world.translation
        tg = bpy.data.objects[f'CTL_RackTarget_{n}']
        mv = [('mx', 'loc', mass, 'LOC_X'), ('ax', 'loc', anchor, 'LOC_X'), ('mz', 'loc', mass, 'LOC_Z'), ('az', 'loc', anchor, 'LOC_Z'),
              ('sway', 'prop', ctl, '["sway"]'), ('sag', 'prop', ctl, '["sag"]')]
        drive(tg, 'location', 0, 'sway*(mx-ax)', mv)
        drive(tg, 'location', 2, f'sway*(mz-az)+{SAG}*sag', mv)
    for i in range(8):
        k = f'{i + 1:02d}'
        anchor, mass = rb_pair(f'Blade{k}', (X0[i], 0, ROCK['h']), 'x', ROCK['f'], ROCK['zeta'], 12 + i, coll)
        drive(anchor, 'location', 0, f'{X0[i]}+sx', [('sx', 'prop', a, bone(f'Slide_{k}') + '.location[0]')])
        anchor.location.y, anchor.location.z = 0.0, ROCK['h']
        mass.location = (X0[i], 0, ROCK['h'])
        drive(a, bone(f'Ram_{k}') + '.rotation_euler', 1, f"rock*atan2(mx-ax,{ROCK['h']})",
              [('mx', 'loc', mass, 'LOC_X'), ('ax', 'loc', anchor, 'LOC_X'), ('rock', 'prop', ctl, '["rock"]')])
    REPORT['dynamics'] = {'bodies': len([o for o in coll.objects if o.rigid_body]), 'springs': len([o for o in coll.objects if o.rigid_body_constraint])}

def simulate(kind):
    """Assign the clip's controls and bake the rigid-body cache for it."""
    use_clip(kind)
    sc = scene(); w = sc.rigidbody_world
    w.point_cache.frame_start, w.point_cache.frame_end = sc.frame_start, sc.frame_end
    bpy.ops.ptcache.free_bake_all()
    sc.frame_set(0)
    for s in (-1, 1): # the masses and the spring pivots start where the anchors rest for this clip
        n = sname(s)
        anc, mass = bpy.data.objects[f'RB_Rack{n}_Anchor'], bpy.data.objects[f'RB_Rack{n}_Mass']
        mass.location = anc.matrix_world.translation
        bpy.data.objects[f'RB_Rack{n}_Spring'].location = anc.matrix_world.translation
    for i in range(8):
        anc, mass = bpy.data.objects[f'RB_Blade{i + 1:02d}_Anchor'], bpy.data.objects[f'RB_Blade{i + 1:02d}_Mass']
        mass.location = anc.matrix_world.translation
    bpy.ops.ptcache.bake_all(bake=True)

def stage_bake():
    """Visual bake of Stow and Deploy (drivers, constraints, physics) to plain keys on every bone."""
    a = rig(); sc = scene()
    out = {}
    for kind in globals().get('BAKE_KINDS', ('Stow', 'Deploy')):
        simulate(kind)
        if kind == 'Stow': # hand-off inverse with the settled physics of the baked cache
            set_handoff_inverse(bpy.data.actions['Stow_ctl'].pose_markers['release'].frame)
        names = [b.name for b in a.data.bones if not b.name.startswith(('Carriage', 'Roll_'))]
        frames = range(sc.frame_start, sc.frame_end + 1)
        samples = {n: [] for n in names}
        for f in frames:
            sc.frame_set(f)
            for n in names:
                pb = a.pose.bones[n]
                M = a.convert_space(pose_bone=pb, matrix=pb.matrix, from_space='POSE', to_space='LOCAL')
                samples[n].append(M.decompose())
        act = bpy.data.actions.get(kind)
        if act: bpy.data.actions.remove(act)
        act = bpy.data.actions.new(kind); act.use_fake_user = True; act['stow_v2_baked'] = True
        ad = a.animation_data; source = ad.action
        ad.action = act # slotted actions: F-curves are created for the assigned slot (sampling is done)
        lin = bpy.types.Keyframe.bl_rna.properties['interpolation'].enum_items['LINEAR'].value
        for n, seq in samples.items():
            qs, prev = [], None
            for loc, q, scl in seq:
                q = q.normalized()
                if prev is not None and prev.dot(q) < 0: q.negate()
                qs.append(q); prev = q
            for prop, vals in (('location', [tuple(l) for l, _, _ in seq]), ('rotation_quaternion', [tuple(q) for q in qs]),
                               ('scale', [tuple(s_) for _, _, s_ in seq])):
                for idx in range(len(vals[0])):
                    fc = act.fcurve_ensure_for_datablock(a, f'pose.bones["{n}"].{prop}', index=idx, group_name=n)
                    fc.keyframe_points.clear(); fc.keyframe_points.add(len(vals))
                    co = []
                    for f, v in zip(frames, vals): co += [float(f), v[idx]]
                    fc.keyframe_points.foreach_set('co', co)
                    fc.keyframe_points.foreach_set('interpolation', [lin] * len(vals)); fc.update()
        ad.action = source
        src = bpy.data.actions[f'{kind}_ctl']
        for m in src.pose_markers:
            mk = act.pose_markers.new(m.name); mk.frame = m.frame
        act.frame_range = (sc.frame_start, sc.frame_end)
        out[kind] = {'frames': len(frames), 'bones': len(names)}
    bpy.ops.ptcache.free_bake_all()
    use_clip('Stow')
    ad = a.animation_data
    for n in [k for k in ('Stow', 'Deploy') if bpy.data.actions.get(k)]:
        for tr in [t for t in ad.nla_tracks if t.name == n]: ad.nla_tracks.remove(tr)
        tr = ad.nla_tracks.new(); tr.name = n; tr.strips.new(n, 0, bpy.data.actions[n]); tr.mute = True
    REPORT['bake'] = out

# ---------------------------------------------------------------- export (baked clips only)
GLB_PATH = ROOT + '/assets/hazards/linked_saw_carriage.glb'
JSON_PATH = ROOT + '/assets/hazards/linked_saw_carriage_stow.json'
SKIN_NAME = 'SAW_StowSkinned'
EVENT_KIND = {'horn': 'horn', 'clamp': 'latch', 'release': 'latch', 'lock': 'latch', 'unlock': 'latch',
              'latch': 'latch', 'unclamp': 'latch'}

class ExportState:
    """Baked clips drive the rig: drivers and Child Of muted, quaternion bones, booleans evaluated.
    Everything is restored on exit, so the editable rig survives in the source file."""
    def __init__(self, clip=None, booleans=True): self.clip, self.booleans = clip, booleans # audits read meshes, not booleans
    def __enter__(self):
        a = rig(); ad = a.animation_data
        self.drivers = [(fc, fc.mute) for fc in ad.drivers]
        for fc, _ in self.drivers: fc.mute = True
        self.cons = [(c, c.mute) for pb in a.pose.bones for c in pb.constraints]
        for c, _ in self.cons: c.mute = True
        self.modes = {pb.name: pb.rotation_mode for pb in a.pose.bones}
        for pb in a.pose.bones:
            q = pb.matrix_basis.to_quaternion()
            pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = q
        self.action, self.slot = ad.action, getattr(ad, 'action_slot', None)
        self.nla = {t.name: t.mute for t in ad.nla_tracks}
        ad.action = bpy.data.actions[self.clip] if self.clip else None
        self.basis = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in a.pose.bones}
        for pb in a.pose.bones: # bones a clip does not key must sit at rest (Spin_Loop, Advance_Demo)
            pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        for t in ad.nla_tracks: t.mute = self.clip is not None
        self.bools = [(m, m.show_viewport) for o in bpy.data.objects for m in o.modifiers if m.type == 'BOOLEAN']
        for m, _ in self.bools: m.show_viewport = self.booleans
        bpy.context.view_layer.update()
        return self
    def __exit__(self, *exc):
        a = rig(); ad = a.animation_data
        for pb in a.pose.bones:
            pb.location, pb.rotation_quaternion, pb.scale = self.basis[pb.name]
        ad.action = self.action
        for t in ad.nla_tracks: t.mute = self.nla.get(t.name, True)
        for m, v in self.bools: m.show_viewport = v
        for pb in a.pose.bones: pb.rotation_mode = self.modes[pb.name]
        for c, v in self.cons: c.mute = v
        for fc, v in self.drivers: fc.mute = v
        bpy.context.view_layer.update()

def build_skinned():
    """Join every v2 stow part (modifiers applied) into one mesh skinned rigidly to its bone:
    one surface per material instead of ~280 bone-parented objects."""
    remove_skinned()
    a = rig(); coll = bpy.data.collections[COLL]
    parts = [o for o in bpy.data.objects if o.get('stow_v2') and o.type == 'MESH']
    copies = []
    with RestPose():
        dg = bpy.context.evaluated_depsgraph_get()
        for o in parts:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            me.transform(o.matrix_world)
            c = bpy.data.objects.new(f'_skin_{o.name}', me); coll.objects.link(c)
            vg = c.vertex_groups.new(name=o.parent_bone); vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
            copies.append(c)
    vl = bpy.context.view_layer
    for x in vl.objects: x.select_set(False)
    for c in copies: c.select_set(True)
    vl.objects.active = copies[0]
    bpy.ops.object.join()
    sk = vl.objects.active
    sk.name = sk.data.name = SKIN_NAME
    sk.parent = a; sk.parent_type = 'OBJECT'; sk.matrix_parent_inverse = Matrix.Identity(4); sk.matrix_world = Matrix.Identity(4)
    mod = sk.modifiers.new('Armature', 'ARMATURE'); mod.object = a
    sk['saw_src'] = True; sk['stow_export_tmp'] = True
    for o in parts: o['saw_src'] = False
    return sk

def remove_skinned():
    for o in [o for o in bpy.data.objects if o.get('stow_export_tmp') or o.name.startswith('_skin_')]:
        me = o.data; bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)
    for o in bpy.data.objects:
        if o.get('stow_v2'): o['saw_src'] = True

def stage_export():
    """Write the GLB (Spin_Loop, Advance_Demo, Stow, Deploy as NLA tracks) and the sidecar JSON."""
    sc = scene(); a = rig(); ad = a.animation_data
    try:
        with ExportState():
            build_skinned()
            for t in ad.nla_tracks: t.mute = False
            vl = bpy.context.view_layer
            for o in vl.objects: o.select_set(False)
            for o in sc.objects:
                if o.get('saw_src') and 'ICO' not in o.name: o.select_set(True)
            a.select_set(True); vl.objects.active = a
            sc.frame_set(0)
            bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format='GLB', use_selection=True, use_active_scene=True,
                export_animations=True, export_animation_mode='NLA_TRACKS', export_force_sampling=True,
                export_optimize_animation_size=True, export_frame_range=False, export_def_bones=False,
                export_cameras=False, export_lights=False, export_extras=False, export_yup=True,
                export_apply=True, export_skins=True, export_morph=False, export_image_format='AUTO')
    finally:
        remove_skinned()
    REPORT['export'] = {'glb': GLB_PATH, 'bytes': os.path.getsize(GLB_PATH)}

def _clip_samples(clip, sub=1):
    """World positions per frame of the points the runtime cares about, from a baked clip."""
    import numpy as np
    sc = scene(); a = rig()
    parts = [o for o in bpy.data.objects if o.get('stow_v2') and o.type == 'MESH']
    tall = [o for o in parts if not o.parent_bone.startswith(('Ram', 'Hinge', 'Tilt', 'Slide')) and o.parent_bone != 'Carriage']
    local = {o.name: _arrays(o)[0] for o in tall}
    blades = [bpy.data.objects[f'Blade_{i + 1:02d} | 24 carbide teeth'] for i in range(8)]
    blocal = {o.name: _arrays(o)[0] for o in blades}
    rows = []
    with ExportState(clip, booleans=False):
        for f in range(sc.frame_start, sc.frame_end + 1):
            sc.frame_set(f)
            pts = []
            for o in tall + blades:
                M = np.array(o.matrix_world); co = (blocal if o in blades else local)[o.name]
                pts.append(co @ M[:3, :3].T + M[:3, 3])
            allp = np.vstack(pts)
            bl = np.vstack(pts[len(tall):])
            track = [(a.matrix_world @ a.pose.bones[n].matrix).translation.copy() for n in
                     [f'Spin_{i + 1:02d}' for i in range(8)] + [f'Knuckle_{c}' for c, _, _ in CORNERS] + [f'Jaw_{c}_1' for c, _, _ in CORNERS]]
            rows.append((f, allp, bl, track))
    return rows

def stage_sidecar():
    import numpy as np
    sc = scene()
    L = bpy.data.actions['Stow_ctl'].pose_markers['end'].frame / FPS
    data = {'version': 2, 'fps': FPS, 'length': round(L, 4), 'brake_seconds': BRAKE, 'curve_rate': 30,
            'events': {}, 'wall_block': [], 'station_airspace': [], 'chair_column': []}
    for kind, key in (('Stow', 'stow'), ('Deploy', 'deploy')):
        data['events'][key] = [{'t': round(m.frame / FPS, 4), 'kind': EVENT_KIND[m.name], 'name': m.name}
                               for m in sorted(bpy.data.actions[f'{kind}_ctl'].pose_markers, key=lambda m: m.frame) if m.name in EVENT_KIND]
    per_p = {} # stow-time p (frame index) -> aggregated flags/speeds from both clips
    for kind in ('Stow', 'Deploy'):
        rows = _clip_samples(kind)
        prev = None
        for f, allp, bl, track in rows:
            p = f if kind == 'Stow' else sc.frame_end - f
            e = per_p.setdefault(p, {'block': False, 'reach': 0.0, 'station': False, 'chair': False, 'speed': 0.0})
            over_belt = allp[(np.abs(allp[:, 0]) < 11.9) & (allp[:, 2] > 0.62)]
            if len(over_belt):
                e['block'] = True; e['reach'] = max(e['reach'], float(np.abs(over_belt[:, 1]).max()))
            st = bl[(bl[:, 0] > 12.01) & (bl[:, 0] < 13.85) & (np.abs(bl[:, 1]) < 0.85)]
            e['station'] = e['station'] or len(st) > 0
            ch = allp[(allp[:, 0] > 12.70) & (allp[:, 0] < 13.80) & (np.abs(allp[:, 1]) < 0.55) & (allp[:, 2] > 0.5)]
            e['chair'] = e['chair'] or len(ch) > 0
            if prev is not None:
                sp = max((t1 - t0).length for t0, t1 in zip(prev, track)) * FPS
                e['speed'] = max(e['speed'], sp)
                pe = per_p.setdefault(p - 1 if kind == 'Stow' else p + 1, e); pe['speed'] = max(pe['speed'], sp)
            prev = track
    def intervals(key):
        out, start = [], None
        for p in range(sc.frame_start, sc.frame_end + 1):
            on = per_p.get(p, {}).get(key, False)
            if on and start is None: start = p
            if not on and start is not None: out.append((start, p - 1)); start = None
        if start is not None: out.append((start, sc.frame_end))
        return out
    for s0, s1 in intervals('block'):
        reach = max(per_p[p]['reach'] for p in range(s0, s1 + 1))
        data['wall_block'].append({'from': round(max(0, s0 - 1) / FPS, 4), 'to': round(min(sc.frame_end, s1 + 1) / FPS, 4), 'reach_y': round(reach + 0.05, 3)})
    for key, name in (('station', 'station_airspace'), ('chair', 'chair_column')):
        iv = intervals(key)
        data[name] = [round(max(0, iv[0][0] - 1) / FPS, 4), round(min(sc.frame_end, iv[-1][1] + 1) / FPS, 4)] if iv else []
    n = int(L * 30) + 1
    spd = [per_p.get(min(sc.frame_end, int(round(q / 30 * FPS))), {}).get('speed', 0.0) for q in range(n)]
    data['speed_env'] = [round(v, 3) for v in spd]
    data['hydraulic'] = [round(min(1.0, v / 3.0), 3) for v in spd]
    with open(JSON_PATH, 'w', encoding='utf-8') as fh: json.dump(data, fh, indent=1)
    REPORT['sidecar'] = {'path': JSON_PATH, 'length': data['length'], 'wall_block': data['wall_block'],
                         'station_airspace': data['station_airspace'], 'chair_column': data['chair_column'],
                         'events': {k: [(e['t'], e['name']) for e in v] for k, v in data['events'].items()}}

# ---------------------------------------------------------------- audit
STATION_BOX = ((12.01, -0.85, 0.07), (13.85, 0.85, 2.25))
BLADE_R = 1.45

def _arrays(o):
    import numpy as np
    me = o.data
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get('co', co)
    return co.reshape(-1, 3), [tuple(p.vertices) for p in me.polygons]

class Group:
    """Rigid mesh group evaluated in world space; BVH rebuilt when its matrix changes."""
    def __init__(self, name, objs):
        self.name, self.parts = name, [(o, *_arrays(o)) for o in objs if o.type == 'MESH' and len(o.data.polygons)]
    def build(self):
        import numpy as np
        from mathutils.bvhtree import BVHTree
        verts, polys, base = [], [], 0
        for o, co, pl in self.parts:
            M = np.array(o.matrix_world)
            w = co @ M[:3, :3].T + M[:3, 3]
            verts.append(w); polys += [tuple(i + base for i in p) for p in pl]; base += len(w)
        self.world = np.vstack(verts) if verts else np.zeros((0, 3))
        self.lo, self.hi = (self.world.min(0), self.world.max(0)) if len(self.world) else (None, None)
        self.bvh = BVHTree.FromPolygons([Vector(v) for v in self.world], polys) if polys else None
        return self

def _hit(a, b, pad=0.0):
    if a.bvh is None or b.bvh is None: return False
    if (a.lo > b.hi + pad).any() or (b.lo > a.hi + pad).any(): return False
    return bool(a.bvh.overlap(b.bvh))

def audit_groups():
    a = rig()
    stow = [o for o in bpy.data.objects if o.get('stow_v2') and o.type == 'MESH']
    by_bone = {}
    for o in stow: by_bone.setdefault(o.parent_bone, []).append(o)
    blades = {i: [bpy.data.objects[f'Blade_{i + 1:02d} | 24 carbide teeth']] for i in range(8)}
    modules = {i: [c for c in bpy.data.objects[f'Slider_{i + 1:02d} | slide X'].children_recursive if c.type == 'MESH'] for i in range(8)}
    skip = {o.name for v in modules.values() for o in v}
    for o in bpy.data.objects: # blade assemblies (blade, spindle, clamp, nut) ride on the Spin bones
        if o.parent_type == 'BONE' and o.parent_bone.startswith('Spin_'):
            skip.add(o.name); skip |= {c.name for c in o.children_recursive}
    carriage = [o for o in bpy.data.collections[COLL].objects if o.type == 'MESH' and not o.get('stow_v2')
                and o.name not in skip and 'ICO' not in o.name]
    ref = [o for o in bpy.data.collections['REF_Conveyor'].objects] + [bpy.data.objects['REF_Belt']] + \
          [o for o in bpy.data.collections['REF_Station_Menu_parts'].objects if o.type == 'MESH']
    return a, by_bone, blades, modules, carriage, ref

def corner_of(bone):
    for c, s, e in CORNERS:
        if bone.endswith('_' + c) or f'_{c}_' in bone: return c
    return None

def stage_audit(step=1, sub=4):
    """Interference, clearance and speed audit. AUDIT_CLIP = 'Stow' / 'Deploy' evaluates the baked
    clip exactly as it is exported; without it the live rig (source actions, drivers, physics) is used."""
    clip = globals().get('AUDIT_CLIP')
    if clip:
        with ExportState(clip, booleans=False): return _audit(step, sub, clip)
    return _audit(step, sub, None)

def _audit(step, sub, clip):
    import numpy as np
    sc = scene(); a, by_bone, blades, modules, carriage, ref = audit_groups()
    rest_hub = {i: a.data.bones[f'Spin_{i + 1:02d}'].matrix_local.translation.copy() for i in range(8)}
    box = Group('station_box', [bpy.data.objects['REF_OperatorStation']]).build()
    carr = Group('carriage', carriage).build(); refg = Group('ref', ref).build()
    fails, notes = {}, {}
    def fail(key, f, detail):
        fails.setdefault(key, {'count': 0, 'first': (f, detail)}); fails[key]['count'] += 1
    end = sc.frame_end
    rel = bpy.data.actions['Stow_ctl'].pose_markers['release'].frame
    # ---- per integer frame: BVH interference
    for f in range(0, end + 1, step):
        sc.frame_set(f)
        bg = {i: Group(f'blade{i + 1}', o).build() for i, o in blades.items()}
        mg = {i: Group(f'module{i + 1}', o).build() for i, o in modules.items()}
        sg = {b: Group(b, o).build() for b, o in by_bone.items()}
        for i, g in bg.items():
            if _hit(g, box): fail('blade_in_station_box', f, g.name)
            if _hit(g, refg): fail('blade_vs_ref', f, g.name)
            if _hit(g, carr): fail('blade_vs_carriage', f, g.name)
            hub = (a.matrix_world @ a.pose.bones[f'Spin_{i + 1:02d}'].matrix).translation
            seated = (hub - rest_hub[i]).length < 0.02 # resting on its own flange
            for j, m in mg.items():
                if (j != i or not seated) and _hit(g, m): fail('blade_vs_module', f, f'{g.name}/{m.name}')
            for j in range(i + 1, 8):
                if _hit(g, bg[j]): fail('blade_vs_blade', f, f'{g.name}/{bg[j].name}')
            for b, s in sg.items():
                if b.endswith(f'_{i + 1:02d}'): continue
                if _hit(g, s): fail('blade_vs_stow', f, f'{g.name}/{b}')
        for b, s in sg.items():
            if b == 'Carriage': continue
            if s.world is not None and len(s.world) and (np.abs(s.world[:, 1]) < 0.87).any() and not b.startswith(('Ram', 'Hinge', 'Tilt')):
                fail('stow_in_station_corridor', f, b)
            if _hit(s, refg): fail('stow_vs_ref', f, b)
            if not b.startswith(('Ram', 'Hinge', 'Tilt')) and _hit(s, carr): fail('stow_vs_carriage', f, b)
            for j, m in mg.items():
                if b.endswith(f'_{j + 1:02d}'): continue
                if _hit(s, m): fail('stow_vs_module', f, f'{b}/{m.name}')
        for c, _, _ in CORNERS:
            beam = [sg[b] for b in sg if corner_of(b) == c and b.startswith(('Knuckle', 'BeamFly', 'Jaw'))]
            mast = [sg[b] for b in sg if corner_of(b) == c and b.startswith('Davit')]
            for x in beam:
                for y in mast:
                    if x.name.startswith('Knuckle') and y.name.startswith(f'DavitS{N_STAGE}'): continue # the knuckle pin joint
                    if _hit(x, y): fail('beam_vs_mast', f, f'{x.name}/{y.name}')
        if f == 0:
            env = np.vstack([s.world for b, s in sg.items() if b.startswith(('Davit', 'Knuckle', 'BeamFly', 'Jaw')) or b == 'Carriage'])
            notes['rest_envelope'] = {'abs_x': [round(float(np.abs(env[:, 0]).min()), 3), round(float(np.abs(env[:, 0]).max()), 3)],
                                      'abs_y': [round(float(np.abs(env[:, 1]).min()), 3), round(float(np.abs(env[:, 1]).max()), 3)],
                                      'z': [round(float(env[:, 2].min()), 3), round(float(env[:, 2].max()), 3)]}
    # ---- sub-frame samples: blade rim clearance, speeds, accelerations
    rim = [(math.cos(t), math.sin(t)) for t in np.linspace(0, 2 * math.pi, 48, endpoint=False)]
    track = {}
    min_bottom_over, min_belt, n = 9.0, 9.0, 0
    for q in range(0, end * sub + 1):
        f, fr_ = divmod(q, sub); sc.frame_set(f, subframe=fr_ / sub)
        t = q / (sub * FPS)
        pts = {}
        for i in range(8):
            M = a.matrix_world @ a.pose.bones[f'Spin_{i + 1:02d}'].matrix
            c = M.translation; X, Z = M.col[0].xyz.normalized(), M.col[2].xyz.normalized()
            ring = [c + BLADE_R * (u * X + v * Z) for u, v in rim]
            pts[f'hub{i + 1}'] = c; pts[f'rim{i + 1}'] = ring
            xs = [p.x for p in ring]
            for p in ring:
                if STATION_BOX[0][0] <= p.x <= STATION_BOX[1][0] and abs(p.y) < 0.85: min_bottom_over = min(min_bottom_over, p.z)
                if abs(p.x) < 12.0: min_belt = min(min_belt, p.z)
        for c_, s, e in CORNERS:
            pts[f'tip_{c_}'] = (a.matrix_world @ a.pose.bones[f'Knuckle_{c_}'].matrix).translation
            for j in (1, 4): pts[f'jaw_{c_}{j}'] = (a.matrix_world @ a.pose.bones[f'Jaw_{c_}_{j}'].matrix).translation
        track[q] = pts
    dt = 1 / (sub * FPS)
    vmax, amax = {}, {}
    keys = [k for k in track[0] if not k.startswith('rim')]
    for k in keys:
        P = np.array([list(track[q][k]) for q in sorted(track)])
        V = np.linalg.norm(np.diff(P, axis=0), axis=1) / dt
        vv = np.diff(P, axis=0) / dt
        A = np.linalg.norm(np.diff(vv, axis=0), axis=1) / dt
        kern = np.ones(sub) / sub # accel over a 1-frame window (ignores sub-frame key noise)
        As = np.convolve(A, kern, 'same')
        vmax[k] = round(float(V.max()), 3); amax[k] = [round(float(As.max()), 3), round(float(np.argmax(As) + 1) * dt, 3)]
    rimv = 0.0
    for i in range(8):
        R = np.array([[list(p) for p in track[q][f'rim{i + 1}']] for q in sorted(track)])
        rimv = max(rimv, float((np.linalg.norm(np.diff(R, axis=0), axis=2) / dt).max()))
    sc.frame_set(0)
    rep = {'fails': fails, 'notes': notes, 'min_blade_bottom_over_station': round(min_bottom_over, 3),
           'min_blade_z_over_belt': round(min_belt, 3), 'vmax': vmax, 'amax': amax, 'rim_vmax': round(rimv, 3),
           'frames': end, 'release_frame': rel}
    os.makedirs(OUT, exist_ok=True)
    rep['clip'] = clip or 'live rig'
    with open(f'{OUT}/audit_{globals().get("AUDIT_TAG", "stow")}.json', 'w') as fh: json.dump(rep, fh, indent=1, default=str)
    REPORT['audit'] = {'fails': {k: v for k, v in fails.items()}, 'min_bottom_over': rep['min_blade_bottom_over_station'],
                       'min_belt': rep['min_blade_z_over_belt'], 'rim_vmax': rep['rim_vmax'],
                       'hub_vmax': max(v for k, v in vmax.items() if k.startswith('hub')),
                       'tip_vmax': max(v for k, v in vmax.items() if k.startswith('tip')),
                       'hub_amax': max((v for k, v in amax.items() if k.startswith('hub')), key=lambda x: x[0]),
                       'tip_amax': max((v for k, v in amax.items() if k.startswith('tip')), key=lambda x: x[0]),
                       'rest_envelope': notes.get('rest_envelope')}

# ---------------------------------------------------------------- review renders
def stage_review(tag='review', cams=('CAM_WallSpeedTab', 'CAM_MenuMain'), times=None, res=(960, 540)):
    sc = scene()
    out = f'{OUT}/{tag}'; os.makedirs(out, exist_ok=True)
    prev = (sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.frame_current, sc.render.filepath)
    files = []
    times = times or [0.0, 1.0, 2.5, 3.5, 5.0, 6.3, 7.5, 8.5, 9.5, 10.5, 11.5, 12.2]
    for cam in cams:
        sc.camera = bpy.data.objects[cam]
        sc.render.resolution_x, sc.render.resolution_y = res
        for t in times:
            f = int(round(t * FPS)); sc.frame_set(f)
            sc.render.filepath = f'{out}/{cam}_{f:04d}.png'
            bpy.ops.render.render(write_still=True); files.append(sc.render.filepath)
    sc.camera, sc.render.resolution_x, sc.render.resolution_y = prev[0], prev[1], prev[2]
    sc.render.filepath = prev[4]; sc.frame_set(prev[3])
    REPORT['review'] = {'dir': out, 'count': len(files)}

def stage_frames():
    """Frame sequence for review videos (background runs): FR_CAM, FR_RES, FR_STEP, FR_TAG, FR_VESSEL, FR_ACTION."""
    g = globals(); sc = scene()
    cam, res, step = g.get('FR_CAM', 'CAM_MenuMain'), g.get('FR_RES', (640, 360)), g.get('FR_STEP', 1)
    out = f"{OUT}/{g.get('FR_TAG', 'video_' + cam)}"; os.makedirs(out, exist_ok=True)
    vc = bpy.data.collections.get('REF_Vessel_parts')
    if g.get('FR_VESSEL') and vc: vc.hide_render = False
    sc.camera = bpy.data.objects[cam]; sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'
    frames = list(g.get('FR_FRAMES') or range(sc.frame_start, sc.frame_end + 1, step))
    for f in frames:
        sc.frame_set(f); sc.render.filepath = f'{out}/f_{f:04d}.png'; bpy.ops.render.render(write_still=True)
    if g.get('FR_VESSEL') and vc: vc.hide_render = True
    REPORT['frames'] = {'dir': out, 'count': len(frames)}

def _act_hash(act):
    """Same digest as artifacts/saw_stow/v2/baseline_v1.json (v1 action fingerprints)."""
    import hashlib
    h, n = hashlib.sha1(), 0
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in sorted(cb.fcurves, key=lambda f: (f.data_path, f.array_index)):
                    h.update(f"{fc.data_path}[{fc.array_index}]".encode())
                    for k in fc.keyframe_points: h.update(("%.6f,%.6f;" % (k.co[0], k.co[1])).encode())
                    n += 1
    return h.hexdigest(), n

def _pose_table(clip):
    """Armature-space matrix of every bone for every frame of a baked clip."""
    sc = scene(); a = rig(); out = []
    with ExportState(clip, booleans=False):
        for f in range(sc.frame_start, sc.frame_end + 1):
            sc.frame_set(f); out.append({pb.name: pb.matrix.copy() for pb in a.pose.bones})
    return out

def stage_verify():
    """Existing data untouched (v1 action hashes, rest matrices), clip ends exact, and Stow(p) ~ Deploy(L - p)
    so the runtime cross-fade on a reversal stays small. Writes blender_validation.json with the audits."""
    base = json.load(open(ROOT + '/artifacts/saw_stow/v2/baseline_v1.json'))
    a = rig(); rep = {}
    rep['action_hash'] = {n: {'now': list(_act_hash(bpy.data.actions[n])), 'v1': base['actions'][n],
                              'same': list(_act_hash(bpy.data.actions[n])) == base['actions'][n]} for n in ('Spin_Loop', 'Advance_Demo')}
    drift = {}
    for n, m in base['bones'].items():
        if not n.startswith(('Carriage', 'Spin_', 'Roll_', 'Slide_')) or n not in a.data.bones: continue
        cur = a.data.bones[n].matrix_local
        drift[n] = max(abs(cur[r][c] - m[r][c]) for r in range(4) for c in range(4))
    rep['rest_drift_max'] = max(drift.values()); rep['rest_drift_bone'] = max(drift, key=drift.get)
    stow, dep = _pose_table('Stow'), _pose_table('Deploy')
    n = len(stow) - 1
    def diff(A, B):
        dp = max((A[k].translation - B[k].translation).length for k in A)
        da = max(math.degrees(A[k].to_quaternion().rotation_difference(B[k].to_quaternion()).angle) for k in A)
        return dp, da
    ident = {k: Matrix.Identity(4) for k in stow[0]}
    rest = {pb.name: pb.bone.matrix_local.copy() for pb in a.pose.bones}
    rep['ends_mm'] = {'stow_start_vs_rest': round(diff(stow[0], rest)[0] * 1000, 3), 'stow_end_vs_deploy_start': round(diff(stow[n], dep[0])[0] * 1000, 3),
                      'deploy_end_vs_rest': round(diff(dep[n], rest)[0] * 1000, 3)}
    worst, per = (0, 0, 0), []
    for f in range(n + 1):
        dp, da = diff(stow[f], dep[n - f]); per.append((round(dp * 100, 2), round(da, 2)))
        if dp > worst[1]: worst = (f, dp, da)
    top = sorted(range(n + 1), key=lambda f: -per[f][0])[:6]
    rep['stow_vs_deploy'] = {'max_cm': round(max(p[0] for p in per), 2), 'max_deg': round(max(p[1] for p in per), 2),
                             'worst_frames': [(f, per[f]) for f in top],
                             'frames_over_3cm': sum(1 for p in per if p[0] > 3.0), 'frames_over_2deg': sum(1 for p in per if p[1] > 2.0)}
    f = top[0]
    rep['stow_vs_deploy']['worst_bones'] = sorted(((k, round((stow[f][k].translation - dep[n - f][k].translation).length * 100, 2)) for k in stow[f]),
                                                  key=lambda x: -x[1])[:6]
    out = {'verify': rep}
    for tag in ('baked_stow', 'baked_deploy'):
        p = f'{OUT}/audit_{tag}.json'
        if os.path.exists(p): out[tag] = json.load(open(p))
    p = ROOT + '/artifacts/saw_stow/v2/transport_clearance.json'
    if os.path.exists(p):
        t = json.load(open(p))
        out['transport'] = {k: v for k, v in t.items() if k != 'samples'}
        out['transport']['per_time'] = [(r['time'], r['intersections'], r['control_intersections'], r['min_clearance']) for r in t['samples']]
    with open(ROOT + '/artifacts/saw_stow/v2/blender_validation.json', 'w') as fh: json.dump(out, fh, indent=1, default=str)
    REPORT['verify'] = rep

def stage_transport():
    """Stowed towers (rest pose) against the service vessel while it raises and transfers the carriage.
    Vessel triangles come from tests/saw_stow_dock_export.gd, already in the carriage's Blender frame."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    base = ROOT + '/artifacts/saw_stow/v2/dock/dock_tris'
    index = json.load(open(base + '.json'))
    raw = np.fromfile(base + '.bin', dtype='<f4').reshape(-1, 3, 3)
    sc = scene()
    a, by_bone, blades, modules, carriage, ref = audit_groups()
    with ExportState('Stow', booleans=False):
        sc.frame_set(0)
        stow = Group('stow', [o for o in bpy.data.objects if o.get('stow_v2') and o.type == 'MESH']).build()
        control = Group('carriage', carriage).build() # the existing carriage: known to ride the vessel
    part_of = []
    for o, co, pl in stow.parts: part_of += [o.name] * len(pl)
    pts = stow.world
    rows, at = [], 0
    for rec in index:
        tris = raw[at:at + rec['triangles']]; at += rec['triangles']
        owner = []
        for name, n in rec['owners']: owner += [name] * n
        verts = [Vector(v) for v in tris.reshape(-1, 3)]
        dock = BVHTree.FromPolygons(verts, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
        hits = stow.bvh.overlap(dock)
        control_hits = control.bvh.overlap(dock) if control.bvh else []
        if hits:
            hit_tris = tris[sorted({b for _, b in hits})].reshape(-1, 3)
            detail = {'stow_parts': sorted({part_of[x] for x, _ in hits})[:8],
                      'dock_hit_box': [[round(float(v), 3) for v in hit_tris.min(0)], [round(float(v), 3) for v in hit_tris.max(0)]]}
        else: detail = {}
        lo, hi = tris.reshape(-1, 3).min(0) - 0.5, tris.reshape(-1, 3).max(0) + 0.5
        near = pts[((pts >= lo) & (pts <= hi)).all(1)]
        best, where = 9.0, None
        for p in near[::2]:
            loc, nrm, idx, dist = dock.find_nearest(Vector(p))
            if loc is not None and dist < best: best, where = dist, (owner[idx], [round(float(c), 3) for c in p])
        rows.append({'time': rec['time'], 'triangles': rec['triangles'], 'intersections': len(hits),
                     'hit_parts': sorted({owner[b] for _, b in hits})[:6], 'min_clearance': round(best, 4), 'nearest': where,
                     'control_intersections': len(control_hits), **detail})
    worst = min(rows, key=lambda r: r['min_clearance'])
    rep = {'samples': rows, 'intersecting_samples': sum(1 for r in rows if r['intersections']),
           'min_clearance': worst['min_clearance'], 'min_at': worst['time'], 'min_part': worst['nearest']}
    with open(ROOT + '/artifacts/saw_stow/v2/transport_clearance.json', 'w') as fh: json.dump(rep, fh, indent=1)
    REPORT['transport'] = {k: v for k, v in rep.items() if k != 'samples'}

def checkpoint(label):
    d = f'{OUT}/checkpoints'; os.makedirs(d, exist_ok=True)
    p = f'{d}/{time.strftime("%Y%m%d_%H%M%S")}_{label}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=p, copy=True)
    REPORT['checkpoint'] = p

STAGES = {'cleanup': stage_cleanup, 'bones': stage_bones, 'blockout': stage_blockout, 'rig': stage_rig,
          'motion': stage_motion, 'audit': stage_audit, 'review': stage_review, 'frames': stage_frames,
          'detail': stage_detail, 'dynamics': stage_dynamics, 'bake': stage_bake, 'export': stage_export,
          'sidecar': stage_sidecar, 'verify': stage_verify, 'transport': stage_transport}

if 'STAGE' in globals():
    for st in (globals().get('STAGE') or '').split(','):
        st = st.strip()
        if st: scene(); STAGES[st]()
    result = REPORT
