extends "res://tests/pv_capture/pv_s09_runtime.gd"

## PV S09 を「人が遊んだ試合」で撮る（2026-10-22 夜、ユーザーの指示）。台本 s09 の自動の動きは使わず、2 人がキーボード 1 つで遊んだ
## キー入力を記録して、同じキーを同じコマで送り直し、本番の画質で撮り直す。問題・乱数・見た目・ゲームの設定は台本 s09 と同じ。
##   1. 記録（人が遊ぶ。窓が実時間の 1 秒 60 コマで動き、押したキーをコマごとに inputs.json に書く。絵は保存しない）：
##      Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s09_play mode=record quality=ultra tag=s09_play_rec
##   2. 流し直し（本番の画質。sub=1 だけ：遊んだときと同じ 1 秒 60 コマで進めないと、押し合いの決着などがずれて別の試合になる）：
##      Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s09_play mode=replay inputs=s09_play_rec quality=ultra tag=s09_play_frames
## 流し直しは、毎フレームのゲームの状態（2 人の位置・ハート・壁・幽霊のサメ）の要約と受け取ったキーを記録と比べ、ずれたら failures に書く。
## 記録のときだけ：準備が終わるまでのキーと Esc（一時停止）はゲームへ渡さない（左上に「準備中」→「● REC」）。窓のフォーカスを外すと
## キーが離された扱いになって流し直しと合わなくなるので、遊んでいる間はほかの窓を触らない。
## 流し直しでは、幽霊がサメに乗ったあとの右下の小窓を隠す（台本 s09 の v1.8 と同じ。wipe_keep で出す）。
## 確かめ用：mode=record に test_driver を付けると、人の代わりに乱数でキーを押す（記録 → 流し直しが同じ試合になるかを見る）。

const FRAME_USEC := 16667                 # 記録のときの 1 コマ（実時間の 60 fps に合わせて待つ）
const INPUTS_FILE := "inputs.json"
const INPUTS_VERSION := 1
const PLAY_MAX_FRAMES := 7200             # 人が遊ぶので長めの上限（2 分）
## 準備の間から押しっぱなしのキーを、撮り始めのコマで押したことにする（ゲームが使うキー）
const WATCH_KEYS: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE, KEY_CTRL,
	KEY_1, KEY_2, KEY_3, KEY_8, KEY_9, KEY_0, KEY_ENTER]
const DRIVER_HOLD_KEYS: Array[Key] = [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]
const DRIVER_TAP_KEYS: Array[Key] = [KEY_SPACE, KEY_CTRL, KEY_1, KEY_8]

var play_mode := ""                       # "record" / "replay"
var inputs_ref := ""                      # 流し直す記録（記録のタグか、inputs.json のパス）
var test_driver := false
var _received: Array = []                 # 受け取ったキー [フレーム, keycode, physical, label, unicode, location, pressed, echo, shift, ctrl, alt, meta, 状態だけ]
var _digests: Array = []                  # 毎フレームのゲームの状態の要約 [フレーム, hash]
var _replay: Dictionary = {}
var _replay_events: Array = []
var _replay_i := 0
var _replay_digests: Dictionary = {}      # フレーム → hash
var _first_mismatch := -1
var _mismatches := 0
var _pace_last_usec := 0
var _late_frames := 0
var _wall_start_usec := 0
var _overlay: Label
var _driver_rng := RandomNumberGenerator.new()
var _driver_hold: Dictionary = {}         # キー → 離すフレーム


func _init() -> void:
	super._init()
	take_name = "s09_play"
	human = false
	ghost_hit = false


func _default_frames() -> int:
	return PLAY_MAX_FRAMES


func _parse_arg(arg: String) -> void:
	if arg.begins_with("mode="):
		play_mode = arg.trim_prefix("mode=")
	elif arg.begins_with("inputs="):
		inputs_ref = arg.trim_prefix("inputs=")
	elif arg == "test_driver":
		test_driver = true
	else:
		super._parse_arg(arg)
	human = false                          # 台本の人らしい動き・幽霊の自動の照準は使わない
	ghost_hit = false


