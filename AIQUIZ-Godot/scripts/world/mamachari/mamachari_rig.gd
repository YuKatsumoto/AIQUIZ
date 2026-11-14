extends Node3D
class_name MamachariRig

## ママチャリ（シークレットの乗り物）の見た目と可動部。
## プレイヤーの入れ物（PlayerController 本体か Player2）の子に置き、足もと（床）を原点にする。
## 進んだ距離・ハンドルの切れ角などを受け取り、車輪・クランク・ペダル・ハンドル・スタンドを動かす。
## 当たり判定は持たない（見た目だけ）。乗り手の姿勢は MamachariRider が、ここの位置を使って解く。

const MODEL: PackedScene = preload("res://assets/vehicles/mamachari/mamachari.glb")

## モデルは実寸（26インチ）。箱人形は身長 約2.2 m と大柄なので、自転車を大きくして釣り合わせる。
## サドルをいちばん下まで下げたモデルで、脚が下死点のペダルにちょうど届く倍率。
const MODEL_SCALE := 1.3
const WHEEL_RADIUS := 0.332 * MODEL_SCALE
## クランク1回転で後輪が回る数（前 32T ÷ 後 14T）。
const GEAR_RATIO := 2.3
const MAX_STEER := deg_to_rad(32.0)
## 両立スタンドを下ろしきった角度（足が床に付く）。
const STAND_DOWN_ANGLE := deg_to_rad(-62.0)
const BRAKE_LEVER_PULL := deg_to_rad(14.0)
## レバーの先がグリップへ近づく回転の軸（レバー自身の座標）。
const BRAKE_AXIS_LEFT := Vector3(0.927, 0.248, 0.281)
const BRAKE_AXIS_RIGHT := Vector3(0.927, -0.248, -0.281)
const SADDLE_SAG_MAX := 0.02

## モデルの座標（Godot の向き。前 +Z・上 +Y・乗り手の左 +X。単位はモデルの実寸）。
## 坐骨が乗るサドルの上面、グリップの中心、グリップの半径。
const SEAT_POINT := Vector3(0.0, 0.832, -0.2725)
const GRIP_POINT := Vector3(0.261, 1.032, 0.190)
const GRIP_RADIUS := 0.0165

const PART_NAMES: Array[StringName] = [
	&"Steer", &"FrontWheel", &"RearWheel", &"Crank", &"PedalL", &"PedalR", &"Stand", &"Saddle",
	&"BrakeLeverL", &"BrakeLeverR", &"Frame", &"FenderFront", &"FenderRear", &"ChainCase", &"Basket",
]

## 車輪の回転（ラジアン。前へ転がると増える）とクランクの回転。
var wheel_angle: float = 0.0
var crank_angle: float = 0.0
## ハンドルの切れ角（ラジアン。正 = 乗り手の左）。
var steer: float = 0.0
## スタンド（0 = 上げた、1 = 下ろした）。
var stand: float = 0.0
## ブレーキレバーの握り（0〜1）。
var brake_left: float = 0.0
var brake_right: float = 0.0
## サドルのばねの沈み（0〜1）。
var saddle_sag: float = 0.0

var _model: Node3D
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
## 部品の、モデルの根もとから見た静止時の変換（グリップなどを部品の座標へ移すのに使う）。
var _rest_in_model: Dictionary = {}


func _init() -> void:
	name = "MamachariRig"
	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	for part: StringName in PART_NAMES:
		var node := _model.find_child(String(part), true, false) as Node3D
		if node == null:
			push_warning("[MamachariRig] 部品 %s がモデルにありません。" % part)
			continue
		_nodes[part] = node
		_rest[part] = node.transform
	for part: StringName in _nodes:
		_rest_in_model[part] = _transform_in_model(_nodes[part])


func has_part(part: StringName) -> bool:
	return _nodes.has(part)


func part(part_name: StringName) -> Node3D:
	return _nodes.get(part_name) as Node3D


## 進んだぶんだけ車輪を回す。pedaling のあいだはクランクも回る（こがないときは空回り＝止まる）。
func advance(distance: float, pedaling: bool) -> void:
	var turned := distance / WHEEL_RADIUS
	wheel_angle = wrapf(wheel_angle + turned, 0.0, TAU)
	if pedaling:
		crank_angle = wrapf(crank_angle + turned / GEAR_RATIO, 0.0, TAU)


