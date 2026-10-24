class_name SuddenDeathFloatplane
extends Node3D

## サドンデス「つきやぶれ！スカイゲート」の水上機 C-130（docs/sudden_death_v2/skygate_build_plan.md 4.2、c130_float.md）。
## 素材は assets/vehicles/floatplane_c130/（floatplane_c130.glb と floatplane_c130_layout.json）。作り方はそこの README.md。
##
## 座標（GLB とこのノードのローカル）：原点は海面 × 機体の中心線 × 主翼の翼弦の中央（機首から 6.6 m）。+Y が上、機首が −Z。
## 浮いているときは position.y を海面の高さにする。
##
## 使い方：
##   var plane := SuddenDeathFloatplane.new()
##   add_child(plane)
##   plane.build(quality)              # 読み込み・材質の作り替え・画質（with_pilot = false ならハテナを載せない）
##   plane.set_ramp(t) / set_upper_door(t) / set_props(speed, reverse) / set_flaps(t) / set_jump_light("red")
##   plane.set_pontoon_spray(amount) / set_cabin_lighting("day" | "red" | "off") / set_belt(player, on)
##   plane.set_water_fx(speed, thrust, reverse, burst, drip) / clear_water_fx()   # 水しぶき（c130_float.md 第9章）
##   plane.marker("MK_RampEdge") / seat_transform(1) / pilot_transform()   # どれもワールドの Transform3D
## マーカーの向き：basis の +Z が人の向き（StagingPuppet の yaw と同じ）。MK_Cam* だけはカメラの向き（−Z が見る向き）。

const MODEL_PATH := "res://assets/vehicles/floatplane_c130/floatplane_c130.glb"
const LAYOUT_PATH := "res://assets/vehicles/floatplane_c130/floatplane_c130_layout.json"
const TEX_DIR := "res://assets/vehicles/floatplane_c130/textures/"
const SURFACE_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_surface.gdshader")
const DECAL_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_decal.gdshader")
const PROP_DISC_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_prop_disc.gdshader")
const GLASS_SHADER := preload("res://shaders/heli_glass.gdshader")
const QualityRules := preload("res://scripts/core/graphics_quality.gd")

## プロペラ：speed 1 の回転（回/秒）と、円盤に替える速さ
const PROP_MAX_RPS := 14.0
## スロープを床より下へ下げたとき（着地台に載せる）の t。開く角度 25° × 1.8 ＝ 45°（床から 20° 下）。
const RAMP_GROUND := 1.8
const PROP_BLUR_SPEED := 0.45
const PROP_RESPONSE := 1.6          # 回転が追いつく速さ（1/秒）
const PITCH_RESPONSE := 2.5         # 羽根の角度（逆推力）が変わる速さ
## 機内の灯（ダウンライト）：色・強さ・届く距離・角度
const CABIN_DAY_COLOR := Color(1.0, 0.91, 0.78)
const CABIN_RED_COLOR := Color(1.0, 0.10, 0.06)
const CABIN_DAY_ENERGY := 2.2
const CABIN_RED_ENERGY := 1.5
const CABIN_LIGHT_RANGE := 4.6
const CABIN_LIGHT_ANGLE := 62.0
const LENS_DAY_EMISSION := 5.0
const AMBER_COLOR := Color(1.0, 0.62, 0.18)
const JUMP_LIGHT_ENERGY := 1.6
const BEACON_PERIOD := 1.2
const BEACON_ON := 0.12
const DECAL_RENDER_PRIORITY := -8
## 貨物室の反射プローブ（室内）：空の青い環境光の代わりに、暗めの暖かい環境光にする（閉じた機内らしく）。
## 箱は内張りの内側だけ（外板は入れない）：x ±1.98・y 1.82〜5.58・z −3.35〜4.35（u 3.25〜10.95）
const CABIN_PROBE_SIZE := Vector3(3.96, 3.76, 7.70)
const CABIN_PROBE_CENTER := Vector3(0.0, 3.70, 0.50)
const CABIN_AMBIENT_DAY := Color(0.55, 0.50, 0.43)
const CABIN_AMBIENT_RED := Color(0.55, 0.12, 0.09)
const CABIN_AMBIENT_ENERGY := 0.42
## 材質の名前 → テクスチャと AO の扱い（色・粗さ・金属は GLB の材質から取る）
const PAINT_MATERIALS := ["FP_Paint", "FP_Navy", "FP_StripeOrange", "FP_StripeBlue"]
const EMISSIVE := {
	"FP_LightRed": 3.0, "FP_LightGreen": 3.0, "FP_LightWhite": 3.0, "FP_InteriorLamp": LENS_DAY_EMISSION,
	"FP_InteriorLampAmber": 2.5, "FP_InteriorScreen": 1.6, "FP_Spinner": 0.0, "FP_Slime": 0.25,
}
## 布の織り目を三方向から貼る材質（UV のない丸い形）：名前 → [1 m あたりの枚数, 法線の強さ]
const FABRIC_TRIPLANAR := {"FP_InteriorSeat": [5.0, 0.7], "FP_Glareshield": [7.0, 0.55]}

