extends Node

## 地下神殿の見た目と性能（docs/sudden_death_underground.md 6.4・6.6・6.7・6.8）。舞台・2本のリフトのタワー・
## 水の流体シミュレーション（鉄砲水が出て満ちるまでと、本戦のカメラ）。
## 直接は起動できないので
## Godot --path . --script res://tests/cistern_look_bootstrap.gd -- [quality=high] [shots] [perf] [frames=…]
## 既定は shots と perf の両方。SuddenDeathLoader で本番と同じく読み込み・組み立て・描画準備をしてから、
## 決まったカメラ位置の画像（artifacts/sudden_death/cistern_m3/<quality>/）を撮り、1280×720 で
## 決まったショットと通路の飛行の p50 / p95 / p99（CPU のフレーム間隔と GPU の描画時間）、描画呼び出し、
## 画面内のプリミティブ、VRAM を記録する（report.json と標準出力の CISTERN_LOOK 行）。
## 人物の代わりに高さ1.9mの人形を2体置く（実ライトの当たり方と大きさの比較用）。本戦ではタワーの上に立たせる。

const OUT_ROOT := "res://artifacts/sudden_death/cistern_m3/"
const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
## 6.8: high p95 <= 16.6 ms, p99 <= 20 ms, <= 1.5 M triangles in view.
const TARGET_P95_MS := 16.6
const TARGET_P99_MS := 20.0
const TARGET_PRIMITIVES := 1500000
## Frames for the reflection probes to finish (one face per frame, one probe after another).
const PROBE_SETTLE_FRAMES := 80

var quality := "high"
var do_shots := true
var do_perf := true
var perf_frames := 300
var out := OUT_ROOT
var checks := 0
var failures: Array[String] = []
var world: Node3D
var camera: Camera3D
var stage: CisternStage
var loader: SuddenDeathLoader
var environment: Environment
var dolls: Array[Node3D] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var only_shots := "shots" in args
	var only_perf := "perf" in args
	if only_shots or only_perf:
		do_shots = only_shots
		do_perf = only_perf
	for arg: String in args:
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		if arg.begins_with("frames="):
			perf_frames = maxi(30, int(arg.trim_prefix("frames=")))
	out = OUT_ROOT + quality + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	get_tree().root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameManager.graphics_quality = quality
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.fov = 50.0
	camera.far = 260.0
	camera.near = 0.1
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 600.0, 0.0), Vector3(0.0, 600.0, 10.0), Vector3.UP)
	camera.current = true
	await frames(5)
	var vram_before := _info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var texture_before := _info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	var started := Time.get_ticks_msec()
	if not await _load():
		_finish()
		return
	report["load_ms"] = Time.get_ticks_msec() - started
	_place_dolls()
	await frames(PROBE_SETTLE_FRAMES)
	report["cistern_vram_mb"] = {"total": snappedf(float(_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) - vram_before) / 1048576.0, 0.1),
		"textures": snappedf(float(_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) - texture_before) / 1048576.0, 0.1)}
	report["cistern_textures"] = _texture_usage()
	if do_shots:
		report["shots"] = await _shots()
	if do_perf:
		report["perf"] = await _perf()
	_finish()


