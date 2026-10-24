extends "res://tests/pv_capture/pv_take_base.gd"

## PV S21「決着はスコアタワー」：ローカル 2P・10 問の回のスコアタワーの結果発表を、本物の GameWorld で撮る（10 拍）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s21 quality=ultra sub=8
## テロップ「決着は、スコアタワーで」は After Effects（レーン 6）で重ねる。
## 下敷きは tests/result_ceremony_runtime.gd（10 問を終えてゴールへ → 結果発表）。カメラ・HUD（得点の式と WIN!）・効果音はゲームのまま。
##
## 中身：P1 は正解 8・残り HP 2 → 8 ×（2 + 0.5）= 20.0、P2 は正解 9・残り HP 1 → 9 ×（1 + 0.5）= 13.5。
## 正解は P2 のほうが多いが、残った HP で P1 が勝つ（得点の式の意味が 1 枚で分かる）。引き分けはデバッグ版ではサドンデスへ
## 進むので避け、念のためサドンデスも切る（gs.sudden_death_enabled = false）。
##
## 流れ（結果発表の時刻 g。ゲームの演出は 11.2 秒）を 10 拍（4.69 秒）に収める。時間の速さを変えるだけで、間は切らない:
##   PV 0      g = G0（3.0）   得点の式のカード（正解数 8・9 が出ている）
##   〜 1.0 秒  等速          残り HP と「+0.5」が出て、2.5・1.5 に合体（3.3〜3.92）
##   〜 p2     早回し約 2 倍  ドラムロールでタワーがせり上がる（4.1〜6.3）。前後は RAMP 秒でなめらかに速さを変える
##   p2 〜     等速          静まって（6.55〜）、6 拍目の頭で WIN!（6.9）
##   6 拍目〜   1.25 倍        紙吹雪・王冠（7.3〜7.66）、負けた P2 のタワーが沈み、観客席の荒くれが P2 へ卵を投げる（最初の命中 9.15）
## 引数（共通のほかに）:
##   measure          等速で G0 から 10 秒回し、卵が飛ぶ時刻などを report に書く（速さを決めるための下調べ）
##   g0=<秒>  verdict_beat=<拍>  after=<倍>   早回しの決め方を試す

const S21_BEATS := 10.0
const HANDLE_FRAMES := 4

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const P1_EMOTES: Array[int] = [2, 7, 13]        # 勝った P1 はタワーの上でカンナムスタイル
const P2_EMOTES: Array[int] = [17, 19, 15]
const DAY_PHASE := 0.25

## [正解数, 残り HP]
const P1_RESULT := [8, 2]
const P2_RESULT := [9, 1]

## 時間の速さ（上の注記）
const G0 := 3.0                 # PV の頭の結果発表の時刻（正解数が出そろい、HP が出る直前）
const FAST_FROM := 1.0          # PV のこの秒まで等速（HP・「+0.5」・2.5 への合体 3.92 を見せる）
const RAMP := 0.3               # 速さを変える長さ（PV 秒）
const G_SLOW := 6.55            # ここで等速に戻る（タワーが止まった後の静けさ）
const VERDICT_BEAT := 5.5       # WIN! を S21 の 5.5 拍目の頭に（前半 5 拍のテロップが消えてから）
const AFTER_SPEED := 1.25       # WIN! のあとの速さ（王冠・沈むタワー・最初の卵が P2 に当たるまでを 4 拍に）
## 卵：投げる時刻は観客席の乱数で決まり、画質・刻み・速さで変わる。そこで、最初の「当たる卵」が投げられた時点で、
## その卵が HIT_FRAME に P2 へ当たるよう残りの速さを決め直す（ADAPT_RAMP 秒でなめらかに。範囲は ADAPT_LIMIT）
const HIT_FRAME := 276
const ADAPT_RAMP := 0.25
const ADAPT_LIMIT := Vector2(0.8, 2.0)

