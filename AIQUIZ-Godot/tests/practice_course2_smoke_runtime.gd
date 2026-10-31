extends Node

## コース②（本番の流れ）の実機の通しテスト（docs/new_tutorial/phase5_design.md 6.2）。
## メニューのコース選択から②を始め、2-1 から 2-5 の『メニュー』まで、キー入力とクリックで通す。
##   2-1：的から遠い所で跳んでも・的の真下で立ったままでも数えない → 6秒スペースなしの声かけ → 的の真下で跳んでタッチ
##   2-2：6秒なにも押さないときの声かけ → 2 でエモート1つ
##   2-3：8秒 Esc なしの声かけ → Esc でポーズ画面 → コーチ（光っていない所は押せない・説明は Enter で早送り）→『ゲームに戻る』
##   2-4：開始の画面 → Enter → 空撮 → カウントダウン → 海に落ちて負け → GAME OVER のカード → コーチの『リトライ』
##        （光っていない『メニュー』は押せない）→ もう一度、3問とも正解でクリア（★）
##   2-5：CLEAR のカードの上で、評価 → 問題履歴 →『◀ 戻る』→『メニュー』→ メインメニュー（PracticeSession.resume_in_menu）
## メニューのコーチ（担当 D の PracticeMenuGuide）ができていれば、2-6 からクリアの［あとで］まで続ける。
## 設定の保存先はテスト用に差し替え、教科などの設定はテストの後で元に戻す。撮った画面は artifacts/practice_course2/。
## 本編側（担当 A）・舞台の小物（担当 C）・コーチとメニュー（担当 D）の道具がまだないときは、その確かめを飛ばして notes に書く。

const OUT := "res://artifacts/practice_course2/"
const SETTINGS := "user://practice_course2_smoke_settings.json"
const GAME_WORLD := "res://scenes/game_world.tscn"
const MAIN_MENU := "res://ui/main_menu.tscn"
const COACH_PATH := "res://scripts/practice/ui/practice_coach.gd"
const PORTRAIT_PATH := "res://scripts/world/practice/hatena_portrait.gd"
const MENU_GUIDE_PATH := "res://scripts/practice/menu/practice_menu_guide.gd"

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 監督が言った言葉の ID（順に）
var said: Array[String] = []
var _director: PracticeDirector = null
var _history_before := 0


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "subject": GameManager.selected_subject,
		"grade": GameManager.selected_grade, "difficulty": GameManager.selected_difficulty,
		"two": GameManager.is_2p_mode, "endless": GameManager.is_endless_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	_history_before = MatchHistory.load_records().size()
	_note_tools()

	if await _launch():
		var director := await _enter_game()
		if director != null:
			_watch(director)
			await _jump(director)
			await _emote(director)
			await _pause(director)
			await _run(director)
			if await _result(director):
				await _menu_continue()
	_finish()


## A・C・D の道具がそろっているか（ないものは notes に書く）
func _note_tools() -> void:
	for path: String in [COACH_PATH, PORTRAIT_PATH, MENU_GUIDE_PATH]:
		if not ResourceLoader.exists(path):
			notes.append("missing script %s" % path)
	var rules := MatchRules.new()
	for property: String in ["finish_with_clear", "real_result_screens"]:
		if not (property in rules):
			notes.append("MatchRules has no %s" % property)
	var hatena := HatenaGuide.new()
	for method: String in ["set_dancing"]:
		if not hatena.has_method(method):
			notes.append("HatenaGuide has no %s" % method)
	hatena.free()


func _watch(director: PracticeDirector) -> void:
	if _director == director:
		return
	_director = director
	said.clear()
	if not director.saying().is_empty():
		said.append(director.saying())
	if not director.said.is_connected(_on_said):
		director.said.connect(_on_said)


func _on_said(text_id: String) -> void:
	said.append(text_id)


# ---------- メニューから②へ ----------

