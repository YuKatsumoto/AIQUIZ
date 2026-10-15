extends Node

## PV 冒頭 S01〜S03 の新しい流れ（絵コンテ docs/pv/storyboard_s01_s03_v2/s01_s03_storyboard_v3.png）を、本物の GameWorld で
## 1 回の通しとして撮る（ローカル 2P）。ロゴ（案 C）は After Effects で重ねる（docs/pv/previz/ae/build_s03_c.jsx）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_v3_bootstrap.gd -- quality=ultra
## 引数（"--" の後ろ）:
##   quality=low|balanced|high|ultra   画質（既定 ultra）
##   frames=<N>                        撮る PV フレーム数（既定 1068 = ロゴの終わりまで）
##   only=<f>,<f>,...                  その PV フレームだけ保存する（構図の確認用。シミュレーションは全フレーム回す）
##   png                               JPEG（品質 0.95）ではなく PNG で保存する
##   sub=<N>                           動きのブレ用に 1 フレームを N 回に分けて進める（--fixed-fps を 60×N にして起動する）。
##                                     各フレームの最後の N/2 回（シャッター 180°相当）を pv_NNNN_0, _1, ... で保存し、
##                                     tools/pv/merge_subframes.py で 1 枚に重ねる（本番は sub=8）
##   seed=<N>                          ドアの破片の乱数（既定 PV_SEED。突破の直前にも同じ値で入れ直す）
##   tag=<名前>                        出力先 artifacts/pv_capture/<tag>/（既定 v3）
## 出力: 画像、report.json（位置の記録・撮れた絵の確認）、cues.json（鳴った効果音と PV の時刻。編集で同じ時刻に置く）。
##
## 流れ（PV フレーム。1 = 曲の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   01   1-113  2 人がスタート位置に立つ（カウントダウンの状態のまま止め、ベルトは動かさない）。コースは空
##   02 114-225  空から問題の壁が 1 枚落ちてドスン（ゲームのプレビューの壁と同じ落ち方・弾み方。土ぼこりの衝撃・揺れ・どよめき）。
##               2 人はびくっとのけぞる（Hit_Chest）
##   03 226-338  2 拍で背中越しのアップへ寄る。2 人がそろって青い「AI」の扉を見る（頭を扉の中心へ実際に向ける）
##   04 339-450  前から 2 人の顔。赤 → 青 → 赤と 1 拍ずつ扉を見比べる
##   05 451-506  前から P2 のアップ。P2 が赤い「せんせい」を指さしてドヤ顔、P1 は首を振って迷う
##   06 507-619  スタート（PLAYING へ）。P2 はヒップホップ2 をその場で見せびらかしてから、踊りながら赤い扉へ斜めに突っ込む。P1 は腕を組んで見送る
##   07 620-661  引き。P2 がゴツン（ハート 1 なのでゲームどおり脱落）、吹き飛ぶ
##   07b 662-773 煽る：P1 が P2 のほうへ向き直って指さし、シリーダンスで煽る（倒れた P2 の向こうから撮る）。
##               ゲームどおり激突の 2 秒後に P2 が爆散（このPVだけ破片の勢いを大きく、大爆発の演出つき）
##   08 774-839  P1 が青い扉の正面へ寄って走る（低い追従）
##   09 840-956  壁の向こう側から。P1 がカンナムスタイルを踊りながら扉を突き破る（突破 846、0.6 秒だけ 0.5 倍のスロー）
##   ロゴ 957-1180 S03 と同じく胸の高さへ上がって引く（この上に AE でロゴ案 C を重ねる）
## このPVだけ：ベルトは 1.0 m/s（ゲームの典型は 2.9。壁を 12 m 先に落としたまま、煽るパートの 1 小節を入れるため）

const OUT_ROOT := "res://artifacts/pv_capture/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const QuizWallScript := preload("res://scripts/world/quiz_wall.gd")
## 壁の着地の衝撃（地面の輪・筋・煙・破片）。元は炎の色なので、土ぼこりの灰色に塗り替えて 1 回だけ流す
const IMPACT_VFX := preload("res://assets/BinbunVFX/impact_explosions/effects/impact/vfx_impact_01.tscn")
## P2 の爆散に重ねる爆発（BinbunVFX。炎の色のまま）
const BURST_VFX := preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_01.tscn")
const BURST_VFX_SCALE := 1.0
## 爆発のうち、画面を覆う白い球（Core）と黒い煙の玉（Smoke）は使わない（大きさが絵の描き方で決まっていて小さくできない）
const BURST_VFX_HIDE := ["Core", "Smoke"]
## 爆散をこのPVだけ大きく：破片を体の中心から外へこの速さで飛ばす（ゲームは横 2〜4・上 5〜9 m/s ほど）
const BURST_SPEED_MIN := 18.0
const BURST_SPEED_MAX := 30.0
const BURST_UP_MIN := 5.0
const BURST_UP_MAX := 11.0
const DOOR_CENTER_Y := 0.59                    # 扉の中心の高さ（床 −1.2 と扉の上 2.38 の間）
const VIEW := Vector2i(1920, 1080)
const FPS := 60.0
const BEAT := 60.0 / 128.0
const PV_SEED := 7
const DAY_PHASE := 0.25
const WARMUP_FRAMES := 150
const PIN_BUDGET_MS := 100000.0

## 場所と速さ（ゲームと同じ）
const START_Z := 24.0
const P1_START_X := 1.5
const P2_START_X := -1.5
const WALL_SPEED := 1.0                         # このPVだけ遅く（上の注記）
const PLAYER_SPEED := 7.6
const HIT_OFFSET := 0.4
const FIRST_WALL_Z := 22.0
const FLOOR_Y := -1.2
const P2_START_HP := 1
const SAW_FOLLOW := 26.0
const SAW_BEHIND := SAW_FOLLOW + 1.45
const DOOR_X := 3.5                              # 青「AI」は +x（後ろから見て左）、赤「せんせい」は −x

