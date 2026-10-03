extends Node

## MatchReel end to end in the real game world: in a local 2P ten-question match P1
## answers three in a row during the goal race, P2 falls into the sea and the shark
## bites, P1 finishes and wins the Score Tower finale (28 to the ghost's 9), and the
## reel must store every moment (the streak, the fall and the bite, the win) as
## highlight clips (JPEG frames of the match camera) and the match in the history.
## Storage goes to user://test_match_reel/ (never the player's own history).
## Results: res://artifacts/menu_led/match_reel/ (report.json, clip contact sheets).
## Run: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/match_reel_bootstrap.gd

const OUT := "res://artifacts/menu_led/match_reel/"
const STORE := "user://test_match_reel"

var checks: Dictionary = {}
var failures: Array[String] = []
var gs: QuizGameState
var world: Node
var perf: Dictionary = {}


func _ready() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks[label] = {"pass": ok, "detail": str(detail)}
	if not ok:
		failures.append("%s: %s" % [label, str(detail)])


func run() -> void:
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_clear_store()
	MatchHistory.path_override = STORE + "/match_history.json"
	HighlightStore.dir_override = STORE + "/highlights"
	GameManager.graphics_quality = "balanced"
	var helper: Node = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	helper.free()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await frames(60)
	world.call("_clear_preview_walls")
	gs.saw.enabled = false # Nobody is caught while the ring buffer fills.
	var reel: MatchReel = world.get("_match_reel")
	check("reel created for a local match", reel != null)
	check("capture enabled (balanced: 12 fps)", reel != null and reel.capture.is_enabled() and is_equal_approx(reel.capture.fps, 12.0),
		reel.capture.fps if reel != null else -1)
	if reel == null:
		finish()
		return
	# Ten answered: 8 vs 9 correct, P1 alive with 3 HP, P2 with 1 HP (the finale's "p1" case).
	gs.score = 8
	gs.player2_score = 9
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	check("ten questions route to the goal race", gs.game_state == Constants.STATE_GOAL_RACE, gs.game_state)
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 12.0
	gs.player2_z = gs.goal_z - 12.0
	gs.player_x = 2.2
	gs.player2_x = -2.2
	gs.p1_hp = 3
	gs.p2_alive = true
	gs.p2_hp = 1
	# Let the ring buffer fill (2.5 s) while measuring what the capture costs, then P1
	# answers three in a row.
	# One shot's cost: the capture viewport rendered every frame for a second.
	var shot_viewport: SubViewport = reel.capture.get("_viewport")
	var shot_rid := shot_viewport.get_viewport_rid()
	var main_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(shot_rid, true)
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	reel.set_process(false)
	reel.capture.set_process(false)
	shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var shots: Array[Vector2] = []
	var mains: Array[Vector2] = []
	for frame in range(90):
		_hold_back()
		await RenderingServer.frame_post_draw
		if frame >= 30:
			shots.append(Vector2(RenderingServer.viewport_get_measured_render_time_cpu(shot_rid), RenderingServer.viewport_get_measured_render_time_gpu(shot_rid)))
			mains.append(Vector2(RenderingServer.viewport_get_measured_render_time_cpu(main_rid), RenderingServer.viewport_get_measured_render_time_gpu(main_rid)))
	shot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	reel.set_process(true)
	reel.capture.set_process(true)
	var shot_ms := _mean(shots)
	perf = {"shot_ms_cpu_gpu": shot_ms, "main_ms_cpu_gpu": _mean(mains), "shots_per_second": reel.capture.fps,
		"capture_ms_per_second": snappedf((shot_ms[0] + shot_ms[1]) * reel.capture.fps, 0.1)}
	for frame in range(150):
		_hold_back()
		await get_tree().process_frame
	var shots_taken: int = reel.capture.get("_ring").size()
	var expected_shots := reel.capture.fps * HighlightCapture.PRE_ROLL_MAX
	check("ring buffer holds the last 2.5 s (%d shots)" % expected_shots, shots_taken >= expected_shots * 0.75 and shots_taken <= expected_shots * 1.25, shots_taken)
	for question in range(3):
		gs.record_question_winner(20 + question, 1)
	check("streak counted", int(reel._players[0].best_streak) == 3 and int(reel._players[1].attempted) == 0, reel._players)
	for frame in range(150):
		_hold_back()
		await get_tree().process_frame
	# P2 goes over the side; the shark comes for them while P1 waits short of the goal.
	gs.player2_x = -(QuizGameState.FLOOR_HALF_WIDTH + 2.5)
	gs.player2_z = gs.goal_z - 12.0
	gs._begin_ocean_shark_wait(2)
	for frame in range(60 * 45):
		gs.player_z = gs.goal_z - 10.0
		await get_tree().process_frame
		if gs.p2_shark_killed:
			break
	check("still racing while the shark comes", gs.game_state == Constants.STATE_GOAL_RACE, gs.game_state)
	check("P2 fell into the sea and the shark bit", not gs.p2_alive and gs.p2_shark_killed)
	for frame in range(90):
		gs.player_z = gs.goal_z - 10.0
		await get_tree().process_frame
	gs.player_z = gs.goal_z - 1.6
	# The finale runs 11.2 s; the reel then waits for its clips and writes the record.
	for frame in range(60 * 20):
		await get_tree().process_frame
		if reel._committed:
			break
	check("match ended in CLEAR after the finale", gs.game_state == Constants.STATE_CLEAR, gs.game_state)
	check("record committed", reel._committed)
	for frame in range(120):
		await get_tree().process_frame
		if FileAccess.file_exists(MatchHistory.path()):
			break
	await frames(30)
	var records := MatchHistory.load_records()
	check("one match in the history", records.size() == 1, records.size())
	var record: Dictionary = records[0] if not records.is_empty() else {}
	check("record: 2P ten, P1 won 28 to the ghost's 9",
		int(record.get("players", 0)) == 2 and record.get("mode") == Constants.MODE_TEN
		and int(record.get("winner", -1)) == 1
		and (record.get("points", []) as Array).map(func(v: Variant) -> int: return int(v)) == [56, 18], record)
	var players: Array = record.get("p", [])
	check("record: correct counts, P1 streak, P2 out",
		players.size() == 2 and int(players[0].correct) == 8 and int(players[1].correct) == 9
		and int(players[0].best_streak) == 3 and not bool(players[1].alive), players)
	var clips := HighlightStore.list()
	var kinds: Array[String] = []
	for clip: Dictionary in clips:
		for event: Dictionary in clip.get("events", []):
			kinds.append("%s:P%d" % [event.kind, int(event.player)])
	check("every moment kept: the streak, the fall, the bite, the win",
		"streak:P1" in kinds and "ocean:P2" in kinds and "shark:P2" in kinds and "win:P1" in kinds, kinds)
	var groups := HighlightStore.by_match(clips)
	check("clips in match order", groups.size() == 1 and (groups[0] as Array).map(func(c: Dictionary) -> String: return str(c.kind)).front() == "streak",
		(groups[0] as Array).map(func(c: Dictionary) -> String: return str(c.kind)) if not groups.is_empty() else [])
	check("record lists its clips", (record.get("highlights", []) as Array).size() == clips.size(), record.get("highlights"))
	var sheet := 0
	for clip: Dictionary in clips:
		var times: Array = clip.get("times", [])
		var images := HighlightStore.load_frames(clip)
		var length := float(times[times.size() - 1]) if not times.is_empty() else 0.0
		check("clip %s: frames decode" % clip.kind, images.size() == times.size() and images.size() >= 8,
			"%d of %d" % [images.size(), times.size()])
		var events: Array = clip.get("events", [])
		check("clip %s: 2..8 s long, its moments inside" % clip.kind,
			length >= 2.0 and length <= HighlightCapture.MAX_CLIP_SECONDS + 0.2 and not events.is_empty()
			and events.all(func(event: Dictionary) -> bool: return float(event.t) > 0.5 and float(event.t) < length),
			"%.2f s, events %s" % [length, events])
		if not images.is_empty():
			var middle := images[images.size() / 2]
			check("clip %s: frame is a real render (%dx%d, not flat)" % [clip.kind, middle.get_width(), middle.get_height()],
				middle.get_size() == HighlightCapture.SIZE and _spread(middle) > 0.08, _spread(middle))
			_save_sheet(images, OUT + "clip_%d_%s.png" % [sheet, clip.kind])
			sheet += 1
	finish()


