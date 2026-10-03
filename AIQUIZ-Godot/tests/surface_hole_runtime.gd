extends Node

## Visual check of the sudden death surface hole (StageEnvironment.set_shaft_hole) and the seaside drain
## (SurfaceDrain) on the real GameWorld (Forward+): a forced local-2P draw puts the Score Tower finale podium
## on the conveyor near the goal, then the hole opens there and the drain erupts on the P1 side.
## Saves PNGs and report.json to artifacts/sudden_death/surface/.
## Godot --path . --script res://tests/surface_hole_bootstrap.gd --fixed-fps 60
## Godot --path . --script res://tests/surface_hole_bootstrap.gd --fixed-fps 60 -- quality=low
## stage=env builds only StageEnvironment (gameplay_build_config) instead of the GameWorld.
## mobile_ocean swaps the ocean to ocean_mobile.gdshader (the LOW/mobile water) for the hole shots.

const OUT_ROOT := "res://artifacts/sudden_death/surface/"
const MOBILE_OCEAN_SHADER: Shader = preload("res://shaders/ocean_mobile.gdshader")
const Layout = preload("res://scripts/world/sudden_death/sudden_death_layout.gd")
const SurfaceDrainScript = preload("res://scripts/world/sudden_death/surface_drain.gd")
const RADIUS: float = Layout.SHAFT_RADIUS
const DECK_DEPTH := 6.0

var quality := "balanced"
var stage_mode := "world"
var mobile_ocean := false
var out := OUT_ROOT
var gs: QuizGameState
var world: Node
var helper: Node
var stage_env: StageEnvironment
var origin := Vector3.ZERO
var camera: Camera3D
var stand_in: Node3D
var checks := 0
var failures: Array[String] = []
var captured: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("quality="): quality = arg.trim_prefix("quality=")
		if arg.begins_with("stage="): stage_mode = arg.trim_prefix("stage=")
		if arg == "mobile_ocean": mobile_ocean = true
	out = OUT_ROOT + quality + ("_" + stage_mode if stage_mode != "world" else "") + ("_mobile" if mobile_ocean else "") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1280, 720)
	if stage_mode == "env":
		await _setup_stage_only()
	else:
		await _setup_world()
	check(stage_env != null, "stage environment present")
	if stage_env == null:
		_finish()
		return
	if mobile_ocean:
		_force_mobile_ocean()
	camera = Camera3D.new()
	camera.name = "SurfaceHoleCamera"
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 3000.0
	get_tree().root.add_child(camera)
	_hide_overlays()
	report["origin"] = origin
	report["quality"] = quality
	report["stage"] = stage_mode
	await _hole_checks()
	await _drain_checks()
	_finish()


# ------------------------------------------------------------------ setup

func _setup_world() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	# Keep the classic draw so the podium stays on the surface for the shots.
	gs.sudden_death_enabled = false
	world = load("res://scenes/game_world.tscn").instantiate()
	if not world.has_method("_debug_force_draw_finish"):
		await _fall_back_to_stage("GameWorld script unavailable")
		return
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await frames(60)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await frames(15)
	world.call("_debug_force_draw_finish")
	if not await until(func() -> bool: return gs.result_presentation_active, 5.0):
		# GameWorld is mid-edit elsewhere (e.g. a dependency does not compile): shoot the stage on its own.
		await _fall_back_to_stage("forced draw did not start the finale")
		return
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 7.6, 12.0)
	await until(func() -> bool: return not SceneTransition.is_transitioning(), 5.0)
	stage_env = world.get_node("StageEnvironment") as StageEnvironment
	origin = ResultCeremonyDirector.stage_origin(gs)
	report["floor"] = {"center_z": stage_env.get_floor_center_z(), "length": stage_env.get_floor_length(),
		"front_z": stage_env.get_floor_center_z() + stage_env.get_floor_length() * 0.5}
	await capture("00_finale_game_camera")


func _fall_back_to_stage(reason: String) -> void:
	push_warning("surface_hole_runtime: %s; using stage=env" % reason)
	report["world_fallback"] = reason
	stage_mode = "env_fallback"
	if world != null:
		if world.is_inside_tree():
			world.get_parent().remove_child(world)
		world.free()
		world = null
	SceneTransition.reveal_current()
	await _setup_stage_only()


