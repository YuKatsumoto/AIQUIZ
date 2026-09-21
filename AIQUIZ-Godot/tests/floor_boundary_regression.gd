extends RefCounted
## Run with the project autoloads loaded: new().run() returns a compact report.

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}

var checks := 0
var failures: Array[String] = []

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _fixture(provider: QuizProvider) -> QuizGameState:
	var gs := QuizGameState.new(provider)
	gs.num_players = 2
	gs.mode = Constants.MODE_ENDLESS
	gs.game_state = Constants.STATE_PLAYING
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.current_wall_index = 20
	gs._active_wall_speed = 2.9
	return gs

func run() -> Dictionary:
	checks = 0
	failures.clear()
	var provider := TestProvider.new()
	for fps: int in [30, 60, 120]:
		for mode: String in [Constants.MODE_TEN, Constants.MODE_ENDLESS]:
			for player: int in [1, 2]:
				for local_push: bool in [true, false]:
					for start_z: float in [139.49, 420.0]:
						var gs := _fixture(provider)
						gs.mode = mode
						gs.local_push_transport_enabled = local_push
						gs.player_z = start_z
						gs.player2_z = start_z
						for frame: int in range(4):
							gs.update(1.0 / fps,
								Vector2(0, 1) if player == 1 else Vector2.ZERO,
								Vector2(0, 1) if player == 2 else Vector2.ZERO)
						var label := str([fps, mode, player, local_push, start_z])
						_check(not gs.p1_fall_committed and not gs.p2_fall_committed, "supported ahead " + label)
						_check(is_equal_approx(gs.player_x, 1.5) and is_equal_approx(gs.player2_x, -1.5), "no sideways teleport " + label)
						_check(gs.player_y == 0.0 and gs.player2_y == 0.0, "both remain grounded " + label)
						var z := gs.player_local_z if player == 1 else gs.player2_local_z
						_check(absf(z - start_z - gs.tuning.player_speed * 4.0 / fps) < 0.001, "forward movement retained " + label)
	for player: int in [1, 2]:
		for edge: String in ["side", "rear", "coop_gap"]:
			var gs := _fixture(provider)
			gs.player_z = 0.0
			gs.player2_z = 0.0
			var axis := Vector2.ZERO
			if edge == "rear":
				if player == 1:
					gs.player_z = -12.49
				else:
					gs.player2_z = -12.49
				axis.y = -1.0
			else:
				var side := 1.0 if player == 1 else -1.0
				var x := 11.99 * side
				axis.x = side
				if edge == "coop_gap":
					gs.mode = Constants.MODE_COOP
					gs.player_x = 4.0
					gs.player2_x = -4.0
					x = (gs.tuning.coop_lane_gap_half_width + 0.01) * side
					axis.x = -side
				if player == 1:
					gs.player_x = x
				else:
					gs.player2_x = x
			gs.update(1.0 / 60.0, axis if player == 1 else Vector2.ZERO, axis if player == 2 else Vector2.ZERO)
			_check(gs.p1_fall_committed if player == 1 else gs.p2_fall_committed, "real edge still falls %s P%d" % [edge, player])
			_check((gs.player_y if player == 1 else gs.player2_y) < 0.0, "gravity at real edge %s P%d" % [edge, player])
	# Goal courses may extend past the previous hardcoded 400m boundary.
	var race := _fixture(provider)
	race.game_state = Constants.STATE_GOAL_RACE
	race.world_scroll_z = 60.0
	race.goal_z = 500.0
	race.player_z = 460.0
	race.player2_z = 460.0
	race.update(1.0 / 60.0, Vector2(0, 1), Vector2.ZERO)
	_check(not race.p1_fall_committed and race.player_y == 0.0, "race floor beyond 400 stays supported")
	_check(is_equal_approx(race.get_floor_front_z(), 460.0), "race front follows goal and scroll")
	for player: int in [1, 2]:
		var front: float = race.get_floor_front_z()
		_check(race._is_on_track_floor(0.0, front - 0.01, player), "inside finite front P%d" % player)
		_check(not race._is_on_track_floor(0.0, front + 0.01, player), "outside finite front P%d" % player)
		var before_x := race.player_x if player == 1 else race.player2_x
		if player == 1:
			race.player_z = race.world_scroll_z + front + 0.01
			race.player_y = -0.01
		else:
			race.player2_z = race.world_scroll_z + front + 0.01
			race.player2_y = -0.01
		race._commit_fall_if_unsupported(player, before_x, -0.01, front + 0.01)
		race._resolve_cliff_body_collision(player)
		var after_x := race.player_x if player == 1 else race.player2_x
		var after_z := race.player_local_z if player == 1 else race.player2_local_z
		_check(is_equal_approx(before_x, after_x), "front fall never ejects sideways P%d" % player)
		_check(after_z >= front + race.PLAYER_BODY_RADIUS - 0.001, "front collision resolves forward P%d" % player)
	provider.free()
	return {"passed": failures.is_empty(), "checks": checks, "failures": failures.duplicate()}
