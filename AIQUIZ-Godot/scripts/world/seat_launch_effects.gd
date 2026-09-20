extends Node3D
class_name SeatLaunchEffects

## Rocket exhaust derived from the installed Effects Collection Vol.1 assets.
## All materials are local copies. Smoke uses world coordinates and outlives the
## visible chair; the stationary ignition cloud stays on the fixed socket.
const FIRE := preload("res://assets/BinbunVFX/fire_effects/effects/Fire/fire_04.tscn")
const SMOKE := preload("res://assets/BinbunVFX/smoke_effects/effects/smoke_big/smoke_big_vfx_01.tscn")
var nozzles: Array[Node3D] = []
var jets: Array[Node3D] = []
var flames: Array[GPUParticles3D] = []
var clouds: Array[GPUParticles3D] = []
var cores: Array[Node3D] = []
var pads: Array[GPUParticles3D] = []
var glow: OmniLight3D
var socket: Node3D
var strength := 0.0

func setup(kit: Node3D, fixed_socket: Node3D) -> void:
	socket = fixed_socket
	for side in ["L", "R"]:
		nozzles.append(kit.find_child("SL_Exhaust_" + side, true, false) as Node3D)
		var fire := FIRE.instantiate() as Node3D
		fire.set_script(null)
		add_child(fire)
		jets.append(fire)
		for node in fire.find_children("*", "GPUParticles3D", true, false):
			var p := node as GPUParticles3D
			p.emitting = false
			if p.name != &"Flame":
				p.visible = false
				continue
			p.process_material = p.process_material.duplicate(true)
			var pm := p.process_material as ParticleProcessMaterial
			pm.direction = Vector3.UP
			pm.gravity = Vector3.ZERO
			pm.spread = 5.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			pm.initial_velocity_min = 7.0
			pm.initial_velocity_max = 11.0
			pm.scale_min = .35
			pm.scale_max = .55
			pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
			p.sub_emitter = NodePath("")
			p.local_coords = true
			p.lifetime = .35
			p.amount = GraphicsQuality.particle_amount(64, GameManager.graphics_quality)
			p.preprocess = .1
			p.draw_pass_1 = p.draw_pass_1.duplicate(true)
			var flame_material := p.draw_pass_1.surface_get_material(0) as ShaderMaterial
			flame_material.set_shader_parameter("lightness", .65)
			flame_material.set_shader_parameter("smoke_color", Color(1.0,.36,.03))
			p.visibility_aabb = AABB(Vector3(-3,-3,-3), Vector3(6,12,6))
			flames.append(p)
		var core := fire.get_node("Flame_Core") as MeshInstance3D
		core.mesh = core.mesh.duplicate(true)
		core.scale = Vector3(.40, 2.5, .40)
		core.position.y = .9
		core.visible = false
		cores.append(core)
		clouds.append(_smoke(false))
		pads.append(_smoke(true))
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, .45, .09)
	glow.omni_range = 4.0
	glow.shadow_enabled = false
	glow.light_energy = 0.0
	add_child(glow)
	follow_nozzles()

func _smoke(burst: bool) -> GPUParticles3D:
	var container := SMOKE.instantiate() as Node3D
	container.set_script(null)
	add_child(container)
	for child in container.get_children():
		if child is GPUParticles3D:
			child.emitting = false
			if child.name != &"Smoke": child.visible = false
	var p := container.get_node("Smoke") as GPUParticles3D
	p.process_material = p.process_material.duplicate(true)
	p.material_override = p.material_override.duplicate(true)
	p.draw_pass_1 = p.draw_pass_1.duplicate(true)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3.DOWN if not burst else Vector3.UP
	pm.gravity = Vector3(0,.8,0)
	pm.spread = 30.0 if not burst else 88.0
	pm.initial_velocity_min = 1.2 if not burst else 1.0
	pm.initial_velocity_max = 3.0 if not burst else 3.2
	pm.scale_min = .10 if not burst else .13
	pm.scale_max = .20 if not burst else .22
	var material := p.material_override as ShaderMaterial
	# The collection's billboard discards particle scale and draws its full 10m
	# quad. Preserve each particle's growth curve in our private shader copy.
	material.shader = preload("res://shaders/chair_rocket_smoke.gdshader")
	material.set_shader_parameter("primary_color", Color(.84,.86,.89))
	material.set_shader_parameter("secondary_color", Color(.60,.64,.69))
	material.set_shader_parameter("tertiary_color", Color(.32,.36,.42))
	material.set_shader_parameter("billboard", true)
	material.set_shader_parameter("proximity_fade_distance", .12)
	material.set_shader_parameter("emission_strength", .08)
	p.local_coords = false
	p.one_shot = burst
	p.explosiveness = .9 if burst else 0.0
	p.lifetime = 1.4 if burst else 1.7
	p.preprocess = 0.0
	p.amount = GraphicsQuality.particle_amount(20 if burst else 40, GameManager.graphics_quality)
	p.visibility_aabb = AABB(Vector3(-12,-45,-12),Vector3(24,90,24))
	return p

func follow_nozzles() -> void:
	for i in nozzles.size():
		jets[i].global_transform = nozzles[i].global_transform * Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
		(clouds[i].get_parent() as Node3D).global_transform = nozzles[i].global_transform
	if glow != null:
		glow.global_position = (nozzles[0].global_position + nozzles[1].global_position) * .5

func ignite() -> void:
	follow_nozzles()
	set_thrust(1.0)
	_burst()

func _burst() -> void:
	for i in pads.size():
		(pads[i].get_parent() as Node3D).global_position = socket.to_global(Vector3(.33 if i == 0 else -.33, 1.0, -.30))
		pads[i].restart()
		pads[i].emitting = true

func touchdown() -> void:
	set_thrust(0.0)
	_burst()

func set_thrust(value: float) -> void:
	var active := value > .01
	var was_active := strength > .01
	strength = clampf(value,0.0,1.0)
	for p in flames + clouds:
		if active and not was_active: p.restart()
		p.emitting = active
		p.amount_ratio = maxf(strength, .05)
	for core in cores:
		core.visible = active
		core.scale.y = lerpf(.50,2.5,strength)
		core.position.y = core.scale.y * .36
	glow.light_energy = strength * 2.0

func stop_immediately() -> void:
	set_thrust(0.0)
	for p in flames + clouds + pads:
		p.restart()
		p.emitting = false
