@tool
extends PanelContainer
class_name MenuConfigConveyor

## Three selector lanes share one metal housing. Plates and belt ribs use the
## same pixel displacement, so they accelerate, travel and stop together.
signal motion_started(row_key: StringName, direction: int)
signal motion_finished(row_key: StringName, direction: int)

const ValuePlate = preload("res://scripts/ui/menu_config_value.gd")
const ROW_KEYS: Array[StringName] = [&"subject", &"grade", &"difficulty"]
const BELT_SPACING: float = 18.0
const BELT_RIB_WIDTH: float = 2.0
const PLATE_GAP: float = 16.0

@export_range(0.15, 0.90, 0.01) var motion_duration: float = 0.28

var _busy: bool = false
var _labels: Dictionary = {}
var _rows: Dictionary = {}
var _slots: Dictionary = {}
var _lanes: Dictionary = {}
var _belt_phases: Dictionary = {&"subject": 0.0, &"grade": 0.0, &"difficulty": 0.0}
var _arrows: Array[Button] = []
var _saved_arrow_mouse_filters: Dictionary = {}
var _saved_arrow_focus_modes: Dictionary = {}
var _frame_style: StyleBoxFlat
var _belt_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_build_styles()
	_bind_controls()
	resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)
	queue_redraw()


func is_moving() -> bool:
	return _busy


func request_shift(row_key: StringName, direction: int, commit: Callable) -> bool:
	if _busy or direction == 0 or not commit.is_valid():
		return false
	var slot: Control = _slots.get(row_key) as Control
	var lane: Control = _lanes.get(row_key) as Control
	if not is_instance_valid(slot) or not is_instance_valid(lane):
		commit.call()
		return true
	_busy = true
	var travel_direction: int = signi(direction)
	_set_arrow_interaction_locked(true)
	_play_arrow_response(row_key, travel_direction)
	motion_started.emit(row_key, travel_direction)
	_run_shift(slot, lane, row_key, travel_direction, commit)
	return true


func _run_shift(slot: Control, lane: Control, row_key: StringName, direction: int, commit: Callable) -> void:
	# Keep the authored slot in place. Only passive copies ride through its window.
	var outgoing: Control = _duplicate_plate(slot, lane, "Departing")
	var origin: Vector2 = slot.position
	slot.visible = false
	commit.call()
	var incoming: Control = _duplicate_plate(slot, lane, "Arriving")
	# Whole rib intervals make every stopped lane line up with its neighbors.
	var pitch: float = ceilf((lane.size.x + PLATE_GAP) / BELT_SPACING) * BELT_SPACING
	incoming.position = origin + Vector2(float(direction) * pitch, 0.0)
	var entries: Array[Dictionary] = [
		{"key": row_key, "plate": outgoing, "origin": origin},
		{"key": row_key, "plate": incoming, "origin": incoming.position},
	]
	var phase_start: float = float(_belt_phases[row_key])
	await _transport(entries, phase_start, -float(direction) * pitch, motion_duration)
	outgoing.queue_free()
	incoming.queue_free()
	slot.visible = true
	_finish_motion(row_key, direction)


