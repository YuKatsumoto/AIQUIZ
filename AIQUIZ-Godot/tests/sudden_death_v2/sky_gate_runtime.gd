extends Node

## 「つきやぶれ！スカイゲート」の見せ方を実画面で通して確かめる（監督なしのデバッグの入口 SkyGateDebug を 1 フレームずつ進める）。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/sudden_death_v2/sky_gate_runtime_bootstrap.gd -- [case=main|small] [quality=low]
## case=main：4 枚の列の引き（G4_Column）→ 図解ルールカード（ゲーム内の実演）→ ROUND 1 を2人とも突破（当たる → 止まらずに紙を
##   破って抜ける → すぐ次のボード）→ 着地台（切らずに降りる）→ ROUND 2（ボードが動く）→ 2 枚目で P2 がまちがえる（画は見下ろしの
##   まま、強いスローと色抜けで、破れずにはね返されて爆散 → 判定）→ 勝者の急降下と着地・ダンス。
## case=small：ROUND 3 から（ボードが小さい）。1 枚目で2人ともまちがえて、スローの中ではね返されて爆散 → その場で復活。
## どちらも毎フレーム、カメラ・人形・近くのボードが飛んでいない（瞬間移動していない）かを測る（skygate_impact.md 第6章）。
## 画は artifacts/sudden_death_v2/sky_gate_play/<case>_*.png、結果は標準出力の SKY_GATE_RUNTIME {...}。

const OUT_DIR := "res://artifacts/sudden_death_v2/sky_gate_play/"
const DT := 1.0 / 60.0
## 1 フレーム（60fps）で許す動き：カメラの位置（m）・向き（度）、見えている人形の腰（m）、近くのボードの位置（m）。
const CAM_STEP_MAX := 2.0
const CAM_TURN_MAX := 8.0
const BODY_STEP_MAX := 1.2
const BOARD_STEP_MAX := 4.0
## 近くのボード（2人からこの距離の中）が急に出たり消えたりしない。
const BOARD_POP_RANGE := 45.0

