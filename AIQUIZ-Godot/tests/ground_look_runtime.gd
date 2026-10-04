extends Node

## 地上（本編）ステージの見た目と GPU 時間のベースライン（ウィンドウあり・Forward+・1280x720 固定）。
## 直接は起動できないので
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/ground_look_bootstrap.gd --fixed-fps 60 -- quality=high shots perf frames=300 tag=before
## 引数（"--" の後ろ）:
##   quality=low|balanced|high|ultra   画質（既定 high）。1 プロセスにつき 1 画質（本番と同じく、ステージは画質を決めてから組む）
##   tag=<名前>                        出力先 artifacts/ground_quality/<tag>/<quality>/（既定 adhoc）
##   shots                             PNG 撮影（SHOTS の構図。番号つき NN_名前.png）
##   perf                              GPU/CPU 時間（p50/p95/p99）、描画呼び出し、プリミティブ、ビデオメモリ
##   frames=<N>                        perf の 1 ビューあたりの計測フレーム数（既定 300）
##   menu=0                            メニュー背景の撮影・計測を省く
##   only=<id先頭>,<id先頭>             構図の調整用。id がこれで始まる SHOTS だけを撮る（例 only=03,05）
##   compare tagA=<名前> tagB=<名前> quality=<画質>   2 回の撮影の画像差分（撮影を行わない。再現性の確認用）
## shots と perf のどちらも付けなければ両方行う。
##
## 組み立て（report.json の "assembly" にも同じ内容を書く）:
##   ・本番と同じ res://scenes/game_world.tscn（GameWorld）を、tests/hp_unit.gd の fixture() による
##     ローカル 2P・10 問・PLAYING の状態で組む。_replay_mode=true で game_state.update() を止め、状態は動かさない。
##     壁・ゴールゲート・ゴール台・観客スタンド・海・空・ランナー 2 体はすべて実物（GameWorld が毎フレーム更新する）。
##   ・カメラは GameWorld 自身の Camera3D（far=5000）を CameraController.set_director_pose() で固定する。
##     標準構図は本番の 2P カメラと同じ姿勢（get_gameplay_pose と一致することを report に記録する）。
##   ・時間で動くものを固定する。ベルト: world_scroll_z=STATION_SCROLL_Z、壁: current_wall_index=STATION_WALL_INDEX、
##     昼: WeatherCycle.force_day_phase(0.25)。海・雲は TIME 依存なので、--fixed-fps 60 のもとで各ショットを
##     「プロセスフレーム番号の決まった位置」で撮る（SCHEDULE_BASE_FRAME + 番号 * スロット長）。同じ画質・同じ引数なら
##     TIME も同じになる。ロード時間が長引いて基準フレームを越えたら report の schedule_base_frame に実値が出る。
##   ・メニュー背景は res://ui/main_menu.tscn の MenuWallBackgroundPreview の SubViewport（3D のみ）を撮る。AI の動きは非決定。
## 画質は GameManager.graphics_quality への直接代入（設定ファイルに保存しない）。GameManager.settings_path も
## user://ground_look_settings.json に逸らし、実行の前後で user://settings.json のハッシュが変わらないことを確かめる。
## Ultra の適応スーパーサンプルは、撮影と report.perf（pinned）では上限に固定し（budget を大きくして降りない。
## 画質が Ultra 以外なら適応はないので pinned がそのまま本番どおり）、Ultra だけ report.perf_adaptive で
## 本番どおり適応させて、その時々のスケール（scale_3d_*、scale_log_settle_1s）を記録する。
## report の読み方: perf.views.<id>.gpu_p50/p95/p99 = ルートビューポートの GPU 描画時間 ms、gpu_all_viewports_* = 全 SubViewport 込み、
## cpu_* = フレーム間隔 ms（vsync なし）、draw_calls_* / primitives_* / objects_p50 = フレーム内の合計（影・SubViewport 込み）。

const OUT_ROOT := "res://artifacts/ground_quality/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const VIEWPORT_SIZE := Vector2i(1280, 720)

# ------------------------------------------------------------------ 構図（レーン A〜D が同じ構図で撮り直せるよう定数にまとめる）

