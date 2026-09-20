extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func row(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func run() -> void:
	var saw=load("res://scripts/world/saw_chase_controller.gd").new()
	root.add_child(saw)
	saw.configure_entrance(false,true)
	var records: Array=[]
	for time in [0.0,2.3,3.3,4.2,4.8,5.5,6.2]:
		saw.dock.elapsed=time;saw.dock.apply_pose()
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		var error:=document.append_from_scene(saw.dock,state)
		var file:="res://artifacts/saw_operator/dock_%03d.glb"%roundi(time*10)
		if error==OK:error=document.write_to_filesystem(state,file)
		records.append({"time":time,"file":file,"error":error,"carriage":row(Transform3D(saw.dock.carriage_basis(),saw.dock.carriage_position()))})
	FileAccess.open("res://artifacts/saw_operator/dock_poses.json",FileAccess.WRITE).store_string(JSON.stringify(records))
	print("OPERATOR_DOCK_EXPORT ",JSON.stringify(records))
	quit()
