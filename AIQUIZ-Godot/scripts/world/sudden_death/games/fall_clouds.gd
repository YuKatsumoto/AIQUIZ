class_name FallClouds
extends Node3D

## 「ひらけ！パラシュート」の落下中の雲（docs/sudden_death_v2/parachute.md 7.1節）。2人は動かさず、雲を下から上へ流して
## 落ちているように見せる。板はマッチング演出の雲と同じシェーダー（online_staging_cloud.gdshader、カメラを向く板）。
## 1 枚ずつ、上の端（+HALF_HEIGHT）を越えたら下の端へ回す。端はカメラの画角の外（真上・真下）なので、回すところは見えない。
## 2 人のすぐまわり（NEAR_CLEAR）は空ける。

const CLOUD_SHADER := preload("res://shaders/online_staging_cloud.gdshader")
const HALF_HEIGHT := 110.0
const NEAR_CLEAR := 22.0
const FAR := 120.0

var _mm: MultiMesh = null
var _offsets := PackedVector3Array()
var _sizes := PackedFloat32Array()


func build(quality: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	var low := GraphicsQuality.normalize(quality) == GraphicsQuality.LOW
	var count := 26 if low else 56
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm.mesh = quad
	_mm.instance_count = count
	_offsets.resize(count)
	_sizes.resize(count)
	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(NEAR_CLEAR, FAR)
		_offsets[i] = Vector3(cos(angle) * distance, rng.randf_range(-HALF_HEIGHT, HALF_HEIGHT), sin(angle) * distance)
		_sizes[i] = rng.randf_range(18.0, 46.0)
		_mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf_range(0.55, 0.95), 0.0))
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	var node := MultiMeshInstance3D.new()
	node.name = "FallCloudPlates"
	node.multimesh = _mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-FAR - 60, -HALF_HEIGHT - 60, -FAR - 60), Vector3(FAR * 2 + 120, HALF_HEIGHT * 2 + 120, FAR * 2 + 120))
	add_child(node)
	_write()


## 落ちた分（m）だけ雲を上へ流す。
func advance(distance: float) -> void:
	if _mm == null or distance == 0.0:
		return
	for i in range(_offsets.size()):
		var p := _offsets[i] + Vector3(0.0, distance, 0.0)
		if p.y > HALF_HEIGHT:
			p.y -= HALF_HEIGHT * 2.0
		elif p.y < -HALF_HEIGHT:
			p.y += HALF_HEIGHT * 2.0
		_offsets[i] = p
	_write()


func _write() -> void:
	for i in range(_mm.instance_count):
		var s := _sizes[i]
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s * 1.5, s * 0.8, 1.0)), _offsets[i]))
