extends SceneTree

## 刷新したチュートリアルの実ゲーム受け入れ確認（tests/tutorial_renewal_runtime.gd）を起動する。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=solo
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=duo

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/tutorial_renewal_runtime.gd").new())
