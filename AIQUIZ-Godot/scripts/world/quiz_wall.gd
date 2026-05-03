extends Node3D

## クイズの壁 + ドア (2個 or 4個)
## Python版 renderer.py の _draw_wall_doors + _draw_labels に相当

var wall_parts: Array[MeshInstance3D] = []
var doors: Array[MeshInstance3D] = []
var door_labels: Array[Label3D] = []

var is_boss: bool = false
var boss_label: Label3D = null
var boss_sparks: Array[CPUParticles3D] = []

# Door colors
const DOOR_COLORS_2 := [
	Color(0.10, 0.60, 0.95),  # Left - Blue
	Color(0.90, 0.15, 0.10),  # Right - Red
]
const DOOR_COLORS_4 := [
	Color(0.10, 0.55, 0.95),  # A - Blue
	Color(0.15, 0.75, 0.30),  # B - Green
	Color(0.95, 0.60, 0.10),  # C - Orange
	Color(0.90, 0.15, 0.15),  # D - Red
]
const WALL_COLOR := Color(0.50, 0.50, 0.50)

# Door positions from tuning
const LEFT_DOOR_X: float = 3.5
const RIGHT_DOOR_X: float = -3.5
const DOOR4_XS: Array[float] = [-5.8, -1.95, 1.95, 5.8]

var _current_num_choices: int = 2

func _ready() -> void:
	_build_doors(2)

func _build_wall_around_doors(num_choices: int) -> void:
	# Clear existing wall parts
	for part in wall_parts:
		if is_instance_valid(part):
			part.queue_free()
	wall_parts.clear()

	# Wall dimensions (matching original single box)
	var total_width := 28.0
	var min_x := -14.0
	var max_x := 14.0
	var door_top_y := 2.38
	var door_bottom_y := -2.02
	var wall_top_y := 4.05
	var wall_bottom_y := -3.15

	# 1. Top beam
	var top_height := wall_top_y - door_top_y
	var top_beam := _create_box(Vector3(total_width / 2.0, top_height / 2.0, 0.55), WALL_COLOR)
	top_beam.position = Vector3(0, door_top_y + top_height / 2.0, 0)
	add_child(top_beam)
	wall_parts.append(top_beam)

	# 2. Bottom beam
	var bottom_height := door_bottom_y - wall_bottom_y
	var bottom_beam := _create_box(Vector3(total_width / 2.0, bottom_height / 2.0, 0.55), WALL_COLOR)
	bottom_beam.position = Vector3(0, wall_bottom_y + bottom_height / 2.0, 0)
	add_child(bottom_beam)
	wall_parts.append(bottom_beam)

	# 3. Pillars
	var pillar_height := door_top_y - door_bottom_y
	var pillar_y := door_bottom_y + pillar_height / 2.0

	var door_xs: Array[float] = []
	var door_half_widths: Array[float] = []
	if num_choices == 4:
		door_xs = DOOR4_XS
		door_half_widths = [1.45, 1.45, 1.45, 1.45]
	else:
		door_xs = [RIGHT_DOOR_X, LEFT_DOOR_X] # Sorted by X (-3.5, 3.5)
		door_half_widths = [1.8, 1.8]

	var current_x := min_x
	for i in range(door_xs.size()):
		var dx := door_xs[i]
		var dhw := door_half_widths[i]
		var door_left := dx - dhw
		var door_right := dx + dhw
		
		var pillar_width := door_left - current_x
		if pillar_width > 0:
			var pillar := _create_box(Vector3(pillar_width / 2.0, pillar_height / 2.0, 0.55), WALL_COLOR)
			pillar.position = Vector3(current_x + pillar_width / 2.0, pillar_y, 0)
			add_child(pillar)
			wall_parts.append(pillar)
		
		current_x = door_right
	
	var final_width := max_x - current_x
	if final_width > 0:
		var pillar := _create_box(Vector3(final_width / 2.0, pillar_height / 2.0, 0.55), WALL_COLOR)
		pillar.position = Vector3(current_x + final_width / 2.0, pillar_y, 0)
		add_child(pillar)
		wall_parts.append(pillar)

