extends SceneTree

## 初回起動のウィンドウの大きさ（GameManager.startup_window_size）。全画面・最大化にせず、
## タイトルバーとタスクバーを除いた所に収まるいちばん大きい 16:9 を選ぶ。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/startup_window_size_unit.gd

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("STARTUP_WINDOW " + message)


func _run() -> void:
	var gm: Script = load("res://scripts/autoload/game_manager.gd")
	var deco := Vector2i(16, 39)
	# 1080p・拡大 100%（タスクバー 48px）：1920x1080 は枠の分はみ出すので 1600x900
	_check(gm.call("startup_window_size", Vector2i(1920, 1032), deco) == Vector2i(1600, 900), "1080p -> 1600x900")
	# 1080p・拡大 125%（物理ピクセルで 1920x1020）
	_check(gm.call("startup_window_size", Vector2i(1920, 1020), deco) == Vector2i(1600, 900), "1080p 125% -> 1600x900")
	# 1440p：1920x1080 がそのまま収まる
	_check(gm.call("startup_window_size", Vector2i(2560, 1392), deco) == Vector2i(1920, 1080), "1440p -> 1920x1080")
	# 1366x768 のノート PC：1280x720 は枠の分はみ出すので 1024x576
	_check(gm.call("startup_window_size", Vector2i(1366, 728), deco) == Vector2i(1024, 576), "1366x768 -> 1024x576")
	# どれも収まらない小さな画面：いちばん小さい候補
	_check(gm.call("startup_window_size", Vector2i(800, 560), deco) == Vector2i(960, 540), "tiny -> smallest")
	print("STARTUP_WINDOW ", "OK" if _failures.is_empty() else "FAIL %s" % str(_failures))
	quit(0 if _failures.is_empty() else 1)
