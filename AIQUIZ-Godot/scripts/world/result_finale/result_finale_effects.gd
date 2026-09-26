class_name ResultFinaleEffects
extends Node3D

## World-space celebration layers for the Score Tower Finale: cannon confetti,
## falling confetti, fireworks, the winner's spotlight beam and the loser's rain.
## Lives outside the (possibly mirrored) stage so particles never inherit a reflection.

const GOLD := Color(1.0, 0.82, 0.29)
const WHITE := Color(1.0, 1.0, 1.0)
const PINK := Color(1.0, 0.45, 0.72)
const MINT := Color(0.45, 1.0, 0.78)
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float strength = 0.0;
void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	ALBEDO = tint.rgb;
	ALPHA = strength * edge * mix(0.35, 1.0, along) * tint.a;
}
"""

var events: Array[Dictionary] = []
var _quality := GraphicsQuality.BALANCED
var _nodes: Array[Node] = []
var _rain: Array[GPUParticles3D] = []
var _confetti_rain: GPUParticles3D
var _spot: SpotLight3D
var _beam: MeshInstance3D
var _beam_material: ShaderMaterial


func setup(quality: String) -> void:
	_quality = GraphicsQuality.normalize(quality)


func _ratio() -> float:
	return 0.45 if _quality == GraphicsQuality.LOW else (1.0 if _quality == GraphicsQuality.HIGH else 0.75)


func _track(node: Node) -> Node:
	add_child(node)
	_nodes.append(node)
	return node


func _flat_material(additive: bool, billboard: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = billboard
	material.billboard_keep_scale = true
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
	return material


func _palette(colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var values := PackedColorArray()
	for index in range(colors.size()):
		# Two stops per colour make a stepped ramp: each particle picks one colour.
		offsets.append(float(index) / colors.size())
		values.append(colors[index])
		offsets.append((float(index) + 0.999) / colors.size())
		values.append(colors[index])
	gradient.offsets = offsets
	gradient.colors = values
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _confetti_process(speed: Vector2, spread: float, gravity: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3(0.0, gravity, 0.0)
	process.damping_min = 1.2
	process.damping_max = 2.6
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -420.0
	process.angular_velocity_max = 420.0
	process.scale_min = 0.7
	process.scale_max = 1.35
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 2.2
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.16
	return process


func _confetti_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.13)
	quad.material = _flat_material(false, BaseMaterial3D.BILLBOARD_PARTICLES)
	return quad


## One-shot bursts from the platform cannons (muzzle +Y is the barrel).
func burst_confetti(muzzles: Array[Node3D], colors: Array, time: float) -> void:
	for muzzle: Node3D in muzzles:
		if not is_instance_valid(muzzle):
			continue
		var particles := _track(GPUParticles3D.new()) as GPUParticles3D
		particles.name = "CannonConfetti"
		particles.global_transform = Transform3D(muzzle.global_basis.orthonormalized(), muzzle.global_position)
		particles.amount = int(70 * _ratio())
		particles.lifetime = 3.4
		particles.one_shot = true
		particles.explosiveness = 0.94
		particles.randomness = 0.4
		particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		var process := _confetti_process(Vector2(6.5, 10.5), 16.0, -5.5)
		process.color_initial_ramp = _palette(colors)
		particles.process_material = process
		particles.draw_pass_1 = _confetti_mesh()
		particles.emitting = true
		particles.restart()
	events.append({"kind": "confetti_burst", "time": time, "count": muzzles.size()})


## A gentle curtain of confetti over the winner that keeps falling.
func start_confetti_rain(centre: Vector3, width: float, colors: Array, time: float) -> void:
	if is_instance_valid(_confetti_rain):
		return
	_confetti_rain = _track(GPUParticles3D.new()) as GPUParticles3D
	_confetti_rain.name = "ConfettiRain"
	_confetti_rain.global_position = centre
	_confetti_rain.amount = int(170 * _ratio())
	_confetti_rain.lifetime = 5.0
	_confetti_rain.preprocess = 0.0
	_confetti_rain.visibility_aabb = AABB(Vector3(-10, -12, -6), Vector3(20, 16, 12))
	var process := _confetti_process(Vector2(0.2, 1.0), 180.0, -1.6)
	process.direction = Vector3.DOWN
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(width * 0.5, 0.3, 2.6)
	process.damping_min = 0.4
	process.damping_max = 0.9
	process.color_initial_ramp = _palette(colors)
	_confetti_rain.process_material = process
	_confetti_rain.draw_pass_1 = _confetti_mesh()
	_confetti_rain.emitting = true
	events.append({"kind": "confetti_rain", "time": time})


func firework(position_value: Vector3, color: Color, time: float) -> void:
	var particles := _track(GPUParticles3D.new()) as GPUParticles3D
	particles.name = "Firework"
	particles.global_position = position_value
	particles.amount = int(110 * _ratio())
	particles.lifetime = 1.7
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-9, -9, -9), Vector3(18, 18, 18))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0, -2.4, 0)
	process.damping_min = 2.0
	process.damping_max = 3.2
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(color, 0.95), Color(color, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	process.scale_curve = shrink_texture
	particles.process_material = process
	var spark := SphereMesh.new()
	spark.radius = 0.07
	spark.height = 0.14
	spark.radial_segments = 6
	spark.rings = 3
	spark.material = _flat_material(true, BaseMaterial3D.BILLBOARD_DISABLED)
	particles.draw_pass_1 = spark
	particles.emitting = true
	particles.restart()
	events.append({"kind": "firework", "time": time})


func start_rain(emitter: Node3D, time: float) -> void:
	if not is_instance_valid(emitter):
		return
	var particles := GPUParticles3D.new()
	particles.name = "CloudRain"
	emitter.add_child(particles)
	_nodes.append(particles)
	_rain.append(particles)
	particles.amount = int(90 * _ratio())
	particles.lifetime = 0.5
	particles.visibility_aabb = AABB(Vector3(-2, -4, -2), Vector3(4, 5, 4))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.DOWN
	process.spread = 3.0
	process.initial_velocity_min = 3.4
	process.initial_velocity_max = 4.6
	process.gravity = Vector3(0, -7.0, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.42, 0.02, 0.2)
	process.color = Color(0.45, 0.66, 1.0, 1.0)
	particles.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.035, 0.28)
	var material := _flat_material(false, BaseMaterial3D.BILLBOARD_FIXED_Y)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = material
	particles.draw_pass_1 = streak
	particles.emitting = true
	events.append({"kind": "rain", "time": time})


## Spotlight and soft volumetric beam dropping onto the winner's platform.
func set_spotlight(target: Vector3, amount: float, color: Color) -> void:
	if not is_instance_valid(_spot):
		_spot = _track(SpotLight3D.new()) as SpotLight3D
		_spot.name = "WinnerSpot"
		_spot.spot_angle = 17.0
		_spot.spot_range = 16.0
		_spot.spot_attenuation = 0.6
		_spot.shadow_enabled = false
		_spot.light_specular = 0.6
		_beam = _track(MeshInstance3D.new()) as MeshInstance3D
		_beam.name = "WinnerBeam"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.18
		cone.bottom_radius = 1.25
		cone.height = 1.0
		cone.radial_segments = 32
		cone.cap_top = false
		cone.cap_bottom = false
		_beam.mesh = cone
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = BEAM_SHADER
		_beam_material.shader = shader
		_beam.material_override = _beam_material
	var source := target + Vector3(0.0, 7.5, 0.0)
	_spot.global_position = source
	_spot.look_at(target, Vector3.FORWARD)
	_spot.light_color = color
	_spot.light_energy = 4.5 * amount
	_spot.visible = amount > 0.001
	# Beam from above the camera frame down to the platform top.
	var length := source.distance_to(target)
	_beam.global_transform = Transform3D(Basis().scaled(Vector3(1.0, length, 1.0)), (source + target) * 0.5)
	_beam_material.set_shader_parameter("tint", Color(color, 1.0))
	_beam_material.set_shader_parameter("strength", 0.12 * amount)
	_beam.visible = amount > 0.001


func clear() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	_rain.clear()
	_confetti_rain = null
	_spot = null
	_beam = null
	_beam_material = null
	events.clear()


func particle_count() -> int:
	var count := 0
	for node: Node in _nodes:
		if is_instance_valid(node) and node is GPUParticles3D:
			count += 1
	return count
