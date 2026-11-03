@tool
extends RefCounted

func run(ctx) -> void:
	var info: Dictionary = ctx.get_import_info()
	ctx.log("importer=%s valid=%s" % [info.get("importer", ""), info.get("import_valid", false)])
	var root: Node = ctx.instantiate_imported_scene()
	if root == null:
		ctx.error("Could not instantiate optimized grandstand")
		return
	var mesh_count: int = 0
	var vertices: int = 0
	var triangles: int = 0
	var bounds := AABB()
	var has_bounds: bool = false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_count += 1
		var local_bounds: AABB = mesh_instance.transform * mesh_instance.mesh.get_aabb()
		bounds = local_bounds if not has_bounds else bounds.merge(local_bounds)
		has_bounds = true
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertices += surface_vertices.size()
			triangles += floori(float(indices.size()) / 3.0)
	ctx.log("meshes=%d vertices=%d triangles=%d bounds=%s" % [mesh_count, vertices, triangles, str(bounds)])
