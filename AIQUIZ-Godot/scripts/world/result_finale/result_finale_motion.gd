class_name ResultFinaleMotion
extends RefCounted

## Evaluated Blender data for the Score Tower Finale and the score -> tower rules.
## Source: assets/result_finale/source (build_set.py, animate_finale.py, export_finale.py).
## Times are real ceremony seconds (0 = both players reached the goal).

const MOTION_PATH := "res://assets/result_finale/finale_motion.json"
const FPS := 60.0
const FLOOR_TOP_Y := -1.2
const TOWER_X := 2.2
const CAST_START := 2.0
const VERDICT := 6.9
const LOCK_BUMP := 0.06
const LOCK_BUMP_TIME := 0.18
## Towers grow one tier per point (totals are half-points, so 2 per tier).
const TIER_POINTS_HALF := 2
const TIER_HEIGHT := 0.30
## Tiers on the column: a perfect 35 points is 35 tiers.
const TIER_COUNT := 36

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


static func beat(name: String) -> float:
	return float((data().beats as Dictionary).get(name, 0.0))


static func end_time() -> float:
	return float(data().last_frame) / FPS


## Authored performance clock. After the final key the cast keeps living on a
## seamless loop (the loser sobs, the referee waves) while controls wait.
static func performance_time(elapsed: float) -> float:
	var end := end_time()
	if elapsed <= end:
		return maxf(elapsed, 0.0)
	var loop_start := float(data().loop_start)
	return loop_start + fposmod(elapsed - end, end - loop_start)


static func _frame(track: Array, time: float) -> Vector3:
	var f := clampf(time * FPS, 0.0, float(track.size() - 1))
	var index := int(f)
	return Vector3(index, mini(index + 1, track.size() - 1), f - float(index))


static func sample_scalar(track: Array, time: float) -> float:
	var f := _frame(track, time)
	return lerpf(float(track[int(f.x)]), float(track[int(f.y)]), f.z)


static func _quat(row: Array, offset: int) -> Quaternion:
	return Quaternion(row[offset], row[offset + 1], row[offset + 2], row[offset + 3]).normalized()


static func sample_quat(track: Array, time: float) -> Quaternion:
	var f := _frame(track, time)
	return _quat(track[int(f.x)], 0).slerp(_quat(track[int(f.y)], 0), f.z)


## Rows are [px, py, pz, qx, qy, qz, qw] with an optional uniform scale.
static func sample_pose(track: Array, time: float) -> Transform3D:
	var f := _frame(track, time)
	var a: Array = track[int(f.x)]
	var b: Array = track[int(f.y)]
	var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), f.z)
	var basis := Basis(_quat(a, 3).slerp(_quat(b, 3), f.z))
	if a.size() > 7:
		basis = basis.scaled(Vector3.ONE * lerpf(float(a[7]), float(b[7]), f.z))
	return Transform3D(basis, origin)


static func sample_actor(side: String, time: float) -> Transform3D:
	return sample_pose(data().actors[side].actor, time)


static func sample_joint(side: String, joint: String, time: float) -> Quaternion:
	return sample_quat(data().actors[side].joints[joint], time)


static func sample_fists(side: String, time: float) -> Vector2:
	var track: Array = data().actors[side].fist
	var f := _frame(track, time)
	var a: Array = track[int(f.x)]
	var b: Array = track[int(f.y)]
	return Vector2(a[0], a[1]).lerp(Vector2(b[0], b[1]), f.z)


static func sample_prop(name: String, time: float) -> Transform3D:
	return sample_pose(data()[name], time)


## Stage-space camera ({transform, fov}); the stage node is rotated PI about Y.
static func sample_camera(draw: bool, time: float) -> Dictionary:
	var track: Array = data().cameras["draw" if draw else "win"]
	var f := _frame(track, time)
	var a: Array = track[int(f.x)]
	var b: Array = track[int(f.y)]
	var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), f.z)
	var rotation := _quat(a, 3).slerp(_quat(b, 3), f.z)
	return {"transform": Transform3D(Basis(rotation), origin), "fov": lerpf(float(a[7]), float(b[7]), f.z)}


