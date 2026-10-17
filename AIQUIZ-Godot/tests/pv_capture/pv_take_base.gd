extends Node

## PV の撮影テイクの共通の土台（S01〜S03 v3 の pv_v3_runtime.gd から、テイクによらない部分を取り出したもの）。
## テイクはこれを extends し、_setup（場面を作る）・_update（毎フレームの演出とカメラ）・_check（撮れた絵の確認）を書く。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=<テイク> quality=ultra
## 共通の引数（"--" の後ろ）:
##   take=<名前>                       tests/pv_capture/pv_<名前>_runtime.gd を動かす（pv_take_bootstrap.gd が読む）
##   quality=low|balanced|high|ultra   画質（既定 ultra）
##   frames=<N>                        撮る PV フレーム数（既定はテイクの長さ）
##   only=<f>,<f>,...                  その PV フレームだけ保存する（構図の確認用。シミュレーションは全フレーム回す）
##   png                               JPEG（品質 0.95）ではなく PNG で保存する
##   sub=<N>                           動きのブレ用に 1 フレームを N 回に分けて進める（--fixed-fps を 60×N にして起動する）。
##                                     各フレームの最後の N/2 回を pv_NNNN_0, _1, ... で保存し、tools/pv/merge_subframes.py で重ねる
##   seed=<N>                          乱数（既定 PV_SEED）
##   tag=<名前>                        出力先 artifacts/pv_capture/<tag>/（既定はテイクの名前）
## 出力: 画像（PV フレーム番号はテイクの頭が 1）、report.json、cues.json（鳴った効果音と時刻。編集で同じ時刻に置く）。
## 撮影中は user://settings.json を使わず、戦績・評価も記録しない。

const OUT_ROOT := "res://artifacts/pv_capture/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const VIEW := Vector2i(1920, 1080)
const FPS := 60.0
const BEAT := 60.0 / 128.0
const PV_SEED := 7
const PIN_BUDGET_MS := 100000.0
const CAPTURE_SETTINGS_PATH := "user://pv_capture_settings.json"

var take_name := "take"
var quality := GraphicsQualityRules.ULTRA
var tag := ""
var frame_count := 0
var only_frames: Dictionary = {}
var use_png := false
var sub := 1
var pv_seed := PV_SEED
var out := ""

var report := {}
var failures: Array[String] = []
var cues: Array = []
var settings_digest_before := ""
var saved_game_state: QuizGameState
var saved_analytics: Variant
var saved_settings_path := ""

var _running := false
var _step := 0                      # 撮った PV の更新の数（sub 回で 1 フレーム）
var _skip := false                  # true の間はゲームだけ進め、PV の時刻と番号を止める（カットの間を詰める）
var _skipped_updates := 0
var _game_time := 0.0
var _saved := 0
var _held: Dictionary = {}
var _overlays: Array[CanvasLayer] = []
var _overlay_keep: Array[CanvasLayer] = []


## 拍 → その拍の頭の PV フレーム（1 始まり）
static func bf(beats: float) -> int:
	return int(round(beats * BEAT * FPS)) + 1


## 0〜1 のなめらかな出入り
static func smooth(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _ready() -> void:
	process_priority = 1000  # ゲームの更新（状態・ポーズ・カメラ）のあとで、演出とカメラの上書きを決める
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
		elif arg.begins_with("frames="):
			frame_count = maxi(1, int(arg.trim_prefix("frames=")))
		elif arg.begins_with("only="):
			for f in arg.trim_prefix("only=").split(",", false):
				only_frames[int(f)] = true
		elif arg == "png":
			use_png = true
		elif arg.begins_with("sub="):
			sub = clampi(int(arg.trim_prefix("sub=")), 1, 8)
		elif arg.begins_with("seed="):
			pv_seed = int(arg.trim_prefix("seed="))
		else:
			_parse_arg(arg)
	if tag == "":
		tag = take_name
	if frame_count <= 0:
		frame_count = _default_frames()
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_prepare_runtime()
	report["tool"] = "pv_take_" + take_name
	report["quality"] = quality
	report["sub"] = sub
	report["args"] = Array(OS.get_cmdline_user_args())
	await _setup()
	_running = true
	_step = 0
	Engine.time_scale = _time_scale_for_step(1)
	_before_update(1)


# ------------------------------------------------------------------ テイクが書くところ

## テイクの長さ（PV フレーム）
func _default_frames() -> int:
	return 1


## 共通でない引数
func _parse_arg(_arg: String) -> void:
	pass


## 場面を作って、撮り始められるところまで進める（await してよい）
func _setup() -> void:
	pass


## 次の更新の前：入力・時間の速さ以外の準備（n = 次に撮る PV フレーム）
func _before_update(_n: int) -> void:
	pass


## ゲームの更新のあと、毎回：演出とカメラ（n = PV フレーム、t = この更新が終わった PV の秒、dt = ゲームの秒）
func _update(_n: int, _t: float, _dt: float) -> void:
	pass


## 間を詰めている（_skip）間の更新
func _update_skipping(_dt: float) -> void:
	pass


## PV の秒 → ゲームの秒（スロー・早回し）。既定は等速
func _game_time_at(pv: float) -> float:
	return pv


## 撮れた絵の確認。外れたら failures に書く
func _check() -> void:
	pass


## 終わる前の片付け
func _cleanup() -> void:
	pass


# ------------------------------------------------------------------ 準備

func _prepare_runtime() -> void:
	get_tree().root.size = VIEW
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = int(FPS) * sub    # 物理もフレームと同じ細かさで進める
	Engine.max_physics_steps_per_frame = 8
	var bgm := AudioServer.get_bus_index("BGM")
	if bgm >= 0:
		AudioServer.set_bus_mute(bgm, true)
	settings_digest_before = _settings_digest()
	saved_settings_path = GameManager.settings_path
	GameManager.graphics_quality = quality
	GameManager.settings_path = CAPTURE_SETTINGS_PATH
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	if quality == GraphicsQualityRules.ULTRA:
		RenderingServer.directional_shadow_atlas_set_size(16384, true)
	saved_game_state = QuizManager.game_state
	saved_analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	seed(pv_seed)
	AudioManager.sfx_played.connect(_on_sfx)


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


## 画面の上の CanvasLayer（HUD など）を毎フレーム隠す。keep に入れたものは隠さない。
func hide_overlays(keep: Array[CanvasLayer] = []) -> void:
	_overlay_keep = keep
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_overlays.append(node as CanvasLayer)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is CanvasLayer:
			_overlays.append(node as CanvasLayer))
	_keep_overlays_hidden()


