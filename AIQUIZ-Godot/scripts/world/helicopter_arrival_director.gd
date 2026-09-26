extends Node3D
class_name HelicopterArrivalDirector

signal presentation_finished(success: bool)
signal menu_boost_launched
var menu_launch_ready: Callable

## Read-only timing hook for stage machinery; excludes hidden render prewarm.
func has_started_arrival() -> bool:
	return _phase == "arrival" and not _prewarm_visible

## Floor contact, before the landing hold/get-up or aircraft departure finishes.
func have_players_touched_down() -> bool:
	if not _start_locked:
		return true # Skip/fail-safe also places the players on the stage.
	if _helicopters.is_empty():
		return false
	for info: Dictionary in _helicopters:
		if not bool(info.get("impact_played", false)):
			return false
	return true

const HELICOPTER_GLB := "res://assets/vehicles/helicopter/helicopter_drop.glb"
const GODOT_PLUSH_GLB := "res://assets/characters/godot_plush/godot_plush_model.glb"
const GODOT_PLUSH_ALBEDO := "res://assets/characters/godot_plush/godot_plush_albedo.png"
const MENU_FLIGHT_PROFILE_SCENE := preload("res://scenes/menu_helicopter_sequence.tscn")
const WINDOW_GLASS_COLOR := Color(0.62, 0.84, 0.95, 0.34)
const PILOT_SCALE := 0.38
const PILOT_SEAT_POSITION := Vector3(0.0, -0.16, -1.08)
const PILOT_SEAT_ROTATION_DEGREES := Vector3(8.0, 180.0, 0.0)
const COCKPIT_LIGHT_ENERGY := 0.7
const PhysicalRopeLadderScript := preload("res://scripts/world/physical_rope_ladder.gd")
const APPROACH_DURATION := 4.40
const HOVER_BEFORE_FIRST_DROP := 0.70
const P2_DROP_DELAY := 0.30
const DEPART_DURATION := 4.80
const MIN_RAGDOLL_DISPLAY := 0.45
const FAILSAFE_SECONDS := 30.0
const RELEASE_HEIGHT := 8.0
const HELICOPTER_ABOVE_RELEASE := 1.25
const OFFSCREEN_DISTANCE := 28.0
const EXIT_RISE_HEIGHT := 16.0
const OCEAN_SIDE_HOVER_HEIGHT := 7.60
const OCEAN_SIDE_APPROACH_RISE := 7.0
const OCEAN_SIDE_INWARD_DRIFT := 3.20
const HATCH_OPEN_LEAD := 0.55
const HATCH_OPEN_DURATION := 0.45
const HATCH_CLOSE_DELAY := 0.55
const HATCH_CLOSE_DURATION := 0.50
const HATCH_OPEN_ANGLE := deg_to_rad(78.0)
const CABIN_WAIT_PELVIS_HEIGHT := 0.32
const CABIN_LIGHT_ENERGY := 0.9
const DEPART_AFTER_DROP := 1.00
const DROP_PRESENTATION_PITCH := deg_to_rad(4.0)
const DEPART_CLIMB_PITCH := deg_to_rad(-6.0)
const MAIN_ROTOR_SPEED := 28.0
const TAIL_ROTOR_SPEED := 42.0
const ROTOR_FADE_SECONDS := 0.45
const MENU_APPROACH_DURATION := 4.40
const MENU_HOVER_BEFORE_FIRST_DROP := 0.75
const MENU_P2_DROP_DELAY := 0.35
const MENU_DEPART_DURATION := 4.60
const MENU_DEPART_AFTER_DROP := 0.85
const MENU_FAILSAFE_SECONDS := 24.0
const MENU_RELEASE_HEIGHT := 8.4
const MENU_HELICOPTER_ABOVE_RELEASE := 1.10
const MENU_HELICOPTER_SCALE := 1.00
const MENU_LANDED_POSE_HOLD := 0.55
const MENU_OFFSCREEN_MARGIN_RATIO := 0.08
const MENU_OFFSCREEN_PLACEMENT_MARGIN_RATIO := 0.10
const MENU_OFFSCREEN_STEP_RATIO := 0.08
const MENU_OFFSCREEN_MAX_STEPS := 16
const MENU_CAMERA_WIDE_FOV_DELTA := 7.5
const MENU_CAMERA_TILT_UP_DEG := 10.0
const MENU_CAMERA_RETURN_START := 7.8
const MENU_CAMERA_RETURN_DURATION := 3.0
const MENU_CAMERA_SHAKE_DURATION := 0.22
const MENU_CAMERA_SHAKE_POSITION := 0.075
const MENU_CAMERA_SHAKE_ROTATION_DEG := 0.20
const MENU_DEPART_TURN_BLEND_RATIO := 0.30
const MENU_PICKUP_APPROACH_DURATION := 1.35
const MENU_PICKUP_HATCH_OPEN_DURATION := 0.34
const MENU_PICKUP_P2_DELAY := 0.18
const MENU_PICKUP_SUCTION_DURATION := 1.45
const MENU_PICKUP_HATCH_CLOSE_DURATION := 0.28
const MENU_PICKUP_EXIT_DURATION := 2.25
const MENU_PICKUP_FAILSAFE_SECONDS := 12.0
const MENU_PICKUP_HOVER_HEIGHT := 10.2
const MENU_PICKUP_CAMERA_FOV_DELTA := 4.0
const MENU_PICKUP_CAMERA_TILT_UP_DEG := 5.0
const MENU_PICKUP_CAMERA_DRIFT := 0.018
const MENU_LADDER_DEPLOY_START := 1.20
const MENU_LADDER_DEPLOY_DURATION := 0.38
const MENU_LADDER_P2_DELAY := 0.104
const MENU_LADDER_GRAB_DURATION := 0.62
const MENU_LADDER_DEPART_PATH_TIME := 2.3075
const BoostExhaustScript := preload("res://scripts/world/helicopter_boost_exhaust.gd")
const MENU_BOOST_CHARGE_DURATION := 0.80
const MENU_BOOST_FLIGHT_DURATION := 1.95
const MENU_BOOST_ACCEL_TIME := 0.65
const MENU_BOOST_SPEED := 78.0
const MENU_BOOST_PITCH := deg_to_rad(-7.0)
const MENU_BOOST_DIRECTION := Vector3(0.0, 0.10, -1.0)
const GP_APPROACH_DURATION := 2.65
const PASS_SPEED := 1.5
const GP_LOWER_DURATION := 1.75
const GP_EXIT_SPEED := 20.0
## Drop-off departures: brake, spool up, then leave on the tail jet.
const DROP_BOOST_CHARGE_DURATION := 1.80
const DROP_BOOST_ACCEL_TIME := 0.60
const DROP_BOOST_SPEED := 64.0
const MENU_DROP_BOOST_DELAY := 0.95
const GP_EXIT_MIN_TIME := DROP_BOOST_CHARGE_DURATION + 0.6
const GP_SWING_DURATION := 0.72
const GP_SWING_CYCLES := 0.125
const GP_SWING_AMPLITUDE_DEG := 24.0
const GP_FLIGHT_DURATION := 1.70
const GP_LAND_HOLD := 0.55
const GP_HOVER_ALTITUDE := 11.40
const GP_OCEAN_OUTSET := 4.50
const GP_SOLO_OCEAN_OUTSET := 1.50
const GP_P2_DELAY := 0.25
const GP_PASSENGER_SEAT_LOCAL := Vector3(0.0, 0.10, -0.42)
const GP_HATCH_KEEP_OPEN := 1.0

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
var _menu_preview_mode := false
var _menu_departure_mode := false
var _requested_helicopter_count := 0
var _menu_camera: Camera3D = null
var _menu_camera_base_position := Vector3.ZERO
var _menu_camera_base_rotation := Vector3.ZERO
var _menu_camera_base_fov := 37.5
var _menu_camera_shake_remaining := 0.0
var _menu_pickup_camera_intensity := 0.0
var _menu_flight_profile: MenuHelicopterSequenceProfile = null
var _menu_pickup_path_time := 0.0
var _menu_launch_charge_elapsed := 0.0
var _menu_launch_elapsed := 0.0
var _menu_boost_started := false
var _presentation_finished_emitted := false
var _preparing_menu_departure := false
var _menu_departure_prepared := false


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
	if _menu_departure_prepared:
		_menu_departure_prepared = false
		# Player count and camera may have changed while the menu was open.
		while _helicopters.size() > _requested_helicopter_count:
			var unused: Dictionary = _helicopters.pop_back()
			for key: String in ["rope_ladder", "downwash", "holder"]:
				var node := unused.get(key) as Node
				if is_instance_valid(node):
					node.queue_free()
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		_restore_menu_camera()
		_start_locked = true
		_phase = "waiting_camera"
		set_process(true)
		call_deferred("_begin_after_reveal_and_camera")
		return
	if not ResourceLoader.exists(HELICOPTER_GLB):
		_skip_missing_asset("%s has not been supplied yet" % HELICOPTER_GLB)
		return
	if _menu_preview_mode:
		_menu_flight_profile = (
			MENU_FLIGHT_PROFILE_SCENE.instantiate()
			as MenuHelicopterSequenceProfile
		)
		if _menu_flight_profile == null:
			_skip_missing_asset("the editable menu helicopter sequence could not be loaded")
			return
		_menu_flight_profile.prepare_runtime()
		add_child(_menu_flight_profile)
		_restore_menu_camera()

	var packed := ResourceLoader.load(HELICOPTER_GLB) as PackedScene
	if packed == null:
		_skip_missing_asset("the helicopter GLB could not be loaded")
		return
	_rotor_stream = _build_rotor_loop()
	_impact_stream = _build_landing_impact()
	var helicopter_count := (
		clampi(_requested_helicopter_count, 1, 2)
		if _requested_helicopter_count > 0
		else (2 if _menu_preview_mode or _game_state.num_players >= 2 else 1)
	)
	for player_index: int in range(1, helicopter_count + 1):
		var info := _instantiate_helicopter(packed, player_index)
		if info.is_empty():
			_skip_missing_asset(
				"the GLB must contain BodyPaint, MainRotor, and TailRotor"
			)
			return
		_helicopters.append(info)

	if not _menu_departure_mode:
		_player_controller.prepare_intro_arrival(helicopter_count)
	if _preparing_menu_departure:
		return
	_start_locked = true
	_phase = "waiting_camera"
	set_process(true)
	call_deferred("_begin_after_reveal_and_camera")


func setup_menu_preview(
	game_state: QuizGameState,
	player_controller: PlayerController,
	camera: Camera3D
) -> void:
	_menu_preview_mode = true
	_menu_camera = camera
	if _menu_camera != null:
		_menu_camera_base_position = _menu_camera.position
		_menu_camera_base_rotation = _menu_camera.rotation_degrees
		_menu_camera_base_fov = _menu_camera.fov
	setup(game_state, player_controller, camera)
	if _player_controller != null and not _helicopters.is_empty():
		_player_controller.prewarm_intro_drop_ragdolls(2)


func setup_menu_departure(
	game_state: QuizGameState,
	player_controller: PlayerController,
	camera: Camera3D,
	player_count: int
) -> void:
	_menu_preview_mode = true
	_menu_departure_mode = true
	_requested_helicopter_count = clampi(player_count, 1, 2)
	_menu_camera = camera
	if _menu_camera != null:
		_menu_camera_base_position = _menu_camera.position
		_menu_camera_base_rotation = _menu_camera.rotation_degrees
		_menu_camera_base_fov = _menu_camera.fov
	setup(game_state, player_controller, camera)


## Build the extraction scene before the menu is revealed. In particular, the
## editable flight profile instantiates a large reference hierarchy; doing that
## on Start blocks the main thread even when its resources are already cached.
## Keep the prepared shot hidden, silent, and paused until the actual click.
func prepare_menu_departure(
	game_state: QuizGameState,
	player_controller: PlayerController,
	camera: Camera3D
) -> void:
	_preparing_menu_departure = true
	setup_menu_departure(game_state, player_controller, camera, 2)
	_preparing_menu_departure = false
	if _cancelled or _helicopters.is_empty():
		return
	_prepare_flight_paths()
	_reset_menu_camera()
	_menu_departure_prepared = true
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	set_process(false)


func get_menu_pickup_clearance_z() -> float:
	if _menu_flight_profile != null:
		return _menu_flight_profile.get_pickup_clearance_z()
	return StageConstants.FLOOR_BACK_Z


func begin_render_prewarm() -> Dictionary:
	if _helicopters.is_empty():
		return {"ready": false, "reason": "helicopter_asset_missing"}
	_prewarm_visible = true
	for info: Dictionary in _helicopters:
		var holder := info.get("holder") as Node3D
		if holder != null:
			holder.visible = true
		var exhaust := info.get("boost_exhaust") as HelicopterBoostExhaust
		if exhaust != null:
			exhaust.set_prewarm(true)
	if _player_controller != null:
		if _menu_preview_mode:
			_player_controller.prewarm_intro_drop_ragdolls(_helicopters.size())
		else:
			_player_controller.prewarm_intro_ladder_clips(_helicopters.size())
			_player_controller.prewarm_intro_drop_ragdolls(_helicopters.size())
	return {"ready": true, "helicopters": _helicopters.size()}


