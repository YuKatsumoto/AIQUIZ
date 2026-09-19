extends SceneTree

const StandScene = preload("res://assets/environment/santorini_grandstand/santorini_open_terrace.glb")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var stand := StandScene.instantiate() as Node3D
	stage.add_child(stand)
	var crowd := CrowdScript.new()
	stand.add_child(crowd)
	crowd.build(0.85, 7919)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.33, 0.57, 0.73)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.79, 0.91)
	environment.ambient_light_energy = 0.40
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.80
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -28.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	stage.add_child(sun)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	sea.mesh = plane
	sea.position.y = -9.2
	var sea_material := StandardMaterial3D.new()
	sea_material.albedo_color = Color(0.02, 0.30, 0.39)
	sea.material_override = sea_material
	stage.add_child(sea)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19.6875
	stage.add_child(camera)
	camera.position = Vector3(-28.0, 19.0, 29.0)
	camera.look_at(Vector3(3.0, 0.6, 39.0), Vector3.UP)
	camera.current = true
	root.msaa_3d = Viewport.MSAA_4X
	for index: int in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png("res://assets/environment/santorini_grandstand/source/previews/santorini_terrace_godot_crowd.png")
	var started_ms: int = Time.get_ticks_msec()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	after.save_png("res://assets/environment/santorini_grandstand/source/previews/santorini_terrace_godot_crowd_after.png")
	var before_data: PackedByteArray = before.get_data()
	var after_data: PackedByteArray = after.get_data()
	var changed_bytes: int = 0
	for index: int in range(before_data.size()):
		if before_data[index] != after_data[index]:
			changed_bytes += 1
	var report := {"passed": changed_bytes > 500, "changed_image_bytes": changed_bytes,
		"elapsed_ms": Time.get_ticks_msec() - started_ms, "spectators": crowd.spectator_count,
		"renderer": "Forward+", "camera_fixed": true, "environment_fixed": true,
		"scope": "Isolated imported stand and crowd shader motion; main gameplay is separate."}
	var output := FileAccess.open("res://assets/environment/santorini_grandstand/motion_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("SANTORINI_STAND_MOTION ", JSON.stringify(report))
	print("SANTORINI_STAND_RENDERED ", crowd.spectator_count, " spectators; isolated Forward+ GLB and crowd review")
	quit()
