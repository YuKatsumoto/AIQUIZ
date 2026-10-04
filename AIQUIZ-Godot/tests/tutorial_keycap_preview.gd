extends SceneTree

## 3Dキーキャップ単体の見た目確認。形状・陰影・刻印・押下・達成表示を1枚に並べて撮る。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_keycap_preview.gd
const OUT := "res://artifacts/tutorial_keys3d/"
const KeycapScript = preload("res://scripts/world/tutorial_keycap_3d.gd")

var _keys: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.46, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 4.4)
	camera.fov = 50.0
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true

	var specs := [
		{"legend": "A", "units": 1.0, "accent": Color("ffa440"), "look": 1, "pos": Vector3(-2.4, 0.0, -0.6)},
		{"legend": "W", "units": 1.0, "accent": Color("ffa440"), "look": 0, "pos": Vector3(-1.2, 0.0, -0.6)},
		{"legend": "D", "units": 1.0, "accent": Color("ffa440"), "look": 2, "pos": Vector3(0.0, 0.0, -0.6)},
		{"legend": "←", "units": 1.0, "accent": Color("51d8ec"), "look": 1, "pos": Vector3(1.2, 0.0, -0.6)},
		{"legend": "Ctrl", "sub": "右", "units": 1.5, "accent": Color("51d8ec"), "look": 1, "pos": Vector3(2.6, 0.0, -0.6)},
		{"legend": "Space", "units": 5.0, "accent": Color("ffa440"), "look": 1, "pos": Vector3(-0.6, 0.0, 0.9), "pressed": true},
		{"legend": "1", "units": 1.0, "accent": Color("ffa440"), "look": 1, "pos": Vector3(2.6, 0.0, 0.9)},
	]
	for spec: Dictionary in specs:
		var key: Node3D = KeycapScript.new()
		stage.add_child(key)
		key.call("setup", spec.legend, spec.units, spec.accent, spec.get("sub", ""))
		key.call("set_look", spec.look)
		key.call("set_shown", true, true)
		key.call("set_pressed", bool(spec.get("pressed", false)))
		key.position = spec.pos
		_keys.append(key)
	for i: int in range(40):
		for key: Node3D in _keys:
			key.call("advance", 1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "keycap_preview.png"))
	# 正面寄りの角度でも1枚撮る（チュートリアル中の見え方に近い）。
	camera.position = Vector3(0.0, 1.6, 4.8)
	camera.look_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)
	for i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "keycap_preview_low.png"))
	print("KEYCAP_PREVIEW_DONE")
	quit(0)
