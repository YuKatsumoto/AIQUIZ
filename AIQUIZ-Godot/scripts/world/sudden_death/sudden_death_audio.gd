class_name SuddenDeathAudio
extends Node
## Procedural sound for the 2P sudden-death branch (docs/sudden_death_underground.md 2.1–2.3,
## 5.6 and 9): the referee whistle and siren, the floor iris, the shaft descent (motor hum,
## wire creaks, passing lamps, echoing drips), the cistern landing and intro, the decisive
## moment and the return to the surface.
##
## Every cue is synthesized in code as a 16-bit mono AudioStreamWAV from seeded noise, like
## the cues in AudioManager. setup() starts one low-priority WorkerThreadPool task that builds
## the cues in timeline order; the streams live in static vars, so a second instance costs
## nothing. A one-shot requested before the task reaches it is built synchronously as a
## fallback (counted in get_debug_snapshot()); loops simply start once their stream is ready.
##
## Each stream is baked to a loudness target (approximate K-weighted momentary loudness, see
## measure()) with its peak capped at about -3 dBFS, so the director can play cues at 0 dB.
## All players use the "SuddenDeath" bus, which sends to "SFX" (user volume) and carries the
## depth/hall reverb, the underwater low-pass and a safety limiter.

const BUS_NAME := &"SuddenDeath"
const SEND_BUS := &"SFX"

const LOOP_MOTOR := &"motor"
const LOOP_SHAFT := &"amb_shaft"
const LOOP_HALL := &"amb_hall"
const AMBIENCE_NONE := &"none"
const AMBIENCE_SHAFT := &"shaft"
const AMBIENCE_HALL := &"hall"
const AMBIENCE_LOOPS := {AMBIENCE_SHAFT: LOOP_SHAFT, AMBIENCE_HALL: LOOP_HALL}

## Peak ceiling of every baked stream (-3.1 dBFS).
const PEAK_LIMIT := 0.7
const ONE_SHOT_VOICES := 10
const POSITIONAL_VOICES := 4
const MOTOR_MAX_SPEED := 10.0
## Motor pitch at standstill and at full descent speed.
const MOTOR_PITCH_RANGE := Vector2(0.7, 1.15)
## Motor loudness (linear) when energized but not moving.
const MOTOR_IDLE_GAIN := 0.3
const MOTOR_GAIN_TAU := 0.22
const MOTOR_PITCH_TAU := 0.3
const AMBIENCE_FADE_SECONDS := 0.8
const DEPTH_REVERB_TAU := 0.45
const HALL_REVERB_TAU := 0.12
const UNDERWATER_CUTOFF_HZ := 480.0
const OPEN_CUTOFF_HZ := 20000.0
const UNDERWATER_TAU := 0.12

## One-shot cues: sample rate, length (s) and baked loudness target (approximate momentary
## LUFS, see measure()). Impacts would hit the peak ceiling long before the target, so
## "drive" soft-saturates them first (tanh) to trade crest factor for body.
const CUES := {
	&"whistle": {"rate": 32000, "seconds": 0.8, "lufs": -15.0},
	&"siren": {"rate": 22050, "seconds": 2.3, "lufs": -15.0},
	&"klaxon": {"rate": 22050, "seconds": 1.0, "lufs": -16.0},
	&"iris_open": {"rate": 22050, "seconds": 1.3, "lufs": -15.0, "drive": 2.0},
	&"iris_close": {"rate": 22050, "seconds": 1.45, "lufs": -15.0, "drive": 2.0},
	&"deck_release": {"rate": 22050, "seconds": 1.5, "lufs": -15.0, "drive": 2.0},
	&"deck_stop": {"rate": 22050, "seconds": 1.3, "lufs": -14.0, "drive": 2.5},
	&"lamp_pass": {"rate": 22050, "seconds": 0.32, "lufs": -30.0},
	&"light_on": {"rate": 22050, "seconds": 0.85, "lufs": -16.0, "drive": 1.6},
	&"landing": {"rate": 22050, "seconds": 1.8, "lufs": -14.0, "drive": 2.5},
	&"gate_open": {"rate": 22050, "seconds": 3.2, "lufs": -16.0, "drive": 1.8},
	&"flood_burst": {"rate": 22050, "seconds": 3.0, "lufs": -13.0, "drive": 2.2},
	&"pump_start": {"rate": 22050, "seconds": 3.6, "lufs": -17.0},
	&"drain_burst": {"rate": 22050, "seconds": 1.8, "lufs": -14.0, "drive": 2.0},
	&"slowmo": {"rate": 22050, "seconds": 1.6, "lufs": -15.0},
	&"win_sting": {"rate": 22050, "seconds": 1.6, "lufs": -14.0, "drive": 1.6},
	&"shout_echo": {"rate": 22050, "seconds": 1.2, "lufs": -16.0},
	# The buzzer duel (早押し): the buzz, right, wrong, the last seconds and the time-up gong.
	&"buzz": {"rate": 32000, "seconds": 0.75, "lufs": -14.0},
	&"correct": {"rate": 32000, "seconds": 1.25, "lufs": -14.0},
	&"wrong": {"rate": 22050, "seconds": 0.95, "lufs": -15.0, "drive": 1.4},
	&"tick": {"rate": 22050, "seconds": 0.12, "lufs": -24.0},
	&"time_up": {"rate": 22050, "seconds": 1.8, "lufs": -16.0},
}
## Seamless loops (whole-cycle tones, crossfaded noise, events placed on the loop circle).
const LOOPS := {
	LOOP_MOTOR: {"rate": 11025, "seconds": 2.0, "lufs": -20.0},
	LOOP_SHAFT: {"rate": 11025, "seconds": 6.0, "lufs": -27.0},
	LOOP_HALL: {"rate": 11025, "seconds": 8.0, "lufs": -27.0},
}
## Build order follows the timeline (whistle at 8.4 s of the ceremony comes first).
const GENERATION_ORDER: Array[StringName] = [
	&"whistle", &"siren", &"klaxon", &"iris_open", LOOP_MOTOR, &"deck_release", &"lamp_pass",
	LOOP_SHAFT, &"deck_stop", &"light_on", &"landing", LOOP_HALL, &"shout_echo", &"gate_open",
	&"flood_burst", &"buzz", &"correct", &"wrong", &"tick", &"time_up", &"slowmo", &"win_sting",
	&"drain_burst", &"iris_close", &"pump_start",
]
## Random pitch spread (± fraction) applied on play() so repeated cues never sound identical.
const PITCH_JITTER := {&"lamp_pass": 0.07, &"light_on": 0.03, &"deck_stop": 0.02, &"klaxon": 0.01}

const REVERB_KEYS: Array[String] = ["room_size", "damping", "wet", "dry", "predelay_msec", "predelay_feedback", "spread", "hipass"]
## Surface: dry (the effect is bypassed once wet reaches zero).
const DRY_REVERB := {"room_size": 0.3, "damping": 0.6, "wet": 0.0, "dry": 1.0, "predelay_msec": 20.0,
	"predelay_feedback": 0.15, "spread": 1.0, "hipass": 0.0}
## Bottom of the shaft: long, wet, with flutter between the concrete walls.
const DEEP_REVERB := {"room_size": 0.9, "damping": 0.3, "wet": 0.33, "dry": 1.0, "predelay_msec": 45.0,
	"predelay_feedback": 0.5, "spread": 1.0, "hipass": 0.0}
## Spec 9: the cistern hall.
const HALL_REVERB := {"room_size": 0.85, "damping": 0.35, "wet": 0.35, "dry": 1.0, "predelay_msec": 60.0,
	"predelay_feedback": 0.4, "spread": 1.0, "hipass": 0.0}

const NOISE_SIZE := 131072
const NOISE_MASK := NOISE_SIZE - 1

static var _streams: Dictionary = {}
static var _stats: Dictionary = {}
static var _cache_mutex: Mutex = Mutex.new()
static var _noise: PackedFloat32Array = PackedFloat32Array()
static var _noise_mutex: Mutex = Mutex.new()
static var _task_id: int = -1
static var _generation_finished: bool = false
static var _generation_ms: float = 0.0
static var _generation_runs: int = 0
static var _sync_builds: int = 0

var _is_setup := false
var _bus_index := -1
var _reverb: AudioEffectReverb
var _lowpass: AudioEffectLowPassFilter
var _reverb_slot := -1
var _lowpass_slot := -1
var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _player_cursor := 0
var _player_3d_cursor := 0
var _motor_player: AudioStreamPlayer
var _ambience_players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _last_tick_usec := 0
var _last_cue: StringName = &""
var _cues_played := 0
var _unknown_cues := 0

var _motor_active := false
var _motor_speed := 0.0
var _motor_gain := 0.0
var _motor_pitch := MOTOR_PITCH_RANGE.x

var _ambience_kind: StringName = AMBIENCE_NONE
var _ambience_front := 0
var _ambience_slot_kind: Array[StringName] = [AMBIENCE_NONE, AMBIENCE_NONE]
var _ambience_gain := PackedFloat32Array([0.0, 0.0])

var _reverb_mode: StringName = &"dry"
var _depth_amount := 0.0
var _reverb_target: Dictionary = DRY_REVERB.duplicate()
var _reverb_current: Dictionary = DRY_REVERB.duplicate()
var _reverb_tau := DEPTH_REVERB_TAU
var _reverb_enabled := false
var _underwater := false
var _lowpass_cutoff := OPEN_CUTOFF_HZ
var _lowpass_enabled := false


# ------------------------------------------------------------------------------ public API

## Creates the bus, the players and starts background synthesis. Safe to call twice.
func setup() -> void:
	if _is_setup:
		return
	_is_setup = true
	_rng.seed = 0x5DA0D10
	_last_tick_usec = Time.get_ticks_usec()
	_ensure_bus()
	for index in range(ONE_SHOT_VOICES):
		_players.append(_make_player("SuddenDeathCue%d" % index))
	for index in range(POSITIONAL_VOICES):
		var player := AudioStreamPlayer3D.new()
		player.name = "SuddenDeathCue3D%d" % index
		player.bus = BUS_NAME
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = 14.0
		player.max_distance = 260.0
		player.max_db = 3.0
		player.attenuation_filter_cutoff_hz = 6000.0
		player.attenuation_filter_db = -18.0
		player.panning_strength = 0.8
		add_child(player)
		_players_3d.append(player)
	_motor_player = _make_player("SuddenDeathMotor")
	for index in range(2):
		_ambience_players.append(_make_player("SuddenDeathAmbience%d" % index))
	_apply_reverb_now(DRY_REVERB)
	_apply_lowpass_now(OPEN_CUTOFF_HZ, false)
	_start_generation(get_script())


