extends Node

## 1Pでうしろのコンベア端へ寄ると、2Pのチップソー接近と同じようにカメラが水平に下がり、
## 端のローラーと体が画面に収まることを確かめる。離れると元へ戻り、2P・ゲームオーバーでは動かない。
## 実行：Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/solo_rear_edge_camera_bootstrap.gd
##   -- natural          本番どおり進めて何もしない（壁とコンベアで端へ運ばれる）
##   -- natural walkback S を押し続けてうしろの端から落ちる
const OUT := "res://artifacts/solo_rear_edge_camera/"
const CameraControllerScript := preload("res://scripts/world/camera_controller.gd")
var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	gs.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var world := get_tree().current_scene
	var deadline := Time.get_ticks_msec() + 45000
	while (SceneTransition.is_transitioning() or world.is_start_presentation_locked()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(Time.get_ticks_msec() < deadline, "startup completes")
	if "natural" in OS.get_cmdline_user_args():
		await run_natural(world, gs)
		return
	world.set_process(false)
	var cc: Node3D = world.camera_controller
	var camera: Camera3D = cc.camera
	gs.game_state = Constants.STATE_PLAYING
	gs.camera_shake = 0.0
	gs.player_y = 0.0
	gs.player_x = 1.2
	gs.p1_alive = true
	gs.p1_fall_committed = false
	gs.p1_waiting_for_shark = false
	for wall_distance: float in [8.0, 16.8]:
		for fps: int in [30, 60, 120]:
			await run_approach(world, gs, cc, camera, wall_distance, fps)
	await run_exclusions(world, gs, cc)
	var report := {"passed": failures.is_empty(), "failures": failures, "samples": samples}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SOLO_REAR_EDGE_CAMERA ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


## 本番どおりに進め、何も操作しないで壁とコンベアにうしろの端まで運ばれて落ちるまでを記録する。
## 引きは端へ近づくほど増え、1フレームの動きは速さの上限を超えず、落ちてから海のカメラへ移るまでカメラが跳ねない。
func run_natural(world: Node, gs: QuizGameState) -> void:
	var cc: Node3D = world.camera_controller
	var camera: Camera3D = cc.camera
	var deadline := Time.get_ticks_msec() + 60000
	var started := false
	while gs.game_state != Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not started and gs.game_state == Constants.STATE_WAITING_START and not world.is_start_presentation_locked():
			started = true
			gs.trigger_start()
	check(gs.game_state == Constants.STATE_PLAYING, "natural: play starts (stuck in %s)" % gs.game_state)
	var frames: Array[Dictionary] = []
	var max_back := 0.0
	var max_back_step := 0.0
	var max_eye_step := 0.0
	var shots := {"2.0": false, "0.6": false, "fall": false}
	# walkback：S を押し続けて自分からうしろの端を越え、落ちる（壁に当たって先にゲームオーバーにならないように）。
	var walk_back := "walkback" in OS.get_cmdline_user_args()
	var play_frames := 0
	var back_at_fall := -1.0
	var max_back_while_falling := 0.0
	var max_fall_eye_step := 0.0
	var previous_eye := camera.global_position
	var previous_back: float = cc._solo_rear_back
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var dt := get_process_delta_time()
		play_frames += 1
		if walk_back and play_frames == 60:
			var key := InputEventKey.new()
			key.keycode = KEY_S
			key.physical_keycode = KEY_S
			key.pressed = true
			Input.parse_input_event(key)
		var clearance: float = gs.player_local_z - StageConstants.FLOOR_BACK_Z
		var back: float = cc._solo_rear_back
		var eye := camera.global_position
		var main_camera := gs.game_state == Constants.STATE_PLAYING and gs.p1_alive and not gs.p1_waiting_for_shark
		# The first frames after the barrier breaks belong to the start blend, not to this retreat.
		if main_camera and play_frames > 30:
			max_back = maxf(max_back, back)
			max_back_step = maxf(max_back_step, absf(back - previous_back) / maxf(dt, 0.0001))
			max_eye_step = maxf(max_eye_step, eye.distance_to(previous_eye))
			if gs.p1_fall_committed:
				if back_at_fall < 0.0:
					back_at_fall = previous_back
				max_back_while_falling = maxf(max_back_while_falling, back)
				max_fall_eye_step = maxf(max_fall_eye_step, eye.distance_to(previous_eye))
		frames.append({"clearance": snappedf(clearance, 0.001), "back": snappedf(back, 0.001), "question_back": snappedf(cc._question_back, 0.001), "state": gs.game_state, "fall": gs.p1_fall_committed, "shark": gs.p1_waiting_for_shark, "eye": str(eye)})
		for key: String in ["2.0", "0.6"]:
			if not shots[key] and main_camera and not gs.p1_fall_committed and clearance <= float(key):
				shots[key] = true
				get_viewport().get_texture().get_image().save_png(OUT + "natural_clearance_%s.png" % key)
		if not shots["fall"] and gs.p1_fall_committed and gs.player_y < -0.6:
			shots["fall"] = true
			get_viewport().get_texture().get_image().save_png(OUT + "natural_fall.png")
		previous_eye = eye
		previous_back = back
		if gs.p1_waiting_for_shark or gs.game_state == Constants.STATE_GAME_OVER:
			break
	if walk_back:
		var key := InputEventKey.new()
		key.keycode = KEY_S
		key.physical_keycode = KEY_S
		key.pressed = false
		Input.parse_input_event(key)
		check(shots["0.6"], "natural: reached the rear edge")
		check(shots["fall"], "natural: fell off the rear edge")
		check(back_at_fall > 0.5, "natural: retreat in place when the fall starts")
		# The eye itself still follows the falling body (and the question framing fits it); this retreat only holds.
		check(max_back_while_falling <= back_at_fall + 0.001, "natural: no extra retreat while falling")
	else:
		check(shots["2.0"], "natural: carried toward the rear edge")
	check(max_back > 1.0, "natural: camera backed off near the edge")
	check(max_back_step <= 10.001, "natural: bounded retreat speed")
	var report := {
		"passed": failures.is_empty(),
		"failures": failures,
		"walk_back": walk_back,
		"max_back": max_back,
		"max_back_speed": max_back_step,
		"max_eye_step": max_eye_step,
		"back_at_fall": back_at_fall,
		"max_back_while_falling": max_back_while_falling,
		"max_fall_eye_step": max_fall_eye_step,
		"shots": shots,
		"frames": frames.size(),
	}
	FileAccess.open(OUT + "natural_frames.json", FileAccess.WRITE).store_string(JSON.stringify(frames, "\t"))
	FileAccess.open(OUT + "natural_report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SOLO_REAR_EDGE_NATURAL ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


func set_clearance(gs: QuizGameState, clearance: float) -> void:
	gs.player_z = gs.world_scroll_z + StageConstants.FLOOR_BACK_Z + clearance


func edge_points(gs: QuizGameState) -> PackedVector3Array:
	var points := PackedVector3Array()
	var r := StageConstants.CONVEYOR_ROLLER_RADIUS
	var half := CameraControllerScript.SOLO_REAR_EDGE_FRAMING_HALF_WIDTH
	var edge := AABB(
		Vector3(gs.player_x - half, StageConstants.FLOOR_TOP_Y - r * 2.0, StageConstants.FLOOR_BACK_Z - r),
		Vector3(half * 2.0, r * 2.0, r)
	)
	for corner: int in range(8):
		points.append(edge.get_endpoint(corner))
	return points


func points_in_frame(camera: Camera3D, points: PackedVector3Array, margin: float) -> bool:
	var size := camera.get_viewport().get_visible_rect().size
	for point: Vector3 in points:
		if camera.is_position_behind(point):
			return false
		var uv := camera.unproject_position(point) / size
		if uv.x < margin or uv.x > 1.0 - margin or uv.y < margin or uv.y > 1.0 - margin:
			return false
	return true


func run_approach(world: Node, gs: QuizGameState, cc: Node3D, camera: Camera3D, wall_distance: float, fps: int) -> void:
	var label := "%s/%s" % [wall_distance, fps]
	var dt := 1.0 / fps
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = gs.wall_z - wall_distance
	set_clearance(gs, 4.5)
	# The world's _process is off; lay the floor out as play does (its back roller at FLOOR_BACK_Z).
	world._update_floor()
	world._update_walls()
	world._update_wall_question()
	cc._solo_rear_back = 0.0
	cc._question_pitch = 0.0
	cc._question_back = 0.0
	for i in range(fps * 2):
		world._update_camera(dt)
	check(is_zero_approx(cc._solo_rear_back), "no retreat at the start position " + label)
	# Without the retreat the rear roller under the player is off screen.
	set_clearance(gs, 0.3)
	var held: float = cc._solo_rear_back
	world._update_camera(0.0)
	var edge_visible_without := points_in_frame(camera, edge_points(gs), 0.0)
	cc._solo_rear_back = held
	# Walk back at 1.5 m/s from 4.5 m to 0.3 m, then hold at the edge.
	var maximum_speed := 0.0
	var max_height_difference := 0.0
	var onset_clearance := -1.0
	for i in range(fps * 5):
		var clearance := maxf(0.3, 4.5 - float(i) / fps * 1.5)
		set_clearance(gs, clearance)
		var before: float = cc._solo_rear_back
		world._update_camera(dt)
		var back: float = cc._solo_rear_back
		if clearance >= CameraControllerScript.SOLO_REAR_EDGE_FRAMING_START_DISTANCE:
			check(is_zero_approx(back), "no early retreat " + label)
		elif onset_clearance < 0.0 and back > 0.000001:
			onset_clearance = clearance
		maximum_speed = maxf(maximum_speed, absf(back - before) * fps)
		# The pose with the retreat removed (dt = 0 leaves every other follower as is) has the same height.
		var actual := camera.global_position
		cc._solo_rear_back = 0.0
		world._update_camera(0.0)
		max_height_difference = maxf(max_height_difference, absf(actual.y - camera.global_position.y))
		cc._solo_rear_back = back
		world._update_camera(0.0)
	var full_back: float = cc._solo_rear_back
	var player_points := PackedVector3Array()
	cc._append_player_framing_points(player_points, Vector3(gs.player_x, gs.player_y, gs.player_local_z))
	var edge_in := points_in_frame(camera, edge_points(gs), 0.075)
	var player_in := points_in_frame(camera, player_points, 0.075)
	check(maximum_speed <= 10.001, "bounded retreat speed " + label)
	check(onset_clearance > 3.3 and onset_clearance < 3.5, "retreat begins just inside 3.5 m " + label)
	check(max_height_difference < 0.001, "retreat is horizontal " + label)
	check(full_back > 1.0, "camera backs off at the edge " + label)
	check(edge_in, "rear roller in frame " + label)
	check(player_in, "player in frame " + label)
	if fps == 60:
		world._update_player(0.0)
		var roller: Node3D = world.stage_env._conveyor_roller_back
		check(roller != null and roller.global_position.is_equal_approx(Vector3(0.0, StageConstants.FLOOR_TOP_Y - StageConstants.CONVEYOR_ROLLER_RADIUS, StageConstants.FLOOR_BACK_Z)), "visual back roller sits at FLOOR_BACK_Z")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "edge_after_%s.png" % wall_distance)
		cc._solo_rear_back = 0.0
		world._update_camera(0.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "edge_before_%s.png" % wall_distance)
		cc._solo_rear_back = full_back
		world._update_camera(0.0)
	# Walking away releases the retreat smoothly.
	set_clearance(gs, 4.5)
	var release_speed := 0.0
	for i in range(fps * 5):
		var before: float = cc._solo_rear_back
		world._update_camera(dt)
		release_speed = maxf(release_speed, absf(cc._solo_rear_back - before) * fps)
	check(cc._solo_rear_back < 0.001, "retreat released away from the edge " + label)
	check(release_speed <= 10.001, "bounded release speed " + label)
	samples.append({
		"wall_distance": wall_distance,
		"fps": fps,
		"onset_clearance": onset_clearance,
		"full_back": full_back,
		"max_speed": maximum_speed,
		"height_change": max_height_difference,
		"edge_visible_without_retreat": edge_visible_without,
		"edge_in_frame": edge_in,
		"player_in_frame": player_in,
	})


func run_exclusions(world: Node, gs: QuizGameState, cc: Node3D) -> void:
	var dt := 1.0 / 60.0
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = gs.wall_z - 16.8
	set_clearance(gs, 0.3)
	cc._solo_rear_back = 0.0
	for i in range(120):
		world._update_camera(dt)
	var held: float = cc._solo_rear_back
	check(held > 1.0, "edge retreat reached before the fall")
	# Past the edge and falling: hold the retreat instead of chasing the falling body.
	gs.p1_fall_committed = true
	set_clearance(gs, -0.8)
	for i in range(30):
		gs.player_y = -float(i) * 0.1
		world._update_camera(dt)
		check(cc._solo_rear_back <= held + 0.001, "no extra retreat while falling")
	check(absf(cc._solo_rear_back - held) < 0.001, "retreat held while falling")
	gs.p1_fall_committed = false
	gs.player_y = 0.0
	set_clearance(gs, 0.3)
	gs.game_state = Constants.STATE_GAME_OVER
	world._update_camera(dt)
	check(cc._solo_rear_back == 0.0, "no edge retreat during game over")
	gs.game_state = Constants.STATE_PLAYING
	gs.num_players = 2
	gs.p2_alive = true
	gs.player2_x = -1.2
	gs.player2_y = 0.0
	gs.player2_z = gs.player_z
	for i in range(60):
		world._update_camera(dt)
	check(cc._solo_rear_back == 0.0, "2P camera unaffected")
	gs.num_players = 1
