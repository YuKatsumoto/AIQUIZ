class_name SuddenDeathLoader
extends Node

## 地下神殿（CisternStage）の準備（docs/sudden_death_underground.md 5.5節）。
## 引き分けを検出した時点（決着演出0秒）から別スレッドで読み込み、許可された（暗いショットの）
## フレームだけで1フレームに1つずつ組み立てる：本体の追加 → 部分シーン（柱・小物・照明）
## → リフトのタワーと水（流体シミュレーション）。最後に、見せてよい状態（set_presentable）になったら小さな SubViewport で
## 地下神殿を一度描き、描画パイプラインのコンパイル数が3フレーム変わらなくなるまで待つ。
## メインスレッドで読み込みを待つことはない（load_threaded_get は読み込み完了後だけ呼ぶ）。

signal stage_changed(stage: int)

const CISTERN_SCENE := "res://scenes/sudden_death/cistern_stage.tscn"
enum Stage { IDLE, LOADING, INSTANTIATE, PARTS, RUNTIME, PREWARM, READY, FAILED }
const STAGE_NAMES: PackedStringArray = ["idle", "loading", "instantiate", "parts", "runtime", "prewarm", "ready", "failed"]

## progress(): 読み込み 0〜0.6、組み立て 0.6〜0.9（部分 0.6〜0.75、タワーと水 0.75〜0.9）、描画準備 0.9〜1。
const LOAD_SHARE := 0.6
const PARTS_END := 0.75
const RUNTIME_END := 0.9
## startup_loading.gd と同じ：コンパイル数が3フレーム続けて変わらなければ準備完了。
const PREWARM_STABLE_FRAMES := 3
## これを超えたら、落ち着かなくても READY にする（get_debug_snapshot の compile.settled = false）。
const PREWARM_MAX_FRAMES := 120
const PREWARM_FOV := 60.0
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const PREWARM_FAR := 260.0
## 本体を追加する前に、マテリアルのシェーダー生成（初回の get_rid で約50ms）を
## 1フレームあたりこの時間までに分けて行う。最低1つは進める。
const WARM_BUDGET_MS := 6.0

## 描画準備用の SubViewport の大きさ（カメラごとに1枚）。
var prewarm_size := Vector2i(480, 270)
## 空なら GameManager.graphics_quality。
var quality := ""
## 読み込み完了とみなすまでに足す秒数（テストの slow_load）。
var debug_extra_delay := 0.0
## 読み込みを失敗させる（テストの load_fail）。
var debug_force_fail := false
## テスト用：描画準備の最後に、各カメラの画像をこのフォルダーへ保存する（空なら保存しない）。
var debug_capture_dir := ""

var _stage := Stage.IDLE
var _parent: Node3D = null
var _state: QuizGameState = null
var _presentable := false
var _heavy_allowed := false
## A threaded request is outstanding (load_threaded_get not called yet).
var _requested := false
var _packed: PackedScene = null
var _cistern: CisternStage = null
var _environment: Environment = null
var _quality: String = GraphicsQualityRules.BALANCED
var _load_progress := 0.0
var _runtime_setup := false
var _failure := ""
## Materials and meshes of the stage and its parts whose first get_rid() is still pending.
var _warm_queue: Array[Resource] = []
var _warm_collected := false
## Prewarm cameras still to add (one a frame).
var _pending_prewarm_views: Array[Dictionary] = []
## CisternFlow.warm_up_step() has nothing left (it keeps its work for the next match).
var _flood_warm := false
## Keeps the runtime shader samples (and so their compiled shaders) alive until READY.
var _warm_keep: Array[Material] = []

var _begin_usec := 0
var _stage_usec := 0
var _last_frame_usec := 0
## The stage whose work the previous frame did (its interval is measured next frame).
var _previous_frame_stage := -1
var _pending_action := -1
## stage name -> {"ms", "frames", "work_ms_max", "frame_ms_max", "first_frame"}
var _timings := {}
var _actions: Array[Dictionary] = []
var _stage_order: PackedStringArray = []

var _prewarm_views: Array[SubViewport] = []
var _prewarm_frames := 0
var _prewarm_stable := 0
var _prewarm_previous: Array[int] = []
var _compile := {}
var _captures: PackedStringArray = []


func _init() -> void:
	name = "SuddenDeathLoader"
	process_mode = Node.PROCESS_MODE_ALWAYS


