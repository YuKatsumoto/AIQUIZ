class_name MenuRunnerGait
extends RefCounted

## メニュー背景ランナーの歩様の計算（状態を持たない）。
## コンベアの床は +z（カメラ側）へ流れているので、床に対する速さで足を運ぶ：その場に留まるランナーは
## 床の速さで走り、床と同じ速さで下がるランナーは立ち止まる。クリップの再生の速さは「床に対する速さ ÷ クリップの
## 自然な速さ」。
## 歩き・ジョグの speed と contact は tests/menu_runner_clip_probe.gd で表示用の箱の人形に当てて測った値
## （speed＝接地区間に足首が後ろへ流れた距離 ÷ その時間、contact＝左足が着く位相）。
## 走りは本編と同じ走り（Mixamo の Run）を本編と同じ速さで回す（本編は壁の速さ ÷ 3.5 倍）。体を起こした正しい
## 姿勢の走りで、本編を遊んだ人が見慣れた走りのまま（UAL の Sprint は全力疾走の前のめりなので普段の走りに使わない）。

## 本編の走りのアニメが 1 倍のときの壁の速さ（PlayerController.update_from_state の speed_ratio と同じ約束）
const RUN_GAME_SPEED: float = 3.5
## key / clip（空なら AnimationRig のその枠の既定のクリップ）/ slot / 自然な速さ m/s / 左足の接地の位相 /
## measured＝自然な速さが計測値か（false は本編に合わせた値で、計測テストは比べない）
const LOCOMOTION_CLIPS: Array[Dictionary] = [
	{"key": &"idle", "clip": "Idle_Loop", "slot": AnimationRig.SLOT_UAL, "speed": 0.0, "contact": 0.0, "measured": false},
	{"key": &"walk", "clip": "Walk_Loop", "slot": AnimationRig.SLOT_UAL, "speed": 0.82, "contact": 0.213, "measured": true},
	{"key": &"jog", "clip": "Jog_Fwd_Loop", "slot": AnimationRig.SLOT_UAL, "speed": 1.91, "contact": 0.167, "measured": true},
	{"key": &"run", "clip": "", "slot": AnimationRig.SLOT_RUN, "speed": RUN_GAME_SPEED, "contact": 0.4, "measured": false},
]
const IDLE := 0
const WALK := 1
const JOG := 2
const RUN := 3
## 速さの段の切り替え（m/s）。上り・下りで少しずらして行ったり来たりしないようにする
const BAND_UP: Array[float] = [0.45, 1.35, 2.5]
const BAND_DOWN: Array[float] = [0.25, 1.15, 2.25]
## 再生の速さの範囲（これを超える分は足が少し滑るが、見た目の崩れを防ぐ。走りの上限は本編の W 押し＝2 倍に合わせる）
const RATE_MIN: float = 0.55
const RATE_MAX: float = 2.2
## 向き：コンベアが動いているあいだは横移動でも壁の方を向いたまま ±38° まで、止まっていれば ±75° まで振り向く
const YAW_LIMIT_RUNNING: float = deg_to_rad(38.0)
const YAW_LIMIT_STOPPED: float = deg_to_rad(75.0)
const YAW_LIMIT_DODGE: float = deg_to_rad(60.0)
## 加速・減速の一瞬だけ体を前後へ、曲がる向きへ傾ける（ラジアン）。ふだんの走りの姿勢はクリップのまま
const LEAN_PER_ACCEL: float = 0.015
const LEAN_MIN: float = -0.06
const LEAN_MAX: float = 0.08
const BANK_PER_ACCEL: float = 0.025
const BANK_MAX: float = 0.12
const FACING_YAW: float = PI


static func clip_name(rig: AnimationRig, entry: Dictionary) -> String:
	var clip := String(entry.clip)
	if clip.is_empty() and rig != null and int(entry.slot) < rig.anim_names.size():
		clip = String(rig.anim_names[int(entry.slot)])
	return clip


static func cycle_length(rig: AnimationRig, entry: Dictionary) -> float:
	if rig == null:
		return 0.0
	return rig.get_ual_clip_length(clip_name(rig, entry), int(entry.slot))


## 床に対する速さから歩様の段を選ぶ（current は今の段。境目で行ったり来たりしない）
static func pick_band(speed: float, current: int) -> int:
	var band := clampi(current, IDLE, RUN)
	while band < RUN and speed >= BAND_UP[band]:
		band += 1
	while band > IDLE and speed < BAND_DOWN[band - 1]:
		band -= 1
	return band


## そのクリップを何倍速で回せば、足の運びが speed に合うか（後ろ向きに下がるときは負）
static func playback_rate(band: int, speed: float) -> float:
	var natural := float(LOCOMOTION_CLIPS[band].speed)
	if natural <= 0.0:
		return 1.0
	var rate := speed / natural
	return signf(rate) * clampf(absf(rate), RATE_MIN, RATE_MAX)


## 体の向きの目標（ヨー）。床に対する進む向きへ、壁向き（PI）から limit まで振る。
## 床より速くカメラ側へ下がるときは、壁を向いたまま後ろ向きに歩く（振り向かない）。
static func target_yaw(rel_velocity: Vector2, limit: float) -> float:
	if rel_velocity.length() < 0.3:
		return FACING_YAW
	var heading := atan2(rel_velocity.x, rel_velocity.y)
	var deviation := wrapf(heading - FACING_YAW, -PI, PI)
	if absf(deviation) > PI * 0.5:
		deviation = wrapf(deviation + PI, -PI, PI)
	return FACING_YAW + clampf(deviation, -limit, limit)


static func yaw_limit(belt_speed: float, dodging: bool) -> float:
	if dodging:
		return YAW_LIMIT_DODGE
	return lerpf(YAW_LIMIT_STOPPED, YAW_LIMIT_RUNNING, clampf(belt_speed / 2.0, 0.0, 1.0))


## 向いている方向（x, z）
static func facing_vector(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## 前後の加速と横の加速（向いている向きで見たもの）から、前傾とその向きへの傾き
static func lean_bank(accel: Vector2, yaw: float) -> Vector2:
	var forward := facing_vector(yaw)
	var right := Vector2(forward.y, -forward.x)
	var lean := clampf(accel.dot(forward) * LEAN_PER_ACCEL, LEAN_MIN, LEAN_MAX)
	var bank := clampf(accel.dot(right) * BANK_PER_ACCEL, -BANK_MAX, BANK_MAX)
	return Vector2(lean, bank)


## 世界の向きで、前へ lean・右へ bank 傾ける回転（StagingPuppet.stand_at の frame）
static func tilt_basis(yaw: float, lean: float, bank: float) -> Basis:
	var forward := facing_vector(yaw)
	var forward3 := Vector3(forward.x, 0.0, forward.y)
	var right3 := Vector3(forward.y, 0.0, -forward.x)
	var basis := Basis.IDENTITY
	if absf(lean) > 0.0001:
		basis = Basis(Vector3.UP.cross(forward3).normalized(), lean) * basis
	if absf(bank) > 0.0001:
		basis = Basis(Vector3.UP.cross(right3).normalized(), bank) * basis
	return basis
