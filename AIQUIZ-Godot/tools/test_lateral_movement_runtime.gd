extends SceneTree

# Historical filename retained; now checks restored four-direction movement.
const OUTPUT := "res://artifacts/vertical_movement_restore/"
var _failures: Array[String] = []
var _samples: Array = []
var _checks := 0
var _frame_index := 0
var _state: Variant
var _world: Node
var _players := 1

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	var qm: Node = root.get_node("QuizManager")
	qm.player_analytics = null
	var helper: Variant = load("res://tests/hp_unit.gd").new()
	for players in [1, 2]:
		_players = players
		_state = helper.fixture(players, Constants.MODE_ENDLESS if players == 1 else Constants.MODE_TEN)
		_state.current_quiz.q = "3 ＋ 2 は？"
		_state.current_quiz.c = PackedStringArray(["5", "6"])
		_state.skip_start_helicopter_arrival = true
		qm.game_state = _state
		change_scene_to_file("res://scenes/game_world.tscn")
		await scene_changed
		_world = current_scene
		_world.set("_replay_mode", true)
		_world.get_node("Player").prepare_for_loading(_state)
		_world.get_node("Player").reveal_without_intro_arrival()
		for i in range(35): await frame()
		_state.player_x = -3.0
		_state.player2_x = 3.0
		_state.player_z = _state.world_scroll_z
		_state.player2_z = _state.world_scroll_z
		_state.player_y = 0.0
		_state.player2_y = 0.0
		_state.player_vel_y = 0.0
		_state.player2_vel_y = 0.0
		await phase("idle", [], 0, 0)
		await phase("forward", [KEY_W, KEY_DOWN] if players == 2 else [KEY_W], 1, -1)
		await phase("backward", [KEY_S, KEY_UP] if players == 2 else [KEY_S], -1, 1)
		if players == 1:
			await phase("arrow_forward", [KEY_UP], 1, 0)
			await phase("arrow_backward", [KEY_DOWN], -1, 0)
		var x_before: float = _state.player_x
		await phase("diagonal_jump", [KEY_W, KEY_A, KEY_SPACE, KEY_UP, KEY_RIGHT, KEY_CTRL] if players == 2 else [KEY_W, KEY_A, KEY_SPACE], 1, 1)
		check(_state.player_x > x_before and _state.player_y > 0.0, "P1 lateral movement and jump remain active")
		check(players == 1 or _state.player2_y > 0.0, "P2 jump remains active")
		_state.game_state = Constants.STATE_GOAL_RACE
		_state.goal_z = _state.world_scroll_z + 100.0
		await phase("goal_forward", [KEY_W, KEY_UP] if players == 2 else [KEY_W], 1, 1)
		await phase("goal_backward", [KEY_S, KEY_DOWN] if players == 2 else [KEY_S], -1, -1)
		_state.game_state = Constants.STATE_PLAYING
		_state.state_changed.emit(Constants.STATE_PLAYING)
		for leader in range(1, players + 1):
			_world.set("_replay_mode", true)
			_state.player_y = 0.0
			_state.player2_y = 0.0
			_state.player_vel_y = 0.0
			_state.player2_vel_y = 0.0
			_state.player_z = _state.wall_z - (1.5 if leader == 1 else 5.0)
			_state.player2_z = _state.wall_z - (1.5 if leader == 2 else 5.0)
			var correct_x: float = helper.door(_state, true)
			_state.player_x = correct_x if leader == 1 else -correct_x
			_state.player2_x = correct_x if leader == 2 else -correct_x
			var before_score: int = _state.score if leader == 1 else _state.player2_score
			var other_score: int = _state.player2_score if leader == 1 else _state.score
			var before_wall: int = _state.current_wall_index
			await phase("p%d_answer" % leader, [KEY_W if leader == 1 else KEY_UP], 1 if leader == 1 else 0, 1 if leader == 2 else 0, false)
			check((_state.score if leader == 1 else _state.player2_score) == before_score + 1, "P%d forward input reaches correct door and scores" % leader)
			check(players == 1 or (_state.player2_score if leader == 1 else _state.score) == other_score, "Only the first answering player scores")
			check(_state.current_wall_index == before_wall + 1, "Correct answer advances exactly one question")
		_world.set("_replay_mode", true)
		check(_state.p1_alive and (players == 1 or _state.p2_alive), "Movement sequence keeps players alive")
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "renderer": RenderingServer.get_current_rendering_method(), "samples": _samples, "frames": _frame_index}
	FileAccess.open(OUTPUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("VERTICAL_MOVEMENT_RUNTIME " + JSON.stringify({"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "frames": _frame_index}))
	for provider in helper.providers: provider.free()
	helper.free()
	quit(0 if _failures.is_empty() else 1)

func phase(label: String, keys: Array, p1_direction: int, p2_direction: int, measure := true) -> void:
	var start := Vector2(_state.player_z, _state.player2_z)
	var start_scroll: float = _state.world_scroll_z
	var start_time: float = _state.play_time
	var p1_speed: float = _state.tuning.player_speed
	var goal: bool = _state.game_state == Constants.STATE_GOAL_RACE
	_world.set("_replay_mode", false)
	for code in keys: key(code, true)
	for i in range(18):
		await frame()
		if i % 3 == 0:
			root.get_texture().get_image().save_png(OUTPUT + "frames/%04d.png" % _frame_index)
			_frame_index += 1
	for code in keys: key(code, false)
	_world.set("_replay_mode", true)
	var elapsed: float = _state.play_time - start_time
	var carry: float = _state._active_wall_speed * elapsed if goal else _state.world_scroll_z - start_scroll
	var delta := Vector2(_state.player_z, _state.player2_z) - start - Vector2.ONE * carry
	var sample := {"players": _players, "phase": label, "elapsed": elapsed, "delta_p1": delta.x, "delta_p2": delta.y, "speed": p1_speed, "score_p1": _state.score, "score_p2": _state.player2_score, "wall": _state.current_wall_index}
	_samples.append(sample)
	print("MOVEMENT_SAMPLE " + JSON.stringify(sample))
	if measure:
		check(elapsed > 0.0, label + " advances real game frames")
		check(delta.x * p1_direction > 0.1 if p1_direction != 0 else absf(delta.x) < 0.001, "%dP P1 %s" % [_players, label])
		if _players == 2:
			check(delta.y * p2_direction > 0.1 if p2_direction != 0 else absf(delta.y) < 0.001, "2P P2 " + label)
	root.get_texture().get_image().save_png(OUTPUT + "%dp_%s.png" % [_players, label])

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error(message)
