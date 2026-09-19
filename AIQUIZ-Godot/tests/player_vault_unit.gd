extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	for fps in [30, 60, 120]:
		for local in [true, false]:
			for race in [true, false]:
				for player in [1, 2]:
					for direction in [-1, 1]:
						_case(fps, local, race, player, direction)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	FileAccess.open("res://artifacts/player_vault/unit.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PLAYER_VAULT_UNIT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _case(fps: int, local: bool, race: bool, player: int, direction: int) -> void:
	var gs = load("res://scripts/core/game_state.gd").new()
	gs.num_players = 2
	gs.mode = Constants.MODE_ENDLESS
	gs.game_state = Constants.STATE_GOAL_RACE if race else Constants.STATE_PLAYING
	gs.local_push_transport_enabled = local
	gs.goal_z = 1000.0
	gs.wall_z = 1000.0
	gs.player_x = -0.62 * direction if player == 1 else 0.62 * direction
	gs.player2_x = 0.62 * direction if player == 1 else -0.62 * direction
	gs.player_z = 0.0
	gs.player2_z = 0.0
	gs._active_wall_speed = 0.0
	var label := str([fps, local, race, player, direction])
	var crossed := false
	var stopped := false
	for frame in range(fps * 2):
		var axis := Vector2(direction, 0) if not stopped else Vector2.ZERO
		if race:
			gs._update_goal_race(1.0 / fps, axis if player == 1 else Vector2.ZERO, axis if player == 2 else Vector2.ZERO, player == 1 and frame == 0, player == 2 and frame == 0)
		else:
			gs._update_playing(1.0 / fps, axis if player == 1 else Vector2.ZERO, axis if player == 2 else Vector2.ZERO, player == 1 and frame == 0, player == 2 and frame == 0)
		var dx: float = (gs.player_x - gs.player2_x) * direction * (1 if player == 1 else -1)
		if dx >= 0.0 and not crossed:
			crossed = true
			_check(absf(gs.player_y - gs.player2_y) >= gs.PLAYER_BODY_HEIGHT, "body clearance " + label)
		if dx > 1.5:
			stopped = true
	_check(crossed, "crossed " + label)
	_check(gs.player_y == 0.0 and gs.player2_y == 0.0, "landed " + label)
	_check((gs.player_x - gs.player2_x) * direction * (1 if player == 1 else -1) > 1.24, "kept new side " + label)