## ステージの状態（全ショット共通）。world_scroll_z は壁の位置とベルトの縞の位相を決める。
## 壁 STATION_WALL_INDEX は wall_start_z(22) + 30*3 = 112 なので、ランナー（局所 z=0）の 12 m 先。
## ゴールは局所 z = 337 - 100 = 237（ゲート）、ゴール台はその 25.8 m 先。座標はすべて GameWorld のワールド座標。
const STATION_SCROLL_Z := 100.0
const STATION_WALL_INDEX := 3
const RUNNER_X := [-2.0, 2.0]
const DAY_PHASE := 0.25
## 撮影の時刻表。ショット i は SCHEDULE_BASE_FRAME + 累計スロット長 のフレームで構図に入り、そのスロットの最後に撮る。
const SCHEDULE_BASE_FRAME := 600
const DEFAULT_SLOT_FRAMES := 30

## id: ファイル名 / eye, target: カメラ位置と注視点 / fov: 縦画角 / runners_z: ランナー 2 体の局所 z（ワールド z - STATION_SCROLL_Z）
## slot: 構図に入ってから撮るまでのフレーム数（群衆など時間で立ち上がるものの待ち） / what: 何を見る構図か
const SHOTS := [
	{"id": "01_standard_2p_day", "eye": Vector3(0.0, 4.5, -9.0), "target": Vector3(0.0, 1.0, 8.0), "fov": 50.0, "runners_z": 0.0,
		"what": "2P 標準カメラ（昼）。CameraController.TWO_PLAYER_* と同じ姿勢"},
	{"id": "02_floor_belt_rail_oblique", "eye": Vector3(3.5, 1.9, -4.0), "target": Vector3(9.0, -1.2, 5.0), "fov": 55.0, "runners_z": -9.0,
		"what": "床の寄り。ベルトの縞と右のレール（x=11.86）を斜め上から。ランナーはカメラの後ろへ退避"},
	{"id": "03_roller_sideframe_close", "eye": Vector3(-6.0, 0.4, -19.0), "target": Vector3(-3.0, -1.7, -12.5), "fov": 55.0, "runners_z": 0.0,
		"what": "手前（後端）ローラーとベルトの折り返し、サイドフレームの端。後端の外側の海から"},
	{"id": "04_wall_door_approach", "eye": Vector3(0.0, 2.3, 0.5), "target": Vector3(0.0, 1.7, 12.0), "fov": 55.0, "runners_z": 8.0,
		"what": "壁とドアへの接近。壁は 12 m 先、ランナーは壁の 3.5 m 手前。問題文つき"},
	{"id": "05_stands_left", "eye": Vector3(-6.0, 3.2, -6.0), "target": Vector3(-30.0, 5.0, 2.0), "fov": 55.0, "runners_z": 0.0,
		"what": "左スタンド（x=-28）の観客席"},
	{"id": "05b_stands_right", "eye": Vector3(6.0, 3.2, -6.0), "target": Vector3(30.0, 5.0, 2.0), "fov": 55.0, "runners_z": 0.0,
		"what": "右スタンド（x=+28）の観客席"},
	{"id": "06_goal_gate_stand", "eye": Vector3(0.0, 3.2, 212.0), "target": Vector3(0.0, 4.5, 250.0), "fov": 55.0, "runners_z": 222.0, "slot": 60,
		"what": "ゴールゲートとゴール台（ゲート局所 z=237、台は +25.8 m）。ランナーはゲートの手前 15 m"},
	{"id": "07_horizon_low_sea_sky", "eye": Vector3(0.0, 0.6, 2.0), "target": Vector3(0.0, 1.6, -300.0), "fov": 60.0, "runners_z": 25.0,
		"what": "低い視点で、ベルト後端の先の空と海の水平線。ランナーはカメラの後ろへ退避"},
]
## perf で順に計測するビュー（SHOTS の id）。ほかに scroll_run（標準構図でベルトと壁が流れる）と、最後にメニュー背景。
const PERF_VIEWS := ["01_standard_2p_day", "02_floor_belt_rail_oblique", "04_wall_door_approach", "05_stands_left", "06_goal_gate_stand", "07_horizon_low_sea_sky"]
## scroll_run: 壁速度 m/s（fixture の wall_speed_override と同じ）。STATION_SCROLL_Z から SCROLL_RUN_SPAN m の間を繰り返す。
const SCROLL_RUN_SPEED := 2.9
const SCROLL_RUN_SPAN := 9.0
## 適応スーパーサンプルを上限に固定する budget（ms）。
const PIN_BUDGET_MS := 100000.0
const ADAPTIVE_SETTLE_SEC := 12.0
const WARMUP_FRAMES_PER_VIEW := 40

var quality := "high"
var tag := "adhoc"
var do_shots := true
var do_perf := true
var do_menu := true
var do_compare := false
var only_prefixes: Array[String] = []
var tag_a := ""
var tag_b := ""
var perf_frames := 300
var out := ""
var checks := 0
var failures: Array[String] = []
var report := {}

