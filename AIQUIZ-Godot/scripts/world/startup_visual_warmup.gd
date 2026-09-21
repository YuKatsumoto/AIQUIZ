extends Node

signal step_completed(fraction: float)

## Isolated render-only rehearsal. Never starts a round, kills a real player,
## emits quiz signals, updates history, or uses the live gameplay world.
var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _report: Dictionary = {}

func _draw_frames(count: int = 3) -> void:
	for frame: int in range(count):
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		await get_tree().process_frame

func run() -> Dictionary:
	_viewport = SubViewport.new()
	_viewport.name = "StartupRehearsalViewport"
	_viewport.size = Vector2i(640, 360)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	GraphicsQuality.apply_text_viewport(_viewport, GameManager.graphics_quality)
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.position = Vector3(0, 3, 16)
	_camera.look_at(Vector3(0, 1, 0))
	_camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.8
	GraphicsQuality.apply_environment(environment, GameManager.graphics_quality)
	_camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.shadow_enabled = true
	_world.add_child(light)
	await _draw_frames()
	var state := QuizGameState.new(QuizManager.provider)
	state.num_players = 2
	state.p1_hat = QuizManager.game_state.p1_hat
	state.p2_hat = QuizManager.game_state.p2_hat
	var player := PlayerController.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(player)
	player.prepare_for_loading(state)
	await _draw_frames()
	step_completed.emit(0.15)
	# Frozen independent ragdolls exercise the genuine mesh/material builder.
	for is_p1: bool in [true, false]:
		var parts: Dictionary = player.p1_parts if is_p1 else player.p2_parts
		var rag: Dictionary = player._setup_ragdoll(parts, is_p1)
		rag.container.process_mode = Node.PROCESS_MODE_DISABLED
		for body: Variant in rag.rag.bodies.values():
			if body is RigidBody3D:
				body.freeze = true
			if body is CollisionObject3D:
				body.collision_layer = 0
				body.collision_mask = 0
		await _draw_frames()
		player._teardown_ragdoll(rag)
	var pieces := player.begin_death_render_prewarm(_camera)
	_report["death_pieces"] = pieces.get_child_count()
	var wipe: Control = load("res://ui/death_wipe.tscn").instantiate()
	_viewport.add_child(wipe)
	wipe.begin_render_prewarm(_viewport.world_3d, _camera)
	await _draw_frames()
	wipe.end_render_prewarm()
	_report["death_viewport"] = true
	step_completed.emit(0.4)
	pieces.queue_free()
	player.queue_free()
	await _draw_frames()
	for choice_count: int in [2, 4]:
		var wall: Node3D = load("res://scenes/quiz_wall.tscn").instantiate()
		_world.add_child(wall)
		var choices := PackedStringArray(["正解", "不正解"] if choice_count == 2 else ["1/2", "漢字", "カタカナ", "正解"])
		var quiz := QuizItem.create("次の問題の答えは？ １２３４５６７８９０", choices, 0, "予熱", "PREWARM")
		wall.set_quiz(quiz, choice_count)
		wall.set_is_boss(choice_count == 4)
		wall.set_gameplay_question(quiz.q, true)
		wall.set_preview_labels(quiz)
		await _draw_frames()
		wall.queue_free()
	_report["question_variants"] = 2
	step_completed.emit(0.6)
	var particles: Node3D = load("res://scripts/effects/particle_spawner.gd").new()
	_world.add_child(particles)
	particles.spawn_correct(Vector3.ZERO)
	await _draw_frames()
	particles.spawn_explosion(Vector3.ZERO)
	await _draw_frames()
	particles.spawn_ocean_splash(Vector3.ZERO)
	# Build the same impact visuals without scheduling gameplay cleanup timers
	# whose captured nodes could outlive this short rehearsal.
	var column: GPUParticles3D = particles._create_shark_water_column()
	particles.add_child(column)
	column.emitting = true
	var ring: MeshInstance3D = particles._create_shark_shock_ring()
	particles.add_child(ring)
	await _draw_frames()
	_report["particle_variants"] = 4
	step_completed.emit(0.8)
	var shark: Node3D = load("res://scenes/shark_swimmer.tscn").instantiate()
	shark.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(shark)
	shark.position = Vector3.ZERO
	shark.begin_ghost_portal_render_prewarm()
	var portals: Node3D = load("res://scripts/world/ghost_shark_ride_controller.gd").new()
	portals.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(portals)
	var portal_report: Dictionary = portals.begin_return_portal_render_prewarm(_camera)
	await _draw_frames(4)
	portals.end_return_portal_render_prewarm()
	shark.end_ghost_portal_render_prewarm()
	_report["portals"] = portal_report.get("portals", 0)
	_report["ready"] = int(_report.death_pieces) > 0 and int(_report.portals) == 2
	step_completed.emit(1.0)
	return _report
