extends Node

## ゴーストシャークの突進が生き残り側（P2）に当たる前後を、本物の 2P の GameWorld で撮って測る
## （docs/ghost_hit_ragdoll_plan.md 段階 0：今の状態の記録）。
## P1 が壁で脱落 → 照準になったら、生き残り（P2）へ決めた強さ・横ずれで突進させる（生き残りはドアの前のまま）。
## 撮る絵：main（ゲームの画面）・side（突進の真横）・front（体が飛んでいく先の斜め前）・chase（サメの後ろ → 命中後は体を追う）。
## 測るもの（毎フレーム）：
##   サメの胴（スキニング後の頂点から作った断面の楕円で近似）・乗り手の箱と、生き残りの体の箱（各 27 点）の重なりの深さ、
##   命中の横ずれ s（判定の幅 1.45 m で割った値）、体の位置・高さ、サメの速さ、鼻先と体の距離。
## 引数（"--" の後ろ）:
##   tag=<名前>        出力先 artifacts/ghost_hit_capture/<tag>/
##   hit=center|side   真ん中に当てる / 横に 0.95 m ずらして当てる（既定 center）
##   power=<0〜1>      突進の強さ（既定 1.0。0.72〜0.94 は PERFECT）
##   after=<N>         命中のあと撮るフレーム数（既定 150）
##   every=<N>         N フレームごとに絵を保存（既定 1。計測は毎フレーム）
##   quality=<画質>    low|balanced|high|ultra（既定 high）
##   images=0          絵を保存しない（計測だけ）
##   x=<m>             照準の前に生き残りを横のこの位置へ動かす（強い命中でも床に落ちるように。既定は動かさない）
##   z=<m>             照準の前に生き残りを前（+）/ 後ろ（−）へこれだけ動かす（サメの待つ位置も一緒に動く）
##   saw=0             2 人用ののこぎりを止める（床の後ろへ飛んだ体が刃に入って脱落しないように）
const OUT_ROOT := "res://artifacts/ghost_hit_capture/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const VIEW_SIZE := Vector2i(960, 540)
const SLABS := 32
const SLAB_PERCENTILE := 0.92
const SIDE_OFFSET := 0.95
const HIT_HALF_WIDTH := 1.45
const MAX_PROFILE_VERTICES := 8000
const OVERLAP_EPSILON := 0.02

var gs: QuizGameState
var world: Node3D
var ghost: GhostSharkRideController
var player: Node
var helper: Node
var out := ""
var tag := "hit"
var hit_kind := "center"
var power := 1.0
var after := 150
var every := 1
var save_images := true
var survivor_x := NAN
var saw_enabled := true
var survivor_dz := 0.0
## move=<フレーム>：命中からこのフレーム以降、操作が戻っていれば生き残りを横へ 6 m/s で動かす（起き上がりの切り上げを見る）。−1 は動かさない。
var move_from := -1
var quality := GraphicsQualityRules.HIGH

var _recording := false
var _frame := 0
var _hit_frame := -1
var _charging_frame := -1
var _views: Dictionary = {}
var _hit_center := Vector3.ZERO
var _dir := Vector3.FORWARD
var _perp := Vector3.RIGHT
var _chase_hold := Vector3.ZERO
var _chase_held := false
var _skin_data: Array[Dictionary] = []
var _axis := 0
var _axis_sign := 1.0
var _samples: Array[Dictionary] = []
var _dims := {}
var _hit_info := {}
var _prev_shark := Vector3.ZERO
var _prev_nose_ahead := -INF
var _nose_pass_frame := -1
var _last_usec := 0
## 鳴った効果音 [録り始めからのフレーム, 名前]（段階 6）。
var _sfx: Array = []


