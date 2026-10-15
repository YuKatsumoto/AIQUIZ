extends Node

## オンライン対戦のマッチング演出（docs/online_match_staging/spec.md）を、リレーなしで通しで確かめる。
## 時間を固定して（--fixed-fps 60）状態の順と長さを測り（受け入れ基準 A1〜A3）、場面ごとにスクリーンショットを撮る。
##   Godot --path . --fixed-fps 60 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_staging_runtime.gd [shots=DIR] [scenario=...] [movie=1]
## scenario（, でつなぐ。省略で all）：
##   normal          乗り込み → … → 検索中 3 秒 → マッチ（ゲスト）→ 合流 → 並走 → カットイン → 読み込み → SWAP
##   early_boarding  乗り込み 1.0 秒でマッチ：操縦席・上昇・検索中を飛ばす
##   early_takeoff   離陸の途中でマッチ：浮いて 0.8 秒で合流
##   early_climb     上昇の途中でマッチ：すぐ合流
##   cancel          乗り込みの途中と検索中で「やめる」：0.40 秒以内に待機へ戻る
##   short           「みじかい」演出の長さ
##   requeue         合流のあと相手がいなくなる：空のまま探し直し、2 回目はホームへ
## movie=1 は Movie Maker で動画を書き出すとき用（スクリーンショットを撮らず、normal だけを通す）。
## cruise=秒 は normal の検索中をその秒数だけ延ばす（検索中のショットを一巡り見るとき。3 秒ごとに s5_cruise_tNN を撮る）。
## カメラ（仕様書 21）：乗り込み〜検索中は、切り替え（cut）のほかで画が飛ばないこと、被写体が画面に入っていること、
## 検索中のヘリが下の帯より上にいること、飛んでいるヘリにカメラが近づきすぎないことを毎フレーム／場面ごとに確かめる。

const DEAD_RELAY := "ws://127.0.0.1:9"
const DT := 1.0 / 60.0
const TOL := 0.05
## カメラの動きの速さの上限（切り替えのほか。60 fps で 1 フレーム 0.5 m・6°）
const CAMERA_MAX_SPEED := 30.0
const CAMERA_MAX_TURN_RATE := 360.0
## 飛んでいるヘリの中心からカメラまでの最短（ローターの半径 5.3 m ＋ゆとり）
const CAMERA_MIN_HELI_DISTANCE := 6.5
const CAMERA_STATES := ["BOARDING", "COCKPIT", "TAKEOFF", "CLIMB", "CRUISE"]
## 離陸〜急発進（TAKEOFF・CLIMB）のカメラは据え置き：位置は向きを変えるだけで動かない（m）
const CAMERA_LIFTOFF_MAX_DRIFT := 0.02

var menu: OnlineMenu
var director: OnlineStagingDirector
var failures: Array[String] = []
var checks := 0
var shots_dir := ""
var movie := false
var report := {}
var _log: Array = []      # [state_name, sim_time]
var _sim := 0.0
var cruise_extra := 0.0
## カメラの見張り：前のフレームのカメラ・切り替えの回数、いちばん大きかった 1 フレームの動き、ヘリへの最短
var _cam_prev := Transform3D.IDENTITY
var _cam_prev_cuts := -1
var _cam_max_speed := 0.0
var _cam_max_turn := 0.0
var _cam_worst := ""
var _cam_min_heli := INF
## 離陸〜急発進：切った所の位置と、そこからいちばん離れた距離
var _cam_liftoff_from := Vector3.ZERO
var _cam_liftoff_set := false
var _cam_liftoff_drift := 0.0


func _ready() -> void:
	call_deferred("run")


func _process(delta: float) -> void:
	_sim += delta
	_watch_camera(delta)


