extends RefCounted
func run(ctx: Variant) -> void:
	var gs: QuizGameState = QuizManager.game_state
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.llm_mode = "OFFLINE"
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	ctx.get_scene_root()._update_ui()
	ctx.get_scene_root()._go_to_game(true)
	for i: int in range(300):
		await ctx.wait(0.1)
		var scene: Node = ctx.get_scene_root()
		if scene != null and scene.name == "GameWorld" and gs.game_state == Constants.STATE_PLAYING and not SceneTransition.is_transitioning():
			scene.get_tree().paused = true
			ctx.log("Local two player ready", {"saw_visible":scene._saw_controller.visible,"clip":str(scene._saw_controller.spin_clip)})
			return
	ctx.log("Startup state", {"state":gs.game_state})