func _setup_stage_only() -> void:
	stage_env = StageEnvironment.new()
	stage_env.name = "StageEnvironment"
	get_tree().root.add_child(stage_env)
	stage_env.build(stage_env.gameplay_build_config())
	stage_env.apply_game_config()
	# Same spot as the finale: 20 m short of the conveyor's front end.
	var front := stage_env.get_floor_center_z() + stage_env.get_floor_length() * 0.5
	origin = Vector3(0.0, StageConstants.FLOOR_TOP_Y, front - 20.3)
	await frames(30)


func _force_mobile_ocean() -> void:
	var ocean := stage_env.get_node_or_null("Ocean") as MeshInstance3D
	if ocean == null:
		return
	var material := ShaderMaterial.new()
	material.shader = MOBILE_OCEAN_SHADER
	ocean.material_override = material


func _hide_overlays() -> void:
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false


# ------------------------------------------------------------------ hole

func _hole_checks() -> void:
	# Freeze time so the inactive before/after frames can be compared pixel for pixel.
	Engine.time_scale = 0.0
	var hits_before := _cylinder_hits()
	report["cylinder_hits_before"] = hits_before
	var shots := {
		"above": [Vector3(0.0, 15.0, 11.0), Vector3(0.0, -3.0, 0.0)],
		"overhead": [Vector3(0.4, 24.0, 3.0), Vector3(0.0, -8.0, 0.0)],
		"deck_side": [Vector3(0.0, -DECK_DEPTH + 1.6, 0.0), Vector3(6.0, -DECK_DEPTH + 2.6, 5.0)],
		"deck_up": [Vector3(0.0, -DECK_DEPTH + 1.6, -1.5), Vector3(1.0, 6.0, 3.0)],
		"deck_down": [Vector3(0.0, -DECK_DEPTH + 1.6, 0.0), Vector3(2.0, -30.0, 4.0)],
	}
	_aim("above", shots)
	var inactive_a := await capture("10_above_0_inactive")
	var inactive_b := await capture("10_above_0_inactive_next_frame")
	report["baseline_frame_diff"] = _diff(inactive_a, inactive_b)
	for shot: String in ["overhead", "deck_side", "deck_up", "deck_down"]:
		_aim(shot, shots)
		await capture("1%d_%s_0_inactive" % [shots.keys().find(shot), shot])

	var started := Time.get_ticks_usec()
	stage_env.prepare_shaft_hole()
	report["prepare_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	stage_env.set_shaft_hole(origin, RADIUS, true)
	report["activate_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	var debug := stage_env.get_shaft_hole_debug()
	report["hole_debug_active"] = debug
	check(bool(debug.active), "hole active")
	check((debug.cut_materials as Array).size() >= 4, "floor, return belt, rollers and ocean carry the cut")
	for entry: Dictionary in debug.cut_materials:
		check(bool(entry.variant) and entry.value is Vector4 and is_equal_approx((entry.value as Vector4).z, RADIUS),
			"hole variant and uniform set: %s" % str(entry))
	var floor_material := stage_env.floor_mesh.material_override as ShaderMaterial
	check(floor_material.get_shader_parameter("base_color") != null and floor_material.get_shader_parameter("scroll_sign") != null,
		"floor keeps its belt parameters on the hole variant")
	var ocean_material := (stage_env.get_node("Ocean") as MeshInstance3D).material_override as ShaderMaterial
	check(mobile_ocean or ocean_material.get_shader_parameter("noise_tex") != null, "ocean keeps its noise textures on the hole variant")
	report["cylinder_hits_active"] = _cylinder_hits()
	check(not str(debug.hidden).contains("FarSea"), "far-sea ring backdrop stays visible %s" % str(debug.hidden))
	if stage_env.get_node_or_null("WaterfrontInfrastructure") != null:
		check(str(debug.hidden).contains("Seabed"), "seabed under the shaft hidden %s" % str(debug.hidden))
	var cut_by_shader := ["StageEnvironment/Floor", "StageEnvironment/ConveyorReturnBelt", "StageEnvironment/Ocean",
		"StageEnvironment/ConveyorRollerFront", "StageEnvironment/ConveyorRollerBack"]
	for hit: Dictionary in report["cylinder_hits_active"]:
		var path := String(hit.path)
		var at := path.find("StageEnvironment/")
		if at >= 0:
			check(path.substr(at) in cut_by_shader, "stage piece inside the shaft is cut or hidden: " + path)
	for shot: String in shots.keys():
		_aim(shot, shots)
		await capture("1%d_%s_1_hole" % [shots.keys().find(shot), shot])
	stand_in = _make_stand_in()
	get_tree().root.add_child(stand_in)
	for shot: String in shots.keys():
		_aim(shot, shots)
		await capture("1%d_%s_2_shaft" % [shots.keys().find(shot), shot])
	stand_in.queue_free()
	stand_in = null

	stage_env.set_shaft_hole(origin, RADIUS, false)
	debug = stage_env.get_shaft_hole_debug()
	report["hole_debug_inactive"] = debug
	check(not bool(debug.active) and (debug.hidden as Array).is_empty(), "hole inactive restores the stage")
	for entry: Dictionary in debug.cut_materials:
		check(not bool(entry.variant) and entry.value == null, "original shader back, no hole parameter: %s" % str(entry))
	_aim("above", shots)
	await frames(2)
	var inactive_after := await capture("10_above_3_inactive_again")
	var diff := _diff(inactive_a, inactive_after)
	report["inactive_before_after_diff"] = diff
	check(int(diff.changed) <= int((report["baseline_frame_diff"] as Dictionary).changed) + 4,
		"inactive frame matches the frame before the hole (%s, baseline %s)" % [str(diff), str(report["baseline_frame_diff"])])
	Engine.time_scale = 1.0


func _aim(shot: String, shots: Dictionary) -> void:
	var pair: Array = shots[shot]
	var eye: Vector3 = origin + (pair[0] as Vector3)
	var target: Vector3 = origin + (pair[1] as Vector3)
	_look(eye, target)


func _look(eye: Vector3, target: Vector3) -> void:
	var direction := (target - eye).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	camera.global_transform = Transform3D(Basis.looking_at(direction, up), eye)
	camera.make_current()


## Every visible mesh that reaches into the shaft cylinder below the floor top.
func _cylinder_hits() -> Array:
	var hits: Array = []
	var top := StageConstants.FLOOR_TOP_Y
	var center := Vector2(origin.x, origin.z)
	for node: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree() or geometry == camera:
			continue
		var bounds: AABB = geometry.global_transform * geometry.get_aabb()
		if bounds.position.y >= top - 0.001:
			continue
		var nearest := Vector2(clampf(center.x, bounds.position.x, bounds.end.x), clampf(center.y, bounds.position.z, bounds.end.z))
		if nearest.distance_to(center) >= RADIUS:
			continue
		if geometry is MeshInstance3D and not StageEnvironment._mesh_reaches_disc(geometry as MeshInstance3D, center, RADIUS):
			continue
		hits.append({
			"path": String(get_tree().root.get_path_to(geometry)),
			"class": geometry.get_class(),
			"y": [snappedf(bounds.position.y, 0.01), snappedf(bounds.end.y, 0.01)],
			"x": [snappedf(bounds.position.x, 0.01), snappedf(bounds.end.x, 0.01)],
			"z": [snappedf(bounds.position.z, 0.01), snappedf(bounds.end.z, 0.01)],
		})
	return hits


## Test-only stand-in for ShaftDescent: inward wall with lamp bands, the collar ring and a deck.
func _make_stand_in() -> Node3D:
	var root := Node3D.new()
	root.name = "ShaftStandIn"
	var wall := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = RADIUS
	tube.bottom_radius = RADIUS
	tube.height = 60.0
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 64
	tube.rings = 12
	wall.mesh = tube
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.42, 0.41, 0.39)
	concrete.roughness = 0.9
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall.material_override = concrete
	wall.position = origin + Vector3(0.0, -30.0, 0.0)
	root.add_child(wall)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.65, 0.12)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.65, 0.12)
	lamp.emission_energy_multiplier = 3.0
	for level in range(1, 12):
		for quarter in range(4):
			var angle := float(quarter) * PI * 0.5
			var bulb := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.4, 0.3)
			bulb.mesh = box
			bulb.material_override = lamp
			bulb.position = origin + Vector3(cos(angle) * (RADIUS - 0.2), -float(level) * 5.0 + 2.0, sin(angle) * (RADIUS - 0.2))
			root.add_child(bulb)
	var collar := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS
	ring.outer_radius = RADIUS + 0.6
	ring.rings = 64
	ring.ring_segments = 8
	collar.mesh = ring
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.85, 0.7, 0.1)
	steel.metallic = 0.4
	steel.roughness = 0.5
	collar.material_override = steel
	collar.scale = Vector3(1.0, 0.12, 1.0)
	collar.position = origin + Vector3(0.0, 0.01, 0.0)
	root.add_child(collar)
	var deck := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Layout.DECK_RADIUS
	disc.bottom_radius = Layout.DECK_RADIUS
	disc.height = 0.3
	disc.radial_segments = 48
	deck.mesh = disc
	var grate := StandardMaterial3D.new()
	grate.albedo_color = Color(0.25, 0.26, 0.27)
	grate.metallic = 0.6
	grate.roughness = 0.5
	deck.material_override = grate
	deck.position = origin + Vector3(0.0, -DECK_DEPTH - 0.15, 0.0)
	root.add_child(deck)
	var bottom := MeshInstance3D.new()
	var cap := CylinderMesh.new()
	cap.top_radius = RADIUS
	cap.bottom_radius = RADIUS
	cap.height = 0.1
	bottom.mesh = cap
	var black := StandardMaterial3D.new()
	black.albedo_color = Color.BLACK
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bottom.material_override = black
	bottom.position = origin + Vector3(0.0, -59.5, 0.0)
	root.add_child(bottom)
	return root


