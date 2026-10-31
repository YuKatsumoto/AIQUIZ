class_name PracticeCpu
extends Node

## 練習の CPU（docs/new_tutorial/phase6_design.md 3.1、台本③の 1.1）。P2（青）として、監督（PracticeDirector）が作って子にする。
## 毎フレーム、いまの「やること」に合わせて、本編側（担当 A）の入力口 game_state.practice_set_cpu_input(axis, jump, emote) を呼ぶ
## （P2 のキーボードと同じ所：移動・ジャンプ・エモート・押し合い・ゴーストの照準とため に使われる）。
## 台本にない動き（勝手に押す・勝手にエモート・勝手にジャンプ）はしない。歩いて動くときは、P1 にぶつからないよう回り込む。
## 座標はゲーム画面のもの（x は +が画面の左、z はコンベア上の前）。P2 を CPU にする（game_state.practice_p2_cpu）のは監督。
##
##   setup(game_state, world) / idle() / wave(slot) / move_to(x, z, speed) / go_door(door, haste) / run_forward(speed)
##   wander(x_range, speed) / push_toward_p1() / practice_moves(p1_like) / ghost_attack(target_player, perfect)
##   is_arrived() / action() / ghost_stage()
## やることは、新しいものを呼ぶと前のものをやめる（やめたものの finished は出さない）。
## 終わりのある動き（wave・move_to・go_door・practice_moves）は、終わったときに finished(動きの名前) を出す
## （呼んだのと同じフレームには出さないので、呼んですぐ await してよい）。終わったあとは入力 0 で待つ。
## 終わりのない動き（idle・run_forward・wander・push_toward_p1・ghost_attack）は、次の動きを呼ぶまで続ける。
## ゴーストの照準とためは、本編側の game_state.practice_ghost_state(2) で見る（ないときはゲーム画面の GhostSharkRideController を見る）。
## 押し合いのあるルール（MatchRules.local_push_enabled）では、横の入力（0.35 以上）が押し合いのキーにもなるので、
## そのあいだは push_toward_p1 のほかの歩く動きを P1 の近くで使わない（勝手に押すことになる）。

## move_to・go_door・wave・practice_moves が終わった（action は &"move_to" など。move_to は動けなくなったときも出す）
signal finished(action: StringName)
## ghost_attack：ためはじめた（構えた。ここから先は狙いを変えない）。台本③の 3-7「構えたら横へよけて」のきっかけ。
signal ghost_charging(target_player: int)