## 毎フレーム：切り替えのないフレームで、カメラの位置と向きがどれだけ動いたか。飛んでいるヘリとの距離。
func _watch_camera(delta: float) -> void:
	if director == null or not is_instance_valid(director) or menu == null or not is_instance_valid(menu) or menu.stage == null:
		_cam_prev_cuts = -1
		return
	var cam := menu.stage.camera.global_transform
	var cuts := director.camera_rig.cut_count
	var name := director.state_name()
	if CAMERA_STATES.has(name) and _cam_prev_cuts == cuts and delta > 0.0:
		var speed := cam.origin.distance_to(_cam_prev.origin) / delta
		var turn := rad_to_deg((-cam.basis.z).angle_to(-_cam_prev.basis.z)) / delta
		if speed > _cam_max_speed or turn > _cam_max_turn:
			_cam_worst = "%s %.2f s (%s)" % [name, director.state_time, director.shot_name]
		_cam_max_speed = maxf(_cam_max_speed, speed)
		_cam_max_turn = maxf(_cam_max_turn, turn)
	if name in ["TAKEOFF", "CLIMB", "CRUISE"]:
		var heli := menu.stage.my_heli.global_transform * (OnlineStagingTimeline.SUBJECTS.heli as Vector3)
		_cam_min_heli = minf(_cam_min_heli, cam.origin.distance_to(heli))
	if name in ["TAKEOFF", "CLIMB"]:
		if not _cam_liftoff_set or _cam_prev_cuts != cuts:
			_cam_liftoff_from = cam.origin
			_cam_liftoff_set = true
		_cam_liftoff_drift = maxf(_cam_liftoff_drift, cam.origin.distance_to(_cam_liftoff_from))
	else:
		_cam_liftoff_set = false
	_cam_prev = cam
	_cam_prev_cuts = cuts


## 点が画面のどこに映るか（-1〜1、右と上が正）。カメラのうしろなら (9, 9)。
func _screen(point: Vector3) -> Vector2:
	var camera := menu.stage.camera
	if camera.is_position_behind(point):
		return Vector2(9.0, 9.0)
	var size := camera.get_viewport().get_visible_rect().size
	var p := camera.unproject_position(point)
	return Vector2(p.x / size.x * 2.0 - 1.0, 1.0 - p.y / size.y * 2.0)


## 被写体が画面の安全な枠（|x|, |y| ≤ limit）に入っているか。min_y があれば、それより上か。
func _check_framed(label: String, point: Vector3, limit: float = 0.8, min_y: float = -1.0) -> void:
	var s := _screen(point)
	report["frame_%s" % label] = [snappedf(s.x, 0.01), snappedf(s.y, 0.01)]
	check(absf(s.x) <= limit and absf(s.y) <= limit and s.y >= min_y, "camera: %s is framed (%.2f, %.2f)" % [label, s.x, s.y])


func _heli_point(key: String) -> Vector3:
	return menu.stage.my_heli.global_transform * (OnlineStagingTimeline.SUBJECTS[key] as Vector3)


func _their_point() -> Vector3:
	return menu.stage.their_heli.global_transform * (OnlineStagingTimeline.SUBJECTS.heli as Vector3)


