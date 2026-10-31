extends Node

## 新しいチュートリアルの土台（docs/new_tutorial/foundation_design.md 12章）のうち、本編側（担当 A）の単体テスト。
## MatchRules の写し、スタンプと初回の案内の保存、QuizGameState のルールの反映（ハートの下限・REPORT_ONLY・
## world_speed・さく・入力の停止・記録しない・問題の差し替え・海・置き直し）と、本編のモードが変わらないことを確かめる。
## 段階4（docs/new_tutorial/phase4_design.md 2.7）：slow_auto_speed と練習の自動の速さ、壁を落とす・着地、
## 練習の負け（practice_round_lost が1回・ゲームオーバーの画面へ進まない）、生き返りと見た目を戻す合図、
## PlayerController の見た目の戻し（爆散・かまれたまま・壁のアウト）、ハートの表示・観客・カメラの道具。
## 段階5（docs/new_tutorial/phase5_design.md 3.5）：finish_with_clear・real_result_screens の写し、本番と同じ始まり方
## （WAITING_START → 空撮 → カウントダウン）、練習の問題を使い切ると CLEAR、本番どおりの GAME OVER、評価を送らないこと、
## HUD の「問題: 1/3」とリザルトのカード（「正解 / 3問」・コーチの部品・ボタンの行き先・練習の合図）、本編のカードが変わらないこと。
## 段階6（docs/new_tutorial/phase6_design.md 2.6）：CPU の入力口（移動・ジャンプ・エモート・押し合い）、のこぎりの
## REPORT_ONLY と止めて片づけるところ、practice_make_ghost とゴーストの合図・様子、さくとゴーストの吹き飛ばし、
## finish_with_goal のゴールレースとスコアタワー（practice_set_score・判定の合図・サドンデスへ行かない）、2人のカードと HUD。
## 段階7（docs/new_tutorial/phase7_design.md 1.2）：練習のオンラインの見せ方（practice_online_look。呼び名・自分の色・2人のカード・
## 練習の「たいせんを やめますか？」）、④のカタログと台本（練習試合のルール・問題）。
## 設定ファイルは user://test_practice_unit/ に書く（プレイヤーの設定には触れない）。
## 結果：res://artifacts/practice_unit/unit.json
## 実行：tests/practice_unit_bootstrap.gd から（オートロードができてから読み込む）。

const OUT := "res://artifacts/practice_unit/"
const STORE := "user://test_practice_unit"
const DT := 1.0 / 60.0

class TestProvider extends QuizProvider:
	var submitted: Array[bool] = []
	var ended := 0
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, correct: bool) -> void:
		submitted.append(correct)
	func end_round() -> void:
		ended += 1

## 段階5：HUD のリザルトのカードのボタンが呼ぶ監督の代わり（HUD は親の practice_director を見る）。
class StubDirector extends Node:
	var retries := 0
	var leaves := 0
	func retry_run() -> void:
		retries += 1
	func leave_to_menu() -> void:
		leaves += 1

class CountingOptimizer extends QuizOptimizer:
	var calls := 0
	func evaluate_history(_history: Array[Dictionary], _subject: String, _grade: int, _difficulty: String) -> void:
		calls += 1

class CountingAnalytics extends PlayerAnalytics:
	var calls := 0
	func record(_quiz: QuizItem, _response_time: float, _correct: bool,
			_chosen_index: int, _subject: String, _grade: int, _difficulty: String) -> void:
		calls += 1

class CountingRatings extends FirebaseRatings:
	var calls := 0
	func send_rating(_quiz: QuizItem, _good: bool, _subject: String, _grade: int, _difficulty: String, _reason: String = "") -> void:
		calls += 1

var checks := 0
var failures: Array[String] = []
var _nodes: Array[Node] = []
## HUD をこのノードの子にしてテストするとき、HUD がゲーム画面の監督として見る（段階5）。
var practice_director: Node = null
var _optimizer: CountingOptimizer
var _analytics: CountingAnalytics
var _ratings: CountingRatings


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		var line := label if str(detail).is_empty() else "%s: %s" % [label, str(detail)]
		failures.append(line)
		push_error(line)


func run() -> void:
	await get_tree().process_frame
	var quiz_manager: Node = get_tree().root.get_node("QuizManager")
	var real_optimizer: Variant = quiz_manager.get("quiz_optimizer")
	var real_analytics: Variant = quiz_manager.get("player_analytics")
	var real_ratings: Variant = quiz_manager.get("firebase_ratings")
	_optimizer = CountingOptimizer.new()
	_analytics = CountingAnalytics.new()
	_ratings = CountingRatings.new()
	_nodes.append_array([_optimizer, _analytics, _ratings])
	quiz_manager.set("quiz_optimizer", _optimizer)
	quiz_manager.set("player_analytics", _analytics)
	quiz_manager.set("firebase_ratings", _ratings)

	_match_rules()
	_stamps()
	_normal_modes_unchanged()
	_start_round()
	_hp_rules()
	_report_only()
	_world_speed()
	_fence()
	_input_lock()
	_records()
	_quizzes_finished()
	_ocean()
	_placement()
	_two_player_rules()
	_reset()
	_slow_auto_speed()
	_wall_drop()
	_practice_loss()
	_revive_signals()
	_ui_tools()
	await _player_visual_reset()
	_real_start_flow()
	_finish_with_clear()
	_real_result_loss()
	await _hud_result_card()
	_cpu_input()
	_cpu_push()
	_saw_report_only()
	_saw_parking()
	_make_ghost()
	_ghost_fence()
	_finish_with_goal()
	await _duo_hud()
	await _online_look()

	quiz_manager.set("quiz_optimizer", real_optimizer)
	quiz_manager.set("player_analytics", real_analytics)
	quiz_manager.set("firebase_ratings", real_ratings)
	for node in _nodes:
		node.free()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT + "unit.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("PRACTICE_UNIT " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ helpers

func _quiz(text: String, choices: Array, answer := 0) -> QuizItem:
	return QuizItem.create(text, PackedStringArray(choices), answer, "練習の解説", "PRACTICE")


func _list(items: Array) -> Array[QuizItem]:
	var list: Array[QuizItem] = []
	for item: Variant in items:
		list.append(item as QuizItem)
	return list


func _two(text := "1 + 1 = ?") -> QuizItem:
	return _quiz(text, ["2", "3"], 0)


func _four(text := "2 + 2 = ?") -> QuizItem:
	return _quiz(text, ["4", "5", "6", "7"], 0)


func _state() -> QuizGameState:
	var provider := TestProvider.new()
	_nodes.append(provider)
	var gs := QuizGameState.new(provider)
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	return gs


func _practice(players := 1, rules: MatchRules = null, quizzes: Array[QuizItem] = [], bosses: Array[int] = []) -> QuizGameState:
	var gs := _state()
	gs.start_practice_round(quizzes, players, rules if rules != null else MatchRules.new(), bosses)
	return gs


func _rules(speed := 0.0) -> MatchRules:
	var rules := MatchRules.new()
	rules.world_speed = speed
	return rules


func _door_x(gs: QuizGameState, door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[door]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x


func _frames(gs: QuizGameState, count: int, axis := Vector2.ZERO, jump := false, emote := 0) -> void:
	for _i in range(count):
		gs.update(DT, axis, Vector2.ZERO, jump, false, emote, 0)


## 条件が立つまで進める（最大 limit フレーム）。立ったら true。
func _frames_until(gs: QuizGameState, limit: int, axis: Vector2, done: Callable) -> bool:
	for _i in range(limit):
		gs.update(DT, axis, Vector2.ZERO, false, false, 0, 0)
		if done.call():
			return true
	return false


# ------------------------------------------------------------------ MatchRules

func _match_rules() -> void:
	var fresh := MatchRules.new()
	check(not fresh.hp_enabled and fresh.hp_floor == 0, "rules default: no hearts")
	check(fresh.mistakes == MatchRules.Mistakes.NORMAL and fresh.ocean == MatchRules.Ocean.NORMAL, "rules default: normal mistakes and ocean")
	check(fresh.world_speed < 0.0 and not fresh.fence_enabled and not fresh.input_locked, "rules default: auto speed, no fence, input free")
	check(not fresh.slow_auto_speed, "rules default: normal auto speed pace")
	check(not fresh.record_results and not fresh.ghost_ride_enabled, "rules default: no records, no ghost ride")
	check(not fresh.show_score and not fresh.finish_with_clear and not fresh.real_result_screens, "rules default: no score, no clear, no real result screens")
	check(fresh.fence_min == Vector2(-10.0, -6.0) and fresh.fence_max == Vector2(10.0, 8.0), "rules default fence")
	check(fresh.saw == MatchRules.Saw.NORMAL and not fresh.finish_with_goal, "rules default: normal saw, no goal")
	var rules := MatchRules.new()
	rules.hp_enabled = true
	rules.hp_floor = 1
	rules.mistakes = MatchRules.Mistakes.REPORT_ONLY
	rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
	rules.saw_enabled = true
	rules.saw = MatchRules.Saw.REPORT_ONLY
	rules.local_push_enabled = true
	rules.scroll_out_enabled = true
	rules.ghost_ride_enabled = true
	rules.world_speed = 2.5
	rules.slow_auto_speed = true
	rules.fence_enabled = true
	rules.fence_min = Vector2(-3.0, -2.0)
	rules.fence_max = Vector2(4.0, 5.0)
	rules.input_locked = true
	rules.record_results = true
	rules.show_score = true
	rules.finish_with_clear = true
	rules.real_result_screens = true
	rules.finish_with_goal = true
	var copy := rules.duplicate_rules()
	check(copy != rules, "duplicate is a new object")
	for property: Dictionary in rules.get_script().get_script_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		check(rules.get(name) != fresh.get(name), "test sets a non-default value", name)
		check(copy.get(name) == rules.get(name), "duplicate copies", name)
	copy.hp_floor = 2
	copy.fence_max = Vector2(1.0, 1.0)
	check(rules.hp_floor == 1 and rules.fence_max == Vector2(4.0, 5.0), "changing the copy keeps the original")


# ------------------------------------------------------------------ stamps

func _read_settings(gm: Node) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gm.settings_path))
	return parsed if parsed is Dictionary else {}


func _stamps() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE))
	var gm: Node = get_tree().root.get_node("GameManager")
	var real_path: String = gm.settings_path
	gm.settings_path = STORE + "/settings.json"
	if FileAccess.file_exists(gm.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.settings_path))
	gm._load_user_settings()
	check(gm.practice_stamps.is_empty() and not gm.practice_intro_seen, "no file: no stamps, intro not seen")
	check(not gm.has_practice_stamp("c1") and not gm.practice_stamp_star("c1"), "no file: c1 has no stamp")
	gm.mark_practice_stamp("c1", false)
	check(gm.has_practice_stamp("c1") and not gm.practice_stamp_star("c1"), "c1 stamped without a star")
	var saved := _read_settings(gm)
	check(saved.get("practice_stamps", {}) == {"c1": {"star": false}}, "stamp saved", saved.get("practice_stamps"))
	gm.mark_practice_stamp("c1", true)
	check(gm.practice_stamp_star("c1"), "star added")
	gm.mark_practice_stamp("c1", false)
	check(gm.practice_stamp_star("c1"), "star is never removed")
	gm.mark_practice_stamp("c2", true)
	gm.mark_practice_stamp("", true)
	check(not gm.has_practice_stamp(""), "empty course id ignored")
	check(not bool(_read_settings(gm).get("practice_intro_seen", true)), "intro not seen saved as false")
	gm.mark_practice_intro_seen()
	saved = _read_settings(gm)
	check(bool(saved.get("practice_intro_seen", false)), "intro seen saved")
	check(saved.get("practice_stamps", {}) == {"c1": {"star": true}, "c2": {"star": true}}, "stamps saved with stars", saved.get("practice_stamps"))
	gm.practice_stamps = {}
	gm.practice_intro_seen = false
	gm._load_user_settings()
	check(gm.practice_stamp_star("c1") and gm.practice_stamp_star("c2") and gm.practice_intro_seen, "stamps and intro read back")
	# 壊れた項目は捨て、ほかの設定のキーは保存し直しても残る。
	var broken := FileAccess.open(gm.settings_path, FileAccess.WRITE)
	broken.store_string(JSON.stringify({"practice_stamps": {"c1": true, "c3": {"star": 1}, "c4": {}}, "practice_intro_seen": true, "keep_me": 7}))
	broken.close()
	gm._load_user_settings()
	check(not gm.has_practice_stamp("c1"), "malformed stamp dropped")
	check(gm.practice_stamp_star("c3") and gm.has_practice_stamp("c4") and not gm.practice_stamp_star("c4"), "stamps normalized", gm.practice_stamps)
	gm.mark_practice_stamp("c5", false)
	saved = _read_settings(gm)
	check(int(saved.get("keep_me", 0)) == 7 and saved.has("graphics_quality"), "other settings kept on save", saved)
	gm.settings_path = real_path
	gm._load_user_settings()


# ------------------------------------------------------------------ 本編のモード

func _normal_modes_unchanged() -> void:
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	ten.target_count = 10
	check(ten.practice_rules == null and ten.allows_ghost_ride(), "ten: no practice rules, ghost ride allowed")
	check(ten.uses_hp() and ten.is_boss_index(9) and not ten.is_boss_index(8), "ten: hearts and the 10th boss wall")
	check(ten.num_choices_for_index(9) == 4 and ten.num_choices_for_index(3) == 2, "ten: choice counts")
	check(ten._is_fixed_count_mode() and ten._records_results(), "ten: fixed count, records results")
	ten.saw_transport_enabled = true
	check(ten.uses_saw_chase() and not ten.is_scroll_out_death_enabled(), "ten 2P: saw chase without scroll-out")
	var ghost := GhostSharkRideController.new()
	ghost.game_state = ten
	check(ghost._base_mode_is_eligible(false, false), "ten 2P: ghost ride eligible")
	ghost.free()
	var endless := _state()
	endless.mode = Constants.MODE_ENDLESS
	check(endless.uses_hp() and not endless._is_fixed_count_mode(), "endless: hearts, not fixed count")
	endless.reset_to_menu()
	check(endless.mode == Constants.MODE_ENDLESS, "reset_to_menu keeps a normal mode")


# ------------------------------------------------------------------ 入口

