extends RefCounted
## Run with the project autoloads loaded: new().run() returns a compact report.
## 問題の壁の延長線上（壁端より外）をワールドボーダーが塞ぎ、前へ出させず後ろへ押し戻すことを確かめる。

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}

var checks := 0
var failures: Array[String] = []
var _pushes: Array[int] = []

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
	gs.world_border_pushed.connect(func(player_index: int) -> void: _pushes.append(player_index))
	return gs

func _set_player(gs: QuizGameState, player: int, x: float, z: float) -> void:
	if player == 1:
		gs.player_x = x
		gs.player_z = z
	else:
		gs.player2_x = x
		gs.player2_z = z

func _z(gs: QuizGameState, player: int) -> float:
	return gs.player_z if player == 1 else gs.player2_z

func run() -> Dictionary:
	checks = 0
	failures.clear()
	var provider := TestProvider.new()
	var stop := QuizGameState.WALL_WORLD_BORDER_STOP_DISTANCE
	_check(StageConstants.QUIZ_WALL_HALF_WIDTH + 0.12 < 11.86 - 0.12, "wall edge stays inside the rail base")
	_check(stop > 0.41, "border stops players before the wall hit line")
	for player: int in [1, 2]:
		for side: float in [1.0, -1.0]:
			var label := "P%d side %+d" % [player, int(side)]
			# 壁端より外（線路側）を前へ走り続ける → 壁の線で止まり、後ろへ弾かれる。被弾はしない。
			var gs := _fixture(provider)
			_pushes.clear()
			var other := 2 if player == 1 else 1
			# 相方は壁にもスクロールアウトにも掛からない位置で待機させる。
			_set_player(gs, other, 0.0, gs.wall_z - 3.0)
			var x := 11.75 * side
			_set_player(gs, player, x, gs.wall_z - 2.0)
			var axis := Vector2(0.0, 1.0)
			var max_z := -INF
			for frame: int in range(30):
				gs.update(1.0 / 60.0, axis if player == 1 else Vector2.ZERO, axis if player == 2 else Vector2.ZERO)
				max_z = maxf(max_z, _z(gs, player))
			var vel := gs.p1_external_velocity if player == 1 else gs.p2_external_velocity
			_check(max_z <= gs.wall_z - stop + 0.0001, "never passes the wall line " + label)
			_check(_pushes.has(player), "push signal " + label)
			_check(_pushes.size() <= 3, "push not spammed every frame " + label)
			_check(gs.p1_alive and gs.p2_alive, "border is not a wall crash " + label)
			_check(gs.current_wall_index == 20, "border does not answer the wall " + label)
			_check(not (gs.p1_fall_committed if player == 1 else gs.p2_fall_committed), "no fall at border " + label)
			_check(is_equal_approx(gs.player_x if player == 1 else gs.player2_x, x), "not pushed sideways " + label)
			# 手を離すと後ろへ戻される。
			var after_push := _fixture(provider)
			_pushes.clear()
			_set_player(after_push, other, 0.0, after_push.wall_z - 3.0)
			_set_player(after_push, player, x, after_push.wall_z - stop + 0.05)
			after_push.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
			for frame: int in range(20):
				after_push.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
			_check(_z(after_push, player) < after_push.wall_z - stop - 0.8, "shoved back from the border " + label)

			# 壁から離れた場所では従来どおり床端から落ちられる。
			var far := _fixture(provider)
			_pushes.clear()
			_set_player(far, player, 11.99 * side, far.wall_z - 20.0)
			far.update(1.0 / 60.0, Vector2(side, 0.0) if player == 1 else Vector2.ZERO, Vector2(side, 0.0) if player == 2 else Vector2.ZERO)
			_check(far.p1_fall_committed if player == 1 else far.p2_fall_committed, "far from wall still falls " + label)
			_check(_pushes.is_empty(), "no border far from wall " + label)

			# 落下が確定したプレイヤーは止めない。
			var fallen := _fixture(provider)
			_set_player(fallen, player, 12.5 * side, fallen.wall_z - 0.6)
			if player == 1:
				fallen.p1_fall_committed = true
				fallen.player_y = -1.0
			else:
				fallen.p2_fall_committed = true
				fallen.player2_y = -1.0
			var before := _z(fallen, player)
			fallen.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
			_check(_z(fallen, player) > before, "committed fall is not held " + label)

			# 壁の幅の内側を走るプレイヤーはボーダーで止めない（壁そのものに当たる）。
			var inside := _fixture(provider)
			_pushes.clear()
			_set_player(inside, player, 9.0 * side, inside.wall_z - 0.7)
			inside.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
			_check(_pushes.is_empty() and _z(inside, player) > inside.wall_z - 0.7, "inside the wall width not held by border " + label)
	provider.free()
	return {"passed": failures.is_empty(), "checks": checks, "failures": failures.duplicate()}
