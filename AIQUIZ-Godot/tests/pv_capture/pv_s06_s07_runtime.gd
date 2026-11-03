extends "res://tests/pv_capture/pv_take_base.gd"

## PV S06「AIが問題を作っている、実際の準備画面」と S07「5教科×6学年の問題」を、本物の GameWorld で 1 回の通しとして撮る
## （ローカル 2 人。S04〜S07 は 2 人プレイを前提に撮る：10/20 の決定。players=1 で 1 人の版も撮れる）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s06_s07 quality=ultra sub=8
## テロップ・教科名・シャッターの光は After Effects で重ねる（レーン 6）。手順と値は docs/pv/takes/s06_s07.md。
##
## 流れ（PV フレーム。1 = S06 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム。絵コンテ v1.2 で S06・S07 とも 12 拍）:
##   S06   1-338  実際の問題の準備画面（PRELOADING）。カメラ（準備中の俯瞰）と HUD の位置・大きさはゲームのまま触らない。
##                2 人のときはゲームのとおり、コースの後ろにチップソーの列が出る。
##                ゲームのとおり、問題が 1 問届くたびにその壁が空から落ちる（奥の壁から手前へ。ONLINE の出題なので 1 枚ずつ）。
##                届く時刻は、本物のオンライン生成を測った時刻そのまま（S06_ARRIVAL_MS。最初の約 3 秒は何も届かず、
##                そのあと 10 問が約 1.7 秒の間に不規則に届く）。カットの頭は start_game の S06_CUT_OFFSET_MS あと
##                （本物は暗転と画面の読み込みの間にも生成が進む）。壁が落ちる間隔（0.16 秒以上あける）はゲームが決める。
##                10 問目が届くと、ゲームと同じく WAITING_START に移り、HUD が「問題ができました！」になる。
##   S07 339-675  いちばん手前の壁を正面から（選手は映さない）。2 拍ごとに問題を替える（算数 4 年・国語 6 年・理科 3 年・
##                社会 6 年・英語 3 年・算数 6 年）。問題は offline_bank.json（AI が作った問題）から 1 問ずつ固定。HUD は出さない。
##                後半の 3 問は大人でも一瞬考える 2 択（その上に AE で「大人も、つい答えたくなる」）。
## このPVだけ：全部の壁が着地してもカウントダウンの壁は落とさない（S09 で別に見せる）。

const S06_BEATS := 12.0
const S07_BEATS := 12.0
const HANDLE_FRAMES := 4                    # 編集のつなぎ用に少し長く撮る

## スタート位置（QuizGameState.start_game）。2 人は x = ±1.5・z = 0、1 人は x = 0・z = −8
const SOLO_START := Vector3(0.0, 0.0, -8.0)
const P1_START := Vector3(1.5, 0.0, 0.0)
const P2_START := Vector3(-1.5, 0.0, 0.0)
## 見た目は S01〜S03（pv_v3_runtime.gd）と同じ：P1 プロペラ帽子、P2 キツネ帽子
const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const DROP_SECONDS := 0.28                  # GameWorld.PREVIEW_WALL_DROP_DURATION
const PREWARM_UPDATES := 4                  # GameWorld.ONLINE_PREVIEW_WALL_PREWARM_FRAMES（ゲームの更新の回数）

## S06 の壁：届く順（1 問目が最奥・ボスの 4 択）。算数 4 年（S04 の設定の終わりと同じ）。[問題, 扉の並び, 正解の番号]
const S06_SUBJECT := "算数"
const S06_GRADE := 4
const S06_QUIZZES := [
	["【角】直角は何度ですか？", ["90度", "45度", "180度", "360度"], 0],
	["25 × 12 の答えは？", ["290", "300"], 1],
	["【わり算の筆算】48 ÷ 4 =", ["12", "11"], 0],
	["36 × 45 の答えは？", ["1600", "1620"], 1],
	["直線がつくる角は何度？", ["180度", "90度"], 0],
	["【小数】0.3 ＋ 0.5 =", ["0.08", "0.8"], 1],
	["60 ÷ 20 の答え（商）はどれですか？", ["3", "30"], 0],
	["【わり算の筆算】64 ÷ 2 =", ["22", "32"], 1],
	["48 × 23 の答えは？", ["1104", "1084"], 0],
	["1辺5cmの正方形の面積は？", ["20㎠", "25㎠"], 1],
]
## 1〜10 問目が届いた時刻（ミリ秒）。本物のオンライン生成を measure=online で測ったもの（2026-10-20 19:30、2 人・算数 4 年・
## 普通・10 問、ラウンドの計画は新作 10 問・バンク 0 問、6 並列のストリーミング）。QuizGameState.start_game() からの実時間
const S06_ARRIVAL_MS := [3072, 3293, 3394, 3528, 3764, 3858, 3999, 4234, 4281, 4737]
## カットの頭 = start_game のこのミリ秒あと。最初の問題は 1.57 秒目、10 問目（「問題ができました！」）は 3.24 秒目に届く
const S06_CUT_OFFSET_MS := 1500

