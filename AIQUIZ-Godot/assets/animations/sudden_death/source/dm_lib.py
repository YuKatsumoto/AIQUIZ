"""Shared helpers for the Sky Gate drop moves (W3, docs/sudden_death_v2/skygate_build_plan.md 4.4).

Run inside the live Blender (Higgsfield connector) only:

    ns = {}; exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/animations/sudden_death/source/dm_lib.py", encoding="utf-8").read(), ns)

Blender units are metres, Z up.  The rig is the Quaternius UAL mannequin (CC0, the same 65 bones and
rest as assets/animations/cc0_quaternius/UAL1_Standard.glb).  The character faces Blender -Y (Godot +Z),
its left is +X.  A pose is {bone: (Quaternion, Vector)} = pose-bone matrix_basis rotation / location.

"Upright frame" key poses are written as if the body stood upright; the body orientation (dives, flips,
the belly-down box) is a separate rotation applied about the pelvis head (rotate_body).
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

PROJECT = "C:/AIQUIZ/AIQUIZ-Godot"
SOURCE = PROJECT + "/assets/animations/sudden_death/source"
OUT = PROJECT + "/assets/animations/sudden_death"
SCENE = "SD_DropMoves"
RIG = "RIG_Drop"
FPS = 30

rig = bpy.data.objects[RIG]
REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
ORDER = []


def _walk(bone):
    ORDER.append(bone.name)
    for child in bone.children:
        _walk(child)


for _b in rig.data.bones:
    if _b.parent is None:
        _walk(_b)
REL = {}
for _n in ORDER:
    _p = PARENT[_n]
    REL[_n] = (REST[_p].inverted() @ REST[_n]) if _p else REST[_n].copy()
IDENTITY_Q = Quaternion((1, 0, 0, 0))
ZERO = Vector((0, 0, 0))
FINGERS = ["index", "middle", "ring", "pinky"]


def scene():
    return bpy.data.scenes[SCENE]


# ------------------------------------------------------------------ math

def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def smoother(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


def ease_out(x):
    x = min(max(x, 0.0), 1.0)
    return 1.0 - (1.0 - x) ** 2


def ease_in(x):
    x = min(max(x, 0.0), 1.0)
    return x * x


def rx(deg):
    return Quaternion((1, 0, 0), math.radians(deg))


def ry(deg):
    return Quaternion((0, 1, 0), math.radians(deg))


def rz(deg):
    return Quaternion((0, 0, 1), math.radians(deg))


def body_rot(pitch=0.0, long=0.0, yaw=0.0, roll=0.0):
    """Armature-space body orientation: yaw (world, about +Z) @ pitch (forward dive about +X: head -> -Y)
    @ roll (about the upright frame's forward axis) @ long (twist about the body's long axis, +Z upright)."""
    return rz(yaw) @ rx(pitch) @ Quaternion((0, -1, 0), math.radians(roll)) @ rz(long)


def v(side, out, fwd, up):
    """Upright-frame direction: out = away from the body centre on that side, fwd = forward (-Y), up = +Z."""
    s = 1.0 if side == "l" else -1.0
    return Vector((s * out, -fwd, up)).normalized()


def pchip(keys, t):
    """Monotone cubic through [(t, value), ...] (Fritsch-Carlson), flat outside the ends."""
    if not keys:
        return 0.0
    if t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    xs = [k[0] for k in keys]
    ys = [k[1] for k in keys]
    n = len(keys)
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0.0:
            m[i] = 0.0
        else:
            w1 = 2.0 * (xs[i + 1] - xs[i]) + (xs[i] - xs[i - 1])
            w2 = (xs[i + 1] - xs[i]) + 2.0 * (xs[i] - xs[i - 1])
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    for i in range(n - 1):
        if xs[i] <= t <= xs[i + 1]:
            h = xs[i + 1] - xs[i]
            s = (t - xs[i]) / h
            h00 = 2 * s ** 3 - 3 * s ** 2 + 1
            h10 = s ** 3 - 2 * s ** 2 + s
            h01 = -2 * s ** 3 + 3 * s ** 2
            h11 = s ** 3 - s ** 2
            return h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]
    return ys[-1]


# ------------------------------------------------------------------ poses

def rest_pose():
    return {n: (IDENTITY_Q.copy(), ZERO.copy()) for n in ORDER}


def copy_pose(p):
    return {n: (q.copy(), l.copy()) for n, (q, l) in p.items()}


def mix(a, b, w):
    w = min(max(w, 0.0), 1.0)
    if w <= 0.0:
        return copy_pose(a)
    if w >= 1.0:
        return copy_pose(b)
    out = {}
    for n in ORDER:
        qa, la = a[n]
        qb, lb = b[n]
        if qa.dot(qb) < 0.0:
            qb = -qb
        out[n] = (qa.slerp(qb, w), la.lerp(lb, w))
    return out


def add(base, delta_from, delta_to, w=1.0):
    """base + (delta_to - delta_from) * w, per bone in local space."""
    out = {}
    for n in ORDER:
        qb, lb = base[n]
        qf, lf = delta_from[n]
        qt, lt = delta_to[n]
        d = qf.inverted() @ qt
        if d.w < 0.0:
            d = -d
        d = IDENTITY_Q.slerp(d, w)
        out[n] = ((qb @ d).normalized(), lb + (lt - lf) * w)
    return out


def world(p):
    """{bone: armature-space Matrix} for a local pose."""
    w = {}
    for n in ORDER:
        par = PARENT[n]
        q, l = p[n]
        basis = Matrix.LocRotScale(l, q, Vector((1, 1, 1)))
        w[n] = (w[par] @ REL[n] @ basis) if par else (REL[n] @ basis)
    return w


def local(w):
    out = {}
    for n in ORDER:
        par = PARENT[n]
        pm = (w[par] @ REL[n]) if par else REL[n]
        loc, rot, _s = (pm.inverted() @ w[n]).decompose()
        out[n] = (rot.normalized(), loc)
    return out


def head(p, bone):
    return world(p)[bone].translation.copy()


def solve(spec, base=None):
    """Armature-space targets on top of a base pose (rest when None).  spec[bone] keys:
      "dir": direction of the bone's Y axis (swing from the inherited orientation)
      "aim": (y_dir, local_axis, world_target): Y along y_dir and local_axis turned toward world_target
      "rot": absolute armature Quaternion, "delta": armature Quaternion applied on top
      "local": bone-space Quaternion applied last (curls), "loc": armature head position
    """
    base = base or rest_pose()
    w = {}
    for n in ORDER:
        par = PARENT[n]
        q0, l0 = base[n]
        basis = Matrix.LocRotScale(l0, q0, Vector((1, 1, 1)))
        default = (w[par] @ REL[n] @ basis) if par else (REL[n] @ basis)
        s = spec.get(n)
        if not s:
            w[n] = default
            continue
        q = default.to_quaternion()
        if "rot" in s:
            q = s["rot"].copy()
        if "delta" in s:
            q = s["delta"] @ q
        if "dir" in s:
            y = q @ Vector((0, 1, 0))
            q = y.rotation_difference(Vector(s["dir"]).normalized()) @ q
        if "aim" in s:
            ydir, axis, target = s["aim"]
            q = aim_quat(Vector(ydir), Vector(axis), Vector(target))
        if "local" in s:
            q = q @ s["local"]
        loc = Vector(s["loc"]) if "loc" in s else default.translation
        w[n] = Matrix.LocRotScale(loc, q, Vector((1, 1, 1)))
    return local(w)


def aim_quat(ydir, local_axis, target):
    """Rotation whose +Y is ydir and whose local_axis points as close as possible to target
    (swing Y onto ydir, then twist about ydir)."""
    y = Vector(ydir).normalized()
    q1 = Vector((0, 1, 0)).rotation_difference(y)
    a = q1 @ Vector(local_axis)
    t = Vector(target)
    a_p = a - y * a.dot(y)
    t_p = t - y * t.dot(y)
    if a_p.length < 1e-5 or t_p.length < 1e-5:
        return q1
    angle = a_p.angle(t_p)
    if a_p.cross(t_p).dot(y) < 0.0:
        angle = -angle
    return (Quaternion(y, angle) @ q1).normalized()


def rest_axis(bone, world_dir):
    """Which bone-local axis points along world_dir in the rest pose."""
    return (REST[bone].to_quaternion().inverted() @ Vector(world_dir)).normalized()


PALM_L = rest_axis("hand_l", (0, 0, -1))
PALM_R = rest_axis("hand_r", (0, 0, -1))
SOLE_L = rest_axis("foot_l", (0, 0, -1))
SOLE_R = rest_axis("foot_r", (0, 0, -1))


def rotate_body(p, rot, pivot=None):
    """Turn the whole body by an armature-space rotation about the pelvis head (or a given pivot).
    Only the pelvis changes locally; returns (pose, pelvis head shift in armature space)."""
    w = world(p)
    ph = w["pelvis"].translation.copy()
    c = ph if pivot is None else Vector(pivot)
    m = Matrix.Translation(c) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-c)
    pw = m @ w["pelvis"]
    par = PARENT["pelvis"]
    pm = (w[par] @ REL["pelvis"]) if par else REL["pelvis"]
    loc, q, _s = (pm.inverted() @ pw).decompose()
    out = dict(p)
    out["pelvis"] = (q.normalized(), loc)
    return out, pw.translation - ph


def set_height(p, z):
    """Pelvis head height (armature Z) without changing its orientation."""
    w = world(p)
    w["pelvis"] = Matrix.LocRotScale(Vector((w["pelvis"].translation.x, w["pelvis"].translation.y, z)),
                                     w["pelvis"].to_quaternion(), Vector((1, 1, 1)))
    out = dict(p)
    out["pelvis"] = local({k: w[k] for k in ORDER})["pelvis"]
    return out


def contact_points(p, knees=False):
    """Lowest skin points that can touch the floor: toes, balls, heels (ankle minus its rest height), knees."""
    w = world(p)
    pts = []
    for s in ("l", "r"):
        pts.append(w["ball_leaf_" + s].translation - Vector((0, 0, 0.0152)))
        pts.append(w["ball_" + s].translation - Vector((0, 0, 0.0152)))
        pts.append(w["foot_" + s].translation - Vector((0, 0, 0.1037)))
        if knees:
            pts.append(w["calf_" + s].translation - Vector((0, 0, 0.06)))
    return pts


def ground(p, knees=False):
    """Move the pelvis up or down so the lowest contact point sits on z = 0."""
    low = min(pt.z for pt in contact_points(p, knees))
    w = world(p)
    par = PARENT["pelvis"]
    pm = (w[par] @ REL["pelvis"]) if par else REL["pelvis"]
    q, l = p["pelvis"]
    out = dict(p)
    out["pelvis"] = (q, l + pm.to_3x3().inverted() @ Vector((0, 0, -low)))
    return out


def zero_root(p):
    out = dict(p)
    out["root"] = (IDENTITY_Q.copy(), ZERO.copy())
    return out


# ------------------------------------------------------------------ UAL sources

_CB = {}


def _curves(action_name):
    if action_name in _CB:
        return _CB[action_name]
    act = bpy.data.actions[action_name]
    cb = act.layers[0].strips[0].channelbag(act.slots[0])
    table = {}
    for fc in cb.fcurves:
        path = fc.data_path
        if not path.startswith('pose.bones["'):
            continue
        bone = path.split('"')[1]
        prop = path.rsplit(".", 1)[-1]
        table[(bone, prop, fc.array_index)] = fc
    f0, f1 = act.frame_range
    _CB[action_name] = (table, f0, f1)
    return _CB[action_name]


def ual_length(name):
    _t, f0, f1 = _curves(name)
    return (f1 - f0) / FPS


def ual(name, t, loop=True, speed=1.0):
    """Sample a UAL action at time t seconds (speed scales playback)."""
    table, f0, f1 = _curves(name)
    span = f1 - f0
    f = t * FPS * speed
    if loop and span > 0:
        f = math.fmod(f, span)
        if f < 0:
            f += span
    else:
        f = min(max(f, 0.0), span)
    f += f0
    out = {}
    for n in ORDER:
        q = [table[(n, "rotation_quaternion", i)].evaluate(f) if (n, "rotation_quaternion", i) in table else (1.0 if i == 0 else 0.0) for i in range(4)]
        l = [table[(n, "location", i)].evaluate(f) if (n, "location", i) in table else 0.0 for i in range(3)]
        out[n] = (Quaternion(q).normalized(), Vector(l))
    return zero_root(out)


# ------------------------------------------------------------------ limb helpers (upright frame)

def arm(spec, side, upper, lower, palm=None, hand=None):
    spec["upperarm_" + side] = {"dir": upper}
    spec["lowerarm_" + side] = {"dir": lower}
    if palm is not None:
        axis = PALM_L if side == "l" else PALM_R
        spec["hand_" + side] = {"aim": (hand or lower, axis, palm)}
    elif hand is not None:
        spec["hand_" + side] = {"dir": hand}
    return spec


def leg(spec, side, thigh, calf, foot=None, sole=None):
    spec["thigh_" + side] = {"dir": thigh}
    spec["calf_" + side] = {"dir": calf}
    if foot is not None:
        axis = SOLE_L if side == "l" else SOLE_R
        spec["foot_" + side] = {"aim": (foot, axis, sole if sole is not None else Vector((0, 0, -1)))}
    return spec


def spine(spec, fwd=0.0, side=0.0, twist=0.0):
    """Bend the three spine bones forward (deg, + forward), sideways (+ toward the left) and twist (+ left)."""
    for n, k in (("spine_01", 0.3), ("spine_02", 0.35), ("spine_03", 0.35)):
        spec[n] = {"delta": rz(twist * k) @ ry(-side * k) @ rx(fwd * k)}
    return spec


def neck(spec, pitch=0.0, yaw=0.0, roll=0.0):
    """Head pitch + forward (look down), yaw + left, split over neck and head."""
    spec["neck_01"] = {"delta": rz(yaw * 0.4) @ rx(pitch * 0.4) @ ry(-roll * 0.4)}
    spec["Head"] = {"delta": rz(yaw * 0.6) @ rx(pitch * 0.6) @ ry(-roll * 0.6)}
    return spec


def fingers(spec, side, curl=20.0, thumb=10.0, spread=0.0):
    for f in FINGERS:
        for j in (1, 2, 3):
            spec.setdefault("%s_0%d_%s" % (f, j, side), {})["local"] = rx(curl * (1.0 if j == 1 else 1.15))
    for j in (1, 2, 3):
        spec.setdefault("thumb_0%d_%s" % (j, side), {})["local"] = rx(thumb)
    return spec


def fist(spec, side):
    return fingers(spec, side, curl=80.0, thumb=35.0)


def flat_hand(spec, side):
    return fingers(spec, side, curl=2.0, thumb=4.0)


# ------------------------------------------------------------------ baking

def new_action(name):
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = action
    return action


def bake(name, poses, loc_bones=("pelvis",)):
    """poses: list of local poses, one per frame from 0.  Linear keys on every frame."""
    action = new_action(name)
    curves = {}
    for n in ORDER:
        path = 'pose.bones["%s"].rotation_quaternion' % n
        curves[(n, "rot")] = [action.fcurve_ensure_for_datablock(rig, path, index=i, group_name=n) for i in range(4)]
        if n in loc_bones:
            path = 'pose.bones["%s"].location' % n
            curves[(n, "loc")] = [action.fcurve_ensure_for_datablock(rig, path, index=i, group_name=n) for i in range(3)]
    # one quaternion hemisphere per bone
    prev = {}
    fixed = []
    for p in poses:
        fp = {}
        for n in ORDER:
            q, l = p[n]
            if n in prev and prev[n].dot(q) < 0.0:
                q = -q
            prev[n] = q
            fp[n] = (q, l)
        fixed.append(fp)
    count = len(fixed)
    for (n, kind), fcs in curves.items():
        for i, fc in enumerate(fcs):
            fc.keyframe_points.clear()
            fc.keyframe_points.add(count)
            co = []
            for f, p in enumerate(fixed):
                q, l = p[n]
                co += [float(f), float(q[i] if kind == "rot" else l[i])]
            fc.keyframe_points.foreach_set("co", co)
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
            fc.update()
    rig.animation_data.action = None
    return action


def show(p):
    """Put a pose on the rig (no action) for screenshots."""
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = None
    for n in ORDER:
        pb = rig.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        q, l = p[n]
        pb.rotation_quaternion = q
        pb.location = l
    bpy.context.view_layer.update()