func _start_round() -> void:
	var gs := _state()
	var states: Array = []
	var finished := [0]
	gs.state_changed.connect(func(state: String) -> void: states.append(state))
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	gs.start_practice_round([], 1, _rules())
	check(gs.mode == Constants.MODE_PRACTICE and gs.practice_rules != null, "empty round: practice mode")
	check(gs.target_count == 0 and gs.current_quiz == null, "empty round: no quiz")
	check(gs.game_state == Constants.STATE_PLAYING and states == [Constants.STATE_PLAYING], "empty round: PLAYING once", states)
	check(finished[0] == 0, "empty round: quizzes_finished not emitted")
	check(is_equal_approx(gs.player_x, 0.0) and is_equal_approx(gs.player_local_z, -8.0) and gs.p1_alive, "1P start position like start_game")
	check(gs.p1_hp == QuizGameState.MAX_HP and not gs.uses_hp(), "hearts full, hearts off by default")
	check(not gs.allows_ghost_ride() and not gs._records_results(), "practice: no ghost ride, no records by default")
	check(gs._is_fixed_count_mode(), "practice counts its quizzes like ten")
	# 壁がない間は前へ走っても止まらない（見えない壁がない）。
	_frames(gs, 360, Vector2(0.0, 1.0))
	check(gs.player_z > gs.wall_z + 1.0, "no quiz: no invisible wall", gs.player_z - gs.wall_z)
	var waiting := _state()
	var loaded: Array = []
	waiting.quiz_loaded.connect(func(quiz: QuizItem) -> void: loaded.append(quiz))
	var quizzes: Array[QuizItem] = [_two(), _four()]
	waiting.start_practice_round(quizzes, 2, _rules(), [1], Constants.STATE_WAITING_START)
	check(waiting.game_state == Constants.STATE_WAITING_START and waiting.num_players == 2, "waiting start, 2 players")
	check(loaded.size() == 1 and loaded[0] == quizzes[0] and waiting.current_quiz == quizzes[0], "first quiz loaded once")
	check(waiting.target_count == 2 and waiting.is_boss_index(1) and not waiting.is_boss_index(0), "boss index from the script")
	check(waiting.num_choices_for_index(0) == 2 and waiting.num_choices_for_index(1) == 4, "choice count follows the quiz")
	check(is_equal_approx(waiting.player_x, 1.5) and is_equal_approx(waiting.player2_x, -1.5), "2P start positions")
	var serial := waiting.practice_round_serial
	waiting.start_practice_round(quizzes, 2, _rules())
	check(waiting.practice_round_serial == serial + 1 and waiting.current_index == 0, "each round has a new serial")


# ------------------------------------------------------------------ ハート

func _hp_rules() -> void:
	var off := _practice(1, _rules(), _list([_two()]))
	check(not off.uses_hp(), "hp_enabled false: no hearts")
	var rules := _rules()
	rules.hp_enabled = true
	rules.hp_floor = 1
	var quizzes: Array[QuizItem] = [_two("a"), _two("b"), _two("c"), _two("d")]
	var gs := _practice(1, rules, quizzes)
	check(gs.uses_hp(), "hp_enabled true: hearts")
	var events: Array = []
	gs.health_changed.connect(func(p: int, old: int, value: int) -> void: events.append([p, old, value]))
	for _i in range(3):
		gs.player_x = _door_x(gs, 1)
		gs.resolve_collision(true, false)
	check(gs.p1_hp == 1 and gs.p1_alive, "hp_floor 1: hearts never below 1", gs.p1_hp)
	check(events == [[1, 3, 2], [1, 2, 1]], "hp_floor: only real drops reported", events)
	check(gs.current_index == 3 and gs.game_state == Constants.STATE_PLAYING, "wrong answers still advance (normal mistakes)")
	gs.practice_set_hp(1, 0)
	check(gs.p1_hp == 1, "practice_set_hp respects the floor")
	gs.practice_set_hp(1, 3)
	check(gs.p1_hp == 3 and events.back() == [1, 1, 3], "practice_set_hp emits health_changed", events)


# ------------------------------------------------------------------ REPORT_ONLY

func _report_only() -> void:
	var rules := _rules()
	rules.hp_enabled = true
	rules.mistakes = MatchRules.Mistakes.REPORT_ONLY
	var gs := _practice(1, rules, _list([_two()]))
	var contacts: Array = []
	var health: Array = []
	var corrects := [0]
	var finished := [0]
	gs.practice_wall_contact.connect(func(p: int, door: int, correct: bool) -> void: contacts.append([p, door, correct]))
	gs.health_changed.connect(func(p: int, old: int, value: int) -> void: health.append([p, old, value]))
	gs.correct_answer.connect(func() -> void: corrects[0] += 1)
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	# 違うドア：手前へ戻すだけ。
	gs.practice_place_player(1, _door_x(gs, 1), 0.0)
	gs.practice_place_current_wall(2.0)
	var touched := _frames_until(gs, 120, Vector2(0.0, 1.0), func() -> bool: return not contacts.is_empty())
	check(touched and contacts[0] == [1, 1, false], "wrong door reported", contacts)
	check(gs.p1_hp == 3 and health.is_empty() and gs.p1_alive, "wrong door: hearts and body unchanged")
	check(not gs.choice_locked and gs.current_index == 0 and gs.current_quiz != null, "wrong door: question still open")
	check(is_equal_approx(gs.player_z, gs.wall_z - QuizGameState.PRACTICE_REPORT_BACKOFF), "wrong door: back 1.5 m", gs.wall_z - gs.player_z)
	# 押し続けると、また着いて、また知らせる。
	_frames_until(gs, 120, Vector2(0.0, 1.0), func() -> bool: return contacts.size() >= 2)
	check(contacts.size() == 2 and contacts[1] == [1, 1, false], "touching again reports again", contacts)
	# ドアの間の壁。
	contacts.clear()
	gs.practice_place_player(1, 0.0, 0.0)
	gs.practice_place_current_wall(2.0)
	_frames_until(gs, 120, Vector2(0.0, 1.0), func() -> bool: return not contacts.is_empty())
	check(not contacts.is_empty() and contacts[0][1] < 0 and not contacts[0][2], "wall between doors reported (door < 0)", contacts)
	check(gs.p1_hp == 3 and gs.p1_alive, "wall between doors: no damage")
	# 正解：本編と同じ流れ。用意した問題が尽きても終わらない。
	contacts.clear()
	gs.practice_place_player(1, _door_x(gs, 0), 0.0)
	gs.practice_place_current_wall(2.0)
	_frames_until(gs, 120, Vector2(0.0, 1.0), func() -> bool: return not contacts.is_empty())
	_frames(gs, 10, Vector2(0.0, 1.0))
	check(contacts == [[1, 0, true]], "correct door reported once", contacts)
	check(corrects[0] == 1 and gs.current_index == 1 and gs.p1_hp == 3, "correct door advances")
	check(finished[0] == 1 and gs.current_quiz == null and gs.game_state == Constants.STATE_PLAYING, "last quiz: finished, no clear")
	# 2人・NORMAL：違うドアで待つ人の通知は1回だけ。
	var duo_rules := _rules()
	duo_rules.hp_enabled = true
	var duo := _practice(2, duo_rules, _list([_two()]))
	var duo_contacts: Array = []
	duo.practice_wall_contact.connect(func(p: int, door: int, correct: bool) -> void: duo_contacts.append([p, door, correct]))
	duo.practice_place_player(1, _door_x(duo, 1), 0.0)
	duo.practice_place_player(2, _door_x(duo, 0), -6.0)
	duo.practice_place_current_wall(2.0)
	_frames(duo, 60, Vector2(0.0, 1.0))
	check(duo_contacts == [[1, 1, false]], "normal mistakes: one report per wall", duo_contacts)
	check(duo.p1_hp == 2 and duo.current_index == 0, "normal mistakes: heart lost, waits for the other player")


# ------------------------------------------------------------------ world_speed

func _world_speed() -> void:
	var stopped := _practice(1, _rules(0.0), _list([_two()]))
	var scroll := stopped.world_scroll_z
	var z := stopped.player_z
	_frames(stopped, 60)
	check(stopped.world_scroll_z == scroll and stopped.player_z == z, "world_speed 0: conveyor and walls stop")
	var fixed := _practice(1, _rules(2.0), _list([_two()]))
	var local := fixed.player_local_z
	_frames(fixed, 60)
	check(absf(fixed.world_scroll_z - 2.0) < 0.01 and absf(fixed.player_local_z - local) < 0.001, "world_speed 2: 2 m/s", fixed.world_scroll_z)
	var auto := _practice(1, _rules(-1.0), _list([_two()]))
	_frames(auto, 60)
	check(auto.world_scroll_z > 0.1, "world_speed < 0: automatic speed", auto.world_scroll_z)


# ------------------------------------------------------------------ さく

func _fence() -> void:
	var rules := _rules()
	rules.fence_enabled = true
	var gs := _practice(1, rules)
	var touches: Array = []
	gs.practice_fence_touched.connect(func(p: int) -> void: touches.append(p))
	_frames(gs, 1)
	check(is_equal_approx(gs.player_local_z, -6.0) and touches == [1], "start behind the fence is pulled in", gs.player_local_z)
	touches.clear()
	gs.practice_place_player(1, 9.5, 0.0)
	_frames(gs, 30, Vector2(1.0, 0.0))
	check(is_equal_approx(gs.player_x, 10.0) and touches == [1], "fence x max, reported once while pushing", [gs.player_x, touches])
	_frames(gs, 2)
	_frames(gs, 5, Vector2(1.0, 0.0))
	check(touches == [1, 1], "pushing again reports again", touches)
	_frames(gs, 180, Vector2(-1.0, 0.0))
	check(is_equal_approx(gs.player_x, -10.0), "fence x min", gs.player_x)
	_frames(gs, 120, Vector2(0.0, 1.0))
	check(is_equal_approx(gs.player_local_z, 8.0), "fence z max", gs.player_local_z)
	_frames(gs, 240, Vector2(0.0, -1.0))
	check(is_equal_approx(gs.player_local_z, -6.0) and gs.p1_alive and not gs.p1_fall_committed, "fence z min keeps the player on the floor", gs.player_local_z)
	rules.fence_enabled = false
	_frames(gs, 10, Vector2(0.0, -1.0))
	check(gs.player_local_z < -6.5, "fence off: free again", gs.player_local_z)


# ------------------------------------------------------------------ 入力の停止

func _input_lock() -> void:
	var rules := _rules()
	rules.input_locked = true
	var gs := _practice(1, rules)
	gs.practice_place_player(1, 0.0, 0.0)
	var jumps := gs.p1_jump_count
	_frames(gs, 30, Vector2(1.0, 1.0), true, 18)
	check(is_equal_approx(gs.player_x, 0.0) and is_equal_approx(gs.player_local_z, 0.0), "input_locked: no movement")
	check(gs.p1_jump_count == jumps and gs.player_y == 0.0 and gs.p1_emote == 0, "input_locked: no jump or emote")
	rules.input_locked = false
	_frames(gs, 30, Vector2(1.0, 0.0), false, 18)
	check(gs.player_x > 1.0 and gs.p1_emote == 18, "input free again", [gs.player_x, gs.p1_emote])


# ------------------------------------------------------------------ 記録

func _reset_counters() -> void:
	_optimizer.calls = 0
	_analytics.calls = 0
	_ratings.calls = 0


func _records() -> void:
	for hp in [true, false]:
		_reset_counters()
		var rules := _rules()
		rules.hp_enabled = hp
		var gs := _practice(1, rules, _list([_two("a"), _two("b")]))
		var provider := gs.provider as TestProvider
		var pace := gs.wall_speed_planner.pace
		gs.player_x = _door_x(gs, 0)
		gs.resolve_collision(true, false)
		check(gs.current_index == 1 and gs.quiz_history.size() == 1, "answer recorded in quiz_history (hp=%s)" % hp)
		check(provider.submitted.is_empty() and _optimizer.calls == 0 and _analytics.calls == 0, "record_results false: nothing sent (hp=%s)" % hp,
			[provider.submitted, _optimizer.calls, _analytics.calls])
		check(gs.wall_speed_planner.pace == pace, "record_results false: wall speed pace kept (hp=%s)" % hp)
		gs.rate_quiz_at(0, true)
		check(_ratings.calls == 0 and gs.quiz_history[0].get("rated") == "good", "record_results false: rating kept locally only")
		# 違うドアでアウト（ハートなし）：ゲームオーバーでも送らない。
		if not hp:
			gs.player_x = _door_x(gs, 1)
			gs.resolve_collision(true, false)
			check(gs.game_state == Constants.STATE_GAME_OVER and provider.submitted.is_empty() and _optimizer.calls == 0, "record_results false: game over sends nothing")
	_reset_counters()
	var on := _rules()
	on.hp_enabled = true
	on.record_results = true
	var sent := _practice(1, on, _list([_two()]))
	sent.player_x = _door_x(sent, 0)
	sent.resolve_collision(true, false)
	sent.rate_quiz_at(0, true)
	check((sent.provider as TestProvider).submitted == [true] and _optimizer.calls >= 1 and _analytics.calls == 1 and _ratings.calls == 1,
		"record_results true: results sent", [(sent.provider as TestProvider).submitted, _optimizer.calls, _analytics.calls, _ratings.calls])


# ------------------------------------------------------------------ 問題の差し替え

func _quizzes_finished() -> void:
	var gs := _practice(1, _rules(), _list([_two("a")]))
	var finished := [0]
	var loaded: Array = []
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	gs.quiz_loaded.connect(func(quiz: QuizItem) -> void: loaded.append(quiz))
	gs.player_x = _door_x(gs, 0)
	gs.resolve_collision(true, false)
	check(finished[0] == 1 and gs.current_quiz == null and gs.game_state == Constants.STATE_PLAYING, "out of quizzes: finished, still playing")
	check(gs.current_index == 1 and gs.current_wall_index == 1 and gs.goal_z == 0.0, "out of quizzes: no goal race")
	var next: Array[QuizItem] = [_four("b"), _two("c")]
	gs.set_practice_quizzes(next, [0])
	check(gs.target_count == 3 and gs.current_quiz == next[0] and loaded.back() == next[0], "set_practice_quizzes continues the round")
	check(gs.num_choices == 4 and gs.is_boss_index(1) and not gs.is_boss_index(2), "boss index counted from current_index")
	check(gs.quiz_history.size() == 1 and finished[0] == 1, "history kept, finished not repeated")
	# 出ている問題の差し替え（まだ答えていない壁）も、同じ壁のまま入れかわる。
	var swap: Array[QuizItem] = [_two("d")]
	gs.set_practice_quizzes(swap)
	check(gs.current_quiz == swap[0] and gs.current_index == 1 and gs.target_count == 2 and not gs.is_boss_index(1), "swap the open question")
	gs.set_practice_quizzes([])
	check(gs.current_quiz == null and gs.target_count == 1 and finished[0] == 1, "empty swap: no wall, no finished signal")


