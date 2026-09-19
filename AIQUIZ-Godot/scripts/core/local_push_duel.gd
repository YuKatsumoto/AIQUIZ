extends RefCounted
## Local, horizontal body contact and shoulder strikes. No shark impulses or render state.

const STALEMATE_TIME := 0.10
const ARM_GRACE := 0.20
const WINDUP := 0.06
const CLASH_WINDOW := 0.05
const COOLDOWN := 0.24
const PUSH_DISTANCE := 0.52
const PUSH_TIME := 0.12
const BODY_WIDTH := 1.24
const HELD_SPEED := 1.35
const SLICE := 1.0 / 240.0

var time := 0.0
var contact := false
var order := 1.0 # direction from P1 to P2; refreshed after a jump clears contact
var stalemate := 0.0
var armed_until := -1.0
var held := [0, 0]
var released := [false, false]
var cooldown_until := [0.0, 0.0]
var pending := [-1.0, -1.0]
var attack_start := [-10.0, -10.0]
var hit_start := [-10.0, -10.0]
var recoil_start := [-10.0, -10.0]
var shove_start := [-10.0, -10.0]
var shove_direction := [0.0, 0.0]
var pose_direction := [1.0, -1.0]
var brace := [0.0, 0.0]
var clash_pose := [false, false]
var inputs: Array[Dictionary] = []
var events: Array[Dictionary] = []
var _valid := [true, true]
var _grounded := [true, true]
var _x := Vector2.ZERO
var _minimum := BODY_WIDTH

func reset() -> void:
	time = 0.0
	contact = false
	order = 1.0
	stalemate = 0.0
	armed_until = -1.0
	held = [0, 0]
	released = [false, false]
	cooldown_until = [0.0, 0.0]
	pending = [-1.0, -1.0]
	attack_start = [-10.0, -10.0]
	hit_start = [-10.0, -10.0]
	recoil_start = [-10.0, -10.0]
	shove_start = [-10.0, -10.0]
	shove_direction = [0.0, 0.0]
	pose_direction = [1.0, -1.0]
	clash_pose = [false, false]
	brace = [0.0, 0.0]
	_valid = [true, true]
	_grounded = [true, true]
	_x = Vector2.ZERO
	_minimum = BODY_WIDTH
	inputs.clear()
	events.clear()

func suspend(key_masks: Array = [0, 0]) -> void:
	inputs.clear()
	held = key_masks.duplicate()
	released = [false, false]
	pending = [-1.0, -1.0]
	attack_start = [-10.0, -10.0]
	armed_until = -1.0
	stalemate = 0.0

## offset is relative to the next update, preserving transitions inside one render frame.
func queue_key(player: int, direction: int, pressed: bool, offset := 0.0, echo := false) -> void:
	if echo or player < 1 or player > 2 or absi(direction) != 1:
		return
	inputs.append({"player": player - 1, "direction": direction, "pressed": pressed,
		"at": time + maxf(0.0, offset), "sequence": inputs.size()})

func presentation(player: int) -> Dictionary:
	var i := player - 1
	if not _valid[i]:
		return {}
	var attack_age: float = time - attack_start[i]
	var hit_age: float = time - hit_start[i]
	var recoil_age: float = time - recoil_start[i]
	var brace_weight: float = brace[i] if _grounded[i] else 0.0
	var lean: float = 6.0 * brace_weight
	var shoulder := 0.0
	var hip_drop := 0.035 * brace_weight
	var phase := "brace" if brace_weight > 0.01 else "run"
	if pending[i] >= 0.0:
		var t := clampf(attack_age / WINDUP, 0.0, 1.0)
		lean = lerpf(6.0, -8.0, t * t)
		shoulder = -t
		hip_drop += 0.055 * t
		phase = "windup"
	elif _grounded[i] and hit_age >= 0.0 and attack_age < 0.24:
		var t := clampf(hit_age / 0.18, 0.0, 1.0)
		# Hold the impact briefly, then release into the ordinary brace/run pose.
		var release := smoothstep(0.02, 0.18, hit_age)
		lean = lerpf(20.0, 6.0 * brace_weight, release)
		shoulder = 1.0 - release
		hip_drop += 0.045 * (1.0 - release)
		if clash_pose[i]:
			lean = lerpf(14.0, 6.0 * brace_weight, release) - sin(t * PI) * 18.0
			shoulder -= sin(t * PI) * 1.2
		phase = "clash" if clash_pose[i] else "strike"
	var recoil := 0.0
	if recoil_age >= 0.0 and recoil_age < 0.18:
		lean *= recoil_age / 0.18
		recoil = 16.0 * (1.0 - smoothstep(0.02, 0.18, recoil_age)) * shove_direction[i]
		shoulder = -0.65 * (1.0 - recoil_age / 0.18)
		hip_drop = (0.035 * brace_weight + 0.055 * (1.0 - recoil_age / 0.18)) if _grounded[i] else 0.0
		phase = "recoil"
	return {"phase": phase, "brace": brace[i], "lean": lean * pose_direction[i] + recoil,
		"shoulder": shoulder, "hip_drop": hip_drop,
		"active": phase != "run", "grounded": _grounded[i], "direction": pose_direction[i]}