func end_render_prewarm() -> void:
	_prewarm_visible = false
	for info: Dictionary in _helicopters:
		var exhaust := info.get("boost_exhaust") as HelicopterBoostExhaust
		if exhaust != null and is_instance_valid(exhaust):
			exhaust.set_prewarm(false)
	if _phase == "waiting_camera":
		for info: Dictionary in _helicopters:
			var holder := info.get("holder") as Node3D
			if holder != null:
				holder.visible = false


func is_start_locked() -> bool:
	return _start_locked


func is_active() -> bool:
	return _start_locked and _phase not in ["idle", "complete", "cancelled"]


func is_ready_for_scene_cover(cover_duration: float = -1.0) -> bool:
	if cover_duration < 0.0:
		cover_duration = SceneTransition.MODULAR_DURATION
	if _phase == "complete":
		return true
	if _phase != "departure_pickup" or not _all_menu_players_captured():
		return false
	return _menu_departure_remaining() <= cover_duration


func _all_menu_players_captured() -> bool:
	if _helicopters.is_empty():
		return false
	for info: Dictionary in _helicopters:
		if not bool(info.get("captured", false)):
			return false
	return true


func _menu_departure_remaining() -> float:
	if _menu_flight_profile != null and is_instance_valid(_menu_flight_profile):
		return maxf(MENU_BOOST_FLIGHT_DURATION - _menu_launch_elapsed, 0.0)
	var pickup_timeline := maxf(0.0, _phase_elapsed - MENU_PICKUP_APPROACH_DURATION)
	var latest_pickup_end := 2.18 + MENU_PICKUP_P2_DELAY
	var exit_start := latest_pickup_end + 0.22
	return maxf(MENU_PICKUP_EXIT_DURATION - maxf(pickup_timeline - exit_start, 0.0), 0.0)


func _is_scene_cover_complete() -> bool:
	return SceneTransition.is_fully_covered()


func skip_menu_departure() -> void:
	if not _menu_departure_mode:
		return
	if _phase in ["complete", "cancelled"]:
		return
	_complete_menu_departure()


func cancel() -> void:
	if _cancelled:
		return
	var already_extracted := _phase == "complete"
	_cancelled = true
	_phase = "cancelled"
	_start_locked = false
	if _player_controller != null and not already_extracted:
		_player_controller.cancel_intro_drops()
	if not already_extracted:
		_reset_menu_camera()
	_cleanup_helicopters(true)
	set_process(false)
	_emit_presentation_finished(false)


func _exit_tree() -> void:
	# Parent scenes release children before their own _exit_tree callback.  Suppress the
	# menu completion callback here so teardown never tries to rebuild preview walls.
	_presentation_finished_emitted = true
	cancel()


func _process(delta: float) -> void:
	_spin_rotors(delta)
	_update_menu_camera(delta)
	if _phase == "departure_pickup":
		_phase_elapsed += delta
		_total_elapsed += delta
		if _total_elapsed >= MENU_PICKUP_FAILSAFE_SECONDS:
			_fail_safe("menu pickup exceeded %.1f seconds" % MENU_PICKUP_FAILSAFE_SECONDS)
			return
		_update_menu_departure_timeline(delta)
		return
	if _phase != "arrival":
		return
	_phase_elapsed += delta
	_total_elapsed += delta
	var failsafe_seconds := MENU_FAILSAFE_SECONDS if _menu_preview_mode else FAILSAFE_SECONDS
	if _total_elapsed >= failsafe_seconds:
		_fail_safe("arrival exceeded %.1f seconds" % failsafe_seconds)
		return
	_update_timeline()


func _begin_after_reveal_and_camera() -> void:
	while is_inside_tree() and not _cancelled and SceneTransition.is_transitioning():
		await get_tree().process_frame
	if not is_inside_tree() or _cancelled:
		return
	if not _menu_preview_mode and _camera_controller.has_method("wait_for_entry_blend"):
		await _camera_controller.wait_for_entry_blend()
	if not is_inside_tree() or _cancelled:
		return
	if (
		not _menu_preview_mode
		and _game_state.game_state not in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START]
	):
		cancel()
		return

	_prepare_flight_paths()
	if _menu_departure_mode:
		pass
	elif _menu_preview_mode:
		if not _prepare_intro_cabin_wait_passengers():
			return
	elif not _prepare_intro_cabin_ride_passengers():
		return
	for info: Dictionary in _helicopters:
		var holder := info.get("holder") as Node3D
		var audio := info.get("audio") as AudioStreamPlayer3D
		if holder != null:
			holder.visible = true
		if audio != null:
			audio.play()
	_phase = "departure_pickup" if _menu_departure_mode else "arrival"
	_phase_elapsed = 0.0
	_total_elapsed = 0.0


func _prepare_flight_paths() -> void:
	if _menu_departure_mode:
		_prepare_menu_departure_paths()
		return
	if _menu_preview_mode:
		_prepare_menu_flight_paths()
		return
	_prepare_gameplay_flight_paths()


func _prepare_intro_cabin_wait_passengers() -> bool:
	if _player_controller == null:
		return false
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		if not _player_controller.begin_intro_cabin_wait(
			player_index,
			_cabin_wait_transform(info)
		):
			_fail_safe("P%d could not be placed inside the helicopter cabin" % player_index)
			return false
	return true


func _prepare_intro_cabin_ride_passengers() -> bool:
	if _player_controller == null:
		return false
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		if not _player_controller.begin_intro_cabin_ride(
			player_index,
			_cabin_ride_transform(info)
		):
			_fail_safe("P%d could not ride inside the helicopter cabin" % player_index)
			return false
		info["gp_phase"] = "approach"
		info["gp_phase_elapsed"] = 0.0
		info["flight_elapsed"] = -(GP_P2_DELAY if player_index == 2 else 0.0)
		info["jumped"] = false
		info["landed"] = false
		info["hanging"] = false
	return true


func _update_intro_cabin_wait_passenger(info: Dictionary) -> void:
	if bool(info.get("dropped", false)) or _player_controller == null:
		return
	_player_controller.update_intro_cabin_wait(
		int(info.get("player_index", 1)),
		_cabin_wait_transform(info)
	)


func _cabin_wait_transform(info: Dictionary) -> Transform3D:
	var holder := info.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return Transform3D.IDENTITY
	var hatch_left := info.get("hatch_left") as Node3D
	var hatch_right := info.get("hatch_right") as Node3D
	var center := holder.global_position
	if (
		hatch_left != null
		and hatch_right != null
		and is_instance_valid(hatch_left)
		and is_instance_valid(hatch_right)
	):
		center = (hatch_left.global_position + hatch_right.global_position) * 0.5
	var cabin_basis := holder.global_basis.orthonormalized()
	return Transform3D(
		cabin_basis,
		center + cabin_basis.y.normalized() * CABIN_WAIT_PELVIS_HEIGHT
	)


func _cabin_ride_transform(info: Dictionary) -> Transform3D:
	var holder := info.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return _cabin_wait_transform(info)
	var cabin_basis := holder.global_basis.orthonormalized()
	return Transform3D(
		cabin_basis,
		holder.global_transform * GP_PASSENGER_SEAT_LOCAL
	)


func _prepare_authored_menu_paths(animation_name: StringName) -> bool:
	if _menu_flight_profile == null or not is_instance_valid(_menu_flight_profile):
		return false
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var ground := Vector3(
			_game_state.player_x if player_index == 1 else _game_state.player2_x,
			StageConstants.FLOOR_TOP_Y,
			_game_state.player_local_z if player_index == 1 else _game_state.player2_local_z
		)
		_menu_flight_profile.set_player_ground(player_index, ground)
		if animation_name == MenuHelicopterSequenceProfile.PICKUP_ANIMATION:
			# Fixed landing slots do not follow the ambient menu AI. Preserve the
			# actors' left/right order so their approaches do not cross.
			var p1_on_left := _game_state.player_x <= _game_state.player2_x
			var left_slot := _helicopters.size() == 1 or (p1_on_left if player_index == 1 else not p1_on_left)
			_menu_flight_profile.set_fixed_pickup_ground(player_index, _helicopters.size(), left_slot)
			info["pickup_target"] = _menu_flight_profile.get_pickup_ground_target(player_index)
		info["ground"] = ground
		info["release"] = ground + Vector3.UP * MENU_RELEASE_HEIGHT
		info["pickup_started"] = false
		info["captured"] = false
		info["ever_visible_in_frame"] = false
		_prepare_menu_downwash(info, ground, player_index)
	_menu_pickup_path_time = 0.0
	if not _menu_flight_profile.select_runtime_animation(animation_name):
		return false
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var state := _menu_flight_profile.get_player_state(player_index)
		if state.is_empty():
			return false
		var holder := info.get("holder") as Node3D
		var flight_direction: Vector3 = state.get("direction", Vector3.FORWARD)
		if animation_name == MenuHelicopterSequenceProfile.PICKUP_ANIMATION:
			flight_direction = _menu_level_flight_direction(flight_direction)
		_set_hatch_openness(info, float(state.get("hatch", 0.0)))
		_set_flight_transform(
			holder,
			state.get("position", Vector3.ZERO),
			flight_direction,
			float(state.get("bank", 0.0)),
			float(state.get("pitch", 0.0))
		)
		if holder != null:
			info["last_position"] = holder.global_position
		if animation_name == MenuHelicopterSequenceProfile.PICKUP_ANIMATION:
			_create_rope_ladder(info)
	return true


func _prepare_menu_departure_paths() -> void:
	if _prepare_authored_menu_paths(MenuHelicopterSequenceProfile.PICKUP_ANIMATION):
		return
	if _menu_camera == null or _menu_camera.get_viewport() == null:
		_prepare_gameplay_flight_paths()
		return
	var viewport_size := _menu_camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		_prepare_gameplay_flight_paths()
		return
	_menu_camera.fov = _menu_camera_base_fov + MENU_PICKUP_CAMERA_FOV_DELTA
	_menu_camera.rotation_degrees = _menu_camera_base_rotation + Vector3(
		MENU_PICKUP_CAMERA_TILT_UP_DEG,
		0.0,
		0.0
	)

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var ground := Vector3(
			_game_state.player_x if player_index == 1 else _game_state.player2_x,
			StageConstants.FLOOR_TOP_Y,
			_game_state.player_local_z if player_index == 1 else _game_state.player2_local_z
		)
		var hover := ground + Vector3.UP * MENU_PICKUP_HOVER_HEIGHT
		var camera_local_hover := _menu_camera.to_local(hover)
		var hover_depth := maxf(-camera_local_hover.z, 4.0)
		var hover_uv := _menu_camera.unproject_position(hover) / viewport_size
		var side := -1.0 if player_index == 1 else 1.0
		var start_report := _resolve_menu_offscreen_point(
			info,
			Vector2(hover_uv.x + side * 0.05, -0.22),
			Vector2(0.0, -1.0),
			hover_depth + 5.0,
			hover,
			true
		)
		var start: Vector3 = start_report.get("position", hover + Vector3.UP * 22.0)
		var approach_c1 := start.lerp(hover + Vector3.UP * 4.0, 0.42)
		var approach_c2 := hover + Vector3.UP * 1.2 + Vector3(side * 0.6, 0.0, 0.0)

		var exit_report := _resolve_menu_offscreen_point(
			info,
			Vector2(hover_uv.x + side * 0.08, -0.26),
			Vector2(0.0, -1.0),
			hover_depth + 4.0,
			hover,
			false
		)
		var exit: Vector3 = exit_report.get("position", hover + Vector3.UP * 26.0)
		var exit_c1 := hover + Vector3.UP * 2.8 + Vector3(side * 0.55, 0.0, 0.0)
		var exit_c2 := exit.lerp(hover, 0.28)
		var facing := Vector3(-0.10 * side, 0.0, -1.0).normalized()
		info["ground"] = ground
		info["release"] = hover - Vector3.UP * 0.8
		info["hover"] = hover
		info["start"] = start
		info["approach_c1"] = approach_c1
		info["approach_c2"] = approach_c2
		info["exit"] = exit
		info["exit_c1"] = exit_c1
		info["exit_c2"] = exit_c2
		info["direction"] = facing
		info["approach_direction"] = facing
		info["pickup_started"] = false
		info["captured"] = false
		info["ever_visible_in_frame"] = false
		_prepare_menu_downwash(info, ground, player_index)
		var holder := info.get("holder") as Node3D
		_set_hatch_openness(info, 0.0)
		_set_flight_transform(holder, start, facing, 0.0, deg_to_rad(-3.0))
		if holder != null:
			info["last_position"] = holder.global_position
		_create_rope_ladder(info)


