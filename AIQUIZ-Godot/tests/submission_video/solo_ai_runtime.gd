extends "res://tests/submission_video/take_base.gd"

## プレイ動画 E（AI が問題をつくるようす）。1 人・10問チャレンジを、出題 ONLINE（AI 生成・Claude）で遊ぶ。
## メインメニュー → 設定（出題が ONLINE になっている所を見せる）→ 10問チャレンジ → 学年・教科の画面 → ゲーム開始
## → 問題をつくっている間の画面 → 試合 → 結果、までを通す。本番のプロキシに本当に頼むので、AI の待ち時間は実際の長さ。
## そのため、この動画だけは Movie Maker ではなく画面の取り込みで撮る（record_take.py solo_ai）。
## 操作はボット（人の操作らしく：読む間・行き過ぎ・立ち直し・ジャンプ・エモート。1 問はまちがえる）。
## 設定とスキンの保存先は撮影用のファイルに替える。AI の使用量（端末ごとの 1 日の上限）は 1 試合ぶん使う。
## 引数（"--" の後ろ）：out=<report.json> screen=second record_audio=<wav>
##   screen=second で 2 台目のモニターに全画面で出す
##                      subject=<教科> grade=<学年> difficulty=<難易度>

const MAIN_MENU := "res://ui/main_menu.tscn"
const GAME_WORLD := "res://scenes/game_world.tscn"
const WRONG_WALLS := [5]
const FAKE_WALLS := [2, 7]
const EMOTE_AFTER := {0: KEY_1, 3: KEY_2, 8: KEY_3}
const COMMIT_AHEAD := 8.0

var gs: QuizGameState
var world: Node
var _playing_started := false
var _plan := {}
var _plan_wall := -1
var _wall_t := 0.0
var _hp_before := 0
var _emote_until := -1.0
var _next_hop := 0.0
var _run_until := -1.0
var _back_until := -1.0


func run() -> void:
	rng.seed = 20261113
	gs = QuizManager.game_state
	var subject := "社会"
	var grade := 6
	var difficulty := "普通"
	# llm=OFFLINE は台本の通し確認用（AI の使用量を使わない）
	var llm := "ONLINE"
	for arg: String in OS.get_cmdline_user_args():
		if arg == "screen=second":
			# 2 台目のモニター（主でない画面）で全画面にする
			var window := get_window()
			for i in range(DisplayServer.get_screen_count()):
				if i != DisplayServer.get_primary_screen():
					window.current_screen = i
			window.mode = Window.MODE_FULLSCREEN
			report["screen"] = {"index": window.current_screen, "size": DisplayServer.screen_get_size(window.current_screen)}
		if arg.begins_with("record_audio="): start_audio_record(arg.trim_prefix("record_audio="))
		if arg.begins_with("subject="): subject = arg.trim_prefix("subject=")
		if arg.begins_with("grade="): grade = int(arg.trim_prefix("grade="))
		if arg.begins_with("difficulty="): difficulty = arg.trim_prefix("difficulty=")
		if arg.begins_with("llm="): llm = arg.trim_prefix("llm=")
	use_capture_settings("ai")
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode(llm)
	# 書き出した版（製品版）と同じ設定画面にする：サドンデスの行はデバッグ版だけ、管理ダッシュボードはエディタだけに出る
	QuizGameState.sudden_death_available = false
	gs.num_players = 1
	gs.subject = subject
	gs.grade = grade
	gs.difficulty = difficulty
	report["settings"] = {"subject": subject, "grade": grade, "difficulty": difficulty}

	get_tree().change_scene_to_file(MAIN_MENU)
	if not await wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == MAIN_MENU and not SceneTransition.is_transitioning(), 60.0):
		finish("the main menu did not open")
		return
	mark("menu")
	var menu := get_tree().current_scene
	var dashboard := menu.find_child("OpenDashboardBtn", true, false) as Control
	if dashboard != null:
		dashboard.visible = false
	await sleep(3.0)
	# 設定：出題が ONLINE（AI 生成）になっている所を見せる
	await click(menu.call("practice_coach_target", &"settings"))
	await sleep(4.5)
	mark("settings_shown")
	await click(menu.call("practice_coach_target", &"set_back"))
	await sleep(1.2)
	await click(menu.call("practice_coach_target", &"mode_ten"))
	if not await wait_until(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 6.0):
		menu.call("practice_menu_show_config")
	mark("config")
	await sleep(4.0)
	report["llm_mode"] = QuizManager.provider.llm_mode
	await click(menu.call("practice_coach_target", &"start"))
	await sleep(1.0)
	if get_tree().current_scene == menu and not bool(menu.call("practice_menu_start_game")):
		pass
	mark("start_pressed")
	if not await wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == GAME_WORLD, 90.0):
		finish("never reached the game world")
		return
	world = get_tree().current_scene
	mark("game_world")
	if not await wait_until(func() -> bool: return bool(world.call("_can_trigger_start")), 180.0):
		finish("the round was never ready to start (state %s)" % gs.game_state)
		return
	mark("ready")
	await sleep(2.0)
	tap(KEY_ENTER, 0.1)
	if not await wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 40.0):
		finish("never reached PLAYING (state %s)" % gs.game_state)
		return
	mark("playing")
	_playing_started = true
	report["walls"] = []
	if not await wait_until(func() -> bool: return gs.game_state in [Constants.STATE_CLEAR, Constants.STATE_GAME_OVER], 400.0):
		finish("the round did not end (state %s, wall %d)" % [gs.game_state, gs.current_wall_index])
		return
	mark("ended")
	if _plan_wall >= 0:
		(report.walls as Array).append({"wall": _plan_wall, "right": gs.p1_hp >= _hp_before, "src": _plan.src, "q": _plan.q})
	report["end_state"] = gs.game_state
	report["score"] = gs.score
	report["hp"] = gs.p1_hp
	release_all()
	# 結果の画面を見せて終わる
	await sleep(9.0)
	mark("end")
	finish()


