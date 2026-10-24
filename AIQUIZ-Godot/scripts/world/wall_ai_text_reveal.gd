class_name WallAiTextReveal
extends Node

## 壁の問題文と選択肢を「AI がいま書いている」ように、1〜3 文字のかたまり（トークン）ずつ出す演出（docs/ai_question_typing.md）。
## 元の Label3D は消さずにカメラから外し（layers = 0）、同じ位置に 1 文字ずつの Label3D を元のラベルの子として並べて動かす。
## 文字の位置は Label3D と同じ規則（TextServer の行分け・行ごとの中央揃え・縦の揃え）で求めるので、
## 書き終えて元のラベルへ戻しても文字は動かない。壁のほかの処理（枠取り・2P の拡大・退場）は元のラベルのまま動く。

## 出たばかりの文字の色（HDR。ステージの glow で水色に光り、白へ冷める）と輪郭の色。
const FRESH_COLOR := Color(0.55, 1.55, 2.2)
const FRESH_OUTLINE := Color(0.0, 0.2, 0.36, 0.95)
## 文字が出るときの動き（秒）：不透明になるまで・ポップ（大きく出て少し縮みすぎて戻る）・下からせり上がる・白へ冷める。
const FADE_IN := 0.06
const POP_TIME := 0.26
const POP_FROM := 1.38
const RISE_TIME := 0.22
const RISE_EM := 0.16
const COOL_TIME := 0.45
## 1 トークン（1〜3 文字）ごとの間隔。ときどき少しつかえる（LLM の出力の揺れ）。行が変わるときも少し置く。
const TOKEN_GAP_MIN := 0.04
const TOKEN_GAP_RANGE := 0.035
const TOKEN_STALL_CHANCE := 0.06
const TOKEN_STALL := 0.12
const LINE_BREAK_PAUSE := 0.05
## 問題文を書き終えてから選択肢を書き始めるまでと、扉ごとのずらし。
const CHOICE_START_GAP := 0.12
const CHOICE_STAGGER := 0.16
## 最後のトークンが出てから「書き終えた」とするまで。
const DONE_AFTER_LAST_TOKEN := 0.12
## カーソル（水色の細い縦線。文字の高さの 0.9 倍・幅 0.08 文字）。最初の文字の少し前に出て、書き終えたら消える。
const CURSOR_COLOR := Color(0.5, 1.4, 2.0, 0.95)
const CURSOR_WIDTH_EM := 0.08
const CURSOR_HEIGHT_EM := 0.9
const CURSOR_LEAD := 0.12
const CURSOR_FOLLOW := 75.0
const CURSOR_LINGER := 0.12
const CURSOR_FADE := 0.15
## 最後のカーソルだけ 2 回点滅してから消える。
const CURSOR_BLINKS := 2
const CURSOR_BLINK_PERIOD := 0.32
## 書いているあいだ問題文の枠を水色に寄せ、書き終えたら元の鋼色へ静かに戻す（光らせたり光の筋を流したりはしない）。
const BORDER_WRITING := Color(0.42, 0.82, 1.0)
const BORDER_TINT_IN := 0.15
const BORDER_SETTLE := 0.3

var _t := 0.0
var _tracks: Array[Dictionary] = []
var _finished := false
var _done_at := INF
var _done_played := false
var _border: MeshInstance3D = null
var _border_color := Color.WHITE
var _rng := RandomNumberGenerator.new()


## labels: 先頭が問題文（無ければ null）、残りが扉の選択肢。delay 秒は文字を隠したまま待つ（壁の落下中など）。
func start(question: Label3D, choices: Array[Label3D], delay: float) -> void:
	_rng.seed = hash(question.text if question != null else "") ^ 0x5eed
	var at := delay
	if question != null:
		var track := _make_track(question, at)
		if not track.is_empty():
			_tracks.append(track)
			at = float(track.end)
	var choice_start := at + CHOICE_START_GAP
	var index := 0
	for label: Label3D in choices:
		var track := _make_track(label, choice_start + index * CHOICE_STAGGER)
		if not track.is_empty():
			_tracks.append(track)
			index += 1
	if _tracks.is_empty():
		_finished = true
		queue_free()
		return
	# 最後のトークンが出て少ししたら「書き終えた」（音を鳴らし、枠の色を戻す）。そのカーソルだけ点滅させる。
	var last: Dictionary = _tracks[0]
	for track: Dictionary in _tracks:
		if float(track.end) >= float(last.end):
			last = track
	last.blink = true
	_done_at = float(last.end) + DONE_AFTER_LAST_TOKEN
	_update(0.0)


