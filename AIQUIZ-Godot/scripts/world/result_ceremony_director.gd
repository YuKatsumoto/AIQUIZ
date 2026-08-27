class_name ResultCeremonyDirector
extends Node3D

const GRASS_MATERIAL_PATH := "res://assets/BinbunGrass/src/materials/grass_01/grass_01.tres"
const GROUND_MATERIAL_PATH := "res://assets/BinbunGrass/src/materials/grass_01/grass_ground_01.tres"
const EXPLOSION_SCENE := preload(
	"res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_02.tscn"
)
const MEADOW_SIZE := Vector2(20.0, 20.0)
# 草原の手前端をゴール兼ベルト終端へ密着させる（20m / 2 = 10m）。
const MEADOW_CENTER_OFFSET_Z: float = MEADOW_SIZE.y * 0.5
const FLOOR_TOP_Y: float = -1.2
const GHOST_FLOAT_HEIGHT: float = 0.34
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.15, 0.68, 1.0)
const KEY_LIGHT_COLOR := Color(1.0, 0.91, 0.76)
const P1_RIM_COLOR := Color(1.0, 0.34, 0.08)
const P2_RIM_COLOR := Color(0.10, 0.58, 1.0)

var game_state: QuizGameState = null
var player_controller: PlayerController = null
var camera_controller: Node3D = null
var ghost_controller: GhostSharkRideController = null

var _meadow: Node3D = null
var _ghosts: Dictionary = {}
var _ghost_start_positions: Dictionary = {}
var _ghost_handoff_attempted: bool = false
var _last_phase: int = QuizGameState.ResultCeremonyPhase.NONE
var _result_exploded_mask: int = 0
var _winner_emote_started: bool = false
var _effect_nodes: Array[Node] = []
var _debris_nodes: Array[RigidBody3D] = []
var _presentation_lights: Node3D = null
var _key_light: SpotLight3D = null
var _p1_rim_light: OmniLight3D = null
var _p2_rim_light: OmniLight3D = null
var _grandstands: Node3D = null
var _grandstands_were_visible: bool = true
var _stadium_geometry: Array[Node3D] = []
var _stadium_geometry_visibility: Dictionary = {}
var _render_prewarm_active: bool = false


func setup(
		state: QuizGameState,
		players: PlayerController,
		camera_rig: Node3D,
		ghost_ride: GhostSharkRideController) -> void:
	game_state = state
	player_controller = players
	camera_controller = camera_rig
	ghost_controller = ghost_ride


func update_result_ceremony(delta: float) -> void:
	if game_state == null:
		return
	var should_prepare_meadow := (
		game_state.uses_local_result_ceremony()
		and game_state.game_state in [
			Constants.STATE_PRELOADING,
			Constants.STATE_WAITING_START,
			Constants.STATE_FLYOVER,
			Constants.STATE_COUNTDOWN,
			Constants.STATE_PLAYING,
			Constants.STATE_GOAL_RACE,
			Constants.STATE_RESULT_CEREMONY,
			Constants.STATE_CLEAR,
		]
	)
	if should_prepare_meadow:
		_ensure_meadow()
		_ensure_presentation_lights()
		_update_meadow_position()
		_update_presentation_lights(delta)
		_update_grandstand_visibility()
	elif _meadow != null and is_instance_valid(_meadow) and not _render_prewarm_active:
		_meadow.visible = false
		_restore_grandstands()
		if _presentation_lights != null and is_instance_valid(_presentation_lights):
			_presentation_lights.visible = false

	if not game_state.result_presentation_active:
		_last_phase = QuizGameState.ResultCeremonyPhase.NONE
		return

	_ensure_result_ghosts()
	_update_result_ghosts()
	if game_state.result_ceremony_phase != _last_phase:
		_last_phase = game_state.result_ceremony_phase
		_on_phase_changed(_last_phase)
	if game_state.is_result_verdict_visible() and not _winner_emote_started:
		_start_winner_emote()
	_update_winner_emote()


