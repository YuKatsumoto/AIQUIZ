extends Node

## コース③（2人対戦）の実機の通しテスト（docs/new_tutorial/phase6_design.md 4.2）。メニューのコース選択から③を始め、キー入力とクリックで通す。
## CPU と（3-0 から クリアまで）：
##   3-0 ［CPUと］ → 3-1 矢印キーの声かけ → W A S D で左右・前後とスペース → 3-2 壁1を先に取る・壁2は CPU が先 → 3-3 CPU が間違えて
##   P1 が正解 → 3-4 押し合い → 離して押し直して一押し → 3-5 のこぎりへ下がって捕まる → まきもどし → 逃げ切る → 3-6 一度外して当てる
##   → 3-7 CPU の突進をよける → 3-8 正解 → ゴールレース → スコアタワーの判定 →（3-9）→ クリアカード（スタンプ）→［メニューに戻る］
## 人どうし（P2 の入力をテストから送る：矢印・右の Ctrl）：
##   3-0 ［2人で］→ 右の Ctrl で参加 → 3-1 2人とも ✓ → 3-2 P2 が先に正解 → 3-3 P1 が先に間違える → 3-4 P2 の一押し
##   → 3-5 はとばす → 3-6 P1 のゴーストが当てて、P2 がよける → 3-7 役を入れかえて（演出は Enter で飛ばす）同じく → メニューへ
## 設定の保存先はテスト用に差し替え、テストの後で元に戻す。撮った画面は artifacts/practice_course3/。
## 本編側（担当 A）・CPU とカード（担当 C）の道具がまだないときは、その確かめを飛ばして notes に書く。

const OUT := "res://artifacts/practice_course3/"
const SETTINGS := "user://practice_course3_smoke_settings.json"
const GAME_WORLD := "res://scenes/game_world.tscn"
const MAIN_MENU := "res://ui/main_menu.tscn"
const CPU_PATH := "res://scripts/practice/practice_cpu.gd"
const PICK_CARD_PATH := "res://scripts/practice/ui/practice_pick_card.gd"
const P1_KEYS := {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S}
const P2_KEYS := {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN}
## 動いている的を狙うときに先を読む秒
const LEAD_SECONDS := 0.3

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 監督が言った言葉の ID（順に）
var said: Array[String] = []
var _director: PracticeDirector = null
## いま押しているキー（最後に全部離す）
var _held := {}
## PRACTICE_C3_FROM（とちゅうのレッスンから始めたとき。前のレッスンの結果を見る確かめはしない）
var _from := ""


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "two": GameManager.is_2p_mode, "endless": GameManager.is_endless_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	PracticeSession.with_cpu = false
	_note_tools()

	# 調べるとき用：PRACTICE_C3_ONLY=cpu / human で片方だけ、PRACTICE_C3_FROM=3-6 などでそのレッスンから（前はとばす）
	var only := OS.get_environment("PRACTICE_C3_ONLY")
	var from := OS.get_environment("PRACTICE_C3_FROM")
	_from = from
	if only != "human" and await _launch(true):
		var director := await _enter_game()
		if director != null:
			_watch(director)
			if await _pick(director, true):
				var flow := [["3-1", _cpu_keys], ["3-2", _cpu_race], ["3-3", _cpu_chance], ["3-4", _push.bind(true)],
					["3-5", _cpu_saw], ["3-6", _cpu_ghost], ["3-7", _cpu_dodge]]
				await _run_flow(director, flow, from)
				if await _cpu_goal(director):
					await _clear(director)
	if only != "cpu" and await _launch(only == "human"):
		var director := await _enter_game()
		if director != null:
			_watch(director)
			if await _pick(director, false):
				var flow := [["3-1", _human_keys], ["3-2", _human_race], ["3-3", _human_chance], ["3-4", _push.bind(false)],
					["3-5", _human_skip_saw], ["3-6", _human_ghost.bind("3-6")], ["3-7", _human_ghost.bind("3-7")]]
				await _run_flow(director, flow, from)
				await _leave(director)
	_finish()


## レッスンの確かめを順に流す。from があれば、そのレッスンへとんでから（前の確かめはしない）。
func _run_flow(d: PracticeDirector, flow: Array, from: String) -> void:
	var start := 0
	if not from.is_empty():
		for i in range(flow.size()):
			if flow[i][0] == from:
				start = i
				notes.append("started at %s (PRACTICE_C3_FROM)" % from)
				d.restart_from(from)
				await _frames(2)
	for i in range(start, flow.size()):
		var call: Callable = flow[i][1]
		await call.call(d)


## A・C の道具がそろっているか（ないものは notes に書く）
func _note_tools() -> void:
	for path: String in [CPU_PATH, PICK_CARD_PATH]:
		if not ResourceLoader.exists(path):
			notes.append("missing script %s" % path)
	var rules := MatchRules.new()
	for property: String in ["saw", "finish_with_goal"]:
		if not (property in rules):
			notes.append("MatchRules has no %s" % property)
	for method: String in ["practice_set_cpu_input", "practice_make_ghost", "practice_skip_ghost_intro", "practice_set_score",
			"practice_ghost_state", "practice_reset_saw"]:
		if not gs.has_method(method):
			notes.append("QuizGameState has no %s" % method)
	for sig: String in ["practice_saw_caught", "practice_ghost_ready", "practice_ghost_hit", "practice_ghost_missed",
			"practice_ceremony_finished"]:
		if not gs.has_signal(sig):
			notes.append("QuizGameState has no signal %s" % sig)
	if not (&"practice_p2_cpu" in gs):
		notes.append("QuizGameState has no practice_p2_cpu")


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


# ---------- メニューから③へ ----------

