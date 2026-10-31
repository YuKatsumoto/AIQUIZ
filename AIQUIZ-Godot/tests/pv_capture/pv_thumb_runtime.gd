extends "res://tests/pv_capture/pv_take_base.gd"

## 応募用サムネイル（1920×1080 の静止画）の背景：コンベアの上で 2 人が競り合いながら問題の壁へ走る。
## 本物の GameWorld（ローカル 2P・10 問・PLAYING）を本物のキーイベントで動かし、短い通しを撮って一番いいコマを選ぶ。
## 絵コンテは docs/pv/thumbnail/（t2 = 真横の並走、t3 = 背中越しに壁へ）。ロゴは docs/pv/thumbnail/finish.py で重ねる。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t3 quality=ultra sub=8 png
##
## 流れ（PV フレーム。60 fps）:
##   撮る前   2 人とも走り出している（PRE_ROLL フレーム）。P2 は P1 より少し遅れて走り出し、走る足の位相をずらす
##   1-      2 人が並んで走る。BRACE から相手のほうへのキーも押し、肩をぶつけて踏ん張る（ゲームの押し合い）
##   SHOVE   押す側がキーを 1 フレーム離して押し直す：肩の予備動作のあと一押し（ゲームの押し合いの「一押し」）
## カメラ：2 人の中点を基準に置く（ゲームの Camera3D を set_director_pose で）。2 人は等速で走るので、中点の z だけ追う。
## 引数（共通のほかに）:
##   shot=t2|t3                     構図の既定（下の SHOTS）
##   cam=ex,ey,ez,tx,ty,tz,fov      カメラ（中点からの x・床からの高さ・中点からの z、注視点も同じ、縦の画角）
##   dof=<先>,<幅>,<量>             背景のぼけ（2 人より <先> m 奥からぼかし始め、<幅> m でぼけきる。量 0〜1。量 0 でぼかさない）
##   wall=<m>                       撮り始めの、P1 から壁までの距離
##   lag=<m>                        P2 が P1 より後ろにいる距離
##   lanes=<P1 の x>,<P2 の x>      走るレーン（後ろから見て +x が左）
##   brace=<f>  shove=<f>  shover=1|2   踏ん張り始め・一押しのフレームと、押す側（brace=0 で押し合わない、shove=0 で一押ししない）
##   day=<0〜1>                     昼の位相
##   hats=<P1>,<P2>                 帽子（HatData の番号）
##   far_stand_cut_z=<z>            奥の観客席（+x）の、z がこれより手前のブロックを観客ごと隠す
##   hide_near_stand=1              手前の観客席（−x）を隠す（カメラを線路から遠く離すとき。カメラの後ろなので写らない）
##   hide_sharks=1                  海のサメを隠す
##   far_stand_offset=<dx>,<dy>,<dz>  奥の観客席（+x）を観客ごと動かす（far_stand_cut_z はそのあとの位置で決める）
##   sprint=<clip>,<P1 の位相>,<P2 の位相>,<rate>  走りの姿を UAL のクリップ（Sprint_Loop など）のその位相（0〜1）に置き換える。
##                                  位相はフレームごとに rate ずつ進む（rate 0 で止めた姿。rate を付けると位相を総なめして選べる）
##   export=<f>                    そのフレーム（最後の刻み）でゲームを止め、Blender で描き直す素材を
##                                  artifacts/pv_capture/<tag>/export/ に書き出して終わる：前景（2 人・壁・コンベア）の
##                                  glTF、カメラ・光・環境・文字の scene.json、背景だけの絵（plate_*）と全体の絵（full_*）、
##                                  粒だけの絵（fx_nodof）と粒を隠した全体の絵（full_nofx_nodof。粒の隠れ方を求める）。
##                                  止めるあいだはゲームの世界ごと止める（粒やプロペラも同じ瞬間のまま）。
##                                  使い方は docs/pv/thumbnail/blender/README.md

const QuizWallScript := preload("res://scripts/world/quiz_wall.gd")
const HANDLE_FRAMES := 0
const EXPORT_RANGE_M := 150.0           # これより遠い壁・文字は書き出さない
const DECK_NODES := ["Floor", "ConveyorSideFrameLeft", "ConveyorSideFrameRight", "ConveyorRunningRails"]

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const FLOOR_Y := -1.2
const WARMUP_FRAMES := 150
const START_Z := 30.0
const PRE_ROLL := 30
const P2_START_DELAY := 7               # P2 は少し遅れて走り出す（足の位相をずらす）

## Q1 は PV と同じ（pv_v3_runtime.gd の Q1_TEXT）。青「56」（正解）は +x（後ろから見て左）、赤「54」は −x
const QUIZZES := [
	["【かけ算】7 × 8 ＝ ？", ["56", "54"]],
	["「たいよう」を漢字で書くと？", ["太陽", "太洋"]],
	["水が氷になる温度は？", ["0℃", "100℃"]],
]
const P2_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_CTRL, KEY_8, KEY_9, KEY_0]

