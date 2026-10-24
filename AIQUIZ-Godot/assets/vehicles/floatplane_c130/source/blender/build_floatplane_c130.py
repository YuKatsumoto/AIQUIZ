"""サドンデスの水上機 C-130（floatplane_c130.glb）を作る。

ユーザーが開いているライブの Blender で動かす（Higgsfield の Blender 連携 bl_execute から runpy）。ヘッドレスでは動かさない。
  import runpy, sys
  sys.argv = ["blender", "--"]            # 省略可。"--no-save" "--no-export" を足せる
  runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/vehicles/floatplane_c130/source/blender/build_floatplane_c130.py", run_name="__main__")

寸法は source/c130_design.py（artifacts/sudden_death_v2/c130_float/c130_design.py の写し）。形は fp_shell.py（胴体）・
fp_parts.py（翼・エンジン・尾翼・フロート）・fp_interior.py（機内・操縦席）。約束は docs/sudden_death_v2/skygate_build_plan.md 4.2。
出力：
  assets/vehicles/floatplane_c130/floatplane_c130.glb          ゲームで使う機体（スロープ・上のふたは閉じた形）
  assets/vehicles/floatplane_c130/floatplane_c130_layout.json  マーカー・動く部品の軸・寸法の実測
  source/build_report.json                                     三角形の数・部品・チェック
  source/blender/floatplane_c130.blend                         （AGENTS.md：作業したら保存する）
"""
from __future__ import annotations

import importlib
import json
import math
import sys
import time
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
for _name in [n for n in sys.modules if n.startswith("fp_")]:
    del sys.modules[_name]          # ライブの Blender に残った前の版を捨てて読み直す

import fp_common  # noqa: E402
import fp_section  # noqa: E402
import fp_shell  # noqa: E402
import fp_parts  # noqa: E402
import fp_interior  # noqa: E402
import fp_detail  # noqa: E402
import fp_cockpit  # noqa: E402
import fp_bake  # noqa: E402

for _m in (fp_common, fp_section, fp_shell, fp_parts, fp_interior, fp_detail, fp_cockpit, fp_bake):
    importlib.reload(_m)
K = fp_common
S = fp_section
from fp_common import GMesh, P, W, collection, create_object, empty, make_materials, set_pivot  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_SAVE = "--no-save" not in ARGS
DO_EXPORT = "--no-export" not in ARGS
DO_BAKE = "--no-bake" not in ARGS
EXPORT_COLL = "FP_EXPORT"
WORK_COLL = "FP_WORK"
ROOT_NAME = "FloatplaneC130"
C = S.C
WARNINGS: list = []
REVERSE_PITCH_DELTA = -42.0      # 逆推力：羽根を放射の軸まわりにこれだけ回す（22° → −20°）


# ---------------------------------------------------------------- シーン

