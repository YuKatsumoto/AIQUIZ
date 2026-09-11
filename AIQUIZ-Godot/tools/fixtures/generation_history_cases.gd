extends RefCounted

## メモリ内だけでプロバイダを動かし、履歴・プールの実データやAPIへ書き込まない。
class MemoryProvider extends BufferedQuizProvider:
	func _ready() -> void:
		pass
	func _fire_immediate_fetch() -> void:
		pass
	func _schedule_history_save() -> void:
		pass
	func _save_cross_round_history() -> void:
		pass
	func _flush_pending_explanations_on_end() -> void:
		pass
	func _schedule_fetch(_delay_sec: float = 0.0) -> void:
		pass

class MemoryBank extends GeneratedBank:
	func ensure_loaded() -> void:
		_loaded = true
	func save() -> void:
		pass

class QuietFetcher extends OnlineFetch:
	func record_adopted_units(_subject: String, _grade: int, _unit_names: Array[String]) -> void:
		pass

var failures: int = 0

func new_provider() -> BufferedQuizProvider:
	var provider := MemoryProvider.new()
	provider.online_fetcher = QuietFetcher.new()
	provider.generated_bank = MemoryBank.new()
	provider.llm_mode = "ONLINE"
	provider.is_active_round = true
	provider.current_subject = "算数"
	provider.current_grade = 3
	provider.current_difficulty = "普通"
	return provider

func dispose(provider: BufferedQuizProvider) -> void:
	provider.online_fetcher.free()
	provider.free()

func entry(question: String, subject: String = "算数", grade: int = 3,
		difficulty: String = "普通") -> Dictionary:
	var result := QuizDedup.make_history_entry(question)
	result.merge({"subject": subject, "grade": grade, "difficulty": difficulty})
	return result

func quiz(question: String, genre: String = "共通") -> QuizItem:
	var item := QuizItem.create(question, PackedStringArray(["正解", "誤答", "別の誤答", "もう一つの誤答"]), 0, "テスト", "GEMINI_STREAM")
	item.genre = genre
	return item

func check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS: " + label)
	else:
		failures += 1
		push_error("  FAIL: " + label)

