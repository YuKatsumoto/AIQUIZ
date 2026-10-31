extends Node

## 練習の CPU（docs/new_tutorial/phase6_design.md 3.1・3.4）と相手を選ぶカード（3.2）の実機テスト。
## ゲーム画面（scenes/game_world.tscn）を練習の2人で開き、監督（PracticeDirector）は外して、P2 を CPU にする
## （game_state.practice_p2_cpu）。CPU の動き（move_to・P1 をよけて通る・wave・practice_moves・go_door の速い／ゆっくり・
## push_toward_p1・wander・ghost_attack）を本編側の入力口（practice_set_cpu_input）で動かし、思った所へ着く・P1 にぶつからない・
## 押し合いになる・ゴーストが構えて突進する（当たる・よけられる）ことを確かめて撮る。最初に相手を選ぶカードも確かめて撮る。
## P1 の動き（押し直し・よける）とカードのキーは、キーボードの入力（Input.parse_input_event）で送る。
##   Godot --path . --script tests/practice_cpu_bootstrap.gd
## 撮った画面は artifacts/practice_cpu/。最後に {"passed", "checks", "failures", "notes"} を出す。

const OUT := "res://artifacts/practice_cpu/"
const GAME_WORLD := "res://scenes/game_world.tscn"
## 練習の壁の速さ（コース①と同じ）と、壁を置く距離
const WALL_SPEED := 1.6
const WALL_DISTANCE := 14.0
## 2人の体がぶつかる距離（game_state の PLAYER_BODY_RADIUS × 2）
const BODY_TOUCH := 1.24
## 開始の位置（台本③の 1.3）
const P1_START := Vector2(1.5, 0.0)
const P2_START := Vector2(-1.5, 0.0)

var gs: QuizGameState
var world: Node3D
var cpu: PracticeCpu
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _finished_actions: Array[StringName] = []
var _contacts: Array[Dictionary] = []
var _push_events: Array[Dictionary] = []
var _ghost_events: Array[String] = []
var _charging := 0


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not await _open_world():
		_finish()
		return
	# 「-- only=push」のように、1つだけ流せる（調べるとき用）
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=")
	for section: String in ["pick_card", "move_to", "move_around_p1", "wave", "practice_moves", "go_door_fast", "go_door_slow",
			"push", "wander", "ghost"]:
		if only.is_empty() or only == section:
			await call("_" + section)
	_finish()


# ---------- ゲーム画面 ----------

func _open_world() -> bool:
	gs = QuizManager.game_state
	QuizManager.player_analytics = null
	gs.mode = Constants.MODE_PRACTICE
	gs.num_players = 2
	world = load(GAME_WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	# 監督は外す（台本を進めず、CPU だけを動かす）。監督のハテナもいっしょに外す。
	var director := world.get("practice_director") as Node
	if director != null:
		world.remove_child(director)
		director.free()
	var stray := world.get_node_or_null("HatenaGuide")
	if stray != null:
		world.remove_child(stray)
		stray.free()
	if not gs.has_method("practice_set_cpu_input") or not ("practice_p2_cpu" in gs):
		check(false, "game_state has the CPU input (practice_p2_cpu / practice_set_cpu_input)")
		return false
	_start_round(_rules())
	gs.practice_p2_cpu = true
	cpu = PracticeCpu.new()
	world.add_child(cpu)
	cpu.setup(gs, world)
	cpu.finished.connect(func(action: StringName) -> void: _finished_actions.append(action))
	cpu.ghost_charging.connect(func(_target: int) -> void: _charging += 1)
	gs.practice_wall_contact.connect(func(player: int, door: int, correct: bool) -> void:
		_contacts.append({"player": player, "door": door, "correct": correct, "p1_z": gs.player_local_z, "p2_z": gs.player2_local_z}))
	gs.local_push_event.connect(func(event: Dictionary) -> void: _push_events.append(event.duplicate()))
	for sig: String in ["practice_ghost_ready", "practice_ghost_dash", "practice_ghost_hit", "practice_ghost_missed"]:
		if gs.has_signal(sig):
			Signal(gs, sig).connect(func(a: int = 0, b: int = 0) -> void: _ghost_events.append("%s %d %d" % [sig, a, b]))
		else:
			notes.append("game_state has no signal %s" % sig)
	_refocus()
	await frames(40)
	check(gs.game_state == Constants.STATE_PLAYING, "the practice round is playing (%s)" % gs.game_state)
	check(gs.practice_cpu_active(), "P2 is the CPU")
	await seconds(0.3)
	await capture("01_cpu_start")
	return true


func _rules() -> MatchRules:
	var rules := MatchRules.new()
	rules.world_speed = 0.0
	rules.fence_enabled = true
	rules.mistakes = MatchRules.Mistakes.REPORT_ONLY
	rules.record_results = false
	return rules


func _start_round(rules: MatchRules, quizzes: Array[QuizItem] = []) -> void:
	gs.start_practice_round(quizzes, 2, rules)
	gs.practice_place_player(1, P1_START.x, P1_START.y)
	gs.practice_place_player(2, P2_START.x, P2_START.y)
	_finished_actions.clear()
	_contacts.clear()


func _quiz(question: String, choices: Array, answer: int) -> Array[QuizItem]:
	var list: Array[QuizItem] = [QuizItem.create(question, PackedStringArray(choices), answer)]
	return list


## テストの窓が前に出ていなくても、押し合いの入力を止めない（ゲーム画面は窓が後ろへ回ると押し合いを止める）。
func _refocus() -> void:
	world.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)


