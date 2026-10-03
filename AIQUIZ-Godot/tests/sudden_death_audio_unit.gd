extends Node

## Sudden-death procedural audio (docs/sudden_death_underground.md 5.6 and 9): every cue and loop
## is synthesized off the main thread with frames still flowing, stays under -3 dBFS without
## clipping or NaN, one-shots start and end silent, loops are seamless, loudness sits near the
## result-ceremony cues, the SuddenDeath bus carries its reverb / underwater low-pass / limiter,
## the runtime API (motor, ambience crossfade, reverb, underwater) behaves, a second instance
## reuses the cache, and stop_all() restores a dry, silent bus.
## Writes res://artifacts/sudden_death/audio/report.json and one .wav per cue for listening.
## Run: Godot --headless --path . --script res://tests/sudden_death_audio_bootstrap.gd

const AudioScript := preload("res://scripts/world/sudden_death/sudden_death_audio.gd")
const OUT := "res://artifacts/sudden_death/audio/"

var checks := 0
var failures: Array[String] = []
var report := {}
var _audio: Node


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Keep the exported .wav files out of the editor's import.
	var ignore := FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	if ignore != null:
		ignore.close()
	await _check_generation()
	_check_cues()
	_check_reference_loudness()
	await _check_runtime()
	await _check_second_instance()
	_export_wavs()
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	var generation: Dictionary = report.get("generation", {})
	print("SUDDEN_DEATH_AUDIO_UNIT " + JSON.stringify({
		"passed": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"setup_ms": generation.get("setup_ms", -1.0),
		"generation_ms": generation.get("worker_ms", -1.0),
		"worst_frame_ms": generation.get("worst_frame_ms", -1.0),
	}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _check_generation() -> void:
	_audio = AudioScript.new()
	add_child(_audio)
	var started := Time.get_ticks_usec()
	_audio.setup()
	var setup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	# A cue asked for immediately must play (built by the worker or the synchronous fallback).
	started = Time.get_ticks_usec()
	_audio.play(&"whistle")
	var first_play_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var snapshot: Dictionary = _audio.get_debug_snapshot()
	check(int(snapshot["voices_playing"]) >= 1, "whistle plays right after setup")
	var worst_frame_ms := 0.0
	var frames := 0
	var waited_from := Time.get_ticks_usec()
	var last := waited_from
	while not AudioScript.is_generation_finished() and Time.get_ticks_usec() - waited_from < 30000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst_frame_ms = maxf(worst_frame_ms, float(now - last) / 1000.0)
		last = now
		frames += 1
	var info: Dictionary = AudioScript.get_generation_info()
	check(AudioScript.is_generation_finished(), "background generation finishes")
	check(int(info["ready"]) == AudioScript.GENERATION_ORDER.size(), "every cue and loop is cached")
	check(AudioScript.GENERATION_ORDER.size() == AudioScript.CUES.size() + AudioScript.LOOPS.size(),
		"generation order covers every cue and loop exactly once")
	check(setup_ms < 150.0, "setup() main-thread cost %.2f ms < 150 ms" % setup_ms)
	check(worst_frame_ms < 100.0, "frames keep flowing during generation (worst %.1f ms)" % worst_frame_ms)
	check(int(info["runs"]) == 1, "generation ran once")
	var build_total := 0.0
	var stats: Dictionary = AudioScript.get_cue_stats()
	for cue: StringName in stats:
		build_total += float(stats[cue]["build_ms"])
	report["generation"] = {
		"setup_ms": setup_ms,
		"first_play_ms": first_play_ms,
		"sync_builds": info["sync_builds"],
		"worker_ms": info["ms"],
		"sum_build_ms": build_total,
		"wall_wait_ms": float(Time.get_ticks_usec() - waited_from) / 1000.0,
		"frames_while_generating": frames,
		"worst_frame_ms": worst_frame_ms,
	}


func _check_cues() -> void:
	var stats: Dictionary = AudioScript.get_cue_stats()
	var cues := {}
	for cue: StringName in AudioScript.GENERATION_ORDER:
		var stream: AudioStreamWAV = AudioScript.get_stream(cue)
		check(stream != null, "%s generated" % cue)
		if stream == null:
			continue
		var is_loop := AudioScript.LOOPS.has(cue)
		var info: Dictionary = AudioScript.LOOPS[cue] if is_loop else AudioScript.CUES[cue]
		var rate := int(info["rate"])
		var samples := AudioScript.decode(stream)
		var n := samples.size()
		var measured: Dictionary = AudioScript.measure(samples, rate)
		var stat: Dictionary = stats.get(cue, {})
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == rate,
			"%s is 16-bit mono at %d Hz" % [cue, rate])
		check(n == int(round(float(rate) * float(info["seconds"]))), "%s length %d samples" % [cue, n])
		check(int(stat.get("nan", -1)) == 0, "%s has no NaN/inf" % cue)
		var clipped := 0
		for i: int in n:
			if absf(samples[i]) >= 0.999:
				clipped += 1
		check(clipped == 0, "%s does not clip" % cue)
		check(float(measured["peak_db"]) <= -2.95, "%s peak %.2f dBFS <= -3" % [cue, measured["peak_db"]])
		check(float(measured["peak_db"]) >= -36.0, "%s is audible (peak %.1f dBFS)" % [cue, measured["peak_db"]])
		var target := float(info["lufs"])
		var lufs := float(measured["lufs"])
		var on_target := absf(lufs - target) <= 1.0 or (String(stat.get("limited_by", "")) == "peak" and lufs <= target + 1.0)
		check(on_target, "%s loudness %.1f vs target %.1f (%s)" % [cue, lufs, target, stat.get("limited_by", "?")])
		var entry := {
			"rate": rate,
			"seconds": float(n) / float(rate),
			"loop": is_loop,
			"peak_db": measured["peak_db"],
			"rms_db": measured["rms_db"],
			"lufs": lufs,
			"target_lufs": target,
			"limited_by": stat.get("limited_by", ""),
			"gain_db": stat.get("gain_db", 0.0),
			"drive": stat.get("drive", 0.0),
			"build_ms": stat.get("build_ms", 0.0),
			"clipped_samples": clipped,
		}
		if is_loop:
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == n,
				"%s loops over the whole buffer" % cue)
			var diffs := PackedFloat32Array()
			diffs.resize(n - 1)
			for i: int in range(1, n):
				diffs[i - 1] = absf(samples[i] - samples[i - 1])
			var seam := absf(samples[0] - samples[n - 1])
			diffs.sort()
			var p999 := diffs[int(float(diffs.size() - 1) * 0.999)]
			check(seam <= p999, "%s seam step %.4f within normal sample steps (p99.9 %.4f)" % [cue, seam, p999])
			var window := int(0.1 * rate)
			var head := _rms(samples, 0, window)
			var tail := _rms(samples, n - window, n)
			var level_jump := absf(_db(head) - _db(tail))
			check(level_jump <= 6.0, "%s level matches across the seam (%.1f dB)" % [cue, level_jump])
			entry["seam_step"] = seam
			entry["step_p999"] = p999
			entry["seam_level_jump_db"] = level_jump
		else:
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s is a one-shot" % cue)
			check(absf(samples[0]) < 0.02, "%s starts without a click" % cue)
			check(absf(samples[n - 1]) < 0.002, "%s ends silent" % cue)
		cues[String(cue)] = entry
	report["cues"] = cues


