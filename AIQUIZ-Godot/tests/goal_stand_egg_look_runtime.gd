extends Node

## The raw egg contents as drawn (GoalStandEggs + GoalStandEggContents): a blockman
## on a lift deck like the finale's loser, lit by a sun and a sky, takes a fixed
## sequence of eggs (a square hit on the chest, a glancing one, a hard one that
## bursts its yolk, a miss on the conveyor), then a barrage. Shots from a close-up,
## the side and a finale-like distance at fixed times after the first hit go to
## artifacts/goal_stand/eggs/<quality>/, with the frame cost and the counts in
## report.json and the GOAL_STAND_EGG_LOOK line.
## Godot --path . --resolution 1280x720 --script res://tests/goal_stand_egg_look_bootstrap.gd -- [quality=high] [barrage=20] [p2]

const OUT_ROOT := "res://artifacts/goal_stand/eggs/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const PROPS_SCENE := preload("res://assets/goal_stand/goal_stand_props.glb")
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
const STEP := 1.0 / 60.0
const SHOT_TIMES := [0.03, 0.06, 0.15, 0.4, 1.0, 2.0, 4.0, 8.0]
## (name, eye offset from the chest, look offset).
const CAMERAS := [
	["close", Vector3(0.35, 0.15, 1.45), Vector3(0.0, -0.1, 0.0)],
	["side", Vector3(1.6, 0.25, 0.9), Vector3(0.0, -0.35, 0.0)],
	["wide", Vector3(1.2, 1.4, 5.6), Vector3(0.0, -0.6, 0.0)],
	["edge", Vector3(0.25, 0.6, 0.75), Vector3(0.0, 0.25, 0.0)],
	["floor", Vector3(1.8, -1.6, 2.3), Vector3(1.1, -2.6, 0.9)],
]

var quality := "high"
var barrage := 20.0
var mirrored := false
var out := OUT_ROOT
var checks := 0
var failures: Array[String] = []
var world: Node3D
var camera: Camera3D
var eggs: GoalStandEggs
var stage: Node3D
var lift: Node3D
var target: Node3D
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		if arg.begins_with("barrage="):
			barrage = float(arg.trim_prefix("barrage="))
		if arg == "p2":
			mirrored = true
	out = OUT_ROOT + quality + ("_p2" if mirrored else "") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	get_tree().root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameManager.graphics_quality = quality
	GraphicsQualityRules.apply_rendering_server(quality)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_world()
	await get_tree().process_frame
	await get_tree().process_frame
	await _sequence()
	await _barrage()
	report.quality = quality
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GOAL_STAND_EGG_LOOK " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "out": ProjectSettings.globalize_path(out)}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.52, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_material.ground_horizon_color = Color(0.6, 0.62, 0.65)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.33, 0.36)
	floor_material.roughness = 0.75
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = FLOOR_Y
	world.add_child(floor_mesh)
	# The finale's stage mirrors in X when P2 wins; so can this one.
	stage = Node3D.new()
	stage.name = "Stage"
	world.add_child(stage)
	if mirrored:
		stage.scale = Vector3(-1.0, 1.0, 1.0)
	lift = Node3D.new()
	lift.name = "TowerLift"
	stage.add_child(lift)
	lift.position = Vector3(0.0, FLOOR_Y + 1.1, 0.0)
	var deck := MeshInstance3D.new()
	deck.name = "TowerPlatform"
	var box := BoxMesh.new()
	box.size = Vector3(1.7, 0.32, 1.7)
	deck.mesh = box
	deck.position.y = -0.16
	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color(0.85, 0.7, 0.3)
	deck_material.metallic = 0.6
	deck_material.roughness = 0.35
	deck.material_override = deck_material
	lift.add_child(deck)
	var actor := Node3D.new()
	actor.name = "P1FinaleActor"
	lift.add_child(actor)
	# P1 winning leaves P2 (blue) the loser; P2 winning mirrors the stage and P1 loses.
	var parts := EmoteBlockmanPreview.build_player_skeleton(mirrored, actor, HatData.HAT_NONE)
	target = parts.spine as Node3D
	# The blockman's feet stand on the deck top.
	actor.position.y = 1.32
	camera = Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	camera.current = true
	var props := PROPS_SCENE.instantiate() as Node3D
	var egg_mesh := (props.find_child("GSP_EggProjectile", true, false) as MeshInstance3D).mesh
	var shard_mesh := (props.find_child("GSP_ShellShard", true, false) as MeshInstance3D).mesh
	props.free()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.97, 0.93, 0.84)
	shell.roughness = 0.55
	eggs = GoalStandEggs.new()
	world.add_child(eggs)
	eggs.setup(egg_mesh, shard_mesh, shell, 4242, quality)
	eggs.support = {"node": lift, "top": 0.0, "radius": 0.85}


func _chest() -> Vector3:
	return target.global_position + Vector3(0.0, 0.2, 0.0)


func _view(spec: Array) -> void:
	var chest := _chest()
	camera.look_at_from_position(chest + (spec[1] as Vector3), chest + (spec[2] as Vector3), Vector3.UP)


