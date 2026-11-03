@tool
extends RefCounted

func run(ctx) -> void:
	var info: Dictionary = ctx.get_import_info()
	ctx.log("importer=%s class=%s valid=%s" % [info.get("importer", ""), info.get("resource_class", ""), info.get("import_valid", false)])
	ctx.log("options=%s" % str(ctx.list_import_options("meshes/")))
	var root: Node = ctx.instantiate_imported_scene()
	if root == null:
		ctx.error("Could not instantiate grandstand")
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
		var mesh := mesh_instance.mesh
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertices += surface_vertices.size()
			triangles += indices.size() / 3 if not indices.is_empty() else surface_vertices.size() / 3
	ctx.log("meshes=%d vertices=%d triangles=%d bounds=%s" % [mesh_count, vertices, triangles, str(bounds)])
