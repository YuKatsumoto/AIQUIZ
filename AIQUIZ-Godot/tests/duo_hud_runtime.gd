extends Node

const OUT := "res://artifacts/duo_hud_compact/"
var gs: QuizGameState
var world: Node3D
var helper: Node
var hud: CanvasLayer
var health: Control
var cards: Array[Control] = []
var failures: Array[String] = []
var events: Array = []
var samples: Array = []
var video_frame := 0
var checks := 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.health_changed.connect(func(p, old, hp): events.append({"p":p,"from":old,"to":hp,"wall":gs.current_wall_index}))
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true) # Advance rendering, hold simulation only during layout checks.
	world.get_node("Player").prepare_for_loading(gs)
	hud = world.get_node("GameplayHUD")
	health = hud.get_node("PlayerHealthHUD")
	cards.assign(health.get_children())
	await frames(60)
	check(cards.size() == 2, "two independently identified player cards")
	check(cards[0].size.x * cards[0].size.y < 244.0 * 136.0 * 0.5, "compact card uses less than half the previous area")
	await capture("settled_1280")
	check_layout()
	check(not hud.get_node("ScoreLabel").visible, "old duplicate 2P score hidden")
	var marker_test: Vector2 = health.reserve_marker_center(Vector2(1134,642),74.4)
	check(marker_test.y + 74.4 < cards[1].get_global_rect().position.y, "offscreen marker clears the right status card")
	var saved_x := gs.player_x
	gs.player_x = 16.0
	await frames(8)
	await capture("offscreen_marker")
	gs.player_x = saved_x
	await frames(8)
	check(cards[0].get_node("AnimatedSurface/Score").text == "0", "P1 initial score")
	check(cards[1].get_node("AnimatedSurface/HP").text == "3 / 3", "P2 initial HP")

	gs.game_state = Constants.STATE_WAITING_START
	await frames(3)
	check(not health.visible, "HUD hidden during preparation")
	gs.game_state = Constants.STATE_COUNTDOWN
	for i in range(36):
		await frames(1)
		if i % 2 == 0: await video_sample("entrance")
	check(is_zero_approx(cards[0].get_node("AnimatedSurface").position.y), "P1 entrance settles")
	check(is_equal_approx(cards[1].get_node("AnimatedSurface").modulate.a, 1.0), "P2 staggered entrance settles")
	gs.game_state = Constants.STATE_PLAYING
	await cross(false, true, "p1_damage_p2_score")
	check(gs.p1_hp == 2 and gs.p2_hp == 3, "real mixed door outcome maps HP to P1")
	check(gs.score == 0 and gs.player2_score == 1, "real mixed door outcome maps score to P2")
	check(int(cards[0].get("_shown_hp")) == 2, "P1 damage animation settles to two hearts")
	check(cards[1].get_node("AnimatedSurface/Score").text == "1", "P2 live score label")
	check(cards[0].get("_bursts").is_empty() and cards[1].get("_bursts").is_empty(), "damage and score FX fully retire")
	await cross(true, false, "p2_damage_p1_score")
	check(gs.p1_hp == 2 and gs.p2_hp == 2 and gs.score == 1, "mirrored real door outcome maps independently")
	gs._set_player_hp(1, 1)
	await frames(30)
	await capture("low_hp")
	check(cards[0].get_node("AnimatedSurface/Status").text == "あと1回", "low HP has explicit text")
	check(cards[0].get_global_rect().encloses(cards[0].get_node("AnimatedSurface/Status").get_global_rect()), "low HP warning stays inside compact card: %s in %s" % [cards[0].get_node("AnimatedSurface/Status").get_global_rect(), cards[0].get_global_rect()])
	gs.mode = Constants.MODE_ENDLESS
	gs.hp_questions_completed = 9
	await cross(true, true, "recovery")
	check(gs.p1_hp == 2 and gs.p2_hp == 3, "real tenth-answer recovery maps to both cards")
	check(int(cards[0].get("_shown_hp")) == 2 and int(cards[1].get("_shown_hp")) == 3, "recovery animations settle")
	await capture("recovered")

	gs.score = 12345
	gs.player2_score = 9876
	await frames(40)
	await capture("long_scores")
	check(cards[0].get_node("AnimatedSurface/Score").text == "12345", "endless large score remains exact")
	gs._set_player_hp(2, 0)
	await frames(30)
	await capture("zero_hp")
	check(cards[1].get_node("AnimatedSurface/Status").text == "脱落", "zero HP has explicit status")
	for dimensions in [Vector2i(1920,1080), Vector2i(1024,768), Vector2i(960,540)]:
		get_tree().root.size = dimensions
		await frames(12)
		check_layout()
		await capture("size_%dx%d" % [dimensions.x,dimensions.y])
	get_tree().root.size = Vector2i(1280,720)
	gs.score = 2
	gs.player2_score = 2
	gs._reset_health()
	await frames(35)
	check(cards[0].get_node("AnimatedSurface/HP").text == "3 / 3" and cards[1].get_node("AnimatedSurface/HP").text == "3 / 3", "round reset clears both cards")
	for state in [Constants.STATE_FLYOVER,Constants.STATE_RESULT_CEREMONY,Constants.STATE_GAME_OVER]:
		gs.game_state = state
		await frames(2)
		check(not health.visible, "hidden during " + state)
	gs.game_state = Constants.STATE_GOAL_RACE
	await frames(35)
	check(health.visible, "visible during goal race")
	gs.hp_state_available = false
	await frames(2)
	check(not health.visible and hud.get_node("ScoreLabel").visible, "legacy replay retains old score and hides unsupported HP")
	gs.hp_state_available = true
	gs.mode = Constants.MODE_COOP
	gs.game_state = Constants.STATE_PLAYING
	await frames(2)
	check(not health.visible and hud.get_node("ScoreLabel").visible, "co-op retains shared score")
	gs.mode = Constants.MODE_TUTORIAL
	await frames(2)
	check(not health.visible, "tutorial HP remains hidden")

	# Verify 1P uses the existing layout and score on the same running viewport.
	health.hide()
	health.set_process(false)
	health.queue_free()
	await frames(2)
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	health = load("res://scripts/ui/player_health_hud.gd").new()
	health.name = "PlayerHealthHUD"
	health.setup(gs)
	hud.add_child(health)
	hud.set("_health_hud", health)
	await frames(8)
	check(health.position == Vector2(16,14) and health.get_child_count() == 0, "1P original HP layout preserved")
	check(hud.get_node("ScoreLabel").visible, "1P original score retained")
	await capture("solo_unchanged")
	var p1_peak := 1.0
	var p2_peak := 1.0
	var p1_damage_fx := false
	var p2_score_fx := false
	var both_heal_fx := false
	for sample in samples:
		p1_peak = maxf(p1_peak, float(sample.p1_score_scale))
		p2_peak = maxf(p2_peak, float(sample.p2_score_scale))
		if sample.tag == "p1_damage_p2_score":
			p1_damage_fx = p1_damage_fx or "damage" in sample.p1_fx
			p2_score_fx = p2_score_fx or "score" in sample.p2_fx
		if sample.tag == "recovery":
			both_heal_fx = both_heal_fx or ("recover" in sample.p1_fx and "recover" in sample.p2_fx)
	check(p1_peak > 1.20 and p2_peak > 1.20, "both enhanced score animations have rendered peak samples")
	check(p1_damage_fx and p2_score_fx and both_heal_fx, "rendered damage, score, recovery FX follow actual gameplay events")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"events":events,"samples":samples,"video_frames":video_frame}
	FileAccess.open(OUT + "runtime.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DUO_HUD_RUNTIME " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"video_frames":video_frame}))
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func check_layout() -> void:
	var viewport := get_viewport().get_visible_rect()
	var left := cards[0].get_global_rect()
	var right := cards[1].get_global_rect()
	check(viewport.encloses(left) and viewport.encloses(right), "cards inside " + str(viewport.size))
	check(left.position.x < viewport.size.x * 0.25 and right.position.x > viewport.size.x * 0.5, "P1 left P2 right")
	check(is_equal_approx(left.position.y,right.position.y) and left.position.y > viewport.size.y * 0.5, "both bottom aligned")
	check(not left.intersects(hud.get_node("ProgressBar").get_global_rect()) and not right.intersects(hud.get_node("ProgressBar").get_global_rect()), "cards clear of progress bar")
	for card in cards:
		check(card.get_node("AnimatedSurface/Score").get_global_rect().end.y < card.get_node("AnimatedSurface/HP").get_global_rect().position.y, "score above HP")

