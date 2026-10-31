extends RefCounted
class_name SawChaseState

## Authoritative, render-independent movement in conveyor-local coordinates.
const BLADE_RADIUS := 1.45
const BLADE_PITCH := 3.0
const INITIAL_Z := -10.85
const BLADE_RPM := 90.0
const SPINUP_SECONDS := 3.99
const STOP_SECONDS := 2.0
const WALL_COLLISION_LAYER := 16
const CUT_SCATTER_DELAY := 1.15
const WHEEL_RADIUS := 0.18
## The catch lift switches between a few fixed heights (0, 1.2, 2.4, 3.6 m) instead of
## tracking the runner's height continuously.
const LIFT_STAGE_STEP := 1.2
const LIFT_STAGE_COUNT := 4
const LIFT_STAGE_HYSTERESIS := 0.15 # in steps: a stage holds until the reach clearly passes the midpoint
const LIFT_STAGE_SPEED := 12.0 # m/s a blade travels from one stage to the next (one step in 0.1 s)
const LIFT_CATCH_MARGIN := 0.5 # m a just-caught runner may sit outside the blade after the swept contact test
var enabled := false
var local_z := INITIAL_Z
var elapsed := 0.0
var wheel_distance := 0.0
var velocity := 0.0
var stopping := false
var stop_elapsed := 0.0
var _stop_velocity := 0.0

func reset() -> void:
	enabled = false
	local_z = INITIAL_Z
	elapsed = 0.0
	wheel_distance = 0.0
	velocity = 0.0
	stopping = false
	stop_elapsed = 0.0
	_stop_velocity = 0.0

func advance(dt: float, leader_z: float, follow_distance: float, max_speed: float, grace: float = 0.0) -> void:
	enabled = true
	elapsed += maxf(dt, 0.0)
	if not is_finite(leader_z):
		velocity = 0.0
		return
	var target := maxf(local_z, leader_z - follow_distance - BLADE_RADIUS)
	var motion_dt := minf(maxf(dt, 0.0), maxf(elapsed - grace, 0.0))
	var next_z := move_toward(local_z, target, maxf(max_speed, 0.0) * motion_dt)
	velocity = (next_z - local_z) / dt if dt > 0.0 else velocity
	wheel_distance += next_z - local_z
	local_z = next_z

func begin_stop() -> void:
	if stopping: return
	stopping = true
	stop_elapsed = 0.0
	_stop_velocity = velocity

func stop_speed_ratio() -> float:
	return 1.0 - smoothstep(0.0, STOP_SECONDS, stop_elapsed) if stopping else 1.0

static func _stop_integral(time: float) -> float:
	var u := clampf(time / STOP_SECONDS, 0.0, 1.0)
	return STOP_SECONDS * (u - u * u * u + 0.5 * u * u * u * u)

func advance_stop(dt: float) -> void:
	if not stopping: return
	var previous := stop_elapsed
	stop_elapsed = minf(STOP_SECONDS, stop_elapsed + maxf(dt, 0.0))
	# Integrate the speed curve so spin and wheel travel agree at every FPS.
	var motor_dt := _stop_integral(stop_elapsed) - _stop_integral(previous)
	elapsed += motor_dt
	var distance := _stop_velocity * motor_dt
	local_z += distance
	wheel_distance += distance
	velocity = _stop_velocity * stop_speed_ratio()

## Stage index for a continuous catch reach. With current >= 0 the stage only changes once the
## reach is past the midpoint by LIFT_STAGE_HYSTERESIS, so a hovering runner doesn't make it flicker.
static func lift_stage(reach: float, current: int = -1) -> int:
	var level := reach / LIFT_STAGE_STEP
	var stage := clampi(roundi(level), 0, LIFT_STAGE_COUNT - 1)
	if current >= 0 and stage != current and absf(level - current) < 0.5 + LIFT_STAGE_HYSTERESIS:
		return current
	return stage

## Height a blade rises to for a jumping runner. Contact ignores height, so death is certain only
## once the runner's footprint overlaps the blade (clearance <= 0); before that the blade stays down.
## A runner caught this frame may already be a hair past the blade after the swept test, hence the margin.
static func catch_reach(player_y: float, clearance: float, caught: bool) -> float:
	if player_y <= 0.05:
		return 0.0
	if clearance > (LIFT_CATCH_MARGIN if caught else 0.0):
		return 0.0
	return player_y + 0.9

func clearance(point: Vector2, body_radius: float) -> float:
	var nearest := INF
	for index in range(8):
		var center := Vector2((index - 3.5) * BLADE_PITCH, local_z)
		nearest = minf(nearest, point.distance_to(center) - BLADE_RADIUS - body_radius)
	return maxf(0.0, nearest)

func swept_contact(from: Vector2, to: Vector2, previous_z: float, body_radius: float) -> bool:
	var radius := BLADE_RADIUS + body_radius
	for index in range(8):
		var x := (index - 3.5) * BLADE_PITCH
		var a := from - Vector2(x, previous_z)
		var b := to - Vector2(x, local_z)
		var segment := b - a
		var t := 0.0 if segment.length_squared() < 0.000001 else clampf(-a.dot(segment) / segment.length_squared(), 0.0, 1.0)
		if (a + segment * t).length_squared() <= radius * radius:
			return true
	return false
