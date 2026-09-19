extends SceneTree

const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Godot's dummy RenderingServer does not preserve the MultiMesh getters this
	# validation needs. Use an isolated offscreen graphical process, not --headless.
	if DisplayServer.get_name() == "headless":
		push_error("Seating validation requires a real rendering backend for MultiMesh readback")
		quit(2)
		return
	var counts: Array[int] = []
	var inspected: int = 0
	for side: int in [-1, 1]:
		var stand := Node3D.new()
		root.add_child(stand)
		stand.position.x = float(side) * 28.0
		stand.rotation.y = PI if side < 0 else 0.0
		var crowd := CrowdScript.new()
		stand.add_child(crowd)
		var seed_value: int = 1729 if side < 0 else 7919
		crowd.build(0.85, seed_value)
		counts.append(crowd.spectator_count)
		var initial: Array = _snapshot(crowd)
		crowd.build(0.85, seed_value)
		_expect(initial == _snapshot(crowd), "Rebuilding changed seeded spectators")
		var poses := {}
		var colors := {}
		var rows := {}
		for scale_z: float in [0.5, 1.0, 2.5]:
			stand.scale.z = scale_z
			crowd.sync_length_scale(scale_z)
			for data: Dictionary in crowd._batches:
				var batch: MultiMeshInstance3D = data["node"]
				poses[String(batch.name).right(1)] = true
				for index: int in range(batch.multimesh.instance_count):
					var rest: Transform3D = data["people"][index]["transform"]
					var row: int = roundi((rest.origin.x - 1.15) / 1.25)
					rows[row] = true
					_expect(row >= 0 and row < 4, "Spectator lies outside the four rows")
					_expect(is_equal_approx(rest.origin.y, 0.865 + float(row) * 0.4), "Spectator floats above or inside its chair")
					_expect(not CrowdScript._is_aisle(rest.origin.z), "Spectator blocks an aisle")
					var local: Transform3D = batch.multimesh.get_instance_transform(index)
					var world: Transform3D = batch.global_transform * local
					_expect(world.origin.is_equal_approx(stand.global_transform * rest.origin), "Crowd drifted off scaled seat grid")
					_expect(is_equal_approx(world.basis.x.length(), 1.0) and is_equal_approx(world.basis.y.length(), 1.0) and is_equal_approx(world.basis.z.length(), 1.0), "Course length distorted a spectator body")
					_expect(world.basis.z.dot(Vector3.LEFT * float(side)) > 0.99, "Spectator faces away from the course")
					_expect(batch.custom_aabb.has_point(local.origin), "Crowd bounds omit an occupied chair")
					colors[batch.multimesh.get_instance_color(index).to_html()] = true
					inspected += 1
		_expect(rows.size() == 4, "A seating row is empty")
		_expect(poses.size() == 3, "Animated spectator pose variety was lost")
		_expect(colors.size() == 8, "Spectator shirt color diversity was lost")
		stand.free()
	var report := {"passed": failures.is_empty(), "failures": failures,
		"spectators_per_side": counts, "inspected_scaled_placements": inspected,
		"tested_length_scales": [0.5, 1.0, 2.5], "seeds": [1729, 7919],
		"checks": ["seeded rebuild", "four rows", "seat heights", "aisle clearance", "scaled seat alignment", "body proportions", "course facing on both sides", "batch bounds", "three poses", "eight clothing colors"],
		"display_server": DisplayServer.get_name(),
		"scope": "Isolated graphical structural runtime; rendered gameplay and animation evidence are separate."}
	var output := FileAccess.open("res://assets/environment/santorini_grandstand/seating_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("SANTORINI_SEATING_VALIDATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, failure: String) -> void:
	if not condition and failure not in failures:
		failures.append(failure)


func _snapshot(crowd: Node3D) -> Array:
	var snapshot: Array = []
	for data: Dictionary in crowd._batches:
		snapshot.append(data["people"].duplicate(true))
	return snapshot
