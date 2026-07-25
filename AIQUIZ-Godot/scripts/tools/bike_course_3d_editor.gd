extends Node3D
class_name BikeCourse3DEditor

const LAYOUT_SCRIPT = preload("res://scripts/core/bike_course_layout.gd")
const BIKE_COURSE_SCENE: PackedScene = preload("res://scenes/bike_course.tscn")

const ROAD_WIDTH: float = 16.0
const STAGE_WIDTH: float = 24.0
const ROAD_SEGMENT_LENGTH: float = 2.5
const SURFACE_Y: float = 0.0
const GIZMO_AXIS_LENGTH: float = 3.4
const GIZMO_RING_RADIUS: float = 2.15
const GIZMO_PICK_PIXELS: float = 13.0
const GIZMO_CENTER_PICK_PIXELS: float = 18.0

enum EditMode {
	GIMMICK,
	HEIGHT,
}

var _layout: Dictionary = {}
var _edit_mode: EditMode = EditMode.GIMMICK
var _selected_kind: String = ""
var _selected_index: int = -1
var _dirty: bool = false
var _updating_inspector: bool = false
var _dragging_view: bool = false
var _gizmo_drag_mode: String = ""
var _gizmo_drag_start_item: Dictionary = {}
var _gizmo_rotation_offset: float = 0.0

var _game_stage: BikeCourse
var _gimmick_root: Node3D
var _height_root: Node3D
var _probe_root: Node3D
var _camera: Camera3D

var _orbit_target := Vector3(0.0, 1.0, 115.0)
var _orbit_yaw: float = -2.62
var _orbit_pitch: float = 0.45
var _orbit_distance: float = 125.0
var _camera_move_speed: float = 32.0
var _probe_z: float = 205.0

var _mode_option: OptionButton
var _type_option: OptionButton
var _selection_label: Label
var _x_spin: SpinBox
var _z_spin: SpinBox
var _height_spin: SpinBox
var _rotation_spin: SpinBox
var _probe_spin: SpinBox
var _count_label: Label
var _status_label: Label
var _duplicate_button: Button
var _delete_button: Button


func _ready() -> void:
	name = "BikeCourse3DEditor"
	_build_environment()
	_build_ui()
	_load_saved_layout()
	_update_camera()


func _process(delta: float) -> void:
	if _camera == null:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return

	var move_input := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move_input.z += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move_input.z -= 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move_input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move_input.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		move_input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		move_input.y += 1.0
	if move_input.is_zero_approx():
		return

	var forward: Vector3 = -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var movement: Vector3 = right * move_input.x + forward * move_input.z + Vector3.UP * move_input.y
	var speed: float = _camera_move_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 2.4
	_orbit_target += movement.normalized() * speed * delta
	_orbit_target.x = clampf(_orbit_target.x, -80.0, 80.0)
	_orbit_target.y = clampf(_orbit_target.y, -8.0, 40.0)
	_orbit_target.z = clampf(_orbit_target.z, -25.0, LAYOUT_SCRIPT.COURSE_LENGTH + 25.0)
	_update_camera()


func get_gimmick_count() -> int:
	return (_layout.get("gimmicks", []) as Array).size()


func get_height_point_count() -> int:
	return (_layout.get("height_points", []) as Array).size()


func get_layout() -> Dictionary:
	return _layout.duplicate(true)


func get_selected_kind() -> String:
	return _selected_kind


func get_selected_data() -> Dictionary:
	var source: Array = _selected_array()
	if _selected_index < 0 or _selected_index >= source.size():
		return {}
	return (source[_selected_index] as Dictionary).duplicate(true)


func get_probe_state() -> Dictionary:
	return {
		"z": _probe_z,
		"height": LAYOUT_SCRIPT.get_height(_layout, _probe_z),
		"pitch": LAYOUT_SCRIPT.get_pitch(_layout, _probe_z),
		"position": _probe_root.position if _probe_root != null else Vector3.ZERO,
		"rotation_x": _probe_root.rotation.x if _probe_root != null else 0.0,
	}


func place_gimmick(type_id: String, x: float, z: float, rotation_y: float = 0.0) -> int:
	if not LAYOUT_SCRIPT.SUPPORTED_TYPES.has(type_id):
		return -1
	var gimmicks: Array = _layout.get("gimmicks", [])
	var snapped_x: float = snappedf(
		clampf(x, -LAYOUT_SCRIPT.ROAD_HALF_WIDTH + 0.5, LAYOUT_SCRIPT.ROAD_HALF_WIDTH - 0.5),
		LAYOUT_SCRIPT.GRID_X
	)
	if type_id == "bump":
		snapped_x = 0.0
	var snapped_z: float = snappedf(clampf(z, LAYOUT_SCRIPT.MIN_Z, LAYOUT_SCRIPT.MAX_Z), LAYOUT_SCRIPT.GRID_Z)
	gimmicks.append({
		"id": _next_item_id(type_id),
		"type": type_id,
		"x": snapped_x,
		"z": snapped_z,
		"rotation_y": snappedf(wrapf(rotation_y, -180.0, 180.0), 5.0),
	})
	_layout["gimmicks"] = gimmicks
	_selected_kind = "gimmick"
	_selected_index = gimmicks.size() - 1
	_mark_changed("ギミックを配置しました")
	return _selected_index


func add_height_point(z: float, height: float) -> int:
	var points: Array = _layout.get("height_points", [])
	if points.size() >= LAYOUT_SCRIPT.MAX_HEIGHT_POINTS:
		_set_status("高さ制御点は最大%d個です" % LAYOUT_SCRIPT.MAX_HEIGHT_POINTS)
		return -1
	var point: Dictionary = LAYOUT_SCRIPT.make_height_point(z, height)
	var target_z: float = float(point.get("z", 0.0))
	for index: int in range(points.size()):
		var existing: Dictionary = points[index] as Dictionary
		if is_equal_approx(float(existing.get("z", 0.0)), target_z):
			_selected_kind = "height"
			_selected_index = index
			_refresh_selection_ui()
			_set_status("同じZ位置の高さ制御点を選択しました")
			return index
	points.append(point)
	_layout["height_points"] = points
	_layout = LAYOUT_SCRIPT.normalize_layout(_layout)
	_selected_kind = "height"
	_selected_index = _find_height_index(target_z)
	_mark_changed("高さ制御点を追加しました")
	return _selected_index


