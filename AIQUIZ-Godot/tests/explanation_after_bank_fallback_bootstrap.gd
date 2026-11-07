extends SceneTree

## Explanations are still requested after a mid-round bank fallback (tests/explanation_after_bank_fallback_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/explanation_after_bank_fallback_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/explanation_after_bank_fallback_unit.gd").new())
