extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var stage:=Node3D.new();add_child(stage)
	var saw:=SawChaseController.new();stage.add_child(saw)
	var gs:=QuizGameState.new()
	gs.num_players=2;gs.mode=Constants.MODE_TEN;gs.saw_transport_enabled=true
	gs.saw.enabled=true;gs.game_state=Constants.STATE_PLAYING
	saw.update_visual(gs)
	var camera:=Camera3D.new();stage.add_child(camera)
	var focus:=saw.operator_seat.station.global_position+Vector3(0,1.45,0)
	camera.position=focus+Vector3(-3.2,1.8,3.8)
	camera.look_at(focus);camera.fov=39
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.09,.13,.18)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.72,.81,.95)
	env.environment.ambient_light_energy=.65;stage.add_child(env)
	var sun:=DirectionalLight3D.new();stage.add_child(sun)
	sun.rotation_degrees=Vector3(-40,-35,0);sun.light_energy=1.8
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var reports: Array=[]
	for fps in [30,60,120]:
		Engine.max_fps=fps
		var folder:="res://artifacts/saw_operator/fps%d/"%fps
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var count:=0
		var stamps: Array[float]=[]
		var max_error:=0.0
		var lift_range:=Vector2.ZERO
		var max_lift:=0.0
		var start:=Time.get_ticks_usec()
		var last:=start
		var records: Array=[]
		var captured:=-1.0
		while Time.get_ticks_usec()-start<10000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			var dt:=(now-last)/1000000.0;last=now
			var t:=(now-start)/1000000.0
			gs.saw.elapsed=t;gs.saw.wheel_distance=maxf(0,t-4.0)*gs.tuning.saw_max_speed
			gs.player_x=10.5;gs.player_z=gs.saw.local_z+gs.world_scroll_z;gs.player_y=2*(smoothstep(4.5,5.5,t)-smoothstep(6.5,7.5,t))
			saw.update_visual(gs,dt,false)
			var motion:float=saw.operator_seat.last_sample.lift_motion
			lift_range.x=minf(lift_range.x,motion);lift_range.y=maxf(lift_range.y,motion)
			max_lift=maxf(max_lift,float(saw.operator_seat.last_sample.lift))
			if t>=8.0:
				# The only negative travel is menu recovery. Exercise the identical pose evaluator.
				saw.operator_seat.apply_sample(SawOperatorPresentation.sample(7,t,-smoothstep(8.0,8.5,t)*(1-smoothstep(9.0,9.5,t)),0,true,0))
			for v in saw.operator_seat.contact_errors.values():max_error=maxf(max_error,float(v))
			if t>.2:stamps.append(dt)
			count+=1
			if fps==60 and t-captured>=1.0/15.0:
				captured=t
				await RenderingServer.frame_post_draw
				var file:="frame_%04d.jpg"%records.size()
				get_viewport().get_texture().get_image().save_jpg(folder+file,.96)
				records.append({"file":file,"time":t})
			elif count==fps*3:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder+"contact.png")
		stamps.sort()
		var median_fps:=1.0/stamps[stamps.size()/2]
		reports.append({"cap":fps,"median_fps":median_fps,"frames":count,"max_contact_error":max_error,"lift_motion_min":lift_range.x,"lift_motion_max":lift_range.y,"max_lift":max_lift,"passed":max_error<.01 and lift_range.x<-.1 and lift_range.y>.1 and max_lift>.9})
		if fps==60:
			var manifest:=FileAccess.open(folder+"frames.txt",FileAccess.WRITE)
			for i in records.size():
				manifest.store_line("file '%s'"%records[i].file)
				manifest.store_line("duration %.6f"%(float(records[i+1].time)-float(records[i].time) if i+1<records.size() else 1.0/15.0))
	FileAccess.open("res://artifacts/saw_operator/runtime_fps.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	print("OPERATOR_RENDER_FPS ",JSON.stringify(reports))
	get_tree().quit()
