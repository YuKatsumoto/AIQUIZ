extends Node

## メニューの「ゲーム開始」→ ヘリのお迎え → 発進を、プレイヤーが見るメニューのカメラのまま連番で撮る（見た目の確認用）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/heli_departure_capture_bootstrap.gd -- players=2 tag=after
## 引数（"--" の後ろ）: players=1|2、tag=<出力名>（artifacts/heli_departure/<tag>/）、every=<N>（N フレームごとに保存、既定 6）、
## stop_after=<秒>（打ち上がりからその秒数でメニューのまま終える。ゲーム画面を読まずに終了時の後始末を確かめる）
## 出力: f_<フレーム>.png と report.json（ヘリの出来事の時刻：つかまる・溜め・打ち上がり・ワイプ・ゲーム画面）。

var players := 2
var tag := "capture"
var every := 6
var stop_after := -1.0
var output := ""
var events: Array[Dictionary] = []
var failures: Array[String] = []
var _start_msec := 0
## Encoding PNGs mid-run slows the real clock enough to trip the menu's real-time departure timeout,
## so frames are kept in memory and written after the run.
var _shots: Dictionary = {}


func _ready() -> void:
	call_deferred("run")


func _event(label: String, frame: int, extra: Dictionary = {}) -> void:
	var entry := {"event": label, "frame": frame, "t": frame / 60.0, "real_ms": Time.get_ticks_msec() - _start_msec}
	entry.merge(extra)
	events.append(entry)


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("players="):
			players = clampi(arg.trim_prefix("players=").to_int(), 1, 2)
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
		elif arg.begins_with("every="):
			every = maxi(1, arg.trim_prefix("every=").to_int())
		elif arg.begins_with("stop_after="):
			stop_after = arg.trim_prefix("stop_after=").to_float()
	output = "res://artifacts/heli_departure/%s" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.5).timeout
	while menu.config_conveyor.is_moving():
		await get_tree().process_frame
	_start_msec = Time.get_ticks_msec()
	menu.call("_on_start_pressed")
	var frame := 0
	var seen := {}
	var deadline := Time.get_ticks_msec() + 40000
	var last_usec := Time.get_ticks_usec()
	var slowest := {}
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		frame += 1
		# Real time per frame (the clock is fixed): a spike is a hitch such as a shader compile.
		var now_usec := Time.get_ticks_usec()
		var frame_ms := (now_usec - last_usec) / 1000.0
		last_usec = now_usec
		if frame_ms > float(slowest.get("ms", 0.0)) and frame % every != 1:
			slowest = {"frame": frame, "ms": snappedf(frame_ms, 0.1)}
		var scene := get_tree().current_scene
		if scene != menu:
			_event("game_scene", frame)
			break
		var director: HelicopterArrivalDirector = preview.get("_menu_start_departure")
		if director != null and is_instance_valid(director):
			if director._all_menu_players_captured() and not seen.has("captured"):
				seen["captured"] = true
				_event("captured", frame)
			if director._menu_launch_charge_elapsed > 0.0 and not seen.has("charge"):
				seen["charge"] = true
				_event("charge", frame)
			if director._menu_boost_started and not seen.has("boost"):
				seen["boost"] = true
				_event("boost", frame)
			if stop_after >= 0.0 and director._menu_boost_started and director._menu_launch_elapsed >= stop_after:
				_event("stopped", frame)
				break
		var cover := SceneTransition.get_cover_factor()
		if cover > 0.0 and not seen.has("cover"):
			seen["cover"] = true
			_event("cover_start", frame)
		if cover >= 1.0 and not seen.has("covered"):
			seen["covered"] = true
			_event("covered", frame)
		if frame % every == 0 and cover < 1.0:
			_shots[frame] = get_viewport().get_texture().get_image()
	for shot_frame: int in _shots:
		(_shots[shot_frame] as Image).save_png("%s/f_%04d.png" % [output, shot_frame])
	if not seen.has("boost"):
		failures.append("boost never started")
	var report := {"passed": failures.is_empty(), "players": players, "failures": failures, "events": events, "slowest_frame": slowest}
	FileAccess.open(output + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HELI_DEPARTURE_CAPTURE ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
