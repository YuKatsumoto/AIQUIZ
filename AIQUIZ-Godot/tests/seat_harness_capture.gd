extends Node

const OUT := "res://artifacts/seat_harness_physics/"

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var root := get_tree().root
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var stage := Node3D.new()
	root.add_child(stage)
	var op := SawOperatorPresentation.new()
	stage.add_child(op)
	op.position = Vector3.ZERO
	op.rotation = Vector3.ZERO
	op.apply_sample(SawOperatorPresentation.sample(6.2, 4.0, 0.0, 0.0, true))
	var camera := Camera3D.new()
	stage.add_child(camera)
	var focus := op.station.to_global(Vector3(0, 1.68, -.25))
	camera.position = focus + Vector3(2.1, .95, 3.6)
	camera.look_at(focus)
	camera.fov = 40
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.075, .105, .145)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.8, .86, 1.0)
	env.environment.ambient_light_energy = .75
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.6
	var transfer := op.seat_transfer
	transfer.begin_buckle()
	transfer.set_process(false)
	if "--motion" in OS.get_cmdline_user_args():
		for frame in 136:
			var time := frame / 30.0
			transfer.phase = transfer.Phase.BUCKLING if time < 3.0 else transfer.Phase.UNBUCKLING
			transfer.elapsed = minf(time, 2.6) if time < 3.0 else minf(time - 3.0, 1.0)
			transfer._apply_pose()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(OUT + "motion_%03d.jpg" % frame, .95)
		transfer.phase = transfer.Phase.BUCKLING
	for time in [0.0, .85, 1.25, 1.65, 1.95, 2.35, 2.6]:
		transfer.elapsed = time
		transfer._apply_pose()
		print("BELT_SAMPLE ",time," tip=",transfer.harness.tips[0].position," lock_gap=",transfer.harness.ropes[0].lock_distance)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "buckle_%03d.png" % int(time * 100))
	var audit := audit_fit(op)
	FileAccess.open(OUT + "fit_audit.json", FileAccess.WRITE).store_string(JSON.stringify(audit, "\t"))
	print("HARNESS_FIT ", JSON.stringify(audit))
	camera.position = focus + Vector3(3.4, .75, 1.9)
	camera.look_at(focus)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "latched_side.png")
	transfer.phase = transfer.Phase.UNBUCKLING
	for time in [.35, .55, .8]:
		transfer.elapsed = time
		transfer._apply_pose()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "release_%03d.png" % int(time * 100))
	print("HARNESS_CAPTURE complete")
	get_tree().quit(0 if audit.passed else 1)

func audit_fit(op: SawOperatorPresentation) -> Dictionary:
	# Compare the rendered, skinned mascot triangles, not the profile table used
	# by the belt. A ray starts in front of each strap sample and finds the body.
	var body := op.station.find_child("GodotPlushMesh", true, false) as MeshInstance3D
	var arrays := body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := bones.size() / vertices.size()
	var posed := PackedVector3Array()
	var head_weights := PackedFloat32Array()
	for v in vertices.size():
		var p := Vector3.ZERO
		var head_weight := 0.0
		for influence in influences:
			var at := v * influences + influence
			var bind := bones[at]
			var bone := body.skin.get_bind_bone(bind)
			if bone < 0: bone = op.skeleton.find_bone(body.skin.get_bind_name(bind))
			if bone in [op.bones["DEF-head"], op.bones["DEF-hips"]]: head_weight += weights[at]
			p += (op.skeleton.get_bone_global_pose(bone) * body.skin.get_bind_pose(bind) * vertices[v]) * weights[at]
		posed.append(op.seat_transfer.kit.to_local(op.skeleton.to_global(p)))
		head_weights.append(head_weight)
	var minimum := INF
	var maximum := -INF
	var samples := 0
	for side in [1.0, -1.0]:
		for step in range(40, 95):
			for width in [-.90, 0.0, .90]:
				var p: Vector3 = op.seat_transfer.harness.rendered_point(side, step / 100.0, width * op.seat_transfer.harness.WIDTH * .5)
				if p.y < 1.55 or p.y > 1.95: continue
				var front := -INF
				for triangle in range(0, indices.size(), 3):
					# Hands rest in front of the straps at the lap. Audit the torso
					# shell, rather than treating the front of a hand as the torso.
					if head_weights[indices[triangle]] < .8 or head_weights[indices[triangle + 1]] < .8 or head_weights[indices[triangle + 2]] < .8: continue
					var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x,p.y,2), Vector3.FORWARD, posed[indices[triangle]], posed[indices[triangle + 1]], posed[indices[triangle + 2]])
					if hit != null: front = maxf(front, (hit as Vector3).z)
				if front == -INF: continue
				minimum = minf(minimum, p.z - front)
				maximum = maxf(maximum, p.z - front)
				samples += 1
	return {"samples":samples, "min_center_surface_gap_m":minimum, "max_center_surface_gap_m":maximum, "passed":samples > 60 and minimum > .004 and maximum < .035}
