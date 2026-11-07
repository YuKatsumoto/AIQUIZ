class_name CrowdSim
extends RefCounted

## One side stand's crowd as a management sim (docs/crowd_sim.md). Every seated
## spectator comes in, goes for a snack or the toilet and may leave, driven by
## its own needs and by the match (CrowdMood). Only blocks the camera sees walk
## (StandPaths, a pool of walkers); elsewhere people simply appear in or vanish
## from their seats, so the crowd's flow costs a few dozen walkers per stand.
##
## Pure logic, no nodes: GrandstandCrowd draws it. `changed` lists the people
## whose seat changed since it last looked (seat_view()), `walkers` the people
## on foot this frame.

enum State { AWAY, SEATED, STANDING_UP, WALKING, SITTING_DOWN }
enum Away { NOT_ARRIVED, ERRAND, LEFT }
enum Errand { NONE, FOOD, TOILET, LEAVE }
enum Goal { SEAT, QUEUE, EXIT }

## At the start: share of people already seated, and of those still on the way.
## The rest only come when the match is worth it (NO_SHOW_INTEREST).
const START_SHARE := 0.65
const LATE_SHARE := 0.25
const LATE_WINDOW := Vector2(5.0, 150.0)
## A block that opens during the match fills this quickly (all but the no-shows).
const NEW_BLOCK_WINDOW := Vector2(5.0, 90.0)
const NO_SHOW_INTEREST := 0.75
## Leaving stops once this share of the stand's people is left.
const FLOOR_SHARE := 0.3
const LEAVE_PER_SECOND := 4.0
## After the match (CrowdMood.exodus_team): the loser's fans and some neutrals go,
## the least patient first, the rest over EXODUS_SECONDS; after a lost game with no
## rival some of everybody. The stand keeps EXODUS_FLOOR of its people.
const EXODUS_LOSER := 0.8
const EXODUS_NEUTRAL := 0.25
const EXODUS_ALL_FANS := 0.45
const EXODUS_ALL_NEUTRAL := 0.35
const EXODUS_SECONDS := 20.0
const EXODUS_FLOOR := 0.2
const EXODUS_PER_SECOND := 8.0
## The wish to leave has to last this long.
const LEAVE_AFTER := 10.0
## Back when the wish to leave drops this far under the patience, now and then.
const RETURN_MARGIN := 0.15
const RETURN_CHANCE := 0.03
const RETURN_AFTER := 20.0
## Fans whose player is this far down (fell out, say) do not come back.
const RETURN_MORALE := 0.35
## Only some people get hungry or need the toilet within a match.
const SNACKER_SHARE := 0.35
const HUNGER_START := Vector2(0.0, 0.4)
const HUNGER_SECONDS := Vector2(300.0, 900.0)
const HUNGRY := 0.7
const TOILET_SHARE := 0.25
const BLADDER_START := Vector2(0.0, 0.5)
const BLADDER_SECONDS := Vector2(300.0, 900.0)
const BURSTING := 0.85
## Above this interest nobody leaves the seat for anything.
const STAY_INTEREST := 0.85
const PATIENCE := Vector2(0.15, 0.45)
## Away from the stand (behind the exit).
const TOILET_AWAY := Vector2(30.0, 60.0)
const SNACK_AWAY := Vector2(40.0, 80.0)
const EAT_SECONDS := Vector2(60.0, 150.0)
const SERVE_SECONDS := Vector2(4.0, 7.0)
## SPEC_StandUp / SPEC_SitDown when the kit does not know them.
const STAND_SECONDS := 1.0
const WALK_SPEED := Vector2(1.0, 1.25)
const HURRY_PACE := 1.8
const TURN_RATE := 8.0
## Feet follow the steps this quickly.
const STEP_EASE := 14.0
## A walker waits while somebody this close is in front of it going its way,
## at most this long (then it squeezes past).
const SPACING := 0.6
const MAX_WAIT := 2.0
## Stopped this long: the walk turns into standing.
const STILL_SECONDS := 0.3
## Every person is looked at this often.
const CHECK_SECONDS := 0.5
## refresh_aisles() がブロックを見直すかを決める範囲の余裕（_block_reach は float32 なので丸めの分）。
const REACH_MARGIN := 0.01
const GROUP_CHANCE := 0.3
const GROUP_MAX := 4
const FOOD_POPCORN := 1
const FOOD_HOTDOG := 2
## A cup from the beer vendor (SeatedSpectatorKit.PROP_CUP).
const FOOD_DRINK := 10
## Beer vendors (docs/crowd_sim.md, step 5): they walk the front deck of their
## stretch of the stand, calling out now and then, and climb an aisle to whoever
## raises a hand there; the cup goes along the row from neighbour to neighbour
## and the money comes back.
const VENDOR_SPEED := 0.85
const VENDOR_X := 0.05
## At a row: on the aisle's step level with it, this far to the row's side.
const VENDOR_ROW_IN := 0.3
const VENDOR_SIDE := 0.55
## Of the hungry in a vendor's stretch the camera sees, this many raise a hand
## (the rest walk to a kiosk), and wait this long for the vendor.
const CALL_SHARE := 0.7
const CALL_PATIENCE := 45.0
const PATROL_CALL := Vector2(2.0, 4.0)
## The cup changes hands this far into a hand-over clip (SPEC_PassItemL/R, SPEC_VendorHand).
const HAND_AT := 0.6
const PASS_SECONDS := 1.0
const THANKS_SECONDS := 1.5

enum VendorState { CALLING, PATROL, TO_ROW, HANDING, THANKS, BACK }
## Facing the course (the rig faces +Z; stand -X is the course).
const FACE_COURSE := -PI * 0.5


class Person:
	var block := 0
	## Hips on the seat and the floor between the feet once standing, stand space.
	var seat := Vector3.ZERO
	var spot := Vector3.ZERO
	var row := 0
	var team := 0
	## Cheer leaders and pairs never leave their seats.
	var fixed := false
	## Empty hands: may fetch a snack (and holds it while eating).
	var can_eat := false
	var aisle := 0.0
	var group := -1
	var state := State.SEATED
	var away := Away.NOT_ARRIVED
	var errand := Errand.NONE
	var since := 0.0
	var until := 0.0
	var hunger := 0.0
	var hunger_rate := 0.0
	var bladder := 0.0
	var bladder_rate := 0.0
	var patience := 0.3
	var arrive_at := 0.0
	var food := 0
	var eat_until := 0.0
	var leave_for := 0.0
	var checked := 0.0
	## A hand raised for the vendor (since when), and which vendor is coming (-1 none).
	var calling := false
	var call_since := 0.0
	var served_by := -1
	## Handing the cup (or the money) along the row: the clip, from when, and what it holds.
	var pass_clip := &""
	var pass_start := 0.0
	var carry := 0