## 構図の既定。cam = [目の x, 高さ, z, 注視点の x, 高さ, z, 縦の画角]（高さは床から。x・z は anchor から：
## players = 2 人の中点、wall = 1 枚目の壁の中心）
## t2：P2 の側（−x）の床すれすれから、長めのレンズで真横に近く。2 人は右へ走り、右の端に壁が迫る。
##     P1 を手前のレーンに置き、P2 を奥のレーンで少し前に出して、2 人とも見えるようにする（押し合わない）
## t3：右うしろの上から。コンベアが右上の壁へ向かい、2 人は画面の中央より右で肩をぶつけ合う
## t5：壁に着いた瞬間の明暗。P1 は青「56」（正解）、P2 は赤「54」の正面を並んで走り、同時に突っ込む。P1 は扉を突き破り、
##     P2（ハート 1）は扉に激突して脱落し、後ろへ吹き飛ぶ。カメラは壁といっしょに動く。突破の少し前から時間を
##     slow 倍にして、破片の散り方のいいコマを細かく選べるようにする。突破した壁は消さずに残す（keep_wall）。
##     ゲームは通過した時点で壁の文字をすべて消すが、サムネイルでは問題の看板と割れていない扉の答えを
##     出したままにする（keep_labels。割れた扉の答えはゲームどおり消えたまま）
const SHOTS := {
	"t2": {"frames": 72, "cam": [-8.5, 0.8, -1.6, 1.47, 0.95, -0.87, 30.0], "dof": [3.0, 10.0, 0.4],
		"wall": 16.0, "lag": -1.5, "lanes": [-0.6, 0.6], "brace": 0, "shove": 0, "shover": 2},
	"t3": {"frames": 72, "cam": [-0.7, 3.5, -4.3, 4.9, -1.2, 8.6, 58.0], "dof": [14.0, 40.0, 0.08],
		"wall": 30.0, "lag": 0.4, "lanes": [0.55, -0.55], "brace": 8, "shove": 44, "shover": 2},
	# t5 のカメラは P1 の側（+x）のうしろ・低めから。左は手前の壁の無地（ロゴの下）、上に空、中央に問題の看板、
	# P1 は砕けた扉の中（画面の 0.5 あたり）、P2 は右で跳ね返される。2 人のレーンは扉の内側寄りにして間を詰め、
	# P2 を 0.35 m 前に出して先にぶつける（P2 が宙を舞っているときに P1 が扉を突き破る）
	"t5": {"frames": 110, "cam": [7.3, 1.1, -12.0, 3.4, 2.57, 1.44, 42.0], "dof": [4.0, 12.0, 0.3],
		"wall": 7.0, "lag": -0.35, "lanes": [2.6, -2.2], "brace": 0, "shove": 0, "shover": 2,
		"anchor": "wall", "p2_hp": 1, "keep_wall": true, "keep_labels": true, "slow_from": 34, "slow": 0.35},
	# t8：t5 の場面を、壁の向こう（P1 の正面）の床すれすれから縦 120° の広角で撮る（ユーザーが画角調整ツールで決めた画角）。
	# 絵コンテ gen_v2/a_shoulder.png（肩から突っ込む）に寄せて、P1 の姿（pose）と、レンズの手前へ飛ぶ演出用の破片（hero_debris）を足す。
	# 演出の値は docs/pv/thumbnail/t8/stage.json（make_stage.py で作る）。使うのは 76 フレーム（export=76 が効くよう、撮るのは 80 まで）
	"t8": {"frames": 80, "cam": [3.23, 1.8, 3.58, -9.13, 1.6, -3.13, 120.0], "dof": [4.0, 12.0, 0.3],
		"stage_file": "res://docs/pv/thumbnail/t8/stage.json",
		"wall": 7.0, "lag": -0.35, "lanes": [2.6, -2.2], "brace": 0, "shove": 0, "shover": 2,
		"anchor": "wall", "p2_hp": 1, "keep_wall": true, "keep_labels": true, "slow_from": 34, "slow": 0.35},
	# t7：絵コンテ gen/t2_side.png をそのまま再現する。カメラは線路に真横（2 人の 62 m 横、床から 2.1 m、縦の画角 7.7° の
	# 超望遠）。位置・高さ・画角は、絵コンテの 2 人の足と頭・地平線・床の奥の縁・壁の端と扉の位置から求めた（ずれ約 6 px）。
	# P2 は 2.8 m 前。書き出すのは 2 人とも大股（前の足を前へ、後ろの足を後ろへ伸ばす）の 71 フレームで、壁はそのとき P1 の
	# 5.75 m 先（走りの周期は約 23 フレーム。48 も同じ形）。帽子は絵コンテと同じ（P1 キリン、P2 魔法使い）。絵コンテは文字なしなので
	# 壁の文字を隠す。カメラは手前の観客席の後ろになるので、その観客席を隠す（写らない）。背景は絵コンテに寄せて置き直す：
	# 奥の観客席を 130 m 遠ざけ、z が 35 より手前のブロックを隠す（左は海、右に観客）。高層ビルと岩の島を真横から見える所へ。
	# 2 人の姿はゲームの全力疾走（UAL の Sprint_Loop。ゲームの走り Run.fbx は上体がまっすぐで歩幅も小さい）の、後ろ足を
	# まっすぐ後ろへ伸ばし前の膝を前へ出した瞬間（P1 は 0.33、P2 は反対の足の 0.83）。
	# 絵コンテの空は小さな積雲が散らばる。ゲームの空（ProceduralSky）は雲なしなので、街の奥（カメラの描画の限り 5000 m の手前）に積雲の板を並べる（clouds）
	"t7": {"frames": 72, "cam": [-61.7, 2.13, -2.42, 38.3, 2.706, -2.42, 7.73], "dof": [3.0, 10.0, 0.0],
		"wall": 18.16, "lag": -2.84, "lanes": [-0.6, 0.6], "brace": 0, "shove": 0, "shover": 2,
		"hats": [14, 7], "hide_wall_text": true, "hide_near_stand": true, "hide_sharks": true,
		"far_stand_offset": [130.0, 0.0, 7.5], "far_stand_cut_z": 35.0,
		"place_backdrop": {"AQS_BG_City": {"center": [4040.0, 201.0], "rot_y_deg": 90.0, "scale": 0.6},
			"AQS_BG_IslandRocky": {"center": [2900.0, -175.0], "rot_y_deg": 90.0, "scale": 0.3}},
		"clouds": {"seed": 11, "count": 46, "dist": [4400.0, 4900.0], "v": [-0.02, 0.46], "w": [0.15, 0.05]},
		"sprint": {"clip": "Sprint_Loop", "phase": [0.33, 0.83], "rate": 0.0}},
}
## 撮影用の雲（t7 の clouds）。オンライン演出の積雲（StagingClouds と同じ板とシェーダー）を、遠くでも消えないようにして使う
const CLOUD_SHADER := preload("res://shaders/online_staging_cloud.gdshader")

var helper: Node
var gs: QuizGameState
var world: Node
var player: PlayerController
var camera_controller: Node
var cam: Camera3D
var attrs: CameraAttributesPractical
var shot := "t3"
var cfg := {}
var day_phase := 0.25
var _overrides := {}
var _trace: Array = []
var _shove_frame := -1
var export_frame := 0
var _export_pending := false
var _exporting := false


func _init() -> void:
	take_name = "thumb"


func _default_frames() -> int:
	return int(cfg.get("frames", 72)) + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	var kv := arg.split("=", true, 1)
	if kv.size() != 2:
		return
	var v := kv[1].split(",")
	match kv[0]:
		"shot":
			shot = kv[1]
		"cam":
			_overrides["cam"] = Array(v).map(func(s: String) -> float: return float(s))
		"dof":
			_overrides["dof"] = Array(v).map(func(s: String) -> float: return float(s))
		"lanes":
			_overrides["lanes"] = Array(v).map(func(s: String) -> float: return float(s))
		"wall", "lag", "slow", "far_stand_cut_z":
			_overrides[kv[0]] = float(kv[1])
		"hats":
			_overrides["hats"] = Array(v).map(func(s: String) -> int: return int(s))
		"hide_near_stand", "hide_sharks":
			_overrides[kv[0]] = kv[1] in ["1", "true"]
		"far_stand_offset":
			_overrides["far_stand_offset"] = Array(v).map(func(s: String) -> float: return float(s))
		"brace", "shove", "shover", "slow_from", "frames":
			_overrides[kv[0]] = int(kv[1])
		"sprint":
			_overrides["sprint"] = {"clip": v[0], "phase": [float(v[1]), float(v[2])], "rate": float(v[3]) if v.size() > 3 else 0.0}
		"day":
			day_phase = float(kv[1])
		"stage":
			_overrides["stage_file"] = kv[1]
		"export":
			export_frame = int(kv[1])


func run() -> void:
	# 引数を読む前に構図の既定を決める（frames の既定に使う）
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.trim_prefix("shot=")
	cfg = (SHOTS.get(shot, SHOTS["t3"]) as Dictionary).duplicate(true)
	if tag == "":
		tag = "thumb_" + shot
	await super.run()


