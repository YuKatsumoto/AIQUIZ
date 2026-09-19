extends Node
## Attach to root from the editor game helper, then defer run().
## All interaction below uses actual InputEventKey events and the live GameWorld loop.
## Door/edge fixtures only place the pair before an interaction; they never resolve it.
const OUTPUT := "res://artifacts/local_push_heavy/runtime/"
var phase := "idle"
var finished := false
var failures: Array[String] = []
var checks: Array[String] = []
var events: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var world: Node3D
var gs: QuizGameState
var recording := false
var frame_number := 0
var record_name := "sequence"
var old_source := ""
var previous_fps := 0
var captured_images: Array[Dictionary] = []

func _flush_captures() -> void:
	# Keep PNG compression/disk I/O outside the measured interaction frames.
	for capture: Dictionary in captured_images:
		capture.image.save_png(capture.path)
	captured_images.clear()

func run_visual_test() -> void:
	name = "LocalPushVisual"
	process_mode = Node.PROCESS_MODE_ALWAYS
	gs = QuizManager.game_state
	old_source = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	previous_fps = Engine.max_fps
	Engine.max_fps = 60
	gs.local_push_event.connect(_on_event)
	RenderingServer.frame_post_draw.connect(_record_frame)
	if await _start(Constants.MODE_ENDLESS):
		await _wait(2.0)
		await _shoulder_sequence("visual60")
	_release_all()
	recording = false
	RenderingServer.frame_post_draw.disconnect(_record_frame)
	gs.local_push_event.disconnect(_on_event)
	Engine.max_fps = previous_fps
	QuizManager.provider.llm_mode = old_source
	_flush_captures()
	var file := FileAccess.open(OUTPUT + "visual_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "frames": frames, "events": events}, "\t"))
	finished = true
	phase = "finished"

func status() -> Dictionary:
	var stages := {}
	for frame: Dictionary in frames:
		var key: String = str(frame.clip) + "/" + str(frame.p1.get("phase", "run"))
		if not stages.has(key):
			stages[key] = {"frame": frame.frame, "time": frame.time, "bursts": frame.active_bursts}
	return {"phase": phase, "finished": finished, "checks": checks.size(), "failures": failures, "stages": stages}

func run() -> void:
	name = "LocalPushRuntime"
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	gs = QuizManager.game_state
	old_source = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	previous_fps = Engine.max_fps
	Engine.max_fps = 60
	gs.local_push_event.connect(_on_event)
	RenderingServer.frame_post_draw.connect(_record_frame)
	if await _start(Constants.MODE_TEN, true):
		await _shoulder_sequence("ten")
		await _input_runtime_cases()
		await _doors_and_goal()
	if await _start(Constants.MODE_ENDLESS):
		await _shoulder_sequence("endless")
		await _edge_case()
	if await _start(Constants.MODE_TUTORIAL):
		await _tutorial()
	_release_all()
	recording = false
	Engine.max_fps = previous_fps
	QuizManager.provider.llm_mode = old_source
	RenderingServer.frame_post_draw.disconnect(_record_frame)
	gs.local_push_event.disconnect(_on_event)
	_flush_captures()
	finished = true
	phase = "finished"
	var report := {"passed": failures.is_empty(), "renderer": RenderingServer.get_current_rendering_method(), "checks": checks,
		"failures": failures, "events": events, "frames": frames, "normal_menu_start": true}
	var file := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LOCAL_PUSH_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures, "frames": frames.size()}))

func _on_event(event: Dictionary) -> void:
	var copy := event.duplicate(true)
	copy["phase"] = phase
	events.append(copy)

func _key(key: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _release_all() -> void:
	for key: Key in [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_CTRL, KEY_W, KEY_S, KEY_UP, KEY_DOWN]:
		_key(key, false)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error("LOCAL_PUSH_RUNTIME " + label)

func _start(mode: String, from_menu := false) -> bool:
	phase = "start_" + mode
	_release_all()
	get_tree().paused = false
	gs.num_players = 2
	gs.mode = mode
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	world = null
	if from_menu:
		var menu := get_tree().current_scene
		menu._update_ui()
		menu._go_to_game(true)
	else:
		if mode == Constants.MODE_TUTORIAL:
			gs.start_tutorial(GameManager.TUTORIAL_COURSE_LOCAL_2P)
		else:
			gs.start_game()
		GameManager.start_game()
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.name == "GameWorld" and not SceneTransition.is_transitioning() and not scene.is_start_presentation_locked() and not scene.is_preload_construction_locked() and scene._barrier_spawned_for_session and not scene._barrier_dropping:
			world = scene
			break
	_check(world != null, phase + " normal arrival completed")
	if world == null:
		return false
	_key(KEY_ENTER, true)
	await get_tree().process_frame
	_key(KEY_ENTER, false)
	deadline = Time.get_ticks_msec() + 18000
	while gs.game_state != Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(gs.game_state == Constants.STATE_PLAYING, phase + " countdown completed")
	await _wait(0.6)
	return gs.game_state == Constants.STATE_PLAYING

func _count(kind: String, since: int = 0, player := 0) -> int:
	var result := 0
	for i in range(since, events.size()):
		if events[i].kind == kind and (player == 0 or events[i].get("player", 0) == player):
			result += 1
	return result

func _inward() -> void:
	_key(KEY_D if gs.player_x > gs.player2_x else KEY_A, true)
	_key(KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT, true)

func _repress(player: int) -> void:
	var key: Key = (KEY_D if gs.player_x > gs.player2_x else KEY_A) if player == 1 else (KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT)
	_key(key, false)
	_key(key, true)

func _begin_record(label: String) -> void:
	record_name = label
	frame_number = 0
	recording = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + label))

