extends Node

## Esc の一時停止（GameWorld._toggle_pause）の間は、海に落ちた人へのサメの襲撃も止まる。
## GameWorld は一時停止の画面のために PROCESS_MODE_ALWAYS で、海のサメの群れがそれを受け継いでいたため、
## 止めてもサメだけ進み、一時停止の裏で噛まれて脱落・GAME OVER になっていた。
## 本物の game_world.tscn で P1 をコースの横から海へ落とし（tests/shark_contact_runtime.gd と同じ）、
## サメが向かい始めたら一時停止して 10 秒待つ：噛まれない。再開すると噛まれる。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 960x540 --script res://tests/shark_pause_bootstrap.gd

var checks := 0
var failures: Array[String] = []
var hits := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func run() -> void:
	var gs: QuizGameState = get_tree().root.get_node("QuizManager").game_state
	get_tree().root.get_node("QuizManager").provider.set("llm_mode", "OFFLINE")
	gs.llm_mode = "OFFLINE"
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_PLAYING
	gs.skip_start_helicopter_arrival = true
	gs.current_quiz = QuizItem.create("Shark pause verification", PackedStringArray(["left", "right"]), 0)
	gs._active_wall_speed = 0.0
	gs.world_scroll_z = 0.0
	gs.current_wall_index = 0
	gs.player_x = 2.0
	gs.player_y = 0.0
	gs.player_z = -12.0
	gs.p1_alive = true
	var world: Node3D = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	gs.saw_transport_enabled = false
	world.get_node("Player").prepare_for_loading(gs)
	await get_tree().create_timer(0.3).timeout
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 0.6
	gs.player_y = -1.0
	gs.player_z = gs.wall_z - 0.2
	gs.player_vel_y = -1.0
	var shark: SharkSwimmer = null
	for i: int in range(600):
		await get_tree().process_frame
		shark = world.get("_ocean_attack_sharks").get(1) as SharkSwimmer
		if shark != null:
			break
	_check(shark != null, "a shark heads for the fallen player")
	if shark == null:
		_finish()
		return
	shark.attack_reached.connect(func(_player: int) -> void: hits += 1)
	# 向かい始めてすぐ一時停止する
	await get_tree().process_frame
	world.call("_toggle_pause")
	_check(get_tree().paused, "Esc pause is on")
	var state_before := gs.game_state
	var shark_before := shark.global_position
	await get_tree().create_timer(10.0, true).timeout
	_check(hits == 0, "no bite while paused", hits)
	_check(gs.game_state == state_before and gs.p1_hp > 0, "the match does not end while paused", [gs.game_state, gs.p1_hp])
	_check(shark.global_position.distance_to(shark_before) < 0.01, "the shark stays still while paused",
		shark.global_position.distance_to(shark_before))
	world.call("_toggle_pause")
	_check(not get_tree().paused, "unpaused")
	for i: int in range(1200):
		await get_tree().process_frame
		if hits > 0:
			break
	_check(hits == 1, "the bite happens after the pause ends", hits)
	_finish()


func _finish() -> void:
	get_tree().paused = false
	print("SHARK_PAUSE " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])
