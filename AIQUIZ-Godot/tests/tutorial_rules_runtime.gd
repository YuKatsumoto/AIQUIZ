extends Node

## 刷新したチュートリアル（V6）の判定を QuizGameState で直接確かめる（描画なし）。
## ハート体験・誘導なしの実践・4択のボス壁・先着の得点・のこぎり・全員ゴール・
## ゴール後のスコアタワー（得点説明の一時停止と勝敗発表）を、
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
	_test_duo_ghost_target_falls()
	_test_duo_saw_and_goal()
	_test_duo_score_tower()
	_test_duo_score_tower_draw()
	_test_duo_score_tower_ghost()
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


## ゴーストシャーク練習で標的（P1）が体当たりで海へ落ちても、ゴースト（P2）は脱落したまま
## 練習を続けられる。ステップ全体をやり直すとP2まで復活し、サメが二度と出ずに進行不能になる。
func _test_duo_ghost_target_falls() -> void:
	var gs := _tutorial_state("LOCAL_2P", 2)
	if not _seek_state(gs, "duo_ocean"):
		return
	gs.player2_x = -30.0
	_check(_step_until(gs, func() -> bool: return gs.p2_waiting_for_shark, 6.0), "P2 drops into the ocean lesson")
	gs.complete_ocean_shark_attack(2)
	_check(gs.get_tutorial_step_id() == "duo_ghost" and not gs.p2_alive, "Shark hands P2 over to the ghost practice")
	gs.register_tutorial_ghost_aim(2)
	gs.register_tutorial_ghost_charge(2, false, 0.5)
	gs.player_x = 30.0
	_check(_step_until(gs, func() -> bool: return gs.player_x < 10.0, 6.0), "Knocked-off P1 comes back to the course")
	_step(gs, 0.5)
	_check(gs.get_tutorial_step_id() == "duo_ghost", "Ghost practice continues after P1 falls")
	_check(gs.p1_alive and not gs.p1_fall_committed, "P1 is back on the course")
	_check(not gs.p2_alive, "P2 stays a ghost so the shark keeps flying")
	_check(gs.tutorial_flow.is_task_done(2, "aim") and gs.tutorial_flow.is_task_done(2, "charge"), "Ghost tasks already done are kept")
	_check(gs.register_tutorial_ghost_charge(2, true, 0.8), "A later hit still finishes the ghost practice")


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
	# 演出を使えないとき（result_ceremony_enabled = false）は従来どおり完了ステップへ進む。
	_check(not gs.uses_local_result_ceremony(), "Ceremony gate off: no score tower")
	_check(gs.get_tutorial_step_id() == "duo_complete", "Course ends once every survivor finishes")


# ---------- ゴール後のスコアタワー（勝敗判定）と得点説明 ----------

const DT := 1.0 / 60.0


## 2人をゴール前に立たせ、指定した正解数とハートでゴールステップを始める。
func _goal_state(p1_correct: int, p1_hp: int, p2_correct: int, p2_hp: int) -> QuizGameState:
	var gs := _tutorial_state("LOCAL_2P", 2)
	gs.result_ceremony_enabled = true
	if not _seek_state(gs, "duo_goal"):
		return gs
	gs.score = p1_correct
	gs.player2_score = p2_correct
	gs._set_player_hp(1, p1_hp)
	gs._set_player_hp(2, p2_hp)
	return gs


func _step(gs: QuizGameState, seconds: float) -> void:
	for i: int in range(int(round(seconds / DT))):
		gs.update(DT)


func _step_until(gs: QuizGameState, condition: Callable, limit_seconds: float) -> bool:
	for i: int in range(int(limit_seconds / DT)):
		if condition.call():
			return true
		gs.update(DT)
	return condition.call()


func _finish_both(gs: QuizGameState) -> void:
	gs.player_z = gs.goal_z + 0.1
	gs.player2_z = gs.goal_z + 0.1
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.update(DT)


