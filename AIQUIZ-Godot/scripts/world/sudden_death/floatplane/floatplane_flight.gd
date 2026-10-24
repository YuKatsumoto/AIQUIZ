class_name FloatplaneFlight
extends RefCounted

## サドンデスの水上機の動き（docs/sudden_death_v2/c130_float.md 第9章）。場面の頭で 1/120 秒ごとの位置・向き・水への沈みを
## 前もって積んでおき、毎フレーム sample(t) で読む（フレームの長さで動きが変わらない）。
##   landing  進入：決まった角度でまっすぐ下りてきて、機首を起こし（フレア）、浮き舟の段から着水する。逆推力と水の抵抗で減速する。
##   dock     後ろ向きに寄せる：逆推力で下がり、なめらかに止まる。止まったあとはその場で波に揺れる。
##   taxi     止まった所から前へ動き出す（水の上で機首が少し上がる）。
##   takeoff  離水：段に乗って滑走しながら加速し、機首を起こして浮き、上昇する。
## 姿勢は動きから決める：空では 機首の角度 ＝ 道すじの角度 ＋ 迎え角（速さの 2 乗に反比例し、荷重倍数に比例）、傾きは横の加速度から。
## 水の上では、速さで決まる「水の上の姿勢（トリム）」と「沈み」へ、ばねのように寄っていく（着水の瞬間は機首が下がって小さく揺れる）。
##
## 枠（frame）：原点＝道すじの基準の海面の点、−Z が進む向き（機首と同じ）、+X が右、+Y が上。
## s は −Z へ進んだ距離、lat は +X への横のずれ、y は機体の原点（喫水線 × 主翼の翼弦の中央）の海面からの高さ。
## 水の上では、浮き舟の段の底（ローカル (0, −0.65, 2.1)）が海面から d だけ沈むように y を決める（止まっていれば d ＝ 喫水 0.65、y ＝ 0）。

const DT := 1.0 / 120.0
const G := 9.8
## 浮き舟の段の底（機体のローカル）。
const STEP_Y := -0.65
const STEP_Z := 2.1
const DRAFT := 0.65

## 水の上の姿勢（km/h ではなく m/秒 → 度）と、段の沈み（m/秒 → m）。着水のあとの減速（land）と離水の加速（takeoff）で違う。
const TRIM_LAND := [[0.0, 0.3], [4.0, 0.6], [8.0, 3.2], [13.0, 6.2], [18.0, 5.4], [24.0, 4.8], [45.0, 4.8]]
const TRIM_TAKEOFF := [[0.0, 0.4], [3.0, 2.0], [7.0, 7.4], [10.0, 8.8], [13.0, 6.6], [17.0, 4.6], [45.0, 4.4]]
const SINK := [[0.0, 0.65], [5.0, 0.72], [9.0, 0.62], [13.0, 0.42], [17.0, 0.28], [24.0, 0.18], [32.0, 0.10], [40.0, 0.04]]

var frame := Transform3D.IDENTITY
## この道すじの始まり（場面の時計の秒）。
var t0 := 0.0
## 着水・浮いた・止まった時刻（場面の時計の秒。ないときは INF）。
var touchdown_at := INF
var liftoff_at := INF
var stop_at := INF
## 着水した瞬間の沈む速さ（m/秒）。しぶきの強さに使う。
var touchdown_sink := 0.0

var _s := PackedFloat32Array()
var _lat := PackedFloat32Array()
var _y := PackedFloat32Array()
var _pitch := PackedFloat32Array()
var _roll := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _v := PackedFloat32Array()
var _a := PackedFloat32Array()
var _d := PackedFloat32Array()
var _phases := PackedFloat32Array()


func length() -> float:
	return float(maxi(_s.size() - 1, 0)) * DT


func end_time() -> float:
	return t0 + length()


# ================================================================== 読む

