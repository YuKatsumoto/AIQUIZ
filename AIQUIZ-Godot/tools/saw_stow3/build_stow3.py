"""Wall speed tab stow v3 for the linked chip saw carriage: side gantries (門型クレーン).

Run in the live Blender 5.1 session with
assets/hazards/linked_saw_carriage_source/linked_saw_carriage.blend open:

    STAGE = 'cleanup,bones,parts'
    exec(open(r'G:/AIQUIZ-Main/AIQUIZ-Godot/tools/saw_stow3/build_stow3.py', encoding='utf-8').read())

Stages (idempotent, run in order; details: assets/hazards/linked_saw_carriage_source/README.md):
    cleanup    remove the v2 davit towers, beams, jaws, controls, physics and actions; keep the blade rams
    bones      gantry bones; the rest pose is the folded gantry hanging beside the conveyor wall
    parts      hard-surface gantry, hinge mounts, hook block, spreader, clamps and rope
    bake       Stow / Deploy / Gantry_Upright clips computed from the timeline below, keyed on every bone
    export     GLB (Spin_Loop, Advance_Demo, Stow, Deploy, Gantry_Upright) with one skinned stow mesh
    sidecar    assets/hazards/linked_saw_carriage_stow.json (events, wall/station/chair spans, speed curves)
    audit      BVH interference and clearance of both clips against the carriage, conveyor and station
    transport  folded upright gantry against the service vessel (tests/saw_stow_dock_export.gd first)
    review     renders from the review cameras (artifacts/saw_stow/v3/blender/review)
    tidy       remove the STOW3_Blockout scene and its proxies

Never start background Blender with --factory-startup: it drops the extension wheels here.

Carriage space: x across the belt, y travel, z up, belt surface z = 0. New bones point along +Y with roll 0
(local axes = world axes at rest), except Rope_* whose local Y runs down the rope so its length is a Y scale.
The motion is analytic: every clip is computed here and keyed directly; there are no drivers or physics.
"""
import bpy, bmesh, math, json, os, time
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), '..', '..', '..')).replace('\\', '/')
OUT = ROOT + '/artifacts/saw_stow/v3/blender'
GLB_PATH = ROOT + '/assets/hazards/linked_saw_carriage.glb'
JSON_PATH = ROOT + '/assets/hazards/linked_saw_carriage_stow.json'
SCENE = 'CUTLINE | 8-blade carriage'
FPS = 24 # Spin_Loop is 80 frames = 3.333 s at 24 fps; the scene must stay at 24 fps.
ARM, COLL = 'Carriage_Motion_Rig', 'SAW_Import'
TAG = 'stow_v3'
SKIN_NAME = 'SAW_StowSkinned'

# Blades and drive modules (rams, clevis and trunnion come from v2 and are kept).
X0 = [-10.5 + 3.0 * i for i in range(8)]
X1 = [-10.5, -9.65, -8.8, -7.95, 7.95, 8.8, 9.65, 10.5] # gathered module x, pitch 0.85 m
SIDE = [-1, -1, -1, -1, 1, 1, 1, 1]
A_HUB = 0.1075 # trunnion pin -> blade centre
RAM_BASE_Z, PIV0, PIV1 = 0.13, 0.2525, 2.20 # ram base; pin at rest / lifted (an upright blade's centre)
CLEVIS_DROP, RAM_LAP = 0.11, 0.06
RAM_REST_LEN = (PIV0 - CLEVIS_DROP - RAM_BASE_Z + 2 * RAM_LAP) / 3
BLADE_R = 1.45
RIM_FLOOR = 0.55 # lowest blade edge while it stands up (module tops are at 0.42)
XC = (X1[4] + X1[7]) / 2 + A_HUB # 9.3325: bunch centre at the belt end
XP = XC + 6.0 # 15.3325: parked bunch centre, hubs x 14.06..16.61 outside the operator station
HUB_OVER, HUB_PARK = 3.85, -1.90 # blade bottoms 2.40 over the station; tops 0.45 below the belt
CLAMP_X = [(k - 1.5) * 0.85 for k in range(4)] # blade planes along the spreader (outboard +)

# Gantry, one per side s. Portal frame P(a) = T(hinge) R_y(s a) F_s: local u outboard, v along y, w up the
# legs; a is the lean from plumb, outboard positive. Folded it hangs at A_HANG beside the conveyor wall.
# While the vessel transfers the carriage it rolls past the lift-bay posts (|x| >= 12.275, top z 0.605):
# below that height nothing may reach |x| 12.26, so the upright leg roots (half width 0.12) stand at 12.13.
HX, HY, HZ = 12.13, 1.76, 0.46
A_HANG = math.radians(177.0) # 3 deg outboard of plumb clears the side frame (x <= 12.0)
# Folded, the docked hook and spreader cross the operator station's y band, so everything that does must sweep
# at >= 2.85 m from the hinge to pass outboard of the station box (x <= 13.85, z <= 2.25): L0 - 1.17 >= 2.85.
L0, L_MAX = 4.0, 6.8 # hinge -> head beam centre, folded / extended (two stages of 1.4 m)
SHEAVE_IN = 0.23 # head beam centre -> rope sheave, down the legs
ROPE_MIN, ROPE_HANG = 0.06, 0.25 # docked / hanging free (clears the sheave block when the portal leans)
HOOK_DROP = 0.46 # rope end -> spreader beam centre
SHEAVE_TO_HUB = ROPE_HANG + HOOK_DROP + 0.10 + 0.04 + BLADE_R # 2.30
HOVER_UP = 0.60 # the spreader comes in this high over the bunch and finishes plumb (fingers straddle the blades)
A_UNDOCK = math.radians(10.0) # the hook unlatches from the head beam as the portal passes this lean
JAW_TRAVEL = 0.026

# Stow timeline (seconds). Deploy is its kinematic reverse; only the hanging sway is solved forward again.
# Consecutive moves overlap so the machine never comes to rest between them: the portal stands up and leans
# in in one sweep, the spreader settles onto the bunch as the lean ends, the bunch rises while it starts to
# swing out and starts down as the swing ends. Only the clamp is a dwell. The windows are checked by the
# audit stage (station, blades, rope).
T = {
    'brake': 0.85, 'swing_up': (0.0, 2.1), 'reach': (1.45, 2.3), 'lean_in': (1.75, 2.85), 'yaw': (1.85, 2.45),
    'rise': (0.45, 1.25), 'tilt': (0.80, 1.45), 'gather': (1.20, 2.75),
    'set_down': (2.75, 3.10), 'clamp': (3.10, 3.25), 'lift': (3.30, 4.10),
    'clevis_tilt': (3.95, 4.50), 'clevis_lower': (4.10, 4.90),
    'swing_out': (3.55, 5.25), 'lower': (4.85, 6.30), 'lock': 6.40, 'end': 6.55,
}
A_UP = math.radians(2.0) # the stand-up sweep aims just outboard of plumb; the lean-in takes over before it gets there
# Hanging sway: response to the sheave's acceleration (the hoist's anti-sway leaves a fraction), damping,
# extra damping before set-downs, and a soft limit on the shown lean.
SWAY = dict(kappa=0.10, zeta=0.60, boost=1.6, limit=math.radians(5.0))

MAT = {'yellow': 'End caps | safety amber', 'charcoal': 'Frame | charcoal powder coat', 'chrome': '02 | machined edge steel',
       'alu': 'Hardware | satin aluminum', 'black': 'Recesses | black oxide', 'rubber': 'Rollers | graphite rubber',
       'lens': 'MAT_BeaconLens'}
V2_BONES = ('Davit_', 'DavitS', 'Knuckle_', 'BeamFlyP_', 'BeamFlyN_', 'Jaw_')
REPORT = {}

def scene():
    s = bpy.data.scenes[SCENE]
    if bpy.context.window: bpy.context.window.scene = s
    return s

def rig(): return bpy.data.objects[ARM]
def sname(s): return 'L' if s < 0 else 'R'

def set_mode(obj, mode):
    vl = bpy.context.view_layer
    if bpy.context.object and bpy.context.object.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    for o in vl.objects: o.select_set(False)
    vl.objects.active = obj; obj.select_set(True)
    if mode != 'OBJECT': bpy.ops.object.mode_set(mode=mode)

class RestPose:
    def __enter__(self):
        self.a = rig(); self.prev = self.a.data.pose_position
        self.a.data.pose_position = 'REST'; bpy.context.view_layer.update()
    def __exit__(self, *exc):
        self.a.data.pose_position = self.prev; bpy.context.view_layer.update()

