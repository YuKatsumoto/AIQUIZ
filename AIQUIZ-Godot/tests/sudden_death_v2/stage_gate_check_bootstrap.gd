extends SceneTree

## 台座の横の水路の確かめ（オートロードが要る）：tests/sudden_death_v2/stage_gate_check.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	# 製品版ではサドンデスは切ってある（parachute.md、M6 まで）。テストは入口で有効にする。
	# 名前で呼ばずに読み込む（名前で呼ぶとオートロードより先に QuizGameState をコンパイルしてしまう）。
	(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
	var script := load("res://tests/sudden_death_v2/stage_gate_check.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
