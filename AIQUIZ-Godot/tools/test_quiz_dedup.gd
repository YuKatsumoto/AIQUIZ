extends SceneTree

## QuizDedup 回帰テスト（ヘッドレス実行用）
func _initialize() -> void:
	var failures := 0
	failures += _assert_true(
		QuizDedup.is_semantically_similar("3 + 5 は？", "4 + 6 は？"),
		"numeric swap should match"
	)
	failures += _assert_true(
		QuizDedup.is_semantically_similar("半径と直径の関係は？", "直径は半径の何倍？"),
		"rephrased concept should match"
	)
	failures += _assert_false(
		QuizDedup.is_semantically_similar("日本の首都は？", "三角形の内角の和は？"),
		"unrelated topics should not match"
	)
	failures += _assert_true(
		QuizDedup.is_duplicate_answer_concept("2×3は？", "4×5は？", "6", "6"),
		"same answer similar concept"
	)
	var blocklist: Array = ["3 + 5 は？", "日本の首都は？"]
	failures += _assert_true(
		QuizDedup.is_similar_to_any("4 + 6 は？", blocklist),
		"blocklist should catch semantic dup"
	)
	failures += _assert_false(
		QuizDedup.is_similar_to_any("月は地球の衛星です。正しい？", blocklist),
		"blocklist should allow distinct question"
	)
	var core := QuizDedup.extract_core_concept("乾電池2個を使って豆電球を光らせるとき")
	failures += _assert_false(core.contains("2"), "core concept strips digits")
	if failures == 0:
		print("[QuizDedupTest] ALL PASSED")
		quit(0)
	else:
		print("[QuizDedupTest] FAILED: %d assertion(s)" % failures)
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
