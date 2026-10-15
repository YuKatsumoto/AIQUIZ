class_name StagingShots
extends RefCounted

## 乗り込み〜検索中（S1〜S5）と合流（S6）のカメラワーク（仕様書 21・22）。状態の時刻から、カメラの目標
## {pos, look, fov, roll, lag, float, focus, dof, name} を作る。カメラを置くのは StagingCameraRig、いつ呼ぶかは監督。
## 値はすべて OnlineStagingTimeline（MOVE_*・CRUISE_SEQUENCE・SUBJECTS・CAMERA_RIG）。
##   ・位置はキーの間を時刻で通る 3 次の曲線（Catmull-Rom の傾き。速さが途切れない）
##   ・注視は compose：被写体を画面の決めた位置に置く向きを解く（3 分割・進む向きの前を空ける）
##   ・検索中のショットのつなぎは、機体のまわりを球面で回り込む（機体やローターを突き抜けない）

const T = preload("res://scripts/world/online_staging/online_staging_timeline.gd")


# ---------- S1 乗り込み ----------

## t：乗り込みの時刻（秒）。ground：パッドのヘリの H。idle：待機のカメラ（揺れ込み、ワールド）。subject：キャラの体の中心。
static func board(t: float, ground: Transform3D, idle: Dictionary, subject: Vector3, aspect: float) -> Dictionary:
	var m: Dictionary = T.MOVE_BOARD
	var keys: Array = [[0.0, idle.pos]]
	for key: Array in m.pos:
		keys.append([float(key[0]), ground * (key[1] as Vector3)])
	var pos: Vector3 = sample(keys, t, true)
	var fov := float(sample(m.fov, t))
	var screen: Vector2 = sample(m.screen, t)
	var aim_in: Array = m.aim_in
	var w := smoothstep(float(aim_in[0]), float(aim_in[1]), t)
	var tracked := compose(pos, subject, screen, fov, aspect)
	var look: Vector3 = (idle.look as Vector3).lerp(tracked, w)
	return {"name": "MV_Board", "pos": pos, "look": look, "fov": fov,
		"lag": {"look": float(m.lag_look) * w}, "float": float(m.float),
		"focus": pos.distance_to(subject), "dof": float(m.dof)}


# ---------- S2 操縦席 ----------

