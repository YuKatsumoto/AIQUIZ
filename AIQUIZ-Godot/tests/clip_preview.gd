extends SceneTree

## ゴドーくんの GLB のクリップを横に並べ、それぞれ指定の位置（長さに対する割合）で止めて撮る（動きの確認用）。
## 引数（-- のあと）: glb=godotkun_lecturer clips=T_Carry,G_Sweep at=0.25,0.5 tag=名前
## 結果: res://artifacts/settings_hall/clips/<tag>.png（行 = at、列 = clips）

const OUT := "res://artifacts/settings_hall/clips/"

var _args := {"glb": "godotkun_lecturer", "clips": "G_Idle", "at": "0.25,0.5", "tag": "clips"}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	call_deferred("run")


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.21, 0.23)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.42, 0.42, 0.45)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.5
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var packed: PackedScene = load("res://assets/settings_hall/%s.glb" % _args.glb)
	var clips: PackedStringArray = str(_args.clips).split(",")
	var ats: PackedStringArray = str(_args.at).split(",")
	var spacing := 1.45
	var count := clips.size() * ats.size()
	var index := 0
	for row in range(ats.size()):
		for col in range(clips.size()):
			var node := packed.instantiate() as Node3D
			node.position = Vector3((index - (count - 1) * 0.5) * -spacing, 0.0, 0.0)
			node.rotation_degrees.y = float(_args.get("yaw", "215"))
			world.add_child(node)
			index += 1
			var player := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if player == null or not player.has_animation(clips[col]):
				print("MISSING ", clips[col])
				continue
			player.play(clips[col])
			var length := player.get_animation(clips[col]).length
			player.seek(length * float(ats[row]), true)
			player.pause()
			var label := Label3D.new()
			label.text = "%s @%s" % [clips[col], ats[row]]
			label.font_size = 40
			label.pixel_size = 0.004
			label.position = node.position + Vector3(0, 1.9, 0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			world.add_child(label)
	var cam := Camera3D.new()
	cam.fov = 36
	world.add_child(cam)
	var width := count * spacing
	cam.look_at_from_position(Vector3(0, 1.5, -width * 0.8 - 1.2), Vector3(0, 0.85, 0))
	for _i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + str(_args.tag) + ".png"))
	print("CLIP_PREVIEW saved ", OUT + str(_args.tag) + ".png")
	quit(0)
