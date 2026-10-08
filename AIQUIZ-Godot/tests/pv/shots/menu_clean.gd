extends RefCounted

## PV shot: the live 3D title background of the main menu (the AI runners at the quiz walls,
## the harbour, the saw carriage with the mascot) with every piece of menu UI hidden, as the
## plate for the end card. Segment: menu_bg.

var kit  # tests/pv/pv_runtime.gd


func run(runner) -> void:
	kit = runner
	var gs := QuizManager.game_state
	gs.num_players = 2
	gs.menu_step = Constants.MENU_STEP_MODE
	kit.get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await kit.until(func() -> bool: return kit.menu() != null, 600)
	var menu = kit.menu()
	menu._update_ui()
	var preview = menu._menu_wall_preview
	if preview != null and preview.has_method("sync_menu_player_count"):
		preview.sync_menu_player_count(2)
	await kit.seconds(4.0)
	for child: Node in menu.get_children():
		if child is CanvasItem and str(child.name) != "LiveBackground":
			(child as CanvasItem).visible = false
	kit.hide_overlays(true)
	await kit.seconds(0.5)
	kit.record("menu_bg")
	await kit.seconds(14.0)
