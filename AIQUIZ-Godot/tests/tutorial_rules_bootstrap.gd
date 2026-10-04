extends SceneTree

## tests/tutorial_rules_runtime.gd をオートロードのあるツリーで動かす。
func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/tutorial_rules_runtime.gd").new())