## ゴーストシャークの乗り手の操作（ゲーム画面の子。本編側の practice_ghost_state がまだ入っていないとき、照準の位置・ためを直接見る）
const GHOST_CONTROLLER_NAME := "GhostSharkRideController"
## プレイヤーの走る速さ（game_state.tuning がないとき）
const DEFAULT_PLAYER_SPEED := 7.6
## 着いたとみなす距離（m）と、残りの距離をこの秒で詰める速さまで落とす（近づくとゆっくりになって行き過ぎない）
const ARRIVE_DISTANCE := 0.15
const STEER_SECONDS := 0.15
## この秒のあいだ近づけなかったら（さく・P1 の体にふさがれた）、あきらめて止まる
const STUCK_SECONDS := 1.5
const STUCK_PROGRESS := 0.05
## P1 をよけて通る：体の真ん中どうしをこの距離より近づけない（体の半径 0.62 m × 2 に余裕）。よけはじめる距離
const BODY_CLEARANCE := 1.6
const AVOID_RADIUS := 2.6
## go_door のゆっくり（haste が SLOW_HASTE より小さい）：P1 より YIELD_GAP 後ろを越えて前に出ない。前に出そうなら少し下がる
## （プレイヤーが先に着く）。下がる強さ、P1 との前後の差、下がりすぎない所（コンベア上の z）
const YIELD_BACK := 0.35
const YIELD_GAP := 1.2
const YIELD_HOLD := 0.5
const YIELD_MIN_Z := -6.0
const SLOW_HASTE := 0.3
## go_door：横へ寄る速さ（haste 0〜1 で）、P1 が同じドアの前にいるときに寄せるドアの端（ドアの真ん中から m）
const DOOR_LATERAL_SPEED := Vector2(0.6, 1.0)
const DOOR_SHARE_OFFSET := 0.9
const DOOR_SHARE_RANGE := 1.2
## go_door：壁がこれより近いのにドアの前に寄れていなければ、前へは出ない（ドアの間の壁にぶつからない）
const DOOR_ALIGN_DISTANCE := 3.0
const DOOR_ALIGN_TOLERANCE := 1.2
## wave：エモートのキーを押している秒と、終わりまでの秒（エモートは本番どおり次のジャンプまで続くので、ここで止める）
const WAVE_SLOT := 1
const EMOTE_PRESS_SECONDS := 0.12
const WAVE_SECONDS := 2.2
## wander：端で折り返す余裕、前後の位置を戻す強さと許す差
const WANDER_EDGE := 0.15
const WANDER_DEPTH_TOLERANCE := 0.3
## practice_moves：左右・前後に動く幅（p1_like は台本 3-1 のクリア条件の合計 1.5 m を超える幅）、速さ、
## 1つの動きであきらめるまでの秒、ジャンプのキーを押す秒、着地のあとの間
const MOVES_STEP := 0.75
const MOVES_SMALL_STEP := 0.4
const MOVES_SPEED := 0.55
const MOVES_ARRIVE := 0.12
const MOVES_STEP_LIMIT := 1.4
const JUMP_PRESS_SECONDS := 0.12
const JUMP_LAND_SECONDS := 0.25
## push_toward_p1：前後をそろえる強さと許す差
const PUSH_DEPTH_TOLERANCE := 0.25
const PUSH_DEPTH_SPEED := 0.5
## ゴースト：照準の速さ（GhostSharkRideController.AIM_SPEED と同じ）、狙いを詰める時定数、合ったとみなす差、
## 照準が出てから構えるまでの最短の秒（1回目・2回目から）、合わなくても構える秒
const AIM_SPEED := 9.0
const AIM_RESPONSE := 0.12
const AIM_DEAD_ZONE := 0.05
const AIM_TOLERANCE := 0.35
const AIM_FIRST_SECONDS := 1.0
const AIM_NEXT_SECONDS := 0.6
const AIM_GIVE_UP_SECONDS := 3.5
## ゴースト：ため（約1.2秒。ためのメーターは 0.5 秒で一周するので、1.2 秒で 0.4 ほど。PERFECT の帯 0.72〜0.94 には入らない）。
## 帯に入っていたら抜けるまで少し待つ（最長 CHARGE_EXTRA_SECONDS）。perfect のときは帯の真ん中あたりで離す
const CHARGE_SECONDS := 1.2
const CHARGE_EXTRA_SECONDS := 0.4
const PERFECT_BAND := Vector2(0.72, 0.94)
const PERFECT_RELEASE := Vector2(0.78, 0.9)
const PERFECT_MIN_SECONDS := 1.0
## ゴースト：離したあと、照準のままこの秒が過ぎたら（突進にならなかった）、狙い直す
const RELEASE_RETRY_SECONDS := 0.6

enum Ghost { WAIT, AIM, CHARGE, RELEASED }

var game_state: QuizGameState = null
## テスト用：設定すると、practice_set_cpu_input の代わりにこれを (axis, jump, emote) で呼ぶ
var input_sink: Callable

var _world: Node = null
var _ghost: Node = null
var _ghost_phases := {}
var _warned_input := false
var _warned_ghost := false

var _action := &"idle"
var _time := 0.0
var _done := false
var _axis := Vector2.ZERO
var _jump := false
var _emote := 0
## move_to・practice_moves の行き先、速さ、近づけなかった秒
var _target := Vector2.ZERO
var _speed := 1.0
var _best_distance := INF
var _stuck_time := 0.0
var _gave_up := false
## go_door
var _door := 0
var _haste := 0.5
var _door_wall := -1
var _door_contact := false
var _door_over := false
## wander
var _range := Vector2.ZERO
var _wander_dir := 1.0
var _anchor_z := 0.0
## wave：始めたエモート（止めるときに、まだ同じものなら止める）
var _wave_emote := 0
## practice_moves：行き先の列、いまの番号、ジャンプの段階（0 まだ、1 押している、2 着地を待つ）、ジャンプの数
var _moves: Array[Vector2] = []
var _move_index := 0
var _move_time := 0.0
var _jump_stage := 0
var _jump_time := 0.0
var _jump_count := 0
## push_toward_p1：押す向き（+1 が画面の左）
var _push_dir := 1.0
## ghost_attack
var _ghost_target := 1
var _perfect := false
var _ghost_stage := Ghost.WAIT
var _stage_time := 0.0
var _aim_rounds := 0
var _left_aiming := false


