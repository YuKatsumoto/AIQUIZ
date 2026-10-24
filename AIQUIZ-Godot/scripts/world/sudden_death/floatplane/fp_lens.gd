extends RefCounted

## 水上機の場面のカメラ（docs/sudden_death_v2/c130_float.md 第10・13章：サドンデスの間はカットしない）。
## 場面の頭では、今のカメラ（前の場面の最後の画）から seed 秒かけて寄せる。場面の中の画の移り変わりは、呼ぶ側が目の位置と
## 狙う点をなめらかに動かす（mix・path）。監督へは毎フレーム、決めた姿をそのまま渡す（stage_camera の cut＝true。
## つながりはこちらで保っているので、監督の追いかけの遅れを重ねない）。
##
## カメラの体（第13章）：決めた画（目・狙う点・画角）に、撮る人と機材のふるまいを重ねてから渡す。画の種類ごとの値は
## STYLES（shot の名前で引く）。画が替わるときは値をなめらかに移す（揺れの強さや傾きがパッと変わらない）。
##   手持ち   撮る人の体のゆっくりした揺れ（0.2〜1.5 Hz を重ねた雑音）。望遠ほど構えを固めるので、画角に比例して小さく
##   機体の震え 機体に載ったカメラだけ：プロペラの回転で細かく震え（buzz）、水の上を走ると波を叩いて跳ねる（chop。呼ぶ側が渡す）
##   風圧     機体が近くを通る・開いた後ろの扉の風（rumble。呼ぶ側が毎フレーム 0〜1 を渡す）
##   衝撃     着水・スロープの閉まりなどの一瞬の揺れ（kick。強さの 2 乗で揺れ、指数で消える）
##   傾き     ride：機体に固定したカメラの割合（機体と一緒に傾き、窓の外の水平線が傾く）。bank：外から追うとき、機体の
##            左右の傾きを画面へ写す割合（撮る人が被写体の傾きに合わせて構えを傾ける）
##   ぼけ     ピントは被写体（focus_on で渡した点、なければ狙う点）までの距離。ピント送りは少し遅れて追う。ぼける範囲は
##            本物のレンズ（フルサイズ・F2、焦点距離は画角から）の被写界深度で決める。画質「低」はなし、「ふつう」は奥だけ、
##            「高」以上は手前も
##   余白     動く被写体（track で渡す）の進む側に画面の余白をあける（被写体が画面を横切る速さに合わせて、ゆっくり付ける）
## 露出（機内で目が慣れる）は呼ぶ側が set_exposure で渡し、ぼけと同じ CameraAttributesPractical に当てる。

const QualityRules := preload("res://scripts/core/graphics_quality.gd")

