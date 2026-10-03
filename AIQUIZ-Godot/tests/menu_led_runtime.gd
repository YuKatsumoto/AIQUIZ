extends Node

## The LED programme ("AIQUIZ VISION", MenuLedProgram), which now plays on the goal
## stand scoreboard (it used to play on the main menu's launch deck).
## Unit checks (motion data, replay pacing, all-time summary), then the programme with
## a history: five matches, the newest with three clips (a streak, a fall into the sea
## and the shark's bite in one clip, the finale win), made up here (default) or what
## tests/match_reel_runtime.gd recorded from a real match (`data=reel`). Checks the
## round plan (replay, two history pages, the logo held for LOGO_HOLD_SECONDS), the
## replay's pacing and captions, the filled-in words and numbers, that the transition
## covers the whole screen at the seam, and captures every segment flat, the replay at
## its beats, the same segments on the scoreboard's 1400 x 600 board (cut-in, the
## programme's wipe strokes over it, then the programme), and the empty-history programme.
## Results: res://artifacts/menu_led/menu/ (report.json and PNGs).
## Run: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/menu_led_bootstrap.gd
## Options after "--": data=reel, record (one round at 30 fps, the logo hold cut short)

const OUT := "res://artifacts/menu_led/menu/"
const STORE := "user://test_menu_led"
const REEL_STORE := "user://test_match_reel"
const SOURCE_SHOT := "res://artifacts/aiquiz_stadium/game/v3_2p_day_play.png"
## Second of each segment where its picture has settled (counters done, text in).
const SEGMENT_MOMENTS := {"LED_Sting": 1.4, "LED_Versus": 4.0, "LED_Solo": 3.2, "LED_History": 3.0, "LED_Stats": 3.2,
	"LED_Logo": 2.6, "LED_LogoLoop": 3.8}

var checks: Dictionary = {}
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks[label] = {"pass": ok, "detail": str(detail)}
	if not ok:
		failures.append("%s: %s" % [label, str(detail)])


func run() -> void:
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1920, 1080)
	var out_path := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out_path)
	for file_name: String in DirAccess.get_files_at(out_path):
		if file_name.ends_with(".png"):
			DirAccess.remove_absolute(out_path + "/" + file_name)
	_unit_checks()
	var store := REEL_STORE if "data=reel" in OS.get_cmdline_user_args() else STORE
	MatchHistory.path_override = store + "/match_history.json"
	HighlightStore.dir_override = store + "/highlights"
	if store == STORE:
		_make_history()
	var records := MatchHistory.load_records()
	var clips := HighlightStore.list()
	check("history to show", records.size() >= 1 and clips.size() >= 1, "%d matches, %d clips" % [records.size(), clips.size()])
	var program := MenuLedProgram.new()
	add_child(program)
	check("LED programme built", program.setup())
	if program.viewport == null:
		finish()
		return
	check("programme keeps its own mips by default", program.mips.size() == MenuLedProgram.MIP_LEVELS)
	_check_plan(program, records)
	var newest: Array = HighlightStore.by_match(clips)[0]
	for frame in range(300):
		await get_tree().process_frame
		if newest.slice(0, 2).all(func(clip: Dictionary) -> bool: return program.is_clip_loaded(clip)):
			break
	check("first replay clips decoded on a worker", newest.slice(0, 2).all(func(clip: Dictionary) -> bool: return program.is_clip_loaded(clip)))
	await _capture_segments(program, records)
	await _capture_replay(program, newest)
	await _check_seam(program)
	program.queue_free()
	var scoreboard := GoalStandScoreboard.new()
	add_child(scoreboard)
	scoreboard.setup()
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_CLEAR
	state.goal_winner = 1
	state.result_presentation_active = true
	await _capture_on_scoreboard(scoreboard, state)
	if "record" in OS.get_cmdline_user_args():
		await _record_round(scoreboard, state)
	scoreboard.free()
	await _empty_programme()
	finish()


