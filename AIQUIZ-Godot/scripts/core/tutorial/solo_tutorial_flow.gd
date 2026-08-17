extends RefCounted
class_name SoloTutorialFlow

## 1P（ソロ）チュートリアルコース。
## ローカル2Pコースは res://scripts/core/tutorial/duo_tutorial_flow.gd が担当する。
## 両クラスは QuizGameState から同じメソッド面で呼ばれるため、
## 片方にクエリを足したらもう片方にも同名で足すこと。
##
## 学習順は「操作 → 危険 → 回答 → 実践 → カスタマイズ」。
## 一度に提示する操作は最大3つまでに抑え、危険を先に見せてから
## 誘導なしの実戦に入る。誘導なしの問題でミスした場合だけ、
## 本編とまったく同じ激突死亡演出を見せてから同じ問題を再挑戦させる。

signal step_changed(step_id: String, step_index: int, step_count: int)
signal task_completed(player_index: int, task_id: String)
signal presentation_requested(presentation_id: String, context: Dictionary)
signal presentation_finished(presentation_id: String)

const COURSE_SOLO := "SOLO"

## 走路エッジのレーンライン、床投影リング、ドアのルートラインなどの表示切替に使う。
const GUIDE_LANE := "lane"
const GUIDE_AIR := "air"
const GUIDE_OCEAN := "ocean"
const GUIDE_GUIDED_DOOR := "guided_door"
const GUIDE_FREE_DOOR := "free_door"
## 既存のガイド描画スクリプトとの互換用。1Pの新フローからは選択しない。
const GUIDE_GOAL := "goal"
const GUIDE_COMPLETE := "complete"
const TASK_HOLD_SECONDS := 0.55
const HINT_SECONDS := 3.4
const GATE_GRACE_SECONDS := 0.7

var course: String = COURSE_SOLO
var step_index: int = 0
var revision: int = 0
var presentation_locked: bool = false
var awaiting_neutral_input: bool = false

var _steps: Array[Dictionary] = []
var _tasks: Array[Dictionary] = []
var _quiz_cursor: int = 0
var _task_hold: float = -1.0
var _hint_text: String = ""
var _hint_timer: float = 0.0
var _gate_elapsed: float = 0.0
var _death_recovery_active: bool = false
var _death_recovery_duration: float = 0.0
var _death_recovery_retry: bool = false


func start(_selected_course: String = COURSE_SOLO) -> void:
	course = COURSE_SOLO
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
		"ghost_player": 0,
		"highlight_answer": guided_answer(),
		"revision": revision,
	}


## 1Pでは presentation ID の一致を要求しない。ID の取り違えで演出が
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


## 1Pはゲーム内の完了演出を使わず、最終クイズ後にカスタマイズへ引き継ぐ。
func should_clear_after_presentation() -> bool:
	return false


# ---------- 入力 ----------

func consume_input_gate(
		axis_p1: Vector2,
		_axis_p2: Vector2,
		jump_p1: bool,
		_jump_p2: bool,
		emote_p1: int,
		_emote_p2: int) -> bool:
	if presentation_locked:
		return true
	if not awaiting_neutral_input:
		return false
	# ミスで押しっぱなしのまま復帰した場合に世界が止まり続けないよう、
	# 中立入力が来なくても GATE_GRACE_SECONDS で必ずゲートを開ける。
	var neutral := axis_p1.length_squared() < 0.01 and not jump_p1 and emote_p1 <= 0
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


## 1Pは導入ステップを持たず、カウントダウン直後に最初の操作練習が始まる。
func advances_after_countdown() -> bool:
	return false


