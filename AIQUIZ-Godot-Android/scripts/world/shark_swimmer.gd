class_name SharkSwimmer
extends Node3D

signal attack_reached(player_index: int)
signal attack_phase_changed(player_index: int, attack_phase: int)
signal ghost_charge_finished()
signal ghost_mount_beam_fired(beam_index: int)

## AIQUIZ-UE から移植したサメを、通常時は滑らかに回遊させ、
## 落水時はステージを避ける経路でプレイヤーへ急行させる。
@export var orbit_radius: Vector2 = Vector2(14.0, 28.0)
@export var swim_speed: float = 0.28
@export var phase: float = 0.0
@export var depth_wave: float = 0.35
@export var animation_speed: float = 1.0
@export var model_scale: float = 0.42
@export var ambient_acceleration: float = 7.5
@export var attack_speed: float = 38.0
@export var attack_acceleration: float = 62.0
@export var turn_response: float = 5.5
@export var bite_distance: float = 4.8

enum AttackPhase {
	AMBIENT,
	APPROACH,
	CHARGE,
	BITE,
	PORTAL_RESCUE,
}

enum AttackPortalPhase {
	NONE,
	OPENING,
	ENTERING,
	EXIT_OPENING,
	EXITING,
}

enum GhostRidePhase {
	NONE,
	RENDEZVOUS_ASCENT,
	RENDEZVOUS,
	MOUNTING,
	DEPARTING,
	ENTERING,
	PORTAL_ENTERING,
	HOVER,
	CHARGING,
	FINISHED,
}

@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer

const STAGE_CLEARANCE: float = 2.8
const UNDER_STAGE_CLEARANCE: float = 2.6
const ROUTE_SAMPLE_COUNT: int = 40
const ATTACK_CRUISE_Y: float = StageConstants.OCEAN_SURFACE_Y - 0.22
const VISIBILITY_EMISSION: Color = Color(0.10, 0.24, 0.30, 1.0)
const VISIBILITY_EMISSION_ENERGY: float = 0.60
const CHARGE_DISTANCE: float = 24.0
const BITE_LUNGE_DURATION: float = 0.40
const BITE_ANIMATION_BLEND_SECONDS: float = 0.06
const OCEAN_ATTACK_STUCK_SECONDS: float = 1.40
const OCEAN_ATTACK_PROGRESS_EPSILON: float = 0.50
const OCEAN_ATTACK_MAX_PORTAL_RESCUES: int = 2
const OCEAN_ATTACK_PORTAL_OPEN_SECONDS: float = 0.38
const OCEAN_ATTACK_PORTAL_ENTER_SECONDS: float = 0.30
const OCEAN_ATTACK_PORTAL_EXIT_OPEN_SECONDS: float = 0.46
const OCEAN_ATTACK_PORTAL_EXIT_SECONDS: float = 0.62
const OCEAN_ATTACK_PORTAL_CLOSE_SECONDS: float = 0.85
const OCEAN_ATTACK_PORTAL_OUTWARD_DISTANCE: float = 7.4
const OCEAN_ATTACK_PORTAL_DEPTH: float = 2.8
const OCEAN_ATTACK_PORTAL_SIZE := Vector2(4.2, 4.2)
const JAW_OPEN_DEGREES: float = 28.0
const WAKE_OFFSET_SCALE: float = 4.35
const GHOST_RIDE_SCALE_MULTIPLIER: float = 0.62
const GHOST_ENTRY_DURATION: float = 2.4
const GHOST_PORTAL_ENTRY_DURATION: float = 2.25
const GHOST_PORTAL_ENTRY_START_SCALE: float = 1.0
const GHOST_RENDEZVOUS_ASCENT_DURATION: float = 2.45
const GHOST_RENDEZVOUS_DEPTH: float = 4.2
const GHOST_DEPARTURE_DURATION: float = 2.45
const GHOST_ENTRY_START_SCALE: float = 0.74
const GHOST_ENTRY_SCALE_PULSE: float = 0.18
const GHOST_ENTRY_BREACH_PROGRESS: float = 0.40
const GHOST_BREACH_RING_DURATION: float = 0.92
const GHOST_AURA_COLOR: Color = Color(0.24, 0.86, 1.0, 1.0)
const GHOST_MOUNT_BEAM_P1_SCENE: PackedScene = preload(
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_06.tscn"
)
const GHOST_MOUNT_BEAM_P2_SCENE: PackedScene = preload(
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_02.tscn"
)
const OCEAN_ATTACK_PORTAL_P1_SCENE: PackedScene = preload(
	"res://assets/BinbunVFX/portal_vfx/effects/portal/portal_vfx_01.tscn"
)
const OCEAN_ATTACK_PORTAL_P2_SCENE: PackedScene = preload(
	"res://assets/BinbunVFX/portal_vfx/effects/portal/portal_vfx_04.tscn"
)
const GHOST_MOUNT_BEAM_HEIGHT: float = 28.0
const GHOST_MOUNT_BEAM_ROOT_ABOVE_OCEAN: float = 0.18
const GHOST_MOUNT_BEAM_ASCENT_HEIGHT: float = 4.2
const GHOST_MOUNT_BEAM_COUNT: int = 1
const GHOST_MOUNT_BEAM_RENDER_LAYER: int = 19
# One oversized vertical pillar fires while the mounted shark remains planted.
# It closes completely, then the camera vibration is allowed to decay before
# the shark begins its ascent.
const GHOST_MOUNT_BEAM_RADIUS: float = 1.40
const GHOST_MOUNT_BEAM_START_RADIUS: float = GHOST_MOUNT_BEAM_RADIUS * 1.5
const GHOST_MOUNT_BEAM_START_DELAY: float = 0.20
const GHOST_MOUNT_BEAM_OPEN_DURATION: float = 0.34
const GHOST_MOUNT_BEAM_FORMATION_DURATION: float = (
	GHOST_MOUNT_BEAM_START_DELAY
	+ GHOST_MOUNT_BEAM_OPEN_DURATION
)
const GHOST_MOUNT_BEAM_POWER_HOLD: float = 1.05
const GHOST_MOUNT_BEAM_CLOSE_DURATION: float = 0.24
const GHOST_MOUNT_BEAM_VIBRATION_SETTLE: float = 0.36
const GHOST_MOUNT_BEAM_SHUTDOWN_TIME: float = (
	GHOST_MOUNT_BEAM_FORMATION_DURATION
	+ GHOST_MOUNT_BEAM_POWER_HOLD
)
const GHOST_MOUNT_BEAM_OFF_TIME: float = (
	GHOST_MOUNT_BEAM_SHUTDOWN_TIME
	+ GHOST_MOUNT_BEAM_CLOSE_DURATION
)
const GHOST_MOUNT_BEAM_ASCENT_START_TIME: float = (
	GHOST_MOUNT_BEAM_OFF_TIME
	+ GHOST_MOUNT_BEAM_VIBRATION_SETTLE
)
const GHOST_MOUNT_BEAM_ASCENT_DURATION: float = 1.40
const GHOST_MOUNT_BEAM_SEQUENCE_DURATION: float = (
	GHOST_MOUNT_BEAM_ASCENT_START_TIME
	+ GHOST_MOUNT_BEAM_ASCENT_DURATION
)
const GHOST_MOUNT_BEAM_ASCENT_EXIT_SPEED: float = (
	GHOST_MOUNT_BEAM_ASCENT_HEIGHT * 1.22
	/ GHOST_MOUNT_BEAM_ASCENT_DURATION
)
const GHOST_MOUNT_VERTICAL_TURN_END: float = 0.34
# 問題壁越しのシルエットはプレイヤーテーマ色より少し暗くし、
# 壁や問題文より前に出すぎないようにする。
const GHOST_SILHOUETTE_P1_COLOR: Color = Color(0.779, 0.451, 0.164, 0.68)
const GHOST_SILHOUETTE_P2_COLOR: Color = Color(0.164, 0.533, 0.738, 0.68)
const GHOST_SILHOUETTE_EMISSION_ENERGY: float = 2.2
const GHOST_MOUNT_SETTLE_DURATION: float = 0.85
const GHOST_RIDER_SOCKET_YAW_CORRECTION: float = PI
const GHOST_RIDER_MOUNT_LIFT: float = 0.16
const GHOST_AIM_TURN_RESPONSE: float = 3.0
const GHOST_RENDEZVOUS_ANIMATION_SPEED: float = 0.62
const GHOST_MOUNT_ANIMATION_SPEED: float = 0.72
const GHOST_HOVER_ANIMATION_SPEED: float = 0.82
const SHARK_SWIM_ANIMATION := &"SharkSwim"
const SHARK_BITE_ANIMATION := &"SharkBite"
const GHOST_RENDEZVOUS_ANIMATION := &"GhostRendezvousIdle"
const GHOST_MOUNT_RECEIVE_ANIMATION := &"GhostMountReceive"
const GHOST_DEPARTURE_ANIMATION := &"GhostDeparture"

var is_attacking: bool = false
var is_ghost_ridden: bool = false
var attack_route_kind: String = "ambient"

var _center: Vector3 = Vector3.ZERO
var _angle: float = 0.0
var _swim_time: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _bank: float = 0.0

var _attack_player_index: int = 0
var _attack_target: Vector3 = Vector3.ZERO
var _attack_waypoints: Array[Vector3] = []
var _attack_route_snapshot: PackedVector3Array = PackedVector3Array()
var _floor_center_z: float = StageConstants.GAME_FLOOR_CENTER_Z
var _floor_length: float = StageConstants.GAME_FLOOR_LENGTH
var _attack_phase: int = AttackPhase.AMBIENT
var _attack_intensity: float = 0.0
var _bite_timer: float = 0.0
var _jaw_open_amount: float = 0.0
var _attack_best_waypoint_distance: float = INF
var _attack_stuck_elapsed: float = 0.0
var _attack_portal_rescue_count: int = 0
var _attack_portal_phase: int = AttackPortalPhase.NONE
var _attack_portal_elapsed: float = 0.0
var _attack_entry_portal: Node3D = null
var _attack_exit_portal: Node3D = null
var _attack_portal_source_start: Vector3 = Vector3.ZERO
var _attack_portal_source_center: Vector3 = Vector3.ZERO
var _attack_portal_source_forward: Vector3 = Vector3.ZERO
var _attack_portal_exit_center: Vector3 = Vector3.ZERO
var _attack_portal_exit_start: Vector3 = Vector3.ZERO
var _attack_portal_exit_end: Vector3 = Vector3.ZERO
var _attack_portal_exit_forward: Vector3 = Vector3.ZERO
var _attack_portal_behind_direction: Vector3 = Vector3.ZERO
var _attack_portal_base_scale: Vector3 = Vector3.ONE
var _jaw_skeleton: Skeleton3D = null
var _jaw_bone_index: int = -1
var _jaw_rest_rotation: Quaternion = Quaternion.IDENTITY
var _wake_particles: GPUParticles3D = null
var _surface_spray: GPUParticles3D = null
var _rush_audio: AudioStreamPlayer3D = null
var _impact_audio: AudioStreamPlayer3D = null
var _ghost_breach_particles: GPUParticles3D = null
var _ghost_aura_particles: GPUParticles3D = null
var _ghost_breach_ring: MeshInstance3D = null
var _ghost_breach_ring_material: StandardMaterial3D = null
var _ghost_phase: int = GhostRidePhase.NONE
var _ghost_player_index: int = 0
var _ghost_hover_target: Vector3 = Vector3.ZERO
var _ghost_aim_point: Vector3 = Vector3.ZERO
var _ghost_entry_start: Vector3 = Vector3.ZERO
var _ghost_entry_breach_point: Vector3 = Vector3.ZERO
var _ghost_entry_control_a: Vector3 = Vector3.ZERO
var _ghost_entry_control_b: Vector3 = Vector3.ZERO
var _ghost_entry_elapsed: float = 0.0
var _ghost_entry_progress: float = 0.0
var _ghost_entry_side: float = 1.0
var _ghost_breach_triggered: bool = false
var _ghost_breach_ring_elapsed: float = -1.0
var _ghost_charge_direction: Vector3 = Vector3.ZERO
var _ghost_charge_speed: float = 0.0
var _ghost_charge_distance: float = 0.0
var _ghost_charge_max_distance: float = 0.0
var _ghost_mount: Node3D = null
var _ghost_mount_socket: Node3D = null
var _ghost_mount_base_position: Vector3 = Vector3.ZERO
var _ghost_rider: Node3D = null
var _ghost_rider_settle_start: Transform3D = Transform3D.IDENTITY
var _ghost_mount_settle_elapsed: float = 0.0
var _ghost_rendezvous_start: Vector3 = Vector3.ZERO
var _ghost_rendezvous_position: Vector3 = Vector3.ZERO
var _ghost_rendezvous_elapsed: float = 0.0
var _ghost_rendezvous_ascent_started: bool = false
var _ghost_departure_control_a: Vector3 = Vector3.ZERO
var _ghost_departure_control_b: Vector3 = Vector3.ZERO
var _ghost_original_scale: Vector3 = Vector3.ONE
var _ghost_base_scale: Vector3 = Vector3.ONE
var _ghost_charge_tension: float = 0.0
var _ghost_silhouette_material: StandardMaterial3D = null
var _ghost_silhouette_meshes: Array[MeshInstance3D] = []
var _ghost_silhouette_original_overlays: Dictionary = {}
var _ghost_silhouette_enabled: bool = false
var _ghost_silhouette_wall_occluded: bool = false
var _ghost_portal_stencil_originals: Dictionary = {}
var _ghost_portal_stencil_material_cache: Dictionary = {}
var _ghost_portal_stencil_active: bool = false
var _ghost_portal_stencil_surface_count: int = 0
var _ghost_portal_stencil_release_progress: float = 1.0
var _ghost_mount_beacons: Array[Node3D] = []
var _ghost_mount_beam_sequence_started: bool = false
var _ghost_mount_beam_shutdown_started: bool = false
var _ghost_mount_beam_elapsed: float = 0.0
var _ghost_mount_beam_ascent_start: Vector3 = Vector3.ZERO
var _ghost_mount_beam_ascent_start_quaternion: Quaternion = Quaternion.IDENTITY
var _ghost_mount_beam_cage_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	_center = position
	_angle = fposmod(phase, TAU)
	model.scale = Vector3.ONE * model_scale
	_apply_underwater_visibility()
	_setup_jaw_rig()
	_setup_attack_effects()
	# 元モデルは +X 向き。ルートノードの -Z 前方へ合わせる。
	model.rotation = Vector3(0.0, PI * 0.5, 0.0)
	_play_swim_animation()
	position = _orbit_position(_angle)
	var ahead_angle: float = _angle + _ambient_angle_step()
	var ahead: Vector3 = _orbit_position(ahead_angle)
	_velocity = position.direction_to(ahead) * _ambient_linear_speed()
	_update_orientation(1.0)


