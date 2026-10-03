extends RefCounted

## Shots for tall score towers. The baked Blender camera is framed for the old 2.6 m
## top; once a tower climbs past it the finale camera blends into these:
## - while the towers climb (and for a whole draw): a low front two-shot of both;
## - a win, once the towers have stopped: the lens moves in close beside the loser,
##   low at their front-outer side, and looks up past them at the winner on the tall
##   tower (it rides down with the loser's sinking tower and keeps them in frame
##   when they kneel).
## Everything is in stage space (winner's tower at -X, loser's at +X, front at +Z),
## so the caller applies the same stage turn / P2 mirror as the baked track.

const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
## Tower height where the baked track stops fitting, and where these shots own it.
const TALL_START := 2.6
const TALL_FULL := 3.6
## Screen space kept free (fractions of the frame). The "スコアタワー" title owns
## the top band until it fades (hud_motion.json: 6.25-6.5 s) and the score cards
## own the bottom band until they fly to the top corner (7.57-8.2 s).
const MARGIN_SIDE := 0.08
const MARGIN_TOP := 0.2
const MARGIN_TOP_CLEAR := 0.08
const MARGIN_BOTTOM := 0.28
const MARGIN_BOTTOM_CLEAR := 0.06
const TITLE_OUT := Vector2(6.2, 6.5)
const CARDS_OUT := Vector2(7.55, 8.2)
## Player box on a pad: body, hat and the crown above it.
const BOX_HALF_WIDTH := 0.65
const BOX_HALF_DEPTH := 0.5
const BOX_HEIGHT := 2.4

## Side shot: the eye sits at the loser's hip, out at their front-outer side, so the
## loser fills one lower corner and the winner towers in the opposite upper one.
const SIDE_DIRECTION := Vector3(0.45, 0.0, 0.9)
const SIDE_EYE_HEIGHT := 0.9
## The eye drops with the loser as they kneel so their bowed head stays in frame.
const SIDE_EYE_KNEEL_HEIGHT := 0.4
const SIDE_DISTANCE := 3.0
const SIDE_DISTANCE_MAX := 14.0
const SIDE_FOV_MIN := 55.0
const SIDE_FOV_MAX := 76.0
## Loser's head and shoulders; once they kneel (orz at 9.15 s) the box reaches down
## to the bowed head.
const SIDE_LOSER_HALF_WIDTH := 0.4
const SIDE_LOSER_TOP := 2.05
const SIDE_LOSER_BOTTOM := 1.45
const SIDE_LOSER_KNEEL_BOTTOM := 0.6
const KNEEL := Vector2(8.8, 9.3)
## The front shot hands over to the side shot once the towers stop: the leader
## locks about 6.27 s and its bump settles by 6.45 s.
const SIDE_IN := Vector2(6.45, 7.25)

## Front two-shot (the climb, and a draw).
const FRONT_FOV := 48.0
const FRONT_EYE_ABOVE_LOWER_PAD := 0.8
const FRONT_EYE_MIN := 0.8
const FRONT_EYE_MAX := 2.0
const FRONT_DISTANCE_MIN := 7.0
const FRONT_DISTANCE_MAX := 40.0


static func tall_weight(heights: Vector2) -> float:
	return smoothstep(TALL_START, TALL_FULL, maxf(heights.x, heights.y))


## {transform, fov} for the tall-tower shot; `winner` 0 is a draw.
static func shot(heights: Vector2, winner: int, time: float) -> Dictionary:
	var side := side_weight(winner, time)
	if side >= 1.0:
		return side_shot(heights, time)
	var front := front_shot(heights)
	if side <= 0.0:
		return front
	var beside := side_shot(heights, time)
	var a: Transform3D = front.transform
	var b: Transform3D = beside.transform
	return {"transform": Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), side)),
		a.origin.lerp(b.origin, side)), "fov": lerpf(float(front.fov), float(beside.fov), side)}


## 0 = front two-shot, 1 = beside the loser.
static func side_weight(winner: int, time: float) -> float:
	return 0.0 if winner == 0 else smoothstep(SIDE_IN.x, SIDE_IN.y, time)


## Free-frame margins (side, top, bottom) the shot keeps at `time`.
static func margins(winner: int, time: float) -> Vector3:
	if winner == 0:
		return Vector3(MARGIN_SIDE, MARGIN_TOP, MARGIN_BOTTOM)
	return Vector3(MARGIN_SIDE,
		lerpf(MARGIN_TOP, MARGIN_TOP_CLEAR, smoothstep(TITLE_OUT.x, TITLE_OUT.y, time)),
		lerpf(MARGIN_BOTTOM, MARGIN_BOTTOM_CLEAR, smoothstep(CARDS_OUT.x, CARDS_OUT.y, time)))


