extends Node

## Milestone 2 of docs/sudden_death_underground.md, the parts around the sudden death:
##   settings  GameManager.sudden_death_enabled persists in the settings file and reaches
##             the long-lived QuizGameState; the main menu's settings row sits under the
##             graphics quality row and switches it.
##   reel      MatchReel records while underground, marks the deciding moment above the
##             win, and stores {rows, by, winner} in the record; older records still read.
##   led       The programme names the moment and shows "SUDDEN DEATH" in the last match
##             panel and the history rows.
##   board     The goal stand scoreboard flashes "SUDDEN DEATH!" once the draw branches
##             (8.6 s) and while the sudden death runs, then the winner's cut-in carries
##             a "SUDDEN DEATH" tag.
##   crowd     Back from the sudden death the crowd reacts afresh (boards, eggs, cheer and
##             boo), and no egg flies before the director's egg target exists.
## Storage goes to user://test_sudden_death_settings_reel/ (never the player's own files).
## Results: res://artifacts/sudden_death/settings_reel/ (report.json, PNGs).
## Run: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/sudden_death_settings_reel_bootstrap.gd

const OUT := "res://artifacts/sudden_death/settings_reel/"
const STORE := "user://test_sudden_death_settings_reel"


## Stands in for ResultCeremonyDirector: the ceremony clock and the crowd's egg target.
class FakeDirector extends Node:
	var elapsed := 0.0
	var target: Node3D = null

	func result_elapsed() -> float:
		return elapsed

	func crowd_egg_target() -> Node3D:
		return target if is_instance_valid(target) else null


var checks: Dictionary = {}
var failures: Array[String] = []
var report: Dictionary = {}


func _ready() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks[label] = {"pass": ok, "detail": str(detail)}
	if not ok:
		failures.append("%s: %s" % [label, str(detail)])
		push_error("%s: %s" % [label, str(detail)])


func run() -> void:
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	var out_path := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out_path)
	for file_name: String in DirAccess.get_files_at(out_path):
		DirAccess.remove_absolute(out_path + "/" + file_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE))
	MatchHistory.path_override = STORE + "/match_history.json"
	HighlightStore.dir_override = STORE + "/highlights"
	MatchHistory.clear()
	HighlightStore.clear()
	var real_settings := GameManager.settings_path
	GameManager.settings_path = STORE + "/settings.json"
	_check_settings()
	await _check_menu_row()
	GameManager.settings_path = real_settings
	GameManager._load_user_settings()
	await _check_reel()
	await _check_led()
	await _check_board()
	await _check_crowd()
	finish()


# ------------------------------------------------------------------ settings

func _read_settings_file() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameManager.settings_path))
	return parsed if parsed is Dictionary else {}


func _check_settings() -> void:
	if FileAccess.file_exists(GameManager.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameManager.settings_path))
	GameManager._load_user_settings()
	check("settings: on by default (no file)", GameManager.sudden_death_enabled == true)
	var state: QuizGameState = QuizManager.game_state
	check("settings: the quiz state starts on", state != null and state.sudden_death_enabled)
	GameManager.set_sudden_death_enabled(false)
	check("settings: off reaches the long-lived state", not state.sudden_death_enabled and not state.uses_sudden_death())
	check("settings: off is saved", _read_settings_file().get("sudden_death_enabled", true) == false, _read_settings_file())
	GameManager.sudden_death_enabled = true
	GameManager._load_user_settings()
	check("settings: off is read back", GameManager.sudden_death_enabled == false)
	GameManager.set_sudden_death_enabled(true)
	check("settings: on again (state and file)", state.sudden_death_enabled and _read_settings_file().get("sudden_death_enabled", false) == true)
	# The rest of the file survives (graphics quality is saved next to it).
	check("settings: other values kept", _read_settings_file().has("graphics_quality"), _read_settings_file().keys())


