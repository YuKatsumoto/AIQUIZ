extends "res://tests/pv_capture/pv_take_base.gd"

## PV S06「AIが作った問題が、空から落ちてくる」と S07「5教科×6学年の問題」を、本物の GameWorld で 1 回の通しとして撮る（1 人）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s06_s07 quality=ultra sub=8
## テロップ・教科名・シャッターの光は After Effects で重ねる（docs/pv/previz/ae/build_s04_s07.jsx）。
##
## 流れ（PV フレーム。1 = S06 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   S06   1-225  問題の準備中（PRELOADING）。ゲームのとおり、問題が 1 問届くたびにその壁が空から落ちる（奥の壁から手前へ。
##                ONLINE の出題なので 1 枚ずつ）。届く時刻だけをこちらで決め、3〜10 問目の壁が 1 拍目〜8 拍目の頭に着地する
##                （1・2 問目はカットの前に着地済み）。HUD の「AIが問題をつくっています n/10」もゲームのまま進む（右上へ寄せる）。
##                カメラはコースの奥の上空から、壁の文字の側（スタート側）を見たまま 1 拍に壁 1 枚ぶん（30 m）ずつ下がり、
##                いつも着地する壁を画面の中央・30 m 先に見る。高さを下げていき、最後は選手（P1）の背中の高さで止まる。
##   S07 226-450  いちばん手前の壁を正面から（選手は映さない）。1.5 拍ごとに問題を替える（算数・国語・理科・社会・英語。英語だけ 2 拍）。
##                問題は offline_bank.json（AI が作った問題）から教科ごとに 1 問ずつ固定。HUD は出さない。
## このPVだけ：全部の壁が着地してもカウントダウンの壁は落とさない（S09 で別に見せる）。

const S06_FRAMES := 225
const S07_FRAMES := 225
const HANDLE_FRAMES := 4                    # 編集のつなぎ用に少し長く撮る

const FLOOR_Y := -1.2
const P1_START := Vector3(0.0, 0.0, -8.0)   # 1 人のときのスタート位置（game_state.start_game）
const DROP_SECONDS := 0.28                  # GameWorld.PREVIEW_WALL_DROP_DURATION
const PREWARM_UPDATES := 4                  # GameWorld.ONLINE_PREVIEW_WALL_PREWARM_FRAMES（ゲームの更新の回数）
const PRE_ROLL_BEATS := 2.0                 # 撮る前に回しておく長さ（1・2 問目の着地を含む）

## S06 の壁：届く順（1 問目が最奥・ボスの 4 択）。算数 4 年（S04 の設定の終わりと同じ）。[問題, 選択肢（先頭が正解）]
const S06_QUIZZES := [
	["【角】直角は何度ですか？", ["90度", "45度", "180度", "360度"]],
	["25 × 12 の答えは？", ["300", "290"]],
	["【わり算の筆算】48 ÷ 4 =", ["12", "11"]],
	["36 × 45 の答えは？", ["1620", "1600"]],
	["直線がつくる角は何度？", ["180度", "90度"]],
	["【小数】0.3 ＋ 0.5 =", ["0.8", "0.08"]],
	["60 ÷ 20 の答え（商）はどれですか？", ["3", "30"]],
	["【わり算の筆算】64 ÷ 2 =", ["32", "22"]],
	["48 × 23 の答えは？", ["1104", "1084"]],
	["1辺5cmの正方形の面積は？", ["25㎠", "20㎠"]],
]
const S06_SUBJECT := "算数"
const S06_GRADE := 4
## 3〜10 問目が着地する拍（S06 の頭からの拍）。1・2 問目はカットの前
const S06_LAND_BEATS := [-1.0, -0.5, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]

## S07 の 5 枚：[教科, 学年, 問題, 選択肢（先頭が正解）, 出す拍（S07 の頭から）]
const S07_QUIZZES := [
	["算数", 4, "96 ÷ 4 の答えは？", ["24", "26"], 0.0],
	["国語", 6, "「増加」の対義語として正しいものは？", ["減少", "拡大"], 1.5],
	["理科", 3, "【昆虫】昆虫の足は全部で何本？", ["6本", "8本"], 3.0],
	["社会", 6, "江戸幕府を　開いた　人物は　だれですか？", ["徳川家康", "源頼朝"], 4.5],
	["英語", 3, "【基本】「頭」を表す英語は？", ["head", "hand"], 6.0],
]

