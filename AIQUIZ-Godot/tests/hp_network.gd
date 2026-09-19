extends Node

const OUT := "res://artifacts/hp_system/"
var role := "host"
var gs: QuizGameState
var world: Node3D
var pc: PlayerController
var net: NetGameState
var helper: Node
var peer_ready := false
var acknowledged := -1
var received := -1
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var completed_events: Array = []
var health_events: Array = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("network="): role = arg.trim_prefix("network=")
	get_tree().root.size = Vector2i(960, 540)
	QuizManager.player_analytics = null
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.question_completed.connect(func(w, correct): completed_events.append([w, correct]))
	gs.health_changed.connect(func(p, old, value): health_events.append([p, old, value]))
	world = load("res://scenes/game_world.tscn").instantiate()
	world.set_meta("replay_mode", true)
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	pc = world.get_node("Player")
	pc.prepare_for_loading(gs)
	net = world.get("_net_state")
	for i in range(30): await get_tree().process_frame
	world.set_process(false)
	NetworkManager.relay_url = "ws://127.0.0.1:18766"
	NetworkManager.room_id = "hp-regression"
	NetworkManager.is_host = role == "host"
	NetworkManager.message_received.connect(_message)
	NetworkManager._connect_to_relay()
	var deadline := Time.get_ticks_msec() + 20000
	while NetworkManager._ws.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if NetworkManager._ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		failures.append("loopback connection timed out")
		finish()
		return
	NetworkManager.state = NetworkManager.State.IN_GAME
	net.is_online = true
	NetworkManager.send_message({"type": "settings", "hp_ready": role})
	if role == "guest":
		while received < 5 and Time.get_ticks_msec() < deadline + 45000:
			await get_tree().process_frame
		if received < 5: failures.append("guest did not receive all phases")
		finish()
		return
	while not peer_ready and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await publish(0)
	helper.answer(gs, false, false)
	await publish(1)
	gs._tick_health(0.175)
	await publish(2)
	gs._tick_health(0.425)
	await publish(3)
	gs.hp_questions_completed = 9
	helper.answer(gs, false, true)
	await publish(4)
	gs._set_player_hp(1, 1)
	helper.answer(gs, false, true)
	await publish(5)
	finish()

func _message(data: Dictionary) -> void:
	if data.has("hp_ready"):
		peer_ready = true
	if data.has("hp_ack"):
		acknowledged = int(data.hp_ack)
	if data.has("hp_phase") and role == "guest":
		sample_guest.call_deferred(int(data.hp_phase))

func publish(phase: int) -> void:
	net._send_snapshot()
	NetworkManager.send_message({"type": "settings", "hp_phase": phase})
	await sample(phase)
	var deadline := Time.get_ticks_msec() + 10000
	while acknowledged < phase and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if acknowledged < phase: failures.append("phase acknowledgement timed out: %d" % phase)

func sample_guest(phase: int) -> void:
	await sample(phase)
	received = phase
	NetworkManager.send_message({"type": "settings", "hp_ack": phase})

func sample(phase: int) -> void:
	for i in range(15):
		pc.update_from_state(gs)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "network_%s_%d.png" % [role, phase])
	var lean := 0.0
	for saved: Dictionary in pc.get("_health_pose_restore"):
		if saved.node == pc.p1_parts.get("spine"):
			lean = rad_to_deg(saved.transform.basis.get_rotation_quaternion().angle_to(saved.node.transform.basis.get_rotation_quaternion()))
	rows.append({"phase": phase, "hp": [gs.p1_hp, gs.p2_hp], "hurt": [gs.p1_damage_time, gs.p2_damage_time], "alive": [gs.p1_alive, gs.p2_alive], "wall": gs.current_wall_index, "lean": lean, "hud": world.get_node("GameplayHUD/PlayerHealthHUD").visible})

func finish() -> void:
	var report := {"role": role, "passed": failures.is_empty(), "samples": rows, "events": completed_events, "health_events": health_events, "failures": failures}
	FileAccess.open(OUT + "network_" + role + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HP_NETWORK " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