func _load() -> bool:
	loader = SuddenDeathLoader.new()
	add_child(loader)
	loader.set_heavy_work_allowed(true)
	loader.set_presentable(true)
	loader.begin(world, _game_state())
	var ready := await until(func() -> bool: return loader.is_ready() or loader.has_failed(), 30.0)
	check(ready and loader.is_ready(), "cistern READY (%s)" % loader.stage_name())
	if not loader.is_ready():
		return false
	stage = loader.cistern()
	environment = loader.environment()
	camera.environment = environment
	var snapshot := stage.get_debug_snapshot()
	report["modules"] = snapshot.get("modules", {})
	report["loader"] = {"timings": loader.get_debug_snapshot().get("timings", {}), "compile": loader.get_debug_snapshot().get("compile", {})}
	check(int(snapshot.parts.added) == stage.part_count() and stage.part_count() == 4, "4 parts added")
	check(stage.row_count() == 15, "15 light rows (%d)" % stage.row_count())
	check(int((snapshot.probes as Dictionary).count) == 8, "8 reflection probes (%s)" % str(snapshot.probes))
	check(bool(snapshot.gate_node), "the inflow gate node is found in the upstream module")
	# Hall meshes live on layer 11 only, real lights never include it.
	var hall_ok := true
	var hall_meshes := 0
	for node: Node in stage.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var in_module := false
		var walk: Node = mesh
		while walk != null and walk != stage:
			if walk.has_meta(CisternStage.MODULE_META):
				in_module = true
				break
			walk = walk.get_parent()
		if in_module:
			hall_meshes += 1
			hall_ok = hall_ok and mesh.layers == CisternStage.HALL_LAYER_MASK and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check(hall_meshes > 0 and hall_ok, "hall meshes on layer 11 only, no shadows (%d)" % hall_meshes)
	var lights_ok := true
	for node: Node in stage.find_children("*", "Light3D", true, false):
		lights_ok = lights_ok and ((node as Light3D).light_cull_mask & CisternStage.HALL_LAYER_MASK) == 0
	check(lights_ok, "no real light reaches layer 11")
	return true


func _game_state() -> QuizGameState:
	var state := QuizGameState.new()
	var quizzes: Array[QuizItem] = []
	var choices := ["23.8m", "18m", "7m", "30m"]
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		quizzes.append(QuizItem.create("地下神殿のテスト問題 %d" % (index + 1), PackedStringArray(choices), 0, "テスト", "OFFLINE"))
	state.sudden_death = SuddenDeathState.new()
	state.sudden_death.setup(quizzes, true)
	return state


## Two 1.9 m stand-ins (lit by the real lights like the runners).
func _place_dolls() -> void:
	for index in range(2):
		var doll := Node3D.new()
		doll.name = "Doll%d" % (index + 1)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.55
		body.mesh = capsule
		body.position = Vector3(0.0, 0.78, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.78, 0.22, 0.16) if index == 0 else Color(0.18, 0.38, 0.78)
		material.roughness = 0.55
		body.material_override = material
		doll.add_child(body)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2
		sphere.height = 0.4
		head.mesh = sphere
		head.position = Vector3(0.0, 1.7, 0.0)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.85, 0.72, 0.6)
		skin.roughness = 0.6
		head.material_override = skin
		doll.add_child(head)
		world.add_child(doll)
		dolls.append(doll)
	_dolls_at(6.0)


func _dolls_at(z: float) -> void:
	dolls[0].position = Vector3(2.2, FLOOR_Y, z)
	dolls[1].position = Vector3(-2.2, FLOOR_Y, z + 0.8)


## The stand-ins on the lift towers, at the towers' heights.
func _dolls_on_towers() -> void:
	for index in range(2):
		var tower := stage.tower_position(index + 1)
		dolls[index].position = tower + Vector3(0.0, stage.tower_height(index + 1), 0.0)
		# Facing the duel camera upstream.
		dolls[index].rotation.y = PI


# ------------------------------------------------------------------ shots

func _lights(rows: float, opening: float) -> void:
	for row in range(stage.row_count()):
		stage.set_row_brightness(row, rows)
	stage.set_opening_light(opening)
	CisternStage.apply_hall_light(environment, rows)


