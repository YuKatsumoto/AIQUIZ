class_name FloatplaneWake
extends MeshInstance3D

## 水上機の航跡（docs/sudden_death_v2/c130_float.md 第9章）。2 本の浮き舟のうしろに残る白い泡の筋と、外へ開いていく
## V 字の引き波（ケルビン波。進む向きから約 19.5°）を、海面の上の帯で描く。点は世界に置いたまま（機体に付いて動かない）、
## 古くなるほど広がって薄くなる。海の波の上下は floatplane_wake.gdshader が海と同じ式でつける。
##
## 使い方：add_child → set_ocean(海の MeshInstance3D) → 毎フレーム advance(delta, 機体の xf, 速さ, 水の上か, 打ちつけ) → clear()

const SHADER := preload("res://shaders/sudden_death/floatplane_wake.gdshader")
## 点を置く間隔（秒）と、残る長さ（秒）。
const STEP := 0.06
const LIFETIME := 8.0
const MAX_POINTS := 140
## 浮き舟の中心の x と、泡が出る所（速いときは段のうしろ、後ろ向きのときは船首）の z（機体のローカル）。
const FLOAT_X := 3.6
const STERN_Z := 6.0
const BOW_Z := -5.2
## ケルビン波の開き（tan 19.47°）と、開いていく幅の上限（m）。
const KELVIN := 0.354
const ARM_MAX := 46.0

var _samples: Array[Dictionary] = []
var _clock := 0.0
var _next := 0.0
var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()
var _ocean: MeshInstance3D = null


func _ready() -> void:
	name = "FloatplaneWake"
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_material.shader = SHADER
	_material.render_priority = 2
	material_override = _material
	mesh = _mesh


## 波を合わせる海（ステージの海、または空のセットの海）。
func set_ocean(ocean: MeshInstance3D) -> void:
	_ocean = ocean
	_sync_ocean()


func clear() -> void:
	_samples.clear()
	_mesh.clear_surfaces()


func point_count() -> int:
	return _samples.size()


## xf は機体（原点は喫水線）。speed は進む向きの速さ（後ろ向きは負）、wet は浮き舟が水に入っている、burst は着水の打ちつけ（0〜1）。
func advance(delta: float, xf: Transform3D, speed: float, wet: bool, burst := 0.0) -> void:
	_clock += delta
	while not _samples.is_empty() and _clock - float(_samples[0].time) > LIFETIME:
		_samples.pop_front()
	_sync_ocean()
	var moving := absf(speed) > 0.4
	if wet and moving and _clock >= _next:
		_next = _clock + STEP
		var z := STERN_Z if speed >= 0.0 else BOW_Z
		var sea := _sea_level()
		var left := xf * Vector3(-FLOAT_X, 0.0, z)
		var right := xf * Vector3(FLOAT_X, 0.0, z)
		left.y = sea
		right.y = sea
		var forward := -xf.basis.z
		forward.y = 0.0
		forward = forward.normalized() * signf(speed)
		var side := forward.cross(Vector3.UP).normalized()
		# 遅いと細い筋、段に乗って速いと太く荒れた泡。着水の瞬間はいちばん濃い。
		var v := absf(speed)
		var strength := clampf(0.3 + v / 20.0, 0.0, 1.0) + burst * 0.6
		if not _samples.is_empty() and left.distance_to(_samples[-1].left) > maxf(8.0, v * STEP * 4.0):
			_samples.clear()
		_samples.append({"left": left, "right": right, "side": side, "time": _clock, "v": v,
			"strength": minf(strength, 1.4), "rough": clampf(v / 18.0 + burst, 0.0, 1.0)})
		if _samples.size() > MAX_POINTS:
			_samples.pop_front()
	_rebuild()


func _sea_level() -> float:
	return _ocean.global_position.y if is_instance_valid(_ocean) else StageConstants.OCEAN_SURFACE_Y


