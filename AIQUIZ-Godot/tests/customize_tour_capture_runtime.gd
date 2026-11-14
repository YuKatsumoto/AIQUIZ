extends Node

## コース⑤（カスタマイズの紹介。画像カード）で見せる画像を、いまの本物のメニューから撮る。
##   メニュー（『10問チャレンジ』の設定の画面）→ カスタマイズ（スキン・エモート・壁速度）→ 設定パネル
## 撮った画像は artifacts/customize_tour/ に、光らせる部品の場所（画像に対する割合）は artifacts/customize_tour/focus.json に書く。
## 使う画像は assets/ui/tutorial/ へ写し、枠の場所は scripts/practice/menu/practice_customize_guide.gd の PAGES へ写す。
## 設定とスキンの保存先はテスト用に差し替え、撮り終わったら元に戻す。ウィンドウありで流す：
##   Godot --path . --resolution 1280x720 --script tests/customize_tour_capture_bootstrap.gd

const OUT := "res://artifacts/customize_tour/"
const SETTINGS := "user://customize_tour_capture_settings.json"
const SKINS := "user://customize_tour_capture_skins.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const SIZE := Vector2i(1280, 720)

var gs: QuizGameState
var focus := {}
var _saved := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "skin_path": PlayerSkinStore.path, "p1_hat": gs.p1_hat,
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	GameManager.practice_intro_seen = true
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.tuning.wall_speed_override = 0.0
	gs.num_players = 1
	gs.p1_hat = HatData.HAT_CAP
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""

	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.has_method(&"practice_customize") \
			and scene.is_node_ready() and not SceneTransition.is_transitioning(), 25000)
	if not ready:
		push_error("CUSTOMIZE_TOUR_CAPTURE: the main menu did not open")
		_finish()
		return
	# のこぎり（操縦席）とメニューの入場が済むまで
	await _seconds(4.0)
	var menu := get_tree().current_scene as Control

	# メニュー：モード選択（『10問チャレンジ』）と、設定の画面（『カスタマイズ』）
	await _shot("menu_mode")
	_record("menu_mode", [menu.call(&"practice_coach_target", &"mode_ten")])
	_record("menu_settings_button", [menu.call(&"practice_coach_target", &"settings")])
	menu.call(&"practice_menu_show_config")
	await _seconds(1.2)
	await _shot("menu_config")
	_record("menu_config", [menu.call(&"practice_coach_target", &"customize")])

	# カスタマイズ
	menu.call(&"practice_open_customize")
	await _wait(func() -> bool: return bool(menu.call(&"practice_customize_ready")), 6000)
	await _seconds(1.5)
	var customize := menu.call(&"practice_customize") as Control
	for tab: Array in [[&"tab_skin", "customize_skin_hat", [&"skin_players", &"skin_hat"]],
			[&"tab_emote", "customize_emote", [&"emote_slots", &"emote_grid"]],
			[&"tab_wall", "customize_wall_speed", [&"wall_mode", &"wall_slider", &"wall_reset"]]]:
		var button := customize.call(&"practice_coach_target", tab[0]) as BaseButton
		if button != null:
			button.pressed.emit()
		await _seconds(1.6)
		await _shot(tab[1])
		var targets: Array = []
		for id: StringName in tab[2]:
			targets.append(customize.call(&"practice_coach_target", id))
			_record("%s.%s" % [tab[1], id], [customize.call(&"practice_coach_target", id)])
		_record(tab[1], targets)
		_record("%s.done" % tab[1], [customize.call(&"practice_coach_target", &"done")])

	# 設定パネル
	menu.call(&"practice_close_customize")
	await _wait(func() -> bool: return bool(menu.call(&"practice_menu_idle")), 6000)
	await _seconds(1.0)
	menu.call(&"practice_menu_show_mode")
	await _seconds(1.0)
	menu.call(&"practice_open_settings")
	await _seconds(1.2)
	await _shot("menu_settings")
	for id: StringName in [&"set_bgm", &"set_sfx", &"set_resolution", &"set_fps", &"set_quality", &"set_connection", &"set_back"]:
		_record("menu_settings.%s" % id, [menu.call(&"practice_coach_target", id)])
	_record("menu_settings", [menu.call(&"practice_coach_target", &"set_bgm"), menu.call(&"practice_coach_target", &"set_sfx"),
		menu.call(&"practice_coach_target", &"set_resolution"), menu.call(&"practice_coach_target", &"set_fps"),
		menu.call(&"practice_coach_target", &"set_quality")])
	menu.call(&"practice_close_settings")
	await _seconds(0.6)

	var file := FileAccess.open(ProjectSettings.globalize_path(OUT + "focus.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(focus, "  "))
	file.close()
	print("CUSTOMIZE_TOUR_CAPTURE " + JSON.stringify({"done": true, "shots": focus.size()}))
	_finish()


## 部品の場所を、画面に対する割合で書く（いくつかなら全部を囲む四角）
func _record(label: String, targets: Array) -> void:
	var view := get_viewport().get_visible_rect().size
	var box := Rect2()
	var any := false
	for target: Variant in targets:
		var control := target as Control
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		box = rect if not any else box.merge(rect)
		any = true
	if not any:
		focus[label] = null
		return
	focus[label] = [snappedf(box.position.x / view.x, 0.001), snappedf(box.position.y / view.y, 0.001),
		snappedf(box.size.x / view.x, 0.001), snappedf(box.size.y / view.y, 0.001)]


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	image.save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _finish() -> void:
	GameManager.settings_path = str(_saved.path)
	PlayerSkinStore.path = str(_saved.skin_path)
	PlayerSkinStore.load_into(gs)
	gs.p1_hat = int(_saved.p1_hat)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	get_tree().quit()
