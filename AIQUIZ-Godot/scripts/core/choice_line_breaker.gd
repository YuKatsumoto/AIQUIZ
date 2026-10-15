extends RefCounted
class_name ChoiceLineBreaker

## 扉の選択肢を、語の途中ではなく文節の切れ目で改行するユーティリティ。
## Label3D の自動折り返しは日本語をどの文字の間でも割るので「二酸化炭素を出し、酸|素を受け取|る」のようになる。
## ここでは文字の種類の変わり目・助詞・句読点などから文字の間ごとの「改行してよい度合い」(0〜1) を見積もり、
## 文字をなるべく大きく保ちつつ、いちばん悪い改行位置がなるべく良い分け方を選んで、明示的な改行を入れる。
## 辞書は持たないので完全ではないが、熟語・カタカナ語・英単語・送り仮名の途中は避けられる。

## 文字幅はこの文字サイズで1字ずつ測り、文字サイズに比例させて使う。
const _REF_SIZE := 100
## 1行増えるごとの評価の割引。同じくらいの大きさなら行数が少ないほうを選ぶ。
const _LINE_PENALTY := 0.98
const _MAX_LINES := 6
## これより小さい文字は遠くの壁では読みにくいので、評価をさらに大きさの比率で割り引く
## (QuizWall.CHOICE_UNIFORM_MIN_FONT_SIZE と同じ)。良い改行位置のために文字を小さくしすぎないようにする。
const _COMFORT_SIZE := 56
## 1文字だけの行 (句読点を除く) は、改行位置の良さに関係なくこの度合いまで下げる。
const _SINGLE_CHAR_LINE_SCORE := 0.3

## 改行位置の良さ。分けた後の文字サイズにこの比率を掛けて比べる
## (例: 熟語の途中で割るくらいなら文字を3割小さくしてでも別の位置で割る)。
const _Q_IDEAL := 1.0
const _Q_BEFORE_OPEN := 0.95
const _Q_AFTER_WO := 0.95
const _Q_AFTER_CLOSE := 0.9
const _Q_ARROW := 0.9
const _Q_AFTER_PARTICLE := 0.85
const _Q_AFTER_NAKAGURO := 0.85
const _Q_AFTER_LONG_PARTICLE := 0.7
const _Q_ADVERBIAL := 0.6
const _Q_HIRAGANA_PARTICLE := 0.5
const _Q_SCRIPT_CHANGE := 0.45
const _Q_OKURIGANA := 0.45
const _Q_HIRAGANA := 0.35
const _Q_TAIL := 0.3
const _Q_KANJI := 0.3
const _Q_NUMBER_UNIT := 0.25
const _Q_KATAKANA := 0.2
## 括弧の中 (読みがな・補足) で割るときは、上の良さにこれを掛ける。
const _IN_BRACKETS_FACTOR := 0.4

enum _Kind { HIRAGANA, KATAKANA, KANJI, ALNUM, OPEN, CLOSE, STOP, SPACE, OTHER }

## 行頭に来てはいけない文字 (閉じ括弧・句読点・小書き仮名・長音など)。
const _NO_LINE_START := "、。，．,.）)」』】〕］]〉》｝}!?！？：；:;…‥ー々ゝゞヽヾぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ%％℃〜～"
## 行末に来てはいけない文字 (開き括弧)。
const _NO_LINE_END := "（(「『【〔［[〈《｛{"
const _OPEN := "（(「『【〔［[〈《｛{“‘"
const _CLOSE := "）)」』】〕］]〉》｝}”’"
const _STOP := "、。，．!?！？：；"
## かな1字で後ろの語と切り離してよい助詞。
const _PARTICLES := "をにがはでともへのやて"
const _LONG_PARTICLES: Array[String] = ["から", "まで", "より", "ので", "には", "では", "とは", "へは", "けど", "でも", "にも", "とも", "へも",
		"だけ", "しか", "など", "ほど", "ごと", "くらい", "ぐらい"]

static var _layout_cache: Dictionary = {}
static var _advance_cache: Dictionary = {}


