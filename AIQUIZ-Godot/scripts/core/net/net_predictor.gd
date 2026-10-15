class_name NetPredictor
extends RefCounted

## Online guest: client-side prediction of the guest's own avatar.
##
## The guest never runs QuizGameState.update(). It instead replays its own
## commands through the same per-slot kinematics the host runs in
## _update_playing / _update_goal_race, in track-local coordinates (the world
## scroll carries the player and the track by the same amount, so it cancels).
## When a snapshot arrives the state is reset to the host's result for the last
## acknowledged command and the still-unacknowledged commands are replayed.
## Interactions that need both players (body collision, push duel, saw, ocean)
## stay host-only: the guest simply accepts the correction.

const TICK := 1.0 / 60.0
## Larger corrections snap instead of blending (teleports, revives, resets).
const SNAP_DISTANCE := 1.5
## Visual error blends out over roughly this many seconds.
const ERROR_DECAY_TIME := 0.1
const MAX_PENDING := 240

var gs: QuizGameState
var slot := 2

# Predicted motion (track-local z).
var x := 0.0
var lz := 0.0
var y := 0.0
var vy := 0.0
var ext := Vector2.ZERO
var lock := 0.0
var hurt := 0.0
var jump_count := 0

## Unacknowledged commands: {seq, ax, ay, j, e, scroll, state}.
var pending: Array[Dictionary] = []
## Rendered offset that hides reconciliation corrections.
var error := Vector3.ZERO
var last_correction := 0.0
## Wall index the guest has already passed through a correct door (no clamp).
var _passed_wall := -1


func setup(state: QuizGameState, predicted_slot: int) -> void:
	gs = state
	slot = predicted_slot
	reset_from_state()


func reset_from_state() -> void:
	var m := gs.get_slot_motion(slot)
	_load(m)
	pending.clear()
	error = Vector3.ZERO
	_passed_wall = -1


func _load(m: Dictionary) -> void:
	x = float(m.get("x", x))
	lz = float(m.get("lz", lz))
	y = float(m.get("y", y))
	vy = float(m.get("vy", vy))
	ext = Vector2(float(m.get("ex", ext.x)), float(m.get("ez", ext.y)))
	lock = float(m.get("lock", lock))
	hurt = float(m.get("hurt", hurt))


## Whether the guest's own movement is predicted in the current game state.
func is_active() -> bool:
	if gs == null:
		return false
	if gs.game_state not in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]:
		return false
	var alive := gs.p2_alive if slot == 2 else gs.p1_alive
	var waiting := gs.p2_waiting_for_shark if slot == 2 else gs.p1_waiting_for_shark
	var committed := gs.p2_fall_committed if slot == 2 else gs.p1_fall_committed
	if not alive or waiting or committed or gs.has_player_reached_goal(slot):
		return false
	return true


## Records one new local command and, while prediction is active, applies it.
func push_command(cmd: Dictionary) -> void:
	pending.append(cmd)
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	if is_active():
		_step(cmd)


## Snapshot from the host: authoritative motion after command `ack`.
func reconcile(ack: int, motion: Dictionary) -> void:
	var before := Vector3(x, y, lz)
	while not pending.is_empty() and int(pending[0].seq) <= ack:
		pending.pop_front()
	_load(motion)
	if is_active():
		for cmd in pending:
			_step(cmd)
	var after := Vector3(x, y, lz)
	var delta := before - after
	last_correction = delta.length()
	if last_correction > SNAP_DISTANCE:
		error = Vector3.ZERO
	else:
		error += delta
		if error.length() > SNAP_DISTANCE:
			error = Vector3.ZERO


func decay_error(dt: float) -> void:
	error *= exp(-dt / ERROR_DECAY_TIME)
	if error.length_squared() < 0.000001:
		error = Vector3.ZERO


## Rendered motion: prediction plus the fading correction offset.
func render_x() -> float:
	return x + error.x


func render_y() -> float:
	return maxf(-50.0, y + error.y)


func render_lz() -> float:
	return lz + error.z


# ---------- Kinematics (mirrors QuizGameState._update_playing for one slot) ----------

func _stunned() -> bool:
	return gs.uses_hp() and hurt > QuizGameState.DAMAGE_FLASH_DURATION - QuizGameState.DAMAGE_STUN_DURATION


func _step(cmd: Dictionary) -> void:
	var dt := TICK
	var state := str(cmd.get("state", Constants.STATE_PLAYING))
	var axis := Vector2(float(cmd.ax), float(cmd.ay))
	var jump := bool(cmd.j)
	var controllable := lock <= 0.0 and not _stunned()
	if not controllable:
		axis = Vector2.ZERO
		jump = false
	lock = maxf(0.0, lock - dt)
	hurt = maxf(0.0, hurt - dt)

	var front := gs.get_floor_front_z()
	x += axis.x * gs.tuning.player_speed * dt
	lz += axis.y * gs.tuning.player_speed * dt
	if state == Constants.STATE_GOAL_RACE:
		# Goal race stops the world scroll but keeps carrying the runners forward.
		lz += gs._active_wall_speed * dt
	x += ext.x * dt
	lz += ext.y * dt
	ext = ext.move_toward(Vector2.ZERO, QuizGameState.EXTERNAL_IMPULSE_DECELERATION * dt)

	var on_floor := gs._is_on_track_floor(x, lz, slot, front)
	if jump and y <= 0.0 and on_floor:
		vy = QuizGameState.TWO_PLAYER_JUMP_FORCE if gs.num_players >= 2 else QuizGameState.JUMP_FORCE
		jump_count += 1
	var hat := gs.p2_hat if slot == 2 else gs.p1_hat
	vy -= gs._jump_gravity(hat, y, vy) * dt
	y += vy * dt
	if y <= 0.0 and on_floor:
		y = 0.0
		vy = 0.0

	if state == Constants.STATE_PLAYING:
		_apply_walls(float(cmd.get("scroll", gs.world_scroll_z)))


## Quiz wall and its world-border extension, judged locally so the guest's own
## avatar stops (wrong door) or passes (right door) without waiting a round trip.
func _apply_walls(scroll: float) -> void:
	if gs.are_tutorial_walls_hidden() or gs.choice_locked:
		return
	var wall_z := gs.wall_z
	var world_z := scroll + lz
	# World border: outside the wall's lanes the player is stopped and bounced.
	var stop_z := wall_z - QuizGameState.WALL_WORLD_BORDER_STOP_DISTANCE
	if gs.is_in_wall_border_lane(x) and world_z > stop_z and world_z <= wall_z + 1.0:
		lz = stop_z - scroll
		if ext.y > -QuizGameState.WALL_WORLD_BORDER_PUSH_SPEED * 0.5:
			ext.y = -QuizGameState.WALL_WORLD_BORDER_PUSH_SPEED
		return
	if gs.current_wall_index == _passed_wall:
		return
	if world_z < wall_z - 0.4 or not gs._is_on_track_floor(x, lz, slot):
		return
	var quiz := gs.current_quiz
	if quiz != null and gs._check_player_door(x) == quiz.a:
		_passed_wall = gs.current_wall_index
		return
	lz = wall_z - 0.4 - scroll
