class_name TitleLogoGeometry
extends RefCounted

## ロゴ（assets/branding/logo/aiquiz_logo.json）の形を、立体の文字に使える多角形に直す。
## 形の計算は tools/logo_editor/logo_geometry.js と同じ（線は中心線と太さ、輪は中心・半径・太さ、
## cut はそれまでに塗った白を消す）。ロゴエディタで形を直すと、メニューの立体ロゴも同じ形になる。
##
## 部品は要素 id の「_」より前でまとめる（a_left・a_right・a_bar → "a"、q_ring・q_tail → "q"）。
## 消す要素（cut）は、それより前に塗った要素だけから引く（エディタの描く順と同じ）。
## 返す座標は「リグ座標」：ロゴの外接矩形の中心が原点、x 右・y 上、単位はロゴのピクセル（1024 の画用紙）。

const LOGO_JSON := "res://assets/branding/logo/aiquiz_logo.json"
const ARC_STEP := PI / 90.0
const MITER_LIMIT := 4.0
const CIRCLE_STEPS := 180


static func load_model(path: String = LOGO_JSON) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## ロゴを部品に分けて返す。
## {
##   "pieces": [{"key", "polys": Array[PackedVector2Array]（部品の中心が原点）, "center": Vector2, "size": Vector2,
##               "bottom": float}],
##   "bounds": Rect2（リグ座標）, "baseline": float（リグ座標の文字の下端）
## }
static func build(model: Dictionary) -> Dictionary:
	var elements: Array = []
	for el: Variant in model.get("elements", []):
		if el is Dictionary and (el as Dictionary).get("visible", true) != false:
			elements.append(el)
	if elements.is_empty():
		return {}
	var logo_rect := _paint_bounds(elements)
	var origin := logo_rect.get_center()
	var grouped := {}
	var order: Array[String] = []
	for i: int in elements.size():
		var el: Dictionary = elements[i]
		if str(el.get("op", "paint")) == "cut":
			continue
		var later_cuts: Array[PackedVector2Array] = []
		for j: int in range(i + 1, elements.size()):
			var cut: Dictionary = elements[j]
			if str(cut.get("op", "paint")) == "cut":
				for poly: PackedVector2Array in _contours(cut, _no_cuts()):
					later_cuts.append(poly)
		var polys := _contours(el, later_cuts)
		for cut_poly: PackedVector2Array in later_cuts:
			polys = _subtract(polys, cut_poly)
		var key := _piece_key(el)
		if not grouped.has(key):
			grouped[key] = []
			order.append(key)
		for poly: PackedVector2Array in polys:
			var clean := _clean(poly)
			if clean.size() >= 3:
				(grouped[key] as Array).append(_to_rig(clean, origin))
	var pieces: Array = []
	var bottoms: Array[float] = []
	for key: String in order:
		var polys: Array = grouped[key]
		if polys.is_empty():
			continue
		var rect := _polys_rect(polys)
		var center := rect.get_center()
		var local: Array[PackedVector2Array] = []
		for poly: PackedVector2Array in polys:
			var moved := PackedVector2Array()
			for p: Vector2 in poly:
				moved.append(p - center)
			local.append(moved)
		pieces.append({
			"key": key, "polys": local, "center": center, "size": rect.size,
			"bottom": rect.position.y,
		})
		bottoms.append(rect.position.y)
	bottoms.sort()
	var rig_rect := Rect2(-logo_rect.size * 0.5, logo_rect.size)
	return {
		"pieces": pieces,
		"bounds": rig_rect,
		# 文字の下端のうちまん中の値（Q の尾・U の丸みのはみ出しに引っぱられない）
		"baseline": bottoms[int(bottoms.size() / 2.0)] if not bottoms.is_empty() else rig_rect.position.y,
	}


static func _piece_key(el: Dictionary) -> String:
	var id := str(el.get("id", ""))
	if id.is_empty():
		return "piece"
	var cut_at := id.find("_")
	return id if cut_at < 0 else id.substr(0, cut_at)