# ------------------------------------------------------------------ 海

func _fall_into_ocean(gs: QuizGameState) -> bool:
	gs.practice_place_player(1, QuizGameState.FLOOR_HALF_WIDTH + 1.0, 0.0)
	return _frames_until(gs, 300, Vector2.ZERO, func() -> bool: return gs.p1_waiting_for_shark)


func _ocean() -> void:
	var rules := _rules()
	rules.hp_enabled = true
	rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
	var gs := _practice(1, rules, _list([_two()]))
	var bites: Array = []
	gs.practice_ocean_bitten.connect(func(p: int) -> void: bites.append(p))
	check(_fall_into_ocean(gs), "falls into the ocean")
	gs.complete_ocean_shark_attack(1)
	check(bites == [1] and gs.p1_alive and gs.p1_waiting_for_shark, "bite reported, still waiting in the sea", bites)
	check(gs.p1_hp == 3 and gs.game_state == Constants.STATE_PLAYING and gs.quiz_history.is_empty(), "bite: not out, no game over")
	gs.practice_place_player(1, 0.0, 0.0)
	check(not gs.p1_waiting_for_shark and not gs.p1_fall_committed and is_equal_approx(gs.player_x, 0.0) and gs.player_y == 0.0, "placed back on the floor")
	var normal_rules := _rules()
	normal_rules.hp_enabled = true
	var normal := _practice(1, normal_rules, _list([_two()]))
	check(_fall_into_ocean(normal), "falls into the ocean (normal)")
	normal.complete_ocean_shark_attack(1)
	check(not normal.p1_alive and normal.p1_hp == 0 and normal.game_state == Constants.STATE_GAME_OVER, "normal ocean: out")
	normal.practice_revive(1)
	check(normal.p1_alive and not normal.p1_shark_killed and not normal.p1_waiting_for_shark and normal.game_over_timer == 0.0, "practice_revive")


# ------------------------------------------------------------------ 置き直し

func _placement() -> void:
	var gs := _practice(1, _rules(), _list([_two()]))
	gs.practice_place_player(1, -2.5, 3.0)
	check(is_equal_approx(gs.player_x, -2.5) and is_equal_approx(gs.player_local_z, 3.0), "place player (x, conveyor z)")
	gs.practice_place_current_wall(12.0)
	check(is_equal_approx(gs.wall_z - gs.player_z, 12.0) and is_equal_approx(gs.player_local_z, 3.0), "place wall 12 m ahead, player stays on the belt",
		[gs.wall_z - gs.player_z, gs.player_local_z])
	gs.practice_place_current_wall(40.0)
	check(is_equal_approx(gs.wall_z - gs.player_z, 40.0) and is_equal_approx(gs.player_local_z, 3.0), "place wall farther (conveyor moves back)")
	var duo := _practice(2, _rules())
	duo.practice_place_player(2, 4.0, -2.0)
	duo.practice_place_current_wall(10.0)
	check(is_equal_approx(duo.player2_x, 4.0) and is_equal_approx(duo.player2_local_z, -2.0), "P2 placement kept when the wall moves")


# ------------------------------------------------------------------ 2人のルール

func _two_player_rules() -> void:
	var rules := _rules()
	var gs := _practice(2, rules)
	gs.saw_transport_enabled = true
	check(not gs.uses_saw_chase() and not gs.uses_local_push() and not gs.is_scroll_out_death_enabled(), "2P practice: all off by default")
	rules.saw_enabled = true
	rules.local_push_enabled = true
	rules.scroll_out_enabled = true
	check(gs.uses_saw_chase() and gs.uses_local_push() and gs.is_scroll_out_death_enabled(), "2P practice: rules switch them on")
	var ghost := GhostSharkRideController.new()
	ghost.game_state = gs
	check(not ghost._base_mode_is_eligible(false, false), "ghost ride off in practice")
	var on := _rules()
	on.ghost_ride_enabled = true
	gs.set_practice_rules(on)
	check(gs.allows_ghost_ride() and ghost._base_mode_is_eligible(false, false), "set_practice_rules: ghost ride on")
	check(not gs.uses_saw_chase() and not gs.uses_local_push(), "set_practice_rules replaces the rules")
	ghost.free()
	var solo := _practice(1, rules)
	solo.saw_transport_enabled = true
	check(not solo.uses_saw_chase() and not solo.uses_local_push(), "1P practice: no saw, no push")


# ------------------------------------------------------------------ 戻る

func _reset() -> void:
	var gs := _practice(2, _rules(), _list([_two(), _four()]), [1])
	gs.reset_to_menu()
	check(gs.practice_rules == null and gs.practice_boss_indices.is_empty(), "reset_to_menu clears the practice rules")
	check(gs.mode == Constants.MODE_TEN and gs.game_state == Constants.STATE_MENU, "reset_to_menu returns to the ten-question mode")
	check(gs.allows_ghost_ride() and gs._records_results() and not gs.uses_saw_chase(), "after reset: normal rules")
	var again := _practice(1, _rules())
	again.mode = Constants.MODE_TEN
	again.start_game()
	check(again.practice_rules == null and again.uses_hp(), "start_game drops leftover practice rules")
	again.set_practice_rules(_rules())
	check(again.practice_rules == null, "set_practice_rules outside practice is ignored")


# ------------------------------------------------------------------ 段階4：自動の速さ

## 練習の問題でも自動の速さを計算する。slow_auto_speed は調子を一番遅い値で計算し、保存されている調子は変えない。
func _slow_auto_speed() -> void:
	var boss := _quiz("くだものは どれ？", ["えんぴつ", "くつ", "りんご", "いす"], 2)
	var normal := _practice(1, _rules(-1.0), _list([boss]), [0])
	var pace := normal.wall_speed_planner.pace
	check(not is_equal_approx(normal._active_wall_speed, GameTuning.WALL_SPEED_AUTO_DEFAULT), "practice quiz: automatic speed is computed", normal._active_wall_speed)
	var budget := normal.wall_speed_planner.last_budget_seconds
	var slow_rules := _rules(-1.0)
	slow_rules.slow_auto_speed = true
	var slow := _practice(1, slow_rules, _list([boss]), [0])
	check(slow.wall_speed_planner.last_budget_seconds > budget + 0.5, "slow_auto_speed: more seconds to the wall",
		[budget, slow.wall_speed_planner.last_budget_seconds])
	check(slow._active_wall_speed < normal._active_wall_speed, "slow_auto_speed: slower wall", [normal._active_wall_speed, slow._active_wall_speed])
	check(slow.wall_speed_planner.pace == pace and normal.wall_speed_planner.pace == pace, "slow_auto_speed: stored pace kept")
	# 台本 1-7 の問題は1枚あたり約8秒（WallSpeedPlanner の最短 7.9 秒の前後）。
	var finals := _list([_quiz("3 + 2 = ?", ["5", "6"], 0), _quiz("ねこの なきごえは？", ["ワン", "ニャー"], 1), boss])
	var final := _practice(1, _rules(-1.0), finals, [2])
	var seconds := (final.wall_z - final.wall_contact_distance() - final.player_z) / final._active_wall_speed
	check(seconds >= 7.5 and seconds <= 10.0, "final quizzes: about 8 s per wall", seconds)
	# 置き直すと、新しい距離で計算し直す（同じ秒数で届く）。
	final.practice_place_current_wall(22.0)
	var placed := (final.wall_z - final.wall_contact_distance() - final.player_z) / final._active_wall_speed
	check(absf(placed - seconds) < 0.05, "placing the wall keeps the seconds to the wall", [seconds, placed])
	# 練習の決まった速さのときは、自動の速さを使わない。
	var fixed := _practice(1, _rules(1.6), finals)
	var scroll := fixed.world_scroll_z
	_frames(fixed, 60)
	check(absf(fixed.world_scroll_z - scroll - 1.6) < 0.01, "fixed practice speed ignores the automatic speed", fixed.world_scroll_z - scroll)


# ------------------------------------------------------------------ 段階4：壁を落とす

func _wall_drop() -> void:
	var gs := _practice(1, _rules(0.0), _list([_two()]))
	var requested: Array = []
	var landed: Array = []
	var contacts: Array = []
	gs.practice_wall_drop_requested.connect(func(index: int) -> void: requested.append(index))
	gs.practice_wall_landed.connect(func(index: int) -> void: landed.append(index))
	gs.practice_wall_contact.connect(func(p: int, door: int, correct: bool) -> void: contacts.append([p, door, correct]))
	gs.practice_place_player(1, _door_x(gs, 0), 0.0)
	var serial := gs.practice_quizzes_serial
	gs.practice_drop_current_wall(22.0)
	check(is_equal_approx(gs.wall_z - gs.player_z, 22.0) and is_equal_approx(gs.player_local_z, 0.0), "drop: wall 22 m ahead, player stays on the belt",
		gs.wall_z - gs.player_z)
	check(requested == [0] and gs.is_practice_wall_airborne(0), "drop: the screen is asked to drop the current wall", requested)
	# 落ちている途中の壁には、目の前でも当たらない。
	gs.practice_drop_current_wall(0.3)
	_frames(gs, 10)
	check(contacts.is_empty() and gs.current_index == 0, "airborne wall: no contact", contacts)
	gs.notify_practice_wall_landed(0)
	check(landed == [0] and not gs.is_practice_wall_airborne(0), "landed once (screen)", landed)
	gs.notify_practice_wall_landed(0)
	check(landed == [0], "a second landing is ignored", landed)
	_frames(gs, 1)
	check(contacts == [[1, 0, true]] and gs.current_index == 1, "landed wall: contact again", contacts)
	check(gs.practice_quizzes_serial == serial, "dropping does not count as a quiz change")
	# 着地の知らせがなくても（ヘッドレス）、決まった秒数で着地したことにする。
	var lone := _practice(1, _rules(0.0), _list([_two()]))
	var lone_landed: Array = []
	lone.practice_wall_landed.connect(func(index: int) -> void: lone_landed.append(index))
	lone.practice_drop_current_wall(22.0)
	var limit_frames := int(QuizGameState.PRACTICE_WALL_AIRBORNE_LIMIT / DT)
	_frames(lone, limit_frames - 5)
	check(lone_landed.is_empty() and lone.is_practice_wall_airborne(0), "not landed before the time limit")
	_frames(lone, 10)
	check(lone_landed == [0] and not lone.is_practice_wall_airborne(0), "landed at the time limit without a screen", lone_landed)
	# 問題がなければ落とさない。本編の壁は落ちない。やり直しで落ちている印は消える。
	var empty := _practice(1, _rules(0.0))
	var empty_requests: Array = []
	empty.practice_wall_drop_requested.connect(func(index: int) -> void: empty_requests.append(index))
	empty.practice_drop_current_wall(12.0)
	check(empty_requests.is_empty() and not empty.is_practice_wall_airborne(0), "no quiz: nothing to drop")
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.notify_practice_wall_dropping(0)
	ten.practice_drop_current_wall(10.0)
	check(not ten.is_practice_wall_airborne(0), "normal mode: walls are never airborne")
	lone.practice_drop_current_wall(22.0)
	lone.start_practice_round(_list([_two()]), 1, _rules(0.0))
	check(not lone.is_practice_wall_airborne(0), "a new round clears airborne walls")
	lone.set_practice_quizzes(_list([_four()]), [0])
	check(lone.practice_quizzes_serial > 0 and lone.num_choices == 4 and lone.is_boss_index(0), "set_practice_quizzes counts the change for the screen")


# ------------------------------------------------------------------ 段階4：練習の負け

