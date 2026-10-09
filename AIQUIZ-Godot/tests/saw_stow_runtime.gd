extends Node
## Real menu, wall speed tab stow v2 (Blender Stow/Deploy clips on one stow clock), 2P ten-question config:
##  A. open customize -> the davit towers rack the blades beside the conveyor; walls break short of the
##     machine while it stands over the belt and flow to the cliff once the blades hang outside.
##     Close -> the machine deploys, every bone returns to rest and the chase resumes.
##  B. close half way and reopen: the clock slows, turns around and turns back without a jump.
##  C. close after a full stow and press Start at once: the operator chair's launch waits while the
##     returning rack crosses its column; chair and blades never meet and the game still starts.
var errors: Array[String]=[]
var checks: Dictionary={}
var notes: Dictionary={}
var records: Array[Dictionary]=[]
const OUT:="res://artifacts/saw_stow/v2/runtime/"
const CAPTURE_HZ:=12.0
const HUB_SPEED:=5.0 # m of blade hub travel per second of stow clock (clips peak at 4.76 m/s)
const BLEND_SLACK:=.02 # a reversal's 0.35 s cross-fade moves the pose a few mm per frame
var menu: Node
var preview: MenuWallBackgroundPreview
var saw: SawChaseController
var start_usec:=0
var last_capture:=-1.0
var stage:="menu"
var prev_hubs: Array[Vector3]=[]
var prev_p:=0.0
var worst_excess:=-INF # per-frame hub displacement beyond HUB_SPEED * |dp| while the stow is active
var worst_excess_at:=-1.0
var worst_excess_stage:=""

func _ready() -> void:call_deferred("run")

func now() -> float:return (Time.get_ticks_usec()-start_usec)/1000000.0

