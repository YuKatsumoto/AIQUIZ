extends SceneTree

## CisternFlow（地下神殿の水の流体シミュレーション、docs/sudden_death_underground.md 6.6節）の単体確認。
## 床・柱・上流の壁・2本のリフトのタワーだけの簡単な舞台で、トンネルから鉄砲水を出し、決まった時刻に
## 3台のカメラで撮影し、GPU の状態を読み戻して水の広がり・水位・流速・泡を記録する。最後に片方の
## タワーを水へ沈めてしぶきを立てる。結果は artifacts/sudden_death/flow/。
## Godot --path . --script res://tests/cistern_flow_preview.gd --fixed-fps 60 [-- quality=high noshots]

const OUTPUT := "res://artifacts/sudden_death/flow/"
const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
const TOWER_Z := 9.0
const TOWER_X := 4.0
const TOWER_RADIUS := 0.9
const LEVEL := 1.2
const START_TOP := 4.2
## Seconds after the gate opened: [time, shots].
const PLAN := [
	[0.6, ["tunnel"]], [1.4, ["tunnel", "top"]], [2.5, ["duel", "top"]], [4.0, ["duel", "top", "low"]],
	[6.0, ["duel", "top"]], [9.0, ["duel", "low", "top"]], [12.0, ["duel", "low", "top"]],
]
const PLUNGE_AT := 12.2
const PLUNGE_SHOTS := [[12.5, ["duel", "low"]], [13.2, ["duel", "low", "top"]], [15.0, ["duel", "top"]]]

var flow: CisternFlow
var camera: Camera3D
var world: Node3D
var quality := "high"
var shots_on := true
var report := {"captures": [], "samples": [], "errors": [], "frame_ms": []}
var _tower_meshes: Array[MeshInstance3D] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			quality = arg.trim_prefix("quality=")
		elif arg == "noshots":
			shots_on = false
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	_build_stage()
	await process_frame
	await process_frame
	report["gpu"] = flow.uses_simulation()
	report["ready_before_flood"] = flow.is_simulation_ready()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	flow.start_flood()
	var t := 0.0
	var plan := PLAN.duplicate(true) + PLUNGE_SHOTS.duplicate(true)
	var plunged := false
	var plunge_from := START_TOP
	while not plan.is_empty() or t < 15.2:
		var dt := 1.0 / 60.0
		flow.update_flow(dt)
		t += dt
		if not plunged and t >= PLUNGE_AT:
			plunged = true
			flow.splash(Vector3(-TOWER_X, FLOOR_Y + LEVEL, TOWER_Z), 1.4, 0.55)
		if plunged:
			var u := clampf((t - PLUNGE_AT) / 0.8, 0.0, 1.0)
			var top := lerpf(plunge_from, LEVEL - 0.7, u * u)
			flow.set_tower(1, Vector2(-TOWER_X, TOWER_Z), TOWER_RADIUS, top)
			_place_tower(1, top)
		await process_frame
		report.frame_ms.append(snappedf(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), 0.001))
		if not plan.is_empty() and t >= float(plan[0][0]) - 0.0001:
			var entry: Array = plan.pop_front()
			await _sample(t)
			if shots_on:
				for shot: String in entry[1]:
					await _capture(shot, t)
	var frames: Array = report.frame_ms.slice(30)
	frames.sort()
	report["gpu_frame_ms"] = {"p50": frames[int(frames.size() * 0.5)], "p95": frames[int(frames.size() * 0.95)], "max": frames.back()}
	report.erase("frame_ms")
	report["flow"] = flow.get_debug_snapshot()
	_check_results()
	var file := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CISTERN_FLOW " + JSON.stringify({"errors": report.errors, "gpu": report.gpu, "gpu_frame_ms": report.gpu_frame_ms}))
	quit(0 if (report.errors as Array).is_empty() else 1)


func _sample(t: float) -> void:
	if not flow.debug_request_readback():
		return
	await process_frame
	await process_frame
	var sample := {"t": snappedf(t, 0.01), "totals": flow.debug_totals()}
	for spot: Array in [["tunnel", Vector2(0.0, -27.0)], ["mid", Vector2(0.0, -10.0)], ["gap", Vector2(0.0, TOWER_Z)],
			["p1_wake", Vector2(TOWER_X, TOWER_Z + 2.0)], ["p2_wake", Vector2(-TOWER_X, TOWER_Z + 2.0)],
			["side", Vector2(-30.0, 10.0)], ["camera", Vector2(0.0, 21.0)], ["p2_tower", Vector2(-TOWER_X, TOWER_Z)]]:
		var value := flow.debug_sample(spot[1])
		sample[spot[0]] = [snappedf(value.x, 0.001), snappedf(value.y, 0.01), snappedf(value.z, 0.01), snappedf(value.w, 0.01)]
	report.samples.append(sample)


