class_name OnlineHeliportHelicopter
extends Node3D

## オンラインメニューのヘリ 1 機：乗り込めるヘリ（assets/vehicles/helicopter_boarding/helicopter_boarding.glb）。
## このノードの原点は「ヘリの座標（H）」：接地点（スキッドの下面の中心）、+x＝機体の右、+y＝上、-z＝機首。
## GLB（原点＝ローターの軸）は子の Model として skid_drop だけ上に置く。目印（MK_*）は marker() で H 座標の Transform3D を返す。
## 動かし方は素材の README と同じ：
##   色替え：材質 BodyPaint の面だけ（set_tint）。BodyAccent（帯より下・尾翼の濃紺）は色替えしない
##   ガラス：材質 Windows の面に shaders/heli_glass.gdshader（風防だけサンバイザーの帯）
##   塗装（BodyPaint / BodyAccent / Trim）はクリアコートのつやを足す（glTF のクリアコートは Godot が読まないのでここで付ける）
##   デカール（Decal：ロゴ・紋章・細い線・黄黒の帯、DecalNumber：尾翼の機体番号）は 1 枚のアトラス。アルファで重ね、
##     ほかの半透明（ガラス・ローターの円盤・炎）より先に描く（render_priority -8）。影は落とさない。
##     機体番号は set_livery_slot(slot)：DecalNumber を機体ごとに複製し、uv1_offset でアトラスの行を選ぶ（1 = AQ-01、2 = AQ-02）
##     室内（Interior：計器盤の銘板・後ろの仕切りのコルクボード）のデカールは紙なので、別の材質にしてつやを消す
##   ドア：Door_L / Door_R をローカル +Z（ヒンジ）回りに open_deg（set_door(side, 0〜1)）
##   ローター：回る勢い spool（0＝止まる、1＝飛べる）が目標へゆっくり近づく。spool が ROTOR_BLUR_SPOOL を超えたら羽根をぼかした円盤に替える
##     MainRotor はハブ（回っても見えたまま）、子の MainRotorBlades が羽根（円盤のあいだ隠す）。羽根 3 枚、止めると 1 枚が機首の上
##   尾：フェネストロン（TailRotor はファンの羽根だけ、ローカル X で回る）。回っているときは羽根をぼかした円盤（TailFanDisc）に替える
##   表示：Belt_L は座ったら出す（set_belt）、Booster_R はハテナが右の席にいる間、Beacon は 1 Hz で 0.12 秒光る、
##         StrobeLights（尾の白いストロボ）はローターが回っている間だけ、ビーコンと交互に光る
## 操縦士ハテナ（HatenaPilot、等倍）を MK_SeatPilot に座らせる。
## ジェットブースト：左右の JetPod_* はふだん下へたたんである。enable_jets() で炎を用意し、set_jet_charge(0〜1) で
##   翼を水平まで上げる → 噴射口の羽根（JetNozzle_*）を広げる → 奥の光（JetGlow_*）を強める。ignite_jets() で炎を出す。
##   本編のヘリ登場（HelicopterArrivalDirector）が、降ろしたあと・迎えのあとの発進で使う。

