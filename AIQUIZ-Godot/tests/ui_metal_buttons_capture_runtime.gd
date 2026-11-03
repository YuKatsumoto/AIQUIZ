extends Node

## tests/ui_metal_buttons_capture_bootstrap.gd の本体。メニュー → 設定パネル → カスタマイズ（壁速度・スキン・エモート）
## → ポーズ相当の画面を順に撮り、画面に出ている Button のうち MenuMetalButton でないものを数えて書き出す。

const OUT := "res://artifacts/ui_metal_buttons/"
const MAIN_MENU := "res://ui/main_menu.tscn"
const SETTINGS := "user://ui_metal_buttons_capture_settings.json"
const SKINS := "user://ui_metal_buttons_capture_skins.json"

var _tag := "shot"
var _plain_total := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2 and parts[0] == "tag":
			_tag = parts[1]
	run.call_deferred()


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	# 撮るだけなので、ふだんの設定ファイルとスキンには書かない
	GameManager.settings_path = SETTINGS
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)

	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 25000)
	if not opened:
		push_error("main menu did not open")
		get_tree().quit(1)
		return
	var menu := get_tree().current_scene
	await _seconds(2.5)
	await _shot("menu", menu)

	menu.call("_on_settings_btn_pressed")
	await _seconds(1.2)
	await _shot("settings", menu.get_node("SettingsPanel"))
	# ドロップダウンの一覧も同じ板になっているか
	var quality := menu.find_child("GraphicsQualityOption", true, false) as OptionButton
	quality.show_popup()
	await _seconds(0.6)
	await _shot("settings_dropdown", menu.get_node("SettingsPanel"))
	quality.get_popup().hide()
	menu.call("_on_settings_back_btn_pressed")
	await _seconds(0.8)

	menu.call("_on_customize_pressed")
	await _seconds(2.5)
	var customize := menu.get("_embedded_customize") as Control
	await _shot("customize_wall", customize)
	customize.call("_set_section", 1)
	await _seconds(1.5)
	await _shot("customize_skin", customize)
	customize.call("_set_section", 2)
	await _seconds(1.5)
	await _shot("customize_emote", customize)

	# チュートリアルのコース選択と、キーの案内（同じメニューを開き直して重ねる）
	var first_menu_id := menu.get_instance_id()
	get_tree().change_scene_to_file(MAIN_MENU)
	await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.get_instance_id() != first_menu_id and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 25000)
	menu = get_tree().current_scene
	await _seconds(2.0)
	menu.call("_ensure_tutorial_selector")
	menu.call("_show_tutorial_selector")
	await _seconds(1.2)
	await _shot("tutorial_select", menu.get_node("TutorialCourseSelector"))
	var intro := menu.get_node("TutorialKeyboardIntro")
	menu.get_node("TutorialCourseSelector").call("hide_selector")
	intro.call("show_intro", GameManager.TUTORIAL_COURSE_SOLO)
	await _seconds(1.2)
	await _shot("tutorial_keyboard", intro)
	intro.visible = false

	# ゲーム中のポーズと、ゲームオーバー・問題履歴の画面
	var gs := QuizManager.game_state
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	GameManager.start_game()
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.name == "GameWorld" and not SceneTransition.is_transitioning() and not scene.call("is_start_presentation_locked"), 60000)
	var world := get_tree().current_scene
	if arrived:
		await _seconds(1.5)
		world.call("_toggle_pause")
		await _seconds(0.6)
		await _shot("pause", world.get("pause_menu"))
		world.call("_toggle_pause")
		var hud := world.get_node("GameplayHUD")
		var panel := hud.get("game_over_panel") as Control
		panel.visible = true
		(hud.get("go_rate_box") as Control).visible = true
		await _seconds(0.5)
		await _shot("game_over", panel)
		panel.visible = false
		var history := hud.get("history_panel") as Control
		history.visible = true
		await _seconds(0.5)
		await _shot("history", history)
	else:
		push_error("game world did not arrive")
	print("UI_METAL_CAPTURE plain_buttons_total=", _plain_total)
	get_tree().paused = false
	get_tree().quit(0)


func _shot(name: String, scope: Node) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + "%s_%s.png" % [_tag, name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	var plain: PackedStringArray = []
	for button: Button in _visible_buttons(scope):
		if not (button is MenuMetalButton):
			plain.append("%s(%s)" % [button.name, button.text])
	_plain_total += plain.size()
	print("CAPTURE ", path, " plain=", plain.size(), " ", ", ".join(plain))


func _visible_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return found
	if node is Button:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_visible_buttons(child))
	return found


func _seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if condition.call():
			return true
		await get_tree().process_frame
	return false
