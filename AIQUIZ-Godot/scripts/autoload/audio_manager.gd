extends Node

const BGM_PATH := "res://assets/audio/bgm/quiz_party_loop.ogg"
## The loop is mastered to -16 LUFS, but CONTEXT_VOLUME_DB was tuned against the
## previous BGM at -25.4 LUFS (docs/bgm_renewal.md); trim to keep that balance.
const BGM_TRACK_GAIN_DB := -9.4
const SETTINGS_PATH := "user://audio_settings.cfg"
## v1 stored the BGM slider as a linear bus gain (1.0 = 0 dB); v2 uses the curve below.
const AUDIO_SETTINGS_VERSION := 2
## BGM slider (0..1) to bus gain. The default position plays at 0 dB (the v1 maximum),
## each halving of the slider is BGM_MAX_GAIN_DB quieter, and the top adds
## BGM_MAX_GAIN_DB, which cancels BGM_TRACK_GAIN_DB so the loop plays at its
## mastered level (peak -4.3 dBFS in gameplay).
const BGM_DEFAULT_VOLUME := 0.5
const BGM_MAX_GAIN_DB := -BGM_TRACK_GAIN_DB
const MUSIC_CONTEXT_MENU: StringName = &"menu"
const MUSIC_CONTEXT_GAMEPLAY: StringName = &"gameplay"
const MUSIC_CONTEXT_PAUSED: StringName = &"paused"
const MUSIC_CONTEXT_RESULT: StringName = &"result"
## 2P sudden death (docs/sudden_death_underground.md 9): BGM 10 dB under gameplay.
const MUSIC_CONTEXT_SUDDEN_DEATH: StringName = &"sudden_death"

const CONTEXT_VOLUME_DB := {
	MUSIC_CONTEXT_MENU: -4.0,
	MUSIC_CONTEXT_GAMEPLAY: 0.0,
	MUSIC_CONTEXT_PAUSED: -10.0,
	MUSIC_CONTEXT_RESULT: -4.0,
	MUSIC_CONTEXT_SUDDEN_DEATH: -10.0,
}

## The only sound effects in the game: the player hitting a wall. files: paths under res://assets/audio/sfx/ (one is picked at
## random). volume_db: base level. pitch_jitter: random +- ratio. min_interval:
## seconds before the same cue may play again. Sources: assets/audio/sfx/CREDITS.md.
const SFX_ROOT := "res://assets/audio/sfx/"
const SFX_CUES := {
	&"bonk": {"files": ["game/bonk_1.ogg", "game/bonk_2.ogg"], "volume_db": -3.0, "pitch_jitter": 0.04, "min_interval": 0.06},
	&"wall_crash": {"files": ["game/wall_crash.ogg"], "volume_db": -2.0, "pitch_jitter": 0.03, "min_interval": 0.06},
}
const SFX_VOICES := 4

## オーディオ管理 (Autoload)
## BGM と、上の壁にぶつかった音だけを鳴らす。

var bgm_player: AudioStreamPlayer