func _launch() -> bool:
	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.find_child("PracticeBtn", true, false) != null \
			and not SceneTransition.is_transitioning(), 20000)
	check(ready, "the main menu opens")
	if not ready:
		return false
	await _seconds(1.5)
	var button := get_tree().current_scene.find_child("PracticeBtn", true, false) as Button
	button.pressed.emit()
	var select := _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	check(select != null and select.is_open(), "the tutorial button opens the course select")
	if select == null:
		return false
	await _seconds(0.4)
	var card := select.card("c2")
	check(card != null and not card.disabled, "the c2 card can be chosen")
	if card == null or card.disabled:
		return false
	card.grab_focus()
	await _frames(2)
	await _shot("00_course_select")
	await _tap(KEY_ENTER)
	return true


func _enter_game() -> PracticeDirector:
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 20000)
	check(arrived, "choosing c2 opens the game world")
	if not arrived:
		return null
	var world := get_tree().current_scene
	# 最初の言葉を聞きのがさないよう、監督ができたらすぐ said をつなぐ
	await _wait(func() -> bool: return world.get("practice_director") is PracticeDirector, 15000)
	if world.get("practice_director") is PracticeDirector:
		_watch(world.get("practice_director") as PracticeDirector)
	var ready := await _wait(func() -> bool:
		var d := world.get("practice_director") as PracticeDirector
		return d != null and d.step != null and not SceneTransition.is_transitioning(), 15000)
	check(ready, "the practice director starts course 2")
	if not ready:
		return null
	var director := world.get("practice_director") as PracticeDirector
	check(PracticeSession.course_id == "c2" and director.course.id == "c2", "the director plays c2")
	check(director.overlay.course_title() == "② 本番の流れ", "the course title is shown (%s)" % director.overlay.course_title())
	check(director.overlay.dot_count() == 6, "six progress dots (%d)" % director.overlay.dot_count())
	return director


# ---------- 2-1 ジャンプ ----------

func _jump(d: PracticeDirector) -> void:
	if not _at(d, "2-1"):
		return
	var step := d.step
	check(not d.rules.input_locked and is_zero_approx(d.rules.world_speed) and d.rules.fence_enabled
		and is_equal_approx(d.rules.fence_max.y, 8.0) and not d.rules.hp_enabled, "2-1 stops the conveyor and sets the fence")
	check(absf(gs.player_x) < 0.05 and absf(gs.player_local_z) < 0.05, "2-1 places the player at x 0, z 0")
	check(await _wait_said("c2.jump.1", 4000), "Hatena says 次はジャンプ")
	check(_sign_has(d, "スペースでジャンプ"), "the sign shows スペースでジャンプ (%s)" % _sign_text(d))
	var target := get_tree().current_scene.find_child("PracticeJumpTarget", true, false) as Node3D
	check(target != null, "a target floats in front of the player")
	await _seconds(0.8)
	await _shot("01_jump_intro")
	check(await _wait_said("c2.jump.2", 4000), "Hatena says to touch the floating target")
	# 的から遠い所（z 0）で跳んでも、的の真下で立ったままでも、タッチにならない
	await _tap(KEY_SPACE)
	await _seconds(0.9)
	check(str(step.get("phase")) == "wait", "a jump far from the target does not count")
	var mark := said.size()
	check(await _wait_said("c2.jump.idle", 8000, mark), "6 s without space brings the space hint")
	var spot: Vector3 = step.call("target_point")
	await _move_z(spot.z)
	await _move_x(spot.x)
	await _seconds(0.5)
	check(str(step.get("phase")) == "wait", "standing under the target does not count")
	await _shot("02_jump_under_target")
	mark = said.size()
	await _tap(KEY_SPACE)
	var touched := await _wait(func() -> bool: return str(step.get("phase")) == "done", 1500)
	check(touched, "jumping under the target touches it")
	await _frames(4)
	await _shot("03_jump_touch")
	check(await _wait_said("c2.jump.ok", 1500, mark), "the touch brings OK")
	check(d.is_sign_done(&"space"), "the space panel is ticked")
	check(await _wait_step(d, "2-2", 5000), "2-1 hands over to 2-2")


