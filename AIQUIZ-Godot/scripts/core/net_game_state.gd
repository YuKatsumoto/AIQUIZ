extends Node
class_name NetGameState

## ネットワーク同期レイヤー（プロトコル v2）
##
## ホスト: QuizGameState を 1/60 秒の固定ティックで進め、ゲストのコマンドを
##   ジッタバッファから 1 ティック 1 個ずつ消費する。30Hz で差分スナップショット、
##   問題（変更があれば再送）、確実に届けたいイベントを送る。
## ゲスト: 判定は行わない。自分のアバターは NetPredictor で予測し、ホストの
##   アバターは NetInterpBuffer で 100ms 過去を補間して描く。表示する世界の
##   スクロールは「自分の入力がホストに届く時刻」まで先回りさせるので、
##   自分が見て通った扉とホストの判定が一致する。
## 切断: どちらかが落ちたら両者とも一時停止し、復帰したらホストが全状態を
##   送り直して 3-2-1 で再開する。猶予切れは不戦勝。

signal pause_changed(paused: bool, message: String)
signal match_over(message: String)
signal shark_impact(player_index: int, position: Vector3, forward: Vector3)
## 相手の画面のゴーストシャーク（照準・チャージ・エモートと、突進・命中のイベント）。
## ホストからはスナップショットに、ゲストからはコマンドに相乗りして届く（リレーは中身を見ない）。
signal ghost_received(state: Dictionary, events: Array)

const TICK := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 4
const SNAPSHOT_EVERY_TICKS := 2  # 30Hz
const KEYFRAME_INTERVAL := 2.0
const CMD_BATCH_TICKS := 2
const HOST_BUFFER_MAX := 8
## ゲストのコマンドは 2 ティック分ずつ届くので、これだけ溜めてから使い始める。
## 空になるたびに直前の入力で埋めると予測とずれるため、空になったら溜め直す。
const HOST_BUFFER_PRIME := 3
const QUIZ_CHECK_INTERVAL := 0.25
const RESUME_COUNTDOWN := 3.0
## 押し合いの相殺（同時押し）とみなす押下時刻の差。オフラインは 0.05 秒。お互い少し前の
## 相手を見て反応するので、オンラインでは広げる。
const ONLINE_CLASH_WINDOW := 0.10
## 接触中・押された直後は、自分の左右位置も相手と同じ補間の時間軸で描く。切り替えにかける秒数。
const PUSH_VIEW_BLEND := 0.15
## 送れないあいだ（一時停止など）に溜めておくゴーストシャークのイベントの上限。
const GHOST_EVENTS_MAX := 16

var game_state: QuizGameState
var is_online: bool = false
var is_host: bool = false
var tick: int = 0

## ネット都合の一時停止（自分か相手の再接続待ち、再開カウントダウン中）。
var paused := false
var pause_message := ""
var resume_countdown := 0.0
var finished := false
## ホスト: ゲストの開始準備（壁の構築など）が整った。
var guest_ready := false
## ホスト: ゲストのゲーム画面の準備の描画が終わった（ready の phase が "loaded"。マッチング演出 M6）。
var guest_loaded := false
## 両方の画面で中央の線を開く時刻（サーバー時刻 ms。ホストの evt reveal で決まる。-1 はまだ）。
var reveal_at_ms := -1.0

# ---------- Host ----------
var _cmd_buffer: Array[Array] = []
var _last_cmd: Array = [0, 0.0, 0.0, false, 0]
var _buffer_primed := false
var _starved_ticks := 0
var _acked_seq := 0
var _host_acc := 0.0
var _snapshot_ticks := 0
var _keyframe_timer := 0.0
var _last_sent: Dictionary = {}
var _quiz_check_timer := 0.0
var _sent_quiz_sigs: Array[String] = []

# ---------- Guest ----------
var predictor: NetPredictor
var _interp: Array[NetInterpBuffer] = []
var _seq := 0
var _guest_acc := 0.0
var _outbox: Array = []
var _outbox_ticks := 0
var _snap_state: Dictionary = {}
var _snap_time := 0.0
var _snap_scroll := 0.0
var _host_buffer := 0
var _scroll := 0.0
var _scroll_ready := false
var _remote_jump_count := 0
var _display_passed_wall: Array[int] = [-1, -1, -1]
var _local_moving_back := false
var _push_view := 0.0
## ホスト: 最後に届いたゲストの押し合いキーの押下状態（中断時の同期に使う）。
var remote_push_mask := 0

