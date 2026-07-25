extends Control
class_name BikeCourseLayoutEditor

const LAYOUT_SCRIPT = preload("res://scripts/core/bike_course_layout.gd")
const CANVAS_SCRIPT = preload("res://scripts/tools/bike_course_editor_canvas.gd")

var _canvas: BikeCourseEditorCanvas
var _type_option: OptionButton
var _selected_label: Label
var _x_spin: SpinBox
var _z_spin: SpinBox
var _count_label: Label
var _status_label: Label
var _updating_inspector: bool = false
var _dirty: bool = false


func _ready() -> void:
	name = "BikeCourseLayoutEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_saved_layout()


func get_gimmick_count() -> int:
	return _canvas.gimmicks.size() if _canvas != null else 0


func get_selected_item() -> Dictionary:
	return _canvas.get_selected_item() if _canvas != null else {}


func get_course_canvas() -> BikeCourseEditorCanvas:
	return _canvas


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.color = Color(0.035, 0.05, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.name = "RootMargin"
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 18)
	root_margin.add_theme_constant_override("margin_right", 18)
	root_margin.add_theme_constant_override("margin_top", 14)
	root_margin.add_theme_constant_override("margin_bottom", 14)
	add_child(root_margin)

	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 12)
	root_margin.add_child(page)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "ママチャリ・ギミック配置ツール"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.30))
	header.add_child(title)

	var header_spacer: Control = Control.new()
	header_spacer.name = "HeaderSpacer"
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var open_3d_button: Button = _button("3D編集", Color(0.95, 0.52, 0.18))
	open_3d_button.name = "Open3DEditor"
	open_3d_button.pressed.connect(_open_3d_editor)
	header.add_child(open_3d_button)

	var load_button: Button = _button("読込", Color(0.25, 0.58, 0.92))
	load_button.name = "LoadButton"
	load_button.pressed.connect(_load_saved_layout)
	header.add_child(load_button)

	var reset_button: Button = _button("標準配置", Color(0.52, 0.48, 0.72))
	reset_button.name = "ResetButton"
	reset_button.pressed.connect(_reset_default)
	header.add_child(reset_button)

	var save_button: Button = _button("保存  Ctrl+S", Color(0.18, 0.78, 0.48))
	save_button.name = "SaveButton"
	save_button.pressed.connect(_save_layout)
	header.add_child(save_button)

	var body: HSplitContainer = HSplitContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 315
	page.add_child(body)

	var side_panel: PanelContainer = PanelContainer.new()
	side_panel.name = "ToolPanel"
	side_panel.custom_minimum_size = Vector2(300.0, 0.0)
	side_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.10, 0.16), Color(0.16, 0.24, 0.34)))
	body.add_child(side_panel)

	var side_margin: MarginContainer = MarginContainer.new()
	side_margin.name = "ToolMargin"
	side_margin.add_theme_constant_override("margin_left", 16)
	side_margin.add_theme_constant_override("margin_right", 16)
	side_margin.add_theme_constant_override("margin_top", 16)
	side_margin.add_theme_constant_override("margin_bottom", 16)
	side_panel.add_child(side_margin)

	var tools: VBoxContainer = VBoxContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("separation", 10)
	side_margin.add_child(tools)

	var help: Label = Label.new()
	help.name = "Help"
	help.text = "1. 種類を選ぶ\n2. 道路を左クリックして配置\n3. ドラッグで移動\n4. 右クリックで選択\n5. 保存でゲームへ反映"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	tools.add_child(help)

	tools.add_child(_section_label("配置するギミック"))

	_type_option = OptionButton.new()
	_type_option.name = "GimmickType"
	_type_option.custom_minimum_size = Vector2(0.0, 44.0)
	for type_id: String in LAYOUT_SCRIPT.SUPPORTED_TYPES:
		var option_index: int = _type_option.item_count
		_type_option.add_item(LAYOUT_SCRIPT.type_label(type_id))
		_type_option.set_item_metadata(option_index, type_id)
	_type_option.item_selected.connect(_on_type_selected)
	tools.add_child(_type_option)

	var palette_hint: Label = Label.new()
	palette_hint.name = "PaletteHint"
	palette_hint.text = "コーン・段差・バリケードは転倒\n水たまりはスリップを発生させます"
	palette_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	palette_hint.add_theme_color_override("font_color", Color(0.62, 0.70, 0.82))
	tools.add_child(palette_hint)

	tools.add_child(_section_label("選択中"))

	_selected_label = Label.new()
	_selected_label.name = "SelectedLabel"
	_selected_label.text = "未選択"
	_selected_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.70))
	tools.add_child(_selected_label)

	var x_row: HBoxContainer = HBoxContainer.new()
	x_row.name = "XRow"
	var x_label: Label = Label.new()
	x_label.name = "XLabel"
	x_label.text = "左右 X"
	x_label.custom_minimum_size.x = 80.0
	x_row.add_child(x_label)
	_x_spin = _spin_box(-7.5, 7.5, 0.5, " m")
	_x_spin.name = "XSpin"
	_x_spin.value_changed.connect(_on_position_value_changed)
	x_row.add_child(_x_spin)
	tools.add_child(x_row)

	var z_row: HBoxContainer = HBoxContainer.new()
	z_row.name = "ZRow"
	var z_label: Label = Label.new()
	z_label.name = "ZLabel"
	z_label.text = "距離 Z"
	z_label.custom_minimum_size.x = 80.0
	z_row.add_child(z_label)
	_z_spin = _spin_box(LAYOUT_SCRIPT.MIN_Z, LAYOUT_SCRIPT.MAX_Z, 1.0, " m")
	_z_spin.name = "ZSpin"
	_z_spin.value_changed.connect(_on_position_value_changed)
	z_row.add_child(_z_spin)
	tools.add_child(z_row)

	var selection_actions: HBoxContainer = HBoxContainer.new()
	selection_actions.name = "SelectionActions"
	selection_actions.add_theme_constant_override("separation", 8)
	var duplicate_button: Button = _button("複製", Color(0.25, 0.58, 0.92))
	duplicate_button.name = "DuplicateButton"
	duplicate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate_button.pressed.connect(_on_duplicate)
	selection_actions.add_child(duplicate_button)
	var delete_button: Button = _button("削除  Del", Color(0.90, 0.28, 0.24))
	delete_button.name = "DeleteButton"
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(_on_delete)
	selection_actions.add_child(delete_button)
	tools.add_child(selection_actions)

	var clear_button: Button = _button("全ギミックをクリア", Color(0.66, 0.28, 0.30))
	clear_button.name = "ClearButton"
	clear_button.pressed.connect(_on_clear)
	tools.add_child(clear_button)

	var tool_spacer: Control = Control.new()
	tool_spacer.name = "ToolSpacer"
	tool_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools.add_child(tool_spacer)

	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_font_size_override("font_size", 18)
	tools.add_child(_count_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 54.0
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.34))
	tools.add_child(_status_label)

	var map_panel: PanelContainer = PanelContainer.new()
	map_panel.name = "MapPanel"
	map_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.065, 0.095), Color(0.16, 0.24, 0.34)))
	body.add_child(map_panel)

	var course_scroll: ScrollContainer = ScrollContainer.new()
	course_scroll.name = "CourseScroll"
	course_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	course_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	course_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(course_scroll)

	_canvas = CANVAS_SCRIPT.new() as BikeCourseEditorCanvas
	_canvas.name = "CourseCanvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.layout_changed.connect(_on_layout_changed)
	_canvas.selection_changed.connect(_on_selection_changed)
	_canvas.status_message.connect(_set_status)
	course_scroll.add_child(_canvas)
	course_scroll.set_deferred("scroll_vertical", 270)