const HELICOPTER_SCENE := "res://assets/vehicles/helicopter_boarding/helicopter_boarding.glb"
const LAYOUT_PATH := "res://assets/vehicles/helicopter_boarding/helicopter_boarding_layout.json"
const WINDOW_GLASS_COLOR := Color(0.62, 0.84, 0.95, 0.30)
const MAIN_ROTOR_SPEED := 26.0
## 羽根が見えているとき（円盤にしない）の 1 フレームの回りの上限。30 fps でも 3 枚羽根が逆回りに見えないように
const MAIN_ROTOR_MAX_STEP := 0.70
const TAIL_ROTOR_SPEED := 42.0
## フェネストロンのファン：速さ、羽根が見えているときの 1 フレームの回りの上限（羽根の間 29° の半分より小さく）、円盤の縞の回り
const TAIL_FAN_SPEED := 64.0
const TAIL_FAN_MAX_STEP := 0.22
const TAIL_FAN_SWIRL := 5.0
## 尾のストロボ（1 秒に 1 回、0.06 秒。ビーコンと半周期ずらす）
const STROBE_PERIOD := 1.0
const STROBE_ON := 0.06
const STROBE_PHASE := 0.5
const STROBE_MIN_SPOOL := 0.05
const SPOOL_UP_RATE := 0.45
const SPOOL_DOWN_RATE := 0.22
const ROTOR_BLUR_SPOOL := 0.8
const BEACON_PERIOD := 1.0
const BEACON_ON := 0.12
const BoostExhaustScript := preload("res://scripts/world/helicopter_boost_exhaust.gd")
const HelicopterSoundScript := preload("res://scripts/world/helicopter_sound.gd")
var sound: Node = null
## 左右のポッドの炎の大きさ（1.0 ＝ 今までの尾の 1 本の炎）
const JET_FLAME_SIZE := 0.72
const JET_GLOW_COLOR := Color(1.0, 0.55, 0.16)
## 帯より下・尾翼の濃紺（素材の hb_common.NAVY_HEX と同じ）
const BRAND_NAVY := Color("#1D2F5C")
const PAINT_CLEARCOAT := 0.30
const PAINT_CLEARCOAT_ROUGHNESS := 0.20
const TRIM_CLEARCOAT := 0.20
const TRIM_CLEARCOAT_ROUGHNESS := 0.25
const DECAL_RENDER_PRIORITY := -8
## 室内のデカール（紙の銘板・コルクボードの写真）のざらつき。クリアコートは付けない
const INTERIOR_DECAL_ROUGHNESS := 0.85
const GLASS_SHADER := preload("res://shaders/heli_glass.gdshader")
const ROTOR_DISC_SHADER := preload("res://shaders/online_staging_rotor_disc.gdshader")
const QualityRules := preload("res://scripts/core/graphics_quality.gd")
## 光る物（全部の面を光る材質に塗り替える）。素材では面を 1 つにしてある
const LIGHT_NODES := ["Beacon", "NavLight_L", "NavLight_R", "LandingLight", "StrobeLights"]

var layout: Dictionary = {}
var model: Node3D = null
var pilot: HatenaPilot = null
var skid_drop := 1.75
var spool := 0.0
var spool_target := 0.0
## ローターの速さの倍率（本編の発進の溜めで上げる）
var rotor_speed_factor := 1.0
## false にするとローターの円盤に替えない（品質「低」）
var rotor_blur_enabled := true

var _main_rotor: Node3D = null
var _tail_rotor: Node3D = null
var _main_rest := Basis.IDENTITY
var _main_angle := 0.0
var _rotor_disc: MeshInstance3D = null
var _rotor_disc_material: ShaderMaterial = null
var _rotor_blades: Array[Node3D] = []
var _doors := {}       # "L"/"R" -> {"node": Node3D, "rest": Basis, "open_deg": float}
var _door_open := {"L": 0.0, "R": 0.0}
var _hatches: Array[Node3D] = []
var _hatch_rest: Array[Basis] = []
var _body_materials: Array[BaseMaterial3D] = []
var _belts := {}       # "L"/"R" -> Node3D
var _belt_rest := {}   # "L"/"R" -> Vector3（縮尺）
var _booster: Node3D = null
var _beacon_material: StandardMaterial3D = null
var _markers := {}     # name -> Transform3D（H 座標）
var _time := 0.0
var _jets: Array[Dictionary] = []   # {pod, rest, deploy, nozzle, nozzle_rest, glow_material, exhaust}
var _jet_charge := 0.0
var jets_ignited := false
var _material_cache := {}   # 元の材質（とガラスの風防／ドア）→ このヘリの材質
var _fenestron := false
var _tail_disc: MeshInstance3D = null
var _tail_disc_material: ShaderMaterial = null
var _tail_swirl := 0.0
var _strobe_material: StandardMaterial3D = null
var _anisotropic := true
var livery_slot := 1
var _number_materials: Array[BaseMaterial3D] = []


