extends RefCounted

## Painted-steel panel look of the quiz walls, the answer doors and the small goal / start props
## (goal-line stripes, the start barrier, the saw's telescopic spindles).
##
## Load it with preload (no class_name), like the other stage helpers:
##   const WallMaterials = preload("res://scripts/world/wall_materials.gd")
##
## Every material stays a StandardMaterial3D whose albedo_color is the original colour: game code
## reads albedo_color (door debris, the pass-through fade, the wall shatter). The textures only
## modulate it: wall_panel_albedo is a grey multiplier with a linear mean of PANEL_ALBEDO_MEAN.
##
## Mapping: OBJECT-space triplanar (uv1_triplanar, uv1_world_triplanar off). Walls, stripes and the
## barrier slide along the belt, so a world-space projection would make the panels swim over them.
## One texture tile covers TILE_M metres of a part's own coordinates (the wall, door and prop
## BoxMeshes are sized in metres and their nodes are never scaled), and a BoxMesh is centred on its
## node, so the offsets put every part's centre in the middle of a 3 m panel (vertical joints at
## +-1.5 m) and its top edge on a horizontal joint.
## Layout of the tile: tools/ground/gen_wall_textures.py (docstring).
##
## Cost per pixel, by graphics quality (triplanar = 3 fetches per texture, whatever the sharpness):
##   low       albedo                                3 fetches
##   balanced  albedo + normal                       6
##   high      albedo + normal + roughness (ORM.G)   9
##   ultra     same as high                          9
## The ORM's AO (R) is not sampled: the joint and rivet cavities are already in the albedo, and the
## walls are mostly lit by the sky, where the two would only double the same darkening.
## Filtering is trilinear, never anisotropic: on a box two of the three triplanar fetches have a
## degenerate footprint (one coordinate is constant across the face), which anisotropic filtering
## would turn into up to 16 taps each for a sample whose weight is zero.

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

const PANEL_ALBEDO := "res://assets/environment/conveyor_stage/textures/wall_panel_albedo.png"
const PANEL_NORMAL := "res://assets/environment/conveyor_stage/textures/wall_panel_normal.png"
const PANEL_ORM := "res://assets/environment/conveyor_stage/textures/wall_panel_orm.png"
## The underground temple's painted steel, referenced in place (same .import / .ctex as the temple,
## so no extra files; about 2.8 MB of VRAM once loaded on the surface). Only its relief and roughness
## are used, on the polished spindles: its albedo carries rust patches and a paint mask in alpha that a
## StandardMaterial3D cannot read.
const STEEL_NORMAL := "res://assets/environment/underground_temple/textures/steel_normal.png"
const STEEL_ORM := "res://assets/environment/underground_temple/textures/steel_orm.png"

## Measured on the PNGs (gen_wall_textures.py verification): linear albedo mean and ORM.G means.
const PANEL_ALBEDO_MEAN := 0.940
const PANEL_ROUGHNESS_MEAN := 0.600
const STEEL_ROUGHNESS_MEAN := 0.561

## Metres of part-local space per texture tile (x, y, z). 3 panels of 3.0 m by 4.4 m.
const TILE_M := Vector3(9.0, 4.4, 9.0)
## Local y of the top edge of the 4.4 m pillars and doors: it lands on the tile's top joint, and the
## joint 3.337 m lower (the base seam) then falls on the lower edge of the standard question beam too.
const PANEL_TOP_Y := 2.2
## u: a part's centre sits mid-panel (panel centres at u = 1/6, 1/2, 5/6).
## z: the 1.1-1.2 m thick side faces (u = -(z / 9 + 0.19)) and top faces (v = z / 9 + 0.19) both
## land inside one panel, clear of the joints, for any part up to 2.5 m thick at scale 1.
const OFFSET_U := 1.0 / 6.0
const OFFSET_Z := 0.19

static var _textures: Dictionary = {}
static var _cache: Dictionary = {}


## GameManager.graphics_quality when the autoload is there (tests and tools may run without it).
static func current_quality() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var manager := tree.root.get_node_or_null(^"GameManager")
		if manager != null:
			return QualityRules.normalize(str(manager.get("graphics_quality")))
	return QualityRules.BALANCED


## A new painted-steel panel material.
## color: albedo_color, unchanged. roughness / metallic: the material's average values (with the ORM
## roughness texture the scalar is scaled so the textured mean lands on `roughness`).
## panel_shift: which of the tile's three panels sits on the part's centre (keeps doors from repeating
## the wall around them). scale: panel size multiplier (the 32 m start barrier uses 2).
## top_y: the part's local y that should carry a horizontal joint (its top edge).
static func panel(color: Color, quality: String = "", panel_shift: int = 0, scale: float = 1.0,
		roughness: float = 0.6, metallic: float = 0.05, top_y: float = PANEL_TOP_Y) -> StandardMaterial3D:
	if quality.is_empty():
		quality = current_quality()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	var albedo := _texture(PANEL_ALBEDO)
	if albedo == null:
		return mat
	var tile := TILE_M * scale
	mat.albedo_texture = albedo
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0 / tile.z)
	# The shader flips v after the offset: v = -(y / tile.y + offset.y), so row 0 sits at y = top_y.
	mat.uv1_offset = Vector3(OFFSET_U + float(posmod(panel_shift, 3)) / 3.0, -top_y / tile.y, OFFSET_Z)
	if QualityRules.is_at_least(quality, QualityRules.BALANCED):
		var normal := _texture(PANEL_NORMAL)
		if normal != null:
			mat.normal_enabled = true
			mat.normal_texture = normal
	if QualityRules.is_at_least(quality, QualityRules.HIGH):
		var orm := _texture(PANEL_ORM)
		if orm != null:
			mat.roughness_texture = orm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.roughness = roughness / PANEL_ROUGHNESS_MEAN
	return mat


## Goal-line stripe of GameWorld._create_goal_box: one shared material per colour (and quality)
## instead of a new one for each of the 48 stripes. Same values as the old per-stripe material.
static func goal_stripe(color: Color) -> StandardMaterial3D:
	var quality := current_quality()
	var key := "stripe_%s_%s" % [color.to_html(), quality]
	var cached := _cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var mat := panel(color, quality, 0, 1.0, 0.4, 0.3)
	mat.emission_enabled = true
	mat.emission = color * 0.3
	mat.emission_energy_multiplier = 0.5
	_cache[key] = mat
	return mat


## The saw carriage's telescopic spindles: polished steel, one shared material (cached per quality).
## The posts are stretched along y with node scale, so the object-space mapping stretches with them;
## the relief then reads as drawing marks along the rod. Low keeps the old untextured material.
static func spindle_steel(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var quality := current_quality()
	var key := "spindle_%s_%s" % [color.to_html(), quality]
	var cached := _cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if QualityRules.is_at_least(quality, QualityRules.BALANCED):
		var normal := _texture(STEEL_NORMAL)
		if normal != null:
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = false
			mat.uv1_triplanar_sharpness = 4.0
			mat.uv1_scale = Vector3(2.0, 1.0, 2.0)
			mat.normal_enabled = true
			mat.normal_texture = normal
			if QualityRules.is_at_least(quality, QualityRules.HIGH):
				var orm := _texture(STEEL_ORM)
				if orm != null:
					mat.roughness_texture = orm
					mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
					mat.roughness = roughness / STEEL_ROUGHNESS_MEAN
	_cache[key] = mat
	return mat


static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		push_warning("WallMaterials: %s is missing; using the plain colour." % path)
	_textures[path] = texture
	return texture
