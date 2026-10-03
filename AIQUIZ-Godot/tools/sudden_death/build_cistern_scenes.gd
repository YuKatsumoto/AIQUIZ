extends SceneTree

## 2Pサドンデスの地下神殿のシーンを、Blenderの部品から組み立てる（docs/sudden_death_underground.md 第6章、
## 部品の取り決めは docs/sudden_death_m3_interface.md）。
## Godot --headless --path . --script res://tools/sudden_death/build_cistern_scenes.gd [-- placeholders]
## 書き出し：scenes/sudden_death/cistern_stage.tscn（CisternStage。床の当たり判定・天井開口のライト・
## 審判の立ち位置・画面の仕上げ）と、CisternStage.add_part_step() が1フレームに1つずつ足す部分シーン
## cistern_bays.tscn（区画 k = −1〜13 と柱・壁の当たり判定）/ cistern_ends.tscn（上流端・下流端）/
## cistern_lights.tscn（行ごとの実ライト・保安灯のにじみ・窓の明かり・反射プローブ・霧）/
## cistern_dressing.tscn（デカール・塵）。材質・生成テクスチャは scenes/sudden_death/cistern_generated/。
## 部品（assets/environment/underground_temple/*.glb）がまだ無いものは、取り決めどおりの仮の部品
## （tools/sudden_death/cistern_placeholder_modules.gd）を作って使う。部品が届いたら再実行する。
## 生成物なので手で編集しない。

const Layout := preload("res://scripts/world/sudden_death/sudden_death_layout.gd")
const Placeholders := preload("res://tools/sudden_death/cistern_placeholder_modules.gd")
const TextureGen := preload("res://tools/sudden_death/cistern_texture_gen.gd")
const STAGE_SCRIPT_PATH := "res://scripts/world/sudden_death/cistern_stage.gd"
const OUT_DIR := "res://scenes/sudden_death/"
const GEN_DIR := "res://scenes/sudden_death/cistern_generated/"
const ART_DIR := "res://assets/environment/underground_temple/"
const SURFACE_SHADER := "res://shaders/sudden_death/cistern_surface.gdshader"
const FLOOR_SHADER := "res://shaders/sudden_death/cistern_floor.gdshader"
const GRATE_SHADER := "res://shaders/sudden_death/cistern_grate.gdshader"
const LAMP_SHADER := "res://shaders/sudden_death/cistern_lamp.gdshader"
const COLUMN_SHADER := "res://shaders/sudden_death/cistern_column.gdshader"
const DUST_SHADER := "res://shaders/sudden_death/cistern_dust.gdshader"
const GRADE_SHADER := "res://shaders/sudden_death/cistern_grade.gdshader"

## Must match CisternStage: module instances carry these, CisternStage dresses them when a part is added.
const MODULE_META := &"cistern_module"
const MATERIALS_META := &"cistern_materials"
const HALL_LAYER := 11
const FLOOR_Y := Layout.FLOOR_Y
const HALL_W := Layout.HALL_HALF_WIDTH
const Z0 := Layout.HALL_START_Z
const Z1 := Layout.HALL_END_Z
const H := Layout.HALL_HEIGHT
const BAY_PITCH := 15.0
const BAY_FIRST := -1
const BAY_LAST := 13
## Bays a/b/c alternate in a fixed shuffled order (k = 0 is the opening bay).
const BAY_VARIANTS := {-1: "a", 1: "b", 2: "c", 3: "a", 4: "c", 5: "b", 6: "a", 7: "b", 8: "c", 9: "b", 10: "a", 11: "c", 12: "a", 13: "b"}
const MODULES: PackedStringArray = ["cistern_bay_a", "cistern_bay_b", "cistern_bay_c", "cistern_bay_opening", "cistern_end_upstream", "cistern_end_downstream"]
## Where a missing module borrows from before falling back to a placeholder.
const MODULE_FALLBACK := {"cistern_bay_b": "cistern_bay_a", "cistern_bay_c": "cistern_bay_a"}
const MATERIAL_NAMES: PackedStringArray = ["CIS_Concrete", "CIS_Floor", "CIS_SteelPaint", "CIS_Galvanized", "CIS_Grate", "CIS_LampLens", "CIS_Sign"]
## Texture set prefix per material (assets/environment/underground_temple/textures/<prefix>_{albedo,normal,orm,wet}.png).
const TEXTURE_PREFIX := {"CIS_Concrete": ["concrete"], "CIS_Floor": ["floor"], "CIS_SteelPaint": ["steel", "steelpaint", "paint"],
	"CIS_Galvanized": ["galvanized", "galv"], "CIS_Grate": ["grate"], "CIS_Sign": ["sign"], "CIS_Hazard": ["hazard"], "CIS_Interior": ["interior"]}

## Lights. The hall itself is never lit by them: everything but layer 11.
const LIGHT_CULL := 0xFFFFF & ~(1 << (HALL_LAYER - 1))
const FLOOD_COLOR := Color(1.0, 0.93, 0.82)
const FLOOD_ENERGY := 7.0
const FLOOD_RANGE := 30.0
const FLOOD_ANGLE := 58.0
## How strongly the floodlight beams show in the volumetric fog.
const FLOOD_FOG := 0.7
const AMBER_COLOR := Color(1.0, 0.55, 0.16)
const WINDOW_COLOR := Color(1.0, 0.78, 0.52)
## Defaults where the modules carry no anchors (interface: inner pillar faces x = +-11.9, 7 m up, bay z + 3.5).
const LAMP_X := 11.3
const LAMP_Y := 7.0
const LAMP_DZ := 3.5
const PROBE_SPACING := 30.0
const PROBE_CAPTURE_Y := 2.5
const SHAFT_LIGHT_ENERGY := 10.0
## The analytic placeholder bake is in its own units: scale it to the level of the Cycles bakes.
const PLACEHOLDER_LIGHT_SCALE := 0.45
## The Cycles bakes are "exposure 0" in scene-linear units; the game opens the hall up a little (the
## director keeps the camera exposure at 1).
const REAL_LIGHT_SCALE := 1.5
## Amber lamps closer to the corridor than this get a volumetric fog halo.
const HALO_MAX_X := 30.0

