@tool class_name PsxConversionDialog extends ConfirmationDialog

enum {
	CONVERT_NONE,
	CONVERT_OVERWRITE,
	CONVERT_CREATE_NEW,
}


const PSX_SUFFIX := "_psx"
const NATIVE_EXTENSIONS: PackedStringArray = [
	"tscn",
	"scn",
	"res",
]


static var MAT_DEFAULT: PsxMaterial3D:
	get: return load("res://addons/psx/materials/psx_mat_default.tres")
static var MAT_PLACEHOLDER: PsxMaterial3D:
	get: return load("res://addons/psx/materials/psx_mat_placeholder.tres")


static func path_is_psx(path: String) -> bool:
	return path.left(-path.get_extension().length() - 1).right(PSX_SUFFIX.length()).to_lower() == PSX_SUFFIX


static func resource_is_native(scene: Resource) -> bool:
	return scene.resource_path.get_extension() in NATIVE_EXTENSIONS

static func property_is_resource(prop: Dictionary) -> bool:
	if (
		prop[&"type"] != TYPE_OBJECT or
		not prop[&"usage"] & PROPERTY_USAGE_STORAGE
	):
		return false

	for type in prop[&"hint_string"].split(",", false):
		if ClassDB.is_parent_class(type, "Resource"):
			return true

	return false

static var IMPORT_DATA_REGEX := RegEx.create_from_string(r"(?m)^_subresources=\{(.*?)\}$")
const IMPORT_DATA_PATCH := "_subresources={%s}"

static func modify_resource_import_data(resource: Resource, data: Dictionary, template: Resource = resource) -> void:
	assert(ResourceLoader.exists(resource.resource_path), "Can't modify import data without a file to edit.")

	var import_file := ConfigFile.new()
	import_file.load(template.resource_path + ".import")

	for section in data:
		for key in data[section]:
			import_file.set_value(section, key, data[section][key])

	import_file.save(resource.resource_path + ".import")


signal closed(response: bool)


var options: Dictionary
var cache: Dictionary


func _init() -> void:
	confirmed.connect(closed.emit.bind(true))
	canceled.connect(closed.emit.bind(false))


func _enter_tree() -> void:
	hide()


func _exit_tree() -> void:
	pass


func prompt() -> bool:
	popup_centered()
	var result: bool = await closed

	for child in %list.get_children():
		if child is not PsxConversionDialogOption: continue
		options[child.name] = child.get_option_value()

	return result


func get_convert_response(resource: Resource) -> int:
	if resource == null or resource is PsxMaterial3D:
		return CONVERT_NONE

	if path_is_psx(resource.resource_path):
		return CONVERT_OVERWRITE

	if resource is PackedScene:
		return options.get(&"convert_native_scenes" if resource_is_native(resource) else &"convert_imported_scenes", CONVERT_NONE)

	if resource is Mesh:
		return options.get(&"convert_meshes", CONVERT_NONE)

	if resource is BaseMaterial3D:
		return options.get(&"convert_base_material_3ds", CONVERT_NONE)

	if resource is ShaderMaterial and resource.shader.get_mode() == Shader.MODE_SPATIAL:
		return options.get(&"convert_shader_materials", CONVERT_NONE)

	return CONVERT_NONE


func convert_nodes(nodes: Array[Node]) -> void:
	for node in nodes:
		convert_node(node)


func convert_resource_paths(paths: PackedStringArray, dir_path := "") -> void:
	if dir_path:
		for i in paths.size():
			paths[i] = dir_path.path_join(paths[i])

	for path in paths:
		if DirAccess.dir_exists_absolute(path):
			convert_resource_paths(DirAccess.get_directories_at(path), path)
			convert_resource_paths(DirAccess.get_files_at(path), path)
		elif ResourceLoader.exists(path):
			convert_resource(ResourceLoader.load(path))


func convert_resource(resource: Resource, new_path := "") -> Variant:
	var response := get_convert_response(resource)
	match response:
		CONVERT_NONE: return resource

	if cache.has(resource):
		return cache[resource]

	if ResourceLoader.exists(resource.resource_path) and new_path.is_empty():
		new_path = resource.resource_path if response == CONVERT_OVERWRITE else resource.resource_path.insert(
			resource.resource_path.length() - resource.resource_path.get_extension().length() - 1,
			PSX_SUFFIX
		)

	if resource.resource_path != new_path and ResourceLoader.exists(new_path):
		cache[resource] = ResourceLoader.load(new_path)
		return cache[resource]

	var result: Variant = null

	if resource is PackedScene:
		result = convert_scene_from(resource, new_path)

	elif resource is Mesh:
		result = convert_mesh_from(resource)

	elif resource is Material:
		result = convert_material_from(resource)

	if result == null:
		return null

	if options.get(&"convert_object_properties", true):
		convert_object_plist(result)

	if new_path.is_empty():
		cache[resource] = result
	else:
		result.take_over_path(new_path)
		ResourceSaver.save(result)
		cache[resource] = ResourceLoader.load(new_path)

	return cache[resource]


