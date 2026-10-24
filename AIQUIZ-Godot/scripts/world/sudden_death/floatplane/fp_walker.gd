extends RefCounted

## 水上機の場面の人の歩き・走り（c130_float.md 第10章）。StagingPuppet 1 人を、道すじに沿って動かす。
##   ・走り出しは加速し（最初の数歩は短く、体を前へ倒す）、止まる所へは減速して止まる（止まる前は体を起こす）
##   ・速さに合わせて、立つ → 歩く（SD_Ramp_Walk）→ 走る（SD_Ramp_Run_Up / Run_Out）を、同じ足の運びの位相でまぜる。
##     位相は進んだ距離から進めるので、足が床をすべらない（1 歩の長さ ＝ そのまぜ方のクリップの 1 周の距離）
##   ・曲がるときは内側へ少し傾け、上り坂では前へ倒す
##   ・その場で向きを変えるときは小さく足踏みする
##   ・plant_feet：歩き以外の動き（座る・立つ）で、両足の真ん中を決めた点に留める（足をすべらせずに腰を動かす）
## 置き方は StagingPuppet.stand_at（足の裏を床に合わせる）。ground は足もとの (x, z) から床の高さ（ワールド）を返す。

const WALK := DropMotion.RAMP_WALK
const RUN := DropMotion.RAMP_RUN_UP
const SPRINT := DropMotion.RAMP_RUN_OUT
## 歩くクリップの速さと 1 周の距離（drop_moves.json）
const WALK_SPEED := 1.3601
const WALK_STRIDE := 1.209
## 立つ ↔ 歩くをまぜる速さ
const IDLE_BLEND := 0.75

var puppet: StagingPuppet = null
var feet := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var accel := 0.0
var phase := 0.0
var run_clip := RUN
var v_max := 5.0
## 加速・減速（m/秒²）。走り出しは強く、終わりはなめらか。
var a_up := 5.0
var a_down := 4.2
var stop_at_end := true
var ground: Callable = Callable()
var idle_clip := "Idle_Loop"
var idle_slot := AnimationRig.SLOT_UAL
var idle_rate := 1.0
## 前への傾き（rad。加速・坂）と、曲がるときの傾き
var lean := 0.0
var bank := 0.0
var extra_lean := 0.0
## 体の向きを道すじへ寄せる速さ（1/秒）
var turn_rate := 9.0
## 動く床の上を歩くとき：feet・道すじ・yaw・ground はこの枠のローカル（機体の床）。毎フレーム呼ぶ側が合わせる。
var space := Transform3D.IDENTITY

var _path: Array[Vector3] = []
var _seg := 0
var _time := 0.0
var _last_yaw := 0.0
var _run_speed := 5.8982
var _run_stride := 5.5049
var _turn_steps := 0.0


func _init(p_puppet: StagingPuppet) -> void:
	puppet = p_puppet


## 道すじを決めて歩き・走り始める（今の速さは保つ）。
func set_path(points: Array, max_speed: float, clip := RUN, stop := true) -> void:
	_path.clear()
	for p: Variant in points:
		_path.append(p as Vector3)
	_seg = 0
	v_max = max_speed
	stop_at_end = stop
	set_run_clip(clip)


func set_run_clip(clip: String) -> void:
	run_clip = clip
	var info := DropMotion.clip_info(clip)
	_run_speed = maxf(float(info.get("speed", 5.9)), 2.0)
	_run_stride = _run_speed * maxf(float(info.get("length", 0.93)), 0.2)


## 道すじの残りの距離（水平）。
func remaining() -> float:
	var d := 0.0
	var at := feet
	for i in range(_seg, _path.size()):
		var p := _path[i]
		d += Vector2(p.x - at.x, p.z - at.z).length()
		at = p
	return d


func arrived() -> bool:
	return _seg >= _path.size() and speed < 0.05


## 道すじの終わりを越えた（止まらずに走り抜けるとき）。
func passed_end() -> bool:
	return _seg >= _path.size()


## 1 フレーム進める。着いて止まったら true。
func step(delta: float) -> bool:
	_time += delta
	var left := remaining()
	# 最後の数 cm：止まりきる前に着いたことにする（なめらかに止まる速さはもう 0 に近い）
	if stop_at_end and _seg < _path.size() and left < 0.06 and speed < 0.6:
		var last := _path[_path.size() - 1]
		feet = Vector3(last.x, feet.y, last.z)
		_seg = _path.size()
		left = 0.0
	var target := v_max
	if stop_at_end:
		# 止まる所までに a_down でなめらかに止まれる速さ（最後の 3 cm は止まる）
		target = minf(target, sqrt(2.0 * a_down * maxf(left - 0.03, 0.0)))
	if _seg >= _path.size():
		target = 0.0
	# 加速度そのものもなめらかに変える（急に蹴り出さない）
	var want := clampf((target - speed) / maxf(delta, 0.001), -a_down * 1.25, a_up)
	accel = move_toward(accel, want, 40.0 * delta)
	speed = clampf(speed + accel * delta, 0.0, maxf(v_max, 0.0))
	if speed <= 0.0 and accel < 0.0:
		accel = 0.0
	# 道すじに沿って進む
	var travel := speed * delta
	var heading := Vector3.ZERO
	while _seg < _path.size() and travel > 0.0:
		var p := _path[_seg]
		var flat := Vector3(p.x - feet.x, 0.0, p.z - feet.z)
		var d := flat.length()
		heading = flat
		if d <= travel:
			feet = Vector3(p.x, feet.y, p.z)
			travel -= d
			_seg += 1
		else:
			feet += flat / maxf(d, 0.0001) * travel
			travel = 0.0
	if heading == Vector3.ZERO and _seg < _path.size():
		var p2 := _path[_seg]
		heading = Vector3(p2.x - feet.x, 0.0, p2.z - feet.z)
	if heading.length() > 0.02 and speed > 0.05:
		yaw = lerp_angle(yaw, atan2(heading.x, heading.z), 1.0 - exp(-turn_rate * delta))
	_advance_gait(delta, speed)
	_pose_and_place(delta)
	return _seg >= _path.size() and speed <= 0.02