## 画の種類ごとのカメラの体。
##   hand  手持ちの揺れ（度。画角 55° のとき）      pos  手持ちの位置の揺れ（m）
##   buzz  機体の震え（度。プロペラいっぱいのとき）  ride 機体に固定する割合     bank 機体の左右の傾きを写す割合
##   dof   ぼけの強さ（0〜1）                         lead 進む側の余白（画面の横の半分に対する割合）
const STYLES := {
	# 乗り込み：床の上の据え置き → 見上げて追う手持ち → 床の端の望遠（三脚）→ 後ろの高い所から 2 人を追うクレーン
	# → 昇降台と一緒に下りる → 2 人の前を後ろ向きに下がるステディカム → 機内 → 操縦席 → 外へ出て並んで飛ぶ
	"board_lift": {"hand": 0.10, "pos": 0.01},
	"board_flyover": {"hand": 0.55, "pos": 0.03},
	"board_splash": {"hand": 0.22, "pos": 0.01, "dof": 0.10, "lead": 0.28},
	"board_reveal": {"hand": 0.20, "pos": 0.02, "lead": 0.12},
	"board_runners": {"hand": 0.24, "pos": 0.03},
	"board_backin": {"hand": 0.26, "pos": 0.03, "dof": 0.05},
	"board_lead": {"hand": 0.30, "pos": 0.025, "dof": 0.10},
	"board_cabin": {"hand": 0.20, "pos": 0.012, "buzz": 0.05, "ride": 0.85, "dof": 0.12},
	"board_cockpit": {"hand": 0.18, "pos": 0.01, "buzz": 0.07, "ride": 0.9, "dof": 0.06},
	"board_exit": {"hand": 0.22, "pos": 0.02, "buzz": 0.02, "ride": 0.35, "bank": 0.1},
	"board_chase": {"hand": 0.30, "pos": 0.04, "bank": 0.28, "dof": 0.04, "lead": 0.18},
	# 巡航・降下：雲の上を並んで飛ぶ → 窓から入る → 機内（機体に固定）→ 背中を追って外へ（風）
	"cruise_outside": {"hand": 0.32, "pos": 0.05, "bank": 0.3},
	"cruise_enter": {"hand": 0.20, "pos": 0.015, "bank": 0.2, "ride": 0.5},
	"cruise_cabin": {"hand": 0.20, "pos": 0.012, "buzz": 0.05, "ride": 0.85, "dof": 0.12},
	"drop_cabin": {"hand": 0.24, "pos": 0.015, "buzz": 0.05, "ride": 0.85, "dof": 0.12},
	"drop_chase": {"hand": 0.40, "pos": 0.03, "dof": 0.05},
	# 迎え：着地台の横から追う → 機内へ → 機内で離水（窓の外の水平線が傾く）
	"pickup_arrive": {"hand": 0.22, "pos": 0.02, "dof": 0.08, "lead": 0.25},
	"pickup_back": {"hand": 0.26, "pos": 0.025, "dof": 0.05},
	"pickup_lead": {"hand": 0.30, "pos": 0.025, "dof": 0.10},
	"pickup_cabin": {"hand": 0.20, "pos": 0.012, "buzz": 0.05, "ride": 0.85, "dof": 0.12},
	"pickup_ride": {"hand": 0.18, "pos": 0.01, "buzz": 0.07, "ride": 0.9, "dof": 0.06},
	# 帰還：機内 → 勝者の背中 → 飛び降りた勝者を見下ろす（風）
	"home_cockpit": {"hand": 0.18, "pos": 0.01, "buzz": 0.07, "ride": 0.9, "dof": 0.06},
	"home_cabin": {"hand": 0.20, "pos": 0.012, "buzz": 0.05, "ride": 0.85, "dof": 0.12},
	"home_follow": {"hand": 0.26, "pos": 0.015, "buzz": 0.04, "ride": 0.8, "dof": 0.10},
	"home_jump": {"hand": 0.34, "pos": 0.02, "dof": 0.06},
}
const STYLE_KEYS := ["hand", "pos", "buzz", "ride", "bank", "dof", "lead"]
## 画が替わるとき、カメラの体の値が移る時定数（秒）
const STYLE_LAG := 0.55
## 衝撃の揺れ（強さ 1 のとき。度・m）と、消える速さ（1/秒）
const KICK_DEG := 1.1
const KICK_POS := 0.05
const KICK_DECAY := 1.5
## 風圧（rumble 1 のとき）・水を叩く跳ね（chop 1 のとき）の揺れ（度）
const RUMBLE_DEG := 0.42
const CHOP_DEG := 0.38
## 外から追うときの傾き（bank）の遅れ（1/秒）と、余白の付け方の遅れ（秒）
const BANK_RATE := 2.4
const LEAD_LAG := 0.8
## ピント送りの遅れ（秒）
const FOCUS_LAG := 0.22
## ぼけを決めるレンズ：フルサイズの縦（m）・許容錯乱円（m）・絞り
const LENS_SENSOR_H := 0.024
const LENS_COC := 0.00003
const LENS_F_NUMBER := 2.0