func _setup() -> void:
	# 演出の値のファイル（t8 の stage）を先に重ね、引数（cam= など）はそのあとで上書きする。stage=<path> で差し替えられる
	if _overrides.has("stage_file"):
		cfg["stage_file"] = _overrides["stage_file"]
	if cfg.has("stage_file"):
		var stage: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(cfg["stage_file"])))
		if stage is Dictionary:
			cfg.merge(stage, true)
		else:
			failures.append("stage_file を読めない：%s" % cfg["stage_file"])
	for key: String in _overrides:
		cfg[key] = _overrides[key]
	await _build_world()
	_set_station()
	if cfg.has("p2_hp"):
		gs.p2_hp = int(cfg["p2_hp"])
	if cfg.get("keep_wall", false):
		QuizWallScript.keep_after_pass_for_capture = true
	hide_overlays()
	attrs = CameraAttributesPractical.new()
	report["plan"] = {"shot": shot, "cfg": cfg, "day": day_phase, "start_z": START_Z, "pre_roll": PRE_ROLL}
	await _pre_roll()


func _build_world() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	_install_quizzes()
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
	var hats: Array = cfg.get("hats", [P1_HAT, P2_HAT])
	gs.p1_hat = int(hats[0])
	gs.p2_hat = int(hats[1])
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_PLAYING
	QuizManager.game_state = gs
	world = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)             # 準備の間はゲームの状態を進めない
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	await _frames(30)
	_set_station()
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", day_phase)
	camera_controller = world.get("camera_controller")
	cam = camera_controller.get_node_or_null("Camera3D") as Camera3D
	await _frames(WARMUP_FRAMES)


func _install_quizzes() -> void:
	for index in range(gs.quiz_list.size()):
		var e: Array = QUIZZES[index % QUIZZES.size()]
		var choices := PackedStringArray(e[1])
		if gs.num_choices_for_index(index) == 4:
			choices = PackedStringArray([choices[0], choices[1], "その他", "わからない"])
		gs.quiz_list[index] = QuizItem.create(e[0], choices, 0, "", "OFFLINE")
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.load_current_quiz()


## 撮る前に走っておく分だけ手前から始める（pv_s16_runtime.gd と同じ考え方）
func _set_station() -> void:
	var run := PRE_ROLL * gs.tuning.player_speed / FPS
	var p1_z := START_Z - run
	var wall: float = cfg["wall"]
	var scroll := gs.tuning.wall_start_z - (START_Z + wall) - gs.tuning.wall_speed_override * PRE_ROLL / FPS
	var lanes: Array = cfg["lanes"]
	gs.world_scroll_z = scroll
	gs.player_x = lanes[0]
	gs.player2_x = lanes[1]
	gs.player_z = scroll + p1_z
	gs.player2_z = scroll + p1_z - float(cfg["lag"]) + P2_START_DELAY * gs.tuning.player_speed / FPS
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.camera_shake = 0.0
	gs.set("_active_wall_speed", gs.tuning.wall_speed_override)
	# チップソーは画面に入れない：ずっと後ろに置き、追い始めの猶予の中に留める
	gs.saw.local_z = p1_z - 80.0
	gs.saw.elapsed = 0.0


func _keys_at(n: int) -> Dictionary:
	var want: Dictionary = {}
	want[KEY_W] = true
	if n > -PRE_ROLL + P2_START_DELAY:
		want[KEY_UP] = true
	var brace: int = cfg["brace"]
	var shove: int = cfg["shove"]
	if brace > 0 and n >= brace:
		# 相手のほうへ：P1（左）は D、P2（右）は ←
		var p1_side := n != shove or int(cfg["shover"]) != 1
		var p2_side := n != shove or int(cfg["shover"]) != 2
		if p1_side:
			want[KEY_D] = true
		if p2_side:
			want[KEY_LEFT] = true
	if gs != null and not gs.p2_alive:
		for key: Variant in P2_KEYS:
			want.erase(key)
	return want


## 2 人を走らせておく（撮らない）。刻みは撮影と同じ
func _pre_roll() -> void:
	world.set("_replay_mode", false)
	for i in range(PRE_ROLL * sub):
		var n := -PRE_ROLL + int(floor(float(i) / sub)) + 1
		hold_keys(_keys_at(n))
		world.set("_push_focus_lost", false)
		await get_tree().process_frame
		_apply_camera()


func _before_update(n: int) -> void:
	hold_keys(_keys_at(n))
	world.set("_push_focus_lost", false)


func _update(n: int, _t: float, _dt: float) -> void:
	if _shove_frame < 0 and n >= int(cfg["shove"]) and int(cfg["shove"]) > 0:
		_shove_frame = n
	if cfg.get("keep_labels", false):
		_restage_labels()
	if cfg.get("hide_wall_text", false):
		# 文字だけを透明にする（Label3D を隠すと、その子の問題の看板の板まで消える）
		for node: Node in world.get_node("WallContainer").find_children("*", "Label3D", true, false):
			var label := node as Label3D
			label.modulate.a = 0.0
			label.outline_modulate.a = 0.0
	if cfg.get("hide_near_stand", false):
		var near := world.find_child("GrandstandLeft", true, false) as Node3D
		if near != null:
			near.visible = false
	if cfg.get("hide_sharks", false):
		var sharks := world.find_child("OceanSharks", true, false) as Node3D
		if sharks != null:
			sharks.visible = false
	if cfg.has("far_stand_offset"):
		var far := world.find_child("GrandstandRight", true, false) as Node3D
		if far != null:
			if not far.has_meta("thumb_home"):
				far.set_meta("thumb_home", far.global_position)
			var o: Array = cfg["far_stand_offset"]
			far.global_position = (far.get_meta("thumb_home") as Vector3) + Vector3(o[0], o[1], o[2])
	if cfg.has("far_stand_cut_z"):
		_hide_far_stand(float(cfg["far_stand_cut_z"]))
	for node_name: String in cfg.get("place_backdrop", {}):
		_place_backdrop(node_name, cfg["place_backdrop"][node_name])
	_apply_camera()
	if cfg.has("clouds"):
		_place_clouds(cfg["clouds"])
	if cfg.has("sprint"):
		# ゲームの処理（PlayerController が走りのアニメを当てる）のあと、描く前に置き換える
		_apply_sprint.call_deferred(cfg["sprint"], n)
	if cfg.has("pose"):
		apply_pose.call_deferred(cfg["pose"])
	stage_debris()
	_record(n)
	if export_frame > 0 and n == export_frame and (_step % sub) == 0 and not _export_pending:
		# この刻みの絵が描かれたあと、ゲームを止める（次のフレームからは物理もゲームの処理も進まない）
		_export_pending = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true


func _process(dt: float) -> void:
	if _exporting:
		return
	if _export_pending:
		_exporting = true
		_freeze_world()
		_do_export.call_deferred()
		return
	super(dt)


## 書き出しのあいだ、ゲームの世界ごと止める。GameWorld は自分を PROCESS_MODE_ALWAYS にしているので、ツリーを止めても
## 物理のほか（GPUParticles3D の粒、プロペラなど）は動き続ける。止めたフレームの絵が描かれたあと（次のフレームの頭）に呼ぶ
func _freeze_world() -> void:
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	for node: Node in world.find_children("*", "GPUParticles3D", true, false):
		(node as GPUParticles3D).speed_scale = 0.0
	for node: Node in world.find_children("*", "CPUParticles3D", true, false):
		(node as CPUParticles3D).speed_scale = 0.0