var _failed := false
var _layout := {}
## module -> {"scene", "light", "light_max", "light_scale", "real", "source"}
var _modules := {}
var _materials := {}
var _textures := {}
var _anchors := {}
var _manifest := {}
var _force_placeholders := false
## Camera white balance (gain per channel) that turns the floodlight colour white, like the review renders.
var _white_balance := Color(1.0, 1.0, 1.0)
## Files DELIVERY.log lists as ready.
var _ready_files := {}


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	_force_placeholders = "placeholders" in OS.get_cmdline_user_args()
	for sub: String in ["", "materials", "textures", "decals", "placeholder", "flood"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN_DIR + sub))
	_layout = _read_json(ART_DIR + "cistern_layout.json")
	_white_balance = _balance_for(_flood_color())
	_build_shared_textures()
	_resolve_modules()
	var parts: Array[PackedScene] = []
	for entry: Array in [["bays", _build_bays], ["ends", _build_ends], ["lights", _build_lights], ["dressing", _build_dressing]]:
		var path := OUT_DIR + "cistern_%s.tscn" % entry[0]
		_save((entry[1] as Callable).call(), path)
		var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if scene == null:
			_fail("could not reload " + path)
		parts.append(scene)
	var stage := _build_stage()
	stage.set("part_scenes", parts)
	stage.set("flood_assets", _flood_assets())
	_save(stage, OUT_DIR + "cistern_stage.tscn")
	# The milestone-2 greybox parts are replaced by the module parts.
	for old: String in ["cistern_pillars.tscn", "cistern_props.tscn"]:
		if FileAccess.file_exists(OUT_DIR + old):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_DIR + old))
	_write_manifest()
	print("CISTERN_SCENES " + ("FAILED" if _failed else "OK") + " " + JSON.stringify(_manifest.get("modules", {})))
	quit(1 if _failed else 0)


## The flood's assets for FloodWave (docs 6.6): the front's mesh out of the GLB (saved on its own so the
## scene does not drag the whole imported scene along) and the VAT / foam / normal / spray textures.
func _flood_assets() -> Array[Resource]:
	var assets: Array[Resource] = []
	var scene := load(FloodWave.FRONT_GLB_PATH) as PackedScene
	var mesh := FloodWave.front_mesh_from_scene(scene)
	if mesh == null:
		_fail("no flood front mesh in " + FloodWave.FRONT_GLB_PATH)
		return assets
	assets.append(_save_resource(mesh.duplicate(), FloodWave.FRONT_MESH_PATH))
	for path: String in [FloodWave.VAT_POS_PATH, FloodWave.VAT_NRM_PATH, FloodWave.FOAM_PATH, FloodWave.WATER_NORMAL_PATH, FloodWave.SPRAY_PATH]:
		var texture := load(path) as Texture2D
		if texture == null:
			_fail("missing flood texture " + path)
		assets.append(texture)
	return assets


## The floodlight colour of the delivered modules (cistern_layout.json), else the default.
func _flood_color() -> Color:
	var modules: Variant = _layout.get("modules", {})
	if modules is Dictionary:
		for module: String in (modules as Dictionary).keys():
			var lights: Variant = (modules[module] as Dictionary).get("lights", []) if modules[module] is Dictionary else []
			for entry: Variant in lights:
				if entry is Dictionary and str((entry as Dictionary).get("kind", "")) == "Flood":
					return _entry_color(entry, FLOOD_COLOR)
	return FLOOD_COLOR


## Per-channel gain that maps `white` to a grey of the same luminance.
static func _balance_for(white: Color) -> Color:
	var luminance := 0.2126 * white.r + 0.7152 * white.g + 0.0722 * white.b
	return Color(luminance / maxf(white.r, 0.01), luminance / maxf(white.g, 0.01), luminance / maxf(white.b, 0.01))


func _balanced(color: Color) -> Color:
	return Color(color.r * _white_balance.r, color.g * _white_balance.g, color.b * _white_balance.b)


func _fail(message: String) -> void:
	_failed = true
	push_error("[build_cistern_scenes] " + message)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Saves a generated resource and binds it to its file, so the scenes reference it instead of embedding it.
func _save_resource(resource: Resource, path: String) -> Resource:
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		_fail("%s: %s" % [path, error_string(error)])
	resource.take_over_path(path)
	return resource


