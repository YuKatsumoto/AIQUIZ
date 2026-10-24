extends Node

## サドンデス「ひらけ！パラシュート」を実際の GameWorld（Forward+）で通しで動かす（docs/sudden_death_v2/parachute.md 第11章）。
## 引き分け → 分岐 → ヘリの迎え → 雲 → 空のセット → 導入（ボタン・ハッチ・落下）→ 図解ルールカード（Enter）→ 3・2・1
## → 本戦（本物のキーで答える）→ 決着（全開・ハンカチ・ドボン・着地）→ 勝者のダンス（エモートのキー）→ 縄ばしごの迎え
## → 帰還 → 判定から勝者の演出 → 操作可能。要所の画像と状態を保存する。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/parachute_runtime_bootstrap.gd -- case=p1
## case: p1 | p2 | final | dance
## 出力：artifacts/sudden_death_v2/parachute/runtime/<case>/（*.png と report.json）。

const OUT_ROOT := "res://artifacts/sudden_death_v2/parachute/runtime/"
const ANSWER_KEYS := [[KEY_A, KEY_W, KEY_S, KEY_D], [KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT]]
## 問題ごとの [P1, P2]："r" 正解、"w" 不正解、"-" 答えない。押す時刻は ANSWER_AT（問題の頭から）。
const PLANS := {
	"p1": [["r", "w"], ["r", "-"], ["r", "r"]],
	"p2": [["-", "r"], ["w", "r"], ["r", "r"]],
	"final": [],
	"dance": [["r", "w"], ["r", "-"], ["r", "r"]],
}
## 最後の1問：P2 が先に外し、P1 があとで当てる。
const FINAL_PLAN := ["r", "w"]
const ANSWER_AT := [1.4, 1.0]
const EXPECTED := {"p1": [1, "chute", 3], "p2": [2, "chute", 3], "final": [1, "final", -1], "dance": [1, "chute", 3]}
## dance：勝者がダンスの何秒目にどのキー（P1 は 1・2・3）を押すか。
const DANCE_PRESSES := [[1.0, KEY_3, 2], [3.0, KEY_2, 1]]

var scenario := "p1"
var fps := 60
var out := OUT_ROOT
var gs: QuizGameState
var world: Node
var helper: Node
var director: HeliSuddenDeathDirector
var checks := 0
var failures: Array[String] = []
var captured: Array[String] = []
var events: Array[Dictionary] = []
var shots_seen := {}
var _held := {}
var _pressed := {}
var _done_captures := {}
var _dance_slots: Array[int] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case="):
			scenario = arg.trim_prefix("case=")
	out = OUT_ROOT + scenario + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	GameManager.graphics_quality = "balanced"
	get_tree().root.size = Vector2i(1280, 720)
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	# 2026-10-19 から引き分けの種目はスカイゲート。パラシュートはテストで指定して動かす。
	gs.debug_sudden_death_kind = "parachute"
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	gs.p1_emote_slots = [EmoteData.EMOTE_GANGNAM, EmoteData.EMOTE_YMCA, EmoteData.EMOTE_HOKEY_POKEY]
	gs.sudden_death_event.connect(func(event: Dictionary) -> void: events.append(event.duplicate()))
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	director = world.get("_sudden_death_director") as HeliSuddenDeathDirector
	director.use_real_time = false
	await frames(fps)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await frames(maxi(3, fps / 4))
	world.call("_debug_force_draw_finish")
	check(await until(func() -> bool: return gs.result_presentation_active, 5.0), "forced draw starts the finale")
	check(gs.result_winner == 0 and gs.sudden_death_pending and gs.sudden_death_kind == "parachute", "a draw prepares the parachute sudden death (%s)" % gs.sudden_death_kind)
	await _watch_reveal_push()
	check(await until(func() -> bool: return director.act_name() == "SKY", 40.0), "the helicopters carry both into the sky (%s)" % director.act_name())
	check(gs.game_state == Constants.STATE_SUDDEN_DEATH and gs.sudden_death_game is ParachuteGame, "the parachute rules wait")
	await frames(fps)
	capture("01_sky")
	check(await until(func() -> bool: return director.act_name() == "VENUE", 30.0), "no cloud cover and no ladder: the game takes over in the sky (%s)" % director.act_name())
	var presenter := director.presenter() as ParachutePresenter
	check(presenter != null, "the parachute presenter")
	await _intro(presenter)
	await _rules(presenter)
	await _play(presenter)
	await _finish(presenter)
	await _home()
	_write_report()
	get_tree().quit(0 if failures.is_empty() else 1)