## 読み込みを始める（別スレッド）。ここでは待たない。parent は地下神殿を置くノード（ワールド原点）。
func begin(parent: Node3D, state: QuizGameState) -> void:
	cancel()
	_parent = parent
	_state = state
	_quality = GraphicsQualityRules.normalize(quality if not quality.is_empty() else GameManager.graphics_quality)
	_environment = CisternStage.make_environment(_quality)
	_begin_usec = Time.get_ticks_usec()
	_last_frame_usec = 0
	_previous_frame_stage = -1
	_pending_action = -1
	_timings.clear()
	_actions.clear()
	_stage_order.clear()
	_compile.clear()
	_captures.clear()
	_load_progress = 0.0
	_runtime_setup = false
	_warm_queue.clear()
	_warm_keep.clear()
	_warm_collected = false
	_failure = ""
	_enter_stage(Stage.LOADING)
	if parent == null:
		_fail("no parent for the cistern")
		return
	if debug_force_fail:
		return # Fails on the first poll, like a real failed load.
	if _requested:
		return # A cancelled request for the same scene is still running: adopt it.
	var error := ResourceLoader.load_threaded_request(CISTERN_SCENE)
	if error != OK:
		_fail("load_threaded_request: " + error_string(error))
		return
	_requested = true


## 地下神殿を見せてよいか。true の間だけ表示し、描画準備（PREWARM）もこの間だけ行う。
func set_presentable(on: bool) -> void:
	_presentable = on
	if not on and not _prewarm_views.is_empty():
		_stop_prewarm(false)
	if is_instance_valid(_cistern):
		_cistern.visible = on


## 重い処理（本体の追加・部分シーンの追加・タワーと水の作成）をしてよいか（暗いショットの間）。
func set_heavy_work_allowed(on: bool) -> void:
	_heavy_allowed = on


func progress() -> float:
	match _stage:
		Stage.LOADING:
			var time_fraction := 1.0
			if debug_extra_delay > 0.0:
				time_fraction = clampf(_elapsed_sec() / debug_extra_delay, 0.0, 1.0)
			return LOAD_SHARE * minf(_load_progress, time_fraction)
		Stage.INSTANTIATE:
			return LOAD_SHARE
		Stage.PARTS:
			var parts := float(_cistern.part_count()) if is_instance_valid(_cistern) else 1.0
			var done := float(_cistern.parts_added_count()) if is_instance_valid(_cistern) else 0.0
			return lerpf(LOAD_SHARE, PARTS_END, done / maxf(parts, 1.0))
		Stage.RUNTIME:
			if not is_instance_valid(_cistern):
				return PARTS_END
			return lerpf(PARTS_END, RUNTIME_END, float(_cistern.runtime_steps_done()) / float(_cistern.runtime_step_count()))
		Stage.PREWARM:
			return RUNTIME_END + 0.09 * clampf(float(_prewarm_stable) / float(PREWARM_STABLE_FRAMES), 0.0, 1.0)
		Stage.READY:
			return 1.0
		Stage.FAILED:
			return 0.0
	return 0.0


func is_ready() -> bool:
	return _stage == Stage.READY


func has_failed() -> bool:
	return _stage == Stage.FAILED


func stage() -> int:
	return _stage


func stage_name() -> String:
	return STAGE_NAMES[_stage]


func cistern() -> CisternStage:
	return _cistern if is_instance_valid(_cistern) else null


## 描画準備に使った環境。本番のカメラにも同じものを使うと、準備したパイプラインがそのまま使える。
func environment() -> Environment:
	return _environment


## 全部捨てて止める。読み込み中のリクエストは裏で終わるのを待って解放する。
func cancel() -> void:
	_stop_prewarm(false)
	if is_instance_valid(_cistern):
		_cistern.visible = false
		_cistern.queue_free()
	_cistern = null
	_packed = null
	_parent = null
	_state = null
	_warm_queue.clear()
	_warm_keep.clear()
	if _stage != Stage.IDLE:
		_enter_stage(Stage.IDLE)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now
	if _previous_frame_stage >= 0 and frame_ms > 0.0:
		var timing := _timing(STAGE_NAMES[_previous_frame_stage])
		timing.frame_ms_max = maxf(float(timing.frame_ms_max), frame_ms)
	if _pending_action >= 0 and _pending_action < _actions.size():
		_actions[_pending_action].frame_ms = snappedf(frame_ms, 0.01)
	_pending_action = -1
	if _requested and _stage != Stage.LOADING:
		_drain_request()
	var working := _stage
	match _stage:
		Stage.LOADING:
			_poll_load()
		Stage.INSTANTIATE:
			if _heavy_allowed:
				if _warm_step():
					_instantiate()
		Stage.PARTS:
			if _heavy_allowed:
				_add_part()
		Stage.RUNTIME:
			if _heavy_allowed:
				_build_runtime()
		Stage.PREWARM:
			_prewarm_step()
	# This frame's interval (measured next frame) belongs to the stage that worked in it.
	var active := working not in [Stage.IDLE, Stage.READY, Stage.FAILED]
	_previous_frame_stage = working if active else -1
	if active:
		_timing(STAGE_NAMES[working]).frames = int(_timing(STAGE_NAMES[working]).frames) + 1


