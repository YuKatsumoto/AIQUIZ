class_name OnlineSkinSign
extends Node3D

## オンライン対戦メニューのトップで、立っている自分のキャラの横に立てる「スキン設定」の看板。
## 柱 2 本と板と文字だけの小物で、原点は床（柱の足元の中心）、文字は +Z 側から読める。
## 置き場所・出し入れ・クリックの判定は OnlineMenu が受け持つ（hit_test で当たりを調べる）。

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const BOARD_SIZE := Vector3(1.36, 0.46, 0.06)
const BOARD_CENTER_Y := 1.2
const FRAME_MARGIN := 0.05
const POST_X := 0.5
const POST_SIZE := Vector3(0.07, 0.0, 0.07)
const BOARD_COLOR := Color("#13253a")
const FRAME_COLOR := Color("#ffd94a")
const POST_COLOR := Color(0.32, 0.36, 0.42)
const TEXT_COLOR := Color(0.96, 0.97, 1.0)
## カーソルが乗ったときの、わくの光と大きさ
const HOVER_GLOW := 1.6
const HOVER_SCALE := 1.06
const POP_SECONDS := 0.28

var hovered := false

var _frame_material: StandardMaterial3D
var _body: Node3D
var _shown := false
var _tween: Tween = null


func _ready() -> void:
	_build()
	visible = false
	_body.scale = Vector3.ONE * 0.01


## ふわっと出す／しまう（出ている間だけ visible）。
func set_shown(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if value:
		visible = true
		_body.scale = Vector3.ONE * 0.01
		_tween.tween_property(_body, "scale", Vector3.ONE * (HOVER_SCALE if hovered else 1.0), POP_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		set_hovered(false)
		_tween.tween_property(_body, "scale", Vector3.ONE * 0.01, POP_SECONDS * 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tween.tween_callback(func() -> void: visible = false)


func is_shown() -> bool:
	return _shown


func set_hovered(value: bool) -> void:
	if value == hovered:
		return
	hovered = value
	_frame_material.emission_energy_multiplier = HOVER_GLOW if value else 0.35
	if _shown and (_tween == null or not _tween.is_running()):
		var tween := create_tween()
		tween.tween_property(_body, "scale", Vector3.ONE * (HOVER_SCALE if value else 1.0), 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ワールドのレイが看板（柱を含む外形の箱）に当たるか。
func hit_test(ray_origin: Vector3, ray_dir: Vector3) -> bool:
	if not _shown or not is_inside_tree():
		return false
	var to_local := _body.global_transform.affine_inverse()
	var origin := to_local * ray_origin
	var dir := to_local.basis * ray_dir
	var half_w := BOARD_SIZE.x * 0.5 + FRAME_MARGIN
	var box := AABB(Vector3(-half_w, 0.0, -0.12), Vector3(half_w * 2.0, BOARD_CENTER_Y + BOARD_SIZE.y * 0.5 + FRAME_MARGIN, 0.24))
	return box.intersects_ray(origin, dir) != null


## 看板の真ん中（文字のあたり）のワールド座標。
func board_center() -> Vector3:
	return _body.global_transform * Vector3(0.0, BOARD_CENTER_Y, 0.0)


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var post_height := BOARD_CENTER_Y + BOARD_SIZE.y * 0.5
	var post_material := _material(POST_COLOR, 0.55, 0.5)
	for side: float in [-1.0, 1.0]:
		_box("Post", Vector3(POST_SIZE.x, post_height, POST_SIZE.z), Vector3(side * POST_X, post_height * 0.5, -0.05), post_material)
		_box("Foot", Vector3(0.16, 0.04, 0.26), Vector3(side * POST_X, 0.02, -0.05), post_material)
	_frame_material = _material(FRAME_COLOR, 0.0, 0.45)
	_frame_material.emission_enabled = true
	_frame_material.emission = FRAME_COLOR
	_frame_material.emission_energy_multiplier = 0.35
	var frame_size := Vector3(BOARD_SIZE.x + FRAME_MARGIN * 2.0, BOARD_SIZE.y + FRAME_MARGIN * 2.0, BOARD_SIZE.z * 0.6)
	_box("Frame", frame_size, Vector3(0.0, BOARD_CENTER_Y, -0.01), _frame_material)
	_box("Board", BOARD_SIZE, Vector3(0.0, BOARD_CENTER_Y, 0.0), _material(BOARD_COLOR, 0.0, 0.7))
	var front := BOARD_SIZE.z * 0.5 + 0.004
	_label("Title", "スキン設定", 112, TEXT_COLOR, Vector3(0.0, BOARD_CENTER_Y, front))


func _box(node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	_body.add_child(node)
	return node


func _label(node_name: String, text: String, font_size: int, color: Color, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = 0.0021
	label.text = text
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	_body.add_child(label)
	return label


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