func _ready() -> void:
	process_priority = 1000
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
		elif arg.begins_with("hit="):
			hit_kind = arg.trim_prefix("hit=")
		elif arg.begins_with("power="):
			power = clampf(float(arg.trim_prefix("power=")), 0.0, 1.0)
		elif arg.begins_with("after="):
			after = maxi(10, int(arg.trim_prefix("after=")))
		elif arg.begins_with("every="):
			every = maxi(1, int(arg.trim_prefix("every=")))
		elif arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg == "images=0":
			save_images = false
		elif arg.begins_with("x="):
			survivor_x = float(arg.trim_prefix("x="))
		elif arg.begins_with("z="):
			survivor_dz = float(arg.trim_prefix("z="))
		elif arg == "saw=0":
			saw_enabled = false
		elif arg.begins_with("move="):
			move_from = int(arg.trim_prefix("move="))
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out + f))
	get_tree().root.size = Vector2i(1920, 1080)
	var bgm := AudioServer.get_bus_index("BGM")
	if bgm >= 0:
		AudioServer.set_bus_mute(bgm, true)
	GameManager.graphics_quality = quality
	GraphicsQualityRules.adaptive_budget_override_ms = 100000.0
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	seed(7)

	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	player = world.get_node("Player")
	player.prepare_for_loading(gs)
	player.reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	await _frames(90)
	if not saw_enabled:
		gs.saw_transport_enabled = false

	# P1 が壁で脱落 → ゴーストの搭乗の演出 → 照準まで進める。
	gs._set_player_hp(1, 1)
	gs.player_x = helper.door(gs, false)
	gs.player2_x = helper.door(gs, true)
	gs.resolve_collision(true, true)
	var reached := await _wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 1800)
	if not reached:
		_finish(false, "never reached AIMING")
		return
	await _frames(30)
	if not is_nan(survivor_x) or survivor_dz != 0.0:
		# 生き残りを動かし、照準の基準点もそこへ移す（サメは床の外の横で待ち、前後は生き残りについてくる）。
		if not is_nan(survivor_x):
			gs.player2_x = survivor_x
			ghost._aim_origin.x = survivor_x
		gs.player2_z += survivor_dz
		await _frames(30)
	# 照準の基準点（_aim_origin）は脱落した時の生き残りの位置で固まり、照準はそこから ±8 m までしか動かない。
	# 生き残りは動かさず、照準を今の体の位置へ合わせる（毎フレームの ±8 m の制限の内側）。
	var shark: Node3D = ghost._shark
	var survivor: Vector3 = ghost._player_position(2)
	var origin: Vector3 = ghost._aim_origin
	var to_aim := Vector2(survivor.x - shark.global_position.x, survivor.z - shark.global_position.z).normalized()
	var aim_offset := Vector2(survivor.x - origin.x, survivor.z - origin.z)
	if hit_kind == "side":
		aim_offset += Vector2(-to_aim.y, to_aim.x) * SIDE_OFFSET
	ghost._aim_offset = aim_offset
	await _frames(2)

	_prepare_skin_data()
	_measure_dims()
	_build_views()
	AudioManager.sfx_played.connect(func(cue: StringName) -> void:
		if _recording:
			_sfx.append([_frame, str(cue)]))
	ghost._charging_input = true
	ghost._charge_amount = power
	ghost._commit_charge()
	_prev_shark = shark.global_position
	_place_cameras()
	_recording = true
	await _wait_until(func(): return _hit_frame >= 0 and _frame >= _hit_frame + after, 900)
	var no_hit_end := _hit_frame < 0
	_recording = false
	await _frames(2)
	_finish(not no_hit_end, "no hit" if no_hit_end else "")


func _finish(ok: bool, note: String) -> void:
	var report := {
		"ok": ok,
		"note": note,
		"args": {"hit": hit_kind, "power": power, "after": after, "every": every, "x": survivor_x if not is_nan(survivor_x) else null, "saw": saw_enabled, "z": survivor_dz, "move": move_from},
		"dims": _dims,
		"hit": _hit_info,
		"summary": _summarize(),
		"sfx": _sfx.map(func(e: Array) -> Array: return [int(e[0]) - _hit_frame, e[1]]) if _hit_frame >= 0 else _sfx,
		"frames": _samples,
	}
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GHOST_HIT_CAPTURE " + JSON.stringify({"ok": ok, "note": note, "summary": report.summary, "dims": _dims, "out": ProjectSettings.globalize_path(out)}))
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- 毎フレーム

func _process(_dt: float) -> void:
	if not _recording or ghost == null:
		return
	var rel := _frame
	_frame += 1
	if move_from >= 0 and _hit_frame >= 0 and rel - _hit_frame >= move_from and gs.p2_external_control_lock <= 0.0 and gs.p2_alive:
		gs.player2_x += 6.0 / 60.0
	var shark: Node3D = ghost._shark
	if shark == null or not is_instance_valid(shark) or not shark.is_visible_in_tree():
		# 突進のあとサメが戻りのポータルへ消えても、体の動き（着地・滑り）は撮り続ける。
		_samples.append(_measure_body_only(rel))
		_update_follow_camera()
		if save_images and rel % every == 0:
			_save(rel)
		return
	if ghost.phase == ghost.Phase.CHARGING and _charging_frame < 0:
		_charging_frame = rel
		_place_cameras()
	if _hit_frame < 0 and bool(ghost._hit_this_charge):
		_hit_frame = rel
		_record_hit_info(rel)
	var sample := _measure(rel)
	_samples.append(sample)
	_update_chase_camera()
	_update_follow_camera()
	_prev_shark = shark.global_position
	if save_images and rel % every == 0:
		_save(rel)


