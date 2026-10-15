extends SceneTree

## Runs the Score Tower runtime test (result_ceremony_runtime.gd) and logs, on the ceremony
## clock, when the drum roll, the crowd sounds and the music tracks start
## (docs/sound_effects.md, docs/bgm_renewal.md). Needs a window (the runtime test captures):
## ./Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . --script res://tests/result_ceremony_audio_probe.gd -- runtime case=p1

var _last_file: Dictionary = {}
var _last_track: StringName = &"?"
var _last_crowd: StringName = &"?"
var events: Array[String] = []
var failures: Array[String] = []
var roll_at := -1.0
var finish_at := -1.0
var result_at := -1.0
var verdict_cheer_at := -1.0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	root.add_child((load("res://tests/result_ceremony_runtime.gd") as Script).new())
	process_frame.connect(_poll)


func _poll() -> void:
	var quiz_manager := root.get_node_or_null("QuizManager")
	var audio := root.get_node_or_null("AudioManager")
	if quiz_manager == null or audio == null:
		return
	var gs = quiz_manager.game_state
	if gs == null or gs.game_state != "RESULT_CEREMONY":
		return
	var t: float = gs.result_ceremony_elapsed
	var track: StringName = audio.get_music_track()
	if track != _last_track:
		events.append("%.2f s music -> '%s'" % [t, track])
		if track == audio.MUSIC_TRACK_RESULT and result_at < 0.0:
			result_at = t
		_last_track = track
	var crowd: StringName = audio.get_crowd_ambience()
	if crowd != _last_crowd:
		events.append("%.2f s crowd -> '%s'" % [t, crowd])
		_last_crowd = crowd
	for voice: AudioStreamPlayer in audio._sfx_voices:
		var file := voice.stream.resource_path.get_file() if voice.playing and voice.stream != null else ""
		var pos := voice.get_playback_position() if voice.playing else -1.0
		var last: Array = _last_file.get(voice, ["", -1.0])
		if file != "" and (file != last[0] or (pos < 0.2 and pos < float(last[1]) - 0.2)):
			events.append("%.2f s sfx %s" % [t, file])
			if file == "score_roll.ogg" and roll_at < 0.0:
				roll_at = t
			if file == "score_roll_finish.ogg" and finish_at < 0.0:
				finish_at = t
			if file == "crowd_win_cheer.ogg" and verdict_cheer_at < 0.0:
				verdict_cheer_at = t
		_last_file[voice] = [file, pos]
	if t > 9.0 and not events.is_empty():
		_report()


func _report() -> void:
	process_frame.disconnect(_poll)
	for line in events:
		print("[audio probe] ", line)
	if absf(roll_at - 2.0) > 0.1:
		failures.append("drum roll at %.2f s (expected 2.0)" % roll_at)
	if absf(finish_at - 6.9) > 0.1:
		failures.append("roll finish at %.2f s (expected the 6.9 s verdict)" % finish_at)
	if absf(result_at - 6.9) > 0.1:
		failures.append("result music at %.2f s (expected the 6.9 s verdict)" % result_at)
	if absf(verdict_cheer_at - 6.9) > 0.1:
		failures.append("verdict cheer at %.2f s" % verdict_cheer_at)
	print("[audio probe] %s" % ("PASS" if failures.is_empty() else "FAIL: " + ", ".join(failures)))
