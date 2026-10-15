extends Node3D
class_name HelicopterBoostSmoke

## Jet boost smoke from the purchased Binbun SmokeVFX pack: a trail of billowing puffs behind
## the nozzle (smoke_vfx_01) and one cloud at ignition (smoke_big_vfx_01). Only local copies of
## the pack's materials are changed.
## Mounted as a child of HelicopterBoostExhaust (the nozzle), but the puffs live in this node's
## own top-level space (identity basis): smoke stays in the air where it left the nozzle while
## the helicopter dashes away, then slows, swells, rises and fades. Each frame spawns its puffs
## along the whole stretch the nozzle covered since the last frame, so the trail has no gaps
## even at 120 m/s. drift() slides the space with scenery that scrolls past a helicopter held at
## the origin (online staging's flow), and every puff drifts along.
const TRAIL_SCENE := preload("res://assets/BinbunVFX/smoke_effects/effects/smoke/smoke_vfx_01.tscn")
const BURST_SCENE := preload("res://assets/BinbunVFX/smoke_effects/effects/smoke_big/smoke_big_vfx_01.tscn")
const TRAIL_LIFETIME := 2.6
const BURST_LIFETIME := 3.4
## Seconds the last puffs float after the jet is cut.
const LINGER := maxf(TRAIL_LIFETIME, BURST_LIFETIME)
## Sunlit and shaded sides of the plume, and the fresh smoke the flame lights orange.
const SMOKE_LIT := Color(0.74, 0.74, 0.73)
const SMOKE_SHADE := Color(0.36, 0.37, 0.39)
const SMOKE_HOT := Color(0.96, 0.62, 0.40)
## A longer nozzle step in one frame is a cut or a teleport, not flight: no smoke along it.
const MAX_STEP := 60.0
## Room around the emitted stretch for puffs to spread, swell and rise.
const BOUNDS_MARGIN := 16.0

## Set before adding to the tree, like HelicopterBoostExhaust.size.
var size := 1.0
var emitting := false
var _nozzle: Node3D
var _trail: GPUParticles3D
var _burst: GPUParticles3D
var _trail_motion: ParticleProcessMaterial
var _burst_motion: ParticleProcessMaterial
## The nozzle in this space last frame. The first frame after ignite() places the space and
## the ignition cloud, after the director has moved the helicopter for that frame.
var _last_local := Vector3.ZERO
var _tracking := false
var _bounds := AABB()
var _linger := 0.0

