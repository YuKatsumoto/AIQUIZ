extends CanvasLayer

## A real boot cover, retained through change_scene until the menu is drawn.
## Resource I/O runs on the loader thread; scene mutations stay on the main thread.
## 2D lettering and the progress bar paint before the 3D flair is constructed.
## The live Label is the source of truth; do not snapshot it into a SubViewport.
const MENU_PATH := "res://ui/main_menu.tscn"
const PROGRESS_HEIGHT := 8.0
var _cover: ColorRect
var _holder: Control
var _status: Label
var _stage := ""
var _stage_progress := 0.0
var _character: Control
var _started_usec: int
var _last_frame_usec: int
var _max_frame_ms := 0.0
var _render_frames := 0
var _failed := false
var _retained_paths: Array[String] = []
var _progress: ProgressBar

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.startup_loading = true
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	_build_screen()
	_run.call_deferred()

func _build_screen() -> void:
	_cover = ColorRect.new()
	_cover.name = "BootCover"
	_cover.color = Color.BLACK
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	# Match the existing stage-transition layout, including its exact label style.
	_holder = Control.new()
	_holder.name = "StartupFlairHolder"
	_holder.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_holder.offset_left = SceneTransition.LOADING_REST_LEFT
	_holder.offset_right = SceneTransition.LOADING_REST_LEFT + SceneTransition.LOADING_HOLDER_SIZE.x
	_holder.offset_top = -SceneTransition.LOADING_BOTTOM - SceneTransition.LOADING_HOLDER_SIZE.y
	_holder.offset_bottom = -SceneTransition.LOADING_BOTTOM
	_cover.add_child(_holder)
	_status = Label.new()
	_status.name = "LoadingLabel"
	_status.text = "LOADING..."
	_status.position = Vector2(96.0, 56.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0))
	_status.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.12, 1.0))
	_status.add_theme_constant_override("outline_size", 4)
	_holder.add_child(_status)
	_progress = ProgressBar.new()
	_progress.name = "PreparationProgress"
	_progress.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_progress.offset_left = SceneTransition.LOADING_REST_LEFT
	_progress.offset_right = SceneTransition.LOADING_REST_LEFT + 220.0
	_progress.offset_top = -SceneTransition.LOADING_BOTTOM + 4.0
	_progress.offset_bottom = -SceneTransition.LOADING_BOTTOM + 4.0 + PROGRESS_HEIGHT
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.30, 0.40)
	track.border_color = Color(0.55, 0.72, 0.92, 0.85)
	track.set_border_width_all(1)
	track.content_margin_left = 1.0
	track.content_margin_top = 1.0
	track.content_margin_right = 1.0
	track.content_margin_bottom = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.48, 0.72, 0.96)
	_progress.add_theme_stylebox_override("background", track)
	_progress.add_theme_stylebox_override("fill", fill)
	_cover.add_child(_progress)

