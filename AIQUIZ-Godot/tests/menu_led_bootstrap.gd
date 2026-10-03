extends SceneTree

## Runs the main menu and checks the LED programme (tests/menu_led_runtime.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/menu_led_bootstrap.gd
## Options after "--": data=reel (show what tests/match_reel_bootstrap.gd recorded)

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/menu_led_runtime.gd").new())
