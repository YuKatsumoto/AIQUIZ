extends CanvasLayer

## メインメニュー背景カメラの直感チューニング（F9 で表示切替）

signal tuner_open_changed(is_open: bool)
signal wall_speed_camera_saved

enum CameraContext {
	MENU,
	CUSTOMIZE_WALL_SPEED,
}

const MenuPreviewCameraSettingsScript = preload("res://scripts/ui/menu_preview_camera_settings.gd")
const CustomizePreviewCameraSettingsScript = preload(
	"res://scripts/ui/customize_preview_camera_settings.gd"
)

const ORBIT_PIVOT := Vector3(0.0, 1.2, 0.0)
const MOUSE_SENS_ORBIT := 0.32
const MOUSE_SENS_PAN := 0.035
const WHEEL_SENS_DISTANCE := 0.85

var _preview_root: Node = null
var _camera: Camera3D = null
var _context: CameraContext = CameraContext.MENU
var _title_label: Label
var _panel: PanelContainer
var _status_label: Label
var _drag_zone: Control
var _sliders: Dictionary = {}
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -0.25
var _orbit_distance: float = 20.0
var _left_drag: bool = false
var _right_drag: bool = false
var _syncing_sliders: bool = false


func setup(preview_root: Node) -> void:
	_preview_root = preview_root
	if _preview_root and _preview_root.has_method("get_camera"):
		_camera = _preview_root.get_camera() as Camera3D
	if _camera:
		_init_orbit_from_camera()
		_refresh_sliders_from_camera()


func set_context(context: CameraContext) -> void:
	_context = context
	_refresh_context_ui()


func get_context() -> CameraContext:
	return _context


func open_tuner() -> void:
	visible = true
	_init_orbit_from_camera()
	_refresh_sliders_from_camera()
	tuner_open_changed.emit(true)


func close_tuner() -> void:
	visible = false
	_left_drag = false
	_right_drag = false
	tuner_open_changed.emit(false)


func toggle_tuner() -> void:
	if visible:
		close_tuner()
	else:
		open_tuner()


