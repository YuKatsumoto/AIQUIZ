extends Node3D

## 雲の層をつき抜けて場所を替える（docs/sudden_death_v2/c130_float.md 第10章。雲の覆いの画面推移の代わり）。
##   雲の層（deck）：カメラの方を向く板を、決めた高さの帯（bottom〜top）に並べた層積雲。外から見ると層、中を通ると板が流れていく。
##   中の白さ（veil）：画面いっぱいの板。カメラが層の中にいる深さで、遠いほど白い霧をかける（機内にカメラがあるときは機内に霧をかけない）。
## 監督の場所の入れ替え（地上 → 空のセット、空のセット → 地上、本戦 → 降下の位置）は、カメラが層のいちばん深い所にいる間に行う。
## そのとき機体とカメラは同じだけ動かし（機体から見たカメラは変わらない）、入れ替えた先にも同じ高さの層を置き直す
## （move_deck）ので、層の中の深さはつながったまま、上か下へ抜けていく。

const VEIL_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_cloud_veil.gdshader")
const PUFF_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_cloud_puff.gdshader")
const QualityRules := preload("res://scripts/core/graphics_quality.gd")

## 層の中のいちばん深い所の霧の濃さ（1/m）。20 m 先の機体がほぼ見えなくなる濃さ。
const PEAK_DENSITY := 0.24
## 層のふち（上下）から中へ、霧が濃くなるまでの深さ（m）
const EDGE := 9.0

var quality := "balanced"
var deck_bottom := 0.0
var deck_top := 0.0
var deck_center := Vector3.ZERO
var deck_size := Vector2(600.0, 500.0)
## 層の中の深さ（0＝外、1＝いちばん深い）。update で決まる。
var depth := 0.0
## 機内にカメラがあるとき：これより近いものに霧をかけない（m）
var interior_start := 0.0
## 雲の層を流す（空のセットは機体を止めて景色を流すので、層も後ろへ流す）。m
var flow := Vector3.ZERO

var _deck: MultiMeshInstance3D = null
var _puff_material: ShaderMaterial = null
var _veil: MeshInstance3D = null
var _veil_material: ShaderMaterial = null
var _offsets := PackedVector3Array()
var _sizes := PackedFloat32Array()
var _forward := Vector3(0, 0, -1)
var _fade := 0.0
var _fade_target := 0.0
var _fade_rate := 0.4
var _drift := Vector3.ZERO     # 霧のむらの流れ（ノイズの空間）
var _noise_basis := Basis.IDENTITY
var _sun := Vector3(0.53, 0.74, -0.41)
var _sun_from := _sun
var _sun_target := _sun
var _sun_k := 1.0
var _sun_rate := 0.0


func build(quality_value: String) -> void:
	quality = QualityRules.normalize(quality_value)
	name = "FloatplaneCloudPass"
	if _veil == null:
		_veil = MeshInstance3D.new()
		_veil.name = "CloudVeil"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		_veil.mesh = quad
		_veil.extra_cull_margin = 16384.0
		_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_veil_material = ShaderMaterial.new()
		_veil_material.shader = VEIL_SHADER
		_veil_material.render_priority = 120
		_veil.material_override = _veil_material
		_veil.visible = false
		add_child(_veil)
	if _deck == null:
		_deck = MultiMeshInstance3D.new()
		_deck.name = "CloudDeck"
		_deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_puff_material = ShaderMaterial.new()
		_puff_material.shader = PUFF_SHADER
		_puff_material.render_priority = 2
		_deck.material_override = _puff_material
		_deck.visible = false
		add_child(_deck)
	var low := quality == QualityRules.LOW
	_veil_material.set_shader_parameter("samples", 1 if low else 3)
	_puff_material.set_shader_parameter("use_soft", not low)


