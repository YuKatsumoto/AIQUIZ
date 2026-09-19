extends Node
## Rendered locomotion probe using the production shark, clips and modifier.
## godot --path . --script tests/shark_locomotion_runtime.gd --fixed-fps 60
const OUT := "res://artifacts/shark_locomotion/"
var shark: SharkSwimmer
var camera: Camera3D
var label: Label
var rows: Array[Dictionary] = []
var bone_sample: Dictionary = {}
var fin_tips: Dictionary = {}
var root: Window

func _ready() -> void:
	root = get_tree().root
	call_deferred("run")

func sample_bones() -> void:
	var skeleton := shark.model.find_child("Skeleton3D", true, false) as Skeleton3D
	bone_sample = {}
	for bone_name in ["head", "body_02", "tail_03", "pectoral.L", "pectoral.R"]:
		var index := skeleton.find_bone(bone_name)
		bone_sample[bone_name] = str(skeleton.get_bone_global_pose(index))
		if bone_name.begins_with("pectoral"):
			fin_tips[bone_name] = skeleton.get_bone_global_pose(index) * Vector3(0, 1.65, 0)

func run() -> void:
	if "menu" in OS.get_cmdline_user_args():
		await run_menu()
		return
	root.size = Vector2i(960, 540)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("102b3c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9e7fa")
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	shark = load("res://scenes/shark_swimmer.tscn").instantiate()
	shark.model_scale = 0.6
	stage.add_child(shark)
	shark.set_process(false)
	shark.position = Vector3.ZERO
	shark.quaternion = Quaternion.IDENTITY
	shark.model.rotation = Vector3(0, PI * 0.5, 0)
	shark.get("_locomotion").modification_processed.connect(sample_bones)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	stage.add_child(camera)
	camera.make_current()
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 22)
	root.add_child(label)
	var heading := 0.0
	var max_left := 0.0
	var min_right := 0.0
	var previous_turn := 0.0
	var max_turn_step := 0.0
	for frame in 1080:
		var t := frame / 60.0
		var yaw_rate := 0.0
		var speed := 3.5
		var vertical := 0.0
		var caption := "CRUISE / restrained travelling tail wave"
		if t >= 4.0 and t < 8.0:
			yaw_rate = 0.65 * sin((t - 4.0) / 4.0 * PI)
			caption = "LEFT TURN / inside fin + curved body"
		elif t >= 8.0 and t < 12.0:
			yaw_rate = -0.65 * sin((t - 8.0) / 4.0 * PI)
			caption = "RIGHT TURN / mirrored steering"
		elif t >= 12.0 and t < 15.0:
			vertical = -0.4
			caption = "DESCENDING GLIDE / reduced effort"
		elif t >= 15.0:
			speed = 12.0
			caption = "ACCELERATION / quicker strokes, bounded amplitude"
		heading += yaw_rate / 60.0
		var velocity := Vector3(-sin(heading) * speed, vertical, -cos(heading) * speed)
		var previous_forward := -shark.basis.z
		shark.set("_velocity", velocity)
		shark.position += velocity / 60.0
		shark.call("_update_orientation", 1.0 / 60.0)
		shark.call("_update_swim_locomotion", 1.0 / 60.0, previous_forward)
		camera.position = shark.position + Vector3(7, 9, 5)
		camera.look_at(shark.position)
		label.text = caption
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var modifier: SkeletonModifier3D = shark.get("_locomotion")
		var turn := float(modifier.get("turn"))
		max_left = maxf(max_left, turn)
		min_right = minf(min_right, turn)
		max_turn_step = maxf(max_turn_step, absf(turn - previous_turn))
		previous_turn = turn
		if frame % 30 == 0:
			rows.append({"time":t,"turn":turn,"stroke_gain":modifier.get("stroke_gain"),
				"cadence":shark.animation_player.speed_scale,"bones":bone_sample.duplicate()})
		if frame % 2 == 0:
			root.get_texture().get_image().save_png(OUT + "motion_%04d.png" % (frame / 2))
	# Freeze the clip at one phase: measure the actual post-modifier fin
	# endpoints, including their axes, and verify that offsets do not build up.
	shark.animation_player.pause()
	shark.animation_player.seek(0.3, true)
	var modifier: SkeletonModifier3D = shark.get("_locomotion")
	modifier.set("stroke_gain", 1.0)
	modifier.set("turn", 0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var neutral := fin_tips.duplicate()
	modifier.set("turn", 1.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var left := fin_tips.duplicate()
	for i in 60:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var drift := (fin_tips["pectoral.L"] as Vector3).distance_to(left["pectoral.L"])
	modifier.set("turn", -1.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var right := fin_tips.duplicate()
	var left_drop: float = left["pectoral.L"].y - neutral["pectoral.L"].y
	var right_drop: float = right["pectoral.R"].y - neutral["pectoral.R"].y
	var fin_pass := left_drop < -0.06 and right_drop < -0.06 and drift < 0.0001
	var passed := max_left > 0.6 and min_right < -0.6 and max_turn_step < 0.03 and fin_pass
	var report := {"passed":passed,"renderer":RenderingServer.get_current_rendering_method(),
		"max_left":max_left,"min_right":min_right,"max_turn_step":max_turn_step,"samples":rows,
		"inside_fin_drop_left":left_drop,"inside_fin_drop_right":right_drop,"pose_accumulation":drift}
	FileAccess.open(OUT + "runtime_motion.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SHARK_LOCOMOTION_RESULT ", JSON.stringify({"passed":passed,"left":max_left,"right":min_right,"max_step":max_turn_step,"fin_left":left_drop,"fin_right":right_drop,"drift":drift}))
	get_tree().quit(0 if passed else 1)


func run_menu() -> void:
	root.size = Vector2i(960, 540)
	root.get_node("QuizManager").provider.set("llm_mode", "OFFLINE")
	var menu: Node = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	get_tree().current_scene = menu
	var samples: Array[Dictionary] = []
	for frame in 600:
		await get_tree().process_frame
		if frame % 60 != 0:
			continue
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "menu_%03d.png" % frame)
		for s: SharkSwimmer in menu.find_children("*", "SharkSwimmer", true, false):
			var modifier: SkeletonModifier3D = s.get("_locomotion")
			samples.append({"frame":frame,"position":str(s.position),"animation":s.animation_player.current_animation,
				"turn":modifier.get("turn"),"stroke_gain":modifier.get("stroke_gain"),"active":modifier.get("swim_active")})
	var passed := samples.size() > 5
	for sample in samples:
		passed = passed and bool(sample.active)
	FileAccess.open(OUT + "menu.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"samples":samples},"\t"))
	print("SHARK_MENU_RESULT ", JSON.stringify({"passed":passed,"samples":samples.size()}))
	get_tree().quit(0 if passed else 1)
