extends RefCounted
func run(ctx: Variant) -> void:
	await load("res://tests/saw_chase_modes_runtime.gd").new().verify(ctx, Constants.MODE_TUTORIAL, 2)
	ctx.get_scene_root().get_tree().paused = false
	QuizManager.game_state.reset_to_menu()
	ctx.get_scene_root().get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await ctx.wait(3.0)
	ctx.log("Returned to menu for preview validation")