func _check_plan(program: MenuLedProgram, records: Array[Dictionary]) -> void:
	var plan := program.round_plan().map(func(item: Dictionary) -> String: return str(item.comp))
	var pages := mini(MenuLedProgram.HISTORY_PAGES, ceili(float(records.size()) / MenuLedProgram.HISTORY_ROWS))
	var last_players := int(MatchHistory.latest(records).get("players", 1))
	var expected := ["LED_Sting", "REPLAY", "LED_Sting", "LED_Versus" if last_players >= 2 else "LED_Solo"]
	for page in range(pages):
		expected.append("LED_History")
	expected.append_array(["LED_Stats", "LED_Logo"])
	check("round plan up to the logo", plan.slice(0, expected.size()) == expected, plan.slice(0, expected.size() + 1))
	var loops := plan.slice(expected.size())
	var loop_seconds: float = float(loops.size()) * program.get("_motion").duration("LED_LogoLoop")
	check("logo held for the hold time after the round", loops.all(func(comp: String) -> bool: return comp == "LED_LogoLoop")
		and loop_seconds >= MenuLedProgram.LOGO_HOLD_SECONDS, "%d loops, %.0f s" % [loops.size(), loop_seconds])
	var items := program.round_plan()
	check("no transition between the logo and its loop, one after the hold",
		items[expected.size() - 1].get("wipe_out", true) == false and items[expected.size()].get("wipe_in", true) == false
		and items[items.size() - 1].get("wipe_out", false) == true)


func _capture_segments(program: MenuLedProgram, records: Array[Dictionary]) -> void:
	var moments := SEGMENT_MOMENTS
	var shot := {}
	for index in range(program.round_plan().size()):
		var comp := str(program.round_plan()[index].comp)
		if comp == "REPLAY" or (comp == "LED_LogoLoop" and shot.has(comp)):
			continue
		program.show_segment(index, float(moments.get(comp, 2.0)))
		await _frames_drawn(2)
		program.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "segment_%02d_%s.png" % [index, comp]))
		shot[comp] = true
		_check_segment(program, comp, records)


func _check_segment(program: MenuLedProgram, comp: String, records: Array[Dictionary]) -> void:
	var segment: AeMotion.Comp = program.get("_segment")
	var info := program.current_segment()
	match comp:
		"LED_Versus":
			var record := MatchHistory.latest(records)
			var totals := MenuLedProgram.versus_totals(record)
			check("versus scores counted up to the final totals",
				segment.layer("P1Score").text == MenuLedProgram.format_points(totals[0], totals[2])
				and segment.layer("P2Score").text == MenuLedProgram.format_points(totals[1], totals[2]),
				[segment.layer("P1Score").text, segment.layer("P2Score").text])
			var winner := int(record.get("winner", -1))
			check("win badge on the winner", segment.layer("WinGroup").visible == (winner >= 0)
				and (winner != 1 or segment.layer("WinGroup").position.x < 648.0)
				and (winner != 2 or segment.layer("WinGroup").position.x > 648.0), segment.layer("WinGroup").position)
		"LED_History":
			var rows: Array = info.rows
			var shown := 0
			for row in range(MenuLedProgram.HISTORY_ROWS):
				if segment.layer("R%dGroup" % (row + 1)).visible:
					shown += 1
			check("history page shows %d rows" % rows.size(), shown == rows.size(), shown)
			var first: Dictionary = rows[0]
			var result := segment.layer("R1ResultText").text
			check("history row 1: %s" % result, not result.is_empty() and segment.layer("R1ResultPill").width_override >= segment.layer("R1ResultText").text_width(),
				[result, segment.layer("R1P1Val").text, first.get("players")])
		"LED_Stats":
			var summary := MatchHistory.summary(records)
			check("stats tiles", segment.layer("T1Value").text == str(summary.matches)
				and segment.layer("T2Value").text == str(summary.best_correct)
				and segment.layer("T3Value").text == "%d%%" % int(round(float(summary.accuracy) * 100.0)),
				[segment.layer("T1Value").text, segment.layer("T2Value").text, segment.layer("T3Value").text])