# ---------------------------------------------------------------- timeline math
def prof(t, span, a=0.3):
    """0 -> 1 over span with smooth acceleration, cruise and braking (peak speed 1 / (1 - a) of the mean)."""
    t0, t1 = span
    u = min(max((t - t0) / (t1 - t0), 0.0), 1.0)
    ramp = lambda w: a * (w ** 3 - 0.5 * w ** 4)
    if u < a: p = ramp(u / a)
    elif u <= 1.0 - a: p = 0.5 * a + (u - a)
    else: p = (1.0 - a) - ramp((1.0 - u) / a)
    return p / (1.0 - a)

def from_sheave(x, z):
    """Portal (lean, length) holding the rope sheave at (x, z), right-side frame."""
    return math.atan2(x - HX, z - HZ), math.hypot(x - HX, z - HZ) + SHEAVE_IN

def sheave_of(a, L):
    return HX + math.sin(a) * (L - SHEAVE_IN), HZ + math.cos(a) * (L - SHEAVE_IN)

LS_MAX = L_MAX - SHEAVE_IN
HOVER = (XC, PIV1 + SHEAVE_TO_HUB + HOVER_UP)
PICK = (XC, PIV1 + SHEAVE_TO_HUB)
TOP = (XC, HZ + math.sqrt(LS_MAX ** 2 - (HX - XC) ** 2))
A_HOVER, L_HOVER = from_sheave(*HOVER)
A_TOP = from_sheave(*TOP)[0]
A_PARK = math.asin((XP - HX) / LS_MAX)
ROPE_PARK = (HZ + LS_MAX * math.cos(A_PARK)) - (SHEAVE_TO_HUB - ROPE_HANG) - HUB_PARK

def z_reach(x):
    """Highest sheave the fully extended portal holds over x."""
    return HZ + math.sqrt(max(LS_MAX ** 2 - (x - HX) ** 2, 0.0))

def portal(t):
    """Right-side portal (lean, length) at stow time t."""
    if t < T['lift'][0]:
        # stand-up sweep and lean-in superposed; the set-down lowers the sheave straight down over the bunch
        a = A_HANG + (A_UP - A_HANG) * prof(t, T['swing_up'], 0.4) + (A_HOVER - A_UP) * prof(t, T['lean_in'])
        L = L0 + (L_HOVER - L0) * prof(t, T['reach'])
        if t <= T['set_down'][0]: return a, L
        x, z = sheave_of(a, L)
        return from_sheave(x, z - HOVER_UP * prof(t, T['set_down']))
    # carry: the swing moves the sheave out, the lift raises it toward the highest point the portal reaches there
    x = XC + (XP - XC) * prof(t, T['swing_out'])
    return from_sheave(x, PICK[1] + (z_reach(x) - PICK[1]) * prof(t, T['lift']))

def _undock_time():
    lo, hi = T['swing_up']
    for _ in range(60):
        m = (lo + hi) / 2
        lo, hi = (m, hi) if portal(m)[0] > A_UNDOCK else (lo, m)
    return hi
T_UNDOCK = _undock_time()

def rope_len(t):
    return (ROPE_MIN + (ROPE_HANG - ROPE_MIN) * prof(t, (T_UNDOCK, T_UNDOCK + 0.30))
            + (ROPE_PARK - ROPE_HANG) * prof(t, T['lower']))
def yaw(t): return 0.5 * math.pi * (1.0 - prof(t, T['yaw']))
def jaw(t): return prof(t, T['clamp'], 0.5)

def blade(t, i):
    """Module slide, ram lift and trunnion tilt (magnitude) of blade i at stow time t."""
    slide = (X1[i] - X0[i]) * prof(t, T['gather'])
    if t < T['clamp'][1]:
        lift = (PIV1 - PIV0) * prof(t, T['rise'])
        tilt = 0.5 * math.pi * prof(t, T['tilt'])
    else: # the empty clevis turns back and the ram sinks once the bunch has lifted clear
        lift = (PIV1 - PIV0) * (1.0 - prof(t, T['clevis_lower']))
        tilt = 0.5 * math.pi * (1.0 - prof(t, T['clevis_tilt']))
    return slide, lift, tilt

def clip_time(kind, t):
    return t if kind == 'Stow' else T['end'] - t

# ---------------------------------------------------------------- hanging sway (pendulum about the sheave)
SIM_DT = 1.0 / 240.0

def sway(kind):
    """Lean of the hook assembly from plumb (right-side frame, rad) at SIM_DT steps of clip time.

    Docked it is the portal's own lean; hanging free it swings under the sheave's acceleration (scaled by
    kappa: the hoist's anti-sway) and is damped hard before every set-down and docking."""
    L = T['end']; n = int(round(L / SIM_DT)) + 1
    kin = []
    for q in range(n):
        tc = clip_time(kind, q * SIM_DT)
        a, Lp = portal(tc)
        x, z = sheave_of(a, Lp)
        loaded = tc >= T['clamp'][1]
        kin.append((a, x, z, rope_len(tc) + (2.0 if loaded else 0.5), tc < T_UNDOCK))
    def acc(q, k):
        q0, q1 = max(q - 1, 0), min(q + 1, n - 1)
        return (kin[q1][k] - 2 * kin[q][k] + kin[q0][k]) / SIM_DT ** 2 if 0 < q < n - 1 else 0.0
    def vel(q, k):
        q0, q1 = max(q - 1, 0), min(q + 1, n - 1)
        return (kin[q1][k] - kin[q0][k]) / ((q1 - q0) * SIM_DT)
    # (damp from, plumb from, plumb until) in clip time: the hoist damps the sway, then holds the load plumb
    # while the fingers are around the blades and the blades come off / onto the trunnions
    if kind == 'Stow':
        quiet = [(T['set_down'][0] - 0.7, T['set_down'][0] - 0.05, T['lift'][0] + 0.40), (T['lower'][1] - 0.6, T['lock'] - 0.05, L + 1.0)]
        guide = []
    else:
        quiet = [(L - T['lift'][1] - 0.5, L - T['lift'][0] - 0.40, L - T['set_down'][0] + 0.05)]
        guide = [(L - T_UNDOCK - 0.6, L - T_UNDOCK)]
    th, om, out = 0.0, 0.0, []
    g, kap, z0, boost = 9.81, SWAY['kappa'], SWAY['zeta'], SWAY['boost']
    for q in range(n):
        t = q * SIM_DT
        a, x, z, l, docked = kin[q]
        if docked:
            th, om = a, vel(q, 0)
            out.append(th); continue
        w = math.sqrt(g / l)
        zeta = z0 + sum(boost * prof(t, (t0, t0 + 0.25)) * (1.0 - prof(t, (t2, t2 + 0.25))) for t0, t1, t2 in quiet)
        ax, az, dl = acc(q, 1), acc(q, 2), vel(q, 3)
        al = -(g / l) * math.sin(th) + kap * (ax * math.cos(th) - az * math.sin(th)) / l - 2 * zeta * w * om - 2 * dl / l * om
        om += al * SIM_DT; th += om * SIM_DT
        lim = SWAY['limit']
        # right after undocking the hook still carries the portal's lean; the soft limit takes over gradually
        w = prof(t, (T_UNDOCK, T_UNDOCK + 0.6)) if kind == 'Stow' else 1.0
        shown = th * (1.0 - w) + lim * math.tanh(th / lim) * w
        for t0, t1, t2 in quiet: shown *= 1.0 - prof(t, (t1 - 0.30, t1), 0.5) * (1.0 - prof(t, (t2, t2 + 0.30), 0.5))
        for t0, t1 in guide:
            k = prof(t, (t0, t1), 0.5)
            shown = shown * (1.0 - k) + a * k
        out.append(shown)
    return out

# ---------------------------------------------------------------- per-frame bone poses (armature space)
def F(s): return Matrix.Identity(4) if s > 0 else Matrix.Rotation(math.pi, 4, 'Z')
def Ry(a): return Matrix.Rotation(a, 4, 'Y')
def Tr(x, y=0.0, z=0.0): return Matrix.Translation((x, y, z))

def portal_m(s, a): return Tr(s * HX, 0.0, HZ) @ Ry(s * a) @ F(s)
def sheave_m(s, a, L): return portal_m(s, a) @ Tr(0, 0, L - SHEAVE_IN)
def hook_m(s, a, L, th, rope):
    """Hook block frame (origin at the spreader beam centre, unyawed), hanging th from plumb under the sheave."""
    p = sheave_m(s, a, L).translation
    return Tr(*p) @ Ry(s * th) @ F(s) @ Tr(0, 0, -(rope + HOOK_DROP))
