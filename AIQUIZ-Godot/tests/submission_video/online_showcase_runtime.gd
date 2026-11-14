extends "res://tests/submission_video/take_base.gd"

## プレイ動画 C（オンライン対戦）の片側。tests/submission_video/record_take.py online が、
## 中継サーバー（relay-server）と、この台本を動かすゲームを 2 つ（host・guest）起動する。
## 本物のロビー（ランダムマッチ）→ 対峙の演出 → 試合 → スコアタワーの結果発表 → オンラインメニューへ戻る、までを通す。
## 問題は内蔵（OFFLINE）。操作はボットだが、人が遊んでいるように動かす：
##   ・問題を読む間（1〜3 秒）は動かない。動き出しは判断の遅れ・行き過ぎ・小さな直しが入る
##   ・迷い：いったん違うドアへ向かってから戻る壁がある。ゲストは 2 回、ホストは 1 回まちがえる
##   ・押し合い：決まった壁では、ドアへ行く前に相手に体を当てて肩で押し合う
##   ・エモート：開始前のあいさつ、正解のあと、相手がまちがえたあと、ゴールのあと。ジャンプでやめる
##   ・待っているあいだの小さなジャンプ、前へ走る・下がる、ドアの中での立ち位置の直し
## 引数（"--" の後ろ）：role=host|guest relay=ws://... out=<report.json> name=<画面に出す名前>

const GUEST_WRONG := [1, 4]
const HOST_WRONG := [6]
## ドアへ行く前に押し合う壁（両方の画面が同じ壁で始める）
const DUEL_WALLS := [0, 3, 7]
## いったん違うドアへ向かってから戻る壁
const HOST_FAKE := [2, 5]
const GUEST_FAKE := [3, 8]
## 正解して抜けたあとにエモートを出す壁（キーの番号）
const HOST_EMOTE_AFTER := {0: KEY_1, 1: KEY_2, 4: KEY_3, 8: KEY_1}
const GUEST_EMOTE_AFTER := {2: KEY_1, 5: KEY_3, 6: KEY_2}
const DUEL_END_AHEAD := 12.5
const COMMIT_AHEAD := 8.0
const EDGE_X := 6.8

var role := "host"
var relay := "ws://127.0.0.1:18766"
var shown_name := ""
var gs: QuizGameState
var world: Node
var net: NetGameState
var mine := 1

var _state := ""
var _state_t := 0.0
var _plan := {}
var _plan_wall := -1
var _wall_t := 0.0
var _hp_before := 0
var _enter_next := 0.0
var _greeted := false
var _countdown_jumped := false
var _emote_until := -1.0
var _next_hop := 0.0
var _strike_t := 0.0
var _strike_hold := 0.26
var _strike_gap := 0.09
var _run_until := -1.0
var _back_until := -1.0
var _goal_weave_until := 0.0
var _goal_weave_dir := 0
var _goal_emoted := false
var _goal_t := -1.0
var _result_phases: Array = []
var _interactive_t := -1.0


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("role="): role = arg.trim_prefix("role=")
		if arg.begins_with("relay="): relay = arg.trim_prefix("relay=")
		if arg.begins_with("name="): shown_name = arg.trim_prefix("name=")
	report["role"] = role
	report["walls"] = []
	rng.seed = 20261111 if role == "host" else 11112026
	gs = QuizManager.game_state
	# 撮影では戦績を記録しない。設定ファイルも保存しない（名前はこのプロセスの中だけ）
	QuizManager.player_analytics = null
	gs.subject = "算数"
	gs.grade = 3
	gs.difficulty = "普通"
	QuizManager.provider.set_llm_mode("OFFLINE")
	GameManager.online_name = shown_name if shown_name != "" else ("ソラ" if role == "host" else "ハテナ")
	NetworkManager.relay_url = relay

	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	if not await wait_until(func() -> bool: return get_tree().current_scene is OnlineMenu, 30.0):
		finish("online menu did not open")
		return
	var menu := get_tree().current_scene as OnlineMenu
	mark("menu")
	shot_once("online_menu", 2.0)
	# ホーム画面を少し見せてから探し始める
	await sleep(3.0 if role == "host" else 2.2)
	NetworkManager.matched.connect(func(_info: Dictionary) -> void:
		mark("matched")
		shot_once("online_found", 1.2)
		shot_once("online_versus", 7.5), CONNECT_ONE_SHOT)
	menu.find_match()
	mark("find_match")
	shot_once("online_search", 2.5)
	if not await wait_until(_in_game_world, 90.0):
		finish("never reached the game world")
		return
	world = get_tree().current_scene
	mark("game_world")
	if not await wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 120.0):
		finish("never reached PLAYING (state %s)" % gs.game_state)
		return
	mark("playing")
	net = world.get("_net_state")
	mine = gs.local_slot
	report["is_host"] = NetworkManager.is_host
	report["local_slot"] = mine

	# 試合 → ゴール → 結果発表のボタンが出るまで
	var started := t
	while t - started < 300.0:
		await get_tree().process_frame
		if gs.result_presentation_active:
			var phase: String = QuizGameState.ResultCeremonyPhase.keys()[gs.result_ceremony_phase]
			if _result_phases.is_empty() or _result_phases[-1] != phase:
				_result_phases.append(phase)
				mark("result_" + phase)
				shot_once("online_result_" + phase.to_lower(), 1.2)
			if phase == "INTERACTIVE" and _interactive_t < 0.0:
				_interactive_t = t
		if _interactive_t >= 0.0 and t - _interactive_t > 5.0:
			break
		if gs.game_state == Constants.STATE_GAME_OVER and not gs.is_elimination_result_pending() and not gs.result_presentation_active:
			report.failures.append("match ended with a game-over card")
			break
	release_all()
	report["result_phases"] = _result_phases
	report["scores"] = [gs.result_p1_score, gs.result_p2_score]
	report["correct"] = [gs.result_p1_correct_count, gs.result_p2_correct_count]
	report["hp"] = [gs.p1_hp, gs.p2_hp]
	report["winner"] = gs.result_winner
	if _interactive_t < 0.0:
		report.failures.append("the result ceremony never reached its buttons")
	# 結果画面の「オンラインメニューへ」と同じ経路で戻り、少し見せて終わる
	OnlineMenu.return_from_match(get_tree())
	await wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).current_id() == OnlineMenu.HOME, 15.0)
	mark("menu_again")
	await sleep(2.5)
	NetworkManager.leave_match()
	finish()


