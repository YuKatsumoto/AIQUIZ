extends SceneTree

## ぬいぐるみの材質の見比べ: 左 = 読み込んだままの材質、右 = plush_actor.gd の目を差し替えるシェーダー（右は半目）。
## 結果: res://artifacts/settings_hall/director/plush_compare.png

const PlushActorScript := preload("res://scripts/world/settings_hall/plush_actor.gd")
const GLB := "res://assets/settings_hall/godotkun_student_notes.glb"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.17, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.35, 0.38)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.6
	world.add_child(sun)
	var packed: PackedScene = load(GLB)
	var actors := []
	for i in range(2):
		var node := packed.instantiate() as Node3D
		node.position = Vector3(-0.9 + 1.8 * i, 0, 0)
		node.rotation_degrees.y = 180.0 - 20.0 + 40.0 * i
		world.add_child(node)
		if i == 1:
			var actor = PlushActorScript.new("cmp", node, world, 7)
			actor.blinking = false
			actor.set_eyes("half")
			actor.update(0.016)
			actors.append(actor)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, -3.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.85, 0))
	cam.fov = 40
	world.add_child(cam)
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/settings_hall/director/"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/settings_hall/director/plush_compare.png"))
	print("PLUSH_COMPARE saved")
	quit(0)
