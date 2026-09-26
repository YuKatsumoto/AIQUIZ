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

var gameplay_question_label: Label3D = null
var _gameplay_question_panel: MeshInstance3D = null
var _gameplay_question_border: MeshInstance3D = null
var _gameplay_question_text: String = ""
## 背景パネル付きラベル原点から、パネル下端を扉上へ揃えるための局所オフセット。
var _gameplay_question_anchor_offset: float = 0.0
## 2Pでカメラが離れたときの問題文・選択肢の拡大率。
var _text_scale: float = 1.0
var _scaled_beam_mesh: BoxMesh = null
## 文字拡大でボス見出しが押し上げられた量 (等倍レイアウトの枠取り用)。
var _boss_scale_lift: float = 0.0
var _shattered: bool = false
var _saw_collision_shapes: Dictionary = {}

func _physics_process(_dt: float) -> void:
	# Only saw-launched bodies opt into this layer. Match each visible solid so
	# broken doors stay open and retired walls never leave an invisible barrier.
	for mesh: MeshInstance3D in wall_parts + doors:
		if not is_instance_valid(mesh) or mesh.is_queued_for_deletion():
			continue
		if not _saw_collision_shapes.has(mesh.get_instance_id()):
			var body := AnimatableBody3D.new()
			body.name = "SawBodyCollision"
			body.collision_layer = SawChaseState.WALL_COLLISION_LAYER
			body.collision_mask = 0
			body.sync_to_physics = false
			mesh.add_child(body)
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = mesh.get_aabb().size
			collision.shape = box
			collision.position = mesh.get_aabb().get_center()
			body.add_child(collision)
			_saw_collision_shapes[mesh.get_instance_id()] = collision
		var shape: CollisionShape3D = _saw_collision_shapes[mesh.get_instance_id()]
		var size := mesh.get_aabb().size
		if (shape.shape as BoxShape3D).size != size:
			(shape.shape as BoxShape3D).size = size
		var disabled := not mesh.is_visible_in_tree() or _retiring_after_pass or _shattered
		if shape.disabled != disabled:
			shape.disabled = disabled
	for id: int in _saw_collision_shapes.keys():
		if not is_instance_valid(_saw_collision_shapes[id]):
			_saw_collision_shapes.erase(id)



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
const BOSS_WALL_COLOR := Color(0.65, 0.15, 0.15)
const JAPANESE_FONT: Font = preload("res://resources/fonts/NotoSansJP-Regular.otf")
## 問題文の実寸に合わせ、上端に小さな余白だけ残す。
var wall_top_y: float = 4.05
const QUESTION_TOP_MARGIN: float = 0.180
const DOOR_TOP_Y: float = 2.38
const QUESTION_DOOR_GAP: float = 0.18

# Door positions from tuning
const LEFT_DOOR_X: float = 3.5
const RIGHT_DOOR_X: float = -3.5
const DOOR4_XS: Array[float] = [-5.8, -1.95, 1.95, 5.8]

## 問題の壁はコンベア床端より各側をわずかに内側へ収める。
const WALL_EDGE_INSET: float = 0.10

var _current_num_choices: int = 2
var _retiring_after_pass: bool = false
var _retirement_finished: bool = false

## 同じサイズ・色の箱はRIDを再利用し、枚ごとのGPUアップロードを避ける。
static var _box_mesh_cache: Dictionary = {}
static var _opaque_material_cache: Dictionary = {}

func _ready() -> void:
	wall_top_y = _minimum_wall_top_y()
	_build_doors(2)



