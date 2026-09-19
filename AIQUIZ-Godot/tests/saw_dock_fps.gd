extends Node

func run(world: Node, cap: int) -> Dictionary:
	var gs: QuizGameState = QuizManager.game_state
	var saw: SawChaseController = world._saw_controller
	world.set_process(false)
	world.camera_controller.set_process(false)
	gs.game_state = Constants.STATE_PRELOADING
	gs.saw.reset()
	gs.p1_saw_killed = false
	gs.p2_saw_killed = false
	gs.player_y = 0.0
	gs.player2_y = 0.0
	saw._landing_spin_elapsed = 0.0
	saw.dock.begin()
	var old_cap := Engine.max_fps
	Engine.max_fps = cap
	var elapsed := 0.0
	var count := 0
	var early_spin := false
	var maximum_wheel_error := 0.0
	var ready_at := -1.0
	var spin_at := -1.0
	while elapsed < 17.4:
		await world.get_tree().process_frame
		var dt: float = world.get_process_delta_time()
		elapsed += dt
		saw.update_visual(gs,dt,elapsed >= 4.65,true)
		count += 1
		if saw.dock.is_deployed() and ready_at < 0.0: ready_at = elapsed
		if saw._landing_spin_elapsed > 0.0 and spin_at < 0.0: spin_at = elapsed
		early_spin = early_spin or (elapsed < saw.dock.READY_TIME and saw._landing_spin_elapsed > 0.0)
		var bone: int = saw.wheel_bones[0]
		var rest := saw.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var expected := rest * Quaternion(Vector3.UP,-saw.dock.wheel_distance()/SawChaseState.WHEEL_RADIUS)
		maximum_wheel_error = maxf(maximum_wheel_error,expected.angle_to(saw.skeleton.get_bone_pose_rotation(bone)))
	var full_speed: float = smoothstep(0.0,SawChaseState.SPINUP_SECONDS,saw._landing_spin_elapsed)
	var result := {"cap":cap,"observed_fps":count/elapsed,"ready_at":ready_at,"spin_at":spin_at,"early_spin":early_spin,"wheel_error_radians":maximum_wheel_error,"full_speed":full_speed,"camera_returned":saw.dock.menu_framing_weight()==0.0,"ship_hidden":not saw.dock.ship.visible,"passed":not early_spin and ready_at >=6.2 and ready_at <6.35 and spin_at >=6.2 and spin_at <6.35 and maximum_wheel_error <.002 and full_speed >.999 and not saw.dock.ship.visible and saw.dock.menu_framing_weight()==0.0}
	FileAccess.open("res://artifacts/saw_vessel/revision2/fps_%d.json" % cap,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	Engine.max_fps = old_cap
	queue_free()
	return result
