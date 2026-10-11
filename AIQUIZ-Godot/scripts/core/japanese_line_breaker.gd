extends RefCounted

## 壁の問題文・選択肢を、日本語の文節の切れ目で改行する。
## Godot の自動折り返しは漢字・かなの間ならどこでも改行するため、「針が0を指 / すか確認す / る」のように
## 語の途中で割れてしまう。ここで改行位置を選んで "\n" を入れ、ラベル側は自動折り返しを切って表示する。
##
## 改行してよい位置にはペナルティを付け、行数・行の長さの揃い具合と合わせて合計が最小の配置を選ぶ。
## 助詞・句読点・空白のあとは自然な切れ目、熟語やかなの途中は「語の途中」、禁則は最後の手段。

## 助詞・句読点・空白のあと、開き括弧の前。
const BREAK_PHRASE := 0
## ひらがなから漢字・カタカナへ変わる所 (送り仮名のあと。「使い|方」のように語中のこともある)。
const BREAK_WEAK := 4
## 文字種の変わり目 (漢字とカタカナ、ひらがなだけの文の「を」のあとなど)。
const BREAK_MEDIUM := 8
## 漢字1字＋送り仮名1字のあとに漢字が続く所 (「組み|合わせ」「書き|順」)。複合語のことが多い。
const BREAK_COMPOUND := 40
## ひらがなだけの並びで、助詞らしい文字 (に・で・と など) のあと。「とけい」の「と」のこともあるので控えめに使う。
const BREAK_KANA_PARTICLE := 30
## 熟語やかなの途中。この値以上の改行は「語の途中で割れた」とみなす。
const BREAK_INSIDE_WORD := 60
## 数字・英単語の途中。
const BREAK_INSIDE_NUMBER := 300
## 行頭禁則 (、。ー っ など) ・行末禁則 (開き括弧) ・空白の直前。収まらないときだけ使う。
const BREAK_PROHIBITED := 10000

## 1行増えるごとのコスト。行が少ないほうを選ぶ。
const LINE_COST := 20.0
## 各行の余白 (幅に対する割合) の2乗に掛ける重み。行の長さを揃え、最後に1〜2文字だけ残る配置を避ける。
const SLACK_WEIGHT := 12.0
## 1文字だけの行 (「…赤くなるか / ら」) のコスト。
const ORPHAN_COST := 40.0
const _OVERFLOW_COST := 1000000.0

## 行頭に置かない文字。ん・ンで始まる語はないので、その前でも切らない。矢印は「取材→ / 放送→」のように行末に付ける。
const _NO_LINE_START := "→ん、。，．,.）)」』】〕］]｝}〉》！？!?：:；;ー〜～…‥・ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶン々゛゜%％"
const _NO_LINE_END := "（(「『【〔［[｛{〈《"
const _PHRASE_END := "、。，．！？!?」』）)】〕］]…→"
## 直後で切りやすい助詞 (1文字)。
const _PARTICLES := "はがをにでとへものやか"
## 動詞の連用形の送り仮名 (イ段)。「組み合わせ」「使い方」のように次の漢字と複合語を作りやすい。
const _CONTINUATIVE_KANA := "いきしちにひみりぎじびぴ"

enum Kind { HIRAGANA, KATAKANA, KANJI, ALNUM, OTHER }


## text を max_width (ピクセル) に収まるよう改行する。元からある "\n" (縦積みの分数・協力モードの役割表示) は保つ。
## 戻り値: text (改行済み), line_count, split_words (語の途中で割った箇所の数)。
## 1文字でも幅を超える場合は、その文字だけの行がはみ出す (呼び出し側で文字サイズを下げて判定する)。
static func layout(text: String, font: Font, font_size: int, max_width: float) -> Dictionary:
	var lines := PackedStringArray()
	var split_words := 0
	var advances := {}
	for paragraph: String in text.split("\n"):
		var result := _layout_paragraph(paragraph, font, font_size, max_width, advances)
		lines.append_array(result.lines)
		split_words += result.split_words
	return {"text": "\n".join(lines), "line_count": lines.size(), "split_words": split_words}