func _build_doors(num_choices: int) -> void:
	_current_num_choices = num_choices
	_build_wall_around_doors(num_choices)
	
	# Clear existing doors
	for d: MeshInstance3D in doors:
		d.queue_free()
	doors.clear()
	for l: Label3D in door_labels:
		l.queue_free()
	door_labels.clear()

	if num_choices == 4:
		for i: int in range(4):
			var door := _create_box(Vector3(1.45, 2.2, 0.60), DOOR_COLORS_4[i])
			door.position = Vector3(DOOR4_XS[i], 0.18, 0)
			add_child(door)
			doors.append(door)

			var label := _create_label()
			label.position = Vector3(DOOR4_XS[i], 0.18, -0.65)
			label.pixel_size = 0.006
			label.width = 240.0
			add_child(label)
			door_labels.append(label)
	else:
		# Left door (Blue)
		var left_door := _create_box(Vector3(1.8, 2.2, 0.60), DOOR_COLORS_2[0])
		left_door.position = Vector3(LEFT_DOOR_X, 0.18, 0)
		add_child(left_door)
		doors.append(left_door)

		var left_label := _create_label()
		left_label.position = Vector3(LEFT_DOOR_X, 0.18, -0.65)
		add_child(left_label)
		door_labels.append(left_label)

		# Right door (Red)
		var right_door := _create_box(Vector3(1.8, 2.2, 0.60), DOOR_COLORS_2[1])
		right_door.position = Vector3(RIGHT_DOOR_X, 0.18, 0)
		add_child(right_door)
		doors.append(right_door)

		var right_label := _create_label()
		right_label.position = Vector3(RIGHT_DOOR_X, 0.18, -0.65)
		add_child(right_label)
		door_labels.append(right_label)

func set_quiz(quiz: QuizItem, num_choices: int) -> void:
	if num_choices != _current_num_choices:
		_build_doors(num_choices)

	if not quiz:
		for label: Label3D in door_labels:
			label.text = ""
		return

	var labels_4 := ["A", "B", "C", "D"]

	if num_choices == 4:
		for i: int in range(mini(4, quiz.c.size())):
			if i < door_labels.size():
				var choice := quiz.c[i]
				if FractionFormatter.is_pure_fraction(choice):
					# 分数の場合: プレフィックスを上に、分数をスタック表示
					door_labels[i].text = "%s.\n%s" % [labels_4[i], FractionFormatter.to_stacked(choice)]
				elif FractionFormatter.has_fraction(choice):
					# 混合テキストの場合: インライン分数表示
					door_labels[i].text = "%s. %s" % [labels_4[i], FractionFormatter.to_inline(choice)]
				else:
					door_labels[i].text = "%s. %s" % [labels_4[i], choice]
	else:
		if door_labels.size() >= 2:
			door_labels[0].text = FractionFormatter.format_choice(quiz.c[0]) if quiz.c.size() > 0 else ""
			door_labels[1].text = FractionFormatter.format_choice(quiz.c[1]) if quiz.c.size() > 1 else ""

func set_is_boss(boss: bool) -> void:
	is_boss = boss
	var target_color = Color(0.65, 0.15, 0.15) if is_boss else WALL_COLOR
	for part in wall_parts:
		if is_instance_valid(part) and part.material_override:
			part.material_override.albedo_color = target_color
	
	if is_boss and not is_instance_valid(boss_label):
		boss_label = _create_label()
		boss_label.text = "BOSS問題"
		boss_label.font_size = 72
		boss_label.modulate = Color(1.0, 0.4, 0.4)
		boss_label.outline_modulate = Color(0.1, 0.1, 0.1)
		boss_label.outline_size = 12
		boss_label.position = Vector3(0, 4.8, 0)
		add_child(boss_label)
		
		# ボス壁のサイドに火花エフェクトを追加
		var left_spark := _create_boss_sparks(13.0)
		var right_spark := _create_boss_sparks(-13.0)
		add_child(left_spark)
		add_child(right_spark)
		boss_sparks.append(left_spark)
		boss_sparks.append(right_spark)
		
	elif not is_boss:
		if is_instance_valid(boss_label):
			boss_label.queue_free()
			boss_label = null
		for sp in boss_sparks:
			if is_instance_valid(sp):
				sp.queue_free()
		boss_sparks.clear()

