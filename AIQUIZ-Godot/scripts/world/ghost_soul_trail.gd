class_name GhostSoulTrail
extends MeshInstance3D

## GOSTRIDER の魂の尾。通った点を少しの間だけ覚え、交差した 2 枚のリボンにして加算で光らせる
## （どの向きのカメラからも帯に見える）。頭は太く白く、尾へ細くプレイヤー色になって消える。

const FX_SHADER := preload("res://assets/ghost_rider/ghost_fx_additive.gdshader")

@export var lifetime: float = 0.55
@export var head_width: float = 0.16
@export var tail_width: float = 0.02
@export var min_spacing: float = 0.04

var color: Color = Color(1.0, 0.62, 0.26, 1.0)
var emitting: bool = false

var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _immediate := ImmediateMesh.new()
var _material := ShaderMaterial.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _immediate
	_material.shader = FX_SHADER
	_material.set_shader_parameter("energy", 0.95)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 64.0


func set_trail_color(value: Color) -> void:
	color = value
	_material.set_shader_parameter("color", Color(1.0, 1.0, 1.0, 1.0))


## 毎フレーム呼ぶ。emitting の間は anchor を足し、古い点は lifetime で消える。
func step(delta: float, anchor: Vector3, scale_factor: float = 1.0) -> void:
	for index: int in range(_ages.size()):
		_ages[index] += delta
	while not _ages.is_empty() and _ages[0] > lifetime:
		_ages.pop_front()
		_points.pop_front()
	if emitting:
		if _points.is_empty() or _points[-1].distance_to(anchor) >= min_spacing * scale_factor:
			_points.append(anchor)
			_ages.append(0.0)
		elif not _points.is_empty():
			_points[-1] = anchor
			_ages[-1] = 0.0
	_rebuild(scale_factor)


func clear() -> void:
	_points.clear()
	_ages.clear()
	_immediate.clear_surfaces()


func is_idle() -> bool:
	return _points.is_empty()


func _rebuild(scale_factor: float) -> void:
	_immediate.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	for ribbon: int in range(2):
		_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
		for index: int in range(count):
			var point := _points[index]
			var previous := _points[maxi(0, index - 1)]
			var following := _points[mini(count - 1, index + 1)]
			var tangent := following - previous
			if tangent.length_squared() < 0.000001:
				tangent = Vector3.FORWARD
			tangent = tangent.normalized()
			var side := tangent.cross(Vector3.UP)
			if side.length_squared() < 0.0001:
				side = tangent.cross(Vector3.RIGHT)
			side = side.normalized()
			if ribbon == 1:
				side = tangent.cross(side).normalized()
			# 0 = 尾（古い）、1 = 頭（新しい）
			var along := float(index) / float(count - 1)
			var life := 1.0 - clampf(_ages[index] / lifetime, 0.0, 1.0)
			var width := lerpf(tail_width, head_width, along * along) * scale_factor
			var fade := 0.75 * life * smoothstep(0.0, 0.3, along) * (1.0 - smoothstep(0.8, 1.0, along) * 0.7)
			var tint := color.lerp(Color(1.0, 1.0, 1.0, 1.0), along * along * 0.15)
			tint.a = fade
			_immediate.surface_set_color(tint)
			_immediate.surface_add_vertex(point - side * width)
			_immediate.surface_set_color(tint)
			_immediate.surface_add_vertex(point + side * width)
		_immediate.surface_end()