def rope_m(s, a, L, th, rope):
    p = sheave_m(s, a, L).translation
    return Tr(*p) @ Ry(s * th) @ F(s) @ Matrix.Rotation(-math.pi / 2, 4, 'X') @ Matrix.Scale(rope / ROPE_MIN, 4, Vector((0, 1, 0)))

REST_STATE = dict(a=A_HANG, L=L0, th=A_HANG, rope=ROPE_MIN, psi=0.5 * math.pi, jaw=0.0)

def gantry_frames(s, st):
    """Part frames of one side's gantry for a state dict (a, L, th, rope, psi, jaw)."""
    a, L, ext = st['a'], st['L'], st['L'] - L0
    P = portal_m(s, a)
    H = hook_m(s, a, L, st['th'], st['rope'])
    S = H @ Matrix.Rotation(st['psi'], 4, 'Z')
    fr = {f'Gantry_{sname(s)}': P, f'GantryS2_{sname(s)}': P @ Tr(0, 0, 0.5 * ext), f'GantryS3_{sname(s)}': P @ Tr(0, 0, ext),
          f'Hook_{sname(s)}': H, f'Spreader_{sname(s)}': S, f'Rope_{sname(s)}': rope_m(s, a, L, st['th'], st['rope'])}
    for k in range(4):
        fr[f'GJaw_{sname(s)}_{k + 1}'] = S @ Tr(JAW_TRAVEL * st['jaw'])
    return fr

def rest_frames():
    out = {}
    for s in (-1, 1): out.update(gantry_frames(s, REST_STATE))
    return out

def bone_rests():
    return {b.name: b.matrix_local.copy() for b in rig().data.bones}

def blade_poses(R, slide, lift, tilt, i):
    """Armature-space poses of blade i's module chain (Spin carried by the trunnion)."""
    k = f'{i + 1:02d}'; s = SIDE[i]
    la = ((PIV0 + lift) - CLEVIS_DROP - RAM_BASE_Z + 2 * RAM_LAP) / 3
    move = Tr(slide)
    pin = Vector((X0[i], 0.0, PIV0))
    out = {f'Slide_{k}': move @ R[f'Slide_{k}'], f'Ram_{k}': move @ R[f'Ram_{k}'],
           f'Hinge_{k}': move @ Tr(0, 0, lift) @ R[f'Hinge_{k}']}
    for st, mult in (('A', 0), ('B', 1), ('C', 2)):
        out[f'Ram{st}_{k}'] = move @ Tr(0, 0, mult * (la - RAM_REST_LEN)) @ R[f'Ram{st}_{k}'] @ Matrix.Scale(la / RAM_REST_LEN, 4, Vector((0, 0, 1)))
    tm = move @ Tr(0, 0, lift) @ Tr(*pin) @ Ry(s * tilt) @ Tr(*(-pin))
    out[f'Tilt_{k}'] = tm @ R[f'Tilt_{k}']
    out[f'Spin_{k}'] = tm @ R[f'Spin_{k}']
    return out

def clip_poses(kind):
    """{frame: {bone: armature-space pose}} for a clip, plus the sway series."""
    R = bone_rests(); W0 = rest_frames()
    th_series = sway(kind)
    L = T['end']; nf = int(round(L * FPS))
    t_clamp = T['clamp'][1] if kind == 'Stow' else L - T['clamp'][1]
    carry = {}
    frames = {}
    def state_at(t):
        tc = clip_time(kind, t)
        a, Lp = portal(tc)
        q = min(len(th_series) - 1, int(round(t / SIM_DT)))
        return tc, {'a': a, 'L': Lp, 'th': th_series[q], 'rope': rope_len(tc), 'psi': yaw(tc), 'jaw': jaw(tc)}
    def pose_at(t):
        tc, st = state_at(t)
        pose = {}
        for s in (-1, 1):
            for name, M in gantry_frames(s, st).items():
                pose[name] = M @ W0[name].inverted() @ R[name]
        for i in range(8):
            pose.update(blade_poses(R, *blade(tc, i), i))
        return tc, pose
    # the bunch is handed over at the clamp instant of this clip
    _, at_clamp = pose_at(t_clamp)
    for i in range(8):
        k = f'{i + 1:02d}'; s = SIDE[i]
        carry[k] = at_clamp[f'Spreader_{sname(s)}'].inverted() @ at_clamp[f'Spin_{k}']
    for f in range(nf + 1):
        t = f / FPS
        tc, pose = pose_at(t)
        held = (t >= t_clamp) if kind == 'Stow' else (t <= t_clamp)
        if held:
            for i in range(8):
                k = f'{i + 1:02d}'
                pose[f'Spin_{k}'] = pose[f'Spreader_{sname(SIDE[i])}'] @ carry[k]
        frames[f] = pose
    return frames, th_series

def folded_pose(a):
    """Folded, docked gantries turned on their hinges to lean a (0 = upright on the vessel, A_HANG = rest)."""
    R = bone_rests(); W0 = rest_frames(); pose = {}
    for s in (-1, 1):
        st = dict(REST_STATE); st['a'] = a; st['th'] = a
        for name, M in gantry_frames(s, st).items(): pose[name] = M @ W0[name].inverted() @ R[name]
    return pose

# On the vessel the folded gantry leans 2 deg inboard: its head beam (which crosses the lift-bay posts' y band
# while the carriage rises between them) stays inside |x| 12.26. 179 deg from rest, so the fold-down slerp
# still takes the outboard arc.
A_TRANSPORT = math.radians(-2.0)

def upright_pose():
    pose = folded_pose(A_TRANSPORT)
    return {0: pose, 1: pose}

# SawChaseController: upright on the vessel, folding down GANTRY_FOLD_DELAY after the transfer (dock READY_TIME)
DOCK_READY, FOLD_DELAY, FOLD_SECONDS = 6.20, 0.10, 1.6
def dock_lean(t):
    x = min(max((t - DOCK_READY - FOLD_DELAY) / FOLD_SECONDS, 0.0), 1.0)
    return A_TRANSPORT + (A_HANG - A_TRANSPORT) * x * x * (3.0 - 2.0 * x)

# ---------------------------------------------------------------- cleanup
def stage_cleanup():
    a = rig(); removed = []
    def drop(o):
        me = o.data if o.type == 'MESH' else None
        removed.append(o.name); bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)
    for o in list(bpy.data.objects):
        if o.get('stow_cutter') or o.name.startswith('DavitBase_') or (o.get('stow_v2') and o.parent_bone.startswith(V2_BONES)):
            drop(o)
    for cname in ('CTL_StowRig', 'CTL_StowPhysics'):
        c = bpy.data.collections.get(cname)
        if c:
            for o in list(c.all_objects): drop(o)
            bpy.data.collections.remove(c)
    sc = scene()
    if sc.rigidbody_world:
        bpy.ops.rigidbody.world_remove()
    for cname in ('RigidBodyWorld', 'RigidBodyConstraints'):
        c = bpy.data.collections.get(cname)
        if c and not c.all_objects: bpy.data.collections.remove(c)
    ad = a.animation_data
    keep = 0
    for fc in list(ad.drivers):
        bone = fc.data_path.split('"')[1] if '"' in fc.data_path else ''
        if bone.startswith(('RamA_', 'RamB_', 'RamC_')): keep += 1; continue
        ad.drivers.remove(fc)
    for pb in a.pose.bones:
        for c in list(pb.constraints): pb.constraints.remove(c)
    set_mode(a, 'EDIT')
    eb = a.data.edit_bones
    gone = [b.name for b in eb if b.name.startswith(V2_BONES)]
    for n in gone: eb.remove(eb[n])
    set_mode(a, 'OBJECT')
    ad.action = None
    for tr in [t for t in ad.nla_tracks if t.name in ('Stow', 'Deploy', 'Gantry_Upright')]: ad.nla_tracks.remove(tr)
    for n in ('Stow_ctl', 'Deploy_ctl', 'Stow_src', 'Deploy_src', 'Stow', 'Deploy'):
        act = bpy.data.actions.get(n)
        if act and not act.get(TAG): bpy.data.actions.remove(act)
    kept = 0
    for o in bpy.data.objects:
        if o.get('stow_v2'):
            del o['stow_v2']; o[TAG] = True; kept += 1
    REPORT['cleanup'] = {'objects_removed': len(removed), 'bones_removed': len(gone), 'drivers_kept': keep, 'parts_kept': kept,
                         'bones_now': len(a.data.bones)}

