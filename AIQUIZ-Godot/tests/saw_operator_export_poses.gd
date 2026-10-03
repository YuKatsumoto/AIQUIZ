extends SceneTree

## Evaluates the v3 operator exactly as the game does and writes 30fps poses for the
## Blender preview bake (tools/saw_operator/bake_source_v3.py):
## transport, all six waiting vignettes, the start, a running cycle with lift moves,
## a blade catch and the shutdown.
## godot --headless --path . --script res://tests/saw_operator_export_poses.gd
const OUT := "res://assets/hazards/saw_operator/source/evaluated_poses_v3.json"
const CONTROLS := ["OP_Lever_L","OP_Lever_R","OP_Pedal_L","OP_Pedal_R","OP_Key","OP_Guard","OP_Start",
	"OP_Horn","OP_Dial","OP_Beacon","OP_Needle_Speed","OP_Needle_RPM","OP_Needle_Lift"]

func _initialize() -> void:
	call_deferred("run")

func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]

func run() -> void:
	var script: Script = load("res://scripts/world/saw_operator_presentation.gd")
	var op = script.new()
	root.add_child(op)
	var capture: Script = load("res://tests/saw_operator_motion_capture.gd")
	var samples: Array[Dictionary] = capture.sequence()
	var markers := {"Transport": 1, "Wait: look around": 91}
	var names := ["look around","drum","stretch","doze","swing","wave"]
	for i in names.size(): markers["Wait: " + names[i]] = 91 + int(i*SawOperatorPresentation.IDLE_SLOT*30)
	var run_start := 91 + int(SawOperatorPresentation.IDLE_SLOT*6*30)
	markers.merge({"Start: key + guard": run_start, "Start: slam": run_start+24, "Start: fist pump": run_start+42,
		"Run: gauges / dial": run_start+90, "Run: lift up/down": run_start+180, "Catch: horn + pump": run_start+330,
		"Stop: key off, guard": run_start+420})
	var poses: Array = []
	for frame in samples.size():
		op.apply_sample(samples[frame])
		var bones: Dictionary = {}
		for key in op.bones: bones[key] = matrix(op.skeleton.get_bone_global_pose(op.bones[key]))
		var controls: Dictionary = {}
		for key: String in CONTROLS: controls[key] = matrix(op.controls[key].transform)
		poses.append({"frame":frame+1,"extension":op.last_sample.extension,"lowering":op.last_sample.lowering,"bones":bones,"controls":controls})
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"fps":30,"markers":markers,"poses":poses}))
	print("OPERATOR_POSE_EXPORT ",poses.size())
	quit()
