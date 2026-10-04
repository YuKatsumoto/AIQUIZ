extends SceneTree

## 地下ステージ（首都圏外郭放水路の調圧水槽を実寸で再現、docs/surge_tank_reproduction.md）のシーンを、
## Blenderで作って光を焼いた部品（assets/environment/surge_tank/）から組み立てる。
## Godot --headless --path . --script res://tools/sudden_death/build_tank_scenes.gd
## 書き出し：scenes/sudden_death/cistern_stage.tscn（CisternStage。床の当たり判定・審判の立ち位置・画面の仕上げ）と、
## CisternStage.add_part_step() が1フレームに1つずつ足す部分シーン
## tank_slices.tscn（柱の線0〜10の区画、床・斜面・棚の当たり判定、柱・壁の当たり判定）/ tank_ends.tscn（ポンプ側の端と
## 吸込口・立坑側の端と開口・第1立坑・見学者の通路と階段）/ tank_lights.tscn（線ごとの実ライト・反射プローブ・霧）/
## tank_dressing.tscn（柱の番号札・塵）。
## 材質・生成テクスチャは scenes/sudden_death/tank_generated/。生成物なので手で編集しない。
## scenes/sudden_death/tank_preview.tscn（エディターで開いて F6）は舞台を単独で歩いて見るプレビュー。

const STAGE_SCRIPT_PATH := "res://scripts/world/sudden_death/cistern_stage.gd"
const TextureGen := preload("res://tools/sudden_death/cistern_texture_gen.gd")
const OUT_DIR := "res://scenes/sudden_death/"
const GEN_DIR := "res://scenes/sudden_death/tank_generated/"
const ART_DIR := "res://assets/environment/surge_tank/"
const SHADER_DIR := "res://shaders/surge_tank/"
const GRADE_SHADER := "res://shaders/sudden_death/cistern_grade.gdshader"
const DUST_SHADER := "res://shaders/surge_tank/tank_dust.gdshader"
const FONT_PATH := "res://resources/fonts/NotoSansJP-Bold.otf"

## Must match CisternStage.
const MODULE_META := &"cistern_module"
const MATERIALS_META := &"cistern_materials"
const LIGHTS_PART := "CisternLights"
const HALL_LAYER := 11
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
## Every layer: the hall takes the real lamps' highlights through its light() (the bake is its diffuse).
const LIGHT_CULL := 0xFFFFF
const WALL_COLLISION_LAYER := 16

## The stage is the plan scaled by S about the landing point (0, FLOOR_Y, 0): the characters are about 2.1 m tall
## (head 0.44 m), so at 1 : 1 the tank read smaller than in the photos of its visitors (SuddenDeathLayout.TANK_SCALE).
const S := SuddenDeathLayout.TANK_SCALE
## Survey (MLIT plan, metres; tank_layout.json carries the same numbers). x = -v across, z = 132.8 - u along the tank.
const HALF_W := 35.5
## the shaft-side end wall (two 10 m openings to shaft No.1) and the pump-side gate face
const Z_SHAFT := -38.6
const Z_PUMP := 132.8
## the side walls close in from here to +-20 at the end wall
const Z_CHAMFER := -23.4
const END_HALF := 20.0
const H := 17.7
const SHELF_Y := 5.0
const LINE_PITCH := 14.0
const LINES := 11
const OPEN_HALF := 11.0