func is_finished() -> bool:
	return _finished


## すぐに書き終えた姿へ戻す（壁の退場・扉の作り直しなど）。
func finish_now() -> void:
	for track: Dictionary in _tracks:
		_restore(track)
	_restore_border()
	_finished = true
	queue_free()


func _process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_update(_t)


func _update(t: float) -> void:
	var all_restored := true
	for track: Dictionary in _tracks:
		if bool(track.restored):
			continue
		if not is_instance_valid(track.label) or _layout_changed(track):
			_restore(track)
			continue
		all_restored = false
		_update_track(track, t)
	_update_border(t)
	if t >= _done_at and not _done_played:
		_done_played = true
		AudioManager.play_sfx(&"ai_type_done")
	if all_restored and t >= _done_at + BORDER_SETTLE:
		_restore_border()
		_finished = true
		queue_free()


# ------------------------------------------------------------------ 1 つのラベル

func _make_track(label: Label3D, start_at: float) -> Dictionary:
	if not is_instance_valid(label) or label.text.strip_edges().is_empty():
		return {}
	var clusters := layout_clusters(label)
	if clusters.is_empty():
		return {}
	# トークンに分けて、かたまりごとの表示時刻を決める。
	var times := PackedFloat32Array()
	times.resize(clusters.size())
	var token_starts := PackedFloat32Array()
	var t := start_at
	var i := 0
	while i < clusters.size():
		var n := 1 + int(_rng.randf() * 3.0)
		if i > 0 and int(clusters[i].line) != int(clusters[i - 1].line):
			t += LINE_BREAK_PAUSE
		token_starts.append(t)
		for _k: int in range(n):
			if i >= clusters.size():
				break
			times[i] = t
			i += 1
			if i < clusters.size() and int(clusters[i].line) != int(clusters[i - 1].line):
				break
		t += TOKEN_GAP_MIN + _rng.randf() * TOKEN_GAP_RANGE
		if _rng.randf() < TOKEN_STALL_CHANCE:
			t += TOKEN_STALL
	var em := float(label.font_size) * label.pixel_size
	var glyphs: Array[Label3D] = []
	for cluster: Dictionary in clusters:
		var glyph := _make_glyph(label, cluster)
		glyph.visible = false
		label.add_child(glyph)
		glyphs.append(glyph)
	var cursor := _make_cursor(label, em)
	var track := {
		"label": label,
		"layers": label.layers,
		"text": label.text,
		"font_size": label.font_size,
		"width": label.width,
		"clusters": clusters,
		"glyphs": glyphs,
		"times": times,
		"token_starts": token_starts,
		"next_token": 0,
		"start": start_at,
		"end": times[times.size() - 1],
		"em": em,
		"cursor": cursor,
		"cursor_x": float(clusters[0].left),
		"cursor_line": -1,
		"blink": false,
		"restored": false,
	}
	label.layers = 0
	return track