var gs: QuizGameState
var world: Node
var pc: PlayerController
var director: Node
var stand: Node
var hud: CanvasLayer
var helper: Node
var measure := false
var g0 := G0
var verdict_beat := VERDICT_BEAT
var after_speed := AFTER_SPEED
var g0_actual := 0.0
var speed_v := 1.0
var p2_end := 0.0
var _trace: Array = []
var _events := {}
var _eggs := []                 # [PV フレーム, 結果発表の時刻, 投げた数, 当たった数]
var _last_eggs := [0, 0]
var _adapt_from := -1.0         # 決め直した PV の秒（-1 = まだ）
var _adapt_g := 0.0
var _adapt_s0 := 1.0
var _adapt_s := 1.0
var _adapt_info := {}


func _init() -> void:
	take_name = "s21"


func _default_frames() -> int:
	if measure:
		return 600
	return bf(S21_BEATS) - 1 + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg == "measure":
		measure = true
	elif arg.begins_with("g0="):
		g0 = float(arg.trim_prefix("g0="))
	elif arg.begins_with("verdict_beat="):
		verdict_beat = float(arg.trim_prefix("verdict_beat="))
	elif arg.begins_with("after="):
		after_speed = float(arg.trim_prefix("after="))


func _setup() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	gs.sudden_death_enabled = false
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
	gs.p1_hat = P1_HAT
	gs.p2_hat = P2_HAT
	gs.p1_emote_slots = P1_EMOTES.duplicate()
	gs.p2_emote_slots = P2_EMOTES.duplicate()
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	QuizManager.game_state = gs
	world = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	pc = world.get_node("Player") as PlayerController
	pc.prepare_for_loading(gs)
	await _frames(60)
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	world.call("_clear_preview_walls")
	# 10 問を終えたところ（ゲームと同じく、10 問目の次でゴールへの走りになる）
	gs.score = P1_RESULT[0]
	gs.player2_score = P2_RESULT[0]
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	if gs.game_state != Constants.STATE_GOAL_RACE:
		failures.append("10 問を終えてもゴールへの走りにならない（%s）" % gs.game_state)
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await _frames(15)
	# 2 人がゴールの手前に並ぶ（P1 が少し先にゴール）
	gs.player_x = 2.2
	gs.player2_x = -2.2
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_hp = P1_RESULT[1]
	gs.p2_hp = P2_RESULT[1]
	gs.player_z = gs.goal_z - 1.6
	gs.player2_z = gs.goal_z - 0.3
	director = world.get("_result_ceremony_director")
	stand = world.get("_goal_stand")
	hud = world.get_node_or_null("GameplayHUD") as CanvasLayer
	var keep: Array[CanvasLayer] = []
	if hud != null:
		keep.append(hud)
	hide_overlays(keep)
	# 結果発表の G0 秒まで回す（撮らない）。1/60 秒刻み（sub によらず同じ）で回してから、最後は撮影の刻みで寄せる
	var fast := float(sub)
	for i in range(60 * 60):
		var elapsed := gs.result_ceremony_elapsed if gs.result_presentation_active else -1.0
		if elapsed >= g0 - 0.35:
			break
		Engine.time_scale = fast
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await get_tree().process_frame          # 速いままの最後の更新を流す
	for i in range(60 * 8 * 4):
		if gs.result_presentation_active and gs.result_ceremony_elapsed >= g0 - 0.5 / (FPS * sub):
			break
		await get_tree().process_frame
	if not gs.result_presentation_active:
		failures.append("結果発表が始まらない")
	g0_actual = gs.result_ceremony_elapsed
	_plan_speed()
	report["plan"] = {"g0": g0, "g0_actual": snappedf(g0_actual, 0.0001), "fast_from": FAST_FROM, "ramp": RAMP, "g_slow": G_SLOW,
		"speed": snappedf(speed_v, 0.001), "slow_from_pv": snappedf(p2_end, 0.0001), "verdict_beat": verdict_beat,
		"after_speed": after_speed, "measure": measure,
		"result": {"p1": P1_RESULT, "p2": P2_RESULT, "points_half": [gs.result_p1_score, gs.result_p2_score], "winner": gs.result_winner}}