var case_name := "main"
var quality := "low"
var debug: SkyGateDebug
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var shot_names := {}
var left_ok := 0
var left_bad := 0
var events_seen: Array[String] = []
## つながりの測定（skip_continuity の間は測らない：デバッグの入口がラウンドの間に空へ戻す所）
var cam_step := 0.0
var cam_turn := 0.0
var body_step := 0.0
var board_step := 0.0
var board_pops: Array[String] = []
var worst := {}
var skip_continuity := false
## もとの寄りの画（g6_death）への切り替えの回数（2026-10-25 から切り替えないので 0 のまま）。
var death_cuts := 0
## 脱落のスローの間に測った一番遅い見せ方の時計の速さ・一番強い色抜け・一番低い彩度。
var slowest := 1.0
var most_wasted := 0.0
var lowest_saturation := INF
var _last_shot := ""
var _last_cam := Transform3D.IDENTITY
var _has_cam := false
var _last_body := {}
var _last_board := {}
## 時間切れの動きの記録（player -> 一番高く上がった高さ・最後の高さ）
var impact_rise := {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair[0] == "case" and pair.size() > 1:
			case_name = pair[1]
		elif pair[0] == "quality" and pair.size() > 1:
			quality = pair[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _run() -> void:
	debug = SkyGateDebug.new()
	debug.manual = true
	debug.quality = quality
	debug.autopilot = {1: "right", 2: "right"}
	add_child(debug)
	debug.build()
	await _frames(3)
	if debug.game == null or debug.presenter == null or not debug.presenter.get_debug_snapshot().get("built", false):
		check(false, "the debug scene did not build (script errors?)")
		print("SKY_GATE_RUNTIME ", JSON.stringify({"case": case_name, "checks": checks, "failures": failures}))
		get_tree().quit(1)
		return
	match case_name:
		"small", "both":
			await _case_small()
		_:
			await _case_main()
	check(cam_step <= CAM_STEP_MAX, "camera never jumps (largest step %.2f m at %s)" % [cam_step, str(worst.get("cam", ""))])
	check(cam_turn <= CAM_TURN_MAX, "camera never snaps round (largest turn %.1f deg at %s)" % [cam_turn, str(worst.get("turn", ""))])
	check(body_step <= BODY_STEP_MAX, "players never teleport (largest step %.2f m at %s)" % [body_step, str(worst.get("body", ""))])
	check(board_step <= BOARD_STEP_MAX, "near boards never jump (largest step %.2f m at %s)" % [board_step, str(worst.get("board", ""))])
	check(board_pops.is_empty(), "no board pops in or out near the players: %s" % str(board_pops))
	print("SKY_GATE_RUNTIME ", JSON.stringify({"case": case_name, "checks": checks, "failures": failures, "shots": shots, "death_cuts": death_cuts,
		"shot_names": shot_names.keys(), "left_ok": left_ok, "left_bad": left_bad, "events": events_seen,
		"cam_step": snappedf(cam_step, 0.01), "cam_turn": snappedf(cam_turn, 0.1), "body_step": snappedf(body_step, 0.01),
		"board_step": snappedf(board_step, 0.01), "worst": worst, "impact_rise": impact_rise, "slowest": snappedf(slowest, 0.01),
		"most_wasted": snappedf(most_wasted, 0.01), "lowest_saturation": snappedf(lowest_saturation, 0.01)}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ cases

func _case_main() -> void:
	var game := debug.game
	var presenter := debug.presenter
	# 4 枚の列の引き（ルールカードの前）
	await _advance_until(func() -> bool: return debug.clock > 0.8, 120)
	await _shot("main_00_column")
	check(presenter.get_debug_snapshot().shot == "g4_column", "opens on the column overview: %s" % presenter.get_debug_snapshot().shot)
	check(not bool(presenter.hud().state.get("rules", false)), "the rule card waits while the column is shown")
	var rows := _column_rows()
	check(rows.size() == 4, "4 boards hang in the column from the start (%d)" % rows.size())
	var texts_ok := true
	for k in range(rows.size()):
		var row: Dictionary = rows[k]
		texts_ok = texts_ok and int(row.k) == k and bool(row.visible) and str(row.q) == game.column_quiz(k).q
	check(texts_ok, "every board already shows its question: %s" % str(rows))
	await _advance_until(func() -> bool: return debug.clock > SkyGatePresenter.RULES_DELAY + SkyGatePresenter.RULE_HOLD + 0.1, 120)
	await _shot("main_01_rules")
	check(presenter.phase_name() == "rules", "starts on the rule card")
	check(bool(presenter.hud().state.get("rules", false)), "rule card is on the HUD")
	var demos := presenter.rule_demos()
	check(demos.size() == 3, "three in-game demos for the rule card")
	for demo: SkyGateRuleDemo in demos:
		check(demo.is_playing(), "demo %s plays while the card is up" % demo.kind)
	await _shot_demos("main_01b_demo")
	check(presenter.confirm_rules(), "Enter closes the card")
	await _advance_until(func() -> bool: return float(presenter.get("_t")) - float(presenter.get("_count_at")) >= SkyGatePresenter.COUNT_STEP * 1.6, 120)
	await _shot("main_01c_countdown_blend")
	await _advance_until(func() -> bool: return game.is_running() and game.phase == "gate", 300)
	check(game.current_round == 1 and game.gate_index == 0, "ROUND 1 gate 1 after the countdown")
	check(presenter.get_debug_snapshot().shot == "g2_topdown", "top-down by GO")
	for demo: SkyGateRuleDemo in demos:
		check(not demo.is_playing(), "demo %s stops after the card" % demo.kind)
	# ゲート 1：列が上がってくる → 読める → 近い → 当たる（時間制限は無い）
	await _advance_until(func() -> bool: return game.gate_clock() >= 2.6, 300)
	await _shot("main_02_gate_read")
	_check_lean_hud(true)
	await _advance_until(func() -> bool: return game.time_to_contact() <= 0.8, 600)
	await _shot("main_03_gate_near")
	await _advance_until(func() -> bool: return game.phase == "impact", 200)
	check(not game.finished and game.passes == [0, 0], "contact: no verdict yet")
	await _advance_impact_to(0.08)
	await _shot("main_04_press")
	check(presenter.get_debug_snapshot().shot == "g2_topdown", "everyone breaks through: the camera stays top-down")
	check(float(presenter.get_debug_snapshot().slow) > 0.99, "no slow-mo when everyone breaks through")
	await _advance_impact_to(0.28)
	await _shot("main_05_through")
	var fading := false
	var board_rows: Array = presenter.get_debug_snapshot().boards
	for i in range(board_rows.size()):
		if str(board_rows[i].role) == "hit" and int(board_rows[i].k) == 0:
			fading = presenter.boards()[i].fade() < 0.99
	check(fading, "the passed board fades as it goes up past them")
	await _advance_until(func() -> bool: return game.phase == "gate" and game.gate_index == 1, 200)
	check(game.passes == [1, 1], "both broke through the first board")
	await _advance_frames(20)
	await _shot("main_07_next_gate")
	_check_lean_hud(false)
	# 残りのゲート → 着地台（切らずに）
	await _advance_until(func() -> bool: return presenter.phase_name() == "round_land", 60 * 40)
	check(game.phase == "landing" and game.current_round == 1, "round 1 cleared")
	await _advance_frames(20)
	await _shot("main_08_round_release")
	await _advance_until(func() -> bool: return presenter.get_debug_snapshot().shot == "g5_follow", 300)
	await _advance_frames(40)
	await _shot("main_09_round_descend")
	await _advance_until(func() -> bool: return presenter.get_debug_snapshot().shot == "g5_landing", 600)
	await _advance_frames(30)
	await _shot("main_10_round_landing")
	await _advance_until(func() -> bool: return presenter.phase_name() == "round_wait", 600)
	await _shot("main_11_round2_banner")
	check(presenter.round_cleared(), "round_cleared() after the ROUND 2 banner")
	var spawn1 := presenter.sky_spawn(1)
	var spawn2 := presenter.sky_spawn(2)
	check(spawn1.origin.x > spawn2.origin.x, "sky_spawn: P1 is on +X (screen left)")
	# ROUND 2（デバッグの入口は水上機の迎えと降下を飛ばしてすぐ空へ戻す：ここは測らない）
	skip_continuity = true
	await _advance_until(func() -> bool: return game.current_round == 2 and game.phase == "gate", 300)
	await _advance_frames(3)
	skip_continuity = false
	_forget_tracks()
	check(is_equal_approx(game.fall_speed, 10.0), "ROUND 2 column rises 10 m/s")
	await _advance_until(func() -> bool: return game.gate_clock() >= 3.0, 300)
	await _shot("main_12_round2_moving")
	await _advance_until(func() -> bool: return game.gate_index == 1 and game.phase == "gate", 60 * 12)
	debug.autopilot[2] = "wrong"
	await _advance_until(func() -> bool: return game.phase == "impact", 60 * 12)
	check(not game.finished, "P2 on the wrong panel: no verdict at the contact")
	impact_rise.clear()
	await _advance_impact_to(0.3)
	await _shot("main_13_stretch")
	_check_wasted("P2 hits the wrong panel")
	await _advance_impact_to(0.7)
	await _shot("main_14_bounce")
	await _advance_impact_to(1.0)
	await _shot("main_15_boom")
	check(presenter.get_debug_snapshot().shot == "g2_topdown", "still the top-down shot at the explosion")
	check(bool((presenter.get_debug_snapshot().hidden as Dictionary)[2]), "P2 blew apart after bouncing")
	check(float(impact_rise.get(2, 0.0)) > 2.5, "P2 was thrown back up before the boom (%.2f m)" % float(impact_rise.get(2, 0.0)))
	check(float(impact_rise.get(1, 0.0)) < 0.2, "P1 broke through without bouncing (%.2f m)" % float(impact_rise.get(1, 0.0)))
	check(not game.finished, "still no verdict while the boom plays")
	await _advance_until(func() -> bool: return game.finished, 120)
	check(game.winner == 1 and game.decided_by == "out", "P2 booms → P1 wins by out")
	check(float(presenter.get_debug_snapshot().wasted) < 0.01, "the colour is back by the verdict")
	check(absf(presenter.environment().adjustment_saturation - 1.0) < 0.05, "saturation restored (%.2f)" % presenter.environment().adjustment_saturation)
	await _advance_frames(10)
	await _shot("main_16_verdict_out")
	var left_boards := 0
	for row: Dictionary in presenter.get_debug_snapshot().boards:
		if str(row.role) == "column":
			left_boards += 1
	check(left_boards == 0, "the rest of the column goes away after the decision (%d left)" % left_boards)
	await _advance_until(func() -> bool: return presenter.get_debug_snapshot().shot == "g5_follow", 400)
	await _advance_frames(30)
	await _shot("main_17_winner_dive")
	await _advance_until(func() -> bool: return presenter.finale_done(), 60 * 15)
	await _shot("main_18_winner_landed")
	check(bool(presenter.get_debug_snapshot().ghost), "the loser became a ghost")
	await _advance_frames(60 * 4)
	await _shot("main_19_dance")
	check(int(presenter.get_debug_snapshot().dance_slot) >= 0, "the winner dances")
	for name: String in ["g4_column", "g2_topdown", "g5_follow", "g5_landing"]:
		check(shot_names.has(name), "shot %s was used" % name)
	for old: String in ["g3_below", "g3_above", "g3_impact", "g4_chain", "g5_sea", "g5_release", "g6_death"]:
		check(not shot_names.has(old), "the old shot %s is gone" % old)
	check(death_cuts == 0, "no cut to a close shot on the boom: %d" % death_cuts)
	check(slowest < SkyGateImpact.WASTED_SLOW + 0.05 and most_wasted > 0.95, "GTA-like slow-mo and colour drain (%.2f, %.2f)" % [slowest, most_wasted])
	check(left_bad == 0 and left_ok > 100, "P1 is on the screen left in the top-down shot (%d ok, %d bad)" % [left_ok, left_bad])


func _case_small() -> void:
	var game := debug.game
	var presenter := debug.presenter
	debug.start_round = 3
	debug.auto_confirm = true
	skip_continuity = true
	await _advance_until(func() -> bool: return game.current_round == 3 and game.phase == "gate", 600)
	await _advance_frames(3)
	skip_continuity = false
	_forget_tracks()
	check(game.board_size() == SkyGateGame.SMALL_BOARD_SIZE, "ROUND 3 board is small")
	debug.autopilot = {1: "wrong", 2: "wrong"}
	await _advance_until(func() -> bool: return game.gate_clock() >= 3.2, 300)
	await _shot("small_01_gate")
	await _advance_until(func() -> bool: return game.phase == "impact", 600)
	impact_rise.clear()
	await _advance_impact_to(0.32)
	await _shot("small_02_both_stretch")
	_check_wasted("both hit wrong panels")
	await _advance_impact_to(0.95)
	await _shot("small_03_both_boom")
	check(float(impact_rise.get(1, 0.0)) > 2.5 and float(impact_rise.get(2, 0.0)) > 2.5, "both thrown back up: %s" % str(impact_rise))
	await _advance_until(func() -> bool: return game.phase == "both_out", 200)
	check(not game.finished, "both out: nobody wins")
	debug.autopilot = {1: "right", 2: "right"}
	await _advance_until(func() -> bool: return game.phase == "gate", 120)
	check(events_seen.has("revive"), "revive arrived")
	await _advance_frames(20)
	await _shot("small_04_revived")
	var snap := presenter.get_debug_snapshot()
	check(not bool((snap.hidden as Dictionary)[1]) and not bool((snap.hidden as Dictionary)[2]), "both are back")
	check(float(snap.wasted) < 0.01, "the colour is back after the revive")
	check(death_cuts == 0 and not shot_names.has("g6_death"), "no cut to a close shot when both boom")


# ------------------------------------------------------------------ helpers

func _step() -> void:
	debug.step_frame(DT)
	var snap := debug.presenter.get_debug_snapshot()
	var shot := str(snap.get("shot", ""))
	if shot != "":
		shot_names[shot] = true
	_track_events()
	if shot == "g2_topdown":
		_check_left()
	_track_continuity(snap)
	_track_rise()
	if debug.game.phase == "impact":
		slowest = minf(slowest, float(snap.get("slow", 1.0)))
		most_wasted = maxf(most_wasted, float(snap.get("wasted", 0.0)))
		lowest_saturation = minf(lowest_saturation, debug.presenter.environment().adjustment_saturation)


func _track_events() -> void:
	var game := debug.game
	var tag := "%s|%d|%d" % [game.phase, game.current_round, game.gate_index]
	if events_seen.is_empty() or events_seen[-1] != tag:
		events_seen.append(tag)
	if game.phase == "gate" and events_seen.size() > 1 and events_seen[-2].begins_with("both_out"):
		events_seen.append("revive")


## 1 フレームのあいだに、カメラ・見えている人形の腰・2人の近くのボードがどれだけ動いたか（一番大きい値を覚える）。
func _track_continuity(snap: Dictionary) -> void:
	var where := "%s/%s/%.2f" % [str(snap.get("phase", "")), str(snap.get("shot", "")), float(snap.get("t", 0.0))]
	if skip_continuity:
		_forget_tracks()
		return
	var cam := debug.camera.global_transform
	var shot := str(snap.get("shot", ""))
	if shot == "g6_death" and _last_shot != "g6_death":
		death_cuts += 1
	_last_shot = shot
	if _has_cam:
		var step := cam.origin.distance_to(_last_cam.origin)
		var turn := rad_to_deg(acos(clampf(cam.basis.z.normalized().dot(_last_cam.basis.z.normalized()), -1.0, 1.0)))
		if step > cam_step:
			cam_step = step
			worst["cam"] = where
		if turn > cam_turn:
			cam_turn = turn
			worst["turn"] = where
	_last_cam = cam
	_has_cam = true
	var presenter := debug.presenter
	var actors: Dictionary = presenter.get("_actors")
	var mid := Vector3.ZERO
	for player: int in [1, 2]:
		var parts: Dictionary = (actors.get(player, {}) as Dictionary).get("parts", {})
		var pelvis := parts.get("pelvis") as Node3D
		var shown := pelvis != null and pelvis.is_visible_in_tree()
		if shown:
			var at := pelvis.global_position
			mid += at * 0.5
			if _last_body.has(player):
				var step := at.distance_to(_last_body[player])
				if step > body_step:
					body_step = step
					worst["body"] = "P%d %s" % [player, where]
			_last_body[player] = at
		else:
			_last_body.erase(player)
			mid += presenter.call("_body_center", player) * 0.5
	var boards := presenter.boards()
	for i in range(boards.size()):
		var board := boards[i]
		var near := board.global_position.distance_to(mid) < BOARD_POP_RANGE
		var was: Dictionary = _last_board.get(i, {})
		# だんだん透明になって消えたボード（fade がほぼ 0）は、見えなくなっても「消えた」ではない
		var shown := board.visible and board.fade() > 0.03
		if shown:
			if not was.is_empty() and bool(was.visible) and near:
				var step := board.global_position.distance_to(was.at)
				if step > board_step:
					board_step = step
					worst["board"] = "%d %s" % [i, where]
			elif not was.is_empty() and not bool(was.visible) and near:
				board_pops.append("in %d %s" % [i, where])
		elif not was.is_empty() and bool(was.visible) and float(was.fade) > 0.15 and (was.at as Vector3).distance_to(mid) < BOARD_POP_RANGE:
			# 透明になりきる前に消えた
			board_pops.append("out %d %s" % [i, where])
		_last_board[i] = {"visible": shown, "at": board.global_position, "fade": board.fade()}


func _forget_tracks() -> void:
	_has_cam = false
	_last_body.clear()
	_last_board.clear()


## 当たったあと、2人の体がどこまで上がったか（落ちる点から）。
func _track_rise() -> void:
	if debug.game.phase != "impact":
		return
	var lifts: Array = debug.presenter.get("_lift")
	for player: int in [1, 2]:
		impact_rise[player] = maxf(float(impact_rise.get(player, -INF)), float(lifts[player - 1]))


## 列のボード（まだ当たっていない）の行：{"k", "d", "visible", "q"}（k の順）。
func _column_rows() -> Array:
	var rows := []
	for row: Dictionary in debug.presenter.get_debug_snapshot().boards:
		if str(row.role) == "column":
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.k) < int(b.k))
	return rows


## 削ぎ落とした HUD：端の札・残りの帯・小さな知らせは無い。ROUND の札は出ている。キーのヒントは ROUND 1 の 1 枚目だけ。
func _check_lean_hud(keys: bool) -> void:
	var hud_state: Dictionary = debug.presenter.hud().state
	check(not hud_state.has("players") and not hud_state.has("notice"), "no player tags or notices on the HUD: %s" % str(hud_state.keys()))
	var round_state: Dictionary = hud_state.get("round", {})
	check(bool(round_state.get("visible", false)) and not round_state.has("timer"), "the small ROUND badge without a timer")
	check(bool(hud_state.get("keys", false)) == keys, "key hint %s" % ("shown on the first board" if keys else "gone after the first board"))


## 脱落：画は切り替えず、強いスローと色抜け（見せ方の時計・本戦の環境の彩度・HUD の暗がり）。
func _check_wasted(label: String) -> void:
	var snap := debug.presenter.get_debug_snapshot()
	check(str(snap.shot) == "g2_topdown", "%s: the camera stays top-down (%s)" % [label, str(snap.shot)])
	check(float(snap.slow) < SkyGateImpact.WASTED_SLOW + 0.05, "%s: slow-mo (%.2f)" % [label, float(snap.slow)])
	check(float(snap.wasted) > 0.9, "%s: the colour drains (%.2f)" % [label, float(snap.wasted)])
	check(debug.presenter.environment().adjustment_saturation < 0.3, "%s: low saturation (%.2f)" % [label, debug.presenter.environment().adjustment_saturation])
	check(float((snap.hud as Dictionary).get("wasted", 0.0)) > 0.9, "%s: the HUD darkens the edges" % label)


func _check_left() -> void:
	var camera := debug.camera
	var p1 := camera.unproject_position(debug.presenter.call("_body_center", 1))
	var p2 := camera.unproject_position(debug.presenter.call("_body_center", 2))
	var game := debug.game
	# 2人が入れ替わっていない（P1 がボードの左にいる）ときだけ数える
	if game.pos[0].x < game.pos[1].x - 0.3:
		if p1.x < p2.x:
			left_ok += 1
		else:
			left_bad += 1


## 当たってから seconds 秒のところまで進める（見せ方の時計。スローの間は遅く進む）。
func _advance_impact_to(seconds: float) -> void:
	var presenter := debug.presenter
	await _advance_until(func() -> bool: return float(presenter.get("_scene_t")) - float(presenter.get("_impact_at")) >= seconds, 240)


func _advance_until(cond: Callable, limit: int) -> void:
	var n := 0
	while not cond.call() and n < limit:
		_step()
		n += 1
		if n % 4 == 0:
			await get_tree().process_frame
	await get_tree().process_frame


func _advance_frames(count: int) -> void:
	for i in range(count):
		_step()
		if i % 4 == 0:
			await get_tree().process_frame
	await get_tree().process_frame


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + shot_name + ".png"
	img.save_png(path)
	shots.append(shot_name)


## 図解ルールカードの 3 つの実演を、それぞれ見どころの時刻で撮る（カードの絵の中身）。
func _shot_demos(prefix: String) -> void:
	var times := {"steer": 2.6, "burst": 1.4, "bounce": 1.22}
	for demo: SkyGateRuleDemo in debug.presenter.rule_demos():
		demo.debug_freeze = true
		demo.debug_seek(float(times.get(demo.kind, 1.0)))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := demo.get_texture().get_image()
		img.save_png(OUT_DIR + "%s_%s.png" % [prefix, demo.kind])
		shots.append("%s_%s" % [prefix, demo.kind])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var card := get_viewport().get_texture().get_image()
	card.save_png(OUT_DIR + prefix + "_card.png")
	shots.append(prefix + "_card")
	for demo: SkyGateRuleDemo in debug.presenter.rule_demos():
		demo.debug_freeze = false
