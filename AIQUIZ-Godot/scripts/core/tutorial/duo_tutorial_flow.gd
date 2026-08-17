extends RefCounted
class_name DuoTutorialFlow

## ローカル2P（デュオ）チュートリアルコース。
## 1Pコースは res://scripts/core/tutorial/solo_tutorial_flow.gd が担当する。
## 両クラスは QuizGameState から同じメソッド面で呼ばれるため、
## 片方にクエリを足したらもう片方にも同名で足すこと。
##
## 学習順は1Pと同じ「操作 → 危険 → 回答 → 実践 → 決着」の9ステップ。
## 一度に提示する操作は各プレイヤー最大3つまでに抑え、海とゴーストシャークを
## 先に体験させてから誘導なしの実戦に入る。誘導なしの実戦だけは本編と同じ
## 個別判定で、間違えた側だけが本当に脱落してゴーストシャークへ回る。

signal step_changed(step_id: String, step_index: int, step_count: int)
signal task_completed(player_index: int, task_id: String)
signal presentation_requested(presentation_id: String, context: Dictionary)
signal presentation_finished(presentation_id: String)

const COURSE_LOCAL_2P := "LOCAL_2P"

## 走路エッジのレーンライン、床投影リング、ドアのルートラインなどの表示切替に使う。
const GUIDE_LANE := "lane"
const GUIDE_AIR := "air"
const GUIDE_EMOTE := "emote"
const GUIDE_OCEAN := "ocean"
const GUIDE_GHOST := "ghost"
const GUIDE_GUIDED_DOOR := "guided_door"
const GUIDE_FREE_DOOR := "free_door"
const GUIDE_GOAL := "goal"
const GUIDE_COMPLETE := "complete"

const TASK_HOLD_SECONDS := 0.55
const HINT_SECONDS := 3.4
const GATE_GRACE_SECONDS := 0.7
const WALL_COUNT := 3

var course: String = COURSE_LOCAL_2P
var step_index: int = 0
var revision: int = 0
var presentation_locked: bool = false
var awaiting_neutral_input: bool = false

var _steps: Array[Dictionary] = []
var _tasks: Dictionary = {}
var _quiz_cursor: int = 0
var _task_hold: float = -1.0
var _hint_text: String = ""
var _hint_timer: float = 0.0
var _gate_elapsed: float = 0.0
var _death_recovery_active: bool = false
var _death_recovery_duration: float = 0.0
var _death_recovery_retry: bool = false


func start(_selected_course: String = COURSE_LOCAL_2P) -> void:
	course = COURSE_LOCAL_2P
	_steps = _build_steps()
	step_index = 0
	revision += 1
	_clear_transient_state()
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
	_quiz_cursor = 0
	_rebuild_tasks()
	_task_hold = -1.0
	presentation_locked = replay_presentation and not presentation_id().is_empty()
	awaiting_neutral_input = not presentation_locked
	revision += 1
	step_changed.emit(current_step_id(), step_index, _steps.size())
	if presentation_locked:
		presentation_requested.emit(presentation_id(), presentation_context())


# ---------- 演出 ----------

func presentation_id() -> String:
	return str(current_step().get("presentation", ""))


func presentation_duration() -> float:
	return float(current_step().get("duration", 1.0))


func presentation_context() -> Dictionary:
	return {
		"course": course,
		"step_id": current_step_id(),
		"step_index": step_index,
		"step_count": _steps.size(),
		"duration": presentation_duration(),
		"hazard_player": designated_hazard_player(),
		"ghost_player": designated_ghost_player(),
		"highlight_answer": guided_answer(),
		"revision": revision,
	}


## 1Pと同じ理由で presentation ID の一致は要求しない。ID の取り違えで演出が
## 永久ロックするより、現在ステップの演出を確実に閉じる方を優先する。
func finish_presentation(_expected_id: String = "") -> bool:
	if not presentation_locked:
		return false
	var finished_id := presentation_id()
	presentation_locked = false
	awaiting_neutral_input = true
	revision += 1
	presentation_finished.emit(finished_id)
	return true


