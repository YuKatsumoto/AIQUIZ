extends Node

## 練習（新チュートリアル）の実機の通しテスト（docs/new_tutorial/foundation_design.md 12章、phase4_design.md 4.3）。
## メニューの初回の案内 → チュートリアルのボタン → コース選択 → コース① を 1-1 からクリアまでキー入力で通す。
## 各レッスンで正解と失敗・まきもどし（やり直し）を少なくとも1回ずつ通り、1-4 では3回失敗して矢印と遅い壁を、
## 1-7 では海に落ちて負け → やり直しを確かめる。クリアカードとスタンプ（★、保存される）→ メニューのコース選択へ戻り、
## 最後に、もう一度①を始めて、ポーズ画面の「このレッスンをスキップ」と「タイトルに戻る」を確かめる。
##   Godot --path . --script tests/practice_smoke_bootstrap.gd
## 設定の保存先はテスト用に差し替える（プレイヤーの設定に書かない）。撮った画面は artifacts/practice_smoke/。
## 本編側（担当 A）・舞台の小物（担当 C）の段階4の道具がまだないときは、その確かめを飛ばして notes に書く。

const OUT := "res://artifacts/practice_smoke/"
const SETTINGS := "user://practice_smoke_settings.json"
const GAME_WORLD := "res://scenes/game_world.tscn"
const MAIN_MENU := "res://ui/main_menu.tscn"
const SIGN_WALL_PATH := "res://scripts/world/practice/sign_wall.gd"
const FLOOR_MARKS_PATH := "res://scripts/world/practice/practice_floor_marks.gd"

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 監督が言った言葉の ID（順に）
var said: Array[String] = []
var fence_touches := 0
var _director: PracticeDirector = null


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = false
	PracticeSession.return_to_select = false
	gs.practice_fence_touched.connect(func(_player: int) -> void: fence_touches += 1)
	_note_tools()

	if await _intro_prompt():
		if await _course_select():
			var director := await _enter_game()
			if director != null:
				_watch(director)
				await _welcome(director)
				await _move(director)
				await _door(director)
				await _quiz(director)
				await _hearts(director)
				await _edge(director)
				await _final(director)
				await _clear(director)
				if await _back_to_select():
					await _pause_skip_and_quit()
	_finish()


## A・C の道具がそろっているか（ないものは notes に書く）
func _note_tools() -> void:
	for path: String in [SIGN_WALL_PATH, FLOOR_MARKS_PATH]:
		if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			notes.append("missing prop script %s (fallback used)" % path)
	for method: String in ["practice_drop_current_wall", "practice_revive"]:
		if not gs.has_method(method):
			notes.append("game_state has no %s" % method)
	for sig: String in ["practice_wall_landed", "practice_round_lost"]:
		if not gs.has_signal(sig):
			notes.append("game_state has no signal %s" % sig)
	var rules := MatchRules.new()
	if not (&"slow_auto_speed" in rules):
		notes.append("MatchRules has no slow_auto_speed")


func _watch(director: PracticeDirector) -> void:
	_director = director
	said.clear()
	if not director.said.is_connected(_on_said):
		director.said.connect(_on_said)


func _on_said(text_id: String) -> void:
	said.append(text_id)


# ---------- メニュー ----------

func _intro_prompt() -> bool:
	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var prompt := _menu_node("PracticeIntroPrompt") as PracticeIntroPrompt
		return prompt != null and prompt.is_open(), 15000)
	check(opened, "the first-run prompt opens on the menu")
	if not opened:
		return false
	var prompt := _menu_node("PracticeIntroPrompt") as PracticeIntroPrompt
	var texts := _label_texts(prompt)
	check(texts.has(PracticeTexts.get_text("menu.intro")), "the prompt asks to practice (%s)" % [texts])
	check(prompt.button(0).text == "チュートリアルへ" and prompt.button(1).text == "あとで", "the prompt buttons are チュートリアルへ / あとで")
	await _seconds(0.5)
	await _shot("01_intro_prompt")
	# Esc は［あとで］：閉じて、見たことを保存する
	await _tap(KEY_ESCAPE)
	await _seconds(0.4)
	check(not prompt.is_open() and not prompt.visible, "Esc closes the prompt")
	check(GameManager.practice_intro_seen, "the prompt is marked as seen")
	check(bool(_saved_settings().get("practice_intro_seen", false)), "practice_intro_seen is saved")
	return true


