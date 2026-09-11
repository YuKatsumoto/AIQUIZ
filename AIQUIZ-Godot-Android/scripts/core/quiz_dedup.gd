class_name QuizDedup
extends RefCounted

## 問題文のセマンティック重複判定（online_fetch / buffered_provider 共通）

const SAME_ANSWER_CORE_SIMILARITY: float = 0.40
const PROMPT_HISTORY_MAX: int = 60
const PROMPT_FULLTEXT_MAX: int = 8
const BLOCKLIST_HISTORY_MAX: int = 1000
## 完全一致・数値差し替えテンプレートは保存している全履歴で拒否する。
const PRELOAD_ACCEPT_HISTORY_MAX: int = 1000
## 「毎回違う」を守るため、保存中の全履歴を意味レベルの重複判定対象にする。
## 枯渇時も重複を許可せず、BufferedProvider が新しい候補を再生成する。
const SEMANTIC_HISTORY_MAX: int = 1000


static func tail_texts(candidates: Array, max_count: int) -> Array[String]:
	var texts: Array[String] = []
	var start := maxi(0, candidates.size() - max_count)
	for i in range(start, candidates.size()):
		var text := history_entry_text(candidates[i])
		if not text.is_empty() and text not in texts:
			texts.append(text)
	return texts


static func is_semantically_similar(q1: String, q2: String) -> bool:
	return is_semantically_similar_with_cores(
		q1, extract_core_concept(q1), q2, extract_core_concept(q2)
	)


static func is_semantically_similar_with_cores(q1: String, core1: String, q2: String, core2: String) -> bool:
	if q1 == q2:
		return true
	if q1.similarity(q2) > 0.68:
		return true
	if not core1.is_empty() and not core2.is_empty():
		if core1.similarity(core2) > 0.72:
			return true
	var kw1 := extract_keywords(q1)
	var kw2 := extract_keywords(q2)
	if kw1.is_empty() or kw2.is_empty():
		return false
	var intersection := 0
	for k in kw1:
		if kw2.has(k):
			intersection += 1
	var union_size := kw1.size() + kw2.size() - intersection
	if union_size == 0:
		return false
	var jaccard := float(intersection) / float(union_size)
	if jaccard > 0.45:
		return true
	# Compare only concept cores here. Raw question bigrams contain generic endings such as
	# "どれですか" and caused unrelated questions to be rejected.
	var core_bigrams1 := _extract_bigrams(core1)
	var core_bigrams2 := _extract_bigrams(core2)
	var shared_core_bigrams := 0
	for bigram in core_bigrams1:
		if core_bigrams2.has(bigram) and not _is_generic_core_bigram(bigram):
			shared_core_bigrams += 1
	# 「計算」「正しい」など同じ教科内で偶然2組だけ重なるケースを
	# 同一問題扱いしない。短い方のコアに対する重複率も満たす近い言い換えだけを拒否する。
	var shorter_core_size: int = mini(core_bigrams1.size(), core_bigrams2.size())
	if shorter_core_size == 0:
		return false
	var core_overlap_ratio := float(shared_core_bigrams) / float(shorter_core_size)
	return shared_core_bigrams >= 2 and core_overlap_ratio >= 0.45


static func is_similar_to_any(question: String, candidates: Array) -> bool:
	var question_core := extract_core_concept(question)
	return is_similar_to_any_with_core(question, question_core, candidates)


static func is_similar_to_any_with_core(question: String, question_core: String, candidates: Array) -> bool:
	for raw in candidates:
		var text := history_entry_text(raw)
		if text.is_empty():
			continue
		var other_core := history_entry_core(raw)
		if other_core.is_empty():
			other_core = extract_core_concept(text)
		if is_semantically_similar_with_cores(question, question_core, text, other_core):
			return true
	return false