func run() -> void:
	var scenarios := ["normal", "early_boarding", "early_takeoff", "early_climb", "cancel", "short", "requeue"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots_dir = arg.trim_prefix("shots=")
		elif arg.begins_with("scenario="):
			scenarios = Array(arg.trim_prefix("scenario=").split(","))
		elif arg == "movie=1":
			movie = true
			scenarios = ["normal"]
		elif arg.begins_with("cruise="):
			cruise_extra = float(arg.trim_prefix("cruise="))
	NetworkManager.relay_url = DEAD_RELAY
	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	await _frames(10)
	menu = get_tree().current_scene as OnlineMenu
	check(menu != null, "online menu opens")
	if menu == null:
		_finish()
		return
	await _wait(func() -> bool: return not SceneTransition.is_transitioning(), 6000)
	director = menu.director
	check(director != null and menu.stage != null, "the 3D heliport and the staging director exist")
	if director == null:
		_finish()
		return
	# 本物の切り替え（ゲーム画面へ）はしない：SWAP の合図を測るだけ
	director.swap_ready.disconnect(menu._on_swap_ready)
	director.hold_started.disconnect(menu._on_hold_started)
	director.state_changed.connect(func(s: int) -> void: _log.append([OnlineStagingDirector.STATE_NAMES[s], _sim]))
	await _frames(30)
	await _shot("s0_idle")
	_idle_checks()
	for name: String in scenarios:
		await _reset()
		match name:
			"normal":
				await _scenario_normal()
			"early_boarding":
				await _scenario_early("BOARDING", 1.0)
			"early_takeoff":
				await _scenario_early("TAKEOFF", 0.3)
			"early_climb":
				await _scenario_early("CLIMB", 1.0)
			"cancel":
				await _scenario_cancel()
			"short":
				await _scenario_short()
			"requeue":
				await _scenario_requeue()
	_finish()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _idle_checks() -> void:
	var stage := menu.stage
	var heli := stage.my_heli
	check(heli.global_transform.origin.distance_to(stage.pad_ground.origin) < 0.01, "S0: the helicopter rests on the pad")
	check(heli.door_openness("L") == 0.0, "S0: the left door is closed")
	check(not heli.get_node("Model").find_child("Belt_L", true, false).visible, "S0: Belt_L is hidden")
	check(heli.pilot != null, "S0: Hatena sits in the right seat")
	var me_center := stage.me().center()
	var spot := heli.marker_global("MK_IdleSpot")
	check(Vector2(me_center.x - spot.x, me_center.z - spot.z).length() < 0.5, "S0: the player waits at MK_IdleSpot")
	check(menu.chrome() == OnlineMenu.CHROME_MENU, "S0: the home column is shown")


## M2：足の裏（低いほうの足）が、目印の床の高さに ±3 cm で着いている。
func _check_feet(label: String, marker: String) -> void:
	var heli := menu.stage.my_heli
	var floor_y := heli.marker_global(marker).y
	var lowest: float = menu.stage.players.call("_lowest_intro_foot_mesh_y", menu.stage.me().parts())
	var gap := lowest - floor_y
	report["feet_%s" % label.replace(" ", "_")] = snappedf(gap, 0.001)
	check(absf(gap) <= 0.03, "M2: feet rest on the %s (gap %.3f m)" % [label, gap])


func _reset() -> void:
	director.reset_to_idle()
	menu.go_home()
	director.short_mode = false
	await _frames(5)
	_log.clear()
	_cam_max_speed = 0.0
	_cam_max_turn = 0.0
	_cam_worst = ""
	_cam_min_heli = INF
	_cam_liftoff_drift = 0.0


func _begin() -> void:
	menu.set("_search_kind", &"random")
	menu.call("_begin_departure")


func _match(as_host: bool) -> void:
	NetworkManager.is_host = as_host
	NetworkManager.opponent_name = "テストの あいて"
	NetworkManager.opponent_profile = {"hat": 3, "name": "テストの あいて"}
	NetworkManager.match_settings = {"subject": "さんすう", "grade": 3, "difficulty": 1}
	NetworkManager.match_you = {"name": GameManager.online_name}
	menu.call("_on_matched", {"you": {"name": GameManager.online_name}})


## 状態の長さを _log から測る（次の状態に入るまで）。
func _lengths() -> Dictionary:
	var out := {}
	for i in range(_log.size() - 1):
		out[_log[i][0]] = snappedf(float(_log[i + 1][1]) - float(_log[i][1]), 0.001)
	return out


func _order() -> Array:
	return _log.map(func(e: Array) -> String: return e[0])


func _expect_lengths(label: String, expected: Dictionary) -> void:
	var got := _lengths()
	for key: String in expected:
		var want := float(expected[key])
		check(got.has(key) and absf(float(got[key]) - want) <= TOL, "%s: %s lasts %.2f (got %s)" % [label, key, want, str(got.get(key))])


# ---------- シナリオ ----------

func _scenario_normal() -> void:
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU, "music: the heliport home plays the menu track")
	_begin()
	await _seconds(0.05)
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU and AudioManager.get_music_context() == AudioManager.MUSIC_CONTEXT_ONLINE_STAGING, "music: boarding lowers the BGM volume (it keeps playing)")
	check(menu.chrome() == OnlineMenu.CHROME_STAGING, "BOARDING hides the column and shows the small cancel")
	await _shot_at("s1_board_walk", 1.00)
	_check_feet("deck", "MK_BoardStand")
	_check_framed("board_walk", menu.stage.me().center())
	await _shot_at("s1_board_step", 1.97)
	_check_feet("step", "MK_Step")
	_check_framed("board_step", menu.stage.me().center())
	await _shot_at("s1_board_sill", 2.30)
	await _shot_at("s1_board_turn", 2.65)
	_check_feet("cabin floor", "MK_DoorSill")
	await _shot_at("s1_board_sit", 3.60)
	_check_framed("board_sit", menu.stage.me().center())
	await _shot_at("s1_board_seated", 4.65)
	_check_framed("board_seated", menu.stage.me().center(), 0.6)
	await _wait_state("COCKPIT", 6.0)
	check(menu.stage.my_heli.door_openness("L") < 0.6, "COCKPIT: the door is closing")
	await _seconds(1.2)
	await _shot("s2_cockpit")
	_check_framed("cockpit", _heli_point("cockpit"), 0.4)
	check(menu.stage.my_heli.get_node("Model").find_child("Belt_L", true, false).visible, "COCKPIT: Belt_L is shown")
	await _wait_state("TAKEOFF", 3.0)
	await _seconds(1.6)
	await _shot("s3_takeoff")
	_check_framed("takeoff", _heli_point("heli"), 0.7)
	check(menu.stage.my_heli.global_position.y > menu.stage.pad_ground.origin.y + 1.0, "TAKEOFF: the helicopter lifts off")
	# S3（仕様書 24）：浮いたらホバーで止まらず、前へ進みながら上がり続ける
	var lift_from := menu.stage.my_heli.global_position
	await _seconds(0.25)
	var lift_speed := menu.stage.my_heli.global_position.distance_to(lift_from) / 0.25
	report["takeoff_end_speed_mps"] = snappedf(lift_speed, 0.1)
	check(lift_speed > 3.0, "S3: the helicopter keeps flying out of the takeoff without a hover (%.1f m/s)" % lift_speed)
	await _wait_state("CLIMB", 3.0)
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU and AudioManager.get_music_context() == AudioManager.MUSIC_CONTEXT_ONLINE_STAGING, "music: stays lowered through takeoff and the dash")
	var ducked_db: float = AudioManager.CONTEXT_VOLUME_DB[AudioManager.MUSIC_CONTEXT_ONLINE_STAGING] + AudioManager.BGM_TRACK_GAIN_DB
	check(absf(AudioManager.bgm_player.volume_db - ducked_db) < 0.5 and AudioManager.bgm_player.playing, "music: the lowered BGM is really playing at %.1f dB (%.1f)" % [ducked_db, AudioManager.bgm_player.volume_db])
	# S4（仕様書 22・24）：旋回しながら上がるあいだにジェットポッドを広げて溜め → 点火して急発進 → 暗転 → 検索中で明ける
	var climb_s := director.duration("CLIMB")
	await _seconds(0.35 * climb_s)
	await _shot("s4_boost_charge")
	_check_framed("boost_charge", _heli_point("heli"), 0.7)
	check(menu.stage.my_heli.jet_charge() > 0.5 and not menu.stage.my_heli.jets_ignited, "S4: the jet pods deploy before ignition (charge %.2f)" % menu.stage.my_heli.jet_charge())
	var charge_from := menu.stage.my_heli.global_position
	await _seconds(0.1)
	var charge_speed := menu.stage.my_heli.global_position.distance_to(charge_from) / 0.1
	var charge_bank := rad_to_deg(asin(clampf(-menu.stage.my_heli.global_basis.x.normalized().y, -1.0, 1.0)))
	report["boost_charge_speed_mps"] = snappedf(charge_speed, 0.1)
	report["boost_charge_bank_deg"] = snappedf(charge_bank, 0.1)
	check(charge_speed > 5.0, "S4: the helicopter is already flying before ignition (%.1f m/s)" % charge_speed)
	check(charge_bank < -8.0, "S4: the helicopter banks left into its turn before ignition (%.1f deg)" % charge_bank)
	await _seconds(0.07 * climb_s - 0.1)
	await _shot("s4_boost_pre_ignite")
	await _seconds(0.10 * climb_s)
	await _shot("s4_boost_ignite")
	_check_framed("boost_ignite", _heli_point("heli"), 0.8)
	check(menu.stage.my_heli.jets_ignited, "S4: the jets ignite for the dash")
	await _seconds(0.18 * climb_s)
	await _shot("s4_boost_dash")
	_check_framed("boost_dash", _heli_point("heli"), 0.9)
	var dash_height := menu.stage.my_heli.global_position.y - menu.stage.pad_ground.origin.y
	report["boost_dash_height_m"] = snappedf(dash_height, 0.1)
	check(dash_height > 15.0, "S4: the helicopter dashes up and away (%.1f m)" % dash_height)
	await _seconds(0.22 * climb_s)
	await _shot("s4_boost_fade")
	report["boost_fade"] = snappedf(director.fade, 0.01)
	check(director.fade > 0.3, "S4: the screen fades to black at the end of the dash (%.2f)" % director.fade)
	await _wait_state("CRUISE", 3.0)
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MATCH and AudioManager.get_music_context() == AudioManager.MUSIC_CONTEXT_MENU, "music: the matching wait plays the match track at the normal volume")
	report["cruise_fade_start"] = snappedf(director.fade, 0.01)
	check(director.fade > 0.85, "CRUISE starts from black (%.2f)" % director.fade)
	await _seconds(0.7)
	var normal_db: float = AudioManager.CONTEXT_VOLUME_DB[AudioManager.MUSIC_CONTEXT_MENU] + AudioManager.BGM_TRACK_GAIN_DB
	check(absf(AudioManager.bgm_player.volume_db - normal_db) < 0.5 and AudioManager.bgm_player.playing, "music: the match track reaches %.1f dB (%.1f)" % [normal_db, AudioManager.bgm_player.volume_db])
	check(not menu.stage.my_heli.jets_ignited and menu.stage.my_heli.jet_charge() == 0.0, "CRUISE: the jets are off and stowed")
	await _seconds(0.8)
	check(director.fade == 0.0, "CRUISE: the search screen fades in")
	var heli_sound = menu.stage.my_heli.sound
	var duck := db_to_linear(heli_sound.WAITING_DUCK_DB)
	check(heli_sound.waiting and absf(heli_sound._waiting_scale - duck) < 0.03, "CRUISE: the helicopter sound sits %.0f dB under while waiting (x%.2f)" % [heli_sound.WAITING_DUCK_DB, heli_sound._waiting_scale])
	check(menu.current_id() == OnlineMenu.SEARCH and menu.chrome() == OnlineMenu.CHROME_BAND, "CRUISE shows the search band")
	check(menu.stage.flow_enabled and not menu.stage.heliport.visible, "CRUISE scrolls the sea instead of moving far away")
	await _shot("s5_cruise_c1")
	_check_cruise_frame("c1")
	await _seconds(9.7)
	await _shot("s5_cruise_blend")
	_check_cruise_frame("blend")
	await _seconds(3.0)
	await _shot("s5_cruise_c2")
	_check_cruise_frame("c2")
	var waited := 0.0
	while waited < cruise_extra - 0.001:
		await _seconds(3.0)
		waited += 3.0
		await _shot("s5_cruise_t%02d" % int(round(13.5 + waited)))
		_check_cruise_frame("t%02d" % int(round(13.5 + waited)))
	check(not menu.stage.my_heli.jets_ignited, "CRUISE: the jets stay off while waiting")
	check(menu.stage.flow_distance > 200.0, "CRUISE: the sea flows at 24 m/s (%.0f m)" % menu.stage.flow_distance)
	_check_camera_motion("normal")
	_match(false)
	await _seconds(0.05)
	check(director.state_name() == "JOIN", "a match during CRUISE starts JOIN")
	check(not heli_sound.waiting, "JOIN: the helicopter sound is back to its normal level")
	check(menu.stage.my_slot == 2 and menu.stage.my_heli != null, "JOIN: the guest becomes slot 2 (blue)")
	# S6（仕様書 22）：相手は画面の外からジェットブーストで曲がりながら飛び込み、着く前にジェットを切る
	var entry := _screen(_their_point())
	report["join_entry_screen"] = [snappedf(entry.x, 0.01), snappedf(entry.y, 0.01)]
	check(absf(entry.x) > 1.0 or absf(entry.y) > 1.0, "JOIN: the opponent comes in from outside the frame (%.2f, %.2f)" % [entry.x, entry.y])
	check(menu.stage.their_heli.jets_ignited, "JOIN: the opponent arrives on its jet boost")
	var join_s := director.duration("JOIN")
	await _seconds(0.18 * join_s)
	await _shot("s6_join_early")
	await _seconds(0.17 * join_s)
	await _shot("s6_join_turn")
	report["join_bank_deg"] = snappedf(rad_to_deg(asin(clampf(-menu.stage.their_heli.global_basis.x.normalized().y, -1.0, 1.0))), 0.1)
	check(absf(float(report["join_bank_deg"])) > 8.0, "JOIN: the opponent banks into its turn (%.1f deg)" % float(report["join_bank_deg"]))
	await _seconds(0.30 * join_s)
	await _shot("s6_join_late")
	_check_framed("join_opponent", _their_point(), 0.9)
	check(not menu.stage.their_heli.jets_ignited, "JOIN: the opponent cuts its jets after joining")
	await _wait_state("FORMATION", 3.0)
	check(not menu.stage.their_heli.jets_ignited and menu.stage.their_heli.jet_charge() == 0.0, "FORMATION: both jets are off")
	await _seconds(1.5)
	await _shot("s7_formation")
	var mine := menu.stage.camera.unproject_position(menu.stage.my_heli.global_position)
	var theirs := menu.stage.camera.unproject_position(menu.stage.their_heli.global_position)
	check(mine.x < theirs.x, "FORMATION: my helicopter is on the left of the screen (D6)")
	report["formation_screen_x"] = [snappedf(mine.x, 1), snappedf(theirs.x, 1)]
	await _wait_state("CUTIN_IN", 2.0)
	await _seconds(0.3)
	await _shot("s8_cutin_bolt")
	await _seconds(0.4)
	await _shot("s8_cutin_vs")
	await _wait_state("CUTIN_HOLD", 2.0)
	check(menu.cutin != null and menu.cutin.visible, "the cut-in is on screen")
	if menu.cutin != null:
		var names := menu.cutin.names()
		check(names[0] == menu.shown_own_name() and names[1] == "テストの あいて", "cut-in names: left = me, right = them (%s)" % [names])
	await _seconds(1.0)
	await _shot("s9_hold")
	# 開始の合図（ゲストは start を受け取る）と読み込みを待つ
	director.start_ready = true
	var swapped := await _wait(func() -> bool: return director.state_name() == "SWAP", 20000)
	check(swapped, "CUTIN_HOLD leaves for SWAP once loaded and started")
	report["loaded"] = menu.is_game_loaded()
	report["normal_order"] = _order()
	report["normal_lengths"] = _lengths()
	check(_order().slice(0, 10) == ["BOARDING", "COCKPIT", "TAKEOFF", "CLIMB", "CRUISE", "JOIN", "FORMATION", "CUTIN_IN", "CUTIN_HOLD", "SWAP"],
		"A1: states in order (%s)" % [_order()])
	_expect_lengths("A1", {"BOARDING": 4.70, "COCKPIT": 2.40, "TAKEOFF": 2.60, "CLIMB": 4.40, "JOIN": 3.20, "FORMATION": 1.80, "CUTIN_IN": 0.90})
	var hold := float(_lengths().get("CUTIN_HOLD", 0.0))
	check(hold >= 1.40 - TOL, "A1: CUTIN_HOLD lasts at least 1.40 (got %.2f)" % hold)
	if movie:
		await _movie_reveal()
		return
	if menu.cutin != null:
		menu.cutin.hide_now()


