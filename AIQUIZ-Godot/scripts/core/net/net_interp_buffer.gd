class_name NetInterpBuffer
extends RefCounted

## Snapshot interpolation for avatars this machine does not control.
## Samples are stamped with local receive time; rendering reads them a fixed
## delay in the past so there is (almost) always a pair to blend between.

const DEFAULT_DELAY := 0.1
const MAX_SAMPLES := 32
## Beyond the newest sample, extrapolate at most this long before holding.
const MAX_EXTRAPOLATION := 0.1

var delay := DEFAULT_DELAY
var _samples: Array[Dictionary] = []  # {t, x, y, lz}


func clear() -> void:
	_samples.clear()


func is_empty() -> bool:
	return _samples.is_empty()


func push(now: float, x: float, y: float, lz: float) -> void:
	if not _samples.is_empty() and now <= float(_samples[-1].t):
		now = float(_samples[-1].t) + 0.0001
	_samples.append({"t": now, "x": x, "y": y, "lz": lz})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


## Returns Vector3(x, y, lz) at `now - delay`.
func sample(now: float) -> Vector3:
	if _samples.is_empty():
		return Vector3.ZERO
	var target := now - delay
	if target <= float(_samples[0].t):
		return _vec(_samples[0])
	for i in range(_samples.size() - 1):
		var a := _samples[i]
		var b := _samples[i + 1]
		if target <= float(b.t):
			var span := float(b.t) - float(a.t)
			var w := 0.0 if span <= 0.0 else (target - float(a.t)) / span
			return _vec(a).lerp(_vec(b), w)
	var last := _samples[-1]
	if _samples.size() >= 2:
		var prev := _samples[-2]
		var span := float(last.t) - float(prev.t)
		var ahead := minf(target - float(last.t), MAX_EXTRAPOLATION)
		if span > 0.0 and ahead > 0.0:
			return _vec(last) + (_vec(last) - _vec(prev)) * (ahead / span)
	return _vec(last)


func _vec(s: Dictionary) -> Vector3:
	return Vector3(float(s.x), float(s.y), float(s.lz))