## 種目発表（common.md 4.2）：カメラが大型ビジョンへ寄るとき、一瞬でもヘリの方へ引かない。
## 引きの画へ追いついている途中（10.4〜11.0 秒）から、寄り終わる（11.0＋0.9 秒）まで毎フレーム測る。
func _watch_reveal_push() -> void:
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 10.7, 14.0)
	var camera := get_viewport().get_camera_3d()
	var screen: Dictionary = director.call("_find_screen")
	var samples: Array = []
	var guard := 0
	# 引きの画へ寄せている最後のフレームから測る（種目発表の頭の 1 フレームの飛びも数える）。
	while guard < fps * 4 and not screen.is_empty():
		guard += 1
		var act := director.act_name()
		if act == "BRANCH" or act == "REVEAL":
			var center: Vector3 = screen.center
			samples.append({"act": act, "t": snappedf(director.act_time(), 0.001), "d": camera.global_position.distance_to(center),
				"p": camera.global_position})
			if act == "REVEAL" and director.act_time() >= 0.9:
				break
		await get_tree().process_frame
	# 比べるのは種目発表の頭の 1 つ前（引きの画へ寄せているところ）から。
	var first := 0
	for i in range(samples.size()):
		if str(samples[i].act) == "REVEAL":
			first = maxi(i - 1, 0)
			break
	samples = samples.slice(first)
	var max_back := 0.0
	var max_step := 0.0
	for i in range(1, samples.size()):
		max_back = maxf(max_back, float(samples[i].d) - float(samples[i - 1].d))
		max_step = maxf(max_step, (samples[i].p as Vector3).distance_to(samples[i - 1].p))
	_reveal_report = {"frames": samples.size(), "max_back_m": snappedf(max_back, 0.0001), "max_step_m": snappedf(max_step, 0.001),
		"start_d": snappedf(float(samples[0].d), 0.01) if not samples.is_empty() else -1.0,
		"end_d": snappedf(float(samples.back().d), 0.01) if not samples.is_empty() else -1.0}
	check(samples.size() > 10, "the push to the big screen was measured (%d frames)" % samples.size())
	check(max_back < 0.01, "the camera never pulls back while pushing in on the big screen (%s)" % str(_reveal_report))
	check(max_step < 2.0, "no jump while pushing in (%s)" % str(_reveal_report))


var _reveal_report := {}


func _snap(presenter: ParachutePresenter) -> Dictionary:
	return presenter.get_debug_snapshot()


func _intro(presenter: ParachutePresenter) -> void:
	await until(func() -> bool: return _snap(presenter).shot == "c1_formation", 2.0)
	await frames(int(fps * 0.3))
	capture("02_formation")
	await until(func() -> bool: return _snap(presenter).shot == "c1b_cockpit", 2.0)
	await frames(int(fps * 0.4))
	capture("03_cockpit")
	await until(func() -> bool: return _snap(presenter).shot == "c2_under", 2.0)
	await frames(int(fps * 0.9))
	capture("04_drop")
	var puppet := director.puppet(1)
	check(puppet != null and not puppet.is_visible(), "the seated avatar hands over to the skydiver double")
	await until(func() -> bool: return _snap(presenter).shot == "c3_chase", 3.0)
	await frames(int(fps * 1.2))
	capture("05_chase")


func _rules(presenter: ParachutePresenter) -> void:
	check(await until(func() -> bool: return _snap(presenter).phase == "rules", 4.0), "the rule card after the drop")
	await frames(int(fps * 1.0))
	capture("06_rules")
	var hud: Dictionary = _snap(presenter).hud
	check(float(hud.alpha.rules) > 0.99, "the illustrated rule card is up (%s)" % str(hud.alpha))
	check((gs.sudden_death_game as ParachuteGame).phase == "idle", "nothing starts before Enter")
	_key(KEY_ENTER, true)
	await frames(2)
	_key(KEY_ENTER, false)
	check(await until(func() -> bool: return _snap(presenter).phase == "countdown", 1.0), "Enter starts the countdown")
	await frames(int(fps * 0.3))
	capture("07_countdown")
	check(await until(func() -> bool: return (gs.sudden_death_game as ParachuteGame).phase == "question", 4.0), "the first question after 3-2-1")