## t（場面の時計）の機体。bob は止まっているときの波の揺れの大きさ（スロープを床や浮き輪に載せている間は小さく）。
## 返り値：xf（ワールド）・v（進む向きの速さ、後ろ向きは負）・a・d（段の沈み、空中は負＝水面からの高さ）・wet・s・lat。
func sample(t: float, bob := 1.0) -> Dictionary:
	var n := _s.size()
	if n == 0:
		return {"xf": frame, "v": 0.0, "a": 0.0, "d": DRAFT, "wet": true, "s": 0.0, "lat": 0.0}
	var u := clampf((t - t0) / DT, 0.0, float(n - 1))
	var i := mini(int(u), n - 2) if n > 1 else 0
	var f := u - float(i) if n > 1 else 0.0
	var j := mini(i + 1, n - 1)
	var s := lerpf(_s[i], _s[j], f)
	var lat := lerpf(_lat[i], _lat[j], f)
	var y := lerpf(_y[i], _y[j], f)
	var pitch := lerpf(_pitch[i], _pitch[j], f)
	var roll := lerpf(_roll[i], _roll[j], f)
	var yaw := lerpf(_yaw[i], _yaw[j], f)
	var v := lerpf(_v[i], _v[j], f)
	var a := lerpf(_a[i], _a[j], f)
	var d := lerpf(_d[i], _d[j], f)
	# 波：止まっている・遅いときはゆっくり大きく、段に乗って速いときは細かく速く。水から離れると消える。
	var on_water := clampf(1.0 + d / 0.8, 0.0, 1.0)
	var slow := (1.0 - smoothstep(3.0, 14.0, absf(v))) * bob
	var fast := smoothstep(6.0, 22.0, absf(v))
	var heave := (0.055 * sin(TAU * t / 3.7 + 0.4) + 0.03 * sin(TAU * t / 5.3 + 2.2)) * slow
	heave += (0.02 * sin(TAU * t * 2.1 + 1.0) + 0.012 * sin(TAU * t * 3.3)) * fast
	var wave_pitch := deg_to_rad(0.45) * sin(TAU * t / 4.4 + 1.1) * slow
	wave_pitch += deg_to_rad(0.3) * (0.6 * sin(TAU * t * 1.7 + 0.3) + 0.4 * sin(TAU * t * 2.9 + 2.0)) * fast
	var wave_roll := deg_to_rad(0.6) * sin(TAU * t / 5.9 + 0.7) * slow
	wave_roll += deg_to_rad(0.3) * sin(TAU * t * 1.3 + 0.9) * fast
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch + wave_pitch * on_water) * Basis(Vector3.FORWARD, roll + wave_roll * on_water)
	var local := Transform3D(basis, Vector3(lat, y + heave * on_water, -s))
	return {"xf": frame * local, "v": v, "a": a, "d": d, "wet": d > -0.02, "s": s, "lat": lat, "pitch": pitch}


## t の原点の位置（ワールド。波の揺れなし）。カメラが少し先を読むのに使う。
func position_at(t: float) -> Vector3:
	var n := _s.size()
	if n == 0:
		return frame.origin
	var u := clampf((t - t0) / DT, 0.0, float(n - 1))
	var i := mini(int(u), maxi(n - 2, 0))
	var j := mini(i + 1, n - 1)
	var f := u - float(i)
	return frame * Vector3(lerpf(_lat[i], _lat[j], f), lerpf(_y[i], _y[j], f), -lerpf(_s[i], _s[j], f))


## s が value をまたぐ最初の時刻（場面の時計）。またがなければ INF。
func time_at_s(value: float) -> float:
	if _s.is_empty():
		return INF
	var side := signf(_s[0] - value)
	for i in range(1, _s.size()):
		if signf(_s[i] - value) != side:
			return t0 + float(i) * DT
	return INF


## 最後の姿勢（次の道すじへ引き継ぐ）：s・v・pitch・d とその速さ。
func last_state() -> Dictionary:
	var n := _s.size()
	if n < 2:
		return {}
	return {"s": _s[n - 1], "v": _v[n - 1], "pitch": _pitch[n - 1], "pitch_rate": (_pitch[n - 1] - _pitch[n - 2]) / DT,
		"d": _d[n - 1], "d_rate": (_d[n - 1] - _d[n - 2]) / DT, "roll": _roll[n - 1], "yaw": _yaw[n - 1], "lat": _lat[n - 1]}


# ================================================================== 進入から着水・減速（landing）

