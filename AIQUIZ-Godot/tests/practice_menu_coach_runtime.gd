extends Node

## メニューの上のレッスン（コース②の 2-6「メニューの えらびかた」とクリア）の実機の通しテスト
## （docs/new_tutorial/phase5_design.md 5.3、course2_script.md の 2-6・クリア）。
##   1回目：PracticeSession.resume_in_menu を入れてメニューを開く → 操縦席のハテナが雲で出てくる → モード選択（光っている所だけ
##          押せる。マウスとキー）→『10問チャレンジ』→ 設定（教科を変える → 学年 … ゲーム開始）→ クリアカードとスタンプ →［あとで］
##          （設定の画面に残り、ハテナは席へ戻る）
##   2回目：PracticeSession.launch_next でメニューからコース①がすぐ始まる → ポーズ画面の「タイトルに戻る」でメニューへ
##   3回目：初回の案内から来た形（first_run）で、Esc で 2-6 をスキップ → クリアカード（［本番を始める］が選ばれている）
##          → Enter で本物の『ゲーム開始』と同じ流れ → ゲーム画面へ移る
##   Godot --path . --script tests/practice_menu_coach_bootstrap.gd
## 設定の保存先はテスト用に差し替え、教科などの設定はテストの後で元に戻す。撮った画面は artifacts/practice_menu/。

const OUT := "res://artifacts/practice_menu/"
const SETTINGS := "user://practice_menu_coach_settings.json"
const MAIN_MENU := "res://ui/main_menu.tscn"
const GAME_WORLD := "res://scenes/game_world.tscn"

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var said: Array[String] = []
var phases: Array[StringName] = []
var _saved := {}
var _finished_with := []
var _said_at: Array[int] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "subject": gs.subject, "grade": gs.grade,
		"difficulty": gs.difficulty, "players": gs.num_players, "mode": gs.mode,
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	# 本物の流れ（①②を遊んでからメニューへ来る）と同じく、メニューの最初の演出は見たことにする
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.subject = "算数"
	gs.grade = 1
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN

	var guide := await _open_menu({"course": "c2", "step": "2-6", "star": true, "skipped": 1, "first_run": false})
	if guide != null:
		await _arrive(guide)
		if await _mode_select(guide):
			await _config(guide)
			await _clear_later(guide)
	await _launch_next()
	guide = await _open_menu({"course": "c2", "step": "2-6", "star": false, "skipped": 0, "first_run": true})
	if guide != null:
		await _skip_and_start(guide)
	_finish()


# ---------- 1回目：2-6 → クリア →［あとで］ ----------

func _open_menu(resume: Dictionary) -> PracticeMenuGuide:
	PracticeSession.resume_in_menu = resume
	said.clear()
	phases.clear()
	get_tree().change_scene_to_file(MAIN_MENU)
	var started := await _wait(func() -> bool: return _guide() != null, 15000)
	check(started, "the menu starts the menu lesson from resume_in_menu")
	check(PracticeSession.resume_in_menu.is_empty(), "the menu consumes resume_in_menu")
	var guide := _guide()
	if guide == null:
		return null
	guide.coach.said.connect(func(text: String) -> void:
		said.append(text)
		_said_at.append(Time.get_ticks_msec()))
	guide.phase_changed.connect(func(phase: StringName) -> void: phases.append(phase))
	guide.finished.connect(func(started_game: bool) -> void: _finished_with.append(started_game))
	check(guide.star == bool(resume.star) and guide.first_run == bool(resume.first_run), "the guide reads star and first_run")
	check(guide.overlay.course_title() == PracticeTexts.get_text("c2.title") and guide.overlay.dot_count() == 6 and guide.overlay.progress_index() == 5,
		"the course header shows ② with 2-6 as the current dot")
	return guide


func _arrive(guide: PracticeMenuGuide) -> void:
	var saw := _saw()
	check(saw != null, "the menu has the saw carriage")
	# 席を離れる前は、操縦席にハテナがいる
	var hatena := guide.hatena
	check(hatena != null, "the guide puts a Hatena in the menu background")
	if hatena == null or saw == null:
		return
	var left := await _wait(func() -> bool: return saw.is_operator_hidden() and hatena.visible, 8000)
	check(left, "the guide Hatena takes the seat Hatena's place (seat hidden, guide shown)")
	# 立ち上がって、呼んだ雲に跳び乗り、メニューの右側へ飛んでくる（PracticeSeatMoves.saw_leave。約 4 秒）
	await _seconds(1.6)
	await _shot("01_leave_seat")
	var mode := await _wait(func() -> bool: return guide.phase == &"mode", 12000)
	check(mode, "after the flight the mode lesson starts")
	check(hatena.has_cloud(), "the Hatena rides a cloud")
	var anchor := _hatena_screen(guide)
	check(anchor.x > 760.0 and anchor.x < 1280.0 and anchor.y > 0.0 and anchor.y < 720.0,
		"the Hatena floats on the right side, off the menu UI (%s)" % anchor)
	# 何も光っていない間は、どこも押せない
	await _click(_target(&"mode_ten"))
	await _click(_target(&"mode_practice"))
	await _frames(5)
	check(gs.menu_step == Constants.MENU_STEP_MODE, "the menu is blocked while Hatena talks")
	var select := _menu().find_child("PracticeCourseSelect", true, false) as PracticeCourseSelect
	check(select != null and not select.is_open(), "the tutorial button is blocked too")