func _mid() -> Vector3:
	if cfg.get("anchor", "players") == "wall":
		return Vector3(0.0, FLOOR_Y, _wall0_z())
	return Vector3(0.0, FLOOR_Y, (gs.player_local_z + gs.player2_local_z) * 0.5)


## 1 枚目の壁の中心の z（描画座標）。突破しても次の壁へ移らない
func _wall0_z() -> float:
	return gs.tuning.wall_start_z - gs.world_scroll_z


## 1 枚目の壁（いちばん近い QuizWall）
func _wall0_node() -> Node3D:
	var best: Node3D = null
	for child: Node in world.get_node("WallContainer").get_children():
		if child is Node3D and "door_labels" in child:
			if best == null or absf((child as Node3D).global_position.z - _wall0_z()) < absf(best.global_position.z - _wall0_z()):
				best = child as Node3D
	return best


## 通過で消えた壁の文字を戻す：問題の看板と、割れていない扉の答え（割れた扉の答えは消えたまま）
func _restage_labels() -> void:
	var wall := _wall0_node()
	if wall == null:
		return
	var doors: Array = wall.get("doors")
	var labels: Array = wall.get("door_labels")
	for i in range(mini(doors.size(), labels.size())):
		var door := doors[i] as MeshInstance3D
		var label := labels[i] as Label3D
		if is_instance_valid(door) and is_instance_valid(label):
			label.visible = door.visible
	var question := wall.get("gameplay_question_label") as Label3D
	if is_instance_valid(question):
		question.visible = true


## 遠景（StadiumBackdrop の島・高層ビルなど）を置き直す：見た目の中心（AABB の中心）を軸に y 軸まわりに回して拡大し、
## 中心を (x, z) へ動かす（高さはそのまま）。place = {"center": [x, z], "rot_y_deg": 度, "scale": 倍}。最初の姿から毎回やり直す
func _place_backdrop(node_name: String, place: Dictionary) -> void:
	var node := world.find_child(node_name, true, false) as Node3D
	if node == null:
		return
	if not node.has_meta("thumb_home"):
		node.set_meta("thumb_home", node.global_transform)
	var home: Transform3D = node.get_meta("thumb_home")
	node.global_transform = home
	var box := AABB()
	var first := true
	for child: Node in [node] + node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var center := box.get_center()
	center.y = box.position.y
	var c: Array = place["center"]
	var spin := Transform3D(Basis(Vector3.UP, deg_to_rad(float(place.get("rot_y_deg", 0.0)))).scaled(Vector3.ONE * float(place.get("scale", 1.0))), Vector3.ZERO)
	var to := Vector3(float(c[0]), center.y, float(c[1]))
	node.global_transform = Transform3D.IDENTITY.translated(to) * spin * Transform3D.IDENTITY.translated(-center) * home


## 空に積雲を散らす。画面の位置（横 0〜1、縦 v）で決め、カメラから dist m 先に置く（街より奥。カメラについて動く）。
## 雲の幅は画面の幅の割合 w（上 → 地平線へ小さく）。c = {"seed", "count", "dist": [近, 遠], "v": [上, 下], "w": [上の幅, 下の幅]}
func _place_clouds(c: Dictionary) -> void:
	var holder := world.get_node_or_null("ThumbClouds") as MultiMeshInstance3D
	if holder == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mm.mesh = quad
		mm.instance_count = int(c["count"])
		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		material.set_shader_parameter("fade_far", 1.0e6)
		holder = MultiMeshInstance3D.new()
		holder.name = "ThumbClouds"
		holder.multimesh = mm
		holder.material_override = material
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))
		world.add_child(holder)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(c["seed"])
		var spots: Array = []
		for i in range(mm.instance_count):
			# 近すぎる場所は引き直す（かたまらないように）
			var spot := Vector3(rng.randf_range(-0.05, 1.05), rng.randf_range(float(c["v"][0]), float(c["v"][1])), rng.randf_range(float(c["dist"][0]), float(c["dist"][1])))
			for retry in range(12):
				if spots.all(func(s: Vector3) -> bool: return Vector2(s.x - spot.x, (s.y - spot.y) * 1.8).length() > 0.075):
					break
				spot = Vector3(rng.randf_range(-0.05, 1.05), rng.randf_range(float(c["v"][0]), float(c["v"][1])), spot.z)
			spots.append(spot)
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf_range(0.75, 1.0), 0.0))
		holder.set_meta("spots", spots)
	var view := cam.global_transform
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var size := get_viewport().get_visible_rect().size
	var tan_h := tan_v * size.x / size.y
	var spots: Array = holder.get_meta("spots")
	var v0 := float(c["v"][0])
	var v1 := float(c["v"][1])
	for i in range(spots.size()):
		var s: Vector3 = spots[i]
		var dir := -view.basis.z + view.basis.x * (s.x * 2.0 - 1.0) * tan_h + view.basis.y * (1.0 - s.y * 2.0) * tan_v
		var width := lerpf(float(c["w"][0]), float(c["w"][1]), clampf((s.y - v0) / maxf(v1 - v0, 0.001), 0.0, 1.0)) * 2.0 * tan_h * s.z
		var board := width / 0.85                # 板のうち雲は幅の約 85 %。縦横は StagingClouds と同じ 1.6 : 0.75
		var basis := Basis.from_scale(Vector3(board, board * 0.75 / 1.6, 1.0))
		holder.multimesh.set_instance_transform(i, Transform3D(basis, view.origin + dir.normalized() * s.z))


## 2 人の姿を、UAL のクリップ（ゲームのリザルトの歩きなどと同じしくみ：AnimationRig.seek_ual_clip と
## PlayerController._apply_skeleton_pose）の決めた位相の姿にする。c = {"clip", "phase": [P1, P2], "rate"}。
## 位相 = phase + rate × フレーム
func _apply_sprint(c: Dictionary, n: int) -> void:
	var phases: Array = c["phase"]
	for i in range(2):
		var rig := player.get("_p1_rig" if i == 0 else "_p2_rig") as AnimationRig
		var parts: Dictionary = player.get("p1_parts" if i == 0 else "p2_parts")
		if rig == null or not rig.is_rigged:
			failures.append("P%d の骨組みがない（sprint を当てられない）" % (i + 1))
			continue
		var ratio := fposmod(float(phases[i]) + float(c.get("rate", 0.0)) * n, 1.0)
		if rig.seek_ual_clip(String(c["clip"]), ratio):
			player.call("_apply_skeleton_pose", parts, rig.active_skeleton, rig.active_bone_indices, rig.mirror_x)
		else:
			failures.append("クリップ %s がない" % c["clip"])


