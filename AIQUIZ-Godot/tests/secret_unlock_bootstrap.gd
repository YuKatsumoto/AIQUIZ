extends SceneTree

## autoload（QuizManager など）が揃ってから、シークレット解放の単体テストを読み込む。
## Run: Godot --headless --path . --script res://tests/secret_unlock_bootstrap.gd -- --fresh-profile

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/secret_unlock_unit.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