func _check_menu_row() -> void:
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	for _frame in range(10):
		await get_tree().process_frame
	var vbox := menu.get_node("SettingsPanel/VBox") as VBoxContainer
	var row := vbox.get_node_or_null("SuddenDeathBox") as HBoxContainer
	var quality_row := vbox.get_node_or_null("GraphicsQualityBox")
	check("menu: sudden death row under the graphics quality row", row != null and quality_row != null
		and row.get_index() == quality_row.get_index() + 1,
		[row.get_index() if row else -1, quality_row.get_index() if quality_row else -1])
	if row == null:
		menu.queue_free()
		return
	var label := row.get_node("Label") as Label
	var option := row.get_node("SuddenDeathOption") as OptionButton
	check("menu: label and choices", label.text == "サドンデス（2P 10問の引き分け）" and option.item_count == 2
		and option.get_item_text(0) == "オン" and option.get_item_text(1) == "オフ", [label.text, option.item_count])
	check("menu: row styled like the graphics quality row",
		label.get_theme_font_size("font_size") == 18 and option.get_theme_font_size("font_size") == 18
		and (quality_row.get_node("Label") as Label).custom_minimum_size == label.custom_minimum_size)
	check("menu: shows the saved value (on)", option.get_selected_id() == 0)
	option.select(1)
	option.item_selected.emit(1)
	check("menu: choosing オフ switches it off", not GameManager.sudden_death_enabled and not QuizManager.game_state.sudden_death_enabled
		and _read_settings_file().get("sudden_death_enabled", true) == false)
	(menu.get_node("SettingsPanel") as Control).visible = true
	# The first-launch tutorial prompt would cover the panel in the picture.
	for overlay in ["TutorialCourseSelector", "TutorialKeyboardIntro"]:
		var node := menu.get_node_or_null(overlay) as CanvasItem
		if node != null:
			node.visible = false
	for _frame in range(3):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "menu_settings_off.png"))
	option.select(0)
	option.item_selected.emit(0)
	check("menu: choosing オン switches it back on", GameManager.sudden_death_enabled and QuizManager.game_state.sudden_death_enabled)
	menu.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ reel

func _finale_state() -> QuizGameState:
	var helper: Node = load("res://tests/hp_unit.gd").new()
	var gs: QuizGameState = helper.fixture()
	helper.free()
	gs.result_ceremony_enabled = true
	gs.game_state = Constants.STATE_RESULT_CEREMONY
	gs.result_presentation_active = true
	gs.result_p1_score = 40
	gs.result_p2_score = 40
	gs.result_p1_correct_count = 8
	gs.result_p2_correct_count = 8
	gs.result_p1_hp = 2
	gs.result_p2_hp = 2
	gs.result_winner = 0
	return gs