func _setup() -> void:
	players = 2
	# 窓が画面に収まるよう縮められても、見える範囲を 16:9（1280x720 の基準）のままにする。見える範囲が変わると、
	# 幽霊のサメのビームの柱を画面に入れる計算（ghost_shark_ride_controller.gd）が変わり、流し直しとサメの位置がずれた（10/22 の記録で 3 m）
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if play_mode == "record":
		_show_overlay("準備中…  まだキーを押さないでください")
		if only_frames.is_empty():
			only_frames[-1] = true              # 記録のときは絵を保存しない（実時間で動かすため）
		_driver_rng.seed = pv_seed
	elif play_mode == "replay":
		_load_inputs()
		if sub != 1:
			failures.append("replay: sub=1（--fixed-fps 60）だけ。遊んだときと同じ細かさで進めないと別の試合になる")
	else:
		failures.append("mode=record か mode=replay を付ける")
	await super._setup()
	report["plan"]["per_question"] = "人が遊ぶ（キー入力の記録と流し直し）"
	report["play"] = {"mode": play_mode, "inputs": inputs_ref, "test_driver": test_driver}
	if play_mode == "replay" and not _replay.is_empty():
		_explicit_frames = true
		frame_count = int(_replay.get("frames", frame_count))


func _process(dt: float) -> void:
	_keep_input_first()
	super._process(dt)