func _shots() -> Array:
	var saved: Array = []
	var landing := Vector3(0.0, FLOOR_Y, 0.0)
	stage.set_inflow_gate(0.0)
	# The dark hall before the lights: only the cool shaft light.
	_lights(0.0, 1.0)
	_dolls_at(1.0)
	saved.append(await _shot("01_dark_before_lights", landing + Vector3(0.0, 3.0, -9.0), landing + Vector3(0.0, 3.0, 40.0)))
	# Half the rows lit, near to far.
	for row in range(stage.row_count()):
		stage.set_row_brightness(row, 1.0 if row < 7 else 0.0)
	CisternStage.apply_hall_light(environment, 7.0 / 15.0)
	saved.append(await _shot("02_half_rows_lit", landing + Vector3(0.0, 3.0, -9.0), landing + Vector3(0.0, 3.0, 40.0)))
	_lights(1.0, 1.0)
	# Probes re-capture once the rows are all lit again.
	await frames(PROBE_SETTLE_FRAMES)
	_dolls_at(8.0)
	saved.append(await _shot("03_corridor_runner_height", landing + Vector3(1.2, 1.7, 0.0), landing + Vector3(0.0, 2.2, 80.0)))
	saved.append(await _shot("04_dry_towers", landing + Vector3(0.0, 2.3, -2.5), landing + Vector3(0.0, 1.0, 12.0)))
	_dolls_at(8.0)
	saved.append(await _shot("05_pillar_forest_wide", landing + Vector3(-8.0, 9.0, 2.0), landing + Vector3(34.0, 2.0, 62.0)))
	saved.append(await _shot("06_aisle_into_dark", landing + Vector3(-19.0, 2.0, 40.0), landing + Vector3(-44.0, 3.0, 100.0)))
	stage.set_inflow_gate(1.0)
	_dolls_at(-18.0)
	saved.append(await _shot("07_upstream_tunnel_balcony", landing + Vector3(4.0, 3.0, 16.0), landing + Vector3(8.0, 6.5, -30.0)))
	stage.set_inflow_gate(0.0)
	_dolls_at(196.0)
	saved.append(await _shot("08_downstream_end", landing + Vector3(0.0, 4.0, 180.0), landing + Vector3(0.0, 4.0, 210.0)))
	_dolls_at(30.0)
	saved.append(await _shot("09_puddle_reflection", landing + Vector3(2.5, 0.7, 14.0), landing + Vector3(-1.0, 0.0, 26.0)))
	saved.append(await _shot("10_opening_up", landing + Vector3(6.0, 1.8, 12.0), landing + Vector3(0.0, 18.0, 0.0)))
	saved.append(await _shot("11_pillar_closeup", landing + Vector3(7.0, 2.2, 10.0), landing + Vector3(12.0, 3.0, 18.5)))
	# Reflection check: a chrome ball and a mirror tile (layer 1) show what the probes and SSR return.
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	ball.mesh = sphere
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.95, 0.95, 0.95)
	chrome.metallic = 1.0
	chrome.roughness = 0.02
	ball.material_override = chrome
	world.add_child(ball)
	ball.position = landing + Vector3(0.0, 1.2, 40.0)
	saved.append(await _shot("12_chrome_probe_check", landing + Vector3(0.0, 1.8, 35.0), landing + Vector3(0.0, 1.2, 40.0)))
	ball.queue_free()
	# Look-dev: the baked light alone on white (compare with the Blender light map checks).
	_set_debug_view(1)
	saved.append(await _shot("13_baked_light_on_white", landing + Vector3(0.0, 5.1, -3.0), landing + Vector3(0.0, 2.0, 30.0)))
	_set_debug_view(0)
	saved.append_array(await _flood_shots())
	return saved


