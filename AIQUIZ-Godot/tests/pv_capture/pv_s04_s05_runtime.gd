extends "res://tests/pv_capture/pv_take_base.gd"

## PV S04「教科と学年をえらぶ」と S05「ヘリのお迎え」を、本物のメインメニューで撮る（1 人）。どちらも 2 小節。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s04_s05 quality=ultra sub=8
## テロップと設定パネルへの寄りは After Effects（docs/pv/previz/ae/build_s04_s07.jsx）。
## 引数 measure を付けると、ゲーム開始から先も等速で回し、ヘリの出来事の時刻（G_*）を report に書く。
##
## 流れ（PV フレーム。1 = S04 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   S04   1-225  メニューの設定パネル（UI あり）。1 拍ごとに矢印を押す（教科 国語 → 社会、学年 3 → 4 年、教科 → 英語 → 算数）。
##                5.5 拍目（155）で「ゲーム開始」：ゲームと同じく、ボタンを止めて決定音、「LETS'GO」のシャッター、UI が下がる、
##                ヘリの出発。カメラはメニューのまま（ヘリの演出が空へ向ける）で、ヘリが近づいてくるところまで等速で見せる。
##   S05a 226-366 横から寄った PV のカメラ（メニューのカメラではキャラが小さすぎる）。ヘリが降りてきて縄ばしごを下ろし、
##                揺れが収まるとキャラが助走してジャンプでつかまる。切らずに見せ、つかまる瞬間を 367（S05 の 6 拍目の頭）に合わせる。
##                縄ばしごの揺れが収まる時刻は物理で決まり、早回しの速さでも変わるので、走り出すまでは S05_PRE_SPEED 倍で回し、
##                走り出した瞬間に「走る時間＋飛びつく 0.62 秒」（物理によらない）が 367 で終わる速さに切り替える。
##   S05b 367-450 つかまったヘリの下、桟橋の床すれすれから見上げる PV のカメラ。エンジンをためて（ゲームの 0.8 秒）打ち上がり、
##                飛び去るのを見送る。打ち上がりを 409（S05 の 7.5 拍目）に合わせる。
## メニューでは UI 以外の効果音が鳴らないので、ヘリの音は編集で置く（docs/pv/capture.md）。

const S04_FRAMES := 225
const S05_FRAMES := 225
const HANDLE_FRAMES := 4

## 1 拍ごとの矢印：[拍, 行]
const SHIFTS := [[1.0, &"subject"], [2.0, &"grade"], [3.0, &"subject"], [4.0, &"subject"]]
const PRESS_BEAT := 5.5
const START_SUBJECT := "国語"
const START_GRADE := 3
const TELOP_END_BEAT := 6.5                 # 編集用の目安：UI が下がりきるころ（build_s04_s07.jsx）

## ヘリ（ゲームの秒、begin_game_start_departure からの経過。measure の等速で）：降りてきて縄ばしご 約 1.2 →
## 揺れが収まって走り出す 約 2.95 → ジャンプ 約 3.33 → つかまる 約 3.95 → エンジンをためて 0.8 秒で打ち上がり
const S05_PRE_SPEED := 1.45                 # S05 の頭から走り出すまでの早回し
const GRAB_HOLD := 0.622                    # 走り終えてからつかまるまで（HelicopterArrivalDirector.MENU_LADDER_GRAB_DURATION ＋ 1 更新）
const CHARGE := 0.8                         # つかまってから打ち上がりまで（MENU_BOOST_CHARGE_DURATION）
const GRAB_BEAT := 13.0                     # S05 の 6 拍目の頭（テイクの頭から 13 拍）
const LAUNCH_BEAT := 14.5

## S05a：横から寄るカメラ（1 人のときヘリは (−1.5, 9, −4) の上で止まり、キャラはその下の縄ばしごへ走る）
const S05A_EYE := Vector3(10.2, 1.1, 0.3)
const S05A_EYE_END := Vector3(9.2, 1.1, -0.4)
const S05A_TARGET := Vector3(-1.5, 5.1, -3.6)
const S05A_FOV := 60.0

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"

## S05b の見上げ：ヘリ（つかまった瞬間の位置）の下、桟橋の床すれすれから
const LOOKUP_EYE_OFFSET := Vector3(1.2, 0.0, 3.6)    # ヘリの真下から (x, z) ずらす。ヘリは −z へ飛ぶので、その反対側から遠ざかるのを見送る
const LOOKUP_EYE_Y := -0.55                          # 床（−1.2）の少し上
const LOOKUP_FOV := 64.0