# ---------- 相手を選ぶカード ----------

func _pick_card() -> void:
	var card := PracticePickCard.new()
	world.add_child(card)
	var results: Array = []
	var joined := [0]
	card.chosen.connect(func(with_cpu: bool) -> void: results.append(with_cpu))
	card.p2_joined.connect(func() -> void: joined[0] += 1)
	await seconds(0.45)
	check(card.is_open() and card.mode() == &"pick", "the pick card opens on its own (%s)" % card.mode())
	check(card.button(1).has_focus(), "[CPUと] is chosen first")
	await capture("00a_pick_card")
	# 矢印キーで［2人で］へ、Enter で選ぶ
	await tap(KEY_LEFT)
	check(card.button(0).has_focus(), "the left arrow moves to [2人で]")
	await tap(KEY_ENTER)
	await seconds(0.3)
	check(card.mode() == &"join", "[2人で] waits for P2 (%s)" % card.mode())
	await capture("00b_pick_join")
	# 左の Ctrl では参加しない。Esc で選び直し
	await tap(KEY_CTRL, KEY_LOCATION_LEFT)
	check(card.mode() == &"join" and joined[0] == 0, "the left Ctrl does not join")
	await tap(KEY_ESCAPE)
	check(card.mode() == &"pick" and results.is_empty(), "Esc goes back to the choice")
	# マウスで［2人で］を押したのと同じ → 右の Ctrl で参加
	card.button(0).pressed.emit()
	await seconds(0.25)
	await tap(KEY_CTRL, KEY_LOCATION_RIGHT)
	check(joined[0] == 1 and card.mode() == &"joined", "the right Ctrl joins P2 (%s)" % card.mode())
	await seconds(0.3)
	await capture("00c_pick_joined")
	await seconds(1.0)
	check(results == [false] and not card.is_open(), "chosen(false) after P2 joined (%s)" % [results])
	# もう一度開いて Esc ＝［CPUと］
	card.open()
	await seconds(0.3)
	await tap(KEY_ESCAPE)
	await seconds(0.3)
	check(results == [false, true] and not card.is_open(), "Esc chooses the CPU (%s)" % [results])
	card.queue_free()
	await frames(2)


# ---------- 歩く ----------

func _move_to() -> void:
	_start_round(_rules())
	await frames(5)
	cpu.move_to(-4.0, 3.0, 1.0)
	var ok := await wait_until(func() -> bool: return &"move_to" in _finished_actions, 4.0)
	check(ok and cpu.is_arrived(), "move_to arrives (%s)" % _p2())
	await seconds(0.4)
	check(_p2().distance_to(Vector2(-4.0, 3.0)) < 0.2, "move_to stays where it stopped (%s)" % _p2())
	check(_finished_actions.count(&"move_to") == 1, "finished(move_to) comes once")
	await capture("02_move_to")


