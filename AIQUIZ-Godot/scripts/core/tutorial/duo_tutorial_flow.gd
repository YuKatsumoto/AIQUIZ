extends RefCounted
class_name DuoTutorialFlow

## ローカル2P（デュオ）チュートリアルコース。
## 1Pコースは res://scripts/core/tutorial/solo_tutorial_flow.gd が担当する。
## 両クラスは QuizGameState から同じメソッド面で呼ばれるため、
## 片方にクエリを足したらもう片方にも同名で足すこと。
##
## 学習順は「操作 → 危険 → ゴースト → のこぎり → 回答 → ハート → 実践 → ゴール → カスタマイズ紹介」。
## 本編のローカル2P（10問チャレンジ・エンドレス）に合わせ、
## - ハートは1人3つ。不正解や壁で1つ減り、0で脱落してゴーストシャークへ回る。
## - 先に正解したプレイヤーだけに1点が入り、壁は2人とも通れるように開く。
## - 後ろから回転のこぎりが追ってくる。触れるとハートに関係なく脱落する。
## - ゴールは生き残った全員が通過し、勝敗はスコアタワー（正解数 ×（残りハート＋0.5））で決まる。
## 一度に提示する操作は各プレイヤー最大3つまでに抑える。
##
## 操作を教えるステップでは、各タスクの "slots" をもとに 3D 空間へ操作キーを浮かべる
## （res://scripts/world/tutorial_key_guides_3d.gd）。"key_layout" がその並べ方。

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
const GUIDE_SAW := "saw"
const GUIDE_GUIDED_DOOR := "guided_door"
const GUIDE_WRONG_DOOR := "wrong_door"
const GUIDE_FREE_DOOR := "free_door"
const GUIDE_GOAL := "goal"
const GUIDE_COMPLETE := "complete"

## 3Dキーの並べ方（TutorialKeyGuides3D の LAYOUT_* と同じ値）。
const KEYS_CLUSTER := "cluster"
const KEYS_SIDES := "sides"
const KEYS_GHOST := "ghost"

const TASK_HOLD_SECONDS := 0.55
const HINT_SECONDS := 3.4
const GATE_GRACE_SECONDS := 0.7
## 4択のボス壁で使う問題の番号。
const BOSS_QUIZ_INDEX := 4
## のこぎり体験: 警告が出る距離まで近づき、警告の外まで戻る。
## 危険度は 1 − 刃までの距離 ÷ 警告距離（6m）。
const SAW_APPROACH_DANGER := 0.2
const SAW_ESCAPE_DANGER := 0.0
const SAW_ESCAPE_HOLD := 0.35

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
var _death_recovery_message: String = ""
var _quiz_items: Array[QuizItem] = []
var _saw_escape_hold: Dictionary = {}


func start(_selected_course: String = COURSE_LOCAL_2P) -> void:
	course = COURSE_LOCAL_2P
	_steps = _build_steps()
	_quiz_items = _build_quiz_items()
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
	_saw_escape_hold.clear()
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


## 1Pと同じく、ゲーム内の完了演出では終わらせず、最終ステップ後にカスタマイズへ引き継ぐ。
func should_clear_after_presentation() -> bool:
	return false


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
	return _hold_after_all_tasks(delta)


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


func is_task_done(player_index: int, task_id: String) -> bool:
	for task: Dictionary in _tasks.get(player_index, []):
		if str(task.get("id", "")) == task_id:
			return bool(task.get("done", false))
	return false


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


## 同じステップの最初の問題へ戻す（2人とも脱落して実践をやり直すとき）。
func rewind_quiz_step() -> void:
	_quiz_cursor = 0
	_rebuild_tasks()
	revision += 1


func guided_answer() -> int:
	return int(current_step().get("highlight_answer", -1))


## 3Dガイドとキーが向かう先のドア。誘導中は正解ドア、ハート体験ではわざと入る不正解ドア。
func target_door() -> int:
	if is_hp_lesson():
		return hp_lesson_door()
	return guided_answer()


