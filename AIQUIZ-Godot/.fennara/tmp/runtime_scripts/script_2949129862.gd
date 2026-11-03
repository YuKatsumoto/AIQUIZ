extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var world: Node3D = root as Node3D
	var stage_env: StageEnvironment = world.get("stage_env") as StageEnvironment
	var sharks: Array[SharkSwimmer] = stage_env.get_ocean_sharks()
	if sharks.is_empty():
		ctx.error("No shark available for jaw close-up")
		return
	var shark: SharkSwimmer = sharks[0]
	shark.cancel_attack()
	shark.process_mode = Node.PROCESS_MODE_DISABLED
	shark.position = Vector3(0.0, StageConstants.OCEAN_SURFACE_Y - 0.6, 12.0)
	shark.rotation = Vector3.ZERO
	shark.set("_jaw_open_amount", 1.0)
	shark.call("_apply_jaw_pose")

	var camera_controller: Node3D = world.get_node("CameraController") as Node3D
	camera_controller.process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = camera_controller.get_node("Camera3D") as Camera3D
	camera.global_position = Vector3(5.5, StageConstants.OCEAN_SURFACE_Y + 1.6, 4.0)
	camera.look_at(Vector3(0.0, StageConstants.OCEAN_SURFACE_Y - 0.35, 8.4), Vector3.UP)
	camera.fov = 42.0
	await ctx.wait(0.08)
	await ctx.capture("jaw_open_closeup")
	shark.set("_jaw_open_amount", 0.0)
	shark.call("_apply_jaw_pose")
	await ctx.wait(0.08)
	await ctx.capture("jaw_closed_closeup")
	var jaw_index: int = int(shark.get("_jaw_bone_index"))
	var skeleton: Skeleton3D = shark.get("_jaw_skeleton") as Skeleton3D
	ctx.log("jaw_closeup index=%d open_reset=%s bone_rotation=%s" % [
		jaw_index,
		str(shark.get("_jaw_open_amount")),
		str(skeleton.get_bone_pose_rotation(jaw_index))
	])