func _save(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	if error != OK:
		_fail("%s: %s" % [path, error_string(error)])
	else:
		print("saved %s (%d nodes)" % [path, _count(root)])
	root.free()


## Owns everything to the scene root, but not the inside of instanced scenes (the modules).
func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_own(child, owner)


func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _count(child)
	return total


# ------------------------------------------------------------------ textures

func _build_shared_textures() -> void:
	_textures["macro"] = _save_resource(TextureGen.macro_noise(), GEN_DIR + "textures/macro_noise.res")
	_textures["lut"] = _save_resource(TextureGen.grade_lut_strip(), GEN_DIR + "textures/grade_lut.res")
	for kind: String in ["concrete", "floor"]:
		if _art_texture(kind, "albedo") != null:
			continue
		var set_dict: Dictionary = TextureGen.concrete_set() if kind == "concrete" else TextureGen.floor_set()
		for channel: String in set_dict.keys():
			_textures["ph_%s_%s" % [kind, channel]] = _save_resource(set_dict[channel], GEN_DIR + "textures/ph_%s_%s.res" % [kind, channel])


func _art_texture(prefix: String, channel: String) -> Texture2D:
	for path: String in [ART_DIR + "textures/%s_%s.png" % [prefix, channel], ART_DIR + "textures/%s_%s.jpg" % [prefix, channel]]:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Tiling set for a material: the module art if delivered, else the placeholder set (concrete, floor).
func _texture_set(material_name: String) -> Dictionary:
	var result := {}
	for prefix: String in TEXTURE_PREFIX.get(material_name, []):
		if _art_texture(prefix, "albedo") == null and not _textures.has("ph_%s_albedo" % prefix):
			continue
		for channel: String in ["albedo", "normal", "orm", "wet"]:
			var texture := _art_texture(prefix, channel)
			if texture == null and _textures.has("ph_%s_%s" % [prefix, channel]):
				texture = _textures["ph_%s_%s" % [prefix, channel]]
			if texture != null:
				result[channel] = texture
		break
	if material_name == "CIS_Hazard" and not result.is_empty():
		# The hazard bands share the painted steel relief and ORM.
		for channel: String in ["normal", "orm"]:
			if not result.has(channel) and _art_texture("steel", channel) != null:
				result[channel] = _art_texture("steel", channel)
	return result


# ------------------------------------------------------------------ modules

func _resolve_modules() -> void:
	var need_placeholders := _force_placeholders
	for module: String in MODULES:
		if not ResourceLoader.exists(ART_DIR + module + ".glb"):
			need_placeholders = need_placeholders or not FileAccess.file_exists(Placeholders.OUT_DIR + _placeholder_name(module) + ".scn")
	var placeholders := {}
	if need_placeholders:
		var builder := Placeholders.new()
		placeholders = builder.build_all()
		for line: String in builder.log_lines:
			print("placeholder " + line)
		_write_json(Placeholders.OUT_DIR + "placeholder_layout.json", placeholders)
	else:
		placeholders = _read_json(Placeholders.OUT_DIR + "placeholder_layout.json")
	for module: String in MODULES:
		var info := _real_module(module)
		if info.is_empty() and MODULE_FALLBACK.has(module):
			info = _real_module(MODULE_FALLBACK[module])
		if info.is_empty():
			var key := _placeholder_name(module)
			var entry: Dictionary = placeholders.get(key, {})
			info = {"scene": Placeholders.OUT_DIR + key + ".scn", "light": Placeholders.OUT_DIR + key + "_light.res",
				"light_max": float(entry.get("light_max", 1.0)), "light_scale": PLACEHOLDER_LIGHT_SCALE,
				"real": false, "source": "placeholder:" + key}
		_modules[module] = info
		_anchors[module] = _module_anchors(info.scene)
		info["materials"] = _module_materials(module, info)
		print("module %s <- %s" % [module, info.source])


func _placeholder_name(module: String) -> String:
	return "cistern_bay_a" if module in ["cistern_bay_a", "cistern_bay_b", "cistern_bay_c"] else module


## A delivered module: listed "ready" in DELIVERY.log (the Blender side writes the GLB first and the
## line last), imported, and loadable.
func _real_module(module: String) -> Dictionary:
	var scene := ART_DIR + module + ".glb"
	if not _delivered(module + ".glb") or not ResourceLoader.exists(scene):
		return {}
	if not load(scene) is PackedScene:
		push_warning("[build_cistern_scenes] %s is listed but does not load yet" % scene)
		return {}
	var light := ""
	for candidate: String in [ART_DIR + "textures/%s_light.png" % module, ART_DIR + "%s_light.png" % module]:
		if ResourceLoader.exists(candidate):
			light = candidate
			break
	if light.is_empty():
		push_warning("[build_cistern_scenes] %s has no light map yet" % module)
	return {"scene": scene, "light": light, "light_max": _layout_light_max(module), "light_scale": _layout_float(module, "light_scale", REAL_LIGHT_SCALE),
		"real": true, "source": scene}


func _delivered(file_name: String) -> bool:
	if _ready_files.is_empty() and FileAccess.file_exists(ART_DIR + "DELIVERY.log"):
		for line: String in FileAccess.get_file_as_string(ART_DIR + "DELIVERY.log").split("\n"):
			var words := line.strip_edges().split(" ", false)
			var at := words.find("ready")
			if at > 0:
				_ready_files[words[at - 1]] = true
	return _ready_files.has(file_name)


func _layout_module(module: String) -> Dictionary:
	for key: String in ["modules", "parts", "lightmaps"]:
		var group: Variant = _layout.get(key)
		if group is Dictionary and (group as Dictionary).get(module) is Dictionary:
			return (group as Dictionary)[module]
		if group is Array:
			for entry: Variant in group:
				if entry is Dictionary and str((entry as Dictionary).get("name", "")) == module:
					return entry
	if _layout.get(module) is Dictionary:
		return _layout[module]
	return {}


func _layout_light_max(module: String) -> float:
	var entry := _layout_module(module)
	if entry.has("light_max"):
		return float(entry.light_max)
	var table: Variant = _layout.get("light_max")
	if table is Dictionary and (table as Dictionary).has(module):
		return float(table[module])
	push_warning("[build_cistern_scenes] no light_max for %s in cistern_layout.json; using 1" % module)
	return 1.0


func _layout_float(module: String, key: String, fallback: float) -> float:
	var entry := _layout_module(module)
	return float(entry.get(key, _layout.get(key, fallback)))


## CIS_Light_<kind>_<n>, CIS_RefereeMark and the movable nodes, in module space.
func _module_anchors(scene_path: String) -> Dictionary:
	var scene := load(scene_path) as PackedScene
	var anchors := {}
	if scene == null:
		_fail("module scene does not load: " + scene_path)
		return anchors
	var root := scene.instantiate() as Node3D
	for node: Node in root.find_children("CIS_*", "Node3D", true, false):
		var node3d := node as Node3D
		var xform := Transform3D.IDENTITY
		var walk: Node = node3d
		while walk != null and walk != root:
			if walk is Node3D:
				xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		anchors[str(node.name)] = xform
	root.free()
	return anchors


## The materials of a module: one ShaderMaterial per CIS_* name (and any other name its meshes use).
func _module_materials(module: String, info: Dictionary) -> Array:
	var sources := _surface_materials(info.scene)
	var names: PackedStringArray = MATERIAL_NAMES.duplicate()
	for name: String in sources.keys():
		if name not in names:
			names.append(name)
	var list: Array = []
	for name: String in names:
		list.append([name, _material(module, name, info, sources.get(name) as BaseMaterial3D)])
	return list


func _surface_materials(scene_path: String) -> Dictionary:
	var result := {}
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return result
	var root := scene.instantiate()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface)
			var name := material_key(material, mesh, surface)
			if not name.is_empty() and not result.has(name):
				result[name] = material
	root.free()
	return result


