extends SceneTree

## PC版「英語」教科のデータ・学年制約・生成指示をAPIなしで検証する。

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_subject_registry()
	_test_question_spacing()
	var provider = load("res://scripts/core/quiz_provider.gd").new("res://offline_bank.json")
	get_root().add_child(provider)
	var fetcher = load("res://scripts/core/online_fetch.gd").new()
	get_root().add_child(fetcher)
	await process_frame
	_test_english_data(provider, fetcher)
	_test_game_state_metadata(provider)
	_test_coop_conversion(provider)
	provider.queue_free()
	fetcher.queue_free()
	await process_frame
	if _failures == 0:
		print("[EnglishSubjectTest] ALL PASSED")
		quit(0)
	else:
		push_error("[EnglishSubjectTest] FAILED: %d assertion(s)" % _failures)
		quit(1)


func _test_subject_registry() -> void:
	_assert_true(Constants.SUBJECTS.count("英語") == 1, "英語が教科一覧に1回だけ存在")
	_assert_true(Constants.SUBJECTS[-2] == "社会" and Constants.SUBJECTS[-1] == "英語", "社会の次が英語")
	_assert_true(Constants.SUBJECT_EN.get("英語", "") == "English", "英語UI名")
	_assert_true(Constants.grades_for_subject("英語") == [3, 4, 5, 6], "英語は3〜6年")
	_assert_true(Constants.normalize_grade_for_subject("英語", 1) == 3, "英語選択時に1年を3年へ補正")
	_assert_true(Constants.normalize_grade_for_subject("英語", 2) == 3, "英語選択時に2年を3年へ補正")
	_assert_true(Constants.cycle_grade_for_subject("英語", 3, -1) == 6, "英語学年の逆循環")
	_assert_true(Constants.cycle_grade_for_subject("英語", 6, 1) == 3, "英語学年の順循環")
	for subject: String in ["算数", "理科", "国語", "社会"]:
		_assert_true(Constants.grades_for_subject(subject) == [1, 2, 3, 4, 5, 6], "%sは従来の1〜6年" % subject)


func _test_question_spacing() -> void:
	var sentence := "I don't like blue apples."
	_assert_true(FractionFormatter.format_question(sentence) == sentence, "英文の空白とアポストロフィを保持")


