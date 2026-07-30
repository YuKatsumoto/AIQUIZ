class_name GhostSharkRideController
extends Node3D

enum Phase {
	INACTIVE,
	DEATH_DELAY,
	ENTERING,
	AIMING,
	WINDUP,
	CHARGING,
	COOLDOWN,
}

const DEATH_DELAY_SECONDS: float = 4.0
const ENTRY_SECONDS: float = 1.2
const AIM_SPEED: float = 9.0
const WINDUP_SECONDS: float = 0.34
const CHARGE_BUILD_SECONDS: float = 1.15
const QUICK_CHARGE_FLOOR: float = 0.24
const PERFECT_CHARGE_MIN: float = 0.72
const PERFECT_CHARGE_MAX: float = 0.94
const MIN_CHARGE_SPEED: float = 31.0
const MAX_CHARGE_SPEED: float = 49.0
const MIN_CHARGE_DISTANCE: float = 46.0
const MAX_CHARGE_DISTANCE: float = 66.0
const MISS_COOLDOWN_SECONDS: float = 4.2
const HIT_COOLDOWN_SECONDS: float = 3.45
const MIN_COOLDOWN_SECONDS: float = 2.15
const PERFECT_COOLDOWN_BONUS: float = 0.45
const COMBO_COOLDOWN_STEP: float = 0.22
const MIN_HIT_HORIZONTAL_SPEED: float = 10.5
const MAX_HIT_HORIZONTAL_SPEED: float = 18.5
const MIN_HIT_VERTICAL_SPEED: float = 4.5
const MAX_HIT_VERTICAL_SPEED: float = 7.2
const MIN_HIT_CONTROL_LOCK: float = 0.25
const MAX_HIT_CONTROL_LOCK: float = 0.48
const AIM_SIDE_LIMIT: float = 8.0
const AIM_BACK_LIMIT: float = 8.0
const AIM_FORWARD_LIMIT: float = 12.0
const CAMERA_EDGE_MARGIN: float = 0.12
const HOVER_OUTSIDE_STAGE_OFFSET: float = 2.2
const ENTRY_SIDE_DISTANCE: float = 8.5
const ENTRY_DEPTH_BELOW_SURFACE: float = 3.2
const ENTRY_BACK_DISTANCE: float = 6.5

var game_state: QuizGameState = null
var stage_environment: StageEnvironment = null
var player_controller: PlayerController = null
var camera_controller: Node3D = null
var particle_spawner: Node3D = null

var phase: int = Phase.INACTIVE
var dead_player_index: int = 0
var survivor_player_index: int = 0
var _phase_timer: float = 0.0
var _aim_offset: Vector2 = Vector2.ZERO
var _locked_direction: Vector3 = Vector3.ZERO
var _shark: SharkSwimmer = null
var _preferred_ocean_sharks: Dictionary = {}
var _previous_p1_alive: bool = true
var _previous_p2_alive: bool = true
var _previous_fire_down: bool = false
var _death_position: Vector3 = Vector3.ZERO
var _sweep_previous_position: Vector3 = Vector3.ZERO
var _hit_this_charge: bool = false
var _charge_finished_pending: bool = false
var _cooldown_entry_started: bool = false
var _charging_input: bool = false
var _charge_amount: float = 0.0
var _last_charge_power: float = QUICK_CHARGE_FLOOR
var _perfect_charge: bool = false
var _combo: int = 0
var _best_combo: int = 0
var _current_cooldown_duration: float = MISS_COOLDOWN_SECONDS
var _result_text: String = ""
var _player_color: Color = Color.WHITE

var _aim_line: MeshInstance3D = null
var _aim_ring: MeshInstance3D = null
var _aim_outer_ring: MeshInstance3D = null
var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _hud_panel_style: StyleBoxFlat = null
var _hud_title: Label = null
var _hud_help: Label = null
var _hud_label: Label = null
var _hud_combo: Label = null
var _charge_bar: ProgressBar = null
var _charge_fill_style: StyleBoxFlat = null
var _aim_material: StandardMaterial3D = null
var _aim_outer_material: StandardMaterial3D = null


