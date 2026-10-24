extends Node

## 水上機の航跡（FloatplaneWake）だけを、ステージと同じ海の上で描いて撮る（c130_float.md 第9章）。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/floatplane_wake_check_bootstrap.gd
## 出力：artifacts/sudden_death_v2/floatplane_flight/wake/（上から見た画と横から見た画）。

const OUT := "res://artifacts/sudden_death_v2/floatplane_flight/wake/"


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_tree().root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.8, 0.9)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var ocean := StageEnvironment.create_ocean_surface()
	world.add_child(ocean)
	ocean.position = Vector3(0.0, StageConstants.OCEAN_SURFACE_Y, 0.0)
	var wake := FloatplaneWake.new()
	world.add_child(wake)
	wake.set_ocean(ocean)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	# 機体の代わりの点：+X へ 30 m/秒、途中で 6 m/秒まで落とす
	var x := -60.0
	var v := 30.0
	for frame in range(240):
		var dt := 1.0 / 60.0
		v = lerpf(30.0, 6.0, clampf(float(frame) / 200.0, 0.0, 1.0))
		x += v * dt
		var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, StageConstants.OCEAN_SURFACE_Y, 0.0))
		wake.advance(dt, xf, v, true, 1.0 if frame < 20 else 0.0)
		cam.global_transform = Transform3D(Basis.looking_at(Vector3(x - 40.0, StageConstants.OCEAN_SURFACE_Y, 0.0) - Vector3(x - 40.0, 60.0, 30.0), Vector3.UP), Vector3(x - 40.0, 60.0, 30.0))
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "wake_top.png"))
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(x - 50.0, StageConstants.OCEAN_SURFACE_Y, 0.0) - Vector3(x + 10.0, StageConstants.OCEAN_SURFACE_Y + 4.0, -25.0), Vector3.UP), Vector3(x + 10.0, StageConstants.OCEAN_SURFACE_Y + 4.0, -25.0))
	for _i in range(3):
		wake.advance(1.0 / 60.0, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, StageConstants.OCEAN_SURFACE_Y, 0.0)), 6.0, true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "wake_low.png"))
	print("WAKE_CHECK points=", wake.point_count())
	get_tree().quit(0)