## spec：
##   start_s・duration（積む長さ）
##   anchor_s・anchor_h（進入の直線が通る点）・glide_deg（下りる角度）・flare_s（起こし始める s）・touch_deg（着く瞬間の道すじの角度）
##   v_app（進入の速さ）・v_td（着く速さ）
##   turn_deg（進入の最後の向きの直し。正で右から寄せる）・turn_from・turn_to（直す s の範囲）
##   alpha_deg（v_app・1G の迎え角）
##   turb（空の揺れの大きさ 0〜1）
static func landing(frame_xf: Transform3D, start_time: float, spec: Dictionary) -> FloatplaneFlight:
	var f := FloatplaneFlight.new()
	f.frame = frame_xf
	f.t0 = start_time
	var start_s := float(spec.get("start_s", -60.0))
	var duration := float(spec.get("duration", 6.0))
	var glide := deg_to_rad(float(spec.get("glide_deg", 12.0)))
	var touch := deg_to_rad(float(spec.get("touch_deg", 2.5)))
	var anchor_s := float(spec.get("anchor_s", 0.0))
	var anchor_h := float(spec.get("anchor_h", 10.0))
	var flare_s := float(spec.get("flare_s", 0.0))
	var v_app := float(spec.get("v_app", 38.0))
	var v_td := float(spec.get("v_td", 34.0))
	var alpha_ref := deg_to_rad(float(spec.get("alpha_deg", 6.5)))
	var turb := float(spec.get("turb", 1.0))
	# 縦の道すじ：直線 → フレア（道すじの角度を 5 次でなめらかに起こす）。着く高さに届く長さを二分法で決める。
	var touch_h := 0.9
	var ds := 0.1
	var profile := _glide_profile(start_s, anchor_s, anchor_h, glide, flare_s, touch, touch_h, ds)
	var heights: PackedFloat32Array = profile.h
	var angles: PackedFloat32Array = profile.g
	var td_s := float(profile.td_s)
	var slow_from := float(spec.get("slow_from", flare_s - 30.0))
	# 横：最後の向きの直し（turn_deg の向きのずれを turn_from〜turn_to で 0 へ）。横のずれは turn_to で 0 になるよう後ろから積む。
	var turn := deg_to_rad(float(spec.get("turn_deg", 0.0)))
	var turn_from := float(spec.get("turn_from", start_s))
	var turn_to := float(spec.get("turn_to", start_s + 1.0))
	var lat_table := _turn_profile(start_s, turn, turn_from, turn_to, td_s + 400.0, ds)
	var s := start_s
	var v := v_app
	var pitch := 0.0
	var pitch_rate := 0.0
	var roll := 0.0
	var roll_rate := 0.0
	var d := -10.0
	var d_rate := 0.0
	var wet := false
	var touch_t := INF
	var prev_d := -10.0
	var steps := int(ceil(duration / DT)) + 1
	for k in range(steps):
		var t := float(k) * DT
		var abs_t := start_time + t
		var y := 0.0
		var a := 0.0
		var yaw := 0.0
		var lat := 0.0
		if not wet:
			# 速さ：slow_from から着く所まで v_td へ
			var v_target := lerpf(v_app, v_td, _ss5((s - slow_from) / maxf(td_s - slow_from, 1.0)))
			a = (v_target - v) / DT if k > 0 else 0.0
			v = v_target
			var h := _table(heights, start_s, ds, s)
			var gamma := _table(angles, start_s, ds, s)
			var kappa := (_table(angles, start_s, ds, s + 0.5) - _table(angles, start_s, ds, s - 0.5)) / 1.0
			var load := 1.0 + v * v * kappa / G
			var alpha := alpha_ref * pow(v_app / maxf(v, 1.0), 2.0) * load
			var wobble := turb * _air_wobble(abs_t)
			var pitch_cmd := gamma + alpha + wobble.x
			# 横
			var psi := _table(lat_table.psi, start_s, ds, s)
			var curve := (_table(lat_table.psi, start_s, ds, s + 0.5) - _table(lat_table.psi, start_s, ds, s - 0.5)) / 1.0
			lat = _table(lat_table.lat, start_s, ds, s)
			yaw = psi + wobble.z
			# 右へ曲がる（psi が減る）ときは右の翼を下げる（正）
			var roll_cmd := atan(-v * v * curve / G) + wobble.y
			if k == 0:
				pitch = pitch_cmd
				roll = roll_cmd
			pitch_rate += (36.0 * (pitch_cmd - pitch) - 2.0 * 0.85 * 6.0 * pitch_rate) * DT
			pitch += pitch_rate * DT
			roll_rate += (16.0 * (roll_cmd - roll) - 2.0 * 0.8 * 4.0 * roll_rate) * DT
			roll += roll_rate * DT
			y = h + turb * 0.1 * sin(TAU * abs_t * 0.45 + 1.7) * clampf(h / 6.0, 0.0, 1.0)
			d = _step_height(pitch) - y
			if d >= 0.0 and k > 0:
				wet = true
				touch_t = abs_t
				d_rate = (d - prev_d) / DT
				f.touchdown_sink = d_rate
				# 段が水を打つと、重心の後ろが持ち上がって機首が下がる
				pitch_rate -= 0.035 * d_rate
			prev_d = d
			s += v * DT
		else:
			var since := abs_t - touch_t
			var rev := smoothstep(0.15, 0.9, since)
			# 逆推力いっぱい＋水の抵抗（段から下りる「こぶ」の速さで最も強い）。止まる直前はやわらげて、そっと止まる。
			a = -(1.4 + float(spec.get("reverse_decel", 4.6)) * rev + 0.9 * pow(v / 35.0, 2.0) + 4.0 * exp(-pow((v - 12.0) / 5.0, 2.0)))
			a *= clampf(v / 1.5, 0.3, 1.0) if v > 0.0 else 0.0
			v = maxf(v + a * DT, 0.0)
			if v <= 0.0 and not is_finite(f.stop_at):
				f.stop_at = abs_t
			var trim := deg_to_rad(_curve(TRIM_LAND, v)) + deg_to_rad(0.1) * a
			var sink := _curve(SINK, v)
			var w_p := lerpf(TAU / 2.6, TAU / 1.0, smoothstep(3.0, 20.0, v))
			var w_d := lerpf(TAU / 2.2, TAU / 0.75, smoothstep(3.0, 20.0, v))
			pitch_rate += (w_p * w_p * (trim - pitch) - 2.0 * 0.32 * w_p * pitch_rate) * DT
			pitch += pitch_rate * DT
			d_rate += (w_d * w_d * (sink - d) - 2.0 * 0.45 * w_d * d_rate) * DT
			d += d_rate * DT
			roll_rate += ((TAU / 1.6) * (TAU / 1.6) * (0.0 - roll) - 2.0 * 0.35 * (TAU / 1.6) * roll_rate) * DT
			roll += roll_rate * DT
			y = _step_height(pitch) - d
			lat = _table(lat_table.lat, start_s, ds, s)
			yaw = deg_to_rad(0.25) * sin(TAU * abs_t * 0.31 + 0.5) * smoothstep(0.0, 1.0, since)
			s += v * DT
		f._push(s, lat, y, pitch, roll, yaw, v, a, d)
	f.touchdown_at = touch_t
	return f


