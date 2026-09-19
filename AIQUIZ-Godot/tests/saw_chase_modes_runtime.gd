extends RefCounted
const OUT := "res://artifacts/chip_saw/verification/"

func start(ctx: Variant, mode: String, count: int) -> bool:
	ctx.get_scene_root().get_tree().paused = false
	var gs: QuizGameState = QuizManager.game_state
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.llm_mode = "OFFLINE"
	gs.num_players = count
	gs.mode = mode
	if mode == Constants.MODE_TUTORIAL:
		gs.start_tutorial(GameManager.TUTORIAL_COURSE_LOCAL_2P)
	else:
		gs.start_game()
	gs.skip_start_helicopter_arrival = true
	GameManager.start_game()
	for attempt: int in range(250):
		await ctx.wait(0.1)
		var scene: Node = ctx.get_scene_root()
		if scene == null or scene.name != "GameWorld" or SceneTransition.is_transitioning():
			continue
		if scene.is_start_presentation_locked() or scene.is_preload_construction_locked() or scene._barrier_dropping:
			continue
		if gs.game_state == Constants.STATE_WAITING_START:
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = true
			Input.parse_input_event(event)
			await ctx.wait(0.1)
			event = InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = false
			Input.parse_input_event(event)
		if gs.game_state == Constants.STATE_PLAYING:
			await ctx.wait(3.0)
			ctx.get_scene_root().get_tree().paused = true
			return true
	ctx.get_scene_root().get_tree().paused = true
	return false

func verify(ctx: Variant, mode: String, count: int) -> void:
	var ready: bool = await start(ctx, mode, count)
	var world: Node = ctx.get_scene_root()
	var gs: QuizGameState = QuizManager.game_state
	var expected: bool = count == 2 and mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS]
	var passed: bool = ready and gs.uses_saw_chase() == expected and world._saw_controller.visible == expected and world.stage_env._running_rails != null
	var image: Image = await ctx.frame(1280)
	image.save_png(OUT + "mode_%s_%d.png" % [mode,count])
	ctx.output(image, "Mode %s/%d" % [mode,count])
	var report := {"mode":mode,"players":count,"ready":ready,"saw":gs.uses_saw_chase(),"passed":passed}
	FileAccess.open(OUT + "mode_%s_%d.json" % [mode,count], FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	ctx.log("Mode validation", report)

func run(ctx: Variant) -> void:
	await verify(ctx, Constants.MODE_ENDLESS, 2)
