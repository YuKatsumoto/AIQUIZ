extends Node3D

## Visual + performance preview of ShaftDescent (docs/sudden_death_underground.md ch.5).
## Renders the spec's shots for each graphics quality into artifacts/sudden_death/shaft/:
##   b             shot B: 3.5 m above the deck edge, 55 deg down over two stand-in players
##   b_wide        shot B framed wider: 4.2 m up near the back wall, 38 deg down
##   c             shot C: straight down from above the players' heads
##   entry_closed  camera above the surface mouth, iris closed, beacons + daylight on
##   entry_half    iris half folded (blades swinging down into the wall pocket)
##   entry_open    iris open, deck 7 m down, daylight on
##   wall          close-up of the concrete around a lamp (material check)
##   sign          a depth sign passing the deck (text from set_depth_signs)
##   up            from the deck 18 m down: the daylight disk of the opening above
##   arrival       from the cistern: walls clipped at the ceiling top, deck emerging below
## `perf` measures cruise frame times at 1280x720 (vsync off) for the given qualities.
## User args: quality=low,balanced  shots=b,c  perf  noshots

const OUTPUT := "res://artifacts/sudden_death/shaft/"
const SHAFT_SCENE := preload("res://scenes/sudden_death/shaft_descent.tscn")
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
const SETTLE_FRAMES := 30
const PERF_FRAMES := 360

var shaft: ShaftDescent
var camera: Camera3D
var sun: DirectionalLight3D
var surface: MeshInstance3D
var ceiling: MeshInstance3D
var day_env: Environment
var report := {"shots": [], "perf": [], "errors": []}
var qualities: PackedStringArray = ["low", "balanced", "high", "ultra"]
var shots: PackedStringArray = ["b", "b_wide", "c", "wall", "sign", "entry_closed", "entry_half", "entry_open", "up", "arrival"]
var do_perf := false
var cruise_scroll := 37.3


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			qualities = arg.trim_prefix("quality=").split(",")
		elif arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=").split(",")
		elif arg == "perf":
			do_perf = true
		elif arg == "noshots":
			shots = PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_window().size = Vector2i(1280, 720)
	_build_stage()
	await _run()
	var file := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SHAFT_PREVIEW " + JSON.stringify(report))
	get_tree().quit(0 if report.errors.is_empty() else 1)


func _build_stage() -> void:
	var started := Time.get_ticks_usec()
	shaft = SHAFT_SCENE.instantiate() as ShaftDescent
	add_child(shaft)
	report["instantiate_msec"] = float(Time.get_ticks_usec() - started) / 1000.0
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	add_child(sun)
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	day_env = Environment.new()
	day_env.background_mode = Environment.BG_SKY
	day_env.sky = sky
	day_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	day_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	day_env.glow_enabled = true
	# Stand-ins owned by the test: two pads with blocky players on the deck, the surface floor
	# around the mouth and the cistern ceiling slab under the shaft.
	for i in range(2):
		var side := 1.0 if i == 0 else -1.0
		var color := P1_COLOR if i == 0 else P2_COLOR
		var pad := _pad(color)
		pad.position = Vector3(side * SuddenDeathLayout.PAD_X, 0.0, 0.0)
		shaft.get_deck().add_child(pad)
		var player := _player(color)
		player.position = Vector3(side * SuddenDeathLayout.PAD_X, SuddenDeathLayout.PAD_TOP, 0.0)
		shaft.get_deck().add_child(player)
	var referee := _player(Color(0.92, 0.92, 0.9), 0.8)
	referee.position = SuddenDeathLayout.REFEREE_OFFSET
	shaft.get_deck().add_child(referee)
	surface = _annulus("SurfaceFloor", 7.6, 45.0, 0.0, -0.3, Color(0.42, 0.43, 0.45))
	shaft.add_child(surface)
	ceiling = _annulus("CisternCeiling", 7.0, 40.0, 0.0, -1.0, Color(0.20, 0.20, 0.19))
	shaft.add_child(ceiling)


