extends Node3D
class_name TutorialKeycap3D

## チュートリアルで3D空間に浮かべる操作キー1個。
## 実キーボードと同じ「裾を絞った角丸キャップ＋皿状の天面」を手続き生成し、
## 刻印・押し込み・発光枠・達成チェックをこの1ノードで扱う。
## どのキーをどこへ並べるかは res://scripts/world/tutorial_key_guides_3d.gd が決める。
##
## ローカル座標: +Y が天面の法線、-Z が刻印の上方向。ノードの向きを変えれば
## キー全体がカメラへ向く。1u（標準キー1個分）の外形を 1.0 とし、大きさは親でスケールする。

enum Look { IDLE, TARGET, DONE }

const LEGEND_FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

const PITCH := 1.0
const GAP := 0.10
const CAP_HEIGHT := 0.50
const SIDE_INSET := 0.11
const BOTTOM_RADIUS := 0.12
const TOP_BEVEL := 0.05
const DISH_DEPTH := 0.035
const PLATE_MARGIN := 0.08
## 押し込み量（TRAVEL）より厚くし、沈んだキャップの裾が下から覗かないようにする。
const PLATE_THICKNESS := 0.30
const TRAVEL := 0.22
const CORNER_SEGMENTS := 5
const SIDE_RINGS := 4
const DISH_RINGS := 4

## 2Dのキーボード説明（tutorial_keyboard.gd）と同じ配色。
const IVORY := Color("e6e2d8")
const INK := Color("14243b")
const PLATE_COLOR := Color("16263d")
const DONE_COLOR := Color("8fdcb4")
const DONE_INK := Color("1d5c43")
const PRESSED_COLOR := Color("fbfff0")

const PRESS_SPEED := 14.0
const POP_SECONDS := 0.32
const DONE_FLASH_SECONDS := 0.5

static var _cap_meshes: Dictionary = {}
static var _plate_meshes: Dictionary = {}
static var _frame_meshes: Dictionary = {}

var legend: String = ""
var sub_legend: String = ""
var width_units: float = 1.0
var accent: Color = Color("ffa440")

var _look: int = Look.IDLE
var _pressed: bool = false
var _depth: float = 0.0
var _time: float = 0.0
var _pop: float = 0.0
var _visible_target: bool = true
var _done_flash: float = 0.0

var _cap_pivot: Node3D = null
var _cap: MeshInstance3D = null
var _plate: MeshInstance3D = null
var _frame: MeshInstance3D = null
var _legend_label: Label3D = null
var _sub_label: Label3D = null
var _check: Node3D = null
var _cap_material: StandardMaterial3D = null
var _plate_material: StandardMaterial3D = null
var _frame_material: StandardMaterial3D = null
var _check_material: StandardMaterial3D = null


func setup(key_legend: String, units: float, key_accent: Color, key_sub_legend: String = "") -> void:
	legend = key_legend
	sub_legend = key_sub_legend
	width_units = maxf(1.0, units)
	accent = key_accent
	_build()
	_apply_look()


## 刻印だけを差し替える（1Pで矢印キーを使い始めたときなど）。形状は作り直さない。
func set_legend(key_legend: String, key_sub_legend: String = "") -> void:
	if key_legend == legend and key_sub_legend == sub_legend:
		return
	legend = key_legend
	sub_legend = key_sub_legend
	if _legend_label != null:
		_configure_legend()


func set_look(look: int) -> void:
	if look == _look:
		return
	if look == Look.DONE and _look != Look.DONE:
		_done_flash = DONE_FLASH_SECONDS
	_look = look
	_apply_look()


func get_look() -> int:
	return _look


## 実際のキー入力。チュートリアルが勝手に押す演出は持たない。
func set_pressed(pressed: bool) -> void:
	_pressed = pressed


func is_pressed() -> bool:
	return _pressed


func press_depth() -> float:
	return _depth


## 表示・非表示はポップで切り替える。透明度を使わないので描画順の破綻がない。
func set_shown(shown: bool, immediate: bool = false) -> void:
	_visible_target = shown
	if immediate:
		_pop = 1.0 if shown else 0.0
		_apply_pop()


func is_fully_hidden() -> bool:
	return not _visible_target and _pop <= 0.0


## キーの横幅（ローカル単位）。リグが隣のキーとの間隔を決めるのに使う。
func footprint_width() -> float:
	return width_units * PITCH


func advance(delta: float) -> void:
	_time += delta
	var target_depth := 1.0 if _pressed else 0.0
	_depth = move_toward(_depth, target_depth, delta * PRESS_SPEED)
	if _cap_pivot != null:
		_cap_pivot.position.y = -_depth * TRAVEL
	var pop_target := 1.0 if _visible_target else 0.0
	_pop = move_toward(_pop, pop_target, delta / POP_SECONDS)
	_apply_pop()
	_done_flash = maxf(0.0, _done_flash - delta)
	_animate_materials()