## 動画（movie=1）だけ：SWAP の覆い方（カットインを写して中央の線で割る）でゲーム画面へ切り替え、開くところまで撮る。
func _movie_reveal() -> void:
	var packed: PackedScene = menu.get("_game_packed")
	var shot := get_viewport().get_texture().get_image()
	SceneTransition.hold_versus_split(ImageTexture.create_from_image(shot), menu.cutin.seam_points(), director.duration("REVEAL"), menu.cutin.side_colors())
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(OnlineMenu.GAME_WORLD_PATH)
	menu = null
	await _wait(func() -> bool: return not SceneTransition.is_transitioning(), 20000)
	await _seconds(1.5)


## 検索中：ヘリが画面に入り、下の帯（画面の下 2 割）より上にいる。カメラは機体から離れている。
func _check_cruise_frame(label: String) -> void:
	_check_framed("cruise_%s" % label, _heli_point("heli"), 0.8, -0.35)
	report["shot_cruise_%s" % label] = director.shot_name


## 乗り込みから検索中まで：切り替えのほかで画が飛ばず、飛んでいるヘリに近づきすぎない。
func _check_camera_motion(label: String) -> void:
	report["camera_%s" % label] = {"max_speed_mps": snappedf(_cam_max_speed, 0.01), "max_turn_dps": snappedf(_cam_max_turn, 0.1),
		"worst": _cam_worst, "min_heli_m": snappedf(_cam_min_heli, 0.01), "liftoff_drift_m": snappedf(_cam_liftoff_drift, 0.001)}
	check(_cam_max_speed <= CAMERA_MAX_SPEED and _cam_max_turn <= CAMERA_MAX_TURN_RATE,
		"camera: no jumps between cuts (%.2f m/s, %.1f deg/s at %s)" % [_cam_max_speed, _cam_max_turn, _cam_worst])
	check(_cam_min_heli >= CAMERA_MIN_HELI_DISTANCE, "camera: keeps clear of the flying helicopter (%.2f m)" % _cam_min_heli)
	check(_cam_liftoff_drift <= CAMERA_LIFTOFF_MAX_DRIFT, "camera: stays put through takeoff and the dash, only turning and zooming (%.3f m)" % _cam_liftoff_drift)
	_cam_liftoff_drift = 0.0
	_cam_max_speed = 0.0
	_cam_max_turn = 0.0
	_cam_worst = ""
	_cam_min_heli = INF