## メインメニューを開き（cpu の回）・コース選択から③を選ぶ。2回目（人どうし）は、クリアのあとに開いたコース選択から。
func _launch(first: bool) -> bool:
	var select: PracticeCourseSelect = null
	if first:
		get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.find_child("PracticeBtn", true, false) != null \
			and not SceneTransition.is_transitioning(), 25000)
	check(ready, "the main menu opens")
	if not ready:
		return false
	await _seconds(1.5)
	select = _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	if select == null or not select.is_open():
		var button := get_tree().current_scene.find_child("PracticeBtn", true, false) as Button
		button.pressed.emit()
		select = _menu_node("PracticeCourseSelect") as PracticeCourseSelect
	elif not first:
		check(true, "the course select is open again after the clear")
	check(select != null and select.is_open(), "the tutorial button opens the course select")
	if select == null:
		return false
	await _seconds(0.4)
	var card := select.card("c3")
	check(card != null and not card.disabled, "the c3 card can be chosen")
	if card == null or card.disabled:
		return false
	card.grab_focus()
	await _frames(2)
	if first:
		await _shot("00_course_select")
	await _tap(KEY_ENTER)
	return true


func _enter_game() -> PracticeDirector:
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 20000)
	check(arrived, "choosing c3 opens the game world")
	if not arrived:
		return null
	var world := get_tree().current_scene
	await _wait(func() -> bool: return world.get("practice_director") is PracticeDirector, 15000)
	if world.get("practice_director") is PracticeDirector:
		_watch(world.get("practice_director") as PracticeDirector)
	var ready := await _wait(func() -> bool:
		var d := world.get("practice_director") as PracticeDirector
		return d != null and d.step != null and not SceneTransition.is_transitioning(), 15000)
	check(ready, "the practice director starts course 3")
	if not ready:
		return null
	var director := world.get("practice_director") as PracticeDirector
	check(PracticeSession.course_id == "c3" and director.course.id == "c3", "the director plays c3")
	check(director.overlay.course_title() == "③ 2人対戦", "the course title is shown (%s)" % director.overlay.course_title())
	var dots := 10 if QuizGameState.sudden_death_available else 9
	check(director.overlay.dot_count() == dots, "%d progress dots (%d)" % [dots, director.overlay.dot_count()])
	check(gs.num_players == 2, "course 3 is a 2-player round (%d)" % gs.num_players)
	return director


# ---------- 3-0 相手を選ぶ ----------

func _pick(d: PracticeDirector, with_cpu: bool) -> bool:
	if not _at(d, "3-0"):
		return false
	check(d.rules.input_locked, "3-0 locks the input")
	var world := get_tree().current_scene
	var card_node: Node = null
	if ResourceLoader.exists(PICK_CARD_PATH):
		await _wait(func() -> bool: return d.find_child("PracticePickCard", true, false) != null, 5000)
		card_node = d.find_child("PracticePickCard", true, false)
	if card_node == null:
		notes.append("no PracticePickCard: 3-0 used PracticeSession.with_cpu")
		PracticeSession.with_cpu = with_cpu
		if not with_cpu:
			await _seconds(0.5)
			await _rctrl_tap()
		return await _wait_step(d, "3-1", 8000)
	var card := card_node as CanvasLayer
	check(await _wait(func() -> bool: return bool(card.call(&"is_open")), 3000), "the pick card opens on the game screen")
	await _seconds(0.5)
	if with_cpu:
		await _shot("01_pick_card")
		# ［CPUと］が選んである：Enter
		await _tap(KEY_ENTER)
		check(await _wait_step(d, "3-1", 5000), "CPUと goes to 3-1")
		check(PracticeSession.with_cpu, "PracticeSession.with_cpu is set")
		check(d.has_cpu() or not ResourceLoader.exists(CPU_PATH), "the director made the CPU")
		if &"practice_p2_cpu" in gs:
			check(bool(gs.get(&"practice_p2_cpu")), "game_state.practice_p2_cpu is on")
		return d.step != null and d.step.id == "3-1"
	# ［2人で］→「P2は右Ctrlで参加」→ 右の Ctrl →「P2が参加」
	await _click(card.call(&"button", 0) as Control)
	check(await _wait(func() -> bool: return str(card.call(&"mode")) == "join", 2000), "2人で waits for P2")
	await _seconds(0.4)
	await _shot("30_pick_join")
	# 左の Ctrl では参加しない
	await _key_event(KEY_CTRL, true, KEY_LOCATION_LEFT)
	await _frames(3)
	await _key_event(KEY_CTRL, false, KEY_LOCATION_LEFT)
	await _frames(3)
	check(str(card.call(&"mode")) == "join", "the left Ctrl does not join")
	await _rctrl_tap()
	check(await _wait(func() -> bool: return str(card.call(&"mode")) == "joined", 1500), "the right Ctrl joins P2")
	await _frames(4)
	await _shot("31_pick_joined")
	check(await _wait_step(d, "3-1", 5000), "the join goes to 3-1")
	check(not PracticeSession.with_cpu and not d.has_cpu(), "2人で plays without the CPU")
	if &"practice_p2_cpu" in gs:
		check(not bool(gs.get(&"practice_p2_cpu")), "game_state.practice_p2_cpu is off")
	return d.step != null and d.step.id == "3-1"


# ---------- 3-1 2人の操作 ----------

