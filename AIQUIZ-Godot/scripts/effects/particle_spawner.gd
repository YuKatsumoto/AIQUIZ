extends Node3D

## パーティクルエフェクト管理
## Python版 renderer.py の _spawn_correct / _spawn_explosion に相当
## Godot の GPUParticles3D を使用

var correct_particles: GPUParticles3D
var explosion_particles: GPUParticles3D

func _ready() -> void:
	_create_correct_particles()
	_create_explosion_particles()

func _create_correct_particles() -> void:
	correct_particles = GPUParticles3D.new()
	correct_particles.name = "CorrectParticles"
	correct_particles.emitting = false
	correct_particles.one_shot = true
	correct_particles.amount = 100
	correct_particles.lifetime = 2.0
	correct_particles.explosiveness = 1.0
	correct_particles.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 20, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3(0, -6.0, 0)
	mat.scale_min = 0.15
	mat.scale_max = 0.35
	# Gold/Green colors
	mat.color = Color(1.0, 0.9, 0.2)
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.9, 0.2, 1.0))   # Gold
	color_ramp.add_point(0.3, Color(0.2, 1.0, 0.5, 1.0))   # Green
	color_ramp.add_point(0.6, Color(0.3, 0.8, 1.0, 1.0))   # Cyan
	color_ramp.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))   # Fade out
	var tex := GradientTexture1D.new()
	tex.gradient = color_ramp
	mat.color_ramp = tex

	correct_particles.process_material = mat

	# Mesh (small cube)
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.15, 0.15)
	correct_particles.draw_pass_1 = box

	add_child(correct_particles)

func _create_explosion_particles() -> void:
	explosion_particles = GPUParticles3D.new()
	explosion_particles.name = "ExplosionParticles"
	explosion_particles.emitting = false
	explosion_particles.one_shot = true
	explosion_particles.amount = 250
	explosion_particles.lifetime = 2.5
	explosion_particles.explosiveness = 1.0
	explosion_particles.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 25, 40))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 30.0
	mat.gravity = Vector3(0, -6.0, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.8
	# Fiery red/orange
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))   # Bright orange
	color_ramp.add_point(0.3, Color(1.0, 0.3, 0.0, 1.0))   # Red
	color_ramp.add_point(0.7, Color(0.8, 0.1, 0.0, 0.8))   # Dark red
	color_ramp.add_point(1.0, Color(0.3, 0.05, 0.0, 0.0))  # Fade out
	var tex := GradientTexture1D.new()
	tex.gradient = color_ramp
	mat.color_ramp = tex

	# Emission (cube emitter area)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1.0, 0.5, 1.0)

	explosion_particles.process_material = mat

	# Mesh (small cube)
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color.WHITE
	box_mat.emission_enabled = true
	box_mat.emission = Color(1.0, 0.5, 0.1)
	box_mat.emission_energy_multiplier = 2.0
	box.material = box_mat
	explosion_particles.draw_pass_1 = box

	add_child(explosion_particles)

func spawn_correct(pos: Vector3) -> void:
	correct_particles.global_position = pos + Vector3(0, 1.0, 0)
	correct_particles.restart()
	correct_particles.emitting = true

func spawn_explosion(pos: Vector3) -> void:
	explosion_particles.global_position = pos + Vector3(0, 0.5, 0)
	explosion_particles.restart()
	explosion_particles.emitting = true
