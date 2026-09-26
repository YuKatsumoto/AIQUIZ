extends Node

const BGM_PATH := "res://assets/audio/bgm/head_in_the_sand.ogg"
const SETTINGS_PATH := "user://audio_settings.cfg"
const MUSIC_CONTEXT_MENU: StringName = &"menu"
const MUSIC_CONTEXT_GAMEPLAY: StringName = &"gameplay"
const MUSIC_CONTEXT_PAUSED: StringName = &"paused"
const MUSIC_CONTEXT_RESULT: StringName = &"result"

const CONTEXT_VOLUME_DB := {
	MUSIC_CONTEXT_MENU: -4.0,
	MUSIC_CONTEXT_GAMEPLAY: 0.0,
	MUSIC_CONTEXT_PAUSED: -10.0,
	MUSIC_CONTEXT_RESULT: -4.0,
}

## Goal stand crowd (assets/goal_stand): procedural beds mixed with Higgsfield voices.
const CROWD_CUE_PATHS := {
	&"applause": "res://assets/audio/sfx/goal_stand/crowd_applause.ogg",
	&"cheer": "res://assets/audio/sfx/goal_stand/crowd_cheer.ogg",
	&"boo": "res://assets/audio/sfx/goal_stand/crowd_boo.ogg",
	&"voice_angry": "res://assets/audio/sfx/goal_stand/voice_angry.ogg",
	&"voice_draw": "res://assets/audio/sfx/goal_stand/voice_draw.ogg",
	&"voice_hype": "res://assets/audio/sfx/goal_stand/voice_hype.ogg",
	&"egg_splat": "res://assets/audio/sfx/goal_stand/egg_splat.ogg",
	&"egg_throw": "res://assets/audio/sfx/goal_stand/egg_throw.ogg",
}

## オーディオ管理 (Autoload)
## Python版 synth.py の generate_correct_sound / generate_explosion_sound に相当
## Godotでは AudioStreamPlayer + AudioStreamGenerator で合成音を生成

var correct_player: AudioStreamPlayer
var explosion_player: AudioStreamPlayer
var result_roll_player: AudioStreamPlayer
var result_lock_player: AudioStreamPlayer
var result_explosion_player: AudioStreamPlayer
var result_victory_player: AudioStreamPlayer
var result_accent_player: AudioStreamPlayer
var result_hero_impact: AudioStream
var result_hero_swish: AudioStream
var result_verdict_impact: AudioStream
var result_cue_players: Array[AudioStreamPlayer] = []
var result_rain_player: AudioStreamPlayer
var crowd_players: Array[AudioStreamPlayer] = []
var _crowd_streams: Dictionary = {}
var _crowd_index: int = 0
var _result_cues: Dictionary = {}
var _result_cue_index: int = 0
var tutorial_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer
var shark_rush_stream: AudioStreamWAV
var shark_impact_stream: AudioStreamWAV
var tutorial_step_stream: AudioStreamWAV
var tutorial_task_stream: AudioStreamWAV
var tutorial_complete_stream: AudioStreamWAV
var tutorial_settle_stream: AudioStreamWAV

