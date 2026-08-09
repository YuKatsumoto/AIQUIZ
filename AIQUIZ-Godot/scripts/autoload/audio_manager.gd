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

## オーディオ管理 (Autoload)
## Python版 synth.py の generate_correct_sound / generate_explosion_sound に相当
## Godotでは AudioStreamPlayer + AudioStreamGenerator で合成音を生成

var correct_player: AudioStreamPlayer
var explosion_player: AudioStreamPlayer
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
	tutorial_player = AudioStreamPlayer.new()
	tutorial_player.name = "TutorialSFX"
	tutorial_player.bus = "SFX"
	add_child(tutorial_player)

	# Generate audio samples
	_generate_correct_sound()
	_generate_explosion_sound()
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