## いまの値を部品に反映する。
func apply() -> void:
	_rotate(&"FrontWheel", Vector3.RIGHT, wheel_angle)
	_rotate(&"RearWheel", Vector3.RIGHT, wheel_angle)
	_rotate(&"Crank", Vector3.RIGHT, crank_angle)
	# ペダルはクランクと逆に回して、ふむ面を水平に保つ。
	_rotate(&"PedalL", Vector3.RIGHT, -crank_angle)
	_rotate(&"PedalR", Vector3.RIGHT, -crank_angle)
	_rotate(&"Steer", Vector3.UP, clampf(steer, -MAX_STEER, MAX_STEER))
	_rotate(&"Stand", Vector3.RIGHT, STAND_DOWN_ANGLE * clampf(stand, 0.0, 1.0))
	_rotate(&"BrakeLeverL", BRAKE_AXIS_LEFT.normalized(), BRAKE_LEVER_PULL * clampf(brake_left, 0.0, 1.0))
	_rotate(&"BrakeLeverR", BRAKE_AXIS_RIGHT.normalized(), BRAKE_LEVER_PULL * clampf(brake_right, 0.0, 1.0))
	var saddle := part(&"Saddle")
	if saddle != null:
		var rest: Transform3D = _rest[&"Saddle"]
		saddle.transform = Transform3D(rest.basis, rest.origin + Vector3.DOWN * SADDLE_SAG_MAX * clampf(saddle_sag, 0.0, 1.0))


## ペダルの軸の中心（このリグの親の座標）。right = 乗り手の右（-X 側）。
func pedal_position(right: bool) -> Vector3:
	var pedal := part(&"PedalR" if right else &"PedalL")
	if pedal == null:
		return transform.origin
	return transform * (_model.transform * _transform_in_model(pedal).origin)


## グリップの中心（このリグの親の座標）。ハンドルを切ると一緒に動く。
func grip_position(right: bool) -> Vector3:
	var point := GRIP_POINT
	if right:
		point.x = -point.x
	return _steer_point(point)


## グリップの向き（後ろの端 → 前。このリグの親の座標での単位ベクトル）。
func grip_axis(right: bool) -> Vector3:
	var back := GRIP_POINT + Vector3(0.004, -0.002, -0.06)
	var front := GRIP_POINT + Vector3(-0.004, 0.002, 0.06)
	if right:
		back.x = -back.x
		front.x = -front.x
	return (_steer_point(front) - _steer_point(back)).normalized()


## サドルの上面（坐骨が乗る所。このリグの親の座標）。ばねで沈むと一緒に下がる。
func seat_position() -> Vector3:
	var saddle := part(&"Saddle")
	if saddle == null:
		return transform * (_model.transform * SEAT_POINT)
	var local: Vector3 = (_rest_in_model[&"Saddle"] as Transform3D).affine_inverse() * SEAT_POINT
	return transform * (_model.transform * (_transform_in_model(saddle) * local))


## 自転車の向き（このリグの親の座標。大きさを含まない）。
func frame_basis() -> Basis:
	return transform.basis.orthonormalized()


func grip_radius() -> float:
	return GRIP_RADIUS * MODEL_SCALE


func _steer_point(model_point: Vector3) -> Vector3:
	var steer_node := part(&"Steer")
	if steer_node == null:
		return transform * (_model.transform * model_point)
	var local: Vector3 = (_rest_in_model[&"Steer"] as Transform3D).affine_inverse() * model_point
	return transform * (_model.transform * (_transform_in_model(steer_node) * local))


func _rotate(part_name: StringName, axis: Vector3, angle: float) -> void:
	var node := part(part_name)
	if node == null:
		return
	var rest: Transform3D = _rest[part_name]
	node.transform = Transform3D(rest.basis * Basis(axis, angle), rest.origin)


## 部品の、モデルの根もと（大きさを掛ける前）から見た変換。
func _transform_in_model(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != _model:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result
