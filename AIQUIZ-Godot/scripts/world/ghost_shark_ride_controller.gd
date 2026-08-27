class_name GhostSharkRideController
extends Node3D

signal aim_used(player_index: int)
signal charge_resolved(player_index: int, hit: bool, power: float)
signal result_rider_released(rider: Node3D)

const SharkSwimmerScript = preload("res://scripts/world/shark_swimmer.gd")
const GHOST_RETURN_PORTAL_P1_SCENE := preload(
	"res://assets/BinbunVFX/portal_vfx/effects/portal/portal_vfx_01.tscn"
)
const GHOST_RETURN_PORTAL_P2_SCENE := preload(
	"res://assets/BinbunVFX/portal_vfx/effects/portal/portal_vfx_04.tscn"
)

enum Phase {
	INACTIVE,
	DEATH_DELAY,
	DEATH_HOLD,
	SOUL_RISE,
	SOUL_FLIGHT,
	MOUNTING,
	BEAM_REVEAL,
	ENTERING,
	AIMING,
	WINDUP,
	CHARGING,
	COOLDOWN,
}

enum ChargeTutorialDemoPhase {
	BUILDING,
	HOLDING,
	RESETTING,
}

const DEATH_HOLD_SECONDS: float = 0.55
const DEATH_DELAY_SECONDS: float = 4.0
const SOUL_RISE_SECONDS: float = 0.85
const SOUL_FLIGHT_SECONDS: float = 2.65
const SOUL_TRAVEL_SECONDS: float = SOUL_RISE_SECONDS + SOUL_FLIGHT_SECONDS
const MOUNTING_SECONDS: float = 0.85
const POST_MOUNT_BEAM_REVEAL_SECONDS: float = 3.59
const ENTRY_SECONDS: float = 2.45
const HEROIC_SEQUENCE_SECONDS: float = (
	DEATH_HOLD_SECONDS
	+ SOUL_TRAVEL_SECONDS
	+ MOUNTING_SECONDS
	+ POST_MOUNT_BEAM_REVEAL_SECONDS
	+ ENTRY_SECONDS
)
const AIM_SPEED: float = 9.0
const WINDUP_SECONDS: float = 0.34
const CHARGE_BUILD_SECONDS: float = 0.5
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
const AIM_VISUAL_DARKEN_FACTOR: float = 0.82
const AIM_SIDE_LIMIT: float = 8.0
const AIM_BACK_LIMIT: float = 8.0
const AIM_FORWARD_LIMIT: float = 12.0
const CAMERA_EDGE_MARGIN: float = 0.12
const HOVER_OUTSIDE_STAGE_OFFSET: float = 0.9
const ENTRY_SIDE_DISTANCE: float = 8.5
const ENTRY_DEPTH_BELOW_SURFACE: float = 3.2
const ENTRY_BACK_DISTANCE: float = 6.5
const SOUL_RISE_HEIGHT: float = 1.35
const SOUL_FLIGHT_SIDE_ARC: float = 2.8
const SOUL_FLIGHT_LIFT: float = 2.55
const RENDEZVOUS_SIDE_DISTANCE: float = 3.0
const RENDEZVOUS_BACK_DISTANCE: float = 2.4
const RENDEZVOUS_REVEAL_DEPTH_OFFSET: float = 4.0
# Keep the whole shark body above the transparent ocean during mount so the
# water depth buffer cannot punch a see-through cut through the mesh.
const RENDEZVOUS_SURFACE_CLEARANCE: float = 2.35
const SOUL_PRESENTATION_RENDER_LAYER: int = 20
const GHOST_MOUNT_BEAM_RENDER_LAYER: int = 19
const GHOST_MOUNT_BEAM_LAUNCH_CAMERA_SHAKE: float = 1.15
const GHOST_MOUNT_BEAM_SUSTAINED_CAMERA_SHAKE: float = 0.82
const RETURN_PORTAL_SEQUENCE_SECONDS: float = 6.0
const RETURN_PORTAL_SHARK_REVEAL_SECONDS: float = 1.15
const RETURN_PORTAL_TAIL_CLEAR_HOLD_SECONDS: float = 0.70
const RETURN_PORTAL_ANIMATION_SPEED: float = 0.72
const RETURN_PORTAL_CLOSED_THRESHOLD: float = 0.02
const RETURN_PORTAL_TAIL_DISTANCE: float = 2.25
const RETURN_PORTAL_GRANDSTAND_OFFSET: float = 2.15
const RETURN_PORTAL_VERTICAL_OFFSET: float = 0.0
const RETURN_PORTAL_SHARK_START_DEPTH: float = 4.20
const RETURN_PORTAL_SIZE := Vector2(5.2, 5.2)
const RETURN_PORTAL_VIEW_YAW_DEGREES: float = 20.0
const RETURN_PORTAL_TUNNEL_DEPTH: float = 1.75
const RETURN_PORTAL_TUNNEL_MOUTH_RADIUS: float = 2.18
const RETURN_PORTAL_TUNNEL_BACK_RADIUS: float = 1.58
const RETURN_PORTAL_TUNNEL_RING_COUNT: int = 5
const RETURN_PORTAL_TUNNEL_FLOW_SPEED: float = 0.32
const RETURN_PORTAL_CROSSING_PROGRESS: float = 0.56
const RETURN_PORTAL_CROSSING_FLASH_SECONDS: float = 0.62
const RETURN_PORTAL_CROSSING_SHAKE: float = 0.30
const STAGE_REVEAL_PROGRESS: float = 0.46
const HUD_SLIDE_SECONDS: float = 0.55
const HUD_PANEL_WIDTH: float = 320.0
const HUD_PANEL_HEIGHT: float = 76.0
const HUD_EDGE_MARGIN: float = 20.0
const HUD_BOTTOM_MARGIN: float = 20.0
const CHARGE_TUTORIAL_PANEL_SIZE := Vector2(780.0, 470.0)
const CHARGE_TUTORIAL_BAR_HEIGHT: float = 42.0
const CHARGE_TUTORIAL_HANDOFF_SECONDS: float = 0.55
const CHARGE_TUTORIAL_DEMO_HOLD_SECONDS: float = 1.35
const CHARGE_TUTORIAL_DEMO_RESET_SECONDS: float = 0.24
const CHARGE_TUTORIAL_DEMO_WRAP_COUNT: int = 2
const CHARGE_TUTORIAL_PERFECT_BLINK_HZ: float = 5.0
const CHARGE_TUTORIAL_DEMO_TARGETS := [0.48, 0.83, 0.99, 0.75]
const CHARGE_TUTORIAL_DEMO_LABELS := [
	"早すぎる",
	"PERFECT！",
	"ためすぎ",
	"PERFECT！",
]

var game_state: QuizGameState = null
var stage_environment: StageEnvironment = null
var player_controller: PlayerController = null
var camera_controller: Node3D = null
var particle_spawner: Node3D = null

var phase: int = Phase.INACTIVE
var dead_player_index: int = 0
var survivor_player_index: int = 0
var _phase_timer: float = 0.0
var _sequence_elapsed: float = 0.0
var _ghost_rendezvous_released: bool = false
var _ghost_reveal_beams_started: bool = false
var _presentation_follow_anchor_z: float = 0.0
var _presentation_follow_initialized: bool = false
var _soul_travel_elapsed: float = 0.0
var _aim_offset: Vector2 = Vector2.ZERO
var _aim_origin: Vector3 = Vector3.ZERO
var _fixed_hover_target: Vector3 = Vector3.ZERO
var _hover_progress_offset_z: float = 0.0
var _locked_direction: Vector3 = Vector3.ZERO
var _shark: SharkSwimmerScript = null
var _preferred_ocean_sharks: Dictionary = {}
var _previous_p1_alive: bool = true
var _previous_p2_alive: bool = true
var _previous_fire_down: bool = false
var _death_position: Vector3 = Vector3.ZERO
var _soul_start_position: Vector3 = Vector3.ZERO
var _soul_rise_position: Vector3 = Vector3.ZERO
var _soul_control_a: Vector3 = Vector3.ZERO
var _soul_control_b: Vector3 = Vector3.ZERO
var _rendezvous_position: Vector3 = Vector3.ZERO
var _presentation_focus: Vector3 = Vector3.ZERO
var _rider: Node3D = null
var _rider_revealed_to_main: bool = false
var _hover_side: float = 1.0
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
var _ghost_emote_id: int = 0
var _return_portal: Node3D = null
var _return_portal_elapsed: float = 0.0
var _return_tail_clear_elapsed: float = 0.0
var _return_portal_close_started: bool = false
var _return_portal_surface_opaque: bool = false
var _return_portal_exit_direction: Vector3 = Vector3.ZERO
var _return_portal_depth_root: Node3D = null
var _return_portal_depth_rings: Array[MeshInstance3D] = []
var _return_portal_depth_light: OmniLight3D = null
var _return_portal_crossing_pulsed: bool = false
var _return_portal_crossing_flash_elapsed: float = -1.0
var _return_animation_locked: bool = false
var _result_departure_only: bool = false
var _return_locked_hover_target: Vector3 = Vector3.ZERO
var _return_locked_aim_point: Vector3 = Vector3.ZERO
var _portal_prewarm_root: Node3D = null
var _portal_prewarm_sharks: Array[SharkSwimmerScript] = []
var _portal_prewarm_instances: Dictionary = {}
var _return_portal_cache: Dictionary = {}

var _aim_ring: MeshInstance3D = null
var _aim_outer_ring: MeshInstance3D = null
var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _hud_title: Label = null
var _hud_combo: Label = null
var _hud_controls: Label = null
var _charge_bar: ProgressBar = null
var _charge_fill_style: StyleBoxFlat = null
var _hud_slide_elapsed: float = 0.0
var _hud_slide_active: bool = false
var _charge_bar_home: Control = null
var _charge_tutorial_overlay: Control = null
var _charge_tutorial_dim: ColorRect = null
var _charge_tutorial_panel: PanelContainer = null
var _charge_tutorial_title: Label = null
var _charge_tutorial_controls: Label = null
var _charge_tutorial_result: Label = null
var _charge_tutorial_bar_slot: Control = null
var _charge_tutorial_active: bool = false
var _charge_tutorial_handoff_active: bool = false
var _charge_tutorial_elapsed: float = 0.0
var _charge_tutorial_demo_phase: int = ChargeTutorialDemoPhase.BUILDING
var _charge_tutorial_demo_index: int = 0
var _charge_tutorial_demo_value: float = 0.0
var _charge_tutorial_demo_travel: float = 0.0
var _charge_tutorial_demo_phase_elapsed: float = 0.0
var _charge_tutorial_handoff_elapsed: float = 0.0
var _charge_tutorial_handoff_waiting_layout: bool = false
var _charge_tutorial_handoff_from: Rect2 = Rect2()
var _charge_tutorial_handoff_to: Rect2 = Rect2()
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
	var main_camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
	if main_camera != null:
		main_camera.set_cull_mask_value(SOUL_PRESENTATION_RENDER_LAYER, false)
		main_camera.set_cull_mask_value(GHOST_MOUNT_BEAM_RENDER_LAYER, true)
	_previous_p1_alive = game_state.p1_alive
	_previous_p2_alive = game_state.p2_alive
	_build_aim_visuals()


func remember_ocean_death_shark(player_index: int, shark: SharkSwimmerScript) -> void:
	if shark and is_instance_valid(shark):
		_preferred_ocean_sharks[player_index] = shark


func update_ghost_ride(
	delta: float,
	axis_p1: Vector2,
	axis_p2: Vector2,
	jump_p1: bool,
	jump_p2: bool,
	emote_p1: int,
	emote_p2: int,
	is_online: bool,
	is_replay: bool
) -> void:
	if game_state == null:
		return
	var fire_down := jump_p1 if dead_player_index == 1 else jump_p2
	var fire_pressed := fire_down and not _previous_fire_down
	var fire_released := not fire_down and _previous_fire_down
	var emote_input := emote_p1 if dead_player_index == 1 else emote_p2

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
				fire_released,
				emote_input
			)
	# サメ移動・壁スクロール・カメラ更新の後に判定しないと透過切替が1フレーム遅れる。
	call_deferred("_update_problem_wall_occlusion")
	_update_hud_animation(delta)

	_previous_fire_down = fire_down
	_previous_p1_alive = game_state.p1_alive
	_previous_p2_alive = game_state.p2_alive