# ---------------------------------------------------------------- bones
def bone_specs():
    """(name, parent, armature-space rest matrix) of the gantry bones, rest = folded and docked."""
    W = rest_frames(); out = []
    for s in (-1, 1):
        n = sname(s)
        hinge = Tr(s * HX, 0.0, HZ)
        out += [(f'Gantry_{n}', 'Carriage', hinge), (f'GantryS2_{n}', f'Gantry_{n}', hinge), (f'GantryS3_{n}', f'GantryS2_{n}', hinge)]
        out.append((f'Hook_{n}', f'GantryS3_{n}', Tr(*W[f'Hook_{n}'].translation)))
        out.append((f'Spreader_{n}', f'Hook_{n}', Tr(*W[f'Spreader_{n}'].translation)))
        for k in range(4):
            jp = W[f'Spreader_{n}'] @ Vector((CLAMP_X[k] - 0.045, 0.0, -0.30))
            out.append((f'GJaw_{n}_{k + 1}', f'Spreader_{n}', Tr(*jp)))
        r = W[f'Rope_{n}'].copy() # oriented down the rope (local Y), unit scale at rest
        out.append((f'Rope_{n}', f'GantryS3_{n}', r))
    return out

def stage_bones():
    a = rig(); set_mode(a, 'EDIT'); eb = a.data.edit_bones; made = []
    for name, parent, M in bone_specs():
        b = eb.get(name) or eb.new(name)
        b.head = M.translation; b.tail = M.translation + Vector((0, 0.2, 0)); b.roll = 0.0
        if name.startswith('Rope_'):
            b.matrix = M; b.length = 0.2
        b.parent, b.use_connect = eb[parent], False
        b.use_deform = True; b.inherit_scale = 'FULL'
        made.append(name)
    set_mode(a, 'OBJECT')
    for name in made:
        pb = a.pose.bones[name]
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
    REPORT['bones'] = {'made': len(made), 'total': len(a.data.bones), 'undock_s': round(T_UNDOCK, 3),
                       'hover': [round(math.degrees(A_HOVER), 2), round(L_HOVER, 3)], 'top_hub': round(TOP[1] - SHEAVE_TO_HUB, 3),
                       'park_deg': round(math.degrees(A_PARK), 2), 'rope_park': round(ROPE_PARK, 3)}

# ---------------------------------------------------------------- geometry helpers (as in v2)
def _merge(dst, src):
    me = bpy.data.meshes.new('_tmp'); src.to_mesh(me); src.free(); dst.from_mesh(me); bpy.data.meshes.remove(me)

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

def chamfer_rect(w, d, c):
    a, b = w / 2, d / 2
    return [(a, -b + c), (a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c), (-a + c, -b), (a - c, -b)]

def loft(bm, frame, stations, cap0=True, cap1=True):
    """Bridge equal-count profiles (u, v) at axial stations w along frame (origin, U, V, W)."""
    o, U, V, W = (Vector(x) for x in frame)
    rings = [[bm.verts.new(o + U * u + V * v + W * w) for u, v in prof_] for w, prof_ in stations]
    n = len(rings[0]); faces = []
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            if (r0[i].co - r1[i].co).length > 1e-7 or (r0[j].co - r1[j].co).length > 1e-7:
                faces.append(bm.faces.new((r0[i], r0[j], r1[j], r1[i])))
    if cap0: faces.append(bm.faces.new(list(reversed(rings[0]))))
    if cap1: faces.append(bm.faces.new(rings[-1]))
    if U.cross(V).dot(W) < 0.0: bmesh.ops.reverse_faces(bm, faces=faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    return bm

def hard_surface(o, width=0.006, segments=2):
    for m in list(o.modifiers):
        if m.name in ('Bevel', 'WeightedNormal'): o.modifiers.remove(m)
    bv = o.modifiers.new('Bevel', 'BEVEL'); bv.width = width; bv.segments = segments
    bv.limit_method = 'ANGLE'; bv.angle_limit = math.radians(35); bv.harden_normals = True
    o.modifiers.new('WeightedNormal', 'WEIGHTED_NORMAL').keep_sharp = True
    for p in o.data.polygons: p.use_smooth = True
    return o

def part(name, bone, bm, mat, frame):
    """Mesh built in a part frame's local coordinates, placed at its rest frame and parented to a bone."""
    bm.transform(frame)
    origin = frame.translation.copy()
    bmesh.ops.translate(bm, verts=bm.verts, vec=-origin)
    me = bpy.data.meshes.get(name) or bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.clear(); me.materials.append(bpy.data.materials[MAT[mat]])
    o = bpy.data.objects.get(name)
    if o is None:
        o = bpy.data.objects.new(name, me); bpy.data.collections[COLL].objects.link(o)
    o.data = me
    o.parent, o.parent_type, o.parent_bone = rig(), 'BONE', bone
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.matrix_world = Matrix.Translation(origin)
    o['saw_src'] = True; o[TAG] = True; o['stow_v3_part'] = True
    for p in me.polygons: p.use_smooth = False
    return o

# ---------------------------------------------------------------- parts
def remove_parts():
    for o in [o for o in bpy.data.objects if o.get('stow_v3_part')]:
        me = o.data; bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)

