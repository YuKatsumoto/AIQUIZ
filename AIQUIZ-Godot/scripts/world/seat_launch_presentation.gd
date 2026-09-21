extends Node3D
class_name SeatLaunchPresentation

## Owns only the exported chair root and the mascot pose. The station keeps moving
## with its dock; this presentation never takes the camera or gameplay controls.
const EffectsScript := preload("res://scripts/world/seat_launch_effects.gd")
const HarnessScript := preload("res://scripts/world/seat_launch_harness.gd")
const HANDOFF := &"chair_transfer_pending"
const BELT_SECONDS := 2.6
const LATCH_TIME := 1.95
const LAND_SECONDS := 1.8
const SETTLE_SECONDS := 0.3
const RELEASE_SECONDS := 1.0
const LAUNCH_SECONDS := 1.6
const ARRIVAL_HEIGHT := 16.0
enum Phase { IDLE, BUCKLING, ARMED, LAUNCHING, AWAY, WAITING_SOCKET, LANDING, SETTLING, UNBUCKLING }

var phase := Phase.IDLE
var elapsed := 0.0
var belt_extension := 0.0
var height := 0.0
var launch_frame := -1
var latch_count := 0
var landing_error := -1.0
var operator: Node3D
var flight_root: Node3D
var socket: Node3D
var kit: Node3D
var harness: Node3D
var effects: SeatLaunchEffects
var flight_rest := Transform3D.IDENTITY
var applying_base := false
var _click: AudioStreamPlayer3D
var _jet: AudioStreamPlayer3D
var _base_sample: Dictionary = {}
var _clicked := false

static func eligible(gs: QuizGameState, online: bool = false) -> bool:
	# The transport flag is initialized by GameWorld, after the menu departure.
	return not online and not gs.is_replay and gs.num_players == 2 and gs.mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS]

static func clear_handoff() -> void:
	QuizManager.remove_meta(HANDOFF)

static func consume_handoff(gs: QuizGameState, online: bool, retry: bool) -> bool:
	var pending := bool(QuizManager.get_meta(HANDOFF, false))
	clear_handoff()
	return pending and eligible(gs, online) and not retry

static func launch_height(time: float) -> float:
	# Gentle lift-off followed by a rocket-like accelerating climb.
	return 2.0 * time + 10.0 * time * time + 7.0 * time * time * time

static func landing_height(time: float) -> float:
	var u := clampf(time / LAND_SECONDS, 0.0, 1.0)
	return ARRIVAL_HEIGHT * (1.0 - u) * (1.0 - u) * (1.0 + .3 * u)

