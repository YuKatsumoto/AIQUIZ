extends Node

const OUT := "res://artifacts/ghost_hud_compact/"
var gs: QuizGameState
var world: Node3D
var ghost: GhostSharkRideController
var helper: Node
var health: Control
var card: Control
var other: Control
var panel: Control
var meter: ProgressBar
var failures: Array[String] = []
var samples: Array = []
var checks := 0
var player := 1
var video_frame := 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	player = 2 if "p2" in OS.get_cmdline_user_args() else 1
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "p%d_frames" % player))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	gs.score = 4
	gs.player2_score = 6
	gs.current_quiz.q = "3 ＋ 2 は？"
	gs.current_quiz.c = PackedStringArray(["5", "6"])
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	world.get_node("Player").reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	health = world.get_node("GameplayHUD/PlayerHealthHUD")
	card = health.get_node("P%dStatusCard" % player)
	other = health.get_node("P%dStatusCard" % (3 - player))
	panel = ghost.get("_hud_panel")
	meter = ghost.get("_charge_bar")
	var original_meter_id := meter.get_instance_id()
	await frames(45)
	check(card.size == Vector2(188, 80), "living card retains compact size")
	gs._set_player_hp(player, 1)
	if player == 1: gs.player_x = helper.door(gs, false)
	else: gs.player2_x = helper.door(gs, false)
	gs.resolve_collision(player == 1, player == 2)
	var reached := false
	for i in range(1800):
		await frames(1)
		if ghost.phase == ghost.Phase.AIMING:
			reached = true
			break
	check(reached, "fatal wall hit reaches actual ghost aiming")
	if not reached:
		finish()
		return
	await frames(40)
	check(gs.get_player_hp(player) == 0, "HP zero belongs to the rider")
	check(panel.get_parent() == card.get_node("AnimatedSurface/GhostRideSlot"), "original ghost panel hosted inside correct HP card")
	check(meter.get_instance_id() == original_meter_id, "same live charge meter retained")
	check(other.size == Vector2(188, 80), "surviving player's card remains compact")
	check(other.get_node("AnimatedSurface/HP").is_visible_in_tree(), "surviving player's HP stays visible")
	check(panel.get_parent().get_parent().get_parent() == card, "single unified card hierarchy")
	check(ghost.get_node("GhostRideHUD").get_node_or_null("GhostRidePanel") == null, "no duplicate floating HUD")
	check(ghost.get("_hud_controls").text.contains("WASD" if player == 1 else "矢印"), "aim key mapping")
	check(ghost.get("_hud_controls").text.contains("Space" if player == 1 else "Ctrl"), "fire key mapping")
	check_layout()
	await capture("aiming")
	var aim_before: Vector2 = ghost.get("_aim_offset")
	key(KEY_D if player == 1 else KEY_RIGHT, true)
	await frames(6)
	key(KEY_D if player == 1 else KEY_RIGHT, false)
	check((ghost.get("_aim_offset") as Vector2).distance_to(aim_before) > 0.1, "actual aim input still moves target")
	# Keep the target away from the surviving player while exercising a real shot.
	ghost.set("_aim_offset", Vector2(5.0, 7.0))
	key(KEY_SPACE if player == 1 else KEY_CTRL, true)
	for i in range(24):
		await frames(1)
		if i % 2 == 0: await capture("charging", true)
	check(meter.value >= 70.0 and meter.value <= 95.0, "held key drives live charge into perfect band")
	await capture("charged")
	key(KEY_SPACE if player == 1 else KEY_CTRL, false)
	await frames(2)
	check(ghost.phase == ghost.Phase.WINDUP, "release triggers windup")
	check(panel.is_visible_in_tree(), "integrated HUD remains visible during windup")
	await capture("windup")
	var saw_charge := false
	var saw_cooldown := false
	for i in range(900):
		await frames(1)
		saw_charge = saw_charge or ghost.phase == ghost.Phase.CHARGING
		if ghost.phase == ghost.Phase.COOLDOWN:
			saw_cooldown = true
			if i % 12 == 0: await capture("cooldown", true)
		if saw_cooldown and ghost.phase == ghost.Phase.AIMING: break
	check(saw_charge and saw_cooldown, "real shot completes charging and cooldown phases")
	check(ghost.phase == ghost.Phase.AIMING and panel.is_visible_in_tree(), "HUD returns to aiming after shot")
	# Long combo is a presentation boundary; normal charge values above came from gameplay.
	ghost.set("_combo", 123)
	await frames(2)
	await capture("combo")
	for dimensions in [Vector2i(1920,1080), Vector2i(1024,768), Vector2i(960,540), Vector2i(640,360)]:
		get_tree().root.size = dimensions
		await frames(8)
		check_layout()
		await capture("size_%dx%d" % [dimensions.x, dimensions.y])
	get_tree().root.size = Vector2i(1280,720)
	await frames(8)
	# The close-up must hand the exact same bar back to its new card slot.
	ghost.call("_start_charge_tutorial")
	await frames(3)
	check(not panel.is_visible_in_tree(), "close-up hides compact controls")
	ghost.dismiss_charge_tutorial()
	for i in range(90): await frames(1)
	check(not ghost.is_charge_tutorial_active(), "close-up handoff completes")
	check(meter.get_parent() == ghost.get("_charge_bar_home") and meter.get_instance_id() == original_meter_id, "close-up returns original meter to integrated slot")
	check_layout()
	await capture("handoff")
	ghost.force_cleanup()
	await frames(2)
	check(card.size == Vector2(188,80) and not panel.is_visible_in_tree(), "cleanup collapses card and hides controls")
	check(card.get_node("AnimatedSurface/HP").is_visible_in_tree(), "normal HP row restored after ghost cleanup")
	await capture("cleanup")
	finish()