## The replay's beats: a fast-forward stretch, each moment's caption, a cut.
func _capture_replay(program: MenuLedProgram, clips: Array) -> void:
	program.show_segment(1, 0.0)
	var plan := program.replay_plan()
	var moments: Array = plan.moments
	check("replay: every clip of the newest match, in match order", moments.size() == clips.size()
		and moments.map(func(m: Dictionary) -> String: return str(m.clip.id)) == clips.map(func(c: Dictionary) -> String: return str(c.id)),
		moments.size())
	var events := 0
	for clip: Dictionary in clips:
		events += MenuLedProgram.clip_events(clip).size()
	check("replay: a caption for every moment", (plan.captions as Array).size() == events, "%d of %d" % [(plan.captions as Array).size(), events])
	check("replay length %.1f s" % float(plan.duration), float(plan.duration) > 3.0 * moments.size() and float(plan.duration) < 90.0)
	var beats: Array[Array] = []
	# A fast-forward stretch after the opening transition has uncovered the screen.
	for moment: Dictionary in moments:
		var found := false
		for piece: Dictionary in moment.pieces:
			var from := float(moment.start) + float(piece.d0)
			var to := from + (float(piece.s1) - float(piece.s0)) / float(piece.rate)
			if float(piece.rate) > 1.0 and to > 0.75:
				beats.append(["fast", maxf(from + 0.05, 0.7)])
				found = true
				break
		if found:
			break
	for caption: Dictionary in plan.captions:
		beats.append(["caption_%s" % caption.event.kind, float(caption.at) + 0.7])
	if moments.size() > 1:
		beats.append(["cut", float(moments[1].start) - 0.02])
	var index := 0
	for beat: Array in beats:
		for frame in range(120):
			await get_tree().process_frame
			if (moments.map(func(m: Dictionary) -> Dictionary: return m.clip) as Array).all(func(clip: Dictionary) -> bool: return program.is_clip_loaded(clip)):
				break
		program.show_segment(1, float(beat[1]))
		await _frames_drawn(2)
		program.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "replay_%02d_%s.png" % [index, beat[0]]))
		index += 1
		var frame_comp: AeMotion.Comp = program.get("_replay_frame")
		var caption_comp: AeMotion.Comp = program.get("_replay_caption")
		if beat[0] == "fast":
			check("fast-forward chip while the gaps run", frame_comp.layer("FastGroup").visible, program.get("_replay_now"))
		elif String(beat[0]).begins_with("caption"):
			check("%s: caption up, band fits the words" % beat[0], caption_comp.visible
				and caption_comp.layer("CapBand").line_end_x >= caption_comp.layer("CapText").text_width(), caption_comp.layer("CapText").text)
		elif beat[0] == "cut":
			check("cut strokes between moments", (program.get("_replay_cut") as AeMotion.Comp).visible)


## At the seam the transition's strokes cover the whole screen (flat cream).
func _check_seam(program: MenuLedProgram) -> void:
	program.set_process(false)
	program.show_segment(0, 0.0)
	program.show_segment(0, program.segment_duration() - 0.02)
	await _frames_drawn(2)
	program.set_process(true)
	var seam := program.get_texture().get_image()
	seam.save_png(ProjectSettings.globalize_path(OUT + "seam.png"))
	check("segments meet on a full cover", _spread(seam) < 0.03 and seam.get_pixel(648, 294).get_luminance() > 0.8, _spread(seam))


## The same programme mounted on the goal stand scoreboard: the winner's cut-in, then
## (the match is saved: programme_ready) the programme's strokes over it, then the
## programme alone on the 1400 x 600 board. Saves the board's picture of the strokes
## over the cut-in and of each segment.
func _capture_on_scoreboard(board: GoalStandScoreboard, state: QuizGameState) -> void:
	var clock := 0.0
	# The first sync starts the cut-in, the second one (programme_ready) the programme.
	for _frame in range(2):
		clock += 1.0 / 60.0
		board.sync(state, clock, true, 1, true)
	check("scoreboard mounts the programme after the cut-in", board.is_programme_started() and board.is_cutin_playing()
		and board.programme() != null and board.programme().mips.is_empty())
	var program := board.programme()
	var plan_comps := program.round_plan().map(func(item: Dictionary) -> String: return str(item.comp))
	check("the history has clips, yet the board's programme leaves the replay out",
		not HighlightStore.list().is_empty() and not ("REPLAY" in plan_comps) and plan_comps[0] == "LED_Sting"
		and str(program.round_plan()[0].get("title", "")) == "RECORDS", plan_comps.slice(0, 4))
	program.set_process(false)
	var strokes := 0
	while program.is_lead_in():
		program._process(1.0 / 60.0)
		clock += 1.0 / 60.0
		board.sync(state, clock, true, 1, true)
		strokes += 1
		if strokes in [8, 16]:
			await _frames_drawn(3)
			board.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "board_strokes_%02d.png" % strokes))
	board.sync(state, clock + 0.02, true, 1, true)
	check("the strokes covered the cut-in, then the programme plays alone", board.is_programme_playing() and not board.is_cutin_playing(),
		"%d lead-in frames" % strokes)
	var plan := program.round_plan()
	for index in range(plan.size()):
		var comp := str(plan[index].comp)
		if comp == "REPLAY" or comp == "LED_LogoLoop":
			continue
		program.show_segment(index, float(SEGMENT_MOMENTS.get(comp, 2.0)))
		# The stand syncs the board every frame: redraw it from the programme's new frame.
		for _frame in range(4):
			clock += 1.0 / 60.0
			board.sync(state, clock, true, 1, true)
			await RenderingServer.frame_post_draw
		var image := board.viewport.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(OUT + "board_%02d_%s.png" % [index, comp]))
		check("board shows %s (picture is not flat)" % comp, _spread(image) > 0.03 and image.get_size() == GoalStandScoreboard.SIZE)
	program.set_process(true)


