extends Node3D
class_name HelicopterArrivalDirector

signal presentation_finished(success: bool)

const HELICOPTER_GLB := "res://assets/vehicles/helicopter/helicopter_drop.glb"
const MENU_FLIGHT_PROFILE_SCENE := preload("res://scenes/menu_helicopter_sequence.tscn")
const PhysicalRopeLadderScript := preload("res://scripts/world/physical_rope_ladder.gd")
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
const MENU_PICKUP_FAILSAFE_SECONDS := 8.0
const MENU_PICKUP_HOVER_HEIGHT := 10.2
const MENU_PICKUP_CAMERA_FOV_DELTA := 4.0
const MENU_PICKUP_CAMERA_TILT_UP_DEG := 5.0
const MENU_PICKUP_CAMERA_DRIFT := 0.018
const MENU_LADDER_DEPLOY_START := 1.50
const MENU_LADDER_DEPLOY_DURATION := 0.76
const MENU_LADDER_P2_DELAY := 0.18
const MENU_LADDER_GRIP_THRESHOLD := 0.92

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
var _presentation_finished_emitted := false


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
		info["ground"] = ground
		info["release"] = ground + Vector3.UP * MENU_RELEASE_HEIGHT
		info["pickup_started"] = false
		info["captured"] = false
		info["ever_visible_in_frame"] = false
		info["downwash"] = _create_menu_downwash(ground, player_index)
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
			_create_menu_rope_ladder(info)
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
		info["downwash"] = _create_menu_downwash(ground, player_index)
		var holder := info.get("holder") as Node3D
		_set_hatch_openness(info, 0.0)
		_set_flight_transform(holder, start, facing, 0.0, deg_to_rad(-3.0))
		if holder != null:
			info["last_position"] = holder.global_position
		_create_menu_rope_ladder(info)


func _create_menu_rope_ladder(info: Dictionary) -> void:
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
	add_child(ladder)
	ladder.configure(mount, player_index)
	info["rope_ladder_mount"] = mount
	info["rope_ladder"] = ladder


func _prepare_gameplay_flight_paths() -> void:
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
	):
		_complete_menu_departure()


func _complete_menu_departure() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_player_controller.complete_intro_extraction()
	_start_locked = false
	_cleanup_helicopters(false)
	set_process(false)
	_emit_presentation_finished(true)


func _update_authored_menu_departure(delta: float) -> bool:
	if _menu_flight_profile == null or not is_instance_valid(_menu_flight_profile):
		return false
	_menu_flight_profile.seek_runtime(_phase_elapsed)
	var all_captured := true
	var camera_intensity := 0.0
	var sequence_duration := maxf(_menu_flight_profile.get_runtime_duration(), 0.01)
	var sequence_progress := clampf(_phase_elapsed / sequence_duration, 0.0, 1.0)
	for info: Dictionary in _helicopters:
		var player_index := int(info.get("player_index", 1))
		var state := _menu_flight_profile.get_player_state(player_index)
		if state.is_empty():
			_fail_safe("editable rope-ladder path became unavailable")
			return true
		var holder := info.get("holder") as Node3D
		var flight_direction := _menu_level_flight_direction(
			state.get("direction", Vector3.FORWARD)
		)
		_set_flight_transform(
			holder,
			state.get("position", Vector3.ZERO),
			flight_direction,
			float(state.get("bank", 0.0)),
			float(state.get("pitch", 0.0))
		)
		var hatch_openness := float(state.get("hatch", 0.0))
		_set_hatch_openness(info, hatch_openness)
		_set_menu_downwash(
			info,
			sequence_progress >= 0.08 and sequence_progress <= 0.92
		)

		var grab_progress := clampf(
			float(state.get("action_progress", 0.0)),
			0.0,
			1.0
		)
		if not _update_menu_rope_ladder_actor(info, grab_progress, delta):
			return true
		var deploy_delay := MENU_LADDER_P2_DELAY if player_index == 2 else 0.0
		var deploy_progress := clampf(
			(_phase_elapsed - MENU_LADDER_DEPLOY_START - deploy_delay)
			/ MENU_LADDER_DEPLOY_DURATION,
			0.0,
			1.0
		)
		camera_intensity = maxf(
			camera_intensity,
			maxf(sin(deploy_progress * PI) * 0.24, sin(grab_progress * PI) * 0.34)
		)

		all_captured = all_captured and bool(info.get("captured", false))
		_update_menu_screen_evidence(info)
		_remember_helicopter_velocity(info)
	_menu_pickup_camera_intensity = lerpf(
		_menu_pickup_camera_intensity,
		camera_intensity,
		clampf(delta * 7.0, 0.0, 1.0)
	)

	if (
		all_captured
		and _menu_flight_profile.is_runtime_finished()
		# The authored endpoint is beyond the frame. The bounds check is retained
		# as early proof, while exact animation completion prevents projected rotor
		# sample points behind the camera from stalling the menu transition.
		and (
			_all_menu_helicopters_fully_offscreen()
			or sequence_progress >= 0.999
		)
	):
		_complete_menu_departure()
	return true


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
	ladder.set_deploy_progress(deploy_progress)
	if grab_progress > 0.0 and ladder.is_fully_deployed():
		if not bool(info.get("pickup_started", false)):
			if not _player_controller.begin_intro_ladder_grab(player_index):
				_fail_safe("ladder grab animation could not start")
				return false
			info["pickup_started"] = true
		if not _player_controller.update_intro_ladder_grab(
			player_index,
			ladder.get_grip_data(),
			grab_progress,
			delta
		):
			_fail_safe("character could not stay attached to the physical rung")
			return false
		if grab_progress >= MENU_LADDER_GRIP_THRESHOLD:
			ladder.set_payload_active(true)
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
		_set_flight_transform(
			holder,
			flight_position,
			state.get("direction", Vector3.FORWARD),
			float(state.get("bank", 0.0)),
			float(state.get("pitch", 0.0))
		)
		_set_hatch_openness(info, float(state.get("hatch", 0.0)))
		var ground: Vector3 = info.get("ground", Vector3.ZERO)
		_set_menu_downwash(
			info,
			flight_position.y - ground.y < 13.5
			and not _menu_flight_profile.is_runtime_finished()
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
	_player_controller.complete_intro_drops(_game_state)
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

	var audio := AudioStreamPlayer3D.new()
	audio.name = "RotorLoop"
	audio.bus = "SFX"
	audio.stream = _rotor_stream
	audio.volume_db = -18.0
	audio.pitch_scale = 0.96 if player_index == 1 else 1.04
	audio.max_distance = 48.0
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	holder.add_child(audio)
	var visual_points := _collect_helicopter_visual_points(holder, model)
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
	if _menu_camera == null or _menu_camera.get_viewport() == null:
		return {}
	var holder := info.get("holder") as Node3D
	var points: Array = info.get("visual_points", [])
	if holder == null or points.is_empty():
		return {}
	var viewport_size := _menu_camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var front_points := 0
	for local_point_variant: Variant in points:
		var local_point: Vector3 = local_point_variant
		var world_point := holder.global_transform * local_point
		if _menu_camera.is_position_behind(world_point):
			continue
		var normalized := _menu_camera.unproject_position(world_point) / viewport_size
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