var layout: Dictionary = {}
var model: Node3D = null
var pilot: HatenaPilot = null
var with_pilot := true
var quality := "high"
var ramp_t := 0.0
var upper_door_t := 0.0
var flaps_t := 0.0
var prop_speed := 0.0          # 今の回転（0〜1。set_props の値へ追いつく）
var prop_target := 0.0
var prop_reverse := false
var jump_light_state := "off"
var cabin_mode := "day"
var _red_mix := 0.0            # 機内の灯の昼（0）と赤（1）のまぜ具合
var _red_target := 0.0
var _red_rate := 0.0           # 1 秒に動く量（0＝止まっている）
var spray_amount := 0.0

var _markers := {}
var _nodes := {}               # 名前 → Node3D（GLB の動く部品）
var _rest := {}                # 名前 → 元の Transform3D
var _materials := {}           # 元の材質の名前 → 作った材質
var _props: Array[Dictionary] = []
var _prop_angle := 0.0
var _reverse_mix := 0.0
var _cabin_lights: Array[Light3D] = []
var _cabin_kinds: Array[String] = []
var _lens_material: ShaderMaterial = null
var _jump_materials := {}
var _jump_omni: OmniLight3D = null
var _beacon_material: ShaderMaterial = null
var _beacon_time := 0.0
var _sprays: Array[GPUParticles3D] = []
var _belts := {}
var _probe: ReflectionProbe = null


static func load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## 読み込み・材質の作り替え・画質。何度呼んでもよい（2 回目からは画質だけ変える）。
func build(quality_value: String) -> bool:
	quality = QualityRules.normalize(quality_value)
	if model != null:
		apply_quality(quality)
		return true
	layout = load_layout()
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null or layout.is_empty():
		push_error("SuddenDeathFloatplane: %s か %s が読めない" % [MODEL_PATH, LAYOUT_PATH])
		return false
	model = packed.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_read_markers()
	_find_parts()
	_prepare_materials()
	_build_prop_discs()
	_build_cabin_lights()
	_build_cabin_probe()
	_build_sprays()
	_build_jump_light()
	for node: Node in model.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.name.begins_with("Glass") or g.name.begins_with("JumpLight") or g.name.begins_with("NavLight") or g.name in ["Beacon", "TailLight"]:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	QualityRules.drop_tiny_shadow_casters(model)
	if with_pilot:
		_mount_pilot()
	set_ramp(0.0)
	set_upper_door(0.0)
	set_flaps(0.0)
	set_jump_light("off")
	set_cabin_lighting("day")
	for player: int in [1, 2]:
		set_belt(player, false)
	apply_quality(quality)
	return true


func is_built() -> bool:
	return model != null


# ---------- 動く部品 ----------

## 0 = 閉じる（GLB のまま、上へ 25°）、1 = 床と水平（開いたまま飛んでも 1）。作動筒もいっしょに動く。
## t が 1 を超えると床より下へ下がる（RAMP_GROUND で約 20° 下。着地台の浮き輪にスロープの端を載せる。skygate_build_plan.md W6）。
func set_ramp(t: float) -> void:
	ramp_t = clampf(t, 0.0, RAMP_GROUND)
	var ramp := _nodes.get("Ramp") as Node3D
	var info: Dictionary = layout.get("ramp", {})
	if ramp == null:
		return
	var angle := deg_to_rad(float(info.get("open_deg", 25.0)) * ramp_t)
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, angle), (_rest["Ramp"] as Transform3D).origin)
	_update_actuators(angle)


## 後ろの上のふた（尾の下）：0 = 閉じる、1 = 尾の中へ上がる（下面が海面から 5.0 m）。
func set_upper_door(t: float) -> void:
	upper_door_t = clampf(t, 0.0, 1.0)
	var door := _nodes.get("UpperDoor") as Node3D
	if door == null:
		return
	var info: Dictionary = layout.get("upper_door", {})
	door.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(info.get("open_deg", 28.0)) * upper_door_t)), (_rest["UpperDoor"] as Transform3D).origin)


## プロペラ：speed 0〜1（回転。だんだん追いつく）、reverse は逆推力（後ろへ進むときの羽根の角度）。
func set_props(speed: float, reverse := false) -> void:
	prop_target = clampf(speed, 0.0, 1.0)
	prop_reverse = reverse


## 回転をすぐその値にする（カットの瞬間）。
func snap_props(speed: float, reverse := false) -> void:
	set_props(speed, reverse)
	prop_speed = prop_target
	_reverse_mix = 1.0 if reverse else 0.0
	_update_props(0.0)


## 羽根の角度が逆推力へ回っている具合（0〜1。エンジンの音 FloatplaneSound が読む）。
func reverse_mix() -> float:
	return _reverse_mix


## フラップ：0 = 上げ、1 = 下げ（30°。着水・離水）。
func set_flaps(t: float) -> void:
	flaps_t = clampf(t, 0.0, 1.0)
	for row: Variant in layout.get("flaps", []):
		var info: Dictionary = row
		var flap := _nodes.get(str(info.get("node", ""))) as Node3D
		if flap == null:
			continue
		flap.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(info.get("down_deg", 30.0)) * flaps_t)), (_rest[flap.name] as Transform3D).origin)


## 降下のランプ："off"・"red"・"green"。光ったほうの色で開口のまわりを少し照らす。
func set_jump_light(state: String) -> void:
	jump_light_state = state if state in ["off", "red", "green"] else "off"
	for key: String in ["red", "green"]:
		var mat := _jump_materials.get(key) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("emission_energy", 7.0 if jump_light_state == key else 0.06)
	if _jump_omni != null:
		_jump_omni.visible = jump_light_state != "off"
		_jump_omni.light_color = Color(1.0, 0.12, 0.08) if jump_light_state == "red" else Color(0.15, 1.0, 0.35)


