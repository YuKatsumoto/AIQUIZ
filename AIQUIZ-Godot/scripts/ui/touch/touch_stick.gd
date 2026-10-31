extends Control

## Floating virtual stick of the touch layer (TouchControls). The control covers a whole zone of
## the screen; the stick appears where the thumb lands and follows it when it slides past the rim.
## The direction is quantised to 8 ways with per-axis hysteresis (press at 0.5, let go at 0.3 of
## the radius), so the keys it stands for go down and up once each instead of chattering — the
## push duel (local_push_duel.gd) reads every press and release with its time.
##
## Only one finger drives the stick; a second finger landing in the zone is swallowed.

## [param direction] is one of LEFT / RIGHT / UP / DOWN (screen directions).
signal direction_changed(direction: int, down: bool)

const LEFT := 0
const RIGHT := 1
const UP := 2
const DOWN := 3
const PRESS_THRESHOLD := 0.5
const RELEASE_THRESHOLD := 0.3
const MOUSE_FINGER := 1000

var radius := 100.0
var color := Color(1.0, 1.0, 1.0)
var font: Font = null
var font_size := 22
## Where the faint idle ring sits (local coordinates), so players know where to put the thumb.
var rest_center := Vector2.ZERO
var caption := "いどう"
var mouse_as_touch := false

var _finger := -1
var _origin := Vector2.ZERO
var _vector := Vector2.ZERO
var _held: Array[bool] = [false, false, false, false]


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE


func is_down() -> bool:
	return _finger != -1 or _held.has(true)


## Lets go of every direction (emits direction_changed(…, false) for each held one).
func force_release() -> void:
	_finger = -1
	_vector = Vector2.ZERO
	_apply(Vector2.ZERO)
	queue_redraw()


## Forgets the finger and the directions without emitting (the caller already released the keys).
func reset_silent() -> void:
	_finger = -1
	_vector = Vector2.ZERO
	_held = [false, false, false, false]
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin(touch.index, touch.position)
		else:
			_end(touch.index)
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _finger:
			_follow(drag.position)
		accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if mouse_as_touch and button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin(MOUSE_FINGER, button.position)
			else:
				_end(MOUSE_FINGER)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if mouse_as_touch and _finger == MOUSE_FINGER:
			_follow(motion.position)
		accept_event()


func _begin(finger: int, at: Vector2) -> void:
	if _finger != -1:
		return
	_finger = finger
	# Keep the ring on screen when the thumb lands right at the edge of the zone.
	var margin := radius * 0.6
	_origin = Vector2(
		clampf(at.x, margin, maxf(margin, size.x - margin)),
		clampf(at.y, margin, maxf(margin, size.y - margin))
	)
	_follow(at)


func _end(finger: int) -> void:
	if finger != _finger:
		return
	force_release()


func _follow(at: Vector2) -> void:
	var offset := at - _origin
	if offset.length() > radius:
		# The base trails the thumb, so turning back never needs a long way home.
		_origin += offset.normalized() * (offset.length() - radius)
		offset = at - _origin
	_vector = (offset / radius).limit_length(1.0)
	_apply(_vector)
	queue_redraw()


func _apply(vector: Vector2) -> void:
	# Screen y grows downwards: up is -y.
	var amounts: Array[float] = [-vector.x, vector.x, -vector.y, vector.y]
	for direction: int in range(4):
		var amount := amounts[direction]
		var held := _held[direction]
		var next := amount > PRESS_THRESHOLD if not held else amount > RELEASE_THRESHOLD
		if next != held:
			_held[direction] = next
			direction_changed.emit(direction, next)


func _draw() -> void:
	if _finger == -1:
		draw_circle(rest_center, radius, Color(color, 0.08))
		draw_arc(rest_center, radius - 1.5, 0.0, TAU, 48, Color(color, 0.35), 2.0, true)
		draw_circle(rest_center, radius * 0.42, Color(color, 0.14))
		if font != null and not caption.is_empty():
			var baseline := rest_center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			var origin := Vector2(rest_center.x - radius, baseline)
			draw_string_outline(font, origin, caption, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, 5, Color(0, 0, 0, 0.5))
			draw_string(font, origin, caption, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color(1, 1, 1, 0.7))
		return
	draw_circle(_origin, radius, Color(color, 0.16))
	draw_arc(_origin, radius - 1.5, 0.0, TAU, 48, Color(color, 0.75), 3.0, true)
	# Tick marks on the held directions.
	var marks: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for direction: int in range(4):
		if _held[direction]:
			draw_circle(_origin + marks[direction] * radius * 0.86, radius * 0.1, Color(color, 0.9))
	draw_circle(_origin + _vector * radius, radius * 0.42, Color(color, 0.5))
	draw_arc(_origin + _vector * radius, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.85), 2.0, true)
