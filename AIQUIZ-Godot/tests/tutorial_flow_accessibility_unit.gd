extends SceneTree

## The restored in-game tutorial keeps its original course, input and handoff contracts.
## Full-screen keyboard help is tested separately by tutorial_keyboard_intro_unit.gd.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var solo: RefCounted = load("res://scripts/core/tutorial/solo_tutorial_flow.gd").new()
	var duo: RefCounted = load("res://scripts/core/tutorial/duo_tutorial_flow.gd").new()
	_test_course(solo, ["run_lane", "air_control", "ocean_lesson", "guided_wall", "free_wall", "stage_complete", "customize_tour"])
	_test_course(duo, ["duo_run", "duo_push", "duo_air", "duo_emote", "duo_ocean", "duo_ghost", "duo_guided_wall", "duo_free_wall", "duo_goal", "duo_complete", "customize_tour"])
	_test_solo(solo)
	_test_duo(duo)
	_test_quiz(solo, ["7 + 5 = ?", "6 × 3 = ?", "20 - 8 = ?"], ["12", "18", "12"])
	_test_quiz(duo, ["8 + 7 = ?", "5 × 7 = ?", "30 - 12 = ?"], ["15", "35", "18"])
	for file: String in ["tutorial_coach_bar", "solo_tutorial_overlay", "duo_tutorial_overlay", "gameplay_hud", "tutorial_course_selector", "tutorial_completion_card"]:
		var source: Script = load("res://scripts/ui/" + file + ".gd")
		_check(source != null and source.can_instantiate(), "Restored UI script loads: " + file)
	var ghost: Script = load("res://scripts/world/ghost_shark_ride_controller.gd")
	_check(ghost != null and ghost.can_instantiate(), "Restored ghost popup/controller loads")
	print("TUTORIAL_ROLLBACK_FLOW " + JSON.stringify({"checks":checks, "failures":failures, "passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _test_course(flow: RefCounted, ids: Array) -> void:
	flow.start()
	_check(flow.step_count() == ids.size(), "Original course count")
	_check(not flow.advances_after_countdown(), "Countdown starts first lesson directly")
	for id: String in ids:
		_check(flow.current_step_id() == id, "Original lesson order: " + id)
		var model: Dictionary = flow.get_overlay_model()
		_check(not str(model.get("title", "")).is_empty(), "Old overlay title exists: " + id)
		_check(not model.has("focus_task") and not model.has("lesson_kind"), "Renewal UI metadata removed: " + id)
		if not flow.is_final_step():
			_check(flow.advance_step(), "Can advance original lesson: " + id)
	_check(flow.starts_customize_tour() and flow.is_final_step(), "Old final step hands off to customization")
	_check(not flow.advance_step(), "Cannot advance beyond customization")

func _seek(flow: RefCounted, id: String) -> void:
	flow.start()
	for i: int in flow.step_count():
		if flow.current_step_id() == id:
			return
		flow.advance_step()
	_check(false, "Missing step " + id)

func _open_gate(flow: RefCounted) -> void:
	if flow.presentation_locked:
		_check(flow.finish_presentation("probe"), "Presentation can finish")
	_check(not flow.consume_input_gate(Vector2.ZERO, Vector2.ZERO, false, false, 0, 0), "Neutral input releases gate")

func _test_solo(flow: RefCounted) -> void:
	flow.start()
	_open_gate(flow)
	var detached: Dictionary = flow.get_overlay_model()
	detached.tasks[0].done = true
	_check(not flow.get_overlay_model().tasks[0].done, "UI tasks cannot mutate completion")
	flow.update_input_practice(Vector2(-1, 0), Vector2.ZERO, false, false, 0, 0)
	_check(flow.get_overlay_model().tasks[1].done and not flow.all_tasks_complete(), "Solo right can complete before left")
	flow.update_input_practice(Vector2(1, 0), Vector2.ZERO, false, false, 0, 0)
	_check(flow.all_tasks_complete(), "Both solo directions complete")
	_check(flow.update_input_practice(Vector2.ZERO, Vector2.ZERO, false, false, 0, 0, 0.55), "Completion hold still applies")
	_seek(flow, "air_control")
	_open_gate(flow)
	flow.update_input_practice(Vector2(0, 1), Vector2.ZERO, false, false, 0, 0)
	flow.update_input_practice(Vector2(0, -1), Vector2.ZERO, true, false, 0, 0)
	_check(flow.all_tasks_complete(), "Solo forward/back plus jump complete in any order")
	flow.restart_current_step()
	_check(not flow.all_tasks_complete(), "Restart resets tasks")
	_check(flow.consume_input_gate(Vector2.ONE, Vector2.ZERO, true, false, 0, 0), "Held input initially gated")
	flow.tick(0.7)
	_check(not flow.consume_input_gate(Vector2.ONE, Vector2.ZERO, true, false, 0, 0), "Held input cannot lock gate forever")
	_seek(flow, "ocean_lesson")
	_check(flow.allows_ocean_entry(1) and not flow.allows_ocean_entry(2), "Solo ocean belongs to P1")
	_check(not flow.hands_off_to_ghost_after_hazard() and not flow.allows_ghost_ride(), "Solo keeps recovery instead of ghost ride")

func _test_duo(flow: RefCounted) -> void:
	flow.start()
	_open_gate(flow)
	flow.update_input_practice(Vector2.ZERO, Vector2(-1, 0), false, false, 0, 0)
	flow.update_input_practice(Vector2.ZERO, Vector2(1, 0), false, false, 0, 0)
	var model: Dictionary = flow.get_overlay_model()
	_check(model.players[1].tasks[0].done and model.players[1].tasks[1].done, "P2 learns independently")
	_check(not flow.all_tasks_complete() and not model.players[0].tasks[0].done, "P2 cannot complete P1 controls")
	flow.update_input_practice(Vector2(-1, 0), Vector2.ZERO, false, false, 0, 0)
	flow.update_input_practice(Vector2(1, 0), Vector2.ZERO, false, false, 0, 0)
	_check(flow.all_tasks_complete(), "Both players must finish directions")
	_seek(flow, "duo_air")
	_open_gate(flow)
	flow.update_input_practice(Vector2(0, 1), Vector2(0, 1), false, false, 0, 0)
	flow.update_input_practice(Vector2(0, -1), Vector2(0, -1), true, true, 0, 0)
	_check(flow.all_tasks_complete(), "Both players retain forward/back plus jump")
	_seek(flow, "duo_push")
	_open_gate(flow)
	flow.on_local_push_event({"kind":"hit", "player":1})
	_check(not flow._push_task_done(1, "push"), "Early push cannot bypass bracing")
	flow.on_local_push_event({"kind":"stalemate"})
	_check(flow._push_task_done(1, "brace") and flow._push_task_done(2, "brace"), "Both players brace")
	flow.on_local_push_event({"kind":"hit", "player":2})
	_check(not flow._push_task_done(2, "push"), "P2 cannot bypass P1 turn")
	flow.on_local_push_event({"kind":"hit", "player":1})
	flow.on_local_push_event({"kind":"hit", "player":2})
	_check(flow.all_tasks_complete(), "Ordered push practice completes")
	_seek(flow, "duo_ocean")
	_check(not flow.allows_ocean_entry(1) and flow.allows_ocean_entry(2), "Hazard practice belongs to P2")
	_check(flow.hands_off_to_ghost_after_hazard() and flow.allows_ghost_ride(), "Ocean hands off to ghost")
	flow.advance_step()
	_check(flow.is_ghost_practice() and flow.designated_ghost_player() == 2, "Only P2 practices ghost")
	_check(flow.get_overlay_model().players[0].tasks.is_empty() and flow.get_overlay_model().players[1].tasks.size() == 3, "Old ghost overlay owns P2 tasks")
	_seek(flow, "duo_goal")
	_check(flow.starts_goal_race() and flow.revives_players(), "Goal race revives both players")

func _test_quiz(flow: RefCounted, questions: Array, answers: Array) -> void:
	flow.start()
	var quizzes: Array = flow.build_quiz_items()
	_check(quizzes.size() == flow.target_quiz_count(), "Old quiz count matches walls")
	for i: int in quizzes.size():
		_check(quizzes[i].q == questions[i], "Old question restored " + str(i))
		_check(quizzes[i].a == [0, 1, 0][i] and quizzes[i].c[quizzes[i].a] == answers[i], "Old correct answer restored " + str(i))
	while not flow.is_quiz_step():
		flow.advance_step()
	_check(flow.presentation_locked and flow.presentation_id() == "wall_reveal", "First wall still has presentation lock")
	_check(flow.guided_answer() == quizzes[0].a and not flow.punishes_mistakes(), "Guided wall remains forgiving")
	_check(flow.on_quiz_cleared(), "Guided wall is one quiz")
	flow.advance_step()
	_check(flow.punishes_mistakes() and flow.guided_answer() == -1, "Free practice keeps prior failure rules")
	_check(flow.quiz_index() == 1 and not flow.on_quiz_cleared() and flow.quiz_index() == 2, "Free practice advances through both questions")
	_check(flow.on_quiz_cleared(), "Last quiz completes step")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