## 内枠 box (ラベルのピクセル単位) に収まる改行入りの文字列と文字サイズを返す: {"text": String, "font_size": int}。
## 文字サイズは max_size 以下。min_size 以上で語を割らずに収まらない文字列や、
## すでに改行を含む文字列 (縦積みの分数) では空の辞書を返すので、呼び出し側で従来の自動折り返しに任せる。
static func layout(text: String, font: Font, box: Vector2, min_size: int, max_size: int) -> Dictionary:
	if text.length() < 2 or text.contains("\n") or font == null:
		return {}
	var key := "%d|%d|%d|%d|%d|%s" % [font.get_instance_id(), roundi(box.x), roundi(box.y), min_size, max_size, text]
	if _layout_cache.has(key):
		return _layout_cache[key]
	var result := _compute_layout(text, font, box, min_size, max_size)
	if _layout_cache.size() > 4096:
		_layout_cache.clear()
	_layout_cache[key] = result
	return result


## 文字の間ごとの改行の良さ。scores[i] は i 文字目の直前で改行する良さ (scores[0] は未使用)。
## 空白の直後での改行は空白を落とす。
static func break_scores(text: String) -> PackedFloat32Array:
	var n := text.length()
	var scores := PackedFloat32Array()
	scores.resize(n)
	var depth := 0
	for i: int in range(1, n):
		var prev := text[i - 1]
		if _OPEN.contains(prev):
			depth += 1
		elif _CLOSE.contains(prev):
			depth = maxi(0, depth - 1)
		scores[i] = _break_score(text, i)
		if depth > 0:
			scores[i] *= _IN_BRACKETS_FACTOR
	return scores


static func _compute_layout(text: String, font: Font, box: Vector2, min_size: int, max_size: int) -> Dictionary:
	var n := text.length()
	var scores := break_scores(text)
	# prefix[i] = 先頭 i 文字の幅 (_REF_SIZE)。
	var prefix := PackedFloat32Array()
	prefix.resize(n + 1)
	for i: int in range(n):
		prefix[i + 1] = prefix[i] + _advance(font, text[i])
	var line_height_ref := font.get_height(_REF_SIZE)
	# 空白・句読点の位置 (行の幅・1文字行の判定は毎回文字列を切り出さずにこれを見る)。
	var spaces := PackedByteArray()
	var stops := PackedByteArray()
	spaces.resize(n)
	stops.resize(n)
	for i: int in range(n):
		spaces[i] = 1 if _is_space(text[i]) else 0
		stops[i] = 1 if _kind(text[i]) == _Kind.STOP else 0

	# 改行を許す位置の下限と行数の上限の組ごとに、収まる最大の文字サイズと最も良い分け方を求め、
	# 文字サイズに改行位置の良さを掛けた評価が最も高いものを選ぶ。
	# (行数の上限も変えるのは、最大サイズだけを見ると「てっきん|―|…」のような1文字行に引きずられるため。)
	var thresholds: Array[float] = []
	for i: int in range(1, n):
		if scores[i] > 0.0 and not thresholds.has(scores[i]):
			thresholds.append(scores[i])
	thresholds.sort()
	thresholds.reverse()
	var best_score := -1.0
	var best_size := 0
	var cuts := PackedInt32Array()
	# 閾値 2.0 は改行位置を1つも許さない (1行のまま)。
	for threshold: float in [2.0] + thresholds:
		var allowed := _allowed_positions(scores, threshold)
		var previous_size := 0
		for line_limit: int in range(1, (1 if threshold > 1.0 else _MAX_LINES) + 1):
			var size := _largest_feasible_size(spaces, prefix, allowed, line_height_ref, box, min_size, max_size, line_limit)
			if size <= previous_size:
				continue
			previous_size = size
			# 改行位置がどれも理想的でも今の最良に届かなければ、分け方を求めるまでもない。
			if _score(size, 1.0, 1) <= best_score:
				continue
			var max_width := _max_line_width_ref(size, box)
			var lines := _greedy_line_count(spaces, prefix, allowed, max_width)
			var candidate := _best_cuts(spaces, stops, prefix, scores, allowed, lines, max_width)
			if candidate.is_empty():
				continue
			var quality := 1.0
			for k: int in range(candidate.size() - 1):
				quality = minf(quality, _line_quality(spaces, stops, scores, candidate[k], candidate[k + 1]))
			var score := _score(size, quality, lines)
			if score > best_score:
				best_score = score
				best_size = size
				cuts = candidate
	if cuts.is_empty():
		return {}

	var parts := PackedStringArray()
	for k: int in range(cuts.size() - 1):
		parts.append(_strip_spaces(text.substr(cuts[k], cuts[k + 1] - cuts[k])))
	var laid := "\n".join(parts)
	# 1字ずつの幅の合計は実際の組版とわずかにずれるので、実測で収まるまで小さくする。
	var size := best_size
	while size > min_size and not _fits(laid, font, size, box):
		size -= 1
	if not _fits(laid, font, size, box):
		return {}
	return {"text": laid, "font_size": size}