## 縦の道すじ：start_s から ds ごとの高さと角度。flare_s から先は角度を 5 次で touch へ起こし、touch_h に届く s（td_s）を決める。
static func _glide_profile(start_s: float, anchor_s: float, anchor_h: float, glide: float, flare_s: float, touch: float,
		touch_h: float, ds: float) -> Dictionary:
	var h_flare := anchor_h - (flare_s - anchor_s) * tan(glide)
	var lo := 5.0
	var hi := 600.0
	for _i in range(48):
		var mid := (lo + hi) * 0.5
		if _flare_end_height(h_flare, glide, touch, mid, ds) > touch_h:
			lo = mid
		else:
			hi = mid
	var flare_len := (lo + hi) * 0.5
	var td_s := flare_s + flare_len
	var heights := PackedFloat32Array()
	var angles := PackedFloat32Array()
	var count := int(ceil((td_s + 400.0 - start_s) / ds)) + 2
	var h := anchor_h - (start_s - anchor_s) * tan(glide)
	for k in range(count):
		var s := start_s + float(k) * ds
		var g := -glide
		if s > flare_s:
			g = -glide + (glide - touch) * _ss5((s - flare_s) / flare_len)
		heights.append(h)
		angles.append(g)
		h += tan(g) * ds
	return {"h": heights, "g": angles, "td_s": td_s}


static func _flare_end_height(h0: float, glide: float, touch: float, flare_len: float, ds: float) -> float:
	var h := h0
	var s := 0.0
	while s < flare_len:
		var g := -glide + (glide - touch) * _ss5(s / flare_len)
		h += tan(g) * ds
		s += ds
	return h


## 横の道すじ：turn_from〜turn_to で向きのずれ（psi、左へ向くと正）を turn から 0 へ。横のずれは turn_to で 0。
static func _turn_profile(start_s: float, turn: float, turn_from: float, turn_to: float, end_s: float, ds: float) -> Dictionary:
	var count := int(ceil((end_s - start_s) / ds)) + 2
	var psi := PackedFloat32Array()
	psi.resize(count)
	for k in range(count):
		var s := start_s + float(k) * ds
		psi[k] = turn * (1.0 - _ss5((s - turn_from) / maxf(turn_to - turn_from, 0.1)))
	# 右から寄せる（turn > 0）：機首は左（−X）へ向いていて、横のずれは正。turn_to で 0 になるよう、後ろから積む。
	var lat := PackedFloat32Array()
	lat.resize(count)
	var end_k := clampi(int(round((turn_to - start_s) / ds)), 0, count - 1)
	for k in range(end_k, count):
		lat[k] = 0.0
	for k in range(end_k - 1, -1, -1):
		lat[k] = lat[k + 1] + tan(psi[k]) * ds
	return {"psi": psi, "lat": lat}


# ================================================================== 後ろ向きに寄せる（dock）

