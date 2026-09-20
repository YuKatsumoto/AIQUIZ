extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]

func run() -> void:
	var script: Script = load("res://scripts/world/saw_operator_presentation.gd")
	var op = script.new()
	root.add_child(op)
	op.apply_sample(script.sample(6.2,0,0,0,true))
	var transfer = op.seat_transfer
	var poses: Array = []
	transfer.begin_buckle();transfer.set_process(false)
	for frame in range(445):
		if frame == 174: transfer.launch()
		if frame == 258: transfer.begin_arrival()
		if frame < 258: transfer.advance_departure(1.0/60.0)
		else: transfer.advance_arrival(1.0/60.0,true)
		var bones := {}
		for key in op.bones: bones[key]=matrix(op.skeleton.get_bone_global_pose(op.bones[key]))
		var controls := {}
		for key in op.controls: controls[key]=matrix(op.controls[key].transform)
		poses.append({"frame":frame+1,"phase":transfer.phase,"height":transfer.height,"belt":transfer.belt_extension,"bones":bones,"controls":controls})
	FileAccess.open("res://assets/hazards/saw_operator/source/chair_transfer_poses.json",FileAccess.WRITE).store_string(JSON.stringify(poses))
	print("CHAIR_POSES ",poses.size())
	quit()