## 1 人の姿を作る（t8 の pose）：UAL のクリップのその位相に置いてから、部品を世界の軸まわりに回す（その部品から先がいっしょに回る）。
## p = {"who": 1|2, "clip": 名前, "phase": 0〜1, "lib": "ual2"（省略で UAL1）, "rot": [[部品, "x"|"y"|"z", 度], ...]}。部品は PlayerController の
## parts の名前（pelvis・spine・neck・head_pivot・l_shoulder・l_elbow・l_wrist・l_hip・l_knee・l_ankle ほか。r_ も同じ）。
## 回す順に並べる（親から先に）。毎回クリップの姿からやり直すので、何度呼んでも同じ姿になる
func apply_pose(p: Dictionary) -> void:
	var who := int(p.get("who", 1))
	var rig := player.get("_p1_rig" if who == 1 else "_p2_rig") as AnimationRig
	var parts: Dictionary = player.get("p1_parts" if who == 1 else "p2_parts")
	if rig == null or not rig.is_rigged:
		failures.append("P%d の骨組みがない（pose を当てられない）" % who)
		return
	# lib = "ual2" で UAL2（Shield_Dash・Melee_Hook など）、ほかは UAL1（Sprint_Loop・Punch_Cross など）
	var slot := AnimationRig.SLOT_UAL2 if String(p.get("lib", "")) == "ual2" else AnimationRig.SLOT_UAL
	if not rig.seek_ual_clip(String(p.get("clip", "Sprint_Loop")), float(p.get("phase", 0.33)), slot):
		failures.append("クリップ %s がない" % p.get("clip"))
		return
	player.call("_apply_skeleton_pose", parts, rig.active_skeleton, rig.active_bone_indices, rig.mirror_x)
	var axes := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
	for r: Array in p.get("rot", []):
		var part := parts.get(String(r[0])) as Node3D
		if part != null:
			part.global_basis = Basis(axes[String(r[1])], deg_to_rad(float(r[2]))) * part.global_basis


## 演出用の破片（t8）：ゲームの破片（物理で飛ぶ箱）に、画面の位置で決めた箱を足す。カメラについて置き直す。
## cfg["hero_debris"] = [[u, v, 距離, 幅, 高さ, 奥行き, 回転 x, y, z（度）], ...]（u・v は画面の横・縦 0〜1、距離はカメラから m）。
## cfg["anchored_debris"] は同じ並びで、位置だけ anchor（t8 は 1 枚目の壁の中心・床）からの x・y・z（m）。扉の穴の縁の割れ残りなど。
## cfg["hide_chunks"] = true でゲームの破片を隠す。色は 1 枚目の壁の、割れた扉の色（少しずつ白へずらす）
func stage_debris() -> void:
	if cfg.get("hide_chunks", false):
		for node: Node in world.get_node("WallContainer").get_children():
			if node is RigidBody3D:
				(node as RigidBody3D).visible = false
	var holder := world.get_node_or_null("ThumbDebris") as Node3D
	if holder != null:
		holder.free()
	var list: Array = cfg.get("hero_debris", [])
	var anchored: Array = cfg.get("anchored_debris", [])
	if (list.is_empty() and anchored.is_empty()) or cam == null:
		return
	holder = Node3D.new()
	holder.name = "ThumbDebris"
	world.add_child(holder)
	var base := _broken_door_color()
	var view := Vector2(get_viewport().get_visible_rect().size)
	for i in range(list.size() + anchored.size()):
		var d: Array = list[i] if i < list.size() else anchored[i - list.size()]
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(d[3], d[4], d[5])
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base.lerp(Color.WHITE, 0.04 + 0.16 * fposmod(i * 0.618, 1.0))
		mat.roughness = 0.6
		mat.metallic = 0.05
		mi.material_override = mat
		holder.add_child(mi)
		var pos := cam.project_position(Vector2(float(d[0]) * view.x, float(d[1]) * view.y), float(d[2])) if i < list.size() \
			else _mid() + Vector3(d[0], d[1], d[2])
		mi.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(d[6]), deg_to_rad(d[7]), deg_to_rad(d[8]))), pos)


func _broken_door_color() -> Color:
	var wall := _wall0_node()
	if wall != null:
		for door: MeshInstance3D in wall.get("doors"):
			if is_instance_valid(door) and not door.visible and door.material_override is StandardMaterial3D:
				return (door.material_override as StandardMaterial3D).albedo_color
	return Color(0.2, 0.55, 0.95)


## 奥の観客席（GrandstandRight。+x）のうち、ブロックの中心が cut_z より手前（−z）のものを、観客ごと隠す
func _hide_far_stand(cut_z: float) -> void:
	var stand := world.find_child("GrandstandRight", true, false) as Node3D
	if stand == null:
		return
	var blocks := stand.get_node_or_null("Blocks")
	var people := stand.get_node_or_null("Spectators")
	if blocks == null:
		return
	var mascot := stand.get_node_or_null("Mascot") as Node3D       # 観客席のマスコット（ブロック 1 の通路）
	if mascot != null:
		mascot.visible = mascot.global_position.z >= cut_z
	for block: Node in blocks.get_children():
		var hide := (block as Node3D).global_position.z < cut_z
		(block as Node3D).visible = not hide
		if people != null:
			for suffix: String in ["", "Props"]:
				var batch := people.get_node_or_null(String(block.name) + suffix) as Node3D
				if batch != null:
					batch.visible = not hide


## 突破の少し前（slow_from）から、ゲームの時間を slow 倍で進める
func _game_time_at(pv: float) -> float:
	var t0 := float(cfg.get("slow_from", 0)) / FPS
	var s := float(cfg.get("slow", 1.0))
	if t0 <= 0.0 or s >= 1.0 or pv <= t0:
		return pv
	return t0 + (pv - t0) * s


func _apply_camera() -> void:
	var saw_node := world.get_node_or_null("SawChaseController") as Node3D
	if saw_node != null:
		saw_node.visible = false
	var c: Array = cfg["cam"]
	var m := _mid()
	var eye := Vector3(m.x + c[0], FLOOR_Y + c[1], m.z + c[2])
	var target := Vector3(m.x + c[3], FLOOR_Y + c[4], m.z + c[5])
	var fov: float = c[6]
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, fov)
	if cam == null:
		return
	cam.h_offset = 0.0
	cam.fov = fov
	cam.global_transform = pose
	var d: Array = cfg["dof"]
	if float(d[2]) > 0.0:
		var subject := eye.distance_to(m + Vector3(0.0, 1.0, 0.0))
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = subject + float(d[0])
		attrs.dof_blur_far_transition = float(d[1])
		# dof_near = [距離, 幅]：カメラからその距離より手前をぼかす（t8 のレンズの手前を飛ぶ破片）
		var near: Array = cfg.get("dof_near", [])
		attrs.dof_blur_near_enabled = near.size() >= 2
		if attrs.dof_blur_near_enabled:
			attrs.dof_blur_near_distance = float(near[0])
			attrs.dof_blur_near_transition = float(near[1])
		attrs.dof_blur_amount = float(d[2])
		cam.attributes = attrs
	else:
		cam.attributes = null


func _record(n: int) -> void:
	if (_step % sub) != 0:
		return
	var entry := {"f": n, "p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_local_z, 0.01)],
		"p2": [snappedf(gs.player2_x, 0.01), snappedf(gs.player2_local_z, 0.01)],
		"wall_ahead": snappedf(gs.tuning.wall_start_z - gs.world_scroll_z - gs.player_local_z, 0.01),
		"alive": [gs.p1_alive, gs.p2_alive], "hp": [gs.p1_hp, gs.p2_hp], "wall_index": gs.current_wall_index,
		"ts": snappedf(Engine.time_scale, 0.001)}
	if not gs.p2_alive:
		var body := player.get_death_presentation_position(false)
		entry["p2_body"] = [snappedf(body.x, 0.01), snappedf(body.y, 0.01), snappedf(body.z, 0.01)]
	_trace.append(entry)