# ------------------------------------------------------------------ drain

func _drain_checks() -> void:
	var drain: SurfaceDrainScript = SurfaceDrainScript.new()
	drain.name = "SurfaceDrainUnderTest"
	(world if world != null else get_tree().root).add_child(drain)
	var setup_started := Time.get_ticks_usec()
	drain.setup(quality)
	report["drain_setup_ms"] = float(Time.get_ticks_usec() - setup_started) / 1000.0
	var snapshot := drain.get_debug_snapshot()
	check(not drain.visible and not drain.is_erupting(), "drain hidden until placed")
	drain.place(origin, 1)
	snapshot = drain.get_debug_snapshot()
	report["drain_placed"] = _plain(snapshot)
	var mouth := drain.mouth_position()
	check(mouth.x > StageConstants.FLOOR_HALF_WIDTH and absf(mouth.z - origin.z) < 0.01 and mouth.y < origin.y,
		"P1 drain mouth in the +X pier wall beside the podium %s" % str(mouth))
	var front_eye := origin + Vector3(0.0, 6.0, 10.0)
	var front_target := origin + Vector3(0.0, 3.0, 0.0)
	var loser_target := origin + Vector3(4.5, 3.0, 0.0)
	var sea_eye := origin + Vector3(21.0, 1.0, 13.0)
	var sea_target := mouth + Vector3(0.0, 2.5, 0.0)
	var close_eye := mouth + Vector3(5.5, 0.6, 4.5)
	_look(front_eye, front_target)
	await capture("30_drain_idle_front")
	_look(sea_eye, sea_target)
	await capture("31_drain_idle_sea")
	_look(close_eye, mouth)
	await capture("32_drain_idle_close")

	var shakes: Array = []
	_look(front_eye, front_target)
	await frames(5)
	# The very first eruption: wall-clock frame times of its first frames (pipelines meet the effect here).
	var first_frames: Array[float] = []
	var erupt_started := Time.get_ticks_usec()
	drain.erupt()
	report["first_erupt_call_ms"] = float(Time.get_ticks_usec() - erupt_started) / 1000.0
	var frame_mark := Time.get_ticks_usec()
	for _frame in range(8):
		await RenderingServer.frame_post_draw
		var frame_now := Time.get_ticks_usec()
		first_frames.append(snappedf(float(frame_now - frame_mark) / 1000.0, 0.01))
		frame_mark = frame_now
	report["first_erupt_frames_ms"] = first_frames
	drain.clear()
	drain.place(origin, 1)
	await _erupt_and_capture(drain, "40_front", [0.06, 0.18, 0.34, 0.6, 1.0, 1.4, 1.9, 2.8], shakes)
	report["shake_curve"] = shakes
	check(not drain.is_erupting(), "eruption settles")
	check(drain.camera_shake() == 0.0, "no shake after the eruption")
	report["drain_arc"] = _plain({"mouth": drain.mouth_position(), "apex": drain.column_point(0.8),
		"tip": drain.column_point(1.0), "quarter": drain.column_point(0.25)})
	_look(front_eye, loser_target)
	await _erupt_and_capture(drain, "50_front_loser", [0.3, 0.8, 1.5], [])
	_look(origin + Vector3(0.0, 6.0, 16.0), origin + Vector3(3.0, 4.0, 0.0))
	await _erupt_and_capture(drain, "55_front_wide", [0.6, 1.1], [])
	_look(sea_eye, sea_target)
	await _erupt_and_capture(drain, "60_sea", [0.08, 0.3, 0.7, 1.1, 1.6, 2.4], [])
	_look(close_eye, mouth + Vector3(0.0, 1.5, 0.0))
	await _erupt_and_capture(drain, "70_close", [0.05, 0.12, 0.4, 2.0], [])

	# Frame times through one eruption with nothing saved (front camera).
	_look(front_eye, front_target)
	await frames(10)
	var times: Array[float] = []
	var quiet: Array[float] = []
	var last := Time.get_ticks_usec()
	for _frame in range(30):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		quiet.append(float(now - last) / 1000.0)
		last = now
	drain.erupt()
	last = Time.get_ticks_usec()
	while drain.is_erupting():
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	quiet.sort()
	report["eruption_frame_ms"] = {"frames": times.size(), "p50": snappedf(times[times.size() / 2], 0.01),
		"p95": snappedf(times[int(times.size() * 0.95)], 0.01), "max": snappedf(times[times.size() - 1], 0.01),
		"quiet_p50": snappedf(quiet[quiet.size() / 2], 0.01)}

	drain.clear()
	check(not drain.visible and not drain.is_erupting(), "clear hides the drain")
	drain.place(origin, -1)
	var mouth_p2 := drain.mouth_position()
	check(mouth_p2.x < -StageConstants.FLOOR_HALF_WIDTH and absf(mouth_p2.z - origin.z) < 0.01, "P2 drain on the -X wall %s" % str(mouth_p2))
	_look(front_eye, front_target)
	await _erupt_and_capture(drain, "80_p2_front", [0.6], [])
	report["drain_p2"] = _plain(drain.get_debug_snapshot())
	drain.clear()