## material name -> [shader file, texture set prefix or "", uses the module light map]
const MATERIALS := {
	"TK_Concrete": ["tank_concrete", "concrete", true],
	"TK_Pillar": ["tank_pillar", "concrete", true],
	"TK_Floor": ["tank_floor", "floor", true],
	"TK_Steel": ["tank_steel", "steel", true],
	"TK_Paint": ["tank_steel", "steel", true],
	"TK_Galv": ["tank_steel", "galv", true],
	"TK_Grate": ["tank_grate", "grate", true],
	"TK_Lens": ["tank_lamp", "", false],
	"TK_Sky": ["tank_sky", "", false],
	"TK_Void": ["tank_void", "", false],
}
## Look of the hall materials (photos: warm, sediment-stained concrete; dark wet floor).
const LOOK := {
	"TK_Concrete": {"albedo_tint": Color(0.93, 0.88, 0.80), "roughness_scale": 1.0, "seepage": 0.22, "macro_strength": 0.12},
	"TK_Pillar": {"albedo_tint": Color(0.95, 0.90, 0.82), "roughness_scale": 0.95, "seepage": 0.25, "macro_strength": 0.1},
	# photos: the slab is wet all over (a film of water with puddles), brown with silt
	"TK_Floor": {"albedo_tint": Color(0.50, 0.38, 0.26), "roughness_scale": 1.0, "macro_strength": 0.16, "puddle_amount": 0.35,
		"puddle_roughness": 0.07, "damp_base": 0.85, "damp_roughness": 0.11, "damp_darkening": 0.45, "silt_amount": 0.45, "mud_amount": 0.2},
	"TK_Steel": {"albedo_tint": Color(0.9, 0.9, 0.9), "roughness_scale": 0.6, "metallic_value": 0.4, "seepage": 0.0, "macro_strength": 0.08},
	"TK_Paint": {"albedo_tint": Color(1.0, 1.0, 1.0), "roughness_scale": 0.55, "metallic_value": 0.0, "seepage": 0.05, "macro_strength": 0.08},
	"TK_Galv": {"albedo_tint": Color(0.68, 0.69, 0.70), "roughness_scale": 0.45, "metallic_value": 0.9, "seepage": 0.0, "macro_strength": 0.12},
	"TK_Grate": {"albedo_tint": Color(0.22, 0.23, 0.24), "roughness_scale": 0.6, "metallic_value": 0.4, "seepage": 0.0, "macro_strength": 0.05},
}
## Godot light per lamp kind (characters and the hall's highlights; spot angle is the half angle). Inverse-square
## fall-off like the Cycles lamps (attenuation 2), energies matched to the baked light on the floor.
const LIGHT_LOOK := {
	# the high-bays are Lambertian discs in the bake: a wide cone with a soft edge
	"Bay": {"energy": 900.0, "range": 34.0, "angle": 85.0, "attenuation": 2.0, "fog": 0.006, "specular": 1.0},
	"Wall": {"energy": 190.0, "range": 22.0, "angle": 56.0, "attenuation": 2.0, "fog": 0.006, "specular": 0.6},
	"Strip": {"energy": 26.0, "range": 9.0, "angle": 80.0, "attenuation": 2.0, "fog": 0.01, "specular": 0.4},
	"Shaft": {"energy": 900.0, "range": 70.0, "angle": 36.0, "attenuation": 2.0, "fog": 0.004, "specular": 0.5},
	"Sky": {"energy": 2400.0, "range": 90.0, "angle": 34.0, "attenuation": 2.0, "fog": 0.004, "specular": 0.3},
	"Exit": {"energy": 6.0, "range": 7.0, "angle": 80.0, "attenuation": 2.0, "fog": 0.05, "specular": 0.2},
}
const LENS_ENERGY := 55.0
const PROBE_COUNT := 6
const PROBE_CAPTURE_Y := 2.5
## The Cycles bakes are "exposure 0" in scene-linear units; Godot opens them up to the exposure of the official
## photo (matched shot 00_official_match of tests/tank_look_runtime.gd).
const LIGHT_SCALE := 2.7

var _failed := false
var _layout := {}
var _textures := {}
var _shared_materials := {}
var _instance_materials := {}
var _white_balance := Color(1.0, 1.0, 1.0)
var _font: Font = null


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	for sub: String in ["", "materials", "textures", "decals", "collision"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN_DIR + sub))
	_layout = _read_json(ART_DIR + "tank_layout.json")
	if _layout.is_empty():
		_fail("missing " + ART_DIR + "tank_layout.json (export the modules from Blender first)")
		quit(1)
		return
	_font = load(FONT_PATH) as Font
	# the camera of the reference photos leaves part of the lamps' warmth in (the stained concrete reads golden)
	_white_balance = _balance_for(_kelvin_color(4800.0)).lerp(Color(1.0, 1.0, 1.0), 0.45)
	_textures["macro"] = _save_resource(TextureGen.macro_noise(), GEN_DIR + "textures/macro_noise.res")
	_textures["lut"] = _save_resource(TextureGen.grade_lut_strip(), GEN_DIR + "textures/grade_lut.res")
	var parts: Array[PackedScene] = []
	for entry: Array in [["slices", _build_slices], ["ends", _build_ends], ["lights", _build_lights], ["dressing", _build_dressing]]:
		var path := OUT_DIR + "tank_%s.tscn" % entry[0]
		_save((entry[1] as Callable).call(), path)
		var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if scene == null:
			_fail("could not reload " + path)
		parts.append(scene)
	var stage := _build_stage()
	stage.set("part_scenes", parts)
	stage.set("flood_assets", _flood_assets())
	_save(stage, OUT_DIR + "cistern_stage.tscn")
	# A walk-through of the stage on its own (open it in the editor, F6).
	var preview := Node3D.new()
	preview.name = "TankPreview"
	preview.set_script(load("res://scripts/world/sudden_death/tank_preview.gd"))
	_save(preview, OUT_DIR + "tank_preview.tscn")
	_write_json(GEN_DIR + "manifest.json", {"layout": ART_DIR + "tank_layout.json", "instances": (_layout.get("instances", []) as Array).size(),
		"white_balance": [_white_balance.r, _white_balance.g, _white_balance.b], "tank_scale": S, "built": Time.get_datetime_string_from_system()})
	print("TANK_SCENES " + ("FAILED" if _failed else "OK"))
	quit(1 if _failed else 0)


