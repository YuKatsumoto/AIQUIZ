class_name PracticeStep
extends RefCounted

## レッスンの土台（docs/new_tutorial/foundation_design.md 7.1）。台本の1つのレッスン（"1-1" など）。
## 監督（PracticeDirector）が enter → 毎フレーム process・出来事ごとに on_event → exit の順に呼ぶ。
## 失敗したときの「まきもどし」は rewind（既定は enter をやり直す）。
##
## enter の中で await を使う（吹き出しを待つなど）ときは、待ったあとに d.is_current(serial) で
## まだ同じレッスンの同じ回かを確かめてから続ける（とばす・まきもどしで、古い流れを止めるため）。

## 台本のレッスンの番号（"1-1" など）。進み具合の点はこれで数える。
var id := ""


## ルール・位置・壁・ハテナを整えて始める。
func enter(_d: PracticeDirector) -> void:
	pass


func process(_d: PracticeDirector, _dt: float) -> void:
	pass


## game_state の出来事（&"wall_contact"・&"jumped" など。PracticeDirector の一覧）を受ける。
func on_event(_d: PracticeDirector, _event: StringName, _data: Dictionary) -> void:
	pass


## 次のレッスンへ行く前・とばすとき・コースをやめるときの片付け。
func exit(_d: PracticeDirector) -> void:
	pass


## まきもどし（台本①の 1.6）：レッスンの始めの状態からやり直す。
func rewind(d: PracticeDirector) -> void:
	exit(d)
	enter(d)


## 2回失敗したときに床の矢印で指すドアの x（台本①の 1.6）。指すものがないときは NAN。監督が毎フレーム見る。
func hint_door_x(_d: PracticeDirector) -> float:
	return NAN


## 本物のリザルトのカードの『リトライ』（docs/new_tutorial/phase5_design.md 3.3。監督の retry_run から）。既定は何もしない。
func on_retry(_d: PracticeDirector) -> void:
	pass


## 本物のリザルトのカードの『メニュー』（監督の leave_to_menu から）。true を返したら、レッスンがメニューへ移す。
## false（既定）なら、監督がコースをやめてメニューへ戻る（ポーズ画面の「タイトルに戻る」と同じ）。
func on_leave_to_menu(_d: PracticeDirector) -> bool:
	return false