## "CIS_Concrete.001" and the like count as "CIS_Concrete" (same rule as CisternStage).
static func material_key(material: Material, mesh: Mesh, surface: int) -> String:
	var name := material.resource_name if material != null else ""
	if name.is_empty() and mesh is ArrayMesh:
		name = (mesh as ArrayMesh).surface_get_name(surface).get_slice("#", 0)
	return name.get_slice(".", 0).strip_edges()


func _material(module: String, name: String, info: Dictionary, source: BaseMaterial3D) -> Material:
	var path := GEN_DIR + "materials/%s__%s.tres" % [module, name.to_snake_case()]
	var material := ShaderMaterial.new()
	var is_lens := name.begins_with("CIS_LampLens")
	var textures := _texture_set(name)
	var shader_path := SURFACE_SHADER
	if is_lens:
		shader_path = LAMP_SHADER
	elif name == "CIS_Floor":
		shader_path = FLOOR_SHADER
	elif name == "CIS_Grate" and (textures.has("albedo") or (source != null and source.albedo_texture != null)):
		shader_path = GRATE_SHADER
	material.shader = load(shader_path) as Shader
	material.resource_name = name
	material.set_shader_parameter("white_balance", Vector3(_white_balance.r, _white_balance.g, _white_balance.b))
	if is_lens:
		# The lens colour is the module material's (white floodlights, amber safety lamps).
		var amber := name != "CIS_LampLens"
		material.set_shader_parameter("energy", _layout_float(module, "amber_lens_energy" if amber else "lens_energy", 10.0 if amber else 26.0))
		if source != null:
			material.set_shader_parameter("lens_color", source.albedo_color)
			if source.albedo_texture != null:
				material.set_shader_parameter("lens_tex", source.albedo_texture)
		elif amber:
			material.set_shader_parameter("lens_color", AMBER_COLOR)
		return _save_resource(material, path) as Material
	if textures.is_empty() and source != null:
		# No tiling set for it: keep what the module's own material carries.
		if source.albedo_texture != null:
			textures["albedo"] = source.albedo_texture
		if source.normal_enabled and source.normal_texture != null:
			textures["normal"] = source.normal_texture
	for channel: String in textures.keys():
		material.set_shader_parameter(channel + "_tex", textures[channel])
	# UV0: the modules repeat their textures every uv0_metres_per_unit; the placeholders every 2 m.
	var metres := _uv_metres(name, textures)
	var module_metres := metres if bool(info.real) else Placeholders.UV_METRES
	material.set_shader_parameter("uv_scale", module_metres / metres)
	material.set_shader_parameter("detail_scale", metres)
	var detail := _art_texture_plain("detail_normal")
	if detail != null and name in ["CIS_Concrete", "CIS_Floor"]:
		material.set_shader_parameter("detail_normal_tex", detail)
	material.set_shader_parameter("macro_noise", _textures.macro)
	if not str(info.light).is_empty():
		material.set_shader_parameter("light_tex", load(info.light))
	material.set_shader_parameter("light_max", float(info.light_max))
	material.set_shader_parameter("light_scale", float(info.light_scale))
	if not bool(info.real):
		# The analytic placeholder bake has no shadows: deepen its falloff a little.
		material.set_shader_parameter("light_gamma", 1.25)
	var albedo := Color(1.0, 1.0, 1.0)
	var roughness := 1.0
	var metallic := 0.0
	match name:
		"CIS_Concrete":
			material.set_shader_parameter("seepage", 0.3)
		"CIS_Floor":
			material.set_shader_parameter("glint_strength", 1.0)
		"CIS_SteelPaint":
			roughness = 0.55
			material.set_shader_parameter("macro_strength", 0.1)
			material.set_shader_parameter("seepage", 0.1)
		"CIS_Galvanized":
			albedo = Color(0.62, 0.63, 0.64)
			roughness = 0.42
			metallic = 0.9
			material.set_shader_parameter("macro_strength", 0.15)
			material.set_shader_parameter("seepage", 0.0)
		"CIS_Grate":
			albedo = Color(0.16, 0.17, 0.18)
			roughness = 0.6
			metallic = 0.3
			material.set_shader_parameter("seepage", 0.0)
		_:
			roughness = 0.6
			material.set_shader_parameter("macro_strength", 0.08)
			material.set_shader_parameter("seepage", 0.0)
	if textures.has("albedo"):
		albedo = Color(1.0, 1.0, 1.0)
	elif source != null and name not in ["CIS_Concrete", "CIS_Floor", "CIS_Galvanized", "CIS_Grate"]:
		albedo = source.albedo_color
	if textures.has("orm"):
		# Roughness and metal come from the ORM set.
		roughness = 1.0
		metallic = 1.0
	material.set_shader_parameter("albedo_color", albedo)
	material.set_shader_parameter("roughness_scale", roughness)
	material.set_shader_parameter("metallic_value", metallic)
	return _save_resource(material, path) as Material


## Metres per UV0 unit of a material's texture set (cistern_layout.json "uv0_metres_per_unit").
func _uv_metres(name: String, textures: Dictionary) -> float:
	var table: Variant = _layout.get("uv0_metres_per_unit", {})
	var placeholder_set := textures.has("albedo") and str((textures.albedo as Resource).resource_path).begins_with(GEN_DIR)
	if placeholder_set:
		return Placeholders.UV_METRES
	if table is Dictionary and (table as Dictionary).has(name):
		return float(table[name])
	return Placeholders.UV_METRES if textures.is_empty() else 1.0


func _instance_module(module: String, node_name: String, position: Vector3) -> Node3D:
	var info: Dictionary = _modules[module]
	var scene := load(info.scene) as PackedScene
	var node := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	node.name = node_name
	node.position = position
	node.set_meta(MODULE_META, module)
	node.set_meta(MATERIALS_META, info.materials)
	return node


