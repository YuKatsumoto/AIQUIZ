extends Node

## PV の S01「Q1の壁が迫る」〜 S03「ロゴ」の背景までを、本物の GameWorld で 1 回の通しとして撮る（ローカル 2P）。
## 直接は起動できないので
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_capture_bootstrap.gd -- quality=ultra
## 引数（"--" の後ろ）:
##   quality=low|balanced|high|ultra   画質（既定 ultra。最高画質の超解像は上限の 2 倍に固定する）
##   frames=<N>                        撮るフレーム数（既定 562 = S01 221 + S02 116 + S03 225）
##   only=<f>,<f>,...                  その PV フレームだけ保存する（構図の確認用）。シミュレーションは全フレーム回す
##   png                               JPEG（品質 0.95）ではなく PNG で保存する
##   seed=<N>                          ドアの破片の乱数（既定 PV_SEED。破片の散り方を選ぶときに変える）
##   tag=<名前>                        出力先 artifacts/pv_capture/<tag>/（既定 s01_s03）
##   emote_at=<f>                      P1 のエモートを押す PV フレーム（既定 344）。ロゴの背景で、ドアの破片が床に残っている間に踊らせるとき
##   logo_cam=ex,ey,ez,lx,ly,lz,fov    突破のフレームから先のカメラを置き換える（ロゴ案 A の背景用）。目と注視点は
##                                     P1（_p1_anchor）からの x・z の差と、描画座標の y。fov は縦の画角。使ったカメラは report の logo_cam
## 出力: pv_NNNN.jpg（PV のフレーム番号。1 = 曲の頭）と report.json（4 フレームごとの位置の記録と、撮れた絵の確認つき）。
##
## 設計（docs/pv/storyboard.html の S01〜S03、docs/pv/capture.md）:
##   ・ローカル 2P・10 問モードの PLAYING を tests/hp_unit.gd の fixture(2) で組み、1 問目にメタ問題 Q1 を入れる。
##     正解は 0 番（青いドア・x=+3.5・画面左の「AI」）。不正解は 1 番（赤いドア・x=−3.5・画面右の「せんせい」）。
##   ・場所はコースの奥: 2 人は描画座標 z=+24（ベルトの後端から 36.5 m）から走る。チップソーはカメラより後ろに置く。
##   ・壁は WALL_SPEED。P1 の突破がちょうど 3 小節目の頭の 2 フレーム後になるよう、壁の最初の位置を
##     P1 の前進（下の入力表）から逆算する。PV の撮影中だけ、通過した壁を薄れさせずに残す（quiz_wall.gd）。
##   ・動きは控えめにする（本物のキーイベント。KEYS の表）:
##       P2（ハート 1 から始める）が、迷わず全速力で斜めに「せんせい」（不正解）へ突っ込む。ゲームどおり壁に激突して
##       後ろへ吹き飛び、2 秒後に爆散する。P1 は落ち着いて「AI」のドアの正面へ 1 回だけ寄り、最後に走ってドアを突き破る。
##       S03 は P1 が踊るだけ（P1 カンナムスタイル）。ジャンプ・押し合い・小さな当て直しはしない。
##   ・カメラはゲームの Camera3D を CameraController.set_director_pose() で動かす（揺れ・上下の揺らぎは乗らない）。
##     揺れて見えないよう、2 人の位置を毎フレーム追いかけず、時間で決めたなめらかな動きだけにする。
##       S01（1〜S02_FIRST_FRAME−1）: 2 人の後ろ・上から（24mm 相当）。ゆっくり寄りながら「AI」のドアの側へ少し振る。
##       S02（S02_FIRST_FRAME〜337）: P1 がドアに触れる直前に切り替える。壁といっしょに動き、壁の向こう 6.5 m から
##                       青いドアを見る（20mm 相当）。突破のあとは、突破した位置の P1 との距離をなめらかに 4.2 m へ詰める。
##       S03（338〜562）: S02 のカメラのまま、踊る P1 を正面から。1 秒かけて胸の高さへ上がって 1.5 m 引き、
##                       P1 を画面の下半分に置く（上半分にロゴ。AE で軽くぼかして暗くする）。
##   ・スロー: 突破から 0.6 秒（PV 時間）は Engine.time_scale = 0.5（ゲーム時間 0.3 秒）、そのあと 0.15 秒で 1.0 に戻す。
##   ・HUD と全 CanvasLayer は隠す（あとから足される脱落の演出の画面も）。BGM のバスは消音、効果音は残す。
##   ・ドアの破片の乱数は seed(PV_SEED) で固定する。昼の位相は 0.25 に固定。2 人の見た目は定数で固定する。
## 設定ファイルは user://pv_capture_settings.json に逸らし、user://settings.json が変わらないことを確かめる。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const QuizWallScript := preload("res://scripts/world/quiz_wall.gd")
const OUT_ROOT := "res://artifacts/pv_capture/"
const VIEW := Vector2i(1920, 1080)
const FPS := 60.0
const BEAT := 60.0 / 128.0
const BAR := BEAT * 4.0
const PV_SEED := 7  # S02 の終わりに大きな破片が手前に残らない散り方（今の入力表で確かめた）
const DAY_PHASE := 0.25
const WARMUP_FRAMES := 150
const PIN_BUDGET_MS := 100000.0

