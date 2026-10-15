extends Node

## Sound stays local to each aircraft and its camera, including menu SubViewports.
## Ordinary players + a private spatial bus avoid SubViewport listener dependencies.
signal cue_played(cue: StringName)

const ROOT := "res://assets/audio/sfx/helicopter/"
const BEDS := {&"rotor": "rotor_loop", &"turbine": "turbine_loop", &"jet": "jet_loop", &"winch": "winch_loop"}
const DETAILS := {&"hatch_open": -7.0, &"hatch_close": -11.0, &"latch": -3.0, &"belt_click": -1.0, &"rope_release": -6.0, &"grip": -4.0, &"jet_ignite": -4.0}
const SILENCE_DB := -80.0
## While the owner is just waiting (the online matching search), the whole aircraft sits this far under.
const WAITING_DUCK_DB := -10.0

var enabled := false
## Set by the owner while the aircraft only waits in the air (online matching search); the level
## eases to WAITING_DUCK_DB and back instead of jumping.
var waiting := false
var mix_gain := 0.0
var _waiting_scale := 1.0
var _carrier: Node3D
var _beds: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _mechanisms: Dictionary = {}
var _last_cue_msec: Dictionary = {}
var _voice_index := 0
var _bus := ""
var _panner: AudioEffectPanner
var _filter: AudioEffectLowPassFilter
var _spool := 0.0
var _speed := 1.0
var _charge := 0.0
var _jet := false
var _previous_jet := false
var _winching := false
var _winch_activity := 0.0
var _last_distance := -1.0
var _doppler := 1.0
var _start_phase := 0.0


func setup(carrier: Node3D) -> void:
	_carrier = carrier
	_start_phase = fmod(float(carrier.get_instance_id()) * 0.61803398875, 1.0)
	_bus = "Helicopter_%d" % get_instance_id()
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, _bus)
	AudioServer.set_bus_send(index, "SFX")
	_panner = AudioEffectPanner.new()
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 9000.0
	AudioServer.add_bus_effect(index, _panner)
	AudioServer.add_bus_effect(index, _filter)
	AudioServer.set_bus_volume_db(index, SILENCE_DB)
	for cue: StringName in BEDS:
		var stream := load(ROOT + str(BEDS[cue]) + ".ogg") as AudioStreamOggVorbis
		if stream == null:
			continue
		stream = stream.duplicate() as AudioStreamOggVorbis
		stream.loop = true
		var player := _make_player(str(cue))
		player.stream = stream
		_beds[cue] = player
	for cue: StringName in DETAILS:
		_streams[cue] = load(ROOT + str(cue) + ".ogg") as AudioStream
	for i in range(4):
		_voices.append(_make_player("Detail%d" % i))
	set_process(false)


func _make_player(label: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label
	player.bus = _bus
	player.volume_db = SILENCE_DB
	add_child(player)
	return player


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if value:
		_waiting_scale = 1.0
		add_to_group("helicopter_sound")
		_previous_jet = _jet
		_last_distance = -1.0
		set_process(true)
	else:
		remove_from_group("helicopter_sound")
		stop()
		set_process(false)


func stop() -> void:
	mix_gain = 0.0
	_last_distance = -1.0
	_winching = false
	_winch_activity = 0.0
	for player: AudioStreamPlayer in _beds.values():
		player.stop()
	for player: AudioStreamPlayer in _voices:
		player.stop()
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, SILENCE_DB)


func set_engine(spool: float, speed: float, charge: float, jet: bool) -> void:
	_spool = clampf(spool, 0.0, 1.0)
	_speed = speed
	_charge = charge
	_jet = jet
	if not enabled:
		_previous_jet = jet


## Called with the actual animated amount, so skipped frames do not lose an event.
## Disabled/prewarm changes establish a baseline without making sound.
func set_mechanism(key: StringName, amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	var previous := float(_mechanisms.get(key, 0.0))
	_mechanisms[key] = amount
	if not _audible():
		return
	if key == &"winch":
		_winching = amount > previous + 0.00001 and amount < 0.999
		return
	if key == &"rope":
		if previous < 0.02 and amount >= 0.02:
			play_detail(&"rope_release")
	elif str(key).begins_with("belt"):
		if previous < 0.85 and amount >= 0.85:
			play_detail(&"belt_click")
	else:
		if previous <= 0.02 and amount > 0.02:
			play_detail(&"hatch_open")
		if previous >= 0.98 and amount < 0.98:
			play_detail(&"hatch_close")
		if previous > 0.015 and amount <= 0.015:
			play_detail(&"latch")


func play_detail(cue: StringName) -> void:
	if not _audible() or not _streams.has(cue):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_cue_msec.get(cue, -100000)) < 100:
		return
	_last_cue_msec[cue] = now
	var player := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	player.stream = _streams[cue]
	player.volume_db = float(DETAILS[cue])
	player.pitch_scale = 0.98 + _start_phase * 0.04
	player.play()
	cue_played.emit(cue)


