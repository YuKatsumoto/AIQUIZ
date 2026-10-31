class_name SkyGateGame
extends SuddenDeathGame

## サドンデス「つきやぶれ！スカイゲート」のルール（docs/sudden_death_v2/sky_gate.md 第2・3・8章、
## skygate_build_plan.md 1.1節・4.5節）。判定は全部ここ（見せ方 SkyGatePresenter は判定しない）。
##
## 2人は落ちながら空中を前後左右に動き、真下に一列に吊られた問題のボード（2×2 の4択の紙のパネル）の、正しいパネルの上へ行く。
## 時間制限は無い（2026-10-25、ユーザーの指示「最初から問題4枚が用意されていて連続で答える」）：1 ラウンドの 4 枚は最初から
## 下に並んでいて（列）、列は一定の速さで2人へ上がってくる。今のボードが2人の高さに届いた瞬間（board_depth が
## SkyGateImpact.CONTACT）に体の中心の真下にあるパネルが答え。そこで位置を止めて gate_impact を出し、見せ方が「つき破る」動きを
## 見せる間をおいて判定（gate_pass・out・decided・both_out）を出す。
##   全員が正解：列は止まらずに上がり続け、BURST_IMPACT_TIME で判定 → すぐ次のボードへ動ける。
##   まちがいがいる：列は止まり、見せ方の脱落のスロー（SkyGateImpact.wasted_scale）が判定の時刻に届くまでの実時間を待つ。
## 正解は次のボード、まちがいはアウト（相手が残れば相手の勝ち）。2人とも同じボードでアウトなら、その場で復活（1.0 秒）して次のボードから。
## ラウンドが進むほど列が速く上がる（ROUND 1：8 m/秒、ROUND 2：10 m/秒・ボードが横へ動く、ROUND 3 以降：13 m/秒・ボードが小さく
## 動きも速い）。2人とも 4 枚を突破したら着地台へ降りて（見せ方と監督）、begin_round() で次のラウンド。ROUND 5 のあとは着地せずに
## 列が下へ続き（延長。13 → 15.5 → 18 m/秒、以後 18 m/秒）、18 m/秒のボードで2人とも正解なら早い者勝ち（正解のパネルの上に入って、
## そのまま当たるまで出なかった時刻が早い方。同じ時刻ならもう1枚）。
##
## 列の k 枚目（ラウンドの頭から 0, 1, 2, 3。延長は 4, 5…と続く）の深さは board_depth(k)（落ちる点から下へ m）、問題は column_quiz(k)。
## 見せ方は始まる前（ルールカード・カウントダウン）からこれを読んで、4 枚とも問題を書いたボードを並べる。
##
## 空中の位置（pos）はボードの座標（m）：ボードが止まっているときの中心が原点、x＝右、y＝前（ゴールの側＝ボードの奥）。
## ボードが横へ動く（ROUND 2 以降）と、ボードの中心は (board_offset(), 0) にずれる（列は1つとして同じずれで揺れる）。
## 真下のパネルはボードから見た位置で決める。動ける範囲は 4 枚のパネルの外のふち（ボードの外・問題文の看板の上へは出られない）。
## 寸法は SkyGateBoard の定数（PANEL_CENTERS・PANEL_SIZE）をそのまま使うので、ボードの素材が変わっても判定はボードと合う。
##
## 入力（1フレーム）：基底の辞書に "move": [P1 の Vector2, P2 の Vector2]（押しっぱなしの向き。x＝右、y＝前。長さ 0〜1）。
## 答えのキー・アクションキー（Space）は使わない。時計は TICK（1/240 秒）ずつ進めるので、30 / 60 / 120fps で同じ結果になる。

