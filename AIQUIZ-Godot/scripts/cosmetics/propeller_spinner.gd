extends Node3D

## プロペラ帽の羽根をローカル Y 軸まわりに常時回転させる
const SPIN_SPEED_RAD := 15.708  # 2.5 回転/秒

func _process(delta: float) -> void:
	rotate_object_local(Vector3.UP, SPIN_SPEED_RAD * delta)