func _shoulder_sequence(label: String) -> void:
	phase = label + "_shoulder_sequence"
	var initial := events.size()
	_begin_record(label)
	_inward()
	await _wait(0.55)
	_check(gs.local_push.contact and gs.local_push.stalemate >= 0.1, label + " live contact and brace")
	_check(_count("hit", initial) == 0, label + " hold creates no attack")
	_repress(1)
	await _wait(0.27)
	_check(_count("hit", initial, 1) == 1, label + " same frame release/down hits once")
	await _wait(0.3)
	_repress(2)
	await _wait(0.27)
	_check(_count("hit", initial, 2) == 1, label + " P2 shoulder hits once")
	await _wait(0.35)
	var before_clash := events.size()
	_repress(1)
	_repress(2)
	await _wait(0.25)
	_check(_count("clash", before_clash) == 1 and _count("hit", before_clash) == 0, label + " actual simultaneous keys clash once")
	var rapid_start := events.size()
	for repeat in range(4):
		_repress(1)
		_repress(2)
		await _wait(0.25)
	_check(_count("clash", rapid_start) == 4 and _count("hit", rapid_start) == 0, label + " four consecutive 0.25 second clashes")
	_release_all()
	_key(KEY_A if gs.player_x > gs.player2_x else KEY_D, true)
	_key(KEY_RIGHT if gs.player_x > gs.player2_x else KEY_LEFT, true)
	await _wait(0.14)
	_release_all()
	await _wait(0.2)
	_check(gs.get_local_push_pose(1).get("phase", "run") == "run", label + " contact release restores pose")
	_check(gs.get_local_push_pose(2).get("phase", "run") == "run", label + " P2 contact release restores pose")
	_check(world.particle_spawner.local_push_effects.slots.all(func(s: Dictionary) -> bool: return not s.root.visible), label + " all pooled effects expire after separation")
	recording = false
	_check(world.particle_spawner.local_push_effects.slots.size() == 4, "four reusable VFX slots")
	var lifetime_ok := true
	var sampled_hits := 0
	for event: Dictionary in events:
		if event.kind != "hit" or event.phase != label + "_shoulder_sequence":
			continue
		for frame: Dictionary in frames:
			if frame.clip == label and frame.time >= event.time and frame.time < event.time + 0.12:
				sampled_hits += 1
				lifetime_ok = lifetime_ok and frame.active_bursts >= 1
	_check(lifetime_ok and sampled_hits >= 2, label + " impact stays visible through first 0.12 seconds")

func _input_runtime_cases() -> void:
	phase = "jump_pause_focus"
	_inward()
	await _wait(0.55)
	var initial := events.size()
	_repress(1)
	await _wait(0.018)
	_key(KEY_SPACE, true)
	await _wait(0.035)
	_key(KEY_SPACE, false)
	await _wait(0.04)
	_check(_count("hit", initial) == 0, "jump cancels pending shoulder")
	_check(gs.player_y > 0.0, "jump still receives ordinary impulse")
	_repress(2)
	await _wait(0.13)
	_check(_count("hit", initial, 2) == 1, "live airborne opponent receives shoulder")
	await _wait(0.75)
	_check(absf(gs.player_x - gs.player2_x) >= 1.239, "jump landing restores body separation after possible vault")
	initial = events.size()
	_repress(1)
	await _wait(0.016)
	world._toggle_pause()
	await _wait(0.25)
	world._toggle_pause()
	await _wait(0.35)
	_check(_count("hit", initial) == 0, "pause discards pending strike; held resume no repeat")
	_repress(1)
	await _wait(0.016)
	world.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait(0.12)
	world.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _wait(0.3)
	_check(_count("hit", initial) == 0, "focus loss discards pending strike")
	_release_all()

