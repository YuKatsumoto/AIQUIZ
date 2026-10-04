extends Node

## 刷新したチュートリアルを実ゲームで最初から最後まで遊ぶ受け入れ確認。
## 実キー入力（Input.parse_input_event）だけで進め、各ステップの画面と3Dキーの状態を残す。
## プレイヤーの設定ファイルには書き込まない（保存先をテスト用に差し替え、元のハッシュを確認する）。
const OUT := "res://artifacts/tutorial_v5/"
const SOLO := "SOLO"
const DUO := "LOCAL_2P"
const TEST_SETTINGS := "user://tutorial_renewal_test_settings.json"

var gs: QuizGameState
var world: Node
var course := SOLO
var tag := "solo"
var checks: Array[String] = []
var failures: Array[String] = []
var shots: Array[String] = []
var steps_seen: Array[String] = []
var key_log: Dictionary = {}
var _settings_hash := ""
var _finished := false


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "course=duo":
			course = DUO
			tag = "duo"
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + tag))
	_settings_hash = FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH)
	GameManager.settings_path = TEST_SETTINGS
	gs = QuizManager.game_state
	QuizManager.player_analytics = null
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.start_tutorial(course)
	gs.skip_start_helicopter_arrival = true
	GameManager.start_game()
	if not await _enter_world():
		_finish()
		return
	if course == SOLO:
		await _run_solo()
	else:
		await _run_duo()
	_finish()


# ---------- 1P ----------

func _run_solo() -> void:
	if not await _wait_step("run_lane"):
		return
	await _wait(0.7)
	await _shot("01_run_lane")
	_expect_layout("P1", "cluster", "run_lane")
	_expect_key("P1", "left", "A", "target", "run_lane")
	_expect_key("P1", "right", "D", "target", "run_lane")
	_expect_key("P1", "up", "W", "idle", "run_lane")
	_expect_key("P1", "down", "S", "idle", "run_lane")
	_check(not _keys().get("P1", {}).get("keys", {}).has("jump"), "run_lane shows only the movement cluster")
	_key(KEY_A, true)
	await _wait(0.2)
	await _shot("02_press_A")
	_check(_key_depth("P1", "left") > 0.6, "holding A sinks the 3D A key")
	_check(_key_depth("P1", "right") < 0.1, "unpressed D key stays up")
	_key(KEY_A, false)
	await _wait(0.35)
	_expect_key("P1", "left", "A", "done", "after pressing A")
	await _tap(KEY_D, 0.2)

	if not await _wait_step("air_control"):
		return
	await _wait(0.6)
	await _shot("03_air_control")
	_expect_key("P1", "jump", "Space", "target", "air_control")
	_expect_key("P1", "up", "W", "target", "air_control")
	_expect_key("P1", "down", "S", "target", "air_control")
	_expect_key("P1", "left", "A", "idle", "air_control context")
	await _tap(KEY_SPACE, 0.15)
	await _wait(0.5)
	await _tap(KEY_W, 0.2)
	_key(KEY_DOWN, true)
	await _wait(0.2)
	_expect_key("P1", "down", "↓", "", "solo arrow keys relabel the 3D keys")
	await _shot("04_arrow_legends")
	_key(KEY_DOWN, false)

	if not await _wait_step("solo_emote"):
		return
	await _wait(0.6)
	_expect_key("P1", "emote_1", "1", "target", "solo_emote")
	_expect_key("P1", "emote_3", "3", "target", "solo_emote")
	_check(not _keys().get("P1", {}).get("keys", {}).has("left"), "emote step shows only the number keys")
	await _shot("05_emote")
	await _tap(KEY_1, 0.25)

	if not await _wait_step("ocean_lesson"):
		return
	await _wait(0.6)
	_expect_layout("P1", "sides", "ocean_lesson")
	await _shot("06_ocean")
	var edge_key: Key = KEY_A if gs.player_x >= 0.0 else KEY_D
	_key(edge_key, true)
	await _wait_until(func() -> bool: return gs.p1_fall_committed or gs.p1_waiting_for_shark or not gs.p1_alive, 5.0)
	_key(edge_key, false)

	if not await _wait_step("guided_wall", 30.0):
		return
	await _wait(0.5)
	_check(_hud_hearts_visible(), "hearts appear from the quiz lessons on")
	_expect_layout("P1", "sides", "guided_wall")
	await _shot("07_guided_wall")
	await _steer(1, gs.tuning.left_door_x)
	await _wait(0.3)
	await _shot("08_guided_aligned")

	if not await _wait_step("hp_lesson", 25.0):
		return
	await _wait(0.6)
	_check(gs.p1_hp == 3, "guided wall never costs a heart")
	_check(gs.tutorial_flow.target_door() == 1, "heart lesson targets the wrong door")
	await _shot("09_hp_lesson")
	await _steer(1, gs.tuning.right_door_x)

	if not await _wait_step("free_wall", 25.0):
		return
	_check(gs.p1_hp == 2, "heart lesson costs exactly one heart (got %d)" % gs.p1_hp)
	await _wait(0.4)
	await _shot("10_free_wall")
	# 1問目（6×3=18、右）は正解、2問目（20-8=12、左）はわざと右のまま外してハートが減るのを確かめる。
	await _steer(1, gs.tuning.right_door_x)
	var first_wall := gs.current_wall_index
	await _wait_until(func() -> bool: return gs.current_wall_index > first_wall, 20.0)
	_check(gs.p1_hp == 2, "correct free answer keeps hearts")

	if not await _wait_step("boss_wall", 25.0):
		return
	_check(gs.p1_hp == 1, "wrong free answer costs one heart and the run continues (got %d)" % gs.p1_hp)
	await _wait(0.3)
	_check(gs.num_choices == 4, "boss wall has four doors")
	await _shot("11_boss_wall")
	await _steer(1, float(gs.tuning.door4_xs[1]))
	await _wait(0.4)
	await _shot("12_boss_aligned")

	if not await _wait_step_any(["stage_complete"], 25.0, true):
		return
	await _wait(1.2)
	await _shot("13_stage_complete")
	await _wait_until(func() -> bool: return gs.has_pending_solo_customize_tour(), 8.0)
	_check(gs.has_pending_solo_customize_tour(), "solo course hands off to the customize tour")
	await _wait(3.0)
	await _shot("14_customize_tour")


