extends Node

## 水上機 C-130（SuddenDeathFloatplane）の確かめ。floatplane_c130_bootstrap.gd から読む。
## 1) GLB の部品・layout のマーカー・材質の名前（計画書 4.2）がそろっているか
## 2) 関数で部品が動くか（スロープ・上のふた・プロペラ・逆推力・フラップ・ランプ・しぶき・ベルト・機内の灯）
## 3) Godot に読んだ形から寸法を測り、c130_design.py の数（layout の design）と比べる（差 5 cm 以内）
## 4) -- shots=<dir> のとき、実画面（外・機内・操縦席）を撮る
## 結果は標準出力（FLOATPLANE_PROBE {...}）と assets/vehicles/floatplane_c130/source/godot_probe.json。

const REPORT_PATH := "res://assets/vehicles/floatplane_c130/source/godot_probe.json"
const TOLERANCE := 0.05
const REQUIRED_NODES := ["Body", "Interior", "Cockpit", "Floats", "Glass", "Ramp", "UpperDoor", "Prop_1", "Prop_2", "Prop_3", "Prop_4",
	"Blade_1_1", "Blade_4_4", "Flap_L1", "Flap_R3", "JumpLight_Red", "JumpLight_Green", "NavLight_L", "NavLight_R", "Beacon", "TailLight",
	"Belt_P1", "Belt_P2", "RampCyl_L", "RampRod_R"]
const REQUIRED_MARKERS := ["MK_SeatP1", "MK_SeatP2", "MK_StandP1", "MK_StandP2", "MK_RampHinge", "MK_RampEdge", "MK_DeckDoor", "MK_PilotSeat",
	"MK_CamAft", "MK_CamFwd", "MK_TailEnd", "MK_JumpLight"]
const REQUIRED_MATERIALS := ["FP_Paint", "FP_Navy", "FP_StripeOrange", "FP_StripeBlue", "FP_Glass", "FP_SeatWebbing", "FP_LightRed", "FP_LightGreen"]

var report := {"passed": true, "checks": [], "dims": {}, "shots": []}
var plane: SuddenDeathFloatplane = null
var shots_dir := ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots_dir = arg.substr(6)
	call_deferred("run")


func check(ok: bool, label: String, detail: Variant = "") -> void:
	report.checks.append({"ok": ok, "check": label, "detail": str(detail)})
	if not ok:
		report.passed = false
		push_warning("FLOATPLANE CHECK FAILED: %s %s" % [label, str(detail)])


func run() -> void:
	plane = SuddenDeathFloatplane.new()
	plane.name = "Floatplane"
	add_child(plane)
	var built := plane.build("high")
	check(built, "build(\"high\") が通る")
	if not built:
		_finish()
		return
	await get_tree().process_frame
	_check_parts()
	await _check_functions()
	_measure()
	await _check_low_quality()
	if not shots_dir.is_empty():
		await _shots()
	_finish()


func _check_parts() -> void:
	var missing: Array[String] = []
	for n: String in REQUIRED_NODES:
		if plane.model.find_child(n, true, false) == null:
			missing.append(n)
	check(missing.is_empty(), "GLB の部品がそろう", missing)
	var mk_missing: Array[String] = []
	for n: String in REQUIRED_MARKERS:
		if not plane.has_marker(n):
			mk_missing.append(n)
	check(mk_missing.is_empty(), "layout のマーカーがそろう（計画書 4.2 の表）", mk_missing)
	var names := {}
	for node: Node in plane.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s: int in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			if m != null:
				names[m.resource_name] = true
	var mat_missing: Array[String] = []
	for n: String in REQUIRED_MATERIALS:
		if not names.has(n):
			mat_missing.append(n)
	var has_interior := names.keys().any(func(k: String) -> bool: return k.begins_with("FP_Interior"))
	check(mat_missing.is_empty() and has_interior, "材質の名前（FP_Paint・FP_Navy・…・FP_Interior*）", mat_missing)
	# P1 は機体の右の壁（+X）、向きは通路の向かい（−X）
	var p1 := plane.seat_transform(1)
	var p2 := plane.seat_transform(2)
	check(p1.origin.x > 1.5 and p2.origin.x < -1.5, "P1 は右の壁（+X）・P2 は左", [p1.origin, p2.origin])
	check((p1.basis * Vector3.BACK).dot(Vector3.LEFT) > 0.99 and (p2.basis * Vector3.BACK).dot(Vector3.RIGHT) > 0.99, "座る向き（+Z）が通路の向かい")
	var tail := plane.marker("MK_TailEnd").origin
	check(absf(tail.z - 11.45) < 0.02, "尾の一番後ろは z = 11.45（機首から 18.05）", tail)
	var cam := plane.marker("MK_CamAft")
	check((cam.basis * Vector3.FORWARD).z > 0.9, "MK_CamAft は後ろを見る（カメラの −Z）", cam.basis * Vector3.FORWARD)