# ---------- 構築 ----------

func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	_plate_material = StandardMaterial3D.new()
	_plate_material.albedo_color = PLATE_COLOR
	_plate_material.roughness = 0.42
	_plate_material.metallic = 0.25
	_plate_material.emission_enabled = true
	_plate_material.emission = PLATE_COLOR.lightened(0.15)
	_plate_material.emission_energy_multiplier = 0.35

	_plate = MeshInstance3D.new()
	_plate.name = "Plate"
	_plate.mesh = _plate_mesh(width_units)
	_plate.material_override = _plate_material
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plate)

	_frame_material = StandardMaterial3D.new()
	_frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame_material.albedo_color = accent
	_frame = MeshInstance3D.new()
	_frame.name = "GlowFrame"
	_frame.mesh = _frame_mesh(width_units)
	_frame.material_override = _frame_material
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.position.y = 0.012
	add_child(_frame)

	_cap_pivot = Node3D.new()
	_cap_pivot.name = "CapPivot"
	add_child(_cap_pivot)

	_cap_material = StandardMaterial3D.new()
	_cap_material.roughness = 0.34
	_cap_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cap_material.emission_enabled = true
	_cap = MeshInstance3D.new()
	_cap.name = "Cap"
	_cap.mesh = _cap_mesh(width_units)
	_cap.material_override = _cap_material
	_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cap_pivot.add_child(_cap)

	_legend_label = Label3D.new()
	_legend_label.name = "Legend"
	_sub_label = Label3D.new()
	_sub_label.name = "SubLegend"
	for label: Label3D in [_legend_label, _sub_label]:
		label.font = LEGEND_FONT
		label.shaded = false
		label.double_sided = false
		label.render_priority = 2
		label.outline_size = 0
		# 天面（+Y）に寝かせ、文字の上方向を -Z に合わせる。
		label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		_cap_pivot.add_child(label)
	_configure_legend()

	_check = _build_check_mark()
	_cap_pivot.add_child(_check)


func _configure_legend() -> void:
	var top_y := CAP_HEIGHT + 0.006
	var text := legend
	var font_size := 128
	var target_height := 0.42
	if text.length() >= 3:
		# Space / Ctrl / Enter など長い刻印は幅に合わせて小さめにする。
		target_height = 0.27 if width_units < 2.0 else 0.30
	_legend_label.text = text
	_legend_label.font_size = font_size
	# Noto Sans JP の行高はフォントサイズの約1.45倍。見た目の文字高を合わせる。
	_legend_label.pixel_size = target_height / (float(font_size) * 1.05)
	_legend_label.position = Vector3(0.0, top_y, 0.02 if sub_legend.is_empty() else 0.07)
	_sub_label.visible = not sub_legend.is_empty()
	_sub_label.text = sub_legend
	_sub_label.font_size = 96
	_sub_label.pixel_size = 0.21 / (96.0 * 1.05)
	var half_top_depth := (PITCH - GAP) * 0.5 - SIDE_INSET - TOP_BEVEL
	_sub_label.position = Vector3(0.0, top_y, -half_top_depth + 0.10)


## 達成したキーの右上の角に載せる、緑の丸に白いチェックのバッジ。
func _build_check_mark() -> Node3D:
	var root := Node3D.new()
	root.name = "CheckMark"
	_check_material = StandardMaterial3D.new()
	_check_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_check_material.albedo_color = Color("1faa5c")
	var stroke_material := StandardMaterial3D.new()
	stroke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stroke_material.albedo_color = Color.WHITE
	var top_half_width := (width_units * PITCH - GAP) * 0.5 - SIDE_INSET
	var top_half_depth := (PITCH - GAP) * 0.5 - SIDE_INSET
	# 画面上の右上（+X・-Z）の角に少しはみ出して載せる。
	root.position = Vector3(top_half_width - 0.02, CAP_HEIGHT + 0.07, -top_half_depth + 0.02)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.19
	cylinder.bottom_radius = 0.19
	cylinder.height = 0.05
	cylinder.radial_segments = 28
	cylinder.rings = 1
	disc.mesh = cylinder
	disc.material_override = _check_material
	root.add_child(disc)
	var short_stroke := MeshInstance3D.new()
	var short_box := BoxMesh.new()
	short_box.size = Vector3(0.11, 0.03, 0.045)
	short_stroke.mesh = short_box
	short_stroke.material_override = stroke_material
	short_stroke.position = Vector3(-0.055, 0.035, 0.012)
	short_stroke.rotation = Vector3(0.0, -PI * 0.25, 0.0)
	root.add_child(short_stroke)
	var long_stroke := MeshInstance3D.new()
	var long_box := BoxMesh.new()
	long_box.size = Vector3(0.21, 0.03, 0.045)
	long_stroke.mesh = long_box
	long_stroke.material_override = stroke_material
	long_stroke.position = Vector3(0.035, 0.035, -0.03)
	long_stroke.rotation = Vector3(0.0, PI * 0.27, 0.0)
	root.add_child(long_stroke)
	for part: MeshInstance3D in [disc, short_stroke, long_stroke]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# ---------- 見た目 ----------