## Keeps both runners short of the goal while the test waits (the race carries them on).
func _hold_back() -> void:
	gs.player_z = gs.goal_z - 12.0
	if gs.p2_alive and not gs.p2_waiting_for_shark:
		gs.player2_z = gs.goal_z - 12.0


func _mean(samples: Array[Vector2]) -> Array[float]:
	var total := Vector2.ZERO
	for sample: Vector2 in samples:
		total += sample
	total /= maxf(1.0, float(samples.size()))
	return [snappedf(total.x, 0.01), snappedf(total.y, 0.01)]


func _spread(image: Image) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in range(8, image.get_height(), 24):
		for x in range(8, image.get_width(), 24):
			var v := image.get_pixel(x, y).get_luminance()
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi - lo


func _save_sheet(images: Array[Image], path: String) -> void:
	var cols := 6
	var step := maxi(1, images.size() / 12)
	var picked: Array[Image] = []
	for index in range(0, images.size(), step):
		picked.append(images[index])
	var w := HighlightCapture.SIZE.x / 2
	var h := HighlightCapture.SIZE.y / 2
	var rows := (picked.size() + cols - 1) / cols
	var sheet := Image.create(cols * w, rows * h, false, Image.FORMAT_RGBA8)
	for index in range(picked.size()):
		var frame := picked[index].duplicate() as Image
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i((index % cols) * w, (index / cols) * h))
	sheet.save_png(ProjectSettings.globalize_path(path))


func _clear_store() -> void:
	var root := ProjectSettings.globalize_path(STORE)
	if not DirAccess.dir_exists_absolute(root):
		return
	for folder: String in DirAccess.get_directories_at(root + "/highlights"):
		for file_name: String in DirAccess.get_files_at(root + "/highlights/" + folder):
			DirAccess.remove_absolute(root + "/highlights/" + folder + "/" + file_name)
		DirAccess.remove_absolute(root + "/highlights/" + folder)
	for sub in ["/highlights", ""]:
		for file_name: String in DirAccess.get_files_at(root + sub):
			DirAccess.remove_absolute(root + sub + "/" + file_name)


func frames(count: int) -> void:
	for frame in range(count):
		await get_tree().process_frame


func finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "perf": perf}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("MATCH_REEL_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "failures": failures, "perf": perf}))
	get_tree().quit(0 if failures.is_empty() else 1)