func force_cleanup() -> void:
	end_return_portal_render_prewarm()
	_cleanup_ghost_ride()
	if game_state:
		_previous_p1_alive = game_state.p1_alive
		_previous_p2_alive = game_state.p2_alive


func begin_result_dismount(target_parent: Node) -> Node3D:
	if dead_player_index not in [1, 2] or target_parent == null:
		return null
	var released := _rider
	if released == null or not is_instance_valid(released):
		released = player_controller.create_ghost_rider_visual(dead_player_index)
		add_child(released)
	var released_transform := released.global_transform
	# Result characters belong to the gameplay camera again. Heroic soul travel
	# temporarily isolates the rider on layer 20, which the main camera culls.
	_set_rider_presentation_only(false)
	released.reparent(target_parent, false)
	released.global_transform = released_transform
	released.scale = Vector3.ONE
	player_controller.make_ghost_rider_translucent(released)
	_rider = null
	_clear_ghost_emote()
	_hide_aim_visuals()
	_result_departure_only = true
	_result_text = "RESULT RETURN"
	_hit_this_charge = false
	if _shark != null and is_instance_valid(_shark):
		_begin_cooldown()
	else:
		_cleanup_ghost_ride()
	result_rider_released.emit(released)
	return released


## 購入済みのP1/P2ポータルと実際の海サメ用Stencil材質を、黒画面の裏で
## カメラへ描画できる状態にする。ゲーム進行用の_return_portalやPhaseは触らない。
func begin_return_portal_render_prewarm(prewarm_camera: Camera3D) -> Dictionary:
	end_return_portal_render_prewarm()
	var report := {
		"ready": false,
		"portals": 0,
		"stencil_surfaces": 0,
	}
	if prewarm_camera == null or not is_instance_valid(prewarm_camera):
		return report

	_portal_prewarm_root = Node3D.new()
	_portal_prewarm_root.name = "GhostReturnPortalPrewarm"
	prewarm_camera.add_child(_portal_prewarm_root)

	var portal_scenes: Array[PackedScene] = [
		GHOST_RETURN_PORTAL_P1_SCENE,
		GHOST_RETURN_PORTAL_P2_SCENE,
	]
	for portal_index: int in range(portal_scenes.size()):
		var portal := portal_scenes[portal_index].instantiate() as Node3D
		if portal == null:
			continue
		portal.name = "PortalP%d" % (portal_index + 1)
		portal.visible = false
		_portal_prewarm_root.add_child(portal)
		portal.position = Vector3(-1.55 if portal_index == 0 else 1.55, 0.0, -5.2)
		portal.set("size", RETURN_PORTAL_SIZE)
		portal.set("portal_mode", 2)
		_make_return_portal_surface_opaque_for(portal)
		_build_return_portal_depth_for(portal)
		portal.set("animation_speed", RETURN_PORTAL_ANIMATION_SPEED)
		portal.set("open_amount", 1.0)
		portal.visible = true
		_portal_prewarm_instances[portal_index + 1] = portal
		report["portals"] = int(report["portals"]) + 1

	if stage_environment != null:
		for shark: SharkSwimmerScript in stage_environment.get_ocean_sharks():
			if shark == null or not is_instance_valid(shark):
				continue
			var surface_count: int = shark.begin_ghost_portal_render_prewarm()
			if surface_count <= 0:
				continue
			_portal_prewarm_sharks.append(shark)
			report["stencil_surfaces"] = int(report["stencil_surfaces"]) + surface_count

	report["ready"] = (
		int(report["portals"]) == portal_scenes.size()
		and int(report["stencil_surfaces"]) > 0
	)
	return report


func end_return_portal_render_prewarm() -> void:
	for shark: SharkSwimmerScript in _portal_prewarm_sharks:
		if shark != null and is_instance_valid(shark):
			shark.end_ghost_portal_render_prewarm()
	_portal_prewarm_sharks.clear()
	for player_index_variant: Variant in _portal_prewarm_instances:
		var player_index := int(player_index_variant)
		var portal := _portal_prewarm_instances[player_index_variant] as Node3D
		if portal == null or not is_instance_valid(portal):
			continue
		portal.reparent(self, false)
		_cache_return_portal(player_index, portal)
	_portal_prewarm_instances.clear()
	if _portal_prewarm_root != null and is_instance_valid(_portal_prewarm_root):
		_portal_prewarm_root.queue_free()
	_portal_prewarm_root = null


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
		"sequence_elapsed": _sequence_elapsed,
		"ghost_rendezvous_released": _ghost_rendezvous_released,
		"ghost_reveal_beams_started": _ghost_reveal_beams_started,
		"hover_target": _calculate_hover_target() if survivor_player_index > 0 else Vector3.ZERO,
		"aim_point": _current_aim_point() if survivor_player_index > 0 else Vector3.ZERO,
		"shark_position": _shark.global_position if _shark and is_instance_valid(_shark) else Vector3.ZERO,
		"rider_position": _rider.global_position if _rider and is_instance_valid(_rider) else Vector3.ZERO,
		"rendezvous_position": _rendezvous_position,
		"presentation_focus": _presentation_focus,
		"ghost_emote": _ghost_emote_id,
		"return_portal_active": _return_portal != null and is_instance_valid(_return_portal),
		"return_portal_position": (
			_return_portal.global_position
			if _return_portal != null and is_instance_valid(_return_portal)
			else Vector3.ZERO
		),
		"return_portal_elapsed": _return_portal_elapsed,
		"return_tail_clear_elapsed": _return_tail_clear_elapsed,
		"return_portal_close_started": _return_portal_close_started,
		"return_portal_surface_opaque": _return_portal_surface_opaque,
		"return_portal_open_amount": (
			float(_return_portal.get("open_amount"))
			if _return_portal != null and is_instance_valid(_return_portal)
			else 0.0
		),
		"return_portal_tail_distance": RETURN_PORTAL_TAIL_DISTANCE,
		"return_portal_exit_forward": (
			_return_portal_exit_direction
			if _return_portal_exit_direction.length_squared() > 0.0001
			else Vector3.ZERO
		),
		"return_portal_forward": (
			_return_portal.global_basis.z.normalized()
			if _return_portal != null and is_instance_valid(_return_portal)
			else Vector3.ZERO
		),
		"return_portal_path_alignment": _return_portal_path_alignment(),
		"return_portal_view_angle_degrees": _return_portal_view_angle_degrees(),
		"return_portal_tunnel_depth": RETURN_PORTAL_TUNNEL_DEPTH,
		"return_portal_tunnel_ring_count": _return_portal_depth_rings.size(),
		"return_portal_crossing_pulsed": _return_portal_crossing_pulsed,
		"return_shark_revealed": _cooldown_entry_started,
		"return_animation_locked": _return_animation_locked,
		"return_locked_hover_target": _return_locked_hover_target,
		"return_locked_aim_point": _return_locked_aim_point,
		"return_portal_preset": "portal_vfx_01" if dead_player_index == 1 else "portal_vfx_04",
		"hud_visible": _hud_panel != null and _hud_panel.visible,
		"hud_position": _hud_panel.position if _hud_panel != null else Vector2.ZERO,
		"hud_slide_progress": clampf(_hud_slide_elapsed / HUD_SLIDE_SECONDS, 0.0, 1.0),
		"hud_controls": _hud_controls.text if _hud_controls != null else "",
	}


func is_active_for_player(player_index: int) -> bool:
	return phase != Phase.INACTIVE and dead_player_index == player_index


## ゴーストシャークの操作（照準・チャージ）が可能なフェーズか。
func is_control_active_for_player(player_index: int) -> bool:
	return (
		dead_player_index == player_index
		and not is_charge_tutorial_active()
		and phase in [Phase.AIMING, Phase.WINDUP, Phase.CHARGING, Phase.COOLDOWN]
	)


func is_charge_tutorial_active() -> bool:
	return _charge_tutorial_active or _charge_tutorial_handoff_active


func dismiss_charge_tutorial() -> bool:
	if _charge_tutorial_handoff_active:
		return true
	if not _charge_tutorial_active:
		return false
	_start_charge_tutorial_handoff()
	return true


