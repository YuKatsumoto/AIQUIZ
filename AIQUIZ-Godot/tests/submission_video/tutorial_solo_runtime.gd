extends "res://tests/submission_video/take_base.gd"

## プレイ動画 D（チュートリアル「1P 実践コース」）。
## メインメニュー →『チュートリアル』→ コース選択 → キーボードの説明 → ステージ（操作 → ジャンプ → エモート → 海 →
## 光るドア → ハート → 誘導なしの 2 問 → 4 択のボス壁）→ メニューの上のカスタマイズ紹介（画像カード）→ 完了カード、までを通す。
## 操作はボット。説明を読む間をとり、キーは 1 つずつ、少し長めに押す。
## 設定とスキンの保存先は撮影用のファイルに替える（プレイヤーの設定には書かない）。
##   python -X utf8 tests/submission_video/record_take.py tutorial_solo <出力フォルダ>

const MAIN_MENU := "res://ui/main_menu.tscn"
const GAME_WORLD := "res://scenes/game_world.tscn"

var gs: QuizGameState
var _steps: Array = []


func run() -> void:
	rng.seed = 20261112
	gs = QuizManager.game_state
	use_capture_settings("tutorial")
	# コースはどちらも「まだ」の表示にする。初回の案内（メニューが出たとたんにコース選択が開く）は出さず、
	# メニューを見せてから『チュートリアル』を押す
	GameManager.reset_tutorial_prompt()
	GameManager.tutorial_prompt_seen_version = GameManager.CURRENT_TUTORIAL_VERSION
	GameManager.tutorial_dismissed = true
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.num_players = 1

	get_tree().change_scene_to_file(MAIN_MENU)
	if not await wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 60.0):
		finish("the main menu did not open")
		return
	mark("menu")
	shot_once("menu", 1.8)
	await sleep(2.5)
	var menu := get_tree().current_scene
	var button := menu.find_child("TutorialMainBtn", true, false) as Button
	if button == null:
		finish("no tutorial button on the menu")
		return
	await click(button)
	var selector := menu.find_child("TutorialCourseSelector", true, false) as Control
	if not await wait_until(func() -> bool: return selector != null and selector.visible, 5.0):
		finish("the course selector did not open")
		return
	mark("selector")
	shot_once("tutorial_select", 1.5)
	await sleep(3.0)
	selector.emit_signal("course_selected", GameManager.TUTORIAL_COURSE_SOLO)
	var intro := menu.find_child("TutorialKeyboardIntro", true, false) as Control
	if await wait_until(func() -> bool: return intro != null and intro.visible, 5.0):
		mark("keyboard_intro")
		shot_once("tutorial_keyboard", 3.0)
		await sleep(5.0)
		intro.emit_signal("completed", GameManager.TUTORIAL_COURSE_SOLO)
	if not await wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return (scene != null and scene.scene_file_path == GAME_WORLD and gs.mode == Constants.MODE_TUTORIAL
				and gs.game_state == Constants.STATE_WAITING_START and not SceneTransition.is_transitioning()
				and not scene.is_start_presentation_locked()
				and bool(scene.get("_barrier_spawned_for_session")) and not bool(scene.get("_barrier_dropping"))), 120.0):
		finish("the tutorial did not reach its start (state %s)" % gs.game_state)
		return
	mark("waiting_start")
	await sleep(2.2)
	tap(KEY_ENTER, 0.1)
	if not await wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 30.0):
		finish("the countdown did not reach the first lesson")
		return
	await _stage()
	if not (report.failures as Array).is_empty():
		finish()
		return
	await _customize()
	finish()


# ---------- ステージ ----------

func _stage() -> void:
	# 前後左右
	if not await _step("move_lane"):
		return
	await sleep(2.4)
	await _press(KEY_A, 0.85)
	await sleep(0.45)
	await _press(KEY_D, 1.2)
	await sleep(0.4)
	await _press(KEY_A, 0.35)
	await sleep(0.5)
	await _press(KEY_W, 0.8)
	await sleep(0.4)
	await _press(KEY_S, 0.9)

	# ジャンプ
	if not await _step("jump_lesson"):
		return
	await sleep(1.8)
	tap(KEY_SPACE, 0.12)

	# エモート（3 つとも。最後はジャンプで止める）
	if not await _step("solo_emote"):
		return
	await sleep(2.0)
	for key: Key in [KEY_1, KEY_2, KEY_3]:
		if gs.get_tutorial_step_id() != "solo_emote":
			break
		tap(key, 0.25)
		await sleep(rng.randf_range(1.7, 2.2))

	# 海へ落ちてみる
	if not await _step("ocean_lesson"):
		return
	await sleep(2.6)
	var edge_key: Key = KEY_A if gs.player_x >= 0.0 else KEY_D
	hold(edge_key, true)
	await sleep(0.5)
	hold(edge_key, false)
	await sleep(0.7)  # 端の手前で、いちど止まる
	hold(edge_key, true)
	await wait_until(func() -> bool: return gs.p1_fall_committed or gs.p1_waiting_for_shark or not gs.p1_alive, 8.0)
	hold(edge_key, false)

	# 光っているドアへ
	if not await _step("guided_wall", 40.0):
		return
	await _answer("guided_wall", 2.2, false)

	# わざと不正解へ
	if not await _step("hp_lesson", 40.0):
		return
	await _answer("hp_lesson", 3.0, false)

	# 誘導なしの 2 問
	if not await _step("free_wall", 40.0):
		return
	await _answer("free_wall", 2.4, true)

	# 4 択のボス壁
	if not await _step("boss_wall", 40.0):
		return
	await _answer("boss_wall", 3.2, true)

	if not await wait_until(func() -> bool: return gs.get_tutorial_step_id() in ["stage_complete", "customize_tour"], 40.0):
		(report.failures as Array).append("the stage did not complete (step %s, hp %d)" % [gs.get_tutorial_step_id(), gs.p1_hp])
		return
	mark("stage_complete")
	report["hp_at_end"] = gs.p1_hp