func _check_functions() -> void:
	# スロープ：1 で床と水平、端がマーカーの位置
	plane.set_ramp(1.0)
	await get_tree().process_frame
	var edge := plane.ramp_edge_now()
	var mk := plane.marker("MK_RampEdge").origin
	check(edge.distance_to(mk) < 0.01, "set_ramp(1)：スロープの端が MK_RampEdge", [edge, mk])
	var ramp_top := _verts(plane.model.find_child("Ramp", true, false), ["FP_InteriorFloor"])
	var ys := ramp_top.map(func(v: Vector3) -> float: return v.y)
	check(ys.max() - ys.min() < 0.01 and absf(ys.max() - 1.90) < 0.01, "set_ramp(1)：スロープの上面が床と水平（y 1.90）", [ys.min(), ys.max()])
	plane.set_ramp(0.0)
	var closed := _verts(plane.model.find_child("Ramp", true, false), ["FP_InteriorFloor"])
	var zs := closed.map(func(v: Vector3) -> float: return v.y)
	check(zs.max() > 3.2, "set_ramp(0)：閉じると端が上がる（25°）", zs.max())
	# 作動筒が付いていく
	plane.set_ramp(0.5)
	var cyl := plane.model.find_child("RampCyl_L", true, false) as Node3D
	var rod := plane.model.find_child("RampRod_L", true, false) as Node3D
	var aim := (cyl.basis * Vector3.FORWARD).normalized().dot((rod.position - cyl.position).normalized())
	check(aim > 0.999, "作動筒の筒が棒の付け根を向く", aim)
	plane.set_ramp(0.0)
	# 上のふた：1 で前の端の下面が 5.0 m
	plane.set_upper_door(1.0)
	var door := _verts(plane.model.find_child("UpperDoor", true, false), ["FP_Paint"])
	var front_low := 99.0
	for v: Vector3 in door:
		if v.z < 7.1 and absf(v.x) < 0.2:
			front_low = minf(front_low, v.y)
	check(absf(front_low - 5.0) < 0.05, "set_upper_door(1)：前の端の下面が海面から 5.0 m", front_low)
	plane.set_upper_door(0.0)
	# フラップ
	plane.set_flaps(1.0)
	var flap := plane.model.find_child("Flap_R2", true, false) as Node3D
	check(absf(rad_to_deg(flap.basis.get_euler().x) - 30.0) < 0.5, "set_flaps(1)：30° 下がる", rad_to_deg(flap.basis.get_euler().x))
	plane.set_flaps(0.0)
	# プロペラ：回る・逆推力で羽根の角度が変わる・速いと円盤
	var hub := plane.model.find_child("Prop_1", true, false) as Node3D
	var blade := plane.model.find_child("Blade_1_1", true, false) as Node3D
	plane.snap_props(1.0, false)
	var b0 := hub.basis
	for i: int in range(3):
		await get_tree().process_frame
	check(not hub.basis.is_equal_approx(b0), "set_props(1)：プロペラが回る")
	var disc_shown := false
	for c: Node in hub.get_parent().get_children():
		if c.name.begins_with("PropDisc") and (c as Node3D).visible:
			disc_shown = true
	check(disc_shown and not blade.visible, "速いときは羽根を隠して円盤")
	plane.snap_props(0.3, true)
	check(not blade.basis.is_equal_approx(Basis.IDENTITY), "set_props(…, true)：逆推力で羽根がねじれる")
	plane.snap_props(0.0, false)
	check(blade.basis.is_equal_approx(Basis.IDENTITY) and blade.visible, "止めると羽根が元に戻る")
	# ランプ
	plane.set_jump_light("red")
	check(plane.jump_light_state == "red", "set_jump_light(\"red\")")
	plane.set_jump_light("green")
	check(plane.jump_light_state == "green", "set_jump_light(\"green\")")
	plane.set_jump_light("off")
	# しぶき
	plane.set_pontoon_spray(1.0)
	var sprays := plane.find_children("Spray*", "GPUParticles3D", false, false)
	check(sprays.size() == 6 and (sprays[0] as GPUParticles3D).emitting, "set_pontoon_spray(1)：しぶき 6 か所", sprays.size())
	plane.set_pontoon_spray(0.0)
	# ベルト・機内の灯
	plane.set_belt(1, true)
	check((plane.model.find_child("Belt_P1", true, false) as Node3D).visible, "set_belt(1, true)")
	plane.set_belt(1, false)
	plane.set_cabin_lighting("red")
	var lights := plane.find_children("CabinLight_downlight*", "SpotLight3D", false, false)
	check(lights.size() >= 20 and (lights[0] as SpotLight3D).light_color.g < 0.3, "set_cabin_lighting(\"red\")：ダウンライトが赤", lights.size())
	plane.set_cabin_lighting("day")


