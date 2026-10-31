class_name PracticeCourse
extends RefCounted

## コースの土台（docs/new_tutorial/foundation_design.md 7.1）。コースの台本（courses/course_N.gd）がこれを継ぎ、
## レッスン（PracticeStep）の並びを作る。台本の「レッスン」は、コードでは step と呼ぶ。

## PracticeCatalog の id（例 "c1"）。文字の ID の頭にもなる（"c1.title" など）。
var id := ""
## 台本のレッスンの並び（画面の上の進み具合の点）。まだ作っていないレッスンも入れる。
## 空なら build_steps() の並びをそのまま使う。
var lesson_ids: Array[String] = []
## クリアカードの1つ目のボタン（［つぎの コースへ］）で始めるコース（例 "c2"）。"" ならボタンは全部コース選択へ戻る。
var next_course := ""


## レッスンの並び。監督（PracticeDirector）がコースの始めに1回だけ呼ぶ。
func build_steps() -> Array[PracticeStep]:
	return []


## 画面の上に出すコース名（例「① はじめの いっぽ」）。
func title() -> String:
	return PracticeTexts.get_text(id + ".title")


## クリアの演出をコースが自分で出すなら true（既定は false：監督の①の形のクリア）。
func handles_clear() -> bool:
	return false


## クリアの演出（handles_clear が true のときだけ、監督の finish_course が呼ぶ）。クリアカードは d.overlay.show_clear_card で出し、
## ボタンは監督が受ける（1つ目は next_course、ほかはコース選択へ）。
func play_clear(_d: PracticeDirector, _star: bool) -> void:
	pass


## このコースの文字の ID（"c1" + ".clear.1" など）。台本にない ID なら ""。
func text_id(suffix: String) -> String:
	var full := "%s.%s" % [id, suffix]
	return full if PracticeTexts.has_text(full) else ""