const ROUNDS := 5
const GATES_PER_ROUND := 4
## 確保する問題の数（5 ラウンド × 4 問）。足りなければ extra_question（算数の自動生成）。
const QUESTION_COUNT := ROUNDS * GATES_PER_ROUND
## 列：ラウンドの頭の 1 枚目の深さと、ボードの間隔（m）。
const FIRST_DEPTH := 72.0
const BOARD_GAP := 64.0
## 列が上がってくる速さ（m/秒）：ROUND 1、2、3 以降。1 枚の間隔がもとの制限時間（8・6.5・5 秒）に近くなる。
const FALL_SPEEDS: Array[float] = [8.0, 10.0, 13.0]
## ROUND 5 のあとの延長のボードごとの速さ（以後は最後の値）。
const OVERTIME_SPEEDS: Array[float] = [13.0, 15.5, 18.0]
## この速さ以上のボードで2人とも正解なら早い者勝ち。
const SPEED_WIN_SPEED := 18.0
## 延長の間、今のボードの下に見せておく先のボードの数。
const OVERTIME_LOOKAHEAD := 3
## 全員が正解のとき、当たってから判定まで（位置を止める間。列は上がり続ける）。
const BURST_IMPACT_TIME := 0.3
## 2人とも同じゲートでアウト → その場で復活するまで（列は止まったまま）。
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

## "idle"（導入）、"gate"（動いて選ぶ。列が上がってくる）、"impact"（当たった。つき破る動きを見せる間、判定はまだ出さない）、
## "both_out"（2人ともアウト → 復活まで）、"landing"（2人とも突破 → 着地台へ。begin_round() を待つ）、"decided"
var phase := "idle"
## 今のラウンド（1〜5。ROUND 5 のあとの延長も 5 のまま、overtime が true）。
var current_round := 0
## 列の何枚目のボードか（ラウンドの頭から 0〜3。ROUND 5 のあとは 4, 5, 6…と続く）。
var gate_index := -1
## 今のボードの列の速さ（m/秒）。
var fall_speed := 0.0
var overtime := false
## 延長のボードの何枚目か（0 から）。
var overtime_count := 0
## 列がラウンドの頭から上がった長さ（m）と、列の 0 枚目の問題の番号（quizzes の）、列を用意したラウンド。
var column_fall := 0.0
var column_first := 0
var column_round := 0
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
## 最後のゲートの結果 "burst" / "boom"（ゲートの間は ""。当たった瞬間（impact）で決まり、判定はそのあと）。
var results: Array[String] = ["", ""]
## 当たった場合（SkyGateImpact.ALL_BURST / MIXED / ALL_BOOM）。
var impact_mode := 0
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
## 今のゲートの頭のボードの深さ（gate_progress の分母）。
var _gate_start_depth := FIRST_DEPTH


func _init() -> void:
	kind = "sky_gate"
	_accel_k = 1.0 - exp(-ACCEL * TICK)
	_brake_k = 1.0 - exp(-BRAKE * TICK)


func setup(questions: Array[QuizItem], seed_value: int) -> void:
	super.setup(questions, seed_value)
	phase = "idle"
	current_round = 0
	fall_speed = 0.0
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
	impact_mode = SkyGateImpact.ALL_BURST
	move = [Vector2.ZERO, Vector2.ZERO]
	_acc = 0.0
	# ROUND 1 の列は始まる前から見せる（ルールカード・カウントダウンの間）
	_prepare_column(1)
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


## 次のラウンドのカウントダウンの間（着地のあと、begin_round() の前）：2人を次のラウンドの頭の位置に置き、次のラウンドの列を
## 用意する（見せ方が 4 枚とも問題を書いて並べる）。時計は動かさない。
func place_for_next_round() -> void:
	if phase != "landing" or finished:
		return
	var size := SMALL_BOARD_SIZE if current_round + 1 >= SMALL_FROM_ROUND else BOARD_SIZE
	for slot: int in [0, 1]:
		pos[slot] = spawn_point(slot + 1, size / BOARD_SIZE)
		vel[slot] = Vector2.ZERO
	under = [-1, -1]
	under_tick = [0, 0]
	if column_round != current_round + 1:
		_prepare_column(current_round + 1)


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


## ゲートの頭（前のボードの判定のあと）からの秒。ゲートの間でなければ 0。
func gate_clock() -> float:
	if phase == "gate":
		return float(phase_ticks) * TICK
	return 0.0


## 今の段階の頭からの秒（見せ方のスロー・復活の進み）。
func phase_clock() -> float:
	return float(phase_ticks) * TICK


## 列の k 枚目のボードの紙の面の深さ（落ちる点から下へ m。上へ抜けたら負）。
func board_depth(k: int) -> float:
	return FIRST_DEPTH + float(k) * BOARD_GAP - column_fall