func _apply_underwater_visibility() -> void:
	var mesh_nodes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	for mesh_node: Node in mesh_nodes:
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		var surface_count: int = mesh_instance.get_surface_override_material_count()
		for surface_index: int in range(surface_count):
			var source_material: BaseMaterial3D = (
				mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			)
			if source_material == null:
				continue
			var visible_material: BaseMaterial3D = source_material.duplicate() as BaseMaterial3D
			if visible_material == null:
				continue
			visible_material.emission_enabled = true
			visible_material.emission = VISIBILITY_EMISSION
			visible_material.emission_energy_multiplier = VISIBILITY_EMISSION_ENERGY
			visible_material.roughness = minf(visible_material.roughness, 0.72)
			mesh_instance.set_surface_override_material(surface_index, visible_material)


func _create_ghost_silhouette_material() -> StandardMaterial3D:
	var silhouette_color := (
		GHOST_SILHOUETTE_P1_COLOR
		if _ghost_player_index == 1
		else GHOST_SILHOUETTE_P2_COLOR
	)
	var silhouette_material := StandardMaterial3D.new()
	silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silhouette_material.albedo_color = silhouette_color
	silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette_material.emission_enabled = true
	silhouette_material.emission = Color(
		silhouette_color.r,
		silhouette_color.g,
		silhouette_color.b,
		1.0
	)
	silhouette_material.emission_energy_multiplier = GHOST_SILHOUETTE_EMISSION_ENERGY
	silhouette_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	silhouette_material.depth_test = BaseMaterial3D.DEPTH_TEST_INVERTED
	silhouette_material.disable_fog = true
	silhouette_material.render_priority = 8
	return silhouette_material


func _register_ghost_silhouette_meshes(root: Node) -> void:
	if root == null:
		return
	if _ghost_silhouette_material == null:
		_ghost_silhouette_material = _create_ghost_silhouette_material()
	var mesh_nodes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		mesh_nodes.push_front(root)
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or _ghost_silhouette_original_overlays.has(mesh_instance):
			continue
		_ghost_silhouette_meshes.append(mesh_instance)
		_ghost_silhouette_original_overlays[mesh_instance] = mesh_instance.material_overlay
		if _ghost_silhouette_enabled:
			mesh_instance.material_overlay = _ghost_silhouette_material


func _update_ghost_occlusion_silhouette() -> void:
	# The inverted-depth pass reacts to ANY closer depth, including the ocean
	# surface. Keep it off while the shark body can still sit under/through the
	# water plane, otherwise the submerged mesh flashes as a transparent tint.
	var clear_of_ocean := (
		global_position.y >= StageConstants.OCEAN_SURFACE_Y + 1.6
	)
	var should_enable := (
		is_ghost_ridden
		and _ghost_silhouette_wall_occluded
		and clear_of_ocean
		and _ghost_phase in [
			GhostRidePhase.ENTERING,
			GhostRidePhase.HOVER,
			GhostRidePhase.CHARGING,
		]
	)
	if should_enable == _ghost_silhouette_enabled:
		return
	_ghost_silhouette_enabled = should_enable
	for mesh_instance: MeshInstance3D in _ghost_silhouette_meshes:
		if not is_instance_valid(mesh_instance):
			continue
		mesh_instance.material_overlay = (
			_ghost_silhouette_material
			if should_enable
			else _ghost_silhouette_original_overlays.get(mesh_instance) as Material
		)


func set_ghost_wall_occluded(is_occluded: bool) -> void:
	if _ghost_silhouette_wall_occluded == is_occluded:
		return
	_ghost_silhouette_wall_occluded = is_occluded
	_update_ghost_occlusion_silhouette()


func _clear_ghost_occlusion_silhouette() -> void:
	for mesh_instance: MeshInstance3D in _ghost_silhouette_meshes:
		if not is_instance_valid(mesh_instance):
			continue
		mesh_instance.material_overlay = (
			_ghost_silhouette_original_overlays.get(mesh_instance) as Material
		)
	_ghost_silhouette_meshes.clear()
	_ghost_silhouette_original_overlays.clear()
	_ghost_silhouette_material = null
	_ghost_silhouette_enabled = false
	_ghost_silhouette_wall_occluded = false


func _make_ghost_portal_stencil_material(
	source_material: BaseMaterial3D
) -> BaseMaterial3D:
	var cached_material := (
		_ghost_portal_stencil_material_cache.get(source_material) as BaseMaterial3D
	)
	if cached_material != null:
		return cached_material
	var stencil_material := source_material.duplicate() as BaseMaterial3D
	if stencil_material == null:
		return null
	stencil_material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	stencil_material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	stencil_material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_EQUAL
	stencil_material.stencil_reference = 1
	# Godot 4.6 requires stencil reads in the alpha queue. This material exists
	# only while the shark passes through the aperture; its authored appearance
	# is restored after the tail clears.
	stencil_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stencil_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	stencil_material.render_priority = maxi(stencil_material.render_priority, 1)
	_ghost_portal_stencil_material_cache[source_material] = stencil_material
	return stencil_material


## Binbun Portal VFXのStencilモードに合わせ、通過中だけサメと騎乗者を開口内に描画する。
func _set_ghost_portal_stencil_enabled(enabled: bool) -> void:
	if enabled:
		if not _ghost_portal_stencil_originals.is_empty():
			return
		_ghost_portal_stencil_surface_count = 0
		for mesh_instance: MeshInstance3D in _ghost_silhouette_meshes:
			if not is_instance_valid(mesh_instance):
				continue
			var original_entry: Dictionary = {
				"material_override": mesh_instance.material_override,
				"surface_overrides": [],
			}
			var source_override := mesh_instance.material_override as BaseMaterial3D
			if source_override != null:
				var stencil_override := _make_ghost_portal_stencil_material(source_override)
				if stencil_override != null:
					mesh_instance.material_override = stencil_override
					_ghost_portal_stencil_surface_count += 1
				_ghost_portal_stencil_originals[mesh_instance] = original_entry
				continue
			var original_surfaces: Array[Material] = []
			var surface_count := mesh_instance.get_surface_override_material_count()
			for surface_index: int in range(surface_count):
				original_surfaces.append(
					mesh_instance.get_surface_override_material(surface_index)
				)
				var source_material := (
					mesh_instance.get_active_material(surface_index) as BaseMaterial3D
				)
				if source_material == null:
					continue
				var stencil_material := _make_ghost_portal_stencil_material(source_material)
				if stencil_material == null:
					continue
				mesh_instance.set_surface_override_material(surface_index, stencil_material)
				_ghost_portal_stencil_surface_count += 1
			original_entry["surface_overrides"] = original_surfaces
			_ghost_portal_stencil_originals[mesh_instance] = original_entry
		_ghost_portal_stencil_active = _ghost_portal_stencil_surface_count > 0
		return

	for mesh_variant: Variant in _ghost_portal_stencil_originals:
		var mesh_instance := mesh_variant as MeshInstance3D
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var original_entry: Dictionary = _ghost_portal_stencil_originals[mesh_variant]
		mesh_instance.material_override = original_entry.get("material_override") as Material
		var surface_overrides_variant: Variant = original_entry.get("surface_overrides", [])
		if not (surface_overrides_variant is Array):
			continue
		var surface_overrides: Array = surface_overrides_variant
		var restore_count := mini(
			surface_overrides.size(),
			mesh_instance.get_surface_override_material_count()
		)
		for surface_index: int in range(restore_count):
			mesh_instance.set_surface_override_material(
				surface_index,
				surface_overrides[surface_index] as Material
			)
	_ghost_portal_stencil_originals.clear()
	_ghost_portal_stencil_active = false
	_ghost_portal_stencil_surface_count = 0


## 黒画面中に実際のサメ材質へポータル用Stencilパスを一度適用し、
## 初回のポータル通過時に発生する材質生成・描画パイプライン生成を先に済ませる。
## 移動・攻撃・ゴースト騎乗の状態は変更しない。
func begin_ghost_portal_render_prewarm() -> int:
	if is_attacking or is_ghost_ridden:
		return 0
	_register_ghost_silhouette_meshes(model)
	_set_ghost_portal_stencil_enabled(true)
	return _ghost_portal_stencil_surface_count


func end_ghost_portal_render_prewarm() -> void:
	if is_ghost_ridden:
		return
	_set_ghost_portal_stencil_enabled(false)
	_clear_ghost_occlusion_silhouette()


func _process(delta: float) -> void:
	_swim_time += delta
	if is_ghost_ridden:
		_update_ghost_ride(delta)
	elif is_attacking:
		_update_attack(delta)
	else:
		_update_ambient_swim(delta)
	if is_ghost_ridden and _ghost_phase == GhostRidePhase.RENDEZVOUS:
		_snap_to_ghost_aim_orientation()
	elif is_ghost_ridden and _ghost_phase in [
		GhostRidePhase.RENDEZVOUS_ASCENT,
		GhostRidePhase.HOVER,
	]:
		_update_ghost_aim_orientation(delta)
	elif (
		is_ghost_ridden
		and _ghost_phase == GhostRidePhase.MOUNTING
		and _ghost_mount_beam_sequence_started
	):
		# The post-mount beam ascent authors its own vertical orientation.
		pass
	elif is_ghost_ridden and _ghost_phase == GhostRidePhase.MOUNTING:
		_update_ghost_aim_orientation(delta)
	else:
		_update_orientation(delta)
	_update_ghost_mount_bob()
	_update_arcade_attack_effects(delta)
	_update_ghost_breach_effect(delta)
	_update_ghost_occlusion_silhouette()


func begin_attack(
	player_index: int,
	target_position: Vector3,
	floor_center_z: float,
	floor_length: float
) -> bool:
	if is_attacking or is_ghost_ridden:
		return false
	_cleanup_attack_rescue_portals(true)
	_attack_player_index = player_index
	_floor_center_z = floor_center_z
	_floor_length = floor_length
	_attack_target = _safe_attack_target(target_position)
	_build_attack_route(position, _attack_target)
	is_attacking = true
	_bite_timer = 0.0
	_attack_intensity = 0.0
	_jaw_open_amount = 0.0
	_attack_best_waypoint_distance = INF
	_attack_stuck_elapsed = 0.0
	_attack_portal_rescue_count = 0
	_attack_portal_phase = AttackPortalPhase.NONE
	_set_attack_phase(AttackPhase.APPROACH)
	animation_player.speed_scale = 1.75
	return true


func prepare_ghost_rendezvous(
	player_index: int,
	rendezvous_position: Vector3,
	aim_point: Vector3
) -> bool:
	if is_attacking or is_ghost_ridden:
		return false
	is_ghost_ridden = true
	_ghost_original_scale = scale
	_ghost_base_scale = _ghost_original_scale * GHOST_RIDE_SCALE_MULTIPLIER
	scale = _ghost_base_scale
	_ghost_player_index = player_index
	_register_ghost_silhouette_meshes(model)
	_ghost_phase = GhostRidePhase.RENDEZVOUS_ASCENT
	_ghost_rendezvous_position = rendezvous_position
	_ghost_rendezvous_start = rendezvous_position + Vector3.DOWN * GHOST_RENDEZVOUS_DEPTH
	_ghost_rendezvous_elapsed = 0.0
	_ghost_rendezvous_ascent_started = false
	_ghost_hover_target = rendezvous_position
	_ghost_aim_point = aim_point
	_ghost_entry_elapsed = 0.0
	_ghost_entry_progress = 0.0
	_ghost_breach_triggered = false
	_ghost_charge_distance = 0.0
	_ghost_charge_tension = 0.0
	position = _ghost_rendezvous_start
	_velocity = Vector3.ZERO
	visible = true
	_play_named_animation(
		GHOST_RENDEZVOUS_ANIMATION,
		true,
		GHOST_RENDEZVOUS_ANIMATION_SPEED
	)
	_ghost_mount_beam_sequence_started = false
	_ghost_mount_beam_shutdown_started = false
	_ghost_mount_beam_elapsed = 0.0
	_ghost_mount_beam_ascent_start = Vector3.ZERO
	_ghost_mount_beam_ascent_start_quaternion = Quaternion.IDENTITY
	_ghost_mount_beam_cage_center = Vector3.ZERO
	return true


func start_ghost_rendezvous_ascent() -> bool:
	if (
		not is_ghost_ridden
		or _ghost_phase != GhostRidePhase.RENDEZVOUS_ASCENT
		or _ghost_rendezvous_ascent_started
	):
		return false
	_ghost_rendezvous_ascent_started = true
	_ghost_rendezvous_elapsed = 0.0
	return true


func begin_ghost_ride(player_index: int, rider_visual: Node3D) -> bool:
	if is_attacking or rider_visual == null:
		return false
	if not is_ghost_ridden:
		if not prepare_ghost_rendezvous(player_index, position, position + Vector3.FORWARD):
			return false
	if _ghost_phase != GhostRidePhase.RENDEZVOUS or _ghost_player_index != player_index:
		return false
	_ghost_phase = GhostRidePhase.MOUNTING
	_ghost_mount_settle_elapsed = 0.0
	_ghost_mount = Node3D.new()
	_ghost_mount.name = "GhostRiderMount"
	add_child(_ghost_mount)
	_ghost_mount_socket = model.find_child("GhostMountSocket", true, false) as Node3D
	if _ghost_mount_socket != null:
		var socket_local := global_transform.affine_inverse() * _ghost_mount_socket.global_transform
		var corrected_socket_basis := (
			socket_local.basis.orthonormalized()
			* Basis.from_euler(Vector3(0.0, GHOST_RIDER_SOCKET_YAW_CORRECTION, 0.0))
		)
		_ghost_mount.transform = Transform3D(
			corrected_socket_basis,
			socket_local.origin + Vector3.UP * GHOST_RIDER_MOUNT_LIFT
		)
		_ghost_mount_base_position = _ghost_mount.position
	else:
		_ghost_mount_base_position = (
			_calculate_ghost_mount_position() + Vector3.UP * GHOST_RIDER_MOUNT_LIFT
		)
		_ghost_mount.position = _ghost_mount_base_position
	_ghost_mount.scale = Vector3.ONE
	rider_visual.reparent(_ghost_mount, true)
	_ghost_rider = rider_visual
	_register_ghost_silhouette_meshes(_ghost_rider)
	_ghost_rider_settle_start = rider_visual.transform
	_play_named_animation(
		GHOST_MOUNT_RECEIVE_ANIMATION,
		false,
		GHOST_MOUNT_ANIMATION_SPEED
	)
	return true