func _create_rope_ladder(info: Dictionary) -> void:
	var holder := info.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return
	var old_ladder := info.get("rope_ladder") as PhysicalRopeLadder
	if old_ladder != null and is_instance_valid(old_ladder):
		return
	var player_index := int(info.get("player_index", 1))
	var mount := Node3D.new()
	mount.name = "P%dRopeLadderMount" % player_index
	holder.add_child(mount)
	mount.global_transform = Transform3D(holder.global_basis, _hatch_release_position(info))
	var ladder := PhysicalRopeLadderScript.new() as PhysicalRopeLadder
	ladder.name = "P%dPhysicalRopeLadder" % player_index
	if _menu_departure_mode:
		ladder.deploy_throw_speed = 9.5
		ladder.deploy_damping = 0.994
		ladder.deploy_recoil_scale = 0.18
	elif not _menu_preview_mode:
		ladder.deploy_throw_speed = 3.8
		ladder.deploy_lateral_scale = 0.18
		ladder.deploy_recoil_scale = 0.12
		ladder.inherit_carrier_velocity = true
	add_child(ladder)
	ladder.configure(mount, player_index)
	info["rope_ladder_mount"] = mount
	info["rope_ladder"] = ladder


func _prepare_gameplay_flight_paths() -> void:
	var is_pair := _helicopters.size() >= 2
	var player_pair_center_x := 0.0
	var player_pair_side := 1.0
	if is_pair:
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
		var player_side := -1.0
		var center_x := ground.x
		if is_pair:
			player_side = player_pair_side if player_index == 1 else -player_pair_side
			center_x = player_pair_center_x
		var hover_ocean := Vector3(
			center_x + player_side * (StageConstants.FLOOR_HALF_WIDTH + (GP_OCEAN_OUTSET if is_pair else GP_SOLO_OCEAN_OUTSET)),
			ground.y + GP_HOVER_ALTITUDE,
			ground.z
		)
		# Two depth lanes keep the rotor discs clear as the aircraft cross on screen.
		hover_ocean.z += 8.0 if is_pair and player_index == 2 else -1.0
		hover_ocean.y += 1.2 if is_pair and player_index == 2 else 0.0
		var inward := Vector3(-player_side, 0.0, 0.0)
		var pass_direction := Vector3(-player_side, 0.0, 0.16).normalized()
		var start := hover_ocean - pass_direction * 20.0 + Vector3.UP * 3.5
		var exit := hover_ocean + pass_direction * 80.0 + Vector3.UP * 16.0
		var approach_direction := (hover_ocean - start).normalized()
		info["ground"] = ground
		info["release"] = hover_ocean
		info["hover"] = hover_ocean
		info["hover_ocean"] = hover_ocean
		info["start"] = start
		info["exit"] = exit
		info["direction"] = pass_direction
		info["approach_direction"] = approach_direction
		info["ocean_side_drop"] = true
		info["player_side"] = player_side
		info["inward_direction"] = inward
		info["world_velocity"] = Vector3.ZERO
		info["gp_phase"] = "approach"
		info["gp_phase_elapsed"] = 0.0
		info["jumped"] = false
		info["landed"] = false
		info["hanging"] = false
		var holder := info.get("holder") as Node3D
		_set_hatch_openness(info, 0.0)
		_set_flight_transform(holder, start, approach_direction, 0.10 * -player_side, 0.0)
		if holder != null:
			info["last_position"] = holder.global_position
		_create_rope_ladder(info)


func _prepare_menu_flight_paths() -> void:
	if _prepare_authored_menu_paths(MenuHelicopterSequenceProfile.INTRO_ANIMATION):
		return
	if _menu_camera == null or _menu_camera.get_viewport() == null:
		_prepare_gameplay_flight_paths()
		return
	var viewport_size := _menu_camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		_prepare_gameplay_flight_paths()
		return
	_menu_camera.fov = _menu_camera_base_fov + MENU_CAMERA_WIDE_FOV_DELTA
	_menu_camera.rotation_degrees = _menu_camera_base_rotation + Vector3(
		MENU_CAMERA_TILT_UP_DEG,
		0.0,
		0.0
	)

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var ground := Vector3(
			_game_state.player_x if player_index == 1 else _game_state.player2_x,
			StageConstants.FLOOR_TOP_Y,
			_game_state.player_local_z if player_index == 1 else _game_state.player2_local_z
		)
		var release := ground + Vector3.UP * MENU_RELEASE_HEIGHT
		var hover := release + Vector3.UP * MENU_HELICOPTER_ABOVE_RELEASE
		var camera_local_hover := _menu_camera.to_local(hover)
		var hover_depth := maxf(-camera_local_hover.z, 4.0)
		var hover_uv := _menu_camera.unproject_position(hover) / viewport_size

		var start_uv := Vector2(0.68, -0.18) if player_index == 1 else Vector2(1.18, 0.31)
		var start_outward := Vector2(0.0, -1.0) if player_index == 1 else Vector2(1.0, 0.0)
		var start_depth := hover_depth + (7.0 if player_index == 1 else 10.0)
		var start_report := _resolve_menu_offscreen_point(
			info,
			start_uv,
			start_outward,
			start_depth,
			hover,
			true
		)
		var start: Vector3 = start_report.get("position", hover + Vector3.UP * 20.0)

		var approach_c1_uv := Vector2(0.67, 0.05) if player_index == 1 else Vector2(0.98, 0.32)
		var approach_c2_uv := (
			hover_uv + Vector2(0.035, -0.14)
			if player_index == 1
			else hover_uv + Vector2(0.11, -0.055)
		)
		var approach_c1 := _menu_camera.project_position(
			approach_c1_uv * viewport_size,
			lerpf(start_depth, hover_depth, 0.36)
		)
		var approach_c2 := _menu_camera.project_position(
			approach_c2_uv * viewport_size,
			lerpf(start_depth, hover_depth, 0.80)
		)

		var exit_uv := Vector2(0.76, -0.20) if player_index == 1 else Vector2(1.20, 0.18)
		var exit_outward := Vector2(0.0, -1.0) if player_index == 1 else Vector2(1.0, 0.0)
		var exit_depth := hover_depth + (8.0 if player_index == 1 else 11.0)
		var exit_report := _resolve_menu_offscreen_point(
			info,
			exit_uv,
			exit_outward,
			exit_depth,
			hover,
			false
		)
		var exit: Vector3 = exit_report.get("position", hover + Vector3.UP * 24.0)
		var exit_c1_uv := (
			hover_uv + Vector2(0.06, -0.10)
			if player_index == 1
			else hover_uv + Vector2(0.12, -0.035)
		)
		var exit_c2_uv := Vector2(0.75, -0.03) if player_index == 1 else Vector2(1.02, 0.20)
		var exit_c1 := _menu_camera.project_position(
			exit_c1_uv * viewport_size,
			lerpf(hover_depth, exit_depth, 0.28)
		)
		var exit_c2 := _menu_camera.project_position(
			exit_c2_uv * viewport_size,
			lerpf(hover_depth, exit_depth, 0.72)
		)

		var approach_direction := (approach_c1 - start).normalized()
		var hover_direction := (hover - approach_c2).normalized()
		info["ground"] = ground
		info["release"] = release
		info["hover"] = hover
		info["start"] = start
		info["approach_c1"] = approach_c1
		info["approach_c2"] = approach_c2
		info["exit"] = exit
		info["exit_c1"] = exit_c1
		info["exit_c2"] = exit_c2
		info["direction"] = hover_direction
		info["approach_direction"] = approach_direction
		info["ocean_side_drop"] = false
		info["inward_direction"] = Vector3.ZERO
		info["world_velocity"] = Vector3.ZERO
		info["start_screen_bounds"] = start_report.get("bounds", {})
		info["exit_screen_bounds"] = exit_report.get("bounds", {})
		info["start_fully_offscreen"] = bool(start_report.get("fully_offscreen", false))
		info["exit_fully_offscreen"] = bool(exit_report.get("fully_offscreen", false))
		info["downwash"] = _create_menu_downwash(ground, player_index)
		var holder := info.get("holder") as Node3D
		_set_hatch_openness(info, 0.0)
		_set_flight_transform(holder, start, approach_direction, 0.0, 0.0)
		if holder != null:
			info["last_position"] = holder.global_position


func _resolve_menu_offscreen_point(
	info: Dictionary,
	initial_uv: Vector2,
	outward_uv: Vector2,
	depth: float,
	look_target: Vector3,
	look_toward_target: bool
) -> Dictionary:
	var holder := info.get("holder") as Node3D
	var viewport := _menu_camera.get_viewport() if _menu_camera != null else null
	if holder == null or viewport == null:
		return {}
	var viewport_size := viewport.get_visible_rect().size
	var uv := initial_uv
	var candidate := look_target
	var bounds: Dictionary = {}
	for _step: int in range(MENU_OFFSCREEN_MAX_STEPS):
		candidate = _menu_camera.project_position(uv * viewport_size, depth)
		var direction := (
			(look_target - candidate).normalized()
			if look_toward_target
			else (candidate - look_target).normalized()
		)
		_set_flight_transform(holder, candidate, direction, 0.0, 0.0)
		bounds = _helicopter_screen_bounds(info)
		if _screen_bounds_fully_outside(bounds, MENU_OFFSCREEN_PLACEMENT_MARGIN_RATIO):
			return {
				"position": candidate,
				"bounds": bounds,
				"fully_offscreen": true,
			}
		uv += outward_uv * MENU_OFFSCREEN_STEP_RATIO
	return {
		"position": candidate,
		"bounds": bounds,
		"fully_offscreen": _screen_bounds_fully_outside(
			bounds,
			MENU_OFFSCREEN_PLACEMENT_MARGIN_RATIO
		),
	}


func _update_menu_departure_timeline(delta: float) -> void:
	if _update_authored_menu_departure(delta):
		return
	var approach_progress := clampf(
		_phase_elapsed / MENU_PICKUP_APPROACH_DURATION,
		0.0,
		1.0
	)
	var eased_approach := smoothstep(0.0, 1.0, approach_progress)
	var pickup_timeline := maxf(0.0, _phase_elapsed - MENU_PICKUP_APPROACH_DURATION)
	var latest_pickup_end := 2.18 + MENU_PICKUP_P2_DELAY
	var exit_start := latest_pickup_end + 0.22
	var exit_progress := clampf(
		(pickup_timeline - exit_start) / MENU_PICKUP_EXIT_DURATION,
		0.0,
		1.0
	)
	if not _all_menu_players_captured():
		exit_progress = 0.0
	var eased_exit := smoothstep(0.0, 1.0, exit_progress)
	var all_captured := true

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var start: Vector3 = info.get("start", Vector3.ZERO)
		var hover: Vector3 = info.get("hover", Vector3.ZERO)
		var exit: Vector3 = info.get("exit", start)
		var direction: Vector3 = info.get("direction", Vector3.FORWARD)
		var holder := info.get("holder") as Node3D
		if approach_progress < 1.0:
			var approach_c1: Vector3 = info.get("approach_c1", start.lerp(hover, 0.35))
			var approach_c2: Vector3 = info.get("approach_c2", start.lerp(hover, 0.78))
			var approach_position := _cubic_bezier(
				start,
				approach_c1,
				approach_c2,
				hover,
				eased_approach
			)
			var bank := (-0.10 if player_index == 1 else 0.10) * sin(approach_progress * PI)
			_set_hatch_openness(info, 0.0)
			_set_flight_transform(
				holder,
				approach_position,
				direction,
				bank,
				deg_to_rad(-3.0) * (1.0 - eased_approach)
			)
			_set_menu_downwash(info, true)
			_update_menu_screen_evidence(info)
			_remember_helicopter_velocity(info)
			all_captured = false
			continue

		var hover_bob := sin((_total_elapsed + player_index * 0.41) * 3.2) * 0.055
		var current_position := hover + Vector3.UP * hover_bob
		if exit_progress > 0.0:
			var exit_c1: Vector3 = info.get("exit_c1", hover.lerp(exit, 0.28))
			var exit_c2: Vector3 = info.get("exit_c2", hover.lerp(exit, 0.72))
			current_position = _cubic_bezier(
				hover,
				exit_c1,
				exit_c2,
				exit,
				eased_exit
			)
		var exit_bank := (-0.14 if player_index == 1 else 0.14) * sin(exit_progress * PI)
		_set_flight_transform(
			holder,
			current_position,
			direction,
			exit_bank,
			deg_to_rad(-7.0) * sin(exit_progress * PI)
		)

		var player_delay := MENU_PICKUP_P2_DELAY if player_index == 2 else 0.0
		var grab_start := 0.90 + player_delay
		var grab_progress := clampf(
			(pickup_timeline - grab_start) / 1.05,
			0.0,
			1.0
		)
		var hatch_openness := clampf(
			pickup_timeline / MENU_PICKUP_HATCH_OPEN_DURATION,
			0.0,
			1.0
		)
		_set_hatch_openness(info, hatch_openness)
		_set_menu_downwash(info, exit_progress < 0.92)
		if not _update_menu_rope_ladder_actor(info, grab_progress, delta):
			return

		all_captured = all_captured and bool(info.get("captured", false))
		_update_menu_screen_evidence(info)
		_remember_helicopter_velocity(info)

	if (
		all_captured
		and exit_progress >= 1.0
		and _all_menu_helicopters_fully_offscreen()
		and _is_scene_cover_complete()
	):
		_complete_menu_departure()


