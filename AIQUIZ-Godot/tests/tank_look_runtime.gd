extends Node

## 地下ステージ（首都圏外郭放水路の調圧水槽の再現、docs/surge_tank_reproduction.md）の見た目と重さ。
## 直接は起動できないので
## Godot --path . --script res://tests/tank_look_bootstrap.gd -- [quality=high] [shots] [perf] [frames=…]
## SuddenDeathLoader で本番と同じく読み込み・組み立て・描画準備をし、全ての照明を点けて反射プローブを撮らせてから、
## 参考写真と同じ構図のカメラ位置の画像（artifacts/surge_tank/<quality>/）を 1280×720 で撮る。perf では
## 決まった画と歩く速さの移動の CPU / GPU 時間、描画呼び出し、画面内のプリミティブ、VRAM を記録する。
## 人物の大きさの比較用に、高さ1.7mの人形を置く。

const OUT_ROOT := "res://artifacts/surge_tank/"
const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
## The shots are given in plan metres; the stage is the plan scaled by this about the landing point.
const SCALE := SuddenDeathLayout.TANK_SCALE
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const PROBE_SETTLE_FRAMES := 90
const TARGET_P95_MS := 16.6

## name: [eye, target, vertical fov(, lens shift as a fraction of the height)] in hall coordinates (floor y = 0);
## the reference each one matches.
const SHOTS := {
	# the official photo matched (level camera, perspective-corrected: horizon at 463 of 540 px, f = 400 px);
	# crop the middle 505:540 of the frame to lay it over the photo
	"00_official_match": [Vector3(0.0, 1.6, -32.9), Vector3(0.0, 1.6, 30.0), 68.0, 0.357],
	"01_official_about": [Vector3(0.0, 1.6, -27.0), Vector3(0.0, 7.0, 30.0), 62.0],       # gaikaku.jp about_img: centre pillar, two lamps
	"02_aisle": [Vector3(7.0, 1.6, 7.0), Vector3(7.0, 2.6, 60.0), 75.0],                 # Google Street View 2007, along a row
	"03_shaft_end": [Vector3(0.0, 1.7, -20.0), Vector3(0.0, 6.0, -60.0), 58.0],          # gaikaku.jp slider_02: pier in the opening
	"04_pump_end": [Vector3(0.0, 1.7, 105.0), Vector3(0.0, 6.5, 135.0), 68.0],           # Commons: intake channels ("altars")
	"05_stairs": [Vector3(-6.0, 1.7, -4.0), Vector3(-30.0, 4.0, -19.0), 62.0],           # MLIT sheet photo 4: visitor stairs
	"06_shelf": [Vector3(-30.0, 6.7, -8.0), Vector3(-31.0, 9.0, 60.0), 70.0],            # along the shelf and the catwalk
	"07_tour_walk": [Vector3(3.5, 1.6, -24.0), Vector3(3.5, 3.5, 40.0), 68.0],           # Commons tour photo: visitor area
	"08_coffers_up": [Vector3(10.0, 1.6, 20.0), Vector3(10.0, 16.0, 34.0), 80.0],        # Street View, looking up
	"09_from_catwalk": [Vector3(-34.9, 13.6, 50.0), Vector3(0.0, 4.0, 60.0), 80.0],      # MLIT "Ceiling" photo: from the side catwalk
	"10_trench_edge": [Vector3(3.0, 1.6, 35.0), Vector3(-24.0, 3.5, 50.0), 64.0],        # the trench slope and the shelf
}

var quality := "high"
var do_shots := true
var do_perf := true
var perf_frames := 240
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
	camera.fov = 60.0
	camera.far = 400.0
	camera.near = 0.05
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 600.0, 0.0), Vector3(0.0, 600.0, 10.0), Vector3.UP)
	camera.current = true
	await frames(5)
	var started := Time.get_ticks_msec()
	if not await _load():
		_finish()
		return
	report["load_ms"] = Time.get_ticks_msec() - started
	_place_dolls()
	stage.set_all_rows(1.0)
	stage.refresh_reflections()
	await frames(PROBE_SETTLE_FRAMES)
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
	var ready := await until(func() -> bool: return loader.is_ready() or loader.has_failed(), 60.0)
	check(ready and loader.is_ready(), "stage READY (%s)" % loader.stage_name())
	if not loader.is_ready():
		return false
	stage = loader.cistern()
	environment = loader.environment()
	camera.environment = environment
	var snapshot := stage.get_debug_snapshot()
	check(int(snapshot.parts.added) == stage.part_count() and stage.part_count() == 4, "4 parts added")
	check(stage.row_count() == 11, "11 light rows (%d)" % stage.row_count())
	var modules := 0
	var meshes := 0
	for node: Node in stage.find_children("*", "Node3D", true, false):
		if node.has_meta(CisternStage.MODULE_META):
			modules += 1
	for node: Node in stage.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).layers == CisternStage.HALL_LAYER_MASK:
			meshes += 1
	check(modules == 15, "15 module instances (11 line slices, pump end, shaft end, shaft No.1, visitor access): %d" % modules)
	report["hall_meshes"] = meshes
	var lights := stage.find_children("*", "Light3D", true, false).size()
	report["real_lights"] = lights
	check(lights >= 80, "real lights at the real lamps (%d)" % lights)
	return true