var measure := false
var gs: QuizGameState
var menu                                    # main_menu.gd（型なしで、メニューの変数と関数をそのまま使う）
var preview: Node
var director: HelicopterArrivalDirector
var menu_cam: Camera3D
var _shift_frames: Dictionary = {}
var _press_frame := 0
var _pressed := false
var _departure_started := false
var _departure_t := -1.0                    # 出発した PV の秒
var _dep_time := 0.0
var _dep_at_s05 := -1.0                     # S05 の頭での出発からの経過（ゲームの秒）
var _speed := 1.0                           # 次の更新の早回し（撮影中に決める）
var _approach_t := -1.0                     # 走り出した PV の秒
var _grab_t := -1.0                         # つかまった PV の秒
var _events := {}
var _grab_frame := -1
var _launch_frame := -1
var _heli_at_grab := Vector3.INF
var _saved_tutorial_version := 0
var _saved_skin_path := ""
var _saved_skin_suspended := false
var _saved_provider_mode := ""
var _trace: Array = []


func _init() -> void:
	take_name = "s04_s05"


func _default_frames() -> int:
	return S04_FRAMES + S05_FRAMES + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg == "measure":
		measure = true


func _setup() -> void:
	for e: Array in SHIFTS:
		_shift_frames[bf(float(e[0]))] = e[1]
	_press_frame = bf(PRESS_BEAT)
	# メニューの起動演出・初回の案内・保守船の入港は飛ばす。見た目と設定は撮影用（保存しない）
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	_saved_tutorial_version = GameManager.tutorial_prompt_seen_version
	GameManager.tutorial_prompt_seen_version = GameManager.CURRENT_TUTORIAL_VERSION
	_saved_skin_path = PlayerSkinStore.path
	_saved_skin_suspended = PlayerSkinStore.suspended
	PlayerSkinStore.path = "user://pv_capture_player_skins.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore._skins[1] = PlayerSkinStore.normalized(1, PlayerSkin.from_code(P1_SKIN_CODE))
	PlayerSkinStore._hats[1] = P1_HAT
	gs = QuizManager.game_state
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.subject = START_SUBJECT
	gs.grade = START_GRADE
	gs.difficulty = "普通"
	gs.llm_mode = "ONLINE"
	_saved_provider_mode = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "ONLINE"
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null or not get_tree().current_scene.is_node_ready():
		await get_tree().process_frame
	menu = get_tree().current_scene
	preview = menu.get("_menu_wall_preview")
	if gs.has_pending_solo_customize_tour():
		failures.append("customize tour pending")
	preview.call("sync_menu_player_count", 1)
	await _frames(int(4.0 * FPS) * sub)                # 入場・P2 が消える演出・ベルトが止まるまで
	while menu.config_conveyor.is_moving():
		await get_tree().process_frame
	var stage: StageEnvironment = preview.call("get_stage_environment")
	if stage != null and stage.get("weather_cycle") != null:
		stage.get("weather_cycle").call("force_day_phase", 0.25)
	menu_cam = preview.call("get_camera")
	_hide_menu_extras()
	await _frames(30 * sub)
	report["start"] = {"subject": gs.subject, "grade": gs.grade, "players": gs.num_players}


## 撮らないもの：「設定 / API状態」、お知らせ、スキップの案内
func _hide_menu_extras() -> void:
	if menu.settings_btn != null:
		menu.settings_btn.visible = false
	var note := menu.find_child("AnnouncementLabel", true, false) as Control
	if note != null:
		note.visible = false
	var hint := menu.get_node_or_null("HelicopterSkipHint") as Control
	if hint != null:
		hint.modulate.a = 0.0


# ------------------------------------------------------------------ 時間

func _t_of(frame: int) -> float:
	return (frame - 1) / FPS


## 時間の速さは撮影中に決める（_speed）。S04 は等速。S05a は走り出すまで S05_PRE_SPEED 倍、走り出したら つかまる が
## 367 になる速さ、S05b は つかまってから打ち上がり（0.8 秒）が 409 になる速さ、そのあとは等速。
func _time_scale_for_step(_step_index: int) -> float:
	return 1.0 if measure else _speed


