extends RefCounted
class_name FractionFormatter

## 分数表記の変換ユーティリティ
## ドアラベル向け: 縦書きスタック表記 (3 → 3\n──\n5)
## インライン向け: Unicode上付き/下付き分数 (3/5 → ³⁄₅)

# Unicode 上付き数字
const _SUPER := {
	"0": "\u2070", "1": "\u00b9", "2": "\u00b2", "3": "\u00b3", "4": "\u2074",
	"5": "\u2075", "6": "\u2076", "7": "\u2077", "8": "\u2078", "9": "\u2079"
}

# Unicode 下付き数字
const _SUB := {
	"0": "\u2080", "1": "\u2081", "2": "\u2082", "3": "\u2083", "4": "\u2084",
	"5": "\u2085", "6": "\u2086", "7": "\u2087", "8": "\u2088", "9": "\u2089"
}

## 分数パターン (数字/数字) を検出するRegExを生成
static func _make_regex() -> RegEx:
	var r := RegEx.new()
	r.compile("(\\d+)/(\\d+)")
	return r

## テキストに分数パターンが含まれるかチェック
static func has_fraction(text: String) -> bool:
	return _make_regex().search(text) != null

## テキスト全体が分数のみか (前後の空白は許可)
static func is_pure_fraction(text: String) -> bool:
	var s := text.strip_edges()
	var m := _make_regex().search(s)
	if not m:
		return false
	return m.get_start() == 0 and m.get_end() == s.length()

## 縦書きスタック表記に変換 (Label3Dのドアラベル向け)
## "3/5" → "3\n──\n5"
## Label3Dの horizontal_alignment=CENTER により各行が自動的に中央揃えされる
static func to_stacked(text: String) -> String:
	var regex := _make_regex()
	var result := text
	var matches := regex.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var num_s := m.get_string(1)
		var den_s := m.get_string(2)
		var bar_len := maxi(num_s.length(), den_s.length()) + 1
		var bar := "\u2500".repeat(bar_len)  # ─ を繰り返し
		var stacked := num_s + "\n" + bar + "\n" + den_s
		result = result.substr(0, m.get_start()) + stacked + result.substr(m.get_end())
	return result

## Unicode分数表記に変換 (インライン表示向け)
## "3/5" → "³⁄₅"
static func to_inline(text: String) -> String:
	var regex := _make_regex()
	var result := text
	var matches := regex.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var num_s := m.get_string(1)
		var den_s := m.get_string(2)
		var frac := _to_super(num_s) + "\u2044" + _to_sub(den_s)  # ⁄ (fraction slash)
		result = result.substr(0, m.get_start()) + frac + result.substr(m.get_end())
	return result

## 選択肢テキスト用: 純粋な分数ならスタック、混合テキストならインライン
static func format_choice(text: String) -> String:
	if is_pure_fraction(text):
		return to_stacked(text)
	elif has_fraction(text):
		return to_inline(text)
	return text

static func _to_super(s: String) -> String:
	var r := ""
	for c in s:
		r += _SUPER.get(c, c)
	return r

static func _to_sub(s: String) -> String:
	var r := ""
	for c in s:
		r += _SUB.get(c, c)
	return r
