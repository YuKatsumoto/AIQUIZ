extends Node

const BGM_PATH := "res://assets/audio/bgm/quiz_party_loop.ogg"
## The loop is mastered to -16 LUFS, but CONTEXT_VOLUME_DB was tuned against the
## previous BGM at -25.4 LUFS (docs/bgm_renewal.md); trim to keep that balance.
const BGM_TRACK_GAIN_DB := -9.4
const SETTINGS_PATH := "user://audio_settings.cfg"
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

## Sample-based sound effects (CC0 libraries, see assets/audio/sfx/CREDITS.md).
const SfxCatalog := preload("res://scripts/autoload/sfx_catalog.gd")
const SFX_ROOT := "res://assets/audio/sfx/"
const SFX_VOICES := 16
## UI focus sounds are skipped right after a scene change, when screens grab
## focus programmatically.
const UI_FOCUS_SOUND_GRACE_MSEC := 350
const UI_NAV_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right",
	&"ui_focus_next", &"ui_focus_prev"]
## Press cue picked from a button's name/text: whole English words, Japanese substrings.
const UI_BACK_TOKENS: Array[String] = ["back", "close", "cancel", "quit", "exit", "return"]
const UI_BACK_TEXT: Array[String] = ["戻る", "もどる", "閉じる", "とじる", "キャンセル", "やめる", "終了",
	"タイトルへ", "メニュー"]
const UI_CONFIRM_TOKENS: Array[String] = ["start", "confirm", "begin", "go", "ok", "retry"]
const UI_CONFIRM_TEXT: Array[String] = ["スタート", "はじめる", "開始", "決定", "けってい", "もう一度", "リトライ"]

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
var _sfx_voices: Array[AudioStreamPlayer] = []
var _sfx_voice_started: Array[int] = []
var _sfx_streams: Dictionary = {}
var _sfx_last_msec: Dictionary = {}
var _sfx_last_variant: Dictionary = {}
var _sfx_loops: Dictionary = {}
var _sfx_loop_tweens: Dictionary = {}
var _sfx_loop_owners: Dictionary = {}
var _scene_started_msec: int = 0
var _ui_camel_regex: RegEx = null
var _ui_split_regex: RegEx = null

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
	# Eight voices: egg throws/splats arrive about once a second during the
	# verdict and used to cut the long cheer and boo short.
	for index in range(8):
		crowd_players.append(_create_sfx_player("GoalStandCrowd%d" % index))
	result_hero_impact = load("res://assets/audio/sfx/result_toon/hero_impact.ogg")
	result_hero_swish = load("res://assets/audio/sfx/result_toon/hero_swish.ogg")
	result_verdict_impact = load("res://assets/audio/sfx/result_toon/verdict_impact.ogg")
	tutorial_player = AudioStreamPlayer.new()
	tutorial_player.name = "TutorialSFX"
	tutorial_player.bus = "SFX"
	add_child(tutorial_player)
	for index in range(SFX_VOICES):
		_sfx_voices.append(_create_sfx_player("SfxVoice%d" % index))
		_sfx_voice_started.append(0)
	get_tree().node_added.connect(_on_tree_node_added)

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
	# Wrong answers are voiced where they show: the wall bonk/crash at the hit and
	# the explosion when the body bursts (game_world.gd).

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
		result_accent_player]
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
	# Prefer an idle voice so a long cheer or boo is not cut by a short splat.
	var player := crowd_players[_crowd_index % crowd_players.size()]
	for offset in range(crowd_players.size()):
		var candidate := crowd_players[(_crowd_index + offset) % crowd_players.size()]
		if not candidate.playing:
			player = candidate
			_crowd_index += offset
			break
	_crowd_index += 1
	player.stream = _crowd_streams[cue]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


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