## 誘導ありの問題とハート体験では優しくやり直させ、誘導なしの実践だけ本編と同じ判定にする。
func punishes_mistakes() -> bool:
	return bool(current_step().get("punish_mistakes", false))


## 旧コースの「2人そろって正解で通過」は本編と食い違うため廃止した。
## 誘導ありの問題も本編と同じく先に正解した人だけが得点し、壁は2人とも通れる。
func requires_both_correct() -> bool:
	return false


func target_quiz_count() -> int:
	return _quiz_items.size() if not _quiz_items.is_empty() else _build_quiz_items().size()


func build_quiz_items() -> Array[QuizItem]:
	var items := _build_quiz_items()
	_quiz_items = items
	return items


func choice_count_for_quiz(index: int) -> int:
	if index >= 0 and index < _quiz_items.size():
		return clampi(_quiz_items[index].c.size(), 2, 4)
	return 4 if index == BOSS_QUIZ_INDEX else 2


func is_boss_quiz(index: int) -> bool:
	return index == BOSS_QUIZ_INDEX


# ---------- ハート（HP） ----------

func uses_hp() -> bool:
	return bool(current_step().get("hp", false))


func uses_hp_rules() -> bool:
	return bool(current_step().get("hp_rules", false))


func is_hp_lesson() -> bool:
	return bool(current_step().get("hp_lesson", false))


func hp_lesson_door() -> int:
	if not is_hp_lesson():
		return -1
	var index := quiz_index()
	if index < 0 or index >= _quiz_items.size():
		return -1
	var answer := _quiz_items[index].a
	return 1 if answer == 0 else 0


# ---------- 回転のこぎり ----------

## このステップで本編と同じ回転のこぎりを走らせるか。
func uses_saw() -> bool:
	return bool(current_step().get("saw", false))


func is_saw_lesson() -> bool:
	return bool(current_step().get("saw_lesson", false))


## のこぎり体験の進行。各プレイヤーの危険度（0〜1）を受け取り、2人が終えたら true。
## 警告が出るまで後退し、その後に警告の外まで前進して戻ると完了。
func update_saw_lesson(danger_p1: float, danger_p2: float, delta: float = 0.0) -> bool:
	if not is_saw_lesson() or presentation_locked or awaiting_neutral_input:
		_task_hold = -1.0
		return false
	for player_index: int in [1, 2]:
		var danger := danger_p1 if player_index == 1 else danger_p2
		if not is_task_done(player_index, "saw_approach"):
			if danger >= SAW_APPROACH_DANGER:
				complete_task(player_index, "saw_approach")
				_saw_escape_hold[player_index] = 0.0
			continue
		if is_task_done(player_index, "saw_escape"):
			continue
		if danger <= SAW_ESCAPE_DANGER:
			_saw_escape_hold[player_index] = float(_saw_escape_hold.get(player_index, 0.0)) + delta
			if float(_saw_escape_hold[player_index]) >= SAW_ESCAPE_HOLD:
				complete_task(player_index, "saw_escape")
		else:
			_saw_escape_hold[player_index] = 0.0
	return _hold_after_all_tasks(delta)


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


func key_layout() -> String:
	return str(current_step().get("key_layout", ""))


func resets_players_on_advance() -> bool:
	return bool(current_step().get("reset_on_advance", false))


## 誘導ステップでは片方だけが動くので、通常の2P分断ルールを止める。
## のこぎりが走るステップでは本編どおり、置き去りの判定はのこぎりが担う。
func blocks_scroll_out_death() -> bool:
	return not bool(current_step().get("allow_scroll_out", false))


func allows_ocean_entry(player_index: int) -> bool:
	if is_ocean_hazard_step():
		return designated_hazard_player() == player_index
	# 実践と最終レースでは本編と同じく、誰が落ちても本当の脱落として扱う。
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