static func bay_module(k: int) -> String:
	if k == 0:
		return "cistern_bay_opening"
	return "cistern_bay_" + str(BAY_VARIANTS.get(k, "a"))


# ------------------------------------------------------------------ parts

## Bays k = -1 … 13 at z = 15 k, and the pillars and side walls as obstacles for swept bodies.
func _build_bays() -> Node3D:
	var root := Node3D.new()
	root.name = "CisternBays"
	for k in range(BAY_FIRST, BAY_LAST + 1):
		root.add_child(_instance_module(bay_module(k), "Bay_%s" % _bay_label(k), Vector3(0.0, FLOOR_Y, BAY_PITCH * float(k))))
	var walls := _static_body(root, "WallCollision", SawChaseState.WALL_COLLISION_LAYER)
	var size := Layout.PILLAR_SIZE
	for k in range(BAY_FIRST, BAY_LAST + 1):
		for x: float in Layout.PILLAR_COLUMNS:
			_box_shape(walls, "Pillar", size, Vector3(x, FLOOR_Y + size.y * 0.5, BAY_PITCH * float(k) + size.z * 0.5))
	for side: float in [-1.0, 1.0]:
		_box_shape(walls, "SideWall", Vector3(1.0, H, Z1 - Z0), Vector3(side * (HALL_W + 0.5), FLOOR_Y + H * 0.5, (Z0 + Z1) * 0.5))
	return root


static func _bay_label(k: int) -> String:
	return "m1" if k < 0 else "%02d" % k


func _build_ends() -> Node3D:
	var root := Node3D.new()
	root.name = "CisternEnds"
	root.add_child(_instance_module("cistern_end_upstream", "EndUpstream", Vector3(0.0, FLOOR_Y, 0.0)))
	root.add_child(_instance_module("cistern_end_downstream", "EndDownstream", Vector3(0.0, FLOOR_Y, 0.0)))
	var walls := _static_body(root, "WallCollision", SawChaseState.WALL_COLLISION_LAYER)
	_box_shape(walls, "UpstreamWall", Vector3(HALL_W * 2.0, H, 1.0), Vector3(0.0, FLOOR_Y + H * 0.5, Z0 - 0.5))
	_box_shape(walls, "DownstreamWall", Vector3(HALL_W * 2.0, H, 1.0), Vector3(0.0, FLOOR_Y + H * 0.5, Z1 + 0.5))
	return root


## Real lights for the characters, floodgates, wave and debris (never the hall): per light row the
## floodlight pair (shadows off), the amber safety lamps as fog-only halos, the control room window;
## reflection probes every 30 m; fog near the floor (6.4). Positions come from the modules'
## CIS_Light_<kind>_<n> nodes (their -Z is the light direction), colours and strengths from the
## "lights" lists of cistern_layout.json.
func _build_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "CisternLights"
	var rows: Array[Node3D] = []
	for row in range(BAY_LAST - BAY_FIRST + 1):
		var k := row + BAY_FIRST
		var row_node := Node3D.new()
		row_node.name = "Row%02d" % row
		row_node.position = Vector3(0.0, 0.0, BAY_PITCH * float(k) + LAMP_DZ)
		root.add_child(row_node)
		rows.append(row_node)
		var module := bay_module(k)
		var anchors: Dictionary = _anchors.get(module, {})
		var bay_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, FLOOR_Y, BAY_PITCH * float(k)))
		var floods := _anchors_of(anchors, "Flood")
		if floods.is_empty():
			for side: float in [-1.0, 1.0]:
				var origin := Vector3(side * LAMP_X, LAMP_Y, LAMP_DZ)
				var target := Vector3(-side * 2.0, 0.0, LAMP_DZ + 3.0)
				floods.append(["", Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)])
		for index in range(floods.size()):
			var entry := _module_light(module, str(floods[index][0]))
			var world: Transform3D = bay_xform * (floods[index][1] as Transform3D)
			var side_name := "R" if world.origin.x > 0.0 else "L"
			var lamp := _spot(row_node, "Lamp%s%d" % [side_name, index], world, _balanced(_entry_color(entry, FLOOD_COLOR)),
				float(entry.get("godot_energy", FLOOD_ENERGY)), float(entry.get("range", FLOOD_RANGE)),
				float(entry.get("spot_angle_deg", FLOOD_ANGLE)), FLOOD_FOG)
			lamp.spot_attenuation = float(entry.get("spot_attenuation", lamp.spot_attenuation))
		for amber: Array in _anchors_of(anchors, "Amber"):
			var world: Transform3D = bay_xform * (amber[1] as Transform3D)
			# Only the halo in the fog (cull mask 0): the lamps light nothing a runner reaches. The ones
			# far out in the aisles stay a glint on their lens (bloom), which saves fog work.
			if absf(world.origin.x) < HALO_MAX_X:
				_halo(row_node, "Halo_%s" % amber[0], world.origin, _balanced(_entry_color(_module_light(module, str(amber[0])), AMBER_COLOR)))
	# The ends: wall washers join the end rows, the window lights the balcony and the referee.
	for end: Array in [["cistern_end_upstream", rows[0]], ["cistern_end_downstream", rows[rows.size() - 1]]]:
		var module: String = end[0]
		var anchors: Dictionary = _anchors.get(module, {})
		var row_node: Node3D = end[1]
		var end_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, FLOOR_Y, 0.0))
		for amber: Array in _anchors_of(anchors, "Amber"):
			var world: Transform3D = end_xform * (amber[1] as Transform3D)
			_halo(row_node, "EndHalo_%s" % amber[0], world.origin, _balanced(_entry_color(_module_light(module, str(amber[0])), AMBER_COLOR)))
		for window: Array in _anchors_of(anchors, "Window"):
			var entry := _module_light(module, str(window[0]))
			var world: Transform3D = end_xform * (window[1] as Transform3D)
			var light := OmniLight3D.new()
			light.name = "Window_%s" % window[0]
			light.position = world.origin - row_node.position
			light.light_color = _balanced(_entry_color(entry, WINDOW_COLOR))
			light.light_energy = float(entry.get("godot_energy", 2.2))
			light.omni_range = float(entry.get("range", 8.0))
			light.omni_attenuation = 1.2
			light.light_cull_mask = LIGHT_CULL
			light.light_volumetric_fog_energy = 0.6
			light.shadow_enabled = false
			row_node.add_child(light)
	_build_probes(root)
	_build_fog(root)
	return root


