class_name SuddenDeathGame
extends RefCounted

## 新サドンデスの種目のルールの基底（docs/sudden_death_v2/common.md 8.1節）。
## 判定だけを持ち、表示は持たない。QuizGameState が毎フレーム step() を呼び、積まれた出来事
## （events）を監督（HeliSuddenDeathDirector）へ渡して消す。
##
## 入力は1フレーム分の辞書（QuizGameState.submit_sudden_death_key が作る）：
##   {"answer": [P1の選択肢, P2の選択肢]（-1 = 押していない）, "answer_offset": [秒, 秒],
##    "action": [P1の秒, P2の秒]（-1 = 押していない）}
## 秒はフレームの頭からの時刻。step() は入力をその時刻の位置で当てはめるので、同じ入力なら
## 30 / 60 / 120fps で同じ結果になる。

## 種目の名前（記録の "game"）。
var kind := ""
var quizzes: Array[QuizItem] = []
## 今の問題（0から）。-1 = まだ出していない。
var question_index := -1
## 用意した問題を使い切ったときの1問（QuizGameState が算数の自動生成を渡す）。
var extra_question: Callable
## 0 = 未決着、1 / 2 = 勝者。
var winner := 0
var decided_by := ""
## 決着してルールが終わった。
var finished := false
var events: Array[Dictionary] = []
## 監督の導入が終わって start() が呼ばれるまで待つ。
var waiting_for_start := true
var rng := RandomNumberGenerator.new()


func setup(questions: Array[QuizItem], seed_value: int) -> void:
	quizzes = questions.duplicate()
	question_index = -1
	winner = 0
	decided_by = ""
	finished = false
	events.clear()
	waiting_for_start = true
	rng.seed = seed_value


## 導入が終わった（カウントダウンから始める）。
func start() -> void:
	waiting_for_start = false


func is_running() -> bool:
	return not waiting_for_start and not finished


## 1フレーム進める。入力は時刻の順に当てはめる。
func step(dt: float, input: Dictionary) -> void:
	if waiting_for_start or finished:
		return
	var presses := _sorted_presses(input, dt)
	var cursor := 0.0
	for press: Dictionary in presses:
		var at := clampf(float(press.at), cursor, dt)
		_advance(at - cursor)
		cursor = at
		if finished:
			return
		_apply_press(press)
	_advance(maxf(0.0, dt - cursor))


## 一時停止・フォーカスを失った（種目ごとに扱いを決める）。
func interrupt() -> void:
	pass


func current_quiz() -> QuizItem:
	if question_index < 0 or question_index >= quizzes.size():
		return null
	return quizzes[question_index]


func current_choices() -> int:
	var quiz := current_quiz()
	return quiz.c.size() if quiz != null else 4


## 記録（MatchReel の sudden_death）。
func record() -> Dictionary:
	return {"game": kind, "winner": winner, "by": decided_by, "questions": question_index + 1, "detail": {}}


func get_debug_snapshot() -> Dictionary:
	return {"kind": kind, "question": question_index, "winner": winner, "finished": finished}


# ------------------------------------------------------------------ 種目が書く部分

## span 秒だけ時計を進める（段階の切り替えは中で行う）。
func _advance(_span: float) -> void:
	pass


## 押した瞬間：{"player": 1|2, "type": "answer"|"action", "value": 選択肢}
func _apply_press(_press: Dictionary) -> void:
	pass


# ------------------------------------------------------------------ 共通

func _emit(event_kind: String, data := {}) -> void:
	var event := data.duplicate()
	event["kind"] = event_kind
	events.append(event)


## 次の問題へ進む。用意した問題が尽きたら extra_question で1問足す。
func _next_quiz() -> QuizItem:
	question_index += 1
	if question_index >= quizzes.size():
		var extra: QuizItem = extra_question.call() if extra_question.is_valid() else null
		if extra == null:
			question_index = quizzes.size() - 1
			return current_quiz()
		quizzes.append(extra)
	return quizzes[question_index]


func _sorted_presses(input: Dictionary, dt: float) -> Array[Dictionary]:
	var presses: Array[Dictionary] = []
	if input.is_empty():
		return presses
	var answers: Array = input.get("answer", [-1, -1])
	var answer_offsets: Array = input.get("answer_offset", [0.0, 0.0])
	var actions: Array = input.get("action", [-1.0, -1.0])
	for slot in [0, 1]:
		if slot < answers.size() and int(answers[slot]) >= 0:
			presses.append({"player": slot + 1, "type": "answer", "value": int(answers[slot]),
				"at": clampf(float(answer_offsets[slot]) if slot < answer_offsets.size() else 0.0, 0.0, dt)})
		if slot < actions.size() and float(actions[slot]) >= 0.0:
			presses.append({"player": slot + 1, "type": "action", "value": -1, "at": clampf(float(actions[slot]), 0.0, dt)})
	presses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.at), float(b.at)):
			return int(a.player) < int(b.player)
		return float(a.at) < float(b.at))
	return presses