## 早回しの速さ V を決める：WIN!（6.9）が verdict_beat の頭に来て、G_SLOW で等速に戻る
func _plan_speed() -> void:
	if measure:
		speed_v = 1.0
		p2_end = 0.0
		return
	var p_verdict := (bf(verdict_beat) - 1) / FPS
	p2_end = p_verdict - (ResultFinaleMotion.VERDICT - G_SLOW)
	var distance := G_SLOW - (g0_actual + FAST_FROM)
	var span := p2_end - FAST_FROM
	speed_v = (distance - RAMP) / (span - RAMP)
	if speed_v < 1.0 or span < 2.0 * RAMP:
		failures.append("早回しが決まらない（V = %.3f）" % speed_v)


## PV の秒 → 結果発表の秒（からの経過）。等速 → なめらかに V 倍 → なめらかに等速
func _game_time_at(pv: float) -> float:
	if measure:
		return pv
	if _adapt_from >= 0.0 and pv > _adapt_from:
		var u := pv - _adapt_from
		if u < ADAPT_RAMP:
			return _adapt_g + _adapt_s0 * u + (_adapt_s - _adapt_s0) * u * u / (2.0 * ADAPT_RAMP)
		return _adapt_g + ADAPT_RAMP * (_adapt_s0 + _adapt_s) * 0.5 + _adapt_s * (u - ADAPT_RAMP)
	return _planned_game_time_at(pv)


func _planned_game_time_at(pv: float) -> float:
	var a := FAST_FROM
	var b := p2_end
	var k := speed_v - 1.0
	if pv <= a:
		return pv
	if pv <= a + RAMP:
		var u := pv - a
		return pv + k * u * u / (2.0 * RAMP)
	var g1 := a + RAMP + k * RAMP * 0.5
	if pv <= b - RAMP:
		return g1 + speed_v * (pv - a - RAMP)
	var g2 := g1 + speed_v * (b - 2.0 * RAMP - a)
	if pv <= b:
		var u := pv - (b - RAMP)
		return g2 + speed_v * u - k * u * u / (2.0 * RAMP)
	var g3 := g2 + RAMP + k * RAMP * 0.5
	var p_verdict := b + (ResultFinaleMotion.VERDICT - G_SLOW)
	if pv <= p_verdict:
		return g3 + (pv - b)
	# WIN! から先（判定の一打と紙吹雪で速さの変わり目は見えない）
	return g3 + (p_verdict - b) + after_speed * (pv - p_verdict)


func _update(n: int, t: float, _dt: float) -> void:
	var elapsed := gs.result_ceremony_elapsed
	for beat: String in ["correct", "hp", "climb", "climb_end", "hush", "verdict", "crown_start", "crown_land", "sink_start", "dance_start", "kneel"]:
		if not _events.has(beat) and elapsed >= ResultFinaleMotion.beat(beat) - 0.00001:
			_events[beat] = n
	if stand != null and is_instance_valid(stand):
		var eggs: Variant = stand.get("eggs")
		if eggs != null:
			var now := [int(eggs.get("launched")), int(eggs.get("hits"))]
			if now != _last_eggs:
				_eggs.append([n, snappedf(elapsed, 0.001), now[0], now[1]])
				_last_eggs = now
			if not measure and _adapt_from < 0.0 and _events.has("verdict"):
				_adapt_to_first_egg(eggs, n, t)
	if (_step % sub) == 0 and (n % 4 == 1 or measure):
		_trace.append({"f": n, "t": snappedf(t, 0.0001), "g": snappedf(elapsed, 0.0001), "phase": gs.result_ceremony_phase,
			"state": gs.game_state, "ts": snappedf(Engine.time_scale, 0.001)})


