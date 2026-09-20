extends Node
var failures: Array[String]=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func _ready() -> void:
	for fps in [30,60,120]:
		var state:=MenuSawChaseState.new()
		for i in fps*8:state.advance(1.0/fps,true,-4.8,false,0.0)
		var required:=SawChaseState.BLADE_RADIUS+QuizGameState.PLAYER_BODY_RADIUS+state.SAFE_GAP
		check(absf(state.local_z-required)<.001,"rear safety at %d fps"%fps)
		var held:=state.local_z
		state.advance(1.0,true,-4.8,false,2.0)
		check(state.local_z==held,"rear retreat stops without reversal")
		state.advance(1.0,true,-4.8,false,-2.0)
		check(state.local_z<held,"advance when rear makes space")
	var preview:=MenuWallBackgroundPreview.new()
	preview._p1_ai=MenuPreviewActorAIState.new();preview._p2_ai=MenuPreviewActorAIState.new()
	preview._preview_gs=QuizGameState.new()
	preview._menu_saw.phase=MenuSawChaseState.Phase.CHASING
	preview._menu_saw.local_z=5.8
	preview._preview_gs.player_z=0;preview._preview_gs.player2_z=0
	preview._preview_gs.p1_alive=true;preview._preview_gs.p2_alive=true
	for t in [0.0,10.0,19.99]:
		preview._ai_time=t;preview._update_saw_accident_trial()
		check(preview._saw_accident_owner==0,"initial grace %.2f"%t)
	preview._ai_time=21;preview._saw_next_trial=INF
	check(preview._clamp_depth_target_z(100,preview._p1_ai)<=preview._saw_safe_depth(),"ordinary retreat safe")
	preview._p1_ai.pending_accident=preview.PENDING_ACCIDENT_OCEAN
	check(preview._clamp_depth_target_z(100,preview._p1_ai)<=preview._saw_safe_depth(),"blocked ocean run-up safe")
	preview._p1_ai.pending_accident=preview.PENDING_ACCIDENT_NONE
	check(preview._start_saw_accident(preview._p1_ai,true,true),"near miss can start")
	preview._preview_gs.player_z=preview._saw_safe_depth()
	preview._update_pending_saw_accident(preview._p1_ai,true)
	check(preview._p1_ai.target_local_z<preview._saw_safe_depth() and preview._saw_accident_owner==0,"near miss escapes forward")
	preview._preview_gs.player_z=0
	check(preview._start_saw_accident(preview._p1_ai,true),"selected accident can cross safety boundary")
	check(preview._p1_ai.target_local_z>preview._saw_safe_depth(),"physical catch remains reachable")
	preview._clear_pending_accident(preview._p1_ai);preview._saw_accident_owner=0
	var rates: Dictionary={}
	for count in [1,2]:
		seed(240920)
		preview._preview_gs.num_players=count;preview._menu_synced_player_count=count
		var fatal:=0
		for trial in 1000:
			preview._ai_time=100.0+trial*10.0
			preview._saw_accident_cooldown=0;preview._saw_next_trial=preview._ai_time
			preview._clear_pending_accident(preview._p1_ai);preview._clear_pending_accident(preview._p2_ai)
			preview._saw_accident_owner=0
			preview._update_saw_accident_trial()
			if preview._saw_accident_owner!=0 and not preview._saw_near_miss:fatal+=1
			var owner:=preview._saw_accident_owner
			preview._update_saw_accident_trial()
			check(owner==preview._saw_accident_owner,"single shared trial per interval")
			preview._saw_events.clear()
		rates[count]=fatal/1000.0
		check(fatal>=120 and fatal<=180,"15 percent shared selection for %d players"%count)
	check(absf(float(rates[1])-float(rates[2]))<.025,"2P does not double accident frequency")
	preview.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"shared_selection_rates":rates}
	FileAccess.open("res://artifacts/saw_operator/rarity_unit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MENU_SAW_RARITY ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
