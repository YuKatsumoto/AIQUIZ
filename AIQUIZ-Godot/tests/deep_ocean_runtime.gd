extends "res://tests/santorini_environment_runtime.gd"

const DEEP_OUTPUT := "res://artifacts/deep_ocean/"
var inspection_done := false
var inspection: Dictionary = {}


func run_and_inspect() -> void:
	return_to_menu_after_run = false
	await run_offline_start("inspection_p2", 2, "direct")
	await inspect_depth()


func _write(tag: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DEEP_OUTPUT)
	var file := FileAccess.open(DEEP_OUTPUT + _tag(tag) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))


func snapshot(stage: Node, viewport: Viewport, tag: String) -> Dictionary:
	var result := {"tag": tag, "errors": [], "stands": [], "state": str(QuizManager.game_state.game_state)}
	var floor_bounds: AABB = stage.floor_mesh.global_transform * stage.floor_mesh.get_aabb()
	result["floor_top"] = floor_bounds.end.y
	result["floor_bottom"] = floor_bounds.position.y
	if absf(floor_bounds.end.y - StageConstants.FLOOR_TOP_Y) > 0.002 or absf(floor_bounds.position.y - StageConstants.SEABED_Y) > 0.002:
		result.errors.append("Floor top/bottom mismatch")
	var collider: Node3D = stage.get("_floor_collision_body")
	if collider != null:
		var shape := collider.get_child(0) as CollisionShape3D
		result["collision_top"] = shape.global_position.y + (shape.shape as BoxShape3D).size.y * 0.5
		if absf(result.collision_top - StageConstants.FLOOR_TOP_Y) > 0.002:
			result.errors.append("Changed gameplay collision top")
	if stage.has_node("HarborCityBackdrop"):
		result.errors.append("Town unexpectedly enabled")
	var waterfront := stage.get_node_or_null("WaterfrontInfrastructure")
	if waterfront != null:
		for node: MeshInstance3D in waterfront.get_node("SeabedAndDistrictFoundations").find_children("*", "MeshInstance3D", true, false):
			var bounds := node.global_transform * node.get_aabb()
			if "Seabed" in node.name:
				result["seabed_top"] = bounds.end.y
				if absf(bounds.end.y - StageConstants.SEABED_Y) > 0.002:
					result.errors.append("Wrong seabed elevation")
			elif absf(bounds.position.y - StageConstants.SEABED_Y) > 0.002 or absf(bounds.end.y + 14.2) > 0.002:
				result.errors.append("Archived district foundation disconnected")
	var stands := stage.get_node_or_null("Grandstands")
	if stands != null:
		for stand: Node3D in stands.get_children():
			var node := stand.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var bounds := node.global_transform * node.get_aabb()
			var crowd := stand.get_node("Spectators")
			result.stands.append({"name":str(stand.name), "bottom":bounds.position.y, "top":bounds.end.y, "people":crowd.spectator_count, "hats":crowd.hat_count, "dancers":crowd.emote_count})
			if absf(bounds.position.y - StageConstants.SEABED_Y) > 0.002 or absf(bounds.end.y - 4.2) > 0.002:
				result.errors.append("Stand support/deck height mismatch")
	await _capture(viewport, tag)
	result["image"] = DEEP_OUTPUT + tag + ".png"
	report.errors.append_array(result.errors)
	return result