var helper: Node
var gs: QuizGameState
var world: Node
## `sun=x,y,z`: the noon sun's direction (toward the sun), tried without touching
## assets/environment/sky/day_night_sun_path.tscn. Zero = the authored orbit.
var sun_override := Vector3.ZERO
var saved_game_state: QuizGameState
var saved_analytics: Variant
var hidden_layers: Dictionary = {}
var settings_digest_before := ""


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var only_shots := "shots" in args
	var only_perf := "perf" in args
	if only_shots or only_perf:
		do_shots = only_shots
		do_perf = only_perf
	do_compare = "compare" in args
	for arg: String in args:
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
		elif arg.begins_with("frames="):
			perf_frames = maxi(30, int(arg.trim_prefix("frames=")))
		elif arg.begins_with("tagA="):
			tag_a = arg.trim_prefix("tagA=").validate_filename()
		elif arg.begins_with("tagB="):
			tag_b = arg.trim_prefix("tagB=").validate_filename()
		elif arg == "menu=0":
			do_menu = false
		elif arg.begins_with("sun="):
			var parts := arg.trim_prefix("sun=").split(",", false)
			if parts.size() == 3:
				sun_override = Vector3(float(parts[0]), float(parts[1]), float(parts[2])).normalized()
		elif arg.begins_with("only="):
			for prefix in arg.trim_prefix("only=").split(",", false):
				only_prefixes.append(prefix)
	if do_compare:
		_compare()
		return
	out = OUT_ROOT + tag + "/" + quality + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_prepare_runtime()
	report["tool"] = "ground_look"
	report["tag"] = tag
	report["quality"] = quality
	report["args"] = Array(args)
	report["command"] = "Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/ground_look_bootstrap.gd --fixed-fps 60 -- quality=%s%s%s frames=%d tag=%s" % [
		quality, " shots" if do_shots else "", " perf" if do_perf else "", perf_frames, tag]
	report["assembly"] = _assembly_notes()
	report["constants"] = {"station_scroll_z": STATION_SCROLL_Z, "station_wall_index": STATION_WALL_INDEX, "day_phase": DAY_PHASE,
		"schedule_base_frame": SCHEDULE_BASE_FRAME, "default_slot_frames": DEFAULT_SLOT_FRAMES, "perf_frames": perf_frames}
	var started := Time.get_ticks_msec()
	if not await _build_world():
		_finish()
		return
	report["load_ms"] = Time.get_ticks_msec() - started
	report["world_ready_frame"] = Engine.get_process_frames()
	if do_shots:
		report["shots"] = await _shots()
	if do_perf:
		report["perf"] = await _perf(false)
		if quality == GraphicsQualityRules.ULTRA:
			report["perf_adaptive"] = await _perf(true)
	if do_shots or do_perf:
		await _teardown_world()
		if do_menu:
			report["menu"] = await _menu(do_shots, do_perf)
	_finish()


# ------------------------------------------------------------------ setup

func _prepare_runtime() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	AudioServer.set_bus_mute(0, true)
	settings_digest_before = _settings_digest()
	# The setter would persist the choice; a plain assignment is in memory only (cistern_look does the same).
	GameManager.graphics_quality = quality
	GameManager.settings_path = "user://ground_look_settings.json"
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	saved_game_state = QuizManager.game_state
	saved_analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	_apply_sun_override()


## WeatherCycle reads the orbit of the authored scene once and keeps it in statics; replacing the
## basis before the first WeatherCycle is built moves the (locked) noon sun without editing the scene.
## The sunrise axis (local Z) stays as authored, the noon sun (local Y) becomes `sun_override`.
func _apply_sun_override() -> void:
	if sun_override == Vector3.ZERO:
		return
	var up := sun_override.normalized()
	var rise := Vector3(-0.82110924, 0.0, -0.57077104)
	var z_axis := (rise - up * rise.dot(up)).normalized()
	var x_axis := up.cross(z_axis).normalized()
	WeatherCycle._shared_orbit_basis = Basis(x_axis, up, z_axis)
	WeatherCycle._shared_orbit_basis_ready = true
	report["sun_override"] = [snappedf(up.x, 0.001), snappedf(up.y, 0.001), snappedf(up.z, 0.001)]


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


