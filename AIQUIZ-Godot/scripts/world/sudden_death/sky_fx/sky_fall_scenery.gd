class_name SkyFallScenery
extends Node3D

## スカイゲートの本戦の空の演出（docs/sudden_death_v2/sky_fx.md、作り方は skygate_build_plan.md の W7・約束は 4.8 節）。
## このノードの位置＝落ちる点（2 人の真ん中）。2 人は動かさず、雲と景色を流して落ちているように見せる（FallClouds と同じ考え）。
## 1 ラウンドの落下の進み p（0＝降下が終わったところ、1＝着地台）で景色を帯で移す：
##   雲海（c、0〜0.15）→ 雲を抜ける（f、0.15〜0.25）→ 点々の雲と島々（a、0.25〜0.85）→ 近い島と着地台（e、0.85〜1）
## ROUND 5 のあとは set_overtime(true) で「点々の雲と島々」をくり返す。
## 雲は写実の体積雲（レイマーチ。2026-10-19 ユーザー指示：UE の VolumeCloud のような雲・リアリティを追求）。
## 体から出る風の筋はわずかに見えるくらい（同じ日の指示）。
##
## 部品（子）：SkyFallClouds（体積雲：雲海・ふちの塔・中の雲と影・近い雲・薄い雲）、SkyFallSea（海のサングリント）、
## SkyFallWind（速さの線・風の筋・水滴）、
## SkyFallIslands（着地台のまわりの島・白波・帆船と小舟。top_level）、SkyFallFlyers（海鳥・飛行機雲）。
## マフラーは SkyFallScarf（同じフォルダ）。
##
## 使い方（W4）：
##   var sky := SkyFallScenery.new(); parent.add_child(sky); sky.global_position = 落ちる点
##   sky.build(quality, 着地台の位置（海面）, 画面の上の向き); sky.set_camera(camera)
##   sky.configure_sea(空のセットの海)（描く順と太陽。1 回）
##   毎フレーム：sky.set_progress(p); sky.advance(落ちた m, delta); sky.set_wind(強さ)
##   海を上げ下げするなら sky.set_landing_point(着地台の位置)（深さのおすすめは SkyFallScenery.sea_depth(p)）
##   ゲートが出たら sky.gate_emerge(board)。風の筋は sky.track_body(player, parts)。

## 海までの深さ（落ちる点から、m）のおすすめ：進み 0 で SEA_FAR、1 で SEA_NEAR。延長戦は SEA_OVERTIME。
const SEA_FAR := 1150.0
const SEA_NEAR := 75.0
const SEA_CURVE := 1.35
const SEA_OVERTIME := 520.0
## 太陽（光の進む向き。HeliSuddenDeathDirector.SKY_SUN_DIRECTION と同じ）と、ステージの太陽の色・強さ。
const SUN_TRAVEL := Vector3(-0.533, -0.742, 0.407)
const SUN_COLOR := Color(1.0, 0.96, 0.9)
## 描く順（半透明どうし）：海 → 白波・航跡・雲の影 → 雲 → ほか（ボードの紙・文字・人形のまわり）
const SEA_PRIORITY := -10

var quality := ""
var progress := 0.0
var overtime := false
var wind := 1.0
var camera: Camera3D = null
var forward := Vector3.FORWARD
var landing_point := Vector3.ZERO

var clouds: SkyFallClouds = null
var sea: SkyFallSea = null
var wind_fx: SkyFallWind = null
var islands: SkyFallIslands = null
var flyers: SkyFallFlyers = null

var _bands := {"c": 1.0, "f": 0.0, "a": 0.0, "e": 0.0, "overtime": false}
var _built := false
var _advance_usec := 0


## 着地台の位置（ワールド、海面の高さ）のまわりに島を置く。forward は画面の上の向き（ゴールの側、水平）。
func build(p_quality: String, p_landing_point: Vector3, p_forward := Vector3.FORWARD) -> void:
	for child: Node in get_children():
		child.queue_free()
	quality = p_quality if not p_quality.is_empty() else GameManager.graphics_quality
	forward = p_forward
	sea = SkyFallSea.new()
	sea.name = "SkyFallSea"
	add_child(sea)
	sea.build(quality)
	sea.set_sun(-SUN_TRAVEL.normalized(), SUN_COLOR, 1.0)
	islands = SkyFallIslands.new()
	islands.name = "SkyFallIslands"
	add_child(islands)
	islands.build(quality)
	clouds = SkyFallClouds.new()
	clouds.name = "SkyFallClouds"
	add_child(clouds)
	clouds.build(quality)
	flyers = SkyFallFlyers.new()
	flyers.name = "SkyFallFlyers"
	add_child(flyers)
	flyers.build(quality)
	wind_fx = SkyFallWind.new()
	wind_fx.name = "SkyFallWind"
	add_child(wind_fx)
	wind_fx.build(quality)
	_built = true
	set_landing_point(p_landing_point)
	set_progress(0.0)
	if camera != null:
		set_camera(camera)


