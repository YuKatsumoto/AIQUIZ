extends SceneTree

## The crown is retired: the hat pickers never land on it, in either direction, and
## every other hat is still reachable. Run: Godot --headless --path . --script tests/hat_retired_unit.gd

func _init() -> void:
	var failures: Array[String] = []
	var seen := {}
	var id := HatData.HAT_NONE
	for _step in range(HatData.HAT_COUNT * 2):
		id = HatData.step_hat(id, 1)
		seen[id] = true
		if id == HatData.HAT_CROWN:
			failures.append("right step landed on the crown")
	for hat in range(HatData.HAT_COUNT):
		if hat != HatData.HAT_CROWN and not seen.has(hat):
			failures.append("hat %d is unreachable going right" % hat)
	id = HatData.HAT_NONE
	for _step in range(HatData.HAT_COUNT * 2):
		id = HatData.step_hat(id, -1)
		if id == HatData.HAT_CROWN:
			failures.append("left step landed on the crown")
	if HatData.step_hat(HatData.HAT_TOP_HAT, 1) != HatData.HAT_CAP:
		failures.append("right of the top hat should skip the crown to the cap")
	if HatData.step_hat(HatData.HAT_CAP, -1) != HatData.HAT_TOP_HAT:
		failures.append("left of the cap should skip the crown to the top hat")
	if HatData.is_selectable(HatData.HAT_CROWN) or not HatData.is_selectable(HatData.HAT_CAP) or HatData.is_selectable(99):
		failures.append("is_selectable")
	print("HAT_RETIRED_UNIT ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
