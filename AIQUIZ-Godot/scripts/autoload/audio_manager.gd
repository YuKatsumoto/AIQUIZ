extends Node

## オーディオ管理 (Autoload)
## Python版 synth.py の generate_correct_sound / generate_explosion_sound に相当
## Godotでは AudioStreamPlayer + AudioStreamGenerator で合成音を生成

var correct_player: AudioStreamPlayer
var explosion_player: AudioStreamPlayer

var sfx_volume: float = 1.0

func _ready() -> void:
	correct_player = AudioStreamPlayer.new()
	correct_player.name = "CorrectSFX"
	correct_player.bus = "Master"
	add_child(correct_player)

	explosion_player = AudioStreamPlayer.new()
	explosion_player.name = "ExplosionSFX"
	explosion_player.bus = "Master"
	add_child(explosion_player)

	# Generate audio samples
	_generate_correct_sound()
	_generate_explosion_sound()

	# Connect to game state
	var game_state: QuizGameState = QuizManager.game_state
	game_state.correct_answer.connect(play_correct)
	game_state.wrong_answer.connect(func(_msg: String): play_explosion())

func play_correct() -> void:
	correct_player.volume_db = linear_to_db(sfx_volume)
	correct_player.play()

func play_explosion() -> void:
	explosion_player.volume_db = linear_to_db(sfx_volume)
	explosion_player.play()

func set_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)

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
