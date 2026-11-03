extends RefCounted

func run(ctx: Variant) -> void:
	var gs: QuizGameState = QuizManager.game_state
	ctx.log("fixture_before", {"state": gs.game_state, "p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z]})
	await ctx.capture("verified_before")
	ctx.get_scene_root().get_tree().paused = false
	ctx.press_key(KEY_W, {"physical": false})
	var samples: Array[Dictionary] = []
	for frame: int in range(40):
		await ctx.get_scene_root().get_tree().process_frame
		gs = QuizManager.game_state
		samples.append({"frame": frame, "key_w": Input.is_key_pressed(KEY_W), "p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "fall": gs.p1_fall_committed})
		if gs.p1_fall_committed:
			break
	ctx.release_all_inputs()
	ctx.get_scene_root().get_tree().paused = true
	ctx.log("verified_keyboard_teleport", {"samples": samples})
	FileAccess.open("res://artifacts/teleport_investigation/live_samples.json", FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	if not QuizManager.game_state.p1_fall_committed:
		ctx.error("Forward input did not reach the reproduction condition")
		return
	await ctx.capture("verified_teleport")
	ctx.get_scene_root().get_tree().paused = false
	await ctx.wait(0.7)
	ctx.get_scene_root().get_tree().paused = true
	await ctx.capture("verified_falling")
