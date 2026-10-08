extends RefCounted

## 単元スロット（抽選・生成ゲート・単元別上限・持ち越し絞り込み）の回帰テスト。
## メモリ内だけで動かし、履歴・プール・単元使用履歴のファイルへ書き込まない。

## 生成は呼ばれた回数だけ数える。API は使える扱いにする。
class SlotProvider extends BufferedQuizProvider:
	var fire_count: int = 0
	func _ready() -> void:
		pass
	func _online_api_available() -> bool:
		return true
	func _fire_immediate_fetch() -> void:
		fire_count += 1
	func _schedule_history_save() -> void:
		pass
	func _save_cross_round_history() -> void:
		pass
	func _store_leftovers_to_pool() -> void:
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

## 単元使用履歴をファイルではなく固定の並び（recent が最近使った単元）で返す。
class FixedLruFetcher extends OnlineFetch:
	var recent: Array[String] = []
	var recorded: Array[String] = []
	func _sort_units_lru(_subject: String, _grade: int, units: Array[String]) -> Array[String]:
		var old: Array[String] = []
		var used: Array[String] = []
		for unit_name in units:
			if recent.has(unit_name):
				used.append(unit_name)
			else:
				old.append(unit_name)
		used.sort_custom(func(a: String, b: String) -> bool:
			return recent.find(a) < recent.find(b)
		)
		old.append_array(used)
		return old
	func record_adopted_units(_subject: String, _grade: int, unit_names: Array[String]) -> void:
		recorded.append_array(unit_names)

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS: " + label)
	else:
		failures += 1
		push_error("  FAIL: " + label)


func quiz(question: String, genre: String) -> QuizItem:
	var item := QuizItem.create(question, PackedStringArray(["正解", "誤答", "別の誤答", "もう一つの誤答"]), 0, "テスト", "GEMINI_STREAM")
	item.genre = genre
	return item


func new_provider() -> SlotProvider:
	var provider := SlotProvider.new()
	provider.online_fetcher = FixedLruFetcher.new()
	provider.generated_bank = MemoryBank.new()
	provider.llm_mode = "ONLINE"
	return provider


func dispose(provider: BufferedQuizProvider) -> void:
	provider.online_fetcher.free()
	provider.free()


func run() -> int:
	_check_pick()
	_check_batch_allocation()
	_check_gate_and_cap()
	_check_non_slot_rounds()
	_check_spread()
	return failures


func _curriculum_units(subject: String, grade: int) -> Array[String]:
	var names: Array[String] = []
	for unit: Variant in CurriculumDB.load_grade(subject, grade).get("units", []):
		names.append(str((unit as Dictionary)["name"]))
	return names


func _check_pick() -> void:
	var fetcher := FixedLruFetcher.new()
	var all_units := _curriculum_units("算数", 3)
	fetcher.recent.assign(all_units.slice(9, 12))
	var picks := fetcher.pick_slot_units("算数", 3, 3)
	var unique := {}
	var in_curriculum := true
	for unit_name in picks:
		unique[unit_name] = true
		in_curriculum = in_curriculum and all_units.has(unit_name)
	check(picks.size() == 3 and unique.size() == 3, "算数3年: 重複なしで3単元を選ぶ")
	check(in_curriculum, "選んだ単元はすべてカリキュラムの単元名")

	var recent_hits := 0
	var oldest_hits := 0
	var oldest: Array[String] = []
	oldest.assign(all_units.slice(0, 3))
	for _i in range(300):
		for unit_name in fetcher.pick_slot_units("算数", 3, 3):
			if fetcher.recent.has(unit_name):
				recent_hits += 1
			elif oldest.has(unit_name):
				oldest_hits += 1
	check(recent_hits * 3 < oldest_hits,
		"最近使った単元は当たりにくい（最近=%d / 古い=%d）" % [recent_hits, oldest_hits])

	check(fetcher.pick_slot_units("社会", 3, 3).is_empty(), "社会3年（3単元）はスロットなし")
	check(fetcher.pick_slot_units("理科", 1, 3).is_empty(), "理科1年（2単元）はスロットなし")
	check(fetcher.pick_slot_units("理科", 4, 3).size() == 3, "理科4年（4単元）はスロットあり")
	fetcher.free()


func _check_batch_allocation() -> void:
	var fetcher := FixedLruFetcher.new()
	var units := PackedStringArray(["A", "B", "C"])
	var six := fetcher._allocate_slot_units_to_batches(units, 6)
	var flat: Array[String] = []
	var single := true
	for batch in six:
		single = single and batch.size() == 1
		flat.append(batch[0])
	check(single, "スロット割り当て: 各バッチは1単元だけ")
	check(flat == (["A", "B", "C", "A", "B", "C"] as Array[String]), "6バッチなら各単元2バッチずつ")
	var two := fetcher._allocate_slot_units_to_batches(PackedStringArray(["C", "A"]), 2)
	check(two.size() == 2 and two[0][0] == "C" and two[1][0] == "A", "補充は渡された不足順に割り当てる")
	fetcher.free()