## [[node name, module-space transform], …] of the CIS_Light_<kind>_<n> nodes, in number order.
func _anchors_of(anchors: Dictionary, kind: String) -> Array:
	var keys: Array = anchors.keys().filter(func(key: String) -> bool: return key.begins_with("CIS_Light_%s_" % kind))
	keys.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var result: Array = []
	for key: String in keys:
		result.append([key, anchors[key]])
	return result


## The cistern_layout.json entry of a module's light node ({} when the layout has none).
func _module_light(module: String, node_name: String) -> Dictionary:
	var source := module
	var info: Dictionary = _modules.get(module, {})
	if bool(info.get("real", false)):
		source = str(info.source).get_file().get_basename()
	var lights: Variant = _layout_module(source).get("lights", [])
	if lights is Array:
		for entry: Variant in lights:
			if entry is Dictionary and str((entry as Dictionary).get("node", "")) == node_name:
				return entry
	return {}


static func _entry_color(entry: Dictionary, fallback: Color) -> Color:
	var value: Variant = entry.get("color_linear", entry.get("color"))
	if value is Array and (value as Array).size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _spot(parent: Node3D, node_name: String, world: Transform3D, color: Color, energy: float, reach: float, angle: float, fog: float) -> SpotLight3D:
	var lamp := SpotLight3D.new()
	lamp.name = node_name
	lamp.transform = parent.transform.affine_inverse() * world
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.light_volumetric_fog_energy = fog
	lamp.spot_range = reach
	lamp.spot_angle = angle
	lamp.spot_attenuation = 0.8
	lamp.spot_angle_attenuation = 1.4
	lamp.shadow_enabled = false
	lamp.light_cull_mask = LIGHT_CULL
	parent.add_child(lamp)
	return lamp


func _halo(parent: Node3D, node_name: String, world_position: Vector3, color: Color) -> OmniLight3D:
	var halo := OmniLight3D.new()
	halo.name = node_name
	halo.position = world_position - parent.position
	halo.light_color = color
	halo.light_energy = 0.8
	halo.omni_range = 3.5
	halo.omni_attenuation = 2.0
	halo.light_cull_mask = 0
	halo.light_volumetric_fog_energy = 3.0
	halo.light_specular = 0.0
	halo.shadow_enabled = false
	parent.add_child(halo)
	return halo


## Box-projected interior probes, one per 30 m of corridor, capturing only the hall (layer 11) from
## above runner height. CisternStage re-captures them once the rows are lit.
func _build_probes(root: Node3D) -> void:
	var probes := Node3D.new()
	probes.name = "Probes"
	root.add_child(probes)
	var count := int(ceil((Z1 - Z0) / PROBE_SPACING))
	for index in range(count):
		var center_z := Z0 + PROBE_SPACING * (float(index) + 0.5)
		var probe := ReflectionProbe.new()
		probe.name = "Probe%d" % index
		probe.position = Vector3(0.0, FLOOR_Y + (H + 1.0) * 0.5, center_z)
		probe.size = Vector3(HALL_W * 2.0 + 0.5, H + 1.0, PROBE_SPACING + 2.0)
		probe.origin_offset = Vector3(0.0, PROBE_CAPTURE_Y - (H + 1.0) * 0.5, 0.0)
		probe.box_projection = true
		probe.interior = true
		probe.enable_shadows = false
		probe.cull_mask = 1 << (HALL_LAYER - 1)
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.blend_distance = 2.0
		probe.intensity = 1.0
		probe.mesh_lod_threshold = 4.0
		probes.add_child(probe)


## Ground mist over the whole floor and a denser breath at the tunnel mouth (volumetric fog tiers).
func _build_fog(root: Node3D) -> void:
	var fog := Node3D.new()
	fog.name = "Fog"
	root.add_child(fog)
	var mist := FogMaterial.new()
	mist.density = 0.03
	mist.albedo = Color(0.82, 0.86, 0.90)
	mist.edge_fade = 0.6
	_save_resource(mist, GEN_DIR + "materials/fog_ground.tres")
	var ground := FogVolume.new()
	ground.name = "GroundMist"
	ground.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	ground.size = Vector3(HALL_W * 2.0, 2.4, Z1 - Z0)
	ground.position = Vector3(0.0, FLOOR_Y + 0.4, (Z0 + Z1) * 0.5)
	ground.material = mist
	fog.add_child(ground)
	# Extra density inside the shaft light: the column through the opening (only that light reaches it).
	var column_fog := FogMaterial.new()
	column_fog.density = 0.012
	column_fog.albedo = Color(0.85, 0.9, 0.96)
	column_fog.edge_fade = 0.4
	_save_resource(column_fog, GEN_DIR + "materials/fog_column.tres")
	var column := FogVolume.new()
	column.name = "ShaftColumn"
	column.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
	column.size = Vector3(15.0, H, 15.0)
	column.position = Vector3(0.0, FLOOR_Y + H * 0.5, 0.0)
	column.material = column_fog
	fog.add_child(column)
	var breath := FogMaterial.new()
	breath.density = 0.08
	breath.albedo = Color(0.78, 0.84, 0.88)
	breath.edge_fade = 1.2
	_save_resource(breath, GEN_DIR + "materials/fog_tunnel.tres")
	var tunnel := FogVolume.new()
	tunnel.name = "TunnelBreath"
	tunnel.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	tunnel.size = Vector3(14.0, 9.0, 14.0)
	tunnel.position = Vector3(0.0, FLOOR_Y + 3.5, Z0 + 1.0)
	tunnel.material = breath
	fog.add_child(tunnel)