var director: HeliSuddenDeathDirector = null
var eye := Vector3.ZERO
var aim := Vector3.FORWARD
var fov := 55.0
## 体を重ねる前の画（入れ替えで運ぶのはこちら。体の揺れは時計で続くので、運んだあともつながる）
var last := Transform3D.IDENTITY
var last_fov := 55.0
var ready := false
## 傾き（ride・bank）の元にする機体
var subject: Node3D = null
## 画質（ぼけの段階を決める）
var quality := "high"
## 呼ぶ側が毎フレーム渡す揺れの元（0〜1）：近くを通る機体・後ろの扉の風（rumble）、水の上を走る跳ね（chop）、プロペラの回転（prop）
var rumble := 0.0
var chop := 0.0
var prop := 0.0
## 今の体の値（STYLES からなめらかに移る）
var style := {}

var _seed_xf := Transform3D.IDENTITY
var _seed_fov := 55.0
var _seed_t := 0.0
var _seed_len := 0.0
## 寄せ始めの画を動かし続ける元（前の場面の画を返す Callable：{"transform", "fov"}）。空なら止めた画から寄せる。
var _seed_src := Callable()
var _seed_offset := Transform3D.IDENTITY
var _seed_fov_offset := 0.0
## 雲の中の入れ替えで運んだ前の画（carry）
var _carry_xf := Transform3D.IDENTITY
var _carry_fov := 55.0
var _carry_t := 0.0
var _carry_len := 0.0
var _carry_fresh := false
var _carry_offset := Transform3D.IDENTITY
var _carry_fov_offset := 0.0
## カメラの体
var _clock := 0.0
var _dt := 0.0
var _noise: FastNoiseLite = null
var _trauma := 0.0
var _bank := 0.0
var _bank_ready := false
var _track_pos := Vector3.ZERO
var _track_vel := Vector3.ZERO
var _tracking := false
var _lead := Vector3.ZERO
var _lead_vel := Vector3.ZERO
var _focus_point := Vector3.ZERO
var _focus_set := false
var _focus := 10.0
var _focus_vel := 0.0
var _optics: CameraAttributesPractical = null
var _exposure := 1.0
## ぼけの強さの倍率（撮っている間は 1。settle で 0 へ）
var _dof_scale := 1.0


func _init(owner: HeliSuddenDeathDirector) -> void:
	director = owner
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 1307
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 2


## 今のカメラから blend 秒かけて寄せ始める（場面の頭）。source（前の場面の画を返す Callable）を渡すと、寄せている間も
## その画の動き（本戦の着地台のまわりを回る画など）を続けたまま寄せる（動いていた画が一度止まらない）。
func seed(blend: float, source := Callable()) -> void:
	var cam := director.main_camera() if director != null else null
	_seed_src = Callable()
	if cam == null or blend <= 0.0:
		_seed_len = 0.0
		return
	_seed_xf = cam.global_transform
	_seed_fov = cam.fov
	_seed_t = 0.0
	_seed_len = blend
	var first := _source_camera(source)
	if not first.is_empty():
		_seed_src = source
		_seed_offset = Transform3D.IDENTITY
		_seed_fov_offset = 0.0
		# 元の画がそのまま映っていた（監督が切って置く画）なら元の画から寄せる。カメラ（前のフレームに置いた姿）とは
		# 1 フレーム分しか違わない。大きく違う（監督が追いかけて寄せていた）ときだけ、そのずれを元の画に付けたまま保つ。
		var src_xf := first.transform as Transform3D
		if src_xf.origin.distance_to(_seed_xf.origin) > 0.3:
			_seed_offset = src_xf.affine_inverse() * _seed_xf
			_seed_fov_offset = _seed_fov - float(first.get("fov", _seed_fov))


func seeding() -> bool:
	return _seed_len > 0.0 and _seed_t < _seed_len


## 雲の中の入れ替え：このフレームに撮った画（last）を入れ替えの写し map で入れ替えた先へ運び、そこから blend 秒かけて
## 新しい場面の画へ寄せる。ずれはカメラから見た向きで持つので、機体と一緒に動く機内の画でも機体に対してずれない。
func carry(map: Transform3D, blend: float) -> void:
	_seed_len = 0.0
	if not ready or blend <= 0.0:
		_carry_len = 0.0
		return
	_carry_xf = map * last
	_carry_fov = last_fov
	_carry_t = 0.0
	_carry_len = blend
	_carry_fresh = true
	# 余白とピントの点も運ぶ（入れ替えの先で付け直さない）
	_lead = map.basis * _lead
	_lead_vel = map.basis * _lead_vel


