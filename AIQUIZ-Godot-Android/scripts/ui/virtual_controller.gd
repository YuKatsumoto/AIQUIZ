extends Control
class_name VirtualController

signal jump_triggered
signal emote_triggered(emote_id: int)
signal pause_triggered
signal primary_action_triggered
signal swipe_left
signal swipe_right

const SWIPE_THRESHOLD := 58.0
const JOYSTICK_DEADZONE := 0.12
const DEBUG_MOUSE_POINTER := -100

@onready var joystick: Control = $Joystick
@onready var joystick_base: Panel = $Joystick/Base
@onready var joystick_tip: Panel = $Joystick/Base/Tip
@onready var jump_button: Button = $JumpButton
@onready var pause_button: Button = $PauseButton
@onready var emote_container: HBoxContainer = $EmoteButtons
@onready var emote_1: Button = $EmoteButtons/Emote1
@onready var emote_2: Button = $EmoteButtons/Emote2
@onready var emote_3: Button = $EmoteButtons/Emote3

var joystick_active := false
var joystick_pointer := -1
var joystick_center := Vector2.ZERO
var joystick_vector := Vector2.ZERO
var joystick_radius := 72.0
var jump_active := false
var action_pointers: Dictionary = {}
var swipe_active := false
var swipe_pointer := -1
var swipe_start_pos := Vector2.ZERO
var _mobile_profile := false
var _cpu_enabled := false
var _ghost_mode := false
var _last_emote_signature := ""
var _primary_action_button: Button = null
var _cpu_badge: PanelContainer = null
var _cpu_badge_label: Label = null
var _move_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_mobile_profile = _is_mobile_profile()
	_build_runtime_controls()
	_style_ui()
	_connect_controls()
	get_viewport().size_changed.connect(_layout_controls)
	call_deferred("_layout_controls")
	visible = _mobile_profile


func _is_mobile_profile() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("android")
		or OS.has_feature("ios")
		or bool(ProjectSettings.get_setting("aiquiz/mobile/enabled", false))
	)


func _build_runtime_controls() -> void:
	_move_label = Label.new()
	_move_label.name = "MoveLabel"
	_move_label.text = "移動"
	_move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_label.add_theme_font_size_override("font_size", 16)
	_move_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.70, 0.92))
	_move_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	_move_label.add_theme_constant_override("outline_size", 4)
	_move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_move_label)

	_primary_action_button = Button.new()
	_primary_action_button.name = "PrimaryActionButton"
	_primary_action_button.text = "タップしてスタート"
	_primary_action_button.focus_mode = Control.FOCUS_NONE
	_primary_action_button.add_theme_font_size_override("font_size", 22)
	_primary_action_button.visible = false
	add_child(_primary_action_button)

	_cpu_badge = PanelContainer.new()
	_cpu_badge.name = "CpuBadge"
	_cpu_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cpu_badge_label = Label.new()
	_cpu_badge_label.text = "P2  CPU"
	_cpu_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cpu_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cpu_badge_label.add_theme_font_size_override("font_size", 16)
	_cpu_badge_label.add_theme_color_override("font_color", Color(0.80, 0.96, 1.0))
	_cpu_badge.add_child(_cpu_badge_label)
	_cpu_badge.visible = false
	add_child(_cpu_badge)


func _connect_controls() -> void:
	jump_button.button_down.connect(_on_jump_down)
	jump_button.button_up.connect(_on_jump_up)
	pause_button.pressed.connect(func() -> void: pause_triggered.emit())
	_primary_action_button.pressed.connect(func() -> void: primary_action_triggered.emit())
	emote_1.pressed.connect(func() -> void: _on_emote_pressed(0))
	emote_2.pressed.connect(func() -> void: _on_emote_pressed(1))
	emote_3.pressed.connect(func() -> void: _on_emote_pressed(2))


