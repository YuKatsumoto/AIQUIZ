class_name SkyFallSea
extends MeshInstance3D

## スカイゲートの海のサングリント（shaders/sky_fx_sea_glint.gdshader）。SkyFallScenery の子（top_level）。
## 空のセットの海（ステージと同じ海のシェーダー）の海面のすぐ上に大きな板を 1 枚置き、太陽が映る所のまわりの
## なめらかな光の帯と、風の弱い所（スリック）の筋を足す。海と一緒に動く（SkyFallScenery.set_landing_point）。
## 描く順：海（-10）のあと、白波・雲の影（-8）の前（-9）。雲の影は光の帯も暗くする。

const GLINT_SHADER := preload("res://shaders/sky_fx_sea_glint.gdshader")
const SIZE := 5000.0
const LIFT := 0.25

var _mat: ShaderMaterial = null


func build(_quality: String) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	mesh = plane
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	_mat = ShaderMaterial.new()
	_mat.shader = GLINT_SHADER
	_mat.render_priority = -9
	_mat.set_shader_parameter("slick_noise", tex)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 64.0
	top_level = true


## 海面の高さ（ワールド）と、水平の中心。
func place(sea_point: Vector3) -> void:
	global_position = Vector3(sea_point.x, sea_point.y + LIFT, sea_point.z)


## 海までの深さ（m）。近い所（近い島と着地台の帯）では光の点が人形とボードに重なってまぶしいので、少し弱める。
func set_depth(depth: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("fade", lerpf(0.45, 1.0, smoothstep(120.0, 420.0, depth)))


func set_sun(direction_to_sun: Vector3, color: Color, energy: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("sun_dir", direction_to_sun.normalized())
	_mat.set_shader_parameter("sun_color", color)
	_mat.set_shader_parameter("intensity", 0.85 * energy)