## カメラ（S06）。届く順 N の壁の z は 22 + (9 − N) × 30。3 問目（z = 232）が 0 拍目に着地し、1 拍ごとに 30 m 手前へ
const S06_WALL_Z0 := 232.0
const S06_LEAD := 24.0                      # 着地する壁までの距離
const S06_CAM_Y0 := 17.0
const S06_CAM_END := Vector3(0.0, 0.55, -13.2)
const S06_SPEED := 30.0                     # m / 拍（壁 1 枚ぶん）
## S07 のカメラ：いちばん手前の壁（z = 22）の正面
const S07_EYE := Vector3(0.0, 1.35, 8.2)   # 壁の正面。P1（z = −8）はカメラの後ろ
const S07_TARGET := Vector3(0.0, 2.25, 22.0) # 壁を画面の下寄りに（上の空けたところにテロップ）
const S07_FOV := 46.0
const P1_CLEAR_Y := 1.9                     # カメラが P1 の上を越えるときの高さ（頭のてっぺんは約 0.9）
const HUD_SCALE := 0.7                      # 準備中のパネル（HUD の座標は 1280×720）

var helper: Node
var gs: QuizGameState
var world: Node
var player: PlayerController
var camera_controller: Node
var cam: Camera3D
var hud: CanvasLayer
var _bank: Dictionary = {}
var _s06_items: Array[QuizItem] = []
var _s07_items: Array[QuizItem] = []
var _deliver_steps: Array[int] = []        # 届けるゲームの更新（撮り始めの更新 = 1。0 以下は撮る前）
var _arrived := 0
var _landed_frames: Array[int] = []
var _s07_shown := -1
var _saved_provider_mode := ""
var _pre_updates := 0                      # 撮り始める前のゲームの更新の数
var _trace: Array = []


func _init() -> void:
	take_name = "s06_s07"


func _default_frames() -> int:
	return S06_FRAMES + S07_FRAMES + HANDLE_FRAMES


func _setup() -> void:
	_bank = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))
	_s06_items = []
	for i in range(S06_QUIZZES.size()):
		var e: Array = S06_QUIZZES[i]
		_s06_items.append(QuizItem.create(e[0], PackedStringArray(e[1]), 0, "", "OFFLINE"))
	for e: Array in S07_QUIZZES:
		_s07_items.append(_from_bank(e[0], e[1], e[2], e[3]))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(1)
	gs.quiz_list.clear()
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.subject = S06_SUBJECT
	gs.grade = S06_GRADE
	gs.difficulty = "普通"
	gs.target_count = 10
	gs.llm_mode = "ONLINE"                      # HUD の見出しを「AIが問題をつくっています」に
	gs.player_x = P1_START.x
	gs.player_z = P1_START.z
	gs.world_scroll_z = 0.0
	gs.p1_hat = 11
	gs.set_player_skin(1, PlayerSkin.from_code("035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"))
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_PRELOADING
	gs.refresh_status_text()
	QuizManager.game_state = gs
	_saved_provider_mode = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "ONLINE"     # 壁を 1 枚ずつ落とす（GameWorld はグローバルの出題元の設定を見る）
	var scene := load("res://scenes/game_world.tscn") as PackedScene
	world = scene.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)             # ゲームの状態は進めない（問題の補充もしない）。壁の演出と HUD は動く
	world.set("_barrier_spawned_for_session", true)
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	await _frames(30)
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", 0.25)
	camera_controller = world.get("camera_controller")
	cam = camera_controller.get_node_or_null("Camera3D") as Camera3D
	await _frames(150)
	hud = world.get_node_or_null("GameplayHUD") as CanvasLayer
	if hud == null:
		for node: Node in world.find_children("*", "CanvasLayer", true, false):
			if node.name == "GameplayHUD":
				hud = node as CanvasLayer
	var keep: Array[CanvasLayer] = []
	if hud != null:
		keep.append(hud)
	hide_overlays(keep)
	_plan_arrivals()
	# 撮る前：1〜3 問目を届ける（1・2 問目はカットの前に着地、3 問目は撮り始めのフレームに着地）
	var pre := int(round(PRE_ROLL_BEATS * BEAT * FPS)) * sub
	for step in range(1 - pre, 1):
		while _arrived < _deliver_steps.size() and _deliver_steps[_arrived] <= step:
			_deliver()
		await get_tree().process_frame
		_pre_updates += 1
		_decay_shake(get_process_delta_time())
		_apply_camera(1, float(step) / (FPS * sub))
	report["plan"] = {"deliver_steps": _deliver_steps, "land_beats": S06_LAND_BEATS}