func _plan_speed(t: float) -> void:
	if measure:
		return
	var t5 := _t_of(S04_FRAMES + 1)
	var tg := _t_of(bf(GRAB_BEAT))
	var tl := _t_of(bf(LAUNCH_BEAT))
	if t < t5 - 0.0001:
		_speed = 1.0
	elif _approach_t < 0.0:
		_speed = S05_PRE_SPEED
	elif _grab_t < 0.0:
		# 残りのゲームの秒（走る残り＋飛びつき）を、つかまる拍までの残りの PV の秒に収める
		var remaining := _remaining_to_grab()
		_speed = clampf(remaining / maxf(tg - t, 0.001), 0.5, 3.0)
	elif not _events.has("launch"):
		var left := CHARGE - (_dep_time - float(_events["grab"]))
		_speed = clampf(left / maxf(tl - t, 0.001), 0.5, 3.0)
	else:
		_speed = 1.0


## 走り出してからつかまるまでの残り（ゲームの秒）：走る時間（プレイヤーが決めた duration）の残り＋飛びつき
func _remaining_to_grab() -> float:
	var pp: Node = preview.get("_preview_player")
	var approaches: Dictionary = pp.get("_intro_pickup_approaches") if pp != null else {}
	var run: Dictionary = approaches.get(1, {})
	var run_left := 0.0
	if not run.is_empty():
		run_left = maxf(float(run.get("duration", 0.0)) - float(run.get("elapsed", 0.0)), 0.0)
	var info: Dictionary = director.get("_helicopters")[0]
	if bool(info.get("pickup_started", false)):
		var since := float(director.get("_phase_elapsed")) - float(info.get("grab_started_at", 0.0))
		return maxf(GRAB_HOLD - since, 0.0)
	return run_left + GRAB_HOLD


# ------------------------------------------------------------------ 毎フレーム

func _before_update(_n: int) -> void:
	_hide_menu_extras()


func _update(n: int, t: float, dt: float) -> void:
	_track_departure(dt)
	var last_sub := (_step % sub) == 0
	if last_sub and _shift_frames.has(n + 1) and not menu.config_conveyor.is_moving():
		var row: StringName = _shift_frames[n + 1]
		var button: Button = menu.next_subject_btn if row == &"subject" else menu.next_grade_btn
		button.pressed.emit()                             # クリック音（ui_click）も鳴る
	if last_sub and n + 1 == _press_frame and not _pressed:
		_press_start()
	if last_sub and n == S04_FRAMES and _dep_at_s05 < 0.0 and _departure_started:
		_dep_at_s05 = _dep_time
		report["dep_at_s05"] = snappedf(_dep_at_s05, 0.0001)
	if _approach_t < 0.0 and _events.has("approach"):
		_approach_t = t
	if _grab_t < 0.0 and _events.has("grab"):
		_grab_t = t
	_plan_speed(t)
	if not measure and n > S04_FRAMES and n < bf(GRAB_BEAT):
		_apply_side_camera(n)
	if n >= bf(GRAB_BEAT) and not measure:
		_apply_lookup_camera(n, t)
	if last_sub and (n % 4 == 1 or n == bf(GRAB_BEAT) or n == bf(LAUNCH_BEAT)):
		_trace_frame(n)


## ゲームと同じ順：ボタンを止め、決定音、LETS'GO のシャッター（UI が下がる）、1 フレームおいてヘリの出発
func _press_start() -> void:
	_pressed = true
	menu.set("_menu_exit_in_progress", true)
	menu.call("_set_all_buttons_disabled", true)
	AudioManager.play_sfx(&"ui_start")
	_run_departure()


func _run_departure() -> void:
	await menu._play_start_ui_departure()
	await get_tree().process_frame
	_departure_started = bool(preview.call("begin_game_start_departure", 1))
	director = preview.get("_menu_start_departure")
	_dep_time = 0.0
	_departure_t = float(_step) / (FPS * sub)
	_events["departure_started"] = _departure_started
	_events["departure_frame"] = frame_of(_step)


func _track_departure(dt: float) -> void:
	if not _departure_started or director == null:
		return
	_dep_time += dt
	var info: Dictionary = director.get("_helicopters")[0] if not director.get("_helicopters").is_empty() else {}
	if not _events.has("approach") and bool(info.get("approach_started", false)):
		_events["approach"] = snappedf(_dep_time, 0.001)
	if not _events.has("jump") and bool(info.get("pickup_started", false)):
		_events["jump"] = snappedf(_dep_time, 0.001)
	if not _events.has("grab") and bool(info.get("captured", false)):
		_events["grab"] = snappedf(_dep_time, 0.001)
		_grab_frame = frame_of(_step)
		var holder := info.get("holder") as Node3D
		if holder != null:
			_heli_at_grab = holder.global_position
	if not _events.has("launch") and bool(director.get("_menu_boost_started")):
		_events["launch"] = snappedf(_dep_time, 0.001)
		_launch_frame = frame_of(_step)


