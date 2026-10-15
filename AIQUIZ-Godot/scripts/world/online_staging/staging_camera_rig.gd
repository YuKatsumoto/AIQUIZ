class_name StagingCameraRig
extends RefCounted

## マッチング演出のカメラ（仕様書 6・21）。ショットは OnlineStagingTimeline の「ヘリの座標（H）」で書き、
## 基準の Transform3D（パッドのヘリ、または飛んでいるヘリの揺れない枠）でワールドへ直す。
##   cut(shot, frame) / cut_to(target)  すぐ切り替える（追いかけの速さも 0 に戻す）
##   blend_to(shot, frame, 秒)           今の位置から 3 次の加減速でつなぐ（つなぐ先が動いても追う）。blend_to_target も同じ
##   follow_lag                          > 0 なら、目標へ臨界減衰のばねで近づく（秒）
## update(delta, target) で Camera3D を置く。target は {pos, look, fov} と、あれば次のもの（StagingShots が作る）：
##   roll   画面の傾き（度。機体と同じ向きに傾けるときは正。前を向いた軸のまわり）
##   lag    {pos, look, fov}：それぞれの追いかけの遅れ（秒）。ないものは follow_lag
##   float  手持ちの「ただよい」の強さ（0〜1）。0.13〜0.34 Hz の低い周波数だけで、揺れ（シェイク）ではない（仕様書 16）
##   focus  ピントの距離（m）、dof  ぼけの強さ（0〜1）。ぼけは画質で決める（set_dof_level）
## kick()：ジェットブーストの点火の一瞬の揺れ（IGNITE_KICK。0.45 秒で消える。仕様書 22）。
## 揺れ（drift）と後ずさり（dolly）は呼ぶ側が target に足す。

const T = preload("res://scripts/world/online_staging/online_staging_timeline.gd")

var camera: Camera3D
var follow_lag := 0.0
## 切り替え（cut）の回数。テストがカットの間だけ画の飛びを許すのに使う
var cut_count := 0
## ぼけ：0＝使わない（画質「低」）、1＝奥だけ（「ふつう」）、2＝手前と奥（「高」以上）
var dof_level := 0

var _pos := Vector3.ZERO
var _look := Vector3(0, 0, -1)
var _fov := 40.0
var _roll := 0.0
var _vel_pos := Vector3.ZERO
var _vel_look := Vector3.ZERO
var _vel_fov := 0.0
var _vel_roll := 0.0
var _focus := 10.0
var _vel_focus := 0.0
var _dof := 0.0
var _float := 0.0
var _clock := 0.0
var _from_pos := Vector3.ZERO
var _from_look := Vector3.ZERO
var _from_fov := 40.0
var _from_roll := 0.0
var _blend := 1.0
var _blend_seconds := 0.0
var _target := {}
var _initialized := false
var _attributes: CameraAttributesPractical = null
var _kick := 0.0
var _kick_time := 0.0


func _init(p_camera: Camera3D) -> void:
	camera = p_camera


## ショットをワールドの {pos, look, fov} にする。
static func shot_world(shot: String, frame: Transform3D, offset := Vector3.ZERO) -> Dictionary:
	var cam: Dictionary = OnlineStagingTimeline.camera(shot)
	return {"pos": frame * (cam.pos as Vector3) + offset, "look": frame * (cam.look as Vector3) + offset, "fov": float(cam.fov)}


func cut(shot: String, frame: Transform3D) -> void:
	cut_to(shot_world(shot, frame))


func cut_to(target: Dictionary) -> void:
	_target = target
	_pos = target.pos
	_look = target.look
	_fov = target.fov
	_roll = float(target.get("roll", 0.0))
	_vel_pos = Vector3.ZERO
	_vel_look = Vector3.ZERO
	_vel_fov = 0.0
	_vel_roll = 0.0
	if target.has("focus"):
		_focus = float(target.focus)
		_vel_focus = 0.0
	_dof = float(target.get("dof", 0.0)) if target.has("focus") else 0.0
	# ただよいも切った先の強さから（前のショットの揺れを持ち込まない。据え置きのショットが動かないように）
	_float = clampf(float(target.get("float", 0.0)), 0.0, 1.0)
	_blend = 1.0
	_kick = 0.0
	_initialized = true
	cut_count += 1


