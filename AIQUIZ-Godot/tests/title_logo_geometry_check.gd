extends SceneTree

## メニューのタイトル（scripts/ui/title_logo/title_logo_intro.gd）に使う TESTOPIA のロゴの部品と、AE の動きを確かめる（静的なチェック）。
##   部品：ロゴの JSON の要素が、文字ごとの部品（t1・e・s・t2・o・p・i・a）に分かれる。O は紺の穴・P1 の頭の立方体（上・前の面。厚みと同じ右上へ伸びる）・白い字、
##         A も同じ並びで頭は P2 の青、I は白い 1 本（2026-10-19〜 書体 Stereofunk。それまでは I が「!」だった）
##   向き：どの多角形も反時計回り（y 上）で、三角形に分けられる（Polygon2D で描ける）
##   大きさ：外接矩形の縦横比が、2D のロゴの画像（assets/ui/branding/testopia_logo.png）と同じ
##   落とす順：T（1つ目）と E は扉のブロック 1 つにまとめ、左の扉のブロックから右の A まで 7 つを、ベルトの右の端に落とす
##   動き：始まりは黄色い線だけ。部品は画面の外（上）から落ちる。全部そろうとブロックが爆散し、中から T と E が出る。
##         最後はどの文字も定位置・傾きなし・等倍で、扉のブロックと破片は消えていて、ベルトのまま
##   厚み：文字に紺の厚みがある
##   時間：形の計算にかかる時間も出す
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/title_logo_geometry_check.gd

const UI_LOGO := "res://assets/ui/branding/testopia_logo.png"
const EXPECTED_KEYS := ["a", "e", "i", "o", "p", "s", "t1", "t2"]

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
	for head: Array in [["o", "#F28C33", "P1"], ["a", "#33A6E6", "P2"]]:
		var key: String = head[0]
		if not by_key.has(key):
			continue
		var colors: Array = by_key[key].colors
		check((by_key[key].polys as Array).size() == 4 and colors[0] == Color.html("#1B2A4A") and colors[2] == Color.html(head[1])
			and colors[3] == Color.WHITE, "%s is the navy hole, the %s head cube (top, front faces) and the white letter" % [key, head[2]])
		check(by_key[key].flat == [true, true, true, false], "only the white %s gets depth" % key)
		# 頭の前の面は、穴の右と下の縁まで届く（紺のすき間がない）
		var hole_rect := _poly_rect(by_key[key].polys[0])
		var front_rect := _poly_rect(by_key[key].polys[2])
		check(front_rect.end.x >= hole_rect.end.x - 0.01 and front_rect.position.y <= hole_rect.position.y + 0.01,
			"the %s head reaches the right and bottom edges of the hole" % key)
		# 頭の上の面は、文字の厚みと同じ向き（右上）へ伸びる：前の面より上へ出て、上の面の一番上の辺の左の端は前の面の左の端より右
		var top_poly: PackedVector2Array = by_key[key].polys[1]
		var top_rect := _poly_rect(top_poly)
		var back_left := INF
		for p: Vector2 in top_poly:
			if p.y >= top_rect.end.y - 0.01:
				back_left = minf(back_left, p.x)
		check(top_rect.end.y > front_rect.end.y + 0.5 and back_left > front_rect.position.x + 0.5,
			"the %s head recedes up-right like the letters' depth" % key)
	if by_key.has("i"):
		check((by_key.i.polys as Array).size() == 1 and by_key.i.colors[0] == Color.WHITE, "I is a single white bar")
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
	# 文字の下端（ベースライン）は T・E・O・A の下にそろう（Stereofunk の O は下へはみ出さない）
	var baseline := float(geometry.baseline)
	for key: String in ["t1", "e", "o", "a"]:
		if by_key.has(key):
			check(absf(float(by_key[key].bottom) - baseline) < 0.5, "baseline is the bottom of %s" % key)
	report["timing_ms"] = {"geometry": (Time.get_ticks_usec() - started) / 1000.0}
	if image != null:
		var logo_size := Vector2(56.0 * image.get_width() / image.get_height(), 56.0)
		_check_layout(logo_size)
		_check_motion(logo_size)
	_finish()


func _check_layout(logo_size: Vector2) -> void:
	var layout := TitleLogoIntro.build_layout(logo_size)
	check(not layout.is_empty(), "layout builds")
	if layout.is_empty():
		return
	var door: Dictionary = layout.door
	var shards: int = int(door.cols) * int(door.rows)
	check((layout.pieces as Array).size() == 8 + 1 + shards, "8 letters, the door block and its shards")
	check(door.letters == ["t1", "e"], "the door block carries T (first) and E")
	check((layout.order as Array).size() == 7 and layout.order[0] == TitleLogoIntro.DOOR_KEY and layout.order[6] == "a",
		"drops the door block (T and E) first and A last (they land on the right end and ride left)")
	check(absf(float(layout.landing_right) - float(_right_edge(layout, "a"))) < 0.01,
		"the landing spot is the right edge of A (the right end of the belt)")
	var rect: Rect2 = door.rect
	var t1_left := INF
	var e_right := -INF
	for record: Dictionary in layout.pieces:
		if record.key == "t1":
			t1_left = (record.slot as Vector2).x - (record.size as Vector2).x * 0.5
		elif record.key == "e":
			e_right = (record.slot as Vector2).x + (record.size as Vector2).x * 0.5
	check(rect.position.x < t1_left and rect.end.x > e_right and absf(rect.end.y - float(layout.baseline)) < 0.01,
		"the door block wraps T and E and stands on the baseline")


