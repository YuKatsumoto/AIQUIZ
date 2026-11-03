extends RefCounted
func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	ctx.log("game readiness", {"scene":root.name,"state":QuizManager.game_state.game_state,"transition":SceneTransition.is_transitioning()})
	if root.name == "GameWorld":
		ctx.log("arrival", {"locked":root.is_start_presentation_locked(),"preload":root.is_preload_construction_locked()})
		if not root.is_start_presentation_locked():
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = true
			Input.parse_input_event(event)
			await ctx.wait(0.1)
			event = InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = false
			Input.parse_input_event(event)
			await ctx.wait(4.5)
			ctx.get_scene_root().get_tree().paused = true
			ctx.log("started", {"state":QuizManager.game_state.game_state,"saw":QuizManager.game_state.saw.local_z})
			await ctx.capture("saw_start")