# ---------- 2-2 エモート ----------

func _emote(d: PracticeDirector) -> void:
	if not _at(d, "2-2"):
		return
	var step := d.step
	check(await _wait_said("c2.emote.1", 3000), "Hatena explains the 1・2・3 emotes")
	check(_sign_has(d, "1・2・3でエモート"), "the sign shows 1・2・3でエモート (%s)" % _sign_text(d))
	await _seconds(1.0)
	check(absf(d.hatena.position.x - PracticeDirector.HATENA_WALL_X) < 0.4, "Hatena stands in front of the sign (%s)" % d.hatena.position)
	await _shot("08_emote_sign")
	var mark := said.size()
	check(await _wait_said("c2.emote.idle", 9000, mark), "6 s without keys brings the digit hint")
	var done := false
	for attempt in range(3):
		await _hold(KEY_2, 0.2)
		done = await _wait(func() -> bool: return str(step.get("phase")) == "done", 1500)
		if done:
			break
	check(done, "one emote finishes 2-2")
	check(await _wait_said("c2.emote.2", 3000), "the emote brings いいね")
	await _seconds(0.2)
	await _shot("10_emote_done")
	check(await _wait_said("c2.emote.3", 4000), "Hatena adds that the emotes can be customized")
	check(await _wait_step(d, "2-3", 5000), "2-2 hands over to 2-3")


# ---------- 2-3 一時停止 ----------

func _pause(d: PracticeDirector) -> void:
	if not _at(d, "2-3"):
		return
	var world := get_tree().current_scene
	check(await _wait_said("c2.pause.1", 3000), "Hatena says やすみたい ときは Esc")
	check(_sign_has(d, "Escで一時停止"), "the sign shows Escで一時停止 (%s)" % _sign_text(d))
	await _seconds(0.8)
	await _shot("11_pause_sign")
	var mark := said.size()
	check(await _wait_said("c2.pause.idle", 10000, mark), "8 s without Esc brings Esc は ひだりうえの キー")
	await _tap(KEY_ESCAPE)
	await _seconds(0.2)
	var pause_menu := world.get("pause_menu") as CanvasLayer
	check(get_tree().paused and pause_menu != null and pause_menu.visible, "Esc opens the real pause menu")
	check(await _wait_said("c2.pause.2", 2000), "the coach says とまったね！")
	var coach := d.coach
	if coach == null:
		notes.append("no PracticeCoach: the pause coach was not checked")
	await _seconds(0.6)
	await _shot("12_pause_coach")
	check(await _wait_said("c2.pause.3", 4000), "the coach says おとの おおきさも かえられる")
	await _seconds(0.5)
	if coach != null:
		var lit: Array = coach.call(&"targets")
		var bgm := d.coach_target(&"pause_bgm")
		check(bgm != null and lit.has(bgm) and bool(coach.call(&"is_clickable")), "the BGM and SFX sliders are lit and usable")
		# 光っていない「この レッスンを とばす」は押せない
		var skip := d.coach_target(&"pause_skip")
		if skip != null:
			await _click(skip)
			await _seconds(0.2)
			check(get_tree().paused and d.step != null and d.step.id == "2-3" and d.skipped_steps == 0,
				"the unlit skip button cannot be pressed")
	await _shot("13_pause_sliders")
	check(await _wait_said("c2.pause.4", 4000), "the coach says 『タイトルに戻る』は メニューへ")
	await _seconds(0.3)
	await _shot("14_pause_title")
	if coach != null:
		check(not bool(coach.call(&"is_clickable")), "タイトルに戻る is only shown")
		var title := d.coach_target(&"pause_title")
		if title != null:
			await _click(title)
			await _seconds(0.2)
			check(get_tree().current_scene == world and get_tree().paused, "the lit-but-shown title button cannot be pressed")
	# 説明だけの段階は Enter で早送り
	mark = said.size()
	var started := Time.get_ticks_msec()
	await _tap(KEY_ENTER)
	check(await _wait_said("c2.pause.5", 4000, mark), "the coach says 『ゲームに戻る』で つづきから")
	if coach != null:
		check(Time.get_ticks_msec() - started < 1200, "Enter fast-forwards the explanation (%d ms)" % (Time.get_ticks_msec() - started))
	await _seconds(0.5)
	await _shot("15_pause_resume")
	var resume := d.coach_target(&"pause_resume")
	check(resume != null, "the pause menu has ゲームに戻る")
	if resume != null:
		await _click(resume)
	var back := await _wait(func() -> bool: return not get_tree().paused, 2000)
	check(back, "ゲームに戻る closes the pause menu")
	check(await _wait_said("c2.pause.6", 2000), "Hatena says おかえり！")
	check(d.skipped_steps == 0, "2-3 is cleared, not skipped")
	await _seconds(0.3)
	await _shot("16_pause_back")
	check(await _wait_step(d, "2-4", 5000), "2-3 hands over to 2-4")


