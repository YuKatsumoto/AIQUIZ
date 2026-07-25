extends RefCounted
class_name BikeRaceRules

## Deterministic bicycle handling and crash-recovery rules.
## QuizGameState remains authoritative; the visible crash is simulated by
## RigidBody3D proxies owned by MamaChariVisual.

const COURSE_LENGTH: float = 230.0
const ROAD_HALF_WIDTH: float = 8.0
const COURSE_SURFACE_Y: float = -1.2
const NORMAL_MAX_SPEED: float = 14.0
const BOOST_MAX_SPEED: float = 16.5
const ACCELERATION: float = 5.0
const BRAKE_DECELERATION: float = 8.0
const COAST_DECELERATION: float = 1.8
const SLIPSTREAM_SPEED_BONUS: float = 1.2
const BOOST_DRAIN_PER_SECOND: float = 1.0 / 3.0
const BOOST_RECOVERY_PER_SECOND: float = 0.24
const FALL_RECOVERY_SECONDS: float = 2.25
const FALL_MIN_HAZARD_STRENGTH: float = 0.40
const FALL_MIN_SPEED: float = 2.0
const RESPAWN_INVULNERABLE_SECONDS: float = 1.1
const PHOTO_FINISH_WINDOW: float = 0.05
const RIDER_RIDING: String = "RIDING"
const RIDER_TUMBLING: String = "TUMBLING"
const CHECKPOINTS: Array[float] = [0.0, 90.0, 130.0, 185.0, 220.0]

var _finish_grace_remaining: float = -1.0


static func get_fall_visual_amount(fall_timer: float) -> float:
	return 1.0 if fall_timer > 0.0 else 0.0


func reset(gs) -> void:
	_finish_grace_remaining = -1.0
	gs.race_elapsed = 0.0
	gs.race_winner = 0
	gs.race_finished = false
	gs.race_win_reason = ""
	gs.p1_finish_time = -1.0
	gs.p2_finish_time = -1.0

	var score_delta: int = gs.score - gs.player2_score
	gs.bike_p1_start_delay = clampf(float(-score_delta) * 0.12, 0.0, 1.0)
	gs.bike_p2_start_delay = clampf(float(score_delta) * 0.12, 0.0, 1.0)
	_reset_rider(gs, 1, 2.25)
	_reset_rider(gs, 2, -2.25)


func _reset_rider(gs, player_index: int, lane_x: float) -> void:
	if player_index == 1:
		gs.player_x = lane_x
		gs.player_y = 0.0
		gs.player_z = gs.bike_start_z
		gs.player_vel_y = 0.0
		gs.bike_p1_speed = 0.0
		gs.bike_p1_stamina = 1.0
		gs.bike_p1_steer = 0.0
		gs.bike_p1_wobble = 0.0
		gs.bike_p1_fall_timer = 0.0
		gs.bike_p1_invulnerable = 0.0
		gs.bike_p1_checkpoint = 0
		gs.bike_p1_slipstream = false
		gs.bike_p1_boosting = false
		gs.bike_p1_recovery_state = RIDER_RIDING
		gs.bike_p1_bike_x = lane_x
		gs.bike_p1_bike_z = gs.bike_start_z
		gs.bike_p1_crash_revision = 0
		gs.bike_p1_crash_strength = 0.0
	else:
		gs.player2_x = lane_x
		gs.player2_y = 0.0
		gs.player2_z = gs.bike_start_z
		gs.player2_vel_y = 0.0
		gs.bike_p2_speed = 0.0
		gs.bike_p2_stamina = 1.0
		gs.bike_p2_steer = 0.0
		gs.bike_p2_wobble = 0.0
		gs.bike_p2_fall_timer = 0.0
		gs.bike_p2_invulnerable = 0.0
		gs.bike_p2_checkpoint = 0
		gs.bike_p2_slipstream = false
		gs.bike_p2_boosting = false
		gs.bike_p2_recovery_state = RIDER_RIDING
		gs.bike_p2_bike_x = lane_x
		gs.bike_p2_bike_z = gs.bike_start_z
		gs.bike_p2_crash_revision = 0
		gs.bike_p2_crash_strength = 0.0


