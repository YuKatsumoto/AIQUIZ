extends RefCounted
func run(ctx: Variant) -> void:
	var results: Array = []
	for width: int in [24,28,34]:
		var recorder := ReplayRecorder.new()
		recorder.load_from_file("res://artifacts/chip_saw/verification/replay_%d.rep" % width)
		QuizManager.set_meta("last_replay", recorder)
		ctx.get_scene_root().get_tree().paused = false
		ctx.get_scene_root().get_tree().change_scene_to_file("res://scenes/replay_scene.tscn")
		await ctx.wait(2.0)
		var scene: Node = ctx.get_scene_root()
		if scene.name != "ReplayScene":
			ctx.error("Unexpected replay scene: " + str(scene.name))
			return
		scene.replay_player.seek(0.0)
		scene.replay_player.is_paused = true
		scene.replay_camera_node.set_mode(ReplayCamera.Mode.OVERHEAD)
		await ctx.wait(0.2)
		var old_visible: bool = scene._game_world._saw_controller.visible
		scene.replay_player.seek(1.0)
		await ctx.wait(0.2)
		var gs: QuizGameState = QuizManager.game_state
		var row := {"fields":width,"before_visible":old_visible,"after_visible":scene._game_world._saw_controller.visible,"saw_killed":gs.p1_saw_killed,"logic_disabled":not gs.uses_saw_chase()}
		results.append(row)
		var frame: Image = await ctx.frame(960)
		frame.save_png("res://artifacts/chip_saw/verification/replay_%d.png" % width)
		ctx.output(frame,"Replay %d fields" % width)
	ctx.get_scene_root().get_tree().paused = true
	FileAccess.open("res://artifacts/chip_saw/verification/replay_runtime.json", FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	ctx.log("Replay seek/visibility", {"results":results})
