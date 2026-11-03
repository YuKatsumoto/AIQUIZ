extends RefCounted
func run(ctx: Variant) -> void:
	ctx.log("Before retry", {"alive":QuizManager.game_state.p1_alive,"saw_killed":QuizManager.game_state.p1_saw_killed,"state":QuizManager.game_state.game_state})
	if not await load("res://tests/saw_chase_modes_runtime.gd").new().start(ctx, Constants.MODE_ENDLESS, 2):
		ctx.error("retry failed")
		return
	var gs: QuizGameState = QuizManager.game_state
	gs.player_x = 11.0
	gs.player_z = gs.world_scroll_z
	var tree: SceneTree = ctx.get_scene_root().get_tree()
	ctx.log("Fall start", {"alive":gs.p1_alive,"fall":gs.p1_fall_committed,"saw_killed":gs.p1_saw_killed,"state":gs.game_state})
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.physical_keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	tree.paused = false
	await ctx.wait(0.55)
	key = InputEventKey.new()
	key.keycode = KEY_A
	key.physical_keycode = KEY_A
	key.pressed = false
	Input.parse_input_event(key)
	tree.paused = true
	var row := {"passed":gs.p1_fall_committed and gs.player_y<0 and not gs.p1_saw_killed,"side_fall":gs.p1_fall_committed,"x":gs.player_x,"y":gs.player_y,"alive":gs.p1_alive,"state":gs.game_state}
	FileAccess.open("res://artifacts/chip_saw/verification/side_fall.json", FileAccess.WRITE).store_string(JSON.stringify(row,"\t"))
	var image: Image = await ctx.frame(1280)
	image.save_png("res://artifacts/chip_saw/verification/side_fall.png")
	ctx.output(image,"Side fall remains possible")
	ctx.log("Fall result", row)
