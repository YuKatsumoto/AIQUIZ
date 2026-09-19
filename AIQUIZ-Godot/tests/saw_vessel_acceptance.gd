extends Node

## Explicit runtime worker; never loaded by the production game.
var failures: Array[String] = []
var checks: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func run_fps(world: Node) -> void:
	var results: Array = []
	for cap in [24,30,60,120]:
		var worker = load("res://tests/saw_dock_fps.gd").new()
		get_tree().root.add_child(worker)
		var result: Dictionary = await worker.run(world,cap)
		results.append(result)
		print("SAW_VESSEL_FPS ",cap," ",result.passed)
	FileAccess.open("res://artifacts/saw_vessel/revision2/fps_suite.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	queue_free()

func run_mechanics(world: Node) -> Dictionary:
	world.set_process(false)
	world.camera_controller.set_process(false)
	var gs: QuizGameState = QuizManager.game_state
	var saw: SawChaseController = world._saw_controller
	var dock := saw.dock
	gs.game_state = Constants.STATE_PRELOADING
	gs.saw.reset()
	gs.saw.enabled = true
	saw._landing_spin_elapsed = 0.0
	dock.begin()
	var maximum_contact_error := 0.0
	for time in [0.0,.6,1.5,2.25,2.5,3.3,4.42,5.2]:
		dock.elapsed = time
		dock.total_elapsed = time
		saw.update_visual(gs,0.0,false,true)
		# Before transfer, each actual skeleton hub stays exactly 0.44m above
		# the moving lift datum despite sea motion. Compare in lift coordinates.
		if time <= 4.42:
			for bone in saw.wheel_bones:
				var hub := saw.skeleton.global_transform * saw.skeleton.get_bone_global_pose(bone).origin
				var local_hub := dock.lift.to_local(hub)
				maximum_contact_error = maxf(maximum_contact_error,absf(local_hub.y-.44))
		check(saw._landing_spin_elapsed == 0.0,"no spin while shipping %.2f" % time)
	check(maximum_contact_error < .001,"four wheel hubs remain on moving platform")
	var maximum_stationary_error := 0.0
	var stroke := 0.0
	for interval in [[2.35,4.20],[6.55,8.40]]:
		dock.elapsed = interval[0]
		dock.apply_pose()
		var stationary_pose := dock.ship.global_transform
		var initial_lift := dock.lift.global_position.y
		for step in range(61):
			dock.elapsed = lerpf(interval[0],interval[1],step/60.0)
			dock.apply_pose()
			maximum_stationary_error = maxf(maximum_stationary_error,dock.ship.global_position.distance_to(stationary_pose.origin))
			check(dock.ship.global_transform.is_equal_approx(stationary_pose),"stationary vessel during lift %.3f" % dock.elapsed)
		stroke = absf(dock.lift.global_position.y-initial_lift)
		check(is_equal_approx(stroke,4.8),"actual lift stroke %.2f to %.2f" % [interval[0],interval[1]])
	dock.elapsed = 4.42
	saw.update_visual(gs,0.0,false,true)
	var rail_error := 0.0
	for bridge in dock.bridges:
		var point := bridge.to_global(Vector3(ConveyorRails.CENTER_X if bridge.name.ends_with("R") else -ConveyorRails.CENTER_X,.26,-1.3))
		rail_error = maxf(rail_error,absf(point.z - StageConstants.FLOOR_BACK_Z))
		rail_error = maxf(rail_error,absf(point.y - (StageConstants.FLOOR_TOP_Y+.26)))
	check(rail_error < .001,"bridge ends match existing conveyor rails")
	dock.elapsed = 3.3
	dock.apply_pose()
	dock.update_audio(true,0.0,saw.global_position)
	check(dock._engine.playing and dock._servo.playing,"vessel and hydraulic SFX active")
	dock.update_audio(false,0.0,saw.global_position)
	check(not dock._engine.playing and not dock._servo.playing,"hidden or paused audio stops")
	var pose := dock.ship.global_transform
	var time := dock.elapsed
	get_tree().paused = true
	await get_tree().create_timer(.2,true).timeout
	check(dock.elapsed == time and dock.ship.global_transform.is_equal_approx(pose),"pause freezes ship and lift")
	get_tree().paused = false
	dock.elapsed = 6.2
	saw.update_visual(gs,0.0,true,true)
	var position := saw.position
	dock.advance(5.0)
	saw.update_visual(gs,0.0,true,true)
	check(saw.position.is_equal_approx(position) and dock.ship.position.z > 1.0,"ship departs without carriage")
	check(saw.basis.is_equal_approx(Basis.IDENTITY),"handoff clears sea tilt")
	dock.restore_deployed()
	check(dock.has_departed() and not dock.ship.visible and dock.framing_weight()==0.0,"skip hides vessel and restores camera")
	check(dock.wheel_distance()==0.0,"retry has no shipping wheel offset")
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"maximum_contact_error_m":maximum_contact_error,"bridge_error_m":rail_error,"maximum_stationary_error_m":maximum_stationary_error,"lift_stroke_m":stroke}
	FileAccess.open("res://artifacts/saw_vessel/revision2/mechanics.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	return result

func wait_scene(path: String, previous: int) -> Node:
	var until := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.get_instance_id() != previous and scene.scene_file_path == path and not SceneTransition.is_transitioning():
			return scene
	check(false,"scene transition timeout " + path)
	return null

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/saw_vessel/revision2/" + label + ".png")

func run_navigation() -> void:
	var world := get_tree().current_scene
	var dock: SawDockPresentation = world._saw_controller.dock
	check(world._helicopter_arrival_director == null,"real retry skips helicopter")
	check(not dock.animated and not dock.ship.visible and dock.is_deployed(),"real retry hides ship and deploys carriage")
	check(is_equal_approx(world._saw_controller.position.z,SawChaseState.INITIAL_Z) and dock.framing_weight()==0.0,"real retry retains carriage position and normal camera")
	await capture("retry")
	var previous := world.get_instance_id()
	world.get_node("GameplayHUD")._return_to_main_menu()
	var menu := await wait_scene("res://ui/main_menu.tscn",previous)
	if menu == null:
		finish_navigation()
		return
	var preview: Node = menu._menu_wall_preview
	var saw: SawChaseController = preview._preview_saw
	check(not saw.dock.animated and not saw.dock.ship.visible,"real menu return skips vessel entrance")
	check(saw.dock.is_deployed() and is_equal_approx(saw.position.z,SawDockPresentation.MENU_Z),"real menu return keeps carriage deployed")
	await capture("menu_return")
	# Force a fresh first-visit presentation without changing session metadata.
	saw.dock.begin()
	saw._preview_elapsed = 0.0
	await get_tree().create_timer(.1).timeout
	preview.set_customize_walls_hidden(true)
	await get_tree().process_frame
	var hold_time := saw.dock.elapsed
	await get_tree().create_timer(.2).timeout
	check(saw.dock.elapsed == hold_time and not saw.visible and not saw.dock._engine.playing,"customize-hidden freezes ship and sound")
	preview.set_customize_walls_hidden(false)
	var container: CanvasItem = preview._viewport.get_parent()
	container.hide()
	await get_tree().process_frame
	hold_time = saw.dock.elapsed
	await get_tree().create_timer(.2).timeout
	check(saw.dock.elapsed == hold_time and not saw.dock._engine.playing,"hidden viewport freezes ship and sound")
	container.show()
	await get_tree().create_timer(.06).timeout
	check(saw.dock.elapsed > hold_time,"showing viewport resumes entrance")
	previous = menu.get_instance_id()
	var pressed_at := saw.dock.elapsed
	menu._on_start_pressed()
	check(pressed_at < .5 and menu._menu_exit_in_progress,"immediate Start accepted while vessel approaches")
	world = await wait_scene("res://scenes/game_world.tscn",previous)
	if world == null:
		finish_navigation()
		return
	dock = world._saw_controller.dock
	var until := Time.get_ticks_msec() + 20000
	while dock.elapsed < .7 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(dock.elapsed > 0.0 and not dock.is_deployed(),"immediate Start enters normal game vessel sequence")
	world._toggle_pause()
	hold_time = dock.elapsed
	var hold_pose := dock.ship.global_transform
	var audio_time := dock._engine.get_playback_position()
	await get_tree().create_timer(.3,true).timeout
	check(dock.elapsed == hold_time and dock.ship.global_transform.is_equal_approx(hold_pose),"actual pause menu freezes moving vessel")
	check(absf(dock._engine.get_playback_position()-audio_time)<.04,"actual pause menu freezes engine playback")
	await capture("paused_approach")
	world._toggle_pause()
	await get_tree().create_timer(.2).timeout
	check(dock.elapsed > hold_time,"resume continues from paused vessel pose")
	until = Time.get_ticks_msec() + 12000
	while dock.elapsed < 9.5 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(dock.is_deployed() and not dock.has_departed() and world._helicopter_arrival_director.have_players_touched_down(),"players land and carriage deploys while ship is still departing")
	check(world._saw_controller._landing_spin_elapsed>0.0,"immediate Start still gates spin on landing")
	await capture("immediate_start")
	previous = world.get_instance_id()
	world.get_node("GameplayHUD")._retry_game()
	world = await wait_scene("res://scenes/game_world.tscn",previous)
	if world != null:
		dock = world._saw_controller.dock
		check(not dock.animated and not dock.ship.visible and world._helicopter_arrival_director==null,"retry during departure restores deployed state")
	finish_navigation()

func finish_navigation() -> void:
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures}
	FileAccess.open("res://artifacts/saw_vessel/revision2/navigation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SAW_VESSEL_NAVIGATION ",result)
	queue_free()
