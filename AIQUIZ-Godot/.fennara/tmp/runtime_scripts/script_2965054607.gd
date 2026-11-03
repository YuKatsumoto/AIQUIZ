extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var world: Node3D = root as Node3D
	var hud: CanvasLayer = world.get_node("GameplayHUD") as CanvasLayer
	var wipe_layer: CanvasLayer = world.get_node("DeathWipeLayer") as CanvasLayer
	hud.visible = false
	wipe_layer.visible = false
	var stage_env: StageEnvironment = world.get("stage_env") as StageEnvironment
	var shark: SharkSwimmer = stage_env.get_ocean_sharks()[0]
	shark.process_mode = Node.PROCESS_MODE_DISABLED
	shark.position = Vector3(0.0, StageConstants.OCEAN_SURFACE_Y - 0.6, 12.0)
	shark.rotation = Vector3.ZERO
	var camera_controller: Node3D = world.get_node("CameraController") as Node3D
	camera_controller.process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = camera_controller.get_node("Camera3D") as Camera3D
	camera.global_position = Vector3(4.8, StageConstants.OCEAN_SURFACE_Y + 0.7, 4.0)
	camera.look_at(Vector3(0.0, StageConstants.OCEAN_SURFACE_Y - 0.4, 8.2), Vector3.UP)
	camera.fov = 36.0
	shark.set("_jaw_open_amount", 1.0)
	shark.call("_apply_jaw_pose")
	await ctx.wait(0.08)
	await ctx.capture("jaw_open_visible")
	shark.set("_jaw_open_amount", 0.0)
	shark.call("_apply_jaw_pose")
	await ctx.wait(0.08)
	await ctx.capture("jaw_closed_visible")