class Walker:
	var person := -1
	var route := PackedVector3Array()
	var next := 0
	## Floor point between the feet, stand space.
	var position := Vector3.ZERO
	var yaw := FACE_COURSE
	var speed := 1.1
	var goal := Goal.SEAT
	var clip := &"SPEC_StandIdle"
	## Seconds into the clip (at its own speed), that speed, and whether it loops
	## (a once clip holds its last frame).
	var phase := 0.0
	var rate := 1.0
	var loop := true
	var still := 0.0
	## Last direction of travel, and how long something has been in the way.
	var heading := Vector3.ZERO
	var waited := 0.0
	## The booth face it queues at (StandPaths.booths_from()), or NAN.
	var booth := Vector2(NAN, 0.0)
	var serve_until := -1.0
	var hurried := false


class Vendor:
	## Floor point between the feet, stand space.
	var position := Vector3.ZERO
	var yaw := FACE_COURSE
	var route := PackedVector3Array()
	var next := 0
	## The aisle it is on or near (the floor's steps).
	var aisle := 0.0
	## Its stretch of the stand (stand z).
	var range_z := Vector2.ZERO
	var state := VendorState.CALLING
	var until := 0.0
	var clip := &"SPEC_VendorCall"
	var phase := 0.0
	var rate := 1.0
	var loop := true
	var customer := -1
	## Facing the row while handing over.
	var face := 0.0
	## The hand-overs: [person (-1 the vendor), clip, carries the cup], and the current one.
	var passes: Array = []
	var step := -1
	var step_at := 0.0


var paths: StandPaths
var people: Array[Person] = []
var walkers: Array[Walker] = []
var vendors: Array[Vendor] = []
var pool_size := 24
## People whose seat changed (index -> true); GrandstandCrowd clears it.
var changed := {}
var now := 0.0
## CrowdMood.match_serial this crowd was set up for (-1: not yet).
var serial := -1
## Counts for tests and the debug snapshot.
var stats := {"walks": 0, "served": 0, "left": 0, "came": 0, "instant": 0, "calls": 0, "delivered": 0}
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _cursor := 0
var _leave_budget := 0.0
## People away from the stand.
var _away := 0
## Standing up to walk: holds a place in the pool.
var _reserved := 0
## People standing up or sitting down.
var _moving: Array[int] = []
## Friends who come and go together (lists of people).
var _groups: Array[Array] = []
## Booth face -> its queue (walkers), first in line first.
var _queues := {}
## Raised hands waiting for a vendor, people handing something along a row, and
## each row's people (Vector2i(block, row) -> indices).
var _calls: Array[int] = []
## Share of the hungry who call a vendor rather than walk to a kiosk (CALL_SHARE).
var call_share := CALL_SHARE
var _passing: Array[int] = []
var _rows := {}
## ブロックごとの人（block -> 番号の並び）と、その席の z の範囲と通路までの一番遠い距離
## （Vector3(最小 z, 最大 z, 距離)）。refresh_aisles() が見直すブロックを選ぶのに使う。
var _block_people := {}
var _block_reach := {}
## 通路が変わったとき歩いていて見直せなかった人（番号 -> true）。次の refresh_aisles() で見直す。
var _stale_aisles := {}
## tick()'s last `awake` and people count, the awake blocks and how many people they
## hold, and the check cursor among them (Vector2i(position in _awake_blocks, index
## in that block's people)).
var _awake_key := PackedByteArray()
var _awake_people := -1
var _awake_blocks: Array[int] = []
var _awake_count := 0
var _awake_cursor := Vector2i.ZERO
## This frame's wish to leave per team (_leave_wish()).
var _wish := PackedFloat32Array([0.0, 0.0, 0.0])
## The clips' timing (_learn_clips()): getting up, sitting down, the gaits' paces.
var _stand_up_seconds := STAND_SECONDS
var _sit_down_seconds := STAND_SECONDS
var _walk_pace := SeatedSpectatorKit.WALK_CLIP_SPEED
var _run_pace := SeatedSpectatorKit.WALK_CLIP_SPEED
## The stretch of the stand that is shown (stand z, set_walk_z()): the vendors
## keep to it, past it the blocks are hidden and there is only water.
var _walk_z := Vector2(-INF, INF)


## `vendor_count` beer vendors walk the stand.
func _init(stand_paths: StandPaths, seed_value: int, pool: int, vendor_count := 0) -> void:
	paths = stand_paths
	_seed = seed_value
	_rng.seed = seed_value
	pool_size = pool
	for _k: int in range(vendor_count):
		vendors.append(Vendor.new())


## Adds the spectator in `seat` (stand space, `spot` the floor in front of it).
## `neighbour`: the person in the next seat of the same row, or -1.
func add_person(block: int, seat: Vector3, spot: Vector3, row: int, team: int, fixed: bool, can_eat: bool,
		neighbour: int = -1) -> int:
	var p := Person.new()
	p.block = block
	p.seat = seat
	p.spot = spot
	p.row = row
	p.team = team
	p.fixed = fixed
	p.can_eat = can_eat
	p.aisle = paths.nearest_aisle(seat.z)
	p.patience = _rng.randf_range(PATIENCE.x, PATIENCE.y)
	if _rng.randf() < SNACKER_SHARE:
		p.hunger_rate = 1.0 / _rng.randf_range(HUNGER_SECONDS.x, HUNGER_SECONDS.y)
	if _rng.randf() < TOILET_SHARE:
		p.bladder_rate = 1.0 / _rng.randf_range(BLADDER_SECONDS.x, BLADDER_SECONDS.y)
	var index := people.size()
	people.append(p)
	var row_key := Vector2i(block, row)
	if not _rows.has(row_key):
		_rows[row_key] = []
	(_rows[row_key] as Array).append(index)
	if not _block_people.has(block):
		_block_people[block] = []
		_block_reach[block] = Vector3(INF, -INF, 0.0)
	(_block_people[block] as Array).append(index)
	_widen_reach(p)
	var joined := false
	if neighbour >= 0 and not fixed and _rng.randf() < GROUP_CHANCE:
		var other := people[neighbour]
		if not other.fixed and other.team == team and _groups[other.group].size() < GROUP_MAX:
			p.group = other.group
			_groups[p.group].append(index)
			joined = true
	if not joined:
		p.group = _groups.size()
		_groups.append([index])
	if serial >= 0 and not fixed:
		# A block added during the match (the endless course grows) opens empty and
		# people stream in: everybody but the no-shows is on the way.
		_set_away(p, Away.NOT_ARRIVED)
		p.arrive_at = INF
		if _rng.randf() < START_SHARE + LATE_SHARE:
			p.arrive_at = now + _rng.randf_range(NEW_BLOCK_WINDOW.x, NEW_BLOCK_WINDOW.y)
		changed[index] = true
	return index