# ------------------------------------------------------------------ stages

func _poll_load() -> void:
	if debug_force_fail:
		_fail("debug_force_fail")
		return
	var progress_out: Array = []
	var status := ResourceLoader.load_threaded_get_status(CISTERN_SCENE, progress_out)
	if not progress_out.is_empty():
		_load_progress = maxf(_load_progress, float(progress_out[0]))
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_load_progress = 1.0
			if _elapsed_sec() < debug_extra_delay:
				return
			# Never call get before LOADED: it would block the main thread.
			var start := Time.get_ticks_usec()
			var resource := ResourceLoader.load_threaded_get(CISTERN_SCENE)
			_requested = false
			_record("loading", "load_threaded_get", start)
			_packed = resource as PackedScene
			if _packed == null:
				_fail("%s is not a PackedScene" % CISTERN_SCENE)
				return
			_enter_stage(Stage.INSTANTIATE)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_requested = false
			_fail("threaded load status %d" % status)


## The first get_rid() of a StandardMaterial3D generates and compiles its shader on the
## main thread (~50 ms for the stage on the dev PC). Do it a few per frame before the
## instantiation, which then costs about a millisecond. True when nothing is left.
func _warm_step() -> bool:
	var start := Time.get_ticks_usec()
	if not _warm_collected:
		_warm_collected = true
		_warm_keep = CisternStage.runtime_shader_samples()
		for material: Material in _warm_keep:
			_warm_queue.append(material)
		_collect_warm_resources(_packed, {})
		_record("instantiate", "collect %d resources" % _warm_queue.size(), start)
		return false
	if _warm_queue.is_empty():
		if _flood_warm:
			return true
		# The water's materials (each new shader compiles when first set), one piece a frame.
		_flood_warm = CisternFlow.warm_up_step(_quality)
		_record("instantiate", "flow warm-up", start)
		return false
	var count := 0
	while not _warm_queue.is_empty():
		var resource: Resource = _warm_queue.pop_back()
		if resource is Material:
			(resource as Material).get_rid()
		elif resource is Mesh:
			(resource as Mesh).get_rid()
		count += 1
		if float(Time.get_ticks_usec() - start) / 1000.0 >= WARM_BUDGET_MS:
			break
	_record("instantiate", "warm %d" % count, start)
	return false


func _collect_warm_resources(scene: PackedScene, seen: Dictionary) -> void:
	if scene == null or seen.has(scene):
		return
	seen[scene] = true
	var state := scene.get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			_collect_warm_value(state.get_node_property_value(node, property), seen)


func _collect_warm_value(value: Variant, seen: Dictionary) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_warm_value(item, seen)
	elif value is PackedScene:
		_collect_warm_resources(value as PackedScene, seen)
	elif value is MultiMesh:
		_collect_warm_value((value as MultiMesh).mesh, seen)
	elif (value is Material or value is Mesh) and not seen.has(value):
		seen[value] = true
		_warm_queue.append(value as Resource)


func _instantiate() -> void:
	if not is_instance_valid(_parent):
		_fail("the cistern parent was freed")
		return
	var start := Time.get_ticks_usec()
	var node := _packed.instantiate()
	_cistern = node as CisternStage
	if _cistern == null:
		if node != null:
			node.free()
		_fail("%s root is not a CisternStage" % CISTERN_SCENE)
		return
	_cistern.visible = _presentable
	_cistern.apply_quality(_quality)
	var instantiated := Time.get_ticks_usec()
	_parent.add_child(_cistern)
	var action := _record("instantiate", "cistern_stage", start)
	action["instantiate_ms"] = snappedf(float(instantiated - start) / 1000.0, 0.01)
	action["add_child_ms"] = snappedf(float(Time.get_ticks_usec() - instantiated) / 1000.0, 0.01)
	# The instance keeps what it uses; dropping the scene lets the cache release it with the stage.
	_packed = null
	_enter_stage(Stage.PARTS)


