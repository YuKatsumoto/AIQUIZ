extends Node

## The gameplay sounds in the real GameWorld (docs/sound_effects.md): the correct-door ding,
## the wrong-door buzzer with the wall hit, the fatal crash, a push in the 2P duel and the
## landing from a jump. Uses the hp_unit fixture so the doors resolve through game logic.
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/gameplay_sfx_bootstrap.gd

var gs: QuizGameState
var world: Node
var helper: Node
var failures: Array[String] = []
var _last: Dictionary = {}
var started: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_TEN)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await _frames(60)
	gs.game_state = Constants.STATE_PLAYING
	gs.state_changed.emit(gs.game_state)
	await _frames(10)

	# P1 through the correct door, P2 into a wrong one.
	started.clear()
	helper.answer(gs, true, false)
	await _frames(6)
	_check_started(["door_correct.ogg", "wall_hit.ogg", "door_wrong.ogg"], "P1 correct / P2 wrong door")

	# A push lands in the 2P duel: queue the duel's own event and send it through the game's
	# flush (which adds the effect position and emits local_push_event).
	await _frames(30)
	started.clear()
	gs.local_push.events.append({"kind": "hit", "time": gs.local_push.time, "player": 1, "direction": 1.0, "x": 0.0})
	gs._flush_local_push_events()
	await _frames(4)
	_check_started(["push_kick.ogg"], "push hit")

	# A jump: P1 goes up and comes back down to the track.
	await _frames(10)
	started.clear()
	gs.player_vel_y = QuizGameState.JUMP_FORCE
	gs.player_y = 0.05
	var landed := false
	for i in range(240):
		await get_tree().process_frame
		_poll()
		if started.has("jump_land.ogg"):
			landed = true
			break
	_check(landed, "landing after a jump (heard %s)" % [started])

	# P2 runs out of hearts: the fatal crash.
	await _frames(30)
	started.clear()
	for i in range(2):
		helper.answer(gs, true, false)
		await _frames(30)
	_check(started.has("wall_hit.ogg") and started.has("door_wrong.ogg") and not gs.p2_alive, "fatal crash (heard %s, p2 alive %s)" % [started, gs.p2_alive])

	print("gameplay sfx runtime: %s" % ("PASS" if failures.is_empty() else "FAIL\n  " + "\n  ".join(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)


func _poll() -> void:
	for voice: AudioStreamPlayer in AudioManager._sfx_voices:
		var file := voice.stream.resource_path.get_file() if voice.playing and voice.stream != null else ""
		var pos := voice.get_playback_position() if voice.playing else -1.0
		var last: Array = _last.get(voice, ["", -1.0])
		if file != "" and (file != last[0] or (pos < 0.2 and pos < float(last[1]) - 0.2)):
			started.append(file)
		_last[voice] = [file, pos]


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
		_poll()


func _check_started(files: Array, what: String) -> void:
	for file: String in files:
		_check(started.has(file), "%s: %s (heard %s)" % [what, file, started])


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