func set_height_point_height(index: int, height: float) -> void:
	var points: Array = _layout.get("height_points", [])
	if index < 0 or index >= points.size():
		return
	var point: Dictionary = points[index] as Dictionary
	point["height"] = snappedf(
		clampf(height, LAYOUT_SCRIPT.MIN_HEIGHT, LAYOUT_SCRIPT.MAX_HEIGHT),
		LAYOUT_SCRIPT.HEIGHT_GRID
	)
	points[index] = point
	_layout["height_points"] = points
	_selected_kind = "height"
	_selected_index = index
	_mark_changed("地面の高さを変更しました")


func set_probe_z(z: float) -> void:
	_probe_z = snappedf(clampf(z, 0.0, LAYOUT_SCRIPT.COURSE_LENGTH), 0.5)
	if _probe_spin != null and not is_equal_approx(float(_probe_spin.value), _probe_z):
		_updating_inspector = true
		_probe_spin.value = _probe_z
		_updating_inspector = false
	_update_probe()


func save_layout() -> Dictionary:
	var result: Dictionary = LAYOUT_SCRIPT.save_layout(_layout)
	if bool(result.get("success", false)):
		_layout = LAYOUT_SCRIPT.normalize_layout(_layout)
		_dirty = false
		_update_count()
		_set_status("3Dコースを保存しました（ギミック%d個 / 高さ点%d個）" % [
			int(result.get("count", 0)),
			int(result.get("height_point_count", 0)),
		])
	else:
		_set_status("保存に失敗しました")
	return result


func _build_environment() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = "EditorEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.09, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.68, 0.82)
	environment.ambient_light_energy = 0.82
	world.environment = environment
	add_child(world)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "EditorSun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.current = true
	_camera.fov = 54.0
	_camera.near = 0.1
	_camera.far = 500.0
	add_child(_camera)

	_game_stage = BIKE_COURSE_SCENE.instantiate() as BikeCourse
	_game_stage.name = "GameStagePreview"
	add_child(_game_stage)
	_game_stage.visible = true

	_gimmick_root = Node3D.new()
	_gimmick_root.name = "SelectionOverlay"
	add_child(_gimmick_root)
	_height_root = Node3D.new()
	_height_root.name = "HeightHandles"
	add_child(_height_root)
	_probe_root = Node3D.new()
	_probe_root.name = "ContactProbe"
	add_child(_probe_root)