# ------------------------------------------------------------------ helpers

func _fail(message: String) -> void:
	_failed = true
	push_error("[build_tank_scenes] " + message)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


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


## Approximate linear-sRGB colour of a blackbody (normalised to max 1), as in the Blender scripts.
static func _kelvin_color(kelvin: float) -> Color:
	var t := kelvin / 100.0
	var r := 255.0
	var g := 0.0
	var b := 255.0
	if t <= 66.0:
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	var c := [clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0]
	for i in range(3):
		c[i] = c[i] / 12.92 if c[i] <= 0.04045 else pow((c[i] + 0.055) / 1.055, 2.4)
	var m := maxf(c[0], maxf(c[1], c[2]))
	return Color(c[0] / m, c[1] / m, c[2] / m)


## Per-channel gain that maps `white` to a grey of the same luminance.
static func _balance_for(white: Color) -> Color:
	var luminance := 0.2126 * white.r + 0.7152 * white.g + 0.0722 * white.b
	return Color(luminance / maxf(white.r, 0.01), luminance / maxf(white.g, 0.01), luminance / maxf(white.b, 0.01))


func _balanced(color: Color) -> Color:
	return Color(color.r * _white_balance.r, color.g * _white_balance.g, color.b * _white_balance.b)


func _art_texture(prefix: String, channel: String) -> Texture2D:
	var path := ART_DIR + "textures/%s_%s.png" % [prefix, channel]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _hall_value(key: String, fallback: Variant) -> Variant:
	var hall: Variant = _layout.get("hall", {})
	return (hall as Dictionary).get(key, fallback) if hall is Dictionary else fallback


## A plan point (y over the trench floor) in the world.
func _w(plan: Vector3) -> Vector3:
	return Vector3(plan.x * S, FLOOR_Y + plan.y * S, plan.z * S)


## A collision box given in plan metres (centre y over the trench floor).
func _plan_box(body: StaticBody3D, node_name: String, size: Vector3, center: Vector3) -> CollisionShape3D:
	return _box_shape(body, node_name, size * S, _w(center))


## z of pillar line k in the plan (0 next to the pump end .. 10 next to the shaft-side end wall).
func line_z(k: int) -> float:
	return Z_PUMP - 20.8 - LINE_PITCH * float(k)


## Light row of a lamp at z: row r = the lamps of line 10 - r (rows run from the shaft end toward the pumps).
## The high-bays hang in the coffers of their line, at the line's own z.
func light_row(_kind: String, z: float) -> int:
	var k := clampi(int(round((line_z(0) - z) / LINE_PITCH)), 0, LINES - 1)
	return LINES - 1 - k


# ------------------------------------------------------------------ materials

## The material of `name` for a light-mapped instance (its own map), or the shared one (lenses, sky, voids).
func _material(name: String, unit: String, light_path: String, light_max: float) -> Material:
	var spec: Array = MATERIALS.get(name, ["tank_concrete", "concrete", true])
	if not bool(spec[2]):
		if _shared_materials.has(name):
			return _shared_materials[name]
		var shared := ShaderMaterial.new()
		shared.shader = load(SHADER_DIR + "%s.gdshader" % spec[0]) as Shader
		shared.resource_name = name
		shared.set_shader_parameter("tank_scale", S)
		if name == "TK_Lens":
			shared.set_shader_parameter("energy", LENS_ENERGY)
			shared.set_shader_parameter("white_balance", Vector3(_white_balance.r, _white_balance.g, _white_balance.b))
			var lens := _kelvin_color(4800.0)
			shared.set_shader_parameter("lens_color", Color(lens.r, lens.g, lens.b, 1.0))
		_shared_materials[name] = _save_resource(shared, GEN_DIR + "materials/shared__%s.tres" % name.to_snake_case())
		return _shared_materials[name]
	var key := unit + "/" + name
	if _instance_materials.has(key):
		return _instance_materials[key]
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_DIR + "%s.gdshader" % spec[0]) as Shader
	material.resource_name = name
	var prefix: String = spec[1]
	for channel: String in ["albedo", "normal", "orm"]:
		var texture := _art_texture(prefix, channel)
		if texture != null:
			material.set_shader_parameter(channel + "_tex", texture)
	var detail := _art_texture("detail", "normal")
	if detail != null and name in ["TK_Concrete", "TK_Pillar", "TK_Floor"]:
		material.set_shader_parameter("detail_normal_tex", detail)
	material.set_shader_parameter("macro_noise", _textures.macro)
	material.set_shader_parameter("white_balance", Vector3(_white_balance.r, _white_balance.g, _white_balance.b))
	material.set_shader_parameter("floor_y", FLOOR_Y)
	material.set_shader_parameter("tank_scale", S)
	if not light_path.is_empty() and ResourceLoader.exists(light_path):
		material.set_shader_parameter("light_tex", load(light_path))
	else:
		_fail("%s: light map %s missing" % [unit, light_path])
	material.set_shader_parameter("light_max", light_max)
	material.set_shader_parameter("light_scale", LIGHT_SCALE)
	var metres := float((_layout.get("uv0_metres_per_unit", {}) as Dictionary).get(name, 3.75 if prefix in ["concrete", "floor"] else 1.0))
	material.set_shader_parameter("uv_metres", metres)
	material.set_shader_parameter("uv_scale", 1.0)
	for param: String in (LOOK.get(name, {}) as Dictionary).keys():
		material.set_shader_parameter(param, LOOK[name][param])
	if name in ["TK_Steel", "TK_Paint", "TK_Galv", "TK_Grate"]:
		material.set_shader_parameter("detail_strength", 0.0)
	_instance_materials[key] = _save_resource(material, GEN_DIR + "materials/%s__%s.tres" % [unit.to_lower(), name.to_snake_case()])
	return _instance_materials[key]


