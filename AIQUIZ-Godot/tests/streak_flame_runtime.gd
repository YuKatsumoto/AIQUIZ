extends Node
## 対戦カードの連続正解バッジ（AE 製の炎＋回数）を実際の壁通過で確かめる。
## Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/streak_flame_bootstrap.gd --fixed-fps 60

const OUT := "res://artifacts/streak_flame/runtime/"
var gs: QuizGameState
var world: Node3D
var helper: Node
var hud: CanvasLayer
var health: Control
var cards: Array[Control] = []
var badges: Array[Control] = []
var failures: Array[String] = []
var checks := 0
var video_frame := 0
var log_rows: Array = []

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
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	world.get_node("Player").prepare_for_loading(gs)
	hud = world.get_node("GameplayHUD")
	health = hud.get_node("PlayerHealthHUD")
	cards.assign(health.get_children())
	for card in cards:
		badges.append(card.get_node("AnimatedSurface/StreakBadge"))
	gs.game_state = Constants.STATE_COUNTDOWN
	await frames(40)
	gs.game_state = Constants.STATE_PLAYING
	await frames(4)
	check(not badges[0].visible and not badges[1].visible, "no flame before any streak")

	await cross(true, true, "first_correct")
	check(gs.current_streak == 1 and gs.player2_streak == 1, "both players counted one correct answer")
	check(not badges[0].visible and not badges[1].visible, "a single correct answer does not light the flame")

	await cross(true, true, "ignite", 12)
	check(gs.current_streak == 2 and gs.player2_streak == 2, "two in a row for both players")
	check(badges[0].visible and badges[1].visible, "both flames lit at two in a row")
	await frames(40)
	await capture("both_streak_2")
	check(badges[0].get_node("StreakCount").text == "2" and badges[1].get_node("StreakCount").text == "2", "count shows 2")
	check(badges[0].get_node("StreakUnit").text == "連続", "Japanese unit next to the count")
	check_layout("both_streak_2")

	await cross(true, false, "p1_pop_p2_out", 12)
	check(gs.current_streak == 3 and gs.player2_streak == 0, "P1 continues, P2's wrong door breaks only P2's streak")
	check(badges[0].get_node("StreakCount").text == "3", "P1 count advanced to 3")
	await frames(40)
	check(badges[0].visible and not badges[1].visible, "P2 flame fully extinguished, P1 still burning")
	await capture("p1_3_p2_out")

	await cross(true, true, "p1_4")
	await cross(true, true, "p1_5_p2_2", 12)
	await frames(40)
	check(gs.current_streak == 5 and gs.player2_streak == 2, "streaks are tracked per player")
	check(float(badges[0].get("_heat")) > 1.1, "five in a row burns larger")
	check(badges[1].visible, "P2 flame re-ignites after a fresh two in a row")
	await capture("p1_5_p2_2")
	check_layout("p1_5_p2_2")

	# 長い正解数でもバッジはカードの中に収まる。
	gs.score = 12345
	gs.player2_score = 98
	await frames(40)
	await capture("long_scores")
	check_layout("long_scores")

	for child in hud.get_children():
		if child is Label and "連続" in (child as Label).text:
			check(false, "old top-right streak label still present")
	check(not hud.has_method("_update_streak_label"), "top-right streak updater removed")

	gs.game_state = Constants.STATE_GAME_OVER
	await frames(3)
	gs.game_state = Constants.STATE_PLAYING
	gs.score = 0
	gs.player2_score = 0
	gs.current_streak = 0
	gs.player2_streak = 0
	await frames(30)
	check(not badges[0].visible and not badges[1].visible, "reset clears both flames")

	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "video_frames": video_frame, "log": log_rows}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("STREAK_FLAME_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "video_frames": video_frame}))
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func check_layout(tag: String) -> void:
	for i in range(2):
		var badge := badges[i]
		if not badge.visible:
			continue
		var card_rect := cards[i].get_global_rect()
		var badge_rect := badge.get_global_rect()
		check(card_rect.encloses(badge_rect), "%s: P%d badge inside card %s in %s" % [tag, i + 1, badge_rect, card_rect])
		var unit: Label = cards[i].get_node("AnimatedSurface/ScoreUnit")
		var font: Font = unit.get_theme_font("font")
		var unit_end := unit.get_global_rect().position.x + font.get_string_size(unit.text, HORIZONTAL_ALIGNMENT_LEFT, -1, unit.get_theme_font_size("font_size")).x
		var score: Label = cards[i].get_node("AnimatedSurface/Score")
		var score_font: Font = score.get_theme_font("font")
		var score_end := score.get_global_rect().position.x + score_font.get_string_size(score.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score.get_theme_font_size("font_size")).x
		var after := unit_end if unit.visible else score_end
		check(badge_rect.position.x >= after - 0.5, "%s: P%d badge sits right of the correct count without overlap (%s >= %s)" % [tag, i + 1, badge_rect.position.x, after])
		check(badge_rect.end.y <= cards[i].get_global_rect().position.y + 39.0, "%s: P%d badge stays in the score row" % [tag, i + 1])

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func cross(correct1: bool, correct2: bool, tag: String, record_after := 0) -> void:
	gs.player_x = helper.door(gs, correct1) + (0.4 if correct1 == correct2 else 0.0)
	gs.player2_x = helper.door(gs, correct2) - (0.4 if correct1 == correct2 else 0.0)
	gs.world_scroll_z = gs.wall_z - 1.0
	gs.player_z = gs.wall_z - 1.0
	gs.player2_z = gs.wall_z - 1.0
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	world.set("_replay_mode", false)
	var before := gs.current_wall_index
	var changed := false
	for i in range(150):
		await frames(1)
		if gs.current_wall_index != before:
			changed = true
			break
	check(changed, tag + " actual wall crossed")
	for i in range(maxi(record_after, 1) * 3):
		await frames(1)
		if record_after > 0 and i % 2 == 0:
			await video_sample(tag)
	world.set("_replay_mode", true)

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")

func video_sample(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "frames/%04d.png" % video_frame)
	log_rows.append({"frame": video_frame, "tag": tag, "streak": [gs.current_streak, gs.player2_streak],
		"phase": [badges[0].get("_phase"), badges[1].get("_phase")], "visible": [badges[0].visible, badges[1].visible]})
	video_frame += 1
