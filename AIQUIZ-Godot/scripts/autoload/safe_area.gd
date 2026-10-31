extends Node

## Screen insets that UI must keep clear of, in canvas (logical) pixels.
##
## On Z Flip 7 held landscape the punch-hole camera sits mid-height on one short
## edge and the corners are rounded; Godot reports the former through
## DisplayServer.get_display_safe_area() but not the latter. A 180° turn keeps
## the window size, so size_changed never fires when the hole swaps sides:
## the insets are polled instead.
##
## Desktop always reports zero, so PC layouts stay put.
##
## Use: SafeArea.left / top / right / bottom, SafeArea.changed,
##      SafeArea.apply_to_margins(container) or SafeArea.rect().

signal changed

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

## Keeps HUD text off the rounded corners, which the safe area ignores.
const CORNER_MARGIN := 20.0
const POLL_INTERVAL_SEC := 0.5
## --mobile-preview fakes a camera hole on the left edge so layouts can be
## checked on desktop.
const PREVIEW_CUTOUT := 64.0

var left: float = 0.0
var top: float = 0.0
var right: float = 0.0
var bottom: float = 0.0

var _poll_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not QualityRules.is_mobile_target():
		set_process(false)
		return
	get_tree().root.size_changed.connect(refresh)
	refresh.call_deferred()


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_INTERVAL_SEC
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		refresh.call_deferred()


## The canvas rectangle that is free of cutouts and corners.
func rect() -> Rect2:
	var size := get_tree().root.get_visible_rect().size
	return Rect2(left, top, maxf(0.0, size.x - left - right), maxf(0.0, size.y - top - bottom))


## Adds the insets on top of a MarginContainer's own margins. Pass the margins
## the container should have on desktop; call again from `changed`.
func apply_to_margins(container: MarginContainer, base: float = 0.0) -> void:
	if container == null:
		return
	container.add_theme_constant_override("margin_left", int(base + left))
	container.add_theme_constant_override("margin_top", int(base + top))
	container.add_theme_constant_override("margin_right", int(base + right))
	container.add_theme_constant_override("margin_bottom", int(base + bottom))


func refresh() -> void:
	if not QualityRules.is_mobile_target():
		return
	var insets := _measure()
	if (
		is_equal_approx(insets[0], left) and is_equal_approx(insets[1], top)
		and is_equal_approx(insets[2], right) and is_equal_approx(insets[3], bottom)
	):
		return
	left = insets[0]
	top = insets[1]
	right = insets[2]
	bottom = insets[3]
	changed.emit()


func _measure() -> Array[float]:
	var window := get_tree().root
	var logical := window.get_visible_rect().size
	var physical := Vector2(DisplayServer.window_get_size())
	if logical.x <= 0.0 or physical.x <= 0.0:
		return [0.0, 0.0, 0.0, 0.0]
	var scale := physical / logical
	var cut := [0.0, 0.0, 0.0, 0.0]
	if QualityRules.is_mobile_preview() and not OS.has_feature("mobile"):
		cut[0] = PREVIEW_CUTOUT
	else:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var origin := Vector2(DisplayServer.window_get_position())
		if safe.size.x > 0.0 and safe.size.y > 0.0:
			safe.position -= origin
			cut[0] = maxf(0.0, safe.position.x) / scale.x
			cut[1] = maxf(0.0, safe.position.y) / scale.y
			cut[2] = maxf(0.0, physical.x - safe.end.x) / scale.x
			cut[3] = maxf(0.0, physical.y - safe.end.y) / scale.y
	var result: Array[float] = []
	for value: float in cut:
		result.append(maxf(value, CORNER_MARGIN))
	return result
