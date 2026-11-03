extends Node

## 本物のメインメニューの上で、ローカル2Pのキーボード説明（3Dの机）を開く。
## モニターにメニューの背景のステージ（LiveViewport）が映ること、21:9 と 4:3 では真ん中を切り出すこと、
## キーを押すと手が動くこと、開始するとモニターへ寄ってそのまま本編へ入ることを撮る。
## 設定は書き換えない（保存先をテスト用に替え、最後に戻す）。
## 起動役は tests/tutorial_keyboard_desk_menu_bootstrap.gd。

const MAIN_MENU := "res://ui/main_menu.tscn"
const OUT := "res://artifacts/tutorial_keyboard_desk"
const SETTINGS := "user://tutorial_keyboard_desk_menu_settings.json"

var _checks := 0
var _failures: Array[String] = []
var _report := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var saved_settings_path: String = GameManager.settings_path
	GameManager.settings_path = SETTINGS
	# メニューの最初の演出（ロゴとのこぎりの船）は見たことにする。
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait_until(func() -> bool: return _menu() != null and _menu().get("_tutorial_keyboard_intro") != null, 15.0)
	_check(ready, "The main menu opens with the keyboard intro prepared")
	if ready:
		await _capture_intro()
	GameManager.settings_path = saved_settings_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "evidence": _report}
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT).path_join("menu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TUTORIAL_KEYBOARD_DESK_MENU " + JSON.stringify({"passed": report.passed, "checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture_intro() -> void:
	var menu := _menu()
	var selector: Control = menu.get("_tutorial_selector")
	if selector != null:
		selector.hide()
	menu.call("_start_tutorial_game", "LOCAL_2P")
	var intro: Control = menu.get("_tutorial_keyboard_intro")
	# 背景のステージを読み込んで描くまで待つ。
	await _seconds(2.5)
	var desk: Dictionary = intro.call("get_evidence").desk
	_check(intro.call("is_active") and desk.monitor_source == "live", "The desk monitor shows the menu's live stage")
	_check(is_equal_approx(desk.monitor_crop.x, 1.0) and is_equal_approx(desk.monitor_crop.y, 1.0), "A 16:9 window shows the whole picture")
	_report["menu_1280x720"] = desk
	await _shot("menu_desk_1280x720")
	await _tap_hold(KEY_9, 0.6, "menu_desk_press_9")
	get_tree().root.size = Vector2i(1680, 720)
	await _seconds(1.0)
	desk = intro.call("get_evidence").desk
	_check(absf(desk.monitor_crop.x - (16.0 / 9.0) / (1680.0 / 720.0)) < 0.02, "A 21:9 window crops the middle of the picture (%.3f)" % desk.monitor_crop.x)
	_report["menu_1680x720"] = desk
	await _shot("menu_desk_1680x720")
	get_tree().root.size = Vector2i(1024, 768)
	await _seconds(1.0)
	desk = intro.call("get_evidence").desk
	_check(is_equal_approx(desk.monitor_crop.x, 1.0) and absf(desk.monitor_crop.y - 0.75) < 0.02,
		"A 4:3 window crops the top and bottom of the picture (%.3f)" % desk.monitor_crop.y)
	_check(Rect2(Vector2.ZERO, intro.get_viewport_rect().size).encloses(intro.call("get_evidence").keyboard_rect),
		"The 3D keyboard stays on screen in a 4:3 window")
	_report["menu_1024x768"] = desk
	await _shot("menu_desk_1024x768")
	get_tree().root.size = Vector2i(1280, 720)
	await _seconds(0.5)
	# 開始：カメラがモニターへ寄り、寄り終えた画面を覆いにしたまま本編へ入る（丸い幕や LOADING は出ない）。
	(intro.call("get_start_button") as Button).pressed.emit()
	await _seconds(0.8)
	await _shot("menu_enter_monitor_mid")
	var covered := await _wait_until(func() -> bool: return SceneTransition.is_transitioning(), 3.0)
	_check(covered and str(SceneTransition.get("_active_style")) == "texture_hold",
		"Entering the monitor holds its last frame as the cover instead of the circle wipe")
	await _shot("menu_enter_monitor_cover")
	var arrived := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path.ends_with("game_world.tscn") and not SceneTransition.is_transitioning(), 40.0)
	_check(arrived, "The tutorial game appears from under the monitor frame")
	await _seconds(0.1)
	await _shot("menu_enter_game")


func _tap_hold(code: int, seconds: float, label: String) -> void:
	_send_key(code, true)
	await _seconds(seconds)
	await _shot(label)
	_send_key(code, false)
	await _seconds(0.5)


func _send_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _menu() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.name == "MainMenu" else null


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join(label + ".png"))


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)