func _init() -> void:
	name = "PracticeCpu"
	# 監督はポーズ中も動く（PROCESS_MODE_ALWAYS）が、CPU はポーズで止める（ためや待ち時間が進まないように）。
	process_mode = Node.PROCESS_MODE_PAUSABLE


## game_state：本編の状態。world：ゲーム画面（ゴーストの照準を見るのに使う。なくても、親の監督の world か
## いまのシーンから探す）。
func setup(state: QuizGameState, world: Node = null) -> void:
	if game_state != null:
		_connect_state(false)
	game_state = state
	_world = world
	_ghost = null
	if game_state != null:
		_connect_state(true)
	idle()


func _exit_tree() -> void:
	# 抜けたあとも P2 が動きつづけないよう、入力を 0 にしておく
	_axis = Vector2.ZERO
	_jump = false
	_emote = 0
	_send()
	if game_state != null:
		_connect_state(false)


# ---------- やること ----------

## 何もしない（入力 0）。
func idle() -> void:
	_begin(&"idle")


## その場で手をふる（エモートのキー slot を1回押す。台本の「CPU が手をふる」は 1）。約2秒で finished(&"wave")。
## 本番のエモートは次のジャンプまで続くので、終わるときに止める。
func wave(slot := WAVE_SLOT) -> void:
	_begin(&"wave")
	_wave_emote = clampi(slot, 1, 3)


## (x, z) へ動いて止まる（speed は 0〜1。1 が全力）。着いたら finished(&"move_to")。
## P1 にふさがれて STUCK_SECONDS 近づけなかったときも、止まって finished を出す（is_arrived は false）。
func move_to(x: float, z: float, speed := 1.0) -> void:
	_begin(&"move_to")
	_target = Vector2(x, z)
	_speed = clampf(speed, 0.05, 1.0)


## いまの壁のドア door（0 から。2択は 0 青・1 赤）の前へ寄り、壁へ向かって進む。壁に着いたら（正解でも不正解でも）
## finished(&"go_door")。ほかの人が先に正解して壁が終わったときも finished を出して止まる。
## haste：0 = ゆっくり〜1 = 前へ全力（前へ歩く入力の大きさ）。0.3 より小さいときは「ゆっくり」で、P1 より 1.2 m 後ろを
## 越えて前に出ない（前に出そうなら少し下がる。プレイヤーが先に着く。P1 がアウトのときは関係なし）。
## 0.5 以上は P1 の前を、それより下は P1 の後ろを回り込む。壁がまだないときは、出るまで待つ。
func go_door(door: int, haste := 0.5) -> void:
	_begin(&"go_door")
	_door = maxi(door, 0)
	_haste = clampf(haste, 0.0, 1.0)
	_door_wall = game_state.current_wall_index if game_state != null and game_state.current_quiz != null else -1


## 左右の位置はそのままで、前へ走りつづける（3-8 のゴールレース・3-5 ののこぎりから逃げるとき。speed 0〜1）。
func run_forward(speed := 1.0) -> void:
	_begin(&"run_forward")
	_speed = clampf(speed, 0.0, 1.0)


## 床の上で x_range（x の範囲。どちらが大きくてもよい）を左右にゆっくり行き来する（3-6 のゴーストの的）。
## 前後は呼んだときの位置に保つ（突進で飛ばされたら戻る）。
func wander(x_range: Vector2, speed := 0.4) -> void:
	_begin(&"wander")
	_range = Vector2(minf(x_range.x, x_range.y), maxf(x_range.x, x_range.y))
	_speed = clampf(speed, 0.05, 1.0)
	if game_state != null:
		var pos := _p2()
		_anchor_z = pos.y
		# 近いほうの端からではなく、遠いほうの端へ向かって歩き出す
		_wander_dir = 1.0 if pos.x < (_range.x + _range.y) * 0.5 else -1.0


