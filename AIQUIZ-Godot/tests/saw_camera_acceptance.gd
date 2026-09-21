extends RefCounted

## Run with an initialized GameWorld, through Godot AI game_eval.
const OUT := "res://artifacts/saw_camera/"
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func run(world: Node) -> Dictionary:
	var gs: QuizGameState = world.game_state
	var controller: Node3D = world.camera_controller
	var camera: Camera3D = controller.camera
	world.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs.game_state = Constants.STATE_PLAYING
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.saw_transport_enabled = true
	gs.saw.enabled = true
	gs.saw.elapsed = 10.0
	gs.camera_shake = 0.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_x = 1.34
	gs.player2_x = -0.45
	gs.p1_alive = true
	gs.p2_alive = true
	for wall_distance: float in [4.0, 8.0, 16.8]:
		gs.world_scroll_z = gs.wall_z - wall_distance
		gs.player_z = gs.world_scroll_z
		gs.player2_z = gs.player_z + 1.0
		world._update_walls()
		world._update_wall_question()
		for fps: int in [30, 60, 120]:
			controller._saw_back = 0.0
			controller._question_pitch = 0.0
			controller._question_back = 0.0
			gs.saw.local_z = -22.0
			for i in range(fps * 2): world._update_camera(1.0 / fps)
			var maximum_speed := 0.0
			var max_height_difference := 0.0
			var onset_clearance := -1.0
			for i in range(fps * 6):
				# Approach at 4 m/s, then hold near the player.
				gs.saw.local_z = minf(-3.5, -22.0 + float(i) / fps * 4.0)
				var before: float = controller._saw_back
				world._update_camera(1.0 / fps)
				var clearance := minf(gs.get_saw_clearance(1), gs.get_saw_clearance(2))
				if clearance >= 8.0:
					check(is_zero_approx(controller._saw_back), "no early retreat %s/%s" % [wall_distance, fps])
				elif onset_clearance < 0.0 and controller._saw_back > 0.000001:
					onset_clearance = clearance
				maximum_speed = maxf(maximum_speed, absf(controller._saw_back - before) * fps)
				# A control pose from the question solver alone has exactly the same Y.
				var actual := camera.global_position
				var held: float = controller._saw_back
				var saw_z: float = gs.saw.local_z
				gs.saw.local_z = -100.0
				controller._saw_back = 0.0
				world._update_camera(0.0)
				max_height_difference = maxf(max_height_difference, absf(actual.y - camera.global_position.y))
				gs.saw.local_z = saw_z
				controller._saw_back = held
				world._update_camera(0.0)
			check(maximum_speed <= 10.001, "bounded horizontal speed %s/%s" % [wall_distance, fps])
			check(onset_clearance > 7.8 and onset_clearance < 8.0, "retreat begins just inside 8 m %s/%s" % [wall_distance, fps])
			check(max_height_difference < 0.001, "no saw-induced camera rise %s/%s" % [wall_distance, fps])
			var points: PackedVector3Array = controller._question_framing_points.duplicate()
			var saw_points_start := points.size()
			var bounds := AABB(Vector3(-12.25, StageConstants.FLOOR_TOP_Y, gs.saw.local_z - 1.7), Vector3(24.5, 0.65, 3.4))
			for corner: int in range(8): points.append(bounds.get_endpoint(corner))
			controller._append_player_framing_points(points, Vector3(gs.player_x, 0, gs.player_local_z))
			controller._append_player_framing_points(points, Vector3(gs.player2_x, 0, gs.player2_local_z))
			var viewport_size := camera.get_viewport().get_visible_rect().size
			var saw_left := 1.0
			var saw_right := 0.0
			for point_index: int in range(points.size()):
				var point := points[point_index]
				var uv := camera.unproject_position(point) / viewport_size
				var is_saw := point_index >= saw_points_start and point_index < saw_points_start + 8
				var side_margin := 0.005 if is_saw else 0.075
				check(not camera.is_position_behind(point) and uv.x >= side_margin and uv.x <= 1.0 - side_margin and uv.y >= 0.075 and uv.y <= 0.925, "framing %s/%s %s" % [wall_distance, fps, uv])
				if is_saw:
					saw_left = minf(saw_left, uv.x)
					saw_right = maxf(saw_right, uv.x)
			check(saw_left <= 0.025 and saw_right >= 0.975, "saw nearly touches both sides %s/%s" % [wall_distance, fps])
			samples.append({"wall_distance":wall_distance,"fps":fps,"onset_clearance":onset_clearance,"max_horizontal_speed":maximum_speed,"saw_height_change":max_height_difference,"eye":str(camera.global_position),"saw_left":saw_left,"saw_right":saw_right,"saw_back":controller._saw_back})
			if fps == 60:
				world._saw_controller.update_visual(gs, 0.0)
				for i in range(30): world._update_player(1.0 / 60.0)
				await RenderingServer.frame_post_draw
				world.get_viewport().get_texture().get_image().save_png(OUT + "near_wall_%s.png" % wall_distance)
	# Sudden danger still eases, and withdrawing fully restores the question camera.
	controller._saw_back = 0.0
	world._update_camera(1.0 / 60.0)
	check(controller._saw_back <= 10.0 / 60.0 + 0.001, "no snap when danger appears")
	gs.saw.local_z = -100.0
	for i in range(360): world._update_camera(1.0 / 60.0)
	check(controller._saw_back < 0.001, "far saw releases correction")
	for mode: String in [Constants.MODE_TUTORIAL, Constants.MODE_COOP]:
		gs.mode = mode
		gs.saw.local_z = -3.5
		world._update_camera(1.0 / 60.0)
		check(controller._saw_back < 0.001, "excluded mode " + mode)
	gs.mode = Constants.MODE_TEN
	gs.num_players = 1
	world._update_camera(1.0 / 60.0)
	check(controller._saw_back == 0.0, "solo camera unaffected")
	gs.num_players = 2
	gs.game_state = Constants.STATE_GAME_OVER
	world._update_camera(1.0 / 60.0)
	check(controller._saw_back == 0.0, "no saw framing during game over")
	gs.game_state = Constants.STATE_PLAYING
	for i in range(240): world._update_camera(1.0 / 60.0)
	world._saw_controller.update_visual(gs, 0.0)
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png(OUT + "after.png")
	var report := {"passed":failures.is_empty(),"failures":failures,"samples":samples}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	return report
