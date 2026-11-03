extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var gs: QuizGameState = root.get("game_state") as QuizGameState
	var ghost: Node = root.get_node_or_null("GhostSharkRideController")
	if gs == null or ghost == null:
		ctx.error("Required game state or ghost controller was not found.")
		return

	gs.num_players = 2
	gs.mode = Constants.MODE_ENDLESS
	gs.game_state = Constants.STATE_PLAYING
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_waiting_for_shark = false
	gs.p2_waiting_for_shark = false
	gs.p1_shark_killed = false
	gs.p2_shark_killed = false
	ghost.call("force_cleanup")

	gs.p1_alive = false
	gs.game_over_timer = 0.001
	gs.p1_wall_impact = true
	gs.player2_x = StageConstants.FLOOR_HALF_WIDTH + 1.0
	gs.player2_y = StageConstants.OCEAN_ENTRY_Y - 0.1
	gs.player2_local_z = 0.0
	gs.call("_begin_ocean_shark_wait", 2)

	var samples: Array[Dictionary] = []
	for second: int in range(13):
		samples.append({
			"t": second,
			"state": gs.game_state,
			"p1_alive": gs.p1_alive,
			"p2_alive": gs.p2_alive,
			"p2_waiting": gs.p2_waiting_for_shark,
			"p2_shark_killed": gs.p2_shark_killed,
			"assigned_attacks": (root.get("_ocean_attack_sharks") as Dictionary).size(),
			"ghost_phase": (ghost.call("get_debug_state") as Dictionary).get("phase", ""),
		})
		if gs.game_state == Constants.STATE_GAME_OVER:
			break
		await ctx.wait(1.0)

	ctx.log("sequential 2P ocean death trace", {"samples": samples})