## Decals (pillar numbers, efflorescence, rust under the lamp brackets, water marks) and airborne dust.
func _build_dressing() -> Node3D:
	var root := Node3D.new()
	root.name = "CisternDressing"
	var decals := Node3D.new()
	decals.name = "Decals"
	root.add_child(decals)
	var sprites := _decal_sprites()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	var inner := Layout.PILLAR_COLUMNS.filter(func(x: float) -> bool: return absf(x) < 20.0)
	for k in range(BAY_FIRST, BAY_LAST + 1):
		var row := k - BAY_FIRST
		var bay_z := BAY_PITCH * float(k)
		# Numbers on the corridor faces of the inner pillars: "<row>-<column>" (columns 1–6 from -X).
		for x: float in inner:
			var column := Layout.PILLAR_COLUMNS.find(x) + 1
			var label := "%d-%d" % [row + 1, column]
			var texture := _number_texture(label)
			var face_x := x - signf(x) * Layout.PILLAR_SIZE.x * 0.5
			_decal(decals, "Number_%s" % label, Vector3(face_x, FLOOR_Y + 2.6, bay_z + 1.7), Vector3(-signf(x), 0.0, 0.0), Vector2(1.5, 0.75), texture, 1.0)
		# Rust running down from the floodlight brackets.
		for x: float in inner:
			if rng.randf() < 0.75:
				var face_x := x - signf(x) * Layout.PILLAR_SIZE.x * 0.5
				_decal(decals, "Rust", Vector3(face_x, FLOOR_Y + LAMP_Y - 1.6, bay_z + LAMP_DZ + rng.randf_range(-0.4, 0.4)), Vector3(-signf(x), 0.0, 0.0),
					Vector2(rng.randf_range(0.6, 1.0), rng.randf_range(2.6, 3.6)), sprites.rust, rng.randf_range(0.6, 0.95))
		# Efflorescence from the beams down an outer pillar, and a water mark low on a pillar.
		var outer_x: float = [-25.8, 25.8, -38.7, 38.7][rng.randi_range(0, 3)]
		var bloom_side := -signf(outer_x)
		_decal(decals, "Efflorescence", Vector3(outer_x + bloom_side * 1.0, FLOOR_Y + H - 4.0, bay_z + rng.randf_range(1.5, 5.5)), Vector3(bloom_side, 0.0, 0.0),
			Vector2(rng.randf_range(1.2, 2.2), rng.randf_range(4.5, 7.0)), sprites.efflorescence, rng.randf_range(0.55, 0.9))
		var stain_x: float = inner[rng.randi_range(0, inner.size() - 1)]
		_decal(decals, "Stain", Vector3(stain_x, FLOOR_Y + 1.1, bay_z), Vector3(0.0, 0.0, -1.0),
			Vector2(rng.randf_range(1.4, 1.9), 2.2), sprites.stain, rng.randf_range(0.5, 0.8))
	_build_dust(root)
	return root


## Decal sprites: cut from the delivered atlas (cistern_layout.json "decals"), else the placeholders.
func _decal_sprites() -> Dictionary:
	var sprites := {}
	var atlas := _art_texture_plain("cistern_decals")
	var rects := _atlas_rects()
	for kind: String in ["efflorescence", "rust", "stain"]:
		var texture: Texture2D = null
		if atlas != null and rects.has(kind):
			var image := atlas.get_image()
			if image != null:
				if image.is_compressed():
					image.decompress()
				image.clear_mipmaps()
				var rect: Rect2i = rects[kind]
				var cropped := image.get_region(rect)
				cropped.generate_mipmaps()
				texture = ImageTexture.create_from_image(cropped)
		if texture == null:
			texture = TextureGen.decal_sprite(kind)
		sprites[kind] = _save_resource(texture, GEN_DIR + "decals/%s.res" % kind)
	return sprites


func _art_texture_plain(file_name: String) -> Texture2D:
	for path: String in [ART_DIR + "textures/%s.png" % file_name, ART_DIR + "%s.png" % file_name]:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## {kind: Rect2i} in atlas pixels from cistern_layout.json (list or map of {"name"/"kind", "rect": [x, y, w, h]}).
func _atlas_rects() -> Dictionary:
	var rects := {}
	var entries: Variant = _layout.get("decals", _layout.get("decal_atlas", []))
	var list: Array = []
	if entries is Dictionary:
		for key: String in (entries as Dictionary).keys():
			var value: Variant = entries[key]
			if value is Dictionary:
				var entry: Dictionary = (value as Dictionary).duplicate()
				entry["name"] = key
				list.append(entry)
	elif entries is Array:
		list = entries
	for entry: Variant in list:
		if not entry is Dictionary:
			continue
		var name := str((entry as Dictionary).get("name", (entry as Dictionary).get("kind", ""))).to_lower()
		var rect: Variant = (entry as Dictionary).get("rect", (entry as Dictionary).get("px", null))
		if rect is Array and (rect as Array).size() == 4:
			for kind: String in ["efflorescence", "rust", "stain"]:
				if kind in name or (kind == "stain" and "water" in name):
					if not rects.has(kind):
						rects[kind] = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
	return rects


func _number_texture(label: String) -> Texture2D:
	var path := GEN_DIR + "decals/number_%s.res" % label
	return _save_resource(TextureGen.number_texture(label), path) as Texture2D


## A decal on a surface whose outward normal is `normal`; size.x across, size.y down the surface.
func _decal(parent: Node3D, node_name: String, at: Vector3, normal: Vector3, size: Vector2, texture: Texture2D, strength: float) -> Decal:
	var decal := Decal.new()
	decal.name = node_name
	var y := normal.normalized()
	var down := Vector3.DOWN if absf(y.y) < 0.9 else Vector3.FORWARD
	var z := (down - y * down.dot(y)).normalized()
	var x := y.cross(z).normalized()
	decal.transform = Transform3D(Basis(x, y, z), at)
	decal.size = Vector3(size.x, 0.6, size.y)
	decal.texture_albedo = texture
	decal.albedo_mix = 1.0
	decal.modulate = Color(1.0, 1.0, 1.0, strength)
	decal.normal_fade = 0.5
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.cull_mask = 1 << (HALL_LAYER - 1)
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 90.0
	decal.distance_fade_length = 20.0
	parent.add_child(decal, true)
	return decal


