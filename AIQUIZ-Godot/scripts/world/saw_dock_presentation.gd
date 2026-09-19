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
var _servo: AudioStreamPlayer3D
var _latch: AudioStreamPlayer3D
var _spindle: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
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
		"cover": ease_between(time, 1.45, 2.30),
		"lock": ease_between(time, 4.25, TRANSFER_START) * (1.0 - ease_between(time, READY_TIME, 6.30)),
		"bridge": bridge,
		"travel": TRAVEL * ease_between(time, TRANSFER_START, READY_TIME),
		"ship_offset": -APPROACH_DISTANCE * (1.0 - approach) - DEPARTURE_DISTANCE * ease_between(time, DEPARTURE_START, FINISH_TIME),
		"speed": 2.0 * APPROACH_DISTANCE / DOCKED_TIME * (1.0 - 3.0 * u * u + 2.0 * u * u * u) - DEPARTURE_DISTANCE * ease_speed(time, DEPARTURE_START, FINISH_TIME),
		"rock": (1.0 - ease_between(time, 1.65, DOCKED_TIME)) + ease_between(time, DEPARTURE_START, 9.75),
		"hydraulic_speed": ease_speed(time, RAISE_START, RAISE_END) + ease_speed(time, LOWER_START, LOWER_END),
		"shutter_speed": ease_speed(time, 1.45, 2.30),
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
	for i in range(24):
		slats.append(machinery.find_child("VSL_SLAT_%02d" % i, true, false) as Node3D)
	for side in ["L", "R"]:
		rods.append(machinery.find_child("VSL_ROD_" + side, true, false) as Node3D)
		locks.append(machinery.find_child("VSL_LOCK_" + side, true, false) as Node3D)
		bridges.append(machinery.find_child("VSL_BRIDGE_" + side, true, false) as Node3D)
	_servo = _audio("Mechanism", "dock_servo.wav", true, -20.0)
	_latch = _audio("RailLock", "dock_latch.wav", false, -12.0)
	_spindle = _audio("BladeMotor", "dock_spindle.wav", true, -26.0)
	_engine = _audio("VesselEngine", "vessel_engine.wav", true, -24.0)
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
	stop_audio()

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
	var before := elapsed
	total_elapsed += maxf(dt, 0.0)
	elapsed = minf(FINISH_TIME, elapsed + maxf(dt, 0.0))
	if before < TRANSFER_START and elapsed >= TRANSFER_START and _latch != null:
		_latch.play()
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
	for i in slats.size():
		var s := shutter_pose(i, float(p.cover))
		slats[i].position = Vector3(0.0, s.y, -s.x)
		slats[i].rotation.x = s.z
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

func update_audio(active: bool, spin_speed: float, blade_origin: Vector3 = Vector3.INF) -> void:
	if _servo == null: return
	if blade_origin.is_finite(): _spindle.global_position = blade_origin
	var ship_active := active and not has_departed()
	var p := pose_at(elapsed)
	var mechanism_speed := maxf(float(p.hydraulic_speed), float(p.shutter_speed) * 0.35)
	var mechanism_moving := ship_active and mechanism_speed > 0.002
	_loop(_servo, mechanism_moving)
	_servo.pitch_scale = 0.7 + minf(mechanism_speed * 0.32, 0.55)
	_servo.volume_db = lerpf(-34.0, -20.0, clampf(mechanism_speed, 0.0, 1.0))
	_loop(_engine, ship_active)
	var throttle := minf(absf(float(p.speed)) / 9.0, 1.0)
	_engine.pitch_scale = lerpf(0.65, 1.15, throttle)
	_engine.volume_db = lerpf(-32.0, -24.0, throttle)
	if ship != null:
		_engine.global_position = ship.to_global(Vector3(0.0, -5.0, 20.0))
		_servo.global_position = lift.global_position
		_latch.global_position = lift.global_position
	_loop(_spindle, active and spin_speed > 0.005)
	_spindle.pitch_scale = lerpf(0.5, 1.5, spin_speed)
	_spindle.volume_db = lerpf(-42.0, -26.0, spin_speed)
	if not active: _latch.stop()

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

func _loop(player: AudioStreamPlayer3D, active: bool) -> void:
	if active and not player.playing: player.play()
	elif not active and player.playing: player.stop()

func stop_audio() -> void:
	for player in [_servo, _latch, _spindle, _engine]:
		if player != null: player.stop()

func _audio(label: String, file: String, looped: bool, gain: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	# GameWorld processes while paused to handle its menu; the vessel's audio must not.
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	var stream := load("res://assets/audio/sfx/" + file).duplicate() as AudioStreamWAV
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Imported WAVs may be QOA/ADPCM; loop endpoints are sample frames, not bytes.
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = gain
	player.unit_size = 15.0
	player.max_distance = 55.0
	add_child(player)
	return player
