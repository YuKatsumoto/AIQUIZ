@tool class_name Psx extends EditorPlugin

#region Sub-Plugins

class PsxFileSystemContextMenuPlugin extends EditorContextMenuPlugin:
	var plugin: Psx


	func _init(__plugin__: Psx) -> void:
		plugin = __plugin__


	func _popup_menu(paths: PackedStringArray) -> void:
		add_context_menu_item("Convert Resource(s) to PSX...", plugin.CONTEXT_convert_selected_paths)


class PsxSceneTreeContextMenuPlugin extends EditorContextMenuPlugin:
	var plugin: Psx


	func _init(__plugin__: Psx) -> void:
		plugin = __plugin__


	func _popup_menu(paths: PackedStringArray) -> void:
		add_context_menu_item("Convert Node(s) to PSX...", plugin.CONTEXT_convert_selected_nodes)


class PsxInspectorPlugin extends EditorInspectorPlugin:
	const META_IGNORE := &"_psx_ignore"
	const META_MATERIAL := &"_psx_material"


	func _can_handle(object: Object) -> bool:
		return object is Node


	func _parse_group(object: Object, group: String) -> void:
		if object is not Node or group != "Editor Description": return

		var container := VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL


		var ignore_container := HBoxContainer.new()
		ignore_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(ignore_container)

		var ignore_label := Label.new()
		ignore_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ignore_label.text = "PSX Ignore"
		ignore_label.mouse_filter = Control.MOUSE_FILTER_STOP
		ignore_label.tooltip_text = "Adds an editor-only meta value '%s' (int)\nwhich will determine if PSX Conversion can occur on this Node." % META_IGNORE
		ignore_container.add_child(ignore_label)

		var ignore_option := OptionButton.new()
		ignore_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ignore_option.add_item("None")
		ignore_option.add_item("Ignore Self")
		ignore_option.add_item("Ignore Self and Children")
		ignore_option.item_selected.connect(_ignore_option_selected.bind(object))
		if object.has_meta(META_IGNORE):
			ignore_option.select(object.get_meta(META_IGNORE))
		ignore_container.add_child(ignore_option)

		add_custom_control(container)


	func _ignore_option_selected(idx: int, node: Node) -> void:
		match idx:
			0: node.set_meta(META_IGNORE, null)
			1: node.set_meta(META_IGNORE, 1)
			2: node.set_meta(META_IGNORE, 2)


	func _auto_resource_changed(resource: Material, node: Node) -> void:
		node.set_meta(META_MATERIAL, resource if resource else null)

#endregion


#region Commands

const CONVERT_CURRENT_SCENE_NAME := "Convert Current Scene to PSX..."
const CONVERT_CURRENT_SCENE_KEY := "psx/convert_current_scene"
const CONVERT_SELECTED_NODE_NAME := "Convert Selected Node(s) to PSX..."
const CONVERT_SELECTED_NODE_KEY := "psx/convert_selected_node"
const CONVERT_ENTIRE_PROJECT_NAME := "Convert Entire Project to PSX..."
const CONVERT_ENTIRE_PROJECT_KEY := "psx/convert_entire_project"
const REBUILD_SHADERS_NAME := "Rebuild Shaders"
const REBUILD_SHADERS_KEY := "psx/rebuild_shaders"
const PURGE_SHADERS_NAME := "Purge Unused Shaders"
const PURGE_SHADERS_KEY := "psx/purge_unused_shaders"

func COMMAND_convert_entire_project() -> void:
	if not await converter.prompt(): return
	converter.convert_resource_paths(["res://"])
	get_editor_interface().save_all_scenes()


func COMMAND_convert_current_scene() -> void:
	if not await converter.prompt(): return
	converter.convert_tree(get_editor_interface().get_edited_scene_root())
	get_editor_interface().mark_scene_as_unsaved()


func COMMAND_convert_selected_nodes() -> void:
	if not await converter.prompt(): return
	converter.convert_nodes(get_editor_interface().get_selection().get_selected_nodes())
	get_editor_interface().mark_scene_as_unsaved()


