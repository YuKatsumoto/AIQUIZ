extends Node

const OUT := "res://artifacts/contact_speed_fix/"
var gs: QuizGameState
var world: Node3D
var helper: Node
var failures: Array[String] = []
var checks := 0
var samples: Array = []
var events: Array = []
var video_frame := 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "movement_frames"))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	gs.skip_start_helicopter_arrival = true
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	world.get_node("Player").prepare_for_loading(gs)
	gs.local_push_event.connect(func(event): events.append(event.duplicate(true)))
	for i in range(50): await frame()
	for order in [-1.0, 1.0]:
		for direction in [-1.0, 1.0]:
			await shared_movement(order, direction)
	# A/B the actual rendered camera at an identical held game state.
	world.set("_replay_mode", true)
	release_keys()
	gs.camera_shake = 0.0
	for i in range(15): await frame()
	var camera := get_viewport().get_camera_3d()
	var rest_x := camera.global_position.x
	gs.camera_shake = 0.36
	var peak_camera_offset := 0.0
	for i in range(8):
		await frame()
		peak_camera_offset = maxf(peak_camera_offset, absf(camera.global_position.x - rest_x))
	gs.camera_shake = 0.0
	await frame()
	check(peak_camera_offset > 0.025 and peak_camera_offset <= 0.181, "actual rendered camera responds with bounded small shake")
	check(absf(camera.global_position.x - rest_x) < 0.001, "actual camera returns after shake")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples,"events":events,"camera_peak_offset":peak_camera_offset,"frames":video_frame,"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open(OUT + "runtime.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CONTACT_SPEED_RUNTIME " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"camera_peak_offset":peak_camera_offset,"frames":video_frame}))
	for provider in helper.providers: provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func shared_movement(order: float, direction: float) -> void:
	world.set("_replay_mode", true)
	release_keys()
	gs.local_push.reset()
	var width := sqrt(1.24 * 1.24 - 0.4 * 0.4)
	gs.player_x = -order * width * 0.5
	gs.player2_x = order * width * 0.5
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z + 0.4
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	for i in range(3): await frame()
	world.set("_replay_mode", false)
	key(axis_key(1,order), true)
	key(axis_key(2,-order), true)
	for i in range(12): await frame()
	check(gs.local_push.contact, "pair touching before shared movement %s" % [[order,direction]])
	var event_start := events.size()
	var start := Vector2(gs.player_x,gs.player2_x)
	var start_time := gs.play_time
	if order != direction:
		key(axis_key(1,order), false)
		key(axis_key(1,direction), true)
	if -order != direction:
		key(axis_key(2,-order), false)
		key(axis_key(2,direction), true)
	var lowest := Vector2(100,100)
	for i in range(18):
		var before := Vector2(gs.player_x,gs.player2_x)
		var before_time := gs.play_time
		await frame()
		var dt := gs.play_time - before_time
		var velocity := (Vector2(gs.player_x,gs.player2_x) - before) * direction / dt
		lowest.x = minf(lowest.x,velocity.x)
		lowest.y = minf(lowest.y,velocity.y)
		samples.append({"order":order,"direction":direction,"time":gs.play_time,"speed1":velocity.x,"speed2":velocity.y,"contact":gs.local_push.contact,"x1":gs.player_x,"x2":gs.player2_x})
		if i % 2 == 0:
			get_viewport().get_texture().get_image().save_png(OUT + "movement_frames/%04d.png" % video_frame)
			video_frame += 1
	var expected := gs.tuning.player_speed * (gs.play_time - start_time)
	var distance := (Vector2(gs.player_x,gs.player2_x) - start) * direction
	check(lowest.x >= gs.tuning.player_speed - 0.005 and lowest.y >= gs.tuning.player_speed - 0.005, "both key inputs retain speed on every frame %s: %s" % [[order,direction],lowest])
	check(absf(distance.x-expected) < 0.001 and absf(distance.y-expected) < 0.001, "ordinary travel distance with contact")
	check(absf(absf(gs.player2_x-gs.player_x)-width) < 0.001, "players remain touching without overlap")
	var hits := 0
	for i in range(event_start,events.size()):
		if events[i].kind in ["hit","clash"]: hits += 1
	check(hits == 0 and gs.p1_hp == 3 and gs.p2_hp == 3, "same-direction movement has no accidental attack or damage")
	release_keys()

func axis_key(player: int, direction: float) -> Key:
	if player == 1: return KEY_A if direction > 0 else KEY_D
	return KEY_LEFT if direction > 0 else KEY_RIGHT

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func release_keys() -> void:
	for code in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]: key(code,false)

func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