## P1 の向こう側へ：P1 にぶつからずに回り込む（P1 は押されない）。
func _move_around_p1() -> void:
	_start_round(_rules())
	gs.practice_place_player(1, 0.0, 2.0)
	gs.practice_place_player(2, -3.5, 2.0)
	await frames(5)
	cpu.move_to(3.5, 2.0, 0.8)
	var gap := INF
	var shot := false
	var elapsed := 0.0
	while elapsed < 6.0 and not (&"move_to" in _finished_actions):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		gap = minf(gap, _p1().distance_to(_p2()))
		if not shot and _p2().x > -0.2:
			shot = true
			await capture("03_move_around_p1")
	check(&"move_to" in _finished_actions and cpu.is_arrived(), "the CPU gets past P1 (%s)" % _p2())
	check(gap >= BODY_TOUCH, "the CPU walks around P1 without touching (closest %.2f m)" % gap)
	check(_p1().distance_to(Vector2(0.0, 2.0)) < 0.05, "P1 is not pushed (%s)" % _p1())


func _wave() -> void:
	_start_round(_rules())
	await frames(5)
	cpu.wave()
	var started := await wait_until(func() -> bool: return gs.p2_emote != 0, 1.0)
	check(started, "wave starts an emote")
	await seconds(0.7)
	await capture("04_wave")
	var done := await wait_until(func() -> bool: return &"wave" in _finished_actions, 3.0)
	await frames(3)
	check(done and gs.p2_emote == 0, "the wave ends after about 2 s (emote %d)" % gs.p2_emote)
	check(gs.player2_y <= 0.001, "waving does not jump")


func _practice_moves() -> void:
	_start_round(_rules())
	await frames(5)
	var start := _p2()
	var previous := start
	var lateral := 0.0
	var depth := 0.0
	var jumps := gs.p2_jump_count
	var shot := false
	cpu.practice_moves(true)
	var elapsed := 0.0
	while elapsed < 12.0 and not (&"practice_moves" in _finished_actions):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var now := _p2()
		lateral += absf(now.x - previous.x)
		depth += absf(now.y - previous.y)
		previous = now
		if not shot and gs.player2_y > 0.5:
			shot = true
			await capture("05_practice_moves_jump")
	check(&"practice_moves" in _finished_actions, "practice_moves finishes (%.1f s)" % elapsed)
	check(lateral >= 1.5 and depth >= 1.5, "practice_moves goes 1.5 m sideways and 1.5 m back and forth (%.2f / %.2f)" % [lateral, depth])
	check(gs.p2_jump_count == jumps + 1, "practice_moves jumps once (%d)" % (gs.p2_jump_count - jumps))
	check(_p2().distance_to(start) < 0.3, "practice_moves ends where it started (%s)" % _p2())


# ---------- 壁のドアへ ----------

## 急いで（haste 1）青のドアへ：P1 の前を回り込み、P1 より先に着く。
func _go_door_fast() -> void:
	var rules := _rules()
	rules.world_speed = WALL_SPEED
	_start_round(rules, _quiz("CPU テスト：青のドア", ["青", "赤"], 0))
	gs.practice_place_current_wall(WALL_DISTANCE)
	await frames(5)
	_contacts.clear()
	cpu.go_door(0, 1.0)
	var gap := INF
	var shot := false
	var elapsed := 0.0
	while elapsed < 12.0 and not (&"go_door" in _finished_actions):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		gap = minf(gap, _p1().distance_to(_p2()))
		if not shot and _p2().x > 0.6:
			shot = true
			await capture("06_go_door_fast")
	check(&"go_door" in _finished_actions, "go_door (fast) finishes (%.1f s)" % elapsed)
	var first: Dictionary = _contacts[0] if not _contacts.is_empty() else {}
	check(int(first.get("player", 0)) == 2 and int(first.get("door", -9)) == 0 and bool(first.get("correct", false)),
		"the CPU reaches the blue door first (%s)" % [first])
	check(gap >= BODY_TOUCH, "going to the door, the CPU does not touch P1 (closest %.2f m)" % gap)
	await seconds(0.25)
	await capture("07_go_door_through")