func step(
	gs,
	dt: float,
	axis_p1: Vector2,
	axis_p2: Vector2,
	boost_p1: bool,
	boost_p2: bool
) -> void:
	if gs.race_finished:
		return

	var p1: Dictionary = _read_rider(gs, 1)
	var p2: Dictionary = _read_rider(gs, 2)
	_apply_slipstream(p1, p2)
	_step_rider(p1, dt, axis_p1, boost_p1, gs.bike_start_z)
	_step_rider(p2, dt, axis_p2, boost_p2, gs.bike_start_z)
	_update_finish_time(gs, p1, dt, 1)
	_update_finish_time(gs, p2, dt, 2)
	_write_rider(gs, 1, p1)
	_write_rider(gs, 2, p2)

	var p1_finished: bool = gs.p1_finish_time >= 0.0
	var p2_finished: bool = gs.p2_finish_time >= 0.0
	if p1_finished and p2_finished:
		_resolve_phase_finish(gs)
	elif p1_finished or p2_finished:
		if _finish_grace_remaining < 0.0:
			_finish_grace_remaining = PHOTO_FINISH_WINDOW
		else:
			_finish_grace_remaining -= dt
			if _finish_grace_remaining <= 0.0:
				_resolve_phase_finish(gs)


func apply_hazard(gs, player_index: int, severity: float) -> void:
	if gs.game_state != Constants.STATE_ATHLETIC_RACE or gs.race_phase != Constants.RACE_PHASE_BIKE:
		return
	var rider: Dictionary = _read_rider(gs, player_index)
	if float(rider.invulnerable) > 0.0 or str(rider.recovery_state) != RIDER_RIDING:
		return

	var hit_strength: float = clampf(severity, 0.0, 1.0)
	rider.wobble = minf(1.0, float(rider.wobble) + 0.35 + hit_strength * 0.55)
	if hit_strength >= FALL_MIN_HAZARD_STRENGTH and float(rider.speed) >= FALL_MIN_SPEED:
		rider.crash_strength = clampf(
			hit_strength * 0.7 + float(rider.speed) / BOOST_MAX_SPEED * 0.55,
			0.45,
			1.25
		)
		rider.speed = 0.0
		rider.steer = 0.0
		rider.boosting = false
		rider.fall_timer = FALL_RECOVERY_SECONDS
		rider.recovery_state = RIDER_TUMBLING
		rider.bike_x = float(rider.x)
		rider.bike_z = float(rider.z)
		rider.crash_revision = int(rider.crash_revision) + 1
	else:
		rider.speed *= lerpf(0.82, 0.48, hit_strength)
	_write_rider(gs, player_index, rider)


func _read_rider(gs, player_index: int) -> Dictionary:
	if player_index == 1:
		return {
			"x": gs.player_x,
			"y": gs.player_y,
			"z": gs.player_z,
			"speed": gs.bike_p1_speed,
			"stamina": gs.bike_p1_stamina,
			"steer": gs.bike_p1_steer,
			"wobble": gs.bike_p1_wobble,
			"fall_timer": gs.bike_p1_fall_timer,
			"invulnerable": gs.bike_p1_invulnerable,
			"checkpoint": gs.bike_p1_checkpoint,
			"slipstream": gs.bike_p1_slipstream,
			"boosting": gs.bike_p1_boosting,
			"start_delay": gs.bike_p1_start_delay,
			"recovery_state": gs.bike_p1_recovery_state,
			"bike_x": gs.bike_p1_bike_x,
			"bike_z": gs.bike_p1_bike_z,
			"crash_revision": gs.bike_p1_crash_revision,
			"crash_strength": gs.bike_p1_crash_strength,
			"previous_z": gs.player_z,
		}
	return {
		"x": gs.player2_x,
		"y": gs.player2_y,
		"z": gs.player2_z,
		"speed": gs.bike_p2_speed,
		"stamina": gs.bike_p2_stamina,
		"steer": gs.bike_p2_steer,
		"wobble": gs.bike_p2_wobble,
		"fall_timer": gs.bike_p2_fall_timer,
		"invulnerable": gs.bike_p2_invulnerable,
		"checkpoint": gs.bike_p2_checkpoint,
		"slipstream": gs.bike_p2_slipstream,
		"boosting": gs.bike_p2_boosting,
		"start_delay": gs.bike_p2_start_delay,
		"recovery_state": gs.bike_p2_recovery_state,
		"bike_x": gs.bike_p2_bike_x,
		"bike_z": gs.bike_p2_bike_z,
		"crash_revision": gs.bike_p2_crash_revision,
		"crash_strength": gs.bike_p2_crash_strength,
		"previous_z": gs.player2_z,
	}


