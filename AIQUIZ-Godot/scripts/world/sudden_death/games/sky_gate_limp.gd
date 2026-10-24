class_name SkyGateLimp
extends RefCounted

## まちがいのパネルに当たった人の「ラグドール」（docs/sudden_death_v2/skygate_impact.md）。体（腰）の動きは見せ方の式
## （SkyGateImpact）のまま、手足と首の関節だけを、力の抜けたばねとして体の上下の加速度で振り回す。
## 当たって止められると手足が紙の側へしなり、はね返されると逆へ振られ、くたっと垂れて揺れる。
## 物理エンジンは使わない（見せ方のスローと関係なく、同じ時刻なら同じ形。30／60／120fps で同じ）。
## 使い方：start() → 毎フレーム step(dt, 体の上下の速さ) → 腹ばいの姿を当てたあとで apply(parts)。

## 関節：[部品, 軸, 力が抜けたときの角度（度）, 体の速さの変わり方の効き（度/秒 あたり m/秒）, 下限, 上限（度）]
## 軸は部品のローカル（+X＝r_ の腕の側、+Y＝頭、+Z＝胸）。腹ばいなので、体が上へはじかれると手足は胸の側（紙の側）へしなる。
const JOINTS := [
	["spine", "x", 8.0, 8.0, -35.0, 35.0],
	["head_pivot", "x", 34.0, 18.0, -40.0, 70.0],
	["head_pivot", "z", 0.0, 6.0, -30.0, 30.0],
	["l_shoulder", "x", -30.0, -35.0, -150.0, 80.0],
	["r_shoulder", "x", -30.0, -32.0, -150.0, 80.0],
	["l_shoulder", "z", 36.0, 15.0, -60.0, 100.0],
	["r_shoulder", "z", -36.0, -15.0, -100.0, 60.0],
	["l_elbow", "z", 40.0, 20.0, -20.0, 120.0],
	["r_elbow", "z", -40.0, -20.0, -120.0, 20.0],
	["l_hip", "x", -14.0, -28.0, -110.0, 50.0],
	["r_hip", "x", -14.0, -25.0, -110.0, 50.0],
	["l_hip", "z", -10.0, -10.0, -50.0, 40.0],
	["r_hip", "z", 10.0, 10.0, -40.0, 50.0],
	["l_knee", "x", -24.0, 24.0, -60.0, 90.0],
	["r_knee", "x", -24.0, 22.0, -60.0, 90.0],
]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
## ばね（1/秒²）と減衰（1/秒）。小さいほどぐにゃぐにゃ。
const STIFF := 34.0
const DAMP := 3.2
## 力が抜けていく速さ（秒）：当たった瞬間から、この秒で「力が抜けたときの角度」へ寄る。
const GO_LIMP := 0.12
## 1 刻み（秒）。
const TICK := 1.0 / 240.0

var _angle := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _time := 0.0
var _acc := 0.0
var _active := false
var _seed := 0
var _last_v := NAN


func _init(seed_value := 0) -> void:
	_seed = seed_value
	reset()


func reset() -> void:
	_angle.resize(JOINTS.size())
	_speed.resize(JOINTS.size())
	for i in range(JOINTS.size()):
		_angle[i] = 0.0
		_speed[i] = 0.0
	_time = 0.0
	_acc = 0.0
	_active = false
	_last_v = NAN


## 当たった瞬間：力を抜く。関節ごとに少しちがう向きへはじく（手足がばらばらに動く）。
func start() -> void:
	reset()
	_active = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + _seed
	for i in range(JOINTS.size()):
		_speed[i] = deg_to_rad(rng.randf_range(-160.0, 160.0))


func is_active() -> bool:
	return _active


## dt 秒進める。vel_y は体の上下の速さ（m/秒、上が +）。速さの変わり方（加速度）で関節を振る：
## このフレームの速さの変わりを、刻みに分けて同じだけ与える（速さが急に変わるはね返りでも、フレームの長さによらず同じだけ振れる）。
func step(dt: float, vel_y: float) -> void:
	if not _active:
		return
	var accel_y := 0.0
	if not is_nan(_last_v) and dt > 0.0:
		accel_y = (vel_y - _last_v) / dt
	_last_v = vel_y
	_acc += maxf(dt, 0.0)
	while _acc >= TICK - 0.000001:
		_acc -= TICK
		_time += TICK
		var limp_w := smoothstep(0.0, GO_LIMP, _time)
		for i in range(JOINTS.size()):
			var row: Array = JOINTS[i]
			var rest := deg_to_rad(float(row[2])) * limp_w
			var push := deg_to_rad(float(row[3])) * accel_y
			var a := -STIFF * (_angle[i] - rest) - DAMP * _speed[i] + push
			_speed[i] += a * TICK
			var next := _angle[i] + _speed[i] * TICK
			var lo := deg_to_rad(float(row[4]))
			var hi := deg_to_rad(float(row[5]))
			if next < lo or next > hi:
				# 関節の限りで止まって少し跳ね返る
				next = clampf(next, lo, hi)
				_speed[i] *= -0.25
			_angle[i] = next


## 腹ばいの姿（DropMotion.pose_box）を当てたあとで呼ぶ：関節を部品のローカルの軸でさらに回す。
func apply(parts: Dictionary) -> void:
	if not _active:
		return
	for i in range(JOINTS.size()):
		var row: Array = JOINTS[i]
		var node := parts.get(row[0]) as Node3D
		if node == null:
			continue
		node.basis = node.basis * Basis(AXES[row[1]] as Vector3, _angle[i])
