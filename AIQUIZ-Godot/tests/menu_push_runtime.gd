extends Node
## Run from the live menu: add to root, then call_deferred("run").
const OUTPUT := "res://artifacts/menu_push/"
var checks: Dictionary = {}
var events: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var finished := false

func fixture() -> MenuWallBackgroundPreview:
	var p := MenuWallBackgroundPreview.new()
	p._preview_gs = QuizGameState.new()
	p._preview_gs.num_players = 2
	p._preview_gs.game_state = Constants.STATE_PLAYING
	p._preview_gs.p1_alive = true
	p._preview_gs.p2_alive = true
	p._p1_ai = MenuPreviewActorAIState.new()
	p._p2_ai = MenuPreviewActorAIState.new()
	p._preview_gs.player_x = -0.62
	p._preview_gs.player2_x = 0.62
	return p

func step(p: MenuWallBackgroundPreview, dt: float, velocity: Vector2) -> void:
	var gs := p._preview_gs
	var a := Vector2(gs.player_x, gs.player_z)
	var b := Vector2(gs.player2_x, gs.player2_z)
	gs.player_x += velocity.x * dt
	gs.player2_x += velocity.y * dt
	p._update_menu_push(dt, a, b)
	gs._resolve_two_player_body_collision(a, b)

func unit_cases() -> void:
	for fps: int in [30, 60, 120]:
		for mirror: float in [1.0, -1.0]:
			var p := fixture()
			var gs := p._preview_gs
			gs.player_x *= mirror
			gs.player2_x *= mirror
			step(p, 0.1, Vector2.ZERO)
			var start := gs.player2_x
			for i in fps:
				step(p, 1.0 / fps, Vector2(3.0 * mirror, 0.0))
			checks["held_%s_%s" % [fps, mirror]] = (gs.player2_x - start) * mirror > 1.0 and absf(gs.player2_x - gs.player_x) >= 1.239
			gs.local_push.reset()
			gs.player_x = -0.62 * mirror
			gs.player2_x = 0.62 * mirror
			for i in fps * 3:
				step(p, 1.0 / fps, Vector2(3.0, -3.0) * mirror)
			var hits := 0
			for event: Dictionary in gs.local_push.events:
				if event.kind in ["hit", "clash"]: hits += 1
			checks["ai_strike_%s_%s" % [fps, mirror]] = hits > 0
			p.free()
	var p := fixture()
	var gs := p._preview_gs
	gs.player2_z = 3.0
	step(p, 0.1, Vector2(3, -3))
	checks.depth_separation = not gs.local_push.contact and is_equal_approx(gs.player_x, -0.32)
	gs.player2_z = 0.0
	gs.player2_y = QuizGameState.PLAYER_BODY_HEIGHT + 0.1
	step(p, 0.1, Vector2(3, -3))
	checks.jump_clearance = not gs.local_push.contact
	gs.player2_y = 0.0
	gs.p2_alive = false
	step(p, 0.1, Vector2(3, 0))
	checks.dead_no_push = not gs.local_push.contact
	gs.p2_alive = true
	p._p2_ai.pending_accident = p.PENDING_ACCIDENT_OCEAN
	step(p, 0.1, Vector2(3, 0))
	checks.accident_no_push = not gs.local_push.contact
	p._reset_menu_push()
	checks.reset_clears_pose = not gs.local_push.presentation(1).active and gs.local_push.inputs.is_empty()
	p.free()

func run() -> void:
	unit_cases()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	while SceneTransition.is_transitioning():
		await get_tree().process_frame
	var p: MenuWallBackgroundPreview = get_tree().current_scene._menu_wall_preview
	p.set_process(false)
	p.sync_menu_player_count(2)
	var gs := p._preview_gs
	p._reset_menu_push()
	p._menu_intro_active = false
	p._saw_next_trial = INF
	p._saw_accident_owner = 0
	p._menu_saw.reset()
	p._menu_saw.local_z = 12.0
	p._preview_saw._preview_elapsed = 30.0
	for wall in p._preview_walls:
		wall.position.z -= 100.0
	gs.player_x = -1.1
	gs.player2_x = 1.1
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_saw_killed = false
	gs.p2_saw_killed = false
	gs.p1_waiting_for_shark = false
	gs.p2_waiting_for_shark = false
	for bundle in [p._p1_ai, p._p2_ai]:
		bundle.ai_state = p.AI_STATE_NORMAL
		bundle.next_action_t = INF
		bundle.lane_shift_active = true
		bundle.lane_shift_speed = 3.0
		bundle.depth_shift_active = false
		p._clear_pending_accident(bundle)
		p._clear_learning_commit(bundle)
	p._stop_ai_emote_if_needed(p._p1_ai, true)
	p._stop_ai_emote_if_needed(p._p2_ai, false)
	p._p1_ai.target_x = 3.0
	p._p2_ai.target_x = -3.0
	gs.local_push_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var captured := {}
	var min_gap := INF
	for frame in 180:
		p._process(1.0 / 60.0)
		if frame % 30 == 0:
			frames.append({"time": gs.local_push.time, "x": [gs.player_x, gs.player2_x], "z": [gs.player_local_z, gs.player2_local_z], "target": [p._p1_ai.target_x, p._p2_ai.target_x], "valid": [p._menu_push_actor_valid(p._p1_ai, true), p._menu_push_actor_valid(p._p2_ai, false)]})
		min_gap = minf(min_gap, absf(gs.player2_x - gs.player_x))
		await RenderingServer.frame_post_draw
		var phase: String = gs.get_local_push_pose(1).get("phase", "run")
		if phase in ["brace", "strike", "recoil", "clash"] and not captured.has(phase):
			get_viewport().get_texture().get_image().save_png(OUTPUT + phase + ".png")
			captured[phase] = frame
		await get_tree().process_frame
	checks.runtime_body_gap = min_gap >= 1.239
	checks.runtime_contact = captured.has("brace")
	checks.runtime_shoulder = captured.has("strike") or captured.has("recoil") or captured.has("clash")
	p.enter_customize_mode()
	checks.customize_reset = not gs.local_push.presentation(1).active
	p.exit_customize_mode()
	p.sync_menu_player_count(1)
	checks.single_player_reset = not gs.local_push.contact and gs.local_push.held == [0, 0]
	var passed := true
	for value in checks.values(): passed = passed and value
	var report := {"passed": passed, "checks": checks, "captures": captured, "events": events, "frames": frames}
	FileAccess.open(OUTPUT + "acceptance.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MENU_PUSH_ACCEPTANCE " + JSON.stringify(report))
	finished = true
	get_tree().reload_current_scene()