## フロートのしぶき（簡単な形）：0〜1。0 ですべて止める。細かく決めるときは set_water_fx。
func set_pontoon_spray(amount: float) -> void:
	spray_amount = clampf(amount, 0.0, 1.0)
	set_water_fx(spray_amount * 26.0, 0.0, false, 0.0, 0.0)


## 水しぶき（c130_float.md 第9章）。speed は水の上を進む速さ（m/秒、空中は 0）、thrust はプロペラの押す強さ（0〜1）、
## reverse は逆推力（プロペラの風が前へ）、burst は着水の打ちつけ（0〜1、すぐ減らす）、drip は浮いたあとのしずく（0〜1）。
##   船首：遅いとき（排水の速さ〜こぶの速さ）の押しのけ波のしぶき
##   段：段に乗って速いときの、横へ広がるしぶきの膜
##   船尾：速いときの、うしろへ噴き上がる水柱
##   プロペラの下：強い推力で水面から舞う霧（逆推力では前へ）
##   しずく：浮いたあと浮き舟から落ちる水
func set_water_fx(speed: float, thrust: float, reverse: bool, burst: float, drip := 0.0) -> void:
	var v := absf(speed)
	var hump := smoothstep(1.5, 6.0, v) * (1.0 - smoothstep(12.0, 19.0, v))
	# 後ろ向きに進むときは、押しのけ波は浮き舟のうしろの端（進む側）に立つ
	var backward := speed < 0.0
	var plane_on := smoothstep(9.0, 18.0, v)
	var fast := smoothstep(14.0, 26.0, v)
	var low := quality == QualityRules.LOW
	for spray: GPUParticles3D in _sprays:
		var kind := String(spray.get_meta("kind", ""))
		var side := float(spray.get_meta("side", 1.0))
		var pm := spray.process_material as ParticleProcessMaterial
		var level := 0.0
		match kind:
			"bow":
				level = (hump * 0.25 if backward else hump * 0.9) + burst * 0.5
				pm.initial_velocity_min = 1.5 + v * 0.2
				pm.initial_velocity_max = 3.5 + v * 0.35 + burst * 5.0
				pm.direction = Vector3(side * 0.9, 0.85, -0.25 if speed >= 0.0 else 0.25)
			"step":
				level = plane_on * 0.9 + burst
				pm.initial_velocity_min = 2.5 + v * 0.16 + burst * 4.0
				pm.initial_velocity_max = 5.0 + v * 0.3 + burst * 7.5
				pm.direction = Vector3(side, 0.7 + burst * 0.5, 0.5)
			"stern":
				level = fast * 0.8 + burst
				pm.initial_velocity_min = 3.0 + v * 0.12 + burst * 3.0
				pm.initial_velocity_max = 6.0 + v * 0.24 + burst * 7.0
				pm.direction = Vector3(side * 0.25, 1.0, 0.9)
				if backward:
					level = hump * 0.85
					pm.initial_velocity_min = 1.5 + v * 0.2
					pm.initial_velocity_max = 3.5 + v * 0.35
					pm.direction = Vector3(side * 0.9, 0.85, 0.25)
			"prop":
				# 呼ぶ側は、水の上（か水面のすぐ上）にいるときだけ thrust を渡す
				level = clampf(thrust, 0.0, 1.0) * (0.35 + 0.65 * smoothstep(0.55, 1.0, thrust))
				pm.direction = Vector3(0.0, 0.35, -1.0 if reverse else 1.0)
				pm.initial_velocity_min = 3.0 + thrust * 2.0
				pm.initial_velocity_max = 6.0 + thrust * 5.0
			"drip":
				level = clampf(drip, 0.0, 1.0)
		if low and kind in ["prop", "drip"]:
			level = 0.0
		spray.emitting = level > 0.02
		spray.amount_ratio = clampf(level, 0.0, 1.0)


## 時間を飛ばすカットのあと：前の場所に残ったしぶきを消す。
func clear_water_fx() -> void:
	for spray: GPUParticles3D in _sprays:
		spray.emitting = false
		spray.restart()
		spray.emitting = false


## 機内の灯："day"（暖かい白）・"red"（降下の前の赤い照明）・"off"。fade 秒かけて昼と赤のあいだを移す（0 ならすぐ。
## 雲の中の入れ替えの直後に赤へ変えても、機内の色がパッと変わらない）。
func set_cabin_lighting(mode: String, fade := 0.0) -> void:
	var was := cabin_mode
	cabin_mode = mode if mode in ["day", "red", "off"] else "day"
	_red_target = 1.0 if cabin_mode == "red" else 0.0
	if fade > 0.0 and was != "off" and cabin_mode != "off":
		_red_rate = 1.0 / fade
	else:
		_red_mix = _red_target
		_red_rate = 0.0
	_refresh_cabin_lights()


## 座った 2 人の腰のベルト（P1 は機体の右の壁）。
func set_belt(player: int, on: bool) -> void:
	var belt := _belts.get(player) as Node3D
	if belt != null:
		belt.visible = on


# ---------- 目印 ----------

## ワールドのマーカー（layout の markers）。ないときは原点。
func marker(marker_name: String) -> Transform3D:
	return global_transform * marker_local(marker_name)