def stage_parts():
    remove_parts()
    W = rest_frames(); made = []
    X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
    def add(o): made.append(o.name); return o
    with RestPose():
        for s in (-1, 1):
            n = sname(s)
            P = W[f'Gantry_{n}']
            # static hinge mounts on the bogie ends (Carriage): a plate on the bogie spine and the luff drum. The
            # service vessel's lift-bay posts stand at |x| >= 12.275, |y| 1.14..1.66 (top z 0.605): inside that band
            # nothing reaches past |x| 12.24, and the drum starts outboard of it at |y| 1.665.
            for e in (-1, 1):
                ylo, yhi = sorted((e * 1.600, e * 1.645))
                x0, x1 = sorted((s * 12.03, s * 12.24))
                bm = bmesh.new(); bm_box(bm, (x0, ylo, 0.30), (x1, yhi, 0.58))
                add(hard_surface(part(f'GantryMount_{n}{"A" if e > 0 else "F"} | hinge plate', 'Carriage', bm, 'charcoal', Matrix.Identity(4)), 0.004))
                bm = bmesh.new()
                d0, d1 = sorted((e * 1.665, e * 1.870))
                bm_cyl(bm, 0.110, d0, d1, 40, 'Y', at=(s * HX, 0, HZ))
                add(hard_surface(part(f'GantryMount_{n}{"A" if e > 0 else "F"} | luff drum', 'Carriage', bm, 'charcoal', Matrix.Identity(4)), 0.004))
                bm = bmesh.new()
                for k in range(6):
                    ang = 2 * math.pi * k / 6
                    lo_, hi_ = sorted((e * 1.870, e * 1.880))
                    bm_cyl(bm, 0.010, lo_, hi_, 8, 'Y', at=(s * HX + 0.08 * math.cos(ang), 0, HZ + 0.08 * math.sin(ang)))
                lo_, hi_ = sorted((e * 1.870, e * 1.884))
                bm_cyl(bm, 0.045, lo_, hi_, 20, 'Y', at=(s * HX, 0, HZ))
                add(part(f'GantryMount_{n}{"A" if e > 0 else "F"} | drum bolts', 'Carriage', bm, 'alu', Matrix.Identity(4)))
            for v in (-HY, HY):
                # base sleeve: chamfered box section from the drum to the first collar
                bm = bmesh.new()
                loft(bm, ((0, v, 0), X, Y, Z), [(-0.05, chamfer_rect(0.24, 0.17, 0.02)), (L0 - 0.30, chamfer_rect(0.24, 0.17, 0.02))])
                add(hard_surface(part(f'Gantry_{n}{v:+.0f} | base sleeve', f'Gantry_{n}', bm, 'charcoal', P), 0.004))
                bm = bmesh.new()
                loft(bm, ((0, v, 0), X, Y, Z), [(L0 - 0.38, chamfer_rect(0.25, 0.18, 0.02)), (L0 - 0.28, chamfer_rect(0.25, 0.18, 0.02)),
                                                (L0 - 0.28, chamfer_rect(0.21, 0.145, 0.014)), (L0 - 0.40, chamfer_rect(0.21, 0.145, 0.014))])
                add(hard_surface(part(f'Gantry_{n}{v:+.0f} | sleeve collar', f'Gantry_{n}', bm, 'black', P), 0.003))
                bm = bmesh.new() # hydraulic lines on the outboard face, clamped twice; above the posts' tops on the vessel
                for dv in (-0.035, 0.035):
                    bm_box(bm, (0.12, v + dv - 0.011, 0.30), (0.142, v + dv + 0.011, L0 - 0.50))
                for w in (0.8, L0 - 1.2):
                    bm_box(bm, (0.12, v - 0.06, w - 0.015), (0.155, v + 0.06, w + 0.015))
                add(part(f'Gantry_{n}{v:+.0f} | hydraulic lines', f'Gantry_{n}', bm, 'rubber', P))
                bm = bmesh.new() # hazard band near the root, the only yellow on the folded leg
                loft(bm, ((0, v, 0), X, Y, Z), [(0.30, chamfer_rect(0.246, 0.176, 0.02)), (0.42, chamfer_rect(0.246, 0.176, 0.02))])
                add(part(f'Gantry_{n}{v:+.0f} | hazard band', f'Gantry_{n}', bm, 'yellow', P))
                # second stage (yellow) and third stage (charcoal), nested with a 2 cm running gap
                bm = bmesh.new()
                loft(bm, ((0, v, 0), X, Y, Z), [(0.05, chamfer_rect(0.20, 0.13, 0.016)), (L0 - 0.20, chamfer_rect(0.20, 0.13, 0.016))])
                add(hard_surface(part(f'GantryS2_{n}{v:+.0f} | stage', f'GantryS2_{n}', bm, 'yellow', P), 0.004))
                bm = bmesh.new()
                loft(bm, ((0, v, 0), X, Y, Z), [(L0 - 0.26, chamfer_rect(0.215, 0.145, 0.016)), (L0 - 0.19, chamfer_rect(0.215, 0.145, 0.016)),
                                                (L0 - 0.19, chamfer_rect(0.17, 0.10, 0.012)), (L0 - 0.30, chamfer_rect(0.17, 0.10, 0.012))])
                add(hard_surface(part(f'GantryS2_{n}{v:+.0f} | collar', f'GantryS2_{n}', bm, 'black', P), 0.003))
                bm = bmesh.new()
                loft(bm, ((0, v, 0), X, Y, Z), [(0.12, chamfer_rect(0.16, 0.095, 0.012)), (L0 - 0.10, chamfer_rect(0.16, 0.095, 0.012))])
                add(hard_surface(part(f'GantryS3_{n}{v:+.0f} | stage', f'GantryS3_{n}', bm, 'charcoal', P), 0.003))
            # head beam across the legs: box girder, yellow-and-black ends, sheave block, winch and beacons
            bm = bmesh.new()
            loft(bm, ((0, -1.93, L0), X, Z, Y), [(0.0, chamfer_rect(0.24, 0.26, 0.025)), (3.86, chamfer_rect(0.24, 0.26, 0.025))])
            add(hard_surface(part(f'GantryS3_{n} | head beam', f'GantryS3_{n}', bm, 'charcoal', P), 0.005))
            for e in (-1, 1):
                bm = bmesh.new()
                ylo, yhi = sorted((e * 1.93, e * 1.95))
                bm_box(bm, (-0.125, ylo, L0 - 0.135), (0.125, yhi, L0 + 0.135))
                add(part(f'GantryS3_{n}{"A" if e > 0 else "F"} | end plate', f'GantryS3_{n}', bm, 'yellow', P))
                bm = bmesh.new()
                for q in range(3):
                    yc = e * (1.70 - 0.12 * q)
                    bm_box(bm, (-0.123, yc - 0.03, L0 - 0.132), (0.123, yc + 0.03, L0 + 0.132))
                add(part(f'GantryS3_{n}{"A" if e > 0 else "F"} | hazard stripes', f'GantryS3_{n}', bm, 'yellow', P))
                bm = bmesh.new() # beacon on the head beam's outer face
                bm_cyl(bm, 0.055, L0 + 0.13, L0 + 0.16, 24, at=(0, e * 1.45, 0)); bm_cyl(bm, 0.032, L0 + 0.27, L0 + 0.29, 20, at=(0, e * 1.45, 0))
                add(part(f'GantryS3_{n}{"A" if e > 0 else "F"} | beacon base', f'GantryS3_{n}', bm, 'black', P))
                bm = bmesh.new()
                loft(bm, ((0, e * 1.45, 0), X, Y, Z), [(L0 + 0.16, [(0.045 * math.cos(2 * math.pi * k / 20), 0.045 * math.sin(2 * math.pi * k / 20)) for k in range(20)]),
                                                     (L0 + 0.25, [(0.045 * math.cos(2 * math.pi * k / 20), 0.045 * math.sin(2 * math.pi * k / 20)) for k in range(20)]),
                                                     (L0 + 0.27, [(0.032 * math.cos(2 * math.pi * k / 20), 0.032 * math.sin(2 * math.pi * k / 20)) for k in range(20)])])
                add(part(f'GantryS3_{n}{"A" if e > 0 else "F"} | beacon lens', f'GantryS3_{n}', bm, 'lens', P))
            bm = bmesh.new()
            bm_cyl(bm, 0.12, -0.42, 0.42, 32, 'Y', at=(0, 0, L0 + 0.26))
            add(hard_surface(part(f'GantryS3_{n} | hoist winch', f'GantryS3_{n}', bm, 'yellow', P), 0.004))
            bm = bmesh.new()
            for e in (-1, 1): bm_cyl(bm, 0.128, *sorted((e * 0.42, e * 0.46)), 32, 'Y', at=(0, 0, L0 + 0.26))
            bm_box(bm, (-0.10, 0.46, L0 + 0.13), (0.10, 0.60, L0 + 0.36))
            add(part(f'GantryS3_{n} | winch flanges and motor', f'GantryS3_{n}', bm, 'black', P))
            bm = bmesh.new()
            bm_box(bm, (-0.085, -0.15, L0 - 0.22), (0.085, 0.15, L0 - 0.13))
            for dv in (-0.06, 0.06): bm_cyl(bm, 0.070, -0.012, 0.012, 24, 'X', at=(0, dv, L0 - 0.20))
            add(hard_surface(part(f'GantryS3_{n} | sheave block', f'GantryS3_{n}', bm, 'charcoal', P), 0.003))
            # hook block (Hook) and swivelling spreader (Spreader) in the spreader frame: x along the beam, z up
            Hm, Sm = W[f'Hook_{n}'], W[f'Spreader_{n}']
            bm = bmesh.new()
            loft(bm, ((0, 0, 0), X, Y, Z), [(0.16, chamfer_rect(0.30, 0.40, 0.04)), (0.44, chamfer_rect(0.30, 0.40, 0.04)),
                                            (0.46, chamfer_rect(0.24, 0.34, 0.04))])
            add(hard_surface(part(f'Hook_{n} | hook block', f'Hook_{n}', bm, 'yellow', Hm), 0.004))
            bm = bmesh.new()
            for dv in (-0.06, 0.06): bm_cyl(bm, 0.09, -0.016, 0.016, 28, 'X', at=(0, dv, 0.34))
            bm_cyl(bm, 0.07, 0.10, 0.16, 24)
            add(part(f'Hook_{n} | sheaves and swivel', f'Hook_{n}', bm, 'black', Hm))
            bm = bmesh.new()
            loft(bm, ((-1.45, 0, 0), Y, Z, X), [(0.0, chamfer_rect(0.16, 0.20, 0.02)), (2.90, chamfer_rect(0.16, 0.20, 0.02))])
            add(hard_surface(part(f'Spreader_{n} | spreader beam', f'Spreader_{n}', bm, 'yellow', Sm), 0.004))
            bm = bmesh.new()
            for e in (-1, 1):
                for q in range(3): bm_box(bm, (e * (1.30 - 0.07 * q) - 0.02, -0.081, -0.098), (e * (1.30 - 0.07 * q) + 0.02, 0.081, 0.098))
            add(part(f'Spreader_{n} | end stripes', f'Spreader_{n}', bm, 'black', Sm))
            bm = bmesh.new()
            for xk in CLAMP_X:
                bm_box(bm, (xk - 0.085, -0.11, -0.19), (xk + 0.085, 0.11, -0.10))
            add(hard_surface(part(f'Spreader_{n} | clamp housings', f'Spreader_{n}', bm, 'charcoal', Sm), 0.003))
            bm = bmesh.new()
            for xk in CLAMP_X:
                bm_box(bm, (xk + 0.033, -0.07, -0.42), (xk + 0.057, 0.07, -0.18))
            add(hard_surface(part(f'Spreader_{n} | fixed fingers', f'Spreader_{n}', bm, 'black', Sm), 0.002))
            for k, xk in enumerate(CLAMP_X):
                bm = bmesh.new()
                bm_box(bm, (xk - 0.057, -0.07, -0.42), (xk - 0.033, 0.07, -0.20))
                bm_box(bm, (xk - 0.075, -0.05, -0.20), (xk - 0.033, 0.05, -0.17))
                add(hard_surface(part(f'GJaw_{n}_{k + 1} | moving finger', f'GJaw_{n}_{k + 1}', bm, 'black', Sm), 0.002))
            # rope: two falls down the rope bone, ROPE_MIN long at rest and stretched by its Y scale
            Rm = W[f'Rope_{n}']
            bm = bmesh.new()
            for dv in (-0.06, 0.06): bm_cyl(bm, 0.013, 0.0, ROPE_MIN, 8, 'Y', at=(0, 0, dv))
            add(part(f'Rope_{n} | wire falls', f'Rope_{n}', bm, 'black', Rm))
    REPORT['parts'] = {'parts': len(made)}

