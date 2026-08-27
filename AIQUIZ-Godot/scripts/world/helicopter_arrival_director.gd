extends Node3D
class_name HelicopterArrivalDirector

const HELICOPTER_GLB := "res://assets/vehicles/helicopter/helicopter_drop.glb"
const APPROACH_DURATION := 4.40
const HOVER_BEFORE_FIRST_DROP := 0.70
const P2_DROP_DELAY := 0.30
const DEPART_DURATION := 4.80
const MIN_RAGDOLL_DISPLAY := 0.45
const FAILSAFE_SECONDS := 22.0
const RELEASE_HEIGHT := 8.0
const HELICOPTER_ABOVE_RELEASE := 1.25
const OFFSCREEN_DISTANCE := 28.0
const EXIT_RISE_HEIGHT := 16.0
const OCEAN_SIDE_HOVER_HEIGHT := 7.60
const OCEAN_SIDE_APPROACH_RISE := 7.0
const BELT_EDGE_LANDING_INSET := 1.20
const OCEAN_SIDE_INWARD_DRIFT := 3.20
const HATCH_OPEN_LEAD := 0.55
const HATCH_OPEN_DURATION := 0.45
const HATCH_CLOSE_DELAY := 0.55
const HATCH_CLOSE_DURATION := 0.50
const HATCH_OPEN_ANGLE := deg_to_rad(78.0)
const DEPART_AFTER_DROP := 1.00
const DROP_PRESENTATION_PITCH := deg_to_rad(4.0)
const DEPART_CLIMB_PITCH := deg_to_rad(-6.0)
const MAIN_ROTOR_SPEED := 28.0
const TAIL_ROTOR_SPEED := 42.0
const ROTOR_FADE_SECONDS := 0.45

var _game_state: QuizGameState = null
var _player_controller: PlayerController = null
var _camera_controller: Node3D = null
var _helicopters: Array[Dictionary] = []
var _impact_players: Array[AudioStreamPlayer3D] = []
var _rotor_stream: AudioStreamWAV = null
var _impact_stream: AudioStreamWAV = null
var _phase := "idle"
var _phase_elapsed := 0.0
var _total_elapsed := 0.0
var _start_locked := false
var _cancelled := false
var _prewarm_visible := false


func setup(
	game_state: QuizGameState,
	player_controller: PlayerController,
	camera_controller: Node3D
) -> void:
	_game_state = game_state
	_player_controller = player_controller
	_camera_controller = camera_controller
	if _game_state == null or _player_controller == null or _camera_controller == null:
		_skip_missing_asset("arrival dependencies are unavailable")
		return
	if not ResourceLoader.exists(HELICOPTER_GLB):
		_skip_missing_asset("%s has not been supplied yet" % HELICOPTER_GLB)
		return

	var packed := ResourceLoader.load(HELICOPTER_GLB) as PackedScene
	if packed == null:
		_skip_missing_asset("the helicopter GLB could not be loaded")
		return
	_rotor_stream = _build_rotor_loop()
	_impact_stream = _build_landing_impact()
	var helicopter_count := 2 if _game_state.num_players >= 2 else 1
	for player_index: int in range(1, helicopter_count + 1):
		var info := _instantiate_helicopter(packed, player_index)
		if info.is_empty():
			_skip_missing_asset(
				"the GLB must contain BodyPaint, MainRotor, and TailRotor"
			)
			return
		_helicopters.append(info)

	_player_controller.prepare_intro_arrival(helicopter_count)
	_start_locked = true
	_phase = "waiting_camera"
	set_process(true)
	call_deferred("_begin_after_reveal_and_camera")


func begin_render_prewarm() -> Dictionary:
	if _helicopters.is_empty():
		return {"ready": false, "reason": "helicopter_asset_missing"}
	_prewarm_visible = true
	for info: Dictionary in _helicopters:
		var holder := info.get("holder") as Node3D
		if holder != null:
			holder.visible = true
	if _player_controller != null:
		_player_controller.prewarm_intro_drop_ragdolls(_helicopters.size())
	return {"ready": true, "helicopters": _helicopters.size()}