func convert_scene_from(scene: PackedScene, new_path: String) -> PackedScene:
	var root := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var result: PackedScene

	if resource_is_native(scene):
		convert_tree(root)

		result = PackedScene.new()
		var err := result.pack(root)

	else:
		match options[&"convert_imported_scenes"]:
			CONVERT_NONE: return
			CONVERT_OVERWRITE: result = scene
			CONVERT_CREATE_NEW:
				result = scene.duplicate()
				DirAccess.copy_absolute(scene.resource_path, new_path)
				result.take_over_path(new_path)

		var materials := get_materials_used_in_tree(root)

		var data: Dictionary
		for k in materials:
			var converted_material := convert_resource(materials[k], "res://%s%s.tres" % [k, PSX_SUFFIX])

			data[k] = {
				"use_external/enabled": true,
				"use_external/fallback_path": converted_material.resource_path,
				"use_external/path": ResourceUID.path_to_uid(converted_material.resource_path)
			}

		modify_resource_import_data(result, {
			"params": {
				"_subresources": {
					"materials": data
				}
			}
		}, scene)

	root.queue_free()

	return result


func convert_tree(node: Node, root: Node = node) -> void:
	var meta_ignore: int = node.get_meta(Psx.PsxInspectorPlugin.META_IGNORE, 0)
	match meta_ignore:
		2: return
		0: convert_node(node)

	for child in node.get_children():
		if child.owner != root: continue
		convert_tree(child, root)


func convert_node(node: Node) -> void:
	if node is MeshInstance3D:
		node.mesh = convert_resource(node.mesh)

		for idx in node.get_surface_override_material_count():
			node.set_surface_override_material(idx, convert_resource(node.get_surface_override_material(idx)))

	elif node is GPUParticles3D:
		for idx in node.draw_passes:
			var prop_name: StringName = &"draw_pass_" + str(idx + 1)
			node.set(prop_name, convert_resource(node.get(prop_name)))

	if node is GeometryInstance3D:
		node.material_override = convert_resource(node.material_override)
		node.material_overlay = convert_resource(node.material_overlay)

	if options.get(&"convert_object_properties", false):
		convert_object_plist(node)


func convert_object_plist(obj: Object) -> void:
	for prop in obj.get_property_list():
		if not property_is_resource(prop): continue

		var old = obj.get(prop[&"name"])
		var new := convert_resource(old)

		if new == null or new == old: continue

		obj.set(prop[&"name"], new)


func get_materials_used_in_tree(node: Node, root: Node = node) -> Dictionary:
	var result: Dictionary

	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			result[node.mesh["surface_%s/name" % str(i)]] = node.mesh.surface_get_material(i)

	for child in node.get_children():
		if child.owner != root: continue

		result.merge(get_materials_used_in_tree(child, root))

	return result


func convert_mesh_from(mesh: Mesh) -> Mesh:
	if mesh == null: return null
	var result: Mesh = mesh.duplicate()

	for idx in mesh.get_surface_count():
		result.surface_set_material(idx, convert_resource(mesh.surface_get_material(idx)))

	return result


func convert_material_from(material: Material) -> PsxMaterial3D:
	var result: PsxMaterial3D = null

	if material is BaseMaterial3D:
		result = PsxMaterial3D.new()

		match material.transparency:
			BaseMaterial3D.TRANSPARENCY_DISABLED:
				result.transparency_mode = 0
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				result.transparency_mode = 1
			_:
				result.transparency_mode = 2

		result.shading_mode = (
			BaseMaterial3D.SHADING_MODE_PER_VERTEX
			if options.get(&"material_force_vertex_lighting", true) and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
			else material.shading_mode
		)

		result.fog_mode = (
			PsxMaterial3D.FogMode.PER_VERTEX
			if options.get(&"material_force_vertex_fog", true) and not material.disable_fog
			else int(not material.disable_fog)
		)

		match options.get(&"material_force_vertex_colors", 0):
			0: result.vertex_color_use_as_albedo = material.vertex_color_use_as_albedo
			1: result.vertex_color_use_as_albedo = false
			2: result.vertex_color_use_as_albedo = true

		for param in PsxMaterial3D.TRANSFERABLE_PARAMS:
			result.set(param, material.get(param))

	elif material is ShaderMaterial \
			and material.shader.get_mode() == Shader.MODE_SPATIAL:
		result = PsxMaterial3D.new()

		var transferable_params: Dictionary[String, String]
		for uniform in material.shader.get_shader_uniform_list():
			for param in PsxMaterial3D.TRANSFERABLE_PARAMS:
				if not uniform[&"name"].ends_with(param): continue
				transferable_params[uniform[&"name"]] = param
				break

		for k in transferable_params.keys():
			var param_value = material.get_shader_parameter(k)
			if param_value == null: continue

			var start_value = result.get(transferable_params[k])
			if start_value != null and typeof(start_value) != typeof(param_value): continue

			result.set(transferable_params[k], param_value)

	else:
		return material

	if result:
		result.render_priority = material.render_priority
		if material.next_pass:
			result.next_pass = convert_resource(material.next_pass)

	return result