func _assembly_notes() -> Dictionary:
	return {
		"world": "res://scenes/game_world.tscn (real GameWorld) + tests/hp_unit.gd fixture(2): local 2P, MODE_TEN, STATE_PLAYING, _replay_mode=true (game_state.update stopped)",
		"camera": "GameWorld's own Camera3D via CameraController.set_director_pose(); far=5000, near=0.1 as in the game",
		"fixed_state": "world_scroll_z=%.1f, current_wall_index=%d, force_day_phase(%.2f); shots on a process-frame schedule from frame %d (TIME-dependent sea and clouds repeat)" % [
			STATION_SCROLL_Z, STATION_WALL_INDEX, DAY_PHASE, SCHEDULE_BASE_FRAME],
		"goal": "the real goal gate and GoalStand, 237 m ahead of the runners in this state (the camera is placed there; not a stage approximation)",
		"menu": "res://ui/main_menu.tscn -> MenuWallBackgroundPreview SubViewport (3D only); actor AI is random, so only the stage is comparable",
		"overlays": "all CanvasLayers hidden for shots; shown (real HUD) for perf",
		"approximations": [],
	}


func _build_world() -> bool:
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2)
	_install_quizzes()
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	var scene := load("res://scenes/game_world.tscn") as PackedScene
	world = scene.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	# Built at the start of the course first (as in the game), so the stands and the conveyor take their full length.
	await frames(90)
	var stage: StageEnvironment = world.get("stage_env")
	check(stage != null and stage.has_ocean_surface() and stage.get_grandstand_count() == 2, "stage, ocean and two stands are built")
	_set_station(0.0)
	await frames(60)
	_hide_overlays(true)
	var weather: Node = stage.get("weather_cycle")
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	check(is_instance_valid(world.get("_goal_stand")), "the goal stand exists")
	check(is_instance_valid(world.get("_goal_line_node")), "the goal gate exists")
	check(is_instance_valid(world.get("camera_controller")), "game camera exists")
	var cc: Node3D = world.get("camera_controller")
	var pose: Dictionary = cc.call("get_gameplay_pose", gs)
	var standard: Dictionary = SHOTS[0]
	report["standard_pose_matches_game"] = (pose.eye as Vector3).is_equal_approx(standard.eye) and (pose.target as Vector3).is_equal_approx(standard.target) \
		and is_equal_approx(float(pose.fov), float(standard.fov))
	report["standard_pose_game"] = {"eye": _v3(pose.eye), "target": _v3(pose.target), "fov": pose.fov}
	check(bool(report["standard_pose_matches_game"]), "the 01 shot equals the game's 2P pose %s" % str(pose))
	report["stage"] = {"floor_center_z": stage.get_floor_center_z(), "floor_length": stage.get_floor_length(),
		"grandstands": stage.get_grandstand_count(), "sharks": stage.get_ocean_sharks().size()}
	report["world_nodes"] = _node_census()
	report["environment"] = _environment_info(stage)
	return true


func _install_quizzes() -> void:
	for index in range(gs.quiz_list.size()):
		var four := gs.num_choices_for_index(index) == 4
		var choices := PackedStringArray(["56", "48", "64", "54"]) if four else PackedStringArray(["56", "54"])
		gs.quiz_list[index] = QuizItem.create("7 × 8 の答えは、次のうちどれ？", choices, 0, "7 × 8 = 56 です。", "OFFLINE")
	gs.current_index = STATION_WALL_INDEX
	gs.current_wall_index = STATION_WALL_INDEX
	gs.load_current_quiz()


## The frozen stage state: belt phase, wall and runners (runners_z is local to the scroll).
func _set_station(runners_z: float, scroll_z: float = STATION_SCROLL_Z) -> void:
	gs.world_scroll_z = scroll_z
	gs.player_x = RUNNER_X[0]
	gs.player2_x = RUNNER_X[1]
	gs.player_z = scroll_z + runners_z
	gs.player2_z = scroll_z + runners_z
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.camera_shake = 0.0


func _teardown_world() -> void:
	_hide_overlays(false)
	if is_instance_valid(world):
		get_tree().current_scene = null
		world.queue_free()
	world = null
	await frames(4)
	QuizManager.game_state = saved_game_state
	if is_instance_valid(helper):
		for provider: Node in helper.providers:
			if is_instance_valid(provider):
				provider.free()
		helper.free()
	helper = null
	gs = null


func _hide_overlays(hide: bool) -> void:
	if hide:
		for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var layer := node as CanvasLayer
			if layer.visible:
				hidden_layers[layer] = true
				layer.visible = false
	else:
		for layer: Variant in hidden_layers.keys():
			if is_instance_valid(layer):
				(layer as CanvasLayer).visible = true
		hidden_layers.clear()