func _write_rider(gs, player_index: int, rider: Dictionary) -> void:
	if player_index == 1:
		gs.player_x = float(rider.x)
		gs.player_y = float(rider.y)
		gs.player_z = float(rider.z)
		gs.bike_p1_speed = float(rider.speed)
		gs.bike_p1_stamina = float(rider.stamina)
		gs.bike_p1_steer = float(rider.steer)
		gs.bike_p1_wobble = float(rider.wobble)
		gs.bike_p1_fall_timer = float(rider.fall_timer)
		gs.bike_p1_invulnerable = float(rider.invulnerable)
		gs.bike_p1_checkpoint = int(rider.checkpoint)
		gs.bike_p1_slipstream = bool(rider.slipstream)
		gs.bike_p1_boosting = bool(rider.boosting)
		gs.bike_p1_start_delay = float(rider.start_delay)
		gs.bike_p1_recovery_state = str(rider.recovery_state)
		gs.bike_p1_bike_x = float(rider.bike_x)
		gs.bike_p1_bike_z = float(rider.bike_z)
		gs.bike_p1_crash_revision = int(rider.crash_revision)
		gs.bike_p1_crash_strength = float(rider.crash_strength)
	else:
		gs.player2_x = float(rider.x)
		gs.player2_y = float(rider.y)
		gs.player2_z = float(rider.z)
		gs.bike_p2_speed = float(rider.speed)
		gs.bike_p2_stamina = float(rider.stamina)
		gs.bike_p2_steer = float(rider.steer)
		gs.bike_p2_wobble = float(rider.wobble)
		gs.bike_p2_fall_timer = float(rider.fall_timer)
		gs.bike_p2_invulnerable = float(rider.invulnerable)
		gs.bike_p2_checkpoint = int(rider.checkpoint)
		gs.bike_p2_slipstream = bool(rider.slipstream)
		gs.bike_p2_boosting = bool(rider.boosting)
		gs.bike_p2_start_delay = float(rider.start_delay)
		gs.bike_p2_recovery_state = str(rider.recovery_state)
		gs.bike_p2_bike_x = float(rider.bike_x)
		gs.bike_p2_bike_z = float(rider.bike_z)
		gs.bike_p2_crash_revision = int(rider.crash_revision)
		gs.bike_p2_crash_strength = float(rider.crash_strength)


func _apply_slipstream(p1: Dictionary, p2: Dictionary) -> void:
	p1.slipstream = false
	p2.slipstream = false
	if str(p1.recovery_state) != RIDER_RIDING or str(p2.recovery_state) != RIDER_RIDING:
		return
	var gap: float = float(p2.z) - float(p1.z)
	var lateral_gap: float = absf(float(p2.x) - float(p1.x))
	if lateral_gap > 2.4:
		return
	if gap >= 2.0 and gap <= 12.0:
		p1.slipstream = true
	elif gap <= -2.0 and gap >= -12.0:
		p2.slipstream = true


