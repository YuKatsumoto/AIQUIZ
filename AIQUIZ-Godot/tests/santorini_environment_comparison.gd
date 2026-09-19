extends Node

## Attach to SceneTree.root, then call_deferred("run_comparison", "final_p2_ab").
## A1 old city/stadium/crowd -> B current environment -> A2 old again.
## Static rendered comparison only: gameplay update is temporarily suspended.
## Both revisions coexist in memory; this is not a memory comparison or a
## measurement of normal active-gameplay CPU. No user settings are persisted.

const OUTPUT := "res://artifacts/santorini_renovation/"
const CITY_BEFORE := OUTPUT + "harbor_city_backdrop.gd.before"
const CROWD_BEFORE := OUTPUT + "grandstand_crowd.gd.before"
const STAGE_BEFORE := OUTPUT + "stage_environment.gd.before"
const ProbeScript := preload("res://tests/santorini_environment_runtime.gd")
var finished := false
var phase := "idle"
var report: Dictionary = {}
var _world: Node
var _city: Node3D
var _stands: Node3D
var _weather: Node
var _baseline: Node3D
var _probe: Node
var _saved: Dictionary = {}
var _restored := true


func run_comparison(tag: String) -> void:
	_restore()
	_saved.clear()
	finished = false
	phase = "preparing"
	report = {"tag": tag, "errors": [], "windows": [], "kind": "STATIC_RENDER_COMPARISON",
		"active_gameplay_cpu_evidence": false, "memory_comparison": false,
		"notes": "A1/B/A2 share one camera, quality, weather and frozen world. Both revisions remain resident; shader time and unrelated rendering continue. Each measured window excludes PNG readback/encoding."}
	_world = get_tree().current_scene
	if _world == null or _world.get_node_or_null("StageEnvironment") == null:
		_fail_and_finish(tag, "Requires a live GameWorld")
		return
	var stage := _world.get_node("StageEnvironment")
	_city = stage.get_node_or_null("HarborCityBackdrop") as Node3D
	_stands = stage.get_node_or_null("Grandstands") as Node3D
	_weather = stage.get("weather_cycle")
	var state := str(QuizManager.game_state.game_state)
	if _city == null or _stands == null or _weather == null or _stands.get_child_count() != 2:
		_fail_and_finish(tag, "Requires current town, two stands and WeatherCycle")
		return
	if state not in [Constants.STATE_WAITING_START, Constants.STATE_PLAYING] or _world.call("is_start_presentation_locked") or _world.call("is_preload_construction_locked") or SceneTransition.is_transitioning():
		_fail_and_finish(tag, "Requires unlocked WAITING_START or PLAYING, with transition uncovered")
		return
	if str(QuizManager.provider.get("llm_mode")) != "OFFLINE":
		_fail_and_finish(tag, "Requires an existing OFFLINE test session")
		return
	var viewport := stage.get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null:
		_fail_and_finish(tag, "No live Camera3D")
		return
	# Validate all source artifacts and resources before changing live visibility.
	var old_city_script := _script_from_copy(CITY_BEFORE)
	var old_crowd_script := _script_from_copy(CROWD_BEFORE)
	var stand_pattern := RegEx.new()
	stand_pattern.compile("res://assets/environment/grandstand/[^\"]+\\.glb")
	var stand_match := stand_pattern.search(FileAccess.get_file_as_string(STAGE_BEFORE))
	if old_city_script == null or old_crowd_script == null or stand_match == null:
		_fail_and_finish(tag, "Missing or invalid before-revision source artifacts")
		return
	var old_stand_path := stand_match.get_string()
	var old_stand_scene := load(old_stand_path) as PackedScene
	if old_stand_scene == null:
		_fail_and_finish(tag, "Could not load original stadium GLB")
		return
	_saved = {"world_process": _world.is_processing(), "world_physics": _world.is_physics_processing(),
		"weather_process": _weather.is_processing(), "city_visible": _city.visible, "stands_visible": _stands.visible,
		"quality": str(GameManager.graphics_quality), "camera_transform": camera.global_transform,
		"camera_fov": camera.fov, "camera_far": camera.far, "camera_near": camera.near,
		"settings_digest": _settings_digest(), "game": _game_signature(), "camera": camera,
		"day_phase": float(_weather.get("day_phase")), "weather_forced": bool(_weather.get("_forced"))}
	_restored = false
	_world.set_process(false)
	_world.set_physics_process(false)
	# Stop this weather updater; do not alter its shared clock or forced flag.
	_weather.set_process(false)
	_baseline = Node3D.new()
	_baseline.name = "SantoriniComparisonBaseline"
	_baseline.visible = false
	stage.add_child(_baseline)
	var old_city: Node3D = old_city_script.new()
	old_city.name = "OriginalHarborCityBackdrop"
	_baseline.add_child(old_city)
	old_city.call("build", _weather)
	var old_stands := Node3D.new()
	old_stands.name = "OriginalGrandstands"
	old_stands.transform = _stands.transform
	_baseline.add_child(old_stands)
	var old_crowd_count := 0
	var layouts: Array[Dictionary] = []
	var quality := str(GameManager.graphics_quality)
	var casts_shadows := quality == GraphicsQuality.HIGH and not GraphicsQuality.is_mobile_target()
	for current_node: Node in _stands.get_children():
		var current := current_node as Node3D
		var old := old_stand_scene.instantiate() as Node3D
		old.name = str(current.name)
		old.position = Vector3(-32.0 if current.position.x < 0.0 else 32.0, current.position.y, current.position.z)
		old.rotation = Vector3(0.0, PI if current.position.x < 0.0 else 0.0, 0.0)
		old.scale = current.scale
		old.process_mode = Node.PROCESS_MODE_DISABLED
		old_stands.add_child(old)
		for node: Node in old.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			instance.lod_bias = GraphicsQuality.grandstand_lod_bias(quality)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if bool(stage.get("_include_spectators")) and float(stage.get("_spectator_density")) > 0.0:
			var crowd: Node3D = old_crowd_script.new()
			crowd.name = "Spectators"
			old.add_child(crowd)
			crowd.call("build", float(stage.get("_spectator_density")), 1729 if current.position.x < 0.0 else 7919)
			crowd.call("sync_length_scale", current.scale.z)
			old_crowd_count += int(crowd.get("spectator_count"))
		layouts.append({"name": str(old.name), "old_center_x": old.position.x, "current_center_x": current.position.x,
			"length": current.scale.z * 160.0, "container_transform": str(old_stands.transform)})
	_probe = ProbeScript.new()
	add_child(_probe)
	report.merge({"quality": quality, "renderer": RenderingServer.get_current_rendering_method(), "game": _game_signature(),
		"camera": {"transform": str(camera.global_transform), "fov": camera.fov, "far": camera.far, "near": camera.near},
		"day_phase": _saved.day_phase, "stand_layouts": layouts, "old_crowd_count": old_crowd_count,
		"old_stand_path": old_stand_path, "old_stadium_casts_shadows": casts_shadows,
		"source_hashes": {CITY_BEFORE: FileAccess.get_sha256(CITY_BEFORE), CROWD_BEFORE: FileAccess.get_sha256(CROWD_BEFORE), STAGE_BEFORE: FileAccess.get_sha256(STAGE_BEFORE)}})
	for label: String in ["baseline_a1", "after_b", "baseline_a2"]:
		phase = label
		var show_baseline := label.begins_with("baseline")
		_baseline.visible = show_baseline
		_city.visible = not show_baseline
		_stands.visible = not show_baseline
		for frame: int in range(30):
			await get_tree().process_frame
		var measurement: Dictionary = await _probe.call("sample_performance", viewport, tag + "_" + label, 2.5)
		await RenderingServer.frame_post_draw
		var path := OUTPUT + tag.validate_filename() + "_" + label + ".png"
		var image_error := viewport.get_texture().get_image().save_png(path)
		var invariants := {"camera_unchanged": camera.global_transform.is_equal_approx(_saved.camera_transform) and is_equal_approx(camera.fov, float(_saved.camera_fov)) and is_equal_approx(camera.far, float(_saved.camera_far)) and is_equal_approx(camera.near, float(_saved.camera_near)),
			"quality_unchanged": str(GameManager.graphics_quality) == str(_saved.quality),
			"weather_unchanged": is_equal_approx(float(_weather.get("day_phase")), float(_saved.day_phase)),
			"game_unchanged": _game_signature() == _saved.game, "image_saved": image_error == OK}
		report.windows.append({"label": label, "image": path, "measurement": measurement, "invariants": invariants})
		for key: String in invariants:
			if not bool(invariants[key]):
				report.errors.append(label + ": " + key)
	var first: Dictionary = report.windows[0].measurement.frame_gap_ms
	var after: Dictionary = report.windows[1].measurement.frame_gap_ms
	var last: Dictionary = report.windows[2].measurement.frame_gap_ms
	var baseline_p95 := (float(first.p95) + float(last.p95)) * 0.5
	report["frame_gap_p95_summary"] = {"a1_ms": first.p95, "b_ms": after.p95, "a2_ms": last.p95,
		"baseline_mean_p95_ms": baseline_p95, "after_to_baseline_ratio": float(after.p95) / maxf(baseline_p95, 0.001),
		"baseline_repeat_drift_ratio": absf(float(first.p95) - float(last.p95)) / maxf(baseline_p95, 0.001)}
	_restore()
	report["settings_unchanged"] = _settings_digest() == str(_saved.settings_digest)
	if not report.settings_unchanged:
		report.errors.append("Stored user settings changed during comparison")
	_finish(tag)


