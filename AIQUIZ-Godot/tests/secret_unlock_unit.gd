extends Node

## シークレット（ママチャリ）の解放条件・保存・乗り物の番号の単体テスト。
## Run: Godot --headless --path . --script res://tests/secret_unlock_bootstrap.gd -- --fresh-profile
## --fresh-profile を外すと、ファイルへの保存と読み直しも確かめる（テスト用の別ファイルを使う）。

var _failures: Array[String] = []
var _signalled: Array[StringName] = []


func _ready() -> void:
	var saved_unlock_path := UnlockStore.path
	var saved_skin_path := PlayerSkinStore.path
	UnlockStore.path = "user://unlocks_unit_test.json"
	PlayerSkinStore.path = "user://player_skins_ride_unit_test.json"
	_remove(UnlockStore.path)
	_remove(PlayerSkinStore.path)
	UnlockStore.reset_memory()
	PlayerSkinStore.reset_memory()

	_test_condition()
	_test_locked_ride_is_rejected()
	_test_report_unlocks_once()
	_test_ride_selectable_after_unlock()
	_test_disk_round_trip()
	_test_game_signal()

	_remove(UnlockStore.path)
	_remove(PlayerSkinStore.path)
	UnlockStore.path = saved_unlock_path
	PlayerSkinStore.path = saved_skin_path
	UnlockStore.load_from_disk()
	PlayerSkinStore.load_from_disk()
	print("SECRET_UNLOCK_UNIT ", JSON.stringify({"passed": _failures.is_empty(), "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _remove(user_path: String) -> void:
	if FileAccess.file_exists(user_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))


func _test_condition() -> void:
	var endless := Constants.MODE_ENDLESS
	_check(UnlockStore.endless_run_qualifies(endless, "普通", 50), "endless normal 50 qualifies")
	_check(UnlockStore.endless_run_qualifies(endless, "難しい", 73), "endless hard 73 qualifies")
	_check(not UnlockStore.endless_run_qualifies(endless, "普通", 49), "49 is not enough")
	_check(not UnlockStore.endless_run_qualifies(endless, "簡単", 200), "easy never qualifies")
	_check(not UnlockStore.endless_run_qualifies(Constants.MODE_TEN, "難しい", 50), "ten-question mode never qualifies")
	_check(not UnlockStore.endless_run_qualifies(Constants.MODE_PRACTICE, "普通", 50), "practice never qualifies")
	for level: String in UnlockStore.MAMACHARI_DIFFICULTIES:
		_check(Constants.DIFFICULTY_LEVELS.has(level), "difficulty name %s exists in the game" % level)


func _test_locked_ride_is_rejected() -> void:
	_check(not UnlockStore.is_unlocked(UnlockStore.MAMACHARI), "starts locked")
	_check(not RideData.is_selectable(RideData.RIDE_MAMACHARI), "locked ride is not selectable")
	_check(RideData.is_selectable(RideData.RIDE_NONE), "no ride is always selectable")
	_check(not RideData.is_selectable(RideData.RIDE_COUNT) and not RideData.is_selectable(-1), "unknown ride ids are rejected")
	PlayerSkinStore.set_ride(1, RideData.RIDE_MAMACHARI)
	_check(PlayerSkinStore.get_ride(1) == RideData.RIDE_NONE, "store refuses a locked ride")


func _test_report_unlocks_once() -> void:
	var endless := Constants.MODE_ENDLESS
	_check(UnlockStore.report_endless_progress(endless, "普通", 49).is_empty(), "no unlock at 49")
	_check(UnlockStore.report_endless_progress(endless, "簡単", 50).is_empty(), "no unlock on easy")
	var newly := UnlockStore.report_endless_progress(endless, "普通", 50)
	_check(newly.size() == 1 and newly[0] == UnlockStore.MAMACHARI, "unlocks at 50")
	_check(UnlockStore.is_unlocked(UnlockStore.MAMACHARI), "is unlocked after reaching 50")
	_check(UnlockStore.is_unseen(UnlockStore.MAMACHARI), "new unlock is unseen")
	_check(UnlockStore.report_endless_progress(endless, "普通", 51).is_empty(), "does not unlock twice")
	UnlockStore.mark_seen(UnlockStore.MAMACHARI)
	_check(not UnlockStore.is_unseen(UnlockStore.MAMACHARI), "mark_seen clears the NEW state")
	_check(not UnlockStore.unlock(&"bogus"), "unknown ids are ignored")


func _test_ride_selectable_after_unlock() -> void:
	_check(RideData.is_selectable(RideData.RIDE_MAMACHARI), "unlocked ride is selectable")
	PlayerSkinStore.set_ride(1, RideData.RIDE_MAMACHARI)
	_check(PlayerSkinStore.get_ride(1) == RideData.RIDE_MAMACHARI, "store keeps an unlocked ride")
	var gs := QuizGameState.new(null)
	PlayerSkinStore.apply_to_state(gs)
	_check(gs.p1_ride == RideData.RIDE_MAMACHARI and gs.p2_ride == RideData.RIDE_NONE, "apply_to_state sets rides")


func _test_disk_round_trip() -> void:
	if UnlockStore.is_fresh_profile():
		return
	PlayerSkinStore.flush()
	UnlockStore.load_from_disk()
	_check(UnlockStore.is_unlocked(UnlockStore.MAMACHARI), "unlock survives a reload")
	_check(not UnlockStore.is_unseen(UnlockStore.MAMACHARI), "seen state survives a reload")
	PlayerSkinStore.load_from_disk()
	_check(PlayerSkinStore.get_ride(1) == RideData.RIDE_MAMACHARI, "ride survives a reload")
	# 解放の記録が無くなったら、保存してあった乗り物は「なし」に戻る。
	var file := FileAccess.open(UnlockStore.path, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	UnlockStore.load_from_disk()
	_check(not UnlockStore.is_unlocked(UnlockStore.MAMACHARI), "broken file means nothing is unlocked")
	PlayerSkinStore.load_from_disk()
	_check(PlayerSkinStore.get_ride(1) == RideData.RIDE_NONE, "ride falls back to none when its unlock is gone")


## QuizManager が正解のシグナルから解放を判定する（リプレイ・オンラインでは数えない）。
func _test_game_signal() -> void:
	UnlockStore.reset_memory()
	var gs := QuizManager.game_state
	var saved := {
		"mode": gs.mode, "difficulty": gs.difficulty, "score": gs.score, "player2_score": gs.player2_score,
		"num_players": gs.num_players, "is_replay": gs.is_replay, "net_online": gs.net_online,
	}
	QuizManager.secret_unlocked.connect(_on_secret_unlocked)
	gs.mode = Constants.MODE_ENDLESS
	gs.difficulty = "普通"
	gs.num_players = 1
	gs.player2_score = 0
	gs.net_online = false

	gs.score = 50
	gs.is_replay = true
	gs.correct_answer.emit()
	_check(_signalled.is_empty(), "replays do not unlock")
	gs.is_replay = false
	gs.net_online = true
	gs.correct_answer.emit()
	_check(_signalled.is_empty(), "online matches do not unlock")
	gs.net_online = false

	gs.score = 49
	gs.correct_answer.emit()
	_check(_signalled.is_empty(), "49 correct does not unlock")
	gs.player2_score = 50
	gs.correct_answer.emit()
	_check(_signalled.is_empty(), "player 2's score is ignored in a solo game")
	gs.num_players = 2
	gs.correct_answer.emit()
	_check(_signalled == [UnlockStore.MAMACHARI], "player 2 reaching 50 unlocks in a local 2-player game")
	gs.score = 60
	gs.correct_answer.emit()
	_check(_signalled.size() == 1, "the unlock is announced only once")

	QuizManager.secret_unlocked.disconnect(_on_secret_unlocked)
	for key: String in saved:
		gs.set(key, saved[key])


func _on_secret_unlocked(id: StringName) -> void:
	_signalled.append(id)