func setup(
	state: QuizGameState,
	environment: StageEnvironment,
	visual_controller: PlayerController,
	main_camera_controller: Node3D,
	effects: Node3D
) -> void:
	game_state = state
	stage_environment = environment
	player_controller = visual_controller
	camera_controller = main_camera_controller
	particle_spawner = effects
	_previous_p1_alive = game_state.p1_alive
	_previous_p2_alive = game_state.p2_alive
	_build_aim_visuals()


func remember_ocean_death_shark(player_index: int, shark: SharkSwimmer) -> void:
	if shark and is_instance_valid(shark):
		_preferred_ocean_sharks[player_index] = shark


func update_ghost_ride(
	delta: float,
	axis_p1: Vector2,
	axis_p2: Vector2,
	jump_p1: bool,
	jump_p2: bool,
	is_online: bool,
	is_replay: bool
) -> void:
	if game_state == null:
		return
	var fire_down := jump_p1 if dead_player_index == 1 else jump_p2
	var fire_pressed := fire_down and not _previous_fire_down
	var fire_released := not fire_down and _previous_fire_down

	if phase == Phase.INACTIVE:
		_detect_new_death(is_online, is_replay)
	else:
		if not _can_continue(is_online, is_replay):
			_cleanup_ghost_ride()
		else:
			_update_active_phase(
				delta,
				axis_p1,
				axis_p2,
				fire_down,
				fire_pressed,
				fire_released
			)

	_previous_fire_down = fire_down
	_previous_p1_alive = game_state.p1_alive
	_previous_p2_alive = game_state.p2_alive


func force_cleanup() -> void:
	_cleanup_ghost_ride()
	if game_state:
		_previous_p1_alive = game_state.p1_alive
		_previous_p2_alive = game_state.p2_alive


func get_debug_state() -> Dictionary:
	return {
		"phase": Phase.keys()[phase],
		"dead_player": dead_player_index,
		"survivor": survivor_player_index,
		"aim_offset": _aim_offset,
		"locked_direction": _locked_direction,
		"hit_this_charge": _hit_this_charge,
		"charging_input": _charging_input,
		"charge_power": _charge_amount if phase == Phase.AIMING else _last_charge_power,
		"perfect_charge": _perfect_charge,
		"combo": _combo,
		"best_combo": _best_combo,
		"cooldown_duration": _current_cooldown_duration,
		"phase_timer": _phase_timer,
		"hover_target": _calculate_hover_target() if survivor_player_index > 0 else Vector3.ZERO,
		"aim_point": _current_aim_point() if survivor_player_index > 0 else Vector3.ZERO,
		"shark_position": _shark.global_position if _shark and is_instance_valid(_shark) else Vector3.ZERO,
	}


func _detect_new_death(is_online: bool, is_replay: bool) -> void:
	if not _base_mode_is_eligible(is_online, is_replay):
		return
	if not game_state.p1_alive and not game_state.p2_alive:
		return
	if _previous_p1_alive and not game_state.p1_alive and game_state.p2_alive:
		_begin_death_delay(1, 2)
	elif _previous_p2_alive and not game_state.p2_alive and game_state.p1_alive:
		_begin_death_delay(2, 1)


func _begin_death_delay(dead_index: int, survivor_index: int) -> void:
	dead_player_index = dead_index
	survivor_player_index = survivor_index
	phase = Phase.DEATH_DELAY
	_phase_timer = DEATH_DELAY_SECONDS
	_previous_fire_down = false
	_death_position = _player_position(dead_player_index)
	_aim_offset = Vector2.ZERO
	_charging_input = false
	_charge_amount = 0.0
	_combo = 0
	_best_combo = 0
	_apply_player_aim_color()
	_hide_aim_visuals()
	_update_hud("幽霊サメ召喚まで %.1f 秒" % _phase_timer)


func _base_mode_is_eligible(is_online: bool, is_replay: bool) -> bool:
	return (
		game_state.num_players == 2
		and not game_state.is_coop_mode()
		and game_state.mode != Constants.MODE_TUTORIAL
		and not is_online
		and not is_replay
	)


func _can_continue(is_online: bool, is_replay: bool) -> bool:
	if not _base_mode_is_eligible(is_online, is_replay):
		return false
	if game_state.game_state not in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_GOAL_RACE]:
		return false
	if not _is_player_alive(survivor_player_index):
		return false
	if game_state.is_player_waiting_for_shark(survivor_player_index):
		return false
	return not (not game_state.p1_alive and not game_state.p2_alive)