## 場所と壁
const START_Z := 24.0                           # 2 人の描画座標 z（ベルトの後端は −12.5）
const P1_START_X := 1.5
const P2_START_X := -1.5
const WALL_SPEED := 2.9                         # ゲームの典型の速さ
const PLAYER_SPEED := 7.6                       # tuning.player_speed（前後・左右とも）
const HIT_OFFSET := 0.4                         # 判定は先頭の z が壁の z − 0.4 に届いたとき
const IMPACT_PV := 2.0 * BAR + 2.0 / FPS        # 3 小節目の頭から 2 フレーム後
const FIRST_WALL_Z := 22.0                      # tuning.wall_start_z（壁 0 番の状態座標）
## P2 はハート 1 から始める。最初の不正解で脱落し、ゲームどおり壁に激突して吹き飛び、爆散する（HUD は映らない）。
const P2_START_HP := 1
## チップソーは先頭の SAW_FOLLOW + 刃の半径の後ろを追う（ゲームは 14 m）。P2 が前へ飛び出しても
## S01 のカメラより後ろに留まるよう、PV では遠ざけておく。
const SAW_FOLLOW := 26.0
const SAW_BEHIND := SAW_FOLLOW + 1.45           # + SawChaseState.BLADE_RADIUS
## スロー
const SLOW_SCALE := 0.5
const SLOW_PV_SEC := 0.6
const RAMP_PV_SEC := 0.15
## カット。S02 へは P1 がドアに触れる直前（突破の 5 フレーム前。体の前がまだ扉の手前にある）に切り替える。
const S02_FIRST_FRAME := 222
const S03_FIRST_FRAME := 338
const DEFAULT_FRAMES := 562
## カメラ
const S01_FOV := 45.747
const S02_FOV := 53.702
## S01: 2 人の後ろ・上から（スタートの 10 m 後ろ・床から 4.5 m 前後）。2 人の位置は追わず、S01 の間に 1.6 m だけ
## ゆっくり引きながら「せんせい」の側へ少し振る。P2 は激突すると後ろ・外側へ吹き飛び、スタートの 2.5 m 後ろ・
## x = −6 あたりで爆散するので、そこまで画面に収める。
const S01_EYE_START := Vector3(-0.6, 3.3, START_Z - 10.4)
const S01_EYE_END := Vector3(-1.4, 3.6, START_Z - 12.0)
const S01_LOOK_START := Vector3(-0.6, 0.5, START_Z + 9.0)
const S01_LOOK_END := Vector3(-2.0, 0.4, START_Z + 7.0)
const S02_WALL_BACK := 6.5                      # 突破までは壁の向こう 6.5 m
const FOLLOW_GAP := 4.2                         # 突破のあとは P1 の前 4.2 m へなめらかに寄る
## S03（ロゴの背景）: 胸の高さへ上がりながら 1.5 m 引き、少し見上げる。P1 は画面の下半分に収まり、
## 上半分（空・壁・スタンド）にロゴが乗る。
const S03_SETTLE_FRAMES := 60.0
const S03_EYE_Y := 0.9
const S03_EXTRA_GAP := 1.5
const S03_LOOK_Y := 1.2