## ゆっくり（haste 0.1。コース③の 3-2 の壁1と同じ）：P1 が同じドアの前にいる。CPU は P1 の後ろを回って、P1 が先に着く。
func _go_door_slow() -> void:
	var rules := _rules()
	rules.world_speed = WALL_SPEED
	_start_round(rules, _quiz("CPU テスト：ゆっくり", ["青", "赤"], 0))
	gs.practice_place_player(1, 3.0, 0.0)
	gs.practice_place_current_wall(WALL_DISTANCE)
	await frames(5)
	_contacts.clear()
	cpu.go_door(0, 0.1)
	var gap := INF
	var shot := false
	var ahead := 0.0
	var elapsed := 0.0
	while elapsed < 16.0 and not (&"go_door" in _finished_actions):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		gap = minf(gap, _p1().distance_to(_p2()))
		ahead = maxf(ahead, _p2().y - _p1().y)
		if not shot and elapsed > 3.0:
			shot = true
			await capture("08_go_door_slow")
	check(&"go_door" in _finished_actions, "go_door (slow) finishes when the wall is done (%.1f s)" % elapsed)
	var first: Dictionary = _contacts[0] if not _contacts.is_empty() else {}
	check(int(first.get("player", 0)) == 1, "with a slow haste, P1 reaches the wall first (%s)" % [first])
	check(ahead <= 0.05, "with a slow haste, the CPU never gets ahead of P1 (most %.2f m)" % ahead)
	check(gap >= BODY_TOUCH, "the CPU stays clear of P1 at the shared door (closest %.2f m)" % gap)
	check(_p2().x > 2.4, "the CPU heads for the blue door (x %.2f)" % _p2().x)


# ---------- 押し合い ----------

func _push() -> void:
	var rules := _rules()
	rules.local_push_enabled = true
	_start_round(rules)
	gs.practice_place_player(1, 0.6, 0.0)
	gs.practice_place_player(2, -0.6, 0.0)
	_refocus()
	await frames(5)
	_push_events.clear()
	cpu.push_toward_p1()
	await seconds(0.4)
	# P1 も P2 のほう（D：画面の右）へ押す → 踏ん張り合い
	key(KEY_D, true)
	var braced := await wait_until(func() -> bool: return _push_kinds().has("stalemate"), 2.0)
	check(braced, "pushing each other becomes a stalemate (%s)" % [_push_kinds()])
	await seconds(0.5)
	await capture("09_push_stalemate")
	check(_p2().x > -1.6 and _p2().x < 0.2, "the CPU holds its ground while P1 pushes (x %.2f)" % _p2().x)
	# 一度離して押し直す → P1 の一押し。押し直しは踏ん張りのあと 0.2 秒のうち（ARM_GRACE）なので、
	# テストの窓のフレームが遅くても間に合うよう、離すと押すを同じフレームで送る（押し合いはキーの順に読む）
	key(KEY_D, false)
	key(KEY_D, true)
	var hit := await wait_until(func() -> bool: return _push_hits(1) > 0, 1.0)
	await frames(4)
	await capture("10_push_hit")
	key(KEY_D, false)
	await seconds(0.4)
	check(hit, "P1's push-again lands on the CPU (%s)" % [_push_kinds()])
	check(_push_hits(2) == 0, "the CPU never pushes again by itself")
	cpu.idle()
	await frames(3)


func _push_kinds() -> Array:
	var kinds := []
	for event: Dictionary in _push_events:
		if not kinds.has(event.get("kind")):
			kinds.append(event.get("kind"))
	return kinds


func _push_hits(player: int) -> int:
	var count := 0
	for event: Dictionary in _push_events:
		if event.get("kind") == "hit" and int(event.get("player", 0)) == player:
			count += 1
	return count


# ---------- 左右に行き来する ----------

func _wander() -> void:
	_start_round(_rules())
	gs.practice_place_player(1, 6.5, -4.0)
	gs.practice_place_player(2, 0.0, 0.0)
	await frames(5)
	cpu.wander(Vector2(3.0, -3.0), 0.4)
	var low := INF
	var high := -INF
	var drift := 0.0
	var elapsed := 0.0
	var shot := false
	while elapsed < 7.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		low = minf(low, _p2().x)
		high = maxf(high, _p2().x)
		drift = maxf(drift, absf(_p2().y))
		if not shot and elapsed > 2.0:
			shot = true
			await capture("11_wander")
	check(low <= -2.5 and high >= 2.5, "wander goes from side to side (%.2f .. %.2f)" % [low, high])
	check(low >= -3.3 and high <= 3.3, "wander stays inside the range (%.2f .. %.2f)" % [low, high])
	check(drift < 0.4, "wander keeps its depth (%.2f)" % drift)
	check(cpu.action() == &"wander" and not cpu.is_arrived(), "wander keeps going")


# ---------- ゴースト ----------