func _check_reel() -> void:
	var gs := _finale_state()
	var reel := MatchReel.new()
	add_child(reel)
	reel.setup(gs, "balanced", false, false)
	var plain := reel.build_record()
	check("reel: a plain draw has no sudden_death", not plain.has("sudden_death") and int(plain.winner) == 0, plain.get("winner"))
	gs.game_state = Constants.STATE_SUDDEN_DEATH
	gs.result_presentation_active = false
	reel._process(1.0 / 60.0)
	check("reel: the capture records underground", reel.capture.recording)
	gs.game_state = Constants.STATE_MENU
	reel._process(1.0 / 60.0)
	check("reel: and not on the menu", not reel.capture.recording)
	gs.game_state = Constants.STATE_SUDDEN_DEATH
	for _frame in range(60):
		reel._process(1.0 / 60.0)
		await get_tree().process_frame
	check("reel: capture on (balanced)", reel.capture.is_enabled())
	var pending: Array = reel.capture.get("_pending")
	var before := pending.size()
	gs.sudden_death_event.emit({"kind": "buzz", "player": 2, "index": 1, "time": 3.0, "revealed": 6})
	check("reel: other sudden death events are not moments", (reel.capture.get("_pending") as Array).size() == before)
	gs.sudden_death_event.emit({"kind": "decided", "winner": 2, "loser": 1, "by": "correct", "index": 2})
	pending = reel.capture.get("_pending")
	var marked: Dictionary = {}
	var clip: Dictionary = {}
	for held: Dictionary in pending:
		for event: Dictionary in held.events:
			if event.get("kind") == "sudden_death":
				marked = event
				clip = held
	check("reel: the deciding moment is marked for the winner", int(marked.get("player", 0)) == 2
		and marked.get("by") == "correct" and int(marked.get("question", -1)) == 3, marked)
	check("reel: above the win and the draw", MatchReel.priority_of(marked) > MatchReel.priority_of({"kind": "win"})
		and MatchReel.priority_of(marked) > MatchReel.priority_of({"kind": "draw"}), MatchReel.priority_of(marked))
	check("reel: clip runs on after the moment", not clip.is_empty() and float(clip.end) - float(marked.at) >= 1.9, clip.get("end"))
	# Back on the surface with the winner (end_sudden_death).
	gs.game_state = Constants.STATE_RESULT_CEREMONY
	gs.result_presentation_active = true
	gs.sudden_death_winner = 2
	gs.sudden_death_decided_by = "correct"
	gs.sudden_death_question_count = 3
	gs.result_winner = 2
	var record := reel.build_record()
	report["record"] = record
	var points: Array = record.points
	check("reel: record keeps the level points and the winner", points.size() == 2 and int(points[0]) == 40 and int(points[1]) == 40
		and int(record.winner) == 2, [record.points, record.winner])
	var sudden: Dictionary = record.get("sudden_death", {})
	check("reel: record carries the sudden death", sudden.size() == 3 and int(sudden.get("questions", 0)) == 3
		and str(sudden.get("by", "")) == "correct" and int(sudden.get("winner", 0)) == 2, sudden)
	# Commit it (the clip may still be collecting: finish now) and read it back with a
	# VERSION 1 record before it.
	MatchHistory.append({"id": "old", "ts": 1, "mode": Constants.MODE_TEN, "players": 2, "p": [{"correct": 5}, {"correct": 7}],
		"points": [10, 14], "winner": 2, "highlights": []})
	reel.capture.finish_now()
	reel.set("_ended", true)
	reel.set("_end_state", Constants.STATE_CLEAR)
	reel._commit()
	MatchReel.wait_for_write()
	var records := MatchHistory.load_records()
	var saved := MatchHistory.latest(records)
	check("history: both records read", records.size() == 2, records.size())
	check("history: the old record has no sudden death", MenuLedProgram.sudden_death_of(records[0]).is_empty())
	var loaded := MenuLedProgram.sudden_death_of(saved)
	check("history: the new one does", int(loaded.get("questions", 0)) == 3 and str(loaded.get("by", "")) == "correct"
		and int(loaded.get("winner", 0)) == 2 and int(saved.get("winner", -1)) == 2, saved.get("sudden_death"))
	check("history: file version", int(MatchHistory.read_json(MatchHistory.path()).get("version", 0)) == MatchHistory.VERSION)
	check("history: the sudden death win counts", MatchHistory.summary(records).wins == [0, 2], MatchHistory.summary(records).wins)
	reel.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ LED