func _build_ui() -> void:
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	canvas_layer.name = "EditorUI"
	add_child(canvas_layer)

	var title_bar: PanelContainer = PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_bar.offset_left = 366.0
	title_bar.offset_right = -16.0
	title_bar.offset_top = 16.0
	title_bar.offset_bottom = 72.0
	title_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.07, 0.11, 0.94), Color(0.22, 0.42, 0.62)))
	canvas_layer.add_child(title_bar)
	var header_margin: MarginContainer = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 10)
	header_margin.add_theme_constant_override("margin_top", 7)
	header_margin.add_theme_constant_override("margin_bottom", 7)
	title_bar.add_child(header_margin)
	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	header_margin.add_child(header_row)
	var title: Label = Label.new()
	title.name = "Title"
	title.text = "ママチャリコース｜ゲーム本番ステージを直接編集"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34))
	header_row.add_child(title)
	var quick_save: Button = _button("保存  Ctrl+S", Color(0.16, 0.76, 0.45))
	quick_save.custom_minimum_size = Vector2(132.0, 38.0)
	quick_save.tooltip_text = "この配置をゲーム用コースとして保存します"
	quick_save.pressed.connect(save_layout)
	header_row.add_child(quick_save)

	var help_bar: Label = Label.new()
	help_bar.name = "ViewportHelp"
	help_bar.text = "WASD: 視点移動　Shift: 高速　Q/E: 上下　右ドラッグ: 回転　ホイール: ズーム　F: 選択へ"
	help_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_bar.offset_left = 366.0
	help_bar.offset_right = -16.0
	help_bar.offset_top = -54.0
	help_bar.offset_bottom = -16.0
	help_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_bar.add_theme_font_size_override("font_size", 16)
	help_bar.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	help_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(help_bar)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ToolPanel"
	panel.position = Vector2(14.0, 14.0)
	panel.custom_minimum_size = Vector2(338.0, 0.0)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_bottom = -14.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.065, 0.105, 0.97), Color(0.18, 0.34, 0.50)))
	canvas_layer.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "PanelMargin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ToolScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	margin.add_child(scroll)

	var tools: VBoxContainer = VBoxContainer.new()
	tools.name = "Tools"
	tools.custom_minimum_size.x = 286.0
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_theme_constant_override("separation", 9)
	scroll.add_child(tools)

	var app_title: Label = Label.new()
	app_title.text = "COURSE BUILDER"
	app_title.add_theme_font_size_override("font_size", 22)
	app_title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	tools.add_child(app_title)
	var sync_badge: Label = Label.new()
	sync_badge.text = "● GAME STAGE SYNCED"
	sync_badge.add_theme_font_size_override("font_size", 13)
	sync_badge.add_theme_color_override("font_color", Color(0.30, 1.0, 0.67))
	tools.add_child(sync_badge)
	var intro: Label = Label.new()
	intro.text = "ここで見える道路・装飾・障害物が、そのままゲームに使われます。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.64, 0.75, 0.88))
	tools.add_child(intro)
	tools.add_child(HSeparator.new())

	var view_row: HBoxContainer = HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 7)
	var whole_button: Button = _button("全体表示  Home", Color(0.24, 0.55, 0.86))
	whole_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	whole_button.pressed.connect(_focus_whole_course)
	view_row.add_child(whole_button)
	var focus_button: Button = _button("選択へ  F", Color(0.26, 0.68, 0.58))
	focus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_button.pressed.connect(_focus_selected)
	view_row.add_child(focus_button)
	tools.add_child(view_row)

	var mode_title: Label = _section_label("1  編集モード")
	tools.add_child(mode_title)
	_mode_option = OptionButton.new()
	_mode_option.name = "EditMode"
	_mode_option.add_item("障害物・ギミックを配置")
	_mode_option.set_item_metadata(0, EditMode.GIMMICK)
	_mode_option.add_item("坂・地面の高さを編集")
	_mode_option.set_item_metadata(1, EditMode.HEIGHT)
	_mode_option.custom_minimum_size.y = 40.0
	_mode_option.item_selected.connect(_on_mode_selected)
	tools.add_child(_mode_option)

	_type_option = OptionButton.new()
	_type_option.name = "GimmickType"
	for type_id: String in LAYOUT_SCRIPT.SUPPORTED_TYPES:
		var option_index: int = _type_option.item_count
		_type_option.add_item(LAYOUT_SCRIPT.type_label(type_id))
		_type_option.set_item_metadata(option_index, type_id)
	_type_option.custom_minimum_size.y = 40.0
	tools.add_child(_type_option)

	var mode_help: Label = Label.new()
	mode_help.name = "ModeHelp"
	mode_help.text = "道路をクリックして追加。障害物を選択すると3Dギズモが表示され、軸移動・平面移動・回転ができます。"
	mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_help.add_theme_color_override("font_color", Color(0.66, 0.76, 0.88))
	tools.add_child(mode_help)

	tools.add_child(HSeparator.new())
	tools.add_child(_section_label("2  選択・数値調整"))
	_selection_label = Label.new()
	_selection_label.name = "SelectionLabel"
	_selection_label.text = "未選択"
	_selection_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.70))
	tools.add_child(_selection_label)

	_x_spin = _add_spin_row(tools, "左右 X", -7.5, 7.5, 0.5, " m", _on_inspector_changed)
	_x_spin.name = "XSpin"
	_z_spin = _add_spin_row(tools, "距離 Z", 0.0, LAYOUT_SCRIPT.COURSE_LENGTH, 1.0, " m", _on_inspector_changed)
	_z_spin.name = "ZSpin"
	_height_spin = _add_spin_row(tools, "高さ Y", LAYOUT_SCRIPT.MIN_HEIGHT, LAYOUT_SCRIPT.MAX_HEIGHT, 0.1, " m", _on_inspector_changed)
	_height_spin.name = "HeightSpin"
	_rotation_spin = _add_spin_row(tools, "Y回転", -180.0, 180.0, 5.0, " °", _on_inspector_changed)
	_rotation_spin.name = "RotationYSpin"

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.name = "SelectionActions"
	action_row.add_theme_constant_override("separation", 7)
	_duplicate_button = _button("複製", Color(0.20, 0.55, 0.90))
	_duplicate_button.name = "DuplicateButton"
	_duplicate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duplicate_button.pressed.connect(_duplicate_selected)
	action_row.add_child(_duplicate_button)
	_delete_button = _button("削除 Del", Color(0.90, 0.28, 0.24))
	_delete_button.name = "DeleteButton"
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(_delete_selected)
	action_row.add_child(_delete_button)
	tools.add_child(action_row)

	tools.add_child(HSeparator.new())
	tools.add_child(_section_label("3  走行位置プレビュー"))
	_probe_spin = _add_spin_row(tools, "走者 Z", 0.0, LAYOUT_SCRIPT.COURSE_LENGTH, 0.5, " m", _on_probe_changed)
	_probe_spin.name = "ProbeZSpin"
	_probe_spin.value = _probe_z
	var probe_help: Label = Label.new()
	probe_help.name = "ProbeHelp"
	probe_help.text = "オレンジの走者が地面の高さと坂角度へ追従します"
	probe_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	probe_help.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	tools.add_child(probe_help)
	var probe_toggle: CheckButton = CheckButton.new()
	probe_toggle.text = "走者プレビューを表示"
	probe_toggle.button_pressed = true
	probe_toggle.toggled.connect(_on_probe_visibility_toggled)
	tools.add_child(probe_toggle)

	tools.add_child(HSeparator.new())
	var save_title: Label = _section_label("4  保存・切り替え")
	tools.add_child(save_title)

	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_font_size_override("font_size", 17)
	tools.add_child(_count_label)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.custom_minimum_size.y = 48.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.30))
	tools.add_child(_status_label)

	var file_row: HBoxContainer = HBoxContainer.new()
	file_row.name = "FileActions"
	file_row.add_theme_constant_override("separation", 6)
	var load_button: Button = _button("再読込", Color(0.22, 0.54, 0.88))
	load_button.tooltip_text = "保存済みの配置を読み込み直します"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_load_saved_layout)
	file_row.add_child(load_button)
	var reset_button: Button = _button("初期配置", Color(0.50, 0.46, 0.72))
	reset_button.tooltip_text = "標準コースへ戻します（保存まではゲームに反映されません）"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(_reset_default)
	file_row.add_child(reset_button)
	var save_button: Button = _button("保存", Color(0.16, 0.76, 0.45))
	save_button.tooltip_text = "ゲームで使用するコース配置を保存します（Ctrl+S）"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(save_layout)
	file_row.add_child(save_button)
	tools.add_child(file_row)

	var two_d_button: Button = _button("2D俯瞰エディターに切り替え", Color(0.30, 0.46, 0.66))
	two_d_button.name = "Open2DEditor"
	two_d_button.pressed.connect(_open_2d_editor)
	tools.add_child(two_d_button)


func _load_saved_layout() -> void:
	_layout = LAYOUT_SCRIPT.load_layout(true)
	_selected_kind = ""
	_selected_index = -1
	_dirty = false
	_rebuild_all()
	_set_status("保存済みコースを読み込みました")


func _reset_default() -> void:
	_layout = LAYOUT_SCRIPT.default_layout()
	_selected_kind = ""
	_selected_index = -1
	_dirty = true
	_rebuild_all()
	_set_status("初期配置へ戻しました。保存するまでゲームには反映されません")


func _rebuild_all() -> void:
	_rebuild_road()
	_rebuild_gimmicks()
	_rebuild_height_handles()
	_rebuild_probe()
	_refresh_selection_ui()
	_update_count()


func _rebuild_road() -> void:
	if _game_stage == null:
		return
	_game_stage.rebuild_course(_layout)