func _test_duo_score_tower() -> void:
	# P1: 3問 × (2 + 0.5) = 7.5、P2: 2問 × (3 + 0.5) = 7 → P1 の勝ち。
	var gs := _goal_state(3, 2, 2, 3)
	_check(gs.uses_local_result_ceremony() and gs.uses_tutorial_result_ceremony(), "2P tutorial goal uses the score tower")
	_check(not gs.uses_sudden_death(), "Tutorial never branches into the sudden death")
	gs.player_z = gs.goal_z + 0.1
	gs.player2_z = gs.goal_z - 20.0
	gs.update(DT)
	_check(gs.game_state == Constants.STATE_GOAL_RACE and gs.has_player_reached_goal(1), "First finisher waits at the goal")
	_check(gs.tutorial_flow.is_task_done(1, "goal") and not gs.tutorial_flow.is_task_done(2, "goal"), "Goal task follows each arrival")
	gs.player2_z = gs.goal_z + 0.1
	gs.update(DT)
	_check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_presentation_active, "Both finishers start the score tower")
	_check(gs.get_tutorial_step_id() == "duo_goal", "Tutorial stays on the goal step during the tower")
	_check(gs.result_p1_score == 15 and gs.result_p2_score == 14 and gs.result_winner == 1, "Tower scores use correct × (hearts + 0.5)")
	_check(_step_until(gs, gs.is_tutorial_score_pause_active, 9.0), "Ceremony pauses once the scores are tallied")
	_check(
		absf(gs.result_ceremony_elapsed - QuizGameState.RESULT_VERDICT_TIME + QuizGameState.RESULT_VERDICT_DURATION) < 0.001,
		"Pause sits at the end of the score roll (%.3f s)" % gs.result_ceremony_elapsed
	)
	_check(gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.VERDICT, "Pause happens before the verdict is shown")
	_check(gs.get_result_formula_text(1) == "P1: 3 × 2.5 = 7.5" and gs.get_result_formula_text(2) == "P2: 2 × 3.5 = 7", "Explanation shows each player's formula")
	_check(not gs.resume_tutorial_score_pause(), "Resume waits for the minimum reading time")
	var frozen := gs.result_ceremony_elapsed
	_step(gs, 3.0)
	_check(gs.is_tutorial_score_pause_active() and is_equal_approx(gs.result_ceremony_elapsed, frozen), "Pause holds until a key is pressed")
	_check(gs.resume_tutorial_score_pause(), "Key press resumes after the minimum time")
	_check(not gs.is_tutorial_score_pause_active(), "Explanation closes on resume")
	_check(_step_until(gs, func() -> bool: return gs.get_tutorial_step_id() == "duo_complete", 6.0), "Verdict and winner lead to the completion step")
	_check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_presentation_active, "Completion card stays on the podium")
	_check(gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.WINNER, "Tutorial never reaches the result buttons")
	_check(gs.tutorial_flow.presentation_locked, "Completion card presentation runs")
	var elapsed := gs.result_ceremony_elapsed
	_step(gs, 1.0)
	_check(is_equal_approx(gs.result_ceremony_elapsed, elapsed) and gs.game_state != Constants.STATE_CLEAR, "Ceremony stays frozen under the card")
	gs.complete_tutorial_presentation()
	_check(gs.get_tutorial_step_id() == "customize_tour", "Completion card hands off to the customize tour")
	_check(not gs.result_presentation_active, "Handoff clears the ceremony")


func _test_duo_score_tower_draw() -> void:
	# 2人とも 2問 × (3 + 0.5) = 7 → 引き分け。本編のサドンデスが有効でも分岐しない。
	var gs := _goal_state(2, 3, 2, 3)
	var previous_available := gs.sudden_death_available
	gs.sudden_death_available = true
	gs.sudden_death_enabled = true
	_check(not gs.uses_sudden_death(), "Sudden death stays off in the tutorial even when enabled")
	_finish_both(gs)
	_check(gs.result_winner == 0 and not gs.sudden_death_pending, "Tied tutorial tower is a plain draw")
	_check(_step_until(gs, gs.is_tutorial_score_pause_active, 9.0), "Draw also pauses for the explanation")
	_step(gs, 1.1)
	_check(gs.resume_tutorial_score_pause(), "Draw resumes after the minimum time")
	_check(_step_until(gs, func() -> bool: return gs.get_tutorial_step_id() == "duo_complete", 6.0), "Draw verdict leads to the completion step")
	gs.sudden_death_available = previous_available


func _test_duo_score_tower_ghost() -> void:
	# P2 がゴール前に脱落 → ゴーストとして表彰台へ。得点は正解数だけ。
	var gs := _goal_state(2, 3, 4, 2)
	gs.player_z = gs.goal_z + 0.1
	gs.player_y = 0.0
	gs.update(DT)
	gs.p2_alive = false
	gs.player2_game_over_timer = 0.01
	_check(_step_until(gs, func() -> bool: return gs.game_state == Constants.STATE_RESULT_CEREMONY, 6.0), "Fallen player's ghost joins the tower")
	_check(gs.is_result_ghost(2) and gs.result_p2_score == 8 and gs.result_p1_score == 14, "Ghost scores correct answers only")
	_check(gs.tutorial_flow.is_task_done(2, "goal"), "Ghost arrival closes the fallen player's goal task")
	_check(gs.get_result_formula_text(2) == "P2: 4 (脱落) = 4", "Explanation marks the eliminated player")
	_check(_step_until(gs, gs.is_tutorial_score_pause_active, 9.0), "Ghost finale also pauses for the explanation")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
