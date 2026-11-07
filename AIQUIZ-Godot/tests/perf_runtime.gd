extends Node

## Runtime performance harness (added to the root by tests/perf_*_bootstrap.gd).
##
## Both measures boot like the real game (ui/startup_loading.tscn: resource loading and the
## visual warm-up), land in ui/main_menu.tscn and start ENDLESS (1P, OFFLINE) through the
## menu's own start (MainMenu._on_start_pressed: helicopter departure, cover, start_game(),
## game_world.tscn), then press Enter at WAITING_START. tests/perf_autoplay.gd steers into
## the correct door; tests/perf_frame_sampler.gd records every frame.
##
## endless    : one run until --walls (60) walls are passed or --max_play_seconds (300).
## multimatch : --matches (5) matches of --play_seconds (60) each; leaves through the pause
##              menu's "タイトルに戻る" (PauseTitleButton) back to the main menu, waits
##              --menu_seconds (5) there and snapshots memory / signals / tree / orphans.
##
## Common args: --label=<name> (output suffix, default "run"), --quality=<low|balanced|high|ultra>,
##   --max_fps=<n>, --window=<WxH> (default 1280x720), --seed=<n>, --start=menu|direct,
##   --frames=0 (skip the per-frame file), --subject/--grade/--difficulty.

const Util := preload("res://tests/perf_util.gd")
const SamplerScript := preload("res://tests/perf_frame_sampler.gd")
const AutoplayScript := preload("res://tests/perf_autoplay.gd")

const MENU_PATH := "res://ui/main_menu.tscn"
const STARTUP_PATH := "res://ui/startup_loading.tscn"
const HITCH_MS := 33.0
const THRESHOLDS: Array[float] = [25.0, 33.0, 50.0, 100.0]
const PHASE_IDLE := 0
const PHASE_BOOT := 1
const PHASE_MENU := 2
const PHASE_TO_MATCH := 3
const PHASE_PLAY := 4
const PHASE_LEAVE := 5
const STATE_PLAYING_CODE := 5

var info: Dictionary = {}
var args: Dictionary = {}
var sampler: SamplerScript
var autoplay: AutoplayScript
var gs: QuizGameState
var errors: Array[String] = []
var notes: Array[String] = []
var result: Dictionary = {}
var timings: Dictionary = {}
var _t0_ms := 0
var _deadline_ms := 0
var _aborted := false
var _done := false
var _unfocused_frames := 0
var _pre_enter_snapshot: Dictionary = {}


func configure(i: Dictionary, a: Dictionary) -> void:
	info = i
	args = a


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _process(_delta: float) -> void:
	if _done or _deadline_ms == 0:
		return
	if not DisplayServer.window_is_focused():
		_unfocused_frames += 1
	if Time.get_ticks_msec() > _deadline_ms and not _aborted:
		_aborted = true
		_err("watchdog: run exceeded %d s, writing partial results" % int((_deadline_ms - _t0_ms) / 1000))
		_finish()


func _err(message: String) -> void:
	errors.append(message)
	push_error("[perf] " + message)


func _log(message: String) -> void:
	print("[perf %6.1fs] %s" % [float(Time.get_ticks_msec() - _t0_ms) / 1000.0, message])


func measure() -> String:
	return String(info.get("measure", "endless"))


func label() -> String:
	return String(args.get("label", "run"))


# ------------------------------------------------------------------ main flow

func _run() -> void:
	_t0_ms = Time.get_ticks_msec()
	var default_limit := 900 if measure() == "endless" else 1500
	_deadline_ms = _t0_ms + Util.arg_int(args, "watchdog_seconds", default_limit) * 1000
	gs = QuizManager.game_state
	seed(Util.arg_int(args, "seed", 1234))
	_setup_window()
	sampler = SamplerScript.new()
	sampler.name = "PerfSampler"
	get_tree().root.add_child(sampler)
	autoplay = AutoplayScript.new()
	autoplay.name = "PerfAutoplay"
	autoplay.rush = String(args.get("rush", "1")) != "0"
	get_tree().root.add_child(autoplay)
	result["environment"] = _environment()
	_log("measure=%s label=%s env=%s" % [measure(), label(), JSON.stringify(result["environment"])])
	sampler.recording = true
	sampler.phase = PHASE_BOOT
	var booted := await _boot_to_menu()
	if booted and not _aborted:
		match measure():
			"endless":
				await _run_endless()
			"multimatch":
				await _run_multimatch()
			_:
				_err("unknown measure " + measure())
	if not _aborted:
		_finish()


func _setup_window() -> void:
	var size := Vector2i(1280, 720)
	var parts := String(args.get("window", "1280x720")).split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		size = Vector2i(int(parts[0]), int(parts[1]))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)


func _git_head() -> String:
	var out: Array = []
	var code := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out)
	return String(out[0]).strip_edges() if code == 0 and not out.is_empty() else ""