func _cpu_keys(d: PracticeDirector) -> void:
	if not _at(d, "3-1"):
		return
	var step := d.step
	check(not d.rules.input_locked and is_zero_approx(d.rules.world_speed) and d.rules.fence_enabled, "3-1 stops the conveyor and sets the fence")
	check(absf(gs.player_x - 1.5) < 0.1 and absf(gs.player2_x + 1.5) < 0.1, "P1 stands at x +1.5 and P2 at x -1.5")
	check(await _wait_said("c3.keys.cpu1", 4000), "Hatena says 今回の相手はCPU")
	check(_sign_has(d, "2人のときの操作"), "the sign shows 2人のときの操作 (%s)" % _sign_text(d))
	await _seconds(1.0)
	await _shot("02_keys_sign")
	check(await _wait_said("c3.keys.cpu2", 5000), "Hatena says 2人のときP1はWASDで動く")
	check(await _wait_said("c3.keys.cpu3", 5000), "Hatena says WASDで動いてジャンプしてみて")
	await _wait(func() -> bool: return str(step.get("phase")) == "play", 4000)
	# 矢印キーでは動かない（P2 の キー。CPU なので何も動かない）→ もう一度「2人のときP1はWASDで動く」
	var mark := said.size()
	var x := gs.player_x
	await _hold(KEY_LEFT, 0.4)
	check(absf(gs.player_x - x) < 0.05, "the arrow keys do not move P1 in a 2-player round")
	check(await _wait_said("c3.keys.cpu2", 1500, mark), "pressing an arrow key repeats 2人のときP1はWASDで動く")
	await _seconds(0.2)
	await _shot("03_keys_arrow_hint")
	# W A S D で左右・前後とスペース
	await _hold(KEY_A, 0.3)
	await _hold(KEY_D, 0.3)
	await _hold(KEY_W, 0.3)
	await _hold(KEY_S, 0.3)
	check(not d.is_sign_done(&"p1_keys"), "moving without a jump does not tick yet")
	mark = said.size()
	await _tap(KEY_SPACE)
	check(await _wait(func() -> bool: return d.is_sign_done(&"p1_keys"), 2000), "moving and a jump tick the P1 panel")
	check(await _wait_said("c3.keys.ok", 2000, mark), "Hatena says OK")
	await _seconds(0.3)
	await _shot("04_keys_done")
	check(await _wait_step(d, "3-2", 5000), "3-1 hands over to 3-2")


func _human_keys(d: PracticeDirector) -> void:
	if not _at(d, "3-1"):
		return
	check(await _wait_said("c3.keys.1", 4000), "Hatena says 2人のときは操作が変わる")
	check(await _wait_said("c3.keys.2", 5000), "Hatena says P1はWASDとスペース")
	check(await _wait_said("c3.keys.3", 5000), "Hatena says P2は矢印キーと右Ctrl")
	check(await _wait_said("c3.keys.5", 5000), "Hatena says エモートはP2なら8・9・0")
	check(await _wait_said("c3.keys.6", 5000), "Hatena says 2人とも動いてみて")
	# P1 だけ動く：P1 のパネルだけ ✓
	for key: Key in [KEY_A, KEY_D, KEY_W, KEY_S]:
		await _hold(key, 0.3)
	await _tap(KEY_SPACE)
	check(await _wait(func() -> bool: return d.is_sign_done(&"p1_keys"), 2000), "P1's moves tick the P1 panel")
	await _seconds(0.5)
	check(d.step.id == "3-1" and not d.is_sign_done(&"p2_keys"), "3-1 waits for P2 too")
	# P2：矢印と右の Ctrl
	var p2x := gs.player2_x
	await _hold(KEY_LEFT, 0.3)
	check(gs.player2_x > p2x + 0.5, "the left arrow moves P2 (x %.2f -> %.2f)" % [p2x, gs.player2_x])
	for key: Key in [KEY_RIGHT, KEY_UP, KEY_DOWN]:
		await _hold(key, 0.3)
	var mark := said.size()
	await _rctrl_tap()
	check(await _wait(func() -> bool: return d.is_sign_done(&"p2_keys"), 2000), "P2's moves and right Ctrl tick the P2 panel")
	check(await _wait_said("c3.keys.ok", 2000, mark), "both ticks bring OK")
	await _seconds(0.3)
	await _shot("32_keys_both")
	check(await _wait_step(d, "3-2", 5000), "3-1 hands over to 3-2")


# ---------- 3-2 早い者勝ち ----------

func _cpu_race(d: PracticeDirector) -> void:
	if not _at(d, "3-2"):
		return
	check(await _wait_said("c3.race.1", 3000), "Hatena says 先にくぐった方だけ得点")
	check(d.rules.hp_enabled and d.rules.mistakes == MatchRules.Mistakes.NORMAL, "3-2 plays the real 2-player rules")
	check(gs.current_quiz != null and gs.current_quiz.q == "1ダースは何個？", "wall 1 is 1ダースは何個？")
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 6000)
	await _seconds(0.5)
	await _shot("05_race_wall1")
	# 壁1：P1 が先に青「12」
	var score1 := gs.score
	await _move_p1_x(d.door_x(0, 2))
	var mark := said.size()
	var passed := await _hold_until(KEY_W, func() -> bool: return gs.score > score1 or gs.player2_score > 0, 12000)
	check(passed and gs.score == score1 + 1 and gs.player2_score == 0, "P1 takes wall 1 first (P1 %d, P2 %d)" % [gs.score, gs.player2_score])
	check(await _wait_said("c3.race.win", 2000, mark), "Hatena says 先に取ったね")
	check(await _wait_said("c3.race.card", 4000, mark), "Hatena says 得点は下のカードに出る")
	await _seconds(0.4)
	await _shot("06_race_card")
	# 壁2：CPU が先に赤「72」
	check(await _wait_said("c3.race.2", 8000, mark), "wall 2 brings 前に出れば早く着く")
	check(gs.current_quiz != null and gs.current_quiz.q == "8 × 9 = ?", "wall 2 is 8 × 9 = ?")
	if d.has_cpu():
		var cpu_won := await _wait(func() -> bool: return gs.player2_score > 0, 15000)
		check(cpu_won, "the CPU rushes and takes wall 2")
		check(await _wait_said("c3.race.lost", 2000, mark), "Hatena says CPUに先を越された")
		check(await _wait_said("c3.race.speed", 4000, mark), "Hatena says 速さも大事")
		await _seconds(0.2)
		await _shot("07_race_cpu_wins")
	else:
		notes.append("no CPU: P1 takes wall 2 in 3-2")
		await _move_p1_x(d.door_x(1, 2))
		await _hold_until(KEY_W, func() -> bool: return d.step.id != "3-2" or str(d.step.get("phase")) == "talk", 12000)
	check(await _wait_step(d, "3-3", 6000), "3-2 hands over to 3-3")


