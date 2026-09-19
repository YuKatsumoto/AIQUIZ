extends Node

## Renders the live world without persisting test settings.
const OUTPUT := "res://artifacts/render_edges_v2/"
var finished := false
var report: Dictionary = {}

func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var was_paused := get_tree().paused
	get_tree().paused = true
	var world := get_tree().current_scene as Node3D
	var stage: Node = world.get_node("StageEnvironment")
	var weather: Node = stage.get("weather_cycle")
	var saved_phase: float = weather.get("day_phase")
	var was_forced: bool = weather.get("_forced")
	weather.call("force_day_phase", 0.25)
	var ocean: MeshInstance3D = stage.get("_ocean_surface")
	var mat := ocean.material_override as ShaderMaterial
	var original_shader := mat.shader
	var original_speed: Variant = mat.get_shader_parameter("wave_speed")
	mat.set_shader_parameter("wave_speed", 0.0)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = 50.0
	camera.far = 5000.0
	camera.make_current()
	var before := Shader.new()
	before.code = FileAccess.get_file_as_string(OUTPUT + "ocean_before.gdshader")
	var after := Shader.new()
	after.code = FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var poses := [
		[Vector3(40,24,-10),Vector3(0,0,45)],
		[Vector3(-30,20,-20),Vector3(0,0,50)],
		[Vector3(0,4.5,-9),Vector3(-10,1,10)]]
	report = {"renderer":RenderingServer.get_current_rendering_method(),
		"state":QuizManager.game_state.game_state,"captures":[],"errors":[]}
	for quality: String in ["low","balanced","high"]:
		GraphicsQuality.apply_text_viewport(viewport, quality)
		for variant: String in ["before","after"]:
			mat.shader = before if variant == "before" else after
			for index: int in range(poses.size()):
				camera.position = poses[index][0]
				camera.look_at(poses[index][1])
				await _capture(viewport,"%s_%s_pose%d" % [quality,variant,index])
			if quality == "high":
				for frame: int in range(24):
					var offset := float(frame) * 0.035
					camera.position = poses[0][0] + Vector3(offset,0.0,offset*0.5)
					camera.look_at(poses[0][1])
					await _capture(viewport,"motion_%s_%02d" % [variant,frame])
			# The wholly submerged target must remain visible with either shader.
			var target := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.8
			sphere.height = 1.6
			target.mesh = sphere
			var target_material := StandardMaterial3D.new()
			target_material.albedo_color = Color(1.0,0.3,0.05)
			target.material_override = target_material
			world.add_child(target)
			target.position = Vector3(80,-10.5,50)
			camera.position = Vector3(80,10,50)
			camera.look_at(target.position,Vector3.FORWARD)
			var visible := await _capture(viewport,"swimmer_%s_%s" % [quality,variant])
			target.hide()
			var hidden := await _capture(viewport,"empty_%s_%s" % [quality,variant])
			var contrast := _center_difference(visible,hidden)
			if contrast < 0.03: report.errors.append(quality+" "+variant+" lost shallow transparency")
			report.captures.append({"quality":quality,"variant":variant,
				"swimmer_contrast":contrast,"scale":viewport.scaling_3d_scale,"msaa":viewport.msaa_3d})
			target.queue_free()
	mat.shader = original_shader
	mat.set_shader_parameter("wave_speed",original_speed)
	if was_forced: weather.call("force_day_phase",saved_phase)
	else: weather.call("clear_force")
	viewport.queue_free()
	get_tree().paused = was_paused
	var file := FileAccess.open(OUTPUT+"validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	finished = true
	print("VERTICAL_OCEAN_EDGE " + JSON.stringify(report))

func _capture(viewport: Viewport, tag: String) -> Image:
	for _frame: int in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image.save_png(OUTPUT+tag+".png") != OK: report.errors.append(tag)
	return image

func _center_difference(a: Image,b: Image) -> float:
	var total := 0.0
	for y: int in range(350,370):
		for x: int in range(630,650):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			total += maxf(absf(ca.r-cb.r),maxf(absf(ca.g-cb.g),absf(ca.b-cb.b)))
	return total / 400.0
