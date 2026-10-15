class_name OnlineStagingDirector
extends Node

## オンライン対戦のマッチング演出の監督（docs/online_match_staging/spec.md の「4. 流れ」と S0〜S9）。
## 3D の舞台（OnlineHeliportStage）のヘリ・キャラ・カメラ・海と雲を、状態と時刻表で動かす。
## 通信・画面（UI）・ゲーム画面への切り替えは OnlineMenu が受け持ち、ここへは次のように伝える：
##   begin_departure()          マッチング開始（IDLE → BOARDING）
##   on_matched(slot, profile)  あいてが決まった（早めのマッチは近道で JOIN へ）
##   reset_to_idle()            やめる・失敗・時間切れ（暗転の下で呼ぶ。D4）
##   requeue()                  合流のあとカットインが終わる前に相手がいなくなった（D12）
##   loaded / start_ready       CUTIN_HOLD を出る条件（読み込み済み・開始の合図）
## 監督からはシグナルで知らせる（下）。時刻・カメラ・速さは OnlineStagingTimeline だけに置く。

signal state_changed(state: int)
## 乗り込みが始まった（左の列を隠す）
signal departure_started
## 検索中の飛行に入った（下の帯を出す。ゲーム画面の読み込みを始める：D9）
signal cruise_started
## 合流が始まった（「あいてが みつかった！」。ゲストなら「きみは ブルー」）
signal join_started(is_guest: bool)
## 並走の終わり：カットインを出す
signal cutin_started
## カットインが入りきった：ホストは開始の合図（start）を送る
signal hold_started
## 読み込みの最短の長さがたち、読み込み済みで、開始の合図がそろった：ゲーム画面へ切り替える（SWAP）
signal swap_ready
## 探し直しで相手のヘリが去り、検索中の飛行に戻った
signal requeue_finished
## 効果音の時刻になった（OnlineStagingTimeline.SFX_TIMES。鳴らすかどうかは SFX_ENABLED）
signal sfx_cue(cue: StringName)

enum State { IDLE, BOARDING, COCKPIT, TAKEOFF, CLIMB, CRUISE, JOIN, FORMATION, CUTIN_IN, CUTIN_HOLD, SWAP, REQUEUE }

const T = preload("res://scripts/world/online_staging/online_staging_timeline.gd")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const Shots = preload("res://scripts/world/online_staging/staging_shots.gd")
const STATE_NAMES := ["IDLE", "BOARDING", "COCKPIT", "TAKEOFF", "CLIMB", "CRUISE", "JOIN", "FORMATION", "CUTIN_IN", "CUTIN_HOLD", "SWAP", "REQUEUE"]
const UAL1 := AnimationRig.SLOT_UAL

var stage: OnlineHeliportStage
var camera_rig: StagingCameraRig
var state: State = State.IDLE
## 今の状態に入ってからの時間（秒、速さを掛けたあと）
var state_time := 0.0
## 「みじかい」演出（D11）
var short_mode := false
## CUTIN_HOLD を出る条件
var loaded := false
var start_ready := false
## 相手の通信が止まっていない（peer_paused のあいだは false。CUTIN_HOLD から先へ進まない）
var peer_ok := true
## 自分のスロット（1 / 2）と相手の見た目（matched で決まる）
var my_slot := 1
var their_profile: Dictionary = {}
## 1 回目の探し直しを使ったか（D12）
var requeued_once := false

var _durations: Dictionary = T.durations(false)
var _speed := 1.0
var _matched_pending := false
var _lift_time := -1.0
## 離陸の長さ（入ったときに決める。乗り込みの途中でマッチしたら 1.0 秒）
var _takeoff_seconds := 1.6
var _early_takeoff := false
var _time := 0.0
## 乗り込みの時刻（BOARDING の始まりから。COCKPIT 以降も数える：ドア・ベルト・ローター）
var _board_time := -1.0
## 揺れない枠 F（自分のヘリの H のワールド）
var _frame := Transform3D.IDENTITY
var _flight := Transform3D.IDENTITY
var _cruise_time := 0.0
var _cruise_shot := 0
## 次のカメラの更新で切る（状態に入ったときに立てる。ショットの目標は、ヘリを置いたあとで作る）
var _camera_cut := false
## 次のカメラの更新から、この秒数でつなぐ（探し直しから検索中へ戻るとき）
var _camera_blend := 0.0
## 検索中のショットの時計のずらし（探し直しから戻るときは CR_Hero から始める）
var _cruise_offset := 0.0
## ぼけ（被写界深度）を決めた画質
var _camera_quality := ""
var _formation_back := 0.0
var _head_timer := 0.0
## 今のカメラのショットの名前（F7 のデバッグ表示）
var shot_name := ""
## Enter／A で、今の状態の終わりまで 2 倍速（仕様書 14）
var _hurry := 1.0
## 3D の画面の暗さ（0＝そのまま、1＝真っ黒）。OnlineMenu が 3D の上の黒い板に当てる（急発進のあとの暗転・明け）
var fade := 0.0
var _fade_in_seconds := 0.0
var _fade_in_time := 0.0
var _fade_in_from := 0.0
## 急発進で点火したか（CLIMB）
var _boost_ignited := false
## 相手のヘリがジェットを切った JOIN の時刻（-1 はまだ）
var _their_jets_off_at := -1.0
## 画面を開いた直後の数フレーム、3D を黒く覆ったままジェットの炎を描いておく（点火のときにシェーダーを作らない）
var _prewarm_frames := 0
## 自分のキャラの今の動きの区切り（"idle"・"walk"・"sit"・"drive"）と、それを動かしている人形（つなぎ：T.CAST_BLEND）
var _cast_segment := ""
var _cast_puppet: StagingPuppet = null
const PREWARM_FRAMES := 3
const PREWARM_THEIR_POSITION := Vector3(12.0, 2.0, 11.0)