## 壁の落下（GameWorld のプレビューの壁と同じ形。長さだけ見える速さにのばす）
const DROP_START_Y := 46.0
const DROP_SECONDS := 0.55
const SETTLE_SECONDS := 0.14
const SQUASH := Vector3(1.16, 0.78, 1.16)

## スロー（突破のまわり）
const SLOW_SCALE := 0.5
const SLOW_PV_SEC := 0.6
const RAMP_PV_SEC := 0.15

## カットと出来事（PV フレーム）。bf(拍) = その拍の頭のフレーム
static func bf(beats: float) -> int:
	return int(round(beats * BEAT * FPS)) + 1

var F_S02 := bf(4)          # 113
var F_LAND := bf(5)         # 142 壁の着地
var F_S03 := bf(8)          # 226
var F_S04 := bf(12)         # 338
var F_S05 := bf(16)         # 451
var F_RACE := bf(18)        # 507 スタート
var F_S07 := bf(22)         # 620 引き：ゴツン
var F_P2_HIT := F_S07 + 6   # 626
var F_TAUNT := bf(23.5)     # 662 煽る：向き直って指さし
var F_TAUNT_DANCE := bf(25)    # 704 シリーダンス（その前の 0.7 秒は向き直って指さす）
var F_S08 := bf(27.5)       # 774 P1 が青い扉へ
var F_P1_SIDE := F_S08 + 3
var F_P1_RUN := F_P1_SIDE + 18
var F_P2_BURST := F_P2_HIT + 120  # ゲームどおり激突の 2 秒後（煽っている最中）
var F_P1_HIT := bf(30) + 2  # 846 突破（9 小節目の頭の 2 フレーム後）
var F_S09 := F_P1_HIT - 6   # 840
var F_LOGO := bf(34)        # 957
const DEFAULT_FRAMES := 1180
var p2_move_frame := 0

## 扉を見比べる（03・04）。[拍, 見る扉]。+1 = 青（+x）、−1 = 赤（−x）、0 = 正面。頭を扉の中心へ実際に向ける。P2 は 2 フレーム遅れ
const LOOKS := [[10.0, 1], [12.0, -1], [13.0, 1], [14.0, -1], [15.0, 0]]
const LOOK_TURN := 0.15                         # 振り向く速さ（秒）

## ポーズ（UAL のクリップ。AnimationRig.SLOT_UAL＝UAL1、SLOT_UAL2）
const FLINCH_CLIP := "Hit_Chest"
const POINT_CLIP := ""                          # 05 の P2 は立ちポーズのまま、右腕だけ赤いドアのほうへ伸ばす（_point_arm）
const POINT_RATIO := 0.5
const DOUBT_CLIP := "Idle_No_Loop"
const FOLD_CLIP := "Idle_FoldArms_Loop"

const P1_EMOTES: Array[int] = [2, 7, 13]        # カンナムスタイル / シリーダンス（煽り、キー 2）/ YMCA
const P2_EMOTES: Array[int] = [17, 19, 15]      # ランニングマン / ウェーブヒップホップ / ヒップホップ2（キー 0）
const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const Q1_TEXT := "Q1 このゲームの もんだいを つくっているのは だれ？"
const Q1_CHOICES := ["AI", "せんせい"]
const FILLER := [
	["【計算】36 ÷ 4 ＝ ？", ["9", "8"]],
	["「たいよう」を漢字で書くと？", ["太陽", "太洋"]],
	["水が氷になる温度は？", ["0℃", "100℃"]],
]
const P2_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_CTRL, KEY_8, KEY_9, KEY_0]

var quality := GraphicsQualityRules.ULTRA
var tag := "v3"
var frame_count := DEFAULT_FRAMES
var only_frames: Dictionary = {}
var use_png := false
var sub := 1
var pv_seed := PV_SEED
var out := ""
var point_clip := POINT_CLIP
var point_ratio := POINT_RATIO
var point_slot := AnimationRig.SLOT_UAL

var helper: Node
var gs: QuizGameState
var world: Node
var player: PlayerController
var camera_controller: Node
var cam: Camera3D
var saved_game_state: QuizGameState
var saved_analytics: Variant
var settings_digest_before := ""
var report := {}
var failures: Array[String] = []
var cues: Array = []

var keys_table: Array = []
var hold_d := 0.0                    # スタート位置から壁（の手前の判定）までの距離
var scroll_hold := 0.0
var p1_run_frame := 0

var _running := false
var _step := 0
var _game_time := 0.0
var _held: Dictionary = {}
var _trace: Array = []
var _saved := 0
var _overlays: Array[CanvasLayer] = []
var _impact_frame := -1
var _impact_game_time := -1.0
var _p2_hit_frame := -1
var _p2_burst_frame := -1
var _landed := false
var _race_started := false
var _reseeded := false
var _burst_forced := false
var _p1_anchor := Vector2.ZERO
var _cam_gap_at_impact := 0.0
var _puppet1: StagingPuppet
var _last_emote := [0, 0]
var _puppet2: StagingPuppet
var _dof_close: CameraAttributesPractical
var _dof_front: CameraAttributesPractical
var _dof_faces: CameraAttributesPractical
var _dof_taunt: CameraAttributesPractical
var _taunt_anchor := Vector3.ZERO           # 煽りのカメラが追う、倒れた P2 の床の位置（なめらかに追う）
var _burst_boosted := false
var _p1_emote_cleared := false