# ---------- Ghost shark (both) ----------
## 自分が乗っているゴーストシャークの最新の状態（乗っていなければ空）と、まだ送っていないイベント。
var _ghost_state: Dictionary = {}
var _ghost_events: Array = []

# ---------- Stats (F8 overlay) ----------
var stats := {"snap_bytes": 0, "cmd_bytes": 0, "correction": 0.0, "buffer": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NetworkManager.relay_message.connect(_on_relay_message)
	NetworkManager.peer_paused.connect(_on_peer_paused)
	NetworkManager.peer_resumed.connect(_on_peer_resumed)
	NetworkManager.resumed.connect(_on_self_resumed)
	NetworkManager.state_changed.connect(_on_network_state_changed)
	NetworkManager.forfeit_received.connect(_on_forfeit)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.server_restarting.connect(_on_server_restart)


func _exit_tree() -> void:
	for pair in [
		[NetworkManager.relay_message, _on_relay_message],
		[NetworkManager.peer_paused, _on_peer_paused],
		[NetworkManager.peer_resumed, _on_peer_resumed],
		[NetworkManager.resumed, _on_self_resumed],
		[NetworkManager.state_changed, _on_network_state_changed],
		[NetworkManager.forfeit_received, _on_forfeit],
		[NetworkManager.reconnect_failed, _on_reconnect_failed],
		[NetworkManager.peer_left, _on_peer_left],
		[NetworkManager.server_restarting, _on_server_restart],
	]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func setup(gs: QuizGameState) -> void:
	"""game_worldから呼ばれる初期化"""
	game_state = gs
	is_online = NetworkManager.is_online_game()
	is_host = NetworkManager.is_host
	tick = 0
	_sent_quiz_sigs.clear()
	_last_sent.clear()
	_cmd_buffer.clear()
	if not is_online:
		return
	gs.net_online = true
	gs.net_authority = is_host
	gs.local_slot = 1 if is_host else 2
	gs.local_push.clash_window = ONLINE_CLASH_WINDOW
	if is_host:
		if not gs.local_push_event.is_connected(_send_push_fx):
			gs.local_push_event.connect(_send_push_fx)
		if not gs.question_completed.is_connected(_send_question_completed):
			gs.question_completed.connect(_send_question_completed)
		if not gs.health_changed.is_connected(_send_health_changed):
			gs.health_changed.connect(_send_health_changed)
		if not gs.question_winner_decided.is_connected(_send_question_winner):
			gs.question_winner_decided.connect(_send_question_winner)
		if not gs.state_changed.is_connected(_on_host_state_changed):
			gs.state_changed.connect(_on_host_state_changed)
	else:
		predictor = NetPredictor.new()
		predictor.setup(gs, 2)
		_interp = [NetInterpBuffer.new(), NetInterpBuffer.new(), NetInterpBuffer.new()]
		_scroll = gs.world_scroll_z
	if not NetworkManager.opponent_present:
		_set_paused(true, "あいてを まっています…")


## 旧テスト互換: 試合外の単体テストで使う最小セットアップ。
func is_guest() -> bool:
	return is_online and not is_host


# ===========================================================================
# Host
# ===========================================================================

## このフレームで回す固定ティック数。一時停止中は 0。
func host_begin_frame(dt: float) -> int:
	if paused:
		_tick_resume_countdown(dt)
		return 0
	_host_acc = minf(_host_acc + dt, TICK * MAX_STEPS_PER_FRAME)
	var steps := int(_host_acc / TICK)
	_host_acc -= steps * TICK
	return steps


## 1 ティック分のゲスト入力 {axis, jump, emote}。届いていなければ直前の移動を続ける。
func host_pop_command() -> Dictionary:
	# 溜まりすぎたら古いものを捨てて遅延を詰める（ジャンプ押下は引き継ぐ）。
	var carried_jump := false
	while _cmd_buffer.size() > HOST_BUFFER_MAX:
		var dropped: Array = _cmd_buffer.pop_front()
		carried_jump = carried_jump or bool(dropped[3])
		_acked_seq = int(dropped[0])
		# 捨てるティックの押し合いキーも順番を保って次のティックの頭で渡す。
		if dropped.size() > 6 and not (dropped[6] as Array).is_empty():
			var carried_push: Array = []
			for event in dropped[6]:
				carried_push.append([event[0], event[1], 0.0])
			if not _cmd_buffer.is_empty():
				_cmd_buffer[0][6] = carried_push + (_cmd_buffer[0][6] as Array)
	if not _buffer_primed and _cmd_buffer.size() >= HOST_BUFFER_PRIME:
		_buffer_primed = true
	var cmd: Array
	if _cmd_buffer.is_empty() or not _buffer_primed:
		# 届いていない間はゲストを動かさない（予測側も同じ入力を再生しないため）。
		# 溜め直しの間だけ、ゲストの位置補正がわずかに出る。
		_buffer_primed = false
		_starved_ticks += 1
		cmd = [_acked_seq, 0.0, 0.0, false, 0, remote_push_mask, []]
	else:
		cmd = _cmd_buffer.pop_front()
		_acked_seq = int(cmd[0])
		_last_cmd = cmd
	stats.buffer = _cmd_buffer.size()
	stats["starved"] = _starved_ticks
	remote_push_mask = int(cmd[5])
	return {
		"axis": Vector2(float(cmd[1]), float(cmd[2])).limit_length(1.0),
		"jump": bool(cmd[3]) or carried_jump,
		"emote": int(cmd[4]),
		"push": cmd[6],
	}


func host_after_tick() -> void:
	tick += 1
	_snapshot_ticks += 1
	if _snapshot_ticks >= SNAPSHOT_EVERY_TICKS:
		_snapshot_ticks = 0
		_send_snapshot(false)


func process_network(dt: float) -> void:
	"""game_world._process()から毎フレーム呼ばれる"""
	if not is_online or game_state == null:
		return
	if is_host:
		_keyframe_timer += dt
		if _keyframe_timer >= KEYFRAME_INTERVAL:
			_keyframe_timer = 0.0
			_send_snapshot(true)
		_quiz_check_timer += dt
		if _quiz_check_timer >= QUIZ_CHECK_INTERVAL:
			_quiz_check_timer = 0.0
			_sync_online_quizzes()


func _send_snapshot(full: bool) -> void:
	if NetworkManager.state != NetworkManager.State.IN_GAME:
		return
	var snap := _build_snapshot()
	var out: Dictionary = {}
	if full or _last_sent.is_empty():
		out = snap.duplicate()
		out["kf"] = true
	else:
		for key in snap:
			if not _last_sent.has(key) or _last_sent[key] != snap[key]:
				out[key] = snap[key]
	_last_sent = snap
	# ゴーストシャークは差分の外（毎回の最新とイベント）。ゲストは受け取ったら取り除く。
	_attach_ghost(out)
	stats.snap_bytes += JSON.stringify(out).length()
	NetworkManager.send("snap", out)


## 自分のゴーストシャークの送るもの（GhostSharkRideController.take_net_outgoing）を毎フレーム渡す。
## 状態は最新だけ、イベントは届けるまで溜める。ホストは次のスナップショット、ゲストは次のコマンドで送る。
func queue_ghost(outgoing: Dictionary) -> void:
	if not is_online:
		return
	_ghost_state = outgoing.get("state", {})
	for event: Variant in outgoing.get("events", []):
		_ghost_events.append(event)
	while _ghost_events.size() > GHOST_EVENTS_MAX:
		_ghost_events.pop_front()


## 送る中身に、ゴーストシャークの分を足す（状態は gh、イベントは ghe）。
func _attach_ghost(payload: Dictionary) -> void:
	if not _ghost_state.is_empty():
		payload["gh"] = _ghost_state
	if not _ghost_events.is_empty():
		payload["ghe"] = _ghost_events
		_ghost_events = []


func _receive_ghost(data: Dictionary) -> void:
	var state: Variant = data.get("gh", {})
	var events: Variant = data.get("ghe", [])
	if state is Dictionary and events is Array and (not (state as Dictionary).is_empty() or not (events as Array).is_empty()):
		ghost_received.emit(state, events)


func _build_snapshot() -> Dictionary:
	var snap := game_state.to_snapshot()
	for key in snap.keys():
		if snap[key] is float:
			snap[key] = snappedf(snap[key], 0.001)
	snap["tick"] = tick
	snap["ack"] = _acked_seq
	snap["bd"] = _cmd_buffer.size()
	return snap


func _sync_online_quizzes() -> void:
	var quizzes := game_state.quiz_list
	if quizzes.size() < _sent_quiz_sigs.size():
		_sent_quiz_sigs.resize(quizzes.size())
	for i in range(quizzes.size()):
		var quiz: QuizItem = quizzes[i]
		if quiz == null:
			continue
		var sig := _quiz_signature(quiz)
		if i < _sent_quiz_sigs.size() and _sent_quiz_sigs[i] == sig:
			continue
		while _sent_quiz_sigs.size() <= i:
			_sent_quiz_sigs.append("")
		_sent_quiz_sigs[i] = sig
		NetworkManager.send("quiz", _quiz_payload(quiz, i))


func _quiz_signature(quiz: QuizItem) -> String:
	return "%s|%s|%d" % [quiz.q, "|".join(quiz.c), quiz.a]


func _quiz_payload(quiz: QuizItem, index: int) -> Dictionary:
	return {
		"index": index,
		"q": quiz.q,
		"c": Array(quiz.c),
		"a": quiz.a,
		"e": quiz.e,
		"src": quiz.src,
		"est": quiz.estimated_seconds,
	}


## 旧 API 互換（ホストから任意の問題を送る）。
func send_quiz_to_client(quiz: QuizItem, quiz_index: int = -1) -> void:
	if is_online and is_host and quiz != null:
		NetworkManager.send("quiz", _quiz_payload(quiz, quiz_index))


func send_game_event(event_name: String, data: Dictionary = {}) -> void:
	"""ホスト: ゲームイベントをクライアントに送信"""
	if not is_online or not is_host:
		return
	var payload := data.duplicate()
	payload["event"] = event_name
	NetworkManager.send("evt", payload)


func _send_question_completed(wall_index: int, correct: bool) -> void:
	send_game_event("question_completed", {"wall_index": wall_index, "correct": correct})


func _send_question_winner(question_index: int, winner_mask: int) -> void:
	send_game_event("question_winner", {"index": question_index, "mask": winner_mask})


func _send_health_changed(player_index: int, _previous: int, hp: int) -> void:
	# Reliable events retain a damage -> heal pair occurring between snapshots.
	send_game_event("health_changed", {"player": player_index, "hp": hp})


func _send_push_fx(event: Dictionary) -> void:
	var feet: Array = []
	for foot: Vector3 in event.get("feet", []):
		feet.append([snappedf(foot.x, 0.01), snappedf(foot.y, 0.01), snappedf(foot.z, 0.01)])
	var pos: Vector3 = event.get("position", Vector3.ZERO)
	send_game_event("push_fx", {
		"kind": str(event.get("kind", "")),
		"player": int(event.get("player", 0)),
		"direction": float(event.get("direction", 0.0)),
		"x": float(event.get("x", 0.0)),
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"feet": feet,
	})


func send_shark_impact(player_index: int, position: Vector3, forward: Vector3) -> void:
	send_game_event("shark_impact", {
		"player": player_index,
		"pos": [position.x, position.y, position.z],
		"fwd": [forward.x, forward.y, forward.z],
	})


func _on_host_state_changed(new_state: String) -> void:
	if finished or not is_host:
		return
	if new_state == Constants.STATE_RESULT_CEREMONY and game_state.result_presentation_active:
		# 結果発表の始まり：確定した中身を送る（ゲストは自分の時計で同じ結果発表を進める）。
		# スナップショットより先に届くので、ゲストの状態はこれで結果発表に入る。
		send_game_event("result_begin", game_state.result_net_payload())
		return
	if new_state == Constants.STATE_GAME_OVER and game_state.elimination_result_pending:
		# 2 人とも脱落：GAME OVER のあと結果発表へ進む。試合の終わりは結果発表のあとの CLEAR で知らせる。
		return
	if new_state in [Constants.STATE_CLEAR, Constants.STATE_GAME_OVER]:
		finished = true
		_send_snapshot(true)
		NetworkManager.send("finish", {"state": new_state})


func _send_resync() -> void:
	var quizzes: Array = []
	for i in range(game_state.quiz_list.size()):
		var quiz: QuizItem = game_state.quiz_list[i]
		if quiz != null:
			quizzes.append(_quiz_payload(quiz, i))
	_last_sent.clear()
	var snap := _build_snapshot()
	_last_sent = snap
	NetworkManager.send("resync", {
		"quizzes": quizzes,
		"winners": Array(game_state.question_winners),
		"snap": snap,
	})
	_cmd_buffer.clear()


# ===========================================================================
# Guest
# ===========================================================================

## ゲストの毎フレーム処理: 入力をコマンドにして送り、予測と描画位置を更新する。
## push_events: この描画フレームの押し合いキー {direction, pressed, usec}。push_mask: 今の押下状態。
func guest_frame(dt: float, axis: Vector2, jump: bool, emote: int, push_events: Array = [], push_mask: int = 0) -> void:
	if game_state == null:
		return
	game_state.client_tick(dt)
	predictor.decay_error(dt)
	if paused:
		_tick_resume_countdown(dt)
	else:
		_guest_acc = minf(_guest_acc + dt, TICK * MAX_STEPS_PER_FRAME)
		var axis_q := Vector2(snappedf(axis.x, 0.001), snappedf(axis.y, 0.001))
		_local_moving_back = axis_q.y < -0.1
		var steps := int(_guest_acc / TICK)
		var tick_push := _split_push_events(push_events, dt, steps)
		var step_index := 0
		while _guest_acc >= TICK:
			_guest_acc -= TICK
			_seq += 1
			_advance_scroll(TICK)
			var jump_before := predictor.jump_count
			predictor.push_command({
				"seq": _seq, "ax": axis_q.x, "ay": axis_q.y, "j": jump, "e": emote,
				"scroll": _scroll, "state": game_state.game_state,
			})
			if predictor.jump_count != jump_before:
				game_state.p2_jump_trigger = true
			_outbox.append([_seq, axis_q.x, axis_q.y, jump, emote, push_mask, tick_push[step_index]])
			step_index += 1
			_outbox_ticks += 1
		if _outbox_ticks >= CMD_BATCH_TICKS:
			var payload := {"c": _outbox}
			_attach_ghost(payload)
			stats.cmd_bytes += JSON.stringify(payload).length()
			NetworkManager.send("cmd", payload)
			_outbox = []
			_outbox_ticks = 0
	_correct_scroll(dt)
	_render()


## 押し合いキーを、このフレームで作るティックへ押下時刻どおりに振り分ける。
## ティックを作らないフレームの分は次のフレームへ持ち越す。
var _carried_push: Array = []

func _split_push_events(events: Array, dt: float, steps: int) -> Array:
	var all := _carried_push + events
	if steps <= 0:
		_carried_push = all
		return []
	_carried_push = []
	var buckets: Array = []
	for i in range(steps):
		buckets.append([])
	var frame_start := Time.get_ticks_usec() - int(dt * 1000000.0)
	for event: Dictionary in all:
		var fraction := clampf(float(int(event.usec) - frame_start) / maxf(dt * 1000000.0, 1.0), 0.0, 0.9999)
		var slot := fraction * steps
		var index := mini(int(slot), steps - 1)
		var offset := snappedf((slot - index) * TICK, 0.0001)
		buckets[index].append([int(event.direction), bool(event.pressed), offset])
	return buckets


func _advance_scroll(dt: float) -> void:
	if game_state.game_state == Constants.STATE_PLAYING:
		_scroll += game_state._active_wall_speed * dt


## 表示スクロールを「自分の入力がホストで処理される時刻」の推定へ寄せる。
func _correct_scroll(dt: float) -> void:
	if not _scroll_ready:
		return
	var target := _snap_scroll
	if game_state.game_state == Constants.STATE_PLAYING:
		var rtt := maxf(0.0, NetworkManager.rtt_ms) / 1000.0
		var age := Time.get_ticks_msec() / 1000.0 - _snap_time
		target += game_state._active_wall_speed * (rtt + age + _host_buffer * TICK)
	var diff := target - _scroll
	if absf(diff) > 3.0:
		_scroll = target
	else:
		_scroll += diff * minf(1.0, dt * 4.0)


func _render() -> void:
	var gs := game_state
	var now := Time.get_ticks_msec() / 1000.0
	gs.world_scroll_z = _scroll
	if gs.result_presentation_active:
		# 結果発表のあいだは、ゲストの時計で動かした立ち位置（_update_result_ceremony）をそのまま描く。
		return
	# 相手（ホスト = スロット 1）は補間。
	if not _interp[1].is_empty():
		var p1 := _interp[1].sample(now)
		gs.player_x = p1.x
		gs.player_y = p1.y
		gs.player_z = _display_wall_clamp(1, p1.x, _scroll + p1.z)
	# 自分（スロット 2）は予測。予測できない状態（演出・脱落中）は補間。
	# 押し合いの接触中と押された直後は、自分の左右位置も相手と同じ補間の時間軸に乗せる。
	# 肩の当たりと押し出しの見た目が、両者そろった 1 つのホストの結果になる。
	var push_target := 1.0 if gs.uses_local_push() and (gs.local_push.contact or gs.local_push.is_shoving(1) or gs.local_push.is_shoving(2)) else 0.0
	_push_view = move_toward(_push_view, push_target, get_process_delta_time() / PUSH_VIEW_BLEND)
	if predictor.is_active():
		gs.player2_x = predictor.render_x()
		if _push_view > 0.0 and not _interp[2].is_empty():
			gs.player2_x = lerpf(gs.player2_x, _interp[2].sample(now).x, _push_view)
		gs.player2_y = predictor.render_y()
		gs.player2_z = _scroll + predictor.render_lz()
		gs.player2_vel_y = predictor.vy
		gs.p2_moving_back = _local_moving_back
	elif not _interp[2].is_empty():
		var p2 := _interp[2].sample(now)
		gs.player2_x = p2.x
		gs.player2_y = p2.y
		gs.player2_z = _scroll + p2.z
	_separate_rendered_bodies()
	stats.correction = predictor.last_correction


## 体の押し合いはホストだけが解く。ゲストは「予測した自分」と「少し過去の相手」を描くので、
## 描画上だけ 2 人を等分に押し離してめり込みを見せない（判定や予測には使わない）。
func _separate_rendered_bodies() -> void:
	var gs := game_state
	if not gs.p1_alive or not gs.p2_alive or gs.p1_fall_committed or gs.p2_fall_committed:
		return
	if absf(gs.player_y - gs.player2_y) >= QuizGameState.PLAYER_BODY_HEIGHT:
		return
	var separation := Vector2(gs.player2_x - gs.player_x, gs.player2_z - gs.player_z)
	var minimum := QuizGameState.PLAYER_BODY_RADIUS * 2.0
	var distance := separation.length()
	if distance >= minimum:
		return
	var normal := separation / distance if distance > 0.0001 else Vector2(-1.0, 0.0)
	var push := normal * (minimum - distance) * 0.5
	gs.player_x -= push.x
	gs.player_z -= push.y
	gs.player2_x += push.x
	gs.player2_z += push.y


## 補間中の相手が、判定待ちの壁を表示上すり抜けないようにする（正解の扉は通す）。
func _display_wall_clamp(slot: int, x: float, world_z: float) -> float:
	var gs := game_state
	if gs.game_state != Constants.STATE_PLAYING or gs.choice_locked:
		return world_z
	var alive := gs.p1_alive if slot == 1 else gs.p2_alive
	var committed := gs.p1_fall_committed if slot == 1 else gs.p2_fall_committed
	if not alive or committed or _display_passed_wall[slot] == gs.current_wall_index:
		return world_z
	if world_z < gs.wall_z - 0.4 or gs.is_in_wall_border_lane(x):
		return world_z
	if gs.current_quiz != null and gs._check_player_door(x) == gs.current_quiz.a:
		_display_passed_wall[slot] = gs.current_wall_index
		return world_z
	return gs.wall_z - 0.4


func _on_snapshot_received(data: Dictionary) -> void:
	"""ゲスト: ホストからのスナップショット（差分）を適用"""
	if game_state == null or is_host:
		return
	if data.has("gh") or data.has("ghe"):
		_receive_ghost(data)
		data = data.duplicate()
		data.erase("gh")
		data.erase("ghe")
	if bool(data.get("kf", false)):
		_snap_state = data.duplicate()
	else:
		_snap_state.merge(data, true)
	var full := _snap_state
	if predictor == null:
		# 単体テストなど、試合の外では位置もそのまま適用する。
		game_state.apply_snapshot(full)
		_sync_client_current_quiz()
		return
	game_state.apply_snapshot(full, true)
	var now := Time.get_ticks_msec() / 1000.0
	var ws := float(full.get("ws", 0.0))
	_snap_time = now
	_snap_scroll = ws
	_host_buffer = int(full.get("bd", 0))
	if not _scroll_ready:
		_scroll = ws
		_scroll_ready = true
	_interp[1].push(now, float(full.get("p1x", 0.0)), float(full.get("p1y", 0.0)), float(full.get("p1z", 0.0)) - ws)
	_interp[2].push(now, float(full.get("p2x", 0.0)), float(full.get("p2y", 0.0)), float(full.get("p2z", 0.0)) - ws)
	var remote_jumps := int(full.get("p1jc", 0))
	if remote_jumps != _remote_jump_count:
		_remote_jump_count = remote_jumps
		game_state.p1_jump_trigger = true
	game_state.player_vel_y = float(full.get("p1vy", game_state.player_vel_y))
	predictor.reconcile(int(full.get("ack", 0)), _slot_motion(full, 2))
	_sync_client_current_quiz()


func _slot_motion(full: Dictionary, slot: int) -> Dictionary:
	var p := "p%d" % slot
	var ws := float(full.get("ws", 0.0))
	return {
		"x": float(full.get(p + "x", 0.0)),
		"lz": float(full.get(p + "z", 0.0)) - ws,
		"y": float(full.get(p + "y", 0.0)),
		"vy": float(full.get(p + "vy", 0.0)),
		"ex": float(full.get(p + "ex", 0.0)),
		"ez": float(full.get(p + "ez", 0.0)),
		"lock": float(full.get(p + "lk", 0.0)),
		"hurt": float(full.get("hurt%d" % slot, 0.0)),
	}


func _sync_client_current_quiz() -> void:
	var index := game_state.current_index
	if index < 0 or index >= game_state.quiz_list.size():
		return
	var quiz: QuizItem = game_state.quiz_list[index]
	if quiz == null or game_state.current_quiz == quiz:
		return
	game_state.current_quiz = quiz
	game_state.quiz_loaded.emit(quiz)


func _on_quiz_received(data: Dictionary) -> void:
	"""クライアント: ホストからのクイズデータを受信"""
	if is_host or game_state == null:
		return
	var quiz := QuizItem.create(
		data.get("q", ""),
		PackedStringArray(data.get("c", [])),
		int(data.get("a", 0)),
		data.get("e", ""),
		str(data.get("src", "")),
		"",
		PackedStringArray(),
		float(data.get("est", 4.0))
	)
	var validator: QuizValidator = QuizManager.quiz_validator
	var validation := validator.validate_rules([quiz]) if validator != null else {"valid": [quiz]}
	if (validation.get("valid", []) as Array).is_empty():
		push_warning("Rejected invalid network quiz payload")
		return
	var quiz_index := int(data.get("index", game_state.quiz_list.size()))
	if quiz_index < 0 or quiz_index > 64:
		return
	while game_state.quiz_list.size() <= quiz_index:
		game_state.quiz_list.append(null)
	game_state.quiz_list[quiz_index] = quiz
	if quiz_index == game_state.current_index:
		game_state.current_quiz = quiz
		game_state.quiz_loaded.emit(quiz)


func _on_event_received(data: Dictionary) -> void:
	"""クライアント: ホストからのゲームイベントを受信"""
	if game_state == null:
		return
	var event_name := str(data.get("event", ""))
	match event_name:
		"health_changed":
			var player_index := int(data.get("player", 0))
			if not NetworkManager.is_host and player_index in [1, 2]:
				game_state._set_player_hp(player_index, int(data.get("hp", game_state.get_player_hp(player_index))))
		"question_winner":
			if not NetworkManager.is_host:
				game_state.record_question_winner(int(data.get("index", -1)), int(data.get("mask", 0)))
		"question_completed":
			if not NetworkManager.is_host:
				if bool(data.get("correct", false)):
					game_state.correct_answer.emit()
				game_state.question_completed.emit(int(data.get("wall_index", -1)), bool(data.get("correct", false)))
		"shark_impact":
			var pos: Array = data.get("pos", [0, 0, 0])
			var fwd: Array = data.get("fwd", [0, 0, 1])
			shark_impact.emit(int(data.get("player", 1)),
				Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
				Vector3(float(fwd[0]), float(fwd[1]), float(fwd[2])))
		"resume":
			_begin_resume_countdown()
		"result_begin":
			if not is_host:
				game_state.begin_net_result_ceremony(data)
		"reveal":
			reveal_at_ms = float(data.get("at", -1.0))
		"push_fx":
			if not is_host:
				var pos: Array = data.get("pos", [0, 0, 0])
				var feet: Array = []
				for foot in data.get("feet", []):
					feet.append(Vector3(float(foot[0]), float(foot[1]), float(foot[2])))
				game_state.local_push_event.emit({
					"kind": str(data.get("kind", "")),
					"player": int(data.get("player", 0)),
					"direction": float(data.get("direction", 0.0)),
					"x": float(data.get("x", 0.0)),
					"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
					"feet": feet,
					"age": 0.0,
				})


func _on_resync(data: Dictionary) -> void:
	if is_host or game_state == null:
		return
	game_state.quiz_list.clear()
	for item in data.get("quizzes", []):
		if item is Dictionary:
			_on_quiz_received(item)
	var winners: Array = data.get("winners", [])
	for i in range(winners.size()):
		if int(winners[i]) >= 0:
			game_state.record_question_winner(i, int(winners[i]))
	var snap: Dictionary = data.get("snap", {})
	snap["kf"] = true
	_snap_state.clear()
	for buffer in _interp:
		buffer.clear()
	predictor.pending.clear()
	_scroll_ready = false
	_on_snapshot_received(snap)
	predictor.reset_from_state()
	predictor._load(_slot_motion(_snap_state, 2))
	_outbox = []
	_outbox_ticks = 0


# ===========================================================================
# Relay messages
# ===========================================================================

func _on_relay_message(msg_type: String, data: Dictionary) -> void:
	if not is_online:
		return
	match msg_type:
		"snap":
			_on_snapshot_received(data)
		"quiz":
			_on_quiz_received(data)
		"evt":
			_on_event_received(data)
		"resync":
			_on_resync(data)
		"finish":
			finished = true
		"cmd":
			if is_host:
				_on_commands(data)
		"req_resync":
			if is_host:
				_send_resync()
		"ready":
			if is_host:
				# phase が "loaded" はゲーム画面の準備ができた知らせ。開始の合図は "start"（なしも start とみなす）
				if str(data.get("phase", "start")) == "loaded":
					guest_loaded = true
				else:
					guest_ready = true


func _on_commands(data: Dictionary) -> void:
	_receive_ghost(data)
	for raw in data.get("c", []):
		if not raw is Array or raw.size() < 5:
			continue
		var seq := int(raw[0])
		if seq <= _acked_seq or (not _cmd_buffer.is_empty() and seq <= int(_cmd_buffer[-1][0])):
			continue
		var push: Array = []
		if raw.size() > 6 and raw[6] is Array:
			for event in raw[6]:
				if event is Array and event.size() >= 3 and absi(int(event[0])) == 1:
					push.append([int(event[0]), bool(event[1]), clampf(float(event[2]), 0.0, TICK)])
		var mask := clampi(int(raw[5]), 0, 3) if raw.size() > 5 else 0
		_cmd_buffer.append([seq, clampf(float(raw[1]), -1.0, 1.0), clampf(float(raw[2]), -1.0, 1.0), bool(raw[3]), clampi(int(raw[4]), 0, 63), mask, push])


# ===========================================================================
# Pause / reconnect / forfeit
# ===========================================================================

func _set_paused(value: bool, message: String = "") -> void:
	paused = value
	pause_message = message
	if not value:
		resume_countdown = 0.0
	pause_changed.emit(value, message)


func _on_peer_paused(_who: String, _grace: float) -> void:
	if finished:
		return
	_set_paused(true, "あいての つうしんを まっています…")


func _on_peer_resumed(_who: String) -> void:
	if finished:
		return
	if is_host:
		_send_resync()
		send_game_event("resume")
		_begin_resume_countdown()


func _on_self_resumed(_info: Dictionary) -> void:
	if finished:
		return
	if is_host:
		if NetworkManager.opponent_present:
			_send_resync()
			send_game_event("resume")
			_begin_resume_countdown()
		else:
			_set_paused(true, "あいてを まっています…")
	else:
		NetworkManager.send("req_resync")
		_set_paused(true, "じゅんびしています…")


func _on_network_state_changed(state: int) -> void:
	if state == NetworkManager.State.RECONNECTING and not finished:
		_set_paused(true, "つながりなおしています…")


func _begin_resume_countdown() -> void:
	paused = true
	resume_countdown = RESUME_COUNTDOWN
	pause_message = ""
	pause_changed.emit(true, "")


func _tick_resume_countdown(dt: float) -> void:
	if resume_countdown <= 0.0:
		return
	resume_countdown -= dt
	if resume_countdown <= 0.0:
		_set_paused(false)


func _on_forfeit(winner_role: String, _reason: String) -> void:
	finished = true
	var won := winner_role == NetworkManager.role()
	_set_paused(false)
	match_over.emit("あいてが いなくなったので\nあなたの かち！" if won else "しあいが おわりました")


func _on_reconnect_failed(reason: String) -> void:
	if finished:
		return
	finished = true
	_set_paused(false)
	match_over.emit("つうしんが きれました\n" + reason)


func _on_peer_left(_who: String) -> void:
	finished = true


func _on_server_restart() -> void:
	if finished:
		return
	finished = true
	match_over.emit("サーバーの メンテナンスで\nしあいが おわりました")
