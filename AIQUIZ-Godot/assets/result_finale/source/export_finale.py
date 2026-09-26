"""Export the Score Tower Finale for Godot. Leaves the active .blend path alone.

Outputs (res://assets/result_finale/):
  score_tower.glb     one tower (Collar + Lift/Platform/Column/Cannons, muzzle markers)
  crown.glb           crown with balls and gems, origin on the head
  rain_cloud.glb      cloud with face and PRP_CloudRain emitter marker
  referee_finale.glb  Godot plush rig + flag, animations "FinaleWin" and "FinaleDraw"
  finale_motion.json  sampled player joints, fists, tower curves, crown, cloud, cameras

Coordinates: Blender Z-up -> Godot Y-up. Joint/prop locals use Ci @ M @ C; cameras
use Ci @ M (both look down local -Z). Godot's stage node is rotated PI about Y.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Matrix

ROOT = Path("C:/AIQUIZ/AIQUIZ-Godot")
OUT = ROOT / "assets/result_finale"
SRC = str(ROOT / "assets/result_finale/source")
if SRC not in sys.path:
    sys.path.insert(0, SRC)
import importlib
import poses as P
importlib.reload(P)

SCENE = "AIQUIZ_ScoreTowerFinale"
C = Matrix.Rotation(math.pi / 2, 4, 'X')
CI = C.inverted()
JOINTS = P.BODY


def r(v, n=4):
    return round(float(v), n)


def local_track(m):
    loc, q, sc = (CI @ m @ C).decompose()
    return loc, q, sc


def quat_list(q):
    return [r(q.x), r(q.y), r(q.z), r(q.w)]


def fist_of(prefix):
    ob = bpy.data.objects[prefix]
    # the index proximal curl is -88 deg * fist
    angle = ob.matrix_basis.to_euler('XYZ').x
    return r(max(0.0, min(1.0, -math.degrees(angle) / 88.0)), 3)


def sample(ns):
    s = bpy.data.scenes[SCENE]
    anim = ns
    end = int(round(anim["END"] * 60))
    actors = {"WIN": {"actor": [], "fist": [], "joints": {j: [] for j in JOINTS}},
              "LOSE": {"actor": [], "fist": [], "joints": {j: [] for j in JOINTS}}}
    lifts = {"W": [], "L": []}
    crown, cloud, cams = [], [], {"win": [], "draw": []}
    prev = {}

    def cont(key, q):
        p = prev.get(key)
        if p is not None and p.dot(q) < 0.0:
            q = -q
        prev[key] = q.copy()
        return q

    for frame in range(end + 1):
        s.frame_set(frame)
        for side in ("WIN", "LOSE"):
            pre = side + "_"
            a = bpy.data.objects[pre + "Actor"]
            loc, q, _ = local_track(a.matrix_local)
            q = cont(pre + "Actor", q)
            actors[side]["actor"].append([r(loc.x), r(loc.y), r(loc.z)] + quat_list(q))
            actors[side]["fist"].append([fist_of(pre + "l_index_prox"), fist_of(pre + "r_index_prox")])
            for j in JOINTS:
                _, qj, _ = local_track(bpy.data.objects[pre + j].matrix_local)
                actors[side]["joints"][j].append(quat_list(cont(pre + j, qj)))
        lifts["W"].append(r(bpy.data.objects["TWR_W_Lift"].location.z))
        lifts["L"].append(r(bpy.data.objects["TWR_L_Lift"].location.z))
        for name, store in (("PRP_Crown", crown), ("PRP_Cloud", cloud)):
            ob = bpy.data.objects[name]
            loc, q, sc = local_track(ob.matrix_local)
            store.append([r(loc.x), r(loc.y), r(loc.z)] + quat_list(cont(name, q)) + [r(sc.x, 3)])
        for key, cam_name in (("win", "CAM_FinaleWin"), ("draw", "CAM_FinaleDraw")):
            cam = bpy.data.objects[cam_name]
            loc, q, _ = (CI @ cam.matrix_world).decompose()
            vfov = 2 * math.atan(cam.data.sensor_height / (2 * cam.data.lens))
            cams[key].append([r(loc.x), r(loc.y), r(loc.z)] + quat_list(cont(cam_name, q)) + [r(math.degrees(vfov), 3)])
    climb = [r(anim["climb_progress"](f / 60.0)) for f in range(end + 1)]
    stop = anim["POP"] + (anim["TOP"] - anim["POP"]) * anim["LOSE_PREVIEW_RATIO"]
    sink_start = int(round(anim["BEATS"]["sink_start"] * 60))
    sink = [0.0 if f < sink_start else r((stop - z) / (stop - anim["COLLAR"])) for f, z in enumerate(lifts["L"])]
    return {
        "version": 1,
        "source": "Blender %s scene %s (assets/result_finale/source/*.py)" % (bpy.app.version_string, SCENE),
        "fps": 60, "last_frame": end, "loop_start": anim["LOOP_START"],
        "beats": anim["BEATS"],
        "heights": {"collar": anim["COLLAR"], "pop": anim["POP"], "top": anim["TOP"]},
        "climb_window": [anim["CLIMB_START"], anim["CLIMB_END"]],
        "joints": JOINTS,
        "actors": actors,
        "win_lift": lifts["W"], "climb": climb, "lose_sink": sink,
        "crown": crown, "cloud": cloud, "cameras": cams,
    }


def export_prop(root_name, filename, prefix, rename=None, frame=0):
    """Export a prop hierarchy re-rooted at the origin via linked duplicates.

    Originals are renamed for the duration so the duplicates can carry clean node
    names into the GLB; names are restored afterwards.
    """
    s = bpy.data.scenes[SCENE]
    s.frame_set(frame)
    src_root = bpy.data.objects[root_name]
    # Only the prop's own parts: tower lifts also carry the actors in the scene.
    items = [src_root] + [c for c in src_root.children_recursive if c.name.startswith(prefix)]
    names = {ob: (rename(ob.name) if rename else ob.name) for ob in items}
    tmp_scene = bpy.data.scenes.new("EXPORT_TMP")
    made = {}
    try:
        for ob in items:
            ob.name = ob.name + "__orig"
        inv = src_root.matrix_world.inverted()
        for ob in items:
            dup = bpy.data.objects.new(names[ob], ob.data)
            tmp_scene.collection.objects.link(dup)
            made[ob] = dup
        for ob, dup in made.items():
            if ob is src_root:
                dup.matrix_basis = Matrix.Identity(4)
            elif ob.parent in made:
                dup.parent = made[ob.parent]
                dup.matrix_parent_inverse.identity()
                dup.matrix_basis = ob.parent.matrix_world.inverted() @ ob.matrix_world
            else:
                dup.matrix_basis = inv @ ob.matrix_world
        win = bpy.context.window
        prev_scene = win.scene
        win.scene = tmp_scene
        bpy.ops.object.select_all(action='DESELECT')
        for dup in made.values():
            dup.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(OUT / filename), export_format='GLB', use_selection=True,
                                  use_active_scene=True, export_animations=False, export_apply=False,
                                  export_lights=False, export_cameras=False, export_extras=True)
        win.scene = prev_scene
    finally:
        for dup in made.values():
            bpy.data.objects.remove(dup, do_unlink=True)
        bpy.data.scenes.remove(tmp_scene)
        for ob, name in names.items():
            ob.name = ob.name[:-len("__orig")] if ob.name.endswith("__orig") else ob.name
    return (OUT / filename).stat().st_size


def export_referee():
    s = bpy.data.scenes[SCENE]
    rig = bpy.data.objects["RIG_Referee"]
    plush = bpy.data.objects["HERO_GodotPlush"]
    flag_parts = [bpy.data.objects[n] for n in ("PRP_Flag", "PRP_FlagKnob", "PRP_FlagCloth")]
    win_action = bpy.data.actions["REF_FinaleWin"]
    draw_action = bpy.data.actions["REF_FinaleDraw"]
    rig.animation_data.action = win_action
    # NLA tracks make both actions exportable as named glTF animations.
    ad = rig.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for name, act in (("FinaleWin", win_action), ("FinaleDraw", draw_action)):
        tr = ad.nla_tracks.new()
        tr.name = name
        strip = tr.strips.new(name, 0, act)
        strip.name = name
    ad.action = None
    s.frame_set(0)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [rig, plush] + flag_parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(OUT / "referee_finale.glb"), export_format='GLB', use_selection=True,
                              use_active_scene=True, export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_frame_range=False, export_bake_animation=True, export_skins=True,
                              export_morph=False, export_lights=False, export_cameras=False,
                              export_optimize_animation_size=True, export_force_sampling=True)
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = win_action
    return (OUT / "referee_finale.glb").stat().st_size


def export_all():
    s = bpy.data.scenes[SCENE]
    bpy.context.window.scene = s
    ns = {}
    exec(open(SRC + "/animate_finale.py", encoding="utf-8").read(), ns)
    frame = s.frame_current
    sizes = {}
    s.frame_set(0)
    sizes["score_tower.glb"] = export_prop("TWR_W_Root", "score_tower.glb", "TWR_W_",
                                           rename=lambda n: n.replace("TWR_W_", "Tower"))
    # crown / cloud while visible (scale 1) so the child offsets are well defined
    sizes["crown.glb"] = export_prop("PRP_Crown", "crown.glb", "PRP_Crown", frame=int(8.2 * 60))
    sizes["rain_cloud.glb"] = export_prop("PRP_Cloud", "rain_cloud.glb", "PRP_Cloud", frame=int(8.2 * 60))
    sizes["referee_finale.glb"] = export_referee()
    data = sample(ns)
    path = OUT / "finale_motion.json"
    path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    sizes["finale_motion.json"] = path.stat().st_size
    s.frame_set(frame)
    return sizes
