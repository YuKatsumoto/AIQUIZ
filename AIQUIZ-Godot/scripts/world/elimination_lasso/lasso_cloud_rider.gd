class_name LassoCloudRider
extends Node3D

## 雲に乗ったハテナ（両者脱落の投げ縄の演出。EliminationLassoDirector）。
## 雲（mascot_cloud.glb と mascot_cloud.gdshader。build_mascot_cloud.py で作る）と、等倍のハテナ（mascot_model.glb）。
## このノードの空間 = ハテナの空間（x 左・y 上・z 前、原点は足の裏 = 雲の原点）。演出がこのノードの拡大で大きさを決める。
## ハテナの骨は演出が毎フレーム渡す姿勢（apply_pose）から組む：体（DEF-head の玉と「？」）の位置・傾き・つぶれ、
## 両手の目標と肘の向き（2 本の骨の IK）、手の向き。脚は雲の中で軽く折りたたむ。カウボーイハットを頭に載せる。
## 速く飛ぶときは、雲の表面が後ろへ流れ、小さな雲のかけらを残す。

const MASCOT_GLB := "res://assets/characters/aiquiz_mascot/mascot_model.glb"
const MASCOT_LOD_GLB := "res://assets/characters/aiquiz_mascot/mascot_model_lod.glb"
const CLOUD_GLB := "res://assets/characters/aiquiz_mascot/mascot_cloud.glb"
const CLOUD_SHADER := preload("res://assets/characters/aiquiz_mascot/mascot_cloud.gdshader")
## 手首から握った手の真ん中まで（ハテナの空間の m）
const GRIP_OFFSET := 0.075
## カウボーイハット：つばの長さ（ハテナの空間の m）と、頭の上の置き場所（DEF-head の空間。体の玉は中心 y 1.03・
## 半径約 0.55、てっぺん y 1.58）・傾き。「？」は帽子のてっぺんから突き出る。
const HAT_BRIM_WIDTH := 1.12
const HAT_OFFSET := Vector3(0.0, 0.69, -0.06)
const HAT_TILT_DEG := Vector3(-10.0, 0.0, 8.0)

var skeleton: Skeleton3D = null
var cloud_material: ShaderMaterial = null
## 雲の表面のなびき（ハテナの空間の向きと量）。演出が速さから入れる。
var trail := Vector3.ZERO

var _model: Node3D = null
var _cloud: MeshInstance3D = null
var _hat: Node3D = null
var _puffs: GPUParticles3D = null
var _bones := {}
var _parents := PackedInt32Array()
var _rest: Array[Transform3D] = []
var _child_dir: Array[Vector3] = []
var _global: Array[Transform3D] = []
var _pose_rot: Array[Quaternion] = []
var _pose_pos: Array[Vector3] = []
var _pose_scale: Array[Vector3] = []


func setup(quality: String) -> bool:
	var normalized := GraphicsQuality.normalize(quality)
	var use_lod := not GraphicsQuality.is_at_least(normalized, GraphicsQuality.HIGH)
	var path := MASCOT_LOD_GLB if use_lod and ResourceLoader.exists(MASCOT_LOD_GLB) else MASCOT_GLB
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(CLOUD_GLB):
		return false
	var packed := load(path) as PackedScene
	_model = packed.instantiate() as Node3D if packed != null else null
	if _model == null:
		return false
	_model.name = "Hatena"
	add_child(_model)
	for node: Node in _model.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	var found := _model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if skeleton == null:
		return false
	_cache_skeleton()
	if not _setup_cloud(normalized):
		return false
	_setup_hat()
	_setup_puffs(normalized)
	apply_pose({})
	return true


func _setup_cloud(quality: String) -> bool:
	var scene := load(CLOUD_GLB) as PackedScene
	var root := scene.instantiate() as Node3D if scene != null else null
	if root == null:
		return false
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		root.free()
		return false
	var source := meshes[0] as MeshInstance3D
	_cloud = MeshInstance3D.new()
	_cloud.name = "Cloud"
	_cloud.mesh = source.mesh
	_cloud.transform = source.global_transform if source.is_inside_tree() else _node_transform_in(root, source)
	root.free()
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	if quality == GraphicsQuality.LOW:
		cloud_material.set_shader_parameter("puff_amount", 0.0)
	_cloud.material_override = cloud_material
	_cloud.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_cloud)
	return true