func _keep_overlays_hidden() -> void:
	for layer: CanvasLayer in _overlays:
		if is_instance_valid(layer) and not _overlay_keep.has(layer):
			layer.visible = false


func _on_sfx(cue: StringName) -> void:
	if _running and not _skip:
		cues.append({"t": snappedf(float(_step) / (FPS * sub), 0.0001), "frame": frame_of(_step), "cue": String(cue)})


# ------------------------------------------------------------------ 時間

func frame_of(step: int) -> int:
	return int(ceil(float(step) / sub)) if step > 0 else 0


func _time_scale_for_step(step: int) -> float:
	var d := 1.0 / (FPS * sub)
	return maxf((_game_time_at(step * d) - _game_time_at((step - 1) * d)) / d, 0.001)


## PV の時刻を止めて、ゲームだけを等速で進める（カットの間を詰める）。end_skip() で戻す。
func begin_skip() -> void:
	_skip = true


func end_skip() -> void:
	_skip = false


func _process(dt: float) -> void:
	if not _running:
		return
	_game_time += dt
	if _skip:
		_skipped_updates += 1
		_update_skipping(dt)
		_keep_overlays_hidden()
		if _skip:
			Engine.time_scale = 1.0
			return
		# _update_skipping の中で詰め終わった：次の更新から撮る
		Engine.time_scale = _time_scale_for_step(_step + 1)
		_before_update(frame_of(_step + 1))
		return
	_step += 1
	var n := frame_of(_step)
	var t := float(_step) / (FPS * sub)          # この更新が終わった PV の時刻
	_update(n, t, dt)
	_keep_overlays_hidden()
	var last_sub := (_step % sub) == 0
	var s_in := ((_step - 1) % sub) + 1                 # このフレームの何回目か（1〜sub）
	var shutter := maxi(1, sub / 2)
	if s_in > sub - shutter and (only_frames.is_empty() or only_frames.has(n)):
		var suffix := "" if sub == 1 else "_%d" % (s_in - (sub - shutter) - 1)
		RenderingServer.frame_post_draw.connect(_capture.bind(n, suffix), CONNECT_ONE_SHOT)
	if last_sub and n >= frame_count:
		_running = false
		_finish.call_deferred()
		return
	if _skip:
		Engine.time_scale = 1.0
		return
	Engine.time_scale = _time_scale_for_step(_step + 1)
	_before_update(frame_of(_step + 1))


# ------------------------------------------------------------------ 入力（本物のキーイベント）

func send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	if keycode == KEY_CTRL:
		event.location = KEY_LOCATION_RIGHT
	Input.parse_input_event(event)
	if pressed:
		_held[keycode] = true
	else:
		_held.erase(keycode)


func hold_keys(want: Dictionary) -> void:
	for key: Variant in _held.keys():
		if not want.has(key):
			send_key(key, false)
	for key: Variant in want.keys():
		if not _held.has(key) or not Input.is_key_pressed(key):
			send_key(key, true)


# ------------------------------------------------------------------ 撮影と記録

func _capture(n: int, suffix: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(out + "pv_%04d%s.%s" % [n, suffix, "png" if use_png else "jpg"])
	var err := image.save_png(path) if use_png else image.save_jpg(path, 0.95)
	if err != OK:
		failures.append("save %s failed (%d)" % [path, err])
	else:
		_saved += 1


func _finish() -> void:
	await _frames(2)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	for key: Variant in _held.keys():
		send_key(key, false)
	_check()
	_cleanup()
	report["saved_images"] = _saved
	report["skipped_updates"] = _skipped_updates
	report["settings_unchanged"] = _settings_digest() == settings_digest_before
	if not report["settings_unchanged"]:
		failures.append("user://settings.json changed")
	report["failures"] = failures
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	var cue_file := FileAccess.open(out + "cues.json", FileAccess.WRITE)
	if cue_file != null:
		cue_file.store_string(JSON.stringify(cues, "  "))
		cue_file.close()
	var summary := report.duplicate()
	summary.erase("trace")
	print("[pv_take_%s] %s" % [take_name, JSON.stringify(summary)])
	QuizManager.game_state = saved_game_state
	QuizManager.player_analytics = saved_analytics
	GameManager.settings_path = saved_settings_path
	get_tree().quit(0 if failures.is_empty() else 1)
