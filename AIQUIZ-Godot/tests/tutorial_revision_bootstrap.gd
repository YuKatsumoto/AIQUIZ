extends SceneTree

## チュートリアルのメニュー側の受け入れ確認（tests/tutorial_revision_runtime.gd）を起動する。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_revision_bootstrap.gd --fixed-fps 60

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/tutorial_revision_runtime.gd").new())
