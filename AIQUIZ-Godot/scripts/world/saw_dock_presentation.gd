extends Node3D
class_name SawDockPresentation

## Presentation only. The ship never owns gameplay/replay position or collisions.
const MODEL_PATH := "res://assets/hazards/saw_service_vessel.glb"
const DOCKED_TIME := 2.25
const RAISE_START := 2.35
const RAISE_END := 4.20
const TRANSFER_START := 4.42
const READY_TIME := 6.20
const LOWER_START := 6.55
const LOWER_END := 8.40
const DEPARTURE_START := 9.00
const FINISH_TIME := 15.00
const CAMERA_FINISH_TIME := 9.00
const MENU_CAMERA_FINISH_TIME := FINISH_TIME
const LIFT_HEIGHT := 4.8
const TRAVEL := 4.8
const MENU_Z := 6.35
const APPROACH_DISTANCE := 10.0
const DEPARTURE_DISTANCE := 42.0
enum Phase {STOWED, APPROACHING, DOCKING, RAISING, TRANSFERRING, RETRACTING, LOWERING, DEPARTING, DEPLOYED}

var elapsed := 0.0
var total_elapsed := 0.0
var phase := Phase.STOWED
var animated := false
var final_z := SawChaseState.INITIAL_Z
var direction := 1.0
var machinery: Node3D
var ship: Node3D
var lift: Node3D
var slats: Array[Node3D] = []
var rods: Array[Node3D] = []
var locks: Array[Node3D] = []
var bridges: Array[Node3D] = []
var _wakes: Array[MeshInstance3D] = []
var _wake_material: ShaderMaterial

static func ease_between(time: float, a: float, b: float) -> float:
	var u := clampf((time - a) / (b - a), 0.0, 1.0)
	return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))

static func ease_speed(time: float, a: float, b: float) -> float:
	var u := clampf((time - a) / (b - a), 0.0, 1.0)
	return 30.0 * u * u * (u - 1.0) * (u - 1.0) / (b - a)

static func pose_at(time: float) -> Dictionary:
	# The arriving ship is already cruising, then decelerates into a level rest.
	var u := clampf(time / DOCKED_TIME, 0.0, 1.0)
	var approach := 2.0 * u - 2.0 * u * u * u + u * u * u * u
	var bridge := ease_between(time, RAISE_END, 4.40) * (1.0 - ease_between(time, 6.30, 6.50))
	return {
		"lift": ease_between(time, RAISE_START, RAISE_END) * (1.0 - ease_between(time, LOWER_START, LOWER_END)),
		"cover": 1.0, # Retained pose field: the lift bay is permanently open.
		"lock": ease_between(time, 4.25, TRANSFER_START) * (1.0 - ease_between(time, READY_TIME, 6.30)),
		"bridge": bridge,
		"travel": TRAVEL * ease_between(time, TRANSFER_START, READY_TIME),
		"ship_offset": -APPROACH_DISTANCE * (1.0 - approach) - DEPARTURE_DISTANCE * ease_between(time, DEPARTURE_START, FINISH_TIME),
		"speed": 2.0 * APPROACH_DISTANCE / DOCKED_TIME * (1.0 - 3.0 * u * u + 2.0 * u * u * u) - DEPARTURE_DISTANCE * ease_speed(time, DEPARTURE_START, FINISH_TIME),
		"rock": (1.0 - ease_between(time, 1.65, DOCKED_TIME)) + ease_between(time, DEPARTURE_START, 9.75),
		"shutter_speed": 0.0,
	}

static func shutter_pose(index: int, amount: float) -> Vector3:
	var d := index * 0.15 + amount * 4.60
	if d <= 4.45:
		return Vector3(1.8 - d, 0.02, 0.0)
	var angle := (d - 4.45) / 0.44
	var radius := 0.46 - 0.006 * angle
	return Vector3(-2.65 - radius * sin(angle), -0.44 + radius * cos(angle), angle)

func setup(preview: bool, play_entrance: bool) -> void:
	final_z = MENU_Z if preview else SawChaseState.INITIAL_Z
	direction = -1.0 if preview else 1.0
	top_level = true
	position = Vector3(0.0, StageConstants.FLOOR_TOP_Y, final_z - direction * TRAVEL)
	machinery = (load(MODEL_PATH) as PackedScene).instantiate()
	machinery.rotation.y = PI if direction > 0.0 else 0.0
	add_child(machinery)
	ship = machinery.find_child("VSL_ROOT", true, false) as Node3D
	lift = machinery.find_child("VSL_LIFT", true, false) as Node3D
	# Remove the complete shutter assembly, including its rolled-up slats.
	var cover := machinery.find_child("VSL_COVER",true,false) as Node3D
	if cover != null: cover.free()
	for side in ["L", "R"]:
		rods.append(machinery.find_child("VSL_ROD_" + side, true, false) as Node3D)
		locks.append(machinery.find_child("VSL_LOCK_" + side, true, false) as Node3D)
		bridges.append(machinery.find_child("VSL_BRIDGE_" + side, true, false) as Node3D)
	_create_wake()
	if play_entrance: begin()
	else: restore_deployed()

