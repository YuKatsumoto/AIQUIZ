extends "res://tests/hp_unit.gd"

func fixture(players := 2, mode := Constants.MODE_TEN) -> QuizGameState:
	var gs := super.fixture(players, mode)
	gs.saw_transport_enabled = true
	return gs

func run() -> void:
	var analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	for fps: int in [24, 30, 60, 120]:
		var saw := SawChaseState.new()
		for frame: int in range(fps * 3):
			saw.advance(1.0 / fps, 100.0, 14.0, 10.0, 2.0)
		check(absf(saw.local_z + 0.85) < 0.001, "grace and speed at %d fps" % fps)
		check(absf(saw.wheel_distance - 10.0) < 0.001, "wheel travel at %d fps" % fps)
		saw.advance(10.0, 30.0, 14.0, 10.0)
		check(is_equal_approx(saw.local_z, 14.55), "never overshoots leader target")
		saw.advance(1.0, -50.0, 14.0, 10.0)
		check(is_equal_approx(saw.local_z, 14.55), "leader retreat never reverses saw")
	var collision := SawChaseState.new()
	collision.local_z = 0.0
	for x: float in [-12.0, -10.5, -9.0, -7.5, -6.0, -4.5, -3.0, -1.5, 0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0]:
		check(collision.swept_contact(Vector2(x, 6), Vector2(x, -6), 0, 0.62), "swept blade/gap/edge x=%.1f" % x)
	check(not collision.swept_contact(Vector2(0, 4), Vector2(0, 3), 0, 0.62), "clear passage ahead stays safe")
	check(collision.swept_contact(Vector2(1.5, 1), Vector2(1.5, 1), -8, 0.62), "fast moving carriage sweeps stationary player")
	check(not collision.swept_contact(Vector2(15, 6), Vector2(15, -6), 0, 0.62), "no infinite horizontal kill plane")
	for first: int in [1, 2]:
		var gs := fixture()
		gs.saw.elapsed = 3.0
		gs.saw.local_z = 0.0
		gs.player_x = 1.5
		gs.player2_x = -1.5
		gs.player_z = 1.0 if first == 1 else 20.0
		gs.player2_z = 1.0 if first == 2 else 20.0
		gs.player_y = 5.0
		gs.player2_y = 5.0
		var events: Array = []
		gs.player_caught_by_saw.connect(func(index: int): events.append(index))
		gs._update_saw_chase(0.016, Vector2(gs.player_x, gs.player_z), Vector2(gs.player2_x, gs.player2_z))
		check(events == [first], "jump cannot evade P%d" % first)
		check(gs.get_player_hp(first) == 0, "saw ignores full HP")
		check(not gs.p1_wall_impact and not gs.p2_wall_impact and gs.quiz_history.is_empty(), "saw is not a wrong answer")
		var before: float = gs.saw.local_z
		gs._update_saw_chase(0.1, Vector2(gs.player_x, gs.player_z), Vector2(gs.player2_x, gs.player2_z))
		check(gs.saw.local_z > before and gs.game_state == Constants.STATE_PLAYING, "survivor continues to be pursued")
		check(not gs.is_wall_death_sequence_complete(), "saw death uses completion gate")
		for connection: Dictionary in gs.player_caught_by_saw.get_connections():
			gs.player_caught_by_saw.disconnect(connection.callable)
	var both := fixture()
	both.saw.elapsed = 3
	both.saw.local_z = 0
	both.player_x = 1.5
	both.player2_x = -1.5
	both.player_z = 0
	both.player2_z = 0
	var atomic: Array = []
	both.player_caught_by_saw.connect(func(_index: int): atomic.append(not both.p1_alive and not both.p2_alive))
	both._update_saw_chase(0.5, Vector2(1.5, 8), Vector2(-1.5, 8))
	check(atomic == [true, true] and both.game_state == Constants.STATE_GAME_OVER, "double swept contact commits atomically")
	check(both.quiz_history.is_empty(), "double hit does not submit false answer")
	for connection: Dictionary in both.player_caught_by_saw.get_connections():
		both.player_caught_by_saw.disconnect(connection.callable)
	var grace := fixture()
	grace.saw.local_z = 0
	grace._update_saw_chase(1.0, Vector2(-2,0), Vector2(2,0))
	check(grace.p1_alive and grace.p2_alive and grace.saw.local_z == 0, "initial grace prevents kill and travel")
	var excluded := fixture()
	excluded.saw.elapsed = 3
	excluded.saw.local_z = 0
	excluded.p1_fall_committed = true
	excluded.p2_waiting_for_shark = true
	excluded._update_saw_chase(0.1, Vector2(-2,0), Vector2(2,0))
	check(excluded.p1_alive and excluded.p2_alive and excluded.saw.local_z == 0, "fall/shark targets excluded")
	var handoff := fixture()
	handoff.saw.elapsed = 3.0
	handoff.player_z = 25.0
	handoff.player2_z = 20.0
	handoff._update_saw_chase(0.1, Vector2(-2,25), Vector2(2,20))
	var handoff_z: float = handoff.saw.local_z
	handoff.player2_z = 30.0
	handoff._update_saw_chase(0.1, Vector2(-2,25), Vector2(2,30))
	check(is_equal_approx(handoff.saw.local_z, handoff_z + 1.0), "leader change respects continuous speed cap")
	handoff.saw.local_z = 12.0
	handoff.player_z = 20.0
	handoff.player2_z = 21.0
	handoff._update_saw_chase(0.1, Vector2(-2,20), Vector2(2,21))
	check(handoff.saw.local_z == 12.0, "both players retreat without moving saw backward")
	var gap := fixture()
	gap.player_z = 18
	gap.player2_z = 0
	gap.update(0.016, Vector2.ZERO, Vector2.ZERO, false, false)
	check(gap.p1_alive and gap.p2_alive, "18m separation alone never kills")
	var held: float = gap.saw.local_z
	gap.advance_after_correct()
	check(gap.saw.local_z == held, "question transition preserves position")
	gap.saw.elapsed = 3.0
	gap.game_state = Constants.STATE_PRELOADING
	check(gap.is_saw_visible(), "mid-game fetch retains saw presentation")
	gap.preload_wait_sec = 0.0
	gap.min_preload_sec = 10.0
	for state: String in [Constants.STATE_COUNTDOWN, Constants.STATE_CORRECT, Constants.STATE_PRELOADING, "ONLINE_QUIZ_ERROR", Constants.STATE_GAME_OVER]:
		gap.game_state = state
		gap.countdown_timer = 10
		gap.message_timer = 10
		var time_before: float = gap.saw.elapsed
		gap.update(0.01, Vector2.ZERO, Vector2.ZERO, false, false)
		check(gap.saw.elapsed == time_before, "freeze outside PLAYING: " + state)
	gap.start_game()
	check(gap.saw.local_z == SawChaseState.INITIAL_Z and gap.saw.elapsed == 0 and not gap.p1_saw_killed, "retry resets saw")
	check(not gap.is_saw_visible(), "initial preload keeps saw hidden")
	for mode: String in [Constants.MODE_TEN, Constants.MODE_ENDLESS, Constants.MODE_COOP, Constants.MODE_TUTORIAL]:
		for count: int in [1, 2]:
			var gs := fixture(count, mode)
			check(gs.uses_saw_chase() == (count == 2 and mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS]), "mode scope %s/%d" % [mode,count])
	var remote := fixture()
	remote.saw_transport_enabled = false
	check(not remote.uses_saw_chase() and remote.is_scroll_out_death_enabled(), "online retains legacy rules")
	_replay_cases()
	var rails := ConveyorRails.new()
	add_child(rails)
	rails.build(10, 100, -1.2)
	check(is_equal_approx(rails.left_head.global_position.x, -11.86) and is_equal_approx(rails.left_head.global_position.y + 0.02, -0.94), "rail gauge/top")
	rails.set_geometry(40, 200, -1.2)
	check(is_equal_approx(rails._caps[1].global_position.z, 139.96) and (rails.left_head.mesh as BoxMesh).size.z == 200, "course length and end caps")
	check(rails.find_children("*", "CollisionObject3D", true, false).is_empty(), "rails add no fall prevention")
	QuizManager.player_analytics = analytics
	for provider: QuizProvider in providers:
		provider.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/chip_saw/verification"))
	FileAccess.open("res://artifacts/chip_saw/verification/unit.json", FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}, "\t"))
	print("SAW_UNIT ", checks, " checks; failures: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _replay_cases() -> void:
	var gs := fixture()
	var recorder := ReplayRecorder.new()
	recorder.start_recording(gs)
	gs.saw.enabled = true
	recorder.capture(gs)
	gs.play_time = 1
	gs.saw.local_z = 4
	gs.saw.elapsed = 3
	gs.saw.wheel_distance = 14.85
	gs.p1_saw_killed = true
	gs.p1_alive = false
	gs.game_over_timer = 0.001
	recorder.capture(gs)
	check(recorder.fields_per_frame == 34 and recorder.meta.version == 4, "v4/34 replay format")
	var restored := ReplayRecorder.new()
	check(restored.import_from_string(recorder.export_for_sharing()), "v4 share roundtrip")
	var player := ReplayPlayer.new()
	player.setup(restored)
	gs.is_replay = true
	player.seek(0.5)
	player.apply_to_game_state(gs)
	check(not gs.p1_saw_killed and gs.p1_alive, "seek before contact retains alive flag")
	player.seek(1.0)
	player.apply_to_game_state(gs)
	check(gs.p1_saw_killed and gs.saw.local_z == 4 and gs.saw.elapsed == 3 and absf(gs.saw.wheel_distance - 14.85) < .001, "seek restores all saw state without collision")
	player.seek(0)
	player.apply_to_game_state(gs)
	check(not gs.p1_saw_killed and gs.p1_alive, "rewind clears saw death")
	for width: int in [24,28,34]:
		var old := ReplayRecorder.new()
		old.meta = recorder.meta.duplicate()
		old.meta.version = 2 if width == 24 else (3 if width == 28 else 4)
		old.fields_per_frame = width
		old.frame_count = 2
		for frame: int in range(2):
			for field: int in range(width):
				old.frames.append(recorder.frames[frame * 34 + field])
		var path := "res://artifacts/chip_saw/verification/replay_%d.rep" % width
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var payload := {"meta":old.meta,"quiz":{},"fields_per_frame":width,"frame_count":2,"frames_base64":Marshalls.raw_to_base64(old.frames.to_byte_array())}
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(payload))
		var loaded := ReplayRecorder.new()
		check(loaded.load_from_file(path), "%d replay file load" % width)
		check(loaded.import_from_string(old.export_for_sharing()), "%d replay share load" % width)
		check(bool(loaded.get_frame(1).saw_enabled) == (width == 34), "old replay hides saw")