## 操作練習ステップの進行。ステップを終えてよいとき true を返す。
func update_input_practice(
		axis_p1: Vector2,
		_axis_p2: Vector2,
		jump_p1: bool,
		_jump_p2: bool,
		emote_p1: int,
		_emote_p2: int,
		delta: float = 0.0) -> bool:
	if not is_input_practice_step() or presentation_locked or awaiting_neutral_input:
		_task_hold = -1.0
		return false

	if axis_p1.x > 0.35:
		complete_task(1, "left")
	if axis_p1.x < -0.35:
		complete_task(1, "right")
	if axis_p1.y > 0.35:
		complete_task(1, "forward")
	if axis_p1.y < -0.35:
		complete_task(1, "back")
	if jump_p1:
		complete_task(1, "jump")
	if emote_p1 > 0:
		complete_task(1, "emote")

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
	if player_index != 1:
		return false
	for task: Dictionary in _tasks:
		if str(task.get("id", "")) != task_id or bool(task.get("done", false)):
			continue
		task["done"] = true
		revision += 1
		task_completed.emit(player_index, task_id)
		return true
	return false


func all_tasks_complete() -> bool:
	if _tasks.is_empty():
		return false
	for task: Dictionary in _tasks:
		if not bool(task.get("done", false)):
			return false
	return true


# ---------- クイズ ----------

func is_quiz_step() -> bool:
	return not _quiz_indices().is_empty()


func quiz_index() -> int:
	var indices := _quiz_indices()
	if indices.is_empty():
		return -1
	return indices[mini(_quiz_cursor, indices.size() - 1)]


## 1問正解した後に呼ぶ。ステップ全体を終えたとき true、
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


## 誘導ありの問題では優しくやり直させ、誘導なしの問題だけ本編と同じ激突を見せる。
func punishes_mistakes() -> bool:
	return bool(current_step().get("punish_mistakes", false))


## 2人同時判定は1Pには存在しない。
func requires_both_correct() -> bool:
	return false


func target_quiz_count() -> int:
	return 3


func build_quiz_items() -> Array[QuizItem]:
	# 選択肢の並びは左ドア=index0、右ドア=index1。正解の左右がばらけるよう配置する。
	var items: Array[QuizItem] = [
		QuizItem.create(
			"7 + 5 = ?",
			PackedStringArray(["12", "13"]),
			0,
			"7に5を足すと12です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"6 × 3 = ?",
			PackedStringArray(["16", "18"]),
			1,
			"6を3回足すと18です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"20 - 8 = ?",
			PackedStringArray(["12", "14"]),
			0,
			"20から8を引くと12です。",
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
	return target_quiz_count()


func world_guide() -> String:
	return str(current_step().get("guide", ""))


func resets_players_on_advance() -> bool:
	return bool(current_step().get("reset_on_advance", false))


func blocks_scroll_out_death() -> bool:
	return true


func allows_ocean_entry(player_index: int) -> bool:
	return player_index == 1 and is_ocean_hazard_step()


func is_ocean_hazard_step() -> bool:
	return is_step("ocean_lesson")


## 1Pは海の危険を見せた後、復活させて次のステップへ進む。
func hands_off_to_ghost_after_hazard() -> bool:
	return false


## ゴーストシャークはローカル2P専用の仕組みなので1Pでは常に false。
func allows_ghost_ride() -> bool:
	return false


func splits_camera_for_hazard() -> bool:
	return false


func revives_players() -> bool:
	return false


func starts_goal_race() -> bool:
	return false


func starts_customize_tour() -> bool:
	return is_step("customize_tour")


func is_final_step() -> bool:
	return is_step("customize_tour")


# ---------- ゴースト（1Pでは使わない） ----------

func is_ghost_practice() -> bool:
	return false


func designated_ghost_player() -> int:
	return 0


func designated_hazard_player() -> int:
	return 1 if is_ocean_hazard_step() else 0


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
		"もう一度チャレンジ！ 問題を読んで正しいドアをねらいましょう。"
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
		"✓ 走りながらの左右移動とジャンプ",
		"✓ コース外＝海とサメの危険",
		"✓ 誘導ありと誘導なしのクイズ",
		"✓ 壁速度・帽子・エモートのカスタマイズ",
	])


# ---------- UIモデル ----------

