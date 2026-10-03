extends Node

## Runtime evidence for the goal stand scoreboard and its per-question winner cut-in.
## Plays four 2P questions (P1 win, P2 win, both miss, P1 win) through the real
## game world and frames the board after each one: marks land, no cut-in (that
## waits for the match verdict, covered by result_ceremony_runtime.gd).
## Run: Godot --path . --script tests/scoreboard_cutin_bootstrap.gd

const OUT := "res://artifacts/scoreboard_cutin/"
var gs: QuizGameState
var world: Node3D
var helper: Node
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var board_camera: Camera3D


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for old in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + old))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_TEN)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await frames(60)
	var stand := world.get("_goal_stand") as GoalStand
	check(is_instance_valid(stand), "goal stand exists in 2P 10-question mode")
	if not is_instance_valid(stand):
		finish()
		return
	check(stand.scoreboard_installed(), "scoreboard LED face installed in game")
	check(world.get_node_or_null("GameplayHUD/QuestionWinnerCutin") == null, "no screen-space cut-in")
	board_camera = Camera3D.new()
	board_camera.fov = 40.0
	world.add_child(board_camera)
	for step: Array in [[true, false, "q1_p1"], [false, true, "q2_p2"], [false, false, "q3_none"], [true, false, "q4_p1"]]:
		var before := gs.current_index
		await cross(step[0], step[1])
		var expected := (1 if step[0] else 0) | (2 if step[1] else 0)
		check(gs.get_question_winner(before) == expected, "%s recorded mask %d (got %d)" % [step[2], expected, gs.get_question_winner(before)])
		await hold(0.3)
		check(not stand.scoreboard.is_cutin_playing(), "%s question win only marks the board" % step[2])
		await board_shot(stand, "%s_board" % step[2])
	var board: Dictionary = stand.get_debug_snapshot().scoreboard
	check(board.marks.slice(0, 4) == [1, 2, 0, 1] and board.totals == [2, 1], "board marks %s totals %s" % [board.marks, board.totals])
	await board_shot(stand, "scoreboard_crowd", 32.0, 5.0)
	await board_shot(stand, "scoreboard_led_close", 4.0, -0.5)
	finish()


func finish() -> void:
	var report := {"passed": failures.is_empty(), "failures": failures, "samples": rows}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SCOREBOARD_CUTIN " + JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func board_shot(stand: GoalStand, tag: String, distance: float = 15.0, lift: float = 0.0) -> void:
	var layout: Dictionary = stand.get("_layout")
	var board: Dictionary = layout.scoreboard
	var center := stand.global_transform * GoalStand.stand_point(0.0, float(board.screen_y), float(board.screen_z) + float(board.screen_height) * 0.5)
	var facing := (stand.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var previous := get_viewport().get_camera_3d()
	board_camera.global_position = center + facing * distance + Vector3(0.0, lift, 0.0)
	board_camera.look_at(center, Vector3.UP)
	board_camera.make_current()
	await frames(2)
	await capture(tag)
	if is_instance_valid(previous):
		previous.make_current()


## Keeps both players parked short of the next wall while real time passes.
func hold(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var parked := gs.wall_z - 8.0
		gs.world_scroll_z = parked
		gs.player_z = parked
		gs.player2_z = parked
		await get_tree().process_frame


func cross(correct1: bool, correct2: bool) -> void:
	gs.player_x = helper.door(gs, correct1) + (0.40 if correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs, correct2) - (0.40 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 2.0
	gs.player_z = gs.wall_z - 2.0
	gs.player2_z = gs.wall_z - 2.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	var previous_wall := gs.current_wall_index
	for i in range(200):
		await get_tree().process_frame
		if gs.current_wall_index != previous_wall:
			break
	gs.p1_hp = 3
	gs.p2_hp = 3


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
	rows.append({"tag": tag, "wall": gs.current_wall_index, "winners": Array(gs.question_winners)})


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
