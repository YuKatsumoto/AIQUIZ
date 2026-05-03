extends RefCounted
class_name CoopQuizBuilder

const MAX_CARD_LEN := 18
const MAX_ANSWER_LEN := 18

static func build_coop_quiz(base: QuizItem, subject: String, grade: int, question_index: int = 0) -> QuizItem:
	if not base:
		return null

	var correct_answer := _choice_at(base, base.a)
	var wrong_answers := _collect_wrong_answers(base, correct_answer)
	var wrong_answer := _pick_wrong_answer(wrong_answers, correct_answer, "")

	var combo_role := _combo_role_name(subject)
	var answer_role := "答えカード"
	var correct_combo := _make_correct_combo_card(base, subject, grade)
	var wrong_combo := _make_wrong_combo_card(base, subject, wrong_answers, correct_combo)

	var combo_choices := _make_pair(correct_combo, wrong_combo)
	var answer_choices := _make_pair(correct_answer, wrong_answer)
	var combo_answer := combo_choices.find(correct_combo)
	var answer_answer := answer_choices.find(correct_answer)

	var p1_gets_combo := question_index % 2 == 0
	var item := QuizItem.create(
		base.q,
		answer_choices,
		answer_answer,
		base.e,
		base.src,
		base.img,
		base.choice_img,
		maxf(base.estimated_seconds + 1.8, 5.6)
	)
	item.coop_prompt = base.q

	if p1_gets_combo:
		item.coop_p1_label = "P1 " + combo_role
		item.coop_p2_label = "P2 " + answer_role
		item.coop_p1_choices = combo_choices
		item.coop_p2_choices = answer_choices
		item.coop_p1_answer = combo_answer
		item.coop_p2_answer = answer_answer
	else:
		item.coop_p1_label = "P1 " + answer_role
		item.coop_p2_label = "P2 " + combo_role
		item.coop_p1_choices = answer_choices
		item.coop_p2_choices = combo_choices
		item.coop_p1_answer = answer_answer
		item.coop_p2_answer = combo_answer
	return item

static func _combo_role_name(subject: String) -> String:
	match subject:
		"算数":
			return "式カード"
		"国語":
			return "言葉カード"
		"理科":
			return "条件カード"
		"社会":
			return "手がかりカード"
		_:
			return "根拠カード"

static func _choice_at(base: QuizItem, idx: int) -> String:
	if base and idx >= 0 and idx < base.c.size():
		return _shorten(base.c[idx], MAX_ANSWER_LEN)
	return "正解"

static func _collect_wrong_answers(base: QuizItem, correct_answer: String) -> PackedStringArray:
	var wrongs: PackedStringArray = []
	if base:
		for i: int in range(base.c.size()):
			if i != base.a:
				var text := _shorten(base.c[i], MAX_ANSWER_LEN)
				if text != correct_answer and not text.is_empty():
					wrongs.append(text)
	return wrongs

static func _pick_wrong_answer(wrongs: PackedStringArray, correct_answer: String, avoid: String) -> String:
	var candidates: PackedStringArray = []
	for wrong: String in wrongs:
		if wrong != avoid:
			candidates.append(wrong)
	if candidates.size() > 0:
		return candidates[randi() % candidates.size()]
	if wrongs.size() > 0 and wrongs[0] != correct_answer:
		return _fallback_wrong_answer(correct_answer, wrongs[0])
	return _fallback_wrong_answer(correct_answer, avoid)

static func _fallback_wrong_answer(correct_answer: String, avoid: String) -> String:
	if correct_answer.is_valid_int():
		var candidate := str(correct_answer.to_int() + 1)
		if candidate != avoid:
			return candidate
		return str(correct_answer.to_int() - 1)
	if correct_answer.is_valid_float():
		var candidate := _shorten(str(correct_answer.to_float() + 1.0), MAX_ANSWER_LEN)
		if candidate != avoid:
			return candidate
		return _shorten(str(correct_answer.to_float() - 1.0), MAX_ANSWER_LEN)
	var text_candidates := PackedStringArray(["ちがう答え", "別の答え", "もう一つの答え"])
	for candidate: String in text_candidates:
		if candidate != correct_answer and candidate != avoid:
			return candidate
	return _shorten("%sではない" % correct_answer, MAX_ANSWER_LEN)

