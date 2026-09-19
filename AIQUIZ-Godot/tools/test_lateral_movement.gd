extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_playing_movement(1)
	_test_playing_movement(2)
	_test_goal_race_movement()
	_test_tutorial_tasks()
	if _failures == 0:
		print("VERTICAL_MOVEMENT_ACCEPTANCE pass=true")
	quit(0 if _failures == 0 else 1)


func _new_state(players: int) -> Variant:
	var state_script: GDScript = load("res://scripts/core/game_state.gd")
	if state_script == null:
		_check(false, "QuizGameState script loads")
		return null
	var state: Variant = state_script.new()
	state.mode = Constants.MODE_ENDLESS
	state.game_state = Constants.STATE_PLAYING
	state.num_players = players
	state.player_x = -2.0 if players >= 2 else 0.0
	state.player2_x = 2.0
	state.player_z = 0.0
	state.player2_z = 0.0
	state.world_scroll_z = 0.0
	state._active_wall_speed = 4.0
	return state


func _test_playing_movement(players: int) -> void:
	var state: Variant = _new_state(players)
	if state == null:
		return
	var delta := 0.1
	state._update_playing(
		delta,
		Vector2(0.0, 1.0),
		Vector2(0.0, -1.0),
		true,
		players >= 2
	)
	_check(state.player_local_z > 0.5, "P1 forward input advances relative to automatic scroll")
	_check(players < 2 or state.player2_local_z < -0.5, "P2 backward input retreats relative to automatic scroll")
	_check(state.player_y > 0.0, "P1 jump remains active")
	_check(players < 2 or state.player2_y > 0.0, "P2 jump remains active")

	state = _new_state(players)
	var p1_start_x: float = state.player_x
	var p2_start_x: float = state.player2_x
	state._update_playing(
		delta,
		Vector2(0.707, 0.707),
		Vector2(-0.707, -0.707),
		false,
		false
	)
	_check(state.player_x > p1_start_x, "P1 diagonal input moves sideways")
	_check(players < 2 or state.player2_x < p2_start_x, "P2 diagonal input moves sideways")
	_check(state.player_local_z > 0.3, "P1 diagonal input moves forward")
	_check(players < 2 or state.player2_local_z < -0.3, "P2 diagonal input moves backward")
	_check(Vector2(state.player_x - p1_start_x, state.player_local_z).length() <= state.tuning.player_speed * delta + 0.001, "Diagonal movement does not exceed ordinary movement speed")
	state = _new_state(players)
	state.p1_external_control_lock = 1.0
	state.p2_damage_time = state.DAMAGE_FLASH_DURATION
	state._update_playing(delta, Vector2(0, 1), Vector2(0, -1), true, true)
	_check(is_zero_approx(state.player_local_z) and is_zero_approx(state.player_y), "External control lock blocks forward movement and jump")
	_check(players < 2 or is_zero_approx(state.player2_local_z) and is_zero_approx(state.player2_y), "Damage stun blocks backward movement and jump")


func _test_goal_race_movement() -> void:
	var state: Variant = _new_state(2)
	if state == null:
		return
	state.goal_z = 1000.0
	state.game_state = Constants.STATE_GOAL_RACE
	state._update_goal_race(
		0.1,
		Vector2(0.0, 1.0),
		Vector2(0.0, -1.0),
		false,
		false
	)
	_check(state.player_z > 0.9, "P1 can accelerate toward goal")
	_check(state.player2_z < 0.0, "P2 can move backward during goal race")


func _test_tutorial_tasks() -> void:
	var solo: RefCounted = load("res://scripts/core/tutorial/solo_tutorial_flow.gd").new()
	var duo: RefCounted = load("res://scripts/core/tutorial/duo_tutorial_flow.gd").new()
	_check(_step_task_ids(solo._build_steps(), "air_control") == ["jump", "forward", "back"], "Solo tutorial teaches jump and forward/back")
	_check(_step_task_ids(duo._build_steps(), "duo_air", 1) == ["jump", "forward", "back"], "Duo P1 tutorial teaches jump and forward/back")
	_check(_step_task_ids(duo._build_steps(), "duo_air", 2) == ["jump", "forward", "back"], "Duo P2 tutorial teaches jump and forward/back")
	for flow in [solo, duo]:
		flow.start()
		while flow.current_step_id() not in ["air_control", "duo_air"]:
			flow.advance_step()
		flow.presentation_locked = false
		flow.awaiting_neutral_input = false
		flow.update_input_practice(Vector2(0, 1), Vector2(0, 1), false, false, 0, 0)
		flow.update_input_practice(Vector2(0, -1), Vector2(0, -1), true, true, 0, 0)
		_check(flow.all_tasks_complete(), "Tutorial forward/back/jump tasks can actually complete")


func _step_task_ids(steps: Array[Dictionary], step_id: String, player_index: int = 0) -> Array[String]:
	for step: Dictionary in steps:
		if String(step.get("id", "")) != step_id:
			continue
		var tasks: Variant = step.get("tasks", [])
		if player_index > 0:
			tasks = (tasks as Dictionary).get(player_index, [])
		var ids: Array[String] = []
		for task: Dictionary in tasks:
			ids.append(String(task.get("id", "")))
		return ids
	return []


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failures += 1
	push_error("FAIL: " + description)
