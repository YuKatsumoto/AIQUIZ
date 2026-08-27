extends Node3D


const SAVE_PATH: String = "user://beam_preset_reviewer.cfg"
const BEAM_LENGTH: float = 28.0
const BEAM_RENDER_LAYER: int = 19

const PRESET_IDS: PackedStringArray = [
	"beam_01", "beam_02", "beam_03", "beam_04",
	"beam_05", "beam_06", "beam_07", "beam_08",
	"laser_01", "laser_02", "laser_03", "laser_04",
	"laser_05", "laser_06", "laser_07", "laser_08",
]

const PRESET_LABELS: PackedStringArray = [
	"Beam 01", "Beam 02", "Beam 03", "Beam 04",
	"Beam 05", "Beam 06", "Beam 07", "Beam 08",
	"Laser 01", "Laser 02", "Laser 03", "Laser 04",
	"Laser 05", "Laser 06", "Laser 07", "Laser 08",
]

const PRESET_PATHS: PackedStringArray = [
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_01.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_02.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_03.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_04.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_05.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_06.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_07.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_08.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_01.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_02.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_03.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_04.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_05.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_06.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_07.tscn",
	"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_08.tscn",
]

# Captured from the real P1-death/P2-survivor BEAM_REVEAL state. The camera is
# shifted 9m toward the effect without changing its rotation or FOV so all three
# rays stay readable beside the review panel.
const REVIEW_CAMERA_TRANSFORM: Transform3D = Transform3D(
	Basis(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.979083, 0.203462),
		Vector3(0.0, 0.203462, -0.979083)
	),
	Vector3(9.0, 4.532753, -9.0)
)

const BEAM_TRANSFORMS: Array[Transform3D] = [
	Transform3D(
		Basis(
			Vector3(-0.990916, -0.134481, 0.0),
			Vector3(-0.018849, 0.138889, -0.990129),
			Vector3(0.133154, -0.981134, -0.140162)
		),
		Vector3(16.25421, -9.02, 10.05013)
	),
	Transform3D(
		Basis(
			Vector3(-0.919145, -0.393919, 0.0),
			Vector3(0.032219, -0.075178, -0.996649),
			Vector3(0.392599, -0.916065, 0.081792)
		),
		Vector3(13.95421, -9.02, 10.05013)
	),
	Transform3D(
		Basis(
			Vector3(-0.968493, -0.249041, 0.0),
			Vector3(0.050606, -0.196802, -0.979136),
			Vector3(0.243845, -0.948287, 0.203204)
		),
		Vector3(15.10421, -9.02, 8.300126)
	),
]

var _stage_environment: StageEnvironment = null
var _camera: Camera3D = null
var _beam_holder: Node3D = null
var _active_beams: Array[Node3D] = []
var _preset_buttons: Array[Button] = []
var _current_label: Label = null
var _saved_label: Label = null
var _status_label: Label = null
var _current_index: int = 0
var _saved_preset_id: String = ""


func _ready() -> void:
	_configure_window()
	_build_review_world()
	_build_interface()
	_load_saved_selection()
	_select_preset(_current_index)


func _configure_window() -> void:
	var window: Window = get_window()
	window.title = "AIQUIZ Beam Preset Reviewer"
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(1280, 720)
	window.min_size = Vector2i(960, 540)


func _build_review_world() -> void:
	_stage_environment = StageEnvironment.new()
	_stage_environment.name = "StageEnvironment"
	add_child(_stage_environment)
	_stage_environment.build({
		"floor_center_z": 0.0,
		"floor_length": 144.0,
		"include_back_roller": true,
		"include_floor_collision": false,
		"is_preview": true,
		"include_sharks": false,
		"include_grandstands": true,
	})

	_beam_holder = Node3D.new()
	_beam_holder.name = "PreviewBeams"
	add_child(_beam_holder)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.global_transform = REVIEW_CAMERA_TRANSFORM
	_camera.fov = 50.0
	_camera.far = 160.0
	_camera.current = true
	_camera.set_cull_mask_value(BEAM_RENDER_LAYER, true)
	add_child(_camera)


func _build_interface() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ReviewerUI"
	layer.layer = 20
	add_child(layer)

	var root_control: Control = Control.new()
	root_control.name = "UIRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(root_control)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ControlPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -390.0
	panel.offset_top = 18.0
	panel.offset_right = -18.0
	panel.offset_bottom = -18.0
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.055, 0.10, 0.94)
	panel_style.border_color = Color(0.18, 0.72, 1.0, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", panel_style)
	root_control.add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "BEAM PRESET REVIEWER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	content.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "実ゲームと同じカメラ・海・3本配置"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
	content.add_child(subtitle)

	_current_label = Label.new()
	_current_label.name = "CurrentPreset"
	_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_current_label.add_theme_font_size_override("font_size", 30)
	_current_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(_current_label)

	var grid: GridContainer = GridContainer.new()
	grid.name = "PresetGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	content.add_child(grid)

	var button_group: ButtonGroup = ButtonGroup.new()
	button_group.allow_unpress = false
	for index: int in range(PRESET_IDS.size()):
		var button: Button = Button.new()
		button.name = "PresetButton%s" % PRESET_IDS[index].to_upper()
		button.text = _short_button_label(index)
		button.custom_minimum_size = Vector2(76.0, 42.0)
		button.toggle_mode = true
		button.button_group = button_group
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_select_preset.bind(index))
		grid.add_child(button)
		_preset_buttons.append(button)

	var nav: HBoxContainer = HBoxContainer.new()
	nav.name = "Navigation"
	nav.add_theme_constant_override("separation", 10)
	content.add_child(nav)

	var previous_button: Button = _make_action_button("PreviousButton", "◀ 前へ")
	previous_button.pressed.connect(_select_relative.bind(-1))
	nav.add_child(previous_button)

	var next_button: Button = _make_action_button("NextButton", "次へ ▶")
	next_button.pressed.connect(_select_relative.bind(1))
	nav.add_child(next_button)

	var save_button: Button = _make_action_button(
		"SaveSelectionButton",
		"このプリセットを採用候補として保存"
	)
	save_button.custom_minimum_size.y = 48.0
	save_button.add_theme_color_override("font_color", Color(0.20, 0.12, 0.02))
	var save_style: StyleBoxFlat = StyleBoxFlat.new()
	save_style.bg_color = Color(1.0, 0.74, 0.24)
	save_style.set_corner_radius_all(8)
	save_button.add_theme_stylebox_override("normal", save_style)
	save_button.pressed.connect(_save_current_selection)
	content.add_child(save_button)

	_saved_label = Label.new()
	_saved_label.name = "SavedPreset"
	_saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved_label.add_theme_font_size_override("font_size", 17)
	_saved_label.add_theme_color_override("font_color", Color(0.64, 1.0, 0.68))
	content.add_child(_saved_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "プリセットをクリックして比較してください。"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.92))
	content.add_child(_status_label)

	var spacer: Control = Control.new()
	spacer.name = "FlexibleSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	var close_button: Button = _make_action_button("CloseButton", "終了")
	close_button.pressed.connect(_close_reviewer)
	content.add_child(close_button)