func _apply_look() -> void:
	if _cap_material == null:
		return
	var ink := DONE_INK if _look == Look.DONE else INK
	_legend_label.modulate = ink
	_sub_label.modulate = ink
	_check.visible = _look == Look.DONE
	_animate_materials()


func _base_cap_color() -> Color:
	match _look:
		Look.TARGET:
			# 日中の強い光でパステルに飛ばないよう、プレイヤー色の彩度を少し上げて沈める。
			return Color.from_hsv(accent.h, minf(1.0, accent.s * 1.18), accent.v * 0.93)
		Look.DONE:
			return DONE_COLOR
	return IVORY


func _animate_materials() -> void:
	if _cap_material == null:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 4.4)
	var flash := clampf(_done_flash / DONE_FLASH_SECONDS, 0.0, 1.0)
	# 夜のステージでも刻印が読めるよう、どの状態でも少しだけ自発光させる。
	var glow := 0.16
	match _look:
		Look.TARGET:
			glow = 0.16 + 0.22 * pulse
		Look.DONE:
			glow = 0.20 + 0.6 * flash
	# 実際に押している間は白っぽく光らせ、入力が届いたことをはっきり返す。
	var cap_color := _base_cap_color().lerp(PRESSED_COLOR, 0.45 * _depth)
	glow += 0.5 * _depth
	_cap_material.albedo_color = cap_color
	_cap_material.emission = cap_color
	_cap_material.emission_energy_multiplier = glow
	var frame_alpha := 0.0
	match _look:
		Look.TARGET:
			frame_alpha = 0.45 + 0.45 * pulse
		Look.DONE:
			frame_alpha = 0.55 * flash
	if _depth > 0.05:
		frame_alpha = maxf(frame_alpha, 0.95 * _depth)
	var frame_color := DONE_COLOR if _look == Look.DONE else accent
	_frame_material.albedo_color = Color(frame_color.r, frame_color.g, frame_color.b, frame_alpha)
	_frame.visible = frame_alpha > 0.01
	if _check.visible:
		_check.scale = Vector3.ONE * (1.0 + 0.35 * flash)


func _apply_pop() -> void:
	var eased := _ease_out_back(_pop)
	scale = Vector3.ONE * maxf(0.001, eased)
	visible = _pop > 0.0