func _add_part() -> void:
	var start := Time.get_ticks_usec()
	var index := _cistern.parts_added_count()
	var done := _cistern.add_part_step()
	var scene: PackedScene = _cistern.part_scenes[index] if index < _cistern.part_scenes.size() else null
	_record("parts", scene.resource_path.get_file().get_basename() if scene != null else "none", start)
	if done:
		_enter_stage(Stage.RUNTIME)


func _build_runtime() -> void:
	var start := Time.get_ticks_usec()
	if not _runtime_setup:
		_runtime_setup = true
		_cistern.setup_runtime(_state)
	var step := _cistern.runtime_steps_done()
	var done := _cistern.build_runtime_step()
	_record("runtime", ["tower P1", "tower P2", "flow", "lights"][mini(step, 3)], start)
	if done:
		_enter_stage(Stage.PREWARM)


func _prewarm_step() -> void:
	if not _presentable:
		return
	if _prewarm_views.is_empty():
		_start_prewarm()
		return
	_prewarm_frames += 1
	# The cistern shows its effects a few at a time (the first draw of each compiles its pipelines).
	_cistern.prewarm_tick(_prewarm_frames)
	if not _pending_prewarm_views.is_empty():
		# One more camera a frame: each first render of the hall from a new place costs a frame of its own.
		_add_prewarm_view(_pending_prewarm_views.pop_front())
		_prewarm_stable = 0
		_prewarm_previous = _pipeline_counts()
		return
	var current := _pipeline_counts()
	_prewarm_stable = _prewarm_stable + 1 if current == _prewarm_previous else 0
	_prewarm_previous = current
	if _prewarm_stable >= PREWARM_STABLE_FRAMES or _prewarm_frames >= PREWARM_MAX_FRAMES:
		_compile["after"] = current
		_compile["frames"] = _prewarm_frames
		_compile["settled"] = _prewarm_stable >= PREWARM_STABLE_FRAMES
		var compiled := 0
		var before: Array = _compile.get("before", [0, 0, 0, 0])
		for index in range(current.size()):
			compiled += current[index] - int(before[index])
		_compile["compiled"] = compiled
		if not bool(_compile.settled):
			push_warning("[SuddenDeathLoader] pipelines still compiling after %d frames" % _prewarm_frames)
		_stop_prewarm(true)
		_warm_keep.clear()
		_enter_stage(Stage.READY)


## Shows everything once through small cameras that share the game world, so the
## materials, lights, fog and the shaft light's shadow compile before the plunge.
func _start_prewarm() -> void:
	var start := Time.get_ticks_usec()
	_cistern.visible = true
	_cistern.begin_prewarm()
	_pending_prewarm_views.clear()
	for view: Dictionary in _cistern.prewarm_views():
		_pending_prewarm_views.append(view)
	_add_prewarm_view(_pending_prewarm_views.pop_front())
	_prewarm_frames = 0
	_prewarm_stable = 0
	_prewarm_previous = _pipeline_counts()
	_compile["before"] = _prewarm_previous.duplicate()
	_compile["views"] = _pending_prewarm_views.size() + 1
	_record("prewarm", "start", start)