func get_presentation_state(player_index: int) -> Dictionary:
	if not is_active_for_player(player_index):
		return {"active": false}
	return {
		"active": true,
		"show_wipe": (
			phase in [
				Phase.DEATH_HOLD,
				Phase.SOUL_RISE,
				Phase.SOUL_FLIGHT,
				Phase.MOUNTING,
				Phase.BEAM_REVEAL,
			]
			or (phase == Phase.ENTERING and not _rider_revealed_to_main)
		),
		"phase": Phase.keys()[phase],
		"elapsed": _sequence_elapsed,
		"duration": HEROIC_SEQUENCE_SECONDS,
		"focus": _presentation_focus,
		"rider_position": (
			_rider.global_position
			if _rider != null and is_instance_valid(_rider)
			else _presentation_focus
		),
		"shark_position": (
			_shark.global_position
			if _shark != null and is_instance_valid(_shark)
			else _rendezvous_position
		),
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
	phase = Phase.DEATH_HOLD
	_phase_timer = DEATH_HOLD_SECONDS
	_sequence_elapsed = 0.0
	_ghost_rendezvous_released = false
	_ghost_reveal_beams_started = false
	_previous_fire_down = false
	_death_position = _death_presentation_position(dead_player_index)
	_hover_side = signf(_death_position.x - _player_position(survivor_player_index).x)
	if is_zero_approx(_hover_side):
		_hover_side = 1.0 if dead_player_index == 1 else -1.0
	_aim_offset = Vector2.ZERO
	_charging_input = false
	_charge_amount = 0.0
	_combo = 0
	_best_combo = 0
	_apply_player_aim_color()
	_hide_aim_visuals()
	_prepare_fixed_targets()
	_shark = _acquire_shark()
	if _shark == null:
		_cleanup_ghost_ride()
		return
	_connect_shark_signals()
	_rendezvous_position = _calculate_rendezvous_position()
	if not _shark.prepare_ghost_rendezvous(
		dead_player_index,
		_rendezvous_position,
		_current_aim_point()
	):
		_shark = null
		_cleanup_ghost_ride()
		return
	_rider = player_controller.create_ghost_rider_visual(dead_player_index)
	if _rider == null:
		_cleanup_ghost_ride()
		return
	add_child(_rider)
	_rider_revealed_to_main = false
	_set_rider_presentation_only(true)
	_soul_start_position = _death_position + Vector3.UP * 0.16
	_soul_rise_position = (
		_soul_start_position
		+ Vector3(-_hover_side * 0.24, SOUL_RISE_HEIGHT, 0.34)
	)
	_rider.global_position = _soul_start_position
	_rider.global_rotation = Vector3.ZERO
	var mount_target := _shark.get_ghost_rendezvous_mount_world_position()
	_soul_control_a = (
		_soul_rise_position
		+ Vector3(_hover_side * SOUL_FLIGHT_SIDE_ARC, SOUL_FLIGHT_LIFT, 2.35)
	)
	_soul_control_b = (
		mount_target
		+ Vector3(-_hover_side * 1.05, SOUL_FLIGHT_LIFT * 0.46, -0.55)
	)
	_presentation_focus = _soul_start_position
	_presentation_follow_anchor_z = _survivor_camera_anchor_z()
	_presentation_follow_initialized = true
	player_controller.sample_ghost_mount_pose(_rider, 0.0)
	_set_meter(0.0, _player_color)
	_hud_slide_elapsed = 0.0
	_hud_slide_active = false
	if _hud_panel != null:
		_hud_panel.visible = false
		_hud_panel.modulate.a = 0.0


func _try_release_ghost_rendezvous_after_wipe() -> void:
	if (
		_ghost_rendezvous_released
		or _shark == null
		or not is_instance_valid(_shark)
		or phase not in [Phase.DEATH_HOLD, Phase.SOUL_RISE, Phase.SOUL_FLIGHT]
	):
		return
	var death_wipe := get_parent().get_node_or_null("DeathWipeLayer/DeathWipe")
	var wipe_is_settled := false
	if death_wipe != null and death_wipe.has_method("is_settled_for_player"):
		wipe_is_settled = bool(
			death_wipe.call("is_settled_for_player", dead_player_index)
		)
	else:
		# Non-UI test scenes still receive the same minimum entrance hold.
		wipe_is_settled = _sequence_elapsed >= DEATH_HOLD_SECONDS
	if not wipe_is_settled:
		return
	_ghost_rendezvous_released = _shark.start_ghost_rendezvous_ascent()


func _base_mode_is_eligible(is_online: bool, is_replay: bool) -> bool:
	return (
		game_state.num_players == 2
		and not game_state.is_coop_mode()
		# チュートリアルでは搭乗を許すステップ（海・ゴースト練習・実戦・最終レース）だけ。
		and game_state.allows_tutorial_ghost_ride()
		and not is_online
		and not is_replay
	)


func _can_continue(is_online: bool, is_replay: bool) -> bool:
	if not _base_mode_is_eligible(is_online, is_replay):
		return false
	if game_state.game_state not in [
		Constants.STATE_PLAYING,
		Constants.STATE_CORRECT,
		Constants.STATE_GOAL_RACE,
		Constants.STATE_RESULT_CEREMONY,
		Constants.STATE_CLEAR,
	]:
		return false
	# 復活したプレイヤーがサメに乗り続けないよう、乗り手が生き返ったら畳む。
	# チュートリアルの復活（最終レース前・全滅やり直し）がこの経路を通る。
	if _is_player_alive(dead_player_index):
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
	fire_released: bool,
	emote_input: int
) -> void:
	if phase in [
		Phase.DEATH_HOLD,
		Phase.SOUL_RISE,
		Phase.SOUL_FLIGHT,
		Phase.MOUNTING,
		Phase.BEAM_REVEAL,
	]:
		_update_heroic_camera_follow()
	_try_release_ghost_rendezvous_after_wipe()
	if phase in [
		Phase.ENTERING,
		Phase.AIMING,
		Phase.WINDUP,
		Phase.CHARGING,
		Phase.COOLDOWN,
	] and not (phase == Phase.COOLDOWN and _return_animation_locked):
		_update_progress_follow()
	match phase:
		Phase.DEATH_HOLD:
			_advance_heroic_sequence(delta)
			_phase_timer -= delta
			_death_position = _death_presentation_position(dead_player_index)
			_soul_start_position = _death_position + Vector3.UP * 0.16
			if _rider != null and is_instance_valid(_rider):
				_rider.global_position = _soul_start_position
			_presentation_focus = _soul_start_position
			if _phase_timer <= 0.0:
				_begin_soul_rise()
		Phase.SOUL_RISE:
			_advance_heroic_sequence(delta)
			_update_soul_travel(delta)
		Phase.SOUL_FLIGHT:
			_advance_heroic_sequence(delta)
			_update_soul_travel(delta)
		Phase.MOUNTING:
			_advance_heroic_sequence(delta)
			_phase_timer -= delta
			if _rider != null and is_instance_valid(_rider):
				var mount_pose_progress := clampf(
					1.0 - _phase_timer / MOUNTING_SECONDS,
					0.0,
					1.0
				)
				player_controller.apply_ghost_rider_mounted_pose(
					_rider,
					smoothstep(0.0, 0.78, mount_pose_progress)
				)
				_presentation_focus = _rider.global_position.lerp(
					_shark.global_position,
					0.38
				)
			if _phase_timer <= 0.0 and _shark.is_ghost_mount_settled():
				_begin_post_mount_beam_reveal()
		Phase.BEAM_REVEAL:
			_advance_heroic_sequence(delta)
			_phase_timer = maxf(0.0, _phase_timer - delta)
			player_controller.apply_ghost_rider_mounted_pose(_rider)
			_presentation_focus = _rider.global_position.lerp(
				_shark.global_position,
				0.38
			)
			if game_state != null and _shark.is_ghost_reveal_beam_firing():
				game_state.camera_shake = maxf(
					game_state.camera_shake,
					GHOST_MOUNT_BEAM_SUSTAINED_CAMERA_SHAKE
				)
			if _shark.is_ghost_reveal_sequence_complete():
				_begin_authored_entry()
		Phase.DEATH_DELAY:
			_phase_timer -= delta
			_set_meter(1.0 - clampf(_phase_timer / DEATH_DELAY_SECONDS, 0.0, 1.0), _player_color)
			_update_hud("幽霊サメ召喚まで %.1f 秒" % maxf(0.0, _phase_timer))
			if _phase_timer <= 0.0:
				_start_ghost_ride()
		Phase.ENTERING:
			_advance_heroic_sequence(delta)
			# Once contact is complete, keep the rider planted on the seat and both
			# hands on the grips while the shark performs its departure motion.
			player_controller.apply_ghost_rider_mounted_pose(_rider)
			_presentation_focus = _shark.global_position
			_update_hover_target()
			_phase_timer -= delta
			var entry_pose_progress := clampf(
				1.0 - _phase_timer / ENTRY_SECONDS,
				0.0,
				1.0
			)
			if not _rider_revealed_to_main and entry_pose_progress >= STAGE_REVEAL_PROGRESS:
				_rider_revealed_to_main = true
				_set_rider_presentation_only(false)
			if _phase_timer <= 0.0 and _shark and _shark.is_ghost_hovering():
				phase = Phase.AIMING
				player_controller.apply_ghost_rider_mount_hold_pose(_rider)
				if _should_show_charge_tutorial():
					_start_charge_tutorial()
				else:
					_show_aim_visuals()
					_start_hud_intro()
		Phase.AIMING:
			if is_charge_tutorial_active():
				if _charge_tutorial_handoff_active:
					_update_charge_tutorial_handoff(delta)
				else:
					_update_charge_tutorial(delta)
				_update_hover_target()
				if _shark != null and is_instance_valid(_shark):
					_presentation_focus = _shark.global_position
				return
			_update_ghost_emote(emote_input, fire_pressed)
			var aim_axis := axis_p1 if dead_player_index == 1 else axis_p2
			if aim_axis.length_squared() > 0.02:
				aim_used.emit(dead_player_index)
			_aim_offset.x = clampf(_aim_offset.x + aim_axis.x * AIM_SPEED * delta, -AIM_SIDE_LIMIT, AIM_SIDE_LIMIT)
			_aim_offset.y = clampf(_aim_offset.y + aim_axis.y * AIM_SPEED * delta, -AIM_BACK_LIMIT, AIM_FORWARD_LIMIT)
			_update_hover_target()
			_update_charge_input(delta, fire_down, fire_pressed, fire_released)
			_update_aim_visuals(false)
		Phase.WINDUP:
			_clear_ghost_emote()
			_update_hover_target()
			_phase_timer -= delta
			_update_aim_visuals(true)
			_set_meter(_last_charge_power, _charge_feedback_color(_last_charge_power))
			if _phase_timer <= 0.0:
				_start_charge()
		Phase.CHARGING:
			_clear_ghost_emote()
			_update_charge_sweep()
			if _charge_finished_pending:
				_begin_cooldown()
		Phase.COOLDOWN:
			if not _result_departure_only:
				_update_ghost_emote(emote_input, false)
			_update_cooldown(delta)
	if (
		phase in [Phase.AIMING, Phase.WINDUP, Phase.CHARGING, Phase.COOLDOWN]
		and _shark != null
		and is_instance_valid(_shark)
	):
		_presentation_focus = _shark.global_position


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
		_charge_amount = fposmod(_charge_amount + delta / CHARGE_BUILD_SECONDS, 1.0)
		if _shark and _shark.has_method("set_ghost_charge_tension"):
			_shark.set_ghost_charge_tension(_charge_amount)
		_set_meter(_charge_amount, _charge_feedback_color(_charge_amount))
		if _is_perfect_power(_charge_amount):
			_update_hud("PERFECT 帯！ 今離すと強力")
		else:
			_update_hud("霊力チャージ %d%%" % roundi(_charge_amount * 100.0))
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


func _prepare_fixed_targets() -> void:
	var survivor_position := _player_position(survivor_player_index)
	_aim_origin = Vector3(
		survivor_position.x,
		survivor_position.y + 0.85,
		survivor_position.z
	)
	var desired_hover_target := Vector3(
		_hover_side * (StageConstants.FLOOR_HALF_WIDTH + HOVER_OUTSIDE_STAGE_OFFSET),
		StageConstants.FLOOR_TOP_Y + 3.8,
		survivor_position.z + 6.0
	)
	_fixed_hover_target = _keep_inside_camera(
		desired_hover_target,
		survivor_position + Vector3.UP * 2.2,
		_hover_side
	)
	_hover_progress_offset_z = _fixed_hover_target.z - survivor_position.z


func _update_progress_follow() -> void:
	if survivor_player_index <= 0:
		return
	var survivor_position := _player_position(survivor_player_index)
	_aim_origin.y = survivor_position.y + 0.85
	_aim_origin.z = survivor_position.z
	_fixed_hover_target.z = survivor_position.z + _hover_progress_offset_z


func _survivor_camera_anchor_z() -> float:
	if (
		camera_controller != null
		and game_state != null
		and camera_controller.has_method("get_gameplay_pose")
	):
		var pose: Dictionary = camera_controller.call("get_gameplay_pose", game_state)
		var target_variant: Variant = pose.get("target", Vector3.ZERO)
		if target_variant is Vector3:
			return (target_variant as Vector3).z
	return _player_position(survivor_player_index).z


func _update_heroic_camera_follow() -> void:
	if survivor_player_index <= 0:
		return
	var current_anchor_z := _survivor_camera_anchor_z()
	if not _presentation_follow_initialized:
		_presentation_follow_anchor_z = current_anchor_z
		_presentation_follow_initialized = true
		return
	var follow_delta_z := current_anchor_z - _presentation_follow_anchor_z
	_presentation_follow_anchor_z = current_anchor_z
	if absf(follow_delta_z) <= 0.0001:
		return
	var offset := Vector3(0.0, 0.0, follow_delta_z)
	_death_position += offset
	_soul_start_position += offset
	_soul_rise_position += offset
	_soul_control_a += offset
	_soul_control_b += offset
	_rendezvous_position += offset
	_presentation_focus += offset
	_aim_origin += offset
	_fixed_hover_target += offset
	if _shark != null and is_instance_valid(_shark):
		_shark.translate_ghost_ride_presentation(offset)


func _calculate_rendezvous_position() -> Vector3:
	return Vector3(
		_fixed_hover_target.x + _hover_side * RENDEZVOUS_SIDE_DISTANCE,
		StageConstants.OCEAN_SURFACE_Y + RENDEZVOUS_SURFACE_CLEARANCE,
		_fixed_hover_target.z
		- RENDEZVOUS_BACK_DISTANCE
		+ RENDEZVOUS_REVEAL_DEPTH_OFFSET
	)


func _begin_soul_rise() -> void:
	phase = Phase.SOUL_RISE
	_phase_timer = SOUL_RISE_SECONDS
	_soul_travel_elapsed = 0.0
	if _rider != null and is_instance_valid(_rider):
		_soul_start_position = _rider.global_position
	_soul_rise_position = (
		_soul_start_position
		+ Vector3(-_hover_side * 0.24, SOUL_RISE_HEIGHT, 0.34)
	)
	var mount_target := _shark.get_ghost_rendezvous_mount_world_position()
	_soul_control_a = (
		_soul_rise_position
		+ Vector3(_hover_side * SOUL_FLIGHT_SIDE_ARC, SOUL_FLIGHT_LIFT, 2.35)
	)
	_soul_control_b = (
		mount_target
		+ Vector3(-_hover_side * 1.05, SOUL_FLIGHT_LIFT * 0.46, -0.55)
	)


