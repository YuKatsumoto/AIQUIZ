extends Node
## メニュー背景ランナーの歩様に使うクリップを、実際に表示する箱の人形へ当てて測る：
## 接地している足が後ろへ流れる速さ（＝そのクリップの自然な移動速度）と、左足が着く位相。
## MenuRunnerGait の定数がこの実測から ±10% 以内かを確かめる（クリップを差し替えたら測り直す）。
## 速さは「接地区間に足首が後ろへ流れた距離 ÷ その時間」（区間の平均）。
const Gait = preload("res://scripts/ui/menu_preview/menu_runner_gait.gd")
const SAMPLES := 240
var failures: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var pc := Node3D.new()
	pc.set_script(load("res://scripts/world/player_controller.gd"))
	add_child(pc)
	for i in 600:
		await get_tree().process_frame
		var rig: AnimationRig = pc.get("_p1_rig")
		if rig != null and rig.is_rigged and rig.aps.size() > AnimationRig.SLOT_UAL and rig.aps[AnimationRig.SLOT_UAL] != null:
			break
	var puppet := StagingPuppet.new(pc as PlayerController, 1)
	if not puppet.is_ready() or puppet.rig() == null:
		failures.append("rig not ready")
		finish()
		return
	for entry: Dictionary in Gait.LOCOMOTION_CLIPS:
		var clip := Gait.clip_name(puppet.rig(), entry)
		var measured := _measure(puppet, clip, int(entry.slot))
		measured["expected_speed"] = entry.speed
		measured["expected_contact"] = entry.contact
		report[String(entry.key)] = measured
		if bool(entry.measured):
			var speed := float(measured.get("stance_speed", 0.0))
			if absf(speed - float(entry.speed)) > float(entry.speed) * 0.1:
				failures.append("%s speed %.2f vs %.2f" % [entry.key, speed, entry.speed])
			var contact_error := absf(wrapf(float(measured.get("contact", 0.0)) - float(entry.contact), -0.5, 0.5))
			if contact_error > 0.06:
				failures.append("%s contact %.3f vs %.3f" % [entry.key, measured.get("contact", 0.0), entry.contact])
	finish()


## 足の位置（pelvis から見た箱の人形の足）を 1 周ぶん取り、接地中（いちばん低い所から 3 cm 以内）の水平の速さの中央値を出す
func _measure(puppet: StagingPuppet, clip: String, slot: int) -> Dictionary:
	var length := puppet.clip_length(clip, slot)
	if length <= 0.0:
		return {"clip": clip, "missing": true}
	var parts := puppet.parts()
	var pelvis := parts.get("pelvis") as Node3D
	# 足首とつま先のうち低いほう（つま先で走るクリップは踵が早く浮くため）
	var feet := {"l": [parts.get("l_ankle"), parts.get("l_toe")], "r": [parts.get("r_ankle"), parts.get("r_toe")]}
	var track := {"l": [], "r": []}
	var track_toe := {"l": [], "r": []}
	for i in SAMPLES:
		var ratio := float(i) / SAMPLES
		puppet.pose(clip, ratio, slot)
		var to_local := pelvis.global_transform.affine_inverse()
		for side: String in feet:
			(track[side] as Array).append(to_local * (feet[side][0] as Node3D).global_position)
			(track_toe[side] as Array).append(to_local * (feet[side][1] as Node3D).global_position)
	var toe_speeds: Array[float] = []
	for side: String in track_toe:
		var points: Array = track_toe[side]
		var min_y := INF
		for p: Vector3 in points:
			min_y = minf(min_y, p.y)
		for i in SAMPLES:
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % SAMPLES]
			if a.y < min_y + 0.02 and b.y < min_y + 0.02:
				toe_speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / (length / SAMPLES))
	toe_speeds.sort()
	var speeds: Array[float] = []
	var contact := -1.0
	for side: String in track:
		var points: Array = track[side]
		var min_y := INF
		for p: Vector3 in points:
			min_y = minf(min_y, p.y)
		var dt := length / SAMPLES
		for i in SAMPLES:
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % SAMPLES]
			var down := a.y < min_y + 0.03 and b.y < min_y + 0.03
			if down:
				speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / dt)
			if side == "l" and contact < 0.0:
				var prev: Vector3 = points[(i - 1 + SAMPLES) % SAMPLES]
				if a.y < min_y + 0.03 and prev.y >= min_y + 0.03:
					contact = float(i) / SAMPLES
	speeds.sort()
	var median := speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
	# 別の測り方：左足が接地しているあいだに後ろへ流れた距離 ÷ 接地の時間（中央値の確かめ）
	var left: Array = track["l"]
	var left_min := INF
	for p: Vector3 in left:
		left_min = minf(left_min, p.y)
	var sweep_start := -1
	var sweep := 0.0
	var stance_time := 0.0
	for k in SAMPLES * 2:
		var i := k % SAMPLES
		var p: Vector3 = left[i]
		var down := p.y < left_min + 0.03
		if down and sweep_start < 0 and k > 0 and (left[(i - 1 + SAMPLES) % SAMPLES] as Vector3).y >= left_min + 0.03:
			sweep_start = i
		elif sweep_start >= 0 and not down:
			var a: Vector3 = left[sweep_start]
			var b: Vector3 = left[(i - 1 + SAMPLES) % SAMPLES]
			sweep = Vector2(b.x - a.x, b.z - a.z).length()
			stance_time = float((i - 1 - sweep_start + SAMPLES) % SAMPLES) / SAMPLES * length
			break
	# 足首がいちばん低い所から 5 cm 以内を接地とみなし、続けて接地している区間の「後ろへ流れた距離 ÷ 時間」を両足で平均する。
	# このクリップの足は接地中に一様には流れない（着いた直後は体の下に残り、あとで蹴り出す）ので、区間の平均で見る
	var stance_speeds: Array[float] = []
	for side: String in track:
		var points: Array = track[side]
		var lo := INF
		var hi := -INF
		for p: Vector3 in points:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var limit := lo + 0.05
		var begin := -1
		for k in SAMPLES * 2:
			var i := k % SAMPLES
			var down := (points[i] as Vector3).y < limit
			var was_down := (points[(i - 1 + SAMPLES) % SAMPLES] as Vector3).y < limit
			if down and not was_down:
				begin = k
			elif not down and was_down and begin >= 0:
				var a: Vector3 = points[begin % SAMPLES]
				var b: Vector3 = points[(k - 1) % SAMPLES]
				var span := float(k - 1 - begin) / SAMPLES * length
				if span > 0.0:
					stance_speeds.append(absf(b.z - a.z) / span)
				break
	var stance_speed := 0.0
	for s: float in stance_speeds:
		stance_speed += s / stance_speeds.size()
	var leg := (parts.get("l_hip") as Node3D).global_position.distance_to((parts.get("l_ankle") as Node3D).global_position)
	return {
		"clip": clip, "length": snappedf(length, 0.001), "speed": snappedf(median, 0.01),
		"toe_speed": snappedf(toe_speeds[toe_speeds.size() / 2] if not toe_speeds.is_empty() else 0.0, 0.01), "toe_samples": toe_speeds.size(),
		"stance_speed": snappedf(stance_speed, 0.01),
		"sweep_speed": snappedf(sweep / maxf(stance_time, 0.001), 0.01), "sweep": snappedf(sweep, 0.01),
		"contact": snappedf(maxf(contact, 0.0), 0.001), "stance_samples": speeds.size(), "leg": snappedf(leg, 0.01),
	}


func finish() -> void:
	var result := {"passed": failures.is_empty(), "failures": failures, "report": report}
	print("MENU_RUNNER_CLIPS ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