static func belt_ease(start: float, end: float, time: float) -> float:
	# Zero velocity AND acceleration at both ends prevents a mechanical jerk
	# when the ribbon begins paying out, locks, tightens, or retracts.
	var u := clampf((time - start) / (end - start), 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

func setup(seat: Node3D) -> void:
	operator = seat
	flight_root = operator.station.find_child("OP_SeatFlightRoot", true, false) as Node3D
	socket = operator.station.find_child("OP_SeatSocket", true, false) as Node3D
	kit = flight_root.find_child("SL_Kit", true, false) as Node3D
	# The original lap assembly stays in the source asset; replace its runtime
	# presentation without touching the artist's Blender work in progress.
	for key in ["SL_LapWebbing", "SL_Tongue", "SL_Reel", "SL_Receiver"]:
		(kit.find_child(key, true, false) as Node3D).hide()
	harness = HarnessScript.new()
	harness.name = "TwinShoulderHarness"
	kit.add_child(harness)
	harness.setup()
	flight_rest = flight_root.transform
	effects = EffectsScript.new()
	effects.name = "ChairRocketEffects"
	# World-space smoke must remain visible after the flying chair is hidden.
	operator.station.add_child(effects)
	effects.setup(kit, socket)
	_click = AudioStreamPlayer3D.new()
	_click.bus = "SFX"
	_click.stream = preload("res://assets/hazards/saw_operator/chair_latch.wav")
	_click.unit_size = 12.0
	_click.volume_db = -5.0
	kit.add_child(_click)
	_click.position = Vector3(0.0, 1.34, .07)
	_jet = AudioStreamPlayer3D.new()
	_jet.bus = "SFX"
	_jet.stream = preload("res://assets/hazards/saw_operator/chair_rocket.wav")
	_jet.unit_size = 20.0
	_jet.volume_db = -12.0
	kit.add_child(_jet)
	_set_belt(0.0)
	set_process(false)

func owns_pose() -> bool:
	return phase != Phase.IDLE

func is_buckled() -> bool:
	return phase == Phase.ARMED

func is_arriving() -> bool:
	return phase in [Phase.WAITING_SOCKET, Phase.LANDING, Phase.SETTLING, Phase.UNBUCKLING]

func begin_buckle() -> void:
	if phase != Phase.IDLE: return
	_base_sample = operator.last_sample.duplicate(true)
	phase = Phase.BUCKLING
	elapsed = 0.0
	_clicked = false
	latch_count = 0
	flight_root.visible = true
	set_process(true)
	_apply_pose()

func launch() -> void:
	if not is_buckled(): return
	phase = Phase.LAUNCHING
	elapsed = 0.0
	launch_frame = Engine.get_process_frames()
	QuizManager.set_meta(HANDOFF, true)
	_apply_pose()
	effects.ignite()
	_jet.play()

func skip_departure() -> void:
	# Also accepts a skip before the dock is ready and before buckling begins.
	phase = Phase.AWAY
	height = 0.0
	_set_belt(1.0)
	flight_root.visible = false
	QuizManager.set_meta(HANDOFF, true)
	effects.stop_immediately()
	_jet.stop()
	set_process(false)

func begin_arrival() -> void:
	phase = Phase.WAITING_SOCKET
	elapsed = 0.0
	height = ARRIVAL_HEIGHT
	flight_root.visible = false
	_set_belt(1.0)
	set_process(false)

func advance_arrival(dt: float, socket_ready: bool, skip: bool = false) -> void:
	if not is_arriving(): return
	if skip:
		finish_arrival()
		return
	if SceneTransition.is_transitioning() or dt <= 0.0: return
	if phase == Phase.WAITING_SOCKET:
		if not socket_ready: return
		phase = Phase.LANDING
		flight_root.visible = true
		elapsed = 0.0
		_base_sample = operator.last_sample.duplicate(true)
	else:
		elapsed += dt
	if phase == Phase.LANDING and elapsed >= LAND_SECONDS:
		elapsed -= LAND_SECONDS
		phase = Phase.SETTLING
		effects.touchdown()
		_jet.stop()
		_click.pitch_scale = .70
		_click.play()
	if phase == Phase.SETTLING and elapsed >= SETTLE_SECONDS:
		elapsed -= SETTLE_SECONDS
		phase = Phase.UNBUCKLING
	if phase == Phase.UNBUCKLING and elapsed >= RELEASE_SECONDS:
		finish_arrival()
		return
	_apply_pose()
	if phase == Phase.LANDING:
		var thrust := smoothstep(.35, 1.25, elapsed)
		effects.set_thrust(thrust)
		if thrust > .1 and not _jet.playing: _jet.play()

func finish_arrival() -> void:
	phase = Phase.IDLE
	height = 0.0
	flight_root.transform = flight_rest
	flight_root.visible = true
	_set_belt(0.0)
	effects.set_thrust(0.0)
	_jet.stop()
	operator.apply_sample(operator.last_sample)
	landing_error = flight_root.global_position.distance_to(socket.global_position)
	set_process(false)

func reset() -> void:
	phase = Phase.IDLE
	elapsed = 0.0
	height = 0.0
	_clicked = false
	flight_root.transform = flight_rest
	flight_root.visible = true
	_set_belt(0.0)
	effects.stop_immediately()
	_jet.stop()
	_click.stop()
	set_process(false)
	if not operator.last_sample.is_empty(): operator.apply_sample(operator.last_sample)

func _process(dt: float) -> void:
	advance_departure(dt)

func advance_departure(dt: float) -> void:
	if phase not in [Phase.BUCKLING, Phase.ARMED, Phase.LAUNCHING]: return
	elapsed += maxf(dt, 0.0)
	if phase == Phase.BUCKLING:
		if elapsed >= LATCH_TIME and not _clicked:
			_clicked = true
			latch_count += 1
			_click.pitch_scale = 1.0
			_click.play()
		if elapsed >= BELT_SECONDS: phase = Phase.ARMED
	elif phase == Phase.LAUNCHING and elapsed >= LAUNCH_SECONDS:
		phase = Phase.AWAY
		flight_root.visible = false
		effects.set_thrust(0.0)
		_jet.stop()
		set_process(false)
		return
	_apply_pose()

func _apply_pose() -> void:
	if _base_sample.is_empty(): _base_sample = operator.last_sample.duplicate(true)
	applying_base = true
	operator.apply_sample(_base_sample)
	applying_base = false
	var extension := 1.0
	var buckle_time := BELT_SECONDS
	if phase == Phase.BUCKLING:
		buckle_time = elapsed
		extension = belt_ease(.30, 1.12, elapsed)
	elif phase == Phase.UNBUCKLING:
		extension = 1.0 - belt_ease(.12, .90, elapsed)
	height = launch_height(elapsed) if phase == Phase.LAUNCHING else (landing_height(elapsed) if phase == Phase.LANDING else 0.0)
	if phase == Phase.SETTLING:
		height = -.035 * sin(PI * clampf(elapsed / SETTLE_SECONDS, 0.0, 1.0))
	_set_belt(extension)
	# Solve the pose at its rest origin, then move the whole chair and rig together.
	# Fixed control contact targets can never drag the airborne hands back down.
	if phase in [Phase.BUCKLING, Phase.ARMED]:
		_pose_buckle(buckle_time)
	else:
		_pose_flight(1.0 - smoothstep(.65, 1.0, elapsed) if phase == Phase.UNBUCKLING else 1.0)
	flight_root.transform = flight_rest
	flight_root.position.y += height
	operator.skeleton.force_update_all_bone_transforms()
	effects.follow_nozzles()

func _set_belt(amount: float) -> void:
	belt_extension = clampf(amount, 0.0, 1.0)
	# Most slack closes progressively as the tongue descends. The remaining
	# bow settles after docking instead of snapping the entire belt at once.
	var tension := .65 * belt_ease(.75, LATCH_TIME, elapsed) + .35 * belt_ease(LATCH_TIME, BELT_SECONDS - .10, elapsed) if phase == Phase.BUCKLING else 1.0
	var simulation_time := elapsed if phase == Phase.BUCKLING else (BELT_SECONDS if phase == Phase.ARMED else -1.0)
	harness.set_extension(belt_extension, tension, simulation_time)

func _pose_buckle(time: float) -> void:
	# Clear both flight paths first, then bring the hands to the lap after lock.
	var clear_weight := smoothstep(0.0, .30, time)
	var settle := smoothstep(LATCH_TIME + .15, BELT_SECONDS, time)
	for side in ["L", "R"]:
		var sign_x := 1.0 if side == "L" else -1.0
		var grip: Vector3 = operator._control("OP_GripContact_" + side).global_position
		var clear: Vector3 = kit.to_global(Vector3(sign_x * .62, 1.60, .13))
		var lap: Vector3 = kit.to_global(Vector3(sign_x * .26, 1.52, .17))
		operator.pose_belt_hand(side, grip.lerp(clear, clear_weight).lerp(lap, settle), clear_weight)
		var foot: Vector3 = operator._control("OP_FootContact_" + side).global_position
		operator._pose_leg(side, foot.lerp(kit.to_global(Vector3(sign_x * .18, 1.15, .42)), settle))

func _pose_flight(weight: float) -> void:
	if weight <= 0.0: return
	for side in ["L", "R"]:
		var sign_x := 1.0 if side == "L" else -1.0
		var grip: Vector3 = operator._control("OP_GripContact_" + side).global_position
		var lap: Vector3 = kit.to_global(Vector3(sign_x * .26, 1.52, .17))
		operator.pose_belt_hand(side, grip.lerp(lap, weight), weight)
		var foot: Vector3 = operator._control("OP_FootContact_" + side).global_position
		operator._pose_leg(side, foot.lerp(kit.to_global(Vector3(sign_x * .18, 1.15, .42)), weight))
