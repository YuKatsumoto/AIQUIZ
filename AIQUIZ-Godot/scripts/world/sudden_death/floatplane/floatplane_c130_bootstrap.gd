extends SceneTree

## 水上機 C-130 の確かめ（floatplane_c130_probe.gd）を、自動読み込みができてから読む。
##   部品・マーカー・材質・関数・寸法（ヘッドレスでよい）：
##     ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/world/sudden_death/floatplane/floatplane_c130_bootstrap.gd
##   実画面（外・機内・操縦席）を撮る：
##     ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/floatplane/floatplane_c130_bootstrap.gd -- shots=assets/vehicles/floatplane_c130/source/previews

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://scripts/world/sudden_death/floatplane/floatplane_c130_probe.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