## 今の列に並べるボードの数（列の 0 枚目から）。延長の間は今のボードの下に OVERTIME_LOOKAHEAD 枚まで続ける。
func board_count() -> int:
	if overtime:
		return gate_index + 1 + OVERTIME_LOOKAHEAD
	return GATES_PER_ROUND


## 列の k 枚目の問題。quizzes を番号で読む（始まる前に問題が差し替わっても追いつく）。足りなければ extra_question で足す。
func column_quiz(k: int) -> QuizItem:
	var index := column_first + k
	if not _ensure_quiz(index):
		return quizzes.back() if not quizzes.is_empty() else null
	return quizzes[index]


## 今のボードへの近づき（0 = ゲートの頭、1 = 当たる）。ゲートの間でなければ 1（まだ始まっていなければ 0）。
func gate_progress() -> float:
	if gate_index < 0:
		return 0.0
	if phase != "gate":
		return 1.0
	var span := maxf(_gate_start_depth - SkyGateImpact.CONTACT, 0.001)
	return clampf(1.0 - (board_depth(gate_index) - SkyGateImpact.CONTACT) / span, 0.0, 1.0)


## 今のボードに当たるまでの秒（列がこのままの速さで上がるとして）。ゲートの間でなければ 0。
func time_to_contact() -> float:
	if phase != "gate" or gate_index < 0:
		return 0.0
	return maxf(board_depth(gate_index) - SkyGateImpact.CONTACT, 0.0) / maxf(fall_speed, 0.001)


func correct_choice() -> int:
	var quiz := current_quiz()
	return quiz.a if quiz != null else -1


## 今のラウンドのボードの大きさ（m）と、縮める割合（素材の 14 × 10 m に対して）。
func board_size() -> Vector2:
	return SMALL_BOARD_SIZE if current_round >= SMALL_FROM_ROUND or overtime else BOARD_SIZE


func board_scale() -> Vector2:
	return board_size() / BOARD_SIZE


## ボードの中心の横のずれ（m、x）。ゲートの間は時計で動き、当たったあとはその位置のまま。
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


## ラウンドの列の速さ（m/秒）。
static func round_speed(round_number: int) -> float:
	return FALL_SPEEDS[clampi(round_number - 1, 0, FALL_SPEEDS.size() - 1)]


func record() -> Dictionary:
	var data := super.record()
	data["detail"] = {"round": current_round, "gate": gate_index, "overtime": overtime, "passes": passes.duplicate(),
		"booms": booms.duplicate(), "revives": revives, "speed_times": speed_times.duplicate()}
	return data