static func _to_rig(poly: PackedVector2Array, origin: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in poly:
		out.append(Vector2(p.x - origin.x, origin.y - p.y))
	# 表を +Z から見て反時計回り（y 上）にそろえる
	if _signed_area(out) < 0.0:
		out.reverse()
	return out


static func _polys_rect(polys: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly: PackedVector2Array in polys:
		for p: Vector2 in poly:
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2(lo, hi - lo)


static func _paint_bounds(elements: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for el: Dictionary in elements:
		if str(el.get("op", "paint")) == "cut":
			continue
		for poly: PackedVector2Array in _contours(el, _no_cuts()):
			for p: Vector2 in poly:
				lo = lo.min(p)
				hi = hi.max(p)
	return Rect2(lo, hi - lo)


static func signed_area(poly: PackedVector2Array) -> float:
	return _signed_area(poly)


static func _signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i: int in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## 近すぎる点と、ほぼ一直線に並んだ点を落とす。
static func _clean(poly: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in poly:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.05:
			pts.append(p)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.05:
		pts.remove_at(pts.size() - 1)
	var changed := true
	while changed and pts.size() > 3:
		changed = false
		for i: int in pts.size():
			var a := pts[(i - 1 + pts.size()) % pts.size()]
			var b := pts[i]
			var c := pts[(i + 1) % pts.size()]
			if absf((b - a).cross(c - b)) < 1e-4 * maxf(1.0, (c - a).length()):
				pts.remove_at(i)
				changed = true
				break
	return pts


## polys（穴なし）から cut を引く。結果に穴が出たら、外周へ細いすき間でつないで 1 つの多角形にする。
static func _subtract(polys: Array[PackedVector2Array], cut: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in polys:
		var pieces := Geometry2D.clip_polygons(poly, cut)
		var outers: Array[PackedVector2Array] = []
		var holes: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			if piece.size() < 3:
				continue
			var inside_other := false
			for other: PackedVector2Array in pieces:
				if other != piece and other.size() >= 3 and Geometry2D.is_point_in_polygon(piece[0], other) \
						and absf(_signed_area(other)) > absf(_signed_area(piece)):
					inside_other = true
					break
			if inside_other:
				holes.append(piece)
			else:
				outers.append(piece)
		for hole: PackedVector2Array in holes:
			for k: int in outers.size():
				if Geometry2D.is_point_in_polygon(hole[0], outers[k]):
					outers[k] = _keyhole(outers[k], hole)
					break
		out.append_array(outers)
	return out


static func _keyhole(outer: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
	var o := outer.duplicate()
	var h := hole.duplicate()
	if (_signed_area(o) > 0.0) == (_signed_area(h) > 0.0):
		h.reverse()
	var best := INF
	var bi := 0
	var bj := 0
	for i: int in o.size():
		for j: int in h.size():
			var d := o[i].distance_squared_to(h[j])
			if d < best:
				best = d
				bi = i
				bj = j
	var merged := PackedVector2Array()
	for i: int in range(0, bi + 1):
		merged.append(o[i])
	for k: int in range(h.size() + 1):
		merged.append(h[(bj + k) % h.size()])
	for i: int in range(bi, o.size()):
		merged.append(o[i])
	return merged


## 要素の輪郭（穴なしの多角形の配列、ロゴ座標）。輪は、後の cut が太さ全体を消す角度で
## 切り開いて 1 本の多角形にする（切り口は cut で消えるので、面取りの溝が残らない）。
static func _contours(el: Dictionary, later_cuts: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if str(el.get("kind", "line")) == "circle":
		var ring: Array[PackedVector2Array] = [_ring_outline(el, later_cuts)]
		return ring
	return _line_outline(el)


static func _no_cuts() -> Array[PackedVector2Array]:
	var none: Array[PackedVector2Array] = []
	return none


static func _v2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _left_of(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x)


static func _centerline(el: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Variant in el.get("points", []):
		pts.append(_v2(p))
	var n := pts.size()
	if n < 2:
		return pts
	var radii: Array = el.get("radii", [])
	var want := PackedFloat32Array()
	var turn := PackedFloat32Array()
	want.resize(n)
	turn.resize(n)
	for i: int in range(1, n - 1):
		var r := maxf(0.0, float(radii[i]) if i < radii.size() else 0.0)
		var d1 := (pts[i] - pts[i - 1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		var th := acos(clampf(d1.dot(d2), -1.0, 1.0))
		turn[i] = th
		if r > 0.0 and th > 1e-4 and th < PI - 1e-3:
			want[i] = r * tan(th / 2.0)
	var t := want.duplicate()
	for i: int in range(n - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		var need := t[i] + t[i + 1]
		if need > seg and need > 0.0:
			var k := seg / need
			t[i] *= k
			t[i + 1] *= k
	var out := PackedVector2Array([pts[0]])
	for i: int in range(1, n - 1):
		var p := pts[i]
		if t[i] <= 1e-6:
			out.append(p)
			continue
		var d1 := (p - pts[i - 1]).normalized()
		var d2 := (pts[i + 1] - p).normalized()
		var th := turn[i]
		var r := t[i] / tan(th / 2.0)
		var t1 := p - d1 * t[i]
		var nrm := _left_of(d1)
		if nrm.dot(d2) < 0.0:
			nrm = -nrm
		var c := t1 + nrm * r
		var a1 := atan2(t1.y - c.y, t1.x - c.x)
		var dir := 1.0 if d1.cross(d2) > 0.0 else -1.0
		var steps := maxi(2, ceili(th / ARC_STEP))
		for s: int in range(steps + 1):
			var a := a1 + dir * th * (float(s) / steps)
			out.append(Vector2(c.x + r * cos(a), c.y + r * sin(a)))
	out.append(pts[n - 1])
	var clean := PackedVector2Array([out[0]])
	for i: int in range(1, out.size()):
		if out[i].distance_to(clean[clean.size() - 1]) > 1e-4:
			clean.append(out[i])
	return clean


static func _cap_points(p: Vector2, d: Vector2, half: float, cap: String) -> Dictionary:
	var n := _left_of(d)
	var l := p + n * half
	var r := p - n * half
	if cap == "h" and absf(d.y) > 0.2:
		l += d * ((p.y - l.y) / d.y)
		r += d * ((p.y - r.y) / d.y)
	elif cap == "v" and absf(d.x) > 0.2:
		l += d * ((p.x - l.x) / d.x)
		r += d * ((p.x - r.x) / d.x)
	var extra := PackedVector2Array()
	if cap == "round":
		var a0 := atan2(n.y, n.x)
		var steps := ceili(PI / ARC_STEP)
		for s: int in range(1, steps):
			var a := a0 + PI * (float(s) / steps)
			extra.append(Vector2(p.x + half * cos(a), p.y + half * sin(a)))
	return {"L": l, "R": r, "extra": extra}


static func _line_outline(el: Dictionary) -> Array[PackedVector2Array]:
	var c := _centerline(el)
	var half := maxf(0.01, float(el.get("width", 0.0)) / 2.0)
	var out: Array[PackedVector2Array] = []
	if c.size() < 2:
		return out
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var m := c.size()
	for i: int in range(1, m - 1):
		var d_prev := (c[i] - c[i - 1]).normalized()
		var d_next := (c[i + 1] - c[i]).normalized()
		var n_prev := _left_of(d_prev)
		var n_next := _left_of(d_next)
		var mid := (n_prev + n_next).normalized()
		var cos_half := mid.dot(n_prev)
		if cos_half > 1.0 / MITER_LIMIT:
			var k := half / cos_half
			left.append(c[i] + mid * k)
			right.append(c[i] - mid * k)
		else:
			left.append_array([c[i] + n_prev * half, c[i] + n_next * half])
			right.append_array([c[i] - n_prev * half, c[i] - n_next * half])
	var d_start := (c[0] - c[1]).normalized()
	var d_end := (c[m - 1] - c[m - 2]).normalized()
	var s := _cap_points(c[0], d_start, half, str(el.get("capStart", "butt")))
	var e := _cap_points(c[m - 1], d_end, half, str(el.get("capEnd", "butt")))
	var poly := PackedVector2Array([s.R])
	poly.append_array(left)
	poly.append(e.L)
	poly.append_array(e.extra)
	poly.append(e.R)
	for i: int in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	poly.append(s.L)
	poly.append_array(s.extra)
	out.append(poly)
	return out


static func _ring_outline(el: Dictionary, later_cuts: Array[PackedVector2Array]) -> PackedVector2Array:
	var center := _v2(el.get("center", [0, 0]))
	var r := float(el.get("radius", 0.0))
	var half := float(el.get("width", 0.0)) / 2.0
	var ri := maxf(0.0, r - half)
	var ro := r + half
	var slit := 0.0
	var found := false
	for cut: PackedVector2Array in later_cuts:
		for s: int in CIRCLE_STEPS:
			var a := TAU * s / CIRCLE_STEPS
			var dir := Vector2(cos(a), sin(a))
			if Geometry2D.is_point_in_polygon(center + dir * (ri + 0.5), cut) \
					and Geometry2D.is_point_in_polygon(center + dir * (ro - 0.5), cut) \
					and Geometry2D.is_point_in_polygon(center + dir * r, cut):
				slit = a
				found = true
				break
		if found:
			break
	var poly := PackedVector2Array()
	for s: int in range(CIRCLE_STEPS + 1):
		var a := slit + TAU * s / CIRCLE_STEPS
		poly.append(center + Vector2(cos(a), sin(a)) * ro)
	if ri <= 0.0:
		poly.remove_at(poly.size() - 1)
		return poly
	for s: int in range(CIRCLE_STEPS, -1, -1):
		var a := slit + TAU * s / CIRCLE_STEPS
		poly.append(center + Vector2(cos(a), sin(a)) * ri)
	return poly
