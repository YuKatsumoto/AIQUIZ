extends RefCounted

## カスタマイズ「壁速度」タブのプレビューカメラ姿勢。
## load_settings() は DEFAULT_* を基準に、存在すれば user:// JSON で上書きする。

const SAVE_PATH := "user://customize_wall_speed_camera.json"

const DEFAULT_POS := Vector3(-5.2, 4.5, 16.0)
const DEFAULT_ROT_DEG := Vector3(-14.0, -18.0, 0.0)
const DEFAULT_FOV := 65.0
const DEFAULT_H_OFFSET := 0.65
const DEFAULT_V_OFFSET := 0.0


static func default_settings() -> Dictionary:
	return code_default_settings()


static func code_default_settings() -> Dictionary:
	return {
		"position": DEFAULT_POS,
		"rotation_degrees": DEFAULT_ROT_DEG,
		"fov": DEFAULT_FOV,
		"h_offset": DEFAULT_H_OFFSET,
		"v_offset": DEFAULT_V_OFFSET,
	}


static func apply_code_defaults_to_camera(camera: Camera3D) -> void:
	apply_to_camera(camera, code_default_settings())


static func load_settings() -> Dictionary:
	var defaults := default_settings()
	if not FileAccess.file_exists(SAVE_PATH):
		return defaults
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return defaults
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return defaults
	return _merge_settings(defaults, parsed)


static func save_settings(settings: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	return true


static func clear_saved_settings() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


static func read_from_camera(camera: Camera3D) -> Dictionary:
	if not camera:
		return default_settings()
	return {
		"position": camera.position,
		"rotation_degrees": camera.rotation_degrees,
		"fov": camera.fov,
		"h_offset": camera.h_offset,
		"v_offset": camera.v_offset,
	}


static func apply_to_camera(camera: Camera3D, settings: Dictionary) -> void:
	if not camera:
		return
	var merged := _merge_settings(default_settings(), settings)
	camera.position = merged["position"]
	camera.rotation_degrees = merged["rotation_degrees"]
	camera.fov = float(merged["fov"])
	camera.h_offset = float(merged["h_offset"])
	camera.v_offset = float(merged.get("v_offset", 0.0))


static func to_gdscript_constants(settings: Dictionary) -> String:
	var merged := _merge_settings(default_settings(), settings)
	var pos: Vector3 = merged["position"]
	var rot: Vector3 = merged["rotation_degrees"]
	return (
		"const WALL_SPEED_PREVIEW_CAM_POS := Vector3(%s, %s, %s)\n"
		% [_fmt(pos.x), _fmt(pos.y), _fmt(pos.z)]
		+ "const WALL_SPEED_PREVIEW_CAM_ROT_DEG := Vector3(%s, %s, %s)\n"
		% [_fmt(rot.x), _fmt(rot.y), _fmt(rot.z)]
		+ "const WALL_SPEED_PREVIEW_CAM_FOV := %s\n" % _fmt(merged["fov"])
		+ "const WALL_SPEED_PREVIEW_CAM_H_OFFSET := %s\n" % _fmt(merged["h_offset"])
		+ "const WALL_SPEED_PREVIEW_CAM_V_OFFSET := %s" % _fmt(merged.get("v_offset", 0.0))
	)


static func _merge_settings(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	if loaded.has("position") and loaded["position"] is Vector3:
		out["position"] = loaded["position"]
	elif loaded.has("position") and loaded["position"] is Array:
		var arr: Array = loaded["position"]
		if arr.size() >= 3:
			out["position"] = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if loaded.has("rotation_degrees") and loaded["rotation_degrees"] is Vector3:
		out["rotation_degrees"] = loaded["rotation_degrees"]
	elif loaded.has("rotation_degrees") and loaded["rotation_degrees"] is Array:
		var arr_r: Array = loaded["rotation_degrees"]
		if arr_r.size() >= 3:
			out["rotation_degrees"] = Vector3(float(arr_r[0]), float(arr_r[1]), float(arr_r[2]))
	if loaded.has("fov"):
		out["fov"] = float(loaded["fov"])
	if loaded.has("h_offset"):
		out["h_offset"] = float(loaded["h_offset"])
	if loaded.has("v_offset"):
		out["v_offset"] = float(loaded["v_offset"])
	return out


static func _fmt(value: Variant) -> String:
	if value is float or value is int:
		return str(snappedf(float(value), 0.001))
	return str(value)
