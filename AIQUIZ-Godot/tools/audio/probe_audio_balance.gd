extends Node

## Inject into the real game with label="before"/"after". Records the music,
## SFX and final output simultaneously, including the actual 2P helicopter route.
var label := "before"
var finished := false
var snapshots: Array[Dictionary] = []
var events: Array[Dictionary] = []
var _captures: Dictionary = {}
var _files: Dictionary = {}
var _indices: Dictionary = {}
var _phase := ""
var _clock := 0.0
var _out := ""
var _shots: Dictionary = {}


func _ready() -> void:
	call_deferred("run")


func _process(dt: float) -> void:
	_clock += dt
	for bus: String in _files:
		var capture: AudioEffectCapture = _captures[bus]
		var buffer := capture.get_buffer(capture.get_frames_available())
		if not buffer.is_empty():
			(_files[bus] as FileAccess).store_buffer(buffer.to_byte_array())
	var scene := get_tree().current_scene
	if scene != null and _phase == "helicopters":
		var d := scene.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
		if d != null and d._phase == "arrival" and d._phase_elapsed > 2.5 and not _shots.has("arrival"):
			_shots["arrival"] = true
			shot("arrival")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + name + ".png")


func _cue(cue: StringName) -> void:
	events.append({"phase": _phase, "cue": str(cue), "time": _clock})


func record(phase: String) -> void:
	_phase = phase
	for bus: String in _captures:
		(_captures[bus] as AudioEffectCapture).clear_buffer()
		_files[bus] = FileAccess.open(_out + phase + "__" + bus + ".f32", FileAccess.WRITE)


func end_record() -> void:
	for bus: String in _files:
		(_files[bus] as FileAccess).close()
		snapshots.append({"phase": _phase + "__" + bus, "sample_rate": AudioServer.get_mix_rate()})
	_files.clear()


func run() -> void:
	_out = "res://artifacts/audio_balance/" + label + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var saved_players := QuizManager.game_state.num_players
	var saved_mode := QuizManager.game_state.mode
	var saved_llm := QuizManager.game_state.llm_mode
	var saved_bgm := AudioManager.bgm_volume
	var saved_sfx := AudioManager.sfx_volume
	for bus: String in ["Master", "BGM", "SFX"]:
		var index := AudioServer.get_bus_index(bus)
		_indices[bus] = AudioServer.get_bus_effect_count(index)
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 10.0
		AudioServer.add_bus_effect(index, capture)
		_captures[bus] = capture
	AudioManager.sfx_played.connect(_cue)
	QuizManager.provider.set_llm_mode("OFFLINE")
	QuizManager.game_state.llm_mode = "OFFLINE"
	QuizManager.game_state.num_players = 2
	QuizManager.game_state.mode = Constants.MODE_TEN
	QuizManager.game_state.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().process_frame
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	menu.get("_menu_wall_preview").sync_menu_player_count(2)
	await get_tree().create_timer(.6).timeout
	record("helicopters")
	menu.call("_on_start_pressed")
	var deadline := _clock + 35.0
	while _clock < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://scenes/game_world.tscn":
			continue
		var d := scene.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
		if d != null and d._phase == "complete":
			break
	await get_tree().create_timer(.7).timeout
	end_record()
	var world := get_tree().current_scene
	# Hold the actual rendered course still for reproducible music/action comparisons.
	world.set_process(false)
	AudioManager.set_music_track(AudioManager.MUSIC_TRACK_PLAY)
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_GAMEPLAY, 0.0)
	AudioManager.set_crowd_ambience(AudioManager.CROWD_RACE, 0.0)
	AudioManager.bgm_player.play(20.0)
	await get_tree().create_timer(.4).timeout
	for cue: StringName in [&"push_kick", &"jump_land", &"heli_land", &"ui_click", &"bonk", &"wall_crash", &"door_correct", &"door_wrong", &"shark_bite", &"body_burst", &"countdown_beep", &"countdown_go"]:
		record(str(cue))
		AudioManager.play_sfx(cue)
		await get_tree().create_timer(.9).timeout
		end_record()
	# Worst overlap at full sliders; silence only the final fader while measuring the
	# actual DSP output, so this deliberately dense stress clip is not played aloud.
	var master_db := AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0, -80.0)
	AudioManager.set_bgm_volume(1.0, false)
	AudioManager.set_sfx_volume(1.0, false)
	record("overlap")
	for i in range(2):
		AudioManager.play_sfx(&"heli_land")
		AudioManager.play_sfx(&"shark_bite")
		AudioManager.play_sfx(&"body_burst")
	await get_tree().create_timer(1.1).timeout
	end_record()
	AudioServer.set_bus_volume_db(0, master_db)
	AudioManager.set_bgm_volume(saved_bgm, false)
	AudioManager.set_sfx_volume(saved_sfx, false)
	var pairs := AudioServer.get_bus_channels(0)
	for bus: String in _captures:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index(bus), _indices[bus])
	AudioManager.sfx_played.disconnect(_cue)
	QuizManager.game_state.num_players = saved_players
	QuizManager.game_state.mode = saved_mode
	QuizManager.game_state.llm_mode = saved_llm
	QuizManager.provider.set_llm_mode(saved_llm)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	FileAccess.open(_out + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify({"snapshots": snapshots, "events": events, "capture_stereo_pairs": pairs, "bgm_volume": saved_bgm, "sfx_volume": saved_sfx}, "\t"))
	print("AUDIO_BALANCE_RECORDED ", label)
	set_process(false)
	finished = true