func _complete_menu_departure() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	if _player_controller != null:
		_player_controller.complete_intro_extraction()
	_start_locked = false
	_cleanup_helicopters(false)
	set_process(false)
	_emit_presentation_finished(true)


func _update_authored_menu_departure(delta: float) -> bool:
	if _menu_flight_profile == null or not is_instance_valid(_menu_flight_profile):
		return false
	var everyone_gripped := _all_menu_players_captured()
	var launch_ready := everyone_gripped
	if menu_launch_ready.is_valid():
		launch_ready = launch_ready and bool(menu_launch_ready.call())
	for info: Dictionary in _helicopters:
		var delay := MENU_LADDER_P2_DELAY if int(info.get("player_index", 1)) == 2 else 0.0
		launch_ready = launch_ready and float(info.get("pickup_path_time", 0.0)) >= MENU_LADDER_DEPART_PATH_TIME + delay

	if _menu_boost_started:
		_menu_launch_elapsed += delta
	elif launch_ready:
		_menu_launch_charge_elapsed += delta
		if _menu_launch_charge_elapsed >= MENU_BOOST_CHARGE_DURATION:
			_menu_boost_started = true
			_menu_launch_elapsed = 0.0
			_menu_camera_shake_remaining = MENU_CAMERA_SHAKE_DURATION
			menu_boost_launched.emit()
	var charge := clampf(_menu_launch_charge_elapsed / MENU_BOOST_CHARGE_DURATION, 0.0, 1.0)
	_menu_pickup_path_time = _menu_flight_profile.get_runtime_duration()
	var all_captured := true
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var depart_at := MENU_LADDER_DEPART_PATH_TIME + (MENU_LADDER_P2_DELAY if player_index == 2 else 0.0)
		var path_time := minf(float(info.get("pickup_path_time", 0.0)) + delta, depart_at)
		info["pickup_path_time"] = path_time
		_menu_pickup_path_time = minf(_menu_pickup_path_time, path_time)
		_menu_flight_profile.seek_runtime(path_time)
		var state := _menu_flight_profile.get_player_state(player_index)
		if state.is_empty():
			_fail_safe("editable rope-ladder path became unavailable")
			return true
		var holder := info.get("holder") as Node3D
		if path_time >= depart_at:
			if not info.has("launch_origin"):
				info["launch_origin"] = state.get("position", holder.global_position)
				info["charge_rotation"] = holder.global_basis.get_rotation_quaternion()
			var launch_basis := Basis(Vector3.RIGHT, MENU_BOOST_PITCH)
			var launch_position: Vector3 = info["launch_origin"]
			if _menu_boost_started:
				# A single straight acceleration path and one immutable attitude.
				# Acceleration, path tangents and camera motion cannot steer the body.
				var t := _menu_launch_elapsed
				var accelerating := minf(t, MENU_BOOST_ACCEL_TIME)
				var distance := 0.5 * MENU_BOOST_SPEED / MENU_BOOST_ACCEL_TIME * accelerating * accelerating
				distance += MENU_BOOST_SPEED * maxf(t - MENU_BOOST_ACCEL_TIME, 0.0)
				launch_position += MENU_BOOST_DIRECTION.normalized() * distance
				var exhaust := info.get("boost_exhaust") as HelicopterBoostExhaust
				if exhaust != null:
					exhaust.ignite()
			else:
				var from_rotation: Quaternion = info["charge_rotation"]
				launch_basis = Basis(from_rotation.slerp(launch_basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, charge)))
			holder.global_transform = Transform3D(launch_basis, launch_position)
		else:
			_set_flight_transform(
				holder, state.get("position", Vector3.ZERO),
				_menu_level_flight_direction(state.get("direction", Vector3.FORWARD)),
				float(state.get("bank", 0.0)), float(state.get("pitch", 0.0))
			)
		_update_menu_engine_charge(info, charge)
		_set_hatch_openness(info, float(state.get("hatch", 0.0)))
		_set_menu_downwash(info, not _menu_boost_started or _menu_launch_elapsed < 0.35)
		var grab_progress := clampf(float(state.get("action_progress", 0.0)), 0.0, 1.0)
		if not _update_menu_rope_ladder_actor(info, grab_progress, delta):
			return true
		all_captured = all_captured and bool(info.get("captured", false))
		_update_menu_screen_evidence(info)
		_remember_helicopter_velocity(info)
	_menu_pickup_camera_intensity = lerpf(_menu_pickup_camera_intensity, charge * 0.8, clampf(delta * 7.0, 0.0, 1.0))
	if all_captured and _menu_boost_started and _menu_launch_elapsed >= MENU_BOOST_FLIGHT_DURATION and _is_scene_cover_complete():
		_complete_menu_departure()
	return true


func _update_menu_engine_charge(info: Dictionary, charge: float) -> void:
	var model := info.get("model") as Node3D
	var base_position: Vector3 = info.get("model_rest_position", Vector3.ZERO)
	# Charge begins only after every participating character has a secure grip.
	var charging := _menu_launch_charge_elapsed > 0.0 and not _menu_boost_started
	var spool := charge if charging else 0.0
	info["rotor_speed_factor"] = 1.8 if _menu_boost_started else 1.0 + spool * 0.55
	if model != null:
		if not charging:
			model.position = base_position
		else:
			# Shake the visible fuselage without moving the pickup target.
			var phase := _total_elapsed * 145.0 + int(info.get("player_index", 1)) * 1.7
			model.position = base_position + Vector3(sin(phase), sin(phase * 1.31) * 0.7, cos(phase * 0.93) * 0.4) * (0.018 + 0.070 * spool)
	var rotor_audio := info.get("audio") as AudioStreamPlayer3D
	if rotor_audio != null:
		var base_pitch := 0.96 if int(info.get("player_index", 1)) == 1 else 1.04
		rotor_audio.pitch_scale = base_pitch * (1.65 if _menu_boost_started else 1.0 + 0.4 * spool)
		rotor_audio.volume_db = -10.0 if _menu_boost_started else lerpf(-18.0, -12.0, spool)


func _update_menu_rope_ladder_actor(
	info: Dictionary,
	grab_progress: float,
	delta: float
) -> bool:
	var ladder := info.get("rope_ladder") as PhysicalRopeLadder
	if ladder == null or not is_instance_valid(ladder):
		_fail_safe("physical rope ladder became unavailable")
		return false
	var player_index := int(info.get("player_index", 1))
	var player_delay := MENU_LADDER_P2_DELAY if player_index == 2 else 0.0
	var deploy_progress := clampf(
		(_phase_elapsed - MENU_LADDER_DEPLOY_START - player_delay)
		/ MENU_LADDER_DEPLOY_DURATION,
		0.0,
		1.0
	)
	if _menu_flight_profile != null and is_instance_valid(_menu_flight_profile):
		var authored_state := _menu_flight_profile.get_player_state(player_index)
		if not authored_state.is_empty() and authored_state.has("ladder_deploy"):
			deploy_progress = clampf(float(authored_state.get("ladder_deploy", deploy_progress)), 0.0, 1.0)
	ladder.set_deploy_progress(deploy_progress)
	# Keep the full rope outside the cabin throughout the hanging departure.
	ladder.set_winch_progress(0.0)
	if not bool(info.get("approach_started", false)):
		if not ladder.is_ready_for_ground_pickup():
			return true
		info["approach_started"] = true
		info["approach_started_at"] = _phase_elapsed
	if not bool(info.get("pickup_started", false)):
		var target: Vector3 = info.get("pickup_target", info.get("ground", Vector3.ZERO))
		info["approach_complete"] = _player_controller.update_intro_pickup_approach(player_index, target, delta)
	if grab_progress > 0.0 and bool(info.get("approach_complete", false)) and (ladder.is_fully_deployed() or bool(info.get("pickup_started", false))):
		if not bool(info.get("pickup_started", false)):
			if not _player_controller.begin_intro_ladder_grab(player_index, MENU_LADDER_GRAB_DURATION):
				_fail_safe("ladder grab animation could not start")
				return false
			info["pickup_started"] = true
			info["grab_started_at"] = _phase_elapsed
		# Start the jump/reach clock only after the run has actually finished.
		var contact_progress := clampf((_phase_elapsed - float(info["grab_started_at"])) / MENU_LADDER_GRAB_DURATION, 0.0, 1.0)
		if not _player_controller.update_intro_ladder_grab(
			player_index,
			ladder.get_grip_data(),
			contact_progress,
			delta
		):
			_fail_safe("character could not stay attached to the physical rung")
			return false
		if contact_progress >= 1.0:
			ladder.set_payload_active(true)
			_set_hatch_openness(info, 1.0)
			if not bool(info.get("captured", false)):
				info["captured_at"] = _phase_elapsed
			info["captured"] = true
	return true


func _menu_suction_target(
	ground: Vector3,
	hatch_position: Vector3,
	progress: float,
	player_index: int
) -> Vector3:
	var side := -1.0 if player_index == 1 else 1.0
	var start := ground + Vector3.UP * 1.25
	return _cubic_bezier(
		start,
		start + Vector3(side * 0.18, 1.75, 0.12),
		hatch_position + Vector3(-side * 0.30, -2.25, 0.08),
		hatch_position,
		progress
	)


func _menu_level_flight_direction(direction: Vector3) -> Vector3:
	var leveled := direction
	leveled.y = clampf(leveled.y, -0.14, 0.14)
	if leveled.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return leveled.normalized()


func _update_authored_menu_arrival() -> bool:
	if _menu_flight_profile == null or not is_instance_valid(_menu_flight_profile):
		return false
	_menu_flight_profile.seek_runtime(_phase_elapsed)
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var state := _menu_flight_profile.get_player_state(player_index)
		if state.is_empty():
			_fail_safe("editable arrival path became unavailable")
			return true
		var holder := info.get("holder") as Node3D
		var flight_position: Vector3 = state.get("position", Vector3.ZERO)
		if (
			bool(info.get("dropped", false))
			and not info.has("drop_boost_elapsed")
			and _phase_elapsed - float(info.get("drop_timeline", _phase_elapsed)) >= MENU_DROP_BOOST_DELAY
		):
			var boost_heading := _menu_level_flight_direction(state.get("direction", Vector3.FORWARD))
			boost_heading.y = 0.0
			if _menu_camera != null:
				# Never fire the jet toward the lens; peel off sideways and away.
				var away := -_menu_camera.global_basis.z
				away.y = 0.0
				away = away.normalized()
				var toward_lens := minf(boost_heading.dot(away), 0.0)
				boost_heading = boost_heading - away * toward_lens + away * 0.35
			_begin_drop_boost(
				info,
				info.get("world_velocity", Vector3.ZERO),
				boost_heading.normalized() + Vector3.UP * 0.14
			)
		if info.has("drop_boost_elapsed"):
			_update_drop_boost(info, get_process_delta_time())
			flight_position = holder.global_position
		else:
			_set_flight_transform(
				holder,
				flight_position,
				state.get("direction", Vector3.FORWARD),
				float(state.get("bank", 0.0)),
				float(state.get("pitch", 0.0))
			)
		_update_intro_cabin_wait_passenger(info)
		_set_hatch_openness(info, float(state.get("hatch", 0.0)))
		var ground: Vector3 = info.get("ground", Vector3.ZERO)
		_set_menu_downwash(
			info,
			flight_position.y - ground.y < 13.5
			and not _menu_flight_profile.is_runtime_finished()
			and float(info.get("drop_boost_elapsed", 0.0)) < DROP_BOOST_CHARGE_DURATION + 0.35
		)
		_update_menu_screen_evidence(info)
		_remember_helicopter_velocity(info)
		if (
			float(state.get("action_progress", 0.0)) >= 1.0
			and not bool(info.get("dropped", false))
		):
			info["drop_timeline"] = _phase_elapsed
			_drop_player(info)
		_update_landing_impact(info)

	if not _menu_flight_profile.is_runtime_finished():
		return true
	var all_physics_valid := true
	var all_recovered := true
	for info: Dictionary in _helicopters:
		if not bool(info.get("dropped", false)):
			all_recovered = false
			continue
		var drop_state := _player_controller.get_intro_drop_state(int(info["player_index"]))
		if not bool(drop_state.get("physics_valid", false)):
			all_physics_valid = false
			break
		all_recovered = all_recovered and bool(drop_state.get("recovery_complete", false))
	if not all_physics_valid:
		_fail_safe("intro ragdoll physics became unavailable")
		return true
	if all_recovered and _all_menu_helicopters_fully_offscreen():
		_complete_arrival()
	return true


