extends Node

## ゴーストシャークの搭乗（脱落 → 魂 → サメに乗る → ビーム → 登場 → 照準）を、本物の 2P の GameWorld で連番に撮る。
## 画面全体（小窓を含む）と、小窓のカメラを大きく撮った絵（wipe_*.jpg）を every フレームごとに保存する。
## 引数（"--" の後ろ）:
##   tag=<名前>          出力先 artifacts/ghost_mount_capture/<tag>/
##   quality=<画質>      low|balanced|high|ultra（既定 high）
##   every=<N>           N フレームごとに保存（既定 3）
##   rider=<1|2>         脱落する人（既定 1）
##   death=wall|ocean    壁で脱落 / 横から海へ落ちてサメに噛まれる（既定 wall）
##   until=aim|dash      照準まで / 1 回突進して戻るまで（既定 aim）
##   wipe_scale=<N>      小窓の大きい版の倍率（既定 3 = 960x720）
##   dead_x=inner        壁で脱落する人を、生き残る人と同じ側の真ん中寄り（ドアの間の壁）に置く（甲板の上の脱落で、
##                       脱落した位置の左右とサメの待つ側が食い違う並び）
const OUT_ROOT := "res://artifacts/ghost_mount_capture/"
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")

var gs: QuizGameState
var world: Node3D
var ghost: GhostSharkRideController
var helper: Node
var out := ""
var tag := "capture"
var quality := GraphicsQualityRules.HIGH
var every := 3
var rider := 1
var death_kind := "wall"
var until := "aim"
var wipe_scale := 3
var dead_inner := false
var frame := 0
var phases: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var _last_phase := -1
var _recording := false
var _record_start := 0
var _big_viewport: SubViewport
var _big_camera: Camera3D
var _wipe_camera: Camera3D
var _wipe: Control


func _ready() -> void:
	process_priority = 1000
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
		elif arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg.begins_with("every="):
			every = maxi(1, int(arg.trim_prefix("every=")))
		elif arg.begins_with("rider="):
			rider = clampi(int(arg.trim_prefix("rider=")), 1, 2)
		elif arg.begins_with("death="):
			death_kind = arg.trim_prefix("death=")
		elif arg.begins_with("until="):
			until = arg.trim_prefix("until=")
		elif arg.begins_with("wipe_scale="):
			wipe_scale = clampi(int(arg.trim_prefix("wipe_scale=")), 1, 6)
		elif arg == "dead_x=inner":
			dead_inner = true
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out + f))
	get_tree().root.size = Vector2i(1920, 1080)
	var bgm := AudioServer.get_bus_index("BGM")
	if bgm >= 0:
		AudioServer.set_bus_mute(bgm, true)
	GameManager.graphics_quality = quality
	GraphicsQualityRules.adaptive_budget_override_ms = 100000.0
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	seed(7)
	AudioManager.sfx_played.connect(_on_sfx)

	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.get_node("Player").prepare_for_loading(gs)
	world.get_node("Player").reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	_wipe = world.get_node_or_null("DeathWipeLayer/DeathWipe") as Control
	if _wipe != null:
		_wipe_camera = _wipe.get_node_or_null("SubViewport/WipeCamera") as Camera3D
	_build_big_wipe_view()
	await _frames(90)

	_recording = true
	_record_start = frame
	if death_kind == "ocean":
		await _ocean_death()
	else:
		gs._set_player_hp(rider, 1)
		if rider == 1:
			gs.player_x = helper.door(gs, false)
			gs.player2_x = helper.door(gs, true)
		else:
			gs.player2_x = helper.door(gs, false)
			gs.player_x = helper.door(gs, true)
		if dead_inner:
			var survivor_x: float = gs.player2_x if rider == 1 else gs.player_x
			if rider == 1:
				gs.player_x = signf(survivor_x) * 0.4
			else:
				gs.player2_x = signf(survivor_x) * 0.4
		gs.resolve_collision(true, true)
	var reached := await _wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 1800)
	if reached and until in ["dash", "miss"]:
		await _frames(30)
		# miss は生き残りから外して突進し、戻りのポータルまで撮る（命中すると生き残りが海へ飛ばされて終わる）。
		ghost.set("_aim_offset", Vector2(5.0, 7.0) if until == "miss" else Vector2.ZERO)
		_key(KEY_SPACE if rider == 1 else KEY_CTRL, true)
		await _frames(25)
		_key(KEY_SPACE if rider == 1 else KEY_CTRL, false)
		await _wait_until(func(): return ghost.phase == ghost.Phase.COOLDOWN, 400)
		await _wait_until(func(): return ghost.phase == ghost.Phase.AIMING, 900)
	else:
		await _frames(45)
	_recording = false
	var report := {
		"reached_aiming": reached,
		"frames": frame - _record_start,
		"every": every,
		"phases": phases,
		"cues": cues,
		"quality": quality,
	}
	FileAccess.open(out + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("GHOST_MOUNT_CAPTURE " + JSON.stringify({"reached": reached, "frames": frame - _record_start, "out": ProjectSettings.globalize_path(out)}))
	get_tree().quit(0 if reached else 1)


func _ocean_death() -> void:
	## 横から海へ歩いて落ちる（サメに噛まれて脱落する）。相手を押し出さないよう、相手と反対の側へ歩く
	## （P1 は x = −2 から −x へ D、P2 は x = 2 から +x へ ←）。
	var key := KEY_D if rider == 1 else KEY_LEFT
	_key(key, true)
	await _wait_until(func(): return not (gs.p1_alive if rider == 1 else gs.p2_alive) or gs.is_player_waiting_for_shark(rider), 600)
	_key(key, false)


func _build_big_wipe_view() -> void:
	if _wipe_camera == null:
		return
	_big_viewport = SubViewport.new()
	_big_viewport.name = "CaptureBigWipe"
	_big_viewport.size = Vector2i(320 * wipe_scale, 240 * wipe_scale)
	_big_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_big_viewport.world_3d = get_tree().root.world_3d
	_big_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_big_viewport)
	_big_camera = Camera3D.new()
	_big_viewport.add_child(_big_camera)
	_big_camera.current = true