func advance(delta: float) -> void:
	_seed_t += delta
	_carry_t += delta
	_clock += delta
	_dt = delta


## 一瞬の揺れ（0〜1。重なると足し合わせる）。
func kick(strength: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)


## 動く被写体（余白を付ける）。このフレームだけ有効（毎フレーム渡す）。
func track(position: Vector3, velocity: Vector3) -> void:
	_track_pos = position
	_track_vel = velocity
	_tracking = true


## ピントを合わせる点（このフレームだけ。渡さないときは狙う点）。
func focus_on(point: Vector3) -> void:
	_focus_point = point
	_focus_set = true


## 機内で目が慣れる露出の倍率（1＝そのまま）。
func set_exposure(value: float) -> void:
	_exposure = value
	_apply_optics(true)


## ぼけと露出をカメラから外す（水上機の場面を出るとき）。ぼけの倍率も 0 のままにする（次に撮る shoot_xf で 1 に戻る）。
## 1 に戻すと、本戦の間に毎フレーム呼ぶ settle が外したぼけをまた付けて、ピンぼけが繰り返す。
func release_optics() -> void:
	_exposure = 1.0
	_dof_scale = 0.0
	var cam := director.main_camera() if director != null else null
	if cam != null and _optics != null and cam.attributes == _optics:
		cam.attributes = null


## 撮るのをやめたあと（監督や本戦がカメラを動かしている間）：ぼけと露出を fade 秒でなくしてから外す（急にくっきりしない）。
## もう外れている（Space で飛ばして外した・薄め終えた）ときは何もしない（付け直さない）。
func settle(delta: float, fade := 0.8) -> void:
	var cam := director.main_camera() if director != null else null
	if _optics == null or cam == null or cam.attributes != _optics:
		return
	_dof_scale = move_toward(_dof_scale, 0.0, delta / maxf(fade, 0.01))
	_exposure = move_toward(_exposure, 1.0, delta / maxf(fade, 0.01))
	if _dof_scale <= 0.0 and _exposure >= 0.999:
		release_optics()
		return
	_apply_optics(true)


## 目の位置と狙う点で撮る。
func shoot(p_eye: Vector3, p_aim: Vector3, p_fov: float, shot: String, up := Vector3.UP) -> void:
	_blend_style(shot)
	var target := p_aim + _lead_room(p_eye, p_aim, p_fov)
	eye = p_eye
	aim = target
	shoot_xf(look(p_eye, target, up), p_fov, shot, p_eye.distance_to(p_aim))


## 姿で撮る。focus は狙う点までの距離（ピントを渡されていないとき）。
func shoot_xf(xf: Transform3D, p_fov: float, shot: String, focus := 10.0) -> void:
	_blend_style(shot)
	var out := xf
	var f := p_fov
	var body_w := 1.0
	if seeding():
		var u := _ss5(_seed_t / _seed_len)
		var from := _seed_xf
		var from_fov := _seed_fov
		var live := _source_camera(_seed_src)
		if not live.is_empty():
			from = (live.transform as Transform3D) * _seed_offset
			from_fov = float(live.get("fov", _seed_fov)) + _seed_fov_offset
		out = from.interpolate_with(xf, u)
		f = lerpf(from_fov, p_fov, u)
		# 前の場面の画には体の揺れがない：寄せるのに合わせて揺れを足していく
		body_w = u
	if _carry_len > 0.0 and _carry_t < _carry_len:
		if _carry_fresh:
			_carry_offset = out.affine_inverse() * _carry_xf
			_carry_fov_offset = _carry_fov - f
			_carry_fresh = false
		var w := 1.0 - _ss5(_carry_t / _carry_len)
		out = out * Transform3D.IDENTITY.interpolate_with(_carry_offset, w)
		f += _carry_fov_offset * w
	last = out
	last_fov = f
	ready = true
	var shown := _body(out, f, body_w)
	eye = shown.origin
	fov = f
	_update_focus(_focus_point.distance_to(shown.origin) if _focus_set else focus)
	_focus_set = false
	_tracking = false
	_dof_scale = 1.0
	director.stage_camera(shown, f, shot, true)
	_apply_optics(true)


