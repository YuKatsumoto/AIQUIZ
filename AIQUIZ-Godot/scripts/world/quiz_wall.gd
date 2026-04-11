extends Node3D

## クイズの壁 + ドア (2個 or 4個)
## Python版 renderer.py の _draw_wall_doors + _draw_labels に相当

var wall_mesh: MeshInstance3D
var doors: Array[MeshInstance3D] = []
var door_labels: Array[Label3D] = []

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
const LEFT_DOOR_X: float = 2.8
const RIGHT_DOOR_X: float = -2.8
const DOOR4_XS: Array[float] = [-5.8, -1.95, 1.95, 5.8]

var _current_num_choices: int = 2

func _ready() -> void:
	_build_wall()
	_build_doors(2)

func _build_wall() -> void:
	wall_mesh = _create_box(Vector3(14.0, 3.6, 0.55), WALL_COLOR)
	wall_mesh.position = Vector3(0, 0.45, 0)
	add_child(wall_mesh)

func _build_doors(num_choices: int) -> void:
	_current_num_choices = num_choices
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
				door_labels[i].text = "%s. %s" % [labels_4[i], quiz.c[i]]
	else:
		if door_labels.size() >= 2:
			door_labels[0].text = quiz.c[0] if quiz.c.size() > 0 else ""
			door_labels[1].text = quiz.c[1] if quiz.c.size() > 1 else ""

func break_door(door_index: int) -> void:
	if door_index >= 0 and door_index < doors.size():
		var door := doors[door_index]
		# 扉が崩れ落ちるようなアニメーション（スケールを潰して下へ）
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(door, "scale", Vector3(1.1, 0.05, 1.1), 0.15)
		tween.tween_property(door, "position:y", -0.5, 0.15)
		
		if door_index < door_labels.size():
			var label := door_labels[door_index]
			var l_tween := create_tween()
			l_tween.tween_property(label, "modulate:a", 0.0, 0.1)

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