## 入力（本物のキーイベント）。[キー, 押し始めの PV フレーム, 押すフレーム数, メモ]。フレーム n の更新に効く。
## 同じフレームに前と横を押すと斜めに動く（ゲームが入力を正規化するので、それぞれ 7.6 × 0.71 m/s）。
## 動きは控えめにする: P2 は 1 本の斜めの線で「せんせい」へ、P1 は横へ 1 回寄って最後に前へ走るだけ。ジャンプはしない。
## 脱落した P2 のキーは送らない（_apply_keys）。
## P1 = A（画面左）/D/W/Space、P2 = ←（画面左）/→/↑/右Ctrl、エモート P1 = 1、P2 = 8。KEY_CTRL は右 Ctrl として送る。
## 位置は tests/pv_capture 撮影の report.json の trace で確かめる。
const KEYS := [
	# 1 小節目: P2 が迷わず全速力で「せんせい」（不正解）へ。ハート 1 なので激突して脱落する
	[KEY_UP, 3, 180, "P2 が全速力で前へ（脱落したら離す）"],
	[KEY_RIGHT, 3, 22, "P2 が斜めに「せんせい」のドアの正面へ（↑＋→）"],
	# 2 小節目: P1 は落ち着いて「AI」のドアの正面へ寄り、最後に走ってドアを突き破る（突破のフレームで離す）
	[KEY_A, 128, 16, "P1 が「AI」のドアの正面へ"],
	[KEY_W, 212, 16, "P1 が走ってドアを突き破る"],
	# S03: 踊るだけ
	[KEY_1, 344, 4, "P1 のエモート（カンナムスタイル）"],
]
const P2_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_CTRL, KEY_8, KEY_9, KEY_0]
const P1_EMOTES: Array[int] = [2, 19, 13]       # EmoteData: カンナムスタイル / ウェーブヒップホップ / YMCA
const P2_EMOTES: Array[int] = [17, 19, 13]      # ランニングマン / ウェーブヒップホップ / YMCA

## 看板はゲームどおり改行と和文間の空白を詰めて自動で折り返すので、ちょうど
## 「Q1 このゲームのもんだいを / つくっているのはだれ？」の 2 行になる文にする（measure_question.gd で確認）。
const Q1_TEXT := "Q1 このゲームの もんだいを つくっているのは だれ？"
const Q1_CHOICES := ["AI", "せんせい"]
## 2 人の見た目（ゲーム内の画面と同じ）。どの PC で撮っても同じになるよう固定する。
const P1_HAT := 11  # HatData.HAT_PROPELLER
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12  # HatData.HAT_FOX
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
## 2 問目以降（PV には映らない想定だが、映っても自然な問題にしておく）
const FILLER := [
	["【計算】36 ÷ 4 ＝ ？", ["9", "8"]],
	["「たいよう」を漢字で書くと？", ["太陽", "太洋"]],
	["水が氷になる温度は？", ["0℃", "100℃"]],
]

var quality := GraphicsQualityRules.ULTRA
var tag := "s01_s03"
var frame_count := DEFAULT_FRAMES
var only_frames: Dictionary = {}
var use_png := false
var pv_seed := PV_SEED
var emote_frame := 344
var logo_cam: PackedFloat64Array = []
var out := ""

var helper: Node
var gs: QuizGameState
var world: Node
var camera_controller: Node
var saved_game_state: QuizGameState
var saved_analytics: Variant
var settings_digest_before := ""
var report := {}
var failures: Array[String] = []

var _running := false
var _pv_frame := 0
var _history: Dictionary = {}      # n -> [p1_x, p1_z, p2_x, p2_z, wall_z]（描画座標）
var _impact_frame := -1
var _impact_game_time := -1.0
var _game_time := 0.0
var _saved := 0
var _held: Dictionary = {}         # keycode -> true
var _trace: Array = []
var _scroll0 := 0.0
var _cam_gap_at_impact := 0.0
var _p1_anchor := Vector2.ZERO     # S02 の頭で決める P1 の (x, z)。S02・S03 のカメラはこれだけを見る
var _p2_out_frame := -1
var _p2_burst_frame := -1
var _overlays: Array[CanvasLayer] = []


