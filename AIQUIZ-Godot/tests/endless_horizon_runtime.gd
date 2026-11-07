extends Node

## エンドレスのコースが地平線まで続いて見えるかの撮影（ウィンドウあり・Forward+・1280x720 固定）。
## 直接は起動できないので
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/endless_horizon_bootstrap.gd --fixed-fps 60 -- tag=after
## 引数（"--" の後ろ）: tag=<名前>（既定 adhoc）、quality=low|balanced|high|ultra（既定 high）
## 画像と report.json は artifacts/endless_horizon/<tag>/<quality>/。
##
## 本番の res://scenes/game_world.tscn を tests/hp_unit.gd の fixture(2, ENDLESS) で PLAYING のまま組み、
## _replay_mode=true で状態を止める（ground_look_runtime.gd と同じ組み方）。カメラは GameWorld 自身の Camera3D。
## ほかに、両者脱落でゴールが決まってもコースの先にゴールを出さず、地平線まで続いたままなことも確かめる
## （エンドレスの2人の結果発表は結果発表アリーナ。tests/result_arena_runtime.gd）。

const OUT_ROOT := "res://artifacts/endless_horizon/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const VIEWPORT_SIZE := Vector2i(1280, 720)
const STATION_SCROLL_Z := 100.0
const STATION_WALL_INDEX := 3
const DAY_PHASE := 0.25
const SLOT_FRAMES := 30

## eye / target はワールド座標（ランナーは局所 z=0、壁 3 枚目が 12 m 先、最奥の壁が 132 m 先）。
## eye が空なら本番の 2P カメラ（CameraController.get_gameplay_pose）。
const SHOTS := [
	{"id": "01_gameplay_2p", "what": "本番の 2P カメラ"},
	{"id": "02_high_course", "eye": Vector3(0.0, 16.0, -14.0), "target": Vector3(0.0, 1.0, 160.0), "fov": 55.0,
		"what": "コース全体を後ろの上から。壁の先にコースが続くか"},
	{"id": "03_past_last_wall", "eye": Vector3(0.0, 9.0, 140.0), "target": Vector3(0.0, 0.0, 700.0), "fov": 55.0,
		"what": "最奥の壁を越えた先。動的な床の前端（172 m）から地平線まで"},
	{"id": "04_low_horizon", "eye": Vector3(6.0, 2.0, 150.0), "target": Vector3(0.0, -1.0, 1500.0), "fov": 45.0,
		"what": "低い視点で、コースが地平線へ消える所"},
]

var quality := "high"
var tag := "adhoc"
var out := ""
var checks := 0
var failures: Array[String] = []
var report := {}
var helper: Node
var gs: QuizGameState
var world: Node
var saved_game_state: QuizGameState
var saved_analytics: Variant


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
	out = OUT_ROOT + tag + "/" + quality + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	get_tree().root.size = VIEWPORT_SIZE
	AudioServer.set_bus_mute(0, true)
	# 設定ファイルには保存しない（ground_look と同じ）。
	GameManager.graphics_quality = quality
	GameManager.settings_path = "user://endless_horizon_settings.json"
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	saved_game_state = QuizManager.game_state
	saved_analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	await _build_world()
	report["shots"] = await _shots()
	report["goal"] = await _goal_ends_course()
	_finish()


func _build_world() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	gs.current_index = STATION_WALL_INDEX
	gs.current_wall_index = STATION_WALL_INDEX
	gs.load_current_quiz()
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	world = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	# 本番と同じく、まずフライオーバー（エンドレスは 25 枚分の長い床）を通す。客席はそこで伸び、プレイ中も縮まない。
	gs.game_state = Constants.STATE_FLYOVER
	gs.flyover_total_walls = 25
	await frames(90)
	gs.game_state = Constants.STATE_PLAYING
	_set_station()
	await frames(60)
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle")
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	check(not is_instance_valid(world.get("_goal_stand")), "endless play shows no goal stand")
	report["stage"] = _stage_info(stage)
	report["backdrop"] = _backdrop_info(stage)
	check(is_equal_approx(stage.get_floor_length(), gs.get_floor_front_z() - gs.FLOOR_BACK_Z),
		"the gameplay floor (collision) keeps the game state's length")
	if stage.has_method(&"get_floor_runout_length"):
		check(float(report.stage["get_floor_runout_length"]) == StageConstants.COURSE_HORIZON_RUNOUT,
			"endless play runs the course out to the horizon")
		check(not bool(report.stage["front_roller_visible"]), "the front roller is hidden while the course runs on")