## [[name, material], ...] for CisternStage._dress_module.
func _material_table(unit: String, light_path: String, light_max: float) -> Array:
	var table: Array = []
	for name: String in MATERIALS.keys():
		table.append([name, _material(name, unit, light_path, light_max)])
	return table


func _instance(entry: Dictionary, node_name: String) -> Node3D:
	var module := str(entry.get("module", ""))
	var scene := load(ART_DIR + module + ".glb") as PackedScene
	if scene == null:
		_fail("module scene missing: " + module)
		return Node3D.new()
	var node := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	node.name = node_name
	node.position = Vector3(0.0, FLOOR_Y, float(entry.get("z", 0.0)) * S)
	node.scale = Vector3.ONE * S
	var unit := str(entry.get("unit", node_name))
	var light_path := ART_DIR + str(entry.get("lightmap", ""))
	node.set_meta(MODULE_META, unit)
	node.set_meta(MATERIALS_META, _material_table(unit, light_path, float(entry.get("light_max", 1.0))))
	return node


func _entries(units: Array) -> Array:
	var out: Array = []
	for entry: Variant in _layout.get("instances", []):
		if entry is Dictionary and str((entry as Dictionary).get("unit", "")) in units:
			out.append(entry)
	return out


# ------------------------------------------------------------------ parts

## Slices of pillar lines 0..10 (each its own GLB and light map); the floor, slopes, shelves and walls as an exact
## collision (from the modules' own floor and concrete meshes); pillars and side walls as obstacles for swept bodies.
func _build_slices() -> Node3D:
	var root := Node3D.new()
	root.name = "TankSlices"
	var units: Array = []
	for k in range(LINES):
		units.append("K%02d" % k)
	var floor_body := _static_body(root, "FloorCollision", 1)
	floor_body.position = Vector3(0.0, FLOOR_Y, 0.0)
	for entry: Dictionary in _entries(units):
		var node := _instance(entry, "Slice_%s" % entry.unit)
		root.add_child(node)
		_trimesh_shapes(floor_body, node, str(entry.unit))
	var walls := _static_body(root, "WallCollision", WALL_COLLISION_LAYER)
	for pillar: Variant in _hall_value("pillars", []):
		var p := pillar as Dictionary
		# a 2.9 x 7.9 box keeps characters off the base flare
		_plan_box(walls, "Pillar", Vector3(2.9, H, 7.9), Vector3(float(p.x), H * 0.5, float(p.z)))
	var straight := Z_PUMP - Z_CHAMFER
	for side: float in [-1.0, 1.0]:
		_plan_box(walls, "SideWall", Vector3(1.0, H, straight), Vector3(side * (HALF_W + 0.5), H * 0.5, (Z_CHAMFER + Z_PUMP) * 0.5))
		# the chamfered stretch before the shaft-side end wall
		var a := Vector2(side * HALF_W, Z_CHAMFER)
		var b := Vector2(side * END_HALF, Z_SHAFT)
		var mid := (a + b) * 0.5
		var along := (b - a)
		var outward := Vector2(side, 0.0).project(Vector2(-along.y, along.x).normalized()).normalized()
		var shape := _plan_box(walls, "ChamferWall", Vector3(1.0, H, along.length() + 1.0), Vector3(mid.x + outward.x * 0.5, H * 0.5, mid.y + outward.y * 0.5))
		shape.rotation.y = atan2(along.x, along.y)
	return root


