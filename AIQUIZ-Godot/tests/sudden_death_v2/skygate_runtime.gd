extends Node

## つきやぶれ！スカイゲートの通し（docs/sudden_death_v2/skygate_build_plan.md W6）。実際の GameWorld で引き分けを起こし、
## 種目発表 → 乗り込み（水上機）→ 機内 → 降下 → ルールカード → 本戦 → （ラウンドの迎え → 短い降下）→ 決着 → 勝者の迎え → 帰還
## → 決着演出に戻る、までを 1 フレームずつ進める。入力は本物のキー（Input.parse_input_event の WASD・矢印・Enter・Space）。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/skygate_runtime_bootstrap.gd -- case=p1
## case:
##   p1      ROUND 1 の 2 枚目で P2 がまちがえて P1 の勝ち
##   round2  ROUND 1 は 2 人とも正解 → 着地台 → 暗転 → 機内から短い降下 → 「ROUND 2」→ 3・2・1 → ROUND 2 の 1 枚目で P1 が
##           まちがえて P2 の勝ち
##   skip    乗り込みと降下を Space で飛ばす（そのあとは p1 と同じ）
##   skip_cruise  乗り込みと機内（巡航）を続けて Space で飛ばす（降下なしで本戦へ。そのあとは p1 と同じ）
##   abort   舞台の準備が失敗した（debug_load_fail）：乗り込みのあと機内から雲の覆いで台座へ戻り、引き分けのまま終わる
## 出力：artifacts/sudden_death_v2/skygate_runtime/<case>/（場面ごとの画と report.json）。
## 通しの動画を撮る（Godot の Movie Maker。quality・size は録画用で、ふだんは balanced・1280x720）：
##   Godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie <out>.avi --script res://tests/sudden_death_v2/skygate_runtime_bootstrap.gd -- case=p1 quality=high size=1920x1080

const OUT_ROOT := "res://artifacts/sudden_death_v2/skygate_runtime/"
const FRAME_LIMIT := 60 * 260
const MAX_SHOTS := 70

var case_name := "p1"
var ghost_mask := 0
var out := OUT_ROOT
## 出力先の親（音のテスト skygate_audio_runtime.gd が替える）と、場面ごとに画を撮るか
var out_root := OUT_ROOT
var take_shots := true
var gs: QuizGameState
var world: Node
var director: HeliSuddenDeathDirector
var helper: Node
var report := {"failures": [], "acts": [], "shots": [], "checks": {}}
var _keys := {}
var _last_act := ""
var _last_shot := ""
var _shot_count := 0
var _frame := 0
var _pending_shots: Array = []
var _skipped := {}
var _wrong_done := false
## ゲートごとのカメラの距離（2人の真ん中から）：{"r_g": {"hover": m, "push": m}}
var _gate_cams := {}
var _black_max := 0.0
var _round_countdown := {}


func _ready() -> void:
	call_deferred("run")


func fail(label: String) -> void:
	(report.failures as Array).append(label)
	push_error(label)