func end_render_prewarm() -> void:
	_prewarm_visible = false
	if _phase == "waiting_camera":
		for info: Dictionary in _helicopters:
			var holder := info.get("holder") as Node3D
			if holder != null:
				holder.visible = false


func is_start_locked() -> bool:
	return _start_locked


func is_active() -> bool:
	return _start_locked and _phase not in ["idle", "complete", "cancelled"]


func cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	_phase = "cancelled"
	_start_locked = false
	if _player_controller != null:
		_player_controller.cancel_intro_drops()
	_cleanup_helicopters(true)
	set_process(false)


func _exit_tree() -> void:
	cancel()


func _process(delta: float) -> void:
	_spin_rotors(delta)
	if _phase != "arrival":
		return
	_phase_elapsed += delta
	_total_elapsed += delta
	if _total_elapsed >= FAILSAFE_SECONDS:
		_fail_safe("arrival exceeded %.1f seconds" % FAILSAFE_SECONDS)
		return
	_update_timeline()


func _begin_after_reveal_and_camera() -> void:
	while is_inside_tree() and not _cancelled and SceneTransition.is_transitioning():
		await get_tree().process_frame
	if not is_inside_tree() or _cancelled:
		return
	if _camera_controller.has_method("wait_for_entry_blend"):
		await _camera_controller.wait_for_entry_blend()
	if not is_inside_tree() or _cancelled:
		return
	if _game_state.game_state not in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]:
		cancel()
		return

	_prepare_flight_paths()
	for info: Dictionary in _helicopters:
		var holder := info.get("holder") as Node3D
		var audio := info.get("audio") as AudioStreamPlayer3D
		if holder != null:
			holder.visible = true
		if audio != null:
			audio.play()
	_phase = "arrival"
	_phase_elapsed = 0.0
	_total_elapsed = 0.0


func _prepare_flight_paths() -> void:
	var player_pair_center_x := 0.0
	var player_pair_side := 1.0
	if _helicopters.size() >= 2:
		player_pair_center_x = (_game_state.player_x + _game_state.player2_x) * 0.5
		player_pair_side = signf(_game_state.player_x - _game_state.player2_x)
		if is_zero_approx(player_pair_side):
			player_pair_side = 1.0

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var ground := Vector3(
			_game_state.player_x if player_index == 1 else _game_state.player2_x,
			StageConstants.FLOOR_TOP_Y,
			_game_state.player_local_z if player_index == 1 else _game_state.player2_local_z
		)
		var release_x := ground.x
		var is_ocean_side_drop := _helicopters.size() >= 2
		var player_side := 1.0
		if is_ocean_side_drop:
			player_side = player_pair_side if player_index == 1 else -player_pair_side
			release_x = player_pair_center_x + player_side * (
				StageConstants.FLOOR_HALF_WIDTH - BELT_EDGE_LANDING_INSET
			)
		var release := Vector3(release_x, ground.y + RELEASE_HEIGHT, ground.z)
		var hover := release + Vector3.UP * HELICOPTER_ABOVE_RELEASE
		if is_ocean_side_drop:
			# Approach from the ocean, then hover over the belt's ocean-side edge
			# so a gravity drop lands on the floor instead of in the water.
			hover = Vector3(release_x, ground.y + OCEAN_SIDE_HOVER_HEIGHT, ground.z)
			release = hover
		var side_origin := release.x - player_pair_center_x if is_ocean_side_drop else ground.x
		var side := signf(side_origin) if absf(side_origin) > 0.1 else -1.0
		var approach_rise := OCEAN_SIDE_APPROACH_RISE if is_ocean_side_drop else 3.0
		var start := hover + Vector3(side * OFFSCREEN_DISTANCE, approach_rise, 0.0)
		var exit := hover + Vector3(side * OFFSCREEN_DISTANCE, EXIT_RISE_HEIGHT, 0.0)
		var approach_direction := (hover - start).normalized()
		var hover_direction := Vector3(-side, 0.0, 0.0)
		info["ground"] = ground
		info["release"] = release
		info["hover"] = hover
		info["start"] = start
		info["exit"] = exit
		info["direction"] = hover_direction
		info["approach_direction"] = approach_direction
		info["ocean_side_drop"] = is_ocean_side_drop
		info["inward_direction"] = Vector3(-player_side, 0.0, 0.0) if is_ocean_side_drop else Vector3.ZERO
		info["world_velocity"] = Vector3.ZERO
		var holder := info.get("holder") as Node3D
		_set_hatch_openness(info, 0.0)
		_set_flight_transform(holder, start, approach_direction, 0.10 * -side, 0.0)
		if holder != null:
			info["last_position"] = holder.global_position


