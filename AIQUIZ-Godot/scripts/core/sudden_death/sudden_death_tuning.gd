class_name SuddenDeathTuning
extends RefCounted

## 2Pサドンデス「早押し水没リフト」の調整値（docs/sudden_death_underground.md 3.6節）。
## プレイテストで直す前提の初期値。リフトの高さは「余裕」（水面からの高さ）を半段単位の整数で持つ。

## 最初に確保する問題の数。足りなくなったら算数の自動生成で補う（第4章）。
const QUESTION_COUNT := 8
## 選択肢の数の上限と下限。問題の元の数のまま出し、4択より多いものは4つへ縮める。
const MAX_CHOICES := 4
const MIN_CHOICES := 2

## 余裕（半段）：開始時、罰（相手の正解・自分の不正解・答えずに時間切れ）で減る量。
var start_margin := 4
var penalty := 2
## 誰も押さずに時間切れ：両方が半段沈む。ただしこの余裕より下へは沈まない（時間切れでは負けない）。
var timeout_penalty := 1
var timeout_floor := 1

## 半段の高さ（m）と地下神殿の水位（床からの高さ、m）。開始時のリフトの天面は水面の3.0m上。
var half_step := 0.75
var water_level := 1.2
## 負けたリフトが沈みきる位置（水面より下、m）。
var sunk_depth := 0.7

## 1問の時間（秒）。
## 「第N問」と選択肢が出てから問題文が流れ始めるまで（この間の早押しは無効）。
var question_intro := 1.1
## 問題文が1秒に出る文字数。
var reveal_rate := 8.0
## 問題文が出きってから時間切れまで。
var think_time := 5.0
## 早押ししてから答えるまで。過ぎたら不正解と同じ。
var answer_time := 4.0
## 判定（正解・不正解・時間切れ）を見せてから次の問題まで。
var result_hold := 2.4
## 「3・2・1」各0.6秒。「第1問」はその直後（docs 2.2）。
var countdown := 1.8
## 決着から負けたリフトが水に沈みきって走者が飲まれるまで、飲まれてから帰還を始めるまで。
var plunge_time := 0.8
var decided_hold := 1.6

## 同時とみなす早押しの差（押し合いの刻みと同じ）。
var tie_window := 1.0 / 240.0
## 短く読める問題（推定解答時間がこれ以下）を優先する。
var question_max_seconds := 6.0


## 余裕 margin（半段）のリフトの天面の高さ（床から、m）。
func lift_height(margin: int) -> float:
	return water_level + float(margin) * half_step


## 負けて沈みきったリフトの天面の高さ（床から、m）。
func sunk_height() -> float:
	return water_level - sunk_depth


## 問題文が出きるまでの秒数。
func reveal_seconds(text: String) -> float:
	return float(text.length()) / maxf(reveal_rate, 0.001)
