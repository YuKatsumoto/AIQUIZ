extends Node

var frames: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failures: Array[String] = []
var events: Array = []
var initial_ids: Array[int] = []
var out := ""

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func run(world: Node, player_index := 1, airborne := false, fps := 60, record := true) -> void:
	out = "res://artifacts/saw_catch/p%d_%s_%d/" % [player_index, "air" if airborne else "ground", fps]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var old_fps := Engine.max_fps
	Engine.max_fps = fps
	var gs: QuizGameState = QuizManager.game_state
	var saw: SawChaseController = world._saw_controller
	var pc: PlayerController = world.player_node
	world.set_process(false)
	world.camera_controller.set_process(false)
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_PLAYING
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_saw_killed = false
	gs.p2_saw_killed = false
	gs.p1_wall_impact = false
	gs.p2_wall_impact = false
	gs._set_player_hp(1, QuizGameState.MAX_HP)
	gs._set_player_hp(2, QuizGameState.MAX_HP)
	gs.game_over_timer = 0.0
	gs.player2_game_over_timer = 0.0
	gs.saw.local_z = 0.0
	gs.saw.elapsed = 6.0
	gs.world_scroll_z = gs.wall_z - 18.0
	gs.player_x = 1.5 if player_index == 1 else -7.5
	gs.player2_x = 1.5 if player_index == 2 else -7.5
	gs.player_z = gs.world_scroll_z + (2.0 if player_index == 1 else 10.0)
	gs.player2_z = gs.world_scroll_z + (2.0 if player_index == 2 else 10.0)
	gs.player_y = 1.8 if airborne and player_index == 1 else 0.0
	gs.player2_y = 1.8 if airborne and player_index == 2 else 0.0
	pc.reveal_without_intro_arrival()
	saw.finish_entrance()
	saw.update_visual(gs, 0.0, true)
	world._update_player(0.0)
	world._update_walls()
	var camera: Camera3D = world.camera_controller.get_node("Camera3D")
	camera.global_position = Vector3(8.5, 5.5, 9.0)
	camera.look_at(Vector3(1.5, 0.5 if not airborne else 1.3, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	gs._update_saw_chase(0.016, Vector2(gs.player_x, gs.player_local_z), Vector2(gs.player2_x, gs.player2_local_z))
	saw.update_visual(gs, 0.0, true)
	world._update_player(0.0)
	check(gs.p1_saw_killed if player_index == 1 else gs.p2_saw_killed, "real contact must start saw death")
	var ragdoll: Dictionary = pc._p1_ragdoll if player_index == 1 else pc._p2_ragdoll
	if not ragdoll.has("saw_catch"):
		failures.append("missing catch driver")
		finish(old_fps)
		return
	var driver: SawCatchRagdoll = ragdoll.saw_catch
	var torso: RigidBody3D = ragdoll.rag.bodies.torso
	for key: String in ragdoll.rag.bodies:
		if key == "anchor": continue
		var body := ragdoll.rag.bodies[key] as RigidBody3D
		initial_ids.append(body.get_instance_id())
		check(body.continuous_cd and (body.collision_mask & SawChaseState.WALL_COLLISION_LAYER) != 0, "wall CCD retained")
	var start_distance := torso.global_position.distance_to(saw.blade_center(driver.blade_index))
	var min_distance := start_distance
	var time := 0.0
	var last_capture := -1.0
	var transfer_time := -1.0
	var paused_checked := false
	while time < 3.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		time += dt
		gs.game_over_timer = time + 0.001 if player_index == 1 else 0.0
		gs.player2_game_over_timer = time + 0.001 if player_index == 2 else 0.0
		gs.saw.elapsed += dt
		gs.saw.local_z += dt * 0.25
		saw.update_visual(gs, dt, true)
		world._update_player(dt)
		if is_instance_valid(driver):
			events = driver.release_events.duplicate(true)
			var distance := torso.global_position.distance_to(saw.blade_center(driver.blade_index))
			min_distance = minf(distance, min_distance)
			if time < 0.45: check(driver.released.is_empty(), "limbs stay attached during initial catch")
			if not paused_checked and time > 0.28:
				paused_checked = true
				var before := driver.elapsed
				var before_position := torso.global_position
				get_tree().paused = true
				await get_tree().create_timer(0.12, true).timeout
				check(driver.elapsed == before and torso.global_position.is_equal_approx(before_position), "pause freezes caught ragdoll")
				get_tree().paused = false
			if record: samples.append({"time":time,"torso":torso.global_position,"distance":distance,"released":driver.released.keys()})
		var debris := pc._p1_explosion_bodies if player_index == 1 else pc._p2_explosion_bodies
		if not debris.is_empty() and transfer_time < 0.0:
			transfer_time = time
			check(debris.size() == initial_ids.size(), "all original physical pieces retained")
			for body: RigidBody3D in debris:
				check(initial_ids.has(body.get_instance_id()), "scatter preserves body identity")
		if record and time - last_capture >= 1.0 / 30.0:
			last_capture = time
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.resize(1400, 710)
			var file := "frame_%04d.jpg" % frames.size()
			image.save_jpg(out + file, 0.94)
			frames.append({"time":time,"file":file})
	check(min_distance < start_distance * 0.85, "torso is visibly pulled into blade")
	check(events.size() == 5, "four limbs and head release in sequence")
	check(transfer_time >= 1.10 and transfer_time < 1.45, "complete physical scatter near 1.15 seconds")
	check(gs.p2_alive if player_index == 1 else gs.p1_alive, "surviving player remains alive")
	samples.append({"start_distance":start_distance,"min_distance":min_distance,"transfer_time":transfer_time,"events":events})
	finish(old_fps)

func regress(world: Node) -> void:
	out = "res://artifacts/saw_catch/regression/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var gs: QuizGameState = QuizManager.game_state
	var pc: PlayerController = world.player_node
	var saw: SawChaseController = world._saw_controller
	# Exercise an actual separated body against the existing closed quiz wall.
	gs.world_scroll_z = gs.wall_z - 4.1
	world._update_walls()
	var piece: RigidBody3D = pc._p2_explosion_bodies[0]
	piece.global_position = Vector3(1.5, 0.0, 2.0)
	piece.linear_velocity = Vector3(0, 0, 25)
	piece.angular_velocity = Vector3.ZERO
	piece.contact_monitor = true
	piece.max_contacts_reported = 8
	var contacts := 0
	var max_z := -INF
	for tick: int in 36:
		await get_tree().physics_frame
		max_z = maxf(max_z, piece.global_position.z)
		for collider: Node3D in piece.get_colliding_bodies():
			if collider.name == "SawBodyCollision": contacts += 1
	check(contacts > 0 and max_z < 4.1, "separated limb physically stops at closed problem wall")
	samples.append({"wall_contacts":contacts,"max_z":max_z})
	# Revive through normal presentation cleanup, then catch both in one tick.
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_saw_killed = false
	gs.p2_saw_killed = false
	gs.game_over_timer = 0.0
	gs.player2_game_over_timer = 0.0
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.player_z = gs.world_scroll_z + 2.0
	gs.player2_z = gs.world_scroll_z + 2.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.game_state = Constants.STATE_PLAYING
	gs.saw.local_z = 0.0
	gs.saw.elapsed = 6.0
	world._update_player(0.0)
	check(pc._p1_explosion_bodies.is_empty() and pc._p2_explosion_bodies.is_empty(), "revival removes physical debris")
	saw.update_visual(gs)
	gs._update_saw_chase(0.016, Vector2(1.5,2.0), Vector2(-1.5,2.0))
	saw.update_visual(gs)
	world._update_player(0.0)
	check(gs.p1_saw_killed and gs.p2_saw_killed, "simultaneous contact catches both")
	check(pc._p1_ragdoll.saw_catch != pc._p2_ragdoll.saw_catch, "victims have independent physical drivers")
	var time := 0.0
	while time < 1.5:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		time += dt
		gs.game_over_timer = time + 0.001
		gs.player2_game_over_timer = time + 0.001
		saw.update_visual(gs,dt,true)
		world._update_player(dt)
	check(pc._p1_explosion_bodies.size() == 14 and pc._p2_explosion_bodies.size() == 14, "both bodies finish as 14 original physical parts")
	# Debris lifetime cleanup and revival must leave no visible death bodies.
	gs.game_over_timer = 7.0
	gs.player2_game_over_timer = 7.0
	world._update_player(0.0)
	check(pc._p1_explosion_bodies.is_empty() and pc._p2_explosion_bodies.is_empty(), "both debris sets expire")
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_saw_killed = false
	gs.p2_saw_killed = false
	gs.game_over_timer = 0.0
	gs.player2_game_over_timer = 0.0
	gs.game_state = Constants.STATE_PLAYING
	world._update_player(0.0)
	check(pc._p1_ragdoll.is_empty() and pc._p2_ragdoll.is_empty(), "revival clears catch containers")
	check(pc.p1_parts.l_hand.visible and pc.p1_parts.r_hand.visible and pc.p2_parts.l_hand.visible and pc.p2_parts.r_hand.visible, "both players restore hand parents")
	finish(Engine.max_fps)

func finish(old_fps: int) -> void:
	Engine.max_fps = old_fps
	var report := {"passed":failures.is_empty(),"failures":failures,"samples":samples,"frames":frames}
	FileAccess.open(out + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	if not frames.is_empty():
		var manifest := FileAccess.open(out + "frames.txt", FileAccess.WRITE)
		for i: int in frames.size():
			manifest.store_line("file '%s'" % frames[i].file)
			manifest.store_line("duration %.6f" % (float(frames[i+1].time) - float(frames[i].time) if i+1 < frames.size() else 1.0/30.0))
	print("SAW_CATCH_RUNTIME ", out, " passed=", failures.is_empty(), " failures=", failures)
	queue_free()
