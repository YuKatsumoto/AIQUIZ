class_name PracticeFloorMarks
extends Node3D

## 練習の床の印（docs/new_tutorial/phase4_design.md 3.2、台本①の 1-6・1.5・1.6）。監督が world の子にして1つ置く（位置は原点のまま）。
## 座標はゲーム画面のもの（x は +が画面の左、z はコンベア上の前）。印は床の面（StageConstants.FLOOR_TOP_Y）のすぐ上に描き、
## プレイヤーの体より下に見える。コンベアが動いても印は動かない（床の端と同じく舞台に固定）。
##
##   show_edge_glow(sides)：床の端（&"left" x = +12・&"right" x = −12・&"back" z = −12.5）が赤く脈打つ
##   show_zones(zones) / flash_zone(index)：黄色い半透明の帯（Rect2：x の範囲、z の範囲）と、ピコンのときの光
##   show_arrow(from, to_x) / hide_arrow()：床の (x, z) から、x = to_x のドアのほうへ向く脈打つ矢印
##   flash_fence(point)：見えないさくにさわった所が、うっすら光って消える（0.5秒）
##   clear_all() / make_target_mark()・attach_target_mark(wall)：壁の的のマーク

const Shapes = preload("res://scripts/world/practice/practice_shapes.gd")

const FLOOR_Y := StageConstants.FLOOR_TOP_Y
## 床の面から印までの高さ（床のしま模様とちらつかない高さ）
const MARK_LIFT := 0.035
const HALF_WIDTH := StageConstants.FLOOR_HALF_WIDTH
const BACK_Z := StageConstants.FLOOR_BACK_Z
## 端の光：床に描く幅、端に立てる光の幕の高さ、前の端（遠くは薄くする）
const EDGE_BAND_WIDTH := 1.0
const EDGE_CURTAIN_HEIGHT := 0.9
## 左右のレール（ConveyorRails：中心 x = ±11.86、頭の上面は床から 0.26 m、幅 0.16 m）
const RAIL_X := 11.86
const RAIL_TOP := 0.26
const RAIL_HALF := 0.1
const EDGE_FRONT_Z := 70.0
const FADE_START_Z := 24.0
const FADE_END_Z := 66.0
const EDGE_PULSE_HZ := 1.3
## ゾーンの縁の太さと、光が消えるまで
const ZONE_BORDER := 0.1
const ZONE_FLASH_SECONDS := 0.45
## 矢印：from から少し前で始める（体に隠れないように）。太さ・頭の大きさ。前へ伸ばす長さは
## 「横のずれ × ARROW_FORWARD_PER_SIDE ＋ ARROW_FORWARD_BASE」を MIN〜MAX に収めたもの（ドアのほうへ斜めに向く）
const ARROW_START_OFFSET := 0.6
const ARROW_SHAFT := 0.62
const ARROW_HEAD_WIDTH := 1.8
const ARROW_HEAD_LENGTH := 1.4
const ARROW_FORWARD_BASE := 2.0
const ARROW_FORWARD_PER_SIDE := 1.6
const ARROW_MIN_FORWARD := 4.0
const ARROW_MAX_FORWARD := 8.0
const ARROW_CHEVRON_SPACING := 1.1
const ARROW_CHEVRON_SPEED := 2.4
## さくの光：大きさ、体の外へ出す距離、消えるまで、近い所で続けて光るときはまとめる
const FENCE_SIZE := Vector2(2.4, 2.2)
const FENCE_OUTSET := 0.4
const FENCE_SECONDS := 0.5
const FENCE_MERGE_DISTANCE := 0.8
## 的のマーク（クイズ壁の空間。2択のドアの間の柱の前面 z = −0.55 のすぐ前、床 −1.2 と ドアの上端 2.38 の真ん中）
const TARGET_MARK_POSITION := Vector3(0.0, 0.59, -0.58)
const TARGET_RADIUS := 1.25

const EDGE_COLOR := Color(1.0, 0.13, 0.10)
const ZONE_COLOR := Color(1.0, 0.85, 0.08)
const ARROW_COLOR := Color(0.16, 0.92, 0.32)
const ARROW_EDGE_COLOR := Color(0.02, 0.24, 0.10)
const FENCE_COLOR := Color(0.55, 0.88, 1.0)

