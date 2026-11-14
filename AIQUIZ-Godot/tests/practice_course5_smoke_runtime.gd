extends Node

## コース⑤（カスタマイズの紹介。画像カード）の実機の通しテスト（course5_script.md v0.3）。
##   1回目：メニューの上で⑤を始める（画面は移らない）→ 画像カード（カスタマイズの開き方 → 帽子 → エモート → 壁の速さ → 設定）を
##          ［次へ →］と → キーでめくる（← と［← 戻る］で戻れる）→［紹介を終える］→ クリアカードとスタンプ →［メニューに戻る］
##   2回目：スタンプが4つある形で、2ページ目で Esc（残りをとばす）→ クリアで「スタンプが全部そろったね！」→ Esc で［メニューに戻る］
## 紹介の間は下のメニューが押せないこと（クリックもキーも）、設定（壁の速さ・帽子）を何も変えないことも確かめる。
## 設定（スタンプ）とスキンの保存先はテスト用に差し替え、テストの後で元に戻す。撮った画面は artifacts/practice_course5/。

const OUT := "res://artifacts/practice_course5/"
const SETTINGS := "user://practice_course5_smoke_settings.json"
const SKINS := "user://practice_course5_smoke_skins.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const PAGE_IDS: Array[StringName] = [&"menu", &"hat", &"emote", &"speed", &"set"]

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 案内の進み具合（順に）
var phases: Array[StringName] = []
## （吹き出しの文字。テストの報告用）
var said: Array[String] = []
var _held := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save_state()
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	gs.num_players = 1
	var guide := await _launch()
	if guide != null:
		await _pages(guide)
		await _clear_back(guide)
	await _skip_run()
	_finish()


# ---------- 1回目：ページを全部めくる ----------

func _launch() -> PracticeCustomizeGuide:
	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.has_method(&"practice_customize") \
			and not SceneTransition.is_transitioning(), 25000)
	check(ready, "the main menu opens")
	if not ready:
		return null
	await _seconds(2.0)
	var menu := _menu()
	PracticeSession.launch(menu, "c5")
	var started := await _wait(func() -> bool: return _guide() != null, 3000)
	check(started, "launching c5 starts the customize guide")
	check(get_tree().current_scene == menu and not SceneTransition.is_transitioning(), "c5 stays on the main menu (no scene change)")
	check(gs.mode != Constants.MODE_PRACTICE, "c5 does not switch the game to the practice mode")
	var guide := _guide()
	if guide == null:
		return null
	_watch(guide)
	return guide


func _watch(guide: PracticeCustomizeGuide) -> void:
	phases.clear()
	guide.phase_changed.connect(func(phase: StringName) -> void: phases.append(phase))
	check(guide.overlay.course_title() == "⑤ カスタマイズ" and guide.overlay.dot_count() == PAGE_IDS.size(),
		"the course has ⑤ with %d dots" % PAGE_IDS.size())
	check(not guide.overlay.header_visible(), "the top header is hidden while the image cards show their own progress")


func _pages(guide: PracticeCustomizeGuide) -> void:
	var tour := guide.tour
	check(tour != null and tour.visible, "the image tour is shown")
	if tour == null:
		return
	var wall_before := gs.tuning.wall_speed_override
	var hat_before := gs.p1_hat
	await _frames(3)
	check(tour.index == 0 and tour.page_id() == &"menu", "the tour opens on the menu page")
	check(tour.pages.size() == PAGE_IDS.size(), "five pages (%d)" % tour.pages.size())
	for i in range(tour.pages.size()):
		var page: Dictionary = tour.pages[i]
		check(StringName(page.id) == PAGE_IDS[i], "page %d is %s" % [i, PAGE_IDS[i]])
		check(page.image is Texture2D and (page.image as Texture2D).get_size() == Vector2(1280, 720), "page %s has its 1280x720 image" % PAGE_IDS[i])
		check(not str(page.title).begins_with("[") and not str(page.body).is_empty(), "page %s has its text" % PAGE_IDS[i])
		var focus: Rect2 = page.focus
		check(focus.size.x > 0.0 and focus.end.x <= 1.0 and focus.end.y <= 1.0, "page %s frames a part of the image" % PAGE_IDS[i])
	await _seconds(0.4)
	await _shot("01_page_menu")
	var back := tour.find_child("PreviousPage", true, false) as Button
	var next := tour.find_child("NextPage", true, false) as Button
	check(back != null and back.disabled, "← 戻る is off on the first page")
	check(next != null and next.text == "次へ →", "the first page says 次へ →")
	# 紹介の間は、下のメニューを押せない（クリックも、キーも）
	var ten := _target(&"mode_ten")
	if ten != null and ten.is_visible_in_tree():
		await _click(ten)
		check(gs.menu_step == Constants.MENU_STEP_MODE, "a click on the menu under the tour does nothing")
	await _tap(KEY_DOWN)
	check(gs.menu_step == Constants.MENU_STEP_MODE and _guide() == guide, "keys do not reach the menu under the tour")
	# ［次へ →］（クリック）→ 2ページ目、← キーで戻る、→ キーで進む
	await _click(next)
	check(tour.index == 1 and guide.phase == &"hat", "次へ → shows the hat page")
	await _tap(KEY_LEFT)
	check(tour.index == 0 and guide.phase == &"menu", "← goes back to the menu page")
	await _tap(KEY_RIGHT)
	check(tour.index == 1, "→ goes to the hat page")
	await _seconds(0.3)
	await _shot("02_page_hat")
	await _click(back)
	check(tour.index == 0, "← 戻る goes back")
	for i in range(1, PAGE_IDS.size()):
		await _tap(KEY_RIGHT)
		check(tour.index == i and guide.phase == PAGE_IDS[i], "→ shows the %s page" % PAGE_IDS[i])
		await _seconds(0.3)
		await _shot("%02d_page_%s" % [i + 1, PAGE_IDS[i]])
	check(next.text == "紹介を終える", "the last page says 紹介を終える")
	check(guide.overlay.progress_index() == PAGE_IDS.size() - 1, "the dots follow the pages")
	# 最後のページは Enter（フォーカスは［紹介を終える］）で終える
	await _tap(KEY_ENTER)
	check(await _wait(func() -> bool: return guide.phase == &"card" or guide.phase == &"done", 3000), "紹介を終える goes to the clear")
	check(not tour.visible, "the image tour closes")
	check(guide.skipped == 0, "nothing skipped (%d)" % guide.skipped)
	check(gs.tuning.wall_speed_override == wall_before and gs.p1_hat == hat_before, "the tour changes no settings")