func _rebuild_gimmicks() -> void:
	_clear_children(_gimmick_root)
	if _selected_kind != "gimmick":
		return
	var gimmicks: Array = _layout.get("gimmicks", [])
	if _selected_index < 0 or _selected_index >= gimmicks.size():
		return
	var item: Dictionary = gimmicks[_selected_index] as Dictionary
	var z: float = float(item.get("z", 0.0))
	var root: Node3D = Node3D.new()
	root.name = "TransformGizmo_%s" % str(item.get("id", "Gimmick"))
	root.position = Vector3(
		float(item.get("x", 0.0)),
		SURFACE_Y + LAYOUT_SCRIPT.get_height(_layout, z) + 0.55,
		z
	)
	_gimmick_root.add_child(root)

	var type_id: String = str(item.get("type", ""))
	var x_locked: bool = type_id == "bump"
	var x_color := Color(0.48, 0.18, 0.22) if x_locked else Color(1.0, 0.16, 0.34)
	var y_color := Color(0.62, 0.98, 0.06)
	var z_color := Color(0.08, 0.56, 1.0)
	var rotate_color := Color(1.0, 0.66, 0.08)
	_add_gizmo_arrow(root, Vector3.RIGHT, x_color, "X", "X LOCK" if x_locked else "X")
	_add_gizmo_arrow(root, Vector3.UP, y_color, "Y", "Y AUTO")
	_add_gizmo_arrow(root, Vector3.FORWARD, z_color, "Z", "Z")
	_add_gizmo_rotation_ring(root, rotate_color)

	var center: MeshInstance3D = _box(
		Vector3(0.42, 0.055, 0.42),
		_material(Color(1.0, 0.90, 0.08), 0.28)
	)
	center.name = "MoveXZHandle"
	center.position.y = 0.045
	root.add_child(center)

	var label: Label3D = Label3D.new()
	label.name = "GizmoHelp"
	label.text = "%s  X %.1f / Z %.1f / R %.0f°\n矢印: 軸移動　中央: 自由移動　リング: 回転" % [
		LAYOUT_SCRIPT.type_label(type_id),
		float(item.get("x", 0.0)),
		z,
		float(item.get("rotation_y", 0.0)),
	]
	label.font_size = 28
	label.pixel_size = 0.0075
	label.modulate = Color(0.92, 0.97, 1.0)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, GIZMO_AXIS_LENGTH + 0.62, 0.0)
	root.add_child(label)


func _add_gizmo_arrow(
	parent: Node3D,
	direction: Vector3,
	color: Color,
	axis_name: String,
	label_text: String
) -> void:
	var material: StandardMaterial3D = _material(color, 0.28)
	_add_rod(
		parent,
		direction * 0.22,
		direction * (GIZMO_AXIS_LENGTH - 0.28),
		0.055,
		material
	)
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "%sArrow" % axis_name
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.18
	head_mesh.height = 0.48
	head_mesh.radial_segments = 18
	head.mesh = head_mesh
	head.material_override = material
	head.position = direction * (GIZMO_AXIS_LENGTH - 0.06)
	head.quaternion = Quaternion(Vector3.UP, direction)
	parent.add_child(head)

	var axis_label: Label3D = Label3D.new()
	axis_label.name = "%sLabel" % axis_name
	axis_label.text = label_text
	axis_label.font_size = 28
	axis_label.pixel_size = 0.007
	axis_label.modulate = color.lightened(0.18)
	axis_label.outline_size = 7
	axis_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	axis_label.position = direction * (GIZMO_AXIS_LENGTH + 0.28)
	parent.add_child(axis_label)


func _add_gizmo_rotation_ring(parent: Node3D, color: Color) -> void:
	var material: StandardMaterial3D = _material(color, 0.24)
	var segment_count: int = 40
	for index: int in range(segment_count):
		var angle_a: float = TAU * float(index) / float(segment_count)
		var angle_b: float = TAU * float(index + 1) / float(segment_count)
		var point_a := Vector3(
			sin(angle_a) * GIZMO_RING_RADIUS,
			0.10,
			cos(angle_a) * GIZMO_RING_RADIUS
		)
		var point_b := Vector3(
			sin(angle_b) * GIZMO_RING_RADIUS,
			0.10,
			cos(angle_b) * GIZMO_RING_RADIUS
		)
		_add_rod(parent, point_a, point_b, 0.035, material)
	var rotate_label: Label3D = Label3D.new()
	rotate_label.name = "RotateYLabel"
	rotate_label.text = "Y回転"
	rotate_label.font_size = 26
	rotate_label.pixel_size = 0.007
	rotate_label.modulate = color.lightened(0.16)
	rotate_label.outline_size = 7
	rotate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rotate_label.position = Vector3(GIZMO_RING_RADIUS + 0.28, 0.16, 0.0)
	parent.add_child(rotate_label)


func _rebuild_height_handles() -> void:
	_clear_children(_height_root)
	_height_root.visible = _edit_mode == EditMode.HEIGHT
	if not _height_root.visible:
		return
	var points: Array = _layout.get("height_points", [])
	for index: int in range(points.size()):
		var point: Dictionary = points[index] as Dictionary
		var z: float = float(point.get("z", 0.0))
		var height: float = float(point.get("height", 0.0))
		var selected: bool = _selected_kind == "height" and _selected_index == index
		var marker: Node3D = Node3D.new()
		marker.name = "HeightPoint_%02d" % index
		marker.position = Vector3(-6.7, SURFACE_Y + height, z)
		var pole_height: float = maxf(0.6, absf(height) + 0.6)
		var pole: MeshInstance3D = _box(
			Vector3(0.10, pole_height, 0.10),
			_material(Color(0.25, 1.0, 0.68) if selected else Color(0.30, 0.72, 1.0), 0.45)
		)
		pole.position.y = 0.3 if height >= 0.0 else -0.3
		marker.add_child(pole)
		var sphere: MeshInstance3D = MeshInstance3D.new()
		sphere.name = "Handle"
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = 0.30 if selected else 0.23
		sphere_mesh.height = sphere_mesh.radius * 2.0
		sphere.mesh = sphere_mesh
		sphere.material_override = _material(Color(0.25, 1.0, 0.68) if selected else Color(0.30, 0.72, 1.0), 0.35)
		sphere.position.y = 0.36
		marker.add_child(sphere)
		_height_root.add_child(marker)


func _rebuild_probe() -> void:
	_clear_children(_probe_root)
	_build_contact_probe()
	_update_probe()