func advance(dt: float, positions: Vector2, z_separation: float, valid: Array,
		grounded: Array, axes: Vector2, speed: float, bodies_overlap := true) -> Vector2:
	_x = positions
	_valid = valid.duplicate()
	_grounded = grounded.duplicate()
	_minimum = sqrt(maxf(0.0, BODY_WIDTH * BODY_WIDTH - z_separation * z_separation)) if bodies_overlap else 0.0
	if not bodies_overlap:
		contact = false
		armed_until = -1.0
		released = [false, false]
	if not contact and absf(_x.y - _x.x) > 0.001:
		order = signf(_x.y - _x.x)
	var finish := time + maxf(0.0, dt)
	inputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.at < b.at if not is_equal_approx(a.at, b.at) else a.sequence < b.sequence)
	while time < finish - 0.0000001:
		_update_contact()
		_cancel_invalid()
		while not inputs.is_empty() and float(inputs[0].at) <= time + 0.0000001:
			_read_key(inputs.pop_front())
		# Both players' edges have been read before either pending strike resolves.
		_resolve_strikes()
		var next := minf(finish, time + SLICE)
		if not inputs.is_empty():
			next = minf(next, float(inputs[0].at))
		for i in range(2):
			if pending[i] > time + 0.0000001:
				next = minf(next, pending[i])
		var step := maxf(0.0000001, next - time)
		_move(step, axes, speed)
		var inward1 := axes.x * order > 0.0
		var inward2 := axes.y * order < 0.0
		if contact and inward1 and inward2:
			var was_armed := stalemate + 0.0000001 >= STALEMATE_TIME
			stalemate += step
			if stalemate + 0.0000001 >= STALEMATE_TIME:
				armed_until = next + ARM_GRACE
				if not was_armed:
					events.append({"kind": "stalemate", "time": next, "x": (_x.x + _x.y) * 0.5})
		else:
			stalemate = 0.0
		for i in range(2):
			brace[i] = move_toward(brace[i], 1.0 if contact and _grounded[i] else 0.0, step / 0.10)
			if not _valid[i]:
				brace[i] = 0.0
		time = next
	_update_contact()
	_cancel_invalid()
	while not inputs.is_empty() and float(inputs[0].at) <= time + 0.0000001:
		_read_key(inputs.pop_front())
	_resolve_strikes()
	return _x

func _update_contact() -> void:
	var touching: bool = _valid[0] and _valid[1] and _minimum > 0.001 and (_x.y - _x.x) * order <= _minimum + 0.002
	if touching and not contact:
		events.append({"kind": "contact", "time": time, "x": (_x.x + _x.y) * 0.5})
	contact = touching
	if contact:
		pose_direction = [order, -order]

func _cancel_invalid() -> void:
	for i in range(2):
		if not contact or not _grounded[i] or not _valid[i]:
			pending[i] = -1.0
			if time - hit_start[i] > 0.24:
				attack_start[i] = -10.0
		if not _valid[i]:
			recoil_start[i] = -10.0
			shove_start[i] = -10.0
			hit_start[i] = -10.0

func _read_key(event: Dictionary) -> void:
	var i: int = event.player
	var bit := 1 if int(event.direction) > 0 else 2
	var was_down: bool = (int(held[i]) & bit) != 0
	if not bool(event.pressed):
		held[i] = int(held[i]) & ~bit
		if was_down and time <= armed_until and float(event.direction) == pose_direction[i]:
			released[i] = true
		return
	held[i] = int(held[i]) | bit
	if held[i] == 3:
		pending[i] = -1.0
		released[i] = false
		return
	if was_down:
		return
	var eligible: bool = released[i] and contact and _grounded[i] and _valid[i] and time <= armed_until + 0.0000001 and time + 0.0000001 >= cooldown_until[i] and float(event.direction) == pose_direction[i]
	# Rejected edges are consumed, never buffered into a future cooldown.
	released[i] = false
	if eligible:
		cooldown_until[i] = time + COOLDOWN
		pending[i] = time + WINDUP
		attack_start[i] = time
		clash_pose[i] = false

