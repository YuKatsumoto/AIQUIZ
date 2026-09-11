@tool
extends Control

## Simple rounded selection plate; its authored Label remains the value source.
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

@export var face_color: Color = Color("#212533"):
	set(value):
		face_color = value
		queue_redraw()
@export var border_color: Color = Color("#5b687b"):
	set(value):
		border_color = value
		queue_redraw()

var _body_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	apply_label_style()


func configure(face: Color, border: Color) -> void:
	face_color = face
	border_color = border
	apply_label_style()


func apply_label_style() -> void:
	for child: Node in get_children():
		if child is Label:
			var label: Label = child as Label
			label.add_theme_font_override("font", FONT)
			label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			label.add_theme_font_size_override("font_size", 22)
			label.add_theme_color_override("font_color", Color("#f4f7fa"))
			label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.05, 0.55))
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 2)
			label.add_theme_constant_override("outline_size", 0)
			label.add_theme_constant_override("shadow_outline_size", 0)


func _draw() -> void:
	if _body_style == null:
		_body_style = StyleBoxFlat.new()
		_body_style.set_border_width_all(2)
		_body_style.set_corner_radius_all(10)
	_body_style.bg_color = face_color
	_body_style.border_color = border_color
	draw_style_box(_body_style, Rect2(Vector2.ZERO, size))
	for bolt_position: Vector2 in [
		Vector2(8.0, 8.0),
		Vector2(size.x - 8.0, 8.0),
		Vector2(8.0, size.y - 8.0),
		Vector2(size.x - 8.0, size.y - 8.0),
	]:
		draw_circle(bolt_position, 2.8, Color("#151d23"))
		draw_circle(bolt_position, 1.7, Color("#87969e"))
		draw_line(bolt_position - Vector2(1.1, 0.0), bolt_position + Vector2(1.1, 0.0), Color("#33434d"), 1.0)