func _build_contact_probe() -> void:
	var orange: StandardMaterial3D = _material(Color(1.0, 0.48, 0.10), 0.48)
	var dark: StandardMaterial3D = _material(Color(0.055, 0.07, 0.09), 0.72)
	var skin: StandardMaterial3D = _material(Color(0.95, 0.72, 0.52), 0.62)
	for z_offset: float in [-0.9, 0.9]:
		var wheel: MeshInstance3D = MeshInstance3D.new()
		wheel.name = "Wheel"
		var wheel_mesh: CylinderMesh = CylinderMesh.new()
		wheel_mesh.top_radius = 0.46
		wheel_mesh.bottom_radius = 0.46
		wheel_mesh.height = 0.08
		wheel_mesh.radial_segments = 24
		wheel.mesh = wheel_mesh
		wheel.material_override = dark
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(0.0, 0.46, z_offset)
		_probe_root.add_child(wheel)
	_add_rod(_probe_root, Vector3(0.0, 0.48, -0.9), Vector3(0.0, 1.15, -0.10), 0.055, orange)
	_add_rod(_probe_root, Vector3(0.0, 0.48, 0.9), Vector3(0.0, 1.15, -0.10), 0.055, orange)
	_add_rod(_probe_root, Vector3(0.0, 0.48, -0.9), Vector3(0.0, 0.76, 0.35), 0.055, orange)
	_add_rod(_probe_root, Vector3(0.0, 0.76, 0.35), Vector3(0.0, 1.15, -0.10), 0.055, orange)
	_add_rod(_probe_root, Vector3(-0.42, 1.45, 0.72), Vector3(0.42, 1.45, 0.72), 0.045, dark)
	var torso: MeshInstance3D = _box(Vector3(0.46, 0.68, 0.32), orange)
	torso.name = "RunnerTorso"
	torso.position = Vector3(0.0, 1.95, -0.05)
	torso.rotation.x = -0.25
	_probe_root.add_child(torso)
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "RunnerHead"
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.20
	head_mesh.height = 0.40
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0.0, 2.45, 0.12)
	_probe_root.add_child(head)
	_add_rod(_probe_root, Vector3(-0.19, 2.10, 0.02), Vector3(-0.36, 1.48, 0.68), 0.06, orange)
	_add_rod(_probe_root, Vector3(0.19, 2.10, 0.02), Vector3(0.36, 1.48, 0.68), 0.06, orange)
	_add_rod(_probe_root, Vector3(-0.14, 1.62, -0.04), Vector3(-0.18, 0.83, -0.42), 0.075, dark)
	_add_rod(_probe_root, Vector3(0.14, 1.62, -0.04), Vector3(0.18, 0.72, 0.34), 0.075, dark)
	var label: Label3D = Label3D.new()
	label.name = "ProbeLabel"
	label.text = "接地テスト"
	label.font_size = 34
	label.pixel_size = 0.009
	label.modulate = Color(1.0, 0.78, 0.25)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 2.95, 0.0)
	_probe_root.add_child(label)


func _update_probe() -> void:
	if _probe_root == null or _layout.is_empty():
		return
	var height: float = LAYOUT_SCRIPT.get_height(_layout, _probe_z)
	var pitch: float = LAYOUT_SCRIPT.get_pitch(_layout, _probe_z)
	_probe_root.position = Vector3(5.2, SURFACE_Y + height, _probe_z)
	_probe_root.rotation = Vector3(pitch, 0.0, 0.0)


func _add_gimmick_mesh(parent: Node3D, type_id: String, index: int) -> void:
	var selected: bool = _selected_kind == "gimmick" and _selected_index == index
	var color: Color = LAYOUT_SCRIPT.type_color(type_id)
	if selected:
		color = color.lightened(0.22)
	match type_id:
		"cone":
			var cone: MeshInstance3D = MeshInstance3D.new()
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = 0.08
			mesh.bottom_radius = 0.36
			mesh.height = 0.9
			mesh.radial_segments = 16
			cone.mesh = mesh
			cone.material_override = _material(color, 0.55)
			cone.position.y = 0.45
			parent.add_child(cone)
		"puddle":
			var puddle: MeshInstance3D = MeshInstance3D.new()
			var puddle_mesh: CylinderMesh = CylinderMesh.new()
			puddle_mesh.top_radius = 1.65
			puddle_mesh.bottom_radius = 1.8
			puddle_mesh.height = 0.045
			puddle_mesh.radial_segments = 28
			puddle.mesh = puddle_mesh
			puddle.material_override = _material(color, 0.22, true)
			puddle.scale.z = 0.58
			puddle.position.y = 0.03
			parent.add_child(puddle)
		"bump":
			var bump: MeshInstance3D = _box(Vector3(ROAD_WIDTH - 1.0, 0.18, 0.38), _material(color, 0.60))
			bump.position.y = 0.09
			parent.add_child(bump)
		"barrier":
			var barrier: MeshInstance3D = _box(Vector3(3.8, 0.34, 0.56), _material(color, 0.52))
			barrier.position.y = 0.17
			parent.add_child(barrier)
	if selected:
		var label: Label3D = Label3D.new()
		label.text = str((_layout.get("gimmicks", []) as Array)[index].get("id", ""))
		label.font_size = 30
		label.pixel_size = 0.008
		label.modulate = Color.WHITE
		label.outline_size = 6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 1.5
		parent.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_view = button_event.pressed
			get_viewport().set_input_as_handled()
			return
		if button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(28.0, _orbit_distance * 0.88)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
		if button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(240.0, _orbit_distance * 1.12)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				_handle_left_click(button_event.position)
			else:
				var finished_drag: bool = not _gizmo_drag_mode.is_empty()
				_gizmo_drag_mode = ""
				_gizmo_drag_start_item = {}
				if finished_drag:
					_rebuild_road()
					_rebuild_gimmicks()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _dragging_view:
			_orbit_yaw -= motion.relative.x * 0.008
			_orbit_pitch = clampf(_orbit_pitch - motion.relative.y * 0.008, 0.10, 1.28)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif not _gizmo_drag_mode.is_empty():
			var hit: Dictionary = _ray_to_course(motion.position)
			if not hit.is_empty():
				_update_gizmo_drag(hit.get("position", Vector3.ZERO) as Vector3)
			get_viewport().set_input_as_handled()
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_DELETE:
				_delete_selected()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_S and key_event.ctrl_pressed:
				save_layout()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_F:
				_focus_selected()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_HOME:
				_focus_whole_course()
				get_viewport().set_input_as_handled()


func _handle_left_click(screen_position: Vector2) -> void:
	var gizmo_hit: String = _pick_gizmo(screen_position)
	if not gizmo_hit.is_empty():
		_begin_gizmo_drag(gizmo_hit, screen_position)
		return
	if _pick_handle(screen_position):
		return
	var hit: Dictionary = _ray_to_course(screen_position)
	if hit.is_empty():
		_selected_kind = ""
		_selected_index = -1
		_rebuild_gimmicks()
		_rebuild_height_handles()
		_refresh_selection_ui()
		return
	var world_position: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	if _edit_mode == EditMode.GIMMICK:
		var type_id: String = str(_type_option.get_item_metadata(_type_option.selected))
		place_gimmick(type_id, world_position.x, world_position.z)
	else:
		add_height_point(world_position.z, LAYOUT_SCRIPT.get_height(_layout, world_position.z))