func _course_select() -> bool:
	var menu := get_tree().current_scene
	var button := menu.find_child("PracticeBtn", true, false) as Button
	var online := menu.find_child("OnlineVersusBtn", true, false) as Button
	check(button != null and button.text == "チュートリアル", "the menu has the tutorial button")
	if button == null:
		return false
	check(online != null and button.get_parent() == online.get_parent() and button.get_index() == 0 and online.get_index() == 1,
		"the tutorial button sits left of the online button")
	button.pressed.emit()
	var select := _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	check(select != null and select.is_open(), "the button opens the course select")
	if select == null:
		return false
	await _seconds(0.4)
	for course: Dictionary in PracticeCatalog.COURSES:
		var card := select.card(course.id)
		check(card != null, "card %s exists" % course.id)
		if card != null:
			check(card.disabled == not bool(course.available), "card %s availability" % course.id)
	var ribbon := select.card("c1").find_child("NextRibbon", true, false) as CanvasItem
	check(ribbon != null and ribbon.visible, "c1 is the recommended course")
	check(get_viewport().gui_get_focus_owner() == select.card("c1"), "c1 has the keyboard focus")
	await _shot("02_course_select")
	# Enter で選ぶ
	await _tap(KEY_ENTER)
	return true


# ---------- ゲーム画面 ----------

func _enter_game() -> PracticeDirector:
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 20000)
	check(arrived, "choosing c1 opens the game world")
	if not arrived:
		return null
	check(gs.mode == Constants.MODE_PRACTICE, "the game runs in the practice mode")
	var world := get_tree().current_scene
	var ready := await _wait(func() -> bool:
		var d := world.get("practice_director") as PracticeDirector
		return d != null and d.step != null and not SceneTransition.is_transitioning(), 15000)
	check(ready, "the practice director starts the course")
	if not ready:
		return null
	var director := world.get("practice_director") as PracticeDirector
	check(gs.practice_rules != null, "practice rules are set")
	check(gs.game_state == Constants.STATE_PLAYING, "the practice round is playing (%s)" % gs.game_state)
	check(director.overlay.course_title() == "① 基本操作", "the course title is shown")
	check(director.overlay.dot_count() == 7, "seven progress dots (%d)" % director.overlay.dot_count())
	return director


## 1-1 ようこそ：操作はロック。看板の壁「テストピアへようこそ」、ハテナが2つ言う。Enter で吹き出しを送れる。
func _welcome(d: PracticeDirector) -> void:
	check(d.step.id == "1-1", "the course starts with 1-1")
	check(d.rules.input_locked, "1-1 locks the controls")
	check(absf(gs.player_x) < 0.01 and absf(gs.player_local_z) < 0.01, "1-1 places the player at x 0, z 0")
	var first := await _wait_said("c1.welcome.1", 6000)
	check(first, "Hatena says the first welcome line")
	check(_sign_has(d, "テストピアへようこそ"), "1-1 shows the welcome sign (%s)" % _sign_text(d))
	if d.sign_wall != null:
		check(absf(d.sign_wall.position.z - 14.0) < 0.2, "the sign wall stands 14 m ahead (%.2f)" % d.sign_wall.position.z)
	var anchor := d.hatena.bubble_anchor(d.camera())
	check(anchor.is_finite() and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(anchor),
		"Hatena is on screen (%s)" % anchor)
	check(absf(d.hatena.position.x - PracticeDirector.HATENA_WALL_X) < 0.3, "Hatena stands in front of the sign (x %.2f)" % d.hatena.position.x)
	await _seconds(0.3)
	await _shot("03_welcome")
	var x0 := gs.player_x
	await _hold(KEY_LEFT, 0.3)
	check(absf(gs.player_x - x0) < 0.01, "locked controls do not move the player")
	# 操作のロック中は Enter で次の吹き出しへ送れる
	var line := d.overlay.bubble_text()
	await _tap(KEY_ENTER)
	var advanced := await _wait(func() -> bool:
		var now := d.overlay.bubble_text()
		return not now.is_empty() and now != line, 1500)
	check(advanced, "Enter advances the bubble while locked")
	var moved_on := await _wait_step(d, "1-2", 12000)
	check(moved_on, "1-1 hands over to 1-2")