func _update_soul_travel(delta: float) -> void:
	if _shark == null or not is_instance_valid(_shark):
		_cleanup_ghost_ride()
		return
	_soul_travel_elapsed = minf(SOUL_TRAVEL_SECONDS, _soul_travel_elapsed + delta)
	var travel_progress := clampf(_soul_travel_elapsed / SOUL_TRAVEL_SECONDS, 0.0, 1.0)
	# One curve owns the full extraction-to-contact trip.  The only ease points
	# are the first lift-off and the final contact; SOUL_RISE -> SOUL_FLIGHT no
	# longer creates a second stop/start pair.
	var travel_weight := _cinematic_travel_ease(travel_progress)
	var mount_target := _shark.get_ghost_mount_world_position()
	var soul_position := _cubic_bezier(
		_soul_start_position,
		_soul_control_a,
		_soul_control_b,
		mount_target,
		travel_weight
	)
	if _rider != null and is_instance_valid(_rider):
		var look_weight := minf(1.0, travel_weight + 0.012)
		var look_position := _cubic_bezier(
			_soul_start_position,
			_soul_control_a,
			_soul_control_b,
			mount_target,
			look_weight
		)
		_rider.global_position = soul_position
		if soul_position.distance_squared_to(look_position) > 0.0001:
			_rider.look_at(look_position, Vector3.UP)
		var launch_bank := sin(travel_progress * PI) * -_hover_side * 0.16
		var contact_counter_bank := (
			smoothstep(0.72, 1.0, travel_progress)
			* _hover_side
			* 0.09
		)
		_rider.rotation.z += launch_bank + contact_counter_bank
		var extraction_scale := lerpf(
			0.86,
			1.0,
			smoothstep(0.0, 0.22, travel_progress)
		)
		var mounted_scale := float(_rider.get_meta("ghost_mount_scale", 0.92))
		_rider.scale = Vector3.ONE * mounted_scale * extraction_scale
		# Become solid before contact so the translucent soul never overlaps the
		# shark for a visible frame during the mount handoff.
		if travel_progress >= 0.78:
			player_controller.make_ghost_rider_opaque(_rider)
		_presentation_focus = _rider.global_position
	if _soul_travel_elapsed < SOUL_RISE_SECONDS:
		phase = Phase.SOUL_RISE
		_phase_timer = SOUL_RISE_SECONDS - _soul_travel_elapsed
	elif _soul_travel_elapsed < SOUL_TRAVEL_SECONDS:
		phase = Phase.SOUL_FLIGHT
		_phase_timer = SOUL_TRAVEL_SECONDS - _soul_travel_elapsed
	else:
		_begin_mounting()


func _begin_mounting() -> void:
	if _shark == null or _rider == null or not is_instance_valid(_rider):
		_cleanup_ghost_ride()
		return
	if not _shark.is_ghost_rendezvous_ready():
		_phase_timer = 0.0
		return
	player_controller.make_ghost_rider_opaque(_rider)
	_rider.global_position = _shark.get_ghost_mount_world_position()
	if not _shark.begin_ghost_ride(dead_player_index, _rider):
		_cleanup_ghost_ride()
		return
	phase = Phase.MOUNTING
	_phase_timer = MOUNTING_SECONDS
	_presentation_focus = _rider.global_position


func _begin_post_mount_beam_reveal() -> void:
	if _shark == null or _rider == null or not is_instance_valid(_rider):
		_cleanup_ghost_ride()
		return
	player_controller.apply_ghost_rider_mounted_pose(_rider)
	if not _shark.start_ghost_reveal_beams():
		return
	_ghost_reveal_beams_started = true
	phase = Phase.BEAM_REVEAL
	_phase_timer = POST_MOUNT_BEAM_REVEAL_SECONDS
	_presentation_focus = _rider.global_position


func _begin_authored_entry() -> void:
	if _shark == null or not is_instance_valid(_shark):
		_cleanup_ghost_ride()
		return
	_update_progress_follow()
	var hover_target := _fixed_hover_target
	if not _shark.depart_ghost_rendezvous(hover_target, _current_aim_point()):
		_cleanup_ghost_ride()
		return
	phase = Phase.ENTERING
	_phase_timer = ENTRY_SECONDS
	_clear_ghost_emote()


func _cinematic_travel_ease(progress: float) -> float:
	var clamped := clampf(progress, 0.0, 1.0)
	# Quintic smoothstep keeps lift-off/contact velocity at zero while its steeper
	# middle section gives the flight a readable acceleration instead of a drift.
	return clamped * clamped * clamped * (
		clamped * (clamped * 6.0 - 15.0) + 10.0
	)


func _set_rider_presentation_only(presentation_only: bool) -> void:
	if _rider == null or not is_instance_valid(_rider):
		return
	for node: Node in _rider.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == null:
			continue
		geometry.set_layer_mask_value(1, not presentation_only)
		geometry.set_layer_mask_value(SOUL_PRESENTATION_RENDER_LAYER, presentation_only)


func _update_ghost_emote(emote_input: int, cancel: bool) -> void:
	if _rider == null or not is_instance_valid(_rider):
		return
	if cancel:
		_clear_ghost_emote()
		return
	if emote_input > 0:
		_ghost_emote_id = EmoteData.normalize_emote_id(emote_input)
	if _ghost_emote_id <= 0:
		player_controller.apply_ghost_rider_mount_hold_pose(_rider)
		return
	player_controller.apply_ghost_rider_emote_pose(
		_rider,
		dead_player_index,
		_ghost_emote_id
	)
	player_controller.apply_ghost_rider_mounted_pose(_rider, 1.0, true)


func _clear_ghost_emote() -> void:
	if _ghost_emote_id <= 0:
		return
	_ghost_emote_id = 0
	if player_controller != null:
		player_controller.stop_ghost_rider_emote(_rider, dead_player_index)


func _advance_heroic_sequence(delta: float) -> void:
	_sequence_elapsed = minf(HEROIC_SEQUENCE_SECONDS, _sequence_elapsed + delta)
	if _rider != null and is_instance_valid(_rider):
		var clip_length := player_controller.get_ghost_mount_animation_length()
		var pose_time := (
			_sequence_elapsed / HEROIC_SEQUENCE_SECONDS * clip_length
			if clip_length > 0.0
			else _sequence_elapsed
		)
		player_controller.sample_ghost_mount_pose(_rider, pose_time)


func _death_presentation_position(player_index: int) -> Vector3:
	if player_controller != null and player_controller.has_method("get_death_presentation_position"):
		return player_controller.get_death_presentation_position(player_index == 1)
	return _player_position(player_index)


func _cubic_bezier(
	start: Vector3,
	control_a: Vector3,
	control_b: Vector3,
	finish: Vector3,
	weight: float
) -> Vector3:
	var inverse := 1.0 - weight
	return (
		start * inverse * inverse * inverse
		+ control_a * 3.0 * inverse * inverse * weight
		+ control_b * 3.0 * inverse * weight * weight
		+ finish * weight * weight * weight
	)


func _start_ghost_ride() -> void:
	_shark = _acquire_shark()
	if _shark == null:
		_cleanup_ghost_ride()
		return
	var rider := player_controller.create_ghost_rider_visual(dead_player_index)
	player_controller.make_ghost_rider_opaque(rider)
	var survivor_position := _player_position(survivor_player_index)
	_aim_origin = Vector3(survivor_position.x, survivor_position.y + 0.85, survivor_position.z)
	var desired_hover_target := Vector3(
		_hover_side * (StageConstants.FLOOR_HALF_WIDTH + HOVER_OUTSIDE_STAGE_OFFSET),
		StageConstants.FLOOR_TOP_Y + 3.8,
		survivor_position.z + 6.0
	)
	_fixed_hover_target = _keep_inside_camera(
		desired_hover_target,
		survivor_position + Vector3.UP * 2.2,
		_hover_side
	)
	_hover_progress_offset_z = _fixed_hover_target.z - survivor_position.z
	var hover_target := _fixed_hover_target
	var aim_point := _current_aim_point()
	if not _shark.begin_ghost_ride(dead_player_index, rider):
		rider.queue_free()
		_shark = null
		_cleanup_ghost_ride()
		return
	_connect_shark_signals()
	_shark.restart_ghost_hover(
		_calculate_entry_position(hover_target),
		hover_target,
		aim_point
	)
	phase = Phase.ENTERING
	_phase_timer = ENTRY_SECONDS
	_update_hud("海から接近中…")


func _acquire_shark() -> SharkSwimmerScript:
	var preferred_variant: Variant = _preferred_ocean_sharks.get(dead_player_index)
	var preferred := preferred_variant as SharkSwimmerScript
	if preferred and is_instance_valid(preferred) and preferred.is_available_for_ocean_attack():
		_preferred_ocean_sharks.erase(dead_player_index)
		return preferred
	if stage_environment == null:
		return null
	var selected: SharkSwimmerScript = null
	var best_distance := INF
	for candidate: SharkSwimmerScript in stage_environment.get_ocean_sharks():
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
	var hover_target := (
		_return_locked_hover_target if _return_animation_locked else _fixed_hover_target
	)
	var aim_point := (
		_return_locked_aim_point if _return_animation_locked else _current_aim_point()
	)
	_shark.set_ghost_hover_target(hover_target, aim_point)


func _update_problem_wall_occlusion() -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	var is_occluded := false
	var world := get_parent()
	if world != null and world.has_method("is_problem_wall_occluding_segment"):
		var sample_points := _ghost_occlusion_sample_points()
		for camera: Camera3D in _occlusion_cameras():
			var cam_pos := camera.global_position
			for sample: Vector3 in sample_points:
				if bool(world.call(
					"is_problem_wall_occluding_segment",
					cam_pos,
					sample
				)):
					is_occluded = true
					break
			if is_occluded:
				break
	_shark.set_ghost_wall_occluded(is_occluded)


func _occlusion_cameras() -> Array[Camera3D]:
	var cameras: Array[Camera3D] = []
	if camera_controller != null:
		var main_camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
		if main_camera != null:
			cameras.append(main_camera)
	var world := get_parent()
	if world != null:
		var wipe_camera := world.get_node_or_null(
			"DeathWipeLayer/DeathWipe/SubViewport/WipeCamera"
		) as Camera3D
		if wipe_camera != null:
			cameras.append(wipe_camera)
	return cameras


func _ghost_occlusion_sample_points() -> Array[Vector3]:
	var origin := _shark.global_position
	var forward := -_shark.global_basis.z
	var right := _shark.global_basis.x
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	# 中心一点だと胴体が壁に入ってから透過するまで遅れて見えるため、
	# サメの前後・左右・上部も同じフレームで判定する。
	return [
		origin + Vector3.UP * 0.35,
		origin + forward * 1.35 + Vector3.UP * 0.25,
		origin - forward * 1.35 + Vector3.UP * 0.25,
		origin + right * 0.65 + Vector3.UP * 0.30,
		origin - right * 0.65 + Vector3.UP * 0.30,
		origin + Vector3.UP * 0.95,
	]


func _calculate_hover_target() -> Vector3:
	return _return_locked_hover_target if _return_animation_locked else _fixed_hover_target


