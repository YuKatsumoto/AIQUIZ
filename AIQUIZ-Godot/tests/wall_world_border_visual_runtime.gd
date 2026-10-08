extends Node
## 描画ありで起動し、壁の延長線上を前へ抜けようとしたプレイヤーの前にワールドボーダーが浮かび、押し戻す様子を撮る。
## godot --path . -s res://tests/wall_world_border_visual_bootstrap.gd

const OUT := "res://artifacts/wall_world_border/"
var gs: QuizGameState
var world: Node3D
var helper: Node
var failures: Array[String] = []
var checks := 0
var pushes: Array[int] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	helper = load("res://tests/hp_unit.gd").new()
	QuizManager.player_analytics = null
	await scenario("solo", 1)
	await scenario("duo", 2)
	print("WALL_WORLD_BORDER_VISUAL " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	for provider in helper.providers:
		provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func scenario(tag: String, players: int) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	gs = helper.fixture(players)
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await frames(50)
	# 壁端の外（線路側）に立たせ、コンベアで壁の線へ運ばせる。2P は P2 を反対側の端へ。
	var edge_x := StageConstants.QUIZ_WALL_HALF_WIDTH + 0.25
	gs.player_x = edge_x
	gs.player2_x = -edge_x if players == 2 else -7.0
	gs.world_scroll_z = gs.wall_z - 1.6
	gs.player_z = gs.world_scroll_z
	gs.player2_z = gs.world_scroll_z
	await frames(3)
	await capture(tag + "_before")
	pushes.clear()
	gs.world_border_pushed.connect(_on_pushed)
	world.set("_replay_mode", false)
	var max_z := -INF
	var captured_push := false
	for i in range(240):
		await frames(1)
		max_z = maxf(max_z, gs.player_z)
		if not pushes.is_empty() and not captured_push:
			captured_push = true
			await frames(2)
			await capture(tag + "_push")
	await capture(tag + "_after")
	check(pushes.has(1), tag + " P1 pushed (pushes=%s, z-wall=%.2f)" % [str(pushes), gs.player_z - gs.wall_z])
	check(max_z <= gs.wall_z - QuizGameState.WALL_WORLD_BORDER_STOP_DISTANCE + 0.0001, tag + " P1 never passes the wall line")
	check(gs.p1_alive and gs.get_player_hp(1) == gs.MAX_HP, tag + " P1 not damaged by the border")
	if players == 2:
		check(pushes.has(2), tag + " P2 pushed")
		check(gs.p2_alive and gs.get_player_hp(2) == gs.MAX_HP, tag + " P2 not damaged by the border")
	var wall := _current_wall()
	var border := wall.get_node_or_null("WorldBorder") as Node3D if wall else null
	check(border != null and border.visible, tag + " current wall shows its border")
	world.set("_replay_mode", true)

func _on_pushed(player_index: int) -> void:
	pushes.append(player_index)

func _current_wall() -> Node3D:
	for wall: Node in world.get_node("WallContainer").get_children():
		if wall.has_meta("wall_index") and int(wall.get_meta("wall_index")) == gs.current_wall_index:
			return wall as Node3D
	return null

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