func frames(count: int) -> void:
	for i in range(count): await get_tree().process_frame

func cross(correct1: bool, correct2: bool, tag: String) -> void:
	gs.player_x = helper.door(gs,correct1) + (0.4 if correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs,correct2) - (0.4 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 1.0
	gs.player_z = gs.wall_z - 1.0
	gs.player2_z = gs.wall_z - 1.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	world.set("_replay_mode",false)
	var before := gs.current_wall_index
	var changed := false
	for i in range(150):
		await frames(1)
		if i % 2 == 0: await video_sample(tag)
		if gs.current_wall_index != before:
			changed = true
			break
	check(changed, tag + " actual wall crossed")
	for i in range(45):
		await frames(1)
		if i % 2 == 0: await video_sample(tag)
	world.set("_replay_mode",true)
	await capture(tag + "_settled")

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")

func video_sample(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "frames/%04d.png" % video_frame)
	samples.append({"frame":video_frame,"tag":tag,"hp":[gs.p1_hp,gs.p2_hp],"score":[gs.score,gs.player2_score],"p1_shown":cards[0].get("_shown_hp"),"p2_shown":cards[1].get("_shown_hp"),"p1_enter_y":cards[0].get_node("AnimatedSurface").position.y,"p2_enter_y":cards[1].get_node("AnimatedSurface").position.y,"p1_score_scale":cards[0].get_node("AnimatedSurface/Score").scale.x,"p2_score_scale":cards[1].get_node("AnimatedSurface/Score").scale.x,"p1_fx":cards[0].get("_bursts").map(func(b): return b.kind),"p2_fx":cards[1].get("_bursts").map(func(b): return b.kind)})
	video_frame += 1
