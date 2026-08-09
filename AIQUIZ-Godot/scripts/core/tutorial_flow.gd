extends RefCounted
class_name TutorialFlow

signal step_changed(step_id: String, step_index: int, step_count: int)
signal task_completed(player_index: int, task_id: String)
signal presentation_requested(presentation_id: String, context: Dictionary)
signal presentation_finished(presentation_id: String)

const COURSE_SOLO := "SOLO"
const COURSE_LOCAL_2P := "LOCAL_2P"

const BASICS_ADVANCE_DELAY := 3.0

var course: String = COURSE_SOLO
var step_index: int = 0
var revision: int = 0
var presentation_locked: bool = false
var awaiting_neutral_input: bool = false

var _steps: Array[Dictionary] = []
var _tasks: Dictionary = {}
var _basics_complete_hold: float = -1.0


func start(selected_course: String) -> void:
	course = COURSE_LOCAL_2P if selected_course == COURSE_LOCAL_2P else COURSE_SOLO
	_steps = _build_steps(course)
	step_index = 0
	revision += 1
	_basics_complete_hold = -1.0
	_enter_current_step()


func current_step() -> Dictionary:
	if step_index < 0 or step_index >= _steps.size():
		return {}
	return _steps[step_index]


func current_step_id() -> String:
	return str(current_step().get("id", ""))


func is_step(step_id: String) -> bool:
	return current_step_id() == step_id


func step_count() -> int:
	return _steps.size()


func advance_step() -> bool:
	if step_index + 1 >= _steps.size():
		return false
	step_index += 1
	revision += 1
	_enter_current_step()
	return true


func restart_current_step(replay_presentation: bool = false) -> void:
	_rebuild_tasks()
	presentation_locked = replay_presentation and not presentation_id().is_empty()
	awaiting_neutral_input = not presentation_locked
	revision += 1
	step_changed.emit(current_step_id(), step_index, _steps.size())
	if presentation_locked:
		presentation_requested.emit(presentation_id(), presentation_context())


func presentation_id() -> String:
	return str(current_step().get("presentation", ""))


func presentation_duration() -> float:
	return float(current_step().get("duration", 1.5))


func presentation_context() -> Dictionary:
	var step: Dictionary = current_step()
	return {
		"course": course,
		"step_id": current_step_id(),
		"step_index": step_index,
		"step_count": _steps.size(),
		"duration": presentation_duration(),
		"hazard_player": int(step.get("hazard_player", 0)),
		"ghost_player": int(step.get("ghost_player", 0)),
		"highlight_answer": int(step.get("highlight_answer", -1)),
		"revision": revision,
	}


func finish_presentation(expected_id: String = "") -> bool:
	if not presentation_locked:
		return false
	if not expected_id.is_empty() and expected_id != presentation_id():
		return false
	var finished_id := presentation_id()
	presentation_locked = false
	awaiting_neutral_input = true
	revision += 1
	presentation_finished.emit(finished_id)
	return true


func current_step_advances_after_presentation() -> bool:
	return bool(current_step().get("auto_after_presentation", false))


func consume_input_gate(
		axis_p1: Vector2,
		axis_p2: Vector2,
		jump_p1: bool,
		jump_p2: bool,
		emote_p1: int,
		emote_p2: int) -> bool:
	if presentation_locked:
		return true
	if not awaiting_neutral_input:
		return false
	var neutral := (
		axis_p1.length_squared() < 0.01
		and axis_p2.length_squared() < 0.01
		and not jump_p1
		and not jump_p2
		and emote_p1 <= 0
		and emote_p2 <= 0
	)
	if neutral:
		awaiting_neutral_input = false
		revision += 1
		return false
	return true


