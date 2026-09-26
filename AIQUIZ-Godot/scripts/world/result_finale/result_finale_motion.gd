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


static func stop_height(total: int, max_total: int) -> float:
	var h := heights()
	if max_total <= 0:
		return float(h.pop)
	return float(h.pop) + (float(h.top) - float(h.pop)) * clampf(float(total) / float(max_total), 0.0, 1.0)


## Platform height above the conveyor for one player's tower.
## The leader (or both, on a draw) rides the authored Blender curve to the top.
static func tower_height(total: int, max_total: int, draw: bool, time: float) -> float:
	var lift := winner_lift(time)
	var window: Array = data().climb_window
	if max_total <= 0:
		return minf(lift, float(heights().pop))
	if draw or total >= max_total:
		return lift
	var stop := stop_height(total, max_total)
	if time < float(window[0]):
		return lift
	if time >= beat("sink_start"):
		return stop - (stop - float(heights().collar)) * lose_sink(time)
	var lock := lock_time(total, max_total)
	if time < lock:
		return minf(lift, stop)
	var u := clampf((time - lock) / LOCK_BUMP_TIME, 0.0, 1.0)
	return stop + LOCK_BUMP * sin(u * PI) * (1.0 - u * 0.4)