static func _ease_out_back(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ---------- 形状生成 ----------

static func _cap_mesh(units: float) -> ArrayMesh:
	var key := snappedf(units, 0.01)
	if _cap_meshes.has(key):
		return _cap_meshes[key]
	var half_x := (units * PITCH - GAP) * 0.5
	var half_z := (PITCH - GAP) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings: Array[PackedVector3Array] = []
	# 裾から天面の縁まで。側面はわずかに膨らませ、成形品らしい丸みを出す。
	for i: int in range(SIDE_RINGS + 1):
		var t := float(i) / float(SIDE_RINGS)
		var inset := SIDE_INSET * (1.0 - pow(1.0 - t, 1.6))
		var y := (CAP_HEIGHT - TOP_BEVEL) * t
		rings.append(_rounded_ring(half_x - inset, half_z - inset, BOTTOM_RADIUS - inset * 0.25, y))
	# 天面の縁を四分円で丸める。
	for i: int in range(1, 4):
		var angle := PI * 0.5 * float(i) / 3.0
		var inset := SIDE_INSET + TOP_BEVEL * (1.0 - cos(angle))
		var y := CAP_HEIGHT - TOP_BEVEL + TOP_BEVEL * sin(angle)
		rings.append(_rounded_ring(half_x - inset, half_z - inset, BOTTOM_RADIUS - inset * 0.3, y))
	var edge_inset := SIDE_INSET + TOP_BEVEL
	var top_half_x := half_x - edge_inset
	var top_half_z := half_z - edge_inset
	var top_radius := maxf(0.03, BOTTOM_RADIUS - edge_inset * 0.3)
	# 横長キー（スペースなど）は皿の底も横長の線分にする。1uでは点になる。
	var center_half := maxf(0.0, top_half_x - top_half_z)
	# 皿状の天面。外周から中心へ同心の角丸リングを縮めながら沈める。
	# 最後のリングは線分（または点）へ潰れ、同じ帯の張り方のまま天面が閉じる。
	for i: int in range(1, DISH_RINGS + 1):
		var s := 1.0 - float(i) / float(DISH_RINGS)
		var y := CAP_HEIGHT - DISH_DEPTH * (1.0 - s * s)
		rings.append(_rounded_ring(
			lerpf(center_half, top_half_x, s), top_half_z * s, top_radius * s, y
		))
	_add_ring_strips(st, rings)
	st.generate_normals()
	var mesh := st.commit()
	_cap_meshes[key] = mesh
	return mesh


## 隣り合う輪を帯でつなぐ。どの輪も点数が同じで、外側から見て時計回り（Godot の表面）。
static func _add_ring_strips(st: SurfaceTool, rings: Array[PackedVector3Array]) -> void:
	for ring: PackedVector3Array in rings:
		for point: Vector3 in ring:
			st.add_vertex(point)
	var ring_size := rings[0].size()
	for r: int in range(rings.size() - 1):
		for j: int in range(ring_size):
			var a := r * ring_size + j
			var b := r * ring_size + (j + 1) % ring_size
			var c := (r + 1) * ring_size + (j + 1) % ring_size
			var d := (r + 1) * ring_size + j
			st.add_index(d)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(b)
			st.add_index(a)


static func _plate_mesh(units: float) -> ArrayMesh:
	var key := snappedf(units, 0.01)
	if _plate_meshes.has(key):
		return _plate_meshes[key]
	var half_x := (units * PITCH - GAP) * 0.5 + PLATE_MARGIN
	var half_z := (PITCH - GAP) * 0.5 + PLATE_MARGIN
	var radius := BOTTOM_RADIUS + PLATE_MARGIN * 0.6
	var bevel := 0.035
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var inner_half := maxf(0.0, (half_x - half_z))
	var rings: Array[PackedVector3Array] = [
		_rounded_ring(half_x, half_z, radius, -PLATE_THICKNESS),
		_rounded_ring(half_x, half_z, radius, -bevel),
		_rounded_ring(half_x - bevel * 0.3, half_z - bevel * 0.3, radius - bevel * 0.3, -bevel * 0.3),
		_rounded_ring(half_x - bevel, half_z - bevel, radius - bevel, 0.0),
		_rounded_ring(lerpf(inner_half, half_x - bevel, 0.5), (half_z - bevel) * 0.5, (radius - bevel) * 0.5, 0.0),
		_rounded_ring(inner_half, 0.0, 0.0, 0.0),
	]
	_add_ring_strips(st, rings)
	st.generate_normals()
	var mesh := st.commit()
	_plate_meshes[key] = mesh
	return mesh


## キャップの裾を囲む発光枠（平らな角丸の輪）。
static func _frame_mesh(units: float) -> ArrayMesh:
	var key := snappedf(units, 0.01)
	if _frame_meshes.has(key):
		return _frame_meshes[key]
	var half_x := (units * PITCH - GAP) * 0.5
	var half_z := (PITCH - GAP) * 0.5
	var outer := _rounded_ring(half_x + PLATE_MARGIN * 0.95, half_z + PLATE_MARGIN * 0.95, BOTTOM_RADIUS + PLATE_MARGIN * 0.6, 0.0)
	var inner := _rounded_ring(half_x + 0.005, half_z + 0.005, BOTTOM_RADIUS, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for point: Vector3 in outer:
		st.add_vertex(point)
	for point: Vector3 in inner:
		st.add_vertex(point)
	var ring_size := outer.size()
	for j: int in range(ring_size):
		var o0 := j
		var o1 := (j + 1) % ring_size
		var i0 := ring_size + j
		var i1 := ring_size + (j + 1) % ring_size
		st.add_index(i1)
		st.add_index(o1)
		st.add_index(o0)
		st.add_index(i1)
		st.add_index(o0)
		st.add_index(i0)
	var mesh := st.commit()
	_frame_meshes[key] = mesh
	return mesh


## 上（+Y）から見て反時計回りに並ぶ角丸長方形の輪郭（画面上方向を -Z とした見え方）。
static func _rounded_ring(half_x: float, half_z: float, radius: float, y: float) -> PackedVector3Array:
	var r := clampf(radius, 0.0, minf(half_x, half_z))
	var corners := [
		Vector2(half_x - r, half_z - r),
		Vector2(half_x - r, -(half_z - r)),
		Vector2(-(half_x - r), -(half_z - r)),
		Vector2(-(half_x - r), half_z - r),
	]
	var points := PackedVector3Array()
	for k: int in range(4):
		var center: Vector2 = corners[k]
		for s: int in range(CORNER_SEGMENTS):
			var angle := deg_to_rad(90.0 - 90.0 * float(k) - 90.0 * float(s) / float(CORNER_SEGMENTS - 1))
			points.append(Vector3(center.x + r * cos(angle), y, center.y + r * sin(angle)))
	return points
