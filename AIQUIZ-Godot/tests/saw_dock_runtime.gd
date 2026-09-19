extends Node

## Attach explicitly to an existing runtime. No production autoload/test hooks.
var mode := "menu"
var evidence_root := "res://artifacts/saw_vessel/revision2/"
var out := "res://artifacts/saw_vessel/revision2/menu/"
var time := 0.0
var frames: Array[Dictionary] = []
var failures: Array[String] = []
var started := false
var busy := false
var last_capture := -1.0
var ready_at := -1.0
var landed_at := -1.0
var spin_at := -1.0
var first_pose := Quaternion.IDENTITY
var old_max_fps := 0
var contacts: Array = []

func _ready() -> void:
	process_priority = 100
	old_max_fps = Engine.max_fps
	Engine.max_fps = 60
	out = evidence_root + mode + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

func _process(dt: float) -> void:
	var world := get_tree().current_scene
	if world == null: return
	var saw: SawChaseController
	var landed := true
	if mode == "menu":
		saw = get_tree().root.find_child("MenuSawCarriage", true, false) as SawChaseController
		if saw == null or SceneTransition.is_transitioning(): return
		if not started:
			saw.dock.begin()
			saw._preview_elapsed = 0.0
			saw.update_preview(0.0)
			world._menu_wall_preview._apply_vessel_camera_return()
	else:
		if world.scene_file_path != "res://scenes/game_world.tscn": return
		saw = world._saw_controller
		if saw == null or saw.dock == null: return
		var director: HelicopterArrivalDirector = world._helicopter_arrival_director
		if director != null:
			landed = director.have_players_touched_down()
			if not started and not director.has_started_arrival(): return
	if saw.skeleton == null: return
	if not started:
		started = true
		first_pose = saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])
	time += dt
	var spin: float = saw._preview_elapsed if mode == "menu" else saw._landing_spin_elapsed
	if saw.dock.is_deployed() and ready_at < 0.0: ready_at = time
	if landed and landed_at < 0.0:
		landed_at = time
		if mode != "menu" and world._helicopter_arrival_director != null:
			for info: Dictionary in world._helicopter_arrival_director._helicopters: contacts.append(bool(info.get("impact_played",false)))
	if spin > 0.0 and spin_at < 0.0: spin_at = time
	if (not landed or not saw.dock.is_deployed()) and spin > 0.0:
		if not failures.has("early spin"): failures.append("early spin")
	if not saw.dock.is_deployed() and saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0]).angle_to(first_pose) > .01:
		if not failures.has("blade moved during transfer"): failures.append("blade moved during transfer")
	if time >= 18.0 and not busy:
		finish(saw)
		return
	if not busy and time - last_capture >= 1.0/30.0:
		last_capture = time
		capture(saw, spin, landed)

func capture(saw: SawChaseController, spin: float, landed: bool) -> void:
	busy = true
	var row := {"time":time,"dock":saw.dock.elapsed,"spin":spin,"landed":landed,"y":saw.position.y,"z":saw.position.z,"wheel_distance":saw.dock.wheel_distance(),"ship_z":saw.dock.ship.global_position.z,"ship_visible":saw.dock.ship.visible,"bridge":float(saw.dock.pose_at(saw.dock.elapsed).bridge)}
	row["lift_y"] = saw.dock.lift.global_position.y
	row["ship_transform"] = str(saw.dock.ship.global_transform)
	if mode == "menu":
		var camera: Camera3D = get_tree().current_scene._menu_wall_preview._preview_camera
		row["camera_position"] = [camera.position.x,camera.position.y,camera.position.z]
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.resize(1400, 710)
	var file := "frame_%04d.jpg" % frames.size()
	shot.save_jpg(out + file, .94)
	row["file"] = file
	frames.append(row)
	busy = false

func finish(saw: SawChaseController) -> void:
	set_process(false)
	if spin_at < 0.0: failures.append("no spin")
	if mode != "menu":
		if contacts != [true,true]: failures.append("missing real landing contacts")
		if absf(spin_at - maxf(landed_at,ready_at)) > .08: failures.append("ready and landing spin latency")
	else:
		var camera: Camera3D = get_tree().current_scene._menu_wall_preview._preview_camera
		if not camera.position.is_equal_approx(Vector3(-18,6.1,23.15)): failures.append("menu camera did not restore original position")
	var result := {"passed":failures.is_empty(),"failures":failures,"mode":mode,"ready_at":ready_at,"landed_at":landed_at,"spin_at":spin_at,"contacts":contacts,"frames":frames,"final_z":saw.position.z,"pursuit_elapsed":QuizManager.game_state.saw.elapsed}
	FileAccess.open(out + "runtime.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var manifest := FileAccess.open(out + "frames.txt", FileAccess.WRITE)
	for i in frames.size():
		manifest.store_line("file '%s'" % frames[i].file)
		manifest.store_line("duration %.6f" % (float(frames[i+1].time)-float(frames[i].time) if i+1 < frames.size() else 1.0/30.0))
	Engine.max_fps = old_max_fps
	print("SAW_DOCK_RUNTIME ",mode," passed=",failures.is_empty()," failures=",failures)
	queue_free()