## 点火の手ごたえ：短く揺らして消す（strength 0〜1）。
func kick(strength: float = 1.0) -> void:
	_kick = clampf(strength, 0.0, 1.0)
	_kick_time = 0.0


func blend_to(shot: String, frame: Transform3D, seconds: float) -> void:
	blend_to_target(shot_world(shot, frame), seconds)


func blend_to_target(target: Dictionary, seconds: float) -> void:
	_from_pos = _pos
	_from_look = _look
	_from_fov = _fov
	_from_roll = _roll
	_blend_seconds = maxf(seconds, 0.0001)
	_blend = 0.0
	_target = target


## ぼけの段階（0〜2）。Camera3D に CameraAttributesPractical を付け外しする。露出は既定のまま（1.0 倍）。
func set_dof_level(level: int) -> void:
	dof_level = clampi(level, 0, 2)
	if dof_level == 0:
		if camera != null and camera.attributes == _attributes:
			camera.attributes = null
		_attributes = null
		return
	if _attributes == null:
		_attributes = CameraAttributesPractical.new()
		_attributes.dof_blur_far_enabled = false
		_attributes.dof_blur_near_enabled = false
	if camera != null:
		camera.attributes = _attributes
	_apply_dof()


## 毎フレーム：今の目標（動く枠なら毎回作り直したもの）を渡す。
func update(delta: float, target: Dictionary) -> void:
	if not _initialized:
		cut_to(target)
	_target = target
	_clock += delta
	var want_pos: Vector3 = target.pos
	var want_look: Vector3 = target.look
	var want_fov: float = target.fov
	var want_roll := float(target.get("roll", 0.0))
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_seconds)
		var e := ease_in_out_cubic(_blend)
		var before_pos := _pos
		var before_look := _look
		_pos = _from_pos.lerp(want_pos, e)
		_look = _from_look.lerp(want_look, e)
		_fov = lerpf(_from_fov, want_fov, e)
		_roll = lerpf(_from_roll, want_roll, e)
		# つなぎ終わったあとにばねへ戻っても止まらないよう、速さを覚えておく
		if delta > 0.0:
			_vel_pos = (_pos - before_pos) / delta
			_vel_look = (_look - before_look) / delta
	else:
		var lag: Dictionary = target.get("lag", {})
		var r := smooth_damp(_pos, want_pos, _vel_pos, float(lag.get("pos", follow_lag)), delta)
		_pos = r[0]
		_vel_pos = r[1]
		r = smooth_damp(_look, want_look, _vel_look, float(lag.get("look", follow_lag)), delta)
		_look = r[0]
		_vel_look = r[1]
		r = smooth_damp(_fov, want_fov, _vel_fov, float(lag.get("fov", follow_lag)), delta)
		_fov = r[0]
		_vel_fov = r[1]
		r = smooth_damp(_roll, want_roll, _vel_roll, float(lag.get("look", follow_lag)), delta)
		_roll = r[0]
		_vel_roll = r[1]
	if _kick > 0.0:
		_kick_time += delta
		if _kick_time >= float(T.IGNITE_KICK.seconds):
			_kick = 0.0
	# ただよい・ピント・ぼけはつなぎの間もなめらかに変える
	var fade := float(T.CAMERA_RIG.float_fade_seconds)
	_float = move_toward(_float, clampf(float(target.get("float", 0.0)), 0.0, 1.0), delta / maxf(fade, 0.01))
	if target.has("focus"):
		var f := smooth_damp(_focus, float(target.focus), _vel_focus, float(T.CAMERA_RIG.focus_lag), delta)
		_focus = f[0]
		_vel_focus = f[1]
	var want_dof := float(target.get("dof", 0.0)) if target.has("focus") else 0.0
	_dof = move_toward(_dof, want_dof, delta * 0.25)
	apply()


func is_blending() -> bool:
	return _blend < 1.0