func _calculate_entry_position(hover_target: Vector3) -> Vector3:
	return Vector3(
		hover_target.x + _hover_side * ENTRY_SIDE_DISTANCE,
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
	return Vector3(
		_aim_origin.x + _aim_offset.x,
		_aim_origin.y,
		_aim_origin.z + _aim_offset.y
	)


func _start_charge() -> void:
	var charge_speed := lerpf(MIN_CHARGE_SPEED, MAX_CHARGE_SPEED, _last_charge_power)
	var charge_distance := lerpf(MIN_CHARGE_DISTANCE, MAX_CHARGE_DISTANCE, _last_charge_power)
	if _perfect_charge:
		charge_speed += 3.0
	if _shark == null or not is_instance_valid(_shark):
		_cleanup_ghost_ride()
		return
	# The survivor can progress during the windup. Commit the full 3D direction
	# through the aim marker at launch so the dash dives onto the player instead
	# of staying flat at hover height and sailing above them.
	var aim_point := _current_aim_point()
	_locked_direction = _shark.global_position.direction_to(aim_point)
	if _locked_direction.length_squared() <= 0.001:
		_cleanup_ghost_ride()
		return
	if Vector2(_locked_direction.x, _locked_direction.z).length_squared() <= 0.001:
		_cleanup_ghost_ride()
		return
	if not _shark.launch_ghost_charge(_locked_direction, charge_speed, charge_distance):
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


func _connect_shark_signals() -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	if not _shark.ghost_charge_finished.is_connected(_on_shark_charge_finished):
		_shark.ghost_charge_finished.connect(_on_shark_charge_finished)
	if not _shark.ghost_mount_beam_fired.is_connected(_on_ghost_mount_beam_fired):
		_shark.ghost_mount_beam_fired.connect(_on_ghost_mount_beam_fired)


func _on_ghost_mount_beam_fired(_beam_index: int) -> void:
	if game_state == null or phase != Phase.BEAM_REVEAL:
		return
	game_state.camera_shake = maxf(
		game_state.camera_shake,
		GHOST_MOUNT_BEAM_LAUNCH_CAMERA_SHAKE
	)


func _begin_cooldown() -> void:
	phase = Phase.COOLDOWN
	# 復帰演出中は生存プレイヤーの移動でポータル位置・通過経路・姿勢を
	# 更新しない。攻撃終了時の構図をアニメーション完了まで保持する。
	_return_animation_locked = true
	_return_locked_hover_target = _fixed_hover_target
	_return_locked_aim_point = _current_aim_point()
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
	_current_cooldown_duration = maxf(
		_current_cooldown_duration,
		RETURN_PORTAL_SEQUENCE_SECONDS
	)
	_phase_timer = _current_cooldown_duration
	_cooldown_entry_started = false
	_return_portal_elapsed = 0.0
	_return_tail_clear_elapsed = 0.0
	_return_portal_close_started = false
	_return_portal_exit_direction = Vector3.ZERO
	_return_portal_crossing_pulsed = false
	_return_portal_crossing_flash_elapsed = -1.0
	_cleanup_return_portal()
	_charge_finished_pending = false
	_charging_input = false
	_charge_amount = 0.0
	if _shark and _shark.has_method("set_ghost_charge_tension"):
		_shark.set_ghost_charge_tension(0.0)
	if _shark:
		_shark.visible = false
	_set_meter(0.0, _player_color)
	_update_hud("%s  /  再突進 %.1f 秒" % [_result_text, _phase_timer])
	charge_resolved.emit(dead_player_index, _hit_this_charge, _last_charge_power)


func _spawn_return_portal() -> void:
	var cached_portal := _return_portal_cache.get(dead_player_index) as Node3D
	var reused_prepared_portal := cached_portal != null and is_instance_valid(cached_portal)
	if reused_prepared_portal:
		_return_portal_cache.erase(dead_player_index)
		_return_portal = cached_portal
		_return_portal.process_mode = Node.PROCESS_MODE_INHERIT
		_return_portal.transform = Transform3D.IDENTITY
		_bind_return_portal_depth(_return_portal)
	else:
		var portal_scene: PackedScene = (
			GHOST_RETURN_PORTAL_P1_SCENE
			if dead_player_index == 1
			else GHOST_RETURN_PORTAL_P2_SCENE
		)
		_return_portal = portal_scene.instantiate() as Node3D
	if _return_portal == null:
		push_warning("Ghost return portal preset could not be instantiated")
		return
	_return_portal.name = "GhostReturnPortalP%d" % dead_player_index
	_return_portal.visible = false
	if not reused_prepared_portal:
		add_child(_return_portal)
	_return_portal.set("size", RETURN_PORTAL_SIZE)
	# The official pack's emergence demo relies on its stencil aperture: the
	# rider and shark are visible through the opening before they clear its plane.
	_return_portal.set("portal_mode", 2)
	if not reused_prepared_portal:
		_make_return_portal_surface_opaque()
		_build_return_portal_depth()
	_return_portal.set("animation_speed", RETURN_PORTAL_ANIMATION_SPEED)
	_return_portal_exit_direction = _return_portal_exit_forward(_calculate_hover_target())
	_update_return_portal_transform()
	_return_portal.set("open_amount", 0.0)
	_return_portal.visible = true
	var portal_particles := _return_portal.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if portal_particles != null:
		portal_particles.restart()
	_return_portal.call("open")


## Keep the purchased preset's stencil writer active, but render its central
## aperture at full opacity. The glow ring and particles remain authored VFX.
func _make_return_portal_surface_opaque() -> void:
	if _return_portal == null or not is_instance_valid(_return_portal):
		_return_portal_surface_opaque = false
		return
	_return_portal_surface_opaque = _make_return_portal_surface_opaque_for(_return_portal)


func _make_return_portal_surface_opaque_for(portal: Node3D) -> bool:
	if portal == null or not is_instance_valid(portal):
		return false
	var portal_mesh := portal.get_node_or_null("PortalMesh") as MeshInstance3D
	if portal_mesh == null:
		push_warning("Ghost return portal is missing PortalMesh")
		return false
	var source_material := portal_mesh.material_override as ShaderMaterial
	if source_material == null:
		push_warning("Ghost return portal PortalMesh is missing its shader material")
		return false
	var opaque_material := source_material.duplicate(true) as ShaderMaterial
	if opaque_material == null:
		push_warning("Ghost return portal material could not be localized")
		return false
	portal_mesh.material_override = opaque_material
	opaque_material.set_shader_parameter("portal_mode", 0)
	return int(opaque_material.get_shader_parameter("portal_mode")) == 0


## Give the preset a physical interior: the authored opaque PortalMesh becomes
## the rear wall, while a tapered shell and moving rings make its depth readable
## from the gameplay camera. The purchased glow and particle nodes stay at the mouth.
func _build_return_portal_depth() -> void:
	_return_portal_depth_rings.clear()
	_return_portal_depth_root = null
	_return_portal_depth_light = null
	if _return_portal == null or not is_instance_valid(_return_portal):
		return
	var depth_parts := _build_return_portal_depth_for(_return_portal)
	_return_portal_depth_root = depth_parts.get("root") as Node3D
	var rings_variant: Variant = depth_parts.get("rings", [])
	if rings_variant is Array:
		for ring_variant: Variant in rings_variant:
			var ring := ring_variant as MeshInstance3D
			if ring != null:
				_return_portal_depth_rings.append(ring)
	_return_portal_depth_light = depth_parts.get("light") as OmniLight3D
	_update_return_portal_depth_effect(0.0)


func _bind_return_portal_depth(portal: Node3D) -> void:
	_return_portal_depth_rings.clear()
	_return_portal_depth_root = portal.get_node_or_null("DepthInterior") as Node3D
	_return_portal_depth_light = null
	if _return_portal_depth_root != null:
		for child: Node in _return_portal_depth_root.get_children():
			if child is MeshInstance3D and child.name.begins_with("DepthRing"):
				_return_portal_depth_rings.append(child as MeshInstance3D)
			elif child is OmniLight3D and child.name == "CrossingFlash":
				_return_portal_depth_light = child as OmniLight3D
	var portal_mesh := portal.get_node_or_null("PortalMesh") as MeshInstance3D
	var portal_material := (
		portal_mesh.material_override as ShaderMaterial if portal_mesh != null else null
	)
	_return_portal_surface_opaque = (
		portal_material != null
		and int(portal_material.get_shader_parameter("portal_mode")) == 0
	)


func _build_return_portal_depth_for(portal: Node3D) -> Dictionary:
	var depth_parts := {"root": null, "rings": [], "light": null}
	if portal == null or not is_instance_valid(portal):
		return depth_parts
	var primary_variant: Variant = portal.get("primary_color")
	var secondary_variant: Variant = portal.get("secondary_color")
	var primary_color: Color = (
		primary_variant if primary_variant is Color else _player_color
	)
	var secondary_color: Color = (
		secondary_variant if secondary_variant is Color else _player_color.darkened(0.58)
	)

	var portal_mesh := portal.get_node_or_null("PortalMesh") as MeshInstance3D
	if portal_mesh != null:
		portal_mesh.position.z = -RETURN_PORTAL_TUNNEL_DEPTH + 0.025
		portal_mesh.scale = Vector3(0.78, 0.78, 1.0)

	var depth_root := Node3D.new()
	depth_root.name = "DepthInterior"
	portal.add_child(depth_root)

	var tunnel_instance := MeshInstance3D.new()
	tunnel_instance.name = "TaperedTunnel"
	var tunnel_mesh := CylinderMesh.new()
	tunnel_mesh.top_radius = RETURN_PORTAL_TUNNEL_MOUTH_RADIUS
	tunnel_mesh.bottom_radius = RETURN_PORTAL_TUNNEL_BACK_RADIUS
	tunnel_mesh.height = RETURN_PORTAL_TUNNEL_DEPTH
	tunnel_mesh.radial_segments = 64
	tunnel_mesh.rings = 8
	tunnel_mesh.cap_top = false
	tunnel_mesh.cap_bottom = true
	tunnel_mesh.flip_faces = true
	var tunnel_material := StandardMaterial3D.new()
	tunnel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tunnel_material.albedo_color = secondary_color.darkened(0.76)
	tunnel_material.emission_enabled = true
	tunnel_material.emission = primary_color.darkened(0.62)
	tunnel_material.emission_energy_multiplier = 0.72
	tunnel_material.metallic_specular = 0.0
	tunnel_material.disable_fog = true
	tunnel_mesh.material = tunnel_material
	tunnel_instance.mesh = tunnel_mesh
	tunnel_instance.rotation_degrees.x = 90.0
	tunnel_instance.position.z = -RETURN_PORTAL_TUNNEL_DEPTH * 0.5
	tunnel_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	depth_root.add_child(tunnel_instance)

	var depth_rings: Array[MeshInstance3D] = []
	for ring_index: int in range(RETURN_PORTAL_TUNNEL_RING_COUNT):
		var ring := MeshInstance3D.new()
		ring.name = "DepthRing%02d" % (ring_index + 1)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.94
		ring_mesh.outer_radius = 1.0
		ring_mesh.rings = 48
		ring_mesh.ring_segments = 8
		var ring_material := StandardMaterial3D.new()
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var ring_mix := float(ring_index) / maxf(
			1.0,
			float(RETURN_PORTAL_TUNNEL_RING_COUNT - 1)
		)
		var ring_color := primary_color.lerp(secondary_color, ring_mix * 0.48)
		ring_color.a = lerpf(0.88, 0.56, ring_mix)
		ring_material.albedo_color = ring_color
		ring_material.emission_enabled = true
		ring_material.emission = ring_color
		ring_material.emission_energy_multiplier = lerpf(2.25, 1.35, ring_mix)
		ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_material.disable_fog = true
		ring_mesh.material = ring_material
		ring.mesh = ring_mesh
		ring.rotation_degrees.x = 90.0
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var travel := float(ring_index) / maxf(1.0, float(RETURN_PORTAL_TUNNEL_RING_COUNT))
		ring.position.z = lerpf(-RETURN_PORTAL_TUNNEL_DEPTH + 0.14, -0.08, travel)
		var radius := lerpf(
			RETURN_PORTAL_TUNNEL_BACK_RADIUS * 0.94,
			RETURN_PORTAL_TUNNEL_MOUTH_RADIUS * 0.98,
			travel
		)
		ring.scale = Vector3.ONE * radius
		depth_root.add_child(ring)
		depth_rings.append(ring)

	var depth_light := OmniLight3D.new()
	depth_light.name = "CrossingFlash"
	depth_light.light_color = primary_color
	depth_light.light_energy = 0.0
	depth_light.omni_range = 5.4
	depth_light.omni_attenuation = 2.1
	depth_light.shadow_enabled = false
	depth_light.position.z = -0.16
	depth_root.add_child(depth_light)
	depth_root.visible = true
	depth_root.scale = Vector3.ONE
	depth_parts["root"] = depth_root
	depth_parts["rings"] = depth_rings
	depth_parts["light"] = depth_light
	return depth_parts


func _update_return_portal_depth_effect(delta: float) -> void:
	if (
		_return_portal == null
		or not is_instance_valid(_return_portal)
		or _return_portal_depth_root == null
		or not is_instance_valid(_return_portal_depth_root)
	):
		return
	var open_amount := clampf(float(_return_portal.get("open_amount")), 0.0, 1.0)
	var open_scale := smoothstep(0.02, 0.78, open_amount)
	_return_portal_depth_root.visible = open_scale > 0.015
	_return_portal_depth_root.scale = Vector3(open_scale, open_scale, 1.0)
	var ring_count := _return_portal_depth_rings.size()
	for ring_index: int in range(ring_count):
		var ring := _return_portal_depth_rings[ring_index]
		if not is_instance_valid(ring):
			continue
		var ring_phase := fposmod(
			_return_portal_elapsed * RETURN_PORTAL_TUNNEL_FLOW_SPEED
			+ float(ring_index) / maxf(1.0, float(ring_count)),
			1.0
		)
		var travel := smoothstep(0.0, 1.0, ring_phase)
		ring.position.z = lerpf(
			-RETURN_PORTAL_TUNNEL_DEPTH + 0.14,
			-0.08,
			travel
		)
		var radius := lerpf(
			RETURN_PORTAL_TUNNEL_BACK_RADIUS * 0.94,
			RETURN_PORTAL_TUNNEL_MOUTH_RADIUS * 0.98,
			travel
		)
		ring.scale = Vector3.ONE * radius

	if (
		_cooldown_entry_started
		and not _return_portal_crossing_pulsed
		and _shark != null
		and is_instance_valid(_shark)
		and _shark.has_method("get_ghost_ride_debug_state")
	):
		var shark_state: Dictionary = _shark.call("get_ghost_ride_debug_state")
		if float(shark_state.get("portal_entry_progress", 0.0)) >= RETURN_PORTAL_CROSSING_PROGRESS:
			_return_portal_crossing_pulsed = true
			_return_portal_crossing_flash_elapsed = 0.0
			if game_state != null:
				game_state.camera_shake = maxf(
					game_state.camera_shake,
					RETURN_PORTAL_CROSSING_SHAKE
				)

	if _return_portal_crossing_flash_elapsed >= 0.0:
		_return_portal_crossing_flash_elapsed += delta
		var flash_progress := clampf(
			_return_portal_crossing_flash_elapsed / RETURN_PORTAL_CROSSING_FLASH_SECONDS,
			0.0,
			1.0
		)
		if _return_portal_depth_light != null and is_instance_valid(_return_portal_depth_light):
			_return_portal_depth_light.light_energy = sin(flash_progress * PI) * 3.2
		if flash_progress >= 1.0:
			_return_portal_crossing_flash_elapsed = -1.0
	else:
		if _return_portal_depth_light != null and is_instance_valid(_return_portal_depth_light):
			_return_portal_depth_light.light_energy = 0.0


func _update_cooldown(delta: float) -> void:
	_phase_timer = maxf(0.0, _phase_timer - delta)
	if _return_portal == null and _phase_timer <= RETURN_PORTAL_SEQUENCE_SECONDS:
		_spawn_return_portal()
	if _return_portal != null and is_instance_valid(_return_portal):
		_return_portal_elapsed = minf(
			RETURN_PORTAL_SEQUENCE_SECONDS,
			_return_portal_elapsed + delta
		)
		# Spawn時に確定したポータル姿勢を復帰完了まで保持する。
		# 生存プレイヤーやカメラが移動しても毎フレーム再計算しない。
		_update_return_portal_depth_effect(delta)
		if (
			not _cooldown_entry_started
			and _return_portal_elapsed >= RETURN_PORTAL_SHARK_REVEAL_SECONDS
		):
			_begin_shark_portal_reentry()
		if (
			_cooldown_entry_started
			and _shark != null
			and is_instance_valid(_shark)
			and _shark.is_ghost_hovering()
		):
			_return_tail_clear_elapsed = minf(
				RETURN_PORTAL_TAIL_CLEAR_HOLD_SECONDS,
				_return_tail_clear_elapsed + delta
			)
		if (
			not _return_portal_close_started
			and _return_tail_clear_elapsed >= RETURN_PORTAL_TAIL_CLEAR_HOLD_SECONDS
		):
			_return_portal_close_started = true
			_return_portal.call("close")
	elif not _cooldown_entry_started and _phase_timer <= ENTRY_SECONDS:
		# Keep the original authored return as a safe fallback if the preset fails.
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
	var portal_finished := _return_portal == null or not is_instance_valid(_return_portal)
	if not portal_finished:
		portal_finished = (
			_return_portal_close_started
			and float(_return_portal.get("open_amount")) <= RETURN_PORTAL_CLOSED_THRESHOLD
		)
	if (
		_phase_timer <= 0.0
		and _shark
		and _shark.is_ghost_hovering()
		and portal_finished
	):
		_cleanup_return_portal()
		_return_animation_locked = false
		if _result_departure_only:
			_cleanup_ghost_ride()
			return
		_update_progress_follow()
		_update_hover_target()
		phase = Phase.AIMING
		_show_aim_visuals()


func _begin_shark_portal_reentry() -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	_cooldown_entry_started = true
	var hover_target := _calculate_hover_target()
	var portal_center := (
		_return_portal.global_position
		if _return_portal != null and is_instance_valid(_return_portal)
		else hover_target
	)
	var travel_forward := portal_center.direction_to(hover_target)
	if travel_forward.length_squared() <= 0.0001:
		travel_forward = _return_portal_exit_direction
	var shark_start := portal_center - travel_forward * RETURN_PORTAL_SHARK_START_DEPTH
	if _shark.has_method("restart_ghost_hover_through_portal"):
		_shark.restart_ghost_hover_through_portal(
			shark_start,
			hover_target,
			_return_locked_aim_point,
			RETURN_PORTAL_CROSSING_PROGRESS
		)
	else:
		_shark.restart_ghost_hover(shark_start, hover_target, _return_locked_aim_point)


func _update_return_portal_transform() -> void:
	if _return_portal == null or not is_instance_valid(_return_portal):
		return
	var hover_target := _calculate_hover_target()
	if _return_portal_exit_direction.length_squared() <= 0.0001:
		_return_portal_exit_direction = _return_portal_exit_forward(hover_target)
	_return_portal.global_position = (
		hover_target
		+ Vector3.UP * RETURN_PORTAL_VERTICAL_OFFSET
		+ Vector3.RIGHT * _hover_side * RETURN_PORTAL_GRANDSTAND_OFFSET
		- _return_portal_exit_direction * RETURN_PORTAL_TAIL_DISTANCE
	)
	var travel_forward := _return_portal.global_position.direction_to(hover_target)
	travel_forward.y = 0.0
	if travel_forward.length_squared() > 0.0001:
		travel_forward = travel_forward.normalized()
		_return_portal_exit_direction = travel_forward
		# The portal plane and shark route share one strictly horizontal normal.
		# The mirrored yaw plus the outward offset keep the three-quarter view.
		_return_portal.look_at(
			_return_portal.global_position + travel_forward,
			Vector3.UP,
			true
		)


func _return_portal_exit_forward(hover_target: Vector3) -> Vector3:
	var toward_camera := _portal_toward_camera(hover_target)
	var mirror_sign := -1.0 if dead_player_index == 1 else 1.0
	var exit_forward := toward_camera.rotated(
		Vector3.UP,
		deg_to_rad(RETURN_PORTAL_VIEW_YAW_DEGREES * mirror_sign)
	)
	exit_forward.y = 0.0
	if exit_forward.length_squared() > 0.0001:
		return exit_forward.normalized()
	var toward_aim := _current_aim_point() - hover_target
	toward_aim.y = 0.0
	return toward_aim.normalized() if toward_aim.length_squared() > 0.0001 else Vector3.BACK


func _portal_toward_camera(world_position: Vector3) -> Vector3:
	if camera_controller != null:
		var camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
		if camera != null:
			var direction := camera.global_position - world_position
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				return direction.normalized()
	return Vector3.BACK


func _return_portal_path_alignment() -> float:
	if _return_portal == null or not is_instance_valid(_return_portal):
		return 0.0
	var travel_forward := _return_portal.global_position.direction_to(
		_calculate_hover_target()
	)
	if travel_forward.length_squared() <= 0.0001:
		return 0.0
	return _return_portal.global_basis.z.normalized().dot(travel_forward)


func _return_portal_view_angle_degrees() -> float:
	if _return_portal == null or not is_instance_valid(_return_portal):
		return 0.0
	var toward_camera := _portal_toward_camera(_return_portal.global_position)
	var portal_forward := _return_portal.global_basis.z.normalized()
	return rad_to_deg(acos(clampf(portal_forward.dot(toward_camera), -1.0, 1.0)))


func _cleanup_return_portal() -> void:
	if _return_portal != null and is_instance_valid(_return_portal):
		_cache_return_portal(dead_player_index, _return_portal)
	_return_portal = null
	_return_portal_surface_opaque = false
	_return_portal_exit_direction = Vector3.ZERO
	_return_portal_depth_root = null
	_return_portal_depth_rings.clear()
	_return_portal_depth_light = null
	_return_portal_crossing_pulsed = false
	_return_portal_crossing_flash_elapsed = -1.0


func _cache_return_portal(player_index: int, portal: Node3D) -> void:
	if portal == null or not is_instance_valid(portal):
		return
	var existing := _return_portal_cache.get(player_index) as Node3D
	if existing != null and is_instance_valid(existing) and existing != portal:
		portal.queue_free()
		return
	portal.name = "CachedGhostReturnPortalP%d" % player_index
	portal.visible = false
	portal.process_mode = Node.PROCESS_MODE_DISABLED
	portal.transform = Transform3D.IDENTITY
	portal.set("open_amount", 0.0)
	_return_portal_cache[player_index] = portal


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
	_aim_material.no_depth_test = false
	_aim_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_aim_material.disable_fog = true
	_aim_material.render_priority = 12

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
	_aim_outer_material.no_depth_test = false
	_aim_outer_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_aim_outer_material.disable_fog = true
	_aim_outer_material.render_priority = 12
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
	_hud_panel.custom_minimum_size = Vector2(HUD_PANEL_WIDTH, HUD_PANEL_HEIGHT)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud_layer.add_child(_hud_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 6)
	_hud_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	_hud_title = Label.new()
	_hud_title.name = "GhostRideTitle"
	_hud_title.add_theme_font_size_override("font_size", 18)
	_hud_title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hud_title.add_theme_constant_override("outline_size", 4)
	title_row.add_child(_hud_title)
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	_hud_combo = Label.new()
	_hud_combo.name = "GhostRideCombo"
	_hud_combo.add_theme_font_size_override("font_size", 18)
	_hud_combo.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22, 1.0))
	_hud_combo.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hud_combo.add_theme_constant_override("outline_size", 4)
	title_row.add_child(_hud_combo)
	_hud_controls = Label.new()
	_hud_controls.name = "GhostRideControls"
	_hud_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_controls.add_theme_font_size_override("font_size", 12)
	_hud_controls.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0, 1.0))
	_hud_controls.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	_hud_controls.add_theme_constant_override("outline_size", 3)
	vbox.add_child(_hud_controls)
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
	# The same ProgressBar node is used in both the compact HUD and the tutorial
	# close-up. These two slots only provide its two layouts.
	_charge_bar_home = Control.new()
	_charge_bar_home.name = "GhostChargeMeterHome"
	_charge_bar_home.custom_minimum_size = Vector2(0.0, 13.0)
	_charge_bar_home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_charge_bar_home)
	_charge_bar_home.add_child(_charge_bar)
	_charge_bar.custom_minimum_size = Vector2.ZERO
	_charge_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_charge_tutorial_overlay()
	_hide_aim_visuals()
	_hud_panel.visible = false


