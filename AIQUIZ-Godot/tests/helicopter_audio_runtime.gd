extends Node

## Run in the editor's real game via game_eval, or helicopter_audio_bootstrap.gd.
## Captures the actual sound bus; no timing guesses from a static timeline.
var phase := "boot"
var failures: Array[String] = []
var checks: Array[String] = []
var events: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var finished := false
var _connected: Dictionary = {}
var _shots: Dictionary = {}
var _record: AudioEffectCapture
var _capture_file: FileAccess
var _capture_peak := 0.0
var _clock := 0.0
var _out := "res://artifacts/helicopter_audio/"
var _capture_bus := "HelicopterCapture"
var _max_mix := 0.0
var _original_players := 1
var _original_mode := ""
var _original_llm := ""
var _original_volume := 1.0


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)


func _process(delta: float) -> void:
	_clock += delta
	if _record != null and _capture_file != null:
		var buffer := _record.get_buffer(_record.get_frames_available())
		if not buffer.is_empty():
			_capture_file.store_buffer(buffer.to_byte_array())
			var index := AudioServer.get_bus_index(_capture_bus)
			_capture_peak = maxf(_capture_peak, db_to_linear(maxf(AudioServer.get_bus_peak_volume_left_db(index, 0), AudioServer.get_bus_peak_volume_right_db(index, 0))))
	for rig in get_tree().get_nodes_in_group("helicopter_sound"):
		if not _connected.has(rig.get_instance_id()):
			_connected[rig.get_instance_id()] = true
			rig.cue_played.connect(func(cue: StringName):
				events.append({"phase": phase, "time": snappedf(_clock, .001), "cue": str(cue), "aircraft": str(rig._carrier.get_parent().name)}))
			AudioServer.set_bus_send(AudioServer.get_bus_index(rig._bus), _capture_bus)
		_max_mix = maxf(_max_mix, rig.mix_gain)
		if rig._jet and rig.mix_gain > .01 and not _shots.has(phase):
			_shots[phase] = true
			capture(phase)


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + label + ".png")


func start_recording() -> void:
	_record.clear_buffer()
	_capture_peak = 0.0
	_capture_file = FileAccess.open(_out + phase + ".f32", FileAccess.WRITE)


