class_name SkyGateGame
extends SuddenDeathGame

## サドンデス「つきやぶれ！スカイゲート」のルール（docs/sudden_death_v2/sky_gate.md 第2・3・8章、
## skygate_build_plan.md 1.1節・4.5節）。判定は全部ここ（見せ方 SkyGatePresenter は判定しない）。
##
## 2人は落ちながら空中を前後左右に動き、下から近づく問題のボード（2×2 の4択の紙のパネル）の、正しいパネルの上へ行く。
## ゲートの時刻（時間切れ。ボードが2人に届いた瞬間）に体の中心の真下にあるパネルが答え。そこで位置を止めて gate_impact を出し、
## 見せ方が「つき破る」動き（正解は紙を破って抜ける。まちがいは破れずにはね返されて爆散）を IMPACT_TIME 秒見せたあとで
## 判定（gate_pass・out・decided・both_out）を出す。正解は次のゲート、まちがいはアウト（相手が残れば相手の勝ち）。
## 2人とも同じゲートでアウトなら、その場で復活（1.0 秒）して次のゲートから。
## 1 ラウンドはゲート 4 枚（ROUND 1：8 秒、ROUND 2：6.5 秒・ボードが横へ動く、ROUND 3 以降：5 秒・ボードが小さく動きも速い）。
## 2人とも突破したら着地台へ降りて（見せ方と監督）、begin_round() で次のラウンド。ROUND 5 のあとは着地せずに
## ゲートが1枚ずつ（5→4→3 秒、以後 3 秒）続き、3 秒のゲートで2人とも正解なら早い者勝ち（正解のパネルの上に入って、
## そのまま通過まで出なかった時刻が早い方。同じ時刻ならもう1枚）。
##
## 空中の位置（pos）はボードの座標（m）：ボードが止まっているときの中心が原点、x＝右、y＝前（ゴールの側＝ボードの奥）。
## ボードが横へ動く（ROUND 2 以降）と、ボードの中心は (board_offset(), 0) にずれる。真下のパネルはボードから見た位置で決める。
## 動ける範囲は 4 枚のパネルの外のふち（ボードの外・問題文の看板の上へは出られない）。寸法は SkyGateBoard の定数
## （PANEL_CENTERS・PANEL_SIZE）をそのまま使うので、ボードの素材が変わっても判定はボードと合う。
##
## 入力（1フレーム）：基底の辞書に "move": [P1 の Vector2, P2 の Vector2]（押しっぱなしの向き。x＝右、y＝前。長さ 0〜1）。
## 答えのキー・アクションキー（Space）は使わない。時計は TICK（1/240 秒）ずつ進めるので、30 / 60 / 120fps で同じ結果になる。

const ROUNDS := 5
const GATES_PER_ROUND := 4
## 確保する問題の数（5 ラウンド × 4 問）。足りなければ extra_question（算数の自動生成）。
const QUESTION_COUNT := ROUNDS * GATES_PER_ROUND
## 1 枚の時間（秒）：ROUND 1、2、3 以降。
const GATE_TIMES: Array[float] = [8.0, 6.5, 5.0]
## ROUND 5 のあとの1枚ずつのゲート（5 → 4 → 3 秒、以後 3 秒）。
const OVERTIME_TIMES: Array[float] = [5.0, 4.0, 3.0]
## この長さ以下のゲートで2人とも正解なら早い者勝ち。
const SPEED_GATE_TIME := 3.0
## 時間切れから判定まで：見せ方が「つき破る」動きを見せる間（skygate_impact.md。SkyGateImpact の時刻はこの中に収める）。
const IMPACT_TIME := 1.3
## 判定から次のゲートまで（通り抜けたボードが消えていくのを見せてから次へ。2026-10-19 夜：0.5 → 0.9）。
const PASS_TIME := 0.9
## 2人とも同じゲートでアウト → その場で復活するまで。
const REVIVE_TIME := 1.0
## ルールの時計の 1 刻み（秒）。どのフレームの長さでも同じ刻みで進める。
const TICK := 1.0 / 240.0

## ボードの大きさ（m）：ROUND 1・2 と、ROUND 3 以降（Godot で縮める。前の 14 × 10 → 10 × 7 と同じ割合）。
const BOARD_SIZE := Vector2(17.0, 12.2)
const SMALL_BOARD_SIZE := Vector2(12.2, 8.6)
const SMALL_FROM_ROUND := 3
## ボードが横へ動く（ROUND 2 から）：[振れ幅 m, 周期 秒]。ROUND 3 以降は小さく速く。
const SWAY_FROM_ROUND := 2
const SWAY_ROUND_2 := Vector2(2.0, 4.4)
const SWAY_LATER := Vector2(1.6, 3.0)