## 届ける更新：着地させたいフレームの最初の更新から、落とし始めるまでの PREWARM 回と落下（0.28 秒）の更新の数だけ前。
## この更新の終わりに届けると、次の更新で壁に問題が入り、その PREWARM 回あとの更新から落ち始める。
func _plan_arrivals() -> void:
	for beat: float in S06_LAND_BEATS:
		var land_step := (bf(beat) - 1) * sub + 1
		_deliver_steps.append(land_step - PREWARM_UPDATES - int(ceil(DROP_SECONDS * FPS * sub - 0.0001)))


## ゲームの状態を進めていないので、揺れはゲームと同じ速さ（毎秒 2.8）でこちらが減らす
func _decay_shake(dt: float) -> void:
	gs.camera_shake = maxf(0.0, gs.camera_shake - dt * 2.8)


func _deliver() -> void:
	if _arrived >= _s06_items.size():
		return
	gs.quiz_list.append(_s06_items[_arrived])
	gs.refresh_status_text()
	_arrived += 1


func _landed_count() -> int:
	var count := 0
	for anim: Dictionary in world.get("_pw_anims"):
		if int(anim.get("phase", 0)) >= 2:
			count += 1
	return count


func _from_bank(subject: String, grade: int, q: String, choices: Array) -> QuizItem:
	var found: Dictionary = {}
	for item: Dictionary in _bank.get(subject, {}).get(str(grade), []):
		if str(item.get("q", "")) == q:
			found = item
			break
	if found.is_empty():
		failures.append("bank: %s %d年「%s」が見つからない" % [subject, grade, q])
	else:
		var c: Array = found.get("c", [])
		var correct := str(c[int(found.get("a", 0))])
		if correct != str(choices[0]) or not c.has(choices[1]):
			failures.append("bank: %s の選択肢が問題集と合わない（%s）" % [q, str(c)])
	return QuizItem.create(q, PackedStringArray(choices), 0, "", "OFFLINE")


# ------------------------------------------------------------------ 毎フレーム

func _update(n: int, t: float, dt: float) -> void:
	_decay_shake(dt)
	# 届ける：この更新で届く予定の問題
	while _arrived < _deliver_steps.size() and _deliver_steps[_arrived] <= _step:
		_deliver()
	var landed := _landed_count()
	while _landed_frames.size() < landed:
		_landed_frames.append(n)
	if n <= S06_FRAMES:
		_place_hud()
	else:
		if _s07_shown < 0:
			_clear_landing_effects()
		_show_s07(n)
		if hud != null:
			hud.visible = false
	_apply_camera(n, t)
	if (_step % sub) == 0 and (n % 4 == 1 or n == S06_FRAMES or n == S06_FRAMES + 1):
		_trace.append({"f": n, "arrived": _arrived, "landed": landed, "shake": snappedf(gs.camera_shake, 0.01),
			"cam": [snappedf(cam.global_position.x, 0.01), snappedf(cam.global_position.y, 0.01), snappedf(cam.global_position.z, 0.01)]})


## 準備中のパネルは右上へ寄せて小さく（画面の中央に壁が着地する）。HUD の座標は 1280×720
func _place_hud() -> void:
	if hud == null:
		return
	var panel := hud.get_node_or_null("PreloadPanel") as Control
	if panel == null:
		return
	var ui := panel.get_viewport_rect().size
	panel.pivot_offset = Vector2.ZERO
	panel.scale = Vector2(HUD_SCALE, HUD_SCALE)
	panel.position = Vector2(ui.x - 24.0 - panel.size.x * HUD_SCALE, 22.0)


## S06 の着地の火花が S07 の画面に残らないように止める
func _clear_landing_effects() -> void:
	for effect: Dictionary in world.get("_merge_effect_pool"):
		for key: String in ["sparks", "flash"]:
			var particles := effect.get(key) as CPUParticles3D
			if particles != null:
				particles.emitting = false
				particles.visible = false