## 1-2 移動：看板の壁のパネルが ← → → ↑ ↓。さく（x ±10）で止まり、8秒なにも押さないと「矢印キーで動いてみて」。
func _move(d: PracticeDirector) -> void:
	if not _at(d, "1-2"):
		return
	check(not d.rules.input_locked, "1-2 unlocks the controls")
	check(d.rules.fence_enabled and is_equal_approx(d.rules.fence_max.y, 8.0), "1-2 sets the invisible fence with the front at z +8")
	await _wait_said("c1.move.1", 3000)
	check(_sign_has(d, "←→で左右に移動"), "1-2 shows the left/right sign (%s)" % _sign_text(d))
	await _seconds(0.4)
	await _shot("04_move_lr")
	await _hold(KEY_LEFT, 0.35)
	check(d.is_sign_done(&"left"), "moving left ticks ←")
	check(not d.is_sign_done(&"right"), "→ is still open")
	await _hold(KEY_RIGHT, 0.45)
	check(d.is_sign_done(&"right"), "moving right ticks →")
	await _seconds(0.3)
	await _shot("05_move_lr_done")
	var vertical := await _wait_said("c1.move.3", 6000)
	check(vertical, "1-2 moves on to forward/back")
	check(_sign_has(d, "↑↓で前後に移動"), "the forward/back sign is shown (%s)" % _sign_text(d))
	# 何も押さないと、8秒で「矢印キーで動いてみて」
	var idle := await _wait_said("c1.move.idle", 10000)
	check(idle, "8 s without keys brings the idle hint")
	# 見えないさく：左へ押しっぱなしでも x は +10 で止まり、さわったことが知らされる
	var touches := fence_touches
	await _hold(KEY_LEFT, 1.8)
	check(gs.player_x <= 10.05, "the fence stops the player at x = +10 (%.2f)" % gs.player_x)
	check(fence_touches > touches, "touching the fence is reported")
	await _shot("06_move_fence")
	await _hold(KEY_UP, 0.35)
	check(d.is_sign_done(&"forward"), "moving forward ticks ↑")
	await _hold(KEY_DOWN, 0.45)
	check(d.is_sign_done(&"back"), "moving back ticks ↓")
	check(gs.player_local_z >= -6.05 and gs.player_local_z <= 8.05, "the fence keeps z in -6..8 (%.2f)" % gs.player_local_z)
	check(await _wait_said("c1.move.4", 3000), "Hatena says いいね")
	check(await _wait_step(d, "1-3", 4000), "1-2 hands over to 1-3")


## 1-3 ドアをくぐる：赤のドアで失敗 → まきもどし（壁は 12m 先）→ 青のドアで突破。
func _door(d: PracticeDirector) -> void:
	if not _at(d, "1-3"):
		return
	check(_said_line("c1.door.1"), "1-3 starts with 壁が来るよ")
	var quiz := gs.current_quiz
	check(quiz != null and quiz.q == "青いドアをくぐろう" and Array(quiz.c) == ["青", "赤"] and quiz.a == 0,
		"1-3 sets the blue-door wall")
	check(d.rules.fence_max.y > 100.0, "1-3 removes the front fence")
	check(absf(d.wall_distance() - 22.0) < 0.3, "the wall comes down 22 m ahead (%.2f)" % d.wall_distance())
	await _seconds(0.3)
	await _shot("10_door_drop")
	check(await _wait(func() -> bool: return d.sign_wall == null, 3000), "the sign wall flies away")
	var moving := await _wait(func() -> bool: return d.rules.world_speed > 0.0, 5000)
	check(moving and is_equal_approx(d.rules.world_speed, 1.6), "the conveyor starts at 1.6 m/s (%.2f)" % d.rules.world_speed)
	check(await _wait_said("c1.door.2", 2000), "Hatena says to read the wall")
	check(absf(d.hatena.position.x - PracticeDirector.HATENA_WALL_X) < 0.3
		and absf(d.hatena.position.z - (d.wall_local_z() - PracticeDirector.HATENA_WALL_FRONT)) < 1.0,
		"Hatena stands in front of the wall (%s)" % d.hatena.position)
	# 失敗：赤のドアをくぐる
	await _move_x(-3.5)
	var mark := said.size()
	var red := await _hold_until(KEY_UP, func() -> bool: return _said_line("c1.door.red", mark), 6000)
	check(red, "the red door brings the red-door line")
	check(is_zero_approx(d.rules.world_speed) and d.rules.input_locked, "the conveyor stops before the words")
	await _shot("11_door_wrong")
	check(await _rewound(d, 1), "1-3 rewinds after the red door")
	check(absf(d.wall_distance() - 12.0) < 0.6, "after the rewind the wall is 12 m ahead (%.2f)" % d.wall_distance())
	# ハテナは置き直された壁の前へ跳び直す（0.8 秒）
	await _seconds(1.0)
	check(absf(d.hatena.position.x - PracticeDirector.HATENA_WALL_X) < 0.3
		and absf(d.hatena.position.z - (d.wall_local_z() - PracticeDirector.HATENA_WALL_FRONT)) < 1.0,
		"Hatena jumps back in front of the replaced wall (%s)" % d.hatena.position)
	await _shot("12_door_rewind")
	# 正解：青のドア
	await _move_x(3.5)
	mark = said.size()
	var ok := await _hold_until(KEY_UP, func() -> bool: return _said_line("c1.door.ok", mark), 8000)
	check(ok, "the blue door brings the OK line")
	check(await _wait_step(d, "1-4", 4000), "1-3 hands over to 1-4")


