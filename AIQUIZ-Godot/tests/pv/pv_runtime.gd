extends Node

## PV capture runner: drives one shot script (tests/pv/shots/<shot>.gd) through the real game
## and saves its frames. One shot per process (tools/pv/capture.ps1 builds the command):
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/pv/pv_bootstrap.gd
##       --resolution 1920x1080 --position 0,0 --fixed-fps 60 --write-movie <out>/movie.avi
##       -- shot=<id> [take=<n>] [seed=<n>] [quality=high] [out=<dir>]
##
## Frames: while a shot records, the root viewport (1920x1080; Movie Maker itself only writes
## 1280x720) is saved as JPEG for every drawn frame, named by Engine.get_frames_drawn(). The
## AVI from --write-movie runs on the same frame clock and carries the game audio; one white
## frame (sync_frame in marks.json) lines the two up. marks.json lists the recorded segments.
## Wall-clock waits are avoided: everything waits in frames, so slow capture never changes the
## timing. Files under user:// are snapshotted first and restored at the end (settings, audio,
## ratings, caches), and ratings never reach Firebase.

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const Providers := preload("res://tests/pv/pv_providers.gd")
const JPEG_QUALITY := 0.95
const MAX_PENDING_SAVES := 24
const CAPTURE_SFX := 0.8
const PLAYER_KEYS := {1: [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE], 2: [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_CTRL]}

var shot := ""
var take := 1
var seed_value := 1
var quality := "high"
var out_dir := ""
var args: Dictionary = {}
var recording := ""
var marks: Array[Dictionary] = []
var notes: Dictionary = {}
var sync_frame := -1
var saved_frames := 0
var _pending: Array[int] = []
var _user_snapshot: Dictionary = {}
var _hidden_layers: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func run() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_snapshot_user_files()
	_prepare_engine()
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	await _sync_flash()
	var ok := false
	var script := load("res://tests/pv/shots/%s.gd" % shot) as Script
	if script == null or not script.can_instantiate():
		push_error("PV: unknown shot " + shot)
	else:
		var runner = script.new()
		await runner.run(self)
		ok = true
	stop_record()
	release_keys()
	_drain_saves()
	_write_marks(ok)
	_restore_user_files()
	print("PV_DONE ", JSON.stringify({"shot": shot, "take": take, "ok": ok, "frames": saved_frames, "segments": marks.size(), "out": out_dir}))
	get_tree().quit(0 if ok else 1)


# ----------------------------------------------------------------------------- setup

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	shot = str(args.get("shot", ""))
	take = int(args.get("take", "1"))
	seed_value = int(args.get("seed", str(take)))
	quality = GraphicsQualityRules.normalize(str(args.get("quality", "high")))
	out_dir = str(args.get("out", "G:/aiquiz_pv_raw/%s_t%d" % [shot, take])).replace("\\", "/")


func _prepare_engine() -> void:
	seed(seed_value)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Plain assignments stay in memory; the settings file is never written by this run.
	GameManager.settings_path = "user://pv_settings.json"
	GameManager.graphics_quality = quality
	GraphicsQualityRules.adaptive_budget_override_ms = 100000.0
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	AudioManager.set_sfx_volume(CAPTURE_SFX, false)
	AudioManager.set_bgm_volume(0.0, false)
	QuizManager.player_analytics = null
	var ratings := Providers.RatingsStub.new()
	ratings.name = "PvRatingsStub"
	add_child(ratings)
	QuizManager.firebase_ratings = ratings


## A single white frame on top of everything: its frames_drawn is the sync point between the
## saved JPEGs and the Movie Maker AVI (and its audio).
func _sync_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var white := ColorRect.new()
	white.color = Color.WHITE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	add_child(layer)
	await RenderingServer.frame_post_draw
	sync_frame = Engine.get_frames_drawn()
	layer.queue_free()
	await frames(2)


# ----------------------------------------------------------------------------- user files

func _snapshot_user_files() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file: String in dir.get_files():
		var path := "user://" + file
		var handle := FileAccess.open(path, FileAccess.READ)
		if handle != null and handle.get_length() < 16 * 1024 * 1024:
			_user_snapshot[path] = handle.get_buffer(handle.get_length())
	# A copy on disk too, so a run that is killed can still be put back (tools/pv/restore_user.ps1).
	DirAccess.make_dir_recursive_absolute(out_dir + "/user_backup")
	for path: String in _user_snapshot:
		var copy := FileAccess.open(out_dir + "/user_backup/" + path.trim_prefix("user://"), FileAccess.WRITE)
		if copy != null:
			copy.store_buffer(_user_snapshot[path])
			copy.close()