func update_basic_controls(
		axis_p1: Vector2,
		axis_p2: Vector2,
		jump_p1: bool,
		jump_p2: bool,
		emote_p1: int,
		emote_p2: int,
		delta: float = 0.0) -> bool:
	if not is_step("basics") or presentation_locked or awaiting_neutral_input:
		_basics_complete_hold = -1.0
		return false
	_update_player_controls(1, axis_p1, jump_p1, emote_p1)
	if course == COURSE_LOCAL_2P:
		_update_player_controls(2, axis_p2, jump_p2, emote_p2)
	# 全員の移動操作が揃ってから少し待って次へ進む
	if not all_tasks_complete():
		_basics_complete_hold = -1.0
		return false
	if _basics_complete_hold < 0.0:
		_basics_complete_hold = 0.0
		return false
	_basics_complete_hold = minf(BASICS_ADVANCE_DELAY, _basics_complete_hold + delta)
	return _basics_complete_hold >= BASICS_ADVANCE_DELAY


func complete_task(player_index: int, task_id: String) -> bool:
	var player_tasks: Array = _tasks.get(player_index, [])
	for task_variant: Variant in player_tasks:
		var task: Dictionary = task_variant
		if str(task.get("id", "")) != task_id or bool(task.get("done", false)):
			continue
		task["done"] = true
		revision += 1
		task_completed.emit(player_index, task_id)
		return true
	return false


func all_tasks_complete() -> bool:
	var found_task := false
	for player_tasks_variant: Variant in _tasks.values():
		var player_tasks: Array = player_tasks_variant
		for task_variant: Variant in player_tasks:
			found_task = true
			var task: Dictionary = task_variant
			if not bool(task.get("done", false)):
				return false
	return found_task


func is_ghost_practice() -> bool:
	return current_step_id() in ["p2_ghost_wall", "p1_ghost_ocean"]


func designated_ghost_player() -> int:
	return int(current_step().get("ghost_player", 0))


func designated_hazard_player() -> int:
	return int(current_step().get("hazard_player", 0))


func is_quiz_step() -> bool:
	return current_step_id() in ["quiz_left", "quiz_right", "quiz_free", "duo_quiz", "duo_quiz_free"]


func should_scroll_world() -> bool:
	return is_quiz_step()


func guided_answer() -> int:
	return int(current_step().get("highlight_answer", -1))


func world_guide() -> String:
	return str(current_step().get("world_guide", ""))


func get_overlay_model() -> Dictionary:
	var step: Dictionary = current_step()
	var players: Array[Dictionary] = []
	for player_index: int in [1, 2]:
		if player_index == 2 and course != COURSE_LOCAL_2P:
			continue
		var copied_tasks: Array[Dictionary] = []
		for task_variant: Variant in _tasks.get(player_index, []):
			copied_tasks.append((task_variant as Dictionary).duplicate(true))
		players.append({
			"player": player_index,
			"label": "P%d" % player_index,
			"tasks": copied_tasks,
		})
	return {
		"visible": true,
		"course": course,
		"step_id": current_step_id(),
		"step_index": step_index,
		"step_number": step_index + 1,
		"step_count": _steps.size(),
		"title": str(step.get("title", "チュートリアル")),
		"body": str(step.get("body", "")),
		"presentation_locked": presentation_locked,
		"awaiting_neutral_input": awaiting_neutral_input,
		"skip_text": "[Enter] 演出スキップ" if presentation_locked else "",
		"players": players,
		"revision": revision,
		"world_guide": world_guide(),
		"highlight_answer": guided_answer(),
	}


func _enter_current_step() -> void:
	_rebuild_tasks()
	_basics_complete_hold = -1.0
	presentation_locked = not presentation_id().is_empty()
	awaiting_neutral_input = not presentation_locked
	step_changed.emit(current_step_id(), step_index, _steps.size())
	if presentation_locked:
		presentation_requested.emit(presentation_id(), presentation_context())


