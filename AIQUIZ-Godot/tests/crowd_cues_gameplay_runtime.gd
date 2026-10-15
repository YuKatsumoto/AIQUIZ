extends Node

## The crowd's cues inside the real game world (scenes/game_world.tscn): the
## countdown and the start, lost HP, a wrong door, a saw catch and the stadium
## wave reach CrowdCues through the game's own signals, and the stands follow.
##   Godot --path . --script tests/crowd_cues_gameplay_bootstrap.gd --fixed-fps 60
## Screenshots from the game camera go to artifacts/crowd_extras/gameplay/.

const OUT := "res://artifacts/crowd_extras/gameplay/"

var world: Node
var gs: QuizGameState
var errors: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


var states: Array = []


func _wait(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
		var now := String(gs.game_state)
		if states.is_empty() or states.back()[0] != now:
			states.append([now, Engine.get_process_frames()])


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_tree().root.size = Vector2i(1280, 720)
	gs = get_tree().root.get_node("QuizManager").game_state
	get_tree().root.get_node("QuizManager").provider.set("llm_mode", "OFFLINE")
	gs.llm_mode = "OFFLINE"
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait(90)
	var cues: CrowdCues = world.get("_crowd_cues")
	check(cues != null, "game world owns the crowd cues")
	if cues == null:
		_finish()
		return
	gs.game_state = Constants.STATE_COUNTDOWN
	await _wait(30)
	check(cues.cue == CrowdCues.Cue.COUNTDOWN, "countdown reaches the crowd (%s)" % CrowdCues.Cue.keys()[cues.cue])
	await _shot("countdown")
	gs.game_state = Constants.STATE_PLAYING
	await _wait(20)
	check(cues.cue == CrowdCues.Cue.START, "the start reaches the crowd")
	await _shot("start")
	# This harness has no questions, so the round ends ~10 s in: bring the first
	# wave forward (the game schedules it WAVE_FIRST_DELAY after the start).
	report["first_wave_scheduled_in"] = snappedf(cues._next_wave - cues.clock, 0.01)
	check(absf(cues._next_wave - cues.clock - (CrowdCues.WAVE_FIRST_DELAY - 20.0 / 60.0)) < 0.2, "the first wave is scheduled after the start")
	cues._next_wave = cues.clock + 5.5
	await _wait(140)
	# Lost HP (a wrong door in HP mode takes one heart).
	gs._set_player_hp(1, gs.get_player_hp(1) - 1)
	await _wait(10)
	check(cues.cue == CrowdCues.Cue.HURT and cues.cue_team == 1, "lost HP reaches the crowd")
	await _wait(140)
	# A wrong door: P2 faced the question but only P1 was right.
	gs._hp_evaluated_mask = 3
	gs.record_question_winner(gs.question_winners.size(), 1)
	await _wait(20)
	check(cues.cue == CrowdCues.Cue.MISS and cues.cue_team == 2, "P2's wrong door reaches the crowd")
	await _shot("miss_p2")
	# The first wave leaves the mascot WAVE_FIRST_DELAY after the start.
	var waited := 0
	while cues.wave_time() < 0.0 and waited < 240:
		await _wait(1)
		waited += 1
	check(cues.wave_time() >= 0.0, "a stadium wave starts during play")
	report["wave_after_frames"] = waited
	await _wait(40)
	await _shot("wave")
	# The saw catches P1: a miss and a gasp around P1.
	gs.player_caught_by_saw.emit(1)
	await _wait(5)
	check(cues.shock_time() >= 0.0, "the saw catch makes the nearby seats gasp")
	check(cues.cue == CrowdCues.Cue.MISS and cues.cue_team == 1, "the saw catch is a miss for P1")
	await _wait(240)
	report["cues"] = cues.snapshot()
	report["states"] = states
	_finish()


func _finish() -> void:
	print("CROWD_CUES_GAMEPLAY ", "PASS" if errors.is_empty() else "FAIL", " ", JSON.stringify({"errors": errors, "report": report}))
	get_tree().quit(0 if errors.is_empty() else 1)
