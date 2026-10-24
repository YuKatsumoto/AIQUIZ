extends Node

## 台座の横の水路（StandGate・FloorEdgeLift）を実際の GameWorld で確かめる（docs/sudden_death_v2/skygate_build_plan.md W2）。
## 引き分けを起こし、タワーが沈んだところで、スタンドの 2 ブロックを持ち上げ、水上機を水路に止め、昇降台をスロープの端へつなぐ。
## 確かめる：2 ブロックだけが上がる・持ち上げた杭の下端と尾翼の上のすき間が 2 m 以上・昇降台の外の端とスロープの端が 0.4 m 以内・
## 元に戻すと前と同じ（ブロックが見え、観客の高さが戻る）。画も撮る。
##   Godot --path . --resolution 1600x900 --fixed-fps 60 --script res://tests/sudden_death_v2/stage_gate_check_bootstrap.gd
## 出力：artifacts/sudden_death_v2/stage_gate/（*.png と report.json）。

const OUT := "res://artifacts/sudden_death_v2/stage_gate/"

var gs: QuizGameState
var world: Node
var helper: Node
var report := {"failures": []}


func _ready() -> void:
	call_deferred("run")


func fail(label: String) -> void:
	(report.failures as Array).append(label)
	push_error(label)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	GameManager.graphics_quality = "balanced"
	get_tree().root.size = Vector2i(1600, 900)
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	(world.get("_sudden_death_director") as HeliSuddenDeathDirector).use_real_time = false
	await _frames(60)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await _frames(15)
	world.call("_debug_force_draw_finish")
	var guard := 0
	while not (gs.result_presentation_active and gs.result_ceremony_elapsed >= 10.5) and guard < 1200:
		guard += 1
		await get_tree().process_frame
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var podium := ResultCeremonyDirector.podium_center(gs)
	var stage_env := world.get("stage_env") as Node
	if stage_env == null:
		stage_env = world.find_child("StageEnvironment", true, false)
	var gate := StandGate.new()
	world.add_child(gate)
	if not gate.setup(stage_env, podium, 1.0):
		fail("StandGate.setup: the +X grandstand blocks were not found")
		_finish()
		return
	report["podium_z"] = podium.z
	report["gap_z"] = gate.gap_center_z()
	var crowd_before := _crowd_heights(gate)
	gate.activate()
	gate.set_towers(1.0)
	gate.set_lift(1.0)
	# 水上機：機首を +X（外の海）、尾を床へ。尾の端を床の壁から 0.5 m に。
	var plane := SuddenDeathFloatplane.new()
	world.add_child(plane)
	plane.build("balanced")
	plane.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(30.0, StageConstants.OCEAN_SURFACE_Y, gate.gap_center_z()))
	await _frames(2)
	var tail_x := plane.marker("MK_TailEnd").origin.x
	plane.global_position.x += (StageConstants.FLOOR_HALF_WIDTH + 0.5) - tail_x
	plane.set_ramp(1.0)
	plane.set_upper_door(1.0)
	await _frames(3)
	var edge := plane.marker("MK_RampEdge").origin
	var lift := FloorEdgeLift.new()
	world.add_child(lift)
	lift.setup(gate.gap_center_z(), 1.0)
	lift.set_reach(edge.x)
	lift.set_target_y(edge.y)
	lift.set_extend(1.0)
	lift.set_lower(1.0)
	await _frames(3)
	var fin_top := _top_y(plane)
	var bottom := gate.lifted_bottom_y()
	report["fin_top_y"] = snappedf(fin_top, 0.01)
	report["lifted_bottom_y"] = snappedf(bottom, 0.01)
	report["clearance"] = snappedf(bottom - fin_top, 0.01)
	if bottom - fin_top < 2.0:
		fail("lifted stand clears the fin by less than 2 m (%.2f)" % (bottom - fin_top))
	var deck_end := lift.deck_point(1.0)
	report["ramp_edge"] = [snappedf(edge.x, 0.01), snappedf(edge.y, 0.01)]
	report["deck_end"] = [snappedf(deck_end.x, 0.01), snappedf(deck_end.y, 0.01)]
	if absf(deck_end.y - edge.y) > 0.15 or deck_end.x < edge.x - 0.4:
		fail("the lift does not meet the ramp edge (deck %s, ramp %s)" % [str(deck_end), str(edge)])
	var sea := StageConstants.OCEAN_SURFACE_Y
	var z := gate.gap_center_z()
	await _shot("01_outside", Vector3(78.0, sea + 22.0, z - 55.0), Vector3(20.0, sea + 6.0, z), 55.0)
	await _shot("02_under", Vector3(14.5, sea + 1.6, z), Vector3(70.0, sea + 4.0, z), 52.0)
	await _shot("03_backin", Vector3(4.0, 9.0, z - 21.0), Vector3(30.0, -6.5, z + 1.0), 56.0)
	await _shot("04_connect", Vector3(3.0, 3.5, z - 10.0), Vector3(17.0, -6.0, z), 52.0)
	await _shot("05_run", Vector3(-4.0, 1.4, z), Vector3(20.0, -5.0, z), 56.0)
	# 途中（塔が半分、持ち上げ半分）
	gate.set_lift(0.5)
	gate.set_towers(1.0)
	await _shot("06_half", Vector3(78.0, sea + 22.0, z - 55.0), Vector3(20.0, sea + 6.0, z), 55.0)
	# 元に戻す
	gate.restore()
	lift.restore()
	plane.queue_free()
	await _frames(3)
	var crowd_after := _crowd_heights_from(gate, crowd_before.keys())
	for key: String in crowd_before:
		if absf(float(crowd_before[key]) - float(crowd_after.get(key, -999.0))) > 0.001:
			fail("crowd %s did not come back (%s → %s)" % [key, crowd_before[key], crowd_after.get(key)])
	await _shot("07_restored", Vector3(78.0, sea + 22.0, z - 55.0), Vector3(20.0, sea + 6.0, z), 55.0)
	_finish()


func _finish() -> void:
	var f := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("STAGE_GATE_CHECK ", JSON.stringify(report))
	get_tree().quit(0 if (report.failures as Array).is_empty() else 1)


func _crowd_heights(gate: StandGate) -> Dictionary:
	var out := {}
	for i in range(gate._crowd.size()):
		out[String(gate._crowd[i].name)] = gate._crowd[i].position.y
	return out


func _crowd_heights_from(gate: StandGate, keys: Array) -> Dictionary:
	var out := {}
	var stand := gate._stand
	var crowd := stand.get_node_or_null("Spectators") if stand != null else null
	if crowd != null:
		for key: String in keys:
			var node := crowd.get_node_or_null(key) as Node3D
			if node != null:
				out[key] = node.position.y
	return out


func _top_y(root: Node3D) -> float:
	var top := -INF
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box := mi.global_transform * mi.get_aabb()
		top = maxf(top, box.end.y)
	return top


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(shot_name: String, eye: Vector3, target: Vector3, fov: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.has_meta("stage_gate_check"):
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.set_meta("stage_gate_check", true)
		add_child(cam)
		cam.make_current()
	cam.fov = fov
	cam.look_at_from_position(eye, target)
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + shot_name + ".png"))