## 草原のMultiMesh構築と初回シェーダー生成を、ゲーム開始時の黒画面内で済ませる。
## ボス問題通過フレームでは表示と位置更新だけになるため、進行中の一瞬停止を防げる。
func begin_render_prewarm() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if game_state == null or not game_state.uses_local_result_ceremony():
		return {"ready": true, "skipped": true, "elapsed_msec": 0.0}
	_render_prewarm_active = true
	_ensure_meadow()
	_ensure_presentation_lights()
	if _meadow != null and is_instance_valid(_meadow):
		_meadow.position = Vector3(0.0, FLOOR_TOP_Y + 0.015, 8.0)
		_meadow.visible = true
	return {
		"ready": _meadow != null and is_instance_valid(_meadow),
		"skipped": false,
		"grass_instances": _grass_instance_count(),
		"elapsed_msec": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func end_render_prewarm() -> void:
	_render_prewarm_active = false
	if _meadow != null and is_instance_valid(_meadow):
		_meadow.visible = false
	if _presentation_lights != null and is_instance_valid(_presentation_lights):
		_presentation_lights.visible = false


func _ensure_meadow() -> void:
	if _meadow != null and is_instance_valid(_meadow):
		_meadow.visible = true
		return
	_meadow = Node3D.new()
	_meadow.name = "ResultMeadow"
	add_child(_meadow)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = MEADOW_SIZE
	ground.mesh = ground_mesh
	var ground_material := load(GROUND_MATERIAL_PATH) as Material
	if ground_material != null:
		var local_ground_material := ground_material.duplicate(true) as Material
		if local_ground_material is ShaderMaterial:
			(local_ground_material as ShaderMaterial).set_shader_parameter(
				"albedo_tint",
				Vector3(0.15, 0.17, 0.08)
			)
		ground.material_override = local_ground_material
	else:
		var fallback_ground := StandardMaterial3D.new()
		fallback_ground.albedo_color = Color(0.27, 0.54, 0.18)
		fallback_ground.roughness = 1.0
		ground.material_override = fallback_ground
	_meadow.add_child(ground)

	var grass := MultiMeshInstance3D.new()
	grass.name = "Grass"
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blade := QuadMesh.new()
	blade.size = Vector2(0.34, 0.62)
	blade.subdivide_width = 2
	blade.subdivide_depth = 2
	blade.center_offset = Vector3(0.0, 0.31, 0.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = blade
	var instance_count := _grass_instance_count()
	multimesh.instance_count = instance_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA1C017
	for index: int in range(instance_count):
		var scale_xz := rng.randf_range(0.72, 1.24)
		var scale_y := rng.randf_range(0.78, 1.34)
		var blade_basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(
			Vector3(scale_xz, scale_y, scale_xz)
		)
		var origin := Vector3(
			rng.randf_range(-MEADOW_SIZE.x * 0.5, MEADOW_SIZE.x * 0.5),
			0.0,
			rng.randf_range(-MEADOW_SIZE.y * 0.5, MEADOW_SIZE.y * 0.5)
		)
		multimesh.set_instance_transform(index, Transform3D(blade_basis, origin))
	grass.multimesh = multimesh
	grass.custom_aabb = AABB(
		Vector3(-MEADOW_SIZE.x * 0.5, -0.1, -MEADOW_SIZE.y * 0.5),
		Vector3(MEADOW_SIZE.x, 1.2, MEADOW_SIZE.y)
	)
	var grass_material := load(GRASS_MATERIAL_PATH) as ShaderMaterial
	if grass_material != null:
		var local_grass_material := grass_material.duplicate(true) as ShaderMaterial
		local_grass_material.set_shader_parameter("wind_velocity", Vector2(0.35, 0.18))
		local_grass_material.set_shader_parameter("albedo_tint", Vector3(0.16, 0.18, 0.07))
		grass.material_override = local_grass_material
	else:
		var fallback_grass := StandardMaterial3D.new()
		fallback_grass.albedo_color = Color(0.34, 0.68, 0.22)
		fallback_grass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		fallback_grass.cull_mode = BaseMaterial3D.CULL_DISABLED
		grass.material_override = fallback_grass
	_meadow.add_child(grass)


func _ensure_presentation_lights() -> void:
	if _presentation_lights != null and is_instance_valid(_presentation_lights):
		_presentation_lights.visible = true
		return
	_presentation_lights = Node3D.new()
	_presentation_lights.name = "ResultPresentationLights"
	add_child(_presentation_lights)

	_key_light = SpotLight3D.new()
	_key_light.name = "CeremonyKey"
	_key_light.light_color = KEY_LIGHT_COLOR
	_key_light.light_energy = 0.0
	_key_light.light_specular = 0.46
	_key_light.shadow_enabled = false
	_key_light.spot_range = 12.5
	_key_light.spot_angle = 52.0
	_key_light.spot_attenuation = 0.72
	_presentation_lights.add_child(_key_light)

	_p1_rim_light = _create_rim_light("P1Rim", P1_RIM_COLOR)
	_p2_rim_light = _create_rim_light("P2Rim", P2_RIM_COLOR)


func _create_rim_light(light_name: String, color: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = 0.0
	light.light_specular = 0.34
	light.shadow_enabled = false
	light.omni_range = 6.8
	light.omni_attenuation = 1.25
	_presentation_lights.add_child(light)
	return light


func _update_presentation_lights(delta: float) -> void:
	if (
		_presentation_lights == null
		or not is_instance_valid(_presentation_lights)
		or _key_light == null
	):
		return
	_presentation_lights.visible = true
	var p1_position := _result_player_global_position(1)
	var p2_position := _result_player_global_position(2)
	var midpoint := (p1_position + p2_position) * 0.5
	_key_light.global_position = midpoint + Vector3(4.8, 5.4, 4.2)
	_key_light.look_at(midpoint + Vector3.UP * 0.72, Vector3.UP)
	_p1_rim_light.global_position = p1_position + Vector3(-1.15, 2.0, -1.65)
	_p2_rim_light.global_position = p2_position + Vector3(1.15, 2.0, -1.65)

	var presentation_amount := 0.0
	match game_state.result_ceremony_phase:
		QuizGameState.ResultCeremonyPhase.ASSEMBLE:
			presentation_amount = 0.12
		QuizGameState.ResultCeremonyPhase.MEADOW_RUN:
			presentation_amount = 0.30
		QuizGameState.ResultCeremonyPhase.SCORE_ROLL:
			presentation_amount = smoothstep(
				0.0,
				1.0,
				clampf(game_state.result_ceremony_phase_elapsed / 0.65, 0.0, 1.0)
			)
		QuizGameState.ResultCeremonyPhase.VERDICT, QuizGameState.ResultCeremonyPhase.EFFECT:
			presentation_amount = 1.0
		QuizGameState.ResultCeremonyPhase.INTERACTIVE:
			presentation_amount = 0.86

	var night_amount := _result_night_amount()
	var quality := GraphicsQuality.normalize(GameManager.graphics_quality)
	var quality_factor := 0.72 if quality == GraphicsQuality.LOW else (
		1.0 if quality == GraphicsQuality.HIGH else 0.86
	)
	var key_target := presentation_amount * quality_factor * lerpf(0.82, 1.58, night_amount)
	var rim_target := presentation_amount * quality_factor * lerpf(0.48, 1.02, night_amount)
	if quality == GraphicsQuality.LOW:
		rim_target *= 0.48
	var light_blend := 1.0 - exp(-delta * 5.8)
	_key_light.light_energy = lerpf(_key_light.light_energy, key_target, light_blend)
	_p1_rim_light.light_energy = lerpf(_p1_rim_light.light_energy, rim_target, light_blend)
	_p2_rim_light.light_energy = lerpf(_p2_rim_light.light_energy, rim_target, light_blend)


func _result_night_amount() -> float:
	var world_root := get_parent()
	if world_root == null:
		return 0.0
	var stage := world_root.get_node_or_null("StageEnvironment")
	if stage == null:
		return 0.0
	var weather: Variant = stage.get("weather_cycle")
	if weather is Node:
		return clampf(float((weather as Node).get("night_amount")), 0.0, 1.0)
	return 0.0


func _grass_instance_count() -> int:
	match GraphicsQuality.normalize(GameManager.graphics_quality):
		GraphicsQuality.LOW:
			return 2500
		GraphicsQuality.HIGH:
			return 10000
		_:
			return 6000


func _update_meadow_position() -> void:
	if _meadow == null or not is_instance_valid(_meadow):
		return
	_meadow.position = Vector3(
		0.0,
		FLOOR_TOP_Y + 0.015,
		_result_goal_world_z() - game_state.world_scroll_z + MEADOW_CENTER_OFFSET_Z
	)


func _result_goal_world_z() -> float:
	if game_state.goal_z > 0.0:
		return game_state.goal_z
	var tuning := game_state.tuning
	return tuning.wall_start_z + game_state.target_count * tuning.wall_spacing + 15.0


func _update_grandstand_visibility() -> void:
	if _grandstands == null or not is_instance_valid(_grandstands):
		var world_root := get_parent()
		var stage := world_root.get_node_or_null("StageEnvironment") if world_root != null else null
		_grandstands = stage.get_node_or_null("Grandstands") as Node3D if stage != null else null
		if _grandstands != null:
			_grandstands_were_visible = _grandstands.visible
		if stage != null and _stadium_geometry.is_empty():
			for child: Node in stage.get_children():
				var visual := child as Node3D
				if visual == null or visual.name == "Ocean" or visual == _grandstands:
					continue
				if visual is MeshInstance3D or visual.name == "ConveyorEdgeLights":
					_stadium_geometry.append(visual)
					_stadium_geometry_visibility[visual.get_instance_id()] = visual.visible
	if _grandstands == null:
		return
	var meadow_only := (
		game_state.result_presentation_active
		and game_state.result_ceremony_phase >= QuizGameState.ResultCeremonyPhase.MEADOW_RUN
	)
	_grandstands.visible = not meadow_only
	for visual: Node3D in _stadium_geometry:
		if visual != null and is_instance_valid(visual):
			visual.visible = not meadow_only


func _restore_grandstands() -> void:
	if _grandstands != null and is_instance_valid(_grandstands):
		_grandstands.visible = _grandstands_were_visible
	for visual: Node3D in _stadium_geometry:
		if visual != null and is_instance_valid(visual):
			visual.visible = bool(_stadium_geometry_visibility.get(visual.get_instance_id(), true))


func _ensure_result_ghosts() -> void:
	if game_state.result_ghost_mask == 0 or player_controller == null:
		return
	if not _ghost_handoff_attempted:
		_ghost_handoff_attempted = true
		var released: Node3D = null
		if ghost_controller != null:
			released = ghost_controller.begin_result_dismount(self)
		if released != null and is_instance_valid(released):
			_register_ghost(game_state.result_ghost_mask, released)

	for player_index: int in [1, 2]:
		var bit: int = 1 if player_index == 1 else 2
		if (game_state.result_ghost_mask & bit) == 0 or _ghosts.has(player_index):
			continue
		var rider := player_controller.create_ghost_rider_visual(player_index)
		if rider == null:
			continue
		add_child(rider)
		var target := _result_player_global_position(player_index)
		rider.global_position = target + Vector3(0.0, 1.45, -1.0)
		_register_ghost(bit, rider)


func _register_ghost(bit_or_mask: int, rider: Node3D) -> void:
	var player_index := 1 if (bit_or_mask & 1) != 0 else 2
	# A controller handoff can only own one rider; use its authored identity when available.
	if rider.name.to_lower().contains("p2"):
		player_index = 2
	elif rider.name.to_lower().contains("p1"):
		player_index = 1
	player_controller.make_ghost_rider_translucent(rider)
	_ghosts[player_index] = rider
	_ghost_start_positions[player_index] = rider.global_position


func _update_result_ghosts() -> void:
	for player_index_variant: Variant in _ghosts.keys():
		var player_index := int(player_index_variant)
		var rider := _ghosts[player_index] as Node3D
		if rider == null or not is_instance_valid(rider):
			continue
		if (_result_exploded_mask & (1 if player_index == 1 else 2)) != 0:
			continue
		var target := _result_player_global_position(player_index)
		if game_state.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.ASSEMBLE:
			var start: Vector3 = _ghost_start_positions.get(player_index, target)
			var progress := game_state.get_result_phase_progress()
			var eased := smoothstep(0.0, 1.0, progress)
			rider.global_position = start.lerp(target, eased)
			rider.global_position.y += sin(progress * PI) * 0.65
		else:
			rider.global_position = target
			if game_state.result_ceremony_phase >= QuizGameState.ResultCeremonyPhase.SCORE_ROLL:
				rider.global_position.y += sin(game_state.result_ceremony_elapsed * 2.4) * 0.045
		rider.global_rotation = Vector3.ZERO
		var moving := game_state.result_ceremony_phase in [
			QuizGameState.ResultCeremonyPhase.ASSEMBLE,
			QuizGameState.ResultCeremonyPhase.MEADOW_RUN,
		]
		player_controller.apply_ghost_rider_result_pose(
			rider,
			player_index,
			moving,
			game_state.result_ceremony_elapsed
		)


func _result_player_global_position(player_index: int) -> Vector3:
	var local_position := game_state.get_result_player_local_position(player_index)
	local_position.y += GHOST_FLOAT_HEIGHT
	var world_root := get_parent() as Node3D
	return world_root.to_global(local_position) if world_root != null else local_position


func _on_phase_changed(phase: int) -> void:
	match phase:
		QuizGameState.ResultCeremonyPhase.SCORE_ROLL:
			AudioManager.play_result_roll()
		QuizGameState.ResultCeremonyPhase.VERDICT:
			AudioManager.play_result_lock()
		QuizGameState.ResultCeremonyPhase.EFFECT:
			_play_verdict_effects()


func _play_verdict_effects() -> void:
	if game_state.result_winner == 1:
		_explode_player(2)
	elif game_state.result_winner == 2:
		_explode_player(1)
	else:
		_explode_player(1)
		_explode_player(2)
	game_state.camera_shake = maxf(game_state.camera_shake, 1.35)
	AudioManager.play_result_explosion(game_state.result_winner == 0)


func _start_winner_emote() -> void:
	_winner_emote_started = true
	if game_state.result_winner == 1:
		game_state.p1_emote = game_state.get_result_winner_emote(1)
		game_state.p1_emote_lock_timer = 999.0
	elif game_state.result_winner == 2:
		game_state.p2_emote = game_state.get_result_winner_emote(2)
		game_state.p2_emote_lock_timer = 999.0


func _explode_player(player_index: int) -> void:
	var bit: int = 1 if player_index == 1 else 2
	if (_result_exploded_mask & bit) != 0:
		return
	_result_exploded_mask |= bit
	var is_ghost := (game_state.result_ghost_mask & bit) != 0
	var effect_position := _result_player_global_position(player_index)
	if is_ghost:
		var rider := _ghosts.get(player_index) as Node3D
		if rider != null and is_instance_valid(rider):
			effect_position = rider.global_position + Vector3.UP * 0.65
			_explode_ghost_meshes(rider, player_index)
	else:
		effect_position = _living_player_effect_position(player_index)
		player_controller.play_result_explosion(player_index)
	_spawn_purchased_explosion(effect_position, player_index, is_ghost)


func _living_player_effect_position(player_index: int) -> Vector3:
	if player_controller == null:
		return _result_player_global_position(player_index)
	return player_controller.get_death_presentation_position(player_index == 1)


func _spawn_purchased_explosion(position_value: Vector3, player_index: int, is_ghost: bool) -> void:
	var effect := EXPLOSION_SCENE.instantiate() as Node3D
	if effect == null:
		return
	add_child(effect)
	effect.global_position = position_value
	effect.scale = Vector3.ONE * (1.35 if not is_ghost else 1.18)
	var player_color := P1_COLOR if player_index == 1 else P2_COLOR
	effect.set("primary_color", player_color)
	effect.set("secondary_color", Color(1.0, 0.24, 0.04))
	effect.set("tertiary_color", Color(0.18, 0.18, 0.20))
	var ratio := 0.45 if GraphicsQuality.normalize(GameManager.graphics_quality) == GraphicsQuality.LOW else (
		1.0 if GraphicsQuality.normalize(GameManager.graphics_quality) == GraphicsQuality.HIGH else 0.72
	)
	for child: Node in effect.find_children("*", "GPUParticles3D", true, false):
		(child as GPUParticles3D).amount_ratio = ratio
	_effect_nodes.append(effect)
	# The authored scene loops its main clip for 3.2 s. Retire it after the
	# readable blast/smoke beat so no particle tint survives into UI control.
	var timer := get_tree().create_timer(1.95)
	timer.timeout.connect(_cleanup_effect_instance.bind(effect.get_instance_id()))


func _cleanup_effect_instance(effect_id: int) -> void:
	var effect := instance_from_id(effect_id) as Node
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
	for index: int in range(_effect_nodes.size() - 1, -1, -1):
		var tracked := _effect_nodes[index]
		if not is_instance_valid(tracked) or tracked.get_instance_id() == effect_id:
			_effect_nodes.remove_at(index)


func _explode_ghost_meshes(rider: Node3D, player_index: int) -> void:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in rider.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.visible and mesh_instance.mesh != null:
			meshes.append(mesh_instance)
	var center := rider.global_position + Vector3.UP * 0.7
	var debris_ids := PackedInt64Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB1057 + player_index * 97
	for mesh_instance: MeshInstance3D in meshes:
		var body := RigidBody3D.new()
		body.name = "ResultGhostShardP%d" % player_index
		body.mass = rng.randf_range(0.18, 0.34)
		body.gravity_scale = 1.55
		body.collision_layer = 0
		body.collision_mask = 1
		var visual := MeshInstance3D.new()
		visual.mesh = mesh_instance.mesh
		visual.material_override = mesh_instance.material_override
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh_instance.mesh.get_aabb().size.max(Vector3.ONE * 0.08)
		collision.shape = shape
		body.add_child(collision)
		get_parent().add_child(body)
		body.global_transform = mesh_instance.global_transform
		var direction := (mesh_instance.global_position - center).normalized()
		if direction.length_squared() < 0.01:
			direction = Vector3(rng.randf_range(-1.0, 1.0), 0.4, rng.randf_range(-1.0, 1.0)).normalized()
		body.linear_velocity = direction * rng.randf_range(5.5, 9.0) + Vector3.UP * rng.randf_range(4.0, 7.0)
		body.angular_velocity = Vector3(
			rng.randf_range(-8.0, 8.0),
			rng.randf_range(-8.0, 8.0),
			rng.randf_range(-8.0, 8.0)
		)
		debris_ids.append(body.get_instance_id())
		_debris_nodes.append(body)
	rider.visible = false
	var timer := get_tree().create_timer(4.5)
	timer.timeout.connect(_cleanup_debris_instances.bind(debris_ids))


func _cleanup_debris_instances(debris_ids: PackedInt64Array) -> void:
	for debris_id: int in debris_ids:
		var body := instance_from_id(debris_id) as RigidBody3D
		if body != null and is_instance_valid(body):
			body.queue_free()
	for index: int in range(_debris_nodes.size() - 1, -1, -1):
		var tracked := _debris_nodes[index]
		if not is_instance_valid(tracked) or tracked.get_instance_id() in debris_ids:
			_debris_nodes.remove_at(index)


func _update_winner_emote() -> void:
	if not _winner_emote_started:
		return
	var winner := game_state.result_winner
	if winner == 0 or (game_state.result_ghost_mask & (1 if winner == 1 else 2)) == 0:
		return
	var rider := _ghosts.get(winner) as Node3D
	if rider != null and is_instance_valid(rider) and rider.visible:
		player_controller.apply_ghost_rider_emote_pose(
			rider,
			winner,
			game_state.get_result_winner_emote(winner)
		)


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": game_state.result_ceremony_phase if game_state != null else -1,
		"meadow_ready": _meadow != null and is_instance_valid(_meadow),
		"grass_instances": (
			((_meadow.get_node_or_null("Grass") as MultiMeshInstance3D).multimesh.instance_count)
			if _meadow != null and _meadow.get_node_or_null("Grass") is MultiMeshInstance3D
			else 0
		),
		"ghost_count": _ghosts.size(),
		"effect_count": _effect_nodes.size(),
		"debris_count": _debris_nodes.size(),
		"exploded_mask": _result_exploded_mask,
		"light_count": (
			_presentation_lights.get_child_count()
			if _presentation_lights != null and is_instance_valid(_presentation_lights)
			else 0
		),
	}


func force_cleanup() -> void:
	_render_prewarm_active = false
	_restore_grandstands()
	_grandstands = null
	_stadium_geometry.clear()
	_stadium_geometry_visibility.clear()
	for rider_variant: Variant in _ghosts.values():
		var rider := rider_variant as Node3D
		if rider != null and is_instance_valid(rider):
			rider.queue_free()
	_ghosts.clear()
	_ghost_start_positions.clear()
	for effect: Node in _effect_nodes:
		if effect != null and is_instance_valid(effect):
			effect.queue_free()
	_effect_nodes.clear()
	for body: RigidBody3D in _debris_nodes:
		if body != null and is_instance_valid(body):
			body.queue_free()
	_debris_nodes.clear()
	if _meadow != null and is_instance_valid(_meadow):
		_meadow.queue_free()
	_meadow = null
	if _presentation_lights != null and is_instance_valid(_presentation_lights):
		_presentation_lights.queue_free()
	_presentation_lights = null
	_key_light = null
	_p1_rim_light = null
	_p2_rim_light = null
	_ghost_handoff_attempted = false
	_result_exploded_mask = 0
	_winner_emote_started = false
	_last_phase = QuizGameState.ResultCeremonyPhase.NONE
	if player_controller != null:
		player_controller.reset_result_presentation()