static func load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## low_quality：品質「低」。ハテナを軽い版（8,000 三角形）にし、ローターを円盤に替えない。
func setup(tint: Color, with_pilot: bool = true, low_quality: bool = false) -> bool:
	rotor_blur_enabled = not low_quality
	_anisotropic = not low_quality
	layout = load_layout()
	skid_drop = float(layout.get("skid_drop", 1.75))
	var packed := load(HELICOPTER_SCENE) as PackedScene
	if packed == null:
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	model.position = Vector3(0.0, skid_drop, 0.0)
	_main_rotor = model.find_child("MainRotor", true, false) as Node3D
	_tail_rotor = model.find_child("TailRotor", true, false) as Node3D
	if _main_rotor != null:
		_main_rest = _main_rotor.basis
	for side: String in ["L", "R"]:
		var door := model.find_child("Door_" + side, true, false) as Node3D
		if door != null:
			var info: Dictionary = layout.get("doors", {}).get("Door_" + side, {})
			_doors[side] = {"node": door, "rest": door.basis, "open_deg": float(info.get("open_deg", -90.0 if side == "L" else 90.0))}
		var belt := model.find_child("Belt_" + side, true, false) as Node3D
		if belt != null:
			_belts[side] = belt
			_belt_rest[side] = belt.scale
	for hatch_name: String in ["DropHatchLeft", "DropHatchRight"]:
		var hatch := model.find_child(hatch_name, true, false) as Node3D
		if hatch != null:
			_hatches.append(hatch)
			_hatch_rest.append(hatch.basis)
	_booster = model.find_child("Booster_R", true, false) as Node3D
	_read_markers()
	_find_jets()
	_prepare_materials(tint)
	_build_rotor_disc()
	_build_tail_disc()
	_add_lights()
	# 小さな部品（灯など）と、光る物・画面は影を落とさない
	QualityRules.drop_tiny_shadow_casters(model)
	for node_name: String in ["DashScreens", "JetGlow_L", "JetGlow_R"]:
		var lit := model.find_child(node_name, true, false) as GeometryInstance3D
		if lit != null:
			lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_belt("L", 0.0)
	set_belt("R", 1.0 if with_pilot else 0.0)
	if _booster != null:
		_booster.visible = with_pilot
	if with_pilot:
		_mount_pilot(low_quality)
	sound = HelicopterSoundScript.new()
	sound.name = "HelicopterSound"
	add_child(sound)
	sound.setup(self)
	return _main_rotor != null and _tail_rotor != null


## Owners enable sound only when the real presentation starts; construction is silent.
func set_sound_enabled(active: bool) -> void:
	if sound != null:
		sound.set_engine(spool, rotor_speed_factor, _jet_charge, jets_ignited)
		sound.set_enabled(active)


# ---------- 目印 ----------

## 目印の Transform3D（H 座標）。原点は位置、basis は yaw だけ（-Z が向く先）。
func marker(name: String) -> Transform3D:
	return _markers.get(name, Transform3D.IDENTITY)


func marker_position(name: String) -> Vector3:
	return marker(name).origin


func has_marker(name: String) -> bool:
	return _markers.has(name)


## 目印のワールドの位置。
func marker_global(name: String) -> Vector3:
	return global_transform * marker_position(name)


func _read_markers() -> void:
	var listed: Dictionary = layout.get("markers", {})
	for name: String in listed:
		var info: Dictionary = listed[name]
		var p: Array = info.get("position", [0, 0, 0])
		# JSON は GLB の座標（原点＝ローターの軸）。GLB の MK_* と一致することは tests/helicopter_boarding_check.gd が確かめる
		var position := Vector3(float(p[0]), float(p[1]) + skid_drop, float(p[2]))
		var yaw_value: Variant = info.get("yaw_deg")
		var basis := Basis.IDENTITY if yaw_value == null else Basis(Vector3.UP, deg_to_rad(float(yaw_value)))
		_markers[name] = Transform3D(basis, position)
	# 操縦かんの握り（H 座標）
	for yoke: String in layout.get("yokes", {}):
		var grips: Dictionary = layout.yokes[yoke]
		for key: String in ["grip_l", "grip_r"]:
			var g: Array = grips.get(key, [0, 0, 0])
			_markers["%s_%s" % [yoke, key]] = Transform3D(Basis.IDENTITY, Vector3(float(g[0]), float(g[1]) + skid_drop, float(g[2])))


# ---------- 見た目 ----------

func set_tint(color: Color) -> void:
	for material: BaseMaterial3D in _body_materials:
		material.albedo_color = color