func _ready() -> void:
	process_priority = 1000  # GameWorld の更新（状態とポーズ）のあとで、カメラ・壁・ポーズの上書きを決める
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
		elif arg.begins_with("point="):
			# 05 の指さしのポーズを試す: point=<クリップ>:<位置 0〜1>:<1|2（UAL1 / UAL2）>
			var parts := arg.trim_prefix("point=").split(":")
			point_clip = parts[0]
			if parts.size() > 1:
				point_ratio = float(parts[1])
			if parts.size() > 2:
				point_slot = AnimationRig.SLOT_UAL2 if parts[2] == "2" else AnimationRig.SLOT_UAL
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_build_keys()
	_plan()
	_prepare_runtime()
	report["tool"] = "pv_v3_capture"
	report["quality"] = quality
	report["sub"] = sub
	report["args"] = Array(OS.get_cmdline_user_args())
	report["plan"] = {"hold_distance": hold_d, "scroll_hold": scroll_hold, "p1_run_frame": p1_run_frame, "p2_move_frame": p2_move_frame,
		"wall_speed": WALL_SPEED,
		"frames": {"S02": F_S02, "land": F_LAND, "S03": F_S03, "S04": F_S04, "S05": F_S05, "race": F_RACE, "S07": F_S07,
			"p2_hit": F_P2_HIT, "taunt": F_TAUNT, "taunt_dance": F_TAUNT_DANCE, "S08": F_S08, "p1_side": F_P1_SIDE,
			"p2_burst": F_P2_BURST, "S09": F_S09, "p1_hit": F_P1_HIT, "logo": F_LOGO}}
	await _build_world()
	_start()


# ------------------------------------------------------------------ plan

func _build_keys() -> void:
	keys_table = [
		[KEY_0, F_RACE + 1, 4, "P2 のエモート（ヒップホップ2）。その場で見せびらかす"],
		[KEY_A, F_P1_SIDE, 16, "P1 が青い扉の正面へ"],
		[KEY_2, F_TAUNT_DANCE, 4, "P1 のエモート（シリーダンス）で煽る"],
	]


## 壁の止まる位置（スタートから何 m 先か）を P1 の突破から、P2 が動き出すフレームを P2 のゴツンから逆算する。
## カウントダウンの間は誰も動かず、ベルトも止まっている。PLAYING の最初の更新から壁が WALL_SPEED で近づく。
func _plan() -> void:
	var per := PLAYER_SPEED / FPS
	var p1_fwd := (F_P1_HIT - F_P1_RUN) * per
	var wall_at_hit := START_Z + p1_fwd + HIT_OFFSET - 0.02
	hold_d = wall_at_hit - START_Z + WALL_SPEED * (F_P1_HIT - F_RACE) / FPS
	scroll_hold = FIRST_WALL_Z - (START_Z + hold_d)
	p1_run_frame = F_P1_RUN
	keys_table.append([KEY_W, F_P1_RUN, F_P1_HIT - F_P1_RUN, "P1 が走って扉を突き破る（突破のフレームで離す）"])
	keys_table.append([KEY_1, F_S09 - 4, 4, "P1 のエモート（カンナムスタイル）。走りながら踊って扉へ"])
	# P2：ヒップホップ2 をその場で見せてから、斜め（22 フレーム）→ まっすぐで F_P2_HIT に判定へ届く動き出し
	var need := START_Z + hold_d - WALL_SPEED * (F_P2_HIT - F_RACE) / FPS - HIT_OFFSET + 0.02 - START_Z
	p2_move_frame = F_RACE + 6
	for start in range(F_P2_HIT - 1, F_RACE + 5, -1):
		var fwd := 0.0
		for n in range(start, F_P2_HIT + 1):
			var diag := n < start + 22
			fwd += (Vector2(1.0, 1.0).normalized().y if diag else 1.0) * per
		if fwd >= need:
			p2_move_frame = start
			break
	keys_table.append([KEY_UP, p2_move_frame, 300, "P2 が踊りながら前へ（脱落したら離す）"])
	keys_table.append([KEY_RIGHT, p2_move_frame, 22, "P2 が斜めに赤い扉の正面へ"])


func _keys_at(n: int) -> Dictionary:
	var want: Dictionary = {}
	for entry: Array in keys_table:
		if n >= entry[1] and n < entry[1] + entry[2]:
			want[entry[0]] = true
	return want


# ------------------------------------------------------------------ setup

func _prepare_runtime() -> void:
	get_tree().root.size = VIEW
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = int(FPS) * sub    # 破片・人形の物理もフレームと同じ細かさで進める
	Engine.max_physics_steps_per_frame = 8
	var bgm := AudioServer.get_bus_index("BGM")
	if bgm >= 0:
		AudioServer.set_bus_mute(bgm, true)
	settings_digest_before = _settings_digest()
	GameManager.graphics_quality = quality
	GameManager.settings_path = "user://pv_capture_settings.json"
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	if quality == GraphicsQualityRules.ULTRA:
		# 撮影だけの上乗せ：影を細かく
		RenderingServer.directional_shadow_atlas_set_size(16384, true)
	saved_game_state = QuizManager.game_state
	saved_analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	QuizWallScript.keep_after_pass_for_capture = true
	seed(pv_seed)
	AudioManager.sfx_played.connect(_on_sfx)


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


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
	# スタートまではカウントダウンの状態で止める（壁は出ていて、ベルトは動かず、2 人は立ちポーズ）
	gs.game_state = Constants.STATE_COUNTDOWN
	gs.countdown_timer = 100000.0
	QuizManager.game_state = gs
	var scene := load("res://scenes/game_world.tscn") as PackedScene
	world = scene.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	await _frames(30)
	_set_station()
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	camera_controller = world.get("camera_controller")
	cam = camera_controller.get_node_or_null("Camera3D") as Camera3D
	await _frames(WARMUP_FRAMES)
	_set_station()
	_hide_overlays()
	_puppet1 = StagingPuppet.new(player, 1)
	_puppet2 = StagingPuppet.new(player, 2)
	_dof_close = _make_dof(9.0, 9.0, 0.06)
	_dof_front = _make_dof(6.5, 6.0, 0.09)
	_dof_faces = _make_dof(6.0, 6.0, 0.08)
	_dof_taunt = _make_dof(9.0, 6.0, 0.07)
	report["stage"] = {"floor_center_z": stage.get_floor_center_z(), "floor_length": stage.get_floor_length()} if stage != null else {}