## The stage's Environment and sun as built for this quality (what is on, for the lanes that change the look).
func _environment_info(stage: StageEnvironment) -> Dictionary:
	var result := {}
	var env: Environment = stage.environment_node.environment if stage.environment_node != null else null
	if env != null:
		result["environment"] = {"background_mode": env.background_mode, "tonemap_mode": env.tonemap_mode, "tonemap_white": env.tonemap_white,
			"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled, "sdfgi": env.sdfgi_enabled, "glow": env.glow_enabled,
			"fog": env.fog_enabled, "volumetric_fog": env.volumetric_fog_enabled, "adjustment": env.adjustment_enabled,
			"ambient_source": env.ambient_light_source, "ambient_energy": env.ambient_light_energy, "reflected_source": env.reflected_light_source,
			"sky": env.sky != null and env.sky.sky_material != null}
	var sun: DirectionalLight3D = stage.directional_light
	if sun != null:
		result["sun"] = {"shadow": sun.shadow_enabled, "energy": sun.light_energy, "max_distance": sun.directional_shadow_max_distance,
			"blend_splits": sun.directional_shadow_blend_splits, "mode": sun.directional_shadow_mode, "rotation_degrees": _v3(sun.global_rotation_degrees)}
	return result


## What the world contains (for deciding what a later lane may touch), by mesh instances and lights.
func _node_census() -> Dictionary:
	var census := {"mesh_instances": 0, "multimeshes": 0, "lights": 0, "subviewports": 0, "gpu_particles": 0, "cpu_particles": 0}
	for node: Node in world.find_children("*", "", true, false):
		if node is MeshInstance3D:
			census.mesh_instances += 1
		elif node is MultiMeshInstance3D:
			census.multimeshes += 1
		elif node is Light3D:
			census.lights += 1
		elif node is SubViewport:
			census.subviewports += 1
		elif node is GPUParticles3D:
			census.gpu_particles += 1
		elif node is CPUParticles3D:
			census.cpu_particles += 1
	return census


# ------------------------------------------------------------------ shots

func _shots() -> Array:
	var saved: Array = []
	_hide_overlays(true)
	var base := maxi(SCHEDULE_BASE_FRAME, int(ceil(float(Engine.get_process_frames()) / 60.0)) * 60)
	report["schedule_base_frame"] = base
	report["schedule_base_nominal"] = base == SCHEDULE_BASE_FRAME
	await _until_frame(base)
	var cursor := base
	for shot: Dictionary in SHOTS:
		if not _shot_selected(shot):
			continue
		var slot := int(shot.get("slot", DEFAULT_SLOT_FRAMES))
		_set_station(float(shot.runners_z))
		_aim(shot.eye, shot.target, float(shot.fov))
		var capture_frame := cursor + slot - 1
		await _until_frame(capture_frame)
		await RenderingServer.frame_post_draw
		var path := out + String(shot.id) + ".png"
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(path)
		check(error == OK, "saved " + path)
		var camera: Camera3D = (world.get("camera_controller") as Node3D).get("camera")
		var at_target: bool = camera.global_position.is_equal_approx(shot.eye) and is_equal_approx(camera.fov, float(shot.fov))
		check(at_target, "camera is at the pose for " + String(shot.id))
		saved.append({"id": shot.id, "path": path, "what": shot.what, "eye": _v3(shot.eye), "target": _v3(shot.target), "fov": shot.fov,
			"runners_z": shot.runners_z, "capture_frame": capture_frame, "image_size": [image.get_width(), image.get_height()],
			"camera_at_pose": at_target, "scale_3d": get_viewport().scaling_3d_scale, "draw_calls": _info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"objects": _info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)})
		cursor += slot
	return saved


func _shot_selected(shot: Dictionary) -> bool:
	if only_prefixes.is_empty():
		return true
	for prefix in only_prefixes:
		if String(shot.id).begins_with(prefix):
			return true
	return false


func _aim(eye: Vector3, target: Vector3, fov: float) -> void:
	var direction := (target - eye).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var cc: Node3D = world.get("camera_controller")
	cc.call("set_director_pose", Transform3D(Basis.looking_at(direction, up), eye), fov)


func _until_frame(target: int) -> void:
	while Engine.get_process_frames() < target:
		await get_tree().process_frame


# ------------------------------------------------------------------ performance

func _shot_by_id(id: String) -> Dictionary:
	for shot: Dictionary in SHOTS:
		if shot.id == id:
			return shot
	return {}