func apply(offset := Vector3.ZERO) -> void:
	if camera == null:
		return
	var rig: Dictionary = T.CAMERA_RIG
	var w := _float
	var t := _clock
	# ただよい：周期の合わない低い周波数を重ねる（3〜8 秒）。位置は数 cm、向きは 0.3° まで
	var drift := Vector3(sin(t * 0.83 + 0.4) * 0.6 + sin(t * 1.37 + 2.1) * 0.4,
		sin(t * 1.07 + 1.3) * 0.6 + sin(t * 2.11 + 0.2) * 0.4,
		sin(t * 0.71 + 2.6) * 0.6 + sin(t * 1.61 + 1.0) * 0.4) * float(rig.float_pos_m) * w
	var yaw := deg_to_rad(float(rig.float_yaw_deg)) * w * (sin(t * 0.93 + 0.7) * 0.6 + sin(t * 1.53 + 2.9) * 0.4)
	var pitch := deg_to_rad(float(rig.float_pitch_deg)) * w * (sin(t * 1.19 + 1.9) * 0.6 + sin(t * 2.03 + 0.5) * 0.4)
	var kick_roll := 0.0
	if _kick > 0.0:
		# 点火の揺れ：一度だけ、指数で消える（向き 0.55°・位置 5 cm まで）
		var k: Dictionary = T.IGNITE_KICK
		var fade := _kick * exp(-_kick_time * 9.0) * (1.0 - smoothstep(0.7, 1.0, _kick_time / float(k.seconds)))
		var ph := _kick_time * float(k.rate) * TAU
		yaw += deg_to_rad(float(k.deg)) * fade * sin(ph)
		pitch += deg_to_rad(float(k.deg)) * fade * sin(ph * 1.37 + 1.1)
		kick_roll = deg_to_rad(float(k.deg)) * 0.6 * fade * sin(ph * 0.83 + 2.0)
		drift += Vector3(sin(ph * 1.11), sin(ph * 0.97 + 0.6), 0.0) * float(k.m) * fade
	var p := _pos + offset + drift
	var dir := _look + offset - (_pos + offset)
	if dir.length_squared() < 1e-6:
		return
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	basis = basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, deg_to_rad(_roll) + kick_roll)
	camera.global_transform = Transform3D(basis.orthonormalized(), p)
	camera.fov = _fov
	_apply_dof()


func _apply_dof() -> void:
	if _attributes == null:
		return
	var on := dof_level > 0 and _dof > 0.002
	_attributes.dof_blur_far_enabled = on
	_attributes.dof_blur_near_enabled = on and dof_level >= 2
	if not on:
		return
	var rig: Dictionary = T.CAMERA_RIG
	var f := maxf(_focus, 0.5)
	_attributes.dof_blur_far_distance = f * (1.0 + float(rig.dof_far_start))
	_attributes.dof_blur_far_transition = f * float(rig.dof_far_transition)
	_attributes.dof_blur_near_distance = f * float(rig.dof_near_start)
	_attributes.dof_blur_near_transition = f * float(rig.dof_near_transition)
	_attributes.dof_blur_amount = _dof


func position() -> Vector3:
	return _pos


func look() -> Vector3:
	return _look


func roll() -> float:
	return _roll


func focus() -> float:
	return _focus


func dof_amount() -> float:
	return _dof


static func ease_in_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


## 臨界減衰のばね（Game Programming Gems 4「Critically Damped Ease-In/Ease-Out Smoothing」）。
## 値と速さ（float か Vector3）を [新しい値, 新しい速さ] で返す。smooth_time が 0 なら目標へそのまま（速さは目標の動き）。
static func smooth_damp(current: Variant, target: Variant, velocity: Variant, smooth_time: float, delta: float) -> Array:
	if delta <= 0.0:
		return [current, velocity]
	if smooth_time <= 0.0001:
		return [target, (target - current) / delta]
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: Variant = current - target
	var temp: Variant = (velocity + change * omega) * delta
	return [target + (change + temp) * e, (velocity - temp * omega) * e]
