extends SceneTree

const Duel = preload("res://scripts/core/local_push_duel.gd")
var failures: Array[String] = []
var checks := 0
var metrics: Array[Dictionary] = []

func _initialize() -> void:
	await process_frame
	for fps: int in [30, 60, 120]:
		for mirror: float in [1.0, -1.0]:
			for attacker: int in [1, 2]:
				_hit_case(fps, mirror, attacker)
			_clash_case(fps, mirror)
		_input_cases(fps)
		_cooldown_boundary_cases(fps)
		_physics_cases(fps)
	_integration_cases()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "metrics": metrics}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/local_push"))
	var file := FileAccess.open("res://artifacts/local_push/unit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LOCAL_PUSH_UNIT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _new(mirror := 1.0):
	var d = Duel.new()
	d._x = Vector2(-0.62, 0.62) * mirror
	d.queue_key(1, int(mirror), true)
	d.queue_key(2, -int(mirror), true)
	return d

func _run(d, seconds: float, fps := 60, axes := Vector2.ZERO, ground: Array = [true, true], valid: Array = [true, true], z := 0.0) -> void:
	var remaining := seconds
	while remaining > 0.00000001:
		var dt := minf(remaining, 1.0 / fps)
		d.advance(dt, d._x, z, valid, ground, axes, 7.6)
		remaining -= dt

func _count(d, kind: String) -> int:
	var count := 0
	for event: Dictionary in d.events:
		if event.kind == kind:
			count += 1
	return count

func _repress(d, player: int, direction: int, offset := 0.0) -> void:
	d.queue_key(player, direction, false, offset)
	d.queue_key(player, direction, true, offset)

func _hit_case(fps: int, mirror: float, attacker: int) -> void:
	var d = _new(mirror)
	var inward := Vector2(mirror, -mirror)
	_run(d, 1.0, fps, inward)
	_check(_count(d, "hit") == 0 and _count(d, "contact") == 1, "hold never attacks %s" % str([fps, mirror, attacker]))
	_check(d._x.is_equal_approx(Vector2(-0.62, 0.62) * mirror), "stalemate has no drift")
	var direction := int(mirror) if attacker == 1 else -int(mirror)
	_repress(d, attacker, direction)
	_run(d, 0.059, fps)
	_check(d.presentation(attacker).phase == "windup" and _count(d, "hit") == 0, "windup before 0.06")
	_run(d, 0.001, fps)
	_check(_count(d, "hit") == 1 and d.presentation(attacker).phase == "strike", "hit synchronized at 0.06")
	var target := 2 - attacker
	var before: float = d._x[target]
	_run(d, 0.12, fps)
	var distance: float = (d._x[target] - before) * direction
	_check(absf(distance - 0.52) < 0.00001, "0.52 displacement %s" % str([fps, mirror, attacker]))
	metrics.append({"fps": fps, "mirror": mirror, "attacker": attacker, "distance": distance, "hits": _count(d, "hit")})
	_run(d, 0.15, fps)
	_check(d.presentation(attacker).phase == "run" and d.presentation(3 - attacker).phase == "run", "both recover after separation")

func _clash_case(fps: int, mirror: float) -> void:
	for gap: float in [0.0, 0.049, 0.05]:
		for first: int in [1, 2]:
			var d = _new(mirror)
			_run(d, 0.2, fps, Vector2(mirror, -mirror))
			_repress(d, first, int(mirror) if first == 1 else -int(mirror))
			_repress(d, 3 - first, -int(mirror) if first == 1 else int(mirror), gap)
			_run(d, 0.2, fps, Vector2(mirror, -mirror))
			_check(_count(d, "clash") == 1 and _count(d, "hit") == 0, "symmetric clash %s" % str([fps, mirror, gap, first]))
			_check(d._x.is_equal_approx(Vector2(-0.62, 0.62) * mirror), "clash no knockback")

func _input_cases(fps: int) -> void:
	var rapid = _new()
	_run(rapid, 0.2, fps, Vector2(1, -1))
	for edge in range(29):
		_repress(rapid, 1, 1, edge * 0.04)
		_repress(rapid, 2, -1, edge * 0.04)
	_run(rapid, 1.2, fps, Vector2(1, -1))
	_check(_count(rapid, "clash") == 5 and _count(rapid, "hit") == 0, "rapid edges respect 0.24 interval at %dfps" % fps)
	var last_clash := -1.0
	for event: Dictionary in rapid.events:
		if event.kind == "clash":
			if last_clash >= 0.0:
				_check(absf(float(event.time) - last_clash - 0.24) < 0.00001, "rapid accepted strikes are 0.24 seconds apart")
			last_clash = event.time
	var late = _new()
	_run(late, 0.2, fps, Vector2(1, -1))
	_repress(late, 1, 1)
	_repress(late, 2, -1, 0.0501)
	_run(late, 0.061, fps, Vector2(1, -1))
	_check(_count(late, "clash") == 0 and _count(late, "hit") == 1, "outside 0.05 window does not clash")
	var wrong = _new()
	_run(wrong, 0.2, fps, Vector2(1, -1))
	wrong.queue_key(1, 1, false)
	wrong.queue_key(1, -1, true)
	_run(wrong, 0.1, fps)
	_check(_count(wrong, "hit") == 0, "reverse key cannot strike")
	var d = _new()
	_run(d, 0.09, fps, Vector2(1, -1))
	_repress(d, 1, 1)
	_run(d, 0.1, fps, Vector2(1, -1))
	_check(_count(d, "hit") == 0, "must first brace 0.10")
	d.queue_key(1, 1, true, 0.0, true)
	d.queue_key(1, 1, true)
	_run(d, 0.1, fps, Vector2(1, -1))
	_check(_count(d, "hit") == 0, "echo and duplicate keydown ignored")
	_repress(d, 1, 1)
	d.queue_key(1, -1, true)
	_run(d, 0.1, fps)
	_check(_count(d, "hit") == 0, "opposite simultaneous keys cancel windup")
	for gap: float in [0.19, 0.21]:
		d = _new()
		_run(d, 0.2, fps, Vector2(1, -1))
		d.queue_key(1, 1, false)
		_run(d, gap, fps)
		d.queue_key(1, 1, true)
		_run(d, 0.07, fps)
		_check(_count(d, "hit") == (1 if gap < 0.2 else 0), "grace window %.2f" % gap)
	d = _new()
	_run(d, 0.2, fps, Vector2(1, -1))
	_repress(d, 1, 1)
	_run(d, 0.03, fps)
	_run(d, 0.08, fps, Vector2.ZERO, [false, true])
	_check(_count(d, "hit") == 0 and d.cooldown_until[0] > d.time, "jump cancels and keeps cooldown")
	_repress(d, 1, 1)
	_run(d, 0.4, fps, Vector2(1, -1))
	_check(_count(d, "hit") == 0, "cooldown input not buffered")
	_repress(d, 1, 1)
	_run(d, 0.061, fps)
	_check(_count(d, "hit") == 1, "new edge after cooldown succeeds")
	d = _new()
	_run(d, 0.2, fps, Vector2(1, -1))
	_repress(d, 1, 1)
	_run(d, 0.02, fps)
	d.suspend([1, 2])
	_run(d, 0.5, fps, Vector2(1, -1))
	_check(_count(d, "hit") == 0, "pause clears windup and held resume does not attack")
	_repress(d, 1, 1)
	_run(d, 0.07, fps, Vector2.ZERO, [true, false])
	_check(_count(d, "hit") == 1, "airborne target can be struck")
	d = _new()
	_run(d, 0.2, fps, Vector2(1, -1))
	_repress(d, 1, 1)
	_run(d, 0.03, fps)
	d._x.y += 2.0
	_run(d, 0.1, fps)
	_check(_count(d, "hit") == 0, "lost contact cancels")
	d = _new()
	_run(d, 0.2, fps, Vector2(1, -1))
	_repress(d, 1, 1)
	_run(d, 0.03, fps)
	_run(d, 0.1, fps, Vector2.ZERO, [true, true], [false, true])
	_check(_count(d, "hit") == 0 and d.presentation(1).is_empty(), "fall or death cancels and removes pose")

func _cooldown_boundary_cases(fps: int) -> void:
	for mirror: float in [1.0, -1.0]:
		for gap: float in [0.2399, 0.24]:
			var d = _new(mirror)
			var inward := Vector2(mirror, -mirror)
			_run(d, 0.2, fps, inward)
			for player in [1, 2]:
				_repress(d, player, int(mirror) if player == 1 else -int(mirror))
			_run(d, gap, fps, inward)
			for player in [1, 2]:
				_repress(d, player, int(mirror) if player == 1 else -int(mirror))
			_run(d, 0.07, fps, inward)
			_check(_count(d, "clash") == (1 if gap < 0.24 else 2), "cooldown boundary %s" % str([fps, mirror, gap]))
		var d = _new(mirror)
		_run(d, 0.2, fps, Vector2(mirror, -mirror))
		_repress(d, 1, int(mirror))
		_run(d, 0.059, fps)
		_check(d.presentation(1).shoulder < -0.9 and d.presentation(1).hip_drop > 0.05, "windup pulls shoulder and lowers hips")
		_run(d, 0.001, fps)
		_check(absf(d.presentation(1).lean - 20.0 * mirror) < 0.00001, "20 degree strike at impact")
		_check(absf(d.presentation(2).lean - 16.0 * mirror) < 0.00001, "16 degree recoil at impact")
		_run(d, 0.20, fps)
		for player in [1, 2]:
			var pose: Dictionary = d.presentation(player)
			_check(pose.phase == "run" and is_zero_approx(pose.shoulder) and is_zero_approx(pose.hip_drop), "separation restores shoulder and hip offsets")

func _physics_cases(fps: int) -> void:
	for mirror: float in [1.0, -1.0]:
		var d = _new(mirror)
		_run(d, 1.0, fps, Vector2(mirror, 0))
		_check(absf(d._x.y - 0.62 * mirror - 1.35 * mirror) < 0.00001, "held push cap 1.35")
		d = _new(mirror)
		_run(d, 0.4, fps, Vector2(mirror, -mirror), [false, false])
		_check((d._x.y - d._x.x) * mirror >= 1.23999, "airborne players cannot cross")
		var result: Vector2 = d.resolve(Vector2(2, -2) * mirror, 0.4)
		_check((result.y - result.x) * mirror > 1.17, "swept order retained with Z separation")
		_check(d.resolve(Vector2(2, -2), 2.0) == Vector2(2, -2), "separate Z lanes do not collide")
	# Input suppression integrates only the covered part of a render frame.
	var d = _new()
	d.shove_start[1] = 0.0
	d.shove_direction[1] = 1.0
	d._x = Vector2(-5, 5)
	_run(d, 0.12, fps, Vector2(0, -1))
	_check(absf(d._x.y - (5.0 + 0.52 - 7.6 * 0.12 * 0.25)) < 0.00001, "25 percent steering during knockback")
	var before: float = d._x.y
	_run(d, 0.1, fps, Vector2(0, -1))
	_check(absf(d._x.y - before + 0.76) < 0.00001, "steering immediately restored")

func _integration_cases() -> void:
	var script: GDScript = load("res://scripts/core/game_state.gd")
	var gs = script.new()
	gs.num_players = 2
	gs.game_state = Constants.STATE_PLAYING
	for mode: String in [Constants.MODE_TEN, Constants.MODE_ENDLESS, Constants.MODE_TUTORIAL, Constants.MODE_COOP]:
		gs.mode = mode
		_check(gs.uses_local_push() == (mode != Constants.MODE_COOP), "mode gate " + mode)
	gs.mode = Constants.MODE_TEN
	gs.num_players = 1
	_check(not gs.uses_local_push(), "solo excluded")
	gs.num_players = 2
	gs.is_replay = true
	_check(not gs.uses_local_push(), "replay excluded")
	gs.is_replay = false
	gs.local_push_transport_enabled = false
	_check(not gs.uses_local_push(), "online excluded")
	gs.local_push_transport_enabled = true
	gs.game_state = Constants.STATE_GOAL_RACE
	_check(gs.uses_local_push(), "goal included")
	gs.player_x = 0.62
	gs.player2_x = -0.62
	gs.player_z = 3.0
	gs.player2_z = 3.2
	gs._active_wall_speed = 4.0
	gs.goal_z = 1000.0
	gs.player2_y = 1.2
	gs._update_goal_race(0.1, Vector2(-1, 1), Vector2(1, -1), false, false)
	_check(gs.player_x > gs.player2_x, "real goal collision retains order in air")
	var forward_step: float = gs.tuning.player_speed * 0.1
	_check(absf(gs.player_z - (3.4 + forward_step)) < 0.00001 and absf(gs.player2_z - (3.6 - forward_step)) < 0.00001, "collision preserves auto advance and forward/back input")
	_check(gs.camera_shake == 0.0 and gs.p1_external_velocity == Vector2.ZERO and gs.p2_external_velocity == Vector2.ZERO, "push leaves camera and shark impulse storage alone")
	gs.local_push.pending = [gs.local_push.time + 0.06, -1.0]
	gs.mode = Constants.MODE_COOP
	gs.game_state = Constants.STATE_MENU
	gs.update(0.01)
	_check(gs.local_push.pending == [-1.0, -1.0] and gs.local_push.inputs.is_empty(), "mode exit resets dedicated state")
	var flow = load("res://scripts/core/tutorial/duo_tutorial_flow.gd").new()
	flow.start()
	flow.advance_step()
	flow.awaiting_neutral_input = false
	_check(flow.current_step_id() == "duo_push", "push lesson follows lateral lesson")
	flow.on_local_push_event({"kind": "hit", "player": 1})
	_check(not flow._push_task_done(1, "push"), "tutorial requires brace first")
	flow.on_local_push_event({"kind": "stalemate"})
	flow.on_local_push_event({"kind": "hit", "player": 2})
	_check(not flow._push_task_done(2, "push"), "tutorial P1 before P2")
	flow.on_local_push_event({"kind": "clash", "player": 0})
	_check(not flow._push_task_done(1, "push"), "clash does not count")
	flow.on_local_push_event({"kind": "hit", "player": 1})
	flow.on_local_push_event({"kind": "hit", "player": 2})
	_check(flow.all_tasks_complete(), "both sequential hits complete lesson")