func _scenario_early(at_state: String, after: float) -> void:
	_begin()
	await _wait_state(at_state, 15.0)
	await _seconds(after)
	_match(true)
	await _wait_state("JOIN", 6.0)
	var order := _order()
	report["early_%s" % at_state.to_lower()] = {"order": order, "lengths": _lengths()}
	match at_state:
		"BOARDING":
			check(not order.has("COCKPIT") and not order.has("CLIMB") and not order.has("CRUISE"), "A2: early match in BOARDING skips COCKPIT, CLIMB and CRUISE (%s)" % [order])
			var takeoff := float(_lengths().get("TAKEOFF", 9.0))
			check(takeoff <= 0.8 + TOL, "A2: TAKEOFF after an early match lasts lift + 0.6 s (%.2f)" % takeoff)
		"TAKEOFF":
			check(not order.has("CLIMB") and not order.has("CRUISE"), "A2: early match in TAKEOFF goes to JOIN after lift-off (%s)" % [order])
		"CLIMB":
			var climb := float(_lengths().get("CLIMB", 9.0))
			check(not order.has("CRUISE") and climb <= after + 0.1, "A2: early match in CLIMB cuts straight to JOIN (%.2f)" % climb)
	_check_camera_motion("early_%s" % at_state.to_lower())
	check(not menu.stage.my_heli.jets_ignited and menu.stage.my_heli.jet_charge() == 0.0, "A2: my jets are off after an early match in %s" % at_state)
	await _seconds(0.5)
	await _shot("a2_early_%s_join" % at_state.to_lower())


