extends SceneTree

## サドンデスへ行くときの幽霊の復活（オートロードが要る）：tests/sudden_death_v2/ghost_revive_runtime.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	# 製品版ではサドンデスは切ってある。テストは入口で有効にする（skygate_runtime_bootstrap.gd と同じ）。
	(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
	var script := load("res://tests/sudden_death_v2/ghost_revive_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
