class_name GhostRiderPresentation
extends Node3D

## GOSTRIDER の乗り手の「見せ方」。GhostSharkRideController がフェーズごとに呼ぶ。
## - 演技（GhostRiderPerformance）をフェーズの時刻で乗り手に当てる（照準中・構え・突進は短いクリップを混ぜて切り替える）
## - 魂の向き（進む向きへ振り向き、曲がりで傾き、着く直前にサメのソケットの向きへそろう）と大きさ（形になりながら育つ）
## - 魂の尾、目覚め・着座・柱の瞬間の光（輪・殻・火花・灯り）
## 乗り手とサメの寿命は GhostSharkRideController が持つ。ここは見た目だけを足し、外では何も消さない。

## 演技の中の拍（秒。GhostRiderPerformance のクリップの時刻）。
signal beat(beat_name: StringName, world_position: Vector3)

const FX_SHADER := preload("res://assets/ghost_rider/ghost_fx_additive.gdshader")
const AWAKEN_TIME := 1.27
## 目覚めの音（ghost_awaken）は吸い込みの 0.16 秒あとに和音が鳴るので、そのぶん先に鳴らす。
const AWAKEN_SOUND_LEAD := 0.16
const ERUPT_TIME := 5.13
const EMERGE_TIME := 0.55
const RIDE_BLEND_SECONDS := 0.16
const LOWER_BODY: Array = ["pelvis", "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe"]
const RIDE_IDLE := &"idle"
const RIDE_WINDUP := &"windup"
const RIDE_DASH := &"dash"
## 魂の向き：進む向きへ振り向く速さ（1/秒）と、上下の向きをどれだけ根元に入れるか（残りは演技の腰の傾き）。
const SOUL_TURN_RATE := 5.5
const SOUL_PITCH_SHARE := 0.32
const SOUL_BANK_PER_TURN := 0.16
const SOUL_BANK_LIMIT := 0.55
## 飛び終わりの割合のここから、ソケットの向きへそろえ始める。
const SOUL_ALIGN_START := 0.78

var player_controller: PlayerController = null

var _rider: Node3D = null
var _player_index := 0
var _color := Color(1.0, 0.62, 0.26, 1.0)
var _world_scale := 0.6
var _soul_yaw := 0.0
var _soul_yaw_ready := false
var _soul_bank := 0.0
var _last_perf_time := -1.0
var _last_pose: Dictionary = {}
var _ride_state: StringName = &""
var _ride_time := 0.0
var _ride_from: Dictionary = {}
var _ride_blend := 1.0
var _flash := 0.0
var _trail: GhostSoulTrail = null
var _effects: Array[Dictionary] = []
## 魂が小窓だけに映っている間（レイヤー 20）は、光も同じレイヤーに置く（メイン画面に光だけ浮かない）。
var _presentation_only := false


func _ready() -> void:
	_trail = GhostSoulTrail.new()
	_trail.name = "GhostSoulTrail"
	add_child(_trail)
	_apply_layers(_trail)


func set_presentation_only(presentation_only: bool) -> void:
	if _presentation_only == presentation_only:
		return
	_presentation_only = presentation_only
	_apply_layers(_trail)


func _apply_layers(node: Node) -> void:
	if node == null:
		return
	var visual := node as VisualInstance3D
	if visual != null:
		visual.layers = 0
		visual.set_layer_mask_value(1, not _presentation_only)
		visual.set_layer_mask_value(GhostSharkRideController.SOUL_PRESENTATION_RENDER_LAYER, _presentation_only)
	for child: Node in node.get_children():
		_apply_layers(child)


func begin(rider: Node3D, player_index: int, world_scale: float, start_yaw: float) -> void:
	_rider = rider
	_player_index = player_index
	_color = (
		PlayerController.GHOST_RIDER_RIM_P1 if player_index == 1 else PlayerController.GHOST_RIDER_RIM_P2
	)
	_world_scale = maxf(0.05, world_scale)
	_soul_yaw = start_yaw
	_soul_yaw_ready = true
	_soul_bank = 0.0
	_last_perf_time = -1.0
	_last_pose = {}
	_ride_state = &""
	_ride_time = 0.0
	_ride_from = {}
	_ride_blend = 1.0
	_flash = 0.0
	if _trail != null:
		_trail.clear()
		_trail.emitting = false
		_trail.set_trail_color(_color)
		_trail.color = _color