## One pass over the views. adaptive=false pins Ultra's supersample at its cap; adaptive=true lets the game's own
## controller follow the GPU (Ultra only) and records the scale it settles on.
func _perf(adaptive: bool) -> Dictionary:
	_hide_overlays(false)
	var result := {"mode": "adaptive" if adaptive else "pinned", "views": {}}
	var root_viewport := get_viewport()
	GraphicsQualityRules.adaptive_budget_override_ms = 0.0 if adaptive else PIN_BUDGET_MS
	var standard := _shot_by_id(PERF_VIEWS[0])
	_set_station(float(standard.runners_z))
	_aim(standard.eye, standard.target, float(standard.fov))
	# Warm up: every view once (pipelines, textures, GPU clocks), not recorded.
	for id: String in PERF_VIEWS:
		var warm := _shot_by_id(id)
		_set_station(float(warm.runners_z))
		_aim(warm.eye, warm.target, float(warm.fov))
		await frames(WARMUP_FRAMES_PER_VIEW)
	_set_station(float(standard.runners_z))
	_aim(standard.eye, standard.target, float(standard.fov))
	if adaptive:
		# The controller works on wall-clock windows (1 s measure, 0.5 s settle, 6 s before climbing back), so settle by time.
		var scale_log: Array = []
		var settle_end := Time.get_ticks_msec() + int(ADAPTIVE_SETTLE_SEC * 1000.0)
		var next_log := Time.get_ticks_msec()
		while Time.get_ticks_msec() < settle_end:
			await get_tree().process_frame
			if Time.get_ticks_msec() >= next_log:
				scale_log.append(snappedf(root_viewport.scaling_3d_scale, 0.001))
				next_log += 1000
		result["scale_log_settle_1s"] = scale_log
	result["scale_3d_start"] = root_viewport.scaling_3d_scale
	for id: String in PERF_VIEWS:
		var shot := _shot_by_id(id)
		_set_station(float(shot.runners_z))
		_aim(shot.eye, shot.target, float(shot.fov))
		await frames(20)
		result.views[id] = await _measure(perf_frames, Callable())
	var standard_shot := _shot_by_id(PERF_VIEWS[0])
	_aim(standard_shot.eye, standard_shot.target, float(standard_shot.fov))
	_set_station(float(standard_shot.runners_z))
	await frames(20)
	var scroll := func(frame: int) -> void:
		var scroll_z := STATION_SCROLL_Z + fposmod(float(frame) * SCROLL_RUN_SPEED / 60.0, SCROLL_RUN_SPAN)
		_set_station(0.0, scroll_z)
	result.views["scroll_run_standard"] = await _measure(perf_frames, scroll)
	_set_station(0.0)
	result["scale_3d_end"] = root_viewport.scaling_3d_scale
	result["vram"] = _vram()
	result["viewport"] = _viewport_info(root_viewport)
	result["summary"] = _perf_summary(result.views)
	return result


func _perf_summary(views: Dictionary) -> Dictionary:
	var worst_gpu_p95 := 0.0
	var worst_view := ""
	var gpu_p50: Array[float] = []
	var gpu_p95: Array[float] = []
	var draws: Array[float] = []
	for id: String in views.keys():
		var entry: Dictionary = views[id]
		gpu_p50.append(float(entry.gpu_p50))
		gpu_p95.append(float(entry.gpu_p95))
		draws.append(float(entry.draw_calls_p50))
		if float(entry.gpu_p95) > worst_gpu_p95:
			worst_gpu_p95 = float(entry.gpu_p95)
			worst_view = id
	return {"gpu_p50_mean_of_views": _mean(gpu_p50), "gpu_p95_mean_of_views": _mean(gpu_p95), "gpu_p95_worst": worst_gpu_p95,
		"gpu_p95_worst_view": worst_view, "draw_calls_p50_mean_of_views": _mean(draws)}


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return snappedf(total / float(values.size()), 0.01)


func _vram() -> Dictionary:
	return {"total_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"texture_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.1),
		"buffer_mb": snappedf(float(_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0, 0.1)}


func _sub_viewport_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		rids.append((node as SubViewport).get_viewport_rid())
	return rids


