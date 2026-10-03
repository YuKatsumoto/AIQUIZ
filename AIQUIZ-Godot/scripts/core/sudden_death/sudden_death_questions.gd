class_name SuddenDeathQuestions
extends RefCounted

## サドンデスの早押し問題を、通信を待たずに用意する（仕様書 第4章）。
## 取る順番：①本編で生成済みの未使用候補 ②オフライン問題 ③算数の自動生成。
## 本編で出た問題と画像付きの問題は除き、短く読める問題（推定解答時間が上限以下）を優先する。
## 選択肢は元の数のまま（4つより多ければ4つへ縮める）、並びは混ぜ直す。


static func collect(provider: QuizProvider, subject: String, grade: int, difficulty: String,
		played: Array, tuning: SuddenDeathTuning, rng: RandomNumberGenerator) -> Array[QuizItem]:
	var used := _used_keys(played)
	var leftovers: Array[QuizItem] = []
	var offline: Array[QuizItem] = []
	if provider != null:
		if provider.has_method("take_round_leftovers"):
			leftovers = provider.call("take_round_leftovers", 12)
		offline = provider.offline_candidates(subject, grade, difficulty)
		_shuffle(offline, rng)
	var short_pool: Array[QuizItem] = []
	var long_pool: Array[QuizItem] = []
	for item: QuizItem in leftovers + offline:
		if not is_usable(item):
			continue
		var key := QuizDedup.exact_key(item.q)
		if used.has(key):
			continue
		used[key] = true
		if item.estimated_seconds <= tuning.question_max_seconds:
			short_pool.append(item)
		else:
			long_pool.append(item)
	var result: Array[QuizItem] = []
	for _index in range(SuddenDeathTuning.QUESTION_COUNT):
		var picked: QuizItem = null
		if not short_pool.is_empty():
			picked = short_pool.pop_front()
		elif not long_pool.is_empty():
			picked = long_pool.pop_front()
		var prepared := prepare(picked, rng)
		if prepared == null and provider != null:
			prepared = fallback(provider, subject, grade, rng)
		if prepared == null:
			return []
		result.append(prepared)
	return result


## オンライン生成で届いた問題（generated）を早押しの問題にする（第4章）。短く読める問題を優先し、
## 本編で出た問題と、確保済みの問題と同じ問題文は除く。生成で足りない分は 0秒で確保した fallback を使う。
## 戻り値：{"questions": Array[QuizItem], "generated": 生成した問題を使った数}
static func assemble(generated: Array[QuizItem], fallback_questions: Array[QuizItem], played: Array,
		tuning: SuddenDeathTuning, rng: RandomNumberGenerator) -> Dictionary:
	var used := _used_keys(played)
	for quiz: QuizItem in fallback_questions:
		if quiz != null:
			used[QuizDedup.exact_key(quiz.q)] = true
	var pool: Array[QuizItem] = []
	for item: QuizItem in generated:
		if not is_usable(item) or item.estimated_seconds > tuning.question_max_seconds:
			continue
		var key := QuizDedup.exact_key(item.q)
		if used.has(key):
			continue
		used[key] = true
		pool.append(item)
	var questions: Array[QuizItem] = []
	var generated_count := 0
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		var prepared: QuizItem = prepare(pool.pop_front(), rng) if not pool.is_empty() else null
		if prepared != null:
			questions.append(prepared)
			generated_count += 1
		elif index < fallback_questions.size() and fallback_questions[index] != null:
			questions.append(fallback_questions[index])
		else:
			return {"questions": fallback_questions.duplicate(), "generated": 0}
	return {"questions": questions, "generated": generated_count}


## 問題が尽きたときの1問：算数の自動生成（第4章 ④）。
static func fallback(provider: QuizProvider, subject: String, grade: int, rng: RandomNumberGenerator) -> QuizItem:
	if provider == null:
		return null
	return prepare(provider.fallback_question(subject, grade), rng)


static func is_usable(item: QuizItem) -> bool:
	if item == null or item.q.strip_edges().is_empty() or not item.img.is_empty() or not item.choice_img.is_empty():
		return false
	if item.c.size() < SuddenDeathTuning.MIN_CHOICES or item.a < 0 or item.a >= item.c.size():
		return false
	var seen := {}
	for choice: String in item.c:
		var key := choice.strip_edges()
		if key.is_empty() or seen.has(key):
			return false
		seen[key] = true
	return true


## 選択肢を元の数のまま（4つより多ければ4つへ）にして並びを混ぜ直す。使えない問題は null。
static func prepare(item: QuizItem, rng: RandomNumberGenerator) -> QuizItem:
	if not is_usable(item):
		return null
	return prepare_choices(item, clampi(item.c.size(), SuddenDeathTuning.MIN_CHOICES, SuddenDeathTuning.MAX_CHOICES), rng)


## 正解と、ランダムな不正解を残して count 個にする。並びも混ぜ直す。
static func prepare_choices(item: QuizItem, count: int, rng: RandomNumberGenerator) -> QuizItem:
	if not is_usable(item) or item.c.size() < count:
		return null
	var wrong: Array[int] = []
	for index in range(item.c.size()):
		if index != item.a:
			wrong.append(index)
	_shuffle(wrong, rng)
	var order: Array[int] = [item.a]
	order.append_array(wrong.slice(0, count - 1))
	_shuffle(order, rng)
	var result := item.duplicate(true) as QuizItem
	result.c = PackedStringArray()
	for source: int in order:
		result.c.append(item.c[source])
	result.a = order.find(item.a)
	result.choice_img = PackedStringArray()
	return result


static func _used_keys(played: Array) -> Dictionary:
	var used := {}
	for quiz: Variant in played:
		if quiz is QuizItem:
			used[QuizDedup.exact_key((quiz as QuizItem).q)] = true
		elif quiz is String:
			used[QuizDedup.exact_key(quiz as String)] = true
	return used


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var held: Variant = values[index]
		values[index] = values[other]
		values[other] = held