## ゴールは本編のローカル2Pと同じく、生き残った全員が通過して終わる。
func requires_all_finishers() -> bool:
	return starts_goal_race()


func starts_customize_tour() -> bool:
	return is_step("customize_tour")


func is_final_step() -> bool:
	return is_step("customize_tour")


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


func begin_death_recovery(duration: float, retry_same_step: bool, message: String = "") -> void:
	_death_recovery_active = true
	_death_recovery_duration = maxf(0.2, duration)
	_death_recovery_retry = retry_same_step
	_death_recovery_message = message
	revision += 1


func finish_death_recovery() -> Dictionary:
	if not _death_recovery_active:
		return {"retry": false, "message": ""}
	var retry := _death_recovery_retry
	var message := _death_recovery_message
	_death_recovery_active = false
	_death_recovery_duration = 0.0
	_death_recovery_retry = false
	_death_recovery_message = ""
	revision += 1
	if message.is_empty():
		message = (
			"2人とも脱落しました。同じ問題からやり直します。"
			if retry
			else "海に落ちた場合の動作を確認しました。次のステップに進みます。"
		)
	return {"retry": retry, "message": message}


# ---------- ヒント ----------

func set_hint(text: String, seconds: float = HINT_SECONDS) -> void:
	_hint_text = text
	_hint_timer = maxf(0.0, seconds)
	revision += 1


