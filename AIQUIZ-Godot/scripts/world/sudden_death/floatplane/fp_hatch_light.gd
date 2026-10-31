extends Node3D

## 後ろの扉（スロープと上のふた）から差し込む昼の光（docs/sudden_death_v2/c130_float.md 第10章）。水上機の子に置く（座標は機体のローカル）。
## 光は機体の後ろの少し上から前へ下りる向き（light_dir）。開いた所の形は、スロープの先と上のふたの下の縁から、光の向きで
## 付け根の面（z ＝ HINGE_Z）に落とした四角（aperture）。開くほど広がり、閉じると細くなって消える。
##   光の筋（fp_light_shaft.gdshader）：機内の空気が光の中だけ明るい。画質「標準」10 歩・「高」18 歩、「低」はなし
##   ほこり（fp_cabin_dust.gdshader）：光の中の粒だけ光る。「低」はなし
##   床の明るい四角（Decal の光）：床と、そこに立つ人の足もとを照らす。「低」でも出す
##   照り返し（SpotLight3D、開口の内側から前へ）：座った人や手すりを照らす。影は「高」だけ
##   白とび（fp_hatch_glare.gdshader）：暗い機内に慣れた目には外が白く光る。開いてから目が慣れるまで（exposure）
## 露出（exposure）：開いた瞬間は外が白とびし、1 秒ほどで目が慣れて機内が暗く見える。呼ぶ側が camera_exposure() をカメラに当てる。

const SHAFT_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_light_shaft.gdshader")
const GLARE_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_hatch_glare.gdshader")
const DUST_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_cabin_dust.gdshader")
const QualityRules := preload("res://scripts/core/graphics_quality.gd")

const HINGE_Z := 4.6
const FLOOR := 1.9
const OPEN_TOP := 5.2
const HALF_W := 1.5
## 上のふたの付け根と、閉じたときの前の下の縁（floatplane_c130_layout.json の upper_door）
const DOOR_PIVOT := Vector2(11.25, 5.0083)     # (z, y)
const DOOR_EDGE_CLOSED := Vector2(7.6, 3.2)
## 光の向き：後ろから前へ、下りる角度（度）と横の傾き
const ELEVATION := 17.0
const LATERAL := 0.14
## 床の明るい四角の奥の端の明るさ（開口の側を 1）と、絵のどちらの端が開口の側か
const PATCH_FAR := 0.35
const PATCH_BRIGHT_AT_TOP := false

var plane: SuddenDeathFloatplane = null
var quality := "balanced"
## 外の明るさ（場面ごと）と色
var daylight := 1.0
var light_color := Color(1.0, 0.95, 0.86)
## 開いている割合（0〜1）と、付け根の面の明るい四角の高さ
var aperture := 0.0
var y_low := 9.0
var y_high := -9.0
## 目の慣れ（0＝暗い機内に慣れている、1＝外の明るさに慣れた）
var adapt := 0.0
## 白とびの強さ（場面ごと。開口から見えるのが明るい空なら 1、壁なら小さく）
var glare := 1.0

var _dir := Vector3.ZERO
var _shaft: MeshInstance3D = null
var _shaft_mat: ShaderMaterial = null
var _dust: GPUParticles3D = null
var _dust_mat: ShaderMaterial = null
var _decal: Decal = null
var _spot: SpotLight3D = null
var _glare: MeshInstance3D = null
var _glare_mat: ShaderMaterial = null
var _time := 0.0


func setup(owner_plane: SuddenDeathFloatplane, quality_value: String) -> void:
	plane = owner_plane
	name = "HatchLight"
	var e := deg_to_rad(ELEVATION)
	_dir = Vector3(LATERAL, -sin(e), -cos(e)).normalized()
	_build()
	apply_quality(quality_value)
	_apply()


func apply_quality(quality_value: String) -> void:
	quality = QualityRules.normalize(quality_value)
	var low := quality == QualityRules.LOW
	var high := QualityRules.is_at_least(quality, QualityRules.HIGH)
	# モバイル：光の筋は「標準」の歩数、ほこりは「標準」より少なく、照り返しは影なし（深度の読み直しと影の描き直しを減らす）。
	var mobile := QualityRules.is_mobile_target()
	if _shaft != null:
		_shaft.visible = not low
		_shaft_mat.set_shader_parameter("steps", 18 if high and not mobile else 10)
	if _dust != null:
		_dust.visible = not low
		_dust.amount = (220 if high else 120) if not mobile else (90 if high else 70)
		QualityRules.mark_particles_scaled(_dust)
	if _spot != null:
		_spot.shadow_enabled = high and not mobile


