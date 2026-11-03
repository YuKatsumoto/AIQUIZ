extends RefCounted

func run(ctx: Variant) -> void:
	var shark: Node3D = ctx.get_scene_root() as Node3D
	shark.set_process(false)
	shark.position = Vector3.ZERO
	shark.rotation = Vector3.ZERO
	var model: Node3D = shark.get_node("Model") as Node3D
	model.position = Vector3.ZERO
	model.rotation = Vector3(0.0, PI * 0.5, 0.0)
	model.scale = Vector3.ONE * 0.82

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.09, 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.58, 0.72)
	environment.ambient_light_energy = 1.25
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	shark.add_child(world_environment)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	shark.add_child(light)
	light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	light.light_energy = 2.2
	light.shadow_enabled = true

	var camera: Camera3D = Camera3D.new()
	shark.add_child(camera)
	camera.position = Vector3(4.2, 1.6, -8.8)
	camera.look_at(Vector3(0.0, -0.15, -0.5), Vector3.UP)
	camera.fov = 38.0
	camera.current = true

	shark.set("_jaw_open_amount", 1.0)
	shark.call("_apply_jaw_pose")
	await ctx.wait(0.45)
	ctx.log("jaw_open bone_index=%d amount=%.2f" % [int(shark.get("_jaw_bone_index")), float(shark.get("_jaw_open_amount"))])
	await ctx.capture("jaw_open")

	shark.set("_jaw_open_amount", 0.0)
	shark.call("_apply_jaw_pose")
	await ctx.wait(0.3)
	ctx.log("jaw_closed amount=%.2f" % float(shark.get("_jaw_open_amount")))
	await ctx.capture("jaw_closed")
