extends Node

const OUT := "res://artifacts/final_death_camera/"
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
	for spec: Array in [[1, false], [2, false], [2, true]]:
		await run_case(world, int(spec[0]), bool(spec[1]))
	# A surviving player, a fresh round, solo and ocean deaths do not inherit it.
	gs.p1_alive = true
	gs.game_state = Constants.STATE_PLAYING
	world._update_camera(1.0 / 60.0)
	check(world.camera_controller._final_death_player == 0, "retry clears physical death focus")
	gs.num_players = 1
	gs.p1_alive = false
	gs.game_state = Constants.STATE_GAME_OVER
	world._update_camera(1.0 / 60.0)
	check(world.camera_controller._final_death_player == 0, "solo behavior retained")
	gs.num_players = 2
	gs.p2_saw_killed = false
	gs.p2_wall_impact = false
	gs.p2_shark_killed = true
	world._update_camera(1.0 / 60.0)
	check(world.camera_controller._final_death_player == 0, "ocean death uses existing shark camera")
	var report := {"passed": failures.is_empty(), "failures": failures, "cases": cases}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FINAL_DEATH_CAMERA ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "cases": cases.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)

func run_case(world: Node, last_player: int, saw: bool) -> void:
	var gs: QuizGameState = world.game_state
	var pc: PlayerController = world.player_node
	var cc: Node3D = world.camera_controller
	var camera: Camera3D = cc.camera
	var label := "p%d_%s" % [last_player, "saw" if saw else "wall"]
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
	world._update_camera(0.0)
	await get_tree().physics_frame
	var first_player := 3 - last_player
	gs._set_player_hp(first_player, 1)
	gs._apply_hp_wall_damage(first_player)
	for frame in range(150):
		await get_tree().physics_frame
		if first_player == 1: gs.game_over_timer += 1.0 / 60.0
		else: gs.player2_game_over_timer += 1.0 / 60.0
		world._update_player(1.0 / 60.0)
		world._update_camera(1.0 / 60.0)
		check(cc._final_death_player == 0, label + " survivor keeps gameplay camera")
	gs._set_player_hp(last_player, 1)
	gs._apply_hp_wall_damage(last_player)
	if saw:
		gs.p2_wall_impact = false
		gs.p2_saw_killed = true
		gs.saw.local_z = 0.0
		world._saw_controller.update_visual(gs, 0.0)
	gs._game_over("Camera regression")
	var samples: Array[Dictionary] = []
	var captured := {}
	var origin := Vector3.ZERO
	var travel := 0.0
	var error := 0.0
	var saw_explosion := false
	var explosion_focus := Vector3.ZERO
	var explosion_frame := -1
	for frame in range(190):
		await get_tree().physics_frame
		gs.update(1.0 / 60.0)
		world._update_player(1.0 / 60.0)
		world._update_camera(1.0 / 60.0)
		world._check_particles()
		var position := pc.get_death_presentation_position(last_player == 1)
		var exploded := pc.has_player_death_exploded(last_player)
		if frame == 0: origin = position
		check(cc._final_death_player == last_player, label + " follows last victim")
		if not exploded:
			travel = maxf(travel, origin.distance_to(position))
			error = maxf(error, cc._final_death_focus.distance_to(position))
			var uv := camera.unproject_position(position) / get_viewport().get_visible_rect().size
			check(not camera.is_position_behind(position) and uv.x > 0.1 and uv.x < 0.9 and uv.y > 0.1 and uv.y < 0.9, label + " physical body remains in frame until burst")
		elif not saw_explosion:
			saw_explosion = true
			explosion_frame = frame
			explosion_focus = cc._final_death_focus
		else:
			check(cc._final_death_focus.is_equal_approx(explosion_focus), label + " holds burst position afterwards")
		if frame % 10 == 0:
			samples.append({"frame": frame, "body": str(position), "focus": str(cc._final_death_focus), "eye": str(camera.global_position), "exploded": exploded})
		var shot := ""
		if frame == 12: shot = "launch"
		if frame == 75: shot = "flight"
		if exploded and not captured.has("burst"): shot = "burst"
		if explosion_frame >= 0 and frame == explosion_frame + 10: shot = "scatter"
		if not shot.is_empty():
			await RenderingServer.frame_post_draw
			var path := OUT + label + "_" + shot + ".png"
			get_viewport().get_texture().get_image().save_png(path)
			captured[shot] = path
	check(error < 0.001, label + " camera tracks actual body position")
	check(travel > 0.5 if saw else travel > 3.0, label + " physical flight observed")
	check(saw_explosion, label + " explosion observed")
	cases.append({"label": label, "max_focus_error": error, "body_travel": travel, "exploded": saw_explosion, "captures": captured, "samples": samples})
