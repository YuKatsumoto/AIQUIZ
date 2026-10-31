extends Node

## The side stands' beer vendors stay on the stand that is shown: when the stand
## ends early at the goal stand's monitor (StageEnvironment.set_grandstand_end_limit(),
## AiquizStadiumStand.fit_end()) the blocks past it hide, and a vendor walking
## there walks on the open water. Runs the sim for a while with the stand cut and
## checks every vendor's world z against the stand's end, on both sides.
##   Godot --headless --path . --script tests/crowd_vendor_bounds_bootstrap.gd

const StageScript = preload("res://scripts/world/stage_environment.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const DT := 1.0 / 30.0
## The stand's back end (world z) and where it is cut (the goal stand's monitor).
const FLOOR_CENTER_Z := 60.0
const FLOOR_LENGTH := 150.0
const END_Z := 95.0
## A vendor's feet may reach this far past the end (the cap's front deck edge).
const SLACK := 0.6

var errors: Array[String] = []
var stage: Node3D
var mood: CrowdMood
var camera: Camera3D


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


func _run() -> void:
	stage = StageScript.new()
	add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = FLOOR_CENTER_Z
	config.floor_length = FLOOR_LENGTH
	config.crowd_sim = true
	stage.build(config)
	camera = Camera3D.new()
	add_child(camera)
	camera.make_current()
	mood = CrowdMood.new()
	mood.match_serial = 1
	await get_tree().process_frame
	var start_z := (stage.get_node("Grandstands") as Node3D).global_position.z
	stage.set_grandstand_end_limit(END_Z)
	var report := {"start_z": start_z, "end_z": END_Z}
	for side: String in ["GrandstandRight", "GrandstandLeft"]:
		var crowd := stage.get_node("Grandstands/%s/Spectators" % side)
		check(crowd.sim != null and not crowd.sim.vendors.is_empty(), "%s has vendors" % side)
	# Long enough for every vendor to patrol its whole stretch a few times.
	var worst := {}
	for _frame: int in range(int(240.0 / DT)):
		CrowdScript.update_sim(mood, DT, camera)
		for side: String in ["GrandstandRight", "GrandstandLeft"]:
			var crowd := stage.get_node("Grandstands/%s/Spectators" % side) as Node3D
			for v: CrowdSim.Vendor in crowd.sim.vendors:
				var z := (crowd.global_transform * v.position).z
				worst[side] = maxf(float(worst.get(side, -INF)), z)
				check(z >= start_z - SLACK, "%s vendor stays past the stand's back end" % side)
	for side: String in worst:
		check(float(worst[side]) <= END_Z + SLACK,
			"%s vendor stays short of the stand's cut end (reached world z %.1f, end %.1f)" % [side, worst[side], END_Z])
	report["furthest_z"] = worst
	print("CROWD_VENDOR_BOUNDS ", "PASS" if errors.is_empty() else "FAIL", " ",
		JSON.stringify({"errors": errors, "report": report}))
	get_tree().quit(0 if errors.is_empty() else 1)