func _build_wall_around_doors(num_choices: int) -> void:
	# Clear existing wall parts
	for part in wall_parts:
		if is_instance_valid(part):
			part.queue_free()
	wall_parts.clear()

	# Wall dimensions (matching original single box)
	var total_width: float = StageConstants.FLOOR_WIDTH - WALL_EDGE_INSET * 2.0
	var min_x: float = -total_width * 0.5
	var max_x: float = total_width * 0.5
	var door_top_y := DOOR_TOP_Y
	var door_bottom_y := -2.02
	var wall_bottom_y := -3.15
	var wall_color := BOSS_WALL_COLOR if is_boss else WALL_COLOR

	# 1. Top beam
	var top_height := wall_top_y - door_top_y
	var top_beam := _create_box(Vector3(total_width / 2.0, top_height / 2.0, 0.55), wall_color)
	top_beam.position = Vector3(0, door_top_y + top_height / 2.0, 0)
	add_child(top_beam)
	wall_parts.append(top_beam)

	# 2. Bottom beam
	var bottom_height := door_bottom_y - wall_bottom_y
	var bottom_beam := _create_box(Vector3(total_width / 2.0, bottom_height / 2.0, 0.55), wall_color)
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
			var pillar := _create_box(Vector3(pillar_width / 2.0, pillar_height / 2.0, 0.55), wall_color)
			pillar.position = Vector3(current_x + pillar_width / 2.0, pillar_y, 0)
			add_child(pillar)
			wall_parts.append(pillar)
		
		current_x = door_right
	
	var final_width := max_x - current_x
	if final_width > 0:
		var pillar := _create_box(Vector3(final_width / 2.0, pillar_height / 2.0, 0.55), wall_color)
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
			label.scale = Vector3.ONE * _text_scale
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
		left_label.scale = Vector3.ONE * _text_scale
		add_child(left_label)
		door_labels.append(left_label)

		# Right door (Red)
		var right_door := _create_box(Vector3(1.8, 2.2, 0.60), DOOR_COLORS_2[1])
		right_door.position = Vector3(RIGHT_DOOR_X, 0.18, 0)
		add_child(right_door)
		doors.append(right_door)

		var right_label := _create_label()
		right_label.position = Vector3(RIGHT_DOOR_X, 0.18, -0.65)
		right_label.scale = Vector3.ONE * _text_scale
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
	if not is_visible:
		set_gameplay_question_visible(false)


## Gameplay faces -Z; the menu keeps its independent +Z labels.
## Called repeatedly by GameWorld, so shaping only runs when the text changes.
func set_gameplay_question(text: String, is_visible: bool) -> void:
	if text.is_empty():
		set_gameplay_question_visible(false)
		return
	if not is_instance_valid(gameplay_question_label):
		gameplay_question_label = _create_label()
		gameplay_question_label.name = "GameplayQuestion"
		gameplay_question_label.position.z = -0.65
		gameplay_question_label.outline_modulate = Color(0.02, 0.05, 0.08, 0.95)
		gameplay_question_label.scale = Vector3.ONE * _text_scale
		add_child(gameplay_question_label)
	if text != _gameplay_question_text:
		_gameplay_question_text = text
		_fit_question_label_to_two_lines(gameplay_question_label, text)
		# Label3D redraws its glyph mesh in the deferred queue after text changes.
		_update_gameplay_question_panel.call_deferred()
	set_gameplay_question_visible(is_visible)


func set_gameplay_question_visible(is_visible: bool) -> void:
	if is_instance_valid(gameplay_question_label):
		gameplay_question_label.visible = is_visible and not _retiring_after_pass and not _shattered


## A solid gray backing keeps the sky and scenery out of the question text.
## Child meshes inherit the label's orientation, visibility and retirement.
func _update_gameplay_question_panel() -> void:
	if not is_instance_valid(_gameplay_question_panel):
		_gameplay_question_border = _create_question_panel_quad("QuestionBorder", Color(0.60, 0.60, 0.60))
		_gameplay_question_panel = _create_question_panel_quad("QuestionBackground", Color(0.35, 0.35, 0.35))
	var glyph_bounds := gameplay_question_label.get_aabb()
	var center := glyph_bounds.get_center()
	var padding := Vector2(0.28, 0.18)
	var panel_size := Vector2(glyph_bounds.size.x, glyph_bounds.size.y) + padding * 2.0
	(_gameplay_question_panel.mesh as QuadMesh).size = panel_size
	(_gameplay_question_border.mesh as QuadMesh).size = panel_size + Vector2.ONE * 0.05
	# Negative local Z is behind the text, on both the -Z and +Z wall faces.
	_gameplay_question_panel.position = Vector3(center.x, center.y, -0.035)
	_gameplay_question_border.position = Vector3(center.x, center.y, -0.045)
	_gameplay_question_anchor_offset = -glyph_bounds.position.y + padding.y + 0.025
	_apply_gameplay_question_anchor()


## Anchor the visible panel edge just above the door, independent of line count
## and of the 2P text scale (the panel is a child and scales with the label).
func _apply_gameplay_question_anchor() -> void:
	gameplay_question_label.position.y = DOOR_TOP_Y + QUESTION_DOOR_GAP + _gameplay_question_anchor_offset * _text_scale
	_update_question_wall_height()