## 動く速さ：ボードの端から端（17 m）を約 1.7 秒。押すと ACCEL、離すと BRAKE（1/秒）でその速さへ寄る（ふわっと止まる）。
const MOVE_SPEED := 10.0
const ACCEL := 9.0
const BRAKE := 11.0
## 2人の体の中心はこれより近づかない（軽く押し合う）。
const BODY_GAP := 1.2
## 体の中心は、パネルの外のふちからこれだけ内側までしか行けない。
const EDGE_MARGIN := 0.3
## ラウンドの頭の位置（ボードの座標、縮める前の値。P1 が左）。
const SPAWN_X := 2.0

## "idle"（導入）、"gate"（動いて選ぶ）、"impact"（時間切れ。つき破る動きを見せる間、判定はまだ出さない）、
## "pass"（判定のあと）、"both_out"（2人ともアウト → 復活まで）、"landing"（2人とも突破 → 着地台へ。begin_round() を待つ）、"decided"
var phase := "idle"
## 今のラウンド（1〜5。ROUND 5 のあとの1枚ずつのゲートも 5 のまま、overtime が true）。
var current_round := 0
## ラウンドの中のゲートの番号（0〜3。ROUND 5 のあとは 4, 5, 6…と続く）。
var gate_index := -1
## このゲートの時間（秒）。
var gate_time := 0.0
var overtime := false
## 1枚ずつのゲートの何枚目か（0 から）。
var overtime_count := 0
## 時計（刻み）。phase_ticks は今の段階の頭から、ticks は始めてから。
var phase_ticks := 0
var phase_length := 0
var ticks := 0
## 空中の位置・速さ（ボードの座標、m）と押している向き [P1, P2]。
var pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var vel: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var move: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## 今の真下のパネル（-1 = ボードの外）と、そのパネルに入った刻み（ゲートの頭から。同じパネルの上にいる間は変えない）。
var under: Array[int] = [-1, -1]
var under_tick: Array[int] = [0, 0]
## 最後のゲートの結果 "burst" / "boom"（ゲートの間は ""。時間切れ（impact）で決まり、判定はそのあと）。
var results: Array[String] = ["", ""]
## 決着したゲートでアウトになった人（0 = なし）。
var loser := 0
## 数（記録）：つき破った枚数、ドカンの回数、2人ともアウトで復活した回数。
var passes: Array[int] = [0, 0]
var booms: Array[int] = [0, 0]
var revives := 0
## 早い者勝ちで決まったときの入った時刻（秒）。
var speed_times: Array[float] = [-1.0, -1.0]

var _acc := 0.0
var _sway := Vector3.ZERO  # 振れ幅・周期・位相
var _sway_t := 0.0
var _accel_k := 0.0
var _brake_k := 0.0


func _init() -> void:
	kind = "sky_gate"
	_accel_k = 1.0 - exp(-ACCEL * TICK)
	_brake_k = 1.0 - exp(-BRAKE * TICK)


func setup(questions: Array[QuizItem], seed_value: int) -> void:
	super.setup(questions, seed_value)
	phase = "idle"
	current_round = 0
	gate_index = -1
	gate_time = 0.0
	overtime = false
	overtime_count = 0
	phase_ticks = 0
	phase_length = 0
	ticks = 0
	passes = [0, 0]
	booms = [0, 0]
	revives = 0
	loser = 0
	speed_times = [-1.0, -1.0]
	results = ["", ""]
	move = [Vector2.ZERO, Vector2.ZERO]
	_acc = 0.0
	_sway = Vector3.ZERO
	_sway_t = 0.0
	_reset_positions()


## カウントダウンが終わった：ROUND 1 の1枚目。
func start() -> void:
	super.start()
	_begin_round(1)


## 2人とも突破して着地台へ降りたあと、見せ方（監督の降下が終わったところ）が次のラウンドを始める。true = 始めた。
func begin_round() -> bool:
	if phase != "landing" or finished:
		return false
	_begin_round(current_round + 1)
	return true


## 次のラウンドのカウントダウンの間（着地のあと、begin_round() の前）：2人を次のラウンドの頭の位置に置く。時計は動かさない。
func place_for_next_round() -> void:
	if phase != "landing" or finished:
		return
	var size := SMALL_BOARD_SIZE if current_round + 1 >= SMALL_FROM_ROUND else BOARD_SIZE
	for slot: int in [0, 1]:
		pos[slot] = spawn_point(slot + 1, size / BOARD_SIZE)
		vel[slot] = Vector2.ZERO
	under = [-1, -1]
	under_tick = [0, 0]


