extends Node

class TestProvider extends QuizProvider:
	var submitted: Array[bool] = []
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, correct: bool) -> void:
		submitted.append(correct)

var checks := 0
var failures: Array[String] = []
var providers: Array[QuizProvider] = []

func _ready() -> void:
	call_deferred("run")

func fixture(players := 2, mode := Constants.MODE_TEN) -> QuizGameState:
	var provider := TestProvider.new()
	providers.append(provider)
	var gs := QuizGameState.new(provider)
	gs.num_players = players
	gs.mode = mode
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	gs.game_state = Constants.STATE_PLAYING
	gs.target_count = 10
	gs.tuning.wall_speed_override = 2.9
	gs._reset_health()
	gs.player_x = -2.0
	gs.player2_x = 2.0
	gs.p2_alive = players == 2
	for i in range(10 if mode == Constants.MODE_TEN else 40):
		var choices := PackedStringArray(["正解", "不正解", "別の不正解", "その他"]) if gs.num_choices_for_index(i) == 4 else PackedStringArray(["正解", "不正解"])
		gs.quiz_list.append(QuizItem.create("HP検証 %d" % i, choices, 0, "テスト問題です。", "OFFLINE"))
	gs.load_current_quiz()
	return gs

func door(gs: QuizGameState, correct: bool) -> float:
	var index := gs.current_quiz.a if correct else (gs.current_quiz.a + 1) % gs.num_choices
	return gs.tuning.door4_xs[index] if gs.num_choices == 4 else (gs.tuning.left_door_x if index == 0 else gs.tuning.right_door_x)

func answer(gs: QuizGameState, correct1: bool, correct2 := true) -> void:
	gs.player_x = door(gs, correct1)
	gs.player2_x = door(gs, correct2)
	gs.resolve_collision(true, gs.num_players == 2 and gs.p2_alive)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	for mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS]:
		for players in [1, 2]:
			var gs := fixture(players, mode)
			for hit in range(1, 4):
				answer(gs, false, false)
				check(gs.p1_hp == 3 - hit, "P1 HP sequence %s/%d/%d" % [mode, players, hit])
				check(gs.p1_alive == (hit < 3), "P1 death only at zero")
				if players == 2:
					check(gs.p2_hp == 3 - hit and gs.p2_alive == (hit < 3), "P2 HP sequence")
				check(gs.current_wall_index == mini(hit, 2), "all-wrong progression")
				check(gs.quiz_history.size() == hit and gs.total_wrong == hit, "one history/stat per question")
				check(gs.score == 0 and gs.player2_score == 0, "wrong never scores")
			check(gs.game_state == Constants.STATE_GAME_OVER and gs.p1_wall_impact, "fatal hit existing ending")
			var health_events: Array = []
			gs.health_changed.connect(func(p, old, value): health_events.append([p, old, value]))
			gs.start_game()
			check(gs.p1_hp == 3 and gs.p2_hp == 3 and gs.hp_questions_completed == 0, "retry resets health")
			check(gs.p1_damage_time == 0.0 and gs._hp_evaluated_mask == 0, "retry clears damage/latches")
	_staggered()
	_recovery()
	_hazards()
	_motion()
	_sync_replay()
	for mode in [Constants.MODE_TUTORIAL, Constants.MODE_COOP]:
		var gs := fixture(2, mode)
		check(not gs.uses_hp(), "excluded mode keeps rules: " + mode)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/hp_system"))
	FileAccess.open("res://artifacts/hp_system/unit.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HP_UNIT " + JSON.stringify(report))
	QuizManager.player_analytics = analytics
	for provider in providers:
		provider.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _staggered() -> void:
	for second_correct in [true, false]:
		for first in [1, 2]:
			var gs := fixture()
			gs.player_x = door(gs, false)
			gs.player2_x = door(gs, false)
			gs.resolve_collision(first == 1, first == 2)
			for i in range(30):
				gs.resolve_collision(first == 1, first == 2)
			check(gs.get_player_hp(first) == 2 and gs.current_wall_index == 0, "same wall once, waits for other player")
			check(gs.quiz_history.is_empty(), "staggered pending question not submitted")
			if first == 1: gs.player2_x = door(gs, second_correct)
			else: gs.player_x = door(gs, second_correct)
			gs.resolve_collision(first == 2, first == 1)
			check(gs.current_wall_index == 1 and gs.quiz_history.size() == 1, "second answer completes once")
			check(gs.provider.submitted == [second_correct], "aggregate submitted result")
	var mixed := fixture()
	mixed.p1_hp = 1
	answer(mixed, false, true)
	check(mixed.p1_hp == 0 and not mixed.p1_alive and mixed.p2_alive and mixed.current_wall_index == 1, "mixed fatal/correct continues survivor")
	var solo := fixture(1)
	solo.current_index = 9
	solo.current_wall_index = 9
	solo.load_current_quiz()
	answer(solo, false)
	check(solo.p1_hp == 2 and solo.game_state == Constants.STATE_CLEAR, "solo last wrong with HP clears")
	var duo := fixture()
	duo.current_index = 9
	duo.current_wall_index = 9
	duo.load_current_quiz()
	answer(duo, false, false)
	check(duo.game_state == Constants.STATE_GOAL_RACE and duo.p1_hp == 2 and duo.p2_hp == 2, "duo last wrong enters goal race")
	var wall := fixture(1)
	wall.player_x = 0.0
	check(wall._check_player_door(0.0) < 0, "wall-gap fixture")
	wall.resolve_collision(true, false)
	check(wall.p1_hp == 2 and wall.current_wall_index == 1, "solid wall loses one HP")

