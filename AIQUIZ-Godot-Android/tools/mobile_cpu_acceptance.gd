extends Node

## Deterministic coverage for every non-tutorial gameplay branch of the local
## mobile CPU. It checks decisions only; the full runtime probe separately
## proves that these inputs move the authored P2 character in GameWorld.

var _checks: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var state: QuizGameState = QuizManager.game_state
	state.num_players = 2
	state.p2_alive = true
	state.game_state = Constants.STATE_PLAYING
	state.target_count = 10
	state.current_index = 0
	state.current_wall_index = 0
	state.player2_z = 0.0
	state.difficulty = "普通"

	var cpu := MobileCpuDriver.new(state)
	_test_two_door(state, cpu, 0)
	_test_two_door(state, cpu, 1)
	_test_four_door(state, cpu, 0)
	_test_four_door(state, cpu, 3)
	_test_coop(state, cpu, 0)
	_test_coop(state, cpu, 1)
	_test_goal_race(state, cpu)
	_test_ghost(state, cpu)

	var passed := true
	for key: String in _checks:
		if not bool(_checks[key]):
			passed = false
	print("[MobileCpuAcceptance] checks=%s" % JSON.stringify(_checks))
	get_tree().quit(0 if passed else 2)


func _sample_after_reaction(cpu: MobileCpuDriver) -> Dictionary:
	cpu.reset()
	cpu.compute(0.01)
	return cpu.compute(0.30)


func _test_two_door(state: QuizGameState, cpu: MobileCpuDriver, answer: int) -> void:
	state.mode = Constants.MODE_TEN
	state.difficulty = "普通"
	state.current_index = 0
	state.current_quiz = QuizItem.create(
		"two-door",
		PackedStringArray(["left", "right"]),
		answer
	)
	state.player2_x = 0.0
	var result := _sample_after_reaction(cpu)
	var expected := (
		state.tuning.left_door_x if answer == 0 else state.tuning.right_door_x
	) - 0.28
	var target := float(cpu.get_debug_report().get("target_x", 999.0))
	var axis: Vector2 = result.get("axis", Vector2.ZERO) as Vector2
	_checks["two_door_%d_target" % answer] = is_equal_approx(target, expected)
	_checks["two_door_%d_steer" % answer] = signf(axis.x) == signf(expected)


func _test_four_door(state: QuizGameState, cpu: MobileCpuDriver, answer: int) -> void:
	state.mode = Constants.MODE_TEN
	state.difficulty = "難しい"
	state.current_index = 0
	state.current_quiz = QuizItem.create(
		"four-door",
		PackedStringArray(["a", "b", "c", "d"]),
		answer
	)
	state.player2_x = 0.0
	var result := _sample_after_reaction(cpu)
	var expected := state.tuning.door4_xs[answer] - 0.28
	var target := float(cpu.get_debug_report().get("target_x", 999.0))
	var axis: Vector2 = result.get("axis", Vector2.ZERO) as Vector2
	_checks["four_door_%d_target" % answer] = is_equal_approx(target, expected)
	_checks["four_door_%d_steer" % answer] = signf(axis.x) == signf(expected)


func _test_coop(state: QuizGameState, cpu: MobileCpuDriver, answer: int) -> void:
	state.mode = Constants.MODE_COOP
	state.difficulty = "普通"
	state.current_quiz = QuizItem.create(
		"coop",
		PackedStringArray(["a", "b"]),
		0
	)
	state.current_quiz.coop_p1_choices = PackedStringArray(["a", "b"])
	state.current_quiz.coop_p2_choices = PackedStringArray(["c", "d"])
	state.current_quiz.coop_p1_answer = 0
	state.current_quiz.coop_p2_answer = answer
	state.player2_x = -6.0
	var result := _sample_after_reaction(cpu)
	var expected := state.tuning.coop_p2_door_xs[answer]
	var target := float(cpu.get_debug_report().get("target_x", 999.0))
	var axis: Vector2 = result.get("axis", Vector2.ZERO) as Vector2
	_checks["coop_%d_target" % answer] = is_equal_approx(target, expected)
	_checks["coop_%d_steer" % answer] = (
		absf(expected - state.player2_x) <= 0.16
		or signf(axis.x) == signf(expected - state.player2_x)
	)


func _test_goal_race(state: QuizGameState, cpu: MobileCpuDriver) -> void:
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_GOAL_RACE
	state.player2_x = 0.0
	cpu.reset()
	var result := cpu.compute(0.30)
	var axis: Vector2 = result.get("axis", Vector2.ZERO) as Vector2
	_checks["goal_forward"] = axis.y > 0.8
	_checks["goal_lane"] = axis.x < 0.0


func _test_ghost(state: QuizGameState, cpu: MobileCpuDriver) -> void:
	state.game_state = Constants.STATE_PLAYING
	state.player_x = 4.0
	state.player2_x = -2.0
	state.player_z = 6.0
	state.player2_z = 0.0
	cpu.reset()
	var aim := cpu.compute(0.20, true)
	var charge := cpu.compute(0.55, true)
	var aim_axis: Vector2 = aim.get("axis", Vector2.ZERO) as Vector2
	_checks["ghost_aim"] = aim_axis.x > 0.0 and aim_axis.y > 0.0
	_checks["ghost_charge"] = bool(charge.get("jump", false))
