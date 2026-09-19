extends Node

var checks: Array[String] = []
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func run(world: Node) -> Dictionary:
	var gs: QuizGameState = QuizManager.game_state
	var saw: SawChaseController = world._saw_controller
	var dock := saw.dock
	world.set_process(false)
	world.camera_controller.set_process(false)
	var hold_t := dock.elapsed
	var hold_spin := saw.spin_time(gs)
	get_tree().paused = true
	await get_tree().create_timer(.25, true).timeout
	check(dock.elapsed == hold_t and saw.spin_time(gs) == hold_spin,"pause holds pose and spin")
	get_tree().paused = false
	gs.game_state = Constants.STATE_COUNTDOWN
	var before := saw.spin_time(gs)
	saw.update_visual(gs,.1,true)
	check(saw.spin_time(gs) >= before and dock.is_deployed(),"countdown continues deployed rotation")
	gs.game_state = Constants.STATE_PRELOADING
	before = saw.spin_time(gs)
	saw.update_visual(gs,20.0,true)
	check(saw.spin_time(gs) > before and is_equal_approx(dock.elapsed, dock.FINISH_TIME),"long generation wait never replays entrance")
	var dock_at := dock.global_position
	gs.game_state = Constants.STATE_PLAYING
	gs.saw.local_z = 8.0
	gs.saw.elapsed = 6.0
	saw.update_visual(gs,.1,true)
	check(dock.global_position.is_equal_approx(dock_at),"fixed dock does not follow chase carriage")
	var wheel_distance: float = gs.saw.wheel_distance + dock.wheel_distance()
	check(not dock.animated or wheel_distance >= 4.8,"deployment wheel travel preserved at handoff")
	for entry in [[1,Constants.MODE_TEN],[2,Constants.MODE_COOP],[2,Constants.MODE_TUTORIAL]]:
		gs.num_players = entry[0]
		gs.mode = entry[1]
		saw.update_visual(gs,.1,true)
		check(not saw.visible,"no saw in excluded mode " + str(entry))
	gs.num_players = 2
	gs.mode = Constants.MODE_ENDLESS
	saw.update_visual(gs,.1,true)
	check(saw.visible,"endless keeps saw visible")
	gs.mode = Constants.MODE_TEN
	# Load the existing physical regression, which exercises real ragdoll contacts.
	saw.finish_entrance()
	var previous = load("res://tests/saw_revision_runtime.gd").new()
	var prior: Dictionary = await previous.run(world)
	check(bool(prior.passed),"wall CCD, local blade lift and warning regression")
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"existing_physics":prior}
	FileAccess.open("res://artifacts/saw_vessel/revision2/regression.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	return result
