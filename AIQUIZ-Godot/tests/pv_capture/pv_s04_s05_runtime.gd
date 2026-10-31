extends "res://tests/pv_capture/pv_take_base.gd"

## PV S04「教科と学年をえらぶ」と S05「ヘリのお迎え」を、本物のメインメニューで撮る（既定は 2 人。players=1 で 1 人）。S04 は 2 小節、
## S05 は 3 小節（10/21 に S03 のタイトルから 4 拍回して、飛び去るのを見送る時間と S06 への帯のワイプを長くした）。
## 2 人のときはヘリが 2 機来て 1 人ずつ迎え、ハテナの椅子もヘリと同時にロケットで発射される（docs/seat_launch.md）。
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
##   S05b 367-562 つかまったヘリの下、桟橋の床すれすれから見上げる PV のカメラ。エンジンをためて（ゲームの 0.8 秒）打ち上がり、
##                飛び去るのを見送る。打ち上がりを 409（S05 の 7.5 拍目）に合わせる。最後の 3 拍に S06 への帯のワイプが重なる（AE）。
## メニューでは UI 以外の効果音が鳴らないので、ヘリの音は編集で置く（docs/pv/capture.md）。

const S04_FRAMES := 225
const S05_FRAMES := 337                     # 12 拍（337.5）。S04 と合わせて 20 拍 = 562 フレーム
const HANDLE_FRAMES := 4

## 1 拍ごとの矢印：[拍, 行]
const SHIFTS := [[1.0, &"subject"], [2.0, &"grade"], [3.0, &"subject"], [4.0, &"subject"]]
const PRESS_BEAT := 5.5
const START_SUBJECT := "国語"
const START_GRADE := 3
const TELOP_END_BEAT := 6.5                 # 編集用の目安：UI が下がりきるころ（build_s04_s07.jsx）

## ヘリ（ゲームの秒、begin_game_start_departure からの経過。measure の等速で）：降りてきて縄ばしご 約 1.2 →
## 揺れが収まって走り出す 約 2.95 → ジャンプ 約 3.33 → つかまる 約 3.95 → 甲板から吊り上げて 1.1 秒（手を振る）→
## エンジンをためて 0.8 秒で打ち上がり
const S05_PRE_SPEED := 1.45                 # S05 の頭から走り出すまでの早回し
const GRAB_HOLD := 0.622                    # 走り終えてからつかまるまで（HelicopterArrivalDirector.MENU_LADDER_GRAB_DURATION ＋ 1 更新）
## つかまってから打ち上がりまで（吊り上げ MENU_LIFT_DURATION ＋ ため MENU_BOOST_CHARGE_DURATION）
const CHARGE := HelicopterArrivalDirector.MENU_LIFT_DURATION + HelicopterArrivalDirector.MENU_BOOST_CHARGE_DURATION
const GRAB_BEAT := 13.0                     # S05 の 6 拍目の頭（テイクの頭から 13 拍）
const LAUNCH_BEAT := 14.5

## S05a：横から寄るカメラ（1 人のときヘリは (−1.5, 9, −4) の上で止まり、キャラはその下の縄ばしごへ走る）
const S05A_EYE := Vector3(10.2, 1.1, 0.3)
const S05A_EYE_END := Vector3(9.2, 1.1, -0.4)
const S05A_TARGET := Vector3(-1.5, 5.1, -3.6)
const S05A_FOV := 60.0
## 2 人のとき：ヘリは P1 側 (−8, 9, −4) と P2 側 (4, 9, −4) に 12 m 離れて止まる。横からでは 2 機が重なるので、
## 2 機の間の正面（+z 側）の低い所から、2 機と 2 人が並んで見えるように撮り、ゆっくり寄る
const S05A2_EYE := Vector3(-2.0, 2.4, 16.0)
const S05A2_EYE_END := Vector3(-2.0, 2.0, 12.5)
const S05A2_TARGET := Vector3(-2.0, 4.4, -4.0)
const S05A2_FOV := 58.0
const SETTLE_2P_SECONDS := 4.5
## S05b（2 人）：2 機の間の真下より手前、床すれすれから見上げる。2 機と、同時に打ち上がるハテナの椅子が一緒に入るように広く
const LOOKUP2_EYE := Vector3(-2.0, -0.55, -1.5)    # 収納したチップソーの柱（z ≈ 0〜2）より奥
const LOOKUP2_TARGET0 := Vector3(-2.0, 7.0, -4.0)
const LOOKUP2_FOV := 74.0

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"