func _ready() -> void:
	process_priority = 1000  # GameWorld の更新のあとでカメラを決める
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
		elif arg.begins_with("seed="):
			pv_seed = int(arg.trim_prefix("seed="))
		elif arg.begins_with("emote_at="):
			emote_frame = int(arg.trim_prefix("emote_at="))
		elif arg.begins_with("logo_cam="):
			logo_cam = PackedFloat64Array(Array(arg.trim_prefix("logo_cam=").split_floats(",")))
			if logo_cam.size() != 7:
				failures.append("logo_cam needs 7 numbers: ex,ey,ez,lx,ly,lz,fov")
				logo_cam = []
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_prepare_runtime()
	_scroll0 = _compute_scroll0()
	report["tool"] = "pv_capture"
	report["shots"] = "S01 (1-%d) + S02 (%d-%d) + S03 background (%d-%d)" % [S02_FIRST_FRAME - 1, S02_FIRST_FRAME,
		S03_FIRST_FRAME - 1, S03_FIRST_FRAME, frame_count]
	report["quality"] = quality
	report["args"] = Array(OS.get_cmdline_user_args())
	report["constants"] = {"start_z": START_Z, "wall_speed": WALL_SPEED, "scroll0": _scroll0, "impact_pv_sec": IMPACT_PV,
		"slow_scale": SLOW_SCALE, "slow_pv_sec": SLOW_PV_SEC, "ramp_pv_sec": RAMP_PV_SEC, "seed": pv_seed,
		"p2_start_hp": P2_START_HP, "saw_follow": SAW_FOLLOW, "s02_first_frame": S02_FIRST_FRAME}
	await _build_world()
	report["viewport"] = {"size": [get_viewport().size.x, get_viewport().size.y],
		"scaling_3d_scale": get_viewport().scaling_3d_scale, "msaa_3d": get_viewport().msaa_3d,
		"screen_space_aa": get_viewport().screen_space_aa}
	_start()


# ------------------------------------------------------------------ setup

func _prepare_runtime() -> void:
	get_tree().root.size = VIEW
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var bgm := AudioServer.get_bus_index("BGM")
	if bgm >= 0:
		AudioServer.set_bus_mute(bgm, true)
	settings_digest_before = _settings_digest()
	# The setter would persist the choice; a plain assignment is in memory only (ground_look does the same).
	GameManager.graphics_quality = quality
	GameManager.settings_path = "user://pv_capture_settings.json"
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	saved_game_state = QuizManager.game_state
	saved_analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	QuizWallScript.keep_after_pass_for_capture = true
	seed(pv_seed)


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


## 先頭（P1）が突破までに前へ出る距離から、PV フレーム 1 の壁の位置（= world_scroll_z）を決める。
## 斜め入力はゲームと同じく正規化して数える（フレーム 1〜突破の更新まで、スローの前なので dt = 1/60）。
func _compute_scroll0() -> float:
	var p1_forward := 0.0
	for n in range(1, int(round(IMPACT_PV * FPS)) + 1):
		var keys := _keys_at(n)
		var axis := Vector2((1.0 if keys.has(KEY_A) else 0.0) - (1.0 if keys.has(KEY_D) else 0.0), 1.0 if keys.has(KEY_W) else 0.0)
		p1_forward += axis.normalized().y * PLAYER_SPEED / FPS
	var wall_render_z0 := START_Z + p1_forward + HIT_OFFSET + WALL_SPEED * IMPACT_PV
	return FIRST_WALL_Z - wall_render_z0


func _build_world() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	_install_quizzes()
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
	gs.p1_hat = P1_HAT
	gs.p2_hat = P2_HAT
	gs.p1_emote_slots = P1_EMOTES.duplicate()
	gs.p2_emote_slots = P2_EMOTES.duplicate()
	gs.tuning.wall_speed_override = WALL_SPEED
	gs.tuning.saw_follow_distance = SAW_FOLLOW
	gs.set("_active_wall_speed", WALL_SPEED)
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	var scene := load("res://scenes/game_world.tscn") as PackedScene
	world = scene.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	# 組み上がるまで状態を止めておき、撮影の頭で動かし始める。
	world.set("_replay_mode", true)
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await _frames(30)
	_set_station()
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	camera_controller = world.get("camera_controller")
	await _frames(WARMUP_FRAMES)
	_set_station()
	_hide_overlays()
	report["stage"] = {"floor_center_z": stage.get_floor_center_z(), "floor_length": stage.get_floor_length(),
		"grandstands": stage.get_grandstand_count(), "saw_enabled": gs.saw.enabled} if stage != null else {}