func _check_reference_loudness() -> void:
	var manager := get_node_or_null("/root/AudioManager")
	if manager == null:
		report["reference"] = "AudioManager autoload unavailable"
		return
	var streams := {}
	var result_cues: Dictionary = manager.get("_result_cues")
	for cue: StringName in result_cues:
		streams["result_" + String(cue)] = result_cues[cue]
	streams["correct"] = manager.correct_player.stream
	streams["explosion"] = manager.explosion_player.stream
	streams["result_impact"] = manager.result_explosion_player.stream
	streams["result_victory"] = manager.result_victory_player.stream
	streams["shark_impact"] = manager.shark_impact_stream
	var reference := {}
	var reference_values: Array[float] = []
	for key: String in streams:
		var stream := streams[key] as AudioStreamWAV
		if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo:
			continue
		var measured: Dictionary = AudioScript.measure(AudioScript.decode(stream), stream.mix_rate)
		reference[key] = {"lufs": measured["lufs"], "peak_db": measured["peak_db"]}
		reference_values.append(float(measured["lufs"]))
	var ours: Array[float] = []
	var cues: Dictionary = report.get("cues", {})
	for cue: StringName in AudioScript.CUES:
		if cue == &"lamp_pass" or not cues.has(String(cue)):
			continue
		ours.append(float(cues[String(cue)]["lufs"]))
	var reference_median := _median(reference_values)
	var ours_median := _median(ours)
	check(reference_values.size() >= 4, "reference cues measured")
	check(absf(ours_median - reference_median) <= 4.0,
		"cue loudness median %.1f within 4 dB of the result cues %.1f" % [ours_median, reference_median])
	var lamp: Dictionary = cues.get("lamp_pass", {})
	check(float(lamp.get("lufs", 0.0)) <= reference_median - 10.0, "lamp_pass stays subtle")
	report["reference"] = {"cues": reference, "median_lufs": reference_median, "sudden_death_median_lufs": ours_median}


