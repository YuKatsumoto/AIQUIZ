extends Node3D
class_name SawWheelSparks

## Presentation only: each carriage roller (Roll_NN) throws a spray of grinding sparks behind it
## while the carriage travels. Reads the rolled distance the controller last applied, so the chase,
## the dock entrance, the menu chase and the stow retreat all spark the same way.
const SPARK_START_SPEED := 0.25 # m/s below which the rollers stay dark
const SPARK_FULL_SPEED := 6.0 # m/s at which every emitter runs at its full amount
const SPARK_JUMP_SPEED := 40.0 # faster than this is a seek/reset, not travel
const SPEED_SMOOTHING := 12.0 # 1/s low-pass on the rolling speed
const SPARK_AMOUNT := 36
const SPARK_LIFETIME := 0.4
## The rollers run in the rail channel (ConveyorRails head at the contact height), so the spray
## starts at the top of the rail head behind the tread and climbs steeply out of the channel.
const SPARK_LIFT := 0.05
const SPARK_RISE := 0.95 # upward share of the spray direction (1 = as much up as back)

var _controller: SawChaseController
var _emitters: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _material: ParticleProcessMaterial
var _last_distance := NAN
var _speed := 0.0 # smoothed signed m/s of wheel_distance
var _clock := 0.0

func setup(controller: SawChaseController) -> void:
	_controller = controller
	_material = _spark_motion()
	var mesh := _spark_mesh()
	var with_lights := not GraphicsQuality.is_mobile_target()
	for bone: int in controller.wheel_bones:
		var particles := GPUParticles3D.new()
		particles.name = "Sparks_" + controller.skeleton.get_bone_name(bone)
		particles.top_level = true # world-aligned, so the spray direction is given in world space
		particles.amount = GraphicsQuality.particle_amount(SPARK_AMOUNT, GameManager.graphics_quality)
		particles.lifetime = SPARK_LIFETIME
		particles.randomness = 0.5
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 4.0, 6.0))
		particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.process_material = _material
		particles.draw_pass_1 = mesh
		particles.emitting = false
		add_child(particles)
		_emitters.append(particles)
		if with_lights:
			var light := OmniLight3D.new()
			light.name = "SparkGlow_" + controller.skeleton.get_bone_name(bone)
			light.top_level = true
			light.light_color = Color(1.0, 0.62, 0.25)
			light.light_energy = 0.0
			light.omni_range = 1.2
			light.shadow_enabled = false
			light.visible = false
			add_child(light)
			_lights.append(light)

func _process(dt: float) -> void:
	if _controller == null or _controller.skeleton == null or dt <= 0.0: return
	var distance := _controller.rolled_distance()
	var raw := 0.0
	if is_finite(_last_distance):
		raw = (distance - _last_distance) / dt
		if absf(raw) > SPARK_JUMP_SPEED: raw = _speed # seek or round reset: keep the last speed
	_last_distance = distance
	_speed = lerpf(_speed, raw, 1.0 - exp(-SPEED_SMOOTHING * dt))
	_clock += dt
	var ratio := spark_ratio() if is_visible_in_tree() else 0.0
	var skeleton := _controller.skeleton
	var up := skeleton.global_basis.y.normalized()
	var travel := travel_world()
	for i: int in _emitters.size():
		var bone: int = _controller.wheel_bones[i]
		var contact := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin - up * SawChaseState.WHEEL_RADIUS
		var particles := _emitters[i]
		# Sparks leave the back of the contact patch, against the travel.
		particles.global_transform = Transform3D(Basis.IDENTITY, contact - travel * 0.12 + up * SPARK_LIFT)
		particles.emitting = ratio > 0.0
		particles.amount_ratio = lerpf(0.15, 1.0, ratio)
		if i < _lights.size():
			var light := _lights[i]
			light.visible = ratio > 0.0
			light.global_position = contact - travel * 0.25 + up * 0.15
			var flicker := 0.7 + 0.3 * sin(_clock * 53.0 + i * 1.7) * sin(_clock * 31.0 + i)
			light.light_energy = 0.7 * ratio * flicker
	if ratio > 0.0:
		_material.direction = (-travel + up * SPARK_RISE).normalized()

## World travel direction of the carriage. A roller spins about its bone Y by -distance / radius,
## so it rolls along -(axle x up); every roller shares the axle orientation.
func travel_world() -> Vector3:
	var skeleton := _controller.skeleton
	if _controller.wheel_bones.is_empty(): return Vector3.ZERO
	var axle := (skeleton.global_basis * skeleton.get_bone_global_pose(_controller.wheel_bones[0]).basis).y
	return -(axle.cross(skeleton.global_basis.y)).normalized() * signf(_speed)

func spark_ratio() -> float:
	return clampf((absf(_speed) - SPARK_START_SPEED) / (SPARK_FULL_SPEED - SPARK_START_SPEED), 0.0, 1.0)

func _spark_motion() -> ParticleProcessMaterial:
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3(0.0, SPARK_RISE, -1.0).normalized()
	motion.spread = 26.0
	motion.initial_velocity_min = 2.5
	motion.initial_velocity_max = 5.5
	motion.gravity = Vector3(0.0, -9.8, 0.0)
	motion.damping_min = 0.6
	motion.damping_max = 1.6
	# Part of the carriage's speed carries over, so at chase speed the spray stays bunched behind the
	# roller instead of being strung out along the rail.
	motion.inherit_velocity_ratio = 0.6
	motion.scale_min = 0.5
	motion.scale_max = 1.0
	motion.particle_flag_align_y = true
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(0.07, 0.02, 0.04)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.75, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.97, 0.82, 1.0), Color(1.0, 0.78, 0.32, 1.0),
		Color(1.0, 0.42, 0.08, 0.8), Color(0.9, 0.18, 0.02, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	return motion

## A thin glowing streak, stretched along the velocity by the emitter's transform align.
func _spark_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.22)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	# HDR, weighted to orange so the tonemapper keeps the hue in daylight instead of clipping to white.
	material.albedo_color = Color(2.2, 1.35, 0.55)
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = dot
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	material.albedo_texture = texture
	mesh.material = material
	return mesh
