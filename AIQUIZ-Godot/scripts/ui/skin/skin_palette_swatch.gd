extends BaseButton
class_name SkinPaletteSwatch

## パレットの1色。今の色と同じなら白い輪とチェックを付ける。

var swatch_color: Color = Color.WHITE
var current: bool = false
var _hovered := false


func _init(p_color: Color = Color.WHITE, p_name: String = "") -> void:
	swatch_color = p_color
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(24, 24)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = p_name if not p_name.is_empty() else "この色にする"


func _ready() -> void:
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func set_current(value: bool) -> void:
	if current == value:
		return
	current = value
	queue_redraw()


func _set_hover(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var style := StyleBoxFlat.new()
	style.bg_color = swatch_color
	style.set_corner_radius_all(6)
	style.border_color = Color(1, 1, 1, 0.95) if (current or _hovered) else Color(0, 0, 0, 0.45)
	style.set_border_width_all(2 if (current or _hovered) else 1)
	draw_style_box(style, rect.grow(1.0) if _hovered else rect)
	if current:
		var ink := SkinUiStyle.ink_on(swatch_color)
		var c := rect.get_center()
		draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1.5, 4), c + Vector2(5, -4)]), ink, 2.2, true)
	if has_focus():
		SkinUiStyle.draw_focus_ring(self, rect, 8)
