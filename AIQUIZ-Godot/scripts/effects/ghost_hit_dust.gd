extends Node3D
class_name GhostHitDust

## ゴーストの突進で吹き飛んだ体が床に落ちる・転がるときの砂ぼこり（docs/ghost_hit_ragdoll_plan.md 段階 6）。
## 押し合いの砂ぼこり（local_push_effects.gd）と同じく、低ポリの球を前もって作っておき、広げながら薄くして消す。
## 座標はワールド（top_level）。PlayerController が持ち、被弾の着地（burst）と転がりの間（trail）に呼ぶ。

const POOL_SIZE := 56
const COLOR := Color(0.86, 0.86, 0.83)
## 粒のいちばん濃いときの不透明度（生まれた直後）。
const ALPHA := 0.4
## 着地の輪：粒の数・広がる速さ（m/s。強さ 1 のとき）・寿命。
const BURST_PUFFS := 12
const BURST_SPEED := 3.6
const BURST_LIFE := 0.6
## 転がりの跡：1 回に出す粒の数・寿命。
const TRAIL_PUFFS := 2
const TRAIL_LIFE := 0.55
## 粒の速さの減り（毎秒の割合）と、浮き上がる速さ。
const DRAG := 3.0
const RISE := 0.9

var _puffs: Array[Dictionary] = []
var _cursor := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 5517
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.radius = 0.5
	mesh.height = 1.0
	for i in range(POOL_SIZE):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(COLOR, 0.0)
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.material_override = material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.visible = false
		add_child(piece)
		_puffs.append({"node": piece, "material": material, "age": 0.0, "life": 0.0, "velocity": Vector3.ZERO, "size": 0.0})


## 着地：floor_point（床の上の点）のまわりに輪を広げる。direction は滑る向き（水平、x と z）で、輪をその向きへ少し寄せる。
## strength は 0〜1.5 くらい（着地の横の速さから）。
func burst(floor_point: Vector3, direction: Vector2, strength: float) -> void:
	var count := int(round(BURST_PUFFS * clampf(0.6 + strength * 0.4, 0.6, 1.4)))
	var lead := Vector3(direction.x, 0.0, direction.y).normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	for i in range(count):
		# 輪がきれいに並ばないよう、向き・速さ・大きさ・出る位置をばらす。
		var angle := TAU * (float(i) + _rng.randf_range(-0.5, 0.5)) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var speed := BURST_SPEED * strength * _rng.randf_range(0.45, 1.2)
		var velocity := outward * speed + lead * speed * 0.6 + Vector3.UP * RISE * _rng.randf_range(0.5, 1.5)
		var size := (0.3 + 0.14 * strength) * _rng.randf_range(0.75, 1.35)
		_spawn(floor_point + outward * _rng.randf_range(0.1, 0.45), velocity, BURST_LIFE * _rng.randf_range(0.75, 1.15), size)


## 転がり・滑りの間：体の下の床の点に小さな粒を残す（滑る向きと逆へ少し流す）。
func trail(floor_point: Vector3, direction: Vector2, strength: float) -> void:
	var back := -Vector3(direction.x, 0.0, direction.y).normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	for i in range(TRAIL_PUFFS):
		var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * 0.6
		var velocity := (back * 0.8 + side) * strength + Vector3.UP * RISE * _rng.randf_range(0.4, 1.0)
		_spawn(floor_point + side * 0.3, velocity, TRAIL_LIFE * _rng.randf_range(0.8, 1.2), 0.24 + 0.1 * strength)


## 見えている粒の数（テスト用）。
func active_count() -> int:
	var count := 0
	for puff: Dictionary in _puffs:
		if (puff.node as MeshInstance3D).visible:
			count += 1
	return count


func clear() -> void:
	for puff: Dictionary in _puffs:
		puff.age = puff.life
		(puff.node as MeshInstance3D).visible = false


func _spawn(point: Vector3, velocity: Vector3, life: float, size: float) -> void:
	var puff: Dictionary = _puffs[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	puff.age = 0.0
	puff.life = maxf(0.05, life)
	puff.velocity = velocity
	puff.size = size
	var node := puff.node as MeshInstance3D
	node.global_position = point + Vector3.UP * 0.15
	node.scale = Vector3.ONE * size * 0.3
	node.visible = true


func _process(delta: float) -> void:
	for puff: Dictionary in _puffs:
		var node := puff.node as MeshInstance3D
		if not node.visible:
			continue
		puff.age = float(puff.age) + delta
		var u := float(puff.age) / float(puff.life)
		if u >= 1.0:
			node.visible = false
			continue
		var velocity: Vector3 = puff.velocity
		velocity *= exp(-DRAG * delta)
		puff.velocity = velocity
		node.global_position += velocity * delta
		# 少し平たく生まれて、ふくらみながら丸くなる。
		var grow := float(puff.size) * (0.35 + 1.0 * sqrt(u))
		node.scale = Vector3(grow, grow * (0.7 + 0.3 * u), grow)
		(puff.material as StandardMaterial3D).albedo_color = Color(COLOR, ALPHA * pow(1.0 - u, 1.5))