func _check_led() -> void:
	var records := MatchHistory.load_records()
	for english in [false, true]:
		var program := MenuLedProgram.new()
		add_child(program)
		check("led: programme built", program.setup(records, []))
		# setup() reads the language from the game state; segments fill their words later.
		program.english = english
		var tag := "en" if english else "ja"
		var label := program.event_label({"kind": "sudden_death", "player": 2}, 2)
		check("led %s: moment name" % tag, label == ("P2 SUDDEN DEATH!" if english else "P2 サドンデス決着！"), label)
		var plan := program.round_plan()
		for index in range(plan.size()):
			var comp := str(plan[index].comp)
			if comp != "LED_Versus" and comp != "LED_History":
				continue
			program.show_segment(index, 4.0 if comp == "LED_Versus" else 3.0)
			await _frames_drawn(2)
			program.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "led_%s_%s.png" % [tag, comp]))
			var segment: AeMotion.Comp = program.get("_segment")
			if comp == "LED_Versus":
				var header := segment.layer("HeaderText")
				var pill := segment.layer("HeaderPill")
				check("led %s: last match header names the sudden death" % tag,
					header.text == ("LAST MATCH · SUDDEN DEATH" if english else "前回の対戦・SUDDEN DEATH"), header.text)
				check("led %s: header pill fits the words and stays on the screen" % tag,
					pill.width_override >= header.text_width() and pill.width_override < float(MenuLedProgram.CANVAS.x) - 200.0
					and pill.fill_color == MenuLedProgram.SUDDEN_DEATH_RED, [pill.width_override, header.text_width()])
				check("led %s: win badge on P2" % tag, segment.layer("WinGroup").visible and segment.layer("WinGroup").position.x > 648.0)
			else:
				var mode := segment.layer("R1ModeText")
				var mode_pill := segment.layer("R1ModePill")
				var right_edge := 214.0 + mode_pill.width_override
				check("led %s: history row names the sudden death" % tag, mode.text == "SUDDEN DEATH"
					and mode_pill.fill_color == MenuLedProgram.SUDDEN_DEATH_RED and segment.layer("R1ResultText").text == "P2 WIN", mode.text)
				check("led %s: the pill ends before the P1 chip (%.0f px)" % [tag, right_edge], right_edge < 570.0 - 26.0 - 8.0, right_edge)
				check("led %s: the older match keeps its mode" % tag, segment.layer("R2ModeText").text == ("10-Q BATTLE" if english else "10問バトル")
					and mode_pill.fill_color != segment.layer("R2ModePill").fill_color, segment.layer("R2ModeText").text)
		program.queue_free()
		await get_tree().process_frame


# ------------------------------------------------------------------ scoreboard

func _board_state() -> QuizGameState:
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_RESULT_CEREMONY
	state.result_presentation_active = true
	state.sudden_death_pending = true
	state.result_winner = 0
	return state


func _sync_board(board: GoalStandScoreboard, state: QuizGameState, clock: float, verdict: int, seconds: float) -> float:
	var frames := int(round(seconds * 60.0))
	for _frame in range(frames):
		clock += 1.0 / 60.0
		board.sync(state, clock, true, verdict, false)
		await RenderingServer.frame_post_draw
	return clock


func _save_board(board: GoalStandScoreboard, name: String) -> void:
	await RenderingServer.frame_post_draw
	board.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "board_%s.png" % name))