func _mode_select(guide: PracticeMenuGuide) -> bool:
	check(await _wait_said("c2.menu.1", 4000), "Hatena says ここが メニュー！")
	await _seconds(0.3)
	await _shot("02_mode_hello")
	var ten := _target(&"mode_ten") as Button
	check(await _wait_said("c2.menu.2", 6000), "Hatena explains 10問チャレンジ")
	check(_lit(guide) == [ten] and not guide.coach.is_clickable(), "10問チャレンジ is lit (show only)")
	await _seconds(0.4)
	await _shot("03_mode_ten")
	await _click(ten)
	check(gs.menu_step == Constants.MENU_STEP_MODE, "a show-only light cannot be pressed")
	check(await _wait_said("c2.menu.3", 5000), "Hatena says さいごは ボスかべ")
	check(await _wait_said("c2.menu.4", 6000), "Hatena explains エンドレス")
	check(_lit(guide) == [_target(&"mode_endless")], "エンドレス is lit")
	await _seconds(0.4)
	await _shot("04_mode_endless")
	# Enter で早送り（説明だけの段階）
	await _tap(KEY_ENTER)
	check(await _wait_said("c2.menu.5", 800), "Enter fast-forwards an explanation line")
	check(await _wait_said("c2.menu.6", 6000), "Hatena explains オンライン対戦")
	var online := _target(&"mode_online")
	check(_lit(guide) == [online], "オンライン対戦 is lit")
	await _seconds(0.4)
	await _shot("05_mode_online")
	await _click(online)
	await _frames(10)
	check(not bool(_menu().get("_menu_exit_in_progress")) and get_tree().current_scene.scene_file_path == MAIN_MENU,
		"the lit online button is show-only (no scene change)")
	check(await _wait_said("c2.menu.7", 6000), "Hatena asks to press 10問チャレンジ")
	check(_lit(guide) == [ten] and guide.coach.is_clickable(), "10問チャレンジ is lit and pressable")
	await _frames(3)
	check(get_viewport().gui_get_focus_owner() == ten, "10問チャレンジ gets the keyboard focus")
	await _seconds(0.5)
	check(guide.coach.bubble_text() == PracticeTexts.get_text("c2.menu.7"), "the ask stays until pressed")
	await _shot("06_mode_press_ten")
	await _click(_target(&"mode_endless"))
	check(gs.menu_step == Constants.MENU_STEP_MODE and gs.mode != Constants.MODE_ENDLESS, "エンドレス cannot be pressed")
	await _tap(KEY_RIGHT)
	check(get_viewport().gui_get_focus_owner() == ten, "the arrow keys keep the focus on the lit button")
	await _tap(KEY_ENTER)
	var config := await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 2000)
	check(config and gs.mode == Constants.MODE_TEN, "Enter presses 10問チャレンジ and the real settings open")
	return config