func run() -> void:
	Engine.max_fps=60
	QuizManager.set_meta("saw_dock_menu_seen",true)
	QuizManager.provider.llm_mode="OFFLINE"
	var gs:=QuizManager.game_state
	gs.llm_mode="OFFLINE";gs.num_players=2;gs.mode=Constants.MODE_TEN;gs.menu_step=Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	for i in 1200:
		await get_tree().process_frame
		menu=get_tree().current_scene
		if menu and menu.get("_menu_wall_preview"):
			preview=menu._menu_wall_preview
			if preview._preview_saw and preview._preview_player and menu.get("_embedded_customize") and not SceneTransition.is_transitioning():break
	if preview==null:errors.append("menu ready timeout");finish();return
	menu.call("_update_ui")
	preview.sync_menu_player_count(2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	saw=preview._preview_saw
	start_usec=Time.get_ticks_usec()
	await wait_until(func():return now()>=6.0,10.0)
	await scenario_full_stow()
	await scenario_reversal()
	await scenario_chair_start()
	finish()

## One rendered frame: continuity of the blade hubs (carriage frame) and a 12 Hz capture.
func frame() -> void:
	await RenderingServer.frame_post_draw
	var t:=now()
	if get_tree().current_scene!=menu:return
	# Measured against the stow clock, not the wall clock: the engine smooths frame deltas.
	var hubs: Array[Vector3]=[]
	for i in saw.spin_bones.size():hubs.append(saw.to_local(saw.blade_center(i)))
	var p:=saw.stow_time()
	if not saw.is_stow_clear() and prev_hubs.size()==hubs.size():
		for i in hubs.size():
			var excess:=hubs[i].distance_to(prev_hubs[i])-HUB_SPEED*absf(p-prev_p)
			if excess>worst_excess:worst_excess=excess;worst_excess_at=p;worst_excess_stage=stage
	prev_hubs=hubs
	prev_p=p
	if t-last_capture>=1.0/CAPTURE_HZ:
		last_capture=t
		var file:="frame_%04d.jpg"%records.size()
		get_viewport().get_texture().get_image().save_jpg(OUT+file,.9)
		records.append({"time":t,"file":file,"stage":stage,"p":saw.stow_time(),"rate":saw._stow_rate,"clip":saw._stow_clip,
			"blocks":saw.stow_blocks_walls(),"break_z":preview._wall_break_z(),"front_wall":front_wall(),"beacon":saw.beacons_lit()})

func wait_until(condition: Callable,timeout: float) -> bool:
	var until:=now()+timeout
	while now()<until:
		if condition.call():return true
		await frame()
	return condition.call()

func front_wall() -> float:
	var z:=-INF
	for wall in preview._preview_walls:
		if is_instance_valid(wall):z=maxf(z,wall.position.z)
	return z

func scenario_full_stow() -> void:
	stage="customize"
	var opened:=now()
	var chase_z:=preview._menu_saw.local_z
	menu._open_embedded_customize()
	var racked_at:=-1.0
	var frozen:=true
	var wall_overrun:=-INF
	var block_since:=-1.0
	var cliff:=false # a wall reaches the cliff edge once the machine has left the belt
	var min_abs_x:=INF
	var max_top:=-INF
	var beacon_seen:=false
	var shown:=true
	while now()<opened+saw.stow_length()+3.5:
		await frame()
		shown=shown and saw.visible and not preview._customize_walls_hidden
		if racked_at<0.0 and saw.is_fully_stowed():racked_at=now()
		frozen=frozen and is_equal_approx(preview._menu_saw.local_z,chase_z)
		beacon_seen=beacon_seen or saw.beacons_lit()
		if saw.stow_blocks_walls():
			if block_since<0.0:block_since=now()
			# Walls already between the new break line and the cliff break on the next update.
			if now()-block_since>.25:wall_overrun=maxf(wall_overrun,front_wall()-preview._wall_break_z())
		else:block_since=-1.0
		if saw.stow_time()>=float(saw._stow_data.wall_block[-1].to) and front_wall()>7.0:cliff=true
		if saw.is_fully_stowed():
			for i in saw.spin_bones.size():
				var c:=saw.to_local(saw.blade_center(i))
				min_abs_x=minf(min_abs_x,absf(c.x))
				max_top=maxf(max_top,c.y+SawChaseState.BLADE_RADIUS)
	checks.wall_speed_tab_shows_the_machine=shown
	checks.racked_within_clip=racked_at>0.0 and racked_at-opened<=saw.stow_length()+.6
	checks.chase_frozen_while_racking=frozen
	checks.walls_break_short_of_the_machine=wall_overrun<=.35
	# QuizWall spans the 24 m floor minus 0.1 m per side; the belt surface is the controller's y=0.
	checks.blades_outside_wall_span=min_abs_x-.15>11.9
	checks.blades_below_belt_surface=max_top<0.0
	checks.walls_reach_cliff_once_the_machine_leaves_the_belt=cliff
	checks.beacons_flash_while_working=beacon_seen
	checks.beacons_dark_when_parked=not saw.beacons_lit()
	notes.stow={"racked_after":snappedf(racked_at-opened,.01),"wall_overrun":snappedf(wall_overrun,.001),"min_blade_abs_x":snappedf(min_abs_x,.001),"max_blade_top":snappedf(max_top,.001)}
	stage="closing"
	var closed:=now()
	menu._on_embedded_customize_close_requested()
	var clear_at:=-1.0
	var spin_clock:=INF
	var chase_clock:=INF
	var resumed:=false
	while now()<closed+saw.stow_length()+3.5:
		await frame()
		if clear_at<0.0 and saw.is_stow_clear():clear_at=now();spin_clock=saw._preview_elapsed;chase_clock=preview._menu_saw.clock
		# The chase only closes in on runners that pull ahead, so its clocks (not its z) show it runs again.
		if clear_at>0.0 and saw._preview_elapsed>spin_clock and preview._menu_saw.clock>chase_clock:resumed=true
	checks.deploy_within_clip=clear_at>0.0 and clear_at-closed<=saw.stow_length()+.6
	checks.spin_and_chase_resume_after_deploy=resumed
	checks.bones_back_at_rest=bones_at_rest()
	checks.beacons_dark_after_deploy=not saw.beacons_lit()
	notes.deploy={"clear_after":snappedf(clear_at-closed,.01)}

func scenario_reversal() -> void:
	stage="reverse"
	menu._open_embedded_customize()
	await wait_until(func():return saw.stow_time()>=5.0,12.0)
	var p_close:=saw.stow_time()
	menu._on_embedded_customize_close_requested()
	await wait_until(func():return not menu._menu_exit_in_progress and saw._stow_rate<0.0,4.0)
	var p_turn:=saw.stow_time()
	await wait_until(func():return saw.stow_time()<=p_close-1.0,6.0)
	var p_reopen:=saw.stow_time()
	menu._open_embedded_customize()
	var parked:=await wait_until(func():return saw.is_fully_stowed(),saw.stow_length()+4.0)
	menu._on_embedded_customize_close_requested()
	var clear:=await wait_until(func():return saw.is_stow_clear(),saw.stow_length()+4.0)
	checks.reopen_mid_stow_completes=parked
	checks.reversed_stow_deploys_to_rest=clear and bones_at_rest()
	checks.stow_has_no_jump=worst_excess<=BLEND_SLACK
	notes.reversal={"closed_at_p":snappedf(p_close,.01),"turned_by_p":snappedf(p_turn,.01),"reopened_at_p":snappedf(p_reopen,.01),
		"worst_hub_excess_m":snappedf(worst_excess,.0001),"at_p":snappedf(worst_excess_at,.01),"in_stage":worst_excess_stage}

func scenario_chair_start() -> void:
	stage="chair"
	menu._open_embedded_customize()
	await wait_until(func():return saw.is_fully_stowed(),saw.stow_length()+4.0)
	for i in 20:await frame()
	menu._on_embedded_customize_close_requested()
	await wait_until(func():return not menu._menu_exit_in_progress,3.0)
	var transfer: SeatLaunchPresentation=saw.operator_seat.seat_transfer
	var pressed_at:=now()
	var pressed_p:=saw.stow_time()
	menu.call("_on_start_pressed")
	var launch_at:=-1.0
	var launch_p:=-1.0
	var clear_at_launch:=false
	var held:=0.0 # buckled and otherwise ready, but a returning rack still crosses the chair column
	var min_gap:=INF
	var left_menu:=false
	while now()<pressed_at+30.0:
		var before:=now()
		await frame()
		if get_tree().current_scene!=menu:left_menu=true;break
		if transfer.phase==SeatLaunchPresentation.Phase.ARMED and not saw.chair_launch_clear(1.5):held+=now()-before
		if launch_at<0.0 and transfer.phase>=SeatLaunchPresentation.Phase.LAUNCHING:
			launch_at=now();launch_p=saw.stow_time();clear_at_launch=saw.chair_launch_clear(0.0)
		if launch_at>0.0 and now()-launch_at<2.5 and transfer.flight_root!=null:
			var base:=transfer.flight_root.global_position
			for i in saw.spin_bones.size():
				var hub:=saw.blade_center(i)
				var nearest:=Geometry3D.get_closest_point_to_segment(hub,base,base+Vector3.UP*1.6)
				min_gap=minf(min_gap,hub.distance_to(nearest)-SawChaseState.BLADE_RADIUS)
	checks.chair_launched=launch_at>0.0
	checks.chair_launch_waits_for_the_rack=clear_at_launch
	checks.chair_and_blades_never_meet=min_gap>.3
	checks.start_completes_without_failsafe=left_menu
	notes.chair={"pressed_at_p":snappedf(pressed_p,.01),"launch_after":snappedf(launch_at-pressed_at,.01),"launch_p":snappedf(launch_p,.01),
		"held_by_rack":snappedf(held,.01),"min_gap":snappedf(min_gap,.01)}

func bones_at_rest() -> bool:
	var sk:=saw.skeleton
	for bone in sk.get_bone_count():
		var prefix:=sk.get_bone_name(bone).get_slice("_",0)
		if prefix in ["Carriage","Roll","Spin"]:continue
		if not sk.get_bone_pose(bone).is_equal_approx(sk.get_bone_rest(bone)):return false
	return true

func finish() -> void:
	for key in checks:
		if not checks[key]:errors.append(key)
	var result:={"passed":errors.is_empty(),"errors":errors,"checks":checks,"notes":notes,"frames":records}
	FileAccess.open(OUT+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var manifest:=FileAccess.open(OUT+"frames.txt",FileAccess.WRITE)
	for i in records.size():
		manifest.store_line("file '%s'"%records[i].file)
		manifest.store_line("duration %.6f"%(float(records[i+1].time)-float(records[i].time) if i+1<records.size() else 1.0/CAPTURE_HZ))
	print("SAW_STOW_RUNTIME ",JSON.stringify({"checks":checks,"errors":errors,"notes":notes}))
	get_tree().quit(0 if errors.is_empty() else 1)
