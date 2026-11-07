class_name StandPaths
extends RefCounted

## Where the side stand's walking crowd walks (docs/crowd_sim.md), in stand
## space: x away from the course, y up, z along the stand. Both stands use the
## same blocks (the left one turned PI), so the same numbers serve both. The
## stand's measures come with the blocks (aiquiz_stadium_stand_blocks.json
## "walk", configure()); the defaults are the same numbers.
##
## A walk: the spot in front of the seat -> the row's lane (behind the seat backs
## of the row below) -> the aisle's stairs (up on one side, down on the other) ->
## the rear walkway -> a kiosk's queue at a booth's end, or the stairwell beside
## the top of the aisle (the way in and out of the stand).

## A row is walked this far in front of its riser, behind the row below's seat backs.
const LANE_BEFORE_RISER := 0.18
## Up the stairs on the aisle's -Z side, down on its +Z side.
const AISLE_LANE := 0.45
## Off the aisle's stairs this far onto the walkway.
const STAIRS_TOP := 0.55
## People queue this far from the counter's edge, this far apart.
const QUEUE_CLEAR := 0.45
const QUEUE_GAP := 0.8
const QUEUE_MAX := 6
## Served people walk back beside the queue, this far onto the walkway.
const RETURN_IN := 0.3
## People spread this much across the stairwell, and stop this far short of the
## step down and of the door.
const EXIT_SPREAD := 0.3
const EXIT_BEFORE := 0.2
const EXIT_DOOR := 0.45
const BLOCK_HALF := 10.0
## Walking pace on stairs.
const STAIRS_PACE := 0.75

var front_x := 0.6              # front edge of row 0's tread
var tread := 1.25
var row_base_y := 0.32
var row_rise := 0.4
var rows := 6
var deck_y := 0.22
var step_tread := 0.625
var step_rise := 0.2
var steps := 12
var aisle_half := 1.1
var walkway_x := Vector2(8.05, 12.3)
var walkway_y := 2.72
var booth_kinds: Array[String] = ["bay", "bay_pergola"]
var booth_half := 1.7
var window_x := Vector2(9.0, 10.0)
var counter_depth := 0.28
## The stairwell: across the walkway (x), along it from the aisle (towards +Z).
var stairwell_x := Vector2(10.95, 12.05)
var stairwell_from := Vector2(0.6, 5.1)
var stairwell_steps := 12
var stairwell_landing := 1.1

## Stand z of every aisle, sorted.
var aisles := PackedFloat32Array()
## set_blocks() で増えた・なくなった通路（stand z、昇順）。CrowdSim.refresh_aisles() はこの近くの人だけを見直して空にする。
var changed_aisles := PackedFloat32Array()
## Stand z of every block with a booth.
var booths := PackedFloat32Array()


## Takes the stand's measures from the blocks' "walk" (missing keys keep the defaults).
func configure(walk: Dictionary) -> void:
	if walk.is_empty():
		return
	front_x = float(walk.get("front_x", front_x))
	tread = float(walk.get("row_tread", tread))
	row_base_y = float(walk.get("row_base_y", row_base_y))
	row_rise = float(walk.get("row_rise", row_rise))
	rows = int(walk.get("rows", rows))
	deck_y = float(walk.get("deck_y", deck_y))
	var aisle: Dictionary = walk.get("aisle", {})
	aisle_half = float(aisle.get("half_width", aisle_half))
	step_tread = float(aisle.get("step_tread", step_tread))
	step_rise = float(aisle.get("step_rise", step_rise))
	steps = int(aisle.get("steps", steps))
	var walkway: Dictionary = walk.get("walkway", {})
	walkway_x = _pair(walkway.get("x"), walkway_x)
	walkway_y = float(walkway.get("y", walkway_y))
	var booth: Dictionary = walk.get("booth", {})
	if booth.has("kinds"):
		booth_kinds.assign(booth.kinds)
	booth_half = float(booth.get("half_length", booth_half))
	window_x = _pair(booth.get("window_x"), window_x)
	counter_depth = float(booth.get("counter_depth", counter_depth))
	var stairwell: Dictionary = walk.get("stairwell", {})
	stairwell_x = _pair(stairwell.get("x"), stairwell_x)
	stairwell_from = _pair(stairwell.get("from_aisle"), stairwell_from)
	stairwell_steps = int(stairwell.get("steps", stairwell_steps))
	stairwell_landing = float(stairwell.get("landing", stairwell_landing))


