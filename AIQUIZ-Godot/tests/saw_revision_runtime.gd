extends RefCounted

const OUT := "res://artifacts/saw_revision/"
var checks: Array[String] = []
var failures: Array[String] = []
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func capture(world: Node, label: String) -> void:
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func run(world: Node) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var tree := world.get_tree()
	var gs: QuizGameState = QuizManager.game_state
	var saw: SawChaseController = world._saw_controller
	world.set_process(false)
	var camera: Camera3D = world.camera_controller.get_node("Camera3D")
	gs.saw.elapsed = 0.0
	gs.game_state = Constants.STATE_PRELOADING
	saw._landing_spin_elapsed = 0.0
	saw.update_visual(gs)
	var rotation_before := saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])
	await tree.create_timer(0.15).timeout
	saw.update_visual(gs)
	check(saw.visible and rotation_before.is_equal_approx(saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])), "preload visible and stationary")
	await capture(world, "preload")
	var dt := 1.0 / 60.0
	var angular_samples: Array = []
	for phase: float in [0.0, 1.0, 2.0, 3.8]:
		saw._landing_spin_elapsed = phase
		saw.update_visual(gs)
		var before := saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])
		saw.update_visual(gs, dt, true)
		angular_samples.append(before.angle_to(saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])))
	check(angular_samples[0] < angular_samples[1] and angular_samples[1] < angular_samples[2] and angular_samples[2] < angular_samples[3], "rendered blades accelerate after landing")
	samples.append({"landing_spin_angles":angular_samples})
	# A real saw catch retains wall CCD through physical limb separation.
	gs.game_state = Constants.STATE_PLAYING
	gs.state_changed.emit(gs.game_state)
	gs.saw.elapsed = 3.0
	gs.saw.local_z = 0.0
	gs.world_scroll_z = gs.wall_z - 4.1
	gs.player_x = 1.5
	gs.player2_x = -4.5
	gs.player_z = gs.world_scroll_z + 2.0
	gs.player2_z = gs.world_scroll_z + 10.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	world._update_player(0.0)
	world._update_walls()
	camera.global_position = Vector3(-9, 5, -9)
	camera.look_at(Vector3(0, 1, 3))
	await tree.physics_frame
	await tree.physics_frame
	gs._update_saw_chase(0.016, Vector2(1.5, 2), Vector2(-4.5, 10))
	saw.update_visual(gs)
	world._update_player(0.0)
	check(gs.p1_saw_killed and gs.p2_alive, "actual saw contact kills P1 and preserves P2")
	var bodies: Dictionary = world.player_node._p1_ragdoll.rag.bodies
	var monitored: Array[RigidBody3D] = []
	for body: Variant in bodies.values():
		if body is RigidBody3D and body.collision_mask & SawChaseState.WALL_COLLISION_LAYER:
			body.contact_monitor = true
			body.max_contacts_reported = 8
			monitored.append(body)
	check(monitored.size() >= 8, "saw ragdoll opts into wall collision with CCD")
	var wall_contacts := 0
	var max_z := -INF
	var elapsed := 0.0
	var impact_saved := false
	var debris_launched := false
	while elapsed < 1.85:
		await tree.physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if elapsed < 0.4: gs.world_scroll_z += 2.9 / Engine.physics_ticks_per_second
		world._update_walls()
		for body: RigidBody3D in monitored:
			if not is_instance_valid(body): continue
			max_z = maxf(max_z, body.global_position.z)
			for collider: Node3D in body.get_colliding_bodies():
				if collider.name == "SawBodyCollision": wall_contacts += 1
		gs.game_over_timer = elapsed + 0.001
		world._update_player(0.0)
		saw.update_visual(gs)
		# The new catch draws the victim inward. After release, deliberately send
		# one real separated body toward the closed wall to test its CCD contract.
		if not debris_launched and not world.player_node._p1_explosion_bodies.is_empty():
			debris_launched = true
			var piece: RigidBody3D = world.player_node._p1_explosion_bodies[0]
			piece.global_position = Vector3(1.5, 0.0, 1.0)
			piece.linear_velocity = Vector3(0.0, 0.0, 18.0)
		if elapsed > 0.30 and not impact_saved:
			impact_saved = true
			await capture(world, "wall_impact")
	check(wall_contacts > 0, "real ragdoll physically contacts problem wall")
	check(max_z < 4.1, "no ragdoll center tunnels through closed wall")
	check(not world.player_node._p1_explosion_bodies.is_empty(), "saw catch separates physical limbs within 1.85 seconds")
	samples.append({"wall_contacts":wall_contacts,"max_body_z":max_z,"wall_z":4.1})
	await capture(world, "wall_scatter")
	# Broken doors must remove their collider; solid frame must remain.
	var wall: Node3D = world._active_walls[0]
	wall.break_door(0)
	await tree.physics_frame
	await tree.physics_frame
	var door_shape: CollisionShape3D = wall._saw_collision_shapes[wall.doors[0].get_instance_id()]
	check(door_shape.disabled, "broken answer door leaves an open passage")
	# Restore P1, then jump towards the real saw using the normal movement update.
	gs.p1_alive = true
	gs.p1_saw_killed = false
	gs.game_over_timer = 0.0
	gs.player_z = gs.world_scroll_z + 4.8
	gs.player_y = 0.0
	gs.player_vel_y = 0.0
	gs._set_player_hp(1, QuizGameState.MAX_HP)
	gs.player2_z = gs.world_scroll_z + 10.0
	world._update_player(0.0)
	gs.tuning.wall_start_z += 50.0
	world._clear_preview_walls()
	world._update_walls()
	var raised_before_hit := false
	var unselected_stays_down := true
	var saved_jump := false
	var steps := 0
	while gs.p1_alive and steps < 90:
		await tree.physics_frame
		gs.update(dt, Vector2(0, -1), Vector2.ZERO, steps == 0, false)
		saw.update_visual(gs)
		world._update_player(dt)
		for i: int in saw.spin_bones.size():
			var bone := saw.spin_bones[i]
			var rest := saw.skeleton.get_bone_rest(bone).origin
			var lift := saw.skeleton.get_bone_pose_position(bone).y - rest.y
			if gs.p1_alive and lift > 0.5: raised_before_hit = true
			if absf(-rest.x - gs.player_x) > 2.07 and lift > 0.01: unselected_stays_down = false
		if gs.player_y > 1.0 and not saved_jump:
			saved_jump = true
			await capture(world, "jump_rising")
		steps += 1
	check(raised_before_hit and unselected_stays_down, "only nearby blade rises before airborne contact")
	check(gs.p1_saw_killed and gs.player_y > 0.1, "normal jumping movement caught by raised saw")
	samples.append({"jump_height_at_hit":gs.player_y,"jump_steps":steps})
	await capture(world, "jump_contact")
	# Vary proximity after a long playtime: the warning phase must only advance
	# by dt * frequency, never jump when the player moves inside the warning zone.
	gs.p1_alive = true
	gs.p1_saw_killed = false
	gs.game_over_timer = 0.0
	var hud: Node = world.get_node("GameplayHUD")
	hud.set_process(false)
	hud._rear_edge_warning_time = 5.0
	var max_phase_step := 0.0
	for frame: int in range(120):
		gs.player_z = gs.world_scroll_z + gs.saw.local_z + 2.2 + float(frame % 30) * 0.13
		var phase_before: float = hud._rear_edge_warning_time
		hud._process(dt)
		var advance := fposmod(float(hud._rear_edge_warning_time) - phase_before, TAU)
		max_phase_step = maxf(max_phase_step, advance)
	check(max_phase_step <= dt * 9.0 + 0.00001, "movement keeps warning phase continuous")
	samples.append({"max_warning_phase_step":max_phase_step})
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return report