func _step(frames: int) -> void:
	for _frame in range(frames):
		_view(CAMERAS[0])
		eggs.update(STEP, camera)
		await get_tree().process_frame


## A thrower 9 m out in front and a little to the side, like the stand's hotheads.
func _throw(offset: Vector3, aim_offset: Vector3, flight: float, miss: bool = false) -> void:
	var chest := _chest()
	var start := chest + Vector3(2.5, 3.0, 8.5) + offset
	var aim := chest + aim_offset
	if miss:
		aim = Vector3(chest.x + 1.1, FLOOR_Y, chest.z + 0.9)
	eggs.launch(start, aim, flight, null if miss else target, miss)


func _sequence() -> void:
	# A square hit on the chest, a glancing one from the side, a hard one, a miss.
	_throw(Vector3.ZERO, Vector3(0.0, 0.05, 0.0), 0.6)
	_throw(Vector3(-6.0, -1.5, -6.0), Vector3(-0.15, 0.2, 0.0), 0.62)
	_throw(Vector3(0.0, -2.0, -3.0), Vector3(0.12, -0.15, 0.0), 0.3)
	_throw(Vector3(1.0, 0.0, 0.0), Vector3.ZERO, 0.66, true)
	var first := -1.0
	var clock := 0.0
	var next_shot := 0
	var shots := 0
	while next_shot < SHOT_TIMES.size():
		_view(CAMERAS[0])
		var impacts := eggs.update(STEP, camera)
		clock += STEP
		if first < 0.0 and not impacts.is_empty():
			first = clock
		await get_tree().process_frame
		if first >= 0.0 and clock - first >= float(SHOT_TIMES[next_shot]):
			for spec: Array in CAMERAS:
				_view(spec)
				await RenderingServer.frame_post_draw
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var image := get_viewport().get_texture().get_image()
				image.save_png(out + "%s_%05.2fs.png" % [spec[0], float(SHOT_TIMES[next_shot])])
				shots += 1
			next_shot += 1
	var counts := eggs.active_counts()
	report.sequence = counts
	check(shots == SHOT_TIMES.size() * CAMERAS.size(), "every shot taken (%d)" % shots)
	check(int(counts.body_splats) >= 1, "the body carries the splats (%d)" % int(counts.body_splats))
	check(int(counts.floor_splats) >= 1, "the miss lies on the conveyor")
	check(int(counts.drips_fallen) >= 1 or int(counts.drips) >= 1, "white drips off the body (%d fallen)" % int(counts.drips_fallen))
	check(int(counts.puddles) >= 1, "drips pool below (%d)" % int(counts.puddles))
	for entry: Dictionary in eggs.contents.splats():
		if entry.body != null:
			check((entry.frame as Transform3D).basis.determinant() > 0.0, "body splat frame right-handed")


func _barrage() -> void:
	if barrage <= 0.0:
		return
	var frames := int(barrage / STEP)
	var clock := 0.0
	var next := 0.0
	var cpu := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var update_usec := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for frame in range(frames):
		clock += STEP
		while clock >= next:
			next += rng.randf_range(0.18, 0.4)
			var miss := rng.randf() < 0.25
			_throw(Vector3(rng.randf_range(-4.0, 2.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-3.0, 0.0)),
				Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.35), 0.0), rng.randf_range(0.7, 1.1), miss)
		_view(CAMERAS[2])
		var started := Time.get_ticks_usec()
		eggs.update(STEP, camera)
		update_usec.append(float(Time.get_ticks_usec() - started))
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		cpu.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		if frame == frames - 1:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out + "barrage_wide.png")
			_view(CAMERAS[0])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out + "barrage_close.png")
	report.barrage = {"counts": eggs.active_counts(), "update_ms_p95": _p95(update_usec) / 1000.0, "contents_ms": eggs.contents_usec / 1000.0, "contents_costs_usec": eggs.contents.costs,
		"frame_ms_p95": _p95(cpu), "gpu_ms_p95": _p95(gpu),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("GOAL_STAND_EGG_BARRAGE " + JSON.stringify(report.barrage))
	# The GPU fluid (HIGH/ULTRA): read its particles back and check they are sane.
	var fluid := eggs.contents.fluid
	if fluid != null and fluid.debug_request_readback():
		for _frame in range(6):
			await get_tree().process_frame
		var totals := fluid.debug_totals()
		report.fluid = totals
		print("GOAL_STAND_EGG_FLUID " + JSON.stringify(totals))
		check(int(totals.get("live", 0)) > 0, "the fluid has live particles")
		check(int(totals.get("nans", 1)) == 0, "no particle went NaN")
		check(int(totals.get("inside", 0)) <= maxi(2, int(totals.get("live", 0)) / 50), "particles stay out of the body (%d inside)" % int(totals.get("inside", 0)))
		check(float(totals.get("lowest", 0.0)) > FLOOR_Y - 0.6, "particles rest on the deck or the conveyor (%.2f)" % float(totals.get("lowest", 0.0)))
		check(float(totals.get("highest", 0.0)) < FLOOR_Y + 7.0, "no particle blows away (%.2f)" % float(totals.get("highest", 0.0)))


static func _p95(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * 0.95)]
