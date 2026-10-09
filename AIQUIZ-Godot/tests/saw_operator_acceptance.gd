extends Node

var failures: Array[String] = []
var checks := 0
var operating := {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and not failures.has(label):failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var saw := SawChaseController.new()
	add_child(saw)
	saw.update_preview(0.0)
	var op := saw.operator_seat
	check(op!=null and op.skeleton.get_bone_count()==16,"existing plush rig")
	check(op.find_children("*","CollisionObject3D",true,false).is_empty(),"no new collision objects")
	check(op.console!=null and op.station.find_child("OP_Toggle",true,false)==null,"v3 console replaces the v2 controls")
	for key in ["OP_Lever_L","OP_Lever_R","OP_Key","OP_Guard","OP_Start","OP_Horn","OP_Dial","OP_Needle_RPM","OP_Beacon","OP_SeatFlightRoot","OP_MountFrame"]:
		check(op.controls.has(key),"control present "+key)
	check(op._lamps.size()>=26,"lamps, LED bars and beacon have their own materials")
	var max_error := 0.0
	var worst := {}
	var fps_samples := {}
	var max_step := 0.0
	for fps in [30,60,120]:
		var previous := Vector3.ZERO
		for i in range(fps*8+1):
			var t: float = float(i)/fps
			var value := SawOperatorPresentation.sample(6.2+t,t,smoothstep(4.0,5.0,t),2.0*smoothstep(5.0,6.0,t),true)
			op.apply_sample(value)
			for key in op.contact_errors:
				if float(op.contact_errors[key])>max_error:
					max_error=float(op.contact_errors[key]);worst={"fps":fps,"time":t,"contact":key}
			var hand := op.skeleton.get_bone_global_pose(op.bones["DEF-hand.R"]).origin
			if i>0:max_step=maxf(max_step,previous.distance_to(hand))
			previous=hand
			if i==fps*2:fps_samples[fps]=str(op.skeleton.get_bone_global_pose(op.bones["DEF-hand.R"]))
	check(max_error<.01,"all control contacts below 1cm")
	check(max_step<.075,"continuous hand motion through start sequence")
	check(fps_samples[30]==fps_samples[60] and fps_samples[60]==fps_samples[120],"pose independent of render rate")
	# Start routine reaches each control.
	for probe in [[.40,"L","key"],[.45,"R","guard"],[.90,"R","start"],[5.0,"L","grip"],[5.0,"R","grip"]]:
		op.apply_sample(SawOperatorPresentation.sample(7,probe[0],0,0,true))
		var target: Vector3 = op._anchor(probe[1],probe[2])
		var palm: Vector3 = op.skeleton.to_global(op.skeleton.get_bone_global_pose(op.bones["DEF-hand."+probe[1]]).origin+Vector3(0,0,.1))
		check(palm.distance_to(target)<.01,"start routine reaches %s at %.2fs"%[probe[2],probe[0]])
	op.apply_sample(SawOperatorPresentation.sample(7,.93,0,0,true))
	check(op.controls.OP_Start.position.y<(op.rest.OP_Start as Transform3D).origin.y-.008,"START is slammed down")
	op.apply_sample(SawOperatorPresentation.sample(7,5,0,0,true))
	check(absf(op.controls.OP_Key.rotation.y+1.2)<.01 and absf(op.controls.OP_Guard.rotation.x+1.75)<.01,"key on and guard open while running")
	check(float(op.last_sample.lamp_Power)>.99 and float(op.last_sample.lamp_Saw)>.99 and float(op.last_sample.beacon)>.99,"power, saw lamp and beacon on at full speed")
	op.apply_sample(SawOperatorPresentation.sample(7,0,0,0,true))
	check(float(op.last_sample.lamp_Power)==0.0 and float(op.last_sample.key)==0.0,"console dark before the start")
	for drive in [-1.0,0.0,1.0]:
		for lift_speed in [-6.0,0.0,6.0]:
			op.apply_sample(SawOperatorPresentation.sample(7,5,drive,2,true,lift_speed))
			for error in op.contact_errors.values():check(float(error)<.01,"signed travel/lift control contact")
	op.apply_sample(SawOperatorPresentation.sample(7,5,1,2,true,0))
	check(op.controls.OP_Lever_L.rotation.z<-.2,"forward travel tilts DRIVE toward the travel side")
	op.apply_sample(SawOperatorPresentation.sample(7,5,0,2,true,6))
	check(op.controls.OP_Lever_R.rotation.x<-.2,"raising pulls BLADE back")
	op.apply_sample(SawOperatorPresentation.sample(7,5,0,2,true,0))
	check(absf(op.controls.OP_Lever_R.rotation.x)<.001,"height hold returns lift lever to neutral")
	operating_pass(op)
	catch_and_stop(op)
	stow_pass(op)
	# Compare actual mesh vertices against the full vertical blade sweep.
	op.rotation=Vector3(0,SawOperatorPresentation.FACING_YAW,0)
	op.position=SawOperatorPresentation.MOUNT
	op.apply_sample(SawOperatorPresentation.sample(7,5,1,2,true))
	check(op.station.global_position.x>12.1 and absf(op.station.global_position.z-saw.global_position.z)<.01,"seat attached at left end, not behind the blade row")
	check((op.global_basis*Vector3.BACK).dot(Vector3.LEFT)>.999,"operator faces across the row to the right")
	check(absf(saw.to_local(op.station.to_global(Vector3(0,.97,0))).y-.341726)<.001,"deployed deck floor aligns with resting blade underside")
	var clearance := INF
	for child in op.find_children("*","MeshInstance3D",true,false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.skin != null:continue
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p := saw.to_local(mesh_node.to_global(vertex))
				if p.y<.30 or p.y>5.5:continue
				clearance=minf(clearance,Vector2(p.x-10.5,p.z).length()-1.45)
	check(clearance>.015,"station clears left blade full vertical sweep")
	op.apply_sample(SawOperatorPresentation.sample(0,0,0,0,false))
	var stowed_top := 0.0
	var stowed_z := 0.0
	var stowed_x := 0.0
	for child in op.find_children("*","MeshInstance3D",true,false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.skin != null:
			# RenderingServer's conservative skinned AABB includes unused pose space.
			# Evaluate the actual occupied mesh with the same skin palette instead.
			for surface in mesh_node.mesh.get_surface_count():
				var arrays := mesh_node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
				var influences: int=indices.size()/vertices.size()
				for v in vertices.size():
					var posed:=Vector3.ZERO
					for influence in influences:
						var at:=v*influences+influence
						var bind:=indices[at]
						var bone:=mesh_node.skin.get_bind_bone(bind)
						if bone<0:bone=op.skeleton.find_bone(mesh_node.skin.get_bind_name(bind))
						posed+=(op.skeleton.get_bone_global_pose(bone)*mesh_node.skin.get_bind_pose(bind)*vertices[v])*weights[at]
					var point:=saw.to_local(op.skeleton.to_global(posed))
					stowed_top=maxf(stowed_top,point.y)
					stowed_x=maxf(stowed_x,absf(point.x))
					stowed_z=maxf(stowed_z,absf(point.z))
			continue
		var bounds := mesh_node.get_aabb()
		for corner in range(8):
			var point := saw.to_local(mesh_node.to_global(bounds.get_endpoint(corner)))
			stowed_top=maxf(stowed_top,point.y)
			stowed_x=maxf(stowed_x,absf(point.x))
			stowed_z=maxf(stowed_z,absf(point.z))
	check(stowed_x<12.5 and stowed_z<1.85,"occupied station fits existing lift footprint")
	var dock := SawDockPresentation.new();add_child(dock);dock.setup(false,true)
	var cover := dock.machinery.find_child("VSL_COVER",true,false) as Node3D
	print("OPERATOR_STOWED_BOUNDS ",stowed_top," ",stowed_x," ",stowed_z)
	check(cover==null and dock.machinery.find_child("VSL_SLAT_00",true,false)==null,"lift shutter assembly removed")
	dock.queue_free()
	var gs:=QuizGameState.new()
	gs.mode=Constants.MODE_TEN;gs.num_players=2;gs.saw_transport_enabled=true
	gs.game_state=Constants.STATE_PRELOADING;gs.saw.enabled=true
	saw._preview_elapsed=0
	saw.update_visual(gs,.1,false)
	check(op.last_sample.spin==0,"waiting cannot start blade controls")
	saw.update_visual(gs,.1,true)
	check(is_equal_approx(op.last_sample.spin,.1),"start follows landing clock")
	gs.game_state=Constants.STATE_PLAYING
	gs.saw.elapsed=3;gs.saw.wheel_distance=5
	saw.update_visual(gs,.1,true)
	var held:=op.last_sample.duplicate(true)
	saw.update_visual(gs,0,true)
	check(op.last_sample==held,"pause holds controls")
	gs.game_state=Constants.STATE_GAME_OVER
	saw.update_visual(gs,.1,true)
	check(op.last_sample==held,"result holds controls")
	# A blade catch from the recorded death timer drives the celebration.
	gs.game_state=Constants.STATE_PLAYING
	gs.p1_saw_killed=true;gs.game_over_timer=.42
	saw.update_visual(gs,.1,true)
	check(float(op.last_sample.catch)>.99 and float(op.last_sample.horn)>.5,"live catch honks the horn")
	gs.p1_saw_killed=false;gs.game_over_timer=0.0
	# Replay scrubbing derives velocity from recorded neighboring frames.
	var recorder:=ReplayRecorder.new()
	gs.game_state=Constants.STATE_PLAYING
	recorder.start_recording(gs)
	for i in range(6):
		gs.play_time=i;gs.saw.elapsed=i;gs.saw.wheel_distance=i*2.0
		gs.player_x=10.5;gs.player_z=gs.saw.local_z+gs.world_scroll_z;gs.player_y=float([0,1,2,2,1,0][i])
		recorder.capture(gs)
	var player:=ReplayPlayer.new();player.setup(recorder);gs.is_replay=true
	player.seek(2.0);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	var seek_pose:=op.last_sample.duplicate(true)
	player.seek(3.0);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	player.seek(2.0);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	check(op.last_sample==seek_pose,"seek order independent replay controls")
	player.seek(1.5);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	check(float(op.last_sample.lift_motion)>0,"replay ascent operates lift lever up")
	player.seek(2.5);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	check(absf(float(op.last_sample.lift_motion))<.001,"replay height hold neutral")
	player.seek(3.5);player.apply_to_game_state(gs);saw.update_visual(gs,0)
	check(float(op.last_sample.lift_motion)<0,"replay descent operates lift lever down")
	check(recorder.fields_per_frame==34,"recording format unchanged")
	for count in [1,2]:
		for mode in [Constants.MODE_TEN,Constants.MODE_ENDLESS,Constants.MODE_COOP,Constants.MODE_TUTORIAL]:
			gs.is_replay=false;gs.num_players=count;gs.mode=mode
			saw.update_visual(gs)
			check(saw.visible==(count==2 and mode in [Constants.MODE_TEN,Constants.MODE_ENDLESS]),"mode visibility %s/%d"%[mode,count])
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"max_contact_error":max_error,"worst_contact":worst,"max_hand_step_30fps":max_step,"blade_clearance":clearance,"stowed":[stowed_top,stowed_x,stowed_z],"fps_samples":fps_samples,"operating_pass":operating}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/saw_operator/v3"))
	FileAccess.open("res://artifacts/saw_operator/v3/acceptance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_ACCEPTANCE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

## Waiting vignettes, the start, running checks: continuous, reachable, varied.
func operating_pass(op: SawOperatorPresentation) -> void:
	var head_key: int = op.bones["DEF-head"]
	var hips_key: int = op.bones["DEF-hips"]
	var lever := Vector2(INF,-INF)
	var head_yaw := Vector2(INF,-INF)
	var hips_moved := 0.0
	var max_turn := 0.0
	var max_error := 0.0
	var max_step := 0.0
	var kinds := {}
	var dial_seen := false
	var raised := {"L":0.0,"R":0.0}
	var feet_lifted := 0.0
	var previous_head := Basis()
	var previous_hand := {"L":Vector3.ZERO,"R":Vector3.ZERO}
	var frames: Array[Dictionary] = []
	# 6 vignettes on the waiting clock, then a start that freezes it mid-slot.
	var wait := SawOperatorPresentation.IDLE_SLOT*6.0+2.0
	for i in range(int(30*wait)): frames.append(SawOperatorPresentation.sample(7,0,0,1,true,0,i/30.0))
	for i in range(30*40): frames.append(SawOperatorPresentation.sample(7,i/30.0,smoothstep(3.3,4.0,i/30.0),1,true,0,wait if i<24 else 0.0))
	for i in frames.size():
		var value: Dictionary = frames[i]
		op.apply_sample(value)
		for error in op.contact_errors.values(): max_error = maxf(max_error,float(error))
		var head := op.skeleton.get_bone_global_pose(head_key).basis.orthonormalized()
		if int(value.idle_kind) >= 0: kinds[int(value.idle_kind)] = true
		for side in ["L","R"]:
			var hand := op.skeleton.get_bone_global_pose(op.bones["DEF-hand."+side]).origin
			var shoulder := op.skeleton.get_bone_global_pose(op.bones["DEF-upper_arm."+side]).origin
			raised[side] = maxf(raised[side], hand.y-shoulder.y)
			if i > 0: max_step = maxf(max_step,(previous_hand[side] as Vector3).distance_to(hand))
			previous_hand[side] = hand
		feet_lifted = maxf(feet_lifted,(value.foot_L as Vector3).y)
		if i > 0:
			var turn := (previous_head.inverse()*head).get_rotation_quaternion().get_angle()
			if turn > max_turn:
				max_turn = turn
				operating.worst_head_frame = {"spin":value.spin,"idle":value.idle}
		previous_head = head
		var yaw := atan2(head.z.x,head.z.z)
		head_yaw = Vector2(minf(head_yaw.x,yaw),maxf(head_yaw.y,yaw))
		hips_moved = maxf(hips_moved,(op.skeleton.get_bone_global_pose(hips_key).basis.orthonormalized()*op.skeleton.get_bone_global_rest(hips_key).basis.orthonormalized().inverse()).get_rotation_quaternion().get_angle())
		if float(value.spin) > 4.0:
			var angle: float = op.controls.OP_Lever_L.rotation.z
			lever = Vector2(minf(lever.x,angle),maxf(lever.y,angle))
		if float((value.hand_R.mix as Dictionary).get("dial",0.0)) > .999:
			dial_seen = true
			check(absf(op.controls.OP_Lever_R.rotation.x)<.001,"dial check leaves held lift lever neutral")
			check(float(op.contact_errors.hand_R)<.01,"running dial check reaches the dial")
	operating.merge({"lever_range":lever.y-lever.x,"head_yaw_range":head_yaw.y-head_yaw.x,"body_turn_max":hips_moved,"max_head_turn_per_frame":max_turn,"max_contact_error":max_error,"max_hand_step":max_step,"idle_kinds":kinds.keys(),"hands_above_shoulder":raised,"feet_lifted":feet_lifted},true)
	check(kinds.size()==6,"all six waiting vignettes play")
	check(raised.L>.05 and raised.R>.05,"stretch/wave/fist pump raise the hands above the shoulders")
	check(feet_lifted>.04,"feet leave the pedals while waiting")
	check(lever.y-lever.x > .03,"travel lever keeps correcting at steady speed")
	check(head_yaw.y-head_yaw.x > .3,"head checks gauges and track")
	check(hips_moved > .03,"whole plush body leans with the controls")
	check(dial_seen,"right hand trims the dial while running")
	check(max_error < .01,"operating pass keeps every hand and foot target below 1cm")
	check(max_turn < .06,"head motion continuous at 30fps")
	check(max_step < .075,"hand motion continuous through waiting, start and checks")
	# Idle clock only drives the waiting pose: replays and held frames stay unaffected.
	check(SawOperatorPresentation.sample(7,5,1,1,true,0,3.0)==SawOperatorPresentation.sample(7,5,1,1,true,0,0.0),"idle clock ignored once running")

## Menu stow on the stow clock: stow, rest racked (vignettes), deploy, and a mid-way reversal.
func stow_pass(op: SawOperatorPresentation) -> void:
	var length := 12.4167
	var frames: Array[Dictionary] = []
	var p := 0.0
	var rate := 0.0
	var idle := -1.0
	# Stow with a reversal at p=5 and back, then the full stow, 12 s racked, then deploy.
	var script := [[1.0,5.0],[-1.0,2.0],[1.0,length],[0.0,12.0],[-1.0,0.0]]
	var step := 1.3/30.0
	for leg: Array in script:
		var want: float = leg[0]
		var guard := 0
		while guard < 2000:
			guard += 1
			rate = move_toward(rate, want, .15)
			if want == 0.0:
				idle = maxf(idle,0.0) + 1.0/30.0
				if idle >= float(leg[1]): break
			else:
				p = clampf(p + rate*step, 0.0, length)
				if p >= length: idle = maxf(idle,0.0)
				elif p <= length - SawOperatorPresentation.STOW_REST_FADE: idle = -1.0
				if (want > 0.0 and p >= float(leg[1])) or (want < 0.0 and p <= float(leg[1])): break
			frames.append(SawOperatorPresentation.sample(7,20,0,0,true,0,0,{"rpm":1.0-smoothstep(0.0,1.3,p),"stow":p,"stow_length":length,"stow_rate":rate,"stow_idle":idle}))
	frames.append(SawOperatorPresentation.sample(7,20,0,0,true,0,0,{"rpm":1.0,"stow":0.0,"stow_length":length,"stow_rate":0.0,"stow_idle":-1.0}))
	var max_error := 0.0
	var max_step := 0.0
	var max_turn := 0.0
	var pulled := 0.0
	var pushed := 0.0
	var covered := false
	var kinds := {}
	var beacon := 0.0
	var previous := {"L":Vector3.ZERO,"R":Vector3.ZERO}
	var previous_head := Basis()
	for i in frames.size():
		var value: Dictionary = frames[i]
		op.apply_sample(value)
		for error in op.contact_errors.values(): max_error = maxf(max_error,float(error))
		for side in ["L","R"]:
			var hand := op.skeleton.get_bone_global_pose(op.bones["DEF-hand."+side]).origin
			if i > 0: max_step = maxf(max_step,(previous[side] as Vector3).distance_to(hand))
			previous[side] = hand
		var head := op.skeleton.get_bone_global_pose(op.bones["DEF-head"]).basis.orthonormalized()
		var turn := (previous_head.inverse()*head).get_rotation_quaternion().get_angle() if i > 0 else 0.0
		if turn > max_turn:
			max_turn = turn
			operating.stow_worst_turn = {"frame":i,"p":float(value.stow_rest),"idle_kind":value.idle_kind,"look":value.look,"head_pitch":value.head_pitch}
		previous_head = head
		var lever: float = op.controls.OP_Lever_R.rotation.x
		pulled = minf(pulled, lever)
		pushed = maxf(pushed, lever)
		if float((value.hand_L.mix as Dictionary).get("cover",0.0)) > .999 and float(op.contact_errors.hand_L) < .01: covered = true
		if int(value.idle_kind) >= 0: kinds[int(value.idle_kind)] = true
		beacon = maxf(beacon, float(value.beacon))
	check(pulled < -.2 and pushed > .2,"stow pulls BLADE back, deploy pushes it forward")
	check(covered,"operator covers his head while the rack passes overhead")
	check(kinds.size() >= 2,"waiting vignettes play while racked")
	check(beacon > .9,"beacon runs while the rack moves")
	check(max_error < .01,"stow targets below 1cm")
	check(max_step < .075,"stow hand motion continuous through reversal, rest and deploy")
	check(max_turn < .06,"stow head motion continuous at 30fps")
	var last: Dictionary = frames[-1]
	check(float(last.stow) == 0.0 and float(last.stow_rest) == 0.0,"deployed again: the stow program has handed back")
	operating.stow = {"frames":frames.size(),"max_error":max_error,"max_step":max_step,"max_turn":max_turn,"lever":[pulled,pushed],"kinds":kinds.keys()}

## Catch celebration then the shutdown routine, as one continuous 30fps sequence.
func catch_and_stop(op: SawOperatorPresentation) -> void:
	var max_error := 0.0
	var max_step := 0.0
	var honk := 0.0
	var last_horn := 0.0
	var honks := 0
	var horn_reached := false
	var previous := Vector3.ZERO
	op.apply_sample(SawOperatorPresentation.sample(7,20,.8,1,true))
	for i in range(30*6):
		var t := i/30.0
		var extra := {"catch": t if t < 3.0 else -1.0}
		if t >= 3.0: extra.merge({"stop": minf(t-3.0,2.0), "rpm": 1.0-smoothstep(0.0,2.0,t-3.0)})
		var value := SawOperatorPresentation.sample(7,20+t,.8*(1.0-smoothstep(3.0,5.0,t)),1,true,0,0,extra)
		op.apply_sample(value)
		for error in op.contact_errors.values(): max_error = maxf(max_error,float(error))
		var hand := op.skeleton.get_bone_global_pose(op.bones["DEF-hand.L"]).origin
		if i > 0: max_step = maxf(max_step,previous.distance_to(hand))
		previous = hand
		if last_horn < .6 and float(value.horn) >= .6: honks += 1
		last_horn = float(value.horn)
		honk = maxf(honk,last_horn)
		if float((value.hand_L.mix as Dictionary).get("horn",0.0)) > .999 and float(op.contact_errors.hand_L) < .01: horn_reached = true
	check(horn_reached and honk > .8,"catch: left hand presses the horn")
	check(honks==2,"catch: two honks")
	check(max_error < .01,"catch/stop targets below 1cm")
	check(max_step < .075,"catch/stop hand motion continuous")
	check(absf(op.controls.OP_Key.rotation.y)<.001 and absf(op.controls.OP_Guard.rotation.x)<.001,"stop: key off and guard closed")
	check(float(op.last_sample.lamp_Power)==0.0 and float(op.last_sample.beacon)==0.0,"stop: console goes dark")
	operating.catch_stop = {"max_error":max_error,"max_step":max_step,"horn_count":honks}