func _practice_loss() -> void:
	var rules := _rules(0.0)
	rules.hp_enabled = true
	var quizzes := _list([_two("a"), _two("b"), _two("c"), _two("d")])
	var gs := _practice(1, rules, quizzes)
	var lost: Array = []
	var finished := [0]
	gs.practice_round_lost.connect(func(reason: StringName) -> void: lost.append(reason))
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	for _i in range(3):
		gs.player_x = _door_x(gs, 1)
		gs.resolve_collision(true, false)
	check(not gs.p1_alive and gs.p1_hp == 0 and gs.game_state == Constants.STATE_GAME_OVER, "3 wrong doors: out, the round stops")
	check(lost == [&"hp"], "practice_round_lost once (hp)", lost)
	check(not gs.message_text.contains("GAME OVER") and gs.status_text.is_empty(), "no GAME OVER text, no menu hint", [gs.message_text, gs.status_text])
	check(not gs.is_elimination_result_pending() and not gs.result_presentation_active, "no result ceremony, no lasso")
	_frames(gs, 300)
	check(lost.size() == 1 and not gs.message_text.contains("GAME OVER") and finished[0] == 0, "still one loss after the death plays out", [lost, gs.message_text])
	check(gs.is_wall_death_sequence_complete() and gs.game_state == Constants.STATE_GAME_OVER, "the wall death plays out like the real game")
	var hud: Node = (load("res://scripts/ui/gameplay_hud.gd") as Script).new()
	hud.set("game_state", gs)
	check(bool(hud.call("_is_practice_loss")), "HUD keeps the game over card hidden for a practice loss")
	hud.free()
	# GAME_OVER のままでも、start_practice_round でやり直せる。
	var resets: Array = []
	gs.practice_player_reset.connect(func(p: int) -> void: resets.append(p))
	gs.start_practice_round(quizzes, 1, rules)
	check(gs.game_state == Constants.STATE_PLAYING and gs.p1_alive and gs.p1_hp == 3 and not gs.p1_wall_impact and gs.game_over_timer == 0.0,
		"restart from GAME_OVER", [gs.game_state, gs.p1_hp])
	check(resets == [1], "the restart asks the screen to reset the player", resets)
	for _i in range(3):
		gs.player_x = _door_x(gs, 1)
		gs.resolve_collision(true, false)
	check(lost == [&"hp", &"hp"], "the new round can be lost again (once)", lost)
	# 海（本番どおり）
	var sea_rules := _rules(0.0)
	sea_rules.hp_enabled = true
	var sea := _practice(1, sea_rules, _list([_two()]))
	var sea_lost: Array = []
	sea.practice_round_lost.connect(func(reason: StringName) -> void: sea_lost.append(reason))
	check(_fall_into_ocean(sea), "normal ocean: falls in")
	sea.complete_ocean_shark_attack(1)
	check(sea_lost == [&"ocean"] and sea.game_state == Constants.STATE_GAME_OVER and sea.p1_shark_killed, "shark: practice_round_lost (ocean)", sea_lost)
	# ハートなしで違うドア：すぐアウト
	var plain := _practice(1, _rules(0.0), _list([_two()]))
	var plain_lost: Array = []
	plain.practice_round_lost.connect(func(reason: StringName) -> void: plain_lost.append(reason))
	plain.player_x = _door_x(plain, 1)
	plain.resolve_collision(true, false)
	check(plain_lost == [&"hp"] and plain.game_state == Constants.STATE_GAME_OVER and not plain.message_text.contains("GAME OVER"), "no hearts: wrong door loses at once", plain_lost)
	# 2人：2人ともアウトになって1回だけ
	var duo := _practice(2, rules.duplicate_rules(), _list([_two("a"), _two("b"), _two("c"), _two("d")]))
	var duo_lost: Array = []
	duo.practice_round_lost.connect(func(reason: StringName) -> void: duo_lost.append(reason))
	duo.practice_place_player(2, _door_x(duo, 1), 0.0)
	for _i in range(3):
		duo.player_x = _door_x(duo, 1)
		duo.player2_x = _door_x(duo, 1)
		duo.resolve_collision(true, true)
	check(duo_lost == [&"hp"] and not duo.p1_alive and not duo.p2_alive, "2 players: one loss when both are out", duo_lost)
	# 本編の10問のゲームオーバーは今までどおり（練習の合図は出ない）。
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 1
	ten.target_count = 4
	ten.game_state = Constants.STATE_PLAYING
	ten._reset_health()
	for i in range(4):
		ten.quiz_list.append(_two("ten %d" % i))
	ten.load_current_quiz()
	var ten_lost := [0]
	ten.practice_round_lost.connect(func(_reason: StringName) -> void: ten_lost[0] += 1)
	for _i in range(3):
		ten.player_x = _door_x(ten, 1)
		ten.resolve_collision(true, false)
	check(ten.game_state == Constants.STATE_GAME_OVER and ten.message_text.begins_with("GAME OVER") and ten_lost[0] == 0,
		"ten: GAME OVER as before, no practice signal", ten.message_text)
	var ten_hud: Node = (load("res://scripts/ui/gameplay_hud.gd") as Script).new()
	ten_hud.set("game_state", ten)
	check(not bool(ten_hud.call("_is_practice_loss")), "ten: HUD shows the game over card as before")
	ten_hud.free()


# ------------------------------------------------------------------ 段階4：生き返りと見た目を戻す合図

func _revive_signals() -> void:
	var rules := _rules(0.0)
	rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
	var gs := _practice(1, rules, _list([_two()]))
	var resets: Array = []
	gs.practice_player_reset.connect(func(p: int) -> void: resets.append(p))
	check(_fall_into_ocean(gs), "bite: falls in")
	resets.clear()
	gs.complete_ocean_shark_attack(1)
	check(gs.is_practice_bitten(1) and gs.p1_waiting_for_shark and gs.p1_alive, "REPORT_AFTER_BITE: bitten, still waiting in the sea")
	_frames(gs, 30)
	check(gs.is_practice_bitten(1) and gs.p1_waiting_for_shark and gs.game_state == Constants.STATE_PLAYING, "a bitten player keeps waiting")
	gs.practice_revive(1)
	check(not gs.is_practice_bitten(1) and resets == [1], "practice_revive clears the bite and asks for a reset", resets)
	gs.practice_place_player(1, 0.0, 0.0)
	check(not gs.p1_waiting_for_shark and gs.player_y == 0.0 and resets == [1, 1], "placed back on the floor, reset again", resets)
	_frames(gs, 10)
	check(gs.p1_alive and not gs.p1_fall_committed and gs.player_y == 0.0, "standing on the floor after the revive")
	# アウトの人を置いても見た目は戻さない（practice_revive が戻す）。
	var normal := _practice(1, _rules(0.0), _list([_two()]))
	var normal_resets: Array = []
	normal.practice_player_reset.connect(func(p: int) -> void: normal_resets.append(p))
	normal.player_x = _door_x(normal, 1)
	normal.resolve_collision(true, false)
	normal.practice_place_player(1, 0.0, 0.0)
	check(not normal.p1_alive and normal_resets.is_empty(), "placing a player who is out does not reset the look", normal_resets)
	normal.practice_revive(1)
	check(normal.p1_alive and not normal.p1_wall_impact and normal.game_over_timer == 0.0 and normal_resets == [1], "practice_revive after a wall death", normal_resets)
	# 2人のやり直しは2人とも戻す。
	var duo := _practice(2, _rules(0.0))
	var duo_resets: Array = []
	duo.practice_player_reset.connect(func(p: int) -> void: duo_resets.append(p))
	duo.start_practice_round([], 2, _rules(0.0))
	check(duo_resets == [1, 2], "2 players: the restart resets both", duo_resets)


# ------------------------------------------------------------------ 段階4：ハートの表示・観客・カメラ

func _ui_tools() -> void:
	var rules := _rules(0.0)
	rules.hp_enabled = true
	rules.hp_floor = 1
	var gs := _practice(1, rules, _list([_two()]))
	var hud: Control = (load("res://scripts/ui/player_health_hud.gd") as Script).new()
	hud.call("setup", gs)
	gs.practice_set_hp(1, 1)
	var lost: Array = hud.get("_lost_flash")
	check(float(lost[0][1]) > 0.0 and float(lost[0][2]) > 0.0 and float(lost[0][0]) == 0.0, "practice: the lost hearts' frames blink", lost)
	var queue: Array = (hud.get("_queues") as Array)[0]
	queue.clear()
	gs.practice_set_hp(1, 3)
	check(queue.size() == 2 and int(queue[0].from) == 1 and int(queue[1].to) == 3 and bool(queue[0].get("practice_gain", false)),
		"practice: 1 → 3 hearts come back one at a time", queue)
	hud.call("play_practice_intro", 1)
	check(float((hud.get("_intro_time") as Array)[0]) == 0.0, "hearts intro starts")
	var hidden := _practice(1, _rules(0.0))
	var hidden_hud: Control = (load("res://scripts/ui/player_health_hud.gd") as Script).new()
	hidden_hud.call("setup", hidden)
	hidden_hud.call("play_practice_intro", 1)
	check(float((hidden_hud.get("_intro_time") as Array)[0]) < 0.0, "no hearts intro while hearts are off")
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 1
	var ten_hud: Control = (load("res://scripts/ui/player_health_hud.gd") as Script).new()
	ten_hud.call("setup", ten)
	ten._set_player_hp(1, 2)
	var ten_queue: Array = (ten_hud.get("_queues") as Array)[0]
	check(ten_queue.size() == 1 and not (ten_queue[0] as Dictionary).has("practice_gain") and float((ten_hud.get("_lost_flash") as Array)[0][2]) == 0.0,
		"ten: hearts move as before", ten_queue)
	for node: Node in [hud, hidden_hud, ten_hud]:
		node.free()
	# 観客：ウェーブと歓声
	var cues := CrowdCues.new()
	cues.update(0.1, gs)
	check(cues.wave_time() < 0.0, "no wave before the cue")
	cues.start_wave()
	check(cues.wave_time() >= 0.0, "the crowd wave starts on cue")
	var started := cues.wave_started
	cues.update(0.5, gs)
	cues.start_wave()
	check(cues.wave_started == started and cues.wave_time() > 0.4, "a running wave is not restarted")
	cues.on_celebrate()
	check(cues.cue == CrowdCues.Cue.GOAL and cues.cue_team == 0, "celebrate: the crowd cheers like a goal")
	# カメラ：向けて戻す、入り
	var cam: Node3D = (load("res://scripts/world/camera_controller.gd") as Script).new()
	var eye := Vector3(0.0, 3.0, -5.6)
	var target := Vector3(0.0, 1.0, 8.0)
	var point := Vector3(-10.5, 0.0, 6.0)
	var still: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(still[0] == eye and still[1] == target, "camera: nothing changes without a practice cue")
	cam.call("practice_look", point, 1.0)
	cam.call("_advance_practice_camera", 0.5)
	var half: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	cam.call("_advance_practice_camera", 0.6)
	var full: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	var full_target := target.lerp(point, 0.6)
	check(half[0] == eye and half[1].x < 0.0 and half[1].x > full_target.x, "camera look: turns smoothly toward the point", [half[1], full_target])
	check(full[1].is_equal_approx(full_target) and full[0] == eye, "camera look: turned (eye stays)", full[1])
	cam.call("practice_release", 0.0)
	var released: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(released[1].is_equal_approx(target), "camera release: back to the normal view")
	cam.call("practice_intro", 2.0)
	var intro_start: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(intro_start[0].y > eye.y + 8.0 and intro_start[0].z < eye.z - 8.0, "camera intro: starts high above the stage", intro_start[0])
	cam.call("_advance_practice_camera", 1.0)
	var intro_mid: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(intro_mid[0].y > eye.y and intro_mid[0].y < intro_start[0].y, "camera intro: comes down", intro_mid[0])
	cam.call("_advance_practice_camera", 1.1)
	var intro_end: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(intro_end[0].is_equal_approx(eye) and intro_end[1].is_equal_approx(target), "camera intro: ends at the normal view", intro_end[0])
	# 画：いまの画から決めた目と注視点へ移って止まり、release でいつものカメラへ戻る。
	var frame_eye := Vector3(-8.5, 9.5, -3.0)
	var frame_target := Vector3(-14.0, -7.5, 8.0)
	cam.call("practice_frame", frame_eye, frame_target, 1.0)
	cam.call("_advance_practice_camera", 0.5)
	var moving: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(moving[0].x < 0.0 and moving[0].x > frame_eye.x and moving[0].y > eye.y and moving[0].y < frame_eye.y, "camera frame: moves smoothly", moving[0])
	cam.call("_advance_practice_camera", 0.6)
	var framed: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(framed[0].is_equal_approx(frame_eye) and framed[1].is_equal_approx(frame_target), "camera frame: arrives", framed)
	cam.call("_advance_practice_camera", 3.0)
	var held: PackedVector3Array = cam.call("_apply_practice_camera", eye + Vector3(0.0, 0.0, 4.0), target + Vector3(0.0, 0.0, 4.0))
	check(held[0].is_equal_approx(frame_eye) and held[1].is_equal_approx(frame_target), "camera frame: stays while the player moves", held)
	cam.call("practice_release", 1.0)
	cam.call("_advance_practice_camera", 0.5)
	var leaving: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(leaving[0].x < 0.0 and leaving[0].x > frame_eye.x, "camera frame release: moves back smoothly", leaving[0])
	cam.call("_advance_practice_camera", 0.6)
	var back: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(back[0].is_equal_approx(eye) and back[1].is_equal_approx(target) and int(cam.get("_practice_frame_mode")) == 0, "camera frame release: back to the normal view", back)
	# 海面の近くの低い画（床の外）へ移る・戻るときも、目は床の土台の中を通らない。
	var low_eye := Vector3(-13.8, -5.0, -1.5)
	var low_target := Vector3(-15.5, -9.0, 7.0)
	var through_floor := []
	for leg: int in range(2):
		if leg == 0:
			cam.call("practice_frame", low_eye, low_target, 1.0)
		else:
			cam.call("practice_release", 1.0)
		for _step in range(21):
			cam.call("_advance_practice_camera", 0.05)
			var pose: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
			var over_floor := absf(pose[0].x) < StageConstants.FLOOR_HALF_WIDTH and pose[0].z > StageConstants.FLOOR_BACK_Z
			if over_floor and pose[0].y < StageConstants.FLOOR_TOP_Y + 1.0:
				through_floor.append(pose[0])
		if leg == 0:
			var low: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
			check(low[0].is_equal_approx(low_eye) and low[1].is_equal_approx(low_target), "camera frame: arrives at the low view by the sea", low)
	check(through_floor.is_empty(), "camera frame: never passes through the floor", through_floor)
	var home: PackedVector3Array = cam.call("_apply_practice_camera", eye, target)
	check(home[0].is_equal_approx(eye) and int(cam.get("_practice_frame_mode")) == 0, "camera frame: back home from the low view", home)
	cam.free()


# ------------------------------------------------------------------ 段階4：PlayerController の見た目の戻し

func _all_visible(nodes: Array) -> bool:
	for node: Variant in nodes:
		if node is Node3D and is_instance_valid(node) and not (node as Node3D).visible:
			return false
	return true


func _any_visible(nodes: Array) -> bool:
	for node: Variant in nodes:
		if node is Node3D and is_instance_valid(node) and (node as Node3D).visible:
			return true
	return false