func _update_timeline() -> void:
	var approach_weight := clampf(_phase_elapsed / APPROACH_DURATION, 0.0, 1.0)
	var eased_approach := smoothstep(0.0, 1.0, approach_weight)
	var timeline := maxf(0.0, _phase_elapsed - APPROACH_DURATION)
	var latest_drop_time := HOVER_BEFORE_FIRST_DROP

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var drop_time := HOVER_BEFORE_FIRST_DROP + (P2_DROP_DELAY if player_index == 2 else 0.0)
		latest_drop_time = maxf(latest_drop_time, drop_time)
		var start: Vector3 = info.get("start", Vector3.ZERO)
		var hover: Vector3 = info.get("hover", Vector3.ZERO)
		var exit: Vector3 = info.get("exit", start)
		var direction: Vector3 = info.get("direction", Vector3.FORWARD)
		var approach_direction: Vector3 = info.get("approach_direction", direction)
		var holder := info.get("holder") as Node3D
		if approach_weight < 1.0:
			var approach_pos := start.lerp(hover, eased_approach)
			var bank := sin(approach_weight * PI) * (0.13 if player_index == 1 else -0.13)
			var level_weight := smoothstep(0.72, 1.0, approach_weight)
			var flight_direction := approach_direction.slerp(direction, level_weight).normalized()
			_set_hatch_openness(info, 0.0)
			_set_flight_transform(
				holder,
				approach_pos,
				flight_direction,
				bank,
				-deg_to_rad(2.0) * sin(approach_weight * PI)
			)
			_remember_helicopter_velocity(info)
			continue

		var hatch_open_start := drop_time - HATCH_OPEN_LEAD
		var hatch_openness := 0.0
		if timeline >= hatch_open_start and timeline < drop_time:
			hatch_openness = smoothstep(
				0.0,
				1.0,
				clampf(
					(timeline - hatch_open_start) / HATCH_OPEN_DURATION,
					0.0,
					1.0
				)
			)
		elif timeline >= drop_time and timeline < drop_time + HATCH_CLOSE_DELAY:
			hatch_openness = 1.0
		elif timeline >= drop_time + HATCH_CLOSE_DELAY:
			hatch_openness = 1.0 - smoothstep(
				0.0,
				1.0,
				clampf(
					(
						timeline - drop_time - HATCH_CLOSE_DELAY
					) / HATCH_CLOSE_DURATION,
					0.0,
					1.0
				)
			)
		_set_hatch_openness(info, hatch_openness)

		var hover_bob := sin((_total_elapsed + player_index * 0.37) * 2.8) * 0.06
		var inward: Vector3 = info.get("inward_direction", Vector3.ZERO)
		var hover_elapsed := timeline
		if bool(info.get("dropped", false)):
			hover_elapsed = float(info.get("drop_timeline", timeline))
		var drifted_hover := hover + inward * (OCEAN_SIDE_INWARD_DRIFT * hover_elapsed)
		var current_pos := drifted_hover + Vector3.UP * (hover_bob + hatch_openness * 0.10)
		var depart_weight := clampf(
			(timeline - drop_time - DEPART_AFTER_DROP) / DEPART_DURATION,
			0.0,
			1.0
		)
		if depart_weight > 0.0:
			current_pos = drifted_hover.lerp(exit, smoothstep(0.0, 1.0, depart_weight))
		var presentation_bank := (
			(0.055 if player_index == 1 else -0.055) * hatch_openness
		)
		var side_bank := presentation_bank + (
			(0.16 if player_index == 1 else -0.16) * sin(depart_weight * PI)
		)
		var pitch := DROP_PRESENTATION_PITCH * hatch_openness
		pitch += DEPART_CLIMB_PITCH * sin(depart_weight * PI)
		_set_flight_transform(holder, current_pos, direction, side_bank, pitch)
		_remember_helicopter_velocity(info)
		if timeline >= drop_time and not bool(info.get("dropped", false)):
			info["drop_timeline"] = timeline
			_drop_player(info)
		_update_landing_impact(info)

	if timeline < latest_drop_time + MIN_RAGDOLL_DISPLAY:
		return
	var all_physics_valid := true
	var all_recovered := true
	for info: Dictionary in _helicopters:
		if not bool(info.get("dropped", false)):
			all_recovered = false
			continue
		var state := _player_controller.get_intro_drop_state(int(info["player_index"]))
		if not bool(state.get("physics_valid", false)):
			all_physics_valid = false
			break
		all_recovered = all_recovered and bool(state.get("recovery_complete", false))
	if not all_physics_valid:
		_fail_safe("intro ragdoll physics became unavailable")
		return
	var helis_exited := (
		timeline >= latest_drop_time + DEPART_AFTER_DROP + DEPART_DURATION
	)
	if helis_exited and all_recovered:
		_complete_arrival()


