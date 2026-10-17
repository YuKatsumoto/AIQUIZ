extends Node

## Ghost shark ride sound effects (docs/sound_effects.md) through the real 2P route: a fatal wall
## hit, the soul / ascent / breach / mount beam sequence, a held charge (hum, no PERFECT cue), a
## missed dash with the return portal, then a dash aimed at the survivor. Records the cues with the
## ride phase they fired in and the SFX bus output to artifacts/ghost_shark_audio/.
const OUT := "res://artifacts/ghost_shark_audio/"
const RIDER := 1

var gs: QuizGameState
var world: Node3D
var ghost: GhostSharkRideController
var helper: Node
var failures: Array[String] = []
var checks := 0
var events: Array[Dictionary] = []
var charge_samples: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var _clock := 0.0
var _capture: AudioEffectCapture
var _file: FileAccess
var _effect_index := -1
var _bus := -1
var _peak := 0.0
var _last_phase := -1
var phase_log: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("run")


func _process(dt: float) -> void:
	_clock += dt
	if ghost != null and ghost.phase != _last_phase:
		_last_phase = ghost.phase
		phase_log.append({"phase": ghost.Phase.keys()[ghost.phase], "time": snappedf(_clock, 0.001), "state": gs.game_state, "p1": gs.p1_alive, "p2": gs.p2_alive})
	if _capture != null and _file != null:
		var buffer := _capture.get_buffer(_capture.get_frames_available())
		if not buffer.is_empty():
			_file.store_buffer(buffer.to_byte_array())
			_peak = maxf(_peak, db_to_linear(maxf(
				AudioServer.get_bus_peak_volume_left_db(_bus, 0),
				AudioServer.get_bus_peak_volume_right_db(_bus, 0)
			)))


func _cue(cue: StringName) -> void:
	var phase_name := "-"
	if ghost != null:
		phase_name = ghost.Phase.keys()[ghost.phase]
	events.append({"cue": str(cue), "phase": phase_name, "time": snappedf(_clock, 0.001)})


func _resolved(player_index: int, hit: bool, power: float) -> void:
	shots.append({"player": player_index, "hit": hit, "power": snappedf(power, 0.01), "time": snappedf(_clock, 0.001)})


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_bus = AudioServer.get_bus_index("SFX")
	_effect_index = AudioServer.get_bus_effect_count(_bus)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 10.0
	AudioServer.add_bus_effect(_bus, _capture)
	AudioManager.sfx_played.connect(_cue)

	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	world.get_node("Player").reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	ghost.charge_resolved.connect(_resolved)
	await seconds(0.8)

	_capture.clear_buffer()
	_file = FileAccess.open(OUT + "ride.f32", FileAccess.WRITE)
	var ride_start := _clock
	gs._set_player_hp(RIDER, 1)
	gs.player_x = helper.door(gs, false)
	gs.resolve_collision(true, false)
	# Waits are in seconds: the game runs uncapped (about 190 fps here), so frame budgets lie.
	var reached := await wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 40.0)
	check(reached, "fatal wall hit reaches ghost aiming")
	if not reached:
		finish()
		return
	for cue in ["ghost_soul_rise", "ghost_shark_rise", "ghost_shark_breach", "ghost_mount_beam"]:
		check(count(cue) == 1, "%s plays once in the summon sequence" % cue)
	check(phase_of("ghost_soul_rise") == "SOUL_RISE", "soul cue fires as the soul rises")
	check(phase_of("ghost_mount_beam") == "BEAM_REVEAL", "beam cue fires with the pillar")
	check(time_of("ghost_shark_rise") <= time_of("ghost_shark_breach"), "ascent precedes the breach")
	check(time_of("ghost_shark_breach") < time_of("ghost_mount_beam"), "breach precedes the mount beam")
	var charge_audio: AudioStreamPlayer = ghost.get("_charge_audio")
	check(charge_audio != null and charge_audio.stream != null, "dedicated charge hum player exists")
	check(charge_audio != null and not charge_audio.playing, "charge hum silent before the button is held")

	await seconds(0.5)
	# Shot 1: aim away from the survivor (miss), hold through one full meter cycle and release in
	# the PERFECT band.
	ghost.set("_aim_offset", Vector2(5.0, 7.0))
	await hold_charge(0.8)
	check(charge_samples.any(func(s): return s.playing), "charge hum plays while the button is held")
	var pitches: Array = charge_samples.filter(func(s): return s.playing).map(func(s): return s.pitch)
	check(pitches.size() >= 2 and pitches.max() > pitches.min() + 0.2, "charge hum pitch rises with the meter")
	check(count("ghost_charge_perfect") == 0, "no extra cue when the meter enters the PERFECT band")
	key(KEY_SPACE, false)
	await frames(2)
	check(ghost.get("_perfect_charge"), "first shot released in the PERFECT band")
	check(not charge_audio.playing, "charge hum stops on release")
	await wait_back_to_aiming()
	check(count("ghost_dash") == 1 and phase_of("ghost_dash") == "CHARGING", "dash cue at launch")
	check(count("ghost_vanish") == 1 and phase_of("ghost_vanish") == "COOLDOWN", "vanish cue when the shark leaves")
	check(count("ghost_portal_open") == 1, "portal opens with sound")
	check(count("ghost_portal_cross") == 1, "shark crossing the portal has sound")
	check(time_of("ghost_portal_open") < time_of("ghost_portal_cross"), "portal opens before the crossing")

	# Shot 2: aim at the survivor (default target).
	await seconds(0.3)
	ghost.set("_aim_offset", Vector2.ZERO)
	await hold_charge(0.2)
	key(KEY_SPACE, false)
	var hit := await wait_until(func(): return count("ghost_hit") > 0, 4.0)
	check(count("ghost_dash") == 2, "second dash has its cue")
	check(hit, "dash aimed at the survivor lands and plays the hit")
	await wait_until(func(): return shots.size() >= 2, 6.0)
	# Let the second return portal play so the capture contains it too.
	await wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 10.0)
	check(shots.size() == 2 and shots[1].hit == hit, "hit cue matches the resolved second shot")
	ghost.force_cleanup()
	await frames(2)
	check(charge_audio == null or not charge_audio.playing, "cleanup leaves no charge hum")
	_file.close()
	_file = null
	check(_peak > 0.001, "SFX bus outputs real sound")
	print("GHOST_RIDE_SECONDS %.2f" % (_clock - ride_start))
	finish()