func _update_timeline() -> void:
	if not _menu_preview_mode:
		_update_gameplay_ladder_timeline()
		return
	if _menu_preview_mode and _update_authored_menu_arrival():
		return
	var approach_duration := MENU_APPROACH_DURATION if _menu_preview_mode else APPROACH_DURATION
	var hover_before_first_drop := (
		MENU_HOVER_BEFORE_FIRST_DROP if _menu_preview_mode else HOVER_BEFORE_FIRST_DROP
	)
	var p2_drop_delay := MENU_P2_DROP_DELAY if _menu_preview_mode else P2_DROP_DELAY
	var depart_duration := MENU_DEPART_DURATION if _menu_preview_mode else DEPART_DURATION
	var depart_after_drop := MENU_DEPART_AFTER_DROP if _menu_preview_mode else DEPART_AFTER_DROP
	var approach_weight := clampf(_phase_elapsed / approach_duration, 0.0, 1.0)
	var eased_approach := smoothstep(0.0, 1.0, approach_weight)
	var timeline := maxf(0.0, _phase_elapsed - approach_duration)
	var latest_drop_time := hover_before_first_drop
	if _menu_preview_mode and _menu_camera != null:
		var camera_return_weight := _menu_camera_return_weight()
		_menu_camera.fov = lerpf(
			_menu_camera_base_fov + MENU_CAMERA_WIDE_FOV_DELTA,
			_menu_camera_base_fov,
			camera_return_weight
		)

	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var drop_time := hover_before_first_drop + (p2_drop_delay if player_index == 2 else 0.0)
		latest_drop_time = maxf(latest_drop_time, drop_time)
		var start: Vector3 = info.get("start", Vector3.ZERO)
		var hover: Vector3 = info.get("hover", Vector3.ZERO)
		var exit: Vector3 = info.get("exit", start)
		var direction: Vector3 = info.get("direction", Vector3.FORWARD)
		var approach_direction: Vector3 = info.get("approach_direction", direction)
		var holder := info.get("holder") as Node3D
		if approach_weight < 1.0:
			var approach_pos := start.lerp(hover, eased_approach)
			var approach_flight_direction := approach_direction.slerp(direction, approach_weight).normalized()
			if _menu_preview_mode:
				var approach_c1: Vector3 = info.get("approach_c1", start.lerp(hover, 0.35))
				var approach_c2: Vector3 = info.get("approach_c2", start.lerp(hover, 0.75))
				approach_pos = _cubic_bezier(
					start,
					approach_c1,
					approach_c2,
					hover,
					eased_approach
				)
				approach_flight_direction = _cubic_bezier_tangent(
					start,
					approach_c1,
					approach_c2,
					hover,
					eased_approach
				)
			var bank := sin(approach_weight * PI) * (0.13 if player_index == 1 else -0.13)
			if not _menu_preview_mode:
				var level_weight := smoothstep(0.72, 1.0, approach_weight)
				approach_flight_direction = approach_direction.slerp(direction, level_weight).normalized()
			_set_hatch_openness(info, 0.0)
			_set_flight_transform(
				holder,
				approach_pos,
				approach_flight_direction,
				bank,
				-deg_to_rad(2.0) * sin(approach_weight * PI)
			)
			_update_intro_cabin_wait_passenger(info)
			_set_menu_downwash(info, _menu_preview_mode and approach_weight >= 0.86)
			_update_menu_screen_evidence(info)
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
			(timeline - drop_time - depart_after_drop) / depart_duration,
			0.0,
			1.0
		)
		var current_flight_direction := direction
		if depart_weight > 0.0:
			var eased_depart := smoothstep(0.0, 1.0, depart_weight)
			if _menu_preview_mode:
				var exit_c1: Vector3 = info.get("exit_c1", drifted_hover.lerp(exit, 0.30))
				var exit_c2: Vector3 = info.get("exit_c2", drifted_hover.lerp(exit, 0.72))
				current_pos = _cubic_bezier(
					drifted_hover,
					exit_c1,
					exit_c2,
					exit,
					eased_depart
				)
				current_pos += Vector3.UP * hover_bob * (1.0 - eased_depart)
				var path_tangent := _cubic_bezier_tangent(
					drifted_hover,
					exit_c1,
					exit_c2,
					exit,
					eased_depart
				)
				var turn_weight := smoothstep(
					0.0,
					1.0,
					clampf(depart_weight / MENU_DEPART_TURN_BLEND_RATIO, 0.0, 1.0)
				)
				current_flight_direction = direction.slerp(path_tangent, turn_weight).normalized()
			else:
				current_pos = drifted_hover.lerp(exit, eased_depart)
		var presentation_bank := (
			(0.055 if player_index == 1 else -0.055) * hatch_openness
		)
		var side_bank := presentation_bank + (
			(0.16 if player_index == 1 else -0.16) * sin(depart_weight * PI)
		)
		var pitch := DROP_PRESENTATION_PITCH * hatch_openness
		pitch += DEPART_CLIMB_PITCH * sin(depart_weight * PI)
		_set_flight_transform(holder, current_pos, current_flight_direction, side_bank, pitch)
		_update_intro_cabin_wait_passenger(info)
		_set_menu_downwash(
			info,
			_menu_preview_mode and depart_weight < 0.38 and timeline <= drop_time + 1.35
		)
		_update_menu_screen_evidence(info)
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
		timeline >= latest_drop_time + depart_after_drop + depart_duration
	)
	if _menu_preview_mode:
		helis_exited = helis_exited and _all_menu_helicopters_fully_offscreen()
	if helis_exited and all_recovered:
		_complete_arrival()


func _update_gameplay_ladder_timeline() -> void:
	var delta := get_process_delta_time()
	var all_ready := true
	var all_departed := true
	for info: Dictionary in _helicopters:
		if not _update_gameplay_helicopter(info, delta):
			return
		var landed := bool(info.get("landed", false))
		var land_hold := float(info.get("landed_hold", 0.0))
		all_ready = all_ready and landed and land_hold >= GP_LAND_HOLD
		var departed := (
			str(info.get("gp_phase", "")) == "depart"
			and float(info.get("gp_phase_elapsed", 0.0)) >= GP_EXIT_MIN_TIME
			and _screen_bounds_fully_outside(_helicopter_screen_bounds(info), 0.10)
		)
		all_departed = all_departed and departed
	if all_ready and _start_locked:
		# Unlock start after the hold so HUD can show Ready, but keep the UAL
		# idle presentation until the course actually begins.
		for info: Dictionary in _helicopters:
			_player_controller.complete_intro_ladder_landing(int(info.get("player_index", 1)), _game_state)
		_start_locked = false
		_emit_presentation_finished(true)
	if all_ready and all_departed:
		_complete_arrival()


func _set_gp_phase(info: Dictionary, phase: String) -> void:
	info["gp_phase"] = phase
	info["gp_phase_elapsed"] = 0.0


func _gp_phase_timeout(phase: String) -> float:
	match phase:
		"approach":
			return GP_APPROACH_DURATION * 2.5
		"lowering":
			return GP_LOWER_DURATION * 3.5
		"swing":
			return GP_SWING_DURATION * 2.5
		"depart":
			return DEPART_DURATION * 2.5
		_:
			return 8.0


func _solve_launch_velocity(origin: Vector3, landing: Vector3, duration: float) -> Vector3:
	var flight_time := maxf(duration, 0.08)
	var gravity := Vector3(0.0, -9.8, 0.0)
	return (landing - origin - gravity * (0.5 * flight_time * flight_time)) / flight_time


func _update_intro_cabin_ride_passenger(info: Dictionary, should_show: bool) -> void:
	if (
		_player_controller == null
		or bool(info.get("hanging", false))
		or bool(info.get("jumped", false))
	):
		return
	_player_controller.update_intro_cabin_ride(
		int(info.get("player_index", 1)),
		_cabin_ride_transform(info),
		should_show
	)


func _update_gameplay_ladder_actor(
	info: Dictionary,
	reach_progress: float,
	swing_angle: float,
	delta: float
) -> bool:
	var ladder := info.get("rope_ladder") as PhysicalRopeLadder
	if ladder == null or not is_instance_valid(ladder):
		_fail_safe("gameplay rope ladder became unavailable")
		return false
	var player_index := int(info.get("player_index", 1))
	if not bool(info.get("hanging", false)):
		if not _player_controller.begin_intro_ladder_hang(player_index):
			_fail_safe("P%d could not grab the rope ladder" % player_index)
			return false
		info["hanging"] = true
	var grip_data := ladder.get_grip_data()
	grip_data["inward"] = info.get("inward_direction", Vector3.ZERO)
	grip_data["carrier_transform"] = (info["holder"] as Node3D).global_transform
	if not _player_controller.update_intro_ladder_hang(
		player_index,
		grip_data,
		reach_progress,
		swing_angle,
		delta
	):
		_fail_safe("P%d could not stay on the rope ladder" % player_index)
		return false
	return true


func _set_ladder_mount_sway(info: Dictionary, sway: float) -> void:
	var mount := info.get("rope_ladder_mount") as Node3D
	if mount == null or not is_instance_valid(mount):
		return
	mount.rotation = Vector3(sway, 0.0, 0.0)


func _launch_gameplay_jump(info: Dictionary) -> bool:
	var player_index := int(info.get("player_index", 1))
	var ground: Vector3 = info.get("ground", Vector3.ZERO)
	var grab_state := _player_controller.get_intro_ladder_grab_state(player_index)
	var origin: Vector3 = grab_state.get("character_position", _hatch_release_position(info))
	var landing := ground + Vector3.UP * 0.9
	var velocity := _solve_launch_velocity(origin, landing, GP_FLIGHT_DURATION)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not _player_controller.begin_intro_ladder_jump(
		player_index,
		velocity,
		ground,
		GP_FLIGHT_DURATION,
		ground
	):
		_fail_safe("P%d could not jump from the rope ladder" % player_index)
		return false
	info["jumped"] = true
	info["hanging"] = false
	info["launch_origin"] = origin
	info["launch_velocity"] = velocity
	info["launch_horizontal_speed"] = horizontal.length()
	var ladder := info.get("rope_ladder") as PhysicalRopeLadder
	if ladder != null and is_instance_valid(ladder):
		ladder.set_payload_active(false)
	_set_ladder_mount_sway(info, 0.0)
	return true


func _update_gameplay_jump(info: Dictionary, delta: float) -> bool:
	var player_index := int(info.get("player_index", 1))
	if bool(info.get("landed", false)):
		info["landed_hold"] = float(info.get("landed_hold", 0.0)) + delta
		return true
	if not bool(info.get("jumped", false)):
		return true
	var jump_state := _player_controller.update_intro_ladder_jump(player_index, delta)
	if not bool(jump_state.get("active", false)):
		_fail_safe("P%d jump state was lost" % player_index)
		return false
	if bool(jump_state.get("floor_contacted", false)) and not bool(info.get("impact_played", false)):
		var impact_position: Vector3 = jump_state.get("position", info.get("ground", Vector3.ZERO))
		info["impact_played"] = true
		info["first_impact_position"] = impact_position
		_play_landing_impact(impact_position, player_index)
		_spawn_menu_landing_dust(impact_position, player_index)
	if bool(jump_state.get("landed", false)):
		var ground: Vector3 = info.get("ground", Vector3.ZERO)
		info["landed"] = true
		info["landed_hold"] = 0.0
		info["final_impact_position"] = jump_state.get("position", ground)
	return true


## The integral of a quintic velocity blend. Its acceleration is zero at both
## ends, so braking, the low pass and departure share the same smooth join.
func _flight_ramp_integral(time: float, duration: float) -> float:
	var u := clampf(time / duration, 0.0, 1.0)
	return duration * (2.5 * pow(u, 4.0) - 3.0 * pow(u, 5.0) + pow(u, 6.0)) + maxf(time - duration, 0.0)


func _flight_ramp(time: float, duration: float) -> float:
	var u := clampf(time / duration, 0.0, 1.0)
	return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))


func _sample_gameplay_approach(info: Dictionary, time: float) -> Dictionary:
	var start: Vector3 = info["start"]
	var pass_origin: Vector3 = info["hover_ocean"]
	var direction: Vector3 = info["direction"]
	if time >= GP_APPROACH_DURATION:
		return {"position": pass_origin + direction * PASS_SPEED * (time - GP_APPROACH_DURATION), "velocity": direction * PASS_SPEED}
	var distance := Vector2(start.x - pass_origin.x, start.z - pass_origin.z).length()
	var initial_speed := 2.0 * distance / GP_APPROACH_DURATION - PASS_SPEED
	var ramp := _flight_ramp(time, GP_APPROACH_DURATION)
	var travel := initial_speed * time + (PASS_SPEED - initial_speed) * _flight_ramp_integral(time, GP_APPROACH_DURATION)
	var position_now := start + direction * travel
	position_now.y = lerpf(start.y, pass_origin.y, ramp)
	return {"position": position_now, "velocity": direction * lerpf(initial_speed, PASS_SPEED, ramp)}