func _build_charge_tutorial_overlay() -> void:
	_charge_tutorial_overlay = Control.new()
	_charge_tutorial_overlay.name = "GhostChargeTutorialOverlay"
	_charge_tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_charge_tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_tutorial_overlay.visible = false
	_hud_layer.add_child(_charge_tutorial_overlay)

	_charge_tutorial_dim = ColorRect.new()
	_charge_tutorial_dim.name = "DimBackground"
	_charge_tutorial_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_charge_tutorial_dim.color = Color(0.015, 0.025, 0.065, 0.84)
	_charge_tutorial_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_tutorial_overlay.add_child(_charge_tutorial_dim)

	_charge_tutorial_panel = PanelContainer.new()
	_charge_tutorial_panel.name = "ChargeExplanationPanel"
	_charge_tutorial_panel.set_anchors_preset(Control.PRESET_CENTER)
	_charge_tutorial_panel.offset_left = -CHARGE_TUTORIAL_PANEL_SIZE.x * 0.5
	_charge_tutorial_panel.offset_top = -CHARGE_TUTORIAL_PANEL_SIZE.y * 0.5
	_charge_tutorial_panel.offset_right = CHARGE_TUTORIAL_PANEL_SIZE.x * 0.5
	_charge_tutorial_panel.offset_bottom = CHARGE_TUTORIAL_PANEL_SIZE.y * 0.5
	_charge_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.07, 0.15, 0.98)
	panel_style.border_color = Color(1.0, 0.86, 0.22, 0.96)
	panel_style.set_border_width_all(3)
	panel_style.corner_radius_top_left = 22
	panel_style.corner_radius_top_right = 22
	panel_style.corner_radius_bottom_left = 22
	panel_style.corner_radius_bottom_right = 22
	_charge_tutorial_panel.add_theme_stylebox_override("panel", panel_style)
	_charge_tutorial_overlay.add_child(_charge_tutorial_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 24)
	_charge_tutorial_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	margin.add_child(content)

	_charge_tutorial_title = Label.new()
	_charge_tutorial_title.name = "ChargeTutorialTitle"
	_charge_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_tutorial_title.add_theme_font_size_override("font_size", 30)
	_charge_tutorial_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.28))
	_charge_tutorial_title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_charge_tutorial_title.add_theme_constant_override("outline_size", 6)
	content.add_child(_charge_tutorial_title)

	var subtitle := Label.new()
	subtitle.text = "チャージバーを見ながら、強力な突進を狙おう"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	content.add_child(subtitle)

	_charge_tutorial_bar_slot = Control.new()
	_charge_tutorial_bar_slot.name = "EnlargedGhostChargeMeterSlot"
	_charge_tutorial_bar_slot.custom_minimum_size = Vector2(0.0, CHARGE_TUTORIAL_BAR_HEIGHT)
	_charge_tutorial_bar_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_charge_tutorial_bar_slot)

	var perfect_band := ColorRect.new()
	perfect_band.name = "PerfectBand"
	perfect_band.anchor_left = PERFECT_CHARGE_MIN
	perfect_band.anchor_top = 0.0
	perfect_band.anchor_right = PERFECT_CHARGE_MAX
	perfect_band.anchor_bottom = 1.0
	perfect_band.color = Color(1.0, 0.82, 0.12, 0.30)
	perfect_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_tutorial_bar_slot.add_child(perfect_band)
	var perfect_label := Label.new()
	perfect_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	perfect_label.text = "PERFECT"
	perfect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perfect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	perfect_label.add_theme_font_size_override("font_size", 15)
	perfect_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42))
	perfect_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	perfect_label.add_theme_constant_override("outline_size", 4)
	perfect_band.add_child(perfect_label)

	var scale_labels := HBoxContainer.new()
	content.add_child(scale_labels)
	for text_value: String in ["0%", "長押しでチャージ", "72〜94%でPERFECT", "100%"]:
		var scale_label := Label.new()
		scale_label.text = text_value
		scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scale_label.add_theme_font_size_override("font_size", 15)
		scale_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.28) if text_value.contains("PERFECT") else Color(0.70, 0.80, 0.94)
		)
		scale_labels.add_child(scale_label)

	_charge_tutorial_result = Label.new()
	_charge_tutorial_result.name = "ChargeTutorialDemoResult"
	_charge_tutorial_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_tutorial_result.add_theme_font_size_override("font_size", 20)
	_charge_tutorial_result.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_charge_tutorial_result.add_theme_constant_override("outline_size", 4)
	content.add_child(_charge_tutorial_result)

	_charge_tutorial_controls = Label.new()
	_charge_tutorial_controls.name = "ChargeTutorialControls"
	_charge_tutorial_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_tutorial_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_charge_tutorial_controls.add_theme_font_size_override("font_size", 21)
	_charge_tutorial_controls.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	content.add_child(_charge_tutorial_controls)

	var confirm := Label.new()
	confirm.text = "[ 任意のキー ]  説明を閉じて操作開始"
	confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.add_theme_color_override("font_color", Color(1.0, 0.88, 0.24))
	confirm.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	confirm.add_theme_constant_override("outline_size", 4)
	content.add_child(confirm)