func _pick_gizmo(screen_position: Vector2) -> String:
	if _selected_kind != "gimmick" or _selected_index < 0:
		return ""
	var item: Dictionary = get_selected_data()
	if item.is_empty():
		return ""
	var origin: Vector3 = _selected_gizmo_origin()
	if _screen_distance(origin, screen_position) <= GIZMO_CENTER_PICK_PIXELS:
		return "free"

	var axis_start_offset: float = 0.34
	var axis_end_offset: float = GIZMO_AXIS_LENGTH + 0.16
	var x_distance: float = _screen_segment_distance(
		origin + Vector3.RIGHT * axis_start_offset,
		origin + Vector3.RIGHT * axis_end_offset,
		screen_position
	)
	var z_distance: float = _screen_segment_distance(
		origin + Vector3.FORWARD * axis_start_offset,
		origin + Vector3.FORWARD * axis_end_offset,
		screen_position
	)
	var y_distance: float = _screen_segment_distance(
		origin + Vector3.UP * axis_start_offset,
		origin + Vector3.UP * axis_end_offset,
		screen_position
	)
	var best_axis_distance: float = minf(x_distance, minf(z_distance, y_distance))
	if best_axis_distance <= GIZMO_PICK_PIXELS:
		if is_equal_approx(best_axis_distance, y_distance):
			return "locked_y"
		if is_equal_approx(best_axis_distance, x_distance):
			return "locked_x" if str(item.get("type", "")) == "bump" else "x"
		return "z"

	var ring_distance: float = INF
	var ring_segments: int = 40
	for index: int in range(ring_segments):
		var angle_a: float = TAU * float(index) / float(ring_segments)
		var angle_b: float = TAU * float(index + 1) / float(ring_segments)
		var point_a: Vector3 = origin + Vector3(
			sin(angle_a) * GIZMO_RING_RADIUS,
			0.10,
			cos(angle_a) * GIZMO_RING_RADIUS
		)
		var point_b: Vector3 = origin + Vector3(
			sin(angle_b) * GIZMO_RING_RADIUS,
			0.10,
			cos(angle_b) * GIZMO_RING_RADIUS
		)
		ring_distance = minf(
			ring_distance,
			_screen_segment_distance(point_a, point_b, screen_position)
		)
	if ring_distance <= GIZMO_PICK_PIXELS:
		return "rotate"
	return ""


func _begin_gizmo_drag(mode: String, screen_position: Vector2) -> void:
	if mode == "locked_y":
		_set_status("Y位置は道路の高さへ自動追従します")
		return
	if mode == "locked_x":
		_set_status("段差は道路全幅を使うためX位置が固定されています")
		return
	_gizmo_drag_mode = mode
	_gizmo_drag_start_item = get_selected_data()
	if mode == "rotate":
		var hit: Dictionary = _ray_to_course(screen_position)
		if not hit.is_empty():
			var world_position: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
			var origin: Vector3 = _selected_gizmo_origin()
			var pointer_angle: float = rad_to_deg(atan2(
				world_position.x - origin.x,
				world_position.z - origin.z
			))
			_gizmo_rotation_offset = float(_gizmo_drag_start_item.get("rotation_y", 0.0)) - pointer_angle
	_set_status("ギズモ操作中: %s" % {
		"free": "XZ平面移動",
		"x": "X軸移動",
		"z": "Z軸移動",
		"rotate": "Y回転（5°刻み）",
	}.get(mode, mode))


func _update_gizmo_drag(world_position: Vector3) -> void:
	if _gizmo_drag_mode.is_empty() or _selected_kind != "gimmick":
		return
	var gimmicks: Array = _layout.get("gimmicks", [])
	if _selected_index < 0 or _selected_index >= gimmicks.size():
		return
	var item: Dictionary = gimmicks[_selected_index] as Dictionary
	var type_id: String = str(item.get("type", ""))
	if _gizmo_drag_mode == "rotate":
		var origin: Vector3 = _selected_gizmo_origin()
		var pointer_delta := Vector2(
			world_position.x - origin.x,
			world_position.z - origin.z
		)
		if pointer_delta.length_squared() > 0.001:
			var pointer_angle: float = rad_to_deg(atan2(pointer_delta.x, pointer_delta.y))
			item["rotation_y"] = snappedf(
				wrapf(pointer_angle + _gizmo_rotation_offset, -180.0, 180.0),
				5.0
			)
	else:
		if _gizmo_drag_mode == "free" or _gizmo_drag_mode == "x":
			item["x"] = 0.0 if type_id == "bump" else snappedf(
				clampf(world_position.x, -7.5, 7.5),
				LAYOUT_SCRIPT.GRID_X
			)
		else:
			item["x"] = float(_gizmo_drag_start_item.get("x", item.get("x", 0.0)))
		if _gizmo_drag_mode == "free" or _gizmo_drag_mode == "z":
			item["z"] = snappedf(
				clampf(world_position.z, LAYOUT_SCRIPT.MIN_Z, LAYOUT_SCRIPT.MAX_Z),
				LAYOUT_SCRIPT.GRID_Z
			)
		else:
			item["z"] = float(_gizmo_drag_start_item.get("z", item.get("z", 0.0)))
	gimmicks[_selected_index] = item
	_layout["gimmicks"] = gimmicks
	_dirty = true
	_update_live_gimmick_preview(item)
	_rebuild_gimmicks()
	_refresh_selection_ui()
	_update_count()


func _update_live_gimmick_preview(item: Dictionary) -> void:
	if _game_stage == null:
		return
	var item_id: String = str(item.get("id", ""))
	var preview: Node3D = _game_stage.get_node_or_null(item_id) as Node3D
	if preview == null:
		return
	var z: float = float(item.get("z", 0.0))
	preview.position = Vector3(
		float(item.get("x", 0.0)),
		SURFACE_Y + LAYOUT_SCRIPT.get_height(_layout, z),
		z
	)
	preview.rotation = Vector3(
		LAYOUT_SCRIPT.get_pitch(_layout, z),
		deg_to_rad(float(item.get("rotation_y", 0.0))),
		0.0
	)


func _selected_gizmo_origin() -> Vector3:
	var item: Dictionary = get_selected_data()
	if item.is_empty():
		return Vector3.ZERO
	var z: float = float(item.get("z", 0.0))
	return Vector3(
		float(item.get("x", 0.0)),
		SURFACE_Y + LAYOUT_SCRIPT.get_height(_layout, z) + 0.55,
		z
	)