func start_ghost_reveal_beams() -> bool:
	if (
		not is_ghost_ridden
		or _ghost_phase != GhostRidePhase.MOUNTING
		or not is_ghost_mount_settled()
		or _ghost_mount_beam_sequence_started
	):
		return false
	_ghost_mount_beam_sequence_started = true
	_ghost_mount_beam_shutdown_started = false
	_ghost_mount_beam_elapsed = 0.0
	_ghost_mount_beam_ascent_start = position
	_ghost_mount_beam_ascent_start_quaternion = quaternion
	_ghost_mount_beam_cage_center = (
		get_ghost_mount_world_position()
		+ Vector3.UP * GHOST_MOUNT_BEAM_ASCENT_HEIGHT * 0.82
	)
	_start_ghost_mount_beacon_sequence()
	return true


func is_ghost_mount_settled() -> bool:
	return (
		is_ghost_ridden
		and _ghost_phase == GhostRidePhase.MOUNTING
		and _ghost_rider != null
		and is_instance_valid(_ghost_rider)
		and _ghost_mount_settle_elapsed >= GHOST_MOUNT_SETTLE_DURATION
	)


func is_ghost_reveal_beam_formation_complete() -> bool:
	return (
		_ghost_mount_beam_sequence_started
		and _ghost_mount_beam_elapsed >= GHOST_MOUNT_BEAM_FORMATION_DURATION
	)


func is_ghost_reveal_beam_firing() -> bool:
	return (
		_ghost_mount_beam_sequence_started
		and _ghost_mount_beam_elapsed >= GHOST_MOUNT_BEAM_START_DELAY
		and _ghost_mount_beam_elapsed < GHOST_MOUNT_BEAM_OFF_TIME
	)


func is_ghost_reveal_sequence_complete() -> bool:
	return (
		_ghost_mount_beam_sequence_started
		and _ghost_mount_beam_elapsed >= GHOST_MOUNT_BEAM_SEQUENCE_DURATION
	)