func _should_show_charge_tutorial() -> bool:
	return (
		game_state != null
		and game_state.is_tutorial_ghost_practice()
		and game_state.get_tutorial_ghost_player() == dead_player_index
	)


func _start_charge_tutorial() -> void:
	if _charge_tutorial_overlay == null or _charge_tutorial_bar_slot == null:
		_show_aim_visuals()
		_start_hud_intro()
		return
	_attach_charge_bar_to_slot(_charge_tutorial_bar_slot)
	_set_meter(0.0, _player_color)
	_charge_tutorial_active = true
	_charge_tutorial_handoff_active = false
	_charge_tutorial_elapsed = 0.0
	_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.BUILDING
	_charge_tutorial_demo_index = 0
	_charge_tutorial_demo_value = 0.0
	_charge_tutorial_demo_travel = 0.0
	_charge_tutorial_demo_phase_elapsed = 0.0
	_charge_tutorial_handoff_elapsed = 0.0
	_charge_tutorial_handoff_waiting_layout = false
	_charge_tutorial_overlay.visible = true
	if _charge_tutorial_panel != null:
		_charge_tutorial_panel.visible = true
		_charge_tutorial_panel.modulate.a = 1.0
	if _charge_tutorial_dim != null:
		_charge_tutorial_dim.visible = true
		_charge_tutorial_dim.modulate.a = 1.0
	if _hud_panel != null:
		_hud_panel.visible = false
	_hide_aim_visuals()
	_charge_tutorial_title.text = "GHOST RIDER · P%d  チャージ操作" % dead_player_index
	var aim_keys := "WASD" if dead_player_index == 1 else "矢印キー"
	var charge_keys := "SPACE" if dead_player_index == 1 else "CTRL"
	_charge_tutorial_controls.text = (
		"① %sで照準を合わせる\n② %sを長押しして霊力をためる\n"
		+ "③ 黄色のPERFECT帯で離すと、最も強い突進！"
	) % [aim_keys, charge_keys]
	_update_charge_tutorial(0.0)


func _update_charge_tutorial(delta: float) -> void:
	if not _charge_tutorial_active or _charge_bar == null:
		return
	_charge_tutorial_elapsed += delta
	_charge_tutorial_demo_phase_elapsed += delta
	var target: float = CHARGE_TUTORIAL_DEMO_TARGETS[_charge_tutorial_demo_index]
	match _charge_tutorial_demo_phase:
		ChargeTutorialDemoPhase.BUILDING:
			var stop_travel: float = float(CHARGE_TUTORIAL_DEMO_WRAP_COUNT) + target
			_charge_tutorial_demo_travel = minf(
				stop_travel,
				_charge_tutorial_demo_travel + delta / CHARGE_BUILD_SECONDS
			)
			_charge_tutorial_demo_value = fposmod(_charge_tutorial_demo_travel, 1.0)
			if _charge_tutorial_demo_travel >= stop_travel:
				_charge_tutorial_demo_value = target
			_charge_bar.modulate = Color.WHITE
			_set_meter(
				_charge_tutorial_demo_value,
				_charge_feedback_color(_charge_tutorial_demo_value)
			)
			_set_charge_tutorial_result("長押し中…", Color(0.76, 0.85, 0.98))
			if _charge_tutorial_demo_travel >= stop_travel:
				_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.HOLDING
				_charge_tutorial_demo_phase_elapsed = 0.0
				_set_charge_tutorial_stop_result(target)
		ChargeTutorialDemoPhase.HOLDING:
			_set_meter(target, _charge_feedback_color(target))
			_set_charge_tutorial_stop_result(target)
			if _is_perfect_power(target):
				var blink_step := int(
					floor(_charge_tutorial_demo_phase_elapsed * CHARGE_TUTORIAL_PERFECT_BLINK_HZ * 2.0)
				)
				_charge_bar.modulate.a = 1.0 if blink_step % 2 == 0 else 0.28
			else:
				_charge_bar.modulate.a = 1.0
			if _charge_tutorial_demo_phase_elapsed >= CHARGE_TUTORIAL_DEMO_HOLD_SECONDS:
				_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.RESETTING
				_charge_tutorial_demo_phase_elapsed = 0.0
				_charge_bar.modulate.a = 1.0
		ChargeTutorialDemoPhase.RESETTING:
			var fade := clampf(
				_charge_tutorial_demo_phase_elapsed / CHARGE_TUTORIAL_DEMO_RESET_SECONDS,
				0.0,
				1.0
			)
			_charge_bar.modulate.a = 1.0 - fade
			_set_charge_tutorial_result("", Color(0.65, 0.74, 0.88))
			if _charge_tutorial_demo_phase_elapsed >= CHARGE_TUTORIAL_DEMO_RESET_SECONDS:
				_charge_tutorial_demo_index = (
					(_charge_tutorial_demo_index + 1) % CHARGE_TUTORIAL_DEMO_TARGETS.size()
				)
				_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.BUILDING
				_charge_tutorial_demo_phase_elapsed = 0.0
				_charge_tutorial_demo_value = 0.0
				_charge_tutorial_demo_travel = 0.0
				_charge_bar.modulate = Color.WHITE
				_set_meter(0.0, _player_color)


func _set_charge_tutorial_stop_result(target: float) -> void:
	var label_text: String = CHARGE_TUTORIAL_DEMO_LABELS[_charge_tutorial_demo_index]
	var label_color := Color(0.72, 0.84, 1.0)
	if _is_perfect_power(target):
		label_color = Color(1.0, 0.88, 0.22)
	elif target > PERFECT_CHARGE_MAX:
		label_color = Color(1.0, 0.38, 0.42)
	_set_charge_tutorial_result(label_text, label_color)


func _set_charge_tutorial_result(label_text: String, color: Color) -> void:
	if _charge_tutorial_result == null:
		return
	_charge_tutorial_result.text = label_text
	_charge_tutorial_result.add_theme_color_override("font_color", color)


func _attach_charge_bar_to_slot(slot: Control) -> void:
	if _charge_bar == null or slot == null:
		return
	var current_parent := _charge_bar.get_parent()
	if current_parent != slot:
		if current_parent != null:
			current_parent.remove_child(_charge_bar)
		slot.add_child(_charge_bar)
	# Keep the real meter behind the tutorial-only PERFECT marker.
	slot.move_child(_charge_bar, 0)
	_charge_bar.custom_minimum_size = Vector2.ZERO
	_charge_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _restore_charge_bar_home() -> void:
	if _charge_bar == null or _charge_bar_home == null:
		return
	_attach_charge_bar_to_slot(_charge_bar_home)


func _start_charge_tutorial_handoff() -> void:
	if _charge_bar == null or _charge_bar_home == null or _charge_tutorial_overlay == null:
		_charge_tutorial_active = false
		_restore_charge_bar_home()
		_show_aim_visuals()
		_start_hud_intro()
		return
	_charge_tutorial_active = false
	_charge_tutorial_handoff_active = true
	_charge_tutorial_handoff_elapsed = 0.0
	_charge_tutorial_handoff_waiting_layout = true

	# 移動先となる本編HUDを最終位置に配置（まだ非表示）
	_hud_slide_active = false
	_hud_slide_elapsed = HUD_SLIDE_SECONDS
	if _hud_panel != null:
		_hud_panel.visible = true
		_hud_panel.modulate.a = 0.0
		_layout_hud(1.0)
	_update_hud("")
	# Container children receive their final sizes at the end of the frame. Keep
	# the explanation visible until GhostChargeMeterHome has a real destination.
	_charge_bar.modulate = Color.WHITE


func _begin_charge_tutorial_handoff_motion() -> void:
	_charge_tutorial_handoff_waiting_layout = false

	# The animated object is the real GhostChargeMeter. The destination is its
	# persistent home slot, so the final rectangle matches the compact HUD exactly.
	_charge_tutorial_handoff_from = _charge_bar.get_global_rect()
	_charge_tutorial_handoff_to = _charge_bar_home.get_global_rect()
	var overlay_origin := _charge_tutorial_overlay.get_global_rect().position
	var current_parent := _charge_bar.get_parent()
	if current_parent != null:
		current_parent.remove_child(_charge_bar)
	_charge_tutorial_overlay.add_child(_charge_bar)
	_charge_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_charge_bar.position = _charge_tutorial_handoff_from.position - overlay_origin
	_charge_bar.size = _charge_tutorial_handoff_from.size
	if _charge_tutorial_panel != null:
		_charge_tutorial_panel.visible = false
	_charge_bar.visible = true
	_charge_bar.modulate = Color.WHITE
	_apply_charge_tutorial_handoff(0.0)