## 場面の外の明るさ（1 ＝ 晴れた空の上）と光の色、光の筋の濃さ（空気のほこり。0 で筋なし）。
func set_daylight(value: float, color := Color(1.0, 0.95, 0.86), haze := 0.05) -> void:
	daylight = value
	light_color = color
	if _shaft_mat != null:
		_shaft_mat.set_shader_parameter("haze", haze)
		_shaft.visible = haze > 0.0 and quality != QualityRules.LOW


## 毎フレーム：スロープと上のふたの開き具合から光を決める。
func update(delta: float) -> void:
	_time += delta
	if plane == null:
		return
	# スロープの先（機体のローカル）
	var edge := plane.global_transform.affine_inverse() * plane.ramp_edge_now()
	var tan_e := -_dir.y / maxf(-_dir.z, 0.05)
	var low := edge.y - (edge.z - HINGE_Z) * tan_e
	# 上のふたの前の下の縁
	var info: Dictionary = plane.layout.get("upper_door", {})
	var angle := deg_to_rad(float(info.get("open_deg", 28.159)) * plane.upper_door_t)
	var rel := DOOR_EDGE_CLOSED - DOOR_PIVOT
	# Basis(RIGHT, a) を (z, y) の面で回す：y' = y cos − z sin、z' = y sin + z cos
	var dz := rel.y * sin(angle) + rel.x * cos(angle)
	var dy := rel.y * cos(angle) - rel.x * sin(angle)
	var door := DOOR_PIVOT + Vector2(dz, dy)
	var high := door.y - (door.x - HINGE_Z) * tan_e
	y_low = maxf(low, FLOOR - 1.0)
	y_high = minf(high, OPEN_TOP)
	aperture = clampf((y_high - maxf(y_low, FLOOR)) / (OPEN_TOP - FLOOR), 0.0, 1.0)
	# 目の慣れ：開いていると外に慣れていき（約 1.2 秒）、閉じると暗さに戻る（ゆっくり）
	var want := smoothstep(0.05, 0.6, aperture)
	adapt = move_toward(adapt, want, delta * (0.85 if want > adapt else 0.35))
	_apply()


## カメラの露出の倍率（機内のカメラに当てる）：開いた瞬間はそのまま（外が白とび）、慣れると機内が暗く見えるまで下げる。
func camera_exposure() -> float:
	return lerpf(1.0, 0.72, adapt * smoothstep(0.02, 0.3, aperture))


func _apply() -> void:
	var strength := aperture * daylight
	var to_plane := Transform3D.IDENTITY
	if is_inside_tree():
		to_plane = plane.global_transform.affine_inverse()
	for mat: ShaderMaterial in [_shaft_mat, _dust_mat]:
		if mat == null:
			continue
		mat.set_shader_parameter("world_to_plane", to_plane)
		mat.set_shader_parameter("light_dir", _dir)
		mat.set_shader_parameter("y_low", y_low)
		mat.set_shader_parameter("y_high", y_high)
		mat.set_shader_parameter("light_color", Color(light_color.r, light_color.g, light_color.b))
	if _shaft_mat != null:
		_shaft_mat.set_shader_parameter("intensity", strength * 1.6)
		_shaft_mat.set_shader_parameter("time", _time)
	if _dust_mat != null:
		_dust_mat.set_shader_parameter("intensity", (0.25 + strength * 2.2) * smoothstep(0.0, 0.15, aperture + 0.02))
	if _dust != null:
		_dust.emitting = aperture > 0.01
	# 床の明るい四角：付け根の面の四角を、光の向きで床へ落とした範囲
	if _decal != null:
		var tan_e := -_dir.y / maxf(-_dir.z, 0.05)
		var near := HINGE_Z - (maxf(y_low, FLOOR) - FLOOR) / tan_e
		var far := HINGE_Z - (maxf(y_high, FLOOR) - FLOOR) / tan_e
		var length := maxf(near - far, 0.0)
		var center_z := (near + far) * 0.5
		var shift := _dir.x / maxf(-_dir.z, 0.05) * (HINGE_Z - center_z)
		_decal.visible = strength > 0.01 and length > 0.05
		_decal.size = Vector3(HALF_W * 2.0 + 0.15, 1.4, maxf(length, 0.05) + 0.25)
		_decal.position = Vector3(shift, FLOOR + 0.1, center_z)
		_decal.emission_energy = 1.05 * strength
		_decal.albedo_mix = 0.0
	if _spot != null:
		_spot.visible = strength > 0.01
		_spot.light_energy = 2.4 * strength
		_spot.light_color = light_color
	if _glare_mat != null:
		var white := strength * glare * (1.0 - adapt * 0.8)
		_glare_mat.set_shader_parameter("intensity", 1.6 * white)
		_glare.visible = white > 0.01
		var top := minf(y_high + (7.9 - HINGE_Z) * (-_dir.y / maxf(-_dir.z, 0.05)), OPEN_TOP + 0.2)
		var bottom := maxf(FLOOR - 0.3, 1.4)
		_glare.scale = Vector3(2.5, maxf(top - bottom, 0.05), 1.0)
		_glare.position = Vector3(0.0, (top + bottom) * 0.5, 8.05)