# ---------- 2-4 ミニ本番 ----------

func _run(d: PracticeDirector) -> void:
	if not _at(d, "2-4"):
		return
	check(await _wait_said("c2.run.1", 3000), "Hatena says さいごに ミニ ほんばん！")
	check(d.rules.hp_enabled and d.rules.mistakes == MatchRules.Mistakes.NORMAL and d.rules.ocean == MatchRules.Ocean.NORMAL
		and not d.rules.record_results and d.rules.show_score and d.rules.world_speed < 0.0 and not d.rules.fence_enabled,
		"2-4 plays by the real rules and does not record")
	if &"finish_with_clear" in d.rules:
		check(bool(d.rules.get(&"finish_with_clear")) and bool(d.rules.get(&"real_result_screens")),
			"2-4 asks for the real CLEAR and result screens")
	check(gs.game_state == Constants.STATE_WAITING_START, "2-4 starts at the start screen (%s)" % gs.game_state)
	check(gs.target_count == 3 and gs.is_boss_index(2) and gs.num_choices_for_index(2) == 4, "three walls, the third is a 4-door boss")
	check(gs.current_quiz != null and gs.current_quiz.q == "9 × 6 = ?", "the first wall is 9 × 6 = ?")
	check(await _wait_said("c2.run.2", 9000), "when the walls are down Hatena says ほんばんは Enter で スタート")
	check(not d.hatena.visible and d.bubble_unanchored, "on the start screen the bubble is shown at the top")
	await _seconds(0.5)
	await _shot("17_run_start_screen")
	if not await _start_run(d):
		return
	# 負け：海に落ちる → 本番の GAME OVER → カード →「ざんねん！」→ コーチの『リトライ』
	var mark := said.size()
	var fell := await _hold_until(KEY_LEFT, func() -> bool: return gs.p1_fall_committed or gs.p1_waiting_for_shark, 5000)
	check(fell, "running off the side drops the player into the sea")
	var over := await _wait(func() -> bool: return gs.game_state == Constants.STATE_GAME_OVER, 10000)
	check(over, "the fall ends the mini run (GAME OVER)")
	if d.has_result_screens():
		var card := await _wait(func() -> bool: return d.result_card_visible(), 15000)
		check(card, "the real GAME OVER card is shown")
		await _seconds(0.3)
		check(not d.overlay.header_visible(), "the course header hides on the result card")
		await _shot("20_run_lost_card")
	check(await _wait_said("c2.run.fail", 15000, mark), "losing brings ざんねん！")
	check(await _wait_said("c2.run.retry", 4000, mark), "Hatena says 『リトライ』で もういちど")
	await _seconds(0.5)
	await _shot("21_run_retry_coach")
	if d.coach != null and d.has_result_screens():
		var retry := d.coach_target(&"result_retry")
		var menu := d.coach_target(&"result_menu")
		var lit: Array = d.coach.call(&"targets")
		check(retry != null and lit.size() == 1 and lit[0] == retry, "only リトライ is lit")
		if menu != null:
			await _click(menu)
			await _seconds(0.4)
			check(get_tree().current_scene.scene_file_path == GAME_WORLD and d.step != null and d.step.id == "2-4",
				"the unlit メニュー cannot be pressed")
		if retry != null:
			await _click(retry)
	var restarted := await _wait(func() -> bool:
		return gs.game_state == Constants.STATE_WAITING_START and d.step_failures == 1, 15000)
	check(restarted, "リトライ goes back to the start screen")
	check(gs.get_player_hp(1) == 3 and gs.p1_alive and gs.current_wall_index == 0, "the retry gives three hearts and the first wall")
	await _seconds(0.4)
	check(not d.result_card_visible(), "the result card is gone after リトライ")
	await _shot("22_run_retry_start")
	mark = said.size()
	check(await _wait_said("c2.run.2", 9000, mark), "the retry says ほんばんは Enter で スタート again")
	if not await _start_run(d):
		return
	# 壁1「9 × 6 = ?」赤「54」・壁2「1年は何日？」青「365日」・壁3（ボス）オレンジ「富士山」
	var doors := [d.door_x(1, 2), d.door_x(0, 2), d.door_x(2, 4)]
	for i in range(doors.size()):
		await _move_x(float(doors[i]))
		var index := i
		mark = said.size()
		var passed := await _hold_until(KEY_UP, func() -> bool:
			return gs.current_wall_index > index or gs.game_state != Constants.STATE_PLAYING, 15000)
		check(passed, "wall %d is passed" % (i + 1))
		if i == 0:
			check(await _wait_said("c2.run.streak1", 1500, mark), "the first right answer brings 1もん！")
			check(await _wait_said("c2.run.hud", 2500, mark), "Hatena points at the score: せいかいの かずと なんもんめか")
			await _seconds(0.4)
			await _shot("23_run_hud")
		elif i == 1:
			check(await _wait_said("c2.run.streak2", 1500, mark), "two in a row bring 2れんぞく！")
			check(await _wait_said("c2.run.boss", 4000, mark), "the boss wall brings さいごは ボス！")
			await _seconds(0.2)
			await _shot("24_run_boss")
		else:
			check(await _wait_said("c2.run.streak3", 1500, mark), "three in a row bring 3れんぞく！ すごい！")
	var cleared := await _wait(func() -> bool: return gs.game_state == Constants.STATE_CLEAR, 8000)
	check(cleared, "passing the boss wall ends with the real CLEAR")
	await _seconds(1.2)
	await _shot("25_run_clear")
	check(gs.get_player_hp(1) == 3 and d.star_earned, "no heart was lost, so the star is earned")
	check(await _wait_step(d, "2-5", 6000), "2-4 hands over to 2-5")