func run() -> void:
	# quality=・size=WxH は録画用（--write-movie で通しの動画を撮るとき。ふだんは balanced・1280x720）
	var quality := "balanced"
	var view_size := Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("case="):
			case_name = arg.trim_prefix("case=")
		elif arg.begins_with("ghosts="):
			# 1 = P1、2 = P2、3 = 2 人とも幽霊のまま引き分け（docs/sudden_death_v2/ghost_revive.md の復活から始まる）
			ghost_mask = clampi(int(arg.trim_prefix("ghosts=")), 0, 3)
		elif arg.begins_with("quality="):
			quality = arg.trim_prefix("quality=")
		elif arg.begins_with("size="):
			var wh := arg.trim_prefix("size=").split("x")
			if wh.size() == 2:
				view_size = Vector2i(int(wh[0]), int(wh[1]))
	out = out_root + case_name + ("_ghosts%d" % ghost_mask if ghost_mask != 0 else "") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	report["case"] = case_name
	GameManager.graphics_quality = quality
	get_tree().root.size = view_size
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	director = world.get("_sudden_death_director") as HeliSuddenDeathDirector
	director.use_real_time = false
	if case_name == "abort":
		director.debug_load_fail = true
	await _frames(60)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await _frames(15)
	world.call("_debug_force_draw_finish", ghost_mask)
	var guard := 0
	while not gs.result_presentation_active and guard < 600:
		guard += 1
		await get_tree().process_frame
	report.checks["kind"] = gs.sudden_death_kind
	report.checks["pending"] = gs.sudden_death_pending
	if gs.sudden_death_kind != "sky_gate" or not gs.sudden_death_pending:
		fail("the draw did not branch into the sky gate (kind %s, pending %s)" % [gs.sudden_death_kind, gs.sudden_death_pending])
		_finish()
		return
	var done_at := -1
	while _frame < FRAME_LIMIT:
		_frame += 1
		_drive_inputs()
		await get_tree().process_frame
		_watch()
		await _flush_shots()
		if director.act_name() == "DONE" and done_at < 0:
			done_at = _frame
		if done_at > 0 and _frame - done_at > 90:
			break
		if director.act_name() == "IDLE" and _frame > 600 and done_at < 0:
			fail("the director went back to IDLE before DONE (act log %s)" % str(report.acts))
			break
	_release_all()
	_check_end(done_at)
	_finish()


# ------------------------------------------------------------------ inputs

func _drive_inputs() -> void:
	# 自動のテストではウィンドウにフォーカスが無いことがある（GameWorld はフォーカスが無いと押しっぱなしを 0 にする）
	world.set("_push_focus_lost", false)
	var act := director.act_name()
	var presenter := director.presenter() as SkyGatePresenter
	# skip：乗り込みの 2 秒目と、降下の 0.8 秒目に Space
	if case_name == "skip":
		if act == "BOARD" and director.act_time() > 2.0 and not _skipped.has("board"):
			_skipped["board"] = director.act_time()
			_tap(KEY_SPACE)
		if act == "DROP" and director.act_time() > 0.8 and not _skipped.has("drop"):
			_skipped["drop"] = director.act_time()
			_tap(KEY_SPACE)
	# skip_cruise：乗り込みの 2 秒目と、機内の画（ぼけあり）に落ち着いた 1.2 秒目以降に飛ばせるようになったら Space
	if case_name == "skip_cruise":
		if act == "BOARD" and director.act_time() > 2.0 and not _skipped.has("board"):
			_skipped["board"] = director.act_time()
			_tap(KEY_SPACE)
		if act == "SKY" and director.act_time() > 1.2 and director.can_skip() and not _skipped.has("cruise"):
			_skipped["cruise"] = director.act_time()
			_tap(KEY_SPACE)
	# ルールカードは 1.0 秒見せて Enter
	if act == "VENUE" and presenter != null and presenter.phase_name() == "rules" and director.act_time() > 1.0 and not _skipped.has("rules"):
		_skipped["rules"] = true
		_tap(KEY_ENTER)
	var game := gs.sudden_death_game as SkyGateGame
	var moves := [Vector2.ZERO, Vector2.ZERO]
	if gs.game_state == Constants.STATE_SUDDEN_DEATH and game != null and game.phase == "gate":
		for player: int in [1, 2]:
			moves[player - 1] = _autopilot(game, player, _mode(game, player))
	_hold(KEY_D, moves[0].x > 0.3)
	_hold(KEY_A, moves[0].x < -0.3)
	_hold(KEY_W, moves[0].y > 0.3)
	_hold(KEY_S, moves[0].y < -0.3)
	_hold(KEY_RIGHT, moves[1].x > 0.3)
	_hold(KEY_LEFT, moves[1].x < -0.3)
	_hold(KEY_UP, moves[1].y > 0.3)
	_hold(KEY_DOWN, moves[1].y < -0.3)