func _update_active_phase(
	delta: float,
	axis_p1: Vector2,
	axis_p2: Vector2,
	fire_down: bool,
	fire_pressed: bool,
	fire_released: bool
) -> void:
	match phase:
		Phase.DEATH_DELAY:
			_phase_timer -= delta
			_set_meter(1.0 - clampf(_phase_timer / DEATH_DELAY_SECONDS, 0.0, 1.0), _player_color)
			_update_hud("幽霊サメ召喚まで %.1f 秒" % maxf(0.0, _phase_timer))
			if _phase_timer <= 0.0:
				_start_ghost_ride()
		Phase.ENTERING:
			_update_hover_target()
			_phase_timer -= delta
			_set_meter(1.0 - clampf(_phase_timer / ENTRY_SECONDS, 0.0, 1.0), _player_color)
			_update_hud("海から接近中…")
			if _phase_timer <= 0.0 and _shark and _shark.is_ghost_hovering():
				phase = Phase.AIMING
				_show_aim_visuals()
		Phase.AIMING:
			var aim_axis := axis_p1 if dead_player_index == 1 else axis_p2
			_aim_offset.x = clampf(_aim_offset.x + aim_axis.x * AIM_SPEED * delta, -AIM_SIDE_LIMIT, AIM_SIDE_LIMIT)
			_aim_offset.y = clampf(_aim_offset.y + aim_axis.y * AIM_SPEED * delta, -AIM_BACK_LIMIT, AIM_FORWARD_LIMIT)
			_update_hover_target()
			_update_charge_input(delta, fire_down, fire_pressed, fire_released)
			_update_aim_visuals(false)
		Phase.WINDUP:
			_phase_timer -= delta
			_update_aim_visuals(true)
			_set_meter(_last_charge_power, _charge_feedback_color(_last_charge_power))
			if _phase_timer <= 0.0:
				_start_charge()
		Phase.CHARGING:
			_update_charge_sweep()
			if _charge_finished_pending:
				_begin_cooldown()
		Phase.COOLDOWN:
			_update_cooldown(delta)


func _update_charge_input(
	delta: float,
	fire_down: bool,
	fire_pressed: bool,
	fire_released: bool
) -> void:
	if fire_pressed:
		_charging_input = true
		_charge_amount = 0.0
	if not _charging_input:
		_set_meter(0.0, _player_color)
		_update_hud("照準を合わせ、突進ボタンを長押し")
		return
	if fire_down:
		_charge_amount = minf(1.0, _charge_amount + delta / CHARGE_BUILD_SECONDS)
		if _shark and _shark.has_method("set_ghost_charge_tension"):
			_shark.set_ghost_charge_tension(_charge_amount)
		_set_meter(_charge_amount, _charge_feedback_color(_charge_amount))
		if _is_perfect_power(_charge_amount):
			_update_hud("PERFECT 帯！ 今離すと強力")
		elif _charge_amount >= PERFECT_CHARGE_MAX:
			_update_hud("OVERCHARGE！ 自動発射")
		else:
			_update_hud("霊力チャージ %d%%" % roundi(_charge_amount * 100.0))
		if _charge_amount >= 1.0:
			_commit_charge()
	elif fire_released:
		_commit_charge()


func _commit_charge() -> void:
	if phase != Phase.AIMING or not _charging_input or _shark == null:
		return
	_last_charge_power = maxf(QUICK_CHARGE_FLOOR, _charge_amount)
	_perfect_charge = _is_perfect_power(_last_charge_power)
	var aim_point := _current_aim_point()
	_locked_direction = _shark.global_position.direction_to(aim_point)
	_charging_input = false
	if _locked_direction.length_squared() <= 0.001:
		_charge_amount = 0.0
		return
	phase = Phase.WINDUP
	_phase_timer = WINDUP_SECONDS
	_update_hud("PERFECT CHARGE！" if _perfect_charge else "突進方向ロック")


func _is_perfect_power(power: float) -> bool:
	return power >= PERFECT_CHARGE_MIN and power <= PERFECT_CHARGE_MAX