static func _node_transform_in(root: Node, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _setup_hat() -> void:
	var hat := HatFactory.create_hat(HatData.HAT_COWBOY)
	if hat == null:
		return
	# つばの幅を測って、ハテナの頭の大きさに合わせる
	var aabb := AABB()
	var first := true
	for node: Node in hat.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var box := _node_transform_in(hat, mesh_instance) * mesh_instance.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var width := maxf(aabb.size.x, aabb.size.z)
	var fit := HAT_BRIM_WIDTH / width if width > 0.001 else 3.0
	_hat = Node3D.new()
	_hat.name = "CowboyHat"
	add_child(_hat)
	hat.scale = Vector3.ONE * fit
	_hat.add_child(hat)
	for node: Node in hat.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _setup_puffs(quality: String) -> void:
	if quality == GraphicsQuality.LOW:
		return
	_puffs = GPUParticles3D.new()
	_puffs.name = "CloudPuffs"
	_puffs.amount = 28
	_puffs.lifetime = 0.9
	_puffs.local_coords = false
	_puffs.emitting = false
	_puffs.visibility_aabb = AABB(Vector3(-8, -6, -8), Vector3(16, 12, 16))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.75
	process.direction = Vector3(0, 0.2, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	process.gravity = Vector3.ZERO
	process.damping_min = 0.5
	process.damping_max = 1.0
	process.scale_min = 0.55
	process.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.55))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.75))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	_puffs.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.97, 0.98, 1.0)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var soft_texture := GradientTexture2D.new()
	soft_texture.gradient = soft
	soft_texture.fill = GradientTexture2D.FILL_RADIAL
	soft_texture.fill_from = Vector2(0.5, 0.5)
	soft_texture.fill_to = Vector2(0.5, 0.0)
	soft_texture.width = 64
	soft_texture.height = 64
	material.albedo_texture = soft_texture
	quad.material = material
	_puffs.draw_pass_1 = quad
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puffs)


## 雲のかけらを出すか（速く飛んでいるあいだ）。
func set_puffing(on: bool) -> void:
	if _puffs != null and _puffs.emitting != on:
		_puffs.emitting = on


## 雲のかけらを、まわりの景色と一緒に流す（コースを流して飛ぶあいだ、残したかけらが景色と同じ速さで後ろへ
## 流れて、速く飛んでいるように見える）。velocity は親の空間の速さ。小さければ、その場にふわっと残る。
func set_flow(velocity: Vector3) -> void:
	if _puffs == null:
		return
	var process := _puffs.process_material as ParticleProcessMaterial
	var speed := velocity.length()
	if speed < 1.0:
		process.direction = Vector3(0, 0.2, 0)
		process.spread = 180.0
		process.initial_velocity_min = 0.1
		process.initial_velocity_max = 0.5
		process.damping_min = 0.5
		process.damping_max = 1.0
		return
	# 出す速さは雲の向きと大きさで変わるので、雲の空間へ直す
	var scale_factor := maxf(transform.basis.get_scale().x, 0.01)
	process.direction = (transform.basis.orthonormalized().inverse() * velocity).normalized()
	process.spread = 8.0
	process.initial_velocity_min = speed / scale_factor * 0.92
	process.initial_velocity_max = speed / scale_factor
	process.damping_min = 0.0
	process.damping_max = 0.0


func _cache_skeleton() -> void:
	var count := skeleton.get_bone_count()
	_parents.resize(count)
	_rest.resize(count)
	_child_dir.resize(count)
	_global.resize(count)
	_pose_rot.resize(count)
	_pose_pos.resize(count)
	_pose_scale.resize(count)
	for b in range(count):
		_bones[skeleton.get_bone_name(b)] = b
		_parents[b] = skeleton.get_bone_parent(b)
		_rest[b] = skeleton.get_bone_rest(b)
		_child_dir[b] = Vector3.UP
	for b in range(count):
		var parent := _parents[b]
		if parent >= 0 and _child_dir[parent] == Vector3.UP:
			_child_dir[parent] = _rest[b].origin.normalized()


func bone(bone_name: String) -> int:
	return int(_bones.get(bone_name, -1))