func _make_dof(far_distance: float, far_transition: float, amount: float) -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = far_distance
	a.dof_blur_far_transition = far_transition
	a.dof_blur_amount = amount
	return a


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


func _set_station() -> void:
	gs.world_scroll_z = scroll_hold
	gs.player_x = P1_START_X
	gs.player2_x = P2_START_X
	gs.player_z = scroll_hold + START_Z
	gs.player2_z = scroll_hold + START_Z
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.camera_shake = 0.0
	gs.p2_hp = P2_START_HP
	gs.set("_active_wall_speed", WALL_SPEED)
	gs.saw.local_z = START_Z - SAW_BEHIND
	gs.saw.elapsed = 10.0


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


func _on_sfx(cue: StringName) -> void:
	if _running:
		cues.append({"t": snappedf(float(_step) / (FPS * sub), 0.0001), "frame": _frame_of(_step), "cue": String(cue)})


# ------------------------------------------------------------------ timeline

func _frame_of(step: int) -> int:
	return int(ceil(float(step) / sub)) if step > 0 else 0


## PV の経過秒 → ゲームの経過秒（突破のまわりのスロー）。
func _game_time_at(pv: float) -> float:
	var impact := (F_P1_HIT - 1) / FPS
	if pv <= impact:
		return pv
	var slow_end := impact + SLOW_PV_SEC
	if pv <= slow_end:
		return impact + (pv - impact) * SLOW_SCALE
	var g1 := impact + SLOW_PV_SEC * SLOW_SCALE
	var ramp_end := slow_end + RAMP_PV_SEC
	if pv <= ramp_end:
		var u := pv - slow_end
		return g1 + SLOW_SCALE * u + (1.0 - SLOW_SCALE) * u * u / (2.0 * RAMP_PV_SEC)
	return g1 + RAMP_PV_SEC * (1.0 + SLOW_SCALE) * 0.5 + (pv - ramp_end)


func _time_scale_for_step(step: int) -> float:
	var d := 1.0 / (FPS * sub)
	return (_game_time_at(step * d) - _game_time_at((step - 1) * d)) / d


func _start() -> void:
	_step = 0
	Engine.time_scale = _time_scale_for_step(1)
	_apply_keys(1)
	world.set("_replay_mode", false)
	_running = true


func _process(dt: float) -> void:
	if not _running:
		return
	_step += 1
	var n := _frame_of(_step)
	var t := float(_step) / (FPS * sub)          # この更新が終わった PV の時刻
	_game_time += dt
	_events_after_update(n, t)
	_fix_emote_start()
	_update_taunt_anchor(dt)
	_apply_wall(t)
	_apply_poses(n, t, dt)
	_keep_overlays_hidden()
	_apply_camera(n, t)
	_record(n)
	# 次の更新の入力・時間の速さ・状態
	var next_n := _frame_of(_step + 1)
	_apply_keys(next_n)
	world.set("_push_focus_lost", false)
	if not _race_started and next_n >= F_RACE:
		gs.countdown_timer = 0.00001                # 次の更新で PLAYING になる
		_race_started = true
	Engine.time_scale = _time_scale_for_step(_step + 1)
	var last_sub := (_step % sub) == 0
	var s_in := ((_step - 1) % sub) + 1                 # このフレームの何回目か（1〜sub）
	var shutter := maxi(1, sub / 2)
	if s_in > sub - shutter and (only_frames.is_empty() or only_frames.has(n)):
		var suffix := "" if sub == 1 else "_%d" % (s_in - (sub - shutter) - 1)
		RenderingServer.frame_post_draw.connect(_capture.bind(n, suffix), CONNECT_ONE_SHOT)
	if last_sub and n >= frame_count:
		_running = false
		_finish.call_deferred()


func _events_after_update(n: int, t: float) -> void:
	if _impact_frame < 0 and gs.current_wall_index > 0:
		_impact_frame = n
		_impact_game_time = _game_time
	if _p2_hit_frame < 0 and not gs.p2_alive:
		_p2_hit_frame = n
	if _p2_burst_frame < 0 and player.has_player_death_exploded(2):
		_p2_burst_frame = n
	if _p2_burst_frame >= 0 and not _burst_boosted:
		_boost_burst()
		_burst_boosted = true
	# 煽りのシリーダンスは走り出す前にやめる（踊りはジャンプでしか止まらないので、状態を直接戻す）
	if not _p1_emote_cleared and n >= F_S08:
		gs.p1_emote = 0
		_p1_emote_cleared = true
	# 突破の破片の散り方を、手前の出来事（火花・土ぼこり・人形）に左右されないようにする
	if not _reseeded and n >= F_P1_HIT - 3:
		seed(pv_seed)
		_reseeded = true


## このPVだけ、P2 の爆散を大きく：ゲームが入れた破片の速さを、体の中心から外へ強く飛ぶ速さに書き直し、
## ゲームの大爆発の演出（閃光・火花・煙）・強い揺れ・爆発音を重ねる。乱数は専用（ドアの破片の散り方を変えない）。
func _boost_burst() -> void:
	var bodies: Array = player.get("_p2_explosion_bodies")
	if bodies.is_empty():
		return
	var center := Vector3.ZERO
	for b: Variant in bodies:
		center += (b as Node3D).global_position
	center /= bodies.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	for b: Variant in bodies:
		var piece := b as RigidBody3D
		if piece == null:
			continue
		var out := piece.global_position - center
		out.y = 0.0
		if out.length() < 0.05:
			out = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		var dir := (out.normalized() + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))).normalized()
		piece.linear_velocity = dir * rng.randf_range(BURST_SPEED_MIN, BURST_SPEED_MAX) + Vector3.UP * rng.randf_range(BURST_UP_MIN, BURST_UP_MAX)
		piece.angular_velocity = Vector3(rng.randf_range(-24.0, 24.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-24.0, 24.0))
		piece.gravity_scale = 1.6
		piece.linear_damp = 0.02
	_play_vfx(BURST_VFX, center + Vector3(0.0, 0.3, 0.0), BURST_VFX_SCALE, [], BURST_VFX_HIDE)
	gs.camera_shake = maxf(gs.camera_shake, 1.6)
	AudioManager.play_sfx(&"barrier_explosion")


