class_name LectureSet
extends Node3D

## 時間帯の明るさが変わった（1 = 夜）。ホールが行の照明と環境光をそれに合わせる。
signal mood_changed(night: float)

## 設定画面の地下神殿に置く「連結チップソー講座」のセット（ui/settings_hall.tscn）。
## 小道具（lecture_set_props.glb）と 5 体のゴドーくん（godotkun_*.glb、各 1 本のループ）は Blender で作る
## （assets/settings_hall/source/blender/build_lecture_set.py、配置の定数はそのビルダーと同じ）。
## ここで作るのは Godot 側だけで持ちたいもの: スポットライト、API 状態に連動する黒板の文字と状態ランプ、
## 教材の台車（ゲームの linked_saw_carriage.glb を縮めて展示台に載せる）。
## ローカル座標: 原点はホールの床、+Z が黒板側（カメラから遠い側）。カメラは +X 側の手前（-Z）から見下ろす。
## 小道具と人物は既定の描画レイヤーに置く（ホールの舞台はレイヤー11で焼いた光）。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const ChalkCanvasScript := preload("res://scripts/world/settings_hall/chalk_canvas.gd")
const LectureDirectorScript := preload("res://scripts/world/settings_hall/lecture_director.gd")
const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

## 舞台のメッシュだけの描画レイヤー（CisternStage.HALL_LAYER = 11）。実ライトはここを外す。
const HALL_LAYER_MASK := 1 << 10