func _recovery() -> void:
	var gs := fixture(2, Constants.MODE_ENDLESS)
	for i in range(1, 21):
		answer(gs, i not in [1, 11], true)
		var expected := 3 if i % 10 == 0 else 2
		check(gs.p1_hp == expected and gs.p2_hp == 3, "endless milestone %d" % i)
		check(gs.hp_questions_completed == i, "completed count %d" % i)
		gs._try_finish_hp_question()
		check(gs.hp_questions_completed == i, "milestone cannot repeat")
	var fatal := fixture(2, Constants.MODE_ENDLESS)
	fatal.hp_questions_completed = 9
	fatal.p1_hp = 1
	fatal.p2_hp = 2
	answer(fatal, false, true)
	check(fatal.p1_hp == 0 and not fatal.p1_alive and fatal.p2_hp == 3, "milestone cannot revive fatal player")
	var wrong := fixture(1, Constants.MODE_ENDLESS)
	wrong.hp_questions_completed = 9
	answer(wrong, false)
	check(wrong.p1_hp == 3 and wrong.hp_questions_completed == 10, "wrong answer counts toward recovery")
	var normal := fixture(2)
	normal.hp_questions_completed = 9
	normal.p1_hp = 2
	answer(normal, true, true)
	check(normal.p1_hp == 2, "normal has no recovery")

func _hazards() -> void:
	for player in [1, 2]:
		var gs := fixture()
		if player == 1: gs.p1_waiting_for_shark = true
		else: gs.p2_waiting_for_shark = true
		gs.complete_ocean_shark_attack(player)
		check(gs.get_player_hp(player) == 0, "ocean fatal at full HP P%d" % player)
		check(gs.p1_shark_killed if player == 1 else gs.p2_shark_killed, "ocean keeps shark death")
		gs.complete_ocean_shark_attack(player)
		check(gs.get_player_hp(player) == 0, "repeated shark callback harmless")
	var scroll := fixture()
	scroll.player_z = 0.0
	scroll.player2_z = -scroll.SCROLL_OUT_LIMIT - 1.0
	scroll.update(0.001)
	check(not scroll.p2_alive and scroll.p2_hp == 0, "scroll-out still fatal at full HP")
	var pending := fixture()
	pending.player_x = door(pending, false)
	pending.resolve_collision(true, false)
	pending.p2_waiting_for_shark = true
	pending.complete_ocean_shark_attack(2)
	pending._try_finish_hp_question()
	check(pending.current_wall_index == 1 and pending.p1_hp == 2, "pending answer advances after other player ocean death")