## 開始の画面で Enter → 空撮 → カウントダウン（「5から かぞえるよ」）→ PLAYING。
func _start_run(d: PracticeDirector) -> bool:
	var mark := said.size()
	await _tap(KEY_ENTER)
	var flyover := await _wait(func() -> bool: return gs.game_state == Constants.STATE_FLYOVER, 4000)
	check(flyover, "Enter starts the flyover")
	if not flyover:
		return false
	await _seconds(1.6)
	if d.step_failures == 0:
		await _shot("18_run_flyover")
	var count := await _wait(func() -> bool: return gs.game_state == Constants.STATE_COUNTDOWN, 5000)
	check(count, "the flyover ends with the countdown")
	check(await _wait_said("c2.run.3", 1500, mark), "Hatena says 5から かぞえるよ")
	check(d.hatena.visible and _on_screen(d.hatena.bubble_anchor(d.camera())), "Hatena comes out for the countdown")
	await _seconds(1.0)
	if d.step_failures == 0:
		await _shot("19_run_countdown")
	var playing := await _wait(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 7000)
	check(playing, "the countdown ends with PLAYING")
	return playing


# ---------- 2-5 リザルトを みよう ----------

func _result(d: PracticeDirector) -> bool:
	if not _at(d, "2-5"):
		return false
	var card := await _wait(func() -> bool: return d.result_card_visible(), 12000)
	check(card, "the CLEAR card is shown")
	check(await _wait_said("c2.result.1", 4000), "the coach says クリア おめでとう！")
	await _seconds(0.5)
	await _shot("26_result_card")
	check(await _wait_said("c2.result.2", 4000), "the coach says これが せいかいの かず")
	await _seconds(0.5)
	await _shot("27_result_score")
	check(await _wait_said("c2.result.3", 4000), "the coach says せいかいりつ・れんぞく・じかん")
	await _seconds(0.5)
	await _shot("28_result_stats")
	if d.coach_target(&"result_explain") != null:
		check(await _wait_said("c2.result.4", 4000), "the coach says さいごの もんだいの かいせつ")
		await _seconds(0.5)
		await _shot("29_result_explain")
	else:
		notes.append("the CLEAR card has no explanation (the practice quizzes have none); c2.result.4 is skipped")
	check(await _wait_said("c2.result.5", 5000), "the coach says この もんだい よかった？")
	check(not _said_line("c2.result.4") or d.coach_target(&"result_explain") != null, "the explanation line only comes with an explanation")
	await _seconds(0.5)
	await _shot("30_result_rate")
	var rate := d.coach_target(&"result_rate")
	var good := _first_button(rate)
	check(good != null, "the rate buttons are there")
	var mark := said.size()
	if good != null:
		await _click(good)
	check(await _wait_said("c2.result.6", 3000, mark), "rating brings ありがとう！")
	await _seconds(0.3)
	await _shot("31_result_rated")
	check(await _wait_said("c2.result.8", 8000, mark), "the coach says ぜんぶの もんだいは ここ")
	await _seconds(0.4)
	await _shot("32_result_history_button")
	var history := d.coach_target(&"result_history")
	mark = said.size()
	if history != null:
		await _click(history)
	check(await _wait_said("c2.result.9", 3000, mark), "opening the history brings かいせつも よめるよ")
	await _seconds(0.6)
	await _shot("33_history_open")
	check(await _wait_said("c2.result.10", 4000, mark), "the coach says みたら『◀ 戻る』を おしてね")
	var back := d.coach_target(&"history_back")
	mark = said.size()
	if back != null:
		await _click(back)
	check(await _wait_said("c2.result.11", 3000, mark), "going back brings 『リトライ』で もういちど あそべる")
	await _seconds(0.4)
	await _shot("34_result_retry_shown")
	check(await _wait_said("c2.result.12", 5000, mark), "the coach says メニューへ いこう！")
	await _seconds(0.5)
	await _shot("35_result_menu")
	var menu := d.coach_target(&"result_menu")
	check(menu != null, "the result card has メニュー")
	if menu == null:
		return false
	await _click(menu)
	var resume := PracticeSession.resume_in_menu.duplicate()
	check(str(resume.get("course", "")) == "c2" and str(resume.get("step", "")) == "2-6" and bool(resume.get("star", false))
		and int(resume.get("skipped", -1)) == 0 and not bool(resume.get("first_run", true)),
		"メニュー hands 2-6 to the menu (%s)" % [resume])
	var returned := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU, 20000)
	check(returned, "メニュー goes to the main menu")
	check(gs.mode != Constants.MODE_PRACTICE and gs.practice_rules == null, "the menu is back to the normal mode")
	check(MatchHistory.load_records().size() == _history_before, "the practice runs are not in the match history")
	check(not GameManager.has_practice_stamp("c2"), "no stamp yet (the menu gives it after 2-6)")
	return returned


