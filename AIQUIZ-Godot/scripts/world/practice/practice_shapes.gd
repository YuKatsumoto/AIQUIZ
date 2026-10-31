extends RefCounted

## 練習の小物（看板の壁・床の印・的のマーク）の平らな絵を、テクスチャを使わずに多角形のメッシュで描く道具。
## preload して使う（class_name なし）：
##   const Shapes = preload("res://scripts/world/practice/practice_shapes.gd")
## 絵の座標は (u, v)。Face.WALL：見る人（−z 側）から見て u が右・v が上（x = −u、y = v、z = 0）。
## Face.FLOOR：u = x、v = z（y = 0）。どちらの面も裏表なしで描く（材質の cull を切る）。

enum Face { WALL, FLOOR }

const BOLD_FONT: FontFile = preload("res://resources/fonts/NotoSansJP-Bold.otf")
## 遠くでも輪郭がにじまないよう、クイズ壁の文字と同じく MSDF で描く（QuizWall._wall_label_font と同じ作り方）。
const MSDF_SIZE := 64
const MSDF_PIXEL_RANGE := 16

static var _font: FontFile = null
static var _materials := {}


## 絵の座標の点を、面の空間の点へ。
static func to_3d(point: Vector2, plane: Face = Face.WALL) -> Vector3:
	if plane == Face.FLOOR:
		return Vector3(point.x, 0.0, point.y)
	return Vector3(-point.x, point.y, 0.0)