func _load_saved_layout() -> void:
	if _canvas == null:
		return
	_canvas.set_layout(LAYOUT_SCRIPT.load_layout())
	_dirty = false
	_update_count()
	_set_status("保存済み配置を読み込みました")


func _reset_default() -> void:
	_canvas.set_layout(LAYOUT_SCRIPT.default_layout())
	_dirty = true
	_update_count()
	_set_status("標準配置へ戻しました。保存するとゲームへ反映されます")


func _save_layout() -> void:
	var result: Dictionary = LAYOUT_SCRIPT.save_layout(_canvas.get_layout())
	if bool(result.get("success", false)):
		_dirty = false
		_update_count()
		var destination: String = "プロジェクト＋ユーザー"
		if not bool(result.get("project_saved", false)):
			destination = "ユーザーデータ"
		elif not bool(result.get("user_saved", false)):
			destination = "プロジェクト"
		_set_status("%d個のギミックを%sへ保存しました" % [
			int(result.get("count", 0)),
			destination,
		])
	else:
		_set_status("保存に失敗しました")


func _on_type_selected(index: int) -> void:
	var metadata: Variant = _type_option.get_item_metadata(index)
	_canvas.set_selected_type(str(metadata))


func _on_selection_changed(_index: int, item: Dictionary) -> void:
	_updating_inspector = true
	if item.is_empty():
		_selected_label.text = "未選択"
		_x_spin.editable = false
		_z_spin.editable = false
	else:
		var type_id: String = str(item.get("type", ""))
		_selected_label.text = "%s  [%s]" % [
			LAYOUT_SCRIPT.type_label(type_id),
			str(item.get("id", "")),
		]
		_x_spin.editable = type_id != "bump"
		_z_spin.editable = true
		_x_spin.value = float(item.get("x", 0.0))
		_z_spin.value = float(item.get("z", 0.0))
	_updating_inspector = false


func _on_position_value_changed(_value: float) -> void:
	if _updating_inspector:
		return
	_canvas.update_selected_position(float(_x_spin.value), float(_z_spin.value))


func _on_duplicate() -> void:
	_canvas.duplicate_selected()


func _on_delete() -> void:
	_canvas.delete_selected()


func _on_clear() -> void:
	_canvas.clear_all()


func _on_layout_changed() -> void:
	_dirty = true
	_update_count()


func _update_count() -> void:
	if _count_label == null or _canvas == null:
		return
	_count_label.text = "配置数: %d%s" % [
		_canvas.gimmicks.size(),
		"  ● 未保存" if _dirty else "",
	]


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _open_3d_editor() -> void:
	get_tree().change_scene_to_file("res://tools/bike_course_3d_editor.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_S and key_event.ctrl_pressed:
			_save_layout()
			get_viewport().set_input_as_handled()


func _button(text: String, color: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110.0, 42.0)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.35)
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.darkened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.50)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style


func _section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.96))
	return label


func _spin_box(minimum: float, maximum: float, step: float, suffix: String) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(150.0, 40.0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.editable = false
	return spin