func _in_game_world() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == OnlineMenu.GAME_WORLD_PATH


# --- 毎フレームの操作 ---

func brain(_delta: float) -> void:
	if gs == null or world == null or not is_instance_valid(world) or not _in_game_world():
		return
	mine = gs.local_slot
	if gs.game_state != _state:
		_state = gs.game_state
		_state_t = t
	if net != null and net.paused:
		release_all()
		return
	match _state:
		Constants.STATE_WAITING_START:
			shot_once("online_arrival", 2.5)
			_before_start()
		Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN:
			_countdown()
		Constants.STATE_PLAYING:
			_playing()
		Constants.STATE_GOAL_RACE:
			_goal_race()
		_:
			set_lateral(0)
			hold(KEY_W, false)
			hold(KEY_S, false)


func _my_x() -> float:
	return gs.player_x if mine == 1 else gs.player2_x


func _their_x() -> float:
	return gs.player2_x if mine == 1 else gs.player_x


func _my_z() -> float:
	return gs.player_z if mine == 1 else gs.player2_z


func _their_z() -> float:
	return gs.player2_z if mine == 1 else gs.player_z


func _my_hp() -> int:
	return gs.p1_hp if mine == 1 else gs.p2_hp


func _alive() -> bool:
	return gs.p1_alive if mine == 1 else gs.p2_alive


## 開始前：あいさつのエモート。ホストは少し待ってから Enter で始める。
func _before_start() -> void:
	var since := t - _state_t
	if not _greeted and since > (1.0 if role == "guest" else 1.7):
		_greeted = true
		tap(KEY_1 if role == "guest" else KEY_2, 0.15)
	if NetworkManager.is_host and since > 4.2 and t >= _enter_next:
		# 受け付けられるまで、ときどき押し直す
		_enter_next = t + 0.8
		tap(KEY_ENTER, 0.1)


## コースの紹介とカウントダウン：GO の少し前にジャンプして、エモートをやめる。
func _countdown() -> void:
	if _state == Constants.STATE_COUNTDOWN:
		shot_once("online_countdown", 1.6)
	if _state == Constants.STATE_COUNTDOWN and not _countdown_jumped and t - _state_t > (0.9 if role == "host" else 1.3):
		_countdown_jumped = true
		tap(KEY_SPACE, 0.1)