func _clear_back(guide: PracticeCustomizeGuide) -> void:
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 3000)
	check(shown, "the clear card is shown")
	check(GameManager.has_practice_stamp("c5"), "the c5 stamp is set")
	check(bool(_read_json(SETTINGS).get("practice_stamps", {}).has("c5")), "the c5 stamp is saved")
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 1 and buttons[0].text == "メニューに戻る", "the card has メニューに戻る")
	await _seconds(1.0)
	check(guide.overlay.bubble_text().is_empty(), "with one stamp there is no all-stamps line")
	await _shot("07_clear_card")
	if buttons.size() == 1:
		await _click(buttons[0])
	check(await _wait(func() -> bool: return _guide() == null, 4000), "メニューに戻る ends the guide")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "back on the mode select")
	check(phases.has(&"leaving") and phases[-1] == &"done", "the guide ends with leaving → done (%s)" % [phases])
	await _seconds(0.5)
	await _click(_target(&"mode_ten"))
	check(await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 2000), "the real menu works again")
	_menu().call("practice_menu_show_mode")
	await _seconds(0.8)


# ---------- 2回目：Esc で とばす ----------

func _skip_run() -> void:
	for id: String in ["c1", "c2", "c3", "c4"]:
		GameManager.practice_stamps[id] = {"star": false}
	GameManager.practice_stamps.erase("c5")
	var menu := _menu()
	if menu == null:
		check(false, "the menu is still there for the second run")
		return
	PracticeSession.launch(menu, "c5")
	var started := await _wait(func() -> bool: return _guide() != null, 3000)
	check(started, "PracticeSession.launch starts c5 again")
	if not started:
		return
	var guide := _guide()
	_watch(guide)
	await _frames(3)
	await _tap(KEY_RIGHT)
	check(guide.tour.index == 1, "skip run: on the hat page")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 3000), "Esc skips the rest to the clear card")
	check(guide.skipped == 3, "three pages skipped (%d)" % guide.skipped)
	check(guide.all_stamps(), "all five stamps are set")
	check(await _wait(func() -> bool: return guide.overlay.bubble_text() == "スタンプが全部そろったね！", 3000),
		"all five stamps: スタンプが全部そろったね")
	await _seconds(0.3)
	await _shot("08_all_stamps")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return _guide() == null, 4000), "Esc on the card is メニューに戻る")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "skip run: back on the mode select")


# ---------- 道具 ----------

func _save_state() -> void:
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "skin_path": PlayerSkinStore.path, "subject": gs.subject, "grade": gs.grade,
		"difficulty": gs.difficulty, "players": gs.num_players, "mode": gs.mode, "wall": gs.tuning.wall_speed_override,
		"p1_emotes": gs.p1_emote_slots.duplicate(), "p2_emotes": gs.p2_emote_slots.duplicate(),
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	# スキンの保存先も差し替える（いまの見た目のまま、書くのはテスト用のファイル）
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.tuning.wall_speed_override = 0.0
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""


func _restore_state() -> void:
	for keycode: Variant in _held.keys():
		if _held[keycode]:
			_key(keycode, false)
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	# スキンは保存先を戻して、ファイルの見た目を読み直す
	PlayerSkinStore.path = str(_saved.skin_path)
	PlayerSkinStore.load_into(gs)
	gs.subject = str(_saved.subject)
	gs.grade = int(_saved.grade)
	gs.difficulty = str(_saved.difficulty)
	gs.num_players = int(_saved.players)
	gs.mode = str(_saved.mode)
	gs.tuning.wall_speed_override = float(_saved.wall)
	gs.p1_emote_slots.assign(_saved.p1_emotes)
	gs.p2_emote_slots.assign(_saved.p2_emotes)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _menu() -> Control:
	var scene := get_tree().current_scene
	return scene as Control if scene != null and scene.scene_file_path == MAIN_MENU else null


func _guide() -> PracticeCustomizeGuide:
	var menu := _menu()
	return menu.call("practice_customize_guide") as PracticeCustomizeGuide if menu != null else null


func _target(id: StringName) -> Control:
	return _menu().call("practice_coach_target", id) as Control


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _read_json(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed if parsed is Dictionary else {}


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(3)
	_key(keycode, false)
	await _frames(3)


func _key(keycode: Key, pressed: bool) -> void:
	_held[keycode] = pressed
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


## 部品の真ん中を、本物のマウスの動きと左クリックで押す。
func _click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		check(false, "click target exists")
		return
	var point := get_viewport().get_final_transform() * _center(control)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.position = point
		button.global_position = point
		Input.parse_input_event(button)
		await _frames(2)
	await _frames(2)


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	_restore_state()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "phases": phases}
	print("PRACTICE_COURSE5_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