func _step_rider(
	rider: Dictionary,
	dt: float,
	axis: Vector2,
	boost_pressed: bool,
	course_start_z: float
) -> void:
	rider.previous_z = float(rider.z)
	rider.invulnerable = maxf(0.0, float(rider.invulnerable) - dt)
	rider.start_delay = maxf(0.0, float(rider.start_delay) - dt)
	var recovery_state: String = str(rider.recovery_state)

	if recovery_state == RIDER_TUMBLING:
		rider.fall_timer = maxf(0.0, float(rider.fall_timer) - dt)
		rider.speed = 0.0
		rider.boosting = false
		rider.wobble = 1.0
		# Bike and rider stay one crash unit. MamaChariVisual writes the bike
		# rigid body's live position into both coordinates during the tumble.
		rider.x = float(rider.bike_x)
		rider.z = float(rider.bike_z)
		if is_zero_approx(float(rider.fall_timer)):
			rider.recovery_state = RIDER_RIDING
			rider.speed = 1.4
			rider.steer = 0.0
			rider.wobble = 0.18
			rider.invulnerable = RESPAWN_INVULNERABLE_SECONDS
			rider.crash_strength = 0.0
		return

	if float(rider.start_delay) > 0.0:
		rider.speed = 0.0
		rider.boosting = false
		return

	var throttle: float = maxf(0.0, axis.y)
	var braking: float = maxf(0.0, -axis.y)
	var can_boost: bool = boost_pressed and throttle > 0.1 and float(rider.stamina) > 0.01
	rider.boosting = can_boost
	if can_boost:
		rider.stamina = maxf(0.0, float(rider.stamina) - BOOST_DRAIN_PER_SECOND * dt)
	else:
		rider.stamina = minf(1.0, float(rider.stamina) + BOOST_RECOVERY_PER_SECOND * dt)

	var relative_z: float = float(rider.z) - course_start_z
	var uphill_factor: float = 0.78 if relative_z >= 185.0 and relative_z < 220.0 else 1.0
	var max_speed: float = BOOST_MAX_SPEED if can_boost else NORMAL_MAX_SPEED
	max_speed *= lerpf(0.90, 1.0, uphill_factor)
	if bool(rider.slipstream):
		max_speed += SLIPSTREAM_SPEED_BONUS

	if throttle > 0.0:
		var accel: float = ACCELERATION * throttle * uphill_factor
		if can_boost:
			accel *= 1.28
		if bool(rider.slipstream):
			accel += 1.1
		rider.speed = move_toward(float(rider.speed), max_speed, accel * dt)
	else:
		rider.speed = move_toward(float(rider.speed), 0.0, COAST_DECELERATION * dt)
	if braking > 0.0:
		rider.speed = move_toward(float(rider.speed), 0.0, BRAKE_DECELERATION * braking * dt)

	var speed_ratio: float = clampf(float(rider.speed) / BOOST_MAX_SPEED, 0.0, 1.0)
	var previous_steer: float = float(rider.steer)
	var steering_response: float = lerpf(7.0, 3.0, speed_ratio)
	rider.steer = move_toward(previous_steer, axis.x, steering_response * dt)
	var steer_delta: float = absf(float(rider.steer) - previous_steer)
	if steer_delta > 0.08 and speed_ratio > 0.45:
		rider.wobble = minf(1.0, float(rider.wobble) + steer_delta * speed_ratio * 1.8)
	rider.wobble = move_toward(float(rider.wobble), 0.0, 0.72 * dt)

	var lateral_speed: float = lerpf(5.3, 2.5, speed_ratio)
	rider.x = clampf(
		float(rider.x) + float(rider.steer) * lateral_speed * dt,
		-ROAD_HALF_WIDTH + 0.55,
		ROAD_HALF_WIDTH - 0.55
	)
	rider.z = float(rider.z) + float(rider.speed) * dt
	rider.bike_x = float(rider.x)
	rider.bike_z = float(rider.z)
	_update_checkpoint(rider, course_start_z)


func _update_checkpoint(rider: Dictionary, course_start_z: float) -> void:
	var relative_z: float = maxf(0.0, float(rider.z) - course_start_z)
	var checkpoint_index: int = int(rider.checkpoint)
	for index: int in range(CHECKPOINTS.size()):
		if relative_z >= CHECKPOINTS[index]:
			checkpoint_index = index
	rider.checkpoint = checkpoint_index


func _update_finish_time(gs, rider: Dictionary, dt: float, player_index: int) -> void:
	if str(rider.recovery_state) != RIDER_RIDING:
		return
	var current_finish_time: float = gs.p1_finish_time if player_index == 1 else gs.p2_finish_time
	if current_finish_time >= 0.0:
		return
	var previous_z: float = float(rider.previous_z)
	var current_z: float = float(rider.z)
	if current_z < gs.bike_finish_z or current_z <= previous_z:
		return
	var fraction: float = clampf(
		(gs.bike_finish_z - previous_z) / (current_z - previous_z),
		0.0,
		1.0
	)
	var crossing_time: float = maxf(0.0, gs.race_elapsed - dt + dt * fraction)
	if player_index == 1:
		gs.p1_finish_time = crossing_time
	else:
		gs.p2_finish_time = crossing_time


func _resolve_phase_finish(gs) -> void:
	var winner: int = 0
	var reason: String = "BIKE_PHASE_FINISH"
	if gs.p1_finish_time >= 0.0 and gs.p2_finish_time >= 0.0:
		var finish_gap: float = absf(gs.p1_finish_time - gs.p2_finish_time)
		if finish_gap <= PHOTO_FINISH_WINDOW:
			reason = "PHOTO_FINISH_SCORE_TIEBREAK"
			if gs.score > gs.player2_score:
				winner = 1
			elif gs.player2_score > gs.score:
				winner = 2
		else:
			winner = 1 if gs.p1_finish_time < gs.p2_finish_time else 2
	elif gs.p1_finish_time >= 0.0:
		winner = 1
	else:
		winner = 2
	gs.complete_bike_phase(winner, reason)