func _screen_segment_distance(
	world_a: Vector3,
	world_b: Vector3,
	screen_position: Vector2
) -> float:
	if _camera == null or _camera.is_position_behind(world_a) or _camera.is_position_behind(world_b):
		return INF
	var screen_a: Vector2 = _camera.unproject_position(world_a)
	var screen_b: Vector2 = _camera.unproject_position(world_b)
	var segment: Vector2 = screen_b - screen_a
	if segment.length_squared() <= 0.001:
		return screen_a.distance_to(screen_position)
	var t: float = clampf(
		(screen_position - screen_a).dot(segment) / segment.length_squared(),
		0.0,
		1.0
	)
	return (screen_a + segment * t).distance_to(screen_position)


func _pick_handle(screen_position: Vector2) -> bool:
	var best_distance: float = 24.0
	var best_kind: String = ""
	var best_index: int = -1
	var gimmicks: Array = _layout.get("gimmicks", [])
	for index: int in range(gimmicks.size()):
		var item: Dictionary = gimmicks[index] as Dictionary
		var z: float = float(item.get("z", 0.0))
		var world := Vector3(
			float(item.get("x", 0.0)),
			SURFACE_Y + LAYOUT_SCRIPT.get_height(_layout, z) + 0.55,
			z
		)
		var distance: float = _screen_distance(world, screen_position)
		if distance < best_distance:
			best_distance = distance
			best_kind = "gimmick"
			best_index = index
	var points: Array = _layout.get("height_points", [])
	for index: int in range(points.size()):
		var point: Dictionary = points[index] as Dictionary
		var world := Vector3(
			-6.7,
			SURFACE_Y + float(point.get("height", 0.0)) + 0.36,
			float(point.get("z", 0.0))
		)
		var distance: float = _screen_distance(world, screen_position)
		if distance < best_distance:
			best_distance = distance
			best_kind = "height"
			best_index = index
	if best_index < 0:
		return false
	_selected_kind = best_kind
	_selected_index = best_index
	_rebuild_gimmicks()
	_rebuild_height_handles()
	_refresh_selection_ui()
	_set_status("ギズモを表示しました。矢印・中央ハンドル・回転リングをドラッグできます")
	return true


func _screen_distance(world_position: Vector3, screen_position: Vector2) -> float:
	if _camera == null or _camera.is_position_behind(world_position):
		return INF
	return _camera.unproject_position(world_position).distance_to(screen_position)