func _ready() -> void:
	layer = 95
	visible = false
	_build_ui()


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_drag_zone = Control.new()
	_drag_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_zone.anchor_left = 0.52
	_drag_zone.anchor_right = 1.0
	_drag_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_drag_zone.gui_input.connect(_on_drag_zone_input)
	root.add_child(_drag_zone)

	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -520.0
	hint.offset_top = 12.0
	hint.offset_right = -16.0
	hint.offset_bottom = 120.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	hint.text = "[F9] ツール切替\n左ドラッグ: 位置パン  |  右ドラッグ: 回転(オービット)\nホイール: 前後(距離)  |  Shift+左ドラッグ: 高さ / h_offset"
	root.add_child(hint)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -436.0
	_panel.offset_top = -400.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	style.border_color = Color(0.35, 0.5, 0.75, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	vbox.add_child(_title_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_add_slider_row(vbox, "pos_x", "位置 X", -20.0, 20.0, 0.05)
	_add_slider_row(vbox, "pos_y", "位置 Y", -2.0, 12.0, 0.05)
	_add_slider_row(vbox, "pos_z", "位置 Z", 4.0, 40.0, 0.05)
	_add_slider_row(vbox, "rot_x", "回転 X", -60.0, 30.0, 0.5)
	_add_slider_row(vbox, "rot_y", "回転 Y", -60.0, 60.0, 0.5)
	_add_slider_row(vbox, "rot_z", "回転 Z", -30.0, 30.0, 0.5)
	_add_slider_row(vbox, "fov", "FOV", 35.0, 90.0, 0.5)
	_add_slider_row(vbox, "h_offset", "水平オフセット", -1.0, 1.5, 0.01)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "JSONに保存"
	save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "デフォルトに戻す"
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)

	var copy_btn := Button.new()
	copy_btn.text = "定数をコピー"
	copy_btn.pressed.connect(_on_copy_pressed)
	btn_row.add_child(copy_btn)

	_refresh_context_ui()


func _refresh_context_ui() -> void:
	if _title_label:
		match _context:
			CameraContext.CUSTOMIZE_WALL_SPEED:
				_title_label.text = "壁速度プレビュー カメラ調整"
			_:
				_title_label.text = "メニュー背景カメラ調整"
	_update_status("未保存")


func _settings_for_context() -> Variant:
	return (
		CustomizePreviewCameraSettingsScript
		if _context == CameraContext.CUSTOMIZE_WALL_SPEED
		else MenuPreviewCameraSettingsScript
	)


func _add_slider_row(parent: Node, key: String, label_text: String, min_v: float, max_v: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(56, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(value_lbl)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)

	_sliders[key] = {"slider": slider, "value_label": value_lbl}


func _on_slider_changed(value: float, key: String) -> void:
	if _syncing_sliders or not _camera:
		return
	match key:
		"pos_x":
			_camera.position.x = value
		"pos_y":
			_camera.position.y = value
		"pos_z":
			_camera.position.z = value
		"rot_x":
			_camera.rotation_degrees.x = value
		"rot_y":
			_camera.rotation_degrees.y = value
		"rot_z":
			_camera.rotation_degrees.z = value
		"fov":
			_camera.fov = value
		"h_offset":
			_camera.h_offset = value
	_init_orbit_from_camera()
	_update_slider_labels_only()
	_update_status("編集中")


func _refresh_sliders_from_camera() -> void:
	if not _camera:
		return
	_syncing_sliders = true
	_set_slider("pos_x", _camera.position.x)
	_set_slider("pos_y", _camera.position.y)
	_set_slider("pos_z", _camera.position.z)
	_set_slider("rot_x", _camera.rotation_degrees.x)
	_set_slider("rot_y", _camera.rotation_degrees.y)
	_set_slider("rot_z", _camera.rotation_degrees.z)
	_set_slider("fov", _camera.fov)
	_set_slider("h_offset", _camera.h_offset)
	_syncing_sliders = false


func _set_slider(key: String, value: float) -> void:
	if not _sliders.has(key):
		return
	var entry: Dictionary = _sliders[key]
	entry["slider"].value = value
	entry["value_label"].text = "%.2f" % value


func _update_slider_labels_only() -> void:
	for key in _sliders:
		var entry: Dictionary = _sliders[key]
		entry["value_label"].text = "%.2f" % float(entry["slider"].value)


func _init_orbit_from_camera() -> void:
	if not _camera:
		return
	var offset := _camera.position - ORBIT_PIVOT
	_orbit_distance = maxf(4.0, offset.length())
	if _orbit_distance > 0.001:
		_orbit_pitch = asin(clampf(offset.y / _orbit_distance, -1.0, 1.0))
		_orbit_yaw = atan2(offset.x, offset.z)


func _apply_orbit_to_camera() -> void:
	if not _camera:
		return
	var cp := cos(_orbit_pitch)
	var offset := Vector3(
		sin(_orbit_yaw) * cp * _orbit_distance,
		sin(_orbit_pitch) * _orbit_distance,
		cos(_orbit_yaw) * cp * _orbit_distance,
	)
	_camera.position = ORBIT_PIVOT + offset
	_camera.look_at(ORBIT_PIVOT, Vector3.UP)
	_refresh_sliders_from_camera()


func _on_drag_zone_input(event: InputEvent) -> void:
	if not _camera or not visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_left_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_right_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit_distance = maxf(4.0, _orbit_distance - WHEEL_SENS_DISTANCE)
			_apply_orbit_to_camera()
			_update_status("編集中")
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit_distance += WHEEL_SENS_DISTANCE
			_apply_orbit_to_camera()
			_update_status("編集中")
	elif event is InputEventMouseMotion and (_left_drag or _right_drag):
		var mm := event as InputEventMouseMotion
		if _right_drag:
			_orbit_yaw -= deg_to_rad(mm.relative.x * MOUSE_SENS_ORBIT)
			_orbit_pitch = clampf(
				_orbit_pitch - deg_to_rad(mm.relative.y * MOUSE_SENS_ORBIT),
				deg_to_rad(-75.0),
				deg_to_rad(30.0),
			)
			_apply_orbit_to_camera()
		elif _left_drag:
			var shift := Input.is_key_pressed(KEY_SHIFT)
			if shift:
				_camera.position.y -= mm.relative.y * MOUSE_SENS_PAN
				_camera.h_offset += mm.relative.x * 0.004
			else:
				_camera.position.x += mm.relative.x * MOUSE_SENS_PAN
				_camera.position.z -= mm.relative.y * MOUSE_SENS_PAN
			_init_orbit_from_camera()
			_refresh_sliders_from_camera()
		_update_status("編集中")


func _on_save_pressed() -> void:
	if not _camera:
		return
	var settings_script: Variant = _settings_for_context()
	var settings: Dictionary = settings_script.read_from_camera(_camera)
	if settings_script.save_settings(settings):
		match _context:
			CameraContext.CUSTOMIZE_WALL_SPEED:
				_update_status(
					"JSONに保存しました（壁速度タブのカメラに即時反映されます）"
				)
				wall_speed_camera_saved.emit()
			_:
				_update_status(
					"JSONに保存しました（次回起動は menu_wall_background_preview.gd の定数が使われます）"
				)
	else:
		_update_status("保存に失敗しました")


func _on_reset_pressed() -> void:
	if not _camera:
		return
	var settings_script: Variant = _settings_for_context()
	settings_script.apply_code_defaults_to_camera(_camera)
	settings_script.clear_saved_settings()
	_init_orbit_from_camera()
	_refresh_sliders_from_camera()
	match _context:
		CameraContext.CUSTOMIZE_WALL_SPEED:
			_update_status("壁速度カメラのデフォルトに戻しました（保存JSONも削除）")
			wall_speed_camera_saved.emit()
		_:
			_update_status("PREVIEW_CAM_* の定数に戻しました（保存JSONも削除）")


func _on_copy_pressed() -> void:
	if not _camera:
		return
	var settings_script: Variant = _settings_for_context()
	var text: String = settings_script.to_gdscript_constants(
		settings_script.read_from_camera(_camera)
	)
	DisplayServer.clipboard_set(text)
	match _context:
		CameraContext.CUSTOMIZE_WALL_SPEED:
			_update_status(
				"定数をコピーしました。customize_preview_camera_settings.gd の DEFAULT_* に貼付できます"
			)
		_:
			_update_status(
				"定数をコピーしました。menu_wall_background_preview.gd の PREVIEW_CAM_* に貼付すると次回起動から反映されます"
			)


func _update_status(text: String) -> void:
	if _status_label:
		_status_label.text = text