## 1-4 クイズに答える：青「大阪」・壁・青「大阪」と3回失敗（2回で矢印、3回で半分の速さ）→ 赤「東京」で突破。
func _quiz(d: PracticeDirector) -> void:
	if not _at(d, "1-4"):
		return
	var quiz := gs.current_quiz
	check(quiz != null and quiz.q == "日本の首都は？" and Array(quiz.c) == ["大阪", "東京"] and quiz.a == 1, "1-4 sets the capital wall")
	check(_said_line("c1.quiz.1"), "1-4 starts with 次はクイズ")
	await _wait(func() -> bool: return d.rules.world_speed > 0.0, 5000)
	var tries: Array = [[3.5, "c1.quiz.ng"], [0.0, "c1.any.wall"], [3.5, "c1.quiz.ng"]]
	for i in range(tries.size()):
		await _move_x(float(tries[i][0]))
		var mark := said.size()
		var wrong := await _hold_until(KEY_UP, func() -> bool: return _said_line(str(tries[i][1]), mark), 8000)
		check(wrong, "1-4 failure %d says %s" % [i + 1, tries[i][1]])
		check(await _rewound(d, i + 1), "1-4 rewinds after failure %d" % (i + 1))
		if i == 1:
			check(is_equal_approx(d.arrow_hint_x(), -3.5), "two failures show the arrow to the red door (%s)" % d.arrow_hint_x())
			check(await _wait_said("c1.any.arrow", 2000, mark), "Hatena says 矢印の方へ")
			await _seconds(0.4)
			await _shot("13_quiz_arrow")
		if i == 2:
			check(is_equal_approx(d.rules.world_speed, 0.8), "three failures halve the wall speed (%.2f)" % d.rules.world_speed)
	await _move_x(-3.5)
	var mark2 := said.size()
	var ok := await _hold_until(KEY_UP, func() -> bool: return _said_line("c1.quiz.ok1", mark2), 8000)
	check(ok, "the red door 東京 brings 正解")
	check(await _wait_said("c1.quiz.ok2", 4000, mark2), "Hatena adds 色じゃなく答えで選ぼう")
	check(await _wait_step(d, "1-5", 6000), "1-4 hands over to 1-5")


