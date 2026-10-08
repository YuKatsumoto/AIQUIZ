extends RefCounted

## PV run 1 (1P, 算数3年, AI questions): menu settings rows -> Start -> helicopter pickup ->
## the game world builds while "AIクイズ生成中 (n/10)" counts up and walls drop as questions
## arrive -> drop-off -> Enter -> flyover over all ten walls -> countdown -> walls.
## Then every remaining wall is answered right, the runner reaches the goal and the clear
## screen opens the question history (explanations, the good/bad rating).
## Recorded segments: menu_config, heli_pickup, generating, flyover, play, goal, history.

const GAME_SCENE := "res://scenes/game_world.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
## Per wall: "correct" walks through the right door, "wrong" through the other one; walls
## past the plan are answered right.
const PLAN := ["correct", "correct", "wrong", "correct", "correct", "correct", "correct", "correct", "correct", "correct"]

var kit  # tests/pv/pv_runtime.gd (untyped: its helpers are called dynamically)
var generator  # tests/pv/pv_providers.gd GeneratingProvider


func run(runner) -> void:
	kit = runner
	var gs := QuizManager.game_state
	var quizzes: Dictionary = kit.load_quizzes("math3")
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.subject = quizzes.subject
	gs.grade = quizzes.grade
	gs.difficulty = quizzes.difficulty
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.sudden_death_enabled = false
	QuizManager.provider.set_llm_mode("ONLINE")
	gs.llm_mode = "ONLINE"
	generator = kit.generating_provider("math3")
	generator.held = true
	generator.interval_frames = 34
	gs.provider = generator
	await _menu()
	await _start()
	await _world_intro()
	await _play()
	await _goal()
	await _history()
	kit.note("final_state", gs.game_state)
	kit.note("score", gs.score)
	kit.note("hp", gs.p1_hp)


func _menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
	await kit.until(func() -> bool: return kit.menu() != null, 600)
	var menu = kit.menu()
	menu._update_ui()
	var preview = menu._menu_wall_preview
	if preview != null and preview.has_method("sync_menu_player_count"):
		preview.sync_menu_player_count(1)
	await kit.seconds(3.0)
	kit.record("menu_config")
	await kit.seconds(1.0)
	# All five subjects (back to 算数), the grade up and down, the difficulty and back.
	for step: Array in [[&"subject", 1], [&"subject", 1], [&"subject", 1], [&"subject", 1], [&"subject", 1],
			[&"grade", 1], [&"grade", 1], [&"grade", -1], [&"grade", -1],
			[&"difficulty", 1], [&"difficulty", -1]]:
		menu._request_config_shift(step[0], step[1])
		await kit.frames(4)
		await kit.until(func() -> bool: return not menu.config_conveyor.is_moving(), 240)
		await kit.seconds(0.45)
	await kit.seconds(1.0)


## The menu's own Start path, with the helicopter departure awaited in frames (the menu's
## guard is a 12 s wall-clock timeout, which slow capture would trip).
func _start() -> void:
	var menu = kit.menu()
	kit.record("heli_pickup")
	menu._menu_exit_in_progress = true
	menu._set_all_buttons_disabled(true)
	menu.settings_panel.visible = false
	await menu._play_start_ui_departure()
	await kit.frames(1)
	var preview = menu._menu_wall_preview
	var started := bool(preview.begin_game_start_departure(1))
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
	# Questions start arriving once the world is uncovered, so the count and the falling walls are seen.
	await kit.until(func() -> bool: return not SceneTransition.is_transitioning(), 60 * 20)
	await kit.seconds(0.8)
	generator.release()
	var ready: bool = await kit.until(func() -> bool:
		return gs.game_state == Constants.STATE_WAITING_START and not SceneTransition.is_transitioning() \
			and not world.is_start_presentation_locked() and not world.is_preload_construction_locked() \
			and bool(world._barrier_spawned_for_session) and not bool(world._barrier_dropping), 60 * 90)
	kit.note("waiting_start_reached", ready)
	await kit.seconds(1.5)
	kit.record("flyover")
	await kit.tap(KEY_ENTER, 2)
	await kit.until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 60 * 20)
	kit.record("play")


func _play() -> void:
	var gs := QuizManager.game_state
	var outcomes: Array = []
	for step: int in range(PLAN.size()):
		if gs.game_state != Constants.STATE_PLAYING or gs.current_quiz == null:
			break
		var index := gs.current_wall_index
		var target: float = kit.correct_door_x() if PLAN[step] == "correct" else kit.wrong_door_x()
		var hp_before := gs.p1_hp
		var passed: bool = await kit.until(func() -> bool:
			kit.steer(1, target)
			return gs.current_wall_index != index or gs.game_state != Constants.STATE_PLAYING, 60 * 40)
		kit.release_keys()
		outcomes.append({"wall": index, "plan": PLAN[step], "passed": passed, "hp": [hp_before, gs.p1_hp], "state": gs.game_state})
		await kit.seconds(0.6)
	kit.note("walls", outcomes)


## The run after the last wall: forward (W) until the goal is reached and the clear screen is up.
func _goal() -> void:
	var gs := QuizManager.game_state
	kit.record("goal")
	var cleared: bool = await kit.until(func() -> bool:
		kit.key(KEY_W, gs.game_state == Constants.STATE_GOAL_RACE)
		return gs.game_state in [Constants.STATE_CLEAR, Constants.STATE_GAME_OVER], 60 * 60)
	kit.release_keys()
	kit.note("cleared", cleared)
	await kit.seconds(4.0)


## History of the round: open it from the clear screen, scroll down the cards, rate one good.
func _history() -> void:
	var world = kit.world()
	var hud = world.get_node_or_null("GameplayHUD") if world != null else null
	if hud == null:
		kit.note("history", "no hud")
		return
	var shown: bool = await kit.until(func() -> bool: return hud.btn_history.visible and hud.btn_history.is_visible_in_tree(), 60 * 20)
	kit.note("history_button", shown)
	if not shown:
		return
	kit.record("history")
	await kit.seconds(1.0)
	hud.btn_history.pressed.emit()
	await kit.seconds(1.6)
	var scroll := hud.history_list.get_parent() as ScrollContainer
	var bottom := maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.size.y))
	for i in range(150):
		scroll.scroll_vertical = int(lerpf(0.0, float(bottom) * 0.35, smoothstep(0.0, 1.0, i / 149.0)))
		await kit.frames(1)
	await kit.seconds(0.6)
	var good: Button = null
	for node: Node in hud.history_list.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.begins_with("◯") and button.is_visible_in_tree():
			var rect := button.get_global_rect()
			if rect.position.y > 120.0 and rect.end.y < float(kit.get_viewport().get_visible_rect().size.y) - 60.0:
				good = button
				break
	if good != null:
		good.pressed.emit()
	kit.note("rated", good != null)
	await kit.seconds(2.0)


func get_tree() -> SceneTree:
	return kit.get_tree()