func _charge_feedback_color(power: float) -> Color:
	if power > PERFECT_CHARGE_MAX:
		return Color(1.0, 0.25, 0.34, 1.0)
	if power >= PERFECT_CHARGE_MIN:
		return Color(1.0, 0.86, 0.22, 1.0)
	return _player_color.lerp(Color.WHITE, clampf(power * 0.35, 0.0, 0.35))


func _start_ghost_ride() -> void:
	_shark = _acquire_shark()
	if _shark == null:
		_cleanup_ghost_ride()
		return
	var rider := player_controller.create_ghost_rider_visual(dead_player_index)
	var hover_target := _calculate_hover_target()
	var aim_point := _current_aim_point()
	if not _shark.begin_ghost_ride(dead_player_index, rider):
		rider.queue_free()
		_shark = null
		_cleanup_ghost_ride()
		return
	if not _shark.ghost_charge_finished.is_connected(_on_shark_charge_finished):
		_shark.ghost_charge_finished.connect(_on_shark_charge_finished)
	if camera_controller and camera_controller.has_method("set_ghost_ride_wide_fov"):
		camera_controller.set_ghost_ride_wide_fov(true)
	_shark.restart_ghost_hover(
		_calculate_entry_position(hover_target),
		hover_target,
		aim_point
	)
	phase = Phase.ENTERING
	_phase_timer = ENTRY_SECONDS
	_update_hud("海から接近中…")


func _acquire_shark() -> SharkSwimmer:
	var preferred_variant: Variant = _preferred_ocean_sharks.get(dead_player_index)
	var preferred := preferred_variant as SharkSwimmer
	if preferred and is_instance_valid(preferred) and preferred.is_available_for_ocean_attack():
		_preferred_ocean_sharks.erase(dead_player_index)
		return preferred
	if stage_environment == null:
		return null
	var selected: SharkSwimmer = null
	var best_distance := INF
	for candidate: SharkSwimmer in stage_environment.get_ocean_sharks():
		if not candidate.is_available_for_ocean_attack():
			continue
		var candidate_distance := candidate.global_position.distance_squared_to(_death_position)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			selected = candidate
	return selected


func _update_hover_target() -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	_shark.set_ghost_hover_target(_calculate_hover_target(), _current_aim_point())


func _calculate_hover_target() -> Vector3:
	var survivor_position := _player_position(survivor_player_index)
	var side := signf(_death_position.x - survivor_position.x)
	if is_zero_approx(side):
		side = 1.0 if dead_player_index == 1 else -1.0
	var desired := Vector3(
		side * (StageConstants.FLOOR_HALF_WIDTH + HOVER_OUTSIDE_STAGE_OFFSET),
		StageConstants.FLOOR_TOP_Y + 3.8,
		survivor_position.z + 6.0
	)
	return _keep_inside_camera(desired, survivor_position + Vector3.UP * 2.2, side)


func _calculate_entry_position(hover_target: Vector3) -> Vector3:
	var survivor_position := _player_position(survivor_player_index)
	var side := signf(hover_target.x - survivor_position.x)
	if is_zero_approx(side):
		side = 1.0 if dead_player_index == 1 else -1.0
	return Vector3(
		hover_target.x + side * ENTRY_SIDE_DISTANCE,
		StageConstants.OCEAN_SURFACE_Y - ENTRY_DEPTH_BELOW_SURFACE,
		hover_target.z - ENTRY_BACK_DISTANCE
	)


func _keep_inside_camera(desired: Vector3, survivor_focus: Vector3, outside_side: float) -> Vector3:
	if camera_controller == null:
		return desired
	var camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
	if camera == null or camera.get_viewport() == null:
		return desired
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return desired
	var margin := viewport_size * CAMERA_EDGE_MARGIN
	var outside_x := outside_side * (
		StageConstants.FLOOR_HALF_WIDTH + HOVER_OUTSIDE_STAGE_OFFSET
	)
	for _attempt in range(10):
		if not camera.is_position_behind(desired):
			var screen_position := camera.unproject_position(desired)
			if (
				screen_position.x >= margin.x
				and screen_position.x <= viewport_size.x - margin.x
				and screen_position.y >= margin.y
				and screen_position.y <= viewport_size.y - margin.y
			):
				break
		# Keep the rider beyond the floor edge. Moving it deeper into the view
		# narrows its projected horizontal offset without pulling it onto the stage.
		desired.x = outside_x
		desired.z = maxf(desired.z + 2.0, survivor_focus.z + 6.0)
	return desired


