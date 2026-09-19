extends Node

const OUT := "res://artifacts/hp_system/"
var gs: QuizGameState
var world: Node3D
var pc: PlayerController
var helper: Node
var scenario := "duo"
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case="): scenario = arg.trim_prefix("case=")
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(1 if scenario == "solo" else 2, Constants.MODE_ENDLESS if scenario == "recovery" else Constants.MODE_TEN)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.health_changed.connect(func(p, old, value): events.append({"kind": "hp", "p": p, "from": old, "to": value, "t": gs.play_time}))
	gs.question_completed.connect(func(w, correct): events.append({"kind": "completed", "wall": w, "correct": correct}))
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	pc = world.get_node("Player") as PlayerController
	pc.prepare_for_loading(gs)
	await frames(60)
	if scenario == "replay":
		var recording := ReplayRecorder.new()
		gs.play_time = 0.0
		recording.start_recording(gs)
		recording.capture(gs)
		helper.answer(gs, false, true)
		gs._tick_health(0.175)
		gs.play_time = 1.0
		recording.capture(gs)
		world.set("_replay_mode", true)
		gs.is_replay = true
		var replay := ReplayPlayer.new()
		replay.setup(recording)
		replay.current_time = 1.0
		replay.apply_to_game_state(gs)
		await frames(5)
		await capture("replay_damage")
		check(gs.p1_hp == 2 and is_equal_approx(gs.p1_damage_time, 0.425), "replay restores visible HP/recoil")
		check(not pc.get("_health_pose_restore").is_empty(), "replay recoil rendered")
		var legacy := JSON.parse_string(recording.export_for_sharing()) as Dictionary
		var legacy_frames := PackedFloat32Array()
		for f in range(2):
			for field in range(24): legacy_frames.append(recording.frames[f * 28 + field])
		legacy.meta.version = 2
		legacy.meta.erase("hp_enabled")
		legacy.fields_per_frame = 24
		legacy.frames_base64 = Marshalls.raw_to_base64(legacy_frames.to_byte_array())
		var old := ReplayRecorder.new()
		check(old.import_from_string(JSON.stringify(legacy)), "old replay loads")
		replay.setup(old)
		replay.current_time = 1.0
		replay.apply_to_game_state(gs)
		await frames(5)
		await capture("replay_legacy")
		check(not world.get_node("GameplayHUD/PlayerHealthHUD").visible and pc.get("_health_pose_restore").is_empty(), "legacy replay hides HP and damage pose")
	elif scenario == "recovery":
		gs.hp_questions_completed = 9
		gs._set_player_hp(1, 2)
		gs._set_player_hp(2, 2)
		await cross(true, true, "recovery")
		check(gs.p1_hp == 3 and gs.p2_hp == 3 and gs.hp_questions_completed == 10, "10-question recovery")
	elif scenario == "goal":
		gs.current_index = 9
		gs.current_wall_index = 9
		gs.load_current_quiz()
		await cross(false, false, "goal")
		check(gs.game_state == Constants.STATE_GOAL_RACE and gs.p1_hp == 2 and gs.p2_hp == 2, "wrong last wall reaches race")
	elif scenario == "both":
		await cross(false, false, "both")
		check(gs.p1_hp == 2 and gs.p2_hp == 2 and gs.current_wall_index == 1, "both miss but survive")
		check(world.get("_retired_wall_indices").has(0), "all-wrong wall visually retires")
	elif scenario == "stagger":
		place(false, false)
		gs.player2_z -= 2.0
		await frames(70)
		check(gs.p1_hp == 2, "leading mistake only one HP")
		await frames(65)
		await capture("stagger_done")
		check(gs.p1_hp == 2 and gs.p2_hp == 2 and gs.current_wall_index == 1, "staggered misses finish")
	else:
		for hit in range(1, 4):
			await cross(false, true, "%s_hit%d" % [scenario, hit])
			check(gs.p1_hp == 3 - hit and gs.p1_alive == (hit < 3), "visible HP progression %d" % hit)
			if hit < 3:
				check(not pc.get("_p1_exploding"), "nonfatal hit has no death explosion")
				check(pc.get("_health_pose_restore").is_empty(), "recoil fully restores")
				for mesh: MeshInstance3D in pc.p1_parts.get("meshes", []):
					check(mesh.transparency == 0.0, "blink fully restores mesh")
		await frames(150)
		await capture(scenario + "_fatal")
		if scenario == "duo":
			var ghost = world.get("_ghost_shark_ride_controller")
			check(ghost.get("dead_player_index") == 1, "fatal hit starts P1 ghost handoff")
	var report := {"passed": failures.is_empty(), "scenario": scenario, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "events": events, "samples": rows}
	FileAccess.open(OUT + "runtime_" + scenario + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HP_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "case": scenario, "failures": failures, "samples": rows.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func place(correct1: bool, correct2: bool) -> void:
	gs.player_x = helper.door(gs, correct1) + (0.40 if gs.num_players == 2 and correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs, correct2) - (0.40 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 2.0
	gs.player_z = gs.wall_z - 2.0
	gs.player2_z = gs.wall_z - 2.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0

func cross(correct1: bool, correct2: bool, tag: String) -> void:
	place(correct1, correct2)
	var previous_wall := gs.current_wall_index
	await frames(12)
	await capture(tag + "_before")
	for i in range(200):
		await get_tree().process_frame
		if gs.current_wall_index != previous_wall or not gs.p1_alive or gs.p1_damage_time > 0.0:
			break
	await capture(tag + "_impact")
	for segment in range(8):
		await frames(5)
		await capture(tag + "_%02d" % segment)

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
	var lean := 0.0
	for saved: Dictionary in pc.get("_health_pose_restore"):
		if saved.node == pc.p1_parts.get("spine"):
			lean = saved.transform.basis.get_rotation_quaternion().angle_to(saved.node.transform.basis.get_rotation_quaternion())
	rows.append({"tag": tag, "t": gs.play_time, "hp": [gs.p1_hp, gs.p2_hp], "alive": [gs.p1_alive, gs.p2_alive], "hurt": [gs.p1_damage_time, gs.p2_damage_time], "state": gs.game_state, "wall": gs.current_wall_index, "p1_x": gs.player_x, "p1_z": gs.player_z, "lean_degrees": rad_to_deg(lean), "hud_visible": world.get_node("GameplayHUD/PlayerHealthHUD").visible})