func _human_race(d: PracticeDirector) -> void:
	if not _at(d, "3-2"):
		return
	check(await _wait_said("c3.race.1", 3000), "Hatena says 先にくぐった方だけ得点")
	check(await _wait_said("c3.race.2", 6000), "3 s later 前に出れば早く着く")
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 6000)
	# P2 が青「12」へ走って先に取る
	await _move_x(2, d.door_x(0, 2))
	var mark := said.size()
	var passed := await _hold_until(KEY_UP, func() -> bool: return gs.player2_score > 0 or gs.score > 0, 12000)
	check(passed and gs.player2_score == 1 and gs.score == 0, "P2 takes the wall first (P1 %d, P2 %d)" % [gs.score, gs.player2_score])
	check(await _wait_said("c3.race.p2", 2000, mark), "Hatena says P2の得点")
	check(await _wait_said("c3.race.card", 4000, mark), "Hatena says 得点は下のカードに出る")
	await _seconds(0.3)
	await _shot("33_race_p2")
	check(await _wait_step(d, "3-3", 6000), "3-2 hands over to 3-3")


# ---------- 3-3 間違えても続く ----------

func _cpu_chance(d: PracticeDirector) -> void:
	if not _at(d, "3-3"):
		return
	check(gs.current_quiz != null and gs.current_quiz.q == "日本一長い川は？", "the wall is 日本一長い川は？")
	var hp2 := gs.get_player_hp(2)
	if d.has_cpu():
		check(await _wait_said("c3.chance.1", 20000), "the CPU runs into 利根川: CPUが間違えた")
		check(gs.get_player_hp(2) == hp2 - 1, "the CPU loses a heart (%d -> %d)" % [hp2, gs.get_player_hp(2)])
		check(await _wait_said("c3.chance.2", 4000), "Hatena says でも問題は続く")
		check(gs.current_quiz != null and gs.current_quiz.q == "日本一長い川は？", "the wall stays after the CPU's mistake")
		await _seconds(0.2)
		await _shot("08_chance_cpu_wrong")
	else:
		notes.append("no CPU: the CPU's mistake in 3-3 was not checked")
	await _move_p1_x(d.door_x(1, 2))
	var mark := said.size()
	var score := gs.score
	await _hold_until(KEY_W, func() -> bool: return gs.score > score, 15000)
	check(gs.score == score + 1, "P1 answers 信濃川")
	check(await _wait_said("c3.chance.3", 4000, mark), "Hatena says もう1人が答えるまで続くよ")
	check(await _wait_step(d, "3-4", 6000), "3-3 hands over to 3-4")


func _human_chance(d: PracticeDirector) -> void:
	if not _at(d, "3-3"):
		return
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 8000)
	# P1 が先に青「利根川」で間違える →「でも問題は続く」→ P2 が赤「信濃川」
	await _move_p1_x(d.door_x(0, 2))
	var mark := said.size()
	var hp1 := gs.get_player_hp(1)
	await _hold_until(KEY_W, func() -> bool: return gs.get_player_hp(1) < hp1, 12000)
	check(gs.get_player_hp(1) == hp1 - 1, "P1's mistake costs a heart")
	check(await _wait_said("c3.chance.2", 3000, mark), "one mistake brings でも問題は続く")
	check(not _said_line("c3.chance.1", mark), "people do not hear CPUが間違えた")
	await _move_x(2, d.door_x(1, 2))
	await _hold_until(KEY_UP, func() -> bool: return gs.player2_score >= 2, 12000)
	check(await _wait_said("c3.chance.3", 4000, mark), "the answer brings もう1人が答えるまで続くよ")
	check(await _wait_step(d, "3-4", 6000), "3-3 hands over to 3-4")


# ---------- 3-4 押し合い ----------