## S07：いちばん手前の壁に、教科ごとの問題を 1.5 拍ごとに出す
func _show_s07(n: int) -> void:
	var local := n - S06_FRAMES
	var index := 0
	for i in range(S07_QUIZZES.size()):
		if local >= bf(float(S07_QUIZZES[i][4])):
			index = i
	var wall := _front_wall()
	if wall == null:
		return
	if index != _s07_shown:
		_s07_shown = index
		var item := _s07_items[index]
		gs.subject = str(S07_QUIZZES[index][0])
		gs.grade = int(S07_QUIZZES[index][1])
		wall.call("set_quiz", item, 2)
		wall.call("set_is_boss", false)
		if index > 0:
			AudioManager.play_sfx(&"ui_click")       # 切り替えの音（編集でシャッターの音に置きかえる）
	wall.call("set_gameplay_question", FractionFormatter.format_question(_s07_items[index].q), true)


func _front_wall() -> Node3D:
	var best: Node3D = null
	for w: Variant in world.get("_pw_walls"):
		if not is_instance_valid(w):
			continue
		var node := w as Node3D
		if best == null or node.position.z < best.position.z:
			best = node
	return best


func _apply_camera(n: int, t: float) -> void:
	var eye: Vector3
	var target: Vector3
	var fov := 50.0
	if n <= S06_FRAMES:
		# 着地する壁の 30 m 手前を、1 拍に 30 m の等速で下がる。最後は等減速で、S06 の終わりに P1 の背中で止まる
		var beat := t / BEAT
		var z0 := S06_WALL_Z0 - S06_LEAD
		var end_beat := float(S06_FRAMES) / (BEAT * FPS)               # 8 拍
		# 減速を始める拍 bs：z0 − v·bs − v·(end − bs)/2 = 終わりの z
		var bs := 2.0 * (z0 - S06_CAM_END.z) / S06_SPEED - end_beat
		var z: float
		if beat <= bs:
			z = z0 - S06_SPEED * beat
		else:
			var span := end_beat - bs
			var u := clampf(beat - bs, 0.0, span)
			z = z0 - S06_SPEED * bs - S06_SPEED * (u - 0.5 * u * u / span)
		var down := smooth(beat / end_beat)
		var y := lerpf(S06_CAM_Y0, S06_CAM_END.y, 1.0 - pow(1.0 - down, 1.5))
		# P1 の頭の上を越えてから、背中の高さへ下りる
		var over := smooth((z - (P1_START.z - 4.6)) / 4.0)
		y = maxf(y, lerpf(S06_CAM_END.y, P1_CLEAR_Y, over))
		eye = Vector3(0.0, y, z)
		# 見る点：いま着地する壁の中ほど。最後の壁のあとはコースの先へ
		var last := float(S06_LAND_BEATS[-1])
		var wall_z := S06_WALL_Z0 - S06_SPEED * clampf(beat, 0.0, last)
		var after := smooth((beat - last) / (end_beat - last))
		target = Vector3(0.0, lerpf(1.7, 1.2, down), lerpf(wall_z, z + 46.0, after))
		fov = lerpf(54.0, 48.0, down)
	else:
		eye = S07_EYE
		target = S07_TARGET
		fov = S07_FOV
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
		cam.attributes = null


func _check() -> void:
	report["landed_frames"] = _landed_frames
	report["pre_updates"] = _pre_updates
	report["trace"] = _trace
	var want: Array[int] = []
	for beat: float in S06_LAND_BEATS:
		if beat >= 0.0:
			want.append(bf(beat))
	report["land_frames_planned"] = want
	if _landed_frames.size() < 10:
		failures.append("S06: only %d walls landed" % _landed_frames.size())
	else:
		for i in range(want.size()):
			var got: int = _landed_frames[i + 2]
			if absi(got - want[i]) > 2:
				failures.append("S06: wall %d landed at %d, planned %d" % [i + 3, got, want[i]])
	if _s07_shown != S07_QUIZZES.size() - 1:
		failures.append("S07: showed up to quiz %d" % _s07_shown)


func _cleanup() -> void:
	QuizManager.provider.llm_mode = _saved_provider_mode