## spec：from_s・to_s（止まる s）・speed（下がる速さ、正）・brake（止まるまでの減速の秒）・duration（積む長さ）・wander（向きのゆらぎ、度）
## 始まりは逆推力で一定の速さ、最後の brake 秒で 5 次でなめらかに止まる（加速度も 0 で止まる）。
static func dock(frame_xf: Transform3D, start_time: float, spec: Dictionary) -> FloatplaneFlight:
	var f := FloatplaneFlight.new()
	f.frame = frame_xf
	f.t0 = start_time
	var from_s := float(spec.get("from_s", 30.0))
	var to_s := float(spec.get("to_s", 20.0))
	var speed := absf(float(spec.get("speed", 4.0)))
	var brake := float(spec.get("brake", 2.4))
	var duration := float(spec.get("duration", 12.0))
	var wander := deg_to_rad(float(spec.get("wander", 0.6)))
	## 止まっている所から下がり始めるときの加速の秒（0 なら初めから speed）。
	var accel_time := float(spec.get("accel_time", 0.0))
	var state: Dictionary = spec.get("state", {})
	var dist := absf(from_s - to_s)
	var dir := signf(to_s - from_s) if dist > 0.001 else -1.0
	brake = minf(brake, 2.0 * dist / maxf(speed, 0.1))
	var cruise := maxf((dist - speed * (brake + accel_time) * 0.5) / maxf(speed, 0.1), 0.0)
	var t_cruise := accel_time + cruise
	var t_stop := t_cruise + brake
	var v := dir * speed if accel_time <= 0.0 else 0.0
	var pitch := float(state.get("pitch", deg_to_rad(0.25 + 0.1 * absf(v))))
	var pitch_rate := float(state.get("pitch_rate", 0.0))
	var d := float(state.get("d", DRAFT + 0.012 * absf(v)))
	var d_rate := float(state.get("d_rate", 0.0))
	var roll := 0.0
	var roll_rate := 0.0
	var steps := int(ceil(duration / DT)) + 1
	for k in range(steps):
		var t := float(k) * DT
		var s: float
		var a := 0.0
		var run_in := speed * accel_time * 0.5
		if t < accel_time:
			var u0 := t / accel_time
			s = from_s + dir * speed * accel_time * (u0 * u0 * u0 * u0 * (u0 * u0 - 3.0 * u0 + 2.5))
			v = dir * speed * _ss5(u0)
			a = dir * speed * _ss5_rate(u0) / accel_time
		elif t < t_cruise:
			s = from_s + dir * (run_in + speed * (t - accel_time))
			v = dir * speed
		elif t < t_stop:
			var u := (t - t_cruise) / brake
			s = from_s + dir * (run_in + speed * cruise + speed * brake * _ss5_integral(u))
			v = dir * speed * (1.0 - _ss5(u))
			a = -dir * speed * _ss5_rate(u) / brake
		else:
			s = to_s
			v = 0.0
		# 下がる：逆推力（プロペラの線は重心より上）で機首が少し上がる。止める間は水の抵抗で戻る。
		var trim := deg_to_rad(0.25 + 0.1 * absf(v)) - deg_to_rad(0.15) * absf(a)
		var sink := DRAFT + 0.012 * absf(v)
		var w_p := lerpf(TAU / 2.6, TAU / 1.4, smoothstep(3.0, 12.0, absf(v)))
		var w_d := lerpf(TAU / 2.2, TAU / 1.2, smoothstep(3.0, 12.0, absf(v)))
		pitch_rate += (w_p * w_p * (trim - pitch) - 2.0 * 0.3 * w_p * pitch_rate) * DT
		pitch += pitch_rate * DT
		d_rate += (w_d * w_d * (sink - d) - 2.0 * 0.4 * w_d * d_rate) * DT
		d += d_rate * DT
		roll_rate += ((TAU / 2.0) * (TAU / 2.0) * (0.0 - roll) - 2.0 * 0.3 * (TAU / 2.0) * roll_rate) * DT
		roll += roll_rate * DT
		# 操縦士が左右の推力で向きを直す：止まるまでに 0 へ
		var settle := (1.0 - smoothstep(0.0, t_stop, t)) * smoothstep(0.0, accel_time + 0.5, t)
		var yaw := wander * (0.7 * sin(TAU * t * 0.23 + 0.4) + 0.3 * sin(TAU * t * 0.41 + 2.0)) * settle
		var lat := 0.12 * sin(TAU * t * 0.17 + 1.2) * settle
		f._push(s, lat, _step_height(pitch) - d, pitch, roll, yaw, v, a, d)
	f.stop_at = start_time + t_stop
	return f


# ================================================================== 動き出し（taxi）

## spec：from_s・go（動き出す秒、t0 から）・accel（押し出す加速度の最大）・duration・state（引き継ぐ姿勢。last_state() の形、なくてもよい）
static func taxi(frame_xf: Transform3D, start_time: float, spec: Dictionary) -> FloatplaneFlight:
	var f := FloatplaneFlight.new()
	f.frame = frame_xf
	f.t0 = start_time
	var state: Dictionary = spec.get("state", {})
	var s := float(spec.get("from_s", 0.0))
	var go := float(spec.get("go", 0.5))
	var accel := float(spec.get("accel", 1.4))
	var duration := float(spec.get("duration", 3.0))
	var v := 0.0
	var pitch := float(state.get("pitch", deg_to_rad(0.3)))
	var pitch_rate := float(state.get("pitch_rate", 0.0))
	var d := float(state.get("d", DRAFT))
	var d_rate := float(state.get("d_rate", 0.0))
	var steps := int(ceil(duration / DT)) + 1
	for k in range(steps):
		var t := float(k) * DT
		var a := accel * smoothstep(go, go + 1.4, t)
		v += a * DT
		s += v * DT
		# 推力を上げると、プロペラの線が重心より上なので機首がいったん少し沈み、速さが出ると水の力で上がっていく
		var trim := deg_to_rad(_curve(TRIM_TAKEOFF, v)) - deg_to_rad(0.35) * smoothstep(go, go + 0.6, t) * (1.0 - smoothstep(2.0, 5.0, v))
		var sink := _curve(SINK, v)
		var w_p := lerpf(TAU / 2.6, TAU / 1.2, smoothstep(2.0, 12.0, v))
		var w_d := TAU / 2.0
		pitch_rate += (w_p * w_p * (trim - pitch) - 2.0 * 0.35 * w_p * pitch_rate) * DT
		pitch += pitch_rate * DT
		d_rate += (w_d * w_d * (sink - d) - 2.0 * 0.45 * w_d * d_rate) * DT
		d += d_rate * DT
		f._push(s, 0.0, _step_height(pitch) - d, pitch, 0.0, 0.0, v, a, d)
	return f