def setup_scene():
    sc = bpy.context.scene
    if sc.name != K.SCENE_NAME:
        sc.name = K.SCENE_NAME
    sc.unit_settings.system = "METRIC"
    for name in (EXPORT_COLL, WORK_COLL):
        coll = bpy.data.collections.get(name)
        if coll is None:
            continue
        for obj in list(coll.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and getattr(data, "users", 1) == 0 and isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
    for obj in [o for o in sc.collection.objects if o.type == "MESH"]:
        bpy.data.objects.remove(obj, do_unlink=True)
    for me in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(me)
    return sc


def check_design_copy():
    """写し（source/c130_design.py）と元（artifacts/…）の数字の部分（「実機」の行から最後まで）が同じか。元がなければ確かめない。"""
    if not K.DESIGN_ORIGINAL.exists():
        return None
    mark = "# ---------------------------------------------------------------- 実機"
    a = K.DESIGN_PATH.read_text(encoding="utf-8")
    b = K.DESIGN_ORIGINAL.read_text(encoding="utf-8")
    if mark not in a or mark not in b:
        return ["区切りの行が見つからない"]
    ta, tb = a[a.index(mark):].splitlines(), b[b.index(mark):].splitlines()
    return [f"{i + 1}: {x!r} ≠ {y!r}" for i, (x, y) in enumerate(zip(ta, tb)) if x != y] + (["行の数が違う"] if len(ta) != len(tb) else [])


# ---------------------------------------------------------------- ブーリアン

def apply_boolean(target, cutter, op, use_self=False):
    mod = target.modifiers.new("fp_bool", "BOOLEAN")
    mod.operation = op
    mod.solver = "EXACT"
    mod.object = cutter
    mod.use_self = use_self
    mod.use_hole_tolerant = True
    mod.material_mode = "TRANSFER"
    dg = bpy.context.evaluated_depsgraph_get()
    ev = target.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    target.modifiers.remove(mod)
    old = target.data
    target.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return len(me.polygons)


def set_all_materials(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0


def drop_unused_slots(obj):
    me = obj.data
    used = {p.material_index for p in me.polygons}
    keep = [i for i in range(len(me.materials)) if i in used]
    if len(keep) == len(me.materials):
        return
    remap = {old: new for new, old in enumerate(keep)}
    mats = [me.materials[i] for i in keep]
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", idx)


def merge_slots_by_name(obj):
    """同じ材質が 2 つの枠に入ったら 1 つにする（ブーリアンの TRANSFER で増える）。"""
    me = obj.data
    names = [m.name if m else "" for m in me.materials]
    first = {}
    remap = {}
    for i, n in enumerate(names):
        if n in first:
            remap[i] = first[n]
        else:
            first[n] = i
            remap[i] = i
    if all(remap[i] == i for i in remap):
        return
    idx = [remap[p.material_index] for p in me.polygons]
    me.polygons.foreach_set("material_index", idx)
    drop_unused_slots(obj)


def join(objs, into):
    with bpy.context.temp_override(active_object=into, selected_editable_objects=[into] + objs, object=into):
        bpy.ops.object.join()
    merge_slots_by_name(into)
    return into


def mesh_stats(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    bm.free()
    return {"non_manifold_edges": non_manifold, "boundary_edges": boundary}


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# ---------------------------------------------------------------- 組み立て

def build(mats):
    exp = collection(EXPORT_COLL)
    work = collection(WORK_COLL)
    root = empty(ROOT_NAME, exp, (0, 0, 0), display="ARROWS", size=2.0)
    info = {"pivots": {}, "stats": {}}

    # 胴体（閉じた立体）→ 窓をくり抜く
    shell_g, shell_stats = fp_shell.build_shell()
    shell = create_object("Body", shell_g, mats, exp, parent=root)
    info["stats"]["shell_before_windows"] = dict(shell_stats, **mesh_stats(shell))
    info["shell_dims"] = measure_shell(shell_g)
    cut_cockpit = create_object("CUT_Cockpit", fp_shell.window_cutters(), mats, work)
    port_g = fp_shell.porthole_cutters()
    port_g.extend(fp_detail.door_window_cutter())
    cut_port = create_object("CUT_Portholes", port_g, mats, work)
    for c in (cut_cockpit, cut_port):
        c.hide_render = True
        c.display_type = "WIRE"
    apply_boolean(shell, cut_cockpit, "DIFFERENCE")
    apply_boolean(shell, cut_port, "DIFFERENCE")
    merge_slots_by_name(shell)
    info["stats"]["shell_after_windows"] = mesh_stats(shell)

    # 操縦席のガラス（窓の輪郭を外板の少し内側へ写した板。窓枠は fp_detail.build_cockpit_frames で胴体に入れる）
    glass = create_object("Glass", fp_detail.build_cockpit_glass(), mats, exp, parent=root)
    cut_frame = None

    # 丸窓のガラスと縁
    pg = GMesh()
    pg.extend(fp_detail.door_window_glass())
    bez = GMesh()
    for side in (-1, 1):
        for u in fp_shell.PORTHOLE_U:
            s = S.section(u)
            xo = S.x_at_v(s, C.WINDOW_V)
            xi = S.x_at_v(S.inner_section(u), C.WINDOW_V)
            c_o = W(u, C.WINDOW_V, side * (xo - 0.05))
            pg.lathe(tuple(c_o), (side, 0, 0), [(0.0, C.WINDOW_R + 0.012), (0.004, C.WINDOW_R + 0.012)], "FP_Glass", n=20, cap0="flat", cap1="flat")
            c_out = W(u, C.WINDOW_V, side * (xo - 0.03))
            bez.lathe(tuple(c_out), (side, 0, 0), [(0.0, C.WINDOW_R), (0.035, C.WINDOW_R + 0.012), (0.05, C.WINDOW_R + 0.06), (0.04, C.WINDOW_R + 0.085),
                                                    (0.025, C.WINDOW_R + 0.09)], "FP_Navy", n=24, smooth=True, crease_deg=80)
            c_in = W(u, C.WINDOW_V, side * (xi + 0.02))
            bez.lathe(tuple(c_in), (-side, 0, 0), [(0.0, C.WINDOW_R), (0.03, C.WINDOW_R + 0.01), (0.04, C.WINDOW_R + 0.07), (0.02, C.WINDOW_R + 0.09)],
                      "FP_InteriorFrame", n=24, smooth=True, crease_deg=80)
    port_glass = create_object("PortGlass", pg, mats, work)
    bezels = create_object("Bezels", bez, mats, work)
    join([port_glass], glass)
    set_all_materials(glass, mats["FP_Glass"])

    # ほかの外の部品（主翼・覆い・エンジン・尾翼・灯の台）を胴体にまとめる
    parts = GMesh()
    fp_parts.build_wing(parts)
    fp_parts.build_wing_fairing(parts)
    for x in fp_parts.engine_order():
        fp_parts.build_nacelle(parts, x)
    fp_parts.build_fin(parts)
    fp_parts.build_stab(parts)
    lamps = fp_parts.nav_light_positions()
    fp_parts.build_beacon_base(parts, lamps["Beacon"])
    fp_detail.build_all(parts)
    parts_obj = create_object("BodyParts", parts, mats, work)
    join([parts_obj, bezels], shell)
    shell.data.set_sharp_from_angle(angle=math.radians(42.0))
    info["stats"]["body"] = mesh_stats(shell)

    floats = GMesh()
    fp_parts.build_floats(floats)
    fp_parts.build_struts(floats)
    fp_detail.build_float_extras(floats)
    floats_obj = create_object("Floats", floats, mats, exp, parent=root, sharp_deg=42.0)

    hold = fp_interior.build_hold()
    interior = create_object("Interior", hold, mats, exp, parent=root, sharp_deg=42.0)
    cockpit = create_object("Cockpit", fp_cockpit.build_cockpit(), mats, exp, parent=root, sharp_deg=42.0)
    info["cabin_lights"] = [dict(l_) for l_ in fp_interior.LIGHTS]

    # スロープ（原点は付け根。閉じた形で書き出す）
    ramp_g, ramp_pivot = fp_shell.build_ramp()
    ramp_g.extend(fp_interior.build_ramp_details(fp_shell.ramp_point))
    ramp = create_object("Ramp", ramp_g, mats, exp, parent=root, sharp_deg=42.0)
    set_pivot(ramp, P(ramp_pivot))
    info["pivots"]["Ramp"] = ramp_pivot

    # スロープの作動筒（左右。筒は胴体の側 A、棒はスロープの側 B。どちらもローカル −Z が相手の向き）
    actuators = {}
    for side, tag in ((-1, "L"), (1, "R")):
        a_pt = fp_interior.ramp_actuator_anchor(side)
        b_pt = fp_interior.ramp_actuator_ramp_point(side, fp_shell.ramp_point)
        for name, g_, origin, target in ((f"RampCyl_{tag}", fp_interior.build_actuator_cyl(), a_pt, b_pt),
                                         (f"RampRod_{tag}", fp_interior.build_actuator_rod(), b_pt, a_pt)):
            ob = create_object(name, g_, mats, exp, parent=root)
            d_b = (P(target) - P(origin)).normalized()
            ob.rotation_mode = "QUATERNION"
            ob.rotation_quaternion = d_b.to_track_quat("Y", "Z")      # ローカル +Y（Blender）＝ Godot の −Z を相手へ
            ob.location = P(origin)
        actuators[tag] = {"cylinder": f"RampCyl_{tag}", "rod": f"RampRod_{tag}", "anchor": a_pt, "ramp_point_closed": b_pt}
    info["actuators"] = actuators

    door_g, door_pivot = fp_shell.build_door()
    door = create_object("UpperDoor", door_g, mats, exp, parent=root, sharp_deg=42.0)
    set_pivot(door, P(door_pivot))
    info["pivots"]["UpperDoor"] = door_pivot

    # フラップ
    flaps = []
    for side, tag in ((-1, "L"), (1, "R")):
        for i, span in enumerate(fp_parts.FLAP_SPANS):
            name = f"Flap_{tag}{i + 1}"
            ob = create_object(name, fp_parts.build_flap(side, span), mats, exp, parent=root)
            hinge = fp_parts.flap_hinge(side, span)
            set_pivot(ob, P(hinge))
            info["pivots"][name] = hinge
            flaps.append(name)
    info["flaps"] = flaps

    # プロペラ（スピナー＝回る軸、子に羽根 4 枚）
    props = []
    for n, x in enumerate(fp_parts.engine_order(), start=1):
        sp_g, hub = fp_parts.build_spinner(x)
        sp = create_object(f"Prop_{n}", sp_g, mats, exp, parent=root)
        set_pivot(sp, P(hub))
        blades = []
        for b in range(fp_parts.BLADE_COUNT):
            ang = 45.0 + 90.0 * b
            bg, radial = fp_parts.build_blade(hub, ang)
            bo = create_object(f"Blade_{n}_{b + 1}", bg, mats, exp)
            set_pivot(bo, P(hub))
            bo.parent = sp
            bo.matrix_parent_inverse = sp.matrix_basis.inverted()     # 親（スピナー）の原点も軸の中心
            blades.append({"node": bo.name, "radial": [round(radial.x, 5), round(radial.y, 5), round(radial.z, 5)]})
        props.append({"node": sp.name, "hub": list(hub), "blades": blades})
    info["props"] = props

    # 灯（面 1 つ。Godot が光らせ方を決める）
    lights = {}
    for name, mat in (("NavLight_L", "FP_LightRed"), ("NavLight_R", "FP_LightGreen"), ("Beacon", "FP_LightRed"), ("TailLight", "FP_LightWhite")):
        pos = lamps[name]
        g = fp_parts.build_lamp(pos, r=0.07 if name.startswith("Nav") else 0.09, mat=mat)
        ob = create_object(name, g, mats, exp, parent=root)
        set_pivot(ob, P(pos))
        lights[name] = pos
    for name, pos in fp_interior.jump_light_positions().items():
        ob = create_object(name, fp_interior.build_jump_lamp(pos, "FP_LightRed" if name.endswith("Red") else "FP_LightGreen"), mats, exp, parent=root)
        set_pivot(ob, P(pos))
        lights[name] = pos
    info["lights"] = lights

    # ベルト（P1 は機体の右の壁 +x、P2 は左 −x）
    for player, side in ((1, 1), (2, -1)):
        create_object(f"Belt_P{player}", fp_interior.build_belt(side), mats, exp, parent=root)

    objs = {o.name: o for o in exp.all_objects if o.type == "MESH"}
    for c in (cut_cockpit, cut_port):
        bpy.data.objects.remove(c, do_unlink=True)
    for obj in objs.values():
        drop_unused_slots(obj)
    return root, objs, info


# ---------------------------------------------------------------- マーカー（計画書 4.2）

def _yaw_basis(yaw_deg):
    return Matrix.Rotation(math.radians(yaw_deg), 3, Vector((0, 1, 0)))


def _look_basis(eye: Vector, target: Vector):
    """カメラの向き（−Z が見る向き、+Y がだいたい上）。Godot の座標。"""
    fwd = (target - eye).normalized()
    z = -fwd
    x = Vector((0, 1, 0)).cross(z).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def marker_table():
    sit_z = C.SIT_U - S.U0
    pel_x = C.BENCH_INNER_X + 0.24
    pel_y = C.BENCH_SEAT_V + 0.18
    stand_x = C.BENCH_INNER_X - 0.37
    pilot_root = W(fp_interior.PILOT_ROOT_U, fp_interior.PILOT_ROOT_V, 0.0)
    cam_aft_eye = W(C.STEPS_U[0] - 0.10, C.FLIGHT_DECK_V + 1.60, 0.0)
    cam_fwd_eye = W(S.HINGE_U - 0.25, C.FLOOR_V + 1.70, 0.0)
    m = {
        "MK_SeatP1": (Vector((pel_x, pel_y, sit_z)), _yaw_basis(-90.0), "P1 の座った pelvis（機体の右の壁のベンチ。ももの下面＝座面）。+Z が向き＝通路の向かい（−X）"),
        "MK_SeatP2": (Vector((-pel_x, pel_y, sit_z)), _yaw_basis(90.0), "P2 の座った pelvis（左の壁のベンチ）。+Z が向き＝通路の向かい（+X）"),
        "MK_StandP1": (Vector((stand_x, C.FLOOR_V, sit_z)), _yaw_basis(-90.0), "P1 がベルトを外して立つ足もと（床の上）"),
        "MK_StandP2": (Vector((-stand_x, C.FLOOR_V, sit_z)), _yaw_basis(90.0), "P2 がベルトを外して立つ足もと（床の上）"),
        "MK_RampHinge": (W(S.HINGE_U, C.FLOOR_V, 0.0), _yaw_basis(0.0), "スロープの付け根（床の上面）。+Z が外（後ろ）"),
        "MK_RampEdge": (W(S.RAMP_OPEN_END_U, C.FLOOR_V, 0.0), _yaw_basis(0.0), "開いたスロープの端の上面＝飛び出す位置（set_ramp(1) のとき）。+Z が外"),
        "MK_DeckDoor": (W(C.STEPS_U[0], C.FLIGHT_DECK_V, 0.0), _yaw_basis(0.0), "操縦席の出入り口（段の上、操縦席の床）。+Z が貨物室"),
        "MK_PilotSeat": (pilot_root, _yaw_basis(180.0), "ハテナ（HatenaPilot）の原点（足元の基準・等倍）。体の下端がクッションの上。+Z が向き＝機首"),
        "MK_CamAft": (cam_aft_eye, _look_basis(cam_aft_eye, W(S.HINGE_U, C.FLOOR_V + 1.0, 0.0)), "機内のカメラ（段の上から後ろを見る。P1 が左）。カメラの −Z が見る向き"),
        "MK_CamFwd": (cam_fwd_eye, _look_basis(cam_fwd_eye, W(C.STEPS_U[0], C.FLIGHT_DECK_V + 0.9, 0.0)), "機内のカメラ（スロープの付け根から前を見る）。カメラの −Z が見る向き"),
        "MK_TailEnd": (W(C.FIN[3][0], C.FIN[3][1], 0.0), _yaw_basis(0.0), "尾の一番後ろ（垂直尾翼の後ろの縁の根元）。水路で床の壁から 0.5 m に合わせる"),
        "MK_JumpLight": (W(fp_interior.PORTAL_U[0] - 0.07, C.JUMP_LIGHT_V, 0.0), _yaw_basis(180.0), "降下のランプ（後ろの開口の上。赤＝+X 側、緑＝−X 側）"),
        "MK_CockpitLight": (W(2.1, S.inner_section(2.1)["top"] - 0.25, 0.0), None, "操縦席の明かり"),
        "MK_CabinLight1": (W(4.9, 5.25, 0.0), None, "貨物室の明かり（前）"),
        "MK_CabinLight2": (W(7.3, 5.25, 0.0), None, "貨物室の明かり（真ん中）"),
        "MK_CabinLight3": (W(9.7, 5.25, 0.0), None, "貨物室の明かり（後ろ）"),
    }
    for side, tag in ((-1, "L"), (1, "R")):
        xf = side * C.FLOAT["x"]
        m[f"MK_SprayBow_{tag}"] = (W(C.FLOAT["u0"] + 0.9, 0.0, xf), None, f"フロートのしぶき（船首、{tag}）")
        m[f"MK_SprayStep_{tag}"] = (W(8.7, 0.0, xf), None, f"フロートのしぶき（船底の段、{tag}）")
        m[f"MK_SprayStern_{tag}"] = (W(C.FLOAT["u1"] - 0.4, 0.0, xf), None, f"フロートのしぶき（船尾、{tag}）")
    return m


def build_markers(root):
    coll = collection(EXPORT_COLL)
    out = {}
    for name, (pos, basis, note) in marker_table().items():
        ob = empty(name, coll, P(pos), parent=root, display="ARROWS" if basis is not None else "PLAIN_AXES", size=0.25)
        if basis is not None:
            ob.rotation_mode = "QUATERNION"
            ob.rotation_quaternion = K.basis_g2b(basis).to_quaternion()
        out[name] = (pos, basis, note)
    return out


# ---------------------------------------------------------------- 寸法の実測

def measure_shell(g: GMesh):
    xs = [v.x for v in g.vg]
    ys = [v.y for v in g.vg]
    zs = [v.z for v in g.vg]
    return {"length": round(max(zs) - min(zs), 4), "width": round(max(xs) - min(xs), 4), "height": round(max(ys) - min(ys), 4),
            "nose_z": round(min(zs), 4), "tail_z": round(max(zs), 4)}


def world_verts(obj):
    mw = obj.matrix_world
    return [K.G(mw @ v.co) for v in obj.data.vertices]


def world_verts_by_material(obj, names):
    me = obj.data
    idx = {i for i, m in enumerate(me.materials) if m and m.name in names}
    vs = set()
    for p in me.polygons:
        if p.material_index in idx:
            vs.update(p.vertices)
    mw = obj.matrix_world
    return [K.G(mw @ me.vertices[i].co) for i in vs]


def measure(objs, info):
    body = objs["Body"]
    allv = []
    for name in ("Body", "Floats", "Ramp", "UpperDoor"):
        allv += world_verts(objs[name])
    for n in range(1, 5):
        allv += world_verts(objs[f"Prop_{n}"])
    wing = [v for v in world_verts_by_material(body, {"FP_Paint", "FP_Navy"}) if v.y > 5.6 and abs(v.x) > 2.5]
    lining = [v for v in world_verts_by_material(body, {"FP_InteriorWall"}) if S.C.HOLD[0] - S.U0 + 0.3 < v.z < S.HINGE_U - S.U0 - 0.3]
    fl = [v for v in world_verts_by_material(objs["Floats"], {"FP_Paint", "FP_Navy"}) if v.x > 2.6 and v.y < 1.06]   # 右のフロート（支柱と金具を除く）
    blade_r = []
    for p in info["props"]:
        hub = Vector(p["hub"])
        for b in p["blades"]:
            for v in world_verts(objs[b["node"]]):
                blade_r.append((v - hub).length)
    ramp_top = [v for v in world_verts_by_material(objs["Ramp"], {"FP_InteriorFloor"})]
    rz = [v.z for v in ramp_top]
    rx = [v.x for v in ramp_top]
    floor_y = C.FLOOR_V
    d = {
        "length_overall": round(max(v.z for v in allv) - min(v.z for v in allv), 4),
        "span": round(max(v.x for v in wing) - min(v.x for v in wing), 4),
        "height_overall": round(max(v.y for v in allv) - min(v.y for v in allv), 4),
        "fuselage_width": info["shell_dims"]["width"],
        "fuselage_height": info["shell_dims"]["height"],
        "hold_length": round(S.HINGE_U - C.HOLD[0], 4),
        "hold_inner_width": round(max(v.x for v in lining) - min(v.x for v in lining), 4),
        "hold_standing_height": round(max(v.y for v in lining) - floor_y, 4),
        "opening_width": round(2 * C.RAMP_HALF_W, 4),
        "opening_height": round(fp_interior.OPENING_TOP_V - floor_y, 4),
        "ramp_length": round(math.hypot(max(rz) - min(rz), 0) / math.cos(math.radians(S.RAMP_CLOSED_DEG)), 4),
        "ramp_width": round(max(rx) - min(rx), 4),
        "prop_diameter": round(2 * max(blade_r), 4),
        "float_length": round(max(v.z for v in fl) - min(v.z for v in fl), 4),
        "float_diameter": round(max(v.y for v in fl) - min(v.y for v in fl), 4),
        "float_draft": round(-min(v.y for v in fl), 4),
        "float_spacing": round(2 * C.FLOAT["x"], 4),
        "floor_height": floor_y,
        "flight_deck_height": C.FLIGHT_DECK_V,
    }
    return d


# ---------------------------------------------------------------- 書き出し

def export_glb(root):
    bpy.ops.object.select_all(action="DESELECT")
    targets = [root] + list(root.children_recursive)
    for obj in targets:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    K.GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(K.GLB), export_format="GLB", use_selection=True, use_active_scene=True,
                              export_apply=True, export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False, export_vertex_color="ACTIVE",
                              export_image_format="AUTO", export_materials="EXPORT")
    return K.GLB.stat().st_size


def r4(v):
    return [round(float(c), 4) for c in v]


def write_layout(objs, info, markers, dims):
    mk = {}
    for name, (pos, basis, note) in markers.items():
        row = {"position": r4(pos), "note": note}
        if basis is not None:
            row["basis"] = [r4(basis.col[0]), r4(basis.col[1]), r4(basis.col[2])]   # 列＝x, y, z の軸（Godot の Basis と同じ並び）
        mk[name] = row
    ramp_p = info["pivots"]["Ramp"]
    door_p = info["pivots"]["UpperDoor"]
    layout = {
        "version": 1,
        "units": "m",
        "origin": "海面（浮いているときの水面）× 機体の中心線 × 主翼の翼弦の中央（機首から 6.6 m）。+Y が上、機首が −Z。z = u − 6.6、y = v",
        "design_source": "source/c130_design.py（artifacts/sudden_death_v2/c130_float/c130_design.py の写し）",
        "plan": "docs/sudden_death_v2/skygate_build_plan.md 4.2",
        "markers": mk,
        "marker_convention": "basis の +Z が人の向き（StagingPuppet の yaw と同じ約束）。MK_Cam* だけはカメラの向き（−Z が見る向き）",
        "ramp": {"node": "Ramp", "pivot": r4(ramp_p), "axis": [1, 0, 0], "open_deg": S.RAMP_CLOSED_DEG, "length": C.RAMP_LEN,
                 "half_width": C.RAMP_HALF_W, "note": "GLB は閉じた形（上へ 25°）。開く：ramp.basis = Basis(Vector3.RIGHT, deg_to_rad(open_deg * t))。t=1 で床と水平"},
        "upper_door": {"node": "UpperDoor", "pivot": r4(door_p), "axis": [1, 0, 0], "open_deg": round(fp_shell.door_open_deg(), 3),
                       "open_front_bottom_y": fp_shell.V_DOOR_OPEN,
                       "note": "尾の下のふた。後ろの端の蝶番で前を上げて尾の中へ入れる（Basis(Vector3.RIGHT, deg_to_rad(open_deg * t))）"},
        "tail_passage": fp_shell.tail_passage(),
        "props": [{"node": p["node"], "hub": r4(p["hub"]), "spin_axis": [0, 0, 1], "diameter": C.PROP_D,
                   "blades": p["blades"], "pitch_deg": fp_parts.BLADE_PITCH_DEG, "reverse_pitch_delta_deg": REVERSE_PITCH_DELTA}
                  for p in info["props"]],
        "flaps": [{"node": n, "pivot": r4(info["pivots"][n]), "axis": [1, 0, 0], "down_deg": fp_parts.FLAP_MAX_DEG} for n in info["flaps"]],
        "jump_light": {"red": "JumpLight_Red", "green": "JumpLight_Green", "marker": "MK_JumpLight"},
        "cabin_lights": info["cabin_lights"],
        "ramp_actuators": {tag: {"cylinder": a["cylinder"], "rod": a["rod"], "anchor": r4(a["anchor"]), "ramp_point_closed": r4(a["ramp_point_closed"]),
                                 "note": "anchor は胴体（動かない）、ramp_point_closed はスロープの上の点（閉じたとき）。筒・棒のローカル −Z を相手へ向ける"}
                           for tag, a in info["actuators"].items()},
        "lights": {n: r4(p) for n, p in info["lights"].items()},
        "exhausts": [r4(fp_parts.exhaust_point(x)) for x in fp_parts.engine_order()],
        "belts": {"1": "Belt_P1", "2": "Belt_P2"},
        "hatena": {"marker": "MK_PilotSeat", "scale": 1.0, "yaw_deg": 180.0},
        "yoke": {"grip_l": r4(W(fp_interior.YOKE_GRIP[2], fp_interior.YOKE_GRIP[1], -fp_interior.YOKE_GRIP[0])),
                 "grip_r": r4(W(fp_interior.YOKE_GRIP[2], fp_interior.YOKE_GRIP[1], fp_interior.YOKE_GRIP[0]))},
        "materials": sorted(K.MATERIAL_SPECS),
        "dims": dims,
        "design": design_dims(),
    }
    K.LAYOUT_JSON.write_text(json.dumps(layout, ensure_ascii=False, indent=1), encoding="utf-8")
    return layout


def design_dims():
    """c130_design.py の数（README の表の「設計」）。"""
    return {
        "length_overall": C.LENGTH, "span": C.SPAN, "height_overall": round(C.HEIGHT, 4),
        "fuselage_width": round(2 * max(C.FUS_HALF_W), 4), "fuselage_height": round(max(C.FUS_TOP) - min(C.FUS_BOT), 4),
        "hold_length": round(C.HOLD[1] - C.HOLD[0], 4), "hold_inner_width": round(2 * (max(C.FUS_HALF_W) - C.WALL), 4),
        "hold_standing_height": round(C.CEILING_V - C.FLOOR_V, 4), "opening_width": round(2 * C.RAMP_HALF_W, 4),
        "opening_height": round(C.OPENING_TOP_V - C.FLOOR_V, 4), "ramp_length": C.RAMP_LEN, "ramp_width": round(2 * C.RAMP_HALF_W, 4),
        "prop_diameter": C.PROP_D, "float_length": round(C.FLOAT["u1"] - C.FLOAT["u0"], 4), "float_diameter": round(2 * C.FLOAT["r"], 4),
        "float_draft": round(C.FLOAT["r"] - C.FLOAT["v"], 4), "float_spacing": round(2 * C.FLOAT["x"], 4), "floor_height": C.FLOOR_V,
        "flight_deck_height": round(C.FLIGHT_DECK_V, 4),
    }


def main():
    t0 = time.time()
    WARNINGS.clear()
    diffs = check_design_copy()
    if diffs:
        WARNINGS.append(f"c130_design.py の写しと元の数字が違う：{diffs}")
    sc = setup_scene()
    mats = make_materials()
    root, objs, info = build(mats)
    markers = build_markers(root)
    bpy.context.view_layer.update()
    dims = measure(objs, info)
    bake_times = fp_bake.bake_ao(list(objs.values())) if DO_BAKE else {}
    tris = {n: tri_count(o) for n, o in objs.items()}
    size = 0
    if DO_EXPORT:
        size = export_glb(root)
        write_layout(objs, info, markers, dims)
    design = design_dims()
    diff = {k: round(dims[k] - design[k], 4) for k in design if k in dims}
    report = {"seconds": round(time.time() - t0, 1), "glb": str(K.GLB), "glb_bytes": size, "triangles_total": sum(tris.values()),
              "triangles": tris, "stats": info["stats"], "dims": dims, "design": design, "diff": diff, "warnings": list(WARNINGS),
              "door_open_deg": fp_shell.door_open_deg(), "bake_seconds": bake_times}
    K.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    if DO_SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=str(K.BLEND))
    return {"seconds": report["seconds"], "triangles_total": report["triangles_total"], "glb_bytes": size, "diff": diff,
            "stats": info["stats"], "warnings": list(WARNINGS)}


if __name__ == "__main__":
    RESULT = main()
    print("FP_BUILD", json.dumps(RESULT, ensure_ascii=False))