## 画質を変えたとき（OnlineHeliportStage.apply_graphics_quality）。低ではローターを円盤に替えない。
func apply_quality(quality: String) -> void:
	rotor_blur_enabled = quality != QualityRules.LOW
	_anisotropic = quality != QualityRules.LOW
	for material: Variant in _material_cache.values():
		if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null:
			(material as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if _anisotropic else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## side："L" / "R"、openness：0（閉じる）〜1（開く）。開き方はだんだん遅く（呼ぶ側で時間の割合を渡す）。
func set_door(side: String, openness: float) -> void:
	if not _doors.has(side):
		return
	var door: Dictionary = _doors[side]
	var t := clampf(openness, 0.0, 1.0)
	_door_open[side] = t
	(door.node as Node3D).basis = (door.rest as Basis) * Basis(Vector3(0, 0, 1), deg_to_rad(float(door.open_deg)) * t)
	if sound != null:
		sound.set_mechanism(StringName("door_" + side), t)


func door_openness(side: String) -> float:
	return float(_door_open.get(side, 0.0))


## ベルト：0 で隠す、0〜1 で縮尺 0.6 → 1.0（出てくるところ）。
func set_belt(side: String, amount: float) -> void:
	var belt := _belts.get(side) as Node3D
	if belt == null:
		return
	belt.visible = amount > 0.0
	belt.scale = (_belt_rest[side] as Vector3) * lerpf(0.6, 1.0, clampf(amount, 0.0, 1.0))
	if sound != null:
		sound.set_mechanism(StringName("belt_" + side), amount)


## 0（閉じる）〜1（開く）。
func set_hatch(openness: float) -> void:
	var t := smoothstep(0.0, 1.0, clampf(openness, 0.0, 1.0))
	if sound != null:
		sound.set_mechanism(&"hatch", openness)
	for i: int in range(_hatches.size()):
		var side := -1.0 if i == 0 else 1.0
		_hatches[i].basis = _hatch_rest[i] * Basis(Vector3(0, 0, 1), side * deg_to_rad(78.0) * t)


## ローターを止めた向き（前後）にそろえる。
func park_rotor() -> void:
	spool = 0.0
	spool_target = 0.0
	_main_angle = 0.0
	if _main_rotor != null:
		_main_rotor.basis = _main_rest
	_update_rotor_blur()


func _process(delta: float) -> void:
	_time += delta
	var rate := SPOOL_UP_RATE if spool_target > spool else SPOOL_DOWN_RATE
	spool = move_toward(spool, spool_target, rate * delta)
	if sound != null:
		sound.set_engine(spool, rotor_speed_factor, _jet_charge, jets_ignited)
	if spool > 0.0001:
		# 立ち上がりは遅く（2 乗）、満ちると速い
		var factor := spool * spool * 1.15 * rotor_speed_factor
		var step := MAIN_ROTOR_SPEED * factor * delta
		if not _blades_blurred():
			step = minf(step, MAIN_ROTOR_MAX_STEP)
		_main_angle = fmod(_main_angle + step, TAU)
		if _main_rotor != null:
			_main_rotor.basis = _main_rest * Basis(Vector3.UP, _main_angle)
		if _tail_rotor != null and _fenestron:
			if _tail_rotor.visible:
				_tail_rotor.rotate_object_local(Vector3.RIGHT, minf(TAIL_FAN_SPEED * factor * delta, TAIL_FAN_MAX_STEP))
			_tail_swirl = fmod(_tail_swirl + TAIL_FAN_SWIRL * factor * delta, TAU)
		elif _tail_rotor != null:
			_tail_rotor.rotate_object_local(Vector3.RIGHT, TAIL_ROTOR_SPEED * factor * delta)
	_update_rotor_blur()
	if _beacon_material != null:
		var on := fmod(_time, BEACON_PERIOD) < BEACON_ON
		_beacon_material.emission_energy_multiplier = 4.0 if on else 0.15
	if _strobe_material != null:
		var flash := spool > STROBE_MIN_SPOOL and fmod(_time + STROBE_PHASE, STROBE_PERIOD) < STROBE_ON
		_strobe_material.emission_energy_multiplier = 6.0 if flash else 0.2


# ---------- ジェットブースト ----------

func _find_jets() -> void:
	var pods: Dictionary = layout.get("jet_boost", {}).get("pods", {})
	var open_scale := float(layout.get("jet_boost", {}).get("nozzle_open_scale", 1.35))
	for pod_name: String in pods:
		var info: Dictionary = pods[pod_name]
		var pod := model.find_child(pod_name, true, false) as Node3D
		if pod == null:
			continue
		var nozzle := model.find_child(str(info.get("nozzle", "")), true, false) as Node3D
		var glow := model.find_child(str(info.get("glow", "")), true, false) as MeshInstance3D
		var glow_material: StandardMaterial3D = null
		if glow != null and glow.mesh != null:
			glow_material = StandardMaterial3D.new()
			glow_material.albedo_color = JET_GLOW_COLOR.darkened(0.35)
			glow_material.emission_enabled = true
			glow_material.emission = JET_GLOW_COLOR
			glow_material.emission_energy_multiplier = 0.0
			for surface: int in range(glow.mesh.get_surface_count()):
				glow.set_surface_override_material(surface, glow_material)
		var exit: Array = info.get("nozzle_exit_local", [0, 0, 0])
		_jets.append({
			"pod": pod, "rest": pod.basis, "deploy": deg_to_rad(float(info.get("deploy_deg", 0.0))),
			"nozzle": nozzle, "nozzle_rest": nozzle.scale if nozzle != null else Vector3.ONE, "open_scale": open_scale,
			"glow_material": glow_material, "exit": Vector3(float(exit[0]), float(exit[1]), float(exit[2])), "exhaust": null,
		})


func has_jets() -> bool:
	return not _jets.is_empty()


## 炎（GPUParticles）を用意する。メニューの背景のように発進しないヘリでは呼ばない。
func enable_jets() -> void:
	for jet: Dictionary in _jets:
		if jet.exhaust != null:
			continue
		var exhaust := BoostExhaustScript.new() as HelicopterBoostExhaust
		exhaust.size = JET_FLAME_SIZE
		exhaust.name = "%sExhaust" % (jet.pod as Node3D).name
		(jet.pod as Node3D).add_child(exhaust)
		exhaust.position = jet.exit
		jet.exhaust = exhaust


## 発進の溜め 0〜1：はじめの 55% で翼を上げ、35〜90% で羽根を広げ、45% から奥が光る。
func set_jet_charge(charge: float) -> void:
	_jet_charge = clampf(charge, 0.0, 1.0)
	var deploy := smoothstep(0.0, 0.55, _jet_charge)
	var open := smoothstep(0.35, 0.9, _jet_charge)
	var glow := smoothstep(0.45, 1.0, _jet_charge)
	for jet: Dictionary in _jets:
		(jet.pod as Node3D).basis = (jet.rest as Basis) * Basis(Vector3(0, 0, 1), float(jet.deploy) * deploy)
		var nozzle := jet.nozzle as Node3D
		if nozzle != null:
			var k := lerpf(1.0, float(jet.open_scale), open)
			var rest: Vector3 = jet.nozzle_rest
			nozzle.scale = Vector3(rest.x * k, rest.y * k, rest.z)
		var material := jet.glow_material as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 7.0 if jets_ignited else glow * 4.5


func jet_charge() -> float:
	return _jet_charge


## smoke：煙（SmokeVFX）も出す。使うのはオンラインの発進（急発進）だけ。
func ignite_jets(smoke: bool = false) -> void:
	set_jet_charge(1.0)
	jets_ignited = true
	for jet: Dictionary in _jets:
		var material := jet.glow_material as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 7.0
		var exhaust := jet.exhaust as HelicopterBoostExhaust
		if exhaust != null:
			exhaust.ignite(smoke)


## ジェットを切る：炎を止め（残りの粒は燃え尽きる。煙は漂って消える）、奥の光を落とす。ポッドの格納は呼ぶ側が set_jet_charge で 1 → 0 へ動かす。
## instant なら炎も煙も今すぐ消す（暗転・カットの下で切るとき）。
func extinguish_jets(instant: bool = false) -> void:
	jets_ignited = false
	for jet: Dictionary in _jets:
		var exhaust := jet.exhaust as HelicopterBoostExhaust
		if exhaust != null and is_instance_valid(exhaust):
			exhaust.extinguish(instant)
	set_jet_charge(_jet_charge)


## ジェットをしまう：炎を今すぐ消し、ポッドを畳んだ状態（溜め 0）に戻す。
func stow_jets() -> void:
	extinguish_jets(true)
	set_jet_charge(0.0)


## 読み込み中の予熱：炎と煙を一度だけ描いて、点火のときにシェーダーを作らないようにする。
func set_jet_prewarm(active: bool) -> void:
	for jet: Dictionary in _jets:
		var exhaust := jet.exhaust as HelicopterBoostExhaust
		if exhaust != null and is_instance_valid(exhaust):
			exhaust.set_prewarm(active)


## ジェットの煙（空中に残る）を offset（ワールド）だけ動かす。原点を動かさない飛行で、海と雲といっしょに後ろへ流すため。
func drift_jet_smoke(offset: Vector3) -> void:
	for jet: Dictionary in _jets:
		var exhaust := jet.exhaust as HelicopterBoostExhaust
		if exhaust != null and is_instance_valid(exhaust):
			exhaust.drift_smoke(offset)


## このヘリを消す前に、空中に残っている煙を parent へ移す（煙はその場で薄れて消え、ヘリといっしょに消えない）。
func release_jet_smoke(parent: Node) -> void:
	for jet: Dictionary in _jets:
		var exhaust := jet.exhaust as HelicopterBoostExhaust
		if exhaust != null and is_instance_valid(exhaust):
			exhaust.release_smoke(parent)


func _blades_blurred() -> bool:
	return _rotor_disc != null and rotor_blur_enabled and spool > ROTOR_BLUR_SPOOL


func _update_rotor_blur() -> void:
	var blur := _blades_blurred()
	if _rotor_disc != null:
		_rotor_disc.visible = blur
		for blade: Node3D in _rotor_blades:
			blade.visible = not blur
		if blur and _rotor_disc_material != null:
			_rotor_disc_material.set_shader_parameter("spin", _main_angle)
	if _tail_disc != null:
		_tail_disc.visible = blur
		if _tail_rotor != null:
			_tail_rotor.visible = not blur
		if blur:
			_tail_disc_material.set_shader_parameter("spin", _tail_swirl)


## 素材の材質 1 つから、このヘリで使う材質を作る。null なら取り込んだ材質のまま使う（上書きしない）。
static func prepare_surface_material(source: Material, tint: Color, node_name: String, anisotropic: bool, glass_layout: Dictionary = {}) -> Material:
	if source == null:
		return null
	match source.resource_name:
		"BodyPaint":
			var paint := source.duplicate(true) as BaseMaterial3D
			if paint == null:
				return null
			paint.albedo_color = tint
			_add_clearcoat(paint, PAINT_CLEARCOAT, PAINT_CLEARCOAT_ROUGHNESS)
			return paint
		"BodyAccent":
			var accent := source.duplicate(true) as BaseMaterial3D
			if accent == null:
				return null
			_add_clearcoat(accent, PAINT_CLEARCOAT, PAINT_CLEARCOAT_ROUGHNESS)
			return accent
		"Trim":
			var trim := source.duplicate(true) as BaseMaterial3D
			if trim == null:
				return null
			_add_clearcoat(trim, TRIM_CLEARCOAT, TRIM_CLEARCOAT_ROUGHNESS)
			return trim
		"Decal", "DecalNumber":
			# アトラス（テクスチャ）は共有。材質だけ機体ごと（番号の行・画質で変える）
			var decal := source.duplicate() as BaseMaterial3D
			if decal == null:
				return null
			configure_decal_material(decal, anisotropic)
			if node_name == "Interior":
				decal.clearcoat_enabled = false
				decal.roughness = INTERIOR_DECAL_ROUGHNESS
			return decal
		"Windows":
			return make_glass_material(node_name == "Windows", glass_layout)
	return null


## デカール：アルファで重ねる（深度は書かない＝影も落とさない）。頂点色（細い線の色・焼いた AO）を掛ける。
## ほかの半透明より先に描く。デカールは必ず不透明な外板の上にあるので、後ろに半透明はない。
static func configure_decal_material(material: BaseMaterial3D, anisotropic: bool = true) -> void:
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.vertex_color_use_as_albedo = true
	material.texture_repeat = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if anisotropic else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.render_priority = DECAL_RENDER_PRIORITY
	_add_clearcoat(material, PAINT_CLEARCOAT, PAINT_CLEARCOAT_ROUGHNESS)


## 機体番号の行のずれ（uv1_offset）。slot 1 = AQ-01（GLB のまま）、2 = AQ-02。layout の livery.number_uv_step を使う。
static func number_uv_offset(layout_data: Dictionary, slot: int) -> Vector3:
	var livery: Dictionary = layout_data.get("livery", {})
	var step: Array = livery.get("number_uv_step", [0.0, 0.0])
	var count := maxi(1, (livery.get("numbers", []) as Array).size())
	var k := clampi(slot - 1, 0, count - 1)
	if step.size() < 2:
		return Vector3.ZERO
	return Vector3(float(step[0]) * k, float(step[1]) * k, 0.0)


## 尾翼の機体番号を選ぶ（1 = AQ-01、2 = AQ-02）。setup の前でも後でもよい。
func set_livery_slot(slot: int) -> void:
	livery_slot = slot
	var offset := number_uv_offset(layout, slot)
	for material: BaseMaterial3D in _number_materials:
		material.uv1_offset = offset


static func _add_clearcoat(material: BaseMaterial3D, amount: float, roughness: float) -> void:
	material.clearcoat_enabled = true
	material.clearcoat = amount
	material.clearcoat_roughness = roughness


## ガラス：風防（canopy）だけサンバイザーの帯。帯の高さは layout の glass.visor_y（GLB の y）。
static func make_glass_material(canopy: bool, glass_layout: Dictionary = {}) -> ShaderMaterial:
	var glass := ShaderMaterial.new()
	glass.shader = GLASS_SHADER
	glass.set_shader_parameter("visor_strength", 1.0 if canopy else 0.0)
	var visor: Array = glass_layout.get("visor_y", [])
	if visor.size() == 2:
		glass.set_shader_parameter("visor_y0", float(visor[0]))
		glass.set_shader_parameter("visor_y1", float(visor[1]))
	return glass


func _prepare_materials(tint: Color) -> void:
	_body_materials.clear()
	_number_materials.clear()
	var glass_layout: Dictionary = layout.get("glass", {})
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or str(mesh_instance.name) in LIGHT_NODES:
			continue
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			# 同じ元の材質は 1 つの材質を使い回す（ガラスは風防とドア、デカールは外と室内で分ける）
			var key: Variant = source
			if source.resource_name == "Windows":
				key = "glass_canopy" if mesh_instance.name == "Windows" else "glass_door"
			elif source.resource_name == "Decal" and mesh_instance.name == "Interior":
				key = "decal_interior"
			var prepared: Variant = _material_cache.get(key)
			if prepared == null and not _material_cache.has(key):
				prepared = prepare_surface_material(source, tint, mesh_instance.name, _anisotropic, glass_layout)
				_material_cache[key] = prepared
				if source.resource_name == "BodyPaint" and prepared is BaseMaterial3D:
					_body_materials.append(prepared as BaseMaterial3D)
				elif source.resource_name == "DecalNumber" and prepared is BaseMaterial3D:
					_number_materials.append(prepared as BaseMaterial3D)
			if prepared != null:
				mesh_instance.set_surface_override_material(surface, prepared as Material)
	set_livery_slot(livery_slot)
	var beacon := model.find_child("Beacon", true, false) as MeshInstance3D
	if beacon != null and beacon.mesh != null:
		_beacon_material = StandardMaterial3D.new()
		_beacon_material.albedo_color = Color(0.85, 0.08, 0.06)
		_beacon_material.emission_enabled = true
		_beacon_material.emission = Color(1.0, 0.12, 0.08)
		_beacon_material.emission_energy_multiplier = 0.15
		_beacon_material.roughness = 0.25
		_warn_light_surfaces(beacon)
		for surface: int in range(beacon.mesh.get_surface_count()):
			beacon.set_surface_override_material(surface, _beacon_material)
	var strobe := model.find_child("StrobeLights", true, false) as MeshInstance3D
	if strobe != null and strobe.mesh != null:
		_strobe_material = StandardMaterial3D.new()
		_strobe_material.albedo_color = Color(0.95, 0.95, 0.92)
		_strobe_material.emission_enabled = true
		_strobe_material.emission = Color(1.0, 0.98, 0.94)
		_strobe_material.emission_energy_multiplier = 0.2
		_warn_light_surfaces(strobe)
		for surface: int in range(strobe.mesh.get_surface_count()):
			strobe.set_surface_override_material(surface, _strobe_material)
	for pair: Array in [["NavLight_L", Color(1.0, 0.15, 0.1)], ["NavLight_R", Color(0.2, 1.0, 0.35)], ["LandingLight", Color(1.0, 0.97, 0.85)]]:
		var lamp := model.find_child(pair[0], true, false) as MeshInstance3D
		if lamp == null or lamp.mesh == null:
			continue
		var glow := StandardMaterial3D.new()
		glow.albedo_color = pair[1]
		glow.emission_enabled = true
		glow.emission = pair[1]
		glow.emission_energy_multiplier = 2.2 if pair[0] != "LandingLight" else 0.6
		_warn_light_surfaces(lamp)
		for surface: int in range(lamp.mesh.get_surface_count()):
			lamp.set_surface_override_material(surface, glow)


func _warn_light_surfaces(lamp: MeshInstance3D) -> void:
	if lamp.mesh.get_surface_count() > 1:
		push_warning("%s has %d surfaces; every surface glows (housings belong in Body)" % [lamp.name, lamp.mesh.get_surface_count()])


## 回っている羽根の代わりの円盤（半透明の輪の縞。spin で縞が回る）。
func _build_rotor_disc() -> void:
	if _main_rotor == null:
		return
	var rotor_info: Dictionary = layout.get("main_rotor", {})
	var blades := _main_rotor.find_child(str(rotor_info.get("blades_node", "MainRotorBlades")), false, false) as Node3D
	if blades != null:
		# 羽根だけ隠し、ハブ（MainRotor）は回って見えたまま
		_rotor_blades.append(blades)
	else:
		# 古い GLB：MainRotor ごと隠す
		for child: Node in _main_rotor.get_children():
			if child is Node3D:
				_rotor_blades.append(child as Node3D)
		if _main_rotor is MeshInstance3D:
			_rotor_blades.append(_main_rotor)
	var radius := float(rotor_info.get("radius", 5.3))
	_rotor_disc = MeshInstance3D.new()
	_rotor_disc.name = "RotorDisc"
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 48
	disc.rings = 1
	_rotor_disc.mesh = disc
	_rotor_disc_material = ShaderMaterial.new()
	_rotor_disc_material.shader = ROTOR_DISC_SHADER
	_rotor_disc_material.set_shader_parameter("r_max", radius)
	if blades != null:
		var bands: Array = rotor_info.get("tip_bands", [])
		_rotor_disc_material.set_shader_parameter("blade_count", float(rotor_info.get("blades", 3)))
		_rotor_disc_material.set_shader_parameter("root_radius", float(rotor_info.get("root_radius", 0.82)))
		_rotor_disc_material.set_shader_parameter("root_ramp", 0.4)
		_rotor_disc_material.set_shader_parameter("hub_radius", 0.0)
		_rotor_disc_material.set_shader_parameter("tip_amount", 0.0)
		_rotor_disc_material.set_shader_parameter("hazard_amount", 1.0)
		if bands.size() == 3:
			_rotor_disc_material.set_shader_parameter("tip_bands", Vector4(float(bands[0][0]), float(bands[1][0]), float(bands[2][0]), float(bands[2][1])))
	_rotor_disc.material_override = _rotor_disc_material
	_rotor_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotor_disc.visible = false
	model.add_child(_rotor_disc)
	var hub := Vector3(0.0, 2.25, 0.0)
	var pivot: Array = layout.get("main_rotor", {}).get("pivot", [0, 2.25, 0])
	hub = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	# 羽根のある GLB は羽根の面の高さ（根元 ~0.0〜先 -0.15）、古い GLB はハブの上
	_rotor_disc.position = hub + Vector3(0.0, -0.03 if blades != null else 0.06, 0.0)


## フェネストロンのファンの代わりの円盤（同じシェーダー。羽根 10 枚、ハブは描かない）。
func _build_tail_disc() -> void:
	var info: Dictionary = layout.get("tail_rotor", {})
	_fenestron = str(info.get("type", "")) == "fenestron"
	if not _fenestron or _tail_rotor == null:
		return
	var radius := minf(float(info.get("radius", 0.452)) + 0.012, float(info.get("duct_radius", 0.47)) - 0.004)
	_tail_disc = MeshInstance3D.new()
	_tail_disc.name = "TailFanDisc"
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.002
	disc.radial_segments = 32
	disc.rings = 1
	_tail_disc.mesh = disc
	_tail_disc_material = ShaderMaterial.new()
	_tail_disc_material.shader = ROTOR_DISC_SHADER
	_tail_disc_material.set_shader_parameter("r_max", radius)
	_tail_disc_material.set_shader_parameter("blade_count", float(info.get("blade_count", 10)))
	_tail_disc_material.set_shader_parameter("root_radius", float(info.get("hub_radius", 0.142)))
	_tail_disc_material.set_shader_parameter("root_ramp", 0.03)
	_tail_disc_material.set_shader_parameter("hub_radius", 0.0)
	_tail_disc_material.set_shader_parameter("tip_amount", 0.0)
	_tail_disc_material.set_shader_parameter("hazard_amount", 0.0)
	_tail_disc_material.set_shader_parameter("trail_length", 2.5)
	_tail_disc_material.set_shader_parameter("strength", 0.55)
	_tail_disc_material.set_shader_parameter("blade_color", Color(0.50, 0.53, 0.57))
	_tail_disc.material_override = _tail_disc_material
	_tail_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail_disc.visible = false
	model.add_child(_tail_disc)
	var pivot: Array = info.get("pivot", [0.0, 1.67, 6.36])
	# 円盤の面をファンの面（YZ）へ：Y 軸を X へ倒す
	_tail_disc.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2])))


func _add_lights() -> void:
	for pair: Array in [["MK_CockpitLight", 0.9, 2.6], ["MK_CabinLight", 0.5, 2.2]]:
		if not _markers.has(pair[0]):
			continue
		var light := OmniLight3D.new()
		light.name = str(pair[0]).trim_prefix("MK_")
		light.light_color = Color(1.0, 0.93, 0.84)
		light.light_energy = float(pair[1])
		light.omni_range = float(pair[2])
		light.shadow_enabled = false
		add_child(light)
		light.position = marker_position(pair[0])


func _mount_pilot(low_quality: bool) -> void:
	pilot = HatenaPilot.new()
	pilot.name = "HatenaPilot"
	pilot.use_lod = low_quality
	add_child(pilot)
	var seat := marker("MK_SeatPilot")
	var info: Dictionary = layout.get("hatena", {})
	var yaw := deg_to_rad(float(info.get("yaw_deg", 180.0)))
	pilot.transform = Transform3D(Basis(Vector3.UP, yaw) * float(info.get("scale", 1.0)), seat.origin)
	if not pilot.setup():
		pilot.queue_free()
		pilot = null
		if _booster != null:
			_booster.visible = false