## Plays a one-shot cue on the next free voice of the SuddenDeath bus.
func play(cue: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _one_shot_stream(cue)
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _cue_pitch(cue, pitch)
	player.play()


## Plays a one-shot cue from a point in the world (far events such as the flood or the drain).
func play_at(cue: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _one_shot_stream(cue)
	if stream == null:
		return
	var player := _next_player_3d()
	if player.is_inside_tree():
		player.global_position = position
	else:
		player.position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _cue_pitch(cue, pitch)
	player.play()


## Elevator motor hum with wire creaks. Pitch and level follow |speed| (0..10 m/s).
func set_motor(active: bool, speed: float) -> void:
	if not _is_setup:
		setup()
	_motor_active = active
	_motor_speed = speed


## &"none", &"shaft" (low drone + distant drips) or &"hall" (huge room tone + drips), crossfaded.
func set_ambience(kind: StringName) -> void:
	if not _is_setup:
		setup()
	if kind != AMBIENCE_NONE and not AMBIENCE_LOOPS.has(kind):
		_unknown_cues += 1
		return
	if kind == _ambience_kind:
		return
	_ambience_kind = kind
	if kind == AMBIENCE_NONE:
		return
	var slot := -1
	for index in range(2):
		if _ambience_slot_kind[index] == kind:
			slot = index
	if slot < 0:
		slot = 0 if _ambience_gain[0] <= _ambience_gain[1] else 1
		if _ambience_players[slot].playing:
			_ambience_players[slot].stop()
		_ambience_gain[slot] = 0.0
		_ambience_slot_kind[slot] = kind
	_ambience_front = slot


## 0 = surface (dry) .. 1 = bottom of the shaft (long, wet). Smoothed.
func set_depth_reverb(amount: float) -> void:
	if not _is_setup:
		setup()
	_depth_amount = clampf(amount, 0.0, 1.0)
	_reverb_mode = &"depth"
	_reverb_tau = DEPTH_REVERB_TAU
	for key: String in REVERB_KEYS:
		_reverb_target[key] = lerpf(float(DRY_REVERB[key]), float(DEEP_REVERB[key]), _depth_amount)


## The big cistern hall (spec 9). Switches quickly, for the moment the deck enters the hall.
func set_hall_reverb() -> void:
	if not _is_setup:
		setup()
	_reverb_mode = &"hall"
	_reverb_tau = HALL_REVERB_TAU
	_reverb_target = HALL_REVERB.duplicate()


## Low-pass on the bus for the swept player's view.
func set_underwater(on: bool) -> void:
	if not _is_setup:
		setup()
	_underwater = on


## Stops every loop and voice and returns the bus to dry, unfiltered.
func stop_all() -> void:
	for player in _players:
		player.stop()
	for player in _players_3d:
		player.stop()
	if is_instance_valid(_motor_player):
		_motor_player.stop()
	for player in _ambience_players:
		player.stop()
	_motor_active = false
	_motor_speed = 0.0
	_motor_gain = 0.0
	_motor_pitch = MOTOR_PITCH_RANGE.x
	_ambience_kind = AMBIENCE_NONE
	_ambience_slot_kind = [AMBIENCE_NONE, AMBIENCE_NONE]
	_ambience_gain = PackedFloat32Array([0.0, 0.0])
	_underwater = false
	_depth_amount = 0.0
	_reverb_mode = &"dry"
	_reverb_tau = DEPTH_REVERB_TAU
	_reverb_target = DRY_REVERB.duplicate()
	if _is_setup:
		_apply_reverb_now(DRY_REVERB)
		_apply_lowpass_now(OPEN_CUTOFF_HZ, false)


func get_debug_snapshot() -> Dictionary:
	var voices := 0
	for player in _players:
		voices += 1 if player.playing else 0
	var voices_3d := 0
	for player in _players_3d:
		voices_3d += 1 if player.playing else 0
	var ambience_playing: Array[bool] = []
	for player in _ambience_players:
		ambience_playing.append(player.playing)
	var reverb := {"mode": _reverb_mode, "depth": _depth_amount, "enabled": _reverb_enabled}
	for key: String in REVERB_KEYS:
		reverb[key] = float(_reverb_current[key])
	return {
		"setup": _is_setup,
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"bus_send": String(AudioServer.get_bus_send(_bus_index)) if _bus_index >= 0 else "",
		"generation": get_generation_info(),
		"voices_playing": voices,
		"voices_3d_playing": voices_3d,
		"cues_played": _cues_played,
		"last_cue": String(_last_cue),
		"unknown_cues": _unknown_cues,
		"motor": {
			"active": _motor_active,
			"speed": _motor_speed,
			"gain": _motor_gain,
			"pitch": _motor_pitch,
			"playing": is_instance_valid(_motor_player) and _motor_player.playing,
		},
		"ambience": {
			"kind": String(_ambience_kind),
			"front": _ambience_front,
			"slots": [String(_ambience_slot_kind[0]), String(_ambience_slot_kind[1])],
			"gains": [_ambience_gain[0], _ambience_gain[1]],
			"playing": ambience_playing,
		},
		"reverb": reverb,
		"underwater": {"on": _underwater, "enabled": _lowpass_enabled, "cutoff_hz": _lowpass_cutoff},
	}


## True once every cue and loop has been synthesized.
func is_ready() -> bool:
	return is_generation_finished()


# ------------------------------------------------------------------------------ static cache

static func get_stream(cue: StringName) -> AudioStreamWAV:
	_cache_mutex.lock()
	var stream: AudioStreamWAV = _streams.get(cue, null)
	_cache_mutex.unlock()
	return stream


static func is_generation_finished() -> bool:
	_cache_mutex.lock()
	var finished := _generation_finished
	_cache_mutex.unlock()
	return finished


## Per-cue measurements of the baked streams (peak, loudness, gain, build time, NaN count).
static func get_cue_stats() -> Dictionary:
	_cache_mutex.lock()
	var stats := _stats.duplicate(true)
	_cache_mutex.unlock()
	return stats


static func get_generation_info() -> Dictionary:
	_cache_mutex.lock()
	var info := {
		"finished": _generation_finished,
		"ms": _generation_ms,
		"runs": _generation_runs,
		"ready": _streams.size(),
		"total": GENERATION_ORDER.size(),
		"sync_builds": _sync_builds,
		"task_pending": _task_id >= 0,
	}
	_cache_mutex.unlock()
	return info


static func cue_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: StringName in CUES:
		names.append(cue)
	return names


static func loop_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: StringName in LOOPS:
		names.append(cue)
	return names


## Blocks until the background synthesis is done (tests, or a loading screen).
static func wait_for_generation() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Peak, RMS and an approximate momentary loudness: a 1.5 kHz high shelf (+4 dB) and a
## 60 Hz high-pass stand in for K-weighting, measured over the loudest 400 ms window
## (shorter sounds count as if padded to 400 ms). Reported as "lufs" (-0.691 + 10 log10).
static func measure(samples: PackedFloat32Array, rate: int) -> Dictionary:
	var n := samples.size()
	var peak := 0.0
	var sum_sq := 0.0
	var nan_count := 0
	var shelf := 0.0
	var high_pass := 0.0
	var a_shelf := 1.0 - exp(-TAU * 1500.0 / rate)
	var a_hp := 1.0 - exp(-TAU * 60.0 / rate)
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	prefix[0] = 0.0
	var acc := 0.0
	for i: int in n:
		var x := samples[i]
		if is_nan(x) or is_inf(x):
			nan_count += 1
			x = 0.0
		peak = maxf(peak, absf(x))
		sum_sq += x * x
		shelf += (x - shelf) * a_shelf
		var k := x + 0.585 * (x - shelf)
		high_pass += (k - high_pass) * a_hp
		var w := k - high_pass
		acc += w * w
		prefix[i + 1] = acc
	var window := int(0.4 * rate)
	var best := 0.0
	if n <= window:
		best = acc
	else:
		var step := maxi(1, int(0.01 * rate))
		var j := 0
		while j + window <= n:
			best = maxf(best, prefix[j + window] - prefix[j])
			j += step
	best /= float(window)
	return {
		"peak": peak,
		"peak_db": _to_db(peak),
		"rms_db": _to_db(sqrt(sum_sq / float(maxi(n, 1)))),
		"lufs": -0.691 + 10.0 * log(best) / log(10.0) if best > 0.0 else -120.0,
		"nan": nan_count,
		"samples": n,
		"seconds": float(n) / float(rate),
	}


## 16-bit mono stream data back to floats in -1..1.
static func decode(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	var out := PackedFloat32Array()
	out.resize(data.size() >> 1)
	for i: int in out.size():
		out[i] = float(data.decode_s16(i * 2)) / 32768.0
	return out


static func _to_db(linear: float) -> float:
	return 20.0 * log(linear) / log(10.0) if linear > 0.0 else -120.0


static func _info(cue: StringName) -> Dictionary:
	if CUES.has(cue):
		return CUES[cue]
	return LOOPS.get(cue, {})


static func _count(cue: StringName) -> int:
	var info := _info(cue)
	return int(round(float(info["rate"]) * float(info["seconds"])))


static func _start_generation(script: Script) -> void:
	if _task_id >= 0 or is_generation_finished():
		return
	_cache_mutex.lock()
	_generation_runs += 1
	_cache_mutex.unlock()
	_task_id = WorkerThreadPool.add_task(Callable(script, "_generate_all"), false, "SuddenDeathAudio cues")


static func _reap_generation() -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Worker task: builds every cue not cached yet, in timeline order.
static func _generate_all() -> void:
	var started := Time.get_ticks_usec()
	_noise_table()
	for cue: StringName in GENERATION_ORDER:
		if get_stream(cue) == null:
			_build(cue)
	_cache_mutex.lock()
	_generation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_generation_finished = true
	_cache_mutex.unlock()


static func _build(cue: StringName) -> void:
	var started := Time.get_ticks_usec()
	var raw := _synthesize(cue)
	if raw.is_empty():
		return
	var info := _info(cue)
	var rate := int(info["rate"])
	var loop := LOOPS.has(cue)
	var drive := float(info.get("drive", 0.0))
	if drive > 0.0:
		_saturate(raw, drive)
	var nan_count := _condition(raw, rate, loop)
	var measured := measure(raw, rate)
	var gain := 1.0
	var limited_by := "loudness"
	if measured["peak"] > 0.0:
		var loudness_gain := db_to_linear(float(info["lufs"]) - float(measured["lufs"]))
		var peak_gain := PEAK_LIMIT / float(measured["peak"])
		if peak_gain < loudness_gain:
			limited_by = "peak"
		gain = minf(loudness_gain, peak_gain)
	var n := raw.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	var scale := gain * 32767.0
	for i: int in n:
		data.encode_s16(i * 2, int(raw[i] * scale))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	var gain_db := _to_db(gain)
	var stats := {
		"rate": rate,
		"samples": n,
		"seconds": float(n) / float(rate),
		"loop": loop,
		"target_lufs": float(info["lufs"]),
		"lufs": float(measured["lufs"]) + gain_db,
		"peak_db": float(measured["peak_db"]) + gain_db,
		"rms_db": float(measured["rms_db"]) + gain_db,
		"gain_db": gain_db,
		"drive": drive,
		"limited_by": limited_by,
		"nan": nan_count,
		"build_ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}
	_cache_mutex.lock()
	_streams[cue] = stream
	_stats[cue] = stats
	_cache_mutex.unlock()


## Normalizes to a unit peak, then tanh soft-clips with `drive` (unit peak again afterwards).
static func _saturate(raw: PackedFloat32Array, drive: float) -> void:
	var peak := 0.0
	for i: int in raw.size():
		var x := raw[i]
		if not (is_nan(x) or is_inf(x)):
			peak = maxf(peak, absf(x))
	if peak <= 0.0:
		return
	var pre := drive / peak
	var post := 1.0 / tanh(drive)
	for i: int in raw.size():
		raw[i] = tanh(raw[i] * pre) * post


## Removes NaN/inf and DC; one-shots get a 1.5 ms fade-in and a 12 ms fade-out. Loops prime
## the DC blocker with one silent pass so its state is periodic and the seam stays clean.
static func _condition(raw: PackedFloat32Array, rate: int, loop: bool) -> int:
	var n := raw.size()
	var nan_count := 0
	var r := 1.0 - TAU * 15.0 / rate
	var px := 0.0
	var py := 0.0
	if loop:
		for i: int in n:
			var x := raw[i]
			if is_nan(x) or is_inf(x):
				x = 0.0
			py = x - px + r * py
			px = x
	for i: int in n:
		var x := raw[i]
		if is_nan(x) or is_inf(x):
			x = 0.0
			nan_count += 1
		var y := x - px + r * py
		px = x
		py = y
		raw[i] = y
	if not loop:
		var fade_in := maxi(1, int(0.0015 * rate))
		for i: int in mini(fade_in, n):
			raw[i] *= float(i) / float(fade_in)
		var fade_out := mini(n, int(0.012 * rate))
		for j: int in fade_out:
			var w := float(j) / float(fade_out)
			raw[n - 1 - j] *= 0.5 - 0.5 * cos(PI * w)
	return nan_count


static func _noise_table() -> PackedFloat32Array:
	_noise_mutex.lock()
	if _noise.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5D0A7D1E
		var table := PackedFloat32Array()
		table.resize(NOISE_SIZE)
		for i: int in NOISE_SIZE:
			table[i] = rng.randf() * 2.0 - 1.0
		_noise = table
	var result := _noise
	_noise_mutex.unlock()
	return result


static func _synthesize(cue: StringName) -> PackedFloat32Array:
	var nz := _noise_table()
	match cue:
		&"whistle":
			return _cue_whistle(nz)
		&"siren":
			return _cue_siren(nz)
		&"klaxon":
			return _cue_klaxon()
		&"iris_open":
			return _cue_iris(nz, false)
		&"iris_close":
			return _cue_iris(nz, true)
		&"deck_release":
			return _cue_deck_release(nz)
		&"deck_stop":
			return _cue_deck_stop(nz)
		&"lamp_pass":
			return _cue_lamp_pass(nz)
		&"light_on":
			return _cue_light_on(nz)
		&"landing":
			return _cue_landing(nz)
		&"gate_open":
			return _cue_gate_open(nz)
		&"flood_burst":
			return _cue_flood_burst(nz)
		&"pump_start":
			return _cue_pump_start(nz)
		&"drain_burst":
			return _cue_drain_burst(nz)
		&"slowmo":
			return _cue_slowmo(nz)
		&"win_sting":
			return _cue_win_sting(nz)
		&"shout_echo":
			return _cue_shout_echo()
		&"buzz":
			return _cue_buzz()
		&"correct":
			return _cue_correct()
		&"wrong":
			return _cue_wrong()
		&"tick":
			return _cue_tick()
		&"time_up":
			return _cue_time_up()
		LOOP_MOTOR:
			return _loop_motor(nz)
		LOOP_SHAFT:
			return _loop_shaft(nz)
		LOOP_HALL:
			return _loop_hall(nz)
	return PackedFloat32Array()


# ------------------------------------------------------------------------------ DSP helpers

static func _alloc(n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	return buf


## One-pole low-pass coefficient for a cutoff in Hz.
static func _one_pole(hz: float, rate: float) -> float:
	return 1.0 - exp(-TAU * hz / rate)


## Adds `src` scaled so that its own peak lands at `peak`.
static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, peak: float) -> void:
	var p := 0.0
	for i: int in src.size():
		p = maxf(p, absf(src[i]))
	if p <= 0.0:
		return
	var g := peak / p
	for i: int in mini(dst.size(), src.size()):
		dst[i] += src[i] * g


## Folds the overhang past `n` back onto the start with an equal-power crossfade, so noise
## rendered continuously for n + x samples loops without a seam.
static func _fold_loop(src: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := src.slice(0, n)
	var x := src.size() - n
	for j: int in x:
		var w := float(j) / float(x) * PI * 0.5
		out[j] = src[j] * sin(w) + src[n + j] * cos(w)
	return out


## Modal ring: exponentially decaying sines (damped-oscillator recursion, no per-sample exp).
static func _add_modes(buf: PackedFloat32Array, rate: float, start: int, freqs: Array, decays: Array,
		amps: Array, wrap := false) -> void:
	var n := buf.size()
	for m: int in freqs.size():
		var w := TAU * float(freqs[m]) / rate
		if w >= PI * 0.95:
			continue
		var r := exp(-float(decays[m]) / rate)
		var count := mini(int(7.6 / float(decays[m]) * rate), n - 1)
		var a1 := 2.0 * r * cos(w)
		var a2 := r * r
		var y2 := 0.0
		var y1 := float(amps[m]) * r * sin(w)
		for k: int in range(1, count):
			var index := start + k
			if index >= n:
				if not wrap:
					break
				index -= n
			buf[index] += y1
			var y := a1 * y1 - a2 * y2
			y2 = y1
			y1 = y


## Low thud whose pitch falls from f_hi toward f_lo.
static func _add_thump(buf: PackedFloat32Array, rate: float, start: int, f_hi: float, f_lo: float,
		sweep: float, decay: float, amp: float) -> void:
	var count := mini(buf.size() - start, int(7.6 / decay * rate) + 1)
	var k := exp(-decay / rate)
	var ks := exp(-sweep / rate)
	var env := 1.0
	var bend := 1.0
	var phase := 0.0
	var attack_samples := 0.0015 * rate
	for j: int in count:
		phase += TAU * (f_lo + (f_hi - f_lo) * bend) / rate
		buf[start + j] += sin(phase) * env * minf(1.0, float(j) / attack_samples) * amp
		env *= k
		bend *= ks


## Decaying low-passed noise burst; `amp` is roughly its peak whatever the cutoff.
static func _add_burst(buf: PackedFloat32Array, nz: PackedFloat32Array, rate: float, start: int,
		decay: float, amp: float, lp_hz: float, offset: int) -> void:
	var count := mini(buf.size() - start, int(7.6 / decay * rate) + 1)
	var a := _one_pole(lp_hz, rate)
	var g := amp * 0.6 * sqrt((2.0 - a) / a)
	var k := exp(-decay / rate)
	var env := 1.0
	var lp := 0.0
	for j: int in count:
		lp += (nz[(j + offset) & NOISE_MASK] - lp) * a
		buf[start + j] += lp * env * g
		env *= k


## Water drop: a short sine whose pitch rises as the bubble closes.
static func _add_drip(buf: PackedFloat32Array, rate: float, start: int, f0: float, amp: float,
		wrap: bool) -> void:
	var n := buf.size()
	var count := int(0.09 * rate)
	var phase := 0.0
	var env := 1.0
	var k := exp(-42.0 / rate)
	var rise := 1.0
	var kr := exp(-45.0 / rate)
	var attack_samples := 0.0007 * rate
	for j: int in count:
		phase += TAU * f0 * (1.8 - 0.8 * rise) / rate
		var index := start + j
		if index >= n:
			if not wrap:
				return
			index -= n
		buf[index] += sin(phase) * env * minf(1.0, float(j) / attack_samples) * amp
		env *= k
		rise *= kr


## Stiff steel cable pluck (inharmonic partials, pitch sagging as the load settles).
static func _add_twang(buf: PackedFloat32Array, rate: float, start: int, f0: float, partials: int,
		base_decay: float, peak: float) -> void:
	var n := buf.size()
	var tone := _alloc(n)
	var phases := PackedFloat64Array()
	var freqs := PackedFloat64Array()
	var envs := PackedFloat64Array()
	var mults := PackedFloat64Array()
	for k: int in partials:
		var h := float(k + 1)
		phases.append(0.0)
		freqs.append(f0 * h * sqrt(1.0 + 0.004 * h * h))
		envs.append(1.0 / pow(h, 0.6))
		mults.append(exp(-(base_decay + 0.9 * h) / rate))
	var bend := 1.0
	var kb := exp(-7.0 / rate)
	for j: int in n - start:
		var v := 0.0
		var scale := TAU * (1.0 + 0.05 * bend) / rate
		for k: int in partials:
			phases[k] += freqs[k] * scale
			v += sin(phases[k]) * envs[k]
			envs[k] *= mults[k]
		tone[start + j] = v * minf(1.0, float(j) / (0.002 * rate))
		bend *= kb
	_mix(buf, tone, peak)


## Wire creak (stick-slip pulses through cable/sheave resonances) placed on a loop circle.
static func _add_creak_circular(buf: PackedFloat32Array, rate: float, at: float, duration: float,
		f_res: float, slip_from: float, slip_to: float, peak: float, nz: PackedFloat32Array, offset: int) -> void:
	var n := buf.size()
	var count := int(duration * rate)
	var temp := _alloc(count)
	var freqs := [f_res, f_res * 2.13, minf(f_res * 3.41, rate * 0.42)]
	var bws := [14.0, 20.0, 30.0]
	var gains := [1.0, 0.5, 0.25]
	var a1 := PackedFloat64Array()
	var a2 := PackedFloat64Array()
	var b0 := PackedFloat64Array()
	var y1 := PackedFloat64Array([0.0, 0.0, 0.0])
	var y2 := PackedFloat64Array([0.0, 0.0, 0.0])
	for m: int in 3:
		var w := TAU * float(freqs[m]) / rate
		var r := exp(-PI * float(bws[m]) / rate)
		a1.append(2.0 * r * cos(w))
		a2.append(r * r)
		b0.append(1.0 - r)
	var slip := 0.0
	for j: int in count:
		var t := float(j) / rate
		var p := t / duration
		slip += (lerpf(slip_from, slip_to, p) + 4.0 * sin(TAU * 3.0 * t)) / rate
		var x := nz[(j + offset * 7919) & NOISE_MASK]
		var exc := x * 0.04
		if slip >= 1.0:
			slip -= 1.0
			exc += 1.0 + 0.5 * x
		var s := 0.0
		for m: int in 3:
			var y := b0[m] * exc + a1[m] * y1[m] - a2[m] * y2[m]
			y2[m] = y1[m]
			y1[m] = y
			s += y * float(gains[m])
		temp[j] = s * pow(sin(PI * p), 0.7)
	var temp_peak := 0.0
	for j: int in count:
		temp_peak = maxf(temp_peak, absf(temp[j]))
	if temp_peak <= 0.0:
		return
	var g := peak / temp_peak
	var start := int(at * rate)
	for j: int in count:
		buf[(start + j) % n] += temp[j] * g


# ------------------------------------------------------------------------------ one-shot cues

## Referee pea whistle: two short blasts with the pea's trill.
static func _cue_whistle(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 32000.0
	var buf := _alloc(_count(&"whistle"))
	var blasts: Array[Vector3] = [Vector3(0.03, 0.17, 2950.0), Vector3(0.30, 0.38, 3040.0)]
	for blast: Vector3 in blasts:
		var start := int(blast.x * rate)
		var count := mini(int(blast.y * rate), buf.size() - start)
		var phase := 0.0
		var low := 0.0
		var band := 0.0
		var offset := start * 3 + 101
		for j: int in count:
			var t := float(j) / rate
			var env := smoothstep(0.0, 0.006, t) * smoothstep(blast.y, blast.y - 0.035, t) * (1.0 + 0.3 * exp(-t * 35.0))
			var trill := sin(TAU * 36.0 * t + 1.2 * sin(TAU * 6.0 * t))
			var f := blast.z * (1.0 + 0.017 * trill - 0.04 * exp(-t * 70.0))
			phase += TAU * f / rate
			var tone := sin(phase) + 0.12 * sin(2.0 * phase) + 0.04 * sin(3.0 * phase)
			var x := nz[(j + offset) & NOISE_MASK]
			var fc := 2.0 * sin(PI * f / rate)
			low += fc * band
			var high := x - low - 0.25 * band
			band += fc * high
			var am := 0.6 + 0.4 * (0.5 + 0.5 * trill)
			buf[start + j] = (tone * am * 0.75 + band * 0.12 + x * 0.02) * env
	return buf


## Motor-driven industrial siren (two chambers a minor third apart): spins up, holds, coasts.
static func _cue_siren(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"siren")
	var duration := float(n) / rate
	var buf := _alloc(n)
	var p1 := 0.0
	var p2 := 0.0
	var low := 0.0
	var band := 0.0
	for i: int in n:
		var t := float(i) / rate
		var f: float
		if t < 1.15:
			var p := t / 1.15
			f = lerpf(165.0, 770.0, 1.0 - (1.0 - p) * (1.0 - p))
		elif t < 1.45:
			f = 770.0 * (1.0 + 0.006 * sin(TAU * 4.5 * (t - 1.15)))
		else:
			f = 225.0 + 545.0 * exp(-(t - 1.45) * 2.4)
		var spin := clampf((f - 165.0) / 605.0, 0.0, 1.0)
		var env := smoothstep(0.0, 0.16, t) * (0.3 + 0.7 * spin) * smoothstep(duration, duration - 0.45, t)
		p1 += TAU * f / rate
		p2 += TAU * f * 1.2 / rate
		var x := 0.62 * sin(p1) + 0.38 * sin(p2)
		x = x * 1.7 / (1.0 + absf(x * 1.7))
		var fc := 2.0 * sin(PI * minf(f * 2.0, 3600.0) / rate)
		low += fc * band
		var high := nz[(i + 977) & NOISE_MASK] - low - 0.6 * band
		band += fc * high
		buf[i] = (x * 0.85 + band * 0.25 * spin) * env
	return buf


## Electromechanical alarm horn: two harsh honks.
static func _cue_klaxon() -> PackedFloat32Array:
	var rate := 22050.0
	var buf := _alloc(_count(&"klaxon"))
	var honks: Array[Vector2] = [Vector2(0.0, 0.34), Vector2(0.46, 0.44)]
	var fc := 2.0 * sin(PI * 1150.0 / rate)
	var a_lp := _one_pole(4500.0, rate)
	for honk: Vector2 in honks:
		var start := int(honk.x * rate)
		var count := mini(int(honk.y * rate), buf.size() - start)
		var phase := 0.0
		var low := 0.0
		var band := 0.0
		var lp := 0.0
		for j: int in count:
			var t := float(j) / rate
			var env := smoothstep(0.0, 0.012, t) * smoothstep(honk.y, honk.y - 0.045, t)
			var dt := 330.0 * (1.0 - 0.07 * exp(-t * 30.0)) * (1.0 + 0.003 * sin(TAU * 9.0 * t)) / rate
			phase += dt
			if phase >= 1.0:
				phase -= 1.0
			var saw := 2.0 * phase - 1.0
			if phase < dt:
				var q := phase / dt
				saw -= q + q - q * q - 1.0
			elif phase > 1.0 - dt:
				var q := (phase - 1.0) / dt
				saw -= q * q + q + q + 1.0
			low += fc * band
			var high := saw - low - 0.35 * band
			band += fc * high
			var y := saw * 0.3 + band * 0.5
			y = clampf(y * 2.2, -1.0, 1.0) * 0.55 + y * 0.25
			lp += (y - lp) * a_lp
			buf[start + j] = lp * env
	return buf


## Floor iris: hydraulic valve hiss, cylinder groan, steel leaves scraping, then the clunk.
## Closing runs lower, ends with a locking bolt and a long pressure-release hiss.
static func _cue_iris(nz: PackedFloat32Array, closing: bool) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"iris_close" if closing else &"iris_open")
	var buf := _alloc(n)
	var hiss := _alloc(n)
	var groan := _alloc(n)
	var scrape := _alloc(n)
	var t_clunk := 0.56 if closing else 0.6
	var shift := 0.88 if closing else 1.0
	var mode_freq := [760.0 * shift, 1310.0 * shift, 2140.0 * shift, 3020.0 * shift]
	var mode_bw := [9.0, 14.0, 22.0, 30.0]
	var mode_gain := PackedFloat64Array([1.0, 0.75, 0.5, 0.3])
	var a1 := PackedFloat64Array()
	var a2 := PackedFloat64Array()
	var b0 := PackedFloat64Array()
	var y1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var y2 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for m: int in 4:
		var w := TAU * float(mode_freq[m]) / rate
		var r := exp(-PI * float(mode_bw[m]) / rate)
		a1.append(2.0 * r * cos(w))
		a2.append(r * r)
		b0.append(1.0 - r)
	var hiss_low := 0.0
	var hiss_band := 0.0
	var hiss_f := 2.0 * sin(PI * 4200.0 / rate)
	var rumble := 0.0
	var a_rumble := _one_pole(160.0, rate)
	var groan_phase := 0.0
	var slip := 0.0
	var offset := 3301 if closing else 1709
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + offset) & NOISE_MASK]
		var hiss_env: float
		if closing:
			hiss_env = 0.35 * smoothstep(0.0, 0.01, t) * smoothstep(0.24, 0.06, t)
			if t > t_clunk + 0.08:
				hiss_env += smoothstep(t_clunk + 0.08, t_clunk + 0.12, t) * exp(-(t - t_clunk - 0.08) * 2.8)
		else:
			hiss_env = smoothstep(0.0, 0.005, t) * (0.3 + 0.7 * exp(-t * 12.0)) * smoothstep(1.0, 0.45, t)
		hiss_low += hiss_f * hiss_band
		var hiss_high := x - hiss_low - 0.9 * hiss_band
		hiss_band += hiss_f * hiss_high
		hiss[i] = (hiss_band + hiss_high * 0.3) * hiss_env
		var moving := smoothstep(0.04, 0.12, t) * smoothstep(t_clunk + 0.01, t_clunk - 0.04, t)
		var progress := clampf(t / t_clunk, 0.0, 1.0)
		var groan_f := lerpf(84.0, 58.0, progress) if closing else lerpf(58.0, 84.0, progress)
		groan_phase += TAU * groan_f / rate
		rumble += (x - rumble) * a_rumble
		groan[i] = (sin(groan_phase) * 0.5 + sin(groan_phase * 2.0) * 0.25 + rumble * 4.0) * moving
		slip += (30.0 + 14.0 * sin(TAU * 2.7 * t) + (12.0 if closing else 0.0)) / rate
		var exc := x * 0.3
		if slip >= 1.0:
			slip -= 1.0
			exc += 1.2 + 0.8 * x
		exc *= moving
		var s := 0.0
		for m: int in 4:
			var y := b0[m] * exc + a1[m] * y1[m] - a2[m] * y2[m]
			y2[m] = y1[m]
			y1[m] = y
			s += y * mode_gain[m]
		scrape[i] = s
	_mix(buf, hiss, 0.3)
	_mix(buf, groan, 0.32)
	_mix(buf, scrape, 0.45)
	var ic := int(t_clunk * rate)
	_add_thump(buf, rate, ic, 64.0 if closing else 76.0, 38.0 if closing else 46.0, 16.0, 10.0, 1.0)
	_add_modes(buf, rate, ic, [410.0 * shift, 1130.0 * shift, 1870.0 * shift, 2730.0 * shift],
		[9.0, 13.0, 18.0, 26.0], [0.35, 0.22, 0.12, 0.07])
	_add_burst(buf, nz, rate, ic, 320.0, 0.6, 6000.0, offset + 7)
	if closing:
		var bolt := int((t_clunk + 0.15) * rate)
		_add_thump(buf, rate, bolt, 120.0, 80.0, 30.0, 26.0, 0.35)
		_add_modes(buf, rate, bolt, [1650.0, 2900.0], [40.0, 60.0], [0.12, 0.06])
	else:
		var rattles := [Vector2(0.07, 0.1), Vector2(0.13, 0.06), Vector2(0.21, 0.035)]
		for rattle: Vector2 in rattles:
			_add_modes(buf, rate, ic + int(rattle.x * rate), [1500.0, 2650.0], [50.0, 70.0], [rattle.y, rattle.y * 0.6])
	return buf


## Deck brake: solenoid clank, pneumatic release and the hoist wires twanging under load.
static func _cue_deck_release(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"deck_release")
	var buf := _alloc(n)
	_add_burst(buf, nz, rate, 0, 520.0, 0.8, 8000.0, 4409)
	_add_modes(buf, rate, 0, [520.0, 1270.0, 2340.0, 3900.0], [22.0, 30.0, 40.0, 55.0], [0.45, 0.32, 0.2, 0.1])
	_add_thump(buf, rate, 0, 150.0, 92.0, 30.0, 28.0, 0.4)
	var hiss := _alloc(n)
	var low := 0.0
	var band := 0.0
	var f := 2.0 * sin(PI * 2800.0 / rate)
	for i: int in n:
		var t := float(i) / rate
		if t > 1.4:
			break
		var env := smoothstep(0.015, 0.04, t) * exp(-maxf(0.0, t - 0.04) * 6.0)
		var x := nz[(i + 5113) & NOISE_MASK]
		low += f * band
		var high := x - low - band
		band += f * high
		hiss[i] = (band + high * 0.4) * env
	_mix(buf, hiss, 0.22)
	_add_twang(buf, rate, int(0.05 * rate), 68.0, 8, 2.4, 0.55)
	return buf


## Heavy stop: deep thud, steel frame ring, grating rattle, a bounce and the cables loading.
static func _cue_deck_stop(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"deck_stop")
	var buf := _alloc(n)
	_add_thump(buf, rate, 0, 62.0, 36.0, 10.0, 6.5, 1.0)
	_add_thump(buf, rate, 0, 135.0, 95.0, 25.0, 22.0, 0.45)
	_add_burst(buf, nz, rate, 0, 120.0, 0.5, 3000.0, 6007)
	_add_modes(buf, rate, 0, [180.0, 455.0, 920.0, 1630.0, 2480.0], [7.0, 10.0, 14.0, 20.0, 28.0],
		[0.3, 0.25, 0.18, 0.1, 0.06])
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEC57
	var t := 0.03
	var amp := 0.22
	while t < 0.4:
		var i := int(t * rate)
		_add_modes(buf, rate, i, [rng.randf_range(1900.0, 2300.0), rng.randf_range(3000.0, 3500.0)], [70.0, 95.0],
			[amp, amp * 0.5])
		_add_burst(buf, nz, rate, i, 700.0, amp * 0.6, 7000.0, i)
		t += rng.randf_range(0.025, 0.05)
		amp *= 0.8
	_add_thump(buf, rate, int(0.42 * rate), 72.0, 52.0, 20.0, 14.0, 0.25)
	_add_twang(buf, rate, int(0.02 * rate), 46.0, 6, 3.5, 0.22)
	return buf


## A lamp ring sliding past: muffled air whoosh, a cage tick and a breath of ballast buzz.
static func _cue_lamp_pass(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"lamp_pass")
	var buf := _alloc(n)
	var duration := float(n) / rate
	var whoosh := _alloc(n)
	var hum := _alloc(n)
	var low := 0.0
	var band := 0.0
	for i: int in n:
		var t := float(i) / rate
		var p := clampf(t / (duration - 0.02), 0.0, 1.0)
		var env := pow(sin(PI * p), 1.8)
		var f := 2.0 * sin(PI * lerpf(950.0, 380.0, p) / rate)
		var x := nz[(i + 7919) & NOISE_MASK]
		low += f * band
		var high := x - low - 1.1 * band
		band += f * high
		whoosh[i] = (band * 0.8 + low * 0.3) * env
		var bell := (t - 0.11) / 0.05
		hum[i] = (sin(TAU * 100.0 * t) + 0.5 * sin(TAU * 200.0 * t) + 0.25 * sin(TAU * 300.0 * t)) * exp(-bell * bell)
	_mix(buf, whoosh, 0.5)
	_mix(buf, hum, 0.12)
	_add_modes(buf, rate, int(0.1 * rate), [2350.0, 3480.0], [170.0, 240.0], [0.1, 0.05])
	return buf


## Contactor slamming in (click + armature clunk) and a burst of 50 Hz mains hum with sizzle.
static func _cue_light_on(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"light_on")
	var buf := _alloc(n)
	var duration := float(n) / rate
	_add_burst(buf, nz, rate, 0, 900.0, 0.9, 10000.0, 9001)
	_add_modes(buf, rate, 0, [3100.0, 4700.0], [120.0, 160.0], [0.22, 0.1])
	var body := int(0.004 * rate)
	_add_modes(buf, rate, body, [240.0, 610.0, 1450.0], [26.0, 34.0, 48.0], [0.42, 0.28, 0.14])
	_add_thump(buf, rate, body, 115.0, 72.0, 30.0, 28.0, 0.55)
	var hum := _alloc(n)
	var amps := PackedFloat64Array([0.0, 0.25, 1.0, 0.45, 0.6, 0.22, 0.3, 0.1, 0.14, 0.05, 0.07])
	for i: int in n:
		var t := float(i) / rate
		var theta := TAU * 50.0 * t
		var c := cos(theta)
		var s_prev := 0.0
		var s := sin(theta)
		var v := 0.0
		for k: int in range(1, amps.size()):
			v += amps[k] * s
			var s_next := 2.0 * c * s - s_prev
			s_prev = s
			s = s_next
		var arc := absf(2.0 * sin(theta) * c)
		arc *= arc
		arc *= arc
		arc *= arc
		var settle := exp(-maxf(0.0, t - 0.02) * 9.0)
		var sizzle := nz[(i + 9203) & NOISE_MASK] * arc * settle
		var env := smoothstep(0.006, 0.02, t) * (0.12 + 0.88 * settle) * smoothstep(duration, duration - 0.45, t)
		hum[i] = (v + sizzle * 0.6) * env
	_mix(buf, hum, 0.38)
	return buf


## Deck touching down in the cistern: deep thud, deck ring, then the puddles sloshing.
static func _cue_landing(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"landing")
	var buf := _alloc(n)
	_add_thump(buf, rate, 0, 56.0, 32.0, 8.0, 4.5, 1.0)
	_add_thump(buf, rate, 0, 104.0, 80.0, 20.0, 18.0, 0.45)
	_add_burst(buf, nz, rate, 0, 90.0, 0.42, 2500.0, 12011)
	_add_modes(buf, rate, 0, [210.0, 530.0, 1180.0, 2050.0], [9.0, 13.0, 19.0, 27.0], [0.26, 0.2, 0.11, 0.06])
	var slosh := _alloc(n)
	var spray := _alloc(n)
	var lp := 0.0
	var lp2 := 0.0
	var a_spray := _one_pole(2500.0, rate)
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + 15013) & NOISE_MASK]
		var swell := smoothstep(0.02, 0.12, t) * (0.55 + 0.45 * sin(TAU * 2.1 * t - 1.0)) * exp(-t * 1.5)
		var w := TAU * (500.0 + 1500.0 * swell) / rate
		lp += (x - lp) * (w / (1.0 + w))
		slosh[i] = lp * swell
		lp2 += (x - lp2) * a_spray
		spray[i] = (x - lp2) * smoothstep(0.02, 0.04, t) * exp(-maxf(0.0, t - 0.04) * 7.0)
	_mix(buf, slosh, 0.5)
	_mix(buf, spray, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1A4D
	for k: int in 14:
		var at := rng.randf_range(0.15, 1.45)
		_add_drip(buf, rate, int(at * rate), rng.randf_range(700.0, 1800.0), 0.12 * (1.0 - (at - 0.15) / 1.4 * 0.7), false)
	return buf


## Huge roller gate grinding up: unlatch clunk, drive motor, grinding guides, roller-chain clatter.
static func _cue_gate_open(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"gate_open")
	var duration := float(n) / rate
	var buf := _alloc(n)
	_add_thump(buf, rate, 0, 70.0, 45.0, 12.0, 9.0, 0.55)
	_add_modes(buf, rate, 0, [330.0, 870.0, 1520.0, 2400.0], [8.0, 12.0, 17.0, 24.0], [0.21, 0.14, 0.08, 0.04])
	_add_burst(buf, nz, rate, 0, 200.0, 0.35, 5000.0, 17011)
	var motor := _alloc(n)
	var grind := _alloc(n)
	var motor_phase := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var a140 := _one_pole(140.0, rate)
	var gl := 0.0
	var gb := 0.0
	var gf := 2.0 * sin(PI * 520.0 / rate)
	var freqs := [310.0, 760.0, 1240.0]
	var bws := [18.0, 25.0, 35.0]
	var a1 := PackedFloat64Array()
	var a2 := PackedFloat64Array()
	var b0 := PackedFloat64Array()
	var y1 := PackedFloat64Array([0.0, 0.0, 0.0])
	var y2 := PackedFloat64Array([0.0, 0.0, 0.0])
	for m: int in 3:
		var w := TAU * float(freqs[m]) / rate
		var r := exp(-PI * float(bws[m]) / rate)
		a1.append(2.0 * r * cos(w))
		a2.append(r * r)
		b0.append(1.0 - r)
	var slip := 0.0
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + 19001) & NOISE_MASK]
		var run := smoothstep(0.15, 0.6, t) * smoothstep(duration, duration - 0.7, t)
		motor_phase += TAU * lerpf(46.0, 54.0, smoothstep(0.15, 0.8, t)) / rate
		r1 += (x - r1) * a140
		r2 += (r1 - r2) * a140
		motor[i] = (sin(motor_phase) * 0.4 + sin(motor_phase * 2.0) * 0.25 + sin(motor_phase * 3.0) * 0.08 + r2 * 6.0) * run
		var rough := 0.35 + 0.65 * absf(sin(TAU * 5.3 * t + 2.0 * sin(TAU * 1.7 * t)))
		slip += (22.0 + 9.0 * sin(TAU * 1.3 * t)) / rate
		var exc := x * rough * 0.5
		if slip >= 1.0:
			slip -= 1.0
			exc += 1.0 + 0.7 * nz[(i * 3 + 23) & NOISE_MASK]
		exc *= smoothstep(0.3, 0.8, t) * smoothstep(duration, duration - 0.6, t)
		gl += gf * gb
		var gh := exc - gl - 1.2 * gb
		gb += gf * gh
		var s := gb * 0.5
		for m: int in 3:
			var y := b0[m] * exc + a1[m] * y1[m] - a2[m] * y2[m]
			y2[m] = y1[m]
			y1[m] = y
			s += y
		grind[i] = s
	_mix(buf, motor, 0.45)
	_mix(buf, grind, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6A7E
	var tick := 0.42
	while tick < duration - 0.4:
		var amp := rng.randf_range(0.06, 0.13) * smoothstep(duration - 0.4, duration - 0.9, tick)
		_add_modes(buf, rate, int(tick * rate), [rng.randf_range(1800.0, 2100.0), rng.randf_range(2800.0, 3100.0), 620.0],
			[90.0, 130.0, 50.0], [amp, amp * 0.6, amp * 0.5])
		tick += 1.0 / 9.5 + rng.randf_range(-0.006, 0.006)
	return buf


## Water bursting out of the inflow tunnel: a crack and boom, then the roar building.
static func _cue_flood_burst(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"flood_burst")
	var duration := float(n) / rate
	var buf := _alloc(n)
	_add_burst(buf, nz, rate, 0, 16.0, 0.85, 4500.0, 21001)
	_add_thump(buf, rate, 0, 52.0, 30.0, 5.0, 3.5, 0.9)
	var low := _alloc(n)
	var mid := _alloc(n)
	var high := _alloc(n)
	var l1 := 0.0
	var l2 := 0.0
	var a220 := _one_pole(220.0, rate)
	var ml := 0.0
	var mb := 0.0
	var mf := 2.0 * sin(PI * 900.0 / rate)
	var hl := 0.0
	var a3500 := _one_pole(3500.0, rate)
	var turbulence := 0.0
	var a_turb := _one_pole(6.0, rate)
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + 25013) & NOISE_MASK]
		var y := nz[(i + 61001) & NOISE_MASK]
		turbulence += (nz[(i * 7 + 3) & NOISE_MASK] - turbulence) * a_turb
		var churn := clampf(1.0 + 12.0 * turbulence, 0.5, 1.5)
		var fade := smoothstep(duration, duration - 0.8, t)
		var env_low := smoothstep(0.02, 0.7, t) * fade
		var env_high := smoothstep(0.0, 0.25, t) * (0.6 + 0.4 * exp(-t * 1.5)) * fade
		l1 += (x - l1) * a220
		l2 += (l1 - l2) * a220
		low[i] = l2 * env_low * churn
		ml += mf * mb
		var mh := y - ml - 1.4 * mb
		mb += mf * mh
		mid[i] = mb * env_low * churn
		hl += (x - hl) * a3500
		high[i] = (x - hl) * env_high * (2.0 - churn)
	_mix(buf, low, 0.75)
	_mix(buf, mid, 0.45)
	_mix(buf, high, 0.25)
	return buf