func _push(d: PracticeDirector, with_cpu: bool) -> void:
	if not _at(d, "3-4"):
		return
	check(bool(d.rules.local_push_enabled) and d.rules.fence_enabled and is_zero_approx(d.rules.world_speed), "3-4 turns on the push duel")
	check(absf(gs.player_x - 0.6) < 0.1 and absf(gs.player2_x + 0.6) < 0.1, "the two stand side by side (%.2f, %.2f)" % [gs.player_x, gs.player2_x])
	check(await _wait_said("c3.push.1", 3000), "Hatena says 相手の方へ押し続けて")
	check(_sign_has(d, "押し続けて踏ん張る"), "the sign shows 押し続けて踏ん張る (%s)" % _sign_text(d))
	var mark := said.size()
	# 押し合い：P1 は D（P2 のほう）、人どうしは P2 も ←（P1 のほう）
	_press(KEY_D)
	if not with_cpu:
		_press(KEY_LEFT)
	var push_start := Time.get_ticks_msec()
	var braced := await _wait(func() -> bool: return _said_line("c3.push.2", mark), 8000)
	check(braced, "pushing into each other brings 踏ん張ってる (%d ms)" % (Time.get_ticks_msec() - push_start))
	check(d.is_sign_done(&"push"), "the push panel is ticked")
	await _seconds(0.3)
	await _shot("09_push_braced" if with_cpu else "34_push_braced")
	check(await _wait_said("c3.push.3", 4000, mark), "Hatena says 一度離して押し直すと…")
	# 離して押し直す（人どうしは P2 が）
	var key: Key = KEY_D if with_cpu else KEY_LEFT
	var hit := false
	for attempt in range(4):
		_release(key)
		await _frames(2)
		_press(key)
		hit = await _wait(func() -> bool: return _said_line("c3.push.4", mark), 700)
		if hit:
			break
		await _seconds(0.3)
	check(hit, "release and press again lands the shove: 一押しが入った")
	_release(KEY_D)
	_release(KEY_LEFT)
	await _frames(6)
	await _shot("10_push_hit" if with_cpu else "35_push_hit")
	check(d.is_sign_done(&"push_again"), "the shove panel is ticked")
	check(await _wait_said("c3.push.5", 4000, mark), "Hatena says 端で押されると海に落ちる")
	check(await _wait_step(d, "3-5", 6000), "3-4 hands over to 3-5")


# ---------- 3-5 のこぎり ----------

func _cpu_saw(d: PracticeDirector) -> void:
	if not _at(d, "3-5"):
		return
	check(d.rules.saw_enabled and not d.rules.fence_enabled, "3-5 runs the saw without the fence")
	if &"saw" in d.rules:
		check(int(d.rules.get(&"saw")) == 1, "the saw only reports a catch (REPORT_ONLY)")
	check(await _wait_said("c3.saw.1", 6000), "from the seat Hatena says 次はのこぎりが追ってくる")
	check(not d.hatena.visible, "the guide Hatena hid at the saw seat")
	await _seconds(0.6)
	await _shot("11_saw_seat")
	check(await _wait_said("c3.saw.4", 5000), "Hatena says 触れたらハートがあってもアウト")
	check(await _wait_said("c3.saw.5", 5000), "the wall brings カードが赤くなったら危険")
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 6000)
	# 一度、うしろへ下がって捕まる
	var hp := [gs.get_player_hp(1), gs.get_player_hp(2)]
	var mark := said.size()
	var caught := await _hold_until(KEY_S, func() -> bool: return _said_line("c3.saw.caught", mark), 8000)
	check(caught, "backing into the saw: 捕まったね")
	check(_said_line("c3.saw.6", mark), "nearing the saw brought 前へ逃げて")
	await _frames(4)
	await _shot("12_saw_caught")
	var rewound := await _wait(func() -> bool: return d.step_failures == 1 and str(d.step.get("phase")) in ["wait", "play"], 8000)
	check(rewound, "the catch rewinds to the start of the wall")
	check(gs.p1_alive and gs.get_player_hp(1) == int(hp[0]) and gs.get_player_hp(2) == int(hp[1]),
		"the rewind keeps both alive with the same hearts (%d, %d)" % [gs.get_player_hp(1), gs.get_player_hp(2)])
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 6000)
	# 逃げ切る：青「60分」
	await _move_p1_x(d.door_x(0, 2))
	mark = said.size()
	var score := gs.score
	await _hold_until(KEY_W, func() -> bool: return gs.score > score or gs.player2_score > 2, 12000)
	check(await _wait_said("c3.saw.ok", 3000, mark), "passing the wall brings 逃げ切った")
	await _seconds(0.3)
	await _shot("13_saw_escaped")
	var course := d.course
	check(bool(course.get(&"saved")), "the hearts and scores are saved for 3-8 (%s %s)" % [course.get(&"saved_hp"), course.get(&"saved_score")])
	check(await _wait_step(d, "3-6", 6000), "3-5 hands over to 3-6")


func _human_skip_saw(d: PracticeDirector) -> void:
	if not _at(d, "3-5"):
		return
	await _seconds(1.0)
	d.skip_step()
	check(await _wait_step(d, "3-6", 3000), "skipping 3-5 goes to 3-6")


# ---------- 3-6 ゴーストシャークに乗る ----------

func _cpu_ghost(d: PracticeDirector) -> void:
	if not _at(d, "3-6"):
		return
	check(d.rules.ghost_ride_enabled and d.rules.fence_enabled and not d.rules.saw_enabled, "3-6 allows the ghost ride inside the fence")
	check(await _wait_said("c3.ghost.1", 6000), "Hatena says アウトになっても終わりじゃない")
	if not gs.has_method(&"practice_make_ghost"):
		notes.append("no practice_make_ghost: 3-6 and 3-7 were not played")
		await _wait_step(d, "3-8", 20000)
		return
	check(not gs.p1_alive, "P1 is out for the ghost ride")
	await _seconds(1.5)
	await _shot("14_ghost_intro")
	check(await _wait_said("c3.ghost.2", 15000), "the shark brings ゴーストシャークで続けられる")
	var ready := await _wait(func() -> bool: return _said_line("c3.ghost.3"), 20000)
	check(ready, "the aim ring brings 移動キーで狙う")
	if not ready:
		return
	await _seconds(0.4)
	await _shot("15_ghost_aim")
	# 一度外す：CPU から横へ離れた所を狙う
	var mark := said.size()
	await _ghost_shot(1, func() -> Vector2: return _miss_point(1, 2), false)
	check(_said_line("c3.ghost.4", 0), "moving the ring brings スペース長押しでためる")
	check(await _wait_said("c3.ghost.miss", 6000, mark), "a miss brings 惜しい、もう一回")
	check(d.step.id == "3-6", "a miss stays in 3-6")
	# 当てる（光る帯で離す）
	await _wait(func() -> bool: return bool(gs.call(&"practice_ghost_state", 1).get("can_aim", false)), 8000)
	mark = said.size()
	await _ghost_shot(1, _lead_aim(2, LEAD_SECONDS), true)
	check(_said_line("c3.ghost.5"), "the PERFECT band brings 光る帯で離すと強い")
	var hit := await _wait_said("c3.ghost.6", 5000, mark)
	check(hit, "hitting the CPU brings 当たった")
	await _frames(10)
	await _shot("16_ghost_hit")
	check(await _wait_said("c3.ghost.7", 4000, mark), "Hatena says アウトでもまだ戦える")
	check(gs.p2_alive and absf(gs.player2_x) < 10.5, "the fence keeps the CPU on the floor (x %.2f)" % gs.player2_x)
	check(await _wait_step(d, "3-7", 6000), "3-6 hands over to 3-7")