# ---------- 2P ----------

func _run_duo() -> void:
	if not await _wait_step("duo_run"):
		return
	await _wait(0.7)
	await _shot("01_duo_run")
	_expect_layout("P1", "cluster", "duo_run")
	_expect_layout("P2", "cluster", "duo_run")
	_expect_key("P1", "left", "A", "target", "duo_run")
	_expect_key("P1", "right", "D", "target", "duo_run")
	_expect_key("P2", "left", "←", "target", "duo_run")
	_expect_key("P2", "up", "↑", "idle", "duo_run")
	_key(KEY_A, true)
	_key(KEY_RIGHT, true)
	await _wait(0.2)
	await _shot("02_duo_press")
	_check(_key_depth("P1", "left") > 0.6 and _key_depth("P2", "right") > 0.6, "each player's own key sinks")
	_key(KEY_A, false)
	_key(KEY_RIGHT, false)
	await _wait(0.2)
	await _tap(KEY_D, 0.2)
	await _tap(KEY_LEFT, 0.2)

	if not await _wait_step("duo_push"):
		return
	await _wait(0.6)
	var p1_inward: Key = KEY_D if gs.player_x > gs.player2_x else KEY_A
	var p2_inward: Key = KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT
	_expect_key("P1", "right" if p1_inward == KEY_D else "left", "D" if p1_inward == KEY_D else "A", "target", "push toward the opponent")
	await _shot("03_push")
	_key(p1_inward, true)
	_key(p2_inward, true)
	await _wait_until(func() -> bool: return gs.tutorial_flow.is_task_done(1, "brace"), 4.0)
	await _wait(0.2)
	_key(p1_inward, false)
	_key(p1_inward, true)
	await _wait_until(func() -> bool: return gs.tutorial_flow.is_task_done(1, "push"), 2.0)
	await _wait(0.35)
	_key(p2_inward, false)
	_key(p2_inward, true)
	await _wait(0.4)
	_key(p1_inward, false)
	_key(p2_inward, false)

	if not await _wait_step("duo_air", 10.0):
		return
	await _wait(0.6)
	_expect_key("P2", "jump", "Ctrl", "target", "P2 jumps with right Ctrl")
	_expect_key("P1", "jump", "Space", "target", "P1 jumps with Space")
	_check(_clusters_apart(), "P1 and P2 key clusters never overlap on screen (air)")
	await _shot("04_duo_air")
	await _tap(KEY_SPACE, 0.15)
	await _tap(KEY_CTRL, 0.15)
	await _wait(0.5)
	_key(KEY_W, true)
	_key(KEY_UP, true)
	await _wait(0.2)
	_key(KEY_W, false)
	_key(KEY_UP, false)
	_key(KEY_S, true)
	_key(KEY_DOWN, true)
	await _wait(0.2)
	_key(KEY_S, false)
	_key(KEY_DOWN, false)

	if not await _wait_step("duo_emote", 10.0):
		return
	await _wait(0.6)
	_expect_key("P2", "emote_1", "8", "target", "duo_emote")
	_check(_clusters_apart(), "P1 and P2 key clusters never overlap on screen (emote)")
	await _shot("05_duo_emote")
	await _tap(KEY_1, 0.25)
	await _tap(KEY_8, 0.25)

	if not await _wait_step("duo_ocean", 10.0):
		return
	await _wait(0.6)
	_expect_layout("P2", "sides", "duo_ocean")
	_check((_keys().get("P1", {}).get("keys", {}) as Dictionary).is_empty(), "P1 shows no keys while only P2 has a task")
	await _shot("06_duo_ocean")
	var p2_edge: Key = KEY_LEFT if gs.player2_x >= 0.0 else KEY_RIGHT
	_key(p2_edge, true)
	await _wait_until(func() -> bool: return gs.p2_fall_committed or gs.p2_waiting_for_shark or not gs.p2_alive, 6.0)
	_key(p2_edge, false)

	if not await _wait_step_any(["duo_ghost"], 15.0, true):
		return
	await _ghost_practice()

	if not await _wait_step_any(["duo_saw"], 30.0, true):
		return
	await _wait(1.0)
	await _shot("08_saw_reveal")
	if not await _wait_step("duo_saw", 6.0):
		return
	await _wait(0.5)
	_expect_key("P1", "down", "S", "target", "saw lesson: back up first")
	_expect_key("P1", "up", "W", "idle", "saw lesson: forward waits its turn")
	await _shot("09_saw_lesson")
	_key(KEY_S, true)
	_key(KEY_DOWN, true)
	await _wait_until(func() -> bool:
		return gs.tutorial_flow.is_task_done(1, "saw_approach") and gs.tutorial_flow.is_task_done(2, "saw_approach"), 4.0)
	_key(KEY_S, false)
	_key(KEY_DOWN, false)
	await _wait(0.25)
	await _shot("10_saw_warning")
	_expect_key("P1", "up", "W", "target", "saw lesson: now move forward")
	_key(KEY_W, true)
	_key(KEY_UP, true)
	if not await _wait_step_any(["duo_guided_wall"], 8.0, true):
		_key(KEY_W, false)
		_key(KEY_UP, false)
		return
	_key(KEY_W, false)
	_key(KEY_UP, false)
	_check(gs.is_saw_visible(), "the saw keeps chasing during the quiz lessons")

	if not await _wait_step("duo_guided_wall", 8.0):
		return
	await _wait(0.4)
	_check(_hud_hearts_visible(), "2P heart cards appear from the quiz lessons on")
	await _shot("11_duo_guided")
	await _steer(1, gs.tuning.left_door_x)

	if not await _wait_step("duo_hp", 25.0):
		return
	_check(gs.score == 1 and gs.player2_score == 0, "only the first correct player scores (P1 %d / P2 %d)" % [gs.score, gs.player2_score])
	await _wait(0.5)
	await _shot("12_duo_hp")
	await _steer(2, -4.4)
	await _steer(1, -2.4)

	if not await _wait_step("duo_free_wall", 25.0):
		return
	_check(gs.p1_hp == 2 and gs.p2_hp == 2, "both players lose one heart in the lesson (P1 %d / P2 %d)" % [gs.p1_hp, gs.p2_hp])
	# 1問目（5×7=35、右）: P2は正解、P1は左へ外れて不正解。2問目（30-12=18、左）: P1正解、P2不正解。
	await _steer(1, 4.2)
	await _wait(0.3)
	await _shot("13_duo_free")
	var free_wall := gs.current_wall_index
	await _wait_until(func() -> bool: return gs.current_wall_index > free_wall, 20.0)
	_check(gs.p1_hp == 1 and gs.player2_score == 1, "a wrong P1 loses a heart while P2 takes the point")

	if not await _wait_step("duo_boss_wall", 25.0):
		return
	_check(gs.p1_hp == 1 and gs.p2_hp == 1, "free practice applies hearts per player (P1 %d / P2 %d)" % [gs.p1_hp, gs.p2_hp])
	await _wait(0.3)
	_check(gs.num_choices == 4, "2P boss wall has four doors")
	await _shot("14_duo_boss")
	await _steer(1, float(gs.tuning.door4_xs[2]))
	await _steer(2, float(gs.tuning.door4_xs[1]))

	if not await _wait_step_any(["duo_goal"], 25.0, true):
		return
	await _wait(0.4)
	await _shot("15_goal_sweep")
	if not await _wait_step("duo_goal", 8.0):
		return
	_check(gs.p1_alive and gs.p2_alive, "both players race to the goal")
	_expect_key("P1", "up", "W", "target", "goal")
	_expect_key("P2", "up", "↑", "target", "goal")
	await _shot("16_goal")
	_key(KEY_W, true)
	await _wait_until(func() -> bool: return gs.has_player_reached_goal(1), 20.0)
	await _shot("17_goal_waiting")
	_check(gs.get_tutorial_step_id() == "duo_goal", "the course waits for every survivor at the goal")
	_key(KEY_UP, true)
	if not await _wait_step_any(["duo_complete"], 25.0, true):
		_key(KEY_W, false)
		_key(KEY_UP, false)
		return
	_key(KEY_W, false)
	_key(KEY_UP, false)
	await _wait(1.4)
	await _shot("18_duo_complete")
	await _wait_until(func() -> bool: return gs.has_pending_solo_customize_tour(), 8.0)
	_check(gs.has_pending_solo_customize_tour(), "duo course hands off to the customize tour")
	await _wait(3.0)
	await _shot("19_customize_tour")


