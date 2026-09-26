extends Node

## Rendered acceptance probe. Attach to the root of an editor game and defer run().
## Fixtures change runtime state only; normal door crossings still use game logic.
const OUTPUT := "res://artifacts/wall_two_line_minimum/"
var finished := false
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var phase := "idle"
var _world: Node3D
var _gs: QuizGameState


func run(compact_only: bool = false) -> void:
	name = "WallQuestionRegression"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_gs = QuizManager.game_state
	var previous_source: String = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	for players: int in [1, 2]:
		if not await _start(players, Constants.MODE_TEN):
			break
		await _text_and_camera_cases(players)
		await _cross_doors(players)
		if compact_only:
			continue
		if await _start(players, Constants.MODE_TEN):
			await _wrong_door_case(players)
	for mode: String in ([] if compact_only else [Constants.MODE_ENDLESS, Constants.MODE_COOP, Constants.MODE_TUTORIAL]):
		for players: int in ([2] if mode == Constants.MODE_COOP else [1, 2]):
			if await _start(players, mode):
				await _mode_case(players, mode)
	QuizManager.provider.llm_mode = previous_source
	finished = true
	phase = "finished"
	var report := {"passed": failures.is_empty(), "failures": failures, "samples": samples, "renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("WALL_QUESTION_REGRESSION " + JSON.stringify(report))


func _start(players: int, mode: String) -> bool:
	phase = "start_p%d_%s" % [players, mode]
	if is_instance_valid(_world):
		_world.set_process(true)
	_gs.num_players = players
	_gs.mode = mode
	_gs.llm_mode = "OFFLINE"
	_gs.subject = "算数"
	if mode == Constants.MODE_TUTORIAL:
		_gs.start_tutorial(GameManager.TUTORIAL_COURSE_SOLO if players == 1 else GameManager.TUTORIAL_COURSE_LOCAL_2P)
	else:
		_gs.start_game()
	GameManager.start_game()
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.name == "GameWorld" and not SceneTransition.is_transitioning() and not scene.is_start_presentation_locked():
			_world = scene
			break
	if Time.get_ticks_msec() >= deadline:
		_fail("start timeout " + phase)
		return false
	_check(_world.get_node_or_null("GameplayHUD/QuestionPanel") == null, "2D panel removed")
	_check(_visible_questions() == 0, "no question before start")
	_gs.trigger_start()
	deadline = Time.get_ticks_msec() + 18000
	while _gs.game_state != Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _gs.game_state != Constants.STATE_PLAYING:
		_fail("countdown timeout " + phase)
		return false
	_world.set_process(false)
	# Let the start barrier's fragments clear before the text fixtures.
	await get_tree().create_timer(2.0).timeout
	return true


func run_boss_confirmation() -> void:
	name = "WallQuestionBossConfirmation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_gs = QuizManager.game_state
	var previous_source: String = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"
	for players: int in [1, 2]:
		if not await _start(players, Constants.MODE_TEN):
			break
		_gs.current_index = 9
		_gs.current_wall_index = 9
		_gs.load_current_quiz()
		_place(6.0, 1.95, -1.95, 2.0 if players == 2 else 0.0)
		await _render_frames(50)
		_validate("p%d_boss_final" % players)
		var wall: Node3D = _world._question_framing_wall
		var boss: Label3D = wall.boss_label
		var bounds := boss.transform * boss.get_aabb()
		_check(bounds.position.y >= 2.38 and bounds.end.y <= wall.wall_top_y, "boss heading inside beam")
		_check(boss.font.get_string_size(boss.text, HORIZONTAL_ALIGNMENT_LEFT, -1, boss.font_size).x <= boss.width, "boss heading single line")
		await _capture("p%d_boss_final" % players)
		_gs.player_x = _gs.tuning.door4_xs[_gs.current_quiz.a]
		_gs.player2_x = _gs.player_x - 0.35
		_world.set_process(true)
		var deadline := Time.get_ticks_msec() + 10000
		while _gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var expected_states: Array = [Constants.STATE_GOAL_RACE] if players == 2 else [Constants.STATE_CLEAR, Constants.STATE_RESULT_CEREMONY]
		_check(_gs.game_state in expected_states and _gs.p1_alive, "final boss completion p%d: %s" % [players, _gs.game_state])
		_world._update_wall_question()
		_check(_visible_questions() == 0, "final boss question retired")
		_world.set_process(false)
		await get_tree().create_timer(4.5).timeout
	QuizManager.provider.llm_mode = previous_source
	finished = true
	phase = "finished"
	var report := {"passed": failures.is_empty(), "failures": failures, "samples": samples, "renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(OUTPUT + "boss_final.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("WALL_QUESTION_BOSS_FINAL " + JSON.stringify(report))


func _text_and_camera_cases(players: int) -> void:
	var original := _gs.current_quiz
	_gs.current_quiz = original.duplicate(true)
	var fixtures := [
		"3 + 4 はいくつですか？",
		"公園に子どもが12人いて、そのうち3人が帰り、あとから5人が来ました。今、公園にいる子どもは全部で何人でしょうか？",
		"Choose the correct word: I go to school with my friends every morning.",
		"1/2 + 1/4 はいくつ？",
		"「き ょ う は あ め で す」の文を読みましょう。",
		"1 + 1 は？\n2 + 2 は？",
	]
	var choices := [["7", "8"], ["14人", "20人"], ["friends", "friend"], ["3/4", "1/4"], ["きょうはあめです", "あしたははれです"], ["4", "5"]]
	var one_line_top := 0.0
	for i: int in range(fixtures.size()):
		phase = "p%d_text%d" % [players, i]
		_gs.current_quiz.q = fixtures[i]
		_gs.current_quiz.c = PackedStringArray(choices[i])
		_place(7.0, 3.5 if i % 2 == 0 else -3.5, -3.5, 3.0 if players == 2 else 0.0)
		await _render_frames(35)
		_validate(phase)
		if i == 0:
			one_line_top = _base_scale_wall_top(_world._question_framing_wall)
		if i == 1:
			_check(_base_scale_wall_top(_world._question_framing_wall) > one_line_top, "long text expands wall")
		if i == 5:
			_check(absf(_base_scale_wall_top(_world._question_framing_wall) - one_line_top) < 0.01, "one and two lines share the same wall height")
		if i in [0, 1, 3, 5]:
			await _capture(phase)
	# Close approach and lateral motion, with no teleports between samples.
	_gs.current_quiz.q = fixtures[1]
	_gs.current_quiz.c = PackedStringArray(choices[1])
	# Settle the initial fixture teleport before measuring continuous approach motion.
	_place(12.0, -6.5, 6.5, 4.0 if players == 2 else 0.0)
	await _render_frames(35)
	for step: int in range(90):
		var ratio := float(step) / 89.0
		_place(12.0 - 11.6 * ratio, lerpf(-6.5, 6.5, ratio), lerpf(6.5, -6.5, ratio), 4.0 if players == 2 else 0.0)
		await _render_frames(1)
		_validate("p%d_approach_%d" % [players, step], step in [0, 45, 89])
	await _capture("p%d_near" % players)
	_check_aspect_ratios(players)
	var wall: Node3D = _world._question_framing_wall
	var label: Label3D = wall.gameplay_question_label
	var label_id := label.get_instance_id()
	await _render_frames(12)
	_check(label_id == wall.gameplay_question_label.get_instance_id(), "label reused")
	_gs.current_quiz = original
	# Releasing the question must not leave old text in the scene.
	for state: String in [Constants.STATE_CORRECT, Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		_gs.game_state = state
		_world._update_wall_question()
		_check(_visible_questions() == 0, "hidden in " + state)
	_gs.game_state = Constants.STATE_PLAYING


func _check_aspect_ratios(players: int) -> void:
	# Use the engine's real Camera3D projection without resizing the user's window.
	var controller: Node3D = _world.camera_controller
	var original_camera: Camera3D = controller.camera
	var original_back: float = controller._question_back
	var original_pitch: float = controller._question_pitch
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var aspect_camera := Camera3D.new()
	viewport.add_child(aspect_camera)
	controller.camera = aspect_camera
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1920, 1080)]:
		viewport.size = size
		for frame: int in range(40):
			controller.update_camera(_gs, 1.0 / 60.0)
		_validate("p%d_aspect_%dx%d" % [players, size.x, size.y])
	controller.camera = original_camera
	controller._question_back = original_back
	controller._question_pitch = original_pitch
	viewport.queue_free()


func _cross_doors(players: int) -> void:
	phase = "p%d_crossings" % players
	_world.set_process(true)
	for step: int in range(10):
		var index := _gs.current_wall_index
		if index == 9:
			_gs.current_quiz = _gs.current_quiz.duplicate(true)
			_gs.current_quiz.q = "公園に子どもが12人いて、そのうち3人が帰り、あとから5人が来ました。今、公園にいる子どもは全部で何人でしょうか？"
		var answer := _gs.current_quiz.a
		var xs: Array = Array(_gs.tuning.door4_xs) if _gs.num_choices == 4 else [_gs.tuning.left_door_x, _gs.tuning.right_door_x]
		_place(7.0, xs[answer] + (0.35 if players == 2 else 0.0), xs[answer] - 0.35, 0.0)
		var deadline := Time.get_ticks_msec() + 10000
		var captured := false
		while _gs.current_wall_index == index and _gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if not captured and _gs.wall_z - _gs.player_z < 4.0:
				_validate("p%d_door%d" % [players, index])
				if _gs.num_choices == 4 or step == 0:
					await _capture("p%d_door%d" % [players, index])
				captured = true
		_check(_gs.current_wall_index == index + 1 and _gs.p1_alive and (players == 1 or _gs.p2_alive), "correct crossing p%d wall%d" % [players, index])
		if _gs.current_wall_index == index:
			break
		for frame: int in range(6):
			await get_tree().process_frame
		if _gs.game_state == Constants.STATE_PLAYING:
			_validate("p%d_next%d" % [players, index])
	_check(_gs.game_state in [Constants.STATE_GOAL_RACE, Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR], "boss correct reaches goal")
	_check(_visible_questions() == 0, "goal hides question")
	_world.set_process(false)
	# Let the goal/door effect callbacks finish before replacing their scene.
	await get_tree().create_timer(3.0).timeout


func _wrong_door_case(players: int) -> void:
	phase = "p%d_retry_wrong" % players
	_world.set_process(true)
	# Wrong-door path, including 2P simultaneous elimination.
	if _gs.current_quiz != null and _gs.game_state == Constants.STATE_PLAYING:
		var wrong := (_gs.current_quiz.a + 1) % _gs.num_choices
		var wrong_x: float = _gs.tuning.door4_xs[wrong] if _gs.num_choices == 4 else (_gs.tuning.left_door_x if wrong == 0 else _gs.tuning.right_door_x)
		_place(3.0, wrong_x + (0.35 if players == 2 else 0.0), wrong_x - 0.35, 0.0)
		var deadline := Time.get_ticks_msec() + 7000
		while _gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		await get_tree().process_frame
		_check(_gs.game_state == Constants.STATE_GAME_OVER, "wrong door game over")
		_check(_visible_questions() == 0, "game over question hidden")
		await _capture("p%d_wrong" % players)
		await get_tree().create_timer(3.0).timeout
	_world.set_process(false)


func _mode_case(players: int, mode: String) -> void:
	phase = "p%d_%s" % [players, mode]
	if mode == Constants.MODE_TUTORIAL:
		_world._update_wall_question()
		_check(_visible_questions() == 0, "tutorial movement has no question")
		var steps := 0
		while not _gs.tutorial_flow.is_quiz_step() and steps < 12:
			_gs._advance_tutorial_step()
			steps += 1
		_gs.tutorial_flow.presentation_locked = true
		_world._update_walls()
		_world._update_wall_question()
		_check(_visible_questions() == 0, "tutorial presentation hides question")
		_gs.complete_tutorial_presentation()
		_world._tutorial_presentation_director.update(0.0)
		_world.camera_controller.clear_tutorial_override()
	_place(3.0, 3.5, -3.5, 3.0 if players == 2 else 0.0)
	await _render_frames(40)
	_validate(phase)
	if mode == Constants.MODE_COOP:
		var label: Label3D = _world._question_framing_wall.gameplay_question_label
		_check(label.text.contains(_gs.current_quiz.coop_p1_label) and label.text.contains(_gs.current_quiz.coop_p2_label), "coop role labels retained")
	await _capture(phase)


func _place(distance: float, p1_x: float, p2_x: float, separation: float) -> void:
	_gs.world_scroll_z = _gs.wall_z - distance
	_gs.player_z = _gs.wall_z - distance
	_gs.player2_z = _gs.player_z - separation
	_gs.player_x = p1_x
	_gs.player2_x = p2_x
	_gs.player_y = 0.0
	_gs.player2_y = 0.0
	_gs.player_vel_z = 0.0
	_gs.player2_vel_z = 0.0
	_gs.camera_shake = 0.0


func _render_frames(count: int) -> void:
	for frame: int in range(count):
		_world._update_player(1.0 / 60.0)
		_world._update_walls()
		_world._update_wall_question()
		_world._update_camera(1.0 / 60.0)
		await get_tree().process_frame


## Wall height as laid out at 1x text, so cases sampled at different 2P
## camera distances (and text scales) stay comparable.
func _base_scale_wall_top(wall: Node3D) -> float:
	return 2.56 + (wall.wall_top_y - 0.18 - 2.56) / wall._text_scale + 0.18


func _visible_questions() -> int:
	var count := 0
	for wall: Node3D in _world._active_walls:
		if is_instance_valid(wall.gameplay_question_label) and wall.gameplay_question_label.is_visible_in_tree():
			count += 1
	return count


func _validate(label: String, record: bool = true) -> void:
	_check(_visible_questions() == 1, label + " exactly one question")
	var wall: Node3D = _world._question_framing_wall
	if not is_instance_valid(wall) or not is_instance_valid(wall.gameplay_question_label):
		_fail(label + " missing current question")
		return
	var question: Label3D = wall.gameplay_question_label
	_check(int(wall.get_meta("wall_index")) == _gs.current_wall_index, label + " current wall")
	_check(question.text.begins_with(FractionFormatter.format_question(_gs.current_quiz.q)), label + " complete formatted text")
	var glyph_bounds := question.transform * question.get_aabb()
	var panel: MeshInstance3D = question.get_node("QuestionBorder")
	var panel_bounds: AABB = (question.transform * panel.transform) * panel.get_aabb()
	_check(absf(panel_bounds.position.y - (2.38 + 0.18)) < 0.01, label + " panel immediately above doors")
	_check(glyph_bounds.position.y > 2.38 and panel_bounds.end.y < wall.wall_top_y, label + " question inside wall")
	var beam: MeshInstance3D = wall.wall_parts[0]
	var actual_top: float = (beam.transform * beam.get_aabb()).end.y
	# The two-line reserve grows with the 2P camera-distance text scale.
	var content_top := maxf(panel_bounds.end.y, 2.56 + (4.474 - 2.56) * wall._text_scale)
	if wall.is_boss:
		var heading: Label3D = wall.boss_label
		content_top = (heading.transform * heading.get_aabb().grow(heading.outline_size * heading.pixel_size)).end.y
	_check(absf(actual_top - content_top - 0.18) < 0.01, label + " small top margin")
	var camera: Camera3D = _world.camera_controller.camera
	var points: PackedVector3Array = wall.get_gameplay_framing_points()
	_check(points.size() >= 16, label + " measured glyph bounds")
	if _gs.p1_alive:
		_world.camera_controller._append_player_framing_points(points, Vector3(_gs.player_x, _gs.player_y, _gs.player_local_z))
	if _gs.num_players >= 2 and _gs.p2_alive:
		_world.camera_controller._append_player_framing_points(points, Vector3(_gs.player2_x, _gs.player2_y, _gs.player2_local_z))
	var size := camera.get_viewport().get_visible_rect().size
	var rect := Rect2(Vector2.INF, Vector2.ZERO)
	var first := true
	for point: Vector3 in points:
		_check(not camera.is_position_behind(point), label + " in front of camera")
		var uv := camera.unproject_position(point) / size
		rect = Rect2(uv, Vector2.ZERO) if first else rect.expand(uv)
		first = false
	_check(rect.position.x >= 0.075 and rect.position.y >= 0.075 and rect.end.x <= 0.925 and rect.end.y <= 0.925, label + " screen margin " + str(rect))
	if _gs.num_choices == 4:
		_check(is_instance_valid(wall.boss_label), label + " boss heading present")
		var boss_bounds: AABB = wall.boss_label.transform * wall.boss_label.get_aabb()
		_check(boss_bounds.position.y > panel_bounds.end.y and boss_bounds.end.y < wall.wall_top_y, label + " boss heading above question inside wall")
	if record:
		samples.append({"label": label, "mode": _gs.mode, "players": _gs.num_players, "wall": _gs.current_wall_index, "choices": _gs.num_choices, "text": question.text, "glyph_bounds": str(glyph_bounds), "screen_rect": str(rect), "camera_back": _world.camera_controller._question_back})


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + label + ".png")


func _check(passed: bool, message: String) -> void:
	if not passed:
		_fail(message)


func _fail(message: String) -> void:
	if message not in failures:
		failures.append(message)
		push_error("WALL_QUESTION_FAIL " + message)