func _make_action_button(node_name: String, label_text: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = label_text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	return button


func _short_button_label(index: int) -> String:
	var prefix: String = "B" if index < 8 else "L"
	var number: int = index + 1 if index < 8 else index - 7
	return "%s%02d" % [prefix, number]


func _select_relative(delta: int) -> void:
	_select_preset(posmod(_current_index + delta, PRESET_IDS.size()))


func _select_preset(index: int) -> void:
	if index < 0 or index >= PRESET_IDS.size():
		return
	_current_index = index
	_clear_active_beams()

	var packed: PackedScene = load(PRESET_PATHS[_current_index]) as PackedScene
	if packed == null:
		_status_label.text = "読み込みに失敗しました: %s" % PRESET_PATHS[_current_index]
		return

	for beam_index: int in range(BEAM_TRANSFORMS.size()):
		var beam: Node3D = packed.instantiate() as Node3D
		if beam == null:
			_status_label.text = "プリセットを生成できませんでした。"
			continue
		beam.name = "ReviewBeam%02d" % (beam_index + 1)
		beam.set_meta("beam_reviewer_preset", PRESET_IDS[_current_index])
		_beam_holder.add_child(beam)
		beam.set("beam_length", BEAM_LENGTH)
		beam.set("open_amount", 1.0)
		beam.global_transform = BEAM_TRANSFORMS[beam_index]
		_set_render_layer(beam)
		_active_beams.append(beam)

	_current_label.text = "%s   (%d / %d)" % [
		PRESET_LABELS[_current_index],
		_current_index + 1,
		PRESET_IDS.size(),
	]
	for button_index: int in range(_preset_buttons.size()):
		_preset_buttons[button_index].set_pressed_no_signal(button_index == _current_index)
	_status_label.text = "表示中: %s / 3本同期 / 長さ %.0fm" % [
		PRESET_LABELS[_current_index],
		BEAM_LENGTH,
	]
	set_meta("current_preset_id", PRESET_IDS[_current_index])


func _clear_active_beams() -> void:
	for beam: Node3D in _active_beams:
		if beam != null and is_instance_valid(beam):
			beam.queue_free()
	_active_beams.clear()


func _set_render_layer(node: Node) -> void:
	if node is VisualInstance3D:
		var visual: VisualInstance3D = node as VisualInstance3D
		visual.layers = 0
		visual.set_layer_mask_value(BEAM_RENDER_LAYER, true)
	for child: Node in node.get_children():
		_set_render_layer(child)


func _load_saved_selection() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SAVE_PATH)
	if error != OK:
		_saved_preset_id = ""
		_update_saved_label()
		return
	var saved_id: String = String(config.get_value("selection", "preset_id", ""))
	var saved_index: int = PRESET_IDS.find(saved_id)
	if saved_index >= 0:
		_saved_preset_id = saved_id
		_current_index = saved_index
	_update_saved_label()


func _save_current_selection() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("selection", "preset_id", PRESET_IDS[_current_index])
	config.set_value("selection", "preset_label", PRESET_LABELS[_current_index])
	config.set_value("selection", "scene_path", PRESET_PATHS[_current_index])
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		_status_label.text = "候補を保存できませんでした: error %d" % error
		return
	_saved_preset_id = PRESET_IDS[_current_index]
	_update_saved_label()
	_status_label.text = "%s を採用候補として保存しました。" % PRESET_LABELS[_current_index]


func _update_saved_label() -> void:
	if _saved_label == null:
		return
	var saved_index: int = PRESET_IDS.find(_saved_preset_id)
	if saved_index < 0:
		_saved_label.text = "保存済み候補: なし"
	else:
		_saved_label.text = "保存済み候補: %s" % PRESET_LABELS[saved_index]


func _close_reviewer() -> void:
	get_tree().quit()


func get_debug_state() -> Dictionary:
	return {
		"current_index": _current_index,
		"current_preset_id": PRESET_IDS[_current_index],
		"current_label": PRESET_LABELS[_current_index],
		"saved_preset_id": _saved_preset_id,
		"beam_count": _active_beams.size(),
		"beam_length": BEAM_LENGTH,
		"save_path": SAVE_PATH,
	}