func _environment() -> Dictionary:
	return {
		"godot": Engine.get_version_info().get("string", ""),
		"debug_build": OS.is_debug_build(),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"cpu": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"os": OS.get_name() + " " + OS.get_version(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"window_size": str(DisplayServer.window_get_size()),
		"engine_max_fps": Engine.max_fps,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"graphics_quality": String(GameManager.graphics_quality),
		"settings_path": String(GameManager.settings_path),
		"harness_settings": info.get("harness_settings", {}),
		"player_settings_read_only": info.get("player_settings", {}),
		"settings_hooked_before_ready": info.get("settings_hooked_before_ready", false),
		"network_env": {"PROXY_URL": OS.get_environment("PROXY_URL"), "FIREBASE_DB_URL": OS.get_environment("FIREBASE_DB_URL")},
		"git_head": _git_head(),
		"args": args,
	}


func _boot_to_menu() -> bool:
	var started := Time.get_ticks_msec()
	_log("booting through %s" % STARTUP_PATH)
	get_tree().change_scene_to_file(STARTUP_PATH)
	if not await _wait_until(_menu_ready, 240.0):
		_err("main menu did not become ready after boot")
		return false
	timings["boot_to_menu_s"] = Util.r2(float(Time.get_ticks_msec() - started) / 1000.0)
	result["startup_report"] = GameManager.startup_report.duplicate(true)
	_log("main menu ready (%.1fs)" % timings["boot_to_menu_s"])
	sampler.phase = PHASE_MENU
	await _wait_seconds(Util.arg_float(args, "menu_settle_seconds", 3.0))
	return true


func _menu_ready() -> bool:
	var scene := get_tree().current_scene
	return (
		scene != null
		and scene.scene_file_path == MENU_PATH
		and not GameManager.startup_loading
		and not SceneTransition.is_transitioning()
	)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.name == "GameWorld" else null


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not bool(cond.call()):
		if _aborted or Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not _aborted:
		await get_tree().process_frame


func _press_key(key: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _configure_round() -> void:
	gs.mode = Constants.MODE_ENDLESS
	gs.num_players = 1
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.llm_mode = "OFFLINE"
	if args.has("subject"):
		gs.subject = String(args["subject"])
	if args.has("grade"):
		gs.grade = int(args["grade"])
	if args.has("difficulty"):
		gs.difficulty = String(args["difficulty"])
	gs.menu_step = Constants.MENU_STEP_CONFIG


## Main menu -> GameWorld -> Enter -> PLAYING. Sets sampler.play_origin_us at PLAYING.
func _start_match(match_no: int, snapshot_before_enter: bool) -> bool:
	sampler.phase = PHASE_TO_MATCH
	var t_start := Time.get_ticks_msec()
	var menu := get_tree().current_scene
	if menu == null or menu.scene_file_path != MENU_PATH:
		_err("match %d: not in the main menu" % match_no)
		return false
	_configure_round()
	if menu.has_method("_update_ui"):
		menu.call("_update_ui")
	var start_mode := String(args.get("start", "menu"))
	if start_mode == "direct":
		gs.start_game()
		gs.skip_start_helicopter_arrival = true
		GameManager.start_game()
	else:
		await _wait_until(func() -> bool:
			if not is_instance_valid(menu):
				return true
			var conveyor: Variant = menu.get("config_conveyor")
			var moving := conveyor != null and is_instance_valid(conveyor) and bool((conveyor as Object).call("is_moving"))
			return not bool(menu.get("_menu_exit_in_progress")) and not moving, 15.0)
		menu.call("_on_start_pressed")
	if not await _wait_until(func() -> bool: return _world() != null, 90.0):
		_err("match %d: GameWorld never loaded" % match_no)
		return false
	var t_world := Time.get_ticks_msec()
	if not await _wait_until(func() -> bool:
		var w := _world()
		return w != null and gs.game_state == Constants.STATE_WAITING_START and bool(w.call("_can_trigger_start")), 150.0):
		_err("match %d: never ready to start (state %s)" % [match_no, gs.game_state])
		return false
	var t_ready := Time.get_ticks_msec()
	if snapshot_before_enter:
		_pre_enter_snapshot = _snapshot(true, "waiting_start")
	var started := false
	for attempt in range(6):
		await _press_key(KEY_ENTER)
		if await _wait_until(func() -> bool: return gs.game_state in [Constants.STATE_COUNTDOWN, Constants.STATE_FLYOVER, Constants.STATE_PLAYING], 3.0):
			started = true
			break
	if not started:
		notes.append("match %d: Enter did not start the round; called game_state.trigger_start()" % match_no)
		gs.trigger_start()
	if not await _wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 40.0):
		_err("match %d: never reached PLAYING (state %s)" % [match_no, gs.game_state])
		return false
	sampler.play_origin_us = Time.get_ticks_usec()
	sampler.phase = PHASE_PLAY
	var t_play := Time.get_ticks_msec()
	timings["match_%d" % match_no] = {
		"menu_to_world_s": Util.r2(float(t_world - t_start) / 1000.0),
		"world_to_ready_s": Util.r2(float(t_ready - t_world) / 1000.0),
		"ready_to_playing_s": Util.r2(float(t_play - t_ready) / 1000.0),
	}
	_log("match %d PLAYING (menu->world %.1fs, world->ready %.1fs)" % [match_no, float(t_world - t_start) / 1000.0, float(t_ready - t_world) / 1000.0])
	return true


## Pause (Esc) -> "タイトルに戻る" -> main menu.
func _leave_match(match_no: int) -> bool:
	sampler.phase = PHASE_LEAVE
	autoplay.set_enabled(false)
	var w := _world()
	if w == null:
		_err("match %d: no GameWorld to leave" % match_no)
		return false
	await _press_key(KEY_ESCAPE)
	if not await _wait_until(func() -> bool: return get_tree().paused, 2.0):
		notes.append("match %d: Esc did not pause; called GameWorld._toggle_pause()" % match_no)
		w.call("_toggle_pause")
		await _wait_until(func() -> bool: return get_tree().paused, 2.0)
	await _wait_seconds(0.5)
	var button: Variant = w.get("_pause_title_button")
	if not (button is Object) or not is_instance_valid(button) or not (button as Object).has_signal("pressed"):
		_err("match %d: pause title button not found" % match_no)
		return false
	(button as Object).emit_signal("pressed")
	var t_leave := Time.get_ticks_msec()
	if not await _wait_until(func() -> bool: return _menu_ready() and _world() == null, 90.0):
		_err("match %d: did not return to the main menu" % match_no)
		return false
	timings["leave_%d_s" % match_no] = Util.r2(float(Time.get_ticks_msec() - t_leave) / 1000.0)
	sampler.phase = PHASE_MENU
	sampler.play_origin_us = -1
	return true


# ------------------------------------------------------------------ measure A

func _run_endless() -> void:
	var target_walls := Util.arg_int(args, "walls", 60)
	var max_play := Util.arg_float(args, "max_play_seconds", 300.0)
	sampler.match_index = 0
	if not await _start_match(0, true):
		return
	autoplay.set_enabled(true)
	var start_ms := Time.get_ticks_msec()
	var end_reason := ""
	var last_logged := -1
	while not _aborted:
		await get_tree().process_frame
		if gs.current_wall_index != last_logged and gs.current_wall_index % 5 == 0:
			last_logged = gs.current_wall_index
			_log("endless wall %d, fps %d, nodes %d" % [gs.current_wall_index, Engine.get_frames_per_second(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		if gs.current_wall_index >= target_walls:
			end_reason = "walls_reached"
			break
		if float(Time.get_ticks_msec() - start_ms) / 1000.0 >= max_play:
			end_reason = "max_play_seconds"
			break
		if gs.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR, Constants.STATE_MENU]:
			end_reason = "state_" + String(gs.game_state)
			break
		if _world() == null:
			end_reason = "left_world"
			break
	autoplay.set_enabled(false)
	var play_seconds := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var end_snapshot := _snapshot(true, "endless_end")
	sampler.recording = false
	result["endless"] = _summarize_endless(end_reason, play_seconds, target_walls, end_snapshot)
	_log("endless done: %s, walls %d, %.1fs" % [end_reason, gs.current_wall_index, play_seconds])


func _summarize_endless(end_reason: String, play_seconds: float, target_walls: int, end_snapshot: Dictionary) -> Dictionary:
	var idx := _indices(func(i: int) -> bool:
		return sampler.phase_code[i] == PHASE_PLAY and sampler.state_code[i] == STATE_PLAYING_CODE and sampler.play_t[i] >= 0.0)
	var idx_after5 := _indices(func(i: int) -> bool:
		return sampler.phase_code[i] == PHASE_PLAY and sampler.state_code[i] == STATE_PLAYING_CODE and sampler.play_t[i] >= 5.0)
	_set_segment_medians(idx)
	var hitches := _hitch_indices(idx)
	var walls_passed := gs.current_wall_index
	var per_wall := _per_wall(idx)
	var play_states := []
	for entry: Array in sampler.state_log:
		if int(entry[3]) == 0:
			play_states.append(entry)
	return {
		"end_reason": end_reason,
		"target_walls": target_walls,
		"walls_passed": walls_passed,
		"play_seconds": Util.r2(play_seconds),
		"hp_left": gs.get_player_hp(1),
		"score": gs.score,
		"autoplay": autoplay.report(),
		"frames_playing": _window_stats(idx),
		"frames_playing_after_5s": _window_stats(idx_after5),
		"hitch_threshold_ms": HITCH_MS,
		"hitches_total": hitches.size(),
		"hitches_per_wall": Util.r3(float(hitches.size()) / float(maxi(1, walls_passed))),
		"hitch_correlation": _hitch_correlation(idx, hitches),
		"hitch_attribution": _hitch_attribution(hitches),
		"event_costs": _event_costs(idx),
		"hitch_timing_since_wall_change": _hitch_timing(idx, hitches),
		"worst_frames": _worst_frames(idx, 40),
		"hitch_list": _hitch_contexts(hitches, 300),
		"per_wall": per_wall,
		"trend_first10_vs_last10": _trend(per_wall),
		"state_transitions_during_play": play_states,
		"slow_samples": sampler.slow,
		"snapshot_waiting_start": _pre_enter_snapshot,
		"snapshot_end": end_snapshot,
		"growth_waiting_start_to_end": _growth(_pre_enter_snapshot, end_snapshot),
	}


# ------------------------------------------------------------------ measure B

func _run_multimatch() -> void:
	var matches := Util.arg_int(args, "matches", 5)
	var play_s := Util.arg_float(args, "play_seconds", 60.0)
	var w0 := Util.arg_float(args, "window_start", 15.0)
	var w1 := Util.arg_float(args, "window_end", 45.0)
	var menu_s := Util.arg_float(args, "menu_seconds", 5.0)
	var snap_at := minf(play_s - 2.0, w1 + 5.0)
	var visits: Array = []
	var match_rows: Array = []
	sampler.match_index = -1
	visits.append(await _menu_visit(0, menu_s))
	for m in range(matches):
		if _aborted:
			break
		sampler.match_index = m
		if not await _start_match(m, false):
			break
		autoplay.set_enabled(true)
		var in_match: Dictionary = {}
		var end_reason := "play_seconds"
		while not _aborted:
			await get_tree().process_frame
			var t := float(Time.get_ticks_usec() - sampler.play_origin_us) / 1e6
			if in_match.is_empty() and t >= snap_at:
				in_match = _snapshot(true, "in_match_%d" % m)
			if t >= play_s:
				break
			if gs.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR, Constants.STATE_MENU] or _world() == null:
				end_reason = "state_" + String(gs.game_state)
				break
		var walls_passed := gs.current_wall_index
		var hp := gs.get_player_hp(1)
		autoplay.set_enabled(false)
		_log("match %d played: walls %d hp %d (%s)" % [m, walls_passed, hp, end_reason])
		if end_reason != "play_seconds":
			_err("match %d ended early: %s" % [m, end_reason])
		var left := await _leave_match(m)
		match_rows.append({"match": m, "walls_passed": walls_passed, "hp_left": hp, "end_reason": end_reason, "in_match_snapshot": in_match})
		if not left:
			break
		visits.append(await _menu_visit(m + 1, menu_s))
	sampler.recording = false
	# Debug builds list every orphan node on stdout (see the log).
	print("[perf] ===== print_orphan_nodes() BEGIN =====")
	Node.print_orphan_nodes()
	print("[perf] ===== print_orphan_nodes() END =====")
	result["multimatch"] = _summarize_multimatch(match_rows, visits, w0, w1, play_s)


func _menu_visit(visit: int, seconds: float) -> Dictionary:
	sampler.phase = PHASE_MENU
	var first := sampler.frame_count()
	await _wait_seconds(seconds)
	var last := sampler.frame_count()
	var idx := PackedInt32Array()
	# Skip the first second (the menu's entrance tween and scene teardown).
	for i in range(first, last):
		if sampler.t_s[i] - sampler.t_s[first] >= 1.0:
			idx.append(i)
	var snap := _snapshot(true, "menu_%d" % visit)
	_log("menu visit %d: nodes %d objects %d orphans %d resources %d static %.1fMB" % [
		visit, snap["perf"]["node_count"], snap["perf"]["object_count"], snap["perf"]["orphan_node_count"],
		snap["perf"]["resource_count"], snap["perf"]["memory_static_mb"]])
	return {"visit": visit, "after_match": visit - 1, "frames": _window_stats(idx), "snapshot": snap}


func _summarize_multimatch(match_rows: Array, visits: Array, w0: float, w1: float, play_s: float) -> Dictionary:
	var per_match: Array = []
	for row: Dictionary in match_rows:
		var m := int(row["match"])
		var idx := _indices(func(i: int) -> bool:
			return sampler.match_code[i] == m and sampler.phase_code[i] == PHASE_PLAY and sampler.state_code[i] == STATE_PLAYING_CODE and sampler.play_t[i] >= w0 and sampler.play_t[i] < w1)
		var full := _indices(func(i: int) -> bool:
			return sampler.match_code[i] == m and sampler.phase_code[i] == PHASE_PLAY and sampler.state_code[i] == STATE_PLAYING_CODE and sampler.play_t[i] >= 3.0 and sampler.play_t[i] < minf(play_s, w1 + 4.0))
		_set_segment_medians(idx)
		var hitches := _hitch_indices(idx)
		var entry := {
			"match": m,
			"walls_passed": row["walls_passed"],
			"hp_left": row["hp_left"],
			"end_reason": row["end_reason"],
			"window_s": [w0, w1],
			"window": _window_stats(idx),
			"window_hitch_correlation": _hitch_correlation(idx, hitches),
			"window_hitch_attribution": _hitch_attribution(hitches),
			"window_event_costs": _event_costs(idx),
			"play_3s_to_window_end_plus_4s": _window_stats(full),
			"timings": timings.get("match_%d" % m, {}),
		}
		var snap: Dictionary = row.get("in_match_snapshot", {})
		if not snap.is_empty():
			entry["in_match_snapshot"] = _light(snap)
			entry["in_match_census_top"] = _top_counts(snap.get("census", {}), 25)
		per_match.append(entry)
	var menu_rows: Array = []
	for v: Dictionary in visits:
		var snap: Dictionary = v["snapshot"]
		menu_rows.append({"visit": v["visit"], "after_match": v["after_match"], "frames": v["frames"], "snapshot": _light(snap)})
	var deltas: Array = []
	for i in range(1, visits.size()):
		var a: Dictionary = visits[i - 1]["snapshot"]
		var b: Dictionary = visits[i]["snapshot"]
		deltas.append({"from_visit": i - 1, "to_visit": i, "growth": _growth(a, b, 15)})
	var in_match_deltas: Array = []
	for i in range(1, match_rows.size()):
		var a: Dictionary = match_rows[i - 1].get("in_match_snapshot", {})
		var b: Dictionary = match_rows[i].get("in_match_snapshot", {})
		if not a.is_empty() and not b.is_empty():
			in_match_deltas.append({"from_match": i - 1, "to_match": i, "growth": _growth(a, b, 15)})
	var total := {}
	if visits.size() >= 2:
		total = _growth(visits[0]["snapshot"], visits[visits.size() - 1]["snapshot"], 40)
	var final_orphans := Util.orphan_census(5)
	return {
		"matches_completed": match_rows.size(),
		"per_match": per_match,
		"trend_per_match": _match_trend(per_match, menu_rows),
		"menu_visits": menu_rows,
		"menu_deltas_per_match": deltas,
		"menu_growth_total_first_to_last": total,
		"in_match_deltas_per_match": in_match_deltas,
		"orphans_final": final_orphans,
		"orphans_final_top": _top_groups(final_orphans, 40),
	}


func _match_trend(per_match: Array, menu_rows: Array) -> Dictionary:
	var xs: Array = []
	var dt_mean: Array = []
	var dt_p95: Array = []
	var dt_p99: Array = []
	var proc_mean: Array = []
	var hitches: Array = []
	for e: Dictionary in per_match:
		var w: Dictionary = e["window"]
		if int(w.get("frames", 0)) == 0:
			continue
		xs.append(e["match"])
		dt_mean.append(w["dt_ms"]["mean"])
		dt_p95.append(w["dt_ms"]["p95"])
		dt_p99.append(w["dt_ms"]["p99"])
		proc_mean.append(w["process_ms"]["mean"])
		hitches.append(w["over_33ms"])
	var mx: Array = []
	var series := {}
	for key: String in ["node_count", "object_count", "orphan_node_count", "resource_count", "memory_static_mb", "video_mem_mb"]:
		series[key] = []
	var signal_series := {}
	for row: Dictionary in menu_rows:
		mx.append(row["visit"])
		var perf: Dictionary = row["snapshot"]["perf"]
		for key: String in series.keys():
			(series[key] as Array).append(perf.get(key, 0))
		var totals: Dictionary = row["snapshot"]["signal_totals"]
		for k: String in totals.keys():
			if not signal_series.has(k):
				signal_series[k] = []
			(signal_series[k] as Array).append(totals[k])
	var menu_slopes := {}
	for key: String in series.keys():
		menu_slopes[key + "_per_match"] = Util.r3(Util.slope(mx, series[key]))
	var signal_slopes := {}
	for k: String in signal_series.keys():
		var s := Util.slope(mx, signal_series[k])
		if absf(s) > 0.0001:
			signal_slopes[k + "_per_match"] = Util.r3(s)
	return {
		"window_dt_mean_ms": dt_mean, "window_dt_p95_ms": dt_p95, "window_dt_p99_ms": dt_p99,
		"window_proc_mean_ms": proc_mean, "window_frames_over_33ms": hitches,
		"window_dt_mean_slope_ms_per_match": Util.r3(Util.slope(xs, dt_mean)),
		"window_dt_p95_slope_ms_per_match": Util.r3(Util.slope(xs, dt_p95)),
		"window_proc_mean_slope_ms_per_match": Util.r3(Util.slope(xs, proc_mean)),
		"menu_series": series,
		"menu_slopes": menu_slopes,
		"menu_signal_total_slopes": signal_slopes,
	}


# ------------------------------------------------------------------ snapshots

func _watched_objects() -> Dictionary:
	var root := get_tree().root
	var objs := {"game_state": gs, "tree": get_tree(), "root_window": root}
	for n: String in ["GameManager", "QuizManager", "AudioManager", "SceneTransition", "TouchControls",
			"ApiStatusAutoload", "LiveConfigManager", "NetworkManager", "GraphicsQuality", "SafeArea", "MobileLifecycle"]:
		objs[n] = root.get_node_or_null(n)
	objs["provider"] = QuizManager.provider
	objs["firebase_quiz_cache"] = QuizManager.firebase_quiz_cache
	objs["player_analytics"] = QuizManager.player_analytics
	objs["quiz_optimizer"] = QuizManager.quiz_optimizer
	return objs


func _snapshot(with_census: bool, tag: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var root := get_tree().root
	var scene := get_tree().current_scene
	var children := {}
	var root_count := 0
	for child: Node in root.get_children():
		if Util.is_harness_object(child):
			continue
		root_count += 1
		children[String(child.name)] = Util.count_descendants(child)
	var signals := {}
	var signal_totals := {}
	var objs := _watched_objects()
	for key: String in objs.keys():
		var rep := Util.connection_report(objs[key])
		signals[key] = rep
		signal_totals[key] = rep.get("total", -1)
	var audio := root.get_node_or_null("AudioManager")
	var snap := {
		"tag": tag,
		"t": Util.r2(float(Time.get_ticks_msec() - _t0_ms) / 1000.0),
		"scene": scene.scene_file_path if scene != null else "",
		"state": String(gs.game_state),
		"perf": Util.perf_numbers(),
		"root_child_count": root_count,
		"root_children_descendants": children,
		"audio_manager_child_count": audio.get_child_count() if audio != null else -1,
		"signal_totals": signal_totals,
		"signals": signals,
		"containers": {
			"game_state": Util.container_sizes(gs),
			"provider": Util.container_sizes(QuizManager.provider),
			"firebase_quiz_cache": Util.container_sizes(QuizManager.firebase_quiz_cache),
			"player_analytics": Util.container_sizes(QuizManager.player_analytics),
			"quiz_optimizer": Util.container_sizes(QuizManager.quiz_optimizer),
		},
	}
	if with_census:
		snap["census"] = Util.tree_census(root)
		snap["orphans"] = Util.orphan_census()
	snap["probe_ms"] = Util.r2(float(Time.get_ticks_usec() - started) / 1000.0)
	return snap


## Snapshot without the bulky maps (for per-row reporting).
func _light(snap: Dictionary) -> Dictionary:
	var out := {}
	for k: String in ["tag", "t", "scene", "state", "perf", "root_child_count", "root_children_descendants", "audio_manager_child_count", "signal_totals", "probe_ms"]:
		out[k] = snap.get(k)
	var orphans: Dictionary = snap.get("orphans", {})
	out["orphan_groups"] = (orphans.get("groups", {}) as Dictionary).size()
	return out


func _flat_signal_targets(snap: Dictionary) -> Dictionary:
	var out := {}
	var signals: Dictionary = snap.get("signals", {})
	for obj: String in signals.keys():
		var targets: Dictionary = (signals[obj] as Dictionary).get("targets", {})
		for k: String in targets.keys():
			out[obj + ": " + k] = targets[k]
	return out


func _flat_containers(snap: Dictionary) -> Dictionary:
	var out := {}
	var containers: Dictionary = snap.get("containers", {})
	for obj: String in containers.keys():
		var sizes: Dictionary = containers[obj]
		for k: String in sizes.keys():
			out[obj + "." + k] = sizes[k]
	return out


func _numeric_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k: String in b.keys():
		var va: Variant = a.get(k)
		var vb: Variant = b.get(k)
		if (va is int or va is float) and (vb is int or vb is float):
			out[k] = Util.r3(float(vb) - float(va)) if (va is float or vb is float) else int(vb) - int(va)
	return out


func _growth(a: Dictionary, b: Dictionary, limit: int = 25) -> Dictionary:
	if a.is_empty() or b.is_empty():
		return {}
	var out := {
		"perf": _numeric_delta(a.get("perf", {}), b.get("perf", {})),
		"root_child_count": int(b.get("root_child_count", 0)) - int(a.get("root_child_count", 0)),
		"audio_manager_child_count": int(b.get("audio_manager_child_count", 0)) - int(a.get("audio_manager_child_count", 0)),
		"signal_totals": _numeric_delta(a.get("signal_totals", {}), b.get("signal_totals", {})),
		"root_children_descendants": Util.top_deltas(a.get("root_children_descendants", {}), b.get("root_children_descendants", {}), limit),
		"signal_targets": Util.top_deltas(_flat_signal_targets(a), _flat_signal_targets(b), limit),
		"containers": Util.top_deltas(_flat_containers(a), _flat_containers(b), limit),
	}
	if a.has("census") and b.has("census"):
		out["tree_census"] = Util.top_deltas(a["census"], b["census"], limit)
	if a.has("orphans") and b.has("orphans"):
		out["orphans"] = Util.top_deltas(Util.orphan_counts(a["orphans"]), Util.orphan_counts(b["orphans"]), limit)
	return out


func _top_counts(counts: Dictionary, limit: int) -> Array:
	var rows := []
	for k: Variant in counts.keys():
		rows.append({"key": String(k), "count": int(counts[k])})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["count"]) > int(y["count"]))
	return rows.slice(0, limit)


func _top_groups(census: Dictionary, limit: int) -> Array:
	var rows := []
	var groups: Dictionary = census.get("groups", {})
	for k: Variant in groups.keys():
		var g: Dictionary = groups[k]
		rows.append({"key": String(k), "count": int(g["count"]), "descendants": int(g["descendants"]), "samples": g["samples"]})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["count"]) > int(y["count"]))
	return rows.slice(0, limit)


