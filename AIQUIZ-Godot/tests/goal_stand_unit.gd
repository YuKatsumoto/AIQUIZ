extends Node

## Goal stand structure checks (no gameplay): every quality keeps a full cast with
## egg throwers on both sides, fans sit behind their player's lane, the clips exist
## with the right loop modes, and spawning stays within a small per-frame budget. The
## scoreboard's cut-in and its hand-over to the AIQUIZ VISION programme are checked too.
## Run: Godot --headless --path . --script tests/goal_stand_bootstrap.gd

const STORE := "user://test_goal_stand_programme"

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	var report := {}
	# The programme reads the match history: keep the test off the player's real one.
	MatchHistory.path_override = STORE + "/match_history.json"
	HighlightStore.dir_override = STORE + "/highlights"
	for quality in ["low", "balanced", "high", "ultra"]:
		var stand := GoalStand.new()
		add_child(stand)
		var started := Time.get_ticks_usec()
		stand.setup(quality)
		var setup_msec := float(Time.get_ticks_usec() - started) / 1000.0
		var worst_frame := 0.0
		var frames := 0
		while not stand.is_populated():
			started = Time.get_ticks_usec()
			stand.update_stand(1.0 / 60.0, null, null, null)
			worst_frame = maxf(worst_frame, float(Time.get_ticks_usec() - started) / 1000.0)
			frames += 1
		var shot := stand.get_debug_snapshot()
		report[quality] = {"setup_msec": snappedf(setup_msec, 0.01), "worst_spawn_frame_msec": snappedf(worst_frame, 0.01),
			"spawn_frames": frames, "spectators": shot.spectators, "kinds": shot.kinds}
		check(int(shot.spectators) >= (40 if quality == "low" else 60), "%s: crowd size %d" % [quality, int(shot.spectators)])
		check(int(shot.kinds.get("HOTHEAD", 0)) == 6, "%s: six egg throwers, three per side" % quality)
		for kind in ["DANCER", "SIGN", "FLAG", "FOAM", "FAN"]:
			check(int(shot.kinds.get(kind, 0)) > 0, "%s: has %s" % [quality, kind])
		var left := 0
		var right := 0
		for s: GoalStand.Spectator in stand.spectators:
			check(absf(s.root.position.x) <= 13.0 and s.root.position.y >= 0.3, "%s: spectator on a tier" % quality)
			if s.team == 1:
				left += 1 if s.root.position.x < 0.0 else 0
			elif s.team == 2:
				right += 1 if s.root.position.x > 0.0 else 0
			check(s.body != null and s.body.material_override != null, "%s: body uses the crowd shader" % quality)
		check(left > 10 and right > 10, "%s: P1 fans behind P1's lane, P2 fans behind P2's" % quality)
		_check_sign_rows(stand, quality)
		if quality == "balanced":
			var ap: AnimationPlayer = stand.spectators[0].ap
			for clip in GoalStand.DANCES + [&"SPEC_Cheer", &"SPEC_Clap", &"SPEC_Rage", &"SPEC_Despair", &"SPEC_Throw", &"SPEC_SignUp", &"SPEC_PointLaugh"]:
				check(ap.has_animation(clip), "clip %s exported" % clip)
			check(ap.get_animation(&"SPEC_Throw").loop_mode == Animation.LOOP_NONE, "throw is a one-shot")
			check(ap.get_animation(&"SPEC_Cheer").loop_mode == Animation.LOOP_LINEAR, "cheer loops")
			check(ap.get_animation(&"SPEC_Dance_YMCA").loop_mode == Animation.LOOP_NONE, "dances end so a new emote is picked")
		if quality == "low":
			_check_programme_timeout(stand)
		if quality == "balanced":
			_check_scoreboard(stand)
			_check_programme(stand)
		stand.free()
	print("GOAL_STAND_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}))
	get_tree().quit(0 if failures.is_empty() else 1)


## Each side has three neighbours on one tier holding "OH" "MY" "GOT" from screen
## left (stand-local -X) to right, present at every quality.
func _check_sign_rows(stand: GoalStand, quality: String) -> void:
	for team in [1, 2]:
		var row: Array[GoalStand.Spectator] = []
		for s: GoalStand.Spectator in stand.spectators:
			if s.kind == GoalStand.Kind.SIGN and s.team == team:
				row.append(s)
		check(row.size() == 3, "%s: P%d has three sign holders" % [quality, team])
		if row.size() != 3:
			continue
		row.sort_custom(func(a: GoalStand.Spectator, b: GoalStand.Spectator) -> bool: return a.root.position.x < b.root.position.x)
		check(row.map(func(s: GoalStand.Spectator) -> int: return s.word) == [0, 1, 2], "%s: P%d signs read OH MY GOT" % [quality, team])
		check(row[0].row == row[2].row and row[2].root.position.x - row[0].root.position.x < GoalStand.SPACING * 2.6,
			"%s: P%d sign holders stand side by side" % [quality, team])
		check(not row[0].props["GSP_SignBoo"].visible, "%s: word boards stay hidden before the verdict" % quality)


func _check_scoreboard(stand: GoalStand) -> void:
	check(stand.scoreboard_installed(), "LED face of the scoreboard cabinet shows the board")
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_PLAYING
	state.current_index = 4
	for mask in [1, 2, 0, 1]:
		state.record_question_winner(state.question_winners.size(), mask)
	stand.update_stand(1.0 / 60.0, state, null, null)
	var board: Dictionary = stand.get_debug_snapshot().scoreboard
	check(board.marks == [1, 2, 0, 1, -1, -1, -1, -1, -1, -1], "scoreboard marks %s" % [board.marks])
	check(board.totals == [2, 1], "scoreboard totals %s" % [board.totals])
	check(stand.scoreboard.current == 4, "scoreboard highlights the current question")
	check(board.cutin == 0, "question wins only mark the board, no cut-in")
	state.record_question_winner(4, 2)
	for _frame in range(150):
		stand.update_stand(1.0 / 60.0, state, null, null)
	check(not stand.scoreboard.is_cutin_playing(), "no cut-in before the verdict")
	# Verdict out (the goal-race clear path uses goal_winner): the winner's cut-in holds.
	state.game_state = Constants.STATE_CLEAR
	state.goal_winner = 2
	for _frame in range(200):
		stand.update_stand(1.0 / 60.0, state, null, null)
	check(stand.scoreboard.cutin_player == 2, "verdict shows the winner's cut-in and holds it")
	for s: GoalStand.Spectator in stand.spectators:
		if s.kind == GoalStand.Kind.SIGN:
			var word_board := s.props["GSP_SignBoo"] as MeshInstance3D
			check(s.boo_sign == (s.team == 1) and word_board.visible == (s.team == 1), "only the loser's sign row flips")
			check((word_board.material_override as BaseMaterial3D).albedo_texture == GoalStand.WORD_SIGNS[s.word], "flipped board shows its own word")
	state.goal_winner = 0
	stand.update_stand(1.0 / 60.0, state, null, null)
	check(stand.scoreboard.cutin_player == GoalStandScoreboard.DRAW, "a draw verdict shows the draw cut-in")
	state.game_state = Constants.STATE_PLAYING
	stand.update_stand(1.0 / 60.0, state, null, null)
	check(not stand.scoreboard.is_cutin_playing(), "a new race returns to the score grid")


## The finale's result screen (STATE_CLEAR with result_presentation_active) on a 2P game.
func _finale_clear_state(winner: int) -> QuizGameState:
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_CLEAR
	state.goal_winner = winner
	return state


## After the cut-in the board hands over to the programme once the match is saved, in
## the local finale only, and the verdict that stays out does not bring the cut-in back.
func _check_programme(stand: GoalStand) -> void:
	var board := stand.scoreboard
	var state := _finale_clear_state(1)
	# A clear that is not the local finale (online, tutorial) keeps the cut-in.
	for _frame in range(30):
		stand.update_stand(1.0 / 60.0, state, null, null, true)
	check(board.is_cutin_playing() and not board.is_programme_started(), "a clear outside the finale never starts the programme")
	state.result_presentation_active = true
	for _frame in range(30):
		stand.update_stand(1.0 / 60.0, state, null, null, false)
	check(board.is_cutin_playing() and not board.is_programme_started(), "the programme waits until the match is saved")
	stand.update_stand(1.0 / 60.0, state, null, null, true)
	check(board.is_programme_started() and not board.is_programme_playing(), "saved match: the programme leads in")
	check(board.is_cutin_playing(), "the cut-in keeps playing under the programme's first strokes")
	var programme := board.programme()
	check(programme != null and programme.is_lead_in(), "the programme starts with its wipe strokes")
	check(programme.viewport.size == MenuLedProgram.CANVAS and programme.mips.is_empty(), "the board's programme keeps no mips of its own")
	# MenuLedProgram._process does not run in this synchronous test: step it by hand.
	for _frame in range(40):
		programme._process(1.0 / 60.0)
		stand.update_stand(1.0 / 60.0, state, null, null, true)
	check(board.is_programme_playing(), "after the strokes the programme plays")
	check(not board.is_cutin_playing(), "and the cut-in is gone")
	check(str(board.programme_segment().get("comp", "")) == "LED_Empty", "no history yet: the invitation segment plays, got %s" % [board.programme_segment()])
	state.goal_winner = 2
	for _frame in range(120):
		programme._process(1.0 / 60.0)
		stand.update_stand(1.0 / 60.0, state, null, null, true)
	check(board.is_programme_playing() and not board.is_cutin_playing(), "the verdict stays out but the cut-in does not start again")
	# Out of range the programme freezes (nobody can see it) and picks up when back.
	stand.scoreboard.sync(state, 99.0, false, 2, true)
	check(not programme.is_processing() and programme.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"out of range the programme and its viewport are paused")
	stand.scoreboard.sync(state, 99.1, true, 2, true)
	check(programme.is_processing() and programme.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"back in range the programme plays on")


## A match that never gets saved (slow disk, no record) cannot hold the cut-in forever.
func _check_programme_timeout(stand: GoalStand) -> void:
	var board := stand.scoreboard
	var state := _finale_clear_state(2)
	state.result_presentation_active = true
	var patient := int((GoalStand.PROGRAMME_WAIT_MAX - 0.5) * 60.0)
	for _frame in range(patient):
		stand.update_stand(1.0 / 60.0, state, null, null, false)
	check(board.is_cutin_playing() and not board.is_programme_started(), "still waiting for the save before the timeout")
	for _frame in range(90):
		stand.update_stand(1.0 / 60.0, state, null, null, false)
	check(board.is_programme_started(), "the programme starts after the timeout without a saved match")
