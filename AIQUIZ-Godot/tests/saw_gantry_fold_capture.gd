extends Node
## Real menu: replay the service vessel's entrance and capture the folded side gantries standing upright on
## the vessel and swinging down beside the conveyor once the carriage is on the belt (SawChaseController).
## Frames and a summary go to artifacts/saw_stow/v3/fold/ (ffmpeg concat list: frames.txt).
const OUT:="res://artifacts/saw_stow/v3/fold/"
const CAPTURE_HZ:=10.0
var checks: Dictionary={}
var records: Array[Dictionary]=[]
var view: Camera3D # the capture camera; the menu keeps making its own current, so this runs last every frame

func _ready() -> void:
	process_priority=1000
	call_deferred("run")

func _process(_dt: float) -> void:
	if view!=null and is_instance_valid(view):view.make_current()

func run() -> void:
	Engine.max_fps=60
	QuizManager.set_meta("saw_dock_menu_seen",true)
	QuizManager.provider.llm_mode="OFFLINE"
	var gs:=QuizManager.game_state
	gs.llm_mode="OFFLINE";gs.num_players=2;gs.mode=Constants.MODE_TEN;gs.menu_step=Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var preview: MenuWallBackgroundPreview
	for i in 1200:
		await get_tree().process_frame
		var menu:=get_tree().current_scene
		if menu and menu.get("_menu_wall_preview"):
			preview=menu._menu_wall_preview
			if preview._preview_saw and not SceneTransition.is_transitioning():break
	if preview==null:finish(false);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var saw:=preview._preview_saw
	for i in 30:await get_tree().process_frame
	# Look back from the belt at the carriage's home and the vessel behind it, both gantries in view.
	var home:=Vector3(0.0,StageConstants.FLOOR_TOP_Y,SawDockPresentation.MENU_Z)
	var cam:=Camera3D.new()
	cam.fov=70.0
	get_tree().current_scene.add_child(cam)
	cam.global_position=home+Vector3(-6.0,9.0,-15.0)
	cam.look_at(home+Vector3(0.0,0.0,3.0))
	view=cam
	saw.dock.begin()
	saw._preview_elapsed=0.0
	var upright_on_vessel:=true
	var folded_after:=false
	var fold_started:=-1.0
	var start:=Time.get_ticks_msec()
	var last:=-1.0
	while saw.dock.elapsed<10.5 and Time.get_ticks_msec()-start<20000:
		await RenderingServer.frame_post_draw
		var t:=saw.dock.elapsed
		var up:=saw.gantry_upright_weight()
		if not saw.dock.is_deployed():
			if up<1.0:upright_on_vessel=false
			for i in saw._gantry_bones.size():
				if not saw.skeleton.get_bone_pose_rotation(saw._gantry_bones[i]).is_equal_approx(saw._gantry_upright[i]):upright_on_vessel=false
		if fold_started<0.0 and up<1.0:fold_started=t
		if t>SawDockPresentation.READY_TIME+SawChaseController.GANTRY_FOLD_DELAY+SawChaseController.GANTRY_FOLD_SECONDS+.1:
			folded_after=is_zero_approx(up)
		if t-last>=1.0/CAPTURE_HZ:
			last=t
			var file:="frame_%04d.jpg"%records.size()
			get_viewport().get_texture().get_image().save_jpg(OUT+file,.9)
			records.append({"time":t,"file":file,"upright":up})
	checks.upright_while_the_vessel_carries_the_carriage=upright_on_vessel
	checks.fold_starts_after_the_transfer=fold_started>=SawDockPresentation.READY_TIME
	checks.folded_beside_the_conveyor_afterwards=folded_after
	finish(true)

func finish(ok: bool) -> void:
	var errors: Array[String]=[]
	if not ok:errors.append("menu ready timeout")
	for key in checks:
		if not checks[key]:errors.append(key)
	var manifest:=FileAccess.open(OUT+"frames.txt",FileAccess.WRITE)
	if manifest:
		for i in records.size():
			manifest.store_line("file '%s'"%records[i].file)
			manifest.store_line("duration %.6f"%(float(records[i+1].time)-float(records[i].time) if i+1<records.size() else 1.0/CAPTURE_HZ))
	print("SAW_GANTRY_FOLD ",JSON.stringify({"checks":checks,"errors":errors,"frames":records.size()}))
	get_tree().quit(0 if errors.is_empty() else 1)
