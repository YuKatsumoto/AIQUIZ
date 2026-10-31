extends SceneTree

## 案内のハテナの、席へ戻る・席を離れる動き（PracticeSeatMoves）の見た目の確かめ。本体は tests/practice_seat_moves_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流す。
##   Godot --path . --script tests/practice_seat_moves_bootstrap.gd
## 撮った画面は artifacts/practice_seat_moves/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/practice_seat_moves_runtime.gd").new())