## One round at 30 fps (the programme stepped by hand so saving never slows it): the
## flat programme and the scoreboard's board, the logo hold cut to 6 s.
## Frames go to OUT/round/ and OUT/round_board/ (encode with ffmpeg, see the docs).
func _record_round(board: GoalStandScoreboard, state: QuizGameState) -> void:
	for folder in ["round", "round_board"]:
		var path := ProjectSettings.globalize_path(OUT + folder)
		DirAccess.make_dir_recursive_absolute(path)
		for file_name: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path + "/" + file_name)
	var program := board.programme()
	program.set_process(false)
	program.show_segment(0, 0.0)
	var clock := 100.0
	var frame := 0
	var loop_frames := 0
	while loop_frames < 180:
		program._process(1.0 / 30.0)
		clock += 1.0 / 30.0
		board.sync(state, clock, true, 1, true)
		if program.current_segment().comp == "LED_LogoLoop":
			loop_frames += 1
		await RenderingServer.frame_post_draw
		program.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "round/%04d.png" % frame))
		board.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "round_board/%04d.png" % frame))
		frame += 1
	program.set_process(true)
	check("recorded one round (%d frames)" % frame, frame > 30 * 30)


## With no history the LED shows an invitation to play, then the logo.
func _empty_programme() -> void:
	var program := MenuLedProgram.new()
	add_child(program)
	program.setup([], [])
	var plan := program.round_plan().map(func(item: Dictionary) -> String: return str(item.comp))
	check("empty history: invitation, logo, logo hold", plan.slice(0, 3) == ["LED_Empty", "LED_Logo", "LED_LogoLoop"], plan.slice(0, 3))
	for index in range(2):
		program.show_segment(index, 2.0)
		await _frames_drawn(2)
		program.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "empty_%d.png" % index))
	program.queue_free()


func _unit_checks() -> void:
	var motion := AeMotion.load_file(MenuLedProgram.MOTION_PATH)
	for comp: String in ["BG_Ambient", "WIPE_Strokes", "CUT_Strokes", "REPLAY_Frame", "REPLAY_Caption", "LED_Sting",
			"LED_Versus", "LED_Solo", "LED_History", "LED_Stats", "LED_Logo", "LED_LogoLoop", "LED_Empty"]:
		check("motion has %s" % comp, motion.has_comp(comp))
	var wipe := motion.instance("WIPE_Strokes", MenuLedProgram.FONT)
	var cover := wipe.layer("Cover1")
	check("transition strokes are round-capped paths with Trim Paths", cover != null and cover.shape.kind == "line"
		and cover.shape.cap == "round" and (cover.shape.trim as Dictionary).has("startTrack"))
	wipe.free()
	# One clip of 3 s with a moment at 2 s, gaps at 2x.
	var pieces := MenuLedProgram.clip_pieces(3.0, [{"t": 2.0}], 2.0)
	var rates := pieces.map(func(p: Dictionary) -> float: return float(p.rate))
	check("replay pacing: fast, real speed, slow at the moment, real speed", rates == [2.0, 1.0, 0.5, 1.0], rates)
	var shown := MenuLedProgram.shown_at(pieces, 2.0)
	check("replay pacing: shown and clip seconds invert", is_equal_approx(MenuLedProgram.source_at(pieces, shown).x, 2.0), shown)
	check("replay pacing: slow motion at the moment", is_equal_approx(MenuLedProgram.source_at(pieces, shown).y, 0.5))
	check("replay pacing: holds on the last frame", is_equal_approx(MenuLedProgram.source_at(pieces, 99.0).x, 3.0))
	check("half points", MenuLedProgram.format_points(25, true) == "12.5" and MenuLedProgram.format_points(24, false) == "12")
	var summary := MatchHistory.summary([
		{"p": [{"correct": 8, "attempted": 10}], "winner": -1},
		{"p": [{"correct": 6, "attempted": 10}, {"correct": 9, "attempted": 10}], "winner": 2},
	])
	check("summary", summary.matches == 2 and summary.best_correct == 9 and is_equal_approx(summary.accuracy, 23.0 / 30.0)
		and summary.wins == [0, 1], summary)