func _style_ui() -> void:
	joystick_base.add_theme_stylebox_override(
		"panel",
		_round_style(Color(0.03, 0.055, 0.10, 0.62), 96, Color(1.0, 0.65, 0.22, 0.82), 4)
	)
	joystick_tip.add_theme_stylebox_override(
		"panel",
		_round_style(Color(1.0, 0.58, 0.16, 0.88), 48, Color(1.0, 0.88, 0.60, 0.96), 3)
	)

	_apply_button_style(
		jump_button,
		Color(0.95, 0.38, 0.09, 0.90),
		Color(1.0, 0.62, 0.18, 0.98),
		64
	)
	jump_button.text = "ジャンプ"
	jump_button.add_theme_font_size_override("font_size", 19)

	_apply_button_style(
		pause_button,
		Color(0.025, 0.045, 0.08, 0.84),
		Color(0.12, 0.26, 0.42, 0.96),
		18
	)
	pause_button.text = "Ⅱ"
	pause_button.add_theme_font_size_override("font_size", 22)

	for button: Button in [emote_1, emote_2, emote_3]:
		_apply_button_style(
			button,
			Color(0.04, 0.08, 0.13, 0.82),
			Color(0.10, 0.42, 0.58, 0.96),
			16
		)
		button.add_theme_font_size_override("font_size", 12)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_apply_button_style(
		_primary_action_button,
		Color(0.08, 0.42, 0.70, 0.95),
		Color(0.12, 0.62, 0.92, 1.0),
		24
	)
	var badge_style := _round_style(
		Color(0.025, 0.10, 0.16, 0.90), 16, Color(0.20, 0.72, 0.92, 0.90), 2
	)
	badge_style.content_margin_left = 14.0
	badge_style.content_margin_right = 14.0
	badge_style.content_margin_top = 7.0
	badge_style.content_margin_bottom = 7.0
	_cpu_badge.add_theme_stylebox_override("panel", badge_style)
	_update_emote_labels()


func _round_style(
	background: Color,
	radius: int,
	border: Color = Color.TRANSPARENT,
	border_width: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _apply_button_style(button: Button, normal_color: Color, pressed_color: Color, radius: int) -> void:
	var normal := _round_style(normal_color, radius, Color(1.0, 1.0, 1.0, 0.28), 2)
	var pressed := _round_style(pressed_color, radius, Color(1.0, 1.0, 1.0, 0.62), 3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal.duplicate())
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.82))
	button.add_theme_constant_override("outline_size", 3)
	button.focus_mode = Control.FOCUS_NONE


func _layout_controls() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := clampf(viewport_size.y / 720.0, 0.82, 1.12)
	var edge := 34.0 * scale_factor
	var stick_box := 202.0 * scale_factor
	var base_size := 162.0 * scale_factor
	var tip_size := 62.0 * scale_factor
	joystick_radius = base_size * 0.44

	joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.offset_left = edge
	joystick.offset_top = -edge - stick_box
	joystick.offset_right = edge + stick_box
	joystick.offset_bottom = -edge
	joystick_base.set_anchors_preset(Control.PRESET_CENTER)
	joystick_base.offset_left = -base_size * 0.5
	joystick_base.offset_top = -base_size * 0.5
	joystick_base.offset_right = base_size * 0.5
	joystick_base.offset_bottom = base_size * 0.5
	joystick_tip.size = Vector2.ONE * tip_size
	_reset_joystick_tip()

	_move_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_label.offset_left = edge
	_move_label.offset_top = -edge - stick_box - 24.0
	_move_label.offset_right = edge + stick_box
	_move_label.offset_bottom = -edge - stick_box

	var jump_size := 126.0 * scale_factor
	jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_button.offset_left = -edge - jump_size
	jump_button.offset_top = -edge - jump_size
	jump_button.offset_right = -edge
	jump_button.offset_bottom = -edge

	var emote_width := 276.0 * scale_factor
	emote_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	emote_container.offset_left = -edge - emote_width
	emote_container.offset_top = -edge - jump_size - 82.0 * scale_factor
	emote_container.offset_right = -edge
	emote_container.offset_bottom = -edge - jump_size - 22.0 * scale_factor
	emote_container.add_theme_constant_override("separation", int(10.0 * scale_factor))
	for button: Button in [emote_1, emote_2, emote_3]:
		button.custom_minimum_size = Vector2(0.0, 58.0 * scale_factor)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -edge - 62.0 * scale_factor
	pause_button.offset_top = edge
	pause_button.offset_right = -edge
	pause_button.offset_bottom = edge + 62.0 * scale_factor

	_primary_action_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_primary_action_button.offset_left = -180.0 * scale_factor
	_primary_action_button.offset_top = -98.0 * scale_factor
	_primary_action_button.offset_right = 180.0 * scale_factor
	_primary_action_button.offset_bottom = -34.0 * scale_factor

	_cpu_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cpu_badge.offset_left = edge
	_cpu_badge.offset_top = edge
	_cpu_badge.offset_right = edge + 112.0 * scale_factor
	_cpu_badge.offset_bottom = edge + 38.0 * scale_factor