## 踊りの最初のフレーム：踊りの骨格はまだ 1 度も動いていない（初期姿勢＝T ポーズ）ので、0 秒の位置を当ててから写し直す。
func _fix_emote_start() -> void:
	for i in [1, 2]:
		var emote: int = gs.p1_emote if i == 1 else gs.p2_emote
		if emote > 0 and _last_emote[i - 1] != emote:
			var rig: AnimationRig = player.get("_p1_rig") if i == 1 else player.get("_p2_rig")
			var idx := rig.loaded_emotes.find(EmoteData.normalize_emote_id(emote)) if rig != null else -1
			if idx >= 0 and idx < AnimationRig.EMOTE_RIG_SLOTS.size():
				var slot: int = AnimationRig.EMOTE_RIG_SLOTS[idx]
				var ap := rig.aps[slot] as AnimationPlayer
				if ap != null:
					if not ap.is_playing():
						ap.play(rig.anim_names[slot])
					ap.seek(0.0, true)
					player.call("_apply_skeleton_pose", player.p1_parts if i == 1 else player.p2_parts,
						rig.skeletons[slot], rig.bone_indices_list[slot], true)
		_last_emote[i - 1] = emote


## 倒れた P2 の床の位置を、時定数 0.3 秒でなめらかに追う（爆散のあとは止める）。
func _update_taunt_anchor(dt: float) -> void:
	if gs.p2_alive or _p2_burst_frame >= 0:
		return
	var body := player.get_death_presentation_position(false)
	var flat := Vector3(body.x, 0.0, body.z)
	if _taunt_anchor == Vector3.ZERO:
		_taunt_anchor = flat
	else:
		_taunt_anchor = _taunt_anchor.lerp(flat, 1.0 - exp(-dt / 0.3))


## 問題の壁：着地までは空の上、着地で火花・土ぼこり・揺れ・音・どよめき、そのあと潰れて戻る。ほかの壁は映さない。
func _apply_wall(t: float) -> void:
	var t_land := (F_LAND - 1) / FPS
	for item: Variant in world.get("_active_walls"):
		if not is_instance_valid(item):
			continue
		var w := item as Node3D
		var idx := int(w.get_meta("wall_index", -1))
		if idx != 0:
			w.visible = false
			continue
		if gs.game_state == Constants.STATE_COUNTDOWN:
			w.call("set_gameplay_question", FractionFormatter.format_question(gs.current_quiz.q), true)
		var start := t_land - DROP_SECONDS
		if t < start:
			w.visible = false
			w.position.y = DROP_START_Y
			continue
		w.visible = true
		if t < t_land:
			var p := clampf((t - start) / DROP_SECONDS, 0.0, 1.0)
			w.position.y = lerpf(DROP_START_Y, 0.0, p * p)
			w.scale = Vector3.ONE
			continue
		if not _landed:
			_landed = true
			_on_wall_land(w)
		var q := clampf((t - t_land) / SETTLE_SECONDS, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - q, 3.0)
		w.position.y = sin(q * PI) * 0.12 * (1.0 - q)
		w.scale = SQUASH.lerp(Vector3.ONE, eased)


func _on_wall_land(w: Node3D) -> void:
	w.position.y = 0.0
	w.scale = SQUASH
	for x in [-4.6, 0.0, 4.6]:
		_spawn_impact(Vector3(x, FLOOR_Y + 0.05, w.global_position.z - 0.9))
	gs.camera_shake = maxf(gs.camera_shake, 1.25)
	AudioManager.play_sfx(&"wall_land")
	var crowd: Variant = world.get("_crowd_cues")
	if crowd != null:
		crowd.call("on_shock", w.global_position.z)


## 衝撃のエフェクトを土ぼこりの色で 1 回だけ流す。
func _spawn_impact(pos: Vector3) -> void:
	_play_vfx(IMPACT_VFX, pos, 2.3, [Color(0.93, 0.93, 0.95), Color(0.66, 0.68, 0.73), Color(0.42, 0.44, 0.5)])


## BinbunVFX のエフェクトを 1 回だけ流す（VFXController.play は繰り返すので、アニメと粒を直接動かす）。colors は [主, 副, 3 番目]（空なら元の色）。
func _play_vfx(scene: PackedScene, pos: Vector3, size: float, colors: Array, hide: Array = []) -> void:
	var fx := scene.instantiate() as Node3D
	fx.set("autoplay", false)
	world.add_child(fx)
	fx.global_position = pos
	fx.scale = Vector3.ONE * size
	if colors.size() >= 3:
		fx.set("primary_color", colors[0])
		fx.set("secondary_color", colors[1])
		fx.set("tertiary_color", colors[2])
	for name in (["Decal", "Light"] if not colors.is_empty() else ["Decal"]) + hide:
		var node := fx.get_node_or_null(name) as Node3D
		if node != null:
			node.visible = false
	for child in fx.get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).restart()
	var anim := fx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null:
		anim.play("oneshot" if anim.has_animation("oneshot") else "main")


# ------------------------------------------------------------------ acting