## 一時停止はルールの時計を止めるだけ（step が呼ばれない）。押している向きは離したことにする。
func interrupt() -> void:
	move = [Vector2.ZERO, Vector2.ZERO]


## 1フレーム進める。押している向きはフレームの間ずっと同じとみなし、TICK ずつ進める。
func step(dt: float, input: Dictionary) -> void:
	if waiting_for_start or finished:
		return
	var moves: Array = input.get("move", [])
	for slot: int in [0, 1]:
		var m: Vector2 = moves[slot] if slot < moves.size() and moves[slot] is Vector2 else Vector2.ZERO
		move[slot] = m.limit_length(1.0)
	_acc += maxf(dt, 0.0)
	# 浮動小数の誤差で 1 刻み足りなくならないよう、ごく小さい余裕をみる
	while _acc >= TICK - 0.000001 and not finished:
		_acc -= TICK
		_tick()
	_acc = maxf(_acc, 0.0)


## 動いて選んでいる（HUD・見せ方の傾き）。
func is_steering() -> bool:
	return phase == "gate" and not finished


## ゲートの頭からの秒。
func gate_clock() -> float:
	if phase == "gate":
		return float(phase_ticks) * TICK
	return gate_time


## ゲートの残り（0〜1）。
func time_left_ratio() -> float:
	if phase != "gate" or phase_length <= 0:
		return 0.0
	return clampf(1.0 - float(phase_ticks) / float(phase_length), 0.0, 1.0)


func time_left() -> float:
	return time_left_ratio() * gate_time


## 今の段階の頭からの秒（見せ方のスロー・復活の進み）。
func phase_clock() -> float:
	return float(phase_ticks) * TICK


func correct_choice() -> int:
	var quiz := current_quiz()
	return quiz.a if quiz != null else -1


## 今のラウンドのボードの大きさ（m）と、縮める割合（素材の 14 × 10 m に対して）。
func board_size() -> Vector2:
	return SMALL_BOARD_SIZE if current_round >= SMALL_FROM_ROUND or overtime else BOARD_SIZE


func board_scale() -> Vector2:
	return board_size() / BOARD_SIZE


## ボードの中心の横のずれ（m、x）。ゲートの間は時計で動き、通りすぎたあとはその位置のまま。
func board_offset() -> float:
	if _sway.x <= 0.0:
		return 0.0
	return _sway.x * sin(TAU * _sway_t / _sway.y + _sway.z)


## ボードの横の速さ（m/秒。見せ方のドローンの傾き）。
func board_velocity() -> float:
	if _sway.x <= 0.0 or phase != "gate":
		return 0.0
	return _sway.x * TAU / _sway.y * cos(TAU * _sway_t / _sway.y + _sway.z)


## プレイヤー（0 / 1）のボードから見た位置（m、縮める前の値。SkyGateBoard.board_point にそのまま渡せる）。
func local_point(slot: int) -> Vector2:
	return to_local(pos[clampi(slot, 0, 1)])


func to_local(p: Vector2) -> Vector2:
	return (p - Vector2(board_offset(), 0.0)) / board_scale()


## 動ける範囲（ボードの座標、m）。
func play_rect() -> Rect2:
	var local := panels_rect()
	var s := board_scale()
	var r := Rect2(local.position * s + Vector2(board_offset(), 0.0), local.size * s)
	return r.grow(-EDGE_MARGIN)


## 4 枚のパネルを囲む四角（縮める前のボードの座標）。
static func panels_rect() -> Rect2:
	var r := SkyGateBoard.panel_rect(0)
	for i in range(1, SkyGateBoard.PANEL_COUNT):
		r = r.merge(SkyGateBoard.panel_rect(i))
	return r


## 縮める前のボードの座標の点の真下のパネル。パネルの間の仕切りの上なら一番近いパネル、パネルの外のふちより外は -1。
static func panel_for_local(local: Vector2) -> int:
	var hit := SkyGateBoard.panel_at(local)
	if hit >= 0:
		return hit
	if not panels_rect().has_point(local):
		return -1
	var best := -1
	var best_d := INF
	for i in range(SkyGateBoard.PANEL_COUNT):
		var r := SkyGateBoard.panel_rect(i)
		var nearest := Vector2(clampf(local.x, r.position.x, r.end.x), clampf(local.y, r.position.y, r.end.y))
		var d := local.distance_squared_to(nearest)
		if d < best_d - 0.0000001:
			best_d = d
			best = i
	return best


