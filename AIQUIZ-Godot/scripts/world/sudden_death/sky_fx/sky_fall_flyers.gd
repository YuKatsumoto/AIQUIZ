class_name SkyFallFlyers
extends Node3D

## スカイゲートの海鳥と飛行機雲（docs/sudden_death_v2/sky_fx.md 第1・3章）。SkyFallScenery の子で、原点＝落ちる点。
##   海鳥   ：低い所（近い島と着地台の帯）で群れが画面を横切る。2 人と海の間（海までの深さの BIRD_DEPTH_SHARE、
##            BIRD_DEPTH_MIN〜MAX m 下）を飛ぶので、2 人とはぶつからない。羽ばたく板（shaders/sky_fx_bird.gdshader）の MultiMesh
##   飛行機雲：高い所（雲海の上・点々の雲の前半）で、はるか下を小さな飛行機が横切り、2 本の白い筋が伸びて薄れる
## 鳥と飛行機は形を手で組む（数枚の板と箱。素材ファイルはない）。

const BIRD_SHADER := preload("res://shaders/sky_fx_bird.gdshader")
const STREAK_SHADER := preload("res://shaders/sky_fx_streak.gdshader")

const BIRD_DEPTH_SHARE := 0.42
const BIRD_DEPTH_MIN := 34.0
const BIRD_DEPTH_MAX := 85.0
const BIRD_SPEED := 9.0
## 翼の幅（m）。見下ろしで読めるように実物より大きめ
const BIRD_SPAN := 3.4
const FLOCK_REACH := 150.0
## 飛行機：落ちる点から何 m 下を、何 m/秒で。飛行機雲の長さ（m）。
const PLANE_DEPTH := 260.0
## 雲海の帯では雲海（進み 0 で 240 m 下）より上を飛ぶ
const PLANE_DEPTH_HIGH := 140.0
const PLANE_SPEED := 70.0
const PLANE_REACH := 520.0
const TRAIL_LENGTH := 650.0
const TRAIL_SEGMENTS := 18

var quality := ""
var low := false
var _birds: MultiMeshInstance3D = null
var _bird_offsets := PackedVector3Array()
var _flock_t := 0.0
var _flock_dir := 1.0
var _flock_z := -14.0
var _bird_weight := 0.0
var _plane: MeshInstance3D = null
var _trail_mesh: ImmediateMesh = null
var _trail_node: MeshInstance3D = null
var _plane_t := 0.0
var _plane_lane := 0
var _plane_weight := 0.0
var _plane_depth := PLANE_DEPTH
var _sea_level := -1000.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func build(p_quality: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	quality = GraphicsQuality.normalize(p_quality)
	low = quality == GraphicsQuality.LOW
	_rng.seed = 314
	_build_birds()
	_build_plane()


func _build_birds() -> void:
	var count := 10 if low else 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bird_mesh()
	mm.instance_count = count
	var mat := ShaderMaterial.new()
	mat.shader = BIRD_SHADER
	_birds = MultiMeshInstance3D.new()
	_birds.name = "Seabirds"
	_birds.multimesh = mm
	_birds.material_override = mat
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_birds.custom_aabb = AABB(Vector3(-400, -1500, -400), Vector3(800, 1600, 800))
	add_child(_birds)
	_bird_offsets.resize(count)
	for i in range(count):
		# ゆるい V 字：先頭から左右へ交互に、後ろへずれる
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 1 else 1.0
		_bird_offsets[i] = Vector3(-rank * 3.6 + _rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.5, 1.5), side * rank * 4.2 + _rng.randf_range(-1.4, 1.4))
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(7.0, 9.5), 0.0, 0.0))
	_flock_t = 0.0


