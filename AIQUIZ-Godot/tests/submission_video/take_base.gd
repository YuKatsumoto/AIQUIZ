extends Node

## 審査用のプレイ動画（docs/submission の 04_プレイ動画 C〜E）を撮る台本の土台。
## Godot の Movie Maker（--write-movie）で、ゲームの絵と音を 60fps の AVI に書き出す。画面の取り込みは使わないので、
## ほかの窓が重なっても写らず、音も PC から鳴らない。起動は tests/submission_video/record_take.py。
##
## ここにあるもの：
##   ・歩調合わせ（pace=<1 秒あたりのフレーム数>）：Movie Maker は 1 フレーム = ゲームの 1/60 秒で進み、1080p の書き出しは
##     実時間より遅い（この PC で 1 フレーム 50 ms 前後）。2 つのゲームを同時に撮るときは、実時刻の同じ刻み
##     （例 pace=12.5 なら 80 ms ごと）で 1 フレームずつ進め、2 本の動画のフレームが 1 対 1 で並ぶようにする
##   ・フレームごとの実時刻の記録（2 つの画面を並べるときの時刻合わせ用。report の "clock"）
##   ・キー入力（Input.parse_input_event）と、人の操作らしい左右移動。窓がフォーカスを失うと Godot は押しているキーを
##     すべて離すので、押しているはずのキーが離れていたら押し直す
## 待ち時間はすべてゲームの時間（t）で数える。
## 共通の引数（"--" の後ろ）：out=<report.json の絶対パス> pace=<fps> shots=<画面写真（PNG）を残すフォルダ>

const RESEND_AFTER_FRAMES := 3

var out_path := ""
var report := {"failures": []}
var rng := RandomNumberGenerator.new()
## ゲームの時間（秒）。Movie Maker では 1 フレーム 1/60 秒ずつ進む。
var t := 0.0

var _held: Dictionary = {}
var _taps: Array = []               # [key, 離す時刻 t]
var _mismatch: Dictionary = {}
var _pace_period := 0.0
var _clock_frames := PackedInt32Array()
var _clock_unix := PackedFloat64Array()
var _unix_anchor := 0.0
var _ticks_anchor := 0
var _lat_next := 0.0
var _finished := false
var _audio_path := ""
var _shots_dir := ""
var _shot_times: Dictionary = {}    # 名前 → 撮る時刻 t（撮ったら -1）
var _audio_rec: AudioEffectRecord = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000  # ゲームより先に、このフレームのキーを決める
	_unix_anchor = Time.get_unix_time_from_system()
	_ticks_anchor = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_path = arg.trim_prefix("out=")
		if arg.begins_with("shots="):
			_shots_dir = arg.trim_prefix("shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
		if arg.begins_with("pace="):
			_pace_period = 1.0 / maxf(1.0, float(arg.trim_prefix("pace=")))
	call_deferred("_start")


func _start() -> void:
	await run()


## 台本の本体（テイクが書く）。
func run() -> void:
	pass


## 毎フレームの操作（テイクが書く）。
func brain(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	_pace()
	t += delta
	_clock_frames.append(Engine.get_process_frames())
	_clock_unix.append(_unix_now())
	for i in range(_taps.size() - 1, -1, -1):
		if t >= float(_taps[i][1]):
			hold(_taps[i][0], false)
			_taps.remove_at(i)
	_reassert_keys()
	for shot_name: String in _shot_times:
		if float(_shot_times[shot_name]) >= 0.0 and t >= float(_shot_times[shot_name]):
			_shot_times[shot_name] = -1.0
			_save_shot(shot_name)
	if not _finished:
		brain(delta)


func _unix_now() -> float:
	return _unix_anchor + float(Time.get_ticks_usec() - _ticks_anchor) / 1000000.0


## 実時刻の次の刻みまで待つ。同じ pace の 2 つのゲームは、同じ刻みで 1 フレームずつ進む。
func _pace() -> void:
	if _pace_period <= 0.0:
		return
	var now := _unix_now()
	var next := ceilf(now / _pace_period) * _pace_period
	if next - now < 0.002:
		next += _pace_period
	OS.delay_usec(int((next - now) * 1000000.0))


func _reassert_keys() -> void:
	for key: Key in _held.keys():
		if Input.is_key_pressed(key) == bool(_held[key]):
			_mismatch[key] = 0
			continue
		_mismatch[key] = int(_mismatch.get(key, 0)) + 1
		if int(_mismatch[key]) >= RESEND_AFTER_FRAMES:
			_mismatch[key] = 0
			var down := bool(_held[key])
			_held[key] = not down
			hold(key, down)


# --- キー入力 ---

func hold(key: Key, down: bool) -> void:
	if bool(_held.get(key, false)) == down:
		return
	_held[key] = down
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	Input.parse_input_event(event)


## 押して、seconds 秒後に離す。
func tap(key: Key, seconds := 0.09) -> void:
	for entry: Array in _taps:
		if entry[0] == key:
			entry[1] = t + seconds
			return
	hold(key, true)
	_taps.append([key, t + seconds])


func is_held(key: Key) -> bool:
	return bool(_held.get(key, false))


func release_all() -> void:
	_taps.clear()
	for key: Key in _held.keys():
		hold(key, false)


func set_lateral(direction: int) -> void:
	hold(KEY_A, direction > 0)
	hold(KEY_D, direction < 0)


## 人の操作らしい左右移動：判断は 50〜110 ms ごと。止まる位置は少し行き過ぎたり、手前になったりする。
## KEY_A で x が増え、KEY_D で減る。
func go_x(x: float, target: float, dead := 0.4) -> void:
	if t < _lat_next:
		return
	_lat_next = t + rng.randf_range(0.05, 0.11)
	var direction := 0
	if x < target - dead:
		direction = 1
	elif x > target + dead:
		direction = -1
	set_lateral(direction)


# --- 待ち ---

func wait_until(condition: Callable, timeout_s: float) -> bool:
	var deadline := t + timeout_s
	var wall_deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0) * 20
	while t < deadline and Time.get_ticks_msec() < wall_deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func sleep(seconds: float) -> void:
	var until := t + seconds
	while t < until:
		await get_tree().process_frame


func mark(name: String) -> void:
	if not report.has("marks"):
		report["marks"] = {}
		report["marks_unix"] = {}
	report.marks[name] = Engine.get_process_frames()
	report.marks_unix[name] = _unix_now()


## 画面の取り込みで撮るとき用：このゲームの音（Master バス）を WAV に残す。finish() で保存する。
func start_audio_record(path: String) -> void:
	_audio_path = path
	_audio_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _audio_rec)
	_audio_rec.set_recording_active(true)
	report["audio_start_unix"] = _unix_now()
	# 音と絵の合わせを確かめる手がかり：効果音が鳴った実時刻
	report["sfx"] = []
	AudioManager.sfx_played.connect(func(cue: StringName) -> void:
		if (report.sfx as Array).size() < 400:
			(report.sfx as Array).append([String(cue), _unix_now()]))