## Exact static collision from a module's floor and concrete meshes (trench floor, slopes, shelves, fillets, walls),
## saved beside the materials so the part scene stays small.
func _trimesh_shapes(body: StaticBody3D, module: Node, unit: String) -> void:
	for child: Node in module.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if not (str(mi.name).begins_with("TK_Floor") or str(mi.name).begins_with("TK_Concrete") or str(mi.name).begins_with("TK_Pillar")):
			continue
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		# scaled shapes are poorly supported by the physics: put the stage scale into the faces
		var faces := shape.get_faces()
		for i in range(faces.size()):
			faces[i] = faces[i] * S
		shape.set_faces(faces)
		var holder := CollisionShape3D.new()
		holder.name = "%s_%s" % [unit, str(mi.name)]
		holder.shape = _save_resource(shape, GEN_DIR + "collision/%s__%s.res" % [unit.to_lower(), str(mi.name).to_snake_case()])
		# the module and the body both sit at (0, FLOOR_Y, 0); the meshes are direct children of the module root
		holder.transform = Transform3D(mi.transform.basis, mi.transform.origin * S)
		body.add_child(holder, true)


func _build_ends() -> Node3D:
	var root := Node3D.new()
	root.name = "TankEnds"
	var floor_body := _static_body(root, "FloorCollision", 1)
	floor_body.position = Vector3(0.0, FLOOR_Y, 0.0)
	for entry: Dictionary in _entries(["P", "S", "Q", "T"]):
		var node := _instance(entry, {"S": "EndShaft", "Q": "Shaft1", "P": "EndPump", "T": "Stairs"}[str(entry.unit)])
		root.add_child(node)
		if str(entry.unit) != "Q":
			_trimesh_shapes(floor_body, node, str(entry.unit))
	var walls := _static_body(root, "WallCollision", WALL_COLLISION_LAYER)
	# shaft-side end wall beside the two openings, the fence at the drop into shaft No.1, the concrete blocks
	for side: float in [-1.0, 1.0]:
		var width := END_HALF - OPEN_HALF
		_plan_box(walls, "EndWall", Vector3(width, H, 1.0), Vector3(side * (OPEN_HALF + width * 0.5), H * 0.5, Z_SHAFT - 0.5))
	_plan_box(walls, "ShaftFence", Vector3(OPEN_HALF * 2.0, 2.0, 0.3), Vector3(0.0, 1.0, Z_PUMP - 179.3))
	_plan_box(walls, "OpeningPier", Vector3(2.0, H, 8.0), Vector3(0.0, H * 0.5, Z_SHAFT - 4.0))
	for i in range(7):
		_plan_box(walls, "Block", Vector3(1.0, 0.85, 0.9), Vector3(12.0 - 4.0 * float(i), 0.425, Z_SHAFT + 1.45))
	# pump-side gate face (the intake channels sit behind their sills) and the five dividing walls
	_plan_box(walls, "GateFace", Vector3(HALF_W * 2.0, H, 1.0), Vector3(0.0, H * 0.5, Z_PUMP + 0.5))
	for x: float in [-28.0, -14.0, 0.0, 14.0, 28.0]:
		_plan_box(walls, "DividingWall", Vector3(2.0, H, 9.3), Vector3(x, H * 0.5, Z_PUMP - 4.65))
	# the door portal of the visitor access on the -x side wall
	_plan_box(walls, "Portal", Vector3(1.0, 3.2, 3.7), Vector3(-35.0, SHELF_Y + 1.6, Z_PUMP - 152.25))
	return root


