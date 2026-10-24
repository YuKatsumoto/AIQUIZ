extends Node
## tests/menu_push_runtime.gd を単独で回す：メインメニューを開き、背景のプレビューが動き出したら足して run を呼ぶ。
## runtime は終わると finished を立ててメニューを読み直すので、それを待って終える。
var runner: Node = null


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.llm_mode = "OFFLINE"
	MenuGhostRideDirector.globally_enabled = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	for i in 1200:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.get("_menu_wall_preview"):
			var preview = scene._menu_wall_preview
			if preview._preview_saw and preview._preview_player and not SceneTransition.is_transitioning():
				break
	runner = load("res://tests/menu_push_runtime.gd").new()
	get_tree().root.add_child(runner)
	runner.call_deferred("run")
	for i in 3600:
		await get_tree().process_frame
		if bool(runner.get("finished")):
			break
	var checks: Dictionary = runner.get("checks")
	var passed := not checks.is_empty()
	for value in checks.values():
		passed = passed and bool(value)
	get_tree().quit(0 if passed else 1)