## このノードのローカルのマーカー。
func marker_local(marker_name: String) -> Transform3D:
	return _markers.get(marker_name, Transform3D.IDENTITY)


func has_marker(marker_name: String) -> bool:
	return _markers.has(marker_name)


## ベンチに座る位置（pelvis）と向き（通路の向かい）。P1 は機体の右の壁（+X）、P2 は左の壁。
func seat_transform(player: int) -> Transform3D:
	return marker("MK_SeatP1" if player == 1 else "MK_SeatP2")


## ハテナ（HatenaPilot）の座る位置（原点＝足元の基準、等倍）。
func pilot_transform() -> Transform3D:
	var info: Dictionary = layout.get("hatena", {})
	var t := marker("MK_PilotSeat")
	return Transform3D(t.basis.scaled(Vector3.ONE * float(info.get("scale", 1.0))), t.origin)


## 開いたスロープの端の上面（飛び出す位置）。set_ramp の今の角度での端（閉じかけでも正しい）。
func ramp_edge_now() -> Vector3:
	var info: Dictionary = layout.get("ramp", {})
	var pivot := _vec(info.get("pivot", [0, 0, 0]))
	var edge := marker_local("MK_RampEdge").origin
	var closed_angle := deg_to_rad(float(info.get("open_deg", 25.0)))
	# マーカーは開いた位置。閉じた位置へ戻してから今の角度で開く
	var rel := Basis(Vector3.RIGHT, -closed_angle) * (edge - pivot)
	return global_transform * (pivot + Basis(Vector3.RIGHT, deg_to_rad(float(info.get("open_deg", 25.0)) * ramp_t)) * rel)


# ---------- 画質 ----------

func apply_quality(value: String) -> void:
	quality = QualityRules.normalize(value)
	_refresh_cabin_lights()
	for spray: GPUParticles3D in _sprays:
		spray.amount = maxi(8, QualityRules.particle_amount(int(spray.get_meta("base_amount", 48)), quality))
	var aniso := QualityRules.uses_anisotropic_material_filter(quality)
	for mat: Variant in _materials.values():
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("triplanar_sharpness", 4.0 if aniso else 3.0)


## 機内の灯の表示・色・強さ・影を、照明（cabin_mode）と画質からまとめて決める。
## 低：ダウンライトは 3 つに 1 つ（そのぶん強く）。影は高から、座席の上の 4 つだけ。
func _refresh_cabin_lights() -> void:
	var low := quality == QualityRules.LOW
	var high := QualityRules.is_at_least(quality, QualityRules.HIGH)
	for i: int in range(_cabin_lights.size()):
		var light := _cabin_lights[i]
		var kind := _cabin_kinds[i]
		var keep := not low or kind != "downlight" or int(light.get_meta("index", 0)) % 3 == 1
		light.visible = keep and cabin_mode != "off"
		light.shadow_enabled = high and bool(light.get_meta("shadow_slot", false))
	_apply_cabin_mix()


## 昼と赤のまぜ具合（_red_mix）を灯・室内の環境光・灯のレンズへ当てる。
func _apply_cabin_mix() -> void:
	var low := quality == QualityRules.LOW
	var color := CABIN_DAY_COLOR.lerp(CABIN_RED_COLOR, _red_mix)
	var base := lerpf(CABIN_DAY_ENERGY, CABIN_RED_ENERGY, _red_mix)
	for i: int in range(_cabin_lights.size()):
		var kind := _cabin_kinds[i]
		if kind == "amber":
			continue
		var light := _cabin_lights[i]
		light.light_color = color
		var energy := base
		if kind == "cockpit":
			energy *= 0.45
		elif low:
			energy *= 1.8
		light.light_energy = energy
	if _probe != null:
		_probe.ambient_color = CABIN_AMBIENT_DAY.lerp(CABIN_AMBIENT_RED, _red_mix)
		_probe.ambient_color_energy = CABIN_AMBIENT_ENERGY * (0.35 if cabin_mode == "off" else 1.0)
	if _lens_material != null:
		_lens_material.set_shader_parameter("emission_color", Color(1.0, 0.93, 0.82).lerp(CABIN_RED_COLOR, _red_mix))
		_lens_material.set_shader_parameter("emission_energy", 0.0 if cabin_mode == "off" else LENS_DAY_EMISSION)


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	if model == null:
		return
	prop_speed = move_toward(prop_speed, prop_target, PROP_RESPONSE * delta * maxf(0.25, absf(prop_target - prop_speed)))
	_reverse_mix = move_toward(_reverse_mix, 1.0 if prop_reverse else 0.0, PITCH_RESPONSE * delta)
	_update_props(delta)
	if _red_rate > 0.0:
		_red_mix = move_toward(_red_mix, _red_target, _red_rate * delta)
		if is_equal_approx(_red_mix, _red_target):
			_red_rate = 0.0
		_apply_cabin_mix()
	_beacon_time += delta
	if _beacon_material != null:
		var on := fmod(_beacon_time, BEACON_PERIOD) < BEACON_ON and prop_speed > 0.05
		_beacon_material.set_shader_parameter("emission_energy", 8.0 if on else 0.15)