static func _layout_paragraph(s: String, font: Font, font_size: int, max_width: float, advances: Dictionary) -> Dictionary:
	var n := s.length()
	if n == 0:
		return {"lines": PackedStringArray([""]), "split_words": 0}
	var prefix := PackedFloat32Array()
	prefix.resize(n + 1)
	for k: int in range(n):
		var ch := s[k]
		if not advances.has(ch):
			advances[ch] = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		prefix[k + 1] = prefix[k] + advances[ch]

	var best := PackedFloat64Array()
	best.resize(n + 1)
	best.fill(INF)
	best[0] = 0.0
	var line_start := PackedInt32Array()
	line_start.resize(n + 1)
	for j: int in range(1, n + 1):
		var end_penalty := 0.0 if j == n else float(break_penalty(s, j))
		for i: int in range(j - 1, -1, -1):
			var w := _line_width(s, prefix, i, j)
			if w > max_width and j - i > 1:
				break
			if best[i] == INF:
				continue
			var slack := maxf(max_width - w, 0.0) / maxf(max_width, 1.0)
			var cost := best[i] + end_penalty + LINE_COST + SLACK_WEIGHT * slack * slack
			if w > max_width:
				cost += _OVERFLOW_COST
			if n > 1 and j - i <= 3 and _trim_spaces(s.substr(i, j - i)).length() == 1:
				cost += ORPHAN_COST
			if cost < best[j]:
				best[j] = cost
				line_start[j] = i

	var breaks: Array[int] = []
	var pos := n
	while pos > 0:
		breaks.push_front(line_start[pos])
		pos = line_start[pos]
	var lines := PackedStringArray()
	var split_words := 0
	for b: int in range(breaks.size()):
		var start := breaks[b]
		var stop := breaks[b + 1] if b + 1 < breaks.size() else n
		lines.append(_trim_spaces(s.substr(start, stop - start)))
		if start > 0 and break_penalty(s, start) >= BREAK_INSIDE_WORD:
			split_words += 1
	return {"lines": lines, "split_words": split_words}


## s[i - 1] と s[i] の間で改行するときのペナルティ。
static func break_penalty(s: String, i: int) -> int:
	var prev := s[i - 1]
	var cur := s[i]
	if _is_space(cur) or _NO_LINE_START.contains(cur) or _NO_LINE_END.contains(prev):
		return BREAK_PROHIBITED
	if _is_space(prev):
		return BREAK_PHRASE
	if _PHRASE_END.contains(prev) or _NO_LINE_END.contains(cur):
		return BREAK_PHRASE
	var pk := _kind(s.unicode_at(i - 1))
	var ck := _kind(s.unicode_at(i))
	if pk == Kind.ALNUM and ck == Kind.ALNUM:
		return BREAK_INSIDE_NUMBER
	if pk == Kind.HIRAGANA:
		if ck != Kind.HIRAGANA:
			if _PARTICLES.contains(prev):
				return BREAK_PHRASE
			if ck == Kind.KANJI and _CONTINUATIVE_KANA.contains(prev) and i >= 2 and _kind(s.unicode_at(i - 2)) == Kind.KANJI:
				return BREAK_COMPOUND
			return BREAK_WEAK
		if prev == "を":
			return BREAK_MEDIUM
		# 「でも」「には」のように助詞が続く所では切らない。
		if _PARTICLES.contains(prev) and not _PARTICLES.contains(cur):
			return BREAK_KANA_PARTICLE
		return BREAK_INSIDE_WORD
	# 数字のあとは単位や助詞が続く (「3本」「0を」) ので割らない。
	if pk == Kind.ALNUM or ck == Kind.HIRAGANA or pk == ck:
		return BREAK_INSIDE_WORD
	return BREAK_MEDIUM


static func _kind(c: int) -> Kind:
	if c >= 0x3041 and c <= 0x309F:
		return Kind.HIRAGANA
	if (c >= 0x30A0 and c <= 0x30FF) or (c >= 0x31F0 and c <= 0x31FF) or (c >= 0xFF66 and c <= 0xFF9F):
		return Kind.KATAKANA
	if (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0x3400 and c <= 0x4DBF) or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0x3005 and c <= 0x3007):
		return Kind.KANJI
	if (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) \
			or (c >= 0xC0 and c <= 0x24F) or (c >= 0xFF10 and c <= 0xFF19) or (c >= 0xFF21 and c <= 0xFF3A) \
			or (c >= 0xFF41 and c <= 0xFF5A) or c == 0xB2 or c == 0xB3 or c == 0xB9 \
			or (c >= 0x2070 and c <= 0x2089) or c == 0x2044:
		# 0x2070-0x2089 と 0x2044 はインライン分数 (³⁄₅) の上付き・下付き数字と斜線。
		return Kind.ALNUM
	return Kind.OTHER


static func _is_space(ch: String) -> bool:
	return ch == " " or ch == "　" or ch == "\t"


## 行頭・行末の空白は幅に数えない (改行した空白は表示しない)。
static func _line_width(s: String, prefix: PackedFloat32Array, start: int, stop: int) -> float:
	while start < stop and _is_space(s[start]):
		start += 1
	while stop > start and _is_space(s[stop - 1]):
		stop -= 1
	return prefix[stop] - prefix[start]


static func _trim_spaces(line: String) -> String:
	var start := 0
	var stop := line.length()
	while start < stop and _is_space(line[start]):
		start += 1
	while stop > start and _is_space(line[stop - 1]):
		stop -= 1
	return line.substr(start, stop - start)
