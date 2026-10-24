class_name MenuPreviewDoorLearner
extends RefCounted

## メニュー背景ランナーの「扉の上達」。くぐれた割合が skill になり、上手になるほど狙いのぶれと失敗が減る。

const ACTION_LEFT: int = 0
const ACTION_RIGHT: int = 1

const NOISE_START: float = 1.1
const NOISE_MIN: float = 0.12
const MISS_CHANCE_START: float = 0.38
const MISS_CHANCE_MIN: float = 0.12
## メニューの壁は180°回して置くので、扉0(青)はワールド x=-3.5、扉1(赤)は x=+3.5。
const LEFT_DOOR_X: float = -3.5
const RIGHT_DOOR_X: float = 3.5
const CENTER_MISS_X: float = 0.0
const MISS_CENTER_CHANCE: float = 0.15

var _attempts: int = 0
var _successes: int = 0
var _next_action: int = ACTION_LEFT
var _start_action: int = ACTION_LEFT
var _episode_miss: bool = false


func reset_session(start_action: int = ACTION_LEFT) -> void:
	_start_action = ACTION_LEFT if start_action != ACTION_RIGHT else ACTION_RIGHT
	_next_action = _start_action
	_attempts = 0
	_successes = 0
	_episode_miss = false


## 次に狙う扉を選び、この1回が失敗の回かどうかも決める（失敗の回は target_x_for_action がずれた位置を返す）。
func pick_door_action() -> int:
	var intended := _next_action
	_episode_miss = randf() < _current_miss_chance()
	if _episode_miss and randf() < 0.45:
		return ACTION_RIGHT if intended == ACTION_LEFT else ACTION_LEFT
	return intended


func target_x_for_action(action: int) -> float:
	var clamped_action := clampi(action, ACTION_LEFT, ACTION_RIGHT)
	if _episode_miss:
		if randf() < MISS_CENTER_CHANCE:
			return CENTER_MISS_X + randf_range(-0.65, 0.65)
		if randf() < 0.5:
			var wrong_action := ACTION_RIGHT if clamped_action == ACTION_LEFT else ACTION_LEFT
			clamped_action = wrong_action
		else:
			var base_miss_x := LEFT_DOOR_X if clamped_action == ACTION_LEFT else RIGHT_DOOR_X
			var outward_sign := 1.0 if base_miss_x > 0.0 else -1.0
			return base_miss_x + outward_sign * randf_range(0.55, 1.05)
	var base_x := LEFT_DOOR_X if clamped_action == ACTION_LEFT else RIGHT_DOOR_X
	var noise_amp := lerpf(NOISE_START, NOISE_MIN, get_skill())
	return base_x + randf_range(-noise_amp, noise_amp)


func record_outcome(action: int, reward: float) -> void:
	var clamped_action := clampi(action, ACTION_LEFT, ACTION_RIGHT)
	_attempts += 1
	if reward > 0.0:
		_successes += 1
		_next_action = ACTION_RIGHT if clamped_action == ACTION_LEFT else ACTION_LEFT
	_episode_miss = false


func get_skill() -> float:
	if _attempts <= 0:
		return 0.0
	return clampf(float(_successes) / float(_attempts), 0.0, 1.0)


func _current_miss_chance() -> float:
	return lerpf(MISS_CHANCE_START, MISS_CHANCE_MIN, get_skill())