func _install_quizzes() -> void:
	for index in range(gs.quiz_list.size()):
		var item: QuizItem
		if index == 0:
			item = QuizItem.create(Q1_TEXT, PackedStringArray(Q1_CHOICES), 0, "PV 用のメタ問題。", "OFFLINE")
		else:
			var filler: Array = FILLER[(index - 1) % FILLER.size()]
			var choices := PackedStringArray(filler[1])
			if gs.num_choices_for_index(index) == 4:
				choices = PackedStringArray([choices[0], choices[1], "その他", "わからない"])
			item = QuizItem.create(filler[0], choices, 0, "", "OFFLINE")
		gs.quiz_list[index] = item
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.load_current_quiz()


## PV フレーム 1 の直前の状態。2 人は描画座標 z = START_Z、チップソーは先頭の SAW_BEHIND 後ろで回っている。
func _set_station() -> void:
	gs.world_scroll_z = _scroll0
	gs.player_x = P1_START_X
	gs.player2_x = P2_START_X
	gs.player_z = _scroll0 + START_Z
	gs.player2_z = _scroll0 + START_Z
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.camera_shake = 0.0
	gs.p2_hp = P2_START_HP
	gs.set("_active_wall_speed", WALL_SPEED)
	gs.saw.local_z = START_Z - SAW_BEHIND
	gs.saw.elapsed = 10.0  # 回り始め（SPINUP）を済ませておく


## 今ある CanvasLayer と、撮影中に足されるもの（脱落の演出など）を、すべて毎フレーム隠す。
func _hide_overlays() -> void:
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_overlays.append(node as CanvasLayer)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is CanvasLayer:
			_overlays.append(node as CanvasLayer))
	_keep_overlays_hidden()


func _keep_overlays_hidden() -> void:
	for layer: CanvasLayer in _overlays:
		if is_instance_valid(layer):
			layer.visible = false


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


# ------------------------------------------------------------------ timeline

## PV の経過秒 → ゲームの経過秒（突破のまわりのスロー）。
func _game_time_at(pv: float) -> float:
	if pv <= IMPACT_PV:
		return pv
	var slow_end := IMPACT_PV + SLOW_PV_SEC
	if pv <= slow_end:
		return IMPACT_PV + (pv - IMPACT_PV) * SLOW_SCALE
	var g1 := IMPACT_PV + SLOW_PV_SEC * SLOW_SCALE
	var ramp_end := slow_end + RAMP_PV_SEC
	if pv <= ramp_end:
		var u := pv - slow_end
		return g1 + SLOW_SCALE * u + (1.0 - SLOW_SCALE) * u * u / (2.0 * RAMP_PV_SEC)
	return g1 + RAMP_PV_SEC * (1.0 + SLOW_SCALE) * 0.5 + (pv - ramp_end)


## PV フレーム n の更新（n−1 → n）に使う time_scale。
func _time_scale_for(n: int) -> float:
	return (_game_time_at(n / FPS) - _game_time_at((n - 1) / FPS)) * FPS


func _start() -> void:
	_pv_frame = 0
	Engine.time_scale = _time_scale_for(1)
	_apply_keys(1)
	world.set("_replay_mode", false)
	_running = true


