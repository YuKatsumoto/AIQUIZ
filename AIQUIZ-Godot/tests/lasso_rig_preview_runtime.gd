extends Node

## tests/lasso_rig_preview.gd から起動する本体（自動読み込みの後に読み込む）。

const OUT := "res://artifacts/elimination_lasso/rig/"

var rider: LassoCloudRider
var rope: LassoRope
var camera: Camera3D
var pose_name := "idle"


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("pose="):
			pose_name = arg.trim_prefix("pose=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_tree().root.size = Vector2i(960, 720)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.5, 0.9)
	sky_material.sky_horizon_color = Color(0.7, 0.82, 0.95)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	rider = LassoCloudRider.new()
	world.add_child(rider)
	if not rider.setup("high"):
		print("RIG_PREVIEW setup failed")
		get_tree().quit(1)
		return
	rope = LassoRope.new()
	world.add_child(rope)
	rope.setup(0.03, "high")
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 40.0
	var pose := _pose(0.0)
	rider.apply_pose(pose)
	rope.reset_hanging(rider.grip_point("R"), Vector3.RIGHT, 0.3, 0.42)
	for step in range(90):
		var t := float(step) / 60.0
		rider.apply_pose(_pose(t))
		rope.hand = rider.grip_point("R")
		rope.coil_transform = Transform3D(rider.transform.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5), rider.grip_point("L"))
		rope.simulate(1.0 / 60.0)
		rope.rebuild_mesh()
		await get_tree().process_frame
	var views := {
		"front": [Vector3(0.6, 1.3, 4.2), Vector3(0.0, 1.0, 0.0)],
		"three_quarter": [Vector3(-2.6, 1.6, 3.2), Vector3(0.0, 1.05, 0.0)],
		"side": [Vector3(-4.2, 1.2, 0.0), Vector3(0.0, 1.0, 0.0)],
		"back": [Vector3(1.4, 2.0, -3.6), Vector3(0.0, 1.0, 0.0)],
		"low": [Vector3(-1.6, -0.3, 2.6), Vector3(-0.1, 1.5, 0.2)],
	}
	for view_name: String in views:
		var view: Array = views[view_name]
		camera.global_position = view[0]
		camera.look_at(view[1], Vector3.UP)
		for _f in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "%s_%s.png" % [pose_name, view_name])
	var head := rider.skeleton.find_bone("DEF-head")
	print("RIG_PREVIEW done ", pose_name, " grip R ", rider.grip_point("R"), " L ", rider.grip_point("L"), " head ", rider.skeleton.get_bone_global_pose(head).origin)
	get_tree().quit(0)


func _pose(t: float) -> Dictionary:
	match pose_name:
		"twirl":
			var theta := t * TAU * 1.6
			var hand := Vector3(-0.44, 1.07, 0.1) + Vector3(sin(theta + 1.9), 0.0, cos(theta + 1.9)) * 0.05
			return {"r_hand": hand, "r_pole": Vector3(-1.0, -0.2, 0.3), "r_hand_dir": Vector3.UP,
				"l_hand": Vector3(0.6, 0.7, 0.32), "body_rot": Quaternion.from_euler(Vector3(deg_to_rad(6.0), 0.0, 0.0))}
		"throw":
			var target_dir := Vector3(0.0, -0.55, 0.83).normalized()
			return {"r_hand": Vector3(-0.52, 0.86, 0.0) + target_dir * 0.31, "r_hand_dir": target_dir, "r_pole": Vector3(-0.8, -0.6, 0.0),
				"l_hand": Vector3(0.3, 0.72, 0.36), "body_rot": Quaternion.from_euler(Vector3(deg_to_rad(22.0), -0.2, 0.0)), "squash": 1.08}
		"haul":
			var rope_dir := Vector3(0.1, -0.85, -0.5).normalized()
			return {"r_hand": Vector3(-0.56, 0.7, -0.12), "r_hand_dir": rope_dir, "l_hand": Vector3(-0.56, 0.7, -0.12) + rope_dir * 0.28 + Vector3(0.18, 0.04, 0.05),
				"l_hand_dir": rope_dir, "body_rot": Quaternion.from_euler(Vector3(deg_to_rad(-20.0), 0.0, 0.0))}
	return {}