func _check_runtime() -> void:
	var bus := AudioServer.get_bus_index(AudioScript.BUS_NAME)
	check(bus >= 0, "SuddenDeath bus exists")
	check(AudioServer.get_bus_send(bus) == AudioScript.SEND_BUS, "SuddenDeath sends to SFX")
	check(AudioServer.get_bus_index(AudioScript.SEND_BUS) < bus, "SFX sits before SuddenDeath")
	var reverb_slot := -1
	var lowpass_slot := -1
	var limiter_slot := -1
	for slot in range(AudioServer.get_bus_effect_count(bus)):
		var effect := AudioServer.get_bus_effect(bus, slot)
		if effect is AudioEffectReverb:
			reverb_slot = slot
		elif effect is AudioEffectLowPassFilter:
			lowpass_slot = slot
		elif effect is AudioEffectHardLimiter:
			limiter_slot = slot
	check(reverb_slot >= 0 and lowpass_slot >= 0 and limiter_slot >= 0, "reverb, low-pass and limiter on the bus")
	if reverb_slot < 0 or lowpass_slot < 0 or limiter_slot < 0:
		return
	var reverb := AudioServer.get_bus_effect(bus, reverb_slot) as AudioEffectReverb
	var lowpass := AudioServer.get_bus_effect(bus, lowpass_slot) as AudioEffectLowPassFilter
	check(reverb_slot < lowpass_slot, "underwater filter muffles the reverb tail too")
	check(not AudioServer.is_bus_effect_enabled(bus, reverb_slot), "reverb starts dry (bypassed)")
	check(not AudioServer.is_bus_effect_enabled(bus, lowpass_slot), "underwater low-pass starts off")
	check(AudioServer.is_bus_effect_enabled(bus, limiter_slot), "limiter is active")
	var runtime := {}

	# One-shots and the 3D voice.
	var played_before := int(_audio.get_debug_snapshot()["cues_played"])
	for cue: StringName in AudioScript.cue_names():
		_audio.play(cue, -6.0)
	var snapshot: Dictionary = _audio.get_debug_snapshot()
	check(int(snapshot["cues_played"]) - played_before == AudioScript.CUES.size(), "every one-shot plays")
	check(int(snapshot["voices_playing"]) >= 8, "voices overlap on the round-robin pool")
	_audio.play(&"no_such_cue")
	_audio.play(AudioScript.LOOP_MOTOR)
	snapshot = _audio.get_debug_snapshot()
	check(int(snapshot["unknown_cues"]) == 2, "unknown cues and loop names are ignored by play()")
	_audio.play_at(&"flood_burst", Vector3(0.0, 0.0, -80.0))
	snapshot = _audio.get_debug_snapshot()
	check(int(snapshot["voices_3d_playing"]) >= 1, "play_at uses a 3D voice")
	var pitches := {}
	for index in range(6):
		_audio.play(&"lamp_pass")
	for child in _audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == AudioScript.get_stream(&"lamp_pass"):
			pitches[snappedf((child as AudioStreamPlayer).pitch_scale, 0.0001)] = true
	check(pitches.size() >= 3, "lamp_pass varies its pitch")

	# Motor: follows |speed|, fades out and stops.
	_audio.set_motor(true, -10.0)
	await _seconds(1.3)
	snapshot = _audio.get_debug_snapshot()
	var motor: Dictionary = snapshot["motor"]
	check(bool(motor["playing"]) and float(motor["gain"]) > 0.95, "motor fades in at full speed (gain %.2f)" % motor["gain"])
	check(absf(float(motor["pitch"]) - AudioScript.MOTOR_PITCH_RANGE.y) < 0.03, "motor pitch rises with |speed| (%.3f)" % motor["pitch"])
	runtime["motor_full"] = motor
	_audio.set_motor(true, 0.0)
	await _seconds(1.5)
	motor = _audio.get_debug_snapshot()["motor"]
	check(absf(float(motor["pitch"]) - AudioScript.MOTOR_PITCH_RANGE.x) < 0.03, "motor pitch settles at idle (%.3f)" % motor["pitch"])
	check(absf(float(motor["gain"]) - AudioScript.MOTOR_IDLE_GAIN) < 0.05, "motor idles quietly (gain %.2f)" % motor["gain"])
	_audio.set_motor(false, 0.0)
	await _seconds(0.3)
	motor = _audio.get_debug_snapshot()["motor"]
	check(bool(motor["playing"]) and float(motor["gain"]) > 0.01, "motor fades rather than cutting off")
	await _seconds(1.6)
	motor = _audio.get_debug_snapshot()["motor"]
	check(not bool(motor["playing"]) and float(motor["gain"]) == 0.0, "motor stops after fading out")

	# Ambience: shaft, then a ~0.8 s crossfade into the hall.
	_audio.set_ambience(&"shaft")
	await _seconds(1.0)
	var ambience: Dictionary = _audio.get_debug_snapshot()["ambience"]
	var front := int(ambience["front"])
	check(bool(ambience["playing"][front]) and float(ambience["gains"][front]) >= 1.0, "shaft ambience fades in")
	_audio.set_ambience(&"hall")
	await _seconds(0.35)
	ambience = _audio.get_debug_snapshot()["ambience"]
	runtime["ambience_mid_crossfade"] = ambience
	check(bool(ambience["playing"][0]) and bool(ambience["playing"][1]), "both ambiences sound during the crossfade")
	await _seconds(0.75)
	ambience = _audio.get_debug_snapshot()["ambience"]
	front = int(ambience["front"])
	check(ambience["slots"][front] == "hall" and float(ambience["gains"][front]) >= 1.0, "hall ambience takes over")
	check(not bool(ambience["playing"][1 - front]), "shaft ambience stops after the crossfade")
	_audio.set_ambience(&"cave")
	check(String(_audio.get_debug_snapshot()["ambience"]["kind"]) == "hall", "unknown ambience is ignored")

	# Reverb: depth curve, then the hall preset from spec 9.
	_audio.set_depth_reverb(1.0)
	await _seconds(2.2)
	check(AudioServer.is_bus_effect_enabled(bus, reverb_slot), "depth reverb enables the effect")
	check(absf(reverb.wet - float(AudioScript.DEEP_REVERB["wet"])) < 0.01 and absf(reverb.room_size - 0.9) < 0.01,
		"deep shaft reverb is long and wet (wet %.3f, room %.3f)" % [reverb.wet, reverb.room_size])
	_audio.set_depth_reverb(0.5)
	await _seconds(2.2)
	check(absf(reverb.wet - float(AudioScript.DEEP_REVERB["wet"]) * 0.5) < 0.01, "half depth gives half the wet level")
	_audio.set_hall_reverb()
	await _seconds(0.9)
	check(is_equal_approx(reverb.room_size, 0.85) and is_equal_approx(reverb.damping, 0.35)
		and is_equal_approx(reverb.wet, 0.35) and is_equal_approx(reverb.predelay_msec, 60.0), "hall reverb matches spec 9")
	runtime["hall_reverb"] = _audio.get_debug_snapshot()["reverb"]

	# Underwater low-pass.
	_audio.set_underwater(true)
	await _seconds(0.8)
	check(AudioServer.is_bus_effect_enabled(bus, lowpass_slot) and absf(lowpass.cutoff_hz - AudioScript.UNDERWATER_CUTOFF_HZ) < 5.0,
		"underwater low-pass closes to %.0f Hz (%.0f)" % [AudioScript.UNDERWATER_CUTOFF_HZ, lowpass.cutoff_hz])
	_audio.set_underwater(false)
	await _seconds(1.0)
	check(not AudioServer.is_bus_effect_enabled(bus, lowpass_slot) and lowpass.cutoff_hz >= 19999.0, "low-pass reopens and bypasses")

	# stop_all: everything silent, bus dry and unfiltered, and it stays that way.
	_audio.set_underwater(true)
	_audio.set_motor(true, 6.0)
	_audio.set_ambience(&"shaft")
	await _seconds(0.5)
	_audio.play(&"siren")
	_audio.play_at(&"drain_burst", Vector3(10.0, 0.0, 0.0))
	_audio.stop_all()
	snapshot = _audio.get_debug_snapshot()
	runtime["after_stop_all"] = snapshot
	check(int(snapshot["voices_playing"]) == 0 and int(snapshot["voices_3d_playing"]) == 0, "stop_all silences every voice")
	check(not bool(snapshot["motor"]["playing"]) and not bool(snapshot["motor"]["active"]), "stop_all stops the motor")
	check(String(snapshot["ambience"]["kind"]) == "none" and not bool(snapshot["ambience"]["playing"][0])
		and not bool(snapshot["ambience"]["playing"][1]), "stop_all stops the ambience")
	check(not AudioServer.is_bus_effect_enabled(bus, reverb_slot) and is_zero_approx(reverb.wet)
		and is_equal_approx(reverb.room_size, float(AudioScript.DRY_REVERB["room_size"])), "stop_all restores the dry reverb")
	check(not AudioServer.is_bus_effect_enabled(bus, lowpass_slot) and lowpass.cutoff_hz >= 19999.0, "stop_all opens the low-pass")
	await _seconds(0.4)
	snapshot = _audio.get_debug_snapshot()
	check(not bool(snapshot["motor"]["playing"]) and not bool(snapshot["ambience"]["playing"][0])
		and not bool(snapshot["ambience"]["playing"][1]) and not AudioServer.is_bus_effect_enabled(bus, reverb_slot),
		"nothing restarts after stop_all")
	report["runtime"] = runtime