func _drop_player(info: Dictionary) -> void:
	var holder := info.get("holder") as Node3D
	var release: Vector3 = _hatch_release_position(info)
	info["release"] = release
	var release_basis := holder.global_basis if holder != null else Basis.IDENTITY
	var inherited_velocity: Vector3 = info.get("world_velocity", Vector3.ZERO)
	var did_begin := _player_controller.begin_intro_drop(
		int(info.get("player_index", 1)),
		Transform3D(release_basis, release),
		inherited_velocity
	)
	if not did_begin:
		_fail_safe("intro ragdoll could not be created")
		return
	info["dropped"] = true


func _all_intro_ragdolls_settled() -> bool:
	if _helicopters.is_empty() or _player_controller == null:
		return false
	for info: Dictionary in _helicopters:
		if not bool(info.get("dropped", false)):
			return false
		var state := _player_controller.get_intro_drop_state(int(info["player_index"]))
		if not bool(state.get("settled", false)):
			return false
	return true


func _update_landing_impact(info: Dictionary) -> void:
	if not bool(info.get("dropped", false)):
		return
	var state := _player_controller.get_intro_drop_state(int(info["player_index"]))
	var ragdoll_position: Vector3 = state.get("position", Vector3.ZERO)
	if ragdoll_position.y < StageConstants.OCEAN_ENTRY_Y:
		_fail_safe("intro ragdoll fell off the belt")
		return
	if bool(state.get("floor_contacted", false)) and not bool(info.get("impact_played", false)):
		info["first_impact_position"] = ragdoll_position
		info["impact_played"] = true
		_play_landing_impact(ragdoll_position, int(info["player_index"]))
	if (
		_all_intro_ragdolls_settled()
		and not bool(info.get("get_up_started", false))
	):
		var recovery_started := _player_controller.begin_intro_get_up(
			int(info["player_index"]),
			info.get("ground", Vector3.ZERO)
		)
		if not recovery_started:
			_fail_safe("intro ragdoll could not be stabilized for recovery")
			return
		info["final_impact_position"] = ragdoll_position
		info["get_up_started"] = true


func _complete_arrival() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_player_controller.complete_intro_drops(_game_state)
	_start_locked = false
	_cleanup_helicopters(false)
	set_process(false)


func _fail_safe(reason: String) -> void:
	push_warning("Helicopter arrival fail-safe: %s" % reason)
	if _player_controller != null:
		_player_controller.cancel_intro_drops()
	_start_locked = false
	_phase = "complete"
	_cleanup_helicopters(true)
	set_process(false)


