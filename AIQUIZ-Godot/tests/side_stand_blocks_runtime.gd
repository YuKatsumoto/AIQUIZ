extends Node

## Side stands built from 20 m terrace blocks with seated goal-stand spectators.
##   Godot --headless --path . --script tests/side_stand_blocks_bootstrap.gd
## Structural checks only; run without --headless to also save screenshots to
## artifacts/side_stand_blocks/ (Forward+ evidence of the seated crowd).

const StageScript = preload("res://scripts/world/stage_environment.gd")
const StandScript = preload("res://scripts/world/santorini_terrace_stand.gd")
const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const OUT := "res://artifacts/side_stand_blocks/"

var errors: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


func _run() -> void:
	var stage: Node3D = StageScript.new()
	get_tree().root.add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = 60.0
	config.floor_length = 150.0
	stage.build(config)
	var stands := stage.get_node("Grandstands") as Node3D
	check(stands.get_child_count() == 2, "two side stands")
	check(is_equal_approx(stands.position.z, -15.0), "stands start at the conveyor's back end")
	var first_people := {}
	for stand: Node3D in stands.get_children():
		_check_stand(stand, 8, 150.0)
		first_people[stand.name] = _people(stand)
		check(is_equal_approx(stand.scale.z, 1.0), "%s is not stretched" % stand.name)

	# A longer conveyor adds blocks at the front; existing blocks stay put.
	var before := {}
	for stand: Node3D in stands.get_children():
		before[stand.name] = (stand.get_node("Blocks/Block01") as Node3D).global_position
	stage.set_floor_geometry(100.0, 230.0)
	for stand: Node3D in stands.get_children():
		_check_stand(stand, 12, 230.0)
		check((stand.get_node("Blocks/Block01") as Node3D).global_position == before[stand.name], "%s first block moved" % stand.name)
		var grown := _people(stand)
		for key: String in first_people[stand.name]:
			check(grown.has(key), "%s lost a spectator when growing" % stand.name)
	# Shrinking the conveyor (countdown) keeps every block.
	stage.set_floor_geometry(40.0, 100.0)
	for stand: Node3D in stands.get_children():
		check(stand.block_count == 12, "%s shrank" % stand.name)

	# Crowd = goal stand rig: every body bone and all seven hairstyles are present.
	var mesh: ArrayMesh = Kit.mesh()
	var styles := 0
	for uv: Vector2 in mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]:
		styles |= int(uv.y)
	check(styles == 127, "all seven goal-stand hairstyles merged")
	check(Kit.bone_count() == 23, "goal-stand rig has 23 bones")
	check(Kit.frame_rows() > 0, "clips baked")

	if DisplayServer.get_name() != "headless":
		await _screenshots(stage)
	print("SIDE_STAND_BLOCKS ", "PASS" if errors.is_empty() else "FAIL", " ", errors)
	get_tree().quit(0 if errors.is_empty() else 1)


func _check_stand(stand: Node3D, blocks: int, floor_length: float) -> void:
	check(stand.block_count == blocks, "%s has %d blocks (expected %d)" % [stand.name, stand.block_count, blocks])
	check(stand.length() >= floor_length, "%s covers the conveyor" % stand.name)
	var kinds: Array = stand.get_node("Blocks").get_children().map(func(b: Node) -> String: return b.get_meta("kind"))
	check(kinds.count("cap_start") == 1 and kinds.count("cap_end") == 1, "%s has one cap at each end" % stand.name)
	# Consecutive blocks are exactly one block length apart in world Z.
	var zs: Array[float] = []
	for block: Node3D in stand.get_node("Blocks").get_children():
		zs.append(block.global_position.z)
		check(is_equal_approx(block.global_transform.basis.get_scale().z, 1.0), "block is not scaled")
	zs.sort()
	for i: int in range(1, zs.size()):
		check(is_equal_approx(zs[i] - zs[i - 1], StandScript.BLOCK_LENGTH), "%s blocks are contiguous" % stand.name)
	var aisles: Array[float] = stand.aisle_offsets_z()
	check(aisles.size() == blocks - 1, "%s has an aisle between every pair of blocks" % stand.name)
	# Nobody sits in an aisle and every spectator faces the course. The headless
	# dummy renderer cannot read MultiMesh transforms back, so only count there.
	var crowd := stand.get_node("Spectators")
	var total := 0
	var readback := DisplayServer.get_name() != "headless"
	for batch: MultiMeshInstance3D in crowd.get_children():
		if not readback:
			total += batch.multimesh.instance_count
			continue
		for i: int in range(batch.multimesh.instance_count):
			var placed := stand.global_transform * batch.multimesh.get_instance_transform(i)
			total += 1
			for aisle: float in aisles:
				check(absf(placed.origin.z - (stand.global_position.z + aisle)) > 1.0, "%s spectator in an aisle" % stand.name)
			var facing := placed.basis.z.normalized()
			check(facing.x * signf(stand.global_position.x) < -0.99, "%s spectator faces the course" % stand.name)
	check(total == crowd.spectator_count and total > blocks * 40, "%s crowd population %d" % [stand.name, total])
	check(crowd.fan_count > total / 2 and crowd.emote_count > 0, "%s has home fans and party people" % stand.name)


func _people(stand: Node3D) -> Dictionary:
	var people := {}
	if DisplayServer.get_name() == "headless":
		return people
	for batch: MultiMeshInstance3D in stand.get_node("Spectators").get_children():
		for i: int in range(batch.multimesh.instance_count):
			people[str(batch.multimesh.get_instance_transform(i).origin)] = true
	return people


func _screenshots(stage: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var camera := Camera3D.new()
	camera.far = 3000.0
	get_tree().root.add_child(camera)
	camera.make_current()
	var shots := [
		["overview", Vector3(0, 40, -45), Vector3(0, 0, 110), 55.0],
		["right_detail", Vector3(22, 3.2, 50), Vector3(29.5, 1.6, 53), 40.0],
		["left_aisle", Vector3(-20, 6, 20), Vector3(-30, 1.5, 25), 45.0],
	]
	for shot: Array in shots:
		camera.global_position = shot[1]
		camera.look_at(shot[2])
		camera.fov = shot[3]
		for _frame: int in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(OUT + str(shot[0]) + ".png")
	# Verdict reaction: P1 fans cheer, P2 fans despair.
	var crowd_script = load("res://scripts/world/grandstand_crowd.gd")
	for _frame: int in range(40):
		crowd_script.follow_reaction({"amount": 1.0, "team": 1, "verdict": true}, 1.0 / 30.0)
		await get_tree().process_frame
	for side: Array in [["verdict_p1_fans", Vector3(22, 3.2, 50), Vector3(29.5, 1.6, 53)],
			["verdict_p2_fans", Vector3(-22, 3.2, 50), Vector3(-29.5, 1.6, 53)]]:
		camera.global_position = side[1]
		camera.look_at(side[2])
		camera.fov = 40.0
		for _frame: int in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(OUT + str(side[0]) + ".png")
	crowd_script.follow_reaction({}, 10.0)