## 雲の層を置く。center は層の真ん中（x, z）、bottom・top は高さ（ワールド）、forward は飛んでいく向き（層は前へ長い）。
## fade_in 秒で薄い所から現れる（急に出ない）。
func place_deck(center: Vector3, bottom: float, top: float, size: Vector2, forward: Vector3, sun_to: Vector3, seed := 1, fade_in := 2.5) -> void:
	deck_center = Vector3(center.x, (bottom + top) * 0.5, center.z)
	deck_bottom = bottom
	deck_top = top
	deck_size = size
	_forward = Vector3(forward.x, 0.0, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else Vector3(0, 0, -1)
	_sun = sun_to.normalized()
	_sun_target = _sun
	_sun_k = 1.0
	_sun_rate = 0.0
	flow = Vector3.ZERO
	_drift = Vector3.ZERO
	_noise_basis = Basis.IDENTITY
	var right := _forward.cross(Vector3.UP).normalized()
	var low := quality == QualityRules.LOW
	var count := 70 if low else 170
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741 + seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = count
	_offsets = PackedVector3Array()
	_sizes = PackedFloat32Array()
	var thick := maxf(top - bottom, 1.0)
	for i in range(count):
		var along := rng.randf_range(-0.5, 0.5) * size.x
		var side := rng.randf_range(-0.5, 0.5) * size.y
		# 層の中ほどに多く、上は丸く盛り上がる
		var h := clampf(rng.randfn(0.5, 0.22), 0.05, 1.0)
		var s := rng.randf_range(26.0, 58.0) * (0.75 if h > 0.8 else 1.0)
		_offsets.append(_forward * along + right * side + Vector3(0.0, bottom + h * thick - deck_center.y, 0.0))
		_sizes.append(s)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf_range(0.55, 0.95), h))
	_deck.multimesh = mm
	_deck.global_position = deck_center
	_deck.custom_aabb = AABB(Vector3(-size.x - 100.0, -thick - 120.0, -size.x - 100.0), Vector3(size.x * 2.0 + 200.0, thick * 2.0 + 240.0, size.x * 2.0 + 200.0))
	_puff_material.set_shader_parameter("sun_dir", _sun)
	_veil_material.set_shader_parameter("sun_dir", _sun)
	_write()
	_deck.visible = true
	_fade = 0.0 if fade_in > 0.0 else 1.0
	_fade_target = 1.0
	_fade_rate = 1.0 / maxf(fade_in, 0.01)
	_apply_fade()


## 層を消す（fade_out 秒で薄れる。0 ならすぐ）。
func clear_deck(fade_out := 0.0) -> void:
	if fade_out <= 0.0:
		_fade = 0.0
		_fade_target = 0.0
		_deck.visible = false
		_veil.visible = false
		depth = 0.0
		return
	_fade_target = 0.0
	_fade_rate = 1.0 / fade_out


func has_deck() -> bool:
	return _deck != null and _deck.visible


## 雲の中の入れ替え：層・霧のむら・太陽の向きを、機体と同じ写し（map：水平の向きの回転と移動）でまとめて運ぶ。
## 機体の中や横から見える雲の板の並び・むらは入れ替えの前とまったく同じに見える（見える物が飛ばない）。
func relocate(map: Transform3D) -> void:
	var f := map.basis * Vector3.FORWARD
	var yaw := Basis(Vector3.UP, atan2(-f.x, -f.z))
	var moved := Transform3D(yaw, map.origin)
	deck_center = moved * deck_center
	deck_bottom += map.origin.y
	deck_top += map.origin.y
	flow = yaw * flow
	_forward = yaw * _forward
	for i in range(_offsets.size()):
		_offsets[i] = yaw * _offsets[i]
	# 霧のむら：ノイズの空間の点 q = N p + c が、運んだ先の点でも同じになるように（N' = N Y⁻¹、c' = c − N' t）
	_noise_basis = _noise_basis * yaw.inverse()
	_drift -= _noise_basis * map.origin
	_sun = yaw * _sun
	_sun_from = yaw * _sun_from
	_sun_target = yaw * _sun_target
	if _deck != null:
		_deck.global_position = deck_center
		_write()
	_apply_sun()
	_veil_material.set_shader_parameter("noise_basis", _noise_basis)


