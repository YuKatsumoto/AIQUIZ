extends Node

## Explicit diagnostic overview using the real imported asset and presentation.
## The game's normal cameras are restored when capture finishes.
var world: Node
var saw: SawChaseController
var camera: Camera3D
var original_camera: Transform3D
var original_fov := 70.0
var original_cap := 0
var elapsed := 0.0
var last_capture := -1.0
var busy := false
var frames: Array[Dictionary] = []
const OUT := "res://artifacts/saw_vessel/revision2/inspection/"

func _ready() -> void:
	world = get_tree().current_scene
	saw = world._saw_controller
	world.set_process(false)
	world.camera_controller.set_process(false)
	camera = world.camera_controller.camera
	original_camera = camera.global_transform
	original_fov = camera.fov
	original_cap = Engine.max_fps
	Engine.max_fps = 60
	camera.global_position = Vector3(42,25,-66)
	camera.look_at(Vector3(0,-3,-30))
	camera.fov = 62
	world.get_node("GameplayHUD").visible = false
	QuizManager.game_state.game_state = Constants.STATE_PRELOADING
	QuizManager.game_state.saw.reset()
	QuizManager.game_state.saw.enabled = true
	saw._landing_spin_elapsed = 0.0
	saw.dock.begin()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _process(dt: float) -> void:
	elapsed += dt
	saw.update_visual(QuizManager.game_state,dt,elapsed >= 4.65,true)
	if elapsed >= 18.0 and not busy:
		finish()
		return
	if not busy and elapsed-last_capture >= 1.0/30.0:
		last_capture = elapsed
		capture()

func capture() -> void:
	busy = true
	var row := {"time":elapsed,"dock":saw.dock.elapsed,"file":"frame_%04d.jpg" % frames.size(),"ship_z":saw.dock.ship.global_position.z,"lift_y":saw.dock.lift.global_position.y}
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.resize(1400,710)
	shot.save_jpg(OUT+row.file,.94)
	frames.append(row)
	busy = false

func finish() -> void:
	set_process(false)
	FileAccess.open(OUT+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"mode":"diagnostic overview; not the production camera","frames":frames},"\t"))
	var manifest := FileAccess.open(OUT+"frames.txt",FileAccess.WRITE)
	for i in frames.size():
		manifest.store_line("file '%s'" % frames[i].file)
		manifest.store_line("duration %.6f" % (float(frames[i+1].time)-float(frames[i].time) if i+1<frames.size() else 1.0/30.0))
	camera.global_transform = original_camera
	camera.fov = original_fov
	Engine.max_fps = original_cap
	world.get_node("GameplayHUD").visible = true
	world.set_process(true)
	world.camera_controller.set_process(true)
	queue_free()
