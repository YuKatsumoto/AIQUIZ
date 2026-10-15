extends HSlider
class_name SkinColorSlider

## 色あい・あざやかさ・明るさのスライダー。溝そのものに色の変化を描き、
## 数値は出さずにつまみの色で今の値を見せる。値・ドラッグ・キー・ホイールは HSlider に任せる。

enum Mode { HUE, SATURATION, VALUE }

const CONTROL_HEIGHT := 26.0
const TRACK_HEIGHT := 12.0
const KNOB_DIAMETER := 20.0
const SEGMENTS := 24

var mode: Mode = Mode.HUE
## 溝を描くための今の色（HSV）。
var hue: float = 0.0
var saturation: float = 1.0
var brightness: float = 1.0
var _hovered := false


func _init(p_mode: Mode = Mode.HUE) -> void:
	mode = p_mode
	custom_minimum_size.y = CONTROL_HEIGHT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	scrollable = true
	min_value = 0.0
	max_value = 1.0
	step = 0.001


func _ready() -> void:
	_hide_native_visuals()
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func set_hsv(h: float, s: float, v: float) -> void:
	hue = h
	saturation = s
	brightness = v
	queue_redraw()


func _value_changed(_new_value: float) -> void:
	queue_redraw()


func _set_hover(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _hide_native_visuals() -> void:
	add_theme_stylebox_override(&"slider", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"grabber_area", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"grabber_area_highlight", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	var transparent := Gradient.new()
	transparent.set_color(0, Color.TRANSPARENT)
	transparent.set_color(1, Color.TRANSPARENT)
	var invisible := GradientTexture2D.new()
	invisible.width = int(KNOB_DIAMETER)
	invisible.height = int(KNOB_DIAMETER)
	invisible.gradient = transparent
	for icon_name: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		add_theme_icon_override(icon_name, invisible)


func _ratio() -> float:
	return clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)


func _color_at(t: float) -> Color:
	match mode:
		Mode.SATURATION:
			return Color.from_hsv(hue, t, maxf(brightness, 0.25))
		Mode.VALUE:
			return Color.from_hsv(hue, saturation, t)
	return Color.from_hsv(t, maxf(saturation, 0.75), maxf(brightness, 0.85))


func _draw() -> void:
	# HSlider の値⇔位置の対応（つまみ幅を除いた範囲）に合わせて描く。
	var half := KNOB_DIAMETER * 0.5
	var track := Rect2(half, (size.y - TRACK_HEIGHT) * 0.5, maxf(size.x - KNOB_DIAMETER, 1.0), TRACK_HEIGHT)
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.02, 0.03, 0.05, 0.9)
	outer.set_corner_radius_all(int(TRACK_HEIGHT * 0.5 + 2.0))
	draw_style_box(outer, track.grow(2.0))
	var radius := TRACK_HEIGHT * 0.5
	draw_circle(Vector2(track.position.x, track.get_center().y), radius, _color_at(0.0))
	draw_circle(Vector2(track.end.x, track.get_center().y), radius, _color_at(1.0))
	for index: int in range(SEGMENTS):
		var t0 := float(index) / SEGMENTS
		var t1 := float(index + 1) / SEGMENTS
		var x0 := track.position.x + track.size.x * t0
		var x1 := track.position.x + track.size.x * t1 + 0.5
		var c0 := _color_at(t0)
		var c1 := _color_at(t1)
		draw_polygon(
			PackedVector2Array([Vector2(x0, track.position.y), Vector2(x1, track.position.y), Vector2(x1, track.end.y), Vector2(x0, track.end.y)]),
			PackedColorArray([c0, c1, c1, c0]),
		)
	var knob_center := Vector2(track.position.x + track.size.x * _ratio(), size.y * 0.5)
	var knob_radius := half - (0.0 if (_hovered or has_focus()) else 1.0)
	draw_circle(knob_center, knob_radius + 1.5, Color(0, 0, 0, 0.55))
	draw_circle(knob_center, knob_radius, Color.WHITE)
	draw_circle(knob_center, knob_radius - 3.5, _color_at(_ratio()))
	if has_focus():
		draw_arc(knob_center, knob_radius + 4.0, 0.0, TAU, 32, SkinUiStyle.FOCUS, 2.0, true)
