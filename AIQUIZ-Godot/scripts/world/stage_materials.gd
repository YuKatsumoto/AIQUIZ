@tool
extends RefCounted

## Surface materials of the conveyor stage: the detail textures of the belt shader
## (floor, return belt, rollers) and the steel side frames. StageEnvironment calls these
## after it builds the stage and again whenever the graphics quality changes, so every
## function here must be safe to call more than once.
##
## Load it with preload (no class_name), like the other stage helpers:
##   const StageMaterialsScript = preload("res://scripts/world/stage_materials.gd")
##
## Cost per quality (texture reads per pixel):
##   belt top / rollers: low 2 (albedo, ORM), balanced and up 3 (+ normal map)
##   pier walls (the floor box's sides): 1 (concrete), plus an arithmetic wet band and streaks
##   side frames, rails: 2 (albedo, ORM); bolt domes and edge bevels from balanced up are
##   arithmetic only

const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const STEEL_SHADER: Shader = preload("res://shaders/ground_steel.gdshader")

## Belt cover detail (assets/environment/conveyor_stage/textures/README.md): a grey multiplier,
## an OpenGL normal map and AO / roughness / wear mask. 1 tile = BELT_TILE_M metres of belt.
const BELT_ALBEDO: Texture2D = preload("res://assets/environment/conveyor_stage/textures/belt_detail_albedo.png")
const BELT_NORMAL: Texture2D = preload("res://assets/environment/conveyor_stage/textures/belt_detail_normal.png")
const BELT_ORM: Texture2D = preload("res://assets/environment/conveyor_stage/textures/belt_detail_orm.png")
const BELT_TILE_M := 2.5
## 1 / linear mean of belt_detail_albedo.png (0.940): the texture keeps the belt colour's average.
const BELT_ALBEDO_GAIN := 1.064
## Mean of the ORM green channel (roughness): roughness_val stays the belt's average roughness.
const BELT_ROUGH_MEAN := 0.814
## Mean of the ORM blue channel (wear: rubbed streaks along travel) and how much lighter they read.
const BELT_POLISH_MEAN := 0.235
const BELT_POLISH_GAIN := 0.1

## The sudden death cistern's steel, referenced in place (same import, no copy): painted steel
## (albedo A = paint mask) and galvanised steel (ORM blue = metal).
const STEEL_ALBEDO: Texture2D = preload("res://assets/environment/underground_temple/textures/steel_albedo.png")
const STEEL_ORM: Texture2D = preload("res://assets/environment/underground_temple/textures/steel_orm.png")
const GALV_ALBEDO: Texture2D = preload("res://assets/environment/underground_temple/textures/galv_albedo.png")
const GALV_ORM: Texture2D = preload("res://assets/environment/underground_temple/textures/galv_orm.png")
const CONCRETE_ALBEDO: Texture2D = preload("res://assets/environment/underground_temple/textures/concrete_albedo.png")
## Linear mean of concrete_albedo.png and its tile (as in the cistern).
const CONCRETE_MEAN := 0.285
const CONCRETE_TILE_M := 3.75
## Linear means of the textures' finish (steel: where the paint mask is set).
const STEEL_PAINT_MEAN := 0.73
const GALV_MEAN := 0.50

## Colours of the previous plain materials, kept as the finish colours.
const SIDE_FRAME_COLOR := Color(0.30, 0.31, 0.33)
const RAIL_HEAD_COLOR := Color(0.64, 0.68, 0.71)
const RAIL_SUPPORT_COLOR := Color(0.16, 0.18, 0.21)


## Gives a belt-shader material (shaders/conveyor_belt_floor.gdshader) its detail textures
## for `quality`. A material that never goes through here keeps the plain procedural look
## (the menu and settings previews build their own belt materials).
static func belt_detail(material: ShaderMaterial, quality: String) -> void:
	if material == null:
		return
	var q: String = QualityRules.normalize(quality)
	material.set_shader_parameter("detail_albedo", BELT_ALBEDO)
	material.set_shader_parameter("detail_orm", BELT_ORM)
	material.set_shader_parameter("detail_normal", BELT_NORMAL)
	material.set_shader_parameter("detail_strength", 1.0)
	material.set_shader_parameter("normal_strength", belt_normal_strength(q))
	# Low renders the 3D view at 70 % and sharpens it back up (FSR): half a mip more filtering
	# keeps the sub-pixel marks of the moving belt from shimmering there.
	material.set_shader_parameter("detail_grad_scale", 1.41 if q == QualityRules.LOW else 1.0)
	material.set_shader_parameter("detail_tile_m", BELT_TILE_M)
	material.set_shader_parameter("detail_albedo_gain", BELT_ALBEDO_GAIN)
	material.set_shader_parameter("detail_rough_mean", BELT_ROUGH_MEAN)
	material.set_shader_parameter("detail_polish_mean", BELT_POLISH_MEAN)
	material.set_shader_parameter("detail_polish_gain", BELT_POLISH_GAIN)
	material.set_shader_parameter("frame_inner_x", StageConstants.FLOOR_HALF_WIDTH - StageConstants.CONVEYOR_SIDE_FRAME_WIDTH)
	material.set_shader_parameter("water_y", StageConstants.OCEAN_SURFACE_Y)
	material.set_shader_parameter("side_albedo", CONCRETE_ALBEDO)
	material.set_shader_parameter("side_albedo_mean", CONCRETE_MEAN)
	material.set_shader_parameter("side_tile_m", CONCRETE_TILE_M)
	material.set_shader_parameter("side_detail", 1.0)