func _create_boss_sparks(pos_x: float) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = 60
	sparks.lifetime = 0.8
	sparks.explosiveness = 0.05
	sparks.randomness = 1.0
	
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 3.5, 0.5)
	
	# 外側に向かって吹き出すようにする
	sparks.direction = Vector3(sign(pos_x), 0.5, 0.5).normalized()
	sparks.spread = 25.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 10.0
	
	sparks.gravity = Vector3(0, -12.0, 0)
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.25
	
	# ピカピカ光るマテリアル
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	
	var mesh := QuadMesh.new()
	mesh.material = mat
	sparks.mesh = mesh
	
	sparks.position = Vector3(pos_x, 0.5, 0.0)
	return sparks


func break_door(door_index: int) -> void:
	if door_index < 0 or door_index >= doors.size():
		return
	var door := doors[door_index]
	var door_color: Color = Color.WHITE
	if door.material_override:
		door_color = door.material_override.albedo_color
	var door_pos: Vector3 = door.global_position
	var door_size: Vector3 = (door.mesh as BoxMesh).size if door.mesh is BoxMesh else Vector3(2.0, 4.0, 1.0)

	# Hide original door and label
	door.visible = false
	if door_index < door_labels.size():
		door_labels[door_index].visible = false

	# Hide boss label if it exists
	if is_instance_valid(boss_label):
		boss_label.visible = false
	
	# Stop boss sparks
	for sp in boss_sparks:
		if is_instance_valid(sp):
			sp.emitting = false

	# Spawn debris chunks — fine fragmentation
	var chunks_x := 4
	var chunks_y := 5
	var chunk_size := Vector3(door_size.x / chunks_x, door_size.y / chunks_y, door_size.z)

	for cx: int in range(chunks_x):
		for cy: int in range(chunks_y):
			var chunk := RigidBody3D.new()
			chunk.mass = 0.6
			chunk.gravity_scale = 1.8

			# Collision shape
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			var size_variation: float = randf_range(0.7, 1.0)
			shape.size = chunk_size * 0.9 * size_variation
			col.shape = shape
			chunk.add_child(col)

			# Mesh
			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = chunk_size * 0.9 * size_variation
			mesh_inst.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = door_color.lerp(Color.WHITE, randf() * 0.2)
			mat.roughness = 0.6
			mat.metallic = 0.05
			mesh_inst.material_override = mat
			chunk.add_child(mesh_inst)

			# Position: offset from door center
			var offset_x: float = (cx - (chunks_x - 1) * 0.5) * chunk_size.x
			var offset_y: float = (cy - (chunks_y - 1) * 0.5) * chunk_size.y
			chunk.global_position = door_pos + Vector3(offset_x, offset_y, 0)

			# Collision layers: only collide with floor (layer 1), not players
			chunk.collision_layer = 0
			chunk.collision_mask = 1

			get_tree().current_scene.add_child(chunk)

			# Scatter in all directions: sideways, upward, and mixed forward/backward
			# so shards are visible in both 1P FPS (fly past the player) and 2P top-down
			var scatter_z: float
			if randf() < 0.4:
				# 40% fly backward (toward the player / camera) for FPS visibility
				scatter_z = randf_range(3.0, 8.0)
			else:
				# 60% fly forward (through the door opening)
				scatter_z = -randf_range(2.0, 7.0)

			var impulse := Vector3(
				(randf() - 0.5) * 10.0,  # wide sideways scatter
				randf() * 5.0 + 1.5,      # upward
				scatter_z
			)
			chunk.apply_impulse(impulse)
			chunk.apply_torque_impulse(Vector3(
				(randf() - 0.5) * 12.0,
				(randf() - 0.5) * 8.0,
				(randf() - 0.5) * 12.0
			))

			# Auto-cleanup after 3 seconds
			var timer := Timer.new()
			timer.wait_time = 3.0
			timer.one_shot = true
			timer.autostart = true
			chunk.add_child(timer)
			timer.timeout.connect(chunk.queue_free)

func _create_box(half_extents: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.05
	mesh_inst.material_override = mat

	return mesh_inst

func _create_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = 0.008
	label.width = 280.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.1, 0.1, 0.1, 1.0)
	label.outline_size = 8
	label.font_size = 48
	label.text = ""
	label.rotation.y = PI

	# Load Japanese font
	var font := load("res://resources/fonts/NotoSansJP-Regular.otf")
	if font:
		label.font = font

	return label