# ------------------------------------------------------------------ Blender へ書き出す（export=<f>）

## 止めた瞬間を書き出して終わる。前景は glTF、そのほかは scene.json。背景だけの絵は前景を隠して撮る
func _do_export() -> void:
	if cfg.has("sprint"):
		_apply_sprint(cfg["sprint"], export_frame)
	if cfg.has("pose"):
		apply_pose(cfg["pose"])
	# 演出用の破片（t8）は Blender で置き直すので書き出さない（GameWorld の直下なので、背景だけの絵にも写ってしまう）
	var thumb_debris := world.get_node_or_null("ThumbDebris")
	if thumb_debris != null:
		thumb_debris.free()
	await _frames(3)                         # 止めたフレームの撮影（_capture）を済ませる
	var dir := out + "export/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var groups := _foreground_groups()
	var info := {"frame": export_frame, "sub": sub, "shot": shot, "quality": quality}
	info["state"] = {"world_scroll_z": gs.world_scroll_z, "p1": [gs.player_x, gs.player_y, gs.player_local_z],
		"p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "wall_z": gs.tuning.wall_start_z - gs.world_scroll_z}
	info["camera"] = _camera_info()
	info["lights"] = _light_info()
	info["environment"] = _environment_info()
	info["labels"] = _label_info()
	info["joints"] = {"P1": _joint_info("p1_parts"), "P2": _joint_info("p2_parts")}
	info["meshes"] = _export_gltf(groups, dir + "foreground.glb")
	var saved_attrs := cam.attributes
	cam.attributes = null
	await _frames(4)
	_grab(dir + "full_nodof.png")
	var roots := _foreground_roots()
	var fx := _fx_roots()
	if not fx.is_empty():
		# 粒だけを隠した絵。full_nodof との差が、粒の見えている所（前景の後ろに隠れた粒は差が出ない）
		for node: Node3D in fx:
			node.visible = false
		await _frames(4)
		_grab(dir + "full_nofx_nodof.png")
	for node: Node3D in roots + fx:
		node.visible = false
	await _frames(4)
	_grab(dir + "plate_nodof.png")
	cam.attributes = saved_attrs
	await _frames(4)
	_grab(dir + "plate_dof.png")
	for node: Node3D in roots + fx:
		node.visible = true
	await _frames(4)
	_grab(dir + "full_dof.png")
	if not fx.is_empty():
		await _grab_fx(dir + "fx_nodof.png", fx)
		info["fx_roots"] = fx.map(func(n: Node3D) -> String: return String(world.get_path_to(n)))
	var file := FileAccess.open(dir + "scene.json", FileAccess.WRITE)
	if file == null:
		failures.append("scene.json を書けない")
	else:
		file.store_string(JSON.stringify(info, "  "))
		file.close()
	var counts := {}
	for group: String in groups:
		counts[group] = (groups[group] as Array).size()
	report["export"] = {"dir": dir, "meshes": counts, "labels": (info["labels"] as Array).size()}
	_running = false
	_finish()


## プレイヤーの関節（PlayerController の parts のノード）：名前 → 位置と向き、ノードの道筋、親の関節の名前。
## Blender で部位をこの関節の子にして、関節を回して姿を付け直す（t8）。部位の glTF の行の path が、どの関節の下かを決める
func _joint_info(parts_key: String) -> Dictionary:
	var parts: Dictionary = player.get(parts_key)
	var by_node := {}
	for key: Variant in parts:
		var value: Variant = parts[key]          # parts には部品のほかの値（寸法など）も入っている
		if value is Node3D and is_instance_valid(value):
			by_node[value] = String(key)
	var out := {}
	for node: Node3D in by_node:
		var parent := node.get_parent()
		while parent != null and not by_node.has(parent):
			parent = parent.get_parent()
		out[by_node[node]] = {"xform": _xform(node.global_transform), "path": String(world.get_path_to(node)),
			"parent": by_node[parent] if parent != null else ""}
	return out


## 前景のいちばん上のノード（背景だけの絵ではこれを隠す）
func _foreground_roots() -> Array[Node3D]:
	var candidates: Array[Node] = [world.get_node_or_null("Player"), world.get_node_or_null("WallContainer"),
		world.get_node_or_null("RagdollLimbsP1"), world.get_node_or_null("RagdollLimbsP2")]
	var stage := world.get("stage_env") as Node
	if stage != null:
		for node_name: String in DECK_NODES:
			candidates.append(stage.find_child(node_name, true, false))
	var roots: Array[Node3D] = []
	for node: Node in candidates:
		if node is Node3D:
			roots.append(node as Node3D)
		elif node != null:
			failures.append("前景のノード %s が Node3D ではない" % node.name)
	return roots


## 粒（扉が砕けたときの火花・土ぼこり）を出す ParticleSpawner。glTF に入らないので、別の絵（fx_nodof.png）にする。
## ステージ（StageEnvironment）にも粒はあるが、背景の一部なので背景の絵のほうに残す
func _fx_roots() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var spawner := world.get_node_or_null("ParticleSpawner") as Node3D
	if spawner != null and spawner.is_visible_in_tree():
		found.append(spawner)
	return found


## 粒だけの絵：粒のほかの形を「影だけ」にし（影を落とさないものは隠す）、背景を透明にして撮る（ぼかさない。アルファつき）。
## 光（太陽）はそのまま残すので、粒の色と、粒に落ちる影は全体の絵と同じになる
func _grab_fx(path: String, fx: Array[Node3D]) -> void:
	var hidden: Array[Node3D] = []
	var shadow_only := {}
	for node: Node in world.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi is Light3D or not vi.is_visible_in_tree() or fx.any(func(f: Node3D) -> bool: return f == vi or f.is_ancestor_of(vi)):
			continue
		var gi := vi as GeometryInstance3D
		if gi != null and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_only[gi] = gi.cast_shadow
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif gi != null or vi is Decal:
			vi.visible = false
			hidden.append(vi)
	var env: Environment = null
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null:
			env = (node as WorldEnvironment).environment
	var saved_bg := env.background_mode if env != null else Environment.BG_SKY
	var saved_attrs := cam.attributes
	cam.attributes = null
	get_viewport().transparent_bg = true
	if env != null:
		env.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	await _frames(4)
	_grab(path)
	get_viewport().transparent_bg = false
	if env != null:
		env.background_mode = saved_bg
	cam.attributes = saved_attrs
	for node: Node3D in hidden:
		node.visible = true
	for gi: GeometryInstance3D in shadow_only:
		gi.cast_shadow = shadow_only[gi]


## 書き出す MeshInstance3D を役ごとに：P1・P2（帽子つき）、WALL（壁・扉・問題の看板）、DECK（床・枠・レール）
func _foreground_groups() -> Dictionary:
	var groups := {"P1": [], "P2": [], "WALL": [], "DECK": []}
	var player_node := world.get_node("Player")
	var p2_root := player_node.get_node_or_null("Player2")
	for mi: MeshInstance3D in _visible_meshes(player_node):
		var is_p2 := p2_root != null and (mi == p2_root or p2_root.is_ancestor_of(mi))
		(groups["P2"] if is_p2 else groups["P1"]).append(mi)
	# 壁に激突して脱落したプレイヤーは、Player の外（GameWorld の直下）のラグドールになって飛ぶ
	for mi: MeshInstance3D in _visible_meshes(world.get_node_or_null("RagdollLimbsP1")):
		groups["P1"].append(mi)
	for mi: MeshInstance3D in _visible_meshes(world.get_node_or_null("RagdollLimbsP2")):
		groups["P2"].append(mi)
	for mi: MeshInstance3D in _visible_meshes(world.get_node("WallContainer")):
		if mi.global_position.distance_to(cam.global_position) > EXPORT_RANGE_M:
			continue
		if mi.get_active_material(0) is ShaderMaterial:   # 見えない WorldBorder（透明のシェーダー）
			continue
		groups["WALL"].append(mi)
	var stage := world.get("stage_env") as Node
	for node_name: String in DECK_NODES:
		var node := stage.find_child(node_name, true, false) if stage != null else null
		for mi: MeshInstance3D in _visible_meshes(node):
			groups["DECK"].append(mi)
	return groups


func _visible_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root == null:
		return found
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null and mi.is_visible_in_tree() and not found.has(mi):
			found.append(mi)
	return found


## 前景を glTF に。変換を持たせたコピーを 1 つの根の下に並べる（BoxMesh などは ArrayMesh に直す）。
## シェーダーの材質と、物体の座標で貼る（triplanar）材質は、glTF で表せないので色だけの仮の材質にし、元の値は scene.json に残す
func _export_gltf(groups: Dictionary, path: String) -> Array:
	var rows: Array = []
	var root := Node3D.new()
	root.name = "THUMB"
	var cache := {}
	for group: String in groups:
		var holder := Node3D.new()
		holder.name = group
		root.add_child(holder)
		var index := 0
		for mi: MeshInstance3D in groups[group]:
			var copy := MeshInstance3D.new()
			copy.name = "%s_%03d_%s" % [group, index, String(mi.name).validate_node_name()]
			index += 1
			var mesh := _array_mesh(mi.mesh)
			var mats: Array = []
			for s in range(mi.mesh.get_surface_count()):
				var src := mi.get_active_material(s)
				var conv := _export_material(group, src, cache)
				mesh.surface_set_material(s, conv)
				copy.set_surface_override_material(s, conv)
				mats.append(_material_info(src, conv))
			copy.mesh = mesh
			copy.transform = mi.global_transform
			holder.add_child(copy)
			rows.append({"name": String(copy.name), "group": group, "path": String(world.get_path_to(mi)),
				"mesh": _mesh_info(mi.mesh), "xform": _xform(mi.global_transform), "materials": mats,
				"motion": _motion_info(mi)})
	var doc := GLTFDocument.new()
	doc.visibility_mode = GLTFDocument.VISIBILITY_MODE_EXCLUDE
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	if err != OK:
		failures.append("glTF の書き出しに失敗（%d）" % err)
	root.free()
	return rows


## 剛体（脱落したプレイヤーのラグドールの部位・扉の破片）の、止めた瞬間の動き：体の原点の位置と速度、角速度（ゲームの秒）。
## Blender では、ここから少し前の位置を出してモーションブラーにする。剛体でないもの（走っている P1 など）は null
func _motion_info(mi: Node) -> Variant:
	var node := mi.get_parent()
	while node != null and not (node is RigidBody3D):
		node = node.get_parent()
	if node == null:
		return null
	var body := node as RigidBody3D
	var v := body.linear_velocity           # 重心の速度
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state != null:
		v = state.get_velocity_at_local_position(Vector3.ZERO)     # 体の原点の速度（回転の分を含む）
	return {"body": String(world.get_path_to(body)), "origin": _jsonable(body.global_position),
		"v": _jsonable(v), "w": _jsonable(body.angular_velocity)}


func _array_mesh(mesh: Mesh) -> ArrayMesh:
	var copy := ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			primitive = (mesh as ArrayMesh).surface_get_primitive_type(s)
		copy.add_surface_from_arrays(primitive, mesh.surface_get_arrays(s))
	return copy


func _export_material(group: String, src: Material, cache: Dictionary) -> StandardMaterial3D:
	var key := src.get_instance_id() if src != null else 0
	if cache.has(key):
		return cache[key]
	var mat := StandardMaterial3D.new()
	var tag := "none"
	if src is BaseMaterial3D:
		var base := src as BaseMaterial3D
		mat.albedo_color = base.albedo_color
		mat.roughness = base.roughness
		mat.metallic = base.metallic
		mat.shading_mode = base.shading_mode
		if not base.uv1_triplanar and base.albedo_texture != null:
			mat.albedo_texture = base.albedo_texture
		tag = base.resource_name if base.resource_name != "" else ("tri" if base.uv1_triplanar else "std")
	elif src is ShaderMaterial:
		var shader_material := src as ShaderMaterial
		tag = "shader_" + (shader_material.shader.resource_path.get_file().get_basename() if shader_material.shader != null else "none")
		for param: String in ["base_color", "albedo", "albedo_color", "finish_color", "color"]:
			var value: Variant = shader_material.get_shader_parameter(param)
			if value is Color:
				mat.albedo_color = value
				break
	mat.resource_name = "%s__%s_%d" % [group, tag.validate_filename(), cache.size()]
	cache[key] = mat
	return mat


func _material_info(src: Material, conv: Material) -> Dictionary:
	var info := {"export_name": conv.resource_name, "class": src.get_class() if src != null else "null"}
	if src is BaseMaterial3D:
		var base := src as BaseMaterial3D
		info["name"] = base.resource_name
		info["albedo"] = _jsonable(base.albedo_color)
		info["roughness"] = base.roughness
		info["metallic"] = base.metallic
		info["shading_mode"] = base.shading_mode
		info["triplanar"] = base.uv1_triplanar
		info["world_triplanar"] = base.uv1_world_triplanar
		info["uv1_scale"] = _jsonable(base.uv1_scale)
		info["uv1_offset"] = _jsonable(base.uv1_offset)
		info["textures"] = {"albedo": _jsonable(base.albedo_texture),
			"normal": _jsonable(base.normal_texture) if base.normal_enabled else "",
			"normal_scale": base.normal_scale,
			"roughness": _jsonable(base.roughness_texture), "roughness_channel": base.roughness_texture_channel}
		info["emission"] = _jsonable(base.emission) if base.emission_enabled else null
		info["transparency"] = base.transparency
	elif src is ShaderMaterial:
		var shader_material := src as ShaderMaterial
		info["shader"] = shader_material.shader.resource_path if shader_material.shader != null else ""
		var params := {}
		if shader_material.shader != null:
			for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
				var uniform_name := String(uniform["name"])
				params[uniform_name] = _jsonable(shader_material.get_shader_parameter(uniform_name))
		info["params"] = params
	return info


func _mesh_info(mesh: Mesh) -> Dictionary:
	var info := {"class": mesh.get_class(), "surfaces": mesh.get_surface_count(), "aabb": _jsonable(mesh.get_aabb())}
	for prop: String in ["size", "radius", "top_radius", "bottom_radius", "height"]:
		if prop in mesh:
			info[prop] = _jsonable(mesh.get(prop))
	return info


func _camera_info() -> Dictionary:
	var c := get_viewport().get_camera_3d()
	var info := {"name": String(c.name), "xform": _xform(c.global_transform), "fov": c.fov, "keep_aspect": c.keep_aspect,
		"near": c.near, "far": c.far, "h_offset": c.h_offset, "v_offset": c.v_offset, "projection": c.projection,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]}
	var practical := c.attributes as CameraAttributesPractical
	if practical != null:
		info["dof"] = {"far_enabled": practical.dof_blur_far_enabled, "far_distance": practical.dof_blur_far_distance,
			"far_transition": practical.dof_blur_far_transition, "near_enabled": practical.dof_blur_near_enabled,
			"near_distance": practical.dof_blur_near_distance, "near_transition": practical.dof_blur_near_transition,
			"amount": practical.dof_blur_amount}
	return info