func _update_props(delta: float) -> void:
	_prop_angle = wrapf(_prop_angle + prop_speed * PROP_MAX_RPS * TAU * delta, 0.0, TAU)
	var blur := prop_speed > PROP_BLUR_SPEED and quality != QualityRules.LOW
	for p: Dictionary in _props:
		var hub := p.node as Node3D
		hub.transform = Transform3D(Basis(Vector3(0, 0, 1), _prop_angle * float(p.dir)), (p.rest as Transform3D).origin)
		for b: Dictionary in p.blades:
			var blade := b.node as Node3D
			blade.transform = Transform3D(Basis(b.radial as Vector3, deg_to_rad(float(p.reverse_delta)) * _reverse_mix), Vector3.ZERO)
			blade.visible = not blur
		var disc := p.disc as MeshInstance3D
		if disc != null:
			disc.visible = blur
			var mat := disc.material_override as ShaderMaterial
			mat.set_shader_parameter("strength", clampf((prop_speed - PROP_BLUR_SPEED) / 0.25, 0.0, 1.0))
			mat.set_shader_parameter("spin", _prop_angle * 0.37)


func _update_actuators(angle: float) -> void:
	var info: Dictionary = layout.get("ramp", {})
	var pivot := _vec(info.get("pivot", [0, 0, 0]))
	for tag: String in ["L", "R"]:
		var a_info: Dictionary = layout.get("ramp_actuators", {}).get(tag, {})
		var cyl := _nodes.get(str(a_info.get("cylinder", ""))) as Node3D
		var rod := _nodes.get(str(a_info.get("rod", ""))) as Node3D
		if cyl == null or rod == null:
			continue
		var a := _vec(a_info.get("anchor", [0, 0, 0]))
		var b := pivot + Basis(Vector3.RIGHT, angle) * (_vec(a_info.get("ramp_point_closed", [0, 0, 0])) - pivot)
		cyl.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), a)
		rod.transform = Transform3D(Basis.looking_at(a - b, Vector3.UP), b)


# ---------- 組み立て ----------

func _read_markers() -> void:
	for marker_name: String in layout.get("markers", {}):
		var info: Dictionary = layout.markers[marker_name]
		var basis := Basis.IDENTITY
		var cols: Array = info.get("basis", [])
		if cols.size() == 3:
			basis = Basis(_vec(cols[0]), _vec(cols[1]), _vec(cols[2]))
		_markers[marker_name] = Transform3D(basis, _vec(info.get("position", [0, 0, 0])))


func _find_parts() -> void:
	var names: Array[String] = ["Ramp", "UpperDoor", "Body", "Interior", "Cockpit", "Floats", "Glass", "Belt_P1", "Belt_P2"]
	for row: Variant in layout.get("flaps", []):
		names.append(str((row as Dictionary).get("node", "")))
	for tag: String in ["L", "R"]:
		var a_info: Dictionary = layout.get("ramp_actuators", {}).get(tag, {})
		names.append(str(a_info.get("cylinder", "")))
		names.append(str(a_info.get("rod", "")))
	for n: String in names:
		var node := model.find_child(n, true, false) as Node3D
		if node == null:
			continue
		_nodes[n] = node
		_rest[n] = node.transform
	_belts[1] = _nodes.get("Belt_P1")
	_belts[2] = _nodes.get("Belt_P2")
	for i: int in range((layout.get("props", []) as Array).size()):
		var info: Dictionary = layout.props[i]
		var hub := model.find_child(str(info.get("node", "")), true, false) as Node3D
		if hub == null:
			continue
		var blades: Array[Dictionary] = []
		for b_info: Variant in info.get("blades", []):
			var bd: Dictionary = b_info
			var blade := hub.find_child(str(bd.get("node", "")), true, false) as Node3D
			if blade != null:
				blades.append({"node": blade, "radial": _vec(bd.get("radial", [0, 1, 0])).normalized()})
		_props.append({"node": hub, "rest": hub.transform, "blades": blades, "dir": 1.0,
			"reverse_delta": float(info.get("reverse_pitch_delta_deg", -42.0)), "disc": null})


func _texture(file: String) -> Texture2D:
	var path := TEX_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 元の材質（GLB）から、名前に合わせた材質を作る。