func _motion() -> void:
	var gs := fixture(1)
	answer(gs, false)
	check(gs.p1_damage_time == 0.6 and gs.is_damage_stunned(1), "damage starts stun/blink")
	gs.player_x = 0.0
	gs.player_z = 0.0
	var z := gs.player_z
	gs.update(0.1, Vector2.RIGHT, Vector2.ZERO, true)
	check(is_zero_approx(gs.player_x) and is_zero_approx(gs.player_y), "stun blocks lateral/jump")
	check(gs.player_z > z, "stun preserves forward movement")
	gs.update(0.26)
	check(not gs.is_damage_stunned(1) and gs.p1_damage_time > 0.0, "stun ends before blink")
	gs.update(0.25)
	check(gs.p1_damage_time == 0.0, "blink ends")
	gs.p1_damage_time = 0.6
	gs.game_state = Constants.STATE_CLEAR
	gs.update(0.01)
	check(gs.p1_damage_time == 0.0, "transition clears recoil")

func _sync_replay() -> void:
	var host := fixture()
	var guest := fixture()
	answer(host, false, true)
	var net := NetGameState.new()
	add_child(net)
	net.game_state = guest
	var previous_host := NetworkManager.is_host
	NetworkManager.is_host = false
	net._on_snapshot_received(host.to_snapshot())
	check(guest.p1_hp == 2 and guest.p2_hp == 3 and guest.p1_damage_time == host.p1_damage_time, "NetGameState host/guest HP and motion")
	NetworkManager.is_host = previous_host
	net.queue_free()
	var recorder := ReplayRecorder.new()
	host.play_time = 0.0
	recorder.start_recording(host)
	recorder.capture(host)
	host.play_time = 1.0
	host.p1_hp = 1
	host.p1_damage_time = 0.0
	recorder.capture(host)
	var copy := ReplayRecorder.new()
	check(copy.import_from_string(recorder.export_for_sharing()), "new replay import")
	var player := ReplayPlayer.new()
	player.setup(copy)
	player.current_time = 0.0
	player.apply_to_game_state(guest)
	check(guest.p1_hp == 2 and is_equal_approx(guest.p1_damage_time, 0.6) and guest.uses_hp(), "replay restores recoil/HP")
	player.current_time = 1.0
	player.apply_to_game_state(guest)
	check(guest.p1_hp == 1 and guest.p1_damage_time == 0.0, "replay seeking restores state")
	var legacy := PackedFloat32Array()
	for frame in range(2):
		for field in range(24):
			legacy.append(recorder.frames[frame * recorder.fields_per_frame + field])
	var old := JSON.parse_string(recorder.export_for_sharing()) as Dictionary
	old.meta.version = 2
	old.meta.erase("hp_enabled")
	old.fields_per_frame = 24
	old.frames_base64 = Marshalls.raw_to_base64(legacy.to_byte_array())
	var old_recorder := ReplayRecorder.new()
	check(old_recorder.import_from_string(JSON.stringify(old)), "legacy replay import")
	check(old_recorder.get_frame(1).t == 1.0, "legacy replay stride preserved")
	player.setup(old_recorder)
	player.apply_to_game_state(guest)
	check(not guest.uses_hp() and guest.p1_damage_time == 0.0, "legacy replay hides HP")
	var new_copy := ReplayRecorder.new()
	check(new_copy.import_from_string(old_recorder.export_for_sharing()) and new_copy.get_frame(1).t == 1.0, "legacy share round-trip")