## だれがどのゲートでまちがえるか。
func _mode(game: SkyGateGame, player: int) -> String:
	match case_name:
		"round2":
			if game.current_round >= 2 and player == 1:
				return "wrong"
		_:
			if game.current_round == 1 and game.gate_index >= 1 and player == 2:
				return "wrong"
	return "right"


## SkyGateDebug.autopilot_move と同じ：判断の間（1.2 秒）のあと、正解（まちがえるときは別）のパネルへ向かう。
func _autopilot(game: SkyGateGame, player: int, mode: String) -> Vector2:
	if game.gate_clock() < 1.2:
		return Vector2.ZERO
	var right := game.correct_choice()
	var panel := right if mode == "right" else (right + 3) % 4
	var side := Vector2(-0.7 if player == 1 else 0.7, 0.0) * game.board_scale()
	var target := SkyGateBoard.PANEL_CENTERS[panel] * game.board_scale() + Vector2(game.board_offset(), 0.0) + side
	var d := target - game.pos[player - 1]
	if d.length() < 0.35:
		return Vector2.ZERO
	return d.normalized()


func _hold(key: Key, on: bool) -> void:
	if bool(_keys.get(key, false)) == on:
		return
	_keys[key] = on
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = on
	Input.parse_input_event(event)


func _tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)


func _release_all() -> void:
	for key: Key in _keys.keys():
		_hold(key, false)


# ------------------------------------------------------------------ watching

func _watch() -> void:
	var act := director.act_name()
	if act != _last_act:
		(report.acts as Array).append([act, _frame, snappedf(float(_frame) / 60.0, 0.01)])
		_on_act(_last_act, act)
		_last_act = act
	# 画を撮らない通し（skygate_audio_runtime.gd）でも、ラウンドの間とゲートのカメラの確かめは行う（撮る予約だけを省く）
	if take_shots:
		var shot := director.shot_name()
		if shot != _last_shot and _shot_count < MAX_SHOTS:
			_last_shot = shot
			# 入ったところと、少しあと
			_pending_shots.append([_frame + 2, "%03d_%s_%s_a" % [_shot_count, act.to_lower(), shot]])
			_pending_shots.append([_frame + 40, "%03d_%s_%s_b" % [_shot_count, act.to_lower(), shot]])
			_shot_count += 1
		# 水上機の場面は、同じ画の中でも 0.75 秒ごとに撮る（動きを見る）
		if act in ["BOARD", "DROP", "HOME"] and _frame % 45 == 0 and _shot_count < MAX_SHOTS + 60:
			_pending_shots.append([_frame, "%03d_%s_%s_t%05d" % [_shot_count, act.to_lower(), shot, _frame]])
	_check_moments(act)
	_watch_round_turn(act)
	_watch_gate_camera()
	_watch_venue_focus(act)


## 本戦の間は水上機のカメラのぼけ（fp_lens.gd）が残らない：本戦へ渡って 1 秒（ぼけを薄める 0.8 秒のあと）からは
## 監督のカメラにぼけの設定が付いていないこと（Space で続けて飛ばしたあと、薄めては付け直すのを繰り返してピンぼけが続いていた）。
func _watch_venue_focus(act: String) -> void:
	if act != "VENUE" or director.act_time() < 1.0:
		return
	var cam := director.main_camera()
	if cam == null or cam.attributes == null:
		return
	var count := int(report.checks.get("venue_blur_frames", 0)) + 1
	report.checks["venue_blur_frames"] = count
	if count == 1:
		var attrs := cam.attributes as CameraAttributesPractical
		fail("the venue camera still has the lens attributes %.2f s into the game (frame %d, far %s, amount %.3f)" % [director.act_time(), _frame,
			str(attrs.dof_blur_far_enabled) if attrs != null else "-", attrs.dof_blur_amount if attrs != null else 0.0])