func _config(guide: PracticeMenuGuide) -> void:
	check(await _wait_said("c2.menu.8", 4000), "Hatena says ここで じゅんびを するよ")
	await _seconds(0.4)
	await _shot("07_config_hello")
	check(await _wait_said("c2.menu.9", 6000), "Hatena asks to change the subject")
	var subject := _target(&"subject")
	check(_lit(guide) == [subject] and guide.coach.is_clickable(), "the subject row is lit and pressable")
	await _frames(3)
	var focus := get_viewport().gui_get_focus_owner()
	check(focus != null and subject.is_ancestor_of(focus), "the subject arrow gets the focus (%s)" % focus)
	await _seconds(0.4)
	await _shot("08_config_subject")
	var before := gs.subject
	await _click(_target(&"start"))
	await _click(_target(&"back"))
	await _frames(5)
	check(gs.menu_step == Constants.MENU_STEP_CONFIG and not bool(_menu().get("_menu_exit_in_progress")),
		"ゲーム開始 and 戻る are blocked while the subject is lit")
	await _click(_menu().get_node("%NextSubjectBtn") as Control)
	check(await _wait(func() -> bool: return gs.subject != before, 1500), "the lit ▶ changes the subject (%s → %s)" % [before, gs.subject])
	check(await _wait_said("c2.menu.10", 3000), "a subject change brings いいね！ つぎは がくねん")
	check(_lit(guide) == [_target(&"grade")], "the grade row is lit")
	await _seconds(0.4)
	await _shot("09_config_grade")
	for entry: Array in [["c2.menu.11", &"difficulty"], ["c2.menu.12", &"llm"], ["c2.menu.13", &"players"],
			["c2.menu.14", &"customize"], ["c2.menu.15", &"start"]]:
		check(await _wait_said(entry[0], 6000), "Hatena says %s" % entry[0])
		check(_lit(guide) == [_target(entry[1])] and not guide.coach.is_clickable(),
			"%s is lit (show only)" % entry[1])
		if entry[1] == &"llm":
			await _seconds(0.4)
			await _shot("10_config_llm")
	await _seconds(0.4)
	await _shot("11_config_start")
	await _click(_target(&"start"))
	check(not bool(_menu().get("_menu_exit_in_progress")), "the lit ゲーム開始 is show-only during 2-6")


func _clear_later(guide: PracticeMenuGuide) -> void:
	check(await _wait_said("c2.clear.1", 6000), "Hatena says これで じゅんび ばっちり！")
	check(guide.phase == &"clear" and gs.menu_step == Constants.MENU_STEP_CONFIG, "the clear plays on the settings screen")
	await _seconds(0.7)
	await _shot("12_clear_hatena")
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 4000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	check(GameManager.has_practice_stamp("c2") and GameManager.practice_stamp_star("c2"), "c2 gets a stamp with the star")
	var saved: Variant = _saved_settings().get("practice_stamps", {})
	check(saved is Dictionary and (saved as Dictionary).has("c2"), "the c2 stamp is saved (%s)" % [saved])
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 2 and buttons[0].text == "本番を始める" and buttons[1].text == "あとで",
		"the card has 本番を始める / あとで")
	var labels := _label_texts(guide.overlay)
	check(labels.has("② 本番の流れ") and labels.has("クリア"), "the card reads ② 本番の流れ / クリア")
	check(await _wait_said("c2.clear.2", 4000), "Hatena says the last clear line")
	await _seconds(0.5)
	if buttons.size() == 2:
		check(get_viewport().gui_get_focus_owner() == buttons[1], "あとで is selected when not from the first run")
	await _shot("13_clear_card")
	var saw := _saw()
	if buttons.size() == 2:
		await _click(buttons[1])
	var done := await _wait(func() -> bool: return _guide() == null, 9000)
	check(done, "あとで ends the menu lesson")
	check(_finished_with == [false], "the lesson finishes without starting the game")
	check(gs.menu_step == Constants.MENU_STEP_CONFIG and get_tree().current_scene.scene_file_path == MAIN_MENU,
		"あとで stays on the settings screen")
	check(saw != null and not saw.is_operator_hidden(), "Hatena is back on the seat")
	await _seconds(0.4)
	await _shot("14_after_later")
	# コーチが終わったら、メニューは今までどおり押せる
	await _click(_target(&"back"))
	check(await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_MODE, 1500), "the menu works again (戻る)")


# ---------- 2回目：launch_next ----------

func _launch_next() -> void:
	PracticeSession.launch_next = "c1"
	get_tree().change_scene_to_file(MAIN_MENU)
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 20000)
	check(arrived, "launch_next starts that course right from the menu")
	check(PracticeSession.launch_next.is_empty(), "the menu consumes launch_next")
	if not arrived:
		return
	check(PracticeSession.course_id == "c1" and gs.mode == Constants.MODE_PRACTICE, "the launched course is c1 in the practice mode")
	var world := get_tree().current_scene
	var ready := await _wait(func() -> bool:
		var d := world.get("practice_director") as PracticeDirector
		return d != null and d.step != null and not SceneTransition.is_transitioning(), 15000)
	check(ready, "the launched course runs")
	if not ready:
		return
	await _shot("15_launch_next")
	(world.get("practice_director") as PracticeDirector).quit_course()
	var back := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 20000)
	check(back, "quitting the course comes back to the menu")
	await _seconds(0.8)
	check(_guide() == null, "a plain return to the menu starts no menu lesson")


# ---------- 3回目：Esc で 2-6 をスキップ →［本番を始める］ ----------

