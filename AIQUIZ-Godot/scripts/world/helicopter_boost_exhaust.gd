extends Node3D
class_name HelicopterBoostExhaust

## Tail-mounted launch jet using the purchased Binbun FireVFX materials.
const FIRE_SCENE := preload("res://assets/BinbunVFX/fire_effects/effects/Fire/fire_04.tscn")

var ignited := false
var _particles: Array[GPUParticles3D] = []
var _core: MeshInstance3D
var _light: OmniLight3D
var _elapsed := 0.0

func _ready() -> void:
	var fire := FIRE_SCENE.instantiate() as Node3D
	fire.name = "BinbunTailFire"
	fire.rotation.x = PI * 0.5  # Source +Y becomes the helicopter's rear +Z.
	add_child(fire)
	for child: Node in fire.get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			particles.emitting = false
			if particles.name == &"Smoke":
				particles.visible = false
				continue
			var material := particles.process_material.duplicate(true) as ParticleProcessMaterial
			particles.process_material = material
			material.direction = Vector3.UP
			material.gravity = Vector3.ZERO
			material.spread = 9.0 if particles.name == &"Flame" else 16.0
			material.initial_velocity_min = 20.0
			material.initial_velocity_max = 32.0
			material.scale_min = 1.8 if particles.name == &"Flame" else 0.65
			material.scale_max = 3.2 if particles.name == &"Flame" else 1.0
			particles.sub_emitter = NodePath("")
			material.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
			particles.local_coords = true
			particles.lifetime = 0.55
			particles.preprocess = 0.12
			particles.amount = GraphicsQuality.particle_amount(160 if particles.name == &"Flame" else 36, GameManager.graphics_quality)
			particles.visibility_aabb = AABB(Vector3(-4.0, -3.0, -4.0), Vector3(8.0, 28.0, 8.0))
			if particles.name == &"Flame":
				var mesh := particles.draw_pass_1.duplicate(true) as Mesh
				var flame_material := mesh.material as ShaderMaterial
				flame_material.set_shader_parameter("lightness", 0.75)
				flame_material.set_shader_parameter("smoke_color", Color(1.0, 0.13, 0.015))
				particles.draw_pass_1 = mesh
			_particles.append(particles)
		elif child is MeshInstance3D:
			_core = child as MeshInstance3D
			_core.mesh = _core.mesh.duplicate(true)
			var core_material := _core.mesh.material as ShaderMaterial
			core_material.set_shader_parameter("main_color", Color(1.0, 0.86, 0.3))
	_light = OmniLight3D.new()
	_light.name = "ExhaustGlow"
	_light.light_color = Color(1.0, 0.33, 0.055)
	_light.light_energy = 0.0
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	add_child(_light)
	visible = false
	set_process(false)

func ignite() -> void:
	if ignited:
		return
	ignited = true
	visible = true
	for particles: GPUParticles3D in _particles:
		particles.restart()
		particles.emitting = true
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	var pulse := 1.0 + sin(_elapsed * 49.0) * 0.12
	_light.light_energy = (3.5 + 3.0 * exp(-_elapsed * 12.0)) * pulse
	if _core != null:
		_core.scale = Vector3.ONE * (1.5 + 1.2 * exp(-_elapsed * 14.0)) * pulse