func _sync_ocean() -> void:
	if not is_instance_valid(_ocean):
		_material.set_shader_parameter("sea_level", StageConstants.OCEAN_SURFACE_Y)
		_material.set_shader_parameter("wave_height", 0.0)
		return
	_material.set_shader_parameter("sea_level", _ocean.global_position.y)
	_material.set_shader_parameter("surface_origin", Vector2(_ocean.global_position.x, _ocean.global_position.z))
	var water := _ocean.material_override as ShaderMaterial
	if water != null:
		for parameter in ["wave_speed", "wave_height", "noise_tex", "noise_tex2", "flow_offset"]:
			_material.set_shader_parameter(parameter, water.get_shader_parameter(parameter))
	var plane_mesh := _ocean.mesh as PlaneMesh
	if plane_mesh != null:
		var scale := _ocean.global_basis.get_scale()
		_material.set_shader_parameter("surface_size", plane_mesh.size * Vector2(scale.x, scale.z))
		_material.set_shader_parameter("surface_cells", Vector2(plane_mesh.subdivide_width + 1, plane_mesh.subdivide_depth + 1))


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var bounds := AABB(_samples[0].left, Vector3.ZERO)
	for point: Dictionary in _samples:
		bounds = bounds.expand(point.left).expand(point.right)
	bounds.position.y = _sea_level() - 1.0
	bounds.size.y = 2.0
	custom_aabb = bounds.grow(ARM_MAX + 6.0)
	# 2 本の筋が合わさった、真ん中の広い泡（少し遅れて広がる）
	_strip(0.0, func(point: Dictionary, age: float) -> Array:
		var base: Vector3 = ((point.left as Vector3) + (point.right as Vector3)) * 0.5
		var width := 3.0 + minf(float(point.v) * 0.12, 1.6) * age
		var fade := smoothstep(0.3, 1.6, age) * pow(maxf(0.0, 1.0 - age / LIFETIME), 1.6) * smoothstep(3.0, 14.0, float(point.v))
		return [base, width, fade * float(point.strength) * 0.5])
	for wing: float in [-1.0, 1.0]:
		# 浮き舟のうしろの泡の筋：時間とともに広がり、薄くなる
		_strip(wing, func(point: Dictionary, age: float) -> Array:
			var base: Vector3 = point.left if wing < 0.0 else point.right
			var spread := minf(float(point.v) * 0.06, 0.8) * age
			var width := 1.5 + spread + age * 0.18
			var fade := smoothstep(0.0, 0.12, age) * pow(maxf(0.0, 1.0 - age / LIFETIME), 1.3)
			return [base + (point.side as Vector3) * wing * spread * 0.35, width, fade * float(point.strength)])
		# 外へ開いていく V 字の腕：進んだ距離 × tan 19.5° だけ外へ
		_strip(wing, func(point: Dictionary, age: float) -> Array:
			var base: Vector3 = point.left if wing < 0.0 else point.right
			var out := minf(KELVIN * float(point.v) * age, ARM_MAX)
			var width := 0.45 + age * 0.22
			var fade := smoothstep(0.15, 0.6, age) * pow(maxf(0.0, 1.0 - age / LIFETIME), 1.8) * smoothstep(1.5, 6.0, float(point.v))
			return [base + (point.side as Vector3) * wing * out, width, fade * float(point.strength) * 0.55])


## 1 本の帯。shape(point, age) は [中心, 幅, 濃さ] を返す。
func _strip(wing: float, shape: Callable) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var along := 0.0
	var last := Vector3.ZERO
	for i in range(_samples.size()):
		var point: Dictionary = _samples[i]
		var age := _clock - float(point.time)
		var row: Array = shape.call(point, age)
		var center: Vector3 = row[0]
		if i > 0:
			along += center.distance_to(last)
		last = center
		var half := float(row[1]) * 0.5
		var alpha := clampf(float(row[2]), 0.0, 1.0)
		var side: Vector3 = point.side
		for edge: float in [-1.0, 1.0]:
			_mesh.surface_set_normal(Vector3.UP)
			_mesh.surface_set_color(Color(float(point.rough), 0.0, 0.0, alpha))
			_mesh.surface_set_uv(Vector2((edge + 1.0) * 0.5, along + wing * 37.0))
			_mesh.surface_add_vertex(center + side * half * edge)
	_mesh.surface_end()