func _material(color: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	parent.add_child(mi)


func _player(color: Color, scale_factor := 1.0) -> Node3D:
	var root := Node3D.new()
	var dark := color.darkened(0.35)
	_box(root, Vector3(0.28, 0.72, 0.3), Vector3(-0.2, 0.36, 0.0), dark)
	_box(root, Vector3(0.28, 0.72, 0.3), Vector3(0.2, 0.36, 0.0), dark)
	_box(root, Vector3(0.82, 0.78, 0.5), Vector3(0.0, 1.11, 0.0), color)
	_box(root, Vector3(0.22, 0.66, 0.24), Vector3(-0.55, 1.1, 0.0), color)
	_box(root, Vector3(0.22, 0.66, 0.24), Vector3(0.55, 1.1, 0.0), color)
	_box(root, Vector3(0.74, 0.62, 0.66), Vector3(0.0, 1.82, 0.0), Color(0.96, 0.86, 0.72))
	root.scale = Vector3.ONE * scale_factor
	return root


func _pad(color: Color) -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.08
	cyl.bottom_radius = 1.08
	cyl.height = 0.07
	base.mesh = cyl
	base.material_override = _material(Color(0.3, 0.3, 0.32), 0.4)
	base.position.y = 0.035
	root.add_child(base)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.06
	ring.mesh = torus
	ring.material_override = _material(color, 0.35)
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position.y = 0.07
	root.add_child(ring)
	return root


func _annulus(node_name: String, r_in: float, r_out: float, top: float, bottom: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 96
	for i in range(segs):
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var i0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var i1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var up := Vector3(0.0, top, 0.0)
		var dn := Vector3(0.0, bottom, 0.0)
		# top (facing up) and bottom (facing down)
		for tri: Array in [[i0 + up, o0 + up, o1 + up], [i0 + up, o1 + up, i1 + up]]:
			for v: Vector3 in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		for tri: Array in [[i0 + dn, o1 + dn, o0 + dn], [i0 + dn, i1 + dn, o1 + dn]]:
			for v: Vector3 in tri:
				st.set_normal(Vector3.DOWN)
				st.add_vertex(v)
		# inner rim (facing the axis)
		var n := -Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		for tri: Array in [[i0 + up, i0 + dn, i1 + dn], [i0 + up, i1 + dn, i1 + up]]:
			for v: Vector3 in tri:
				st.set_normal(n)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	var m := _material(color, 0.85)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.visible = false
	return mi


func _look(from: Vector3, target: Vector3, up := Vector3.UP) -> void:
	camera.global_position = shaft.to_global(from)
	camera.look_at(shaft.to_global(target), up)


func _settle(frames: int) -> void:
	for i in range(frames):
		await RenderingServer.frame_post_draw


func _capture(shot_name: String, quality: String) -> void:
	await _settle(SETTLE_FRAMES)
	var image := get_viewport().get_texture().get_image()
	var path := OUTPUT + "%s_%s.png" % [shot_name, quality]
	image.save_png(path)
	report.shots.append({"shot": shot_name, "quality": quality, "image": path, "snapshot": shaft.get_debug_snapshot()})


func _reset_shaft() -> void:
	shaft.set_mouth(false, 0.0, 0.0)
	shaft.set_beacons(false)
	shaft.set_daylight(0.0)
	shaft.set_lamps_enabled(true)
	shaft.set_deck_visible(true)
	shaft.set_clip(ShaftDescent.FAR, -ShaftDescent.FAR)
	shaft.set_depth_signs([])
	surface.visible = false
	ceiling.visible = false
	sun.visible = false


func _shot(shot_name: String, quality: String, env_shaft: Environment) -> void:
	_reset_shaft()
	camera.environment = env_shaft
	camera.fov = 50.0
	match shot_name:
		"b":
			shaft.set_motion_speed(10.0)
			shaft.set_view(0.0, cruise_scroll)
			shaft.set_depth_signs([{"y": -7.5, "text": "−30m"}])
			var pitch := deg_to_rad(55.0)
			var from := Vector3(0.0, 3.5, -SuddenDeathLayout.DECK_RADIUS)
			_look(from, from + Vector3(0.0, -sin(pitch), cos(pitch)))
		"b_wide":
			shaft.set_motion_speed(10.0)
			shaft.set_view(0.0, cruise_scroll + 2.2)
			shaft.set_depth_signs([{"y": -5.0, "text": "−30m"}])
			var pitch := deg_to_rad(38.0)
			var from := Vector3(0.0, 4.2, -6.2)
			_look(from, from + Vector3(0.0, -sin(pitch), cos(pitch)))
		"c":
			shaft.set_motion_speed(6.0)
			shaft.set_view(0.0, cruise_scroll + 14.6)
			shaft.set_depth_signs([{"y": -11.0, "text": "−50m"}])
			camera.fov = 62.0
			_look(Vector3(0.0, 7.0, -0.4), Vector3(0.0, -10.0, -0.39), Vector3.FORWARD)
		"entry_closed":
			camera.environment = day_env
			sun.visible = true
			surface.visible = true
			shaft.set_motion_speed(0.0)
			shaft.set_clip(0.0, -ShaftDescent.FAR)
			shaft.set_view(0.0, 0.0)
			shaft.set_mouth(true, 0.0, 0.0)
			shaft.set_beacons(true)
			shaft.set_daylight(1.0)
			_look(Vector3(0.0, 8.5, -14.0), Vector3(0.0, 0.5, 0.0))
		"entry_half":
			camera.environment = day_env
			sun.visible = true
			surface.visible = true
			shaft.set_motion_speed(0.0)
			shaft.set_clip(0.0, -ShaftDescent.FAR)
			shaft.set_view(-0.4, 0.0)
			shaft.set_mouth(true, 0.0, 0.45)
			shaft.set_beacons(true)
			shaft.set_daylight(1.0)
			_look(Vector3(0.0, 8.5, -14.0), Vector3(0.0, -1.0, 0.0))
		"entry_open":
			camera.environment = day_env
			sun.visible = true
			surface.visible = true
			shaft.set_motion_speed(4.0)
			shaft.set_clip(0.0, -ShaftDescent.FAR)
			shaft.set_view(-7.0, 0.0)
			shaft.set_mouth(true, 0.0, 1.0)
			shaft.set_beacons(true)
			shaft.set_daylight(1.0)
			_look(Vector3(0.0, 9.0, -12.5), Vector3(0.0, -6.0, 0.5))
		"wall":
			shaft.set_motion_speed(0.0)
			shaft.set_view(-6.0, 0.0)
			camera.fov = 55.0
			var a := deg_to_rad(65.0)
			_look(Vector3(cos(a) * 2.6, 3.3, sin(a) * 2.6), Vector3(cos(deg_to_rad(45.0)) * 7.0, 2.4, sin(deg_to_rad(45.0)) * 7.0))
		"sign":
			shaft.set_motion_speed(10.0)
			shaft.set_view(0.0, cruise_scroll)
			shaft.set_depth_signs([{"y": 2.4, "text": "−40m"}, {"y": -27.6, "text": "−70m"}])
			_look(Vector3(0.0, 2.6, 1.5), Vector3(0.0, 2.3, 7.0))
		"up":
			shaft.set_motion_speed(10.0)
			shaft.set_clip(0.0, -ShaftDescent.FAR)
			shaft.set_view(-18.0, 0.0)
			shaft.set_mouth(true, 0.0, 1.0)
			shaft.set_beacons(true)
			shaft.set_daylight(0.7)
			camera.fov = 60.0
			_look(Vector3(0.0, -16.2, -4.0), Vector3(0.0, 0.0, 1.5))
		"arrival":
			ceiling.visible = true
			ceiling.position.y = -40.0
			shaft.set_motion_speed(2.0)
			shaft.set_clip(ShaftDescent.FAR, -40.0)
			shaft.set_view(-43.5, cruise_scroll + 3.1)
			_look(Vector3(0.0, -56.0, -15.0), Vector3(0.0, -40.0, 0.0))
	await _capture(shot_name, quality)


func _run() -> void:
	for quality: String in qualities:
		var started := Time.get_ticks_usec()
		shaft.setup(quality)
		var setup_msec := float(Time.get_ticks_usec() - started) / 1000.0
		GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
		var env_shaft := ShaftDescent.make_environment(quality)
		for shot_name: String in shots:
			await _shot(shot_name, quality, env_shaft)
		if do_perf:
			await _perf(quality, env_shaft)
		report["setup_msec_" + quality] = setup_msec


func _perf(quality: String, env_shaft: Environment) -> void:
	_reset_shaft()
	camera.environment = env_shaft
	camera.fov = 50.0
	var pitch := deg_to_rad(55.0)
	var from := Vector3(0.0, 3.5, -SuddenDeathLayout.DECK_RADIUS)
	shaft.set_motion_speed(10.0)
	shaft.set_view(0.0, cruise_scroll)
	_look(from, from + Vector3(0.0, -sin(pitch), cos(pitch)))
	var prewarm := shaft.begin_render_prewarm(camera)
	var compiles_before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
	await _settle(4)
	shaft.end_render_prewarm()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _settle(60)
	var compiles_mid := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
	var frame: PackedFloat32Array = []
	var gpu: PackedFloat32Array = []
	var cpu: PackedFloat32Array = []
	var scroll := cruise_scroll
	var last := Time.get_ticks_usec()
	for i in range(PERF_FRAMES):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		scroll += 10.0 * dt / 1000.0
		shaft.set_view(0.0, scroll)
		frame.append(dt)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var spikes: Array = []
	for i in range(frame.size()):
		if frame[i] > 8.0:
			spikes.append({"frame": i, "ms": snappedf(frame[i], 0.01), "gpu": snappedf(gpu[i], 0.01), "cpu": snappedf(cpu[i], 0.01)})
	var entry := {
		"quality": quality,
		"prewarm": prewarm,
		"draw_pipeline_compiles_after_prewarm": compiles_mid - compiles_before,
		"draw_pipeline_compiles_during_cruise": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW) - compiles_mid,
		"spikes_over_8ms": spikes,
		"frames": PERF_FRAMES,
		"frame_ms": _stats(frame),
		"gpu_ms": _stats(gpu),
		"render_cpu_ms": _stats(cpu),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
		"texture_mem_mb": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0,
	}
	report.perf.append(entry)


func _stats(values: PackedFloat32Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		return {}
	return {
		"p50": snappedf(sorted[n / 2], 0.01),
		"p95": snappedf(sorted[mini(n - 1, int(n * 0.95))], 0.01),
		"p99": snappedf(sorted[mini(n - 1, int(n * 0.99))], 0.01),
		"max": snappedf(sorted[n - 1], 0.01),
	}
