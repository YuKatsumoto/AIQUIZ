extends Node

## Loads every game script with the project's autoloads registered and reports
## the ones that fail to compile. Run headless:
##   Godot --headless --path . res://tests/android/script_load_check.tscn

const ROOTS := ["res://scripts", "res://ui", "res://scenes", "res://shaders", "res://assets"]


func _ready() -> void:
	var failed: Array[String] = []
	var count := 0
	for root: String in ROOTS:
		for path: String in _collect(root):
			count += 1
			var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res == null or (res is GDScript and not (res as GDScript).can_instantiate() and not (res as GDScript).is_abstract()):
				failed.append(path)
	print("SCRIPT_LOAD_CHECK checked=%d failed=%d" % [count, failed.size()])
	for path: String in failed:
		print("SCRIPT_LOAD_FAIL ", path)
	get_tree().quit(1 if failed.size() > 0 else 0)


func _collect(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".gdshader"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		if sub.begins_with(".") or FileAccess.file_exists(dir_path.path_join(sub).path_join(".gdignore")):
			continue
		out.append_array(_collect(dir_path.path_join(sub)))
	return out