# ---------- 3-7 ゴーストシャークをよける ----------

func _cpu_dodge(d: PracticeDirector) -> void:
	if not _at(d, "3-7"):
		return
	check(await _wait_said("c3.dodge.1", 6000), "Hatena says 次は狙われる側")
	check(gs.p1_alive and not gs.p2_alive, "P1 is back on the floor and the CPU is out")
	check(gs.get_player_hp(1) > 0, "P1 gets the hearts back from the ghost (%d)" % gs.get_player_hp(1))
	check(not d.rules.fence_enabled, "3-7 has no fence (the sea is there)")
	if not d.has_cpu():
		notes.append("no CPU: 3-7 was skipped")
		d.skip_step()
		return
	var charging := await _wait(func() -> bool: return _said_line("c3.dodge.2"), 20000)
	check(charging, "the CPU's charge brings 構えたら横へよけて")
	await _seconds(0.2)
	await _shot("17_dodge_charging")
	# 横へよける（画面の左へ）
	var mark := said.size()
	await _hold(KEY_A, 0.6)
	var dodged := await _wait_said("c3.dodge.ok", 6000, mark)
	check(dodged, "stepping aside makes the dash miss: よけたね")
	await _shot("18_dodge_ok")
	check(await _wait_step(d, "3-8", 8000), "3-7 hands over to 3-8")


# ---------- 人どうしの 3-6・3-7 ----------

## 3-6：P1 がゴースト・P2 がよける。3-7：P2 がゴースト・P1 がよける（演出は Enter で飛ばす）。1回当てて1回よけたら終わり。
func _human_ghost(d: PracticeDirector, id: String) -> void:
	if not _at(d, id):
		return
	var ghost := 1 if id == "3-6" else 2
	var target := 3 - ghost
	var start := maxi(said.size() - 1, 0)
	if not gs.has_method(&"practice_make_ghost"):
		notes.append("no practice_make_ghost: the human %s was not played" % id)
		return
	check(d.rules.fence_enabled and d.rules.ghost_ride_enabled, "%s (people) keeps the fence" % id)
	if id == "3-7":
		check(await _wait_said("c3.dodge.1", 6000), "3-7 says 次は狙われる側")
		check(await _wait(func() -> bool: return d.allow_ghost_skip, 3000), "the second ghost intro can be skipped with Enter")
		await _seconds(1.0)
		var started := Time.get_ticks_msec()
		await _tap(KEY_ENTER)
		var aiming := await _wait(func() -> bool: return bool(gs.call(&"practice_ghost_state", ghost).get("can_aim", false)), 9000)
		check(aiming and Time.get_ticks_msec() - started < 7000, "Enter skips the intro (%d ms)" % (Time.get_ticks_msec() - started))
	else:
		check(await _wait_said("c3.ghost.1", 6000), "3-6 says アウトになっても終わりじゃない")
		check(not d.allow_ghost_skip, "the first ghost intro cannot be skipped")
	check(await _wait_said("c3.ghost.3", 20000, start), "the aim ring brings 移動キーで狙う")
	# 当てる（的の人は動かない）
	var mark := said.size()
	await _ghost_shot(ghost, _lead_aim(target, LEAD_SECONDS), false)
	check(_said_line("c3.ghost.4" if ghost == 1 else "c3.ghost.4b", start), "the charge line names the right key (%s)" % ("スペース" if ghost == 1 else "右Ctrl"))
	check(not _said_line("c3.ghost.4b" if ghost == 1 else "c3.ghost.4", start), "the other player's charge key is not named")
	check(await _wait_said("c3.ghost.6", 5000, mark), "a hit brings 当たった")
	await _frames(8)
	await _shot("36_ghost_p%d_hit" % ghost)
	await _wait_said("c3.ghost.7", 4000, mark)
	check(await _wait_said("c3.dodge.2", 5000, start), "the dodger hears 構えたら横へよけて")
	check(d.step.id == id, "a hit alone does not end the round (the dodge is still to come)")
	# よける：構えた所を狙ったまま、的の人が横へ走る
	await _wait(func() -> bool: return bool(gs.call(&"practice_ghost_state", ghost).get("can_aim", false)), 8000)
	mark = said.size()
	var spot := _player_xz(target)
	var dodge_key: Key = (P1_KEYS if target == 1 else P2_KEYS)["left" if spot.x < 0.0 else "right"]
	await _ghost_shot(ghost, func() -> Vector2: return spot, false, dodge_key)
	check(await _wait_said("c3.dodge.ok", 5000, mark), "a dodge brings よけたね")
	await _shot("37_ghost_p%d_dodged" % ghost)
	var next := "3-7" if id == "3-6" else "3-8"
	check(await _wait_step(d, next, 6000), "%s hands over to %s" % [id, next])


