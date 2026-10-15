class_name StagingClouds
extends Node3D

## マッチング演出の検索中の飛行（S5〜S7）の雲の層（仕様書 10、D14）。
## 板（QuadMesh）を MultiMesh で並べ、online_staging_cloud.gdshader で積雲を描く。
## 原点を動かさない：ヘリの近くを中心にした箱の中に雲を置き、流れた分（advance）だけ後ろへずらし、
## 箱の後ろへ出た雲は前へ回す。品質「低」は下の層だけ（16 枚）。

const CLOUD_SHADER := preload("res://shaders/online_staging_cloud.gdshader")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const HALF_LENGTH := 420.0   # 進む向きの半分の長さ
const HALF_WIDTH := 300.0

## {"name", "count", "height"（中心からの高さ m）, "size"（m）}
var layers: Array[Dictionary] = []

var _multimeshes: Array[MultiMesh] = []
var _offsets: Array = []     # 層ごとの PackedVector3Array（中心からの位置）
var _sizes: Array = []       # 層ごとの PackedFloat32Array
var _forward := Vector3(0, 0, -1)
var _right := Vector3(1, 0, 0)


func build(quality: String, forward: Vector3) -> void:
	for child: Node in get_children():
		child.queue_free()
	_multimeshes.clear()
	_offsets.clear()
	_sizes.clear()
	_forward = Vector3(forward.x, 0.0, forward.z).normalized()
	_right = _forward.cross(Vector3.UP).normalized()
	var low := QualityRules.normalize(quality) == QualityRules.LOW
	layers = [{"name": "Lower", "count": 16 if low else 40, "height": -30.0, "size": Vector2(26.0, 52.0)}]
	if not low:
		layers.append({"name": "Upper", "count": 24, "height": 25.0, "size": Vector2(34.0, 70.0)})
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	for layer: Dictionary in layers:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mm.mesh = quad
		mm.instance_count = int(layer.count)
		var offsets := PackedVector3Array()
		var sizes := PackedFloat32Array()
		for i in range(mm.instance_count):
			var along := rng.randf_range(-HALF_LENGTH, HALF_LENGTH)
			var side := rng.randf_range(-HALF_WIDTH, HALF_WIDTH)
			# ヘリのすぐ横（カメラの通り道）は空ける
			if absf(side) < 40.0:
				side = signf(side if side != 0.0 else 1.0) * rng.randf_range(40.0, HALF_WIDTH)
			var size_range: Vector2 = layer.size
			var size := rng.randf_range(size_range.x, size_range.y)
			offsets.append(_forward * along + _right * side + Vector3(0, float(layer.height) + rng.randf_range(-4.0, 4.0), 0))
			sizes.append(size)
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.0), 0.0))
		var node := MultiMeshInstance3D.new()
		node.name = "Clouds" + str(layer.name)
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-HALF_LENGTH - 200, -120, -HALF_LENGTH - 200), Vector3(HALF_LENGTH * 2 + 400, 240, HALF_LENGTH * 2 + 400))
		add_child(node)
		_multimeshes.append(mm)
		_offsets.append(offsets)
		_sizes.append(sizes)
	_write()


## 流れた距離（m）だけ雲を後ろへずらす。
func advance(distance: float) -> void:
	if distance == 0.0:
		return
	for l in range(_offsets.size()):
		var offsets: PackedVector3Array = _offsets[l]
		for i in range(offsets.size()):
			var p := offsets[i] - _forward * distance
			var along := p.dot(_forward)
			if along < -HALF_LENGTH:
				p += _forward * HALF_LENGTH * 2.0
			elif along > HALF_LENGTH:
				p -= _forward * HALF_LENGTH * 2.0
			offsets[i] = p
		_offsets[l] = offsets
	_write()


func _write() -> void:
	for l in range(_multimeshes.size()):
		var mm: MultiMesh = _multimeshes[l]
		var offsets: PackedVector3Array = _offsets[l]
		var sizes: PackedFloat32Array = _sizes[l]
		for i in range(mm.instance_count):
			var s := sizes[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s * 1.6, s * 0.75, 1.0)), offsets[i]))