func current_step_advances_after_presentation() -> bool:
	return bool(current_step().get("auto_after_presentation", false))


## 完了カードを見せ終えたら、勝者と個別スコアが並ぶリザルト画面へ送る。
func should_clear_after_presentation() -> bool:
	return true


# ---------- 入力 ----------

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
	# ミスで押しっぱなしのまま復帰した場合に世界が止まり続けないよう、
	# 中立入力が来なくても GATE_GRACE_SECONDS で必ずゲートを開ける。
	var neutral := (
		axis_p1.length_squared() < 0.01
		and axis_p2.length_squared() < 0.01
		and not jump_p1
		and not jump_p2
		and emote_p1 <= 0
		and emote_p2 <= 0
	)
	if neutral or _gate_elapsed >= GATE_GRACE_SECONDS:
		awaiting_neutral_input = false
		revision += 1
		return false
	return true


func tick(delta: float) -> void:
	if awaiting_neutral_input and not presentation_locked:
		_gate_elapsed += delta
	else:
		_gate_elapsed = 0.0
	if _hint_timer > 0.0:
		_hint_timer = maxf(0.0, _hint_timer - delta)
		if _hint_timer <= 0.0:
			_hint_text = ""
			revision += 1


func is_input_practice_step() -> bool:
	return bool(current_step().get("input_practice", false))


## 2Pも導入ステップを持たず、カウントダウン直後に最初の操作練習が始まる。
func advances_after_countdown() -> bool:
	return false


## 操作練習ステップの進行。2人分のタスクが揃ったら true を返す。
func update_input_practice(
		axis_p1: Vector2,
		axis_p2: Vector2,
		jump_p1: bool,
		jump_p2: bool,
		emote_p1: int,
		emote_p2: int,
		delta: float = 0.0) -> bool:
	if not is_input_practice_step() or presentation_locked or awaiting_neutral_input:
		_task_hold = -1.0
		return false

	_update_player_controls(1, axis_p1, jump_p1, emote_p1)
	_update_player_controls(2, axis_p2, jump_p2, emote_p2)

	if not all_tasks_complete():
		_task_hold = -1.0
		return false
	if _task_hold < 0.0:
		_task_hold = 0.0
		return false
	_task_hold = minf(TASK_HOLD_SECONDS, _task_hold + delta)
	return _task_hold >= TASK_HOLD_SECONDS


# ---------- タスク ----------

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


# ---------- クイズ ----------

func is_quiz_step() -> bool:
	return not _quiz_indices().is_empty()


func quiz_index() -> int:
	var indices := _quiz_indices()
	if indices.is_empty():
		return -1
	return indices[mini(_quiz_cursor, indices.size() - 1)]


## 1問終えた後に呼ぶ。ステップ全体を終えたとき true、
## 同じステップ内にまだ問題が残っているとき false を返す。
func on_quiz_cleared() -> bool:
	var indices := _quiz_indices()
	if indices.is_empty():
		return true
	_quiz_cursor += 1
	revision += 1
	if _quiz_cursor >= indices.size():
		return true
	_rebuild_tasks()
	return false


func guided_answer() -> int:
	return int(current_step().get("highlight_answer", -1))


## 誘導ありの問題では2人揃って優しくやり直させ、誘導なしの実戦だけ
## 本編と同じ個別判定にする。
func punishes_mistakes() -> bool:
	return bool(current_step().get("punish_mistakes", false))


## 誘導ありの問題は「2人とも正解」で初めて通過とする。
func requires_both_correct() -> bool:
	return bool(current_step().get("requires_both_correct", false))


func target_quiz_count() -> int:
	return WALL_COUNT