## 1-5 ハート：ルールの説明 → 1問（わざと赤「54」で間違える）→ ハート 3→2 →「練習だから戻しておくよ」で3つに戻る。
func _hearts(d: PracticeDirector) -> void:
	if not _at(d, "1-5"):
		return
	check(d.rules.hp_enabled and d.rules.hp_floor == 1 and d.rules.mistakes == MatchRules.Mistakes.NORMAL,
		"1-5 turns hearts on with the floor at 1")
	check(gs.uses_hp() and gs.get_player_hp(1) == 3, "three hearts are shown")
	check(await _wait_said("c1.heart.1", 3000), "Hatena points at the hearts")
	await _seconds(0.6)
	await _shot("14_hearts_intro")
	check(await _wait_said("c1.heart.3", 8000), "Hatena explains that zero hearts is out")
	var wall := "7 × 8 = ?"
	check(await _wait(func() -> bool: return gs.current_quiz != null and gs.current_quiz.q == wall, 7000), "the 7 × 8 wall comes down")
	check(Array(gs.current_quiz.c) == ["56", "54"] and gs.current_quiz.a == 0, "the wall has 56 / 54 with 56 right")
	check(await _wait_said("c1.heart.4", 3000), "Hatena asks to solve one question")
	await _wait(func() -> bool: return d.rules.world_speed > 0.0, 5000)
	await _seconds(0.3)
	await _shot("15_hearts_wall")
	# 赤「54」（不正解）をくぐる → ハート 3→2 →「ハートが1つ減ったね」→「練習だから戻しておくよ」で3つに戻る
	await _move_x(-3.5)
	var mark := said.size()
	var lost := await _hold_until(KEY_UP, func() -> bool: return _said_line("c1.heart.ng", mark), 8000)
	check(lost, "the wrong door brings the lost-heart line")
	check(gs.get_player_hp(1) == 2, "the wrong door takes a heart (%d)" % gs.get_player_hp(1))
	check(await _wait_said("c1.heart.5", 6000, mark), "Hatena puts the heart back for practice")
	check(await _wait(func() -> bool: return gs.get_player_hp(1) == 3, 4000), "the hearts come back to three")
	await _shot("16_hearts_restored")
	check(await _wait_step(d, "1-6", 6000), "1-5 hands over to 1-6")


## 1-6 床の端：始めに海とサメを短く見せる → 横の端から落ちて失敗 → まきもどし → 横・うしろのギリギリ ゾーン。
func _edge(d: PracticeDirector) -> void:
	if not _at(d, "1-6"):
		return
	check(d.rules.input_locked and not d.rules.fence_enabled and is_zero_approx(d.rules.world_speed),
		"1-6 stops the conveyor, removes the fence and locks for the start")
	check(d.rules.ocean == MatchRules.Ocean.REPORT_AFTER_BITE, "1-6 reports the shark bite instead of ending")
	check(await _wait_said("c1.edge.1", 5000), "Hatena says the sea is outside the floor")
	await _seconds(1.6)
	await _shot("17_edge_sea")
	check(await _wait_said("c1.edge.2", 5000), "Hatena says falling is out even with hearts")
	await _seconds(0.6)
	await _shot("18_edge_sign")
	check(await _wait_said("c1.edge.6", 8000), "task A starts with the floor edge line")
	check(not d.rules.input_locked, "the start unlocks the controls")
	await _seconds(2.3)
	check(_sign_has(d, "横の端まで"), "the sign shows the side task (%s)" % _sign_text(d))
	await _shot("19_edge_zones")
	# 失敗：横の端から海へ落ちる → サメにかまれて「落ちたね」→ まきもどし
	var mark := said.size()
	var fell := await _hold_until(KEY_LEFT, func() -> bool: return gs.p1_fall_committed or gs.p1_waiting_for_shark, 5000)
	check(fell, "running off the side drops the player into the sea")
	await _seconds(1.2)
	await _shot("20_edge_fall")
	check(await _wait_said("c1.edge.13", 9000, mark), "the shark bite brings the fell line")
	check(await _rewound(d, 1), "1-6 rewinds to the start of the task")
	check(gs.p1_alive and not gs.p1_waiting_for_shark, "the player is back on the floor")
	await _shot("21_edge_rewind")
	# タスクA：横のゾーンに入って、真ん中へ戻る
	mark = said.size()
	await _move_x(10.6)
	check(await _wait_said("c1.edge.8", 2000, mark), "the side zone brings ギリギリ")
	await _move_x(0.0)
	check(await _wait_said("c1.edge.9", 2000, mark), "back in the middle brings OK")
	check(d.is_sign_done(&"wave") or d.sign_wall == null, "task A ticks the sign")
	check(await _wait_said("c1.edge.10", 4000, mark), "task B starts with the back edge line")
	# タスクB：うしろのゾーン（z −10〜−12.5）に入って、z −5 より前へ戻る
	mark = said.size()
	await _hold_until(KEY_DOWN, func() -> bool: return gs.player_local_z <= -10.6, 3000)
	check(await _wait_said("c1.edge.8", 2000, mark), "the back zone brings ギリギリ")
	await _shot("22_edge_back")
	await _hold_until(KEY_UP, func() -> bool: return gs.player_local_z >= -4.0, 3000)
	check(await _wait_said("c1.edge.11", 2000, mark), "back in front brings the time tip")
	check(await _wait_step(d, "1-7", 8000), "1-6 hands over to 1-7")