## 最初の当たる卵が飛んでいたら、その卵が HIT_FRAME で当たるよう、ここから先の速さを決め直す
func _adapt_to_first_egg(eggs: Object, n: int, t: float) -> void:
	var remaining := INF
	for flight: Dictionary in eggs.get("_flights"):
		if not bool(flight.get("miss", false)):
			remaining = minf(remaining, float(flight.flight) - float(flight.age))
	if remaining == INF:
		return
	var s0 := (_game_time_at(t) - _game_time_at(t - 1.0 / (FPS * sub))) * FPS * sub
	var span := HIT_FRAME / FPS - t
	var speed := (remaining - ADAPT_RAMP * s0 * 0.5) / maxf(span - ADAPT_RAMP * 0.5, 0.05)
	speed = clampf(speed, ADAPT_LIMIT.x, ADAPT_LIMIT.y)
	_adapt_g = _game_time_at(t)
	_adapt_s0 = s0
	_adapt_s = speed
	_adapt_from = t
	_adapt_info = {"frame": n, "egg_remaining": snappedf(remaining, 0.001), "speed_before": snappedf(s0, 0.001), "speed": snappedf(speed, 0.001)}


func _check() -> void:
	report["cut_in_frame"] = 1                 # レーン 6 はここからカットの長さを使う（テイクの頭 = カットの頭）
	report["events"] = _events
	report["eggs"] = _eggs
	report["trace"] = _trace
	report["winner"] = gs.result_winner
	report["points_half"] = [gs.result_p1_score, gs.result_p2_score]
	report["sudden_death"] = gs.game_state == Constants.STATE_SUDDEN_DEATH or gs.sudden_death_pending
	if gs.result_winner != 1:
		failures.append("P1 が勝っていない（winner %d）" % gs.result_winner)
	if bool(report["sudden_death"]):
		failures.append("サドンデスへ進んだ")
	if measure:
		return
	var verdict_planned := bf(verdict_beat)
	if not _events.has("verdict") or absi(int(_events["verdict"]) - verdict_planned) > 1:
		failures.append("WIN! が %s（予定 %d）" % [str(_events.get("verdict", "なし")), verdict_planned])
	if not _events.has("crown_land"):
		failures.append("王冠が乗る前に終わった")
	if _eggs.is_empty():
		failures.append("卵が飛ばない")
	# 見せ場の PV フレーム（レーン 6 用）
	var highlights := {"formula_correct": _events.get("correct", -1), "hp_bonus": _events.get("hp", -1),
		"climb": _events.get("climb", -1), "towers_stop": _events.get("climb_end", -1), "win": _events.get("verdict", -1),
		"crown_land": _events.get("crown_land", -1), "loser_sinks": _events.get("sink_start", -1),
		"first_egg_thrown": _eggs[0][0] if not _eggs.is_empty() else -1}
	for e: Array in _eggs:
		if int(e[3]) > 0:
			highlights["first_egg_hit"] = e[0]
			break
	report["highlights"] = highlights
	report["egg_adapt"] = _adapt_info
	if not highlights.has("first_egg_hit") or absi(int(highlights["first_egg_hit"]) - HIT_FRAME) > 2:
		failures.append("最初の卵が P2 に当たるのが %s（予定 %d）" % [str(highlights.get("first_egg_hit", "なし")), HIT_FRAME])
	# ドラムロール（score_drum_roll）は結果発表の 2.0 秒（cast_start）に鳴り始めるので、撮影の頭より前で cues.json に入らない。
	# 編集では PV の頭に、音の頭から (g0 − 2.0) 秒のところから置き、WIN! の score_drum_finish で切る（早回しのぶん、音は長い）。
	report["audio_before_take"] = [{"cue": "score_drum_roll", "seconds_into_sound_at_frame_1": snappedf(g0_actual - ResultFinaleMotion.beat("cast_start"), 0.001),
		"cut_at_frame": highlights["win"]}]