## 海鳥の形：体（ひし形）・尾・2 枚の翼（後ろへ少し流れる）。頂点色 R＝翼の重み、G＝左右。前は −Z。
func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := BIRD_SPAN * 0.5
	var tris := [
		# 体（上から見えるひし形を 2 枚）
		[Vector3(0, 0.03, -0.38), Vector3(0.07, 0, 0.0), Vector3(-0.07, 0, 0.0), 0.0, 0.0],
		[Vector3(0.07, 0, 0.0), Vector3(0, 0.02, 0.3), Vector3(-0.07, 0, 0.0), 0.0, 0.0],
		# 尾
		[Vector3(0.0, 0.0, 0.22), Vector3(0.09, 0.0, 0.42), Vector3(-0.09, 0.0, 0.42), 0.0, 0.0],
	]
	for side: float in [-1.0, 1.0]:
		var g := 1.0 if side > 0.0 else 0.0
		var root_f := Vector3(side * 0.06, 0.0, -0.1)
		var root_b := Vector3(side * 0.06, 0.0, 0.14)
		var mid_f := Vector3(side * s * 0.5, 0.04, -0.06)
		var mid_b := Vector3(side * s * 0.5, 0.04, 0.16)
		var tip := Vector3(side * s, 0.0, 0.22)
		tris.append([root_f, mid_f, root_b, 0.0, g])
		tris.append([mid_f, mid_b, root_b, 0.0, g])
		tris.append([mid_f, tip, mid_b, 0.0, g])
	for t: Array in tris:
		for k in range(3):
			var v: Vector3 = t[k]
			var w := clampf(absf(v.x) / s, 0.0, 1.0)
			st.set_color(Color(w, 1.0 if v.x > 0.0 else 0.0, 0.0, 1.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _build_plane() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(0.96, 0.97, 0.98)
	var navy := Color(0.12, 0.2, 0.42)
	_box(st, Vector3(0, 0, 0), Vector3(1.4, 1.4, 12.0), white)
	_box(st, Vector3(0, -0.2, -0.6), Vector3(13.0, 0.25, 2.4), white)
	_box(st, Vector3(0, 0.1, 5.2), Vector3(4.6, 0.2, 1.2), white)
	_box(st, Vector3(0, 1.2, 5.3), Vector3(0.2, 2.2, 1.4), navy)
	for sx: float in [-3.0, 3.0]:
		_box(st, Vector3(sx, -0.75, -1.4), Vector3(0.6, 0.6, 1.8), Color(0.75, 0.78, 0.82))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	_plane = MeshInstance3D.new()
	_plane.name = "ContrailPlane"
	_plane.mesh = st.commit()
	_plane.material_override = mat
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)
	_trail_mesh = ImmediateMesh.new()
	var tmat := ShaderMaterial.new()
	tmat.shader = STREAK_SHADER
	tmat.set_shader_parameter("opacity", 0.85)
	tmat.set_shader_parameter("flow_speed", 0.15)
	tmat.set_shader_parameter("grain", 14.0)
	tmat.set_shader_parameter("edge_soft", 0.85)
	tmat.set_shader_parameter("tail_power", 1.3)
	tmat.set_shader_parameter("head_soft", 0.01)
	tmat.render_priority = 3
	_trail_node = MeshInstance3D.new()
	_trail_node.name = "Contrail"
	_trail_node.mesh = _trail_mesh
	_trail_node.material_override = tmat
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_node.extra_cull_margin = 4096.0
	add_child(_trail_node)
	_plane_t = 0.35


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	for f: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		for idx: int in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.set_color(col)
			st.add_vertex(p[idx])


func set_sea_level(local_y: float) -> void:
	_sea_level = local_y


func advance(delta: float, bands: Dictionary, progress: float) -> void:
	_time += delta
	var overtime := bool(bands.get("overtime", false))
	var depth := -_sea_level
	_bird_weight = maxf(float(bands.get("e", 0.0)), float(bands.get("a", 0.0)) * (1.0 - smoothstep(260.0, 380.0, depth)))
	# 雲海の上（雲海が 2 人に近づく前まで）と、雲を抜けたあとの点々の雲の前半。雲海の間は雲海より上を飛ぶ
	_plane_weight = maxf(1.0 - smoothstep(0.06, 0.1, progress), smoothstep(0.26, 0.3, progress) * (1.0 - smoothstep(0.42, 0.5, progress))) if not overtime else 0.6
	_plane_depth = PLANE_DEPTH_HIGH if progress < 0.17 and not overtime else PLANE_DEPTH
	_update_birds(delta)
	_update_plane(delta)


func _update_birds(delta: float) -> void:
	_birds.visible = _bird_weight > 0.01
	if not _birds.visible:
		return
	_flock_t += delta
	var x := -FLOCK_REACH + _flock_t * BIRD_SPEED
	if x > FLOCK_REACH + 30.0:
		_flock_t = 0.0
		_flock_dir = -_flock_dir
		_flock_z = _rng.randf_range(-35.0, 5.0)
		x = -FLOCK_REACH
	var heading := Vector3(_flock_dir, 0.0, sin(_flock_t * 0.15) * 0.25).normalized()
	var side := Vector3(-heading.z, 0.0, heading.x)
	var depth := clampf(-_sea_level * BIRD_DEPTH_SHARE, BIRD_DEPTH_MIN, BIRD_DEPTH_MAX)
	var center := Vector3(x * _flock_dir, -depth, _flock_z + sin(_flock_t * 0.3) * 6.0)
	var basis := Basis.looking_at(heading, Vector3.UP)
	var mm := _birds.multimesh
	var fade := smoothstep(-FLOCK_REACH, -FLOCK_REACH + 25.0, x) * (1.0 - smoothstep(FLOCK_REACH, FLOCK_REACH + 30.0, x))
	for i in range(_bird_offsets.size()):
		var o := _bird_offsets[i]
		var bob := sin(_time * 1.6 + float(i) * 1.3) * 0.5
		var p := center - heading * (-o.x) + side * o.z + Vector3(0.0, o.y + bob, 0.0)
		var bank := Basis(heading, sin(_time * 0.7 + float(i)) * 0.15)
		var s := maxf(fade * _bird_weight, 0.001)
		mm.set_instance_transform(i, Transform3D((bank * basis).scaled(Vector3(s, s, s)) if s < 0.999 else bank * basis, p))
		var cd := mm.get_instance_custom_data(i)
		# ときどき滑空（羽ばたかない）
		cd.b = smoothstep(0.55, 0.85, sin(_time * 0.4 + float(i) * 2.1) * 0.5 + 0.5)
		mm.set_instance_custom_data(i, cd)


func _update_plane(delta: float) -> void:
	var show := _plane_weight > 0.01
	_plane.visible = show
	_trail_mesh.clear_surfaces()
	if not show:
		return
	_plane_t += delta * PLANE_SPEED / (PLANE_REACH * 2.0)
	if _plane_t > 1.25:
		_plane_t = 0.0
		_plane_lane += 1
	# 画面の上のほう（見下ろしの画の中心は 2 人の少し前、260 m 下で約 70 m 前。上のふちは約 240 m 前）を斜めに横切る。
	# 2 人とボードの上（画面の真ん中）は通らない
	var lanes := [[Vector3(-PLANE_REACH, 0.0, -210.0), Vector3(PLANE_REACH, 0.0, -130.0)],
		[Vector3(PLANE_REACH, 0.0, -200.0), Vector3(-PLANE_REACH, 0.0, -150.0)],
		[Vector3(-PLANE_REACH, 0.0, -140.0), Vector3(PLANE_REACH, 0.0, -220.0)]]
	var lane: Array = lanes[_plane_lane % lanes.size()]
	var zk := _plane_depth / PLANE_DEPTH
	var a: Vector3 = (lane[0] as Vector3) * Vector3(1.0, 1.0, zk)
	var b: Vector3 = (lane[1] as Vector3) * Vector3(1.0, 1.0, zk)
	var dir := (b - a).normalized()
	var y := -_plane_depth
	var pos := a.lerp(b, _plane_t) + Vector3(0.0, y, 0.0)
	_plane.position = pos
	_plane.basis = Basis.looking_at(dir, Vector3.UP)
	var travelled := minf(_plane_t, 1.0) * a.distance_to(b)
	var length := minf(TRAIL_LENGTH, travelled + maxf(_plane_t - 1.0, 0.0) * 0.0)
	if length < 2.0:
		return
	var side := Vector3(-dir.z, 0.0, dir.x)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for eng: float in [-3.0, 3.0]:
		for i in range(TRAIL_SEGMENTS):
			var t0 := float(i) / TRAIL_SEGMENTS
			var t1 := float(i + 1) / TRAIL_SEGMENTS
			var spread0 := eng * (1.0 + t0 * 1.6)
			var spread1 := eng * (1.0 + t1 * 1.6)
			var c0 := pos - dir * (6.0 + length * t0) + side * spread0 + Vector3(0.0, -0.8, 0.0)
			var c1 := pos - dir * (6.0 + length * t1) + side * spread1 + Vector3(0.0, -0.8, 0.0)
			var w0 := 0.7 + 7.0 * t0
			var w1 := 0.7 + 7.0 * t1
			var col := Color(0.3 + eng * 0.05, 0.0, 0.0, _plane_weight)
			var u0 := t0 * length / TRAIL_LENGTH
			var u1 := t1 * length / TRAIL_LENGTH
			for v: Array in [[c0 - side * w0 * 0.5, u0, 0.0], [c0 + side * w0 * 0.5, u0, 1.0], [c1 + side * w1 * 0.5, u1, 1.0],
					[c0 - side * w0 * 0.5, u0, 0.0], [c1 + side * w1 * 0.5, u1, 1.0], [c1 - side * w1 * 0.5, u1, 0.0]]:
				_trail_mesh.surface_set_color(col)
				_trail_mesh.surface_set_uv(Vector2(float(v[1]), float(v[2])))
				_trail_mesh.surface_add_vertex(v[0] as Vector3)
	_trail_mesh.surface_end()


## 確認用：群れを画面の真ん中あたり（x m）に、飛行機を道の途中（0〜1）に置く。
func debug_place(flock_x: float, plane_t: float) -> void:
	_flock_t = (flock_x + FLOCK_REACH) / BIRD_SPEED
	_plane_t = plane_t


func stats() -> Dictionary:
	var draws := 0
	if _birds != null and _birds.visible:
		draws += 1
	if _plane != null and _plane.visible:
		draws += 1
	if _trail_mesh != null and _trail_mesh.get_surface_count() > 0:
		draws += 1
	return {"draws": draws, "birds": _bird_offsets.size(), "bird_weight": snappedf(_bird_weight, 0.01), "plane_weight": snappedf(_plane_weight, 0.01)}
