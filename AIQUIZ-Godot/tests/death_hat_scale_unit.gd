extends Node

## 爆散した帽子の破片が、物理で剛体の scale が捨てられたあとも
## 被っていたときと同じ大きさのままかを確かめる。

const HATS := [HatData.HAT_SOMBRERO, HatData.HAT_TOP_HAT, HatData.HAT_CAP, HatData.HAT_CROWN]
const SCALE_TOLERANCE := 0.02

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40.0, 1.0, 40.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	var pc := PlayerController.new()
	add_child(pc)
	await get_tree().process_frame

	for hat_id: int in HATS:
		pc.set_hat(1, hat_id)
		await get_tree().physics_frame
		var parts: Dictionary = pc.p1_parts
		var hat_meshes: Array = parts.get("hat_meshes", [])
		if hat_meshes.is_empty():
			failures.append("hat %d has meshes" % hat_id)
			continue
		var worn_scales: Array[float] = []
		for mesh: MeshInstance3D in hat_meshes:
			worn_scales.append(mesh.global_transform.basis.get_scale().x)
		pc._init_explosion(parts, true)
		var bodies: Array[RigidBody3D] = pc._p1_explosion_bodies
		var hat_pieces := bodies.slice(bodies.size() - hat_meshes.size())
		for _i in range(20):
			await get_tree().physics_frame
		for index: int in range(hat_pieces.size()):
			var piece := hat_pieces[index] as RigidBody3D
			if not is_instance_valid(piece):
				continue
			var visual: MeshInstance3D = null
			for child in piece.get_children():
				if child is MeshInstance3D:
					visual = child
			var shown := visual.global_transform.basis.get_scale().x
			var worn := worn_scales[index]
			print("hat %d piece %d worn=%s shown=%s local=%s body=%s" % [
				hat_id, index, worn, shown,
				(hat_meshes[index] as MeshInstance3D).scale.x,
				piece.global_transform.basis.get_scale().x,
			])
			if absf(shown - worn) > maxf(SCALE_TOLERANCE * worn, 0.0005):
				failures.append("hat %d piece %d keeps its worn size (%.4f -> %.4f)" % [hat_id, index, worn, shown])
		pc._clear_explosion_bodies(true)
		pc._p1_exploding = false
		pc._set_parts_visible(parts, true)

	if failures.is_empty():
		print("DEATH_HAT_SCALE_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
		get_tree().quit(1)
