extends Control
class_name BikeCourseEditorCanvas

signal layout_changed
signal selection_changed(index: int, item: Dictionary)
signal status_message(text: String)

const LAYOUT_SCRIPT = preload("res://scripts/core/bike_course_layout.gd")
const PX_PER_X: float = 34.0
const PX_PER_Z: float = 7.0
const MAP_TOP: float = 42.0
const ROAD_WIDTH_PX: float = LAYOUT_SCRIPT.ROAD_HALF_WIDTH * 2.0 * PX_PER_X
const HIT_RADIUS: float = 20.0

var gimmicks: Array[Dictionary] = []
var selected_type: String = "cone"
var selected_index: int = -1
var _dragging: bool = false


func _ready() -> void:
	name = "CourseCanvas"
	custom_minimum_size = Vector2(780.0, LAYOUT_SCRIPT.COURSE_LENGTH * PX_PER_Z + 90.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func set_layout(layout: Dictionary) -> void:
	var normalized: Dictionary = LAYOUT_SCRIPT.normalize_layout(layout)
	gimmicks.clear()
	for item: Variant in normalized.get("gimmicks", []):
		if item is Dictionary:
			gimmicks.append((item as Dictionary).duplicate(true))
	selected_index = -1
	queue_redraw()
	selection_changed.emit(-1, {})
	layout_changed.emit()


func get_layout() -> Dictionary:
	return LAYOUT_SCRIPT.normalize_layout({
		"version": LAYOUT_SCRIPT.VERSION,
		"course_length": LAYOUT_SCRIPT.COURSE_LENGTH,
		"grid_x": LAYOUT_SCRIPT.GRID_X,
		"grid_z": LAYOUT_SCRIPT.GRID_Z,
		"gimmicks": gimmicks.duplicate(true),
	})


func set_selected_type(type_id: String) -> void:
	if LAYOUT_SCRIPT.SUPPORTED_TYPES.has(type_id):
		selected_type = type_id
		status_message.emit("配置モード: %s" % LAYOUT_SCRIPT.type_label(type_id))


func place_gimmick(type_id: String, x: float, z: float) -> int:
	if not LAYOUT_SCRIPT.SUPPORTED_TYPES.has(type_id):
		return -1
	var item_x: float = snappedf(clampf(x, -LAYOUT_SCRIPT.ROAD_HALF_WIDTH + 0.5, LAYOUT_SCRIPT.ROAD_HALF_WIDTH - 0.5), LAYOUT_SCRIPT.GRID_X)
	if type_id == "bump":
		item_x = 0.0
	var item_z: float = snappedf(clampf(z, LAYOUT_SCRIPT.MIN_Z, LAYOUT_SCRIPT.MAX_Z), LAYOUT_SCRIPT.GRID_Z)
	var item: Dictionary = {
		"id": _next_id(type_id),
		"type": type_id,
		"x": item_x,
		"z": item_z,
	}
	gimmicks.append(item)
	_select(gimmicks.size() - 1)
	queue_redraw()
	layout_changed.emit()
	status_message.emit("%sを X %.1f / Z %.1fm に配置" % [
		LAYOUT_SCRIPT.type_label(type_id),
		item_x,
		item_z,
	])
	return selected_index


func update_selected_position(x: float, z: float) -> void:
	if selected_index < 0 or selected_index >= gimmicks.size():
		return
	var item: Dictionary = gimmicks[selected_index]
	var type_id: String = str(item.get("type", "cone"))
	item.x = 0.0 if type_id == "bump" else snappedf(
		clampf(x, -LAYOUT_SCRIPT.ROAD_HALF_WIDTH + 0.5, LAYOUT_SCRIPT.ROAD_HALF_WIDTH - 0.5),
		LAYOUT_SCRIPT.GRID_X
	)
	item.z = snappedf(clampf(z, LAYOUT_SCRIPT.MIN_Z, LAYOUT_SCRIPT.MAX_Z), LAYOUT_SCRIPT.GRID_Z)
	gimmicks[selected_index] = item
	queue_redraw()
	layout_changed.emit()
	selection_changed.emit(selected_index, item.duplicate(true))


func delete_selected() -> void:
	if selected_index < 0 or selected_index >= gimmicks.size():
		status_message.emit("削除するギミックを選択してください")
		return
	var removed: Dictionary = gimmicks[selected_index]
	gimmicks.remove_at(selected_index)
	selected_index = -1
	queue_redraw()
	layout_changed.emit()
	selection_changed.emit(-1, {})
	status_message.emit("%sを削除" % LAYOUT_SCRIPT.type_label(str(removed.get("type", ""))))


func duplicate_selected() -> void:
	if selected_index < 0 or selected_index >= gimmicks.size():
		status_message.emit("複製するギミックを選択してください")
		return
	var source: Dictionary = gimmicks[selected_index]
	place_gimmick(
		str(source.get("type", "cone")),
		float(source.get("x", 0.0)) + LAYOUT_SCRIPT.GRID_X,
		float(source.get("z", 0.0)) + 3.0
	)


func clear_all() -> void:
	gimmicks.clear()
	selected_index = -1
	queue_redraw()
	layout_changed.emit()
	selection_changed.emit(-1, {})
	status_message.emit("全ギミックをクリアしました")


func get_selected_item() -> Dictionary:
	if selected_index < 0 or selected_index >= gimmicks.size():
		return {}
	return gimmicks[selected_index].duplicate(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				grab_focus()
				var hit_index: int = _find_gimmick(mouse_event.position)
				if hit_index >= 0:
					_select(hit_index)
					_dragging = true
				elif _is_on_road(mouse_event.position):
					var map_pos: Vector2 = _canvas_to_map(mouse_event.position)
					place_gimmick(selected_type, map_pos.x, map_pos.y)
					_dragging = true
				accept_event()
			else:
				_dragging = false
				accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var right_hit: int = _find_gimmick(mouse_event.position)
			if right_hit >= 0:
				_select(right_hit)
				status_message.emit("右クリック選択: Deleteキーまたは削除ボタン")
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var map_pos: Vector2 = _canvas_to_map(motion.position)
		update_selected_position(map_pos.x, map_pos.y)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_DELETE:
			delete_selected()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var center_x: float = size.x * 0.5
	var road_left: float = center_x - ROAD_WIDTH_PX * 0.5
	var road_right: float = center_x + ROAD_WIDTH_PX * 0.5
	var map_height: float = LAYOUT_SCRIPT.COURSE_LENGTH * PX_PER_Z

	draw_rect(Rect2(0.0, 0.0, size.x, size.y), Color(0.055, 0.075, 0.105))
	draw_rect(Rect2(road_left - 42.0, MAP_TOP, ROAD_WIDTH_PX + 84.0, map_height), Color(0.21, 0.24, 0.29))
	draw_rect(Rect2(road_left, MAP_TOP, ROAD_WIDTH_PX, map_height), Color(0.105, 0.125, 0.155))
	draw_line(Vector2(center_x, MAP_TOP), Vector2(center_x, MAP_TOP + map_height), Color(1.0, 0.82, 0.18, 0.8), 3.0)

	for z_meter: int in range(0, int(LAYOUT_SCRIPT.COURSE_LENGTH) + 1, 10):
		var y: float = MAP_TOP + float(z_meter) * PX_PER_Z
		draw_line(Vector2(road_left, y), Vector2(road_right, y), Color(0.35, 0.40, 0.48, 0.35), 1.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(road_right + 12.0, y + 5.0),
			"%dm" % z_meter,
			HORIZONTAL_ALIGNMENT_LEFT,
			70.0,
			14,
			Color(0.72, 0.78, 0.88)
		)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(road_left, 28.0),
		"START  0m",
		HORIZONTAL_ALIGNMENT_LEFT,
		160.0,
		18,
		Color(0.35, 0.95, 0.62)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(road_left, MAP_TOP + map_height + 30.0),
		"BIKE FINISH  230m",
		HORIZONTAL_ALIGNMENT_LEFT,
		240.0,
		18,
		Color(0.35, 0.95, 0.62)
	)

	for index: int in range(gimmicks.size()):
		_draw_gimmick(index, gimmicks[index])


func _draw_gimmick(index: int, item: Dictionary) -> void:
	var type_id: String = str(item.get("type", "cone"))
	var center: Vector2 = _map_to_canvas(float(item.get("x", 0.0)), float(item.get("z", 0.0)))
	var color: Color = LAYOUT_SCRIPT.type_color(type_id)
	match type_id:
		"cone":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0.0, -12.0),
				center + Vector2(-10.0, 10.0),
				center + Vector2(10.0, 10.0),
			]), color)
			draw_line(center + Vector2(-7.0, 2.0), center + Vector2(7.0, 2.0), Color.WHITE, 3.0)
		"puddle":
			draw_set_transform(center, 0.0, Vector2(1.7, 0.62))
			draw_circle(Vector2.ZERO, 14.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"bump":
			draw_rect(Rect2(center.x - ROAD_WIDTH_PX * 0.46, center.y - 5.0, ROAD_WIDTH_PX * 0.92, 10.0), color)
		"barrier":
			draw_rect(Rect2(center.x - 44.0, center.y - 8.0, 88.0, 16.0), color)
			draw_line(center + Vector2(-34.0, 0.0), center + Vector2(34.0, 0.0), Color.WHITE, 3.0)
	if index == selected_index:
		draw_arc(center, 25.0, 0.0, TAU, 32, Color(0.35, 1.0, 0.70), 4.0)


func _select(index: int) -> void:
	selected_index = index
	queue_redraw()
	if index >= 0 and index < gimmicks.size():
		selection_changed.emit(index, gimmicks[index].duplicate(true))


func _find_gimmick(point: Vector2) -> int:
	var best_index: int = -1
	var best_distance: float = HIT_RADIUS
	for index: int in range(gimmicks.size()):
		var item: Dictionary = gimmicks[index]
		var center: Vector2 = _map_to_canvas(float(item.get("x", 0.0)), float(item.get("z", 0.0)))
		var distance: float = center.distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _is_on_road(point: Vector2) -> bool:
	var center_x: float = size.x * 0.5
	var road_left: float = center_x - ROAD_WIDTH_PX * 0.5
	var road_right: float = center_x + ROAD_WIDTH_PX * 0.5
	return (
		point.x >= road_left
		and point.x <= road_right
		and point.y >= MAP_TOP + LAYOUT_SCRIPT.MIN_Z * PX_PER_Z
		and point.y <= MAP_TOP + LAYOUT_SCRIPT.MAX_Z * PX_PER_Z
	)


func _map_to_canvas(x: float, z: float) -> Vector2:
	return Vector2(size.x * 0.5 + x * PX_PER_X, MAP_TOP + z * PX_PER_Z)


func _canvas_to_map(point: Vector2) -> Vector2:
	return Vector2(
		(point.x - size.x * 0.5) / PX_PER_X,
		(point.y - MAP_TOP) / PX_PER_Z
	)


func _next_id(type_id: String) -> String:
	var serial: int = 1
	while true:
		var candidate: String = "%s_%03d" % [type_id, serial]
		var exists: bool = false
		for item: Dictionary in gimmicks:
			if str(item.get("id", "")) == candidate:
				exists = true
				break
		if not exists:
			return candidate
		serial += 1
	return ""