## The aisles changed (the stand grew): everybody takes the nearest one again.
## 増えた・なくなった通路（StandPaths.changed_aisles）が今の通路より遠い人は答えが変わらないので、その近くの
## ブロックの人と、前に歩いていて見直せなかった人だけを見直す（全員を見直すと、客席が長いほど重くなる）。
func refresh_aisles() -> void:
	var changed_aisles := paths.changed_aisles
	paths.changed_aisles = PackedFloat32Array()
	if not changed_aisles.is_empty():
		for block: int in _block_people:
			var span: Vector3 = _block_reach[block]
			if not _any_within(changed_aisles, span.x - span.z - REACH_MARGIN, span.y + span.z + REACH_MARGIN):
				continue
			_block_reach[block] = Vector3(INF, -INF, 0.0)
			for index: int in _block_people[block]:
				var p := people[index]
				if p.state != State.WALKING:
					p.aisle = paths.nearest_aisle(p.seat.z)
					_stale_aisles.erase(index)
				else:
					_stale_aisles[index] = true
				_widen_reach(p)
	for index: int in _stale_aisles.keys():
		var p := people[index]
		if p.state != State.WALKING:
			p.aisle = paths.nearest_aisle(p.seat.z)
			_stale_aisles.erase(index)
			_widen_reach(p)
	_assign_vendor_ranges()


## _block_reach を p の席と通路まで広げる。
func _widen_reach(p: Person) -> void:
	var span: Vector3 = _block_reach[p.block]
	_block_reach[p.block] = Vector3(minf(span.x, p.seat.z), maxf(span.y, p.seat.z), maxf(span.z, absf(p.aisle - p.seat.z)))


static func _any_within(values: PackedFloat32Array, low: float, high: float) -> bool:
	for value: float in values:
		if value >= low and value <= high:
			return true
	return false


## A fresh match: who is in, who is on the way, who stays home for now.
func start(time: float, match_serial: int) -> void:
	_learn_clips()
	now = time
	serial = match_serial
	_rng.seed = _seed + match_serial * 7919
	walkers.clear()
	_queues.clear()
	_moving.clear()
	_calls.clear()
	_passing.clear()
	_reserved = 0
	_away = 0
	_leave_budget = 0.0
	for group: Array in _groups:
		var roll := _rng.randf()
		for index: int in group:
			var p := people[index]
			p.state = State.SEATED
			p.food = 0
			p.calling = false
			p.served_by = -1
			p.pass_clip = &""
			p.carry = 0
			p.errand = Errand.NONE
			p.leave_for = 0.0
			p.checked = now
			p.hunger = _rng.randf_range(HUNGER_START.x, HUNGER_START.y)
			p.bladder = _rng.randf_range(BLADDER_START.x, BLADDER_START.y)
			if not p.fixed:
				_roll_arrival(p, roll)
			changed[index] = true
	_place_vendors()


func _roll_arrival(p: Person, roll: float) -> void:
	if roll < START_SHARE:
		return
	_set_away(p, Away.NOT_ARRIVED)
	p.arrive_at = now + _rng.randf_range(LATE_WINDOW.x, LATE_WINDOW.y) if roll < START_SHARE + LATE_SHARE else INF


## One frame. `watched[block]` is 1 for the blocks the camera sees: people walk
## there only. `awake[block]` is 1 for the blocks near enough to the camera for
## their people's comings and goings to show; the others keep what they are doing
## until the camera comes back (an endless course keeps adding blocks, and checking
## everybody would cost more every wall). Empty: every block is awake.
func tick(time: float, delta: float, mood: CrowdMood, watched: PackedByteArray,
		awake := PackedByteArray()) -> void:
	if serial != mood.match_serial:
		start(time, mood.match_serial)
	now = time
	var checked := people.size()
	if not awake.is_empty():
		_sync_awake(awake)
		checked = _awake_count
	# The people checked get the share of the leaving budget they would get if
	# everybody were checked.
	var share := float(checked) / float(people.size()) if not people.is_empty() else 1.0
	var leaving := (EXODUS_PER_SECOND if mood.exodus_team >= 0 else LEAVE_PER_SECOND) * share
	_leave_budget = minf(_leave_budget + leaving * delta, maxf(leaving * 2.0, 1.0))
	for team: int in range(3):
		_wish[team] = _leave_wish(team, mood)
	_step_walkers(delta, mood, watched)
	_step_moving()
	_step_vendors(delta, mood)
	_step_passing()
	if people.is_empty():
		return
	if awake.is_empty():
		var count := mini(people.size(), ceili(people.size() * delta / CHECK_SECONDS))
		for _k: int in range(count):
			_cursor = (_cursor + 1) % people.size()
			_check(_cursor, mood, watched)
		return
	if _awake_blocks.is_empty():
		return
	for _k: int in range(mini(_awake_count, ceili(_awake_count * delta / CHECK_SECONDS))):
		var block: Array = _block_people[_awake_blocks[_awake_cursor.x]]
		_awake_cursor.y += 1
		if _awake_cursor.y >= block.size():
			_awake_cursor = Vector2i((_awake_cursor.x + 1) % _awake_blocks.size(), 0)
			block = _block_people[_awake_blocks[_awake_cursor.x]]
		_check(block[_awake_cursor.y], mood, watched)


