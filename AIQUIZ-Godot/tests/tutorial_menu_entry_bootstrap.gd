extends SceneTree

## メインメニューの『チュートリアル』から旧チュートリアルが始まるまでの通しテスト。本体は tests/tutorial_menu_entry_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/tutorial_menu_entry_bootstrap.gd
## 撮った画面は artifacts/tutorial_menu_entry/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/tutorial_menu_entry_runtime.gd").new())
