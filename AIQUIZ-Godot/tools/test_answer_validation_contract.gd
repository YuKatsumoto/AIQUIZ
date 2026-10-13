extends SceneTree

## 正解チェックの扱い（API なし）:
## - 不合格は正解番号を書き換えず、問題文で記録して以降の払い出しから外す
## - 結果なし・通信失敗は出題を止めないが validated にしない
## - 良問・悪問の評価は同じ教科・学年・難易度だけでまとめる
func _initialize() -> void:
	# --script では本体の型がオートロードより先にコンパイルされるため、起動後に load() する
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var validator = load("res://scripts/core/quiz_validator.gd").new()

	var item := QuizItem.create("3 + 4 は？", PackedStringArray(["5", "7", "8", "9"]), 1)
	failures += _check(not validator.is_rejected(item.q), "未判定の問題は不合格扱いにしない")
	validator._mark_rejected(item, "正解の不一致")
	failures += _check(validator.is_rejected("3 + 4 は?"), "不合格は記号違いの同じ問題文でも弾く")
	failures += _check(item.a == 1, "不合格でも正解番号は書き換えない")
	failures += _check(not item.validated, "不合格は validated にしない")

	for i in range(validator.MAX_REJECTED + 5):
		validator._mark_rejected(QuizItem.create("問題%d" % i, PackedStringArray(["a", "b"]), 0), "x")
	failures += _check(validator._rejected.size() == validator.MAX_REJECTED, "不合格の記録は上限で古いものから消す")
	validator.free()

	var optimizer = load("res://scripts/core/quiz_optimizer.gd").new()
	for ctx: Array in [["算数", 3, "普通"], ["理科", 5, "普通"], ["算数", 3, "普通"]]:
		optimizer._eval_queue.append({
			"quiz": QuizItem.create("%s%d" % [ctx[0], ctx[1]], PackedStringArray(["a", "b"]), 0, "", "GEMINI"),
			"_eval_ctx": {"subject": ctx[0], "grade": ctx[1], "difficulty": ctx[2]},
		})
	var batch: Array[Dictionary] = optimizer._take_same_context_batch(10)
	failures += _check(batch.size() == 2, "先頭と同じ教科・学年・難易度だけを1回にまとめる")
	failures += _check(optimizer._eval_queue.size() == 1 \
			and optimizer._eval_queue[0]["_eval_ctx"]["subject"] == "理科", "別の教科は次の回に残す")
	optimizer.free()

	print("test_answer_validation_contract: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)


func _check(ok: bool, label: String) -> int:
	print("%s %s" % ["OK  " if ok else "FAIL", label])
	return 0 if ok else 1