## 画質「低」：作れる・ダウンライトは 3 つに 1 つ・影なし・プロペラは円盤にしない。
func _check_low_quality() -> void:
	var low := SuddenDeathFloatplane.new()
	low.with_pilot = false
	add_child(low)
	var ok := low.build("low")
	var shown := 0
	var shadows := 0
	for l: Node in low.find_children("CabinLight_downlight*", "SpotLight3D", false, false):
		if (l as SpotLight3D).visible:
			shown += 1
		if (l as SpotLight3D).shadow_enabled:
			shadows += 1
	low.snap_props(1.0)
	var disc_off := true
	for d: Node in low.model.find_children("PropDisc", "MeshInstance3D", true, false):
		disc_off = disc_off and not (d as Node3D).visible
	check(ok and shown > 0 and shown <= 9 and shadows == 0 and disc_off, "画質「低」：灯を減らす・影なし・円盤なし", [shown, shadows])
	low.queue_free()
	await get_tree().process_frame


## ノード（と子）の、材質 names の面の頂点（機体のローカルの座標）。
func _verts(node: Node, names: Array, include_children := false) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if node == null:
		return out
	var targets: Array = [node]
	if include_children:
		targets.append_array(node.find_children("*", "MeshInstance3D", true, false))
	var inv := plane.global_transform.affine_inverse()
	for t: Variant in targets:
		var mi := t as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := inv * mi.global_transform
		for s: int in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			if m == null or (not names.is_empty() and not m.resource_name in names):
				continue
			var arr: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in arr:
				out.append(xf * v)
	return out


func _range(vs: Array[Vector3], axis: int) -> Vector2:
	var lo := INF
	var hi := -INF
	for v: Vector3 in vs:
		lo = minf(lo, v[axis])
		hi = maxf(hi, v[axis])
	return Vector2(lo, hi)