func _playing() -> void:
	if not _alive() or gs.current_quiz == null:
		set_lateral(0)
		hold(KEY_W, false)
		hold(KEY_S, false)
		return
	var index := gs.current_wall_index
	var previous_wall_z := gs.tuning.wall_start_z + float(index - 1) * gs.tuning.wall_spacing
	var cleared := index == 0 or _my_z() > previous_wall_z + 0.8
	if not cleared:
		# 前の壁のドアを抜けきるまでは、そのまま進む
		set_lateral(0)
		hold(KEY_W, false)
		hold(KEY_S, false)
		return
	if _plan_wall != index:
		_make_plan(index)
	var s := t - _wall_t
	var ahead := gs.wall_z - _my_z()
	var local_z := _my_z() - gs.world_scroll_z
	var x := _my_x()

	# 前の壁のあとのエモートは、読み終わるころにジャンプでやめる
	if _emote_until > 0.0 and t >= _emote_until:
		_emote_until = -1.0
		tap(KEY_SPACE, 0.1)
	if _plan.has("emote_key") and s > float(_plan.emote_at):
		tap(_plan.emote_key, 0.15)
		_emote_until = t + float(_plan.emote_len)
		_plan.erase("emote_key")

	# 前後：走って前へ出すぎたら下がる
	hold(KEY_W, t < _run_until and local_z < 5.0 and ahead > 9.0)
	hold(KEY_S, (t < _back_until or local_z > 6.0) and local_z > -2.5)

	if s < float(_plan.read) or _emote_until > 0.0:
		# 読んでいる・踊っている間は動かない
		set_lateral(0)
		return

	# 押し合い
	if bool(_plan.duel) and ahead > DUEL_END_AHEAD and absf(x) < EDGE_X and absf(_their_x()) < EDGE_X:
		_duel(x)
		return
	if bool(_plan.duel):
		_plan.duel = false
		hold(KEY_W, false)
		# 押し合いのあと、ひと呼吸おいてからドアへ
		_plan.read = s + rng.randf_range(0.15, 0.45)
		set_lateral(0)
		return

	# 迷い：いったん違うドアへ
	var target_door: int = _plan.door
	if int(_plan.fake) >= 0:
		if s < float(_plan.fake_until) and ahead > COMMIT_AHEAD + 2.5:
			target_door = int(_plan.fake)
		else:
			_plan.fake = -1
			_plan.hesitate_until = t + rng.randf_range(0.25, 0.6)
	if t < float(_plan.get("hesitate_until", -1.0)):
		set_lateral(0)
		return

	# ドアの中の立ち位置。待っているあいだは時々立ち直す
	if ahead > COMMIT_AHEAD and t > float(_plan.shift_at):
		_plan.shift_at = t + rng.randf_range(1.4, 3.2)
		_plan.offset = _door_offset()
		if rng.randf() < 0.3 and local_z < 2.0 and ahead > 14.0:
			_run_until = t + rng.randf_range(0.25, 0.6)
		elif rng.randf() < 0.2 and local_z > 0.5:
			_back_until = t + rng.randf_range(0.2, 0.45)
	var target_x := _door_x(target_door) + float(_plan.offset)
	go_x(x, target_x, 0.3 if ahead < COMMIT_AHEAD else 0.45)
	if ahead < 9.0:
		shot_once("online_wall_%d" % _plan_wall)
	if ahead < 1.2:
		shot_once("online_door_%d" % _plan_wall, 0.35)

	# 待っているあいだの小さなジャンプ
	if t > _next_hop and ahead > COMMIT_AHEAD and ahead < 24.0 and absf(x - target_x) < 0.8 and not gs.local_push.contact:
		_next_hop = t + rng.randf_range(2.2, 5.5)
		if rng.randf() < 0.6:
			tap(KEY_SPACE, 0.08)