## Gas-turbine drainage pump spinning up: starter relay, rising whine, ignition, combustion roar.
static func _cue_pump_start(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"pump_start")
	var duration := float(n) / rate
	var buf := _alloc(n)
	_add_burst(buf, nz, rate, 0, 600.0, 0.35, 9000.0, 27011)
	_add_modes(buf, rate, 0, [2600.0, 4100.0], [90.0, 140.0], [0.12, 0.05])
	var whine := _alloc(n)
	var roar := _alloc(n)
	var intake := _alloc(n)
	var phase := 0.0
	var blade_phase := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var il := 0.0
	var a900 := _one_pole(900.0, rate)
	var a120 := _one_pole(120.0, rate)
	var a2500 := _one_pole(2500.0, rate)
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + 37003) & NOISE_MASK]
		var spool := 1.0 - exp(-t * 0.85)
		var f := 90.0 + 1500.0 * spool
		phase += TAU * f / rate
		blade_phase += TAU * f * 4.7 / rate
		var fade := smoothstep(duration, duration - 0.6, t)
		var tone := sin(phase) * 0.5 + sin(phase * 2.0) * 0.28 + sin(phase * 3.0) * 0.1 + sin(blade_phase) * 0.18 * spool
		whine[i] = tone * smoothstep(0.0, 0.35, t) * fade
		r1 += (x - r1) * a900
		r2 += (r1 - r2) * a120
		roar[i] = (r1 * 0.6 + r2 * 2.5) * smoothstep(1.0, 2.2, t) * fade
		il += (x - il) * a2500
		intake[i] = (x - il) * spool * fade
	_mix(buf, whine, 0.42)
	_mix(buf, roar, 0.5)
	_mix(buf, intake, 0.12)
	var ignition := int(1.0 * rate)
	_add_thump(buf, rate, ignition, 80.0, 40.0, 9.0, 7.0, 0.65)
	_add_burst(buf, nz, rate, ignition, 12.0, 0.45, 900.0, 29011)
	return buf