func _process(_dt: float) -> void:
	if not _recording:
		return
	frame += 1
	if ghost != null and ghost.phase != _last_phase:
		_last_phase = ghost.phase
		var entry := {"phase": ghost.Phase.keys()[ghost.phase], "frame": frame - _record_start}
		var debug: Dictionary = ghost.get_debug_state()
		var rendezvous: Vector3 = debug.get("rendezvous_position", Vector3.ZERO)
		entry["rendezvous"] = str(rendezvous)
		var main_camera := world.get_node_or_null("CameraController/Camera3D") as Camera3D
		if main_camera != null:
			var probe := Vector3(rendezvous.x, StageConstants.FLOOR_TOP_Y + 4.0, rendezvous.z)
			entry["beam_screen"] = str(main_camera.unproject_position(probe)) if not main_camera.is_position_behind(probe) else "behind"
			entry["main_camera"] = str(main_camera.global_position)
		phases.append(entry)
	if _big_camera != null and _wipe_camera != null:
		_big_camera.global_transform = _wipe_camera.global_transform
		_big_camera.fov = _wipe_camera.fov
		_big_camera.near = _wipe_camera.near
		_big_camera.far = _wipe_camera.far
		_big_camera.cull_mask = _wipe_camera.cull_mask
		_big_camera.environment = _wipe_camera.environment
	var rel := frame - _record_start
	if rel % every == 0:
		_save(rel)


func _save(rel: int) -> void:
	await RenderingServer.frame_post_draw
	var phase_name := str(ghost.Phase.keys()[ghost.phase]) if ghost != null else "-"
	var main_image := get_viewport().get_texture().get_image()
	if main_image != null:
		main_image.save_jpg(out + "main_%04d.jpg" % rel, 0.88)
	var wipe_visible := _wipe != null and _wipe.visible
	if _big_viewport != null and wipe_visible:
		var wipe_image := _big_viewport.get_texture().get_image()
		if wipe_image != null:
			wipe_image.save_jpg(out + "wipe_%04d.jpg" % rel, 0.9)
	FileAccess.open(out + "frame_%04d.txt" % rel, FileAccess.WRITE).store_string(phase_name)


func _on_sfx(cue: StringName) -> void:
	if _recording:
		cues.append({"cue": str(cue), "frame": frame - _record_start})


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