## 姿勢（キーはすべて省略できる。ハテナの空間）：
##   body_offset: Vector3 体の玉の移動、body_rot: Quaternion 体の傾き（DEF-head の付け根まわり）、
##   squash: float（1 = そのまま、>1 で縦に伸び、<1 でつぶれる）、
##   r_hand / l_hand: Vector3 手首の目標、r_pole / l_pole: Vector3 肘を向ける方向、
##   r_hand_dir / l_hand_dir: Vector3 手（ミトン）の先を向ける方向、hat_lift: float 帽子の浮き（跳ねる）。
func apply_pose(pose: Dictionary) -> void:
	if skeleton == null:
		return
	var count := _rest.size()
	for b in range(count):
		_pose_rot[b] = _rest[b].basis.get_rotation_quaternion()
		_pose_pos[b] = _rest[b].origin
		_pose_scale[b] = Vector3.ONE
	var head := bone("DEF-head")
	var hips := bone("DEF-hips")
	var offset: Vector3 = pose.get("body_offset", Vector3.ZERO)
	var body_rot: Quaternion = pose.get("body_rot", Quaternion.IDENTITY)
	var squash: float = clampf(float(pose.get("squash", 1.0)), 0.7, 1.4)
	var side_scale := 1.0 / sqrt(squash)
	_pose_pos[head] = _rest[head].origin + offset
	_pose_rot[head] = body_rot * _pose_rot[head]
	_pose_scale[head] = Vector3(side_scale, squash, side_scale)
	_pose_pos[hips] = _rest[hips].origin + offset * Vector3(0.6, 0.45, 0.6)
	_global[head] = _local_xform(head)
	_global[hips] = _local_xform(hips)
	_solve_arm("R", pose.get("r_hand", Vector3(-0.74, 0.66, 0.04)), pose.get("r_pole", Vector3(-0.6, -0.8, -0.3)),
		pose.get("r_hand_dir", Vector3.ZERO))
	_solve_arm("L", pose.get("l_hand", Vector3(0.74, 0.66, 0.04)), pose.get("l_pole", Vector3(0.6, -0.8, -0.3)),
		pose.get("l_hand_dir", Vector3.ZERO))
	_fold_legs()
	for b in range(count):
		skeleton.set_bone_pose_position(b, _pose_pos[b])
		skeleton.set_bone_pose_rotation(b, _pose_rot[b])
		skeleton.set_bone_pose_scale(b, _pose_scale[b])
	if _hat != null:
		var lift := float(pose.get("hat_lift", 0.0))
		var hat_basis := Basis.from_euler(Vector3(deg_to_rad(HAT_TILT_DEG.x), deg_to_rad(HAT_TILT_DEG.y), deg_to_rad(HAT_TILT_DEG.z)))
		var on_head := Transform3D(hat_basis, HAT_OFFSET + Vector3.UP * lift)
		var head_xform := _global[head]
		# 帽子はつぶれ・伸びにつられず、位置だけ追う
		var unscaled := Transform3D(head_xform.basis.orthonormalized(), head_xform.origin + head_xform.basis.y * (HAT_OFFSET.y * (squash - 1.0)))
		_hat.transform = unscaled * on_head
	if cloud_material != null:
		cloud_material.set_shader_parameter("trail", trail)


func _local_xform(b: int) -> Transform3D:
	var local := Transform3D(Basis(_pose_rot[b]) * Basis.from_scale(_pose_scale[b]), _pose_pos[b])
	var parent := _parents[b]
	return _global[parent] * local if parent >= 0 else local


## 骨 b の向き（根元から子の骨へ）を、ハテナの空間の dir に合わせる（休みの姿勢からの最短の回転）。
func _aim(b: int, dir: Vector3) -> void:
	var parent := _parents[b]
	var parent_global := _global[parent] if parent >= 0 else Transform3D.IDENTITY
	var rest_rot := _rest[b].basis.get_rotation_quaternion()
	var rest_global := parent_global * Transform3D(Basis(rest_rot), _pose_pos[b])
	var want := (rest_global.basis.inverse() * dir)
	if want.length_squared() < 1e-10:
		_global[b] = _local_xform(b)
		return
	want = want.normalized()
	var from := _child_dir[b]
	var arc := _arc(from, want)
	_pose_rot[b] = rest_rot * arc
	_global[b] = _local_xform(b)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var d := clampf(from.dot(to), -1.0, 1.0)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var axis := from.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = from.cross(Vector3.FORWARD)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)


