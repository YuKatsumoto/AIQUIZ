extends RefCounted

var sequence_status: String = "idle"
var sequence_reports: Array[Dictionary] = []


func exercise_rounds(tree: SceneTree) -> void:
	sequence_status = "running"
	for player_count: int in [1, 2]:
		QuizManager.provider.set_llm_mode("OFFLINE")
		QuizManager.game_state.num_players = player_count
		var previous_world_id: int = tree.current_scene.get_instance_id()
		tree.current_scene.get_node("GameplayHUD")._retry_game()
		var deadline: int = Time.get_ticks_msec() + 60000
		var states: Array[String] = []
		while Time.get_ticks_msec() < deadline:
			var world: Node = tree.current_scene
			if world == null or world.get_instance_id() == previous_world_id:
				await tree.create_timer(0.08).timeout
				continue
			var state: String = QuizManager.game_state.game_state
			if states.is_empty() or states.back() != state:
				states.append(state)
			if state == Constants.STATE_WAITING_START and world.has_method("is_start_presentation_locked"):
				if not world.is_start_presentation_locked() and not world.is_preload_construction_locked():
					var key := InputEventKey.new()
					key.keycode = KEY_ENTER
					key.pressed = true
					Input.parse_input_event(key)
					await tree.process_frame
					key = InputEventKey.new()
					key.keycode = KEY_ENTER
					Input.parse_input_event(key)
			if state == Constants.STATE_PLAYING and not SceneTransition.is_transitioning():
				# Let the countdown barrier fragments clear the actual gameplay view.
				await tree.create_timer(2.6).timeout
				var report: Dictionary = await capture(world.stage_env, world.get_viewport(), "gameplay_%dp" % player_count)
				report["states"] = states
				report["fresh_scene_instance"] = world.get_instance_id() != previous_world_id
				report["transition_cover_active"] = SceneTransition.is_transitioning()
				report["camera_far"] = world.camera_controller.camera.far
				report["fps_observed"] = Engine.get_frames_per_second()
				sequence_reports.append(report)
				break
			await tree.create_timer(0.08).timeout
		if sequence_reports.size() != player_count:
			sequence_status = "timeout_%dp" % player_count
			_save_sequence()
			return
	sequence_status = "passed"
	_save_sequence()
	tree.current_scene.get_node("GameplayHUD")._return_to_main_menu()


func _save_sequence() -> void:
	var file := FileAccess.open("res://artifacts/harbor_city/runtime_sequence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": sequence_status, "rounds": sequence_reports}, "\t"))
	print("HARBOR_CITY_SEQUENCE " + sequence_status)


## Run against the real menu/game StageEnvironment using Godot AI game_eval.
## Captures the actual viewport and checks the imported, placed scenery.
func capture(stage: StageEnvironment, viewport: Viewport, tag: String) -> Dictionary:
	var city: Node3D = stage.get_node("HarborCityBackdrop")
	var meshes: Array[Node] = city.find_children("*", "MeshInstance3D", true, false)
	var sides: Dictionary = {"Left": 0, "Right": 0, "Rear": 0}
	var triangles: int = 0
	var surfaces: int = 0
	var forward_corridor_vertices: int = 0
	var city_bounds := AABB()
	var first := true
	for node: Node in meshes:
		var instance := node as MeshInstance3D
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		city_bounds = bounds if first else city_bounds.merge(bounds)
		first = false
		for side: String in sides:
			if String(instance.name).begins_with(side):
				sides[side] += 1
		surfaces += instance.mesh.get_surface_count()
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var world: Vector3 = instance.global_transform * vertex
				if absf(world.x) < 1000.0 and world.z > -1200.0:
					forward_corridor_vertices += 1
	var report: Dictionary = {
		"tag": tag, "renderer": RenderingServer.get_current_rendering_method(),
		"mesh_count": meshes.size(), "sides": sides,
		"source_triangles": triangles, "surfaces": surfaces,
		"bounds": str(city_bounds), "forward_corridor_vertices": forward_corridor_vertices,
		"collision_bodies": city.find_children("*", "CollisionObject3D", true, false).size(),
		"night_window_materials": city._window_materials.size(),
		"sea_level": city.position.y, "player_count": QuizManager.game_state.num_players,
		"game_state": QuizManager.game_state.game_state,
	}
	assert(meshes.size() == 13, "Expected one U city with 13 export meshes")
	assert(sides.Left == 4 and sides.Right == 4 and sides.Rear == 4)
	assert(forward_corridor_vertices == 0, "Scenery entered the open course corridor")
	assert(report.collision_bodies == 0)
	assert(is_equal_approx(city.position.y, StageConstants.OCEAN_SURFACE_Y))
	assert(city._window_materials.size() == 3)
	var previous_phase: float = stage.weather_cycle.day_phase
	var was_forced: bool = stage.weather_cycle._forced
	var output_dir := "res://artifacts/harbor_city"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	for phase: String in ["day", "night"]:
		stage.weather_cycle.force_day_phase(0.25 if phase == "day" else 0.75)
		for frame in range(8):
			await stage.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var energy: float = city._window_materials[0].emission_energy_multiplier
		assert(energy < 0.01 if phase == "day" else energy > 1.0)
		var capture_path: String = output_dir.path_join(tag + "_" + phase + ".png")
		var capture_image: Image = viewport.get_texture().get_image()
		assert(capture_image.save_png(capture_path) == OK)
		report[phase] = {"window_emission": energy, "image": capture_path}
	if was_forced:
		stage.weather_cycle.force_day_phase(previous_phase)
	else:
		stage.weather_cycle.clear_force()
	var file := FileAccess.open(output_dir.path_join(tag + "_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("HARBOR_CITY_RUNTIME_PASS " + JSON.stringify(report))
	return report
