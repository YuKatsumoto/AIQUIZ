extends SceneTree

## スカイゲートの空の演出のデバッグの入口（オートロードが要る）：sky_fx_debug.gd を参照。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/sky_fx/sky_fx_debug_bootstrap.gd -- low
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/sky_fx/sky_fx_debug_bootstrap.gd -- low shots

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://scripts/world/sudden_death/sky_fx/sky_fx_debug.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