func setup(p_stage: OnlineHeliportStage) -> void:
	stage = p_stage
	camera_rig = StagingCameraRig.new(stage.camera)
	reset_to_idle()
	_prewarm_frames = PREWARM_FRAMES
	stage.my_heli.set_jet_prewarm(true)
	# 相手のヘリも待機のカメラに入る所（パッドの右うしろの海の上）で一度描く（合流で初めて描くと止まる）
	stage.their_heli.visible = true
	stage.their_heli.transform = stage.pad_ground * Transform3D(Basis.IDENTITY, PREWARM_THEIR_POSITION)
	stage.their_heli.set_jet_prewarm(true)
	fade = 1.0


func state_name() -> String:
	return STATE_NAMES[state]


func duration(key: String) -> float:
	return float(_durations.get(key, 0.0))


# ---------- 外からの合図 ----------

func begin_departure() -> void:
	if state != State.IDLE:
		return
	_durations = T.durations(short_mode)
	_speed = T.SHORT_BOARDING_SPEED if short_mode else 1.0
	_matched_pending = false
	_board_time = 0.0
	_enter(State.BOARDING)
	departure_started.emit()


## あいてが決まった。slot：自分のスロット（ホスト 1・ゲスト 2）。profile：相手の hat など。
func on_matched(slot: int, profile: Dictionary) -> void:
	my_slot = 2 if slot == 2 else 1
	their_profile = profile
	match state:
		State.BOARDING:
			_matched_pending = true
			_speed = T.EARLY_BOARDING_SPEED
		State.COCKPIT, State.TAKEOFF:
			_matched_pending = true
			_speed = T.EARLY_TAKEOFF_SPEED
		State.CLIMB, State.CRUISE, State.REQUEUE:
			_enter_join()
		State.IDLE:
			# 乗り込みを飛ばして（テストやともだちのコードがすぐ通ったとき）、合流から始める
			_board_time = 9.0
			_enter_join()


## やめる・失敗・時間切れ：すべてを待機に戻す（OnlineMenu が暗転の下で呼ぶ。D4）。
func reset_to_idle() -> void:
	_durations = T.durations(short_mode)
	_speed = 1.0
	_matched_pending = false
	_lift_time = -1.0
	_board_time = -1.0
	loaded = false
	start_ready = false
	peer_ok = true
	my_slot = 1
	requeued_once = false
	stage.set_flow(false)
	stage.set_my_slot(1)
	stage.them().set_visible(false)
	stage.me().set_visible(true)
	stage.their_heli.visible = false
	stage.their_heli.set_process(false)
	stage.my_heli.transform = stage.pad_ground
	stage.my_heli.park_rotor()
	stage.my_heli.set_door("L", 0.0)
	stage.my_heli.set_belt("L", 0.0)
	stage.windsock_tension = 0.0
	stage.set_splash(0.0, Vector3.ZERO, 0.0, 0.0)
	_stow_jets(stage.my_heli)
	_stow_jets(stage.their_heli)
	# Reset happens under the menu fade: discard the engine tails immediately.
	for heli: OnlineHeliportHelicopter in [stage.my_heli, stage.their_heli]:
		if heli.sound != null:
			heli.sound.stop()
	_boost_ignited = false
	_their_jets_off_at = -1.0
	fade = 0.0
	_fade_in_seconds = 0.0
	if stage.my_heli.pilot != null:
		stage.my_heli.pilot.play(&"sit_idle")
	_frame = stage.pad_ground
	_flight = Transform3D.IDENTITY
	_enter(State.IDLE)
	_camera_cut = false
	_camera_blend = 0.0
	camera_rig.follow_lag = 0.0
	camera_rig.cut("CAM_Idle", stage.pad_ground)
	_update(0.0)


## 相手がいなくなった（合流〜カットインの前）。1 回目は空のまま探し直す、2 回目は false（呼ぶ側がホームへ戻す）。
func requeue() -> bool:
	if requeued_once:
		return false
	requeued_once = true
	loaded = false
	start_ready = false
	_enter(State.REQUEUE)
	return true


