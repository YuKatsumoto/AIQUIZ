extends RefCounted

const HistoryFixtures = preload("res://tools/fixtures/generation_history_cases.gd")
var failures: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS: " + label)
	else:
		failures += 1
		push_error("  FAIL: " + label)

func run() -> int:
	var fixtures: RefCounted = HistoryFixtures.new()
	var provider: BufferedQuizProvider = fixtures.new_provider()
	var bank: QuizProvider = QuizProvider.new()
	var raw: Array = []
	for i in range(1, 61):
		raw.append({"q":"【計算】%d ÷ 2 はいくつ？" % (i * 2),
			"c":[str(i), str(i + 1)], "a":0, "e":"2で割ります。", "genre":"わり算"})
	bank.bank = {"算数":{"3":raw}}
	provider.offline_provider = bank
	provider.set_llm_mode("OFFLINE")
	for i in range(1000):
		provider.recent_history_entries.append(fixtures.entry("【計算】%d ÷ 2 はいくつ？" % (i * 2)))
	provider._sync_recent_questions_from_entries()
	var saved_history: Array[Dictionary] = provider.recent_history_entries.duplicate(true)

	# バンクにある数値違いは採用し、同じ問題文は採用しない。
	var excluded: Array[String] = ["【計算】2 ÷ 2 はいくつ？"]
	var batch: Array[QuizItem] = bank.get_quizzes("算数", 3, "普通", Constants.MODE_TEN, 10, excluded)
	check(batch.size() == 10, "除外指定があってもローカルバンクから10問を取得")
	var bank_only: bool = true
	var no_excluded: bool = true
	for q in batch:
		bank_only = bank_only and q.src == "OFFLINE"
		no_excluded = no_excluded and q.q not in excluded
	check(bank_only and no_excluded, "同じ計算書式の別問題を使い、除外問題・代替生成を使わない")
	check(not provider._should_block_quiz(batch[1].q, [batch[0].q] as Array[String], true),
		"オフラインでは数値の違う計算問題を受け入れる")
	check(provider._should_block_quiz(batch[0].q, [batch[0].q] as Array[String], true),
		"同じ問題文の二重採用は拒否")

	for round_index in range(2):
		provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
		provider._on_poll()
		var delivered: Array[QuizItem] = provider.get_quizzes("算数", 3, "普通", Constants.MODE_TEN, 4)
		delivered.append_array(provider.get_quizzes("算数", 3, "普通", Constants.MODE_TEN, 6))
		check(delivered.size() == 10, "ラウンド%d: 4問と6問に分割して10問を取得" % (round_index + 1))
		var texts: Array[String] = []
		for q in delivered:
			texts.append(q.q)
		check(QuizDedup.make_exact_index(texts).size() == 10, "ラウンド%d: プリロード10問に重複なし" % (round_index + 1))
		check(provider._should_block_quiz(delivered[0].q, [] as Array[String], true),
			"未回答でも払い出し済みの問題を再採用しない")
		provider._prepare_emergency_cache()
		check(provider._emergency_cache.size() == 5, "予備キャッシュを1回で5問補充")
		var cache_fresh: bool = true
		for q in provider._emergency_cache:
			cache_fresh = cache_fresh and q.q not in texts and q.src == "OFFLINE"
		check(cache_fresh, "予備問題にも払い出し済み問題が混ざらない")
		provider.end_round()

	provider.begin_round("算数", 3, "普通", Constants.MODE_ENDLESS, 1)
	provider._on_poll()
	var endless_texts: Array[String] = []
	for i in range(12):
		var next: Array[QuizItem] = provider.get_quizzes("算数", 3, "普通", Constants.MODE_ENDLESS, 1)
		if next.size() == 1:
			endless_texts.append(next[0].q)
	check(endless_texts.size() == 12, "エンドレスはバッファ枯渇後も12問を連続供給")
	check(QuizDedup.make_exact_index(endless_texts).size() == 12, "予備キャッシュの再補充をまたいでも重複なし")
	check(provider.recent_history_entries == saved_history, "オフライン検証で保存履歴1000件を変更しない")
	bank.free()
	fixtures.dispose(provider)
	return failures