var sfx_volume: float = 1.0
var bgm_volume: float = 0.5
var _music_context: StringName = MUSIC_CONTEXT_MENU
var _context_before_pause: StringName = MUSIC_CONTEXT_MENU
var _context_tween: Tween = null
var _tutorial_ducked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("BGM")
	_ensure_bus("SFX")
	_load_audio_settings()

	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGMPlayer"
	bgm_player.bus = "BGM"
	var bgm_stream: AudioStream = load(BGM_PATH) as AudioStream
	if bgm_stream is AudioStreamOggVorbis:
		(bgm_stream as AudioStreamOggVorbis).loop = true
	bgm_player.stream = bgm_stream
	bgm_player.volume_db = CONTEXT_VOLUME_DB[MUSIC_CONTEXT_MENU]
	add_child(bgm_player)

	correct_player = AudioStreamPlayer.new()
	correct_player.name = "CorrectSFX"
	correct_player.bus = "SFX"
	add_child(correct_player)

	explosion_player = AudioStreamPlayer.new()
	explosion_player.name = "ExplosionSFX"
	explosion_player.bus = "SFX"
	add_child(explosion_player)
	result_roll_player = _create_sfx_player("ResultScoreRollSFX")
	result_lock_player = _create_sfx_player("ResultScoreLockSFX")
	result_explosion_player = _create_sfx_player("ResultCeremonyExplosionSFX")
	result_victory_player = _create_sfx_player("ResultVictorySFX")
	result_accent_player = _create_sfx_player("ResultToonAccentSFX")
	result_accent_player.volume_db = -5.0
	for index in range(4):
		result_cue_players.append(_create_sfx_player("ResultFinaleCue%d" % index))
	result_rain_player = _create_sfx_player("ResultFinaleRain")
	result_rain_player.volume_db = -15.0
	for index in range(5):
		crowd_players.append(_create_sfx_player("GoalStandCrowd%d" % index))
	result_hero_impact = load("res://assets/audio/sfx/result_toon/hero_impact.ogg")
	result_hero_swish = load("res://assets/audio/sfx/result_toon/hero_swish.ogg")
	result_verdict_impact = load("res://assets/audio/sfx/result_toon/verdict_impact.ogg")
	tutorial_player = AudioStreamPlayer.new()
	tutorial_player.name = "TutorialSFX"
	tutorial_player.bus = "SFX"
	add_child(tutorial_player)

	# Generate audio samples
	_generate_correct_sound()
	_generate_explosion_sound()
	_generate_result_ceremony_sounds()
	_generate_finale_sounds()
	result_lock_player.stream = load("res://assets/audio/sfx/result_toon/score_confirm.ogg")
	result_lock_player.volume_db = -6.0
	_generate_shark_rush_sound()
	_generate_shark_impact_sound()
	_generate_tutorial_sounds()

	# Connect to game state
	var game_state: QuizGameState = QuizManager.game_state
	game_state.sfx_volume = sfx_volume
	game_state.bgm_volume = bgm_volume
	game_state.correct_answer.connect(play_correct)
	game_state.wrong_answer.connect(func(_msg: String): play_explosion())

	set_sfx_volume(sfx_volume, false)
	set_bgm_volume(bgm_volume, false)
	if bgm_player.stream != null:
		bgm_player.play()

func play_correct() -> void:
	correct_player.play()

func play_explosion() -> void:
	explosion_player.play()


func play_result_roll(rate: float = 1.0) -> void:
	if result_roll_player != null:
		result_roll_player.pitch_scale = rate
		result_roll_player.play()


func play_result_lock() -> void:
	if result_roll_player != null:
		result_roll_player.stop()
	if result_lock_player != null:
		result_lock_player.play()


func play_result_explosion(is_draw: bool = false) -> void:
	if result_explosion_player == null:
		return
	result_explosion_player.volume_db = 2.5 if is_draw else 0.0
	result_explosion_player.play()


func play_result_victory(is_draw: bool = false) -> void:
	if result_victory_player != null:
		result_victory_player.pitch_scale = 0.84 if is_draw else 1.0
		result_victory_player.play()


func stop_result_sounds() -> void:
	var players: Array = [result_roll_player, result_lock_player, result_explosion_player, result_victory_player,
		result_accent_player, result_rain_player]
	players.append_array(result_cue_players)
	players.append_array(crowd_players)
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.pitch_scale = 1.0