var sfx_volume: float = 1.0
var bgm_volume: float = BGM_DEFAULT_VOLUME
var _music_context: StringName = MUSIC_CONTEXT_MENU
var _context_before_pause: StringName = MUSIC_CONTEXT_MENU
var _context_tween: Tween = null
var _tutorial_ducked: bool = false
var _sfx_voices: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}
var _sfx_last_msec: Dictionary = {}
var _sfx_last_variant: Dictionary = {}

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
	bgm_player.volume_db = CONTEXT_VOLUME_DB[MUSIC_CONTEXT_MENU] + BGM_TRACK_GAIN_DB
	add_child(bgm_player)

	for index in range(SFX_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxVoice%d" % index
		voice.bus = "SFX"
		add_child(voice)
		_sfx_voices.append(voice)

	var game_state: QuizGameState = QuizManager.game_state
	game_state.sfx_volume = sfx_volume
	game_state.bgm_volume = bgm_volume

	set_sfx_volume(sfx_volume, false)
	set_bgm_volume(bgm_volume, false)
	# Playback starts on the first set_music_context(), so the startup loading
	# screen stays silent until the menu has actually appeared.


## Plays one of SFX_CUES. volume_db and pitch_scale apply on top of the cue's values.
func play_sfx(cue: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var def: Dictionary = SFX_CUES.get(cue, {})
	if def.is_empty():
		push_warning("AudioManager: unknown sfx cue '%s'" % cue)
		return
	var now := Time.get_ticks_msec()
	var min_interval_msec := int(float(def.get("min_interval", 0.0)) * 1000.0)
	if min_interval_msec > 0 and now - int(_sfx_last_msec.get(cue, -100000)) < min_interval_msec:
		return
	var stream := _sfx_pick_stream(cue, def)
	if stream == null:
		return
	_sfx_last_msec[cue] = now
	var player := _sfx_voices[0]
	for voice in _sfx_voices:
		if not voice.playing:
			player = voice
			break
	player.stream = stream
	player.volume_db = float(def.get("volume_db", 0.0)) + volume_db
	var jitter := float(def.get("pitch_jitter", 0.0))
	player.pitch_scale = maxf(0.05, pitch_scale * (1.0 + randf_range(-jitter, jitter)))
	player.play()


func _sfx_pick_stream(cue: StringName, def: Dictionary) -> AudioStream:
	var files: Array = def.get("files", [])
	if files.is_empty():
		return null
	var index := 0
	if files.size() > 1:
		index = randi() % files.size()
		if index == int(_sfx_last_variant.get(cue, -1)):
			index = (index + 1) % files.size()
	_sfx_last_variant[cue] = index
	var path: String = SFX_ROOT + String(files[index])
	if not _sfx_streams.has(path):
		_sfx_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _sfx_streams[path]


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
	_set_bus_volume_db("BGM", bgm_volume_to_db(bgm_volume))
	if save_setting:
		_save_audio_settings()

func bgm_volume_to_db(vol: float) -> float:
	if vol <= 0.0:
		return -80.0
	var halvings: float = log(vol / BGM_DEFAULT_VOLUME) / log(1.0 / BGM_DEFAULT_VOLUME)
	return maxf(-80.0, BGM_MAX_GAIN_DB * halvings)

func _bgm_volume_from_db(gain_db: float) -> float:
	if gain_db <= -80.0:
		return 0.0
	return clampf(BGM_DEFAULT_VOLUME * pow(1.0 / BGM_DEFAULT_VOLUME, gain_db / BGM_MAX_GAIN_DB), 0.0, 1.0)

func set_music_context(context: StringName, fade_seconds: float = 0.4) -> void:
	if context != MUSIC_CONTEXT_PAUSED:
		_context_before_pause = context
	_music_context = context
	if not is_instance_valid(bgm_player):
		return
	if not bgm_player.playing and bgm_player.stream != null:
		bgm_player.volume_db = -60.0
		bgm_player.play()
		fade_seconds = maxf(fade_seconds, 0.8)
	_apply_music_target(fade_seconds)


func _apply_music_target(fade_seconds: float) -> void:
	if not is_instance_valid(bgm_player):
		return
	var target_db: float = float(CONTEXT_VOLUME_DB.get(_music_context, 0.0)) + BGM_TRACK_GAIN_DB
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
	_set_bus_volume_db(bus_name, linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0)

func _set_bus_volume_db(bus_name: String, volume_db: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, volume_db)

func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	bgm_volume = clampf(float(config.get_value("audio", "bgm_volume", bgm_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	if int(config.get_value("audio", "version", 1)) < AUDIO_SETTINGS_VERSION:
		# Keep the loudness a v1 player chose; the slider just moves to the new curve.
		var v1_db: float = linear_to_db(bgm_volume) if bgm_volume > 0.0 else -80.0
		bgm_volume = snappedf(_bgm_volume_from_db(v1_db), 0.05)
		_save_audio_settings()

func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "version", AUDIO_SETTINGS_VERSION)
	config.set_value("audio", "bgm_volume", bgm_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)