func get_overlay_model() -> Dictionary:
	var step: Dictionary = current_step()
	var copied_tasks: Array[Dictionary] = []
	for task: Dictionary in _tasks:
		copied_tasks.append(task.duplicate(true))
	var indices := _quiz_indices()
	var sub_label := ""
	if indices.size() > 1:
		sub_label = "問題 %d / %d" % [mini(_quiz_cursor + 1, indices.size()), indices.size()]
	return {
		# The stage-complete card owns the whole presentation. Hiding the regular
		# coach bar also removes its unusable Enter-to-skip hint beneath the card.
		"visible": current_step_id() != "stage_complete",
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
			if presentation_locked and current_step_id() != "stage_complete"
			else ""
		),
		"tasks": copied_tasks,
		"players": [{"player": 1, "label": "P1", "tasks": copied_tasks}],
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
	for task_variant: Variant in current_step().get("tasks", []):
		var task: Dictionary = (task_variant as Dictionary).duplicate(true)
		task["done"] = false
		_tasks.append(task)


func _quiz_indices() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in current_step().get("quiz_indices", []):
		result.append(int(value))
	return result


func _build_steps() -> Array[Dictionary]:
	return [
		{
			"id": "run_lane",
			"title": "まずは走ってみよう",
			"body": "キャラクターは自動で前に進みます。左右に動いてコースの幅をつかみましょう。",
			"guide": GUIDE_LANE,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": [
				{"id": "left", "key": "A / ←", "caption": "左へ動く"},
				{"id": "right", "key": "D / →", "caption": "右へ動く"},
			],
		},
		{
			"id": "air_control",
			"title": "ジャンプと前後の微調整",
			"body": "ジャンプで飛び越え、前後で走る速さを微調整できます。",
			"guide": GUIDE_AIR,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": [
				{"id": "jump", "key": "Space", "caption": "ジャンプ"},
				{"id": "forward", "key": "W / ↑", "caption": "前進"},
				{"id": "back", "key": "S / ↓", "caption": "後退"},
			],
		},
		{
			"id": "ocean_lesson",
			"title": "コースの外は海",
			"body": "左右の端から外へ出てみましょう。海に落ちるとサメに襲われます。",
			"guide": GUIDE_OCEAN,
			"speed": 0.0,
			"walls": false,
			"tasks": [
				{"id": "ocean", "key": "A / D", "caption": "コースの外へ出る"},
			],
		},
		{
			"id": "guided_wall",
			"title": "最初の問題",
			"body": "光っているドアが正解です。問題を読んで、そのドアを通り抜けましょう。",
			"guide": GUIDE_GUIDED_DOOR,
			"speed": 1.0,
			"walls": true,
			"reset_on_advance": true,
			"quiz_indices": [0],
			"highlight_answer": 0,
			"presentation": "wall_reveal",
			"duration": 0.9,
			"tasks": [
				{"id": "answer", "key": "A / D", "caption": "光るドアへ"},
			],
		},
		{
			"id": "free_wall",
			"title": "自分で選ぶ",
			"body": "ここからは光りません。自分で解いてみましょう。違えたドアや壁にぶつかると一発でアウトです",
			"guide": GUIDE_FREE_DOOR,
			"speed": 1.0,
			"walls": true,
			"quiz_indices": [1, 2],
			"highlight_answer": -1,
			"punish_mistakes": true,
			"tasks": [
				{"id": "answer", "key": "A / D", "caption": "自分で答える"},
			],
		},
		{
			"id": "stage_complete",
			"title": "ステージチュートリアル完了！",
			"body": "実践問題クリア！。続いてカスタマイズを紹介します。",
			"guide": "",
			"speed": 0.0,
			"walls": false,
			"presentation": "solo_stage_complete",
			"duration": 3.2,
			"auto_after_presentation": true,
		},
		{
			"id": "customize_tour",
			"title": "カスタマイズを見てみよう",
			"body": "最後に実際のカスタマイズ画面へ移動します。",
			"guide": "",
			"speed": 0.0,
			"walls": false,
		},
	]