func _ready() -> void:
	top_level = true
	# Run after the directors that move the helicopter, so each step ends at this frame's nozzle.
	process_priority = 100
	_nozzle = get_parent() as Node3D
	_trail = _make_particles(TRAIL_SCENE, "TrailSmoke")
	_trail_motion = _trail.process_material as ParticleProcessMaterial
	_trail_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_trail_motion.emission_ring_radius = 0.16 * size
	_trail_motion.emission_ring_inner_radius = 0.0
	_trail_motion.emission_ring_cone_angle = 90.0
	_trail_motion.emission_ring_height = 0.0
	_trail_motion.spread = 7.0
	_trail_motion.initial_velocity_min = 10.0
	_trail_motion.initial_velocity_max = 16.0
	_trail_motion.damping_min = 7.0
	_trail_motion.damping_max = 9.0
	_trail_motion.gravity = Vector3(0.0, 0.7, 0.0)
	_trail_motion.scale_min = 1.8 * size
	_trail_motion.scale_max = 2.6 * size
	_trail_motion.scale_curve = _curve([Vector2(0.0, 0.3), Vector2(0.05, 0.6), Vector2(0.25, 0.85), Vector2(1.0, 1.0)])
	_trail_motion.alpha_curve = _curve([Vector2(0.0, 0.6), Vector2(0.06, 1.0), Vector2(0.45, 0.8), Vector2(1.0, 0.0)])
	_trail_motion.color_ramp = _hot_ramp(0.08)
	_trail.lifetime = TRAIL_LIFETIME
	_trail.amount = GraphicsQuality.particle_amount(roundi(240 * clampf(size, 0.5, 1.0)), GameManager.graphics_quality)
	_burst = _make_particles(BURST_SCENE, "IgnitionSmoke")
	_burst_motion = _burst.process_material as ParticleProcessMaterial
	_burst_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_burst_motion.emission_sphere_radius = 0.6 * size
	_burst_motion.spread = 80.0
	_burst_motion.initial_velocity_min = 2.0
	_burst_motion.initial_velocity_max = 7.0
	_burst_motion.damping_min = 3.5
	_burst_motion.damping_max = 5.0
	_burst_motion.gravity = Vector3(0.0, 0.5, 0.0)
	_burst_motion.scale_min = 0.8 * size
	_burst_motion.scale_max = 1.3 * size
	_burst_motion.scale_curve = _curve([Vector2(0.0, 0.15), Vector2(0.08, 0.5), Vector2(0.4, 0.85), Vector2(1.0, 1.0)])
	_burst_motion.alpha_curve = _curve([Vector2(0.0, 0.0), Vector2(0.04, 1.0), Vector2(0.5, 0.75), Vector2(1.0, 0.0)])
	_burst_motion.color_ramp = _hot_ramp(0.12)
	_burst.lifetime = BURST_LIFETIME
	_burst.one_shot = true
	_burst.explosiveness = 0.9
	_burst.amount = GraphicsQuality.particle_amount(roundi(18 * clampf(size, 0.5, 1.0)), GameManager.graphics_quality)
	set_process(false)

## One of the pack's emitters with private copies of its look and motion, re-tuned for jet
## exhaust: the source effect is a column rising in place, this one is left behind in the air.
func _make_particles(scene: PackedScene, node_name: String) -> GPUParticles3D:
	var template := scene.instantiate()
	var source := template.get_node("Smoke") as GPUParticles3D
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.draw_pass_1 = source.draw_pass_1
	particles.process_material = source.process_material.duplicate(true)
	var look := source.material_override.duplicate() as ShaderMaterial
	template.free()
	look.set_shader_parameter("primary_color", SMOKE_LIT)
	look.set_shader_parameter("secondary_color", SMOKE_SHADE)
	look.set_shader_parameter("tertiary_color", SMOKE_HOT)
	look.set_shader_parameter("emission_strength", 0.45)
	look.set_shader_parameter("proximity_fade_distance", 0.6)
	# Soft billows instead of the pack's hard cartoon cells (its controller's hard_clouds off, low cloud_density).
	look.set_shader_parameter("mask2_blend_mode", 0)
	look.set_shader_parameter("mask2_strength", 0.5)
	look.set_shader_parameter("alpha_multiplier", 1.0)
	# After the sea and the other default transparents (like shark_surface_wake): a trail drifting
	# far over the water would otherwise sort behind the huge ocean plane and vanish under it.
	# The jet's flame (HelicopterBoostExhaust.FLAME_RENDER_PRIORITY) stays in front of its own smoke.
	look.render_priority = 1
	particles.material_override = look
	var motion := particles.process_material as ParticleProcessMaterial
	motion.lifetime_randomness = 0.25
	# The exhaust jet brakes in the air first; only then does buoyancy lift the cooling smoke.
	motion.damping_curve = _curve([Vector2(0.0, 1.0), Vector2(0.35, 1.0), Vector2(0.55, 0.0), Vector2(1.0, 0.0)])
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 1.0
	motion.turbulence_noise_scale = 4.0
	motion.turbulence_influence_min = 0.02
	motion.turbulence_influence_max = 0.05
	particles.local_coords = true
	# Spawn every frame (not at the default 30 Hz) so each frame's stretch gets its own puffs.
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.fract_delta = true
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.emitting = false
	add_child(particles)
	return particles

static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points:
		curve.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

