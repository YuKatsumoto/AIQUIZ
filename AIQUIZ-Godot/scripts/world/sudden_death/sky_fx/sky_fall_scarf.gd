class_name SkyFallScarf
extends Node3D

## スカイゲートのマフラー（docs/sudden_death_v2/sky_fx.md 第1・3章、約束は skygate_build_plan.md 4.8 節）。
## P1 はオレンジ（赤み）、P2 は青。サドンデスの間だけ。首に巻いた輪（首の部位の子）と、背中の結び目から出る 2 本の端。
## 端は骨（つながった点の列）で揺らす：点ごとに空気の流れに引かれ（落ちている間は空気が下から上へ流れる）、
## 列に沿って進む波（はためき）を足し、長さを保つ（Verlet）。体の中には入らない（背骨のまわりの筒から押し出す）。
## 人形（EmoteBlockmanPreview.build_player_skeleton の parts）と本物のアバター（StagingPuppet.parts()）は同じ部位の形なので、
## どちらも attach_doll の中身は同じ。
##
## 使い方：var scarf := SkyFallScarf.new(); parent.add_child(scarf); scarf.attach_doll(parts, 1)
##   落ちていないとき（着地台の上など）は air_velocity を小さく（重さで垂れる）。スローは time_scale。
##   自分で進める（スローを細かく合わせる）なら auto_advance = false にして advance(delta)。

const SCARF_SHADER := preload("res://shaders/sky_fx_scarf.gdshader")
const P1_COLOR := Color("#F0562A")
const P2_COLOR := Color("#2C62D8")
const STRIPE_COLOR := Color("#FBF3DE")
## 端の点の数・1 つの長さ（m）・幅（m）。2 本で少し長さを変える。
const POINTS := 10
const TAIL_SEG := [0.125, 0.105]
const TAIL_WIDTH := [0.25, 0.22]
## 輪：頭の箱のまわりの余白、太さ（横・縦）
const RING_GAP := 0.035
const RING_THICK := 0.075
const RING_HEIGHT := 0.085
const SUBSTEP := 1.0 / 120.0
const DRAG := 7.0
const GRAVITY := Vector3(0.0, -9.8, 0.0)

## 体に対する空気の流れ（ワールド、m/秒）。落ちている間は上向き。
var air_velocity := Vector3(0.0, 30.0, 0.0)
## 体の後ろ（足の側）へ流す空気の速さ（m/秒）。腹ばいで見下ろしたとき、マフラーが背中の上を後ろへなびく。
var trail_back := 22.0
## はためきの強さ（SkyFallScenery.set_wind と同じ 0〜1.4）。
var wind := 1.0
var time_scale := 1.0
var auto_advance := true
var player := 1

var _parts := {}
var _ring: MeshInstance3D = null
var _tails_node: MeshInstance3D = null
var _tails_mesh: ImmediateMesh = null
var _tail_mat: ShaderMaterial = null
var _ring_mat: ShaderMaterial = null
var _anchor_local := Vector3.ZERO
## 2 本の端：点の位置と前の位置（ワールド）
var _pts: Array[PackedVector3Array] = []
var _prev: Array[PackedVector3Array] = []
var _acc := 0.0
var _time := 0.0
var _attached := false
## 前の 1 歩の結び目（大きく飛んだら＝人形が瞬間移動したら、布を結び目へ引き寄せ直す）。
var _last_anchor := Vector3.INF
## これより遠くへ 1 歩で動いたら瞬間移動とみなす（m）。
const SNAP_DISTANCE := 3.0