## 平らな多角形のメッシュ（凹んだ形でもよい。辺どうしが交わらないこと）。colors は点ごとの色（なくてよい）。
static func polygon_mesh(points: PackedVector2Array, plane: Face = Face.WALL,
		colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		push_warning("PracticeShapes: polygon could not be triangulated (%d points)" % points.size())
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var normal := Vector3.UP if plane == Face.FLOOR else Vector3.FORWARD
	for point: Vector2 in points:
		vertices.append(to_3d(point, plane))
		normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if colors.size() == points.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 太い折れ線（波線など）。両はしは丸める。
static func polyline_mesh(points: PackedVector2Array, width: float, plane: Face = Face.WALL) -> ArrayMesh:
	var half := width * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i: int in range(points.size()):
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var along := (next - prev).normalized()
		var side := Vector2(-along.y, along.x) * half
		left.append(points[i] + side)
		right.append(points[i] - side)
	for i: int in range(points.size() - 1):
		_add_quad(tool, to_3d(left[i], plane), to_3d(left[i + 1], plane), to_3d(right[i + 1], plane), to_3d(right[i], plane))
	for end: Vector2 in [points[0], points[points.size() - 1]]:
		var cap := circle(half, 16, end)
		for i: int in range(cap.size()):
			tool.add_vertex(to_3d(end, plane))
			tool.add_vertex(to_3d(cap[i], plane))
			tool.add_vertex(to_3d(cap[(i + 1) % cap.size()], plane))
	return tool.commit()


## 輪（inner〜outer の帯）。
static func ring_mesh(inner: float, outer: float, steps: int = 48, plane: Face = Face.WALL,
		center: Vector2 = Vector2.ZERO) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(steps):
		var a0 := TAU * float(i) / steps
		var a1 := TAU * float(i + 1) / steps
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		_add_quad(tool, to_3d(center + d0 * inner, plane), to_3d(center + d1 * inner, plane),
			to_3d(center + d1 * outer, plane), to_3d(center + d0 * outer, plane))
	return tool.commit()


static func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		tool.add_vertex(point)


## 円（多角形の点）。
static func circle(radius: float, steps: int = 40, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(steps):
		var angle := TAU * float(i) / steps
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## 楕円（多角形の点）。angle で回す。
static func ellipse(radii: Vector2, steps: int = 32, center: Vector2 = Vector2.ZERO, angle: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(steps):
		var a := TAU * float(i) / steps
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(angle))
	return points


## 星（多角形の点）。spikes 本のとがりで、とがりの先が outer、谷が inner。angle 0 で1本目が +v を向く。
static func star(outer: float, inner: float, spikes: int = 4, center: Vector2 = Vector2.ZERO, angle: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(spikes * 2):
		var a := PI * 0.5 + angle + PI * float(i) / spikes
		var r := outer if i % 2 == 0 else inner
		points.append(center + Vector2(cos(a), sin(a)) * r)
	return points


## 角の丸い長方形（多角形の点）。
static func rounded_rect(size: Vector2, radius: float, center: Vector2 = Vector2.ZERO, corner_steps: int = 6) -> PackedVector2Array:
	var r := clampf(radius, 0.001, minf(size.x, size.y) * 0.5 - 0.001)
	var inner := size * 0.5 - Vector2(r, r)
	var corners := [Vector2(inner.x, inner.y), Vector2(-inner.x, inner.y), Vector2(-inner.x, -inner.y), Vector2(inner.x, -inner.y)]
	var points := PackedVector2Array()
	for i: int in range(4):
		for step: int in range(corner_steps + 1):
			var angle := PI * 0.5 * (i + float(step) / corner_steps)
			points.append(center + (corners[i] as Vector2) + Vector2(cos(angle), sin(angle)) * r)
	return points


## 太い矢印（多角形の点）。angle 0 で +u を向く。center は矢印の長さの真ん中。
static func arrow_polygon(length: float, shaft_width: float, head_width: float, head_length: float,
		angle: float = 0.0, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var tail := -length * 0.5
	var neck := length * 0.5 - head_length
	var tip := length * 0.5
	var shape := [
		Vector2(tail, -shaft_width * 0.5), Vector2(neck, -shaft_width * 0.5), Vector2(neck, -head_width * 0.5),
		Vector2(tip, 0.0), Vector2(neck, head_width * 0.5), Vector2(neck, shaft_width * 0.5), Vector2(tail, shaft_width * 0.5),
	]
	var points := PackedVector2Array()
	for point: Vector2 in shape:
		points.append(center + point.rotated(angle))
	return points


## 2次ベジェ曲線の点（start を含まず、end を含む steps 個）。
static func bezier(start: Vector2, control: Vector2, end: Vector2, steps: int = 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(1, steps + 1):
		var t := float(i) / steps
		points.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
	return points


## 光の当たり方に左右されない色の材質（看板の絵・床の印）。unique でなければ同じ設定どうしで共有する。
static func flat_material(color: Color, transparent: bool = false, additive: bool = false,
		priority: int = 0, vertex_colors: bool = false, unique: bool = false) -> StandardMaterial3D:
	var key := "%s_%s_%s_%d_%s" % [color.to_html(), transparent, additive, priority, vertex_colors]
	if not unique and _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.disable_receive_shadows = true
	if transparent or additive:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.render_priority = priority
	material.vertex_color_use_as_albedo = vertex_colors
	if not unique:
		_materials[key] = material
	return material


## 平らなメッシュを1つ置く。
static func add_mesh(parent: Node3D, mesh: Mesh, material: Material, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = offset
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(node)
	return node


static func msdf_font() -> FontFile:
	if _font == null:
		_font = FontFile.new()
		_font.data = BOLD_FONT.data
		_font.multichannel_signed_distance_field = true
		_font.msdf_size = MSDF_SIZE
		_font.msdf_pixel_range = MSDF_PIXEL_RANGE
		_font.generate_mipmaps = true
		_font.allow_system_fallback = BOLD_FONT.allow_system_fallback
	return _font


## 壁の面に貼る文字（−z 側から読める。真ん中がこのノードの位置）。高さ em（m）は font_size × pixel_size。
static func wall_label(text: String, font_size: int, pixel_size: float, color: Color,
		outline_color: Color = Color(0, 0, 0, 0), outline: int = 0) -> Label3D:
	var label := Label3D.new()
	label.font = msdf_font()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = outline_color
	label.outline_size = outline
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.render_priority = 20
	label.outline_render_priority = 19
	label.rotation.y = PI
	return label
