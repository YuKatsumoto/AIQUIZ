extends Node

const OUT := "res://artifacts/saw_operator/"
func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var stage := Node3D.new()
	get_tree().root.add_child(stage)
	var saw := preload("res://scripts/world/saw_chase_controller.gd").new()
	stage.add_child(saw)
	var gs := QuizGameState.new()
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_PLAYING
	gs.saw.enabled = true
	gs.saw_transport_enabled = true
	gs.saw.elapsed = 6.0
	saw.update_visual(gs,0.0,true)
	var camera := Camera3D.new()
	stage.add_child(camera)
	var focus := saw.operator_seat.station.global_position + Vector3(0,1.45,0)
	camera.position = focus + Vector3(-3.2,1.8,3.8)
	camera.look_at(focus)
	camera.fov = 43
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
	var op := saw.operator_seat
	var report: Dictionary = {"bones":{},"samples":[]}
	for key in op.bone_rest:
		report.bones[key] = str(op.bone_rest[key])
	for t in [0.0,.08,.5,.9,1.15,1.7,2.4,3.5,6.0]:
		op.apply_sample(SawOperatorPresentation.sample(7.0,t,.7,.8,true))
		await get_tree().process_frame
		report.samples.append({"time":t,"errors":op.contact_errors.duplicate()})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT+"probe_%03d.png"%int(t*100))
	FileAccess.open(OUT+"probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_PROBE ",JSON.stringify(report.samples))
	get_tree().quit()
