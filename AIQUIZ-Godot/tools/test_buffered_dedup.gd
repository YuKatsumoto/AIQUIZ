extends SceneTree

## BufferedProvider dedup 統合シミュレーション（API なし）
func _initialize() -> void:
	var failures := 0
	var recent: Array[String] = ["3 + 5 は？", "日本の首都は？"]
	var play_hist: Array[String] = ["三角形の内角の和は？"]
	var buffer_qs: Array[String] = ["分数 1/2 + 1/4 は？"]
	var active: Array[String] = []
	for t in recent:
		if t not in active:
			active.append(t)
	for t in play_hist:
		if t not in active:
			active.append(t)
	for t in buffer_qs:
		if t not in active:
			active.append(t)
	failures += _assert_true(
		QuizDedup.is_similar_to_any("4 + 6 は？", active),
		"10問ラウンド相当: 数値差し替えを履歴+バッファでブロック"
	)
	failures += _assert_false(
		QuizDedup.is_similar_to_any("月は地球の衛星です。正しい？", active),
		"10問ラウンド相当: 別単元は通過"
	)
	# エンドレス30問相当: 履歴が play_history のみでも recent を含めれば同等
	var endless_active: Array[String] = recent.duplicate()
	for t in play_hist:
		if t not in endless_active:
			endless_active.append(t)
	failures += _assert_true(
		QuizDedup.is_similar_to_any("4 + 6 は？", endless_active),
		"エンドレス: recent_questions 統合で重複ブロック"
	)
	# 複数ラウンド分の履歴上限
	var entries: Array[Dictionary] = []
	for i in range(310):
		entries.append(QuizDedup.make_history_entry("ユニーク問題%d" % i, "単元A"))
	while entries.size() > 300:
		entries.pop_front()
	failures += _assert_true(entries.size() == 300, "cross-round 履歴300件上限")
	if failures == 0:
		print("[BufferedDedupSim] ALL PASSED")
		quit(0)
	else:
		print("[BufferedDedupSim] FAILED: %d assertion(s)" % failures)
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