func _play(presenter: ParachutePresenter) -> void:
	var guard := 0.0
	var finals := 0
	var last_final_index := -1
	while gs.game_state == Constants.STATE_SUDDEN_DEATH and not (gs.sudden_death_game as ParachuteGame).finished and guard < 150.0:
		var game := gs.sudden_death_game as ParachuteGame
		_release_answer_keys()
		var number := game.question_index + 1
		if game.phase == "question":
			if game.final and game.question_index != last_final_index:
				last_final_index = game.question_index
				finals += 1
			var plan: Array = []
			if game.final:
				plan = FINAL_PLAN
			elif game.question_index < (PLANS[scenario] as Array).size():
				plan = PLANS[scenario][game.question_index]
			for slot in [0, 1]:
				if plan.is_empty():
					break
				var action := str(plan[slot])
				var tag := "%d_%d" % [game.question_index, slot]
				var at := float(ANSWER_AT[slot]) + (1.0 if game.final and slot == 0 else 0.0)
				if action != "-" and not _pressed.has(tag) and game.phase_time >= at:
					_pressed[tag] = true
					var count := game.current_choices()
					var choice := game.correct_choice() if action == "r" else (game.correct_choice() + 1) % count
					var key := QuizGameState.sudden_death_key_for_choice(choice, count)
					_key(ANSWER_KEYS[slot][key], true)
			if game.phase_time >= 0.9:
				if not _done_captures.has("10_q%d_question%s" % [number, "_final" if game.final else ""]):
					_check_p1_left(presenter, "Q%d%s" % [number, " (final)" if game.final else ""])
					if not game.final:
						_check_framing(presenter, "Q%d" % number)
				_capture_once("10_q%d_question%s" % [number, "_final" if game.final else ""])
				if number == 1 and not _done_captures.has("q1_hud"):
					_done_captures["q1_hud"] = true
					var hud: Dictionary = _snap(presenter).hud
					check(float(hud.alpha.quiz) > 0.9 and float(hud.alpha.status) > 0.9 and float(hud.alpha.altimeter) > 0.9,
						"question panel, chute stages and altimeter on screen (%s)" % str(hud.alpha))
		if game.phase == "reveal" and game.phase_time >= 0.95:
			_capture_once("11_q%d_reveal" % number)
		# 段が変わってから落ち着いたところ（答え合わせの終わり）でも構図を確かめる
		if game.phase == "reveal" and game.phase_time >= 1.45 and not game.final and not _done_captures.has("frame_r%d" % number):
			_done_captures["frame_r%d" % number] = true
			_check_framing(presenter, "Q%d reveal" % number)
		if game.final and _snap(presenter).shot == "c6_final" and game.phase == "question" and game.phase_time > 0.6:
			_capture_once("13_final_question")
		await get_tree().process_frame
		guard += 1.0 / float(fps)
		var shot := str(_snap(presenter).shot)
		if not shots_seen.has(shot):
			shots_seen[shot] = snappedf(director.act_time(), 0.01)
	_release_all()
	var game := gs.sudden_death_game as ParachuteGame
	var expected: Array = EXPECTED[scenario]
	check(game != null and game.winner == int(expected[0]) and game.decided_by == str(expected[1]),
		"P%d wins by %s (P%d by %s)" % [expected[0], expected[1], game.winner if game != null else 0, game.decided_by if game != null else ""])
	if int(expected[2]) > 0:
		check(game.question_index + 1 == int(expected[2]), "decided on question %d (%d)" % [expected[2], game.question_index + 1])
	if scenario == "final":
		check(game.final and finals >= 1 and shots_seen.has("c6_final"), "the final question in slow motion from the float (%s)" % str(shots_seen.keys()))
	else:
		check(shots_seen.has("c4_main"), "the main shot")
	# 真上から見下ろす高度の画は 2026-10-18 にやめた
	check(not shots_seen.has("c5_altitude"), "no top-down altitude shot (%s)" % str(shots_seen.keys()))


