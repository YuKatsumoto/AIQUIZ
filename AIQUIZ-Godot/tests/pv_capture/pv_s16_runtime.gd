extends "res://tests/pv_capture/pv_take_base.gd"

## PV S16「うしろからチップソー」：並んで逃げる 2 人の後ろから 8 連のチップソーが迫り、わざと遅れた P2 が巻き込まれてバラバラになる
## （8 拍）。本物の GameWorld（ローカル 2P・10 問・PLAYING）を、本物のキーイベントで動かして撮る。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s16 quality=ultra sub=8
## テロップ「おくれると、チップソー」は After Effects（レーン 6）で重ねる。HUD は出さない。効果音はゲームのまま（cues.json）。
##
## チップソーはゲームのまま：いちばん前を走る人の 14 m 後ろ（game_tuning.gd の saw_follow_distance）を、最高 10 m/s で追う。
## 刃は 8 枚・3 m 間隔（saw_chase_state.gd）。走る速さは 7.6 m/s、壁（ベルト）は 2.9 m/s（ゲームの典型）。
##
## 流れ（PV フレーム。1 = S16 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   撮る前   2 人とも走り出している（PRE_ROLL フレーム）。P2 は P1 より P2_BEHIND m 後ろ
##   1-      2 人が並んで逃げる。刃の列がうしろから追ってくる
##   F_LAG   P2 がわざと立ち止まり、その場でランニングマン（走るふりのエモート、キー 8）を踊る。P1 はそのまま逃げる
##   〜      刃が P2 に追いつき、巻き込む（ゲームどおり上・前へ跳ね飛ばされ、1.15 秒後にバラバラになる）
## カメラ：刃の列の後ろ・上から、刃越しに 2 人を見る。刃の列（ゲームの値で動く）といっしょに等速で進み、少しずつ寄る。
## 引数（共通のほかに）:
##   cam=<後ろ>,<高さ>,<先>,<画角>[,<寄り>]   カメラを試す（刃の中心からの距離 m・床からの高さ m・注視点の先 m・縦の画角・最後に寄る m）

const S16_FRAMES := 225
const HANDLE_FRAMES := 4

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const P1_EMOTES: Array[int] = [2, 7, 13]
const P2_EMOTES: Array[int] = [17, 19, 15]      # キー 8 = ランニングマン（その場で走るふり）
const DAY_PHASE := 0.25
const WARMUP_FRAMES := 150
const FLOOR_Y := -1.2

## 場所（描画座標 = ベルトの上の位置）。いちばん手前の壁は 2 人の WALL_AHEAD m 先
const P1_X := 1.5                       # 後ろから見て左
const P2_X := -1.5                      # 後ろから見て右（刃の 1 枚の正面）
const START_Z := 30.0                   # 撮り始めの P1 の位置
const P2_BEHIND := 2.0
const WALL_AHEAD := 80.0
const PRE_ROLL := 30                    # 撮る前に走っておくフレーム
const F_LAG := 36                       # P2 が立ち止まって踊りだす

## 壁の問題（遠くに見えるだけ）。tests/pv_capture/pv_v3_runtime.gd と同じ
const QUIZZES := [
	["【計算】36 ÷ 4 ＝ ？", ["9", "8"]],
	["「たいよう」を漢字で書くと？", ["太陽", "太洋"]],
	["水が氷になる温度は？", ["0℃", "100℃"]],
]
const P2_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_CTRL, KEY_8, KEY_9, KEY_0]

## カメラ（刃の中心の z からの位置）
const CAM_BACK := 9.0                   # 頭：刃の中心から後ろ（8 枚の列を広めに）
const CAM_HEIGHT := 8.0                 # 床（-1.2）からの高さ
const CAM_AHEAD := 9.0                  # 注視点：刃の中心から先
const CAM_LOOK_Y := 0.0                 # 注視点の床からの高さ
const CAM_FOV := 55.0
const CAM_PUSH := 3.0                   # 巻き込みまでに寄る（後ろへ 3 m・下へ 1.2 m）
const CAM_PUSH_END := 106               # 寄り終わるフレーム
const CAM_STOP := 0.7                   # 巻き込んだら、この秒数でなめらかに止まる（刃の列だけが先へ進み、手前に破片が残る）
const CAM_X := -0.4                     # P2 の側へ少し