func end() -> void:
	_rider = null
	_ride_state = &""
	if _trail != null:
		_trail.emitting = false
	# 光の輪・火花は寿命まで残す（乗り手が消えても、出た光は自然に消える）。


func world_scale() -> float:
	return _world_scale


func player_color() -> Color:
	return _color


# ------------------------------------------------------------------ 演技

## 脱落〜発進（DEATH_HOLD〜ENTERING）。phase_elapsed はそのフェーズに入ってからの秒。
func apply_heroic(phase_name: String, phase_elapsed: float) -> void:
	if not _has_rider():
		return
	var t := GhostRiderPerformance.performance_time(phase_name, phase_elapsed)
	var pose := GhostRiderPerformance.sample(GhostRiderPerformance.CLIP_PERFORMANCE, t)
	if not pose.is_empty():
		player_controller.apply_ghost_rider_performance_pose(_rider, pose)
		_last_pose = pose
	_fire_beats(t)
	_last_perf_time = t


## 照準・構え・突進・戻り（AIMING〜COOLDOWN）。emote_active のときは下半身（腰と脚）だけ当てる。
func update_ride(delta: float, state: StringName, emote_active: bool) -> void:
	if not _has_rider():
		return
	if state != _ride_state:
		_ride_from = _last_pose
		_ride_blend = 0.0 if not _ride_from.is_empty() else 1.0
		_ride_state = state
		_ride_time = 0.0
	_ride_time += delta
	var clip := GhostRiderPerformance.CLIP_IDLE
	match state:
		RIDE_WINDUP:
			clip = GhostRiderPerformance.CLIP_WINDUP
		RIDE_DASH:
			clip = GhostRiderPerformance.CLIP_DASH
	var pose := GhostRiderPerformance.sample(clip, _ride_time, state == RIDE_IDLE)
	if _ride_blend < 1.0:
		_ride_blend = minf(1.0, _ride_blend + delta / RIDE_BLEND_SECONDS)
		pose = GhostRiderPerformance.blend_poses(_ride_from, pose, smoothstep(0.0, 1.0, _ride_blend))
	if pose.is_empty():
		return
	if emote_active:
		player_controller.apply_ghost_rider_performance_pose(_rider, pose, LOWER_BODY)
	else:
		player_controller.apply_ghost_rider_performance_pose(_rider, pose)
	_last_pose = pose


func _fire_beats(t: float) -> void:
	if _last_perf_time < 0.0:
		return
	for entry: Array in [
		[EMERGE_TIME, &"emerge"],
		[AWAKEN_TIME - AWAKEN_SOUND_LEAD, &"awaken_sound"],
		[AWAKEN_TIME, &"awaken"],
		[ERUPT_TIME, &"erupt"],
	]:
		var at: float = entry[0]
		if _last_perf_time < at and t >= at:
			beat.emit(entry[1], chest_position())


# ------------------------------------------------------------------ 魂の向きと大きさ

## 魂の形になりかけの大きさ（脱落の場所で小さく丸まって出て、目覚めるまでに育つ）。
func soul_scale_at(performance_time: float) -> float:
	if performance_time < EMERGE_TIME:
		return lerpf(0.34, 0.58, smoothstep(0.0, EMERGE_TIME, performance_time))
	return lerpf(0.58, 1.0, smoothstep(EMERGE_TIME, AWAKEN_TIME + 0.05, performance_time))