## S05b の見上げ：ヘリ（つかまった瞬間の位置）の下、桟橋の床すれすれから
const LOOKUP_EYE_OFFSET := Vector3(1.2, 0.0, 3.6)    # ヘリの真下から (x, z) ずらす。ヘリは −z へ飛ぶので、その反対側から遠ざかるのを見送る
const LOOKUP_EYE_Y := -0.55                          # 床（−1.2）の少し上
const LOOKUP_FOV := 64.0

var measure := false
var players := 2
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
	elif arg.begins_with("players="):
		players = clampi(int(arg.trim_prefix("players=")), 1, 2)


func _setup() -> void:
	for e: Array in SHIFTS:
		_shift_frames[bf(float(e[0]))] = e[1]
	_press_frame = bf(PRESS_BEAT)
	# メニューの起動演出・保守船の入港は飛ばす。見た目と設定は撮影用（保存しない）
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	_saved_skin_path = PlayerSkinStore.path
	_saved_skin_suspended = PlayerSkinStore.suspended
	PlayerSkinStore.path = "user://pv_capture_player_skins.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore._skins[1] = PlayerSkinStore.normalized(1, PlayerSkin.from_code(P1_SKIN_CODE))
	PlayerSkinStore._hats[1] = P1_HAT
	PlayerSkinStore._skins[2] = PlayerSkinStore.normalized(2, PlayerSkin.from_code(P2_SKIN_CODE))
	PlayerSkinStore._hats[2] = P2_HAT
	gs = QuizManager.game_state
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.subject = START_SUBJECT
	gs.grade = START_GRADE
	gs.difficulty = "普通"
	gs.llm_mode = "ONLINE"
	_saved_provider_mode = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "ONLINE"
	# 撮影済みの素材と同じ見た目で撮る：メニュー背景のゴーストライダーは使わない
	MenuGhostRideDirector.globally_enabled = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null or not get_tree().current_scene.is_node_ready():
		await get_tree().process_frame
	menu = get_tree().current_scene
	preview = menu.get("_menu_wall_preview")
	# 待ちの演出の「チップソーに巻き込まれる」抽選を撮影のあいだだけ止める（menu_wall_background_preview.gd の SAW_*）
	preview.set("_saw_accident_cooldown", 1.0e9)
	preview.set("_saw_next_trial", 1.0e9)
	preview.call("sync_menu_player_count", players)
	await _frames(int(4.0 * FPS) * sub)                # 入場・P2 が消える演出・ベルトが止まるまで
	if players >= 2:
		# 2 人にした直後は P1 がチップソーに巻き込まれて復帰する流れが入る（約 4 秒、pv_s23_runtime.gd と同じ）。落ち着くまで待つ
		await _frames(int(SETTLE_2P_SECONDS * FPS) * sub)
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
		var last_grab := maxf(float(_events["grab"]), float(_events.get("grab2", 0.0)))
		var left := CHARGE - (_dep_time - last_grab)
		_speed = clampf(left / maxf(tl - t, 0.001), 0.5, 3.0)
	else:
		_speed = 1.0


## 走り出してからつかまるまでの残り（ゲームの秒）：走る時間（プレイヤーが決めた duration）の残り＋飛びつき。2 人のときは遅いほう
func _remaining_to_grab() -> float:
	var pp: Node = preview.get("_preview_player")
	var approaches: Dictionary = pp.get("_intro_pickup_approaches") if pp != null else {}
	var helis: Array = director.get("_helicopters")
	var worst := 0.0
	for i in range(mini(players, helis.size())):
		var info: Dictionary = helis[i]
		var rem := 0.0
		if bool(info.get("captured", false)):
			rem = 0.0
		elif bool(info.get("pickup_started", false)):
			var since := float(director.get("_phase_elapsed")) - float(info.get("grab_started_at", 0.0))
			rem = maxf(GRAB_HOLD - since, 0.0)
		else:
			var run: Dictionary = approaches.get(i + 1, {})
			var run_left := 0.0
			if not run.is_empty():
				run_left = maxf(float(run.get("duration", 0.0)) - float(run.get("elapsed", 0.0)), 0.0)
			rem = run_left + GRAB_HOLD
		worst = maxf(worst, rem)
	return worst


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
	# 2 人のときは、遅いほうが走り出した／つかまった時刻で決める（発射は最後につかまった 0.8 秒後）
	if _approach_t < 0.0 and _events.has("approach") and (players == 1 or _events.has("approach2")):
		_approach_t = t
	if _grab_t < 0.0 and _events.has("grab") and (players == 1 or _events.has("grab2")):
		_grab_t = t
	_plan_speed(t)
	if not measure and n > S04_FRAMES and n < bf(GRAB_BEAT):
		_apply_side_camera(n) if players == 1 else _apply_front_camera(n)
	if n >= bf(GRAB_BEAT) and not measure:
		_apply_lookup_camera(n, t) if players == 1 else _apply_lookup_camera_2p(n, t)
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
	_departure_started = bool(preview.call("begin_game_start_departure", players))
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
	var helis: Array = director.get("_helicopters")
	if helis.size() >= 2:
		var info2: Dictionary = helis[1]
		if not _events.has("approach2") and bool(info2.get("approach_started", false)):
			_events["approach2"] = snappedf(_dep_time, 0.001)
		if not _events.has("jump2") and bool(info2.get("pickup_started", false)):
			_events["jump2"] = snappedf(_dep_time, 0.001)
		if not _events.has("grab2") and bool(info2.get("captured", false)):
			_events["grab2"] = snappedf(_dep_time, 0.001)
			_events["grab2_frame"] = frame_of(_step)
	var saw: Variant = preview.get("_preview_saw")
	if saw != null and saw.get("operator_seat") != null:
		var phase := int(saw.operator_seat.seat_transfer.phase)
		var key := "seat_phase_%d" % phase
		if phase != 0 and not _events.has(key):
			_events[key] = snappedf(_dep_time, 0.001)
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