func _game_state() -> QuizGameState:
	var state := QuizGameState.new()
	var quizzes: Array[QuizItem] = []
	var choices := ["177m", "78m", "18m", "59"]
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		quizzes.append(QuizItem.create("地下ステージのテスト問題 %d" % (index + 1), PackedStringArray(choices), 0, "テスト", "OFFLINE"))
	state.sudden_death = SuddenDeathState.new()
	state.sudden_death.setup(quizzes, true)
	return state


## Two 1.7 m stand-ins (for scale, lit by the real lamps like the players).
func _place_dolls() -> void:
	for index in range(2):
		var doll := Node3D.new()
		doll.name = "Doll%d" % (index + 1)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.25
		capsule.height = 1.45
		body.mesh = capsule
		body.position = Vector3(0.0, 0.72, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.14, 0.16, 0.2) if index == 0 else Color(0.55, 0.1, 0.08)
		material.roughness = 0.6
		body.material_override = material
		doll.add_child(body)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		head.mesh = sphere
		head.position = Vector3(0.0, 1.56, 0.0)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.8, 0.66, 0.55)
		head.material_override = skin
		doll.add_child(head)
		world.add_child(doll)
		dolls.append(doll)
	dolls[0].position = Vector3(1.2 * SCALE, FLOOR_Y, 24.0 * SCALE)
	dolls[1].position = Vector3(-2.6 * SCALE, FLOOR_Y, 31.0 * SCALE)


func _shots() -> Array:
	var shots: Array = []
	for tag: String in SHOTS.keys():
		var spec: Array = SHOTS[tag]
		shots.append(await _shot(tag, spec[0] * SCALE, spec[1] * SCALE, float(spec[2]), float(spec[3]) if spec.size() > 3 else 0.0))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	return shots


func _shot(tag: String, from: Vector3, to: Vector3, fov: float, shift := 0.0) -> Dictionary:
	camera.fov = fov
	if is_zero_approx(shift):
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	else:
		# a shifted (perspective-corrected) frustum: the near-plane rectangle moved up by `shift` of its height
		var height := 2.0 * camera.near * tan(deg_to_rad(fov) * 0.5)
		camera.projection = Camera3D.PROJECTION_FRUSTUM
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.size = height
		camera.frustum_offset = Vector2(0.0, shift * height)
	camera.look_at_from_position(from + Vector3(0.0, FLOOR_Y, 0.0), to + Vector3(0.0, FLOOR_Y, 0.0), Vector3.UP)
	# Volumetric fog and SSR reproject over a few frames after a cut.
	await frames(24)
	await RenderingServer.frame_post_draw
	var path := out + tag + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	return {"tag": tag, "path": path, "draw_calls": _info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}


func _perf() -> Dictionary:
	var result := {}
	for tag: String in ["02_aisle", "06_shelf", "09_from_catwalk", "05_stairs"]:
		var spec: Array = SHOTS[tag]
		camera.fov = float(spec[2])
		camera.look_at_from_position(spec[0] * SCALE + Vector3(0.0, FLOOR_Y, 0.0), spec[1] * SCALE + Vector3(0.0, FLOOR_Y, 0.0), Vector3.UP)
		await frames(20)
		result[tag] = await _measure(perf_frames, Callable())
	# A walk up the trench between the rows x = 0 and x = 7, eye height 1.6 m, looking toward the pumps.
	var walk := func(frame: int) -> void:
		var z := -25.0 + 140.0 * float(frame) / float(perf_frames * 2)
		camera.fov = 70.0
		camera.look_at_from_position(Vector3(3.5 * SCALE, FLOOR_Y + 1.6, z * SCALE), Vector3(3.5 * SCALE, FLOOR_Y + 3.0, (z + 30.0) * SCALE), Vector3.UP)
	result["walk"] = await _measure(perf_frames * 2, walk)
	result["vram"] = {"total_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"texture_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.1)}
	if quality == GraphicsQualityRules.HIGH:
		check(float(result.walk.cpu_p95) <= TARGET_P95_MS * 1.5, "high: walk p95 %.2f ms" % float(result.walk.cpu_p95))
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
	cpu.remove_at(0)
	return {"frames": cpu.size(), "cpu_p50": _pct(cpu, 0.5), "cpu_p95": _pct(cpu, 0.95), "cpu_p99": _pct(cpu, 0.99),
		"gpu_p50": _pct(gpu, 0.5), "gpu_p95": _pct(gpu, 0.95), "draw_calls_p50": int(_pct(draws, 0.5)), "primitives_max": int(_pct(primitives, 1.0))}


static func _pct(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return snappedf(float(sorted[index]), 0.01)


static func _info(kind: RenderingServer.RenderingInfo) -> int:
	return RenderingServer.get_rendering_info(kind)


func _finish() -> void:
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	report["quality"] = quality
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["gpu"] = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	var summary := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "quality": quality, "load_ms": report.get("load_ms", -1),
		"real_lights": report.get("real_lights", 0)}
	if report.has("perf"):
		for tag: String in (report.perf as Dictionary).keys():
			var entry: Variant = report.perf[tag]
			if entry is Dictionary and (entry as Dictionary).has("cpu_p95"):
				summary[tag] = {"p50": entry.cpu_p50, "p95": entry.cpu_p95, "gpu_p50": entry.gpu_p50, "gpu_p95": entry.gpu_p95,
					"draws": entry.draw_calls_p50, "prims": entry.primitives_max}
		summary["vram"] = report.perf.get("vram", {})
	print("TANK_LOOK " + JSON.stringify(summary))
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
