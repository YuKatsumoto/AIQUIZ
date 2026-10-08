extends SceneTree

func _initialize() -> void:
	# オートロードが登録されてからプロバイダを使うテストをロードする。
	await process_frame
	var suite = load("res://tools/fixtures/unit_slot_cases.gd").new()
	var failures: int = suite.run()
	print("[UnitSlotTest] %s" % ("ALL PASSED" if failures == 0 else "FAILED: %d" % failures))
	quit(0 if failures == 0 else 1)
