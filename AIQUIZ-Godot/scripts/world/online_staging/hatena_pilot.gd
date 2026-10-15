class_name HatenaPilot
extends Node3D

## 乗り込めるヘリの右の席に座る操縦士ハテナ（等倍。mascot_model.glb、品質「低」は軽い版 mascot_model_lod.glb）。
## 動きは Blender で作った操縦の動き（mascot_pilot.glb の Pilot_SitIdle / Pilot_Wave / Pilot_Point / Pilot_Steer。
## assets/characters/aiquiz_mascot/source/build_pilot.py）を AnimationPlayer で 0.25 秒つないで再生する。
## 頭の向き（head_side）は動きの上に足す。ヘッドセット（pilot_headset.glb）は頭の骨に付ける。
## 動きの GLB がないときは、同じ骨の向き（設計図の HATENA_SEATED）を手で当てて座らせる。
##
## 使い方：ヘリのモデルの子にして、目印 MK_SeatPilot に置く（OnlineHeliportHelicopter がする）。
##   play(&"wave") / play(&"point") / play(&"steer") / play(&"sit_idle")、head_side（-1＝プレイヤーの側〜1）

const MASCOT_GLB := "res://assets/characters/aiquiz_mascot/mascot_model.glb"
const MASCOT_LOD_GLB := "res://assets/characters/aiquiz_mascot/mascot_model_lod.glb"
const PILOT_ANIM_GLB := "res://assets/characters/aiquiz_mascot/mascot_pilot.glb"
const HEADSET_GLB := "res://assets/characters/aiquiz_mascot/pilot_headset.glb"
const BLEND_SECONDS := 0.25
const ACTIONS := {&"sit_idle": "Pilot_SitIdle", &"wave": "Pilot_Wave", &"point": "Pilot_Point", &"steer": "Pilot_Steer"}
const LOOPED := ["Pilot_SitIdle", "Pilot_Wave", "Pilot_Steer"]

## 骨の向き（ハテナの空間：前が +Z、左が +X）。動きの GLB がないときに使う。設計図の HATENA_SEATED
const SEATED := {
	"DEF-thigh.L": Vector3(0.05, 0.16, 1.0), "DEF-thigh.R": Vector3(-0.05, 0.16, 1.0),
	"DEF-shin.L": Vector3(0.04, 0.02, 1.0), "DEF-shin.R": Vector3(-0.04, 0.02, 1.0),
	"DEF-foot.L": Vector3(0.0, 0.95, 0.30), "DEF-foot.R": Vector3(0.0, 0.95, 0.30),
	"DEF-upper_arm.L": Vector3(0.42, -0.30, 0.86), "DEF-upper_arm.R": Vector3(-0.42, -0.30, 0.86),
	"DEF-forearm.L": Vector3(0.05, 0.12, 1.0), "DEF-forearm.R": Vector3(-0.05, 0.12, 1.0),
}

var skeleton: Skeleton3D = null
var player: AnimationPlayer = null
var action: StringName = &"sit_idle"
## 頭の向き（-1 で左＝プレイヤーの側、+1 で右。0.6 秒でゆっくり向く）
var head_side := 0.0
## 品質「低」は軽い版（8,000 三角形）
var use_lod := false

var _model: Node3D = null
var _time := 0.0
var _head := 0.0
var _head_bone := -1
var _rest_rot: Array[Quaternion] = []
var _rest_pos: Array[Vector3] = []
var _child_offset: Array[Vector3] = []
var _bone_names: Array[String] = []


func setup() -> bool:
	var path := MASCOT_LOD_GLB if use_lod and ResourceLoader.exists(MASCOT_LOD_GLB) else MASCOT_GLB
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	_model = packed.instantiate() as Node3D if packed != null else null
	if _model == null:
		return false
	_model.name = "Mascot"
	add_child(_model)
	for body_node: Node in _model.find_children("*", "CollisionObject3D", true, false):
		var body := body_node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	var found := _model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if skeleton == null:
		return false
	_head_bone = skeleton.find_bone("DEF-head")
	_cache_rest()
	_mount_headset()
	_setup_player()
	_apply(0.0)
	return true


func play(next: StringName) -> void:
	if next == action and (player == null or player.is_playing()):
		return
	action = next
	if player != null:
		var clip: String = ACTIONS.get(next, "Pilot_SitIdle")
		if player.has_animation(clip):
			player.play(clip, BLEND_SECONDS)


