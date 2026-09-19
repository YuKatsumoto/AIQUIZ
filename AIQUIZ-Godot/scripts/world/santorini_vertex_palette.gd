@tool
extends Node3D

## glTF shares the opaque palette across many surfaces. Godot can disable the
## vertex-color flag and fold a surface color into the shared material albedo.
## COLOR_0 already contains the complete palette; keep its material multiplier neutral.
func _ready() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in range(instance.mesh.get_surface_count()):
			var material := instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name.begins_with("Santorini Vertex Palette"):
				material.vertex_color_use_as_albedo = true
				material.albedo_color = Color.WHITE