## ラウンドの間（2026-10-20）：着地のあと暗転して（迎えの水上機は来ない）機内から短い降下へ。ROUND 2 の頭にもカウントダウン。
func _watch_round_turn(act: String) -> void:
	var presenter := director.presenter() as SkyGatePresenter
	var game := gs.sudden_death_game as SkyGateGame
	# 暗転はラウンドの間（ルールが着地のまま）だけ数える（乗り込みの雲の中の暗転は別）
	var cover := director.get("_cover") as Node
	var black := cover.get("_black") as ColorRect if cover != null else null
	if black != null and black.visible and game != null and game.phase == "landing":
		_black_max = maxf(_black_max, black.color.a)
		if take_shots and black.color.a > 0.99 and not _round_countdown.has("black_shot"):
			_round_countdown["black_shot"] = _frame
			_pending_shots.append([_frame + 45, "round_black_after"])
	if act != "VENUE" or presenter == null or game == null:
		return
	var counting := presenter.phase_name() == "countdown" and game.phase == "landing"
	# 「GO!」はルールが次のラウンドを始めたフレームに出る（そのあとも HUD に残る）
	var key := "r%d" % (game.current_round + 1 if game.phase == "landing" else game.current_round)
	if counting or (_round_countdown.has(key) and game.phase == "gate" and game.gate_index == 0):
		if not _round_countdown.has(key):
			_round_countdown[key] = {"from_frame": _frame}
			if take_shots:
				_pending_shots.append([_frame + 20, "round%d_intro_banner" % (game.current_round + 1)])
				_pending_shots.append([_frame + int(60.0 * (SkyGatePresenter.ROUND_INTRO + 0.3)), "round%d_countdown_3" % (game.current_round + 1)])
		var hud := director.hud()
		var text := str(hud.get("_count_text")) if hud != null else ""
		if text != "":
			var seen: Dictionary = _round_countdown[key]
			if not seen.has(text):
				seen[text] = _frame


## 見下ろしのカメラ：ボードが読める近さ（ゲートの 2.0 秒）と、時間切れの直前の距離。終わりに寄っていること。
func _watch_gate_camera() -> void:
	var presenter := director.presenter() as SkyGatePresenter
	var game := gs.sudden_death_game as SkyGateGame
	var cam := director.main_camera()
	if presenter == null or game == null or cam == null or director.act_name() != "VENUE" or game.phase != "gate":
		return
	var mid: Vector3 = presenter.call("_players_mid")
	var dist := cam.global_position.distance_to(mid)
	var key := "r%d_g%d" % [game.current_round, game.gate_index]
	if not _gate_cams.has(key):
		_gate_cams[key] = {"hover": -1.0, "push": INF, "gate_time": game.gate_time}
	var row: Dictionary = _gate_cams[key]
	var clock := game.gate_clock()
	if float(row.hover) < 0.0 and clock >= 2.0:
		row.hover = snappedf(dist, 0.01)
		if take_shots and game.gate_index <= 1:
			_pending_shots.append([_frame, "gate_%s_hover" % key])
	if game.gate_time - clock <= 0.25:
		row.push = minf(float(row.push), snappedf(dist, 0.01))
		if take_shots and game.gate_index <= 1 and not row.has("shot"):
			row["shot"] = true
			_pending_shots.append([_frame, "gate_%s_push" % key])