func _rebuild_tasks() -> void:
	_tasks.clear()
	var source: Dictionary = current_step().get("tasks", {})
	for player_key: Variant in source.keys():
		var copied: Array[Dictionary] = []
		for task_variant: Variant in source[player_key]:
			var task: Dictionary = (task_variant as Dictionary).duplicate(true)
			task["done"] = false
			copied.append(task)
		_tasks[int(player_key)] = copied


func _update_player_controls(player_index: int, axis: Vector2, jump: bool, emote: int) -> void:
	if axis.x > 0.35:
		complete_task(player_index, "left")
	if axis.x < -0.35:
		complete_task(player_index, "right")
	if axis.y > 0.35:
		complete_task(player_index, "forward")
	if axis.y < -0.35:
		complete_task(player_index, "back")
	if jump:
		complete_task(player_index, "jump")
	if emote > 0:
		complete_task(player_index, "emote")


func _control_tasks(player_index: int) -> Array[Dictionary]:
	var p1 := player_index == 1
	return [
		{"id": "left", "key": "A" if p1 else "←", "caption": "左へ"},
		{"id": "right", "key": "D" if p1 else "→", "caption": "右へ"},
		{"id": "forward", "key": "W" if p1 else "↑", "caption": "前へ"},
		{"id": "back", "key": "S" if p1 else "↓", "caption": "後ろへ"},
		{"id": "jump", "key": "Space" if p1 else "Ctrl / Num0", "caption": "ジャンプ"},
		{"id": "emote", "key": "1 / 2 / 3" if p1 else "8 / 9 / 0", "caption": "エモート"},
	]