func get_debug_snapshot() -> Dictionary:
	var data := super.get_debug_snapshot()
	data.merge({"phase": phase, "round": current_round, "gate": gate_index, "speed": fall_speed, "overtime": overtime,
		"clock": snappedf(gate_clock(), 0.0001), "ticks": ticks, "fall": snappedf(column_fall, 0.0001),
		"depth": snappedf(board_depth(maxi(gate_index, 0)), 0.0001),
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
			column_fall += fall_speed * TICK
			_move_players()
			_track_under()
			var contact := FIRST_DEPTH + float(gate_index) * BOARD_GAP - SkyGateImpact.CONTACT
			if column_fall >= contact - 0.000001:
				# 当たった刻み：はみ出した分は戻して、ちょうど紙に触れる深さにする
				column_fall = contact
				_impact()
		"impact":
			phase_ticks += 1
			if impact_mode == SkyGateImpact.ALL_BURST:
				# 全員がつき破った：列は止まらずに上がり続ける（減速せずに突破）
				column_fall += fall_speed * TICK
			if phase_ticks >= phase_length:
				_judge()
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

## ラウンドの列を用意する：列の 0 枚目は次に使う問題。列は頭の深さへ戻す。
func _prepare_column(round_number: int) -> void:
	column_round = round_number
	column_first = question_index + 1
	column_fall = 0.0
	gate_index = -1
	_sway = Vector3.ZERO
	_sway_t = 0.0
	_gate_start_depth = FIRST_DEPTH


func _begin_round(number: int) -> void:
	current_round = number
	if column_round != number:
		_prepare_column(number)
	_reset_positions()
	var questions: Array = []
	for k in range(GATES_PER_ROUND):
		questions.append(_quiz_event(column_quiz(k)))
	_emit("round_start", {"round": current_round, "gates": GATES_PER_ROUND, "speed": round_speed(current_round),
		"gap": BOARD_GAP, "first_depth": FIRST_DEPTH, "board_size": board_size(), "questions": questions})
	_next_gate()


func _quiz_event(quiz: QuizItem) -> Dictionary:
	var choices: Array = []
	if quiz != null:
		for choice: String in quiz.c:
			choices.append(choice)
	return {"question": quiz.q if quiz != null else "", "choices": choices, "correct": quiz.a if quiz != null else -1}


## 用意した問題に index 番が無ければ extra_question で足す。足せなければ false。
func _ensure_quiz(index: int) -> bool:
	while quizzes.size() <= index:
		var extra: QuizItem = extra_question.call() if extra_question.is_valid() else null
		if extra == null:
			return false
		quizzes.append(extra)
	return true


func _next_gate() -> void:
	gate_index += 1
	if overtime:
		fall_speed = OVERTIME_SPEEDS[mini(overtime_count, OVERTIME_SPEEDS.size() - 1)]
		overtime_count += 1
	else:
		fall_speed = round_speed(current_round)
	question_index = column_first + gate_index
	if not _ensure_quiz(question_index):
		question_index = quizzes.size() - 1
	_start_sway()
	results = ["", ""]
	_set_phase("gate")
	_gate_start_depth = board_depth(gate_index)
	under = [-1, -1]
	_track_under()
	var data := _quiz_event(current_quiz())
	data.merge({"round": current_round, "index": gate_index, "depth": _gate_start_depth, "speed": fall_speed,
		"overtime": overtime, "board_size": board_size()})
	_emit("gate", data)


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
	_emit("overtime", {"speed": OVERTIME_SPEEDS[0], "round": current_round})
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

## 当たった：位置を止めて、真下のパネルで正解かどうかを決める（判定を出すのは見せる間のあとの _judge）。
## gate_impact は見せ方が「つき破る」動き（正解は紙を破って抜ける、まちがいは破れずにはね返されてスローで爆散）を始める合図。
func _impact() -> void:
	_track_under()
	var answer := correct_choice()
	for slot: int in [0, 1]:
		results[slot] = "burst" if under[slot] >= 0 and under[slot] == answer else "boom"
		vel[slot] = Vector2.ZERO
		move[slot] = Vector2.ZERO
	impact_mode = SkyGateImpact.mode_of(results)
	_emit("gate_impact", _gate_result(answer))
	var length := BURST_IMPACT_TIME
	if impact_mode != SkyGateImpact.ALL_BURST:
		# まちがいがいる：見せ方の脱落のスローが判定の時刻（SkyGateImpact.BOOM_JUDGE_AT）に届くまで待つ
		length = SkyGateImpact.wasted_real_time(SkyGateImpact.BOOM_JUDGE_AT, impact_mode)
	_set_phase("impact", length)


func _gate_result(answer: int) -> Dictionary:
	return {"round": current_round, "index": gate_index, "panels": under.duplicate(), "results": results.duplicate(),
		"correct": answer, "local": [local_point(0), local_point(1)], "since": [float(under_tick[0]) * TICK, float(under_tick[1]) * TICK],
		"overtime": overtime, "mode": impact_mode, "speed": fall_speed}


## つき破る動きを見せ終えた：判定を出す（中身は当たった瞬間に止めた位置のまま）。
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
	if overtime and fall_speed >= SPEED_WIN_SPEED - 0.0001 and under_tick[0] != under_tick[1]:
		# 早い者勝ち：正解のパネルに入ってそのまま当たった時刻が早い方。同じ刻みならもう1枚。
		speed_times = [float(under_tick[0]) * TICK, float(under_tick[1]) * TICK]
		_decide(1 if under_tick[0] < under_tick[1] else 2, "speed")
		return
	_after_gate()


## 判定のあと（または2人とも復活したあと）：次のボード、ラウンドの終わり、ROUND 5 のあとの延長。
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