## 2P: カメラが離れた分だけ問題文と選択肢を中心基準で拡大する。1Pや通常距離では 1.0。
func set_text_scale(text_scale: float) -> void:
	text_scale = maxf(text_scale, 1.0)
	if text_scale == _text_scale or (text_scale > 1.0 and absf(text_scale - _text_scale) < 0.002):
		return
	_text_scale = text_scale
	for label: Label3D in door_labels:
		if is_instance_valid(label):
			label.scale = Vector3.ONE * _text_scale
	if not is_instance_valid(gameplay_question_label):
		return
	gameplay_question_label.scale = Vector3.ONE * _text_scale
	if is_instance_valid(_gameplay_question_panel):
		_apply_gameplay_question_anchor()


func _minimum_wall_top_y() -> float:
	# Reserve two lines at the actual question font size, plus the existing panel padding/border.
	var two_line_height := JAPANESE_FONT.get_height(QUESTION_LABEL_FONT_SIZE) * 0.008 * 2.0
	return DOOR_TOP_Y + QUESTION_DOOR_GAP + two_line_height + 0.41 + QUESTION_TOP_MARGIN


func _update_question_wall_height() -> void:
	if wall_parts.is_empty() or not is_instance_valid(wall_parts[0]):
		return
	# The panel bottom stays on this line, so everything above it scales linearly.
	var question_floor := DOOR_TOP_Y + QUESTION_DOOR_GAP
	# Keep the two-line reserve at the current text scale so one- and two-line
	# questions still share the wall height while 2P text is enlarged.
	var minimum_content_top := question_floor + (_minimum_wall_top_y() - QUESTION_TOP_MARGIN - question_floor) * _text_scale
	var content_top := minimum_content_top
	if is_instance_valid(_gameplay_question_border):
		var panel_bounds: AABB = (gameplay_question_label.transform * _gameplay_question_border.transform) * _gameplay_question_border.get_aabb()
		content_top = panel_bounds.end.y
	elif is_instance_valid(preview_question_label):
		var text_bounds := preview_question_label.transform * preview_question_label.get_aabb()
		content_top = text_bounds.end.y + preview_question_label.outline_size * preview_question_label.pixel_size
	content_top = maxf(content_top, minimum_content_top)
	_boss_scale_lift = 0.0
	if is_boss and is_instance_valid(boss_label):
		var heading_bounds := boss_label.get_aabb().grow(boss_label.outline_size * boss_label.pixel_size)
		boss_label.position.y = content_top + QUESTION_TOP_MARGIN - heading_bounds.position.y
		var base_content_top := question_floor + (content_top - question_floor) / _text_scale
		_boss_scale_lift = content_top - base_content_top
		content_top = boss_label.position.y + heading_bounds.end.y
	wall_top_y = content_top + QUESTION_TOP_MARGIN
	var beam := wall_parts[0]
	var beam_size := (beam.mesh as BoxMesh).size
	beam_size.y = wall_top_y - DOOR_TOP_Y
	if _text_scale > 1.0:
		# The 2P text scale eases every frame; resize a wall-owned box instead of
		# filling the shared cache with one mesh per intermediate height.
		if beam.mesh != _scaled_beam_mesh:
			_scaled_beam_mesh = BoxMesh.new()
			beam.mesh = _scaled_beam_mesh
		_scaled_beam_mesh.size = beam_size
	else:
		# Shared cached meshes are immutable; other walls keep their own height.
		beam.mesh = _shared_box_mesh(beam_size)
	beam.position.y = DOOR_TOP_Y + beam_size.y * 0.5