## 1-7 仕上げ：カウントダウン → 海に落ちて負け → 「惜しい」→ やり直し → 3枚（3枚目はボス壁）をノーミスで突破。
func _final(d: PracticeDirector) -> void:
	if not _at(d, "1-7"):
		return
	check(await _wait_said("c1.final.2", 5000), "Hatena says the real speed line")
	check(await _wait(func() -> bool: return d.overlay.countdown_text() == "3", 6000), "the countdown starts with 3")
	check(d.rules.input_locked and d.rules.hp_enabled and d.rules.mistakes == MatchRules.Mistakes.NORMAL
		and d.rules.ocean == MatchRules.Ocean.NORMAL, "1-7 plays by the real rules")
	check(gs.target_count == 3 and gs.is_boss_index(2) and gs.num_choices_for_index(2) == 4, "three walls, the third is a 4-door boss")
	check(d.overlay.round_label() == "仕上げ 1/3", "the HUD shows 仕上げ 1/3 (%s)" % d.overlay.round_label())
	await _shot("23_final_countdown")
	check(await _round_running(d), "スタート unlocks and runs at the automatic speed")
	# 負け：海に落ちる → 本番のサメ → 「惜しい」→「もう一回」→ 仕上げの最初から
	var mark := said.size()
	var fell := await _hold_until(KEY_LEFT, func() -> bool: return gs.p1_fall_committed or gs.p1_waiting_for_shark, 5000)
	check(fell, "running off the side drops the player into the sea")
	check(await _wait_said("c1.final.ng", 12000, mark), "losing brings 惜しい")
	await _shot("24_final_lost")
	check(await _wait_said("c1.any.retry", 4000, mark), "Hatena says もう一回")
	check(await _wait(func() -> bool: return d.overlay.countdown_text() == "3", 4000), "the round restarts with the countdown")
	check(d.step_failures == 1 and gs.get_player_hp(1) == 3 and gs.p1_alive and gs.current_wall_index == 0,
		"the restart gives three hearts and the first wall (failures %d, hp %d)" % [d.step_failures, gs.get_player_hp(1)])
	check(await _round_running(d), "the second round starts")
	# 壁1「12 ÷ 4 = ?」青「3」・壁2「水が凍る温度は？」赤「0℃」・壁3（ボス）緑「木星」
	var answers := [3.5, -3.5, -1.95]
	for i in range(answers.size()):
		await _move_x(float(answers[i]))
		var index := i
		var wall_mark := said.size()
		var passed := await _hold_until(KEY_UP, func() -> bool:
			return gs.current_wall_index > index or d.finished, 15000)
		check(passed, "wall %d is passed" % (i + 1))
		if i < 2:
			check(await _wait(func() -> bool: return d.overlay.round_label() == "仕上げ %d/3" % (index + 2), 1000),
				"the HUD shows 仕上げ %d/3 (%s)" % [i + 2, d.overlay.round_label()])
			check(await _wait_said("c1.final.ok", 2000, wall_mark), "a right answer brings いいね")
		if i == 1:
			check(await _wait_said("c1.final.boss", 4000, wall_mark), "the boss wall brings the boss line")
			await _shot("25_final_boss")
	check(gs.get_player_hp(1) == 3, "no heart was lost in the final round")


