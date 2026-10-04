class_name LectureSet
extends Node3D

## 設定画面の地下神殿に置く「連結チップソー講座」のセット（ui/settings_hall.tscn）。
## 小道具（lecture_set_props.glb）と 5 体のゴドーくん（godotkun_*.glb、各 1 本のループ）は Blender で作る
## （assets/settings_hall/source/blender/build_lecture_set.py、配置の定数はそのビルダーと同じ）。
## ここで作るのは Godot 側だけで持ちたいもの: スポットライト、API 状態に連動する黒板の文字と状態ランプ、
## 教材の台車（ゲームの linked_saw_carriage.glb を縮めて展示台に載せる）。
## ローカル座標: 原点はホールの床、+Z が黒板側（カメラから遠い側）。カメラは +X 側の手前（-Z）から見下ろす。
## 小道具と人物は既定の描画レイヤーに置く（ホールの舞台はレイヤー11で焼いた光）。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

## 舞台のメッシュだけの描画レイヤー（CisternStage.HALL_LAYER = 11）。実ライトはここを外す。
const HALL_LAYER_MASK := 1 << 10

const ASSET_DIR := "res://assets/settings_hall/"
const PROPS_GLB := ASSET_DIR + "lecture_set_props.glb"
## 登場人物: GLB、足元の位置（セットのローカル）、向き（0 = +Z = 黒板向き）、ループのクリップ名。
## 位置はビルダー（build_lecture_set.py の CAST）と同じ。
const CAST := {
	"lecturer": {"path": ASSET_DIR + "godotkun_lecturer.glb", "at": Vector3(3.4, 0.0, 6.5), "yaw": 180.0, "clip": "Teach"},
	"student_notes": {"path": ASSET_DIR + "godotkun_student_notes.glb", "at": Vector3(-2.3, 0.0, 0.74), "yaw": 0.0, "clip": "TakeNotes"},
	"student_hand": {"path": ASSET_DIR + "godotkun_student_hand.glb", "at": Vector3(0.0, 0.0, 0.74), "yaw": 0.0, "clip": "RaiseHand"},
	"student_doze": {"path": ASSET_DIR + "godotkun_student_doze.glb", "at": Vector3(2.3, 0.0, 0.74), "yaw": 0.0, "clip": "Doze"},
	"trainee": {"path": ASSET_DIR + "godotkun_trainee.glb", "at": Vector3(-4.4, 0.0, 1.2), "yaw": 0.0, "clip": "Practice"},
}

# ------------------------------------------------------------------ layout (local metres, same as the builder)
const BOARD_POS := Vector3(0.0, 0.0, 8.6)
const BOARD_SIZE := Vector2(7.6, 3.3)
const BOARD_CENTER_Y := 2.3
## 黒板の左 5.6 m が文字の領域（右 1.8 m はチョーク画）。
const BOARD_TEXT_WIDTH := 5.6
const LAMP_POS := Vector3(4.3, 0.0, 7.6)
const SAW_TABLE_POS := Vector3(-3.9, 0.45, 5.4)
const SAW_TABLE_SIZE := Vector3(5.6, 0.9, 1.5)
const SAW_SCALE := 0.22
const SAW_YAW_DEG := 8.0
const SAW_SPIN_SPEED := 0.35

# ------------------------------------------------------------------ light
const KEY_FROM := Vector3(3.5, 4.8, -3.0)
const KEY_AIM := Vector3(0.0, 0.8, 3.0)
const FILL_FROM := Vector3(-4.0, 3.6, -2.5)
const FILL_AIM := Vector3(0.0, 0.5, -0.5)
const RIM_FROM := Vector3(-2.0, 5.0, 7.5)
const RIM_AIM := Vector3(0.0, 0.6, 1.0)
const KEY_ENERGY := 14.0
const FILL_ENERGY := 5.0
const RIM_ENERGY := 8.0
const LAMP_ENERGY := 1.2
const LAMP_EMISSION := 4.5

const COLOR_OK := Color(0.35, 0.90, 0.45)
const COLOR_FAIL := Color(1.0, 0.35, 0.35)
const COLOR_CHECKING := Color(1.0, 0.80, 0.30)
const COLOR_IDLE := Color(0.70, 0.76, 0.86)
const CHALK := Color(0.93, 0.94, 0.90)