func CONTEXT_convert_selected_paths(paths: Array) -> void:
	if not await converter.prompt(): return
	converter.convert_resource_paths(paths)
	get_editor_interface().save_all_scenes()


func CONTEXT_convert_selected_nodes(nodes: Array) -> void:
	if not await converter.prompt(): return
	converter.convert_nodes(nodes)
	get_editor_interface().mark_scene_as_unsaved()

#endregion


#region Shader Globals

const GLOBAL_VARS := {
	&"psx_affine_strength": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 1.0,
	},
	&"psx_bit_depth": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_INT,
		"type": "int",
		"value": 5,
	},
	&"psx_fog_color": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_COLOR,
		"type": "color",
		"value": Color(0.5, 0.5, 0.5, 0.0),
	},
	&"psx_fog_far": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 20.0,
	},
	&"psx_fog_near": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 10.0,
	},
	&"psx_precision_uv": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 128.0,
	},
	&"psx_precision_xy": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 256.0,
	},
	&"psx_precision_z": {
		"rtype": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
		"type": "float",
		"value": 512.0,
	},
}

static var affine_strength: float:
	set(value):
		affine_strength = value
		RenderingServer.global_shader_parameter_set(&"psx_affine_strength", value)

static var bit_depth: int:
	set(value):
		bit_depth = value
		RenderingServer.global_shader_parameter_set(&"psx_bit_depth", value)

static var fog_color: Color:
	set(value):
		fog_color = value
		RenderingServer.global_shader_parameter_set(&"psx_fog_color", value)
		if inst == null: return
		inst.fog_changed.emit()

static var fog_far: float:
	set(value):
		fog_far = value
		RenderingServer.global_shader_parameter_set(&"psx_fog_far", value)
		if inst == null: return
		inst.fog_changed.emit()

static var fog_near: float:
	set(value):
		fog_near = value
		RenderingServer.global_shader_parameter_set(&"psx_fog_near", value)
		if inst == null: return
		inst.fog_changed.emit()

static var precision_uv: float:
	set(value):
		precision_uv = value
		RenderingServer.global_shader_parameter_set(&"psx_precision_uv", value)

static var precision_xy: float:
	set(value):
		precision_xy = value
		RenderingServer.global_shader_parameter_set(&"psx_precision_xy", value)

static var precision_z: float:
	set(value):
		precision_z = value
		RenderingServer.global_shader_parameter_set(&"psx_precision_z", value)


static func touch_shader_globals() -> void:
	for k: StringName in GLOBAL_VARS.keys():
		var setting := "shader_globals/" + k
		if not ProjectSettings.has_setting(setting):
			var data: Dictionary = GLOBAL_VARS[k].duplicate()
			RenderingServer.global_shader_parameter_add(k, data[&"rtype"], data[&"value"])
			data.erase(&"rtype")
			ProjectSettings.set_setting(setting, data)
			ProjectSettings.set_initial_value(setting, data[&"value"])
		if not Engine.is_editor_hint():
			inst.set(k, RenderingServer.global_shader_parameter_get(k))

	ProjectSettings.save()

#endregion

const AUTOLOAD_NAME := "psx_post_process"
const AUTOLOAD_PATH := "res://addons/psx/scripts/PsxPostProcessAutoload.gd"

static var CONVERTER_SCENE: PackedScene:
	get: return load("res://addons/psx/scenes/PsxConversionDialog.tscn")
static var MAT_DEFAULT: PsxMaterial3D:
	get: return load("res://addons/psx/materials/psx_mat_default.tres")
static var MAT_PLACEHOLDER: PsxMaterial3D:
	get: return load("res://addons/psx/materials/psx_mat_placeholder.tres")


static var inst: Psx


static func get_path_file_name(path: String) -> String:
	return path.right(path.rfind("/")).left(path.rfind("."))


static func append_suffix_to_path(path: String, suffix: String = "_psx") -> String:
	if path.contains("::"): return path
	return path.left(path.rfind(".")) + suffix + "." + path.get_extension()


