extends Node

## Drives native UI input and the real Start, floor-contact, shark and wall-death routes.
var phase := "ui"
var finished := false
var failures: Array[String] = []
var checks: Array[String] = []
var events: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var _clock := 0.0
var _capture: AudioEffectCapture
var _file: FileAccess
var _peak := 0.0
var _out := "res://artifacts/event_audio/"
var _effect_index := -1
var _saved_players := 1
var _saved_llm := ""
var _saved_mode := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func _process(dt: float) -> void:
	_clock += dt
	if _capture != null and _file != null:
		var buffer := _capture.get_buffer(_capture.get_frames_available())
		if not buffer.is_empty():
			_file.store_buffer(buffer.to_byte_array())
			var bus := AudioServer.get_bus_index("SFX")
			_peak = maxf(_peak, db_to_linear(maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))))


func _cue(cue: StringName) -> void:
	events.append({"phase": phase, "cue": str(cue), "time": snappedf(_clock, .001)})
	if cue in [&"heli_land", &"shark_bite", &"body_burst", &"saw_start"]:
		shot(phase + "_" + str(cue))


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + label + ".png")


func count(cue: String, scope: String = "") -> int:
	var key := phase if scope.is_empty() else scope
	return events.filter(func(e): return e.phase == key and e.cue == cue).size()


func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)


func begin_record(label: String) -> void:
	phase = label
	_capture.clear_buffer()
	_peak = 0.0
	_file = FileAccess.open(_out + label + ".f32", FileAccess.WRITE)


func end_record() -> void:
	if _file != null:
		_file.close()
		_file = null
	snapshots.append({"phase": phase, "sample_rate": AudioServer.get_mix_rate(), "peak": _peak})
	check(_peak > .001, "%s outputs real sound" % phase)
	phase = "setup"


func click(button: BaseButton) -> void:
	await RenderingServer.frame_post_draw
	var p := button.get_viewport_transform() * button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = p
		event.global_position = p
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event)
		await get_tree().process_frame
	await get_tree().create_timer(.08, true).timeout


func menu_for(players: int) -> Node:
	QuizManager.game_state.num_players = players
	QuizManager.game_state.mode = Constants.MODE_TEN
	QuizManager.game_state.llm_mode = "OFFLINE"
	QuizManager.game_state.menu_step = Constants.MENU_STEP_CONFIG
	QuizManager.provider.set_llm_mode("OFFLINE")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().process_frame
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	menu.get("_menu_wall_preview").sync_menu_player_count(players)
	await get_tree().create_timer(.4).timeout
	return menu


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_saved_players = QuizManager.game_state.num_players
	_saved_llm = QuizManager.game_state.llm_mode
	_saved_mode = QuizManager.game_state.mode
	var bus := AudioServer.get_bus_index("SFX")
	_effect_index = AudioServer.get_bus_effect_count(bus)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 10.0
	AudioServer.add_bus_effect(bus, _capture)
	AudioManager.sfx_played.connect(_cue)
	await ui_checks()
	for players in [1, 2]:
		await landing_route(players)
	await death_routes()
	await menu_saw()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "events": events, "snapshots": snapshots, "capture_stereo_pairs": AudioServer.get_bus_channels(bus)}
	FileAccess.open(_out + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	AudioManager.sfx_played.disconnect(_cue)
	AudioServer.remove_bus_effect(bus, _effect_index)
	QuizManager.game_state.num_players = _saved_players
	QuizManager.game_state.mode = _saved_mode
	QuizManager.game_state.llm_mode = _saved_llm
	QuizManager.provider.set_llm_mode(_saved_llm)
	print("EVENT_AUDIO ", JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "events": events.size(), "failures": failures}))
	set_process(false)
	finished = true


