extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var script := load("res://tests/sudden_death_audio_unit.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