# ---------------------------------------------------------------- bake
def write_action(name, frames):
    a = rig(); ad = a.animation_data or a.animation_data_create()
    act = bpy.data.actions.get(name)
    if act: bpy.data.actions.remove(act)
    act = bpy.data.actions.new(name); act.use_fake_user = True; act[TAG] = True
    prev_action = ad.action
    ad.action = act
    R = bone_rests()
    bones = [b for b in a.data.bones if not b.name.startswith(('Carriage', 'Roll_'))]
    keys = sorted(frames)
    lin = bpy.types.Keyframe.bl_rna.properties['interpolation'].enum_items['LINEAR'].value
    for b in bones:
        n = b.name; parent = b.parent.name if b.parent else None
        seq = []
        prevq = None
        for f in keys:
            pose = frames[f]
            Pb = pose.get(n, R[n])
            Pp = pose.get(parent, R[parent]) if parent else Matrix.Identity(4)
            Rp = R[parent] if parent else Matrix.Identity(4)
            basis = R[n].inverted() @ Rp @ Pp.inverted() @ Pb
            loc, q, scl = basis.decompose()
            q.normalize()
            if prevq is not None and prevq.dot(q) < 0: q.negate()
            prevq = q
            seq.append((loc, q, scl))
        for prop, vals in (('location', [tuple(l) for l, _, _ in seq]), ('rotation_quaternion', [tuple(q) for _, q, _ in seq]),
                           ('scale', [tuple(s_) for _, _, s_ in seq])):
            for idx in range(len(vals[0])):
                fc = act.fcurve_ensure_for_datablock(a, f'pose.bones["{n}"].{prop}', index=idx, group_name=n)
                fc.keyframe_points.clear(); fc.keyframe_points.add(len(vals))
                co = []
                for f, v in zip(keys, vals): co += [float(f), v[idx]]
                fc.keyframe_points.foreach_set('co', co)
                fc.keyframe_points.foreach_set('interpolation', [lin] * len(vals)); fc.update()
    ad.action = prev_action
    act.frame_range = (keys[0], keys[-1])
    return act

EVENTS = {
    'Stow': [(0.0, 'horn'), (T_UNDOCK, 'release'), (T['clamp'][1], 'clamp'), (T['lock'], 'lock')],
    'Deploy': [(0.0, 'horn'), (0.10, 'unlock'), (T['end'] - T['clamp'][0], 'unclamp'), (T['end'] - T_UNDOCK, 'dock'), (T['end'] - 0.04, 'lock')],
}
EVENT_KIND = {'horn': 'horn', 'release': 'latch', 'clamp': 'latch', 'lock': 'latch', 'unlock': 'latch', 'unclamp': 'latch', 'dock': 'latch'}

def stage_bake():
    a = rig(); sc = scene(); ad = a.animation_data
    for b in a.pose.bones: b.rotation_mode = 'QUATERNION' if b.name.startswith(('Gantry', 'Hook_', 'Spreader_', 'GJaw_', 'Rope_')) else b.rotation_mode
    out = {}
    for kind in ('Stow', 'Deploy'):
        frames, th = clip_poses(kind)
        act = write_action(kind, frames)
        for t, name in EVENTS[kind] + [(T['end'], 'end')]:
            mk = act.pose_markers.new(name); mk.frame = int(round(t * FPS))
        out[kind] = {'frames': len(frames), 'sway_max_deg': round(math.degrees(max(abs(x - (portal(clip_time(kind, q * SIM_DT))[0] if clip_time(kind, q * SIM_DT) < T_UNDOCK else 0.0)) for q, x in enumerate(th))), 2)}
    write_action('Gantry_Upright', upright_pose())
    for n in ('Stow', 'Deploy', 'Gantry_Upright'):
        for tr in [t for t in ad.nla_tracks if t.name == n]: ad.nla_tracks.remove(tr)
        tr = ad.nla_tracks.new(); tr.name = n; tr.strips.new(n, 0, bpy.data.actions[n]); tr.mute = True
    sc.frame_start, sc.frame_end = 0, int(round(T['end'] * FPS))
    ad.action = bpy.data.actions['Stow']
    REPORT['bake'] = out

def use_clip(kind):
    a = rig(); ad = a.animation_data
    for tr in ad.nla_tracks: tr.mute = True
    ad.action = bpy.data.actions[kind] if kind else None

# ---------------------------------------------------------------- export
class ExportState:
    """Baked clips drive the rig: drivers muted, quaternion bones, bones a clip does not key at rest."""
    def __init__(self, clip=None): self.clip = clip
    def __enter__(self):
        a = rig(); ad = a.animation_data
        self.drivers = [(fc, fc.mute) for fc in ad.drivers]
        for fc, _ in self.drivers: fc.mute = True
        self.modes = {pb.name: pb.rotation_mode for pb in a.pose.bones}
        for pb in a.pose.bones:
            q = pb.matrix_basis.to_quaternion(); pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = q
        self.action = ad.action
        self.nla = {t.name: t.mute for t in ad.nla_tracks}
        ad.action = bpy.data.actions[self.clip] if self.clip else None
        self.basis = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in a.pose.bones}
        for pb in a.pose.bones: pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        for t in ad.nla_tracks: t.mute = self.clip is not None
        bpy.context.view_layer.update()
        return self
    def __exit__(self, *exc):
        a = rig(); ad = a.animation_data
        for pb in a.pose.bones: pb.location, pb.rotation_quaternion, pb.scale = self.basis[pb.name]
        ad.action = self.action
        for t in ad.nla_tracks: t.mute = self.nla.get(t.name, True)
        for pb in a.pose.bones: pb.rotation_mode = self.modes[pb.name]
        for fc, v in self.drivers: fc.mute = v
        bpy.context.view_layer.update()

def stow_parts(): return [o for o in bpy.data.objects if o.get(TAG) and o.type == 'MESH' and o.parent_type == 'BONE']

def remove_skinned():
    for o in [o for o in bpy.data.objects if o.get('stow_export_tmp') or o.name.startswith('_skin_')]:
        me = o.data; bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)
    for o in stow_parts(): o['saw_src'] = True

def build_skinned():
    """Join every stow part (modifiers applied) into one mesh skinned rigidly to its bone."""
    remove_skinned()
    a = rig(); coll = bpy.data.collections[COLL]; parts = stow_parts(); copies = []
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
    sk.modifiers.new('Armature', 'ARMATURE').object = a
    sk['saw_src'] = True; sk['stow_export_tmp'] = True
    for o in parts: o['saw_src'] = False
    return sk

def stage_export():
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

# ---------------------------------------------------------------- analytic sampling (sidecar, audit)
def _evaluated_world(objs):
    """Rest-pose world vertices and polygons of each object (modifiers applied)."""
    import numpy as np
    out = []
    with RestPose():
        dg = bpy.context.evaluated_depsgraph_get()
        for o in objs:
            ev = o.evaluated_get(dg); me = ev.to_mesh()
            co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get('co', co)
            M = np.array(o.matrix_world); w = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
            out.append((o, w, [tuple(p.vertices) for p in me.polygons]))
            ev.to_mesh_clear()
    return out

def _bone_of(o):
    while o is not None and o.parent_type != 'BONE': o = o.parent
    return o.parent_bone if o is not None else 'Carriage'