static func joints() -> Array:
	return data().joints


# ------------------------------------------------------------------ score rules

static func climb(time: float) -> float:
	return sample_scalar(data().climb, time)


static func winner_lift(time: float) -> float:
	return sample_scalar(data().win_lift, time)


static func lose_sink(time: float) -> float:
	return sample_scalar(data().lose_sink, time)


static func heights() -> Dictionary:
	return data().heights


## Both counters tick at the same points-per-second, so the lower total stops first.
static func display_count(total: int, max_total: int, time: float) -> int:
	if max_total <= 0:
		return 0
	return mini(total, int(floor(float(max_total) * climb(time) + 0.0001)))


## First moment a counter has reached its total.
static func lock_time(total: int, max_total: int) -> float:
	var track: Array = data().climb
	var window: Array = data().climb_window
	if max_total <= 0 or total <= 0:
		return float(window[0])
	for frame in range(track.size()):
		if float(max_total) * float(track[frame]) + 0.0001 >= float(total):
			return float(frame) / FPS
	return float(window[1])


## Resting height for a total: the pad pop plus one TIER_HEIGHT per point,
## whatever the other player scored (half a tier shows half a tier).
static func stop_height(total: int) -> float:
	return float(heights().pop) + TIER_HEIGHT * float(maxi(total, 0)) / float(TIER_POINTS_HALF)


## Platform height above the conveyor for one player's tower. Before the climb both
## ride the authored pad pop; then each tower rises with its own counter (both count
## at the same points per second), bumps when it locks, and the loser sinks later.
## force_sink: the sudden death loser sinks although the scores are level.
static func tower_height(total: int, max_total: int, time: float, force_sink := false) -> float:
	var base := minf(winner_lift(time), float(heights().pop))
	if max_total <= 0 or total <= 0:
		return base
	var counted := minf(float(total), float(max_total) * climb(time))
	var height := base + TIER_HEIGHT * counted / float(TIER_POINTS_HALF)
	if time >= beat("sink_start") and (total < max_total or force_sink):
		var stop := stop_height(total)
		return stop - (stop - float(heights().collar)) * lose_sink(time)
	var lock := lock_time(total, max_total)
	if time < lock:
		return height
	var u := clampf((time - lock) / LOCK_BUMP_TIME, 0.0, 1.0)
	return height + LOCK_BUMP * sin(u * PI) * (1.0 - u * 0.4)


## A draw that branches into the sudden death (docs/sudden_death_underground.md 2.1):
## both towers stand at their score, then sink together into the elevator deck from
## `sink_from` on the authored loser curve (1.4 s), down to the collar.
static func branch_height(total: int, max_total: int, time: float, sink_from: float) -> float:
	var standing := tower_height(total, max_total, minf(time, sink_from))
	if time < sink_from:
		return standing
	var u := lose_sink(beat("sink_start") + (time - sink_from))
	return standing - (standing - float(heights().collar)) * u


## Tower heights in stage space: x = the -X tower (the winner's, or P1's on a
## draw), y = the +X tower. Mirrors ResultFinaleStage._side_x.
## The sudden death loser's tower sank into the deck before the verdict replays.
static func side_heights(p1_total: int, p2_total: int, winner: int, time: float, sudden_death_loser := 0) -> Vector2:
	var max_total := maxi(p1_total, p2_total)
	var collar := float(heights().collar)
	var p1 := collar if sudden_death_loser == 1 else tower_height(p1_total, max_total, time)
	var p2 := collar if sudden_death_loser == 2 else tower_height(p2_total, max_total, time)
	return Vector2(p2, p1) if winner == 2 else Vector2(p1, p2)
