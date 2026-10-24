extends SceneTree

## 観客船・クラッカー・打ち上げ花火の実画面の確認（オートロードが要る）：tests/sudden_death_v2/flotilla_check.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/sudden_death_v2/flotilla_check.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