func _process(dt: float) -> void:
	if not _running:
		return
	_pv_frame += 1
	var n := _pv_frame
	_game_time += dt
	_history[n] = [gs.player_x, gs.player_local_z, gs.player2_x, gs.player2_local_z, FIRST_WALL_Z - gs.world_scroll_z]
	if _impact_frame < 0 and gs.current_wall_index > 0:
		_impact_frame = n
		_impact_game_time = _game_time
	if _p2_out_frame < 0 and not gs.p2_alive:
		_p2_out_frame = n
	var player := world.get_node("Player") as PlayerController
	if _p2_burst_frame < 0 and player.has_player_death_exploded(2):
		_p2_burst_frame = n
	if n % 4 == 1 or (n >= 200 and n <= 300 and n % 2 == 0):
		var entry := {"f": n, "p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_local_z, 0.01)],
			"p2": [snappedf(gs.player2_x, 0.01), snappedf(gs.player2_local_z, 0.01)],
			"wall_z": snappedf(FIRST_WALL_Z - gs.world_scroll_z, 0.01), "saw_z": snappedf(gs.saw.local_z, 0.01),
			"alive": [gs.p1_alive, gs.p2_alive], "hp": [gs.p1_hp, gs.p2_hp], "emote": [gs.p1_emote, gs.p2_emote],
			"ts": snappedf(Engine.time_scale, 0.001)}
		if not gs.p2_alive:
			var body := player.get_death_presentation_position(false)
			entry["p2_body"] = [snappedf(body.x, 0.01), snappedf(body.y, 0.01), snappedf(body.z, 0.01)]
		_trace.append(entry)
	_keep_overlays_hidden()
	_apply_camera(n)
	# 次のフレームの入力と時間の速さ（ここで決めたものが次の更新に効く）。
	_apply_keys(n + 1)
	world.set("_push_focus_lost", false)
	Engine.time_scale = _time_scale_for(n + 1)
	if only_frames.is_empty() or only_frames.has(n):
		RenderingServer.frame_post_draw.connect(_capture.bind(n), CONNECT_ONE_SHOT)
	if n >= frame_count:
		_running = false
		_finish.call_deferred()


func _keys_at(n: int) -> Dictionary:
	var want: Dictionary = {}
	for entry: Array in KEYS:
		var start: int = emote_frame if entry[0] == KEY_1 else entry[1]
		if n >= start and n < start + entry[2]:
			want[entry[0]] = true
	return want


## フレーム n の更新で押されているべきキーをそろえる。ウィンドウのフォーカスが外れて離されたキーは押し直す。
## 脱落した P2 のキーは送らない（脱落したプレイヤーの入力は、ゲームでは別の操作に使われるため）。
func _apply_keys(n: int) -> void:
	var want := _keys_at(n)
	if gs != null and not gs.p2_alive:
		for key: Variant in P2_KEYS:
			want.erase(key)
	for key: Variant in _held.keys():
		if not want.has(key):
			_send_key(key, false)
	for key: Variant in want.keys():
		if not _held.has(key) or not Input.is_key_pressed(key) or (key == KEY_CTRL and not bool(world.get("_right_ctrl_down"))):
			_send_key(key, true)


func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	if keycode == KEY_CTRL:
		event.location = KEY_LOCATION_RIGHT  # P2 のジャンプは右 Ctrl
	Input.parse_input_event(event)
	if pressed:
		_held[keycode] = true
	else:
		_held.erase(keycode)


func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## カメラは時間で決めたなめらかな動きだけにする（揺れて見えないよう、2 人の位置を毎フレーム追わない）。
## S02 からは、S02 の頭で決めた P1 の位置（_p1_anchor。P1 はそのあと横にも前にも動かない）だけを見る。
func _apply_camera(n: int) -> void:
	var eye: Vector3
	var target: Vector3
	var fov: float
	if n < S02_FIRST_FRAME:
		var u := _ease((n - 1) / float(S02_FIRST_FRAME - 2))
		eye = S01_EYE_START.lerp(S01_EYE_END, u)
		target = S01_LOOK_START.lerp(S01_LOOK_END, u)
		fov = S01_FOV
	else:
		if n == S02_FIRST_FRAME or _p1_anchor == Vector2.ZERO:
			_p1_anchor = Vector2(gs.player_x, gs.player_local_z)
		var wall_z := FIRST_WALL_Z - gs.world_scroll_z
		var cam_z: float
		var look := Vector3(3.5, 0.55, wall_z)
		if _impact_frame < 0 or n < _impact_frame:
			cam_z = wall_z + S02_WALL_BACK
		else:
			# 突破の瞬間の距離から、壁が近づいてきたのと同じ速さで寄り始め、なめらかに FOLLOW_GAP へ。
			# 寄る先は突破した位置の P1（突破で壁の手前に止められ、そのあとは前へ走らない）。
			if n == _impact_frame:
				_p1_anchor.y = gs.player_local_z
			var p1_z := _p1_anchor.y
			if _cam_gap_at_impact <= 0.0:
				_cam_gap_at_impact = maxf(wall_z + S02_WALL_BACK - p1_z, FOLLOW_GAP + 0.1)
			var g := _game_time - _impact_game_time
			var excess := _cam_gap_at_impact - FOLLOW_GAP
			var tau := excess / WALL_SPEED
			var s03 := _ease((n - S03_FIRST_FRAME) / S03_SETTLE_FRAMES)
			cam_z = p1_z + FOLLOW_GAP + S03_EXTRA_GAP * s03 + excess * exp(-g / tau)
			var w := _ease(g / 0.45)
			look = look.lerp(Vector3(_p1_anchor.x, lerpf(0.35, S03_LOOK_Y, s03), p1_z), w)
		var cam_x := lerpf(3.6, _p1_anchor.x, _ease((n - S02_FIRST_FRAME) / 90.0))
		var rise := _ease((n - S03_FIRST_FRAME) / S03_SETTLE_FRAMES)
		eye = Vector3(cam_x, lerpf(-0.25, S03_EYE_Y, rise), cam_z)
		target = look
		fov = S02_FOV
	if logo_cam.size() == 7 and _impact_frame >= 0 and n >= _impact_frame:
		eye = Vector3(_p1_anchor.x + logo_cam[0], logo_cam[1], _p1_anchor.y + logo_cam[2])
		target = Vector3(_p1_anchor.x + logo_cam[3], logo_cam[4], _p1_anchor.y + logo_cam[5])
		fov = logo_cam[6]
		if only_frames.is_empty() or only_frames.has(n):
			var cams: Dictionary = report.get_or_add("logo_cam", {})
			cams[str(n)] = {"eye": [eye.x, eye.y, eye.z], "target": [target.x, target.y, target.z], "fov": fov}
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, fov)
	var cam := camera_controller.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.h_offset = 0.0
		cam.fov = fov
		cam.global_transform = pose