## ラウンドの落下の進み（0〜1）。帯の重みを決める。
func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	_bands = band_weights(progress, overtime)
	if clouds != null:
		clouds.set_bands(_bands, progress, overtime)


## ROUND 5 のあと：「点々の雲と島々」をくり返す（雲海・雲を抜ける・近い島の帯は出さない）。
func set_overtime(on: bool) -> void:
	overtime = on
	set_progress(progress)


## 落ちた分（m、正）だけ雲と粒を上へ流す。delta は演出の時計の進み（スローなら小さく）。
func advance(fall_distance: float, delta: float) -> void:
	if not _built:
		return
	var t0 := Time.get_ticks_usec()
	var sea_local := landing_point.y - global_position.y
	sea.set_depth(-sea_local)
	clouds.set_sea_level(sea_local)
	flyers.set_sea_level(sea_local)
	clouds.advance(fall_distance, delta)
	wind_fx.wind = wind
	wind_fx.advance(fall_distance, delta)
	islands.advance(delta)
	flyers.advance(delta, _bands, progress)
	_advance_usec = Time.get_ticks_usec() - t0


## 風切りの強さ 0〜1.4（ふだん 1.0、ゲートが近い間 0.5、通過の瞬間 1.4）。
func set_wind(strength: float) -> void:
	wind = clampf(strength, 0.0, 1.4)
	if wind_fx != null:
		wind_fx.wind = wind


## ボードが出た（ゲートの頭）。雲海の帯なら、雲海の穴をボードの真上に合わせて開く。
func gate_emerge(board: Node3D) -> void:
	if clouds != null:
		clouds.gate_emerge(board)


## 速さの線を出すカメラ（その子に画面の板を置く）。雲の前後の並べ替えと、島の細かさの切り替えにも使う。
func set_camera(p_camera: Camera3D) -> void:
	camera = p_camera
	if wind_fx != null:
		wind_fx.set_camera(camera)
	if islands != null:
		islands.camera = camera
	if clouds != null:
		clouds.camera = camera


# ------------------------------------------------------------------ 足したもの（約束の 4.8 節は変えていない）

## 着地台の位置（ワールド、海面の高さ）。海を上げ下げしたら毎フレーム渡す（島・薄い雲・影・海鳥が海と一緒に動く）。
func set_landing_point(point: Vector3) -> void:
	landing_point = point
	if islands != null:
		islands.place(point, forward)
	if sea != null:
		sea.place(point)


## 空のセットの海（StageEnvironment.create_ocean_surface で作ったもの）を、この演出に合わせる：
## 半透明の描く順（海を先に、白波・雲の影・雲をあとに）と、太陽の向き（ステージと同じ海の光り方・照り返し）。
## 海のシェーダー（shaders/ocean.gdshader）と画質ごとの細かさ（OceanDetail）はステージのまま変えない。
## sun_light を渡すとその太陽の向き（ステージの太陽）で光らせる。省くと空のセットの太陽（SUN_TRAVEL）。
func configure_sea(ocean: MeshInstance3D, sun_light: DirectionalLight3D = null) -> void:
	if ocean == null:
		return
	var mat := ocean.material_override as ShaderMaterial
	if mat == null:
		return
	mat.render_priority = SEA_PRIORITY
	var to_sun := sun_light.global_basis.z.normalized() if sun_light != null else -SUN_TRAVEL.normalized()
	OceanDetailScript.set_sun(mat, to_sun)
	# 照り返し（画質「標準」以上）：ステージは横から見るので細かい波の向きの広がりが大きいが、真上から見ると
	# 海じゅうに白い点が散って雪のように見える。空撮では太陽が映る所のまわりだけがきらめく（サングリント）ので、
	# 波の向きの広がりを狭め、点を小さく少なく、そのぶん明るく
	for key: String in AERIAL_GLINTS:
		if mat.get_shader_parameter(key) != null:
			mat.set_shader_parameter(key, AERIAL_GLINTS[key])