func clear_summary_lines() -> PackedStringArray:
	return PackedStringArray([
		"✓ 2人分の移動・ジャンプ・エモートと押し合い",
		"✓ 海（即脱落）とゴーストシャークでの反撃",
		"✓ 後ろから迫る回転のこぎり（即脱落）",
		"✓ ハート3つと、先に正解した人だけの得点",
		"✓ 4択のボス壁、ゴールとスコアタワー",
		"✓ 壁速度・帽子・エモートのカスタマイズ",
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
	var hint := _hint_text
	if is_step("duo_push") and hint.is_empty():
		if not _push_task_done(1, "brace"):
			hint = "2人とも相手の方向のキーを押し続けてください。ジャンプでは相手を越えられません。"
		elif not _push_task_done(1, "push"):
			hint = "P2は押し続けたまま、P1はキーを一度離して押し直すと体当たりで押せます。"
		elif not _push_task_done(2, "push"):
			hint = "P1は押し続けたまま、P2はキーを一度離して押し直すと体当たりで押せます。"
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
		"hint": hint,
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
		"target_door": target_door(),
		"key_layout": key_layout(),
		# 順番に行うタスク（踏ん張り→押す、後退→前進）は、今やる分のキーだけを光らせる。
		"ordered_tasks": bool(step.get("ordered_tasks", false)),
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
	_death_recovery_message = ""
	_saw_escape_hold.clear()


func _enter_current_step() -> void:
	_quiz_cursor = 0
	_task_hold = -1.0
	_hint_text = ""
	_hint_timer = 0.0
	_saw_escape_hold.clear()
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


func _hold_after_all_tasks(delta: float) -> bool:
	if not all_tasks_complete():
		_task_hold = -1.0
		return false
	if _task_hold < 0.0:
		_task_hold = 0.0
		return false
	_task_hold = minf(TASK_HOLD_SECONDS, _task_hold + delta)
	return _task_hold >= TASK_HOLD_SECONDS


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


func on_local_push_event(event: Dictionary) -> void:
	if not is_step("duo_push") or awaiting_neutral_input or presentation_locked:
		return
	if event.kind == "stalemate":
		complete_task(1, "brace")
		complete_task(2, "brace")
	elif event.kind == "hit" and _push_task_done(1, "brace"):
		if event.player == 1:
			complete_task(1, "push")
		elif _push_task_done(1, "push"):
			complete_task(2, "push")

func _push_task_done(player: int, id: String) -> bool:
	for task: Dictionary in _tasks.get(player, []):
		if task.id == id:
			return task.get("done", false)
	return false


func _build_quiz_items() -> Array[QuizItem]:
	# 2択の選択肢は左ドア=index0、右ドア=index1。正解の左右がばらけるよう配置する。
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
		# ハート体験。正解は左の「6」で、2人ともわざと右の「7」へ入ってもらう。
		QuizItem.create(
			"3 + 3 = ?",
			PackedStringArray(["6", "7"]),
			0,
			"3に3を足すと6です。",
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
		# 4択のボス壁。正解のCは中央寄りのドアにして、2人の立ち位置から届きやすくする。
		QuizItem.create(
			"8 × 4 = ?",
			PackedStringArray(["24", "28", "32", "36"]),
			2,
			"8を4回足すと32です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			9.0
		),
	]
	return items


func _build_steps() -> Array[Dictionary]:
	return [
		{
			"id": "duo_run",
			"title": "2人プレイの基本操作",
			"body": "P1はオレンジ、P2は水色です。頭の上に出ているキーで、それぞれ左右に動いてみましょう。",
			"guide": GUIDE_LANE,
			"key_layout": KEYS_CLUSTER,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [
					{"id": "left", "key": "A", "caption": "左移動", "slots": ["left"]},
					{"id": "right", "key": "D", "caption": "右移動", "slots": ["right"]},
				],
				2: [
					{"id": "left", "key": "←", "caption": "左移動", "slots": ["left"]},
					{"id": "right", "key": "→", "caption": "右移動", "slots": ["right"]},
				],
			},
		},
		{
			"id": "duo_push",
			"title": "押し合い",
			"body": "相手の方向のキーを押し続けると踏ん張り、一度離して押し直すと体当たりで押せます。押し出された相手は海に落ちることもあります。",
			"guide": GUIDE_LANE,
			"key_layout": KEYS_CLUSTER,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"ordered_tasks": true,
			"tasks": {
				1: [
					{"id": "brace", "key": "A / D", "caption": "2人で踏ん張る", "slots": ["toward_opponent"]},
					{"id": "push", "key": "離す→押す", "caption": "P1から押す", "slots": ["toward_opponent"]},
				],
				2: [
					{"id": "brace", "key": "← / →", "caption": "2人で踏ん張る", "slots": ["toward_opponent"]},
					{"id": "push", "key": "離す→押す", "caption": "P2から押す", "slots": ["toward_opponent"]},
				],
			},
		},
		{
			"id": "duo_air",
			"title": "ジャンプと前後の移動",
			"body": "前後の移動で壁に着くタイミングを調整できます。P2のジャンプはキーボード右側のCtrlです（左のCtrlは使えません）。",
			"guide": GUIDE_AIR,
			"key_layout": KEYS_CLUSTER,
			"speed": 0.55,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [
					{"id": "jump", "key": "Space", "caption": "ジャンプ", "slots": ["jump"]},
					{"id": "forward", "key": "W", "caption": "前進", "slots": ["up"]},
					{"id": "back", "key": "S", "caption": "後退", "slots": ["down"]},
				],
				2: [
					{"id": "jump", "key": "Ctrl", "caption": "ジャンプ", "slots": ["jump"]},
					{"id": "forward", "key": "↑", "caption": "前進", "slots": ["up"]},
					{"id": "back", "key": "↓", "caption": "後退", "slots": ["down"]},
				],
			},
		},
		{
			"id": "duo_emote",
			"title": "エモート",
			"body": "数字キーでエモートを踊れます（P2はテンキーの7・8・9でも可）。ジャンプで止まります。それぞれ1つ再生してください。",
			"guide": GUIDE_EMOTE,
			"key_layout": KEYS_CLUSTER,
			"speed": 0.4,
			"walls": false,
			"input_practice": true,
			"tasks": {
				1: [{"id": "emote", "key": "1 / 2 / 3", "caption": "エモート", "slots": ["emote_1", "emote_2", "emote_3"]}],
				2: [{"id": "emote", "key": "8 / 9 / 0", "caption": "エモート", "slots": ["emote_1", "emote_2", "emote_3"]}],
			},
		},
		{
			"id": "duo_ocean",
			"title": "コース外は海",
			"body": "コースの外は海です。落ちるとサメに襲われ、ハートの数に関係なく脱落します。P2は端から外へ出てみてください。",
			"guide": GUIDE_OCEAN,
			"key_layout": KEYS_SIDES,
			"speed": 0.0,
			"walls": false,
			"hazard_player": 2,
			"ghost_handoff": true,
			"ghost_ride": true,
			"split_camera": true,
			"tasks": {
				2: [{"id": "ocean", "key": "← / →", "caption": "コースの外へ出る", "slots": ["toward_edge"]}],
			},
		},
		{
			"id": "duo_ghost",
			"title": "ゴーストシャークで反撃",
			"body": "脱落した人はゴーストシャークに乗り、残った相手を体当たりで海やのこぎりへ弾き飛ばせます。照準をP1に合わせ、右Ctrlを長押しして黄色いPERFECTで離すと最大パワーです。",
			"guide": GUIDE_GHOST,
			"key_layout": KEYS_GHOST,
			"speed": 0.0,
			"walls": false,
			"hazard_player": 2,
			"ghost_player": 2,
			"ghost_ride": true,
			"split_camera": true,
			"tasks": {
				2: [
					{"id": "aim", "key": "矢印", "caption": "照準移動", "slots": ["left", "up", "down", "right"]},
					{"id": "charge", "key": "Ctrl", "caption": "長押し→離す", "slots": ["jump"]},
					{"id": "hit", "key": "HIT", "caption": "P1へ命中"},
				],
			},
		},
		{
			"id": "duo_saw",
			"title": "回転のこぎりに注意",
			"body": "2人プレイでは後ろから回転のこぎりが迫ります。先頭から約14m遅れると巻き込まれ、ハートに関係なく脱落します。少し後退して赤い警告を確かめたら、前進して離れてください。",
			"guide": GUIDE_SAW,
			"key_layout": KEYS_CLUSTER,
			"speed": 0.55,
			"walls": false,
			"saw": true,
			"saw_lesson": true,
			"ordered_tasks": true,
			"presentation": "saw_reveal",
			"duration": 2.4,
			"tasks": {
				1: [
					{"id": "saw_approach", "key": "S", "caption": "後退して警告を見る", "slots": ["down"]},
					{"id": "saw_escape", "key": "W", "caption": "前進で離れる", "slots": ["up"]},
				],
				2: [
					{"id": "saw_approach", "key": "↓", "caption": "後退して警告を見る", "slots": ["down"]},
					{"id": "saw_escape", "key": "↑", "caption": "前進で離れる", "slots": ["up"]},
				],
			},
		},
		{
			"id": "duo_guided_wall",
			"title": "クイズの答え方",
			"body": "光ったドアが正解です。先に正解した人だけに1点が入り、壁は2人とも通れるように開きます。",
			"guide": GUIDE_GUIDED_DOOR,
			"key_layout": KEYS_SIDES,
			"speed": 1.0,
			"walls": true,
			"hp": true,
			"saw": true,
			"reset_on_advance": true,
			"quiz_indices": [0],
			"highlight_answer": 0,
			"presentation": "wall_reveal",
			"duration": 0.9,
			"tasks": {
				1: [{"id": "answer", "key": "A / D", "caption": "光ったドアへ", "slots": ["toward_door"]}],
				2: [{"id": "answer", "key": "← / →", "caption": "光ったドアへ", "slots": ["toward_door"]}],
			},
		},
		{
			"id": "duo_hp",
			"title": "ハート（HP）のしくみ",
			"body": "ハートは1人3つ。不正解や壁で1つ減り、0で脱落します。2人とも、わざと不正解の「7」へ入ってください。",
			"guide": GUIDE_WRONG_DOOR,
			"key_layout": KEYS_SIDES,
			"speed": 1.0,
			"walls": true,
			"hp": true,
			"hp_lesson": true,
			"saw": true,
			"quiz_indices": [1],
			"highlight_answer": -1,
			"tasks": {
				1: [{"id": "wrong_door", "key": "A / D", "caption": "わざと不正解へ", "slots": ["toward_door"]}],
				2: [{"id": "wrong_door", "key": "← / →", "caption": "わざと不正解へ", "slots": ["toward_door"]}],
			},
		},
		{
			"id": "duo_free_wall",
			"title": "誘導なしで回答",
			"body": "本番と同じ判定です。不正解の人はハートが1つ減り、相手が答えるまで壁の前で止められます。",
			"guide": GUIDE_FREE_DOOR,
			"key_layout": KEYS_SIDES,
			"speed": 1.0,
			"walls": true,
			"hp": true,
			"hp_rules": true,
			"saw": true,
			"quiz_indices": [2, 3],
			"highlight_answer": -1,
			"punish_mistakes": true,
			"ghost_ride": true,
			"tasks": {
				1: [{"id": "answer", "key": "A / D", "caption": "答えのドアへ", "slots": ["toward_door"]}],
				2: [{"id": "answer", "key": "← / →", "caption": "答えのドアへ", "slots": ["toward_door"]}],
			},
		},
		{
			"id": "duo_boss_wall",
			"title": "4択のボス壁",
			"body": "最後の問題と難易度「難しい」はドアが4つ（A〜D）。ここでも先に正解した人だけに1点です。",
			"guide": GUIDE_FREE_DOOR,
			"key_layout": KEYS_SIDES,
			"speed": 1.0,
			"walls": true,
			"hp": true,
			"hp_rules": true,
			"saw": true,
			"quiz_indices": [BOSS_QUIZ_INDEX],
			"highlight_answer": -1,
			"punish_mistakes": true,
			# 本編どおり、実践で脱落した人はゴーストシャークのままボス壁を迎える。
			"ghost_ride": true,
			"presentation": "wall_reveal",
			"duration": 1.6,
			"tasks": {
				1: [{"id": "answer", "key": "A / D", "caption": "4つから選ぶ", "slots": ["toward_door"]}],
				2: [{"id": "answer", "key": "← / →", "caption": "4つから選ぶ", "slots": ["toward_door"]}],
			},
		},
		{
			"id": "duo_goal",
			"title": "ゴールとスコアタワー",
			"body": "最後の問題の後はゴールへ向かいます。2人ともゴールすると、スコアタワーで勝敗が決まります（正解数 ×（残りハート＋0.5））。",
			"guide": GUIDE_GOAL,
			"key_layout": KEYS_CLUSTER,
			"speed": 1.0,
			"walls": true,
			"hp": true,
			"revive_players": true,
			"ghost_ride": true,
			"presentation": "goal_sweep",
			"duration": 1.15,
			"tasks": {
				1: [{"id": "goal", "key": "W", "caption": "GOALへ", "slots": ["up"]}],
				2: [{"id": "goal", "key": "↑", "caption": "GOALへ", "slots": ["up"]}],
			},
		},
		{
			"id": "duo_complete",
			"title": "ステージチュートリアル完了",
			"body": "実践コースをクリアしました。続いてカスタマイズを紹介します。",
			"guide": "",
			"speed": 0.0,
			"walls": false,
			"hp": true,
			"presentation": "duo_stage_complete",
			"duration": 4.2,
			"auto_after_presentation": true,
		},
		{
			"id": "customize_tour",
			"title": "カスタマイズの紹介",
			"body": "最後に実際のカスタマイズ画面へ移動します。",
			"guide": "",
			"speed": 0.0,
			"walls": false,
		},
	]