var helper: Node
var gs: QuizGameState
var world: Node
var player: PlayerController
var camera_controller: Node
var cam: Camera3D
var keys_table: Array = []
var wall_ahead := WALL_AHEAD
var cam_back := CAM_BACK
var cam_height := CAM_HEIGHT
var cam_ahead := CAM_AHEAD
var cam_fov := CAM_FOV
var cam_push := CAM_PUSH
var _trace: Array = []
var _caught_frame := -1
var _catch_t := -1.0
var _catch_sz := 0.0
var _catch_v := 0.0
var _scatter_frame := -1
var _last_emote := [0, 0]
var cam_look_y := 0.0


func _init() -> void:
	take_name = "s16"


func _default_frames() -> int:
	return S16_FRAMES + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg.begins_with("cam="):
		var v := arg.trim_prefix("cam=").split(",")
		cam_back = float(v[0])
		if v.size() > 1: cam_height = float(v[1])
		if v.size() > 2: cam_ahead = float(v[2])
		if v.size() > 3: cam_fov = float(v[3])
		if v.size() > 4: cam_push = float(v[4])
		if v.size() > 5: cam_look_y = float(v[5])


func _setup() -> void:
	cam_look_y = CAM_LOOK_Y if cam_look_y == 0.0 else cam_look_y
	_build_keys()
	await _build_world()
	_set_station()
	hide_overlays()
	report["plan"] = {"p1_x": P1_X, "p2_x": P2_X, "start_z": START_Z, "p2_behind": P2_BEHIND, "wall_ahead": wall_ahead,
		"pre_roll": PRE_ROLL, "lag": F_LAG, "saw_follow": gs.tuning.saw_follow_distance, "saw_max_speed": gs.tuning.saw_max_speed,
		"camera": {"back": cam_back, "height": cam_height, "ahead": cam_ahead, "fov": cam_fov, "push": cam_push, "look_y": cam_look_y}}
	await _pre_roll()


func _build_keys() -> void:
	keys_table = [
		[KEY_W, -PRE_ROLL, 100000, "P1 が走って逃げる"],
		[KEY_UP, -PRE_ROLL, F_LAG + PRE_ROLL, "P2 も走る（F_LAG で立ち止まる）"],
		[KEY_8, F_LAG, 4, "P2 のエモート（ランニングマン）。その場で走るふり"],
	]


func _keys_at(n: int) -> Dictionary:
	var want: Dictionary = {}
	for entry: Array in keys_table:
		if n >= entry[1] and n < entry[1] + entry[2]:
			want[entry[0]] = true
	if gs != null and not gs.p2_alive:
		for key: Variant in P2_KEYS:
			want.erase(key)
	return want


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
		weather.call("force_day_phase", DAY_PHASE)
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


## 撮る前に走っておく分だけ手前から始める
func _set_station() -> void:
	var run := PRE_ROLL * gs.tuning.player_speed / FPS
	var p1_z := START_Z - run
	var scroll := gs.tuning.wall_start_z - (START_Z + wall_ahead) - gs.tuning.wall_speed_override * PRE_ROLL / FPS
	gs.world_scroll_z = scroll
	gs.player_x = P1_X
	gs.player2_x = P2_X
	gs.player_z = scroll + p1_z
	gs.player2_z = scroll + p1_z - P2_BEHIND
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.camera_shake = 0.0
	gs.set("_active_wall_speed", gs.tuning.wall_speed_override)
	gs.saw.local_z = p1_z - gs.tuning.saw_follow_distance - SawChaseState.BLADE_RADIUS
	gs.saw.elapsed = 10.0                       # 追い始めの猶予（2 秒）と回り始め（4 秒）は済んだことに


## 2 人を走らせておく（撮らない）。刻みは撮影と同じ
func _pre_roll() -> void:
	world.set("_replay_mode", false)
	for i in range(PRE_ROLL * sub):
		var n := -PRE_ROLL + int(floor(float(i) / sub)) + 1
		hold_keys(_keys_at(n))
		world.set("_push_focus_lost", false)
		await get_tree().process_frame
		_apply_camera(1, 0.0)


func _before_update(n: int) -> void:
	hold_keys(_keys_at(n))
	world.set("_push_focus_lost", false)


func _update(n: int, t: float, _dt: float) -> void:
	if _caught_frame < 0 and gs.p2_saw_killed:
		_caught_frame = n
		_catch_t = t
		_catch_sz = gs.saw.local_z
		_catch_v = gs.saw.velocity
	if _scatter_frame < 0 and player.has_player_death_exploded(2):
		_scatter_frame = n
	_fix_emote_start()
	_apply_camera(n, t)
	_record(n)


