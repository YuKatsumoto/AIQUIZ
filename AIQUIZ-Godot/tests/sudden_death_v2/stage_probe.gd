extends Node

## サドンデスの水上機の水路（docs/sudden_death_v2/c130_float.md）を決めるため、引き分けの台座のまわりを実際の GameWorld で測る。
## 引き分けを起こし、台座が出たところで、横のスタンドのブロック・ゴールの観客席・ゴールの門・床・海の位置（ワールドの AABB）を書き出し、
## 真上（正射影）・海の高さ・斜め上から画像を撮る。
##   Godot --path . --resolution 1600x900 --script res://tests/sudden_death_v2/stage_probe_bootstrap.gd
## 出力：artifacts/sudden_death_v2/c130_float/stage_probe/（*.png と layout.json）。

const OUT := "res://artifacts/sudden_death_v2/c130_float/stage_probe/"

var gs: QuizGameState
var world: Node
var helper: Node
var report := {}


func _ready() -> void:
	call_deferred("run")


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
	var director := world.get("_sudden_death_director") as HeliSuddenDeathDirector
	director.use_real_time = false
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
	# 両方のタワーが床まで沈みきったあと（10.4 秒）、種目発表（11.0 秒）の前
	while not (gs.result_presentation_active and gs.result_ceremony_elapsed >= 10.5) and guard < 1200:
		guard += 1
		await get_tree().process_frame
	await _frames(10)
	_measure()
	await _captures()
	var f := FileAccess.open(OUT + "layout.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("STAGE_PROBE ", JSON.stringify(report.get("summary", {})))
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _box_dict(b: AABB) -> Dictionary:
	return {"min": [snappedf(b.position.x, 0.01), snappedf(b.position.y, 0.01), snappedf(b.position.z, 0.01)],
		"max": [snappedf(b.end.x, 0.01), snappedf(b.end.y, 0.01), snappedf(b.end.z, 0.01)]}


func _measure() -> void:
	var podium := ResultCeremonyDirector.podium_center(gs)
	report["podium_center"] = [podium.x, podium.y, podium.z]
	report["floor_top_y"] = StageConstants.FLOOR_TOP_Y
	report["ocean_surface_y"] = StageConstants.OCEAN_SURFACE_Y
	report["floor_half_width"] = StageConstants.FLOOR_HALF_WIDTH
	var goal_stand := world.get("_goal_stand") as Node3D
	if goal_stand != null:
		report["goal_stand"] = _box_dict(_aabb(goal_stand))
	var goal_line := world.get("_goal_line_node") as Node3D
	if goal_line != null:
		report["goal_line"] = _box_dict(_aabb(goal_line))
		report["goal_line_position"] = [goal_line.global_position.x, goal_line.global_position.y, goal_line.global_position.z]
	var stands := []
	for node: Node in world.find_children("Grandstand*", "Node3D", true, false):
		var stand := node as Node3D
		var blocks_node := stand.get_node_or_null("Blocks")
		var blocks := []
		if blocks_node != null:
			for b: Node in blocks_node.get_children():
				if b is Node3D:
					var box := _aabb(b)
					if absf(box.get_center().z - podium.z) < 80.0:
						blocks.append({"name": String(b.name), "box": _box_dict(box)})
		stands.append({"name": String(stand.name), "box": _box_dict(_aabb(stand)), "blocks_near_podium": blocks})
	report["stands"] = stands
	# まとめ：台座の前後で、横の海（床の端〜スタンドの内側）がどこまで開いているか
	var summary := {"podium_z": podium.z, "floor_above_sea": StageConstants.FLOOR_TOP_Y - StageConstants.OCEAN_SURFACE_Y}
	for s: Dictionary in stands:
		var box: Dictionary = s.box
		summary[s.name] = {"x": [box.min[0], box.max[0]], "z": [box.min[2], box.max[2]], "top_y": box.max[1]}
	if report.has("goal_stand"):
		summary["goal_stand"] = {"x": [report.goal_stand.min[0], report.goal_stand.max[0]], "z": [report.goal_stand.min[2], report.goal_stand.max[2]],
			"top_y": report.goal_stand.max[1]}
	report["summary"] = summary


func _captures() -> void:
	var podium := ResultCeremonyDirector.podium_center(gs)
	# 2D の表示（DRAW! や得点の札）は隠して撮る（絵の下絵に使うため）
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	cam.make_current()
	# 真上（正射影、120 m × 67.5 m）。上が +Z（ゴールの側）、右が +X
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 90.0
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, 1)), podium + Vector3(0.0, 120.0, 12.0))
	await _shot(cam, "top_ortho")
	cam.size = 160.0
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, 1)), podium + Vector3(0.0, 200.0, 20.0))
	await _shot(cam, "top_ortho_wide")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 55.0
	# 海の高さから、台座の横（+X の側）の海と床の端とスタンドを見る
	var sea := StageConstants.OCEAN_SURFACE_Y
	cam.look_at_from_position(Vector3(19.5, sea + 1.6, podium.z - 34.0), Vector3(19.5, sea + 4.0, podium.z + 10.0))
	await _shot(cam, "channel_sea_level")
	# 斜め上から台座とゴールのまわり
	cam.look_at_from_position(Vector3(46.0, sea + 34.0, podium.z - 30.0), Vector3(8.0, sea + 4.0, podium.z + 8.0))
	await _shot(cam, "oblique")
	# 外の海の上から、台座の横のスタンドと床（水上機が入ってくる側）を見る
	cam.look_at_from_position(Vector3(78.0, sea + 22.0, podium.z - 28.0), Vector3(14.0, sea + 5.0, podium.z + 2.0))
	await _shot(cam, "outside_sea")
	# 床の上から、横のスタンドの方
	cam.look_at_from_position(Vector3(-4.0, StageConstants.FLOOR_TOP_Y + 2.5, podium.z - 6.0), Vector3(24.0, StageConstants.FLOOR_TOP_Y + 1.0, podium.z + 2.0))
	await _shot(cam, "from_floor")
	await _boarding_shots(cam, podium)


