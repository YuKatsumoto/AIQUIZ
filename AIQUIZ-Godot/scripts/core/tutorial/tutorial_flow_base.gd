extends RefCounted
class_name TutorialFlowBase

## 1P・2Pチュートリアルの共通土台（V7）。
## 1Pコースは res://scripts/core/tutorial/solo_tutorial_flow.gd、
## ローカル2Pコースは res://scripts/core/tutorial/duo_tutorial_flow.gd が継承する。
##
## V7 では説明の段落をなくし、ゲーム中に出す文章を次の3つに絞る。
## - ミッション: 各ステップの "mission"（12字以内の1行）。ミニバーに出す。
## - ルール表示: 体験した直後だけ出す短い表示（"toast"）。見出し10字以内、補足16字以内。
## - ヒント: ミスしたときだけミッションの行を短い文で置き換える（set_hint）。
## ステップは "chapter"（操作・キケン・クイズ・ボス・ゴール）にまとまり、章を終えると
## 「◯◯ CLEAR」のバナーを出す。同じ章の中では世界を止めずに次のステップへ移る。

## ルール表示が出るきっかけ。enter = ステップに入った直後（演出があれば演出の後）、
## done = そのステップのタスクがすべてそろった瞬間。
const TOAST_ON_ENTER := "enter"
const TOAST_ON_DONE := "done"
## ルール表示は表示側が順番に再生する。モデルには直近の数件だけを載せる。
const TOAST_KEEP := 4
const HINT_SECONDS := 2.6
## ヒントはミッションの行を一時的に置き換えるだけなので、長く居座らせない。
const HINT_MAX_SECONDS := 3.2
const HINT_TONE_WARN := "warn"
const HINT_TONE_GOOD := "good"

var step_index: int = 0
var revision: int = 0

var _steps: Array[Dictionary] = []
var _hint_text: String = ""
var _hint_tone: String = HINT_TONE_WARN
var _hint_timer: float = 0.0
var _toasts: Array[Dictionary] = []
var _toast_serial: int = 0
var _fired_toasts: Dictionary = {}
var _banner: Dictionary = {}
var _banner_serial: int = 0


# ---------- ステップ ----------

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


# ---------- 章 ----------

## 章の定義。継承先が {"id", "label", "icon"} の配列を返す。
func chapter_defs() -> Array[Dictionary]:
	return []


func chapter_id() -> String:
	return str(current_step().get("chapter", ""))


func chapter_label(id: String = "") -> String:
	var wanted := id if not id.is_empty() else chapter_id()
	for chapter: Dictionary in chapter_defs():
		if str(chapter.get("id", "")) == wanted:
			return str(chapter.get("label", ""))
	return ""


## 進行バー用。章ごとのステップ数・終えたステップ数・今の章かどうか。
func chapter_progress() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current := chapter_id()
	for chapter: Dictionary in chapter_defs():
		var id := str(chapter.get("id", ""))
		var total := 0
		var done := 0
		for i: int in _steps.size():
			if str(_steps[i].get("chapter", "")) != id:
				continue
			total += 1
			if i < step_index:
				done += 1
		if current.is_empty() and total > 0 and step_index >= _steps.size() - 1:
			done = total
		result.append({
			"id": id,
			"label": str(chapter.get("label", "")),
			"icon": str(chapter.get("icon", "")),
			"steps": total,
			"done_steps": done,
			"current": id == current,
		})
	return result


# ---------- ルール表示 ----------

func push_toast(toast: Dictionary) -> void:
	if toast.is_empty():
		return
	_toast_serial += 1
	var copied := toast.duplicate(true)
	copied["serial"] = _toast_serial
	_toasts.append(copied)
	while _toasts.size() > TOAST_KEEP:
		_toasts.remove_at(0)
	revision += 1


## ステップに書かれたルール表示を、きっかけが合えば1コースで1回だけ出す。
func _fire_step_toast(trigger: String) -> void:
	var toast: Dictionary = current_step().get("toast", {})
	if toast.is_empty() or str(toast.get("on", TOAST_ON_ENTER)) != trigger:
		return
	var key := current_step_id()
	if _fired_toasts.has(key):
		return
	_fired_toasts[key] = true
	push_toast(toast)


# ---------- 章クリアのバナー ----------

## 章が変わるときに呼ぶ。次のステップが章を持たない（クリア画面など）ときは出さない。
func _queue_chapter_banner(previous_chapter: String) -> void:
	var next_chapter := chapter_id()
	if previous_chapter.is_empty() or next_chapter.is_empty() or previous_chapter == next_chapter:
		return
	_banner_serial += 1
	_banner = {
		"serial": _banner_serial,
		"chapter": previous_chapter,
		"label": chapter_label(previous_chapter),
		"next_label": chapter_label(next_chapter),
	}
	revision += 1


# ---------- ヒント ----------

func set_hint(text: String, seconds: float = HINT_SECONDS, tone: String = HINT_TONE_WARN) -> void:
	_hint_text = text
	_hint_tone = tone
	_hint_timer = clampf(seconds, 0.0, HINT_MAX_SECONDS)
	revision += 1


func _tick_hint(delta: float) -> void:
	if _hint_timer <= 0.0:
		return
	_hint_timer = maxf(0.0, _hint_timer - delta)
	if _hint_timer <= 0.0:
		_hint_text = ""
		revision += 1


func _clear_hint() -> void:
	_hint_text = ""
	_hint_timer = 0.0
	_hint_tone = HINT_TONE_WARN


## コースを始め直すときに表示の記録を消す。
func _reset_v7_state() -> void:
	_clear_hint()
	_toasts.clear()
	_fired_toasts.clear()
	_banner = {}


## ミッションの行。順番に行うタスクがあるステップは、今やる分の文を出す。
func _mission_text(pending_task_id: String = "") -> String:
	var step := current_step()
	var by_task: Dictionary = step.get("mission_by_task", {})
	if not pending_task_id.is_empty() and by_task.has(pending_task_id):
		return str(by_task[pending_task_id])
	return str(step.get("mission", step.get("title", "")))


## UIモデルに共通で載せる V7 の項目。
func _v7_model(pending_task_id: String = "") -> Dictionary:
	var step := current_step()
	var toasts: Array[Dictionary] = []
	for toast: Dictionary in _toasts:
		toasts.append(toast.duplicate(true))
	return {
		"mission": _mission_text(pending_task_id),
		"icon": str(step.get("icon", "")),
		"chapter": chapter_id(),
		"chapter_label": chapter_label(),
		"chapters": chapter_progress(),
		"hint_tone": _hint_tone,
		"toasts": toasts,
		"banner": _banner.duplicate(true),
	}