## ゴーストシャーク練習: 照準キー → 長押し → PERFECT帯で離して P1 に命中させる。
func _ghost_practice() -> void:
	var ghost: Node = world.get("_ghost_shark_ride_controller")
	var controlled := await _wait_until(func() -> bool:
		if world.is_ghost_charge_tutorial_active():
			_key(KEY_ENTER, true)
			_key(KEY_ENTER, false)
		return world.is_ghost_shark_control_active(2), 30.0)
	_check(controlled, "P2 reaches ghost shark control")
	if not controlled:
		return
	await _wait(0.6)
	_expect_layout("P2", "ghost", "ghost practice keys ride on the shark")
	_expect_key("P2", "left", "←", "target", "ghost aim")
	_expect_key("P2", "jump", "Ctrl", "target", "ghost charge")
	_check(_keys_on_screen("P2"), "ghost keys stay inside the screen")
	await _shot("07_ghost_keys")
	await _tap(KEY_LEFT, 0.15)
	for attempt: int in range(4):
		if gs.get_tutorial_step_id() != "duo_ghost":
			break
		await _wait_until(func() -> bool: return ghost.phase == ghost.Phase.AIMING or gs.get_tutorial_step_id() != "duo_ghost", 10.0)
		if gs.get_tutorial_step_id() != "duo_ghost":
			break
		ghost.set("_aim_offset", Vector2.ZERO)
		_key(KEY_CTRL, true)
		await _wait(0.42)
		_key(KEY_CTRL, false)
		await _wait_until(func() -> bool: return gs.get_tutorial_step_id() != "duo_ghost", 8.0)