static func _score(font_size: int, quality: float, lines: int) -> float:
	return font_size * minf(1.0, float(font_size) / _COMFORT_SIZE) * quality * pow(_LINE_PENALTY, lines - 1)


static func _break_score(text: String, i: int) -> float:
	var prev := text[i - 1]
	var next := text[i]
	if _is_space(next):
		return 0.0
	if _is_space(prev):
		return _Q_IDEAL
	if _NO_LINE_START.contains(next) or _NO_LINE_END.contains(prev):
		return 0.0
	var pk := _kind(prev)
	var nk := _kind(next)
	if pk == _Kind.STOP:
		return _Q_IDEAL
	if nk == _Kind.OPEN:
		return _Q_BEFORE_OPEN
	if pk == _Kind.CLOSE:
		return _Q_AFTER_CLOSE
	if prev == "→" or next == "→":
		return _Q_ARROW
	if prev == "・":
		return _Q_AFTER_NAKAGURO
	if next == "・":
		return 0.0
	if pk == _Kind.ALNUM and nk == _Kind.ALNUM:
		return 0.0
	if pk == _Kind.HIRAGANA:
		if prev == "を":
			return _Q_AFTER_WO
		var run := _hiragana_run_before(text, i)
		if nk == _Kind.HIRAGANA:
			# 「を」や「だけ|が」の「が」のように、助詞は行頭に来ると前の語から切り離されて読みにくい。
			if next == "を":
				return _Q_TAIL
			for particle: String in _LONG_PARTICLES:
				if text.substr(i - 1, particle.length()) == particle or (particle.length() == 3 and text.substr(i - 2, 3) == particle):
					return _Q_HIRAGANA
			for particle: String in _LONG_PARTICLES:
				if run.ends_with(particle):
					return _Q_HIRAGANA if _PARTICLES.contains(next) else _Q_AFTER_LONG_PARTICLE
			# 「大きく|なる」「早く|する」の連用形の「く」の後。
			if prev == "く" and (next == "な" or next == "す"):
				return _Q_ADVERBIAL
			return _Q_HIRAGANA_PARTICLE if _PARTICLES.contains(prev) else _Q_HIRAGANA
		# かなの後に漢字・カタカナ・英数字が来る: 助詞の後なら語の切れ目。
		# 漢字1字 + かな1字 (買い|物・受け|取る) は送り仮名の途中なので避ける。
		var run_start := i - run.length()
		var after_kanji := run_start > 0 and _kind(text[run_start - 1]) == _Kind.KANJI
		if after_kanji and run.length() == 1 and not _PARTICLES.contains(prev):
			return _Q_OKURIGANA
		if run.length() == 1 and run_start == 0 and (prev == "お" or prev == "ご"):
			return _Q_OKURIGANA
		return _Q_AFTER_PARTICLE
	if nk == _Kind.HIRAGANA:
		# 助詞や送り仮名は前の語に付くので、その手前では割らない。
		return _Q_TAIL
	if pk == _Kind.KANJI and nk == _Kind.KANJI:
		return _Q_KANJI
	if pk == _Kind.KATAKANA and nk == _Kind.KATAKANA:
		return _Q_KATAKANA
	if pk == _Kind.ALNUM and nk == _Kind.KANJI and _is_digit(prev):
		return _Q_NUMBER_UNIT
	if pk in [_Kind.KANJI, _Kind.KATAKANA, _Kind.ALNUM] and nk in [_Kind.KANJI, _Kind.KATAKANA, _Kind.ALNUM]:
		return _Q_SCRIPT_CHANGE
	return _Q_TAIL