func _check_gate_and_cap() -> void:
	var provider := new_provider()
	var fetcher := provider.online_fetcher as FixedLruFetcher
	var units := PackedStringArray(["A", "B", "C"])
	provider.generated_bank.store_items([quiz("三角形の内角の和は何度？", "A"), quiz("日本で一番長い川の名前は？", "X")] as Array[QuizItem],
		"算数", 3, "普通")
	var serial_before := provider.slot_round_serial
	provider.request_slot_round(units)
	provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
	check(provider.is_slot_gate_closed(), "スロット付きラウンドは生成を止めて始まる")
	check(provider.slot_round_serial == serial_before + 1, "抽選番号が進む")
	check(provider.get_slot_units() == units, "ラウンドのスロット単元を返す")
	check(provider.fire_count == 0 and provider.buffer.is_empty(), "解放前は生成も持ち越し投入もしない")
	check(not provider._worker_should_fill(), "解放前は補充判定も止まる")
	check(provider._genre_cap_for("A") == 4, "3単元なら単元ごとの上限は4問（ほかの単元に3問ずつ残す）")

	provider.release_slot_gate()
	check(not provider.is_slot_gate_closed(), "解放でゲートが開く")
	check(provider.fire_count == 1, "解放で生成を1回始める")
	check(fetcher.recorded.slice(0, 3) == (["A", "B", "C"] as Array[String]), "解放時に抽選単元を使用履歴へ記録")
	check(provider.buffer.size() == 1 and provider.buffer[0].genre == "A", "持ち越しはスロット単元の問題だけ使う")
	check(provider.generated_bank.list_question_texts("算数", 3, "普通").has("日本で一番長い川の名前は？"),
		"スロット外の持ち越し問題はプールに残す")
	check(provider._worker_should_fill(), "解放後は補充判定が動く")
	var need := provider._slot_units_by_need()
	check(need.size() == 3 and need[2] == "A", "補充は問題の少ない単元から並べる（%s）" % str(need))

	provider.release_slot_gate()
	check(provider.fire_count == 1, "二重に解放しても生成は増えない")

	# 先に届いた単元だけで埋まらないよう、ほかの単元に3問ずつ枠を残す（4・3・3）
	provider.buffer.assign([
		quiz("三角形の内角の和は何度？", "A"), quiz("正方形の辺の数はいくつ？", "A"),
		quiz("1時間は何分ですか？", "A"), quiz("100円玉が3枚でいくら？", "A"),
		quiz("ひらがなの「あ」はどれ？", "B"), quiz("春の七草をひとつ選んで", "B"),
		quiz("日本の首都はどこ？", "B"),
	])
	check(provider._genre_cap_for("B") == 3, "A=4問なら B は3問で止める")
	check(provider._genre_cap_for("C") == 3, "C には3問の枠が残る")
	check(provider._slot_units_by_need() == PackedStringArray(["C"]), "補充は枠が残っている C だけを狙う")
	provider._on_fetch_partial([quiz("磁石が引きつける金属はどれ？", "B")] as Array[QuizItem])
	check(provider._genre_count_in_round("B") == 3, "枠を超えた B の問題は採用しない")
	check(provider._dedup_retry_count == 0, "配分上限だけで弾いた候補は新規性の再試行に数えない")
	provider._dedup_retry_count = 2
	check(provider._genre_cap_for("B") == 5, "再試行が続いたら最低枠を1問に緩める")
	provider._dedup_retry_count = 4
	check(provider._genre_cap_for("B") == 6, "さらに続いたら最低枠をなくす")
	provider._dedup_retry_count = 0
	provider.buffer.clear()

	provider.end_round()
	check(provider.get_slot_units().is_empty(), "ラウンド終了でスロット単元を消す")
	dispose(provider)


func _check_non_slot_rounds() -> void:
	var provider := new_provider()
	provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
	check(not provider.is_slot_gate_closed() and provider.fire_count == 1, "スロットなしは従来どおりすぐ生成")
	check(provider._effective_genre_cap() == BufferedQuizProvider.GENRE_CAP_PER_ROUND, "スロットなしの上限は従来値")
	provider.end_round()

	provider.request_slot_round(PackedStringArray(["A", "B", "C"]))
	provider.begin_round("算数", 3, "普通", Constants.MODE_ENDLESS, 1)
	check(provider.get_slot_units().is_empty() and not provider.is_slot_gate_closed(), "エンドレスではスロットを使わない")
	provider.end_round()

	provider.llm_mode = "OFFLINE"
	provider.request_slot_round(PackedStringArray(["A", "B", "C"]))
	provider.begin_round("算数", 3, "普通", Constants.MODE_TEN, 10)
	check(provider.get_slot_units().is_empty() and not provider.is_slot_gate_closed(), "オフラインではスロットを使わない")
	provider.end_round()
	dispose(provider)


func _check_spread() -> void:
	var items: Array[QuizItem] = [
		quiz("a1", "A"), quiz("a2", "A"), quiz("a3", "A"), quiz("a4", "A"),
		quiz("b1", "B"), quiz("b2", "B"), quiz("b3", "B"),
		quiz("c1", "C"), quiz("c2", "C"), quiz("c3", "C"),
	]
	var spread := BufferedQuizProvider.spread_by_genre(items)
	var consecutive := false
	for i in range(1, spread.size()):
		consecutive = consecutive or spread[i].genre == spread[i - 1].genre
	check(spread.size() == items.size(), "並べ替えで問題数が変わらない")
	check(not consecutive, "4-3-3 の配分で同じ単元が連続しない")
