extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var path := "res://tests/shark_asset_runtime.gd" if "asset" in OS.get_cmdline_user_args() else "res://tests/shark_contact_runtime.gd"
	var probe := load(path) as Script
	if probe == null or not probe.can_instantiate():
		quit(1)
		return
	root.add_child(probe.new())