func _audible() -> bool:
	return enabled and not AudioManager.menu_sfx_muted and is_instance_valid(_carrier) and _carrier.is_visible_in_tree() and not get_tree().paused and not SceneTransition.is_fully_covered()


func _process(delta: float) -> void:
	if not _audible():
		stop()
		_previous_jet = _jet
		return
	var camera := _carrier.get_viewport().get_camera_3d()
	if camera == null:
		stop()
		return
	var offset := _carrier.global_position - camera.global_position
	var distance := offset.length()
	var target_gain := pow(36.0 / maxf(36.0, distance), 1.4)
	target_gain *= 1.0 - smoothstep(100.0, 165.0, distance)
	target_gain *= pow(1.0 - SceneTransition.get_cover_factor(), 1.5)
	# Equal-power compensation only for other audible aircraft, including P1/P2 arrivals.
	var count := 0
	for rig in get_tree().get_nodes_in_group("helicopter_sound"):
		if rig._audible() and rig._carrier.global_position.distance_to(camera.global_position) < 100.0:
			count += 1
	target_gain /= sqrt(float(maxi(count, 1)))
	_waiting_scale = lerpf(_waiting_scale, db_to_linear(WAITING_DUCK_DB) if waiting else 1.0, 1.0 - exp(-delta * 4.0))
	target_gain *= _waiting_scale
	mix_gain = lerpf(mix_gain, target_gain, 1.0 - exp(-delta * 10.0))
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(mix_gain, 0.0001)))
	var pan := clampf(offset.dot(camera.global_basis.x) / maxf(distance * 0.60, 1.0), -0.68, 0.68)
	_panner.pan = lerpf(_panner.pan, pan, 1.0 - exp(-delta * 8.0))
	_filter.cutoff_hz = lerpf(9000.0, 2400.0, smoothstep(45.0, 140.0, distance))
	var radial_speed := 0.0 if _last_distance < 0.0 else clampf((distance - _last_distance) / maxf(delta, 0.001), -65.0, 65.0)
	_last_distance = distance
	_doppler = lerpf(_doppler, clampf(343.0 / (343.0 + radial_speed), 0.88, 1.12), 1.0 - exp(-delta * 5.0))
	if _jet and not _previous_jet:
		play_detail(&"jet_ignite")
	_previous_jet = _jet
	var rotor_pitch := lerpf(0.55, 1.0, smoothstep(0.0, 1.0, _spool))
	rotor_pitch *= (1.0 + maxf(0.0, _speed - 1.0) * 0.12) * _doppler
	_bed(&"rotor", pow(_spool, 1.4), -7.0, rotor_pitch, delta)
	_bed(&"turbine", _charge if not _jet else 0.0, -11.0, lerpf(0.65, 1.35, _charge) * _doppler, delta)
	_bed(&"jet", 1.0 if _jet else 0.0, -8.0, _doppler, delta)
	_winch_activity = move_toward(_winch_activity, 1.0 if _winching else 0.0, delta * 12.0)
	_bed(&"winch", _winch_activity, -12.0, 1.0, delta)
	_winching = false


func _bed(cue: StringName, amount: float, level: float, pitch: float, delta: float) -> void:
	var player := _beds.get(cue) as AudioStreamPlayer
	if player == null:
		return
	var gain := db_to_linear(player.volume_db)
	gain = lerpf(gain, db_to_linear(level) * amount, 1.0 - exp(-delta * 14.0))
	player.volume_db = linear_to_db(maxf(gain, 0.0001))
	player.pitch_scale = lerpf(player.pitch_scale, pitch, 1.0 - exp(-delta * 10.0))
	if gain > 0.00015 and mix_gain > 0.00015:
		if not player.playing:
			player.play(_start_phase * player.stream.get_length())
	elif player.playing:
		player.stop()


func _exit_tree() -> void:
	stop()
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.remove_bus(index)