func _update_gameplay_helicopter(info: Dictionary, delta: float) -> bool:
	var player_index := int(info.get("player_index", 1))
	var phase := str(info.get("gp_phase", "approach"))
	var elapsed := float(info.get("gp_phase_elapsed", 0.0)) + delta
	info["gp_phase_elapsed"] = elapsed
	info["flight_elapsed"] = float(info.get("flight_elapsed", 0.0)) + delta
	if elapsed > _gp_phase_timeout(phase):
		_fail_safe("P%d gameplay phase %s exceeded %.1f seconds" % [player_index, phase, _gp_phase_timeout(phase)])
		return false
	var holder := info.get("holder") as Node3D
	var pass_direction: Vector3 = info["direction"]
	var flight_time := float(info["flight_elapsed"])
	var player_side := float(info.get("player_side", -1.0))
	# Aircraft time never waits for the passenger or the other helicopter.
	if phase == "depart":
		_update_drop_boost(info, delta)
	else:
		var flight := _sample_gameplay_approach(info, flight_time)
		_set_flight_transform(holder, flight["position"], flight["velocity"], 0.0, 0.0)

	# Trigger from the actual rendered camera bounds, including the rotor tips.
	# This also works for the different solo/pair camera framing.
	if phase == "approach":
		_set_hatch_openness(info, smoothstep(0.0, HATCH_OPEN_DURATION, flight_time + GP_P2_DELAY))
		_update_intro_cabin_ride_passenger(info, true)
		if _screen_bounds_intersects_frame(_helicopter_screen_bounds(info)):
			info["entered_frame_at"] = _phase_elapsed
			info["lowering_started_at"] = _phase_elapsed
			_set_gp_phase(info, "lowering")
			phase = "lowering"
			elapsed = 0.0

	match phase:
		"approach":
			pass
		"lowering":
			_set_hatch_openness(info, GP_HATCH_KEEP_OPEN)
			var ladder := info.get("rope_ladder") as PhysicalRopeLadder
			ladder.set_deploy_progress(maxf(0.04, elapsed / GP_LOWER_DURATION))
			var reach := clampf(elapsed / GP_LOWER_DURATION, 0.0, 1.0)
			if not _update_gameplay_ladder_actor(info, reach, 0.0, delta):
				return false
			if reach >= 1.0 and ladder.is_fully_deployed():
				ladder.set_payload_active(true)
				_set_gp_phase(info, "swing")
		"swing":
			_set_hatch_openness(info, GP_HATCH_KEEP_OPEN)
			var swing_t := clampf(elapsed / GP_SWING_DURATION, 0.0, 1.0)
			var envelope := smoothstep(0.0, 0.18, swing_t)
			var swing_angle := deg_to_rad(GP_SWING_AMPLITUDE_DEG) * envelope * sin(swing_t * TAU * GP_SWING_CYCLES)
			if not _update_gameplay_ladder_actor(info, 1.0, swing_angle, delta):
				return false
			if swing_t >= 1.0 and flight_time >= GP_APPROACH_DURATION:
				if not _launch_gameplay_jump(info):
					return false
				# Maintain the incoming horizontal heading. P2 rises into a deeper lane;
				# the rotor discs stay separated while their screen paths cross.
				var depart_velocity := Vector3(-player_side * GP_EXIT_SPEED, 3.4 if player_index == 2 else 2.2, 5.0 if player_index == 2 else 2.5)
				_begin_drop_boost(info, pass_direction * PASS_SPEED, depart_velocity)
				info["released_at"] = _phase_elapsed
				_set_gp_phase(info, "depart")
		"depart":
			var ladder := info.get("rope_ladder") as PhysicalRopeLadder
			# Reel the rope in before ignition so it never trails the jet.
			ladder.set_winch_progress(smoothstep(0.0, DROP_BOOST_CHARGE_DURATION * 0.95, elapsed))
			_set_hatch_openness(info, 1.0 - smoothstep(0.45, 0.45 + HATCH_CLOSE_DURATION, elapsed))
			_set_ladder_mount_sway(info, 0.0)
		_:
			_fail_safe("P%d entered unknown gameplay phase %s" % [player_index, phase])
			return false
	_remember_helicopter_velocity(info)
	return _update_gameplay_jump(info, delta)


func _begin_drop_boost(info: Dictionary, drift_velocity: Vector3, boost_direction: Vector3) -> void:
	var holder := info.get("holder") as Node3D
	info["drop_boost_elapsed"] = 0.0
	info["drop_boost_origin"] = holder.global_position
	info["drop_boost_drift"] = drift_velocity
	info["drop_boost_direction"] = boost_direction.normalized()
	info["drop_boost_charge_rotation"] = holder.global_basis.get_rotation_quaternion()


## Slows down while the engine spools, then fires the tail jet along one
## straight line. The nose points down that line so the flame trails behind it.
func _update_drop_boost(info: Dictionary, delta: float) -> void:
	var holder := info.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return
	var t := float(info.get("drop_boost_elapsed", 0.0)) + delta
	info["drop_boost_elapsed"] = t
	var direction: Vector3 = info["drop_boost_direction"]
	var drift: Vector3 = info["drop_boost_drift"]
	# Drift eases down to 30% while charging, then keeps that residue under the jet.
	var charge_t := minf(t, DROP_BOOST_CHARGE_DURATION)
	var position_now: Vector3 = info["drop_boost_origin"]
	position_now += drift * (charge_t - 0.35 * charge_t * charge_t / DROP_BOOST_CHARGE_DURATION)
	position_now += drift * 0.3 * maxf(t - DROP_BOOST_CHARGE_DURATION, 0.0)
	var boost_rotation := Basis.looking_at(direction, Vector3.UP).get_rotation_quaternion()
	var model := info.get("model") as Node3D
	var rest_position: Vector3 = info.get("model_rest_position", Vector3.ZERO)
	var rotor_audio := info.get("audio") as AudioStreamPlayer3D
	var base_pitch := 0.96 if int(info.get("player_index", 1)) == 1 else 1.04
	var rotation_now: Quaternion
	if t < DROP_BOOST_CHARGE_DURATION:
		var charge := t / DROP_BOOST_CHARGE_DURATION
		var from_rotation: Quaternion = info["drop_boost_charge_rotation"]
		rotation_now = from_rotation.slerp(boost_rotation, smoothstep(0.0, 1.0, charge))
		info["rotor_speed_factor"] = 1.0 + charge * 0.55
		if model != null:
			var shake_phase := _total_elapsed * 145.0 + int(info.get("player_index", 1)) * 1.7
			model.position = rest_position + Vector3(sin(shake_phase), sin(shake_phase * 1.31) * 0.7, cos(shake_phase * 0.93) * 0.4) * (0.018 + 0.070 * charge)
		if rotor_audio != null:
			rotor_audio.pitch_scale = base_pitch * (1.0 + 0.4 * charge)
			rotor_audio.volume_db = lerpf(-18.0, -12.0, charge)
	else:
		var boost_t := t - DROP_BOOST_CHARGE_DURATION
		var accelerating := minf(boost_t, DROP_BOOST_ACCEL_TIME)
		var distance := 0.5 * DROP_BOOST_SPEED / DROP_BOOST_ACCEL_TIME * accelerating * accelerating
		distance += DROP_BOOST_SPEED * maxf(boost_t - DROP_BOOST_ACCEL_TIME, 0.0)
		position_now += direction * distance
		rotation_now = boost_rotation
		info["rotor_speed_factor"] = 1.8
		if model != null:
			model.position = rest_position
		if rotor_audio != null:
			rotor_audio.pitch_scale = base_pitch * 1.65
			rotor_audio.volume_db = -10.0
		var exhaust := info.get("boost_exhaust") as HelicopterBoostExhaust
		if exhaust != null and not exhaust.ignited:
			exhaust.ignite()
			if _menu_preview_mode:
				_menu_camera_shake_remaining = MENU_CAMERA_SHAKE_DURATION
	holder.global_transform = Transform3D(Basis(rotation_now), position_now)


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


func _all_menu_landing_impacts_held() -> bool:
	if not _menu_preview_mode or _helicopters.is_empty():
		return false
	for info: Dictionary in _helicopters:
		if not bool(info.get("impact_played", false)):
			return false
		if _total_elapsed - float(info.get("impact_elapsed", _total_elapsed)) < MENU_LANDED_POSE_HOLD:
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
		info["impact_elapsed"] = _total_elapsed
		_play_landing_impact(ragdoll_position, int(info["player_index"]))
		if _menu_preview_mode:
			_spawn_menu_landing_dust(ragdoll_position, int(info["player_index"]))
			_menu_camera_shake_remaining = MENU_CAMERA_SHAKE_DURATION
	var recovery_ready := (
		_all_menu_landing_impacts_held()
		if _menu_preview_mode
		else _all_intro_ragdolls_settled()
	)
	if recovery_ready and not bool(info.get("get_up_started", false)):
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
	if _player_controller != null and _start_locked:
		if _menu_preview_mode:
			_player_controller.complete_intro_drops(_game_state)
		else:
			for info: Dictionary in _helicopters:
				_player_controller.complete_intro_ladder_landing(
					int(info.get("player_index", 1)),
					_game_state
				)
	_start_locked = false
	_reset_menu_camera()
	_cleanup_helicopters(false)
	set_process(false)
	_emit_presentation_finished(true)


func _fail_safe(reason: String) -> void:
	push_warning("Helicopter arrival fail-safe: %s" % reason)
	if _player_controller != null:
		_player_controller.cancel_intro_drops()
	_start_locked = false
	_phase = "complete"
	_reset_menu_camera()
	_cleanup_helicopters(true)
	set_process(false)
	_emit_presentation_finished(false)


func _skip_missing_asset(reason: String) -> void:
	push_warning("Helicopter arrival skipped: %s" % reason)
	_start_locked = false
	_phase = "complete"
	_reset_menu_camera()
	_cleanup_helicopters(true)
	set_process(false)
	_emit_presentation_finished(false)


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
	if _menu_preview_mode:
		model.scale *= MENU_HELICOPTER_SCALE
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
	_apply_window_glass(model)
	_mount_godot_pilot(model)
	var cabin_light := OmniLight3D.new()
	cabin_light.name = "CabinLight"
	cabin_light.light_color = Color(1.0, 0.82, 0.62)
	cabin_light.light_energy = 0.0
	cabin_light.omni_range = 2.4
	cabin_light.shadow_enabled = false
	holder.add_child(cabin_light)
	var hatch_center := (hatch_left.global_position + hatch_right.global_position) * 0.5
	cabin_light.global_position = hatch_center + holder.global_basis.y.normalized() * 0.36
	var cockpit_light := OmniLight3D.new()
	cockpit_light.name = "CockpitLight"
	cockpit_light.light_color = Color(1.0, 0.92, 0.82)
	cockpit_light.light_energy = COCKPIT_LIGHT_ENERGY
	cockpit_light.omni_range = 2.0
	cockpit_light.shadow_enabled = false
	model.add_child(cockpit_light)
	cockpit_light.position = Vector3(0.0, 0.32, -0.78)

	var audio := AudioStreamPlayer3D.new()
	audio.name = "RotorLoop"
	audio.bus = "SFX"
	audio.stream = _rotor_stream
	audio.volume_db = -18.0
	audio.pitch_scale = 0.96 if player_index == 1 else 1.04
	audio.max_distance = 48.0
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	holder.add_child(audio)
	# Every aircraft leaves on the tail jet, whether it drops off or picks up.
	var exhaust := BoostExhaustScript.new() as HelicopterBoostExhaust
	exhaust.name = "TailBoostExhaust"
	model.add_child(exhaust)
	var tail_local := model.to_local(tail_rotor.global_position)
	exhaust.position = Vector3(0.0, tail_local.y, tail_local.z + 0.35)
	var visual_points := _collect_helicopter_visual_points(holder, model)
	holder.visible = false
	return {
		"player_index": player_index,
		"holder": holder,
		"model": model,
		"model_rest_position": model.position,
		"boost_exhaust": exhaust,
		"main_rotor": main_rotor,
		"tail_rotor": tail_rotor,
		"hatch_left": hatch_left,
		"hatch_right": hatch_right,
		"hatch_left_rotation": hatch_left.rotation,
		"hatch_right_rotation": hatch_right.rotation,
		"cabin_light": cabin_light,
		"audio": audio,
		"dropped": false,
		"get_up_started": false,
		"first_impact_position": Vector3.INF,
		"final_impact_position": Vector3.INF,
		"impact_played": false,
		"world_velocity": Vector3.ZERO,
		"visual_points": visual_points,
		"ever_visible_in_frame": false,
		"last_screen_bounds": {},
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


func _apply_window_glass(root: Node) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var window_node := str(mesh_instance.name) == "Windows"
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			var window_material := source != null and source.resource_name == "Windows"
			if not window_node and not window_material:
				continue
			var material := source.duplicate(true) as BaseMaterial3D if source != null else StandardMaterial3D.new()
			if material == null:
				material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			material.albedo_color = WINDOW_GLASS_COLOR
			material.roughness = 0.06
			material.metallic = 0.08
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
			mesh_instance.set_surface_override_material(surface_index, material)


func _mount_godot_pilot(model: Node3D) -> void:
	if model == null or not ResourceLoader.exists(GODOT_PLUSH_GLB):
		return
	var packed := ResourceLoader.load(GODOT_PLUSH_GLB) as PackedScene
	if packed == null:
		return
	var pilot := packed.instantiate() as Node3D
	if pilot == null:
		return
	pilot.name = "GodotPilot"
	model.add_child(pilot)
	pilot.position = PILOT_SEAT_POSITION
	pilot.rotation_degrees = PILOT_SEAT_ROTATION_DEGREES
	pilot.scale = Vector3.ONE * PILOT_SCALE
	_apply_plush_albedo(pilot)
	_disable_pilot_collision(pilot)
	var animation := pilot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation != null and animation.has_animation("idle"):
		animation.play("idle")
		animation.advance(0.2)
		animation.stop()
		animation.active = false
	_pose_pilot_seated(pilot)


func _apply_plush_albedo(root: Node) -> void:
	if root == null or not ResourceLoader.exists(GODOT_PLUSH_ALBEDO):
		return
	var albedo := ResourceLoader.load(GODOT_PLUSH_ALBEDO) as Texture2D
	if albedo == null:
		return
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface_index)
			var material := source.duplicate(true) as BaseMaterial3D if source != null else StandardMaterial3D.new()
			if material == null:
				material = StandardMaterial3D.new()
			material.albedo_texture = albedo
			material.vertex_color_use_as_albedo = true
			mesh_instance.set_surface_override_material(surface_index, material)