var _quality := GraphicsQualityRules.BALANCED
var _clock := 0.0
var _lit := 0.0
var _spots: Array[SpotLight3D] = []
var _spot_energy: Array[float] = []
var _key_light: SpotLight3D = null
var _lamp_light: OmniLight3D = null
var _lamp_material: StandardMaterial3D = null
var _lamp_color := COLOR_IDLE
var _lamp_pulsing := false
var _status_labels: Array[Label3D] = []
var _props: Node3D = null
var _cast: Dictionary = {}
var _players: Array[AnimationPlayer] = []
var _saw: Node3D = null
var _built := false
var _rng := RandomNumberGenerator.new()


## 読み込み役（settings_hall.gd）が別スレッドで読む GLB の一覧。
static func asset_paths() -> Array[String]:
	var paths: Array[String] = [PROPS_GLB]
	for key: String in CAST:
		paths.append(str((CAST[key] as Dictionary).path))
	return paths


func build(quality: String) -> void:
	if _built:
		apply_quality(quality)
		return
	_built = true
	_quality = GraphicsQualityRules.normalize(quality)
	_rng.seed = 0x5E7
	_build_board_text()
	_build_lamp()
	_build_lights()
	apply_quality(_quality)
	set_lit(0.0)


func has_props() -> bool:
	return _props != null


func cast_count() -> int:
	return _cast.size()


func has_saw() -> bool:
	return _saw != null


## 読み込みが終わった GLB を受け取る（小道具・人物のどれでも）。
func attach_asset(path: String, packed: PackedScene) -> void:
	if packed == null:
		return
	if path == PROPS_GLB:
		_attach_props(packed)
		return
	for key: String in CAST:
		if str((CAST[key] as Dictionary).path) == path:
			_attach_character(key, packed)
			return
	push_warning("LectureSet: unknown asset %s" % path)


# ------------------------------------------------------------------ Godot-side pieces

## 黒板の文字（API 状態）。ビルダーの黒板の左 5.6 m に重ねる。
func _build_board_text() -> void:
	var text_center_x := BOARD_SIZE.x * 0.5 - BOARD_TEXT_WIDTH * 0.5
	var top := BOARD_CENTER_Y + BOARD_SIZE.y * 0.5
	var z := BOARD_POS.z - 0.1
	var title := _chalk_label("Title", "連結チップソー概論", 64, Vector3(text_center_x, top - 0.38, z))
	title.modulate = Color(1.0, 0.90, 0.55)
	_chalk_label("Sub", "第3講：安全な観察距離と回転数", 40, Vector3(text_center_x, top - 0.82, z))
	var names := ["Internet", "Gateway", "Firebase", "Offline"]
	for index in range(names.size()):
		var label := _chalk_label("Status" + names[index], "", 56,
			Vector3(BOARD_SIZE.x * 0.5 - 0.3, top - 1.32 - 0.47 * float(index), z))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.modulate = COLOR_IDLE
		_status_labels.append(label)
	set_api_status({})


func _chalk_label(node_name: String, text: String, font_size: int, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font = FONT_BOLD
	label.font_size = font_size
	label.pixel_size = 0.008
	label.width = (BOARD_TEXT_WIDTH - 0.4) / 0.008
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = CHALK
	label.outline_modulate = Color(0.02, 0.05, 0.04, 0.9)
	label.outline_size = 4
	label.shaded = false
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.text = text
	label.position = at
	label.rotation.y = PI
	add_child(label)
	return label


func _build_lamp() -> void:
	var lamp_root := Node3D.new()
	lamp_root.name = "StatusLamp"
	lamp_root.position = LAMP_POS
	add_child(lamp_root)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.28, 0.30, 0.33)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.04
	cylinder.bottom_radius = 0.06
	cylinder.height = 2.0
	pole.mesh = cylinder
	pole.material_override = steel
	pole.position = Vector3(0.0, 1.0, 0.0)
	lamp_root.add_child(pole)
	var foot := MeshInstance3D.new()
	foot.name = "Foot"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.16
	disc.bottom_radius = 0.18
	disc.height = 0.04
	foot.mesh = disc
	foot.material_override = steel
	foot.position = Vector3(0.0, 0.02, 0.0)
	lamp_root.add_child(foot)
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb"
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	bulb.mesh = sphere
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = COLOR_IDLE
	_lamp_material.emission_enabled = true
	_lamp_material.emission = COLOR_IDLE
	_lamp_material.emission_energy_multiplier = LAMP_EMISSION
	bulb.material_override = _lamp_material
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = Vector3(0.0, 2.12, 0.0)
	lamp_root.add_child(bulb)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "Light"
	_lamp_light.light_color = COLOR_IDLE
	_lamp_light.light_energy = LAMP_ENERGY
	_lamp_light.omni_range = 3.5
	_lamp_light.shadow_enabled = false
	_lamp_light.light_cull_mask = 0xFFFFF & ~HALL_LAYER_MASK
	_lamp_light.position = Vector3(0.0, 2.12, 0.0)
	lamp_root.add_child(_lamp_light)