# ---------- 3-8 ゴールと得点 ----------

func _cpu_goal(d: PracticeDirector) -> bool:
	if not _at(d, "3-8"):
		return false
	check(await _wait_said("c3.goal.1", 4000), "Hatena says 最後はゴールまで")
	check(gs.p1_alive and gs.p2_alive, "both are back on the floor")
	var course := d.course
	var hp: Array = course.get(&"saved_hp")
	check(gs.get_player_hp(1) == maxi(int(hp[0]), 1) and gs.get_player_hp(2) == maxi(int(hp[1]), 1),
		"the hearts are the ones from the end of 3-5 (%d, %d / %s)" % [gs.get_player_hp(1), gs.get_player_hp(2), hp])
	if _from.is_empty():
		check(gs.get_player_hp(2) < QuizGameState.MAX_HP or not d.has_cpu(), "the CPU still misses the heart from 3-3")
	if &"finish_with_goal" in d.rules:
		check(bool(d.rules.get(&"finish_with_goal")), "3-8 asks for the goal race")
	else:
		notes.append("MatchRules has no finish_with_goal: 3-8 ends at the wall")
	await _wait(func() -> bool: return str(d.step.get("phase")) == "play", 8000)
	await _move_p1_x(d.door_x(0, 2))
	var score := gs.score
	await _hold_until(KEY_W, func() -> bool: return gs.score > score or gs.game_state != Constants.STATE_PLAYING, 15000)
	var race := await _wait(func() -> bool: return gs.game_state == Constants.STATE_GOAL_RACE, 6000)
	check(race, "the wall leads to the real goal race")
	if race:
		await _seconds(0.8)
		await _shot("19_goal_race")
		await _hold_until(KEY_W, func() -> bool: return gs.game_state != Constants.STATE_GOAL_RACE or (gs.goal_reached_mask & 1) != 0, 15000)
		var ceremony := await _wait(func() -> bool: return gs.game_state == Constants.STATE_RESULT_CEREMONY, 20000)
		check(ceremony, "both reach the goal and the score tower ceremony starts")
		check(await _wait_said("c3.goal.2", 12000), "the ceremony brings 得点の計算を見ておこう")
		await _seconds(1.0)
		await _shot("20_ceremony_walk")
		check(await _wait_said("c3.goal.3", 15000), "the formula brings 正解数 ×（ハート ＋ 0.5）")
		await _seconds(0.6)
		check(not d.overlay.header_visible(), "the course header hides over the score tower's banner")
		await _shot("21_ceremony_formula")
		check(await _wait_said("c3.goal.4", 5000), "Hatena says ハートが残るほど有利")
		check(await _wait_said("c3.goal.5", 20000), "the verdict brings アウトの人は正解数だけ")
		await _seconds(0.4)
		await _shot("22_ceremony_verdict")
	if QuizGameState.sudden_death_available:
		check(await _wait_said("c3.sd.1", 15000), "3-9 says 同点ならサドンデス")
		check(await _wait_said("c3.sd.2", 5000), "3-9 says 設定でオフにもできる")
	return await _wait(func() -> bool: return d.finished, 15000)


# ---------- クリア ----------

func _clear(d: PracticeDirector) -> void:
	check(await _wait_said("c3.clear.1", 4000), "the clear says 対戦のルールはこれで全部")
	var card := await _wait(func() -> bool: return d.overlay.clear_card_visible(), 5000)
	check(card, "the clear card is shown")
	check(GameManager.has_practice_stamp("c3") and not GameManager.practice_stamp_star("c3"), "c3 gets the stamp without a star")
	check(await _wait_said("c3.clear.2", 5000), "Hatena says 次はオンライン対戦")
	await _seconds(0.6)
	await _shot("23_clear_card")
	var buttons := d.overlay.clear_buttons()
	check(buttons.size() == 2 and buttons[0].text == "次のコースへ" and buttons[1].text == "メニューに戻る", "the clear card has both buttons")
	if buttons.size() < 2:
		return
	check(get_viewport().gui_get_focus_owner() == buttons[1], "メニューに戻る is selected (not from the first run)")
	await _click(buttons[1])
	check(PracticeSession.return_to_select and PracticeSession.launch_next.is_empty(), "メニューに戻る goes back to the course select")


func _leave(d: PracticeDirector) -> void:
	if d.step != null:
		check(d.step.id == "3-8", "the human run reached 3-8 (%s)" % d.step.id)
	d.quit_course()
	var back := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU, 20000)
	check(back, "quitting goes back to the main menu")
	if &"practice_p2_cpu" in gs:
		check(not bool(gs.get(&"practice_p2_cpu")), "practice_p2_cpu is off after leaving")


# ---------- ゴーストの道具 ----------