func attach_doll(parts: Dictionary, p_player: int) -> void:
	detach()
	_parts = parts
	player = p_player
	var neck := parts.get("neck") as Node3D
	if neck == null:
		push_warning("SkyFallScarf: 首（neck）がない")
		return
	var col := P1_COLOR if player == 1 else P2_COLOR
	_ring_mat = _material(col, false)
	_tail_mat = _material(col, true)
	var half := _head_half(parts)
	_ring = MeshInstance3D.new()
	_ring.name = "ScarfRing_P%d" % player
	_ring.mesh = _ring_mesh(half)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neck.add_child(_ring)
	_ring.position = Vector3(0.0, 0.035, 0.0)
	# 結び目：背中（−Z）の少し右
	_anchor_local = Vector3(half.x * 0.38, 0.035, -(half.y + RING_GAP + RING_THICK * 0.8))
	_tails_mesh = ImmediateMesh.new()
	_tails_node = MeshInstance3D.new()
	_tails_node.name = "ScarfTails_P%d" % player
	_tails_node.mesh = _tails_mesh
	_tails_node.material_override = _tail_mat
	_tails_node.top_level = true
	_tails_node.extra_cull_margin = 8.0
	_tails_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tails_node)
	_pts.clear()
	_prev.clear()
	var anchor := neck.global_transform * _anchor_local
	var back := -neck.global_basis.z.normalized()
	for k in range(2):
		var p := PackedVector3Array()
		p.resize(POINTS)
		for i in range(POINTS):
			p[i] = anchor + (back * 0.6 + Vector3.UP * 0.4).normalized() * float(TAIL_SEG[k]) * i + neck.global_basis.x * (0.04 * (k * 2 - 1)) * i * 0.2
		_pts.append(p)
		_prev.append(p.duplicate())
	_attached = true


func attach_puppet(puppet: StagingPuppet, p_player: int) -> void:
	if puppet == null or not puppet.is_ready():
		return
	attach_doll(puppet.parts(), p_player)


func detach() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	if _tails_node != null and is_instance_valid(_tails_node):
		_tails_node.queue_free()
	_ring = null
	_tails_node = null
	_tails_mesh = null
	_parts = {}
	_attached = false


## 布を今の結び目から後ろへまっすぐ垂らした形に戻す（速さも 0 に）。
func snap() -> void:
	var neck := _parts.get("neck") as Node3D
	if neck == null or not is_instance_valid(neck) or not neck.is_inside_tree() or _pts.size() < 2:
		return
	var anchor := neck.global_transform * _anchor_local
	var back := -neck.global_basis.z.normalized()
	for k in range(2):
		var line := PackedVector3Array()
		line.resize(POINTS)
		for i in range(POINTS):
			line[i] = anchor + (back * 0.6 + Vector3.UP * 0.4).normalized() * float(TAIL_SEG[k]) * i + neck.global_basis.x * (0.04 * (k * 2 - 1)) * i * 0.2
		_pts[k] = line
		_prev[k] = line.duplicate()
	_last_anchor = anchor


func is_attached() -> bool:
	return _attached


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta * time_scale)


func advance(delta: float) -> void:
	if not _attached:
		return
	var neck := _parts.get("neck") as Node3D
	if neck == null or not is_instance_valid(neck) or not neck.is_inside_tree():
		return
	_tails_node.visible = neck.is_visible_in_tree()
	if not _tails_node.visible:
		return
	# 人形が瞬間移動したとき（ラウンドの頭・降下からの入れ替え・着地の画へのカット）、布が前の場所から長く伸びないように
	var anchor_now := neck.global_transform * _anchor_local
	if not is_finite(_last_anchor.x) or anchor_now.distance_to(_last_anchor) > SNAP_DISTANCE:
		snap()
	_last_anchor = anchor_now
	_acc = minf(_acc + delta, SUBSTEP * 6.0)
	while _acc >= SUBSTEP:
		_acc -= SUBSTEP
		_time += SUBSTEP
		_step(neck, SUBSTEP)
	_rebuild_mesh(neck)


