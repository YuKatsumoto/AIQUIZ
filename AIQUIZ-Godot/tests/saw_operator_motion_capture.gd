extends Node

## Close-up stills (and an optional frame sequence) of the operating pass:
## waiting look-around, start sequence, running checks, lever pushes and lifts.
## godot --path . --resolution 960x720 --script res://tests/saw_operator_motion_capture_bootstrap.gd [-- --sequence]
const OUT := "res://artifacts/saw_operator/operating_pass/"
const VIEWS := {
	"side": [Vector3(2.7,1.55,1.35), Vector3(0.0,.86,.3)],
	"front": [Vector3(-1.05,2.25,2.35), Vector3(0.0,.82,.22)],
	"rear": [Vector3(-.95,1.85,-1.75), Vector3(0.0,.9,.3)],
}
var op: SawOperatorPresentation
var camera: Camera3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var stage := Node3D.new()
	get_tree().root.add_child(stage)
	var saw := SawChaseController.new()
	stage.add_child(saw)
	saw.update_preview(0.0)
	op = saw.operator_seat
	camera = Camera3D.new()
	camera.fov = 40
	stage.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.09,.13,.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.72,.81,.95)
	environment.environment.ambient_light_energy = .65
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-40,-35,0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	var tap_cycle := 0
	while fposmod(sin(tap_cycle*12.9898+.37)*43758.5453,1.0) >= .65: tap_cycle += 1
	var cycle := 3.3 + tap_cycle*SawOperatorPresentation.CHASE_CYCLE
	var shots := [
		["wait_rest",0.0,0.0,0.0,0.0],["wait_gauge_L",0.0,0.0,0.0,1.65],["wait_regrip",0.0,0.0,0.0,1.35],
		["wait_ahead",0.0,0.0,0.0,3.85],["wait_gauge_R",0.0,0.0,0.0,5.8],
		["start_press",.10,0.0,0.0,0.0],["start_cover",.62,0.0,0.0,0.0],["start_toggle",1.12,0.0,0.0,0.0],
		["start_dial",2.30,0.0,0.0,0.0],["start_return",3.05,0.0,0.0,0.0],
		["run_gauge_L",cycle+1.15,1.0,0.0,0.0],["run_ahead",cycle+2.7,1.0,0.0,0.0],
		["run_dial_tap",cycle+4.35,1.0,0.0,0.0],["run_gauge_R",cycle+5.75,1.0,0.0,0.0],
		["push_travel",cycle+.2,-1.0,0.0,0.0],["lift_up",cycle+.2,1.0,6.0,0.0],["lift_down",cycle+.2,1.0,-6.0,0.0],
	]
	var report := {"tap_cycle":tap_cycle,"shots":[]}
	for shot: Array in shots:
		op.apply_sample(SawOperatorPresentation.sample(7.0,shot[1],shot[2],1.0,true,shot[3],shot[4]))
		report.shots.append({"name":shot[0],"errors":op.contact_errors.duplicate()})
		for view: String in VIEWS:
			await _save(view,"%s_%s.png"%[shot[0],view])
	if "--sequence" in OS.get_cmdline_user_args():
		# Waiting (idle clock) then the start and a full running cycle, 30fps.
		var frame := 0
		for i in range(30*8):
			op.apply_sample(SawOperatorPresentation.sample(7.0,0.0,0.0,1.0,true,0.0,i/30.0))
			await _save("front","seq/%05d.jpg"%frame); frame += 1
		for i in range(int(30*(cycle+SawOperatorPresentation.CHASE_CYCLE))):
			var t := i/30.0
			var lift_speed := 6.0*(smoothstep(5.0,5.2,t)-smoothstep(5.8,6.0,t)) - 6.0*(smoothstep(7.0,7.2,t)-smoothstep(7.8,8.0,t))
			op.apply_sample(SawOperatorPresentation.sample(7.0,t,smoothstep(3.3,4.0,t),1.0,true,lift_speed,8.0))
			await _save("front","seq/%05d.jpg"%frame); frame += 1
		report.sequence_frames = frame
	FileAccess.open(OUT+"capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_MOTION_CAPTURE ",JSON.stringify({"shots":shots.size(),"frames":report.get("sequence_frames",0)}))
	get_tree().quit()

func _save(view: String, file: String) -> void:
	var pose: Array = VIEWS[view]
	camera.global_position = op.skeleton.to_global(pose[0])
	camera.look_at(op.skeleton.to_global(pose[1]))
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless": return
	var path := OUT+file
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image := get_viewport().get_texture().get_image()
	if file.ends_with(".jpg"): image.save_jpg(path,.9)
	else: image.save_png(path)