func _on_act(previous: String, act: String) -> void:
	var snap := director.get_debug_snapshot()
	match act:
		"BOARD":
			var staging := director.floatplane_staging()
			if staging == null or staging.plane == null:
				fail("BOARD without the floatplane")
		"SKY":
			if previous != "BOARD":
				fail("SKY did not follow BOARD (%s)" % previous)
		"DROP":
			report.checks["drop_from_%s_%d" % [previous.to_lower(), _frame]] = snap.get("staging", {})
		"VENUE":
			if previous == "DROP":
				# 渡した瞬間：2人の人形が本戦の位置の近く（Space で飛ばしたときは見ない）
				var presenter := director.presenter()
				var gaps := []
				for player: int in [1, 2]:
					var puppet := director.puppet(player)
					var pelvis := puppet.parts().get("pelvis") as Node3D
					if pelvis != null and presenter != null:
						gaps.append(snappedf(pelvis.global_position.distance_to(presenter.sky_spawn(player).origin), 0.01))
				report.checks["handover_gap_%d" % _frame] = gaps
				if not _skipped.has("drop") or case_name != "skip":
					for gap: Variant in gaps:
						if float(gap) > 3.0:
							fail("the drop hands over %.2f m away from the game's spawn" % float(gap))


## 場面ごとに確かめる数字。
func _check_moments(act: String) -> void:
	var staging := director.floatplane_staging()
	if staging == null:
		return
	if act == "BOARD" and staging.lift != null and staging.lift.lower >= 0.999 and not report.checks.has("board_link"):
		var edge := staging.plane.global_transform * Vector3(0.0, FloatplaneStaging.CABIN_FLOOR, FloatplaneStaging.EDGE_Z)
		var deck := staging.lift.deck_point(1.0)
		report.checks["board_link"] = {"edge": [snappedf(edge.x, 0.01), snappedf(edge.y, 0.01)], "deck": [snappedf(deck.x, 0.01), snappedf(deck.y, 0.01)]}
		if absf(edge.y - deck.y) > 0.2 or deck.x < edge.x - 0.5:
			fail("the lift does not meet the ramp edge in the boarding (deck %s, edge %s)" % [str(deck), str(edge)])
	if act == "EXTRACT" and staging.plane != null and director.presenter() != null and not report.checks.has("pickup_ramp") and staging.plane.ramp_t >= SuddenDeathFloatplane.RAMP_GROUND - 0.01:
		var landing := director.presenter().landing_float()
		var edge := staging.plane.ramp_edge_now()
		var center := landing.global_position
		var r := Vector2(edge.x - center.x, edge.z - center.z).length()
		report.checks["pickup_ramp"] = {"edge_r": snappedf(r, 0.01), "edge_above_sea": snappedf(edge.y - landing.sea_y, 0.01)}
		if r > 4.1 or r < 3.0 or absf(edge.y - landing.sea_y - 0.8) > 0.25:
			fail("the ramp edge does not rest on the float tube (r %.2f, above sea %.2f)" % [r, edge.y - landing.sea_y])


func _flush_shots() -> void:
	var keep: Array = []
	for row: Array in _pending_shots:
		if _frame >= int(row[0]):
			await RenderingServer.frame_post_draw
			var path := out + String(row[1]) + ".png"
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			(report.shots as Array).append(path)
		else:
			keep.append(row)
	_pending_shots = keep