## The flood out of the tunnel and the duel over the water, driven through the runtime like the game does:
## the towers rise, the gate lifts, the simulated flood runs out and fills the hall around them.
func _flood_shots() -> Array:
	var saved: Array = []
	var sd := stage.game_state.sudden_death
	if sd == null:
		return saved
	var landing := Vector3(0.0, FLOOR_Y, 0.0)
	var start := sd.tuning.lift_height(sd.tuning.start_margin)
	for player_index in [1, 2]:
		stage.set_tower_target(player_index, start, 0.0, true)
	_dolls_on_towers()
	stage.set_inflow_gate(1.0)
	stage.start_flood()
	stage.set_focus(true)
	await _run_flow(sd, 0.7)
	saved.append(await _shot("14_flood_gush", landing + Vector3(6.6, 3.1, -7.5), landing + Vector3(-1.0, 2.6, -30.0)))
	await _run_flow(sd, 2.6)
	saved.append(await _shot("15_flood_front", landing + Vector3(-9.0, 2.6, 4.0), landing + Vector3(2.0, 0.6, -14.0)))
	await _run_flow(sd, 2.5)
	var duel := SuddenDeathDirector.duel_wide_shot()
	saved.append(await _shot("16_flood_reaches_towers", duel.origin, duel.origin - duel.basis.z * 10.0))
	await _run_flow(sd, 6.5)
	saved.append(await _shot("17_duel_camera", duel.origin, duel.origin - duel.basis.z * 10.0))
	var p2 := stage.tower_position(2)
	saved.append(await _shot("18_tower_in_the_current", p2 + Vector3(2.5, 2.2, -6.0), p2 + Vector3(0.0, 1.4, 1.0)))
	saved.append(await _shot("19_wakes_from_above", landing + Vector3(0.0, 20.0, -2.0), landing + Vector3(0.0, 0.0, 14.0)))
	# The loser's tower goes under: the water closes over its platform.
	stage.set_tower_target(2, sd.tuning.sunk_height(), CisternStage.PLUNGE_SPEED)
	await _run_flow(sd, 2.0)
	saved.append(await _shot("20_tower_under", p2 + Vector3(2.0, 2.4, -6.5), p2 + Vector3(-0.5, 1.0, 0.5)))
	var flow := stage.flow()
	if flow != null and flow.debug_request_readback():
		await frames(3)
		var totals := flow.debug_totals()
		report["flow"] = {"totals": totals, "over_sunk_tower": flow.debug_depth_at(Vector2(p2.x, p2.z)),
			"by_towers": flow.debug_depth_at(Vector2(0.0, p2.z)), "snapshot": flow.get_debug_snapshot()}
		check(flow.debug_depth_at(Vector2(p2.x, p2.z)) > 0.3, "the water closes over the sunk platform (%s)" % str(report.flow))
		check(absf(flow.debug_depth_at(Vector2(0.0, p2.z)) - sd.tuning.water_level) < 0.5, "the hall holds the level by the towers (%s)" % str(report.flow))
		check(float(totals.get("wet_m2", 0.0)) > 3000.0, "the flood fills the hall around the towers (%s)" % str(totals))
	else:
		check(not flow.uses_simulation() if flow != null else false, "water readback")
	stage.set_tower_target(2, start, 0.0, true)
	return saved


## Runs the stage (towers, water, lights) for [param seconds] of game time at 60 fps.
func _run_flow(sd: SuddenDeathState, seconds: float) -> void:
	for _frame in range(int(seconds * 60.0)):
		stage.update_runtime(1.0 / 60.0, sd)
		await get_tree().process_frame


func _set_debug_view(mode: int) -> void:
	for node: Node in stage.find_children("*", "Node3D", true, false):
		if not node.has_meta(CisternStage.MATERIALS_META):
			continue
		for pair: Variant in node.get_meta(CisternStage.MATERIALS_META):
			var material := (pair as Array)[1] as ShaderMaterial
			if material != null and material.shader != null and "cistern_lamp" not in material.shader.resource_path:
				material.set_shader_parameter("debug_view", mode)


func _shot(tag: String, from: Vector3, to: Vector3) -> Dictionary:
	camera.look_at_from_position(from, to, Vector3.UP)
	# Volumetric fog reprojects over a few frames after a cut.
	await frames(16)
	await RenderingServer.frame_post_draw
	var path := out + tag + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	return {"tag": tag, "path": path, "draw_calls": _info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}


# ------------------------------------------------------------------ performance