## u：操縦席の進み（0〜1）。heli：自分のヘリのワールドの Transform3D。
static func cockpit(u: float, ground: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	return _move(T.MOVE_COCKPIT, "MV_Cockpit", u, ground, heli, aspect)


# ---------- S3 離陸 ----------

## u：離陸の進み（0〜1）。
static func takeoff(u: float, ground: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	return _move(T.MOVE_TAKEOFF, "MV_Takeoff", u, ground, heli, aspect)


# ---------- S4 ジェットブーストの急発進 ----------

## u：CLIMB の進み（0〜1）。カメラはパッドの上にとどまり、向きとズームで飛び去るヘリを追う。
static func boost(u: float, ground: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	return _move(T.MOVE_BOOST, "MV_Boost", u, ground, heli, aspect)


# ---------- S6 合流 ----------

## u：JOIN の進み（0〜1）。frame：揺れない枠。注視は枠の中の動かない点なので、相手のヘリは画面の外から入ってくる。
static func join(u: float, frame: Transform3D, aspect: float) -> Dictionary:
	var m: Dictionary = T.MOVE_JOIN
	var keys: Array = []
	for key: Array in m.pos:
		keys.append([float(key[0]), frame * (key[1] as Vector3)])
	var pos: Vector3 = sample(keys, u)
	var fov := float(sample(m.fov, u))
	var subject := frame * (sample(m.aim_points, u) as Vector3)
	var look := compose(pos, subject, sample(m.screen, u), fov, aspect)
	return {"name": "MV_Join", "pos": pos, "look": look, "fov": fov, "lag": {"look": float(m.lag_look)},
		"float": float(m.float), "focus": pos.distance_to(subject), "dof": float(m.dof)}


## キーが進み（0〜1）で書いてある動き。frame はキーの位置の基準。
static func _move(m: Dictionary, name: String, u: float, frame: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	var keys: Array = []
	for key: Array in m.pos:
		keys.append([float(key[0]), frame * (key[1] as Vector3)])
	var pos: Vector3 = sample(keys, u)
	var fov := float(sample(m.fov, u))
	var subject := heli * (T.SUBJECTS[m.aim] as Vector3)
	var look := compose(pos, subject, sample(m.screen, u), fov, aspect)
	return {"name": name, "pos": pos, "look": look, "fov": fov, "lag": {"look": float(m.lag_look)},
		"float": float(m.float), "focus": pos.distance_to(subject), "dof": float(m.dof)}


# ---------- S5 検索中 ----------

## time：検索中に入ってからの秒。frame：揺れない枠。heli：揺れを含む自分のヘリ（ワールド）。
## 返す辞書には、今のショットの番号 index と、そのショットへ切り替えるときに切るか（cut）も入る。
static func cruise(time: float, frame: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	var seq: Array = T.CRUISE_SEQUENCE
	var period := float(T.CRUISE_SHOT_SECONDS)
	var blend := float(T.CRUISE_BLEND_SECONDS)
	var k := int(floor(maxf(time, 0.0) / period))
	var within := time - float(k) * period
	var a: Dictionary = seq[k % seq.size()]
	var b: Dictionary = seq[(k + 1) % seq.size()]
	# a は前のショットから回り込んで来た（最初のショットと、切って入ったショットは 0 秒から）
	var a_in := 0.0 if k == 0 or bool(a.get("cut", false)) else blend
	var shot_a := _cruise_shot(a, (within + a_in) / (period + a_in), frame, heli, aspect)
	var out := shot_a
	if within > period - blend and not bool(b.get("cut", false)):
		var e := smootherstep((within - (period - blend)) / blend)
		var shot_b := _cruise_shot(b, (within - (period - blend)) / (period + blend), frame, heli, aspect)
		out = _arc_blend(shot_a, shot_b, e, heli * (T.SUBJECTS.heli as Vector3), aspect)
		out["name"] = "%s→%s" % [a.name, b.name]
	out["index"] = k
	out["cut"] = bool(a.get("cut", false)) and k > 0
	out["lag"] = {"look": float(T.CRUISE_LAG_LOOK)}
	out["float"] = 1.0
	# 機体の横揺れにつられて画面を傾ける（カメラの向きと機首の向きがそろうほど同じ向きに）
	var heli_roll := asin(clampf(-heli.basis.x.normalized().dot(frame.basis.y.normalized()), -1.0, 1.0))
	var cam_forward := ((out.look as Vector3) - (out.pos as Vector3)).normalized()
	var nose := -heli.basis.z.normalized()
	out["roll"] = rad_to_deg(heli_roll) * float(out.bank) * cam_forward.dot(nose)
	return out


## 1 本のショット：s は見えている間の進み（0〜1。一定の速さで from → to）。
static func _cruise_shot(shot: Dictionary, s: float, frame: Transform3D, heli: Transform3D, aspect: float) -> Dictionary:
	var u := clampf(s, 0.0, 1.0)
	var pos := frame * (shot.from as Vector3).lerp(shot.to, u)
	var fovs: Array = shot.fov
	var fov := lerpf(float(fovs[0]), float(fovs[1]), u)
	var subject := heli * (T.SUBJECTS[shot.get("aim", "heli")] as Vector3)
	var screen: Vector2 = shot.screen
	return {"name": shot.name, "pos": pos, "subject": subject, "screen": screen, "fov": fov,
		"look": compose(pos, subject, screen, fov, aspect), "bank": float(shot.get("bank", 0.0)),
		"focus": pos.distance_to(subject), "dof": float(shot.get("dof", 0.0))}


## 2 つのショットのあいだ：カメラは機体の中心（pivot）のまわりを球面で回り込み（距離もなめらかに変える）、
## 注視は被写体と画面の位置をまぜてから解き直す。
static func _arc_blend(a: Dictionary, b: Dictionary, e: float, pivot: Vector3, aspect: float) -> Dictionary:
	var pos := pivot + ((a.pos as Vector3) - pivot).slerp((b.pos as Vector3) - pivot, e)
	var fov := lerpf(float(a.fov), float(b.fov), e)
	var subject := (a.subject as Vector3).lerp(b.subject, e)
	var screen := (a.screen as Vector2).lerp(b.screen, e)
	return {"pos": pos, "subject": subject, "screen": screen, "fov": fov, "look": compose(pos, subject, screen, fov, aspect),
		"bank": lerpf(float(a.bank), float(b.bank), e), "focus": pos.distance_to(subject), "dof": lerpf(float(a.dof), float(b.dof), e)}


# ---------- 道具 ----------

## 被写体 subject が画面の screen（-1〜1、右と上が正。縦の画角 fov、横/縦 aspect）に来るように向いたときの注視点。
## 横の振りは真上のまわり、縦の振りはカメラの右のまわり（傾きなし）。3 回で 0.1% 以下に収まる。
static func compose(cam_pos: Vector3, subject: Vector3, screen: Vector2, fov: float, aspect: float) -> Vector3:
	var to := subject - cam_pos
	var dist := to.length()
	if dist < 0.001:
		return subject
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * maxf(aspect, 0.1)
	var dir := to / dist
	for i: int in range(3):
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		var basis := Basis.looking_at(dir, up)
		var local := basis.inverse() * to
		var depth := maxf(-local.z, 0.001)
		var now := Vector2(local.x / (depth * tan_h), local.y / (depth * tan_v))
		var yaw := atan(screen.x * tan_h) - atan(now.x * tan_h)
		var pitch := atan(screen.y * tan_v) - atan(now.y * tan_v)
		# 左へ振る（真上のまわりに正）と被写体は右へ、下へ振る（右のまわりに負）と被写体は上へ動く
		dir = dir.rotated(Vector3.UP, yaw)
		var right := dir.cross(Vector3.UP)
		if right.length_squared() > 1e-6:
			dir = dir.rotated(right.normalized(), -pitch)
		dir = dir.normalized()
	return cam_pos + dir * dist


## キー [[時刻, 値], ...]（値は float / Vector2 / Vector3）を時刻 t で通す 3 次の曲線（エルミート、Catmull-Rom の傾き）。
## ease_in なら最初の点で止まった状態から動き出す。ほかの端は隣の点への傾きのまま（動きの途中で切れる）。
static func sample(keys: Array, t: float, ease_in: bool = false) -> Variant:
	var n := keys.size()
	if n == 0:
		return 0.0
	if n == 1 or t <= float(keys[0][0]):
		return keys[0][1]
	if t >= float(keys[n - 1][0]):
		return keys[n - 1][1]
	var i := 0
	while i < n - 2 and t > float(keys[i + 1][0]):
		i += 1
	var t0 := float(keys[i][0])
	var t1 := float(keys[i + 1][0])
	var h := maxf(t1 - t0, 0.0001)
	var s := (t - t0) / h
	var p0: Variant = keys[i][1]
	var p1: Variant = keys[i + 1][1]
	var m0: Variant = _tangent(keys, i, ease_in)
	var m1: Variant = _tangent(keys, i + 1, ease_in)
	var s2 := s * s
	var s3 := s2 * s
	return p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (h * (s3 - 2.0 * s2 + s)) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (h * (s3 - s2))


## 点 i の傾き（値/秒）：前後の点を結ぶ向き。端は隣の点へ（ease_in の最初の点は 0）。
static func _tangent(keys: Array, i: int, ease_in: bool) -> Variant:
	var n := keys.size()
	var p: Variant = keys[i][1]
	if i == 0:
		if ease_in:
			return p * 0.0
		return (keys[1][1] - p) / maxf(float(keys[1][0]) - float(keys[0][0]), 0.0001)
	if i == n - 1:
		return (p - keys[i - 1][1]) / maxf(float(keys[i][0]) - float(keys[i - 1][0]), 0.0001)
	return (keys[i + 1][1] - keys[i - 1][1]) / maxf(float(keys[i + 1][0]) - float(keys[i - 1][0]), 0.0001)


## 5 次のなめらかな加減速（つなぎの始まりと終わりで加速度も 0）。
static func smootherstep(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