## GameWorld が状態から当てた姿（立ち・走り・踊り）の上に、絵コンテの演技を足す。毎フレーム上書きなので積み重ならない。
## つなぎ：演技が変わる（ゲームの姿 → ポーズ、ポーズ → ポーズ、ポーズ → ゲームの姿）前のフレームの終わりで今の姿を覚え、
## 次のフレームから 0.18 秒で新しい姿へなめらかにつなぐ（StagingPuppet.begin_blend / apply_blend）。
func _apply_poses(n: int, t: float, dt: float) -> void:
	var next_t := float(_step + 1) / (FPS * sub)
	var next_n := _frame_of(_step + 1)
	for i in [1, 2]:
		var puppet: StagingPuppet = _puppet1 if i == 1 else _puppet2
		var now: Array = _clip_for(i, n, t)
		if now[0] != "":
			puppet.pose(now[0], now[1], now[2])
	_apply_looks(n, t)
	for i in [1, 2]:
		var puppet: StagingPuppet = _puppet1 if i == 1 else _puppet2
		puppet.apply_blend(dt)
		var now_clip: String = _clip_for(i, n, t)[0]
		var next_clip: String = _clip_for(i, next_n, next_t)[0]
		if next_clip != now_clip:
			puppet.begin_blend(0.3 if (i == 1 and next_n == F_TAUNT_DANCE) else 0.18)


## [クリップ, 位置 0〜1, スロット]。"" はゲームの姿のまま。
func _clip_for(i: int, n: int, t: float) -> Array:
	var t_land := (F_LAND - 1) / FPS
	var flinch_len := 0.62
	var t0 := t_land + 0.03 + (0.033 if i == 2 else 0.0)
	if t >= t0 and t < t0 + flinch_len:
		# 02：着地でびくっとのけぞる（P2 は 2 フレーム遅れ）
		return [FLINCH_CLIP, clampf((t - t0) / flinch_len, 0.0, 1.0) * 0.85, AnimationRig.SLOT_UAL]
	if n >= F_S05 and n < F_RACE:
		if i == 2:
			return [point_clip, point_ratio, point_slot]            # 05：赤いドアを指さす（既定は "" = 腕だけ _point_arm で動かす）
		var dl := _puppet1.clip_length(DOUBT_CLIP, AnimationRig.SLOT_UAL2)
		var r := fposmod(t - (F_S05 - 1) / FPS, dl) / dl if dl > 0.0 else 0.0
		return [DOUBT_CLIP, r, AnimationRig.SLOT_UAL2]             # 05：首を振って迷う
	if i == 1 and n >= F_RACE and n < F_TAUNT:
		var fl := _puppet1.clip_length(FOLD_CLIP, AnimationRig.SLOT_UAL2)
		var r2 := fposmod(t, fl) / fl if fl > 0.0 else 0.3
		return [FOLD_CLIP, r2, AnimationRig.SLOT_UAL2]             # 06・07：腕を組んで見送る
	if i == 1 and n >= F_TAUNT and n < F_TAUNT_DANCE:
		var il := _puppet1.clip_length("Idle_Loop", AnimationRig.SLOT_UAL)
		var r3 := fposmod(t, il) / il if il > 0.0 else 0.0
		return ["Idle_Loop", r3, AnimationRig.SLOT_UAL]            # 07b：立って P2 を指さす（腕は _point_arm）
	return ["", 0.0, AnimationRig.SLOT_UAL]


## 扉を見比べる（03・04）、P2 を目で追う・向き直って煽る（06〜07b）。頭は見る点へ実際に向け、体（pelvis）は一部だけ回す。
func _apply_looks(n: int, t: float) -> void:
	for i in [1, 2]:
		var parts: Dictionary = player.p1_parts if i == 1 else player.p2_parts
		if parts.is_empty():
			continue
		var pelvis := parts.get("pelvis") as Node3D
		var head := parts.get("head_pivot") as Node3D
		if pelvis == null or head == null:
			continue
		var yaw := NAN                 # 頭を向ける向き（ワールド、+z が 0、+x が +）
		var body_share := 0.2
		if n >= F_S03 and n < F_S05 + 4:
			yaw = _door_look_yaw(head.global_position, t - (0.033 if i == 2 else 0.0))
		elif n >= F_S05 and n < F_RACE and i == 2:
			pelvis.global_basis = Basis(Vector3.UP, deg_to_rad(-22.0)) * pelvis.global_basis   # 胸を赤い扉のほうへ
			if point_clip == "":
				_point_arm(parts, Vector3(-0.62, 0.32, 0.72), t - (F_S05 - 1) / FPS - 0.1, 0.42)
			continue
		elif i == 1 and n >= F_RACE and n < F_S08:
			var target := _p2_focus()
			var d := target - head.global_position
			yaw = atan2(d.x, d.z)
			if n >= F_TAUNT:
				body_share = 1.0       # 07b：体ごと P2 へ向き直る
				var since := t - (F_TAUNT - 1) / FPS
				yaw = yaw * (1.0 - pow(1.0 - clampf(since / 0.2, 0.0, 1.0), 3.0))
				if n < F_TAUNT_DANCE:
					var aim := target + Vector3(0.0, 0.6, 0.0) - (parts.get("r_shoulder") as Node3D).global_position
					_point_arm(parts, aim.normalized(), since - 0.05, 0.38)
		if is_nan(yaw):
			continue
		pelvis.global_basis = Basis(Vector3.UP, yaw * body_share) * pelvis.global_basis
		var f := head.global_basis.z
		var cur := atan2(f.x, f.z)
		head.global_basis = Basis(Vector3.UP, wrapf(yaw - cur, -PI, PI)) * head.global_basis


## P1 が見る P2：生きている間は P2、脱落してからは倒れた体（爆散のあとは止めておく）。
func _p2_focus() -> Vector3:
	if gs.p2_alive:
		return Vector3(gs.player2_x, 0.4, (player.p2_container.global_position.z if player.p2_container != null else 0.0))
	return _taunt_anchor + Vector3(0.0, 0.2, 0.0)


## 03・04 で頭を向ける向き：今の扉と前の扉（またはは正面）の間をなめらかに。
func _door_look_yaw(head_pos: Vector3, t: float) -> float:
	var prev := 0.0
	var value := 0.0
	for e: Array in LOOKS:
		var t0 := float(e[0]) * BEAT
		if t < t0:
			break
		var side := int(e[1])
		var target_yaw := 0.0
		if side != 0:
			var d := Vector3(side * DOOR_X, DOOR_CENTER_Y, _wall_z()) - head_pos
			target_yaw = atan2(d.x, d.z)
		var u := clampf((t - t0) / LOOK_TURN, 0.0, 1.0)
		u = 1.0 - pow(1.0 - u, 3.0)
		value = lerpf(prev, target_yaw, u)
		prev = value
	return value