func _make_plan(index: int) -> void:
	# 前の壁の結果（HP が減っていなければ正解）
	var was_right := _plan_wall >= 0 and _my_hp() >= _hp_before
	var previous := _plan_wall
	if previous >= 0:
		(report.walls as Array).append({"wall": previous, "right": was_right, "door": _plan.door, "t": snappedf(_wall_t, 0.01)})
	_plan_wall = index
	_wall_t = t
	_hp_before = _my_hp()
	var answer := gs.current_quiz.a
	var choices := maxi(gs.num_choices, 2)
	var wrong_walls: Array = HOST_WRONG if role == "host" else GUEST_WRONG
	var fake_walls: Array = HOST_FAKE if role == "host" else GUEST_FAKE
	var door := answer
	if index in wrong_walls:
		door = (answer + 1 + rng.randi() % (choices - 1)) % choices
	# 読む時間：問題文が長いほど長い。ゲストは少しゆっくり
	var read := rng.randf_range(1.1, 2.2) + minf(1.2, float(gs.current_quiz.q.length()) / 40.0)
	if role == "guest":
		read += 0.35
	_plan = {
		"door": door,
		"fake": -1,
		"fake_until": 0.0,
		"read": read,
		"duel": index in DUEL_WALLS,
		"offset": 0.0,
		"shift_at": t + read + rng.randf_range(1.5, 2.5),
	}
	_plan.offset = _door_offset()
	if index in fake_walls:
		_plan.fake = (door + 1 + rng.randi() % (choices - 1)) % choices
		_plan.fake_until = read + rng.randf_range(1.3, 2.1)
	_next_hop = t + read + rng.randf_range(1.5, 3.5)
	_run_until = -1.0
	_back_until = -1.0
	# 正解して抜けたあとのエモート。相手がまちがえた壁のあとは、ホストがからかう
	var emotes: Dictionary = HOST_EMOTE_AFTER if role == "host" else GUEST_EMOTE_AFTER
	if previous >= 0 and was_right and emotes.has(previous):
		_plan["emote_key"] = emotes[previous]
		_plan["emote_at"] = rng.randf_range(0.25, 0.6)
		_plan["emote_len"] = rng.randf_range(1.5, 2.3)
		_plan.read = maxf(read, float(_plan.emote_at) + float(_plan.emote_len) + 0.3)
		_plan.shift_at = t + float(_plan.read) + rng.randf_range(1.5, 2.5)


## ドアの中で立つ位置（中心からのずれ）。2 人が同じドアに入れるよう、ホストとゲストで左右に分ける。
func _door_offset() -> float:
	var half: float = gs.tuning.door4_half_width if gs.num_choices == 4 else gs.tuning.door_half_width
	var side := 1.0 if role == "host" else -1.0
	# 体の幅は 1.24。中心から 0.64 以上はなれて立てば、2 人が並んでもドアの中に収まる
	return side * rng.randf_range(0.64, maxf(0.7, half - 0.72))


func _door_x(door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[clampi(door, 0, 3)]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x


## 押し合い：相手へ歩いていき、体が当たったら「押しっぱなし → 離して押し直す」で肩をぶつける。
func _duel(x: float) -> void:
	# 前後がずれていると体が当たらないので、相手の横へ並ぶ
	var dz := _their_z() - _my_z()
	var local_z := _my_z() - gs.world_scroll_z
	hold(KEY_W, dz > 0.45 and local_z < 5.0)
	hold(KEY_S, dz < -0.45 and local_z > -4.0)
	var toward := 1 if _their_x() > x else -1
	if not gs.local_push.contact:
		set_lateral(toward)
		_strike_t = t
		return
	shot_once("online_push_%d" % _plan_wall, 0.5)
	var phase := t - _strike_t
	if phase >= _strike_hold + _strike_gap:
		_strike_t = t
		_strike_hold = rng.randf_range(0.2, 0.36)
		_strike_gap = rng.randf_range(0.07, 0.12)
		phase = 0.0
	set_lateral(toward if phase < _strike_hold else 0)


## ゴールまでの競走：前へ走り、左右にふらつき、ときどき跳ぶ。着いたらエモート。
func _goal_race() -> void:
	if _goal_t < 0.0:
		_goal_t = t
		shot_once("online_goal_race", 1.5)
	hold(KEY_S, false)
	if not _alive():
		set_lateral(0)
		hold(KEY_W, false)
		return
	if gs.has_player_reached_goal(mine):
		hold(KEY_W, false)
		set_lateral(0)
		if not _goal_emoted:
			_goal_emoted = true
			tap(KEY_3 if role == "host" else KEY_1, 0.15)
		return
	hold(KEY_W, t - _goal_t > (0.25 if role == "host" else 0.5))
	if t > _goal_weave_until:
		_goal_weave_until = t + rng.randf_range(0.35, 0.9)
		_goal_weave_dir = [0, 0, 1, -1][rng.randi() % 4]
		if absf(_my_x()) > 4.0:
			_goal_weave_dir = -1 if _my_x() > 0.0 else 1
		if rng.randf() < 0.3:
			tap(KEY_SPACE, 0.08)
	set_lateral(_goal_weave_dir)
