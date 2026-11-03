extends RefCounted

func run(ctx: Variant) -> void:
	var world: Node3D = ctx.get_scene_root() as Node3D
	world.set_process(false)
	var state: Object = world.get("game_state")
	state.set("num_players", 1)
	state.set("p1_waiting_for_shark", true)
	state.set("player_x", -15.0)
	state.set("player_y", StageConstants.OCEAN_FLOAT_Y)
	state.set("player_local_z", 18.0)

	var controller: Node3D = world.get_node("CameraController") as Node3D
	var camera: Camera3D = controller.get_node("Camera3D") as Camera3D
	camera.fov = 47.25
	var before: float = camera.fov
	controller.call("set_ocean_attack_focus", Vector3(-15.0, StageConstants.OCEAN_SURFACE_Y, -12.0), 1.0)
	for _step: int in range(12):
		controller.call("_update_ocean_attack_camera", state, 1.0 / 60.0)
	var during_charge: float = camera.fov
	controller.call("trigger_ocean_attack_impact")
	for _step: int in range(24):
		controller.call("_update_ocean_attack_camera", state, 1.0 / 60.0)
	var during_impact: float = camera.fov
	ctx.log("shark_fov before=%.2f charge=%.2f impact=%.2f unchanged=%s" % [
		before,
		during_charge,
		during_impact,
		str(is_equal_approx(before, during_charge) and is_equal_approx(before, during_impact)),
	])
	await ctx.capture("shark_attack_fixed_fov")
