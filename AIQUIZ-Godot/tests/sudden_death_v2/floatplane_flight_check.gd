extends "res://tests/sudden_death_v2/skygate_runtime.gd"

## 水上機の離着水（docs/sudden_death_v2/c130_float.md 第9章）を実際の GameWorld で撮って測る。skygate_runtime と同じ進みで、
## 見たい場面のあいだ 3 フレームごとに画を撮り、毎フレームの機体の位置・速さ・加速度・姿勢を telemetry.csv に書く。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/floatplane_flight_check_bootstrap.gd -- focus=board
## focus:
##   board   乗り込み（進入・着水・後ろ向きに寄せる・機内・離水）。SKY に入ったら終わる。
##   pickup  勝者の迎え（round2 の進み：着地台の上を越えて着水・後ろ向きに寄せる・駆け込み）。ROUND の間の迎えは 2026-10-20 に
##           やめた（着地のあと暗転して機内から短い降下）ので、迎えは勝者の分だけ。
##   home    勝者の帰還（p1 の進み）。DONE で終わる。
## 出力：artifacts/sudden_death_v2/floatplane_flight/<focus>/（f*.png・telemetry.csv・report.json）。
## 確かめる数字：速さ・加速度のとび（なめらかさ）、持ち上げたスタンドとのすき間、台座・向こうのスタンドの上の高さ、止まる位置。

const FLIGHT_OUT := "res://artifacts/sudden_death_v2/floatplane_flight/"
const EVERY := 3

var focus := "board"
var my_out := ""
var _rows: PackedStringArray = PackedStringArray()
var _top_points: Array[Vector3] = []
var _low_points: Array[Vector3] = []
var _last_pos := Vector3.INF
var _last_vel := Vector3.INF
var _metrics := {"max_accel": 0.0, "max_jerk_frames": 0, "min_stand_gap": INF, "min_floor_gap": INF, "min_far_stand_gap": INF,
	"max_pitch_deg": -INF, "min_pitch_deg": INF, "max_roll_deg": 0.0}
var _focus_done := false


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("focus="):
			focus = arg.trim_prefix("focus=")
	var cmd := "p1"
	if focus == "pickup":
		cmd = "round2"
	# 親の case= を合わせる（オートパイロットのまちがえ方）
	case_name = cmd
	my_out = FLIGHT_OUT + focus + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(my_out))
	for file: String in DirAccess.get_files_at(ProjectSettings.globalize_path(my_out)):
		if file.ends_with(".png") or file.ends_with(".csv"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(my_out + file))
	# 親の場面ごとの画は撮らない（こちらで 3 フレームごとに撮る）
	_shot_count = 100000
	_rows.append("frame,act,t,shot,step,x,y,z,pitch,roll,yaw,v,a,d,speed_world,accel_world,cam_x,cam_y,cam_z")
	await super.run()


func _focus_acts() -> Array[String]:
	match focus:
		"pickup":
			return ["EXTRACT"]
		"home":
			return ["HOME"]
	return ["BOARD"]


func _watch() -> void:
	super._watch()
	var act := director.act_name()
	var staging := director.floatplane_staging()
	if staging == null or staging.plane == null:
		return
	if act in _focus_acts():
		if _top_points.is_empty():
			_collect_points(staging.plane)
		_record(act, staging)
		if _frame % EVERY == 0:
			_pending_shots.append([_frame, "f%05d_%s" % [_frame, director.shot_name()]])
	elif not _rows.is_empty() and _rows.size() > 1 and not _focus_done and _seen_focus():
		_focus_done = true
		_write_outputs()
		get_tree().quit(0 if (report.failures as Array).is_empty() else 1)


func _seen_focus() -> bool:
	for row: Array in report.acts:
		if String(row[0]) in _focus_acts():
			return true
	return false


## 機体のメッシュの頂点から、上のほう（尾翼・翼・プロペラ）と下のほう（浮き舟の底）の点を拾う（機体のローカル、間引く）。
func _collect_points(plane: SuddenDeathFloatplane) -> void:
	var inv := plane.global_transform.affine_inverse()
	for node: Node in plane.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.name.begins_with("PropDisc"):
			continue
		var to_plane := inv * mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var stride := maxi(1, verts.size() / 400)
			for i in range(0, verts.size(), stride):
				var p := to_plane * verts[i]
				if p.y > 4.2:
					_top_points.append(p)
				elif p.y < -0.3:
					_low_points.append(p)
	# プロペラの羽根の先（回っている円の上端）
	for row: Variant in plane.layout.get("props", []):
		var hub: Array = (row as Dictionary).get("hub", [0, 5.2, -3.7])
		var r := float((row as Dictionary).get("diameter", 2.8)) * 0.5
		_top_points.append(Vector3(float(hub[0]), float(hub[1]) + r, float(hub[2])))


