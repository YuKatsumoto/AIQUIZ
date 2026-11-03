extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
	var stage: Node = root.get_node_or_null("StageEnvironment")
	if stage == null:
		ctx.error("no stage")
		return
	var gs: Node = stage.get_node_or_null("Grandstands")
	if gs == null:
		ctx.error("no grandstands")
		return
	var total_surfaces: int = 0
	var total_verts: int = 0
	var total_indices: int = 0
	var listed: int = 0
	var stack: Array[Node] = [gs]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh != null:
				var surf_count: int = mesh.get_surface_count()
				var local_verts: int = 0
				var local_idx: int = 0
				for s: int in range(surf_count):
					var arrays: Array = mesh.surface_get_arrays(s)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var indices: Variant = arrays[Mesh.ARRAY_INDEX]
					local_verts += verts.size()
					if indices is PackedInt32Array:
						local_idx += (indices as PackedInt32Array).size()
					elif indices is PackedInt64Array:
						local_idx += (indices as PackedInt64Array).size()
				total_surfaces += surf_count
				total_verts += local_verts
				total_indices += local_idx
				if listed < 12:
					ctx.log("mesh name=%s surfaces=%d verts=%d indices=%d visible=%s" % [
						String(mi.name), surf_count, local_verts, local_idx, str(mi.visible)
					])
					listed += 1
		for c: Node in n.get_children():
			stack.append(c)
	var tris: int = total_indices / 3 if total_indices > 0 else 0
	ctx.log("grandstand totals: surfaces=%d verts=%d indices=%d approx_tris=%d" % [
		total_surfaces, total_verts, total_indices, tris
	])
	var ocean: MeshInstance3D = stage.get_node_or_null("Ocean") as MeshInstance3D
	if ocean != null and ocean.mesh != null:
		var omesh: Mesh = ocean.mesh
		var oarrays: Array = omesh.surface_get_arrays(0)
		var overts: PackedVector3Array = oarrays[Mesh.ARRAY_VERTEX]
		var oidx: Variant = oarrays[Mesh.ARRAY_INDEX]
		var oidx_count: int = 0
		if oidx is PackedInt32Array:
			oidx_count = (oidx as PackedInt32Array).size()
		ctx.log("ocean verts=%d indices=%d subdiv_hint=%s" % [
			overts.size(), oidx_count, str(omesh)
		])
	var light: DirectionalLight3D = stage.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light != null:
		ctx.log("shadow_enabled=%s" % str(light.shadow_enabled))
	ctx.close_scene()
