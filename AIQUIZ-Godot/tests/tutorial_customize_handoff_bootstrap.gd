extends SceneTree

## 旧チュートリアルのあとのカスタマイズ紹介（いまのハテナの案内）の通しテスト。本体は tests/tutorial_customize_handoff_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/tutorial_customize_handoff_bootstrap.gd
## 撮った画面は artifacts/tutorial_customize_handoff/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/tutorial_customize_handoff_runtime.gd").new())