## キーを GameWorld より先に受け取る（_input は木の後ろの子から順に届く）。準備中のキーと Esc を止めるため
func _keep_input_first() -> void:
	var root := get_tree().root
	if get_index() != root.get_child_count() - 1:
		root.move_child(self, -1)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or play_mode == "":
		return
	var key := event as InputEventKey
	if play_mode == "record" and (not _running or key.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()   # 準備中のキーと Esc（一時停止）はゲームへ渡さない
		return
	if not _running:
		return
	var state_only := event.has_meta("pv_state_only")
	_received.append([frame_of(_step + 1), int(key.keycode), int(key.physical_keycode), int(key.key_label), int(key.unicode),
		int(key.location), key.pressed, key.echo, key.shift_pressed, key.ctrl_pressed, key.alt_pressed, key.meta_pressed, state_only])
	if state_only:
		get_viewport().set_input_as_handled()   # 準備の間から押しっぱなしだったキー：押されている状態だけにする（記録のときと同じ）
		return
	if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and gs.game_state == Constants.STATE_WAITING_START and _find_event("enter_pressed") < 0:
		_event("enter_pressed")
		_show_overlay("● REC")


## 台本の自動のキーは押さない（Enter も人が押す）
func _keys_now() -> Dictionary:
	return {}


func _before_update(n: int) -> void:
	super._before_update(n)
	if play_mode == "record":
		if n == 1:
			_start_recording()
		if test_driver:
			_drive_test_keys(n)
	elif play_mode == "replay":
		while _replay_i < _replay_events.size() and int(_replay_events[_replay_i][0]) <= n:
			Input.parse_input_event(_key_event(_replay_events[_replay_i]))
			_replay_i += 1


func _start_recording() -> void:
	for key: Key in WATCH_KEYS:
		if Input.is_key_pressed(key):
			_received.append([1, int(key), int(key), int(key), 0, KEY_LOCATION_RIGHT if key == KEY_CTRL else KEY_LOCATION_UNSPECIFIED,
				true, false, false, false, false, false, true])
	_wall_start_usec = Time.get_ticks_usec()
	_show_overlay("● REC  ENTER でスタート（P1：A・D・Space・1/2/3　P2：←・→・右Ctrl・8/9/0）")


func _update(n: int, t: float, dt: float) -> void:
	super._update(n, t, dt)
	var digest := _state_digest()
	if play_mode == "record":
		_digests.append([n, digest])
		_pace_realtime()
	elif play_mode == "replay" and _replay_digests.has(n) and int(_replay_digests[n]) != digest:
		_mismatches += 1
		if _first_mismatch < 0:
			_first_mismatch = n


## 実時間の 1 秒 60 コマに合わせて待つ（土台は垂直同期とコマ数の上限を外している。描画が間に合わないコマはそのまま遅れる）
func _pace_realtime() -> void:
	var now := Time.get_ticks_usec()
	if _pace_last_usec > 0:
		var wait := FRAME_USEC - (now - _pace_last_usec)
		if wait > 0:
			OS.delay_usec(wait)
		else:
			_late_frames += 1
	_pace_last_usec = Time.get_ticks_usec()


## ゲームの状態の要約（流し直しが記録と同じ試合になっているかを毎フレーム比べる）
func _state_digest() -> int:
	var shark_pos := Vector3.ZERO
	var phase := -1
	if ride != null:
		phase = int(ride.get("phase"))
		var shark: Node3D = ride.get("_shark")
		if shark != null and is_instance_valid(shark):
			shark_pos = shark.global_position
	return hash(var_to_str([gs.game_state, gs.current_index, gs.get_player_hp(1), gs.get_player_hp(2),
		snappedf(gs.player_x, 0.0001), snappedf(gs.player_y, 0.0001), snappedf(gs.player_z, 0.0001),
		snappedf(gs.player2_x, 0.0001), snappedf(gs.player2_y, 0.0001), snappedf(gs.player2_z, 0.0001),
		snappedf(gs.wall_z, 0.0001), snappedf(gs.world_scroll_z, 0.0001), gs.p1_emote, gs.p2_emote, phase,
		snappedf(shark_pos.x, 0.001), snappedf(shark_pos.y, 0.001), snappedf(shark_pos.z, 0.001)]))


## 流し直しのときだけ、幽霊がサメに乗ったあとの右下の小窓を隠す（記録のときは遊ぶ人に見せる）
func _hide_wipe_after_mount(n: int) -> void:
	if play_mode != "replay" or not hide_wipe or ride == null:
		return
	if not _wipe_hidden and int(ride.get("phase")) >= GhostSharkRideController.Phase.MOUNTING:
		_wipe_hidden = true
		_event("wipe_hidden", {}, n)
	if _wipe_hidden:
		var layer := world.get_node_or_null("DeathWipeLayer") as CanvasLayer
		if layer != null and layer.visible:
			layer.visible = false


## 確かめ用：人の代わりに乱数でキーを押す（グローバルの乱数は使わない）
func _drive_test_keys(n: int) -> void:
	for key: Variant in _driver_hold.keys():
		if n >= int(_driver_hold[key]):
			_send_driver_key(key, false)
			_driver_hold.erase(key)
	if n == 120:
		_send_driver_key(KEY_ENTER, true)
		_driver_hold[KEY_ENTER] = n + 3
	if n < 400:
		return
	if _driver_rng.randf() < 0.06:
		var key: Key = DRIVER_HOLD_KEYS[_driver_rng.randi() % DRIVER_HOLD_KEYS.size()]
		if not _driver_hold.has(key):
			_send_driver_key(key, true)
			_driver_hold[key] = n + _driver_rng.randi_range(6, 50)
	if _driver_rng.randf() < 0.01:
		var tap: Key = DRIVER_TAP_KEYS[_driver_rng.randi() % DRIVER_TAP_KEYS.size()]
		if not _driver_hold.has(tap):
			_send_driver_key(tap, true)
			_driver_hold[tap] = n + 6


func _send_driver_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	if key == KEY_CTRL:
		event.location = KEY_LOCATION_RIGHT
	Input.parse_input_event(event)


func _key_event(row: Array) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = int(row[1]) as Key
	event.physical_keycode = int(row[2]) as Key
	event.key_label = int(row[3]) as Key
	event.unicode = int(row[4])
	event.location = int(row[5]) as KeyLocation
	event.pressed = bool(row[6])
	event.echo = bool(row[7])
	event.shift_pressed = bool(row[8])
	event.ctrl_pressed = bool(row[9])
	event.alt_pressed = bool(row[10])
	event.meta_pressed = bool(row[11])
	if row.size() > 12 and bool(row[12]):
		event.set_meta("pv_state_only", true)
	return event


func _load_inputs() -> void:
	if inputs_ref == "":
		failures.append("replay: inputs=<記録のタグ> を付ける")
		return
	var path := inputs_ref
	if not path.ends_with(".json"):
		path = OUT_ROOT + path + "/" + INPUTS_FILE
	elif not path.begins_with("res://") and not path.is_absolute_path():
		path = "res://" + path
	if not FileAccess.file_exists(path):
		failures.append("replay: %s が無い" % path)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		failures.append("replay: %s が読めない" % path)
		return
	_replay = data
	_replay_events = _replay.get("events", [])
	for row: Array in _replay.get("digests", []):
		_replay_digests[int(row[0])] = int(row[1])
	if str(_replay.get("quality", "")) != quality:
		report["replay_quality_note"] = "記録 %s、流し直し %s（画質が違うと試合がずれることがある）" % [_replay.get("quality", ""), quality]


func _show_overlay(text: String) -> void:
	if play_mode != "record":
		return
	if _overlay == null:
		var layer := CanvasLayer.new()
		layer.layer = 120
		add_child(layer)
		_overlay = Label.new()
		_overlay.position = Vector2(20, 12)
		_overlay.add_theme_font_override("font", load("res://resources/fonts/NotoSansJP-Bold.otf") as Font)
		_overlay.add_theme_font_size_override("font_size", 22)
		_overlay.add_theme_color_override("font_color", Color(1.0, 0.32, 0.3))
		_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
		_overlay.add_theme_constant_override("outline_size", 6)
		layer.add_child(_overlay)
	_overlay.text = text


## 人が遊ぶので、台本 s09 の決まった流れ（押し合い・ゴツン・落下・体当たり）は確かめない。出た問題が問題集どおりかだけ見る
func _check_2p(by_n: Dictionary) -> void:
	for n: int in by_n:
		if str(by_n[n]["q"]) != str(QUIZZES[n - 1][0]):
			failures.append("Q%d showed 「%s」" % [n, by_n[n]["q"]])


func _check() -> void:
	super._check()
	var play: Dictionary = report["play"]
	play["received"] = _received.size()
	if play_mode == "record":
		var wall := float(Time.get_ticks_usec() - _wall_start_usec) / 1000000.0 if _wall_start_usec > 0 else 0.0
		play["live"] = {"frames": frame_count, "wall_sec": snappedf(wall, 0.01),
			"mean_fps": snappedf(frame_count / wall, 0.1) if wall > 0.0 else 0.0, "late_frames": _late_frames}
		var data := {"version": INPUTS_VERSION, "take": take_name, "quality": quality, "sub": sub, "seed": pv_seed, "fps": FPS,
			"frames": frame_count, "end_frame": _end_frame, "test_driver": test_driver, "live": play["live"],
			"events": _received, "digests": _digests}
		var file := FileAccess.open(out + INPUTS_FILE, FileAccess.WRITE)
		if file == null:
			failures.append("record: %s に書けない" % (out + INPUTS_FILE))
		else:
			file.store_string(JSON.stringify(data))
			file.close()
	elif play_mode == "replay":
		var first_event_diff := -1
		var count := mini(_received.size(), _replay_events.size())
		for i in range(count):
			var a: Array = _received[i]
			var b: Array = _replay_events[i]
			for j in range(13):
				if (bool(a[j]) if j >= 6 else int(a[j])) != (bool(b[j]) if j >= 6 else int(b[j])):
					first_event_diff = i
					break
			if first_event_diff >= 0:
				break
		if first_event_diff < 0 and _received.size() != _replay_events.size():
			first_event_diff = count
		play["replay"] = {"events_recorded": _replay_events.size(), "events_received": _received.size(),
			"first_event_diff": first_event_diff, "digest_frames": _replay_digests.size(), "mismatched_frames": _mismatches,
			"first_mismatch": _first_mismatch}
		if first_event_diff >= 0:
			failures.append("replay: キーが記録と違う（%d 番目から）" % first_event_diff)
		if _mismatches > 0:
			failures.append("replay: ゲームの状態が記録と違う（%d フレーム目から、%d フレーム）" % [_first_mismatch, _mismatches])