func _step(neck: Node3D, h: float) -> void:
	var anchor := neck.global_transform * _anchor_local
	var nb := neck.global_basis.orthonormalized()
	var back := -nb.z
	var spine := _parts.get("spine") as Node3D
	var pelvis := _parts.get("pelvis") as Node3D
	var seg_a := pelvis.global_position if pelvis != null else anchor - nb.y
	var seg_b := neck.global_position + nb.y * 0.25
	var w := clampf(wind, 0.0, 1.4)
	var air := air_velocity * (0.65 + 0.35 * w) - nb.y * trail_back * (0.6 + 0.4 * w)
	var speed := air.length()
	for k in range(2):
		var p := _pts[k]
		var q := _prev[k]
		var seg := float(TAIL_SEG[k])
		var phase := 0.0 if k == 0 else 1.9
		for i in range(1, POINTS):
			var t := float(i) / float(POINTS - 1)
			var vel := (p[i] - q[i]) / h
			var dir := (p[i] - p[i - 1]).normalized()
			var side := dir.cross(nb.y).normalized() if absf(dir.dot(nb.y)) < 0.98 else nb.x
			var normal := side.cross(dir).normalized()
			# はためき：根元から先へ進む波。先ほど大きい
			var wave := sin(_time * (15.0 + 2.5 * k) - float(i) * 0.95 + phase)
			var wave2 := sin(_time * (9.5 - 1.5 * k) - float(i) * 0.6 + phase * 1.7)
			var sway := sin(_time * 2.3 + phase * 2.0) * 0.6 + (0.35 if k == 0 else -0.35)
			var flutter := (normal * wave * 1.0 + side * (wave2 * 0.5 + sway)) * speed * (0.55 + 0.45 * w) * t * 3.0
			var acc := GRAVITY + (air - vel) * DRAG + flutter
			var np := p[i] + (p[i] - q[i]) * 0.985 + acc * h * h
			q[i] = p[i]
			p[i] = np
		p[0] = anchor
		q[0] = anchor
		for _iter in range(3):
			# 根元は結び目から背中の向きへ出る（最初の 1 つは向きも寄せる）
			var first := anchor + (back * 0.55 + nb.y * 0.15 + (p[1] - anchor).normalized() * 0.6).normalized() * seg
			p[1] = p[1].lerp(first, 0.5)
			for i in range(1, POINTS):
				var d := p[i] - p[i - 1]
				var l := d.length()
				if l > 1e-6:
					var corr := d * ((l - seg) / l)
					if i == 1:
						p[i] -= corr
					else:
						p[i - 1] += corr * 0.35
						p[i] -= corr * 0.65
			p[0] = anchor
			# 体の中に入らない：背骨（腰〜首）のまわりの筒から外へ
			if spine != null:
				for i in range(1, POINTS):
					var pt := p[i]
					var ab := seg_b - seg_a
					var tt := clampf((pt - seg_a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var closest := seg_a + ab * tt
					var off := pt - closest
					var dist := off.length()
					var r := 0.36
					if dist < r and dist > 1e-5:
						p[i] = closest + off / dist * r
		_pts[k] = p
		_prev[k] = q


func _rebuild_mesh(neck: Node3D) -> void:
	_tails_mesh.clear_surfaces()
	_tails_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var nb := neck.global_basis.orthonormalized()
	for k in range(2):
		var src := _pts[k]
		# 点の列をなめらかに 2 倍に（Catmull-Rom）
		var pts := PackedVector3Array()
		for i in range(POINTS - 1):
			var p0 := src[maxi(i - 1, 0)]
			var p1 := src[i]
			var p2 := src[i + 1]
			var p3 := src[mini(i + 2, POINTS - 1)]
			pts.append(p1)
			pts.append(_catmull(p0, p1, p2, p3, 0.5))
		pts.append(src[POINTS - 1])
		var n := pts.size()
		var width := float(TAIL_WIDTH[k])
		var ref := nb.y
		var prev_side := nb.x
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		left.resize(n)
		right.resize(n)
		for i in range(n):
			var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var side := dir.cross(ref)
			if side.length() < 1e-3:
				side = prev_side
			side = side.normalized()
			if side.dot(prev_side) < 0.0:
				side = -side
			prev_side = side
			ref = dir.cross(side).normalized() * -1.0
			var t := float(i) / float(n - 1)
			var w := width * (0.82 + 0.18 * t)
			left[i] = pts[i] - side * w * 0.5
			right[i] = pts[i] + side * w * 0.5
		for i in range(n - 1):
			var v0 := float(i) / float(n - 1)
			var v1 := float(i + 1) / float(n - 1)
			var nrm := (right[i] - left[i]).cross(pts[i + 1] - pts[i]).normalized()
			for v: Array in [[left[i], 0.0, v0], [right[i], 1.0, v0], [right[i + 1], 1.0, v1],
					[left[i], 0.0, v0], [right[i + 1], 1.0, v1], [left[i + 1], 0.0, v1]]:
				_tails_mesh.surface_set_normal(nrm)
				_tails_mesh.surface_set_uv(Vector2(float(v[1]), float(v[2])))
				_tails_mesh.surface_add_vertex(v[0] as Vector3)
	_tails_mesh.surface_end()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _material(col: Color, tail: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SCARF_SHADER
	mat.set_shader_parameter("base_color", col)
	mat.set_shader_parameter("stripe_color", STRIPE_COLOR)
	mat.set_shader_parameter("is_tail", tail)
	mat.set_shader_parameter("ribs", 5.0 if tail else 3.0)
	mat.set_shader_parameter("stitch_rows", 40.0 if tail else 70.0)
	return mat


## 頭の箱の横と奥の半分（m）。部位の大きさが違うアバターでも輪が合うように測る。
static func _head_half(parts: Dictionary) -> Vector2:
	var head := parts.get("head") as MeshInstance3D
	if head == null or head.mesh == null:
		return Vector2(0.22, 0.22)
	var box := head.mesh.get_aabb()
	var s := head.scale
	return Vector2(box.size.x * 0.5 * absf(s.x), box.size.z * 0.5 * absf(s.z))


## 首に巻いた輪：角の丸い四角の道に沿って、ふくらんだ断面（枕形）を回す。UV：x＝断面の 0..1、y＝1 周 0..1。
static func _ring_mesh(half: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := 32
	var prof := 8
	var a := half.x + RING_GAP + RING_THICK * 0.5
	var b := half.y + RING_GAP + RING_THICK * 0.5
	var path: Array[Vector3] = []
	for i in range(around + 1):
		var th := TAU * float(i) / around
		var c := cos(th)
		var s := sin(th)
		var x := a * signf(c) * pow(absf(c), 0.5)
		var z := b * signf(s) * pow(absf(s), 0.5)
		path.append(Vector3(x, 0.0, z))
	var rows: Array = []
	for i in range(around + 1):
		var p: Vector3 = path[i]
		var tangent := (path[mini(i + 1, around)] - path[maxi(i - 1, 0)]) if i > 0 and i < around else (path[1] - path[around - 1])
		var outward := tangent.cross(Vector3.UP).normalized() * -1.0
		if outward.dot(Vector3(p.x, 0.0, p.z)) < 0.0:
			outward = -outward
		var th := TAU * float(i) / around
		# 結び目（背中の少し右、th ≈ −90°）のあたりはふくらませる
		var knot := exp(-pow(wrapf(th - (-PI * 0.5 + 0.35), -PI, PI) / 0.45, 2.0))
		var row: Array = []
		for j in range(prof + 1):
			var ph := TAU * float(j) / prof
			var r_out := RING_THICK * 0.5 * (1.0 + 0.35 * knot)
			var r_up := RING_HEIGHT * (1.0 + 0.25 * knot)
			var wob := 1.0 + 0.06 * sin(th * 9.0 + ph * 2.0)
			row.append(p + outward * cos(ph) * r_out * wob + Vector3.UP * sin(ph) * r_up)
		rows.append(row)
	for i in range(around):
		for j in range(prof):
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for idx: Array in [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]:
				st.set_uv(Vector2(float(idx[1]) / prof, float(idx[0]) / around))
				st.add_vertex(rows[idx[0]][idx[1]])
	st.generate_normals()
	return st.commit()