func _current_aim_point() -> Vector3:
	var survivor_position := _player_position(survivor_player_index)
	return Vector3(
		survivor_position.x + _aim_offset.x,
		survivor_position.y + 0.85,
		survivor_position.z + _aim_offset.y
	)


func _start_charge() -> void:
	var charge_speed := lerpf(MIN_CHARGE_SPEED, MAX_CHARGE_SPEED, _last_charge_power)
	var charge_distance := lerpf(MIN_CHARGE_DISTANCE, MAX_CHARGE_DISTANCE, _last_charge_power)
	if _perfect_charge:
		charge_speed += 3.0
	if _shark == null or not _shark.launch_ghost_charge(_locked_direction, charge_speed, charge_distance):
		_cleanup_ghost_ride()
		return
	phase = Phase.CHARGING
	_sweep_previous_position = _shark.global_position
	_hit_this_charge = false
	_charge_finished_pending = false
	_hide_aim_visuals()
	_set_meter(_last_charge_power, _charge_feedback_color(_last_charge_power))
	_update_hud("PERFECT DASH！" if _perfect_charge else "直線突進中！")


func _update_charge_sweep() -> void:
	if _shark == null or not is_instance_valid(_shark):
		_cleanup_ghost_ride()
		return
	var current_position := _shark.global_position
	if not _hit_this_charge and _segment_hits_survivor(_sweep_previous_position, current_position):
		_apply_charge_hit()
	_sweep_previous_position = current_position


func _segment_hits_survivor(from_position: Vector3, to_position: Vector3) -> bool:
	var target := _player_position(survivor_player_index) + Vector3.UP * 0.85
	var segment := to_position - from_position
	var closest := from_position
	if segment.length_squared() > 0.0001:
		var weight := clampf((target - from_position).dot(segment) / segment.length_squared(), 0.0, 1.0)
		closest = from_position + segment * weight
	var horizontal_distance := Vector2(target.x - closest.x, target.z - closest.z).length()
	return horizontal_distance <= 1.45 and absf(target.y - closest.y) <= 1.35


func _apply_charge_hit() -> void:
	_hit_this_charge = true
	_combo += 1
	_best_combo = maxi(_best_combo, _combo)
	var horizontal_direction := Vector2(_locked_direction.x, _locked_direction.z).normalized()
	if horizontal_direction.length_squared() < 0.001:
		horizontal_direction = Vector2.RIGHT
	var horizontal_speed := lerpf(
		MIN_HIT_HORIZONTAL_SPEED,
		MAX_HIT_HORIZONTAL_SPEED,
		_last_charge_power
	)
	var vertical_speed := lerpf(
		MIN_HIT_VERTICAL_SPEED,
		MAX_HIT_VERTICAL_SPEED,
		_last_charge_power
	)
	var control_lock := lerpf(
		MIN_HIT_CONTROL_LOCK,
		MAX_HIT_CONTROL_LOCK,
		_last_charge_power
	)
	if _perfect_charge:
		horizontal_speed += 1.8
		vertical_speed += 0.6
	_result_text = (
		"PERFECT HIT！ HAUNT x%d" % _combo
		if _perfect_charge
		else "HIT！ HAUNT x%d" % _combo
	)
	game_state.apply_external_impulse(
		survivor_player_index,
		horizontal_direction * horizontal_speed,
		vertical_speed,
		control_lock
	)
	var survivor_position := _player_position(survivor_player_index) + Vector3.UP * 0.85
	if particle_spawner and particle_spawner.has_method("spawn_shark_impact"):
		particle_spawner.spawn_shark_impact(survivor_position, _locked_direction)
	if camera_controller and camera_controller.has_method("trigger_ocean_attack_impact"):
		camera_controller.trigger_ocean_attack_impact()
	if _shark:
		_shark.play_ghost_impact()


func _on_shark_charge_finished() -> void:
	_charge_finished_pending = true