func _player_visual_reset() -> void:
	var holder := Node3D.new()
	holder.name = "PracticeVisualHolder"
	add_child(holder)
	var pc := PlayerController.new()
	holder.add_child(pc)
	await get_tree().process_frame
	pc.set_hat(1, HatData.HAT_TOP_HAT)
	# 海でかまれた（REPORT_AFTER_BITE）：戻されるまで爆散したまま、床へ戻すと立った姿。
	var rules := _rules(0.0)
	rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
	var gs := _practice(1, rules, _list([_two()]))
	gs.practice_player_reset.connect(pc.practice_reset_player)
	check(_fall_into_ocean(gs), "visual: falls in")
	pc.update_from_state(gs)
	pc.begin_ocean_shark_explosion(1)
	gs.complete_ocean_shark_attack(1)
	for _i in range(5):
		_frames(gs, 1)
		pc.update_from_state(gs)
	var meshes: Array = pc.p1_parts.get("meshes", [])
	check(pc.has_player_death_exploded(1) and not pc._p1_explosion_bodies.is_empty() and not _any_visible(meshes), "bitten: the body stays exploded")
	gs.practice_place_player(1, 0.0, 0.0)
	pc.update_from_state(gs)
	var hat_meshes: Array = pc.p1_parts.get("hat_meshes", [])
	check(not pc.has_player_death_exploded(1) and pc._p1_explosion_bodies.is_empty() and _all_visible(meshes), "placed back: the body stands again")
	check(not hat_meshes.is_empty() and _all_visible(hat_meshes) and is_instance_valid(pc._p1_hat_node) and pc._p1_hat_node.visible, "placed back: the hat is back")
	# 壁のアウト（ラグドール → 爆散）から start_practice_round でやり直す。
	var wall := _practice(1, _rules(0.0), _list([_two(), _two()]))
	wall.practice_player_reset.connect(pc.practice_reset_player)
	wall.player_x = _door_x(wall, 1)
	wall.resolve_collision(true, false)
	var ragdolled := false
	for _i in range(170):
		_frames(wall, 1)
		pc.update_from_state(wall)
		ragdolled = ragdolled or not pc._p1_ragdoll.is_empty()
	check(ragdolled and pc.has_player_death_exploded(1) and not _any_visible(meshes), "wall death: ragdoll then scatter")
	wall.start_practice_round(_list([_two()]), 1, _rules(0.0))
	pc.update_from_state(wall)
	meshes = pc.p1_parts.get("meshes", [])
	hat_meshes = pc.p1_parts.get("hat_meshes", [])
	check(not pc.has_player_death_exploded(1) and pc._p1_ragdoll.is_empty() and pc._p1_explosion_bodies.is_empty(), "restart: no ragdoll, no pieces")
	check(_all_visible(meshes) and _all_visible(hat_meshes) and pc._p1_hat_node.visible, "restart: standing with the hat on")
	holder.free()


# ------------------------------------------------------------------ 段階5：コース②のミニ本番

## 台本②の 2-4 の問題（3枚目はボス壁。画面の左から 赤「さかな」・オレンジ「とり」・緑「いぬ」・青「ねこ」）。
func _mini_run_quizzes() -> Array[QuizItem]:
	return _list([
		QuizItem.create("5 - 2 = ?", PackedStringArray(["4", "3"]), 1, "5 から 2 を ひくと 3", "PRACTICE"),
		QuizItem.create("あかい くだものは？", PackedStringArray(["りんご", "バナナ"]), 0, "りんごは あかい", "PRACTICE"),
		QuizItem.create("そらを とぶ のは？", PackedStringArray(["ねこ", "いぬ", "とり", "さかな"]), 2, "とりは つばさで そらを とぶ", "PRACTICE"),
	])


## ミニ本番のルール（本番どおり・自動の速さ・右上の数字・CLEAR・本番どおりの画面。記録はしない）。
func _mini_run_rules() -> MatchRules:
	var rules := MatchRules.new()
	rules.hp_enabled = true
	rules.show_score = true
	rules.finish_with_clear = true
	rules.real_result_screens = true
	return rules


## 段階5（docs/new_tutorial/phase5_design.md 3.2）：開始の画面 → Enter → 空撮 3.8秒 → カウントダウン 4.99秒 → PLAYING。
func _real_start_flow() -> void:
	var gs := _state()
	var states: Array = []
	gs.state_changed.connect(func(state: String) -> void: states.append(state))
	var quizzes := _mini_run_quizzes()
	gs.start_practice_round(quizzes, 1, _mini_run_rules(), [2], Constants.STATE_WAITING_START)
	check(states == [Constants.STATE_WAITING_START] and gs.current_quiz == quizzes[0], "mini run: the round waits at the start screen", states)
	check(gs.target_count == 3 and gs.is_boss_index(2) and gs.num_choices_for_index(2) == 4, "mini run: 3 walls, the 3rd is the boss")
	var scroll := gs.world_scroll_z
	_frames(gs, 120, Vector2(1.0, 1.0), true)
	check(gs.game_state == Constants.STATE_WAITING_START and gs.world_scroll_z == scroll, "mini run: nothing starts before Enter")
	check(is_equal_approx(gs.player_x, 0.0) and is_equal_approx(gs.player_local_z, -8.0) and gs.player_y == 0.0, "mini run: the player waits at the 1P start",
		[gs.player_x, gs.player_local_z, gs.player_y])
	gs.trigger_start()
	check(gs.game_state == Constants.STATE_FLYOVER and gs.flyover_total_walls == 3 and is_equal_approx(gs.flyover_duration, 3.8),
		"Enter: the flyover over the 3 walls (3.8 s)", [gs.flyover_total_walls, gs.flyover_duration])
	var frames := 0
	while gs.game_state == Constants.STATE_FLYOVER and frames < 600:
		_frames(gs, 1)
		frames += 1
	check(gs.game_state == Constants.STATE_COUNTDOWN and absf(frames * DT - 3.8) < 0.05, "the flyover lasts 3.8 s", frames * DT)
	check(is_equal_approx(gs.countdown_timer, QuizGameState.COUNTDOWN_SECONDS) and is_equal_approx(QuizGameState.COUNTDOWN_SECONDS, 4.99),
		"the countdown starts from 4.99 s", gs.countdown_timer)
	frames = 0
	while gs.game_state == Constants.STATE_COUNTDOWN and frames < 600:
		_frames(gs, 1)
		frames += 1
	check(gs.game_state == Constants.STATE_PLAYING and absf(frames * DT - 4.99) < 0.05, "the countdown lasts 4.99 s", frames * DT)
	check(states == [Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN, Constants.STATE_PLAYING],
		"state_changed for every step of the real start", states)
	check(gs.world_scroll_z == scroll, "the conveyor waits until GO")
	_frames(gs, 30)
	check(gs.world_scroll_z > scroll + 0.1, "after GO the walls come at the automatic speed", gs.world_scroll_z - scroll)


## 段階5（3.1・3.3）：finish_with_clear で最後の壁を抜けたら本番どおりの CLEAR。数は練習の数、記録も評価も送らない。
func _finish_with_clear() -> void:
	_reset_counters()
	var gs := _state()
	var quizzes := _mini_run_quizzes()
	gs.start_practice_round(quizzes, 1, _mini_run_rules(), [2])
	var provider := gs.provider as TestProvider
	var states: Array = []
	var finished := [0]
	var cleared: Array = []
	gs.state_changed.connect(func(state: String) -> void: states.append(state))
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	gs.game_cleared.connect(func(message: String) -> void: cleared.append(message))
	# 壁1 正解、壁2 ミス（ハートが1つ減る）、ボス壁 正解。
	for door: int in [1, 1]:
		gs.player_x = _door_x(gs, door)
		gs.resolve_collision(true, false)
	check(gs.current_index == 2 and gs.score == 1 and gs.p1_hp == 2 and gs.num_choices == 4, "mini run: two walls passed, one heart lost",
		[gs.current_index, gs.score, gs.p1_hp])
	gs.player_x = _door_x(gs, 2)
	gs.resolve_collision(true, false)
	check(gs.game_state == Constants.STATE_CLEAR and states.back() == Constants.STATE_CLEAR and states.count(Constants.STATE_CLEAR) == 1,
		"finish_with_clear: the boss wall clears the round", states)
	check(finished[0] == 0 and cleared.size() == 1, "finish_with_clear: no practice_quizzes_finished, game_cleared once", [finished[0], cleared.size()])
	check(gs.score == 2 and gs.current_quiz == null and gs.rating_target_quiz == quizzes[2], "clear: score 2, no wall left, the boss quiz is rated")
	check(gs.message_text.contains("3問完走") and gs.message_text.contains("2/3") and gs.message_text.contains(quizzes[2].e)
		and not gs.message_text.contains("/10"), "clear text: the practice count and the last explanation", gs.message_text)
	check(gs.status_text.is_empty(), "clear: no [R] menu hint in practice", gs.status_text)
	check(gs.goal_z == 0.0 and not gs.result_presentation_active and not gs.is_elimination_result_pending(), "clear: no goal race, no ceremony")
	check(provider.submitted.is_empty() and provider.ended == 0 and _optimizer.calls == 0 and _analytics.calls == 0,
		"clear: nothing recorded, the quiz provider is not touched", [provider.submitted, provider.ended, _optimizer.calls, _analytics.calls])
	gs.rate_last_question(true)
	check(_ratings.calls == 0 and not gs.rating_feedback.is_empty(), "record_results false: the rating reacts but is not sent", gs.rating_feedback)
	# 記録するルールなら、評価も送る（本編と同じ）。
	var sent_rules := _mini_run_rules()
	sent_rules.record_results = true
	var sent := _state()
	sent.start_practice_round(_mini_run_quizzes(), 1, sent_rules, [2])
	for door: int in [1, 0, 2]:
		sent.player_x = _door_x(sent, door)
		sent.resolve_collision(true, false)
	sent.rate_last_question(false)
	check(sent.game_state == Constants.STATE_CLEAR and _ratings.calls == 1, "record_results true: the rating is sent", _ratings.calls)
	# finish_with_clear なし（段階4まで）：問題が尽きても CLEAR にならない。
	var plain_rules := _mini_run_rules()
	plain_rules.finish_with_clear = false
	var plain := _state()
	plain.start_practice_round(_mini_run_quizzes(), 1, plain_rules, [2])
	var plain_finished := [0]
	plain.practice_quizzes_finished.connect(func() -> void: plain_finished[0] += 1)
	for door: int in [1, 0, 2]:
		plain.player_x = _door_x(plain, door)
		plain.resolve_collision(true, false)
	check(plain.game_state == Constants.STATE_PLAYING and plain_finished[0] == 1, "without finish_with_clear: finished, no clear")
	# CLEAR のままでも、本番の始まり方でやり直せる。
	gs.start_practice_round(quizzes, 1, _mini_run_rules(), [2], Constants.STATE_WAITING_START)
	check(gs.game_state == Constants.STATE_WAITING_START and gs.score == 0 and gs.p1_hp == 3 and gs.rating_target_quiz == null
		and gs.message_text.is_empty() and gs.current_quiz == quizzes[0], "retry from CLEAR: back to the start screen")
	# 本編の10問の CLEAR は今までどおり。
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 1
	ten.target_count = 2
	ten.game_state = Constants.STATE_PLAYING
	ten._reset_health()
	ten.quiz_list.append(_two("ten 0"))
	ten.quiz_list.append(_four("ten 1"))
	ten.load_current_quiz()
	for _i in range(2):
		ten.player_x = _door_x(ten, 0)
		ten.resolve_collision(true, false)
	check(ten.game_state == Constants.STATE_CLEAR and ten.message_text.contains("10問完走") and (ten.provider as TestProvider).ended == 1,
		"ten: CLEAR as before", [ten.game_state, ten.message_text])


## 段階5（3.3）：real_result_screens の負けは本番どおりの GAME OVER の文字。practice_round_lost も1回出す。
func _real_result_loss() -> void:
	var rules := _mini_run_rules()
	rules.world_speed = 0.0
	var gs := _state()
	var quizzes := _mini_run_quizzes()
	gs.start_practice_round(quizzes, 1, rules, [2])
	var lost: Array = []
	gs.practice_round_lost.connect(func(reason: StringName) -> void: lost.append(reason))
	for door: int in [0, 1, 0]:
		gs.player_x = _door_x(gs, door)
		gs.resolve_collision(true, false)
	check(gs.game_state == Constants.STATE_GAME_OVER and lost == [&"hp"] and not gs.p1_alive, "real result screens: the loss is reported once", lost)
	check(gs.message_text.begins_with("GAME OVER") and gs.message_text.contains(quizzes[2].e), "real result screens: the real GAME OVER text", gs.message_text)
	check(gs.status_text.is_empty() and gs.current_quiz == quizzes[2] and gs.rating_target_quiz == quizzes[2], "real result screens: the boss quiz is rated, no [R] hint")
	var hud: Node = (load("res://scripts/ui/gameplay_hud.gd") as Script).new()
	hud.set("game_state", gs)
	check(not bool(hud.call("_is_practice_loss")), "real result screens: the HUD shows the GAME OVER card")
	hud.free()
	_frames(gs, 300)
	check(lost.size() == 1 and gs.message_text.begins_with("GAME OVER") and gs.is_wall_death_sequence_complete(), "the death plays out, still one loss", lost)
	gs.start_practice_round(quizzes, 1, rules, [2], Constants.STATE_WAITING_START)
	check(gs.game_state == Constants.STATE_WAITING_START and gs.p1_alive and gs.p1_hp == 3 and gs.message_text.is_empty() and gs.score == 0,
		"retry from GAME OVER: the start screen with 3 hearts")


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label:
		texts.append((node as Label).text)
	for child: Node in node.get_children():
		texts.append_array(_label_texts(child))
	return texts


