extends Node
var errors: Array[String]=[]
var checks: Dictionary={}
var records: Array[Dictionary]=[]
const OUT:="res://artifacts/saw_operator/v2_menu/"
func _ready() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	QuizManager.set_meta("saw_dock_menu_seen",true)
	QuizManager.provider.llm_mode="OFFLINE"
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	var preview: MenuWallBackgroundPreview
	for i in 1200:
		await get_tree().process_frame
		var scene:=get_tree().current_scene
		if scene and scene.get("_menu_wall_preview"):
			preview=scene._menu_wall_preview
			if preview._preview_saw and preview._preview_player and not SceneTransition.is_transitioning():break
	if preview==null:errors.append("menu ready timeout");finish();return
	preview.set_process(false)
	preview.sync_menu_player_count(2)
	preview._preview_saw._preview_elapsed=0.0
	preview._menu_saw.reset()
	# This fixture deliberately triggers a catch; rarity has its own acceptance test.
	preview._saw_accident_cooldown=0.0
	preview._saw_next_trial=INF
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var start:=Time.get_ticks_usec()
	var last:=start
	var previous_capture:=-1.0
	var accident_started:=false
	var caught:=false
	var returned:=false
	var resumed:=false
	while Time.get_ticks_usec()-start<28000000:
		await get_tree().process_frame
		var now:=Time.get_ticks_usec()
		var t:float=(now-start)/1000000.0
		var dt:float=minf(.05,(now-last)/1000000.0);last=now
		var gs:=preview._preview_gs
		# Deterministic inputs to the real AI/controller; the catch and recovery are production code.
		gs.player_x=-4.5;gs.player_z=-4.2*smoothstep(0,4,t)
		preview._p1_ai.next_action_t=preview._ai_time+100
		preview._p1_ai.depth_shift_active=true;preview._p1_ai.target_local_z=gs.player_local_z
		preview._p1_ai.depth_shift_speed=0.0;preview._p1_ai.lane_shift_active=false
		if not accident_started:
			gs.player2_x=-1.5;gs.player2_z=-.5
			preview._p2_ai.next_action_t=preview._ai_time+100
			preview._p2_ai.depth_shift_active=true;preview._p2_ai.target_local_z=-.5
			preview._p2_ai.depth_shift_speed=0.0;preview._p2_ai.lane_shift_active=false
			if t>8.0:accident_started=preview._start_saw_accident(preview._p2_ai,false)
		preview._process(dt)
		caught=caught or gs.p2_saw_killed
		if gs.p2_saw_killed:
			var pc:=preview._preview_player as PlayerController
			var driver:=pc._p2_ragdoll.get("saw_catch") as SawCatchRagdoll
			if driver!=null:checks.real_saw_anchor=driver.saw==preview._preview_saw
		returned=returned or (caught and preview._menu_saw.phase==MenuSawChaseState.Phase.RESPAWNING)
		resumed=resumed or (returned and preview._menu_saw.phase==MenuSawChaseState.Phase.CHASING and gs.p2_alive)
		if preview._menu_saw.phase==MenuSawChaseState.Phase.GRACE and not checks.has("landing_cooldown"):
			var remaining:=preview._saw_accident_cooldown-preview._ai_time
			checks.landing_cooldown=remaining>=44.9 and remaining<=60.0
		if returned and preview._ai_time<preview._saw_accident_cooldown:
			checks.recovery_blocks_new_accident=not preview._start_saw_accident(preview._p1_ai,true)
		if t-previous_capture>=1.0/12:
			previous_capture=t
			var file:="frame_%04d.jpg"%records.size()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(OUT+file,.93)
			records.append({"time":t,"file":file,"z":preview._menu_saw.local_z,"phase":preview._menu_saw.phase,"alive":gs.p2_alive,"drive":preview._preview_saw.operator_seat.last_sample.drive})
			if caught and not checks.has("caught_image"):
				get_viewport().get_texture().get_image().save_png(OUT+"caught.png");checks.caught_image=true
	checks.accident_started=accident_started;checks.caught=caught;checks.returned=returned;checks.resumed=resumed
	var old_z:=preview._menu_saw.local_z
	preview._customize_active=true
	preview._process(.3)
	checks.customize_freezes=preview._menu_saw.local_z==old_z
	preview._customize_active=false
	# Start during an outstanding saw death must clear flags and recovery waits.
	preview._menu_saw.phase=MenuSawChaseState.Phase.CATCHING
	preview._menu_saw.victim_mask=1
	preview._preview_gs.p1_saw_killed=true;preview._preview_gs.p1_alive=false
	checks.start_handoff=preview.begin_game_start_departure(2) and preview._preview_gs.p1_alive and not preview._preview_gs.p1_saw_killed and preview._menu_saw.victim_mask==0
	checks.record_format=ReplayRecorder.FIELDS_PER_FRAME==34
	finish()
func finish() -> void:
	for key in checks:
		if not checks[key]:errors.append(key)
	var result:={"passed":errors.is_empty(),"errors":errors,"checks":checks,"frames":records}
	FileAccess.open(OUT+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var manifest:=FileAccess.open(OUT+"frames.txt",FileAccess.WRITE)
	for i in records.size():
		manifest.store_line("file '%s'"%records[i].file)
		manifest.store_line("duration %.6f"%(float(records[i+1].time)-float(records[i].time) if i+1<records.size() else 1.0/12))
	print("MENU_SAW_RUNTIME ",JSON.stringify({"checks":checks,"errors":errors}))
	get_tree().quit(0 if errors.is_empty() else 1)