## P1 のほうへ押しつづける（3-4 の押し合い。踏ん張る）。押し直し（一押し）はしない。前後は P1 にそろえる。
func push_toward_p1() -> void:
	_begin(&"push_toward_p1")
	if game_state != null:
		var dx := _p1().x - _p2().x
		_push_dir = signf(dx) if absf(dx) > 0.05 else 1.0


## 3-1 のお手本：左右（画面の左 → 右 → 元の所）、前後（前 → 後ろ → 元の所）に動いて、1回ジャンプする。
## 終わったら finished(&"practice_moves")。p1_like = true は台本 3-1 のクリア条件（左右・前後それぞれ合計 1.5 m 以上と
## ジャンプ1回）を満たす幅（左右・前後とも合計 3 m）、false は小さく（合計 1.6 m）。
func practice_moves(p1_like := true) -> void:
	_begin(&"practice_moves")
	_moves.clear()
	if game_state == null:
		return
	var start := _p2()
	var step := MOVES_STEP if p1_like else MOVES_SMALL_STEP
	for offset: Vector2 in [Vector2(step, 0.0), Vector2(-step, 0.0), Vector2.ZERO,
			Vector2(0.0, step), Vector2(0.0, -step), Vector2.ZERO]:
		_moves.append(start + offset)


## ゴーストのとき（P2 がゴーストシャークに乗っている）：照準が出たら target_player を狙い、合ったら構えて（ghost_charging）
## 約1.2秒ためて離す（突進）。構えたあとは狙いを変えない。突進のあと照準に戻ったら、また狙う（次の動きを呼ぶまで続ける）。
## perfect = false（既定）は PERFECT の帯では離さない（よけられる強さ）。true は帯の中で離す。
func ghost_attack(target_player := 1, perfect := false) -> void:
	_begin(&"ghost_attack")
	_ghost_target = 1 if target_player != 2 else 2
	_perfect = perfect
	_ghost_stage = Ghost.WAIT
	_stage_time = 0.0
	_aim_rounds = 0
	_left_aiming = false


## いまの動きの行き先に着いている（move_to：行き先の近く、go_door：壁に着いた・壁が終わった、
## wave・practice_moves：終わった、idle：いつも true、ほかの続く動き：false）。
func is_arrived() -> bool:
	match _action:
		&"idle":
			return true
		&"move_to":
			return game_state != null and _p2().distance_to(_target) <= ARRIVE_DISTANCE
		&"go_door":
			return _door_contact or _door_over
		&"wave", &"practice_moves":
			return _done
	return false


## いまの動きの名前（&"idle"・&"move_to" など）。
func action() -> StringName:
	return _action


## ghost_attack の段階（&"wait" 照準が出るのを待つ・&"aim" 狙う・&"charge" ためる・&"released" 離した）。ほかの動きのときは &"".
func ghost_stage() -> StringName:
	if _action != &"ghost_attack":
		return &""
	return [&"wait", &"aim", &"charge", &"released"][_ghost_stage]


func _begin(next: StringName) -> void:
	if _action == &"wave" and next != &"wave":
		_stop_wave_emote()
	_action = next
	_time = 0.0
	_done = false
	_axis = Vector2.ZERO
	_jump = false
	_emote = 0
	_best_distance = INF
	_stuck_time = 0.0
	_gave_up = false
	_door_contact = false
	_door_over = false
	_move_index = 0
	_move_time = 0.0
	_jump_stage = 0
	_jump_time = 0.0


func _finish() -> void:
	if _done:
		return
	_done = true
	_axis = Vector2.ZERO
	_jump = false
	_emote = 0
	finished.emit(_action)


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if game_state == null:
		return
	_time += delta
	match _action:
		&"wave":
			_update_wave()
		&"move_to":
			_update_move_to(delta)
		&"go_door":
			_update_go_door()
		&"run_forward":
			_update_run_forward()
		&"wander":
			_update_wander()
		&"push_toward_p1":
			_update_push()
		&"practice_moves":
			_update_practice_moves(delta)
		&"ghost_attack":
			_update_ghost(delta)
		_:
			_axis = Vector2.ZERO
			_jump = false
			_emote = 0
	_send()