func _measure(rel: int) -> Dictionary:
	var shark: Node3D = ghost._shark
	var frame := _shark_frame()
	var frame_inv := frame.affine_inverse()
	var root := _survivor_root()
	var parts: Dictionary = player.get("p2_parts")
	var pelvis := parts.get("pelvis") as Node3D
	var pelvis_pos := pelvis.global_position if pelvis != null else Vector3.ZERO
	var nose: Vector3 = shark.get_ocean_attack_head_position()
	var sample := {
		"f": rel,
		"t": snappedf(float(rel - _hit_frame) / 60.0, 0.001) if _hit_frame >= 0 else null,
		"phase": str(ghost.Phase.keys()[ghost.phase]),
		"shark": _v(shark.global_position),
		"shark_speed": snappedf(shark.global_position.distance_to(_prev_shark) * 60.0, 0.01),
		"nose": _v(nose),
		"root": _v(root.global_position) if root != null else null,
		"pelvis": _v(pelvis_pos),
		"game_pos": _v(ghost._player_position(2)),
		"game_y": snappedf(gs.player2_y, 0.001),
		"ext_vel": [snappedf(gs.p2_external_velocity.x, 0.01), snappedf(gs.p2_external_velocity.y, 0.01)],
		"control_lock": snappedf(gs.p2_external_control_lock, 0.001),
		"alive": gs.p2_alive,
		"ragdoll": bool(player.has_ghost_hit_ragdoll(2)),
		"gh_phase": int(player.get_ghost_hit_phase(2)),
		"upright": _upright(),
		"dust": _dust_count(),
		"frame_ms": snappedf(float(Time.get_ticks_usec() - _last_usec) / 1000.0, 0.01),
	}
	_last_usec = Time.get_ticks_usec()
	# 鼻先が体の前後どちらか（突進の向きに沿った距離。+ なら鼻先が骨盤を通り過ぎた）
	var nose_ahead := (nose - pelvis_pos).dot(_dir)
	sample["nose_ahead"] = snappedf(nose_ahead, 0.001)
	if _nose_pass_frame < 0 and _prev_nose_ahead < 0.0 and nose_ahead >= 0.0:
		_nose_pass_frame = rel
	_prev_nose_ahead = nose_ahead
	# 重なり：サメの近くにいるときだけ（スキニングの計算が重いので）
	var near := shark.global_position.distance_to(pelvis_pos) < 8.0
	sample["near"] = near
	if near:
		var profile := _profile_from(_posed_shark_points(frame_inv))
		var shark_depth := 0.0
		var rider_depth := 0.0
		var shark_parts: Array[String] = []
		var rider_parts: Array[String] = []
		var rider_boxes: Array[Dictionary] = []
		for rm in _rider_meshes():
			rider_boxes.append({"inv": rm.global_transform.affine_inverse(), "box": rm.get_aabb(), "scale": rm.global_transform.basis.get_scale()})
		for mi in _survivor_meshes():
			var part_shark := 0.0
			var part_rider := 0.0
			for p in _box_points(mi):
				part_shark = maxf(part_shark, _shark_depth(profile, frame_inv * p))
				for rb: Dictionary in rider_boxes:
					part_rider = maxf(part_rider, _box_depth_local(rb.box, rb.scale, (rb.inv as Transform3D) * p))
			if part_shark > OVERLAP_EPSILON:
				shark_parts.append(_part_name(mi))
			if part_rider > OVERLAP_EPSILON:
				rider_parts.append(_part_name(mi))
			shark_depth = maxf(shark_depth, part_shark)
			rider_depth = maxf(rider_depth, part_rider)
		sample["shark_depth"] = snappedf(shark_depth, 0.001)
		sample["rider_depth"] = snappedf(rider_depth, 0.001)
		sample["shark_parts"] = shark_parts
		sample["rider_parts"] = rider_parts
	return sample


func _measure_body_only(rel: int) -> Dictionary:
	var root := _survivor_root()
	var parts: Dictionary = player.get("p2_parts")
	var pelvis := parts.get("pelvis") as Node3D
	return {
		"f": rel,
		"t": snappedf(float(rel - _hit_frame) / 60.0, 0.001) if _hit_frame >= 0 else null,
		"phase": str(ghost.Phase.keys()[ghost.phase]),
		"root": _v(root.global_position) if root != null else null,
		"pelvis": _v(pelvis.global_position) if pelvis != null else null,
		"game_pos": _v(ghost._player_position(2)),
		"game_y": snappedf(gs.player2_y, 0.001),
		"ext_vel": [snappedf(gs.p2_external_velocity.x, 0.01), snappedf(gs.p2_external_velocity.y, 0.01)],
		"control_lock": snappedf(gs.p2_external_control_lock, 0.001),
		"alive": gs.p2_alive,
		"ragdoll": bool(player.has_ghost_hit_ragdoll(2)),
		"gh_phase": int(player.get_ghost_hit_phase(2)),
		"upright": _upright(),
		"dust": _dust_count(),
		"near": false,
	}


func _record_hit_info(rel: int) -> void:
	var shark: Node3D = ghost._shark
	var locked: Vector3 = ghost._locked_direction
	var dir2 := Vector2(locked.x, locked.z).normalized()
	var perp2 := Vector2(-dir2.y, dir2.x)
	# ゴーストの判定と同じ空間（ゲームの座標）での横ずれ
	var target: Vector3 = ghost._player_position(2) + Vector3.UP * 0.85
	var from := _prev_shark
	var offset_game := Vector2(target.x - from.x, target.z - from.z).dot(perp2)
	# 見た目の骨盤での横ずれ
	var parts: Dictionary = player.get("p2_parts")
	var pelvis := parts.get("pelvis") as Node3D
	var pelvis_pos := pelvis.global_position if pelvis != null else target
	var offset_visual := Vector2(pelvis_pos.x - from.x, pelvis_pos.z - from.z).dot(perp2)
	_hit_info = {
		"frame": rel,
		"charging_frame": _charging_frame,
		"power": snappedf(float(ghost._last_charge_power), 0.001),
		"perfect": bool(ghost._perfect_charge),
		"locked_direction": _v(locked),
		"shark_at_hit": _v(shark.global_position),
		"shark_speed_at_hit": snappedf(shark.global_position.distance_to(_prev_shark) * 60.0, 0.01),
		"aim_target_game": _v(target),
		"pelvis_at_hit": _v(pelvis_pos),
		"vertical_gap_pelvis_minus_aim": snappedf(pelvis_pos.y - target.y, 0.001),
		"offset_game_m": snappedf(offset_game, 0.001),
		"s_game": snappedf(offset_game / HIT_HALF_WIDTH, 0.001),
		"offset_visual_m": snappedf(offset_visual, 0.001),
		"nose_ahead_of_pelvis_at_hit": snappedf((shark.get_ocean_attack_head_position() - pelvis_pos).dot(_dir), 0.001),
	}
	# 段階 1〜3 の当たり方（GhostSharkRideController._last_hit_info）
	var info: Variant = ghost.get("_last_hit_info")
	if info is Dictionary and not (info as Dictionary).is_empty():
		var d := info as Dictionary
		_hit_info["contact_part"] = str(d.get("part", ""))
		_hit_info["contact_lead_m"] = snappedf(float(d.get("lead", 0.0)), 0.001)
		_hit_info["contact_point"] = _v(d.get("point", Vector3.ZERO))
		_hit_info["contact_height_above_pelvis"] = snappedf((d.get("point", Vector3.ZERO) as Vector3).y - pelvis_pos.y, 0.001)
		_hit_info["s_contact"] = snappedf(float(d.get("s", 0.0)), 0.001)
		_hit_info["launch_velocity"] = _v(d.get("launch_velocity", Vector3.ZERO))
		_hit_info["tumble"] = bool(d.get("tumble", false))
		_hit_info["roll"] = bool(d.get("roll", false))
		_hit_info["control_lock"] = snappedf(float(d.get("control_lock", 0.0)), 0.001)


