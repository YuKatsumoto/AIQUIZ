class_name SkyGateImpact
extends RefCounted

## スカイゲートの時間切れの「つき破る」動き（docs/sudden_death_v2/skygate_impact.md）。見せ方（SkyGatePresenter）と
## 図解ルールカードの実演（SkyGateRuleDemo）が同じ式を使う。t はゲートの時刻（時間切れ）からの秒で、ルールの
## SkyGateGame.IMPACT_TIME（判定を出す時刻）より前に、破れる・はね返る・爆散が終わる。
##
## 高さはどれも「紙の面から体の中心まで」（m、上が +）。体は腹ばい（お腹が下）で、お腹は体の中心の BELLY 下。
##   正解（burst）：紙にお腹が当たって押し込み（へこみ）→ PRESS_END で紙が破れて → 体が抜ける（ボードは上へ抜けていく）。
##   まちがい（boom）：紙にお腹が当たって大きくたわむが破れない（体はぐにゃっと力が抜ける）→ STRETCH_END ではね返されて
##   回りながら上へ → EXPLODE_AT で爆散。
## 場合（mode）：ALL_BURST＝全員が正解、MIXED＝正解とまちがいが 1 人ずつ、ALL_BOOM＝全員まちがい。
##   正解の人は落ちる点のまま（ボードが動く）。全員が正解なら、破れたらすぐボードが上へ抜けていく（見下ろしのカメラのまま、
##   体の上を通りすぎて消える）。1 人ずつなら、はね返った人が爆散してからボードが上へ抜けていく。全員まちがいなら、ボードは
##   たわむまで押し上がって止まり、爆散のあと少し沈みながら消える。
## 通りすぎたボードは、ゲーム中の問題の壁と同じく、文字を消してからだんだん透明になって消える（fade）。

const ALL_BURST := 0
const MIXED := 1
const ALL_BOOM := 2

## 時間切れの瞬間の、紙の面から体の中心までの高さ（お腹の少し上で、すぐ紙に触れる）。
const CONTACT := 0.32
const BELLY := 0.24
## 正解：押し込み → 破れる → 抜ける。THROUGH_END には体がボードの 3 m 以上下にいる。
const PRESS_END := 0.30
const PRESS_DEPTH := -0.26
const THROUGH_END := 1.2
## 抜けたあと、ボードが上へ離れていく速さ（m/秒、スローのあとの速さ）と、その速さになるまでの秒。
const PASS_UP_SPEED := 16.0
const PASS_UP_RAMP := 0.25
## 1 人ずつのとき、爆散までに正解の人がボードの下へ抜ける深さ（m）。
const MIXED_DROP := 1.2
## まちがい：たわむ → はね返る → 回りながら上がって爆散。
const STRETCH_END := 0.36
const STRETCH_DEPTH := -0.56
const BOUNCE_END := 0.84
const BOUNCE_HEIGHT := 4.0
const EXPLODE_AT := 0.84
const TUMBLE := 1.15 * PI
## はね返ったあとの紙のゆれ（トランポリン）：振幅 m・周期 s・減り方 1/s。
const WOBBLE_AMP := 0.22
const WOBBLE_PERIOD := 0.24
const WOBBLE_DECAY := 5.5
## へこみの広がり（半径 m）。
const DENT_RADIUS := 1.25
## 通りすぎたボードが消え始める時刻（全員が正解：破れてから、ほか：爆散のあと）と、消えるまでの秒。全員まちがいのときの沈み方。
const FADE_AFTER_TEAR := 0.1
const FADE_AFTER_BOOM := 0.1
const FADE_TIME := 0.45
const SINK_ACCEL := 6.0
## 時間切れの前後のスロー（見せ方の時計の速さ）。触れる少し前から遅くし、爆散のあとで戻す。
const SLOW := 0.32
const SLOW_IN := 0.12
const SLOW_OUT := Vector2(0.62, 1.15)
## スローを考えた道のりを数えるときの刻み（秒）。
const _STEP := 1.0 / 90.0


static func mode_of(results: Array) -> int:
	var any_burst := results.has("burst")
	var any_boom := results.has("boom")
	if any_burst and any_boom:
		return MIXED
	return ALL_BOOM if any_boom else ALL_BURST


static func _ease_out(u: float) -> float:
	var k := clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


## ボードが上へ抜けていく道のり（m）：start から PASS_UP_RAMP 秒で PASS_UP_SPEED になり、スローの間は遅い（見せ方の時計に合わせる）。
static func _pass_up(start: float, t: float, mode := -1) -> float:
	if t <= start:
		return 0.0
	var d := 0.0
	var tau := start
	while tau < t:
		var h := minf(_STEP, t - tau)
		var mid := tau + h * 0.5
		d += PASS_UP_SPEED * smoothstep(start, start + PASS_UP_RAMP, mid) * time_scale(mid, mode) * h
		tau += h
	return d


## ボードが上へ抜け始める時刻。
static func pass_up_start(mode: int) -> float:
	return PRESS_END if mode == ALL_BURST else EXPLODE_AT + 0.05