## Rebuilds the awake blocks when tick()'s `awake` or the people change (the course
## adds blocks as it grows): a pass over the blocks, not the people.
func _sync_awake(awake: PackedByteArray) -> void:
	if awake == _awake_key and people.size() == _awake_people:
		return
	_awake_key = awake
	_awake_people = people.size()
	_awake_blocks.clear()
	_awake_count = 0
	for block: int in _block_people:
		if block < awake.size() and awake[block] != 0:
			_awake_blocks.append(block)
			_awake_count += (_block_people[block] as Array).size()
	if _awake_cursor.x >= _awake_blocks.size():
		_awake_cursor = Vector2i.ZERO


## Share of the stand's people in, or on the way to, their seats.
func present_share() -> float:
	return 1.0 - float(_away) / maxf(1.0, float(people.size()))


func free_walkers() -> int:
	return pool_size - walkers.size() - _reserved


## What the seat of `index` shows: {shown, clip (&"" none), start, loop, food}.
## Getting up or sitting down, then a hand-over (with the cup in hand), then a
## hand raised for the vendor.
func seat_view(index: int) -> Dictionary:
	var p := people[index]
	var clip := &""
	var start := p.since
	var loop := false
	var food := p.food
	if p.state == State.STANDING_UP:
		clip = &"SPEC_StandUp"
	elif p.state == State.SITTING_DOWN:
		clip = &"SPEC_SitDown"
	elif p.pass_clip != &"":
		clip = p.pass_clip
		start = p.pass_start
		if p.carry != 0 and p.can_eat:
			food = p.carry
	elif p.calling:
		clip = &"SPEC_RaiseHand"
		start = p.call_since
		loop = true
	return {"shown": p.state in [State.SEATED, State.STANDING_UP, State.SITTING_DOWN], "clip": clip,
		"start": start, "loop": loop, "food": food}


func snapshot() -> Dictionary:
	var states := {}
	for p: Person in people:
		var key: String = State.keys()[p.state] if p.state != State.AWAY else "AWAY_" + Away.keys()[p.away]
		states[key] = int(states.get(key, 0)) + 1
	var queued := 0
	for queue: Array in _queues.values():
		queued += queue.size()
	var vendor_states: Array = []
	for v: Vendor in vendors:
		vendor_states.append(VendorState.keys()[v.state])
	return {"people": people.size(), "present": snappedf(present_share(), 0.001), "states": states,
		"walkers": walkers.size(), "queued": queued, "calls": _calls.size(), "vendors": vendor_states,
		"stats": stats.duplicate()}


# ------------------------------------------------------------------ people

func _check(index: int, mood: CrowdMood, watched: PackedByteArray) -> void:
	var p := people[index]
	var dt := now - p.checked
	p.checked = now
	if dt <= 0.0:
		return
	p.hunger += p.hunger_rate * dt
	p.bladder += p.bladder_rate * dt
	if p.state == State.AWAY:
		_check_away(index, p, mood, watched)
	elif p.state == State.SEATED:
		_check_seated(index, p, dt, mood, watched)


func _check_away(index: int, p: Person, mood: CrowdMood, watched: PackedByteArray) -> void:
	var comes := false
	if mood.finished and p.away != Away.ERRAND:
		# The match is over: nobody arrives or comes back any more.
		return
	match p.away:
		Away.NOT_ARRIVED:
			comes = now >= p.arrive_at or (mood.hurry and p.arrive_at < INF) \
				or (mood.interest >= NO_SHOW_INTEREST and _rng.randf() < RETURN_CHANCE)
		Away.ERRAND:
			comes = now >= p.until or mood.hurry
		Away.LEFT:
			comes = now - p.since > RETURN_AFTER and _wish[p.team] < 1.0 - p.patience - RETURN_MARGIN \
				and (p.team == 0 or mood.morale_for(p.team) >= RETURN_MORALE) and _rng.randf() < RETURN_CHANCE
	if not comes:
		return
	if _walks(p, watched):
		if free_walkers() <= 0:
			return
		var route := paths.from_exit(p.aisle, _rng.randf_range(-1.0, 1.0))
		route.append_array(paths.walkway_to_seat(p.spot, p.row, p.aisle))
		var w := _add_walker(index, route, Goal.SEAT, mood.hurry)
		w.yaw = _yaw_to(route[0], route[1], w.yaw)
		_set_back(p, State.WALKING)
	else:
		_set_back(p, State.SEATED)
		_finish_errand(p)
		stats.instant += 1
		changed[index] = true
	stats.came += 1


func _check_seated(index: int, p: Person, dt: float, mood: CrowdMood, watched: PackedByteArray) -> void:
	if p.food != 0 and now >= p.eat_until:
		p.food = 0
		changed[index] = true
	if p.calling:
		if not _walks(p, watched) and (p.served_by < 0 or _release_vendor(p.served_by)):
			# Out of sight: the vendor has been.
			_hand_down(index, p)
			_eat(p, FOOD_DRINK)
			stats.instant += 1
		elif p.served_by < 0 and (mood.hurry or mood.finished):
			_hand_down(index, p)
		elif p.served_by < 0 and now - p.call_since > CALL_PATIENCE:
			# Tired of waiting: off to a kiosk.
			_hand_down(index, p)
			_send(index, p, Errand.FOOD, watched)
			return
	if p.calling or p.served_by >= 0:
		return
	if p.fixed:
		return
	if mood.finished:
		p.leave_for = 0.0
		if _goes_home(p, mood) and present_share() > EXODUS_FLOOR and _leave_budget >= 1.0:
			_leave_with_friends(p, watched)
		return
	if mood.hurry or mood.interest > STAY_INTEREST:
		p.leave_for = 0.0
		return
	if _wish[p.team] > 1.0 - p.patience:
		p.leave_for += dt
	else:
		p.leave_for = maxf(0.0, p.leave_for - dt)
	if p.leave_for >= LEAVE_AFTER and present_share() > FLOOR_SHARE and _leave_budget >= 1.0:
		_leave_with_friends(p, watched)
		return
	if p.bladder >= BURSTING:
		_send(index, p, Errand.TOILET, watched)
	elif p.can_eat and p.food == 0 and p.hunger >= HUNGRY:
		if _walks(p, watched) and _vendor_covers(p.seat.z) and _rng.randf() < call_share:
			p.calling = true
			p.call_since = now
			_calls.append(index)
			changed[index] = true
			stats.calls += 1
		else:
			_send(index, p, Errand.FOOD, watched)