func _scenario_cancel() -> void:
	for at_state: String in ["BOARDING", "CRUISE"]:
		await _reset()
		_begin()
		await _wait_state(at_state, 15.0)
		await _seconds(1.0)
		var t0 := _sim
		menu.cancel_search()
		var back := await _wait(func() -> bool: return director.state_name() == "IDLE", 2000)
		var took := _sim - t0
		check(back and took <= 0.40, "A3: cancel during %s returns to IDLE within 0.40 s (%.2f)" % [at_state, took])
		await _wait(func() -> bool: return not menu.get("_cancelling"), 2000)
		check(menu.current_id() == OnlineMenu.HOME and menu.chrome() == OnlineMenu.CHROME_MENU, "A3: cancel during %s shows home again" % at_state)
		check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU and AudioManager.get_music_context() == AudioManager.MUSIC_CONTEXT_MENU, "music: cancel during %s brings the menu track back at the normal volume" % at_state)
		check(menu.stage.my_heli.global_position.distance_to(menu.stage.pad_ground.origin) < 0.01 and not menu.stage.flow_enabled,
			"A3: the helicopter is back on the pad after cancel (%s)" % at_state)
		report["cancel_%s" % at_state.to_lower()] = snappedf(took, 0.001)
	await _shot("a3_after_cancel")


