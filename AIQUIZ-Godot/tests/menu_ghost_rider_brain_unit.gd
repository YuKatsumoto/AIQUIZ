extends Node
## メニュー背景のゴーストライダーの「手」（MenuGhostRiderBrain）の単体テスト。
## コントローラーの照準と溜めを小さな模型で再現し、必ず撃つ・狙いが合う・作戦の割合・フレームレートによらないことを確かめる。
const Brain = preload("res://scripts/ui/menu_preview/menu_ghost_rider_brain.gd")
const AIMING := GhostSharkRideController.Phase.AIMING
const WINDUP := GhostSharkRideController.Phase.WINDUP
var failures: Array[String] = []
var checks := 0
var report := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _ready() -> void:
	for fps: int in [30, 60, 144]:
		_fire_cases(fps)
	_plan_mix()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}
	print("MENU_GHOST_BRAIN ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


## 模型：照準は軸 × AIM_SPEED で動き（本編と同じ制限）、押している間の溜めは 0.5 秒で一周、離した瞬間の溜めで突進する。
func _simulate(brain, fps: int, survivor: Vector3, survivor_velocity: Vector2) -> Dictionary:
	var dt := 1.0 / fps
	var origin := Vector3(survivor.x, 0.85, survivor.z)
	var offset := Vector2.ZERO
	var charge := 0.0
	var down := false
	var t := 0.0
	var phase := AIMING
	var errors: Array[float] = []
	while t < 8.0:
		var aim := Vector3(origin.x + offset.x, origin.y, origin.z + offset.y)
		var cmd: Dictionary = brain.update(dt, phase, aim, survivor, survivor_velocity, charge)
		if phase != AIMING:
			check(not bool(cmd.fire), "never fires outside aiming")
			break
		var axis: Vector2 = cmd.axis
		offset.x = clampf(offset.x + axis.x * GhostSharkRideController.AIM_SPEED * dt, -8.0, 8.0)
		offset.y = clampf(offset.y + axis.y * GhostSharkRideController.AIM_SPEED * dt, -8.0, 12.0)
		var fire: bool = cmd.fire
		if fire and not down:
			charge = 0.0
		if fire:
			charge = fposmod(charge + dt / GhostSharkRideController.CHARGE_BUILD_SECONDS, 1.0)
		elif down:
			# 離した：この溜めで突進
			var hit_point := Vector2(origin.x + offset.x, origin.z + offset.y)
			return {"time": t, "power": maxf(GhostSharkRideController.QUICK_CHARGE_FLOOR, charge), "error": hit_point.distance_to(Vector2(survivor.x, survivor.z)), "plan": brain.plan}
		down = fire
		survivor.x += survivor_velocity.x * dt
		survivor.z += survivor_velocity.y * dt
		origin.z = survivor.z
		t += dt
	return {"time": INF, "power": 0.0, "error": INF, "plan": brain.plan}


func _fire_cases(fps: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + fps
	var brain = Brain.new(rng)
	brain.whiff_chance = 0.0
	var worst_time := 0.0
	var close := 0
	for trial in 200:
		brain.reset()
		var survivor := Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.0, 3.0))
		var result := _simulate(brain, fps, survivor, Vector2.ZERO)
		worst_time = maxf(worst_time, float(result.time))
		if float(result.error) < 1.45:
			close += 1
		if int(result.plan) == Brain.Plan.PERFECT:
			check(float(result.power) >= GhostSharkRideController.PERFECT_CHARGE_MIN - 0.001 and float(result.power) <= GhostSharkRideController.PERFECT_CHARGE_MAX + 0.034, "perfect plan lands near the band at %d fps (%.3f)" % [fps, float(result.power)])
		# 撃ったあとは突進が終わるまで撃たない
		var after: Dictionary = brain.update(1.0 / fps, WINDUP, Vector3.ZERO, survivor, Vector2.ZERO, 0.0)
		check(not bool(after.fire), "no fire during windup")
	report["worst_fire_time_%d" % fps] = worst_time
	report["close_share_%d" % fps] = close / 200.0
	check(worst_time <= Brain.FORCE_FIRE_AFTER + 0.6, "always commits at %d fps" % fps)
	check(close >= 150, "aim settles near the survivor at %d fps (%d/200)" % [fps, close])


func _plan_mix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var brain = Brain.new(rng)
	var counts := [0, 0, 0]
	for i in 3000:
		brain.reset()
		brain.update(1.0 / 60.0, AIMING, Vector3.ZERO, Vector3.ZERO, Vector2.ZERO, 0.0)
		counts[brain.plan] += 1
	report["plan_mix"] = counts
	check(absf(counts[0] / 3000.0 - Brain.PLAN_PERFECT_SHARE) < 0.05, "perfect share")
	check(absf(counts[1] / 3000.0 - Brain.PLAN_WEAK_SHARE) < 0.05, "weak share")
