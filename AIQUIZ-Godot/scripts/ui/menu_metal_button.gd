@tool
extends Button
class_name MenuMetalButton

## Metal push plate styling, independent of menu layout and transitions.
@export var accent: Color = Color("#e6b844"):
	set(value):
		accent = value
		refresh_style()
@export var featured: bool = false:
	set(value):
		featured = value
		refresh_style()
@export var compact: bool = false:
	set(value):
		compact = value
		refresh_style()
@export var arrow_button: bool = false:
	set(value):
		arrow_button = value
		refresh_style()

var mechanical_pulse: float = 0.0:
	set(value):
		mechanical_pulse = clampf(value, 0.0, 1.0)
		queue_redraw()

const FACE := Color("#323e48")
const INK := Color("#f2f5f6")
const FRAME_DARK := Color("#151d23")
const FRAME_LIGHT := Color("#56636c")
const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")

var _press_tween: Tween


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override("font", FONT)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(_on_resized)
	_on_resized()
	refresh_style()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _style(face: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = face
	style.set_corner_radius_all(7)
	style.content_margin_left = 16.0 if arrow_button else (24.0 if compact else 32.0)
	style.content_margin_right = 10.0 if arrow_button else (16.0 if compact else 24.0)
	var vertical_margin: float = 4.0 if compact else 10.0
	style.content_margin_top = vertical_margin
	style.content_margin_bottom = vertical_margin
	if arrow_button:
		style.border_color = Color("#72838b")
		style.set_border_width_all(3)
		style.border_width_bottom = 5
		style.shadow_size = 0
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
	else:
		style.set_border_width_all(0)
		style.shadow_color = Color.TRANSPARENT
		style.shadow_size = 0
		style.shadow_offset = Vector2.ZERO
	return style


func refresh_style() -> void:
	if not is_inside_tree():
		return
	var face: Color = accent if featured else FACE
	add_theme_stylebox_override("normal", _style(face))
	add_theme_stylebox_override("hover", _style(face.lightened(0.10)))
	add_theme_stylebox_override("pressed", _style(face.darkened(0.10)))
	add_theme_stylebox_override("disabled", _style(face.darkened(0.18)))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = accent.lightened(0.15)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(9)
	focus.set_expand_margin_all(3.0)
	add_theme_stylebox_override("focus", focus)
	var text_color: Color = Color("#182129") if featured else INK
	for slot: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(slot, text_color)
	add_theme_color_override("font_disabled_color", Color("#8b969e"))
	queue_redraw()


func play_conveyor_press(direction: int) -> void:
	if not arrow_button or disabled:
		return
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	# Mounted controls stay flush with their rail while the belt moves.
	mechanical_pulse = 1.0 if direction != 0 else 0.0
	_press_tween = create_tween()
	_press_tween.tween_property(self, "mechanical_pulse", 0.0, 0.24)


func _draw() -> void:
	var active: bool = (
		not disabled
		and (has_focus() or is_hovered() or is_pressed() or mechanical_pulse > 0.01)
	)
	var lamp: Color = accent if active else accent.darkened(0.55)
	if arrow_button:
		var bolt_color: Color = FRAME_LIGHT.lightened(mechanical_pulse * 0.22)
		for bolt_position: Vector2 in [
			Vector2(7.0, 7.0),
			Vector2(size.x - 7.0, 7.0),
			Vector2(7.0, size.y - 8.0),
			Vector2(size.x - 7.0, size.y - 8.0),
		]:
			draw_circle(bolt_position, 2.5, FRAME_DARK)
			draw_circle(bolt_position, 1.15, bolt_color)
		draw_circle(Vector2(8.0, size.y * 0.5), 2.8, FRAME_DARK)
		draw_circle(Vector2(8.0, size.y * 0.5), 1.7, lamp)
		if active:
			draw_line(
				Vector2(11.0, size.y - 4.0),
				Vector2(size.x - 11.0, size.y - 4.0),
				Color(accent, 0.60 + mechanical_pulse * 0.40),
				1.5 + mechanical_pulse,
				true
			)
		return
	var lamp_x: float = 12.0 if compact else 16.0
	draw_circle(Vector2(lamp_x, size.y * 0.5), 3.5 if compact else 4.5, FRAME_DARK)
	draw_circle(Vector2(lamp_x, size.y * 0.5), 2.0 if compact else 2.8, lamp)