func _begin_cooldown() -> void:
	phase = Phase.COOLDOWN
	if _hit_this_charge:
		_current_cooldown_duration = HIT_COOLDOWN_SECONDS
		_current_cooldown_duration -= minf(4.0, float(_combo - 1)) * COMBO_COOLDOWN_STEP
		if _perfect_charge:
			_current_cooldown_duration -= PERFECT_COOLDOWN_BONUS
		_current_cooldown_duration = maxf(MIN_COOLDOWN_SECONDS, _current_cooldown_duration)
	else:
		_combo = 0
		_result_text = "MISS… HAUNT COMBO RESET"
		_current_cooldown_duration = MISS_COOLDOWN_SECONDS
	_phase_timer = _current_cooldown_duration
	_cooldown_entry_started = false
	_charge_finished_pending = false
	_charging_input = false
	_charge_amount = 0.0
	if _shark and _shark.has_method("set_ghost_charge_tension"):
		_shark.set_ghost_charge_tension(0.0)
	if _shark:
		_shark.visible = false
	_set_meter(0.0, _player_color)
	_update_hud("%s  /  再突進 %.1f 秒" % [_result_text, _phase_timer])


func _update_cooldown(delta: float) -> void:
	_phase_timer = maxf(0.0, _phase_timer - delta)
	if not _cooldown_entry_started and _phase_timer <= ENTRY_SECONDS:
		_cooldown_entry_started = true
		var hover_target := _calculate_hover_target()
		var entry_position := _calculate_entry_position(hover_target)
		_shark.restart_ghost_hover(entry_position, hover_target, _current_aim_point())
	if _cooldown_entry_started:
		_update_hover_target()
	var cooldown_progress := 1.0 - clampf(
		_phase_timer / maxf(0.001, _current_cooldown_duration),
		0.0,
		1.0
	)
	_set_meter(cooldown_progress, _player_color)
	_update_hud("%s  /  再突進 %.1f 秒" % [_result_text, _phase_timer])
	if _phase_timer <= 0.0 and _shark and _shark.is_ghost_hovering():
		phase = Phase.AIMING
		_show_aim_visuals()


func _player_position(player_index: int) -> Vector3:
	if player_index == 1:
		return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)
	return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)


func _is_player_alive(player_index: int) -> bool:
	return game_state.p1_alive if player_index == 1 else game_state.p2_alive