## parachute.md 7.1節（M2）：2人の体とパラシュートの一番上が、問題パネルの下と4択の上の間、画面の左右の端の内側に収まる。
func _check_framing(presenter: ParachutePresenter, label: String) -> void:
	var camera := get_viewport().get_camera_3d()
	var size := get_viewport().get_visible_rect().size
	var hud: Dictionary = _snap(presenter).hud
	var rects: Dictionary = hud.get("rects", {})
	# HUD の矩形は 1280×720 の基準の座標（テストの画面は同じ大きさ）
	var top_px := 96.0
	if rects.has("quiz"):
		top_px = (rects.quiz as Rect2).end.y
	var bottom_px := 620.0
	if rects.has("choice_0"):
		bottom_px = (rects.choice_0 as Rect2).position.y
	var fit: Dictionary = presenter.framing()
	var out: Array[String] = []
	for key: String in fit.points:
		var p: Vector3 = fit.points[key]
		if camera.is_position_behind(p):
			out.append("%s behind" % key)
			continue
		var at := camera.unproject_position(p)
		if at.y < top_px - 2.0 or at.y > bottom_px + 2.0 or at.x < 0.0 or at.x > size.x:
			out.append("%s %.0f,%.0f" % [key, at.x, at.y])
	_framing_log.append({"label": label, "out": out, "shot": str(_snap(presenter).shot), "predicted": _snap(presenter).get("fit", {}),
		"camera": [snappedf(camera.global_position.y, 0.01), snappedf(camera.fov, 0.1)]})
	check(out.is_empty(), "%s: bodies and chutes inside the frame between the question panel (%.0f px) and the choices (%.0f px) %s" % [label, top_px, bottom_px, str(out)])


var _framing_log: Array = []


## common.md 第12章：P1 は常に画面の左。
func _check_p1_left(presenter: ParachutePresenter, label: String) -> void:
	var camera := get_viewport().get_camera_3d()
	var actors: Dictionary = presenter.get("_actors")
	var x1 := camera.unproject_position((actors[1].root as Node3D).global_position).x
	var x2 := camera.unproject_position((actors[2].root as Node3D).global_position).x
	check(x1 < x2, "%s: P1 is on the left of the screen (%.0f / %.0f px, %s)" % [label, x1, x2, str(_snap(presenter).shot)])


## 着地のあと：勝者のパラシュートは肩から外れて床に落ちている（ライザーのつけ根が体にめり込まない）。
func _check_grounded(presenter: ParachutePresenter, winner: int) -> void:
	var canopy := presenter._canopies[winner] as ParachuteCanopy
	var floor_y := presenter._float.land_point().y
	var pelvis := presenter._actors[winner].parts.get("pelvis") as Node3D
	var snap := canopy.get_debug_snapshot()
	var gap := Vector2(canopy.global_position.x - pelvis.global_position.x, canopy.global_position.z - pelvis.global_position.z).length()
	check(bool(snap.grounded) and float(snap.weights.Grounded) > 0.99 and absf(canopy.global_position.y - floor_y) < 0.05 and gap > 0.3,
		"the winner's chute lies on the floor behind (y %.2f / floor %.2f, %.2f m from the body, %s)" % [canopy.global_position.y, floor_y, gap, str(snap.weights)])


