extends Node

## Main-menu harbour city (assets/aiquiz_menu_stage): the moved city is built in the
## menu world and the menu camera frames it. The launch deck ("island" with the LED
## screen and the AIQUIZ sign) is NOT built any more (AiquizMenuStage.BUILD_LAUNCH_DECK;
## the LED programme plays on the goal stand scoreboard), so none of it may be in the
## menu world. The rebuilt waterfront in front of the towers is there (its facades on
## the backdrop shader, the Ferris wheel above the runway walls), the Ferris wheel turns
## (the rim about its axle, the gondolas carried with their hang points and kept
## upright), and the rendered menu is captured from the menu camera, a few views of the
## conveyor and the empty sea where the deck stood, two telephoto views of the
## waterfront and two of the wheel 3 s apart.
## Results: res://artifacts/aiquiz_menu_stage/game/ (report.json and PNGs).

const OUT := "res://artifacts/aiquiz_menu_stage/game/"
const LAYOUT := "res://assets/aiquiz_menu_stage/aiquiz_menu_stage_layout.json"

var errors: Array[String] = []
var checks: Dictionary = {}
var capture := true


func _ready() -> void:
	call_deferred("run")


func check(name: String, ok: bool, detail: Variant = "") -> void:
	checks[name] = {"pass": ok, "detail": str(detail)}
	if not ok:
		errors.append("%s: %s" % [name, str(detail)])


func run() -> void:
	capture = not ("--no-capture" in OS.get_cmdline_user_args())
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Skip the service vessel's first-visit entrance so the menu camera settles at once.
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var preview: MenuWallBackgroundPreview = null
	for i in 1500:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.get("_menu_wall_preview"):
			preview = scene._menu_wall_preview
			if preview.get_camera() and not SceneTransition.is_transitioning():
				break
	if preview == null:
		errors.append("menu ready timeout")
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var stage := preview.get_menu_stage()
	check("harbor stage enabled", AiquizMenuStage.enabled())
	check("menu city built", stage != null and stage.city != null)
	if stage == null or stage.city == null:
		finish()
		return
	# The launch deck (island, LED screen, sign, speakers, palms) is gone from the menu world.
	check("launch deck switched off", not AiquizMenuStage.BUILD_LAUNCH_DECK and stage.stage_root == null)
	check("no HarborLaunch node", stage.find_child("HarborLaunch", true, false) == null)
	check("no LED programme in the menu", stage.led_program == null and get_tree().root.find_children("MenuLedProgram", "", true, false).is_empty())
	var deck_meshes := []
	for node: Node in get_tree().current_scene.find_children("AMS_*", "MeshInstance3D", true, false):
		if String(node.name) in ["AMS_LaunchDeck", "AMS_Backdrop", "AMS_LedScreen", "AMS_Sign", "AMS_DeckTowers", "AMS_Palms",
				"AMS_PalmLeaves", "AMS_Pennants"]:
			deck_meshes.append(String(node.name))
	check("no launch deck mesh anywhere (deck, backdrop, LED screen, sign, towers, palms)", deck_meshes.is_empty(), deck_meshes)
	# The game's lighthouse, islands, skyline and sailboats lie behind the menu camera
	# (customize turns it round): the menu builds none of them, only the shared night glow.
	var backdrop := preview.get_stage_environment().find_child("StadiumBackdrop", true, false)
	check("menu has no stadium scenery behind the camera", backdrop != null and backdrop.find_child("Scenery", true, false) == null)
	# The city.
	var city := stage.city
	check("city built", city != null)
	if city != null:
		var pos: Array = layout["city"]["position"]
		var expected := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		check("city position", city.global_position.distance_to(expected) < 0.05, city.global_position)
		check("city yaw", absf(rad_to_deg(city.global_rotation.y) - wrapf(float(layout["city"]["yaw_deg"]), -180.0, 180.0)) < 0.05,
			rad_to_deg(city.global_rotation.y))
	# The menu camera: harbor pitch, and the city's towers inside the frame.
	var camera := preview.get_camera()
	var expected_rot := AiquizMenuStage.camera_rotation_degrees()
	check("camera rotation", camera.rotation_degrees.distance_to(expected_rot) < 0.05, camera.rotation_degrees)
	if city != null:
		var centre := city.global_transform * Vector3(0.0, 120.0, 100.0)
		var screen := camera.unproject_position(centre)
		var size := preview.get_shared_viewport().get_visible_rect().size
		check("city centre in frame", not camera.is_position_behind(centre) and screen.x > 0.0 and screen.x < size.x and screen.y > 0.0 and screen.y < size.y,
			"%s of %s" % [screen, size])
	var vsize := preview.get_shared_viewport().get_visible_rect().size
	# The rebuilt waterfront in front of the towers (aiquiz_menu_city.glb).
	if city != null:
		var city_meshes := []
		for node: Node in city.find_children("*", "MeshInstance3D", true, false):
			city_meshes.append(String(node.name))
		for expected: String in ["AMS_City", "AMS_CityQuay", "AMS_CityPromenade", "AMS_CityWaterfront", "AMS_FerrisWheelStand",
				"AMS_FerrisWheelRim", "AMS_CityBoats"]:
			check("city mesh %s" % expected, expected in city_meshes, city_meshes)
		var facades := 0
		var facades_ok := true
		for node: Node in city.find_children("*", "MeshInstance3D", true, false):
			var geometry := node as MeshInstance3D
			for surface in geometry.mesh.get_surface_count():
				var mat := geometry.get_active_material(surface)
				if mat != null and mat.resource_name.begins_with("AMS_Facade"):
					facades += 1
					facades_ok = facades_ok and mat is ShaderMaterial and bool((mat as ShaderMaterial).get_shader_parameter("use_facade"))
		check("waterfront facades use the backdrop shader", facades >= 3 and facades_ok, facades)
		# Blender city-local (x, y, z) is glTF / Godot local (x, z, -y).
		var waterfront: Dictionary = layout["city"]["waterfront"]
		var wheel_c: Array = waterfront.get("wheel_axle_local", waterfront["wheel_center_local"])
		var wheel := city.global_transform * Vector3(float(wheel_c[0]), float(wheel_c[2]), -float(wheel_c[1]))
		var wheel_screen := camera.unproject_position(wheel)
		check("Ferris wheel above the runway walls, right of the middle", not camera.is_position_behind(wheel)
			and wheel_screen.x > vsize.x * 0.5 and wheel_screen.x < vsize.x
			and wheel_screen.y > vsize.y * 0.12 and wheel_screen.y < vsize.y * 0.4, wheel_screen / vsize)
		await _ferris_wheel_checks(stage, waterfront)
	if capture:
		await _captures(preview, camera, layout)
		await _customize_captures(preview)
	finish()