class Group:
    """Rigid mesh pieces, each riding one bone; posed analytically from a {bone: pose} table."""
    def __init__(self, name, objs):
        self.name = name; self.pieces = [(_bone_of(o), w, pl) for o, w, pl in _evaluated_world(objs) if len(pl)]
        self.static = all(b == 'Carriage' for b, _, _ in self.pieces)
        self.bvh = None
    def pose(self, R, pose, bvh=True):
        import numpy as np
        from mathutils.bvhtree import BVHTree
        if self.static and self.bvh is not None: return self # never moves: built once
        verts, polys, base = [], [], 0
        for bone, w, pl in self.pieces:
            M = np.array(pose.get(bone, R[bone]) @ R[bone].inverted())
            p = w @ M[:3, :3].T + M[:3, 3]
            verts.append(p)
            if bvh: polys += [tuple(i + base for i in q) for q in pl]
            base += len(p)
        self.world = np.vstack(verts) if verts else np.zeros((0, 3))
        self.lo, self.hi = (self.world.min(0), self.world.max(0)) if len(self.world) else (None, None)
        self.bvh = BVHTree.FromPolygons([Vector(v) for v in self.world], polys) if bvh and polys else None
        return self

def _hit(a, b, pad=0.0):
    if a.bvh is None or b.bvh is None: return False
    if (a.lo > b.hi + pad).any() or (b.lo > a.hi + pad).any(): return False
    return bool(a.bvh.overlap(b.bvh))

def blade_objs(i):
    rot = bpy.data.objects[f'Rotor_{i + 1:02d} | rotate Z']
    return [o for o in [rot] + list(rot.children_recursive) if o.type == 'MESH']

def module_objs(i):
    sl = bpy.data.objects[f'Slider_{i + 1:02d} | slide X']
    return [o for o in [sl] + list(sl.children_recursive) if o.type == 'MESH']

def groups():
    parts = stow_parts()
    side = lambda o, n: _bone_of(o).endswith('_' + n) or f'_{n}_' in _bone_of(o)
    g = {'blade': {i: Group(f'blade{i + 1}', blade_objs(i)) for i in range(8)},
         'module': {i: Group(f'module{i + 1}', module_objs(i)) for i in range(8)},
         'clevis': {i: Group(f'clevis{i + 1}', [o for o in parts if _bone_of(o).endswith(f'_{i + 1:02d}')]) for i in range(8)}}
    for n in ('L', 'R'):
        g[f'portal{n}'] = Group(f'portal{n}', [o for o in parts if _bone_of(o).startswith('Gantry') and side(o, n)])
        g[f'hook{n}'] = Group(f'hook{n}', [o for o in parts if _bone_of(o).startswith(('Hook_', 'Spreader_', 'GJaw_')) and side(o, n)])
        g[f'rope{n}'] = Group(f'rope{n}', [o for o in parts if _bone_of(o).startswith('Rope_') and side(o, n)])
    skip = {o.name for i in range(8) for o in blade_objs(i) + module_objs(i)}
    g['carriage'] = Group('carriage', [o for o in bpy.data.collections[COLL].objects if o.type == 'MESH' and not o.get(TAG)
                                       and o.name not in skip and 'ICO' not in o.name and not o.name.startswith('_skin_')])
    g['mounts'] = Group('mounts', [o for o in parts if _bone_of(o) == 'Carriage'])
    g['conveyor'] = Group('conveyor', [o for o in bpy.data.collections['REF_Conveyor'].objects if 'EdgeLight' not in o.name] +
                          [bpy.data.objects['REF_Belt']])
    g['station'] = Group('station', [bpy.data.objects['REF_OperatorStation']])
    return g

def stage_sidecar():
    import numpy as np
    R = bone_rests(); L = T['end']; nf = int(round(L * FPS))
    G = groups()
    tall = [G[k] for k in ('portalL', 'portalR', 'hookL', 'hookR', 'ropeL', 'ropeR')] + list(G['clevis'].values())
    data = {'version': 3, 'fps': FPS, 'length': round(L, 4), 'brake_seconds': T['brake'], 'curve_rate': 30,
            'events': {}, 'wall_block': [], 'station_airspace': [], 'chair_column': []}
    for kind, key in (('Stow', 'stow'), ('Deploy', 'deploy')):
        data['events'][key] = [{'t': round(t, 4), 'kind': EVENT_KIND[n], 'name': n} for t, n in sorted(EVENTS[kind])]
    per_p = {}
    for kind in ('Stow', 'Deploy'):
        frames, _ = clip_poses(kind)
        prev = None
        for f in range(nf + 1):
            pose = frames[f]
            p = f if kind == 'Stow' else nf - f
            e = per_p.setdefault(p, {'block': False, 'reach': 0.0, 'station': False, 'chair': False, 'speed': 0.0})
            allp = np.vstack([g.pose(R, pose, bvh=False).world for g in tall] + [G['blade'][i].pose(R, pose, bvh=False).world for i in range(8)])
            bl = np.vstack([G['blade'][i].world for i in range(8)])
            over = allp[(np.abs(allp[:, 0]) < 11.9) & (allp[:, 2] > 0.62)]
            if len(over): e['block'] = True; e['reach'] = max(e['reach'], float(np.abs(over[:, 1]).max()))
            e['station'] |= bool(((np.abs(bl[:, 0]) > 12.01) & (np.abs(bl[:, 0]) < 13.85) & (np.abs(bl[:, 1]) < 0.85)).any())
            e['chair'] |= bool(((np.abs(allp[:, 0]) > 12.70) & (np.abs(allp[:, 0]) < 13.80) & (np.abs(allp[:, 1]) < 0.55) & (allp[:, 2] > 0.5)).any())
            track = [pose[f'Spin_{i + 1:02d}'].translation for i in range(8)] + \
                    [(pose[f'GantryS3_{n}'] @ R[f'GantryS3_{n}'].inverted() @ rest_frames()[f'GantryS3_{n}'] @ Vector((0, 0, L0))) for n in 'LR'] + \
                    [pose[f'Spreader_{n}'].translation for n in 'LR']
            if prev is not None:
                sp = max((b - a).length for a, b in zip(prev, track)) * FPS
                e['speed'] = max(e['speed'], sp)
                q = p - 1 if kind == 'Stow' else p + 1
                if q in per_p: per_p[q]['speed'] = max(per_p[q]['speed'], sp)
            prev = track
    def intervals(key):
        out, start = [], None
        for p in range(nf + 1):
            on = per_p.get(p, {}).get(key, False)
            if on and start is None: start = p
            if not on and start is not None: out.append((start, p - 1)); start = None
        if start is not None: out.append((start, nf))
        return out
    for s0, s1 in intervals('block'):
        reach = max(per_p[p]['reach'] for p in range(s0, s1 + 1))
        data['wall_block'].append({'from': round(max(0, s0 - 1) / FPS, 4), 'to': round(min(nf, s1 + 1) / FPS, 4), 'reach_y': round(reach + 0.05, 3)})
    for key, name in (('station', 'station_airspace'), ('chair', 'chair_column')):
        iv = intervals(key)
        data[name] = [round(max(0, iv[0][0] - 1) / FPS, 4), round(min(nf, iv[-1][1] + 1) / FPS, 4)] if iv else []
    n = int(L * 30) + 1
    spd = [per_p.get(min(nf, int(round(q / 30 * FPS))), {}).get('speed', 0.0) for q in range(n)]
    data['speed_env'] = [round(v, 3) for v in spd]
    data['hydraulic'] = [round(min(1.0, v / 3.0), 3) for v in spd]
    with open(JSON_PATH, 'w', encoding='utf-8') as fh: json.dump(data, fh, indent=1)
    REPORT['sidecar'] = {k: data[k] for k in ('length', 'wall_block', 'station_airspace', 'chair_column')} | {'speed_max': max(spd)}