## S07 の 6 問（各 2 拍）：[教科, 学年, 問題, 扉の並び, 正解の番号]。後半の 3 問は大人でも一瞬考える 2 択
const S07_SLOT_BEATS := 2.0
const S07_QUIZZES := [
	["算数", 4, "96 ÷ 4 の答えは？", ["24", "26"], 0],
	["国語", 6, "「増加」の対義語として正しいものは？", ["拡大", "減少"], 1],
	["理科", 3, "【昆虫】昆虫の足は全部で何本？", ["6本", "8本"], 0],
	["社会", 6, "ブラジルで主に話されている言語は何ですか？", ["スペイン語", "ポルトガル語"], 1],
	["英語", 3, "「木曜日」の正しいつづりは、どれですか？", ["Thursday", "Thirsday"], 0],
	["算数", 6, "正三角形の対称の軸は何本ありますか？", ["2本", "3本"], 1],
]

## S07 のカメラ：いちばん手前の壁（z = 22）の正面（10/19 の版と同じ）
const S07_EYE := Vector3(0.0, 1.35, 8.2)   # 壁の正面。P1（z = −8）はカメラの後ろ
const S07_TARGET := Vector3(0.0, 2.25, 22.0) # 壁を画面の下寄りに（上の空けたところにテロップ）
const S07_FOV := 46.0

var players := 2                           # players=1 で 1 人の版
var measure := false                       # measure=online：本物のオンライン生成で 1 ラウンドぶん届く時刻を測るだけ（撮らない）
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
var _s06_end := 0                          # S06 の最後の PV フレーム
var _s07_end := 0                          # S07 の最後の PV フレーム（この後ろは編集のつなぎ）
var _s07_starts: Array[int] = []           # S07 の各問を出す PV フレーム
var _deliver_steps: Array[int] = []        # 届けるゲームの更新（撮り始めの更新 = 1。0 以下は撮る前）
var _arrived := 0
var _arrive_frames: Array[int] = []        # HUD の数字が増える PV フレーム
var _landed_frames: Array[int] = []
var _landed_subs: Array[int] = []         # 着地したのがフレームの何回目の更新か（撮るのは後ろの sub/2 回）
var _planned_arrive_frames: Array[int] = []
var _ready_frame := -1                     # HUD が「問題ができました！」になる PV フレーム
var _s07_shown := -1
var _s07_frames: Array[int] = []           # 実際に問題を替えた PV フレーム
var _saved_provider_mode := ""
var _pre_updates := 0                      # 撮り始める前のゲームの更新の数
var _frame_pose := Transform3D.IDENTITY    # S06：この PV フレームのゲームのカメラの姿勢
var _trace: Array = []


func _init() -> void:
	take_name = "s06_s07"
	_s06_end = bf(S06_BEATS) - 1
	_s07_end = bf(S06_BEATS + S07_BEATS) - 1
	for i in range(S07_QUIZZES.size()):
		_s07_starts.append(bf(S06_BEATS + S07_SLOT_BEATS * i))


func _default_frames() -> int:
	return 1 if measure else _s07_end + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg.begins_with("players="):
		players = clampi(int(arg.trim_prefix("players=")), 1, 2)
	elif arg == "measure=online":
		measure = true