## Enter／A：乗り込み〜上昇のあいだ、今の状態の終わりまで 2 倍速。
func hurry() -> void:
	if state in [State.BOARDING, State.COCKPIT, State.TAKEOFF, State.CLIMB]:
		_hurry = 2.0


func is_flying() -> bool:
	return state >= State.TAKEOFF


## 出口の状態か（JOIN 以降。やめるは出さない）。
func is_committed() -> bool:
	return state >= State.JOIN and state != State.REQUEUE


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if stage == null:
		return
	_update(delta)


func _update(delta: float) -> void:
	_time += delta
	if _prewarm_frames > 0:
		_prewarm_frames -= 1
		if _prewarm_frames == 0:
			stage.my_heli.set_jet_prewarm(false)
			stage.their_heli.set_jet_prewarm(false)
			if state == State.IDLE:
				stage.their_heli.visible = false
	# 速さ（みじかい演出・早めのマッチ）は乗り込み・操縦席・離陸に掛ける（離陸に入るときに決め直す）
	var dt := delta * (_speed if state in [State.BOARDING, State.COCKPIT, State.TAKEOFF] else 1.0) * _hurry
	state_time += dt
	if _board_time >= 0.0:
		_board_time += dt
	match state:
		State.IDLE:
			_frame = stage.pad_ground
		State.BOARDING:
			_frame = stage.pad_ground
			if _board_time >= float(T.DURATIONS.normal.BOARDING):
				if _matched_pending or duration("COCKPIT") <= 0.0:
					_enter(State.TAKEOFF)
				else:
					_enter(State.COCKPIT)
		State.COCKPIT:
			_frame = stage.pad_ground
			if state_time >= duration("COCKPIT"):
				_enter(State.TAKEOFF)
		State.TAKEOFF:
			_frame = stage.pad_ground
			var seconds := _takeoff_seconds
			var lift_u := _lift_seconds() / seconds
			var u := state_time / seconds
			_flight = StagingFlight.departure(state_time, _lift_seconds(), _departure_pre())
			if _lift_time < 0.0 and u >= lift_u:
				_lift_time = state_time
			if _matched_pending and _lift_time >= 0.0 and state_time - _lift_time >= T.EARLY_LIFT_TO_JOIN:
				_enter_join()
			elif state_time >= seconds:
				_enter(State.CLIMB)
		State.CLIMB:
			_frame = stage.pad_ground
			var seconds := duration("CLIMB")
			var u := state_time / maxf(seconds, 0.001)
			# 離陸からそのまま続く道すじ（ホバーで止まらない）
			_flight = StagingFlight.departure(_takeoff_seconds + state_time, _lift_seconds(), _departure_pre())
			_update_boost(u)
			if _matched_pending:
				_enter_join()
			elif state_time >= seconds:
				_enter(State.CRUISE)
		State.CRUISE:
			_advance_cruise(delta)
		State.JOIN:
			_advance_cruise(delta)
			if state_time >= duration("JOIN"):
				_enter(State.FORMATION)
		State.FORMATION:
			_advance_cruise(delta)
			_formation_back += delta * T.FORMATION_DOLLY_BACK
			if state_time >= duration("FORMATION"):
				_enter(State.CUTIN_IN)
		State.CUTIN_IN:
			_advance_cruise(delta)
			_formation_back += delta * T.FORMATION_DOLLY_BACK
			if state_time >= duration("CUTIN_IN"):
				_enter(State.CUTIN_HOLD)
		State.CUTIN_HOLD:
			_advance_cruise(delta)
			_formation_back += delta * T.FORMATION_DOLLY_BACK
			if state_time >= duration("CUTIN_HOLD_MIN") and loaded and start_ready and peer_ok:
				_enter(State.SWAP)
		State.SWAP:
			_advance_cruise(delta)
			_formation_back += delta * T.FORMATION_DOLLY_BACK
		State.REQUEUE:
			_advance_cruise(delta)
			# 去っていく相手はジェットを切って畳む
			if stage.their_heli.jets_ignited:
				stage.their_heli.extinguish_jets()
				stage.their_heli.rotor_speed_factor = 1.0
			stage.their_heli.set_jet_charge(maxf(stage.their_heli.jet_charge() - delta / float(T.JOIN.fold_seconds), 0.0))
			if state_time >= T.REQUEUE_LEAVE_SECONDS:
				stage.their_heli.visible = false
				stage.them().set_visible(false)
				_enter(State.CRUISE)
				requeue_finished.emit()
	# swap_ready でゲーム画面へ切り替えると、この画面はもうツリーにない（以降の 3D の更新はしない）
	if not is_inside_tree():
		return
	_update_fade(delta)
	_place_helicopters()
	_animate_cast(delta, dt)
	_update_camera(delta)
	_emit_sfx(dt)


## 離陸で浮き始める秒（乗り込みの途中でマッチした 1.0 秒の離陸は 0.15 秒）。
func _lift_seconds() -> float:
	return 0.15 if _early_takeoff else 0.2