func _add_prewarm_view(view: Dictionary) -> void:
	var main := _parent.get_viewport()
	var world := main.find_world_3d()
	var viewport := SubViewport.new()
	viewport.name = "CisternPrewarm_" + str(view.name)
	viewport.size = prewarm_size
	viewport.own_world_3d = false
	viewport.world_3d = world
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	# Same framebuffer and shadow formats as the game view, so the same pipelines compile.
	viewport.msaa_3d = main.msaa_3d
	viewport.screen_space_aa = main.screen_space_aa
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = main.positional_shadow_atlas_size
	viewport.positional_shadow_atlas_16_bits = main.positional_shadow_atlas_16_bits
	for quadrant in range(4):
		viewport.set_positional_shadow_atlas_quadrant_subdiv(quadrant, main.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = PREWARM_FOV
	camera.near = 0.1
	camera.far = PREWARM_FAR
	camera.environment = _environment
	viewport.add_child(camera)
	add_child(viewport)
	camera.look_at_from_position(view.from, view.to, Vector3.UP)
	camera.current = true
	_prewarm_views.append(viewport)


func _stop_prewarm(finished: bool) -> void:
	_pending_prewarm_views.clear()
	if _prewarm_views.is_empty():
		return
	if finished and not debug_capture_dir.is_empty():
		var capture_start := Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(debug_capture_dir))
		for viewport: SubViewport in _prewarm_views:
			var path := debug_capture_dir.path_join("prewarm_%s.png" % str(viewport.name).trim_prefix("CisternPrewarm_"))
			var image := viewport.get_texture().get_image()
			if image != null and image.save_png(path) == OK:
				_captures.append(path)
		_record("debug", "capture", capture_start)
	var start := Time.get_ticks_usec()
	for viewport: SubViewport in _prewarm_views:
		if is_instance_valid(viewport):
			remove_child(viewport)
			viewport.queue_free()
	_prewarm_views.clear()
	_prewarm_stable = 0
	if is_instance_valid(_cistern):
		_cistern.end_prewarm()
		_cistern.visible = _presentable
	_record("prewarm", "finish" if finished else "abort", start)


## A request left behind by cancel(): release it once the loader thread is done.
func _drain_request() -> void:
	var status := ResourceLoader.load_threaded_get_status(CISTERN_SCENE)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(CISTERN_SCENE)
	_requested = false


func _fail(message: String) -> void:
	_failure = message
	push_warning("[SuddenDeathLoader] " + message)
	_stop_prewarm(false)
	if is_instance_valid(_cistern):
		_cistern.queue_free()
	_cistern = null
	_packed = null
	_enter_stage(Stage.FAILED)


func _enter_stage(next: int) -> void:
	var now := Time.get_ticks_usec()
	if _stage not in [Stage.IDLE, Stage.READY, Stage.FAILED] and _timings.has(STAGE_NAMES[_stage]):
		_timing(STAGE_NAMES[_stage]).ms = snappedf(float(now - _stage_usec) / 1000.0, 0.01)
	_stage = next
	_stage_usec = now
	_stage_order.append(STAGE_NAMES[next])
	if next not in [Stage.IDLE, Stage.READY, Stage.FAILED]:
		_timing(STAGE_NAMES[next]).first_frame = Engine.get_process_frames()
	stage_changed.emit(next)


func _timing(stage_key: String) -> Dictionary:
	if not _timings.has(stage_key):
		_timings[stage_key] = {"ms": 0.0, "frames": 0, "work_ms_max": 0.0, "frame_ms_max": 0.0, "first_frame": -1}
	return _timings[stage_key]


func _record(stage_key: String, what: String, start_usec: int) -> Dictionary:
	var work_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var timing := _timing(stage_key)
	timing.work_ms_max = maxf(float(timing.work_ms_max), work_ms)
	var action := {"stage": stage_key, "what": what, "frame": Engine.get_process_frames(),
		"work_ms": snappedf(work_ms, 0.01), "frame_ms": -1.0}
	_actions.append(action)
	_pending_action = _actions.size() - 1
	return action


func _elapsed_sec() -> float:
	return float(Time.get_ticks_usec() - _begin_usec) / 1000000.0


func _pipeline_counts() -> Array[int]:
	return [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
	]


func get_debug_snapshot() -> Dictionary:
	var timings := {}
	for key: String in _timings.keys():
		var timing: Dictionary = _timings[key]
		timings[key] = {"ms": timing.ms, "frames": timing.frames, "first_frame": timing.first_frame,
			"work_ms_max": snappedf(float(timing.work_ms_max), 0.01), "frame_ms_max": snappedf(float(timing.frame_ms_max), 0.01)}
	return {
		"stage": STAGE_NAMES[_stage], "stage_id": _stage, "progress": snappedf(progress(), 0.001),
		"order": _stage_order, "presentable": _presentable, "heavy_work_allowed": _heavy_allowed,
		"quality": _quality, "failure": _failure, "elapsed_ms": snappedf(_elapsed_sec() * 1000.0, 0.1) if _begin_usec > 0 else 0.0,
		"extra_delay": debug_extra_delay, "timings": timings, "actions": _actions.duplicate(true),
		"compile": _compile.duplicate(true), "captures": _captures,
		"cistern": _cistern.get_debug_snapshot() if is_instance_valid(_cistern) else {},
	}