func ui_checks() -> void:
	var menu := await menu_for(1)
	begin_record("ui")
	var back: BaseButton
	for button in menu.find_children("*", "BaseButton", true, false):
		if button.text == "戻る" and button.is_visible_in_tree():
			back = button
			break
	check(back != null, "actual menu back button exists")
	if back != null:
		await click(back)
		check(count("ui_click") == 1, "native menu click sounds exactly once")
	# The game-start button sounds the decision cue instead of the plain click. Press it through
	# the shared handler: a real click would leave the menu.
	var start: BaseButton = menu.get("start_button")
	check(start.get_meta(AudioManager.UI_SOUND_META, &"") == &"ui_start", "start button asks for the start sound")
	var clicks := count("ui_click")
	var starts := count("ui_start")
	AudioManager._ui_button_pressed(start)
	check(count("ui_start") == starts + 1 and count("ui_click") == clicks, "start button plays ui_start, not ui_click")
	await get_tree().create_timer(.35).timeout
	var dynamic := Button.new()
	dynamic.text = "SE確認"
	dynamic.position = Vector2(1000, 40)
	dynamic.size = Vector2(220, 65)
	dynamic.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.add_child(dynamic)
	await get_tree().process_frame
	var before := count("ui_click")
	await click(dynamic)
	check(count("ui_click") == before + 1, "a dynamically created button is hooked")
	dynamic.disabled = true
	before = count("ui_click")
	await click(dynamic)
	check(count("ui_click") == before, "disabled button remains silent")
	dynamic.disabled = false
	dynamic.toggle_mode = true
	dynamic.set_pressed_no_signal(true)
	await get_tree().process_frame
	check(count("ui_click") == before, "programmatic toggle initialization is silent")
	get_tree().paused = true
	await click(dynamic)
	check(count("ui_click") == before + 1, "pause UI still clicks")
	get_tree().paused = false
	await get_tree().create_timer(.15).timeout
	dynamic.queue_free()
	check(AudioManager._ui_voices[0] not in AudioManager._sfx_voices, "UI voices cannot steal gameplay voices")
	end_record()


func landing_route(players: int) -> void:
	var menu := await menu_for(players)
	begin_record("landing_p%d" % players)
	menu.call("_on_start_pressed")
	var deadline := _clock + 40.0
	var saw_world := false
	var saw_expected := false
	while _clock < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://scenes/game_world.tscn":
			continue
		saw_world = true
		saw_expected = QuizManager.game_state.is_saw_visible()
		var director = scene.get_node_or_null("HelicopterArrivalDirector")
		if is_instance_valid(director) and director._phase == "complete" and (not saw_expected or count("saw_start") >= 1):
			break
	check(saw_world, "P%d actual Start reaches gameplay" % players)
	check(count("heli_land") == players, "P%d has one floor-contact landing per player" % players)
	check(count("jump_land") == 0, "P%d helicopter impact does not double with jump landing" % players)
	check(count("saw_start") == (1 if saw_expected else 0), "P%d saw startup matches the mode's actual saw visibility" % players)
	await get_tree().create_timer(4.3).timeout
	check(count("heli_land") == players and count("saw_start") == (1 if saw_expected else 0), "P%d steady updates do not retrigger" % players)
	end_record()


func death_routes() -> void:
	var world := get_tree().current_scene
	if world.scene_file_path != "res://scenes/game_world.tscn":
		check(false, "gameplay world available for deaths")
		return
	var gs: QuizGameState = QuizManager.game_state
	gs.game_state = Constants.STATE_PLAYING
	gs.state_changed.emit(gs.game_state)
	gs._active_wall_speed = 0.0
	begin_record("shark")
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + .6
	gs.player_y = -1.0
	gs.player_z = gs.wall_z - .2
	gs.player_vel_y = -1.0
	gs._begin_ocean_shark_wait(1)
	var deadline := _clock + 20.0
	while not gs.p1_shark_killed and _clock < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(.6).timeout
	check(gs.p1_shark_killed, "real shark attack reaches the ocean victim")
	check(count("shark_bite") == 1 and count("body_burst") == 1, "shark bite and breakup each sound once")
	end_record()
	begin_record("wall_burst")
	gs._set_player_hp(2, 1)
	gs._apply_hp_wall_damage(2)
	gs._game_over("Sound verification")
	deadline = _clock + 9.0
	while count("body_burst") < 1 and _clock < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(.9).timeout
	check(count("body_burst") == 1, "fatal wall ragdoll breakup sounds exactly once")
	end_record()


## The main menu keeps every in-world effect silent (UI sounds still play, see ui_checks).
func menu_saw() -> void:
	begin_record("menu_saw")
	await menu_for(2)
	check(AudioManager.menu_sfx_muted, "main menu mutes in-world effects")
	await get_tree().create_timer(18.0).timeout
	check(count("saw_start") == 0, "actual menu saw stays silent")
	AudioManager.play_sfx(&"body_burst")
	AudioManager.play_sfx(&"door_correct")
	check(events.filter(func(e): return e.phase == phase and e.cue != "ui_click").is_empty(), "menu plays no in-world effect")
	if _file != null:
		_file.close()
		_file = null
	phase = "setup"