## 浮いてから点火（CLIMB の BOOST.charge_end）までの秒。
func _departure_pre() -> float:
	return maxf(_takeoff_seconds - _lift_seconds(), 0.0) + duration("CLIMB") * StagingFlight.boost_ignite_u()


## S4 急発進：旋回しながら上がるあいだにポッドを広げて溜め（機体ごと震える）、点火で炎を出してローターを速め、カメラに一度だけ手ごたえを伝える。
func _update_boost(u: float) -> void:
	var heli := stage.my_heli
	var charge := StagingFlight.boost_charge(u)
	var b: Dictionary = T.BOOST
	if u < StagingFlight.boost_ignite_u():
		heli.set_jet_charge(charge)
		heli.rotor_speed_factor = lerpf(1.0, float(b.rotor_factor_charge), charge)
		_flight.origin += StagingFlight.boost_shudder(state_time, charge)
	elif not _boost_ignited:
		_boost_ignited = true
		heli.ignite_jets(true)
		heli.rotor_speed_factor = float(b.rotor_factor_boost)
		camera_rig.kick(1.0)
		sfx_cue.emit(&"jet_ignite")


## 相手のヘリ（JOIN）：ジェットブーストで飛び込み、JOIN.jets_off で炎を切って、ポッドを畳む。
func _update_their_jets() -> void:
	var heli := stage.their_heli
	var j: Dictionary = T.JOIN
	var u := state_time / maxf(duration("JOIN"), 0.001)
	if _their_jets_off_at < 0.0:
		if u >= float(j.jets_off):
			_their_jets_off_at = state_time
			heli.extinguish_jets()
			heli.rotor_speed_factor = 1.0
		return
	heli.set_jet_charge(1.0 - clampf((state_time - _their_jets_off_at) / float(j.fold_seconds), 0.0, 1.0))


## 暗転：CLIMB の終わりで黒く、検索中（や早めのマッチの合流）に入ったら明ける。
func _update_fade(delta: float) -> void:
	if state == State.CLIMB:
		var b: Dictionary = T.BOOST
		fade = smoothstep(float(b.fade_start), float(b.fade_end), state_time / maxf(duration("CLIMB"), 0.001))
	elif _fade_in_seconds > 0.0:
		_fade_in_time += delta
		var k := clampf(_fade_in_time / _fade_in_seconds, 0.0, 1.0)
		fade = _fade_in_from * (1.0 - smoothstep(0.0, 1.0, k))
		if k >= 1.0:
			_fade_in_seconds = 0.0
	elif _prewarm_frames > 0:
		fade = 1.0
	else:
		fade = 0.0


func _begin_fade_in(seconds: float) -> void:
	if fade <= 0.001:
		fade = 0.0
		_fade_in_seconds = 0.0
		return
	_fade_in_from = fade
	_fade_in_time = 0.0
	_fade_in_seconds = seconds


## ジェットをしまう（炎を消し、ポッドを畳み、ローターをふつうの速さに）。
func _stow_jets(heli: OnlineHeliportHelicopter) -> void:
	if heli == null:
		return
	heli.stow_jets()
	heli.rotor_speed_factor = 1.0


func _emit_sfx(dt: float) -> void:
	var name: String = STATE_NAMES[state]
	var t := state_time if name != "BOARDING" else _board_time
	for cue: Array in T.SFX_TIMES:
		if cue[0] == name and t - dt < float(cue[1]) and t >= float(cue[1]):
			sfx_cue.emit(StringName(cue[2]))
			if T.SFX_ENABLED:
				AudioManager.play_sfx(StringName(cue[2]))


func _advance_cruise(delta: float) -> void:
	_cruise_time += delta
	stage.advance_flow(float(T.CRUISE.speed) * delta)
	_frame = _flow_frame()
	_flight = StagingFlight.cruise_sway(_cruise_time)


func _flow_frame() -> Transform3D:
	var ground := stage.pad_ground
	return Transform3D(ground.basis, Vector3(0.0, ground.origin.y + float(T.CRUISE.altitude), 0.0))