func _check_board() -> void:
	var board := GoalStandScoreboard.new()
	add_child(board)
	board.setup()
	var state := _board_state()
	var clock := 0.0
	state.result_ceremony_elapsed = 7.2
	clock = await _sync_board(board, state, clock, 0, 0.5)
	check("board: the draw verdict shows DRAW!", board.cutin_player == GoalStandScoreboard.DRAW, board.cutin_player)
	state.result_ceremony_elapsed = 8.5
	clock = await _sync_board(board, state, clock, 0, 0.1)
	check("board: DRAW! until 8.6 s", board.cutin_player == GoalStandScoreboard.DRAW, board.cutin_player)
	state.result_ceremony_elapsed = GoalStandScoreboard.SUDDEN_DEATH_CUTIN
	clock = await _sync_board(board, state, clock, 0, 0.3)
	check("board: SUDDEN DEATH! from 8.6 s", board.cutin_player == GoalStandScoreboard.SUDDEN_DEATH and not board.cutin_sudden_death, board.cutin_player)
	await _save_board(board, "sudden_death_slam")
	clock = await _sync_board(board, state, clock, 0, 0.8)
	await _save_board(board, "sudden_death_ja")
	var image := board.viewport.get_texture().get_image()
	var reddish := 0
	for y in range(20, image.get_height(), 40):
		for x in range(20, image.get_width(), 40):
			var c := image.get_pixel(x, y)
			reddish += 1 if c.r > c.g + 0.2 and c.r > c.b + 0.2 else 0
	check("board: the hazard cut-in is red", reddish > 100, reddish)
	# Underground: the verdict is gone (the crowd is idle) but the board keeps it up.
	state.result_presentation_active = false
	state.game_state = Constants.STATE_SUDDEN_DEATH
	clock = await _sync_board(board, state, clock, -1, 0.3)
	check("board: SUDDEN DEATH! while it runs", board.cutin_player == GoalStandScoreboard.SUDDEN_DEATH, board.cutin_player)
	# English sub-line.
	state.use_english_ui = true
	board.call("_start_cutin", state, GoalStandScoreboard.SUDDEN_DEATH, clock)
	clock = await _sync_board(board, state, clock, -1, 1.0)
	await _save_board(board, "sudden_death_en")
	state.use_english_ui = false
	# Back with P2 the winner.
	state.game_state = Constants.STATE_RESULT_CEREMONY
	state.result_presentation_active = true
	state.sudden_death_pending = false
	state.sudden_death_winner = 2
	state.result_winner = 2
	state.result_ceremony_elapsed = 6.9
	clock = await _sync_board(board, state, clock, 2, 1.2)
	check("board: the sudden death winner's cut-in with its tag", board.cutin_player == 2 and board.cutin_sudden_death,
		[board.cutin_player, board.cutin_sudden_death])
	await _save_board(board, "winner_p2_sudden_death")
	state.sudden_death_winner = 1
	state.result_winner = 1
	clock = await _sync_board(board, state, clock, 1, 1.2)
	await _save_board(board, "winner_p1_sudden_death")
	# A plain win has no tag; switched off, a draw stays DRAW!.
	var plain := _board_state()
	plain.sudden_death_pending = false
	plain.result_winner = 1
	clock = await _sync_board(board, plain, clock, -1, 0.1)
	clock = await _sync_board(board, plain, clock, 1, 0.1)
	check("board: a plain win has no sudden death tag", board.cutin_player == 1 and not board.cutin_sudden_death)
	var off := _board_state()
	off.sudden_death_pending = false
	off.result_ceremony_elapsed = 9.5
	clock = await _sync_board(board, off, clock, 0, 0.1)
	check("board: a draw without the sudden death stays DRAW!", board.cutin_player == GoalStandScoreboard.DRAW, board.cutin_player)
	board.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ crowd

func _step_stand(stand: GoalStand, state: QuizGameState, director: FakeDirector, camera: Camera3D, seconds: float,
		advance_clock: bool) -> void:
	for _frame in range(int(round(seconds * 60.0))):
		if advance_clock:
			director.elapsed += 1.0 / 60.0
			state.result_ceremony_elapsed = director.elapsed
		stand.update_stand(1.0 / 60.0, state, director, camera)
		await get_tree().process_frame


func _hotheads(stand: GoalStand, team: int) -> Array[GoalStand.Spectator]:
	var list: Array[GoalStand.Spectator] = []
	for s: GoalStand.Spectator in stand.spectators:
		if s.kind == GoalStand.Kind.HOTHEAD and s.team == team:
			list.append(s)
	return list