## 被弾の砂ぼこりの見えている粒の数（段階 6）。
func _dust_count() -> int:
	var dust: Variant = player.get_ghost_hit_dust() if player.has_method("get_ghost_hit_dust") else null
	return int(dust.active_count()) if dust is Node and is_instance_valid(dust) else 0


func _summarize() -> Dictionary:
	var shark_frames := 0
	var rider_frames := 0
	var max_shark := 0.0
	var max_rider := 0.0
	var first_shark := -1
	var last_shark := -1
	var parts_hit := {}
	var peak_y := 0.0
	var air_frames := 0
	var landed_frame := -1
	var start_root := Vector3.ZERO
	var end_root := Vector3.ZERO
	# 段階 4：被弾の段が変わったフレーム（命中から）と、操作が戻ったフレーム
	var phase_first := {}
	var control_back := -1
	var min_upright := 1.0
	for s: Dictionary in _samples:
		if _hit_frame >= 0 and int(s.f) > _hit_frame:
			var gp := int(s.get("gh_phase", -1))
			var key := str(gp)
			if not phase_first.has(key):
				phase_first[key] = int(s.f) - _hit_frame
			if control_back < 0 and int(s.f) > _hit_frame + 6 and float(s.get("control_lock", 0.0)) <= 0.0:
				control_back = int(s.f) - _hit_frame
			min_upright = minf(min_upright, float(s.get("upright", 1.0)))
		var sd := float(s.get("shark_depth", 0.0))
		var rd := float(s.get("rider_depth", 0.0))
		if sd > OVERLAP_EPSILON:
			shark_frames += 1
			if first_shark < 0:
				first_shark = int(s.f)
			last_shark = int(s.f)
			for p: String in s.get("shark_parts", []):
				parts_hit[p] = true
		if rd > OVERLAP_EPSILON:
			rider_frames += 1
		max_shark = maxf(max_shark, sd)
		max_rider = maxf(max_rider, rd)
		if _hit_frame >= 0 and int(s.f) >= _hit_frame:
			var gy := float(s.game_y)
			peak_y = maxf(peak_y, gy)
			if gy > 0.001:
				air_frames += 1
			elif air_frames > 0 and landed_frame < 0:
				landed_frame = int(s.f)
			if int(s.f) == _hit_frame and s.root != null:
				start_root = _vec(s.root)
			if s.root != null:
				end_root = _vec(s.root)
	return {
		"hit_frame": _hit_frame,
		"nose_pass_frame": _nose_pass_frame,
		"shark_overlap_frames": shark_frames,
		"shark_overlap_first_rel_hit": first_shark - _hit_frame if first_shark >= 0 and _hit_frame >= 0 else null,
		"shark_overlap_last_rel_hit": last_shark - _hit_frame if last_shark >= 0 and _hit_frame >= 0 else null,
		"shark_max_depth_m": snappedf(max_shark, 0.001),
		"shark_overlap_parts": parts_hit.keys(),
		"rider_overlap_frames": rider_frames,
		"rider_max_depth_m": snappedf(max_rider, 0.001),
		"peak_game_y_m": snappedf(peak_y, 0.001),
		"air_seconds": snappedf(float(air_frames) / 60.0, 0.001),
		"landed_rel_hit": landed_frame - _hit_frame if landed_frame >= 0 else null,
		"horizontal_travel_m": snappedf(Vector2(end_root.x - start_root.x, end_root.z - start_root.z).length(), 0.01),
		"ghost_hit_phase_first_rel_hit": phase_first,
		"control_back_rel_hit": control_back,
		"min_upright": snappedf(min_upright, 0.001),
		"recovery": {"tumble": _hit_info.get("tumble"), "roll": _hit_info.get("roll"), "control_lock": _hit_info.get("control_lock")},
	}


# ---------------------------------------------------------------- サメの形

func _shark_frame() -> Transform3D:
	var t: Transform3D = ghost._shark.global_transform
	return Transform3D(t.basis.orthonormalized(), t.origin)