func _enter_join() -> void:
	# 検索中の飛行より前にマッチした（早めのマッチ）ら、合流・並走・読み込みの最短を「みじかい」の長さにする（マッチから開くまでを短く）
	if state in [State.IDLE, State.BOARDING, State.COCKPIT, State.TAKEOFF, State.CLIMB]:
		var quick: Dictionary = T.durations(true)
		_durations = _durations.duplicate()
		_durations["JOIN"] = quick.JOIN
		_durations["FORMATION"] = quick.FORMATION
		_durations["CUTIN_HOLD_MIN"] = quick.CUTIN_HOLD_MIN
	_matched_pending = false
	_speed = 1.0
	_board_time = maxf(_board_time, 9.0)
	if not stage.flow_enabled:
		stage.set_flow(true, -stage.pad_ground.basis.z)
	_frame = _flow_frame()
	_flight = StagingFlight.cruise_sway(_cruise_time)
	var their_skin: Variant = their_profile.get("skin", "")
	stage.set_my_slot(my_slot, int(their_profile.get("hat", 0)), their_skin if their_skin is String else "")
	# 自分のジェットは切る（合流のあと・検索中は使わない）。相手はジェットブーストで飛び込んでくる
	_stow_jets(stage.my_heli)
	stage.their_heli.visible = true
	stage.their_heli.set_process(true)
	stage.their_heli.spool = 1.0
	stage.their_heli.spool_target = 1.0
	stage.their_heli.enable_jets()
	stage.their_heli.stow_jets()
	stage.their_heli.ignite_jets()
	stage.their_heli.rotor_speed_factor = float(T.BOOST.rotor_factor_boost)
	_their_jets_off_at = -1.0
	_begin_fade_in(float(T.JOIN_FADE_IN))
	stage.them().set_visible(true)
	stage.me().set_visible(true)
	_enter(State.JOIN)
	join_started.emit(my_slot == 2)


func _enter(next: State) -> void:
	var previous := state
	state = next
	state_time = 0.0
	# 検索中（マッチング待機）のあいだだけ、自機のヘリの音を下げる。
	if stage != null and stage.my_heli != null and stage.my_heli.sound != null:
		stage.my_heli.sound.waiting = next == State.CRUISE
	_hurry = 1.0
	match next:
		State.COCKPIT:
			camera_rig.follow_lag = 0.0
			_camera_cut = true
		State.TAKEOFF:
			_lift_time = -1.0
			_early_takeoff = _matched_pending and previous == State.BOARDING
			if _early_takeoff:
				# 乗り込みの途中でマッチ：操縦席を飛ばし、離陸を 1.0 秒にして、浮いて 0.8 秒で合流
				_takeoff_seconds = T.EARLY_TAKEOFF_SECONDS
				_speed = 1.0
			else:
				_takeoff_seconds = duration("TAKEOFF")
				if not _matched_pending:
					_speed = 1.0
			stage.my_heli.spool_target = 1.0
			stage.windsock_tension = 1.0
			camera_rig.follow_lag = 0.0
			_camera_cut = true
			if stage.my_heli.pilot != null:
				stage.my_heli.pilot.play(&"steer")
		State.CLIMB:
			# 離陸の画から切らずに続ける（MOVE_BOOST の最初の点＝MOVE_TAKEOFF の終わり）
			camera_rig.follow_lag = 0.0
			_boost_ignited = false
			stage.my_heli.enable_jets()
			stage.my_heli.stow_jets()
		State.CRUISE:
			if not stage.flow_enabled:
				stage.set_flow(true, -stage.pad_ground.basis.z)
			stage.set_splash(0.0, Vector3.ZERO, 0.0, 0.0)
			# 検索中はジェットを切る（暗転の下で、炎もポッドも今すぐしまう）
			_stow_jets(stage.my_heli)
			if previous == State.CLIMB:
				_begin_fade_in(float(T.CRUISE_FADE_IN))
			_frame = _flow_frame()
			_flight = StagingFlight.cruise_sway(_cruise_time)
			camera_rig.follow_lag = 0.0
			# 上昇からは切る（動きの途中で切る）。探し直しからは、並走の画（正面）からいちばん近い左前のショットへつなぐ
			if previous == State.REQUEUE:
				_cruise_shot = int(T.REQUEUE_CRUISE_SHOT)
				_camera_blend = float(T.REQUEUE_CAMERA_BLEND)
			else:
				_cruise_shot = 0
				_camera_cut = true
			_cruise_offset = float(_cruise_shot) * float(T.CRUISE_SHOT_SECONDS)
			if previous != State.REQUEUE:
				cruise_started.emit()
		State.JOIN:
			_camera_cut = true
			_camera_blend = 0.0
			camera_rig.follow_lag = 0.0
			if stage.my_heli.pilot != null:
				stage.my_heli.pilot.play(&"steer")
		State.FORMATION:
			_formation_back = 0.0
			# 並走に入ったら相手のジェットも必ず切れている
			if stage.their_heli.jets_ignited or stage.their_heli.jet_charge() > 0.0:
				_stow_jets(stage.their_heli)
			camera_rig.blend_to("CAM_Formation", _frame, duration("FORMATION"))
		State.CUTIN_IN:
			cutin_started.emit()
		State.CUTIN_HOLD:
			hold_started.emit()
		State.SWAP:
			swap_ready.emit()
	state_changed.emit(next)


# ---------- ヘリ ----------