## The pack's shader mixes in tertiary_color by the particle's blue channel: fresh smoke starts
## flame-lit (blue 1) and cools to grey by `cooled` of its life. Red stays the pack's per-puff noise offset.
static func _hot_ramp(cooled: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, cooled])
	gradient.colors = PackedColorArray([Color(1.0, 0.0, 1.0, 1.0), Color(1.0, 0.0, 0.0, 1.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func ignite() -> void:
	emitting = true
	_tracking = false
	set_process(true)

## Cut the jet: no new puffs; the trail and the ignition cloud float on and fade out.
func stop() -> void:
	if not emitting:
		return
	emitting = false
	_tracking = false
	_trail.emitting = false
	_linger = LINGER

## Remove every puff now (under a blackout or a cut).
func clear() -> void:
	emitting = false
	_tracking = false
	_linger = 0.0
	set_process(false)
	for particles: GPUParticles3D in [_trail, _burst]:
		particles.restart()
		particles.emitting = false

## True while puffs are still in the air.
func is_alive() -> bool:
	return emitting or _linger > 0.0

## Move every puff with scenery that scrolls past a helicopter held at the origin.
func drift(offset: Vector3) -> void:
	global_position += offset

## Keep the floating smoke when the helicopter is freed: move it under parent and free it
## once the last puff has faded.
func release_to(parent: Node) -> void:
	stop()
	_nozzle = null
	set_process(false)
	reparent(parent)
	get_tree().create_timer(maxf(_linger, 0.05)).timeout.connect(queue_free)

## Draw both emitters once at the nozzle during the loading prewarm so ignition never compiles
## the smoke material mid-flight.
func set_prewarm(active: bool) -> void:
	if emitting:
		return
	if not active:
		clear()
		return
	_place_space()
	_aim(_trail_motion, Vector3.ZERO, 0.0)
	_trail.restart()
	_fire_burst()

func _process(delta: float) -> void:
	if not emitting:
		_linger -= delta
		if _linger <= 0.0:
			set_process(false)
		return
	if _nozzle == null:
		return
	if not _tracking:
		_tracking = true
		if _linger > 0.0:
			# Lit again while the last burn's puffs still float: leave them where they are.
			_last_local = _nozzle.global_position - global_position
			_grow_bounds(_last_local)
			_trail.emitting = true
		else:
			_place_space()
			_trail.restart()
		_linger = 0.0
		_aim(_trail_motion, _last_local, 0.0)
		_fire_burst()
		return
	var local := _nozzle.global_position - global_position
	var step := local - _last_local
	if step.length() > MAX_STEP:
		step = Vector3.ZERO
	_last_local = local
	_aim(_trail_motion, local - step * 0.5, step.length())
	if step.length_squared() > 0.000001:
		_trail_motion.emission_ring_axis = step.normalized()
	_grow_bounds(local)

## Start a fresh space at the nozzle: offsets stay small and the visibility box tight.
func _place_space() -> void:
	global_transform = Transform3D(Basis.IDENTITY, _nozzle.global_position)
	_last_local = Vector3.ZERO
	_bounds = AABB()
	_grow_bounds(Vector3.ZERO)

func _fire_burst() -> void:
	var rear := _nozzle.global_basis.z.normalized()
	_aim(_burst_motion, _last_local + rear * 0.9 * size, 0.0)
	_burst.restart()

## Spawn puffs along the nozzle's last step (a thin cylinder centred on `center`), blown out of the nozzle.
func _aim(motion: ParticleProcessMaterial, center: Vector3, length: float) -> void:
	motion.direction = _nozzle.global_basis.z.normalized()
	motion.emission_shape_offset = center
	if motion.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING:
		motion.emission_ring_height = length

func _grow_bounds(local: Vector3) -> void:
	_bounds = _bounds.expand(local)
	var box := _bounds.grow(BOUNDS_MARGIN)
	_trail.visibility_aabb = box
	_burst.visibility_aabb = box
