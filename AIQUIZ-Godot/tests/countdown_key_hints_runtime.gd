extends Node

## 本編のカウントダウン中、頭上に操作キーがうっすら出て、GO の後に消えることを実際の game_world で確かめる。
## godot --path . -s res://tests/countdown_key_hints_bootstrap.gd

const OUT := "res://artifacts/countdown_key_hints/"
const HintsScript = preload("res://scripts/world/countdown_key_hints.gd")

var helper: Node
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	helper = load("res://tests/hp_unit.gd").new()
	await run_case(1)
	await run_case(2)
	print("COUNTDOWN_KEY_HINTS_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)


func run_case(players: int) -> void:
	var tag := "solo" if players == 1 else "duo"
	var gs: QuizGameState = helper.fixture(players)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	var world: Node3D = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	await frames(30)
	var hints = world.get("_countdown_key_hints")
	check(hints != null, tag + ": countdown key hints exist in the main game")
	if hints == null:
		world.queue_free()
		await frames(2)
		return
	var guides = hints.get_key_guides()
	check(guides.get_evidence().values().all(func(p): return (p["keys"] as Dictionary).is_empty()), tag + ": no keys before the countdown")

	# 本編のスタート位置（2人なら P1 が画面左の +1.5、P2 が画面右の -1.5）。
	gs.player_x = 1.5 if players == 2 else 0.0
	gs.player2_x = -1.5
	gs.game_state = Constants.STATE_COUNTDOWN
	gs.countdown_timer = QuizGameState.COUNTDOWN_SECONDS
	await frames(60)
	var evidence: Dictionary = guides.get_evidence()
	print("[%s] countdown evidence: %s" % [tag, evidence])
	for player_index in range(1, players + 1):
		var keys: Dictionary = evidence["P%d" % player_index]["keys"]
		check(keys.size() == 5, tag + ": P%d shows 4 move keys + jump, no emotes (%d)" % [player_index, keys.size()])
		for slot: String in keys.keys():
			check(keys[slot]["look"] == "idle", tag + ": P%d %s is plain (not lit)" % [player_index, slot])
	var p1_legends: Array = (evidence["P1"]["keys"] as Dictionary).values().map(func(k): return k["legend"])
	for legend in ["W", "A", "S", "D", "Space"]:
		check(legend in p1_legends, tag + ": P1 legend %s" % legend)
	var points: Dictionary = guides.get_screen_points()
	# P1 の Space は D の右隣、A S D と同じ段に並ぶ（P2 の右Ctrl と左右対称）。
	check(points["P1:jump"].x > points["P1:right"].x, tag + ": P1 Space sits right of D")
	check(absf(points["P1:jump"].y - points["P1:right"].y) < 6.0, tag + ": P1 Space shares the A S D row")
	if players == 2:
		var p2_legends: Array = (evidence["P2"]["keys"] as Dictionary).values().map(func(k): return k["legend"])
		for legend in ["↑", "←", "↓", "→", "Ctrl"]:
			check(legend in p2_legends, tag + ": P2 legend %s" % legend)
		check(points["P2:jump"].x < points["P2:left"].x and absf(points["P2:jump"].y - points["P2:left"].y) < 6.0, tag + ": P2 Ctrl sits left of the arrow row")
		check(points["P1:jump"].x < points["P2:jump"].x, tag + ": P1 and P2 clusters do not overlap")
	var any_key = guides.get_node("P1Keys").get_child(0)
	check(any_key.translucent and absf(any_key.opacity - HintsScript.MAX_OPACITY) < 0.01, tag + ": keys are faint (opacity %.2f)" % any_key.opacity)
	await capture(tag + "_countdown")

	# GO（壁が割れて PLAYING）の後も、操作キーを押すまでは残る。
	var guard := 0
	while gs.game_state == Constants.STATE_COUNTDOWN and guard < 900:
		guard += 1
		await frames(1)
	check(gs.game_state == Constants.STATE_PLAYING, tag + ": countdown reaches PLAYING")
	await frames(45)
	await capture(tag + "_go")
	for player_index in range(1, players + 1):
		check(is_equal_approx(hints.get_fade(player_index), 1.0), tag + ": P%d keys stay after GO until a key is pressed" % player_index)

	# P1 が D を押すと P1 の分だけすっと消え、P2 の分は残る。
	await tap(KEY_D)
	var p1_mid: float = hints.get_fade(1)
	check(p1_mid > 0.1 and p1_mid < 0.9, tag + ": P1 keys fade out (not pop) after D (%.2f)" % p1_mid)
	if players == 2:
		check(is_equal_approx(hints.get_fade(2), 1.0), tag + ": P2 keys stay while only P1 pressed")
	await capture(tag + "_p1_fading")
	await frames(16)
	check(is_zero_approx(hints.get_fade(1)), tag + ": P1 keys gone within about 0.4 s")
	await frames(20)
	check((guides.get_evidence()["P1"]["keys"] as Dictionary).is_empty(), tag + ": P1 keys removed")
	if players == 2:
		await tap(KEY_LEFT)
		await frames(24)
		check(is_zero_approx(hints.get_fade(2)), tag + ": P2 keys fade after ←")
	check(gs.game_state == Constants.STATE_PLAYING, tag + ": still running when the checks ended (%s)" % gs.game_state)
	world.queue_free()
	await frames(4)


## 実際のキー入力として押して離す。
func tap(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(4)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