func _send() -> void:
	if input_sink.is_valid():
		input_sink.call(_axis, _jump, _emote)
		return
	if game_state == null:
		return
	if game_state.has_method(&"practice_set_cpu_input"):
		game_state.call(&"practice_set_cpu_input", _axis, _jump, _emote)
	elif not _warned_input:
		_warned_input = true
		push_warning("PracticeCpu: game_state has no practice_set_cpu_input (the CPU cannot move P2)")


func _update_wave() -> void:
	_axis = Vector2.ZERO
	_jump = false
	_emote = _wave_emote if _time < EMOTE_PRESS_SECONDS else 0
	if _time >= WAVE_SECONDS and not _done:
		_stop_wave_emote()
		_finish()


## 手をふるエモートを止める（本番のエモートはジャンプするまで続くので、CPU の「1回」はここで終える）。
## ほかのエモートに変わっていたら触らない。
func _stop_wave_emote() -> void:
	if game_state == null or _wave_emote <= 0:
		return
	var slots: Array = game_state.p2_emote_slots
	var id: int = slots[_wave_emote - 1] if _wave_emote - 1 < slots.size() else 0
	if id > 0 and game_state.p2_emote == id:
		game_state.p2_emote = 0
	_wave_emote = 0


func _update_move_to(delta: float) -> void:
	var distance := _p2().distance_to(_target)
	if _gave_up:
		_axis = Vector2.ZERO
		return
	if distance <= ARRIVE_DISTANCE:
		_axis = Vector2.ZERO
		_finish()
		return
	if _track_stuck(distance, delta):
		_gave_up = true
		_finish()
		return
	_axis = _drive_to(_target, _speed, false)


func _update_go_door() -> void:
	_jump = false
	_emote = 0
	if _door_contact or _door_over:
		_axis = Vector2.ZERO
		_finish()
		return
	var quiz := game_state.current_quiz
	if quiz == null:
		# 壁がまだない（落ちてくる前）か、もう終わった
		_axis = Vector2.ZERO
		if _door_wall >= 0:
			_door_over = true
		return
	if _door_wall < 0:
		_door_wall = game_state.current_wall_index
	elif game_state.current_wall_index != _door_wall:
		_door_over = true
		_axis = Vector2.ZERO
		return
	if not _p2_standing():
		_axis = Vector2.ZERO
		return
	var pos := _p2()
	var door_x := _door_x(_door, quiz.c.size())
	var target_x := door_x
	# P1 も同じドアの前にいたら、ドアの P1 と反対の端をくぐる（体をぶつけない）
	if _p1_standing():
		var p1 := _p1()
		if absf(p1.x - door_x) < DOOR_SHARE_RANGE and absf(p1.y - pos.y) < 4.0:
			var side := signf(door_x - p1.x)
			if side == 0.0:
				side = signf(pos.x - door_x) if pos.x != door_x else 1.0
			target_x = door_x + side * DOOR_SHARE_OFFSET
	var lateral := lerpf(DOOR_LATERAL_SPEED.x, DOOR_LATERAL_SPEED.y, _haste)
	var ax := clampf((target_x - pos.x) / (_player_speed() * STEER_SECONDS), -1.0, 1.0) * lateral
	var ay := _haste
	if _haste < SLOW_HASTE and _p1_standing():
		# ゆっくり：P1 の少し後ろを行く（前に出そうなら下がる。すぐ後ろまで来たら、その差のままコンベアに運ばれる）
		var lead := pos.y - (_p1().y - YIELD_GAP)
		if lead > 0.0:
			ay = -YIELD_BACK if pos.y > YIELD_MIN_Z else 0.0
		elif lead > -YIELD_HOLD:
			ay = 0.0
	var wall_distance := game_state.wall_z - game_state.player2_z
	if absf(target_x - pos.x) > DOOR_ALIGN_TOLERANCE and wall_distance < DOOR_ALIGN_DISTANCE:
		ay = minf(ay, 0.0)
	_axis = _avoid_p1(Vector2(ax, ay), _haste >= 0.5).limit_length(1.0)