## Normal map strength of the belt cover: off on low (two texture reads instead of three).
static func belt_normal_strength(quality: String) -> float:
	return 0.0 if QualityRules.normalize(quality) == QualityRules.LOW else 1.0


## The material of the two steel side frames of the conveyor.
static func side_frame(quality: String) -> Material:
	var material := _painted_steel(SIDE_FRAME_COLOR, quality)
	# The frame's outer face lies in the pier wall's plane: push it out of the wall.
	material.set_shader_parameter("push_out_x", 0.012)
	# Bolted sections, each with its own texture offset (no 1 m repeat along the course).
	material.set_shader_parameter("section_m", 3.2)
	material.set_shader_parameter("edge_wear", 0.85)
	material.set_shader_parameter("edge_width", 0.045)
	material.set_shader_parameter("bolt_spacing", 0.8)
	material.set_shader_parameter("bolt_on_top", 0.0)
	material.set_shader_parameter("bolt_rows", Vector2(0.34, -0.30))
	material.set_shader_parameter("bolt_radius", 0.022)
	material.set_shader_parameter("grime", 0.45)
	return material


## Head and web of the running rails: galvanised steel with a polished running band on top.
static func rail_head(quality: String) -> Material:
	var material := ShaderMaterial.new()
	material.shader = STEEL_SHADER
	material.set_shader_parameter("albedo_tex", GALV_ALBEDO)
	material.set_shader_parameter("orm_tex", GALV_ORM)
	material.set_shader_parameter("finish_color", RAIL_HEAD_COLOR)
	material.set_shader_parameter("tex_mean", GALV_MEAN)
	material.set_shader_parameter("tex_m", 1.3)
	# Only a hint of the zinc spangle and its smudges: a rail head is a plain steel bar.
	material.set_shader_parameter("tex_contrast", 0.4)
	material.set_shader_parameter("metal_tex_weight", 0.2)
	material.set_shader_parameter("paint_mask", 0.0)
	material.set_shader_parameter("finish_metallic", 0.8)
	material.set_shader_parameter("roughness_mul", 0.45)
	material.set_shader_parameter("roughness_add", 0.12)
	material.set_shader_parameter("bare_color", Color(0.70, 0.72, 0.74))
	material.set_shader_parameter("polish_top", 1.0)
	material.set_shader_parameter("polish_half_width", 0.05)
	material.set_shader_parameter("section_m", 6.4)
	material.set_shader_parameter("grime", 0.2)
	material.set_shader_parameter("relief", _relief(quality))
	return material


## Mounting base and end caps of the running rails: dark painted steel, bolted down.
static func rail_support(quality: String) -> Material:
	var material := _painted_steel(RAIL_SUPPORT_COLOR, quality)
	material.set_shader_parameter("edge_wear", 0.9)
	material.set_shader_parameter("edge_width", 0.025)
	material.set_shader_parameter("section_m", 6.4)
	material.set_shader_parameter("bolt_spacing", 0.6)
	material.set_shader_parameter("bolt_on_top", 1.0)
	# Just outside the 0.16 m head on the 0.24 m base, so they show from above.
	material.set_shader_parameter("bolt_rows", Vector2(0.098, -0.098))
	material.set_shader_parameter("bolt_radius", 0.015)
	material.set_shader_parameter("grime", 0.35)
	return material


## The current graphics quality (GameManager.graphics_quality, as StageEnvironment reads it).
## Looked up at run time, so ConveyorRails does not need the autoload to compile.
static func current_quality() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.get_node_or_null("GameManager") if tree != null and tree.root != null else null
	var raw: Variant = manager.get("graphics_quality") if manager != null else null
	if typeof(raw) != TYPE_STRING or String(raw).is_empty():
		return QualityRules.BALANCED
	return QualityRules.normalize(String(raw))


static func _painted_steel(color: Color, quality: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STEEL_SHADER
	material.set_shader_parameter("albedo_tex", STEEL_ALBEDO)
	material.set_shader_parameter("orm_tex", STEEL_ORM)
	material.set_shader_parameter("finish_color", color)
	material.set_shader_parameter("tex_mean", STEEL_PAINT_MEAN)
	material.set_shader_parameter("tex_m", 1.0)
	material.set_shader_parameter("paint_mask", 1.0)
	material.set_shader_parameter("finish_metallic", 0.0)
	material.set_shader_parameter("finish_metallic_add", 0.12)
	material.set_shader_parameter("roughness_mul", 1.0)
	material.set_shader_parameter("roughness_add", 0.06)
	material.set_shader_parameter("relief", _relief(quality))
	return material


## Procedural relief (bolt domes, edge bevels) from balanced up.
static func _relief(quality: String) -> float:
	return 0.0 if QualityRules.normalize(quality) == QualityRules.LOW else 1.0
