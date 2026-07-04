extends Node3D

## クイズの壁 + ドア (2個 or 4個)
## Python版 renderer.py の _draw_wall_doors + _draw_labels に相当

var wall_parts: Array[MeshInstance3D] = []
var doors: Array[MeshInstance3D] = []
var door_labels: Array[Label3D] = []

var is_boss: bool = false
var boss_label: Label3D = null
var boss_sparks: Array[CPUParticles3D] = []

# メニュー背景プレビュー用: カメラ側(+Z)を向いた問題文・選択肢ラベル
# (通常の door_labels はプレイヤー側(-Z)向きでメニューカメラからは見えない)
var preview_question_label: Label3D = null
var preview_choice_labels: Array[Label3D] = []



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
## 壁本体の物理的な最上端(Y座標)。メニュー背景プレビューの問題文はこの高さより
## 確実に上に留めるための基準として参照する。
const WALL_TOP_Y: float = 4.05

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
	var total_width := 24.0
	var min_x := -12.0
	var max_x := 12.0
	var door_top_y := 2.38
	var door_bottom_y := -2.02
	var wall_top_y := WALL_TOP_Y
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

func set_labels_visible(is_visible: bool) -> void:
	for label: Label3D in door_labels:
		if is_instance_valid(label):
			label.visible = is_visible


## メニュー背景プレビュー用: 問題文と選択肢をカメラ側(+Z)の面に表示する (2択専用)
func set_preview_labels(quiz: QuizItem) -> void:
	_clear_preview_labels()
	if not quiz or quiz.q.is_empty():
		return

	preview_question_label = _create_label()
	preview_question_label.rotation.y = 0.0
	# Y座標は _fit_question_label_to_two_lines 内で壁と衝突しない位置に決定する
	preview_question_label.position = Vector3(0, 0, 0.65)
	preview_question_label.width = 640.0
	# 遠くの壁でも読めるよう純黒の太アウトラインで縁取ってコントラストを上げる
	preview_question_label.outline_modulate = Color(0, 0, 0, 1.0)
	preview_question_label.outline_size = 16
	var question_text: String = FractionFormatter.to_inline(quiz.q) if FractionFormatter.has_fraction(quiz.q) else quiz.q
	add_child(preview_question_label)
	_fit_question_label_to_two_lines(preview_question_label, question_text)

	var door_xs := [LEFT_DOOR_X, RIGHT_DOOR_X]
	for i: int in range(mini(2, quiz.c.size())):
		var lbl := _create_label()
		lbl.rotation.y = 0.0
		lbl.position = Vector3(door_xs[i], 0.18, 0.65)
		lbl.width = 200.0
		lbl.font_size = 56
		lbl.outline_modulate = Color(0, 0, 0, 1.0)
		lbl.outline_size = 16
		lbl.text = FractionFormatter.format_choice(quiz.c[i])
		add_child(lbl)
		preview_choice_labels.append(lbl)


const QUESTION_LABEL_MAX_LINES := 2
## 1行でも2行でも常にこの大きさで表示する（行数によって縮小しない）
const QUESTION_LABEL_FONT_SIZE := 52
## 壁の最上端(WALL_TOP_Y)から問題文の下端までの最低クリアランス
const QUESTION_LABEL_WALL_CLEARANCE := 0.5
## 横幅の初期値・拡張刻み・上限（壁全幅24mに対して十分小さく、省略せず全文表示するために広げる）
const QUESTION_LABEL_BASE_WIDTH := 640.0
const QUESTION_LABEL_WIDTH_STEP := 80.0
const QUESTION_LABEL_MAX_WIDTH := 1600.0

## 問題文ラベルは1行・2行のどちらでも同じ文字サイズで表示し、省略はしない。
## 2行に収まらない場合は横幅を段階的に広げて全文を表示する（上限に達したらそこで止める）。
## 縦位置は「下端」を壁の最上端より確実に上の固定位置にアンカーし、行数が増えても
## 上方向にしか伸びないようにすることで、絶対に壁と重ならないようにする。
func _fit_question_label_to_two_lines(label: Label3D, text: String) -> void:
	if not label:
		return
	var font: Font = label.font if label.font else ThemeDB.fallback_font
	var break_flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var font_size := QUESTION_LABEL_FONT_SIZE
	label.font_size = font_size
	label.text = text

	var width := QUESTION_LABEL_BASE_WIDTH
	while width < QUESTION_LABEL_MAX_WIDTH and _measure_line_count(text, font, font_size, width, break_flags) > QUESTION_LABEL_MAX_LINES:
		width = minf(width + QUESTION_LABEL_WIDTH_STEP, QUESTION_LABEL_MAX_WIDTH)
	label.width = width

	# 下端を壁の最上端より確実に上へ固定し、行数が増えても壁側(下方向)へは伸びないようにする
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position.y = WALL_TOP_Y + QUESTION_LABEL_WALL_CLEARANCE

