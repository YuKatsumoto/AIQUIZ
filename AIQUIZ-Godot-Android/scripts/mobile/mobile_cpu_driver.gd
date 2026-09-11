extends RefCounted
class_name MobileCpuDriver

## Android版のローカル2Pを担当する入力合成ドライバー。
## QuizGameStateへ座標を直接書かず、人間と同じaxis/jump/emote入力だけを返す。

const STEER_GAIN := 0.72
const STEER_DEADZONE := 0.16
const REACTION_SECONDS := 0.24
const APPROACH_BRAKE_DISTANCE := 4.4
const APPROACH_CRITICAL_DISTANCE := 2.0
const GOAL_RUN_SPEED := 0.82
const P2_DOOR_OFFSET := -0.28
const GHOST_CHARGE_HOLD_SECONDS := 0.92
const GHOST_CHARGE_CYCLE_SECONDS := 3.4

var game_state: QuizGameState
var _last_game_state: String = ""
var _last_step_id: String = ""
var _last_wall_index: int = -1
var _state_elapsed: float = 0.0
var _step_elapsed: float = 0.0
var _reaction_remaining: float = 0.0
var _emote_cooldown: float = 5.5
var _ghost_cycle: float = 0.0
var _decision_count: int = 0
var _last_target_x: float = 0.0
var _last_mode: String = "idle"


func _init(state: QuizGameState = null) -> void:
	game_state = state


func setup(state: QuizGameState) -> void:
	game_state = state
	reset()


func reset() -> void:
	_last_game_state = ""
	_last_step_id = ""
	_last_wall_index = -1
	_state_elapsed = 0.0
	_step_elapsed = 0.0
	_reaction_remaining = 0.0
	_emote_cooldown = 5.5
	_ghost_cycle = 0.0
	_decision_count = 0
	_last_target_x = 0.0
	_last_mode = "idle"


func compute(delta: float, ghost_control_active: bool = false) -> Dictionary:
	var result := _neutral_input()
	if game_state == null:
		return result

	_update_timers(delta)
	if ghost_control_active:
		return _compute_ghost_input(delta)
	if game_state.num_players < 2 or not game_state.p2_alive:
		_last_mode = "inactive"
		return result

	match game_state.game_state:
		Constants.STATE_PLAYING:
			if game_state.mode == Constants.MODE_TUTORIAL:
				result = _compute_tutorial_input()
			else:
				result = _compute_quiz_input()
		Constants.STATE_GOAL_RACE:
			result = _compute_goal_race_input()
		Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN:
			_last_mode = "ready"
		_:
			_last_mode = "idle"

	if int(result.get("emote", 0)) == 0:
		_emote_cooldown -= delta
		if _emote_cooldown <= 0.0 and game_state.p2_emote_slots.size() > 0:
			result["emote"] = int(game_state.p2_emote_slots[0])
			_emote_cooldown = 7.5
	return result


func get_debug_report() -> Dictionary:
	return {
		"available": true,
		"active": game_state != null and game_state.num_players >= 2,
		"mode": _last_mode,
		"target_x": _last_target_x,
		"reaction_remaining": _reaction_remaining,
		"decisions": _decision_count,
		"wall_index": _last_wall_index,
		"step_id": _last_step_id,
	}


func _neutral_input() -> Dictionary:
	return {"axis": Vector2.ZERO, "jump": false, "emote": 0}


func _update_timers(delta: float) -> void:
	var state_name := str(game_state.game_state)
	if state_name != _last_game_state:
		_last_game_state = state_name
		_state_elapsed = 0.0
	else:
		_state_elapsed += delta

	var step_id := game_state.get_tutorial_step_id() if game_state.mode == Constants.MODE_TUTORIAL else ""
	if step_id != _last_step_id:
		_last_step_id = step_id
		_step_elapsed = 0.0
	else:
		_step_elapsed += delta

	if game_state.current_wall_index != _last_wall_index:
		_last_wall_index = game_state.current_wall_index
		_reaction_remaining = REACTION_SECONDS
		_decision_count += 1
	else:
		_reaction_remaining = maxf(0.0, _reaction_remaining - delta)


func _compute_quiz_input() -> Dictionary:
	_last_mode = "quiz"
	var target_variant: Variant = _answer_target_x()
	if target_variant == null:
		return _neutral_input()
	var target_x := float(target_variant)
	_last_target_x = target_x
	if _reaction_remaining > 0.0:
		return {"axis": Vector2.ZERO, "jump": false, "emote": 0}
	return _steer_toward_door(target_x)


