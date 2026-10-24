class_name SkyFallClouds
extends Node3D

## スカイゲートの体積雲（docs/sudden_death_v2/sky_fx.md 第2・3章。2026-10-19 ユーザー指示で写実の体積雲に作り直し）。
## SkyFallScenery の子で、原点＝落ちる点（2 人の真ん中）。1 つの雲＝1 つの箱で、箱の中をレイマーチで描く
## （shaders/sky_fx_cloud_volume.gdshader、形は sky_fx_cloud_shapes.res）。すべての雲を 1 つの MultiMesh に入れ、
## 毎フレーム遠い順に並べ直す（半透明の重なりを正しく）。描く回数は雲の数によらず 1 回（＋影の 1 回）。
## 層：
##   雲海   ：進み 0〜0.27。足もとの雲の海（平たい塊を敷きつめる）。真ん中に穴（ボードの真上。gate_emerge で開く）
##   ふちの塔：穴のふちの高い積雲。雲を抜けるとき（進み 0.17〜0.2）に 2 人を囲む壁になる
##   中の雲 ：ゲートの高さ（2 人の 14〜340 m 下）。落ちた分だけ上へ流し、下の端で現れる。海に影を落とす
##   近い雲 ：カメラの近くを抜ける小さな雲。画面のふちだけ（真ん中＝ボードと 2 人の上は通さない）
##   薄い雲 ：はるか下、海の少し上のうすい雲。海と一緒に近づく。影を落とす
## 2 人のすぐまわりは空ける（中・近い雲は、雲の半径＋余白より軸に近づけない）。

const CLOUD_SHADER := preload("res://shaders/sky_fx_cloud_volume.gdshader")
const SHADOW_SHADER := preload("res://shaders/sky_fx_cloud_shadow.gdshader")
const SHAPES_TEX := "res://assets/sudden_death/sky_fx/sky_fx_cloud_shapes.res"
const DETAIL_TEX := "res://assets/sudden_death/sky_fx/sky_fx_cloud_detail.res"
const SHADOW_TEX := "res://assets/sudden_death/sky_fx/sky_fx_cloud_shadows.png"
const META := "res://assets/sudden_death/sky_fx/sky_fx_cloud_volumes.json"

## 形の番号（bake_cloud_volumes.py の SHAPES の順）
const TOWER := 0
const CUMULUS := 1
const DECK_A := 2
const DECK_B := 3
const SMALL := 4
const WISP := 5

## 雲海の上面が落ちる点から何 m 下か（進み 0）。進み SEA_PASS で 2 人の高さを通る。
## ROUND 1（ゲート 8 秒 × 4、毎秒 40 m）の落ちる速さとそろう：0.19 × 1280 m ≈ 240 m。
const SEA_DEPTH0 := 240.0
const SEA_PASS := 0.19
const HOLE_START := 18.0
const HOLE_OPEN := 52.0
const HOLE_TIME := 1.4
const MID_TOP := -14.0
const MID_BOTTOM := -340.0
const MID_FADE_IN := 90.0
const NEAR_TOP := 28.0
const NEAR_BOTTOM := -70.0
const AXIS_CLEAR := 16.0
const NEAR_AXIS_CLEAR := 22.0
const THIN_LOW := 60.0
const THIN_HIGH := 140.0
const SUN_TRAVEL := Vector3(-0.533, -0.742, 0.407)

## 画質ごと：雲の数の倍率・レイマーチの歩数・光の歩数・細かいノイズ
const QUALITY := {
	"low": {"count": 0.5, "steps": 16, "light_steps": 2, "fine": false},
	"balanced": {"count": 0.8, "steps": 30, "light_steps": 3, "fine": true},
	"high": {"count": 1.0, "steps": 42, "light_steps": 4, "fine": true},
	"ultra": {"count": 1.0, "steps": 60, "light_steps": 5, "fine": true},
}

