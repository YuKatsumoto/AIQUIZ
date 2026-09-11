extends Node3D

## 分離済みのキリン頭部だけを、現在表示しているプレイヤーカメラへ向け続ける。

const PLAYER_FACE_FALLBACK_FROM_MOUNT := Vector3(0.0, -0.22, 0.14)

var _hat_mount: Node3D


func _ready() -> void:
	process_priority = 100
	_hat_mount = _find_hat_mount()
	_update_gaze()


func _process(_delta: float) -> void:
	if not is_instance_valid(_hat_mount):
		_hat_mount = _find_hat_mount()
	_update_gaze()


func _update_gaze() -> void:
	if _hat_mount == null or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	var target := (
		camera.global_position
		if camera != null
		else _hat_mount.to_global(PLAYER_FACE_FALLBACK_FROM_MOUNT)
	)
	var owner_up := _hat_mount.global_basis.y.normalized()
	var to_target := target - global_position
	if to_target.length_squared() < 0.000001:
		return
	if absf(to_target.normalized().dot(owner_up)) > 0.999:
		return
	# このFBXの顔はローカル +Z 側なので、model_front=true で注視方向を合わせる。
	look_at(target, owner_up, true)


func _find_hat_mount() -> Node3D:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Node3D and ancestor.name == &"HatMount":
			return ancestor as Node3D
		ancestor = ancestor.get_parent()
	return null
