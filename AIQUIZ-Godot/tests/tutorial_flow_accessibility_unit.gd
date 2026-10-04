extends SceneTree

## 刷新したチュートリアル（V5）のコース・入力・判定・引き継ぎの契約。
## コースは本編（3ハート、2択／4択の壁、ローカル2Pののこぎり・先着の得点・スコアタワー）に合わせ、
## 操作のステップでは各タスクの "slots" をもとに 3D 空間へ操作キーを浮かべる。
## 開始前の全画面キーボード説明は tutorial_keyboard_intro_unit.gd、ゲーム状態での判定は
## tutorial_rules_bootstrap.gd、実ゲームでの通し確認は tutorial_renewal_bootstrap.gd が担当する。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_flow_accessibility_unit.gd

const SOLO_STEPS := [
	"run_lane", "air_control", "solo_emote", "ocean_lesson", "guided_wall",
	"hp_lesson", "free_wall", "boss_wall", "stage_complete", "customize_tour",
]
const DUO_STEPS := [
	"duo_run", "duo_push", "duo_air", "duo_emote", "duo_ocean", "duo_ghost", "duo_saw",
	"duo_guided_wall", "duo_hp", "duo_free_wall", "duo_boss_wall", "duo_goal", "duo_complete",
	"customize_tour",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var solo: RefCounted = load("res://scripts/core/tutorial/solo_tutorial_flow.gd").new()
	var duo: RefCounted = load("res://scripts/core/tutorial/duo_tutorial_flow.gd").new()
	_test_course(solo, SOLO_STEPS)
	_test_course(duo, DUO_STEPS)
	_test_key_metadata(solo, false)
	_test_key_metadata(duo, true)
	_test_solo_inputs(solo)
	_test_duo_inputs(duo)
	_test_quiz_items(solo)
	_test_quiz_items(duo)
	_test_hp_flags(solo, ["guided_wall", "hp_lesson", "free_wall", "boss_wall"], ["free_wall", "boss_wall"])
	_test_hp_flags(duo, ["duo_guided_wall", "duo_hp", "duo_free_wall", "duo_boss_wall", "duo_goal"], ["duo_free_wall", "duo_boss_wall"])
	_test_saw_lesson(duo)
	for file: String in ["tutorial_coach_bar", "solo_tutorial_overlay", "duo_tutorial_overlay", "gameplay_hud", "tutorial_course_selector", "tutorial_completion_card"]:
		var source: Script = load("res://scripts/ui/" + file + ".gd")
		_check(source != null and source.can_instantiate(), "UI script loads: " + file)
	for file: String in ["tutorial_keycap_3d", "tutorial_key_guides_3d", "solo_tutorial_guides", "duo_tutorial_guides", "ghost_shark_ride_controller"]:
		var world_script: Script = load("res://scripts/world/" + file + ".gd")
		_check(world_script != null and world_script.can_instantiate(), "World script loads: " + file)
	print("TUTORIAL_FLOW " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)


# ---------- コース ----------

func _test_course(flow: RefCounted, ids: Array) -> void:
	flow.start()
	_check(flow.step_count() == ids.size(), "%s course has %d steps" % [flow.course, ids.size()])
	_check(not flow.advances_after_countdown(), "Countdown starts the first lesson directly")
	for id: String in ids:
		_check(flow.current_step_id() == id, "Lesson order: " + id + " (got " + flow.current_step_id() + ")")
		var model: Dictionary = flow.get_overlay_model()
		_check(not str(model.get("title", "")).is_empty(), "Overlay title exists: " + id)
		# 差し戻した旧リニューアルの2Dキーボード用メタデータは再導入しない。
		_check(not model.has("focus_task") and not model.has("lesson_kind"), "No in-game 2D keyboard metadata: " + id)
		_check(model.has("key_layout") and model.has("target_door") and model.has("ordered_tasks"), "3D key metadata present: " + id)
		if not flow.is_final_step():
			_check(flow.advance_step(), "Can advance lesson: " + id)
	_check(flow.starts_customize_tour() and flow.is_final_step(), "Final step hands off to customization")
	_check(not flow.advance_step(), "Cannot advance beyond customization")


## 操作を教えるステップは3Dキーの並べ方を持ち、各タスクは押すキー（slots）を持つ。
func _test_key_metadata(flow: RefCounted, duo: bool) -> void:
	flow.start()
	for i: int in flow.step_count():
		var step: Dictionary = flow.current_step()
		var id := str(step.get("id", ""))
		var layout := str(step.get("key_layout", ""))
		var tasks_by_player: Dictionary = {}
		if duo:
			tasks_by_player = step.get("tasks", {})
		else:
			tasks_by_player = {1: step.get("tasks", [])}
		var has_tasks := false
		for player_key: Variant in tasks_by_player.keys():
			for task: Dictionary in tasks_by_player[player_key]:
				has_tasks = true
				if str(task.get("id", "")) == "hit":
					continue
				_check(not (task.get("slots", []) as Array).is_empty(), "%s task %s names its 3D keys" % [id, str(task.get("id", ""))])
		if has_tasks:
			_check(layout in ["cluster", "sides", "ghost"], "%s shows its keys in 3D (%s)" % [id, layout])
		if bool(step.get("input_practice", false)):
			_check(layout == "cluster", "%s practice uses the keyboard cluster" % id)
		if bool(step.get("walls", false)) and not (step.get("quiz_indices", []) as Array).is_empty():
			_check(layout == "sides", "%s steering keys sit beside the runner" % id)
		flow.advance_step()


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


func _test_solo_inputs(flow: RefCounted) -> void:
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
	_seek(flow, "solo_emote")
	_open_gate(flow)
	flow.update_input_practice(Vector2.ZERO, Vector2.ZERO, false, false, 3, 0)
	_check(flow.all_tasks_complete(), "Solo course now teaches emotes")
	_seek(flow, "ocean_lesson")
	_check(flow.allows_ocean_entry(1) and not flow.allows_ocean_entry(2), "Solo ocean belongs to P1")
	_check(not flow.hands_off_to_ghost_after_hazard() and not flow.allows_ghost_ride(), "Solo keeps recovery instead of ghost ride")
	_check(not flow.uses_saw() and not flow.starts_goal_race(), "Solo has no saw and no goal race (1P ends at CLEAR)")


func _test_duo_inputs(flow: RefCounted) -> void:
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
	_check(bool(flow.get_overlay_model().get("ordered_tasks", false)), "Push lesson lights its keys in order")
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
	_check(flow.get_overlay_model().players[0].tasks.is_empty() and flow.get_overlay_model().players[1].tasks.size() == 3, "Ghost overlay owns P2 tasks")
	_check(str(flow.get_overlay_model().get("key_layout", "")) == "ghost", "Ghost keys ride on the shark")
	_seek(flow, "duo_guided_wall")
	_check(not flow.requires_both_correct(), "Guided 2P wall follows first-correct scoring")
	_seek(flow, "duo_boss_wall")
	_check(not flow.revives_players() and flow.allows_ghost_ride(), "Boss wall keeps fallen players as ghost sharks")
	_seek(flow, "duo_goal")
	_check(flow.starts_goal_race() and flow.revives_players() and flow.requires_all_finishers(), "Goal waits for every survivor")


func _test_quiz_items(flow: RefCounted) -> void:
	flow.start()
	var quizzes: Array = flow.build_quiz_items()
	_check(quizzes.size() == flow.target_quiz_count() and quizzes.size() == 5, "%s builds five walls" % flow.course)
	for i: int in quizzes.size():
		var quiz: QuizItem = quizzes[i]
		_check(quiz.a >= 0 and quiz.a < quiz.c.size(), "%s quiz %d has a valid answer" % [flow.course, i])
		_check(flow.choice_count_for_quiz(i) == quiz.c.size(), "%s quiz %d door count matches choices" % [flow.course, i])
		_check(flow.is_boss_quiz(i) == (i == 4), "%s boss wall is the last wall only" % flow.course)
	_check((quizzes[4] as QuizItem).c.size() == 4, "%s boss wall offers A-D" % flow.course)
	while not flow.is_quiz_step():
		flow.advance_step()
	_check(flow.presentation_locked and flow.presentation_id() == "wall_reveal", "First wall keeps its reveal")
	_check(flow.guided_answer() == quizzes[0].a and not flow.punishes_mistakes(), "Guided wall remains forgiving")
	_check(flow.target_door() == quizzes[0].a, "Guided wall steers keys toward the correct door")
	_check(flow.on_quiz_cleared(), "Guided wall is one quiz")
	flow.advance_step()
	_check(flow.is_hp_lesson() and not flow.punishes_mistakes(), "Heart lesson follows the guided wall")
	_check(flow.target_door() == 1 - (quizzes[1] as QuizItem).a, "Heart lesson steers toward the wrong door")
	flow.advance_step()
	_check(flow.punishes_mistakes() and flow.uses_hp_rules() and flow.guided_answer() == -1, "Free practice uses real heart rules")
	_check(flow.quiz_index() == 2 and not flow.on_quiz_cleared() and flow.quiz_index() == 3, "Free practice advances through both questions")
	_check(flow.on_quiz_cleared(), "Last free quiz completes step")
	flow.advance_step()
	_check(flow.quiz_index() == 4 and flow.uses_hp_rules(), "Boss wall closes the quiz lessons")


func _test_hp_flags(flow: RefCounted, hp_steps: Array, rule_steps: Array) -> void:
	flow.start()
	for i: int in flow.step_count():
		var id: String = flow.current_step_id()
		if id in ["stage_complete", "duo_complete", "customize_tour"]:
			flow.advance_step()
			continue
		_check(flow.uses_hp() == (id in hp_steps), "%s hearts shown only from the quiz lessons (%s)" % [flow.course, id])
		_check(flow.uses_hp_rules() == (id in rule_steps), "%s real heart rules only in practice (%s)" % [flow.course, id])
		flow.advance_step()


func _test_saw_lesson(flow: RefCounted) -> void:
	flow.start()
	for i: int in flow.step_count():
		var id: String = flow.current_step_id()
		var expect_saw := id in ["duo_saw", "duo_guided_wall", "duo_hp", "duo_free_wall", "duo_boss_wall"]
		_check(flow.uses_saw() == expect_saw, "Saw chases only from its lesson to the boss wall (%s)" % id)
		flow.advance_step()
	_seek(flow, "duo_saw")
	_check(flow.is_saw_lesson() and bool(flow.get_overlay_model().get("ordered_tasks", false)), "Saw lesson is ordered")
	_open_gate(flow)
	_check(not flow.update_saw_lesson(0.0, 0.0, 0.1), "Standing still does not finish the saw lesson")
	flow.update_saw_lesson(0.3, 0.1, 0.1)
	_check(flow.is_task_done(1, "saw_approach") and not flow.is_task_done(2, "saw_approach"), "Each player must reach the warning")
	flow.update_saw_lesson(0.0, 0.3, 0.1)
	_check(not flow.is_task_done(1, "saw_escape"), "Escape needs a short hold outside the warning")
	flow.update_saw_lesson(0.0, 0.0, 0.4)
	flow.update_saw_lesson(0.0, 0.0, 0.4)
	_check(flow.is_task_done(1, "saw_escape") and flow.is_task_done(2, "saw_escape"), "Both escape after backing away")
	var finished := false
	for i: int in range(4):
		finished = finished or flow.update_saw_lesson(0.0, 0.0, 0.2)
	_check(finished, "Saw lesson completes after the hold")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