## 長期履歴向けの厳格判定。完全一致と、数字・記号・助詞だけを変えたテンプレートを拒否する。
## 広い意味類似はここでは扱わず、SEMANTIC_HISTORY_MAX の短期窓で別に判定する。
static func is_strict_duplicate(q1: String, q2: String) -> bool:
	var normalized1 := q1.strip_edges().to_lower()
	var normalized2 := q2.strip_edges().to_lower()
	if normalized1 == normalized2:
		return true
	var core1 := extract_core_concept(normalized1)
	var core2 := extract_core_concept(normalized2)
	if core1.is_empty() or core2.is_empty():
		return false
	if core1 == core2:
		return true
	return core1.similarity(core2) > 0.88


static func is_strict_duplicate_to_any(question: String, candidates: Array) -> bool:
	for raw in candidates:
		var text := history_entry_text(raw)
		if not text.is_empty() and is_strict_duplicate(question, text):
			return true
	return false


static func is_duplicate_answer_concept(q1: String, q2: String, correct1: String, correct2: String) -> bool:
	if correct1.is_empty() or correct2.is_empty() or correct1 != correct2:
		return false
	return extract_core_concept(q1).similarity(extract_core_concept(q2)) > SAME_ANSWER_CORE_SIMILARITY


static func history_entry_text(entry: Variant) -> String:
	if entry is String:
		return entry as String
	if entry is Dictionary:
		return str((entry as Dictionary).get("q", ""))
	return ""


static func history_entry_core(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("core", ""))
	return ""


static func make_history_entry(question: String, genre: String = "") -> Dictionary:
	return {
		"q": question,
		"core": extract_core_concept(question),
		"genre": genre,
	}


static func extract_core_concept(text: String) -> String:
	var result := ""
	for i in range(text.length()):
		var c := text[i]
		if c >= "0" and c <= "9":
			continue
		if c in ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９"]:
			continue
		result += c
	var noise := ["は", "の", "が", "を", "に", "で", "と", "も", "へ", "から",
		"まで", "より", "など", "たり", "って", "です", "ます", "した", "する",
		"ある", "いる", "なる", "ない", "この", "その", "どの", "どれ",
		"いくつ", "何", "どう", "とき", "こと", "もの", "ため", "ところ",
		"一番", "最も", "どの", "どれ", "どちら", "いくら",
		"？", "。", "、", "「", "」", "（", "）", "＝", "＋", "−", "×", "÷",
		"?", ".", ",", "(", ")", "=", "+", "-", " ", "　"]
	for nw: String in noise:
		result = result.replace(nw, "")
	return result


static func extract_keywords(text: String) -> Dictionary:
	var normalized := text
	var noise_words := ["は", "の", "が", "を", "に", "で", "と", "も", "へ", "から",
		"まで", "より", "など", "たり", "って", "です", "ます", "した", "する",
		"ある", "いる", "なる", "ない", "この", "その", "どの", "どれ",
		"いくつ", "何", "どう", "とき", "こと", "もの", "ため", "ところ",
		"？", "。", "、", "「", "」", "（", "）", "＝", "＋", "−", "×", "÷",
		"?", ".", ",", "(", ")", "=", "+", "-"]
	var keywords := {}
	var tokens := normalized.split(" ")
	var expanded_tokens: Array[String] = []
	for t in tokens:
		expanded_tokens.append(t)
	for token: String in expanded_tokens:
		var cleaned := token.strip_edges()
		if cleaned.length() < 2:
			continue
		if cleaned in noise_words:
			continue
		if cleaned.is_valid_int() or cleaned.is_valid_float():
			continue
		keywords[cleaned] = true
	for i in range(normalized.length() - 1):
		var bigram := normalized.substr(i, 2)
		var skip := false
		for nw: String in ["は", "の", "が", "を", "に", "で", "と", "も"]:
			if bigram.contains(nw):
				skip = true
				break
		if skip:
			continue
		if bigram.strip_edges().length() == 2:
			keywords[bigram] = true
	return keywords


static func _extract_bigrams(text: String) -> Dictionary:
	var bigrams := {}
	for i in range(maxi(0, text.length() - 1)):
		bigrams[text.substr(i, 2)] = true
	return bigrams


static func _is_generic_core_bigram(bigram: String) -> bool:
	return bigram in [
		"すか", "です", "ます", "正し", "しい", "どれ", "答え", "方法",
		"大き", "小さ", "求め", "選び", "なる", "あり", "いる", "表す",
	]
