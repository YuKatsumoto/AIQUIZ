extends Node

## 2Pで片方だけが壁・のこぎりで脱落したとき、生存者のカメラへ移る前に体が爆散して破片が散るまで映すことを確かめる。
const OUT := "res://artifacts/first_death_camera/"
var failures: Array[String] = []
var cases: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label): failures.append(label)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	gs.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	while get_tree().current_scene == null: await get_tree().process_frame
	var world := get_tree().current_scene
	var deadline := Time.get_ticks_msec() + 45000
	while (SceneTransition.is_transitioning() or world.is_start_presentation_locked()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(Time.get_ticks_msec() < deadline, "startup completes")
	world.set_process(false)
	for spec: Array in [[1, false], [2, false], [1, true]]:
		await run_case(world, int(spec[0]), bool(spec[1]))
	var report := {"passed": failures.is_empty(), "failures": failures, "cases": cases}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	var brief: Array = []
	for c: Dictionary in cases:
		brief.append({"label": c.label, "explosion_frame": c.explosion_frame, "returned_frame": c.returned_frame, "max_eye_step": c.max_eye_step, "worst_body_v": c.worst_body_v, "worst_burst_v": c.worst_burst_v})
	print("FIRST_DEATH_CAMERA ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "cases": brief}))
	get_tree().quit(0 if failures.is_empty() else 1)

func in_frame(camera: Camera3D, point: Vector3, margin: float) -> bool:
	if camera.is_position_behind(point): return false
	var uv := camera.unproject_position(point) / get_viewport().get_visible_rect().size
	return uv.x > margin and uv.x < 1.0 - margin and uv.y > margin and uv.y < 1.0 - margin

func screen_v(camera: Camera3D, point: Vector3) -> float:
	if camera.is_position_behind(point): return 9.0
	return camera.unproject_position(point).y / get_viewport().get_visible_rect().size.y

func run_case(world: Node, dead_player: int, saw: bool) -> void:
	var gs: QuizGameState = world.game_state
	var pc: PlayerController = world.player_node
	var cc: Node3D = world.camera_controller
	var camera: Camera3D = cc.camera
	var label := "p%d_%s" % [dead_player, "saw" if saw else "wall"]
	var survivor := 3 - dead_player
	gs.start_game()
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = gs.wall_z - 10.0
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.saw.local_z = -30.0
	world._saw_controller.update_visual(gs, 0.0)
	world._update_walls()
	world._update_player(0.0)
	for i in range(30):
		world._update_camera(1.0 / 60.0)
	await get_tree().physics_frame
	gs._set_player_hp(dead_player, 1)
	gs._apply_hp_wall_damage(dead_player)
	if saw:
		if dead_player == 1:
			gs.p1_wall_impact = false
			gs.p1_saw_killed = true
		else:
			gs.p2_wall_impact = false
			gs.p2_saw_killed = true
		gs.saw.local_z = 0.0
		world._saw_controller.update_visual(gs, 0.0)
	var captured := {}
	var samples: Array[Dictionary] = []
	var explosion_frame := -1
	var burst_point := Vector3.ZERO
	var max_jump := 0.0
	var prev_eye := camera.global_position
	var returned_frame := -1
	var travel := 0.0
	var origin := Vector3.ZERO
	var worst_body_v := 0.0
	var worst_burst_v := 0.0
	for frame in range(480):
		await get_tree().physics_frame
		if dead_player == 1: gs.game_over_timer += 1.0 / 60.0
		else: gs.player2_game_over_timer += 1.0 / 60.0
		world._update_player(1.0 / 60.0)
		# 揺れ（camera_shake）は既存の演出なので、カメラの飛びの判定から外す。
		gs.camera_shake = 0.0
		world._update_camera(1.0 / 60.0)
		world._check_particles()
		check(gs.game_state == Constants.STATE_PLAYING, label + " match keeps playing")
		var body := pc.get_death_presentation_position(dead_player == 1)
		var exploded := pc.has_player_death_exploded(dead_player)
		var survivor_pos := Vector3(
			gs.player_x if survivor == 1 else gs.player2_x,
			(gs.player_y if survivor == 1 else gs.player2_y) + 0.8,
			gs.player_local_z if survivor == 1 else gs.player2_local_z
		)
		if frame == 0: origin = body
		var eye := camera.global_position
		max_jump = maxf(max_jump, eye.distance_to(prev_eye))
		prev_eye = eye
		check(in_frame(camera, survivor_pos, 0.03), label + " survivor stays in frame")
		if not exploded:
			travel = maxf(travel, origin.distance_to(body))
			worst_body_v = maxf(worst_body_v, screen_v(camera, body))
			check(in_frame(camera, body, 0.05), label + " flying body stays in frame until burst")
		elif explosion_frame < 0:
			explosion_frame = frame
			burst_point = cc._first_death_focus
		elif frame < explosion_frame + int(cc.FIRST_DEATH_BURST_HOLD * 60.0):
			worst_burst_v = maxf(worst_burst_v, screen_v(camera, burst_point))
			check(in_frame(camera, burst_point, 0.05), label + " burst stays in frame while scattering")
		if explosion_frame >= 0 and returned_frame < 0 and cc.get_first_death_weight() <= 0.0:
			returned_frame = frame
		if frame % 15 == 0:
			samples.append({"frame": frame, "body": str(body), "eye": str(eye), "weight": cc.get_first_death_weight(), "exploded": exploded})
		var shot := ""
		if frame == 20: shot = "flight"
		if exploded and not captured.has("burst"): shot = "burst"
		if explosion_frame >= 0 and frame == explosion_frame + 40: shot = "scatter"
		if returned_frame >= 0 and not captured.has("returned"): shot = "returned"
		if not shot.is_empty():
			await RenderingServer.frame_post_draw
			var path := OUT + label + "_" + shot + ".png"
			get_viewport().get_texture().get_image().save_png(path)
			captured[shot] = path
	check(explosion_frame >= 0, label + " explosion observed")
	check(returned_frame >= 0, label + " camera returns to survivor")
	check(returned_frame < 0 or returned_frame > explosion_frame + int(cc.FIRST_DEATH_BURST_HOLD * 60.0), label + " return waits for scatter")
	check(max_jump < 0.6, label + " no camera snap")
	# 戻ったあとは、生存者だけの通常のカメラと同じ位置。
	# （のこぎりの場面はのこぎりの引きが重なるので、壁の場面だけ比べる。）
	if not saw:
		var pose: Dictionary = cc.get_gameplay_pose(gs)
		var normal_eye: Vector3 = pose.eye
		check(absf(camera.global_position.z - normal_eye.z) < 0.6, label + " final pose matches survivor camera")
	cases.append({"label": label, "worst_body_v": worst_body_v, "worst_burst_v": worst_burst_v, "explosion_frame": explosion_frame, "returned_frame": returned_frame, "max_eye_step": max_jump, "body_travel": travel, "captures": captured, "samples": samples})
