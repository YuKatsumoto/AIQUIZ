extends SceneTree

## Plays a local 2P match through the finale and checks the highlight clips and the
## match record MatchReel stores (tests/match_reel_runtime.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/match_reel_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/match_reel_runtime.gd").new())