func _create_question_panel_quad(node_name: String, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	panel.mesh = QuadMesh.new()
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_fog = true
	panel.material_override = material
	gameplay_question_label.add_child(panel)
	return panel


## Actual glyph bounds, including the outline, for camera framing.
## at_base_scale: the same layout without the 2P text scale. The saw retreat
## uses it so enlarged text never feeds back into a larger camera pull-back.
func get_gameplay_framing_points(at_base_scale: bool = false) -> PackedVector3Array:
	var points := PackedVector3Array()
	if not is_instance_valid(gameplay_question_label) or not gameplay_question_label.is_visible_in_tree():
		return points
	var question_xform := _framing_transform(gameplay_question_label, at_base_scale)
	_append_label_framing_points(points, gameplay_question_label, question_xform)
	if is_instance_valid(boss_label) and boss_label.is_visible_in_tree():
		_append_label_framing_points(points, boss_label, _framing_transform(boss_label, at_base_scale))
	if is_instance_valid(_gameplay_question_border):
		var panel_bounds := _gameplay_question_border.get_aabb()
		var panel_xform := question_xform * _gameplay_question_border.transform
		for corner: int in range(8):
			points.append(panel_xform * panel_bounds.get_endpoint(corner))
	for label: Label3D in door_labels:
		if is_instance_valid(label) and label.is_visible_in_tree():
			_append_label_framing_points(points, label, _framing_transform(label, at_base_scale))
	return points


func _framing_transform(node: Node3D, at_base_scale: bool) -> Transform3D:
	if not at_base_scale or _text_scale == 1.0:
		return node.global_transform
	var local := node.transform
	if node == boss_label:
		local.origin.y -= _boss_scale_lift
	else:
		local.basis = local.basis.scaled(Vector3.ONE / _text_scale)
		if node == gameplay_question_label and is_instance_valid(_gameplay_question_panel):
			local.origin.y = DOOR_TOP_Y + QUESTION_DOOR_GAP + _gameplay_question_anchor_offset
	return global_transform * local


func _append_label_framing_points(points: PackedVector3Array, label: Label3D, xform: Transform3D) -> void:
	var bounds := label.get_aabb().grow(label.outline_size * label.pixel_size)
	for corner: int in range(8):
		points.append(xform * bounds.get_endpoint(corner))


## 1P用: プレイヤーが通過した壁を、文字を残さず短くフェード退場させる。
func retire_after_player_pass(fade_duration: float = 0.28) -> void:
	if _retiring_after_pass:
		return
	_retiring_after_pass = true
	_retirement_finished = false
	set_labels_visible(false)
	if is_instance_valid(boss_label):
		boss_label.visible = false
	for sparks: CPUParticles3D in boss_sparks:
		if is_instance_valid(sparks):
			sparks.emitting = false
			sparks.visible = false
	for part: MeshInstance3D in wall_parts:
		_fade_mesh_to_transparent(part, fade_duration)
	for door: MeshInstance3D in doors:
		_fade_mesh_to_transparent(door, fade_duration)
	var finish_tween: Tween = create_tween()
	finish_tween.tween_interval(fade_duration)
	finish_tween.tween_callback(_mark_retirement_finished)


func is_retiring_after_pass() -> bool:
	return _retiring_after_pass


func is_retirement_finished() -> bool:
	return _retirement_finished


func _fade_mesh_to_transparent(mesh_inst: MeshInstance3D, fade_duration: float) -> void:
	if not is_instance_valid(mesh_inst):
		return
	var material: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
	if material == null:
		return
	var unique_material: StandardMaterial3D = material.duplicate() as StandardMaterial3D
	mesh_inst.material_override = unique_material
	unique_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color: Color = unique_material.albedo_color
	var target_color := Color(color.r, color.g, color.b, 0.0)
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(unique_material, "albedo_color", target_color, fade_duration)


func _mark_retirement_finished() -> void:
	_retirement_finished = true


## メニュー背景プレビュー用: 問題文と選択肢をカメラ側(+Z)の面に表示する (2択専用)
func set_preview_labels(quiz: QuizItem) -> void:
	_clear_preview_labels()
	if not quiz or quiz.q.is_empty():
		return

	preview_question_label = _create_label()
	preview_question_label.rotation.y = 0.0
	# 問題文はゲームと同じく扉のすぐ上の壁面に表示する
	preview_question_label.position = Vector3(0, 0, 0.65)
	preview_question_label.width = 640.0
	# 遠景で塗りと輪郭が競合しないよう、細めの濃紺アウトラインでコントラストを保つ
	preview_question_label.outline_modulate = Color(0.02, 0.05, 0.08, 0.95)
	preview_question_label.outline_size = 8
	var question_text: String = FractionFormatter.to_inline(quiz.q) if FractionFormatter.has_fraction(quiz.q) else quiz.q
	add_child(preview_question_label)
	_fit_question_label_to_two_lines(preview_question_label, question_text)
	_update_question_wall_height.call_deferred()

	var door_xs := [LEFT_DOOR_X, RIGHT_DOOR_X]
	for i: int in range(mini(2, quiz.c.size())):
		var lbl := _create_label()
		lbl.rotation.y = 0.0
		lbl.position = Vector3(door_xs[i], 0.18, 0.65)
		lbl.width = 200.0
		lbl.font_size = 64
		lbl.outline_modulate = Color(0.02, 0.05, 0.08, 0.95)
		lbl.outline_size = 8
		lbl.text = FractionFormatter.format_choice(quiz.c[i])
		add_child(lbl)
		preview_choice_labels.append(lbl)


const QUESTION_LABEL_MAX_LINES := 2
## 1行でも2行でも常にこの大きさで表示する（行数によって縮小しない）
const QUESTION_LABEL_FONT_SIZE := 64
## 扉から文字の下端までの余白（ゲームでは背景パネルの実寸でも補正する）
const QUESTION_LABEL_DOOR_CLEARANCE := 0.45
## 横幅の初期値・拡張刻み・上限（壁全幅24mに対して十分小さく、省略せず全文表示するために広げる）
const QUESTION_LABEL_BASE_WIDTH := 640.0
const QUESTION_LABEL_WIDTH_STEP := 80.0
const QUESTION_LABEL_MAX_WIDTH := 1600.0

## 問題文ラベルは1行・2行のどちらでも同じ文字サイズで表示し、省略はしない。
## 2行に収まらない場合は横幅を段階的に広げて全文を表示する（上限に達したらそこで止める）。
## 下端を扉の上端へ固定し、行数が増えたら壁面の上方向へ伸ばす。
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

	# 行数によらず、問題文を扉のすぐ上に揃える。
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position.y = DOOR_TOP_Y + QUESTION_LABEL_DOOR_CLEARANCE

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
	var target_color = BOSS_WALL_COLOR if is_boss else WALL_COLOR
	for part in wall_parts:
		if is_instance_valid(part):
			part.material_override = _shared_opaque_material(target_color)
	
	if is_boss and not is_instance_valid(boss_label):
		boss_label = _create_label()
		boss_label.text = "BOSS問題"
		boss_label.font_size = 72
		boss_label.modulate = Color(1.0, 0.4, 0.4)
		boss_label.outline_modulate = Color(0.1, 0.1, 0.1)
		boss_label.outline_size = 12
		boss_label.position = Vector3(0, wall_top_y - 0.55, -0.65)
		boss_label.width = QUESTION_LABEL_BASE_WIDTH
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
	_update_question_wall_height.call_deferred()

func _create_boss_sparks(pos_x: float) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = GraphicsQuality.particle_amount(60, GameManager.graphics_quality)
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

func is_solid_frame_occluding_segment(segment_start: Vector3, segment_end: Vector3) -> bool:
	# Answer doors are intentionally excluded so the x-ray silhouette cannot cover choices.
	for part: MeshInstance3D in wall_parts:
		if (
			not is_instance_valid(part)
			or part.mesh == null
			or not part.is_visible_in_tree()
		):
			continue
		var inverse_transform := part.global_transform.affine_inverse()
		var local_start := inverse_transform * segment_start
		var local_end := inverse_transform * segment_end
		if part.get_aabb().intersects_segment(local_start, local_end) != null:
			return true
	return false


func _create_box(half_extents: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _shared_box_mesh(half_extents * 2.0)
	mesh_inst.material_override = _shared_opaque_material(color)
	return mesh_inst


static func _shared_box_mesh(size: Vector3) -> BoxMesh:
	var key := "%0.4f_%0.4f_%0.4f" % [size.x, size.y, size.z]
	var cached: BoxMesh = _box_mesh_cache.get(key) as BoxMesh
	if cached != null:
		return cached
	var box := BoxMesh.new()
	box.size = size
	_box_mesh_cache[key] = box
	return box


static func _shared_opaque_material(color: Color) -> StandardMaterial3D:
	var key := "%0.4f_%0.4f_%0.4f_%0.4f" % [color.r, color.g, color.b, color.a]
	var cached: StandardMaterial3D = _opaque_material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.05
	_opaque_material_cache[key] = mat
	return mat

func _create_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Keep the nearby answer text above the transparent shark pass while preserving depth
	# testing, so choices on farther walls do not show through nearer walls.
	label.render_priority = 20
	label.outline_render_priority = 19
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

	label.font = JAPANESE_FONT

	return label

func shatter_wall(direction_z: float = -1.0) -> void:
	_shattered = true
	set_gameplay_question_visible(false)
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