## クリア：花火・歓声・ウェーブ → クリアカードとスタンプ（★）→ ボタン。
func _clear(d: PracticeDirector) -> void:
	var done := await _wait(func() -> bool: return d.finished, 8000)
	check(done, "passing the boss wall finishes the course")
	if not done:
		return
	check(GameManager.has_practice_stamp("c1") and GameManager.practice_stamp_star("c1"), "c1 gets a stamp with the star")
	check(await _wait_said("c1.clear.1", 3000), "Hatena says the clear line")
	await _seconds(0.8)
	await _shot("26_clear_celebrate")
	check(await _wait_said("c1.clear.nomiss", 3000), "a no-miss final brings the no-miss line")
	var shown := await _wait(func() -> bool: return d.overlay.clear_card_visible(), 8000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	var saved_stamps: Variant = _saved_settings().get("practice_stamps", {})
	check(saved_stamps is Dictionary and (saved_stamps as Dictionary).has("c1"), "the stamp is saved (%s)" % [saved_stamps])
	var buttons := d.overlay.clear_buttons()
	check(buttons.size() == 2 and buttons[0].text == "次のコースへ" and buttons[1].text == "メニューに戻る",
		"the clear card has both buttons")
	var last_line := await _wait_said("c1.clear.2", 4000)
	check(last_line, "Hatena says the last clear line with the card")
	await _seconds(0.6)
	if buttons.size() == 2:
		check(get_viewport().gui_get_focus_owner() == buttons[1], "メニューに戻る is selected")
	await _shot("27_clear_card")
	await _tap(KEY_ENTER)


func _back_to_select() -> bool:
	var returned := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU, 20000)
	check(returned, "the clear card returns to the menu")
	if not returned:
		return false
	check(gs.mode != Constants.MODE_PRACTICE and gs.practice_rules == null, "the menu is back to the normal mode")
	var opened := await _wait(func() -> bool:
		var select := _menu_node("PracticeCourseSelect") as PracticeCourseSelect
		return select != null and select.is_open(), 8000)
	check(opened, "the course select opens again after the course")
	check(not PracticeSession.return_to_select, "the return flag is consumed")
	var prompt := _menu_node("PracticeIntroPrompt") as PracticeIntroPrompt
	check(prompt != null and not prompt.is_open(), "the first-run prompt stays closed")
	if not opened:
		return false
	var select := _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	var holder := select.card("c1").find_child("StampHolder", true, false)
	var stamp: Node = holder.get_child(holder.get_child_count() - 1) if holder != null and holder.get_child_count() > 0 else null
	check(stamp != null and bool(stamp.get("stamped")), "the c1 card shows the stamp")
	var ribbon := select.card("c1").find_child("NextRibbon", true, false) as CanvasItem
	check(ribbon != null and not ribbon.visible, "c1 is no longer recommended")
	await _seconds(0.5)
	# ①が済んだので、つぎのおすすめ（遊べるなら②。段階5から）が選ばれている
	var next := PracticeCatalog.next_recommended()
	var expected := select.card(next) if PracticeCatalog.is_available(next) else select.card("c1")
	check(get_viewport().gui_get_focus_owner() == expected, "the next recommended card is selected (%s)" % next)
	await _shot("28_back_to_select")
	await _tap(KEY_ESCAPE)
	await _seconds(0.3)
	check(not select.is_open(), "Esc closes the course select")
	return true


## もう一度①：ポーズ画面の「このレッスンをスキップ」で 1-2 へ、「タイトルに戻る」でコースをやめる（コース選択は開かない）。
func _pause_skip_and_quit() -> void:
	var button := get_tree().current_scene.find_child("PracticeBtn", true, false) as Button
	button.pressed.emit()
	await _seconds(0.4)
	# おすすめは②になっているので、①のカードを選んでから Enter
	var select := _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	if select != null and select.card("c1") != null:
		select.card("c1").grab_focus()
		await _frames(2)
	await _tap(KEY_ENTER)
	var director := await _enter_game()
	if director == null:
		return
	check(director.step.id == "1-1", "the second run starts at 1-1")
	var world := get_tree().current_scene
	await _tap(KEY_ESCAPE)
	await _seconds(0.3)
	var pause_menu := world.get("pause_menu") as CanvasLayer
	check(get_tree().paused and pause_menu != null and pause_menu.visible, "Esc opens the pause menu")
	var skip := world.find_child("PracticeSkipButton", true, false) as Button
	check(skip != null and skip.text == "このレッスンをスキップ", "the pause menu has the skip button")
	await _shot("29_pause_practice")
	if skip == null:
		return
	skip.pressed.emit()
	await _frames(5)
	check(not get_tree().paused, "skipping resumes the game")
	check(director.step != null and director.step.id == "1-2" and director.skipped_steps == 1, "skipping moves on to 1-2")
	check(gs.player_local_z >= -6.05, "after skipping 1-1 the player stands inside the fence (%.2f)" % gs.player_local_z)
	await _seconds(0.5)
	await _tap(KEY_ESCAPE)
	await _seconds(0.3)
	var title: Button = null
	for node: Node in pause_menu.find_children("*", "Button", true, false):
		if (node as Button).text == "タイトルに戻る":
			title = node as Button
	check(title != null, "the pause menu has the title button")
	if title == null:
		return
	title.pressed.emit()
	var returned := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU, 20000)
	check(returned, "quitting the course returns to the menu")
	await _seconds(1.2)
	select = _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	check(select != null and not select.is_open(), "quitting does not open the course select")
	check(not get_tree().paused and gs.mode != Constants.MODE_PRACTICE, "the menu is unpaused and back to normal")