static func look(p_eye: Vector3, target: Vector3, up := Vector3.UP) -> Transform3D:
	var dir := target - p_eye
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	var u := up
	if absf(dir.normalized().dot(u.normalized())) > 0.995:
		u = Vector3.FORWARD if absf(dir.normalized().y) > 0.9 else Vector3.UP
	return Transform3D(Basis.looking_at(dir, u), p_eye)


## 2 つの画（{eye, aim, fov}）を w でまぜる。目と狙う点を別々にまぜるので、回る途中で傾かない。
static func mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var k := clampf(w, 0.0, 1.0)
	return {"eye": (a.eye as Vector3).lerp(b.eye, k), "aim": (a.aim as Vector3).lerp(b.aim, k), "fov": lerpf(float(a.fov), float(b.fov), k)}


## Catmull-Rom の道すじ（点の列）の u（0〜1）の点。
static func path(points: Array, u: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return points[0]
	var x := clampf(u, 0.0, 1.0) * float(n - 1)
	var i := mini(int(x), n - 2)
	var f := x - float(i)
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, n - 1)]
	var f2 := f * f
	var f3 := f2 * f
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)


# ---------- カメラの体 ----------

## 画の種類の値へなめらかに移る（1 フレームに 1 回だけ進める）。
func _blend_style(shot: String) -> void:
	var want: Dictionary = STYLES.get(shot, {})
	if style.is_empty() or not ready:
		for key: String in STYLE_KEYS:
			style[key] = float(want.get(key, 0.0))
		return
	if _dt <= 0.0 or style.get("_clock", -1.0) == _clock:
		return
	style["_clock"] = _clock
	var k := 1.0 - exp(-_dt / STYLE_LAG)
	for key: String in STYLE_KEYS:
		style[key] = lerpf(float(style.get(key, 0.0)), float(want.get(key, 0.0)), k)


## 進む側の余白：被写体が画面を横切る速さ（角速度）に合わせて、狙う点を進む向きへずらす（ばねでゆっくり）。
func _lead_room(p_eye: Vector3, p_aim: Vector3, p_fov: float) -> Vector3:
	var want := Vector3.ZERO
	var amount := float(style.get("lead", 0.0))
	if _tracking and amount > 0.001:
		var dir := (p_aim - p_eye).normalized()
		var dist := maxf(p_eye.distance_to(_track_pos), 1.0)
		var across := _track_vel - dir * _track_vel.dot(dir)
		var omega := across.length() / dist
		var half_w := dist * tan(deg_to_rad(p_fov) * 0.5) * _aspect()
		if across.length() > 0.01:
			want = across.normalized() * half_w * amount * smoothstep(0.02, 0.22, omega)
	if _dt <= 0.0:
		return _lead
	var r := _smooth_damp_v(_lead, want, _lead_vel, LEAD_LAG, _dt)
	_lead = r[0]
	_lead_vel = r[1]
	return _lead


