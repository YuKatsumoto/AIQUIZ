class_name OnlineSkinCloseup
extends Node

## オンライン画面の「スキン設定」のあいだ、立っている自分のキャラへカメラを寄せ、キャラをカメラの方へ向かせる。
## カメラと待機のポーズは監督（OnlineStagingDirector）が毎フレーム決めるので、このノードは
## process_priority で監督のあとに動き、その上から重ねる（監督のファイルにはさわらない）。
## 効くのは待機（IDLE）のときだけ。active を false にすると、なめらかに監督のカメラへ戻る。

const BLEND_SECONDS := 0.5
## キャラの胸からカメラまでの水平距離と高さ（m）
const DISTANCE := 5.2
const HEIGHT := 0.7
const FOV := 40.0
## 左の列（ページ）にかからないよう、キャラを画面の右寄り（横幅のこの位置）に映す
const SCREEN_X := 0.71
## 見る高さ（胸より少し上。帽子まで入るように）
const LOOK_RAISE := 0.1

var stage: OnlineHeliportStage = null
var director: OnlineStagingDirector = null
var active := false
var _weight := 0.0


func _init() -> void:
	name = "SkinCloseup"
	process_priority = 100


## 寄りきったか（テスト用）。
func weight() -> float:
	return _weight


func _process(delta: float) -> void:
	if stage == null or director == null or stage.camera == null:
		return
	if director.state != OnlineStagingDirector.State.IDLE:
		_weight = 0.0
		return
	_weight = move_toward(_weight, 1.0 if active else 0.0, delta / BLEND_SECONDS)
	if _weight <= 0.0:
		return
	var me := stage.me()
	if me == null or not me.is_ready():
		return
	var blend := _weight * _weight * (3.0 - 2.0 * _weight)
	var camera := stage.camera
	# 監督が置いたカメラの方向（水平）から、キャラの正面へ回り込む
	var away := camera.global_position - me.center()
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.BACK
	_turn_to(me, atan2(away.x, away.z), blend)
	var chest := me.center() + Vector3.UP * LOOK_RAISE
	var eye := chest + away * DISTANCE + Vector3.UP * HEIGHT
	var forward := (chest - eye).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var view := camera.get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var half_width := tan(deg_to_rad(FOV) * 0.5) * aspect * eye.distance_to(chest)
	# 注視点を左へずらすと、キャラは画面の右寄りに映る
	var look := chest - right * (SCREEN_X - 0.5) * 2.0 * half_width
	var close := Basis.looking_at(look - eye, Vector3.UP).get_rotation_quaternion()
	var base := camera.global_transform
	camera.global_transform = Transform3D(
		Basis(base.basis.get_rotation_quaternion().slerp(close, blend)),
		base.origin.lerp(eye, blend),
	)
	camera.fov = lerpf(camera.fov, FOV, blend)
	camera.h_offset = lerpf(camera.h_offset, 0.0, blend)
	camera.v_offset = lerpf(camera.v_offset, 0.0, blend)
	# 監督のピントは遠くのヘリ向き。寄っているあいだは手前のぼけを切る
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes != null and blend > 0.5:
		attributes.dof_blur_near_enabled = false
		attributes.dof_blur_far_enabled = false


## 監督が決めた向きから、カメラの方（yaw）へ blend だけ回す。腰を軸に回すので足の位置は変わらない。
func _turn_to(me: StagingPuppet, yaw: float, blend: float) -> void:
	var pelvis := me.parts().get("pelvis") as Node3D
	if pelvis == null:
		return
	var facing := pelvis.global_basis.z
	var current := atan2(facing.x, facing.z)
	var turn := wrapf(yaw - current, -PI, PI) * blend
	pelvis.global_transform = Transform3D(Basis(Vector3.UP, turn) * pelvis.global_basis, pelvis.global_position)