## The Ferris wheel turns: its rim and gondolas are separate nodes of the city, the rim
## turns about the axle at the set speed and direction, and over 1 s every gondola's
## origin (its hang point) moves exactly like the matching point of the rim, stays on
## the hang circle, and the gondola stays upright (within its sway).
func _ferris_wheel_checks(stage: AiquizMenuStage, waterfront: Dictionary) -> void:
	var city := stage.city
	var rim := stage.ferris_rim
	var gondolas := stage.ferris_gondolas
	check("Ferris wheel rim is a node of the city", rim != null and rim.get_parent() == city, rim)
	check("Ferris gondolas", gondolas.size() == int(waterfront.get("wheel_gondolas", 24)), gondolas.size())
	if rim == null or gondolas.is_empty():
		return
	var axle_l: Array = waterfront.get("wheel_axle_local", waterfront["wheel_center_local"])
	var axle := Vector3(float(axle_l[0]), float(axle_l[2]), -float(axle_l[1]))
	var axis := stage.ferris_wheel_axis()
	var hang_r := float(waterfront.get("wheel_hang_radius", waterfront.get("wheel_radius", 30.0)))
	check("Ferris rim origin on the axle", rim.position.distance_to(axle) < 0.05 and stage.ferris_wheel_axle().distance_to(axle) < 0.01,
		rim.position - axle)
	var rim0 := rim.transform
	var pos0 := PackedVector3Array()
	for g: Node3D in gondolas:
		pos0.append(g.position)
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(1.0).timeout
	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
	var turn := rim.transform * rim0.affine_inverse()
	var ref := pos0[0] - axle
	var angle := ref.signed_angle_to(turn.basis * ref, axis)
	var expected := -TAU * elapsed / AiquizMenuStage.FERRIS_WHEEL_PERIOD
	check("Ferris rim turns about its axle", (turn * axle).distance_to(axle) < 0.02 and (turn.basis * axis).distance_to(axis) < 0.001,
		turn * axle - axle)
	check("Ferris rim speed and direction (clockwise from the camera)",
		signf(angle) == signf(expected) and absf(angle - expected) < absf(expected) * 0.5,
		"%.2f deg in %.2f s, expected %.2f" % [rad_to_deg(angle), elapsed, rad_to_deg(expected)])
	var follow := 0.0
	var radius_error := 0.0
	var tilt := 0.0
	var plane := Plane(axis, axle)
	for i: int in gondolas.size():
		var g := gondolas[i]
		follow = maxf(follow, (turn * pos0[i]).distance_to(g.position))
		radius_error = maxf(radius_error, absf(plane.project(g.position).distance_to(axle) - hang_r))
		tilt = maxf(tilt, rad_to_deg(g.global_transform.basis.y.normalized().angle_to(Vector3.UP)))
	check("Ferris gondolas follow their hang points on the rim", follow < 0.05, "%.3f m" % follow)
	check("Ferris gondolas on the hang circle", radius_error < 0.05, "%.3f m" % radius_error)
	check("Ferris gondolas stay upright", tilt <= AiquizMenuStage.GONDOLA_SWAY_DEG + 0.1, "%.2f deg" % tilt)