## 正解の人の、紙の面から体の中心までの高さ（m）。
static func _burst_height(mode: int, t: float) -> float:
	if t <= 0.0:
		return CONTACT
	if t < PRESS_END:
		return lerpf(CONTACT, PRESS_DEPTH, _ease_out(t / PRESS_END))
	var h := PRESS_DEPTH
	if mode != ALL_BURST:
		h -= MIXED_DROP * smoothstep(PRESS_END, EXPLODE_AT, t)
	return h - _pass_up(pass_up_start(mode), t, mode)


## まちがいの人の、紙の面から体の中心までの高さ（m）。
static func _boom_height(t: float) -> float:
	if t <= 0.0:
		return CONTACT
	if t < STRETCH_END:
		return lerpf(CONTACT, STRETCH_DEPTH, _ease_out(t / STRETCH_END))
	return lerpf(STRETCH_DEPTH, BOUNCE_HEIGHT, _ease_out((t - STRETCH_END) / (BOUNCE_END - STRETCH_END)))


## 紙の面から体の中心までの高さ（m）。t < 0 は時間切れの前（CONTACT のまま。近づき方はボードの側の式）。
static func rel_height(burst: bool, t: float, mode := -1) -> float:
	if burst:
		return _burst_height(ALL_BURST if mode < 0 else mode, t)
	return _boom_height(t)


## 紙のへこみの深さ（m、下が +）。体が紙を押している間はお腹の高さまで。破れたらすぐ戻り、はね返したあとはゆれる。
static func dent(burst: bool, t: float) -> float:
	if t <= 0.0:
		return 0.0
	if burst:
		if t < PRESS_END:
			return maxf(0.0, BELLY - _burst_height(ALL_BURST, t))
		# 破れた紙はすぐ平らに戻る（穴のふちのフラップは SkyGateEffects）
		return (BELLY - PRESS_DEPTH) * exp(-(t - PRESS_END) / 0.035)
	var press := maxf(0.0, BELLY - _boom_height(t))
	if press > 0.0:
		return press
	var s := t - _leave_time()
	return -WOBBLE_AMP * exp(-s * WOBBLE_DECAY) * sin(TAU * s / WOBBLE_PERIOD)


## はね返るとき、お腹が紙から離れる時刻。
static func _leave_time() -> float:
	var span := BOUNCE_END - STRETCH_END
	var k := clampf((BELLY - STRETCH_DEPTH) / (BOUNCE_HEIGHT - STRETCH_DEPTH), 0.0, 1.0)
	return STRETCH_END + span * (1.0 - sqrt(1.0 - k))


## 紙が破れた（正解）。
static func torn(t: float) -> bool:
	return t >= PRESS_END


## 爆散した（まちがい）。
static func exploded(t: float) -> bool:
	return t >= EXPLODE_AT


## まちがいの人が紙に当たって、力が抜けた（ラグドール）。
static func limp(t: float) -> bool:
	return t >= 0.0 and t < EXPLODE_AT


## はね返って回る角度（rad、体の横の軸まわり。頭が上へ起きてうしろへ回る）。
static func tumble(t: float) -> float:
	return -TUMBLE * smoothstep(STRETCH_END, BOUNCE_END + 0.1, t)


## ボードの紙の面の高さ（落ちる点から、m、上が +）。
static func board_height(mode: int, t: float) -> float:
	if mode == ALL_BOOM:
		var y := -_boom_height(minf(t, STRETCH_END))
		var start := fade_start(mode)
		if t > start:
			y -= 0.5 * SINK_ACCEL * (t - start) * (t - start)
		return y
	return -_burst_height(mode, t)


## 体の中心の高さ（落ちる点から、m）。正解の人は落ちる点のまま。はね返された体はお腹が紙を離れたら紙とは別に飛ぶ。
static func body_height(burst: bool, mode: int, t: float) -> float:
	if burst:
		return 0.0
	return _boom_height(t) + board_height(mode, minf(t, _leave_time()))


## 通りすぎたボードが消え始める時刻。
static func fade_start(mode: int) -> float:
	return PRESS_END + FADE_AFTER_TEAR if mode == ALL_BURST else EXPLODE_AT + FADE_AFTER_BOOM


## 通りすぎたボードの不透明さ（1 → 0）。
static func board_alpha(mode: int, t: float) -> float:
	var start := fade_start(mode)
	return 1.0 - smoothstep(start, start + FADE_TIME, t)


## 見せ方の時計の速さ（1 = ふつう）。t は時間切れからの秒（負は前）。
## 全員が正解（ALL_BURST）でくぐるときは減速せず、そのままの速さで突き抜ける（ユーザーの指示）。
static func time_scale(t: float, mode := -1) -> float:
	if mode == ALL_BURST:
		return 1.0
	if t < -SLOW_IN:
		return 1.0
	if t < 0.0:
		return lerpf(1.0, SLOW, smoothstep(-SLOW_IN, 0.0, t))
	return lerpf(SLOW, 1.0, smoothstep(SLOW_OUT.x, SLOW_OUT.y, t))