## Real lights (characters, and the highlights of the hall in its light()): per pillar line a row with the
## pendant lamps in that line's coffers, the wall floods of the line and what hangs nearby (intake channels,
## stairs); the shaft light; reflection probes; fog. Positions and kinds come from the modules'
## TK_Light_<kind>_<name> anchors.
func _build_lights() -> Node3D:
	var root := Node3D.new()
	root.name = LIGHTS_PART
	var rows: Array[Node3D] = []
	for r in range(LINES):
		var row := Node3D.new()
		row.name = "Row%02d" % r
		row.position = Vector3(0.0, 0.0, line_z(LINES - 1 - r) * S)
		root.add_child(row)
		rows.append(row)
	var modules: Dictionary = _layout.get("modules", {})
	var count := 0
	for entry: Variant in _layout.get("instances", []):
		var inst := entry as Dictionary
		var module: Dictionary = modules.get(str(inst.module), {})
		var dz := float(inst.get("z", 0.0))
		for light: Variant in module.get("lights", []):
			var l := light as Dictionary
			var pos_a: Array = l.get("position", [0, 0, 0])
			var dir_a: Array = l.get("direction", [0, -1, 0])
			var plan_z := float(pos_a[2]) + dz
			var pos := _w(Vector3(float(pos_a[0]), float(pos_a[1]), plan_z))
			var dir := Vector3(float(dir_a[0]), float(dir_a[1]), float(dir_a[2])).normalized()
			var kind := str(l.get("kind", "Bay"))
			var row := rows[light_row(kind, plan_z)]
			var color := _entry_color(l)
			var look: Dictionary = LIGHT_LOOK.get(kind, LIGHT_LOOK.Bay)
			var name := "%s_%s_%d" % [kind, str(inst.unit), count]
			count += 1
			if kind in ["Strip", "Exit"]:
				var omni := OmniLight3D.new()
				omni.name = name
				omni.position = pos - row.position
				omni.light_color = color
				# distances grow by S: keep the illuminance (inverse square)
				omni.light_energy = float(look.energy) * S * S
				omni.omni_range = float(look.range) * S
				omni.omni_attenuation = float(look.attenuation)
				omni.light_volumetric_fog_energy = float(look.fog)
				omni.light_specular = float(look.specular)
				omni.light_cull_mask = LIGHT_CULL
				omni.shadow_enabled = false
				row.add_child(omni)
			else:
				var spot := SpotLight3D.new()
				spot.name = name
				var up := Vector3.FORWARD if absf(dir.y) > 0.95 else Vector3.UP
				spot.transform = Transform3D(Basis.looking_at(dir, up), pos - row.position)
				spot.light_color = color
				spot.light_energy = float(look.energy) * S * S
				spot.spot_range = float(look.range) * S
				spot.spot_angle = float(look.angle)
				spot.spot_attenuation = float(look.attenuation)
				spot.spot_angle_attenuation = 1.2
				spot.light_volumetric_fog_energy = float(look.fog)
				spot.light_specular = float(look.specular)
				spot.light_cull_mask = LIGHT_CULL
				spot.shadow_enabled = false
				row.add_child(spot)
	_build_probes(root)
	_build_fog(root)
	print("lights: %d real lights in %d rows" % [count, LINES])
	return root


func _entry_color(entry: Dictionary) -> Color:
	var kelvin := float(entry.get("kelvin", 4800.0))
	if kelvin <= 0.0:
		return Color(0.05, 1.0, 0.3)
	return _balanced(_kelvin_color(kelvin))


## Box-projected interior probes along the tank, capturing only the hall (layer 11) from standing height;
## CisternStage re-captures them once the rows are lit. One more for the bright end at shaft No.1.
func _build_probes(root: Node3D) -> void:
	var probes := Node3D.new()
	probes.name = "Probes"
	root.add_child(probes)
	var length := (Z_PUMP - Z_SHAFT) * S / float(PROBE_COUNT)
	for index in range(PROBE_COUNT):
		var center_z := Z_SHAFT * S + length * (float(index) + 0.5)
		var probe := ReflectionProbe.new()
		probe.name = "Probe%d" % index
		probe.position = Vector3(0.0, FLOOR_Y + H * S * 0.5, center_z)
		probe.size = Vector3(HALF_W * 2.0 * S + 0.5, H * S + 0.5, length + 2.0)
		probe.origin_offset = Vector3(0.0, (PROBE_CAPTURE_Y - H * 0.5) * S, 0.0)
		probe.box_projection = true
		probe.interior = true
		probe.enable_shadows = false
		probe.cull_mask = 1 << (HALL_LAYER - 1)
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.blend_distance = 3.0
		probe.intensity = 1.0
		probe.mesh_lod_threshold = 4.0
		probe.max_distance = 200.0 * S
		probes.add_child(probe)


## A thin haze in the trench (the volumetric fog of the environment carries the lamp cones); a little more mist in
## the damp air at the openings to shaft No.1.
func _build_fog(root: Node3D) -> void:
	var fog := Node3D.new()
	fog.name = "Fog"
	root.add_child(fog)
	var mist := FogMaterial.new()
	mist.density = 0.018
	mist.albedo = Color(0.84, 0.86, 0.88)
	mist.edge_fade = 0.8
	_save_resource(mist, GEN_DIR + "materials/fog_ground.tres")
	var ground := FogVolume.new()
	ground.name = "GroundMist"
	ground.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	ground.size = Vector3(HALF_W * 2.0, 2.0, Z_PUMP - Z_SHAFT) * S
	ground.position = _w(Vector3(0.0, 0.5, (Z_SHAFT + Z_PUMP) * 0.5))
	ground.material = mist
	fog.add_child(ground)
	var breath := FogMaterial.new()
	breath.density = 0.035
	breath.albedo = Color(0.86, 0.9, 0.95)
	breath.edge_fade = 1.4
	_save_resource(breath, GEN_DIR + "materials/fog_shaft.tres")
	var shaft := FogVolume.new()
	shaft.name = "ShaftBreath"
	shaft.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	shaft.size = Vector3(30.0, 24.0, 24.0) * S
	shaft.position = _w(Vector3(0.0, 9.0, Z_SHAFT - 6.0))
	shaft.material = breath
	fog.add_child(shaft)