func _shark_body_meshes() -> Array[MeshInstance3D]:
	var shark: Node3D = ghost._shark
	var rider: Node3D = ghost._rider
	var found: Array[MeshInstance3D] = []
	var listing: Array[String] = []
	for node in shark.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if rider != null and (mi == rider or rider.is_ancestor_of(mi)):
			continue
		listing.append("%s skin=%s visible=%s aabb=%s" % [mi.name, mi.skin != null, mi.is_visible_in_tree(), mi.get_aabb().size])
		if mi.skin != null and mi.is_visible_in_tree():
			found.append(mi)
	print("GHOST_HIT_CAPTURE shark meshes: ", listing)
	return found


## スキニングに使う頂点・骨・重み（重いので最大 MAX_PROFILE_VERTICES 点に間引く）
func _prepare_skin_data() -> void:
	_skin_data.clear()
	var total := 0
	for mi in _shark_body_meshes():
		for s in range(mi.mesh.get_surface_count()):
			total += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var step := maxi(1, ceili(float(total) / float(MAX_PROFILE_VERTICES)))
	for mi in _shark_body_meshes():
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin := mi.skin
		var bind_bones := PackedInt32Array()
		var bind_poses: Array[Transform3D] = []
		if skeleton != null and skin != null:
			for j in range(skin.get_bind_count()):
				var bone := skin.get_bind_bone(j)
				if bone < 0:
					bone = skeleton.find_bone(skin.get_bind_name(j))
				bind_bones.append(bone)
				bind_poses.append(skin.get_bind_pose(j))
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := 0
			if bones != null and weights != null and verts.size() > 0:
				stride = int((bones as Array).size() / verts.size()) if bones is Array else int(bones.size() / verts.size())
			var keep_v := PackedVector3Array()
			var keep_b := PackedInt32Array()
			var keep_w := PackedFloat32Array()
			for i in range(0, verts.size(), step):
				keep_v.append(verts[i])
				for k in range(stride):
					keep_b.append(int(bones[i * stride + k]))
					keep_w.append(float(weights[i * stride + k]))
			_skin_data.append({
				"mi": mi, "skeleton": skeleton, "verts": keep_v, "bones": keep_b, "weights": keep_w,
				"stride": stride, "bind_bones": bind_bones, "bind_poses": bind_poses,
			})
	print("GHOST_HIT_CAPTURE skin data: total=%d step=%d sets=%d" % [total, step, _skin_data.size()])


