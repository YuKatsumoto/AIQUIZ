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
const _STANDARD_PATH: String = ""
const _BASIC_PATH: String = "res://assets/BinbunMaterials/presets/basic/basic_medium.tres"
const _DOT_PATH: String = "res://assets/BinbunMaterials/presets/dot/dot_medium.tres"
const _HATCHING_PATH: String = "res://assets/BinbunMaterials/presets/hatching/hatching_medium.tres"
const _BRUSH_PATH: String = "res://assets/BinbunMaterials/presets/brush/brush_01.tres"
const _DIAGONAL_PATH: String = "res://assets/BinbunMaterials/presets/diagonal/diagonal_medium.tres"

const _BASIC_MATERIAL: ShaderMaterial = preload(_BASIC_PATH)
const _DOT_MATERIAL: ShaderMaterial = preload(_DOT_PATH)
const _HATCHING_MATERIAL: ShaderMaterial = preload(_HATCHING_PATH)
const _BRUSH_MATERIAL: ShaderMaterial = preload(_BRUSH_PATH)
const _DIAGONAL_MATERIAL: ShaderMaterial = preload(_DIAGONAL_PATH)

const _CATALOG: Array[Dictionary] = [
	{"id": STANDARD, "name": "標準", "material_path": _STANDARD_PATH},
	{"id": BASIC, "name": "ベーシック", "material_path": _BASIC_PATH},
	{"id": DOT, "name": "ドット", "material_path": _DOT_PATH},
	{"id": HATCHING, "name": "ハッチング", "material_path": _HATCHING_PATH},
	{"id": BRUSH, "name": "ブラシ", "material_path": _BRUSH_PATH},
	{"id": DIAGONAL, "name": "斜線", "material_path": _DIAGONAL_PATH},
]


static func normalize(preset_id: int) -> int:
	return preset_id if preset_id >= STANDARD and preset_id < COUNT else STANDARD


static func get_catalog() -> Array[Dictionary]:
	return _CATALOG.duplicate(true)


static func resolve_player_preset(game_state: Variant, player_id: int) -> int:
	if game_state == null:
		return STANDARD
	var local_preset: int = game_state.p1_toon_preset if player_id == 1 else game_state.p2_toon_preset
	if game_state.is_replay:
		return normalize(local_preset)
	if NetworkManager.state != NetworkManager.State.IN_GAME:
		return normalize(local_preset)
	var is_opponent_slot := (
		(NetworkManager.is_host and player_id == 2)
		or (not NetworkManager.is_host and player_id == 1)
	)
	return normalize(NetworkManager.opponent_toon_preset if is_opponent_slot else local_preset)


static func create_material(preset_id: int, base_color: Color) -> Material:
	var normalized := normalize(preset_id)
	var opaque_base := Color(base_color.r, base_color.g, base_color.b, 1.0)
	if normalized == STANDARD:
		var standard := StandardMaterial3D.new()
		standard.albedo_color = opaque_base
		standard.roughness = 0.7
		standard.metallic = 0.1
		return standard

	var preset: ShaderMaterial = _get_preset_material(normalized)
	var material := preset.duplicate(true) as ShaderMaterial
	material.set_shader_parameter(&"albedo_color", opaque_base)
	material.set_shader_parameter(&"albedo_affect", 1.0)
	material.set_shader_parameter(&"shadow_tint", Color(opaque_base.darkened(0.62), 1.0))
	material.set_shader_parameter(&"rim_color", Color(opaque_base.lightened(0.58), 1.0))
	return material


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


static func _get_preset_material(preset_id: int) -> ShaderMaterial:
	match preset_id:
		BASIC:
			return _BASIC_MATERIAL
		DOT:
			return _DOT_MATERIAL
		HATCHING:
			return _HATCHING_MATERIAL
		BRUSH:
			return _BRUSH_MATERIAL
		DIAGONAL:
			return _DIAGONAL_MATERIAL
	return _BASIC_MATERIAL