## Plays a catalog cue (scripts/autoload/sfx_catalog.gd) on a pooled 2D voice.
## volume_db and pitch_scale are applied on top of the catalog values.
func play_sfx(cue: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var def: Dictionary = SfxCatalog.CUES.get(cue, {})
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
	var voice_index := _sfx_free_voice_index()
	var player := _sfx_voices[voice_index]
	player.stream = stream
	player.volume_db = float(def.get("volume_db", 0.0)) + volume_db
	var jitter := float(def.get("pitch_jitter", 0.0))
	player.pitch_scale = maxf(0.05, pitch_scale * float(def.get("pitch", 1.0)) * (1.0 + randf_range(-jitter, jitter)))
	player.play()
	_sfx_voice_started[voice_index] = now


## Starts a looping cue under `key`, or retargets its volume if it already
## runs. When `owner_node` leaves the tree the loop fades out on its own.
func start_sfx_loop(key: StringName, cue: StringName, volume_db: float = 0.0, fade_in: float = 0.15,
		owner_node: Node = null) -> void:
	var def: Dictionary = SfxCatalog.CUES.get(cue, {})
	if def.is_empty():
		push_warning("AudioManager: unknown sfx loop cue '%s'" % cue)
		return
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	if player == null:
		player = _create_sfx_player("SfxLoop_%s" % key)
		_sfx_loops[key] = player
	var target_db := float(def.get("volume_db", 0.0)) + volume_db
	if owner_node != null:
		_sfx_loop_owners[key] = owner_node
	else:
		_sfx_loop_owners.erase(key)
	if player.playing and player.has_meta(&"cue") and player.get_meta(&"cue") == cue:
		_fade_sfx_loop(key, target_db, fade_in, false)
		return
	var stream := _sfx_pick_stream(cue, def)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.set_meta(&"cue", cue)
	player.stream = stream
	player.pitch_scale = float(def.get("pitch", 1.0))
	player.volume_db = -60.0 if fade_in > 0.0 else target_db
	player.play()
	if fade_in > 0.0:
		_fade_sfx_loop(key, target_db, fade_in, false)


## Loops started with an owner fade out once that node leaves the tree
## (scene change, freed controller), even if nobody calls stop_sfx_loop().
func _process(_delta: float) -> void:
	if _sfx_loop_owners.is_empty():
		return
	for key: StringName in _sfx_loop_owners.keys():
		var owner_node = _sfx_loop_owners[key]  # Untyped: the node may already be freed.
		if not is_instance_valid(owner_node) or not (owner_node as Node).is_inside_tree():
			_sfx_loop_owners.erase(key)
			stop_sfx_loop(key, 0.15)


func stop_sfx_loop(key: StringName, fade_out: float = 0.25) -> void:
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	if player == null or not player.playing:
		return
	if fade_out <= 0.0:
		player.stop()
		return
	_fade_sfx_loop(key, -60.0, fade_out, true)


func set_sfx_loop_pitch(key: StringName, pitch_scale: float) -> void:
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	if player != null:
		player.pitch_scale = maxf(0.05, pitch_scale)


## volume_db is relative to the cue's catalog level, as in start_sfx_loop().
func set_sfx_loop_volume(key: StringName, volume_db: float) -> void:
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	if player == null or not player.playing or not player.has_meta(&"cue"):
		return
	var previous: Tween = _sfx_loop_tweens.get(key)
	if is_instance_valid(previous) and previous.is_running():
		return  # Let fade-ins and fade-outs finish.
	var def: Dictionary = SfxCatalog.CUES.get(player.get_meta(&"cue"), {})
	player.volume_db = float(def.get("volume_db", 0.0)) + volume_db


## For world scripts that own positional players: one variant of a cue and its
## catalog level, so 3D sounds share files and mix with play_sfx().
func get_sfx_stream(cue: StringName) -> AudioStream:
	var def: Dictionary = SfxCatalog.CUES.get(cue, {})
	return null if def.is_empty() else _sfx_pick_stream(cue, def)


func get_sfx_volume_db(cue: StringName) -> float:
	return float(SfxCatalog.CUES.get(cue, {}).get("volume_db", 0.0))


func is_sfx_loop_playing(key: StringName) -> bool:
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	return player != null and player.playing


func _fade_sfx_loop(key: StringName, target_db: float, seconds: float, stop_after: bool) -> void:
	var player: AudioStreamPlayer = _sfx_loops.get(key)
	if player == null:
		return
	var previous: Tween = _sfx_loop_tweens.get(key)
	if is_instance_valid(previous):
		previous.kill()
	if seconds <= 0.0:
		player.volume_db = target_db
		if stop_after:
			player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, seconds)
	if stop_after:
		tween.tween_callback(player.stop)
	_sfx_loop_tweens[key] = tween


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
		if not ResourceLoader.exists(path):
			push_warning("AudioManager: missing sfx file %s" % path)
			_sfx_streams[path] = null
		else:
			_sfx_streams[path] = load(path)
	return _sfx_streams[path]


func _sfx_free_voice_index() -> int:
	var oldest := 0
	for index in range(_sfx_voices.size()):
		if not _sfx_voices[index].playing:
			return index
		if _sfx_voice_started[index] < _sfx_voice_started[oldest]:
			oldest = index
	return oldest