def stage_audit():
    """BVH interference of both clips (every frame) and the folded/upright rest poses."""
    import numpy as np
    R = bone_rests(); G = groups(); L = T['end']; nf = int(round(L * FPS))
    rep = {}
    def check(tag, pose, fails, f):
        def fail(key, detail):
            fails.setdefault(key, {'count': 0, 'first': (f, detail)}); fails[key]['count'] += 1
        posed = {}
        def P(k, i=None):
            g = G[k] if i is None else G[k][i]
            key = (k, i)
            if key not in posed: posed[key] = g.pose(R, pose)
            return posed[key]
        rest_hub = {i: R[f'Spin_{i + 1:02d}'].translation for i in range(8)}
        for i in range(8):
            b = P('blade', i)
            # on (or lifting off) its own module: the spindle stub is still leaving its bearing housing
            seated = (pose.get(f'Spin_{i + 1:02d}', R[f'Spin_{i + 1:02d}']).translation - rest_hub[i]).length < 0.12
            for j in range(i + 1, 8):
                if _hit(b, P('blade', j)): fail('blade_vs_blade', f'{i + 1}/{j + 1}')
            for j in range(8):
                if (j != i or not seated) and _hit(b, P('module', j)): fail('blade_vs_module', f'{i + 1}/{j + 1}')
                if j != i and _hit(b, P('clevis', j)): fail('blade_vs_clevis', f'{i + 1}/{j + 1}')
            for k in ('carriage', 'conveyor', 'station', 'mounts', 'portalL', 'portalR', 'ropeL', 'ropeR'):
                if _hit(b, P(k)): fail(f'blade_vs_{k}', str(i + 1))
        for n in 'LR':
            for part_ in ('portal', 'hook', 'rope'):
                g = P(part_ + n)
                for k in ('station', 'conveyor', 'carriage'):
                    if _hit(g, P(k)): fail(f'{part_}_vs_{k}', n)
                for j in range(8):
                    if _hit(g, P('module', j)): fail(f'{part_}_vs_module', f'{n}{j + 1}')
            if _hit(P('hook' + n), P('portal' + n)): fail('hook_vs_portal', n)
    step, offset = globals().get('AUDIT_STEP', 1), globals().get('AUDIT_OFFSET', 0)
    for kind in globals().get('AUDIT_KINDS', ('Stow', 'Deploy')):
        frames, th = clip_poses(kind)
        fails = {}
        for f in range(offset, nf + 1, step): check(kind, frames[f], fails, f)
        # clearances over the operator station and the belt, per frame
        hub_over, rim_belt = 9.0, 9.0
        for f in range(nf + 1):
            pose = frames[f]
            for i in range(8):
                b = G['blade'][i].pose(R, pose, bvh=False).world
                over = b[(np.abs(b[:, 0]) > 12.01) & (np.abs(b[:, 0]) < 13.85) & (np.abs(b[:, 1]) < 0.85)]
                if len(over): hub_over = min(hub_over, float(over[:, 2].min()))
        rep[kind] = {'fails': fails, 'min_blade_z_over_station': round(hub_over, 3)}
    for tag, pose in (('folded', {}), ('upright', upright_pose()[0])):
        fails = {}; check(tag, pose, fails, 0); rep[tag] = {'fails': fails}
        env = np.vstack([G[k].pose(R, pose, bvh=False).world for k in ('portalL', 'portalR', 'hookL', 'hookR', 'ropeL', 'ropeR', 'mounts')])
        rep[tag]['envelope'] = {'abs_x': [round(float(np.abs(env[:, 0]).min()), 3), round(float(np.abs(env[:, 0]).max()), 3)],
                                'abs_y': [round(float(np.abs(env[:, 1]).min()), 3), round(float(np.abs(env[:, 1]).max()), 3)],
                                'z': [round(float(env[:, 2].min()), 3), round(float(env[:, 2].max()), 3)]}
    os.makedirs(OUT, exist_ok=True)
    with open(f'{OUT}/audit.json', 'w') as fh: json.dump(rep, fh, indent=1, default=str)
    REPORT['audit'] = rep

def stage_transport():
    """Folded gantries against the service vessel: upright while it raises and transfers the carriage, then
    swinging down beside the conveyor. Vessel triangles come from tests/saw_stow_dock_export.gd (carriage frame)."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    base = ROOT + '/artifacts/saw_stow/v3/dock/dock_tris'
    index = json.load(open(base + '.json'))
    raw = np.fromfile(base + '.bin', dtype='<f4').reshape(-1, 3, 3)
    R = bone_rests(); G = groups()
    ctrl = G['carriage'].pose(R, {})
    rows, at = [], 0
    for rec in index:
        pose = folded_pose(dock_lean(rec['time']))
        stow = [G[k].pose(R, pose) for k in ('portalL', 'portalR', 'hookL', 'hookR', 'ropeL', 'ropeR', 'mounts')]
        tris = raw[at:at + rec['triangles']]; at += rec['triangles']
        owner = []
        for name, n in rec['owners']: owner += [name] * n
        dock = BVHTree.FromPolygons([Vector(v) for v in tris.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
        hits = sum(len(g.bvh.overlap(dock)) for g in stow if g.bvh)
        ctrl_hits = len(ctrl.bvh.overlap(dock)) if ctrl.bvh else 0
        best = 9.0
        for g in stow:
            for p in g.world[::3]:
                loc, nrm, idx, dist = dock.find_nearest(Vector(p))
                if loc is not None and dist < best: best = dist
        rows.append({'time': rec['time'], 'lean_deg': round(math.degrees(dock_lean(rec['time'])), 1), 'intersections': hits,
                     'control_intersections': ctrl_hits, 'min_clearance': round(best, 4)})
    rep = {'samples': rows, 'intersecting': [r['time'] for r in rows if r['intersections']],
           'min_clearance': min(r['min_clearance'] for r in rows)}
    os.makedirs(OUT, exist_ok=True)
    with open(f'{OUT}/transport_clearance.json', 'w') as fh: json.dump(rep, fh, indent=1)
    REPORT['transport'] = {k: v for k, v in rep.items() if k != 'samples'}

def stage_review(tag='review', cams=('CAM_WallSpeedTab', 'CAM_MenuMain', 'CAM_Closeup'), times=None, res=(960, 540)):
    sc = scene(); out = f'{OUT}/{tag}'; os.makedirs(out, exist_ok=True)
    prev = (sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.frame_current, sc.render.filepath)
    kind = globals().get('REVIEW_CLIP', 'Stow')
    times = times or globals().get('REVIEW_TIMES') or [0.0, 0.9, 1.6, 2.4, 3.1, 3.7, 4.4, 5.1, 5.8, 6.85]
    files = []
    with ExportState(kind):
        for cam in cams:
            sc.camera = bpy.data.objects[cam]; sc.render.resolution_x, sc.render.resolution_y = res
            for t in times:
                f = int(round(t * FPS)); sc.frame_set(f)
                sc.render.filepath = f'{out}/{kind}_{cam}_{f:04d}.png'
                bpy.ops.render.render(write_still=True); files.append(sc.render.filepath)
    sc.camera, sc.render.resolution_x, sc.render.resolution_y = prev[0], prev[1], prev[2]
    sc.render.filepath = prev[4]; sc.frame_set(prev[3])
    REPORT['review'] = {'dir': out, 'count': len(files)}

def stage_tidy():
    sc = bpy.data.scenes.get('STOW3_Blockout')
    if sc: bpy.data.scenes.remove(sc)
    c = bpy.data.collections.get('STOW3_Proxy')
    if c:
        for o in list(c.all_objects):
            me = o.data if o.type == 'MESH' else None; bpy.data.objects.remove(o)
            if me and me.users == 0: bpy.data.meshes.remove(me)
        bpy.data.collections.remove(c)
    for o in [o for o in bpy.data.objects if o.name.startswith('S3_')]:
        me = o.data if o.type == 'MESH' else None; bpy.data.objects.remove(o)
        if me and me.users == 0: bpy.data.meshes.remove(me)
    for act in [x for x in bpy.data.actions if x.name.startswith('S3_')]: bpy.data.actions.remove(act)
    for m in [m for m in bpy.data.materials if m.name.startswith('S3_') and m.users == 0]: bpy.data.materials.remove(m)
    cam = bpy.data.objects.get('CAM_S3_Side')
    if cam: bpy.data.objects.remove(cam)
    REPORT['tidy'] = True

def checkpoint(label):
    d = f'{OUT}/checkpoints'; os.makedirs(d, exist_ok=True)
    p = f'{d}/{time.strftime("%Y%m%d_%H%M%S")}_{label}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=p, copy=True)
    REPORT['checkpoint'] = p

STAGES = {'cleanup': stage_cleanup, 'bones': stage_bones, 'parts': stage_parts, 'bake': stage_bake, 'export': stage_export,
          'sidecar': stage_sidecar, 'audit': stage_audit, 'transport': stage_transport, 'review': stage_review, 'tidy': stage_tidy}

if 'STAGE' in globals():
    for st in (globals().get('STAGE') or '').split(','):
        st = st.strip()
        if st: scene(); STAGES[st]()
    result = REPORT