func _update_track(track: Dictionary, t: float) -> void:
	var label: Label3D = track.label
	var glyphs: Array[Label3D] = track.glyphs
	var clusters: Array = track.clusters
	var times: PackedFloat32Array = track.times
	var em := float(track.em)
	var settled := true
	var last_shown := -1
	for i: int in range(glyphs.size()):
		var glyph := glyphs[i]
		var age := t - times[i]
		if age < 0.0:
			glyph.visible = false
			settled = false
			continue
		last_shown = i
		glyph.visible = true
		var base: Vector3 = clusters[i].position
		if age >= COOL_TIME and age >= POP_TIME:
			if glyph.has_meta(&"settled"):
				continue
			glyph.set_meta(&"settled", true)
			glyph.position = base
			glyph.scale = Vector3.ONE
			glyph.modulate = label.modulate
			glyph.outline_modulate = label.outline_modulate
			continue
		settled = false
		var alpha := clampf(age / FADE_IN, 0.0, 1.0)
		var pop := clampf(age / POP_TIME, 0.0, 1.0)
		var rise := clampf(age / RISE_TIME, 0.0, 1.0)
		var cool := clampf(age / COOL_TIME, 0.0, 1.0)
		glyph.scale = Vector3.ONE * lerpf(POP_FROM, 1.0, _ease_out_back(pop))
		glyph.position = base + Vector3(0.0, -RISE_EM * em * pow(1.0 - rise, 3.0), 0.0)
		var cool_eased := 1.0 - (1.0 - cool) * (1.0 - cool)
		var color := FRESH_COLOR.lerp(label.modulate, cool_eased)
		color.a = label.modulate.a * alpha
		glyph.modulate = color
		var outline := FRESH_OUTLINE.lerp(label.outline_modulate, cool_eased)
		outline.a *= alpha
		glyph.outline_modulate = outline
	# トークンが出た瞬間の小さな音。
	var token_starts: PackedFloat32Array = track.token_starts
	var next_token := int(track.next_token)
	while next_token < token_starts.size() and t >= token_starts[next_token]:
		next_token += 1
		AudioManager.play_sfx(&"ai_type_tick")
	track.next_token = next_token
	_update_cursor(track, t, last_shown)
	var cursor: MeshInstance3D = track.cursor
	if settled and not is_instance_valid(cursor):
		_restore(track)


func _update_cursor(track: Dictionary, t: float, last_shown: int) -> void:
	var cursor: MeshInstance3D = track.cursor
	if not is_instance_valid(cursor):
		return
	var start := float(track.start)
	var end := float(track.end)
	var em := float(track.em)
	var clusters: Array = track.clusters
	var appear := clampf((t - (start - CURSOR_LEAD)) / CURSOR_LEAD, 0.0, 1.0)
	var alpha := appear
	var linger := CURSOR_LINGER
	if bool(track.blink):
		linger = CURSOR_BLINKS * CURSOR_BLINK_PERIOD
		var since := t - end - CURSOR_LINGER
		if since > 0.0 and since < linger and fmod(since, CURSOR_BLINK_PERIOD) > CURSOR_BLINK_PERIOD * 0.5:
			alpha = 0.0
		linger += CURSOR_LINGER
	var fade_from := end + linger
	if t >= fade_from:
		alpha *= 1.0 - clampf((t - fade_from) / CURSOR_FADE, 0.0, 1.0)
	if t >= fade_from + CURSOR_FADE:
		cursor.queue_free()
		track.cursor = null
		return
	cursor.visible = alpha > 0.001
	var material := cursor.material_override as StandardMaterial3D
	material.albedo_color.a = CURSOR_COLOR.a * alpha
	# 最後に出た文字の右へ（まだ何も出ていなければ 1 行目の頭へ）。行が変わったら飛ぶ。
	var line := int(clusters[0].line)
	var target := float(clusters[0].left) - em * 0.08
	var center_y := float(clusters[0].line_center)
	if last_shown >= 0:
		line = int(clusters[last_shown].line)
		target = float(clusters[last_shown].right)
		center_y = float(clusters[last_shown].line_center)
	target += em * (0.08 + CURSOR_WIDTH_EM * 0.5)
	var x := float(track.cursor_x)
	if line != int(track.cursor_line):
		x = target
	else:
		x = lerpf(x, target, 1.0 - exp(-CURSOR_FOLLOW * get_process_delta_time()))
	track.cursor_x = x
	track.cursor_line = line
	cursor.position = Vector3(x, center_y, 0.002)


