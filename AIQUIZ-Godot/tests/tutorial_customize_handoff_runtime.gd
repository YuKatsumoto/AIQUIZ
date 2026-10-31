extends "res://tests/practice_course5_smoke_runtime.gd"

## 旧チュートリアル（1P 実践コース）の終わりからカスタマイズ紹介への引き継ぎの通しテスト。
## カスタマイズ紹介は新しいチュートリアルのコース⑤（PracticeCustomizeGuide）をそのまま使う（main_menu._begin_pending_customize_tutorial）。
##   実践コースのクリアと同じ「カスタマイズ紹介待ち」の状態でメニューへ戻る → メニューの上でハテナの案内が始まる
##   → 5-1〜5-6（tests/practice_course5_smoke_runtime.gd の1回目と同じ操作）→ クリアカード →［メニューに戻る］
##   → 旧版の完了カード（2 / 2 TUTORIAL COMPLETE）→ 1P コースが完了になって保存される → メニューがふつうに使える
## 撮った画面は artifacts/tutorial_customize_handoff/。
##   Godot --path . --script tests/tutorial_customize_handoff_bootstrap.gd

const HANDOFF_OUT := "res://artifacts/tutorial_customize_handoff/"


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HANDOFF_OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "skin_path": PlayerSkinStore.path, "subject": gs.subject, "grade": gs.grade,
		"difficulty": gs.difficulty, "players": gs.num_players, "mode": gs.mode, "wall": gs.tuning.wall_speed_override,
		"p1_emotes": gs.p1_emote_slots.duplicate(), "p2_emotes": gs.p2_emote_slots.duplicate(),
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	# 新版のスタンプが5つそろっていても、旧版のあとでは「スタンプが全部そろったね！」を言わない
	GameManager.practice_stamps = {"c1": {"star": false}, "c2": {"star": false}, "c3": {"star": false}, "c4": {"star": false}}
	GameManager.reset_tutorial_prompt()
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.tuning.wall_speed_override = 0.0

	var guide := await _launch()
	if guide != null:
		await _arrive(guide)
		if await _go(guide):
			await _hat(guide)
			await _emote(guide)
			await _speed(guide)
			await _done(guide)
			await _settings(guide)
			await _clear_to_completion(guide)
	_finish_handoff()


## 1P 実践コースを終えた所（_begin_solo_customize_handoff と同じ状態）からメニューへ戻る。
func _launch() -> PracticeCustomizeGuide:
	gs.start_tutorial(GameManager.TUTORIAL_COURSE_SOLO)
	gs._pending_solo_customize_tour = true
	gs._pending_customize_tour_course = GameManager.TUTORIAL_COURSE_SOLO
	gs.reset_to_menu()
	check(gs.has_pending_solo_customize_tour(), "the solo course left the customize tour pending")
	check(gs.mode != Constants.MODE_TUTORIAL, "back on the menu the mode is the one before the tutorial")
	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 25000)
	check(opened, "the main menu opens")
	if not opened:
		return null
	var menu := _menu()
	var tutorial_button := menu.find_child("TutorialMainBtn", true, false) as Button
	check(tutorial_button != null and tutorial_button.text == "チュートリアル", "the menu has the old tutorial button")
	check(menu.find_child("PracticeBtn", true, false) == null, "the practice course button is gone")
	var started := await _wait(func() -> bool: return _guide() != null, 5000)
	check(started, "the pending customize tour starts the Hatena customize guide on the menu")
	var guide := _guide()
	if guide == null:
		return null
	check(gs.has_pending_solo_customize_tour(), "the course stays pending while the guide runs")
	said.clear()
	phases.clear()
	guide.coach.said.connect(func(text: String) -> void: said.append(text))
	guide.phase_changed.connect(func(phase: StringName) -> void: phases.append(phase))
	check(guide.overlay.course_title() == "⑤ カスタマイズ" and guide.overlay.dot_count() == 6, "the header shows ⑤ with 6 dots")
	return guide


## クリアカード →［メニューに戻る］→ 旧版の完了カード → 1P コースが完了になる。
func _clear_to_completion(guide: PracticeCustomizeGuide) -> void:
	check(await _wait_said("c5.clear.1", 6000), "クリア 自分だけのスタイル")
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 5000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	check(gs.has_pending_solo_customize_tour(), "the course is not marked done before the old completion card")
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 1 and buttons[0].text == "メニューに戻る", "the card has メニューに戻る")
	check(await _wait_said("c5.clear.2", 6000), "クリア 楽しんでね")
	check(not said.has("c5.clear.all"), "after the old tutorial the guide does not count the other courses' stamps")
	await _seconds(0.5)
	await _shot("22_clear_card")
	if buttons.size() == 1:
		await _click(buttons[0])
	check(await _wait(func() -> bool: return _guide() == null, 9000), "メニューに戻る ends the guide")
	var card_shown := await _wait(func() -> bool: return _menu().find_child("SoloTutorialCompletionCard", true, false) != null, 3000)
	check(card_shown, "the old completion card follows the guide")
	await _seconds(1.2)
	await _shot("23_completion_card")
	var completed := await _wait(func() -> bool: return not gs.has_pending_solo_customize_tour(), 8000)
	check(completed, "the completion card finishes the tour")
	check(GameManager.is_tutorial_course_completed(GameManager.TUTORIAL_COURSE_SOLO), "the 1P course is marked completed")
	check(not GameManager.is_tutorial_course_completed(GameManager.TUTORIAL_COURSE_LOCAL_2P), "the 2P course is still to do")
	check(bool(_read_json(SETTINGS).get("tutorial_solo_completed", false)), "the 1P completion is saved")
	check(await _wait(func() -> bool: return _menu().find_child("SoloTutorialCompletionCard", true, false) == null, 4000),
		"the completion card goes away")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "the menu is back on the mode select")
	await _seconds(0.6)
	await _shot("24_after_completion")
	await _click(_target(&"mode_ten"))
	check(await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 2000), "the real menu works again")
	_menu().call("practice_menu_show_mode")
	await _seconds(0.6)


func _shot(label: String) -> void:
	await _frames(2)
	var path := HANDOFF_OUT + label + ".png"
	get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _finish_handoff() -> void:
	for keycode: Variant in _held.keys():
		if _held[keycode]:
			_key(keycode, false)
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said, "phases": phases}
	print("TUTORIAL_CUSTOMIZE_HANDOFF " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
