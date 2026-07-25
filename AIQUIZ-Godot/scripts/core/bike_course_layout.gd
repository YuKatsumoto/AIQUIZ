extends RefCounted
class_name BikeCourseLayout

## Shared, versioned layout for the mama-chari course and both editors.

const VERSION: int = 2
const COURSE_LENGTH: float = 230.0
const ROAD_HALF_WIDTH: float = 8.0
const PROJECT_LAYOUT_PATH: String = "res://data/bike_course_layout.json"
const USER_LAYOUT_PATH: String = "user://bike_course_layout.json"
const GRID_X: float = 0.5
const GRID_Z: float = 1.0
const HEIGHT_GRID: float = 0.1
const MIN_HEIGHT: float = -4.0
const MAX_HEIGHT: float = 8.0
const MIN_Z: float = 8.0
const MAX_Z: float = 222.0
const MAX_HEIGHT_POINTS: int = 32
const SUPPORTED_TYPES: Array[String] = ["cone", "puddle", "bump", "barrier"]

static var _cached_layout: Dictionary = {}


static func type_label(type_id: String) -> String:
	match type_id:
		"cone":
			return "コーン"
		"puddle":
			return "水たまり"
		"bump":
			return "段差"
		"barrier":
			return "バリケード"
	return type_id


static func type_color(type_id: String) -> Color:
	match type_id:
		"cone":
			return Color(1.0, 0.36, 0.06)
		"puddle":
			return Color(0.12, 0.62, 0.96, 0.82)
		"bump":
			return Color(1.0, 0.82, 0.12)
		"barrier":
			return Color(1.0, 0.25, 0.18)
	return Color.WHITE


static func type_hazard(type_id: String) -> Dictionary:
	match type_id:
		"cone":
			return {"hx": 0.72, "hz": 0.72, "severity": 0.42}
		"puddle":
			return {"hx": 1.8, "hz": 1.05, "severity": 0.32}
		"bump":
			return {"hx": 7.5, "hz": 0.38, "severity": 0.54}
		"barrier":
			return {"hx": 2.0, "hz": 0.48, "severity": 0.78}
	return {"hx": 0.5, "hz": 0.5, "severity": 0.0}


static func default_height_points() -> Array[Dictionary]:
	return [
		{"z": 0.0, "height": 0.0},
		{"z": 185.0, "height": 0.0},
		{"z": 220.0, "height": 1.4},
		{"z": COURSE_LENGTH, "height": 0.0},
	]


static func default_layout() -> Dictionary:
	var gimmicks: Array[Dictionary] = []
	for index: int in range(9):
		gimmicks.append(_make_item(
			"cone_%02d" % index,
			"cone",
			-3.1 if index % 2 == 0 else 3.1,
			50.0 + index * 4.5
		))
	gimmicks.append(_make_item("puddle_00", "puddle", -3.8, 97.0))
	gimmicks.append(_make_item("puddle_01", "puddle", 3.2, 108.0))
	gimmicks.append(_make_item("puddle_02", "puddle", -1.0, 119.0))
	for index: int in range(3):
		gimmicks.append(_make_item("bump_%02d" % index, "bump", 0.0, 123.0 + index * 1.5))
	for index: int in range(5):
		gimmicks.append(_make_item("barrier_%02d" % index, "barrier", -4.0, 143.0 + index * 7.5))
	return {
		"version": VERSION,
		"course_length": COURSE_LENGTH,
		"grid_x": GRID_X,
		"grid_z": GRID_Z,
		"height_points": default_height_points(),
		"gimmicks": gimmicks,
	}


static func load_layout(force_reload: bool = false) -> Dictionary:
	if not force_reload and not _cached_layout.is_empty():
		return _cached_layout.duplicate(true)
	for path: String in [USER_LAYOUT_PATH, PROJECT_LAYOUT_PATH]:
		var loaded: Dictionary = _load_path(path)
		if not loaded.is_empty():
			_cached_layout = normalize_layout(loaded)
			return _cached_layout.duplicate(true)
	_cached_layout = default_layout()
	return _cached_layout.duplicate(true)