func _solve_arm(side: String, target: Vector3, pole: Vector3, hand_dir: Vector3) -> void:
	var upper := bone("DEF-upper_arm." + side)
	var fore := bone("DEF-forearm." + side)
	var hand := bone("DEF-hand." + side)
	if upper < 0 or fore < 0 or hand < 0:
		return
	var shoulder_global := _global[_parents[upper]] * Transform3D(Basis(_rest[upper].basis.get_rotation_quaternion()), _pose_pos[upper])
	var shoulder := shoulder_global.origin
	var l1 := (shoulder_global.basis * _rest[fore].origin).length()
	var l2 := (shoulder_global.basis * _rest[hand].origin).length()
	var to := target - shoulder
	var reach := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var axis := to.normalized() if to.length_squared() > 1e-10 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + reach * reach - l2 * l2) / (2.0 * l1 * reach), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var bend := pole - axis * pole.dot(axis)
	if bend.length_squared() < 1e-8:
		bend = axis.cross(Vector3.FORWARD)
	bend = bend.normalized()
	var elbow := shoulder + axis * (l1 * cos_a) + bend * (l1 * sin_a)
	var wrist := shoulder + axis * reach
	_aim(upper, elbow - shoulder)
	_aim(fore, wrist - elbow)
	_aim(hand, hand_dir if hand_dir.length_squared() > 1e-6 else (wrist - elbow))


## 雲の中で脚を軽く折りたたむ（体が傾いても足が雲から出ない）。
func _fold_legs() -> void:
	for side in ["L", "R"]:
		var sign := 1.0 if side == "L" else -1.0
		var thigh := bone("DEF-thigh." + side)
		var shin := bone("DEF-shin." + side)
		var foot := bone("DEF-foot." + side)
		var toe := bone("DEF-toe." + side)
		if thigh < 0:
			continue
		_aim(thigh, Vector3(0.06 * sign, -0.72, 0.62))
		_aim(shin, Vector3(0.02 * sign, -0.80, -0.55))
		if foot >= 0:
			_aim(foot, Vector3(0.0, -0.35, -0.92))
		if toe >= 0:
			_global[toe] = _local_xform(toe)


## 握った手の真ん中（親 = 演出の根の空間）。
func grip_point(side: String) -> Vector3:
	return transform * grip_local(side)


## 握った手の真ん中（ハテナの空間）。
func grip_local(side: String) -> Vector3:
	var hand := bone("DEF-hand." + side)
	if hand < 0:
		return Vector3.ZERO
	var g := _global[hand]
	return g.origin + g.basis.y.normalized() * GRIP_OFFSET


## 手の向き（親の空間）。y が指先の向き。
func hand_basis(side: String) -> Basis:
	var hand := bone("DEF-hand." + side)
	if hand < 0:
		return transform.basis.orthonormalized()
	return (transform.basis * _global[hand].basis).orthonormalized()


## 肩の位置（ハテナの空間）。
func shoulder_local(side: String) -> Vector3:
	var upper := bone("DEF-upper_arm." + side)
	if upper < 0:
		return Vector3.ZERO
	return (_global[_parents[upper]] * _rest[upper]).origin


## 縄の当たり（親の空間の [a, b, 半径]）：体の玉と帽子。投げて放す瞬間に、輪が頭や帽子をすり抜けないように使う。
func colliders() -> Array:
	var head := bone("DEF-head")
	if head < 0:
		return []
	var g := transform * _global[head]
	var k := transform.basis.get_scale().x
	var ball := g * Vector3(0.0, 0.234, 0.0)
	var crown := g * (HAT_OFFSET + Vector3(0.0, 0.16, 0.0))
	return [[ball, ball, 0.5 * k], [crown, crown, 0.27 * k]]


## 体の玉の真ん中（ハテナの空間）。
func body_center_local() -> Vector3:
	var head := bone("DEF-head")
	return _global[head].origin + _global[head].basis.y * 0.1 if head >= 0 else Vector3(0, 0.9, 0)