func _erupt_and_capture(drain: SurfaceDrainScript, prefix: String, times: Array, shakes: Array) -> void:
	drain.erupt()
	check(drain.is_erupting(), prefix + " erupting")
	var index := 0
	var guard := 0
	while (drain.is_erupting() or index < times.size()) and guard < 600:
		guard += 1
		await RenderingServer.frame_post_draw
		var snapshot := drain.get_debug_snapshot()
		var t := float(snapshot.time)
		shakes.append([snappedf(t, 0.001), snappedf(float(snapshot.shake), 0.001)])
		if index < times.size() and (t >= float(times[index]) or not drain.is_erupting()):
			var tag := "%s_t%.2f" % [prefix, t]
			get_viewport().get_texture().get_image().save_png(out + tag + ".png")
			captured.append(tag)
			if index == 2:
				report[prefix + "_snapshot"] = _plain(snapshot)
			index += 1


# ------------------------------------------------------------------ output

func capture(tag: String) -> Image:
	for _frame in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out + tag + ".png")
	captured.append(tag)
	return image


func _diff(a: Image, b: Image) -> Dictionary:
	if a == null or b == null or a.get_size() != b.get_size():
		return {"changed": 999999, "max": 1.0, "mean": 1.0}
	var changed := 0
	var max_delta := 0.0
	var total := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			total += delta
			samples += 1
			max_delta = maxf(max_delta, delta)
			if delta > 2.5 / 255.0:
				changed += 1
	return {"changed": changed, "max": snappedf(max_delta, 0.0001), "mean": snappedf(total / maxf(1.0, float(samples)), 0.00001)}


func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in (value as Dictionary).keys():
			result[str(key)] = _plain((value as Dictionary)[key])
		return result
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_plain(item))
		return items
	if value is Vector3:
		var v := value as Vector3
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
	return value


func _finish() -> void:
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	report["captures"] = captured
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_plain(report), "\t"))
	file.close()
	print("SURFACE_HOLE_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks,
		"failures": failures, "out": out}))
	get_tree().quit(0 if failures.is_empty() else 1)


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func until(predicate: Callable, seconds: float) -> bool:
	var limit := int(seconds * 60.0)
	for _frame in range(limit):
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()