## 0→1。前半はゆっくり、最後に 8% ほど行き過ぎて戻る。
static func _ease_out_back(u: float) -> float:
	var x := u * u * (3.0 - 2.0 * u)            # まずなめらかに
	var c := 1.25
	var b := 1.0 + (c + 1.0) * pow(u - 1.0, 3.0) + c * pow(u - 1.0, 2.0)
	return lerpf(x, b, u)


## 指さし：dir の側（x の符号）の腕を、肩 → ひじの順に dir へ回す。since 秒目から duration 秒かけて腕を上げる
## （ゆっくり動き出し、少し行き過ぎて戻る）。since < 0 の間は下ろしたまま。
## 05 の P2 は前（+z）と −x の間・少し上（前から撮るので、カメラの左を指して見える）、07b の P1 は倒れた P2 へ。
func _point_arm(parts: Dictionary, dir_in: Vector3, since: float, duration: float) -> void:
	var ls := parts.get("l_shoulder") as Node3D
	var rs := parts.get("r_shoulder") as Node3D
	if ls == null or rs == null:
		return
	var dir := dir_in.normalized()
	var use_r := (rs.global_position.x < ls.global_position.x) == (dir.x < 0.0)
	var side := "r_" if use_r else "l_"
	var shoulder := parts.get(side + "shoulder") as Node3D
	var elbow := parts.get(side + "elbow") as Node3D
	var wrist := parts.get(side + "wrist") as Node3D
	if shoulder == null or elbow == null or wrist == null:
		return
	var w := _ease_out_back(clampf(since / duration, 0.0, 1.0))
	if w <= 0.0:
		return
	var upper := (elbow.global_position - shoulder.global_position).normalized()
	var q1 := Quaternion(upper, upper.slerp(dir, w).normalized())
	shoulder.global_basis = Basis(q1) * shoulder.global_basis
	var lower := (wrist.global_position - elbow.global_position).normalized()
	var q2 := Quaternion(lower, lower.slerp(dir, w).normalized())
	elbow.global_basis = Basis(q2) * elbow.global_basis


# ------------------------------------------------------------------ input

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
		event.location = KEY_LOCATION_RIGHT
	Input.parse_input_event(event)
	if pressed:
		_held[keycode] = true
	else:
		_held.erase(keycode)


# ------------------------------------------------------------------ camera

static func _ease(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _wall_z() -> float:
	return FIRST_WALL_Z - gs.world_scroll_z


## カットごとのカメラ。2 人の位置を毎フレーム追わず、時間で決めたなめらかな動きにする（08 は計画どおりの走りに合わせる）。
func _apply_camera(n: int, t: float) -> void:
	var eye: Vector3
	var target: Vector3
	var fov := 50.0
	var attrs: CameraAttributes = null
	var cz := START_Z
	if n < F_S03:
		# 01・02：2 人の後ろ・上から。ゆっくり寄る
		var u := _ease(t / ((F_S03 - 1) / FPS))
		eye = Vector3(0.0, 3.1, cz - 9.6).lerp(Vector3(0.0, 2.7, cz - 8.4), u)
		target = Vector3(0.0, 1.0, cz + 18.0)
		fov = 50.0
	elif n < F_S04:
		# 03：2 拍で背中越しのアップへ寄り、そこからごくゆっくり寄る
		var t0 := (F_S03 - 1) / FPS
		var u := _ease((t - t0) / (2.0 * BEAT))
		var far := Vector3(0.0, 2.7, cz - 8.4)
		var near := Vector3(0.0, 1.6, cz - 4.0)
		var drift := _ease((t - t0 - 2.0 * BEAT) / ((F_S04 - F_S03) / FPS - 2.0 * BEAT)) * 0.25
		eye = far.lerp(near, u) + Vector3(0.0, 0.0, drift)
		target = Vector3(0.0, lerpf(1.0, 0.7, u), cz + 12.6)
		fov = lerpf(50.0, 42.0, u)
		attrs = _dof_close if u > 0.5 else null
	elif n < F_S05:
		# 04：前から 2 人の顔（扉はカメラの後ろ。顔と目の向きで見比べているのが分かる）
		var t0 := (F_S04 - 1) / FPS
		var u := _ease((t - t0) / ((F_S05 - F_S04) / FPS))
		eye = Vector3(0.0, 0.62, cz + 3.7).lerp(Vector3(0.0, 0.6, cz + 3.4), u)
		target = Vector3(0.0, 0.48, cz)
		fov = 46.0
		attrs = _dof_faces
	elif n < F_RACE:
		# 05：前から P2 のアップ（低め）。前から見るので左右は逆
		var t0 := (F_S05 - 1) / FPS
		var u := _ease((t - t0) / ((F_RACE - F_S05) / FPS))
		eye = Vector3(-0.85, -0.2, cz + 4.4).lerp(Vector3(-0.9, -0.25, cz + 4.0), u)
		target = Vector3(-0.55, 0.35, cz)
		fov = 44.0
		attrs = _dof_front
	elif n < F_TAUNT:
		# 06・07：引いて 2 人の後ろ・上から。赤い扉のほうへ少しずつ振る
		var t0 := (F_RACE - 1) / FPS
		var u := _ease((t - t0) / ((F_TAUNT - F_RACE) / FPS))
		eye = Vector3(-0.6, 3.3, cz - 8.8).lerp(Vector3(-1.4, 3.5, cz - 8.2), u)
		target = Vector3(-1.2, 0.6, cz + 13.0).lerp(Vector3(-1.8, 0.6, cz + 12.0), u)
		fov = 50.0
	elif n < F_S08:
		# 07b：横（スタート側）から、向き直って煽る P1（左）と倒れた P2（右）を一緒に撮る。爆散も画面の中で見える
		var t0 := (F_TAUNT - 1) / FPS
		var u := _ease((t - t0) / ((F_S08 - F_TAUNT) / FPS))
		var mid_x := (gs.player_x + _taunt_anchor.x) * 0.5
		eye = Vector3(mid_x, 1.45, cz - 8.6).lerp(Vector3(mid_x + 0.4, 1.3, cz - 7.4), u)
		target = Vector3(mid_x, 0.15, cz - 0.6)
		fov = 46.0
		attrs = null
	elif n < F_S09:
		# 08：P1 の後ろ・低めの追従（計画どおりの走りに合わせて進む）
		var run_t := maxf(t - (p1_run_frame - 1) / FPS, 0.0)
		var pz := cz + run_t * PLAYER_SPEED
		var side_u := _ease((t - (F_P1_SIDE - 1) / FPS) / 0.3)
		eye = Vector3(lerpf(P1_START_X - 0.4, DOOR_X - 0.55, side_u), -0.15, pz - 3.3)
		target = Vector3(DOOR_X - 0.2, 0.55, _wall_z())
		fov = 56.0
	else:
		# 09・ロゴ：壁の向こう側から（v1 の S02・S03 と同じ考え方）
		if n == F_S09 or _p1_anchor == Vector2.ZERO:
			_p1_anchor = Vector2(gs.player_x, gs.player_local_z)
		var wall_z := _wall_z()
		var cam_z: float
		var look := Vector3(DOOR_X, 0.55, wall_z)
		var s03 := _ease((n - F_LOGO) / 60.0)
		if _impact_frame < 0 or n < _impact_frame:
			cam_z = wall_z + 6.5
		else:
			if n == _impact_frame:
				_p1_anchor.y = gs.player_local_z
			var p1_z := _p1_anchor.y
			if _cam_gap_at_impact <= 0.0:
				_cam_gap_at_impact = maxf(wall_z + 6.5 - p1_z, 4.3)
			var g := _game_time - _impact_game_time
			var excess := _cam_gap_at_impact - 4.2
			var tau := excess / WALL_SPEED
			cam_z = p1_z + 4.2 + 1.5 * s03 + excess * exp(-g / tau)
			var w := _ease(g / 0.45)
			look = look.lerp(Vector3(_p1_anchor.x, lerpf(0.35, 1.2, s03), p1_z), w)
		var cam_x := lerpf(DOOR_X + 0.1, _p1_anchor.x, _ease((n - F_S09) / 90.0))
		eye = Vector3(cam_x, lerpf(-0.25, 0.9, s03), cam_z)
		target = look
		fov = 53.7
	# 着地の揺れ（乱数を使わない）
	var shake := gs.camera_shake
	if shake > 0.001:
		var a := 0.09 * shake
		eye += Vector3(sin(t * 57.0) * a, cos(t * 43.0) * a, 0.0)
		target += Vector3(sin(t * 61.0) * a * 0.6, cos(t * 47.0) * a * 0.6, 0.0)
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, fov)
	if cam != null:
		cam.h_offset = 0.0
		cam.fov = fov
		cam.global_transform = pose
		cam.attributes = attrs