## ボタンを押して、HUD が次のフレームを済ませるまで待つ。
func _press(hud: Node, button_name: String) -> void:
	(hud.get(button_name) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## 段階5（3.3・3.4）：HUD の「問題: 1/3」とリザルトのカード（「正解 / 3問」・コーチの部品・評価・問題履歴・リトライ・メニュー）。
func _hud_result_card() -> void:
	var hud: CanvasLayer = (load("res://ui/gameplay_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var gs := _state()
	var quizzes := _mini_run_quizzes()
	gs.start_practice_round(quizzes, 1, _mini_run_rules(), [2])
	hud.set("game_state", gs)
	await get_tree().process_frame
	var score_label := hud.get("score_label") as Label
	var bar := hud.get("progress_bar") as ProgressBar
	check(score_label.visible and score_label.text == "正解: 0  問題: 1/3", "HUD: 正解: 0  問題: 1/3", score_label.text)
	check(bar.visible and is_equal_approx(bar.max_value, 3.0) and is_equal_approx(bar.value, 0.0), "HUD: the progress bar counts 3 walls")
	gs.player_x = _door_x(gs, 1)
	gs.resolve_collision(true, false)
	await get_tree().process_frame
	check(score_label.text == "正解: 1  問題: 2/3", "HUD: 正解: 1  問題: 2/3", score_label.text)
	gs.practice_rules.show_score = false
	await get_tree().process_frame
	check(not score_label.visible and not bar.visible, "HUD: no score without show_score (practice before 2-4)")
	gs.practice_rules.show_score = true
	for door: int in [0, 2]:
		gs.player_x = _door_x(gs, door)
		gs.resolve_collision(true, false)
	check(gs.game_state == Constants.STATE_CLEAR, "HUD test: cleared")
	await get_tree().process_frame
	check(bool(hud.call("practice_result_card_visible")), "HUD: the CLEAR card is up")
	check((hud.get("go_title") as Label).text == "CLEAR!", "HUD: CLEAR! title")
	var score_row := hud.call("practice_coach_target", &"result_score") as Control
	check(score_row != null and _label_texts(score_row).has("正解 / 3問") and _label_texts(score_row).size() == 2,
		"coach target result_score: the big number and 正解 / 3問", _label_texts(score_row) if score_row != null else [])
	var stats := hud.call("practice_coach_target", &"result_stats") as Control
	check(stats != null and _label_texts(stats).has("正答率") and _label_texts(stats).has("連続正解") and _label_texts(stats).has("時間"),
		"coach target result_stats")
	var explain := hud.call("practice_coach_target", &"result_explain") as Control
	check(explain != null and _label_texts(explain) == [quizzes[2].e], "coach target result_explain: the last explanation",
		_label_texts(explain) if explain != null else [])
	var rate := hud.call("practice_coach_target", &"result_rate") as Control
	check(rate != null and rate == hud.get("go_rate_box") and rate.is_visible_in_tree(), "coach target result_rate: the rating box")
	var parts := {&"result_card": "_stats_panel", &"result_history": "btn_history", &"result_retry": "btn_retry",
		&"result_menu": "btn_menu", &"history_back": "history_back_btn"}
	for id: StringName in parts:
		check(hud.call("practice_coach_target", id) == hud.get(parts[id]), "coach target %s" % id)
	check(hud.call("practice_coach_target", &"pause_bgm") == null and hud.call("practice_coach_target", &"nothing") == null,
		"HUD: no pause parts, unknown ids are null")
	for _i in range(5):
		await get_tree().process_frame
	check(hud.call("practice_coach_target", &"result_score") == score_row and is_instance_valid(score_row) and not score_row.is_queued_for_deletion(),
		"the practice card keeps its parts (no rebuild every frame)")
	await _wait_seconds(1.6)
	check(_label_texts(score_row).has("3"), "the big number counts up to 3", _label_texts(score_row))
	# 評価：画面の反応は本番どおり、送らない。
	var actions: Array = []
	hud.connect("practice_result_action", func(action: StringName) -> void: actions.append(action))
	_reset_counters()
	await _press(hud, "btn_good")
	var feedback := hud.get("rate_feedback") as Label
	check(actions == [&"rated"] and _ratings.calls == 0, "rating: reported as rated, not sent", [actions, _ratings.calls])
	check(feedback.visible and feedback.text == gs.rating_feedback and not (hud.get("btn_good") as Button).is_visible_in_tree(),
		"rating: the same reaction as the real game", feedback.text)
	check(hud.call("practice_coach_target", &"result_score") == score_row, "rating does not rebuild the card")
	# 問題履歴
	await _press(hud, "btn_history")
	check(actions.back() == &"history_opened" and (hud.get("history_panel") as Control).visible and not bool(hud.call("practice_result_card_visible")),
		"history: opened, the card is hidden", actions)
	await _press(hud, "history_back_btn")
	check(actions.back() == &"history_closed" and not (hud.get("history_panel") as Control).visible and bool(hud.call("practice_result_card_visible")),
		"history: closed, the card is back", actions)
	# リトライ・メニュー：監督へ（start_game もシーンの切り替えもしない）。監督がいないときのリトライは何もしない。
	await _press(hud, "btn_retry")
	check(gs.mode == Constants.MODE_PRACTICE and gs.game_state == Constants.STATE_CLEAR and not SceneTransition.is_transitioning(),
		"retry without a director: nothing happens")
	var stub := StubDirector.new()
	add_child(stub)
	practice_director = stub
	await _press(hud, "btn_retry")
	check(stub.retries == 1 and gs.mode == Constants.MODE_PRACTICE and gs.game_state == Constants.STATE_CLEAR and not SceneTransition.is_transitioning(),
		"retry: the director's retry_run, no start_game")
	await _press(hud, "btn_menu")
	check(stub.leaves == 1 and gs.practice_rules != null and not SceneTransition.is_transitioning(), "menu: the director's leave_to_menu")
	practice_director = null
	stub.queue_free()
	# やり直し（practice_player_reset → practice_clear_flashes）でカードを閉じ、次の回のカードは作り直す。
	hud.call("practice_clear_flashes")
	check(not (hud.get("game_over_panel") as Control).visible and (hud.get("_practice_card_key") as Array).is_empty(), "practice reset: the card is closed")
	# 本番どおりの GAME OVER：死ぬ演出のあとにカード。段階4の練習の負けはカードなし。
	var lose_rules := _mini_run_rules()
	lose_rules.world_speed = 0.0
	var lose := _state()
	lose.start_practice_round(_mini_run_quizzes(), 1, lose_rules, [2])
	for door: int in [0, 1, 0]:
		lose.player_x = _door_x(lose, door)
		lose.resolve_collision(true, false)
	hud.set("game_state", lose)
	await get_tree().process_frame
	check(lose.game_state == Constants.STATE_GAME_OVER and not bool(hud.call("practice_result_card_visible")), "GAME OVER: no card during the death")
	_frames(lose, 300)
	hud.set("_go_fade_timer", 20.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(bool(hud.call("practice_result_card_visible")) and (hud.get("go_title") as Label).text == "GAME OVER" and (hud.get("btn_retry") as Button).visible,
		"GAME OVER: the real card after the death, with リトライ")
	var lose_row := hud.call("practice_coach_target", &"result_score") as Control
	check(lose_row != null and _label_texts(lose_row).has("正解 / 3問"), "GAME OVER card: 正解 / 3問")
	lose_rules.real_result_screens = false
	await get_tree().process_frame
	check(not (hud.get("game_over_panel") as Control).visible, "phase 4 practice loss: still no card")
	# 本編の10問のカードは今までどおり（毎フレーム作り直す・「正解 / 10問」・練習の合図は出さない）。
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 1
	ten.target_count = 2
	ten.game_state = Constants.STATE_PLAYING
	ten._reset_health()
	ten.quiz_list.append(_two("ten 0"))
	ten.quiz_list.append(_four("ten 1"))
	ten.load_current_quiz()
	hud.set("game_state", ten)
	await get_tree().process_frame
	check(score_label.text == "正解: 0  問題: 1/10", "ten: 正解: 0  問題: 1/10 as before", score_label.text)
	for _i in range(2):
		ten.player_x = _door_x(ten, 0)
		ten.resolve_collision(true, false)
	await get_tree().process_frame
	var ten_row := hud.get("_card_score_row") as Control
	check(ten_row != null and _label_texts(ten_row).has("正解 / 10問"), "ten: 正解 / 10問 as before")
	await get_tree().process_frame
	check(hud.get("_card_score_row") != ten_row, "ten: the card is rebuilt every frame as before")
	actions.clear()
	await _press(hud, "btn_good")
	check(actions.is_empty() and _ratings.calls == 1, "ten: the rating is sent, no practice signal", [actions, _ratings.calls])
	hud.queue_free()
	for _i in range(3):
		await get_tree().process_frame


# ------------------------------------------------------------------ 段階6：2人対戦

## 2人で進める（P1 と P2 のキーボードの入力を渡す）。
func _frames2(gs: QuizGameState, count: int, axis1 := Vector2.ZERO, axis2 := Vector2.ZERO, jump1 := false, jump2 := false) -> void:
	for _i in range(count):
		gs.update(DT, axis1, axis2, jump1, jump2, 0, 0)


## 段階6（2.1）：practice_p2_cpu と practice_set_cpu_input で、P2 はキーボードの代わりに CPU の入力で動く。
func _cpu_input() -> void:
	var gs := _practice(2, _rules(0.0))
	gs.practice_place_player(1, 8.0, 5.0)
	gs.practice_place_player(2, -1.5, 0.0)
	# CPU にしていないときは、渡しても使わない。
	gs.practice_set_cpu_input(Vector2(1.0, 0.0), false)
	check(not gs.practice_cpu_active(), "cpu: off unless practice_p2_cpu")
	_frames2(gs, 30)
	check(is_equal_approx(gs.player2_x, -1.5), "cpu off: the CPU input is not used", gs.player2_x)
	gs.practice_p2_cpu = true
	check(gs.practice_cpu_active(), "cpu: on in a 2-player practice round")
	# キーボードの P2 の入力（逆向き）は使わない。
	_frames2(gs, 30, Vector2.ZERO, Vector2(-1.0, 0.0))
	check(absf(gs.player2_x - (-1.5 + gs.tuning.player_speed * 0.5)) < 0.05, "cpu: P2 moves left at full speed (keyboard ignored)", gs.player2_x)
	gs.practice_set_cpu_input(Vector2(0.0, 0.5), false)
	var z := gs.player2_local_z
	_frames2(gs, 60)
	check(absf(gs.player2_local_z - z - gs.tuning.player_speed * 0.5) < 0.05, "cpu: half speed forward (speed 0.5)", gs.player2_local_z - z)
	gs.practice_set_cpu_input(Vector2(3.0, 4.0), false)
	check((gs.practice_cpu_frame_input().axis as Vector2).is_equal_approx(Vector2(0.6, 0.8)), "cpu: the axis is limited to length 1")
	var jumps := gs.p2_jump_count
	gs.practice_set_cpu_input(Vector2.ZERO, true)
	_frames2(gs, 1)
	check(gs.p2_jump_count == jumps + 1 and gs.player2_vel_y > 0.0 and gs.player2_y > 0.0, "cpu: jump", [gs.p2_jump_count, gs.player2_y])
	gs.practice_set_cpu_input(Vector2.ZERO, false)
	_frames2(gs, 90)
	check(gs.player2_y == 0.0 and gs.p2_jump_count == jumps + 1, "cpu: lands, one jump")
	gs.practice_set_cpu_input(Vector2.ZERO, false, 2)
	_frames2(gs, 1)
	check(gs.p2_emote == gs.p2_emote_slots[1], "cpu: emote slot 2 = the P2 '9' emote", gs.p2_emote)
	var frame_input := gs.practice_cpu_frame_input()
	check(int(frame_input.emote) == gs.p2_emote_slots[1] and int(frame_input.emote_keys) == 2, "cpu frame input: emote id and key bits", frame_input)
	gs.practice_set_cpu_input(Vector2.ZERO, true)
	_frames2(gs, 1)
	check(gs.p2_emote == 0, "cpu: a jump ends the emote like the keyboard")
	# 説明中（input_locked）は CPU も止まる。P1 は CPU の影響を受けない。
	gs.practice_rules.input_locked = true
	gs.practice_set_cpu_input(Vector2(1.0, 0.0), true)
	var x2 := gs.player2_x
	var x1 := gs.player_x
	_frames2(gs, 20)
	check(is_equal_approx(gs.player2_x, x2) and is_equal_approx(gs.player_x, x1), "input_locked: the CPU stops too")
	gs.practice_rules.input_locked = false
	# 本編へ戻ると CPU は外れる。
	gs.mode = Constants.MODE_TEN
	gs.start_game()
	check(not gs.practice_p2_cpu and not gs.practice_cpu_active(), "start_game turns the CPU off")
	var again := _practice(2, _rules(0.0))
	again.practice_p2_cpu = true
	again.start_practice_round([], 2, _rules(0.0))
	check(again.practice_p2_cpu, "start_practice_round keeps practice_p2_cpu")
	again.reset_to_menu()
	check(not again.practice_p2_cpu, "reset_to_menu turns the CPU off")


## 段階6（2.1）：CPU の横の入力は押し合いのキー。押し続けて踏ん張り、離して押し直すと一押し。
func _cpu_push() -> void:
	var rules := _rules(0.0)
	rules.local_push_enabled = true
	var gs := _practice(2, rules)
	gs.practice_p2_cpu = true
	gs.practice_place_player(1, 0.6, 0.0)
	gs.practice_place_player(2, -0.6, 0.0)
	var events: Array = []
	gs.local_push_event.connect(func(event: Dictionary) -> void: events.append(event))
	check(gs.practice_cpu_push_mask() == 0, "cpu push: no key without input")
	# P2 は画面の左（+x）にいる P1 のほうへ、P1 は右（−x）の P2 のほうへ押し続ける。
	gs.practice_set_cpu_input(Vector2(1.0, 0.0), false)
	check(gs.practice_cpu_push_mask() == 1, "cpu push: +x is the ← key")
	_frames2(gs, 20, Vector2(-1.0, 0.0))
	var kinds: Array = events.map(func(event: Dictionary) -> String: return str(event.kind))
	check(kinds.has("contact") and kinds.has("stalemate"), "cpu push: contact and a stalemate", kinds)
	check(not kinds.has("hit"), "cpu push: holding does not strike", kinds)
	check(absf(gs.player_x - gs.player2_x) < 1.4, "cpu push: bodies stay together", [gs.player_x, gs.player2_x])
	# 一度離して押し直す。
	var p1_x := gs.player_x
	gs.practice_set_cpu_input(Vector2.ZERO, false)
	_frames2(gs, 1, Vector2(-1.0, 0.0))
	gs.practice_set_cpu_input(Vector2(1.0, 0.0), false)
	_frames2(gs, 20, Vector2(-1.0, 0.0))
	var hits: Array = events.filter(func(event: Dictionary) -> bool: return str(event.kind) == "hit")
	check(hits.size() == 1 and int(hits[0].player) == 2, "cpu push: release and press again strikes once (P2)", hits)
	check(float(gs.local_push.shove_start[0]) > 0.0 and gs.player_x > p1_x + 0.05, "cpu push: P1 is shoved back toward the left",
		[p1_x, gs.player_x])
	# 押し合いがないレッスンでは、何も渡さない。
	var off := _practice(2, _rules(0.0))
	off.practice_p2_cpu = true
	off.practice_set_cpu_input(Vector2(1.0, 0.0), false)
	_frames2(off, 5)
	check(off.local_push.inputs.is_empty() and off._practice_cpu_push_sent == 0, "cpu push: nothing sent without local_push_enabled")


func _saw_rules(report_only: bool) -> MatchRules:
	var rules := _rules(0.0)
	rules.hp_enabled = true
	rules.saw_enabled = true
	rules.saw = MatchRules.Saw.REPORT_ONLY if report_only else MatchRules.Saw.NORMAL
	return rules


## 段階6（2.3）：のこぎりは床のうしろから入って本番どおり走り、REPORT_ONLY では捕まっても知らせるだけ。
func _saw_report_only() -> void:
	var gs := _practice(2, _saw_rules(true))
	gs.saw_transport_enabled = true
	var caught: Array = []
	var reported: Array = []
	var lost: Array = []
	gs.player_caught_by_saw.connect(func(p: int) -> void: caught.append(p))
	gs.practice_saw_caught.connect(func(p: int) -> void: reported.append(p))
	gs.practice_round_lost.connect(func(reason: StringName) -> void: lost.append(reason))
	gs.practice_place_player(1, 1.5, 4.0)
	gs.practice_place_player(2, -1.5, -8.9)
	check(gs.uses_saw_chase() and gs.is_saw_visible(), "saw: runs in a 2-player practice round")
	_frames2(gs, 1)
	check(gs.saw.enabled and gs.saw.local_z < QuizGameState.FLOOR_BACK_Z, "saw: enters from behind the floor", gs.saw.local_z)
	check(gs.get_saw_danger_ratio(2) == 0.0, "saw: no danger while far behind")
	var arrived := _frames_until(gs, 600, Vector2.ZERO, func() -> bool: return not reported.is_empty())
	check(arrived and reported == [2] and caught == [2], "REPORT_ONLY: caught, reported once (player_caught_by_saw too)", [reported, caught])
	check(not gs.p2_alive and gs.p2_saw_killed and gs.p2_hp == 3 and gs.is_practice_saw_caught(2), "REPORT_ONLY: the body is cut, hearts kept",
		[gs.p2_alive, gs.p2_hp])
	check(gs.game_state == Constants.STATE_PLAYING and lost.is_empty(), "REPORT_ONLY: no loss, the round goes on")
	check(gs.saw.local_z >= SawChaseState.INITIAL_Z - 0.05, "saw: drove in to the real start position", gs.saw.local_z)
	_frames2(gs, 60)
	check(reported == [2] and gs.p1_alive, "REPORT_ONLY: one report, P1 still running", reported)
	gs.practice_revive(2)
	check(gs.p2_alive and not gs.p2_saw_killed and not gs.is_practice_saw_caught(2), "practice_revive after the saw")
	check(not gs.saw.enabled and is_equal_approx(gs.saw.local_z, QuizGameState.PRACTICE_SAW_ENTRY_Z), "revive: the saw comes in again from behind")
	gs.practice_place_player(2, -1.5, 0.0)
	_frames2(gs, 30)
	check(gs.saw.enabled and gs.saw.elapsed < gs.tuning.saw_grace_seconds + 0.5, "revive: the saw waits its grace again", gs.saw.elapsed)
	# 2人とも捕まっても、練習の負けにしない。
	var both := _practice(2, _saw_rules(true))
	both.saw_transport_enabled = true
	var both_lost: Array = []
	var both_reported: Array = []
	both.practice_round_lost.connect(func(reason: StringName) -> void: both_lost.append(reason))
	both.practice_saw_caught.connect(func(p: int) -> void: both_reported.append(p))
	both.practice_place_player(1, 1.5, -8.9)
	both.practice_place_player(2, -1.5, -8.9)
	_frames_until(both, 600, Vector2.ZERO, func() -> bool: return both_reported.size() >= 2)
	check(both_reported.size() == 2 and both_lost.is_empty() and both.game_state == Constants.STATE_PLAYING, "REPORT_ONLY: both caught, still no loss",
		[both_reported, both_lost, both.game_state])
	# NORMAL：本番どおりアウト（2人とも捕まれば練習の負け &"saw"）。
	var normal := _practice(2, _saw_rules(false))
	normal.saw_transport_enabled = true
	var normal_lost: Array = []
	var normal_reported := [0]
	normal.practice_round_lost.connect(func(reason: StringName) -> void: normal_lost.append(reason))
	normal.practice_saw_caught.connect(func(_p: int) -> void: normal_reported[0] += 1)
	normal.practice_place_player(1, 1.5, -8.9)
	normal.practice_place_player(2, -1.5, -8.9)
	_frames_until(normal, 600, Vector2.ZERO, func() -> bool: return not normal_lost.is_empty())
	check(normal_lost == [&"saw"] and normal.p1_hp == 0 and normal.p2_hp == 0 and normal_reported[0] == 0, "NORMAL saw: out, practice_round_lost (saw)",
		[normal_lost, normal.p1_hp])
	# 本編の2人の10問ののこぎりは今までどおり（入ってこず、始めの位置から）。
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	ten.saw_transport_enabled = true
	ten.game_state = Constants.STATE_PLAYING
	ten.update(DT)
	check(is_equal_approx(ten.saw.local_z, SawChaseState.INITIAL_Z) and not ten._practice_saw_parking, "ten: the saw starts where it always did", ten.saw.local_z)


## 段階6（2.3）：saw_enabled を false にしたら、本番の止まり方で止めて床のうしろへ下げ、見えなくする。
func _saw_parking() -> void:
	var rules := _saw_rules(true)
	var gs := _practice(2, rules)
	gs.saw_transport_enabled = true
	gs.practice_place_player(1, 1.5, 2.0)
	gs.practice_place_player(2, -1.5, 2.0)
	_frames2(gs, 240)
	check(gs.saw.enabled and gs.is_saw_visible(), "parking: the saw is running")
	rules.saw_enabled = false
	_frames2(gs, 1)
	check(gs.saw.stopping and gs.is_saw_visible() and not gs.uses_saw_chase(), "parking: stops like the real game, still visible")
	check(gs.get_saw_clearance(1) == INF and gs.get_saw_danger_ratio(2) == 0.0, "parking: no danger while it stops")
	_frames2(gs, int(SawChaseState.STOP_SECONDS / DT) + 5)
	check(gs.is_saw_visible() and gs.saw.stop_speed_ratio() == 0.0, "parking: the blades have stopped")
	var hidden := _frames_until(gs, 600, Vector2.ZERO, func() -> bool: return not gs.is_saw_visible())
	check(hidden and not gs.saw.enabled, "parking: backs away and disappears")
	# また saw_enabled にしたら、床のうしろから入り直す。
	rules.saw_enabled = true
	_frames2(gs, 1)
	check(gs.saw.enabled and gs.is_saw_visible() and gs.saw.local_z < QuizGameState.FLOOR_BACK_Z and not gs.saw.stopping, "parking: enabled again, enters from behind")
	rules.saw_enabled = false
	_frames2(gs, 10)
	rules.saw_enabled = true
	_frames2(gs, 1)
	check(not gs.saw.stopping and not gs._practice_saw_parking, "parking: enabling while stopping restarts the saw")


## 段階6（2.4）：practice_make_ghost と、ゴーストの合図・様子（ゲーム画面の GhostSharkRideController が知らせる）。
func _make_ghost() -> void:
	var rules := _rules(0.0)
	rules.hp_enabled = true
	rules.hp_floor = 1
	rules.ghost_ride_enabled = true
	var gs := _practice(2, rules)
	var requests: Array = []
	var skips := [0]
	var health: Array = []
	gs.practice_ghost_requested.connect(func(p: int, skip: bool) -> void: requests.append([p, skip]))
	gs.practice_ghost_skip_requested.connect(func() -> void: skips[0] += 1)
	gs.health_changed.connect(func(p: int, old: int, value: int) -> void: health.append([p, old, value]))
	gs.practice_make_ghost(1)
	check(requests == [[1, false]], "make_ghost: the screen is asked to start the ride", requests)
	check(not gs.p1_alive and gs.p1_wall_impact and gs.game_over_timer > 0.0 and gs.p2_alive, "make_ghost: P1 is out like a wall death")
	check(gs.p1_hp == 0 and health == [[1, 3, 0]], "make_ghost: hearts 0 below hp_floor (the card shows OUT)", health)
	_frames2(gs, 30)
	check(gs.game_state == Constants.STATE_PLAYING and gs.game_over_timer > 0.4, "make_ghost: the round goes on, the death plays out")
	gs.practice_make_ghost(1)
	check(requests.size() == 1, "make_ghost: a player who is out is not asked again")
	gs.practice_skip_ghost_intro()
	check(skips[0] == 1, "skip_ghost_intro: the screen is asked to skip")
	var signals: Array = []
	gs.practice_ghost_ready.connect(func(p: int) -> void: signals.append(["ready", p]))
	gs.practice_ghost_dash.connect(func(p: int) -> void: signals.append(["dash", p]))
	gs.practice_ghost_hit.connect(func(a: int, v: int) -> void: signals.append(["hit", a, v]))
	gs.practice_ghost_missed.connect(func(p: int) -> void: signals.append(["missed", p]))
	for event: StringName in [&"ready", &"dash", &"missed"]:
		gs.notify_practice_ghost(event, 1)
	gs.notify_practice_ghost(&"hit", 1, 2)
	check(signals == [["ready", 1], ["dash", 1], ["missed", 1], ["hit", 1, 2]], "ghost events become practice signals", signals)
	gs.notify_practice_ghost_state(1, {"phase": &"AIMING", "aim": Vector2(1.0, 2.0)})
	var state := gs.practice_ghost_state(1)
	check(state.get("phase") == &"AIMING" and state.get("aim") == Vector2(1.0, 2.0) and gs.practice_ghost_state(2).is_empty(), "ghost state is readable", state)
	state["phase"] = &"CHANGED"
	check(gs.practice_ghost_state(1).get("phase") == &"AIMING", "ghost state is a copy")
	gs.practice_revive(1)
	check(gs.p1_alive and not gs.p1_wall_impact and gs.practice_ghost_state(1).is_empty() and gs.p1_hp == 0, "revive from the ghost: alive, state cleared, hearts kept (0)",
		[gs.p1_alive, gs.p1_hp])
	gs.practice_set_hp(1, 3)
	check(gs.p1_hp == 3, "hearts restored with practice_set_hp")
	gs.practice_make_ghost(2, true)
	check(requests.back() == [2, true] and not gs.p2_alive, "make_ghost P2 with skip_intro", requests)
	# 1人・本編では何もしない。
	var solo := _practice(1, rules.duplicate_rules())
	var solo_requests := [0]
	solo.practice_ghost_requested.connect(func(_p: int, _s: bool) -> void: solo_requests[0] += 1)
	solo.practice_make_ghost(1)
	check(solo_requests[0] == 0 and solo.p1_alive, "make_ghost: not in a 1-player round")
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	var ten_signals := [0]
	ten.practice_ghost_ready.connect(func(_p: int) -> void: ten_signals[0] += 1)
	ten.notify_practice_ghost(&"ready", 1)
	ten.notify_practice_ghost_state(1, {"phase": &"AIMING"})
	check(ten_signals[0] == 0 and ten.practice_ghost_state(1).is_empty(), "ten: no ghost practice signals or state")
	# ゴーストシャークの操作：照準の演出の途中でなければ飛ばさない。CPU が乗っているかの見分け。
	var ghost := GhostSharkRideController.new()
	ghost.game_state = gs
	check(not ghost.practice_skip_intro(), "skip intro: nothing to skip while inactive")
	gs.practice_p2_cpu = true
	ghost.dead_player_index = 2
	check(ghost._is_practice_cpu_rider(), "the CPU riding the ghost is recognized")
	ghost.dead_player_index = 1
	check(not ghost._is_practice_cpu_rider(), "P1 riding is not the CPU")
	ghost.free()


## 段階6（2.4）：さく（fence_enabled）は、ゴーストの突進の吹き飛ばしでも海へ落とさない。
func _ghost_fence() -> void:
	var rules := _rules(0.0)
	rules.fence_enabled = true
	var gs := _practice(2, rules)
	gs.practice_place_player(2, -9.0, 0.0)
	gs.apply_external_impulse(2, Vector2(-20.3, 0.0), 7.8, 0.48)
	_frames2(gs, 120)
	check(gs.p2_alive and not gs.p2_fall_committed and not gs.p2_waiting_for_shark and gs.player2_y == 0.0, "fence: the knocked player stays on the floor")
	check(gs.player2_x >= rules.fence_min.x - 0.001, "fence: stopped at the fence", gs.player2_x)
	var open := _practice(2, _rules(0.0))
	open.practice_place_player(2, -9.0, 0.0)
	open.apply_external_impulse(2, Vector2(-20.3, 0.0), 7.8, 0.48)
	_frames2(open, 120)
	check(open.p2_fall_committed or open.p2_waiting_for_shark, "no fence: the same hit throws the player into the sea")


func _goal_rules() -> MatchRules:
	var rules := _rules(1.6)
	rules.hp_enabled = true
	rules.finish_with_goal = true
	return rules


## ゴールレースで2人ともゴールラインを越えさせる。
func _reach_goal(gs: QuizGameState) -> void:
	gs.player_z = gs.goal_z + 0.6
	gs.player2_z = gs.goal_z + 0.6
	gs.player_y = 0.0
	gs.player2_y = 0.0
	_frames2(gs, 2)


## 段階6（2.5）：finish_with_goal で最後の壁のあとゴールレース → スコアタワー → 判定で practice_ceremony_finished。
func _finish_with_goal() -> void:
	var quiz := _two("100 − 36 = ?")
	var gs := _practice(2, _goal_rules(), _list([quiz]))
	gs.result_ceremony_enabled = true
	var provider := gs.provider as TestProvider
	var finished := [0]
	var states: Array = []
	var ceremonies: Array = []
	gs.practice_quizzes_finished.connect(func() -> void: finished[0] += 1)
	gs.state_changed.connect(func(state: String) -> void: states.append(state))
	gs.practice_ceremony_finished.connect(func(winner: int) -> void: ceremonies.append(winner))
	check(gs.uses_local_result_ceremony() and gs.practice_finishes_with_goal(), "finish_with_goal: the real 2-player finale is used")
	# ハートと正解数の持ち越し（P1 は正解3・ハート3、P2 は正解2・ハート2）。
	gs.practice_set_score(1, 3)
	gs.practice_set_score(2, 2)
	gs.practice_set_hp(2, 2)
	check(gs.score == 3 and gs.player2_score == 2 and gs.p2_hp == 2, "practice_set_score / practice_set_hp carry the results over")
	gs.practice_place_player(2, _door_x(gs, 0), 0.0)
	gs.player_x = _door_x(gs, 0)
	gs.resolve_collision(true, true)
	check(gs.game_state == Constants.STATE_GOAL_RACE and finished[0] == 0 and gs.current_quiz == null, "last wall: the goal race starts", [gs.game_state, finished[0]])
	check(is_equal_approx(gs.goal_z, gs.tuning.wall_start_z + gs.tuning.wall_spacing + 15.0), "the goal line is behind the last wall", gs.goal_z)
	check(gs.message_text == "GOAL へ走れ！", "goal race message like the real game", gs.message_text)
	# ゴールレースは練習の速さで前へ運ぶ。
	var z := gs.player_z
	_frames2(gs, 60)
	check(absf(gs.player_z - z - 1.6) < 0.02, "goal race: carried at the practice speed", gs.player_z - z)
	_reach_goal(gs)
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_presentation_active, "both at the goal: the score tower ceremony", gs.game_state)
	check(gs.result_p1_correct_count == 4 and gs.result_p2_correct_count == 3 and gs.result_p2_hp == 2, "ceremony: carried scores and hearts")
	check(gs.get_result_formula_text(1) == "P1: 4 × 3.5 = 14" and gs.get_result_formula_text(2) == "P2: 3 × 2.5 = 7.5",
		"ceremony: the real formula", [gs.get_result_formula_text(1), gs.get_result_formula_text(2)])
	check(gs.result_winner == 1 and not gs.sudden_death_pending, "ceremony: P1 wins")
	_frames2(gs, int(QuizGameState.RESULT_VERDICT_TIME / DT) - 10)
	check(ceremonies.is_empty() and gs.result_ceremony_phase < QuizGameState.ResultCeremonyPhase.EFFECT, "no ceremony signal before the verdict")
	_frames2(gs, 20)
	check(ceremonies == [1] and gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.EFFECT,
		"practice_ceremony_finished(1) when the verdict is out (6.9 s), the ceremony goes on", [ceremonies, gs.result_ceremony_phase])
	_frames2(gs, int((QuizGameState.RESULT_TOTAL_DURATION - QuizGameState.RESULT_VERDICT_TIME) / DT) + 30)
	check(ceremonies == [1] and gs.game_state == Constants.STATE_CLEAR and states.back() == Constants.STATE_CLEAR, "the ceremony ends in CLEAR like the real game, one signal",
		[ceremonies, gs.game_state])
	check(gs.message_text.begins_with("P1 の勝ち！"), "verdict text like the real game", gs.message_text)
	check(provider.ended == 0 and provider.submitted.is_empty(), "the quiz provider is not touched", [provider.ended, provider.submitted])
	_frames2(gs, 120)
	check(ceremonies.size() == 1, "the ceremony signal is sent once")
	# 引き分け：サドンデスへ行かずに引き分けのまま終わる。
	var draw := _practice(2, _goal_rules(), _list([quiz]))
	draw.result_ceremony_enabled = true
	var draw_done: Array = []
	draw.practice_ceremony_finished.connect(func(winner: int) -> void: draw_done.append(winner))
	draw.practice_place_player(2, _door_x(draw, 0), 0.0)
	draw.player_x = _door_x(draw, 0)
	draw.resolve_collision(true, true)
	_reach_goal(draw)
	check(draw.result_winner == 0 and not draw.sudden_death_pending and not draw.uses_sudden_death(), "draw: no sudden death in practice")
	_frames2(draw, int(QuizGameState.RESULT_DRAW_TOTAL_DURATION / DT) + 30)
	check(draw_done == [0] and draw.game_state == Constants.STATE_CLEAR, "draw: practice_ceremony_finished(0)", [draw_done, draw.game_state])
	# 1人のときや finish_with_goal なしでは、今までどおり（問題を使い切っても何も起きない）。
	var plain_rules := _goal_rules()
	plain_rules.finish_with_goal = false
	var plain := _practice(2, plain_rules, _list([quiz]))
	plain.result_ceremony_enabled = true
	var plain_finished := [0]
	plain.practice_quizzes_finished.connect(func() -> void: plain_finished[0] += 1)
	plain.practice_place_player(2, _door_x(plain, 0), 0.0)
	plain.player_x = _door_x(plain, 0)
	plain.resolve_collision(true, true)
	check(plain.game_state == Constants.STATE_PLAYING and plain_finished[0] == 1 and not plain.uses_local_result_ceremony(), "without finish_with_goal: finished, no goal race")
	var solo := _practice(1, _goal_rules(), _list([quiz]))
	solo.result_ceremony_enabled = true
	solo.player_x = _door_x(solo, 0)
	solo.resolve_collision(true, false)
	check(solo.game_state == Constants.STATE_PLAYING and not solo.practice_finishes_with_goal(), "1 player: finish_with_goal does nothing")
	# 本編の2人の10問のスコアタワーは今までどおり。
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	ten.result_ceremony_enabled = true
	check(ten.uses_local_result_ceremony() and not ten.practice_finishes_with_goal(), "ten 2P: the finale as before")
	check(ten.uses_sudden_death() == QuizGameState.sudden_death_available, "ten 2P: the sudden death availability as before")


## 段階6（2.2）：2人の練習のカード（ハートを使わないレッスンでも）と、右上の数字を出さないこと。判定のあとのボタンも出さない。
func _duo_hud() -> void:
	var gs := _practice(2, _rules(0.0), _list([_two()]))
	check(gs.shows_duo_cards() and not gs.uses_hp(), "2P practice: duo cards even without hearts")
	var hearts := _practice(2, _goal_rules())
	check(hearts.shows_duo_cards(), "2P practice with hearts: duo cards")
	check(not _practice(1, _rules(0.0)).shows_duo_cards(), "1P practice: no duo cards")
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	check(ten.shows_duo_cards(), "ten 2P: duo cards as before")
	var coop := _state()
	coop.mode = Constants.MODE_COOP
	coop.num_players = 2
	check(not coop.shows_duo_cards(), "co-op: no duo cards as before")
	var health: Control = (load("res://scripts/ui/player_health_hud.gd") as Script).new()
	health.call("setup", gs)
	add_child(health)
	await get_tree().process_frame
	await get_tree().process_frame
	check(health.visible and (health.get("_duo_cards") as Array).size() == 2, "health HUD: the two corner cards are shown")
	check(health.call("get_ghost_hud_card", 1) != null and health.call("get_ghost_hud_card", 2) != null, "health HUD: the ghost HUD lives in the cards")
	var card: Control = (health.get("_duo_cards") as Array)[1]
	card.set("_shine_time", 10.0)
	health.call("practice_card_shine", 2)
	check(float(card.get("_shine_time")) < 0.1 and float(card.get("_flash_time")) > 0.0, "practice_card_shine: the P2 card shines")
	health.queue_free()
	var hud: CanvasLayer = (load("res://ui/gameplay_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	gs.practice_rules.show_score = true
	hud.set("game_state", gs)
	await get_tree().process_frame
	check(not (hud.get("score_label") as Label).visible, "2P practice: no 正解・問題 in the corner (the cards are used)")
	hud.queue_free()
	# スコアタワーの演出の HUD：練習は判定のあとのボタンと記録の文字を出さない。本編は今までどおり出す。
	var finale := _practice(2, _goal_rules(), _list([_two()]))
	finale.result_ceremony_enabled = true
	finale.practice_place_player(2, _door_x(finale, 0), 0.0)
	finale.player_x = _door_x(finale, 0)
	finale.resolve_collision(true, true)
	_reach_goal(finale)
	_frames2(finale, int(QuizGameState.RESULT_TOTAL_DURATION / DT) + 30)
	check(finale.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.INTERACTIVE, "finale HUD test: the ceremony reached the end")
	var overlay := ResultFinaleHud.new()
	var noop := func() -> void: pass
	overlay.setup(finale, noop, noop, noop)
	add_child(overlay)
	overlay.update_overlay(DT)
	overlay.update_overlay(0.6)
	var snapshot := overlay.get_debug_snapshot()
	check(overlay.visible and not bool(snapshot.get("actions_visible", true)) and not (overlay.get("_stats") as Label).visible,
		"practice finale: no buttons or stats after the verdict", snapshot.get("actions_visible"))
	finale.practice_rules = null
	finale.mode = Constants.MODE_TEN
	overlay.set("_built_winner", -2)
	overlay.update_overlay(DT)
	overlay.update_overlay(0.6)
	check(bool(overlay.get_debug_snapshot().get("actions_visible", false)), "ten finale: the buttons as before")
	overlay.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ 段階7：練習のオンラインの見せ方（④の 4-6）

func _online_look() -> void:
	var rules := _rules(0.0)
	var gs := _practice(2, rules, _list([_two()]))
	check(not gs.is_practice_online_look(), "online look: off by default")
	check(gs.slot_label(1) == "1P" and gs.slot_label(2) == "2P", "online look off: slot labels as before", [gs.slot_label(1), gs.slot_label(2)])
	gs.practice_online_look = true
	check(gs.is_practice_online_look(), "online look: on in a 2P practice round")
	check(gs.slot_label(1) == "じぶん" and gs.slot_label(2) == "CPU", "online look: じぶん / CPU", [gs.slot_label(1), gs.slot_label(2)])
	check(bool(gs.call("_shows_custom_skin", 1)) and not bool(gs.call("_shows_custom_skin", 2)),
		"online look: my own skin colours only (the CPU keeps the slot colour)")
	check(gs.get_display_skin_key(2) == "", "online look: the CPU display skin key stays default")
	var solo := _practice(1, _rules(0.0))
	solo.practice_online_look = true
	check(not solo.is_practice_online_look(), "online look: not for a 1P round")
	var ten := _state()
	ten.mode = Constants.MODE_TEN
	ten.num_players = 2
	ten.practice_online_look = true
	check(not ten.is_practice_online_look() and ten.slot_label(2) == "2P", "online look: never outside the practice mode")
	var replay := _practice(2, _rules(0.0))
	replay.practice_online_look = true
	replay.is_replay = true
	check(not replay.is_practice_online_look(), "online look: not in a replay")
	gs.reset_to_menu()
	check(not gs.practice_online_look and gs.slot_label(1) == "1P", "online look: reset_to_menu clears it")

	# ④のカタログと台本
	var course := PracticeCatalog.find("c4")
	check(PracticeCatalog.is_available("c4") and str(course.get("scene", "")) == "res://ui/online_menu.tscn" and int(course.get("round_players", 0)) == 2,
		"catalog: c4 is playable, starts on the online menu and plays a 2-player round", course)
	var script := load(str(course.get("course_script", ""))) as Script
	var c4: PracticeCourse = script.new() as PracticeCourse if script != null else null
	check(c4 != null and c4.id == "c4" and c4.lesson_ids.size() == 6, "course_4: c4 with 4-1..4-6 dots")
	if c4 != null:
		var steps := c4.build_steps()
		check(steps.size() == 1 and steps[0].id == "4-6", "course_4: the game world part is 4-6 only")
		var match_rules: MatchRules = steps[0].call(&"match_rules")
		check(match_rules.world_speed < 0.0 and match_rules.hp_enabled and match_rules.hp_floor == 0 and match_rules.saw_enabled
			and match_rules.local_push_enabled and match_rules.ghost_ride_enabled and not match_rules.record_results
			and match_rules.finish_with_clear and match_rules.real_result_screens and not match_rules.fence_enabled,
			"course_4: the match uses the real 2-player rules with the auto speed and real result cards")
		var quizzes: Array[QuizItem] = steps[0].call(&"quizzes")
		check(quizzes.size() == 2 and quizzes[0].q == "13 + 29 = ?" and quizzes[0].a == 0 and quizzes[0].c[0] == "42"
			and quizzes[1].q == "太陽が昇る方角は？" and quizzes[1].a == 1 and quizzes[1].c[1] == "東",
			"course_4: the two walls of the script (42 blue, 東 red)")
	check(str(PracticeCatalog.find("c3").get("scene", "")) == "" and int(PracticeCatalog.find("c3").get("round_players", 2)) == 2,
		"catalog: c3 is unchanged (game world, 2 players)")
	# ⑤のカタログ（メインメニューの上だけで遊ぶ。docs/new_tutorial/phase8_design.md 1.1）
	var c5 := PracticeCatalog.find("c5")
	check(PracticeCatalog.is_available("c5") and str(c5.get("scene", "")) == "res://ui/main_menu.tscn" and int(c5.get("players", 0)) == 1,
		"catalog: c5 is playable on the main menu with 1 player", c5)
	check(PracticeTexts.get_text("c5.title") == "⑤ カスタマイズ" and not PracticeTexts.has_text("c5.set.2"),
		"texts: course 5 title and no unused 戻る line (script v0.2)")

	# 練習の「たいせんを やめますか？」
	var net := NetOverlay.new()
	add_child(net)
	net.setup_practice()
	var opened: Array[bool] = []
	net.confirm_changed.connect(func(open: bool) -> void: opened.append(open))
	check(not net.is_confirm_open(), "practice net overlay: closed at first")
	net.toggle_quit_confirm()
	check(net.is_confirm_open() and opened == [true], "practice net overlay: Esc opens たいせんを やめますか？", opened)
	check(net.quit_button().disabled and net.quit_button().text == "やめる" and not net.continue_button().disabled
		and net.continue_button().text == "つづける", "practice net overlay: やめる cannot be pressed, つづける can")
	var ping := net.find_child("PingDisplay", true, false) as Control
	check(ping != null and not ping.visible, "practice net overlay: no ping badge (not connected)")
	net.continue_button().pressed.emit()
	check(not net.is_confirm_open() and opened == [true, false], "practice net overlay: つづける closes it", opened)
	net.toggle_quit_confirm()
	net.close_confirm()
	check(not net.is_confirm_open() and opened.size() == 4, "practice net overlay: close_confirm closes it", opened)
	net.queue_free()
	var online_net := NetOverlay.new()
	add_child(online_net)
	online_net.toggle_quit_confirm()
	check(not online_net.quit_button().disabled, "online net overlay: やめる stays pressable as before")
	online_net.queue_free()

	# 2人のカードの札（じぶん・あいて）
	var look := _practice(2, _rules(0.0), _list([_two()]))
	look.practice_online_look = true
	var health: Control = (load("res://scripts/ui/player_health_hud.gd") as Script).new()
	health.call("setup", look)
	add_child(health)
	await get_tree().process_frame
	var badges: Array[String] = []
	for card_node: Variant in health.get("_duo_cards"):
		var label := (card_node as Node).find_child("Player", true, false) as Label
		badges.append(label.text if label != null else "-")
	check(badges == ["じぶん", "あいて"], "online look: the corner cards read じぶん / あいて", badges)
	health.queue_free()
	await get_tree().process_frame