# ---------- レッスンの道具 ----------

## いまのレッスンが id か（違えば、失敗にしてそのレッスンを飛ばす）。
func _at(d: PracticeDirector, id: String) -> bool:
	var ok := d.step != null and d.step.id == id
	check(ok, "the course is at %s (%s)" % [id, d.step.id if d.step != null else "-"])
	return ok


func _wait_step(d: PracticeDirector, id: String, timeout_ms: int) -> bool:
	return await _wait(func() -> bool: return d.step != null and d.step.id == id, timeout_ms)


## 監督が text_id を言ったか（since から後で）。
func _said_line(text_id: String, since := 0) -> bool:
	return said.slice(since).has(text_id)


func _wait_said(text_id: String, timeout_ms: int, since := 0) -> bool:
	return await _wait(func() -> bool: return _said_line(text_id, since), timeout_ms)


## まきもどしが済んだ（失敗の数が failures、プレイヤーが x 0・z 0 に戻った）。
func _rewound(d: PracticeDirector, failures: int) -> bool:
	return await _wait(func() -> bool:
		return d.step_failures == failures and not d.rules.input_locked and absf(gs.player_x) < 0.05 \
			and absf(gs.player_local_z) < 0.05 and gs.p1_alive, 8000)


## しあげの回が動き出した（カウントダウンの「スタート！」のあと、操作が戻り、自動の速さ）
func _round_running(d: PracticeDirector) -> bool:
	var started := await _wait(func() -> bool: return d.overlay.countdown_text() == "スタート", 5000)
	var running := await _wait(func() -> bool: return not d.rules.input_locked and d.rules.world_speed < 0.0, 1000)
	if running:
		await _seconds(0.2)
		await _shot("23b_final_start")
		# 「スタート！」は 0.55 秒で上へ抜けて消える（同じ時に来る最初の壁のドアと問題文に長くかぶらない）
		await _seconds(0.5)
		check(d.overlay.countdown_text().is_empty(), "スタート is gone before the first wall comes close")
	return started and running


## 看板の文字（看板の壁の文字を集める。看板の壁がないときはオーバーレイの代わりの看板）。
func _sign_text(d: PracticeDirector) -> String:
	if d.sign_wall == null:
		return d.overlay.sign_text().replace("\n", "／")
	var parts: Array[String] = []
	for node: Node in d.sign_wall.find_children("*", "Label3D", true, false):
		parts.append((node as Label3D).text)
	for node: Node in d.sign_wall.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return "／".join(parts).replace("\n", "／")


func _sign_has(d: PracticeDirector, text: String) -> bool:
	var shown := _sign_text(d)
	if shown.is_empty() and d.sign_wall != null:
		# 看板の壁が文字を Label3D・Label で出していないときは、読めないので確かめない
		if not notes.has("sign wall text is not readable from Label3D/Label"):
			notes.append("sign wall text is not readable from Label3D/Label")
		return true
	return shown.replace("／", " ").replace("\n", " ").contains(text.replace("／", " "))


func _has_prop(path: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(path))


# ---------- 道具 ----------

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


## 実際のキー入力として押して離す。
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


## condition が true になるまで押しつづける（timeout_ms まで）。
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
	PracticeSession.return_to_select = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes,
		"said": said}
	print("PRACTICE_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
