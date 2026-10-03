extends Node

## SuddenDeathLoader と CisternStage を最小のシーン（Forward+、ウィンドウあり）で動かす
## （docs/sudden_death_underground.md 5.5節・第6章）。直接は起動できないので
## Godot --path . --script res://tests/cistern_loader_bootstrap.gd -- runtime [case=…] [quality=…]
## case: all（既定）| normal | slow_load | load_fail | cancel_restart
## normal：段階の順番、重い処理の許可と表示の許可による待ち、部分シーンと水門列が別々のフレームに
## 分かれること、1回の追加が50ms以内、描画準備の完了、準備後に照明が0へ戻ること、水門列と波の動作、
## 決まったカメラ位置の画像（artifacts/sudden_death/cistern/<quality>/）。

const OUT_ROOT := "res://artifacts/sudden_death/cistern/"
const Stage := SuddenDeathLoader.Stage
const FLOOR_Y := SuddenDeathLayout.FLOOR_Y
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const ALL_CASES: PackedStringArray = ["normal", "slow_load", "load_fail", "cancel_restart"]
const EXPECTED_ORDER: PackedStringArray = ["loading", "instantiate", "parts", "runtime", "prewarm", "ready"]
## 1回の追加（本体・部分シーン・水門列）にかけてよい時間（6.8節の「50msを超えるフレームなし」）。
const ADD_BUDGET_MS := 50.0
const SLOW_DELAY := 2.5

var quality := "balanced"
var cases: PackedStringArray = ALL_CASES
var out := OUT_ROOT
var checks := 0
var failures: Array[String] = []
var results := {}
var world: Node3D
var camera: Camera3D
var gs: QuizGameState
var _frame_ms: Array[float] = []
var _frame_usec := 0
var _measuring := false


func _ready() -> void:
	call_deferred("run")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _frame_usec > 0:
		_frame_ms.append(float(now - _frame_usec) / 1000.0)
	_frame_usec = now


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	if "parse" in OS.get_cmdline_user_args():
		await _parse_check()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case=") and arg.trim_prefix("case=") != "all":
			cases = [arg.trim_prefix("case=")]
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
	out = OUT_ROOT + quality + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	get_tree().root.size = Vector2i(1280, 720)
	GameManager.graphics_quality = quality
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	# The game camera looks into an empty sky, like the shaft shots while the cistern loads.
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.fov = 50.0
	camera.far = 260.0
	camera.environment = CisternStage.make_environment(quality)
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 600.0, 0.0), Vector3(0.0, 600.0, 10.0), Vector3.UP)
	camera.current = true
	gs = _game_state()
	# The match start builds the deck's score towers (SuddenDeathDirector.prepare_for_match) and with them
	# the shared tier column the lift towers reuse; the loader never pays for it.
	ResultFinaleStage.tier_column_mesh()
	await frames(10)
	for case_name: String in cases:
		print("== case %s" % case_name)
		var started := Time.get_ticks_usec()
		var result: Dictionary = await call("case_" + case_name)
		result["wall_ms"] = snappedf(float(Time.get_ticks_usec() - started) / 1000.0, 0.1)
		results[case_name] = result
	_write_report()
	get_tree().quit(0 if failures.is_empty() else 1)


func _game_state() -> QuizGameState:
	var state := QuizGameState.new()
	var quizzes: Array[QuizItem] = []
	var choices := ["23.8m", "18m", "7m", "30m"]
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		quizzes.append(QuizItem.create("地下神殿のテスト問題 %d" % (index + 1), PackedStringArray(choices), 0, "テスト", "OFFLINE"))
	state.sudden_death = SuddenDeathState.new()
	state.sudden_death.setup(quizzes, true)
	state.player_x = SuddenDeathLayout.LIFT_X
	state.player2_x = -SuddenDeathLayout.LIFT_X
	state.player_z = SuddenDeathLayout.LIFT_Z
	state.player2_z = SuddenDeathLayout.LIFT_Z
	return state


