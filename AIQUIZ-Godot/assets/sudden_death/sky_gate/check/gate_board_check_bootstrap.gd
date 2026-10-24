extends SceneTree

## スカイゲートのボードの確認（オートロードが要る）：gate_board_check.gd を参照。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://assets/sudden_death/sky_gate/check/gate_board_check_bootstrap.gd -- low

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://assets/sudden_death/sky_gate/check/gate_board_check.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
