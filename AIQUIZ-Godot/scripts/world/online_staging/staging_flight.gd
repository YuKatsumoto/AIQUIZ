class_name StagingFlight
extends RefCounted

## マッチング演出のヘリの飛び方（仕様書 S3〜S7、9、22）。どれも「ヘリの座標（H）」の中の Transform3D を返す。
## 呼ぶ側は「揺れない枠」F（パッドの上、または流しの高さ）に掛けてワールドへ直す：heli.transform = F * これ。

const T = preload("res://scripts/world/online_staging/online_staging_timeline.gd")


## S3〜S4 の発進（離陸 → 急発進。仕様書 24）：ホバーで止まらず、浮いたらそのまま前へ進みながら上がり、
## DEPART.pre_turn_deg の向き（今は左）へ旋回しはじめる（旋回の向きへ機体を傾ける）。進みながらジェットポッドを広げ、点火で旋回の向きのまま
## 前の上（BOOST.climb_deg）へ accel_seconds で speed m/秒まで加速し、旋回をゆるめながら飛び去る。機首の上げと傾きは暗転まで戻さない。
## t は離陸の始まりからの秒（CLIMB では 離陸の長さ＋CLIMB の時刻）、lift は浮き始める秒、pre は浮いてから点火までの秒。
## 点火までの道すじは DEPART.pre_seconds の長さで決めてあり、pre が違えば（みじかい演出など）同じ道すじを速さを変えて通る。
static func departure(t: float, lift: float, pre: float) -> Transform3D:
	var d: Dictionary = T.DEPART
	if t <= lift:
		return Transform3D.IDENTITY
	var nominal := float(d.pre_seconds)
	var rate := nominal / maxf(pre, 0.001)
	var since := t - lift
	var tau := minf(since, pre) * rate
	var yaw := _pre_yaw(tau)
	var position := _pre_position(tau)
	var k := clampf(tau / nominal, 0.0, 1.0)
	var pitch := deg_to_rad(float(d.pre_pitch_deg)) * smoothstep(0.0, 1.0, k)
	var bank := _bank(_pre_speed(tau) * _pre_turn_rate(tau))
	if since <= pre:
		return _pose(position, yaw, pitch, bank)
	# 点火のあと（実際の秒）：点火の直前の速さ・旋回から続ける
	var b: Dictionary = T.BOOST
	var after := since - pre
	var v0 := _pre_speed(nominal) * rate
	var vy0 := (float(d.climb_mps) + float(d.climb_gain_mps)) * rate
	var w0 := _pre_turn_rate(nominal) * rate
	var decay := float(d.turn_decay_seconds)
	var accel := float(b.accel_seconds)
	var climb := deg_to_rad(float(b.climb_deg))
	var velocity := func(s: float) -> Vector3:
		var speed := _dash_speed(s, v0)
		var w := smoothstep(0.0, accel, s)
		var heading := yaw - w0 * decay * (1.0 - exp(-s / decay))
		var horizontal := speed * lerpf(1.0, cos(climb), w)
		return Vector3(-sin(heading), 0.0, -cos(heading)) * horizontal + Vector3.UP * lerpf(vy0, speed * sin(climb), w)
	# 加速の終わり（速さの折れ目）で分けて積む
	position += _simpson(velocity, 0.0, minf(after, accel), 24)
	if after > accel:
		position += _simpson(velocity, accel, after, 24)
	var dash_yaw := yaw - w0 * decay * (1.0 - exp(-after / decay))
	var dash_pitch := lerpf(pitch, deg_to_rad(float(b.pitch_deg)), smoothstep(0.0, float(b.pitch_seconds), after))
	# 傾きは旋回の向きへ max_bank_deg まで深め、機首の上げと同じく暗転まで戻さない
	var dash_bank := lerpf(bank, signf(w0) * deg_to_rad(float(d.max_bank_deg)), smoothstep(0.0, float(d.bank_blend_seconds), after))
	return _pose(position, dash_yaw, dash_pitch, dash_bank)