## ラウンドの頭の位置（ボードの座標、m）。P1 が左。
static func spawn_point(player: int, scale := Vector2.ONE) -> Vector2:
	var center := panels_rect().get_center()
	return Vector2(SPAWN_X * (-1.0 if player == 1 else 1.0), center.y) * scale


func record() -> Dictionary:
	var data := super.record()
	data["detail"] = {"round": current_round, "gate": gate_index, "overtime": overtime, "passes": passes.duplicate(),
		"booms": booms.duplicate(), "revives": revives, "speed_times": speed_times.duplicate()}
	return data


func get_debug_snapshot() -> Dictionary:
	var data := super.get_debug_snapshot()
	data.merge({"phase": phase, "round": current_round, "gate": gate_index, "gate_time": gate_time, "overtime": overtime,
		"clock": snappedf(gate_clock(), 0.0001), "ticks": ticks,
		"pos": [[snappedf(pos[0].x, 0.0001), snappedf(pos[0].y, 0.0001)], [snappedf(pos[1].x, 0.0001), snappedf(pos[1].y, 0.0001)]],
		"under": under.duplicate(), "under_tick": under_tick.duplicate(), "results": results.duplicate(),
		"offset": snappedf(board_offset(), 0.0001), "loser": loser}, true)
	return data


# ------------------------------------------------------------------ the clock

func _tick() -> void:
	ticks += 1
	match phase:
		"gate":
			phase_ticks += 1
			_sway_t = float(phase_ticks) * TICK
			_move_players()
			_track_under()
			if phase_ticks >= phase_length:
				_impact()
		"impact":
			phase_ticks += 1
			if phase_ticks >= phase_length:
				_judge()
		"pass":
			phase_ticks += 1
			if phase_ticks >= phase_length:
				_after_gate()
		"both_out":
			phase_ticks += 1
			if phase_ticks >= phase_length:
				_emit("revive", {"index": gate_index, "round": current_round})
				_after_gate()


func _set_phase(next: String, seconds := 0.0) -> void:
	phase = next
	phase_ticks = 0
	phase_length = maxi(round_to_ticks(seconds), 0)


static func round_to_ticks(seconds: float) -> int:
	return int(roundf(seconds / TICK))


# ------------------------------------------------------------------ rounds and gates

func _begin_round(number: int) -> void:
	current_round = number
	gate_index = -1
	_sway = Vector3.ZERO
	_sway_t = 0.0
	_reset_positions()
	_emit("round_start", {"round": current_round, "gates": GATES_PER_ROUND, "gate_time": _round_gate_time(),
		"board_size": board_size()})
	_next_gate()


func _round_gate_time() -> float:
	return GATE_TIMES[clampi(current_round - 1, 0, GATE_TIMES.size() - 1)]


func _next_gate() -> void:
	gate_index += 1
	if overtime:
		gate_time = OVERTIME_TIMES[mini(overtime_count, OVERTIME_TIMES.size() - 1)]
		overtime_count += 1
	else:
		gate_time = _round_gate_time()
	_next_quiz()
	_start_sway()
	results = ["", ""]
	_set_phase("gate", gate_time)
	under = [-1, -1]
	_track_under()
	var quiz := current_quiz()
	var choices: Array = []
	if quiz != null:
		for choice: String in quiz.c:
			choices.append(choice)
	_emit("gate", {"round": current_round, "index": gate_index, "question": quiz.q if quiz != null else "",
		"choices": choices, "correct": correct_choice(), "time": gate_time, "overtime": overtime,
		"board_size": board_size()})


## ボードが横へ動く：前のゲートの最後のずれから続ける（向きはランダム）。ROUND 1 は動かない。
func _start_sway() -> void:
	var previous := board_offset()
	_sway_t = 0.0
	if current_round < SWAY_FROM_ROUND and not overtime:
		_sway = Vector3.ZERO
		return
	var params := SWAY_ROUND_2 if current_round == SWAY_FROM_ROUND and not overtime else SWAY_LATER
	var start := asin(clampf(previous / params.x, -1.0, 1.0))
	if rng.randf() < 0.5:
		start = PI - start
	_sway = Vector3(params.x, params.y, start)


func _start_overtime() -> void:
	overtime = true
	overtime_count = 0
	_emit("overtime", {"gate_time": OVERTIME_TIMES[0], "round": current_round})
	_next_gate()


func _reset_positions() -> void:
	for slot: int in [0, 1]:
		pos[slot] = spawn_point(slot + 1, board_scale())
		vel[slot] = Vector2.ZERO
	under = [-1, -1]
	under_tick = [0, 0]


# ------------------------------------------------------------------ moving in the air

