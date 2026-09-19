extends RefCounted
class_name SawChaseState

## Authoritative, render-independent movement in conveyor-local coordinates.
const BLADE_RADIUS := 1.45
const BLADE_PITCH := 3.0
const INITIAL_Z := -10.85
const BLADE_RPM := 90.0
const SPINUP_SECONDS := 3.99
const WALL_COLLISION_LAYER := 16
const CUT_SCATTER_DELAY := 1.15
const WHEEL_RADIUS := 0.18
var enabled := false
var local_z := INITIAL_Z
var elapsed := 0.0
var wheel_distance := 0.0

func reset() -> void:
	enabled = false
	local_z = INITIAL_Z
	elapsed = 0.0
	wheel_distance = 0.0

func advance(dt: float, leader_z: float, follow_distance: float, max_speed: float, grace: float = 0.0) -> void:
	enabled = true
	elapsed += maxf(dt, 0.0)
	if not is_finite(leader_z):
		return
	var target := maxf(local_z, leader_z - follow_distance - BLADE_RADIUS)
	var motion_dt := minf(maxf(dt, 0.0), maxf(elapsed - grace, 0.0))
	var next_z := move_toward(local_z, target, maxf(max_speed, 0.0) * motion_dt)
	wheel_distance += next_z - local_z
	local_z = next_z

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