## Gives every Button / Slider / TabBar in the game a UI sound without touching
## each screen. A control can opt out with set_meta("sfx_silent", true) or pick
## its own press cue with set_meta("sfx_press", &"cue").
func _on_tree_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root:
		_scene_started_msec = Time.get_ticks_msec()
	if not (node is Control) or node.has_meta(&"_sfx_hooked"):
		return
	if node is BaseButton:
		var button := node as BaseButton
		node.set_meta(&"_sfx_hooked", true)
		if button.toggle_mode:
			button.toggled.connect(_on_ui_button_toggled.bind(button))
		else:
			button.pressed.connect(_on_ui_button_pressed.bind(button))
		button.mouse_entered.connect(_on_ui_control_hovered.bind(button))
		button.focus_entered.connect(_on_ui_control_focused.bind(button))
	elif node is Slider:
		var slider := node as Slider
		node.set_meta(&"_sfx_hooked", true)
		slider.value_changed.connect(_on_ui_slider_changed.bind(slider))
		slider.focus_entered.connect(_on_ui_control_focused.bind(slider))
	elif node is TabBar:
		node.set_meta(&"_sfx_hooked", true)
		(node as TabBar).tab_clicked.connect(_on_ui_tab_clicked.bind(node))
	elif node is TabContainer:
		node.set_meta(&"_sfx_hooked", true)
		(node as TabContainer).tab_clicked.connect(_on_ui_tab_clicked.bind(node))


## Presses skip the visibility test: the button's own handler often hides its
## screen before this hook runs.
func _ui_sound_allowed(control: Control, require_visible: bool = true) -> bool:
	if not is_instance_valid(control) or control.get_meta(&"sfx_silent", false):
		return false
	return not require_visible or control.is_visible_in_tree()


func _on_ui_button_pressed(button: BaseButton) -> void:
	if not _ui_sound_allowed(button, false):
		return
	play_sfx(_ui_press_cue(button))


func _on_ui_button_toggled(toggled_on: bool, button: BaseButton) -> void:
	if not _ui_sound_allowed(button, false):
		return
	if button.has_meta(&"sfx_press"):
		play_sfx(button.get_meta(&"sfx_press"))
	else:
		play_sfx(&"ui_toggle_on" if toggled_on else &"ui_toggle_off")


func _on_ui_control_hovered(control: Control) -> void:
	if not _ui_sound_allowed(control) or control.get_meta(&"sfx_no_hover", false):
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	play_sfx(&"ui_hover")


## Keyboard / gamepad focus moves only: screens that call grab_focus() on open
## stay silent.
func _on_ui_control_focused(control: Control) -> void:
	if not _ui_sound_allowed(control) or control.get_meta(&"sfx_no_hover", false):
		return
	if Time.get_ticks_msec() - _scene_started_msec < UI_FOCUS_SOUND_GRACE_MSEC:
		return
	for action in UI_NAV_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			play_sfx(&"ui_hover")
			return


func _on_ui_slider_changed(value: float, slider: Slider) -> void:
	if not _ui_sound_allowed(slider):
		return
	# Values set from code (screen setup, loading settings) stay silent.
	if not slider.has_focus() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var span := slider.max_value - slider.min_value
	var ratio := 0.5 if span <= 0.0 else clampf((value - slider.min_value) / span, 0.0, 1.0)
	play_sfx(&"ui_slider", 0.0, lerpf(0.85, 1.3, ratio))


func _on_ui_tab_clicked(_tab: int, control: Control) -> void:
	if _ui_sound_allowed(control, false):
		play_sfx(&"ui_tab")


func _ui_press_cue(button: BaseButton) -> StringName:
	if button.has_meta(&"sfx_press"):
		return button.get_meta(&"sfx_press")
	var label := String(button.name)
	if button is Button:
		label += " " + (button as Button).text
	var tokens := _ui_label_tokens(label)
	for word in UI_BACK_TOKENS:
		if tokens.has(word):
			return &"ui_back"
	for word in UI_BACK_TEXT:
		if label.contains(word):
			return &"ui_back"
	for word in UI_CONFIRM_TOKENS:
		if tokens.has(word):
			return &"ui_confirm"
	for word in UI_CONFIRM_TEXT:
		if label.contains(word):
			return &"ui_confirm"
	return &"ui_click"


## "BackButton" / "start_btn" / "Quit Game" -> ["back", "button"], ["start", "btn"], ["quit", "game"].
func _ui_label_tokens(label: String) -> PackedStringArray:
	if _ui_camel_regex == null:
		_ui_camel_regex = RegEx.create_from_string("([a-z0-9])([A-Z])")
		_ui_split_regex = RegEx.create_from_string("[^a-z0-9]+")
	var spaced := _ui_camel_regex.sub(label, "$1 $2", true).to_lower()
	var tokens := PackedStringArray()
	for part in _ui_split_regex.sub(spaced, " ", true).split(" ", false):
		tokens.append(part)
	return tokens


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
	# result_ceremony_director plays "swish" right after the verdict.
	if result_hero_swish != null:
		_result_cues[&"swish"] = result_hero_swish


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
