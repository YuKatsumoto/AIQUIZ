extends Node

## Drives the real Start route and checks which BGM track plays (docs/bgm_renewal.md):
## no music (only the spectators' murmur) from arrival through countdown, the play loop from its head when the
## start barrier breaks, and the menu loop again after leaving the game world.
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/bgm_track_bootstrap.gd

var failures: Array[String] = []
var log_lines: Array[String] = []
var _sfx_last: Dictionary = {}
var sfx_starts: Dictionary = {}  # sound file name -> [msec, ...]


## Records SFX starts by watching the AudioManager voices: a voice that starts a stream, or
## jumps back to its head, has started that sound. The reported playback position wobbles a
## little between mix chunks, so a restart must land near the head after a real jump back.
func _poll_sfx() -> void:
	for voice: AudioStreamPlayer in AudioManager._sfx_voices:
		var file := voice.stream.resource_path.get_file() if voice.playing and voice.stream != null else ""
		var pos := voice.get_playback_position() if voice.playing else -1.0
		var last: Array = _sfx_last.get(voice, ["", -1.0])
		var restarted := pos < 0.2 and pos < float(last[1]) - 0.2
		if file != "" and (file != last[0] or restarted):
			if not sfx_starts.has(file):
				sfx_starts[file] = []
			(sfx_starts[file] as Array).append(Time.get_ticks_msec())
		_sfx_last[voice] = [file, pos]


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn":
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn":
			await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	await get_tree().create_timer(2.0).timeout
	_note("menu")
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU and _player(&"menu").playing, "menu loop plays in the menu")

	gs.state_changed.connect(func(state: String) -> void: _note("state -> %s" % state))
	menu.call("_on_start_pressed")
	var deadline := Time.get_ticks_msec() + 60000
	var started := false
	var play_seen_msec := -1
	var countdown_msec := -1
	var numbers: Array[String] = []
	var covered_bgm_db := INF
	var covered_ambience_db := INF
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		_poll_sfx()
		if SceneTransition.is_fully_covered():
			covered_bgm_db = minf(covered_bgm_db, _bus_db("BGM"))
			covered_ambience_db = minf(covered_ambience_db, _bus_db(AudioManager.AMBIENCE_BUS))
		if gs.game_state == Constants.STATE_COUNTDOWN:
			if countdown_msec < 0:
				countdown_msec = Time.get_ticks_msec()
			var barrier = get_tree().current_scene.get("_start_barrier")
			var label := (barrier as Node).get_node_or_null("QuestionLabel") as Label3D if is_instance_valid(barrier) else null
			if label != null and label.text != "" and (numbers.is_empty() or numbers[-1] != label.text):
				numbers.append(label.text)
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://scenes/game_world.tscn":
			continue
		var director := scene.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
		if not started and gs.game_state == Constants.STATE_WAITING_START and (director == null or not director.is_start_locked()):
			check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_NONE and not _player(&"menu").playing, "menu loop stops in the game world")
			check(AudioManager.get_crowd_ambience() == AudioManager.CROWD_MURMUR, "only the crowd murmur before the start")
			started = true
			gs.trigger_start()
		if gs.game_state in [Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN]:
			if AudioManager.get_music_track() != AudioManager.MUSIC_TRACK_NONE:
				check(false, "no music during %s" % gs.game_state)
			if AudioManager.get_crowd_ambience() != AudioManager.CROWD_MURMUR:
				check(false, "crowd murmur during %s" % gs.game_state)
		if gs.game_state == Constants.STATE_PLAYING and play_seen_msec < 0:
			play_seen_msec = Time.get_ticks_msec()
			await get_tree().process_frame
			_note("first PLAYING frame")
			check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_PLAY, "play track selected when the barrier breaks")
			check(_player(&"play").playing and _player(&"play").get_playback_position() < 0.5, "play loop starts from its head")
		if play_seen_msec >= 0 and Time.get_ticks_msec() - play_seen_msec > 4000:
			break
	check(play_seen_msec >= 0, "reached PLAYING")
	# Scene transition (docs/bgm_renewal.md): silent while the black wipe covers the screen,
	# back to the slider level once the game world is revealed.
	var slider_db := AudioManager.bgm_volume_to_db(AudioManager.bgm_volume)
	check(covered_bgm_db <= -60.0, "music silent under the black wipe (%.1f dB)" % covered_bgm_db)
	check(covered_ambience_db <= -60.0, "crowd silent under the black wipe (%.1f dB)" % covered_ambience_db)
	check(absf(_bus_db("BGM") - slider_db) < 0.1 and absf(_bus_db(AudioManager.AMBIENCE_BUS)) < 0.1, "buses back to normal after the reveal")
	# Start countdown (docs/sound_effects.md): 5-4-3-2-1 over ~5 s, a beep per number, GO at the break.
	var beeps: Array = sfx_starts.get("countdown_beep.ogg", [])
	var gos: Array = sfx_starts.get("countdown_go.ogg", [])
	var countdown_s := (play_seen_msec - countdown_msec) / 1000.0
	log_lines.append("countdown %.2f s, numbers %s, beeps at %s, go at %s (PLAYING at %d)" % [
		countdown_s, numbers, beeps.map(func(t: int) -> int: return t - countdown_msec),
		gos.map(func(t: int) -> int: return t - countdown_msec), play_seen_msec - countdown_msec])
	check(numbers == ["5", "4", "3", "2", "1"], "barrier counts 5-4-3-2-1 (%s)" % [numbers])
	check(absf(countdown_s - QuizGameState.COUNTDOWN_SECONDS) < 0.15, "countdown lasts %.2f s" % countdown_s)
	check(beeps.size() == 5, "one beep per number (%d)" % beeps.size())
	check(gos.size() == 1 and absi(int(gos[0]) - play_seen_msec) <= 50, "GO sounds when the barrier breaks")
	_note("4 s into PLAYING")
	var play_pos := _player(&"play").get_playback_position()
	check(_player(&"play").playing and play_pos > 2.5, "play loop keeps going (%.2f s)" % play_pos)
	check(not _player(&"menu").playing, "menu loop faded out and stopped")
	var race_crowd: AudioStreamPlayer = AudioManager._crowd_players[AudioManager.CROWD_RACE]
	var murmur: AudioStreamPlayer = AudioManager._crowd_players[AudioManager.CROWD_MURMUR]
	check(AudioManager.get_crowd_ambience() == AudioManager.CROWD_RACE and race_crowd.playing, "race crowd cheers while playing")
	check(not murmur.playing, "murmur faded out after the start")

	# The clear screen switches to the result loop from its head (forced here instead of
	# answering ten questions; the music choice only depends on the state change).
	gs.game_state = Constants.STATE_CLEAR
	gs.state_changed.emit(gs.game_state)
	await get_tree().create_timer(1.0).timeout
	_note("1 s into CLEAR")
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_RESULT, "clear screen selects the result loop")
	check(_player(&"result").playing and _player(&"result").get_playback_position() < 1.5, "result loop starts from its head")
	check(not _player(&"play").playing, "play loop stops on the clear screen")
	_poll_sfx()
	check(sfx_starts.has("crowd_goal_cheer.ogg"), "spectators cheer on the clear")
	check(AudioManager.get_crowd_ambience() == AudioManager.CROWD_NONE and not race_crowd.playing, "crowd bed stops on the clear screen")

	# Dying ends in GAME_OVER: the play loop fades out and the menu loop must NOT come back
	# (it did before 2026-10-12). Forced from PLAYING like the clear above.
	gs.game_state = Constants.STATE_PLAYING
	gs.state_changed.emit(gs.game_state)
	await get_tree().create_timer(0.6).timeout
	gs.game_state = Constants.STATE_GAME_OVER
	gs.state_changed.emit(gs.game_state)
	await get_tree().create_timer(1.4).timeout
	_note("1.4 s into GAME_OVER")
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_NONE, "game over selects no music")
	check(not _player(&"menu").playing and not _player(&"play").playing and not _player(&"result").playing, "game over is silent (no menu loop)")

	gs.reset_to_menu()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().create_timer(1.5).timeout
	_note("back in the menu")
	check(AudioManager.get_music_track() == AudioManager.MUSIC_TRACK_MENU and _player(&"menu").playing, "menu loop returns after leaving the world")
	check(not _player(&"play").playing, "play loop stops after leaving the world")

	for line in log_lines:
		print(line)
	print("BGM track runtime: %s" % ("PASS" if failures.is_empty() else "FAIL\n  " + "\n  ".join(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)


func _bus_db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func _player(track: StringName) -> AudioStreamPlayer:
	return AudioManager._track_players[track]


func _note(what: String) -> void:
	var parts: Array[String] = []
	for track: StringName in AudioManager.MUSIC_TRACKS:
		var p := _player(track)
		parts.append("%s %s %.2fs %.1fdB" % [track, "on" if p.playing else "off", p.get_playback_position(), p.volume_db])
	log_lines.append("[%7.2f] %-22s track=%s | %s" % [Time.get_ticks_msec() / 1000.0, what, AudioManager.get_music_track(), " | ".join(parts)])


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