func run() -> int:
	var provider := new_provider()
	var old_question := "18本の鉛筆を3人で分けると？"
	var different_numbers := "24本の鉛筆を4人で分けると？"
	provider.recent_history_entries.append(entry(old_question))
	for i in range(999):
		provider.recent_history_entries.append(entry("国語の資料番号%dの作者を調べる" % i))
	provider._sync_recent_questions_from_entries()
	var fetcher := provider.online_fetcher
	var saved_ratings := QuizManager.quiz_optimizer.ratings
	var saved_analytics := QuizManager.player_analytics
	QuizManager.quiz_optimizer.ratings = {"good": [], "bad": []}
	QuizManager.player_analytics = null

	check(provider.recent_questions.size() == 1000, "1,000件の履歴を削除せず保持")
	check(provider._recent_history_for_selection(QuizDedup.SEMANTIC_HISTORY_MAX).size() == 20,
		"履歴1,000件でも意味判定は同じ条件の直近20問")
	check(provider._should_block_quiz(old_question, [], true), "古い履歴の問題文と一致すれば拒否")
	check(not provider._should_block_quiz(different_numbers, [], true),
		"古い単元を別の数値で学び直せる")
	check(not provider._should_block_quiz(different_numbers, [], false),
		"エンドレスの補充も全履歴で単元を禁止しない")
	var history := provider._build_fetch_history()
	var exact := fetcher._collect_exact_blocklist("算数", 3, history)
	var strict := fetcher._collect_dedup_blocklist("算数", 3, "普通", history)
	var semantic := QuizDedup.tail_texts(history, QuizDedup.SEMANTIC_HISTORY_MAX)
	var filtered := fetcher._filter_unique_candidates(
		[quiz(old_question), quiz(different_numbers)] as Array[QuizItem],
		strict, semantic, {}, {}, PackedStringArray(), "算数", exact)
	check(filtered.size() == 1 and filtered[0].q == different_numbers,
		"生成側と採用側で同じ長期・短期の判定を使う")

	check(provider._append_history_entry(different_numbers, "わり算"),
		"古い概念の別問題を採用したら新しい履歴に記録")
	check(provider.recent_history_entries.size() == 1000, "採用後も保存件数は1,000件以内")
	check(provider._should_block_quiz("30本の鉛筆を5人で分けると？", [], true),
		"直近で出した数値違い・言い換えは拒否")
	check(provider._should_block_quiz("30本の鉛筆を5人で分けると？", [], false),
		"エンドレスでも直近の数値違いを拒否")

	provider.recent_history_entries.clear()
	provider.recent_history_entries.append(entry(old_question))
	for i in range(40):
		provider.recent_history_entries.append(entry("社会の資料%dを読む" % i, "社会", 3, "普通"))
		provider.recent_history_entries.append(entry("算数の発展資料%dを読む" % i, "算数", 6, "普通"))
		provider.recent_history_entries.append(entry("算数の難問資料%dを読む" % i, "算数", 3, "難しい"))
	provider._sync_recent_questions_from_entries()
	check(provider._recent_history_for_selection(20).size() == 1,
		"教科・学年・難易度が違う履歴を意味判定から除外")
	check(provider._build_fetch_history() == ([old_question] as Array[String]),
		"生成プロンプトにも選択した条件の履歴だけを渡す")
	check(provider._should_block_quiz(different_numbers, [], true),
		"別条件を続けて遊んでも対象条件の直近問題を忘れない")

	provider.recent_history_entries.clear()
	provider._sync_recent_questions_from_entries()
	provider.buffer.assign([quiz(old_question)])
	for i in range(30):
		provider.play_history.append("国語資料%dの作者を調べる" % i)
	check(provider._should_block_quiz(different_numbers, [], true),
		"今回のラウンドは20問を超えても数値違いを拒否")
	check(provider._should_block_quiz(different_numbers, [], false),
		"エンドレスでも今回のラウンドの重複を拒否")
	provider.buffer.clear()
	provider.play_history.clear()

	QuizManager.quiz_optimizer.ratings = {"good": [
		{"q": old_question, "subject": "算数", "grade": 3}], "bad": []}
	check(fetcher._collect_exact_blocklist("算数", 3, []).has(QuizDedup.exact_key(old_question)),
		"評価済み良問の問題文コピーは拒否")
	check(not QuizDedup.is_strict_duplicate_to_any(different_numbers,
		fetcher._collect_dedup_blocklist("算数", 3, "普通", [])),
		"評価済み良問と同じ単元を永久禁止しない")
	QuizManager.quiz_optimizer.ratings = {"good": [], "bad": [
		{"q": old_question, "subject": "算数", "grade": 3}]}
	check(QuizDedup.is_strict_duplicate_to_any(different_numbers,
		fetcher._collect_dedup_blocklist("算数", 3, "普通", [])),
		"品質NGとして記録された問題の除外を維持")
	QuizManager.quiz_optimizer.ratings = {"good": [], "bad": []}

	provider.buffer.assign([quiz("日本の首都は？"), quiz("三角形の内角の和は？")])
	var unused := quiz("月は地球の衛星です。正しい？")
	provider._on_fetch_partial([unused] as Array[QuizItem])
	check(not provider._recent_exact_keys.has(QuizDedup.exact_key(unused.q)),
		"ジャンル上限で採用しなかった候補を出題済みにしない")
	check(provider.generated_bank.list_question_texts("算数", 3, "普通").has(unused.q),
		"未使用候補は生成プールへ残す")
	provider.buffer.clear()
	provider._seed_from_generated_bank()
	check(provider.buffer.size() == 1 and provider.buffer[0].q == unused.q,
		"未使用のプール候補を次のラウンドで採用できる")
	check(provider._recent_exact_keys.has(QuizDedup.exact_key(unused.q)),
		"プールから採用した時点で出題履歴へ記録")

	check(QuizDedup.exact_key("18本の鉛筆を3人で分けると？")
		== QuizDedup.exact_key("18本の鉛筆を3人で分けると?"),
		"疑問符の表記変更で長期の一致判定を回避できない")
	check(QuizDedup.exact_key("3+5は？") != QuizDedup.exact_key("4+6は？"),
		"長期の一致キーで数値を保持")
	check(QuizDedup.exact_key("a long の意味は？") != QuizDedup.exact_key("along の意味は？"),
		"英語の単語間の空白を保持")
	provider.llm_mode = "OFFLINE"
	provider.buffer.clear()
	check(not provider._should_block_quiz(old_question, [], true),
		"オフラインの出題は過去オンライン履歴で枯渇しない")

	QuizManager.quiz_optimizer.ratings = saved_ratings
	QuizManager.player_analytics = saved_analytics
	dispose(provider)
	return failures