func _setup() -> void:
	if measure:
		await _measure_online()
		return
	_bank = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))
	for e: Array in S06_QUIZZES:
		_s06_items.append(_from_bank(S06_SUBJECT, S06_GRADE, e[0], e[1], e[2]))
	for e: Array in S07_QUIZZES:
		_s07_items.append(_from_bank(e[0], e[1], e[2], e[3], e[4]))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(players)
	gs.quiz_list.clear()
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.subject = S06_SUBJECT
	gs.grade = S06_GRADE
	gs.difficulty = "普通"
	gs.target_count = 10
	gs.llm_mode = "ONLINE"                      # HUD の見出しを「AIが問題をつくっています」に
	var p1_start := P1_START if players == 2 else SOLO_START
	gs.player_x = p1_start.x
	gs.player_z = p1_start.z
	gs.player2_x = P2_START.x
	gs.player2_z = P2_START.z
	gs.world_scroll_z = 0.0
	gs.saw.reset()                              # start_game と同じ（チップソーはコースの後ろ、2 人のときだけ出る）
	gs.p1_hat = P1_HAT
	gs.p2_hat = P2_HAT
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
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
	world.set("_replay_mode", true)             # ゲームの状態は進めない（問題の補充もしない）。壁の演出・カメラ・HUD は動く
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
	camera_controller.call("clear_director_pose")
	await _frames(150)
	hud = world.get_node_or_null("GameplayHUD") as CanvasLayer
	if hud == null:
		for node: Node in world.find_children("*", "CanvasLayer", true, false):
			if node.name == "GameplayHUD":
				hud = node as CanvasLayer
	if hud == null:
		failures.append("GameplayHUD が見つからない")
	var keep: Array[CanvasLayer] = []
	if hud != null:
		keep.append(hud)
	var hidden: Array[String] = []
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if node != hud and (node as CanvasLayer).visible:
			hidden.append(str(node.get_path()))
	report["overlays_hidden"] = hidden
	hide_overlays(keep)
	_plan_arrivals()
	# 撮る前に届く予定の問題があれば、ここで届けて落としておく
	var first := _deliver_steps.min() as int
	for step in range(mini(first, 1), 1):
		while _arrived < _deliver_steps.size() and _deliver_steps[_arrived] <= step:
			_deliver(1)
		await get_tree().process_frame
		_pre_updates += 1
		_decay_shake(get_process_delta_time())
	report["plan"] = {"deliver_steps": _deliver_steps, "arrival_ms": S06_ARRIVAL_MS, "cut_offset_ms": S06_CUT_OFFSET_MS,
		"arrive_frames": _planned_arrive_frames}
	report["players"] = players
	report["saw_visible"] = gs.is_saw_visible()


## 届ける更新：測った時刻に届いた問題は、その時刻を含む PV フレーム F（F/60 秒の絵）から HUD の数字に出る。
## 届けるのは F の 1 つ前のフレームの最後の更新（HUD の数字と見出しがフレームの頭から切り替わり、sub 回の更新を
## 重ねても二重写しにならない）。この更新の終わりに届けると、次の更新で壁に問題が入り、その PREWARM 回あとの更新から
## 落ち始める（前の壁から 0.16 秒たっていなければ待つ）。0 以下の更新は撮る前に届ける。
func _plan_arrivals() -> void:
	for ms: int in S06_ARRIVAL_MS:
		var t := float(ms - S06_CUT_OFFSET_MS) / 1000.0
		var frame := int(ceil(t * FPS - 0.0001))
		_planned_arrive_frames.append(maxi(frame, 1))
		_deliver_steps.append((frame - 1) * sub)


## ゲームの状態を進めていないので、揺れはゲームと同じ速さ（毎秒 2.8、QuizGameState.update）でこちらが減らす
func _decay_shake(dt: float) -> void:
	gs.camera_shake = maxf(0.0, gs.camera_shake - dt * 2.8)


## 問題が 1 問届く。HUD とゲームの壁は次の更新でそれを見る。全部そろったら、ゲームと同じく WAITING_START へ
## （QuizGameState._update_preloading：そろって min_preload_sec を過ぎていれば同じ更新で移る）。
func _deliver(next_frame: int) -> void:
	if _arrived >= _s06_items.size():
		return
	gs.quiz_list.append(_s06_items[_arrived])
	gs.refresh_status_text()
	_arrived += 1
	_arrive_frames.append(next_frame)
	if _arrived >= gs.target_count and gs.game_state == Constants.STATE_PRELOADING:
		gs.game_state = Constants.STATE_WAITING_START
		gs.refresh_status_text()
		gs.state_changed.emit(gs.game_state)
		_ready_frame = next_frame


