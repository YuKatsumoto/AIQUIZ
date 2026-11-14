extends "res://tests/practice_course5_smoke_runtime.gd"

## 旧チュートリアル（1P 実践コース）の終わりからカスタマイズ紹介への引き継ぎの通しテスト。
## カスタマイズ紹介は新しいチュートリアルのコース⑤（PracticeCustomizeGuide。画像カード）をそのまま使う
## （main_menu._begin_pending_customize_tutorial）。
##   実践コースのクリアと同じ「カスタマイズ紹介待ち」の状態でメニューへ戻る → メニューの上に画像カードが出る
##   → 5ページ（tests/practice_course5_smoke_runtime.gd の1回目と同じ操作）→ クリアカード →［メニューに戻る］
##   → 旧版の完了カード（2 / 2 TUTORIAL COMPLETE）→ 1P コースが完了になって保存される → メニューがふつうに使える
## 撮った画面は artifacts/tutorial_customize_handoff/。
##   Godot --path . --script tests/tutorial_customize_handoff_bootstrap.gd

const HANDOFF_OUT := "res://artifacts/tutorial_customize_handoff/"


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HANDOFF_OUT))
	_save_state()
	# 新版のスタンプが5つそろっていても、旧版のあとでは「スタンプが全部そろったね！」を言わない
	GameManager.practice_stamps = {"c1": {"star": false}, "c2": {"star": false}, "c3": {"star": false}, "c4": {"star": false}}
	GameManager.reset_tutorial_prompt()

	var guide := await _launch()
	if guide != null:
		await _pages(guide)
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
	var started := await _wait(func() -> bool: return _guide() != null, 8000)
	check(started, "the pending customize tour starts the image cards on the menu")
	var guide := _guide()
	if guide == null:
		return null
	check(gs.has_pending_solo_customize_tour(), "the course stays pending while the guide runs")
	check(guide.from_tutorial, "the guide knows it follows the old tutorial")
	check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "the mouse is shown for the image cards")
	_watch(guide)
	return guide


## クリアカード →［メニューに戻る］→ 旧版の完了カード → 1P コースが完了になる。
func _clear_to_completion(guide: PracticeCustomizeGuide) -> void:
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 5000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	check(gs.has_pending_solo_customize_tour(), "the course is not marked done before the old completion card")
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 1 and buttons[0].text == "メニューに戻る", "the card has メニューに戻る")
	await _seconds(1.5)
	check(guide.overlay.bubble_text().is_empty(), "after the old tutorial the guide does not count the other courses' stamps")
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
	_restore_state()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "phases": phases}
	print("TUTORIAL_CUSTOMIZE_HANDOFF " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
