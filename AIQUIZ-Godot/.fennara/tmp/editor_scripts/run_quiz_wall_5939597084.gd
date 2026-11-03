@tool
extends RefCounted
func run(ctx) -> void:
	var path: String = "res://scripts/core/game_state.gd"
	var disk: String = FileAccess.get_file_as_string(path)
	var script: GDScript = load(path)
	ctx.log({"absolute": ProjectSettings.globalize_path(path), "disk_has_boundary": disk.contains("func get_floor_front_z"), "cached_has_boundary": script.source_code.contains("func get_floor_front_z"), "disk_length": disk.length(), "cached_length": script.source_code.length()})