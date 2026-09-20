extends Node

## Explicit real-scene acceptance capture. Does not alter production cameras.
const OUT := "res://artifacts/saw_operator/"
var errors: Array[String] = []
var frames: Array[Dictionary] = []
var mode := "menu"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("mode="):mode = arg.trim_prefix("mode=")
	Engine.max_fps = 60
	if mode.begins_with("menu"):
		QuizManager.remove_meta("saw_dock_menu_seen")
		if mode == "menu_return":QuizManager.set_meta("saw_dock_menu_seen",true)
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	else:
		var gs: QuizGameState = QuizManager.game_state
		QuizManager.provider.llm_mode = "OFFLINE"
		gs.llm_mode = "OFFLINE"
		gs.num_players = 2
		gs.mode = Constants.MODE_TEN
		gs.start_game()
		gs.skip_start_helicopter_arrival = mode == "retry"
		if mode=="game":
			# Exercise the production Start route, including preparation under cover.
			QuizManager.set_meta("saw_dock_menu_seen",true)
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")
			for attempt in 1200:
				await get_tree().process_frame
				if get_tree().current_scene and get_tree().current_scene.get("_menu_wall_preview") and not SceneTransition.is_transitioning():break
			get_tree().current_scene._on_start_pressed()
		else:
			get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	var saw: SawChaseController
	for attempt in range(900):
		await get_tree().process_frame
		var world := get_tree().current_scene
		if world == null:continue
		if mode.begins_with("menu"):saw=get_tree().root.find_child("MenuSawCarriage",true,false) as SawChaseController
		elif world.name == "GameWorld":saw=world._saw_controller
		if saw != null and saw.operator_seat != null and not SceneTransition.is_transitioning():break
	if saw == null or saw.operator_seat == null:
		errors.append("scene not ready")
		finish()
		return
	if mode == "menu":
		saw.dock.begin()
		saw._preview_elapsed = 0.0
	var folder := OUT+mode+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var start := Time.get_ticks_msec()
	var previous := -1.0
	var start_sent := false
	var pause_started := -1.0
	var pause_sample := {}
	var pause_finished := false
	while Time.get_ticks_msec()-start < (20000 if mode.begins_with("menu") else 36000):
		await get_tree().process_frame
		var t := (Time.get_ticks_msec()-start)/1000.0
		if not mode.begins_with("menu") and not start_sent and t > 9.0:
			var world := get_tree().current_scene
			if world.game_state.game_state == Constants.STATE_WAITING_START and not world.is_start_presentation_locked() and not world._barrier_dropping:
				var event := InputEventKey.new()
				event.keycode=KEY_ENTER;event.pressed=true
				world._unhandled_input(event)
				start_sent=world.game_state.game_state != Constants.STATE_WAITING_START
		if not mode.begins_with("menu") and start_sent and not pause_finished:
			if get_tree().current_scene.game_state.game_state==Constants.STATE_PLAYING and pause_started<0:
				pause_started=t
				pause_sample=saw.operator_seat.last_sample.duplicate()
				get_tree().paused=true
			elif pause_started>=0 and t-pause_started>1.0:
				if saw.operator_seat.last_sample!=pause_sample:errors.append("pause changed pose")
				get_tree().paused=false
				pause_finished=true
		if t-previous < 1.0/15.0:continue
		previous=t
		var op := saw.operator_seat
		var maximum := 0.0
		for v in op.contact_errors.values():maximum=maxf(maximum,float(v))
		if maximum > .01 and not errors.has("control contact exceeds 1cm"):errors.append("control contact exceeds 1cm")
		var camera: Camera3D
		if mode.begins_with("menu"):camera=get_tree().current_scene._menu_wall_preview._preview_camera
		else:camera=get_tree().current_scene.camera_controller.camera
		var row := {"time":t,"dock":saw.dock.elapsed if saw.dock else -1,"spin":op.last_sample.get("spin",-1),"contact_error":maximum,"camera":str(camera.transform),"state":"MENU" if mode.begins_with("menu") else get_tree().current_scene.game_state.game_state,"paused":get_tree().paused,"file":"frame_%04d.jpg"%frames.size()}
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(folder+row.file,.94)
		frames.append(row)
		if frames.size() in [1,60,120,200,300,400]:get_viewport().get_texture().get_image().save_png(OUT+mode+"_%03d.png"%frames.size())
	if not mode.begins_with("menu"):
		if not start_sent:errors.append("gameplay start not reached")
		if not pause_finished:errors.append("pause/resume not exercised")
	finish()

func finish() -> void:
	var folder := OUT+mode+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"passed":errors.is_empty(),"errors":errors,"frames":frames},"\t"))
	var manifest := FileAccess.open(folder+"frames.txt",FileAccess.WRITE)
	for i in frames.size():
		manifest.store_line("file '%s'"%frames[i].file)
		manifest.store_line("duration %.6f"%(float(frames[i+1].time)-float(frames[i].time) if i+1<frames.size() else 1.0/15.0))
	print("OPERATOR_SCENE ",mode," ",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