func _skip_and_start(guide: PracticeMenuGuide) -> void:
	await _wait(func() -> bool: return guide.phase == &"mode" and not guide.coach.bubble_text().is_empty(), 10000)
	await _tap(KEY_ESCAPE)
	var cleared := await _wait(func() -> bool: return guide.phase == &"clear", 2000)
	check(cleared and guide.skipped == 1, "Esc skips 2-6 and goes to the clear (skipped %d)" % guide.skipped)
	check(await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 1500),
		"skipping from the mode screen opens the settings screen for the clear")
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 5000)
	check(shown, "the clear card is shown after skipping")
	if not shown:
		return
	check(GameManager.practice_stamp_star("c2"), "the star stays once earned")
	var buttons := guide.overlay.clear_buttons()
	await _seconds(0.6)
	if buttons.size() == 2:
		check(get_viewport().gui_get_focus_owner() == buttons[0], "本番を始める is selected after the first-run start")
	await _wait_said("c2.clear.2", 4000)
	await _seconds(0.3)
	await _shot("16_card_first_run")
	var saw := _saw()
	await _tap(KEY_ENTER)
	# ハテナが雲で席の横へ飛び、座面へ跳び降りて座ってから（約 3.5 秒）、本番を始める
	var leaving := await _wait(func() -> bool: return _guide() == null, 9000)
	check(leaving, "本番を始める ends the menu lesson")
	check(saw != null and is_instance_valid(saw) and not saw.is_operator_hidden(), "Hatena is back on the seat before the start")
	check(_finished_with.size() == 2 and _finished_with[1] == true, "the lesson reports the started game")
	check(bool(_menu().get("_menu_exit_in_progress")) if _menu() != null else true, "the real start departure begins")
	await _seconds(0.5)
	await _shot("17_start_departure")
	await _seconds(1.5)
	await _tap(KEY_SPACE)  # ヘリの出発を飛ばす（本番と同じ）
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 30000)
	check(arrived, "the real game starts from the clear card")
	if arrived:
		check(gs.mode == Constants.MODE_TEN and gs.practice_rules == null, "the real game is the 10-question mode, not practice")
		await _seconds(2.0)
		await _shot("18_game_started")


# ---------- 道具 ----------

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _menu() -> Node:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != MAIN_MENU:
		return null
	return scene


func _guide() -> PracticeMenuGuide:
	var menu := _menu()
	return menu.call("practice_menu_guide") as PracticeMenuGuide if menu != null else null


func _target(id: StringName) -> Control:
	var menu := _menu()
	return menu.call("practice_coach_target", id) as Control if menu != null else null


func _saw() -> SawChaseController:
	var menu := _menu()
	return menu.call("practice_menu_saw") as SawChaseController if menu != null else null


func _lit(guide: PracticeMenuGuide) -> Array:
	return Array(guide.coach.targets())


func _hatena_screen(guide: PracticeMenuGuide) -> Vector2:
	var camera := _menu().call("practice_menu_camera") as Camera3D
	var head := guide.hatena.bubble_anchor(camera)
	return _menu().call("practice_menu_to_screen", head) if head.is_finite() else head


func _said(text_id: String) -> bool:
	return said.has(text_id)


func _wait_said(text_id: String, timeout_ms: int) -> bool:
	var ok := await _wait(func() -> bool: return said.has(text_id), timeout_ms)
	if not ok:
		var guide := _guide()
		var ticket: Variant = guide.coach.get("_say") if guide != null else null
		notes.append("waiting %s: said %s at %s (now %d), bubble \"%s\", phase %s, ticket %s" % [text_id, said, _said_at,
			Time.get_ticks_msec(), guide.coach.bubble_text() if guide != null else "-", guide.phase if guide != null else "-",
			[ticket.get("remaining"), ticket.get("finished"), ticket.get("hold")] if ticket != null else "none"])
		if guide != null:
			notes.append("coach can_process %s inside %s paused %s fps %.1f" % [guide.coach.can_process(),
				guide.coach.is_inside_tree(), get_tree().paused, Engine.get_frames_per_second()])
	return ok


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _saved_settings() -> Dictionary:
	var path := ProjectSettings.globalize_path(SETTINGS)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _to_window(point: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * point


## 部品の真ん中を、本物のマウスのようにクリックする。
func _click(control: Control) -> void:
	if control == null:
		check(false, "click target exists")
		return
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(point)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = _to_window(point)
		button.global_position = button.position
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(button)
		await _frames(2)
	await _frames(2)


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(3)
	_key(keycode, false)
	await _frames(3)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	gs.subject = str(_saved.subject)
	gs.grade = int(_saved.grade)
	gs.difficulty = str(_saved.difficulty)
	gs.num_players = int(_saved.players)
	gs.mode = str(_saved.mode)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	PracticeSession.return_to_select = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said}
	print("PRACTICE_MENU_COACH " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
