extends Node

## Keeps player 1 alive by steering into the correct door, through simulated key input
## (Input.parse_input_event with KEY_A / KEY_D, the keys GameWorld._process reads with
## Input.is_key_pressed). A raises player_x, D lowers it.
## Door centres: QuizGameState.is_within_door() (tuning.left_door_x / right_door_x for two
## doors, tuning.door4_xs for four); the right door is current_quiz.a.
## After a correct answer the next quiz is already current while the player is still in the
## door, so the steering waits until the player has cleared the previous wall.
## rush (default on): like a player who knows the answer, hold W (run ahead on the conveyor)
## whenever no sideways move is needed. A cadence of ~3 s per wall instead of the planner's
## reading time (~10 s for grade 3), so 40+ walls fit in a few minutes.

const DEADBAND := 0.25
const CLEAR_MARGIN := 0.8
const RESEND_AFTER_FRAMES := 3

var enabled := false
var rush := true
var steering_frames := 0
var targets_set := 0
var resends := 0

var _down := {KEY_A: false, KEY_D: false, KEY_W: false}
var _mismatch := {KEY_A: 0, KEY_D: 0, KEY_W: 0}
var _last_target_wall := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		release_all()


func release_all() -> void:
	for key: int in _down.keys():
		_send(key, false)
	_down = {KEY_A: false, KEY_D: false, KEY_W: false}


func _send(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key as Key
	event.physical_keycode = key as Key
	event.pressed = pressed
	Input.parse_input_event(event)


func _set_key(key: int, pressed: bool) -> void:
	if bool(_down[key]) != pressed:
		_down[key] = pressed
		_mismatch[key] = 0
		_send(key, pressed)
		return
	# Re-assert the key if the engine dropped it (e.g. the window lost focus).
	if Input.is_key_pressed(key as Key) != pressed:
		_mismatch[key] = int(_mismatch[key]) + 1
		if int(_mismatch[key]) >= RESEND_AFTER_FRAMES:
			_mismatch[key] = 0
			resends += 1
			_send(key, pressed)
	else:
		_mismatch[key] = 0


static func door_x(gs: QuizGameState, door: int) -> float:
	var t := gs.tuning
	if gs.num_choices == 4:
		return t.door4_xs[clampi(door, 0, t.door4_xs.size() - 1)]
	return t.left_door_x if door == 0 else t.right_door_x


func _process(_delta: float) -> void:
	if not enabled:
		return
	var gs: QuizGameState = QuizManager.game_state
	if gs == null or get_tree().paused or gs.game_state not in [Constants.STATE_PLAYING, Constants.STATE_COUNTDOWN, Constants.STATE_CORRECT]:
		_set_key(KEY_A, false)
		_set_key(KEY_D, false)
		_set_key(KEY_W, false)
		return
	var quiz := gs.current_quiz
	if quiz == null or not gs.p1_alive or gs.game_state != Constants.STATE_PLAYING:
		_set_key(KEY_A, false)
		_set_key(KEY_D, false)
		_set_key(KEY_W, false)
		return
	var t := gs.tuning
	var previous_wall_z := t.wall_start_z + float(gs.current_wall_index - 1) * t.wall_spacing
	var cleared := gs.current_wall_index == 0 or gs.player_z > previous_wall_z + CLEAR_MARGIN
	var want := 0
	if cleared:
		if _last_target_wall != gs.current_wall_index:
			_last_target_wall = gs.current_wall_index
			targets_set += 1
		var err := door_x(gs, quiz.a) - gs.player_x
		if err > DEADBAND:
			want = 1
		elif err < -DEADBAND:
			want = -1
	if want != 0:
		steering_frames += 1
	_set_key(KEY_A, want == 1)
	_set_key(KEY_D, want == -1)
	_set_key(KEY_W, rush and want == 0)


func report() -> Dictionary:
	return {"rush": rush, "steering_frames": steering_frames, "targets_set": targets_set, "key_resends": resends}
