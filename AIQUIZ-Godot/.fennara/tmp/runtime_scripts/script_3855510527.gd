extends RefCounted
func run(ctx: Variant) -> void:
	var world: Node = ctx.get_scene_root()
	var gs: QuizGameState = QuizManager.game_state
	ctx.log("current", {"state": gs.game_state, "x": gs.player_x, "z": gs.player_local_z, "wall": gs.wall_z, "fall": gs.p1_fall_committed, "same_state": gs == world.game_state, "world_processing": world.is_processing(), "locked": gs.is_tutorial_presentation_locked(), "paused": world.get_tree().paused, "speed": gs._active_wall_speed, "external_lock": gs.p1_external_control_lock})
