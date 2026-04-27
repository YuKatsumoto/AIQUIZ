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
	explosion_particles.global_position = pos + Vector3(0, 2.0, 0)
	explosion_particles.restart()
	explosion_particles.emitting = true

# ---------- Fireworks ----------

const FIREWORK_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.2),   # Red
	Color(0.2, 0.5, 1.0),   # Blue
	Color(1.0, 0.85, 0.1),  # Gold
	Color(0.1, 1.0, 0.4),   # Green
	Color(0.8, 0.2, 1.0),   # Purple
	Color(1.0, 0.5, 0.0),   # Orange
	Color(0.0, 1.0, 0.9),   # Cyan
]

func spawn_fireworks(center_pos: Vector3) -> void:
	## 複数の花火を時間差で打ち上げる
	var num_fireworks: int = 7
	for i: int in range(num_fireworks):
		var delay: float = i * 0.45 + randf() * 0.2
		var offset := Vector3(
			randf_range(-8.0, 8.0),
			0.0,
			randf_range(-3.0, 5.0)
		)
		var color: Color = FIREWORK_COLORS[i % FIREWORK_COLORS.size()]
		# 色をランダムに少しずらして個性を出す
		color = color.lightened(randf_range(-0.1, 0.15))
		var height: float = randf_range(8.0, 14.0)
		_schedule_firework(center_pos + offset, color, delay, height)

func _schedule_firework(pos: Vector3, color: Color, delay: float, height: float) -> void:
	## 指定遅延後に花火を打ち上げる
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _launch_single_firework(pos, color, height))

func _launch_single_firework(pos: Vector3, color: Color, height: float) -> void:
	## 1発の花火: 上昇シェル → 爆発バースト

	# --- Phase 1: 打ち上げトレイル (上昇する光の筋) ---
	var trail := GPUParticles3D.new()
	trail.emitting = false
	trail.one_shot = true
	trail.amount = 30
	trail.lifetime = 0.8
	trail.explosiveness = 0.9

	var trail_mat := ParticleProcessMaterial.new()
	trail_mat.direction = Vector3(0, 1, 0)
	trail_mat.spread = 5.0
	trail_mat.initial_velocity_min = height * 1.2
	trail_mat.initial_velocity_max = height * 1.5
	trail_mat.gravity = Vector3(0, -4.0, 0)
	trail_mat.scale_min = 0.08
	trail_mat.scale_max = 0.15
	trail_mat.damping_min = 2.0
	trail_mat.damping_max = 4.0

	var trail_gradient := Gradient.new()
	trail_gradient.add_point(0.0, Color(1.0, 0.95, 0.7, 1.0))
	trail_gradient.add_point(0.5, color.lightened(0.3))
	trail_gradient.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
	var trail_tex := GradientTexture1D.new()
	trail_tex.gradient = trail_gradient
	trail_mat.color_ramp = trail_tex

	trail.process_material = trail_mat
	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.06
	trail_mesh.height = 0.12
	var trail_mesh_mat := StandardMaterial3D.new()
	trail_mesh_mat.albedo_color = Color.WHITE
	trail_mesh_mat.emission_enabled = true
	trail_mesh_mat.emission = color.lightened(0.5)
	trail_mesh_mat.emission_energy_multiplier = 3.0
	trail_mesh.material = trail_mesh_mat
	trail.draw_pass_1 = trail_mesh

	trail.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 20, 10))
	trail.global_position = pos
	add_child(trail)
	trail.restart()
	trail.emitting = true

	# --- Phase 2: 爆発バースト (遅延して打ち上げ先で爆発) ---
	var burst_delay: float = 0.6
	var burst_timer := get_tree().create_timer(burst_delay)
	burst_timer.timeout.connect(func(): _spawn_firework_burst(pos + Vector3(0, height, 0), color))

	# トレイルのクリーンアップ
	var cleanup_timer := get_tree().create_timer(3.0)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(trail):
			trail.queue_free()
	)

func _spawn_firework_burst(pos: Vector3, color: Color) -> void:
	## 花火の爆発パーティクル
	var burst := GPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 200
	burst.lifetime = 2.5
	burst.explosiveness = 1.0

	var burst_mat := ParticleProcessMaterial.new()
	burst_mat.direction = Vector3(0, 0, 0)
	burst_mat.spread = 180.0
	burst_mat.initial_velocity_min = 6.0
	burst_mat.initial_velocity_max = 14.0
	burst_mat.gravity = Vector3(0, -3.5, 0)
	burst_mat.scale_min = 0.08
	burst_mat.scale_max = 0.25
	burst_mat.damping_min = 1.0
	burst_mat.damping_max = 3.0

	# 色のグラデーション: メインカラー → 白熱 → フェードアウト
	var burst_gradient := Gradient.new()
	burst_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))   # 白熱の瞬間
	burst_gradient.add_point(0.15, color)                         # メインカラー
	burst_gradient.add_point(0.5, color.darkened(0.2))            # やや暗く
	burst_gradient.add_point(0.8, color.darkened(0.5))            # さらに暗く
	burst_gradient.add_point(1.0, Color(0.1, 0.05, 0.0, 0.0))   # フェードアウト
	var burst_tex := GradientTexture1D.new()
	burst_tex.gradient = burst_gradient
	burst_mat.color_ramp = burst_tex

	# Scale curve: 小さく始まり→膨張→縮小
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.5, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	scale_curve.curve = curve
	burst_mat.scale_curve = scale_curve

	burst.process_material = burst_mat

	# Mesh: 小さな球体（光の粒）
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = color
	sphere_mat.emission_enabled = true
	sphere_mat.emission = color
	sphere_mat.emission_energy_multiplier = 4.0
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = sphere_mat
	burst.draw_pass_1 = sphere

	burst.visibility_aabb = AABB(Vector3(-20, -15, -20), Vector3(40, 30, 40))
	burst.global_position = pos
	add_child(burst)
	burst.restart()
	burst.emitting = true

	# クリーンアップ
	var cleanup_timer := get_tree().create_timer(4.0)
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(burst):
			burst.queue_free()
	)