func _make_material(source: Material, node_name: String) -> Material:
	var src_name := source.resource_name
	var base := source as BaseMaterial3D
	var color := base.albedo_color if base != null else Color.WHITE
	var rough := base.roughness if base != null else 0.6
	var metal := base.metallic if base != null else 0.0
	if src_name == "FP_Glass":
		var glass := ShaderMaterial.new()
		glass.shader = GLASS_SHADER
		glass.set_shader_parameter("visor_strength", 0.0)
		glass.set_shader_parameter("tint", Color(0.62, 0.80, 0.92, 0.18))
		return glass
	if src_name == "FP_Decal" or src_name == "FP_InteriorDecal":
		var decal := ShaderMaterial.new()
		decal.shader = DECAL_SHADER
		decal.set_shader_parameter("atlas", _texture("fp_decals.png"))
		decal.set_shader_parameter("roughness", 0.45 if src_name == "FP_Decal" else 0.8)
		decal.set_shader_parameter("ao_strength", 0.6 if src_name == "FP_Decal" else 1.0)
		decal.render_priority = DECAL_RENDER_PRIORITY
		return decal
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	var interior := src_name.begins_with("FP_Interior") or src_name.begins_with("FP_Seat") or src_name.begins_with("FP_Hazard")
	m.set_shader_parameter("ao_strength", 1.0 if interior else 0.75)
	m.set_shader_parameter("ao_light_affect", 0.18 if interior else 0.08)
	m.set_shader_parameter("albedo_ao", 0.25 if interior else 0.10)
	if src_name in PAINT_MATERIALS:
		m.set_shader_parameter("triplanar", true)
		m.set_shader_parameter("triplanar_scale", 0.5)
		m.set_shader_parameter("normal_texture", _texture("fp_paint_normal.png"))
		m.set_shader_parameter("normal_scale", 0.9)
		m.set_shader_parameter("roughness_texture", _texture("fp_paint_rough.png"))
		m.set_shader_parameter("roughness_texture_mix", 0.6)
		m.set_shader_parameter("clearcoat", 0.30)
		m.set_shader_parameter("clearcoat_roughness", 0.22)
		# 2026-10-22：パネルごとの色むら・継ぎ目のくすみ（三方向から貼る倍率）と、外板の汚れ（むら・排気口の焼け・フロートの水線）
		m.set_shader_parameter("albedo_texture", _texture("fp_paint_albedo.png"))
		m.set_shader_parameter("albedo_texture_mix", 1.0)
		m.set_shader_parameter("exterior_grime", true)
		m.set_shader_parameter("waterline_stain", 1.0)
		var soot: Array[Vector4] = []
		for row: Variant in layout.get("exhausts", []):
			var e := _vec(row)
			soot.append(Vector4(e.x, e.y, e.z, 0.9))
		while soot.size() < 4:
			soot.append(Vector4(0, -100, 0, 0))
		m.set_shader_parameter("soot_src", soot)
	match src_name:
		"FP_InteriorBlanket":
			m.set_shader_parameter("albedo", Color.WHITE)
			m.set_shader_parameter("albedo_texture", _texture("fp_quilt_albedo.png"))
			m.set_shader_parameter("albedo_texture_mix", 1.0)
			m.set_shader_parameter("normal_texture", _texture("fp_quilt_normal.png"))
			m.set_shader_parameter("normal_scale", 1.6)
			m.set_shader_parameter("specular", 0.22)
		"FP_InteriorFloor":
			m.set_shader_parameter("albedo", Color.WHITE)
			m.set_shader_parameter("albedo_texture", _texture("fp_floor_albedo.png"))
			m.set_shader_parameter("albedo_texture_mix", 1.0)
			m.set_shader_parameter("normal_texture", _texture("fp_floor_normal.png"))
			m.set_shader_parameter("normal_scale", 1.0)
			m.set_shader_parameter("roughness_texture", _texture("fp_floor_rough.png"))
			m.set_shader_parameter("roughness_texture_mix", 1.0)
			m.set_shader_parameter("metallic", 0.30)
		"FP_InteriorTread":
			m.set_shader_parameter("normal_texture", _texture("fp_tread_normal.png"))
			m.set_shader_parameter("normal_scale", 1.2)
		"FP_SeatFabric":
			m.set_shader_parameter("normal_texture", _texture("fp_fabric_normal.png"))
			m.set_shader_parameter("normal_scale", 0.8)
			m.set_shader_parameter("specular", 0.3)
		"FP_SeatWebbing", "FP_InteriorBelt":
			m.set_shader_parameter("normal_texture", _texture("fp_webbing_normal.png"))
			m.set_shader_parameter("normal_scale", 0.9)
			m.set_shader_parameter("specular", 0.3)
		"FP_InteriorPanel":
			# 計器の盤面（4 つの画面・灯・表示）。アルファの所（画面・灯）だけ光る（2026-10-22）
			m.set_shader_parameter("albedo", Color.WHITE)
			m.set_shader_parameter("albedo_texture", _texture("fp_panel.png"))
			m.set_shader_parameter("albedo_texture_mix", 1.0)
			m.set_shader_parameter("emission_from_albedo", 1.15)
			m.set_shader_parameter("emission_mask_alpha", 1.0)
			m.set_shader_parameter("roughness", 0.5)
			m.set_shader_parameter("ao_strength", 0.6)
		"FP_Exhaust", "FP_WingEdge":
			m.set_shader_parameter("clearcoat", 0.2)
			m.set_shader_parameter("clearcoat_roughness", 0.3)
	if FABRIC_TRIPLANAR.has(src_name):
		var row: Array = FABRIC_TRIPLANAR[src_name]
		m.set_shader_parameter("triplanar", true)
		m.set_shader_parameter("triplanar_scale", float(row[0]))
		m.set_shader_parameter("normal_texture", _texture("fp_fabric_normal.png"))
		m.set_shader_parameter("normal_scale", float(row[1]))
		m.set_shader_parameter("specular", 0.3)
	if EMISSIVE.has(src_name) and float(EMISSIVE[src_name]) > 0.0:
		m.set_shader_parameter("emission_color", color)
		m.set_shader_parameter("emission_energy", float(EMISSIVE[src_name]))
		m.set_shader_parameter("ao_strength", 0.0)
	return m


func _prepare_materials() -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s)
			if source == null:
				continue
			var key := source.resource_name
			var own := mi.name.begins_with("JumpLight") or mi.name == "Beacon"
			if own:
				key = "%s@%s" % [key, mi.name]
			var prepared: Material = _materials.get(key)
			if prepared == null:
				prepared = _make_material(source, mi.name)
				_materials[key] = prepared
				if source.resource_name == "FP_InteriorLamp":
					_lens_material = prepared as ShaderMaterial
				if mi.name == "JumpLight_Red":
					_jump_materials["red"] = prepared
				elif mi.name == "JumpLight_Green":
					_jump_materials["green"] = prepared
				elif mi.name == "Beacon":
					_beacon_material = prepared as ShaderMaterial
			mi.set_surface_override_material(s, prepared)