## 踊りの最初のフレームは骨格がまだ初期姿勢（T ポーズ）なので、0 秒の位置を当てて写し直す（pv_v3_runtime.gd と同じ）
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


## 刃の列の後ろ・上から。刃の中心の z といっしょに進みながら寄り、P2 を巻き込んだら CAM_STOP 秒でなめらかに止まる
## （揺れはゲームの camera_shake を乱数なしで）
func _apply_camera(n: int, t: float) -> void:
	var u := smooth(t / (CAM_PUSH_END / FPS))
	var back := cam_back - cam_push * u
	var height := cam_height - cam_push * 0.4 * u
	var base_z: float = gs.saw.local_z
	if _catch_t >= 0.0:
		var a := (t - _catch_t) / CAM_STOP
		var travel := 0.5 if a >= 1.0 else a - (a * a * a - 0.5 * a * a * a * a)
		base_z = _catch_sz + _catch_v * CAM_STOP * travel
	var eye := Vector3(CAM_X, FLOOR_Y + height, base_z - back)
	var target := Vector3(CAM_X - 0.3, FLOOR_Y + cam_look_y, base_z + cam_ahead)
	var shake := gs.camera_shake
	if shake > 0.001:
		var k := 0.09 * shake
		eye += Vector3(sin(t * 57.0) * k, cos(t * 43.0) * k, 0.0)
		target += Vector3(sin(t * 61.0) * k * 0.6, cos(t * 47.0) * k * 0.6, 0.0)
	var pose := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, cam_fov)
	if cam != null:
		cam.h_offset = 0.0
		cam.fov = cam_fov
		cam.global_transform = pose
		cam.attributes = null


func _record(n: int) -> void:
	if (_step % sub) != 0:
		return
	if n % 4 == 1 or (_caught_frame >= 0 and n <= _caught_frame + 2):
		var entry := {"f": n, "p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_local_z, 0.01)],
			"p2": [snappedf(gs.player2_x, 0.01), snappedf(gs.player2_local_z, 0.01)],
			"saw_z": snappedf(gs.saw.local_z, 0.01), "wall_z": snappedf(gs.tuning.wall_start_z - gs.world_scroll_z, 0.01),
			"alive": [gs.p1_alive, gs.p2_alive], "emote": [gs.p1_emote, gs.p2_emote]}
		var active := get_viewport().get_camera_3d()
		if active != null:
			var o := active.global_position
			var f := -active.global_basis.z
			entry["cam"] = [snappedf(o.x, 0.01), snappedf(o.y, 0.01), snappedf(o.z, 0.01), snappedf(f.y, 0.001), snappedf(active.fov, 0.1), String(active.name)]
		var saw_node := world.get_node_or_null("SawChaseController") as Node3D
		if saw_node != null:
			entry["saw_node"] = [snappedf(saw_node.global_position.y, 0.01), snappedf(saw_node.global_position.z, 0.01)]
		if not gs.p2_alive:
			var body := player.get_death_presentation_position(false)
			entry["p2_body"] = [snappedf(body.x, 0.01), snappedf(body.y, 0.01), snappedf(body.z, 0.01)]
		_trace.append(entry)


func _check() -> void:
	report["cut_in_frame"] = 1                 # レーン 6 はここからカットの長さを使う（テイクの頭 = カットの頭）
	report["caught_frame"] = _caught_frame
	report["scatter_frame"] = _scatter_frame
	report["alive_at_end"] = [gs.p1_alive, gs.p2_alive]
	report["trace"] = _trace
	report["highlights"] = {"p2_stops": F_LAG, "p2_caught": _caught_frame, "p2_scatters": _scatter_frame}
	if not gs.p1_alive:
		failures.append("P1 が脱落した")
	if gs.p2_alive or not gs.p2_saw_killed:
		failures.append("P2 がチップソーに巻き込まれていない")
	if _caught_frame < F_LAG + 30 or _caught_frame > 150:
		failures.append("P2 の巻き込みが %d（%d〜150 のはず）" % [_caught_frame, F_LAG + 30])
	if _scatter_frame < 0 or _scatter_frame > S16_FRAMES - 12:
		failures.append("P2 がカットの中でバラバラにならない（%d）" % _scatter_frame)
	if gs.current_wall_index != 0:
		failures.append("撮影中に壁を通過した")

