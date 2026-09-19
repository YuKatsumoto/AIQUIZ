extends "res://tests/santorini_environment_runtime.gd"

## Uses the existing offline arrival/play/menu fixture. Inspection cameras are
## temporary and restored before the timed gameplay sample begins.
func snapshot(stage: Node, viewport: Viewport, tag: String) -> Dictionary:
	var captured: Dictionary = await super.snapshot(stage, viewport, tag)
	if tag.ends_with("_playing_start"):
		captured["waterfront"] = await inspect_waterfront(stage, tag)
		if not captured.waterfront.errors.is_empty():
			report.errors.append_array(captured.waterfront.errors)
	return captured


func inspect_waterfront(stage: Node, tag: String) -> Dictionary:
	var result := {"errors": [], "foundations": [], "routes": [], "captures": [], "quality": {}}
	var waterfront := stage.get_node_or_null("WaterfrontInfrastructure")
	if waterfront == null:
		result.errors.append("Missing waterfront")
		return result
	var floor_bounds: AABB = stage.floor_mesh.global_transform * stage.floor_mesh.get_aabb()
	result["conveyor_bottom"] = floor_bounds.position.y
	var foundations := waterfront.get_node("SeabedAndDistrictFoundations")
	var bed_top := INF
	for mesh: MeshInstance3D in foundations.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if "Seabed" in mesh.name:
			bed_top = bounds.end.y
		else:
			result.foundations.append({"name": str(mesh.name), "bottom": bounds.position.y, "top": bounds.end.y})
	result["seabed_top"] = bed_top
	if absf(bed_top - floor_bounds.position.y) > 0.002:
		result.errors.append("Conveyor and seabed do not meet")
	if result.foundations.size() != 13:
		result.errors.append("Expected 13 district foundations")
	for foundation: Dictionary in result.foundations:
		if absf(foundation.bottom - bed_top) > 0.002 or absf(foundation.top + 14.2) > 0.002:
			result.errors.append("District foundation contact mismatch")
	result["stands"] = _inspect_stands(stage)
	for stand: Dictionary in result.stands:
		if absf(float(stand.geometry_bounds.min[1]) - bed_top) > 0.002:
			result.errors.append("Stand base does not meet seabed")
	result.routes = waterfront.routes.duplicate(true)
	if result.routes.size() != 4:
		result.errors.append("Expected two access routes per stand")
	result["new_collision_bodies"] = waterfront.find_children("*", "CollisionObject3D", true, false).size()
	var scene := get_tree().current_scene
	var saved_process := scene.is_processing()
	var saved_physics := scene.is_physics_processing()
	scene.set_process(false)
	scene.set_physics_process(false)
	var weather: Node = stage.weather_cycle
	var saved_phase := float(weather.day_phase)
	var saved_forced := bool(weather.get("_forced"))
	var quality := str(GameManager.graphics_quality)
	for q: String in ["low", "balanced", "high"]:
		stage.apply_graphics_quality(q)
		var shadows := 0
		for geometry: GeometryInstance3D in waterfront.find_children("*", "GeometryInstance3D", true, false):
			if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows += 1
		result.quality[q] = shadows
		if (q == "low" and shadows != 0) or (q != "low" and shadows == 0):
			result.errors.append("Waterfront quality forwarding failed")
	stage.apply_graphics_quality(quality)
	weather.force_day_phase(0.25)
	var old_camera := stage.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.name = "WaterfrontInspectionCamera"
	scene.add_child(camera)
	camera.far = 4500.0
	camera.fov = 58.0
	camera.make_current()
	var route: Dictionary = result.routes[-1] if not result.routes.is_empty() else {"world_z": 64.0}
	var z := float(route.world_z)
	var views := {
		"overview": [Vector3(24, 34, z + 95), Vector3(80, -3, z)],
		"stairs": [Vector3(42, 10, z + 22), Vector3(47, -1, z)],
		"seabed": [Vector3(3, -12, z + 35), Vector3(39, -15, z)],
	}
	for label: String in views:
		camera.global_position = views[label][0]
		camera.look_at(views[label][1])
		for frame: int in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://artifacts/santorini_waterfront/" + tag + "_" + label + ".png"
		stage.get_viewport().get_texture().get_image().save_png(path)
		result.captures.append(path)
	old_camera.make_current()
	camera.queue_free()
	if saved_forced:
		weather.force_day_phase(saved_phase)
	else:
		weather.clear_force()
	scene.set_process(saved_process)
	scene.set_physics_process(saved_physics)
	var file := FileAccess.open("res://artifacts/santorini_waterfront/" + tag + "_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	return result