func _resolve_strikes() -> void:
	if pending[0] >= 0.0 and pending[1] >= 0.0 and absf(attack_start[0] - attack_start[1]) <= CLASH_WINDOW + 0.0000001:
		if time + 0.0000001 >= minf(pending[0], pending[1]):
			for i in range(2):
				pending[i] = -1.0
				hit_start[i] = time
				attack_start[i] = time - WINDUP
				clash_pose[i] = true
			events.append({"kind": "clash", "time": time, "player": 0, "direction": 0.0, "x": (_x.x + _x.y) * 0.5})
		return
	for i in range(2):
		if pending[i] >= 0.0 and time + 0.0000001 >= pending[i]:
			pending[i] = -1.0
			hit_start[i] = time
			var target := 1 - i
			shove_start[target] = time
			recoil_start[target] = time
			shove_direction[target] = pose_direction[i]
			events.append({"kind": "hit", "time": time, "player": i + 1, "direction": pose_direction[i], "x": (_x.x + _x.y) * 0.5})

func _distance_at(age: float) -> float:
	var t := clampf(age / PUSH_TIME, 0.0, 1.0)
	return PUSH_DISTANCE * (2.0 * t - t * t)

func _move(dt: float, axes: Vector2, speed: float) -> void:
	var old := _x
	var dx := Vector2.ZERO
	var nudges := Vector2.ZERO
	for i in range(2):
		if not _valid[i]:
			continue
		var age: float = time - shove_start[i]
		var reduced := minf(dt, maxf(0.0, PUSH_TIME - age)) if age >= 0.0 else 0.0
		dx[i] = axes[i] * speed * (dt - reduced * 0.75)
		nudges[i] = (_distance_at(age + dt) - _distance_at(age)) * shove_direction[i]
		_x[i] += dx[i] + nudges[i]
	if _valid[0] and _valid[1] and _minimum > 0.001 and (_x.y - _x.x) * order < _minimum:
		var left := 0 if order > 0.0 else 1
		var right := 1 - left
		var penetration := _minimum - (_x[right] - _x[left])
		# During a shove the struck body's trajectory remains authoritative; the
		# pursuer is blocked behind it, so ordinary running cannot double the hit.
		if nudges[right] > 0.0:
			_x[left] = _x[right] - _minimum
		elif nudges[left] < 0.0:
			_x[right] = _x[left] + _minimum
		else:
			# Limit only the pressure between bodies, not their shared movement.
			# Even a roundoff-sized overlap can reach this path while running together.
			var shared := signf(dx.x) * minf(absf(dx.x), absf(dx.y)) if dx.x * dx.y > 0.0 else 0.0
			var common := shared + clampf((dx.x + dx.y) * 0.5 - shared, -HELD_SPEED * dt, HELD_SPEED * dt)
			if axes[left] > 0.0 and axes[right] < 0.0:
				common = 0.0
			var closing := maxf(0.0, dx[left] - dx[right])
			var fraction := clampf(penetration / closing, 0.0, 1.0) if closing > 0.0 else 1.0
			var center := (old.x + old.y) * 0.5 + (dx.x + dx.y) * 0.5 * (1.0 - fraction) + common * fraction
			_x[left] = center - _minimum * 0.5
			_x[right] = center + _minimum * 0.5
	_update_contact()

## Final X-only correction for external impulses or a change in Z separation.
func resolve(positions: Vector2, z_separation: float, bodies_overlap := true) -> Vector2:
	if not bodies_overlap:
		contact = false
		return positions
	if not contact and absf(positions.y - positions.x) > 0.001:
		order = signf(positions.y - positions.x)
	if not _valid[0] or not _valid[1] or absf(z_separation) >= BODY_WIDTH:
		return positions
	var width := sqrt(BODY_WIDTH * BODY_WIDTH - z_separation * z_separation)
	if (positions.y - positions.x) * order < width:
		var center := (positions.x + positions.y) * 0.5
		return Vector2(center - order * width * 0.5, center + order * width * 0.5)
	return positions
