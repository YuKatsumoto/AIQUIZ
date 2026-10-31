extends SceneTree

## メニューの上のレッスン（コース②の 2-6 とクリア）と画面のコーチの実機テスト。
## 本体は tests/practice_menu_coach_runtime.gd（--script で読んだスクリプトは自動読み込みの名前が見えないので、
## 自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/practice_menu_coach_bootstrap.gd
## コーチだけの小さな確かめ（ボタンを並べた画面で、光っている所だけ押せる）は
##   Godot --path . --script tests/practice_menu_coach_bootstrap.gd -- runtime=res://tests/practice_menu_coach_unit.gd
## 撮った画面は artifacts/practice_menu/。

const DEFAULT_RUNTIME := "res://tests/practice_menu_coach_runtime.gd"


func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var runtime := DEFAULT_RUNTIME
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("runtime="):
			runtime = arg.trim_prefix("runtime=")
	root.add_child(load(runtime).new())