const ASSET_DIR := "res://assets/settings_hall/"
const PROPS_GLB := ASSET_DIR + "lecture_set_props.glb"
## 漫符（！？怒り・汗・…・♪・電球）。進行役が人物の頭の上に出す（lsb_fx.py）。
const FX_GLB := ASSET_DIR + "lecture_fx.glb"
## 登場人物: GLB、足元の位置（セットのローカル）、向き（0 = +Z = 黒板向き）、ループのクリップ名。
## 位置はビルダー（build_lecture_set.py の CAST）と同じ。
const CAST := {
	"lecturer": {"path": ASSET_DIR + "godotkun_lecturer.glb", "at": Vector3(3.4, 0.0, 6.5), "yaw": 180.0, "clip": "Teach"},
	"student_notes": {"path": ASSET_DIR + "godotkun_student_notes.glb", "at": Vector3(-2.3, 0.0, 0.74), "yaw": 0.0, "clip": "TakeNotes"},
	"student_hand": {"path": ASSET_DIR + "godotkun_student_hand.glb", "at": Vector3(0.0, 0.0, 0.74), "yaw": 0.0, "clip": "RaiseHand"},
	"student_doze": {"path": ASSET_DIR + "godotkun_student_doze.glb", "at": Vector3(2.3, 0.0, 0.74), "yaw": 0.0, "clip": "Doze"},
	"trainee": {"path": ASSET_DIR + "godotkun_trainee.glb", "at": Vector3(-4.4, 0.0, 1.2), "yaw": 0.0, "clip": "Practice"},
	# ふだんは隠していて、授業の出来事のときだけ出てくる（lecture_director.gd の EXTRAS）
	"duty": {"path": ASSET_DIR + "godotkun_duty.glb", "at": Vector3(5.2, 0.0, 2.2), "yaw": 0.0, "clip": "G_Idle", "hidden": true},
	"vice": {"path": ASSET_DIR + "godotkun_vice.glb", "at": Vector3(5.0, 0.0, 9.6), "yaw": 0.0, "clip": "G_Idle", "hidden": true},
	"transfer": {"path": ASSET_DIR + "godotkun_transfer.glb", "at": Vector3(5.2, 0.0, 2.6), "yaw": 0.0, "clip": "G_Idle", "hidden": true},
	"janitor": {"path": ASSET_DIR + "godotkun_janitor.glb", "at": Vector3(-6.4, 0.0, -1.2), "yaw": 0.0, "clip": "G_Idle", "hidden": true},
	"parent": {"path": ASSET_DIR + "godotkun_parent.glb", "at": Vector3(-6.4, 0.0, -3.4), "yaw": 0.0, "clip": "G_Idle", "hidden": true},
}
## 授業の進行役が動かす人物（練習生は実習の自分のループのまま）。
const DIRECTED := ["lecturer", "student_notes", "student_hand", "student_doze", "trainee", "duty", "vice", "transfer", "janitor", "parent"]

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
var _night := 0.0
var _spots: Array[SpotLight3D] = []
var _spot_energy: Array[float] = []
var _key_light: SpotLight3D = null
var _lamp_light: OmniLight3D = null
var _lamp_material: StandardMaterial3D = null
var _lamp_color := COLOR_IDLE
var _lamp_pulsing := false
var _lamp_flicker := false
var _status_labels: Array[Label3D] = []
## 黒板の面の絵（ChalkCanvas）。"F" = 前の（下の）パネル、"B" = 後ろの（上の）パネル。
var boards: Dictionary = {}
## 黒板の面の大きさ（m、Blender の lsb_board.PANEL_W − 2×TRIM と PANEL_H − 2×TRIM）
const BOARD_FACE := Vector2(7.53, 1.71)
const BOARD_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D canvas_tex : source_color, filter_linear_mipmap;
uniform sampler2D wet_tex : filter_linear;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float normal_depth = 1.0;
uniform bool has_normal = false;
void fragment() {
	float wet = clamp(texture(wet_tex, UV).r, 0.0, 1.0);
	ALBEDO = texture(canvas_tex, UV).rgb * mix(1.0, 0.4, wet);
	ROUGHNESS = mix(0.95, 0.24, wet);
	SPECULAR = mix(0.18, 0.5, wet);
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth * (1.0 - 0.6 * wet);
	}
}
"""
var _props: Node3D = null
var _cast: Dictionary = {}
var _players: Array[AnimationPlayer] = []
var _saw: Node3D = null
## 壁掛け時計の針（PRP_ClockHand_H / M / S、原点 = 文字盤の中心、休止で 12 時を指す）。PC の時計で回す。
var _clock_hands: Dictionary = {}
## 授業の進行役（lecture_director.gd）。小道具と人物が全部そろったら作る。
var director: Node = null
var _fx_scene: PackedScene = null
var _attempted: Dictionary = {}
var _built := false
var _rng := RandomNumberGenerator.new()


## 読み込み役（settings_hall.gd）が別スレッドで読む GLB の一覧。
static func asset_paths() -> Array[String]:
	var paths: Array[String] = [PROPS_GLB, FX_GLB]
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
	# 黒板には API の状態を出さない（状態は左の設定パネル）。題字はチョークで黒板の絵に書く（_setup_boards）。
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
## packed が null なら読み込みに失敗した印（そろうのを待つ数に入れる）。
func attach_asset(path: String, packed: PackedScene) -> void:
	_attempted[path] = true
	if packed != null:
		if path == FX_GLB:
			_fx_scene = packed
		elif path == PROPS_GLB:
			_attach_props(packed)
		else:
			var known := false
			for key: String in CAST:
				if str((CAST[key] as Dictionary).path) == path:
					_attach_character(key, packed)
					known = true
			if not known:
				push_warning("LectureSet: unknown asset %s" % path)
	_try_start_director()


## 小道具と人物の読み込みが全部終わったら（失敗したものは飛ばして）、授業の進行役を動かす。
func _try_start_director() -> void:
	if director != null or _props == null or not _cast.has("lecturer") or not boards.has("F"):
		return
	for path: String in asset_paths():
		if not _attempted.has(path):
			return
	var cast := {}
	for key: String in DIRECTED:
		if _cast.has(key):
			cast[key] = _cast[key]
	var node: Node = LectureDirectorScript.new()
	node.name = "LectureDirector"
	add_child(node)
	node.set("fx_scene", _fx_scene)
	if node.call("setup", self, _props, cast, boards):
		director = node
	else:
		push_warning("LectureSet: lecture director could not start (lesson or glyph data missing)")
		node.queue_free()
		if boards.has("B"):
			var b: SubViewport = boards["B"]
			b.stamp_text("連結チップソー概論", Vector2(0.45, 1.05), 0.34, "yellow", 0.9)
			b.stamp_text("第3講　安全な観察距離と回転数", Vector2(0.5, 0.45), 0.2, "white", 0.8)


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
	for name in ["PRP_Platform", "PRP_PlatformEdge", "PRP_Blackboard", "PRP_BoardSurface_F", "PRP_BoardSurface_B"]:
		var big := root.find_child(name, true, false)
		if big is MeshInstance3D:
			(big as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key in ["H", "M", "S"]:
		var hand := root.find_child("PRP_ClockHand_" + key, true, false) as Node3D
		if hand != null:
			if hand is MeshInstance3D:
				(hand as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_clock_hands[key] = hand
	_update_clock()
	_setup_boards(root)
	# 時間帯の小道具（昼食の弁当）はふだん隠す（第 3 段階の時間帯の仕組みが出し入れする）
	for node: Node in root.find_children("PRP_Bento_*", "Node3D", true, false):
		(node as Node3D).visible = false
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
	if spec.get("hidden", false):
		root.visible = false
		root.process_mode = Node.PROCESS_MODE_DISABLED
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
	_apply_spots()
	_apply_lamp()


## 状態ランプをちらつかせる・直す（進行役の用務員の場面）。
func set_lamp_flicker(on: bool) -> void:
	_lamp_flicker = on
	_apply_lamp()


## 状態ランプの電球の位置（セットのローカル）。
func lamp_point() -> Vector3:
	return LAMP_POS + Vector3(0.0, 2.12, 0.0)


## 時間帯の明るさ（進行役が使う）: 1 = 夜（部屋のスポットを落とす）、0 = ふだん。
func set_mood(night: float) -> void:
	_night = clampf(night, 0.0, 1.0)
	_apply_spots()
	mood_changed.emit(_night)


func _apply_spots() -> void:
	var scale := _lit * lerpf(1.0, 0.18, _night)
	for index in range(_spots.size()):
		var light := _spots[index]
		light.light_energy = _spot_energy[index] * scale
		light.visible = scale > 0.001


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
	if _lamp_flicker:
		# 接触不良のちらつき（用務員が直しに来る: 項目 118）
		pulse *= 0.05 if fmod(_clock * 7.3, 1.0) < 0.35 or fmod(_clock * 2.9, 1.0) < 0.2 else 1.0
	_lamp_material.albedo_color = _lamp_color
	_lamp_material.emission = _lamp_color
	_lamp_material.emission_energy_multiplier = LAMP_EMISSION * lerpf(0.35, 1.0, _lit) * pulse
	_lamp_light.light_color = _lamp_color
	_lamp_light.light_energy = LAMP_ENERGY * _lit * pulse
	_lamp_light.visible = _lit > 0.001


## 黒板の 2 枚の面の材質の色を ChalkCanvas の絵に差し替える（下地は Blender で焼いた色）。題字を書き付ける。
func _setup_boards(root: Node) -> void:
	for tag in ["F", "B"]:
		var surface := root.find_child("PRP_BoardSurface_" + tag, true, false) as MeshInstance3D
		if surface == null or surface.mesh == null:
			continue
		var source := surface.get_active_material(0) as BaseMaterial3D
		if source == null:
			continue
		var canvas: SubViewport = ChalkCanvasScript.new()
		canvas.name = "BoardCanvas_" + tag
		add_child(canvas)
		canvas.setup(source.albedo_texture, BOARD_FACE, 2048)
		# 黒板（ホーローにつや消しの塗り）はほとんど光を返さない（焼いた粗さのままだと、近くのスポットの
		# 鏡面の照り返しが白いもやのように広がる）。濡れ雑巾で拭いたところだけ暗く、つやつやになる
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = BOARD_SHADER
		material.shader = shader
		material.set_shader_parameter("canvas_tex", canvas.get_texture())
		material.set_shader_parameter("wet_tex", canvas.call("wet_texture"))
		if source.normal_enabled and source.normal_texture != null:
			material.set_shader_parameter("normal_tex", source.normal_texture)
			material.set_shader_parameter("normal_depth", source.normal_scale)
			material.set_shader_parameter("has_normal", true)
		surface.material_override = material
		boards[tag] = canvas
	# 上の黒板の題は、授業の進行役が今回の講義に合わせて書く（lesson_builder.gd）


## 時計の針を PC の時刻に合わせる。文字盤は Godot -z（カメラ）を向き、針は +Z まわりに回すと見る人から時計回り。
## 秒針は 1 秒ごとにカチッと進む（学校の時計）。
func _update_clock() -> void:
	if _clock_hands.is_empty():
		return
	var now := Time.get_time_dict_from_system()
	var sec := float(now.second)
	var minute := float(now.minute) + sec / 60.0
	var hour := fmod(float(now.hour), 12.0) + minute / 60.0
	var turns := {"H": hour / 12.0, "M": minute / 60.0, "S": sec / 60.0}
	for key: String in _clock_hands:
		(_clock_hands[key] as Node3D).rotation.z = TAU * float(turns[key])


## 3D の人物をクリックすると反応する（UI が受け取らなかったクリックだけ）。
func _unhandled_input(event: InputEvent) -> void:
	if director == null or not is_visible_in_tree():
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var key: String = director.call("pick_actor", click.position)
	if key != "":
		director.call("on_click", key)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_clock += delta
	_update_clock()
	if _lamp_pulsing or _lamp_flicker:
		_apply_lamp()
