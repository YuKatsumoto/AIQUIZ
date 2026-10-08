extends RefCounted

## PV run 2 (local 2P, 理科, AI questions): Start -> two helicopters pick both runners up ->
## the world builds while the AI questions arrive -> flyover -> countdown -> ten walls with
## shoulder pushes at the doors and the eight-blade saw closing in behind a runner who took a
## wrong door (a reverse camera shows it; nobody is caught) -> goal race -> Score Tower finale.
## Recorded segments: heli_pickup, generating, countdown, push_<n>, saw, play, goal, finale.

const GAME_SCENE := "res://scenes/game_world.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
## Per wall, what the runners do: "push" = both take the right door side by side and shoulder
## each other on the way, "one_wrong" = whoever stands on the wrong door's side takes it (and
## falls behind toward the saw; the other one wins the round), "both" = both answer right.
const PLAN := ["push", "both", "one_wrong", "both", "push", "both", "both", "both", "both", "both"]

var kit  # tests/pv/pv_runtime.gd
var generator  # tests/pv/pv_providers.gd GeneratingProvider


func run(runner) -> void:
	kit = runner
	var gs := QuizManager.game_state
	var quizzes: Dictionary = kit.load_quizzes("science34")
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.subject = quizzes.subject
	gs.grade = quizzes.grade
	gs.difficulty = quizzes.difficulty
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.sudden_death_enabled = false
	QuizManager.provider.set_llm_mode("ONLINE")
	gs.llm_mode = "ONLINE"
	generator = kit.generating_provider("science34")
	generator.held = true
	generator.interval_frames = 30
	gs.provider = generator
	await _menu_and_start()
	await _world_intro()
	await _play()
	await _goal_and_finale()
	kit.note("final_state", gs.game_state)
	kit.note("scores", [gs.score, gs.player2_score])


func _menu_and_start() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
	await kit.until(func() -> bool: return kit.menu() != null, 600)
	var menu = kit.menu()
	menu._update_ui()
	var preview = menu._menu_wall_preview
	if preview != null and preview.has_method("sync_menu_player_count"):
		preview.sync_menu_player_count(2)
	await kit.seconds(3.0)
	kit.record("heli_pickup")
	await kit.seconds(0.8)
	menu._menu_exit_in_progress = true
	menu._set_all_buttons_disabled(true)
	menu.settings_panel.visible = false
	await menu._play_start_ui_departure()
	await kit.frames(1)
	var started := bool(preview.begin_game_start_departure(2))
	kit.note("heli_departure_started", started)
	if started:
		await kit.until(func() -> bool:
			return not bool(preview.is_game_start_departure_active()) or bool(preview.is_ready_for_scene_cover()), 60 * 25)
	await menu._begin_scene_change(GAME_SCENE, true, "")


func _world_intro() -> void:
	var gs := QuizManager.game_state
	await kit.until(func() -> bool: return kit.world() != null, 60 * 30)
	kit.record("generating")
	var world = kit.world()
	await kit.until(func() -> bool: return not SceneTransition.is_transitioning(), 60 * 20)
	await kit.seconds(0.8)
	generator.release()
	var ready: bool = await kit.until(func() -> bool:
		return gs.game_state == Constants.STATE_WAITING_START and not SceneTransition.is_transitioning() \
			and not world.is_start_presentation_locked() and not world.is_preload_construction_locked() \
			and bool(world._barrier_spawned_for_session) and not bool(world._barrier_dropping), 60 * 90)
	kit.note("waiting_start_reached", ready)
	await kit.seconds(1.2)
	kit.record("countdown")
	await kit.tap(KEY_ENTER, 2)
	await kit.until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 60 * 20)
	kit.record("play")