## AE から書き出した動き（TitleLogoIntro.MOTION_PATH）を読んで、始まりと終わりの姿を確かめる。
func _check_motion(logo_size: Vector2) -> void:
	var intro := TitleLogoIntro.new()
	check(intro.setup(logo_size), "intro loads the After Effects motion")
	if intro._pieces.is_empty():
		intro.free()
		return
	report["intro_duration"] = intro.duration()
	check(intro.duration() > 4.0 and intro.duration() < 7.0, "intro lasts 4-7 s")
	var seated_at := intro.marker_time("ALL SEATED")
	check(seated_at > 0.0 and seated_at < intro.duration(), "marker ALL SEATED inside the intro")
	var burst_at := intro.marker_time("BURST")
	check(burst_at > seated_at and burst_at < intro.duration() - 0.5, "marker BURST after ALL SEATED")
	report["burst_s"] = burst_at
	# 落ちはじめは、モード選択の大きなロゴ（1.55 倍、画面の上のほう）でも画面の上の外
	var highest := INF
	var riders: Array = TitleLogoIntro.build_layout(logo_size).order
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if riders.has(piece.key):
			var first := float(piece.layer.get("inPoint", 0.0))
			highest = minf(highest, (intro._layer_transform(piece.layer, first).origin + piece.rest_shift).y)
	report["drop_start_y_px"] = highest
	check(highest < -150.0, "pieces start falling far above the logo")
	var worst_shift := 0.0
	var worst_key := ""
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if piece.rest_shift.length() > worst_shift:
			worst_shift = piece.rest_shift.length()
			worst_key = piece.key
	report["rest_shift_px"] = {"worst": worst_shift, "piece": worst_key}
	check(worst_shift < 0.05, "AE rest poses sit on the logo slots (layout.json is current)")
	intro.start()
	var any_shown := false
	for piece: TitleLogoIntro.Piece in intro._pieces:
		any_shown = any_shown or piece.face.visible
	check(not any_shown and is_zero_approx(intro._form), "starts as the yellow bar with nothing on it")
	# 爆散の直前はブロック、直後は T と E（ブロックは消え、破片が飛ぶ）
	if burst_at > 0.0:
		intro._t = burst_at - 0.05
		intro._apply_frame()
		var before := _shown(intro)
		intro._t = burst_at + 0.05
		intro._apply_frame()
		var after := _shown(intro)
		check(before.has("door") and not before.has("t1") and not before.has("e"), "the door block hides T and E until the burst")
		check(not after.has("door") and after.has("t1") and after.has("e") and after.has("shard0"), "the burst shows T, E and the shards")
	intro.show_final()
	var final_shown := _shown(intro)
	final_shown.sort()
	check(final_shown == EXPECTED_KEYS, "only the 8 letters are left at the end %s" % [final_shown])
	var settled := true
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if not EXPECTED_KEYS.has(piece.key):
			continue
		var xf := piece.face.transform
		settled = settled and piece.face.visible and xf.origin.distance_to(piece.slot) < 0.01 \
			and xf.x.distance_to(Vector2.RIGHT) < 0.001 and xf.y.distance_to(Vector2.DOWN) < 0.001
	check(settled, "every letter ends exactly on its slot, upright and unscaled")
	check(is_equal_approx(intro._form, 1.0), "ends on the conveyor (the belt stays)")
	var depth_ok := true
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if EXPECTED_KEYS.has(piece.key):
			depth_ok = depth_ok and piece.depth != null and piece.depth.visible and piece.depth.get_child_count() > 0
	check(depth_ok, "every letter has its navy depth")
	intro.set_view_scale(2.0)
	var o_piece: TitleLogoIntro.Piece = null
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if piece.key == "o":
			o_piece = piece
	if o_piece != null:
		check(o_piece.face.transform.origin.distance_to(o_piece.slot * 2.0) < 0.02, "view scale doubles positions")
	intro.free()


static func _right_edge(layout: Dictionary, key: String) -> float:
	for record: Dictionary in layout.pieces:
		if record.key == key:
			return (record.slot as Vector2).x + (record.size as Vector2).x * 0.5
	return NAN


## 多角形の外接矩形（リグ座標なので y 上。position.y が下の端）
static func _poly_rect(poly: PackedVector2Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


static func _shown(intro: TitleLogoIntro) -> Array:
	var out: Array = []
	for piece: TitleLogoIntro.Piece in intro._pieces:
		if piece.face.visible:
			out.append(piece.key)
	return out


func _finish() -> void:
	print("TITLE_LOGO_GEOMETRY " + JSON.stringify(report))
	quit(0 if report.passed else 1)