## S05a：横から。カットの間にゆっくり寄る
func _apply_side_camera(n: int) -> void:
	if menu_cam == null:
		return
	var u := smooth(float(n - S04_FRAMES - 1) / float(bf(GRAB_BEAT) - S04_FRAMES - 1))
	var eye := S05A_EYE.lerp(S05A_EYE_END, u)
	menu_cam.global_transform = Transform3D(Basis.looking_at(S05A_TARGET - eye, Vector3.UP), eye)
	menu_cam.fov = S05A_FOV


## S05b：つかまった瞬間のヘリの下から見上げる（カメラは置いたまま。ヘリを追って向きだけ変え、飛び去るのを見送る）
func _apply_lookup_camera(_n: int, _t: float) -> void:
	if menu_cam == null or _heli_at_grab == Vector3.INF:
		return
	var eye := Vector3(_heli_at_grab.x + LOOKUP_EYE_OFFSET.x, LOOKUP_EYE_Y, _heli_at_grab.z + LOOKUP_EYE_OFFSET.z)
	var info: Dictionary = director.get("_helicopters")[0]
	# ローターの風で舞う破片は、床すれすれのカメラではレンズの前を横切る大きな白い四角になるので、このカットだけ隠す
	var downwash := info.get("downwash") as GPUParticles3D
	if downwash != null:
		downwash.visible = false
	var holder := info.get("holder") as Node3D
	var target := holder.global_position + Vector3(0.0, -1.2, 0.0) if holder != null else _heli_at_grab
	var up := Vector3.FORWARD if absf((target - eye).normalized().y) > 0.98 else Vector3.UP
	menu_cam.global_transform = Transform3D(Basis.looking_at(target - eye, up), eye)
	menu_cam.fov = LOOKUP_FOV


func _trace_frame(n: int) -> void:
	var entry := {"f": n, "dep": snappedf(_dep_time, 0.001), "subject": gs.subject, "grade": gs.grade, "ts": snappedf(Engine.time_scale, 0.01)}
	if director != null and not director.get("_helicopters").is_empty():
		var holder := (director.get("_helicopters")[0] as Dictionary).get("holder") as Node3D
		if holder != null:
			var p := holder.global_position
			entry["heli"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		entry["phase"] = str(director.get("_phase"))
	if menu_cam != null:
		var c := menu_cam.global_position
		entry["cam"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]
	_trace.append(entry)


func _check() -> void:
	report["events"] = _events
	report["grab_frame"] = _grab_frame
	report["launch_frame"] = _launch_frame
	report["grab_frame_planned"] = bf(GRAB_BEAT)
	report["launch_frame_planned"] = bf(LAUNCH_BEAT)
	report["press_frame"] = _press_frame
	report["telop_end_frame"] = bf(TELOP_END_BEAT)
	report["end"] = {"subject": gs.subject, "grade": gs.grade}
	report["trace"] = _trace
	if gs.subject != "算数" or gs.grade != 4:
		failures.append("S04: ended at %s %d年 (want 算数 4年)" % [gs.subject, gs.grade])
	if not _departure_started or _dep_at_s05 < 0.0:
		failures.append("S05: helicopter departure did not start before S05")
	if not measure:
		if absi(_grab_frame - bf(GRAB_BEAT)) > 1:
			failures.append("S05: grab at %d, planned %d" % [_grab_frame, bf(GRAB_BEAT)])
		if absi(_launch_frame - bf(LAUNCH_BEAT)) > 1:
			failures.append("S05: launch at %d, planned %d" % [_launch_frame, bf(LAUNCH_BEAT)])


func _cleanup() -> void:
	if director != null and is_instance_valid(director):
		preview.call("cancel_game_start_departure")
	QuizManager.provider.llm_mode = _saved_provider_mode
	GameManager.tutorial_prompt_seen_version = _saved_tutorial_version
	PlayerSkinStore.path = _saved_skin_path
	PlayerSkinStore.suspended = _saved_skin_suspended