func _build_prop_discs() -> void:
	for i: int in range(_props.size()):
		var p: Dictionary = _props[i]
		var info: Dictionary = layout.props[i]
		var disc := MeshInstance3D.new()
		disc.name = "PropDisc"
		var quad := QuadMesh.new()
		var d := float(info.get("diameter", 2.8))
		quad.size = Vector2(d, d)
		disc.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = PROP_DISC_SHADER
		mat.set_shader_parameter("hub_radius", 0.30 / (d * 0.5))
		mat.set_shader_parameter("tip_start", 1.0 - 0.18 / (d * 0.5))
		disc.material_override = mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.visible = false
		# 羽根の回る面（スピナーの原点、ローカル XY）
		(p.node as Node3D).get_parent().add_child(disc)
		disc.transform = Transform3D(Basis.IDENTITY, (p.rest as Transform3D).origin + Vector3(0, 0, -0.02))
		p.disc = disc


func _build_cabin_lights() -> void:
	var idx := 0
	var shadow_slots := 0
	for row: Variant in layout.get("cabin_lights", []):
		var info: Dictionary = row
		var kind := str(info.get("kind", "downlight"))
		var pos := _vec(info.get("position", [0, 0, 0]))
		var dir := _vec(info.get("direction", [0, -1, 0])).normalized()
		var light: Light3D
		if kind == "downlight":
			var spot := SpotLight3D.new()
			spot.spot_range = CABIN_LIGHT_RANGE
			spot.spot_angle = CABIN_LIGHT_ANGLE
			spot.spot_angle_attenuation = 0.9
			spot.spot_attenuation = 1.2
			spot.light_size = 0.12
			light = spot
			# 影は真ん中の 4 つ（座席の上）だけ（高い画質のとき）
			var z := pos.z
			light.set_meta("shadow_slot", absf(z - 0.8) < 2.6 and pos.x > 0.0 and shadow_slots < 4)
			if bool(light.get_meta("shadow_slot")):
				shadow_slots += 1
			light.set_meta("index", idx)
			idx += 1
		elif kind == "amber":
			var omni := OmniLight3D.new()
			omni.omni_range = 1.3
			omni.light_color = AMBER_COLOR
			omni.light_energy = 0.35
			light = omni
		else:
			var omni2 := OmniLight3D.new()
			omni2.omni_range = 2.6
			omni2.light_color = CABIN_DAY_COLOR
			light = omni2
		light.name = "CabinLight_%s_%d" % [kind, _cabin_lights.size()]
		light.shadow_bias = 0.04
		light.light_specular = 0.6
		add_child(light)
		var up := Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP
		light.transform = Transform3D(Basis.looking_at(dir, up), pos + dir * 0.02)
		_cabin_lights.append(light)
		_cabin_kinds.append(kind)
	# 計器の明かり（画面の色の弱い光）
	var dash := OmniLight3D.new()
	dash.name = "DashGlow"
	dash.omni_range = 1.4
	dash.light_color = Color(0.55, 0.85, 1.0)
	dash.light_energy = 0.25
	add_child(dash)
	dash.position = Vector3(0.0, 3.85, 0.95 - 6.6 - 0.15)


func _build_cabin_probe() -> void:
	_probe = ReflectionProbe.new()
	_probe.name = "CabinProbe"
	_probe.interior = true
	_probe.box_projection = true
	_probe.size = CABIN_PROBE_SIZE
	_probe.blend_distance = 0.25
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = CABIN_AMBIENT_DAY
	_probe.ambient_color_energy = CABIN_AMBIENT_ENERGY
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.enable_shadows = false
	add_child(_probe)
	_probe.position = CABIN_PROBE_CENTER


func _build_jump_light() -> void:
	_jump_omni = OmniLight3D.new()
	_jump_omni.name = "JumpLightGlow"
	_jump_omni.omni_range = 3.2
	_jump_omni.light_energy = JUMP_LIGHT_ENERGY
	_jump_omni.visible = false
	add_child(_jump_omni)
	_jump_omni.position = marker_local("MK_JumpLight").origin + Vector3(0, -0.15, -0.25)


## しぶきの出どころ（set_water_fx の種類ごと）：数・寿命・大きさ・空気の抵抗・機体の速さを受け継ぐ割合・濃さ。
## stretch は飛ぶ向きへの伸び（fp_spray.gdshader）。
const SPRAY_KINDS := {
	"bow": {"amount": 90, "life": 1.2, "size": [0.9, 2.4], "damping": 1.2, "inherit": 0.15, "alpha": 0.6, "box": Vector3(0.5, 0.1, 0.9), "spread": 24.0, "stretch": 2.2},
	"step": {"amount": 150, "life": 1.5, "size": [1.2, 3.4], "damping": 1.8, "inherit": 0.3, "alpha": 0.6, "box": Vector3(0.45, 0.1, 1.8), "spread": 18.0, "stretch": 2.6},
	"stern": {"amount": 100, "life": 1.6, "size": [1.1, 3.2], "damping": 1.6, "inherit": 0.2, "alpha": 0.55, "box": Vector3(0.4, 0.1, 0.6), "spread": 16.0, "stretch": 2.4},
	"prop": {"amount": 56, "life": 1.8, "size": [2.6, 5.5], "damping": 2.2, "inherit": 0.0, "alpha": 0.22, "box": Vector3(1.1, 0.05, 1.3), "spread": 34.0, "stretch": 1.3},
	"drip": {"amount": 72, "life": 0.9, "size": [0.12, 0.3], "damping": 0.2, "inherit": 0.85, "alpha": 0.8, "box": Vector3(0.3, 0.05, 4.2), "spread": 8.0, "stretch": 3.5},
}
const SPRAY_SHADER := preload("res://assets/vehicles/floatplane_c130/shaders/fp_spray.gdshader")