func _landed_count() -> int:
	var count := 0
	for anim: Dictionary in world.get("_pw_anims"):
		if int(anim.get("phase", 0)) >= 2:
			count += 1
	return count


## 問題集（offline_bank.json）の問題と一致するか確かめて QuizItem にする。扉の並びは問題集の選択肢から選んだもの
func _from_bank(subject: String, grade: int, q: String, choices: Array, answer: int) -> QuizItem:
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
		var ok := correct == str(choices[answer])
		for choice: Variant in choices:
			ok = ok and c.has(str(choice))
		if not ok:
			failures.append("bank: %s の選択肢が問題集と合わない（%s）" % [q, str(c)])
	return QuizItem.create(q, PackedStringArray(choices), answer, "", "OFFLINE")


# ------------------------------------------------------------------ 毎フレーム

func _update(n: int, t: float, dt: float) -> void:
	if measure:
		return
	_decay_shake(dt)
	# 届ける：この更新で届く予定の問題
	while _arrived < _deliver_steps.size() and _deliver_steps[_arrived] <= _step:
		_deliver(frame_of(_step + 1))
	var landed := _landed_count()
	while _landed_frames.size() < landed:
		_landed_frames.append(n)
		_landed_subs.append(((_step - 1) % sub) + 1)
	if n <= _s06_end:
		_hold_game_camera()
	else:
		if _s07_shown < 0:
			_clear_landing_effects()
		_show_s07(n)
		if hud != null:
			hud.visible = false
		_apply_s07_camera()
	if (_step % sub) == 0 and (n % 4 == 1 or n == _s06_end or n == _s06_end + 1):
		_trace.append({"f": n, "arrived": _arrived, "landed": landed, "state": gs.game_state,
			"shake": snappedf(gs.camera_shake, 0.01),
			"cam": [snappedf(cam.global_position.x, 0.01), snappedf(cam.global_position.y, 0.01), snappedf(cam.global_position.z, 0.01)]})


## S06 はゲームのカメラのまま。ただし着地の揺れはゲームが更新ごとに乱数の位置へ飛ばすので、sub 回に分けた更新を
## そのまま重ねると二重写しのボケになる。ゲームのカメラがその PV フレームの撮る最初の更新（土台が後ろの sub/2 回を撮る）で
## 出した姿勢を、フレームの終わりまで保つ（60 fps のゲームと同じく、1 フレームに 1 回だけ揺れる）。
func _hold_game_camera() -> void:
	if cam == null:
		return
	var s_in := ((_step - 1) % sub) + 1
	var first_shot := sub - maxi(1, sub / 2) + 1
	if s_in == first_shot:
		_frame_pose = cam.global_transform
	elif s_in > first_shot:
		cam.global_transform = _frame_pose


## S06 の着地の火花が S07 の画面に残らないように止める
func _clear_landing_effects() -> void:
	for effect: Dictionary in world.get("_merge_effect_pool"):
		for key: String in ["sparks", "flash"]:
			var particles := effect.get(key) as CPUParticles3D
			if particles != null:
				particles.emitting = false
				particles.visible = false


## S07：いちばん手前の壁に、教科ごとの問題を 2 拍ごとに出す
func _show_s07(n: int) -> void:
	var index := 0
	for i in range(_s07_starts.size()):
		if n >= _s07_starts[i]:
			index = i
	var wall := _front_wall()
	if wall == null:
		return
	if index != _s07_shown:
		_s07_shown = index
		_s07_frames.append(n)
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


## S07 だけ PV のカメラ（壁の正面に固定）。S06 はゲームのカメラのまま触らない
func _apply_s07_camera() -> void:
	var pose := Transform3D(Basis.looking_at(S07_TARGET - S07_EYE, Vector3.UP), S07_EYE)
	camera_controller.call("set_director_pose", pose, S07_FOV)
	if cam != null:
		cam.h_offset = 0.0
		cam.fov = S07_FOV
		cam.global_transform = pose
		cam.attributes = null


