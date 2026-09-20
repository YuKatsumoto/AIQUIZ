extends Node
var records: Array[Dictionary]=[]
var events: Array[Dictionary]=[]
var known: Dictionary={}
const OUT:="res://artifacts/saw_operator/rarity/"
func _ready() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	seed(240920)
	QuizManager.set_meta("saw_dock_menu_seen",true)
	QuizManager.provider.llm_mode="OFFLINE"
	QuizManager.game_state.num_players=2
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var preview: MenuWallBackgroundPreview
	for i in 1200:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.get("_menu_wall_preview"):
			preview=get_tree().current_scene._menu_wall_preview
			if preview._preview_saw and preview._preview_saw.operator_seat and not SceneTransition.is_transitioning():break
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var start:=Time.get_ticks_msec()
	var captured:=-1.0
	# Unmodified AI and real elapsed time: no forced actor placement or accident.
	while Time.get_ticks_msec()-start<180000:
		await get_tree().process_frame
		var t:float=(Time.get_ticks_msec()-start)/1000.0
		for event: Dictionary in preview._saw_events:
			var key:=JSON.stringify(event)
			if not known.has(key):known[key]=true;events.append(event.duplicate())
		if t-captured>=.25:
			captured=t
			await RenderingServer.frame_post_draw
			var file:="frame_%04d.jpg"%records.size()
			get_viewport().get_texture().get_image().save_jpg(OUT+file,.88)
			records.append({"file":file,"time":t,"ai_time":preview._ai_time,"phase":preview._menu_saw.phase,"z":preview._menu_saw.local_z,"p1":preview._actor_local_z(true),"p2":preview._actor_local_z(false),"cooldown_until":preview._saw_accident_cooldown})
	var catches: Array=[]
	for event in events:
		if event.event=="catch":catches.append(event)
	var result:={"seconds":180,"players":2,"catches":catches,"events":events,"frames":records}
	FileAccess.open(OUT+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var manifest:=FileAccess.open(OUT+"frames.txt",FileAccess.WRITE)
	for i in records.size():
		manifest.store_line("file '%s'"%records[i].file)
		manifest.store_line("duration %.6f"%(records[i+1].time-records[i].time if i+1<records.size() else .25))
	print("MENU_SAW_FREQUENCY ",JSON.stringify({"seconds":180,"catches":catches,"events":events}))
	get_tree().quit()