# --- 毎フレームの操作（1 人） ---

func brain(_delta: float) -> void:
	if not _playing_started or gs.game_state != Constants.STATE_PLAYING:
		if _playing_started:
			set_lateral(0)
			hold(KEY_W, false)
			hold(KEY_S, false)
		return
	if not gs.p1_alive or gs.current_quiz == null:
		set_lateral(0)
		return
	var index := gs.current_wall_index
	var previous_wall_z := gs.tuning.wall_start_z + float(index - 1) * gs.tuning.wall_spacing
	if index > 0 and gs.player_z < previous_wall_z + 0.8:
		set_lateral(0)
		hold(KEY_W, false)
		hold(KEY_S, false)
		return
	if _plan_wall != index:
		_make_plan(index)
	var s := t - _wall_t
	var ahead := gs.wall_z - gs.player_z
	var local_z := gs.player_z - gs.world_scroll_z
	var x := gs.player_x

	if _emote_until > 0.0 and t >= _emote_until:
		_emote_until = -1.0
		tap(KEY_SPACE, 0.1)
	if _plan.has("emote_key") and s > float(_plan.emote_at):
		tap(_plan.emote_key, 0.15)
		_emote_until = t + float(_plan.emote_len)
		_plan.erase("emote_key")

	# 前後（1 人のときの立ち位置は -8）：前へ出すぎたら下がる
	hold(KEY_W, t < _run_until and local_z < -3.0 and ahead > 10.0)
	hold(KEY_S, (t < _back_until or local_z > -2.0) and local_z > -10.0)

	if s < float(_plan.read) or _emote_until > 0.0:
		set_lateral(0)
		return
	var target_door: int = _plan.door
	if int(_plan.fake) >= 0:
		if s < float(_plan.fake_until) and ahead > COMMIT_AHEAD + 2.5:
			target_door = int(_plan.fake)
		else:
			_plan.fake = -1
			_plan["hesitate_until"] = t + rng.randf_range(0.3, 0.7)
	if t < float(_plan.get("hesitate_until", -1.0)):
		set_lateral(0)
		return
	if ahead > COMMIT_AHEAD and t > float(_plan.shift_at):
		_plan.shift_at = t + rng.randf_range(1.6, 3.4)
		_plan.offset = _door_offset()
		if rng.randf() < 0.3 and ahead > 14.0:
			_run_until = t + rng.randf_range(0.25, 0.6)
		elif rng.randf() < 0.2:
			_back_until = t + rng.randf_range(0.2, 0.4)
	var target_x := _door_x(target_door) + float(_plan.offset)
	go_x(x, target_x, 0.3 if ahead < COMMIT_AHEAD else 0.45)
	if t > _next_hop and ahead > COMMIT_AHEAD and ahead < 24.0 and absf(x - target_x) < 0.8:
		_next_hop = t + rng.randf_range(2.5, 6.0)
		if rng.randf() < 0.55:
			tap(KEY_SPACE, 0.08)


func _make_plan(index: int) -> void:
	var was_right := _plan_wall >= 0 and gs.p1_hp >= _hp_before
	var previous := _plan_wall
	if previous >= 0:
		(report.walls as Array).append({"wall": previous, "right": was_right, "src": _plan.src, "q": _plan.q})
	_plan_wall = index
	_wall_t = t
	_hp_before = gs.p1_hp
	var answer := gs.current_quiz.a
	var choices := maxi(gs.num_choices, 2)
	var door := answer
	if index in WRONG_WALLS:
		door = (answer + 1 + rng.randi() % (choices - 1)) % choices
	# AI の問題は初めて見るので、読む時間を長めにとる
	var read := rng.randf_range(1.6, 2.8) + minf(1.8, float(gs.current_quiz.q.length()) / 30.0)
	_plan = {"door": door, "fake": -1, "fake_until": 0.0, "read": read, "offset": 0.0,
		"shift_at": t + read + rng.randf_range(1.5, 2.5), "src": gs.current_quiz.src, "q": gs.current_quiz.q}
	_plan.offset = _door_offset()
	if index in FAKE_WALLS:
		_plan.fake = (door + 1 + rng.randi() % (choices - 1)) % choices
		_plan.fake_until = read + rng.randf_range(1.2, 2.0)
	_next_hop = t + read + rng.randf_range(1.5, 3.5)
	_run_until = -1.0
	_back_until = -1.0
	if previous >= 0 and was_right and EMOTE_AFTER.has(previous):
		_plan["emote_key"] = EMOTE_AFTER[previous]
		_plan["emote_at"] = rng.randf_range(0.3, 0.6)
		_plan["emote_len"] = rng.randf_range(1.5, 2.2)
		_plan.read = maxf(read, float(_plan.emote_at) + float(_plan.emote_len) + 0.4)
		_plan.shift_at = t + float(_plan.read) + rng.randf_range(1.5, 2.5)


func _door_offset() -> float:
	var half: float = gs.tuning.door4_half_width if gs.num_choices == 4 else gs.tuning.door_half_width
	return rng.randf_range(-(half - 0.8), half - 0.8)


func _door_x(door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[clampi(door, 0, 3)]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x