func hold_charge(release_charge: float) -> void:
	## Holds the button until the meter has wrapped once (for release_charge > 0.5) and reaches
	## release_charge, sampling the dedicated hum every frame.
	key(KEY_SPACE, true)
	var start := _clock
	var wrapped := release_charge <= 0.5
	var previous := 0.0
	while _clock - start < 3.0:
		await frames(1)
		var charge := float(ghost.get("_charge_amount"))
		var player: AudioStreamPlayer = ghost.get("_charge_audio")
		charge_samples.append({
			"time": snappedf(_clock, 0.001),
			"charge": snappedf(charge, 0.001),
			"playing": player != null and player.playing,
			"pitch": snappedf(player.pitch_scale, 0.001) if player != null else 0.0,
			"volume_db": snappedf(player.volume_db, 0.01) if player != null else 0.0,
		})
		wrapped = wrapped or charge < previous
		previous = charge
		if wrapped and charge >= release_charge:
			return


func wait_back_to_aiming() -> void:
	await wait_until(func(): return ghost.phase == ghost.Phase.COOLDOWN, 6.0)
	await wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 12.0)


func wait_until(condition: Callable, timeout: float) -> bool:
	var start := _clock
	while _clock - start < timeout:
		if condition.call():
			return true
		await frames(1)
	return bool(condition.call())


func seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func count(cue: String) -> int:
	return events.filter(func(e): return e.cue == cue).size()


func phase_of(cue: String) -> String:
	for e in events:
		if e.cue == cue:
			return e.phase
	return ""


func time_of(cue: String) -> float:
	for e in events:
		if e.cue == cue:
			return e.time
	return INF


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func finish() -> void:
	if _file != null:
		_file.close()
	AudioManager.sfx_played.disconnect(_cue)
	AudioServer.remove_bus_effect(_bus, _effect_index)
	var report := {
		"passed": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"events": events,
		"shots": shots,
		"phase_log": phase_log,
		"charge_samples": charge_samples,
		"snapshots": [{"phase": "ride", "sample_rate": AudioServer.get_mix_rate(), "peak": _peak}],
		"capture_stereo_pairs": AudioServer.get_bus_channels(_bus),
	}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("GHOST_SHARK_AUDIO " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
