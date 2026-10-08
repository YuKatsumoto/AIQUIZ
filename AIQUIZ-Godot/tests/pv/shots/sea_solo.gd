extends RefCounted

## PV shot: 1P runs off the side of the floor into the sea, floats, and the shark comes for
## them (the game over that follows). Recorded as "sea" from the run-off to the game over.

var kit  # tests/pv/pv_runtime.gd


func run(runner) -> void:
	kit = runner
	var world = await kit.build_world(1, "math3")
	var gs := QuizManager.game_state
	gs.player_x = 4.0
	await kit.seconds(1.0)
	kit.record("sea")
	await kit.seconds(0.6)
	# Run to the +x side (A) and over the edge.
	var fell: bool = await kit.until(func() -> bool:
		kit.key(KEY_A, true)
		return gs.p1_waiting_for_shark or not gs.p1_alive, 60 * 15)
	kit.release_keys()
	kit.note("fell", fell)
	var bitten: bool = await kit.until(func() -> bool: return gs.p1_shark_killed, 60 * 25)
	kit.note("bitten", bitten)
	await kit.seconds(4.0)
	kit.note("final_state", gs.game_state)
