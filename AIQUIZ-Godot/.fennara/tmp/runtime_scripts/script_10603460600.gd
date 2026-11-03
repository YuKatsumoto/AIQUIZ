extends RefCounted
func run(ctx: Variant) -> void:
	ctx.log("Active project", {"path":ProjectSettings.globalize_path("res://"),"scene":str(ctx.get_scene_root().name)})
	await ctx.capture("menu_rails")
	var gs: QuizGameState = QuizManager.game_state
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.llm_mode = "OFFLINE"
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	ctx.get_scene_root()._update_ui()
	ctx.get_scene_root()._go_to_game(true)
	ctx.log("Starting local 2P through main menu")