## 魂を path_position に置き、look_position の向きへ振り向かせる。progress は飛ぶ道のりの割合（0〜1）。
## 道のりの終わりで、乗り手の向きを mount_basis（サメのソケット）へそろえる。
func place_soul(
	delta: float,
	path_position: Vector3,
	look_position: Vector3,
	progress: float,
	mount_basis: Basis,
	performance_time: float
) -> void:
	if not _has_rider():
		return
	var travel := look_position - path_position
	var flat := Vector3(travel.x, 0.0, travel.z)
	var turn := 0.0
	if flat.length_squared() > 0.000025:
		var target_yaw := atan2(flat.x, flat.z)
		if not _soul_yaw_ready:
			_soul_yaw = target_yaw
			_soul_yaw_ready = true
		var previous := _soul_yaw
		_soul_yaw = lerp_angle(_soul_yaw, target_yaw, 1.0 - exp(-SOUL_TURN_RATE * delta))
		turn = angle_difference(previous, _soul_yaw) / maxf(delta, 0.0001)
	var bank_target := clampf(-turn * SOUL_BANK_PER_TURN, -SOUL_BANK_LIMIT, SOUL_BANK_LIMIT)
	_soul_bank = lerpf(_soul_bank, bank_target, 1.0 - exp(-4.0 * delta))
	var vertical := 0.0
	if travel.length_squared() > 0.000025:
		vertical = clampf(travel.normalized().y, -1.0, 1.0)
	# 乗り手の正面は +Z。上へ進むときは前を上げる（X 回りの負）。体を水平に倒すのは演技の腰の仕事。
	var flight_basis := (
		Basis(Vector3.UP, _soul_yaw)
		* Basis(Vector3.RIGHT, -asin(vertical) * SOUL_PITCH_SHARE)
		* Basis(Vector3.BACK, _soul_bank)
	)
	var align := smoothstep(SOUL_ALIGN_START, 1.0, progress)
	var final_basis := flight_basis
	if align > 0.0:
		final_basis = Basis(
			Quaternion(flight_basis.orthonormalized()).slerp(Quaternion(mount_basis.orthonormalized()), align)
		)
	var size := _world_scale * soul_scale_at(performance_time)
	_rider.global_transform = Transform3D(final_basis.orthonormalized().scaled(Vector3.ONE * size), path_position)


## 魂を出す前（脱落の場所）。向きは出した向きのまま、大きさだけ育てる。
func hold_soul(position: Vector3, performance_time: float) -> void:
	if not _has_rider():
		return
	var size := _world_scale * soul_scale_at(performance_time)
	var basis := Basis(Vector3.UP, _soul_yaw).scaled(Vector3.ONE * size)
	_rider.global_transform = Transform3D(basis, position)


## 胸のあたり（尾の付け根・光の中心）。
func chest_position() -> Vector3:
	if not _has_rider():
		return global_position
	var parts: Dictionary = _rider.get_meta("ghost_mount_parts", {})
	var spine := parts.get("spine") as Node3D
	if spine != null:
		return spine.global_transform * Vector3(0.0, 0.2, 0.0)
	return _rider.global_position


# ------------------------------------------------------------------ 毎フレーム（尾・光）

func update_effects(delta: float, trail_emitting: bool) -> void:
	if _trail != null:
		_trail.emitting = trail_emitting and _has_rider()
		var anchor := chest_position() if _has_rider() else Vector3.ZERO
		if _has_rider() or not _trail.is_idle():
			_trail.step(delta, anchor, _world_scale / 0.6)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.5)
		if _has_rider():
			player_controller.set_ghost_rider_shader_parameter(_rider, &"flash", _flash)
	_update_spawned(delta)


## 乗り手の白い光（目覚め・着座・柱）。
func flash_rider(strength: float) -> void:
	_flash = maxf(_flash, clampf(strength, 0.0, 1.0))
	if _has_rider():
		player_controller.set_ghost_rider_shader_parameter(_rider, &"flash", _flash)


## 脱落の場所に魂が出る：小さな光の殻と、上へ昇る光の粒。
func play_emerge(position: Vector3) -> void:
	_spawn_shell(position, 0.12, 0.85 * _world_scale / 0.6, 0.5, _color.lerp(Color.WHITE, 0.3), 1.3, 3.0)
	_spawn_motes(position, 26, Vector3.UP, 2.6, 0.9)
	_spawn_light(position, 3.2, 3.5, 0.5)