func _play() -> void:
	var gs := QuizManager.game_state
	var outcomes: Array = []
	var laggard := 0
	while true:
		if gs.game_state != Constants.STATE_PLAYING or gs.current_quiz == null:
			break
		if gs.current_wall_index >= PLAN.size():
			break
		var index := gs.current_wall_index
		var plan: String = PLAN[index]
		var targets := _targets(plan)
		laggard = int(targets[2])
		# Lambdas capture locals by value, so the per-wall counters live in a dictionary.
		var state := {"frame": 0, "pushed": false}
		if plan == "push":
			kit.record("push_%d" % index)
		var done: bool = await kit.until(func() -> bool:
			state.frame += 1
			if plan == "push" and not state.pushed and state.frame > 70:
				state.pushed = true
				# A low side camera beside the pair for the shoulder hits.
				var mid := (gs.player_z + gs.player2_z) * 0.5 - gs.world_scroll_z
				var mid_x := (gs.player_x + gs.player2_x) * 0.5
				kit.aim(Vector3(mid_x + 5.5, 1.7, mid - 1.5), Vector3(mid_x, 1.0, mid + 1.0), 42.0)
				_push_sequence()
			if plan == "push" and state.pushed and state.frame == 70 + 110:
				kit.release_camera()
			if not (plan == "push" and state.pushed and state.frame < 70 + 75):
				kit.steer(1, targets[0])
				kit.steer(2, targets[1])
			return gs.current_wall_index != index or gs.game_state != Constants.STATE_PLAYING, 60 * 45)
		kit.release_keys()
		outcomes.append({"wall": index, "plan": plan, "laggard": laggard, "passed": done, "scores": [gs.score, gs.player2_score],
			"hp": [gs.p1_hp, gs.p2_hp], "alive": [gs.p1_alive, gs.p2_alive]})
		if plan == "push":
			kit.record("play")
		if plan == "one_wrong" and gs.game_state == Constants.STATE_PLAYING:
			await _saw_shot(laggard)
	kit.note("walls", outcomes)


## [p1_x, p2_x, laggard] for the current wall. Sharing a door, each keeps the side it is on
## (they cannot pass through each other); "one_wrong" sends the runner already on the wrong
## door's side through it.
func _targets(plan: String) -> Array:
	var gs := QuizManager.game_state
	var right: float = kit.correct_door_x()
	var wrong: float = kit.wrong_door_x()
	var p1_side := 1.0 if gs.player_x >= gs.player2_x else -1.0
	if plan == "one_wrong":
		if (wrong - right) * (gs.player2_x - gs.player_x) >= 0.0:
			return [right, wrong, 2]
		return [wrong, right, 1]
	return [right + 0.55 * p1_side, right - 0.55 * p1_side, 0]


## P1 and P2 press toward each other, then P1 releases and presses again (a shoulder hit),
## then P2 answers (tests/local_push_runtime.gd _shoulder_sequence).
func _push_sequence() -> void:
	var gs := QuizManager.game_state
	var toward_p2: Key = KEY_D if gs.player_x > gs.player2_x else KEY_A
	var toward_p1: Key = KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT
	kit.key(toward_p2, true)
	kit.key(toward_p1, true)
	await kit.seconds(0.55)
	kit.key(toward_p2, false)
	kit.key(toward_p2, true)
	await kit.seconds(0.4)
	kit.key(toward_p1, false)
	kit.key(toward_p1, true)
	await kit.seconds(0.3)
	kit.key(toward_p2, false)
	kit.key(toward_p1, false)


## After the wrong door: a camera above the right rear of the blade row looks forward along it, the
## spinning blades large in the foreground and both runners fleeing for the next wall's right door
## (framing picked with shots/cam_test.gd).
func _saw_shot(laggard: int) -> void:
	var gs := QuizManager.game_state
	var lead_local := maxf(gs.player_z, gs.player2_z) - gs.world_scroll_z
	var saw_z: float = gs.saw.local_z if gs.saw != null else lead_local - 14.0
	var base := Vector3(0.0, 0.0, saw_z)
	kit.record("saw")
	kit.aim(base + Vector3(6.5, 3.2, -2.5), base + Vector3(-1.5, -1.0, 7.0), 58.0)
	var index := gs.current_wall_index
	var targets := _targets("both")
	await kit.until(func() -> bool:
		kit.steer(1, targets[0])
		kit.steer(2, targets[1])
		return gs.current_wall_index != index or gs.game_state != Constants.STATE_PLAYING, int(60 * 3.5))
	kit.release_camera()
	kit.note("saw_shot", {"laggard": laggard, "p1_alive": gs.p1_alive, "p2_alive": gs.p2_alive,
		"z": [gs.player_z - gs.world_scroll_z, gs.player2_z - gs.world_scroll_z], "saw_local_z": gs.saw.local_z if gs.saw != null else 0.0})
	kit.record("play")


func _goal_and_finale() -> void:
	var gs := QuizManager.game_state
	kit.record("goal")
	await kit.until(func() -> bool:
		var racing := gs.game_state == Constants.STATE_GOAL_RACE
		kit.key(KEY_W, racing)
		kit.key(KEY_UP, racing)
		return gs.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR, Constants.STATE_GAME_OVER], 60 * 60)
	kit.release_keys()
	kit.record("finale")
	await kit.seconds(14.0)


func get_tree() -> SceneTree:
	return kit.get_tree()
