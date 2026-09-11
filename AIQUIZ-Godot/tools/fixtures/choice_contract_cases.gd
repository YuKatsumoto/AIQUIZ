extends RefCounted

const HistoryFixtures := preload("res://tools/fixtures/generation_history_cases.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 30:
		failures.append(label)

func run() -> int:
	QuizManager.provider.set_llm_mode("OFFLINE")
	var bank := QuizProvider.new()
	var source := QuizItem.create("正しいものは？", ["甲", "乙", "丙", "丁"], 3, "解説", "TEST", "", ["a.png", "b.png", "c.png", "d.png"], 6.2)
	source.genre = "言葉"
	source.validated = true
	for _i: int in range(100):
		var reduced := bank.prepare_choice_count(source, 2)
		check(reduced.c.size() == 2 and reduced.c[reduced.a] == "丁", "Reduction retained the correct answer")
		check(reduced.choice_img.size() == 2 and reduced.choice_img[reduced.a] == "d.png", "Choice images followed the selected answers")
		check(reduced.genre == source.genre and reduced.validated and reduced.estimated_seconds == source.estimated_seconds, "Reduction preserved metadata")
	check(source.c.size() == 4 and source.a == 3 and source.choice_img[3] == "d.png", "Original resource was not mutated")
	check(bank.prepare_choice_count(QuizItem.create("Duplicate", ["1", "1"], 0), 2) == null, "Duplicate answer texts rejected")
	var binary := QuizItem.create("太陽がのぼるのは？", ["東", "西"], 0)
	check(bank.prepare_choice_count(binary, 4) == null, "No invented text distractors")
	var numeric := QuizItem.create("3+4は？", ["7", "8"], 0)
	numeric.genre = "足し算"
	numeric.src = "GEMINI_STREAM"
	var expanded := bank.prepare_choice_count(numeric, 4)
	check(expanded != null and expanded.c.size() == 4 and expanded.c[expanded.a] == "7" and expanded.genre == "足し算", "Numeric expansion preserved answer and genre")
	var hard_source := QuizItem.create("100+100は？", ["1", "200", "900", "5000"], 1, "", "OFFLINE", "", [], 7.1)
	hard_source.genre = "計算"
	hard_source.validated = true
	var hardened := bank._harden_distractors(hard_source)
	check(hardened.genre == "計算" and hardened.estimated_seconds == 7.1 and hardened.validated, "Hard distractors retain quiz metadata")

	var rounds := 0
	for subject: String in bank.bank:
		var grades: Dictionary = bank.bank[subject]
		for grade_text: String in grades:
			for difficulty: String in Constants.DIFFICULTY_LEVELS:
				for mode: String in [Constants.MODE_TEN, Constants.MODE_ENDLESS]:
					var state := QuizGameState.new(bank)
					state.subject = subject
					state.grade = int(grade_text)
					state.difficulty = difficulty
					state.mode = mode
					state.target_count = 10 if mode == Constants.MODE_TEN else 1
					state.quiz_list = bank.get_quizzes(subject, int(grade_text), difficulty, mode, state.target_count)
					var answers: Dictionary = {}
					for q: QuizItem in state.quiz_list:
						answers[q.q] = q.c[q.a]
					state._prepare_quiz_choices()
					check(state.quiz_list.size() == state.target_count, "Round filled: %s %s %s %s" % [subject,grade_text,difficulty,mode])
					for i: int in range(state.quiz_list.size()):
						var expected := 4 if difficulty == "難しい" or (mode == Constants.MODE_TEN and i == 9) else 2
						var q: QuizItem = state.quiz_list[i]
						check(q.c.size() == expected and state.num_choices_for_index(i) == expected, "Preview count: %s %s %s %s Q%d" % [subject,grade_text,difficulty,mode,i+1])
						check(q.c[q.a] == answers[q.q], "Answer retained in preview")
						state.current_index = i
						state.load_current_quiz()
						check(state.num_choices == expected and state.choices_text().size() == expected, "Gameplay/HUD count matches preview")
					rounds += 1
	var endless := QuizGameState.new(bank)
	endless.mode = Constants.MODE_ENDLESS
	endless.difficulty = "難しい"
	endless.current_index = 25
	endless.current_wall_index = 25
	endless.game_state = Constants.STATE_PRELOADING
	endless.quiz_list.clear()
	endless._update_preloading(0.5)
	check(endless.game_state == Constants.STATE_PLAYING and endless.quiz_list.size() == 1 and endless.current_quiz.c.size() == 4, "Endless Q26 resumes as soon as one question arrives")

	var fixtures := HistoryFixtures.new()
	var buffer: BufferedQuizProvider = fixtures.new_provider()
	buffer.current_mode = Constants.MODE_TEN
	buffer.current_difficulty = "難しい"
	buffer._on_fetch_partial([binary, expanded, source])
	check(buffer.buffer.size() == 2, "Online-shaped mixed input rejects non-expandable binary data")
	buffer.current_difficulty = "普通"
	buffer._dispatched_items.append(source)
	var presented := buffer.prepare_choice_count(source, 2)
	check(buffer._dispatched_items[0] == presented, "Async metadata follows presented choices")
	var coop := QuizGameState.new(bank)
	coop.mode = Constants.MODE_COOP
	coop.num_players = 2
	coop.subject = "算数"
	coop.grade = 3
	coop.target_count = 10
	coop.quiz_list = bank.get_quizzes("算数", 3, "普通", Constants.MODE_TEN, 10)
	coop._prepare_coop_quiz_list()
	coop._prepare_quiz_choices()
	for i: int in range(coop.quiz_list.size()):
		check(coop.num_choices_for_index(i) == 2 and coop.quiz_list[i].has_coop_data(), "Coop preserves two doors per player")
	fixtures.dispose(buffer)
	bank.free()
	print("[ChoiceContract] rounds=%d checks=%d failures=%d" % [rounds, checks, failures.size()])
	for failure: String in failures:
		printerr("[ChoiceContract] FAIL: " + failure)
	return failures.size()