static func save_layout(layout: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize_layout(layout)
	var json_text: String = JSON.stringify(normalized, "	")
	var project_saved: bool = _write_path(PROJECT_LAYOUT_PATH, json_text)
	var user_saved: bool = _write_path(USER_LAYOUT_PATH, json_text)
	_cached_layout = normalized.duplicate(true)
	return {
		"success": project_saved or user_saved,
		"project_saved": project_saved,
		"user_saved": user_saved,
		"count": (normalized.get("gimmicks", []) as Array).size(),
		"height_point_count": (normalized.get("height_points", []) as Array).size(),
	}


static func normalize_layout(layout: Dictionary) -> Dictionary:
	var gimmicks: Array[Dictionary] = _normalize_gimmicks(layout.get("gimmicks", []) as Array)
	var height_points: Array[Dictionary] = _normalize_height_points(layout.get("height_points", []) as Array)
	return {
		"version": VERSION,
		"course_length": COURSE_LENGTH,
		"grid_x": GRID_X,
		"grid_z": GRID_Z,
		"height_points": height_points,
		"gimmicks": gimmicks,
	}


static func get_height(layout: Dictionary, relative_z: float) -> float:
	var points: Array = layout.get("height_points", [])
	if points.is_empty():
		points = default_height_points()
	var sample_z: float = clampf(relative_z, 0.0, COURSE_LENGTH)
	var first: Dictionary = points[0] as Dictionary
	if sample_z <= float(first.get("z", 0.0)):
		return float(first.get("height", 0.0))
	for index: int in range(points.size() - 1):
		var point_a: Dictionary = points[index] as Dictionary
		var point_b: Dictionary = points[index + 1] as Dictionary
		var z_a: float = float(point_a.get("z", 0.0))
		var z_b: float = float(point_b.get("z", COURSE_LENGTH))
		if sample_z <= z_b:
			var t: float = clampf((sample_z - z_a) / maxf(0.001, z_b - z_a), 0.0, 1.0)
			var eased: float = t * t * (3.0 - 2.0 * t)
			return lerpf(float(point_a.get("height", 0.0)), float(point_b.get("height", 0.0)), eased)
	var last: Dictionary = points[points.size() - 1] as Dictionary
	return float(last.get("height", 0.0))


static func get_pitch(layout: Dictionary, relative_z: float) -> float:
	var z_before: float = maxf(0.0, relative_z - 0.25)
	var z_after: float = minf(COURSE_LENGTH, relative_z + 0.25)
	if is_equal_approx(z_before, z_after):
		return 0.0
	var height_delta: float = get_height(layout, z_after) - get_height(layout, z_before)
	return -atan2(height_delta, z_after - z_before)


static func get_cached_height(relative_z: float) -> float:
	if _cached_layout.is_empty():
		load_layout()
	return get_height(_cached_layout, relative_z)


static func get_cached_pitch(relative_z: float) -> float:
	if _cached_layout.is_empty():
		load_layout()
	return get_pitch(_cached_layout, relative_z)


static func set_cached_layout(layout: Dictionary) -> void:
	_cached_layout = normalize_layout(layout)


static func make_height_point(z: float, height: float) -> Dictionary:
	return {
		"z": snappedf(clampf(z, 0.0, COURSE_LENGTH), GRID_Z),
		"height": snappedf(clampf(height, MIN_HEIGHT, MAX_HEIGHT), HEIGHT_GRID),
	}


static func _normalize_gimmicks(raw_items: Array) -> Array[Dictionary]:
	var gimmicks: Array[Dictionary] = []
	var used_ids: Dictionary = {}
	for raw: Variant in raw_items:
		if not raw is Dictionary:
			continue
		var source: Dictionary = raw as Dictionary
		var type_id: String = str(source.get("type", ""))
		if not SUPPORTED_TYPES.has(type_id):
			continue
		var fallback_id: String = "%s_%03d" % [type_id, gimmicks.size()]
		var item_id: String = str(source.get("id", fallback_id)).strip_edges()
		if item_id.is_empty() or used_ids.has(item_id):
			item_id = fallback_id
		used_ids[item_id] = true
		var x: float = snappedf(clampf(float(source.get("x", 0.0)), -ROAD_HALF_WIDTH + 0.5, ROAD_HALF_WIDTH - 0.5), GRID_X)
		if type_id == "bump":
			x = 0.0
		var z: float = snappedf(clampf(float(source.get("z", MIN_Z)), MIN_Z, MAX_Z), GRID_Z)
		var rotation_y: float = snappedf(
			wrapf(float(source.get("rotation_y", 0.0)), -180.0, 180.0),
			5.0
		)
		gimmicks.append(_make_item(item_id, type_id, x, z, rotation_y))
	return gimmicks


static func _normalize_height_points(raw_points: Array) -> Array[Dictionary]:
	var source_points: Array = raw_points
	if source_points.is_empty():
		source_points = default_height_points()
	var by_z: Dictionary = {}
	for raw: Variant in source_points:
		if not raw is Dictionary:
			continue
		var point: Dictionary = raw as Dictionary
		var normalized: Dictionary = make_height_point(
			float(point.get("z", 0.0)),
			float(point.get("height", 0.0))
		)
		by_z[float(normalized.get("z", 0.0))] = normalized
	by_z[0.0] = by_z.get(0.0, make_height_point(0.0, 0.0))
	by_z[COURSE_LENGTH] = by_z.get(COURSE_LENGTH, make_height_point(COURSE_LENGTH, 0.0))
	var points: Array[Dictionary] = []
	for value: Variant in by_z.values():
		if value is Dictionary:
			points.append(value as Dictionary)
	points.sort_custom(_sort_height_points)
	if points.size() > MAX_HEIGHT_POINTS:
		points.resize(MAX_HEIGHT_POINTS)
		if float(points[points.size() - 1].get("z", 0.0)) < COURSE_LENGTH:
			points[points.size() - 1] = make_height_point(COURSE_LENGTH, 0.0)
	return points


static func _sort_height_points(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("z", 0.0)) < float(b.get("z", 0.0))


static func _make_item(
	item_id: String,
	type_id: String,
	x: float,
	z: float,
	rotation_y: float = 0.0
) -> Dictionary:
	return {
		"id": item_id,
		"type": type_id,
		"x": x,
		"z": z,
		"rotation_y": rotation_y,
	}


static func _load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _write_path(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	return true