func _update_run_forward() -> void:
	_jump = false
	_emote = 0
	_axis = _avoid_p1(Vector2(0.0, _speed), true).limit_length(1.0) if _p2_standing() else Vector2.ZERO


func _update_wander() -> void:
	_jump = false
	_emote = 0
	if not _p2_standing():
		_axis = Vector2.ZERO
		return
	var pos := _p2()
	if pos.x >= _range.y - WANDER_EDGE:
		_wander_dir = -1.0
	elif pos.x <= _range.x + WANDER_EDGE:
		_wander_dir = 1.0
	var ay := 0.0
	var dz := _anchor_z - pos.y
	if absf(dz) > WANDER_DEPTH_TOLERANCE:
		ay = clampf(dz / (_player_speed() * STEER_SECONDS), -1.0, 1.0) * maxf(_speed, 0.5)
	_axis = _avoid_p1(Vector2(_wander_dir * _speed, ay), false).limit_length(1.0)


func _update_push() -> void:
	_jump = false
	_emote = 0
	var p1 := _p1()
	var pos := _p2()
	var dx := p1.x - pos.x
	if absf(dx) > 0.05:
		_push_dir = signf(dx)
	var ay := 0.0
	var dz := p1.y - pos.y
	if absf(dz) > PUSH_DEPTH_TOLERANCE:
		ay = clampf(dz / (_player_speed() * STEER_SECONDS), -1.0, 1.0) * PUSH_DEPTH_SPEED
	_axis = Vector2(_push_dir, ay).limit_length(1.0)


func _update_practice_moves(delta: float) -> void:
	_emote = 0
	if _done:
		_axis = Vector2.ZERO
		_jump = false
		return
	if _move_index < _moves.size():
		_jump = false
		var target := _moves[_move_index]
		_move_time += delta
		if _p2().distance_to(target) <= MOVES_ARRIVE or _move_time >= MOVES_STEP_LIMIT:
			_move_index += 1
			_move_time = 0.0
			_axis = Vector2.ZERO
			return
		_axis = _drive_to(target, MOVES_SPEED, false)
		return
	# 動き終わったら、1回ジャンプする（床に立ってから押す）
	_axis = Vector2.ZERO
	_jump_time += delta
	match _jump_stage:
		0:
			_jump = false
			if game_state.player2_y <= 0.001 and _p2_standing():
				_jump_stage = 1
				_jump_time = 0.0
				_jump_count = game_state.p2_jump_count
		1:
			_jump = true
			if _jump_time >= JUMP_PRESS_SECONDS:
				_jump = false
				_jump_stage = 2
				_jump_time = 0.0
		2:
			_jump = false
			if _jump_time >= JUMP_LAND_SECONDS and game_state.player2_y <= 0.001:
				_finish()


# ---------- ゴースト ----------

func _update_ghost(delta: float) -> void:
	_emote = 0
	var view := _ghost_view()
	var aiming: bool = view.aiming
	_stage_time += delta
	match _ghost_stage:
		Ghost.WAIT:
			_axis = Vector2.ZERO
			_jump = false
			if aiming:
				_start_aim()
		Ghost.AIM:
			_jump = false
			if not aiming:
				_axis = Vector2.ZERO
				_ghost_stage = Ghost.WAIT
				return
			var error := Vector2.ZERO
			if view.aim is Vector2:
				error = _player_pos(_ghost_target) - (view.aim as Vector2)
			_axis = Vector2.ZERO if error.length() < AIM_DEAD_ZONE else (error / (AIM_SPEED * AIM_RESPONSE)).limit_length(1.0)
			var think := AIM_FIRST_SECONDS if _aim_rounds <= 1 else AIM_NEXT_SECONDS
			var on_target := error.length() < AIM_TOLERANCE
			if _player_standing(_ghost_target) and _stage_time >= think and (on_target or _stage_time >= AIM_GIVE_UP_SECONDS):
				# 構える：ここから先は照準を動かさない
				_axis = Vector2.ZERO
				_jump = true
				_ghost_stage = Ghost.CHARGE
				_stage_time = 0.0
				ghost_charging.emit(_ghost_target)
		Ghost.CHARGE:
			_axis = Vector2.ZERO
			if not aiming:
				_jump = false
				_ghost_stage = Ghost.WAIT
				return
			_jump = true
			if _should_release(float(view.charge)):
				_jump = false
				_ghost_stage = Ghost.RELEASED
				_stage_time = 0.0
				_left_aiming = false
		Ghost.RELEASED:
			_axis = Vector2.ZERO
			_jump = false
			if not aiming:
				_left_aiming = true
			elif _left_aiming or _stage_time >= RELEASE_RETRY_SECONDS:
				# 突進のあと照準に戻った（か、突進にならなかった）。また狙う
				_start_aim()