## `p` and the friends with it go home.
func _leave_with_friends(p: Person, watched: PackedByteArray) -> void:
	for member: int in _groups[p.group]:
		var other := people[member]
		if other.state == State.SEATED and not other.fixed and _leave_budget >= 1.0:
			if _send(member, other, Errand.LEAVE, watched):
				_leave_budget -= 1.0


## After the match: whether `p` is one of those going home, and its turn has come
## (the least patient first, spread over EXODUS_SECONDS).
func _goes_home(p: Person, mood: CrowdMood) -> bool:
	var share := 0.0
	if mood.exodus_team == 0:
		share = EXODUS_ALL_NEUTRAL if p.team == 0 else EXODUS_ALL_FANS
	elif mood.exodus_team > 0:
		if p.team == mood.exodus_team:
			share = EXODUS_LOSER
		elif p.team == 0:
			share = EXODUS_NEUTRAL
	var rank := (p.patience - PATIENCE.x) / (PATIENCE.y - PATIENCE.x)
	return rank < share and mood.exodus_since >= EXODUS_SECONDS * rank / maxf(share, 0.01)


## How much a fan of `team` (0 neutral) would rather go home: a dull match, and
## the fan's player doing badly.
func _leave_wish(team: int, mood: CrowdMood) -> float:
	var dull := 1.0 - mood.interest
	if team == 0:
		return dull
	return 0.6 * dull + 0.4 * (1.0 - mood.morale_for(team))


## Off for `errand`: stands up and walks where the camera sees it, otherwise just
## goes. False while it has to wait for a free walker.
func _send(index: int, p: Person, errand: int, watched: PackedByteArray) -> bool:
	var walks := _walks(p, watched)
	if walks and free_walkers() <= 0:
		return false
	p.errand = errand
	p.leave_for = 0.0
	if walks:
		p.state = State.STANDING_UP
		p.since = now
		_reserved += 1
		_moving.append(index)
	else:
		_go_away(p)
		stats.instant += 1
	changed[index] = true
	return true


## Gone behind the exit: home (for now), or back after the errand.
func _go_away(p: Person) -> void:
	if p.errand == Errand.LEAVE:
		_set_away(p, Away.LEFT)
		p.since = now
		stats.left += 1
		return
	_set_away(p, Away.ERRAND)
	var away := TOILET_AWAY if p.errand == Errand.TOILET else SNACK_AWAY
	p.until = now + _rng.randf_range(away.x, away.y)
	if p.errand == Errand.TOILET:
		p.bladder = 0.0


## Back in the seat after an errand (with the snack, if it went for one).
func _finish_errand(p: Person) -> void:
	if p.errand == Errand.FOOD:
		_eat(p)
	p.errand = Errand.NONE


## Something to eat or drink in hand for a while: `food`, or popcorn or a hot dog.
func _eat(p: Person, food := 0) -> void:
	p.hunger = 0.0
	if p.can_eat:
		p.food = food if food != 0 else (FOOD_POPCORN if _rng.randf() < 0.6 else FOOD_HOTDOG)
		p.eat_until = now + _rng.randf_range(EAT_SECONDS.x, EAT_SECONDS.y)


func _walks(p: Person, watched: PackedByteArray) -> bool:
	return p.block < watched.size() and watched[p.block] != 0


## Away from the stand (_away counts them).
func _set_away(p: Person, kind: int) -> void:
	if p.state != State.AWAY:
		_away += 1
	p.state = State.AWAY
	p.away = kind


## Back from AWAY into `state`.
func _set_back(p: Person, state: int) -> void:
	if p.state == State.AWAY:
		_away -= 1
	p.state = state


## Stood up or sat down: the walk starts, or the seat is taken again.
func _step_moving() -> void:
	var still: Array[int] = []
	for index: int in _moving:
		var p := people[index]
		if now - p.since < _stand_seconds(p.state):
			still.append(index)
			continue
		if p.state == State.STANDING_UP:
			_reserved -= 1
			_start_walk(index, p)
		elif p.state == State.SITTING_DOWN:
			p.state = State.SEATED
			changed[index] = true
	_moving = still


## The baked clips' lengths and paces, once (the kit knows them after it is built).
func _learn_clips() -> void:
	var up := SeatedSpectatorKit.clip_seconds(&"SPEC_StandUp")
	var down := SeatedSpectatorKit.clip_seconds(&"SPEC_SitDown")
	_stand_up_seconds = up if up > 0.0 else STAND_SECONDS
	_sit_down_seconds = down if down > 0.0 else STAND_SECONDS
	_walk_pace = SeatedSpectatorKit.clip_ground_speed(&"SPEC_Walk")
	_run_pace = SeatedSpectatorKit.clip_ground_speed(&"SPEC_Run")


## How long getting up (or sitting down) takes: the clip's length.
func _stand_seconds(state: int) -> float:
	return _stand_up_seconds if state == State.STANDING_UP else _sit_down_seconds


## Off the seat towards its errand: a booth with room in its queue for a snack,
## otherwise the exit.
func _start_walk(index: int, p: Person) -> void:
	var route := paths.seat_to_walkway(p.spot, p.row, p.aisle)
	var booth := Vector2(NAN, 0.0)
	if p.errand == Errand.FOOD:
		# The booth on the seat's side of the aisle first.
		var faces := paths.booths_from(p.aisle)
		faces.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.x - p.seat.z) < absf(b.x - p.seat.z))
		for face: Vector2 in faces:
			if (_queues.get(face, []) as Array).size() < StandPaths.QUEUE_MAX:
				booth = face
				break
	var goal := Goal.EXIT if is_nan(booth.x) else Goal.QUEUE
	if goal == Goal.QUEUE:
		var queue: Array = _queues.get(booth, [])
		route.append(paths.queue_point(booth, queue.size()))
	else:
		route.append_array(paths.to_exit(p.aisle, _rng.randf_range(-1.0, 1.0)))
	var w := _add_walker(index, route, goal, false)
	if goal == Goal.QUEUE:
		w.booth = booth
		var queue: Array = _queues.get(booth, [])
		queue.append(w)
		_queues[booth] = queue
	p.state = State.WALKING
	changed[index] = true
	stats.walks += 1