func _ray_to_course(screen_position: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var closest_t: float = INF
	var closest_position := Vector3.ZERO
	var segment_count: int = int(LAYOUT_SCRIPT.COURSE_LENGTH / ROAD_SEGMENT_LENGTH)
	for index: int in range(segment_count):
		var z0: float = float(index) * ROAD_SEGMENT_LENGTH
		var z1: float = z0 + ROAD_SEGMENT_LENGTH
		var h0: float = LAYOUT_SCRIPT.get_height(_layout, z0)
		var h1: float = LAYOUT_SCRIPT.get_height(_layout, z1)
		var slope: float = (h1 - h0) / ROAD_SEGMENT_LENGTH
		var plane_constant: float = SURFACE_Y + h0 - slope * z0
		var denominator: float = direction.y - slope * direction.z
		if absf(denominator) < 0.00001:
			continue
		var t: float = (plane_constant + slope * origin.z - origin.y) / denominator
		if t <= 0.0 or t >= closest_t:
			continue
		var point: Vector3 = origin + direction * t
		if point.z < z0 - 0.01 or point.z > z1 + 0.01:
			continue
		if absf(point.x) > LAYOUT_SCRIPT.ROAD_HALF_WIDTH:
			continue
		closest_t = t
		closest_position = point
	if is_inf(closest_t):
		return {}
	return {"position": closest_position, "distance": closest_t}


func _on_mode_selected(index: int) -> void:
	_edit_mode = int(_mode_option.get_item_metadata(index)) as EditMode
	_type_option.disabled = _edit_mode == EditMode.HEIGHT
	_rebuild_height_handles()
	_set_status("道路をクリックして%s" % [
		"ギミックを配置します" if _edit_mode == EditMode.GIMMICK else "高さ制御点を追加します"
	])


func _on_inspector_changed(_value: float) -> void:
	if _updating_inspector or _selected_index < 0:
		return
	if _selected_kind == "gimmick":
		var gimmicks: Array = _layout.get("gimmicks", [])
		if _selected_index >= gimmicks.size():
			return
		var item: Dictionary = gimmicks[_selected_index] as Dictionary
		item["x"] = 0.0 if str(item.get("type", "")) == "bump" else snappedf(float(_x_spin.value), LAYOUT_SCRIPT.GRID_X)
		item["z"] = snappedf(float(_z_spin.value), LAYOUT_SCRIPT.GRID_Z)
		item["rotation_y"] = snappedf(
			wrapf(float(_rotation_spin.value), -180.0, 180.0),
			5.0
		)
		gimmicks[_selected_index] = item
		_layout["gimmicks"] = gimmicks
	elif _selected_kind == "height":
		var points: Array = _layout.get("height_points", [])
		if _selected_index >= points.size():
			return
		var point: Dictionary = points[_selected_index] as Dictionary
		var old_z: float = float(point.get("z", 0.0))
		var new_z: float = old_z
		if old_z > 0.0 and old_z < LAYOUT_SCRIPT.COURSE_LENGTH:
			new_z = snappedf(float(_z_spin.value), LAYOUT_SCRIPT.GRID_Z)
		point["z"] = new_z
		point["height"] = snappedf(float(_height_spin.value), LAYOUT_SCRIPT.HEIGHT_GRID)
		points[_selected_index] = point
		_layout["height_points"] = points
		_layout = LAYOUT_SCRIPT.normalize_layout(_layout)
		_selected_index = _find_height_index(new_z)
	_mark_changed("数値を変更しました")


func _on_probe_changed(value: float) -> void:
	if _updating_inspector:
		return
	set_probe_z(value)


func _on_probe_visibility_toggled(enabled: bool) -> void:
	if _probe_root != null:
		_probe_root.visible = enabled


func _duplicate_selected() -> void:
	if _selected_kind != "gimmick" or _selected_index < 0:
		_set_status("複製できるギミックを選択してください")
		return
	var gimmicks: Array = _layout.get("gimmicks", [])
	if _selected_index >= gimmicks.size():
		return
	var source: Dictionary = gimmicks[_selected_index] as Dictionary
	place_gimmick(
		str(source.get("type", "cone")),
		float(source.get("x", 0.0)) + LAYOUT_SCRIPT.GRID_X,
		float(source.get("z", 0.0)) + LAYOUT_SCRIPT.GRID_Z,
		float(source.get("rotation_y", 0.0))
	)


func _delete_selected() -> void:
	if _selected_index < 0:
		return
	if _selected_kind == "gimmick":
		var gimmicks: Array = _layout.get("gimmicks", [])
		if _selected_index < gimmicks.size():
			gimmicks.remove_at(_selected_index)
			_layout["gimmicks"] = gimmicks
	elif _selected_kind == "height":
		var points: Array = _layout.get("height_points", [])
		if _selected_index >= points.size():
			return
		var z: float = float((points[_selected_index] as Dictionary).get("z", 0.0))
		if is_equal_approx(z, 0.0) or is_equal_approx(z, LAYOUT_SCRIPT.COURSE_LENGTH):
			_set_status("スタートとゴールの高さ点は削除できません")
			return
		points.remove_at(_selected_index)
		_layout["height_points"] = points
	else:
		return
	_selected_kind = ""
	_selected_index = -1
	_mark_changed("選択項目を削除しました")


func _focus_whole_course() -> void:
	_orbit_target = Vector3(0.0, 1.0, LAYOUT_SCRIPT.COURSE_LENGTH * 0.5)
	_orbit_yaw = -2.62
	_orbit_pitch = 0.45
	_orbit_distance = 125.0
	_update_camera()
	_set_status("コース全体を表示しました")


func _focus_selected() -> void:
	var item: Dictionary = get_selected_data()
	if item.is_empty():
		return
	var z: float = float(item.get("z", _probe_z))
	var x: float = float(item.get("x", -6.7 if _selected_kind == "height" else 0.0))
	var height: float = LAYOUT_SCRIPT.get_height(_layout, z)
	_orbit_target = Vector3(x, SURFACE_Y + height + 0.8, z)
	_orbit_distance = 28.0
	_update_camera()


func _refresh_selection_ui() -> void:
	_updating_inspector = true
	var item: Dictionary = get_selected_data()
	var has_selection: bool = not item.is_empty()
	_x_spin.editable = has_selection and _selected_kind == "gimmick" and str(item.get("type", "")) != "bump"
	_z_spin.editable = has_selection
	_height_spin.editable = has_selection and _selected_kind == "height"
	_rotation_spin.editable = has_selection and _selected_kind == "gimmick"
	_duplicate_button.disabled = not (has_selection and _selected_kind == "gimmick")
	_delete_button.disabled = not has_selection
	if not has_selection:
		_selection_label.text = "未選択"
		_x_spin.value = 0.0
		_z_spin.value = 0.0
		_height_spin.value = 0.0
		_rotation_spin.value = 0.0
	elif _selected_kind == "gimmick":
		_selection_label.text = "%s  [%s]" % [
			LAYOUT_SCRIPT.type_label(str(item.get("type", ""))),
			str(item.get("id", "")),
		]
		_x_spin.value = float(item.get("x", 0.0))
		_z_spin.value = float(item.get("z", 0.0))
		_height_spin.value = LAYOUT_SCRIPT.get_height(_layout, float(item.get("z", 0.0)))
		_rotation_spin.value = float(item.get("rotation_y", 0.0))
	else:
		var z: float = float(item.get("z", 0.0))
		_selection_label.text = "高さ制御点  Z=%.1f m" % z
		_x_spin.value = -6.7
		_z_spin.value = z
		_height_spin.value = float(item.get("height", 0.0))
		_rotation_spin.value = 0.0
		_z_spin.editable = z > 0.0 and z < LAYOUT_SCRIPT.COURSE_LENGTH
	_updating_inspector = false


func _mark_changed(message: String) -> void:
	_dirty = true
	_rebuild_all()
	_set_status(message)


func _update_count() -> void:
	if _count_label == null:
		return
	_count_label.text = "ギミック %d個 / 高さ点 %d個%s" % [
		get_gimmick_count(),
		get_height_point_count(),
		"  ●未保存" if _dirty else "",
	]


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _update_camera() -> void:
	if _camera == null:
		return
	var horizontal: float = cos(_orbit_pitch)
	var offset := Vector3(
		sin(_orbit_yaw) * horizontal,
		sin(_orbit_pitch),
		cos(_orbit_yaw) * horizontal
	) * _orbit_distance
	_camera.position = _orbit_target + offset
	_camera.look_at(_orbit_target, Vector3.UP)


func _selected_array() -> Array:
	if _selected_kind == "gimmick":
		return _layout.get("gimmicks", []) as Array
	if _selected_kind == "height":
		return _layout.get("height_points", []) as Array
	return []


func _find_height_index(z: float) -> int:
	var points: Array = _layout.get("height_points", [])
	for index: int in range(points.size()):
		if is_equal_approx(float((points[index] as Dictionary).get("z", 0.0)), z):
			return index
	return -1


func _next_item_id(type_id: String) -> String:
	var used: Dictionary = {}
	for raw: Variant in _layout.get("gimmicks", []):
		if raw is Dictionary:
			used[str((raw as Dictionary).get("id", ""))] = true
	var number: int = 0
	while used.has("%s_%02d" % [type_id, number]):
		number += 1
	return "%s_%02d" % [type_id, number]


func _open_2d_editor() -> void:
	get_tree().change_scene_to_file("res://tools/bike_course_layout_editor.tscn")


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _add_rod(parent: Node3D, start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
	var rod: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(finish)
	mesh.radial_segments = 10
	rod.mesh = mesh
	rod.material_override = material
	rod.position = (start + finish) * 0.5
	rod.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	parent.add_child(rod)


func _material(color: Color, roughness: float, transparent: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent or color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


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
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.98))
	return label


func _button(text: String, color: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(82.0, 38.0)
	var normal: StyleBoxFlat = _panel_style(color.darkened(0.38), color)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.darkened(0.18)
	button.add_theme_stylebox_override("hover", hover)
	return button


func _add_spin_row(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	callback: Callable
) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = label_text.replace(" ", "")
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 78.0
	row.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(160.0, 36.0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.editable = false
	spin.value_changed.connect(callback)
	row.add_child(spin)
	parent.add_child(row)
	return spin