func _check_crowd() -> void:
	var stand := GoalStand.new()
	add_child(stand)
	stand.setup("balanced")
	while not stand.is_populated():
		stand.update_stand(1.0 / 60.0, null, null, null)
	var target := Node3D.new()
	target.name = "LoserSpine"
	add_child(target)
	target.global_position = stand.global_position + Vector3(0.0, -0.4, 22.0)
	var director := FakeDirector.new()
	add_child(director)
	var far_camera := Camera3D.new()
	add_child(far_camera)
	far_camera.global_position = stand.global_position + Vector3(0.0, -60.0, 400.0)
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_RESULT_CEREMONY
	state.result_presentation_active = true
	state.sudden_death_pending = true
	state.result_winner = 0
	# The draw verdict: eggs at the referee.
	director.elapsed = ResultFinaleMotion.VERDICT
	director.target = target
	await _step_stand(stand, state, director, null, 3.0, true)
	var shot := stand.get_debug_snapshot()
	report["crowd_draw"] = {"eggs_launched": shot.eggs_launched, "boo_signs": shot.boo_signs}
	check("crowd: the draw verdict has its eggs and voice", int(shot.eggs_launched) > 0 and (stand.get("_cues") as Dictionary).has(&"verdict_draw"),
		[shot.eggs_launched, (stand.get("_cues") as Dictionary).keys()])
	check("crowd: nobody's boards flip on a draw", int(shot.boo_signs) == 0, shot.boo_signs)
	# Underground (the stand far from the camera, the director has no target).
	state.game_state = Constants.STATE_SUDDEN_DEATH
	state.result_presentation_active = false
	director.target = null
	await _step_stand(stand, state, director, far_camera, 1.0, false)
	# Back on the surface with P2 the winner; the director holds the verdict and has no
	# egg target yet.
	state.game_state = Constants.STATE_RESULT_CEREMONY
	state.result_presentation_active = true
	state.sudden_death_pending = false
	state.sudden_death_winner = 2
	state.result_winner = 2
	director.elapsed = ResultFinaleMotion.VERDICT
	state.result_ceremony_elapsed = director.elapsed
	await _step_stand(stand, state, director, null, 1.5, false)
	shot = stand.get_debug_snapshot()
	var cues := stand.get("_cues") as Dictionary
	report["crowd_return_waiting"] = {"eggs_launched": shot.eggs_launched, "boo_signs": shot.boo_signs, "cues": cues.keys(), "mood": shot.mood}
	check("crowd: back from the sudden death, old eggs cleared and none thrown without a target", int(shot.eggs_launched) == 0
		and int(stand.get("_egg_budget")) == GoalStand.EGG_BUDGET, [shot.eggs_launched, stand.get("_egg_budget")])
	var waiting := _hotheads(stand, 1)
	check("crowd: the loser's hotheads wait to throw", not waiting.is_empty()
		and waiting.all(func(s: GoalStand.Spectator) -> bool: return s.throws_left > 0 and s.throw_started < 0.0),
		waiting.map(func(s: GoalStand.Spectator) -> int: return s.throws_left))
	check("crowd: the winner's hotheads cheer instead", _hotheads(stand, 2).all(func(s: GoalStand.Spectator) -> bool: return s.throws_left == 0))
	check("crowd: the new verdict is cheered again (the draw's cue is gone)", cues.has(&"verdict_cheer") and not cues.has(&"verdict_draw"), cues.keys())
	check("crowd: the loser's sign row flips", int(shot.boo_signs) == 3, shot.boo_signs)
	check("crowd: the side stands follow the new verdict", stand.side_crowd_reaction().get("team", -1) == 2, stand.side_crowd_reaction())
	# The target shows up and the ceremony goes on: throws start, staggered.
	director.target = target
	var appeared := 0.0
	var first_launch := -1.0
	for frame in range(240):
		director.elapsed += 1.0 / 60.0
		state.result_ceremony_elapsed = director.elapsed
		stand.update_stand(1.0 / 60.0, state, director, null)
		appeared += 1.0 / 60.0
		if first_launch < 0.0 and stand.eggs.launched > 0:
			first_launch = appeared
		await get_tree().process_frame
	shot = stand.get_debug_snapshot()
	cues = stand.get("_cues") as Dictionary
	report["crowd_return_throwing"] = {"eggs_launched": shot.eggs_launched, "first_launch_after_s": snappedf(first_launch, 0.01), "cues": cues.keys()}
	check("crowd: eggs fly once the target exists", int(shot.eggs_launched) > 0 and int(shot.eggs_launched) <= GoalStand.EGG_BUDGET, shot.eggs_launched)
	check("crowd: the first throw is staggered after the target appears", first_launch >= 0.4, first_launch)
	check("crowd: boo for the loser", cues.has(&"verdict_boo"), cues.keys())
	stand.queue_free()
	for node: Node in [target, director, far_camera]:
		node.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ helpers

func _frames_drawn(count: int) -> void:
	for _frame in range(count):
		await RenderingServer.frame_post_draw


func finish() -> void:
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("SUDDEN_DEATH_SETTINGS_REEL " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
