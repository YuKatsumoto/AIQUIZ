class_name MatchRules
extends RefCounted

## 練習（Constants.MODE_PRACTICE）のルールの切り替え口（docs/new_tutorial/foundation_design.md 2章）。
## QuizGameState.practice_rules に入っているときだけ効く。本編のモードでは使わない（practice_rules は null）。
## 台本はレッスンごとに作って QuizGameState.set_practice_rules() で入れかえる。

## REPORT_ONLY：違うドア・ドアの間の壁でも、ハートも体もそのまま。壁の手前へ戻して通知（practice_wall_contact）だけ出す。
enum Mistakes { NORMAL, REPORT_ONLY }
## REPORT_AFTER_BITE：サメにかまれてもアウトにせず、通知（practice_ocean_bitten）だけ出す。
enum Ocean { NORMAL, REPORT_AFTER_BITE }
## REPORT_ONLY：のこぎりに捕まっても、ゴーストにもアウトの判定（練習の負け）にもしない（体がばらばらになる演出は本番どおり）。
## practice_saw_caught(player_index) を出すだけ。監督が practice_revive と practice_place_player で戻す（docs/new_tutorial/phase6_design.md 2.3）。
enum Saw { NORMAL, REPORT_ONLY }

var hp_enabled := false
## 1 にすると、ハートは 1 より減らない。
var hp_floor := 0
var mistakes := Mistakes.NORMAL
var ocean := Ocean.NORMAL
## 2人のとき、のこぎりを本番どおりに走らせる（入ってくる・加速・14m 後ろまで迫る・最初の2秒は待つ）。
## false に戻すと、のこぎりは止まって（ブレーキ・操縦席の止める動き）床のうしろへ下がり、見えなくなる。
var saw_enabled := false
var saw := Saw.NORMAL
var local_push_enabled := false
var scroll_out_enabled := false
var ghost_ride_enabled := false
## <0：本番の自動計算、0：止める（コンベアも壁も）、>0：その速さ（m/s）。
var world_speed := -1.0
## 自動の速さ（world_speed < 0）のとき、壁の速さの自動計算の「調子」を一番遅い値（WallSpeedPlanner.PACE_MAX）で計算する。
## 保存されている調子（WallSpeedPlanner.pace）は変えない。次の問題から効く（置き直し・落とし直しでも計算し直す）。
var slow_auto_speed := false
## 見えないさく。範囲は (x, コンベア上の z)。2人のときも同じ範囲を使う。
var fence_enabled := false
var fence_min := Vector2(-10.0, -6.0)
var fence_max := Vector2(10.0, 8.0)
## 移動・ジャンプ・エモートを止める。
var input_locked := false
## 問題の成績・AI の改善・分析・評価の送信へ渡すか。練習の既定は渡さない。
var record_results := false
## 本番の右上の「正解・問題」の表示を出すか。練習の既定は出さない（コース②のミニ本番だけ出す）。
var show_score := false
## 用意した問題を全部終えたら、本番の1人の10問と同じく CLEAR にする（practice_quizzes_finished は出さない）。
var finish_with_clear := false
## GAME OVER と CLEAR を本番どおりの画面（カード・紙吹雪・死ぬ演出のあとのカード）で見せる。
## false（既定）は段階4の「練習の負け」（カードを出さない）。どちらでも practice_round_lost は出す。
var real_result_screens := false
## 2人のとき、用意した問題を全部終えたら、本番の2人の10問と同じくゴールレース（GOAL へ走れ）→ ゴール →
## スコアタワーの演出と判定へ進む（practice_quizzes_finished は出さない）。ゴールラインとスタンドは最後の壁の後ろに出る。
## 判定が出たら practice_ceremony_finished(winner) を出す（判定のあとのボタンは出さない）。
var finish_with_goal := false


## 全部の値を写した新しいもの。
func duplicate_rules() -> MatchRules:
	var copy := MatchRules.new()
	copy.hp_enabled = hp_enabled
	copy.hp_floor = hp_floor
	copy.mistakes = mistakes
	copy.ocean = ocean
	copy.saw_enabled = saw_enabled
	copy.saw = saw
	copy.local_push_enabled = local_push_enabled
	copy.scroll_out_enabled = scroll_out_enabled
	copy.ghost_ride_enabled = ghost_ride_enabled
	copy.world_speed = world_speed
	copy.slow_auto_speed = slow_auto_speed
	copy.fence_enabled = fence_enabled
	copy.fence_min = fence_min
	copy.fence_max = fence_max
	copy.input_locked = input_locked
	copy.record_results = record_results
	copy.show_score = show_score
	copy.finish_with_clear = finish_with_clear
	copy.real_result_screens = real_result_screens
	copy.finish_with_goal = finish_with_goal
	return copy