func _scenario_short() -> void:
	director.short_mode = true
	menu.set("_search_kind", &"random")
	director.begin_departure()
	await _wait_state("CRUISE", 15.0)
	_match(true)
	await _wait_state("CUTIN_IN", 6.0)
	report["short_lengths"] = _lengths()
	check(not _order().has("COCKPIT"), "short: COCKPIT is skipped")
	_expect_lengths("short", {"BOARDING": 2.94, "TAKEOFF": 1.60, "CLIMB": 3.00, "JOIN": 2.20, "FORMATION": 1.20})
	director.short_mode = false


func _scenario_requeue() -> void:
	_begin()
	await _wait_state("CRUISE", 15.0)
	_match(true)
	await _wait_state("JOIN", 2.0)
	await _seconds(0.6)
	menu.call("_on_forfeit", "host", "left")
	check(director.state_name() == "REQUEUE", "A7: the opponent leaving during JOIN starts REQUEUE")
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MATCH, "music: the match track keeps playing into the requeue")
	await _seconds(0.6)
	await _shot("a7_requeue")
	await _wait_state("CRUISE", 3.0)
	_cam_max_speed = 0.0
	_cam_max_turn = 0.0
	_cam_min_heli = INF
	await _seconds(2.0)
	await _shot("a7_requeue_cruise")
	_check_cruise_frame("requeue")
	_check_camera_motion("requeue")
	check(menu.current_id() == OnlineMenu.SEARCH and menu.stage.flow_enabled, "A7: back to the search band in the air")
	_match(true)
	await _wait_state("JOIN", 2.0)
	await _seconds(0.3)
	menu.call("_on_forfeit", "host", "left")
	var home := await _wait(func() -> bool: return director.state_name() == "IDLE" and menu.current_id() == OnlineMenu.HOME, 3000)
	check(home, "A7: a second loss goes home (D12)")


# ---------- 道具 ----------

func _wait_state(name: String, timeout_s: float) -> bool:
	var ok := await _wait(func() -> bool: return director.state_name() == name, int(timeout_s * 1000.0 / maxf(Engine.time_scale, 0.01)) + 20000)
	check(ok, "reached %s" % name)
	return ok


## 乗り込みの始まりから at 秒の場面を撮る。
func _shot_at(label: String, at: float) -> void:
	await _wait(func() -> bool: return director.state_name() != "BOARDING" or director.state_time >= at, 10000)
	await _shot(label)


func _seconds(duration: float) -> void:
	var end := _sim + duration
	while _sim < end - 0.0001:
		await get_tree().process_frame


func _shot(label: String) -> void:
	if movie or shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, label])


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _finish() -> void:
	# ゲーム画面の読み込み（別スレッド）の途中で終わると、読み込みが中断されたエラーが出るので待つ
	if menu != null and is_instance_valid(menu):
		await _wait(func() -> bool: return not is_instance_valid(menu) or int(menu.get("_load_state")) != 1, 30000)
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	print("ONLINE_STAGING " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