func _disable_pilot_collision(root: Node) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body == null:
			continue
		body.collision_layer = 0
		body.collision_mask = 0


func _pose_pilot_seated(pilot: Node3D) -> void:
	if pilot == null:
		return
	var skeleton := pilot.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var thigh_bend := Quaternion(Vector3.RIGHT, deg_to_rad(78.0))
	var shin_bend := Quaternion(Vector3.RIGHT, deg_to_rad(-82.0))
	var arm_forward := Quaternion(Vector3.FORWARD, deg_to_rad(28.0))
	_set_named_bone_rotation(skeleton, "DEF-thigh.L", thigh_bend)
	_set_named_bone_rotation(skeleton, "DEF-thigh.R", thigh_bend)
	_set_named_bone_rotation(skeleton, "DEF-shin.L", shin_bend)
	_set_named_bone_rotation(skeleton, "DEF-shin.R", shin_bend)
	_set_named_bone_rotation(skeleton, "DEF-upper_arm.L", arm_forward.inverse())
	_set_named_bone_rotation(skeleton, "DEF-upper_arm.R", arm_forward)


func _set_named_bone_rotation(skeleton: Skeleton3D, bone_name: String, bone_rotation: Quaternion) -> void:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return
	skeleton.set_bone_pose_rotation(bone_index, bone_rotation)


func _spin_rotors(delta: float) -> void:
	for info: Dictionary in _helicopters:
		var main_rotor := info.get("main_rotor") as Node3D
		var tail_rotor := info.get("tail_rotor") as Node3D
		var speed_factor := float(info.get("rotor_speed_factor", 1.0))
		if main_rotor != null and is_instance_valid(main_rotor):
			main_rotor.rotate_y(MAIN_ROTOR_SPEED * speed_factor * delta)
		if tail_rotor != null and is_instance_valid(tail_rotor):
			tail_rotor.rotate_x(TAIL_ROTOR_SPEED * speed_factor * delta)


func _set_flight_transform(
	holder: Node3D,
	world_position: Vector3,
	direction: Vector3,
	bank: float,
	pitch: float
) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	# Rotor thrust balances gravity and horizontal acceleration. Flight-path slope
	# is NOT fuselage pitch: a helicopter can climb with a nearly level cabin.
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	if not holder.has_meta("flight_position") or _phase not in ["arrival", "departure_pickup"]:
		holder.global_transform = Transform3D(Basis.looking_at(forward), world_position)
		holder.set_meta("flight_position", world_position)
		holder.set_meta("flight_velocity", Vector3.ZERO)
		holder.set_meta("flight_acceleration", Vector3.ZERO)
		holder.set_meta("flight_yaw", atan2(-forward.x, -forward.z))
		return
	var dt := maxf(get_process_delta_time(), 0.001)
	var last: Vector3 = holder.get_meta("flight_position")
	var previous_velocity: Vector3 = holder.get_meta("flight_velocity")
	var velocity := (world_position - last) / dt
	var measured_accel := ((velocity - previous_velocity) / dt).limit_length(18.0)
	var acceleration: Vector3 = holder.get_meta("flight_acceleration")
	acceleration = acceleration.lerp(measured_accel, 1.0 - exp(-dt / 0.16))
	var yaw: float = holder.get_meta("flight_yaw")
	var desired_yaw := atan2(-forward.x, -forward.z)
	# Tail rotor yaw control has a finite turn rate, including the exit turn.
	yaw += clampf(wrapf(desired_yaw - yaw, -PI, PI), -deg_to_rad(42.0) * dt, deg_to_rad(42.0) * dt)
	var heading := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var horizontal_accel := Vector3(acceleration.x, 0.0, acceleration.z)
	var drag_compensation := Vector3(velocity.x, 0.0, velocity.z) * 0.10
	var thrust_up := Vector3.UP * maxf(9.81 + acceleration.y, 5.0)
	var tilt_limit := 8.0 if _menu_preview_mode else 3.5
	thrust_up += (horizontal_accel + drag_compensation).limit_length(tilt_limit)
	thrust_up = thrust_up.normalized()
	var right := heading.cross(thrust_up).normalized()
	var target_basis := Basis(right, thrust_up, right.cross(thrust_up)).orthonormalized()
	# Authored attitude tracks are small artistic trim; acceleration owns the tilt.
	target_basis = target_basis * Basis(Vector3.FORWARD, bank * 0.12)
	target_basis = target_basis * Basis(Vector3.RIGHT, pitch * 0.12)
	var current_rotation := holder.global_basis.get_rotation_quaternion()
	var target_rotation := target_basis.get_rotation_quaternion()
	var angle := current_rotation.angle_to(target_rotation)
	var response := minf(1.0 - exp(-dt / 0.12), deg_to_rad(55.0) * dt / maxf(angle, 0.0001))
	holder.global_transform = Transform3D(Basis(current_rotation.slerp(target_rotation, response)), world_position)
	holder.set_meta("flight_position", world_position)
	holder.set_meta("flight_velocity", velocity)
	holder.set_meta("flight_acceleration", acceleration)
	holder.set_meta("flight_yaw", yaw)


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
	var cabin_light := info.get("cabin_light") as OmniLight3D
	if cabin_light != null and is_instance_valid(cabin_light):
		var seated := (
			not _menu_preview_mode
			and not bool(info.get("hanging", false))
			and not bool(info.get("jumped", false))
		)
		cabin_light.light_energy = CABIN_LIGHT_ENERGY * (1.0 if seated else eased)
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
	return center - down * 0.08


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
		var downwash := info.get("downwash") as GPUParticles3D
		var rope_ladder := info.get("rope_ladder") as PhysicalRopeLadder
		if rope_ladder != null and is_instance_valid(rope_ladder):
			rope_ladder.queue_free()
		var pickup_vfx: Dictionary = info.get("pickup_vfx", {})
		var pickup_particles := pickup_vfx.get("particles") as GPUParticles3D
		var pickup_beam := pickup_vfx.get("beam") as MeshInstance3D
		var pickup_ring := pickup_vfx.get("ring") as MeshInstance3D
		if pickup_particles != null and is_instance_valid(pickup_particles):
			pickup_particles.emitting = false
			pickup_particles.queue_free()
		if pickup_beam != null and is_instance_valid(pickup_beam):
			pickup_beam.queue_free()
		if pickup_ring != null and is_instance_valid(pickup_ring):
			pickup_ring.queue_free()
		if downwash != null and is_instance_valid(downwash):
			downwash.emitting = false
			if immediate:
				downwash.queue_free()
			else:
				get_tree().create_timer(1.1).timeout.connect(downwash.queue_free)
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
	if _menu_flight_profile != null and is_instance_valid(_menu_flight_profile):
		_menu_flight_profile.queue_free()
	_menu_flight_profile = null


func _collect_helicopter_visual_points(holder: Node3D, model: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if holder == null or model == null:
		return points
	var holder_inverse := holder.global_transform.affine_inverse()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.get_aabb()
		var mesh_to_holder := holder_inverse * mesh_instance.global_transform
		for corner_index: int in range(8):
			var corner := bounds.position + Vector3(
				bounds.size.x if (corner_index & 1) != 0 else 0.0,
				bounds.size.y if (corner_index & 2) != 0 else 0.0,
				bounds.size.z if (corner_index & 4) != 0 else 0.0
			)
			points.append(mesh_to_holder * corner)
	if points.is_empty():
		var fallback := AABB(Vector3(-3.2, -1.7, -4.2), Vector3(6.4, 3.4, 8.4))
		for corner_index: int in range(8):
			points.append(fallback.position + Vector3(
				fallback.size.x if (corner_index & 1) != 0 else 0.0,
				fallback.size.y if (corner_index & 2) != 0 else 0.0,
				fallback.size.z if (corner_index & 4) != 0 else 0.0
			))
	return points


func _helicopter_screen_bounds(info: Dictionary) -> Dictionary:
	var camera := _menu_camera if _menu_preview_mode else get_viewport().get_camera_3d()
	if camera == null or camera.get_viewport() == null:
		return {}
	var holder := info.get("holder") as Node3D
	var points: Array = info.get("visual_points", [])
	if holder == null or points.is_empty():
		return {}
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var front_points := 0
	for local_point_variant: Variant in points:
		var local_point: Vector3 = local_point_variant
		var world_point := holder.global_transform * local_point
		if camera.is_position_behind(world_point):
			continue
		var normalized := camera.unproject_position(world_point) / viewport_size
		minimum.x = minf(minimum.x, normalized.x)
		minimum.y = minf(minimum.y, normalized.y)
		maximum.x = maxf(maximum.x, normalized.x)
		maximum.y = maxf(maximum.y, normalized.y)
		front_points += 1
	if front_points == 0:
		return {
			"min": Vector2(2.0, 2.0),
			"max": Vector2(2.0, 2.0),
			"front_points": 0,
		}
	return {
		"min": minimum,
		"max": maximum,
		"front_points": front_points,
	}


func _screen_bounds_fully_outside(bounds: Dictionary, margin: float) -> bool:
	if bounds.is_empty():
		return false
	var minimum: Vector2 = bounds.get("min", Vector2.ZERO)
	var maximum: Vector2 = bounds.get("max", Vector2.ZERO)
	return (
		maximum.x < -margin
		or minimum.x > 1.0 + margin
		or maximum.y < -margin
		or minimum.y > 1.0 + margin
	)


func _screen_bounds_intersects_frame(bounds: Dictionary) -> bool:
	if bounds.is_empty() or int(bounds.get("front_points", 0)) <= 0:
		return false
	var minimum: Vector2 = bounds.get("min", Vector2.ZERO)
	var maximum: Vector2 = bounds.get("max", Vector2.ZERO)
	return maximum.x >= 0.0 and minimum.x <= 1.0 and maximum.y >= 0.0 and minimum.y <= 1.0


func _update_menu_screen_evidence(info: Dictionary) -> void:
	if not _menu_preview_mode:
		return
	var bounds := _helicopter_screen_bounds(info)
	info["last_screen_bounds"] = bounds
	if _screen_bounds_intersects_frame(bounds):
		info["ever_visible_in_frame"] = true


func _all_menu_helicopters_fully_offscreen() -> bool:
	if _helicopters.is_empty():
		return false
	for info: Dictionary in _helicopters:
		var bounds := _helicopter_screen_bounds(info)
		info["last_screen_bounds"] = bounds
		if not bool(info.get("ever_visible_in_frame", false)):
			return false
		if not _screen_bounds_fully_outside(bounds, MENU_OFFSCREEN_MARGIN_RATIO):
			return false
	return true


func _cubic_bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	var inverse := 1.0 - clamped_t
	return (
		a * inverse * inverse * inverse
		+ b * 3.0 * inverse * inverse * clamped_t
		+ c * 3.0 * inverse * clamped_t * clamped_t
		+ d * clamped_t * clamped_t * clamped_t
	)


func _cubic_bezier_tangent(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	t: float
) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	var inverse := 1.0 - clamped_t
	var tangent := (
		(b - a) * 3.0 * inverse * inverse
		+ (c - b) * 6.0 * inverse * clamped_t
		+ (d - c) * 3.0 * clamped_t * clamped_t
	)
	if tangent.length_squared() <= 0.0001:
		tangent = d - a
	return tangent.normalized()


func _prepare_menu_downwash(info: Dictionary, ground: Vector3, player_index: int) -> void:
	var particles := info.get("downwash") as GPUParticles3D
	if is_instance_valid(particles):
		particles.position = ground + Vector3.UP * 0.12
	else:
		info["downwash"] = _create_menu_downwash(ground, player_index)


func _create_menu_downwash(ground: Vector3, player_index: int) -> GPUParticles3D:
	if not _menu_preview_mode:
		return null
	var particles := GPUParticles3D.new()
	particles.name = "P%dMenuRotorWash" % player_index
	particles.emitting = false
	particles.one_shot = false
	particles.amount = GraphicsQuality.particle_amount(32, GameManager.graphics_quality)
	particles.lifetime = 0.90
	particles.randomness = 0.55
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-7.0, -2.0, -7.0), Vector3(14.0, 8.0, 14.0))
	particles.position = ground + Vector3.UP * 0.12

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.15, 1.0)
	process_material.spread = 90.0
	process_material.initial_velocity_min = 2.4
	process_material.initial_velocity_max = 4.8
	process_material.gravity = Vector3(0.0, 0.55, 0.0)
	process_material.damping_min = 0.8
	process_material.damping_max = 1.8
	process_material.scale_min = 0.10
	process_material.scale_max = 0.32
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1.8, 0.08, 1.8)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.72, 0.76, 0.80, 0.0))
	gradient.add_point(0.18, Color(0.72, 0.76, 0.80, 0.26))
	gradient.set_color(1, Color(0.58, 0.62, 0.68, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	process_material.color_ramp = gradient_texture
	particles.process_material = process_material
	particles.draw_pass_1 = _make_menu_dust_mesh(Vector2(0.24, 0.10))
	add_child(particles)
	return particles


func _create_menu_pickup_vfx(ground: Vector3, player_index: int) -> Dictionary:
	if not _menu_departure_mode:
		return {}
	var theme_color := PlayerController.P1_BODY if player_index == 1 else PlayerController.P2_BODY

	var beam := MeshInstance3D.new()
	beam.name = "P%dPickupLight" % player_index
	var beam_mesh := CylinderMesh.new()
	beam_mesh.height = 1.0
	beam_mesh.top_radius = 0.48
	beam_mesh.bottom_radius = 1.45
	beam_mesh.radial_segments = 24
	beam.mesh = beam_mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam_material.albedo_color = Color(theme_color.r, theme_color.g, theme_color.b, 0.0)
	beam_material.emission_enabled = true
	beam_material.emission = theme_color.lightened(0.28)
	beam_material.emission_energy_multiplier = 1.8
	beam.material_override = beam_material
	beam.visible = false
	add_child(beam)

	var ring := MeshInstance3D.new()
	ring.name = "P%dPickupGroundRing" % player_index
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.08
	ring_mesh.outer_radius = 1.34
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 10
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring_material.albedo_color = Color(theme_color.r, theme_color.g, theme_color.b, 0.0)
	ring_material.emission_enabled = true
	ring_material.emission = theme_color.lightened(0.32)
	ring_material.emission_energy_multiplier = 2.2
	ring.material_override = ring_material
	ring.position = ground + Vector3.UP * 0.055
	ring.visible = false
	add_child(ring)

	var particles := GPUParticles3D.new()
	particles.name = "P%dPickupSpiral" % player_index
	particles.emitting = false
	particles.one_shot = false
	particles.amount = GraphicsQuality.particle_amount(64, GameManager.graphics_quality)
	particles.lifetime = 0.95
	particles.randomness = 0.32
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 14.0, 8.0))
	particles.position = ground + Vector3.UP * 0.12
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 14.0
	process_material.initial_velocity_min = 4.2
	process_material.initial_velocity_max = 8.4
	process_material.gravity = Vector3(0.0, 4.0, 0.0)
	process_material.damping_min = 0.6
	process_material.damping_max = 1.4
	process_material.scale_min = 0.07
	process_material.scale_max = 0.20
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1.25, 0.08, 1.25)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(theme_color.r, theme_color.g, theme_color.b, 0.0))
	gradient.add_point(0.18, Color(theme_color.r, theme_color.g, theme_color.b, 0.85))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	process_material.color_ramp = gradient_texture
	particles.process_material = process_material
	particles.draw_pass_1 = _make_menu_dust_mesh(Vector2(0.16, 0.08))
	add_child(particles)
	return {
		"beam": beam,
		"beam_material": beam_material,
		"ring": ring,
		"ring_material": ring_material,
		"particles": particles,
		"ground": ground,
	}