func is_animated() -> bool:
	return player != null


func _process(delta: float) -> void:
	if skeleton == null:
		return
	_time += delta
	_apply(delta)


func _setup_player() -> void:
	if not ResourceLoader.exists(PILOT_ANIM_GLB):
		return
	var packed := load(PILOT_ANIM_GLB) as PackedScene
	var source := packed.instantiate() if packed != null else null
	if source == null:
		return
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		source.free()
		return
	var library := AnimationLibrary.new()
	for clip_name: StringName in source_player.get_animation_list():
		var clip := source_player.get_animation(clip_name).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_LINEAR if String(clip_name) in LOOPED else Animation.LOOP_NONE
		library.add_animation(clip_name, clip)
	source.free()
	player = AnimationPlayer.new()
	player.name = "PilotAnimation"
	_model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", library)
	# 頭の向きを動きの上に足すため、進めるのはこのスクリプト（_apply）が行う
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if player.has_animation("Pilot_SitIdle"):
		player.play("Pilot_SitIdle")
		player.seek(randf() * 3.0, true)


func _apply(delta: float) -> void:
	_head = move_toward(_head, clampf(head_side, -1.0, 1.0), delta / 0.6) if delta > 0.0 else head_side
	if player != null:
		player.advance(delta)
		# ハテナの空間の +X（ヘリでは左＝プレイヤーの側）を向くのが +Y 回りの正の角度
		if _head_bone >= 0 and absf(_head) > 0.001:
			var current := skeleton.get_bone_pose_rotation(_head_bone)
			skeleton.set_bone_pose_rotation(_head_bone, current * Quaternion(Vector3.UP, deg_to_rad(-25.0) * _head))
		return
	_pose_aims(SEATED)


func _cache_rest() -> void:
	var count := skeleton.get_bone_count()
	_rest_rot.resize(count)
	_rest_pos.resize(count)
	_child_offset.resize(count)
	_bone_names.resize(count)
	for b in range(count):
		var rest := skeleton.get_bone_rest(b)
		_rest_rot[b] = rest.basis.get_rotation_quaternion()
		_rest_pos[b] = rest.origin
		_bone_names[b] = skeleton.get_bone_name(b)
		_child_offset[b] = Vector3(0, 0.1, 0)
	for b in range(count):
		var parent := skeleton.get_bone_parent(b)
		if parent >= 0 and _child_offset[parent] == Vector3(0, 0.1, 0):
			_child_offset[parent] = _rest_pos[b]


## 動きの GLB がないとき：骨を親から順に、根元から子の骨への向きが aims の向きになるよう回す（設計図の HatenaRig.pose と同じ）。
func _pose_aims(aims: Dictionary) -> void:
	var count := skeleton.get_bone_count()
	var global: Array[Transform3D] = []
	global.resize(count)
	for b in range(count):
		var parent := skeleton.get_bone_parent(b)
		var pg := global[parent] if parent >= 0 else Transform3D.IDENTITY
		var rot := _rest_rot[b]
		var g := pg * Transform3D(Basis(rot), _rest_pos[b])
		var name := _bone_names[b]
		if aims.has(name):
			var want := g.basis.inverse() * (aims[name] as Vector3).normalized()
			var from := _child_offset[b].normalized()
			if want.length_squared() > 1e-6 and from.length_squared() > 1e-6:
				rot = rot * Quaternion(from, want.normalized())
				g = pg * Transform3D(Basis(rot), _rest_pos[b])
		elif b == _head_bone:
			rot = rot * Quaternion(Vector3.UP, deg_to_rad(-25.0) * _head)
			g = pg * Transform3D(Basis(rot), _rest_pos[b])
		global[b] = g
		skeleton.set_bone_pose_rotation(b, rot)
		skeleton.set_bone_pose_position(b, _rest_pos[b])


## ヘッドセット（Blender で作った小さな GLB。ハテナの空間で作ってある）を頭の骨に付ける。
func _mount_headset() -> void:
	if not ResourceLoader.exists(HEADSET_GLB) or _head_bone < 0:
		return
	var packed := load(HEADSET_GLB) as PackedScene
	var headset := packed.instantiate() as Node3D if packed != null else null
	if headset == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "HeadsetMount"
	attach.bone_name = "DEF-head"
	skeleton.add_child(attach)
	attach.add_child(headset)
	headset.name = "Pilot_Headset"
	headset.transform = skeleton.get_bone_global_rest(_head_bone).affine_inverse()