## 本戦の画の環境：ステージと同じ空・空の光・トーンマップ（ACES）・グロー・色の調整で、霧だけ空撮向けにしたもの。
## ステージの霧（StageAtmosphere、水平線のかすみ）は高い所から見下ろすと海を白く濁らせるので、
## 遠くほど少し青くなる薄い霞（1000 m で約 2 割）に替える。島と雲は自分のシェーダーでかすむ（同じ色）。
## 監督は見せ方の environment() をカメラに当てる（HeliSuddenDeathDirector._set_environment）ので、
## SkyGatePresenter.environment() でこれを返すとよい。
static func venue_environment(p_quality: String) -> Environment:
	var q := GraphicsQuality.normalize(p_quality)
	var env := Environment.new()
	StageEnvironment.configure_stage_environment(env)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.8
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	GraphicsQuality.apply_environment(env, q)
	StageAtmosphereScript.apply_environment_quality(env, q)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.74, 0.92)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = AERIAL_HAZE_DENSITY
	env.fog_light_color = AERIAL_HAZE_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.06
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_height_density = 0.0
	return env


## 太陽の光（向き・色・強さ）を雲に合わせる（ふだんは空のセットの太陽 SUN_TRAVEL のまま）。
func set_sun(light: DirectionalLight3D) -> void:
	if clouds == null or light == null:
		return
	clouds.set_sun(light.global_basis.z.normalized(), light.light_color, 2.25 * light.light_energy)
	if sea != null:
		sea.set_sun(light.global_basis.z.normalized(), light.light_color, light.light_energy)


## 手足と頭から風の筋を出す（build_player_skeleton の parts、StagingPuppet.parts() も同じ形）。
func track_body(player: int, parts: Dictionary) -> void:
	if wind_fx != null:
		wind_fx.track(player, parts)


func untrack_body(player: int) -> void:
	if wind_fx != null:
		wind_fx.untrack(player)


## 海までの深さのおすすめ（落ちる点から、m）。帯の見え方はこの深さで作ってある。
static func sea_depth(p: float, is_overtime := false) -> float:
	if is_overtime:
		return SEA_OVERTIME
	return SEA_NEAR + (SEA_FAR - SEA_NEAR) * pow(1.0 - clampf(p, 0.0, 1.0), SEA_CURVE)


## 帯の重み（0〜1）：c＝雲海、f＝雲を抜ける、a＝点々の雲と島々、e＝近い島と着地台。
static func band_weights(p: float, is_overtime := false) -> Dictionary:
	if is_overtime:
		return {"c": 0.0, "f": 0.0, "a": 1.0, "e": 0.0, "overtime": true}
	return {
		"c": 1.0 - smoothstep(0.2, 0.27, p),
		"f": smoothstep(0.13, 0.18, p) * (1.0 - smoothstep(0.21, 0.26, p)),
		"a": smoothstep(0.17, 0.27, p) * (1.0 - smoothstep(0.83, 0.92, p)),
		"e": smoothstep(0.82, 0.92, p),
		"overtime": false,
	}


## いまの帯の名前（いちばん重い帯）。
func band_name() -> String:
	if overtime:
		return "A"
	var best := "C"
	var w := -1.0
	for key: String in ["c", "f", "a", "e"]:
		if float(_bands[key]) > w:
			w = float(_bands[key])
			best = key.to_upper()
	return best


## 描く回数の目安・粒の数・advance の時間（README の表に使う）。
func stats() -> Dictionary:
	if not _built:
		return {}
	var c := clouds.stats()
	var w := wind_fx.stats()
	var i := islands.stats()
	var f := flyers.stats()
	return {
		"draws_estimate": int(c.draws) + int(w.draws) + int(i.draws) + int(f.draws) + (1 if sea != null and sea.visible else 0),
		"clouds": c, "wind": w, "islands": i, "flyers": f,
		"advance_ms": snappedf(_advance_usec / 1000.0, 0.001),
		"progress": snappedf(progress, 0.001), "band": band_name(), "wind_strength": wind,
	}


const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
const StageAtmosphereScript = preload("res://scripts/world/stage_atmosphere.gd")
## 空撮の照り返し（海のシェーダーの glint_*。画質「標準」以上で glint_strength が 0 でないときだけ効く）
## なめらかな光の帯は SkyFallSea が足すので、ここでは帯の中で瞬く少しの点だけにする
const AERIAL_GLINTS := {"glint_spread": 0.12, "glint_density": 0.05, "glint_max_chance": 0.05, "glint_cell_pixels": 2.0}
## 空撮の霞（1/m）と色。exp(-0.00022 × 1000) で 1000 m 先が約 2 割かすむ
const AERIAL_HAZE_DENSITY := 0.00022
const AERIAL_HAZE_COLOR := Color(0.70, 0.82, 0.97)