func _set_menu_pickup_vfx(
	info: Dictionary,
	strength: float,
	hatch_position: Vector3
) -> void:
	var pickup_vfx: Dictionary = info.get("pickup_vfx", {})
	if pickup_vfx.is_empty():
		return
	var beam := pickup_vfx.get("beam") as MeshInstance3D
	var ring := pickup_vfx.get("ring") as MeshInstance3D
	var particles := pickup_vfx.get("particles") as GPUParticles3D
	var material := pickup_vfx.get("beam_material") as StandardMaterial3D
	var ring_material := pickup_vfx.get("ring_material") as StandardMaterial3D
	var weight := clampf(strength, 0.0, 1.0)
	if beam != null and is_instance_valid(beam):
		beam.visible = weight > 0.01
		if beam.visible:
			var ground: Vector3 = pickup_vfx.get("ground", Vector3.ZERO)
			var ground_focus := ground + Vector3.UP * 0.10
			var beam_vector := hatch_position - ground_focus
			var distance := maxf(beam_vector.length(), 0.2)
			var pulse := 0.88 + sin(_total_elapsed * 15.0) * 0.08
			beam.global_transform = Transform3D(
				_basis_align_y(beam_vector / distance),
				ground_focus + beam_vector * 0.5
			)
			beam.scale = Vector3(pulse, distance, pulse)
	if material != null:
		var color := material.albedo_color
		color.a = weight * 0.18
		material.albedo_color = color
	if ring != null and is_instance_valid(ring):
		ring.visible = weight > 0.025
		if ring.visible:
			var ring_pulse := 0.92 + weight * 0.13 + sin(_total_elapsed * 11.0) * 0.035
			ring.scale = Vector3(ring_pulse, 1.0, ring_pulse)
	if ring_material != null:
		var ring_color := ring_material.albedo_color
		ring_color.a = weight * 0.58
		ring_material.albedo_color = ring_color
	if particles != null and is_instance_valid(particles):
		particles.emitting = weight > 0.04


func _basis_align_y(direction: Vector3) -> Basis:
	var normalized := direction.normalized()
	if normalized.length_squared() <= 0.0001:
		return Basis.IDENTITY
	var cosine := clampf(Vector3.UP.dot(normalized), -1.0, 1.0)
	if cosine >= 0.9999:
		return Basis.IDENTITY
	if cosine <= -0.9999:
		return Basis(Vector3.RIGHT, PI)
	var axis := Vector3.UP.cross(normalized).normalized()
	return Basis(axis, acos(cosine))


func _set_menu_downwash(info: Dictionary, enabled: bool) -> void:
	if not _menu_preview_mode:
		return
	var particles := info.get("downwash") as GPUParticles3D
	if particles != null and is_instance_valid(particles):
		particles.emitting = enabled


func _spawn_menu_landing_dust(world_position: Vector3, player_index: int) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "P%dMenuLandingDust" % player_index
	particles.emitting = false
	particles.one_shot = true
	particles.amount = GraphicsQuality.particle_amount(46, GameManager.graphics_quality)
	particles.lifetime = 0.72
	particles.explosiveness = 0.94
	particles.randomness = 0.48
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-6.0, -2.0, -6.0), Vector3(12.0, 8.0, 12.0))
	particles.position = world_position + Vector3.UP * 0.08

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 82.0
	process_material.initial_velocity_min = 2.8
	process_material.initial_velocity_max = 6.2
	process_material.gravity = Vector3(0.0, -4.0, 0.0)
	process_material.damping_min = 0.8
	process_material.damping_max = 2.2
	process_material.scale_min = 0.10
	process_material.scale_max = 0.28
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.85, 0.08, 0.85)
	var base_color := PlayerController.P1_BODY if player_index == 1 else PlayerController.P2_BODY
	var gradient := Gradient.new()
	gradient.set_color(0, Color(base_color.r, base_color.g, base_color.b, 0.70))
	gradient.add_point(0.30, Color(0.78, 0.80, 0.84, 0.42))
	gradient.set_color(1, Color(0.60, 0.62, 0.67, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	process_material.color_ramp = gradient_texture
	particles.process_material = process_material
	particles.draw_pass_1 = _make_menu_dust_mesh(Vector2(0.18, 0.18))
	add_child(particles)
	particles.restart()
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


func _make_menu_dust_mesh(size: Vector2) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	return mesh


func _restore_menu_camera() -> void:
	if not _menu_preview_mode or _menu_camera == null or not is_instance_valid(_menu_camera):
		return
	if not _menu_camera.current:
		_menu_camera.current = true


func _update_menu_camera(delta: float) -> void:
	if not _menu_preview_mode or _menu_camera == null or not is_instance_valid(_menu_camera):
		return
	_restore_menu_camera()
	var tilt_up := (
		MENU_PICKUP_CAMERA_TILT_UP_DEG
		if _menu_departure_mode
		else MENU_CAMERA_TILT_UP_DEG
	)
	var fov_delta := (
		MENU_PICKUP_CAMERA_FOV_DELTA
		if _menu_departure_mode
		else MENU_CAMERA_WIDE_FOV_DELTA * (1.0 - _menu_camera_return_weight())
	)
	if _menu_flight_profile != null and is_instance_valid(_menu_flight_profile):
		tilt_up = _menu_flight_profile.camera_tilt_deg
		fov_delta = _menu_flight_profile.camera_fov_delta
	elif not _menu_departure_mode:
		tilt_up *= 1.0 - _menu_camera_return_weight()
	if _menu_departure_mode:
		# Leave headroom for the tail jet throughout the charge and launch.
		tilt_up += 5.0 * smoothstep(0.0, 0.8, _phase_elapsed)
		fov_delta += 3.0 * smoothstep(0.0, 0.8, _phase_elapsed)
		if _menu_boost_started:
			fov_delta += 3.0 * smoothstep(0.0, 0.40, _menu_launch_elapsed)
	_menu_camera.fov = _menu_camera_base_fov + fov_delta
	var framing_rotation := _menu_camera_base_rotation + Vector3(
		tilt_up,
		0.0,
		0.0
	)
	var pickup_drift := _menu_pickup_camera_intensity if _menu_departure_mode else 0.0
	var cinematic_position := _menu_camera_base_position + Vector3(
		sin(_total_elapsed * 2.35) * MENU_PICKUP_CAMERA_DRIFT * pickup_drift,
		cos(_total_elapsed * 1.85) * MENU_PICKUP_CAMERA_DRIFT * 0.55 * pickup_drift,
		0.0
	)
	var cinematic_rotation := framing_rotation + Vector3(
		cos(_total_elapsed * 2.05) * 0.045 * pickup_drift,
		sin(_total_elapsed * 1.70) * 0.035 * pickup_drift,
		0.0
	)
	if _menu_camera_shake_remaining <= 0.0:
		_menu_camera.position = cinematic_position
		_menu_camera.rotation_degrees = cinematic_rotation
		return
	_menu_camera_shake_remaining = maxf(0.0, _menu_camera_shake_remaining - delta)
	var strength := _menu_camera_shake_remaining / MENU_CAMERA_SHAKE_DURATION
	var phase := _total_elapsed * 58.0
	_menu_camera.position = cinematic_position + Vector3(
		sin(phase) * MENU_CAMERA_SHAKE_POSITION * strength,
		cos(phase * 1.37) * MENU_CAMERA_SHAKE_POSITION * 0.55 * strength,
		0.0
	)
	_menu_camera.rotation_degrees = cinematic_rotation + Vector3(
		cos(phase * 1.11) * MENU_CAMERA_SHAKE_ROTATION_DEG * strength,
		sin(phase * 0.93) * MENU_CAMERA_SHAKE_ROTATION_DEG * strength,
		0.0
	)


func _menu_camera_return_weight() -> float:
	if _phase != "arrival":
		return 0.0
	return smoothstep(
		0.0,
		1.0,
		clampf(
			(_phase_elapsed - MENU_CAMERA_RETURN_START) / MENU_CAMERA_RETURN_DURATION,
			0.0,
			1.0
		)
	)


func _reset_menu_camera() -> void:
	if not _menu_preview_mode or _menu_camera == null or not is_instance_valid(_menu_camera):
		return
	_menu_camera_shake_remaining = 0.0
	_menu_pickup_camera_intensity = 0.0
	_menu_camera.position = _menu_camera_base_position
	_menu_camera.rotation_degrees = _menu_camera_base_rotation
	_menu_camera.fov = _menu_camera_base_fov


func _emit_presentation_finished(success: bool) -> void:
	if _presentation_finished_emitted:
		return
	_presentation_finished_emitted = true
	presentation_finished.emit(success)


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
