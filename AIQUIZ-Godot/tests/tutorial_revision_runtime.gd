extends Node

## チュートリアル（V7）のメニュー側の受け入れ確認。実際のメインメニューで次を確かめる。
## - コース選択とキー配置を1画面にまとめた開始画面（1P・2Pの切り替え）。
## - カスタマイズ紹介（画像3枚・戻る／次へ・← → Space Enter Esc）と、ボタンの見た目。
## - 紹介を終えたときの小さな完了通知（以前の大きな完了カードは出さない）。
## 設定ファイルはテスト用に差し替え、本物の保存ファイルには書かない（最後にハッシュで確認）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_revision_bootstrap.gd --fixed-fps 60
const OUT := "res://artifacts/tutorial_v7/menu/"

var checks: Array[Dictionary] = []
var failures: Array[String] = []
var _menu: Node = null


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var settings_hash := FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH)
	var skins_hash := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH)
	GameManager.settings_path = "user://tutorial_revision_test_settings.json"
	PlayerSkinStore.path = "user://tutorial_revision_test_skins.json"
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var ready := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.name == "MainMenu" and scene.get("_embedded_customize") != null, 40.0)
	_check(ready, "main menu is ready")
	if not ready:
		_finish(settings_hash, skins_hash)
		return
	_menu = get_tree().current_scene
	await _wait(2.5)
	var gs: QuizGameState = QuizManager.game_state

	# ---- 開始画面（コース選択とキー配置） ----
	var selector: Node = _menu.get("_tutorial_selector")
	selector.call("show_selector")
	await _wait(0.5)
	var evidence: Dictionary = selector.call("get_evidence")
	_check(bool(evidence.active) and evidence.legend.size() == 3, "course select explains the 1P keys on the same screen")
	_check(_menu.get("_tutorial_keyboard_intro") == null, "the separate keyboard screen is gone")
	await _capture("course_select_solo")
	selector.call("_select_course", "LOCAL_2P")
	await _wait(0.3)
	_check((selector.call("get_evidence") as Dictionary).legend.size() == 6, "choosing 2P shows both players' keys")
	await _capture("course_select_duo")
	selector.call("hide_selector")
	await _wait(0.3)

	# ---- カスタマイズ紹介 ----
	_menu.call("_open_embedded_customize")
	await _wait(1.2)
	var host: Node = _menu.get("_embedded_customize")
	host.call("begin_tutorial_tour")
	await _wait(0.4)
	_check(bool(host.get("_tutorial_tour_active")), "customize tour opens")
	var titles := ["壁の速さ", "帽子", "エモート"]
	var images := ["customize_wall_speed.png", "customize_skin_hat.png", "customize_emote.png"]
	for i: int in 3:
		var title: Label = host.get("_tutorial_tour_title")
		var image: TextureRect = host.get("_tutorial_tour_image")
		var next_button: Button = host.get("_tutorial_tour_next_button")
		_check(title.text == titles[i], "page %d title (%s)" % [i, title.text])
		_check(image.texture.resource_path.ends_with(images[i]), "page %d keeps its screenshot" % i)
		var normal := next_button.get_theme_stylebox("normal") as StyleBoxFlat
		_check(normal != null and normal.bg_color.is_equal_approx(TutorialUiStyle.ACCENT), "page %d next button keeps the tutorial style" % i)
		await _capture("customize_%d" % i)
		if i < 2:
			await _tap(KEY_RIGHT)
	_check((host.get("_tutorial_tour_key_legend") as Control).visible, "emote page shows the P1/P2 keys")
	await _tap(KEY_LEFT)
	_check(int(host.get("_tutorial_tour_index")) == 1, "left key returns to the previous page")
	await _tap(KEY_SPACE)
	_check(int(host.get("_tutorial_tour_index")) == 2, "space advances")
	await _tap(KEY_ENTER)
	_check(not bool(host.get("_tutorial_tour_active")), "Enter on the last page finishes the tour")
	await _tap(KEY_ESCAPE)
	await _wait(0.8)

	# ---- チュートリアルから来たときの完了通知 ----
	gs.set("_pending_solo_customize_tour", true)
	gs.set("_pending_customize_tour_course", GameManager.TUTORIAL_COURSE_SOLO)
	_menu.call("_begin_pending_customize_tutorial")
	await _wait(1.2)
	_check(bool(host.get("_tutorial_tour_active")), "the pending tour opens from the menu")
	for i: int in 3:
		await _tap(KEY_ENTER)
	var notice_shown := await _wait_until(func() -> bool: return _menu.get_node_or_null("TutorialCompleteNotice") != null, 4.0)
	_check(notice_shown, "finishing the tour shows the small completion notice")
	_check(not gs.has_pending_solo_customize_tour(), "the course is saved as completed")
	_check(_menu.get_node_or_null("SoloTutorialCompletionCard") == null, "the old full-screen completion card is not shown")
	await _wait(0.3)
	await _capture("completion_notice")
	var notice_gone := await _wait_until(func() -> bool: return _menu.get_node_or_null("TutorialCompleteNotice") == null, 6.0)
	_check(notice_gone, "the notice disappears by itself")
	_finish(settings_hash, skins_hash)


func _finish(settings_hash: String, skins_hash: String) -> void:
	PlayerSkinStore.flush()
	_check(FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) == settings_hash, "player settings file untouched")
	_check(FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) == skins_hash, "player skins file untouched")
	var report := {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}
	var file := FileAccess.open(OUT + "runtime_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t"))
		file.close()
	print("TUTORIAL_MENU_RUNTIME " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


func _tap(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(0.08)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _wait(0.2)


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return bool(condition.call())


func _check(ok: bool, label: String) -> void:
	checks.append({"passed": ok, "name": label})
	if not ok:
		failures.append(label)
		push_error("TUTORIAL_MENU " + label)