## 点火までの前への速さ（DEPART.pre_seconds の時間 tau 秒で。止まらずに上がっていき、点火の直前もまだ加速している）。
static func _pre_speed(tau: float) -> float:
	var k := clampf(tau / float(T.DEPART.pre_seconds), 0.0, 1.0)
	return float(T.DEPART.pre_speed) * k * k * (2.0 - k)


## 点火までの向き（右へ旋回すると減る）。
static func _pre_yaw(tau: float) -> float:
	var k := clampf(tau / float(T.DEPART.pre_seconds), 0.0, 1.0)
	return -deg_to_rad(float(T.DEPART.pre_turn_deg)) * k * k * k


## 点火までの旋回の速さ（右へ正、rad/秒）。
static func _pre_turn_rate(tau: float) -> float:
	var nominal := float(T.DEPART.pre_seconds)
	var k := clampf(tau / nominal, 0.0, 1.0)
	return 3.0 * deg_to_rad(float(T.DEPART.pre_turn_deg)) * k * k / nominal


## 点火までの位置：上へは rise_seconds で climb_mps まで速め、旋回しながら climb_gain_mps を足していく（道すじが上へ反る）。前へは向きに沿って積む。
static func _pre_position(tau: float) -> Vector3:
	var d: Dictionary = T.DEPART
	var rise := float(d.rise_seconds)
	var x := clampf(tau / rise, 0.0, 1.0)
	var k := clampf(tau / float(d.pre_seconds), 0.0, 1.0)
	var height := float(d.climb_mps) * (rise * (x * x * x - x * x * x * x * 0.5) + maxf(tau - rise, 0.0))
	height += float(d.climb_gain_mps) * float(d.pre_seconds) * k * k * k / 3.0
	var ground := _simpson(func(s: float) -> Vector3:
		var heading := _pre_yaw(s)
		return Vector3(-sin(heading), 0.0, -cos(heading)) * _pre_speed(s), 0.0, tau, 24)
	return ground + Vector3.UP * height


## 点火のあとの速さ：点火の直前の速さ v0 から accel_seconds で一様に speed まで。
static func _dash_speed(s: float, v0: float) -> float:
	var b: Dictionary = T.BOOST
	return lerpf(v0, float(b.speed), clampf(s / float(b.accel_seconds), 0.0, 1.0))


## 旋回の傾き（右の翼を下げると正）：横の加速度（速さ × 旋回の速さ）から。max_bank_deg で止める。
static func _bank(lateral_accel: float) -> float:
	var d: Dictionary = T.DEPART
	var max_bank := deg_to_rad(float(d.max_bank_deg))
	return clampf(atan(lateral_accel / 9.8) * float(d.bank_gain), -max_bank, max_bank)


static func _pose(position: Vector3, yaw: float, pitch: float, bank: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, bank), position)


## シンプソンの公式で f（Vector3 を返す）を a〜b で積む（n は偶数）。
static func _simpson(f: Callable, a: float, b: float, n: int) -> Vector3:
	if b <= a:
		return Vector3.ZERO
	var h := (b - a) / float(n)
	var sum: Vector3 = f.call(a) + f.call(b)
	for i in range(1, n):
		sum += (f.call(a + h * float(i)) as Vector3) * (4.0 if i % 2 == 1 else 2.0)
	return sum * h / 3.0


## 溜め（0〜1）：charge_start〜charge_end で一様に上がる。
static func boost_charge(u: float) -> float:
	var b: Dictionary = T.BOOST
	return clampf((u - float(b.charge_start)) / maxf(float(b.charge_end) - float(b.charge_start), 0.001), 0.0, 1.0)


## 点火する進み。
static func boost_ignite_u() -> float:
	return float(T.BOOST.charge_end)


