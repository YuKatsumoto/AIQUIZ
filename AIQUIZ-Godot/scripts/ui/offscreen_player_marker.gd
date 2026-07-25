extends Control
class_name OffscreenPlayerMarker

const MARKER_SIZE := Vector2(120.0, 120.0)
const CIRCLE_RADIUS := 29.0
const POINTER_LENGTH := 25.0
const POINTER_HALF_WIDTH := 13.0
const CIRCLE_DIRECTION_OFFSET := 9.0
const WARNING_BLINK_MIN_SPEED := 4.0
const WARNING_BLINK_MAX_SPEED := 14.0
const WARNING_MIN_ALPHA := 0.28
const WARNING_COLOR := Color(1.0, 0.08, 0.04, 1.0)

var _direction: Vector2 = Vector2.DOWN
var _accent_color: Color = Color(1.0, 0.48, 0.14)
var _label_text: String = "1P"
var _player_label: Label = null
var _warning_strength: float = 0.0
var _warning_time: float = 0.0


func _ready() -> void:
	if name.is_empty():
		name = "OffscreenPlayerMarker"
	size = MARKER_SIZE
	custom_minimum_size = MARKER_SIZE
	pivot_offset = MARKER_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	visible = false

	_player_label = Label.new()
	_player_label.name = "PlayerLabel"
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 27)
	_player_label.add_theme_color_override("font_color", Color(0.025, 0.035, 0.05))
	_player_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.72))
	_player_label.add_theme_constant_override("outline_size", 2)
	_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_label)
	_apply_label()
	_layout_label()
	queue_redraw()


func configure(label_text: String, accent_color: Color) -> void:
	_label_text = label_text
	_accent_color = accent_color
	_apply_label()
	queue_redraw()


func set_marker_state(
		marker_center: Vector2,
		target_direction: Vector2,
		target_scale: float,
		delta: float,
		warning_strength: float = 0.0) -> void:
	var was_visible: bool = visible
	_direction = (
		target_direction.normalized()
		if target_direction.length_squared() > 0.0001
		else Vector2.DOWN
	)
	_warning_strength = clampf(warning_strength, 0.0, 1.0)
	position = marker_center - MARKER_SIZE * 0.5
	var next_scale := Vector2.ONE * target_scale
	if was_visible:
		scale = scale.lerp(next_scale, clampf(delta * 12.0, 0.0, 1.0))
	else:
		scale = next_scale
	visible = true
	if _warning_strength > 0.0:
		var blink_speed: float = lerpf(
			WARNING_BLINK_MIN_SPEED,
			WARNING_BLINK_MAX_SPEED,
			_warning_strength
		)
		_warning_time = fmod(_warning_time + delta * blink_speed, TAU)
		var blink: float = 0.5 + 0.5 * sin(_warning_time)
		modulate.a = lerpf(1.0, lerpf(WARNING_MIN_ALPHA, 1.0, blink), _warning_strength)
	else:
		_warning_time = 0.0
		modulate.a = 1.0
	_layout_label()
	queue_redraw()


func hide_marker() -> void:
	visible = false
	modulate.a = 1.0
	_warning_strength = 0.0


func _apply_label() -> void:
	if _player_label != null:
		_player_label.text = _label_text


func _layout_label() -> void:
	if _player_label == null:
		return
	var circle_center := MARKER_SIZE * 0.5 - _direction * CIRCLE_DIRECTION_OFFSET
	_player_label.position = circle_center - Vector2(44.0, 21.0)
	_player_label.size = Vector2(88.0, 42.0)


func _draw() -> void:
	var center := MARKER_SIZE * 0.5
	var direction := (
		_direction.normalized()
		if _direction.length_squared() > 0.0001
		else Vector2.DOWN
	)
	var side := Vector2(-direction.y, direction.x)
	var circle_center := center - direction * CIRCLE_DIRECTION_OFFSET
	var pointer_base := circle_center + direction * (CIRCLE_RADIUS * 0.72)
	var pointer_tip := circle_center + direction * (CIRCLE_RADIUS + POINTER_LENGTH)
	var pointer_points := PackedVector2Array([
		pointer_base + side * POINTER_HALF_WIDTH,
		pointer_tip,
		pointer_base - side * POINTER_HALF_WIDTH,
	])
	var outline_width := 2.0
	var outer_pointer_base := circle_center + direction * (CIRCLE_RADIUS * 0.70)
	var outer_pointer_points := PackedVector2Array([
		outer_pointer_base + side * (POINTER_HALF_WIDTH + outline_width),
		pointer_tip + direction * outline_width,
		outer_pointer_base - side * (POINTER_HALF_WIDTH + outline_width),
	])
	var outline_color := Color(0.025, 0.035, 0.05, 0.92)
	# Treat warning strength as the opacity of a red overlay: the marker keeps its
	# player color at first and becomes progressively less transparent red.
	var marker_color: Color = _accent_color.lerp(WARNING_COLOR, _warning_strength)
	var pointer_color := marker_color * Color(0.90, 0.90, 0.90, 1.0)

	# Draw the larger silhouette first, then cover it with the colored union.
	# This leaves one thin black line only around the outside edge.
	draw_colored_polygon(outer_pointer_points, outline_color)
	draw_circle(circle_center, CIRCLE_RADIUS + outline_width, outline_color, true, -1.0, true)
	draw_colored_polygon(pointer_points, pointer_color)
	draw_circle(circle_center, CIRCLE_RADIUS, marker_color, true, -1.0, true)