## Score Tower Finale one-shots: pad_pop, climb, confetti, crown, sad, cymbal.
func play_result_cue(cue: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if result_cue_players.is_empty() or not _result_cues.has(cue):
		return
	var player := result_cue_players[_result_cue_index % result_cue_players.size()]
	_result_cue_index += 1
	player.stream = _result_cues[cue]
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


## Goal stand crowd one-shots (cheer, boo, applause, voices, egg throw/splat).
## Streams load on first use so the menu never pays for them.
func play_crowd_cue(cue: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if crowd_players.is_empty():
		return
	if not _crowd_streams.has(cue):
		var path: String = CROWD_CUE_PATHS.get(cue, "")
		if path.is_empty() or not ResourceLoader.exists(path):
			return
		_crowd_streams[cue] = load(path)
	var player := crowd_players[_crowd_index % crowd_players.size()]
	_crowd_index += 1
	player.stream = _crowd_streams[cue]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func start_result_rain() -> void:
	if is_instance_valid(result_rain_player) and not result_rain_player.playing:
		result_rain_player.play()


func play_result_accent(cue: StringName) -> void:
	result_accent_player.stream = result_hero_impact if cue == &"freeze" else (result_verdict_impact if cue == &"verdict" else result_hero_swish)
	result_accent_player.play()


func play_tutorial_step() -> void:
	_play_tutorial_stream(tutorial_step_stream)


func play_tutorial_task() -> void:
	_play_tutorial_stream(tutorial_task_stream)


func play_tutorial_complete() -> void:
	_play_tutorial_stream(tutorial_complete_stream)


func play_tutorial_settle() -> void:
	_play_tutorial_stream(tutorial_settle_stream)


func set_tutorial_ducked(ducked: bool, fade_seconds: float = 0.22) -> void:
	_tutorial_ducked = ducked
	_apply_music_target(fade_seconds)

func set_volume(vol: float) -> void:
	set_sfx_volume(vol)

func set_sfx_volume(vol: float, save_setting: bool = true) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear_volume("SFX", sfx_volume)
	if save_setting:
		_save_audio_settings()

func set_bgm_volume(vol: float, save_setting: bool = true) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear_volume("BGM", bgm_volume)
	if save_setting:
		_save_audio_settings()

func set_music_context(context: StringName, fade_seconds: float = 0.4) -> void:
	if context != MUSIC_CONTEXT_PAUSED:
		_context_before_pause = context
	_music_context = context
	if not is_instance_valid(bgm_player):
		return
	_apply_music_target(fade_seconds)


func _apply_music_target(fade_seconds: float) -> void:
	if not is_instance_valid(bgm_player):
		return
	var target_db: float = float(CONTEXT_VOLUME_DB.get(_music_context, 0.0))
	if _tutorial_ducked:
		target_db -= 6.0
	if is_instance_valid(_context_tween):
		_context_tween.kill()
	if fade_seconds <= 0.0:
		bgm_player.volume_db = target_db
		return
	_context_tween = create_tween()
	_context_tween.set_trans(Tween.TRANS_SINE)
	_context_tween.set_ease(Tween.EASE_IN_OUT)
	_context_tween.tween_property(bgm_player, "volume_db", target_db, fade_seconds)


func _play_tutorial_stream(stream: AudioStreamWAV) -> void:
	if tutorial_player == null or stream == null:
		return
	tutorial_player.stream = stream
	tutorial_player.play()

func set_music_paused(paused: bool) -> void:
	if paused:
		set_music_context(MUSIC_CONTEXT_PAUSED)
	else:
		set_music_context(_context_before_pause)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var bus_index: int = AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, bus_name)


func _create_sfx_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "SFX"
	add_child(player)
	return player

func _set_bus_linear_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0
	)