static func _kind(c: String) -> _Kind:
	if _is_space(c):
		return _Kind.SPACE
	if _STOP.contains(c):
		return _Kind.STOP
	if _OPEN.contains(c):
		return _Kind.OPEN
	if _CLOSE.contains(c):
		return _Kind.CLOSE
	var code := c.unicode_at(0)
	if (code >= 0x3041 and code <= 0x309F):
		return _Kind.HIRAGANA
	if (code >= 0x30A0 and code <= 0x30FF and code != 0x30FB) or (code >= 0x31F0 and code <= 0x31FF) or (code >= 0xFF66 and code <= 0xFF9F):
		return _Kind.KATAKANA
	if (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3400 and code <= 0x4DBF) or code == 0x3005 or code == 0x3006 or (code >= 0xF900 and code <= 0xFAFF):
		return _Kind.KANJI
	# 英数字 (全角・上付き下付きの分数を含む) と、単語の中に現れる記号。
	if (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A) \
			or (code >= 0xFF10 and code <= 0xFF19) or (code >= 0xFF21 and code <= 0xFF3A) or (code >= 0xFF41 and code <= 0xFF5A) \
			or (code >= 0x00C0 and code <= 0x024F) or (code >= 0x2070 and code <= 0x209F) \
			or code in [0xB2, 0xB3, 0xB9, 0x2044, 0x27, 0x2D, 0x2E, 0x2C, 0x2F, 0x3A, 0x25, 0x2B, 0x3D, 0x5E]:
		return _Kind.ALNUM
	return _Kind.OTHER


static func _is_space(c: String) -> bool:
	return c == " " or c == "　" or c == "\t"


static func _strip_spaces(line: String) -> String:
	var from := 0
	var to := line.length()
	while from < to and _is_space(line[from]):
		from += 1
	while to > from and _is_space(line[to - 1]):
		to -= 1
	return line.substr(from, to - from)


static func _is_digit(c: String) -> bool:
	var code := c.unicode_at(0)
	return (code >= 0x30 and code <= 0x39) or (code >= 0xFF10 and code <= 0xFF19)


static func _hiragana_run_before(text: String, i: int) -> String:
	var start := i
	while start > 0 and _kind(text[start - 1]) == _Kind.HIRAGANA:
		start -= 1
	return text.substr(start, i - start)


static func _advance(font: Font, c: String) -> float:
	var key := "%d|%s" % [font.get_instance_id(), c]
	if not _advance_cache.has(key):
		_advance_cache[key] = font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, _REF_SIZE).x
	return _advance_cache[key]


## 輪郭の太さ (QuizWall と同じく文字サイズの 1/6)。
static func _outline(font_size: int) -> int:
	return maxi(1, roundi(float(font_size) / 6.0))


## この文字サイズで1行に使える幅 (_REF_SIZE 換算)。
static func _max_line_width_ref(font_size: int, box: Vector2) -> float:
	return (box.x - _outline(font_size) * 2.0) * _REF_SIZE / font_size


static func _max_lines(font_size: int, line_height_ref: float, box: Vector2) -> int:
	var line_height := line_height_ref * font_size / _REF_SIZE
	return mini(_MAX_LINES, floori((box.y - _outline(font_size) * 2.0) / line_height))


static func _allowed_positions(scores: PackedFloat32Array, threshold: float) -> PackedInt32Array:
	var allowed := PackedInt32Array()
	for i: int in range(1, scores.size()):
		if scores[i] >= threshold:
			allowed.append(i)
	allowed.append(scores.size())
	return allowed


## 前後の空白を除いた [from, to) の幅。
static func _segment_width(spaces: PackedByteArray, prefix: PackedFloat32Array, from: int, to: int) -> float:
	while from < to and spaces[from] == 1:
		from += 1
	while to > from and spaces[to - 1] == 1:
		to -= 1
	return prefix[to] - prefix[from]


