extends Node

## Android back gesture, app pause/resume and audio handling (Android port).
##
## Only the mobile target (GraphicsQuality.is_mobile_target(), including the desktop
## --mobile-preview) reacts; desktop ignores every notification here.
##
## - Back gesture (NOTIFICATION_WM_GO_BACK_REQUEST, needs quit_on_go_back=false): emits
##   back_requested and sends an Escape press and release. InputMap's ui_cancel contains Escape,
##   so screens that check the Escape key and screens that check ui_cancel both react, once each
##   (a separate ui_cancel InputEventAction would make the ui_cancel screens react twice).
##   While the quit dialog is open, back closes it.
## - Going to the background (APPLICATION_PAUSED / FOCUS_OUT): lets go of every touch key, mutes
##   the master bus, saves the settings and pauses an offline match (game_world.pause_for_background;
##   online matches never stop). Coming back (RESUMED / FOCUS_IN) unmutes.

signal back_requested

const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const FONT_PATH := "res://resources/fonts/NotoSansJP-Bold.otf"
## Above every game layer (pause menu 100, SceneTransition 100, practice coach 106) but under the
## "本体をひらいて" notice (TouchControls, 127).
const QUIT_LAYER := 126

var _enabled := false
## The master bus was muted by us (not by the player or another screen).
var _muted_by_background := false
var _quit_layer: CanvasLayer = null
var _quit_cancel: Button = null

const PERF_LOG_INTERVAL_SEC := 5.0
const DEBUG_COMMAND_POLL_SEC := 0.5
const DEBUG_COMMAND_PATH := "user://aiq_cmd.gd"
const DEBUG_OUTPUT_PATH := "user://aiq_out.txt"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = QualityRules.is_mobile_target()
	set_process(false)
	# Device debug builds report performance to logcat (adb logcat -s godot | grep AIQ_PERF).
	if OS.has_feature("mobile") and OS.is_debug_build():
		var timer := Timer.new()
		timer.wait_time = PERF_LOG_INTERVAL_SEC
		timer.timeout.connect(_log_perf)
		add_child(timer)
		timer.start()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var probe := Timer.new()
		probe.wait_time = DEBUG_COMMAND_POLL_SEC
		probe.timeout.connect(_run_debug_command)
		add_child(probe)
		probe.start()


## Device debug builds only: a script pushed to user://aiq_cmd.gd
## (`extends RefCounted` + `func run(tree: SceneTree) -> Variant`) runs once and its result
## lands in user://aiq_out.txt, so a phone can be inspected without a debugger.
func _run_debug_command() -> void:
	if not FileAccess.file_exists(DEBUG_COMMAND_PATH):
		return
	var source := FileAccess.get_file_as_string(DEBUG_COMMAND_PATH)
	DirAccess.remove_absolute(DEBUG_COMMAND_PATH)
	var script := GDScript.new()
	script.source_code = source
	var result: Variant = "compile error"
	if script.reload() == OK:
		var command: Object = script.new()
		result = command.call("run", get_tree()) if command.has_method("run") else "no run()"
	var out := FileAccess.open(DEBUG_OUTPUT_PATH, FileAccess.WRITE)
	if out != null:
		out.store_string(var_to_str(result))
		out.close()


func _log_perf() -> void:
	var root := get_viewport()
	var scene := get_tree().current_scene
	print("AIQ_PERF fps=%d process_ms=%.1f physics_ms=%.1f cpu_ms=%.1f gpu_ms=%.1f scale3d=%.2f objects=%d draws=%d nodes=%d prims_k=%d vram_mb=%d mem_mb=%d scene=%s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		root.scaling_3d_scale,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(OS.get_static_memory_usage() / 1048576.0),
		scene.scene_file_path.get_file() if scene != null else "-",
	])


## Runs only while focus is elsewhere (notification shade, split screen): a match in
## FLYOVER/CORRECT cannot pause yet and would otherwise reach PLAYING unattended.
func _process(_delta: float) -> void:
	var world := _current_game_world()
	if world != null:
		world.call("pause_for_background")


func _notification(what: int) -> void:
	if not _enabled:
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back()
		NOTIFICATION_APPLICATION_PAUSED:
			_enter_background(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_enter_background(false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_leave_background()


## Shows "ゲームを終了しますか？" with big buttons; 「終了する」 quits the app.
func request_quit_confirm() -> void:
	if _quit_layer == null:
		_build_quit_dialog()
	if _quit_layer.visible:
		return
	_quit_layer.visible = true
	# No keyboard focus (injected Enter must not quit by accident); the buttons are tapped.
	get_viewport().gui_release_focus()


func is_quit_confirm_open() -> bool:
	return _quit_layer != null and _quit_layer.visible


func close_quit_confirm() -> void:
	if _quit_layer != null:
		_quit_layer.visible = false


# ---------- Back gesture ----------

func _on_back() -> void:
	if is_quit_confirm_open():
		close_quit_confirm()
		return
	back_requested.emit()
	# The same Escape a keyboard sends: game_world's Esc branch (pause, online quit confirm,
	# practice), menus that close on Escape or on ui_cancel.
	_send_escape(true)
	_send_escape(false)


func _send_escape(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	Input.parse_input_event(event)


# ---------- Background / foreground ----------

func _enter_background(app_paused: bool) -> void:
	set_process(true)
	TouchControls.release_all()
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0 and not AudioServer.is_bus_mute(master_bus):
		AudioServer.set_bus_mute(master_bus, true)
		_muted_by_background = true
	if app_paused:
		# Samsung freely kills background apps (and no close request comes then): write the settings now.
		GameManager._save_user_settings()
	var world := _current_game_world()
	if world != null:
		world.call("pause_for_background")


func _leave_background() -> void:
	set_process(false)
	if not _muted_by_background:
		return
	_muted_by_background = false
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, false)


func _current_game_world() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("pause_for_background"):
		return scene
	return null


# ---------- Quit dialog ----------

func _build_quit_dialog() -> void:
	var font := load(FONT_PATH) as Font
	_quit_layer = CanvasLayer.new()
	_quit_layer.name = "QuitConfirm"
	_quit_layer.layer = QUIT_LAYER
	_quit_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_layer.visible = false
	add_child(_quit_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2, 0.97)
	style.border_color = Color(1, 1, 1, 0.35)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 36
	style.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 32)
	panel.add_child(column)

	var title := Label.new()
	title.text = "ゲームを終了しますか？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", MobileUi.font(36))
	column.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	column.add_child(row)

	_quit_cancel = _make_dialog_button("やめない", font)
	_quit_cancel.pressed.connect(close_quit_confirm)
	row.add_child(_quit_cancel)
	var quit_button := _make_dialog_button("終了する", font)
	quit_button.pressed.connect(func() -> void:
		GameManager._save_user_settings()
		get_tree().quit()
	)
	row.add_child(quit_button)


func _make_dialog_button(text: String, font: Font) -> Button:
	# メニュー画面と同じ金属プレート（MenuMetalButton）
	var button := MenuMetalButton.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(240, 96)
	MobileUi.ensure_touch_size(button)
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", MobileUi.font(30))
	return button