## Points the shot keeps inside the free part of a 16:9 frame.
static func framing_points(heights: Vector2, winner: int, time: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	_add_box(points, AABB(Vector3(-Motion.TOWER_X - BOX_HALF_WIDTH, heights.x, -BOX_HALF_DEPTH),
		Vector3(BOX_HALF_WIDTH * 2.0, BOX_HEIGHT, BOX_HALF_DEPTH * 2.0)))
	if winner == 0:
		_add_box(points, AABB(Vector3(Motion.TOWER_X - BOX_HALF_WIDTH, heights.y, -BOX_HALF_DEPTH),
			Vector3(BOX_HALF_WIDTH * 2.0, BOX_HEIGHT, BOX_HALF_DEPTH * 2.0)))
	else:
		var bottom := lerpf(SIDE_LOSER_BOTTOM, SIDE_LOSER_KNEEL_BOTTOM, kneel(time))
		_add_box(points, AABB(Vector3(Motion.TOWER_X - SIDE_LOSER_HALF_WIDTH, heights.y + bottom, -SIDE_LOSER_HALF_WIDTH),
			Vector3(SIDE_LOSER_HALF_WIDTH * 2.0, SIDE_LOSER_TOP - bottom, SIDE_LOSER_HALF_WIDTH * 2.0)))
	return points


## 0 while the loser stands, 1 once they kneel.
static func kneel(time: float) -> float:
	return smoothstep(KNEEL.x, KNEEL.y, time)


static func side_shot(heights: Vector2, time: float) -> Dictionary:
	var points := framing_points(heights, 1, time)
	var free := margins(1, time)
	var anchor := Vector3(Motion.TOWER_X, heights.y + lerpf(SIDE_EYE_HEIGHT, SIDE_EYE_KNEEL_HEIGHT, kneel(time)), 0.0)
	var direction := SIDE_DIRECTION.normalized()
	# Stay close to the loser and widen the lens first; step back only when even
	# the widest lens cannot hold the winner.
	var fov := SIDE_FOV_MAX
	var distance := SIDE_DISTANCE
	if _fits(points, anchor + direction * distance, fov, free):
		var lower := SIDE_FOV_MIN
		var upper := SIDE_FOV_MAX
		if _fits(points, anchor + direction * distance, lower, free):
			upper = lower
		else:
			for _iteration in range(14):
				fov = (lower + upper) * 0.5
				if _fits(points, anchor + direction * distance, fov, free):
					upper = fov
				else:
					lower = fov
		fov = upper
	else:
		var lower := SIDE_DISTANCE
		var upper := SIDE_DISTANCE_MAX
		for _iteration in range(14):
			distance = (lower + upper) * 0.5
			if _fits(points, anchor + direction * distance, fov, free):
				upper = distance
			else:
				lower = distance
		distance = upper
	var eye := anchor + direction * distance
	return {"transform": Transform3D(_aim(points, eye, fov, free), eye), "fov": fov}


static func front_shot(heights: Vector2) -> Dictionary:
	var points := framing_points(heights, 0, 0.0)
	var free := margins(0, 0.0)
	var eye := Vector3(0.0, clampf(minf(heights.x, heights.y) + FRONT_EYE_ABOVE_LOWER_PAD, FRONT_EYE_MIN, FRONT_EYE_MAX), FRONT_DISTANCE_MIN)
	if not _fits(points, eye, FRONT_FOV, free):
		var lower := FRONT_DISTANCE_MIN
		var upper := FRONT_DISTANCE_MAX
		for _iteration in range(16):
			eye.z = (lower + upper) * 0.5
			if _fits(points, eye, FRONT_FOV, free):
				upper = eye.z
			else:
				lower = eye.z
		eye.z = upper
	return {"transform": Transform3D(_aim(points, eye, FRONT_FOV, free), eye), "fov": FRONT_FOV}


static func _add_box(points: PackedVector3Array, box: AABB) -> void:
	for corner in range(8):
		points.append(box.get_endpoint(corner))


## Screen position for a camera basis: (x, y) in -1..1 with y up, z = depth.
static func _project(point: Vector3, eye: Vector3, basis: Basis, tan_y: float) -> Vector3:
	var relative := point - eye
	var depth := -relative.dot(basis.z)
	return Vector3(relative.dot(basis.x) / (depth * tan_y * 16.0 / 9.0), relative.dot(basis.y) / (depth * tan_y), depth)


## Level-horizon view (yaw and pitch only) that centres the points in the free band.
static func _aim(points: PackedVector3Array, eye: Vector3, fov: float, free: Vector3) -> Basis:
	var tan_y := tan(deg_to_rad(fov) * 0.5)
	var centre := Vector3.ZERO
	for point in points:
		centre += point
	var forward := (centre / float(points.size()) - eye).normalized()
	var free_centre := free.z - free.y
	for _iteration in range(12):
		var basis := Basis.looking_at(forward, Vector3.UP)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point in points:
			var screen := _project(point, eye, basis, tan_y)
			low = Vector2(minf(low.x, screen.x), minf(low.y, screen.y))
			high = Vector2(maxf(high.x, screen.x), maxf(high.y, screen.y))
		var offset := (low + high) * 0.5 - Vector2(0.0, free_centre)
		# Right is a negative turn about +Y; up is a positive turn about the camera's right.
		forward = forward.rotated(Vector3.UP, -atan(offset.x * tan_y * 16.0 / 9.0))
		forward = forward.rotated(Basis.looking_at(forward, Vector3.UP).x, atan(offset.y * tan_y))
		var limit := deg_to_rad(70.0)
		if absf(asin(clampf(forward.y, -1.0, 1.0))) > limit:
			var flat := Vector3(forward.x, 0.0, forward.z).normalized()
			forward = flat * cos(limit) + Vector3.UP * sin(limit) * signf(forward.y)
	return Basis.looking_at(forward, Vector3.UP)


static func _fits(points: PackedVector3Array, eye: Vector3, fov: float, free: Vector3) -> bool:
	var tan_y := tan(deg_to_rad(fov) * 0.5)
	var basis := _aim(points, eye, fov, free)
	for point in points:
		var screen := _project(point, eye, basis, tan_y)
		if screen.z < 0.5 or absf(screen.x) > 1.0 - 2.0 * free.x \
				or screen.y > 1.0 - 2.0 * free.y or screen.y < -1.0 + 2.0 * free.z:
			return false
	return true