func _perf() -> Dictionary:
	_lights(1.0, 1.0)
	await frames(PROBE_SETTLE_FRAMES)
	var result := {}
	var views := {
		"corridor": [Vector3(0.0, 5.1, -3.0), Vector3(0.0, 2.0, 30.0)],
		"pillar_forest": [Vector3(-8.0, 9.0, 2.0), Vector3(34.0, 2.0, 62.0)],
		"upstream": [Vector3(4.0, 3.0, 16.0), Vector3(8.0, 6.5, -30.0)],
		"downstream": [Vector3(0.0, 4.0, 180.0), Vector3(0.0, 4.0, 210.0)],
	}
	for view_name: String in views.keys():
		var pair: Array = views[view_name]
		camera.look_at_from_position(Vector3(0.0, FLOOR_Y, 0.0) + pair[0], Vector3(0.0, FLOOR_Y, 0.0) + pair[1], Vector3.UP)
		await frames(20)
		result[view_name] = await _measure(perf_frames, Callable())
	# The gameplay camera running the corridor (runners 10 m ahead), 9 m/s.
	var fly := func(frame: int) -> void:
		var z := -5.0 + 190.0 * float(frame) / float(perf_frames * 2)
		camera.look_at_from_position(Vector3(0.0, FLOOR_Y + 5.1, z), Vector3(0.0, FLOOR_Y + 2.0, z + 33.0), Vector3.UP)
		_dolls_at(z + 10.0)
	result["fly_through"] = await _measure(perf_frames * 2, fly)
	# The rows going dark and lit again (landing): the probes re-capture over the next frames.
	camera.look_at_from_position(Vector3(0.0, FLOOR_Y + 5.1, -3.0), Vector3(0.0, FLOOR_Y + 2.0, 30.0), Vector3.UP)
	_lights(0.0, 1.0)
	await frames(10)
	_lights(1.0, 1.0)
	result["probe_recapture"] = await _measure(90, Callable())
	result["probe_recapture"]["captures"] = int((stage.get_debug_snapshot().probes as Dictionary).captures)
	# The duel over the running water (the fluid simulation steps every frame).
	var sd := stage.game_state.sudden_death
	if sd != null and stage.flow() != null and not stage.flow().is_flooding():
		for player_index in [1, 2]:
			stage.set_tower_target(player_index, sd.tuning.lift_height(sd.tuning.start_margin), 0.0, true)
		stage.start_flood()
		await _run_flow(sd, 9.0)
	if sd != null and stage.flow() != null and stage.flow().is_flooding():
		var running := func(_frame: int) -> void:
			stage.update_runtime(1.0 / 60.0, sd)
		var duel := SuddenDeathDirector.duel_wide_shot()
		camera.global_transform = duel
		result["duel_water"] = await _measure(perf_frames, running)
		camera.look_at_from_position(Vector3(0.0, FLOOR_Y + 20.0, -2.0), Vector3(0.0, FLOOR_Y, 14.0), Vector3.UP)
		result["water_from_above"] = await _measure(perf_frames, running)
	result["vram"] = {"total_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"texture_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.1),
		"buffer_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0, 0.1)}
	if quality == GraphicsQualityRules.HIGH:
		var worst: Dictionary = result.fly_through
		check(float(worst.cpu_p95) <= TARGET_P95_MS, "high: fly-through p95 %.2f ms <= %.1f" % [float(worst.cpu_p95), TARGET_P95_MS])
		check(float(worst.cpu_p99) <= TARGET_P99_MS, "high: fly-through p99 %.2f ms <= %.1f" % [float(worst.cpu_p99), TARGET_P99_MS])
	for view_name: String in result.keys():
		if result[view_name] is Dictionary and (result[view_name] as Dictionary).has("primitives_max"):
			check(int(result[view_name].primitives_max) <= TARGET_PRIMITIVES, "%s: primitives %d <= 1.5M" % [view_name, int(result[view_name].primitives_max)])
	return result