## S05a（2 人）：2 機の間の正面から。カットの間にゆっくり寄る
func _apply_front_camera(n: int) -> void:
	if menu_cam == null:
		return
	var u := smooth(float(n - S04_FRAMES - 1) / float(bf(GRAB_BEAT) - S04_FRAMES - 1))
	var eye := S05A2_EYE.lerp(S05A2_EYE_END, u)
	menu_cam.global_transform = Transform3D(Basis.looking_at(S05A2_TARGET - eye, Vector3.UP), eye)
	menu_cam.fov = S05A2_FOV


## S05b（2 人）：床すれすれから広く見上げる。カメラは置いたまま、2 機の中点を追って向きだけ変える
func _apply_lookup_camera_2p(_n: int, _t: float) -> void:
	if menu_cam == null or director == null:
		return
	var helis: Array = director.get("_helicopters")
	var mid := LOOKUP2_TARGET0
	var count := 0
	var sum := Vector3.ZERO
	for info: Dictionary in helis:
		var downwash := info.get("downwash") as GPUParticles3D
		if downwash != null:
			downwash.visible = false
		var holder := info.get("holder") as Node3D
		if holder != null:
			sum += holder.global_position + Vector3(0.0, -2.0, 0.0)
			count += 1
	if count > 0:
		mid = sum / count
	var eye := LOOKUP2_EYE
	menu_cam.global_transform = Transform3D(Basis.looking_at(mid - eye, Vector3.UP), eye)
	menu_cam.fov = LOOKUP2_FOV


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
		for hi in range(director.get("_helicopters").size()):
			var holder := (director.get("_helicopters")[hi] as Dictionary).get("holder") as Node3D
			if holder != null:
				var p := holder.global_position
				entry["heli" if hi == 0 else "heli%d" % (hi + 1)] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		entry["phase"] = str(director.get("_phase"))
	if menu_cam != null:
		var c := menu_cam.global_position
		entry["cam"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]
	var saw: Variant = preview.get("_preview_saw")
	if saw != null and saw.get("operator_seat") != null:
		var seat_node := saw.operator_seat as Node3D
		if seat_node != null:
			var sp := seat_node.global_position
			entry["seat"] = [snappedf(sp.x, 0.01), snappedf(sp.y, 0.01), snappedf(sp.z, 0.01), int(saw.operator_seat.seat_transfer.phase)]
	_trace.append(entry)


func _check() -> void:
	report["players"] = players
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
		var last_grab_frame := maxi(_grab_frame, int(_events.get("grab2_frame", -1)))
		if absi(last_grab_frame - bf(GRAB_BEAT)) > 1:
			failures.append("S05: last grab at %d, planned %d" % [last_grab_frame, bf(GRAB_BEAT)])
		if absi(_launch_frame - bf(LAUNCH_BEAT)) > 1:
			failures.append("S05: launch at %d, planned %d" % [_launch_frame, bf(LAUNCH_BEAT)])


func _cleanup() -> void:
	if director != null and is_instance_valid(director):
		preview.call("cancel_game_start_departure")
	QuizManager.provider.llm_mode = _saved_provider_mode
	PlayerSkinStore.path = _saved_skin_path
	PlayerSkinStore.suspended = _saved_skin_suspended
