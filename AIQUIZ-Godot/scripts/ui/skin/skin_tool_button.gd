extends BaseButton
class_name SkinToolButton

## アイコン＋文字ラベルのボタン（ツールバー・小さな操作）。
## アイコンは絵文字に頼らず線で描く（フォントに無い記号で豆腐にならないように）。

enum Icon { NONE, UNDO, RESET, DICE, COPY, CAMERA }

var icon_kind: Icon = Icon.NONE
var text: String = ""
var compact: bool = false
var _hovered := false


func _init(p_icon: Icon = Icon.NONE, p_text: String = "", p_tooltip: String = "", p_compact: bool = false) -> void:
	icon_kind = p_icon
	text = p_text
	compact = p_compact
	tooltip_text = p_tooltip
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(34, 34) if compact else Vector2(0, 42)


func _ready() -> void:
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func set_text(value: String) -> void:
	text = value
	update_minimum_size()
	queue_redraw()


## 文字が切れないよう、ラベルの長さから最小幅を決める。
func _get_minimum_size() -> Vector2:
	if compact or text.is_empty():
		return Vector2.ZERO
	var text_width := SkinUiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var icon_width := 0.0 if icon_kind == Icon.NONE else 30.0
	return Vector2(ceilf(text_width + icon_width + 16.0), 0.0)


func _set_hover(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENABLED or what == NOTIFICATION_DISABLED:
		mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	SkinUiStyle.draw_card(self, rect, _hovered and not disabled, button_pressed and toggle_mode, SkinUiStyle.GOLD, 10)
	var ink := SkinUiStyle.DIM if disabled else (SkinUiStyle.GOLD_SOFT if (button_pressed and toggle_mode) else SkinUiStyle.TEXT)
	if icon_kind == Icon.NONE:
		SkinUiStyle.draw_text_centered(self, rect, text, 14, ink, true)
	elif compact or text.is_empty():
		_draw_icon(rect.get_center(), 9.0, ink)
	else:
		var icon_center := Vector2(18.0, size.y * 0.5)
		_draw_icon(icon_center, 8.0, ink)
		SkinUiStyle.draw_text_centered(self, Rect2(30.0, 0, size.x - 34.0, size.y), text, 13, ink, true)
	if has_focus():
		SkinUiStyle.draw_focus_ring(self, rect)


func _draw_icon(c: Vector2, r: float, ink: Color) -> void:
	var w := 2.2
	match icon_kind:
		Icon.UNDO:
			# 上半分の弧（↶）。矢じりは左下向き。
			var center := c + Vector2(0, r * 0.35)
			var arc_radius := r * 0.85
			draw_arc(center, arc_radius, PI, TAU, 18, ink, w, true)
			var tip := center + Vector2(-arc_radius, 0.0)
			draw_colored_polygon(PackedVector2Array([
				tip + Vector2(-r * 0.45, -r * 0.05),
				tip + Vector2(r * 0.45, -r * 0.05),
				tip + Vector2(0.0, r * 0.55),
			]), ink)
		Icon.RESET:
			draw_arc(c, r * 0.85, deg_to_rad(-60), deg_to_rad(250), 20, ink, w, true)
			var tip := c + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * r * 0.85
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.55, -r * 0.1), tip + Vector2(r * 0.2, -r * 0.45), tip + Vector2(r * 0.15, r * 0.35)]), ink)
		Icon.DICE:
			var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
			var style := StyleBoxFlat.new()
			style.draw_center = false
			style.border_color = ink
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			draw_style_box(style, box)
			for offset: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, 0.45), Vector2.ZERO, Vector2(0.45, -0.45), Vector2(-0.45, 0.45)]:
				draw_circle(c + offset * r, 1.8, ink)
		Icon.COPY:
			var back := Rect2(c - Vector2(r, r) + Vector2(-2, -2), Vector2(r * 1.4, r * 1.6))
			var front := Rect2(c - Vector2(r * 0.4, r * 0.6) + Vector2(2, 2), Vector2(r * 1.4, r * 1.6))
			draw_rect(back, ink, false, w)
			draw_rect(front, Color(0.10, 0.12, 0.18), true)
			draw_rect(front, ink, false, w)
		Icon.CAMERA:
			draw_arc(c, r * 0.9, 0.0, TAU, 24, ink, w, true)
			draw_circle(c, r * 0.3, ink)