func check_layout() -> void:
	var bounds := card.get_global_rect()
	check(get_viewport().get_visible_rect().encloses(bounds), "expanded card inside viewport")
	check(not bounds.intersects(other.get_global_rect()), "player cards do not overlap")
	check(not bounds.intersects(world.get_node("GameplayHUD/ProgressBar").get_global_rect()), "card clears round progress bar")
	for node in [panel, ghost.get("_hud_title"), ghost.get("_hud_combo"), ghost.get("_hud_controls"), meter]:
		check(bounds.grow(1).encloses(node.get_global_rect()), "ghost content contained: " + node.name)
	check(card.size == Vector2(320,120), "ghost card is 25 percent shorter")
	for node_name in ["HPHeading", "HP", "Status"]:
		check(not card.get_node("AnimatedSurface/" + node_name).is_visible_in_tree(), "ghost card hides " + node_name)
	check(card.get_node("AnimatedSurface/Score").get_global_rect().end.y < panel.get_global_rect().position.y, "score above ghost controls")
	var title: Control = ghost.get("_hud_title")
	var combo: Control = ghost.get("_hud_combo")
	check(not title.get_global_rect().intersects(combo.get_global_rect()), "title and combo do not overlap")
	var marker: Vector2 = health.call("reserve_marker_center", bounds.get_center(), 74.4)
	check(marker.y + 74.4 < bounds.position.y, "offscreen marker clears expanded card")

func frames(count: int) -> void:
	for i in range(count): await get_tree().process_frame

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func capture(tag: String, video := false) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + ("p%d_frames/%04d.png" % [player,video_frame] if video else "p%d_%s.png" % [player,tag])
	get_viewport().get_texture().get_image().save_png(path)
	samples.append({"tag":tag,"phase":ghost.Phase.keys()[ghost.phase],"meter":meter.value,"card":str(card.get_global_rect()),"panel":str(panel.get_global_rect())})
	if video: video_frame += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func finish() -> void:
	var report := {"passed":failures.is_empty(),"player":player,"checks":checks,"failures":failures,"samples":samples,"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open(OUT + "p%d_report.json" % player,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GHOST_HUD_RUNTIME " + JSON.stringify({"passed":failures.is_empty(),"player":player,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
