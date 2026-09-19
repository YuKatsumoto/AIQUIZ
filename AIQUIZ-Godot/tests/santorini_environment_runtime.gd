extends Node

## Rendered-environment probe; attach to SceneTree.root, never the changing scene.
## game_eval: var p = load("res://tests/santorini_environment_runtime.gd").new()
## get_tree().root.add_child(p); p.name = "SantoriniEnvironmentProbe"
## p.call_deferred("run_offline_start", "after_p1", 1, "menu")
## Poll p.finished / p.phase / p.report. Each output tag is a caller-owned label.
## snapshot(stage, viewport, tag) and sample_performance(viewport, tag, 2.5)
## are read-only apart from artifact files. They do not change light or quality.
## restore_runtime_settings() ends the OFFLINE test round before restoring source.
## It is explicit so inspecting the resulting game never starts an ONLINE refill.

const OUTPUT := "res://artifacts/santorini_renovation/"
var finished := false
var phase := "idle"
var report: Dictionary = {}
var validation_enabled := true
var return_to_menu_after_run := true
var capture_matrix_after_start := false
var constraints: Dictionary = {
	"corridor_half_width": 70.0,
	"corridor_start_z": -150.0,
	"city_sea_y": -9.2,
	"stand_center_abs_x": 28.0,
	"stand_center_tolerance": 0.25,
	"crowd_rows_max": 4,
	"crowd_seated_top_y_max": 4.0,
}
var _saved_settings: Dictionary = {}
var _state_events: Array[Dictionary] = []
var _start_usec: int = 0
var _mesh_cache: Dictionary = {}
var _properties: Dictionary = {}


func snapshot(stage: Node, viewport: Viewport, tag: String) -> Dictionary:
	var result := {"tag": tag, "errors": [], "checks": {}, "visual_review_required": true}
	if not is_instance_valid(stage) or not is_instance_valid(viewport):
		result.errors.append("Missing live stage or viewport")
		result["passed_structural"] = false
		_write(tag + "_snapshot", result)
		return result
	var stage_viewport := stage.get_viewport()
	var camera := stage_viewport.get_camera_3d()
	var city := stage.get_node_or_null("HarborCityBackdrop") as Node3D
	if city == null:
		city = stage.get_node_or_null("SantoriniTown") as Node3D
	var city_data := _inspect_city(city, camera)
	var stands := _inspect_stands(stage)
	result.merge({
		"renderer": RenderingServer.get_current_rendering_method(),
		"scene": str(get_tree().current_scene.scene_file_path) if get_tree().current_scene else "",
		"stage_path": str(stage.get_path()), "game": _game_info(),
		"city": city_data, "stands": stands, "camera": _camera_info(camera),
		"render": _render_info(stage_viewport), "quality": str(GameManager.graphics_quality),
		"capture_viewport_size": _v2(viewport.get_visible_rect().size),
		"render_viewport_size": _v2(stage_viewport.get_visible_rect().size),
		"scale_3d": stage_viewport.scaling_3d_scale,
		"msaa_3d": stage_viewport.msaa_3d,
		"constraints": constraints.duplicate(true),
		"question": _question_info(get_tree().current_scene, camera),
		"helicopters": _helicopter_info(get_tree().current_scene),
		"weather": _weather_info(stage),
		"unix_time": Time.get_unix_time_from_system(),
	})
	var checks: Dictionary = result.checks
	var validating := validation_enabled and not constraints.is_empty()
	result["validation_enabled"] = validating
	var current_scene := get_tree().current_scene
	var gameplay_stage := current_scene != null and current_scene.get_node_or_null("StageEnvironment") == stage
	result["stands_required_in_this_context"] = gameplay_stage
	result["city_required_in_this_context"] = gameplay_stage
	if validating:
		if gameplay_stage:
			checks["city_has_geometry"] = int(city_data.get("mesh_count", 0)) > 0
			checks["city_no_collision_bodies"] = int(city_data.get("collision_bodies", -1)) == 0
			checks["city_corridor_clear"] = int(city_data.get("corridor_intersecting_triangles", -1)) == 0
			checks["city_sea_datum"] = city != null and absf(city.position.y - float(constraints.get("city_sea_y", -9.2))) < 0.01
			checks["opposing_stands_present"] = stands.size() == 2
		else:
			checks["city_absent_on_menu"] = city == null
		for stand: Dictionary in stands:
			var stand_name: String = stand.name
			checks[stand_name + "_outside_play_space"] = absf(float(stand.center_x)) >= 24.0
			checks[stand_name + "_center"] = absf(absf(float(stand.center_x)) - float(constraints.get("stand_center_abs_x", 28.0))) <= float(constraints.get("stand_center_tolerance", 0.25))
			checks[stand_name + "_low_crowd_rows"] = int(stand.crowd_row_heights.size()) <= int(constraints.get("crowd_rows_max", 4))
			checks[stand_name + "_low_crowd_silhouette"] = float(stand.crowd_seated_top_y) <= float(constraints.get("crowd_seated_top_y_max", 4.0))
	var all_passed := true
	for key: String in checks:
		if not bool(checks[key]):
			all_passed = false
			result.errors.append(key)
	result["passed_structural"] = all_passed if validating else null
	# All expensive geometry inspection precedes the real rendered image readback.
	await RenderingServer.frame_post_draw
	var image_path := OUTPUT + _tag(tag) + ".png"
	_ensure_output()
	var capture_image := viewport.get_texture().get_image()
	var save_error := capture_image.save_png(image_path) if capture_image != null else ERR_UNAVAILABLE
	result["image"] = image_path
	result["image_saved"] = save_error == OK
	if save_error != OK:
		result.errors.append("Image save failed: %d" % save_error)
		result.passed_structural = false
	_write(tag + "_snapshot", result)
	return result