func _move_players() -> void:
	for slot: int in [0, 1]:
		var target := move[slot] * MOVE_SPEED
		var k := _accel_k if move[slot].length_squared() > 0.0001 else _brake_k
		vel[slot] += (target - vel[slot]) * k
		pos[slot] += vel[slot] * TICK
	var area := play_rect()
	for _pass in range(2):
		_clamp(area)
		_push_apart()
	_clamp(area)


func _clamp(area: Rect2) -> void:
	for slot: int in [0, 1]:
		var p := pos[slot]
		var q := Vector2(clampf(p.x, area.position.x, area.end.x), clampf(p.y, area.position.y, area.end.y))
		if q.x != p.x:
			vel[slot].x = 0.0
		if q.y != p.y:
			vel[slot].y = 0.0
		pos[slot] = q


## 2人の体が重ならないよう、半分ずつ押し戻す。近づく向きの速さも半分ずつ消す（軽く押し合う）。
func _push_apart() -> void:
	var d := pos[1] - pos[0]
	var dist := d.length()
	if dist >= BODY_GAP:
		return
	# ぴったり重なったときは P1 を左へ（P1 は画面の左）
	var n := d / dist if dist > 0.000001 else Vector2.RIGHT
	var push := (BODY_GAP - dist) * 0.5
	pos[0] -= n * push
	pos[1] += n * push
	var closing := (vel[1] - vel[0]).dot(n)
	if closing < 0.0:
		vel[0] += n * closing * 0.5
		vel[1] -= n * closing * 0.5


func _track_under() -> void:
	for slot: int in [0, 1]:
		var panel := panel_for_local(local_point(slot))
		if panel != under[slot]:
			under[slot] = panel
			under_tick[slot] = phase_ticks


# ------------------------------------------------------------------ the gate

## 時間切れ：位置を止めて、真下のパネルで正解かどうかを決める（判定を出すのは IMPACT_TIME のあとの _judge）。
## gate_impact は見せ方が「つき破る」動き（正解は紙を破って抜ける、まちがいは破れずにはね返されて爆散）を始める合図。
func _impact() -> void:
	_track_under()
	var answer := correct_choice()
	for slot: int in [0, 1]:
		results[slot] = "burst" if under[slot] >= 0 and under[slot] == answer else "boom"
		vel[slot] = Vector2.ZERO
		move[slot] = Vector2.ZERO
	_emit("gate_impact", _gate_result(answer))
	_set_phase("impact", IMPACT_TIME)


func _gate_result(answer: int) -> Dictionary:
	return {"round": current_round, "index": gate_index, "panels": under.duplicate(), "results": results.duplicate(),
		"correct": answer, "local": [local_point(0), local_point(1)], "since": [float(under_tick[0]) * TICK, float(under_tick[1]) * TICK],
		"overtime": overtime}


## つき破る動きを見せ終えた：判定を出す（中身は時間切れで止めた位置のまま）。
func _judge() -> void:
	var answer := correct_choice()
	var outs: Array[int] = []
	for slot: int in [0, 1]:
		if results[slot] == "burst":
			passes[slot] += 1
		else:
			booms[slot] += 1
			outs.append(slot)
	_emit("gate_pass", _gate_result(answer))
	if outs.size() == 1:
		loser = outs[0] + 1
		_emit("out", {"player": loser, "index": gate_index, "round": current_round})
		_decide(3 - loser, "out")
		return
	if outs.size() == 2:
		revives += 1
		_set_phase("both_out", REVIVE_TIME)
		_emit("both_out", {"index": gate_index, "round": current_round})
		return
	if overtime and gate_time <= SPEED_GATE_TIME + 0.0001 and under_tick[0] != under_tick[1]:
		# 早い者勝ち：正解のパネルに入ってそのまま通過した時刻が早い方。同じ刻みならもう1枚。
		speed_times = [float(under_tick[0]) * TICK, float(under_tick[1]) * TICK]
		_decide(1 if under_tick[0] < under_tick[1] else 2, "speed")
		return
	_set_phase("pass", PASS_TIME)


## 通りすぎた（または2人とも復活した）あと：次のゲート、ラウンドの終わり、ROUND 5 のあとの1枚ずつのゲート。
func _after_gate() -> void:
	if overtime or gate_index < GATES_PER_ROUND - 1:
		_next_gate()
		return
	if current_round >= ROUNDS:
		_start_overtime()
		return
	_set_phase("landing")
	_emit("round_clear", {"round": current_round})


func _decide(player: int, by: String) -> void:
	winner = player
	decided_by = by
	_set_phase("decided")
	finished = true
	_emit("decided", {"winner": winner, "by": by, "round": current_round, "index": gate_index, "overtime": overtime,
		"times": speed_times.duplicate()})