func _test_english_data(provider: Variant, fetcher: Variant) -> void:
	var file := FileAccess.open("res://offline_bank.json", FileAccess.READ)
	_assert_true(file != null, "オフラインバンクを開ける")
	if file == null:
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_assert_true(raw is Dictionary, "オフラインバンクがJSONオブジェクト")
	if not raw is Dictionary:
		return
	var english: Variant = raw.get("英語", {})
	_assert_true(english is Dictionary, "英語バンクが存在")
	if not english is Dictionary:
		return
	var global_seen: Dictionary = {}
	for grade: int in range(3, 7):
		var items: Variant = english.get(str(grade), [])
		_assert_true(items is Array and items.size() == 150, "英語%d年が150問" % grade)
		if not items is Array:
			continue
		var genres: Dictionary = {}
		var slots := [0, 0, 0, 0]
		var tier_counts := {"基本": 0, "標準": 0, "応用": 0}
		for item_raw: Variant in items:
			_assert_true(item_raw is Dictionary, "英語%d年の問題形式" % grade)
			if not item_raw is Dictionary:
				continue
			var q := str(item_raw.get("q", ""))
			for tier: String in tier_counts:
				if q.begins_with("【%s】" % tier):
					tier_counts[tier] += 1
			var choices: Variant = item_raw.get("c", [])
			var answer := int(item_raw.get("a", -1))
			_assert_true(not q.is_empty() and q.length() <= 50 and not q.contains("�"), "英語%d年の問題文品質" % grade)
			_assert_true(not global_seen.has(q), "英語問題が全学年で重複しない")
			global_seen[q] = true
			_assert_true(choices is Array and choices.size() == 4, "英語%d年は4択" % grade)
			if choices is Array:
				var choice_seen: Dictionary = {}
				for choice_raw: Variant in choices:
					var choice := str(choice_raw)
					_assert_true(not choice.is_empty() and choice.length() <= 24 and not choice.contains("�"), "英語%d年の選択肢品質" % grade)
					choice_seen[choice] = true
				_assert_true(choice_seen.size() == choices.size(), "英語%d年の選択肢が一意" % grade)
			_assert_true(answer >= 0 and answer < 4, "英語%d年の正解番号" % grade)
			if answer >= 0 and answer < 4:
				slots[answer] += 1
			var genre := str(item_raw.get("g", ""))
			_assert_true(not genre.is_empty(), "英語%d年にジャンルあり" % grade)
			genres[genre] = true
			_assert_true(not str(item_raw.get("exp", "")).is_empty(), "英語%d年に解説あり" % grade)
		_assert_true(genres.size() >= 5, "英語%d年に5ジャンル以上" % grade)
		_assert_true(slots.max() - slots.min() <= 1, "英語%d年の正解位置が均等" % grade)
		for tier: String in tier_counts:
			_assert_true(tier_counts[tier] == 50, "英語%d年/%sが50問" % [grade, tier])

		var curriculum := CurriculumDB.load_grade("英語", grade)
		_assert_true(not curriculum.is_empty(), "英語%d年カリキュラム読込" % grade)
		_assert_true(str(curriculum.get("subject", "")) == "英語", "英語%d年カリキュラム教科" % grade)
		_assert_true(int(curriculum.get("grade", 0)) == grade, "英語%d年カリキュラム学年" % grade)
		_assert_true(curriculum.get("units", []).size() >= 8, "英語%d年に8単元以上" % grade)
		var units: PackedStringArray = []
		for unit: Variant in curriculum.get("units", []).slice(0, 2):
			units.append(str(unit.get("name", "")))
		var empty_history: Array[String] = []
		var prompt: String = str(fetcher.compose_prompt(
			"英語", grade, "普通", 4, empty_history, false, units, false
		))
		_assert_true(prompt.contains("音声を聞かなければ解けない"), "英語%d年で音声依存問題を禁止" % grade)
		_assert_true(prompt.contains("解説(e)は日本語"), "英語%d年の解説言語" % grade)
		if grade <= 4:
			_assert_true(prompt.contains("問題の指示を日本語"), "英語%d年は日本語補助中心" % grade)
		else:
			_assert_true(prompt.contains("短い英文・二往復以内の会話"), "英語%d年は短い英文を追加" % grade)

		for difficulty: String in Constants.DIFFICULTY_LEVELS:
			var selected: Array = provider.get_quizzes("英語", grade, difficulty, Constants.MODE_TEN, 10)
			_assert_true(selected.size() == 10, "英語%d年/%sで10問取得" % [grade, difficulty])
			var selected_seen: Dictionary = {}
			var expected_tier: String = {
				"簡単": "【基本】", "普通": "【標準】", "難しい": "【応用】"
			}[difficulty]
			var tier_matches := 0
			for quiz: QuizItem in selected:
				_assert_true(quiz != null and quiz.src == "OFFLINE", "英語%d年/%sで算数フォールバックなし" % [grade, difficulty])
				if quiz == null:
					continue
				selected_seen[quiz.q] = true
				if quiz.q.begins_with(expected_tier):
					tier_matches += 1
			_assert_true(selected_seen.size() == selected.size(), "英語%d年/%sの10問が一意" % [grade, difficulty])
			_assert_true(tier_matches >= 8, "英語%d年/%sの難易度帯" % [grade, difficulty])


func _test_coop_conversion(provider: Variant) -> void:
	var quizzes: Array = provider.get_quizzes("英語", 5, "普通", Constants.MODE_TEN, 1)
	_assert_true(not quizzes.is_empty(), "協力テスト用英語問題を取得")
	if quizzes.is_empty():
		return
	var coop_builder = load("res://scripts/core/coop_quiz_builder.gd")
	var coop: QuizItem = coop_builder.build_coop_quiz(quizzes[0], "英語", 5, 0)
	_assert_true(coop != null, "英語問題を協力形式へ変換")
	if coop == null:
		return
	_assert_true(coop.coop_p1_label == "P1 英語カード", "英語協力P1ラベル")
	_assert_true(coop.coop_p2_label == "P2 答えカード", "英語協力P2ラベル")
	_assert_true(coop.coop_p1_choices.size() == 2 and coop.coop_p2_choices.size() == 2, "英語協力は両者2択")
	_assert_true(coop.coop_p1_answer in [0, 1] and coop.coop_p2_answer in [0, 1], "英語協力の正解番号")


func _test_game_state_metadata(provider: Variant) -> void:
	# --script starts before autoload globals are registered, so load this class
	# only after _initialize() has yielded one frame.
	var state = load("res://scripts/core/game_state.gd").new(provider)
	state.subject = "英語"
	state.grade = 5
	state.difficulty = "普通"
	state.mode = Constants.MODE_TEN
	state.num_players = 1
	state.llm_mode = "OFFLINE"
	state.start_game()
	_assert_true(state.quiz_list.size() == 10, "英語ゲーム状態に10問準備")
	_assert_true(state.current_quiz != null, "英語の現在問題を設定")
	if state.current_quiz == null:
		return
	_assert_true(state.current_quiz.c.size() == 2, "通常の第1問を2択化")
	_assert_true(not state.current_quiz.genre.is_empty(), "2択化後も英語単元ラベルを保持")
	_assert_true(state.current_quiz.src == "OFFLINE", "2択化後もオフライン出典を保持")


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failures += 1
	push_error("FAIL: %s" % label)
