@tool
extends Control
class_name MenuCardboardBox

## Compact cardboard cargo plate used by the menu configuration conveyor.
## The value Label remains a normal authored child so selection text and
## accessibility stay unchanged while this node supplies the physical box.

const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const BOX_EDGE := Color("#54351f")
const BOX_DARK := Color("#714722")
const BOX_LIGHT := Color("#d6a363")
const TAPE := Color("#e8c88b")
const INK_DEFAULT := Color("#382719")

@export var category_text: String = "教科":
	set(value):
		category_text = value
		queue_redraw()
@export var box_color: Color = Color("#b97a3d"):
	set(value):
		box_color = value
		queue_redraw()
@export var ink_color: Color = INK_DEFAULT:
	set(value):
		ink_color = value
		_apply_label_style()
		queue_redraw()

var motion_energy: float = 0.0:
	set(value):
		motion_energy = clampf(value, 0.0, 1.0)
		queue_redraw()
var landing_flash: float = 0.0:
	set(value):
		landing_flash = clampf(value, 0.0, 1.0)
		queue_redraw()

var _shadow_style: StyleBoxFlat
var _body_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	_build_styles()
	_apply_label_style()
	queue_redraw()


func configure(category: String, tint: Color, ink: Color) -> void:
	category_text = category
	box_color = tint
	ink_color = ink
	_apply_label_style()
	queue_redraw()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _apply_label_style() -> void:
	var label: Label = _value_label()
	if label == null:
		return
	label.add_theme_font_override("font", FONT)
	label.add_theme_color_override("font_color", ink_color)
	label.add_theme_color_override("font_shadow_color", Color(0.16, 0.09, 0.035, 0.28))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_constant_override("outline_size", 0)
	label.offset_top = 5.0
	label.offset_bottom = 0.0


func _value_label() -> Label:
	for child: Node in get_children():
		if child is Label:
			return child as Label
	return null


func _build_styles() -> void:
	_shadow_style = StyleBoxFlat.new()
	_shadow_style.set_corner_radius_all(5)
	_body_style = StyleBoxFlat.new()
	_body_style.border_color = BOX_EDGE
	_body_style.set_border_width_all(2)
	_body_style.set_corner_radius_all(4)


func _draw() -> void:
	if size.x < 40.0 or size.y < 24.0:
		return
	if _shadow_style == null or _body_style == null:
		_build_styles()

	var lift: float = motion_energy
	var shadow_rect := Rect2(3.0, 4.0 + lift * 2.0, size.x - 6.0, size.y - 5.0)
	_shadow_style.bg_color = Color(0.06, 0.045, 0.03, 0.42 - lift * 0.10)
	draw_style_box(_shadow_style, shadow_rect)

	var box_rect := Rect2(2.0, 1.0, size.x - 4.0, size.y - 5.0)
	_body_style.bg_color = box_color.lightened(0.05 + landing_flash * 0.05)
	draw_style_box(_body_style, box_rect)

	# Pressed fibre and lower corrugation give the plate visible cardboard depth.
	draw_rect(
		Rect2(box_rect.position + Vector2(2.0, box_rect.size.y - 6.0), Vector2(box_rect.size.x - 4.0, 4.0)),
		box_color.darkened(0.24)
	)
	draw_line(
		Vector2(box_rect.position.x + 3.0, box_rect.position.y + 8.0),
		Vector2(box_rect.end.x - 3.0, box_rect.position.y + 8.0),
		Color(BOX_DARK, 0.54),
		1.0,
		true
	)
	draw_line(
		Vector2(box_rect.position.x + 3.0, box_rect.position.y + 9.5),
		Vector2(box_rect.end.x - 3.0, box_rect.position.y + 9.5),
		Color(BOX_LIGHT, 0.30),
		1.0,
		true
	)

	# Fold seams converge under the packing strip, like a closed shipping carton.
	var middle_x: float = box_rect.get_center().x
	draw_line(
		Vector2(box_rect.position.x + 5.0, box_rect.position.y + 2.0),
		Vector2(middle_x - 8.0, box_rect.position.y + 9.0),
		Color(BOX_DARK, 0.42),
		1.0,
		true
	)
	draw_line(
		Vector2(box_rect.end.x - 5.0, box_rect.position.y + 2.0),
		Vector2(middle_x + 8.0, box_rect.position.y + 9.0),
		Color(BOX_DARK, 0.42),
		1.0,
		true
	)
	draw_rect(
		Rect2(middle_x - 6.0, box_rect.position.y + 1.5, 12.0, 8.0),
		Color(TAPE, 0.64)
	)
	draw_line(
		Vector2(middle_x, box_rect.position.y + 2.0),
		Vector2(middle_x, box_rect.position.y + 9.0),
		Color("#a97b42"),
		1.0,
		true
	)

	# Small printed category mark and handling bars sell the parcel metaphor.
	draw_string(
		FONT,
		Vector2(box_rect.position.x + 8.0, box_rect.position.y + 8.0),
		category_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		34.0,
		8,
		Color(ink_color, 0.76)
	)
	var bars_x: float = box_rect.end.x - 27.0
	for index: int in range(6):
		var bar_width: float = 1.0 if index % 2 == 0 else 2.0
		var bar_height: float = 4.0 + float(index % 3)
		draw_rect(
			Rect2(bars_x + float(index) * 3.0, box_rect.position.y + 3.0, bar_width, bar_height),
			Color(INK_DEFAULT, 0.45)
		)

	# Reinforced corners and a brief landing highlight make motion readable.
	for corner_x: float in [box_rect.position.x + 4.0, box_rect.end.x - 4.0]:
		draw_line(
			Vector2(corner_x, box_rect.position.y + 3.0),
			Vector2(corner_x, box_rect.end.y - 4.0),
			Color(BOX_LIGHT, 0.25),
			1.0,
			true
		)
	if landing_flash > 0.001:
		var flash := Color("#ffd978", landing_flash * 0.72)
		draw_line(
			Vector2(box_rect.position.x + 7.0, box_rect.end.y - 1.0),
			Vector2(box_rect.end.x - 7.0, box_rect.end.y - 1.0),
			flash,
			2.0 + landing_flash,
			true
		)