func _check_end(done_at: int) -> void:
	var names: Array[String] = []
	for row: Array in report.acts:
		names.append(String(row[0]))
	report.checks["acts"] = names
	var expected: Array[String] = ["BRANCH", "REVEAL", "BOARD", "SKY", "DROP", "VENUE", "EXTRACT", "HOME", "DONE"]
	if case_name == "abort":
		expected = ["BRANCH", "REVEAL", "BOARD", "SKY", "ABORT", "DONE"]
	elif case_name == "skip_cruise":
		expected = ["BRANCH", "REVEAL", "BOARD", "SKY", "VENUE", "EXTRACT", "HOME", "DONE"]
	elif case_name == "round2":
		expected = ["BRANCH", "REVEAL", "BOARD", "SKY", "DROP", "VENUE", "DROP", "VENUE", "EXTRACT", "HOME", "DONE"]
	if ghost_mask != 0:
		expected.insert(1, "REVIVE")
		_check_revived_looks()
	var at := 0
	for name: String in names:
		if at < expected.size() and name == expected[at]:
			at += 1
	if at < expected.size():
		fail("the acts did not run in order (expected %s, got %s)" % [str(expected), str(names)])
	if done_at < 0:
		fail("the sudden death did not finish within %d frames (act %s)" % [FRAME_LIMIT, director.act_name()])
	var winner := 2 if case_name == "round2" else 1
	if case_name == "abort":
		winner = 0
	report.checks["result_winner"] = gs.result_winner
	if gs.result_winner != winner:
		fail("the winner is P%d, expected P%d" % [gs.result_winner, winner])
	report.checks["state"] = gs.game_state
	report.checks["gate_camera"] = _gate_cams
	for key: String in _gate_cams.keys():
		var row: Dictionary = _gate_cams[key]
		# 2人が離れたパネルにいると、2人を収める距離で止まる（寄るが 8 割より遠いことがある）
		if float(row.hover) > 0.0 and is_finite(float(row.push)) and float(row.push) > float(row.hover) * 0.95:
			fail("the top-down lens does not close in at the end of gate %s (%.2f m -> %.2f m)" % [key, float(row.hover), float(row.push)])
	if case_name == "round2":
		report.checks["round_black_max"] = snappedf(_black_max, 0.001)
		report.checks["round_countdown"] = _round_countdown
		if _black_max < 0.99:
			fail("the landing did not fade to black before the next drop (max %.2f)" % _black_max)
		var r2: Dictionary = _round_countdown.get("r2", {})
		for text: String in ["3", "2", "1", "GO!"]:
			if not r2.has(text):
				fail("ROUND 2 did not count down (%s missing, seen %s)" % [text, str(r2)])
	if case_name == "skip":
		report.checks["skipped"] = _skipped
		var board_frames := _act_frames("BOARD")
		if board_frames > 60 * 5:
			fail("Space did not skip the boarding (%d frames)" % board_frames)


## Back on the podium: a ghost whose body came back stays solid; the sudden death's loser comes home a ghost.
func _check_revived_looks() -> void:
	var ceremony := world.get("_result_ceremony_director") as ResultCeremonyDirector
	var stage := ceremony.stage() if ceremony != null else null
	if stage == null or not stage.is_built():
		fail("no finale stage after the return")
		return
	var looks := {}
	for player: int in [1, 2]:
		var ghost_parts := 0
		for node: Node in (stage.actor_parts(player).get("pelvis") as Node3D).find_children("*", "MeshInstance3D", true, false):
			if PlayerController.is_ghost_soul_look(node as MeshInstance3D):
				ghost_parts += 1
		looks[player] = ghost_parts
		var lost := gs.sudden_death_winner in [1, 2] and player != gs.sudden_death_winner
		if lost and ghost_parts == 0:
			fail("P%d lost the sudden death but is not a ghost on the podium" % player)
		if not lost and ghost_parts > 0:
			fail("P%d got its body back but stands on the podium as a ghost (%d parts)" % [player, ghost_parts])
	report.checks["finale_ghost_parts"] = looks
	report.checks["revived_mask"] = gs.sudden_death_revived_mask


func _act_frames(name: String) -> int:
	var rows: Array = report.acts
	for i in range(rows.size() - 1):
		if String(rows[i][0]) == name:
			return int(rows[i + 1][1]) - int(rows[i][1])
	return -1


func _finish() -> void:
	report["frames"] = _frame
	report["director"] = director.get_debug_snapshot() if director != null else {}
	var f := FileAccess.open(out + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("SKYGATE_RUNTIME ", JSON.stringify({"case": case_name, "failures": report.failures, "acts": report.checks.get("acts", []),
		"frames": _frame, "winner": report.checks.get("result_winner", 0)}))
	get_tree().quit(0 if (report.failures as Array).is_empty() else 1)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
