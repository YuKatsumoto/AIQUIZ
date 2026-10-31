extends SceneTree

## 練習の CPU（PracticeCpu）と相手を選ぶカード（PracticePickCard）の実機テスト。本体は tests/practice_cpu_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/practice_cpu_bootstrap.gd
## 撮った画面は artifacts/practice_cpu/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/practice_cpu_runtime.gd").new())
