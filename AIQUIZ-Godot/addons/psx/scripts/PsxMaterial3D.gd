@tool class_name PsxMaterial3D extends ShaderMaterial

enum FogMode {
	## No fog of any kind will be applied.
	DISABLED,
	## Regular, non-PSX, per-pixel fog will be used.
	PER_PIXEL,
	## This is the default value for PSX-style fog.
	PER_VERTEX,
	## Vertex fog will always be applied regardless of distance. For use in things like skyboxes. Use with vertex lighting for a complete effect.
	ALWAYS,
}

const TRANSFERABLE_PARAMS: PackedStringArray = [
	&"alpha_scissor_threshold",
	&"cull_mode",
	&"depth_test",
	&"albedo_texture",
	&"albedo_color",
	&"emission_enabled",
	&"emission",
	&"emission_energy_multiplier",
	&"emission_operator",
	&"emission_on_uv2",
	&"emission_texture",
	&"billboard_mode",
]


#region Shader Compilation

const SHADER_TEMPLATE := preload("res://addons/psx/shaders/psx_template.gdshader")
const SHADER_CODE_INSERT_POSITION := 20 ## "shader_type spatial;\n" == 20
const SHADER_CACHE_DIR := "res://addons/psx/shaders/cache"
const SHADER_PATH_TEMPLATE := "res://addons/psx/shaders/cache/psx_%05d.gdshader"
const SHADER_FLAGS_ALWAYS := ["blend_mix", "diffuse_lambert", "specular_occlusion_disabled", "specular_disabled", "shadows_disabled"]
const SHADER_FLAGS := [
	["#ALPHA_DISABLED", "depth_draw_opaque,#ALPHA_SCISSOR", "depth_draw_always"],
	["cull_back", "cull_front", "cull_disabled"],
	["depth_test_default", "depth_test_inverted", "depth_test_disabled"],
	["unshaded", "", "vertex_lighting"],
	["fog_disabled", "", "fog_disabled,#VERTEX_FOG_ENABLED", "fog_disabled,#VERTEX_FOG_ALWAYS"],
	["", "#EMISSION_ADD", "#EMISSION_MULTIPLY"],
	[
		"#BILLBOARD_DISABLED",
		"#BILLBOARD_ENABLED",
		"#BILLBOARD_ENABLED,#BILLBOARD_KEEP_SCALE",
		"#BILLBOARD_FIXED_Y",
		"#BILLBOARD_FIXED_Y,#BILLBOARD_KEEP_SCALE",
		"#BILLBOARD_PARTICLES",
		"#BILLBOARD_PARTICLES,#BILLBOARD_KEEP_SCALE",
	],
]

static var SHADER_DEFAULT_INDEX := 210
static var SHADER_FLAGS_PERMUTATION_SIZES: PackedInt32Array
static var SHADER_FLAGS_CACHE: PackedStringArray
static var SHADER_CACHE: Dictionary[int, Shader]


static func touch_shader(idx: int) -> Shader:
	if not SHADER_CACHE.has(idx):
		var path := SHADER_PATH_TEMPLATE % idx
		if not ResourceLoader.exists(path):
			rebuild_shader(idx)

		SHADER_CACHE[idx] = ResourceLoader.load(path)

	return SHADER_CACHE[idx]


static func rebuild_shader(idx: int) -> void:
	for fdx in SHADER_FLAGS.size():
		SHADER_FLAGS_CACHE[fdx + SHADER_FLAGS_ALWAYS.size()] = SHADER_FLAGS[fdx][(idx / SHADER_FLAGS_PERMUTATION_SIZES[fdx] % SHADER_FLAGS[fdx].size())]

	var render_flags_string: String
	var define_flags_string: String

	for flag in SHADER_FLAGS_CACHE:
		if flag.is_empty(): continue
		for subflag in flag.split(","):
			if subflag.begins_with("#"):
				define_flags_string += "\n#define " + subflag.right(-1) + ";"
			else:
				render_flags_string += subflag + ", "

	render_flags_string = "\nrender_mode " + render_flags_string.left(-2) + ";"

	SHADER_CACHE[idx] = Shader.new()
	SHADER_CACHE[idx].code = SHADER_TEMPLATE.code.insert(SHADER_CODE_INSERT_POSITION, render_flags_string + define_flags_string)
	SHADER_CACHE[idx].take_over_path(SHADER_PATH_TEMPLATE % idx)
	ResourceSaver.save(SHADER_CACHE[idx])


static func rebuild_shaders() -> void:
	for idx in SHADER_CACHE.size():
		if not SHADER_CACHE.has(idx): continue
		rebuild_shader(idx)


static func purge_unused_shaders() -> void:
	var purge_list = Psx.get_resources([SHADER_CACHE_DIR], "Shader")
	var items_purged := 0

	for shader: Shader in purge_list.duplicate():
		if shader.get_reference_count() > 2: continue

		DirAccess.remove_absolute(shader.resource_path)
		shader.take_over_path("")
		items_purged += 1

	var popup := AcceptDialog.new()
	popup.dialog_autowrap = true
	popup.size.x = 300.0
	if items_purged:
		popup.dialog_text = "%s cached shaders purged." % items_purged
	else:
		popup.dialog_text = "No cached shaders were purged. This is an action that is only effective after an editor restart. This means either you need to restart the editor and try again, or all shaders are in use."
	EditorInterface.get_editor_main_screen().add_child(popup)

	popup.popup_centered()
	await popup.confirmed

	popup.queue_free()


