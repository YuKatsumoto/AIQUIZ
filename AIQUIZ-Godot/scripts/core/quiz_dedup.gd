class_name QuizDedup
extends RefCounted

## 問題文のセマンティック重複判定（online_fetch / buffered_provider 共通）

const SAME_ANSWER_CORE_SIMILARITY: float = 0.40
const PROMPT_HISTORY_MAX: int = 30
const BLOCKLIST_HISTORY_MAX: int = 80
## プリロード中は cross-round 履歴のこの件数だけをセマンティック dedup 対象にする
const PRELOAD_ACCEPT_HISTORY_MAX: int = 30


static func tail_texts(candidates: Array, max_count: int) -> Array[String]:
	var texts: Array[String] = []
	var start := maxi(0, candidates.size() - max_count)
	for i in range(start, candidates.size()):
		var text := history_entry_text(candidates[i])
		if not text.is_empty() and text not in texts:
			texts.append(text)
	return texts


static func is_semantically_similar(q1: String, q2: String) -> bool:
	if q1 == q2:
		return true
	if q1.similarity(q2) > 0.55:
		return true
	var core1 := extract_core_concept(q1)
	var core2 := extract_core_concept(q2)
	if not core1.is_empty() and not core2.is_empty():
		if core1.similarity(core2) > 0.60:
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
	# 2語以上の内容語が共通（聞き方違いの同一概念）
	var sig_shared := 0
	for k in kw1:
		if k.length() >= 2 and kw2.has(k):
			sig_shared += 1
	return sig_shared >= 2


static func is_similar_to_any(question: String, candidates: Array) -> bool:
	for raw in candidates:
		var text := history_entry_text(raw)
		if text.is_empty():
			continue
		if is_semantically_similar(question, text):
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