## 撮る人と機材のふるまいを重ねる（w は重ねる強さ。場面の頭で前の画から寄せる間は 0 から）。
func _body(xf: Transform3D, f: float, w: float) -> Transform3D:
	var basis := xf.basis.orthonormalized()
	var fwd := -basis.z
	var t := _clock
	# 傾き：機体に固定（ride）は機体の上の向きそのまま、外から追う（bank）は機体の左右の傾きだけを遅れて写す
	var ride := float(style.get("ride", 0.0))
	var bank := float(style.get("bank", 0.0))
	var up := Vector3.UP
	if subject != null and is_instance_valid(subject) and subject.is_inside_tree() and (ride > 0.001 or bank > 0.001):
		var pb := subject.global_transform.basis.orthonormalized()
		var nose := Vector3(-pb.z.x, 0.0, -pb.z.z)
		var phi := asin(clampf(-pb.x.y, -1.0, 1.0))
		if not _bank_ready or _dt <= 0.0:
			_bank = phi if not _bank_ready else _bank
			_bank_ready = true
		else:
			_bank = lerp_angle(_bank, phi, 1.0 - exp(-BANK_RATE * _dt))
		var banked := Vector3.UP
		if nose.length() > 0.01:
			var right := nose.normalized().cross(Vector3.UP).normalized()
			banked = (Vector3.UP * cos(_bank) + right * sin(_bank)).normalized()
		up = (Vector3.UP * maxf(0.0, 1.0 - ride - bank) + pb.y * ride + banked * bank).normalized()
	var roll := 0.0
	var a := Vector3.UP - fwd * fwd.dot(Vector3.UP)
	var b := up - fwd * fwd.dot(up)
	if a.length() > 0.05 and b.length() > 0.05:
		a = a.normalized()
		b = b.normalized()
		roll = atan2(fwd.dot(a.cross(b)), a.dot(b)) * (1.0 - smoothstep(0.9, 0.98, absf(fwd.y)))
	# 揺れ：手持ち（ゆっくり）・機体の震え（細かい）・水を叩く跳ね・風圧・衝撃
	var tele := clampf(f / 55.0, 0.3, 1.2)
	var hand := deg_to_rad(float(style.get("hand", 0.0))) * tele
	var yaw := hand * _n(t * 0.55, 0.0)
	var pitch := hand * 0.8 * _n(t * 0.47, 1.0)
	var twist := hand * 0.45 * _n(t * 0.38, 2.0)
	var pos_amp := float(style.get("pos", 0.0))
	var offset := Vector3(_n(t * 0.42, 3.0), _n(t * 0.5, 4.0), _n(t * 0.33, 5.0) * 0.6) * pos_amp
	var buzz := deg_to_rad(float(style.get("buzz", 0.0))) * clampf(prop, 0.0, 1.0)
	yaw += buzz * _n(t * 17.0, 6.0)
	pitch += buzz * _n(t * 21.0, 7.0)
	var bump := deg_to_rad(CHOP_DEG) * clampf(chop, 0.0, 1.0) * clampf(float(style.get("ride", 0.0)) + 0.2, 0.0, 1.0)
	pitch += bump * _n(t * 5.5, 8.0)
	twist += bump * 0.6 * _n(t * 4.3, 9.0)
	offset.y += 0.02 * clampf(chop, 0.0, 1.0) * _n(t * 6.0, 10.0)
	var gust := deg_to_rad(RUMBLE_DEG) * clampf(rumble, 0.0, 1.0)
	yaw += gust * _n(t * 11.0, 11.0)
	pitch += gust * _n(t * 13.0, 12.0)
	twist += gust * 0.5 * _n(t * 9.0, 13.0)
	offset += Vector3(_n(t * 10.0, 14.0), _n(t * 12.0, 15.0), 0.0) * 0.015 * clampf(rumble, 0.0, 1.0)
	if _trauma > 0.0:
		var shake := _trauma * _trauma
		yaw += deg_to_rad(KICK_DEG) * shake * _n(t * 15.0, 16.0)
		pitch += deg_to_rad(KICK_DEG) * shake * _n(t * 17.0, 17.0)
		twist += deg_to_rad(KICK_DEG) * 0.6 * shake * _n(t * 13.0, 18.0)
		offset += Vector3(_n(t * 14.0, 19.0), _n(t * 16.0, 20.0), 0.0) * KICK_POS * shake
		_trauma = maxf(0.0, _trauma - KICK_DECAY * _dt)
	var k := clampf(w, 0.0, 1.0)
	var shaken := basis * Basis(Vector3(0, 0, 1), -roll * k) * Basis(Vector3.UP, yaw * k) * Basis(Vector3.RIGHT, pitch * k) \
		* Basis(Vector3(0, 0, 1), twist * k)
	return Transform3D(shaken.orthonormalized(), xf.origin + basis * (offset * k))


