extends Node

## 2Pでカメラが後ろへ引いて現在の壁の文字が拡大するとき、奥にある壁も同時に拡大し、
## 戻るときも一緒に等倍へ戻ることの確認。

const OUT := "res://artifacts/wall_text_far/"
var gs: QuizGameState
var world: Node3D
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var helper: Node = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true) # 描画は進め、シミュレーションは止めて位置を直接指定する。
	world.get_node("Player").prepare_for_loading(gs)
	await frames(60)

	await place(false)
	check(walls().size() >= 2, "at least two walls exist (%d)" % walls().size())
	check_all(false, "camera at base position: every wall at 1x")
	await capture("base")

	await place(true)
	check(current_wall().is_text_enlarged(), "current wall enlarges when the camera pulls back")
	check_all(true, "pulled back: every wall, including those further ahead, is enlarged")
	await capture("pulled_back")

	await place(false)
	check_all(false, "camera returns: every wall returns to 1x together")

	var report := {"passed": failures.is_empty(), "failures": failures}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WALL_TEXT_SYNC " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func walls() -> Array:
	return world.get("_active_walls").filter(func(w): return is_instance_valid(w))

func current_wall() -> Node3D:
	for wall: Node3D in walls():
		if int(wall.get_meta("wall_index", -1)) == gs.current_wall_index:
			return wall
	return null

func check_all(enlarged: bool, label: String) -> void:
	for wall: Node3D in walls():
		var expected := 1.5 if enlarged else 1.0
		check(wall.is_text_enlarged() == enlarged and absf(float(wall.get("_text_scale")) - expected) < 0.01,
			"%s (wall %d: enlarged=%s scale=%f)" % [label, int(wall.get_meta("wall_index", -1)), wall.is_text_enlarged(), float(wall.get("_text_scale"))])

## back_edge: プレイヤーを床の後端に寄せ、後方ローラー端へのカメラの引きを起こす。
func place(back_edge: bool) -> void:
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = gs.wall_z - 12.0
	var z := gs.world_scroll_z + (StageConstants.FLOOR_BACK_Z + 0.5 if back_edge else 0.0)
	gs.player_z = z
	gs.player2_z = z
	gs.player_x = -2.0
	gs.player2_x = 2.0
	await frames(420)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