func _build_steps(selected_course: String) -> Array[Dictionary]:
	if selected_course == COURSE_LOCAL_2P:
		return [
			{
				"id": "intro", "title": "ローカル2P 実践コース",
				"body": "P1とP2の操作、個別回答、脱落後のゴーストシャーク、最終レースを体験します。",
				"world_guide": "players", "tasks": {},
			},
			{
				"id": "basics", "title": "2人の基本操作",
				"body": "P1はオレンジ、P2はシアンです。2人とも全方向・ジャンプ・エモートを試しましょう。",
				"world_guide": "controls",
				"tasks": {1: _control_tasks(1), 2: _control_tasks(2)},
			},
			{
				"id": "duo_quiz", "title": "2人とも正解しよう",
				"body": "同じ正解ドアを選びます。得点はP1とP2で別々に表示されます。",
				"highlight_answer": 0,
				"world_guide": "guided_door",
				"tasks": {
					1: [{"id": "answer", "key": "A", "caption": "左ドア"}],
					2: [{"id": "answer", "key": "←", "caption": "左ドア"}],
				},
			},
			{
				"id": "p2_ghost_wall", "title": "P2 脱落とゴーストシャーク",
				"body": "P2だけ中央の壁へ進みます。脱落後は照準を動かし、長押ししてP1へ突進します。",
				"hazard_player": 2, "ghost_player": 2,
				"world_guide": "wall_hazard",
				"tasks": {2: [
					{"id": "aim", "key": "矢印", "caption": "照準移動"},
					{"id": "charge", "key": "Ctrl / Num0", "caption": "長押し→離す"},
					{"id": "hit", "key": "HIT", "caption": "P1へ命中"},
				]},
			},
			{
				"id": "p1_ghost_ocean", "title": "P1 海とゴーストシャーク",
				"body": "今度はP1だけ海へ落ちます。サメ演出後、ゴーストシャークでP2へ命中させましょう。",
				"hazard_player": 1, "ghost_player": 1,
				"world_guide": "ocean_hazard",
				"tasks": {1: [
					{"id": "aim", "key": "WASD", "caption": "照準移動"},
					{"id": "charge", "key": "Space", "caption": "長押し→離す"},
					{"id": "hit", "key": "HIT", "caption": "P2へ命中"},
				]},
			},
			{
				"id": "duo_quiz_free", "title": "誘導なしの実践問題",
				"body": "強調表示はありません。問題を読んで、2人とも自分でドアを選びましょう。",
				"highlight_answer": -1,
				"world_guide": "quiz_free",
				"tasks": {
					1: [{"id": "answer", "key": "A / D", "caption": "自分で回答"}],
					2: [{"id": "answer", "key": "← / →", "caption": "自分で回答"}],
				},
			},
			{
				"id": "goal", "title": "最終レース",
				"body": "ゴールゲートまで走ります。先に到着したプレイヤーが勝者です。",
				"presentation": "goal_sweep", "duration": 1.15, "world_guide": "goal",
				"tasks": {
					1: [{"id": "goal", "key": "W", "caption": "GOALへ"}],
					2: [{"id": "goal", "key": "↑", "caption": "GOALへ"}],
				},
			},
			{
				"id": "complete", "title": "ローカル2Pコース完了",
				"body": "2人の操作、個別回答、両プレイヤーのゴースト操作、最終レースを習得しました。",
				"presentation": "completion_hero", "duration": 1.0,
				"world_guide": "complete", "tasks": {},
			},
		]

	return [
		{
			"id": "intro", "title": "1P 実践コース",
			"body": "基本操作、クイズの扉、壁と海の危険、ゴールまでを順番に体験します。",
			"world_guide": "player", "tasks": {},
		},
		{
			"id": "basics", "title": "基本操作を試そう",
			"body": "全方向へ動き、ジャンプとエモートを1回ずつ試すと次へ進みます。",
			"world_guide": "controls",
			"tasks": {1: _control_tasks(1)},
		},
		{
			"id": "quiz_left", "title": "左の正解ドア",
			"body": "黄色く光る左ドアへ移動して、壁を突破しましょう。",
			"highlight_answer": 0,
			"world_guide": "guided_door",
			"tasks": {1: [{"id": "answer", "key": "A", "caption": "左ドア"}]},
		},
		{
			"id": "quiz_right", "title": "右の正解ドア",
			"body": "次は黄色く光る右ドアへ移動します。",
			"highlight_answer": 1,
			"world_guide": "guided_door",
			"tasks": {1: [{"id": "answer", "key": "D", "caption": "右ドア"}]},
		},
		{
			"id": "quiz_free", "title": "誘導なしの実践問題",
			"body": "今度は正解が光りません。問題を読んで自分でドアを選びましょう。",
			"highlight_answer": -1,
			"world_guide": "quiz_free",
			"tasks": {1: [{"id": "answer", "key": "A / D", "caption": "自分で回答"}]},
		},
		{
			"id": "wall_hazard", "title": "壁にぶつかったとき",
			"body": "赤く示された中央の壁へ進み、ラグドールと復帰の流れを体験します。",
			"hazard_player": 1,
			"world_guide": "wall_hazard",
			"tasks": {1: [{"id": "wall", "key": "W", "caption": "中央の壁へ"}]},
		},
		{
			"id": "ocean_hazard", "title": "海へ落ちたとき",
			"body": "床の外へ進み、遊泳とサメ襲撃を体験します。演出後は安全に復帰します。",
			"hazard_player": 1,
			"world_guide": "ocean_hazard",
			"tasks": {1: [{"id": "ocean", "key": "A / D", "caption": "海へ出る"}]},
		},
		{
			"id": "goal", "title": "ゴールへ走ろう",
			"body": "前方のゴールゲートまで走れば1Pコース完了です。",
			"presentation": "goal_sweep", "duration": 1.15, "world_guide": "goal",
			"tasks": {1: [{"id": "goal", "key": "W", "caption": "GOALへ"}]},
		},
		{
			"id": "complete", "title": "1Pコース完了",
			"body": "基本操作、クイズ、壁と海の危険、ゴールまでを習得しました。",
			"presentation": "completion_hero", "duration": 1.0,
			"world_guide": "complete", "tasks": {},
		},
	]