# ---------- 起動 ----------

func _enter_world() -> bool:
	var ok := await _wait_until(func() -> bool:
		var scene := get_tree().current_scene
		return (
			scene != null and scene.name == "GameWorld"
			and not SceneTransition.is_transitioning()
			and not scene.is_start_presentation_locked()
			and bool(scene.get("_barrier_spawned_for_session"))
			and not bool(scene.get("_barrier_dropping"))
		), 90.0)
	_check(ok, "game world prepared")
	if not ok:
		return false
	world = get_tree().current_scene
	await _wait(0.3)
	_key(KEY_ENTER, true)
	await get_tree().process_frame
	_key(KEY_ENTER, false)
	var playing := await _wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 20.0)
	_check(playing, "countdown reaches the first lesson")
	return playing


# ---------- 補助 ----------

func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.location = KEY_LOCATION_RIGHT if key == KEY_CTRL else KEY_LOCATION_UNSPECIFIED
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(key: Key, hold := 0.2) -> void:
	_key(key, true)
	await _wait(hold)
	_key(key, false)
	await _wait(0.12)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return bool(condition.call())


## 指定ステップに入り、演出のロックが外れるまで待つ。
func _wait_step(id: String, timeout := 20.0) -> bool:
	var ok := await _wait_until(func() -> bool:
		return gs.get_tutorial_step_id() == id and not gs.is_tutorial_presentation_locked() and gs.game_state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE], timeout)
	_check(ok, "reached step %s (now %s)" % [id, gs.get_tutorial_step_id()])
	if ok and id not in steps_seen:
		steps_seen.append(id)
	if ok:
		key_log[id] = _keys()
	return ok