## Number plates on the shaft-side end of every pillar (white, black lettering, 2.3 m up) and airborne dust.
func _build_dressing() -> Node3D:
	var root := Node3D.new()
	root.name = "CisternDressing"
	var decals := Node3D.new()
	decals.name = "Decals"
	root.add_child(decals)
	var index := 0
	for pillar: Variant in _hall_value("pillars", []):
		var p := pillar as Dictionary
		index += 1
		var label := "%d" % index
		var texture := _plate_texture(["No." + label])
		var base := SHELF_Y if bool(p.get("on_shelf", false)) else 0.0
		var face := _w(Vector3(float(p.x), base + 2.35, float(p.z) - 3.5))
		_decal(decals, "Plate_%02d" % index, face, Vector3(0.0, 0.0, -1.0), Vector2(0.62, 0.38) * S, texture, 1.0)
	_build_dust(root)
	return root


## A white enamel plate with dark lettering (one or two lines), slightly worn.
func _plate_texture(lines: Array, w := 256, h := 160) -> Texture2D:
	var key := "_".join(lines).replace(".", "").replace(" ", "")
	var path := GEN_DIR + "decals/plate_%s.res" % key
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var plate := Color(0.86, 0.85, 0.80, 1.0)
	image.fill(Color(plate.r, plate.g, plate.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var margin := 6
	for y in range(h):
		for x in range(w):
			var inside := x >= margin and y >= margin and x < w - margin and y < h - margin
			if not inside:
				continue
			var grime := 0.92 + 0.08 * rng.randf() - 0.18 * float(y) / float(h) * rng.randf()
			image.set_pixel(x, y, Color(plate.r * grime, plate.g * grime, plate.b * grime * 0.97, 1.0))
	if _font != null:
		var ts := TextServerManager.get_primary_interface()
		var font_size := int(float(h) * (0.5 if lines.size() == 1 else 0.32))
		for li in range(lines.size()):
			var shaped := ts.create_shaped_text()
			ts.shaped_text_add_string(shaped, str(lines[li]), _font.get_rids(), font_size)
			ts.shaped_text_shape(shaped)
			var width := ts.shaped_text_get_width(shaped)
			var ascent := ts.shaped_text_get_ascent(shaped)
			var descent := ts.shaped_text_get_descent(shaped)
			var line_h := float(h - margin * 2) / float(lines.size())
			var pen := Vector2((float(w) - width) * 0.5, float(margin) + line_h * float(li) + (line_h - (ascent + descent)) * 0.5 + ascent)
			for glyph: Dictionary in ts.shaped_text_get_glyphs(shaped):
				_blit_glyph(image, ts, glyph, pen, font_size, Color(0.08, 0.08, 0.09))
				pen.x += float(glyph.get("advance", 0.0))
			ts.free_rid(shaped)
	image.generate_mipmaps()
	return _save_resource(ImageTexture.create_from_image(image), path) as Texture2D


func _blit_glyph(image: Image, ts: TextServer, glyph: Dictionary, pen: Vector2, font_size: int, ink: Color) -> void:
	var font_rid: RID = glyph.get("font_rid", RID())
	if not font_rid.is_valid():
		return
	var index: int = int(glyph.get("index", 0))
	var gsize := Vector2i(int(glyph.get("font_size", font_size)), 0)
	ts.font_render_glyph(font_rid, gsize, index)
	var texture_index := ts.font_get_glyph_texture_idx(font_rid, gsize, index)
	if texture_index < 0:
		return
	var uv := ts.font_get_glyph_uv_rect(font_rid, gsize, index)
	var offset := ts.font_get_glyph_offset(font_rid, gsize, index)
	var glyph_size := ts.font_get_glyph_size(font_rid, gsize, index)
	var cache := ts.font_get_texture_image(font_rid, gsize, texture_index)
	if cache == null or glyph_size.x <= 0.0 or glyph_size.y <= 0.0:
		return
	var origin := pen + Vector2(glyph.get("offset", Vector2.ZERO)) + offset
	for gy in range(int(ceil(glyph_size.y))):
		for gx in range(int(ceil(glyph_size.x))):
			var tx := int(origin.x) + gx
			var ty := int(origin.y) + gy
			if tx < 0 or ty < 0 or tx >= image.get_width() or ty >= image.get_height():
				continue
			var sx := int(uv.position.x + float(gx) * uv.size.x / glyph_size.x)
			var sy := int(uv.position.y + float(gy) * uv.size.y / glyph_size.y)
			if sx < 0 or sy < 0 or sx >= cache.get_width() or sy >= cache.get_height():
				continue
			var coverage := cache.get_pixel(sx, sy).a
			if coverage <= 0.0:
				continue
			var base := image.get_pixel(tx, ty)
			image.set_pixel(tx, ty, Color(lerpf(base.r, ink.r, coverage), lerpf(base.g, ink.g, coverage), lerpf(base.b, ink.b, coverage), maxf(base.a, coverage)))


## A decal on a surface whose outward normal is `normal`; size.x across, size.y down the surface.
func _decal(parent: Node3D, node_name: String, at: Vector3, normal: Vector3, size: Vector2, texture: Texture2D, strength: float) -> Decal:
	var decal := Decal.new()
	decal.name = node_name
	var y := normal.normalized()
	var down := Vector3.DOWN if absf(y.y) < 0.9 else Vector3.FORWARD
	var z := (down - y * down.dot(y)).normalized()
	var x := y.cross(z).normalized()
	decal.transform = Transform3D(Basis(x, y, z), at)
	decal.size = Vector3(size.x, 0.5, size.y)
	decal.texture_albedo = texture
	decal.albedo_mix = 1.0
	decal.modulate = Color(1.0, 1.0, 1.0, strength)
	decal.normal_fade = 0.3
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05
	decal.cull_mask = 1 << (HALL_LAYER - 1)
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 70.0
	decal.distance_fade_length = 20.0
	parent.add_child(decal, true)
	return decal


## Fine dust in the lamp light over the whole tank; CisternStage scales the amount by quality.
func _build_dust(root: Node3D) -> void:
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 2400
	dust.lifetime = 16.0
	dust.preprocess = 16.0
	dust.randomness = 0.6
	dust.local_coords = false
	dust.position = _w(Vector3(0.0, 7.5, (Z_SHAFT + Z_PUMP) * 0.5))
	dust.visibility_aabb = AABB(Vector3(-37.0, -8.5, -88.0) * S, Vector3(74.0, 17.0, 176.0) * S)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(HALF_W - 0.5, 7.0, (Z_PUMP - Z_SHAFT) * 0.5) * S
	process.direction = Vector3(0.0, 1.0, 0.2)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.1
	process.gravity = Vector3(0.0, -0.012, 0.015)
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
	quad.size = Vector2(0.02, 0.02)
	var material := ShaderMaterial.new()
	material.shader = load(DUST_SHADER) as Shader
	material.set_shader_parameter("tank_scale", S)
	material.set_shader_parameter("floor_y", FLOOR_Y)
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

## The flood's assets the runtime water (CisternFlow) still borrows: foam, water normal, spray. Kept from the
## previous stage so the current sudden death keeps running on the new hall.
func _flood_assets() -> Array[Resource]:
	var assets: Array[Resource] = []
	var old := load(OUT_DIR + "cistern_stage.tscn") as PackedScene
	if old != null:
		var state := old.get_state()
		for i in range(state.get_node_property_count(0)):
			if state.get_node_property_name(0, i) == &"flood_assets":
				for value: Variant in state.get_node_property_value(0, i):
					if value is Resource:
						assets.append(value)
	return assets


func _build_stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "CisternStage"
	stage.set_script(load(STAGE_SCRIPT_PATH))
	var shell := Node3D.new()
	shell.name = "Shell"
	stage.add_child(shell)
	var floor_body := _static_body(shell, "FloorCollision", 1)
	floor_body.position = Vector3(0.0, FLOOR_Y - 0.25, (Z_SHAFT + Z_PUMP) * 0.5 * S)
	var floor_shape := _box_shape(floor_body, "Shape", Vector3(HALF_W * 2.0 * S, 0.5, (Z_PUMP - Z_SHAFT) * S), Vector3.ZERO)
	floor_shape.name = "Shape"
	# the trench floor before the parts arrive (the slices carry the exact floor, slopes and shelves);
	# no ceiling opening in the real tank: the referee stands on the floor of the visitor area
	var upstream := Node3D.new()
	upstream.name = "Upstream"
	stage.add_child(upstream)
	var balcony := Node3D.new()
	balcony.name = "Balcony"
	upstream.add_child(balcony)
	var mark := Marker3D.new()
	mark.name = "RefereeMark"
	mark.position = Vector3(6.0, FLOOR_Y, -9.0)
	balcony.add_child(mark)
	_build_grade(stage)
	return stage


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