## 目覚め：光の殻が広がり、輪が 2 本走る。
func play_awaken(position: Vector3, camera_facing: Vector3) -> void:
	var size := _world_scale / 0.6
	_spawn_shell(position, 0.2 * size, 1.25 * size, 0.45, _color.lerp(Color.WHITE, 0.5), 1.5, 3.2)
	_spawn_ring(position, camera_facing, 0.22 * size, 1.25 * size, 0.42, _color.lerp(Color.WHITE, 0.25), 2.0, 0.04 * size)
	_spawn_ring(position, Vector3.UP, 0.2 * size, 1.5 * size, 0.42, _color, 2.0, 0.04 * size)
	_spawn_motes(position, 34, Vector3.UP, 3.4, 0.8)
	_spawn_light(position, 5.0, 4.5, 0.45)
	flash_rider(0.7)


## 着座：鞍の高さで横に走る衝撃の輪、白い殻、火花、強い灯り。
func play_mount_impact(position: Vector3, up: Vector3) -> void:
	var size := _world_scale / 0.6
	_spawn_ring(position, up, 0.35 * size, 3.6 * size, 0.6, _color.lerp(Color.WHITE, 0.2), 2.0, 0.08 * size)
	_spawn_ring(position, up, 0.2 * size, 1.8 * size, 0.3, _color.lerp(Color.WHITE, 0.5), 1.3, 0.03 * size)
	_spawn_shell(position, 0.2 * size, 0.6 * size, 0.18, _color.lerp(Color.WHITE, 0.5), 0.8, 3.4)
	_spawn_sparks(position, up, 36, 7.0 * size)
	_spawn_light(position, 6.0, 6.0, 0.35)
	flash_rider(0.45)


## 柱が立つ：乗り手の拳から昇る光の粒と、足元の輪。
func play_erupt(position: Vector3, up: Vector3) -> void:
	var size := _world_scale / 0.6
	_spawn_ring(position, up, 0.3 * size, 1.7 * size, 0.55, _color.lerp(Color.WHITE, 0.3), 1.6, 0.035 * size)
	_spawn_motes(position, 40, up, 5.0, 1.0)
	flash_rider(0.35)


# ------------------------------------------------------------------ 光の部品

