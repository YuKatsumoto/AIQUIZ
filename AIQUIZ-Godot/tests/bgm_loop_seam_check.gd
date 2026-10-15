extends SceneTree

## Checks that each BGM loop wraps cleanly in Godot's own decoder (docs/bgm_renewal.md):
## play across the end of the file and compare the samples after the wrap with a playback
## started directly at loop_offset. Also reports the sample step at the wrap.
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/bgm_loop_seam_check.gd

const TRACKS := [
	"res://assets/audio/bgm/quiz_party_loop.ogg",
	"res://assets/audio/bgm/quiz_play_loop.ogg",
	"res://assets/audio/bgm/quiz_result_loop.ogg",
	"res://assets/audio/bgm/quiz_match_loop.ogg",
]
const LEAD_SECONDS := 1.0
const AFTER_SECONDS := 1.0


func _init() -> void:
	var failed := false
	for path: String in TRACKS:
		failed = not _check(path) or failed
	quit(1 if failed else 0)


func _check(path: String) -> bool:
	var stream := load(path) as AudioStreamOggVorbis
	if stream == null:
		printerr("%s: not an AudioStreamOggVorbis" % path)
		return false
	stream.loop = true
	# mix_audio() resamples to the AudioServer rate, not the file's.
	var rate := AudioServer.get_mix_rate()
	var length := stream.get_length()
	var lead := int(LEAD_SECONDS * rate)
	var after := int(AFTER_SECONDS * rate)

	var across := stream.instantiate_playback()
	across.start(length - LEAD_SECONDS)
	var wrapped: PackedVector2Array = across.mix_audio(1.0, lead + after)

	var direct := stream.instantiate_playback()
	direct.start(stream.loop_offset)
	var reference: PackedVector2Array = direct.mix_audio(1.0, after)

	# The resampler (file rate -> mix rate) lands the wrapped audio up to one output frame
	# (23 us at 44.1 kHz) off a fresh playback. Square waves turn that into large per-sample
	# differences, so judge the match by normalized correlation at the best lag.
	var wrap_lag := _best_lag(wrapped.slice(lead, lead + after), reference)
	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0
	for i in range(100, after - 100):
		var a: Vector2 = wrapped[lead + i]
		var b: Vector2 = reference[i + wrap_lag]
		dot += a.dot(b)
		norm_a += a.length_squared()
		norm_b += b.length_squared()
	var corr := dot / sqrt(norm_a * norm_b + 1e-12)

	var steps: Array[float] = []
	for i in range(1, wrapped.size()):
		var d: Vector2 = wrapped[i] - wrapped[i - 1]
		steps.append(maxf(absf(d.x), absf(d.y)))
	var wrap_step: float = steps[lead - 1]
	var sorted := steps.duplicate()
	sorted.sort()
	var p999: float = sorted[int(sorted.size() * 0.999)]

	var ok := absi(wrap_lag) <= 1 and corr >= 0.99 and wrap_step <= p999 * 0.5
	print("%s: mix rate %d | length %.3fs loop_offset %.3fs | after-wrap lag %d frames, corr %.4f | wrap step %.5f, p99.9 step %.5f -> %s" % [
		path.get_file(), int(rate), length, stream.loop_offset, wrap_lag, corr, wrap_step, p999, "OK" if ok else "MISMATCH"])
	return ok


## Lag (frames, b relative to a) that best matches the left channel, searched over +-2000 frames.
func _best_lag(a: PackedVector2Array, b: PackedVector2Array) -> int:
	var n := mini(a.size(), b.size()) - 4000
	var best_lag := 0
	var best := -INF
	for lag in range(-2000, 2001):
		var s := 0.0
		for i in range(2000, n, 7):
			s += a[i].x * b[i + lag].x
		if s > best:
			best = s
			best_lag = lag
	return best_lag
