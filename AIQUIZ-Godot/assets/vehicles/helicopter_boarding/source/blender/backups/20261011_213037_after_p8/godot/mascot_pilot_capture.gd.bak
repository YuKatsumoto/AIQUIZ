extends Node

## Close-up of the mascot pilot in the helicopter cockpit (the same OnlineHeliportHelicopter the
## HelicopterArrivalDirector flies: glass, full-size HatenaPilot), saved to artifacts/mascot/pilot_*.png.
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/mascot_capture_bootstrap.gd -- pilot

const OUT := "res://artifacts/mascot/"
## Helicopter coordinates (H): origin at the skid contact, nose -Z. The pilot sits at MK_SeatPilot.
## [eye, target, fov]. cockpit / board are the online staging CAM_Cockpit / CAM_Board (board opens the left door).
const VIEWS := {
	"front": [Vector3(0.4, 2.6, -7.0), Vector3(0.4, 2.0, -1.3), 40.0],
	"side": [Vector3(4.8, 2.4, -1.6), Vector3(0.5, 2.0, -1.3), 40.0],
	"high": [Vector3(2.6, 4.6, -4.8), Vector3(0.4, 1.9, -1.0), 40.0],
	"cockpit": [Vector3(-0.3, 2.35, -6.6), Vector3(0.0, 2.15, -1.2), 34.0],
	"board": [Vector3(-7.2, 1.45, -4.4), Vector3(-1.3, 1.65, -1.3), 42.0],
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := get_tree().root
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var stage := Node3D.new()
	root.add_child(stage)
	var heli := OnlineHeliportHelicopter.new()
	stage.add_child(heli)
	heli.setup(PlayerController.P1_BODY, true, false)
	heli.pilot.play(&"steer")
	var pilot := heli.pilot as Node3D
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
		var mesh := pilot.find_child("*", true, false) as Node3D
		report["mesh"] = mesh != null
		report["pilot_global"] = str(pilot.global_transform)
	for view: String in VIEWS:
		var eye: Vector3 = VIEWS[view][0]
		var target: Vector3 = VIEWS[view][1]
		camera.fov = float(VIEWS[view][2])
		heli.set_door("L", 1.0 if view == "board" else 0.0)
		camera.look_at_from_position(eye, target)
		for i in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "pilot_%s.png" % view))
	stage.queue_free()
	print("MASCOT_PILOT_CAPTURE ", JSON.stringify(report))
	get_tree().quit()