func _transport(entries: Array[Dictionary], phase_start: float, distance: float, duration: float) -> void:
	# One driver owns the complete motion. No independent label tween, overshoot,
	# rotation, scale, lift or fade can make a plate slip against the belt.
	var transport: Tween = create_tween()
	transport.tween_method(
		_apply_transport.bind(entries, phase_start), 0.0, distance, duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await transport.finished


func _apply_transport(displacement: float, entries: Array[Dictionary], phase_start: float) -> void:
	var row_key: StringName = entries[0]["key"]
	_belt_phases[row_key] = phase_start + displacement
	for entry: Dictionary in entries:
		var plate: Control = entry["plate"] as Control
		if is_instance_valid(plate):
			plate.position = (entry["origin"] as Vector2) + Vector2(displacement, 0.0)
	queue_redraw()


func _duplicate_plate(source: Control, lane: Control, prefix: String) -> Control:
	var plate: Control = source.duplicate() as Control
	plate.name = "%s%s" % [prefix, source.name]
	_make_clone_passive(plate)
	lane.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	plate.position = source.position
	plate.size = source.size
	plate.visible = true
	return plate


func _finish_motion(row_key: StringName, direction: int) -> void:
	_busy = false
	_set_arrow_interaction_locked(false)
	motion_finished.emit(row_key, direction)


func _bind_controls() -> void:
	_labels = {
		&"subject": get_node_or_null("%CurrentSubjectLabel"),
		&"grade": get_node_or_null("%CurrentGradeLabel"),
		&"difficulty": get_node_or_null("%CurrentDiffLabel"),
	}
	_rows = {
		&"subject": get_node_or_null("%SubjectCarousel"),
		&"grade": get_node_or_null("%GradeCarousel"),
		&"difficulty": get_node_or_null("%DiffCarousel"),
	}
	_slots = {
		&"subject": get_node_or_null("%SubjectValueSlot"),
		&"grade": get_node_or_null("%GradeValueSlot"),
		&"difficulty": get_node_or_null("%DifficultyValueSlot"),
	}
	for row_key: StringName in ROW_KEYS:
		var slot: Control = _slots.get(row_key) as Control
		if slot != null:
			_lanes[row_key] = slot.get_parent()
			_watch_lane_layout(slot.get_parent() as Control)
	_arrows.clear()
	for node_name: String in [
		"%PrevSubjectBtn", "%NextSubjectBtn", "%PrevGradeBtn",
		"%NextGradeBtn", "%PrevDiffBtn", "%NextDiffBtn",
	]:
		var button: Button = get_node_or_null(node_name) as Button
		if button != null:
			_arrows.append(button)
	refresh_value_style()


func _watch_lane_layout(lane: Control) -> void:
	# Containers can move descendants without resizing this panel or its plates.
	# Redraw on position changes throughout the layout chain, including reopening.
	var item: CanvasItem = lane
	while item != null and item != self:
		if not item.item_rect_changed.is_connected(queue_redraw):
			item.item_rect_changed.connect(queue_redraw)
		item = item.get_parent() as CanvasItem


func _lane_rect(lane: Control) -> Rect2:
	# Accumulate local transforms so the menu's entrance motion cannot offset
	# cached belt geometry, and scaled parents do not distort the calculation.
	var local_transform: Transform2D = lane.get_transform()
	var ancestor: CanvasItem = lane.get_parent() as CanvasItem
	while ancestor != null and ancestor != self:
		local_transform = ancestor.get_transform() * local_transform
		ancestor = ancestor.get_parent() as CanvasItem
	return local_transform * Rect2(Vector2.ZERO, lane.size)


func refresh_value_style() -> void:
	for row_key: StringName in ROW_KEYS:
		var label: Label = _labels.get(row_key) as Label
		var plate: Control = _slots.get(row_key) as Control
		if label == null or not plate is ValuePlate:
			continue
		var face: Color = Color("#212533")
		var border: Color = Color("#5b687b")
		if row_key == &"subject":
			var colors: Dictionary = {
				"算数": Color("#24529a"),
				"理科": Color("#257343"),
				"国語": Color("#a33545"),
				"社会": Color("#8b641f"),
				"英語": Color("#674195"),
			}
			face = colors.get(label.text, colors["算数"]) as Color
			border = face.lightened(0.30)
		(plate as ValuePlate).configure(face, border)


func _play_arrow_response(row_key: StringName, direction: int) -> void:
	var names: Dictionary = {&"subject": "Subject", &"grade": "Grade", &"difficulty": "Diff"}
	var side: String = "Next" if direction > 0 else "Prev"
	var button: Button = get_node_or_null("%%%s%sBtn" % [side, names[row_key]]) as Button
	if button != null and button.has_method("play_conveyor_press"):
		button.call("play_conveyor_press", direction)


func _set_arrow_interaction_locked(locked: bool) -> void:
	if locked:
		_saved_arrow_mouse_filters.clear()
		_saved_arrow_focus_modes.clear()
		for button: Button in _arrows:
			if is_instance_valid(button):
				_saved_arrow_mouse_filters[button] = button.mouse_filter
				_saved_arrow_focus_modes[button] = button.focus_mode
				button.release_focus()
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.focus_mode = Control.FOCUS_NONE
		return
	for button: Button in _arrows:
		if is_instance_valid(button):
			button.mouse_filter = int(
				_saved_arrow_mouse_filters.get(button, Control.MOUSE_FILTER_STOP)
			) as Control.MouseFilter
			button.focus_mode = int(
				_saved_arrow_focus_modes.get(button, Control.FOCUS_ALL)
			) as Control.FocusMode
	_saved_arrow_mouse_filters.clear()
	_saved_arrow_focus_modes.clear()


func _make_clone_passive(node: Node) -> void:
	node.unique_name_in_owner = false
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children():
		_make_clone_passive(child)


func _build_styles() -> void:
	_frame_style = StyleBoxFlat.new()
	_frame_style.bg_color = Color("#72838b")
	_frame_style.border_color = Color("#53666f")
	_frame_style.set_border_width_all(2)
	_frame_style.set_corner_radius_all(9)
	_frame_style.shadow_color = Color(0.03, 0.05, 0.07, 0.25)
	_frame_style.shadow_size = 2
	_frame_style.shadow_offset = Vector2(0.0, 2.0)
	_belt_style = StyleBoxFlat.new()
	_belt_style.bg_color = Color("#293540")
	_belt_style.set_corner_radius_all(4)


func _draw() -> void:
	if _frame_style == null or _belt_style == null:
		_build_styles()
	draw_style_box(_frame_style, Rect2(Vector2.ZERO, size))
	var lane_rects: Array[Rect2] = []
	for row_key: StringName in ROW_KEYS:
		var lane: Control = _lanes.get(row_key) as Control
		if not is_instance_valid(lane):
			return
		var rect: Rect2 = _lane_rect(lane)
		if not Rect2(Vector2.ZERO, size).encloses(rect) or not rect.has_area():
			return
		if not lane_rects.is_empty() and rect.position.y < lane_rects[-1].end.y:
			return
		lane_rects.append(rect)
	for index: int in range(ROW_KEYS.size()):
		var belt: Rect2 = lane_rects[index]
		draw_style_box(_belt_style, belt)
		var surface: Rect2 = belt.grow(-2.0)
		var phase: float = fposmod(float(_belt_phases[ROW_KEYS[index]]), BELT_SPACING)
		var rib_x: float = surface.position.x + phase
		while rib_x < surface.end.x:
			draw_line(Vector2(roundf(rib_x), surface.position.y),
				Vector2(roundf(rib_x), surface.end.y), Color("#526571"), 1.0)
			rib_x += BELT_SPACING
		draw_line(Vector2(belt.position.x + 3.0, belt.position.y + 1.0),
			Vector2(belt.end.x - 3.0, belt.position.y + 1.0), Color("#17222b"), 2.0)
		draw_line(Vector2(belt.position.x + 3.0, belt.end.y - 1.0),
			Vector2(belt.end.x - 3.0, belt.end.y - 1.0), Color("#91a1a7"), 1.0)
		if index == ROW_KEYS.size() - 1:
			continue
		var divider_y: float = roundf((belt.end.y + lane_rects[index + 1].position.y) * 0.5)
		# One shallow metal seam across the housing separates each control row.
		draw_line(Vector2(10.0, divider_y), Vector2(size.x - 10.0, divider_y),
			Color("#40545e"), 2.0)
		draw_line(Vector2(10.0, divider_y + 2.0), Vector2(size.x - 10.0, divider_y + 2.0),
			Color("#9aabb2"), 1.0)
		for bolt_x: float in [10.0, size.x - 10.0]:
			draw_circle(Vector2(bolt_x, divider_y + 0.5), 2.5, Color("#354751"))
			draw_line(Vector2(bolt_x - 1.0, divider_y), Vector2(bolt_x + 1.0, divider_y),
				Color("#b1c0c6"), 1.0)
