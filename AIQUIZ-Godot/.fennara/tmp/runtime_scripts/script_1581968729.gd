extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	root.set_process(false)
	var gs: QuizGameState = root.get("game_state") as QuizGameState
	var event_count: Array[int] = [0]
	var on_ocean: Callable = func(_player_index: int, _local_position: Vector3) -> void:
		event_count[0] += 1
	gs.player_entered_ocean.connect(on_ocean)

	gs.mode = Constants.MODE_TEN
	gs.num_players = 2
	gs.game_state = Constants.STATE_PLAYING
	gs.p1_alive = true
	gs.p2_alive = true
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 1.0
	gs.player_y = StageConstants.OCEAN_ENTRY_Y - 0.1
	gs.player_z = 0.0
	gs.player2_x = 0.0
	gs.player2_y = 0.0
	gs.player2_z = 0.0
	gs.world_scroll_z = 0.0
	gs.game_over_timer = 0.0
	gs.player2_game_over_timer = 0.0
	gs.update(0.016)
	var two_player_ok: bool = not gs.p1_alive and gs.p2_alive and gs.game_state == Constants.STATE_PLAYING and event_count[0] == 1

	gs.mode = Constants.MODE_TUTORIAL
	gs.num_players = 1
	gs.game_state = Constants.STATE_PLAYING
	gs.p1_alive = true
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 1.0
	gs.player_y = StageConstants.OCEAN_ENTRY_Y - 0.1
	gs.player_z = 0.0
	gs.game_over_timer = 0.0
	var before_tutorial_events: int = event_count[0]
	gs.update(0.016)
	var tutorial_ok: bool = gs.p1_alive and is_zero_approx(gs.player_y) and event_count[0] == before_tutorial_events

	gs.mode = Constants.MODE_COOP
	gs.num_players = 2
	gs.game_state = Constants.STATE_PLAYING
	gs.choice_locked = false
	gs.p1_alive = true
	gs.p2_alive = true
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 1.0
	gs.player_y = StageConstants.OCEAN_ENTRY_Y - 0.1
	gs.player_z = 0.0
	gs.player2_x = 0.0
	gs.player2_y = 0.0
	gs.player2_z = 0.0
	gs.game_over_timer = 0.0
	gs.player2_game_over_timer = 0.0
	var before_coop_events: int = event_count[0]
	gs.update(0.016)
	var coop_ok: bool = not gs.p1_alive and not gs.p2_alive and gs.game_state == Constants.STATE_GAME_OVER and event_count[0] == before_coop_events + 1

	ctx.log("modes two_player=%s tutorial=%s coop=%s events=%d" % [
		str(two_player_ok),
		str(tutorial_ok),
		str(coop_ok),
		event_count[0]
	])