func _build_aim_visuals() -> void:
	_aim_material = StandardMaterial3D.new()
	_aim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_material.emission_enabled = true

	_aim_line = MeshInstance3D.new()
	_aim_line.name = "GhostAimLine"
	var line_mesh := CylinderMesh.new()
	line_mesh.height = 1.0
	line_mesh.top_radius = 0.045
	line_mesh.bottom_radius = 0.075
	line_mesh.radial_segments = 8
	_aim_line.mesh = line_mesh
	_aim_line.material_override = _aim_material
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_line)

	_aim_ring = MeshInstance3D.new()
	_aim_ring.name = "GhostAimRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.78
	ring_mesh.outer_radius = 1.05
	_aim_ring.mesh = ring_mesh
	_aim_ring.material_override = _aim_material
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_ring)

	_aim_outer_material = StandardMaterial3D.new()
	_aim_outer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_outer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_outer_material.emission_enabled = true
	_aim_outer_ring = MeshInstance3D.new()
	_aim_outer_ring.name = "GhostAimOuterRing"
	var outer_ring_mesh := TorusMesh.new()
	outer_ring_mesh.inner_radius = 1.16
	outer_ring_mesh.outer_radius = 1.28
	_aim_outer_ring.mesh = outer_ring_mesh
	_aim_outer_ring.material_override = _aim_outer_material
	_aim_outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_outer_ring)

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GhostRideHUD"
	_hud_layer.layer = 12
	add_child(_hud_layer)

	_hud_panel = PanelContainer.new()
	_hud_panel.name = "GhostRidePanel"
	_hud_panel.custom_minimum_size = Vector2(456.0, 142.0)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel_style = StyleBoxFlat.new()
	_hud_panel_style.bg_color = Color(0.012, 0.025, 0.065, 0.90)
	_hud_panel_style.border_width_left = 4
	_hud_panel_style.border_width_top = 1
	_hud_panel_style.border_width_right = 1
	_hud_panel_style.border_width_bottom = 1
	_hud_panel_style.corner_radius_top_left = 10
	_hud_panel_style.corner_radius_top_right = 10
	_hud_panel_style.corner_radius_bottom_left = 10
	_hud_panel_style.corner_radius_bottom_right = 10
	_hud_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	_hud_panel_style.shadow_size = 8
	_hud_panel.add_theme_stylebox_override("panel", _hud_panel_style)
	_hud_layer.add_child(_hud_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 11)
	_hud_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	_hud_title = Label.new()
	_hud_title.name = "GhostRideTitle"
	_hud_title.add_theme_font_size_override("font_size", 18)
	title_row.add_child(_hud_title)
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	_hud_combo = Label.new()
	_hud_combo.name = "GhostRideCombo"
	_hud_combo.add_theme_font_size_override("font_size", 18)
	_hud_combo.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22, 1.0))
	title_row.add_child(_hud_combo)
	_hud_help = Label.new()
	_hud_help.name = "GhostRideControls"
	_hud_help.add_theme_font_size_override("font_size", 15)
	_hud_help.add_theme_color_override("font_color", Color(0.76, 0.83, 0.93, 1.0))
	vbox.add_child(_hud_help)
	_hud_label = Label.new()
	_hud_label.name = "GhostRideInstructions"
	_hud_label.add_theme_font_size_override("font_size", 19)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	_hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_hud_label.add_theme_constant_override("shadow_offset_x", 2)
	_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hud_label)
	_charge_bar = ProgressBar.new()
	_charge_bar.name = "GhostChargeMeter"
	_charge_bar.custom_minimum_size = Vector2(0.0, 13.0)
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 100.0
	_charge_bar.show_percentage = false
	var charge_background := StyleBoxFlat.new()
	charge_background.bg_color = Color(0.02, 0.04, 0.09, 0.92)
	charge_background.corner_radius_top_left = 6
	charge_background.corner_radius_top_right = 6
	charge_background.corner_radius_bottom_left = 6
	charge_background.corner_radius_bottom_right = 6
	_charge_bar.add_theme_stylebox_override("background", charge_background)
	_charge_fill_style = StyleBoxFlat.new()
	_charge_fill_style.bg_color = Color.WHITE
	_charge_fill_style.corner_radius_top_left = 6
	_charge_fill_style.corner_radius_top_right = 6
	_charge_fill_style.corner_radius_bottom_left = 6
	_charge_fill_style.corner_radius_bottom_right = 6
	_charge_bar.add_theme_stylebox_override("fill", _charge_fill_style)
	vbox.add_child(_charge_bar)
	_hide_aim_visuals()
	_hud_label.visible = false
	_hud_panel.visible = false


func _show_aim_visuals() -> void:
	if _aim_line:
		_aim_line.visible = true
	if _aim_ring:
		_aim_ring.visible = true
	if _aim_outer_ring:
		_aim_outer_ring.visible = true
	_charging_input = false
	_charge_amount = 0.0
	_perfect_charge = false
	if _shark and _shark.has_method("set_ghost_charge_tension"):
		_shark.set_ghost_charge_tension(0.0)
	_update_aim_visuals(false)
	_set_meter(0.0, _player_color)
	_update_hud("照準を合わせ、突進ボタンを長押し")


func _hide_aim_visuals() -> void:
	if _aim_line:
		_aim_line.visible = false
	if _aim_ring:
		_aim_ring.visible = false
	if _aim_outer_ring:
		_aim_outer_ring.visible = false


func _update_aim_visuals(blink: bool) -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	var aim_point := _current_aim_point()
	var start := _shark.global_position
	var direction := aim_point - start
	var distance := direction.length()
	if distance < 0.01:
		return
	var visible_now := not blink or int(Time.get_ticks_msec() / 90.0) % 2 == 0
	var display_power := _last_charge_power if phase == Phase.WINDUP else _charge_amount
	var effect_color := _charge_feedback_color(display_power) if _charging_input or phase == Phase.WINDUP else _player_color
	_set_aim_color(effect_color)
	_aim_line.visible = visible_now
	_aim_ring.visible = visible_now
	_aim_outer_ring.visible = visible_now
	_aim_line.global_position = start + direction * 0.5
	var line_width := lerpf(0.9, 1.65, display_power)
	_aim_line.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized())) * Basis.from_scale(Vector3(line_width, distance, line_width))
	_aim_ring.global_position = Vector3(aim_point.x, StageConstants.FLOOR_TOP_Y + 0.035, aim_point.z)
	_aim_ring.rotation = Vector3.ZERO
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * (0.04 + display_power * 0.07)
	_aim_ring.scale = Vector3.ONE * (pulse + display_power * 0.18)
	_aim_outer_ring.global_position = Vector3(aim_point.x, StageConstants.FLOOR_TOP_Y + 0.05, aim_point.z)
	_aim_outer_ring.rotation = Vector3.ZERO
	_aim_outer_ring.scale = Vector3.ONE * (1.0 + display_power * 0.42 - sin(Time.get_ticks_msec() * 0.009) * 0.08)


