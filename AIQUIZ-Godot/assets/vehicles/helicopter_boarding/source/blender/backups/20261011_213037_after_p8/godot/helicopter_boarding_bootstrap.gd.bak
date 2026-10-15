extends SceneTree

## 乗り込めるヘリの実行時のチェック（tests/helicopter_boarding_runtime.gd）を、自動読み込みができてから読む
## （--script で直接読むと、OnlineHeliportHelicopter が使う GameManager などがまだなくてコンパイルできない）。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/helicopter_boarding_bootstrap.gd
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/helicopter_boarding_bootstrap.gd -- shots=assets/vehicles/helicopter_boarding/source/previews

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/helicopter_boarding_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