func _new_loader() -> SuddenDeathLoader:
	var loader := SuddenDeathLoader.new()
	add_child(loader)
	return loader


# ------------------------------------------------------------------ parse

const SCRIPTS: PackedStringArray = [
	"res://scripts/world/sudden_death/cistern_stage.gd",
	"res://scripts/world/sudden_death/cistern_lighting.gd",
	"res://scripts/world/sudden_death/sudden_death_loader.gd",
	"res://tools/sudden_death/build_cistern_scenes.gd",
	"res://tools/sudden_death/cistern_placeholder_modules.gd",
	"res://tools/sudden_death/cistern_texture_gen.gd",
	"res://tests/cistern_loader_bootstrap.gd",
	"res://tests/cistern_look_runtime.gd",
]
const SCENES: PackedStringArray = [
	"res://scenes/sudden_death/cistern_stage.tscn",
	"res://scenes/sudden_death/cistern_bays.tscn",
	"res://scenes/sudden_death/cistern_ends.tscn",
	"res://scenes/sudden_death/cistern_lights.tscn",
	"res://scenes/sudden_death/cistern_dressing.tscn",
]
## Parts of the milestone-3 stage: bays, ends, lights (with probes and fog), dressing.
const PART_COUNT := 4


## Headless: every script compiles, the generated scenes load, and the stage API works without rendering.
func _parse_check() -> void:
	for path: String in SCRIPTS:
		var script := load(path) as GDScript
		check(script != null and script.can_instantiate(), "script compiles: " + path)
	for path: String in SCENES:
		check(load(path) is PackedScene, "scene loads: " + path)
	var packed := load(SCENES[0]) as PackedScene
	var stage: CisternStage = packed.instantiate() as CisternStage if packed != null else null
	check(stage != null, "cistern_stage.tscn root is a CisternStage")
	if stage != null:
		stage.apply_quality("low")
		add_child(stage)
		var part_steps := 1
		while not stage.add_part_step():
			part_steps += 1
		check(stage.part_count() == PART_COUNT and part_steps == PART_COUNT and stage.parts_added(), "%d parts, one per step" % PART_COUNT)
		check(stage.row_count() == SuddenDeathLayout.pillar_row_zs().size(), "light rows = pillar rows (%d)" % stage.row_count())
		stage.set_all_rows(0.5)
		stage.set_opening_light(1.0)
		stage.set_inflow_gate(1.0)
		stage.setup_runtime(null)
		var runtime_steps := 1
		while not stage.build_runtime_step():
			runtime_steps += 1
		check(runtime_steps == stage.runtime_step_count() and stage.is_runtime_built(), "runtime in %d steps" % runtime_steps)
		var snapshot := stage.get_debug_snapshot()
		for key: String in ["active", "towers", "flow", "lights", "parts"]:
			check(snapshot.has(key), "snapshot key: " + key)
		stage.begin_prewarm()
		stage.end_prewarm()
		stage.clear_runtime()
		stage.queue_free()
	for tier: String in ["low", "balanced", "high", "ultra"]:
		var environment := CisternStage.make_environment(tier)
		check(environment != null and environment.volumetric_fog_enabled == (tier != "low"), "environment " + tier)
	var loader := SuddenDeathLoader.new()
	check(loader.stage() == Stage.IDLE and loader.progress() == 0.0, "loader starts idle")
	loader.free()
	await frames(2)
	print("CISTERN_PARSE " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ cases

func case_normal() -> Dictionary:
	var loader := _new_loader()
	loader.debug_capture_dir = out
	var order: PackedStringArray = []
	loader.stage_changed.connect(func(value: int) -> void: order.append(SuddenDeathLoader.STAGE_NAMES[value]))
	_start_measure()
	var begin_usec := Time.get_ticks_usec()
	loader.begin(world, gs)
	var begin_ms := float(Time.get_ticks_usec() - begin_usec) / 1000.0
	check(loader.stage() == Stage.LOADING and loader.progress() < 0.6, "begin() starts a threaded load")
	check(begin_ms < 20.0, "begin() does not block (%.2f ms)" % begin_ms)
	var progress_samples: Array[float] = []
	var loaded := await until(func() -> bool:
		progress_samples.append(loader.progress())
		return loader.stage() != Stage.LOADING, 20.0)
	check(loaded and loader.stage() == Stage.INSTANTIATE, "loaded; waits for heavy work (stage %s)" % loader.stage_name())
	check(_monotonic(progress_samples) and progress_samples.max() <= 0.6, "load progress rises within 0..0.6")
	await frames(10)
	check(loader.stage() == Stage.INSTANTIATE and loader.cistern() == null, "nothing is instantiated while heavy work is not allowed")
	check(is_equal_approx(loader.progress(), 0.6), "progress 0.6 after the load")
	loader.set_heavy_work_allowed(true)
	check(await until(func() -> bool: return loader.stage() == Stage.PARTS, 3.0), "instantiated once allowed")
	# A bright shot: heavy work pauses mid-build.
	loader.set_heavy_work_allowed(false)
	var parts_before := loader.cistern().parts_added_count()
	await frames(6)
	check(loader.cistern().parts_added_count() == parts_before and loader.stage() == Stage.PARTS, "part adds pause while heavy work is not allowed")
	loader.set_heavy_work_allowed(true)
	var built := await until(func() -> bool: return loader.stage() == Stage.PREWARM or loader.has_failed(), 10.0)
	var stage := loader.cistern()
	check(built and stage != null and loader.stage() == Stage.PREWARM, "parts, lift towers and water built")
	check(stage != null and stage.parts_added() and stage.is_runtime_built(), "all parts and the runtime are in")
	check(stage != null and not stage.visible, "the cistern stays hidden until presentable")
	await frames(10)
	check(loader.stage() == Stage.PREWARM and absf(loader.progress() - 0.9) < 0.001, "prewarm waits for presentable (progress %.3f)" % loader.progress())
	loader.set_presentable(true)
	var ready := await until(func() -> bool: return loader.is_ready() or loader.has_failed(), 10.0)
	_stop_measure()
	check(ready and loader.is_ready() and is_equal_approx(loader.progress(), 1.0), "READY (stage %s)" % loader.stage_name())
	check(order == EXPECTED_ORDER, "stages in order %s" % str(order))
	var snapshot := loader.get_debug_snapshot()
	var adds := _adds(snapshot)
	var frames_seen := {}
	var spread := true
	var add_max := 0.0
	var add_worst := ""
	for action: Dictionary in adds:
		spread = spread and not frames_seen.has(int(action.frame))
		frames_seen[int(action.frame)] = true
		if float(action.work_ms) > add_max:
			add_max = float(action.work_ms)
			add_worst = "%s/%s" % [action.stage, action.what]
	check(adds.filter(func(action: Dictionary) -> bool: return str(action.what) == "cistern_stage").size() == 1
		and adds.filter(func(action: Dictionary) -> bool: return str(action.stage) == "parts").size() == PART_COUNT
		and adds.filter(func(action: Dictionary) -> bool: return str(action.stage) == "runtime").size() == stage.runtime_step_count(),
		"1 instantiate + %d parts + %d runtime steps (%d adds incl. warm-up)" % [PART_COUNT, stage.runtime_step_count(), adds.size()])
	check(spread, "every add happens on its own frame")
	check(add_max <= ADD_BUDGET_MS, "no single add over %d ms (max %.2f ms: %s)" % [ADD_BUDGET_MS, add_max, add_worst])
	var compile: Dictionary = snapshot.compile
	check(bool(compile.get("settled", false)), "pipeline compilations settled for 3 frames (%s)" % str(compile))
	check(captures_exist(snapshot), "prewarm camera images saved")
	stage = loader.cistern()
	var lights: Dictionary = stage.get_debug_snapshot().lights
	var all_dark := true
	for amount: float in lights.brightness:
		all_dark = all_dark and amount == 0.0
	check(all_dark and float(lights.opening) == 0.0, "lights restored to 0 after the prewarm")
	check(stage.visible and loader.get_child_count() == 0, "cistern shown, prewarm viewports freed")
	check(stage.get_parent() == world and stage.position == Vector3.ZERO, "the cistern sits at the world origin under the parent")
	var runtime := await _runtime_smoke(stage)
	var shots := await _capture_views(stage)
	loader.cancel()
	await frames(2)
	check(not is_instance_valid(stage) and loader.stage() == Stage.IDLE, "cancel frees the cistern")
	loader.queue_free()
	return {"order": order, "frame_ms": _frame_stats(), "add_max_ms": add_max, "loader": snapshot, "runtime": runtime, "shots": shots}


func case_slow_load() -> Dictionary:
	var loader := _new_loader()
	loader.debug_extra_delay = SLOW_DELAY
	loader.set_heavy_work_allowed(true)
	loader.set_presentable(true)
	_start_measure()
	var started := Time.get_ticks_usec()
	loader.begin(world, gs)
	var samples: Array[float] = []
	await until(func() -> bool:
		samples.append(loader.progress())
		return loader.stage() != Stage.LOADING, SLOW_DELAY + 15.0)
	var load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	check(load_ms >= SLOW_DELAY * 1000.0 - 20.0, "extra delay holds the load (%.0f ms)" % load_ms)
	check(_monotonic(samples) and samples.max() <= 0.6, "load progress rises within 0..0.6 while delayed")
	var ready := await until(func() -> bool: return loader.is_ready() or loader.has_failed(), 15.0)
	_stop_measure()
	check(ready and loader.is_ready(), "slow load still reaches READY")
	var snapshot := loader.get_debug_snapshot()
	check(PackedStringArray(snapshot.order) == EXPECTED_ORDER, "slow load stage order %s" % str(snapshot.order))
	loader.cancel()
	loader.queue_free()
	await frames(2)
	return {"load_ms": snappedf(load_ms, 0.1), "frame_ms": _frame_stats(), "progress_samples": samples.size(), "loader": snapshot}


func case_load_fail() -> Dictionary:
	var loader := _new_loader()
	loader.debug_force_fail = true
	loader.set_heavy_work_allowed(true)
	loader.set_presentable(true)
	loader.begin(world, gs)
	var failed := await until(func() -> bool: return loader.has_failed(), 2.0)
	check(failed and loader.stage() == Stage.FAILED and loader.cistern() == null, "forced failure reports FAILED without a cistern")
	check(not loader.is_ready() and loader.progress() == 0.0, "failed loader is not ready")
	var snapshot := loader.get_debug_snapshot()
	check(str(snapshot.failure) == "debug_force_fail", "failure reason recorded")
	await frames(5)
	check(loader.stage() == Stage.FAILED and world.get_child_count() == 1, "stays failed and adds nothing")
	loader.cancel()
	check(loader.stage() == Stage.IDLE, "cancel after a failure returns to IDLE")
	loader.queue_free()
	return {"loader": snapshot}


## cancel() while loading, begin() again (adopts the running request), and withdraw
## presentable in the middle of the prewarm (restores and restarts it).
func case_cancel_restart() -> Dictionary:
	var loader := _new_loader()
	loader.begin(world, gs)
	await frames(1)
	loader.cancel()
	check(loader.stage() == Stage.IDLE and loader.cistern() == null, "cancel while loading")
	await frames(1)
	loader.set_heavy_work_allowed(true)
	loader.begin(world, gs)
	check(await until(func() -> bool: return loader.stage() == Stage.PREWARM or loader.has_failed(), 20.0), "restart reaches the prewarm")
	loader.set_presentable(true)
	await frames(2)
	var views := loader.get_child_count()
	loader.set_presentable(false)
	var stage := loader.cistern()
	check(views > 0 and loader.get_child_count() == 0 and stage != null and not stage.visible and not stage.is_prewarming(),
		"withdrawing presentable aborts the prewarm and hides the cistern (views %d)" % views)
	await frames(3)
	check(loader.stage() == Stage.PREWARM, "waits again in PREWARM")
	loader.set_presentable(true)
	check(await until(func() -> bool: return loader.is_ready(), 10.0), "prewarm restarts and finishes")
	var snapshot := loader.get_debug_snapshot()
	loader.cancel()
	loader.queue_free()
	await frames(2)
	check(world.get_child_count() == 1, "nothing left under the parent")
	return {"loader": snapshot}


# ------------------------------------------------------------------ runtime

## The lift towers and the water, driven by a real SuddenDeathState.
func _runtime_smoke(stage: CisternStage) -> Dictionary:
	var sd := gs.sudden_death
	var dt := 1.0 / 60.0
	# INTRO (descent, landing, rule card): the towers flush with the floor, the hall dry.
	for _step in range(10):
		sd.step(dt)
		stage.update_runtime(dt, sd)
	var intro := stage.get_debug_snapshot()
	check(sd.phase == SuddenDeathState.Phase.INTRO and int(intro.towers.built) == 2 and float(intro.towers.height[0]) == 0.0
		and not bool(intro.flow.flooding), "intro: towers flush with the floor, the hall dry (%s)" % str(intro.towers))
	var start := sd.tuning.lift_height(sd.tuning.start_margin)
	stage.set_tower_target(1, start, 2.4)
	stage.set_tower_target(2, start, 2.4)
	stage.start_flood()
	for _step in range(180):
		stage.update_runtime(dt, sd)
		await get_tree().process_frame
	var risen := stage.get_debug_snapshot()
	check(absf(float(risen.towers.height[0]) - start) < 0.01 and absf(float(risen.towers.height[1]) - start) < 0.01,
		"the towers lift to %.1f m (%s)" % [start, str(risen.towers)])
	check(bool(risen.flow.flooding) and (not bool(risen.flow.gpu) or int(risen.flow.steps) > 0), "the flood is out and the water runs (%s)" % str(risen.flow))
	# A step down after a wrong answer: the hydraulics ease the platform down and ripple the water.
	stage.set_tower_target(2, sd.tuning.lift_height(2))
	stage.on_event({"kind": "sink", "player": 2, "from": 4, "to": 2, "reason": "wrong"})
	for _step in range(150):
		stage.update_runtime(dt, sd)
		await get_tree().process_frame
	var sunk := stage.get_debug_snapshot()
	check(absf(float(sunk.towers.height[1]) - sd.tuning.lift_height(2)) < 0.01 and absf(float(sunk.towers.height[0]) - start) < 0.01,
		"one tower steps down, the other stands (%s)" % str(sunk.towers))
	stage.set_tower_glow(1, 1.0)
	stage.update_runtime(dt, sd)
	check(float(stage.get_debug_snapshot().towers.glow[0]) == 1.0, "the buzzer's tower lights up")
	return sunk


# ------------------------------------------------------------------ images

func _capture_views(stage: CisternStage) -> Array[String]:
	var saved: Array[String] = []
	var landing := Vector3(0.0, FLOOR_Y, 0.0)
	var environment := camera.environment
	# Let the smoke test's splash particles finish (freed after 1.6 s).
	await get_tree().create_timer(1.8).timeout
	stage.set_inflow_gate(0.0)
	# 2.2: darkness, only the cool column through the opening.
	stage.set_all_rows(0.0)
	stage.set_opening_light(1.0)
	CisternStage.apply_hall_light(environment, 0.0)
	saved.append(await _shot("01_intro_dark", landing + Vector3(0.0, 3.0, -7.0), landing + Vector3(0.0, 2.5, 40.0)))
	# The rows light up near to far.
	var lit := 0.0
	for row in range(stage.row_count()):
		var amount := 1.0 if row < 5 else (0.5 if row == 5 else 0.0)
		stage.set_row_brightness(row, amount)
		lit += amount / float(stage.row_count())
	CisternStage.apply_hall_light(environment, lit)
	saved.append(await _shot("02_rows_lighting", landing + Vector3(0.0, 3.0, -7.0), landing + Vector3(0.0, 2.5, 40.0)))
	stage.set_all_rows(1.0)
	CisternStage.apply_hall_light(environment, 1.0)
	saved.append(await _shot("03_gameplay_corridor", landing + Vector3(0.0, 5.1, -10.0), landing + Vector3(0.0, 2.0, 22.0)))
	saved.append(await _shot("04_opening_up", landing + Vector3(6.0, 1.8, 12.0), landing + Vector3(0.0, 18.0, 0.0)))
	stage.set_inflow_gate(1.0)
	saved.append(await _shot("05_upstream_balcony", landing + Vector3(4.0, 3.0, 16.0), landing + Vector3(8.0, 6.5, -30.0)))
	saved.append(await _shot("06_pillar_forest", landing + Vector3(-4.0, 15.5, -27.0), landing + Vector3(10.0, 4.0, 70.0)))
	saved.append(await _shot("07_downstream_end", landing + Vector3(0.0, 5.0, 186.0), landing + Vector3(0.0, 3.5, 210.0)))
	stage.set_all_rows(0.0)
	stage.set_opening_light(0.0)
	stage.set_inflow_gate(0.0)
	return saved


func _shot(tag: String, from: Vector3, to: Vector3) -> String:
	camera.look_at_from_position(from, to, Vector3.UP)
	# Volumetric fog reprojects over a few frames after a cut.
	await frames(12)
	await RenderingServer.frame_post_draw
	var path := out + tag + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	return path


# ------------------------------------------------------------------ helpers

func captures_exist(snapshot: Dictionary) -> bool:
	var captures: PackedStringArray = snapshot.get("captures", PackedStringArray())
	if captures.size() != 4:
		return false
	for path: String in captures:
		if not FileAccess.file_exists(path):
			return false
	return true


func _adds(snapshot: Dictionary) -> Array[Dictionary]:
	var adds: Array[Dictionary] = []
	for action: Dictionary in snapshot.actions:
		if str(action.stage) in ["instantiate", "parts", "runtime"]:
			adds.append(action)
	return adds


func _monotonic(values: Array[float]) -> bool:
	for index in range(1, values.size()):
		if values[index] < values[index - 1] - 0.0001:
			return false
	return true


func _start_measure() -> void:
	_frame_ms.clear()
	_frame_usec = 0
	_measuring = true


func _stop_measure() -> void:
	_measuring = false


func _frame_stats() -> Dictionary:
	if _frame_ms.is_empty():
		return {}
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	return {"frames": sorted.size(), "p50": snappedf(sorted[sorted.size() / 2], 0.01),
		"p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.01), "max": snappedf(sorted[sorted.size() - 1], 0.01),
		"over_50ms": sorted.filter(func(value: float) -> bool: return value > 50.0).size()}


func _write_report() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "quality": quality,
		"renderer": RenderingServer.get_current_rendering_method(), "cases": results}
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var summary := {}
	for case_name: String in results.keys():
		var result: Dictionary = results[case_name]
		var loader: Dictionary = result.get("loader", {})
		summary[case_name] = {"wall_ms": result.get("wall_ms"), "frame_ms": result.get("frame_ms", {}),
			"timings": loader.get("timings", {}), "compile": loader.get("compile", {}), "add_max_ms": result.get("add_max_ms", -1.0)}
	print("CISTERN_LOADER " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"quality": quality, "summary": summary}))


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