func _start_ghost_mount_beacon_sequence() -> void:
	_clear_ghost_mount_beacons()
	var formation_center := get_ghost_mount_world_position()
	var beam_origins := _get_ghost_mount_beacon_origins(formation_center)
	for beam_index in range(mini(GHOST_MOUNT_BEAM_COUNT, beam_origins.size())):
		var beam := _create_ghost_mount_beacon(
			beam_index,
			beam_origins[beam_index]
		)
		if beam == null:
			continue
		beam.set_meta("ghost_mount_beam_index", beam_index)
		_ghost_mount_beacons.append(beam)
		var beam_tween := create_tween().bind_node(beam)
		beam_tween.tween_interval(GHOST_MOUNT_BEAM_START_DELAY)
		beam_tween.tween_callback(
			_emit_ghost_mount_beam_fired.bind(beam_index)
		)
		beam_tween.tween_property(
			beam,
			"open_amount",
			1.0,
			GHOST_MOUNT_BEAM_OPEN_DURATION
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _emit_ghost_mount_beam_fired(beam_index: int) -> void:
	ghost_mount_beam_fired.emit(beam_index)


func _get_ghost_mount_beacon_origins(_formation_center: Vector3) -> Array[Vector3]:
	# The pillar marks the exact vertical path used by the shark's post-beam
	# ascent. Camera-relative presentation following keeps this axis on screen.
	var ocean_center := global_position
	ocean_center.y = (
		StageConstants.OCEAN_SURFACE_Y
		+ GHOST_MOUNT_BEAM_ROOT_ABOVE_OCEAN
	)
	return [ocean_center]


func translate_ghost_ride_presentation(offset: Vector3) -> bool:
	if not is_ghost_ridden or offset.is_zero_approx():
		return false
	position += offset
	_ghost_rendezvous_start += offset
	_ghost_rendezvous_position += offset
	_ghost_hover_target += offset
	_ghost_aim_point += offset
	if _ghost_mount_beam_sequence_started:
		_ghost_mount_beam_ascent_start += offset
		_ghost_mount_beam_cage_center += offset
		for beam: Node3D in _ghost_mount_beacons:
			if beam != null and is_instance_valid(beam):
				beam.global_position += offset
	return true


func _create_ghost_mount_beacon(beam_index: int, beam_origin: Vector3) -> Node3D:
	var beam_scene := (
		GHOST_MOUNT_BEAM_P1_SCENE
		if _ghost_player_index == 1
		else GHOST_MOUNT_BEAM_P2_SCENE
	)
	var beam := beam_scene.instantiate() as Node3D
	if beam == null:
		push_warning("Ghost mount beam scene could not be instantiated")
		return null
	beam.name = "GhostMountBeacon%02d" % (beam_index + 1)
	# The purchased presets keep shared embedded meshes and materials. Localize
	# only this gameplay instance before its controller enters the tree so the
	# extreme in-game dimensions never leak back into the template showcase.
	_localize_ghost_mount_beam_resources(beam)
	add_child(beam)
	_set_ghost_mount_beam_render_layer(beam)
	beam.top_level = true
	_set_ghost_mount_beacon_transform(beam, beam_index, beam_origin)
	beam.set_meta(
		"ghost_mount_beam_style",
		&"beam_06" if _ghost_player_index == 1 else &"beam_02"
	)
	beam.set("beam_length", GHOST_MOUNT_BEAM_HEIGHT)
	beam.set("beam_radius", GHOST_MOUNT_BEAM_RADIUS)
	beam.set("start_radius", GHOST_MOUNT_BEAM_START_RADIUS)
	beam.set("emission", 1.5) # 極太ビームだけ暗くする
	# Preserve each purchased preset's authored emission, pulse, particles, noise,
	# flares, and audio. Only the gameplay-required dimensions are overridden.
	beam.set("open_amount", 0.0)
	return beam


func _localize_ghost_mount_beam_resources(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			mesh_instance.mesh = mesh_instance.mesh.duplicate(true) as Mesh
		if mesh_instance.material_override != null:
			mesh_instance.material_override = (
				mesh_instance.material_override.duplicate(true) as Material
			)
	elif node is GPUParticles3D:
		var particles := node as GPUParticles3D
		if particles.material_override != null:
			particles.material_override = (
				particles.material_override.duplicate(true) as Material
			)
		if particles.process_material != null:
			particles.process_material = particles.process_material.duplicate(true)
		if particles.draw_pass_1 != null:
			particles.draw_pass_1 = particles.draw_pass_1.duplicate(true) as Mesh
	for child: Node in node.get_children():
		_localize_ghost_mount_beam_resources(child)


func _set_ghost_mount_beacon_transform(
	beam: Node3D,
	_beam_index: int,
	beam_origin: Vector3
) -> void:
	# Beam presets fire along local -Z. Forward is used as the roll reference so
	# the firing vector can be exactly vertical without an up-vector singularity.
	beam.global_transform = Transform3D(
		Basis.looking_at(Vector3.UP, Vector3.FORWARD),
		beam_origin
	)


func _set_ghost_mount_beam_render_layer(node: Node) -> void:
	if node is VisualInstance3D:
		var visual := node as VisualInstance3D
		visual.layers = 0
		visual.set_layer_mask_value(GHOST_MOUNT_BEAM_RENDER_LAYER, true)
	for child: Node in node.get_children():
		_set_ghost_mount_beam_render_layer(child)


func _stop_ghost_mount_beacon_sequence() -> void:
	var active_beams: Array[Node3D] = _ghost_mount_beacons.duplicate()
	for beam in active_beams:
		if beam == null or not is_instance_valid(beam):
			_ghost_mount_beacons.erase(beam)
			continue
		var beam_tween := create_tween().bind_node(beam)
		beam_tween.tween_property(
			beam,
			"open_amount",
			0.0,
			GHOST_MOUNT_BEAM_CLOSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		beam_tween.tween_callback(_finish_ghost_mount_beacon.bind(beam))


func _clear_ghost_mount_beacons() -> void:
	for beam in _ghost_mount_beacons:
		if beam != null and is_instance_valid(beam):
			beam.queue_free()
	_ghost_mount_beacons.clear()


func _finish_ghost_mount_beacon(beam: Node3D) -> void:
	_ghost_mount_beacons.erase(beam)
	if beam != null and is_instance_valid(beam):
		beam.queue_free()


func get_ghost_mount_world_position() -> Vector3:
	var authored_socket := model.find_child("GhostMountSocket", true, false) as Node3D
	if authored_socket != null:
		return authored_socket.global_position + Vector3.UP * GHOST_RIDER_MOUNT_LIFT
	return to_global(_calculate_ghost_mount_position() + Vector3.UP * GHOST_RIDER_MOUNT_LIFT)


func get_ghost_rendezvous_mount_world_position() -> Vector3:
	return get_ghost_mount_world_position() + (_ghost_rendezvous_position - position)


func set_ghost_hover_target(target_position: Vector3, aim_point: Vector3) -> void:
	if not is_ghost_ridden:
		return
	_ghost_hover_target = target_position
	_ghost_aim_point = aim_point


func set_ghost_charge_tension(amount: float) -> void:
	_ghost_charge_tension = clampf(amount, 0.0, 1.0)


func launch_ghost_charge(direction: Vector3, speed: float, max_distance: float) -> bool:
	if not is_ghost_ridden or _ghost_phase != GhostRidePhase.HOVER:
		return false
	# Keep the vertical component so the dash dives through the aim marker / player
	# instead of cruising above them at hover height.
	var charge_direction := direction.normalized()
	if charge_direction.length_squared() < 0.001:
		return false
	if Vector2(charge_direction.x, charge_direction.z).length_squared() < 0.001:
		return false
	_ghost_phase = GhostRidePhase.CHARGING
	_ghost_charge_direction = charge_direction
	_ghost_charge_speed = maxf(1.0, speed)
	_ghost_charge_max_distance = maxf(1.0, max_distance)
	_ghost_charge_distance = 0.0
	_ghost_charge_tension = 1.0
	_velocity = _ghost_charge_direction * _ghost_charge_speed
	quaternion = _quat_look_at(position, position + _ghost_charge_direction)
	_attack_intensity = 1.0
	animation_player.speed_scale = 2.35
	return true


func restart_ghost_hover(entry_position: Vector3, target_position: Vector3, aim_point: Vector3) -> void:
	if not is_ghost_ridden:
		return
	_set_ghost_portal_stencil_enabled(false)
	visible = true
	position = entry_position
	_ghost_entry_start = entry_position
	_ghost_hover_target = target_position
	_ghost_aim_point = aim_point
	_ghost_entry_elapsed = 0.0
	_ghost_entry_progress = 0.0
	_ghost_breach_triggered = false
	_ghost_breach_ring_elapsed = -1.0
	_ghost_phase = GhostRidePhase.ENTERING
	_ghost_charge_tension = 0.0
	_attack_intensity = 0.0
	scale = _ghost_base_scale * GHOST_ENTRY_START_SCALE
	_velocity = entry_position.direction_to(target_position) * 12.0
	_configure_ghost_entry_curve(entry_position, target_position)
	if _ghost_aura_particles != null:
		_ghost_aura_particles.emitting = true
		_ghost_aura_particles.amount_ratio = 0.28
	if _ghost_breach_ring != null:
		_ghost_breach_ring.visible = false
	_play_named_animation(GHOST_DEPARTURE_ANIMATION, false, 0.96)


## ポータルの奥から短く抜け、従来の海中再入場を使わず攻撃準備位置へ戻る。
func restart_ghost_hover_through_portal(
	entry_position: Vector3,
	target_position: Vector3,
	aim_point: Vector3,
	stencil_release_progress: float = 1.0
) -> void:
	if not is_ghost_ridden:
		return
	visible = true
	position = entry_position
	_ghost_entry_start = entry_position
	_ghost_hover_target = target_position
	_ghost_aim_point = aim_point
	_ghost_entry_elapsed = 0.0
	_ghost_entry_progress = 0.0
	_ghost_breach_triggered = false
	_ghost_breach_ring_elapsed = -1.0
	_ghost_phase = GhostRidePhase.PORTAL_ENTERING
	_ghost_portal_stencil_release_progress = clampf(
		stencil_release_progress,
		0.0,
		1.0
	)
	_update_ghost_occlusion_silhouette()
	_set_ghost_portal_stencil_enabled(true)
	_ghost_charge_tension = 0.0
	_attack_intensity = 0.28
	scale = _ghost_base_scale * GHOST_PORTAL_ENTRY_START_SCALE
	_velocity = entry_position.direction_to(target_position) * 13.0
	if _velocity.length_squared() > 0.001:
		quaternion = _quat_look_at(position, target_position)
	_bank = 0.0
	model.rotation = Vector3(0.0, PI * 0.5, 0.0)
	if _ghost_aura_particles != null:
		_ghost_aura_particles.emitting = false
		_ghost_aura_particles.amount_ratio = 0.0
	if _ghost_breach_ring != null:
		_ghost_breach_ring.visible = false
	_play_swim_animation()


func depart_ghost_rendezvous(
	target_position: Vector3,
	aim_point: Vector3
) -> bool:
	if not is_ghost_ridden or _ghost_phase != GhostRidePhase.MOUNTING:
		return false
	visible = true
	_ghost_entry_start = position
	_ghost_hover_target = target_position
	_ghost_aim_point = aim_point
	_ghost_entry_side = signf(_ghost_entry_start.x - target_position.x)
	if is_zero_approx(_ghost_entry_side):
		_ghost_entry_side = 1.0 if _ghost_player_index == 1 else -1.0
	_ghost_entry_elapsed = 0.0
	_ghost_entry_progress = 0.0
	_ghost_charge_tension = 0.0
	_attack_intensity = 0.08
	_ghost_phase = GhostRidePhase.DEPARTING
	_ghost_breach_triggered = false
	_ghost_breach_ring_elapsed = -1.0
	if _ghost_breach_ring != null:
		_ghost_breach_ring.visible = false
	scale = _ghost_base_scale
	var travel := target_position - _ghost_entry_start
	# Preserve the upward beam-reveal velocity at the phase boundary. Starting
	# both curves at zero made the shark visibly hang for one beat in mid-air.
	var departure_handoff_velocity := (
		Vector3.UP * GHOST_MOUNT_BEAM_ASCENT_EXIT_SPEED
	)
	_ghost_departure_control_a = (
		_ghost_entry_start
		+ departure_handoff_velocity * (GHOST_DEPARTURE_DURATION / 3.0)
	)
	_ghost_departure_control_b = (
		_ghost_entry_start
		+ travel * 0.76
		+ Vector3(_ghost_entry_side * 0.65, 3.65, -0.90)
	)
	_play_named_animation(GHOST_DEPARTURE_ANIMATION, false, 0.96)
	if _ghost_aura_particles != null:
		_ghost_aura_particles.emitting = true
		_ghost_aura_particles.amount_ratio = 0.24
	return true


func end_ghost_ride() -> void:
	if not is_ghost_ridden:
		return
	_set_ghost_portal_stencil_enabled(false)
	_clear_ghost_occlusion_silhouette()
	is_ghost_ridden = false
	scale = _ghost_original_scale
	visible = true
	_ghost_phase = GhostRidePhase.NONE
	_ghost_player_index = 0
	_ghost_charge_distance = 0.0
	_ghost_charge_max_distance = 0.0
	_ghost_charge_tension = 0.0
	_ghost_entry_progress = 0.0
	_ghost_breach_triggered = false
	_ghost_mount_beam_sequence_started = false
	_ghost_mount_beam_shutdown_started = false
	_ghost_mount_beam_elapsed = 0.0
	_ghost_mount_beam_ascent_start = Vector3.ZERO
	_ghost_mount_beam_ascent_start_quaternion = Quaternion.IDENTITY
	_ghost_mount_beam_cage_center = Vector3.ZERO
	_ghost_rendezvous_ascent_started = false
	_clear_ghost_mount_beacons()
	if _ghost_mount and is_instance_valid(_ghost_mount):
		_ghost_mount.queue_free()
	_ghost_mount = null
	_ghost_mount_socket = null
	_ghost_rider = null
	_ghost_mount_settle_elapsed = 0.0
	_ghost_rendezvous_start = Vector3.ZERO
	_ghost_rendezvous_position = Vector3.ZERO
	_ghost_rendezvous_elapsed = 0.0
	_ghost_departure_control_a = Vector3.ZERO
	_ghost_departure_control_b = Vector3.ZERO
	_play_swim_animation()
	if _ghost_aura_particles != null:
		_ghost_aura_particles.emitting = false
		_ghost_aura_particles.amount_ratio = 0.0
	if _ghost_breach_particles != null:
		_ghost_breach_particles.emitting = false
	if _ghost_breach_ring != null:
		_ghost_breach_ring.visible = false
	_ghost_breach_ring_elapsed = -1.0
	_reset_arcade_attack_effects()
	_recenter_ambient_path()


func is_available_for_ocean_attack() -> bool:
	return not is_attacking and not is_ghost_ridden


func is_ghost_hovering() -> bool:
	return is_ghost_ridden and _ghost_phase == GhostRidePhase.HOVER


func is_ghost_rendezvous_ready() -> bool:
	return is_ghost_ridden and _ghost_phase == GhostRidePhase.RENDEZVOUS


func get_ghost_ride_debug_state() -> Dictionary:
	return {
		"phase": GhostRidePhase.keys()[_ghost_phase],
		"position": global_position,
		"velocity": _velocity,
		"rendezvous": _ghost_rendezvous_position,
		"ascent_elapsed": _ghost_rendezvous_elapsed,
		"ascent_started": _ghost_rendezvous_ascent_started,
		"beam_sequence_started": _ghost_mount_beam_sequence_started,
		"beam_firing": is_ghost_reveal_beam_firing(),
		"beam_shutdown_started": _ghost_mount_beam_shutdown_started,
		"beam_count": _ghost_mount_beacons.size(),
		"beam_elapsed": _ghost_mount_beam_elapsed,
		"beam_formation_complete": is_ghost_reveal_beam_formation_complete(),
		"beam_sequence_complete": is_ghost_reveal_sequence_complete(),
		"portal_entry_progress": _ghost_entry_progress,
		"portal_stencil_active": _ghost_portal_stencil_active,
		"portal_stencil_surface_count": _ghost_portal_stencil_surface_count,
		"portal_stencil_cache_size": _ghost_portal_stencil_material_cache.size(),
		"portal_stencil_release_progress": _ghost_portal_stencil_release_progress,
		"forward": -global_basis.z.normalized(),
		"model_rotation": model.rotation,
		"animation": String(animation_player.current_animation),
		"animation_speed": animation_player.get_playing_speed(),
	}


func is_ghost_mounted() -> bool:
	return (
		is_ghost_ridden
		and (
			is_ghost_mount_settled()
			or _ghost_phase not in [
				GhostRidePhase.RENDEZVOUS_ASCENT,
				GhostRidePhase.RENDEZVOUS,
				GhostRidePhase.MOUNTING,
			]
		)
	)


func is_ghost_charging() -> bool:
	return is_ghost_ridden and _ghost_phase == GhostRidePhase.CHARGING


func play_ghost_impact() -> void:
	if _impact_audio:
		_impact_audio.pitch_scale = randf_range(0.96, 1.05)
		_impact_audio.play()
	if _surface_spray:
		_surface_spray.restart()


func set_attack_target(target_position: Vector3) -> void:
	if not is_attacking:
		return
	_attack_target = _safe_attack_target(target_position)
	if not _attack_waypoints.is_empty():
		_attack_waypoints[_attack_waypoints.size() - 1] = _attack_target
	if not _attack_route_snapshot.is_empty():
		_attack_route_snapshot[_attack_route_snapshot.size() - 1] = _attack_target


func cancel_attack() -> void:
	if not is_attacking:
		return
	_set_attack_phase(AttackPhase.AMBIENT)
	is_attacking = false
	attack_route_kind = "ambient"
	_attack_player_index = 0
	_attack_waypoints.clear()
	_attack_route_snapshot.clear()
	_cleanup_attack_rescue_portals(true)
	animation_player.speed_scale = 1.0
	_reset_arcade_attack_effects()
	_play_swim_animation(BITE_ANIMATION_BLEND_SECONDS)
	_recenter_ambient_path()


func is_attacking_player(player_index: int) -> bool:
	return is_attacking and _attack_player_index == player_index


func get_attack_route() -> PackedVector3Array:
	return _attack_route_snapshot.duplicate()


func get_attack_player_index() -> int:
	return _attack_player_index


func get_attack_phase() -> int:
	return _attack_phase


func get_attack_intensity() -> float:
	return _attack_intensity


func get_ocean_attack_debug_state() -> Dictionary:
	return {
		"attacking": is_attacking,
		"player": _attack_player_index,
		"phase": AttackPhase.keys()[_attack_phase],
		"route_kind": attack_route_kind,
		"target": _attack_target,
		"waypoint_count": _attack_waypoints.size(),
		"stuck_elapsed": _attack_stuck_elapsed,
		"portal_phase": AttackPortalPhase.keys()[_attack_portal_phase],
		"portal_rescue_count": _attack_portal_rescue_count,
		"entry_portal_active": (
			_attack_entry_portal != null and is_instance_valid(_attack_entry_portal)
		),
		"exit_portal_active": (
			_attack_exit_portal != null and is_instance_valid(_attack_exit_portal)
		),
		"entry_portal_open_amount": (
			float(_attack_entry_portal.get("open_amount"))
			if _attack_entry_portal != null and is_instance_valid(_attack_entry_portal)
			else 0.0
		),
		"exit_portal_open_amount": (
			float(_attack_exit_portal.get("open_amount"))
			if _attack_exit_portal != null and is_instance_valid(_attack_exit_portal)
			else 0.0
		),
		"exit_portal_position": (
			_attack_exit_portal.global_position
			if _attack_exit_portal != null and is_instance_valid(_attack_exit_portal)
			else _attack_portal_exit_center
		),
		"exit_portal_forward": _attack_portal_exit_forward,
		"exit_portal_behind_direction": _attack_portal_behind_direction,
		"exit_portal_behind_alignment": (
			_attack_target.direction_to(_attack_portal_exit_center).dot(
				_attack_portal_behind_direction
			)
			if _attack_target.distance_squared_to(_attack_portal_exit_center) > 0.0001
			else 0.0
		),
		"shark_visible": visible,
	}


func _set_attack_phase(next_phase: int) -> void:
	if _attack_phase == next_phase:
		return
	_attack_phase = next_phase
	attack_phase_changed.emit(_attack_player_index, _attack_phase)


func _setup_jaw_rig() -> void:
	_jaw_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _jaw_skeleton == null:
		push_warning("Shark jaw rig could not find Skeleton3D")
		return
	_jaw_bone_index = _jaw_skeleton.find_bone("jaw")
	if _jaw_bone_index < 0:
		push_warning("Shark model has no jaw bone; attack will use body lunge only")
		return
	_jaw_rest_rotation = _jaw_skeleton.get_bone_pose_rotation(_jaw_bone_index)


func _setup_attack_effects() -> void:
	_wake_particles = _create_wake_particles()
	_wake_particles.name = "ArcadeWake"
	_wake_particles.position = Vector3(0.0, 0.0, WAKE_OFFSET_SCALE * model_scale)
	add_child(_wake_particles)

	_surface_spray = _create_surface_spray()
	_surface_spray.name = "ChargeSurfaceSpray"
	add_child(_surface_spray)

	_ghost_breach_particles = _create_ghost_breach_particles()
	_ghost_breach_particles.name = "GhostBreachBurst"
	_ghost_breach_particles.top_level = true
	add_child(_ghost_breach_particles)

	_ghost_aura_particles = _create_ghost_aura_particles()
	_ghost_aura_particles.name = "GhostAuraTrail"
	add_child(_ghost_aura_particles)

	_ghost_breach_ring = _create_ghost_breach_ring()
	_ghost_breach_ring.name = "GhostBreachRing"
	_ghost_breach_ring.top_level = true
	add_child(_ghost_breach_ring)

	_rush_audio = AudioStreamPlayer3D.new()
	_rush_audio.name = "SharkRushSFX"
	_rush_audio.bus = "SFX"
	_rush_audio.max_distance = 90.0
	_rush_audio.unit_size = 12.0
	_rush_audio.stream = AudioManager.get_shark_rush_stream()
	add_child(_rush_audio)

	_impact_audio = AudioStreamPlayer3D.new()
	_impact_audio.name = "SharkImpactSFX"
	_impact_audio.bus = "SFX"
	_impact_audio.max_distance = 100.0
	_impact_audio.unit_size = 14.0
	_impact_audio.stream = AudioManager.get_shark_impact_stream()
	add_child(_impact_audio)


func _create_wake_particles() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.amount = GraphicsQuality.particle_amount(72, GameManager.graphics_quality)
	particles.amount_ratio = 0.0
	particles.lifetime = 0.85
	particles.randomness = 0.34
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-10.0, -5.0, -10.0), Vector3(20.0, 12.0, 20.0))

	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.direction = Vector3.BACK
	process_material.spread = 28.0
	process_material.initial_velocity_min = 2.5
	process_material.initial_velocity_max = 7.5
	process_material.gravity = Vector3(0.0, 1.8, 0.0)
	process_material.damping_min = 1.2
	process_material.damping_max = 2.8
	process_material.scale_min = 0.08
	process_material.scale_max = 0.30
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1.25 * model_scale, 0.28, 0.35)
	var color_ramp: Gradient = Gradient.new()
	color_ramp.set_color(0, Color(0.88, 0.98, 1.0, 0.92))
	color_ramp.set_color(1, Color(0.16, 0.62, 0.88, 0.0))
	var color_texture: GradientTexture1D = GradientTexture1D.new()
	color_texture.gradient = color_ramp
	process_material.color_ramp = color_texture
	particles.process_material = process_material

	var bubble_mesh: SphereMesh = SphereMesh.new()
	bubble_mesh.radius = 0.07
	bubble_mesh.height = 0.14
	var bubble_material: StandardMaterial3D = StandardMaterial3D.new()
	bubble_material.albedo_color = Color(0.74, 0.94, 1.0, 0.78)
	bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mesh.material = bubble_material
	particles.draw_pass_1 = bubble_mesh
	return particles


func _create_surface_spray() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.amount = GraphicsQuality.particle_amount(54, GameManager.graphics_quality)
	particles.amount_ratio = 0.0
	particles.lifetime = 0.58
	particles.randomness = 0.42
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8.0, -3.0, -8.0), Vector3(16.0, 12.0, 16.0))

	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 52.0
	process_material.initial_velocity_min = 2.8
	process_material.initial_velocity_max = 7.2
	process_material.gravity = Vector3(0.0, -10.0, 0.0)
	process_material.damping_min = 0.6
	process_material.damping_max = 1.6
	process_material.scale_min = 0.08
	process_material.scale_max = 0.25
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1.35 * model_scale, 0.12, 1.4)
	var color_ramp: Gradient = Gradient.new()
	color_ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.96))
	color_ramp.set_color(1, Color(0.22, 0.72, 0.96, 0.0))
	var color_texture: GradientTexture1D = GradientTexture1D.new()
	color_texture.gradient = color_ramp
	process_material.color_ramp = color_texture
	particles.process_material = process_material

	var droplet_mesh: SphereMesh = SphereMesh.new()
	droplet_mesh.radius = 0.055
	droplet_mesh.height = 0.22
	var droplet_material: StandardMaterial3D = StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.82, 0.97, 1.0, 0.88)
	droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	droplet_mesh.material = droplet_material
	particles.draw_pass_1 = droplet_mesh
	return particles


