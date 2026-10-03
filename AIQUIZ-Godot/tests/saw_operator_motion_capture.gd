extends Node

## Close-up stills (and an optional 30fps frame sequence) of every v3 operator motion:
## transport, six waiting vignettes, the start routine, running checks, stick inputs,
## the catch celebration and the shutdown.
## godot --path . --resolution 960x720 --script res://tests/saw_operator_motion_capture_bootstrap.gd [-- --sequence]
const OUT := "res://artifacts/saw_operator/v3/operating_pass/"
const VIEWS := {
	"front": [Vector3(-1.2,2.3,2.6), Vector3(0.0,.8,.35)],
	"side": [Vector3(2.9,1.7,1.2), Vector3(0.0,.85,.35)],
	"high": [Vector3(.9,3.1,-1.1), Vector3(0.0,.7,.45)],
	"hero": [Vector3(1.7,2.2,2.5), Vector3(-.05,.8,.35)],
}
var op: SawOperatorPresentation
var camera: Camera3D

func _ready() -> void:
	call_deferred("run")

## [name, entry, spin, drive, lift_speed, idle, extra]
static func shots() -> Array:
	var slot := SawOperatorPresentation.IDLE_SLOT
	return [
		["ship_slide",5.62,0.0,0.0,0.0,0.0,{},false],["ship_drop",6.12,0.0,0.0,0.0,0.0,{},false],
		["wait_look",7.0,0.0,0.0,0.0,1.8,{}],["wait_drum",7.0,0.0,0.0,0.0,slot+2.55,{}],
		["wait_stretch",7.0,0.0,0.0,0.0,2*slot+2.6,{}],["wait_doze",7.0,0.0,0.0,0.0,3*slot+3.5,{}],
		["wait_swing",7.0,0.0,0.0,0.0,4*slot+2.6,{}],["wait_wave",7.0,0.0,0.0,0.0,5*slot+2.4,{}],
		["start_key_guard",7.0,.45,0.0,0.0,0.0,{}],["start_windup",7.0,.68,0.0,0.0,0.0,{}],
		["start_slam",7.0,.90,0.0,0.0,0.0,{}],["start_pump",7.0,1.55,0.0,0.0,0.0,{}],
		["run_gauges",7.0,3.9,1.0,0.0,0.0,{}],["run_dial",7.0,7.0,1.0,0.0,0.0,{}],
		["run_hunt",7.0,11.6,1.0,0.0,0.0,{}],["run_groove",7.0,14.6,1.0,0.0,0.0,{}],
		["run_lift_check",7.0,18.4,1.0,0.0,0.0,{}],
		["drive_reverse",7.0,20.0,-1.0,0.0,0.0,{}],["lift_up",7.0,20.0,1.0,6.0,0.0,{}],["lift_down",7.0,20.0,1.0,-6.0,0.0,{}],
		["catch_honk",7.0,20.0,1.0,0.0,0.0,{"catch":.42}],["catch_pump",7.0,20.0,1.0,0.0,0.0,{"catch":1.32}],
		["stop_key_off",7.0,20.0,0.0,0.0,0.0,{"stop":.9,"rpm":.4}],["stop_guard",7.0,20.0,0.0,0.0,0.0,{"stop":1.4,"rpm":.1}],
		["stop_relaxed",7.0,20.0,0.0,0.0,0.0,{"stop":2.0,"rpm":0.0}],
	]

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
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.environment.glow_enabled = true
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-42,-35,0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	var report := {"shots":[]}
	var views: Array = VIEWS.keys()
	if "--sequence" in OS.get_cmdline_user_args() or "--stow" in OS.get_cmdline_user_args(): views = ["hero"]
	for shot: Array in shots():
		var deployed: bool = shot[7] if shot.size() > 7 else true
		op.apply_sample(SawOperatorPresentation.sample(shot[1],shot[2],shot[3],1.0,deployed,shot[4],shot[5],shot[6]))
		report.shots.append({"name":shot[0],"errors":op.contact_errors.duplicate()})
		for view: String in views:
			await _save(view,"%s_%s.png"%[shot[0],view])
	if "--stow" in OS.get_cmdline_user_args():
		# Menu stow on its own clock: stow, rest racked, deploy (seq_stow/, hero view).
		var stow_frame := 0
		for sample: Dictionary in stow_sequence():
			op.apply_sample(sample)
			await _save("hero","seq_stow/%05d.jpg"%stow_frame)
			stow_frame += 1
		report.stow_frames = stow_frame
	if "--sequence" in OS.get_cmdline_user_args():
		var frame := 0
		for sample: Dictionary in sequence():
			op.apply_sample(sample)
			await _save("hero","seq/%05d.jpg"%frame)
			frame += 1
		report.sequence_frames = frame
	FileAccess.open(OUT+"capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_MOTION_CAPTURE ",JSON.stringify({"shots":shots().size(),"frames":report.get("sequence_frames",0)}))
	get_tree().quit()

## Menu stow at full clip speed (p advances 1.3/s): stow, 16 s racked, then deploy.
static func stow_sequence() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var length := 12.4167
	var p := 0.0
	var rate := 0.0
	var idle := -1.0
	for leg: Array in [[0.0,1.0],[1.0,length],[0.0,16.0],[-1.0,0.0],[0.0,1.0]]:
		var want: float = leg[0]
		var held := 0.0
		for i in 3000:
			rate = move_toward(rate, want, .1)
			if want == 0.0:
				held += 1.0/30.0
				if p >= length: idle = maxf(idle,0.0) + 1.0/30.0
				if held >= float(leg[1]): break
			else:
				p = clampf(p + rate*1.3/30.0, 0.0, length)
				if p >= length: idle = maxf(idle,0.0)
				elif p <= length - SawOperatorPresentation.STOW_REST_FADE: idle = -1.0
				if (want > 0.0 and p >= float(leg[1])) or (want < 0.0 and p <= float(leg[1])): break
			out.append(SawOperatorPresentation.sample(7.2,20.0,0.0,1.0,true,0.0,0.0,
				{"rpm":1.0-smoothstep(0.0,1.3,p),"stow":p,"stow_length":length,"stow_rate":rate,"stow_idle":idle}))
	return out

## Transport, all six waiting vignettes, the start, one running cycle, a catch and the stop.
static func sequence() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(30*3): out.append(SawOperatorPresentation.sample(4.2+i/30.0,0.0,0.0,1.0,false))
	var wait := SawOperatorPresentation.IDLE_SLOT*6.0
	for i in range(int(30*wait)): out.append(SawOperatorPresentation.sample(7.2,0.0,0.0,1.0,true,0.0,i/30.0))
	for i in range(30*11):
		var t := i/30.0
		var lift_speed := 6.0*(smoothstep(6.0,6.2,t)-smoothstep(6.8,7.0,t)) - 6.0*(smoothstep(8.0,8.2,t)-smoothstep(8.8,9.0,t))
		out.append(SawOperatorPresentation.sample(7.2,t,smoothstep(3.3,4.0,t),1.0,true,lift_speed,wait))
	for i in range(30*6):
		var t := i/30.0
		var extra := {"catch": t if t < 3.0 else -1.0}
		if t >= 3.0: extra.merge({"stop": minf(t-3.0,2.0), "rpm": 1.0-smoothstep(0.0,2.0,t-3.0)})
		out.append(SawOperatorPresentation.sample(7.2,11.0+t,1.0-smoothstep(3.0,5.0,t),1.0,true,0.0,wait,extra))
	return out

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
