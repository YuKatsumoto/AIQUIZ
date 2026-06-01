class_name MenuPreviewDoorLearner
extends RefCounted

const ACTION_LEFT: int = 0
const ACTION_RIGHT: int = 1

const ALPHA: float = 0.35
const NOISE_START: float = 1.1
const NOISE_MIN: float = 0.12
const MISS_CHANCE_START: float = 0.38
const MISS_CHANCE_MIN: float = 0.12
const LEFT_DOOR_X: float = 3.5
const RIGHT_DOOR_X: float = -3.5
const CENTER_MISS_X: float = 0.0

var _q_values: Array[float] = [0.0, 0.0]
var _attempts: int = 0
var _successes: int = 0
var _next_action: int = ACTION_LEFT
var _start_action: int = ACTION_LEFT
var _episode_miss: bool = false
var _last_miss_chance: float = MISS_CHANCE_START


func reset_session(start_action: int = ACTION_LEFT) -> void:
	_start_action = ACTION_LEFT if start_action != ACTION_RIGHT else ACTION_RIGHT
	_next_action = _start_action
	_q_values = [0.0, 0.0]
	_attempts = 0
	_successes = 0
	_episode_miss = false


func pick_door_action() -> int:
	var intended := _next_action
	_episode_miss = randf() < _current_miss_chance()
	_last_miss_chance = _current_miss_chance()
	if _episode_miss and randf() < 0.45:
		return ACTION_RIGHT if intended == ACTION_LEFT else ACTION_LEFT
	return intended


func target_x_for_action(action: int) -> float:
	var clamped_action := clampi(action, ACTION_LEFT, ACTION_RIGHT)
	if _episode_miss:
		if randf() < 0.55:
			return CENTER_MISS_X + randf_range(-0.65, 0.65)
		var wrong_action := ACTION_RIGHT if clamped_action == ACTION_LEFT else ACTION_LEFT
		clamped_action = wrong_action
	var base_x := LEFT_DOOR_X if clamped_action == ACTION_LEFT else RIGHT_DOOR_X
	var noise_amp := lerpf(NOISE_START, NOISE_MIN, get_skill())
	return base_x + randf_range(-noise_amp, noise_amp)


func is_episode_miss() -> bool:
	return _episode_miss


func record_outcome(action: int, reward: float) -> void:
	var clamped_action := clampi(action, ACTION_LEFT, ACTION_RIGHT)
	_attempts += 1
	if reward > 0.0:
		_successes += 1
		_next_action = ACTION_RIGHT if clamped_action == ACTION_LEFT else ACTION_LEFT
	var prev_q := _q_values[clamped_action]
	_q_values[clamped_action] = prev_q + ALPHA * (reward - prev_q)
	_episode_miss = false


func get_skill() -> float:
	if _attempts <= 0:
		return 0.0
	return clampf(float(_successes) / float(_attempts), 0.0, 1.0)


func get_stats() -> Dictionary:
	return {
		"attempts": _attempts,
		"successes": _successes,
		"skill": get_skill(),
		"miss_chance": _last_miss_chance,
		"next_action": _next_action,
		"q_left": _q_values[ACTION_LEFT],
		"q_right": _q_values[ACTION_RIGHT],
	}


func _current_miss_chance() -> float:
	return lerpf(MISS_CHANCE_START, MISS_CHANCE_MIN, get_skill())
