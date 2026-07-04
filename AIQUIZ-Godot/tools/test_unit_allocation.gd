extends SceneTree

## _allocate_units_to_batches / compose_prompt 回帰テスト（ヘッドレス実行用）
## 10問モードの「バッチ間で単元が重複しない」保証を検証する
func _initialize() -> void:
	# --script モードではオートロード登録前にグローバルクラスの静的コンパイルが走るため、
	# 1フレーム待ってから動的ロードする（LiveConfigManager 等の識別子解決のため）
	await process_frame
	var failures := 0
	var fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(fetcher)

	# ── 算数3年（6単元）を3バッチ×4問に割当 → 2単元ずつ・重複なし ──
	var batches = fetcher._allocate_units_to_batches("算数", 3, 3, 4)
	failures += _assert_true(batches.size() == 3, "バッチ数=3")
	var seen := {}
	var dup_found := false
	var total_units := 0
	for b in batches:
		failures += _assert_true(b.size() >= 1, "各バッチに担当単元が1つ以上ある")
		total_units += b.size()
		for u in b:
			if seen.has(u):
				dup_found = true
			seen[u] = true
	failures += _assert_false(dup_found, "算数3年: バッチ間で単元が重複しない")
	failures += _assert_true(total_units == 6, "算数3年: 全6単元が使われる（実際: %d）" % total_units)

	# ── 理科5年（4単元）を3バッチに割当 → 全単元使用・重複なし ──
	var batches2 = fetcher._allocate_units_to_batches("理科", 5, 3, 4)
	var seen2 := {}
	var dup2 := false
	for b in batches2:
		for u in b:
			if seen2.has(u):
				dup2 = true
			seen2[u] = true
	failures += _assert_false(dup2, "理科5年: バッチ間で単元が重複しない")
	failures += _assert_true(seen2.size() == 4, "理科5年: 全4単元が使われる")

	# ── 補充フェッチ相当: 1バッチのみ ──
	var batches3 = fetcher._allocate_units_to_batches("国語", 4, 1, 4)
	failures += _assert_true(batches3.size() == 1 and batches3[0].size() >= 1, "1バッチ割当も動作する")

	# ── compose_prompt: 複数単元 + 解説省略モード ──
	var hist: Array[String] = ["9+6はいくつ？"]
	var units: PackedStringArray = PackedStringArray(batches[0])
	var prompt = fetcher.compose_prompt("算数", 3, "普通", 4, hist, false, units, true)
	failures += _assert_true(prompt.contains("空文字列"), "defer_explanations: 解説省略指示を含む")
	failures += _assert_true(prompt.contains("均等に割り振る"), "複数単元: 均等配分指示を含む")
	failures += _assert_true(prompt.contains(str(units[0])), "担当単元名がプロンプトに含まれる")
	failures += _assert_true(prompt.contains("セルフ検証"), "出力前セルフ検証指示を含む")

	# ── compose_prompt: 通常モード（解説あり） ──
	var prompt2 = fetcher.compose_prompt("算数", 3, "普通", 4, hist, false, units, false)
	failures += _assert_true(prompt2.contains("50〜100文字程度"), "通常モード: 解説生成指示を含む")

	if failures == 0:
		print("[UnitAllocationTest] ALL PASSED")
		quit(0)
	else:
		print("[UnitAllocationTest] FAILED: %d assertion(s)" % failures)
		quit(1)


func _assert_true(cond: bool, label: String) -> int:
	if not cond:
		push_error("FAIL (expected true): %s" % label)
		return 1
	print("OK: %s" % label)
	return 0


func _assert_false(cond: bool, label: String) -> int:
	if cond:
		push_error("FAIL (expected false): %s" % label)
		return 1
	print("OK: %s" % label)
	return 0
