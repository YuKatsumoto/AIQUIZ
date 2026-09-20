extends Node

var failures: Array[String] = []
var checks := 0
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
	for drive in [-1.0,0.0,1.0]:
		for lift_speed in [-6.0,0.0,6.0]:
			op.apply_sample(SawOperatorPresentation.sample(7,5,drive,2,true,lift_speed))
			for error in op.contact_errors.values():check(float(error)<.01,"signed travel/lift control contact")
	op.apply_sample(SawOperatorPresentation.sample(7,5,0,2,true,0))
	check(absf(op.controls.OP_Lever_R.rotation.x)<.001,"height hold returns lift lever to neutral")
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
	var held:=op.last_sample.duplicate()
	saw.update_visual(gs,0,true)
	check(op.last_sample==held,"pause holds controls")
	gs.game_state=Constants.STATE_GAME_OVER
	saw.update_visual(gs,.1,true)
	check(op.last_sample==held,"result holds controls")
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
	var seek_pose:=op.last_sample.duplicate()
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
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"max_contact_error":max_error,"worst_contact":worst,"max_hand_step_30fps":max_step,"blade_clearance":clearance,"fps_samples":fps_samples}
	FileAccess.open("res://artifacts/saw_operator/acceptance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_ACCEPTANCE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