enum Layer { SEA, RIM, MID, NEAR, THIN }

var quality := ""
var hole_center := Vector2.ZERO
var hole_radius := HOLE_OPEN
var camera: Camera3D = null

var _aspects: Array = []
var _node: MultiMeshInstance3D = null
var _mat: ShaderMaterial = null
var _shadow_node: MultiMeshInstance3D = null
var _shadow_mat: ShaderMaterial = null
## 1 つずつの雲：層・位置（落ちる点から）・大きさ（m、x y z）・向き・形・濃さ・穴を使うか・模様・出方
var _layer := PackedInt32Array()
var _pos := PackedVector3Array()
var _size := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _shape := PackedInt32Array()
var _density := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _fade := PackedFloat32Array()
var _shadowed := PackedInt32Array()
var _order: Array[int] = []
var _sea_top := -SEA_DEPTH0
var _sea_level := -1000.0
var _bands := {"c": 1.0, "f": 0.0, "a": 0.0, "e": 0.0}
var _board: Node3D = null
var _hole_t := 99.0
var _visible_count := 0


func build(p_quality: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	quality = GraphicsQuality.normalize(p_quality)
	var q: Dictionary = QUALITY.get(quality, QUALITY.balanced)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	var shapes: Array = (meta as Dictionary).get("shapes", []) if meta is Dictionary else []
	_aspects = []
	for sh: Dictionary in shapes:
		_aspects.append(Vector3(float(sh.aspect[0]), float(sh.aspect[1]), float(sh.aspect[2])))
	while _aspects.size() < 6:
		_aspects.append(Vector3(1.0, 0.6, 1.0))
	_layer = PackedInt32Array()
	_pos = PackedVector3Array()
	_size = PackedVector3Array()
	_yaw = PackedFloat32Array()
	_shape = PackedInt32Array()
	_density = PackedFloat32Array()
	_seed = PackedFloat32Array()
	_fade = PackedFloat32Array()
	_shadowed = PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var k := float(q.count)
	_add_sea(rng, k)
	_add_rim(rng, k)
	_add_mid(rng, k)
	_add_near(rng, k)
	_add_thin(rng, k)
	var count := _pos.size()
	_order.resize(count)
	for i in range(count):
		_order[i] = i
	_mat = ShaderMaterial.new()
	_mat.shader = CLOUD_SHADER
	_mat.render_priority = -5
	_mat.set_shader_parameter("shape_tex", load(SHAPES_TEX))
	_mat.set_shader_parameter("detail_tex", load(DETAIL_TEX))
	_mat.set_shader_parameter("sun_dir", -SUN_TRAVEL.normalized())
	_mat.set_shader_parameter("steps", int(q.steps))
	_mat.set_shader_parameter("light_steps", int(q.light_steps))
	_mat.set_shader_parameter("fine_detail", bool(q.fine))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = count
	_node = MultiMeshInstance3D.new()
	_node.name = "VolumeClouds"
	_node.multimesh = mm
	_node.material_override = _mat
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_node.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	add_child(_node)
	# 影（中の雲と薄い雲）
	var shadowed := 0
	for i in range(count):
		if _layer[i] == Layer.MID or _layer[i] == Layer.THIN:
			_shadowed.append(i)
			shadowed += 1
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	_shadow_mat.render_priority = -8
	_shadow_mat.set_shader_parameter("shadow_atlas", load(SHADOW_TEX))
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.use_custom_data = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	smm.mesh = plane
	smm.instance_count = shadowed
	_shadow_node = MultiMeshInstance3D.new()
	_shadow_node.name = "CloudShadows"
	_shadow_node.multimesh = smm
	_shadow_node.material_override = _shadow_mat
	_shadow_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_node.custom_aabb = AABB(Vector3(-3000, -3000, -3000), Vector3(6000, 6000, 6000))
	add_child(_shadow_node)


func _add(layer: int, pos: Vector3, base_size: float, shape: int, density: float, rng: RandomNumberGenerator, y_scale := 1.0) -> void:
	var a: Vector3 = _aspects[shape]
	_layer.append(layer)
	_pos.append(pos)
	_size.append(Vector3(base_size * a.x, base_size * a.y * y_scale, base_size * a.z))
	_yaw.append(rng.randf_range(0.0, TAU))
	_shape.append(shape)
	_density.append(density)
	_seed.append(rng.randf())
	_fade.append(1.0)


func _add_sea(rng: RandomNumberGenerator, k: float) -> void:
	# 並びは画質によらず同じ（雲を抜ける画が画質で変わらないように）。低い画質は外側を減らすだけ
	var spacing := 105.0
	var radius := 380.0 + 180.0 * k
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	var n := int(560.0 / spacing)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var x := (i + (0.5 if j % 2 != 0 else 0.0) + rng.randf_range(-0.3, 0.3)) * spacing
			var z := (j * 0.87 + rng.randf_range(-0.25, 0.25)) * spacing
			var d := Vector2(x, z).length()
			var cover := noise.get_noise_2d(x, z)
			var shape := DECK_A if rng.randf() < 0.5 else DECK_B
			var pick := rng.randf()
			var size := spacing * rng.randf_range(1.35, 1.75)
			var dens := rng.randf_range(0.9, 1.25)
			if d > radius:
				continue
			if cover < -0.42 and d > 160.0:
				continue
			if pick < 0.18:
				shape = CUMULUS
			_add(Layer.SEA, Vector3(x, 0.0, z), size, shape, dens, rng)


func _add_rim(rng: RandomNumberGenerator, k: float) -> void:
	var count := 12
	for i in range(count):
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
		var d := HOLE_OPEN + rng.randf_range(18.0, 46.0)
		var shape := TOWER if i % 2 == 0 else CUMULUS
		_add(Layer.RIM, Vector3(cos(a) * d, 0.0, sin(a) * d), rng.randf_range(62.0, 92.0), shape, rng.randf_range(1.0, 1.3), rng)


func _add_mid(rng: RandomNumberGenerator, k: float) -> void:
	var count := int(round(18 * k))
	for i in range(count):
		var shape: int = [TOWER, CUMULUS, CUMULUS, SMALL][rng.randi() % 4]
		var size := rng.randf_range(38.0, 86.0) * (0.6 if shape == SMALL else 1.0)
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(size * 0.5 + AXIS_CLEAR, 280.0)
		var y := lerpf(MID_TOP, MID_BOTTOM, (float(i) + rng.randf()) / count)
		_add(Layer.MID, Vector3(cos(a) * d, y, sin(a) * d), size, shape, rng.randf_range(0.85, 1.2), rng)


func _add_near(rng: RandomNumberGenerator, k: float) -> void:
	var count := int(round(7 * k))
	for i in range(count):
		var shape := SMALL if i % 3 != 2 else WISP
		var size := rng.randf_range(20.0, 38.0)
		var a := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / count
		var d := rng.randf_range(size * 0.5 + NEAR_AXIS_CLEAR, size * 0.5 + NEAR_AXIS_CLEAR + 40.0)
		_add(Layer.NEAR, Vector3(cos(a) * d, lerpf(NEAR_TOP, NEAR_BOTTOM, rng.randf()), sin(a) * d), size, shape, rng.randf_range(0.7, 1.0), rng)


func _add_thin(rng: RandomNumberGenerator, k: float) -> void:
	var count := int(round(12 * k))
	for i in range(count):
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(120.0, 950.0)
		var shape := DECK_A if i % 2 == 0 else DECK_B
		_add(Layer.THIN, Vector3(cos(a) * d, rng.randf_range(THIN_LOW, THIN_HIGH), sin(a) * d), rng.randf_range(150.0, 260.0), shape,
			rng.randf_range(0.3, 0.45), rng, 0.45)


# ------------------------------------------------------------------ 毎フレーム

func set_bands(bands: Dictionary, progress: float, overtime: bool) -> void:
	_bands = bands
	_sea_top = -SEA_DEPTH0 * (SEA_PASS - progress) / SEA_PASS if not overtime else 2000.0


func set_sea_level(local_y: float) -> void:
	_sea_level = local_y


func set_sun(direction_to_sun: Vector3, color: Color, intensity: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("sun_dir", direction_to_sun.normalized())
	_mat.set_shader_parameter("sun_color", color)
	_mat.set_shader_parameter("sun_intensity", intensity)


func gate_emerge(board: Node3D) -> void:
	_board = board
	if board != null and is_instance_valid(board):
		var p := board.global_position
		hole_center = Vector2(p.x, p.z)
	_hole_t = 0.0


func advance(distance: float, delta: float) -> void:
	if _node == null:
		return
	var c := float(_bands.get("c", 0.0))
	var f := float(_bands.get("f", 0.0))
	var a := float(_bands.get("a", 0.0))
	var e := float(_bands.get("e", 0.0))
	if _board != null and is_instance_valid(_board):
		var bp := _board.global_position
		hole_center = hole_center.lerp(Vector2(bp.x, bp.z), clampf(delta * 3.0, 0.0, 1.0))
	else:
		hole_center = Vector2(global_position.x, global_position.z)
	_hole_t += delta
	var k := clampf(_hole_t / HOLE_TIME, 0.0, 1.0)
	hole_radius = lerpf(HOLE_START, HOLE_OPEN, 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k))
	_mat.set_shader_parameter("hole_center", hole_center)
	# 雲を抜ける間は穴を細くして、ふちの雲に囲まれる
	var near_sea := 1.0 - smoothstep(30.0, 120.0, absf(_sea_top))
	_mat.set_shader_parameter("hole_radius", hole_radius * (1.0 - 0.4 * near_sea))
	var local_hole := to_local(Vector3(hole_center.x, global_position.y, hole_center.y))
	var mid_amount := clampf(0.3 * c + 1.0 * a + 0.5 * e, 0.0, 1.0)
	var near_amount := clampf(0.2 * c + 0.7 * a + 0.5 * e, 0.0, 1.0) * (1.0 - f)
	var thin_amount := clampf(a + e, 0.0, 1.0) * smoothstep(260.0, 420.0, -_sea_level)
	var span_mid := MID_TOP - MID_BOTTOM
	var span_near := NEAR_TOP - NEAR_BOTTOM
	var count := _pos.size()
	for i in range(count):
		var layer := _layer[i]
		var p := _pos[i]
		var fade := 0.0
		var rank := float(i % 17) / 17.0
		match layer:
			Layer.SEA:
				fade = c
			Layer.RIM:
				fade = c
			Layer.MID:
				p.y += distance
				if p.y > MID_TOP:
					p.y -= span_mid
				_pos[i] = p
				fade = smoothstep(MID_BOTTOM, MID_BOTTOM + MID_FADE_IN, p.y) * (1.0 - smoothstep(MID_TOP - 18.0, MID_TOP, p.y))
				fade *= smoothstep(rank - 0.05, rank, mid_amount)
				# 雲海より下は雲海に隠れるので出さない。海より下（海が近い所）も出さない
				if c > 0.01 and p.y < _sea_top + 10.0:
					fade *= 1.0 - c
				fade *= smoothstep(_sea_level + 20.0, _sea_level + 70.0, p.y - _size[i].y * 0.5)
			Layer.NEAR:
				p.y += distance
				if p.y > NEAR_TOP:
					p.y -= span_near
				_pos[i] = p
				fade = smoothstep(NEAR_BOTTOM, NEAR_BOTTOM + 25.0, p.y) * (1.0 - smoothstep(NEAR_TOP - 12.0, NEAR_TOP, p.y))
				fade *= smoothstep(rank - 0.05, rank, near_amount)
				if c > 0.01 and p.y < _sea_top + 10.0:
					fade *= 1.0 - c
				fade *= smoothstep(_sea_level + 20.0, _sea_level + 50.0, p.y)
			Layer.THIN:
				fade = thin_amount
		_fade[i] = fade
	# 遠い順に並べて書く
	var cam := camera if camera != null and is_instance_valid(camera) else (get_viewport().get_camera_3d() if is_inside_tree() else null)
	var eye := to_local(cam.global_position) if cam != null else Vector3(0.0, 8.0, 0.0)
	var dist := PackedFloat32Array()
	dist.resize(count)
	var world_pos: Array[Vector3] = []
	world_pos.resize(count)
	for i in range(count):
		var wp := _cloud_center(i, local_hole)
		world_pos[i] = wp
		dist[i] = wp.distance_squared_to(eye)
	_order.sort_custom(func(x: int, y: int) -> bool: return dist[x] > dist[y])
	var mm := _node.multimesh
	_visible_count = 0
	for slot in range(count):
		var i := _order[slot]
		var s := _size[i]
		mm.set_instance_transform(slot, Transform3D(Basis(Vector3.UP, _yaw[i]) * Basis.from_scale(s), world_pos[i]))
		var hole_flag := 0.5 if _layer[i] == Layer.SEA else 0.0
		mm.set_instance_custom_data(slot, Color(float(_shape[i]) / 8.0, _density[i] * 0.5, hole_flag + _seed[i] * 0.49, _fade[i]))
		if _fade[i] > 0.003:
			_visible_count += 1
	_node.visible = _visible_count > 0
	_update_shadows(a + e)


## 雲の箱の中心（落ちる点からの位置）。雲海とふちの塔は雲海の高さに、ふちの塔は穴の中心のまわりに。
func _cloud_center(i: int, local_hole: Vector3) -> Vector3:
	var p := _pos[i]
	var s := _size[i]
	match _layer[i]:
		Layer.SEA:
			return Vector3(p.x, _sea_top - s.y * 0.36, p.z)
		Layer.RIM:
			return Vector3(local_hole.x + p.x, _sea_top + 24.0 - s.y * 0.4, local_hole.z + p.z)
		Layer.THIN:
			return Vector3(p.x, _sea_level + p.y, p.z)
	return p


func _update_shadows(strength: float) -> void:
	var smm := _shadow_node.multimesh
	var down := SUN_TRAVEL.normalized()
	_shadow_node.visible = strength > 0.01
	if not _shadow_node.visible:
		return
	for k in range(_shadowed.size()):
		var i := _shadowed[k]
		var p := _cloud_center(i, Vector3.ZERO)
		var s := _size[i]
		var h := p.y - _sea_level
		var sp := p + down * (h / maxf(-down.y, 0.1))
		sp.y = _sea_level + 0.6
		var alpha := _fade[i] * strength * (0.0 if h < 5.0 else 1.0) * clampf(_density[i], 0.0, 1.0)
		smm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, _yaw[i]) * Basis.from_scale(Vector3(s.x, 1.0, s.z)), sp))
		smm.set_instance_custom_data(k, Color(float(_shape[i]) / 8.0, alpha, 0.0, 0.0))


func stats() -> Dictionary:
	var by_layer := {}
	for i in range(_layer.size()):
		var key: String = ["sea", "rim", "mid", "near", "thin"][_layer[i]]
		by_layer[key] = int(by_layer.get(key, 0)) + 1
	var draws := (1 if _node != null and _node.visible else 0) + (1 if _shadow_node != null and _shadow_node.visible else 0)
	return {"draws": draws, "clouds": _pos.size(), "visible": _visible_count, "layers": by_layer, "shadows": _shadowed.size(),
		"steps": int((QUALITY.get(quality, QUALITY.balanced) as Dictionary).steps)}