## 水上機の乗り込みの絵コンテ（docs/sudden_death_v2/c130_float.md 第6章）のカメラの位置。Codex の下絵に使う。
## 水上機は台座の +X の側（画面の左）の水路に、尾を床の壁（x=12.5）へ向けて止まる（機体の中心 z=25）。
const BOARDING_SHOTS := [
	["b1_lift", Vector3(-7.0, 7.0, -2.0), Vector3(26.0, 2.0, 30.0), 58.0],
	["b2_flyover", Vector3(-3.0, 2.2, 14.0), Vector3(18.0, 14.0, 30.0), 64.0],
	["b3_splash", Vector3(14.5, -7.6, 25.0), Vector3(70.0, -6.0, 25.0), 52.0],
	["b4_backin", Vector3(4.0, 9.0, 4.0), Vector3(30.0, -6.5, 26.0), 56.0],
	["b5_connect", Vector3(3.0, 3.5, 15.0), Vector3(17.0, -6.0, 25.0), 52.0],
	["b6_run", Vector3(-4.0, 1.4, 25.0), Vector3(20.0, -5.0, 25.0), 56.0],
	["b8_takeoff", Vector3(-10.0, 4.5, -4.0), Vector3(60.0, -2.0, 32.0), 56.0],
]


func _boarding_shots(cam: Camera3D, podium: Vector3) -> void:
	var dz := podium.z - 27.7
	for row: Array in BOARDING_SHOTS:
		var eye: Vector3 = row[1]
		var target: Vector3 = row[2]
		cam.fov = float(row[3])
		cam.look_at_from_position(eye + Vector3(0, 0, dz), target + Vector3(0, 0, dz))
		await _shot(cam, String(row[0]))


func _shot(cam: Camera3D, name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