func _add_walker(index: int, route: PackedVector3Array, goal: int, hurried: bool) -> Walker:
	var w := Walker.new()
	w.person = index
	w.route = route
	w.next = 1
	w.position = route[0]
	w.goal = goal
	w.speed = _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y)
	w.hurried = hurried
	walkers.append(w)
	return w


# ------------------------------------------------------------------ walkers

func _step_walkers(delta: float, mood: CrowdMood, watched: PackedByteArray) -> void:
	if walkers.is_empty():
		return
	# Walkers keep their distance from the others on the same aisle.
	var lanes := {}
	for w: Walker in walkers:
		var aisle := people[w.person].aisle
		if not lanes.has(aisle):
			lanes[aisle] = []
		(lanes[aisle] as Array).append(w)
	var done: Array[Walker] = []
	for w: Walker in walkers:
		var p := people[w.person]
		if not _walks(p, watched):
			# Out of sight: whatever it was on its way to happens at once.
			_finish_now(w, p)
			done.append(w)
			continue
		if mood.hurry and w.goal != Goal.SEAT:
			_head_home(w, p)
		if _step_walker(w, p, delta, lanes[p.aisle]):
			done.append(w)
	for w: Walker in done:
		walkers.erase(w)


## Moves one walker; true once it is done (seated or gone).
func _step_walker(w: Walker, p: Person, delta: float, lane: Array) -> bool:
	var pace := HURRY_PACE if w.hurried else 1.0
	var budget := w.speed * pace * delta
	var moved := false
	var heading := NAN
	# Past a route point the rest of the frame's step goes on to the next one.
	for _leg: int in range(4):
		var target := _target(w)
		if target == Vector3.INF or budget <= 0.0:
			break
		var flat := Vector3(target.x - w.position.x, 0.0, target.z - w.position.z)
		var distance := flat.length()
		if distance < 0.005:
			if w.next < w.route.size():
				w.next += 1
				continue
			break
		var direction := flat / distance
		if _blocked(w, direction, lane):
			w.waited += delta
			if w.waited < MAX_WAIT:
				break
		else:
			w.waited = 0.0
		var stairs := paths.pace(w.position.x, w.position.z, p.aisle)
		var step := minf(distance, budget * stairs)
		w.position.x += direction.x * step
		w.position.z += direction.z * step
		budget -= step / stairs
		heading = atan2(direction.x, direction.z)
		w.heading = direction
		moved = true
	w.position.y = lerpf(w.position.y, paths.floor_y(w.position.x, w.position.z, p.aisle), 1.0 - exp(-STEP_EASE * delta))
	w.still = 0.0 if moved else w.still + delta
	if moved:
		_turn(w, heading, delta)
		# Hurrying back runs; the clip plays at the pace its feet cover the ground.
		if w.hurried:
			_play(w, &"SPEC_Run", w.speed * pace / _run_pace, delta)
		else:
			_play(w, &"SPEC_Walk", w.speed * pace / _walk_pace, delta)
		return false
	if w.still < STILL_SECONDS and (w.clip == &"SPEC_Walk" or w.clip == &"SPEC_Run"):
		_play(w, w.clip, w.rate, delta)
	elif w.serve_until >= 0.0:
		# Served at the kiosk window: reaching for the snack once, then holding it.
		_play(w, &"SPEC_Buy", 1.0, delta, false)
	else:
		_play(w, &"SPEC_StandPhone" if w.person % 3 == 0 else &"SPEC_StandIdle", 1.0, delta)
	if w.next < w.route.size():
		return false
	match w.goal:
		Goal.QUEUE:
			_turn(w, atan2(0.0, -w.booth.y), delta)
			var queue: Array = _queues.get(w.booth, [])
			if queue.find(w) == 0:
				if w.serve_until < 0.0:
					w.serve_until = now + _rng.randf_range(SERVE_SECONDS.x, SERVE_SECONDS.y)
				elif now >= w.serve_until:
					_served(w, p)
		Goal.SEAT:
			# At the seat: turn to the course, then sit down.
			_turn(w, FACE_COURSE, delta)
			if absf(angle_difference(w.yaw, FACE_COURSE)) < 0.15:
				p.state = State.SITTING_DOWN
				p.since = now
				_moving.append(w.person)
				_finish_errand(p)
				changed[w.person] = true
				return true
		Goal.EXIT:
			_go_away(p)
			changed[w.person] = true
			return true
	return false


## Where the walker heads now: the next route point, or its place in the queue.
func _target(w: Walker) -> Vector3:
	if w.next < w.route.size():
		return w.route[w.next]
	if w.goal == Goal.QUEUE and not is_nan(w.booth.x):
		var place := maxi(0, (_queues.get(w.booth, []) as Array).find(w))
		return paths.queue_point(w.booth, place)
	return Vector3.INF


## Somebody close ahead going the same way, or standing in the way. People
## coming the other way pass each other, and people standing in a queue only
## hold up the queue.
func _blocked(w: Walker, direction: Vector3, lane: Array) -> bool:
	var queued := _in_queue(w)
	for other: Walker in lane:
		if other == w:
			continue
		var gap := Vector3(other.position.x - w.position.x, 0.0, other.position.z - w.position.z)
		if gap.length_squared() >= SPACING * SPACING or gap.dot(direction) <= 0.05:
			continue
		if _in_queue(other) != queued:
			continue
		if other.still < STILL_SECONDS and other.heading.dot(direction) < 0.3:
			continue
		return true
	return false


## Standing in (or shuffling up) a booth's queue.
func _in_queue(w: Walker) -> bool:
	return w.goal == Goal.QUEUE and w.next >= w.route.size()


func _play(w: Walker, clip: StringName, rate: float, delta: float, loop := true) -> void:
	if clip != w.clip:
		w.clip = clip
		w.phase = 0.0
	w.rate = rate
	w.loop = loop
	w.phase += delta * rate


func _turn(w: Walker, yaw: float, delta: float) -> void:
	w.yaw += clampf(angle_difference(w.yaw, yaw), -TURN_RATE * delta, TURN_RATE * delta)