func _check_second_instance() -> void:
	var info_before: Dictionary = AudioScript.get_generation_info()
	var whistle := AudioScript.get_stream(&"whistle")
	var second: Node = AudioScript.new()
	add_child(second)
	var started := Time.get_ticks_usec()
	second.setup()
	var setup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	second.play(&"light_on", -9.0)
	var info_after: Dictionary = AudioScript.get_generation_info()
	check(int(info_after["runs"]) == int(info_before["runs"]) and int(info_after["sync_builds"]) == int(info_before["sync_builds"]),
		"a second instance reuses the static cache")
	check(AudioScript.get_stream(&"whistle") == whistle, "cached streams are shared")
	check(setup_ms < 20.0, "second setup() is cheap (%.2f ms)" % setup_ms)
	second.set_hall_reverb()
	await _seconds(0.3)
	second.queue_free()
	await get_tree().process_frame
	var bus := AudioServer.get_bus_index(AudioScript.BUS_NAME)
	var dry := true
	for slot in range(AudioServer.get_bus_effect_count(bus)):
		var effect := AudioServer.get_bus_effect(bus, slot)
		if effect is AudioEffectReverb or effect is AudioEffectLowPassFilter:
			dry = dry and not AudioServer.is_bus_effect_enabled(bus, slot)
	check(dry, "freeing an instance leaves the bus dry")
	report["second_instance"] = {"setup_ms": setup_ms}


func _export_wavs() -> void:
	var exported: Array[String] = []
	for cue: StringName in AudioScript.GENERATION_ORDER:
		var stream := AudioScript.get_stream(cue)
		if stream == null:
			continue
		var path := OUT + String(cue) + ".wav"
		var error := stream.save_to_wav(ProjectSettings.globalize_path(path))
		check(error == OK, "exported %s" % path)
		if error == OK:
			exported.append(path)
	report["exported"] = exported


func _rms(samples: PackedFloat32Array, from: int, to: int) -> float:
	var sum := 0.0
	for i: int in range(from, to):
		sum += samples[i] * samples[i]
	return sqrt(sum / float(maxi(1, to - from)))


func _db(value: float) -> float:
	return 20.0 * log(value) / log(10.0) if value > 0.0 else -120.0


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return -120.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() >> 1])