func _record(act: String, staging: FloatplaneStaging) -> void:
	var plane := staging.plane
	var xf := plane.global_transform
	var dt := 1.0 / 60.0
	var pos := xf.origin
	var speed := 0.0
	var accel := 0.0
	if _last_pos != Vector3.INF:
		var vel := (pos - _last_pos) / dt
		speed = vel.length()
		if _last_vel != Vector3.INF:
			var acc := (vel - _last_vel) / dt
			accel = acc.length()
			# 道すじを替えるカット（時間を飛ばす）は数えない
			if (pos - _last_pos).length() < 3.0 and plane.visible:
				_metrics.max_accel = maxf(float(_metrics.max_accel), accel)
				if accel > 40.0:
					_metrics.max_jerk_frames = int(_metrics.max_jerk_frames) + 1
		_last_vel = vel if (pos - _last_pos).length() < 3.0 else Vector3.INF
	_last_pos = pos
	var euler := xf.basis.get_euler(EULER_ORDER_YXZ)
	var snap: Dictionary = staging.get_debug_snapshot()
	var step := String(snap.get("step", ""))
	var flight: Dictionary = snap.get("flight", {})
	var cam := director.main_camera()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	# 機体の左右の傾き・機首の上げ（ワールドで）
	var forward := -xf.basis.z
	var pitch_deg := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	var right := xf.basis.x
	var roll_deg := rad_to_deg(asin(clampf(-right.y, -1.0, 1.0)))
	if plane.visible and act in ["BOARD", "EXTRACT"]:
		_metrics.max_pitch_deg = maxf(float(_metrics.max_pitch_deg), pitch_deg)
		_metrics.min_pitch_deg = minf(float(_metrics.min_pitch_deg), pitch_deg)
		_metrics.max_roll_deg = maxf(float(_metrics.max_roll_deg), absf(roll_deg))
	if act == "BOARD":
		_measure_board(staging, xf)
	_rows.append("%d,%s,%.3f,%s,%s,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f" % [
		_frame, act, director.act_time(), director.shot_name(), step, pos.x, pos.y, pos.z, pitch_deg, roll_deg,
		rad_to_deg(euler.y), float(flight.get("v", 0.0)), float(flight.get("a", 0.0)), float(flight.get("d", 0.0)), speed, accel,
		cam_pos.x, cam_pos.y, cam_pos.z])


## 乗り込みの進入：持ち上げたスタンドの下とのすき間、台座の床と向こうのスタンドの上の高さ。
func _measure_board(staging: FloatplaneStaging, xf: Transform3D) -> void:
	if staging.gate == null or String(staging.get_debug_snapshot().get("step", "")) != "approach":
		return
	var bottom := staging.gate.lifted_bottom_y()
	var gap_z := staging.gate.gap_center_z()
	for p: Vector3 in _top_points:
		var w := xf * p
		if w.x > 27.2 and w.x < 42.5 and absf(w.z - gap_z) < 20.0:
			_metrics.min_stand_gap = minf(float(_metrics.min_stand_gap), bottom - w.y)
	var floor_y := StageConstants.FLOOR_TOP_Y
	for p: Vector3 in _low_points:
		var w := xf * p
		if absf(w.x) < 12.0:
			_metrics.min_floor_gap = minf(float(_metrics.min_floor_gap), w.y - floor_y)
		elif w.x < -27.2 and w.x > -42.5:
			_metrics.min_far_stand_gap = minf(float(_metrics.min_far_stand_gap), w.y - (StageConstants.OCEAN_SURFACE_Y + 19.35))


func _flush_shots() -> void:
	var keep: Array = []
	for row: Array in _pending_shots:
		if _frame >= int(row[0]):
			await RenderingServer.frame_post_draw
			var path := my_out + String(row[1]) + ".png"
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		else:
			keep.append(row)
	_pending_shots = keep


func _write_outputs() -> void:
	var f := FileAccess.open(my_out + "telemetry.csv", FileAccess.WRITE)
	f.store_string("\n".join(_rows))
	f.close()
	var staging := director.floatplane_staging()
	var out_report := {"focus": focus, "metrics": _metrics, "acts": report.acts, "failures": report.failures, "checks": report.checks}
	if staging != null:
		out_report["staging"] = staging.get_debug_snapshot()
	var r := FileAccess.open(my_out + "report.json", FileAccess.WRITE)
	r.store_string(JSON.stringify(out_report, "  "))
	r.close()
	print("FLOATPLANE_FLIGHT ", JSON.stringify({"focus": focus, "metrics": _metrics, "failures": report.failures}))


func _finish() -> void:
	if not _focus_done:
		_focus_done = true
		_write_outputs()
	get_tree().quit(0 if (report.failures as Array).is_empty() else 1)
