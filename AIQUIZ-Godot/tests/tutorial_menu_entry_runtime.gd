extends Node

## メインメニューの『チュートリアル』から旧チュートリアルが始まるまでの通しテスト。
##   『チュートリアル』→ コース選択（1P 実践コース／ローカル2P 実践コース）→ キーボード説明 → ゲーム画面の開始待ち
##   （「1Pチュートリアル」と「Enter でチュートリアル開始」）
## 設定の保存先はテスト用に差し替え、テストの後で元に戻す。撮った画面は artifacts/tutorial_menu_entry/。
##   Godot --path . --script tests/tutorial_menu_entry_bootstrap.gd

const OUT := "res://artifacts/tutorial_menu_entry/"
const SETTINGS := "user://tutorial_menu_entry_settings.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const GAME_WORLD := "res://scenes/game_world.tscn"

var gs: QuizGameState
var failures: Array[String] = []
var checks := 0
var _saved := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "subject": gs.subject, "grade": gs.grade, "difficulty": gs.difficulty,
		"players": gs.num_players, "mode": gs.mode, "llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.reset_tutorial_prompt()
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	await _entry()
	_finish()


func _entry() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 25000)
	check(opened, "the main menu opens")
	if not opened:
		return
	await _seconds(1.2)
	var menu := get_tree().current_scene
	var button := menu.find_child("TutorialMainBtn", true, false) as Button
	check(button != null and button.text == "チュートリアル" and button.get_parent().name == "TutorialRow",
		"the old tutorial button sits in the tutorial row")
	check(menu.find_child("PracticeCourseSelect", true, false) == null, "the practice course select is not built")
	await _shot("00_menu")
	if button == null:
		return
	button.pressed.emit()
	var selector := menu.find_child("TutorialCourseSelector", true, false) as Control
	check(selector != null and selector.visible, "the tutorial button opens the old course selector")
	await _seconds(0.5)
	await _shot("01_course_selector")
	if selector == null:
		return
	selector.emit_signal("course_selected", GameManager.TUTORIAL_COURSE_SOLO)
	var intro := menu.find_child("TutorialKeyboardIntro", true, false) as Control
	check(await _wait(func() -> bool: return intro != null and intro.visible, 3000), "choosing 1P shows the keyboard intro")
	await _seconds(1.0)
	await _shot("02_keyboard_intro")
	if intro == null:
		return
	intro.emit_signal("completed", GameManager.TUTORIAL_COURSE_SOLO)
	var in_game := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD and gs.mode == Constants.MODE_TUTORIAL \
			and gs.game_state == Constants.STATE_WAITING_START and not SceneTransition.is_transitioning(), 40000)
	check(in_game, "the 1P tutorial starts in the game world")
	check(gs.get_tutorial_course() == GameManager.TUTORIAL_COURSE_SOLO and gs.num_players == 1, "the 1P course is running")
	await _seconds(2.5)
	await _shot("03_waiting_start")
	var hud := get_tree().current_scene.get_node_or_null("GameplayHUD")
	var title := hud.get_node_or_null("PreloadPanel/Title") as Label if hud != null else null
	if title == null and hud != null:
		title = hud.find_child("Title", true, false) as Label
	check(title != null and title.text == "1Pチュートリアル", "the waiting panel names the 1P tutorial (%s)" % [title.text if title != null else "?"])


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("TUTORIAL_MENU_ENTRY " + label)


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _shot(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	GameManager.settings_path = str(_saved.path)
	gs.subject = str(_saved.subject)
	gs.grade = int(_saved.grade)
	gs.difficulty = str(_saved.difficulty)
	gs.num_players = int(_saved.players)
	gs.mode = str(_saved.mode)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	print("TUTORIAL_MENU_ENTRY " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