static func _make_correct_combo_card(base: QuizItem, subject: String, grade: int) -> String:
	match subject:
		"算数":
			var expression := _extract_math_expression(base.q)
			if not expression.is_empty():
				return _shorten("式: " + expression, MAX_CARD_LEN)
			return _shorten("計算: %s" % _best_reason_text(base, grade), MAX_CARD_LEN)
		"国語":
			var quoted_word := _extract_quoted_text(base.q)
			if not quoted_word.is_empty():
				return _shorten("言葉: " + quoted_word, MAX_CARD_LEN)
			return _shorten("文: %s" % _best_reason_text(base, grade), MAX_CARD_LEN)
		"理科":
			var condition := _extract_quoted_text(base.q)
			if not condition.is_empty():
				return _shorten("条件: " + condition, MAX_CARD_LEN)
			return _shorten("性質: %s" % _best_reason_text(base, grade), MAX_CARD_LEN)
		"社会":
			var clue := _extract_quoted_text(base.q)
			if not clue.is_empty():
				return _shorten("手がかり: " + clue, MAX_CARD_LEN)
			return _shorten("関係: %s" % _best_reason_text(base, grade), MAX_CARD_LEN)
		_:
			return _shorten("根拠: %s" % _best_reason_text(base, grade), MAX_CARD_LEN)

static func _make_wrong_combo_card(base: QuizItem, subject: String,
		wrong_answers: PackedStringArray, correct_combo: String) -> String:
	var candidates: PackedStringArray = []
	if wrong_answers.size() > 0:
		candidates.append(_shorten("まぎれ: " + wrong_answers[randi() % wrong_answers.size()], MAX_CARD_LEN))
	match subject:
		"算数":
			candidates.append("式: 逆に考える")
			candidates.append("単位を見落とす")
		"国語":
			candidates.append("似た読みを選ぶ")
			candidates.append("意味を取り違える")
		"理科":
			candidates.append("条件を一つ外す")
			candidates.append("似た性質を選ぶ")
		"社会":
			candidates.append("時代を混同する")
			candidates.append("場所を取り違える")
		_:
			candidates.append("一部だけを見る")
			candidates.append("似た答えを選ぶ")

	var safe_candidates: PackedStringArray = []
	for candidate: String in candidates:
		var text := _shorten(candidate, MAX_CARD_LEN)
		if text != correct_combo and not text.is_empty():
			safe_candidates.append(text)
	if safe_candidates.is_empty():
		return "別の根拠"
	return safe_candidates[randi() % safe_candidates.size()]

static func _make_pair(correct: String, wrong: String) -> PackedStringArray:
	var choices := PackedStringArray([correct, wrong])
	if randf() > 0.5:
		choices = PackedStringArray([wrong, correct])
	return choices

static func _best_reason_text(base: QuizItem, grade: int) -> String:
	if base:
		var explanation := _clean_text(base.e)
		if not explanation.is_empty():
			return explanation
		var question := _clean_text(base.q)
		if not question.is_empty():
			return question
	return "%d年の知識" % grade

static func _extract_quoted_text(text: String) -> String:
	var regex := RegEx.new()
	if regex.compile("[「『](.+?)[」』]") != OK:
		return ""
	var result := regex.search(text)
	if result:
		return result.get_string(1)
	return ""

static func _extract_math_expression(text: String) -> String:
	var regex := RegEx.new()
	if regex.compile("(\\d+(?:\\.\\d+)?\\s*[+\\-×xX*/÷]\\s*\\d+(?:\\.\\d+)?)") != OK:
		return ""
	var result := regex.search(text)
	if result:
		return result.get_string(1).replace(" ", "")
	return ""

static func _clean_text(text: String) -> String:
	var cleaned := text.replace("\n", " ").replace("\r", " ").strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	return cleaned

static func _shorten(text: String, max_len: int) -> String:
	var cleaned := _clean_text(text)
	if cleaned.length() <= max_len:
		return cleaned
	return cleaned.left(maxi(1, max_len - 1)) + "…"