func build_quiz_items() -> Array[QuizItem]:
	# 選択肢の並びは左ドア=index0、右ドア=index1。正解の左右がばらけるよう配置する。
	var items: Array[QuizItem] = [
		QuizItem.create(
			"8 + 7 = ?",
			PackedStringArray(["15", "16"]),
			0,
			"8に7を足すと15です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"5 × 7 = ?",
			PackedStringArray(["30", "35"]),
			1,
			"5を7回足すと35です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"30 - 12 = ?",
			PackedStringArray(["18", "22"]),
			0,
			"30から12を引くと18です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
	]
	return items


# ---------- ワールド挙動クエリ ----------

func should_scroll_world() -> bool:
	return world_speed_scale() > 0.0


func world_speed_scale() -> float:
	return float(current_step().get("speed", 0.0))


func walls_hidden() -> bool:
	return not bool(current_step().get("walls", true))


func wall_count() -> int:
	return WALL_COUNT


func world_guide() -> String:
	return str(current_step().get("guide", ""))


func resets_players_on_advance() -> bool:
	return bool(current_step().get("reset_on_advance", false))


## 誘導ステップでは片方だけが動くので、通常の2P分断ルールを止める。
## 誘導なしの実戦だけは本編どおり分断の危険を残す。
func blocks_scroll_out_death() -> bool:
	return not bool(current_step().get("allow_scroll_out", false))


func allows_ocean_entry(player_index: int) -> bool:
	if is_ocean_hazard_step():
		return designated_hazard_player() == player_index
	# 実戦と最終レースでは本編と同じく、誰が落ちても本当の脱落として扱う。
	return punishes_mistakes() or starts_goal_race()


func is_ocean_hazard_step() -> bool:
	return is_step("duo_ocean")


## 海のハザードを見せた後、復活させずにゴーストシャークの練習ステップへ繋ぐか。
func hands_off_to_ghost_after_hazard() -> bool:
	return bool(current_step().get("ghost_handoff", false))


## 脱落したプレイヤーがゴーストシャークに乗れるステップか。
## チュートリアル中はこのクエリが false のステップでは搭乗させない。
func allows_ghost_ride() -> bool:
	return bool(current_step().get("ghost_ride", false))


## 2人が意図的に離れるステップでは、待機側が画面外へ切れないようカメラを引く。
func splits_camera_for_hazard() -> bool:
	return bool(current_step().get("split_camera", false))


## ステップ開始時に脱落者を復活させるか（最終レースの直前で使う）。
func revives_players() -> bool:
	return bool(current_step().get("revive_players", false))


func starts_goal_race() -> bool:
	return is_step("duo_goal")


func starts_customize_tour() -> bool:
	return false


func is_final_step() -> bool:
	return is_step("duo_complete")


# ---------- ゴースト ----------

func is_ghost_practice() -> bool:
	return is_step("duo_ghost")


func designated_ghost_player() -> int:
	return int(current_step().get("ghost_player", 0))


func designated_hazard_player() -> int:
	return int(current_step().get("hazard_player", 0))


# ---------- 死亡演出からの復帰 ----------

func is_awaiting_death_recovery() -> bool:
	return _death_recovery_active


func death_recovery_duration() -> float:
	return _death_recovery_duration


func begin_death_recovery(duration: float, retry_same_step: bool) -> void:
	_death_recovery_active = true
	_death_recovery_duration = maxf(0.2, duration)
	_death_recovery_retry = retry_same_step
	revision += 1


func finish_death_recovery() -> Dictionary:
	if not _death_recovery_active:
		return {"retry": false, "message": ""}
	var retry := _death_recovery_retry
	_death_recovery_active = false
	_death_recovery_duration = 0.0
	_death_recovery_retry = false
	revision += 1
	var message := (
		"2人とも脱落しました。もう一度同じ問題に挑戦しましょう。"
		if retry
		else "危険を体験できました。ここからは本番と同じ流れです。"
	)
	return {"retry": retry, "message": message}


# ---------- ヒント ----------

func set_hint(text: String, seconds: float = HINT_SECONDS) -> void:
	_hint_text = text
	_hint_timer = maxf(0.0, seconds)
	revision += 1


func clear_summary_lines() -> PackedStringArray:
	return PackedStringArray([
		"✓ 2人分の移動・ジャンプ・エモート",
		"✓ コース外＝海とサメの危険",
		"✓ 脱落後のゴーストシャークで反撃",
		"✓ 1人ずつ判定される実戦と最終レース",
	])


# ---------- UIモデル ----------

func get_overlay_model() -> Dictionary:
	var step: Dictionary = current_step()
	var players: Array[Dictionary] = []
	var flat_tasks: Array[Dictionary] = []
	for player_index: int in [1, 2]:
		var copied_tasks: Array[Dictionary] = []
		for task_variant: Variant in _tasks.get(player_index, []):
			var copied: Dictionary = (task_variant as Dictionary).duplicate(true)
			copied_tasks.append(copied)
			flat_tasks.append(copied)
		players.append({
			"player": player_index,
			"label": "P%d" % player_index,
			"tasks": copied_tasks,
		})
	var indices := _quiz_indices()
	var sub_label := ""
	if indices.size() > 1:
		sub_label = "問題 %d / %d" % [mini(_quiz_cursor + 1, indices.size()), indices.size()]
	return {
		# 完了カードが画面全体を使うので、コーチバーは隠して
		# 使えない Enter スキップ行を出さないようにする。
		"visible": current_step_id() != "duo_complete",
		"course": course,
		"step_id": current_step_id(),
		"step_index": step_index,
		"step_number": step_index + 1,
		"step_count": _steps.size(),
		"title": str(step.get("title", "チュートリアル")),
		"body": str(step.get("body", "")),
		"hint": _hint_text,
		"sub_label": sub_label,
		"presentation_locked": presentation_locked,
		"awaiting_neutral_input": awaiting_neutral_input,
		"skip_text": (
			"[Enter] スキップ"
			if presentation_locked and current_step_id() != "duo_complete"
			else ""
		),
		"tasks": flat_tasks,
		"players": players,
		"ghost_player": designated_ghost_player(),
		"revision": revision,
		"world_guide": world_guide(),
		"highlight_answer": guided_answer(),
	}


# ---------- 内部 ----------

func _clear_transient_state() -> void:
	_quiz_cursor = 0
	_task_hold = -1.0
	_hint_text = ""
	_hint_timer = 0.0
	_death_recovery_active = false
	_death_recovery_duration = 0.0
	_death_recovery_retry = false


func _enter_current_step() -> void:
	_quiz_cursor = 0
	_task_hold = -1.0
	_hint_text = ""
	_hint_timer = 0.0
	_rebuild_tasks()
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


func _quiz_indices() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in current_step().get("quiz_indices", []):
		result.append(int(value))
	return result


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


func _build_steps() -> Array[Dictionary]:
	return [
		{
			"id": "duo_run",
			"title": "2人で走ってみよう",
			"body": "P1はオレンジ、P2はシアン。左右に動いてコースの幅をつかみましょう。ぶつかると押し合います。",
			"guide": GUIDE_LANE,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [
					{"id": "left", "key": "A", "caption": "左へ動く"},
					{"id": "right", "key": "D", "caption": "右へ動く"},
				],
				2: [
					{"id": "left", "key": "←", "caption": "左へ動く"},
					{"id": "right", "key": "→", "caption": "右へ動く"},
				],
			},
		},
		{
			"id": "duo_air",
			"title": "ジャンプと前後の微調整",
			"body": "ジャンプで飛び越え、前後で走る速さを微調整できます。離れすぎると画面外に取り残されます。",
			"guide": GUIDE_AIR,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [
					{"id": "jump", "key": "Space", "caption": "ジャンプ"},
					{"id": "forward", "key": "W", "caption": "前進"},
					{"id": "back", "key": "S", "caption": "後退"},
				],
				2: [
					{"id": "jump", "key": "Ctrl / Num0", "caption": "ジャンプ"},
					{"id": "forward", "key": "↑", "caption": "前進"},
					{"id": "back", "key": "↓", "caption": "後退"},
				],
			},
		},
		{
			"id": "duo_emote",
			"title": "エモートで煽ろう",
			"body": "エモートは相手を挑発するアクションです。2人とも1つ出してみましょう。",
			"guide": GUIDE_EMOTE,
			"speed": 0.4,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [{"id": "emote", "key": "1 / 2 / 3", "caption": "エモート"}],
				2: [{"id": "emote", "key": "8 / 9 / 0", "caption": "エモート"}],
			},
		},
		{
			"id": "duo_ocean",
			"title": "コースの外は海",
			"body": "P2だけコースの外へ出てみましょう。海に落ちるとサメに襲われて脱落します。",
			"guide": GUIDE_OCEAN,
			"speed": 0.0,
			"walls": false,
			"hazard_player": 2,
			"ghost_handoff": true,
			"ghost_ride": true,
			"split_camera": true,
			"tasks": {
				2: [{"id": "ocean", "key": "← / →", "caption": "コースの外へ出る"}],
			},
		},
		{
			"id": "duo_ghost",
			"title": "ゴーストシャークで反撃",
			"body": "脱落したP2はゴーストシャークに乗れます。照準を合わせ、長押しで溜めてP1へ突進しましょう。",
			"guide": GUIDE_GHOST,
			"speed": 0.0,
			"walls": false,
			"hazard_player": 2,
			"ghost_player": 2,
			"ghost_ride": true,
			"split_camera": true,
			"tasks": {
				2: [
					{"id": "aim", "key": "矢印", "caption": "照準移動"},
					{"id": "charge", "key": "Ctrl / Num0", "caption": "長押し→離す"},
					{"id": "hit", "key": "HIT", "caption": "P1へ命中"},
				],
			},
		},
		{
			"id": "duo_guided_wall",
			"title": "最初の問題",
			"body": "光っているドアが正解です。2人とも同じドアを通り抜けましょう。得点はP1・P2別々に入ります。",
			"guide": GUIDE_GUIDED_DOOR,
			"speed": 1.0,
			"walls": true,
			"reset_on_advance": true,
			"quiz_indices": [0],
			"highlight_answer": 0,
			"requires_both_correct": true,
			"presentation": "wall_reveal",
			"duration": 0.9,
			"tasks": {
				1: [{"id": "answer", "key": "A / D", "caption": "光るドアへ"}],
				2: [{"id": "answer", "key": "← / →", "caption": "光るドアへ"}],
			},
		},
		{
			"id": "duo_free_wall",
			"title": "自分で選ぶ",
			"body": "ここからは光りません。判定は1人ずつ。間違えた側だけ脱落し、正解した側はそのまま走り続けます。",
			"guide": GUIDE_FREE_DOOR,
			"speed": 1.0,
			"walls": true,
			"quiz_indices": [1, 2],
			"highlight_answer": -1,
			"punish_mistakes": true,
			"allow_scroll_out": true,
			"ghost_ride": true,
			"tasks": {
				1: [{"id": "answer", "key": "A / D", "caption": "自分で答える"}],
				2: [{"id": "answer", "key": "← / →", "caption": "自分で答える"}],
			},
		},
		{
			"id": "duo_goal",
			"title": "最終レース",
			"body": "脱落したプレイヤーも復活します。ゴールゲートへ先に着いたほうが勝ちです。",
			"guide": GUIDE_GOAL,
			"speed": 1.0,
			"walls": true,
			"revive_players": true,
			"ghost_ride": true,
			"presentation": "goal_sweep",
			"duration": 1.15,
			"tasks": {
				1: [{"id": "goal", "key": "W", "caption": "GOALへ"}],
				2: [{"id": "goal", "key": "↑", "caption": "GOALへ"}],
			},
		},
		{
			"id": "duo_complete",
			"title": "ローカル2Pコース完了！",
			"body": "2人の操作、海とゴーストシャーク、個別判定、最終レースを習得しました。",
			"guide": GUIDE_COMPLETE,
			"speed": 0.0,
			"walls": true,
			"presentation": "duo_stage_complete",
			"duration": 3.4,
		},
	]