func _light_info() -> Array:
	var rows: Array = []
	for node: Node in get_tree().root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not light.is_visible_in_tree():
			continue
		var row := {"class": light.get_class(), "path": String(light.get_path()), "xform": _xform(light.global_transform),
			"color": _jsonable(light.light_color), "energy": light.light_energy, "indirect_energy": light.light_indirect_energy,
			"angular_distance": light.light_angular_distance, "negative": light.light_negative,
			"shadow": light.shadow_enabled, "bake_mode": light.light_bake_mode}
		if light is OmniLight3D:
			row["range"] = (light as OmniLight3D).omni_range
		elif light is SpotLight3D:
			row["range"] = (light as SpotLight3D).spot_range
			row["angle"] = (light as SpotLight3D).spot_angle
		rows.append(row)
	return rows


func _environment_info() -> Dictionary:
	var env: Environment = null
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null:
			env = (node as WorldEnvironment).environment
	if env == null and get_viewport().world_3d != null:
		env = get_viewport().world_3d.environment
	if env == null:
		return {}
	var glow_levels: Array = []
	for i in range(7):
		glow_levels.append(env.get_glow_level(i))
	return {"background_mode": env.background_mode, "background_energy": env.background_energy_multiplier,
		"ambient_source": env.ambient_light_source, "ambient_color": _jsonable(env.ambient_light_color),
		"ambient_energy": env.ambient_light_energy, "ambient_sky_contribution": env.ambient_light_sky_contribution,
		"reflected_source": env.reflected_light_source,
		"tonemap_mode": env.tonemap_mode, "tonemap_exposure": env.tonemap_exposure, "tonemap_white": env.tonemap_white,
		"adjustment_enabled": env.adjustment_enabled, "brightness": env.adjustment_brightness,
		"contrast": env.adjustment_contrast, "saturation": env.adjustment_saturation,
		"glow_enabled": env.glow_enabled, "glow_intensity": env.glow_intensity, "glow_strength": env.glow_strength,
		"glow_bloom": env.glow_bloom, "glow_blend_mode": env.glow_blend_mode, "glow_hdr_threshold": env.glow_hdr_threshold,
		"glow_hdr_scale": env.glow_hdr_scale, "glow_mix": env.glow_mix, "glow_levels": glow_levels,
		"ssao_enabled": env.ssao_enabled, "ssao_radius": env.ssao_radius, "ssao_intensity": env.ssao_intensity,
		"ssao_power": env.ssao_power, "ssao_light_affect": env.ssao_light_affect,
		"fog_enabled": env.fog_enabled, "fog_density": env.fog_density, "fog_light_color": _jsonable(env.fog_light_color),
		"fog_light_energy": env.fog_light_energy, "fog_sky_affect": env.fog_sky_affect}