func _build() -> void:
	# 光の筋：貨物室を覆う箱（中から見ても描くよう裏の面を描く）
	_shaft = MeshInstance3D.new()
	_shaft.name = "LightShafts"
	var box := BoxMesh.new()
	var bmin := Vector3(-2.0, FLOOR, -3.5)
	var bmax := Vector3(2.0, 5.65, 4.95)
	box.size = bmax - bmin
	_shaft.mesh = box
	_shaft.position = (bmin + bmax) * 0.5
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	_shaft_mat.render_priority = 4
	_shaft_mat.set_shader_parameter("box_min", bmin)
	_shaft_mat.set_shader_parameter("box_max", bmax)
	_shaft_mat.set_shader_parameter("hinge_z", HINGE_Z)
	_shaft_mat.set_shader_parameter("half_w", HALF_W)
	_shaft_mat.set_shader_parameter("floor_y", FLOOR)
	_shaft_mat.set_shader_parameter("haze", 0.07)
	_shaft.material_override = _shaft_mat
	add_child(_shaft)
	# ほこり
	_dust = GPUParticles3D.new()
	_dust.name = "CabinDust"
	_dust.amount = 120
	_dust.lifetime = 7.0
	_dust.preprocess = 6.0
	_dust.local_coords = true
	_dust.visibility_aabb = AABB(Vector3(-2.2, -0.2, -4.5), Vector3(4.4, 4.2, 10.0))
	_dust.position = Vector3(0.0, FLOOR, 0.6)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.9, 1.8, 4.0)
	pm.direction = Vector3(0.0, 0.2, -1.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0.0, -0.01, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 1.6
	pm.scale_min = 0.012
	pm.scale_max = 0.03
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = DUST_SHADER
	_dust_mat.set_shader_parameter("hinge_z", HINGE_Z)
	_dust_mat.set_shader_parameter("half_w", HALF_W)
	quad.material = _dust_mat
	_dust.draw_pass_1 = quad
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	# 床の明るい四角（光る貼り絵）
	_decal = Decal.new()
	_decal.name = "FloorPatch"
	_decal.texture_emission = _patch_texture()
	_decal.modulate = Color(1.0, 0.96, 0.88)
	_decal.upper_fade = 0.6
	_decal.lower_fade = 0.3
	_decal.normal_fade = 0.4
	_decal.cull_mask = 0xFFFFF
	add_child(_decal)
	# 照り返し：開口の内側から前の下へ
	_spot = SpotLight3D.new()
	_spot.name = "HatchFill"
	_spot.spot_range = 10.0
	_spot.spot_angle = 48.0
	_spot.spot_angle_attenuation = 1.6
	_spot.spot_attenuation = 0.9
	_spot.light_specular = 0.4
	_spot.shadow_bias = 0.05
	add_child(_spot)
	_spot.transform = Transform3D(Basis.looking_at(_dir, Vector3.UP), Vector3(0.0, 4.4, HINGE_Z + 0.6))
	# 白とび：開口の奥（スロープの先の少し後ろ）の板
	_glare = MeshInstance3D.new()
	_glare.name = "HatchGlare"
	var gq := QuadMesh.new()
	gq.size = Vector2(1.0, 1.0)
	_glare.mesh = gq
	_glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glare_mat = ShaderMaterial.new()
	_glare_mat.shader = GLARE_SHADER
	_glare_mat.render_priority = 3
	_glare.material_override = _glare_mat
	add_child(_glare)


## 床の四角の絵（ふちが柔らかい白）。
static func _patch_texture() -> Texture2D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			# 開口に近い端ほど明るく、奥（機首の側）へ弱まる（空気に散らされて届く光が減る）
			var reach := lerpf(1.0, PATCH_FAR, (v + 1.0) * 0.5) if PATCH_BRIGHT_AT_TOP else lerpf(PATCH_FAR, 1.0, (v + 1.0) * 0.5)
			var a := (1.0 - smoothstep(0.7, 1.0, absf(u))) * (1.0 - smoothstep(0.75, 1.0, absf(v))) * reach
			image.set_pixel(x, y, Color(a, a, a, a))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