func _place_helicopters() -> void:
	stage.my_heli.transform = _frame * _flight
	# ローター：乗り込みの 3.20 秒から回り始める（仕様書 S2）
	if state == State.IDLE:
		stage.my_heli.spool_target = 0.0
	elif _board_time >= float(T.DURATIONS.normal.BOARDING) + float(T.COCKPIT.rotor_start_from_boarding_end):
		stage.my_heli.spool_target = 1.0
	# ドア：0.00 から 0.6 秒で開く（だんだん遅く）、3.00 から 0.6 秒で閉じる
	var b := _board_time
	var door := 0.0
	if b >= 0.0 and b < 9.0:
		var open := 1.0 - pow(1.0 - clampf((b - float(T.BOARD.door_open_at)) / 0.6, 0.0, 1.0), 3.0)
		var close := StagingCameraRig.ease_in_out_cubic(clampf((b - float(T.BOARD.door_close_at)) / 0.6, 0.0, 1.0))
		door = open * (1.0 - close)
	stage.my_heli.set_door("L", door)
	# ベルト：3.30 で 0.12 秒かけて出る
	stage.my_heli.set_belt("L", clampf((b - float(T.BOARD.belt_at)) / float(T.BOARD.belt_grow), 0.0, 1.0) if b >= float(T.BOARD.belt_at) else 0.0)
	# 水しぶき（離陸の 0〜1.8 秒）
	if state in [State.TAKEOFF, State.CLIMB]:
		var since := state_time if state == State.TAKEOFF else duration("TAKEOFF") + state_time
		var p := clampf((since - float(T.TAKEOFF.splash_start)) / (float(T.TAKEOFF.splash_end) - float(T.TAKEOFF.splash_start)), 0.0, 0.999)
		stage.set_splash(p, stage.pad_ground.origin, float(T.TAKEOFF.splash_r0), float(T.TAKEOFF.splash_r1))
	# 相手のヘリ
	if stage.their_heli.visible:
		var local := Transform3D.IDENTITY
		match state:
			State.JOIN:
				local = StagingFlight.join(state_time / maxf(duration("JOIN"), 0.001), duration("JOIN"))
				_update_their_jets()
			State.REQUEUE:
				local = StagingFlight.leave(state_time / T.REQUEUE_LEAVE_SECONDS)
			_:
				var sway := StagingFlight.cruise_sway(_cruise_time, T.FORMATION_SWAY_OFFSET)
				local = Transform3D(sway.basis, T.JOIN_PATH[T.JOIN_PATH.size() - 1] + sway.origin)
		if state == State.JOIN:
			# 着いてから自分の揺れに少しずつ合わせる
			var sway := StagingFlight.cruise_sway(_cruise_time, T.FORMATION_SWAY_OFFSET)
			var w := smoothstep(float(T.JOIN.arrive) - 0.1, 1.0, state_time / maxf(duration("JOIN"), 0.001))
			local = Transform3D(local.basis.slerp(sway.basis, w), local.origin + sway.origin * w)
		stage.their_heli.transform = _frame * local


# ---------- キャラとハテナ ----------

func _animate_cast(delta: float, board_dt: float) -> void:
	var me := stage.me()
	var heli := stage.my_heli
	var pilot := heli.pilot
	var b := _board_time
	_begin_cast_blend(me, b)
	if state == State.IDLE or b < 0.0:
		_pose_idle(me, heli)
		if pilot != null:
			pilot.play(&"sit_idle")
			# 12 秒ごとにプレイヤーの方を見る（0.6 秒で向き、2 秒見てから戻る）
			_head_timer += delta
			pilot.head_side = -1.0 if fmod(_head_timer, 12.0) > 9.4 and fmod(_head_timer, 12.0) < 11.4 else 0.0
	elif b < float(T.BOARD.sit_end):
		_pose_boarding(me, heli, b)
		if pilot != null:
			pilot.play(&"wave" if b < float(T.BOARD.wave_end) else &"sit_idle")
			pilot.head_side = -1.0 if b < float(T.BOARD.sit_end) else 0.0
	else:
		_pose_seated(me, heli)
		if pilot != null and state == State.COCKPIT:
			var cp: Dictionary = T.COCKPIT
			pilot.head_side = 0.0
			pilot.play(&"point" if state_time >= float(cp.point_start) and state_time < float(cp.point_end) else &"sit_idle")
		elif pilot != null and state == State.BOARDING:
			pilot.head_side = 0.0
	me.apply_blend(board_dt)
	if stage.their_heli.visible:
		_pose_seated(stage.them(), stage.their_heli)
		if stage.their_heli.pilot != null:
			stage.their_heli.pilot.play(&"steer")


## 自分のキャラの動きの区切り（S1 の時刻表）。
func _cast_segment_at(b: float) -> String:
	if state == State.IDLE or b < float(T.BOARD.turn_end):
		return "idle"
	if b < float(T.BOARD.turn_seat_end):
		return "walk"
	if b < float(T.BOARD.sit_end):
		return "sit"
	return "drive"