func _update_hud(status: String) -> void:
	if _hud_label == null or _hud_panel == null:
		return
	_hud_panel.visible = true
	_hud_label.visible = true
	_hud_title.text = "GHOST RIDER · P%d" % dead_player_index
	_hud_help.text = _control_help_text()
	_hud_label.text = status
	_hud_combo.text = "HAUNT x%d" % _combo if _combo > 0 else ""
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := minf(456.0, maxf(320.0, viewport_size.x - 40.0))
	_hud_panel.position = Vector2(
		20.0 if dead_player_index == 1 else maxf(20.0, viewport_size.x - panel_width - 20.0),
		maxf(20.0, viewport_size.y - 166.0)
	)
	_hud_panel.size = Vector2(panel_width, 142.0)


func _control_help_text() -> String:
	if dead_player_index == 1:
		return "WASD  照準　|　SPACE 長押し→離して突進"
	return "矢印キー  照準　|　CTRL / NUM0 長押し→離して突進"


func _apply_player_aim_color() -> void:
	if _aim_material == null:
		return
	_player_color = Color(0.95, 0.55, 0.20, 1.0) if dead_player_index == 1 else Color(0.20, 0.65, 0.90, 1.0)
	_set_aim_color(_player_color)
	if _hud_panel_style:
		_hud_panel_style.border_color = _player_color
	if _hud_title:
		_hud_title.add_theme_color_override("font_color", _player_color)
	if _hud_label:
		_hud_label.add_theme_color_override("font_color", Color.WHITE)


func _set_aim_color(color: Color) -> void:
	if _aim_material:
		_aim_material.albedo_color = Color(color.r, color.g, color.b, 0.84)
		_aim_material.emission = Color(color.r, color.g, color.b, 1.0)
		_aim_material.emission_energy_multiplier = 2.1
	if _aim_outer_material:
		_aim_outer_material.albedo_color = Color(color.r, color.g, color.b, 0.42)
		_aim_outer_material.emission = Color(color.r, color.g, color.b, 1.0)
		_aim_outer_material.emission_energy_multiplier = 1.6


func _set_meter(progress: float, color: Color) -> void:
	if _charge_bar:
		_charge_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	if _charge_fill_style:
		_charge_fill_style.bg_color = Color(color.r, color.g, color.b, 0.96)


func _cleanup_ghost_ride() -> void:
	_hide_aim_visuals()
	if camera_controller and camera_controller.has_method("set_ghost_ride_wide_fov"):
		camera_controller.set_ghost_ride_wide_fov(false)
	if _hud_label:
		_hud_label.visible = false
	if _hud_panel:
		_hud_panel.visible = false
	if _shark and is_instance_valid(_shark):
		if _shark.ghost_charge_finished.is_connected(_on_shark_charge_finished):
			_shark.ghost_charge_finished.disconnect(_on_shark_charge_finished)
		_shark.end_ghost_ride()
	_shark = null
	phase = Phase.INACTIVE
	dead_player_index = 0
	survivor_player_index = 0
	_phase_timer = 0.0
	_aim_offset = Vector2.ZERO
	_locked_direction = Vector3.ZERO
	_hit_this_charge = false
	_charge_finished_pending = false
	_cooldown_entry_started = false
	_charging_input = false
	_charge_amount = 0.0
	_last_charge_power = QUICK_CHARGE_FLOOR
	_perfect_charge = false
	_combo = 0
	_best_combo = 0
	_current_cooldown_duration = MISS_COOLDOWN_SECONDS
	_result_text = ""
	_preferred_ocean_sharks.clear()