func _place_at_wall(distance: float, center: float) -> void:
	_release_all()
	gs.local_push.reset()
	gs.world_scroll_z = gs.wall_z - distance
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	gs.player_x = center + 0.62
	gs.player2_x = center - 0.62
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0

func _doors_and_goal() -> void:
	phase = "shared_correct_doors"
	for step in range(10):
		if gs.game_state != Constants.STATE_PLAYING or gs.current_quiz == null:
			break
		var index := gs.current_wall_index
		var choice_count := gs.num_choices
		var answer := gs.current_quiz.a
		var center: float = gs.tuning.door4_xs[answer] if gs.num_choices == 4 else (gs.tuning.left_door_x if answer == 0 else gs.tuning.right_door_x)
		_place_at_wall(5.0, center)
		_inward()
		await _wait(0.2)
		if gs.num_choices == 4 or index == 0:
			_begin_record("door%d" % index)
			_repress(1)
			_repress(2)
		var deadline := Time.get_ticks_msec() + 10000
		while gs.current_wall_index == index and gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		recording = false
		_check(gs.current_wall_index == index + 1 and gs.p1_alive and gs.p2_alive, "both enter correct door %d choices%d" % [index, choice_count])
		_release_all()
		await _wait(0.12)
	_check(gs.game_state == Constants.STATE_GOAL_RACE, "ten correct answers reach final goal interval")
	if gs.game_state == Constants.STATE_GOAL_RACE:
		await _shoulder_sequence("goal")

func _edge_case() -> void:
	phase = "edge_fall_death_wipe"
	_place_at_wall(45.0, -11.30)
	_begin_record("edge")
	var initial := events.size()
	_inward()
	await _wait(0.22)
	_repress(1)
	await _wait(0.25)
	_release_all()
	_check(_count("hit", initial, 1) == 1, "edge shoulder lands")
	_check(gs.p2_fall_committed, "shoulder commits ocean fall")
	_check(gs.get_local_push_pose(2).is_empty(), "fall pose immediately cleared")
	await _wait(2.2)
	_check(gs.p2_waiting_for_shark or not gs.p2_alive, "fall reaches ocean/death flow")
	var wipe: Node = world.get_node_or_null("DeathWipeLayer/DeathWipe")
	_check(wipe != null and wipe.visible and wipe._active and wipe._dead_player == 2, "death wipe visibly follows pushed P2")
	await _wait(2.0)
	recording = false
	_check(gs.p1_alive, "survivor continues after edge push")

func _tutorial() -> void:
	phase = "tutorial_push"
	# Complete the original left/right lesson with real keys.
	_release_all()
	await _wait(0.25)
	_key(KEY_A, true)
	_key(KEY_RIGHT, true)
	await _wait(0.12)
	_release_all()
	_key(KEY_D, true)
	_key(KEY_LEFT, true)
	await _wait(0.12)
	_release_all()
	await _wait(0.9)
	_check(gs.tutorial_flow.current_step_id() == "duo_push", "live tutorial enters push lesson after movement")
	await _wait(0.3)
	_begin_record("tutorial")
	_inward()
	await _wait(0.55)
	_repress(1)
	await _wait(0.28)
	await _wait(0.2)
	_repress(2)
	await _wait(0.28)
	_release_all()
	await _wait(1.1)
	_check(gs.tutorial_flow.current_step_id() == "duo_air", "actual sequential shoulder hits complete tutorial lesson")
	recording = false

func _record_frame() -> void:
	if not recording or not is_instance_valid(world):
		return
	var viewport_image := get_viewport().get_texture().get_image()
	viewport_image.resize(960, roundi(960.0 * viewport_image.get_height() / viewport_image.get_width()), Image.INTERPOLATE_BILINEAR)
	captured_images.append({"image": viewport_image, "path": OUTPUT + record_name + "/%04d.png" % frame_number})
	var p1 := gs.get_local_push_pose(1)
	var p2 := gs.get_local_push_pose(2)
	frames.append({"clip": record_name, "frame": frame_number, "time": gs.local_push.time,
		"x1": gs.player_x, "x2": gs.player2_x, "y1": gs.player_y, "y2": gs.player2_y,
		"p1": p1, "p2": p2, "state": gs.game_state,
		"pose_restore_count": world.player_node._push_pose_restore.size(),
		"effects": world.particle_spawner.local_push_effects.slots.filter(func(s: Dictionary) -> bool: return s.root.visible).map(func(s: Dictionary) -> Dictionary: return {"age": s.age, "flash": s.flash.visible, "streaks": s.pieces[0].visible, "dust": s.dust_pieces.filter(func(p: MeshInstance3D) -> bool: return p.visible).size()}),
		"active_bursts": world.particle_spawner.local_push_effects.slots.filter(func(s: Dictionary) -> bool: return s.root.visible).size()})
	frame_number += 1
