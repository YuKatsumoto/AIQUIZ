class_name MenuGhostRiderBrain
extends RefCounted

## メニュー背景で、死んでゴーストシャークに乗ったランナーの「手」。本編で人が押すのと同じ入力
## （照準のスティックと突進ボタン）を作り、GhostSharkRideController.update_ghost_ride へ渡す。
## 照準に入るたびに作戦を立てる：少し考えてから狙い（ときどき大きく外す）、ボタンを長押しして
## PERFECT 帯・弱め・溜めすぎ（一周して戻る）のどこかで離す。考えているあいだにサメの上で踊ることもある。

enum Plan { PERFECT, WEAK, OVERSHOOT }

const AIM_SPEED: float = GhostSharkRideController.AIM_SPEED
## 照準の誤差をスティックの倒し具合へ直す時定数（秒）
const AIM_RESPONSE: float = 0.12
const AIM_DEAD_ZONE: float = 0.05
## 誤差がこれより小さくなったら押し始めてよい
const FIRE_TOLERANCE: float = 0.6
const FIRST_THINK_MIN: float = 0.7
const FIRST_THINK_MAX: float = 1.5
const NEXT_THINK_MIN: float = 0.4
const NEXT_THINK_MAX: float = 1.1
## 照準がこれだけ続いたら、合っていなくても撃つ
const FORCE_FIRE_AFTER: float = 6.0
const PLAN_PERFECT_SHARE: float = 0.55
const PLAN_WEAK_SHARE: float = 0.30
const AIM_NOISE_SIGMA := Vector2(0.45, 0.6)
const WHIFF_CHANCE: float = 0.18
const WHIFF_OFFSET_MIN: float = 2.2
const WHIFF_OFFSET_MAX: float = 3.4
## 生き残った人の動きを何秒先まで読むか（作戦ごとに 0.3〜0.9 倍）
const LEAD_SECONDS: float = 0.9
const TAUNT_EMOTE_CHANCE: float = 0.35

## テストが作戦の割合を変えるときに使う（forced_plan >= 0 なら毎回その作戦）
var whiff_chance: float = WHIFF_CHANCE
var forced_plan: int = -1
var rng: RandomNumberGenerator
var emotes: Array[int] = []

var plan: int = Plan.PERFECT
var _in_aiming := false
var _aim_time := 0.0
var _think := 0.0
var _release_at := 0.8
var _noise := Vector2.ZERO
var _lead := 0.6
var _pressing := false
var _wrapped := false
var _released := false
var _last_charge := 0.0
var _plans_made := 0
var _emote_to_send := 0


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func reset() -> void:
	_in_aiming = false
	_pressing = false
	_released = false
	_plans_made = 0
	_emote_to_send = 0


## phase は GhostSharkRideController.Phase。aim_point と survivor は世界座標、survivor_velocity はローカル (x, z)。
## 戻り値 {axis: Vector2, fire: bool, emote: int}
func update(dt: float, phase: int, aim_point: Vector3, survivor: Vector3,
		survivor_velocity: Vector2, charge: float) -> Dictionary:
	var out := {"axis": Vector2.ZERO, "fire": false, "emote": 0}
	if phase != GhostSharkRideController.Phase.AIMING:
		_in_aiming = false
		_pressing = false
		return out
	if not _in_aiming:
		_make_plan()
	_aim_time += dt
	var target := Vector2(survivor.x, survivor.z) + survivor_velocity * LEAD_SECONDS * _lead + _noise
	var error := target - Vector2(aim_point.x, aim_point.z)
	var axis := (error / (AIM_SPEED * AIM_RESPONSE)).limit_length(1.0)
	if error.length() < AIM_DEAD_ZONE:
		axis = Vector2.ZERO
	out["axis"] = axis
	if _emote_to_send > 0:
		out["emote"] = _emote_to_send
		_emote_to_send = 0
	if _released:
		return out
	if not _pressing:
		var ready := _aim_time >= _think and error.length() < FIRE_TOLERANCE
		if ready or _aim_time >= FORCE_FIRE_AFTER:
			_pressing = true
			_wrapped = false
			_last_charge = 0.0
			out["fire"] = true
		return out
	# 長押し中：コントローラーの溜め（0〜1 を 0.5 秒で一周）を見て、決めた所で離す
	if charge + 0.001 < _last_charge:
		_wrapped = true
	_last_charge = charge
	var release := charge >= _release_at
	if plan == Plan.OVERSHOOT:
		release = _wrapped and charge >= _release_at
	if release:
		_pressing = false
		_released = true
		return out
	out["fire"] = true
	return out


func _make_plan() -> void:
	_in_aiming = true
	_aim_time = 0.0
	_pressing = false
	_released = false
	_think = rng.randf_range(FIRST_THINK_MIN, FIRST_THINK_MAX) if _plans_made == 0 else rng.randf_range(NEXT_THINK_MIN, NEXT_THINK_MAX)
	_plans_made += 1
	var roll := rng.randf()
	if forced_plan >= 0:
		roll = [0.0, PLAN_PERFECT_SHARE, 1.0 - 0.001][forced_plan]
	if roll < PLAN_PERFECT_SHARE:
		plan = Plan.PERFECT
		_release_at = rng.randf_range(0.76, 0.90)
	elif roll < PLAN_PERFECT_SHARE + PLAN_WEAK_SHARE:
		plan = Plan.WEAK
		_release_at = rng.randf_range(0.30, 0.66)
	else:
		plan = Plan.OVERSHOOT
		_release_at = rng.randf_range(0.10, 0.40)
	_noise = Vector2(rng.randfn(0.0, AIM_NOISE_SIGMA.x), rng.randfn(0.0, AIM_NOISE_SIGMA.y))
	if rng.randf() < whiff_chance:
		_noise += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(WHIFF_OFFSET_MIN, WHIFF_OFFSET_MAX)
	_lead = rng.randf_range(0.3, 0.9)
	_emote_to_send = 0
	if not emotes.is_empty() and _think >= 1.0 and rng.randf() < TAUNT_EMOTE_CHANCE:
		_emote_to_send = emotes[rng.randi() % emotes.size()]