func _capture(shot: String, t: float) -> void:
	match shot:
		"duel":
			camera.fov = 50.0
			var duel := SuddenDeathDirector.duel_wide_shot()
			camera.global_transform = duel
		"tunnel":
			camera.fov = 55.0
			camera.look_at_from_position(Vector3(7.0, FLOOR_Y + 3.2, -12.0), Vector3(-1.0, FLOOR_Y + 1.5, -30.0))
		"top":
			camera.fov = 60.0
			camera.look_at_from_position(Vector3(0.0, FLOOR_Y + 46.0, 6.0), Vector3(0.0, FLOOR_Y, 6.5))
		"low":
			camera.fov = 55.0
			camera.look_at_from_position(Vector3(-1.0, FLOOR_Y + 2.2, TOWER_Z - 8.0), Vector3(-4.0, FLOOR_Y + 1.2, TOWER_Z + 1.0))
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var path := OUTPUT + "%s_%05.2f.png" % [shot, t]
	if image != null and image.save_png(path) == OK:
		report.captures.append(path)


func _check_results() -> void:
	var samples: Array = report.samples
	if not bool(report.gpu):
		report.errors.append("no GPU simulation (RenderingDevice unavailable)")
		return
	if samples.is_empty():
		report.errors.append("no readback")
		return
	var early: Dictionary = samples[0]
	var settled: Dictionary = {}
	for sample: Dictionary in samples:
		if float(sample.t) <= 12.05:
			settled = sample
	if float((early.totals as Dictionary).get("wet_m2", 0.0)) <= 0.0:
		report.errors.append("the flood did not leave the tunnel")
	var last_totals: Dictionary = (samples.back() as Dictionary).totals
	if float(last_totals.get("wet_m2", 0.0)) < 0.8 * 90.0 * 72.0 - 700.0:
		report.errors.append("the hall did not fill by 15 s (%s)" % str(last_totals))
	var gap_depth := float((settled.gap as Array)[0])
	if absf(gap_depth - LEVEL) > 0.35:
		report.errors.append("the water by the towers is not at the level (%.3f)" % gap_depth)
	if float((settled.p2_tower as Array)[0]) > 0.01:
		report.errors.append("water inside the standing tower")
	var last: Dictionary = samples.back()
	if float((last.p2_tower as Array)[0]) < 0.3:
		report.errors.append("the sunk tower was not covered (%s)" % str(last.p2_tower))


func _build_stage() -> void:
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 260.0
	world.add_child(camera)
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.012, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.54, 0.6)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.055, 0.06)
	environment.fog_density = 0.01
	environment.ssr_enabled = quality in ["high", "ultra"]
	camera.environment = environment
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.36, 0.35, 0.33)
	concrete.roughness = 0.85
	_box(Vector3(0.0, FLOOR_Y - 0.25, 90.0), Vector3(90.0, 0.5, 240.0), concrete)
	# Upstream end wall around the tunnel mouth (10 m wide, 10 m high).
	_box(Vector3(-25.0, FLOOR_Y + 9.0, -30.5), Vector3(40.0, 18.0, 1.0), concrete)
	_box(Vector3(25.0, FLOOR_Y + 9.0, -30.5), Vector3(40.0, 18.0, 1.0), concrete)
	_box(Vector3(0.0, FLOOR_Y + 14.0, -30.5), Vector3(10.0, 8.0, 1.0), concrete)
	var tunnel := StandardMaterial3D.new()
	tunnel.albedo_color = Color(0.02, 0.02, 0.025)
	_box(Vector3(0.0, FLOOR_Y + 5.0, -33.0), Vector3(10.0, 10.0, 4.0), tunnel)
	for pillar: Vector2 in SuddenDeathLayout.pillars():
		if pillar.y < 80.0:
			_box(Vector3(pillar.x, FLOOR_Y + 9.0, pillar.y), Vector3(2.0, 18.0, 7.0), concrete)
	for index in range(2):
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = TOWER_RADIUS
		cylinder.bottom_radius = TOWER_RADIUS
		cylinder.height = 1.0
		mesh.mesh = cylinder
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.95, 0.55, 0.2) if index == 0 else Color(0.2, 0.65, 0.9)
		mesh.material_override = paint
		world.add_child(mesh)
		_tower_meshes.append(mesh)
		_place_tower(index, START_TOP)
	for z: float in [-20.0, -5.0, 10.0, 25.0, 40.0]:
		for x: float in [-11.0, 11.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, FLOOR_Y + 7.0, z)
			lamp.omni_range = 26.0
			lamp.light_energy = 3.0
			lamp.light_color = Color(1.0, 0.95, 0.88)
			world.add_child(lamp)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(20.0), 0.0)
	key.light_energy = 0.35
	world.add_child(key)
	flow = CisternFlow.new()
	world.add_child(flow)
	flow.setup(quality)
	flow.set_level(LEVEL)
	flow.set_tower(0, Vector2(TOWER_X, TOWER_Z), TOWER_RADIUS, START_TOP)
	flow.set_tower(1, Vector2(-TOWER_X, TOWER_Z), TOWER_RADIUS, START_TOP)


func _place_tower(index: int, top: float) -> void:
	var mesh := _tower_meshes[index]
	var height := top + 8.0
	(mesh.mesh as CylinderMesh).height = height
	mesh.position = Vector3(TOWER_X if index == 0 else -TOWER_X, FLOOR_Y + top - height * 0.5, TOWER_Z)


func _box(center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = center
	world.add_child(mesh)
