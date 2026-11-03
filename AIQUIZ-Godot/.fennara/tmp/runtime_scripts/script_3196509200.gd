extends RefCounted

var reached_count: int = 0
var phases: Array[int] = []

func _on_reached(_player_index: int) -> void:
	reached_count += 1

func _on_phase(_player_index: int, phase: int) -> void:
	if phases.is_empty() or phases[-1] != phase:
		phases.append(phase)

func _run_case(shark: Node3D, fps: int) -> Dictionary:
	shark.cancel_attack()
	shark.position = Vector3(20.0, -0.22, -20.0)
	shark.set("_center", shark.position)
	shark.set("_velocity", Vector3.ZERO)
	phases.clear()
	var before_count: int = reached_count
	var started: bool = shark.begin_attack(1, Vector3(20.0, -0.22, 20.0), 4.0, 160.0)
	var dt: float = 1.0 / float(fps)
	var steps: int = 0
	while shark.is_attacking and steps < fps * 5:
		shark.call("_update_attack", dt)
		steps += 1
	return {
		"fps": fps,
		"started": started,
		"steps": steps,
		"elapsed": float(steps) * dt,
		"hits": reached_count - before_count,
		"phases": phases.duplicate(),
	}

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	var shark: Node3D = ctx.get_scene_root() as Node3D
	shark.set_process(false)
	shark.attack_reached.connect(_on_reached)
	shark.attack_phase_changed.connect(_on_phase)
	var results: Array[Dictionary] = []
	for fps: int in [30, 60, 120]:
		results.append(_run_case(shark, fps))
	ctx.log("fps_sync=%s total_hits=%d" % [str(results), reached_count])
