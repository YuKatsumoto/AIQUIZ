extends "res://tests/santorini_environment_runtime.gd"

const CROWD_OUTPUT := "res://artifacts/crowd_variety/"
var detail_finished := false
var detail_report: Dictionary = {}


func snapshot(stage: Node, viewport: Viewport, tag: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(CROWD_OUTPUT)
	var result := {"tag": tag, "errors": [], "crowds": [], "state": str(QuizManager.game_state.game_state)}
	if stage.has_node("HarborCityBackdrop"):
		result.errors.append("Town is still instantiated")
	var stands := stage.get_node_or_null("Grandstands")
	if get_tree().current_scene.has_node("StageEnvironment") and (stands == null or stands.get_child_count() != 2):
		result.errors.append("Missing opposing stands")
	if stands != null:
		for stand: Node3D in stands.get_children():
			var crowd := stand.get_node("Spectators")
			var bodies := 0
			var hats := 0
			var dancers := 0
			var hat_styles := {}
			for batch: Dictionary in crowd._batches:
				var node: MultiMeshInstance3D = batch.node
				var is_hat := "Hat" in node.name
				if is_hat:
					hat_styles[str(node.name).right(1)] = true
				for i: int in range(batch.people.size()):
					var person: Dictionary = batch.people[i]
					if crowd._is_aisle(person.transform.origin.z):
						result.errors.append("Occupied aisle")
					var basis: Basis = (stand.global_transform * node.multimesh.get_instance_transform(i)).basis
					if not is_equal_approx(basis.x.length(), 1.0) or not is_equal_approx(basis.z.length(), 1.0):
						result.errors.append("Stretched spectator/hat")
					if is_hat:
						hats += 1
					else:
						bodies += 1
						if node.multimesh.get_instance_custom_data(i).g >= 2.0:
							dancers += 1
			if bodies != crowd.spectator_count or hats != crowd.hat_count or dancers != crowd.emote_count:
				result.errors.append("Batch population mismatch")
			if hats <= 0 or hats >= bodies / 5 or dancers <= 0 or dancers >= bodies / 5 or hat_styles.size() != 3:
				result.errors.append("Expected rare hats/dancers with all three hat styles")
			result.crowds.append({"stand": str(stand.name), "bodies": bodies, "hats": hats, "dancers": dancers, "hat_styles": hat_styles.keys(), "batches": crowd._batches.size()})
	var waterfront := stage.get_node_or_null("WaterfrontInfrastructure")
	if waterfront != null:
		if not waterfront.routes.is_empty():
			result.errors.append("Town access routes remain")
		for node: MeshInstance3D in waterfront.get_node("SeabedAndDistrictFoundations").find_children("*", "MeshInstance3D", true, false):
			if "Seabed" not in node.name and node.visible:
				result.errors.append("Visible town foundation")
	await RenderingServer.frame_post_draw
	result["image"] = CROWD_OUTPUT + tag + ".png"
	result["image_saved"] = viewport.get_texture().get_image().save_png(result.image) == OK
	if not result.image_saved:
		result.errors.append("Screenshot failed")
	report.errors.append_array(result.errors)
	return result


func inspect_details() -> void:
	detail_finished = false
	detail_report = {"images": [], "errors": [], "note": "Live Forward+ world, temporary inspection camera, gameplay paused; shader animations continue in real time."}
	var scene := get_tree().current_scene
	var stage := scene.get_node("StageEnvironment")
	var crowd := stage.get_node("Grandstands/GrandstandRight/Spectators")
	var viewport := stage.get_viewport()
	var old_camera := viewport.get_camera_3d()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.far = 4500.0
	camera.fov = 55.0
	var was_paused := get_tree().paused
	get_tree().paused = true
	camera.make_current()
	camera.global_position = Vector3(-5, 35, -65)
	camera.look_at(Vector3(0, 0, 55))
	await _detail_capture(viewport, "overview")
	var selected: Dictionary = {}
	for batch: Dictionary in crowd._batches:
		if "Hat" not in batch.node.name:
			continue
		for person: Dictionary in batch.people:
			if person.custom.g >= 2.0:
				selected = person
				break
		if not selected.is_empty():
			break
	if selected.is_empty():
		detail_report.errors.append("No hatted dancer to inspect")
	else:
		var target: Vector3 = crowd.to_global(selected.transform.origin) + Vector3.UP * 0.55
		camera.global_position = target + Vector3(-4.6, 2.0, 4.0)
		camera.look_at(target)
		detail_report["target"] = str(target)
		# Long enough to observe this spectator both resting and dancing naturally.
		for i: int in range(28):
			await _detail_capture(viewport, "dance_%02d" % i)
			await get_tree().create_timer(1.0, true).timeout
	old_camera.make_current()
	camera.queue_free()
	get_tree().paused = was_paused
	var file := FileAccess.open(CROWD_OUTPUT + "detail_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(detail_report, "\t"))
	detail_finished = true


func _detail_capture(viewport: Viewport, tag: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CROWD_OUTPUT + tag + ".png"
	var error := viewport.get_texture().get_image().save_png(path)
	detail_report.images.append({"path": path, "time_ms": Time.get_ticks_msec(), "saved": error == OK})
	if error != OK:
		detail_report.errors.append("Capture failed: " + tag)


func check_rebuilds() -> Dictionary:
	var crowd := load("res://scripts/world/grandstand_crowd.gd").new()
	add_child(crowd)
	crowd.build(0.85, 1729)
	var before := [crowd.spectator_count, crowd.hat_count, crowd.emote_count, crowd.get_child_count()]
	crowd.sync_length_scale(3.0)
	crowd.build(0.85, 1729)
	var after := [crowd.spectator_count, crowd.hat_count, crowd.emote_count, crowd.get_child_count()]
	crowd.build(0.0, 1729)
	var empty: bool = crowd.get_child_count() == 0 and crowd.spectator_count == 0 and crowd.hat_count == 0 and crowd.emote_count == 0
	crowd.free()
	return {"deterministic": before == after, "empty_density_clears_all": empty, "population": before}