func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	bgm_volume = clampf(float(config.get_value("audio", "bgm_volume", bgm_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)

func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "bgm_volume", bgm_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)

func get_shark_rush_stream() -> AudioStreamWAV:
	return shark_rush_stream


func get_shark_impact_stream() -> AudioStreamWAV:
	return shark_impact_stream


func _generate_correct_sound() -> void:
	var sample_rate: int = 44100
	var duration: float = 0.4
	var num_samples: int = int(sample_rate * duration)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit = 2 bytes per sample

	for i: int in range(num_samples):
		var t: float = float(i) / sample_rate
		var envelope: float = exp(-t * 8.0)

		# Frequency sweep 600 -> 1200 Hz
		var f_sweep: float = lerpf(600.0, 1200.0, float(i) / num_samples)
		var wave: float = sin(2.0 * PI * f_sweep * t)

		# Second layer 800 -> 1600 Hz
		var f_sweep2: float = lerpf(800.0, 1600.0, float(i) / num_samples)
		var wave2: float = sin(2.0 * PI * f_sweep2 * t) * exp(-t * 6.0)

		var combined: float = wave * envelope + wave2 * 0.5
		combined = clampf(combined, -1.0, 1.0)

		var sample: int = int(combined * 32767.0)
		data.encode_s16(i * 2, sample)

	stream.data = data
	correct_player.stream = stream

func _generate_explosion_sound() -> void:
	var sample_rate: int = 44100
	var duration: float = 1.2
	var num_samples: int = int(sample_rate * duration)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Generate noise and apply smoothing
	var noise: Array[float] = []
	noise.resize(num_samples)
	for i: int in range(num_samples):
		noise[i] = randf_range(-1.0, 1.0)

	# Simple moving average filter (low-pass)
	var window: int = 30
	var filtered: Array[float] = []
	filtered.resize(num_samples)
	for i: int in range(num_samples):
		var sum_val: float = 0.0
		var count: int = 0
		for j: int in range(maxi(0, i - window / 2), mini(num_samples, i + window / 2)):
			sum_val += noise[j]
			count += 1
		filtered[i] = sum_val / maxf(1.0, float(count))

	for i: int in range(num_samples):
		var t: float = float(i) / sample_rate
		var envelope: float = exp(-t * 4.0)

		# Attack ramp
		var attack: float = 1.0
		if i < 100:
			attack = float(i) / 100.0

		var boom: float = filtered[i] * envelope * attack * 1.5
		boom = clampf(boom, -1.0, 1.0)

		var sample: int = int(boom * 32767.0)
		data.encode_s16(i * 2, sample)

	stream.data = data
	explosion_player.stream = stream


func _generate_result_ceremony_sounds() -> void:
	var sample_rate := 44100

	# 2.4 seconds of a deterministic stepped trill. The alternating partials make
	# the score roll readable without relying on an imported voice sample.
	var roll_duration := 2.4
	var roll_samples := int(sample_rate * roll_duration)
	var roll_data := PackedByteArray()
	roll_data.resize(roll_samples * 2)
	for index: int in range(roll_samples):
		var time := float(index) / float(sample_rate)
		var step := int(time * 12.0)
		var frequency := 520.0 + float(step % 5) * 72.0
		var pulse_time := fposmod(time, 1.0 / 12.0)
		var envelope := 1.0 - smoothstep(0.0, 1.0, pulse_time * 12.0)
		var fade := smoothstep(0.0, 0.045, time) * smoothstep(0.0, 0.10, roll_duration - time)
		var wave := (
			sin(TAU * frequency * time) * 0.55
			+ sin(TAU * frequency * 1.5 * time) * 0.24
		) * envelope * fade
		roll_data.encode_s16(index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	var roll_stream := AudioStreamWAV.new()
	roll_stream.format = AudioStreamWAV.FORMAT_16_BITS
	roll_stream.mix_rate = sample_rate
	roll_stream.stereo = false
	roll_stream.data = roll_data
	result_roll_player.stream = roll_stream

	var lock_duration := 0.52
	var lock_samples := int(sample_rate * lock_duration)
	var lock_data := PackedByteArray()
	lock_data.resize(lock_samples * 2)
	for index: int in range(lock_samples):
		var time := float(index) / float(sample_rate)
		var envelope := exp(-time * 6.5)
		var wave := (
			sin(TAU * 880.0 * time)
			+ sin(TAU * 1320.0 * time) * 0.52
		) * envelope * 0.52
		lock_data.encode_s16(index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	var lock_stream := AudioStreamWAV.new()
	lock_stream.format = AudioStreamWAV.FORMAT_16_BITS
	lock_stream.mix_rate = sample_rate
	lock_stream.stereo = false
	lock_stream.data = lock_data
	result_lock_player.stream = lock_stream

	var impact_duration := 1.45
	var impact_samples := int(sample_rate * impact_duration)
	var impact_data := PackedByteArray()
	impact_data.resize(impact_samples * 2)
	var noise_state: int = 0x13579BDF
	for index: int in range(impact_samples):
		var time := float(index) / float(sample_rate)
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise := float(noise_state) / 1073741824.0 - 1.0
		var envelope := exp(-time * 3.4)
		var boom := sin(TAU * (92.0 - time * 34.0) * time) * exp(-time * 4.4)
		var crack := noise * exp(-time * 8.2)
		var wave := (boom * 0.72 + crack * 0.58) * envelope
		impact_data.encode_s16(index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	var impact_stream := AudioStreamWAV.new()
	impact_stream.format = AudioStreamWAV.FORMAT_16_BITS
	impact_stream.mix_rate = sample_rate
	impact_stream.stereo = false
	impact_stream.data = impact_data
	result_explosion_player.stream = impact_stream

	# A short original major arpeggio resolves only after the blast has cleared.
	var victory_duration := 2.0
	var victory_data := PackedByteArray()
	victory_data.resize(int(sample_rate * victory_duration) * 2)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for index in range(int(sample_rate * victory_duration)):
		var time := float(index) / sample_rate
		var wave := 0.0
		for note in range(notes.size()):
			var local_time := time - float(note) * 0.14
			if local_time >= 0.0:
				var envelope := (1.0 - exp(-local_time * 100.0)) * exp(-local_time * 3.2)
				wave += (sin(TAU * notes[note] * local_time) + 0.2 * sin(TAU * notes[note] * 2.0 * local_time)) * envelope * 0.20
		victory_data.encode_s16(index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	var victory_stream := AudioStreamWAV.new()
	victory_stream.format = AudioStreamWAV.FORMAT_16_BITS
	victory_stream.mix_rate = sample_rate
	victory_stream.stereo = false
	victory_stream.data = victory_data
	result_victory_player.stream = victory_stream


func _finale_wav(samples: PackedFloat32Array, sample_rate: int, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index in range(samples.size()):
		data.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## Original synthesized cues for the Score Tower Finale (deterministic noise).
func _generate_finale_sounds() -> void:
	var rate := 44100
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x2468ACE1

	# Pad pop: floor thump plus a springy rise as both platforms kick up.
	var pop := PackedFloat32Array()
	pop.resize(int(rate * 0.42))
	var phase := 0.0
	for i in range(pop.size()):
		var t := float(i) / rate
		var thump := sin(TAU * (95.0 - t * 90.0) * t) * exp(-t * 16.0)
		phase += TAU * (300.0 + 260.0 * smoothstep(0.02, 0.18, t) + 18.0 * sin(t * 90.0)) / rate
		var boing := sin(phase) * exp(-t * 9.0) * smoothstep(0.0, 0.02, t)
		pop[i] = thump * 0.75 + boing * 0.32 + rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.25
	_result_cues[&"pad_pop"] = _finale_wav(pop, rate)

	# Climb: an accelerating snare roll over a rising elevator tone (2.25 s).
	var climb := PackedFloat32Array()
	climb.resize(int(rate * 2.25))
	var lowpass := 0.0
	var tone := 0.0
	var roll_phase := 0.0
	for i in range(climb.size()):
		var t := float(i) / rate
		roll_phase += (13.0 + 15.0 * (t / 2.25)) / rate
		var hit := exp(-fposmod(roll_phase, 1.0) * 7.0)
		lowpass += (rng.randf_range(-1.0, 1.0) - lowpass) * 0.35
		tone += TAU * (180.0 + 200.0 * pow(t / 2.25, 1.4)) / rate
		var swell := smoothstep(0.0, 0.25, t) * lerpf(0.45, 1.0, t / 2.25) * smoothstep(2.25, 2.12, t)
		climb[i] = (lowpass * hit * 0.55 + sin(tone) * 0.14 + sin(tone * 2.0) * 0.05) * swell
	_result_cues[&"climb"] = _finale_wav(climb, rate)

	# Cymbal: bright decaying noise under the verdict slam.
	var cymbal := PackedFloat32Array()
	cymbal.resize(int(rate * 1.6))
	var previous := 0.0
	for i in range(cymbal.size()):
		var t := float(i) / rate
		var n := rng.randf_range(-1.0, 1.0)
		var bright := n - previous
		previous = n
		cymbal[i] = bright * 0.42 * exp(-t * 2.6) * smoothstep(0.0, 0.004, t)
	_result_cues[&"cymbal"] = _finale_wav(cymbal, rate)

	# Confetti cannons: four quick pops with a papery tail.
	var confetti := PackedFloat32Array()
	confetti.resize(int(rate * 0.8))
	for i in range(confetti.size()):
		var t := float(i) / rate
		var v := 0.0
		for k in range(4):
			var local := t - float(k) * 0.055
			if local >= 0.0:
				v += (rng.randf_range(-1.0, 1.0) * exp(-local * 55.0) * 0.7 + sin(TAU * 140.0 * local) * exp(-local * 30.0) * 0.5)
		v += rng.randf_range(-1.0, 1.0) * 0.08 * exp(-t * 3.0) * smoothstep(0.05, 0.12, t)
		confetti[i] = v * 0.6
	_result_cues[&"confetti"] = _finale_wav(confetti, rate)

	# Crown landing: a three-note sparkle.
	var crown := PackedFloat32Array()
	crown.resize(int(rate * 0.9))
	var notes := [1568.0, 2093.0, 2637.0]
	for i in range(crown.size()):
		var t := float(i) / rate
		var v := 0.0
		for k in range(notes.size()):
			var local := t - float(k) * 0.07
			if local >= 0.0:
				v += (sin(TAU * notes[k] * local) + 0.3 * sin(TAU * notes[k] * 2.01 * local)) * exp(-local * 6.5) * (1.0 - exp(-local * 400.0))
		crown[i] = v * 0.22
	_result_cues[&"crown"] = _finale_wav(crown, rate)

	# Sad trombone for the sinking tower: three steps down, the last one wobbling.
	var sad := PackedFloat32Array()
	sad.resize(int(rate * 2.2))
	var steps := [[0.0, 0.34, 293.66], [0.38, 0.34, 277.18], [0.76, 0.34, 261.63], [1.14, 1.0, 246.94]]
	var sad_phase := 0.0
	for i in range(sad.size()):
		var t := float(i) / rate
		var frequency := 0.0
		var envelope := 0.0
		for step: Array in steps:
			var local := t - float(step[0])
			if local >= 0.0 and local < float(step[1]):
				frequency = float(step[2])
				if step == steps.back():
					frequency *= 1.0 + 0.018 * sin(local * TAU * 5.5) - 0.04 * smoothstep(0.5, 1.0, local)
				envelope = smoothstep(0.0, 0.04, local) * smoothstep(float(step[1]), float(step[1]) - 0.08, local)
				# Plunger "wah": brighten then close on each note.
				envelope *= 0.75 + 0.25 * sin(clampf(local / float(step[1]), 0.0, 1.0) * PI)
		if frequency > 0.0:
			sad_phase += TAU * frequency / rate
		var brass := sin(sad_phase) * 0.6 + sin(sad_phase * 2.0) * 0.28 + sin(sad_phase * 3.0) * 0.16 + sin(sad_phase * 4.0) * 0.08
		sad[i] = brass * envelope * 0.42
	_result_cues[&"sad"] = _finale_wav(sad, rate)

	# Rain loop: soft filtered noise with sparse droplets (seamless 1 s loop).
	var rain := PackedFloat32Array()
	rain.resize(rate)
	var rain_low := 0.0
	for i in range(rain.size()):
		rain_low += (rng.randf_range(-1.0, 1.0) - rain_low) * 0.12
		var drip := 0.0
		if rng.randf() < 0.0006:
			drip = 0.6
		rain[i] = rain_low * 0.55 + drip * rng.randf_range(-1.0, 1.0)
	result_rain_player.stream = _finale_wav(rain, rate, true)


func _generate_shark_rush_sound() -> void:
	var sample_rate: int = 22050
	var duration: float = 1.0
	var num_samples: int = int(sample_rate * duration)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0x5A4B11
	var data: PackedByteArray = PackedByteArray()
	data.resize(num_samples * 2)
	var filtered_noise: float = 0.0
	for i: int in range(num_samples):
		var t: float = float(i) / float(sample_rate)
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.08)
		var churn: float = sin(TAU * 43.0 * t) * 0.18 + sin(TAU * 71.0 * t) * 0.09
		var seam_fade: float = minf(1.0, minf(t * 18.0, (duration - t) * 18.0))
		var value: float = clampf((filtered_noise * 0.68 + churn) * seam_fade, -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))
	stream.data = data
	shark_rush_stream = stream


func _generate_shark_impact_sound() -> void:
	var sample_rate: int = 44100
	var duration: float = 0.72
	var num_samples: int = int(sample_rate * duration)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0xB17E5
	var data: PackedByteArray = PackedByteArray()
	data.resize(num_samples * 2)
	var filtered_noise: float = 0.0
	for i: int in range(num_samples):
		var t: float = float(i) / float(sample_rate)
		var progress: float = t / duration
		var envelope: float = exp(-t * 6.2)
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.16)
		var frequency: float = lerpf(92.0, 42.0, progress)
		var boom: float = sin(TAU * frequency * t) * 0.78
		var snap: float = sin(TAU * 215.0 * t) * exp(-t * 22.0) * 0.46
		var splash: float = filtered_noise * 0.74
		var attack: float = minf(1.0, t * 120.0)
		var value: float = clampf((boom + snap + splash) * envelope * attack, -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))
	stream.data = data
	shark_impact_stream = stream


func _generate_tutorial_sounds() -> void:
	tutorial_step_stream = _make_tutorial_tone(420.0, 760.0, 0.24, 0.34)
	tutorial_task_stream = _make_tutorial_tone(720.0, 980.0, 0.12, 0.28)
	tutorial_complete_stream = _make_tutorial_tone(520.0, 1320.0, 0.38, 0.38)
	tutorial_settle_stream = _make_tutorial_tone(880.0, 620.0, 0.14, 0.22)


func _make_tutorial_tone(
		start_frequency: float,
		end_frequency: float,
		duration: float,
		amplitude: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := maxi(1, int(float(sample_rate) * duration))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for index: int in range(sample_count):
		var progress := float(index) / float(sample_count)
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / float(sample_rate)
		var attack := minf(1.0, progress * 18.0)
		var release := pow(1.0 - progress, 2.2)
		var harmonic := sin(phase * 2.0) * 0.18
		var value := clampf((sin(phase) + harmonic) * amplitude * attack * release, -1.0, 1.0)
		data.encode_s16(index * 2, int(value * 32767.0))
	stream.data = data
	return stream