## Five matches (older ones first; the newest a 2P battle P1 won) and three clips of
## the newest cut from a gameplay screenshot with a slow pan, as HighlightCapture
## stores them.
func _make_history() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE))
	for path: String in [MatchHistory.path(), HighlightStore.index_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var now := int(Time.get_unix_time_from_system())
	var solo := {"mode": Constants.MODE_TEN, "players": 1, "target": 10, "points": [], "winner": -1, "highlights": []}
	var duo := {"mode": Constants.MODE_TEN, "players": 2, "target": 10, "highlights": []}
	var matches := [
		_record(solo, "t1", now - 86400 * 3, "CLEAR", 84.2, [[10, 10, 10]], [], -1),
		_record(duo, "t2", now - 86400 * 2, "CLEAR", 101.0, [[6, 10, 3], [7, 10, 4]], [14, 21], 2),
		_record(solo, "t3", now - 86400, "GAME_OVER", 40.5, [[4, 6, 2]], [], -1),
		_record(duo, "t4", now - 7200, "CLEAR", 97.0, [[5, 10, 2], [7, 10, 3]], [35, 35], 0),
		_record(duo, "t5", now - 60, "CLEAR", 96.0, [[8, 10, 4], [9, 10, 3]], [56, 27], 1),
	]
	for record: Dictionary in matches:
		MatchHistory.append(record)
	var shot := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_SHOT))
	var clips: Array = []
	var moments := [
		[{"kind": "streak", "player": 1, "streak": 3, "t": 2.8}],
		[{"kind": "ocean", "player": 2, "t": 1.5}, {"kind": "shark", "player": 2, "t": 3.6}],
		[{"kind": "win", "player": 1, "t": 1.4}],
	]
	for order in range(moments.size()):
		var jpegs: Array[PackedByteArray] = []
		var times: Array[float] = []
		var frames := 48 if order == 1 else 38
		for frame in range(frames):
			var u := float(frame) / float(frames - 1)
			var w := int(shot.get_width() * (0.9 - 0.12 * u))
			var h := int(w * 9.0 / 16.0)
			var x := int((shot.get_width() - w) * (0.5 + (0.2 if order % 2 == 0 else -0.2) * (u - 0.5)))
			var image := shot.get_region(Rect2i(x, clampi(int(shot.get_height() * 0.08), 0, shot.get_height() - h), w, h))
			image.resize(HighlightCapture.SIZE.x, HighlightCapture.SIZE.y, Image.INTERPOLATE_BILINEAR)
			jpegs.append(image.save_jpg_to_buffer(0.75))
			times.append(frame / 12.0)
		var lead: Dictionary = moments[order][moments[order].size() - 1]
		var entry := {"id": "t5_%02d" % order, "ts": float(now - 60) + order * 0.01, "match": "t5", "order": order,
			"at": 20.0 * order, "mode": Constants.MODE_TEN, "players": 2, "online": false, "times": times,
			"events": moments[order], "size": [HighlightCapture.SIZE.x, HighlightCapture.SIZE.y],
			"kind": lead.kind, "player": lead.player, "event": lead.t}
		clips.append({"entry": entry, "jpegs": jpegs})
	HighlightStore.add_clips(clips)


func _record(base: Dictionary, id: String, ts: int, end: String, time: float, players: Array, points: Array, winner: int) -> Dictionary:
	var record := base.duplicate(true)
	record.merge({"id": id, "ts": ts, "end": end, "time": time, "points": points, "winner": winner}, true)
	var list: Array = []
	for player: Array in players:
		list.append({"correct": player[0], "attempted": player[1], "best_streak": player[2], "hp": 2, "alive": true})
	record["p"] = list
	return record


func _frames_drawn(count: int) -> void:
	for frame in range(count):
		await RenderingServer.frame_post_draw


func _spread(image: Image) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in range(4, image.get_height(), 20):
		for x in range(4, image.get_width(), 20):
			var v := image.get_pixel(x, y).get_luminance()
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi - lo


func finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("MENU_LED_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
