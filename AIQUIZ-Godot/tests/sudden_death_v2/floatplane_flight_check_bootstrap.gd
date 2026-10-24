extends SceneTree

## 水上機の離着水の確かめ（オートロードが要る）：tests/sudden_death_v2/floatplane_flight_check.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	# 製品版ではサドンデスは切ってある。テストは入口で有効にする。
	(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
	var script := load("res://tests/sudden_death_v2/floatplane_flight_check.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
