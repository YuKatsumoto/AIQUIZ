extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]

func run() -> void:
	var script: Script=load("res://scripts/world/saw_operator_presentation.gd")
	var op=script.new()
	root.add_child(op)
	var poses: Array=[]
	for frame in range(961):
		var t: float=frame/60.0
		var spin:=maxf(0,t-6.2)
		var drive:=smoothstep(10.2,10.8,t)-2*smoothstep(12.3,13.0,t)+smoothstep(14,14.7,t)
		var height:=2*(smoothstep(10.5,11.5,t)-smoothstep(12.5,13.5,t))
		var before:=2*(smoothstep(10.5,11.5,t-.01)-smoothstep(12.5,13.5,t-.01))
		var after:=2*(smoothstep(10.5,11.5,t+.01)-smoothstep(12.5,13.5,t+.01))
		op.apply_sample(script.sample(t,spin,drive,height,t>=6.2,(after-before)/.02))
		var bones: Dictionary={}
		for key in op.bones:bones[key]=matrix(op.skeleton.get_bone_global_pose(op.bones[key]))
		var controls: Dictionary={}
		for key in op.controls:controls[key]=matrix(op.controls[key].transform)
		poses.append({"frame":frame+1,"sample":op.last_sample.duplicate(),"bones":bones,"controls":controls})
	FileAccess.open("res://assets/hazards/saw_operator/source/evaluated_poses.json",FileAccess.WRITE).store_string(JSON.stringify(poses))
	print("OPERATOR_POSE_EXPORT ",poses.size())
	quit()
