extends RefCounted
class_name PlayerBadgePaint

## 「P1」「P2」のカプセル型バッジを、そのプレイヤーのキャラの 頭・胴・足 の3色の縦グラデーションでぬる。
## 勝利画面（ResultFinaleHud）とサドンデスの呼び出し・ゲージ（SuddenDeathHud）で使う。

const INK := Color(0.043, 0.071, 0.125)
const ROUND_SEGMENTS := 10


## 上から 頭・胴・足 の色。試合で見えていた見た目を使う（ローカル2人対戦なら頭は標準色）。
static func colors_for(state: QuizGameState, slot: int) -> Array[Color]:
	var skin := PlayerSkin.resolve(state.get_display_skin(slot) if state != null else {}, slot)
	var legs := PlayerSkin.part_color(skin, &"l_leg").lerp(PlayerSkin.part_color(skin, &"r_leg"), 0.5)
	var colors: Array[Color] = [PlayerSkin.part_color(skin, PlayerSkin.HEAD), PlayerSkin.part_color(skin, &"chest"), legs]
	return colors


## バッジの文字色。文字が載る真ん中（胴）を重く見て、明るければ紺、暗ければ白。
static func ink_for(colors: Array[Color]) -> Color:
	if colors.size() < 3:
		return INK
	var luminance := colors[0].get_luminance() * 0.2 + colors[1].get_luminance() * 0.6 + colors[2].get_luminance() * 0.2
	return INK if luminance > 0.45 else Color(1, 1, 1)


## 角丸の矩形を、上から colors の順の縦グラデーションでぬる（ふちは呼ぶ側が上に描く）。
## 色の切りかわる高さで横に切り、帯ごとに直線のグラデーションにするので、真ん中の色がちょうど中央に来る。
static func fill_rounded_gradient(item: CanvasItem, rect: Rect2, radius: float, colors: Array[Color], alpha: float = 1.0) -> void:
	if colors.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if colors.size() == 1:
		colors = [colors[0], colors[0]]
	var outline := rounded_points(rect, radius)
	var bands := colors.size() - 1
	for band: int in range(bands):
		var y0 := rect.position.y + rect.size.y * float(band) / float(bands)
		var y1 := rect.position.y + rect.size.y * float(band + 1) / float(bands)
		var strip := PackedVector2Array([
			Vector2(rect.position.x - 1.0, y0), Vector2(rect.end.x + 1.0, y0),
			Vector2(rect.end.x + 1.0, y1), Vector2(rect.position.x - 1.0, y1),
		])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(outline, strip):
			var piece_colors := PackedColorArray()
			for point: Vector2 in piece:
				var t := clampf((point.y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
				var color := colors[band].lerp(colors[band + 1], t)
				color.a *= alpha
				piece_colors.append(color)
			item.draw_polygon(piece, piece_colors)


## ふちのない小さなバッジ用：外周をなめらかにする細い線（同じグラデーション）。
static func smooth_edge(item: CanvasItem, rect: Rect2, radius: float, colors: Array[Color], alpha: float = 1.0) -> void:
	if colors.size() < 2:
		return
	var outline := rounded_points(rect, radius)
	outline.append(outline[0])
	var edge_colors := PackedColorArray()
	var bands := colors.size() - 1
	for point: Vector2 in outline:
		var u := clampf((point.y - rect.position.y) / maxf(rect.size.y, 0.001), 0.0, 1.0) * float(bands)
		var band := mini(int(u), bands - 1)
		var color := colors[band].lerp(colors[band + 1], u - float(band))
		color.a *= alpha
		edge_colors.append(color)
	item.draw_polyline_colors(outline, edge_colors, 1.0, true)


## 角丸の矩形の外周（時計回り）。
static func rounded_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	if r < 0.5:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	var points := PackedVector2Array()
	for corner: Array in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for index: int in range(ROUND_SEGMENTS + 1):
			var angle := start + PI * 0.5 * float(index) / float(ROUND_SEGMENTS)
			var point := center + Vector2(cos(angle), sin(angle)) * r
			# 半円どうしがつながる所（カプセル）で同じ点を重ねない
			if points.is_empty() or points[points.size() - 1].distance_to(point) > 0.01:
				points.append(point)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) <= 0.01:
		points.remove_at(points.size() - 1)
	return points