func _restore_user_files() -> void:
	var restored: Array[String] = []
	var removed: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir != null:
		for file: String in dir.get_files():
			var path := "user://" + file
			if not _user_snapshot.has(path) and not file.ends_with(".log"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				removed.append(file)
	for path: String in _user_snapshot:
		var before: PackedByteArray = _user_snapshot[path]
		var now := FileAccess.get_file_as_bytes(path)
		if now != before:
			var handle := FileAccess.open(path, FileAccess.WRITE)
			if handle != null:
				handle.store_buffer(before)
				handle.close()
				restored.append(path.trim_prefix("user://"))
	notes["user_files_restored"] = restored
	notes["user_files_removed"] = removed


# ----------------------------------------------------------------------------- recording

func record(tag: String) -> void:
	stop_record()
	recording = tag
	marks.append({"tag": tag, "first": -1, "last": -1})


func stop_record() -> void:
	recording = ""


func _on_post_draw() -> void:
	_reap_saves(false)
	if recording.is_empty() or marks.is_empty():
		return
	var index := Engine.get_frames_drawn()
	var image := get_viewport().get_texture().get_image()
	var path := "%s/frames/%08d.jpg" % [out_dir, index]
	_pending.append(WorkerThreadPool.add_task(func() -> void: image.save_jpg(path, JPEG_QUALITY)))
	var mark: Dictionary = marks.back()
	if int(mark.first) < 0:
		mark.first = index
	mark.last = index
	saved_frames += 1
	if _pending.size() > MAX_PENDING_SAVES:
		_reap_saves(true)


func _reap_saves(block_oldest: bool) -> void:
	while not _pending.is_empty() and WorkerThreadPool.is_task_completed(_pending[0]):
		WorkerThreadPool.wait_for_task_completion(_pending.pop_front())
	if block_oldest and not _pending.is_empty():
		WorkerThreadPool.wait_for_task_completion(_pending.pop_front())


func _drain_saves() -> void:
	while not _pending.is_empty():
		WorkerThreadPool.wait_for_task_completion(_pending.pop_front())


func note(key: String, value: Variant) -> void:
	notes[key] = value


func _write_marks(ok: bool) -> void:
	var data := {"shot": shot, "take": take, "seed": seed_value, "quality": quality, "ok": ok,
		"sync_frame": sync_frame, "fps": 60, "size": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()],
		"segments": marks, "notes": notes}
	var handle := FileAccess.open(out_dir + "/marks.json", FileAccess.WRITE)
	handle.store_string(JSON.stringify(data, "  "))
	handle.close()


# ----------------------------------------------------------------------------- time

func frames(count: int) -> void:
	for i in range(maxi(0, count)):
		await get_tree().process_frame


func seconds(duration: float) -> void:
	await frames(int(round(duration * 60.0)))


