extends RefCounted

func run(ctx: Variant) -> void:
	var shark := ctx.get_scene_root() as SharkSwimmer
	if shark == null:
		ctx.error("Shark root was not found")
		ctx.close_scene()
		return
	shark.prepare_ghost_rendezvous(1, Vector3.ZERO, Vector3.LEFT * 5.0)
	shark.position = Vector3.ZERO
	shark.set("_ghost_phase", SharkSwimmer.GhostRidePhase.HOVER)
	shark.set_process(false)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.2, 8.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.2, 0.0))
	camera.current = true
	shark.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	light.light_energy = 1.4
	shark.add_child(light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.38, 0.53)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.78)
	env.ambient_light_energy = 0.75
	environment.environment = env
	shark.add_child(environment)

	shark.set_ghost_wall_occluded(false)
	var normal_frame: Image = await ctx.frame()
	var normal_overlay_count := _overlay_count(shark.model)
	ctx.log("no_wall overlays=%d expected=0" % normal_overlay_count)
	if normal_overlay_count != 0:
		ctx.error("Silhouette overlay remained active without a wall")

	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(1.5, 4.0, 0.25)
	wall.mesh = wall_mesh
	wall.position = Vector3(-0.5, 0.0, 2.5)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.40, 0.42, 0.46)
	wall.material_override = wall_material
	shark.add_child(wall)
	shark.set_ghost_wall_occluded(true)
	var occluded_frame: Image = await ctx.frame()
	var occluded_overlay_count := _overlay_count(shark.model)
	ctx.log("wall_blocked overlays=%d expected_positive=true" % occluded_overlay_count)
	if occluded_overlay_count <= 0:
		ctx.error("Silhouette overlay did not activate for a blocking wall")

	shark.set_ghost_wall_occluded(false)
	var restored_overlay_count := _overlay_count(shark.model)
	ctx.log("wall_cleared overlays=%d expected=0" % restored_overlay_count)
	if restored_overlay_count != 0:
		ctx.error("Silhouette overlay was not removed after occlusion cleared")

	var pages: Array[Image] = ctx.sheet(
		[normal_frame, occluded_frame],
		{
			"columns": 2,
			"labels": ["NO WALL", "WALL BLOCKING"],
			"cell_size": Vector2i(512, 288),
			"gap": 8
		}
	)
	for page: Image in pages:
		ctx.output(page, "Ghost shark wall-gated silhouette comparison")
	ctx.close_scene()


func _overlay_count(root: Node) -> int:
	var count := 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.material_overlay != null:
			count += 1
	return count
