class_name SharkSwimmer
extends Node3D

signal attack_reached(player_index: int)
signal attack_phase_changed(player_index: int, attack_phase: int)

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
const BITE_LUNGE_DURATION: float = 0.18
const JAW_OPEN_DEGREES: float = 28.0
const WAKE_OFFSET_SCALE: float = 4.35

var is_attacking: bool = false
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
var _jaw_skeleton: Skeleton3D = null
var _jaw_bone_index: int = -1
var _jaw_rest_rotation: Quaternion = Quaternion.IDENTITY
var _wake_particles: GPUParticles3D = null
var _surface_spray: GPUParticles3D = null
var _rush_audio: AudioStreamPlayer3D = null
var _impact_audio: AudioStreamPlayer3D = null


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


func _process(delta: float) -> void:
	_swim_time += delta
	if is_attacking:
		_update_attack(delta)
	else:
		_update_ambient_swim(delta)
	_update_orientation(delta)
	_update_arcade_attack_effects(delta)


func begin_attack(
	player_index: int,
	target_position: Vector3,
	floor_center_z: float,
	floor_length: float
) -> bool:
	if is_attacking:
		return false
	_attack_player_index = player_index
	_floor_center_z = floor_center_z
	_floor_length = floor_length
	_attack_target = _safe_attack_target(target_position)
	_build_attack_route(position, _attack_target)
	is_attacking = true
	_bite_timer = 0.0
	_attack_intensity = 0.0
	_jaw_open_amount = 0.0
	_set_attack_phase(AttackPhase.APPROACH)
	animation_player.speed_scale = 1.75
	return true


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
	animation_player.speed_scale = 1.0
	_reset_arcade_attack_effects()
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


func _update_arcade_attack_effects(delta: float) -> void:
	if is_attacking:
		animation_player.speed_scale = lerpf(1.75, 2.35, _attack_intensity)
	if _wake_particles != null:
		_wake_particles.emitting = is_attacking and _attack_intensity > 0.03
		_wake_particles.amount_ratio = clampf(_attack_intensity, 0.0, 1.0)
	if _surface_spray != null:
		_surface_spray.position.y = StageConstants.OCEAN_SURFACE_Y - position.y + 0.12
		_surface_spray.emitting = is_attacking and _attack_intensity > 0.16
		_surface_spray.amount_ratio = clampf((_attack_intensity - 0.12) / 0.88, 0.0, 1.0)
	if _rush_audio != null:
		if is_attacking and _attack_intensity > 0.04:
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
	if not is_attacking:
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


func _play_swim_animation() -> void:
	var animation_names: PackedStringArray = animation_player.get_animation_list()
	for animation_name: StringName in animation_names:
		if animation_name == &"RESET":
			continue
		var animation: Animation = animation_player.get_animation(animation_name)
		if animation == null:
			continue
		animation.loop_mode = Animation.LOOP_LINEAR
		animation_player.play(animation_name, -1.0, animation_speed)
		if animation.length > 0.0:
			var normalized_phase: float = fposmod(phase, TAU) / TAU
			animation_player.seek(normalized_phase * animation.length, true)
		return
	push_warning("Shark swimmer has no playable animation")


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
	if _attack_waypoints.is_empty():
		_finish_attack()
		return

	var waypoint: Vector3 = _attack_waypoints[0]
	var final_leg: bool = _attack_waypoints.size() == 1
	var distance: float = position.distance_to(waypoint)

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
	animation_player.speed_scale = 1.0
	_reset_arcade_attack_effects()
	_recenter_ambient_path()
	attack_reached.emit(reached_player)


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
	var direction: Vector3 = _velocity.normalized()
	var target_quaternion: Quaternion = _quat_look_at(position, position + direction)
	var response: float = turn_response * (1.8 if is_attacking else 1.0)
	quaternion = quaternion.slerp(target_quaternion, clampf(delta * response, 0.0, 1.0))

	var current_forward: Vector3 = -basis.z
	var turn_amount: float = current_forward.cross(direction).y
	var target_bank: float = clampf(-turn_amount * 0.7, -0.42, 0.42)
	_bank = lerpf(_bank, target_bank, clampf(delta * 4.0, 0.0, 1.0))
	var body_pitch: float = clampf(-direction.y * 0.18, -0.16, 0.16)
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