## An uninterrupted 2.5 s window. No screenshots, geometry queries or file writes
## occur inside it. Process/physics monitors are CPU observations, not GPU timing.
func sample_performance(viewport: Viewport, tag: String, seconds: float = 2.5) -> Dictionary:
	var samples: Array[Dictionary] = []
	await get_tree().process_frame
	var started := Time.get_ticks_usec()
	var previous := started
	var deadline := started + int(clampf(seconds, 0.5, 30.0) * 1000000.0)
	while Time.get_ticks_usec() < deadline and is_instance_valid(viewport):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var sample := _render_info(viewport)
		sample["t_ms"] = float(now - started) / 1000.0
		sample["frame_gap_ms"] = float(now - previous) / 1000.0
		sample["process_cpu_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sample["physics_cpu_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		sample["state"] = str(QuizManager.game_state.game_state)
		samples.append(sample)
		previous = now
	var result := {"tag": tag, "samples": samples, "sample_count": samples.size(),
		"renderer": RenderingServer.get_current_rendering_method(), "quality": GameManager.graphics_quality,
		"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"image_readback_excluded": true,
		"notes": "Wall-clock gaps include frame pacing and rendering. Engine process/physics monitors are CPU observations and can repeat across frames; this is not a GPU timer."}
	for metric: String in ["frame_gap_ms", "process_cpu_ms", "physics_cpu_ms", "draw_calls", "primitives", "objects"]:
		var values: Array[float] = []
		for sample: Dictionary in samples:
			values.append(float(sample[metric]))
		result[metric] = _distribution(values)
	_write(tag + "_performance", result)
	return result


## Captures a real start: menu invokes the real Start handler; direct invokes the
## same state and GameManager entry points; retry invokes the existing HUD retry.
## Does not teleport players, skip helicopter presentation, or force game states.
func run_offline_start(tag: String, players: int, route: String = "menu", mode: String = Constants.MODE_TEN) -> void:
	finished = false
	phase = "starting_" + tag
	report = {"tag": tag, "players": players, "route": route, "mode": mode, "errors": [], "captures": [], "timeline": []}
	if players not in [1, 2] or route not in ["menu", "direct", "retry"] or mode not in [Constants.MODE_TEN, Constants.MODE_ENDLESS, Constants.MODE_TUTORIAL]:
		report.errors.append("Expected players 1/2, route menu/direct/retry, mode TEN_QUESTIONS/ENDLESS/TUTORIAL")
		_finish_sequence(tag)
		return
	var initial_scene := get_tree().current_scene
	if initial_scene == null or (route == "menu" and not initial_scene.has_method("_on_start_pressed")) or (route == "retry" and initial_scene.get_node_or_null("GameplayHUD") == null):
		report.errors.append("Current scene does not support requested start route")
		_finish_sequence(tag)
		return
	var initial_scene_id := initial_scene.get_instance_id()
	var tutorial := mode == Constants.MODE_TUTORIAL
	var tutorial_course := GameManager.TUTORIAL_COURSE_SOLO if players == 1 else GameManager.TUTORIAL_COURSE_LOCAL_2P
	if route == "retry" and tutorial and (QuizManager.game_state.mode != Constants.MODE_TUTORIAL or QuizManager.game_state.get_tutorial_course() != tutorial_course):
		report.errors.append("Tutorial retry requires a live tutorial of the same player course; use direct for a fresh course")
		_finish_sequence(tag)
		return
	_save_runtime_settings()
	QuizManager.provider.set("llm_mode", "OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	# start_tutorial() owns its mode and backs up the previous normal selection.
	# Preserve an existing tutorial for HUD restart_tutorial() on the retry route.
	gs.mode = mode if not tutorial or route == "retry" else Constants.MODE_TEN
	gs.subject = "算数"
	gs.grade = 3
	gs.difficulty = "普通"
	_state_events.clear()
	_start_usec = Time.get_ticks_usec()
	if not gs.state_changed.is_connected(_record_state):
		gs.state_changed.connect(_record_state)
	_record_state(str(gs.game_state))
	if route == "menu":
		var preview: Node = _value(initial_scene, "_menu_wall_preview")
		if preview != null:
			preview.call("sync_menu_player_count", players)
		await get_tree().create_timer(0.5).timeout
		var stage := _stage_for(initial_scene)
		if stage != null:
			report.captures.append(await snapshot(stage, initial_scene.get_viewport(), tag + "_menu"))
		if tutorial:
			initial_scene.call("_start_tutorial_game", tutorial_course)
		else:
			initial_scene.call("_on_start_pressed")
	elif route == "retry":
		initial_scene.get_node("GameplayHUD").call("_retry_game")
	else:
		if tutorial:
			gs.start_tutorial(tutorial_course)
		else:
			gs.start_game()
		GameManager.start_game()
	var deadline := Time.get_ticks_msec() + 90000
	var capture_keys: Dictionary = {}
	var last_capture_ms: int = 0
	var did_trigger := false
	var saw_new_world := false
	var max_departure_count := 0
	var max_arrival_count := 0
	var saw_departure := false
	var saw_arrival := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null:
			continue
		var is_initial_scene := scene.get_instance_id() == initial_scene_id
		if route != "menu" and is_initial_scene:
			continue
		var state := str(gs.game_state)
		var heli := _helicopter_info(scene)
		var lock := _presentation_locked(scene)
		var key := str(heli.get("phase", "none")) if is_initial_scene and route == "menu" else state + ("_arrival" if lock else "")
		phase = key
		var now := Time.get_ticks_msec()
		if not report.timeline.is_empty() and str(report.timeline.back().key) == key:
			pass
		else:
			report.timeline.append({"t_ms": float(Time.get_ticks_usec() - _start_usec) / 1000.0, "key": key, "state": state, "helicopters": heli})
		if is_initial_scene and route == "menu":
			if str(heli.get("phase", "idle")) not in ["none", "idle", "complete", "waiting_camera"]:
				saw_departure = true
				max_departure_count = maxi(max_departure_count, int(heli.get("count", 0)))
		else:
			if scene.get_node_or_null("StageEnvironment") == null:
				continue
			saw_new_world = true
			if lock:
				saw_arrival = true
				max_arrival_count = maxi(max_arrival_count, int(heli.get("count", 0)))
			if state == Constants.STATE_WAITING_START and not lock and not _construction_locked(scene) and not SceneTransition.is_transitioning() and not did_trigger:
				# trigger_start is the normal Enter handler's model command, only
				# after both real presentation gates report unlocked.
				did_trigger = true
				gs.trigger_start()
		var capture_key := key
		# Two times per moving flight provide sequence evidence, not just an endpoint.
		if state == Constants.STATE_FLYOVER:
			capture_key += "_" + str(mini(2, int(float(gs.flyover_timer) / 1.3)))
		elif bool(heli.get("active", false)):
			capture_key += "_" + str(mini(2, int(float(heli.get("elapsed", 0.0)) / 1.5)))
		if not capture_keys.has(capture_key) and now - last_capture_ms >= 700 and not SceneTransition.is_transitioning():
			var stage := _stage_for(scene)
			if stage != null:
				capture_keys[capture_key] = true
				report.captures.append(await snapshot(stage, scene.get_viewport(), tag + "_" + capture_key))
				last_capture_ms = Time.get_ticks_msec()
		if saw_new_world and state == Constants.STATE_PLAYING and not SceneTransition.is_transitioning():
			var stage := _stage_for(scene)
			report.captures.append(await snapshot(stage, scene.get_viewport(), tag + "_playing_start"))
			report["performance"] = await sample_performance(stage.get_viewport(), tag + "_playing", 2.5)
			report.captures.append(await snapshot(stage, scene.get_viewport(), tag + "_playing_sample_end"))
			report["sample_end_state"] = str(gs.game_state)
			if gs.game_state != Constants.STATE_PLAYING:
				report.errors.append("Game left PLAYING during performance window")
			elif capture_matrix_after_start:
				report["visual_matrix"] = await capture_visual_matrix(tag + "_matrix")
				if not bool(report.visual_matrix.get("passed_matrix", false)):
					report.errors.append("Static light/quality matrix reported an error")
			break
	if gs.state_changed.is_connected(_record_state):
		gs.state_changed.disconnect(_record_state)
	report["states"] = _state_events.duplicate(true)
	report["departure_observed"] = saw_departure
	report["departure_helicopters"] = max_departure_count
	report["arrival_observed"] = saw_arrival
	report["arrival_helicopters"] = max_arrival_count
	report["new_game_world_observed"] = saw_new_world
	report["provider_source"] = str(QuizManager.provider.get("llm_mode"))
	report["settings_unchanged"] = _settings_digest() == str(_saved_settings.get("settings_digest", ""))
	var expected := [Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING]
	if tutorial:
		expected = [Constants.STATE_WAITING_START, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING]
	report["expected_states"] = expected
	var matched := 0
	for event: Dictionary in _state_events:
		if matched < expected.size() and str(event.state) == str(expected[matched]):
			matched += 1
	if matched != expected.size():
		report.errors.append("Missing ordered state sequence: " + " > ".join(expected))
	if not report.has("performance"):
		report.errors.append("Timed out before settled PLAYING sample")
	if route == "menu" and not tutorial and (not saw_departure or max_departure_count != players):
		report.errors.append("Menu departure not observed for requested player count")
	if route != "retry" and (not saw_arrival or max_arrival_count != players):
		report.errors.append("Gameplay arrival not observed for requested player count")
	if not report.settings_unchanged:
		report.errors.append("Stored settings changed during probe")
	if return_to_menu_after_run:
		var scene := get_tree().current_scene
		var hud := scene.get_node_or_null("GameplayHUD") if scene != null else null
		if hud != null and not SceneTransition.is_transitioning():
			hud.call("_return_to_main_menu")
			var return_deadline := Time.get_ticks_msec() + 20000
			var departed_scene_id := scene.get_instance_id()
			while get_tree().current_scene != null and get_tree().current_scene.get_instance_id() == departed_scene_id and Time.get_ticks_msec() < return_deadline:
				await get_tree().process_frame
			while SceneTransition.is_transitioning() and Time.get_ticks_msec() < return_deadline:
				await get_tree().process_frame
			report["returned_to_menu"] = get_tree().current_scene != null and get_tree().current_scene.has_method("_on_start_pressed")
	_finish_sequence(tag)


## Static visual comparison at the existing real camera/player placement. The
## game or menu-preview updater is suspended so the player cannot reach a wrong
## door while PNGs are encoded. These samples must not be used as gameplay CPU
## performance evidence. Light, viewport quality and process state are restored.
func capture_visual_matrix(tag: String, qualities: Array = ["low", "balanced", "high"], phases: Dictionary = {"day": 0.25, "sunset": 0.49, "night": 0.75}) -> Dictionary:
	var result := {"tag": tag, "captures": [], "errors": [], "static_visual_comparison": true,
		"gameplay_performance_evidence": false, "changes_saved_to_user_settings": false}
	var scene := get_tree().current_scene
	var stage := _stage_for(scene)
	if scene == null or stage == null or SceneTransition.is_transitioning():
		result.errors.append("Visual matrix requires an uncovered live menu or game stage")
		_write(tag + "_matrix", result)
		return result
	var is_game := scene.get_node_or_null("StageEnvironment") == stage
	var state := str(QuizManager.game_state.game_state)
	if is_game and (state not in [Constants.STATE_WAITING_START, Constants.STATE_PLAYING] or _presentation_locked(scene) or _construction_locked(scene)):
		result.errors.append("Visual matrix requires unlocked WAITING_START or PLAYING; flight/countdown is observed separately")
		_write(tag + "_matrix", result)
		return result
	for quality: Variant in qualities:
		if str(quality) not in ["low", "balanced", "high"]:
			result.errors.append("Unsupported quality " + str(quality))
	if not result.errors.is_empty():
		_write(tag + "_matrix", result)
		return result
	var updater: Node = scene if is_game else _value(scene, "_menu_wall_preview")
	var weather: Node = _value(stage, "weather_cycle")
	if updater == null or weather == null:
		result.errors.append("Missing scene updater or WeatherCycle")
		_write(tag + "_matrix", result)
		return result
	var render_viewport := stage.get_viewport()
	var saved_quality := str(GameManager.graphics_quality)
	var saved_phase := float(_value(weather, "day_phase", 0.25))
	var saved_forced := bool(_value(weather, "_forced", false))
	var saved_process := updater.is_processing()
	var saved_physics := updater.is_physics_processing()
	var saved_digest := _settings_digest()
	var saved_viewport: Dictionary = {}
	for property: String in ["scaling_3d_mode", "scaling_3d_scale", "msaa_3d", "msaa_2d", "screen_space_aa", "use_taa", "use_debanding", "mesh_lod_threshold", "anisotropic_filtering_level", "texture_mipmap_bias"]:
		saved_viewport[property] = render_viewport.get(property)
	updater.set_process(false)
	updater.set_physics_process(false)
	result["frozen_state"] = state
	result["frozen_updater"] = str(updater.get_path())
	result["game_before"] = _game_info()
	for quality: Variant in qualities:
		# The normal setter persists user settings. The fixture deliberately uses
		# an in-memory assignment plus the same renderer/environment entry points.
		GameManager.graphics_quality = str(quality)
		GraphicsQuality.apply_text_viewport(render_viewport, str(quality))
		stage.call("apply_graphics_quality", str(quality))
		for light_name: Variant in phases:
			phase = "matrix_" + str(quality) + "_" + str(light_name)
			weather.call("force_day_phase", float(phases[light_name]))
			for frame: int in range(10):
				await get_tree().process_frame
			var capture := await snapshot(stage, scene.get_viewport(), tag + "_" + str(quality) + "_" + str(light_name))
			capture["matrix_light"] = str(light_name)
			capture["matrix_quality"] = str(quality)
			result.captures.append(capture)
			if capture.get("passed_structural") == false:
				result.errors.append("Structural failure: " + str(capture.tag))
	GameManager.graphics_quality = saved_quality
	GraphicsQuality.apply_text_viewport(render_viewport, saved_quality)
	stage.call("apply_graphics_quality", saved_quality)
	for property: String in saved_viewport:
		render_viewport.set(property, saved_viewport[property])
	if saved_forced:
		weather.call("force_day_phase", saved_phase)
	else:
		weather.call("clear_force")
	result["game_after"] = _game_info()
	updater.set_process(saved_process)
	updater.set_physics_process(saved_physics)
	result["settings_unchanged"] = _settings_digest() == saved_digest
	result["quality_restored"] = str(GameManager.graphics_quality) == saved_quality
	result["state_preserved"] = str(QuizManager.game_state.game_state) == state
	result["gameplay_state_unchanged"] = result.game_before == result.game_after
	result["weather_restore"] = _weather_info(stage)
	if not result.settings_unchanged or not result.state_preserved or not result.gameplay_state_unchanged or not result.quality_restored:
		result.errors.append("Visual matrix did not preserve state/settings")
	result["passed_matrix"] = result.errors.is_empty()
	_write(tag + "_matrix", result)
	return result


## Convenience wrapper for call_deferred + finished/report polling in game_eval.
func run_visual_matrix(tag: String) -> void:
	finished = false
	phase = "matrix_" + tag
	report = await capture_visual_matrix(tag)
	_finish_sequence(tag)


## For root-triggered shark/helipad/retry/mode events. It never triggers an action.
func watch_current(tag: String, seconds: float = 12.0, interval: float = 1.5) -> void:
	finished = false
	phase = "watching_" + tag
	report = {"tag": tag, "captures": [], "errors": [], "passive_observation": true}
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var next_capture := 0
	var index := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if Time.get_ticks_msec() < next_capture:
			continue
		var scene := get_tree().current_scene
		var stage := _stage_for(scene)
		if stage != null and not SceneTransition.is_transitioning():
			report.captures.append(await snapshot(stage, scene.get_viewport(), "%s_%02d" % [tag, index]))
			index += 1
		next_capture = Time.get_ticks_msec() + int(maxf(interval, 0.25) * 1000.0)
	_finish_sequence(tag)


func restore_runtime_settings() -> Dictionary:
	if _saved_settings.is_empty():
		return {"restored": false, "reason": "No test configuration saved"}
	# Cancel/end while still offline; otherwise end_round may request explanations.
	QuizManager.provider.set("llm_mode", "OFFLINE")
	QuizManager.provider.end_round()
	for key: String in ["num_players", "mode", "subject", "grade", "difficulty", "llm_mode"]:
		QuizManager.game_state.set(key, _saved_settings[key])
	QuizManager.provider.set("llm_mode", _saved_settings.provider_source)
	var result := {"restored": true, "provider_round_active": _value(QuizManager.provider, "is_active_round", false), "settings_unchanged": _settings_digest() == str(_saved_settings.settings_digest)}
	_saved_settings.clear()
	return result


func _inspect_city(city: Node3D, camera: Camera3D) -> Dictionary:
	if city == null:
		return {"missing": true}
	var instances := city.find_children("*", "MeshInstance3D", true, false)
	var result := {"path": str(city.get_path()), "mesh_count": 0, "source_triangles": 0,
		"surfaces": 0, "corridor_intersecting_triangles": 0, "collision_bodies": city.find_children("*", "CollisionObject3D", true, false).size(),
		"local_origin": _v3(city.position), "global_origin": _v3(city.global_position), "meshes": [], "materials": [],
		"visibility_note": "Projection and tree visibility are structural evidence; screenshot review is required for actual occlusion and legibility."}
	var bounds := AABB()
	var first := true
	var materials: Dictionary = {}
	for node: Node in instances:
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var world_bounds: AABB = instance.global_transform * instance.get_aabb()
		bounds = world_bounds if first else bounds.merge(world_bounds)
		first = false
		var mesh_data := _mesh_data(instance.mesh)
		var hit_count := _corridor_hits(instance, world_bounds)
		result.mesh_count += 1
		result.source_triangles += int(mesh_data.triangles)
		result.surfaces += instance.mesh.get_surface_count()
		result.corridor_intersecting_triangles += hit_count
		result.meshes.append({"name": str(instance.name), "bounds": _aabb(world_bounds), "triangles": mesh_data.triangles,
			"surfaces": instance.mesh.get_surface_count(), "visible_in_tree": instance.is_visible_in_tree(),
			"corridor_hits": hit_count, "projection": _project_bounds(world_bounds, camera),
			"cast_shadow": instance.cast_shadow, "lod_bias": instance.lod_bias})
		for surface: int in range(instance.mesh.get_surface_count()):
			var mat := instance.get_active_material(surface)
			if mat == null or materials.has(mat.get_instance_id()):
				continue
			materials[mat.get_instance_id()] = true
			var info := {"name": mat.resource_name, "class": mat.get_class()}
			if mat is BaseMaterial3D:
				info["albedo"] = mat.albedo_color.to_html(true)
				info["emission_enabled"] = mat.emission_enabled
				info["emission"] = mat.emission.to_html(true)
				info["emission_energy"] = mat.emission_energy_multiplier
			result.materials.append(info)
	result["bounds"] = _aabb(bounds)
	return result


func _inspect_stands(stage: Node) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var container := stage.get_node_or_null("Grandstands")
	if container == null:
		return results
	for node: Node in container.get_children():
		var stand := node as Node3D
		if stand == null:
			continue
		var bounds := AABB()
		var first := true
		for mesh_node: Node in stand.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_node as MeshInstance3D
			var b: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
		var count := 0
		var row_heights: Dictionary = {}
		var max_top := -INF
		var min_seat := INF
		for batch_node: Node in stand.find_children("*", "MultiMeshInstance3D", true, false):
			var batch := batch_node as MultiMeshInstance3D
			if batch.multimesh == null or batch.multimesh.mesh == null:
				continue
			count += batch.multimesh.instance_count
			for index: int in range(batch.multimesh.instance_count):
				var placed := batch.multimesh.get_instance_transform(index)
				var world_pose := batch.global_transform * placed
				var body_bounds: AABB = world_pose * batch.multimesh.mesh.get_aabb()
				max_top = maxf(max_top, body_bounds.end.y)
				min_seat = minf(min_seat, world_pose.origin.y)
				row_heights[snappedf(placed.origin.y, 0.01)] = true
		var rows: Array = row_heights.keys()
		rows.sort()
		results.append({"name": str(stand.name), "center_x": stand.global_position.x,
			"origin": _v3(stand.global_position), "scale": _v3(stand.scale), "geometry_bounds": _aabb(bounds),
			"geometry_top_y": bounds.end.y, "crowd_count": count, "crowd_row_heights": rows,
			"crowd_seated_top_y": max_top if count > 0 else 0.0, "lowest_seat_y": min_seat if count > 0 else 0.0,
			"crowd_bounds_note": "Rest mesh bounds; shader arm sway/height modulation is not included.",
			"visible_in_tree": stand.is_visible_in_tree()})
	return results


func _mesh_data(mesh: Mesh) -> Dictionary:
	var id := mesh.get_instance_id()
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var data := {"triangles": 0, "surfaces": []}
	for surface: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var primitive: int = (mesh as ArrayMesh).surface_get_primitive_type(surface) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		if primitive == Mesh.PRIMITIVE_TRIANGLES:
			data.triangles += floori(float(count) / 3.0)
		data.surfaces.append({"vertices": vertices, "indices": indices, "primitive": primitive})
	_mesh_cache[id] = data
	return data


func _corridor_hits(instance: MeshInstance3D, bounds: AABB) -> int:
	var half := float(constraints.get("corridor_half_width", 70.0))
	var start_z := float(constraints.get("corridor_start_z", -150.0))
	if bounds.position.x >= half or bounds.end.x <= -half or bounds.end.z <= start_z:
		return 0
	var hit_count := 0
	var data := _mesh_data(instance.mesh)
	for surface: Dictionary in data.surfaces:
		if int(surface.primitive) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var vertices: PackedVector3Array = surface.vertices
		var indices: PackedInt32Array = surface.indices
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for tri: int in range(0, count - 2, 3):
			var polygon: Array[Vector2] = []
			for corner: int in range(3):
				var vi := int(indices[tri + corner]) if not indices.is_empty() else tri + corner
				var point: Vector3 = instance.global_transform * vertices[vi]
				polygon.append(Vector2(point.x, point.z))
			# Clip each triangle to the open navigation corridor in XZ. Unlike a
			# vertex-only test this also catches triangles that bridge the corridor.
			polygon = _clip_polygon(polygon, 0, -half + 0.001, true)
			polygon = _clip_polygon(polygon, 0, half - 0.001, false)
			polygon = _clip_polygon(polygon, 1, start_z + 0.001, true)
			if not polygon.is_empty():
				hit_count += 1
	return hit_count


func _clip_polygon(points: Array[Vector2], axis: int, boundary: float, keep_greater: bool) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if points.is_empty():
		return output
	var previous: Vector2 = points.back()
	var previous_inside: bool = previous[axis] >= boundary if keep_greater else previous[axis] <= boundary
	for current: Vector2 in points:
		var inside: bool = current[axis] >= boundary if keep_greater else current[axis] <= boundary
		if inside != previous_inside:
			var denominator: float = current[axis] - previous[axis]
			if absf(denominator) > 0.000001:
				output.append(previous.lerp(current, (boundary - previous[axis]) / denominator))
		if inside:
			output.append(current)
		previous = current
		previous_inside = inside
	return output


func _project_bounds(bounds: AABB, camera: Camera3D) -> Dictionary:
	if camera == null:
		return {"camera_missing": true}
	var rect := Rect2()
	var first := true
	var front_count := 0
	var inside_count := 0
	var size := camera.get_viewport().get_visible_rect().size
	for index: int in range(9):
		var point := bounds.get_endpoint(index) if index < 8 else bounds.get_center()
		if camera.is_position_behind(point):
			continue
		front_count += 1
		var uv := camera.unproject_position(point) / size
		if Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv):
			inside_count += 1
		rect = Rect2(uv, Vector2.ZERO) if first else rect.expand(uv)
		first = false
	return {"sample_points_in_front": front_count, "sample_points_in_view": inside_count,
		"rect_uv": [_v2(rect.position), _v2(rect.end)], "center_distance": camera.global_position.distance_to(bounds.get_center())}


func _question_info(scene: Node, camera: Camera3D) -> Dictionary:
	var wall: Node = _value(scene, "_question_framing_wall")
	if wall == null or camera == null:
		return {"active_wall": false}
	var label: Label3D = _value(wall, "gameplay_question_label")
	if label == null:
		return {"active_wall": true, "label_missing": true}
	var projection := _project_bounds(label.global_transform * label.get_aabb(), camera)
	return {"active_wall": true, "text": label.text, "visible_in_tree": label.is_visible_in_tree(), "projection": projection}


func _helicopter_info(scene: Node) -> Dictionary:
	var director: Node = _value(scene, "_helicopter_arrival_director")
	var preview: Node = _value(scene, "_menu_wall_preview")
	if director == null and preview != null:
		director = _value(preview, "_menu_start_departure")
	if director == null:
		return {"phase": "none", "count": 0, "active": false}
	var helicopters: Array = _value(director, "_helicopters", [])
	var placements: Array[Dictionary] = []
	for info: Dictionary in helicopters:
		var entry := {"player_index": info.get("player_index", -1), "captured": info.get("captured", false)}
		for key: Variant in info:
			if info[key] is Node3D and is_instance_valid(info[key]):
				entry[str(key)] = _v3((info[key] as Node3D).global_position)
		placements.append(entry)
	return {"phase": str(_value(director, "_phase", "unknown")), "elapsed": float(_value(director, "_phase_elapsed", 0.0)),
		"count": helicopters.size(), "active": bool(director.call("is_active")) if director.has_method("is_active") else false, "placements": placements}


func _stage_for(scene: Node) -> Node:
	if scene == null:
		return null
	var stage := scene.get_node_or_null("StageEnvironment")
	if stage != null:
		return stage
	var preview: Node = _value(scene, "_menu_wall_preview")
	return preview.call("get_stage_environment") if preview != null and preview.has_method("get_stage_environment") else null


func _camera_info(camera: Camera3D) -> Dictionary:
	if camera == null:
		return {"missing": true}
	return {"position": _v3(camera.global_position), "rotation_degrees": _v3(camera.global_rotation_degrees),
		"fov": camera.fov, "near": camera.near, "far": camera.far, "current": camera.current, "projection": camera.projection}


func _render_info(viewport: Viewport) -> Dictionary:
	return {"objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"fps_monitor": Engine.get_frames_per_second(), "process_frame": Engine.get_process_frames(),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))}


func _game_info() -> Dictionary:
	var gs := QuizManager.game_state
	return {"players": gs.num_players, "mode": gs.mode, "state": gs.game_state, "source": gs.llm_mode,
		"provider_source": str(QuizManager.provider.get("llm_mode")), "wall_index": gs.current_wall_index,
		"world_scroll_z": gs.world_scroll_z, "p1_alive": gs.p1_alive, "p2_alive": gs.p2_alive,
		"p1_position": [gs.player_x, gs.player_y, gs.player_local_z],
		"p2_position": [gs.player2_x, gs.player2_y, gs.player2_local_z] if gs.num_players == 2 else []}


func _weather_info(stage: Node) -> Dictionary:
	var weather: Node = _value(stage, "weather_cycle")
	return {"day_phase": _value(weather, "day_phase", -1.0), "night_amount": _value(weather, "night_amount", -1.0), "forced": _value(weather, "_forced", false)}


func _presentation_locked(scene: Node) -> bool:
	return bool(scene.call("is_start_presentation_locked")) if scene.has_method("is_start_presentation_locked") else false


func _construction_locked(scene: Node) -> bool:
	return bool(scene.call("is_preload_construction_locked")) if scene.has_method("is_preload_construction_locked") else false


func _record_state(state: String) -> void:
	_state_events.append({"state": state, "t_ms": float(Time.get_ticks_usec() - _start_usec) / 1000.0})


func _save_runtime_settings() -> void:
	if not _saved_settings.is_empty():
		return
	for key: String in ["num_players", "mode", "subject", "grade", "difficulty", "llm_mode"]:
		_saved_settings[key] = QuizManager.game_state.get(key)
	_saved_settings["provider_source"] = QuizManager.provider.get("llm_mode")
	_saved_settings["settings_digest"] = _settings_digest()


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


func _finish_sequence(tag: String) -> void:
	report["passed_sequence"] = report.errors.is_empty()
	report["visual_review_required"] = true
	report["runtime_settings_retained_for_inspection"] = not _saved_settings.is_empty()
	_write(tag + "_sequence", report)
	phase = "finished"
	finished = true
	print("SANTORINI_ENVIRONMENT_SEQUENCE " + JSON.stringify({"tag": tag, "passed_sequence": report.passed_sequence, "errors": report.errors, "captures": report.captures.size()}))


func _value(object: Object, property: String, fallback: Variant = null) -> Variant:
	if not is_instance_valid(object):
		return fallback
	var id := object.get_instance_id()
	if not _properties.has(id):
		var names: Dictionary = {}
		for item: Dictionary in object.get_property_list():
			names[str(item.name)] = true
		_properties[id] = names
	return object.get(property) if _properties[id].has(property) else fallback


func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	values.sort()
	var total := 0.0
	for value: float in values:
		total += value
	return {"count": values.size(), "min": values.front(), "mean": total / values.size(), "max": values.back(),
		"p50": values[clampi(ceili(values.size() * 0.50) - 1, 0, values.size() - 1)],
		"p95": values[clampi(ceili(values.size() * 0.95) - 1, 0, values.size() - 1)],
		"p99": values[clampi(ceili(values.size() * 0.99) - 1, 0, values.size() - 1)]}


func _aabb(bounds: AABB) -> Dictionary:
	return {"min": _v3(bounds.position), "max": _v3(bounds.end), "size": _v3(bounds.size)}


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _v2(value: Vector2) -> Array:
	return [value.x, value.y]


func _tag(value: String) -> String:
	return value.validate_filename().replace(" ", "_")


func _ensure_output() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))


func _write(tag: String, data: Dictionary) -> void:
	_ensure_output()
	var file := FileAccess.open(OUTPUT + _tag(tag) + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Santorini probe cannot write artifact: " + tag)
		return
	file.store_string(JSON.stringify(data, "\t"))
