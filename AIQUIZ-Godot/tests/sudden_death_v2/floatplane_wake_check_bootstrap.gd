extends SceneTree

## 水上機の航跡だけの確かめ（オートロードが要る）：tests/sudden_death_v2/floatplane_wake_check.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/sudden_death_v2/floatplane_wake_check.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