## 壁の文字（扉の答えと問題の看板）。Label3D は glTF に入らないので、Blender で同じ書体の文字に作り直す
func _label_info() -> Array:
	var rows: Array = []
	for node: Node in world.get_node("WallContainer").find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if not label.is_visible_in_tree() or label.modulate.a < 0.01 or label.global_position.distance_to(cam.global_position) > EXPORT_RANGE_M:
			continue
		var font_info := {}
		if label.font != null:
			font_info = {"class": label.font.get_class(), "path": label.font.resource_path, "name": label.font.get_font_name(),
				"style": label.font.get_font_style_name()}
		rows.append({"path": String(world.get_path_to(label)), "text": label.text, "font": font_info,
			"font_size": label.font_size, "outline_size": label.outline_size, "pixel_size": label.pixel_size,
			"modulate": _jsonable(label.modulate), "outline_modulate": _jsonable(label.outline_modulate),
			"width": label.width, "autowrap": label.autowrap_mode, "h_align": label.horizontal_alignment,
			"v_align": label.vertical_alignment, "line_spacing": label.line_spacing, "offset": _jsonable(label.offset),
			"billboard": label.billboard, "shaded": label.shaded, "double_sided": label.double_sided,
			"render_priority": label.render_priority, "outline_render_priority": label.outline_render_priority,
			"uppercase": label.uppercase, "xform": _xform(label.global_transform), "aabb": _jsonable(label.get_aabb())})
	return rows


func _grab(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		failures.append("save %s failed (%d)" % [path, err])


## 変換は基底の列（x・y・z 軸）と原点。Godot の座標のまま（Y が上）
func _xform(t: Transform3D) -> Dictionary:
	return {"basis": [_jsonable(t.basis.x), _jsonable(t.basis.y), _jsonable(t.basis.z)], "origin": _jsonable(t.origin)}


func _jsonable(value: Variant) -> Variant:
	if value is Color:
		var c: Color = value
		return [c.r, c.g, c.b, c.a]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is AABB:
		var box: AABB = value
		return {"position": _jsonable(box.position), "size": _jsonable(box.size)}
	if value is Resource:
		return (value as Resource).resource_path
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)


func _check() -> void:
	report["trace"] = _trace
	report["shove_frame"] = _shove_frame
	var impact := {}
	for entry: Dictionary in _trace:
		if not impact.has("p2_out") and not (entry["alive"] as Array)[1]:
			impact["p2_out"] = entry["f"]
		if not impact.has("p1_through") and int(entry["wall_index"]) > 0:
			impact["p1_through"] = entry["f"]
	report["impact"] = impact
	if cfg.has("p2_hp"):
		# t5：P1 は扉を突き破り、P2 は扉に激突して脱落する
		if not gs.p1_alive:
			failures.append("P1 が脱落した")
		if gs.p2_alive:
			failures.append("P2 が脱落していない")
		if not impact.has("p1_through"):
			failures.append("P1 が壁を通過していない")
		return
	if not gs.p1_alive or not gs.p2_alive:
		failures.append("撮影中に脱落した（%s, %s）" % [gs.p1_alive, gs.p2_alive])
	if gs.current_wall_index != 0:
		failures.append("撮影中に壁を通過した")


func _cleanup() -> void:
	QuizWallScript.keep_after_pass_for_capture = false