func _yaw_to(from: Vector3, to: Vector3, fallback: float) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	return atan2(flat.x, flat.y) if flat.length_squared() > 1e-6 else fallback


## Served at the booth: back to the seat with the snack.
func _served(w: Walker, p: Person) -> void:
	_leave_queue(w)
	stats.served += 1
	p.errand = Errand.NONE
	_eat(p)
	w.goal = Goal.SEAT
	w.route = paths.home_from(w.position, p.spot, p.row, p.aisle)
	w.next = 1


## The goal race: everybody on foot hurries back to the seat.
func _head_home(w: Walker, p: Person) -> void:
	_leave_queue(w)
	p.errand = Errand.NONE
	w.goal = Goal.SEAT
	w.hurried = true
	w.route = paths.home_from(w.position, p.spot, p.row, p.aisle)
	w.next = 1


func _leave_queue(w: Walker) -> void:
	if is_nan(w.booth.x):
		return
	(_queues.get(w.booth, []) as Array).erase(w)
	w.booth = Vector2(NAN, 0.0)
	w.serve_until = -1.0


## The camera turned away: what the walker was on its way to happens at once.
func _finish_now(w: Walker, p: Person) -> void:
	_leave_queue(w)
	if w.goal == Goal.SEAT:
		p.state = State.SEATED
		_finish_errand(p)
	elif w.goal == Goal.QUEUE:
		p.state = State.SEATED
		p.errand = Errand.NONE
		_eat(p)
	else:
		_go_away(p)
	changed[w.person] = true


# ------------------------------------------------------------------ vendors

## The stand ends early (AiquizStadiumStand.fit_end()): only `walk_z` (stand z,
## x < y) is shown. A vendor left outside it gives up its customer and starts
## again at the nearest point of its new stretch.
func set_walk_z(walk_z: Vector2) -> void:
	if walk_z == _walk_z:
		return
	_walk_z = walk_z
	_assign_vendor_ranges()
	for v: Vendor in vendors:
		if v.position.z >= v.range_z.x and v.position.z <= v.range_z.y:
			continue
		if v.customer >= 0:
			people[v.customer].served_by = -1
		v.customer = -1
		v.passes = []
		v.route = PackedVector3Array()
		v.position = paths.point(VENDOR_X, clampf(v.position.z, v.range_z.x, v.range_z.y))
		v.aisle = paths.nearest_aisle(v.position.z)
		v.yaw = FACE_COURSE
		_vendor_call(v)


## The vendors' stretches: the shown stand split evenly along its aisles.
func _assign_vendor_ranges() -> void:
	if vendors.is_empty() or paths.aisles.is_empty():
		return
	var low := maxf(paths.aisles[0] - StandPaths.BLOCK_HALF, _walk_z.x)
	var high := minf(paths.aisles[paths.aisles.size() - 1] + StandPaths.BLOCK_HALF, _walk_z.y)
	var width := (high - low) / vendors.size()
	for k: int in range(vendors.size()):
		vendors[k].range_z = Vector2(low + width * k, low + width * (k + 1))


## Every vendor on the front deck in the middle of its stretch, calling out.
func _place_vendors() -> void:
	_assign_vendor_ranges()
	for v: Vendor in vendors:
		v.position = paths.point(VENDOR_X, (v.range_z.x + v.range_z.y) * 0.5)
		v.aisle = paths.nearest_aisle(v.position.z)
		v.route = PackedVector3Array()
		v.passes = []
		v.customer = -1
		v.yaw = FACE_COURSE
		_vendor_call(v)


func _vendor_covers(z: float) -> bool:
	for v: Vendor in vendors:
		if z >= v.range_z.x and z < v.range_z.y:
			return true
	return false


func _step_vendors(delta: float, mood: CrowdMood) -> void:
	for k: int in range(vendors.size()):
		var v := vendors[k]
		match v.state:
			VendorState.CALLING:
				_vendor_play(v, &"SPEC_VendorCall", 1.0, delta)
				if not _take_call(k, v, mood) and now >= v.until:
					_patrol(v)
			VendorState.PATROL:
				if not _take_call(k, v, mood) and _vendor_walk(v, delta):
					_vendor_call(v)
			VendorState.TO_ROW:
				if _vendor_walk(v, delta):
					_start_delivery(v)
			VendorState.HANDING:
				v.yaw += clampf(angle_difference(v.yaw, v.face), -TURN_RATE * delta, TURN_RATE * delta)
				_vendor_play(v, v.clip, 1.0, delta, v.loop)
				_step_delivery(v)
			VendorState.THANKS:
				_vendor_play(v, &"SPEC_VendorCall", 1.0, delta)
				if now >= v.until:
					v.state = VendorState.BACK
					v.route = PackedVector3Array([v.position, paths.point(VENDOR_X, v.position.z)])
					v.next = 1
			VendorState.BACK:
				if _vendor_walk(v, delta):
					_vendor_call(v)


func _vendor_call(v: Vendor) -> void:
	v.state = VendorState.CALLING
	v.until = now + _rng.randf_range(PATROL_CALL.x, PATROL_CALL.y)


## Along the front deck to another aisle of the stretch.
func _patrol(v: Vendor) -> void:
	var stops: Array[float] = []
	for aisle: float in paths.aisles:
		if aisle >= v.range_z.x and aisle < v.range_z.y and absf(aisle - v.position.z) > 1.0:
			stops.append(aisle)
	var z := (v.range_z.x + v.range_z.y) * 0.5
	if not stops.is_empty():
		z = stops[_rng.randi_range(0, stops.size() - 1)]
	v.route = PackedVector3Array([v.position, paths.point(VENDOR_X, z)])
	v.next = 1
	v.state = VendorState.PATROL


## The nearest raised hand in the vendor's stretch nobody serves yet: up its
## aisle to the step level with the row, on the row's side.
func _take_call(k: int, v: Vendor, mood: CrowdMood) -> bool:
	if mood.hurry or mood.finished or _calls.is_empty():
		return false
	var best := -1
	for index: int in _calls:
		var p := people[index]
		if p.served_by >= 0 or p.seat.z < v.range_z.x or p.seat.z >= v.range_z.y:
			continue
		if best < 0 or absf(p.seat.z - v.position.z) < absf(people[best].seat.z - v.position.z):
			best = index
	if best < 0:
		return false
	var p := people[best]
	p.served_by = k
	v.customer = best
	v.aisle = p.aisle
	var side := 1.0 if p.seat.z >= p.aisle else -1.0
	var z := p.aisle + side * VENDOR_SIDE
	var stop := paths.front_x + paths.tread * p.row + VENDOR_ROW_IN
	v.route = PackedVector3Array([v.position, paths.point(VENDOR_X, z), paths.point(stop, z)])
	v.next = 1
	v.face = 0.0 if side > 0.0 else PI
	v.state = VendorState.TO_ROW
	return true