func _skip_missing_asset(reason: String) -> void:
	push_warning("Helicopter arrival skipped: %s" % reason)
	_start_locked = false
	_phase = "complete"
	_cleanup_helicopters(true)
	set_process(false)


func _instantiate_helicopter(packed: PackedScene, player_index: int) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "P%dHelicopter" % player_index
	add_child(holder)
	var model := packed.instantiate() as Node3D
	if model == null:
		holder.queue_free()
		return {}
	model.name = "Model"
	holder.add_child(model)
	var main_rotor := model.find_child("MainRotor", true, false) as Node3D
	var tail_rotor := model.find_child("TailRotor", true, false) as Node3D
	var hatch_left := model.find_child("DropHatchLeft", true, false) as Node3D
	var hatch_right := model.find_child("DropHatchRight", true, false) as Node3D
	var body_tinted := _apply_body_tint(
		model,
		PlayerController.P1_BODY if player_index == 1 else PlayerController.P2_BODY
	)
	if (
		main_rotor == null
		or tail_rotor == null
		or hatch_left == null
		or hatch_right == null
		or not body_tinted
	):
		holder.queue_free()
		return {}

	var audio := AudioStreamPlayer3D.new()
	audio.name = "RotorLoop"
	audio.bus = "SFX"
	audio.stream = _rotor_stream
	audio.volume_db = -18.0
	audio.pitch_scale = 0.96 if player_index == 1 else 1.04
	audio.max_distance = 48.0
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	holder.add_child(audio)
	holder.visible = false
	return {
		"player_index": player_index,
		"holder": holder,
		"model": model,
		"main_rotor": main_rotor,
		"tail_rotor": tail_rotor,
		"hatch_left": hatch_left,
		"hatch_right": hatch_right,
		"hatch_left_rotation": hatch_left.rotation,
		"hatch_right_rotation": hatch_right.rotation,
		"audio": audio,
		"dropped": false,
		"get_up_started": false,
		"first_impact_position": Vector3.INF,
		"final_impact_position": Vector3.INF,
		"impact_played": false,
		"world_velocity": Vector3.ZERO,
	}


func _apply_body_tint(root: Node, color: Color) -> bool:
	var applied := false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var body_node := str(mesh_instance.name) == "BodyPaint"
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			var body_material := source != null and source.resource_name == "BodyPaint"
			if not body_node and not body_material:
				continue
			var material := source.duplicate(true) as BaseMaterial3D if source != null else StandardMaterial3D.new()
			if material == null:
				continue
			material.albedo_color = color
			mesh_instance.set_surface_override_material(surface_index, material)
			applied = true
	return applied


func _spin_rotors(delta: float) -> void:
	for info: Dictionary in _helicopters:
		var main_rotor := info.get("main_rotor") as Node3D
		var tail_rotor := info.get("tail_rotor") as Node3D
		if main_rotor != null and is_instance_valid(main_rotor):
			main_rotor.rotate_y(MAIN_ROTOR_SPEED * delta)
		if tail_rotor != null and is_instance_valid(tail_rotor):
			tail_rotor.rotate_x(TAIL_ROTOR_SPEED * delta)


func _set_flight_transform(
	holder: Node3D,
	world_position: Vector3,
	direction: Vector3,
	bank: float,
	pitch: float
) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var forward := direction.normalized()
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	holder.global_transform = Transform3D(Basis.IDENTITY, world_position).looking_at(world_position + forward, Vector3.UP)
	holder.rotate_object_local(Vector3.FORWARD, bank)
	holder.rotate_object_local(Vector3.RIGHT, pitch)


func _remember_helicopter_velocity(info: Dictionary) -> void:
	var holder := info.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return
	var current := holder.global_position
	var last: Vector3 = info.get("last_position", current)
	var delta := maxf(get_process_delta_time(), 0.0001)
	info["world_velocity"] = (current - last) / delta
	info["last_position"] = current