func _measure() -> void:
	var design: Dictionary = plane.layout.get("design", {})
	var d := {}
	var all: Array[Vector3] = []
	for n: String in ["Body", "Floats", "Ramp", "UpperDoor"]:
		all.append_array(_verts(plane.model.find_child(n, true, false), []))
	for i: int in range(1, 5):
		all.append_array(_verts(plane.model.find_child("Prop_%d" % i, true, false), [], true))
	var zr := _range(all, 2)
	var yr := _range(all, 1)
	d["length_overall"] = zr.y - zr.x
	d["height_overall"] = yr.y - yr.x
	var body := plane.model.find_child("Body", true, false)
	var wing: Array[Vector3] = []
	for v: Vector3 in _verts(body, ["FP_Paint", "FP_Navy"]):
		if v.y > 5.6 and absf(v.x) > 2.5:
			wing.append(v)
	var wr := _range(wing, 0)
	d["span"] = wr.y - wr.x
	var navy := _verts(body, ["FP_Navy"])
	var hold_navy: Array[Vector3] = []
	for v: Vector3 in navy:
		if v.z > -2.0 and v.z < 4.0 and absf(v.x) < 3.0 and v.y < 3.5:
			hold_navy.append(v)
	var nr := _range(hold_navy, 0)
	d["fuselage_width"] = nr.y - nr.x
	var top := -INF
	for v: Vector3 in _verts(body, ["FP_Paint"]):
		if v.z > 3.0 and v.z < 4.0 and absf(v.x) < 0.3:
			top = maxf(top, v.y)
	d["fuselage_height"] = top - _range(hold_navy, 1).x
	var lining: Array[Vector3] = []
	for v: Vector3 in _verts(body, ["FP_InteriorWall"]):
		if v.z > -2.9 and v.z < 4.3:
			lining.append(v)
	var lr := _range(lining, 0)
	var interior := plane.model.find_child("Interior", true, false)
	var floor_top := -INF
	for v: Vector3 in _verts(interior, ["FP_InteriorFloor"]):
		floor_top = maxf(floor_top, v.y)
	d["floor_height"] = floor_top
	d["hold_inner_width"] = lr.y - lr.x
	d["hold_standing_height"] = _range(lining, 1).y - floor_top
	# 貨物室の長さ：前の壁（操縦席との間、FP_InteriorBlanket の平らな面の z）〜スロープの付け根（MK_RampHinge）
	var bulk_z := INF
	for v: Vector3 in _verts(interior, ["FP_InteriorBlanket"]):
		if absf(v.x) < 0.9 and v.y > 3.0:
			bulk_z = minf(bulk_z, v.z)
	d["hold_length"] = plane.marker_local("MK_RampHinge").origin.z - bulk_z
	# 開口：枠の縁（FP_InteriorDark、z 4.35〜4.59）
	var edge_x := 0.0
	var edge_top := 0.0
	for v: Vector3 in _verts(interior, ["FP_InteriorDark"]):
		if v.z > 4.34 and v.z < 4.60:
			if v.y > 1.7 and v.y < 5.1 and absf(v.x) < 1.6:
				edge_x = maxf(edge_x, absf(v.x))
			if absf(v.x) < 0.1 and v.y < 5.25:
				edge_top = maxf(edge_top, v.y)
	d["opening_width"] = 2.0 * edge_x
	d["opening_height"] = edge_top - floor_top
	plane.set_ramp(1.0)
	var rt := _verts(plane.model.find_child("Ramp", true, false), ["FP_InteriorFloor"])
	d["ramp_length"] = _range(rt, 2).y - _range(rt, 2).x
	d["ramp_width"] = _range(rt, 0).y - _range(rt, 0).x
	plane.set_ramp(0.0)
	var hub := plane.model.find_child("Prop_1", true, false) as Node3D
	var rmax := 0.0
	var hub_pos := (plane.global_transform.affine_inverse() * hub.global_transform).origin
	for b: Node in hub.find_children("Blade_*", "MeshInstance3D", true, false):
		for v: Vector3 in _verts(b, []):
			rmax = maxf(rmax, Vector2(v.x - hub_pos.x, v.y - hub_pos.y).length())
	d["prop_diameter"] = 2.0 * rmax
	var fl: Array[Vector3] = []
	for v: Vector3 in _verts(plane.model.find_child("Floats", true, false), ["FP_Paint", "FP_Navy"]):
		if v.x > 2.6 and v.y < 1.06:
			fl.append(v)
	d["float_length"] = _range(fl, 2).y - _range(fl, 2).x
	d["float_diameter"] = _range(fl, 1).y - _range(fl, 1).x
	d["float_draft"] = -_range(fl, 1).x
	var fx := _range(fl, 0)
	d["float_spacing"] = fx.x + fx.y
	var deck := -INF
	for v: Vector3 in _verts(plane.model.find_child("Cockpit", true, false), ["FP_InteriorTread"]):
		deck = maxf(deck, v.y)
	d["flight_deck_height"] = deck
	var rows := []
	var worst := 0.0
	for key: String in design:
		if not d.has(key):
			continue
		var diff := float(d[key]) - float(design[key])
		worst = maxf(worst, absf(diff))
		rows.append({"key": key, "godot": snappedf(float(d[key]), 0.001), "design": float(design[key]), "diff": snappedf(diff, 0.001)})
	report.dims = {"rows": rows, "worst_abs_diff": snappedf(worst, 0.001)}
	check(worst <= TOLERANCE, "寸法の差が 5 cm 以内（Godot で読んだ形 と c130_design.py）", worst)


# ---------- 実画面 ----------