func begin() -> void:
	elapsed = 0.0
	total_elapsed = 0.0
	animated = true
	phase = Phase.STOWED
	apply_pose()

func restore_deployed() -> void:
	elapsed = FINISH_TIME
	total_elapsed = FINISH_TIME
	animated = false
	phase = Phase.DEPLOYED
	apply_pose()

func is_deployed() -> bool:
	return elapsed >= READY_TIME

func has_departed() -> bool:
	return not animated or elapsed >= FINISH_TIME

func framing_weight() -> float:
	return 1.0 - ease_between(total_elapsed, READY_TIME, CAMERA_FINISH_TIME) if animated else 0.0

func menu_framing_weight() -> float:
	return 1.0 - ease_between(total_elapsed, DEPARTURE_START, MENU_CAMERA_FINISH_TIME) if animated else 0.0

func wheel_distance() -> float:
	return float(pose_at(elapsed).travel) if animated else 0.0

func carriage_position() -> Vector3:
	if is_deployed():
		return Vector3(0.0, StageConstants.FLOOR_TOP_Y, final_z)
	var p := pose_at(elapsed)
	var height := -LIFT_HEIGHT * (1.0 - float(p.lift))
	if ship != null:
		return ship.global_transform * Vector3(0.0, height, -float(p.travel))
	return Vector3(0.0, StageConstants.FLOOR_TOP_Y + height, final_z - direction * (TRAVEL - float(p.travel) - float(p.ship_offset)))

func carriage_basis() -> Basis:
	if is_deployed() or ship == null:
		return Basis.IDENTITY
	# Transfer the small sea motion without changing the model's existing facing.
	return ship.global_basis * Basis(Vector3.UP, PI if direction > 0.0 else 0.0).inverse()

func advance(dt: float) -> void:
	if not animated: return
	total_elapsed += maxf(dt, 0.0)
	elapsed = minf(FINISH_TIME, elapsed + maxf(dt, 0.0))
	if elapsed < DOCKED_TIME: phase = Phase.APPROACHING
	elif elapsed < RAISE_START: phase = Phase.DOCKING
	elif elapsed < TRANSFER_START: phase = Phase.RAISING
	elif elapsed < READY_TIME: phase = Phase.TRANSFERRING
	elif elapsed < LOWER_START: phase = Phase.RETRACTING
	elif elapsed < DEPARTURE_START: phase = Phase.LOWERING
	elif elapsed < FINISH_TIME: phase = Phase.DEPARTING
	else: phase = Phase.DEPLOYED
	apply_pose()

func apply_pose() -> void:
	if machinery == null: return
	var p := pose_at(elapsed)
	ship.visible = not has_departed()
	ship.position = Vector3(0.0, 0.055 * sin(elapsed * 1.7) * float(p.rock), -float(p.ship_offset))
	ship.rotation = Vector3(0.002 * sin(elapsed * 1.3) * float(p.rock), 0.0, 0.0018 * sin(elapsed * 1.1) * float(p.rock))
	lift.position.y = -LIFT_HEIGHT * (1.0 - float(p.lift))
	for i in rods.size():
		rods[i].scale.y = 0.12 + LIFT_HEIGHT * float(p.lift)
		locks[i].position.x = (-1.0 if i == 0 else 1.0) * (12.44 - 0.25 * float(p.lock))
		bridges[i].scale.z = maxf(0.001, float(p.bridge))
	if _wake_material != null:
		_wake_material.set_shader_parameter("phase", elapsed)
		_wake_material.set_shader_parameter("strength", minf(absf(float(p.speed)) / 6.0, 1.0))
		for wake in _wakes:
			wake.visible = ship.visible
			wake.position.z = -float(p.ship_offset) + (29.0 if float(p.speed) >= 0.0 else -5.5)
			wake.rotation.y = 0.0 if float(p.speed) >= 0.0 else PI

func _create_wake() -> void:
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = load("res://shaders/saw_vessel_wake.gdshader")
	for side in [-1.0, 1.0]:
		var wake := MeshInstance3D.new()
		wake.name = "VesselWakeLeft" if side < 0.0 else "VesselWakeRight"
		var plane := PlaneMesh.new()
		plane.size = Vector2(3.2, 10.0)
		wake.mesh = plane
		wake.material_override = _wake_material
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		machinery.add_child(wake)
		wake.position = Vector3(side * 10.6, StageConstants.OCEAN_SURFACE_Y - StageConstants.FLOOR_TOP_Y + 0.07, 0.0)
		_wakes.append(wake)
