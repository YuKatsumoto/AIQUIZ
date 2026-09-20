extends Node
var errors: Array[String]=[]
var checks: Dictionary={}

func _ready() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/saw_operator/"+label+".png")

func ready_world() -> void:
	for i in range(1200):
		await get_tree().process_frame
		var world=get_tree().current_scene
		if world and world.name=="GameWorld" and world._saw_controller.operator_seat and not SceneTransition.is_transitioning():return
	errors.append("game world readiness timeout")

func run() -> void:
	Engine.max_fps=60
	var gs:=QuizManager.game_state
	QuizManager.provider.llm_mode="OFFLINE";gs.llm_mode="OFFLINE"
	gs.mode=Constants.MODE_TEN;gs.num_players=2;gs.start_game();gs.skip_start_helicopter_arrival=true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	await ready_world()
	if not errors.is_empty():finish();return
	var world=get_tree().current_scene
	var saw: SawChaseController=world._saw_controller
	checks.skip_deployed=saw.dock.is_deployed() and saw.operator_seat.last_sample.extension==1.0
	await capture("lifecycle_skip")
	var before:=saw.operator_seat.last_sample.duplicate()
	gs._game_over("Operator presentation acceptance")
	await get_tree().create_timer(1.0).timeout
	checks.result_holds=before==saw.operator_seat.last_sample
	await capture("lifecycle_result")
	world.get_node("GameplayHUD")._retry_game()
	await get_tree().create_timer(2.0).timeout
	await ready_world()
	world=get_tree().current_scene;saw=world._saw_controller
	checks.retry_deployed=saw.dock.is_deployed() and saw.operator_seat.last_sample.extension==1.0
	await capture("lifecycle_retry")
	var recorder:=ReplayRecorder.new()
	gs.game_state=Constants.STATE_PLAYING;gs.saw.enabled=true
	recorder.start_recording(gs)
	for i in range(61):
		gs.play_time=i/10.0;gs.saw.elapsed=i/10.0;gs.saw.wheel_distance=i*.2;gs.saw.local_z=-10.85+i*.1
		recorder.capture(gs)
	recorder.stop_recording(gs)
	QuizManager.set_meta("last_replay",recorder)
	get_tree().change_scene_to_file("res://scenes/replay_scene.tscn")
	await get_tree().create_timer(2.5).timeout
	var replay=get_tree().current_scene
	replay.replay_player.pause()
	var samples: Array=[]
	for time in [2.0,4.0,2.0]:
		replay.replay_player.seek(time)
		await get_tree().create_timer(.15).timeout
		saw=replay._game_world._saw_controller
		samples.append(saw.operator_seat.last_sample.duplicate())
	checks.replay_seek=samples[0]==samples[2]
	checks.replay_has_operator=saw.visible and saw.operator_seat.visible
	checks.record_format=recorder.fields_per_frame==34
	await capture("lifecycle_replay_default")
	# Free replay camera is an inspection view, separate from production cameras.
	var rc: ReplayCamera=replay.replay_camera_node
	var focus:=saw.operator_seat.station.global_position+Vector3(0,1.5,0)
	rc.camera.position=focus+Vector3(-3,1.5,4)
	rc.camera.look_at(focus)
	rc.set_mode(ReplayCamera.Mode.FREE)
	await get_tree().create_timer(.15).timeout
	await capture("lifecycle_replay_contact")
	finish()

func finish() -> void:
	for key in checks:
		if not checks[key]:errors.append(key)
	var report:={"passed":errors.is_empty(),"errors":errors,"checks":checks}
	FileAccess.open("res://artifacts/saw_operator/lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OPERATOR_LIFECYCLE ",JSON.stringify(report))
	get_tree().quit(0 if errors.is_empty() else 1)