func _seat_doll(is_p1: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "DollP1" if is_p1 else "DollP2"
	plane.add_child(holder)
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(is_p1, holder, 0)
	var pelvis := parts.get("pelvis") as Node3D
	pelvis.global_transform = plane.seat_transform(1 if is_p1 else 2)
	for k: String in ["l_hip", "r_hip"]:
		var hip := parts.get(k) as Node3D
		if hip != null:
			hip.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
	for k: String in ["l_knee", "r_knee"]:
		var knee := parts.get(k) as Node3D
		if knee != null:
			knee.rotation = Vector3(deg_to_rad(90.0), 0, 0)
	for k: String in ["l_shoulder", "r_shoulder"]:
		var sh := parts.get(k) as Node3D
		if sh != null:
			sh.rotation = Vector3(deg_to_rad(-25.0), 0, 0)
	return holder


func _shots() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = StageEnvironment.create_stage_sky()
	StageEnvironment.configure_stage_environment(e)
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -150, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	var ocean := StageEnvironment.create_ocean_surface()
	add_child(ocean)
	StageEnvironment.configure_ocean_surface(ocean, "high")
	ocean.position = Vector3(0, 0.0, 0)
	ocean.scale = Vector3.ONE
	_seat_doll(true)
	_seat_doll(false)
	plane.set_belt(1, true)
	plane.set_belt(2, true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	# [名前, 目, 見る所（または "MK_*"）, fov, ramp, door, props, cabin, jump]
	var list := [
		["godot_ext_34", Vector3(-17, 8.5, -16), Vector3(0, 4.0, 1.5), 42.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_ext_side_left", Vector3(-25, 3.8, 1.0), Vector3(0, 4.0, 1.0), 40.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_ext_rear_open", Vector3(7.5, 4.0, 27.0), Vector3(0, 3.8, 9.0), 40.0, 1.0, 1.0, 0.8, "day", "off"],
		["godot_ext_nose", Vector3(-6.5, 5.2, -14.0), Vector3(0, 4.3, -5.4), 40.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_ext_float", Vector3(-9.0, 1.3, -6.5), Vector3(-3.6, 0.8, 1.0), 45.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_int_aft", "MK_CamAft", null, 72.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_int_fwd", "MK_CamFwd", null, 72.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_int_red_open", "MK_CamAft", null, 72.0, 1.0, 1.0, 0.6, "red", "red"],
		["godot_int_seats", Vector3(-0.9, 3.55, -1.6), Vector3(1.9, 2.85, 1.4), 62.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_int_wall", Vector3(0.6, 3.3, 3.3), Vector3(-2.0, 3.7, 2.2), 58.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_cockpit", Vector3(0.62, 5.02, -3.70), Vector3(-0.05, 4.05, -5.95), 60.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_cockpit_side", Vector3(0.95, 4.45, -4.15), Vector3(-0.15, 4.0, -5.75), 62.0, 0.0, 0.0, 0.0, "day", "off"],
		# 2026-10-22 に足した画：演出の操縦席の目（floatplane_staging.gd の COCKPIT_EYE → COCKPIT_AIM）・エンジン・フロート・天井の盤
		["godot_cockpit_eye", Vector3(0.9, 4.55, -4.55), Vector3(0.2, 4.2, -14.0), 70.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_cockpit_back", Vector3(-0.55, 4.62, -3.55), Vector3(0.1, 4.25, -5.6), 66.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_ext_engine", Vector3(-10.5, 7.2, -9.0), Vector3(-6.0, 5.3, -2.0), 40.0, 0.0, 0.0, 0.0, "day", "off"],
		["godot_ext_float_bow", Vector3(-7.5, 2.4, -10.5), Vector3(-3.6, 0.5, -3.0), 42.0, 0.0, 0.0, 0.0, "day", "off"],
	]
	DirAccess.make_dir_recursive_absolute(shots_dir)
	for s: Array in list:
		plane.set_ramp(float(s[4]))
		plane.set_upper_door(float(s[5]))
		plane.snap_props(float(s[6]), false)
		plane.set_cabin_lighting(str(s[7]))
		plane.set_jump_light(str(s[8]))
		if s[1] is String:
			cam.global_transform = plane.marker(str(s[1]))
		else:
			cam.position = s[1]
			cam.look_at(s[2])
		cam.fov = float(s[3])
		cam.near = 0.03
		for i: int in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [shots_dir, s[0]]
		get_viewport().get_texture().get_image().save_png(path)
		report.shots.append(path)


func _finish() -> void:
	var text := JSON.stringify(report, "  ")
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
	print("FLOATPLANE_PROBE " + JSON.stringify({"passed": report.passed, "worst_abs_diff": report.dims.get("worst_abs_diff"),
		"failed": report.checks.filter(func(c: Dictionary) -> bool: return not c.ok), "shots": report.shots.size()}))
	get_tree().quit(0 if report.passed else 1)
