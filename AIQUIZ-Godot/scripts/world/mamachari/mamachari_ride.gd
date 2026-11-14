extends RefCounted
class_name MamachariRide

## ママチャリの「乗り方」。進む速さ・前へ押しているか・地面に付いているかを受け取り、
## 座ってこぐ／立ちこぎ／止まって片足をつく／空中 を切り替え、自転車（MamachariRig）を動かす。
## 乗り手の姿勢は pose() の値を MamachariRider.apply に渡して作る。見た目だけで、判定や速さには関わらない。

## 画面の中で前へ進む速さ（m/s）がこれを超えたら「前へ押している」とみなして立ちこぎにする。
const STAND_PUSH_SPEED := 0.6
## 地面に対する速さ（m/s）がこれ未満で STOP_DELAY 秒たったら、止まったとみなして片足をつく。
const STOP_SPEED := 0.25
const STOP_DELAY := 0.15
## 止まっているあいだのクランクの位置：右のペダルが前ななめ上（2時）。こぎ出しやすい位置へ逆回しで戻す。
const READY_CRANK := deg_to_rad(330.0)
const READY_CRANK_SPEED := 5.0
const LEVEL_CRANK_SPEED := 7.0
## 立ちこぎで車体を左右に振る角度と、止まって足をついたときに車体を左へ倒す角度。
const SWAY_MAX := deg_to_rad(8.0)
const FOOT_DOWN_LEAN := deg_to_rad(7.0)
## ハンドルの切れ角に対する車体の傾き。
const STEER_LEAN := 0.45
## 着地で沈む量（タイヤのつぶれぶん。m）。
const LAND_SINK := 0.015

var rig: MamachariRig
## 自転車と乗り手の向き（入れ物の中での、上向きの軸まわりの回転）。
var yaw: float = 0.0
## 自転車の原点（床の高さ。入れ物の座標）。
var base_position: Vector3 = Vector3.ZERO

var steer: float = 0.0
## 立ちこぎ・片足をつく・空中 の度合い（0〜1。なめらかに変わる）。
var standing: float = 0.0
var foot_down: float = 0.0
var air: float = 0.0
## 着地の沈み（着地した瞬間に上がり、すぐ戻る。0〜1）。
var land: float = 0.0

var _stopped_time: float = 0.0
var _was_grounded: bool = true
var _last_rise: float = 0.0
var _pitch: float = 0.0


func _init(p_rig: MamachariRig) -> void:
	rig = p_rig


## 1フレーム進める。
##   ground_speed：地面に対して前へ進む速さ（m/s）   push_speed：画面の中で前へ進む速さ（前へ押している強さ）
##   side_speed：乗り手から見て左へ動く速さ          rise：上向きの速さ          grounded：地面に付いているか
##   braking：後ろへ下がろうとしている（ブレーキ）
func update(dt: float, ground_speed: float, push_speed: float, side_speed: float, rise: float, grounded: bool, braking: bool) -> void:
	var moving := absf(ground_speed) >= STOP_SPEED
	_stopped_time = 0.0 if (moving or not grounded) else _stopped_time + dt
	var want_down := grounded and _stopped_time > STOP_DELAY
	var want_stand := grounded and not braking and not want_down and push_speed > STAND_PUSH_SPEED and ground_speed > 0.5
	foot_down = move_toward(foot_down, 1.0 if want_down else 0.0, dt * (3.5 if want_down else 2.5))
	standing = move_toward(standing, 1.0 if want_stand else 0.0, dt * (4.0 if want_stand else 3.0))
	air = move_toward(air, 0.0 if grounded else 1.0, dt * (8.0 if grounded else 10.0))
	land *= exp(-dt * 7.0)
	if grounded and not _was_grounded:
		land = clampf(-_last_rise * 0.11, 0.0, 1.0)
	_was_grounded = grounded
	_last_rise = rise

	# 車輪とクランク
	var distance := ground_speed * dt
	if not grounded:
		# 空中：ペダルを水平にそろえて、その上に立つ。
		rig.advance(distance, false)
		var level := 0.0 if absf(angle_difference(rig.crank_angle, 0.0)) <= PI * 0.5 else PI
		rig.crank_angle = wrapf(rig.crank_angle + clampf(angle_difference(rig.crank_angle, level), -LEVEL_CRANK_SPEED * dt, LEVEL_CRANK_SPEED * dt), 0.0, TAU)
	elif want_down or foot_down > 0.5:
		# 止まる：こぎ出しの位置までペダルを逆回しで戻す（フリーホイールなので後ろへは空回りする）。
		rig.advance(distance, false)
		var ahead := wrapf(rig.crank_angle - READY_CRANK, 0.0, TAU)
		rig.crank_angle = wrapf(rig.crank_angle - minf(ahead, READY_CRANK_SPEED * dt), 0.0, TAU)
	else:
		rig.advance(distance, ground_speed > 0.4 and not braking)

	# ハンドルは進む向きへ切り、車体はその内側へ傾く。
	var steer_target := clampf(atan2(side_speed, maxf(absf(ground_speed), 3.0)) * 1.6, -MamachariRig.MAX_STEER, MamachariRig.MAX_STEER)
	steer = lerpf(steer, steer_target, 1.0 - exp(-dt * 10.0))
	rig.steer = steer
	rig.stand = 0.0
	var squeeze := 1.0 if (braking or want_down) else 0.0
	rig.brake_left = move_toward(rig.brake_left, squeeze, dt * 8.0)
	rig.brake_right = move_toward(rig.brake_right, squeeze, dt * 8.0)
	rig.saddle_sag = clampf(land * 1.3, 0.0, 1.0) * (1.0 - maxf(standing, air))
	# 跳んでいるあいだは、上がるときに前輪が上がり、下りるときに前が下がる。
	_pitch = 0.0 if grounded else clampf(-rise * 0.035, -0.28, 0.2)
	rig.rotation = Vector3(_pitch, yaw, _steer_lean() + _sway() + _stop_lean())
	rig.position = base_position + Vector3.DOWN * (LAND_SINK * land)
	rig.apply()


## 乗り手の姿勢を作るための値（MamachariRider.apply の pose）。
func pose() -> Dictionary:
	return {
		# 体の向き。立ちこぎの車体の振りには付いていかず、止まったときの傾きも少しだけ。
		"body_basis": Basis.from_euler(Vector3(_pitch, yaw, _steer_lean() + _stop_lean() * 0.35)),
		"standing": standing,
		"foot_down": foot_down,
		"air": air,
		"land": land,
	}


func _steer_lean() -> float:
	return -steer * STEER_LEAN


## 立ちこぎの振り：右足でふみ込むあいだ（右のペダルが前）は左へ、左足のときは右へ倒す。
func _sway() -> float:
	return -SWAY_MAX * standing * cos(rig.crank_angle)


## 止まって左足をつくときの傾き（乗り手の左 = +X へ）。
func _stop_lean() -> float:
	return -FOOT_DOWN_LEAN * smoothstep(0.0, 1.0, foot_down)