## 層の帯を高さ [bottom, top] に、中心を center に置き直す（入れ替えた先で、機体の層の中の深さを保つとき）。
func move_deck(center: Vector3, bottom: float, top: float, forward: Vector3) -> void:
	var scale_y := (top - bottom) / maxf(deck_top - deck_bottom, 0.01)
	var new_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var turn := Basis(Vector3.UP, atan2(-new_forward.x, -new_forward.z) - atan2(-_forward.x, -_forward.z))
	for i in range(_offsets.size()):
		var o := turn * _offsets[i]
		o.y = o.y * scale_y
		_offsets[i] = o
	_forward = new_forward
	deck_bottom = bottom
	deck_top = top
	deck_center = Vector3(center.x, (bottom + top) * 0.5, center.z)
	flow = Vector3.ZERO
	_deck.global_position = deck_center
	_write()


## 太陽の向き（太陽へ向かう向き、ワールド）。blend 秒かけて回す（雲の中の入れ替えで白さの明暗がパッと変わらない）。
func set_sun(sun_to: Vector3, blend := 0.0) -> void:
	_sun_target = sun_to.normalized()
	if blend > 0.0:
		_sun_from = _sun
		_sun_k = 0.0
		_sun_rate = 1.0 / blend
		return
	_sun = _sun_target
	_sun_k = 1.0
	_sun_rate = 0.0
	_apply_sun()


func _apply_sun() -> void:
	if _puff_material != null:
		_puff_material.set_shader_parameter("sun_dir", _sun)
		_veil_material.set_shader_parameter("sun_dir", _sun)


## 毎フレーム：カメラ（このフレームに撮る目の位置）の高さから層の中の深さを決め、霧を当てる。flow_step は景色を流した距離（空のセット）。
func update(eye: Vector3, delta: float, flow_step := Vector3.ZERO) -> void:
	if _deck == null:
		return
	_fade = move_toward(_fade, _fade_target, _fade_rate * delta)
	if _sun_rate > 0.0:
		_sun_k = minf(_sun_k + _sun_rate * delta, 1.0)
		_sun = _sun_from.slerp(_sun_target, smoothstep(0.0, 1.0, _sun_k)).normalized()
		if _sun_k >= 1.0:
			_sun_rate = 0.0
		_apply_sun()
	if _fade_target <= 0.0 and _fade <= 0.0:
		_deck.visible = false
		_veil.visible = false
		depth = 0.0
		return
	if flow_step != Vector3.ZERO:
		flow += flow_step
		for i in range(_offsets.size()):
			_offsets[i] = _offsets[i] + flow_step
		_write()
	_apply_fade()
	var p := eye
	var inside_y := smoothstep(deck_bottom - 1.0, deck_bottom + EDGE, p.y) * (1.0 - smoothstep(deck_top - EDGE, deck_top + 1.0, p.y))
	var rel := p - (deck_center + flow)
	var right := _forward.cross(Vector3.UP).normalized()
	var a := absf(rel.dot(_forward)) / maxf(deck_size.x * 0.5, 1.0)
	var b := absf(rel.dot(right)) / maxf(deck_size.y * 0.5, 1.0)
	var inside_xz := 1.0 - smoothstep(0.75, 1.0, maxf(a, b))
	depth = inside_y * inside_xz * _fade
	var density := PEAK_DENSITY * pow(depth, 1.6)
	_drift += _noise_basis * ((_forward * 8.0 + Vector3(0.0, 0.6, 0.0)) * delta - flow_step)
	_veil_material.set_shader_parameter("density", density)
	_veil_material.set_shader_parameter("start", interior_start)
	_veil_material.set_shader_parameter("drift", _drift)
	_veil_material.set_shader_parameter("noise_basis", _noise_basis)
	_veil_material.set_shader_parameter("max_alpha", 1.0)
	_veil.visible = density > 0.0004


## カメラの今の、層の中の深さ（0〜1）。
func depth_at(y: float) -> float:
	return smoothstep(deck_bottom - 1.0, deck_bottom + EDGE, y) * (1.0 - smoothstep(deck_top - EDGE, deck_top + 1.0, y))


func _apply_fade() -> void:
	if _puff_material != null:
		_puff_material.set_shader_parameter("opacity", 0.92 * _fade)


func _write() -> void:
	var mm := _deck.multimesh
	if mm == null:
		return
	for i in range(mini(mm.instance_count, _offsets.size())):
		var s := _sizes[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s * 1.7, s * 0.62, 1.0)), _offsets[i]))