func _create_ghost_breach_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = GraphicsQuality.particle_amount(112, GameManager.graphics_quality)
	particles.lifetime = 0.92
	particles.explosiveness = 0.94
	particles.randomness = 0.34
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-9.0, -4.0, -9.0), Vector3(18.0, 17.0, 18.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 57.0
	process_material.initial_velocity_min = 5.8
	process_material.initial_velocity_max = 12.4
	process_material.gravity = Vector3(0.0, -13.5, 0.0)
	process_material.damping_min = 0.25
	process_material.damping_max = 1.15
	process_material.scale_min = 0.08
	process_material.scale_max = 0.28
	process_material.radial_velocity_min = 1.4
	process_material.radial_velocity_max = 4.6
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 1.15
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.93, 1.0, 1.0, 0.98))
	color_ramp.add_point(0.28, Color(0.28, 0.90, 1.0, 0.88))
	color_ramp.set_color(2, Color(0.10, 0.42, 0.78, 0.0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_ramp
	process_material.color_ramp = color_texture
	particles.process_material = process_material

	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.065
	droplet_mesh.height = 0.30
	var droplet_material := StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.82, 0.98, 1.0, 0.92)
	droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	droplet_material.vertex_color_use_as_albedo = true
	droplet_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	droplet_mesh.material = droplet_material
	particles.draw_pass_1 = droplet_mesh
	return particles


func _create_ghost_aura_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.amount = GraphicsQuality.particle_amount(48, GameManager.graphics_quality)
	particles.amount_ratio = 0.0
	particles.lifetime = 0.72
	particles.randomness = 0.42
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8.0, -6.0, -8.0), Vector3(16.0, 14.0, 16.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 72.0
	process_material.initial_velocity_min = 0.7
	process_material.initial_velocity_max = 2.4
	process_material.gravity = Vector3(0.0, 0.8, 0.0)
	process_material.damping_min = 0.8
	process_material.damping_max = 2.2
	process_material.scale_min = 0.06
	process_material.scale_max = 0.22
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 1.05
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.68, 0.98, 1.0, 0.0))
	color_ramp.add_point(0.18, Color(0.25, 0.88, 1.0, 0.78))
	color_ramp.set_color(2, Color(0.16, 0.36, 1.0, 0.0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_ramp
	process_material.color_ramp = color_texture
	particles.process_material = process_material

	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.055
	mote_mesh.height = 0.11
	var mote_material := StandardMaterial3D.new()
	mote_material.albedo_color = Color(0.42, 0.94, 1.0, 0.78)
	mote_material.emission_enabled = true
	mote_material.emission = GHOST_AURA_COLOR
	mote_material.emission_energy_multiplier = 2.6
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.vertex_color_use_as_albedo = true
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mesh.material = mote_material
	particles.draw_pass_1 = mote_mesh
	return particles


func _create_ghost_breach_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.82
	ring_mesh.outer_radius = 1.05
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 10
	_ghost_breach_ring_material = StandardMaterial3D.new()
	_ghost_breach_ring_material.albedo_color = Color(0.50, 0.95, 1.0, 0.0)
	_ghost_breach_ring_material.emission_enabled = true
	_ghost_breach_ring_material.emission = GHOST_AURA_COLOR
	_ghost_breach_ring_material.emission_energy_multiplier = 2.4
	_ghost_breach_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_breach_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_breach_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mesh.material = _ghost_breach_ring_material
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	return ring


func _update_arcade_attack_effects(delta: float) -> void:
	var ghost_charging := is_ghost_ridden and _ghost_phase == GhostRidePhase.CHARGING
	var portal_entering := (
		is_ghost_ridden and _ghost_phase == GhostRidePhase.PORTAL_ENTERING
	)
	var ghost_entering := is_ghost_ridden and _ghost_phase in [
		GhostRidePhase.ENTERING,
		GhostRidePhase.PORTAL_ENTERING,
	]
	var ghost_departing := is_ghost_ridden and _ghost_phase == GhostRidePhase.DEPARTING
	var arcade_active := is_attacking or ghost_charging or ghost_entering or ghost_departing
	var authored_mount_animation := is_ghost_ridden and _ghost_phase in [
		GhostRidePhase.RENDEZVOUS_ASCENT,
		GhostRidePhase.RENDEZVOUS,
		GhostRidePhase.MOUNTING,
		GhostRidePhase.DEPARTING,
		GhostRidePhase.ENTERING,
		GhostRidePhase.PORTAL_ENTERING,
	]
	var authored_bite_animation := (
		is_attacking and _attack_phase == AttackPhase.BITE
	)
	if authored_bite_animation:
		# Match the 0.40-second authored clip to the gameplay bite timer.
		animation_player.speed_scale = 1.0
	elif arcade_active and not authored_mount_animation:
		animation_player.speed_scale = lerpf(1.75, 2.35, _attack_intensity)
	if _wake_particles != null:
		_wake_particles.emitting = (
			arcade_active and not portal_entering and _attack_intensity > 0.03
		)
		_wake_particles.amount_ratio = clampf(_attack_intensity, 0.0, 1.0)
	if _surface_spray != null:
		_surface_spray.position.y = StageConstants.OCEAN_SURFACE_Y - position.y + 0.12
		_surface_spray.emitting = is_attacking and _attack_intensity > 0.16
		_surface_spray.amount_ratio = clampf((_attack_intensity - 0.12) / 0.88, 0.0, 1.0)
	if _ghost_aura_particles != null:
		_ghost_aura_particles.emitting = (
			is_ghost_ridden
			and not portal_entering
			and _ghost_phase != GhostRidePhase.FINISHED
		)
		var aura_target := 0.0
		if is_ghost_ridden and not portal_entering:
			aura_target = lerpf(0.34, 1.0, maxf(_attack_intensity, _ghost_charge_tension))
		_ghost_aura_particles.amount_ratio = move_toward(
			_ghost_aura_particles.amount_ratio,
			aura_target,
			delta * 2.8
		)
	if _rush_audio != null:
		if arcade_active and _attack_intensity > 0.04:
			if not _rush_audio.playing:
				_rush_audio.play()
			var audible_strength: float = clampf(_attack_intensity, 0.001, 1.0)
			_rush_audio.volume_db = linear_to_db(audible_strength) - 2.5
			_rush_audio.pitch_scale = lerpf(0.78, 1.52, _attack_intensity)
		elif _rush_audio.playing:
			_rush_audio.stop()

	var bite_progress: float = (
		clampf(_bite_timer / BITE_LUNGE_DURATION, 0.0, 1.0)
		if _attack_phase == AttackPhase.BITE
		else 0.0
	)
	var lunge_curve: float = sin(bite_progress * PI)
	model.position = Vector3(0.0, lunge_curve * 0.12, -lunge_curve * 0.78 * model_scale)
	model.rotation.x -= lunge_curve * 0.11
	_apply_jaw_pose()
	if not arcade_active:
		_attack_intensity = move_toward(_attack_intensity, 0.0, delta * 5.0)


func _apply_jaw_pose() -> void:
	if _jaw_skeleton == null or _jaw_bone_index < 0:
		return
	var open_rotation: Quaternion = Quaternion(
		Vector3.FORWARD,
		deg_to_rad(JAW_OPEN_DEGREES * _jaw_open_amount)
	)
	_jaw_skeleton.set_bone_pose_rotation(
		_jaw_bone_index,
		_jaw_rest_rotation * open_rotation
	)


func _reset_arcade_attack_effects() -> void:
	_attack_intensity = 0.0
	_bite_timer = 0.0
	_jaw_open_amount = 0.0
	model.position = Vector3.ZERO
	if _wake_particles != null:
		_wake_particles.emitting = false
		_wake_particles.amount_ratio = 0.0
	if _surface_spray != null:
		_surface_spray.emitting = false
		_surface_spray.amount_ratio = 0.0
	if _rush_audio != null and _rush_audio.playing:
		_rush_audio.stop()
	_apply_jaw_pose()


func _play_swim_animation(blend_time: float = -1.0) -> void:
	if _play_named_animation(
		SHARK_SWIM_ANIMATION,
		true,
		animation_speed,
		blend_time
	):
		return
	var animation_names: PackedStringArray = animation_player.get_animation_list()
	for animation_name: StringName in animation_names:
		if animation_name == &"RESET":
			continue
		var animation: Animation = animation_player.get_animation(animation_name)
		if animation == null:
			continue
		animation.loop_mode = Animation.LOOP_LINEAR
		animation_player.play(animation_name, blend_time, animation_speed)
		if animation.length > 0.0:
			var normalized_phase: float = fposmod(phase, TAU) / TAU
			animation_player.seek(normalized_phase * animation.length, true)
		return
	push_warning("Shark swimmer has no playable animation")


func _play_bite_animation() -> void:
	if _play_named_animation(
		SHARK_BITE_ANIMATION,
		false,
		1.0,
		BITE_ANIMATION_BLEND_SECONDS
	):
		return
	# Keep the procedural jaw/lunge fallback if an older imported shark asset
	# is temporarily present while the editor is reimporting the GLB.
	push_warning("Shark swimmer has no SharkBite animation; using procedural bite")


func _play_named_animation(
	preferred_name: StringName,
	looped: bool,
	speed: float,
	blend_time: float = -1.0
) -> bool:
	var resolved_name := StringName()
	for animation_name: StringName in animation_player.get_animation_list():
		var short_name := String(animation_name).get_file()
		if animation_name == preferred_name or short_name == String(preferred_name):
			resolved_name = animation_name
			break
	if resolved_name == StringName():
		return false
	var animation: Animation = animation_player.get_animation(resolved_name)
	if animation == null:
		return false
	animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	animation_player.play(resolved_name, blend_time, speed)
	return true


func _update_ghost_ride(delta: float) -> void:
	if _ghost_mount_beam_sequence_started:
		_ghost_mount_beam_elapsed += delta
	match _ghost_phase:
		GhostRidePhase.RENDEZVOUS_ASCENT:
			if not _ghost_rendezvous_ascent_started:
				position = _ghost_rendezvous_start
				_velocity = Vector3.ZERO
				_attack_intensity = move_toward(_attack_intensity, 0.0, delta)
				return
			_ghost_rendezvous_elapsed += delta
			var ascent_progress := clampf(
				_ghost_rendezvous_elapsed / GHOST_RENDEZVOUS_ASCENT_DURATION,
				0.0,
				1.0
			)
			var ascent_eased := smoothstep(0.0, 1.0, ascent_progress)
			var ascent_previous := position
			position = _ghost_rendezvous_start.lerp(
				_ghost_rendezvous_position,
				ascent_eased
			)
			_velocity = (position - ascent_previous) / maxf(delta, 0.0001)
			_attack_intensity = move_toward(_attack_intensity, 0.18, delta * 0.65)
			if (
				not _ghost_breach_triggered
				and ascent_previous.y < StageConstants.OCEAN_SURFACE_Y
				and position.y >= StageConstants.OCEAN_SURFACE_Y
			):
				_trigger_ghost_breach()
			if ascent_progress >= 1.0:
				position = _ghost_rendezvous_position
				_velocity = Vector3.ZERO
				_attack_intensity = 0.08
				_snap_to_ghost_aim_orientation()
				_ghost_phase = GhostRidePhase.RENDEZVOUS
		GhostRidePhase.RENDEZVOUS:
			_ghost_rendezvous_elapsed += delta
			var hold_time := maxf(
				0.0,
				_ghost_rendezvous_elapsed - GHOST_RENDEZVOUS_ASCENT_DURATION
			)
			var previous_position := position
			position = _ghost_rendezvous_position + Vector3(
				sin(hold_time * 1.35) * 0.16,
				sin(hold_time * 2.15) * 0.10,
				cos(hold_time * 1.35) * 0.22
			)
			_velocity = (position - previous_position) / maxf(delta, 0.0001)
			_attack_intensity = move_toward(_attack_intensity, 0.08, delta * 1.2)
		GhostRidePhase.MOUNTING:
			if _ghost_mount_beam_sequence_started:
				_update_post_mount_beam_ascent(delta)
				return
			_ghost_mount_settle_elapsed += delta
			var settle_progress := clampf(
				_ghost_mount_settle_elapsed / GHOST_MOUNT_SETTLE_DURATION,
				0.0,
				1.0
			)
			var previous_position := position
			# Keep the settle dip small so the belly does not re-enter the ocean
			# surface and flash as transparent against water depth.
			var contact_dip := sin(settle_progress * PI) * 0.06
			var contact_surge := sin(settle_progress * PI) * 0.10
			position = (
				_ghost_rendezvous_position
				+ Vector3.DOWN * contact_dip
				+ Vector3.FORWARD * contact_surge
			)
			_velocity = (position - previous_position) / maxf(delta, 0.0001)
			if _ghost_rider != null and is_instance_valid(_ghost_rider):
				var eased_settle := 1.0 - pow(1.0 - settle_progress, 3.0)
				var mounted_transform_variant: Variant = _ghost_rider.get_meta(
					"ghost_mount_target_transform",
					Transform3D(Basis.from_scale(Vector3.ONE * 0.92), Vector3.ZERO)
				)
				var mounted_transform := mounted_transform_variant as Transform3D
				_ghost_rider.transform = _ghost_rider_settle_start.interpolate_with(
					mounted_transform,
					eased_settle
				)
				var rider_rebound := sin(settle_progress * PI * 2.0) * (1.0 - settle_progress)
				_ghost_rider.position += Vector3(0.0, rider_rebound * 0.07, rider_rebound * 0.04)
			_attack_intensity = move_toward(_attack_intensity, 0.16, delta * 1.8)
		GhostRidePhase.DEPARTING:
			if animation_player.current_animation == StringName():
				_play_swim_animation()
				animation_player.speed_scale = GHOST_HOVER_ANIMATION_SPEED
			_ghost_entry_elapsed += delta
			var departure_progress := clampf(
				_ghost_entry_elapsed / GHOST_DEPARTURE_DURATION,
				0.0,
				1.0
			)
			# Unit slope at the start matches the inherited ascent velocity; zero
			# slope at the end still lets the shark settle cleanly into hover.
			var departure_eased := (
				departure_progress
				+ departure_progress * departure_progress
				- departure_progress * departure_progress * departure_progress
			)
			var departure_previous := position
			position = _cubic_bezier(
				_ghost_entry_start,
				_ghost_departure_control_a,
				_ghost_departure_control_b,
				_ghost_hover_target,
				departure_eased
			)
			_velocity = (position - departure_previous) / maxf(delta, 0.0001)
			_ghost_entry_progress = departure_progress
			_attack_intensity = 0.08 + sin(departure_progress * PI) * 0.12
			if (
				not _ghost_breach_triggered
				and departure_previous.y < StageConstants.OCEAN_SURFACE_Y
				and position.y >= StageConstants.OCEAN_SURFACE_Y
			):
				_trigger_ghost_breach()
			if departure_progress >= 1.0:
				position = _ghost_hover_target
				_velocity = Vector3.ZERO
				_ghost_entry_progress = 1.0
				_ghost_phase = GhostRidePhase.HOVER
				_stop_ghost_mount_beacon_sequence()
				_play_swim_animation()
				animation_player.speed_scale = GHOST_HOVER_ANIMATION_SPEED
		GhostRidePhase.PORTAL_ENTERING:
			_ghost_entry_elapsed += delta
			var progress := clampf(
				_ghost_entry_elapsed / GHOST_PORTAL_ENTRY_DURATION,
				0.0,
				1.0
			)
			var travel_weight := smoothstep(0.0, 1.0, progress)
			var previous_position := position
			position = _ghost_entry_start.lerp(_ghost_hover_target, travel_weight)
			_velocity = (position - previous_position) / maxf(delta, 0.0001)
			_ghost_entry_progress = travel_weight
			# Behind the mouth, the stencil reveals the shark only through the
			# aperture. Once its center crosses the portal plane, restore the
			# authored materials so the front half can exist outside the ring;
			# the opaque tunnel keeps the remaining rear half physically occluded.
			if (
				_ghost_portal_stencil_active
				and travel_weight >= _ghost_portal_stencil_release_progress
			):
				_set_ghost_portal_stencil_enabled(false)
			# Keep authored scale constant. Apparent growth now comes from actual
			# movement through the portal depth, matching the pack's demo.
			scale = _ghost_base_scale
			_attack_intensity = lerpf(0.28, 0.0, progress)
			if progress >= 1.0:
				position = _ghost_hover_target
				scale = _ghost_base_scale
				_velocity = Vector3.ZERO
				_ghost_entry_progress = 1.0
				_set_ghost_portal_stencil_enabled(false)
				_ghost_phase = GhostRidePhase.HOVER
				_update_ghost_occlusion_silhouette()
				_play_swim_animation()
		GhostRidePhase.ENTERING:
			_ghost_entry_elapsed += delta
			var progress := clampf(_ghost_entry_elapsed / GHOST_ENTRY_DURATION, 0.0, 1.0)
			# Use one ease for the complete underwater-to-hover route.  Splitting
			# this into separately eased underwater and breach legs made the shark
			# visibly brake at the waterline before accelerating again.
			var travel_weight := smoothstep(0.0, 1.0, progress)
			var previous_position := position
			if travel_weight < GHOST_ENTRY_BREACH_PROGRESS:
				var underwater_progress := travel_weight / GHOST_ENTRY_BREACH_PROGRESS
				position = _ghost_entry_start.lerp(
					_ghost_entry_breach_point,
					underwater_progress
				)
			else:
				var breach_progress := inverse_lerp(
					GHOST_ENTRY_BREACH_PROGRESS,
					1.0,
					travel_weight
				)
				position = _cubic_bezier(
					_ghost_entry_breach_point,
					_ghost_entry_control_a,
					_ghost_entry_control_b,
					_ghost_hover_target,
					breach_progress
				)
			_velocity = (position - previous_position) / maxf(delta, 0.0001)
			_ghost_entry_progress = travel_weight
			var scale_pulse := sin(travel_weight * PI) * GHOST_ENTRY_SCALE_PULSE
			var scale_factor := (
				lerpf(GHOST_ENTRY_START_SCALE, 1.0, travel_weight) + scale_pulse
			)
			scale = _ghost_base_scale * scale_factor
			_attack_intensity = 0.16 + sin(progress * PI) * 0.32
			if (
				not _ghost_breach_triggered
				and previous_position.y < StageConstants.OCEAN_SURFACE_Y
				and position.y >= StageConstants.OCEAN_SURFACE_Y
			):
				_trigger_ghost_breach()
			if progress >= 1.0:
				position = _ghost_hover_target
				scale = _ghost_base_scale
				_ghost_entry_progress = 1.0
				_ghost_phase = GhostRidePhase.HOVER
				_play_swim_animation()
		GhostRidePhase.HOVER:
			var hover_position := _ghost_hover_target + Vector3.UP * sin(_swim_time * 2.1) * 0.12
			var previous_position := position
			position = position.move_toward(hover_position, 15.0 * delta)
			_velocity = (position - previous_position) / maxf(delta, 0.0001)
			_attack_intensity = move_toward(_attack_intensity, 0.0, delta * 2.0)
			animation_player.speed_scale = lerpf(
				animation_player.speed_scale,
				GHOST_HOVER_ANIMATION_SPEED,
				minf(1.0, delta * 2.0)
			)
		GhostRidePhase.CHARGING:
			_ghost_charge_tension = move_toward(_ghost_charge_tension, 1.0, delta * 8.0)
			var remaining := maxf(0.0, _ghost_charge_max_distance - _ghost_charge_distance)
			var travel := minf(remaining, _ghost_charge_speed * delta)
			position += _ghost_charge_direction * travel
			_ghost_charge_distance += travel
			_velocity = _ghost_charge_direction * _ghost_charge_speed
			_attack_intensity = 1.0
			if _ghost_charge_distance >= _ghost_charge_max_distance - 0.001:
				_ghost_phase = GhostRidePhase.FINISHED
				ghost_charge_finished.emit()
		GhostRidePhase.FINISHED:
			_velocity = Vector3.ZERO


func _update_post_mount_beam_ascent(delta: float) -> void:
	if (
		_ghost_mount_beam_elapsed >= GHOST_MOUNT_BEAM_SHUTDOWN_TIME
		and not _ghost_mount_beam_shutdown_started
	):
		_ghost_mount_beam_shutdown_started = true
		_stop_ghost_mount_beacon_sequence()
	# Keep the shark planted for the complete firing and closing sequence. The
	# extra settle window lets the sustained camera shake decay to zero before
	# any upward movement begins.
	if _ghost_mount_beam_elapsed < GHOST_MOUNT_BEAM_ASCENT_START_TIME:
		position = _ghost_mount_beam_ascent_start
		quaternion = _ghost_mount_beam_ascent_start_quaternion
		_velocity = Vector3.ZERO
		_attack_intensity = 0.16
		return
	var ascent_elapsed := (
		_ghost_mount_beam_elapsed - GHOST_MOUNT_BEAM_ASCENT_START_TIME
	)
	var ascent_progress := clampf(
		ascent_elapsed / GHOST_MOUNT_BEAM_ASCENT_DURATION,
		0.0,
		1.0
	)
	# Only after the beam and vibration have fully settled, turn upward and rise.
	var vertical_turn := smoothstep(
		0.0,
		GHOST_MOUNT_VERTICAL_TURN_END,
		ascent_progress
	)
	var vertical_quaternion := _quat_look_at(
		_ghost_mount_beam_ascent_start,
		_ghost_mount_beam_ascent_start + Vector3.UP
	)
	quaternion = _ghost_mount_beam_ascent_start_quaternion.slerp(
		vertical_quaternion,
		vertical_turn
	)
	_bank = 0.0
	model.rotation = Vector3(0.0, PI * 0.5, 0.0)

	# Ease into the lift, but retain upward velocity at the end so the following
	# departure curve can continue without a mid-air stop.
	var lift_progress := pow(ascent_progress, 1.22)
	var previous_position := position
	position = (
		_ghost_mount_beam_ascent_start
		+ Vector3.UP * GHOST_MOUNT_BEAM_ASCENT_HEIGHT * lift_progress
	)
	_velocity = (position - previous_position) / maxf(delta, 0.0001)
	_attack_intensity = lerpf(0.16, 0.34, lift_progress)


func _configure_ghost_entry_curve(entry_position: Vector3, target_position: Vector3) -> void:
	_ghost_entry_side = signf(entry_position.x - target_position.x)
	if is_zero_approx(_ghost_entry_side):
		_ghost_entry_side = 1.0 if _ghost_player_index == 1 else -1.0
	_ghost_entry_breach_point = target_position + Vector3(
		_ghost_entry_side * 3.65,
		StageConstants.OCEAN_SURFACE_Y - 0.85 - target_position.y,
		-1.65
	)
	# Match the incoming underwater velocity at the piece boundary so crossing
	# the surface changes direction smoothly without pausing there.
	var incoming_tangent := _ghost_entry_breach_point - entry_position
	var tangent_scale := (
		(1.0 - GHOST_ENTRY_BREACH_PROGRESS)
		/ (3.0 * GHOST_ENTRY_BREACH_PROGRESS)
	)
	_ghost_entry_control_a = _ghost_entry_breach_point + incoming_tangent * tangent_scale
	_ghost_entry_control_b = target_position + Vector3(
		_ghost_entry_side * 1.30,
		3.0,
		-0.65
	)


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


func _trigger_ghost_breach() -> void:
	_ghost_breach_triggered = true
	var breach_position := Vector3(
		global_position.x,
		StageConstants.OCEAN_SURFACE_Y + 0.08,
		global_position.z
	)
	if _ghost_breach_particles != null:
		_ghost_breach_particles.global_position = breach_position
		_ghost_breach_particles.global_basis = Basis.IDENTITY
		_ghost_breach_particles.restart()
	if _ghost_breach_ring != null:
		_ghost_breach_ring.global_position = breach_position + Vector3.UP * 0.04
		_ghost_breach_ring.global_basis = Basis.IDENTITY
		_ghost_breach_ring.scale = Vector3.ONE * 0.42
		_ghost_breach_ring.visible = true
		_ghost_breach_ring_elapsed = 0.0
	if _impact_audio != null:
		_impact_audio.volume_db = -5.5
		_impact_audio.pitch_scale = randf_range(1.08, 1.16)
		_impact_audio.play()


func _update_ghost_breach_effect(delta: float) -> void:
	if _ghost_breach_ring_elapsed < 0.0 or _ghost_breach_ring == null:
		return
	_ghost_breach_ring_elapsed += delta
	var progress := clampf(_ghost_breach_ring_elapsed / GHOST_BREACH_RING_DURATION, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	_ghost_breach_ring.scale = Vector3.ONE * lerpf(0.42, 3.25, eased)
	if _ghost_breach_ring_material != null:
		var alpha := pow(1.0 - progress, 1.65) * 0.84
		_ghost_breach_ring_material.albedo_color = Color(0.50, 0.95, 1.0, alpha)
		_ghost_breach_ring_material.emission_energy_multiplier = lerpf(3.1, 0.45, progress)
	if progress >= 1.0:
		_ghost_breach_ring.visible = false
		_ghost_breach_ring_elapsed = -1.0


func _update_ghost_aim_orientation(delta: float) -> void:
	var flat_target := Vector3(_ghost_aim_point.x, position.y, _ghost_aim_point.z)
	if position.distance_squared_to(flat_target) < 0.01:
		return
	var target_quaternion := _quat_look_at(position, flat_target)
	var turn_blend := 1.0 - exp(-GHOST_AIM_TURN_RESPONSE * delta)
	quaternion = quaternion.slerp(target_quaternion, turn_blend)
	var settle_blend := 1.0 - exp(-5.0 * delta)
	_bank = lerpf(_bank, 0.0, settle_blend)
	model.rotation = Vector3(
		lerp_angle(model.rotation.x, 0.0, settle_blend),
		PI * 0.5,
		_bank
	)


func _snap_to_ghost_aim_orientation() -> void:
	var flat_target := Vector3(_ghost_aim_point.x, position.y, _ghost_aim_point.z)
	if position.distance_squared_to(flat_target) < 0.01:
		return
	quaternion = _quat_look_at(position, flat_target)
	_bank = 0.0
	model.rotation = Vector3(0.0, PI * 0.5, 0.0)


func _update_ghost_mount_bob() -> void:
	if _ghost_mount == null or not is_instance_valid(_ghost_mount):
		return
	var base_basis := Basis.IDENTITY
	var base_position := _ghost_mount_base_position
	if _ghost_mount_socket != null and is_instance_valid(_ghost_mount_socket):
		var socket_local := global_transform.affine_inverse() * _ghost_mount_socket.global_transform
		base_basis = (
			socket_local.basis.orthonormalized()
			* Basis.from_euler(Vector3(0.0, GHOST_RIDER_SOCKET_YAW_CORRECTION, 0.0))
		)
		base_position = socket_local.origin + Vector3.UP * GHOST_RIDER_MOUNT_LIFT
		_ghost_mount_base_position = base_position
	var bob_speed := lerpf(3.2, 5.8, _ghost_charge_tension)
	var bob_amount := lerpf(0.055, 0.025, _ghost_charge_tension)
	var bob := sin(_swim_time * bob_speed + float(_ghost_player_index)) * bob_amount
	var entry_reveal := 1.0
	if _ghost_phase == GhostRidePhase.ENTERING:
		entry_reveal = clampf((_ghost_entry_progress - 0.08) / 0.54, 0.0, 1.0)
	_ghost_mount.position = (
		base_position
		+ Vector3.UP * bob
		+ Vector3(0.0, -0.04, -0.18) * _ghost_charge_tension
	)
	var entry_pitch := lerpf(18.0, 0.0, entry_reveal)
	var animated_basis := Basis.from_euler(
		Vector3(deg_to_rad(entry_pitch - 12.0 * _ghost_charge_tension), 0.0, 0.0)
	)
	animated_basis = animated_basis.scaled(
		Vector3.ONE * lerpf(GHOST_ENTRY_START_SCALE, 1.0, entry_reveal)
	)
	_ghost_mount.basis = base_basis * animated_basis


func _calculate_ghost_mount_position() -> Vector3:
	var mesh_nodes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var has_bounds := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		var box := mesh_instance.get_aabb()
		for corner_index in range(8):
			var corner := box.position + Vector3(
				box.size.x if (corner_index & 1) != 0 else 0.0,
				box.size.y if (corner_index & 2) != 0 else 0.0,
				box.size.z if (corner_index & 4) != 0 else 0.0
			)
			var local_corner := to_local(mesh_instance.to_global(corner))
			if not has_bounds:
				min_point = local_corner
				max_point = local_corner
				has_bounds = true
			else:
				min_point = min_point.min(local_corner)
				max_point = max_point.max(local_corner)
	if not has_bounds:
		return Vector3(0.0, 0.8, 0.0)
	return Vector3(
		(min_point.x + max_point.x) * 0.5,
		max_point.y - minf(1.25, (max_point.y - min_point.y) * 0.32),
		(min_point.z + max_point.z) * 0.5
	)


func _update_ambient_swim(delta: float) -> void:
	_angle = fposmod(_angle + swim_speed * delta, TAU)
	var desired_position: Vector3 = _orbit_position(_angle)
	var lookahead_position: Vector3 = _orbit_position(_angle + _ambient_angle_step())
	var desired_direction: Vector3 = desired_position.direction_to(lookahead_position)
	var correction: Vector3 = (desired_position - position) * 0.72
	var desired_velocity: Vector3 = desired_direction * _ambient_linear_speed() + correction
	desired_velocity = desired_velocity.limit_length(_ambient_linear_speed() * 1.35)
	_velocity = _velocity.move_toward(desired_velocity, ambient_acceleration * delta)
	position += _velocity * delta
	animation_player.speed_scale = lerpf(animation_player.speed_scale, 1.0, minf(1.0, delta * 2.0))


func _update_attack(delta: float) -> void:
	if _attack_portal_phase != AttackPortalPhase.NONE:
		_update_attack_portal_rescue(delta)
		return
	if _attack_waypoints.is_empty():
		_finish_attack()
		return

	var waypoint: Vector3 = _attack_waypoints[0]
	var final_leg: bool = _attack_waypoints.size() == 1
	var distance: float = position.distance_to(waypoint)
	if _update_attack_stuck_watchdog(delta, waypoint, distance):
		return

	if final_leg and _attack_phase != AttackPhase.BITE:
		var bite_start_distance: float = bite_distance + attack_speed * BITE_LUNGE_DURATION
		if distance <= CHARGE_DISTANCE:
			_set_attack_phase(AttackPhase.CHARGE)
			_attack_intensity = clampf(
				1.0 - inverse_lerp(bite_start_distance, CHARGE_DISTANCE, distance),
				0.18,
				0.92
			)
			_jaw_open_amount = smoothstep(0.12, 0.82, _attack_intensity)
		if distance <= bite_start_distance:
			_set_attack_phase(AttackPhase.BITE)
			_bite_timer = 0.0
			_attack_intensity = 1.0
			_jaw_open_amount = 1.0
			animation_player.speed_scale = 1.0
			_play_bite_animation()
	elif not final_leg:
		_set_attack_phase(AttackPhase.APPROACH)
		_attack_intensity = move_toward(_attack_intensity, 0.08, delta * 0.6)
		_jaw_open_amount = move_toward(_jaw_open_amount, 0.0, delta * 4.0)

	if _attack_phase == AttackPhase.BITE:
		_update_bite_lunge(delta, waypoint)
		return

	var arrival_distance: float = maxf(1.0, attack_speed * delta * 0.8)
	if not final_leg and distance <= arrival_distance:
		position = waypoint
		_attack_waypoints.pop_front()
		if not _attack_waypoints.is_empty():
			var next_direction: Vector3 = position.direction_to(_attack_waypoints[0])
			var redirected_velocity: Vector3 = next_direction * attack_speed * 0.68
			_velocity = _velocity.lerp(redirected_velocity, 0.82)
		_reset_attack_stuck_watchdog()
		return

	var leg_speed: float = attack_speed if final_leg else attack_speed * 0.72
	var desired_velocity: Vector3 = position.direction_to(waypoint) * leg_speed
	var acceleration: float = attack_acceleration * (1.35 if final_leg else 1.0)
	_velocity = _velocity.move_toward(desired_velocity, acceleration * delta)
	var previous_position: Vector3 = position
	var candidate: Vector3 = position + _velocity * delta
	position = _keep_clear_of_stage(candidate, previous_position)


func _update_bite_lunge(delta: float, waypoint: Vector3) -> void:
	_bite_timer += delta
	var bite_progress: float = clampf(_bite_timer / BITE_LUNGE_DURATION, 0.0, 1.0)
	var direction: Vector3 = position.direction_to(waypoint)
	var remaining_travel: float = maxf(position.distance_to(waypoint) - bite_distance, 0.0)
	var travel: float = minf(remaining_travel, attack_speed * 1.08 * delta)
	if direction.length_squared() > 0.001 and travel > 0.0:
		var previous_position: Vector3 = position
		position = _keep_clear_of_stage(position + direction * travel, previous_position)
		_velocity = direction * attack_speed * 1.08
	_attack_intensity = 1.0
	_jaw_open_amount = 1.0 - smoothstep(0.22, 0.88, bite_progress)
	if _bite_timer >= BITE_LUNGE_DURATION:
		_finish_attack()


func _finish_attack() -> void:
	if not is_attacking:
		return
	var reached_player: int = _attack_player_index
	if _impact_audio != null:
		_impact_audio.pitch_scale = randf_range(0.96, 1.05)
		_impact_audio.play()
	_set_attack_phase(AttackPhase.AMBIENT)
	is_attacking = false
	attack_route_kind = "ambient"
	_attack_player_index = 0
	_attack_waypoints.clear()
	_cleanup_attack_rescue_portals(false)
	animation_player.speed_scale = 1.0
	_reset_arcade_attack_effects()
	_play_swim_animation(BITE_ANIMATION_BLEND_SECONDS)
	_recenter_ambient_path()
	attack_reached.emit(reached_player)


## ステージ壁の接触補正で同じ場所に押し戻され続けた場合だけ、
## 入口へ消えた後に落下キャラの背後で出口を開き、通常の噛みつきへ復帰させる。
func _update_attack_stuck_watchdog(
	delta: float,
	waypoint: Vector3,
	distance: float
) -> bool:
	if _attack_phase == AttackPhase.BITE:
		_reset_attack_stuck_watchdog(distance)
		return false
	if distance + OCEAN_ATTACK_PROGRESS_EPSILON < _attack_best_waypoint_distance:
		_attack_best_waypoint_distance = distance
		_attack_stuck_elapsed = 0.0
		return false
	_attack_stuck_elapsed += delta
	if (
		_attack_stuck_elapsed < OCEAN_ATTACK_STUCK_SECONDS
		or _attack_portal_rescue_count >= OCEAN_ATTACK_MAX_PORTAL_RESCUES
	):
		return false
	_start_attack_portal_rescue(waypoint)
	return _attack_portal_phase != AttackPortalPhase.NONE


func _reset_attack_stuck_watchdog(distance: float = INF) -> void:
	_attack_best_waypoint_distance = distance
	_attack_stuck_elapsed = 0.0


func _start_attack_portal_rescue(waypoint: Vector3) -> void:
	var portal_parent := get_parent() as Node3D
	if portal_parent == null:
		_reset_attack_stuck_watchdog()
		return
	var source_forward := _velocity.normalized()
	if source_forward.length_squared() <= 0.001:
		source_forward = position.direction_to(waypoint)
	source_forward.y = 0.0
	if source_forward.length_squared() <= 0.001:
		source_forward = Vector3.FORWARD
	source_forward = source_forward.normalized()

	# The edge-facing side is the fallen character's rear space: farther away
	# from the stage than the character, with the exit aimed back at them.
	var behind_direction := _attack_target_outward_normal(_attack_target)
	var exit_forward := -behind_direction
	var exit_center := (
		_attack_target
		+ behind_direction * OCEAN_ATTACK_PORTAL_OUTWARD_DISTANCE
	)
	exit_center.y = ATTACK_CRUISE_Y

	# Only the entry exists at rescue start. The exit is created after the shark
	# has completely disappeared into this portal.
	_attack_entry_portal = _create_ocean_attack_portal(
		portal_parent,
		"OceanAttackEntryPortalP%d" % _attack_player_index
	)
	if _attack_entry_portal == null:
		_cleanup_attack_rescue_portals(true)
		_reset_attack_stuck_watchdog()
		return

	_attack_portal_source_start = global_position
	_attack_portal_source_forward = source_forward
	_attack_portal_source_center = global_position + source_forward * 2.7
	_attack_portal_exit_center = exit_center
	_attack_portal_exit_forward = exit_forward
	_attack_portal_behind_direction = behind_direction
	_attack_portal_exit_start = exit_center - exit_forward * OCEAN_ATTACK_PORTAL_DEPTH
	_attack_portal_exit_end = exit_center + exit_forward * 2.35
	_attack_portal_base_scale = scale
	_place_ocean_attack_portal(
		_attack_entry_portal,
		_attack_portal_source_center,
		source_forward
	)
	_attack_entry_portal.call("open")
	_attack_portal_rescue_count += 1
	_attack_portal_elapsed = 0.0
	_attack_portal_phase = AttackPortalPhase.OPENING
	attack_route_kind = "portal_rescue"
	_set_attack_phase(AttackPhase.PORTAL_RESCUE)
	_velocity = Vector3.ZERO
	_attack_intensity = 0.32
	_jaw_open_amount = 0.0
	_reset_attack_stuck_watchdog()


func _create_ocean_attack_portal(parent: Node3D, portal_name: String) -> Node3D:
	var portal_scene := (
		OCEAN_ATTACK_PORTAL_P1_SCENE
		if _attack_player_index == 1
		else OCEAN_ATTACK_PORTAL_P2_SCENE
	)
	var portal := portal_scene.instantiate() as Node3D
	if portal == null:
		return null
	portal.name = portal_name
	portal.visible = false
	parent.add_child(portal)
	portal.set("size", OCEAN_ATTACK_PORTAL_SIZE)
	portal.set("portal_mode", 0)
	portal.set("animation_speed", 1.25)
	portal.set("open_amount", 0.0)
	portal.visible = true
	return portal


func _place_ocean_attack_portal(
	portal: Node3D,
	portal_position: Vector3,
	travel_forward: Vector3
) -> void:
	portal.global_position = portal_position
	portal.look_at(portal_position + travel_forward, Vector3.UP, true)


func _open_attack_exit_portal() -> bool:
	var portal_parent := get_parent() as Node3D
	if portal_parent == null:
		return false
	_attack_exit_portal = _create_ocean_attack_portal(
		portal_parent,
		"OceanAttackExitPortalP%d" % _attack_player_index
	)
	if _attack_exit_portal == null:
		return false
	_place_ocean_attack_portal(
		_attack_exit_portal,
		_attack_portal_exit_center,
		_attack_portal_exit_forward
	)
	_attack_exit_portal.call("open")
	return true


func _update_attack_portal_rescue(delta: float) -> void:
	_attack_portal_elapsed += delta
	match _attack_portal_phase:
		AttackPortalPhase.OPENING:
			_attack_intensity = move_toward(_attack_intensity, 0.55, delta * 1.8)
			if _attack_portal_elapsed >= OCEAN_ATTACK_PORTAL_OPEN_SECONDS:
				_attack_portal_elapsed = 0.0
				_attack_portal_phase = AttackPortalPhase.ENTERING
		AttackPortalPhase.ENTERING:
			var enter_progress := clampf(
				_attack_portal_elapsed / OCEAN_ATTACK_PORTAL_ENTER_SECONDS,
				0.0,
				1.0
			)
			var previous_position := global_position
			global_position = _attack_portal_source_start.lerp(
				_attack_portal_source_center + _attack_portal_source_forward * 0.8,
				smoothstep(0.0, 1.0, enter_progress)
			)
			_velocity = (global_position - previous_position) / maxf(delta, 0.0001)
			scale = _attack_portal_base_scale * lerpf(1.0, 0.18, enter_progress)
			if enter_progress >= 1.0:
				# Finish the entry first. While the shark is hidden in transit,
				# open a new portal behind the fallen character.
				visible = false
				if _attack_entry_portal != null and is_instance_valid(_attack_entry_portal):
					_attack_entry_portal.call("close")
				_attack_portal_elapsed = 0.0
				if _open_attack_exit_portal():
					_attack_portal_phase = AttackPortalPhase.EXIT_OPENING
				else:
					# If the VFX cannot be created, preserve the rescue gameplay
					# contract by resuming the charge from the intended exit.
					global_position = _attack_portal_exit_end
					scale = _attack_portal_base_scale
					visible = true
					_finish_attack_portal_rescue()
		AttackPortalPhase.EXIT_OPENING:
			_attack_intensity = move_toward(_attack_intensity, 0.72, delta * 1.5)
			if _attack_portal_elapsed >= OCEAN_ATTACK_PORTAL_EXIT_OPEN_SECONDS:
				global_position = _attack_portal_exit_start
				quaternion = _quat_look_at(
					global_position,
					global_position + _attack_portal_exit_forward
				)
				scale = _attack_portal_base_scale * 0.18
				visible = true
				_attack_portal_elapsed = 0.0
				_attack_portal_phase = AttackPortalPhase.EXITING
		AttackPortalPhase.EXITING:
			var exit_progress := clampf(
				_attack_portal_elapsed / OCEAN_ATTACK_PORTAL_EXIT_SECONDS,
				0.0,
				1.0
			)
			var previous_position := global_position
			global_position = _attack_portal_exit_start.lerp(
				_attack_portal_exit_end,
				smoothstep(0.0, 1.0, exit_progress)
			)
			_velocity = (global_position - previous_position) / maxf(delta, 0.0001)
			scale = _attack_portal_base_scale * lerpf(0.18, 1.0, exit_progress)
			_attack_intensity = lerpf(0.55, 0.92, exit_progress)
			_jaw_open_amount = smoothstep(0.35, 0.88, exit_progress)
			if exit_progress >= 1.0:
				_finish_attack_portal_rescue()


func _finish_attack_portal_rescue() -> void:
	global_position = _attack_portal_exit_end
	scale = _attack_portal_base_scale
	visible = true
	_velocity = _attack_portal_exit_forward * attack_speed
	_attack_portal_phase = AttackPortalPhase.NONE
	_attack_portal_elapsed = 0.0
	_attack_waypoints.clear()
	_attack_route_snapshot.clear()
	_append_attack_waypoint(_attack_target)
	_set_attack_phase(AttackPhase.CHARGE)
	_reset_attack_stuck_watchdog(global_position.distance_to(_attack_target))
	_release_attack_rescue_portals()


func _attack_target_outward_normal(target_position: Vector3) -> Vector3:
	var half_length: float = _floor_length * 0.5
	var min_z: float = _floor_center_z - half_length
	var max_z: float = _floor_center_z + half_length
	if target_position.x <= -StageConstants.FLOOR_HALF_WIDTH:
		return Vector3.LEFT
	if target_position.x >= StageConstants.FLOOR_HALF_WIDTH:
		return Vector3.RIGHT
	if target_position.z <= min_z:
		return Vector3.BACK
	if target_position.z >= max_z:
		return Vector3.FORWARD
	var distances := PackedFloat32Array([
		absf(target_position.x + StageConstants.FLOOR_HALF_WIDTH),
		absf(StageConstants.FLOOR_HALF_WIDTH - target_position.x),
		absf(target_position.z - min_z),
		absf(max_z - target_position.z),
	])
	var nearest_side := 0
	for side_index: int in range(1, distances.size()):
		if distances[side_index] < distances[nearest_side]:
			nearest_side = side_index
	return [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD][nearest_side]


func _release_attack_rescue_portals() -> void:
	for portal: Node3D in [_attack_entry_portal, _attack_exit_portal]:
		if portal == null or not is_instance_valid(portal):
			continue
		portal.call("close")
		var cleanup_tween := create_tween().bind_node(portal)
		cleanup_tween.tween_interval(OCEAN_ATTACK_PORTAL_CLOSE_SECONDS)
		cleanup_tween.tween_callback(portal.queue_free)
	_attack_entry_portal = null
	_attack_exit_portal = null


func _cleanup_attack_rescue_portals(immediate: bool) -> void:
	var had_active_rescue := (
		_attack_portal_phase != AttackPortalPhase.NONE
		or (_attack_entry_portal != null and is_instance_valid(_attack_entry_portal))
		or (_attack_exit_portal != null and is_instance_valid(_attack_exit_portal))
	)
	for portal: Node3D in [_attack_entry_portal, _attack_exit_portal]:
		if portal == null or not is_instance_valid(portal):
			continue
		if immediate:
			portal.queue_free()
		else:
			portal.call("close")
			var cleanup_tween := create_tween().bind_node(portal)
			cleanup_tween.tween_interval(OCEAN_ATTACK_PORTAL_CLOSE_SECONDS)
			cleanup_tween.tween_callback(portal.queue_free)
	_attack_entry_portal = null
	_attack_exit_portal = null
	_attack_portal_phase = AttackPortalPhase.NONE
	_attack_portal_elapsed = 0.0
	_attack_portal_exit_center = Vector3.ZERO
	_attack_portal_exit_forward = Vector3.ZERO
	_attack_portal_behind_direction = Vector3.ZERO
	if had_active_rescue:
		scale = _attack_portal_base_scale
		visible = true


func _build_attack_route(from_position: Vector3, target_position: Vector3) -> void:
	_attack_waypoints.clear()
	_attack_route_snapshot.clear()

	if not _segment_crosses_stage(from_position, target_position):
		attack_route_kind = "surface_direct"
		if from_position.y < ATTACK_CRUISE_Y - 0.35:
			_append_attack_waypoint(Vector3(from_position.x, ATTACK_CRUISE_Y, from_position.z))
		_append_attack_waypoint(target_position)
		return

	var around_route: PackedVector3Array = _shortest_around_route(from_position, target_position)
	if not around_route.is_empty():
		attack_route_kind = "surface_around"
		for point: Vector3 in around_route:
			_append_attack_waypoint(point)
		return

	# Emergency fallback only: authored routes should normally remain at the surface.
	attack_route_kind = "under_fallback"
	var under_route: PackedVector3Array = _under_stage_route(from_position, target_position)
	for point: Vector3 in under_route:
		_append_attack_waypoint(point)


func _append_attack_waypoint(point: Vector3) -> void:
	_attack_waypoints.append(point)
	_attack_route_snapshot.append(point)


func _under_stage_route(from_position: Vector3, target_position: Vector3) -> PackedVector3Array:
	var floor_bottom_y: float = StageConstants.FLOOR_CENTER_Y - StageConstants.FLOOR_THICKNESS * 0.5
	var under_y: float = floor_bottom_y - UNDER_STAGE_CLEARANCE
	return PackedVector3Array([
		Vector3(from_position.x, under_y, from_position.z),
		Vector3(target_position.x, under_y, target_position.z),
		target_position,
	])


func _shortest_around_route(from_position: Vector3, target_position: Vector3) -> PackedVector3Array:
	var edge_x: float = StageConstants.FLOOR_HALF_WIDTH + STAGE_CLEARANCE
	var half_length: float = _floor_length * 0.5
	var back_z: float = _floor_center_z - half_length - STAGE_CLEARANCE
	var front_z: float = _floor_center_z + half_length + STAGE_CLEARANCE
	var cruise_y: float = ATTACK_CRUISE_Y
	var candidates: Array[PackedVector3Array] = [
		PackedVector3Array([
			Vector3(from_position.x, cruise_y, back_z),
			Vector3(target_position.x, cruise_y, back_z),
			target_position,
		]),
		PackedVector3Array([
			Vector3(from_position.x, cruise_y, front_z),
			Vector3(target_position.x, cruise_y, front_z),
			target_position,
		]),
		PackedVector3Array([
			Vector3(-edge_x, cruise_y, from_position.z),
			Vector3(-edge_x, cruise_y, target_position.z),
			target_position,
		]),
		PackedVector3Array([
			Vector3(edge_x, cruise_y, from_position.z),
			Vector3(edge_x, cruise_y, target_position.z),
			target_position,
		]),
	]

	var best_route: PackedVector3Array = PackedVector3Array()
	var best_length: float = INF
	for candidate: PackedVector3Array in candidates:
		if not _route_stays_outside_stage(from_position, candidate):
			continue
		var candidate_length: float = _route_length(from_position, candidate)
		if candidate_length < best_length:
			best_length = candidate_length
			best_route = candidate
	return best_route


func _route_stays_outside_stage(from_position: Vector3, route: PackedVector3Array) -> bool:
	var segment_start: Vector3 = from_position
	for point: Vector3 in route:
		if _segment_crosses_stage(segment_start, point):
			return false
		segment_start = point
	return true


func _is_ocean_attack_target(point: Vector3) -> bool:
	var half_length: float = _floor_length * 0.5
	var min_z: float = _floor_center_z - half_length
	var max_z: float = _floor_center_z + half_length
	return (
		absf(point.x) >= StageConstants.FLOOR_HALF_WIDTH
		or point.z <= min_z
		or point.z >= max_z
	)


func _route_length(from_position: Vector3, route: PackedVector3Array) -> float:
	var total: float = 0.0
	var segment_start: Vector3 = from_position
	for point: Vector3 in route:
		total += segment_start.distance_to(point)
		segment_start = point
	return total


func _segment_crosses_stage(from_position: Vector3, to_position: Vector3) -> bool:
	var floor_bottom_y: float = StageConstants.FLOOR_CENTER_Y - StageConstants.FLOOR_THICKNESS * 0.5
	if from_position.y <= floor_bottom_y - UNDER_STAGE_CLEARANCE 			and to_position.y <= floor_bottom_y - UNDER_STAGE_CLEARANCE:
		return false

	var half_length: float = _floor_length * 0.5
	var min_z: float = _floor_center_z - half_length - STAGE_CLEARANCE
	var max_z: float = _floor_center_z + half_length + STAGE_CLEARANCE
	var edge_x: float = StageConstants.FLOOR_HALF_WIDTH + STAGE_CLEARANCE
	for sample_index: int in range(ROUTE_SAMPLE_COUNT + 1):
		var weight: float = float(sample_index) / float(ROUTE_SAMPLE_COUNT)
		var point: Vector3 = from_position.lerp(to_position, weight)
		if absf(point.x) < edge_x and point.z > min_z and point.z < max_z:
			if point.y > floor_bottom_y - UNDER_STAGE_CLEARANCE:
				return true
	return false


func _safe_attack_target(target_position: Vector3) -> Vector3:
	var safe_target: Vector3 = target_position
	safe_target.y = ATTACK_CRUISE_Y
	var half_length: float = _floor_length * 0.5
	var min_z: float = _floor_center_z - half_length
	var max_z: float = _floor_center_z + half_length
	var edge_x: float = StageConstants.FLOOR_HALF_WIDTH + STAGE_CLEARANCE

	if safe_target.x <= -StageConstants.FLOOR_HALF_WIDTH:
		safe_target.x = minf(safe_target.x, -edge_x)
	elif safe_target.x >= StageConstants.FLOOR_HALF_WIDTH:
		safe_target.x = maxf(safe_target.x, edge_x)
	elif safe_target.z <= min_z:
		safe_target.z = minf(safe_target.z, min_z - STAGE_CLEARANCE)
	elif safe_target.z >= max_z:
		safe_target.z = maxf(safe_target.z, max_z + STAGE_CLEARANCE)
	else:
		# 念のため床上座標が渡った場合も、現在位置に近い外周へ退避する。
		var left_distance: float = absf(safe_target.x + StageConstants.FLOOR_HALF_WIDTH)
		var right_distance: float = absf(StageConstants.FLOOR_HALF_WIDTH - safe_target.x)
		var back_distance: float = absf(safe_target.z - min_z)
		var front_distance: float = absf(max_z - safe_target.z)
		var nearest: float = minf(minf(left_distance, right_distance), minf(back_distance, front_distance))
		if is_equal_approx(nearest, left_distance):
			safe_target.x = -edge_x
		elif is_equal_approx(nearest, right_distance):
			safe_target.x = edge_x
		elif is_equal_approx(nearest, back_distance):
			safe_target.z = min_z - STAGE_CLEARANCE
		else:
			safe_target.z = max_z + STAGE_CLEARANCE
	return safe_target


func _keep_clear_of_stage(candidate: Vector3, previous_position: Vector3) -> Vector3:
	var floor_bottom_y: float = StageConstants.FLOOR_CENTER_Y - StageConstants.FLOOR_THICKNESS * 0.5
	if candidate.y <= floor_bottom_y - UNDER_STAGE_CLEARANCE:
		return candidate

	var half_length: float = _floor_length * 0.5
	var min_z: float = _floor_center_z - half_length - STAGE_CLEARANCE
	var max_z: float = _floor_center_z + half_length + STAGE_CLEARANCE
	var edge_x: float = StageConstants.FLOOR_HALF_WIDTH + STAGE_CLEARANCE
	if absf(candidate.x) >= edge_x or candidate.z <= min_z or candidate.z >= max_z:
		return candidate

	var distances: PackedFloat32Array = PackedFloat32Array([
		absf(candidate.x + edge_x),
		absf(edge_x - candidate.x),
		absf(candidate.z - min_z),
		absf(max_z - candidate.z),
	])
	var nearest_side: int = 0
	var nearest_distance: float = distances[0]
	for side_index: int in range(1, distances.size()):
		if distances[side_index] < nearest_distance:
			nearest_distance = distances[side_index]
			nearest_side = side_index

	if absf(previous_position.x) >= edge_x:
		candidate.x = signf(previous_position.x) * edge_x
	elif previous_position.z <= min_z:
		candidate.z = min_z
	elif previous_position.z >= max_z:
		candidate.z = max_z
	else:
		match nearest_side:
			0:
				candidate.x = -edge_x
			1:
				candidate.x = edge_x
			2:
				candidate.z = min_z
			_:
				candidate.z = max_z
	_velocity *= 0.72
	return candidate


func _update_orientation(delta: float) -> void:
	if _velocity.length_squared() < 0.01:
		return
	var portal_entering := (
		is_ghost_ridden and _ghost_phase == GhostRidePhase.PORTAL_ENTERING
	)
	var direction: Vector3 = _velocity.normalized()
	if portal_entering:
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			return
		direction = direction.normalized()
	var target_quaternion: Quaternion = _quat_look_at(
		position,
		position + direction
	)
	if portal_entering:
		# The portal mouth, travel axis, and shark body must share one level
		# orientation. Do not carry charge banking or pitch into the emergence.
		quaternion = target_quaternion
		_bank = 0.0
		model.rotation = Vector3(0.0, PI * 0.5, 0.0)
		return
	var response: float = turn_response * (1.8 if is_attacking else 1.0)
	quaternion = quaternion.slerp(target_quaternion, clampf(delta * response, 0.0, 1.0))

	var current_forward: Vector3 = -basis.z
	var turn_amount: float = current_forward.cross(direction).y
	var target_bank: float = clampf(-turn_amount * 0.7, -0.42, 0.42)
	if is_ghost_ridden and _ghost_phase in [
		GhostRidePhase.ENTERING,
		GhostRidePhase.DEPARTING,
	]:
		target_bank += _ghost_entry_side * sin(_ghost_entry_progress * PI) * 0.16
	_bank = lerpf(_bank, target_bank, clampf(delta * 4.0, 0.0, 1.0))
	var body_pitch: float = clampf(-direction.y * 0.18, -0.16, 0.16)
	if is_ghost_ridden and _ghost_phase in [
		GhostRidePhase.ENTERING,
		GhostRidePhase.DEPARTING,
	]:
		body_pitch -= sin(_ghost_entry_progress * PI) * 0.11
	model.rotation = Vector3(body_pitch, PI * 0.5, _bank)
func _quat_look_at(origin: Vector3, look_target: Vector3) -> Quaternion:
	var direction: Vector3 = origin.direction_to(look_target)
	if direction.length_squared() < 1e-8:
		return quaternion
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(up)) > 0.998:
		up = Vector3.RIGHT
	var z_axis: Vector3 = -direction
	var x_axis: Vector3 = up.cross(z_axis)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.FORWARD.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).get_rotation_quaternion()


func _ambient_angle_step() -> float:
	return 0.035 * signf(swim_speed) if not is_zero_approx(swim_speed) else 0.035


func _ambient_linear_speed() -> float:
	var radius_scale: float = maxf(orbit_radius.x, orbit_radius.y)
	return clampf(absf(swim_speed) * radius_scale * 0.62, 2.4, 7.5)


func _recenter_ambient_path() -> void:
	var offset: Vector3 = Vector3(
		cos(_angle) * orbit_radius.x,
		sin(_angle * 2.0 + phase) * depth_wave,
		sin(_angle) * orbit_radius.y
	)
	_center = position - offset


func _orbit_position(angle: float) -> Vector3:
	var speed_pulse: float = sin(angle * 0.65 + phase) * 0.12
	var lateral_sway: float = sin(_swim_time * 0.55 + phase) * orbit_radius.x * 0.04
	return _center + Vector3(
		cos(angle) * orbit_radius.x + lateral_sway,
		sin(angle * 2.0 + phase) * depth_wave + speed_pulse,
		sin(angle) * orbit_radius.y
	)