const FENCE_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 tint : source_color = vec4(0.55, 0.88, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float soft = 1.0 - smoothstep(0.35, 1.0, length(c * vec2(1.0, 1.15)));
	float grid = max(smoothstep(0.86, 1.0, abs(sin(UV.x * 22.0))), smoothstep(0.86, 1.0, abs(sin(UV.y * 18.0))));
	ALBEDO = tint.rgb * (0.35 + 0.9 * grid) * soft * strength;
	ALPHA = clamp(soft * strength, 0.0, 1.0);
}
"""

static var _fence_shader: Shader = null

var _clock := 0.0
## 端の光：sides の名前 → 部品（Node3D）。材質は共有して脈打たせる
var _edges := {}
var _edge_band_material: StandardMaterial3D = null
var _edge_curtain_material: StandardMaterial3D = null
var _edge_rail_material: StandardMaterial3D = null
## ゾーン：{root, fill: StandardMaterial3D, border: StandardMaterial3D, flash}
var _zones: Array[Dictionary] = []
var _arrow: Node3D = null
var _arrow_length := 0.0
var _arrow_materials: Array[StandardMaterial3D] = []
var _chevrons: Array[MeshInstance3D] = []
## さくの光：{node, material: ShaderMaterial, age, point}
var _fences: Array[Dictionary] = []


func _init() -> void:
	# ゲーム画面は止めている間も動く（PROCESS_MODE_ALWAYS）ので、印はポーズで止める。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "PracticeFloorMarks"


# ---------- 端の光 ----------

## 床の端を赤く脈打たせる。sides は &"left"（x = +12、画面の左）・&"right"（x = −12）・&"back"（z = −12.5）。
## 渡さなかった端は消す（空の配列で全部消える）。
func show_edge_glow(sides: Array) -> void:
	_ensure_edge_materials()
	var wanted: Array[StringName] = []
	for side: Variant in sides:
		wanted.append(StringName(side))
	for side: StringName in [&"left", &"right", &"back"]:
		var on := side in wanted
		if on and not _edges.has(side):
			_edges[side] = _build_edge(side)
		if _edges.has(side):
			(_edges[side] as Node3D).visible = on
	for side: StringName in wanted:
		if side not in [&"left", &"right", &"back"]:
			push_warning("PracticeFloorMarks: unknown edge %s" % side)


func _ensure_edge_materials() -> void:
	if _edge_band_material != null:
		return
	# ゾーン（黄色）と重なっても赤が上に見えるよう、ゾーンより後に描く
	_edge_band_material = Shapes.flat_material(EDGE_COLOR, true, false, 5, true, true)
	_edge_curtain_material = Shapes.flat_material(EDGE_COLOR, true, false, 6, true, true)
	_edge_rail_material = Shapes.flat_material(EDGE_COLOR, true, false, 6, true, true)


func _build_edge(side: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Edge_%s" % side
	add_child(root)
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curtain := SurfaceTool.new()
	curtain.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := FLOOR_Y + MARK_LIFT
	if side == &"back":
		# うしろの端：x = −12〜+12、z = −12.5 から内側へ
		var outer := BACK_Z + 0.02
		var inner := BACK_Z + EDGE_BAND_WIDTH
		_strip(band, Vector3(-HALF_WIDTH, y, outer), Vector3(HALF_WIDTH, y, outer), Vector3(HALF_WIDTH, y, inner), Vector3(-HALF_WIDTH, y, inner), 1.0, 1.0, 0.0, 0.0)
		_strip(curtain, Vector3(-HALF_WIDTH, FLOOR_Y, outer), Vector3(HALF_WIDTH, FLOOR_Y, outer),
			Vector3(HALF_WIDTH, FLOOR_Y + EDGE_CURTAIN_HEIGHT, outer), Vector3(-HALF_WIDTH, FLOOR_Y + EDGE_CURTAIN_HEIGHT, outer), 1.0, 1.0, 0.0, 0.0)
	else:
		# 左右の端：レール（x = ±11.86）の外まで。遠くは薄くする
		var sign_x := 1.0 if side == &"left" else -1.0
		var outer_x := sign_x * (HALF_WIDTH - 0.02)
		var inner_x := sign_x * (HALF_WIDTH - EDGE_BAND_WIDTH)
		var z := BACK_Z
		while z < EDGE_FRONT_Z - 0.01:
			var z2 := minf(z + 4.0, EDGE_FRONT_Z)
			var f1 := _far_fade(z)
			var f2 := _far_fade(z2)
			_strip(band, Vector3(outer_x, y, z), Vector3(outer_x, y, z2), Vector3(inner_x, y, z2), Vector3(inner_x, y, z), f1, f2, 0.0, 0.0)
			_strip(curtain, Vector3(outer_x, FLOOR_Y, z), Vector3(outer_x, FLOOR_Y, z2),
				Vector3(outer_x, FLOOR_Y + EDGE_CURTAIN_HEIGHT, z2), Vector3(outer_x, FLOOR_Y + EDGE_CURTAIN_HEIGHT, z), f1, f2, 0.0, 0.0)
			# レールの頭（上の面と内側の面）を赤くする
			var top := FLOOR_Y + RAIL_TOP + 0.012
			var near_x := sign_x * (RAIL_X - RAIL_HALF)
			var far_x := sign_x * (RAIL_X + RAIL_HALF)
			_strip(rail, Vector3(near_x, top, z), Vector3(near_x, top, z2), Vector3(far_x, top, z2), Vector3(far_x, top, z), f1, f2, f2, f1)
			_strip(rail, Vector3(near_x, top, z), Vector3(near_x, top, z2), Vector3(near_x, top - 0.13, z2), Vector3(near_x, top - 0.13, z), f1, f2, f2, f1)
			z = z2
	Shapes.add_mesh(root, band.commit(), _edge_band_material)
	Shapes.add_mesh(root, curtain.commit(), _edge_curtain_material)
	if side != &"back":
		Shapes.add_mesh(root, rail.commit(), _edge_rail_material)
	return root


## 4つの角に白の濃さ（頂点の色のアルファ）を付けた四角。
func _strip(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ka: float, kb: float, kc: float, kd: float) -> void:
	var points := [a, b, c, a, c, d]
	var alphas := [ka, kb, kc, ka, kc, kd]
	for i: int in range(6):
		tool.set_color(Color(1.0, 1.0, 1.0, alphas[i]))
		tool.add_vertex(points[i])


## 遠く（z が大きい所）を薄くする割合。
func _far_fade(z: float) -> float:
	return 1.0 - smoothstep(FADE_START_Z, FADE_END_Z, z)


# ---------- ギリギリ ゾーン ----------

## 黄色い半透明の帯を出す（前に出していた帯は消す）。各 Rect2 は position = (x の小さいほう, z の小さいほう)、size = (幅, 奥行き)。
func show_zones(zones: Array) -> void:
	for zone: Dictionary in _zones:
		(zone.root as Node3D).queue_free()
	_zones.clear()
	for value: Variant in zones:
		if not value is Rect2:
			push_warning("PracticeFloorMarks: zone %s is not a Rect2" % [value])
			continue
		_zones.append(_build_zone((value as Rect2).abs()))


## そのゾーンを一瞬明るくする（ピコンのとき）。
func flash_zone(index: int) -> void:
	if index >= 0 and index < _zones.size():
		_zones[index].flash = 1.0


func _build_zone(rect: Rect2) -> Dictionary:
	var root := Node3D.new()
	root.name = "Zone%d" % _zones.size()
	add_child(root)
	var fill_material := Shapes.flat_material(ZONE_COLOR, true, false, 3, true, true)
	var border_material := Shapes.flat_material(ZONE_COLOR, true, false, 4, true, true)
	var y := FLOOR_Y + MARK_LIFT + 0.004
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var border := SurfaceTool.new()
	border.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z := rect.position.y
	while z < rect.end.y - 0.001:
		var z2 := minf(z + 4.0, rect.end.y)
		var f1 := _far_fade(z)
		var f2 := _far_fade(z2)
		_strip(fill, Vector3(x0, y, z), Vector3(x1, y, z), Vector3(x1, y, z2), Vector3(x0, y, z2), f1, f1, f2, f2)
		# 縁（x の両側）
		for edge_x: float in [x0, x1 - ZONE_BORDER]:
			_strip(border, Vector3(edge_x, y + 0.002, z), Vector3(edge_x + ZONE_BORDER, y + 0.002, z),
				Vector3(edge_x + ZONE_BORDER, y + 0.002, z2), Vector3(edge_x, y + 0.002, z2), f1, f1, f2, f2)
		z = z2
	# 縁（z の両はし）
	for edge_z: float in [rect.position.y, rect.end.y - ZONE_BORDER]:
		var f := _far_fade(edge_z)
		_strip(border, Vector3(x0, y + 0.002, edge_z), Vector3(x1, y + 0.002, edge_z),
			Vector3(x1, y + 0.002, edge_z + ZONE_BORDER), Vector3(x0, y + 0.002, edge_z + ZONE_BORDER), f, f, f, f)
	Shapes.add_mesh(root, fill.commit(), fill_material)
	Shapes.add_mesh(root, border.commit(), border_material)
	return {"root": root, "fill": fill_material, "border": border_material, "flash": 0.0, "rect": rect}


# ---------- 矢印 ----------

## from（x, z）の床から、x = to_x のドアのほうへ向く矢印を出す（前の矢印は消す）。脈打ち、光の山が先へ流れる。
## 矢印は from から ARROW_START_OFFSET だけ前で始まり、前へ ARROW_MIN_FORWARD〜ARROW_MAX_FORWARD m 伸びる。
func show_arrow(from: Vector2, to_x: float) -> void:
	hide_arrow()
	var forward := clampf(absf(to_x - from.x) * ARROW_FORWARD_PER_SIDE + ARROW_FORWARD_BASE, ARROW_MIN_FORWARD, ARROW_MAX_FORWARD)
	var end := Vector2(to_x, from.y + forward)
	var direction := (end - from).normalized()
	var start := from + direction * ARROW_START_OFFSET
	_arrow_length = start.distance_to(end)
	_arrow = Node3D.new()
	_arrow.name = "Arrow"
	_arrow.position = Vector3(start.x, FLOOR_Y + MARK_LIFT + 0.01, start.y)
	# 矢印の空間：+z が向き（絵の座標の u = x、v = z で、+v 向きに描く）
	_arrow.rotation.y = atan2(direction.x, direction.y)
	add_child(_arrow)
	var center := Vector2(0.0, _arrow_length * 0.5)
	var outline := _arrow_points(_arrow_length + 0.3, ARROW_SHAFT + 0.24, ARROW_HEAD_WIDTH + 0.36, ARROW_HEAD_LENGTH + 0.2, center + Vector2(0.0, 0.02))
	var body := _arrow_points(_arrow_length, ARROW_SHAFT, ARROW_HEAD_WIDTH, ARROW_HEAD_LENGTH, center)
	_arrow_materials = [
		Shapes.flat_material(ARROW_EDGE_COLOR, true, false, 5, false, true),
		Shapes.flat_material(ARROW_COLOR, true, false, 6, false, true),
	]
	Shapes.add_mesh(_arrow, Shapes.polygon_mesh(outline, Shapes.Face.FLOOR), _arrow_materials[0])
	Shapes.add_mesh(_arrow, Shapes.polygon_mesh(body, Shapes.Face.FLOOR), _arrow_materials[1], Vector3(0.0, 0.004, 0.0))
	var chevron_mesh := Shapes.polygon_mesh(_chevron_points(), Shapes.Face.FLOOR)
	var chevron_material := Shapes.flat_material(Color(1.0, 1.0, 1.0, 0.9), true, false, 7)
	_chevrons.clear()
	var count := maxi(1, int((_arrow_length - ARROW_HEAD_LENGTH) / ARROW_CHEVRON_SPACING))
	for i: int in range(count):
		_chevrons.append(Shapes.add_mesh(_arrow, chevron_mesh, chevron_material, Vector3(0.0, 0.008, 0.0)))
	_update_arrow()


func hide_arrow() -> void:
	if _arrow != null:
		_arrow.queue_free()
	_arrow = null
	_chevrons.clear()
	_arrow_materials.clear()


func has_arrow() -> bool:
	return _arrow != null


## +v 向きの矢印（絵の座標）。
func _arrow_points(length: float, shaft: float, head_width: float, head_length: float, center: Vector2) -> PackedVector2Array:
	return Shapes.arrow_polygon(length, shaft, head_width, head_length, PI * 0.5, center)


## 矢印の中を流れる「く」の字（+v 向き）。
func _chevron_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.24, -0.12), Vector2(0.0, 0.12), Vector2(0.24, -0.12),
		Vector2(0.24, -0.3), Vector2(0.0, -0.06), Vector2(-0.24, -0.3),
	])


func _update_arrow() -> void:
	if _arrow == null:
		return
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 1.6)
	(_arrow_materials[1] as StandardMaterial3D).albedo_color = Color(ARROW_COLOR.lerp(Color(0.75, 1.0, 0.75), 0.35 * pulse), 0.9 + 0.1 * pulse)
	(_arrow_materials[0] as StandardMaterial3D).albedo_color = Color(ARROW_EDGE_COLOR, 0.7 + 0.2 * pulse)
	var run := _arrow_length - ARROW_HEAD_LENGTH - 0.3
	for i: int in range(_chevrons.size()):
		var along := fmod(_clock * ARROW_CHEVRON_SPEED + i * ARROW_CHEVRON_SPACING, maxf(run, 0.1)) + 0.3
		var chevron := _chevrons[i]
		chevron.position.z = along
		# 両はしで薄くする
		var edge := minf(along - 0.3, run + 0.3 - along)
		chevron.transparency = 1.0 - clampf(edge / 0.5, 0.0, 1.0)


# ---------- 見えない さく ----------

## 見えないさくにさわった所（point の x・z。高さは見ない）が、うっすら光って消える（FENCE_SECONDS）。
## さくの面の光（格子）・床の上のさくの線・カメラを向いて広がる輪の3つ。横のさくは遊ぶカメラから真横に見えて
## 面の光がほとんど映らないので、床の線と輪で分かるようにする。
## normal はさくの外向き（+x・−x・+z・−z）。渡さなければ point から決める（|x| が 9 より大きければ横のさく、
## そうでなければ前（z > 0）かうしろのさく）。同じ所で続けて呼んだときは、光をつなげる（さわり続けても増えない）。
func flash_fence(point: Vector3, normal: Vector3 = Vector3.ZERO) -> void:
	if normal == Vector3.ZERO:
		if absf(point.x) > 9.0:
			normal = Vector3(signf(point.x), 0.0, 0.0)
		else:
			normal = Vector3(0.0, 0.0, 1.0 if point.z > 0.0 else -1.0)
	normal = normal.normalized()
	var at := Vector3(point.x, FLOOR_Y, point.z) + normal * FENCE_OUTSET
	for fence: Dictionary in _fences:
		if (fence.point as Vector3).distance_to(at) < FENCE_MERGE_DISTANCE:
			fence.age = minf(float(fence.age), 0.06)
			(fence.node as Node3D).position = at
			fence.point = at
			return
	if _fence_shader == null:
		_fence_shader = Shader.new()
		_fence_shader.code = FENCE_SHADER_CODE
	var node := Node3D.new()
	node.name = "FenceFlash"
	node.position = at
	# この印の空間：+z が さくの外向き、x が さくに沿う向き
	node.rotation.y = atan2(normal.x, normal.z)
	add_child(node)
	var wall := ShaderMaterial.new()
	wall.shader = _fence_shader
	wall.set_shader_parameter("tint", FENCE_COLOR)
	wall.render_priority = 8
	var quad := QuadMesh.new()
	quad.size = FENCE_SIZE
	Shapes.add_mesh(node, quad, wall, Vector3(0.0, FENCE_SIZE.y * 0.5, 0.0))
	# 床の上のさくの線（両はしは薄く）
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := FENCE_SIZE.x * 0.6
	var y := MARK_LIFT + 0.02
	for piece: int in range(4):
		var x0 := -half + half * 2.0 * piece / 4.0
		var x1 := -half + half * 2.0 * (piece + 1) / 4.0
		var k0 := sin(PI * piece / 4.0)
		var k1 := sin(PI * (piece + 1) / 4.0)
		_strip(line, Vector3(x0, y, -0.09), Vector3(x1, y, -0.09), Vector3(x1, y, 0.09), Vector3(x0, y, 0.09), k0, k1, k1, k0)
	var line_material := Shapes.flat_material(FENCE_COLOR, true, true, 8, true, true)
	Shapes.add_mesh(node, line.commit(), line_material)
	# 体の横で広がる輪（いつもカメラを向く）
	var ring_material := Shapes.flat_material(FENCE_COLOR, true, true, 9, false, true)
	ring_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ring_material.billboard_keep_scale = true
	var ring := Shapes.add_mesh(node, Shapes.ring_mesh(0.86, 1.0, 40), ring_material, Vector3(0.0, 1.0, 0.0))
	_fences.append({"node": node, "materials": [wall, line_material, ring_material], "ring": ring, "age": 0.0, "point": at})


# ---------- 全部 ----------

func clear_all() -> void:
	show_edge_glow([])
	show_zones([])
	hide_arrow()
	for fence: Dictionary in _fences:
		(fence.node as Node3D).queue_free()
	_fences.clear()


func _process(delta: float) -> void:
	_clock += delta
	if _edge_band_material != null:
		var pulse := 0.5 + 0.5 * sin(_clock * TAU * EDGE_PULSE_HZ)
		_edge_band_material.albedo_color = Color(EDGE_COLOR, 0.55 + 0.4 * pulse)
		_edge_curtain_material.albedo_color = Color(EDGE_COLOR, 0.3 + 0.45 * pulse)
		_edge_rail_material.albedo_color = Color(EDGE_COLOR.lerp(Color(1.0, 0.6, 0.5), 0.35 * pulse), 0.75 + 0.25 * pulse)
	for zone: Dictionary in _zones:
		var flash: float = zone.flash
		if flash > 0.0:
			flash = maxf(flash - delta / ZONE_FLASH_SECONDS, 0.0)
			zone.flash = flash
		(zone.fill as StandardMaterial3D).albedo_color = Color(ZONE_COLOR.lerp(Color(1.0, 1.0, 0.85), flash * 0.6), 0.3 + 0.5 * flash)
		(zone.border as StandardMaterial3D).albedo_color = Color(ZONE_COLOR.lerp(Color.WHITE, flash * 0.6), 0.9)
	_update_arrow()
	for i: int in range(_fences.size() - 1, -1, -1):
		var fence: Dictionary = _fences[i]
		fence.age = float(fence.age) + delta
		var k := clampf(1.0 - float(fence.age) / FENCE_SECONDS, 0.0, 1.0)
		# さっと光って、ゆっくり消える
		var rise := clampf(float(fence.age) / 0.06, 0.0, 1.0)
		var strength := rise * k * k
		var materials: Array = fence.materials
		(materials[0] as ShaderMaterial).set_shader_parameter("strength", 0.85 * strength)
		(materials[1] as StandardMaterial3D).albedo_color = Color(FENCE_COLOR, 0.9 * strength)
		(materials[2] as StandardMaterial3D).albedo_color = Color(FENCE_COLOR, 0.8 * strength)
		(fence.ring as Node3D).scale = Vector3.ONE * lerpf(0.3, 0.95, 1.0 - k * k)
		if k <= 0.0:
			(fence.node as Node3D).queue_free()
			_fences.remove_at(i)


# ---------- 的のマーク ----------

## 的のマーク（赤と白の輪。中心が原点、前は −z、直径 2.5 m）。監督が壁のノードの子にする（attach_target_mark も使える）。
static func make_target_mark() -> Node3D:
	var mark := TargetMark.new()
	mark.build()
	return mark


## 的のマークを、クイズ壁（wall：ゲーム画面の壁のノード）の2つのドアの間の柱の前に付けて返す（wall が null なら null）。
static func attach_target_mark(wall: Node3D) -> Node3D:
	if wall == null:
		return null
	var mark := make_target_mark()
	mark.position = TARGET_MARK_POSITION
	wall.add_child(mark)
	return mark


## 的のマーク：外の黒い縁、赤・白・赤・白・赤の輪、外側で脈打つ光の輪。
class TargetMark extends Node3D:
	const RED := Color(0.93, 0.15, 0.13)
	const WHITE := Color(0.98, 0.98, 0.98)
	const STEP := 0.012
	var _glow: StandardMaterial3D = null
	var _glow_node: MeshInstance3D = null
	var _clock := 0.0

	func _init() -> void:
		name = "TargetMark"
		process_mode = Node.PROCESS_MODE_PAUSABLE

	func build() -> void:
		var r := TARGET_RADIUS
		Shapes.add_mesh(self, Shapes.polygon_mesh(Shapes.circle(r + 0.08, 56)), Shapes.flat_material(Color(0.06, 0.08, 0.14)))
		var radii := [r, r * 0.78, r * 0.56, r * 0.36, r * 0.17]
		for i: int in range(radii.size()):
			var color := RED if i % 2 == 0 else WHITE
			Shapes.add_mesh(self, Shapes.polygon_mesh(Shapes.circle(radii[i], 56)), Shapes.flat_material(color),
				Vector3(0.0, 0.0, -STEP * (i + 1)))
		_glow = Shapes.flat_material(Color(1.0, 0.35, 0.25, 0.6), true, true, 9, false, true)
		_glow_node = Shapes.add_mesh(self, Shapes.ring_mesh(r + 0.08, r + 0.42, 56), _glow, Vector3(0.0, 0.0, -STEP))

	func _process(delta: float) -> void:
		_clock += delta
		var pulse := 0.5 + 0.5 * sin(_clock * TAU * 1.4)
		_glow.albedo_color = Color(1.0, 0.35, 0.25, 0.25 + 0.55 * pulse)
		_glow_node.scale = Vector3.ONE * (1.0 + 0.06 * pulse)
