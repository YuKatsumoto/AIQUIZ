extends Node

## Run from the editor game after a real offline round has reached PLAYING.
## Renders the live world's meshes through a controlled moving camera. The
## original shader is an artifact backup, never a second production shader.
const OUTPUT := "res://artifacts/render_edges/"
var finished := false
var report: Dictionary = {}


func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	var paused_before := tree.paused
	tree.paused = true
	var world := tree.current_scene as Node3D
	var stage := world.get_node("StageEnvironment")
	var ocean: MeshInstance3D = stage.get("_ocean_surface")
	var material := ocean.material_override as ShaderMaterial
	var saved_shader := material.shader
	var saved_speed: Variant = material.get_shader_parameter("wave_speed")
	material.set_shader_parameter("wave_speed", 0.0)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.far = 5000.0
	camera.fov = 50.0
	camera.make_current()
	var before := Shader.new()
	before.code = FileAccess.get_file_as_string(OUTPUT + "ocean_before.gdshader")
	var after := Shader.new()
	after.code = FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	report = {"renderer":RenderingServer.get_current_rendering_method(),
		"state":QuizManager.game_state.game_state, "players":QuizManager.game_state.num_players,
		"captures":[], "errors":[]}
	for quality: String in ["low", "balanced", "high"]:
		GraphicsQuality.apply_text_viewport(viewport, quality)
		for variant: String in ["before", "after"]:
			material.shader = before if variant == "before" else after
			for frame: int in range(24):
				# Subpixel lateral motion + yaw exposes crawling silhouette edges.
				var offset := float(frame) * 0.018
				camera.position = Vector3(offset, 4.5, -9.0 + offset * 0.5)
				camera.look_at(Vector3(-10.0 + offset * 0.3, 1.0, 10.0))
				for _settle: int in range(2): await tree.process_frame
				await RenderingServer.frame_post_draw
				var filename := "%s_%s_%02d.png" % [quality, variant, frame]
				var error := viewport.get_texture().get_image().save_png(OUTPUT + filename)
				if error != OK: report.errors.append(filename)
			report.captures.append({"quality":quality,"variant":variant,"frames":24,
				"scale":viewport.scaling_3d_scale,"msaa":viewport.msaa_3d})
	material.shader = saved_shader
	material.set_shader_parameter("wave_speed", saved_speed)
	viewport.queue_free()
	tree.paused = paused_before
	var file := FileAccess.open(OUTPUT + "motion_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	finished = true
	print("OCEAN_EDGE_RUNTIME " + JSON.stringify(report))