func _make_glyph(source: Label3D, cluster: Dictionary) -> Label3D:
	var glyph := Label3D.new()
	glyph.name = "AiGlyph"
	glyph.text = cluster.text
	glyph.font = source.font
	glyph.font_size = source.font_size
	glyph.outline_size = source.outline_size
	glyph.pixel_size = source.pixel_size
	glyph.modulate = source.modulate
	glyph.outline_modulate = source.outline_modulate
	glyph.render_priority = source.render_priority
	glyph.outline_render_priority = source.outline_render_priority
	glyph.alpha_cut = source.alpha_cut
	glyph.alpha_antialiasing_mode = source.alpha_antialiasing_mode
	glyph.texture_filter = source.texture_filter
	glyph.double_sided = source.double_sided
	glyph.no_depth_test = source.no_depth_test
	glyph.shaded = source.shaded
	glyph.fixed_size = source.fixed_size
	glyph.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	glyph.text_direction = source.text_direction
	glyph.language = source.language
	glyph.cast_shadow = source.cast_shadow
	glyph.layers = source.layers
	glyph.autowrap_mode = TextServer.AUTOWRAP_OFF
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.position = cluster.position
	return glyph


func _make_cursor(source: Label3D, em: float) -> MeshInstance3D:
	var cursor := MeshInstance3D.new()
	cursor.name = "AiCursor"
	var quad := QuadMesh.new()
	quad.size = Vector2(CURSOR_WIDTH_EM * em, CURSOR_HEIGHT_EM * em)
	cursor.mesh = quad
	cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cursor.layers = source.layers
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.albedo_color = CURSOR_COLOR
	material.render_priority = source.render_priority + 1
	cursor.material_override = material
	cursor.visible = false
	source.add_child(cursor)
	return cursor


func _layout_changed(track: Dictionary) -> bool:
	var label: Label3D = track.label
	return label.text != String(track.text) or label.font_size != int(track.font_size) or label.width != float(track.width)


## 元のラベルをカメラへ戻し、1 文字ずつのラベルとカーソルを片付ける。
func _restore(track: Dictionary) -> void:
	if bool(track.restored):
		return
	track.restored = true
	# 扉を作り直したときなどは、元のラベルごと 1 文字ずつのラベルも消えている（型付きの変数に入れる前に確かめる）。
	if is_instance_valid(track.label):
		(track.label as Label3D).layers = int(track.layers)
	for glyph: Variant in track.glyphs:
		if is_instance_valid(glyph):
			(glyph as Label3D).visible = false
			(glyph as Label3D).queue_free()
	if is_instance_valid(track.cursor):
		(track.cursor as MeshInstance3D).visible = false
		(track.cursor as MeshInstance3D).queue_free()
	track.cursor = null


# ------------------------------------------------------------------ 問題文の枠

func _question_border() -> MeshInstance3D:
	if is_instance_valid(_border):
		return _border
	if _tracks.is_empty() or not is_instance_valid(_tracks[0].label):
		return null
	var label: Label3D = _tracks[0].label
	_border = label.get_node_or_null("QuestionBorder") as MeshInstance3D
	if _border != null and _border.material_override is StandardMaterial3D:
		_border_color = (_border.material_override as StandardMaterial3D).albedo_color
	else:
		_border = null
	return _border


func _update_border(t: float) -> void:
	var border := _question_border()
	if border == null:
		return
	var material := border.material_override as StandardMaterial3D
	var start := float(_tracks[0].start)
	var color := _border_color
	if t < _done_at:
		color = _border_color.lerp(BORDER_WRITING, clampf((t - start + BORDER_TINT_IN) / BORDER_TINT_IN, 0.0, 1.0))
	else:
		var settle := clampf((t - _done_at) / BORDER_SETTLE, 0.0, 1.0)
		color = BORDER_WRITING.lerp(_border_color, settle * settle * (3.0 - 2.0 * settle))
	material.albedo_color = color


func _restore_border() -> void:
	var border := _question_border()
	if border != null:
		(border.material_override as StandardMaterial3D).albedo_color = _border_color


# ------------------------------------------------------------------ Label3D と同じ文字の置き方