## Water column erupting from a surface drain: gurgle, pressure pop, gush, then splatter.
static func _cue_drain_burst(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"drain_burst")
	var duration := float(n) / rate
	var buf := _alloc(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD7A1
	for k: int in 5:
		_add_drip(buf, rate, int(rng.randf_range(0.0, 0.14) * rate), rng.randf_range(260.0, 560.0), 0.3, false)
	var pop := int(0.16 * rate)
	_add_thump(buf, rate, pop, 85.0, 45.0, 12.0, 10.0, 0.9)
	_add_burst(buf, nz, rate, pop, 30.0, 0.6, 2500.0, 31013)
	var gush := _alloc(n)
	var spray := _alloc(n)
	var gl := 0.0
	var sl := 0.0
	var a700 := _one_pole(700.0, rate)
	var a2000 := _one_pole(2000.0, rate)
	for i: int in range(pop, n):
		var tt := float(i - pop) / rate
		var x := nz[(i + 43013) & NOISE_MASK]
		var env := smoothstep(0.0, 0.06, tt) * (0.25 + 0.75 * exp(-tt * 2.2)) * smoothstep(duration - 0.16, duration - 0.7, tt)
		gl += (x - gl) * a700
		gush[i] = gl * env
		sl += (x - sl) * a2000
		spray[i] = (x - sl) * smoothstep(0.0, 0.03, tt) * exp(-tt * 3.5)
	_mix(buf, gush, 0.7)
	_mix(buf, spray, 0.4)
	for k: int in 18:
		var at := rng.randf_range(0.7, 1.7)
		_add_burst(buf, nz, rate, int(at * rate), 70.0, rng.randf_range(0.05, 0.16), 3000.0, k * 1013)
	return buf


## The decisive slow motion: a deep falling whoosh over a sub drop.
static func _cue_slowmo(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"slowmo")
	var duration := float(n) / rate
	var buf := _alloc(n)
	var sweep := _alloc(n)
	var sub := _alloc(n)
	var drone := _alloc(n)
	var low := 0.0
	var band := 0.0
	var sub_phase := 0.0
	var d1 := 0.0
	var d2 := 0.0
	for i: int in n:
		var t := float(i) / rate
		var x := nz[(i + 47017) & NOISE_MASK]
		var fade := smoothstep(duration, duration - 0.3, t)
		var f := 2.0 * sin(PI * (90.0 + 1800.0 * exp(-t * 2.2)) / rate)
		low += f * band
		var high := x - low - 0.4 * band
		band += f * high
		sweep[i] = band * smoothstep(0.0, 0.22, t) * exp(-maxf(0.0, t - 0.22) * 1.3) * fade
		sub_phase += TAU * (30.0 + 70.0 * exp(-t * 2.5)) / rate
		sub[i] = sin(sub_phase) * smoothstep(0.0, 0.08, t) * exp(-t * 1.1) * fade
		var fd := 55.0 + 55.0 * exp(-t * 2.0)
		d1 += TAU * fd / rate
		d2 += TAU * fd * 1.0073 / rate
		drone[i] = (sin(d1) + 0.35 * sin(2.0 * d1) + sin(d2) + 0.35 * sin(2.0 * d2)) * sin(PI * clampf(t / duration, 0.0, 1.0))
	_mix(buf, sweep, 0.6)
	_mix(buf, sub, 0.75)
	_mix(buf, drone, 0.18)
	return buf


## Bright brass-section sting: a pickup into an open C major chord, with a timpani hit and splash.
static func _cue_win_sting(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"win_sting")
	var buf := _alloc(n)
	var chord_at := 0.12
	var chord_end := 1.5
	# x: start, y: end, z: frequency, w: level.
	var voices: Array[Vector4] = [Vector4(0.0, 0.1, 392.0 * 0.9971, 0.8), Vector4(0.0, 0.1, 392.0 * 1.0029, 0.8)]
	var notes := [Vector2(261.63, 0.9), Vector2(392.0, 0.8), Vector2(523.25, 0.8), Vector2(659.25, 0.6)]
	for note: Vector2 in notes:
		voices.append(Vector4(chord_at, chord_end, note.x * 0.9971, note.y))
		voices.append(Vector4(chord_at, chord_end, note.x * 1.0029, note.y))
	var phases := PackedFloat64Array()
	phases.resize(voices.size())
	phases.fill(0.0)
	var brass := _alloc(n)
	var low := 0.0
	var band := 0.0
	for i: int in n:
		var t := float(i) / rate
		var vibrato := 1.0 + 0.0035 * sin(TAU * 5.6 * t) * smoothstep(0.45, 0.7, t)
		var sum := 0.0
		for v: int in voices.size():
			var voice := voices[v]
			if t < voice.x or t >= voice.y:
				continue
			var dt := voice.z * vibrato / rate
			var ph := phases[v] + dt
			if ph >= 1.0:
				ph -= 1.0
			phases[v] = ph
			var saw := 2.0 * ph - 1.0
			if ph < dt:
				var q := ph / dt
				saw -= q + q - q * q - 1.0
			elif ph > 1.0 - dt:
				var q := (ph - 1.0) / dt
				saw -= q * q + q + q + 1.0
			var length := voice.y - voice.x
			var local := t - voice.x
			var release := 0.03 if length < 0.2 else 0.35
			sum += saw * smoothstep(0.0, 0.018, local) * smoothstep(length, length - release, local) * voice.w
		var bright: float
		if t < chord_at:
			bright = 0.45 * smoothstep(0.0, 0.03, t)
		else:
			var ct := t - chord_at
			bright = smoothstep(0.0, 0.03, ct) * (0.55 + 0.45 * exp(-ct * 4.5)) * (1.0 - 0.35 * smoothstep(0.9, 1.4, ct))
		var f := 2.0 * sin(PI * (450.0 + 3100.0 * bright) / rate)
		low += f * band
		var high := sum - low - 0.75 * band
		band += f * high
		brass[i] = low
	_mix(buf, brass, 0.75)
	var hit := int(chord_at * rate)
	_add_thump(buf, rate, hit, 98.0, 62.0, 12.0, 6.5, 0.35)
	var splash := _alloc(n)
	var lp := 0.0
	var a5000 := _one_pole(5000.0, rate)
	var env := 1.0
	var k := exp(-3.2 / rate)
	for i: int in range(hit, n):
		var x := nz[(i + 53003) & NOISE_MASK]
		lp += (x - lp) * a5000
		splash[i] = (x - lp) * env * minf(1.0, float(i - hit) / 40.0)
		env *= k
	_mix(buf, splash, 0.12)
	return buf


## Stylised megaphone accent for the referee's shout: "blip-blip" plus two darker slap echoes.
static func _cue_shout_echo() -> PackedFloat32Array:
	var rate := 22050.0
	var n := _count(&"shout_echo")
	var dry := _alloc(n)
	var blips: Array[Vector4] = [Vector4(0.0, 0.085, 740.0, 760.0), Vector4(0.12, 0.13, 990.0, 1045.0)]
	var bf := 2.0 * sin(PI * 1500.0 / rate)
	var a_lp := _one_pole(3500.0, rate)
	for blip: Vector4 in blips:
		var start := int(blip.x * rate)
		var count := int(blip.y * rate)
		var phase := 0.0
		var low := 0.0
		var band := 0.0
		var lp := 0.0
		for j: int in count:
			var t := float(j) / rate
			var dt := lerpf(blip.z, blip.w, t / blip.y) / rate
			phase += dt
			if phase >= 1.0:
				phase -= 1.0
			var square := _blep_saw(phase, dt) - _blep_saw(fposmod(phase + 0.5, 1.0), dt)
			low += bf * band
			var high := square - low - 1.1 * band
			band += bf * high
			var y := clampf((band + square * 0.25) * 2.5, -1.0, 1.0)
			lp += (y - lp) * a_lp
			dry[start + j] = lp * smoothstep(0.0, 0.004, t) * smoothstep(blip.y, blip.y - 0.015, t)
	var buf := dry.duplicate()
	var taps := [Vector3(0.34, 0.42, 2200.0), Vector3(0.355, 0.12, 2000.0), Vector3(0.68, 0.2, 1400.0)]
	for tap: Vector3 in taps:
		var delay := int(tap.x * rate)
		var a := _one_pole(tap.z, rate)
		var e1 := 0.0
		var e2 := 0.0
		for i: int in n - delay:
			e1 += (dry[i] - e1) * a
			e2 += (e1 - e2) * a
			buf[i + delay] += e2 * tap.y
	return buf


# ------------------------------------------------------------------------------ the buzzer duel

## A struck bell: a few inharmonic partials, each with its own decay (the first one is the pitch).
static func _add_bell(buf: PackedFloat32Array, rate: float, start: float, freq: float, length: float, amp: float) -> void:
	var partials: Array[Vector3] = [Vector3(1.0, 1.0, 1.0), Vector3(2.0, 0.42, 1.6), Vector3(3.01, 0.2, 2.4), Vector3(4.17, 0.08, 3.4)]
	var first := int(start * rate)
	var count := mini(int(length * rate), buf.size() - first)
	for j: int in count:
		var t := float(j) / rate
		var attack := smoothstep(0.0, 0.004, t)
		var tail := smoothstep(length, length - 0.06, t)
		var sum := 0.0
		for partial: Vector3 in partials:
			sum += sin(TAU * freq * partial.x * t) * partial.y * exp(-t * partial.z * 3.2 / length)
		buf[first + j] += sum * amp * attack * tail


## 早押しの音：明るい2音の上行（ピコーン）。
static func _cue_buzz() -> PackedFloat32Array:
	var rate := 32000.0
	var buf := _alloc(_count(&"buzz"))
	_add_bell(buf, rate, 0.0, 1567.98, 0.16, 0.7)
	_add_bell(buf, rate, 0.07, 2093.0, 0.66, 0.9)
	return buf


## 正解：ピンポン・ピンポーン（高・低を2回、最後を長く）。
static func _cue_correct() -> PackedFloat32Array:
	var rate := 32000.0
	var buf := _alloc(_count(&"correct"))
	_add_bell(buf, rate, 0.0, 1318.51, 0.2, 0.85)
	_add_bell(buf, rate, 0.17, 1046.5, 0.25, 0.85)
	_add_bell(buf, rate, 0.36, 1318.51, 0.2, 0.85)
	_add_bell(buf, rate, 0.53, 1046.5, 0.72, 0.95)
	return buf


## 不正解：ブッブー（低い角ばった2回のブザー、2回目を長く）。
static func _cue_wrong() -> PackedFloat32Array:
	var rate := 22050.0
	var buf := _alloc(_count(&"wrong"))
	var a_lp := _one_pole(2400.0, rate)
	for honk: Vector2 in [Vector2(0.0, 0.16), Vector2(0.24, 0.66)]:
		var first := int(honk.x * rate)
		var count := mini(int(honk.y * rate), buf.size() - first)
		var phase := 0.0
		var lp := 0.0
		for j: int in count:
			var t := float(j) / rate
			var env := smoothstep(0.0, 0.01, t) * smoothstep(honk.y, honk.y - 0.04, t)
			var dt := 148.0 / rate
			phase = fmod(phase + dt, 1.0)
			var square := 1.0 if phase < 0.5 else -1.0
			var y := square * 0.6 + (2.0 * phase - 1.0) * 0.4
			lp += (y - lp) * a_lp
			buf[first + j] = lp * env
	return buf


## 残り時間の刻み：短い木のクリック。
static func _cue_tick() -> PackedFloat32Array:
	var rate := 22050.0
	var buf := _alloc(_count(&"tick"))
	_add_bell(buf, rate, 0.0, 1900.0, 0.1, 0.6)
	_add_bell(buf, rate, 0.0, 3150.0, 0.05, 0.3)
	return buf


## 時間切れ：低い銅鑼（ボーン）。
static func _cue_time_up() -> PackedFloat32Array:
	var rate := 22050.0
	var buf := _alloc(_count(&"time_up"))
	_add_bell(buf, rate, 0.0, 146.83, 1.75, 0.9)
	_add_bell(buf, rate, 0.0, 220.0, 1.2, 0.35)
	return buf


static func _blep_saw(phase: float, dt: float) -> float:
	var saw := 2.0 * phase - 1.0
	if phase < dt:
		var q := phase / dt
		saw -= q + q - q * q - 1.0
	elif phase > 1.0 - dt:
		var q := (phase - 1.0) / dt
		saw -= q * q + q + q + 1.0
	return saw


# ------------------------------------------------------------------------------ loops

## Elevator motor: mains hum, gear whine and rumble, with wire creaks on the loop circle.
static func _loop_motor(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 11025.0
	var n := _count(LOOP_MOTOR)
	var overhang := int(0.25 * rate)
	var rumble := _alloc(n + overhang)
	var brush := _alloc(n + overhang)
	var r1 := 0.0
	var r2 := 0.0
	var a140 := _one_pole(140.0, rate)
	var bl := 0.0
	var bb := 0.0
	var bf := 2.0 * sin(PI * 1100.0 / rate)
	for i: int in n + overhang:
		var v := nz[(i + 33013) & NOISE_MASK]
		r1 += (v - r1) * a140
		r2 += (r1 - r2) * a140
		rumble[i] = r2
		bl += bf * bb
		var bh := v - bl - 1.6 * bb
		bb += bf * bh
		brush[i] = bb
	var buf := _alloc(n)
	_mix(buf, _fold_loop(rumble, n), 0.45)
	_mix(buf, _fold_loop(brush, n), 0.05)
	# Every tone completes whole cycles in the 2 s loop, so it needs no crossfade.
	var tonal := _alloc(n)
	for i: int in n:
		var t := float(i) / rate
		var hum := 0.25 * sin(TAU * 50.0 * t) + 0.55 * sin(TAU * 100.0 * t) + 0.2 * sin(TAU * 150.0 * t) \
			+ 0.15 * sin(TAU * 200.0 * t) + 0.07 * sin(TAU * 300.0 * t)
		var gear := sin(TAU * 287.5 * t) * (1.0 + 0.35 * sin(TAU * 1.5 * t)) * 0.14 + sin(TAU * 862.5 * t) * 0.05
		tonal[i] = hum * (1.0 + 0.15 * sin(TAU * 12.5 * t)) + gear
	_mix(buf, tonal, 0.5)
	_add_creak_circular(buf, rate, 0.28, 0.34, 520.0, 22.0, 34.0, 0.2, nz, 1)
	_add_creak_circular(buf, rate, 1.08, 0.26, 610.0, 30.0, 24.0, 0.13, nz, 2)
	_add_creak_circular(buf, rate, 1.72, 0.38, 470.0, 18.0, 30.0, 0.17, nz, 3)
	return buf


## Shaft: low concrete drone with faint air movement and drips echoing between the walls.
static func _loop_shaft(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 11025.0
	var n := _count(LOOP_SHAFT)
	var overhang := int(0.5 * rate)
	var drone := _alloc(n + overhang)
	var air := _alloc(n + overhang)
	var d1 := 0.0
	var d2 := 0.0
	var a85 := _one_pole(85.0, rate)
	var al := 0.0
	var ab := 0.0
	var af := 2.0 * sin(PI * 600.0 / rate)
	for i: int in n + overhang:
		var t := float(i) / rate
		var v := nz[(i + 41011) & NOISE_MASK]
		d1 += (v - d1) * a85
		d2 += (d1 - d2) * a85
		drone[i] = d2 * (1.0 + 0.2 * sin(TAU * t / 3.0))
		al += af * ab
		var ah := v - al - ab
		ab += af * ah
		air[i] = ab * (0.7 + 0.3 * sin(TAU * t / 2.0 + 1.0))
	var buf := _alloc(n)
	_mix(buf, _fold_loop(drone, n), 0.55)
	_mix(buf, _fold_loop(air, n), 0.06)
	var tonal := _alloc(n)
	for i: int in n:
		var t := float(i) / rate
		tonal[i] = 0.12 * sin(TAU * 31.5 * t) * (1.0 + 0.3 * sin(TAU * 0.5 * t)) \
			+ 0.08 * sin(TAU * 47.0 * t) * (1.0 + 0.3 * sin(TAU * t / 3.0)) + 0.05 * sin(TAU * 63.5 * t)
	_mix(buf, tonal, 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5AF7
	var taps := [Vector2(0.085, 0.5), Vector2(0.19, 0.28), Vector2(0.33, 0.14)]
	for k: int in 8:
		var at := int((float(k) + rng.randf_range(0.1, 0.9)) * 6.0 / 8.0 * rate) % n
		var f0 := rng.randf_range(1000.0, 2600.0)
		var amp := rng.randf_range(0.08, 0.3)
		_add_drip(buf, rate, at, f0, amp, true)
		for tap: Vector2 in taps:
			_add_drip(buf, rate, (at + int(tap.x * rate)) % n, f0 * 0.985, amp * tap.y, true)
	return buf


## Cistern hall: huge room tone, sub rumble, distant trickle and long-echo drips.
static func _loop_hall(nz: PackedFloat32Array) -> PackedFloat32Array:
	var rate := 11025.0
	var n := _count(LOOP_HALL)
	var overhang := int(0.6 * rate)
	var room := _alloc(n + overhang)
	var sub := _alloc(n + overhang)
	var water := _alloc(n + overhang)
	var r1 := 0.0
	var r2 := 0.0
	var s1 := 0.0
	var s2 := 0.0
	var a260 := _one_pole(260.0, rate)
	var a55 := _one_pole(55.0, rate)
	var wl := 0.0
	var wb := 0.0
	var wf := 2.0 * sin(PI * 1500.0 / rate)
	for i: int in n + overhang:
		var t := float(i) / rate
		var v := nz[(i + 51001) & NOISE_MASK]
		var u := nz[(i * 5 + 77) & NOISE_MASK]
		r1 += (v - r1) * a260
		r2 += (r1 - r2) * a260
		room[i] = r2 * (1.0 + 0.15 * sin(TAU * 0.125 * t))
		s1 += (u - s1) * a55
		s2 += (s1 - s2) * a55
		sub[i] = s2
		wl += wf * wb
		var wh := v - wl - 0.8 * wb
		wb += wf * wh
		water[i] = wb * (0.6 + 0.4 * sin(TAU * 0.375 * t))
	var buf := _alloc(n)
	_mix(buf, _fold_loop(room, n), 0.42)
	_mix(buf, _fold_loop(sub, n), 0.5)
	_mix(buf, _fold_loop(water, n), 0.05)
	var tonal := _alloc(n)
	for i: int in n:
		var t := float(i) / rate
		tonal[i] = 0.06 * sin(TAU * 41.25 * t) + 0.03 * sin(TAU * 100.0 * t) + 0.015 * sin(TAU * 150.0 * t)
	_mix(buf, tonal, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4A11
	var taps := [Vector2(0.12, 0.5), Vector2(0.27, 0.32), Vector2(0.45, 0.2), Vector2(0.7, 0.1)]
	for k: int in 11:
		var at := int((float(k) + rng.randf_range(0.1, 0.9)) * 8.0 / 11.0 * rate) % n
		var f0 := rng.randf_range(800.0, 2400.0)
		var amp := rng.randf_range(0.05, 0.2)
		_add_drip(buf, rate, at, f0, amp, true)
		for tap: Vector2 in taps:
			_add_drip(buf, rate, (at + int(tap.x * rate)) % n, f0 * 0.98, amp * tap.y, true)
	return buf


# ------------------------------------------------------------------------------ node runtime

func _process(_delta: float) -> void:
	if not _is_setup:
		return
	var now := Time.get_ticks_usec()
	# Real time, so fades keep their length during the decisive slow motion.
	var dt := clampf(float(now - _last_tick_usec) / 1000000.0, 0.0, 0.1)
	_last_tick_usec = now
	_reap_generation()
	_update_motor(dt)
	_update_ambience(dt)
	_update_reverb(dt)
	_update_underwater(dt)


func _exit_tree() -> void:
	if _is_setup:
		_reap_generation()
		_apply_reverb_now(DRY_REVERB)
		_apply_lowpass_now(OPEN_CUTOFF_HZ, false)


func _one_shot_stream(cue: StringName) -> AudioStreamWAV:
	if not CUES.has(cue):
		_unknown_cues += 1
		return null
	if not _is_setup:
		setup()
	var stream := get_stream(cue)
	if stream == null:
		# The worker has not reached this cue yet: build it here rather than stay silent.
		_build(cue)
		_cache_mutex.lock()
		_sync_builds += 1
		_cache_mutex.unlock()
		stream = get_stream(cue)
	if stream != null:
		_last_cue = cue
		_cues_played += 1
	return stream


func _cue_pitch(cue: StringName, pitch: float) -> float:
	var spread := float(PITCH_JITTER.get(cue, 0.0))
	if spread > 0.0:
		pitch *= 1.0 + _rng.randf_range(-spread, spread)
	return clampf(pitch, 0.05, 4.0)


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = BUS_NAME
	add_child(player)
	return player


func _next_player() -> AudioStreamPlayer:
	var count := _players.size()
	for step in range(count):
		var index := (_player_cursor + step) % count
		if not _players[index].playing:
			_player_cursor = (index + 1) % count
			return _players[index]
	var stolen := _players[_player_cursor]
	_player_cursor = (_player_cursor + 1) % count
	return stolen


func _next_player_3d() -> AudioStreamPlayer3D:
	var count := _players_3d.size()
	for step in range(count):
		var index := (_player_3d_cursor + step) % count
		if not _players_3d[index].playing:
			_player_3d_cursor = (index + 1) % count
			return _players_3d[index]
	var stolen := _players_3d[_player_3d_cursor]
	_player_3d_cursor = (_player_3d_cursor + 1) % count
	return stolen


static func _approach(current: float, target: float, dt: float, tau: float) -> float:
	return lerpf(current, target, 1.0 - exp(-dt / tau))


static func _gain_db(gain: float) -> float:
	return linear_to_db(gain) if gain > 0.0001 else -80.0


func _update_motor(dt: float) -> void:
	var ratio := clampf(absf(_motor_speed) / MOTOR_MAX_SPEED, 0.0, 1.0)
	var target_gain := lerpf(MOTOR_IDLE_GAIN, 1.0, ratio) if _motor_active else 0.0
	_motor_pitch = _approach(_motor_pitch, lerpf(MOTOR_PITCH_RANGE.x, MOTOR_PITCH_RANGE.y, ratio), dt, MOTOR_PITCH_TAU)
	if _motor_active and not _motor_player.playing:
		var stream := get_stream(LOOP_MOTOR)
		if stream == null:
			return
		_motor_player.stream = stream
		_motor_player.volume_db = _gain_db(_motor_gain)
		_motor_player.play(_rng.randf() * float(LOOPS[LOOP_MOTOR]["seconds"]))
	_motor_gain = _approach(_motor_gain, target_gain, dt, MOTOR_GAIN_TAU)
	if not _motor_player.playing:
		_motor_gain = 0.0
		return
	if not _motor_active and _motor_gain < 0.003:
		_motor_player.stop()
		_motor_gain = 0.0
		return
	_motor_player.volume_db = _gain_db(_motor_gain)
	_motor_player.pitch_scale = _motor_pitch


func _update_ambience(dt: float) -> void:
	var step := dt / AMBIENCE_FADE_SECONDS
	for slot in range(2):
		var player := _ambience_players[slot]
		var kind := _ambience_slot_kind[slot]
		var wanted := slot == _ambience_front and kind == _ambience_kind and kind != AMBIENCE_NONE
		if wanted and not player.playing:
			var stream := get_stream(AMBIENCE_LOOPS[kind])
			if stream == null:
				continue
			player.stream = stream
			player.volume_db = -80.0
			player.play(_rng.randf() * float(LOOPS[AMBIENCE_LOOPS[kind]]["seconds"]))
		_ambience_gain[slot] = move_toward(_ambience_gain[slot], 1.0 if wanted else 0.0, step)
		if not wanted and _ambience_gain[slot] <= 0.0:
			if player.playing:
				player.stop()
			_ambience_slot_kind[slot] = AMBIENCE_NONE
			continue
		# Equal-power crossfade curve.
		player.volume_db = _gain_db(sin(_ambience_gain[slot] * PI * 0.5))


func _update_reverb(dt: float) -> void:
	var changed := false
	for key: String in REVERB_KEYS:
		var current := float(_reverb_current[key])
		var target := float(_reverb_target[key])
		if is_equal_approx(current, target):
			continue
		var value := _approach(current, target, dt, _reverb_tau)
		if absf(value - target) < 0.0005 * maxf(1.0, absf(target)):
			value = target
		_reverb_current[key] = value
		changed = true
	if changed:
		_push_reverb()


func _update_underwater(dt: float) -> void:
	var target := UNDERWATER_CUTOFF_HZ if _underwater else OPEN_CUTOFF_HZ
	if is_equal_approx(_lowpass_cutoff, target) and _lowpass_enabled == _underwater:
		return
	var log_cutoff := _approach(log(_lowpass_cutoff), log(target), dt, UNDERWATER_TAU)
	_lowpass_cutoff = exp(log_cutoff)
	if absf(_lowpass_cutoff - target) < target * 0.01:
		_lowpass_cutoff = target
	_apply_lowpass_now(_lowpass_cutoff, _underwater or _lowpass_cutoff < OPEN_CUTOFF_HZ * 0.95)


func _apply_reverb_now(params: Dictionary) -> void:
	_reverb_current = params.duplicate()
	_reverb_target = params.duplicate()
	_push_reverb()


func _push_reverb() -> void:
	if _reverb == null:
		return
	for key: String in REVERB_KEYS:
		_reverb.set(key, float(_reverb_current[key]))
	var enabled := float(_reverb_current["wet"]) > 0.001 or float(_reverb_target["wet"]) > 0.001
	if enabled != _reverb_enabled:
		_reverb_enabled = enabled
		_set_effect_enabled(_reverb_slot, enabled)


func _apply_lowpass_now(cutoff: float, enabled: bool) -> void:
	_lowpass_cutoff = cutoff
	if _lowpass == null:
		return
	_lowpass.cutoff_hz = cutoff
	if enabled != _lowpass_enabled:
		_lowpass_enabled = enabled
		_set_effect_enabled(_lowpass_slot, enabled)


func _set_effect_enabled(slot: int, enabled: bool) -> void:
	var bus := AudioServer.get_bus_index(BUS_NAME)
	if bus >= 0 and slot >= 0 and slot < AudioServer.get_bus_effect_count(bus):
		AudioServer.set_bus_effect_enabled(bus, slot, enabled)


## Creates (or adopts) the SuddenDeath bus: reverb, underwater low-pass, limiter; sends to SFX.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(SEND_BUS) < 0:
		var sfx := AudioServer.bus_count
		AudioServer.add_bus(sfx)
		AudioServer.set_bus_name(sfx, SEND_BUS)
	_bus_index = AudioServer.get_bus_index(BUS_NAME)
	if _bus_index < 0:
		_bus_index = AudioServer.bus_count
		AudioServer.add_bus(_bus_index)
		AudioServer.set_bus_name(_bus_index, BUS_NAME)
	AudioServer.set_bus_send(_bus_index, SEND_BUS)
	var limiter_found := false
	for slot in range(AudioServer.get_bus_effect_count(_bus_index)):
		var effect := AudioServer.get_bus_effect(_bus_index, slot)
		if effect is AudioEffectReverb and _reverb == null:
			_reverb = effect
			_reverb_slot = slot
		elif effect is AudioEffectLowPassFilter and _lowpass == null:
			_lowpass = effect
			_lowpass_slot = slot
		elif effect is AudioEffectHardLimiter:
			limiter_found = true
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb_slot = AudioServer.get_bus_effect_count(_bus_index)
		AudioServer.add_bus_effect(_bus_index, _reverb, _reverb_slot)
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.resonance = 0.6
		_lowpass_slot = AudioServer.get_bus_effect_count(_bus_index)
		AudioServer.add_bus_effect(_bus_index, _lowpass, _lowpass_slot)
	if not limiter_found:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(_bus_index, limiter)
	# Start dry and unfiltered: both effects bypassed until needed.
	AudioServer.set_bus_effect_enabled(_bus_index, _reverb_slot, false)
	AudioServer.set_bus_effect_enabled(_bus_index, _lowpass_slot, false)
	_reverb_enabled = false
	_lowpass_enabled = false