# ================================================================== 離水（takeoff）

## spec：from_s・v0（段に乗って滑走している速さ）・duration・v_rotate（機首を起こし始める速さ）・rotate_time・pitch_lof（浮く姿勢、度）
##   v_lof（浮く速さ）・climb_deg（上昇の角度）・alpha_deg（浮いたあとの迎え角）
##   turn_after（浮いてから旋回を始める秒）・turn_rate（旋回の速さ、度/秒。正で右）
static func takeoff(frame_xf: Transform3D, start_time: float, spec: Dictionary) -> FloatplaneFlight:
	var f := FloatplaneFlight.new()
	f.frame = frame_xf
	f.t0 = start_time
	var s := float(spec.get("from_s", 0.0))
	var v := float(spec.get("v0", 26.0))
	var duration := float(spec.get("duration", 5.0))
	var v_rotate := float(spec.get("v_rotate", 31.0))
	var rotate_time := float(spec.get("rotate_time", 0.9))
	var pitch_lof := deg_to_rad(float(spec.get("pitch_lof", 8.5)))
	var v_lof := float(spec.get("v_lof", 34.5))
	var climb := deg_to_rad(float(spec.get("climb_deg", 7.0)))
	var alpha_air := deg_to_rad(float(spec.get("alpha_deg", 7.5)))
	var pitch := deg_to_rad(_curve(TRIM_TAKEOFF, v))
	var pitch_rate := 0.0
	var d := _curve(SINK, v)
	var d_rate := 0.0
	var roll := 0.0
	var roll_rate := 0.0
	var rotate_at := INF
	var air := false
	var y := _step_height(pitch) - d
	var gamma := 0.0
	var turn_after := float(spec.get("turn_after", INF))
	var turn_rate := deg_to_rad(float(spec.get("turn_rate", 0.0)))
	var heading := 0.0
	var lat := 0.0
	var steps := int(ceil(duration / DT)) + 1
	for k in range(steps):
		var t := float(k) * DT
		var abs_t := start_time + t
		var a: float
		if not air:
			a = 3.5 - 0.012 * pow(v - 26.0, 2.0)
			v += a * DT
			if v >= v_rotate and not is_finite(rotate_at):
				rotate_at = t
			var rot := smoothstep(0.0, rotate_time, t - rotate_at) if is_finite(rotate_at) else 0.0
			var trim := lerpf(deg_to_rad(_curve(TRIM_TAKEOFF, v)), pitch_lof, rot)
			# 浮く前は翼が重さを受け持っていき、段の沈みが 0 へ
			var lift := clampf(pow(v / v_lof, 2.0) * lerpf(0.75, 1.0, rot), 0.0, 1.0)
			var sink := _curve(SINK, v) * (1.0 - smoothstep(0.82, 1.0, lift))
			var w_p := TAU / 0.95
			var w_d := TAU / 0.7
			pitch_rate += (w_p * w_p * (trim - pitch) - 2.0 * 0.4 * w_p * pitch_rate) * DT
			pitch += pitch_rate * DT
			d_rate += (w_d * w_d * (sink - d) - 2.0 * 0.5 * w_d * d_rate) * DT
			d += d_rate * DT
			y = _step_height(pitch) - d
			# 浮く：速さが足りて、機首が起きた
			if v >= v_lof and rot >= 0.95 and not air:
				air = true
				f.liftoff_at = abs_t
				gamma = atan2(-d_rate, v)
			roll_rate += ((TAU / 1.2) * (TAU / 1.2) * (0.0 - roll) - 2.0 * 0.35 * (TAU / 1.2) * roll_rate) * DT
			roll += roll_rate * DT
		else:
			var since := abs_t - f.liftoff_at
			a = 2.2
			v += a * DT
			# 道すじを荷重 1.2 G で上へ曲げ、climb の角度で止める
			var bend := 0.2 * G / maxf(v, 1.0)
			gamma = minf(gamma + bend * DT * smoothstep(0.0, 0.3, since), climb)
			var alpha := alpha_air * pow(v_lof / v, 2.0)
			var pitch_cmd := gamma + alpha
			pitch_rate += (25.0 * (pitch_cmd - pitch) - 2.0 * 0.9 * 5.0 * pitch_rate) * DT
			pitch += pitch_rate * DT
			y += v * tan(gamma) * DT
			d = _step_height(pitch) - y
			# 浮いて少ししたら、翼を傾けて緩く旋回しながら上がっていく（右旋回は向きが減る＝右の翼を下げる）
			var w := turn_rate * smoothstep(turn_after, turn_after + 1.5, since)
			heading -= w * DT
			# 片方の浮き舟が先に離れて、小さく傾いてから戻す
			var roll_cmd := deg_to_rad(1.2) * sin(PI * clampf(since / 1.6, 0.0, 1.0)) + deg_to_rad(0.8) * sin(TAU * abs_t * 0.4)
			roll_cmd += atan(v * w / G)
			roll_rate += (9.0 * (roll_cmd - roll) - 2.0 * 0.8 * 3.0 * roll_rate) * DT
			roll += roll_rate * DT
		s += v * cos(heading) * DT
		lat += -v * sin(heading) * DT
		f._push(s, lat, y, pitch, roll, heading, v, a, d)
	return f