func _start_aim() -> void:
	_ghost_stage = Ghost.AIM
	_stage_time = 0.0
	_aim_rounds += 1
	_left_aiming = false


## charge はいまのため（0〜1。分からなければ < 0 で、秒だけで決める）。
func _should_release(charge: float) -> bool:
	if _perfect:
		if charge < 0.0:
			return _stage_time >= PERFECT_MIN_SECONDS + (PERFECT_RELEASE.x + PERFECT_RELEASE.y) * 0.25
		return _stage_time >= PERFECT_MIN_SECONDS and charge >= PERFECT_RELEASE.x and charge <= PERFECT_RELEASE.y
	if _stage_time < CHARGE_SECONDS:
		return false
	if charge < 0.0 or _stage_time >= CHARGE_SECONDS + CHARGE_EXTRA_SECONDS:
		return true
	# PERFECT の帯の中では離さない（よけられる強さ）
	return charge < PERFECT_BAND.x - 0.02 or charge > PERFECT_BAND.y + 0.02


## P2 のゴーストの様子 {aiming: 照準を動かせる, aim: 照準の (x, コンベア上の z)（分からなければ null）, charge: ため（分からなければ −1）}。
## 本編側の game_state.practice_ghost_state(2) を使う。まだ入っていないときは、ゲーム画面の GhostSharkRideController を直接見る。
func _ghost_view() -> Dictionary:
	if game_state.has_method(&"practice_ghost_state"):
		var state: Dictionary = game_state.call(&"practice_ghost_state", 2)
		if not state.is_empty():
			var aim: Variant = state.get("aim")
			return {"aiming": bool(state.get("can_aim", false)), "aim": aim if aim is Vector2 else null,
				"charge": float(state.get("charge", -1.0))}
	var controller := _ghost_controller()
	if controller == null:
		return {"aiming": false, "aim": null, "charge": -1.0}
	var view := {"aiming": _ghost_aiming(controller), "aim": null, "charge": -1.0}
	if controller.has_method(&"get_aim_point"):
		var point: Vector3 = controller.call(&"get_aim_point")
		view.aim = Vector2(point.x, point.z)
	if controller.has_method(&"get_charge_amount"):
		view.charge = float(controller.call(&"get_charge_amount"))
	return view


## P2 のゴーストが照準を動かせる所（GhostSharkRideController の AIMING）にいる。
func _ghost_aiming(controller: Node) -> bool:
	if controller == null:
		return false
	if controller.has_method(&"is_control_active_for_player") and not bool(controller.call(&"is_control_active_for_player", 2)):
		return false
	if _ghost_phases.is_empty():
		var script := controller.get_script() as Script
		if script != null:
			var phases: Variant = script.get_script_constant_map().get("Phase", {})
			if phases is Dictionary:
				_ghost_phases = phases
	return _ghost_phases.has("AIMING") and int(controller.get(&"phase")) == int(_ghost_phases["AIMING"])


func _ghost_controller() -> Node:
	if _ghost != null and is_instance_valid(_ghost):
		return _ghost
	_ghost = null
	var world := _world if _world != null and is_instance_valid(_world) else null
	if world == null:
		var parent := get_parent()
		if parent != null and "world" in parent:
			world = parent.get("world") as Node
	if world == null and is_inside_tree():
		world = get_tree().current_scene
	if world != null:
		_ghost = world.get_node_or_null(NodePath(GHOST_CONTROLLER_NAME))
		if _ghost == null:
			_ghost = world.find_child(GHOST_CONTROLLER_NAME, true, false)
	if _ghost == null and not _warned_ghost:
		_warned_ghost = true
		push_warning("PracticeCpu: no %s found (the CPU ghost cannot see its aim)" % GHOST_CONTROLLER_NAME)
	return _ghost


