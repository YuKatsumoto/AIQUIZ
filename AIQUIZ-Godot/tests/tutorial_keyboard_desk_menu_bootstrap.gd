extends SceneTree

## 本物のメインメニューから、ローカル2Pのキーボード説明（3Dの机）を開いて撮る実機の確かめ。
## 本体は tests/tutorial_keyboard_desk_menu_runtime.gd（--script で読んだスクリプトは自動読み込みの名前が
## 見えないので、自動読み込みができてから読む）。ウィンドウありで流す。
##   Godot --path . --script res://tests/tutorial_keyboard_desk_menu_bootstrap.gd
## 撮った画面と数値は artifacts/tutorial_keyboard_desk/menu_*。


func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/tutorial_keyboard_desk_menu_runtime.gd").new())