func save_recording(label: String, expect_audio: bool = true) -> void:
	if _capture_file != null:
		_capture_file.close()
		_capture_file = null
	snapshots.append({"phase": label, "sample_rate": AudioServer.get_mix_rate(), "peak": _capture_peak})
	if expect_audio:
		check(_capture_peak > .001, "%s contains real audio samples" % label)
	else:
		check(_capture_peak < .0001, "%s is silent" % label)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_original_players = QuizManager.game_state.num_players
	_original_mode = QuizManager.game_state.mode
	_original_llm = QuizManager.game_state.llm_mode
	_original_volume = AudioManager.sfx_volume
	var index := AudioServer.get_bus_index("SFX") + 1
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, _capture_bus)
	AudioServer.set_bus_send(index, "SFX")
	_record = AudioEffectCapture.new()
	_record.buffer_length = 2.0
	AudioServer.add_bus_effect(index, _record)
	for players in [1, 2]:
		await start_route(players)
	await skip_and_cancel()
	await online_route()
	# Every per-aircraft bus must disappear on a scene teardown.
	await get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var buses := 0
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i).begins_with("Helicopter_"):
			buses += 1
	var carriers := get_tree().get_nodes_in_group("helicopter_sound")
	check(buses <= 4, "scene teardown leaves only the new menu's prebuilt aircraft buses")
	AudioManager.set_sfx_volume(_original_volume, false)
	QuizManager.game_state.num_players = _original_players
	QuizManager.game_state.mode = _original_mode
	QuizManager.game_state.llm_mode = _original_llm
	QuizManager.provider.set_llm_mode(_original_llm)
	for rig in carriers:
		AudioServer.set_bus_send(AudioServer.get_bus_index(rig._bus), "SFX")
	var capture_pairs := AudioServer.get_bus_channels(AudioServer.get_bus_index(_capture_bus))
	AudioServer.remove_bus(AudioServer.get_bus_index(_capture_bus))
	set_process(false)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "events": events, "snapshots": snapshots, "max_mix_gain": _max_mix, "capture_stereo_pairs": capture_pairs}
	var file := FileAccess.open(_out + "runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("HELICOPTER_AUDIO ", JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "events": events.size(), "failures": failures}))
	finished = true


func menu_for(players: int) -> Node:
	var gs := QuizManager.game_state
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.menu_step = Constants.MENU_STEP_CONFIG
	QuizManager.provider.set_llm_mode("OFFLINE")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().process_frame
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	return menu


func start_route(players: int) -> void:
	phase = "prewarm_p%d" % players
	start_recording()
	var menu := await menu_for(players)
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	var deadline := _clock + 25.0
	while bool(preview.get("_menu_intro_active")) and _clock < deadline:
		await get_tree().process_frame
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(.5).timeout
	var prepared: HelicopterArrivalDirector = preview.get("_menu_start_departure")
	check(is_instance_valid(prepared), "P%d departure is prebuilt" % players)
	if not is_instance_valid(prepared):
		return
	for info in prepared._helicopters:
		var rig = info.heli.sound
		check(not rig.enabled and not rig._beds[&"rotor"].playing, "P%d prewarm is silent" % players)
	save_recording(phase, false)
	phase = "departure_p%d" % players
	start_recording()
	menu.call("_on_start_pressed")
	deadline = _clock + 35.0
	var observed := false
	var switched := false
	while _clock < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null:
			continue
		if scene.scene_file_path == "res://scenes/game_world.tscn":
			if not switched:
				# The main menu keeps every in-world effect silent, helicopters included.
				save_recording(phase, false)
				phase = "arrival_p%d" % players
				start_recording()
				switched = true
			var d := scene.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
			if is_instance_valid(d):
				observed = observed or d._phase == "arrival"
				if d._phase == "complete":
					break
	check(switched and observed, "P%d actual Start reaches gameplay arrival" % players)
	await get_tree().create_timer(.65).timeout
	save_recording(phase)
	check(get_tree().get_nodes_in_group("helicopter_sound").is_empty(), "P%d arrival cleans up all active sound rigs" % players)
	var departure_events := events.filter(func(e): return e.phase == "departure_p%d" % players)
	check(departure_events.is_empty(), "P%d menu departure plays no effects (%d)" % [players, departure_events.size()])
	var key := "arrival_p%d" % players
	var ignitions := events.filter(func(e): return e.phase == key and e.cue == "jet_ignite").size()
	check(ignitions == players, "%s has one ignition per aircraft (%d)" % [key, ignitions])


func skip_and_cancel() -> void:
	phase = "skip_cancel"
	var menu := await menu_for(2)
	await get_tree().create_timer(1.0).timeout
	var preview: Node = menu.get("_menu_wall_preview")
	preview.call("_cancel_menu_helicopter_intro")
	preview.begin_game_start_departure(2)
	await get_tree().create_timer(.8).timeout
	preview.cancel_game_start_departure()
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("helicopter_sound").is_empty(), "mid-flight cancel immediately stops sound")
	preview.begin_game_start_departure(2)
	await get_tree().create_timer(.8).timeout
	var director = preview.get("_menu_start_departure")
	if is_instance_valid(director):
		director.skip_menu_departure()
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("helicopter_sound").is_empty(), "skip immediately stops sound")


func online_route() -> void:
	phase = "online_boarding"
	get_tree().change_scene_to_file("res://ui/online_menu.tscn")
	await get_tree().process_frame
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	var d = menu.get("director")
	var stage = menu.get("stage")
	check(d != null and stage != null, "actual online menu creates the helicopter stage")
	if d == null or stage == null:
		return
	start_recording()
	d.begin_departure()
	var deadline := _clock + 23.0
	while d.state_name() != "CRUISE" and _clock < deadline:
		await get_tree().process_frame
	check(d.state_name() == "CRUISE", "online boarding, spool and launch reach cruise")
	check(events.any(func(e): return e.phase == phase and e.cue == "belt_click"), "online seatbelt clicks after fastening")
	check(events.filter(func(e): return e.phase == phase and e.cue == "jet_ignite").size() == 1, "online launch ignites exactly once")
	save_recording(phase)
	phase = "online_join"
	start_recording()
	d.on_matched(1, {"hat": 0})
	await get_tree().create_timer(4.0).timeout
	check(events.filter(func(e): return e.phase == phase and e.cue == "jet_ignite").size() == 1, "joining aircraft ignites exactly once")
	check(stage.my_heli.sound._beds[&"rotor"].playing and stage.their_heli.sound._beds[&"rotor"].playing, "formation has both continuous rotor beds")
	await capture("online_formation")
	save_recording(phase)
	d.reset_to_idle()
	await get_tree().create_timer(.2).timeout
	check(not stage.my_heli.sound._beds[&"jet"].playing and not stage.their_heli.sound._beds[&"jet"].playing, "online cancel stops both jets")
	# The user's SFX slider must reach the helicopter buses, without changing BGM.
	AudioManager.set_sfx_volume(0.0, false)
	var index := AudioServer.get_bus_index("SFX")
	check(AudioServer.is_bus_mute(index) or AudioServer.get_bus_volume_db(index) < -60.0, "SFX mute controls all helicopter sounds")
	AudioManager.set_sfx_volume(_original_volume, false)
