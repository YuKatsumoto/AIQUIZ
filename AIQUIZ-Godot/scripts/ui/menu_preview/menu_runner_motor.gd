class_name MenuRunnerMotor
extends RefCounted

## ゴーストの体当たりで吹き飛ぶとき・海へ落ちるときの計算（状態を持たない静的関数）。

## 吹き飛ばしの減速と重力は本編（QuizGameState）と同じにして、同じ放物線で飛ばす
const KNOCKBACK_DECEL: float = QuizGameState.EXTERNAL_IMPULSE_DECELERATION
const KNOCKBACK_GRAVITY: float = QuizGameState.GRAVITY
## 海へ落ちるときの重力の倍率と、空中で横の勢いが抜ける速さ（1/秒）
const FALL_GRAVITY_SCALE: float = 1.35
const AIR_DRAG: float = 2.0


## 本編の吹き飛ばしと同じ：水平の速さを長さで減らしながら進める。戻り値は (位置, 速度)。
static func knockback_step(pos: Vector2, vel: Vector2, dt: float) -> Array[Vector2]:
	var next_pos := pos + vel * dt
	var next_vel := vel.move_toward(Vector2.ZERO, KNOCKBACK_DECEL * dt)
	return [next_pos, next_vel]


## 空中の水平の勢いを抜く（フレームレートによらない指数減衰）。
static func air_drag(vel: Vector2, dt: float) -> Vector2:
	return vel * exp(-AIR_DRAG * dt)