func _step(id: String, timeout := 25.0) -> bool:
	var ok := await wait_until(func() -> bool:
		return gs.get_tutorial_step_id() == id and not gs.is_tutorial_presentation_locked() \
			and gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE], timeout)
	if ok:
		_steps.append(id)
		report["steps"] = _steps
		mark("step_" + id)
		shot_once("tutorial_" + id, 1.5)
	else:
		(report.failures as Array).append("did not reach step %s (now %s, state %s)" % [id, gs.get_tutorial_step_id(), gs.game_state])
	return ok


func _press(key: Key, seconds: float) -> void:
	hold(key, true)
	await sleep(seconds)
	hold(key, false)


## このステップの壁を答える。読む間をとってからドアへ向かい、ドアの前では少し立ち位置を直し、ときどき跳ぶ。
func _answer(step_id: String, read_seconds: float, hops: bool) -> void:
	var wall := -1
	var read_until := 0.0
	var offset := 0.0
	var shift_at := 0.0
	var hop_at := 0.0
	while gs.get_tutorial_step_id() == step_id:
		await get_tree().process_frame
		if gs.is_tutorial_presentation_locked() or gs.game_state != Constants.STATE_PLAYING or gs.current_quiz == null or not gs.p1_alive:
			set_lateral(0)
			continue
		var index := gs.current_wall_index
		var previous_wall_z := gs.tuning.wall_start_z + float(index - 1) * gs.tuning.wall_spacing
		if index != wall:
			if index > 0 and gs.player_z < previous_wall_z + 0.8 and wall >= 0:
				set_lateral(0)
				continue
			wall = index
			read_until = t + read_seconds + rng.randf_range(0.0, 0.8)
			offset = rng.randf_range(-0.5, 0.5)
			shift_at = read_until + rng.randf_range(2.0, 3.5)
			hop_at = read_until + rng.randf_range(2.0, 4.0)
		if t < read_until:
			set_lateral(0)
			continue
		var door: int = int(gs.tutorial_flow.target_door()) if gs.tutorial_flow != null else -1
		if door < 0:
			door = gs.current_quiz.a
		var ahead := gs.wall_z - gs.player_z
		if t > shift_at and ahead > 8.0:
			shift_at = t + rng.randf_range(1.8, 3.2)
			offset = rng.randf_range(-0.6, 0.6)
		var target_x := _door_x(door) + offset
		go_x(gs.player_x, target_x, 0.3 if ahead < 8.0 else 0.45)
		if hops and t > hop_at and ahead > 8.0 and ahead < 24.0 and absf(gs.player_x - target_x) < 0.8:
			hop_at = t + rng.randf_range(2.5, 5.0)
			tap(KEY_SPACE, 0.08)
	set_lateral(0)


func _door_x(door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[clampi(door, 0, 3)]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x


# ---------- カスタマイズ紹介（メニューの上の画像カード） ----------

func _menu() -> Control:
	var scene := get_tree().current_scene
	return scene as Control if scene != null and scene.scene_file_path == MAIN_MENU else null


func _guide() -> PracticeCustomizeGuide:
	var menu := _menu()
	return menu.call("practice_customize_guide") as PracticeCustomizeGuide if menu != null else null


func _customize() -> void:
	if not await wait_until(func() -> bool: return _guide() != null and _guide().tour != null, 60.0):
		(report.failures as Array).append("the customize guide did not start on the menu")
		return
	mark("customize")
	shot_once("tutorial_customize", 2.0)
	var guide := _guide()
	var pages: int = guide.tour.pages.size()
	report["customize_pages"] = pages
	for i in range(pages):
		await sleep(3.6 if i == 0 else 3.0)
		tap(KEY_RIGHT if i < pages - 1 else KEY_ENTER, 0.08)
		await sleep(0.3)
	if not await wait_until(func() -> bool: return is_instance_valid(guide) and guide.overlay.clear_card_visible(), 10.0):
		(report.failures as Array).append("the clear card did not show")
		return
	mark("clear_card")
	shot_once("tutorial_clear", 1.5)
	await sleep(2.5)
	var buttons: Array = guide.overlay.clear_buttons()
	if buttons.size() >= 1:
		await click(buttons[0])
	await wait_until(func() -> bool: return _guide() == null, 12.0)
	if await wait_until(func() -> bool: return _menu() != null and _menu().find_child("SoloTutorialCompletionCard", true, false) != null, 6.0):
		mark("completion_card")
		await wait_until(func() -> bool: return _menu() != null and _menu().find_child("SoloTutorialCompletionCard", true, false) == null, 15.0)
	await sleep(2.5)
	mark("end")