func _spawn_flair_character() -> void:
	if _character != null or _holder == null:
		return
	_character = load("res://scripts/ui/loading_character_3d.gd").new()
	_character.name = "FlairCharacter"
	_character.set("emote_id", EmoteData.EMOTE_FLAIR)
	_character.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(_character)
	_holder.move_child(_character, 0)
	# Leave horizontal room for both legs throughout the Flair loop.
	var camera: Camera3D = _character.get("_camera")
	if camera != null:
		camera.position = Vector3(0.0, -0.25, 5.0)
		camera.fov = 38.0
		camera.look_at(Vector3(0.0, -0.3, 0.0))
	_character.call("set_active", true)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_max_frame_ms = maxf(_max_frame_ms, float(now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	_render_frames += 1

func _input(event: InputEvent) -> void:
	# Keep controller/keyboard shortcuts from reaching the covered menu.
	if not event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()

func _set_stage(text: String, progress: float) -> void:
	_stage = text
	_stage_progress = progress
	_progress.value = progress
	await _draw_frame()

func _draw_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	await get_tree().process_frame

func _load_resource(path: String) -> Resource:
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		_fail("素材を読み込めませんでした", path)
		return null
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			# Never call get before LOADED: it would block the animation.
			var resource := ResourceLoader.load_threaded_get(path)
			GameManager.startup_resources.append(resource)
			_retained_paths.append(path)
			return resource
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("素材を読み込めませんでした", path)
			return null
		await get_tree().process_frame
	return null

func _fail(message: String, detail: String) -> void:
	_failed = true
	if _status != null:
		_status.show()
		_status.text = message + "\nゲームを再起動してください"
	GameManager.startup_report = {"ready": false, "error": detail}
	push_error("[StartupLoading] " + detail)

func _run() -> void:
	_status.reset_size()
	# Paint the 2D cover, lettering, and bar before constructing the 3D flair.
	await _draw_frame()
	await _draw_frame()
	_spawn_flair_character()
	await _draw_frame()
	await _set_stage("ゲームの素材を読み込んでいます", 5)
	var menu := await _load_resource(MENU_PATH) as PackedScene
	if _failed or menu == null:
		return
	var paths: Array[String] = []
	for path: String in AnimationRig.FBX_PATHS:
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	for emote_id: int in EmoteData.merge_emote_slot_ids(
		QuizManager.game_state.p1_emote_slots, EmoteData.get_menu_preview_rig_slots()):
		var path := EmoteData.get_emote_fbx(emote_id)
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	for emote_id: int in EmoteData.merge_emote_slot_ids(
		QuizManager.game_state.p2_emote_slots, EmoteData.get_menu_preview_rig_slots(true)):
		var path := EmoteData.get_emote_fbx(emote_id)
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	paths.append_array([
		"res://assets/vehicles/helicopter/helicopter_drop.glb",
		"res://assets/characters/godot_plush/godot_plush_model.glb",
		"res://scripts/world/startup_visual_warmup.gd",
	])
	for index: int in range(paths.size()):
		await _set_stage("キャラクターを準備しています", 20.0 + 35.0 * index / paths.size())
		await _load_resource(paths[index])
		if _failed:
			return
	await _set_stage("演出を準備しています", 60)
	var warmup: Node = load("res://scripts/world/startup_visual_warmup.gd").new()
	add_child(warmup)
	warmup.step_completed.connect(_on_warmup_step)
	var effects_report: Dictionary = await warmup.run()
	if not bool(effects_report.get("ready", false)):
		_fail("演出を準備できませんでした", str(effects_report))
		return
	warmup.queue_free()
	await _draw_frame()
	await _set_stage("メニューを準備しています", 90)
	var error := get_tree().change_scene_to_packed(menu)
	if error != OK:
		_fail("メニューを開けませんでした", error_string(error))
		return
	await get_tree().scene_changed
	# Rendering must happen before dropping the cover, including Surface/Canvas.
	var stable_frames := 0
	var previous := _pipeline_counts()
	for frame: int in range(120):
		await _draw_frame()
		var current := _pipeline_counts()
		stable_frames = stable_frames + 1 if current == previous else 0
		previous = current
		if stable_frames >= 3:
			break
	if stable_frames < 3:
		_fail("描画の準備を完了できませんでした", "Menu pipelines did not settle")
		return
	await _set_stage("準備ができました", 100)
	GameManager.startup_report = {
		"ready": true, "emote_id": EmoteData.EMOTE_FLAIR,
		"resources": _retained_paths, "effects": effects_report,
		"elapsed_ms": (Time.get_ticks_usec() - _started_usec) / 1000.0,
		"covered_max_frame_ms": _max_frame_ms, "frames": _render_frames,
		"renderer": RenderingServer.get_current_rendering_method(),
	}
	print("STARTUP_LOADING " + JSON.stringify(GameManager.startup_report))
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", 0.0, 0.25)
	await tween.finished
	GameManager.startup_loading = false
	GameManager.startup_finished.emit()
	queue_free()

func _on_warmup_step(fraction: float) -> void:
	_stage_progress = 60.0 + fraction * 28.0
	_progress.value = _stage_progress

func _pipeline_counts() -> Array[int]:
	return [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
	]
