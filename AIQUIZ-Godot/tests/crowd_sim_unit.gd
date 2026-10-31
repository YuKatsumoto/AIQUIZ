extends Node

## The side stands' management-sim crowd (docs/crowd_sim.md) without drawing:
## the walk's geometry on the stand blocks, the attendance at the start and the
## late arrivals, people walking where the camera looks (and only there), the
## snack queue, the goal race sending everybody back, leaving in a dull lopsided
## match down to the floor and coming back, CrowdMood's reading of the match, and
## the cost of a frame.
## Run: Godot --headless --path . --script tests/crowd_sim_bootstrap.gd

const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const LAYOUT_PATH := "res://assets/aiquiz_stadium/aiquiz_stadium_stand_blocks.json"
const DT := 1.0 / 60.0
const BLOCKS := 10
## The stand's rows (dimensions.json side_stand_block): seat x, cushion top.
const SEAT_X: Array[float] = [1.15, 2.4, 3.65, 4.9, 6.15, 7.4]
const CUSHION_Y: Array[float] = [0.865, 1.265, 1.665, 2.065, 2.465, 2.865]

var checks := 0
var failures: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	_check_clips()
	_check_paths()
	_check_mood()
	_check_attendance()
	_check_walkers()
	_check_snack()
	_check_goal_race()
	_check_leaving()
	_check_matches()
	_check_new_block()
	_check_vendors()
	_check_cost()
	print("CROWD_SIM_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"report": report}))
	get_tree().quit(0 if failures.is_empty() else 1)


## The stand blocks' walk as exported with them (aiquiz_stadium_stand_blocks.json).
func _walk() -> Dictionary:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return (layout as Dictionary).get("walk", {}) if layout is Dictionary else {}


## A right stand of BLOCKS blocks as aiquiz_stadium_stand.gd lays it out: block 0
## is the far cap (no aisle), the last one the near cap, every block but the far
## cap owns the aisle on its -Z edge.
func _paths() -> StandPaths:
	var centers: Array[float] = []
	var kinds: Array[String] = []
	var aisles: Array[float] = []
	for index: int in range(BLOCKS):
		var center := 20.0 * (index + 0.5)
		centers.append(center)
		kinds.append("cap_end" if index == 0 else ("cap_start" if index == BLOCKS - 1 else "bay"))
		if index > 0:
			aisles.append(center - 10.0)
	var paths := StandPaths.new()
	paths.configure(_walk())
	paths.set_blocks(centers, kinds, aisles)
	return paths


## Every seat of every block taken, people as GrandstandCrowd hands them over.
func _sim(seed_value := 7, pool := 24, team_of := Callable(), vendors := 0) -> CrowdSim:
	var sim := CrowdSim.new(_paths(), seed_value, pool, vendors)
	var floor_point := Kit.stand_floor()
	var basis := Basis(Vector3.UP, -PI * 0.5)
	for block: int in range(BLOCKS):
		var center := 20.0 * (block + 0.5)
		for row: int in range(6):
			var previous := -1
			for k: int in range(19):
				var seat := Vector3(SEAT_X[row] + 0.06, CUSHION_Y[row], center - 8.28 + 0.92 * k)
				var team: int = team_of.call(block, row, k) if team_of.is_valid() else (k % 3)
				previous = sim.add_person(block, seat, Transform3D(basis, seat) * floor_point, row, team,
					row == 1 and k == 9, true, previous)
	return sim


func _mood(serial := 1) -> CrowdMood:
	var mood := CrowdMood.new()
	mood.match_serial = serial
	return mood


func _run(sim: CrowdSim, mood: CrowdMood, watched: PackedByteArray, seconds: float, from := 0.0) -> float:
	var time := from
	for _i: int in range(int(round(seconds / DT))):
		time += DT
		sim.tick(time, DT, mood, watched)
		sim.changed.clear()
	return time


func _watch(blocks: Array) -> PackedByteArray:
	var watched := PackedByteArray()
	watched.resize(BLOCKS)
	for block: int in blocks:
		watched[block] = 1
	return watched


## The walking crowd's clips from goal_stand_spectator.glb (author_crowd_walks.py).
func _check_clips() -> void:
	Kit.mesh()
	var clips := {}
	for clip: StringName in [&"SPEC_StandUp", &"SPEC_SitDown", &"SPEC_StandIdle", &"SPEC_Walk", &"SPEC_Run",
			&"SPEC_StandPhone", &"SPEC_Buy", &"SPEC_RaiseHand", &"SPEC_PassItemL", &"SPEC_PassItemR", &"SPEC_VendorHand"]:
		var index := Kit.clip_index(clip)
		check(index >= 0 and index < Kit.MAX_CLIPS, "%s is baked" % clip)
		clips[String(clip)] = snappedf(Kit.clip_seconds(clip), 0.01)
	report["clips"] = clips
	check(Kit.CLIPS.size() <= Kit.MAX_CLIPS, "the clip table fits the shader (%d)" % Kit.CLIPS.size())
	check(absf(Kit.clip_seconds(&"SPEC_StandUp") - 1.033) < 0.05 and absf(Kit.clip_seconds(&"SPEC_SitDown") - 1.3) < 0.05,
		"getting up and sitting down are the authored clips, not stand-ins")
	var rise: Array = (Kit._clip_meta.get("SPEC_StandUp", {}) as Dictionary).get("rise", [])
	check(rise.size() == 4 and float(rise[0]) > 0.0 and float(rise[1]) < 1.0, "getting up lifts the hips along its measured rise (%s)" % [rise])
	var walk := Kit.clip_ground_speed(&"SPEC_Walk")
	var run := Kit.clip_ground_speed(&"SPEC_Run")
	report["ground_speed"] = {"walk": walk, "run": run}
	check(walk > 0.7 and walk < 1.2 and run > walk * 1.4, "walking and running cover the ground at their own paces")
	check(Kit.FREE_LEGS.has(&"SPEC_Walk") and not Kit.FREE_LEGS.has(&"SPEC_StandUp"), "people on foot keep their legs, getting up is seated")


func _check_paths() -> void:
	var walk := _walk()
	check(not walk.is_empty(), "the stand blocks export their walk")
	var paths := _paths()
	report["walkway_x"] = [paths.walkway_x.x, paths.walkway_x.y]
	check(paths.walkway_x.y - paths.walkway_x.x > 4.0, "the rear walkway is wide enough to walk behind the booths")
	var floor_point := Kit.stand_floor()
	report["stand_floor"] = [snappedf(floor_point.x, 0.001), snappedf(floor_point.y, 0.001), snappedf(floor_point.z, 0.001)]
	var basis := Basis(Vector3.UP, -PI * 0.5)
	for row: int in range(6):
		var seat := Vector3(SEAT_X[row] + 0.06, CUSHION_Y[row], 30.0)
		var spot := Transform3D(basis, seat) * floor_point
		check(absf(spot.y - paths.row_y(row)) < 0.05, "row %d: the feet of a risen spectator rest on its tread (%.3f)" % [row, spot.y])
		check(absf(paths.floor_y(spot.x, spot.z) - paths.row_y(row)) < 0.001, "row %d: the spot in front of the seat is on its tread" % row)
		var up := paths.seat_to_walkway(spot, row, paths.nearest_aisle(spot.z))
		check(absf(up[up.size() - 1].y - paths.walkway_y) < 0.001, "row %d: the way up ends on the walkway" % row)
		for point: Vector3 in up:
			check(point.x > paths.front_x - 0.6 and point.x < paths.walkway_x.y, "row %d: the way stays on the stand" % row)
	check(absf(paths.floor_y(0.2, 30.0) - paths.deck_y) < 0.001, "the front deck")
	check(absf(paths.floor_y(4.0, 40.3) - (paths.row_base_y + 0.2 * 5.0)) < 0.001, "a stair of the aisle at z 40")
	check(absf(paths.floor_y(9.0, 31.0) - paths.walkway_y) < 0.001, "the rear walkway")
	check(absf(paths.floor_y(11.5, 32.0) - paths.walkway_y) < 0.001, "the walkway behind the booth")
	# The stairwell beside the aisle at z 40: steps down to the landing on the deck.
	var exit := paths.to_exit(40.0)
	check(absf(exit[0].y - paths.walkway_y) < 0.001, "the way out starts on the walkway")
	check(absf(exit[1].y - paths.deck_y) < 0.001, "and ends on the stairwell's landing (%.2f)" % exit[1].y)
	var last := paths.walkway_y
	var descends := true
	for k: int in range(1, 40):
		var z := lerpf(exit[0].z, exit[1].z, k / 40.0)
		var y := paths.floor_y(exit[0].x, z, 40.0)
		descends = descends and y <= last + 1e-4
		last = y
	check(descends, "the stairwell only goes down towards its door")
	check(paths.pace(exit[0].x, 42.5, 40.0) < 1.0, "people slow down on the stairwell")
	var back := paths.from_exit(40.0)
	check(back[0] == exit[1] and back[1] == exit[0], "people come up the way others go down")
	var home := paths.home_from(Vector3(exit[0].x, 1.0, 42.5), Vector3(5.0, 1.92, 45.0), 4, 40.0)
	check(absf(home[1].z - exit[0].z) < 0.001, "from the stairwell the way home first climbs out of it")
	check(paths.nearest_aisle(31.0) == 40.0 and paths.nearest_aisle(29.0) == 20.0, "the nearest aisle")
	var faces := paths.booths_from(40.0)
	check(faces.size() == 2, "two booths along the walkway from an aisle between bays (%d)" % faces.size())
	for face: Vector2 in faces:
		var tail := paths.queue_point(face, StandPaths.QUEUE_MAX - 1)
		check(absf(tail.z - 40.0) > paths.aisle_half + 0.3, "a full queue stays clear of the aisle")
		check(tail.z < 40.0 + paths.stairwell_from.x or tail.z > 40.0 + paths.stairwell_from.y or tail.x < paths.stairwell_x.x,
			"a full queue stays clear of the stairwell")
		check(absf(paths.queue_point(face, 1).z - 40.0) < absf(paths.queue_point(face, 0).z - 40.0), "the queue grows towards the aisle")
	check(paths.booths_from(180.0).size() == 1, "the near cap has no booth")


func _check_mood() -> void:
	var mood := CrowdMood.new()
	var state := QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_WAITING_START
	mood.update(DT, state)
	check(mood.match_serial == 1, "a new match starts a new crowd")
	state.game_state = Constants.STATE_PLAYING
	var start := mood.interest
	for _i: int in range(int(60.0 / DT)):
		mood.update(DT, state)
	check(mood.interest < start - 0.05, "a minute without events drags (%.2f -> %.2f)" % [start, mood.interest])
	var dull := mood.interest
	mood.on_correct(1)
	for _i: int in range(int(3.0 / DT)):
		mood.update(DT, state)
	check(mood.interest > dull, "an answer wakes the crowd up")
	mood.on_out(2)
	check(mood.morale_for(2) < 0.3 and mood.morale_for(1) > 0.6, "falling out sinks the player's fans (%.2f, %.2f)" % [mood.morale_for(1), mood.morale_for(2)])
	state.p2_alive = false
	for _i: int in range(int(30.0 / DT)):
		mood.update(DT, state)
	check(mood.interest < CrowdMood.BASE_INTEREST, "a lopsided match is less worth watching (%.2f)" % mood.interest)
	state.game_state = Constants.STATE_GOAL_RACE
	for _i: int in range(int(5.0 / DT)):
		mood.update(DT, state)
	check(mood.hurry and mood.interest > 0.95, "the goal race holds everybody")
	state.game_state = Constants.STATE_RESULT_CEREMONY
	mood.update(DT, state)
	state.game_state = Constants.STATE_WAITING_START
	mood.update(DT, state)
	check(mood.match_serial == 2 and absf(mood.morale_for(2) - CrowdMood.MORALE_START) < 0.001, "the next match starts afresh")
	state.num_players = 1
	mood.on_miss(1)
	mood.update(DT, state)
	check(mood.morale_for(2) == mood.morale_for(1), "with one player both stands follow P1")


func _check_attendance() -> void:
	var sim := _sim()
	var mood := _mood()
	var nobody := _watch([])
	var time := _run(sim, mood, nobody, DT)
	var at_start := sim.present_share()
	report["present_at_start"] = snappedf(at_start, 0.001)
	check(at_start > 0.6 and at_start < 0.72, "about two thirds are seated at the start (%.3f)" % at_start)
	time = _run(sim, mood, nobody, 160.0, time)
	report["present_after_160s"] = snappedf(sim.present_share(), 0.001)
	check(sim.present_share() > 0.84, "the late ones have come (%.3f)" % sim.present_share())
	check(sim.walkers.is_empty(), "nobody walks where the camera does not look")
	check(int(sim.stats.instant) > 0, "out of sight people simply appear")
	# The same seed gives the same crowd.
	var again := _sim()
	_run(again, _mood(), nobody, DT)
	check(absf(again.present_share() - at_start) < 1e-6, "the same seed gives the same attendance")
	var other := _sim()
	_run(other, _mood(2), nobody, DT)
	check(absf(other.present_share() - at_start) > 1e-6, "another match rolls a new crowd")


func _check_walkers() -> void:
	var sim := _sim(11, 24)
	var mood := _mood()
	var watched := _watch([4])
	var time := 0.0
	var most := 0
	var arrived := 0
	var outside := 0
	var sat := 0
	var shown_while_walking := 0
	for _i: int in range(int(150.0 / DT)):
		time += DT
		sim.tick(time, DT, mood, watched)
		for index: int in sim.changed:
			var view := sim.seat_view(index)
			if sim.people[index].state == CrowdSim.State.SITTING_DOWN:
				sat += 1
			if view.shown and sim.people[index].state == CrowdSim.State.WALKING:
				shown_while_walking += 1
		sim.changed.clear()
		most = maxi(most, sim.walkers.size())
		for w: CrowdSim.Walker in sim.walkers:
			if sim.people[w.person].block != 4:
				outside += 1
			var p := w.position
			if p.x < -0.6 or p.x > sim.paths.walkway_x.y or p.y < sim.paths.deck_y - 0.05 or p.y > sim.paths.walkway_y + 0.05 \
					or p.z < 60.0 or p.z > 112.0:
				outside += 1
		arrived = int(sim.stats.came)
	report["walkers_most"] = most
	report["walk_stats"] = sim.stats.duplicate()
	check(most >= 3, "late arrivals walk in the watched block (%d at most)" % most)
	check(most <= 24, "the pool holds (%d)" % most)
	check(outside == 0, "walkers stay on the watched block's walks")
	check(sat > 3, "walkers sit down in their seats (%d)" % sat)
	check(shown_while_walking == 0, "a walking person's seat is empty")
	check(arrived > 0, "people came")
	# Looking away: the walkers finish at once.
	sim.tick(time + DT, DT, mood, _watch([]))
	check(sim.walkers.is_empty(), "walkers out of sight finish at once")


func _check_snack() -> void:
	var sim := _sim(5, 24)
	var mood := _mood()
	var watched := _watch([4])
	var time := _run(sim, mood, watched, DT)
	# Everybody is in; make one hungry person in the watched block (row 2).
	var hungry := -1
	for index: int in range(sim.people.size()):
		var p := sim.people[index]
		if p.block == 4 and p.row == 2 and p.state == CrowdSim.State.SEATED and not p.fixed:
			hungry = index
			break
	check(hungry >= 0, "a seated person to feed")
	if hungry < 0:
		return
	for p: CrowdSim.Person in sim.people:
		p.hunger_rate = 0.0
		p.bladder_rate = 0.0
		p.hunger = 0.0
		p.bladder = 0.0
		p.arrive_at = INF
	sim.people[hungry].hunger = 1.0
	var queued := false
	var bought := false
	var served_food := 0
	for _i: int in range(int(90.0 / DT)):
		time += DT
		sim.tick(time, DT, mood, watched)
		sim.changed.clear()
		queued = queued or int(sim.snapshot().queued) > 0
		for w: CrowdSim.Walker in sim.walkers:
			bought = bought or (w.clip == &"SPEC_Buy" and not w.loop)
		if sim.people[hungry].state == CrowdSim.State.SEATED and int(sim.stats.served) > 0:
			served_food = sim.people[hungry].food
			break
	report["snack"] = {"queued": queued, "served": sim.stats.served, "food": served_food, "seconds": snappedf(time, 0.1)}
	check(queued, "the hungry one queues at the booth")
	check(bought, "and reaches for the snack at the window (once)")
	check(int(sim.stats.served) == 1, "served at the booth")
	check(served_food != 0, "back in the seat with the snack (%d)" % served_food)


func _check_goal_race() -> void:
	var sim := _sim(9, 24)
	var mood := _mood()
	var watched := _watch([4])
	var time := _run(sim, mood, watched, DT)
	for p: CrowdSim.Person in sim.people:
		p.hunger_rate = 0.0
		p.bladder_rate = 0.0
		p.arrive_at = INF
	# Three people in the watched block need the toilet.
	var sent: Array[int] = []
	for index: int in range(sim.people.size()):
		var p := sim.people[index]
		if p.block == 4 and p.state == CrowdSim.State.SEATED and not p.fixed and sent.size() < 3:
			p.bladder = 1.0
			sent.append(index)
	time = _run(sim, mood, watched, 4.0, time)
	check(sim.walkers.size() > 0, "people head for the toilet (%d)" % sim.walkers.size())
	mood.hurry = true
	mood.interest = 1.0
	var hurried := false
	for _i: int in range(int(1.0 / DT)):
		time += DT
		sim.tick(time, DT, mood, watched)
		sim.changed.clear()
		for w: CrowdSim.Walker in sim.walkers:
			hurried = hurried or (w.hurried and w.goal == CrowdSim.Goal.SEAT)
	check(hurried, "the goal race turns them back, hurrying")
	var running := false
	for _i: int in range(int(1.0 / DT)):
		time += DT
		sim.tick(time, DT, mood, watched)
		sim.changed.clear()
		for w: CrowdSim.Walker in sim.walkers:
			running = running or (w.hurried and w.clip == &"SPEC_Run" and w.still == 0.0)
	check(running, "hurrying back, they run")
	time = _run(sim, mood, watched, 40.0, time)
	for index: int in sent:
		check(sim.people[index].state == CrowdSim.State.SEATED, "back in the seat for the goal race (%s)"
			% CrowdSim.State.keys()[sim.people[index].state])
	var away := 0
	for p: CrowdSim.Person in sim.people:
		away += 1 if p.state == CrowdSim.State.AWAY and p.away != CrowdSim.Away.NOT_ARRIVED else 0
	check(away == 0, "nobody is away during the goal race (%d)" % away)


func _check_leaving() -> void:
	# P2's fans on the near half, P1's on the far half, neutral every third seat.
	var team_of := func(block: int, _row: int, k: int) -> int:
		return 0 if k % 3 == 0 else (2 if block >= BLOCKS / 2 else 1)
	var sim := _sim(3, 24, team_of)
	var mood := _mood()
	var nobody := _watch([])
	var time := _run(sim, mood, nobody, 160.0)
	var before := sim.present_share()
	# A dull, lopsided match: P2 is far behind.
	mood.interest = 0.15
	mood.morale = {1: 0.8, 2: 0.1}
	time = _run(sim, mood, nobody, 120.0, time)
	var left := {0: 0, 1: 0, 2: 0}
	var fans := {0: 0, 1: 0, 2: 0}
	for p: CrowdSim.Person in sim.people:
		fans[p.team] += 1
		if p.state == CrowdSim.State.AWAY and p.away == CrowdSim.Away.LEFT:
			left[p.team] += 1
	var low := sim.present_share()
	report["leaving"] = {"before": snappedf(before, 0.001), "after": snappedf(low, 0.001), "left": left}
	check(low < before - 0.25, "a dull lopsided match empties the stand (%.3f -> %.3f)" % [before, low])
	check(low >= CrowdSim.FLOOR_SHARE - 0.01, "but not below the floor (%.3f)" % low)
	check(float(left[2]) / fans[2] > float(left[1]) / fans[1], "the losing side's fans leave first (%s)" % [left])
	for p: CrowdSim.Person in sim.people:
		if p.fixed:
			check(p.state == CrowdSim.State.SEATED, "cheer leaders stay")
	# The match turns exciting again: some come back.
	mood.interest = 0.95
	mood.morale = {1: 0.7, 2: 0.7}
	time = _run(sim, mood, nobody, 120.0, time)
	report["leaving"]["back"] = snappedf(sim.present_share(), 0.001)
	check(sim.present_share() > low + 0.1, "an exciting match brings people back (%.3f)" % sim.present_share())


# ------------------------------------------------------------------ whole matches

const MATCH_DT := 1.0 / 30.0
## Every this many seconds a scripted match samples both stands.
const SAMPLE_SECONDS := 10.0


## Both stands of a scripted match: the right one cheers P1, the left one P2
## (GrandstandCrowd's shares: 55 % home, 12 % away, the rest neutral).
func _stands(seed_value: int) -> Array[CrowdSim]:
	var out: Array[CrowdSim] = []
	for home: int in [1, 2]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 31 + home
		var team_of := func(_block: int, _row: int, _k: int) -> int:
			var roll := rng.randf()
			return home if roll < 0.55 else ((3 - home) if roll < 0.67 else 0)
		out.append(_sim(seed_value + home, 24, team_of))
	return out


## Plays `timeline` ([seconds, action, value]) for `seconds` on both stands and
## samples them: {"t", "right", "left", "interest"} arrays plus the stands' stats.
## Actions: state, correct, miss, hurt, out, result (the winner), dance.
func _play_match(players: int, mode: String, seconds: float, timeline: Array) -> Dictionary:
	var state := QuizGameState.new()
	state.num_players = players
	state.mode = mode
	state.game_state = Constants.STATE_WAITING_START
	var mood := CrowdMood.new()
	var cues := CrowdCues.new()
	var stands := _stands(players * 100 + seconds)
	var watched := _watch([3, 4, 5])
	var curve := {"t": [], "right": [], "left": [], "interest": []}
	var events := timeline.duplicate()
	events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var time := 0.0
	var next_sample := 0.0
	while time < seconds:
		while not events.is_empty() and float(events[0][0]) <= time:
			var event: Array = events.pop_front()
			var who: Variant = event[2]
			match String(event[1]):
				"state":
					state.game_state = String(who)
				"correct":
					mood.on_correct(int(who))
				"miss":
					mood.on_miss(int(who))
				"hurt":
					if int(who) == 1:
						state.p1_hp -= 1
					else:
						state.p2_hp -= 1
					mood.on_hurt(int(who))
				"out":
					if int(who) == 1:
						state.p1_alive = false
					else:
						state.p2_alive = false
					mood.on_out(int(who))
				"result":
					state.result_presentation_active = true
					state.result_winner = int(who)
					state.game_state = Constants.STATE_RESULT_CEREMONY
				"dance":
					cues.sync_elapsed = 0.0
		time += MATCH_DT
		mood.update(MATCH_DT, state, cues)
		for sim: CrowdSim in stands:
			sim.tick(time, MATCH_DT, mood, watched)
			sim.changed.clear()
		if time >= next_sample:
			next_sample += SAMPLE_SECONDS
			curve.t.append(snappedf(time, 1.0))
			curve.right.append(snappedf(stands[0].present_share(), 0.001))
			curve.left.append(snappedf(stands[1].present_share(), 0.001))
			curve.interest.append(snappedf(mood.interest, 0.01))
	curve["stats"] = [stands[0].stats.duplicate(), stands[1].stats.duplicate()]
	curve["mood"] = mood.snapshot()
	return curve


## A ten-question match: a question every 15 s from the start at 8 s (5 s of
## countdown), `answers` per question as [P1 right, P2 right] (false: a miss and,
## once, a lost heart), then the goal race and the result.
func _ten_questions(answers: Array, goal_at: float, winner: int) -> Array:
	var timeline: Array = [[1.0, "state", Constants.STATE_COUNTDOWN], [6.0, "state", Constants.STATE_PLAYING]]
	var hurt := {1: 0, 2: 0}
	for q: int in range(answers.size()):
		var at := 8.0 + 15.0 * q
		for player: int in [1, 2]:
			if bool(answers[q][player - 1]):
				timeline.append([at, "correct", player])
			else:
				timeline.append([at, "miss", player])
				if hurt[player] < 2:
					hurt[player] += 1
					timeline.append([at + 0.5, "hurt", player])
	timeline.append([goal_at, "state", Constants.STATE_GOAL_RACE])
	timeline.append([goal_at + 15.0, "result", winner])
	timeline.append([goal_at + 22.0, "dance", 0])
	timeline.append([goal_at + 40.0, "state", Constants.STATE_CLEAR])
	return timeline


func _at(curve: Dictionary, side: String, seconds: float) -> float:
	var index := clampi(int(round(seconds / SAMPLE_SECONDS)) - 1, 0, (curve[side] as Array).size() - 1)
	return float(curve[side][index])


func _check_matches() -> void:
	var report_matches := {}
	# 1. A close match: both stands stay full; P2 loses and its fans go home.
	var close: Array = []
	for q: int in range(10):
		close.append([q % 3 != 1, q % 4 != 2])
	var a := _play_match(2, Constants.MODE_TEN, 260.0, _ten_questions(close, 160.0, 1))
	report_matches["close"] = a
	check(_at(a, "right", 150.0) > 0.8 and _at(a, "left", 150.0) > 0.8, "a close match keeps both stands full (%.2f, %.2f)"
		% [_at(a, "right", 150.0), _at(a, "left", 150.0)])
	check(_at(a, "left", 180.0) - _at(a, "left", 250.0) > 0.25, "the loser's stand empties after the winner's dance (%.2f -> %.2f)"
		% [_at(a, "left", 180.0), _at(a, "left", 250.0)])
	# The winner's stand loses only its few rival fans and some neutrals.
	check(_at(a, "right", 250.0) > 0.75 and _at(a, "right", 250.0) - _at(a, "left", 250.0) > 0.15,
		"the winner's stand stays to celebrate (%.2f vs %.2f)" % [_at(a, "right", 250.0), _at(a, "left", 250.0)])
	check(_at(a, "left", 250.0) >= CrowdSim.EXODUS_FLOOR - 0.01, "but not below the floor")
	# 2. A lopsided match: P2 misses, loses two hearts and falls out at 70 s.
	var lopsided: Array = []
	for q: int in range(10):
		lopsided.append([true, q < 1])
	var b_line := _ten_questions(lopsided, 160.0, 1)
	b_line.append([70.0, "out", 2])
	var b := _play_match(2, Constants.MODE_TEN, 200.0, b_line)
	report_matches["lopsided"] = b
	check(_at(b, "right", 150.0) - _at(b, "left", 150.0) > 0.1, "the losing player's stand thins out during the match (%.2f vs %.2f)"
		% [_at(b, "right", 150.0), _at(b, "left", 150.0)])
	check(_at(b, "left", 180.0) - _at(b, "left", 160.0) < 0.12, "the fans of a player who fell out do not come back for the goal race (%.2f -> %.2f)"
		% [_at(b, "left", 160.0), _at(b, "left", 180.0)])
	# 3. One player falls out: game over, some of everybody goes.
	var solo: Array = [[1.0, "state", Constants.STATE_COUNTDOWN], [6.0, "state", Constants.STATE_PLAYING]]
	for q: int in range(6):
		solo.append([8.0 + 15.0 * q, "correct" if q != 2 and q != 3 else "miss", 1])
	solo.append_array([[54.0, "hurt", 1], [69.0, "hurt", 1], [90.0, "out", 1], [95.0, "state", Constants.STATE_GAME_OVER]])
	var c := _play_match(1, Constants.MODE_TEN, 150.0, solo)
	report_matches["solo_game_over"] = c
	for side: String in ["right", "left"]:
		check(_at(c, side, 90.0) - _at(c, side, 150.0) > 0.12, "after a lost solo game people go home (%s %.2f -> %.2f)"
			% [side, _at(c, side, 90.0), _at(c, side, 150.0)])
	# 4. A co-op clear: nobody leaves the cheering stands, nobody comes any more.
	var coop: Array = [[1.0, "state", Constants.STATE_COUNTDOWN], [6.0, "state", Constants.STATE_PLAYING]]
	for q: int in range(9):
		coop.append([8.0 + 15.0 * q, "correct", 1 + q % 2])
	coop.append([150.0, "state", Constants.STATE_CLEAR])
	var d := _play_match(2, Constants.MODE_COOP, 200.0, coop)
	report_matches["coop_clear"] = d
	for side: String in ["right", "left"]:
		check(absf(_at(d, side, 160.0) - _at(d, side, 200.0)) < 0.03, "a co-op clear keeps the crowd (%s %.2f -> %.2f)"
			% [side, _at(d, side, 160.0), _at(d, side, 200.0)])
	# 5. Ten minutes of endless play: the crowd breathes but holds, errands go on.
	var endless: Array = [[1.0, "state", Constants.STATE_COUNTDOWN], [6.0, "state", Constants.STATE_PLAYING]]
	for q: int in range(40):
		endless.append([8.0 + 15.0 * q, "miss" if q % 5 == 4 else "correct", 1])
	var e := _play_match(1, Constants.MODE_ENDLESS, 600.0, endless)
	report_matches["endless"] = e
	var lowest := 1.0
	for side: String in ["right", "left"]:
		for k: int in range(6, (e[side] as Array).size()):
			lowest = minf(lowest, float(e[side][k]))
	check(lowest > 0.5, "ten minutes of endless play keep the stands lively (lowest %.2f)" % lowest)
	var errands := 0
	for stats: Dictionary in e.stats:
		errands += int(stats.walks) + int(stats.instant)
	check(errands > 300, "people keep coming and going in a long game (%d)" % errands)
	report["matches"] = report_matches


## The beer vendors: up the aisle to a raised hand, the cup along the row from
## neighbour to neighbour, the money back, and down to the front deck again.
func _check_vendors() -> void:
	var sim := _sim(17, 24, Callable(), 2)
	var mood := _mood()
	var watched := _watch([4])
	var time := _run(sim, mood, watched, MATCH_DT)
	check(sim.vendors.size() == 2, "two vendors walk the stand")
	for p: CrowdSim.Person in sim.people:
		p.hunger_rate = 0.0
		p.bladder_rate = 0.0
		p.hunger = 0.0
		p.bladder = 0.0
		p.arrive_at = INF
	# The customer sits seven seats in from the aisle, row 3 of block 4.
	var customer := -1
	var center := 20.0 * (4 + 0.5)
	for index: int in range(sim.people.size()):
		var p := sim.people[index]
		if p.block == 4 and p.row == 3 and absf(p.seat.z - (center - 8.28 + 0.92 * 7)) < 0.01:
			customer = index
	check(customer >= 0 and sim.people[customer].state == CrowdSim.State.SEATED, "a seated customer")
	if customer < 0 or sim.people[customer].state != CrowdSim.State.SEATED:
		return
	var p := sim.people[customer]
	p.calling = true
	p.call_since = time
	sim._calls.append(customer)
	var view := sim.seat_view(customer)
	check(view.clip == &"SPEC_RaiseHand" and bool(view.loop), "the customer raises a hand")
	var order: Array[int] = []
	var states := {}
	var outside := 0
	var carried := false
	for _i: int in range(int(120.0 / MATCH_DT)):
		time += MATCH_DT
		sim.tick(time, MATCH_DT, mood, watched)
		for index: int in sim.changed:
			var q := sim.people[index]
			if q.pass_clip != &"" and absf(q.pass_start - time) < 1e-4:
				order.append(index)
				carried = carried or (q.carry == CrowdSim.FOOD_DRINK and int(sim.seat_view(index).food) == CrowdSim.FOOD_DRINK)
		sim.changed.clear()
		for v: CrowdSim.Vendor in sim.vendors:
			states[CrowdSim.VendorState.keys()[v.state]] = true
			var at := v.position
			if at.x < -0.6 or at.x > sim.paths.walkway_x.x or at.y < sim.paths.deck_y - 0.05 or at.y > sim.paths.walkway_y:
				outside += 1
		if int(sim.stats.delivered) > 0 and sim.vendors[0].state == CrowdSim.VendorState.CALLING:
			break
	var chain := sim._chain(p, p.aisle, customer)
	# Empty seats (people who never came) are skipped.
	var seated: Array[int] = []
	for index: int in chain:
		if sim.people[index].state == CrowdSim.State.SEATED:
			seated.append(index)
	var expected: Array[int] = seated.duplicate()
	expected.append(customer)
	var back := seated.duplicate()
	back.reverse()
	expected.append_array(back)
	report["vendor"] = {"order": order, "chain": chain, "seated": seated, "states": states.keys(),
		"seconds": snappedf(time, 0.1), "food": p.food}
	check(int(sim.stats.delivered) == 1 and p.food == CrowdSim.FOOD_DRINK, "the vendor's cup reaches the customer")
	check(not p.calling, "the customer's hand comes down")
	check(chain.size() >= 5 and seated.size() >= 2, "the cup goes along the row (%d seats, %d taken)" % [chain.size(), seated.size()])
	check(order == expected, "neighbour to neighbour towards the customer, then the money back (%s, expected %s)" % [order, expected])
	check(carried, "the cup shows in the hands passing it")
	check(states.has("TO_ROW") and states.has("HANDING") and states.has("BACK"), "up the aisle, handing over, down again (%s)" % [states.keys()])
	check(outside == 0, "vendors stay on the deck and the aisles")
	check(sim.vendors[0].position.x < sim.paths.front_x, "the vendor is back on the front deck")
	# The goal race: a raised hand comes down; out of sight the vendor serves at once.
	var other := seated[0]
	var q := sim.people[other]
	q.food = 0
	q.calling = true
	q.call_since = time
	sim._calls.append(other)
	mood.hurry = true
	time = _run(sim, mood, watched, 1.5, time)
	check(not q.calling, "the goal race lowers the raised hands")
	mood.hurry = false
	q.calling = true
	q.call_since = time
	sim._calls.append(other)
	time = _run(sim, mood, _watch([]), 1.5, time)
	check(not q.calling and q.food == CrowdSim.FOOD_DRINK, "out of sight the vendor has been")
	# Hungry people call the vendors by themselves.
	var busy := _sim(19, 24, Callable(), 2)
	_run(busy, _mood(), _watch([3, 4, 5]), 240.0)
	report["vendor_calls"] = {"calls": busy.stats.calls, "delivered": busy.stats.delivered, "walks": busy.stats.walks}
	check(int(busy.stats.calls) > 0 and int(busy.stats.delivered) > 0, "hungry people call the vendors (%s)" % [report["vendor_calls"]])


## The endless course grows: a block added during the match opens empty and fills.
func _check_new_block() -> void:
	var sim := _sim(13, 24)
	var mood := _mood()
	var nobody := _watch([])
	var time := _run(sim, mood, nobody, 30.0)
	var first := sim.people.size()
	var center := 20.0 * (BLOCKS + 0.5)
	var floor_point := Kit.stand_floor()
	var basis := Basis(Vector3.UP, -PI * 0.5)
	for row: int in range(6):
		var previous := -1
		for k: int in range(19):
			var seat := Vector3(SEAT_X[row] + 0.06, CUSHION_Y[row], center - 8.28 + 0.92 * k)
			previous = sim.add_person(BLOCKS, seat, Transform3D(basis, seat) * floor_point, row, k % 3, false, true, previous)
	var empty := true
	for index: int in range(first, sim.people.size()):
		empty = empty and sim.people[index].state == CrowdSim.State.AWAY and not sim.seat_view(index).shown
	check(empty, "a block added during the match opens empty")
	var watched := _watch([])
	watched.resize(BLOCKS + 1)
	_run(sim, mood, watched, 130.0, time)
	var seated := 0
	for index: int in range(first, sim.people.size()):
		seated += 1 if sim.people[index].state == CrowdSim.State.SEATED else 0
	var share := float(seated) / (sim.people.size() - first)
	report["new_block_filled"] = snappedf(share, 0.01)
	check(share > 0.6, "and fills up as people arrive (%.2f)" % share)


func _check_cost() -> void:
	# Both stands: two sims, a few watched blocks, a busy minute.
	var sims: Array[CrowdSim] = [_sim(21, 24), _sim(22, 24)]
	var mood := _mood()
	var watched := _watch([3, 4, 5])
	var time := 0.0
	for sim: CrowdSim in sims:
		_run(sim, mood, watched, DT)
	mood.interest = 0.3
	var total := 0
	var worst := 0
	var frames := int(60.0 / DT)
	for _i: int in range(frames):
		time += DT
		var started := Time.get_ticks_usec()
		for sim: CrowdSim in sims:
			sim.tick(time, DT, mood, watched)
			sim.changed.clear()
		var spent := Time.get_ticks_usec() - started
		total += spent
		worst = maxi(worst, spent)
	var average := float(total) / frames / 1000.0
	report["tick_msec"] = {"average": snappedf(average, 0.001), "worst": snappedf(worst / 1000.0, 0.001),
		"people": sims[0].people.size() * 2, "walkers": sims[0].walkers.size() + sims[1].walkers.size()}
	check(average < 0.5, "two stands' sims cost little per frame (%.3f ms)" % average)