## 演出中でもよいので、いずれかのステップに入るまで待つ。
func _wait_step_any(ids: Array, timeout: float, allow_locked: bool) -> bool:
	var ok := await _wait_until(func() -> bool:
		return gs.get_tutorial_step_id() in ids and (allow_locked or not gs.is_tutorial_presentation_locked()), timeout)
	_check(ok, "reached one of %s (now %s)" % [str(ids), gs.get_tutorial_step_id()])
	if ok and gs.get_tutorial_step_id() not in steps_seen:
		steps_seen.append(gs.get_tutorial_step_id())
	return ok


## 実キーで左右に動き、目標の X に合わせる。A / ← が +X（画面左）。
func _steer(player: int, target_x: float, tolerance := 0.25, timeout := 4.0) -> bool:
	var plus_key: Key = KEY_A if player == 1 else KEY_LEFT
	var minus_key: Key = KEY_D if player == 1 else KEY_RIGHT
	var elapsed := 0.0
	var ok := false
	while elapsed < timeout:
		var x := gs.player_x if player == 1 else gs.player2_x
		var dx := target_x - x
		if absf(dx) <= tolerance:
			ok = true
			break
		_key(plus_key, dx > 0.0)
		_key(minus_key, dx < 0.0)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_key(plus_key, false)
	_key(minus_key, false)
	return ok


func _guides() -> Node:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null("DuoTutorialGuides" if course == DUO else "SoloTutorialGuides")


func _keys() -> Dictionary:
	var guides := _guides()
	if guides == null:
		return {}
	var key_guides: Node = guides.call("get_key_guides")
	return key_guides.call("get_evidence") if key_guides != null else {}


