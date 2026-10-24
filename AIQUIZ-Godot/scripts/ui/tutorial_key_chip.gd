extends Control
class_name TutorialKeyChip

## 2D のキーキャップ1個。3D のキーキャップ（res://scripts/world/tutorial_keycap_3d.gd）と
## 同じ色の決まりで描く。通常はアイボリー、押すキーはプレイヤーの色、達成は緑に✓。
## 幅はキー何個分か（units）で決め、Space のような横長のキーも実際の比率に近づける。

enum Look { IDLE, TARGET, DONE }

const GAP_RATIO := 0.12
const DEPTH_RATIO := 0.14
const POP_SECONDS := 0.32

var label_text: String = ""
var look: Look = Look.IDLE
var accent: Color = TutorialUiStyle.P1
var unit: float = 32.0
## キー何個分の幅か。0 以下なら文字の長さから決める。
var units: float = 0.0

var _pop: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_END
	set_process(false)


func setup(text: String, new_look: Look, new_accent: Color, new_unit: float = 32.0, new_units: float = 0.0) -> void:
	label_text = text
	look = new_look
	accent = new_accent
	unit = new_unit
	units = new_units
	update_minimum_size()
	queue_redraw()


## 達成した瞬間に一度だけ跳ねさせる。
func pop() -> void:
	_pop = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_pop = maxf(0.0, _pop - delta / POP_SECONDS)
	queue_redraw()
	if _pop <= 0.0:
		set_process(false)


func _get_minimum_size() -> Vector2:
	return Vector2(_face_width(), unit + unit * DEPTH_RATIO)


func _font_size() -> int:
	return int(round(unit * (0.42 if label_text.length() >= 3 else 0.5)))


func _face_width() -> float:
	if units > 0.0:
		return units * unit + maxf(0.0, units - 1.0) * unit * GAP_RATIO
	var font := TutorialUiStyle.FONT_BOLD
	var text_width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	return maxf(unit * 1.06, text_width + unit * 0.62)


func _draw() -> void:
	var width := _face_width()
	var depth := unit * DEPTH_RATIO
	var face_color := TutorialUiStyle.IVORY
	var side_color := TutorialUiStyle.IVORY_SIDE
	var ink := TutorialUiStyle.KEY_INK
	match look:
		Look.TARGET:
			face_color = accent
			side_color = accent.darkened(0.32)
			ink = accent.darkened(0.82)
		Look.DONE:
			face_color = TutorialUiStyle.DONE
			side_color = TutorialUiStyle.DONE.darkened(0.36)
			ink = Color("05301a")
	var lift := sin(_pop * PI) * unit * 0.12
	var radius := unit * 0.22
	var side := StyleBoxFlat.new()
	side.bg_color = side_color
	side.set_corner_radius_all(int(radius))
	side.anti_aliasing = true
	draw_style_box(side, Rect2(0.0, depth - lift, width, unit))
	var face := StyleBoxFlat.new()
	face.bg_color = face_color
	face.set_corner_radius_all(int(radius))
	face.anti_aliasing = true
	draw_style_box(face, Rect2(0.0, -lift, width, unit))
	var font := TutorialUiStyle.FONT_BOLD
	var font_size := _font_size()
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := -lift + unit * 0.5 + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2((width - text_size.x) * 0.5, baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	if look == Look.DONE:
		var badge_radius := unit * 0.28
		var center := Vector2(width - badge_radius * 0.35, -lift + badge_radius * 0.35)
		draw_circle(center, badge_radius + unit * 0.06, Color("12844f"))
		draw_circle(center, badge_radius, Color.WHITE)
		var s := badge_radius * 0.62
		draw_polyline(PackedVector2Array([
			center + Vector2(-s * 0.85, 0.0),
			center + Vector2(-s * 0.2, s * 0.62),
			center + Vector2(s * 0.95, -s * 0.66),
		]), Color("12844f"), maxf(1.6, unit * 0.075), true)