## `count` frames of CPU interval, GPU render time (root viewport alone and with every SubViewport), draws and
## primitives. step(frame) runs before each frame.
func _measure(count: int, step: Callable, focus: RID = RID()) -> Dictionary:
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var gpu_all: Array[float] = []
	var gpu_focus: Array[float] = []
	var draws: Array[int] = []
	var primitives: Array[int] = []
	var objects: Array[int] = []
	var scales: Array[float] = []
	var last := Time.get_ticks_usec()
	var viewport := get_viewport()
	var rid := viewport.get_viewport_rid()
	var subs := _sub_viewport_rids()
	for sub in subs:
		RenderingServer.viewport_set_measure_render_time(sub, true)
	for frame in range(count):
		if step.is_valid():
			step.call(frame)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		cpu.append(float(now - last) / 1000.0)
		last = now
		var root_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var all_ms := root_ms
		for sub in subs:
			all_ms += RenderingServer.viewport_get_measured_render_time_gpu(sub)
		if root_ms > 0.0:
			gpu.append(root_ms)
			gpu_all.append(all_ms)
		if focus.is_valid():
			var focus_ms := RenderingServer.viewport_get_measured_render_time_gpu(focus)
			if focus_ms > 0.0:
				gpu_focus.append(focus_ms)
		draws.append(_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objects.append(_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		scales.append(viewport.scaling_3d_scale)
	# The first frame's interval includes the camera cut.
	cpu.remove_at(0)
	var focus_stats := {}
	if focus.is_valid():
		focus_stats = {"gpu_focus_p50": _pct(gpu_focus, 0.5), "gpu_focus_p95": _pct(gpu_focus, 0.95), "gpu_focus_p99": _pct(gpu_focus, 0.99)}
	var stats := _measure_stats(cpu, gpu, gpu_all, draws, primitives, objects, scales, subs.size())
	stats.merge(focus_stats)
	return stats


func _measure_stats(cpu: Array[float], gpu: Array[float], gpu_all: Array[float], draws: Array[int], primitives: Array[int],
		objects: Array[int], scales: Array[float], sub_count: int) -> Dictionary:
	return {"frames": cpu.size(), "gpu_samples": gpu.size(),
		"cpu_p50": _pct(cpu, 0.5), "cpu_p95": _pct(cpu, 0.95), "cpu_p99": _pct(cpu, 0.99), "cpu_max": _pct(cpu, 1.0),
		"gpu_p50": _pct(gpu, 0.5), "gpu_p95": _pct(gpu, 0.95), "gpu_p99": _pct(gpu, 0.99), "gpu_max": _pct(gpu, 1.0),
		"gpu_all_viewports_p50": _pct(gpu_all, 0.5), "gpu_all_viewports_p95": _pct(gpu_all, 0.95), "sub_viewports": sub_count,
		"draw_calls_p50": int(_pct(draws, 0.5)), "draw_calls_max": int(_pct(draws, 1.0)),
		"primitives_p50": int(_pct(primitives, 0.5)), "primitives_max": int(_pct(primitives, 1.0)),
		"objects_p50": int(_pct(objects, 0.5)),
		"scale_3d_min": snappedf(_pct(scales, 0.0), 0.001), "scale_3d_max": snappedf(_pct(scales, 1.0), 0.001)}


# ------------------------------------------------------------------ menu background

func _menu(shoot: bool, measure: bool) -> Dictionary:
	var result := {"approximation": "MenuWallBackgroundPreview SubViewport (3D only) of res://ui/main_menu.tscn"}
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	QuizManager.set_meta("saw_dock_menu_seen", true)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var preview: Node = null
	for _frame in range(1800):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.get("_menu_wall_preview") != null:
			preview = scene.get("_menu_wall_preview")
			if preview.has_method("get_camera") and preview.call("get_camera") != null and not SceneTransition.is_transitioning():
				break
	if preview == null or not preview.has_method("get_shared_viewport"):
		result["skipped"] = "menu preview did not come up"
		check(false, "menu preview did not come up")
		return result
	# Fixed frame position, so the sea and clouds repeat between runs.
	var base := int(ceil(float(Engine.get_process_frames()) / 60.0)) * 60 + 240
	await _until_frame(base)
	var viewport := preview.call("get_shared_viewport") as SubViewport
	result["sub_viewport_size"] = [viewport.size.x, viewport.size.y]
	result["viewport"] = _viewport_info(viewport)
	if shoot:
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := out + "08_menu_background.png"
		check(image.save_png(path) == OK, "saved " + path)
		result["shot"] = {"id": "08_menu_background", "path": path, "capture_frame": Engine.get_process_frames(),
			"image_size": [image.get_width(), image.get_height()]}
	if measure:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		await frames(30)
		result["perf"] = await _measure(perf_frames, Callable(), viewport.get_viewport_rid())
		result["perf_note"] = "gpu_focus_* is the menu's 3D SubViewport; gpu_* is the root window (2D composite only); gpu_all_viewports_* is every viewport"
	return result


# ------------------------------------------------------------------ compare

func _compare() -> void:
	var result := {"tag_a": tag_a, "tag_b": tag_b, "quality": quality, "images": {}}
	var dir_a := OUT_ROOT + tag_a + "/" + quality + "/"
	var dir_b := OUT_ROOT + tag_b + "/" + quality + "/"
	var names := DirAccess.get_files_at(ProjectSettings.globalize_path(dir_a))
	var worst_mean := 0.0
	for file_name: String in names:
		if not file_name.ends_with(".png"):
			continue
		var image_a := Image.load_from_file(ProjectSettings.globalize_path(dir_a + file_name))
		var image_b := Image.load_from_file(ProjectSettings.globalize_path(dir_b + file_name))
		var diff := _diff(image_a, image_b)
		result.images[file_name] = diff
		worst_mean = maxf(worst_mean, float(diff.mean))
	result["worst_mean_delta"] = worst_mean
	var path := OUT_ROOT + "compare_%s_vs_%s_%s.json" % [tag_a, tag_b, quality]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("GROUND_LOOK_COMPARE " + JSON.stringify(result))
	get_tree().quit(0)


## Per-channel max delta over every 2nd pixel: mean delta (0..1), fraction of pixels that changed by more than 2.5/255, max.
func _diff(a: Image, b: Image) -> Dictionary:
	if a == null or b == null or a.get_size() != b.get_size():
		return {"mean": 1.0, "changed_fraction": 1.0, "max": 1.0, "note": "missing or different size"}
	var changed := 0
	var max_delta := 0.0
	var total := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			total += delta
			samples += 1
			max_delta = maxf(max_delta, delta)
			if delta > 2.5 / 255.0:
				changed += 1
	return {"mean": snappedf(total / maxf(1.0, float(samples)), 0.00001), "changed_fraction": snappedf(float(changed) / maxf(1.0, float(samples)), 0.0001),
		"max": snappedf(max_delta, 0.0001)}


# ------------------------------------------------------------------ helpers

static func _pct(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return snappedf(float(sorted[index]), 0.01)


static func _info(kind: RenderingServer.RenderingInfo) -> int:
	return RenderingServer.get_rendering_info(kind)


static func _v3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]


func _viewport_info(viewport: Viewport) -> Dictionary:
	return {"size": [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y], "scaling_3d_mode": viewport.scaling_3d_mode,
		"scale_3d": viewport.scaling_3d_scale, "msaa_3d": viewport.msaa_3d, "screen_space_aa": viewport.screen_space_aa, "taa": viewport.use_taa,
		"mesh_lod_threshold": viewport.mesh_lod_threshold, "anisotropic": viewport.anisotropic_filtering_level,
		"mipmap_bias": viewport.texture_mipmap_bias, "adaptive_scale": GraphicsQualityRules.adaptive_scale(viewport)}


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


# ------------------------------------------------------------------ report

func _finish() -> void:
	var digest_after := _settings_digest()
	report["user_settings_sha256_unchanged"] = digest_after == settings_digest_before
	check(digest_after == settings_digest_before, "user://settings.json unchanged")
	report["passed"] = failures.is_empty()
	report["checks"] = checks
	report["failures"] = failures
	report["quality"] = quality
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["gpu"] = {"name": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(), "type": RenderingServer.get_video_adapter_type()}
	report["engine"] = Engine.get_version_info().get("string", "")
	GraphicsQualityRules.adaptive_budget_override_ms = 0.0
	report["window"] = {"root_size": [get_tree().root.size.x, get_tree().root.size.y], "display_refresh": DisplayServer.screen_get_refresh_rate(),
		"adaptive_budget_ms_natural": GraphicsQualityRules.adaptive_frame_budget_ms()}
	report["unix_time"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	var summary := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "quality": quality, "tag": tag, "out": out,
		"load_ms": report.get("load_ms", -1)}
	for key: String in ["perf", "perf_adaptive"]:
		if report.has(key):
			summary[key] = (report[key] as Dictionary).get("summary", {})
	if report.has("shots"):
		summary["shots"] = (report.shots as Array).size()
	print("GROUND_LOOK " + JSON.stringify(summary))
	GraphicsQualityRules.adaptive_budget_override_ms = 0.0
	QuizManager.player_analytics = saved_analytics
	await frames(2)
	get_tree().quit(0 if failures.is_empty() else 1)