# ---------- メニューの上の 2-6 とクリア（担当 D） ----------

func _menu_continue() -> void:
	if not ResourceLoader.exists(MENU_GUIDE_PATH):
		notes.append("no PracticeMenuGuide: 2-6 and the clear were not run")
		return
	var menu := get_tree().current_scene
	var started := await _wait(func() -> bool: return menu.find_child("PracticeMenuGuide", true, false) != null, 15000)
	check(started, "the menu starts the 2-6 guide")
	check(PracticeSession.resume_in_menu.is_empty(), "the menu consumes resume_in_menu")
	if not started:
		return
	var guide := menu.find_child("PracticeMenuGuide", true, false)
	var coach := guide.get("coach") as Node
	await _seconds(2.0)
	await _shot("36_menu_guide")
	# モード選択：「『10問チャレンジ』を おして みて」→ 押す
	var ask_mode := await _wait(func() -> bool: return _bubble(coach) == PracticeTexts.get_text("c2.menu.7"), 40000)
	check(ask_mode, "2-6 asks to press 10問チャレンジ")
	await _seconds(0.4)
	await _shot("37_menu_mode_ten")
	await _click(menu.call("practice_coach_target", &"mode_ten") as Control)
	check(await _wait(func() -> bool: return str(guide.get("phase")) == "config", 6000), "10問チャレンジ opens the config screen")
	# 設定：「◀ ▶ で きょうかを かえて みて」→ ▶ を押す
	var ask_subject := await _wait(func() -> bool: return _bubble(coach) == PracticeTexts.get_text("c2.menu.9"), 15000)
	check(ask_subject, "2-6 asks to change the subject")
	await _seconds(0.4)
	await _shot("38_menu_subject")
	var subject := gs.subject
	var carousel := menu.call("practice_coach_target", &"subject") as Control
	var arrows: Array[Node] = []
	if carousel != null:
		arrows = carousel.find_children("*", "BaseButton", true, false)
	if not arrows.is_empty():
		await _click(arrows[arrows.size() - 1] as Control)
	check(await _wait(func() -> bool: return gs.subject != subject, 3000), "the right arrow changes the subject (%s -> %s)" % [subject, gs.subject])
	# クリア：カードとスタンプ（★）→［あとで］
	var card := await _wait(func() -> bool: return str(guide.get("phase")) == "card", 45000)
	check(card, "2-6 ends with the clear card")
	if not card:
		return
	check(GameManager.has_practice_stamp("c2") and GameManager.practice_stamp_star("c2"), "c2 gets the stamp with the star")
	await _wait(func() -> bool: return _bubble(coach) == PracticeTexts.get_text("c2.clear.2"), 5000)
	await _seconds(0.5)
	await _shot("39_menu_clear_card")
	var overlay := guide.get("overlay") as PracticeOverlay
	var buttons: Array[Button] = []
	if overlay != null:
		buttons = overlay.clear_buttons()
	check(buttons.size() == 2 and buttons[0].text == "本番を始める" and buttons[1].text == "あとで", "the clear card has both buttons")
	if buttons.size() < 2:
		return
	check(get_viewport().gui_get_focus_owner() == buttons[1], "あとで is selected (not from the first run)")
	await _click(buttons[1])
	# 案内は終わると消えるので、弱い参照で見る（消えたノードを lambda に入れておくと「Lambda capture … was freed」が出る）
	var guide_ref: WeakRef = weakref(guide)
	guide = null
	var done := await _wait(func() -> bool:
		var live := guide_ref.get_ref() as Node
		return live == null or str(live.get("phase")) == "done", 8000)
	check(done, "あとで ends the menu lesson")
	check(gs.menu_step == Constants.MENU_STEP_CONFIG, "あとで stays on the config screen")
	await _seconds(1.0)
	await _shot("40_menu_later")