func _finish(presenter: ParachutePresenter) -> void:
	var winner := (gs.sudden_death_game as ParachuteGame).winner
	check(await until(func() -> bool: return _snap(presenter).phase == "finish", 2.0), "the finish starts")
	await frames(int(fps * 0.9))
	capture("20_release")
	check(int((_snap(presenter).stages as Array)[winner - 1]) == 3, "the winner's chute is fully open")
	await until(func() -> bool: return _snap(presenter).shot == "c8_sea", 3.0)
	await frames(int(fps * 0.85))
	capture("21_splash")
	await frames(int(fps * 1.2))
	capture("22_descend")
	await until(func() -> bool: return _snap(presenter).shot == "c9_landing", 4.0)
	await frames(int(fps * 1.3))
	capture("23_landing")
	check(await until(func() -> bool: return director.act_name() == "EXTRACT", 4.0), "the dance and the pickup follow the landing")
	# 勝者のダンス
	var dance_from := director.act_time()
	var presses := DANCE_PRESSES if scenario == "dance" else []
	var done := {}
	var guard := 0.0
	while director.act_name() == "EXTRACT" and not bool(_snap(presenter).released) and guard < 12.0:
		var t := director.act_time() - dance_from
		for press: Array in presses:
			var key := int(press[1])
			if t >= float(press[0]) and not done.has(key):
				done[key] = true
				_key(key, true)
			if done.has(key) and t >= float(press[0]) + 0.25:
				_key(key, false)
		var slot := int(_snap(presenter).dance_slot)
		if _dance_slots.is_empty() or _dance_slots.back() != slot:
			_dance_slots.append(slot)
		if t >= 2.0:
			_capture_once("24_dance_a")
			if not _done_captures.has("emote_hud"):
				_done_captures["emote_hud"] = true
				check(float(_snap(presenter).hud.alpha.emote) > 0.9, "the emote keys are on screen while dancing")
				_check_grounded(presenter, winner)
		if t >= 4.6:
			_capture_once("25_dance_b")
		await get_tree().process_frame
		guard += 1.0 / float(fps)
	_release_all()
	if scenario == "dance":
		check(_dance_slots == [-1, 2, 1], "the keys pick the dances: none, 3, then 2 (%s)" % str(_dance_slots))
	else:
		check(_dance_slots == [-1, 0], "no key: the first dance after 2.5 s (%s)" % str(_dance_slots))
	check(bool(_snap(presenter).released), "the winner runs for the ladder after the dance")
	await frames(int(fps * 1.0))
	capture("26_pickup")


func _home() -> void:
	check(await until(func() -> bool: return director.act_name() == "HOME", 12.0), "back to the goal (%s)" % director.act_name())
	var sky := director.sky_set()
	check(sky != null and not sky.visible and is_equal_approx(sky.ocean.position.y, -SuddenDeathSkySet.FLY_HEIGHT), "the sky set is put away and its sea restored")
	await frames(int(fps * 3.0))
	capture("30_home")
	check(await until(func() -> bool: return director.act_name() == "DONE", 20.0), "the verdict resumes (%s)" % director.act_name())
	check(gs.result_winner == int(EXPECTED[scenario][0]), "the finale crowns the winner")
	check(await until(func() -> bool: return gs.game_state == Constants.STATE_CLEAR, 12.0), "controls after the celebration")
	check(gs.message_text.contains("サドンデスで P%d" % gs.sudden_death_winner), "result text (%s)" % gs.message_text)
	check(str(gs.sudden_death_record.get("game", "")) == "parachute", "recorded as the parachute game")
	capture("31_final")


# ------------------------------------------------------------------ helpers

func _key(code: Key, pressed: bool) -> void:
	if bool(_held.get(code, false)) == pressed:
		return
	_held[code] = pressed
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_answer_keys() -> void:
	for row: Array in ANSWER_KEYS:
		for code: Key in row:
			_key(code, false)


func _release_all() -> void:
	for code: Variant in _held.keys():
		_key(code, false)


func _capture_once(tag: String) -> void:
	if _done_captures.has(tag):
		return
	_done_captures[tag] = true
	capture(tag)


func capture(tag: String) -> void:
	captured.append(tag)
	get_viewport().get_texture().get_image().save_png(out + tag + ".png")


func _write_report() -> void:
	var report := {"case": scenario, "passed": failures.is_empty(), "checks": checks, "failures": failures,
		"winner": gs.sudden_death_winner, "decided_by": gs.sudden_death_decided_by, "record": gs.sudden_death_record,
		"events": events, "captures": captured, "shots": shots_seen, "reveal_push": _reveal_report, "framing": _framing_log, "shot_log": director.shot_log(), "dance_slots": _dance_slots,
		"director": director.get_debug_snapshot()}
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PARACHUTE_RUNTIME " + JSON.stringify({"case": scenario, "passed": report.passed, "checks": checks, "failures": failures,
		"winner": report.winner, "by": report.decided_by}))


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func until(predicate: Callable, seconds: float) -> bool:
	var limit := int(seconds * fps)
	for _frame in range(limit):
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()