func check_import_preservation() -> Dictionary:
	var packed := load("res://assets/environment/santorini_waterfront/santorini_open_terrace_grounded.glb") as PackedScene
	var original := packed.instantiate() as Node3D
	var extended := packed.instantiate() as Node3D
	load("res://scripts/world/santorini_waterfront.gd").extend_stand_supports(extended)
	var src: ArrayMesh = original.find_children("*", "MeshInstance3D", true, false)[0].mesh
	var dst: ArrayMesh = extended.find_children("*", "MeshInstance3D", true, false)[0].mesh
	var result := {"errors": [], "preserved_upper_vertices":0, "extended_lower_vertices":0, "lods":0}
	for surface: int in range(src.get_surface_count()):
		var a := src.surface_get_arrays(surface)
		var b := dst.surface_get_arrays(surface)
		for i: int in range(a[Mesh.ARRAY_VERTEX].size()):
			var v: Vector3 = a[Mesh.ARRAY_VERTEX][i]
			var w: Vector3 = b[Mesh.ARRAY_VERTEX][i]
			if v.y >= StageConstants.OCEAN_SURFACE_Y:
				result.preserved_upper_vertices += 1
				if not v.is_equal_approx(w): result.errors.append("Upper vertex changed")
			else:
				result.extended_lower_vertices += 1
				if absf(w.y - v.y + 112.0) > 0.002: result.errors.append("Lower extension mismatch")
		if a[Mesh.ARRAY_INDEX] != b[Mesh.ARRAY_INDEX] or src.surface_get_material(surface) != dst.surface_get_material(surface):
			result.errors.append("Topology/material changed")
		var old_lods: Array = RenderingServer.mesh_get_surface(src.get_rid(), surface).get("lods", [])
		var new_lods: Array = RenderingServer.mesh_get_surface(dst.get_rid(), surface).get("lods", [])
		result.lods += old_lods.size()
		if old_lods != new_lods: result.errors.append("LOD changed")
	original.free()
	extended.free()
	_write("mesh_preservation", result)
	return result


func inspect_depth() -> void:
	inspection_done = false
	inspection = {"errors":[], "qualities":[], "renderer":RenderingServer.get_current_rendering_method()}
	var scene := get_tree().current_scene
	var stage := scene.get_node("StageEnvironment")
	var viewport := stage.get_viewport()
	var old_camera := viewport.get_camera_3d()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.far = 4500.0
	camera.fov = 55.0
	var was_paused := get_tree().paused
	get_tree().paused = true
	camera.make_current()
	var bed: MeshInstance3D
	for node: MeshInstance3D in stage.get_node("WaterfrontInfrastructure/SeabedAndDistrictFoundations").find_children("*", "MeshInstance3D", true, false):
		if "Seabed" in node.name: bed = node
	for quality: String in ["low", "balanced", "high"]:
		stage.apply_graphics_quality(quality)
		camera.global_position = Vector3(-5, 35, -65)
		camera.look_at(Vector3(0, 0, 55))
		await _capture(viewport, quality + "_overview")
		camera.global_position = Vector3(80, 20, 80)
		camera.look_at(Vector3(80, -9.2, 80), Vector3.FORWARD)
		var material: ShaderMaterial = stage.get("_ocean_surface").material_override
		var speed: Variant = material.get_shader_parameter("wave_speed")
		material.set_shader_parameter("wave_speed", 0.0)
		var visible_bed := await _capture(viewport, quality + "_bed_visible")
		bed.visible = false
		var hidden_bed := await _capture(viewport, quality + "_bed_hidden")
		bed.visible = true
		material.set_shader_parameter("wave_speed", speed)
		var total := 0.0
		var maximum := 0.0
		var center := Vector2i(visible_bed.get_width() / 2, visible_bed.get_height() / 2)
		for x: int in range(center.x - 64, center.x + 64):
			for y: int in range(center.y - 64, center.y + 64):
				var a := visible_bed.get_pixel(x, y)
				var b := hidden_bed.get_pixel(x, y)
				var error := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g),absf(a.b-b.b)))
				total += error
				maximum = maxf(maximum, error)
		var mean := total / (128.0 * 128.0)
		inspection.qualities.append({"quality":quality, "seabed_pixel_mean_255":mean*255.0, "seabed_pixel_max_255":maximum*255.0})
		if mean > 1.0 / 255.0: inspection.errors.append(quality + " seabed remains perceptible")
	stage.apply_graphics_quality(str(GameManager.graphics_quality))
	camera.global_position = Vector3(150,-25,-130)
	camera.look_at(Vector3(0,-70,30))
	await _capture(viewport, "underwater_support_contact")
	old_camera.make_current()
	camera.queue_free()
	get_tree().paused = was_paused
	_write("depth_inspection", inspection)
	inspection_done = true


func _capture(viewport: Viewport, tag: String) -> Image:
	DirAccess.make_dir_recursive_absolute(DEEP_OUTPUT)
	for _frame: int in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(DEEP_OUTPUT + tag + ".png")
	return image