func _measure_line_count(text: String, font: Font, font_size: int, width: float, break_flags: int) -> int:
	var tp := TextParagraph.new()
	tp.width = width
	tp.break_flags = break_flags
	tp.add_string(text, font, font_size)
	return maxi(1, tp.get_line_count())


func _clear_preview_labels() -> void:
	if is_instance_valid(preview_question_label):
		preview_question_label.queue_free()
	preview_question_label = null
	for lbl: Label3D in preview_choice_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	preview_choice_labels.clear()


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
	if not door.visible:
		return
	# global_position はツリー内でのみ有効。ツリー外で読むと identity を返し
	# !is_inside_tree() エラーを毎回吐くため、ツリー外なら破砕をスキップする。
	if not door.is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	var door_color: Color = Color.WHITE
	if door.material_override:
		door_color = door.material_override.albedo_color
	var door_pos: Vector3 = door.global_position
	var door_size: Vector3 = (door.mesh as BoxMesh).size if door.mesh is BoxMesh else Vector3(2.0, 4.0, 1.0)

	# Hide original door and label
	door.visible = false
	if door_index < door_labels.size():
		door_labels[door_index].visible = false
	if door_index < preview_choice_labels.size() and is_instance_valid(preview_choice_labels[door_index]):
		preview_choice_labels[door_index].visible = false

	# Hide boss label if it exists
	if is_instance_valid(boss_label):
		boss_label.visible = false
	
	# Stop boss sparks
	for sp in boss_sparks:
		if is_instance_valid(sp):
			sp.emitting = false

	# Spawn debris chunks — fine fragmentation
	var vp := door.get_viewport()
	var is_preview_subviewport := vp is SubViewport
	var chunks_x := 2 if is_preview_subviewport else 4
	var chunks_y := 2 if is_preview_subviewport else 5
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

			# Collision layers: only collide with floor (layer 1), not players
			chunk.collision_layer = 0
			chunk.collision_mask = 1

			# 先にツリーへ追加してから global_position を設定する。
			# ツリー外で global_position を書くと get_global_transform() が
			# identity を返し !is_inside_tree() エラーを毎回吐く。
			parent.add_child(chunk)
			chunk.global_position = door_pos + Vector3(offset_x, offset_y, 0)

			if is_preview_subviewport:
				# 扉欠片だけ強めに弾け、短いTweenで縮小消滅（カメラ縮小処理とは別）
				chunk.set_meta("preview_door_shard", true)
				chunk.mass = 1.22
				chunk.gravity_scale = 2.35
				chunk.linear_damp = 0.09
				chunk.angular_damp = 0.14
				chunk.collision_mask = 1
				chunk.apply_central_impulse(
					Vector3(
						randf_range(-2.35, 2.35),
						randf_range(0.45, 3.15),
						randf_range(-26.5, -14.0),
					)
				)
				chunk.apply_torque_impulse(
					Vector3(
						randf_range(-3.6, 3.6),
						randf_range(-2.5, 2.5),
						randf_range(-3.6, 3.6),
					)
				)
				var vanish_tw := chunk.create_tween()
				vanish_tw.tween_interval(0.22)
				vanish_tw.tween_property(mesh_inst, "scale", Vector3.ZERO, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				vanish_tw.tween_callback(chunk.queue_free)
			else:
				# 本番：前方に飛ばす（画面手前側、+Z方向）＋縮小で消滅
				var scatter_z: float = randf_range(5.0, 15.0)
				var impulse := Vector3(
					(randf() - 0.5) * 10.0,
					randf() * 5.0 + 1.5,
					scatter_z
				)
				chunk.apply_central_impulse(impulse)
				chunk.apply_torque_impulse(Vector3(
					(randf() - 0.5) * 12.0,
					(randf() - 0.5) * 8.0,
					(randf() - 0.5) * 12.0
				))
				var tween := chunk.create_tween()
				tween.tween_interval(1.5)
				tween.tween_property(mesh_inst, "scale", Vector3.ZERO, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				tween.tween_callback(chunk.queue_free)

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

func shatter_wall(direction_z: float = -1.0) -> void:
	for part in wall_parts:
		if is_instance_valid(part) and part.visible:
			_shatter_mesh(part, direction_z)
			part.visible = false
	for door in doors:
		if is_instance_valid(door) and door.visible:
			_shatter_mesh(door, direction_z)
			door.visible = false
	for label in door_labels:
		if is_instance_valid(label):
			label.visible = false
	if is_instance_valid(boss_label):
		boss_label.visible = false
	if is_instance_valid(preview_question_label):
		preview_question_label.visible = false
	for plbl in preview_choice_labels:
		if is_instance_valid(plbl):
			plbl.visible = false

func _shatter_mesh(mesh_inst: MeshInstance3D, direction_z: float) -> void:
	if not is_instance_valid(mesh_inst): return
	var box := mesh_inst.mesh as BoxMesh
	if not box: return
	
	var base_color := WALL_COLOR
	if mesh_inst.material_override and mesh_inst.material_override is StandardMaterial3D:
		base_color = (mesh_inst.material_override as StandardMaterial3D).albedo_color
		
	# global_position はツリー内でのみ有効。ツリー外で読むと identity を返し
	# !is_inside_tree() エラーを毎回吐くため、ツリー外なら破砕をスキップする。
	if not mesh_inst.is_inside_tree(): return
	var parent := get_parent()
	if parent == null: return

	var size := box.size
	var pos := mesh_inst.global_position

	var chunks_x := maxi(1, ceili(size.x / 1.5))
	var chunks_y := maxi(1, ceili(size.y / 1.5))
	var chunk_size := Vector3(size.x / chunks_x, size.y / chunks_y, size.z)
	
	for cx: int in range(chunks_x):
		for cy: int in range(chunks_y):
			var chunk := RigidBody3D.new()
			chunk.mass = 0.5
			chunk.gravity_scale = 1.8
			chunk.collision_layer = 0
			chunk.collision_mask = 1
			
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			var size_variation: float = randf_range(0.7, 0.95)
			shape.size = chunk_size * size_variation
			col.shape = shape
			chunk.add_child(col)
			
			var cmi := MeshInstance3D.new()
			var cbox := BoxMesh.new()
			cbox.size = chunk_size * size_variation
			cmi.mesh = cbox
			var mat := StandardMaterial3D.new()
			mat.albedo_color = base_color.lerp(Color.WHITE, randf() * 0.2)
			mat.roughness = 0.6
			mat.metallic = 0.05
			cmi.material_override = mat
			chunk.add_child(cmi)
			
			var offset_x: float = (cx - (chunks_x - 1) * 0.5) * chunk_size.x
			var offset_y: float = (cy - (chunks_y - 1) * 0.5) * chunk_size.y

			# 先にツリーへ追加してから global_position を設定する。
			# ツリー外で global_position を書くと get_global_transform() が
			# identity を返し !is_inside_tree() エラーを毎回吐く。
			parent.add_child(chunk)
			chunk.global_position = pos + Vector3(offset_x, offset_y, 0)
			
			var vp := chunk.get_viewport()
			var is_preview_subviewport := vp is SubViewport
			if is_preview_subviewport:
				chunk.set_meta("preview_door_shard", true)
				chunk.mass = 1.1
				chunk.gravity_scale = 2.2
				chunk.linear_damp = 0.12
				chunk.angular_damp = 0.16
				chunk.apply_central_impulse(
					Vector3(
						randf_range(-2.8, 2.8),
						randf_range(0.5, 3.4),
						randf_range(12.0, 24.0) * direction_z,
					)
				)
				chunk.apply_torque_impulse(
					Vector3(
						randf_range(-4.0, 4.0),
						randf_range(-3.0, 3.0),
						randf_range(-4.0, 4.0),
					)
				)
				var vanish_tw := chunk.create_tween()
				vanish_tw.tween_interval(0.25)
				vanish_tw.tween_property(cmi, "scale", Vector3.ZERO, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				vanish_tw.tween_callback(chunk.queue_free)
			else:
				# 進行方向（direction_z）へ爆散させる
				var impulse_x: float = (randf() - 0.5) * 30.0 # 左右への強い散らばり
				var impulse_y: float = randf_range(5.0, 25.0) # 上方向への強い吹き飛ばし
				var impulse_z: float = randf_range(10.0, 40.0) * direction_z # 指定方向へ大きく飛ばす
				
				var impulse := Vector3(impulse_x, impulse_y, impulse_z)
				chunk.apply_central_impulse(impulse)
				chunk.apply_torque_impulse(Vector3(
					(randf() - 0.5) * 40.0,
					(randf() - 0.5) * 40.0,
					(randf() - 0.5) * 40.0
				))
				
				# 縮小しながら消滅する演出
				var tween := chunk.create_tween()
				tween.tween_interval(1.5)
				tween.tween_property(cmi, "scale", Vector3.ZERO, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				tween.tween_callback(chunk.queue_free)

const MAGMA_DEBRIS_MASS: float = 3.2
const MAGMA_DEBRIS_GRAVITY_SCALE: float = 2.4
const MAGMA_DEBRIS_LINEAR_DAMP: float = 0.28
const MAGMA_DEBRIS_ANGULAR_DAMP: float = 0.38
const MAGMA_DEBRIS_IMP_X: float = 0.36
const MAGMA_DEBRIS_IMP_Y: float = 0.48
const MAGMA_DEBRIS_IMP_Z_MIN: float = 1.85
const MAGMA_DEBRIS_IMP_Z_MAX: float = 3.85
const MAGMA_DEBRIS_TORQUE: float = 0.52
const MAGMA_DEBRIS_LIFETIME_SEC: float = 5.0

## 崖に到達した壁を、扉破壊の爆散(shatter_wall)とは別の
## 静かな「ボトッ」落下でマグマへ崩す。実ゲーム・各種プレビュー共通の見た目。
func collapse_into_magma() -> void:
	for part in wall_parts:
		if is_instance_valid(part) and part.visible:
			_drop_mesh_into_magma(part)
			part.visible = false
	for door in doors:
		if is_instance_valid(door) and door.visible:
			_drop_mesh_into_magma(door)
			door.visible = false
	for label in door_labels:
		if is_instance_valid(label):
			label.visible = false
	if is_instance_valid(boss_label):
		boss_label.visible = false
	if is_instance_valid(preview_question_label):
		preview_question_label.visible = false
	for plbl in preview_choice_labels:
		if is_instance_valid(plbl):
			plbl.visible = false

func _drop_mesh_into_magma(mesh_inst: MeshInstance3D) -> void:
	if not mesh_inst.is_inside_tree(): return
	var box := mesh_inst.mesh as BoxMesh
	if not box: return
	var parent := get_parent()
	if parent == null: return

	var piece := RigidBody3D.new()
	piece.mass = MAGMA_DEBRIS_MASS
	piece.gravity_scale = MAGMA_DEBRIS_GRAVITY_SCALE
	piece.linear_damp = MAGMA_DEBRIS_LINEAR_DAMP
	piece.angular_damp = MAGMA_DEBRIS_ANGULAR_DAMP
	piece.collision_layer = 0
	piece.collision_mask = 1

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	piece.add_child(col)

	var cmi := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = box.size
	cmi.mesh = cbox
	if mesh_inst.material_override:
		cmi.material_override = mesh_inst.material_override.duplicate()
	piece.add_child(cmi)

	parent.add_child(piece)
	piece.global_transform = mesh_inst.global_transform

	# Z-: 崖の奥(マグマ側) / Z+: 床が残っているコンベア側。
	# wall.position.z は world_scroll_z の増加で減っていき、崖(FLOOR_BACK_Z)の先＝マグマは-Z側にあるため、
	# 崩落時はコンベア側(+Z)に戻さず -Z 方向へ押し出す。
	piece.apply_central_impulse(Vector3(
		randf_range(-MAGMA_DEBRIS_IMP_X, MAGMA_DEBRIS_IMP_X),
		randf_range(0.0, MAGMA_DEBRIS_IMP_Y),
		randf_range(-MAGMA_DEBRIS_IMP_Z_MAX, -MAGMA_DEBRIS_IMP_Z_MIN),
	))
	piece.apply_torque_impulse(Vector3(
		randf_range(-MAGMA_DEBRIS_TORQUE, MAGMA_DEBRIS_TORQUE),
		randf_range(-MAGMA_DEBRIS_TORQUE * 0.62, MAGMA_DEBRIS_TORQUE * 0.62),
		randf_range(-MAGMA_DEBRIS_TORQUE, MAGMA_DEBRIS_TORQUE),
	))

	var tw := piece.create_tween()
	tw.tween_interval(MAGMA_DEBRIS_LIFETIME_SEC)
	tw.tween_callback(func() -> void:
		if is_instance_valid(piece):
			piece.queue_free()
	)
