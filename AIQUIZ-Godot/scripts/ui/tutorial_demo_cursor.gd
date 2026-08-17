extends Control
class_name TutorialDemoCursor

var _pressed_visual: bool = false
var _action_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220.0, 58.0)
	size = custom_minimum_size
	z_index = 220

	_action_label = Label.new()
	_action_label.position = Vector2(28.0, 8.0)
	_action_label.custom_minimum_size = Vector2(164.0, 32.0)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_label.add_theme_font_size_override("font_size", 14)
	_action_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72))
	var label_style := StyleBoxFlat.new()
	label_style.bg_color = Color(0.025, 0.055, 0.11, 0.96)
	label_style.border_color = Color(1.0, 0.78, 0.20, 0.95)
	label_style.set_border_width_all(2)
	label_style.set_corner_radius_all(9)
	label_style.content_margin_left = 10.0
	label_style.content_margin_right = 10.0
	_action_label.add_theme_stylebox_override("normal", label_style)
	_action_label.visible = false
	add_child(_action_label)
	queue_redraw()


func show_action(text: String, anchor_global_position: Variant = null) -> void:
	_action_label.text = text
	_action_label.visible = not text.is_empty()
	if _action_label.visible:
		var anchor_position: Vector2 = global_position
		if anchor_global_position is Vector2:
			anchor_position = anchor_global_position
		var viewport_width := get_viewport_rect().size.x
		var label_width := maxf(_action_label.size.x, _action_label.custom_minimum_size.x)
		var desired_offset_x := (
			-192.0 if anchor_position.x > viewport_width - 235.0 else 28.0
		)
		var label_global_x := clampf(
			anchor_position.x + desired_offset_x,
			8.0,
			maxf(8.0, viewport_width - label_width - 8.0),
		)
		_action_label.position = Vector2(label_global_x - anchor_position.x, 8.0)


func set_pressed_visual(pressed: bool) -> void:
	_pressed_visual = pressed
	queue_redraw()


func _draw() -> void:
	var shadow := PackedVector2Array([
		Vector2(3, 3), Vector2(7, 32), Vector2(14, 25), Vector2(21, 41),
		Vector2(29, 37), Vector2(22, 22), Vector2(34, 21),
	])
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.58))

	var cursor := PackedVector2Array([
		Vector2(0, 0), Vector2(4, 29), Vector2(11, 22), Vector2(18, 38),
		Vector2(26, 34), Vector2(19, 19), Vector2(31, 18),
	])
	draw_colored_polygon(cursor, Color(0.98, 0.99, 1.0))
	var outline := PackedVector2Array(cursor)
	outline.append(cursor[0])
	draw_polyline(outline, Color(0.02, 0.04, 0.08), 2.5, true)
	if _pressed_visual:
		draw_circle(Vector2(1.5, 1.5), 17.0, Color(1.0, 0.76, 0.16, 0.22))
		draw_arc(Vector2(1.5, 1.5), 17.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.28, 0.95), 2.5, true)