func _check() -> void:
	if measure:
		return
	var s07: Array = []
	for i in range(S07_QUIZZES.size()):
		var e: Array = S07_QUIZZES[i]
		s07.append({"subject": e[0], "grade": e[1], "q": e[2], "choices": e[3], "answer": e[4],
			"frame": _s07_frames[i] if i < _s07_frames.size() else -1})
	report["cuts"] = {"S06": [1, _s06_end], "S07": [_s06_end + 1, _s07_end], "handle": [_s07_end + 1, frame_count]}
	report["s06"] = {"arrive_frames": _arrive_frames, "arrive_frames_planned": _planned_arrive_frames,
		"land_frames": _landed_frames, "land_subs": _landed_subs, "ready_frame": _ready_frame,
		"arrival_ms": S06_ARRIVAL_MS, "cut_offset_ms": S06_CUT_OFFSET_MS}
	report["s07"] = {"switch_frames": _s07_frames, "switch_frames_planned": _s07_starts, "quizzes": s07}
	# レーン 6（編集）が読む名前でも置く（docs/pv/takes/s06_s07.md）
	report["s07_start_frame"] = _s06_end + 1
	report["s07_switch_frames"] = _s07_frames
	report["pre_updates"] = _pre_updates
	report["trace"] = _trace
	if _landed_frames.size() != S06_QUIZZES.size() or _landed_frames.back() > _s06_end:
		failures.append("S06: 10 枚の壁が S06 の中で着地していない（%s）" % str(_landed_frames))
	if _arrive_frames != _planned_arrive_frames:
		failures.append("S06: arrived at %s, planned %s" % [str(_arrive_frames), str(_planned_arrive_frames)])
	if _ready_frame < 1 or _ready_frame > _s06_end:
		failures.append("S06: 「問題ができました！」が S06 の中にない（%d）" % _ready_frame)
	if _s07_frames != _s07_starts:
		failures.append("S07: switched at %s, planned %s" % [str(_s07_frames), str(_s07_starts)])


func _cleanup() -> void:
	if measure:
		return
	QuizManager.provider.llm_mode = _saved_provider_mode


# ------------------------------------------------------------------ 本物のオンライン生成の計測（measure=online）

const MEASURE_TIMEOUT_MS := 60000

## 本物のゲームと同じく QuizGameState.start_game() で 1 ラウンド（10 問・普通・S06 の教科と学年）の生成を始め、
## 準備中の更新（_update_preloading：毎フレーム provider.get_quizzes で届いた分を quiz_list へ）を回して、
## 問題が quiz_list に入った実時間（start_game からのミリ秒）を report の measure に書く。プロキシを本当に使う。
## 端末の出題履歴（user:// の履歴やプール）は書き換わるので、測る前に控えて、終わったら戻すこと（docs/pv/takes/s06_s07.md）。
func _measure_online() -> void:
	var settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 3000:   # 起動直後の許可証などの準備を待つ
		await get_tree().process_frame
	_saved_provider_mode = QuizManager.provider.llm_mode
	QuizManager.provider.set_llm_mode("ONLINE")
	gs = QuizGameState.new(QuizManager.provider)
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.subject = S06_SUBJECT
	gs.grade = S06_GRADE
	gs.difficulty = "普通"
	gs.llm_mode = "ONLINE"
	QuizManager.game_state = gs
	var arrivals: Array = []
	var t0 := Time.get_ticks_msec()
	gs.start_game()
	var last := 0
	var ready_ms := -1
	while Time.get_ticks_msec() - t0 < MEASURE_TIMEOUT_MS:
		await get_tree().process_frame
		if gs.game_state == Constants.STATE_PRELOADING:
			gs._update_preloading(get_process_delta_time())
		var now := Time.get_ticks_msec() - t0
		while last < gs.quiz_list.size():
			var item: QuizItem = gs.quiz_list[last]
			arrivals.append({"ms": now, "n": last + 1, "src": item.src if item != null else "",
				"q": item.q.left(24) if item != null else ""})
			last += 1
		if gs.game_state != Constants.STATE_PRELOADING:
			ready_ms = now
			break
	report["measure"] = {"players": players, "subject": S06_SUBJECT, "grade": S06_GRADE, "difficulty": "普通",
		"arrivals": arrivals, "ready_ms": ready_ms, "state": gs.game_state,
		"round_new_target": QuizManager.provider.get("_round_new_target"),
		"started": Time.get_datetime_string_from_system()}
	if ready_ms < 0:
		failures.append("measure: %d 問しか届かなかった（%d ms）" % [arrivals.size(), MEASURE_TIMEOUT_MS])
	QuizManager.provider.end_round()
	QuizManager.provider.set_llm_mode(_saved_provider_mode)