## その場で向きを変える（小さく足踏み）。向き終わったら true。
func turn_to(target_yaw: float, delta: float, rate := 3.2) -> bool:
	_time += delta
	var diff := wrapf(target_yaw - yaw, -PI, PI)
	var stepv := clampf(diff, -rate * delta, rate * delta)
	yaw += stepv
	speed = move_toward(speed, 0.0, a_down * delta)
	accel = 0.0
	# 回る速さに合わせて足踏み（1 歩で約 35°）
	_turn_steps = absf(stepv) / maxf(delta, 0.001)
	_advance_gait(delta, maxf(speed, _turn_steps * 0.35))
	_pose_and_place(delta)
	return absf(diff) < 0.03


## 止まって立つ（idle_clip）。
func stand(delta: float) -> void:
	_time += delta
	speed = move_toward(speed, 0.0, a_down * delta)
	accel = 0.0
	_turn_steps = 0.0
	_advance_gait(delta, speed)
	_pose_and_place(delta)


## 足踏みの位相を、進んだ距離から進める。
func _advance_gait(delta: float, v: float) -> void:
	var w := _run_weight(v)
	var stride := lerpf(WALK_STRIDE, _run_stride, w)
	phase = fposmod(phase + delta * v / maxf(stride, 0.1), 1.0)


func _run_weight(v: float) -> float:
	return clampf((v - WALK_SPEED) / maxf(_run_speed - WALK_SPEED, 0.1), 0.0, 1.0)


func _pose_and_place(delta: float) -> void:
	var v := maxf(speed, _turn_steps * 0.35)
	var walk_len := maxf(puppet.clip_length(WALK, AnimationRig.SLOT_DROP), 0.1)
	var run_len := maxf(puppet.clip_length(run_clip, AnimationRig.SLOT_DROP), 0.1)
	var walk_ratio := minf(phase, 0.999)
	var idle_len := maxf(puppet.clip_length(idle_clip, idle_slot), 0.1)
	var idle_ratio := fposmod(_time * idle_rate / idle_len, 1.0)
	if v < IDLE_BLEND:
		var w0 := smoothstep(0.0, IDLE_BLEND, v)
		puppet.pose_blend(idle_clip, idle_ratio, WALK, walk_ratio, w0, idle_slot, AnimationRig.SLOT_DROP)
	else:
		var w := _run_weight(v)
		puppet.pose_blend(WALK, walk_ratio, run_clip, walk_ratio, w, AnimationRig.SLOT_DROP, AnimationRig.SLOT_DROP)
	# 傾き：加速で前へ、減速で後ろへ（走っているときほど大きく）、坂の向きへ。曲がるときは内側へ。
	var run_share := smoothstep(0.5, 4.0, speed)
	var want_lean := clampf(accel * 0.045, -0.16, 0.22) * lerpf(0.4, 1.0, run_share) + extra_lean
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	if ground.is_valid():
		var ahead := float(ground.call(feet + forward * 0.35))
		var behind := float(ground.call(feet - forward * 0.35))
		want_lean += atan((ahead - behind) / 0.7) * 0.5
	lean = lerpf(lean, want_lean, 1.0 - exp(-7.0 * delta))
	var yaw_speed := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	var want_bank := clampf(-yaw_speed * speed * 0.035, -0.2, 0.2)
	bank = lerpf(bank, want_bank, 1.0 - exp(-6.0 * delta))
	var axis := Vector3.UP.cross(forward).normalized()
	var tilt := Basis(axis, lean) * Basis(forward, bank)
	var floor_y := float(ground.call(feet)) if ground.is_valid() else feet.y
	feet.y = floor_y
	if space == Transform3D.IDENTITY:
		puppet.stand_at(feet, yaw, floor_y, tilt)
	else:
		var world := space * feet
		puppet.stand_at(world, yaw, world.y, space.basis.orthonormalized() * tilt)
	puppet.apply_blend(delta)


## 両足の真ん中を point（の x, z）に留める：腰を水平にずらす（pose と stand_at／sit_at のあと、apply_blend の前に呼ぶ）。
static func plant_feet(p: StagingPuppet, point: Vector3, weight := 1.0) -> void:
	var parts := p.parts()
	var pelvis := parts.get("pelvis") as Node3D
	var lf := parts.get("l_foot") as Node3D
	var rf := parts.get("r_foot") as Node3D
	if pelvis == null or lf == null or rf == null:
		return
	var mid := (lf.global_position + rf.global_position) * 0.5
	var shift := Vector3(point.x - mid.x, 0.0, point.z - mid.z) * clampf(weight, 0.0, 1.0)
	pelvis.global_position += shift


## 両足の真ん中（ワールド）。
static func feet_mid(p: StagingPuppet) -> Vector3:
	var parts := p.parts()
	var lf := parts.get("l_foot") as Node3D
	var rf := parts.get("r_foot") as Node3D
	if lf == null or rf == null:
		return p.center()
	return (lf.global_position + rf.global_position) * 0.5