## 区切りが変わったら、前の動きの最後の姿から新しい動きへつなぐ（立つ → 歩く → 座る → ハンドルを握る）。
## 待機へ戻す・乗り込みを飛ばすなどの飛びはつながない。人形が替わったとき（スロットの入れ替え）もつながない。
func _begin_cast_blend(me: StagingPuppet, b: float) -> void:
	var segment := _cast_segment_at(b)
	if me != _cast_puppet:
		if _cast_puppet != null:
			_cast_puppet.cancel_blend()
		me.cancel_blend()
		_cast_puppet = me
		_cast_segment = segment
		return
	if segment == _cast_segment:
		return
	var seconds := float(T.CAST_BLEND.get("%s>%s" % [_cast_segment, segment], 0.0))
	_cast_segment = segment
	if seconds > 0.0:
		me.begin_blend(seconds)
	else:
		me.cancel_blend()


func _pose_idle(me: StagingPuppet, heli: OnlineHeliportHelicopter) -> void:
	var spot := heli.marker("MK_IdleSpot")
	me.pose("Idle_Loop", fposmod(_time / maxf(me.clip_length("Idle_Loop"), 0.1), 1.0))
	me.stand_at(heli.global_transform * spot.origin, _idle_yaw(heli), (heli.global_transform * spot.origin).y)


## 待機の向き：カメラの方を向き、そこからヘリの方へ 30° 回す（仕様書 S0）。H の向き。
func _idle_yaw(heli: OnlineHeliportHelicopter) -> float:
	var spot := heli.marker_position("MK_IdleSpot")
	var cam: Vector3 = (OnlineStagingTimeline.camera("CAM_Idle").pos as Vector3)
	var to_cam := atan2(cam.x - spot.x, cam.z - spot.z)
	var to_heli := atan2(-spot.x, 0.0)
	var turn := clampf(wrapf(to_heli - to_cam, -PI, PI), -deg_to_rad(30.0), deg_to_rad(30.0))
	return to_cam + turn + heli.global_basis.get_euler().y


## S1 乗り込み：設計図の図 6 の時刻表。目印の間を動かし、足の裏を床・ステップに合わせる。
func _pose_boarding(me: StagingPuppet, heli: OnlineHeliportHelicopter, b: float) -> void:
	var B: Dictionary = T.BOARD
	var xf := heli.global_transform
	var heli_yaw := xf.basis.get_euler().y
	var idle := heli.marker_position("MK_IdleSpot")
	var stand := heli.marker_position("MK_BoardStand")
	var step := heli.marker_position("MK_Step")
	var sill := heli.marker_position("MK_DoorSill")
	var front := heli.marker_position("MK_SeatFront")
	var seat := heli.marker("MK_SeatPassenger")
	var face_heli := deg_to_rad(90.0)
	var walk_len := maxf(me.clip_length("Walk_Loop"), 0.1)
	var t_turn := float(B.turn_end)
	var t_walk := float(B.walk_end)
	var t_s1 := float(B.step1_end)
	var t_s2 := float(B.step2_end)
	var t_seat := float(B.turn_seat_end)
	var t_sit := float(B.sit_end)
	if b < t_turn:
		var u := b / t_turn
		me.pose("Idle_Loop", fposmod(_time / maxf(me.clip_length("Idle_Loop"), 0.1), 1.0))
		var yaw := lerp_angle(_idle_yaw(heli) - heli_yaw, face_heli, smoothstep(0.0, 1.0, u))
		me.stand_at(xf * idle, yaw + heli_yaw, (xf * idle).y)
	elif b < t_walk:
		var u := (b - t_turn) / (t_walk - t_turn)
		me.pose("Walk_Loop", fposmod((b - t_turn) * float(B.walk_rate) / walk_len, 1.0))
		var p := idle.lerp(stand, u)
		me.stand_at(xf * p, face_heli + heli_yaw, (xf * p).y)
	elif b < t_s1:
		var u := (b - t_walk) / (t_s1 - t_walk)
		me.pose("Walk_Loop", fposmod((b - t_turn) * float(B.walk_rate) / walk_len, 1.0))
		var p := stand.lerp(step, u)
		p.y = lerpf(stand.y, step.y, smoothstep(0.1, 0.8, u))
		me.stand_at(xf * p, face_heli + heli_yaw, (xf * p).y)
	elif b < t_s2:
		var u := (b - t_s1) / (t_s2 - t_s1)
		var crouch_len := maxf(me.clip_length("Crouch_Fwd_Loop"), 0.1)
		me.pose_blend("Walk_Loop", fposmod((b - t_turn) * float(B.walk_rate) / walk_len, 1.0),
			"Crouch_Fwd_Loop", fposmod((b - t_s1) / crouch_len, 1.0), float(B.crouch_mix) * smoothstep(0.0, 0.6, u))
		var p := step.lerp(sill, u)
		p.y = lerpf(step.y, sill.y, smoothstep(0.1, 0.8, u))
		me.stand_at(xf * p, face_heli + heli_yaw, (xf * p).y)
	elif b < t_seat:
		var u := (b - t_s2) / (t_seat - t_s2)
		var crouch_len := maxf(me.clip_length("Crouch_Fwd_Loop"), 0.1)
		me.pose_blend("Walk_Loop", fposmod((b - t_turn) * float(B.walk_rate) / walk_len, 1.0),
			"Crouch_Fwd_Loop", fposmod((b - t_s1) / crouch_len, 1.0), float(B.crouch_mix))
		var p := sill.lerp(front, smoothstep(0.0, 1.0, u))
		var yaw := lerp_angle(face_heli, deg_to_rad(180.0), smoothstep(0.0, 1.0, u))
		me.stand_at(xf * p, yaw + heli_yaw, (xf * p).y)
	else:
		var u := clampf((b - t_seat) / (t_sit - t_seat), 0.0, 1.0)
		me.pose("Sitting_Enter", u)
		var p := front.lerp(seat.origin, smoothstep(0.15, 0.9, u))
		var yaw := deg_to_rad(180.0)
		me.stand_at(xf * p, yaw + heli_yaw, (xf * front).y, Basis.IDENTITY)
		# 最後の 4 割で、座った位置（目印）へ pelvis を寄せる
		var w := smoothstep(0.6, 1.0, u)
		if w > 0.0:
			var pelvis := me.parts().get("pelvis") as Node3D
			if pelvis != null:
				var target := xf * seat.origin
				pelvis.global_position = pelvis.global_position.lerp(target, w)


