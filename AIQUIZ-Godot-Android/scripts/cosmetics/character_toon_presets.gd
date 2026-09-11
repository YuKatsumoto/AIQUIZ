extends RefCounted
class_name CharacterToonPresets

const STANDARD: int = 0
const BASIC: int = 1
const DOT: int = 2
const HATCHING: int = 3
const BRUSH: int = 4
const DIAGONAL: int = 5
const COUNT: int = 6

const BASE_COLOR_META: StringName = &"character_toon_base_color"

static func normalize(_preset_id: int) -> int:
	## キャラクター用シェーダー選択は廃止済み。旧保存値や旧オンライン値も標準へ丸める。
	return STANDARD


static func resolve_player_preset(_game_state: Variant, _player_id: int) -> int:
	return STANDARD


static func create_material(_preset_id: int, base_color: Color) -> Material:
	var opaque_base := Color(base_color.r, base_color.g, base_color.b, 1.0)
	var standard := StandardMaterial3D.new()
	standard.albedo_color = opaque_base
	standard.roughness = 0.7
	standard.metallic = 0.1
	return standard


static func remember_base_color(mesh_instance: MeshInstance3D, base_color: Color) -> void:
	if mesh_instance == null:
		return
	mesh_instance.set_meta(BASE_COLOR_META, Color(base_color.r, base_color.g, base_color.b, 1.0))


static func get_base_color(mesh_instance: MeshInstance3D) -> Color:
	if mesh_instance == null:
		return Color.WHITE
	if mesh_instance.has_meta(BASE_COLOR_META):
		var stored: Variant = mesh_instance.get_meta(BASE_COLOR_META)
		if stored is Color:
			return stored
	var material := mesh_instance.material_override
	if material is StandardMaterial3D:
		return material.albedo_color
	if material is ShaderMaterial:
		var shader_color: Variant = material.get_shader_parameter(&"albedo_color")
		if shader_color is Color:
			return shader_color
	return Color.WHITE


static func apply_to_parts(parts: Dictionary, preset_id: int) -> void:
	var normalized := normalize(preset_id)
	var materials_by_color: Dictionary = {}
	var meshes: Variant = parts.get("meshes", [])
	if not meshes is Array:
		return
	for mesh_value: Variant in meshes:
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance == null:
			continue
		var base_color := get_base_color(mesh_instance)
		if not mesh_instance.has_meta(BASE_COLOR_META):
			remember_base_color(mesh_instance, base_color)
		var color_key := base_color.to_rgba32()
		if not materials_by_color.has(color_key):
			materials_by_color[color_key] = create_material(normalized, base_color)
		mesh_instance.material_override = materials_by_color[color_key]