static var _spray_texture: Texture2D = null


func _build_sprays() -> void:
	var rows: Array = []
	for marker_name: String in _markers:
		if not marker_name.begins_with("MK_Spray"):
			continue
		var kind := "bow" if marker_name.contains("Bow") else ("step" if marker_name.contains("Step") else "stern")
		rows.append([marker_name.replace("MK_", ""), kind, marker_local(marker_name).origin, -1.0 if marker_name.ends_with("_L") else 1.0])
	for i: int in range((layout.get("props", []) as Array).size()):
		var hub := _vec((layout.props[i] as Dictionary).get("hub", [0, 5.2, -3.7]))
		rows.append(["PropWash_%d" % (i + 1), "prop", Vector3(hub.x, 0.05, hub.z + 1.2), signf(hub.x)])
	for side: float in [-1.0, 1.0]:
		rows.append(["Drip_%s" % ("L" if side < 0.0 else "R"), "drip", Vector3(3.6 * side, -0.55, 1.6), side])
	for row: Array in rows:
		var kind := String(row[1])
		var info: Dictionary = SPRAY_KINDS[kind]
		var spray := GPUParticles3D.new()
		spray.name = String(row[0])
		spray.set_meta("kind", kind)
		spray.set_meta("side", float(row[3]))
		spray.set_meta("base_amount", int(info.amount))
		spray.amount = int(info.amount)
		spray.lifetime = float(info.life)
		spray.randomness = 0.4
		spray.emitting = false
		spray.local_coords = false
		# 粒は世界に残るので、機体のうしろへ長く伸びる（機体のローカルの +Z がうしろ）
		spray.visibility_aabb = AABB(Vector3(-32, -6, -24), Vector3(64, 28, 100))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = info.box
		pm.direction = Vector3(0, -1, 0) if kind == "drip" else Vector3(0, 1, 0.35)
		pm.spread = float(info.spread)
		pm.initial_velocity_min = 0.2 if kind == "drip" else 2.5
		pm.initial_velocity_max = 1.2 if kind == "drip" else 5.5
		pm.gravity = Vector3(0, -9.8 if kind != "prop" else -1.5, 0)
		pm.damping_min = float(info.damping) * 0.7
		pm.damping_max = float(info.damping)
		pm.inherit_velocity_ratio = float(info.inherit)
		# 粒の Y を飛ぶ向きへ（描く板はその向きに伸びる）
		pm.particle_flag_align_y = true
		var sizes: Array = info.size
		pm.scale_min = float(sizes[0])
		pm.scale_max = float(sizes[1])
		var curve := Curve.new()
		if kind == "drip":
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(1.0, 0.7))
		else:
			# しぶきは出てすぐ広がり、崩れて霧になる
			curve.add_point(Vector2(0.0, 0.35))
			curve.add_point(Vector2(0.25, 0.9))
			curve.add_point(Vector2(1.0, 1.7))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
		var grad := Gradient.new()
		var alpha := float(info.alpha)
		grad.offsets = PackedFloat32Array([0.0, 0.08, 0.45, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, alpha), Color(0.93, 0.96, 1.0, alpha * 0.7), Color(0.86, 0.91, 0.96, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		spray.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var qm := ShaderMaterial.new()
		qm.shader = SPRAY_SHADER
		qm.set_shader_parameter("blob", _spray_blob())
		qm.set_shader_parameter("stretch", float(info.stretch))
		quad.material = qm
		spray.draw_pass_1 = quad
		spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spray)
		spray.position = row[2]
		_sprays.append(spray)


## しぶきの粒の絵（白い、ふちがちぎれた丸）。1 度だけ作る。
static func _spray_blob() -> Texture2D:
	if _spray_texture != null:
		return _spray_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) / float(size) * 2.0 - Vector2.ONE
			var r := p.length()
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# ふちが目立たないよう、ガウスのように薄れる中に、ちぎれた濃淡
			var a := exp(-r * r * 3.2) * clampf(0.25 + n * 1.1, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r))
			a = clampf(a * 1.25, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	image.generate_mipmaps()
	_spray_texture = ImageTexture.create_from_image(image)
	return _spray_texture


func _mount_pilot() -> void:
	pilot = HatenaPilot.new()
	pilot.name = "HatenaPilot"
	pilot.use_lod = quality == QualityRules.LOW
	add_child(pilot)
	var info: Dictionary = layout.get("hatena", {})
	var seat := marker_local("MK_PilotSeat")
	pilot.transform = Transform3D(seat.basis.scaled(Vector3.ONE * float(info.get("scale", 1.0))), seat.origin)
	if not pilot.setup():
		pilot.queue_free()
		pilot = null


static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2])) if arr.size() >= 3 else Vector3.ZERO
