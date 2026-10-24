extends SceneTree

## 「ひらけ！パラシュート」の絵コンテのコマを撮る（オートロードが要る）：tests/sudden_death_v2/parachute_storyboard.gd を参照。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/sudden_death_v2/parachute_storyboard.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