func _bubble(coach: Node) -> String:
	return str(coach.call(&"bubble_text")) if coach != null and is_instance_valid(coach) else ""


# ---------- 道具 ----------

func _at(d: PracticeDirector, id: String) -> bool:
	var ok := d.step != null and d.step.id == id
	check(ok, "the course is at %s (%s)" % [id, d.step.id if d.step != null else "-"])
	return ok


func _wait_step(d: PracticeDirector, id: String, timeout_ms: int) -> bool:
	return await _wait(func() -> bool: return d.step != null and d.step.id == id, timeout_ms)


func _said_line(text_id: String, since := 0) -> bool:
	return said.slice(maxi(since, 0)).has(text_id)


func _wait_said(text_id: String, timeout_ms: int, since := 0) -> bool:
	return await _wait(func() -> bool: return _said_line(text_id, since), timeout_ms)


## 看板の文字（看板の壁の Label3D を集める。看板の壁がないときはオーバーレイの代わりの看板）。
func _sign_text(d: PracticeDirector) -> String:
	if d.sign_wall == null:
		return d.overlay.sign_text().replace("\n", "／")
	var parts: Array[String] = []
	for node: Node in d.sign_wall.find_children("*", "Label3D", true, false):
		parts.append((node as Label3D).text)
	return "／".join(parts).replace("\n", "／")


