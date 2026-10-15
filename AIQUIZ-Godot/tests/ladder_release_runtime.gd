extends Node

## Measures the real Start route from the last rope-ladder hang frames into
## the Falling Idle flight. Reports the largest per-frame joint rotation so a
## pose pop at the hand release is visible as a number, plus close-up frames.
const OUT := "res://artifacts/ladder_release/"
const KEYS := [
	"pelvis", "spine", "neck", "head_pivot",
	"l_shoulder", "r_shoulder", "l_elbow", "r_elbow",
	"l_wrist", "r_wrist", "l_hip", "r_hip", "l_knee", "r_knee",
]
const SHOT_FRAMES := [0, 2, 4, 6, 9, 12, 16, 22]
## The old 0.15 s pose swap measured ~1800 deg/s on the shoulders.
const MAX_RELEASE_DEG_PER_SECOND := 800.0
var players := 2
var fps := 60
var label := ""
var tracks: Dictionary = {}
var closeups: Dictionary = {}
var pictures: Dictionary = {}
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="): players = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--fps="): fps = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	label = "%s_p%d_%dfps" % [label if not label.is_empty() else "run", players, fps]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + label))
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.5).timeout
	while menu.config_conveyor != null and menu.config_conveyor.is_moving():
		await get_tree().process_frame
	menu.call("_on_start_pressed")
	var deadline := Time.get_ticks_msec() + 65000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var world := get_tree().current_scene
		if world == null or world.scene_file_path != "res://scenes/game_world.tscn":
			continue
		var director := world.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
		if director == null:
			continue
		var pc: PlayerController = director._player_controller
		if closeups.is_empty():
			for n in range(1, players + 1):
				var viewport := SubViewport.new()
				viewport.size = Vector2i(560, 560)
				viewport.world_3d = world.get_world_3d()
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var camera := Camera3D.new()
				camera.fov = 40.0
				viewport.add_child(camera)
				camera.make_current()
				closeups[n] = {"viewport": viewport, "camera": camera}
		var done := 0
		for n in range(1, players + 1):
			if sample(pc, n):
				done += 1
		if done == players:
			break
	report()


## Returns true once enough post-release frames were recorded.
func sample(pc: PlayerController, n: int) -> bool:
	if not tracks.has(n):
		tracks[n] = {"frames": [], "release": -1, "prev": {}}
	var track: Dictionary = tracks[n]
	var hanging: bool = pc._intro_ladder_grabs.has(n)
	var jumping: bool = pc._intro_jumps.has(n)
	if not hanging and not jumping:
		return int(track.release) >= 0
	var parts: Dictionary = pc.p1_parts if n == 1 else pc.p2_parts
	var pose := {}
	for key: String in KEYS:
		var node := parts.get(key) as Node3D
		if node != null:
			pose[key] = node.global_basis.get_rotation_quaternion() if key == "pelvis" else node.quaternion
	var frames: Array = track.frames
	if jumping and int(track.release) < 0:
		track.release = frames.size()
	var index := frames.size()
	var rel := index - int(track.release) if int(track.release) >= 0 else -1
	var worst := 0.0
	var worst_key := ""
	var prev: Dictionary = track.prev
	for key: String in pose:
		if prev.has(key):
			var angle := rad_to_deg((pose[key] as Quaternion).angle_to(prev[key]))
			if angle > worst:
				worst = angle
				worst_key = key
	track.prev = pose
	var pelvis := parts.get("pelvis") as Node3D
	var elapsed := float(pc._intro_jumps.get(n, {}).get("elapsed", 0.0))
	var from_deg := -1.0
	var jump_state: Dictionary = pc._intro_jumps.get(n, {})
	var release_pose: Dictionary = jump_state.get("release_pose", {})
	if release_pose.has("l_shoulder") and pose.has("l_shoulder"):
		from_deg = rad_to_deg((pose["l_shoulder"] as Quaternion).angle_to((release_pose["l_shoulder"] as Transform3D).basis.get_rotation_quaternion()))
	frames.append({"hang": hanging, "elapsed": elapsed, "max_deg": worst, "joint": worst_key, "from_deg": from_deg})
	if closeups.has(n) and pelvis != null:
		var focus := pelvis.global_position + Vector3.UP * 0.2
		var camera: Camera3D = closeups[n].camera
		camera.global_position = focus + Vector3(3.2, 0.6, -3.6)
		camera.look_at(focus)
		if int(track.release) >= 0 and rel in SHOT_FRAMES:
			shot(n, "f%+03d" % rel)
	if int(track.release) >= 0 and rel >= 40:
		return true
	return false


func shot(n: int, key: String) -> void:
	var name := "p%d_%s" % [n, key]
	if pictures.has(name):
		return
	var path := OUT + label + "/" + name + ".png"
	closeups[n].viewport.get_texture().get_image().save_png(path)
	pictures[name] = path


func report() -> void:
	var summary := {}
	for n in tracks:
		var track: Dictionary = tracks[n]
		var frames: Array = track.frames
		var release := int(track.release)
		var hang_peak := 0.0
		var transition_peak := 0.0
		var transition_joint := ""
		var window := []
		var peak_rate := 0.0
		for i in range(frames.size()):
			var f: Dictionary = frames[i]
			var rel := i - release
			if release >= 0 and rel >= -12 and rel < -1:
				hang_peak = maxf(hang_peak, f.max_deg)
			if release >= 0 and rel >= 0 and rel <= 30:
				if f.max_deg > transition_peak:
					transition_peak = f.max_deg
					transition_joint = f.joint
				if rel >= 1:
					# Frame times are uneven under load; compare angular speed, not per-frame angle.
					var dt := float(f.elapsed) - float(frames[i - 1].elapsed)
					if dt > 0.0001:
						peak_rate = maxf(peak_rate, float(f.max_deg) / dt)
				window.append("%d:%.1f(%s) t=%.3f from=%.1f" % [rel, f.max_deg, f.joint, f.elapsed, f.from_deg])
		summary[str(n)] = {
			"release_frame": release,
			"hang_peak_deg_per_frame": hang_peak,
			"transition_peak_deg_per_frame": transition_peak,
			"transition_peak_joint": transition_joint,
			"transition_peak_deg_per_second": peak_rate,
			"window": window,
		}
		if release < 0:
			failures.append("P%s never released the rope ladder" % n)
		elif peak_rate > MAX_RELEASE_DEG_PER_SECOND:
			failures.append("P%s release pops at %.0f deg/s" % [n, peak_rate])
	if tracks.size() < players:
		failures.append("not every player reached the rope ladder")
	var result := {"label": label, "passed": failures.is_empty(), "failures": failures, "summary": summary, "pictures": pictures}
	FileAccess.open(OUT + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("LADDER_RELEASE ", JSON.stringify({"passed": failures.is_empty(), "failures": failures, "summary": summary}))
	get_tree().quit(0 if failures.is_empty() else 1)