## なめらかな雑音（−1〜1 くらい）。channel ごとに別の列。
func _n(x: float, channel: float) -> float:
	return clampf(_noise.get_noise_2d(x, channel * 31.7) * 1.6, -1.0, 1.0)


# ---------- ぼけと露出 ----------

func _update_focus(distance: float) -> void:
	var d := clampf(distance, 0.4, 2000.0)
	if _dt <= 0.0:
		_focus = d
		_focus_vel = 0.0
		return
	var r := _smooth_damp_f(_focus, d, _focus_vel, FOCUS_LAG, _dt)
	_focus = r[0]
	_focus_vel = r[1]


func _dof_level() -> int:
	match QualityRules.normalize(quality):
		QualityRules.LOW:
			return 0
		QualityRules.BALANCED:
			return 1
	return 2


## ぼけ（望遠ほど浅い）と露出を、監督のカメラの CameraAttributesPractical に当てる。どちらも要らないときは外す。
## ほかの誰かがカメラに付けた設定があるときは触らない。まだ撮っていない（ready でない）ときはぼかさない。
func _apply_optics(with_dof: bool) -> void:
	var cam := director.main_camera() if director != null else null
	if cam == null:
		return
	var amount := float(style.get("dof", 0.0)) * _dof_scale if with_dof and ready else 0.0
	var level := _dof_level()
	var dof_on := level > 0 and amount > 0.004
	if not dof_on and _exposure >= 0.999:
		if _optics != null and cam.attributes == _optics:
			cam.attributes = null
		return
	if _optics == null:
		_optics = CameraAttributesPractical.new()
	if cam.attributes != _optics:
		if cam.attributes != null:
			return
		cam.attributes = _optics
	_optics.exposure_multiplier = _exposure
	_optics.dof_blur_near_enabled = dof_on and level >= 2
	if not dof_on:
		_optics.dof_blur_far_enabled = false
		return
	# 本物のレンズの被写界深度（フルサイズ・F2）：焦点距離は画角から。過焦点距離 H より遠くにピントがあれば奥はぼけない
	# （遠くの被写体を望遠で撮ってもミニチュアのようにならない）。手前は近いほど、奥は遠いほどぼける。
	var focal := LENS_SENSOR_H * 0.5 / tan(deg_to_rad(fov) * 0.5)
	var hyper := focal * focal / (LENS_F_NUMBER * LENS_COC)
	var d := _focus
	var near := hyper * d / (hyper + d)
	_optics.dof_blur_near_distance = near
	_optics.dof_blur_near_transition = near * 0.5
	_optics.dof_blur_far_enabled = d < hyper * 0.95
	if _optics.dof_blur_far_enabled:
		var far := hyper * d / (hyper - d)
		_optics.dof_blur_far_distance = far
		_optics.dof_blur_far_transition = far
	_optics.dof_blur_amount = clampf(amount, 0.0, 0.3)


func _aspect() -> float:
	var cam := director.main_camera() if director != null else null
	var vp := cam.get_viewport() if cam != null and cam.is_inside_tree() else null
	if vp == null:
		return 16.0 / 9.0
	var size := vp.get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


static func _smooth_damp_v(current: Vector3, target: Vector3, velocity: Vector3, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + change * omega) * delta
	return [target + (change + temp) * e, (velocity - temp * omega) * e]


static func _smooth_damp_f(current: float, target: float, velocity: float, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + change * omega) * delta
	return [target + (change + temp) * e, (velocity - temp * omega) * e]


static func _source_camera(source: Callable) -> Dictionary:
	if not source.is_valid():
		return {}
	var got: Variant = source.call()
	if not (got is Dictionary) or not (got as Dictionary).has("transform"):
		return {}
	return got


static func _ss5(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