func finish(error := "") -> void:
	if _finished:
		return
	_finished = true
	release_all()
	if not error.is_empty():
		(report.failures as Array).append(error)
	report["passed"] = (report.failures as Array).is_empty()
	if _audio_rec != null:
		report["audio_end_unix"] = _unix_now()
		_audio_rec.set_recording_active(false)
		var wav := _audio_rec.get_recording()
		if wav != null:
			wav.save_to_wav(_audio_path)
	report["clock"] = {"frames": _clock_frames, "unix": _clock_unix}
	if not out_path.is_empty():
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report))
			file.close()
	remove_capture_settings()
	print("VIDEO_TAKE passed=%s failures=%s" % [report.passed, report.failures])
	get_tree().quit(0 if report.passed else 1)


# --- 画面写真 ---

## delay 秒後の画面を PNG（圧縮で絵が変わらない）で残す。同じ名前は 1 回だけ。shots= がなければ何もしない。
## Movie Maker の撮影中は、保存で止まる時間は動画に写らない。
func shot_once(shot_name: String, delay := 0.0) -> void:
	if _shots_dir.is_empty() or _shot_times.has(shot_name):
		return
	_shot_times[shot_name] = t + delay


func _save_shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_shots_dir, shot_name])


# --- マウス ---

## 部品の真ん中を、マウスの動きと左クリックで押す。
func click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var center := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point := get_viewport().get_final_transform() * center
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await sleep(0.25)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.position = point
		button.global_position = point
		Input.parse_input_event(button)
		await sleep(0.08)


## 撮影のあいだ、設定とスキンの保存先を撮影用のファイルに替える（プレイヤーの設定ファイルには書かない）。
func use_capture_settings(tag: String) -> void:
	GameManager.settings_path = "user://submission_video_%s_settings.json" % tag
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameManager.settings_path))
	PlayerSkinStore.flush()
	PlayerSkinStore.path = "user://submission_video_%s_skins.json" % tag
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerSkinStore.path))
	QuizManager.player_analytics = null


func remove_capture_settings() -> void:
	for path: String in [GameManager.settings_path, PlayerSkinStore.path]:
		if path.begins_with("user://submission_video_"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