# ================================================================== 動き出しから離水・上昇まで続けて（departure）

## 止まっている所から、推力を上げて動き出し、こぶを越えて段に乗って滑走し、機首を起こして浮き、上昇する（時間を飛ばさない。
## c130_float.md 第10章）。level_h を決めると、その高さ（枠の海面から）へなめらかに水平になる。
## spec：from_s・go（推力を上げ始める秒、t0 から）・spool（推力が上がりきるまでの秒）・a_max（押す加速度の最大）
##   v_rotate・rotate_time・pitch_lof（度）・v_lof・climb_deg・alpha_deg・level_h（INF なら水平にしない）・v_cruise（上昇中に近づける速さ）
##   turn_after（浮いてから旋回を始める秒）・turn_rate（度/秒、正で右）・turn_for（旋回を続ける秒）・duration・state（引き継ぐ姿勢）
static func departure(frame_xf: Transform3D, start_time: float, spec: Dictionary) -> FloatplaneFlight:
	var f := FloatplaneFlight.new()
	f.frame = frame_xf
	f.t0 = start_time
	var state: Dictionary = spec.get("state", {})
	var s := float(spec.get("from_s", 0.0))
	var go := float(spec.get("go", 0.5))
	var spool := float(spec.get("spool", 1.6))
	var a_max := float(spec.get("a_max", 4.0))
	var duration := float(spec.get("duration", 20.0))
	var v_rotate := float(spec.get("v_rotate", 31.0))
	var rotate_time := float(spec.get("rotate_time", 0.9))
	var pitch_lof := deg_to_rad(float(spec.get("pitch_lof", 8.5)))
	var v_lof := float(spec.get("v_lof", 34.5))
	var climb := deg_to_rad(float(spec.get("climb_deg", 10.0)))
	var alpha_air := deg_to_rad(float(spec.get("alpha_deg", 7.5)))
	var level_h := float(spec.get("level_h", INF))
	var v_cruise := float(spec.get("v_cruise", 48.0))
	var turn_after := float(spec.get("turn_after", INF))
	var turn_rate := deg_to_rad(float(spec.get("turn_rate", 0.0)))
	var turn_for := float(spec.get("turn_for", INF))
	var v := 0.0
	var pitch := float(state.get("pitch", deg_to_rad(0.3)))
	var pitch_rate := float(state.get("pitch_rate", 0.0))
	var d := float(state.get("d", DRAFT))
	var d_rate := float(state.get("d_rate", 0.0))
	var roll := 0.0
	var roll_rate := 0.0
	var rotate_at := INF
	var air := false
	var y := _step_height(pitch) - d
	var gamma := 0.0
	var heading := 0.0
	var lat := 0.0
	var steps := int(ceil(duration / DT)) + 1
	for k in range(steps):
		var t := float(k) * DT
		var abs_t := start_time + t
		var a: float
		if not air:
			# 推力（なめらかに上がる）− 水の抵抗（こぶの速さ約 10 m/秒で最も強い）− 空気の抵抗
			var thrust := a_max * smoothstep(go, go + spool, t)
			a = thrust - 1.6 * exp(-pow((v - 10.0) / 4.5, 2.0)) * smoothstep(0.5, 4.0, v) - 0.0012 * v * v
			v = maxf(v + a * DT, 0.0)
			if v >= v_rotate and not is_finite(rotate_at):
				rotate_at = t
			var rot := smoothstep(0.0, rotate_time, t - rotate_at) if is_finite(rotate_at) else 0.0
			# 推力を上げると機首がいったん少し沈み、速さが出ると水の力で上がる（taxi と同じ）
			var trim := lerpf(deg_to_rad(_curve(TRIM_TAKEOFF, v)) - deg_to_rad(0.35) * smoothstep(go, go + 0.6, t) * (1.0 - smoothstep(2.0, 5.0, v)), pitch_lof, rot)
			var lift := clampf(pow(v / v_lof, 2.0) * lerpf(0.75, 1.0, rot), 0.0, 1.0)
			var sink := _curve(SINK, v) * (1.0 - smoothstep(0.82, 1.0, lift))
			var w_p := lerpf(TAU / 2.6, TAU / 0.95, smoothstep(2.0, 14.0, v))
			var w_d := lerpf(TAU / 2.0, TAU / 0.7, smoothstep(6.0, 20.0, v))
			pitch_rate += (w_p * w_p * (trim - pitch) - 2.0 * lerpf(0.35, 0.4, smoothstep(2.0, 14.0, v)) * w_p * pitch_rate) * DT
			pitch += pitch_rate * DT
			d_rate += (w_d * w_d * (sink - d) - 2.0 * 0.47 * w_d * d_rate) * DT
			d += d_rate * DT
			y = _step_height(pitch) - d
			if v >= v_lof and rot >= 0.95:
				air = true
				f.liftoff_at = abs_t
				gamma = atan2(-d_rate, v)
			roll_rate += ((TAU / 1.2) * (TAU / 1.2) * (0.0 - roll) - 2.0 * 0.35 * (TAU / 1.2) * roll_rate) * DT
			roll += roll_rate * DT
		else:
			var since := abs_t - f.liftoff_at
			a = clampf((v_cruise - v) * 0.35, -1.0, 2.6)
			v += a * DT
			# 道すじを 1.25 G で上へ曲げて climb で止め、level_h に近づくと 0.85 G でなめらかに水平へ
			var bend := 0.25 * G / maxf(v, 1.0)
			var target := climb
			if is_finite(level_h):
				var left := level_h - y
				target = clampf(atan(left / maxf(v * 3.2, 1.0)) * 1.6, -climb * 0.4, climb)
			gamma = move_toward(gamma, target, bend * DT * smoothstep(0.0, 0.3, since))
			var alpha := alpha_air * pow(v_lof / maxf(v, 1.0), 2.0)
			var pitch_cmd := gamma + alpha
			pitch_rate += (25.0 * (pitch_cmd - pitch) - 2.0 * 0.9 * 5.0 * pitch_rate) * DT
			pitch += pitch_rate * DT
			y += v * tan(gamma) * DT
			d = _step_height(pitch) - y
			var w := turn_rate * smoothstep(turn_after, turn_after + 1.5, since) * (1.0 - smoothstep(turn_after + turn_for, turn_after + turn_for + 1.5, since))
			heading -= w * DT
			var roll_cmd := deg_to_rad(1.2) * sin(PI * clampf(since / 1.6, 0.0, 1.0)) + deg_to_rad(0.6) * sin(TAU * abs_t * 0.4)
			roll_cmd += atan(v * w / G)
			roll_rate += (9.0 * (roll_cmd - roll) - 2.0 * 0.8 * 3.0 * roll_rate) * DT
			roll += roll_rate * DT
		s += v * cos(heading) * DT
		lat += -v * sin(heading) * DT
		f._push(s, lat, y, pitch, roll, heading, v, a, d)
	return f


