extends SceneTree

## Loads a runtime test after the autoloads exist (scripts compiled by --script cannot see them).
##   -- runtime=res://tests/net/online_menu_runtime.gd   (default: net_match_runtime.gd)

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var path := "res://tests/net/net_match_runtime.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runtime="):
			path = arg.trim_prefix("runtime=")
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
