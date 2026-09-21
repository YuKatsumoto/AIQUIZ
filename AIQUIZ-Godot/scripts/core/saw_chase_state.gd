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