func set_cpu_enabled(enabled: bool) -> void:
	_cpu_enabled = enabled


func set_ghost_mode(enabled: bool) -> void:
	if _ghost_mode == enabled:
		return
	_ghost_mode = enabled
	jump_button.text = "チャージ" if enabled else "ジャンプ"


func _process(_delta: float) -> void:
	if not _mobile_profile:
		visible = false
		return
	visible = true
	var state := QuizManager.game_state
	if state == null:
		_set_gameplay_controls_visible(false)
		return

	var gameplay_active := state.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE]
	_set_gameplay_controls_visible(gameplay_active)
	pause_button.visible = state.game_state in [
		Constants.STATE_WAITING_START,
		Constants.STATE_FLYOVER,
		Constants.STATE_COUNTDOWN,
		Constants.STATE_PLAYING,
		Constants.STATE_GOAL_RACE,
	]
	_cpu_badge.visible = _cpu_enabled and state.num_players >= 2

	var presentation_locked := (
		state.mode == Constants.MODE_TUTORIAL
		and state.is_tutorial_presentation_locked()
	)
	if state.game_state == Constants.STATE_WAITING_START:
		_primary_action_button.text = "タップしてスタート"
		_primary_action_button.visible = true
	elif presentation_locked:
		_primary_action_button.text = "スキップ"
		_primary_action_button.visible = true
	else:
		_primary_action_button.visible = false

	if gameplay_active:
		_update_emote_labels()
	else:
		_reset_pointer_state()


func _set_gameplay_controls_visible(show_controls: bool) -> void:
	joystick.visible = show_controls
	_move_label.visible = show_controls
	jump_button.visible = show_controls
	emote_container.visible = show_controls


func _update_emote_labels() -> void:
	var state := QuizManager.game_state
	if state == null:
		return
	var signature := str(state.p1_emote_slots)
	if signature == _last_emote_signature:
		return
	_last_emote_signature = signature
	var buttons: Array[Button] = [emote_1, emote_2, emote_3]
	for index: int in range(buttons.size()):
		var button := buttons[index]
		if state.p1_emote_slots.size() <= index:
			button.visible = false
			continue
		var emote_id := int(state.p1_emote_slots[index])
		var emote_name := EmoteData.get_emote_name(emote_id)
		var display_name := emote_name.left(6)
		if display_name.length() < emote_name.length():
			display_name += "…"
		button.text = "%d\n%s" % [index + 1, display_name]
		button.tooltip_text = emote_name
		button.visible = true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if _handle_action_touch(touch.index, touch.position, touch.pressed):
			get_viewport().set_input_as_handled()
			return
		if not joystick.visible:
			return
		_handle_pointer_button(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		if not joystick.visible:
			return
		var drag := event as InputEventScreenDrag
		_handle_pointer_motion(drag.index, drag.position)
	elif bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)):
		if not joystick.visible:
			return
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index == MOUSE_BUTTON_LEFT:
				_handle_pointer_button(DEBUG_MOUSE_POINTER, mouse_button.position, mouse_button.pressed)
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_pointer_motion(DEBUG_MOUSE_POINTER, (event as InputEventMouseMotion).position)


