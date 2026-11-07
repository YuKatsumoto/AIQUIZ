extends SceneTree

## Clicking the result card's rating button (tests/result_rating_click_runtime.gd).
## Needs a window (GUI mouse input): Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/result_rating_click_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/result_rating_click_runtime.gd").new())