func _key_depth(player: String, slot: String) -> float:
	var key: Dictionary = _keys().get(player, {}).get("keys", {}).get(slot, {})
	return float(key.get("depth", 0.0))


func _expect_layout(player: String, layout: String, label: String) -> void:
	var evidence: Dictionary = _keys().get(player, {})
	_check(str(evidence.get("layout", "")) == layout and not (evidence.get("keys", {}) as Dictionary).is_empty(),
		"%s: %s keys use the %s layout (got %s)" % [label, player, layout, str(evidence.get("layout", ""))])


func _expect_key(player: String, slot: String, legend: String, look: String, label: String) -> void:
	var key: Dictionary = _keys().get(player, {}).get("keys", {}).get(slot, {})
	var ok := not key.is_empty() and str(key.get("legend", "")) == legend
	if not look.is_empty():
		ok = ok and str(key.get("look", "")) == look
	_check(ok, "%s: %s %s key shows %s/%s (got %s/%s)" % [
		label, player, slot, legend, look, str(key.get("legend", "-")), str(key.get("look", "-"))
	])


## 2人のキーボード片が画面上で横に重なっていないか（キーの中心どうしの範囲で判定）。
func _clusters_apart() -> bool:
	var guides := _guides()
	if guides == null:
		return false
	var points: Dictionary = guides.call("get_key_guides").call("get_screen_points")
	var ranges := {1: Vector2(INF, -INF), 2: Vector2(INF, -INF)}
	for id: String in points.keys():
		var player := 2 if id.begins_with("P2") else 1
		var x := (points[id] as Vector2).x
		ranges[player] = Vector2(minf(ranges[player].x, x), maxf(ranges[player].y, x))
	var p1: Vector2 = ranges[1]
	var p2: Vector2 = ranges[2]
	if not is_finite(p1.x) or not is_finite(p2.x):
		return false
	# キー1個ぶん（約40px）の余白を見込んで、範囲が交わらないこと。
	return p1.y + 40.0 < p2.x or p2.y + 40.0 < p1.x


func _keys_on_screen(player: String) -> bool:
	var guides := _guides()
	if guides == null:
		return false
	var points: Dictionary = guides.call("get_key_guides").call("get_screen_points")
	var size := get_viewport().get_visible_rect().size
	var found := false
	for id: String in points.keys():
		if not id.begins_with(player):
			continue
		found = true
		var point: Vector2 = points[id]
		if point.x < 0.0 or point.x > size.x or point.y < 0.0 or point.y > size.y:
			return false
	return found


func _hud_hearts_visible() -> bool:
	var health := world.get_node_or_null("GameplayHUD/PlayerHealthHUD") as Control
	return health != null and health.is_visible_in_tree()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + tag + "/" + name + ".png"
	get_tree().root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append(path)


func _check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error("TUTORIAL_RENEWAL " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for key: Key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE, KEY_CTRL]:
		_key(key, false)
	_check(FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) == _settings_hash, "player settings file untouched")
	var report := {
		"course": course,
		"checks": checks.size(),
		"failures": failures,
		"passed": failures.is_empty(),
		"steps_seen": steps_seen,
		"shots": shots,
		"keys": _stringify_keys(key_log),
	}
	var file := FileAccess.open(OUT + tag + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("TUTORIAL_RENEWAL_RUNTIME " + JSON.stringify({"course": course, "checks": checks.size(), "failures": failures, "passed": failures.is_empty()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _stringify_keys(log: Dictionary) -> Dictionary:
	var out := {}
	for step: String in log.keys():
		var players := {}
		for player: String in (log[step] as Dictionary).keys():
			var entry: Dictionary = log[step][player]
			var keys := {}
			for slot: String in (entry.get("keys", {}) as Dictionary).keys():
				var key: Dictionary = entry["keys"][slot]
				keys[slot] = "%s:%s" % [key.get("legend", ""), key.get("look", "")]
			players[player] = {"layout": entry.get("layout", ""), "keys": keys}
		out[step] = players
	return out