# ---------- 道具 ----------

## target へ向かう入力（speed は入力の大きさの上限）。近づくと小さくして行き過ぎない。P1 はよけて通る。
func _drive_to(target: Vector2, speed: float, prefer_ahead: bool) -> Vector2:
	var delta := target - _p2()
	var distance := delta.length()
	if distance < 0.0001:
		return Vector2.ZERO
	var magnitude := minf(speed, distance / (_player_speed() * STEER_SECONDS))
	return _avoid_p1(delta / distance * magnitude, prefer_ahead).limit_length(1.0)


## want（入力）のうち P1 へ近づく分を、P1 のまわりを回る向きへ曲げる（近いほど強く）。とても近ければ少し離れる。
## prefer_ahead：P1 の前（+z）を回る。false なら後ろを回る。P1 が床に立っていないときは何もしない。
func _avoid_p1(want: Vector2, prefer_ahead: bool) -> Vector2:
	if game_state.num_players < 2 or not _p1_standing() or not _p2_standing():
		return want
	var away := _p2() - _p1()
	var distance := away.length()
	if distance >= AVOID_RADIUS or distance < 0.001:
		return want
	var toward := -away / distance
	var closing := want.dot(toward)
	var steered := want
	if closing > 0.0:
		var tangent := Vector2(-toward.y, toward.x)
		if absf(tangent.y) > 0.2:
			if (tangent.y > 0.0) != prefer_ahead:
				tangent = -tangent
		elif want.x != 0.0 and signf(tangent.x) != signf(want.x):
			tangent = -tangent
		var weight := clampf((AVOID_RADIUS - distance) / (AVOID_RADIUS - BODY_CLEARANCE), 0.0, 1.0)
		steered = want - toward * closing * weight + tangent * closing * weight
	if distance < BODY_CLEARANCE:
		steered -= toward * (BODY_CLEARANCE - distance) / BODY_CLEARANCE
	return steered


## 近づけないまま STUCK_SECONDS たった。
func _track_stuck(distance: float, delta: float) -> bool:
	if distance < _best_distance - STUCK_PROGRESS:
		_best_distance = distance
		_stuck_time = 0.0
		return false
	_stuck_time += delta
	return _stuck_time >= STUCK_SECONDS


func _door_x(door: int, choices: int) -> float:
	var tuning: Variant = game_state.tuning
	if choices == 4:
		var xs: Array = tuning.door4_xs
		return float(xs[clampi(door, 0, xs.size() - 1)])
	return float(tuning.left_door_x) if door == 0 else float(tuning.right_door_x)


func _player_speed() -> float:
	var tuning: Variant = game_state.tuning
	return float(tuning.player_speed) if tuning != null else DEFAULT_PLAYER_SPEED


func _p1() -> Vector2:
	return Vector2(game_state.player_x, game_state.player_local_z)


func _p2() -> Vector2:
	return Vector2(game_state.player2_x, game_state.player2_local_z)


func _player_pos(index: int) -> Vector2:
	return _p2() if index == 2 else _p1()


func _p1_standing() -> bool:
	return game_state.p1_alive and not game_state.p1_fall_committed and not game_state.p1_waiting_for_shark


func _p2_standing() -> bool:
	return game_state.p2_alive and not game_state.p2_fall_committed and not game_state.p2_waiting_for_shark


func _player_standing(index: int) -> bool:
	return _p2_standing() if index == 2 else _p1_standing()


# ---------- game_state の出来事 ----------

func _connect_state(on: bool) -> void:
	var pairs := [[game_state.practice_wall_contact, _on_wall_contact], [game_state.question_completed, _on_question_completed]]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var callback: Callable = pair[1]
		if on and not sig.is_connected(callback):
			sig.connect(callback)
		elif not on and sig.is_connected(callback):
			sig.disconnect(callback)


func _on_wall_contact(player_index: int, _door_index: int, _correct: bool) -> void:
	if _action == &"go_door" and player_index == 2:
		_door_contact = true


func _on_question_completed(wall_index: int, _correct: bool) -> void:
	if _action == &"go_door" and (_door_wall < 0 or wall_index == _door_wall):
		_door_over = true