func _handle_action_touch(pointer: int, position: Vector2, pressed: bool) -> bool:
	if pressed:
		if jump_button.visible and jump_button.get_global_rect().has_point(position):
			action_pointers[pointer] = "jump"
			_on_jump_down()
			return true
		if pause_button.visible and pause_button.get_global_rect().has_point(position):
			action_pointers[pointer] = "pause"
			pause_triggered.emit()
			return true
		if _primary_action_button.visible and _primary_action_button.get_global_rect().has_point(position):
			action_pointers[pointer] = "primary"
			primary_action_triggered.emit()
			return true
		var emote_buttons: Array[Button] = [emote_1, emote_2, emote_3]
		for slot_index: int in range(emote_buttons.size()):
			var button := emote_buttons[slot_index]
			if button.visible and button.get_global_rect().has_point(position):
				action_pointers[pointer] = "emote"
				_on_emote_pressed(slot_index)
				return true
		return false

	if not action_pointers.has(pointer):
		return false
	var action := str(action_pointers[pointer])
	action_pointers.erase(pointer)
	if action == "jump":
		_on_jump_up()
	return true


func _handle_pointer_button(pointer: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		if _is_over_action_control(position):
			return
		var center := joystick_base.global_position + joystick_base.size * 0.5
		var activation_radius := joystick_base.size.x * 0.82
		if joystick_pointer < 0 and position.distance_to(center) <= activation_radius:
			joystick_pointer = pointer
			joystick_active = true
			joystick_center = center
			_update_joystick(position)
			swipe_active = false
			return
		if swipe_pointer < 0:
			swipe_pointer = pointer
			swipe_active = true
			swipe_start_pos = position
		return

	if pointer == joystick_pointer:
		joystick_pointer = -1
		joystick_active = false
		joystick_vector = Vector2.ZERO
		_reset_joystick_tip()
	elif pointer == swipe_pointer:
		swipe_pointer = -1
		if swipe_active:
			_emit_swipe(position - swipe_start_pos)
		swipe_active = false


func _handle_pointer_motion(pointer: int, position: Vector2) -> void:
	if pointer == joystick_pointer and joystick_active:
		_update_joystick(position)


func _is_over_action_control(position: Vector2) -> bool:
	for control: Control in [jump_button, pause_button, emote_1, emote_2, emote_3, _primary_action_button]:
		if control.visible and control.get_global_rect().has_point(position):
			return true
	return false


func _emit_swipe(diff: Vector2) -> void:
	if diff.length() < SWIPE_THRESHOLD:
		return
	if absf(diff.x) > absf(diff.y):
		if diff.x > SWIPE_THRESHOLD:
			swipe_right.emit()
		elif diff.x < -SWIPE_THRESHOLD:
			swipe_left.emit()
	elif diff.y < -SWIPE_THRESHOLD:
		jump_triggered.emit()


func _update_joystick(touch_position: Vector2) -> void:
	var offset := touch_position - joystick_center
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	joystick_tip.position = joystick_base.size * 0.5 + offset - joystick_tip.size * 0.5
	var normalized := offset / joystick_radius
	if normalized.length() < JOYSTICK_DEADZONE:
		normalized = Vector2.ZERO
	joystick_vector = Vector2(-normalized.x, -normalized.y)


func _reset_joystick_tip() -> void:
	if joystick_base == null or joystick_tip == null:
		return
	joystick_tip.position = joystick_base.size * 0.5 - joystick_tip.size * 0.5


func _reset_pointer_state() -> void:
	joystick_active = false
	joystick_pointer = -1
	joystick_vector = Vector2.ZERO
	jump_active = false
	action_pointers.clear()
	swipe_active = false
	swipe_pointer = -1
	_reset_joystick_tip()


func _on_jump_down() -> void:
	jump_active = true
	jump_triggered.emit()


func _on_jump_up() -> void:
	jump_active = false


func _on_emote_pressed(slot_index: int) -> void:
	var state := QuizManager.game_state
	if state != null and state.p1_emote_slots.size() > slot_index:
		emote_triggered.emit(int(state.p1_emote_slots[slot_index]))


func get_joystick_axis() -> Vector2:
	return joystick_vector


func is_jump_pressed() -> bool:
	return jump_active


func get_debug_report() -> Dictionary:
	return {
		"available": true,
		"mobile_profile": _mobile_profile,
		"visible": visible,
		"gameplay_controls": joystick.visible,
		"cpu_badge": _cpu_badge.visible if _cpu_badge != null else false,
		"ghost_mode": _ghost_mode,
		"axis": joystick_vector,
		"jump": jump_active,
		"joystick_pointer": joystick_pointer,
	}