static func _static_init() -> void:
	DirAccess.remove_absolute(SHADER_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(SHADER_CACHE_DIR)

	SHADER_FLAGS_PERMUTATION_SIZES.resize(SHADER_FLAGS.size())
	SHADER_FLAGS_PERMUTATION_SIZES.fill(1)
	for i in SHADER_FLAGS.size():
		for j in SHADER_FLAGS.size() - i - 1:
			SHADER_FLAGS_PERMUTATION_SIZES[i] *= SHADER_FLAGS[-j - 1].size()

	SHADER_FLAGS_CACHE = SHADER_FLAGS_ALWAYS.duplicate()
	for f in SHADER_FLAGS.size():
		SHADER_FLAGS_CACHE.push_back(SHADER_FLAGS[f][0])

	## This is where it should go, but doing so causes issues across the board.
	# purge_unused_shaders()


#endregion

@export_subgroup("Transparency")

@export_enum("Opaque", "Cutout", "Transparent") var transparency_mode: int = 0:
	set(value):
		transparency_mode = value
		refresh_shader()


@export var cull_mode := BaseMaterial3D.CullMode.CULL_BACK:
	set(value):
		cull_mode = value
		refresh_shader()


@export_enum("Default", "Inverted", "Disabled") var depth_test: int = 0:
	set(value):
		depth_test = value
		refresh_shader()


@export_range(0.0, 1.0, 0.001) var alpha_scissor_threshold: float = 0.5:
	set(value):
		alpha_scissor_threshold = value
		set_shader_parameter(&"alpha_scissor_threshold", alpha_scissor_threshold if transparency_mode == 1 else 0.0)


@export_subgroup("Shading")


@export_enum("Unshaded", "Per-Pixel", "Per-Vertex") var shading_mode: int = 2:
	set(value):
		shading_mode = value
		refresh_shader()


@export var fog_mode: FogMode = FogMode.PER_VERTEX:
	set(value):
		fog_mode = value
		refresh_shader()


@export_subgroup("Color")

@export var vertex_color_use_as_albedo: bool = true:
	set(value):
		vertex_color_use_as_albedo = value
		set_shader_parameter(&"u_vertex_color_use_as_albedo", vertex_color_use_as_albedo)


@export var albedo_texture: Texture2D = null:
	set(value):
		albedo_texture = value
		set_shader_parameter(&"u_albedo_texture", albedo_texture)


@export var albedo_color: Color = Color.WHITE:
	set(value):
		albedo_color = value
		set_shader_parameter(&"u_albedo_color", albedo_color)


@export_subgroup("Emission", "emission_")


@export var emission_enabled: bool = false:
	set(value):
		emission_enabled = value
		refresh_shader()


@export_color_no_alpha var emission: Color = Color.BLACK:
	set(value):
		emission = value
		set_shader_parameter(&"u_emission", emission)


@export_range(0.0, 16.0, 0.01, "or_greater") var emission_energy_multiplier: float = 1.0:
	set(value):
		emission_energy_multiplier = value
		set_shader_parameter(&"u_emission_energy_multiplier", emission_energy_multiplier)


@export_enum("Add", "Multiply") var emission_operator: int = BaseMaterial3D.EmissionOperator.EMISSION_OP_ADD:
	set(value):
		emission_operator = value
		refresh_shader()


@export var emission_on_uv2: bool = false:
	set(value):
		emission_on_uv2 = value
		set_shader_parameter(&"u_emission_on_uv2", emission_on_uv2)


@export var emission_texture: Texture2D = null:
	set(value):
		emission_texture = value
		set_shader_parameter(&"u_emission_texture", emission_texture)


@export_subgroup("Billboard", "billboard_")


@export var billboard_mode: BaseMaterial3D.BillboardMode:
	set(value):
		## Currently unsure what BILLBOARD_PARTICLES does or how to implement.
		billboard_mode = value
		refresh_shader()


@export var billboard_keep_scale: bool:
	set(value):
		billboard_keep_scale = value
		refresh_shader()


func _init() -> void:
	if not Engine.is_editor_hint(): return

	shader = touch_shader(SHADER_DEFAULT_INDEX)


func refresh_shader() -> void:
	shader = touch_shader(get_shader_index())

	set_shader_parameter(&"u_alpha_scissor_threshold", alpha_scissor_threshold if transparency_mode == 1 else 0.0)
	set_shader_parameter(&"u_emission", emission)
	set_shader_parameter(&"u_emission_energy_multiplier", emission_energy_multiplier)
	set_shader_parameter(&"u_emission_operator", emission_operator)
	set_shader_parameter(&"u_emission_on_uv2", emission_on_uv2)
	set_shader_parameter(&"u_emission_texture", emission_texture)


func get_shader_index() -> int:
	var shader_indeces := [
		transparency_mode,
		cull_mode,
		depth_test,
		shading_mode,
		fog_mode,
		emission_operator + 1 if emission_enabled else 0,
		((billboard_mode * 2 - 1) + (1 if billboard_keep_scale else 0)) if billboard_mode else 0
	]
	assert(shader_indeces.size() == SHADER_FLAGS.size(), "Shader index getter must conform to the size of SHADER_FLAGS. Please update the function.")

	var result := 0
	for i in shader_indeces.size():
		result += shader_indeces[i] * SHADER_FLAGS_PERMUTATION_SIZES[i]

	return result