func _set_station() -> void:
	gs.world_scroll_z = STATION_SCROLL_Z
	gs.player_x = -2.0
	gs.player2_x = 2.0
	gs.player_z = STATION_SCROLL_Z
	gs.player2_z = STATION_SCROLL_Z
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.camera_shake = 0.0


func _stage_info(stage: StageEnvironment) -> Dictionary:
	var info := {"floor_center_z": stage.get_floor_center_z(), "floor_length": stage.get_floor_length(),
		"floor_front_z": stage.get_floor_center_z() + stage.get_floor_length() * 0.5}
	for method: StringName in [&"get_floor_runout_length", &"get_visual_floor_front_z"]:
		if stage.has_method(method):
			info[String(method)] = stage.call(method)
	var roller := stage.get_node_or_null("ConveyorRollerFront") as Node3D
	info["front_roller_visible"] = roller != null and roller.visible
	var stands := stage.get_node_or_null("Grandstands") as Node3D
	if stands != null:
		for stand: Node in stands.get_children():
			info["stand_blocks"] = stand.get("block_count")
	return info


## 遠景（島・街）の位置。コースの延長がそれらとどう重なるかを決める材料。
func _backdrop_info(stage: StageEnvironment) -> Dictionary:
	var info := {}
	var scenery := stage.get_node_or_null("StadiumBackdrop/Scenery")
	if scenery == null:
		return info
	for child: Node in scenery.get_children():
		var bounds := AABB()
		var first := true
		for mesh: Node in [child] + child.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		if not first:
			info[String(child.name)] = {"min": [snappedf(bounds.position.x, 1), snappedf(bounds.position.y, 1), snappedf(bounds.position.z, 1)],
				"max": [snappedf(bounds.end.x, 1), snappedf(bounds.end.y, 1), snappedf(bounds.end.z, 1)]}
	return info


func _shots() -> Array:
	var saved: Array = []
	var cc: Node3D = world.get("camera_controller")
	for shot: Dictionary in SHOTS:
		_set_station()
		if shot.has("eye"):
			_aim(shot.eye, shot.target, float(shot.fov))
		else:
			var pose: Dictionary = cc.call("get_gameplay_pose", gs)
			_aim(pose.eye, pose.target, float(pose.fov))
		await frames(SLOT_FRAMES)
		await RenderingServer.frame_post_draw
		var path := out + String(shot.id) + ".png"
		var error := get_viewport().get_texture().get_image().save_png(path)
		check(error == OK, "saved " + path)
		saved.append({"id": shot.id, "what": shot.what, "path": ProjectSettings.globalize_path(path)})
	return saved


## 両者脱落でゴールが決まっても（エンドレスの2人の結果発表の前の待ち）、コースの先にゴールは出さない
## （結果発表は結果発表アリーナ）。コースは地平線まで続いたまま。
func _goal_ends_course() -> Dictionary:
	var stage: StageEnvironment = world.get("stage_env")
	gs.endless_result_wall_count = STATION_WALL_INDEX + 4
	gs.goal_z = gs.tuning.wall_start_z + gs.endless_result_wall_count * gs.tuning.wall_spacing + 15.0
	gs.game_state = Constants.STATE_GAME_OVER
	gs.elimination_result_pending = true
	await frames(10)
	check(not is_instance_valid(world.get("_goal_stand")), "no goal stand at the end of the endless course")
	var info := _stage_info(stage)
	if stage.has_method(&"get_floor_runout_length"):
		check(float(info["get_floor_runout_length"]) == StageConstants.COURSE_HORIZON_RUNOUT, "the course still runs to the horizon")
	gs.elimination_result_pending = false
	gs.game_state = Constants.STATE_PLAYING
	gs.endless_result_wall_count = 0
	gs.goal_z = 0.0
	await frames(10)
	return info


func _aim(eye: Vector3, target: Vector3, fov: float) -> void:
	var cc: Node3D = world.get("camera_controller")
	cc.call("set_director_pose", Transform3D(Basis.looking_at((target - eye).normalized(), Vector3.UP), eye), fov)


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _finish() -> void:
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	report["tag"] = tag
	report["quality"] = quality
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("ENDLESS_HORIZON " + JSON.stringify({"passed": report.passed, "failures": failures, "stage": report.get("stage", {}),
		"goal": report.get("goal", {})}))
	if is_instance_valid(world):
		get_tree().current_scene = null
		world.queue_free()
	QuizManager.game_state = saved_game_state
	QuizManager.player_analytics = saved_analytics
	get_tree().quit(0 if failures.is_empty() else 1)
