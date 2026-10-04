extends Node

## 刷新したチュートリアル（V5）の判定を QuizGameState で直接確かめる（描画なし）。
## ハート体験・誘導なしの実践・4択のボス壁・先着の得点・のこぎり・全員ゴールを、
## 壁に当たったときの本物の処理（resolve_collision など）で進める。
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_rules_bootstrap.gd

## 問題バンクを読まない最小のプロバイダー（ネットワーク・ディスクに触れない）。
class TutorialTestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	QuizManager.player_analytics = null
	_test_solo_state_rules()
	_test_duo_state_rules()
	_test_duo_saw_and_goal()
	print("TUTORIAL_RULES " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------- 実際の判定（QuizGameState） ----------

func _tutorial_state(course: String, players: int) -> QuizGameState:
	var gs := QuizGameState.new(TutorialTestProvider.new())
	gs.num_players = players
	gs.saw_transport_enabled = players == 2
	gs.start_tutorial(course)
	gs.game_state = Constants.STATE_PLAYING
	_check(gs.tutorial_flow != null and gs.get_tutorial_step_id() != "", "%s state fixture starts" % course)
	return gs


func _seek_state(gs: QuizGameState, id: String) -> bool:
	for i: int in range(20):
		if gs.get_tutorial_step_id() == id:
			if gs.tutorial_flow.presentation_locked:
				gs.tutorial_flow.finish_presentation()
			return true
		gs._advance_tutorial_step()
	_check(false, "state reaches " + id)
	return false


func _hit_wall(gs: QuizGameState, p1_x: float, p2_x: float = NAN) -> void:
	gs.player_x = p1_x
	gs.player_z = gs.wall_z
	if gs.num_players >= 2:
		if is_nan(p2_x):
			gs.player2_z = gs.wall_z - 6.0
		else:
			gs.player2_x = p2_x
			gs.player2_z = gs.wall_z
	gs.resolve_collision(true, gs.num_players >= 2 and not is_nan(p2_x))


func _test_solo_state_rules() -> void:
	var gs := _tutorial_state("SOLO", 1)
	_check(not gs.uses_hp(), "Solo hearts stay hidden during the control lessons")
	if not _seek_state(gs, "guided_wall"):
		return
	_check(gs.uses_hp() and gs.p1_hp == 3, "Solo hearts appear at the first wall")
	_check(gs.num_choices == 2 and not gs.is_boss_index(0), "Guided wall has two doors")
	_hit_wall(gs, gs.tuning.right_door_x)
	_check(gs.get_tutorial_step_id() == "guided_wall" and gs.p1_hp == 3, "Guided miss retries without losing a heart")
	_hit_wall(gs, gs.tuning.left_door_x)
	_check(gs.get_tutorial_step_id() == "hp_lesson" and gs.score == 1, "Guided correct answer scores and continues")
	_hit_wall(gs, gs.tuning.left_door_x)
	_check(gs.get_tutorial_step_id() == "hp_lesson" and gs.p1_hp == 3, "Heart lesson asks for the wrong door instead")
	_hit_wall(gs, gs.tuning.right_door_x)
	_check(gs.get_tutorial_step_id() == "free_wall" and gs.p1_hp == 2, "Heart lesson costs exactly one heart")
	_check(gs.is_damage_stunned(1), "Heart loss staggers the runner like the real game")
	var wall := gs.current_wall_index
	_hit_wall(gs, gs.tuning.left_door_x)
	_check(gs.p1_hp == 1 and gs.p1_alive and gs.current_wall_index == wall + 1, "Free miss costs a heart and the run continues")
	_hit_wall(gs, gs.tuning.right_door_x)
	_check(gs.p1_hp == 0 and not gs.p1_alive and gs.tutorial_flow.is_awaiting_death_recovery(), "Zero hearts eliminates the runner")
	gs._recover_tutorial_from_death()
	_check(gs.p1_alive and gs.p1_hp == 3 and gs.get_tutorial_step_id() == "free_wall", "Elimination retries the same question with full hearts")
	_hit_wall(gs, gs.tuning.left_door_x)
	_check(gs.get_tutorial_step_id() == "boss_wall", "Correct retry reaches the boss wall")
	_check(gs.num_choices == 4 and gs.is_boss_index(gs.current_index), "Boss wall uses four doors")
	_hit_wall(gs, float(gs.tuning.door4_xs[gs.current_quiz.a]))
	_check(gs.get_tutorial_step_id() == "stage_complete", "Boss answer completes the solo stage")


func _test_duo_state_rules() -> void:
	var gs := _tutorial_state("LOCAL_2P", 2)
	if not _seek_state(gs, "duo_guided_wall"):
		return
	_check(gs.uses_saw_chase(), "2P saw runs during the quiz lessons")
	_hit_wall(gs, gs.tuning.left_door_x)
	_check(gs.get_tutorial_step_id() == "duo_hp" and gs.score == 1 and gs.player2_score == 0, "First correct player alone scores and opens the wall")
	gs.player2_z = gs.wall_z - 6.0
	_hit_wall(gs, gs.tuning.right_door_x)
	_check(gs.get_tutorial_step_id() == "duo_hp" and gs.p1_hp == 2 and gs.p2_hp == 3, "P1 waits at the wall after the lesson miss")
	_hit_wall(gs, gs.tuning.right_door_x, gs.tuning.right_door_x)
	_check(gs.get_tutorial_step_id() == "duo_free_wall" and gs.p1_hp == 2 and gs.p2_hp == 2, "Both lesson misses cost one heart each")
	var answer: int = gs.current_quiz.a
	var correct_x: float = gs.tuning.left_door_x if answer == 0 else gs.tuning.right_door_x
	var wrong_x: float = gs.tuning.right_door_x if answer == 0 else gs.tuning.left_door_x
	var wall := gs.current_wall_index
	_hit_wall(gs, wrong_x, correct_x)
	_check(gs.p1_hp == 1 and gs.p2_hp == 2 and gs.player2_score == 1 and gs.current_wall_index == wall + 1, "Wrong P1 loses a heart while P2 takes the point")
	answer = gs.current_quiz.a
	correct_x = gs.tuning.left_door_x if answer == 0 else gs.tuning.right_door_x
	wrong_x = gs.tuning.right_door_x if answer == 0 else gs.tuning.left_door_x
	_hit_wall(gs, wrong_x, wrong_x)
	_check(gs.get_tutorial_step_id() == "duo_boss_wall", "Both wrong still closes the question")
	_check(not gs.p1_alive and gs.p2_alive and gs.p2_hp == 1, "P1 at zero hearts falls while P2 keeps playing")
	_check(not gs.p1_alive and gs.allows_tutorial_ghost_ride(), "Fallen player rides the ghost shark into the boss wall")


func _test_duo_saw_and_goal() -> void:
	var gs := _tutorial_state("LOCAL_2P", 2)
	if not _seek_state(gs, "duo_saw"):
		return
	_check(gs.uses_saw_chase() and gs.is_saw_visible(), "Saw appears for its lesson")
	gs.saw.local_z = gs.player_local_z - 0.4
	gs._update_saw_chase(1.0 / 60.0, Vector2(gs.player_x, gs.player_local_z), Vector2(gs.player2_x, gs.player2_local_z))
	_check(not gs.p1_alive and gs.tutorial_flow.is_awaiting_death_recovery(), "Saw contact ends the attempt regardless of hearts")
	gs._recover_tutorial_from_death()
	_check(gs.p1_alive and gs.p2_alive and gs.saw.local_z <= SawChaseState.INITIAL_Z + 0.001, "Recovery moves the saw back to its start")
	if not _seek_state(gs, "duo_boss_wall"):
		return
	gs.p2_alive = false
	gs._set_player_hp(2, 0)
	if not _seek_state(gs, "duo_goal"):
		return
	_check(gs.game_state == Constants.STATE_GOAL_RACE and gs.p2_alive and gs.p2_hp == 1, "Goal revives a fallen player with one heart")
	_check(not gs.uses_saw_chase(), "Saw stops before the goal")
	gs.player_z = gs.goal_z + 0.1
	gs.player2_z = gs.goal_z - 20.0
	gs._update_goal_race(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, false, false, 0, 0)
	_check(gs.get_tutorial_step_id() == "duo_goal" and gs.has_player_reached_goal(1), "First finisher waits for the other survivor")
	gs.player2_z = gs.goal_z + 0.1
	gs._update_goal_race(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, false, false, 0, 0)
	_check(gs.get_tutorial_step_id() == "duo_complete", "Course ends once every survivor finishes")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