## Fine dust over the corridor; the shader lights each speck by its row. CisternStage scales the amount.
func _build_dust(root: Node3D) -> void:
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 2400
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.randomness = 0.6
	dust.local_coords = false
	dust.position = Vector3(0.0, FLOOR_Y + 6.5, (Z0 + Z1) * 0.5)
	dust.visibility_aabb = AABB(Vector3(-14.0, -7.0, -122.0), Vector3(28.0, 14.0, 244.0))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(13.0, 6.5, 120.0)
	process.direction = Vector3(0.0, 1.0, 0.3)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.12
	process.gravity = Vector3(0.0, -0.015, 0.02)
	process.scale_min = 0.5
	process.scale_max = 1.4
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 6.0
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.06
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.85, Color(1.0, 1.0, 1.0, 1.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_save_resource(process, GEN_DIR + "materials/dust_process.tres")
	dust.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022)
	var material := ShaderMaterial.new()
	material.shader = load(DUST_SHADER) as Shader
	_save_resource(material, GEN_DIR + "materials/dust.tres")
	quad.material = material
	dust.draw_pass_1 = quad
	root.add_child(dust)


func _static_body(parent: Node3D, node_name: String, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	return body


func _box_shape(body: StaticBody3D, node_name: String, size: Vector3, center: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape, true)
	return shape


# ------------------------------------------------------------------ stage

func _build_stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "CisternStage"
	stage.set_script(load(STAGE_SCRIPT_PATH))
	var shell := Node3D.new()
	shell.name = "Shell"
	stage.add_child(shell)
	# Floor: same collision layer as the milestone-1 floor (swept bodies, door debris).
	var floor_body := _static_body(shell, "FloorCollision", 1)
	floor_body.position = Vector3(0.0, FLOOR_Y - 0.25, (Z0 + Z1) * 0.5)
	var floor_shape := _box_shape(floor_body, "Shape", Vector3(HALL_W * 2.0 + 2.0, 0.5, Z1 - Z0 + 2.0), Vector3.ZERO)
	floor_shape.name = "Shape"
	_build_opening(stage)
	var upstream := Node3D.new()
	upstream.name = "Upstream"
	stage.add_child(upstream)
	var balcony := Node3D.new()
	balcony.name = "Balcony"
	upstream.add_child(balcony)
	var mark := Marker3D.new()
	mark.name = "RefereeMark"
	var anchors: Dictionary = _anchors.get("cistern_end_upstream", {})
	var referee: Transform3D = anchors.get("CIS_RefereeMark", Transform3D(Basis.IDENTITY,
		Vector3(16.0, Layout.BALCONY_HEIGHT, Z0 + 3.0 + 2.6 - 0.9)))
	mark.position = Vector3(0.0, FLOOR_Y, 0.0) + referee.origin
	balcony.add_child(mark)
	_build_grade(stage)
	return stage


func _build_opening(stage: Node3D) -> void:
	var opening := Node3D.new()
	opening.name = "Opening"
	stage.add_child(opening)
	# The cool light column falling from the shaft (6.5: the only shadowed light). Its pool on the
	# hall floor comes from the hall shaders (cistern_row_grid.w); the light itself reaches the
	# runners, the deck and the fog.
	var light := SpotLight3D.new()
	light.name = "ShaftLight"
	light.light_color = Color(0.70, 0.82, 1.0)
	light.light_energy = SHAFT_LIGHT_ENERGY
	light.light_volumetric_fog_energy = 2.0
	light.spot_range = 34.0
	light.spot_angle = 24.0
	light.spot_attenuation = 0.6
	light.spot_angle_attenuation = 0.6
	light.shadow_enabled = false
	light.shadow_bias = 0.04
	light.light_cull_mask = LIGHT_CULL
	light.position = Vector3(0.0, Layout.ceiling_top_y() - 0.2, 0.0)
	light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	opening.add_child(light)
	# Without volumetric fog (low) the column is a faint additive cone.
	var column := MeshInstance3D.new()
	column.name = "LightColumn"
	var cone := CylinderMesh.new()
	cone.top_radius = Layout.OPENING_RADIUS - 0.4
	cone.bottom_radius = Layout.OPENING_RADIUS + 1.6
	cone.height = H
	cone.radial_segments = 32
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	column.mesh = cone
	var material := ShaderMaterial.new()
	material.shader = load(COLUMN_SHADER) as Shader
	material.set_shader_parameter("tint", Color(0.55, 0.68, 0.90, 0.07))
	material.set_shader_parameter("strength", 1.0)
	_save_resource(material, GEN_DIR + "materials/light_column.tres")
	column.material_override = material
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = Vector3(0.0, FLOOR_Y + H * 0.5, 0.0)
	opening.add_child(column)


## Restrained vignette and grain over the 3D view (under the HUD), shown with the stage.
func _build_grade(stage: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = -20
	layer.visible = false
	stage.add_child(layer)
	var rect := ColorRect.new()
	rect.name = "Overlay"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load(GRADE_SHADER) as Shader
	_save_resource(material, GEN_DIR + "materials/grade_overlay.tres")
	rect.material = material
	layer.add_child(rect)


func _write_manifest() -> void:
	var modules := {}
	for module: String in _modules.keys():
		var info: Dictionary = _modules[module]
		modules[module] = {"source": info.source, "real": info.real, "light": info.light, "light_max": info.light_max,
			"anchors": (_anchors.get(module, {}) as Dictionary).size()}
	_manifest = {"modules": modules, "lut": GEN_DIR + "textures/grade_lut.res", "built": Time.get_datetime_string_from_system()}
	_write_json(GEN_DIR + "manifest.json", _manifest)


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