# ================================================================== helpers

func _push(s: float, lat: float, y: float, pitch: float, roll: float, yaw: float, v: float, a: float, d: float) -> void:
	_s.append(s)
	_lat.append(lat)
	_y.append(y)
	_pitch.append(pitch)
	_roll.append(roll)
	_yaw.append(yaw)
	_v.append(v)
	_a.append(a)
	_d.append(d)


## 段の底が海面にちょうど触れるときの原点の高さ（pitch は機首上げが正）。
static func _step_height(pitch: float) -> float:
	return -STEP_Y * cos(pitch) + STEP_Z * sin(pitch)


## 空の揺れ（x＝縦、y＝横の傾き、z＝向き。rad）。いくつかのゆっくりした波を重ねる。
static func _air_wobble(t: float) -> Vector3:
	var pitch := deg_to_rad(0.35) * (0.6 * sin(TAU * t * 0.53 + 0.3) + 0.4 * sin(TAU * t * 1.21 + 1.9))
	var roll := deg_to_rad(1.4) * (0.55 * sin(TAU * t * 0.37 + 2.4) + 0.3 * sin(TAU * t * 0.83 + 0.6) + 0.15 * sin(TAU * t * 1.7 + 1.3))
	var yaw := deg_to_rad(0.45) * (0.6 * sin(TAU * t * 0.29 + 1.1) + 0.4 * sin(TAU * t * 0.71 + 2.7))
	return Vector3(pitch, roll, yaw)


static func _table(values: PackedFloat32Array, start: float, step: float, x: float) -> float:
	var n := values.size()
	if n == 0:
		return 0.0
	var u := clampf((x - start) / step, 0.0, float(n - 1))
	var i := mini(int(u), maxi(n - 2, 0))
	var j := mini(i + 1, n - 1)
	return lerpf(values[i], values[j], u - float(i))


## 折れ線の表 [[x, y], ...] を読む（端より外は端の値）。
static func _curve(points: Array, x: float) -> float:
	var n := points.size()
	if x <= float(points[0][0]):
		return float(points[0][1])
	for i in range(n - 1):
		var x1 := float(points[i + 1][0])
		if x <= x1:
			var x0 := float(points[i][0])
			var u := (x - x0) / maxf(x1 - x0, 0.0001)
			return lerpf(float(points[i][1]), float(points[i + 1][1]), u * u * (3.0 - 2.0 * u))
	return float(points[n - 1][1])


## 5 次のなめらかな 0→1（始まりと終わりで速さも加速度も 0）。
static func _ss5(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## 1 − _ss5 の 0〜u の積分（なめらかに止まるあいだに進む割合。u＝1 で 0.5）。
static func _ss5_integral(u: float) -> float:
	var t := clampf(u, 0.0, 1.0)
	return t - (t * t * t * t * (t * (t - 3.0) + 2.5))


## _ss5 の傾き。
static func _ss5_rate(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 30.0 * t * t * (t - 1.0) * (t - 1.0)