## ゴースト（player）で照準を aim（毎フレームの狙い）へ動かし、ジャンプのキーでためて離す。perfect なら光る帯で離す。
## dodge_key があれば、ため始めたら的の人がそのキーで横へ走る（狙いは構えた所のまま）。
func _ghost_shot(player: int, aim: Callable, perfect: bool, dodge_key: Key = KEY_NONE) -> void:
	var keys: Dictionary = P1_KEYS if player == 1 else P2_KEYS
	await _aim(player, keys, aim, 4000)
	# ためる
	if player == 1:
		_press(KEY_SPACE)
	else:
		await _key_event(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	if dodge_key != KEY_NONE:
		_press(dodge_key)
	var deadline := Time.get_ticks_msec() + 3000
	var held_ms := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		_steer(player, keys, aim)
		var state: Dictionary = gs.call(&"practice_ghost_state", player)
		held_ms = Time.get_ticks_msec() - start
		if perfect and bool(state.get("perfect", false)):
			break
		if not perfect and held_ms >= 450 and not bool(state.get("perfect", false)):
			break
	if player == 1:
		_release(KEY_SPACE)
	else:
		await _key_event(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	# 突進の向きは、離して少しあとの照準で決まる
	var lock := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < lock:
		await get_tree().process_frame
		_steer(player, keys, aim)
	_release_all(keys)
	if dodge_key != KEY_NONE:
		await _seconds(0.3)
		_release(dodge_key)
	await _seconds(1.2)


## 照準を aim へ寄せる（近づいたら返る）。
func _aim(player: int, keys: Dictionary, aim: Callable, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	var close := 0
	while Time.get_ticks_msec() < deadline and close < 4:
		await get_tree().process_frame
		close = close + 1 if _steer(player, keys, aim) else 0
	_release_all(keys)


## 照準と狙いの差で移動キーを押す（x は +が画面の左＝左のキー）。合っていたら true。
func _steer(player: int, keys: Dictionary, aim: Callable) -> bool:
	var state: Dictionary = gs.call(&"practice_ghost_state", player)
	var ring: Variant = state.get("aim", null)
	if not (ring is Vector2):
		return false
	var delta: Vector2 = (aim.call() as Vector2) - (ring as Vector2)
	_set_key(keys.left, delta.x > 0.25)
	_set_key(keys.right, delta.x < -0.25)
	_set_key(keys.up, delta.y > 0.25)
	_set_key(keys.down, delta.y < -0.25)
	return delta.length() < 0.4


## ゴーストの突進が的に当たらない所：サメから的への線の横へ 6m
func _miss_point(ghost: int, target: int) -> Vector2:
	var state: Dictionary = gs.call(&"practice_ghost_state", ghost)
	var at := _player_xz(target)
	var shark: Variant = state.get("shark", null)
	var from := Vector2(shark.x, shark.z) if shark is Vector3 else at + Vector2(0.0, -8.0)
	var dir := (at - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var point := at + side * 6.0
	if absf(point.x) > 7.5:
		point = at - side * 6.0
	return Vector2(clampf(point.x, -7.5, 7.5), point.y)


## 動いている的の先を狙う（突進の向きは離して 0.34 秒後に決まり、突進はそこから約 0.3 秒で届く）
func _lead_aim(player: int, lead: float) -> Callable:
	var memo := {"pos": _player_xz(player), "vel": Vector2.ZERO, "t": Time.get_ticks_usec()}
	return func() -> Vector2:
		var now := _player_xz(player)
		var t := Time.get_ticks_usec()
		var dt := float(t - int(memo.t)) / 1000000.0
		if dt > 0.005:
			memo.vel = (memo.vel as Vector2).lerp((now - (memo.pos as Vector2)) / dt, 0.3)
			memo.pos = now
			memo.t = t
		return now + (memo.vel as Vector2) * lead


func _player_xz(player: int) -> Vector2:
	return Vector2(gs.player_x, gs.player_local_z) if player == 1 else Vector2(gs.player2_x, gs.player2_local_z)


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
	_press(keycode)
	await _seconds(seconds)
	_release(keycode)
	await _frames(3)


func _hold_until(keycode: Key, condition: Callable, timeout_ms: int) -> bool:
	_press(keycode)
	var ok := await _wait(condition, timeout_ms)
	_release(keycode)
	await _frames(3)
	return ok


## P1（W A S D）の x を target へ（x は +が画面の左＝A）。
func _move_p1_x(target: float, timeout_ms := 3000) -> void:
	await _move_x(1, target, timeout_ms)


## player の x を target へ（P1 は A・D、P2 は ← →）。
func _move_x(player: int, target: float, timeout_ms := 3000) -> void:
	var now := func() -> float: return gs.player_x if player == 1 else gs.player2_x
	if absf(float(now.call()) - target) < 0.12:
		return
	var keys: Dictionary = P1_KEYS if player == 1 else P2_KEYS
	var left := target > float(now.call())
	await _hold_until(keys.left if left else keys.right, func() -> bool:
		return float(now.call()) >= target - 0.06 if left else float(now.call()) <= target + 0.06, timeout_ms)


func _press(keycode: Key) -> void:
	if not _held.get(keycode, false):
		_key(keycode, true)


func _release(keycode: Key) -> void:
	if _held.get(keycode, false):
		_key(keycode, false)


func _set_key(keycode: Key, pressed: bool) -> void:
	if pressed:
		_press(keycode)
	else:
		_release(keycode)


func _release_all(keys: Dictionary) -> void:
	for keycode: Key in keys.values():
		_release(keycode)


func _key(keycode: Key, pressed: bool) -> void:
	_held[keycode] = pressed
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


## location つきのキー（右の Ctrl など）
func _key_event(keycode: Key, pressed: bool, location: KeyLocation) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame


func _rctrl_tap() -> void:
	await _key_event(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	await _frames(3)
	await _key_event(KEY_CTRL, false, KEY_LOCATION_RIGHT)
	await _frames(3)


## 部品の真ん中を、本物のマウスの動きと左クリックで押す。
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
	for keycode: Variant in _held.keys():
		if _held[keycode]:
			_key(keycode, false)
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	GameManager.is_2p_mode = bool(_saved.two)
	GameManager.is_endless_mode = bool(_saved.endless)
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	PracticeSession.with_cpu = false
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said}
	print("PRACTICE_COURSE3_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
