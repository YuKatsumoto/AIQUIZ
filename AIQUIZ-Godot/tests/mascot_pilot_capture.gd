extends Node

## Close-up of the mascot pilot in the helicopter cockpit (the real HelicopterArrivalDirector
## glass and pilot mount on the real helicopter model), saved to artifacts/mascot/pilot_*.png.
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/mascot_capture_bootstrap.gd -- pilot

const OUT := "res://artifacts/mascot/"
const VIEWS := {
	"front": [Vector3(0.0, 0.6, -4.2), Vector3(0.0, 0.1, -1.0)],
	"side": [Vector3(3.6, 0.7, -1.4), Vector3(0.0, 0.1, -1.0)],
	"high": [Vector3(1.8, 2.6, -3.4), Vector3(0.0, 0.0, -0.8)],
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := get_tree().root
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var director := HelicopterArrivalDirector.new()
	var model := (load(HelicopterArrivalDirector.HELICOPTER_GLB) as PackedScene).instantiate() as Node3D
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(model)
	director.call("_apply_window_glass", model)
	director.call("_mount_pilot", model)
	var pilot := model.find_child("MascotPilot", true, false) as Node3D
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.70, 0.86)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 40.0
	stage.add_child(camera)
	camera.make_current()
	var report := {"pilot": pilot != null}
	if pilot != null:
		var mesh := pilot.find_child("HERO_Mascot", true, false) as MeshInstance3D
		report["mesh"] = mesh != null
		report["pilot_global"] = str(pilot.global_transform)
	for view: String in VIEWS:
		var eye: Vector3 = VIEWS[view][0]
		var target: Vector3 = VIEWS[view][1]
		camera.look_at_from_position(eye, target)
		for i in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "pilot_%s.png" % view))
	director.free()
	print("MASCOT_PILOT_CAPTURE ", JSON.stringify(report))
	get_tree().quit()
