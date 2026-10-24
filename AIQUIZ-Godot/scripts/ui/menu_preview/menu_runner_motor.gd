class_name MenuRunnerMotor
extends RefCounted

## メニュー背景ランナーの移動の計算だけをまとめた静的関数。状態は持たない。
## 横（x）と奥行き（z）を別々に、加速して巡航し、目標の手前で止まれる速さまで落としてぴたりと止める。

const LANE_ACCEL: float = 9.0
const LANE_DECEL: float = 11.0
const DEPTH_ACCEL: float = 7.5
const DEPTH_DECEL: float = 9.5
## ゴーストの突進をよけるときの踏み切り
const DODGE_ACCEL: float = 18.0
const ARRIVE_EPSILON: float = 0.03
## 1フレームでこれ以上ずれていたら、外から位置を書き換えられた（テストの固定・復活・2P の登場）とみなす
const TELEPORT_DISTANCE: float = 0.5
## 吹き飛ばしの減速と重力は本編（QuizGameState）と同じにして、同じ放物線で飛ばす
const KNOCKBACK_DECEL: float = QuizGameState.EXTERNAL_IMPULSE_DECELERATION
const KNOCKBACK_GRAVITY: float = QuizGameState.GRAVITY
## 海へ落ちるときの重力の倍率と、空中で横の勢いが抜ける速さ（1/秒）
const FALL_GRAVITY_SCALE: float = 1.35
const AIR_DRAG: float = 2.0


## 残り distance で decel をかけて止まりきれる速さ（cruise が上限）
static func arrive_speed(distance: float, cruise: float, decel: float) -> float:
	return minf(cruise, sqrt(2.0 * decel * maxf(0.0, distance)))


## 1軸を目標へ動かす。戻り値は (新しい位置, 新しい速度, 着いたら 1.0)。
## 加速は accel、減速と折り返しは decel。目標を飛び越えるフレームは目標で止める。
static func steer_axis(pos: float, vel: float, target: float, cruise: float,
		accel: float, decel: float, dt: float) -> Vector3:
	var offset := target - pos
	var dist := absf(offset)
	if dist <= ARRIVE_EPSILON and absf(vel) <= decel * dt + 0.05:
		return Vector3(target, 0.0, 1.0)
	var desired := signf(offset) * arrive_speed(dist, maxf(0.0, cruise), decel)
	var speeding_up := desired * vel >= 0.0 and absf(desired) > absf(vel)
	var next_vel := move_toward(vel, desired, (accel if speeding_up else decel) * dt)
	var next_pos := pos + next_vel * dt
	var next_offset := target - next_pos
	if signf(next_offset) != signf(offset) or absf(next_offset) <= ARRIVE_EPSILON * 0.5:
		return Vector3(target, 0.0, 1.0)
	return Vector3(next_pos, next_vel, 0.0)


## 目標を持たないときは止まるまでブレーキをかける。戻り値は (新しい位置, 新しい速度)。
static func brake_axis(pos: float, vel: float, decel: float, dt: float) -> Vector2:
	if is_zero_approx(vel):
		return Vector2(pos, 0.0)
	var next_vel := move_toward(vel, 0.0, decel * dt)
	return Vector2(pos + (vel + next_vel) * 0.5 * dt, next_vel)


## 本編の吹き飛ばしと同じ：水平の速さを長さで減らしながら進める。戻り値は (位置, 速度)。
static func knockback_step(pos: Vector2, vel: Vector2, dt: float) -> Array[Vector2]:
	var next_pos := pos + vel * dt
	var next_vel := vel.move_toward(Vector2.ZERO, KNOCKBACK_DECEL * dt)
	return [next_pos, next_vel]


## 空中の水平の勢いを抜く（フレームレートによらない指数減衰）。
static func air_drag(vel: Vector2, dt: float) -> Vector2:
	return vel * exp(-AIR_DRAG * dt)


## コンベアの床に対する速度。床は +z（カメラ側）へ belt_speed で流れる。
## その場に留まって走るランナーは (0, -belt_speed) で走っていることになる。
static func belt_relative_velocity(vel_x: float, vel_z: float, belt_speed: float) -> Vector2:
	return Vector2(vel_x, vel_z - belt_speed)


## 1 - exp(-rate*dt)：毎秒 rate 回の割合で起きることが、このフレームに起きる確率。
static func chance_per_frame(rate: float, dt: float) -> float:
	return 1.0 - exp(-maxf(0.0, rate) * maxf(0.0, dt))