func _build_lights() -> void:
	_key_light = _spot("KeyLight", KEY_FROM, KEY_AIM, KEY_ENERGY, 16.0, 32.0, Color(1.0, 0.93, 0.82))
	_spot("FillLight", FILL_FROM, FILL_AIM, FILL_ENERGY, 14.0, 40.0, Color(0.80, 0.86, 1.0))
	_spot("RimLight", RIM_FROM, RIM_AIM, RIM_ENERGY, 14.0, 30.0, Color(0.95, 0.97, 1.0))


func _spot(node_name: String, from: Vector3, aim: Vector3, energy: float, range_m: float, angle: float, color: Color) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = energy
	light.light_specular = 0.6
	light.spot_range = range_m
	light.spot_angle = angle
	light.spot_angle_attenuation = 1.2
	light.shadow_enabled = false
	light.light_cull_mask = 0xFFFFF & ~HALL_LAYER_MASK
	light.transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)
	add_child(light)
	_spots.append(light)
	_spot_energy.append(energy)
	return light


# ------------------------------------------------------------------ assets

func _attach_props(packed: PackedScene) -> void:
	if _props != null:
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		return
	root.name = "Props"
	add_child(root)
	_props = root
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 台座と黒板は影を落とさなくてよい（影の予算を人物に回す）。
	for name in ["PRP_Platform", "PRP_Blackboard"]:
		var big := root.find_child(name, true, false)
		if big is MeshInstance3D:
			(big as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disable_collision(root)


## 人物: 足元を置き、自分のクリップをループで回す（位相をずらして同期させない）。
func _attach_character(key: String, packed: PackedScene) -> void:
	if _cast.has(key):
		return
	var spec: Dictionary = CAST[key]
	var root := packed.instantiate() as Node3D
	if root == null:
		return
	root.name = "Cast_" + key
	root.position = spec.at
	root.rotation.y = deg_to_rad(float(spec.yaw))
	add_child(root)
	_disable_collision(root)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := _find_clip(player, str(spec.clip))
	if player != null and not clip.is_empty():
		var animation := player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		player.seek(_rng.randf() * animation.length, true)
		_players.append(player)
	else:
		push_warning("LectureSet: %s has no animation %s (has %s)" % [key, spec.clip,
			player.get_animation_list() if player != null else "no AnimationPlayer"])
	_cast[key] = root


## 教材の模型: 連結チップソーの台車（assets/hazards/linked_saw_carriage.glb）を縮めて展示台に載せ、ゆっくり回す。
func attach_saw(packed: PackedScene) -> void:
	if _saw != null or packed == null:
		return
	var holder := Node3D.new()
	holder.name = "SawExhibit"
	holder.position = SAW_TABLE_POS + Vector3(0.0, SAW_TABLE_SIZE.y * 0.5, 0.0)
	add_child(holder)
	var model := packed.instantiate() as Node3D
	if model == null:
		holder.queue_free()
		return
	model.rotation.y = PI + deg_to_rad(SAW_YAW_DEG) # Blender +Y exports toward Godot -Z.
	model.scale = Vector3.ONE * SAW_SCALE
	holder.add_child(model)
	GraphicsQualityRules.drop_tiny_shadow_casters(model)
	_disable_collision(model)
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		var animation := node as AnimationPlayer
		var spin_clip: StringName = &""
		for clip: StringName in animation.get_animation_list():
			if str(clip) in ["Spin_Loop", "Spin"]:
				spin_clip = clip
		if spin_clip == &"":
			continue
		var clip_animation := animation.get_animation(spin_clip)
		if clip_animation != null:
			clip_animation.loop_mode = Animation.LOOP_LINEAR
		animation.speed_scale = SAW_SPIN_SPEED
		animation.play(spin_clip)
	_saw = holder


## インポート時にライブラリ名や接尾辞が付くことがある（"lib/Teach"、"Teach_002"）ので、それらも探す。
static func _find_clip(player: AnimationPlayer, clip: String) -> String:
	if player == null:
		return ""
	if player.has_animation(clip):
		return clip
	for name: StringName in player.get_animation_list():
		var plain := str(name).get_file() if str(name).contains("/") else str(name)
		if plain == clip or plain.begins_with(clip + "_") or plain.begins_with(clip + "."):
			return str(name)
	return ""


func _disable_collision(root: Node) -> void:
	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body != null:
			body.collision_layer = 0
			body.collision_mask = 0


# ------------------------------------------------------------------ state

func apply_quality(quality: String) -> void:
	_quality = GraphicsQualityRules.normalize(quality)
	if _key_light != null:
		_key_light.shadow_enabled = GraphicsQualityRules.gameplay_shadow_enabled(_quality)


## セットの照明（スポットと状態ランプ）の強さ 0〜1。0 のライトは描かない。
func set_lit(amount: float) -> void:
	_lit = clampf(amount, 0.0, 1.0)
	for index in range(_spots.size()):
		var light := _spots[index]
		light.light_energy = _spot_energy[index] * _lit
		light.visible = _lit > 0.001
	_apply_lamp()


func lit() -> float:
	return _lit


## 黒板の 4 行と状態ランプ。summary は SettingsHallPanel.api_summary()（空なら未チェック）。
func set_api_status(summary: Dictionary) -> void:
	var internet: Variant = summary.get("internet", null)
	var gateway: Variant = summary.get("gateway", null)
	var firebase: Variant = summary.get("firebase", null)
	var checked := bool(summary.get("checked", not summary.is_empty()))
	_set_status_line(0, "● ネット：%s" % _status_word(internet, checked, true), internet, checked)
	_set_status_line(1, "● AI Gateway：%s" % _status_word(gateway, checked, bool(summary.get("gateway_configured", false))), gateway, checked)
	_set_status_line(2, "● Firebase：%s" % _status_word(firebase, checked, bool(summary.get("firebase_configured", false))), firebase, checked)
	var offline := int(summary.get("offline_count", 0))
	_set_status_line(3, "自習プリント：%d問" % offline, true, true)
	if _status_labels.size() > 3:
		_status_labels[3].modulate = CHALK
	var statuses: Array = [internet, gateway, firebase]
	if not checked:
		_lamp_color = COLOR_IDLE
		_lamp_pulsing = false
	elif statuses.has(false):
		_lamp_color = COLOR_FAIL
		_lamp_pulsing = false
	elif statuses.has(null):
		_lamp_color = COLOR_CHECKING
		_lamp_pulsing = true
	else:
		_lamp_color = COLOR_OK
		_lamp_pulsing = false
	_apply_lamp()


func _status_word(status: Variant, checked: bool, configured: bool) -> String:
	if not checked:
		return "未チェック"
	if not configured:
		return "未設定"
	if status == null:
		return "チェック中"
	return "接続OK" if bool(status) else "接続失敗"


func _set_status_line(index: int, text: String, status: Variant, checked: bool) -> void:
	if index < 0 or index >= _status_labels.size():
		return
	var label := _status_labels[index]
	label.text = text
	if not checked:
		label.modulate = COLOR_IDLE
	elif status == null:
		label.modulate = COLOR_CHECKING
	else:
		label.modulate = COLOR_OK if bool(status) else COLOR_FAIL


func _apply_lamp() -> void:
	if _lamp_material == null or _lamp_light == null:
		return
	var pulse := 1.0
	if _lamp_pulsing:
		pulse = 0.55 + 0.45 * sin(_clock * TAU * 2.0)
	_lamp_material.albedo_color = _lamp_color
	_lamp_material.emission = _lamp_color
	_lamp_material.emission_energy_multiplier = LAMP_EMISSION * lerpf(0.35, 1.0, _lit) * pulse
	_lamp_light.light_color = _lamp_color
	_lamp_light.light_energy = LAMP_ENERGY * _lit * pulse
	_lamp_light.visible = _lit > 0.001


func _process(delta: float) -> void:
	_clock += delta
	if _lamp_pulsing:
		_apply_lamp()