func _compute_tutorial_input() -> Dictionary:
	match _last_step_id:
		"duo_run":
			_last_mode = "tutorial_run"
			var run_phase := fmod(_step_elapsed, 2.4)
			return {
				"axis": Vector2(0.72 if run_phase < 1.2 else -0.72, 0.0),
				"jump": false,
				"emote": 0,
			}
		"duo_air":
			_last_mode = "tutorial_air"
			var air_phase := fmod(_step_elapsed, 2.4)
			return {
				"axis": Vector2(0.0, 0.72 if air_phase < 1.2 else -0.72),
				"jump": fmod(_step_elapsed, 1.8) < 0.18,
				"emote": 0,
			}
		"duo_emote":
			_last_mode = "tutorial_emote"
			return {
				"axis": Vector2.ZERO,
				"jump": false,
				"emote": int(game_state.p2_emote_slots[0]) if game_state.p2_emote_slots.size() > 0 else 0,
			}
		"duo_ocean":
			_last_mode = "tutorial_ocean"
			return {"axis": Vector2(-1.0, 0.0), "jump": false, "emote": 0}
		"duo_ghost":
			_last_mode = "tutorial_ghost_wait"
			return _neutral_input()
		"duo_guided_wall", "duo_free_wall":
			return _compute_quiz_input()
		"duo_goal":
			return _compute_goal_race_input()
		_:
			_last_mode = "tutorial_idle"
			return _neutral_input()


func _compute_goal_race_input() -> Dictionary:
	_last_mode = "goal_race"
	_last_target_x = -2.1
	var lateral := _steer_axis(_last_target_x)
	return {
		"axis": Vector2(lateral, GOAL_RUN_SPEED),
		"jump": fmod(_state_elapsed, 3.1) < 0.14,
		"emote": 0,
	}


func _compute_ghost_input(delta: float) -> Dictionary:
	_last_mode = "ghost"
	_ghost_cycle = fmod(_ghost_cycle + delta, GHOST_CHARGE_CYCLE_SECONDS)
	var aim_x := clampf((game_state.player_x - game_state.player2_x) * 0.08, -0.42, 0.42)
	var aim_y := clampf((game_state.player_z - game_state.player2_z) * 0.05, -0.35, 0.35)
	return {
		"axis": Vector2(aim_x, aim_y) if _ghost_cycle < 0.55 else Vector2.ZERO,
		"jump": _ghost_cycle >= 0.62 and _ghost_cycle < 0.62 + GHOST_CHARGE_HOLD_SECONDS,
		"emote": 0,
	}


func _answer_target_x() -> Variant:
	var quiz := game_state.current_quiz
	if quiz == null:
		return null
	var tuning := game_state.tuning
	if game_state.is_coop_mode() and quiz.has_coop_data():
		var coop_answer := quiz.coop_p2_answer
		if coop_answer >= 0 and coop_answer < tuning.coop_p2_door_xs.size():
			return float(tuning.coop_p2_door_xs[coop_answer])
		return null

	var answer := quiz.a
	if game_state.num_choices == 4:
		if answer >= 0 and answer < tuning.door4_xs.size():
			return float(tuning.door4_xs[answer]) + P2_DOOR_OFFSET
		return null
	if answer == 0:
		return float(tuning.left_door_x) + P2_DOOR_OFFSET
	if answer == 1:
		return float(tuning.right_door_x) + P2_DOOR_OFFSET
	return null


func _steer_toward_door(target_x: float) -> Dictionary:
	var lateral := _steer_axis(target_x)
	var distance_to_wall := game_state.wall_z - game_state.player2_z
	var forward := 0.12
	if distance_to_wall < APPROACH_CRITICAL_DISTANCE and absf(target_x - game_state.player2_x) > 0.42:
		forward = -0.48
	elif distance_to_wall < APPROACH_BRAKE_DISTANCE and absf(target_x - game_state.player2_x) > 0.30:
		forward = -0.18
	elif distance_to_wall > 8.0:
		forward = 0.24
	return {"axis": Vector2(lateral, forward), "jump": false, "emote": 0}


func _steer_axis(target_x: float) -> float:
	var error := target_x - game_state.player2_x
	if absf(error) <= STEER_DEADZONE:
		return 0.0
	return clampf(error * STEER_GAIN, -1.0, 1.0)
