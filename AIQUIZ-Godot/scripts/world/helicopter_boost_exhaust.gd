extends Node3D
class_name HelicopterBoostExhaust

## Launch jet using the purchased Binbun FireVFX materials. The flame leaves along
## this node's local +Z (the helicopter's rear when mounted on a jet pod).
## The smoke (Binbun SmokeVFX, HelicopterBoostSmoke) stays in the air behind it and
## keeps floating for a while after the jet is cut.
const FIRE_SCENE := preload("res://assets/BinbunVFX/fire_effects/effects/Fire/fire_04.tscn")
const BoostSmokeScript := preload("res://scripts/world/helicopter_boost_smoke.gd")
## The flame draws after its smoke (render priority 1), so the jet glows in front of it.
const FLAME_RENDER_PRIORITY := 2

## Set before adding to the tree: 1.0 is one big tail jet, the twin pods use a smaller flame each.
var size := 1.0
var ignited := false
var _fire: Node3D
var _particles: Array[GPUParticles3D] = []
var _core: MeshInstance3D
var _light: OmniLight3D
var _smoke: BoostSmokeScript
var _elapsed := 0.0
## Bumped on every ignition so a timer from an earlier burn never hides this one.
var _burn := 0

func _ready() -> void:
	var fire := FIRE_SCENE.instantiate() as Node3D
	fire.name = "BinbunTailFire"
	fire.rotation.x = PI * 0.5  # Source +Y becomes the helicopter's rear +Z.
	add_child(fire)
	_fire = fire
	for child: Node in fire.get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			particles.emitting = false
			if particles.name == &"Smoke":
				particles.visible = false
				continue
			# Only numbers change, so a shallow copy shares the curve and colour textures.
			var material := particles.process_material.duplicate() as ParticleProcessMaterial
			particles.process_material = material
			material.direction = Vector3.UP
			material.gravity = Vector3.ZERO
			material.spread = 9.0 if particles.name == &"Flame" else 16.0
			material.initial_velocity_min = 20.0 * size
			material.initial_velocity_max = 32.0 * size
			material.scale_min = (1.8 if particles.name == &"Flame" else 0.65) * size
			material.scale_max = (3.2 if particles.name == &"Flame" else 1.0) * size
			particles.sub_emitter = NodePath("")
			material.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
			particles.local_coords = true
			particles.lifetime = 0.55
			particles.preprocess = 0.12
			particles.amount = GraphicsQuality.particle_amount(roundi((160 if particles.name == &"Flame" else 36) * clampf(size, 0.5, 1.0)), GameManager.graphics_quality)
			particles.visibility_aabb = AABB(Vector3(-4.0, -3.0, -4.0) * size, Vector3(8.0, 28.0, 8.0) * size)
			if particles.name == &"Flame":
				# Copy only the mesh and its material. A deep copy also clones the noise textures, and a
				# cloned NoiseTexture2D generates its first image on the main thread (~190 ms per jet,
				# which froze the online VS cut-in while the game world was built).
				var mesh := particles.draw_pass_1.duplicate() as Mesh
				var flame_material := (mesh.material as ShaderMaterial).duplicate() as ShaderMaterial
				mesh.material = flame_material
				flame_material.set_shader_parameter("lightness", 0.75)
				flame_material.set_shader_parameter("smoke_color", Color(1.0, 0.13, 0.015))
				flame_material.render_priority = FLAME_RENDER_PRIORITY
				particles.draw_pass_1 = mesh
			_particles.append(particles)
		elif child is MeshInstance3D:
			_core = child as MeshInstance3D
			_core.mesh = _core.mesh.duplicate()
			var core_material := (_core.mesh.material as ShaderMaterial).duplicate() as ShaderMaterial
			_core.mesh.material = core_material
			core_material.set_shader_parameter("main_color", Color(1.0, 0.86, 0.3))
			core_material.render_priority = FLAME_RENDER_PRIORITY
	_light = OmniLight3D.new()
	_light.name = "ExhaustGlow"
	_light.light_color = Color(1.0, 0.33, 0.055)
	_light.light_energy = 0.0
	_light.omni_range = 9.0 * size
	_light.shadow_enabled = false
	add_child(_light)
	_smoke = BoostSmokeScript.new()
	_smoke.name = "BoostSmoke"
	_smoke.size = size
	add_child(_smoke)
	visible = false
	set_process(false)

## smoke: also puff SmokeVFX smoke (only the online staging's takeoff dash uses it).
func ignite(smoke: bool = false) -> void:
	if ignited:
		return
	ignited = true
	_burn += 1
	visible = true
	_fire.visible = true
	for particles: GPUParticles3D in _particles:
		particles.restart()
		particles.emitting = true
	if smoke and _smoke != null:
		_smoke.ignite()
	set_process(true)

## Cut the jet: stop emitting, let the flame burn out and the smoke drift and fade,
## then hide. instant removes flame and smoke now (under a blackout or a cut).
## ignite() can light it again afterwards.
func extinguish(instant: bool = false) -> void:
	var was_ignited := ignited
	ignited = false
	for particles: GPUParticles3D in _particles:
		particles.emitting = false
	_light.light_energy = 0.0
	if _core != null:
		_core.scale = Vector3.ZERO
	set_process(false)
	_elapsed = 0.0
	if instant or not is_inside_tree():
		if _smoke != null:
			_smoke.clear()
		visible = false
		return
	if not was_ignited:
		return
	if _smoke != null:
		_smoke.stop()
	var burn := _burn
	var lifetime := 0.6
	for particles: GPUParticles3D in _particles:
		lifetime = maxf(lifetime, particles.lifetime)
	get_tree().create_timer(lifetime).timeout.connect(func() -> void:
		if burn == _burn and not ignited and is_instance_valid(self):
			_fire.visible = false)
	get_tree().create_timer(BoostSmokeScript.LINGER).timeout.connect(func() -> void:
		if burn == _burn and not ignited and is_instance_valid(self):
			visible = false)

## Slide the floating smoke with scenery that scrolls past a helicopter held at the origin.
func drift_smoke(offset: Vector3) -> void:
	if _smoke != null and visible:
		_smoke.drift(offset)

## Hand the floating smoke to parent before the helicopter is freed, so it fades out
## in the air instead of vanishing with the aircraft.
func release_smoke(parent: Node) -> void:
	if _smoke == null or not is_visible_in_tree() or not _smoke.is_alive():
		return
	_smoke.release_to(parent)
	_smoke = null

## Render the jet once during the loading prewarm so ignition never compiles
## the fire and smoke materials mid-flight.
func set_prewarm(active: bool) -> void:
	if ignited:
		return
	visible = active
	_fire.visible = true
	for particles: GPUParticles3D in _particles:
		particles.emitting = active
		if active:
			particles.restart()
	if _smoke != null:
		_smoke.set_prewarm(active)

func _process(delta: float) -> void:
	_elapsed += delta
	var pulse := 1.0 + sin(_elapsed * 49.0) * 0.12
	_light.light_energy = (3.5 + 3.0 * exp(-_elapsed * 12.0)) * pulse * size
	if _core != null:
		_core.scale = Vector3.ONE * (1.5 + 1.2 * exp(-_elapsed * 14.0)) * pulse * size
