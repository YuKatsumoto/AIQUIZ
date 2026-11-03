@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node = ctx.instantiate_imported_scene()
	if root == null:
		ctx.error("Could not instantiate shark asset")
		return
	var mesh_instance: MeshInstance3D = root.find_child("SK_Shark_001", true, false) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		ctx.log("mesh=none")
		return
	ctx.log("mesh_class=%s surfaces=%d blend_shapes=%d" % [mesh_instance.mesh.get_class(), mesh_instance.mesh.get_surface_count(), mesh_instance.mesh.get_blend_shape_count()])
	var names: PackedStringArray = PackedStringArray()
	for index: int in range(mesh_instance.mesh.get_blend_shape_count()):
		names.append(mesh_instance.mesh.get_blend_shape_name(index))
	ctx.log("blend_shape_names=%s" % str(names))