## Waits (in frames) until condition returns true; false when max_frames ran out.
func until(condition: Callable, max_frames: int = 3600) -> bool:
	for i in range(max_frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


# ----------------------------------------------------------------------------- input

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = KEY_LOCATION_RIGHT if code == KEY_CTRL else KEY_LOCATION_UNSPECIFIED
	event.pressed = pressed
	Input.parse_input_event(event)


func tap(code: Key, hold_frames: int = 3) -> void:
	key(code, true)
	await frames(hold_frames)
	key(code, false)


func release_keys() -> void:
	for player: int in PLAYER_KEYS:
		for code: Key in PLAYER_KEYS[player]:
			key(code, false)
	key(KEY_ENTER, false)


## One frame of steering: holds the key that moves the player toward x (A / LEFT move +x),
## releases both within tolerance. Returns true when there.
func steer(player: int, x: float, tolerance: float = 0.12) -> bool:
	var gs := QuizManager.game_state
	var now := gs.player_x if player == 1 else gs.player2_x
	var plus: Key = PLAYER_KEYS[player][0]
	var minus: Key = PLAYER_KEYS[player][1]
	if absf(x - now) <= tolerance:
		key(plus, false)
		key(minus, false)
		return true
	key(plus, x > now)
	key(minus, x < now)
	return false


func jump(player: int) -> void:
	await tap(PLAYER_KEYS[player][4], 4)


## X of the door holding the answer `index` on the current wall (tests/hp_unit.gd door()).
func door_x(index: int) -> float:
	var gs := QuizManager.game_state
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[index]
	return gs.tuning.left_door_x if index == 0 else gs.tuning.right_door_x


func correct_door_x() -> float:
	return door_x(QuizManager.game_state.current_quiz.a)


func wrong_door_x() -> float:
	var gs := QuizManager.game_state
	return door_x((gs.current_quiz.a + 1) % gs.num_choices)


# ----------------------------------------------------------------------------- scene helpers

func world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.name == "GameWorld" else null


func menu() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.name == "MainMenu" else null


## Cinematic camera in the game world for a moment of play: the director pose holds the
## camera (GameWorld drops a tutorial override every frame outside tutorials).
## `release_camera()` gives the gameplay camera back without clear_director_pose(), which
## would latch the result camera.
func aim(eye: Vector3, target: Vector3, fov: float = 50.0) -> void:
	pose(eye, target, fov)


func release_camera() -> void:
	var w = world()
	if w != null:
		w.camera_controller._director_pose_active = false


## Fixed camera through the world's director pose (overrides everything; for static shots).
func pose(eye: Vector3, target: Vector3, fov: float = 50.0) -> void:
	var w = world()
	if w == null:
		return
	var direction := (target - eye).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	w.camera_controller.set_director_pose(Transform3D(Basis.looking_at(direction, up), eye), fov)


## The real GameWorld on a fixture state (tests/hp_unit.gd fixture): the set's questions,
## PLAYING at wall 0, no helicopter arrival. Replaces any world already loaded.
func build_world(players: int, set_name: String) -> Node:
	var old := world()
	if old != null:
		get_tree().current_scene = null
		old.queue_free()
		await frames(4)
	var helper: Node = load("res://tests/hp_unit.gd").new()
	var gs: QuizGameState = helper.fixture(players, Constants.MODE_TEN)
	helper.free()
	var data := load_quizzes(set_name)
	gs.subject = data.subject
	gs.grade = data.grade
	gs.difficulty = data.difficulty
	gs.quiz_list.clear()
	for item: QuizItem in data.items:
		gs.quiz_list.append(item)
	while gs.quiz_list.size() < 10:
		gs.quiz_list.append(data.items[gs.quiz_list.size() % data.items.size()])
	gs.current_index = 0
	gs.current_wall_index = 0
	gs.load_current_quiz()
	gs.sudden_death_enabled = false
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	var scene: Node = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	(scene.get_node("Player") as PlayerController).prepare_for_loading(gs)
	await frames(90)
	scene._clear_preview_walls()
	return scene


func hide_overlays(hide: bool) -> void:
	if hide:
		for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var layer := node as CanvasLayer
			if layer.visible and layer.layer < 100:
				_hidden_layers[layer] = true
				layer.visible = false
	else:
		for layer: Variant in _hidden_layers.keys():
			if is_instance_valid(layer):
				(layer as CanvasLayer).visible = true
		_hidden_layers.clear()


## Remote announcements (Firebase live config) never appear in the footage, and the game sound
## stays audible: the menu and pause sliders push the player's saved volumes back on load.
func _process(_delta: float) -> void:
	var gs := QuizManager.game_state
	if gs != null and (not is_equal_approx(gs.sfx_volume, CAPTURE_SFX) or not is_equal_approx(gs.bgm_volume, 0.0)):
		gs.sfx_volume = CAPTURE_SFX
		gs.bgm_volume = 0.0
	if not is_equal_approx(AudioManager.sfx_volume, CAPTURE_SFX) or not is_equal_approx(AudioManager.bgm_volume, 0.0):
		AudioManager.set_sfx_volume(CAPTURE_SFX, false)
		AudioManager.set_bgm_volume(0.0, false)
	var m := menu()
	if m != null:
		var label := m.find_child("AnnouncementLabel", true, false) as CanvasItem
		if label != null and label.visible:
			label.visible = false


func load_quizzes(set_name: String) -> Dictionary:
	return Providers.load_set(set_name)


func generating_provider(set_name: String) -> QuizProvider:
	var data := load_quizzes(set_name)
	var provider := Providers.GeneratingProvider.new()
	provider.items = data.items
	add_child(provider)
	return provider