## 溜めの震え（H の中の位置のずれ）：t は秒、charge は溜め（0〜1）。点火の前だけ。
static func boost_shudder(t: float, charge: float) -> Vector3:
	var b: Dictionary = T.BOOST
	var phase := t * float(b.shudder_rate)
	return Vector3(sin(phase), sin(phase * 1.31) * 0.7, cos(phase * 0.93) * 0.4) * float(b.shudder_m) * charge


## S5〜S7 の揺れ（time は秒。phase で 2 機をずらす）：横揺れ・縦揺れ・上下・向き。
static func cruise_sway(time: float, phase: float = 0.0) -> Transform3D:
	var c: Dictionary = T.CRUISE
	var t := time + phase
	var roll := deg_to_rad(float(c.roll_deg)) * sin(TAU * t / float(c.roll_period))
	var pitch := deg_to_rad(float(c.pitch_deg) + float(c.pitch_amp_deg) * sin(TAU * t / float(c.pitch_period) + 0.6))
	var bob := float(c.bob_m) * sin(TAU * t / float(c.bob_period) + 1.3)
	var yaw := deg_to_rad(float(c.yaw_deg)) * sin(TAU * t / float(c.yaw_period) + 2.1)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll)
	return Transform3D(basis, Vector3(0.0, bob, 0.0))


## S6 合流：相手のヘリ（自分のヘリの H）。u は JOIN の進み、seconds は JOIN の長さ。
## JOIN.arrive までに 3 次の減速で道すじを通る。向きは「流れ（検索中の速さ）を足した本当の進む向き」、
## 傾きは横の加速度、機首は前後の加速度から決める（曲がる側へ傾き、減速で機首を上げる）。
static func join(u: float, seconds: float) -> Transform3D:
	var j: Dictionary = T.JOIN
	var arrive := float(j.arrive)
	var h := 0.01
	var p0 := join_position(u - h, arrive)
	var p1 := join_position(u, arrive)
	var p2 := join_position(u + h, arrive)
	var dt := h * maxf(seconds, 0.001)
	var velocity := (p2 - p0) / (2.0 * dt)
	var accel := (p2 - 2.0 * p1 + p0) / (dt * dt)
	var world := velocity + Vector3(0.0, 0.0, -float(T.CRUISE.speed))
	var yaw := atan2(-world.x, -world.z)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var max_bank := deg_to_rad(float(j.max_bank_deg))
	var max_pitch := deg_to_rad(float(j.max_pitch_deg))
	var bank := clampf(deg_to_rad(float(j.bank_per_mps2)) * accel.dot(right), -max_bank, max_bank)
	var pitch := clampf(-deg_to_rad(float(j.pitch_per_mps2)) * accel.dot(forward), -max_pitch, max_pitch) + deg_to_rad(float(T.CRUISE.pitch_deg))
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, bank), p1)


## 合流の道すじの上の位置（u は JOIN の進み。arrive で着いて止まる）。
static func join_position(u: float, arrive: float) -> Vector3:
	var k := clampf(u / maxf(arrive, 0.001), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	return OnlineHeliportStage.catmull(T.JOIN_PATH, e)


## 探し直し：相手のヘリが並走の位置から、うしろ左の上へ離れていく（u は 0〜1、2 次の加速）。
static func leave(u: float) -> Transform3D:
	var e := clampf(u, 0.0, 1.0)
	var points: Array = [T.JOIN_PATH[T.JOIN_PATH.size() - 1], Vector3(-16.0, 3.0, 8.0), Vector3(-28.0, 12.0, 30.0), Vector3(-44.0, 22.0, 60.0)]
	var p := OnlineHeliportStage.catmull(points, e * e)
	var roll := deg_to_rad(28.0) * smoothstep(0.0, 0.6, e)
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)) * Basis(Vector3.FORWARD, roll), p)


## 5 次のなめらかな加減速（始まりと終わりで速さも加速度も 0）。
static func smootherstep(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
