extends Node
var checks: Dictionary={}
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
	preview.set_process(false)
	preview._preview_saw.update_preview(0)
	var gs:=preview._preview_gs
	preview._preview_saw._preview_elapsed=5.0
	preview.sync_menu_player_count(1)
	gs.num_players=1
	preview._menu_saw.reset();preview._menu_saw.phase=MenuSawChaseState.Phase.CHASING;preview._menu_saw.local_z=1.65
	gs.p1_alive=true;gs.player_x=-4.5;gs.player_z=1.0;gs.player_y=1.0
	preview._p1_ai.ai_state=preview.AI_STATE_NORMAL
	preview._update_menu_saw(1.0/60,Vector2(-4.5,-2),Vector2.ZERO)
	checks.single_player_catch=gs.p1_saw_killed and preview._menu_saw.victim_mask==1
	var lift:float=preview._preview_saw.operator_seat.last_sample.lift
	checks.airborne_blade_lift=lift>0
	preview.sync_menu_player_count(2)
	gs.num_players=2
	preview._menu_saw.reset();preview._menu_saw.phase=MenuSawChaseState.Phase.CHASING;preview._menu_saw.local_z=1.65
	gs.p1_alive=true;gs.p2_alive=true;gs.p1_saw_killed=false;gs.p2_saw_killed=false
	gs.player_x=-4.5;gs.player_z=1;gs.player2_x=4.5;gs.player2_z=1
	preview._p1_ai.ai_state=preview.AI_STATE_NORMAL;preview._p2_ai.ai_state=preview.AI_STATE_NORMAL
	preview._update_menu_saw(1.0/60,Vector2(-4.5,-2),Vector2(4.5,-2))
	checks.simultaneous_catch=gs.p1_saw_killed and gs.p2_saw_killed and preview._menu_saw.victim_mask==3
	var pose:=preview._preview_saw.operator_seat.last_sample.duplicate()
	var old_z:=preview._menu_saw.local_z
	(preview._viewport.get_parent() as CanvasItem).hide()
	preview._process(.5)
	checks.hidden_freezes=preview._menu_saw.local_z==old_z and pose==preview._preview_saw.operator_seat.last_sample
	(preview._viewport.get_parent() as CanvasItem).show()
	preview._menu_saw.reset();preview._menu_saw.phase=MenuSawChaseState.Phase.CHASING
	gs.p1_alive=true;gs.p1_saw_killed=false
	preview._trigger_preview_death("crash",preview._p1_ai,true)
	checks.wall_death_no_return=preview._menu_saw.phase==MenuSawChaseState.Phase.CHASING
	gs.p2_alive=true;gs.p2_saw_killed=false
	preview._trigger_preview_death("ocean",preview._p2_ai,false)
	checks.ocean_death_no_return=preview._menu_saw.phase==MenuSawChaseState.Phase.CHASING
	# Render the real near-miss retreat and escape, without a timed death.
	preview._menu_saw.reset();preview._menu_saw.phase=MenuSawChaseState.Phase.CHASING;preview._menu_saw.local_z=3.0
	preview._ai_time=100;preview._saw_accident_cooldown=0;preview._saw_next_trial=INF
	preview._saw_accident_owner=0
	gs.p1_alive=true;gs.p2_alive=true;gs.p1_saw_killed=false;gs.p2_saw_killed=false
	gs.player_z=-4.2;gs.player2_z=-2.5;gs.player_y=0;gs.player2_y=0;gs.player2_x=-1.5
	preview._p1_ai.ai_state=preview.AI_STATE_NORMAL;preview._p2_ai.ai_state=preview.AI_STATE_NORMAL
	preview._p2_ai.is_emoting=false
	preview._clear_pending_accident(preview._p2_ai)
	checks.near_miss_starts=preview._start_saw_accident(preview._p2_ai,false,true)
	var retreated:=false
	var escaped:=false
	var gap:=INF
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/saw_operator/rarity_near/"))
	for i in 150:
		await get_tree().process_frame
		preview._ai_time+=1.0/60
		var before:=gs.player2_local_z
		preview._update_depth_shift(1.0/60,preview._p2_ai,false)
		preview._update_pending_saw_accident(preview._p2_ai,false)
		preview._update_menu_saw(1.0/60,Vector2(gs.player_x,gs.player_local_z),Vector2(gs.player2_x,before))
		preview._preview_player.update_from_state(gs)
		retreated=retreated or gs.player2_local_z>before+.001
		escaped=escaped or (retreated and gs.player2_local_z<before-.001)
		gap=minf(gap,preview._menu_saw.local_z-SawChaseState.BLADE_RADIUS-QuizGameState.PLAYER_BODY_RADIUS-gs.player2_local_z)
		if i%6==0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("res://artifacts/saw_operator/rarity_near/frame_%03d.jpg"%(i/6),.94)
	checks.near_miss_survives=gs.p2_alive and retreated and escaped
	checks.near_miss_clearance=gap>=MenuSawChaseState.SAFE_GAP-.001
	preview._menu_saw.phase=MenuSawChaseState.Phase.CATCHING
	preview._menu_saw.victim_mask=3
	gs.p1_alive=false;gs.p2_alive=false
	gs.p1_saw_killed=true;gs.p2_saw_killed=true
	preview.set_process(true)
	QuizManager.game_state.num_players=2
	QuizManager.game_state.mode=Constants.MODE_TEN
	var menu:=get_tree().current_scene
	menu._on_start_pressed()
	var deadline:=Time.get_ticks_msec()+25000
	var grips: Dictionary={}
	checks.start_revives=false
	while is_instance_valid(menu) and get_tree().current_scene==menu and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if not is_instance_valid(preview):break
		if preview.is_game_start_departure_active():
			checks.start_revives=gs.p1_alive and gs.p2_alive and not gs.p1_saw_killed and not gs.p2_saw_killed
			for info: Dictionary in preview._menu_start_departure._helicopters:
				if info.get("captured",false):grips[int(info.player_index)]=true
	while get_tree().current_scene==null and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	checks.start_finishes=get_tree().current_scene!=null and get_tree().current_scene.scene_file_path=="res://scenes/game_world.tscn" and grips.size()==2
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/saw_operator/v2_start_finished.png")
	var errors: Array[String]=[]
	for key in checks:
		if not checks[key]:errors.append(key)
	FileAccess.open("res://artifacts/saw_operator/v2_edges.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"errors":errors,"passed":errors.is_empty()},"\t"))
	print("MENU_SAW_EDGES ",JSON.stringify({"checks":checks,"errors":errors}))
	get_tree().quit(0 if errors.is_empty() else 1)