func run_p2_clip(world: Node) -> Dictionary:
	var gs: QuizGameState = QuizManager.game_state
	gs.game_state = Constants.STATE_PLAYING
	gs.state_changed.emit(gs.game_state)
	gs.saw.elapsed = 3.0
	gs.saw.local_z = 0.0
	gs.player_x = -4.5
	gs.player_z = gs.world_scroll_z + 10.0
	gs.player2_x = 1.5
	gs.player2_z = gs.world_scroll_z + 4.8
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player2_vel_y = 0.0
	world._clear_preview_walls()
	world.set_process(false)
	var camera: Camera3D = world.camera_controller.get_node("Camera3D")
	camera.global_position = Vector3(-8, 4.0, -10)
	camera.look_at(Vector3(0, 1, 2))
	var caught_height := 0.0
	var saw_caught := false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "clip"))
	var old_max_fps := Engine.max_fps
	Engine.max_fps = 30
	for frame: int in range(75):
		gs.update(1.0 / 30.0, Vector2.ZERO, Vector2(0, -1) if not saw_caught else Vector2.ZERO, false, frame == 0)
		world._saw_controller.update_visual(gs)
		world._update_player(1.0 / 30.0)
		world._update_walls()
		if gs.p2_saw_killed and not saw_caught:
			saw_caught = true
			caught_height = gs.player2_y
		await RenderingServer.frame_post_draw
		var shot := world.get_viewport().get_texture().get_image()
		shot.resize(1280, 650)
		shot.save_png(OUT + "clip/frame_%03d.png" % frame)
	Engine.max_fps = old_max_fps
	return {"p2_caught_airborne":saw_caught and caught_height > 0.1,"height":caught_height,"frames":75,"p1_alive":gs.p1_alive,"debris":world.player_node._p2_explosion_bodies.size()}
