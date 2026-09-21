extends Node

const OUT := "res://artifacts/seat_launch_rebuild/"
var failures: Array[String] = []
var checks: Dictionary = {}
var report: Dictionary = {}
var fps := 60
var label := "unit"
var full := false
var capture := false
var start_delay := 1.0
var scenario := "normal"
var mode := Constants.MODE_TEN
var players := 2
var frames: Array[Dictionary] = []
var pictures: Dictionary = {}
var elapsed := 0.0
var next_capture := 0.0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, key: String) -> void:
	checks[key] = bool(checks.get(key, true)) and ok
	if not ok and not failures.has(key): failures.append(key)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--full": full = true
		if arg == "--capture": capture = true
		if arg.begins_with("--fps="): fps = arg.get_slice("=",1).to_int()
		if arg.begins_with("--label="): label = arg.get_slice("=",1)
		if arg.begins_with("--delay="): start_delay = arg.get_slice("=",1).to_float()
		if arg.begins_with("--scenario="): scenario = arg.get_slice("=",1)
		if arg.begins_with("--players="): players = arg.get_slice("=",1).to_int()
		if arg == "--endless": mode = Constants.MODE_ENDLESS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+label))
	if full: await runtime()
	else: await unit()
	report.merge({"passed":failures.is_empty(),"failures":failures,"checks":checks,"fps":fps,"frames":frames,"pictures":pictures})
	FileAccess.open(OUT+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CHAIR_TRANSFER ",JSON.stringify({"passed":failures.is_empty(),"label":label,"failures":failures,"checks":checks.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)

func unit() -> void:
	var saw := SawChaseController.new()
	add_child(saw)
	saw.update_preview(0.0)
	var op := saw.operator_seat
	var t := op.seat_transfer
	check(op.skeleton.get_bone_count()==16,"plush rig retained")
	check(t.flight_root.is_ancestor_of(op.skeleton),"mascot belongs to flying chair")
	check(not t.flight_root.is_ancestor_of(op.controls.OP_Pedal_L),"pedals stay on fixed station")
	check(not t.flight_root.is_ancestor_of(op.controls.OP_Lever_R),"consoles stay on fixed station")
	check(t.harness.straps.size()==2 and t.harness.tips.size()==2,"two physical shoulder belts")
	check(not t.kit.find_child("SL_LapWebbing",true,false).visible,"old lap belt hidden")
	for amount in [0.0, .25, .5, .75, 1.0]:
		t._set_belt(amount)
		for i in 2:
			var side := 1.0 if i==0 else -1.0
			var tip: Node3D = t.harness.tips[i]
			check(tip.position.distance_to(t.harness.point(side,amount,1.0))<.0001,"metal tip follows paid out ribbon %.2f/%d"%[amount,i])
			if amount==1.0:
				check(tip.position.distance_to(t.harness.receivers[i].position)<.0001,"each tongue reaches seat base lock %d"%i)
			if amount==0.0:
				check(not t.harness.straps[i].visible and tip.position.y>2.1,"retracted into seat top %d"%i)
	t._set_belt(0.0)
	var rope = t.harness.ropes[0]
	var physics_samples := {}
	for rate in [30,60,120]:
		rope.reset()
		for frame in range(rate + 1): rope.seek(float(frame) / rate)
		physics_samples[rate] = rope.points.duplicate()
		check(rope.points[rope.COUNT].z > .25,"physical throw passes in front of head at %d"%rate)
	check(physics_samples[30] == physics_samples[60] and physics_samples[60] == physics_samples[120],"Verlet physics matches at 30 60 120 fps")
	rope.seek(1.1)
	var unperturbed: PackedVector3Array = rope.points.duplicate()
	rope.reset();rope.seek(1.0)
	rope.kick(12,Vector3(0,2.0,1.0));rope.seek(1.1)
	check(rope.points[12].distance_to(unperturbed[12]) > .005,"external impulse changes free belt trajectory")
	check(rope.points[18].distance_to(unperturbed[18]) > .0005,"impulse propagates through linked belt segments")
	rope.reset();rope.seek(1.94)
	check(not rope.locked,"free tip remains physical until latch")
	rope.seek(1.95)
	check(rope.locked and rope.lock_distance < .025,"receiver spring seats tongue before locking without large snap")
	check(rope.points[rope.COUNT].distance_to(rope.rest[rope.COUNT]) < .0001,"physical tongue pinned at seat lock")
	rope.seek(2.6)
	check(rope.points == rope.rest,"winch settles entire belt onto fitted body support")
	t._set_belt(0.0)
	check(op.station.find_children("OP_SeatFlightRoot","Node3D",true,false).size()==1 and op.station.find_children("*","Skeleton3D",true,false).size()==1,"one chair and one mascot only")
	t.begin_buckle();t.set_process(false);t.launch()
	check(t.phase==t.Phase.BUCKLING and not QuizManager.has_meta(SeatLaunchPresentation.HANDOFF),"ignition refuses unfastened belt")
	t.advance_departure(SeatLaunchPresentation.LATCH_TIME)
	check(t.latch_count==1 and t.belt_extension==1.0,"latch sound occurs at belt endpoint")
	var rate_samples := {}
	for rate in [30,60,120]:
		t.reset()
		op.apply_sample(SawOperatorPresentation.sample(6.2,4.0,0.0,0.0,true))
		var fixed := fixed_transforms(op)
		t.begin_buckle();t.set_process(false)
		for i in range(rate*3): t.advance_departure(1.0/rate)
		check(t.is_buckled() and t.latch_count==1,"one buckle at %d"%rate)
		var launch_frame := Engine.get_process_frames()
		t.launch()
		check(t.launch_frame==launch_frame and t.belt_extension>.999,"armed launch same frame at %d"%rate)
		for i in range(rate): t.advance_departure(1.0/rate)
		rate_samples[rate] = t.flight_root.position.y
		check(t.flight_root.global_position.distance_to(t.socket.global_position)>10,"chair actually leaves socket at %d"%rate)
		check(fixed_equal(fixed,op),"all fixed meshes stay at %d"%rate)
		t.begin_arrival()
		check(not t.flight_root.visible and op.station.visible,"only chair hidden while waiting at %d"%rate)
		t.advance_arrival(.5,false)
		check(t.phase==t.Phase.WAITING_SOCKET,"no arrival before dock at %d"%rate)
		for i in range(rate*4): t.advance_arrival(1.0/rate,true)
		check(t.phase==t.Phase.IDLE and t.flight_root.visible,"arrival finishes at %d"%rate)
		check(t.flight_root.global_position.distance_to(t.socket.global_position)<.001,"measured socket error below 1mm at %d"%rate)
		check(t.flight_root.global_basis.is_equal_approx(t.socket.global_basis),"socket orientation at %d"%rate)
		check(t.belt_extension==0.0 and t.effects.strength==0.0,"belt release and engine off at %d"%rate)
		check(fixed_equal(fixed,op),"fixed assembly unchanged after arrival at %d"%rate)
	check(absf(rate_samples[30]-rate_samples[60])<.001 and absf(rate_samples[120]-rate_samples[60])<.001,"flight independent of frame rate")
	for time in [.1,1.4,2.8,3.3]:
		t.reset();t.begin_buckle();t.set_process(false);t.advance_departure(time)
		if t.is_buckled(): t.launch()
		t.skip_departure()
		check(not t.flight_root.visible and op.station.visible,"departure skip %.1f"%time)
		t.reset()
		check(t.phase==t.Phase.IDLE and t.flight_root.visible,"cancel restores %.1f"%time)
	for time in [0.0,.8,1.95,2.3]:
		t.begin_arrival();t.advance_arrival(.001,true);t.advance_arrival(time,true);t.advance_arrival(.001,true,true)
		check(t.phase==t.Phase.IDLE and t.landing_error<.001,"arrival skip %.2f"%time)
	var gs := QuizManager.game_state
	gs.num_players=2;gs.mode=Constants.MODE_TEN;gs.is_replay=false
	check(SeatLaunchPresentation.eligible(gs),"local 2P ten eligible")
	gs.mode=Constants.MODE_ENDLESS
	check(SeatLaunchPresentation.eligible(gs),"local 2P endless eligible")
	check(not SeatLaunchPresentation.eligible(gs,true),"online excluded")
	gs.is_replay=true
	check(not SeatLaunchPresentation.eligible(gs),"replay excluded")
	gs.is_replay=false;gs.num_players=1
	check(not SeatLaunchPresentation.eligible(gs),"1P excluded")
	gs.num_players=2;gs.mode=Constants.MODE_TUTORIAL
	check(not SeatLaunchPresentation.eligible(gs),"tutorial excluded")
	gs.mode=Constants.MODE_TEN
	QuizManager.set_meta(SeatLaunchPresentation.HANDOFF,true)
	check(SeatLaunchPresentation.consume_handoff(gs,false,false),"handoff consumed once")
	check(not SeatLaunchPresentation.consume_handoff(gs,false,false),"handoff cannot replay")
	QuizManager.set_meta(SeatLaunchPresentation.HANDOFF,true)
	check(not SeatLaunchPresentation.consume_handoff(gs,false,true) and not QuizManager.has_meta(SeatLaunchPresentation.HANDOFF),"retry consumes stale handoff")
	report.rate_samples=rate_samples
	saw.queue_free()
	await get_tree().process_frame

func fixed_transforms(op: SawOperatorPresentation) -> Dictionary:
	var transforms := {}
	for node in op.station.find_children("*","Node3D",true,false):
		if node==op.seat_transfer.flight_root or op.seat_transfer.flight_root.is_ancestor_of(node): continue
		if node==op.seat_transfer.effects or op.seat_transfer.effects.is_ancestor_of(node): continue
		transforms[str(node.get_path())] = (node as Node3D).global_transform
	return transforms

func fixed_equal(reference: Dictionary, op: SawOperatorPresentation) -> bool:
	var current := fixed_transforms(op)
	if current.size()!=reference.size(): return false
	for path in reference:
		if not (reference[path] as Transform3D).is_equal_approx(current[path]): return false
	return true

func runtime() -> void:
	Engine.max_fps=fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.size=Vector2i(1280,720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode="OFFLINE";gs.num_players=players;gs.mode=mode;gs.menu_step=Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene==null: await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(start_delay).timeout
	# Selecting a different player count animates the existing config conveyor.
	# Its Start button is deliberately disabled until that selection settles.
	var ready_deadline := Time.get_ticks_msec()+5000
	while menu.config_conveyor!=null and menu.config_conveyor.is_moving() and Time.get_ticks_msec()<ready_deadline:
		await get_tree().process_frame
	var expected := SeatLaunchPresentation.eligible(gs)
	preview._menu_start_departure.menu_boost_launched.connect(func(): report.boost_frame=Engine.get_process_frames())
	menu.call("_on_start_pressed")
	menu.call("_on_start_pressed")
	check(menu._menu_exit_in_progress,"real Start accepted once")
	var start := Time.get_ticks_msec()
	var saw_launch := false
	var saw_landing := false
	var saw_loading := false
	var did_action := false
	var fixed := {}
	var max_socket_error := 0.0
	var ended_world: Node
	var route_completed := false
	while Time.get_ticks_msec()-start<60000:
		await RenderingServer.frame_post_draw
		elapsed=(Time.get_ticks_msec()-start)/1000.0
		var scene := get_tree().current_scene
		if scene==null: continue
		var t: SeatLaunchPresentation
		if scene==menu:
			t=preview._preview_saw.operator_seat.seat_transfer
			if t.phase==t.Phase.BUCKLING and fixed.is_empty(): fixed=fixed_transforms(t.operator)
			if t.phase==t.Phase.BUCKLING and t.elapsed>1.1: await picture("buckle")
			if t.phase==t.Phase.ARMED: await picture("latched")
			if t.phase==t.Phase.LAUNCHING:
				saw_launch=true
				check(preview._menu_start_departure._menu_boost_started,"real helicopter boost is simultaneous")
				check(t.launch_frame==int(report.get("boost_frame",-2)),"actual ignition frame matches helicopter event")
				check(t.belt_extension>.999,"belt stays closed during rocket flight")
				check(fixed_equal(fixed,t.operator),"station stays fixed during real launch")
				if t.elapsed>.18: await picture("launch")
				if t.elapsed>.65: await picture("ascent")
			var cancel_now := (scenario=="cancel" and t.phase==t.Phase.BUCKLING and t.elapsed>.7) or (scenario=="cancel_flight" and t.phase==t.Phase.LAUNCHING and t.elapsed>.3)
			if cancel_now and not did_action:
				preview.cancel_game_start_departure();did_action=true
				check(t.phase==t.Phase.IDLE and not QuizManager.has_meta(SeatLaunchPresentation.HANDOFF),"real cancellation resets chair and token")
				await picture("cancelled")
				break
			var skip_now := (scenario=="skip" and elapsed>.15) or (scenario=="skip_buckle" and t.phase==t.Phase.BUCKLING and t.elapsed>1.0) or (scenario=="skip_flight" and t.phase==t.Phase.LAUNCHING and t.elapsed>.3)
			if skip_now and preview.is_game_start_departure_active() and not did_action:
				preview.skip_game_start_departure();did_action=true
				check(t.phase==t.Phase.AWAY,"early real skip before buckle")
			if expected:
				check(preview._viewport.get_camera_3d()==preview._preview_camera,"existing menu wide camera retained")
		elif scene.scene_file_path=="res://scenes/game_world.tscn":
			var saw: SawChaseController=scene._saw_controller
			if saw.operator_seat!=null:
				t=saw.operator_seat.seat_transfer
				if t.is_arriving(): check(scene.is_start_presentation_locked(),"start stays locked until chair settled")
				if t.phase==t.Phase.WAITING_SOCKET:
					check(not t.flight_root.visible and t.operator.station.visible,"fixed station visible before chair arrival")
				if t.phase==t.Phase.LANDING:
					saw_landing=true
					check(not SceneTransition.is_transitioning() and saw.dock.is_deployed(),"visible landing waits for loading and socket")
					if t.elapsed>.65: await picture("descent")
					if t.elapsed>1.45: await picture("braking")
					if scenario=="arrival_skip" and not did_action:
						saw.finish_entrance();did_action=true
						check(t.phase==t.Phase.IDLE,"arrival skip settles chair")
				if t.phase==t.Phase.SETTLING: await picture("contact")
				if t.phase==t.Phase.UNBUCKLING: await picture("release")
				if t.phase==t.Phase.IDLE and saw_landing:
					max_socket_error=maxf(max_socket_error,t.flight_root.global_position.distance_to(t.socket.global_position))
					check(max_socket_error<.001,"real landing socket error below 1mm")
					check(not QuizManager.has_meta(SeatLaunchPresentation.HANDOFF),"token removed on world entry")
					if not scene.is_start_presentation_locked():
						await picture("landed")
						check(t.belt_extension==0.0,"unbuckled before gameplay")
						ended_world=scene
						route_completed=true
						break
				if not expected:
					check(t.phase==t.Phase.IDLE,"excluded mode has no chair animation")
			if not expected and not scene.is_start_presentation_locked():
				route_completed=true
				break
		if SceneTransition.is_fully_covered():
			saw_loading=true
			await picture("loading")
		if capture and elapsed>=next_capture:
			var img:=get_viewport().get_texture().get_image()
			img.resize(960,540)
			var path:=OUT+label+"/%05d.jpg"%frames.size()
			img.save_jpg(path,.88)
			frames.append({"path":path,"time":elapsed,"phase":t.phase if t!=null else -1})
			next_capture=elapsed+1.0/12.0
	if scenario=="retry" and is_instance_valid(ended_world):
		gs._game_over("Chair transfer retry acceptance")
		await get_tree().create_timer(.2).timeout
		ended_world.get_node("GameplayHUD")._retry_game()
		var deadline := Time.get_ticks_msec()+20000
		var retried := false
		while Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
			var retry_world := get_tree().current_scene
			if retry_world==null or retry_world==ended_world or SceneTransition.is_transitioning(): continue
			var retry_saw: SawChaseController=retry_world._saw_controller
			var rt := retry_saw.operator_seat.seat_transfer
			check(rt.phase==rt.Phase.IDLE and rt.flight_root.visible and rt.belt_extension==0.0,"actual retry begins seated and unbuckled")
			check(retry_saw.dock.is_deployed() and not retry_world.is_start_presentation_locked(),"actual retry has deployed dock and released input")
			await picture("retry_seated")
			retried=true
			break
		check(retried,"actual retry completes")
	if not scenario.begins_with("cancel"):
		check(route_completed,"real route finishes before timeout")
		check(saw_loading,"existing loading screen observed")
		if expected:
			check(saw_launch or scenario.begins_with("skip"),"real chair launch observed")
			check(saw_landing,"real chair landing observed")
			check(pictures.has("landed"),"real route reaches settled chair and unlock")
		else: check(not saw_launch and not saw_landing,"excluded mode departure unchanged")
	report.socket_error=max_socket_error
	report.scenario=scenario
	report.runtime_seconds=elapsed

func picture(key: String) -> void:
	if pictures.has(key): return
	var path := OUT+label+"/"+key+".png"
	pictures[key]={"path":path,"time":elapsed}
	get_viewport().get_texture().get_image().save_png(path)