func _fx_material(color: Color, energy: float, fresnel_power: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FX_SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("fresnel_power", fresnel_power)
	material.set_shader_parameter("opacity", 1.0)
	return material


func _spawn_ring(
	position: Vector3,
	normal: Vector3,
	start_radius: float,
	end_radius: float,
	duration: float,
	color: Color,
	energy: float,
	thickness: float
) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "GhostFxRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - 0.5
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 6
	ring.mesh = torus
	var material := _fx_material(color, energy, 0.0)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	add_child(ring)
	_apply_layers(ring)
	var axis := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var ring_basis := Basis(Quaternion(Vector3.UP, axis))
	ring.global_transform = Transform3D(ring_basis, position)
	_effects.append({
		"node": ring,
		"kind": "ring",
		"age": 0.0,
		"duration": duration,
		"from": start_radius,
		"to": end_radius,
		"thickness": thickness,
		"basis": ring_basis,
		"material": material,
	})


func _spawn_shell(
	position: Vector3,
	start_radius: float,
	end_radius: float,
	duration: float,
	color: Color,
	energy: float,
	fresnel_power: float
) -> void:
	var shell := MeshInstance3D.new()
	shell.name = "GhostFxShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	shell.mesh = sphere
	var material := _fx_material(color, energy, fresnel_power)
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.top_level = true
	add_child(shell)
	_apply_layers(shell)
	shell.global_position = position
	_effects.append({
		"node": shell,
		"kind": "shell",
		"age": 0.0,
		"duration": duration,
		"from": start_radius,
		"to": end_radius,
		"material": material,
	})


func _spawn_light(position: Vector3, energy: float, light_range: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.name = "GhostFxLight"
	light.light_color = _color.lerp(Color.WHITE, 0.3)
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	light.top_level = true
	add_child(light)
	_apply_layers(light)
	light.global_position = position
	_effects.append({"node": light, "kind": "light", "age": 0.0, "duration": duration, "energy": energy})


func _spawn_sparks(position: Vector3, up: Vector3, count: int, speed: float) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "GhostFxSparks"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = GraphicsQuality.particle_amount(count, GameManager.graphics_quality)
	particles.lifetime = 0.55
	particles.local_coords = false
	particles.top_level = true
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var process := ParticleProcessMaterial.new()
	process.direction = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	process.spread = 80.0
	process.flatness = 0.55
	process.initial_velocity_min = speed * 0.45
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.damping_min = 2.0
	process.damping_max = 4.5
	process.particle_flag_align_y = true
	process.scale_min = 0.6
	process.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.25, _color.lerp(Color.WHITE, 0.3))
	ramp.set_color(2, Color(_color.r, _color.g, _color.b, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	particles.process_material = process
	var spark := BoxMesh.new()
	spark.size = Vector3(0.035, 0.32, 0.035) * maxf(0.6, _world_scale / 0.6)
	var vertex_material := StandardMaterial3D.new()
	vertex_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vertex_material.vertex_color_use_as_albedo = true
	vertex_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vertex_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	vertex_material.emission_enabled = true
	vertex_material.emission = _color.lerp(Color.WHITE, 0.4)
	vertex_material.emission_energy_multiplier = 3.0
	vertex_material.disable_fog = true
	spark.material = vertex_material
	particles.draw_pass_1 = spark
	add_child(particles)
	_apply_layers(particles)
	particles.global_position = position
	particles.emitting = true
	_effects.append({"node": particles, "kind": "particles", "age": 0.0, "duration": 1.2})


func _spawn_motes(position: Vector3, count: int, up: Vector3, speed: float, lifetime: float) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "GhostFxMotes"
	particles.one_shot = true
	particles.explosiveness = 0.75
	particles.amount = GraphicsQuality.particle_amount(count, GameManager.graphics_quality)
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.top_level = true
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var process := ParticleProcessMaterial.new()
	process.direction = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	process.spread = 40.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35 * _world_scale / 0.6
	process.initial_velocity_min = speed * 0.35
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, 1.5, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(2, Color(_color.r, _color.g, _color.b, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	particles.process_material = process
	var mote := SphereMesh.new()
	mote.radius = 0.045
	mote.height = 0.09
	mote.radial_segments = 8
	mote.rings = 4
	var mote_material := StandardMaterial3D.new()
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.vertex_color_use_as_albedo = true
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote_material.disable_fog = true
	mote.material = mote_material
	particles.draw_pass_1 = mote
	add_child(particles)
	_apply_layers(particles)
	particles.global_position = position
	particles.emitting = true
	_effects.append({"node": particles, "kind": "particles", "age": 0.0, "duration": lifetime + 0.4})


func _update_spawned(delta: float) -> void:
	for index: int in range(_effects.size() - 1, -1, -1):
		var effect: Dictionary = _effects[index]
		var node := effect.node as Node3D
		effect.age = float(effect.age) + delta
		var progress := clampf(float(effect.age) / maxf(0.001, float(effect.duration)), 0.0, 1.0)
		if node == null or not is_instance_valid(node):
			_effects.remove_at(index)
			continue
		match str(effect.kind):
			"ring":
				var eased := 1.0 - pow(1.0 - progress, 3.0)
				var radius := lerpf(float(effect.from), float(effect.to), eased)
				var thickness := float(effect.thickness) * (1.0 - progress * 0.6)
				# トーラスは半径ごと拡大するので、管の太さ（外径 1 − 内径）を半径で割って保つ。
				var torus := (node as MeshInstance3D).mesh as TorusMesh
				if torus != null:
					torus.inner_radius = clampf(1.0 - thickness / maxf(radius, 0.001), 0.0, 0.995)
				var ring_basis: Basis = effect.basis
				node.global_transform = Transform3D(ring_basis.scaled(Vector3.ONE * radius), node.global_position)
				(effect.material as ShaderMaterial).set_shader_parameter("opacity", pow(1.0 - progress, 1.6))
			"shell":
				var eased_shell := 1.0 - pow(1.0 - progress, 2.4)
				node.scale = Vector3.ONE * lerpf(float(effect.from), float(effect.to), eased_shell)
				(effect.material as ShaderMaterial).set_shader_parameter("opacity", pow(1.0 - progress, 2.0))
			"light":
				(node as OmniLight3D).light_energy = float(effect.energy) * pow(1.0 - progress, 2.0)
		if progress >= 1.0:
			node.queue_free()
			_effects.remove_at(index)


func _has_rider() -> bool:
	return _rider != null and is_instance_valid(_rider) and player_controller != null
