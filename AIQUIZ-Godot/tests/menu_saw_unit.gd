extends Node
var failures: Array[String]=[]
var checks:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value and not failures.has(label):failures.append(label)
func _ready() -> void:
	for fps in [30,60,120]:
		var state:=MenuSawChaseState.new()
		var dt:=1.0/float(fps)
		state.advance(1.0,false,-4.8,false)
		check(state.local_z==state.HOME_Z,"wait for arrival and spin")
		for i in fps*4:state.advance(dt,true,-4.8,false)
		check(absf(state.local_z-1.65)<.001,"leader gap and speed")
		var held:=state.local_z
		state.advance(1.0,true,3.0,false)
		check(state.local_z==held,"leader retreat does not reverse saw")
		check(state.hit(Vector2(-4.5,-3),Vector2(-4.5,3)),"swept contact catches fast crossing")
		state.catch_players(3)
		check(not state.can_respawn(1) and not state.can_respawn(2),"double catch holds both respawns")
		check(not state.hit(Vector2(-4.5,-3),Vector2(-4.5,3)),"catch phase disables repeated hit")
		for i in fps*5:state.advance(dt,true,-4.8,false)
		check(state.phase==state.Phase.RESPAWNING and state.local_z==state.HOME_Z,"return reaches original edge")
		check(state.can_respawn(1) and state.can_respawn(2),"home releases victims")
		state.advance(dt,true,-4.8,true)
		state.advance(1.0,true,-4.8,true)
		check(state.phase==state.Phase.GRACE and state.local_z==state.HOME_Z,"landing grace")
		for i in fps*2:state.advance(dt,true,-4.8,true)
		check(state.phase==state.Phase.CHASING and state.local_z<state.HOME_Z,"resume after grace")
	print("MENU_SAW_UNIT ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
