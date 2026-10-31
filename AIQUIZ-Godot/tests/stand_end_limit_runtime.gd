extends Node

## 左右の客席が、ゴール観客席のモニターより奥へ出ないこと。
##   Godot --headless --path . --script tests/stand_end_limit_bootstrap.gd

const StageScript = preload("res://scripts/world/stage_environment.gd")

var errors: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not errors.has(message):
		errors.append(message)
		push_error(message)


func _run() -> void:
	var stage: Node3D = StageScript.new()
	get_tree().root.add_child(stage)
	var config: Dictionary = stage.gameplay_build_config()
	config.floor_center_z = 60.0
	config.floor_length = 150.0
	stage.build(config)
	var stands := stage.get_node("Grandstands") as Node3D

	# 制限なしなら全ブロックが見える。
	for stand: Node3D in stands.get_children():
		check(_visible_blocks(stand).size() == stand.block_count, "%s: 制限なしで全ブロックが見える" % stand.name)

	# ゴール観客席のモニターの位置（原点からの奥行き）が測れる。
	var goal := GoalStand.new()
	get_tree().root.add_child(goal)
	goal.setup("balanced")
	goal.position = Vector3(0.0, -1.2, 100.0)
	var offset: float = goal.monitor_z_offset()
	print("monitor_z_offset = %.2f" % offset)
	check(offset > 0.0 and offset < 20.0, "モニターはゴール観客席の原点より奥にある (%.2f)" % offset)
	check(is_equal_approx(goal.monitor_z_offset(), offset), "モニターの奥行きは変わらない")

	# 制限を手前に引くと、前端のキャップがちょうど制限で終わる位置まで下がり、その手前のブロックは
	# キャップの始まりで切られ、間のブロックは座席ごと隠れる（モニターまで途切れずに続く）。
	var limit: float = 85.0
	stage.set_grandstand_end_limit(limit)
	for stand: Node3D in stands.get_children():
		_check_fitted(stand, limit, "制限 %.1f" % limit)

	# ゴールが近づいて制限が動いても（ブロックの途中でも）同じ。
	limit = 71.3
	stage.set_grandstand_end_limit(limit)
	for stand: Node3D in stands.get_children():
		_check_fitted(stand, limit, "制限 %.1f" % limit)

	# 床が伸びて新しいブロックが増えても、制限で終わったまま。
	stage.set_floor_geometry(100.0, 230.0)
	for stand: Node3D in stands.get_children():
		_check_fitted(stand, limit, "増えたあと")

	# 制限を外すと全ブロックが元の場所に戻り、切られたブロックもなくなる。
	stage.set_grandstand_end_limit(INF)
	for stand: Node3D in stands.get_children():
		check(_visible_blocks(stand).size() == stand.block_count, "%s: 制限を外すと全ブロックが戻る" % stand.name)
		for block: MeshInstance3D in stand.get_node("Blocks").get_children():
			check(is_equal_approx(block.position.z, stand.block_center_z(block.get_index())), "%s %s: 元の場所に戻る" % [stand.name, block.name])
			check(block.get_surface_override_material(0) == null, "%s %s: 切られたままにならない" % [stand.name, block.name])

	# 客席が短すぎてキャップを下げられないときは、従来どおりはみ出すブロックだけを隠す。
	limit = stands.global_position.z + 30.0
	stage.set_grandstand_end_limit(limit)
	for stand: Node3D in stands.get_children():
		for block: Node3D in stand.get_node("Blocks").get_children():
			check(block.visible == (block.global_position.z + 10.0 <= limit), "%s %s: 短いときは丸ごと隠す" % [stand.name, block.name])

	if errors.is_empty():
		print("stand_end_limit: OK")
	get_tree().quit(0 if errors.is_empty() else 1)


func _check_fitted(stand: Node3D, limit: float, label: String) -> void:
	var crowd := stand.get_node("Spectators")
	var blocks: Array = stand.get_node("Blocks").get_children()
	var front := blocks[blocks.size() - 1] as MeshInstance3D
	check(front.visible, "%s %s: 前端のキャップは見える" % [stand.name, label])
	check(is_equal_approx(front.global_position.z + 10.0, limit), "%s %s: キャップの端 %.2f が制限で終わる" % [stand.name, label, front.global_position.z + 10.0])
	var cap_start: float = limit - 20.0
	var cut := 0
	for i: int in range(blocks.size() - 1):
		var block := blocks[i] as MeshInstance3D
		var start_z: float = stand.global_position.z + 20.0 * i
		var expect_visible: bool = start_z < cap_start
		check(block.visible == expect_visible, "%s %s %s: 始まり %.1f / キャップ %.1f" % [stand.name, label, block.name, start_z, cap_start])
		var batch := crowd.get_node_or_null(String(block.name)) as Node3D
		if batch != null:
			check(batch.visible == expect_visible, "%s %s %s の観客も同じ表示" % [stand.name, label, block.name])
		var is_cut: bool = expect_visible and start_z + 20.0 >= cap_start
		check((block.get_surface_override_material(0) != null) == is_cut, "%s %s %s: キャップと重なるブロックだけ切る" % [stand.name, label, block.name])
		if is_cut:
			cut += 1
			check(is_equal_approx(float(block.get_instance_shader_parameter(&"far_clip_z")), cap_start + 0.02), "%s %s: キャップの始まりで切る" % [stand.name, label])
			if batch != null:
				check(float(batch.get_instance_shader_parameter(&"far_clip_z")) < cap_start, "%s %s: 切った先の観客は消える" % [stand.name, label])
	check(cut == 1, "%s %s: 切るブロックは 1 つ (%d)" % [stand.name, label, cut])
	var cap_batch := crowd.get_node_or_null(String(front.name)) as Node3D
	if cap_batch != null:
		check(cap_batch.visible, "%s %s: キャップの観客も見える" % [stand.name, label])


func _visible_blocks(stand: Node3D) -> Array:
	return stand.get_node("Blocks").get_children().filter(func(block: Node) -> bool: return (block as Node3D).visible)