func _ghost() -> void:
	if not gs.has_method("practice_make_ghost"):
		notes.append("game_state has no practice_make_ghost (ghost not checked)")
		return
	var rules := _rules()
	rules.ghost_ride_enabled = true
	_start_round(rules)
	gs.practice_place_player(1, 1.5, 2.0)
	await frames(10)
	_ghost_events.clear()
	_charging = 0
	cpu.ghost_attack(1)
	gs.practice_make_ghost(2, true)
	var ready := await wait_until(func() -> bool: return cpu.ghost_stage() == &"aim", 25.0)
	check(ready, "the CPU ghost gets its aim (%s)" % _ghost_phase())
	if not ready:
		return
	if gs.has_method("practice_ghost_state") and gs.practice_ghost_state(2).is_empty():
		notes.append("practice_ghost_state(2) is empty while aiming (the CPU read the ride controller directly)")
	await seconds(0.45)
	await capture("12_ghost_aim")
	var charged := await wait_until(func() -> bool: return _charging >= 1, 6.0)
	check(charged, "the CPU ghost starts charging (ghost_charging)")
	if not charged:
		return
	var charge_from := Time.get_ticks_msec()
	var locked := _aim()
	check(locked.distance_to(_p1()) < 0.5, "it charges with the aim on P1 (aim %s, P1 %s)" % [locked, _p1()])
	await seconds(0.6)
	await capture("13_ghost_charging")
	check(_aim().distance_to(locked) < 0.05, "the aim does not move while charging (%s -> %s)" % [locked, _aim()])
	var released := await wait_until(func() -> bool: return _ghost_phase() in ["WINDUP", "CHARGING", "COOLDOWN"], 3.0)
	var held := (Time.get_ticks_msec() - charge_from) / 1000.0
	check(released and held > 1.05 and held < 1.75, "it holds the charge about 1.2 s (%.2f s)" % held)
	check(not bool(_ghost_debug().get("perfect_charge", true)), "the release is not PERFECT (power %.2f)" % float(_ghost_debug().get("charge_power", -1.0)))
	await wait_until(func() -> bool: return _ghost_phase() == "CHARGING", 1.0)
	await frames(5)
	await capture("14_ghost_dash")
	var hit := await wait_until(func() -> bool: return bool(_ghost_debug().get("hit_this_charge", false)), 2.0)
	check(hit, "the dash hits P1 standing still (%s)" % [_ghost_events])
	await frames(8)
	await capture("15_ghost_hit")
	# 2回目：構えたら P1 が横へよける（床の真ん中のほうへ 0.45 秒）
	var second := await wait_until(func() -> bool: return _charging >= 2, 20.0)
	check(second, "after the cooldown the CPU aims and charges again")
	if second:
		var dodge_key := KEY_D if _p1().x > 0.0 else KEY_A
		key(dodge_key, true)
		await seconds(0.45)
		key(dodge_key, false)
		await wait_until(func() -> bool: return _ghost_phase() == "CHARGING", 3.0)
		await frames(6)
		await capture("16_ghost_dodge")
		await wait_until(func() -> bool: return _ghost_phase() == "COOLDOWN", 3.0)
		await frames(2)
		check(not bool(_ghost_debug().get("hit_this_charge", true)), "P1 dodges the dash by moving aside")
	notes.append("ghost events from game_state: %s" % [_ghost_events])
	cpu.idle()


func _ghost_controller() -> Node:
	return world.get_node_or_null("GhostSharkRideController")


func _ghost_debug() -> Dictionary:
	var controller := _ghost_controller()
	return controller.call("get_debug_state") if controller != null else {}


func _ghost_phase() -> String:
	return str(_ghost_debug().get("phase", ""))


## 照準の (x, コンベア上の z)
func _aim() -> Vector2:
	var point: Vector3 = _ghost_debug().get("aim_point", Vector3.ZERO)
	return Vector2(point.x, point.z)


# ---------- 道具 ----------

func _p1() -> Vector2:
	return Vector2(gs.player_x, gs.player_local_z)


func _p2() -> Vector2:
	return Vector2(gs.player2_x, gs.player2_local_z)


## キーを押す・離す（本物のキーボードと同じ入口から）。
func key(code: Key, pressed: bool, location := KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)


func tap(code: Key, location := KEY_LOCATION_UNSPECIFIED) -> void:
	key(code, true, location)
	await frames(2)
	key(code, false, location)
	await frames(2)


func wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while not bool(condition.call()):
		if elapsed >= timeout:
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")


func _finish() -> void:
	if cpu != null:
		cpu.idle()
	gs.practice_p2_cpu = false
	print("PRACTICE_CPU " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes}))
	get_tree().quit(0 if failures.is_empty() else 1)