## Moves the vendor along its route; true once it is there.
func _vendor_walk(v: Vendor, delta: float) -> bool:
	var budget := VENDOR_SPEED * delta
	var moved := false
	for _leg: int in range(4):
		if v.next >= v.route.size() or budget <= 0.0:
			break
		var target := v.route[v.next]
		var flat := Vector3(target.x - v.position.x, 0.0, target.z - v.position.z)
		var distance := flat.length()
		if distance < 0.005:
			v.next += 1
			continue
		var stairs := paths.pace(v.position.x, v.position.z, v.aisle)
		var step := minf(distance, budget * stairs)
		v.position.x += flat.x / distance * step
		v.position.z += flat.z / distance * step
		budget -= step / stairs
		v.yaw += clampf(angle_difference(v.yaw, atan2(flat.x, flat.z)), -TURN_RATE * delta, TURN_RATE * delta)
		moved = true
	if v.position.x < paths.front_x:
		v.aisle = paths.nearest_aisle(v.position.z)
	v.position.y = lerpf(v.position.y, paths.floor_y(v.position.x, v.position.z, v.aisle), 1.0 - exp(-STEP_EASE * delta))
	if moved:
		_vendor_play(v, &"SPEC_VendorWalk", VENDOR_SPEED / SeatedSpectatorKit.clip_ground_speed(&"SPEC_VendorWalk"), delta)
		return false
	return v.next >= v.route.size()


func _vendor_play(v: Vendor, clip: StringName, rate: float, delta: float, loop := true) -> void:
	if clip != v.clip:
		v.clip = clip
		v.phase = 0.0
	v.rate = rate
	v.loop = loop
	v.phase += delta * rate


## At the row: the vendor hands a cup to the seat at the row's end, it goes from
## neighbour to neighbour to the customer, and the money comes back the same way.
## Empty seats are skipped.
func _start_delivery(v: Vendor) -> void:
	var p := people[v.customer]
	var toward := 1.0 if p.seat.z >= v.aisle else -1.0
	# A seated spectator's left (+X of the rig) is stand +Z.
	var give := &"SPEC_PassItemL" if toward > 0.0 else &"SPEC_PassItemR"
	var back := &"SPEC_PassItemR" if toward > 0.0 else &"SPEC_PassItemL"
	var chain := _chain(p, v.aisle, v.customer)
	v.passes = [[-1, &"SPEC_VendorHand", true]]
	for index: int in chain:
		v.passes.append([index, give, true])
	v.passes.append([v.customer, back, false])
	chain.reverse()
	for index: int in chain:
		v.passes.append([index, back, false])
	v.passes.append([-1, &"", false])
	v.step = -1
	v.state = VendorState.HANDING


## The row's seats between the aisle and the customer, nearest the aisle first.
func _chain(p: Person, aisle: float, customer: int) -> Array[int]:
	var side := 1.0 if p.seat.z >= aisle else -1.0
	var reach := (p.seat.z - aisle) * side
	var out: Array[int] = []
	for index: int in _rows.get(Vector2i(p.block, p.row), []):
		var d := (people[index].seat.z - aisle) * side
		if index != customer and d > 0.0 and d < reach:
			out.append(index)
	out.sort_custom(func(a: int, b: int) -> bool: return absf(people[a].seat.z - aisle) < absf(people[b].seat.z - aisle))
	return out


## The next hand-over once the last one has let go (HAND_AT into its clip).
func _step_delivery(v: Vendor) -> void:
	if v.step >= 0 and now - v.step_at < HAND_AT:
		return
	v.step += 1
	while v.step < v.passes.size():
		var hand: Array = v.passes[v.step]
		var who: int = hand[0]
		if who < 0:
			if hand[1] == &"":
				break
			_vendor_play(v, hand[1], 1.0, 0.0, false)
			v.step_at = now
			return
		var p := people[who]
		if who == v.customer:
			# The cup has arrived: the customer drinks and hands the money back.
			_hand_down(who, p)
			if p.state == State.SEATED:
				_eat(p, FOOD_DRINK)
				stats.delivered += 1
		if p.state != State.SEATED:
			v.step += 1
			continue
		p.pass_clip = hand[1]
		p.pass_start = now
		p.carry = FOOD_DRINK if bool(hand[2]) else 0
		_passing.append(who)
		changed[who] = true
		v.step_at = now
		return
	if v.customer >= 0:
		people[v.customer].served_by = -1
		_hand_down(v.customer, people[v.customer])
	v.customer = -1
	v.state = VendorState.THANKS
	v.until = now + THANKS_SECONDS


## Hand-overs that have ended give the seat back to its usual clips.
func _step_passing() -> void:
	if _passing.is_empty():
		return
	var still: Array[int] = []
	for index: int in _passing:
		var p := people[index]
		if p.pass_clip != &"" and now - p.pass_start < PASS_SECONDS:
			still.append(index)
		elif p.pass_clip != &"":
			p.pass_clip = &""
			p.carry = 0
			changed[index] = true
	_passing = still


## The camera turned away while vendor `k` was on its way to a row: it turns back
## to the front deck (and the customer is served out of sight). False once it
## has started handing over.
func _release_vendor(k: int) -> bool:
	var v := vendors[k]
	if v.state != VendorState.TO_ROW:
		return false
	if v.customer >= 0:
		people[v.customer].served_by = -1
	v.customer = -1
	v.state = VendorState.BACK
	v.route = PackedVector3Array([v.position, paths.point(VENDOR_X, v.position.z)])
	v.next = 1
	return true


## Lowers a raised hand.
func _hand_down(index: int, p: Person) -> void:
	if not p.calling:
		return
	p.calling = false
	_calls.erase(index)
	changed[index] = true