# ------------------------------------------------------------------ frame analysis

func _indices(pred: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := sampler.frame_count()
	for i in range(n):
		if bool(pred.call(i)):
			out.append(i)
	return out


func _hitch_indices(idx: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in idx:
		if sampler.dt_ms[i] > HITCH_MS:
			out.append(i)
	return out


func _window_stats(idx: PackedInt32Array) -> Dictionary:
	if idx.is_empty():
		return {"frames": 0}
	var dt := PackedFloat32Array()
	var proc := PackedFloat32Array()
	var post := PackedFloat32Array()
	var draw := PackedFloat32Array()
	var phys := PackedFloat32Array()
	var idle := PackedFloat32Array()
	var rcpu := PackedFloat32Array()
	var rgpu := PackedFloat32Array()
	var draws := 0.0
	var nodes := 0.0
	var seconds := 0.0
	for i: int in idx:
		dt.append(sampler.dt_ms[i])
		proc.append(sampler.process_ms[i])
		post.append(sampler.post_ms[i])
		draw.append(sampler.draw_ms[i])
		phys.append(sampler.physics_ms[i])
		idle.append(sampler.idle_ms[i])
		rcpu.append(sampler.render_cpu_ms[i])
		rgpu.append(sampler.render_gpu_ms[i])
		draws += sampler.draw_calls[i]
		nodes += sampler.node_count[i]
		seconds += sampler.dt_ms[i] / 1000.0
	var out := {
		"frames": idx.size(),
		"seconds": Util.r2(seconds),
		"avg_fps": Util.r2(float(idx.size()) / maxf(seconds, 0.001)),
		"dt_ms": Util.stats(dt),
		"process_ms": Util.stats(proc),
		"post_ms": Util.stats(post),
		"draw_ms": Util.stats(draw),
		"physics_ms": Util.stats(phys),
		"idle_ms": Util.stats(idle),
		"render_cpu_ms": Util.stats(rcpu),
		"render_gpu_ms": Util.stats(rgpu),
		"draw_calls_mean": Util.r2(draws / idx.size()),
		"node_count_mean": Util.r2(nodes / idx.size()),
	}
	for thr: float in THRESHOLDS:
		out["over_%dms" % int(thr)] = Util.count_over(dt, thr)
	return out


func _events_of(mask: int) -> Array:
	var names := []
	for bit: int in SamplerScript.EV_NAMES.keys():
		if (mask & bit) != 0:
			names.append(SamplerScript.EV_NAMES[bit])
	return names


func _hitch_contexts(hitches: PackedInt32Array, limit: int) -> Array:
	var rows := []
	for i: int in hitches:
		if rows.size() >= limit:
			break
		rows.append(_frame_context(i))
	return rows


func _frame_context(i: int) -> Dictionary:
	var prev := maxi(0, i - 1)
	var since_wall := _frames_since(i, SamplerScript.EV_WALL_INDEX, 600)
	var since_spawn := _frames_since(i, SamplerScript.EV_WALL_SPAWN, 600)
	var since_refill := _frames_since(i, SamplerScript.EV_PROVIDER_FETCH, 600)
	return {
		"frame": i,
		"t": Util.r3(sampler.t_s[i]),
		"play_t": Util.r2(sampler.play_t[i]),
		"dt_ms": Util.r2(sampler.dt_ms[i]),
		"process_ms": Util.r2(sampler.process_ms[i]),
		"post_ms": Util.r2(sampler.post_ms[i]),
		"draw_ms": Util.r2(sampler.draw_ms[i]),
		"physics_ms": Util.r2(sampler.physics_ms[i]),
		"idle_ms": Util.r2(sampler.idle_ms[i]),
		"cause": _cause(i),
		"render_cpu_ms": Util.r2(sampler.render_cpu_ms[i]),
		"render_gpu_ms": Util.r2(sampler.render_gpu_ms[i]),
		"wall_index": sampler.wall_index[i],
		"state": sampler.state_code[i],
		"wall_container_children": sampler.walls[i],
		"wall_container_delta": sampler.walls[i] - sampler.walls[prev],
		"nodes_added": sampler.nodes_added[i],
		"nodes_added_prev_frame": sampler.nodes_added[prev],
		"nodes_removed": sampler.nodes_removed[i],
		"node_count": sampler.node_count[i],
		"quiz_list": sampler.quiz_list_size[i],
		"quiz_list_delta": sampler.quiz_list_size[i] - sampler.quiz_list_size[prev],
		"pipelines": sampler.pipelines[i] + sampler.pipelines[prev],
		"draw_calls": sampler.draw_calls[i],
		"events": _events_of(sampler.events[i]),
		"events_prev_frame": _events_of(sampler.events[prev]),
		"frames_since_wall_index_change": since_wall,
		"frames_since_wall_spawn": since_spawn,
		"frames_since_provider_refill": since_refill,
	}


var _since_cache := {}
var _or_cache := {}


## Frames since `bit` was last seen at or before frame i (-1 if not within max_back).
func _frames_since(i: int, bit: int, max_back: int) -> int:
	if not _since_cache.has(bit) or (_since_cache[bit] as PackedInt32Array).size() != sampler.frame_count():
		var arr := PackedInt32Array()
		arr.resize(sampler.frame_count())
		var last := -1
		for k in range(arr.size()):
			if (sampler.events[k] & bit) != 0:
				last = k
			arr[k] = k - last if last >= 0 else -1
		_since_cache[bit] = arr
	var v: int = (_since_cache[bit] as PackedInt32Array)[i]
	return v if v >= 0 and v <= max_back else -1


## OR of the event masks of frames i-span .. i.
func _events_window(span: int) -> PackedInt32Array:
	if _or_cache.has(span) and (_or_cache[span] as PackedInt32Array).size() == sampler.frame_count():
		return _or_cache[span]
	var arr := PackedInt32Array()
	arr.resize(sampler.frame_count())
	for k in range(arr.size()):
		var m := 0
		for back in range(span + 1):
			if k - back >= 0:
				m |= sampler.events[k - back]
		arr[k] = m
	_or_cache[span] = arr
	return arr


func _worst_frames(idx: PackedInt32Array, limit: int) -> Array:
	var order: Array = Array(idx)
	order.sort_custom(func(a: int, b: int) -> bool: return sampler.dt_ms[a] > sampler.dt_ms[b])
	var rows := []
	for k in range(mini(limit, order.size())):
		rows.append(_frame_context(int(order[k])))
	return rows


## For each event: how often frames carrying it (in that frame or the one before) are hitches,
## compared with frames without it; and the share of all hitches that carry it.
## "near10" uses a 10-frame look-back instead (async costs such as first draws).
## Cost of the frames that carry each event (that frame only): how heavy each kind of
## event is on its own, independent of the hitch threshold.
func _event_costs(idx: PackedInt32Array) -> Dictionary:
	var out := {}
	for bit: int in SamplerScript.EV_NAMES.keys():
		var dt := PackedFloat32Array()
		var proc := PackedFloat32Array()
		var post := PackedFloat32Array()
		var draw := PackedFloat32Array()
		for i: int in idx:
			if (sampler.events[i] & bit) != 0:
				dt.append(sampler.dt_ms[i])
				proc.append(sampler.process_ms[i])
				post.append(sampler.post_ms[i])
				draw.append(sampler.draw_ms[i])
		if dt.is_empty():
			continue
		var sd := Util.stats(dt)
		var sp := Util.stats(proc)
		var spo := Util.stats(post)
		var sdr := Util.stats(draw)
		out[String(SamplerScript.EV_NAMES[bit])] = {
			"frames": dt.size(),
			"dt_mean": sd["mean"], "dt_p95": sd["p95"], "dt_max": sd["max"],
			"process_mean": sp["mean"], "process_max": sp["max"],
			"post_mean": spo["mean"], "post_max": spo["max"],
			"draw_mean": sdr["mean"], "draw_max": sdr["max"],
			"over_33ms": Util.count_over(dt, HITCH_MS),
		}
	return out


func _hitch_correlation(idx: PackedInt32Array, hitches: PackedInt32Array) -> Dictionary:
	var out := {}
	var total_frames := idx.size()
	var total_hitches := hitches.size()
	var hitch_set := {}
	for i: int in hitches:
		hitch_set[i] = true
	for bit: int in SamplerScript.EV_NAMES.keys():
		for span: int in [1, 10]:
			var window := _events_window(span)
			var with_frames := 0
			var with_hitches := 0
			for i: int in idx:
				if (window[i] & bit) != 0:
					with_frames += 1
					if hitch_set.has(i):
						with_hitches += 1
			if with_frames == 0:
				continue
			var without_frames := total_frames - with_frames
			var key := String(SamplerScript.EV_NAMES[bit]) + ("" if span == 1 else "_near10")
			out[key] = {
				"frames": with_frames,
				"hitches": with_hitches,
				"hitch_rate_with": Util.r3(float(with_hitches) / float(with_frames)),
				"hitch_rate_without": Util.r3(float(total_hitches - with_hitches) / float(maxi(1, without_frames))),
				"share_of_hitches": Util.r3(float(with_hitches) / float(maxi(1, total_hitches))),
			}
	return out


## Baseline (median) of each frame segment over the measured frames, for _cause().
var _segment_medians := {"process": 0.0, "post": 0.0, "draw": 0.0, "physics": 0.0, "idle": 0.0}


func _set_segment_medians(idx: PackedInt32Array) -> void:
	var proc := PackedFloat32Array()
	var post := PackedFloat32Array()
	var draw := PackedFloat32Array()
	var phys := PackedFloat32Array()
	var idle := PackedFloat32Array()
	for i: int in idx:
		proc.append(sampler.process_ms[i])
		post.append(sampler.post_ms[i])
		draw.append(sampler.draw_ms[i])
		phys.append(sampler.physics_ms[i])
		idle.append(sampler.idle_ms[i])
	for pair: Array in [["process", proc], ["post", post], ["draw", draw], ["physics", phys], ["idle", idle]]:
		var arr: PackedFloat32Array = pair[1]
		arr.sort()
		_segment_medians[pair[0]] = Util.percentile_sorted(arr, 0.5)


## The frame segment with the largest excess over its median (process = scripts/_process,
## post = deferred calls / queue_free / timers / tweens, draw = rendering + present,
## physics, idle = limiter sleep / input / coroutines).
func _cause(i: int) -> String:
	var excess := {
		"process": sampler.process_ms[i] - float(_segment_medians["process"]),
		"post": sampler.post_ms[i] - float(_segment_medians["post"]),
		"draw": sampler.draw_ms[i] - float(_segment_medians["draw"]),
		"physics": sampler.physics_ms[i] - float(_segment_medians["physics"]),
		"idle": sampler.idle_ms[i] - float(_segment_medians["idle"]),
	}
	var best := "process"
	for k: String in excess.keys():
		if float(excess[k]) > float(excess[best]):
			best = k
	return best


func _hitch_attribution(hitches: PackedInt32Array) -> Dictionary:
	var counts := {"process": 0, "post": 0, "draw": 0, "physics": 0, "idle": 0}
	var excess_ms := {"process": 0.0, "post": 0.0, "draw": 0.0, "physics": 0.0, "idle": 0.0}
	var with_pipeline := 0
	for i: int in hitches:
		var c := _cause(i)
		counts[c] = int(counts[c]) + 1
		excess_ms["process"] = float(excess_ms["process"]) + maxf(0.0, sampler.process_ms[i] - float(_segment_medians["process"]))
		excess_ms["post"] = float(excess_ms["post"]) + maxf(0.0, sampler.post_ms[i] - float(_segment_medians["post"]))
		excess_ms["draw"] = float(excess_ms["draw"]) + maxf(0.0, sampler.draw_ms[i] - float(_segment_medians["draw"]))
		excess_ms["physics"] = float(excess_ms["physics"]) + maxf(0.0, sampler.physics_ms[i] - float(_segment_medians["physics"]))
		excess_ms["idle"] = float(excess_ms["idle"]) + maxf(0.0, sampler.idle_ms[i] - float(_segment_medians["idle"]))
		if sampler.pipelines[i] > 0:
			with_pipeline += 1
	for k: String in excess_ms.keys():
		excess_ms[k] = Util.r2(float(excess_ms[k]))
	return {
		"by_largest_segment": counts,
		"total_excess_ms_by_segment": excess_ms,
		"segment_medians_ms": _segment_medians.duplicate(),
		"hitches_with_pipeline_compilation": with_pipeline,
		"doc": "cause = frame segment with the largest excess over its median in the measured window",
	}


func _hitch_timing(idx: PackedInt32Array, hitches: PackedInt32Array) -> Dictionary:
	var buckets := {"0-1f": 0, "2-5f": 0, "6-30f": 0, "31-120f": 0, ">120f_or_none": 0}
	var base := buckets.duplicate()
	for pass_i in range(2):
		var src: PackedInt32Array = idx if pass_i == 0 else hitches
		var dst: Dictionary = base if pass_i == 0 else buckets
		for i: int in src:
			var f := _frames_since(i, SamplerScript.EV_WALL_INDEX, 120)
			var key := ">120f_or_none"
			if f >= 0 and f <= 1:
				key = "0-1f"
			elif f >= 2 and f <= 5:
				key = "2-5f"
			elif f >= 6 and f <= 30:
				key = "6-30f"
			elif f >= 31:
				key = "31-120f"
			dst[key] = int(dst[key]) + 1
	return {"hitches": buckets, "all_frames": base}


func _per_wall(idx: PackedInt32Array) -> Array:
	var groups := {}
	for i: int in idx:
		var w: int = sampler.wall_index[i]
		# Plain Arrays (reference type); a Packed array in a Dictionary would be copied.
		if not groups.has(w):
			groups[w] = []
		(groups[w] as Array).append(i)
	var rows := []
	var keys := groups.keys()
	keys.sort()
	for w: Variant in keys:
		var g: Array = groups[w]
		var dt := PackedFloat32Array()
		var proc := PackedFloat32Array()
		var post := PackedFloat32Array()
		var draw := PackedFloat32Array()
		var nodes := 0.0
		var draws := 0.0
		var seconds := 0.0
		for i: int in g:
			dt.append(sampler.dt_ms[i])
			proc.append(sampler.process_ms[i])
			post.append(sampler.post_ms[i])
			draw.append(sampler.draw_ms[i])
			nodes += sampler.node_count[i]
			draws += sampler.draw_calls[i]
			seconds += sampler.dt_ms[i] / 1000.0
		var ds := Util.stats(dt)
		var row := {
			"wall": int(w),
			"frames": g.size(),
			"seconds": Util.r2(seconds),
			"dt_mean": ds["mean"], "dt_p95": ds["p95"], "dt_max": ds["max"],
			"hitches": Util.count_over(dt, HITCH_MS),
			"proc_mean": Util.r2(Util.mean(proc)),
			"post_mean": Util.r2(Util.mean(post)),
			"draw_mean": Util.r2(Util.mean(draw)),
			"node_count_mean": Util.r2(nodes / g.size()),
			"draw_calls_mean": Util.r2(draws / g.size()),
		}
		for s: Dictionary in sampler.slow:
			if int(s["wall_index"]) == int(w) and String(s["state"]) == Constants.STATE_PLAYING:
				var p: Dictionary = s["perf"]
				row["object_count"] = p["object_count"]
				row["resource_count"] = p["resource_count"]
				row["orphan_node_count"] = p["orphan_node_count"]
				row["memory_static_mb"] = p["memory_static_mb"]
				row["video_mem_mb"] = p["video_mem_mb"]
				break
		rows.append(row)
	return rows


func _trend(per_wall: Array) -> Dictionary:
	var rows: Array = per_wall.filter(func(r: Dictionary) -> bool: return int(r["frames"]) > 10)
	if rows.size() < 4:
		return {}
	var n := mini(10, rows.size() / 2)
	var first: Array = rows.slice(0, n)
	var last: Array = rows.slice(rows.size() - n)
	return {"walls_each": n, "first": _aggregate_walls(first), "last": _aggregate_walls(last)}


func _aggregate_walls(rows: Array) -> Dictionary:
	var frames := 0
	var dt_sum := 0.0
	var proc_sum := 0.0
	var hitches := 0
	var keys := ["object_count", "resource_count", "orphan_node_count", "memory_static_mb", "video_mem_mb", "node_count_mean", "draw_calls_mean", "dt_p95", "dt_max"]
	var sums := {}
	var counts := {}
	for r: Dictionary in rows:
		var f := int(r["frames"])
		frames += f
		dt_sum += float(r["dt_mean"]) * f
		proc_sum += float(r["proc_mean"]) * f
		hitches += int(r["hitches"])
		for k: String in keys:
			if r.has(k):
				sums[k] = float(sums.get(k, 0.0)) + float(r[k])
				counts[k] = int(counts.get(k, 0)) + 1
	var out := {
		"walls": [rows[0]["wall"], rows[rows.size() - 1]["wall"]],
		"frames": frames,
		"dt_mean_ms": Util.r2(dt_sum / maxf(1.0, frames)),
		"proc_mean_ms": Util.r2(proc_sum / maxf(1.0, frames)),
		"hitches": hitches,
		"hitches_per_wall": Util.r3(float(hitches) / rows.size()),
	}
	for k: String in sums.keys():
		out[k + "_avg"] = Util.r2(float(sums[k]) / int(counts[k]))
	return out


# ------------------------------------------------------------------ output

func _finish() -> void:
	if _done:
		return
	_done = true
	if autoplay != null:
		autoplay.set_enabled(false)
	if sampler != null:
		sampler.recording = false
	result["measure"] = measure()
	result["label"] = label()
	result["ok"] = errors.is_empty()
	result["errors"] = errors
	result["notes"] = notes
	result["timings"] = timings
	result["wall_clock_s"] = Util.r2(float(Time.get_ticks_msec() - _t0_ms) / 1000.0)
	result["unfocused_frames"] = _unfocused_frames
	result["user_data_leftover_moved_to"] = info.get("user_data_leftover_moved_to", "")
	var base := Util.OUT_DIR + "%s_%s" % [measure(), label()]
	var frames_written := ""
	if sampler != null and String(args.get("frames", "1")) != "0":
		if Util.write_json(base + "_frames.json", sampler.export_frames()):
			frames_written = base + "_frames.json"
	result["frames_file"] = frames_written
	Util.write_json(base + ".json", result, " ")
	print("PERF_RESULT ", JSON.stringify(_headline()))
	_log("wrote %s.json" % base)
	var tree := get_tree()
	if tree.has_method("perf_finish"):
		tree.call("perf_finish", 0 if errors.is_empty() else 1)
	else:
		tree.quit(0 if errors.is_empty() else 1)


func _headline() -> Dictionary:
	var h := {"measure": measure(), "label": label(), "ok": errors.is_empty(), "errors": errors.size()}
	if result.has("endless"):
		var e: Dictionary = result["endless"]
		var f: Dictionary = e.get("frames_playing", {})
		h["walls_passed"] = e.get("walls_passed")
		h["dt"] = f.get("dt_ms", {})
		h["over_33ms"] = f.get("over_33ms")
		h["hitches_per_wall"] = e.get("hitches_per_wall")
	if result.has("multimatch"):
		var m: Dictionary = result["multimatch"]
		h["matches"] = m.get("matches_completed")
		h["trend"] = {
			"window_dt_mean_ms": m["trend_per_match"].get("window_dt_mean_ms"),
			"window_dt_p95_ms": m["trend_per_match"].get("window_dt_p95_ms"),
			"menu_slopes": m["trend_per_match"].get("menu_slopes"),
		}
	return h