# ------------------------------------------------------------------ capture & report

func _record(n: int) -> void:
	if (_step % sub) != 0:
		return
	if n % 4 == 1 or (n >= F_P2_HIT - 10 and n <= F_P2_HIT + 20) or (n >= F_P2_BURST - 4 and n <= F_P2_BURST + 8) or (n >= F_P1_HIT - 10 and n <= F_P1_HIT + 20):
		var entry := {"f": n, "p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_local_z, 0.01)],
			"p2": [snappedf(gs.player2_x, 0.01), snappedf(gs.player2_local_z, 0.01)],
			"wall_z": snappedf(_wall_z(), 0.01), "state": gs.game_state, "alive": [gs.p1_alive, gs.p2_alive],
			"emote": [gs.p1_emote, gs.p2_emote], "ts": snappedf(Engine.time_scale, 0.001)}
		if not gs.p2_alive:
			var body := player.get_death_presentation_position(false)
			entry["p2_body"] = [snappedf(body.x, 0.01), snappedf(body.y, 0.01), snappedf(body.z, 0.01)]
		_trace.append(entry)


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
		_send_key(key, false)
	QuizWallScript.keep_after_pass_for_capture = false
	report["impact_frame"] = _impact_frame
	report["impact_frame_planned"] = F_P1_HIT
	report["p2_hit_frame"] = _p2_hit_frame
	report["p2_hit_frame_planned"] = F_P2_HIT
	report["p2_burst_frame"] = _p2_burst_frame
	report["alive_at_end"] = [gs.p1_alive, gs.p2_alive]
	report["saved_images"] = _saved
	report["settings_unchanged"] = _settings_digest() == settings_digest_before
	if not report["settings_unchanged"]:
		failures.append("user://settings.json changed")
	if not gs.p1_alive:
		failures.append("P1 was eliminated during the capture")
	if gs.p2_alive or not gs.p2_wall_impact:
		failures.append("P2 did not crash into the wrong door")
	if absi(_p2_hit_frame - F_P2_HIT) > 3:
		failures.append("P2 hit at %d, planned %d" % [_p2_hit_frame, F_P2_HIT])
	if absi(_impact_frame - F_P1_HIT) > 2:
		failures.append("P1 broke through at %d, planned %d" % [_impact_frame, F_P1_HIT])
	if _p2_burst_frame < F_TAUNT or _p2_burst_frame >= F_S08:
		failures.append("P2 did not burst during the taunt 07b (frame %d)" % _p2_burst_frame)
	report["failures"] = failures
	report["trace"] = _trace
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
	print("[pv_v3_capture] %s" % JSON.stringify(summary))
	QuizManager.game_state = saved_game_state
	QuizManager.player_analytics = saved_analytics
	get_tree().quit(0 if failures.is_empty() else 1)
