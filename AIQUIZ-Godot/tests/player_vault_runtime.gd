extends "res://tests/local_push_runtime.gd"
## Run on the live game helper. Fixtures position players; real key input drives each jump.
const VAULT_OUTPUT := "res://artifacts/player_vault/"
var samples: Array[Dictionary] = []
var vault_captures: Array[Dictionary] = []

func run() -> void:
	name = "PlayerVaultRuntime"
	gs = QuizManager.game_state
	old_source = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	previous_fps = Engine.max_fps
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VAULT_OUTPUT))
	if await _start(Constants.MODE_ENDLESS):
		for player in [1, 2]:
			for direction in [1, -1]:
				await _vault_case(player, direction)
		await _ground_case(false)
		await _ground_case(true)
	_release_all()
	Engine.max_fps = previous_fps
	QuizManager.provider.llm_mode = old_source
	for capture: Dictionary in vault_captures:
		capture.image.save_png(capture.path)
	vault_captures.clear()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"renderer": RenderingServer.get_current_rendering_method(), "samples": samples}
	FileAccess.open(VAULT_OUTPUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	finished = true
	phase = "finished"
	print("PLAYER_VAULT_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}))

func _fixture(player: int, direction: int) -> void:
	_release_all()
	gs.local_push.reset()
	gs.player_x = -0.62 * direction if player == 1 else 0.62 * direction
	gs.player2_x = 0.62 * direction if player == 1 else -0.62 * direction
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	gs.p1_external_velocity = Vector2.ZERO
	gs.p2_external_velocity = Vector2.ZERO
	gs.p1_hat = 0
	gs.p2_hat = 0
	gs._active_wall_speed = 0.0
	gs.wall_z = gs.world_scroll_z + 100.0

func _capture(label: String) -> void:
	vault_captures.append({"path": VAULT_OUTPUT + label + ".png", "image": get_viewport().get_texture().get_image()})

func _vault_case(player: int, direction: int) -> void:
	phase = "p%d_direction%d" % [player, direction]
	_fixture(player, direction)
	await _wait(0.1)
	_capture(phase + "_before")
	var move_key: Key = (KEY_A if direction > 0 else KEY_D) if player == 1 else (KEY_LEFT if direction > 0 else KEY_RIGHT)
	var jump_key: Key = KEY_SPACE if player == 1 else KEY_CTRL
	_key(move_key, true)
	_key(jump_key, true)
	var elapsed := 0.0
	var crossed := false
	var max_y := 0.0
	var released_move := false
	while elapsed < 1.4:
		await RenderingServer.frame_post_draw
		elapsed += get_process_delta_time()
		if elapsed >= 0.08:
			_key(jump_key, false)
		var dx := (gs.player_x - gs.player2_x) if player == 1 else (gs.player2_x - gs.player_x)
		var height := gs.player_y if player == 1 else gs.player2_y
		max_y = maxf(max_y, height)
		samples.append({"case": phase, "time": elapsed, "p1": [gs.player_x, gs.player_y], "p2": [gs.player2_x, gs.player2_y], "contact": gs.local_push.contact})
		if dx * direction >= 0.0 and not crossed:
			crossed = true
			_check(height >= gs.PLAYER_BODY_HEIGHT, phase + " crosses above full body height")
			_check(not gs.local_push.contact, phase + " no push contact above opponent")
			_capture(phase + "_above")
		if dx * direction > 1.5 and not released_move:
			released_move = true
			_key(move_key, false)
	_check(crossed and max_y > gs.PLAYER_BODY_HEIGHT, phase + " jumps across opponent")
	_check(gs.player_y == 0.0 and gs.player2_y == 0.0, phase + " lands on floor")
	_check((gs.player_x - gs.player2_x) * direction * (1 if player == 1 else -1) > 1.24, phase + " landing retains swapped sides")
	_capture(phase + "_landed")
	# Move back into contact from the new side and exercise the normal shoulder input.
	_key(KEY_D if gs.player_x > gs.player2_x else KEY_A, true)
	_key(KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT, true)
	await _wait(0.3)
	_check(gs.local_push.contact, phase + " ground contact resumes after crossing")
	var hit_count := 0
	var listener := func(event: Dictionary):
		if event.kind == "hit":
			events.append(event.duplicate())
	gs.local_push_event.connect(listener)
	hit_count = events.size()
	_repress(player)
	await _wait(0.2)
	_check(events.size() == hit_count + 1, phase + " shoulder works from swapped side")
	gs.local_push_event.disconnect(listener)
	_release_all()

func _ground_case(both_jump: bool) -> void:
	phase = "simultaneous_jump" if both_jump else "ground_block"
	_fixture(1, 1)
	_key(KEY_A, true)
	_key(KEY_RIGHT, true)
	if both_jump:
		_key(KEY_SPACE, true)
		_key(KEY_CTRL, true)
	await _wait(0.06)
	_key(KEY_SPACE, false)
	_key(KEY_CTRL, false)
	await _wait(1.2)
	_check(gs.player_x < gs.player2_x and gs.player2_x - gs.player_x >= 1.239, phase + " bodies cannot pass at equal height")
	_release_all()
