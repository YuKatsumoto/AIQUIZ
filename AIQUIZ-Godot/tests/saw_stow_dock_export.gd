extends SceneTree
## Service-vessel triangles around the stowed davit towers while the vessel raises and transfers the
## carriage, in the carriage's Blender frame (x across, y forward, z up). Read by the "transport"
## stage of tools/saw_stow/build_stow.py, which tests them against the real tower meshes.
const OUT := "res://artifacts/saw_stow/v2/dock/"
const BOX_ABS_X := Vector2(11.5, 13.1)
const BOX_ABS_Y := Vector2(0.8, 2.5)
const BOX_Z := Vector2(-0.3, 2.9)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var saw = load("res://scripts/world/saw_chase_controller.gd").new()
	root.add_child(saw)
	saw.configure_entrance(false, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var times: Array[float] = []
	for i in range(23, 44, 2): times.append(i / 10.0) # raising 2.3 .. 4.3
	for i in range(44, 63): times.append(i / 10.0) # transfer 4.4 .. 6.2
	var index: Array = []
	var blob := PackedFloat32Array()
	for time in times:
		saw.dock.elapsed = time
		saw.dock.apply_pose()
		var inverse := Transform3D(saw.dock.carriage_basis(), saw.dock.carriage_position()).affine_inverse()
		var owners: Array = []
		var count := 0
		for node: Node in saw.dock.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree(): continue
			var to_carriage := inverse * mesh_instance.global_transform
			var kept := 0
			for surface: int in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					indices.resize(vertices.size())
					for i: int in vertices.size(): indices[i] = i
				var local := PackedVector3Array()
				local.resize(vertices.size())
				for i: int in vertices.size():
					# Saw-node frame -> Blender carriage frame: the model is turned PI about Y and
					# glTF maps Blender (x, y, z) to (x, z, -y).
					var s: Vector3 = to_carriage * vertices[i]
					local[i] = Vector3(-s.x, s.z, s.y)
				for t: int in range(0, indices.size() - 2, 3):
					var a := local[indices[t]]
					var b := local[indices[t + 1]]
					var c := local[indices[t + 2]]
					if not _near(a, b, c): continue
					blob.append_array(PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]))
					kept += 1
			if kept > 0:
				owners.append([str(saw.dock.get_path_to(mesh_instance)), kept])
				count += kept
		index.append({"time": time, "triangles": count, "owners": owners})
	var bin := FileAccess.open(OUT + "dock_tris.bin", FileAccess.WRITE)
	bin.store_buffer(blob.to_byte_array())
	bin.close()
	FileAccess.open(OUT + "dock_tris.json", FileAccess.WRITE).store_string(JSON.stringify(index, "\t"))
	print("SAW_STOW_DOCK_EXPORT ", JSON.stringify(index.map(func(r: Dictionary) -> Array: return [r.time, r.triangles])))
	quit()

static func _near(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var low := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
	var high := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
	if high.z < BOX_Z.x or low.z > BOX_Z.y: return false
	var x_ok := (high.x >= BOX_ABS_X.x and low.x <= BOX_ABS_X.y) or (low.x <= -BOX_ABS_X.x and high.x >= -BOX_ABS_X.y)
	var y_ok := (high.y >= BOX_ABS_Y.x and low.y <= BOX_ABS_Y.y) or (low.y <= -BOX_ABS_Y.x and high.y >= -BOX_ABS_Y.y)
	return x_ok and y_ok
