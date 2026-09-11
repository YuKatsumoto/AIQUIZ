extends SceneTree

func _initialize() -> void:
	await process_frame
	var suite = load("res://tools/fixtures/offline_loading_cases.gd").new()
	var failures: int = suite.run()
	print("[OfflineLoadingTest] %s" % ("ALL PASSED" if failures == 0 else "FAILED: %d" % failures))
	quit(0 if failures == 0 else 1)
