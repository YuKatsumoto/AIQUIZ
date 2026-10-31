extends Node

## The side stands' management-sim crowd (docs/crowd_sim.md) on the real stands:
## the stage built as the game builds it (crowd_sim on), driven the way
## game_world._update_crowd() drives it. Checks that the drawn seats and walkers
## follow the sim, and photographs a watched block: empty seats at the start,
## late arrivals coming down the stairs, the snack queue on the rear walkway,
## fans leaving a dull match, the goal race rush back, and the stand from the
## course as a player sees it.
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script tests/crowd_sim_runtime_bootstrap.gd
## Screenshots go to artifacts/crowd_sim/runtime/ (needs a window); under
## --headless only the structural and timing checks run.

const StageScript = preload("res://scripts/world/stage_environment.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const OUT := "res://artifacts/crowd_sim/runtime/"
const DT := 1.0 / 60.0
## The watched block of the right stand (world z 30..50 with the stage below).
const BLOCK := 2

var errors: Array[String] = []
var report := {}
var stage: Node3D
var crowd: Node3D
var mood: CrowdMood
var cues: CrowdCues
var camera: Camera3D
var shots := DisplayServer.get_name() != "headless"
var _spent := 0
var _steps := 0
var _worst := 0
## The worst frame once the match has started (the first frames set up the crowd).
var _worst_running := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_build()
	_aim_at_block()
	await _frames(20)
	_check_start()
	await _shot("01_start")
	await _arrivals()
	await _snacks()
	await _leaving()
	await _goal_race()
	await _follow_one()
	await _vendor()
	await _new_block()
	await _player_view()
	report["update_msec"] = {"average": snappedf(float(_spent) / maxi(1, _steps) / 1000.0, 0.001),
		"worst": snappedf(_worst / 1000.0, 0.001), "worst_running": snappedf(_worst_running / 1000.0, 0.001),
		"frames": _steps}
	report["sim"] = crowd.sim_snapshot()
	print("CROWD_SIM_RUNTIME ", "PASS" if errors.is_empty() else "FAIL", " ",
		JSON.stringify({"errors": errors, "report": report}))
	get_tree().quit(0 if errors.is_empty() else 1)


func _build() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.72, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(25.0), 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	stage = StageScript.new()
	add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = 60.0
	config.floor_length = 150.0
	config.crowd_sim = true
	stage.build(config)
	crowd = stage.get_node("Grandstands/GrandstandRight/Spectators")
	check(crowd.sim != null, "the gameplay stage builds the right stand's crowd as a sim")
	check((stage.get_node("Grandstands/GrandstandLeft/Spectators")).sim != null, "and the left one's")
	mood = CrowdMood.new()
	mood.match_serial = 1
	cues = CrowdCues.new()
	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 45.0
	add_child(camera)
	camera.make_current()


## One frame of the crowd, as game_world._update_crowd() runs it.
func _step() -> void:
	var stands := stage.get_node("Grandstands") as Node3D
	cues.course_z = stands.global_position.z
	cues.update(DT, null, {}, null)
	CrowdScript.follow_cues(cues)
	var started := Time.get_ticks_usec()
	CrowdScript.update_sim(mood, DT, camera)
	var spent := Time.get_ticks_usec() - started
	_spent += spent
	_steps += 1
	_worst = maxi(_worst, spent)
	if _steps > 30:
		_worst_running = maxi(_worst_running, spent)


func _frames(count: int) -> void:
	for _i in range(count):
		_step()
		await get_tree().process_frame


func _block_center() -> Vector3:
	return crowd.global_transform * Vector3(4.0, 1.5, float(crowd._centers[BLOCK]))


## A view across the watched block from the course: its stairs, rows and walkway.
func _aim_at_block() -> void:
	var center := _block_center()
	camera.global_position = center + Vector3(-17.0, 5.5, -13.0)
	camera.look_at(center + Vector3(0.5, 0.4, 0.0))
	camera.fov = 45.0


## Down into the stairwell beside the block's aisle (start side), from above the
## sea behind the stand (the course side only sees its top steps).
func _aim_at_stairwell() -> void:
	var paths: StandPaths = crowd.sim.paths
	var aisle: float = float(crowd._centers[BLOCK]) - StandPaths.BLOCK_HALF
	var middle := (paths.stairwell_from.x + paths.stairwell_from.y) * 0.5
	var well := crowd.global_transform * Vector3((paths.stairwell_x.x + paths.stairwell_x.y) * 0.5, 1.8, aisle + middle)
	camera.global_position = well + Vector3(3.5, 7.5, 5.0)
	camera.look_at(well)
	camera.fov = 45.0


## Down onto the rear walkway beside the block's booth, where the snack queue forms.
func _aim_at_booth() -> void:
	var booth := crowd.global_transform * Vector3(9.0, 2.7, float(crowd._centers[BLOCK]) - 4.5)
	camera.global_position = booth + Vector3(-9.0, 7.0, -7.0)
	camera.look_at(booth)
	camera.fov = 45.0


func _shot(name: String) -> void:
	if not shots:
		await _frames(2)
		return
	for _i in range(3):
		_step()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


## The drawn crowd follows the sim: each block draws exactly its seated people,
## the walkers batch exactly the people on foot.
func _check_drawn(label: String) -> void:
	var sim: CrowdSim = crowd.sim
	var seated := {}
	for index: int in range(sim.people.size()):
		if sim.seat_view(index).shown:
			var block := sim.people[index].block
			seated[block] = int(seated.get(block, 0)) + 1
	for block: int in crowd._batches:
		var drawn := 0
		for batch: MultiMeshInstance3D in crowd._batches[block]:
			drawn += batch.multimesh.visible_instance_count
		check(drawn == int(seated.get(block, 0)), "%s: block %d draws its %d seated people (%d)" % [label, block,
			int(seated.get(block, 0)), drawn])
	var walkers := crowd.get_node("Walkers") as MultiMeshInstance3D
	check(walkers.multimesh.visible_instance_count == sim.walkers.size() + sim.vendors.size(),
		"%s: every walker and vendor is drawn" % label)


func _check_start() -> void:
	var sim: CrowdSim = crowd.sim
	report["start"] = sim.snapshot()
	check(sim.present_share() > 0.58 and sim.present_share() < 0.75, "the match starts with empty seats (%.2f)" % sim.present_share())
	check(sim.paths.aisles.size() >= 7 and sim.paths.booths.size() >= 5, "the stand tells the sim its aisles and booths")
	var watched: PackedByteArray = crowd._watched_blocks(camera)
	check(watched.size() > BLOCK and watched[BLOCK] == 1, "the camera watches block %d (%s)" % [BLOCK, watched])
	_check_drawn("start")


func _people_in(block: int) -> Array[int]:
	var out: Array[int] = []
	var sim: CrowdSim = crowd.sim
	for index: int in range(sim.people.size()):
		if sim.people[index].block == block:
			out.append(index)
	return out


func _arrivals() -> void:
	var sim: CrowdSim = crowd.sim
	var most := 0
	var shot := false
	for _i in range(int(30.0 / DT)):
		_step()
		await get_tree().process_frame
		most = maxi(most, sim.walkers.size())
		if not shot and sim.walkers.size() >= 4:
			var on_stairs := 0
			for w: CrowdSim.Walker in sim.walkers:
				on_stairs += 1 if w.position.x > 1.5 and w.position.x < 8.0 else 0
			if on_stairs >= 2:
				await _shot("02_arrivals")
				shot = true
	if not shot:
		await _shot("02_arrivals")
	report["arrivals_most_walkers"] = most
	check(most >= 3, "late arrivals walk into the watched block (%d)" % most)
	_check_drawn("arrivals")
	# The way in: up out of the stairwell beside the block's aisle. Three people of
	# the block who use that aisle come back from an errand.
	_aim_at_stairwell()
	var aisle: float = float(crowd._centers[BLOCK]) - StandPaths.BLOCK_HALF
	var watched: PackedByteArray = crowd._watched_blocks(camera)
	report["stairwell_view_watches"] = watched[BLOCK] == 1
	check(watched[BLOCK] == 1, "the stairwell view still watches block %d" % BLOCK)
	var sent := 0
	for index: int in _people_in(BLOCK):
		var p := sim.people[index]
		if sent < 3 and p.state == CrowdSim.State.SEATED and not p.fixed and p.aisle == aisle:
			sim._set_away(p, CrowdSim.Away.ERRAND)
			p.errand = CrowdSim.Errand.TOILET
			p.until = sim.now
			sim.changed[index] = true
			sent += 1
	var climbing := 0
	for _i in range(int(30.0 / DT)):
		_step()
		await get_tree().process_frame
		var inside := 0
		for w: CrowdSim.Walker in sim.walkers:
			var along := w.position.z - aisle
			if w.position.x > sim.paths.stairwell_x.x and along > sim.paths.stairwell_from.x and along < sim.paths.stairwell_from.y:
				inside += 1
				check(w.position.y < sim.paths.walkway_y + 0.05 and w.position.y > sim.paths.deck_y - 0.05,
					"people on the stairwell stand on its steps (%.2f)" % w.position.y)
		climbing = maxi(climbing, inside)
		if inside >= 2:
			break
	await _shot("02_stairwell")
	report["stairwell_most"] = climbing
	check(climbing >= 1, "people come and go by the stairwell (%d)" % climbing)
	_aim_at_block()


func _snacks() -> void:
	var sim: CrowdSim = crowd.sim
	# They all walk to the kiosk here (the vendors are _vendor()'s).
	sim.call_share = 0.0
	var hungry := 0
	for index: int in _people_in(BLOCK):
		var p := sim.people[index]
		if p.state == CrowdSim.State.SEATED and p.can_eat and hungry < 7:
			p.hunger = 1.0
			hungry += 1
	var queued := 0
	var shot := false
	_aim_at_booth()
	# The queue at the block's own booth, on the start side (the hungry sit there).
	var center: float = crowd._centers[BLOCK]
	var face := Vector2(NAN, 0.0)
	for candidate: Vector2 in sim.paths.booths_from(center - StandPaths.BLOCK_HALF):
		if absf(candidate.x - (center - sim.paths.booth_half)) < 0.01:
			face = candidate
	check(not is_nan(face.x), "the block's booth faces its aisle")
	for _i in range(int(45.0 / DT)):
		_step()
		await get_tree().process_frame
		# People join the line as they stand up; count the ones standing in it.
		var line := 0
		for w: CrowdSim.Walker in sim._queues.get(face, []):
			line += 1 if sim._in_queue(w) else 0
		queued = maxi(queued, line)
		if not shot and line >= 3:
			await _shot("03_queue")
			shot = true
	if not shot:
		await _shot("03_queue")
	await _frames(int(30.0 / DT))
	var eating := 0
	for index: int in _people_in(BLOCK):
		eating += 1 if sim.people[index].food != 0 else 0
	report["snacks"] = {"queued_most": queued, "served": sim.stats.served, "eating": eating}
	check(queued >= 2, "a queue forms at the booth (%d)" % queued)
	check(int(sim.stats.served) >= 3, "people are served (%d)" % int(sim.stats.served))
	check(eating >= 3, "back in their seats with a snack (%d)" % eating)
	_check_drawn("snacks")
	sim.call_share = CrowdSim.CALL_SHARE
	_aim_at_block()
	await _shot("04_eating")


func _leaving() -> void:
	var sim: CrowdSim = crowd.sim
	var before := sim.present_share()
	var left_before := int(sim.stats.left)
	# A dull match the right stand's player is losing (late arrivals still come in).
	mood.interest = 0.2
	mood.morale = {1: 0.1, 2: 0.8}
	var most := 0
	var shot := false
	for _i in range(int(40.0 / DT)):
		_step()
		await get_tree().process_frame
		most = maxi(most, sim.walkers.size())
		if not shot and sim.walkers.size() >= 8:
			await _shot("05_leaving")
			shot = true
	if not shot:
		await _shot("05_leaving")
	var left := int(sim.stats.left) - left_before
	report["leaving"] = {"before": snappedf(before, 0.01), "after": snappedf(sim.present_share(), 0.01), "left": left,
		"walkers_most": most}
	check(left >= 40, "fans leave a dull match (%d)" % left)
	check(sim.present_share() < before, "the stand empties (%.2f -> %.2f)" % [before, sim.present_share()])
	_check_drawn("leaving")


func _goal_race() -> void:
	var sim: CrowdSim = crowd.sim
	mood.interest = 1.0
	mood.morale = {1: 0.7, 2: 0.7}
	mood.hurry = true
	var hurried := 0
	for _i in range(int(1.5 / DT)):
		_step()
		await get_tree().process_frame
		for w: CrowdSim.Walker in sim.walkers:
			hurried = maxi(hurried, 1 if w.hurried else 0)
	await _shot("06_goal_race")
	await _frames(int(25.0 / DT))
	var errands := 0
	for p: CrowdSim.Person in sim.people:
		errands += 1 if p.state == CrowdSim.State.AWAY and p.away == CrowdSim.Away.ERRAND else 0
	report["goal_race"] = {"hurried": hurried, "away_on_errands": errands, "walkers": sim.walkers.size()}
	check(errands == 0, "nobody is out on an errand in the goal race (%d)" % errands)
	_check_drawn("goal_race")
	mood.hurry = false


## One spectator up close, through a snack run: getting up, walking, buying at
## the window and sitting down again (the walking crowd's clips).
func _follow_one() -> void:
	var sim: CrowdSim = crowd.sim
	mood.interest = 0.45
	mood.hurry = false
	var who := -1
	for index: int in _people_in(BLOCK):
		var p := sim.people[index]
		if p.state == CrowdSim.State.SEATED and p.can_eat and p.food == 0 and p.row == 1 				and p.seat.z < float(crowd._centers[BLOCK]) - 3.0:
			who = index
			break
	check(who >= 0, "somebody to follow")
	if who < 0:
		return
	var p := sim.people[who]
	# This one walks to the kiosk (the vendors are _vendor()'s).
	sim.call_share = 0.0
	p.hunger = 1.0
	var seen := {}
	var shots := {}
	for _i in range(int(70.0 / DT)):
		_step()
		await get_tree().process_frame
		var w: CrowdSim.Walker = null
		for walker: CrowdSim.Walker in sim.walkers:
			if walker.person == who:
				w = walker
		var key := ""
		var at := Vector3.ZERO
		if p.state == CrowdSim.State.STANDING_UP and now_since(p) > 0.45:
			key = "08_stand_up"
			at = p.spot
		elif w != null and w.clip == &"SPEC_Walk" and w.position.x > 3.0 and w.position.x < 7.0:
			key = "09_walk"
			at = w.position
		elif w != null and w.clip == &"SPEC_Buy" and w.phase > 0.6:
			key = "10_buy"
			at = w.position
		elif p.state == CrowdSim.State.SITTING_DOWN and now_since(p) > 0.5:
			key = "11_sit_down"
			at = p.spot
		if w != null:
			seen[String(w.clip)] = true
		if key != "" and not shots.has(key):
			shots[key] = true
			var target := crowd.global_transform * (at + Vector3(0.0, 0.9, 0.0))
			camera.global_position = target + Vector3(-3.6, 1.6, -2.4)
			camera.look_at(target)
			camera.fov = 40.0
			await _shot(key)
		if shots.has("11_sit_down"):
			break
	report["follow"] = {"clips": seen.keys(), "shots": shots.keys(), "food": p.food}
	for clip: String in ["SPEC_Walk", "SPEC_Buy"]:
		check(seen.has(clip), "the snack run plays %s" % clip)
	check(shots.size() == 4, "the snack run is photographed whole (%s)" % [shots.keys()])
	sim.call_share = CrowdSim.CALL_SHARE
	_aim_at_block()


## A beer vendor climbs to a raised hand in the watched block and hands a cup
## along the row.
func _vendor() -> void:
	var sim: CrowdSim = crowd.sim
	mood.interest = 0.45
	check(sim.vendors.size() >= 1, "the side stand has beer vendors (%d)" % sim.vendors.size())
	var who := -1
	for index: int in _people_in(BLOCK):
		var p := sim.people[index]
		if p.state == CrowdSim.State.SEATED and p.can_eat and p.food == 0 and p.row == 2 and not p.calling \
				and absf(p.seat.z - p.aisle) > 4.0 and absf(p.seat.z - p.aisle) < 6.5:
			who = index
			break
	check(who >= 0, "somebody to serve")
	if who < 0:
		return
	var p := sim.people[who]
	p.calling = true
	p.call_since = sim.now
	sim._calls.append(who)
	sim.changed[who] = true
	var shot := false
	var waited := 0.0
	while waited < 150.0 and int(p.food) != CrowdSim.FOOD_DRINK:
		_step()
		await get_tree().process_frame
		waited += DT
		var v: CrowdSim.Vendor = null
		for vendor: CrowdSim.Vendor in sim.vendors:
			if vendor.customer == who:
				v = vendor
		if not shot and v != null and v.state == CrowdSim.VendorState.HANDING and v.step >= 2:
			var target := crowd.global_transform * Vector3(v.position.x + 0.8, v.position.y + 1.0, (v.position.z + p.seat.z) * 0.5)
			camera.global_position = target + Vector3(-4.2, 2.2, -3.0)
			camera.look_at(target)
			camera.fov = 45.0
			await _shot("12_vendor")
			shot = true
	await _frames(int(4.0 / DT))
	report["vendor"] = {"seconds": snappedf(waited, 0.1), "delivered": sim.stats.delivered, "food": p.food, "shot": shot}
	check(p.food == CrowdSim.FOOD_DRINK, "the vendor's cup reaches the customer in %.0f s" % waited)
	check(shot, "the hand-over is photographed")
	_check_drawn("vendor")
	_aim_at_block()


## The endless course grows the stand by a block during the match: its seats are
## empty at first and fill as people arrive.
func _new_block() -> void:
	var stand := crowd.get_parent()
	var index: int = stand.block_count
	stand.ensure_blocks(index + 1)
	var drawn := func() -> int:
		var count := 0
		for batch: MultiMeshInstance3D in crowd._batches[index]:
			count += batch.multimesh.visible_instance_count
		return count
	check(crowd._batches.has(index), "the new block has its batches")
	if not crowd._batches.has(index):
		return
	var at_first: int = drawn.call()
	# Only the cheer leader and the pairs (who never leave) sit there from the start.
	var regulars := 0
	for person: int in _people_in(index):
		regulars += 1 if crowd.sim.people[person].fixed else 0
	await _frames(int(120.0 / DT))
	var later: int = drawn.call()
	report["new_block"] = {"at_first": at_first, "regulars": regulars, "after_120s": later}
	check(at_first == regulars, "a block added during the match opens empty but for its regulars (%d drawn, %d regulars)"
		% [at_first, regulars])
	check(later > 40, "people arrive in the new block (%d)" % later)
	_check_drawn("new block")


func now_since(p: CrowdSim.Person) -> float:
	return crowd.sim.now - p.since


## The stand as a player sees it: from the course, looking ahead.
func _player_view() -> void:
	mood.interest = 0.45
	await _frames(int(20.0 / DT))
	camera.global_position = Vector3(1.5, 3.2, crowd.global_transform.origin.z + 8.0)
	camera.look_at(camera.global_position + Vector3(0.0, -0.15, 1.0))
	camera.fov = 50.0
	await _shot("07_player_view")