func _update_charge_tutorial_handoff(delta: float) -> void:
	if not _charge_tutorial_handoff_active:
		return
	if _charge_tutorial_handoff_waiting_layout:
		if _charge_bar_home == null or _charge_bar_home.size.x <= 0.0 or _charge_bar_home.size.y <= 0.0:
			return
		_begin_charge_tutorial_handoff_motion()
		return
	_charge_tutorial_handoff_elapsed = minf(
		CHARGE_TUTORIAL_HANDOFF_SECONDS,
		_charge_tutorial_handoff_elapsed + delta
	)
	var progress := clampf(
		_charge_tutorial_handoff_elapsed / CHARGE_TUTORIAL_HANDOFF_SECONDS,
		0.0,
		1.0
	)
	var weight := 1.0 - pow(1.0 - progress, 3.0)
	_apply_charge_tutorial_handoff(weight)
	if _charge_tutorial_handoff_elapsed >= CHARGE_TUTORIAL_HANDOFF_SECONDS:
		_finish_charge_tutorial_handoff()


func _apply_charge_tutorial_handoff(weight: float) -> void:
	if _charge_bar == null or _charge_tutorial_overlay == null:
		return
	var overlay_origin := _charge_tutorial_overlay.get_global_rect().position
	var from_rect := _charge_tutorial_handoff_from
	var to_rect := _charge_tutorial_handoff_to
	var rect := Rect2(
		from_rect.position.lerp(to_rect.position, weight),
		from_rect.size.lerp(to_rect.size, weight)
	)
	_charge_bar.position = rect.position - overlay_origin
	_charge_bar.size = rect.size
	# The real bar stays fully visible while it shrinks directly into its HUD slot.
	_charge_bar.modulate = Color.WHITE
	if _charge_tutorial_dim != null:
		_charge_tutorial_dim.modulate.a = 1.0 - weight
	if _hud_panel != null:
		_hud_panel.modulate.a = clampf((weight - 0.55) / 0.45, 0.0, 1.0)


func _finish_charge_tutorial_handoff() -> void:
	_charge_tutorial_handoff_active = false
	_charge_tutorial_active = false
	_charge_tutorial_elapsed = 0.0
	_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.BUILDING
	_charge_tutorial_demo_index = 0
	_charge_tutorial_demo_value = 0.0
	_charge_tutorial_demo_travel = 0.0
	_charge_tutorial_demo_phase_elapsed = 0.0
	_charge_tutorial_handoff_elapsed = 0.0
	_charge_tutorial_handoff_waiting_layout = false
	_restore_charge_bar_home()
	if _charge_bar != null:
		_charge_bar.visible = true
		_charge_bar.modulate = Color.WHITE
	if _charge_tutorial_overlay != null:
		_charge_tutorial_overlay.visible = false
	if _charge_tutorial_panel != null:
		_charge_tutorial_panel.visible = true
		_charge_tutorial_panel.modulate.a = 1.0
	if _charge_tutorial_dim != null:
		_charge_tutorial_dim.modulate.a = 1.0
	_show_aim_visuals()
	if _hud_panel != null:
		_hud_panel.visible = true
		_hud_panel.modulate.a = 1.0
		_hud_slide_active = false
		_hud_slide_elapsed = HUD_SLIDE_SECONDS
		_layout_hud(1.0)
	_set_meter(0.0, _player_color)
	_update_hud("")


func _start_hud_intro() -> void:
	if _hud_panel == null:
		return
	_hud_slide_elapsed = 0.0
	_hud_slide_active = true
	_hud_panel.visible = true
	_update_hud("")


func _update_hud_animation(delta: float) -> void:
	if _hud_panel == null or not _hud_panel.visible or phase == Phase.INACTIVE:
		return
	if _hud_slide_active:
		_hud_slide_elapsed = minf(HUD_SLIDE_SECONDS, _hud_slide_elapsed + delta)
		if _hud_slide_elapsed >= HUD_SLIDE_SECONDS:
			_hud_slide_active = false
	_layout_hud(_hud_slide_weight())


func _hud_slide_weight() -> float:
	if not _hud_slide_active:
		return 1.0
	var progress := clampf(_hud_slide_elapsed / HUD_SLIDE_SECONDS, 0.0, 1.0)
	return 1.0 - pow(1.0 - progress, 3.0)


func _layout_hud(slide_weight: float) -> void:
	if _hud_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := minf(
		HUD_PANEL_WIDTH,
		maxf(240.0, viewport_size.x - HUD_EDGE_MARGIN * 2.0)
	)
	var target_x := (
		HUD_EDGE_MARGIN
		if dead_player_index == 1
		else maxf(HUD_EDGE_MARGIN, viewport_size.x - panel_width - HUD_EDGE_MARGIN)
	)
	var hidden_x := (
		-panel_width - HUD_EDGE_MARGIN
		if dead_player_index == 1
		else viewport_size.x + HUD_EDGE_MARGIN
	)
	_hud_panel.position = Vector2(
		lerpf(hidden_x, target_x, slide_weight),
		maxf(HUD_EDGE_MARGIN, viewport_size.y - HUD_PANEL_HEIGHT - HUD_BOTTOM_MARGIN)
	)
	_hud_panel.size = Vector2(panel_width, HUD_PANEL_HEIGHT)
	_hud_panel.modulate.a = slide_weight


func _show_aim_visuals() -> void:
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
	if _aim_ring:
		_aim_ring.visible = false
	if _aim_outer_ring:
		_aim_outer_ring.visible = false


func _update_aim_visuals(blink: bool) -> void:
	if _shark == null or not is_instance_valid(_shark):
		return
	var aim_point := _current_aim_point()
	var visible_now := not blink or int(Time.get_ticks_msec() / 90.0) % 2 == 0
	var display_power := _last_charge_power if phase == Phase.WINDUP else _charge_amount
	var effect_color := _charge_feedback_color(display_power) if _charging_input or phase == Phase.WINDUP else _player_color
	_set_aim_color(effect_color)
	_aim_ring.visible = visible_now
	_aim_outer_ring.visible = visible_now
	_aim_ring.global_position = Vector3(aim_point.x, StageConstants.FLOOR_TOP_Y + 0.035, aim_point.z)
	_aim_ring.rotation = Vector3.ZERO
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * (0.04 + display_power * 0.07)
	_aim_ring.scale = Vector3.ONE * (pulse + display_power * 0.18)
	_aim_outer_ring.global_position = Vector3(aim_point.x, StageConstants.FLOOR_TOP_Y + 0.05, aim_point.z)
	_aim_outer_ring.rotation = Vector3.ZERO
	_aim_outer_ring.scale = Vector3.ONE * (1.0 + display_power * 0.42 - sin(Time.get_ticks_msec() * 0.009) * 0.08)


func _update_hud(_status: String) -> void:
	if _hud_panel == null:
		return
	if _result_departure_only:
		_hud_panel.visible = false
		return
	if phase not in [Phase.AIMING, Phase.WINDUP, Phase.CHARGING, Phase.COOLDOWN]:
		_hud_panel.visible = false
		return
	_hud_panel.visible = true
	_hud_title.text = "GHOST RIDER · P%d" % dead_player_index
	_hud_combo.text = "HAUNT x%d" % _combo if _combo > 0 else ""
	_hud_controls.text = (
		"WASD 照準  |  SPACE 長押し→離して発射"
		if dead_player_index == 1
		else "←↑↓→ 照準  |  CTRL 長押し→離して発射"
	)
	_layout_hud(_hud_slide_weight())


func _apply_player_aim_color() -> void:
	if _aim_material == null:
		return
	_player_color = Color(0.95, 0.55, 0.20, 1.0) if dead_player_index == 1 else Color(0.20, 0.65, 0.90, 1.0)
	_set_aim_color(_player_color)
	if _hud_title:
		_hud_title.add_theme_color_override("font_color", _player_color)


func _set_aim_color(color: Color) -> void:
	var ring_color := Color(
		color.r * AIM_VISUAL_DARKEN_FACTOR,
		color.g * AIM_VISUAL_DARKEN_FACTOR,
		color.b * AIM_VISUAL_DARKEN_FACTOR,
		color.a
	)
	if _aim_material:
		_aim_material.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.68)
		_aim_material.emission = Color(ring_color.r, ring_color.g, ring_color.b, 1.0)
		_aim_material.emission_energy_multiplier = 2.1
	if _aim_outer_material:
		_aim_outer_material.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.30)
		_aim_outer_material.emission = Color(ring_color.r, ring_color.g, ring_color.b, 1.0)
		_aim_outer_material.emission_energy_multiplier = 1.6


func _set_meter(progress: float, color: Color) -> void:
	if _charge_bar:
		_charge_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	if _charge_fill_style:
		_charge_fill_style.bg_color = Color(color.r, color.g, color.b, 0.96)


func _cleanup_ghost_ride() -> void:
	_clear_ghost_emote()
	_hide_aim_visuals()
	_charge_tutorial_active = false
	_charge_tutorial_handoff_active = false
	_charge_tutorial_elapsed = 0.0
	_charge_tutorial_demo_phase = ChargeTutorialDemoPhase.BUILDING
	_charge_tutorial_demo_index = 0
	_charge_tutorial_demo_value = 0.0
	_charge_tutorial_demo_travel = 0.0
	_charge_tutorial_demo_phase_elapsed = 0.0
	_charge_tutorial_handoff_elapsed = 0.0
	_charge_tutorial_handoff_waiting_layout = false
	if _charge_tutorial_overlay != null:
		_charge_tutorial_overlay.visible = false
	_restore_charge_bar_home()
	if _charge_bar != null:
		_charge_bar.visible = true
		_charge_bar.modulate = Color.WHITE
	if _charge_tutorial_panel != null:
		_charge_tutorial_panel.visible = true
		_charge_tutorial_panel.modulate.a = 1.0
	if _charge_tutorial_dim != null:
		_charge_tutorial_dim.modulate.a = 1.0
	if _hud_panel:
		_hud_panel.visible = false
		_hud_panel.modulate.a = 1.0
	_cleanup_return_portal()
	if _shark and is_instance_valid(_shark):
		if _shark.ghost_charge_finished.is_connected(_on_shark_charge_finished):
			_shark.ghost_charge_finished.disconnect(_on_shark_charge_finished)
		if _shark.ghost_mount_beam_fired.is_connected(_on_ghost_mount_beam_fired):
			_shark.ghost_mount_beam_fired.disconnect(_on_ghost_mount_beam_fired)
		_shark.end_ghost_ride()
	if _rider != null and is_instance_valid(_rider):
		_rider.queue_free()
	_rider = null
	_rider_revealed_to_main = false
	_shark = null
	phase = Phase.INACTIVE
	dead_player_index = 0
	survivor_player_index = 0
	_phase_timer = 0.0
	_sequence_elapsed = 0.0
	_ghost_rendezvous_released = false
	_ghost_reveal_beams_started = false
	_presentation_follow_anchor_z = 0.0
	_presentation_follow_initialized = false
	_soul_travel_elapsed = 0.0
	_hud_slide_elapsed = 0.0
	_hud_slide_active = false
	_aim_offset = Vector2.ZERO
	_aim_origin = Vector3.ZERO
	_fixed_hover_target = Vector3.ZERO
	_hover_progress_offset_z = 0.0
	_locked_direction = Vector3.ZERO
	_hover_side = 1.0
	_soul_start_position = Vector3.ZERO
	_soul_rise_position = Vector3.ZERO
	_soul_control_a = Vector3.ZERO
	_soul_control_b = Vector3.ZERO
	_rendezvous_position = Vector3.ZERO
	_presentation_focus = Vector3.ZERO
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
	_ghost_emote_id = 0
	_return_portal_elapsed = 0.0
	_return_tail_clear_elapsed = 0.0
	_return_portal_close_started = false
	_return_portal_surface_opaque = false
	_return_animation_locked = false
	_result_departure_only = false
	_return_locked_hover_target = Vector3.ZERO
	_return_locked_aim_point = Vector3.ZERO
	_preferred_ocean_sharks.clear()