func _script_from_copy(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		return null
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	return script if script.reload() == OK else null


func _restore() -> void:
	if _restored:
		return
	_restored = true
	if is_instance_valid(_baseline):
		_baseline.free()
	if is_instance_valid(_probe):
		_probe.queue_free()
	if _saved.is_empty():
		return
	if is_instance_valid(_city):
		_city.visible = bool(_saved.city_visible)
	if is_instance_valid(_stands):
		_stands.visible = bool(_saved.stands_visible)
	var camera: Camera3D = _saved.camera
	if is_instance_valid(camera):
		camera.global_transform = _saved.camera_transform
		camera.fov = float(_saved.camera_fov)
		camera.near = float(_saved.camera_near)
		camera.far = float(_saved.camera_far)
	if is_instance_valid(_weather):
		_weather.set_process(bool(_saved.weather_process))
	if is_instance_valid(_world):
		_world.set_process(bool(_saved.world_process))
		_world.set_physics_process(bool(_saved.world_physics))
	report["baseline_destroyed"] = not is_instance_valid(_baseline)
	report["original_visibility_restored"] = is_instance_valid(_city) and _city.visible == bool(_saved.city_visible) and is_instance_valid(_stands) and _stands.visible == bool(_saved.stands_visible)
	report["process_flags_restored"] = is_instance_valid(_world) and _world.is_processing() == bool(_saved.world_process) and _world.is_physics_processing() == bool(_saved.world_physics)
	report["weather_flags_restored"] = is_instance_valid(_weather) and _weather.is_processing() == bool(_saved.weather_process) and bool(_weather.get("_forced")) == bool(_saved.weather_forced)


func _exit_tree() -> void:
	_restore()


func _game_signature() -> Dictionary:
	var gs := QuizManager.game_state
	return {"state": gs.game_state, "mode": gs.mode, "players": gs.num_players, "world_scroll_z": gs.world_scroll_z,
		"wall_index": gs.current_wall_index, "p1_alive": gs.p1_alive, "p2_alive": gs.p2_alive,
		"p1": [gs.player_x, gs.player_y, gs.player_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_z]}


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


func _fail_and_finish(tag: String, message: String) -> void:
	report.errors.append(message)
	_restore()
	_finish(tag)


func _finish(tag: String) -> void:
	report["passed_comparison"] = report.errors.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + tag.validate_filename() + "_comparison.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	phase = "finished"
	finished = true
	print("SANTORINI_STATIC_COMPARISON " + JSON.stringify({"tag": tag, "passed": report.passed_comparison, "errors": report.errors, "windows": report.windows.size()}))
