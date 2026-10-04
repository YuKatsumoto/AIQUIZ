class_name SettingsHallDescent
extends RefCounted

## 設定画面の「地下へ降りる」演出の時間割（実時間）。表示は持たない。
## SHAFT（立坑を降りる。資産がそろうまで続く）→ BLACKOUT（暗転。ホールの初描画のコンパイルを隠す）
## → ARRIVAL（ホールへ降り立ち、照明が列ごとに点く）→ SETTLED（設定UIが出る）。
## 進行役（settings_hall.gd）が実時間の dt で advance() を呼ぶ。止まった分は先へ飛ぶ。

enum Phase { SHAFT, BLACKOUT, ARRIVAL, SETTLED }

## 立坑: 最低この秒数は降り、資産（地下神殿・小道具）がそろうまで続ける。上限を過ぎたら揃わなくても進む。
const SHAFT_MIN := 1.8
const SHAFT_MAX := 6.0
## 暗転: この秒数と、ホールを表示した状態で描いたフレーム数の両方を満たしたら到着へ。
const BLACKOUT_MIN := 0.2
const BLACKOUT_MIN_FRAMES := 2
const ARRIVAL_TIME := 2.0
## 立坑の降下速度（m/s）: 開始値から巡航値へ SPEED_RAMP 秒で上げる。
const SPEED_START := 6.0
const SPEED_CRUISE := 12.0
const SPEED_RAMP := 0.8
## 立坑が見え始めた時点の深さ（メニューの急降下で最初の数 m は過ぎている）。
const DEPTH_START := 15.0
## 深度表示板の間隔（m）。
const SIGN_PITCH := 10.0
const SIGN_SLOTS := 4

var phase := Phase.SHAFT
var phase_time := 0.0
var t := 0.0
var speed := 0.0
## 立坑の模様を上へ流した量（m）。
var scroll := 0.0
## 表示深度（m）。
var depth := DEPTH_START
var assets_ready := false
var drawn_frames := 0
var skip := false


func advance(dt: float) -> void:
	t += dt
	phase_time += dt
	match phase:
		Phase.SHAFT:
			speed = lerpf(SPEED_START, SPEED_CRUISE, clampf(phase_time / SPEED_RAMP, 0.0, 1.0))
			scroll += speed * dt
			depth += speed * dt
			var can_leave := (phase_time >= SHAFT_MIN or skip) and assets_ready
			if can_leave or phase_time >= SHAFT_MAX:
				_enter(Phase.BLACKOUT)
		Phase.BLACKOUT:
			speed = 0.0
			if phase_time >= BLACKOUT_MIN and drawn_frames >= BLACKOUT_MIN_FRAMES:
				_enter(Phase.ARRIVAL)
		Phase.ARRIVAL:
			if skip or phase_time >= ARRIVAL_TIME:
				_enter(Phase.SETTLED)
		Phase.SETTLED:
			pass


func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0
	if next == Phase.BLACKOUT:
		drawn_frames = 0


## 暗転中にホールを描いたフレームを数える（RenderingServer.frame_post_draw から）。
func note_frame_drawn() -> void:
	if phase == Phase.BLACKOUT:
		drawn_frames += 1


## 到着の進み（0〜1、3次のイーズアウト）。到着前は 0、落ち着いた後は 1。
func arrival_u() -> float:
	var u := clampf(arrival_time() / ARRIVAL_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


## 到着が始まってからの秒数（落ち着いた後は ARRIVAL_TIME）。
func arrival_time() -> float:
	match phase:
		Phase.ARRIVAL:
			return phase_time
		Phase.SETTLED:
			return ARRIVAL_TIME
	return 0.0


func is_descending() -> bool:
	return phase != Phase.SETTLED


## 立坑の深度表示板（{"y": 立坑ローカル, "text"}）。昇降台の天面 deck_y に近い順に SIGN_SLOTS 枚まで。
func depth_signs(deck_y: float) -> Array:
	var signs: Array = []
	for board in range(1, 13):
		var board_depth := float(board) * SIGN_PITCH
		var y := deck_y + 1.6 + (depth - board_depth)
		if y > deck_y - 40.0 and y < deck_y + 20.0:
			signs.append({"y": y, "text": "−%dm" % int(board_depth)})
	signs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.y) - deck_y) < absf(float(b.y) - deck_y))
	if signs.size() > SIGN_SLOTS:
		signs.resize(SIGN_SLOTS)
	return signs