func _pose_seated(puppet: StagingPuppet, heli: OnlineHeliportHelicopter) -> void:
	var length := maxf(puppet.clip_length("Driving_Loop"), 0.1)
	puppet.pose("Driving_Loop", fposmod(_time / length, 1.0))
	puppet.sit_at(heli.global_transform * heli.marker("MK_SeatPassenger"))


# ---------- カメラ ----------

func _update_camera(delta: float) -> void:
	if stage.quality != _camera_quality:
		_camera_quality = stage.quality
		camera_rig.set_dof_level(dof_level_for(_camera_quality))
	var target := {}
	shot_name = {State.IDLE: "CAM_Idle", State.REQUEUE: "CAM_Formation"}.get(state, "CAM_Formation")
	var heli := stage.my_heli.global_transform
	var aspect := _aspect()
	match state:
		State.IDLE:
			target = StagingCameraRig.shot_world("CAM_Idle", stage.pad_ground, _idle_drift())
		State.BOARDING:
			var idle := StagingCameraRig.shot_world("CAM_Idle", stage.pad_ground, _idle_drift())
			target = Shots.board(state_time, stage.pad_ground, idle, stage.me().center(), aspect)
		State.COCKPIT:
			target = Shots.cockpit(state_time / maxf(duration("COCKPIT"), 0.001), stage.pad_ground, heli, aspect)
		State.TAKEOFF:
			target = Shots.takeoff(state_time / maxf(_takeoff_seconds, 0.001), stage.pad_ground, heli, aspect)
		State.CLIMB:
			target = Shots.boost(state_time / maxf(duration("CLIMB"), 0.001), stage.pad_ground, heli, aspect)
		State.CRUISE:
			target = Shots.cruise(state_time + _cruise_offset, _frame, heli, aspect)
			var index := int(target.index)
			if index != _cruise_shot:
				_cruise_shot = index
				if bool(target.cut):
					_camera_cut = true
		State.JOIN:
			target = Shots.join(state_time / maxf(duration("JOIN"), 0.001), _frame, aspect)
		State.FORMATION, State.CUTIN_IN, State.CUTIN_HOLD, State.SWAP:
			var shot := StagingCameraRig.shot_world("CAM_Formation", _frame)
			var dir := ((shot.look as Vector3) - (shot.pos as Vector3)).normalized()
			target = {"pos": (shot.pos as Vector3) - dir * _formation_back, "look": shot.look, "fov": shot.fov}
		State.REQUEUE:
			target = StagingCameraRig.shot_world("CAM_Formation", _frame)
	if target.is_empty():
		return
	shot_name = str(target.get("name", shot_name))
	if _camera_cut:
		_camera_cut = false
		camera_rig.cut_to(target)
	elif _camera_blend > 0.0:
		camera_rig.blend_to_target(target, _camera_blend)
		_camera_blend = 0.0
	camera_rig.update(delta, target)


## 画質ごとのぼけ：低＝なし、ふつう＝奥だけ、高・最高＝手前と奥。
static func dof_level_for(quality: String) -> int:
	match quality:
		QualityRules.LOW:
			return 0
		QualityRules.BALANCED:
			return 1
	return 2


## 3D の画面の横/縦（SubViewport の大きさ。構図の計算に使う）。
func _aspect() -> float:
	var viewport := stage.camera.get_viewport() if stage.camera != null and stage.camera.is_inside_tree() else null
	if viewport == null:
		return 16.0 / 9.0
	var size := viewport.get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0


## S0 のゆっくりした揺れ（カメラの右と上へ）。
func _idle_drift() -> Vector3:
	var d: Dictionary = T.IDLE_DRIFT
	var basis := stage.pad_ground.basis
	return basis.x * sin(TAU * _time / float(d.period_x)) * float(d.amp_x) + Vector3.UP * sin(TAU * _time / float(d.period_y)) * float(d.amp_y)