func _sign_has(d: PracticeDirector, text: String) -> bool:
	return _sign_text(d).replace("／", " ").contains(text)


func _on_screen(point: Vector2) -> bool:
	return point.is_finite() and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(point)


func _first_button(node: Control) -> Button:
	if node == null:
		return null
	if node is Button:
		return node as Button
	for child: Node in node.find_children("*", "Button", true, false):
		if (child as Button).is_visible_in_tree():
			return child as Button
	return null


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _menu_node(node_name: String) -> Node:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != MAIN_MENU:
		return null
	return scene.find_child(node_name, true, false)


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(3)
	_key(keycode, false)
	await _frames(3)


func _hold(keycode: Key, seconds: float) -> void:
	_key(keycode, true)
	await _seconds(seconds)
	_key(keycode, false)
	await _frames(3)


func _hold_until(keycode: Key, condition: Callable, timeout_ms: int) -> bool:
	_key(keycode, true)
	var ok := await _wait(condition, timeout_ms)
	_key(keycode, false)
	await _frames(3)
	return ok


## 左右のキーで、プレイヤーの x を target へ（x は +が画面の左＝←）。
func _move_x(target: float, timeout_ms := 3000) -> void:
	if absf(gs.player_x - target) < 0.12:
		return
	var left := target > gs.player_x
	await _hold_until(KEY_LEFT if left else KEY_RIGHT, func() -> bool:
		return gs.player_x >= target - 0.06 if left else gs.player_x <= target + 0.06, timeout_ms)


## 前後のキーで、プレイヤーのコンベア上の z を target へ。
func _move_z(target: float, timeout_ms := 3000) -> void:
	if absf(gs.player_local_z - target) < 0.15:
		return
	var forward := target > gs.player_local_z
	await _hold_until(KEY_UP if forward else KEY_DOWN, func() -> bool:
		return gs.player_local_z >= target - 0.08 if forward else gs.player_local_z <= target + 0.08, timeout_ms)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


## 部品の真ん中を、本物のマウスの動きと左クリックで押す（コーチの押せない仕組みも通る）。
func _click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var center := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point := get_viewport().get_final_transform() * center
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
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	GameManager.selected_subject = str(_saved.subject)
	GameManager.selected_grade = str(_saved.grade)
	GameManager.selected_difficulty = str(_saved.difficulty)
	GameManager.is_2p_mode = bool(_saved.two)
	GameManager.is_endless_mode = bool(_saved.endless)
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said}
	print("PRACTICE_COURSE2_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