func _capture(n: int) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(out + "pv_%04d.%s" % [n, "png" if use_png else "jpg"])
	var err := image.save_png(path) if use_png else image.save_jpg(path, 0.95)
	if err != OK:
		failures.append("save %s failed (%d)" % [path, err])
	else:
		_saved += 1


# ------------------------------------------------------------------ finish

func _finish() -> void:
	await _frames(2)
	Engine.time_scale = 1.0
	for key: Variant in _held.keys():
		_send_key(key, false)
	QuizWallScript.keep_after_pass_for_capture = false
	report["impact_frame"] = _impact_frame
	report["impact_frame_planned"] = int(round(IMPACT_PV * FPS)) + 1
	report["p2_out_frame"] = _p2_out_frame
	report["p2_burst_frame"] = _p2_burst_frame
	report["at_s01_end"] = _history.get(S02_FIRST_FRAME - 1, null)
	# S01 の最後の絵で、P1 の中心から壁の手前の面（壁の z − 厚み 1.10 の半分）までの距離。
	var last_s01: Array = _history.get(S02_FIRST_FRAME - 1, [0.0, 0.0, 0.0, 0.0, 0.0])
	report["p1_to_door_face_at_cut"] = snappedf(float(last_s01[4]) - 0.55 - float(last_s01[1]), 0.01)
	report["alive_at_end"] = [gs.p1_alive, gs.p2_alive]
	report["hp_at_end"] = [gs.p1_hp, gs.p2_hp]
	report["scores"] = [gs.score, gs.player2_score]
	report["saved_frames"] = _saved
	report["settings_unchanged"] = _settings_digest() == settings_digest_before
	if not report["settings_unchanged"]:
		failures.append("user://settings.json changed")
	if not gs.p1_alive:
		failures.append("P1 was eliminated during the capture")
	if gs.p2_alive or not gs.p2_wall_impact:
		failures.append("P2 did not crash into the wrong door")
	if _p2_burst_frame < 0 or _p2_burst_frame >= S02_FIRST_FRAME:
		failures.append("P2 did not burst during S01 (frame %d)" % _p2_burst_frame)
	if _impact_frame <= S02_FIRST_FRAME:
		failures.append("the cut to S02 is not before P1 reaches the door (impact %d)" % _impact_frame)
	report["failures"] = failures
	report["trace"] = _trace
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	var summary := report.duplicate()
	summary.erase("trace")
	print("[pv_capture] %s" % JSON.stringify(summary))
	QuizManager.game_state = saved_game_state
	QuizManager.player_analytics = saved_analytics
	get_tree().quit(0 if failures.is_empty() else 1)