## Label3D の文字を 1 かたまり（書記素のまとまり）ずつ、ラベルの中の位置（m）と行の情報つきで返す。
## Label3D と同じく、TextServer の行分け（autowrap と端の空白の削り）、行ごとの水平の揃え、全体の縦の揃えで置く。
## 空白は返さない（出す文字が無い）。
static func layout_clusters(label: Label3D) -> Array:
	var result: Array = []
	var ts := TextServerManager.get_primary_interface()
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text := label.text.to_upper() if label.uppercase else label.text
	var px := label.pixel_size
	var shaped := ts.create_shaped_text()
	ts.shaped_text_set_direction(shaped, label.text_direction as TextServer.Direction)
	ts.shaped_text_add_string(shaped, text, font.get_rids(), label.font_size, font.get_opentype_features(), label.language)
	var flags := TextServer.BREAK_MANDATORY
	match label.autowrap_mode:
		TextServer.AUTOWRAP_ARBITRARY:
			flags = TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_MANDATORY
		TextServer.AUTOWRAP_WORD:
			flags = TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY
		TextServer.AUTOWRAP_WORD_SMART:
			flags = TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE | TextServer.BREAK_MANDATORY
	flags |= label.autowrap_trim_flags
	var breaks := ts.shaped_text_get_line_breaks(shaped, label.width, 0, flags)
	var lines: Array[RID] = []
	var total_h := 0.0
	for b: int in range(0, breaks.size(), 2):
		var line := ts.shaped_text_substr(shaped, breaks[b], breaks[b + 1] - breaks[b])
		lines.append(line)
		total_h += (ts.shaped_text_get_size(line).y + label.line_spacing) * px
	var y := 0.0
	match label.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = (total_h - label.line_spacing * px) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = total_h - label.line_spacing * px
	y += label.offset.y * px
	var single := ts.create_shaped_text()
	for line_index: int in range(lines.size()):
		var line := lines[line_index]
		var ascent := ts.shaped_text_get_ascent(line) * px
		var descent := ts.shaped_text_get_descent(line) * px
		var line_width := ts.shaped_text_get_width(line) * px
		var x := 0.0
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_FILL:
				x = -line_width * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = -line_width
		x += label.offset.x * px
		var baseline := y - ascent
		var line_center := baseline + (ascent - descent) * 0.5
		var glyphs := ts.shaped_text_get_glyphs(line)
		var g := 0
		while g < glyphs.size():
			var first: Dictionary = glyphs[g]
			var count := maxi(1, int(first.get("count", 1)))
			var advance := 0.0
			for k: int in range(count):
				if g + k < glyphs.size():
					var glyph: Dictionary = glyphs[g + k]
					advance += float(glyph.advance) * int(glyph.get("repeat", 1))
			var cluster_text := text.substr(int(first.start), int(first.end) - int(first.start))
			var left := x
			x += advance * px
			g += count
			# 折り返しの切れ目に入る見えないグリフ（幅 0、前の文字と同じ範囲）は描かない。
			if int(first.flags) & TextServer.GRAPHEME_IS_VIRTUAL or cluster_text.strip_edges().is_empty():
				continue
			# 1 文字だけのラベル（中央揃え）の原点を、このかたまりの描かれる位置に合わせる。
			ts.shaped_text_clear(single)
			ts.shaped_text_add_string(single, cluster_text, font.get_rids(), label.font_size, font.get_opentype_features(), label.language)
			var own_width := ts.shaped_text_get_width(single) * px
			var own_ascent := ts.shaped_text_get_ascent(single) * px
			var own_height := ts.shaped_text_get_size(single).y * px
			result.append({
				"text": cluster_text,
				"line": line_index,
				"position": Vector3(left + own_width * 0.5, baseline + own_ascent - own_height * 0.5, 0.0),
				"left": left,
				"right": left + advance * px,
				"line_center": line_center,
			})
		y = baseline - descent - label.line_spacing * px
	for line: RID in lines:
		ts.free_rid(line)
	ts.free_rid(single)
	ts.free_rid(shaped)
	return result


static func _ease_out_back(x: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * pow(x - 1.0, 3.0) + C1 * pow(x - 1.0, 2.0)