static func get_resources(paths: Array, type: String, result: Array = []) -> Array:
	var valid_exts: PackedStringArray = ResourceLoader.get_recognized_extensions_for_type(type)
	for path: String in paths:
		if DirAccess.dir_exists_absolute(path):
			var sub_paths := PackedStringArray()
			for sub_path in DirAccess.get_files_at(path):
				sub_paths.push_back(path.path_join(sub_path))

			for sub_path in DirAccess.get_directories_at(path):
				sub_paths.push_back(path.path_join(sub_path))

			get_resources(sub_paths, type, result)

		elif path.get_extension() in valid_exts:
			var resource := ResourceLoader.load(path)
			if not resource.is_class(type): continue
			if resource in result: continue

			result.push_back(resource)

	return result


static func await_inst(node: Node):
	while inst == null:
		await node.get_tree().create_timer(1.0).timeout


signal fog_changed


var file_system_context_menu_plugin: PsxFileSystemContextMenuPlugin
var scene_tree_context_menu_plugin: PsxSceneTreeContextMenuPlugin
var inspector_plugin: PsxInspectorPlugin
var post_process_node: Node
var converter: PsxConversionDialog


func _init() -> void:
	inst = self


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	touch_shader_globals()

	var command_palette := get_editor_interface().get_command_palette()
	command_palette.add_command(CONVERT_CURRENT_SCENE_NAME, CONVERT_CURRENT_SCENE_KEY, COMMAND_convert_current_scene)
	command_palette.add_command(CONVERT_SELECTED_NODE_NAME, CONVERT_SELECTED_NODE_KEY, COMMAND_convert_selected_nodes)
	command_palette.add_command(CONVERT_ENTIRE_PROJECT_NAME, CONVERT_ENTIRE_PROJECT_KEY, COMMAND_convert_entire_project)
	command_palette.add_command(REBUILD_SHADERS_NAME, REBUILD_SHADERS_KEY, PsxMaterial3D.rebuild_shaders)
	# command_palette.add_command(PURGE_SHADERS_NAME, PURGE_SHADERS_KEY, PsxMaterial3D.purge_unused_shaders)

	if file_system_context_menu_plugin == null:
		file_system_context_menu_plugin = PsxFileSystemContextMenuPlugin.new(self )
		add_context_menu_plugin(EditorContextMenuPlugin.ContextMenuSlot.CONTEXT_SLOT_FILESYSTEM, file_system_context_menu_plugin)

	if scene_tree_context_menu_plugin == null:
		scene_tree_context_menu_plugin = PsxSceneTreeContextMenuPlugin.new(self )
		add_context_menu_plugin(EditorContextMenuPlugin.ContextMenuSlot.CONTEXT_SLOT_SCENE_TREE, scene_tree_context_menu_plugin)

	if inspector_plugin == null:
		inspector_plugin = PsxInspectorPlugin.new()
		add_inspector_plugin(inspector_plugin)

	if post_process_node == null:
		post_process_node = CanvasLayer.new()
		post_process_node.set_script(preload(AUTOLOAD_PATH))
		get_editor_interface().get_editor_viewport_3d().add_child(post_process_node)

	if converter == null:
		converter = CONVERTER_SCENE.instantiate()
		get_editor_interface().get_editor_main_screen().add_child(converter)


func _exit_tree() -> void:
	var command_palette := get_editor_interface().get_command_palette()
	command_palette.remove_command(CONVERT_CURRENT_SCENE_KEY)
	command_palette.remove_command(CONVERT_SELECTED_NODE_KEY)
	command_palette.remove_command(CONVERT_ENTIRE_PROJECT_KEY)
	command_palette.remove_command(REBUILD_SHADERS_KEY)
	# command_palette.remove_command(PURGE_SHADERS_KEY)

	if file_system_context_menu_plugin != null:
		remove_context_menu_plugin(file_system_context_menu_plugin)
		file_system_context_menu_plugin = null

	if scene_tree_context_menu_plugin != null:
		remove_context_menu_plugin(scene_tree_context_menu_plugin)
		scene_tree_context_menu_plugin = null

	if inspector_plugin != null:
		remove_inspector_plugin(inspector_plugin)
		inspector_plugin = null

	if post_process_node != null:
		post_process_node.queue_free()

	if converter != null:
		converter.queue_free()
