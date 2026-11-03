extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var gs: QuizGameState = root.get("game_state") as QuizGameState
	if gs == null:
		ctx.error("Game state was not found.")
		return
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_GOAL_RACE
	gs.p1_alive = false
	gs.p2_alive = false
	gs.p1_waiting_for_shark = false
	gs.p2_waiting_for_shark = false
	gs.game_over_timer = 0.001
	gs.player2_game_over_timer = 0.001
	await ctx.wait(0.1)
	var passed: bool = gs.game_state == Constants.STATE_GAME_OVER
	ctx.log("goal race all-dead transition after fix", {
		"passed": passed,
		"state": gs.game_state,
		"message": gs.message_text.left(120),
	})
	if not passed:
		ctx.error("All-dead goal race did not enter GAME_OVER.")
