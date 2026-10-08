extends Node3D
class_name WallWorldBorder

## 問題の壁の延長線上（壁端〜床の外側）に立つ、マイクラのワールドボーダー風の力場。
## 普段は透明で、プレイヤーが近づいたときだけ近くが浮かび上がる。
## 前へ出させない押し戻しそのものは GameState（_apply_wall_world_border）が行い、ここは見た目だけを担う。

const BORDER_SHADER: Shader = preload("res://shaders/world_border.gdshader")
## 壁の正面（プレイヤー側 -Z）の面と揃える。壁の厚みの半分。
const WALL_FRONT_Z: float = -0.55
const FLASH_DECAY_PER_SEC: float = 2.4
const FAR_AWAY := Vector3(100000.0, 100000.0, 100000.0)

## 全壁で共有する材質。プレイヤー位置と押し戻しの閃光を1か所で更新する。
static var _material: ShaderMaterial = null
static var _flash: float = 0.0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = BORDER_SHADER
	return _material


## 毎フレーム、プレイヤーのワールド座標を渡す（いないプレイヤーは FAR_AWAY）。
static func update_players(player_a: Vector3, player_b: Vector3, dt: float) -> void:
	var mat := shared_material()
	_flash = maxf(0.0, _flash - FLASH_DECAY_PER_SEC * dt)
	mat.set_shader_parameter("player_a", player_a)
	mat.set_shader_parameter("player_b", player_b)
	mat.set_shader_parameter("flash", _flash)


static func hide_all() -> void:
	_flash = 0.0
	update_players(FAR_AWAY, FAR_AWAY, 0.0)


## プレイヤーを押し戻した瞬間に光らせる。
static func pulse() -> void:
	_flash = 1.0


func build(inner_x: float, outer_x: float, bottom_y: float, top_y: float) -> void:
	var height := top_y - bottom_y
	var width := outer_x - inner_x
	for side: int in [-1, 1]:
		var plane := MeshInstance3D.new()
		plane.name = "LeftBorder" if side < 0 else "RightBorder"
		var quad := QuadMesh.new()
		quad.size = Vector2(width, height)
		plane.mesh = quad
		plane.material_override = shared_material()
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# QuadMesh は XY 平面のまま。壁の正面と同じ面に、壁端から外側へ張る。
		plane.position = Vector3((inner_x + width * 0.5) * side, bottom_y + height * 0.5, WALL_FRONT_Z)
		add_child(plane)
