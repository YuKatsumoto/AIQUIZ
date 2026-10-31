extends Control

## One on-screen button of the touch layer (TouchControls): round (jump, emotes) or a rounded
## rectangle (pause, スタート/OK, the sudden-death answers). It stays down while any finger that
## landed on it is still on the glass, so a held jump behaves like a held key; sliding off does not
## let go (a thumb drifting a little must not drop the jump).
##
## Each finger is tracked by its touch index: the viewport routes a finger's drag and lift to the
## control it first touched, so several buttons can be held at once. MOUSE_FILTER_STOP keeps the
## touch (and the mouse event Android emulates from the first finger) away from the GUI and the 3D
## picking underneath.

signal pressed_changed(down: bool)

## Finger id the desktop --mobile-preview gives the left mouse button.
const MOUSE_FINGER := 1000

var label := ""
## Small second line under the label (e.g. "エモート").
var caption := ""
var color := Color(1.0, 1.0, 1.0)
## "" or "pause" (two bars instead of text).
var icon := ""
var font: Font = null
var font_size := 28
## Round button: radius in canvas pixels. Ignored when box_size is set.
var radius := 40.0
## Rectangular button when non-zero.
var box_size := Vector2.ZERO
## The desktop preview has no touch screen: the left mouse button stands in for a finger.
var mouse_as_touch := false

var _fingers: Dictionary = {}
var _box_style: StyleBoxFlat = null


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE


func is_down() -> bool:
	return not _fingers.is_empty()


## Places a round button by its centre.
func place_round(center: Vector2, new_radius: float) -> void:
	box_size = Vector2.ZERO
	radius = new_radius
	size = Vector2.ONE * radius * 2.0
	position = center - Vector2(radius, radius)
	queue_redraw()


## Places a rectangular button by its centre.
func place_box(center: Vector2, new_size: Vector2) -> void:
	box_size = new_size
	size = new_size
	position = center - new_size * 0.5
	queue_redraw()


## Lets go as if every finger lifted (emits pressed_changed(false) once when it was down).
func force_release() -> void:
	if _fingers.is_empty():
		return
	_fingers.clear()
	queue_redraw()
	pressed_changed.emit(false)


## Forgets the fingers without emitting (the caller already released the keys).
func reset_silent() -> void:
	if _fingers.is_empty():
		return
	_fingers.clear()
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	if box_size != Vector2.ZERO:
		return Rect2(Vector2.ZERO, size).grow(6.0).has_point(point)
	# A little slack outside the circle: thumbs land off-centre.
	return point.distance_to(size * 0.5) <= radius * 1.15


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index)
		else:
			_release(touch.index)
		accept_event()
	elif event is InputEventScreenDrag:
		accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		# On a phone these are emulated from the first finger: the touch above already counted it.
		if mouse_as_touch and button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press(MOUSE_FINGER)
			else:
				_release(MOUSE_FINGER)
		accept_event()
	elif event is InputEventMouseMotion:
		accept_event()


func _press(finger: int) -> void:
	var was_down := is_down()
	_fingers[finger] = true
	if not was_down:
		queue_redraw()
		pressed_changed.emit(true)


func _release(finger: int) -> void:
	if not _fingers.has(finger):
		return
	_fingers.erase(finger)
	if _fingers.is_empty():
		queue_redraw()
		pressed_changed.emit(false)


func _draw() -> void:
	var down := is_down()
	var fill := Color(color, 0.42 if down else 0.2)
	var edge := Color(color, 0.95 if down else 0.7)
	var center := size * 0.5
	if box_size != Vector2.ZERO:
		if _box_style == null:
			_box_style = StyleBoxFlat.new()
			_box_style.set_corner_radius_all(18)
			_box_style.set_border_width_all(3)
			_box_style.anti_aliasing = true
		_box_style.bg_color = fill
		_box_style.border_color = edge
		draw_style_box(_box_style, Rect2(Vector2.ZERO, size))
	else:
		draw_circle(center, radius, fill)
		draw_arc(center, radius - 1.5, 0.0, TAU, 48, edge, 3.0, true)
	if icon == "pause":
		var bar := Vector2(size.x * 0.12, size.y * 0.4)
		var gap := size.x * 0.08
		var top := center.y - bar.y * 0.5
		draw_rect(Rect2(center.x - gap - bar.x, top, bar.x, bar.y), Color(1, 1, 1, 0.92))
		draw_rect(Rect2(center.x + gap, top, bar.x, bar.y), Color(1, 1, 1, 0.92))
		return
	if font == null or label.is_empty():
		return
	var caption_size := maxi(int(font_size * 0.5), 14)
	var text_center_y := center.y
	if not caption.is_empty():
		text_center_y -= caption_size * 0.45
	_draw_centered(label, font_size, text_center_y)
	if not caption.is_empty():
		_draw_centered(caption, caption_size, text_center_y + font_size * 0.55 + caption_size * 0.5)


func _draw_centered(text: String, text_size: int, center_y: float) -> void:
	var baseline := center_y + (font.get_ascent(text_size) - font.get_descent(text_size)) * 0.5
	var origin := Vector2(0.0, baseline)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, text_size, 6, Color(0, 0, 0, 0.7))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, text_size, Color(1, 1, 1, 0.95))