func _set_hatch_openness(info: Dictionary, openness: float) -> void:
	var hatch_left := info.get("hatch_left") as Node3D
	var hatch_right := info.get("hatch_right") as Node3D
	var left_base: Vector3 = info.get("hatch_left_rotation", Vector3.ZERO)
	var right_base: Vector3 = info.get("hatch_right_rotation", Vector3.ZERO)
	var eased := smoothstep(0.0, 1.0, clampf(openness, 0.0, 1.0))
	if hatch_left != null and is_instance_valid(hatch_left):
		hatch_left.rotation = left_base + Vector3(0.0, 0.0, -HATCH_OPEN_ANGLE * eased)
	if hatch_right != null and is_instance_valid(hatch_right):
		hatch_right.rotation = right_base + Vector3(0.0, 0.0, HATCH_OPEN_ANGLE * eased)


func _hatch_release_position(info: Dictionary) -> Vector3:
	var hatch_left := info.get("hatch_left") as Node3D
	var hatch_right := info.get("hatch_right") as Node3D
	if (
		hatch_left == null
		or hatch_right == null
		or not is_instance_valid(hatch_left)
		or not is_instance_valid(hatch_right)
	):
		return info.get("release", Vector3.ZERO)
	var center := (hatch_left.global_position + hatch_right.global_position) * 0.5
	var holder := info.get("holder") as Node3D
	var down := Vector3.DOWN
	if holder != null and is_instance_valid(holder):
		down = -holder.global_basis.y.normalized()
	return center + down * 0.18


func _play_landing_impact(world_position: Vector3, player_index: int) -> void:
	var impact := AudioStreamPlayer3D.new()
	impact.name = "P%dLandingImpact" % player_index
	impact.bus = "SFX"
	impact.stream = _impact_stream
	impact.volume_db = -13.0
	impact.pitch_scale = 0.96 if player_index == 1 else 1.03
	impact.max_distance = 36.0
	add_child(impact)
	impact.global_position = world_position
	impact.finished.connect(impact.queue_free)
	_impact_players.append(impact)
	impact.play()


func _cleanup_helicopters(immediate: bool) -> void:
	for info: Dictionary in _helicopters:
		var holder := info.get("holder") as Node3D
		var audio := info.get("audio") as AudioStreamPlayer3D
		if audio != null and is_instance_valid(audio) and audio.playing and not immediate:
			var tween := create_tween()
			tween.tween_property(audio, "volume_db", -80.0, ROTOR_FADE_SECONDS)
			tween.tween_callback(audio.stop)
		if holder != null and is_instance_valid(holder):
			if immediate:
				holder.queue_free()
			else:
				get_tree().create_timer(ROTOR_FADE_SECONDS).timeout.connect(holder.queue_free)
	_helicopters.clear()
	for impact: AudioStreamPlayer3D in _impact_players:
		if impact != null and is_instance_valid(impact):
			impact.stop()
			impact.queue_free()
	_impact_players.clear()


func _build_rotor_loop() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var sample_count := int(stream.mix_rate * 0.50)
	stream.loop_begin = 0
	stream.loop_end = sample_count
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var t := float(sample_index) / float(stream.mix_rate)
		var pulse := 0.62 * sin(TAU * 17.0 * t) + 0.23 * sin(TAU * 34.0 * t)
		var engine := 0.15 * sin(TAU * 93.0 * t)
		var sample := int(clampf((pulse + engine) * 0.28, -1.0, 1.0) * 32767.0)
		bytes[sample_index * 2] = sample & 0xff
		bytes[sample_index * 2 + 1] = (sample >> 8) & 0xff
	stream.data = bytes
	return stream


func _build_landing_impact() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var sample_count := int(stream.mix_rate * 0.28)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var t := float(sample_index) / float(stream.mix_rate)
		var envelope := exp(-t * 15.0)
		var tone := sin(TAU * 54.0 * t) + 0.45 * sin(TAU * 81.0 * t)
		var sample := int(clampf(tone * envelope * 0.42, -1.0, 1.0) * 32767.0)
		bytes[sample_index * 2] = sample & 0xff
		bytes[sample_index * 2 + 1] = (sample >> 8) & 0xff
	stream.data = bytes
	return stream