## 今の姿勢のサメの頂点（サメの向きの空間、単位 m）
func _posed_shark_points(frame_inv: Transform3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for d: Dictionary in _skin_data:
		var mi := d.mi as MeshInstance3D
		var skeleton := d.skeleton as Skeleton3D
		var verts: PackedVector3Array = d.verts
		var stride := int(d.stride)
		var bind_bones: PackedInt32Array = d.bind_bones
		if skeleton == null or stride == 0 or bind_bones.is_empty():
			var to_frame_rest := frame_inv * mi.global_transform
			for v in verts:
				pts.append(to_frame_rest * v)
			continue
		var to_frame := frame_inv * skeleton.global_transform
		var bind_poses: Array[Transform3D] = d.bind_poses
		var mats: Array[Transform3D] = []
		for j in range(bind_bones.size()):
			var bone := bind_bones[j]
			mats.append(to_frame * (skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY) * bind_poses[j])
		var bones: PackedInt32Array = d.bones
		var weights: PackedFloat32Array = d.weights
		for i in range(verts.size()):
			var acc := Vector3.ZERO
			var wsum := 0.0
			for k in range(stride):
				var w := weights[i * stride + k]
				if w <= 0.0:
					continue
				var b := bones[i * stride + k]
				if b < 0 or b >= mats.size():
					continue
				acc += mats[b] * verts[i] * w
				wsum += w
			pts.append(acc / wsum if wsum > 0.0 else to_frame * verts[i])
	return pts


## 長さの軸に沿って SLABS 枚に切り、それぞれの断面を楕円（中心・半径 = 92% の点が入る距離）にする。
func _profile_from(points: PackedVector3Array) -> Dictionary:
	var b := (_axis + 1) % 3
	var c := (_axis + 2) % 3
	var umin := INF
	var umax := -INF
	for p in points:
		var u := _axis_sign * p[_axis]
		umin = minf(umin, u)
		umax = maxf(umax, u)
	var buckets: Array = []
	buckets.resize(SLABS)
	for k in range(SLABS):
		buckets[k] = PackedVector2Array()
	var span := maxf(umax - umin, 0.001)
	for p in points:
		var k := clampi(int((_axis_sign * p[_axis] - umin) / span * SLABS), 0, SLABS - 1)
		var bucket: PackedVector2Array = buckets[k]
		bucket.append(Vector2(p[b], p[c]))
		buckets[k] = bucket
	var centers := PackedVector2Array()
	var semis := PackedVector2Array()
	var full_min := Vector2(INF, INF)
	var full_max := Vector2(-INF, -INF)
	for k in range(SLABS):
		var bucket: PackedVector2Array = buckets[k]
		if bucket.is_empty():
			centers.append(Vector2.ZERO)
			semis.append(Vector2.ZERO)
			continue
		var mean := Vector2.ZERO
		for q in bucket:
			mean += q
			full_min = full_min.min(q)
			full_max = full_max.max(q)
		mean /= float(bucket.size())
		var db: Array[float] = []
		var dc: Array[float] = []
		for q in bucket:
			db.append(absf(q.x - mean.x))
			dc.append(absf(q.y - mean.y))
		db.sort()
		dc.sort()
		var idx := int(float(bucket.size() - 1) * SLAB_PERCENTILE)
		centers.append(mean)
		semis.append(Vector2(maxf(db[idx], 0.01), maxf(dc[idx], 0.01)))
	return {"umin": umin, "umax": umax, "centers": centers, "semis": semis, "b": b, "c": c, "full_min": full_min, "full_max": full_max}


func _shark_depth(profile: Dictionary, local: Vector3) -> float:
	var umin := float(profile.umin)
	var umax := float(profile.umax)
	var u := _axis_sign * local[_axis]
	if u < umin or u > umax:
		return 0.0
	var k := clampi(int((u - umin) / maxf(umax - umin, 0.001) * SLABS), 0, SLABS - 1)
	var semi: Vector2 = (profile.semis as PackedVector2Array)[k]
	if semi.x <= 0.0 or semi.y <= 0.0:
		return 0.0
	var center: Vector2 = (profile.centers as PackedVector2Array)[k]
	var dx := (local[int(profile.b)] - center.x) / semi.x
	var dy := (local[int(profile.c)] - center.y) / semi.y
	var r := sqrt(dx * dx + dy * dy)
	if r >= 1.0:
		return 0.0
	return (1.0 - r) * minf(semi.x, semi.y)


## 照準中（ホバー）のサメと乗り手の寸法。鼻先は get_ocean_attack_head_position（判定・演出が使う点）。
func _measure_dims() -> void:
	var shark: Node3D = ghost._shark
	var frame := _shark_frame()
	var frame_inv := frame.affine_inverse()
	var nose_local: Vector3 = frame_inv * shark.get_ocean_attack_head_position()
	_axis = 0
	for i in range(1, 3):
		if absf(nose_local[i]) > absf(nose_local[_axis]):
			_axis = i
	_axis_sign = signf(nose_local[_axis])
	var posed := _profile_from(_posed_shark_points(frame_inv))
	var rest_points := PackedVector3Array()
	for d: Dictionary in _skin_data:
		var to_frame_rest := frame_inv * (d.mi as MeshInstance3D).global_transform
		for v: Vector3 in d.verts:
			rest_points.append(to_frame_rest * v)
	var rest := _profile_from(rest_points)
	var axes := [frame.basis.x, frame.basis.y, frame.basis.z]
	var b := int(posed.b)
	var c := int(posed.c)
	var up_axis := b if absf((axes[b] as Vector3).y) >= absf((axes[c] as Vector3).y) else c
	var side_axis := c if up_axis == b else b
	var max_semi := Vector2.ZERO
	for semi: Vector2 in posed.semis:
		max_semi = max_semi.max(semi)
	var up_index := 0 if up_axis == b else 1
	var full_min: Vector2 = posed.full_min
	var full_max: Vector2 = posed.full_max
	# 乗り手の箱（サメの向きの空間）
	var rider_up_max := -INF
	var rider_u_min := INF
	var rider_u_max := -INF
	var rider_world_top := -INF
	for rm in _rider_meshes():
		for p in _box_points(rm):
			var l := frame_inv * p
			rider_up_max = maxf(rider_up_max, l[up_axis])
			rider_u_min = minf(rider_u_min, _axis_sign * l[_axis])
			rider_u_max = maxf(rider_u_max, _axis_sign * l[_axis])
			rider_world_top = maxf(rider_world_top, p.y)
	var survivor_top := -INF
	var survivor_bottom := INF
	for mi in _survivor_meshes():
		for p in _box_points(mi):
			survivor_top = maxf(survivor_top, p.y)
			survivor_bottom = minf(survivor_bottom, p.y)
	_dims = {
		"shark_scale": _v(shark.global_transform.basis.get_scale()),
		"length_axis": "xyz"[_axis] + ("+" if _axis_sign > 0.0 else "-"),
		"up_axis": "xyz"[up_axis],
		"nose_offset_m": snappedf(_axis_sign * nose_local[_axis], 0.001),
		"nose_up_m": snappedf(nose_local[up_axis], 0.001),
		"mesh_front_m": snappedf(float(posed.umax), 0.001),
		"mesh_back_m": snappedf(float(posed.umin), 0.001),
		"length_m": snappedf(float(posed.umax) - float(posed.umin), 0.001),
		"rest_front_m": snappedf(float(rest.umax), 0.001),
		"rest_back_m": snappedf(float(rest.umin), 0.001),
		"body_width_92_m": snappedf((max_semi.y if up_index == 0 else max_semi.x) * 2.0, 0.001),
		"body_height_92_m": snappedf((max_semi.x if up_index == 0 else max_semi.y) * 2.0, 0.001),
		"full_side_extent_m": [snappedf(full_min[1 - up_index], 0.001), snappedf(full_max[1 - up_index], 0.001)],
		"full_up_extent_m": [snappedf(full_min[up_index], 0.001), snappedf(full_max[up_index], 0.001)],
		"side_axis": "xyz"[side_axis],
		"rider_top_above_shark_origin_m": snappedf(rider_up_max, 0.001),
		"rider_along_m": [snappedf(rider_u_min, 0.001), snappedf(rider_u_max, 0.001)],
		"rider_world_top_minus_shark_y_m": snappedf(rider_world_top - shark.global_position.y, 0.001),
		"survivor_height_m": snappedf(survivor_top - survivor_bottom, 0.001),
		"survivor_bottom_y": snappedf(survivor_bottom, 0.001),
		"shark_y": snappedf(shark.global_position.y, 0.001),
		"profile_local": _body_profile_local(),
	}


## サメの胴（SK_Shark_001 だけ、静止姿勢）の断面を、サメのノードのローカル単位で鼻先から後ろへ 0.4 ずつ。
## [鼻先からの距離, 断面の中心の上下, 横の半径, 上下の半径]（各断面の 95% の点が入る楕円）。GhostHitContact.PROFILE と比べる。
func _body_profile_local() -> Array:
	var shark: Node3D = ghost._shark
	var to_local := shark.global_transform.affine_inverse()
	# 低ポリゴンで頂点がまばらなので、三角形の面の上を細かく取る（1 辺 0.08 ほどの間隔）。
	var points := PackedVector3Array()
	for node in shark.find_children("SK_Shark*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := to_local * mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i in range(verts.size()):
					indices.append(i)
			for t in range(0, indices.size() - 2, 3):
				var a := xf * verts[indices[t]]
				var b := xf * verts[indices[t + 1]]
				var c := xf * verts[indices[t + 2]]
				var n := clampi(ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / 0.08), 1, 60)
				for i in range(n + 1):
					for j in range(n + 1 - i):
						var u := float(i) / float(n)
						var v := float(j) / float(n)
						points.append(a + (b - a) * u + (c - a) * v)
	if points.is_empty():
		return []
	var front := -INF
	for p in points:
		front = maxf(front, -p.z)
	var step := 0.4
	var count := ceili((front - _min_forward(points)) / step)
	var side_lists: Array = []
	var up_min := PackedFloat32Array()
	var up_max := PackedFloat32Array()
	for k in range(count):
		side_lists.append([])
		up_min.append(INF)
		up_max.append(-INF)
	for p in points:
		var k := clampi(int((front - (-p.z)) / step), 0, count - 1)
		(side_lists[k] as Array).append(absf(p.x))
		up_min[k] = minf(up_min[k], p.y)
		up_max[k] = maxf(up_max[k], p.y)
	var rows: Array = []
	for k in range(count):
		var side: Array = side_lists[k]
		if side.is_empty():
			continue
		side.sort()
		var idx := int(float(side.size() - 1) * 0.97)
		rows.append([
			snappedf(step * k, 0.01),
			snappedf((up_min[k] + up_max[k]) * 0.5, 0.001),
			snappedf(float(side[idx]), 0.001),
			snappedf((up_max[k] - up_min[k]) * 0.5, 0.001),
		])
	return [snappedf(front, 0.001), rows]


static func _min_forward(points: PackedVector3Array) -> float:
	var lowest := INF
	for p in points:
		lowest = minf(lowest, -p.z)
	return lowest


# ---------------------------------------------------------------- 体の箱

func _survivor_root() -> Node3D:
	return player.get("p2_container") as Node3D


## 見えている胴の上向きと、世界の上向きの内積（1 = 立っている、0 = 横倒し、−1 = 逆さ）。
func _upright() -> float:
	var bodies: Array = player.get_ghost_hit_bodies(2)
	for body: Variant in bodies:
		if (body as Node).name == "TorsoBody":
			return snappedf((body as Node3D).global_basis.y.normalized().y, 0.001)
	var pelvis := (player.get("p2_parts") as Dictionary).get("pelvis") as Node3D
	return snappedf(pelvis.global_basis.y.normalized().y, 0.001) if pelvis != null else 1.0


## 見えている体の箱。被弾のラグドール中（PlayerController.get_ghost_hit_bodies）は、ラグドールの体の箱。
func _survivor_meshes() -> Array[MeshInstance3D]:
	var list: Array[MeshInstance3D] = []
	var bodies: Array = player.get_ghost_hit_bodies(2)
	if not bodies.is_empty():
		for body: Variant in bodies:
			for child in (body as Node).get_children():
				var bm := child as MeshInstance3D
				if bm != null and bm.mesh != null and bm.is_visible_in_tree():
					list.append(bm)
		return list
	var parts: Dictionary = player.get("p2_parts")
	for m: Variant in parts.get("meshes", []):
		var mi := m as MeshInstance3D
		if mi != null and is_instance_valid(mi) and mi.mesh != null and mi.is_visible_in_tree():
			list.append(mi)
	return list


func _rider_meshes() -> Array[MeshInstance3D]:
	var list: Array[MeshInstance3D] = []
	var rider: Node3D = ghost._rider
	if rider == null or not is_instance_valid(rider) or not rider.has_meta("ghost_mount_parts"):
		return list
	var parts: Dictionary = rider.get_meta("ghost_mount_parts")
	for m: Variant in parts.get("meshes", []):
		var mi := m as MeshInstance3D
		if mi != null and is_instance_valid(mi) and mi.mesh != null and mi.is_visible_in_tree():
			list.append(mi)
	return list


static func _box_points(mi: MeshInstance3D) -> PackedVector3Array:
	var box := mi.get_aabb()
	var xf := mi.global_transform
	var pts := PackedVector3Array()
	for ix in range(3):
		for iy in range(3):
			for iz in range(3):
				pts.append(xf * (box.position + box.size * Vector3(ix * 0.5, iy * 0.5, iz * 0.5)))
	return pts


static func _box_depth_local(box: AABB, scale: Vector3, l: Vector3) -> float:
	if l.x < box.position.x or l.y < box.position.y or l.z < box.position.z:
		return 0.0
	if l.x > box.end.x or l.y > box.end.y or l.z > box.end.z:
		return 0.0
	var d := INF
	for i in range(3):
		d = minf(d, (l[i] - box.position[i]) * scale[i])
		d = minf(d, (box.end[i] - l[i]) * scale[i])
	return d


## 部品の名前（p2_parts のキーのうち、この箱にいちばん近い親。ラグドールの箱は体の名前）
func _part_name(mi: MeshInstance3D) -> String:
	var body := mi.get_parent() as RigidBody3D
	if body != null:
		return "rag:" + str(body.name).trim_prefix("RB_")
	var parts: Dictionary = player.get("p2_parts")
	var best := ""
	var best_depth := -1
	for key: Variant in parts:
		var value: Variant = parts[key]
		if not (value is Node3D) or not is_instance_valid(value):
			continue
		var node := value as Node3D
		if node == mi or node.is_ancestor_of(mi):
			var depth := node.get_path().get_name_count()
			if depth > best_depth:
				best_depth = depth
				best = str(key)
	return best if best != "" else str(mi.name)


# ---------------------------------------------------------------- カメラと保存

func _build_views() -> void:
	if not save_images:
		return
	for view_name: String in ["side", "front", "chase", "follow"]:
		var vp := SubViewport.new()
		vp.name = "CaptureView_" + view_name
		vp.size = VIEW_SIZE
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.world_3d = get_tree().root.world_3d
		vp.msaa_3d = Viewport.MSAA_4X
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 60.0 if view_name == "chase" else (50.0 if view_name == "follow" else 45.0)
		cam.near = 0.05
		cam.far = 500.0
		vp.add_child(cam)
		cam.current = true
		var main_camera := get_viewport().get_camera_3d()
		if main_camera != null:
			cam.cull_mask = main_camera.cull_mask
			cam.environment = main_camera.environment
			cam.attributes = main_camera.attributes
		_views[view_name] = {"viewport": vp, "camera": cam}


func _place_cameras() -> void:
	var locked: Vector3 = ghost._locked_direction
	var flat := Vector3(locked.x, 0.0, locked.z)
	if flat.length_squared() < 0.0001:
		return
	_dir = flat.normalized()
	_perp = Vector3.UP.cross(_dir).normalized()
	var root := _survivor_root()
	_hit_center = (root.global_position if root != null else Vector3.ZERO) + Vector3.UP * 0.9
	var main_camera := get_viewport().get_camera_3d()
	if main_camera != null and (main_camera.global_position - _hit_center).dot(_perp) < 0.0:
		_perp = -_perp
	if _views.is_empty():
		return
	var side := _views.side.camera as Camera3D
	side.global_position = _hit_center + _perp * 7.5 + Vector3.UP * 0.4
	side.look_at(_hit_center + _dir * 2.0, Vector3.UP)
	var front := _views.front.camera as Camera3D
	front.global_position = _hit_center + _dir * 11.0 + _perp * 5.0 + Vector3.UP * 2.2
	front.look_at(_hit_center + _dir * 3.0, Vector3.UP)
	_update_chase_camera()
	_update_follow_camera()


## 体を横から追う（着地・転がり・起き上がりを撮る。段階 4）。見えている胴（ラグドールなら胴の体）を真ん中に置く。
func _update_follow_camera() -> void:
	if _views.is_empty() or not _views.has("follow"):
		return
	var cam := _views.follow.camera as Camera3D
	var target := Vector3.ZERO
	var found := false
	for body: Variant in player.get_ghost_hit_bodies(2):
		if (body as Node).name == "TorsoBody":
			target = (body as Node3D).global_position
			found = true
	if not found:
		var pelvis := (player.get("p2_parts") as Dictionary).get("pelvis") as Node3D
		if pelvis == null:
			return
		target = pelvis.global_position
	target.y = maxf(target.y, StageConstants.FLOOR_TOP_Y + 0.6)
	cam.global_position = target + _perp * 6.5 - _dir * 1.5 + Vector3.UP * 1.4
	cam.look_at(target, Vector3.UP)


func _update_chase_camera() -> void:
	if _views.is_empty():
		return
	var cam := _views.chase.camera as Camera3D
	var shark: Node3D = ghost._shark
	var parts: Dictionary = player.get("p2_parts")
	var pelvis := parts.get("pelvis") as Node3D
	if _hit_frame >= 0 and _frame > _hit_frame + 4:
		if not _chase_held:
			_chase_held = true
			_chase_hold = cam.global_position
		cam.global_position = _chase_hold
		if pelvis != null:
			cam.look_at(pelvis.global_position, Vector3.UP)
		return
	if shark == null:
		return
	var locked: Vector3 = ghost._locked_direction
	var dir3 := locked.normalized() if locked.length_squared() > 0.0001 else _dir
	cam.global_position = shark.global_position - dir3 * 5.5 + Vector3.UP * 1.6
	cam.look_at(shark.global_position + dir3 * 4.0, Vector3.UP)


func _save(rel: int) -> void:
	await RenderingServer.frame_post_draw
	var main_image := get_viewport().get_texture().get_image()
	if main_image != null:
		main_image.save_jpg(out + "main_%04d.jpg" % rel, 0.88)
	for view_name: String in _views:
		var vp := _views[view_name].viewport as SubViewport
		var image := vp.get_texture().get_image()
		if image != null:
			image.save_jpg(out + "%s_%04d.jpg" % [view_name, rel], 0.9)


# ---------------------------------------------------------------- 小物

static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