func _measure(count: int, step: Callable) -> Dictionary:
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[int] = []
	var primitives: Array[int] = []
	var last := Time.get_ticks_usec()
	var rid := get_viewport().get_viewport_rid()
	for frame in range(count):
		if step.is_valid():
			step.call(frame)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		cpu.append(float(now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		draws.append(_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	# The first frame's interval includes the camera cut.
	cpu.remove_at(0)
	return {"frames": cpu.size(), "cpu_p50": _pct(cpu, 0.5), "cpu_p95": _pct(cpu, 0.95), "cpu_p99": _pct(cpu, 0.99), "cpu_max": _pct(cpu, 1.0),
		"gpu_p50": _pct(gpu, 0.5), "gpu_p95": _pct(gpu, 0.95), "gpu_p99": _pct(gpu, 0.99),
		"draw_calls_p50": int(_pct(draws, 0.5)), "draw_calls_max": int(_pct(draws, 1.0)),
		"primitives_p50": int(_pct(primitives, 0.5)), "primitives_max": int(_pct(primitives, 1.0))}


## The stage's own textures (budget 6.8: 150 MB, BC7) apart from the renderer's buffers, largest
## first. Imported (VRAM-compressed) textures are counted at 1 byte per pixel (BC7/BC5, the upper
## bound), images by their format; mipmaps add a third.
func _texture_usage() -> Dictionary:
	var seen := {}
	for node: Node in stage.find_children("*", "", true, false):
		var materials: Array[Material] = []
		if node is GeometryInstance3D:
			materials.append((node as GeometryInstance3D).material_override)
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mesh_node := node as MeshInstance3D
				for surface in range(mesh_node.mesh.get_surface_count()):
					materials.append(mesh_node.get_active_material(surface))
		elif node is Decal:
			for texture: Texture2D in [(node as Decal).texture_albedo, (node as Decal).texture_normal, (node as Decal).texture_orm]:
				if texture != null:
					seen[texture] = true
		for material: Material in materials:
			_collect_textures(material, seen)
	var total := 0.0
	var largest: Array = []
	for texture: Texture in seen.keys():
		var bytes := _texture_bytes(texture)
		total += bytes
		largest.append({"name": texture.resource_path.get_file() if not texture.resource_path.is_empty() else texture.get_class(),
			"mb": snappedf(bytes / 1048576.0, 0.01)})
	largest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.mb) > float(b.mb))
	return {"mb": snappedf(total / 1048576.0, 0.1), "count": largest.size(), "largest": largest.slice(0, 12)}


static func _collect_textures(material: Material, seen: Dictionary) -> void:
	if material == null:
		return
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		for uniform: Dictionary in (material as ShaderMaterial).shader.get_shader_uniform_list():
			var value: Variant = (material as ShaderMaterial).get_shader_parameter(str(uniform.name))
			if value is Texture:
				seen[value] = true
	elif material is BaseMaterial3D:
		for slot in range(BaseMaterial3D.TEXTURE_MAX):
			var texture := (material as BaseMaterial3D).get_texture(slot)
			if texture != null:
				seen[texture] = true
	if material.next_pass != null:
		_collect_textures(material.next_pass, seen)


static func _texture_bytes(texture: Texture) -> float:
	var pixels := 0.0
	var per_pixel := 1.0
	if texture is Texture2D:
		pixels = float((texture as Texture2D).get_width() * (texture as Texture2D).get_height())
	if texture is Texture3D:
		var volume := texture as Texture3D
		pixels = float(volume.get_width() * volume.get_height() * volume.get_depth())
		per_pixel = 4.0
	if texture is ImageTexture:
		var image := (texture as ImageTexture).get_image()
		if image != null:
			return float(image.get_data_size()) * (1.0 if image.has_mipmaps() else 1.333)
	return pixels * per_pixel * 1.333


static func _pct(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return snappedf(float(sorted[index]), 0.01)


static func _info(kind: RenderingServer.RenderingInfo) -> int:
	return RenderingServer.get_rendering_info(kind)


# ------------------------------------------------------------------ report

func _finish() -> void:
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	report["quality"] = quality
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["viewport"] = {"size": get_viewport().get_visible_rect().size, "scale_3d": get_viewport().scaling_3d_scale}
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	var summary := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "quality": quality, "load_ms": report.get("load_ms", -1),
		"cistern_vram_mb": report.get("cistern_vram_mb", {})}
	if report.has("perf"):
		var perf: Dictionary = report.perf
		for view_name: String in perf.keys():
			var entry: Variant = perf[view_name]
			if entry is Dictionary and (entry as Dictionary).has("cpu_p95"):
				summary[view_name] = {"p50": entry.cpu_p50, "p95": entry.cpu_p95, "p99": entry.cpu_p99, "gpu_p50": entry.gpu_p50,
					"gpu_p95": entry.gpu_p95, "draws": entry.draw_calls_p50, "prims": entry.primitives_max}
		summary["vram"] = perf.get("vram", {})
	print("CISTERN_LOOK " + JSON.stringify(summary))
	if is_instance_valid(loader):
		loader.cancel()
	await frames(2)
	get_tree().quit(0 if failures.is_empty() else 1)


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()