## 許された位置だけで改行し、各行をできるだけ長くしたときの行数 (最少行数)。収まらなければ 0。
static func _greedy_line_count(spaces: PackedByteArray, prefix: PackedFloat32Array, allowed: PackedInt32Array, max_width: float) -> int:
	var start := 0
	var lines := 0
	var idx := 0
	while start < spaces.size():
		var end := -1
		while idx < allowed.size() and _segment_width(spaces, prefix, start, allowed[idx]) <= max_width:
			end = allowed[idx]
			idx += 1
		if end < 0:
			return 0
		lines += 1
		start = end
	return lines


static func _largest_feasible_size(spaces: PackedByteArray, prefix: PackedFloat32Array, allowed: PackedInt32Array,
		line_height_ref: float, box: Vector2, min_size: int, max_size: int, line_limit: int) -> int:
	var low := min_size - 1
	var high := max_size
	while low < high:
		var mid := (low + high + 1) / 2
		var lines := _greedy_line_count(spaces, prefix, allowed, _max_line_width_ref(mid, box))
		if lines > 0 and lines <= mini(line_limit, _max_lines(mid, line_height_ref, box)):
			low = mid
		else:
			high = mid - 1
	return low if low >= min_size else 0


## line_count 行に分ける改行位置のうち、いちばん悪い改行位置が最も良く、次いで良さの合計が大きいものを選ぶ。
## 戻り値は [0, 改行位置..., 文字数]。
static func _best_cuts(spaces: PackedByteArray, stops: PackedByteArray, prefix: PackedFloat32Array, scores: PackedFloat32Array,
		allowed: PackedInt32Array, line_count: int, max_width: float) -> PackedInt32Array:
	var positions := PackedInt32Array([0])
	positions.append_array(allowed)
	var count := positions.size()
	# best[j][p]: 先頭から positions[p] までを j 行に分けたときの [最悪の良さ, 良さの合計] と、直前の位置。
	var best: Array = []
	var back: Array = []
	for j: int in range(line_count + 1):
		var row: Array = []
		row.resize(count)
		best.append(row)
		var back_row := PackedInt32Array()
		back_row.resize(count)
		back.append(back_row)
	best[0][0] = Vector2(2.0, 0.0)
	for j: int in range(1, line_count + 1):
		for p: int in range(1, count):
			var to := positions[p]
			for s: int in range(p - 1, -1, -1):
				var from := positions[s]
				if _segment_width(spaces, prefix, from, to) > max_width:
					break
				var prior: Variant = best[j - 1][s]
				if prior == null:
					continue
				var quality := _line_quality(spaces, stops, scores, from, to)
				var candidate := Vector2(minf(prior.x, quality), prior.y + quality)
				var current: Variant = best[j][p]
				if current == null or candidate.x > current.x or (is_equal_approx(candidate.x, current.x) and candidate.y > current.y):
					best[j][p] = candidate
					back[j][p] = s
	if best[line_count][count - 1] == null:
		return PackedInt32Array()
	var cuts := PackedInt32Array()
	var p := count - 1
	for j: int in range(line_count, 0, -1):
		cuts.append(positions[p])
		p = back[j][p]
	cuts.append(0)
	cuts.reverse()
	return cuts


## 行 [from, to) の終わりの改行の良さ (最終行は 1)。句読点以外1文字だけの行は下げる。
static func _line_quality(spaces: PackedByteArray, stops: PackedByteArray, scores: PackedFloat32Array, from: int, to: int) -> float:
	var quality := 1.0 if to >= spaces.size() else scores[to]
	var first := from
	var last := to
	while first < last and spaces[first] == 1:
		first += 1
	while last > first and spaces[last - 1] == 1:
		last -= 1
	if last - first == 1 and stops[first] == 0:
		quality = minf(quality, _SINGLE_CHAR_LINE_SCORE)
	return quality


static func _fits(text: String, font: Font, font_size: int, box: Vector2) -> bool:
	var tp := TextParagraph.new()
	tp.width = -1.0
	tp.break_flags = TextServer.BREAK_MANDATORY
	tp.add_string(text, font, font_size)
	var size := tp.get_size() + Vector2.ONE * _outline(font_size) * 2.0
	return size.x <= box.x and size.y <= box.y
