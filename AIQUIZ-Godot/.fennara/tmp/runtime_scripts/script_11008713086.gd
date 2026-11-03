extends RefCounted
func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	root.get_tree().paused = false
	ctx.log("Before input", {"state":QuizManager.game_state.game_state,"scene":root.name})
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	await ctx.wait(0.1)
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = false
	Input.parse_input_event(event)
	await ctx.wait(7.0)
	ctx.get_scene_root().get_tree().paused = true
	if QuizManager.game_state.game_state == Constants.STATE_PLAYING:
		await load("res://tests/saw_chase_runtime.gd").new().run(ctx)
	else:
		ctx.error("Not PLAYING: " + QuizManager.game_state.game_state)