static func _pair(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


## `centers`: each block's stand z; `kinds`: its kind (aiquiz_stadium_stand.gd);
## `aisle_list`: stand z of the aisles.
func set_blocks(centers: Array, kinds: Array, aisle_list: Array) -> void:
	var sorted: Array = aisle_list.duplicate()
	sorted.sort()
	var previous := aisles
	aisles = PackedFloat32Array(sorted)
	var difference := _difference(previous, aisles)
	if not difference.is_empty():
		changed_aisles.append_array(difference)
		changed_aisles.sort()
	booths = PackedFloat32Array()
	for index: int in range(mini(centers.size(), kinds.size())):
		if String(kinds[index]) in booth_kinds:
			booths.append(float(centers[index]))


## 昇順の a と b の片方にだけある値（昇順）。
static func _difference(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var i := 0
	var j := 0
	while i < a.size() or j < b.size():
		if i < a.size() and j < b.size() and a[i] == b[j]:
			i += 1
			j += 1
		elif j >= b.size() or (i < a.size() and a[i] < b[j]):
			out.append(a[i])
			i += 1
		else:
			out.append(b[j])
			j += 1
	return out


func row_y(row: int) -> float:
	return row_base_y + row_rise * row


func lane_x(row: int) -> float:
	return front_x + tread * row - LANE_BEFORE_RISER


func stairs_top_x() -> float:
	return walkway_x.x + STAIRS_TOP


func queue_x() -> float:
	return (window_x.x + window_x.y) * 0.5


func nearest_aisle(z: float) -> float:
	var best := INF
	# aisles は昇順なので、z の前後（z と同じ値の並びとその両隣）だけ見れば、前から全部見たときと同じ答えになる。
	var first := maxi(aisles.bsearch(z, true) - 1, 0)
	var last := mini(aisles.bsearch(z, false) + 1, aisles.size())
	for index: int in range(first, last):
		var aisle: float = aisles[index]
		if absf(aisle - z) < absf(best - z):
			best = aisle
	return best


## The floor under (x, z): the front deck, a row's tread, a stair of the aisle,
## the walkway or a step of the stairwell. `aisle`: the aisle nearby when the
## caller knows it (a walker keeps to its own).
func floor_y(x: float, z: float, aisle := NAN) -> float:
	var near := nearest_aisle(z) if is_nan(aisle) else aisle
	if x >= walkway_x.x:
		var along := z - near
		if x >= stairwell_x.x and x <= stairwell_x.y and along >= stairwell_from.x and along <= stairwell_from.y:
			var run := stairwell_from.y - stairwell_from.x - stairwell_landing
			var down := along - stairwell_from.x
			if down >= run:
				return deck_y
			var rise := (walkway_y - deck_y) / (stairwell_steps + 1)
			return walkway_y - rise * (floorf(down / (run / stairwell_steps)) + 1.0)
		return walkway_y
	if x < front_x:
		return deck_y
	if absf(z - near) <= aisle_half:
		return row_base_y + step_rise * minf(steps - 1, floorf((x - front_x) / step_tread))
	return row_y(clampi(int(floorf((x - front_x) / tread)), 0, rows - 1))


## Pace on the floor under (x, z) next to `aisle`: slower on stairs.
func pace(x: float, z: float, aisle: float) -> float:
	if x >= front_x and x < walkway_x.x and absf(z - aisle) <= aisle_half:
		return STAIRS_PACE
	if _in_stairwell(x, z, aisle):
		return STAIRS_PACE
	return 1.0


func _in_stairwell(x: float, z: float, aisle: float) -> bool:
	var along := z - aisle
	return x >= stairwell_x.x - 0.05 and x <= stairwell_x.y + 0.05 \
		and along >= stairwell_from.x - 0.05 and along <= stairwell_from.y


func point(x: float, z: float) -> Vector3:
	return Vector3(x, floor_y(x, z), z)


static func up_lane(aisle: float) -> float:
	return aisle - AISLE_LANE


static func down_lane(aisle: float) -> float:
	return aisle + AISLE_LANE


## From the spot in front of a seat in `row` up the stairs of `aisle`.
func seat_to_walkway(spot: Vector3, row: int, aisle: float) -> PackedVector3Array:
	var lane := lane_x(row)
	var up := up_lane(aisle)
	return PackedVector3Array([spot, point(lane, spot.z), point(lane, up), point(stairs_top_x(), up)])


## Down the stairs of `aisle` to the spot in front of a seat in `row`.
func walkway_to_seat(spot: Vector3, row: int, aisle: float) -> PackedVector3Array:
	var lane := lane_x(row)
	var down := down_lane(aisle)
	return PackedVector3Array([point(stairs_top_x(), down), point(lane, down), point(lane, spot.z), spot])


## Into the stairwell beside `aisle` and down to its door; `spread` -1..1 picks
## the line across the stairs.
func to_exit(aisle: float, spread := 0.0) -> PackedVector3Array:
	var x := (stairwell_x.x + stairwell_x.y) * 0.5 + EXIT_SPREAD * spread
	return PackedVector3Array([point(x, aisle + stairwell_from.x - EXIT_BEFORE), point(x, aisle + stairwell_from.y - EXIT_DOOR)])


## Up from the stairwell's door onto the walkway.
func from_exit(aisle: float, spread := 0.0) -> PackedVector3Array:
	var route := to_exit(aisle, spread)
	route.reverse()
	return route


## Back home from wherever on the way: up out of the stairwell, off the walkway
## (beside the queue) down the aisle, back down the stairs, or along the row.
func home_from(at: Vector3, spot: Vector3, row: int, aisle: float) -> PackedVector3Array:
	var route := PackedVector3Array([at])
	if at.x >= walkway_x.x - 0.1:
		if _in_stairwell(at.x, at.z, aisle):
			route.append(point(at.x, aisle + stairwell_from.x - EXIT_BEFORE))
		elif at.x > walkway_x.x + RETURN_IN + 0.3:
			# Off the queue's line first, then along beside it.
			route.append(point(walkway_x.x + RETURN_IN, at.z))
		route.append_array(walkway_to_seat(spot, row, aisle))
		return route
	var lane := lane_x(row)
	if absf(at.z - aisle) <= aisle_half:
		var down := down_lane(aisle)
		route.append(point(at.x, down))
		route.append(point(lane, down))
	route.append(point(lane, spot.z))
	route.append(spot)
	return route


## The kiosk windows reachable along the walkway from `aisle`: Vector2(the
## booth end's z, the way the queue grows from it, towards the aisle).
func booths_from(aisle: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for center: float in booths:
		if absf(center - (aisle + BLOCK_HALF)) < 0.5:
			out.append(Vector2(center - booth_half, -1.0))
		elif absf(center - (aisle - BLOCK_HALF)) < 0.5:
			out.append(Vector2(center + booth_half, 1.0))
	return out


## Place `index` (0 at the counter) in the queue at `face` (booths_from()).
func queue_point(face: Vector2, index: int) -> Vector3:
	return point(queue_x(), face.x + face.y * (counter_depth + QUEUE_CLEAR + QUEUE_GAP * index))
