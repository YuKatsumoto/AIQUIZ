extends SceneTree

## メニューのタイトルの登場演出（scripts/ui/title_logo/title_logo_intro.gd）に使うロゴの部品の形を確かめる（静的なチェック）。
##   部品：ロゴの JSON の要素が、文字ごとの部品（a・i1・q・u・i2・z と、ヘリが運ぶ d1）に分かれる
##   すき間：A→Q の斜め線のすき間で I（1 本目）が 2 つに割れる。Q の輪は尾のすき間で開き、1 本の多角形になる
##   向き：どの多角形も反時計回り（y 上）で、三角形に分けられる（Polygon2D で描ける）
##   大きさ：外接矩形の縦横比が、2D のロゴの画像（assets/ui/branding/aiquiz_logo.png）と同じ
##     （演出の最後に部品から画像へ入れ替えるので、定位置にそろった部品が画像と重なる必要がある）
##   時間：形の計算にかかる時間も出す
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/title_logo_geometry_check.gd

const UI_LOGO := "res://assets/ui/branding/aiquiz_logo.png"
const EXPECTED_KEYS := ["a", "d1", "i1", "i2", "q", "u", "z"]

var report := {"passed": true, "problems": [], "checks": 0}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	report.checks += 1
	if not ok:
		report.passed = false
		report.problems.append(label)


func run() -> void:
	var started := Time.get_ticks_usec()
	var model := TitleLogoGeometry.load_model()
	check(not model.is_empty(), "logo JSON loads")
	var geometry := TitleLogoGeometry.build(model)
	check(not geometry.is_empty(), "geometry builds")
	if geometry.is_empty():
		_finish()
		return
	var pieces: Array = geometry.pieces
	var by_key := {}
	for info: Dictionary in pieces:
		by_key[str(info.key)] = info
	var keys := by_key.keys()
	keys.sort()
	check(keys == EXPECTED_KEYS, "piece keys %s" % [keys])
	if by_key.has("i1"):
		check((by_key.i1.polys as Array).size() == 2, "I (first) is split in two by the A→Q gap")
	if by_key.has("q"):
		# 輪は斜め線と尾のすき間で 2 つの弧に開き、穴のない多角形だけになる。尾は 4 頂点の 1 本
		var q_polys: Array = by_key.q.polys
		var tails := q_polys.filter(func(poly: PackedVector2Array) -> bool: return poly.size() == 4)
		check(q_polys.size() == 3 and tails.size() == 1, "Q is two ring arcs plus the tail")
	for info: Dictionary in pieces:
		for poly: PackedVector2Array in info.polys:
			check(TitleLogoGeometry.signed_area(poly) > 0.0, "%s polygon is counter-clockwise" % info.key)
			check(not Geometry2D.triangulate_polygon(poly).is_empty(), "%s polygon triangulates" % info.key)
	var bounds: Rect2 = geometry.bounds
	var image := Image.load_from_file(ProjectSettings.globalize_path(UI_LOGO))
	if image != null:
		var used := image.get_used_rect()
		var png_aspect := float(used.size.x) / float(used.size.y)
		var aspect := bounds.size.x / bounds.size.y
		report["aspect"] = {"geometry": aspect, "ui_png": png_aspect}
		check(absf(aspect - png_aspect) / png_aspect < 0.02, "aspect matches the 2D logo")
	# 文字の下端（ベースライン）は A・I・Z の下にそろう（Q の尾・U の丸みははみ出す）
	var baseline := float(geometry.baseline)
	if by_key.has("a"):
		var a: Dictionary = by_key.a
		check(absf(float(a.bottom) - baseline) < 0.5, "baseline is the bottom of A")
	if by_key.has("q"):
		check(float(by_key.q.bottom) < baseline - 5.0, "Q tail reaches below the baseline")
	report["timing_ms"] = {"geometry": (Time.get_ticks_usec() - started) / 1000.0}
	if image != null:
		_check_motion(Vector2(56.0 * image.get_width() / image.get_height(), 56.0))
	_finish()


## AE から書き出した動き（TitleLogoIntro.MOTION_PATH）を読んで、始まりと終わりの姿を確かめる。
func _check_motion(logo_size: Vector2) -> void:
	var intro := TitleLogoIntro.new()
	check(intro.setup(logo_size, [], null), "intro loads the After Effects motion")
	if intro._pieces.is_empty():
		intro.free()
		return
	report["intro_duration"] = intro.duration()
	check(intro.duration() > 5.5 and intro.duration() < 8.5, "intro lasts 5.5-8.5 s")
	var worst_shift := 0.0
	for piece: TitleLogoIntro.Piece in intro._pieces:
		worst_shift = maxf(worst_shift, piece.rest_shift.length())
	report["rest_shift_px"] = worst_shift
	check(worst_shift < 0.05, "AE rest poses sit on the logo slots (layout.json is current)")
	intro._bar_rect = TitleLogoIntro.DEFAULT_BAR_RECT
	intro._running = true
	intro._t = 0.0
	intro._apply_frame()
	var any_shown := false
	for piece: TitleLogoIntro.Piece in intro._pieces:
		any_shown = any_shown or piece.face.visible
	check(not any_shown and is_zero_approx(intro._form), "starts as the yellow bar with no letters")
	intro._t = intro.duration()
	intro._apply_frame()
	var settled := true
	for piece: TitleLogoIntro.Piece in intro._pieces:
		var xf := piece.face.transform
		settled = settled and piece.face.visible and xf.origin.distance_to(piece.slot) < 0.01 			and xf.x.distance_to(Vector2.RIGHT) < 0.001 and xf.y.distance_to(Vector2.DOWN) < 0.001
	check(settled, "every letter ends exactly on its slot, upright and unscaled")
	check(is_zero_approx(intro._form), "ends as the yellow bar")
	if intro._bridge != null:
		var full := true
		for i: int in intro._bridge.outlines.size():
			full = full and intro._bridge.face_shapes[i].polygon == intro._bridge.outlines[i]
		check(full, "the A-Q bar ends fully revealed")
	intro.free()


func _finish() -> void:
	print("TITLE_LOGO_GEOMETRY " + JSON.stringify(report))
	quit(0 if report.passed else 1)