## The embedded customize screen shares the menu world and camera: every tab still
## frames the runners, and leaving it returns the camera to the harbor pose.
func _customize_captures(preview: MenuWallBackgroundPreview) -> void:
	var menu := get_tree().current_scene
	if not menu.has_method("_open_embedded_customize"):
		return
	menu.call("_open_embedded_customize")
	await get_tree().create_timer(2.5).timeout
	var customize := menu.find_child("CustomizeSettings", true, false)
	if customize == null:
		check("customize opened", false, "CustomizeSettings not found")
		return
	for section: Array in [[0, "wall_speed"], [1, "skin"], [2, "emote"]]:
		if customize.has_method("_set_section"):
			customize.call("_set_section", section[0])
		await get_tree().create_timer(3.5 if section[0] == 0 else 2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "customize_%s.png" % section[1]))
	if customize.has_method("_on_back_pressed"):
		customize.call("_on_back_pressed")
	elif menu.has_method("_close_embedded_customize"):
		menu.call("_close_embedded_customize")
	await get_tree().create_timer(2.0).timeout
	var camera := preview.get_camera()
	check("camera back at the harbor pose after customize",
		camera.rotation_degrees.distance_to(AiquizMenuStage.camera_rotation_degrees()) < 0.1, camera.rotation_degrees)


func _captures(preview: MenuWallBackgroundPreview, camera: Camera3D, layout: Dictionary) -> void:
	var vp := preview.get_shared_viewport()
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "menu_camera.png"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "menu_with_ui.png"))
	var saved := camera.global_transform
	var saved_fov := camera.fov
	preview.set_process(false)
	# Where the launch deck stood (the layout still records it) is open sea now.
	var deck: Array = layout["launch_deck"]["center"]
	var deck_c := Vector3(float(deck[0]), float(deck[1]), float(deck[2]))
	var views := {
		"deck_site": [deck_c + (Vector3(-48.0, 0.0, 57.15).normalized() * 30.0) + Vector3(0.0, 4.0, 0.0), deck_c, 40.0],
		# The bare conveyor side (the walkways, piles and light towers were removed).
		"runway_edge": [Vector3(-26.0, 3.5, -4.0), Vector3(-12.0, -2.0, -45.0), 45.0],
		"aerial": [Vector3(-60.0, 45.0, 60.0), Vector3(10.0, 0.0, -40.0), 45.0],
		# Turned round, as in the customize screen: open sea and sky, no game scenery.
		"turned_round": [saved.origin, saved.origin + Vector3(0.0, 0.0, 500.0), 60.0],
	}
	# The waterfront in front of the towers, from the menu camera's own position (telephoto).
	var city := preview.get_menu_stage().city
	if city != null:
		for key: String in ["waterfront_zoom", "waterfront_left"]:
			var local := Vector3(40.0, 22.0, -236.0) if key == "waterfront_zoom" else Vector3(400.0, 20.0, -236.0)
			views[key] = [saved.origin, city.global_transform * local, 5.0]
	for key: String in views:
		var v: Array = views[key]
		camera.global_position = v[0]
		camera.look_at(v[1], Vector3.UP)
		camera.fov = v[2]
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
	# The Ferris wheel from the menu camera's position (telephoto), twice 3 s apart: the
	# rim and the gondolas should have moved about 12 degrees between the two.
	var stage := preview.get_menu_stage()
	if city != null and stage.ferris_rim != null:
		camera.global_position = saved.origin
		camera.look_at(city.global_transform * (stage.ferris_wheel_axle() + Vector3(0.0, -3.0, 0.0)), Vector3.UP)
		camera.fov = 6.5
		for key: String in ["ferris_wheel_a", "ferris_wheel_b"]:
			if key == "ferris_wheel_b":
				await get_tree().create_timer(3.0).timeout
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
	camera.global_transform = saved
	camera.fov = saved_fov
	preview.set_process(true)


func finish() -> void:
	var report := {"checks": checks, "errors": errors, "pass": errors.is_empty()}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("MENU_HARBOR_STAGE ", JSON.stringify({"pass": errors.is_empty(), "errors": errors, "checks": checks.size()}))
	get_tree().quit(0 if errors.is_empty() else 1)
