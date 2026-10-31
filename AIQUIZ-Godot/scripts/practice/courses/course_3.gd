extends PracticeCourse

## コース③ 2人対戦（台本 docs/new_tutorial/course3_script.md v0.2、段階6の設計 docs/new_tutorial/phase6_design.md 4章）。
## 3-0 相手を選ぶ → 3-1 2人の操作 → 3-2 早い者勝ち → 3-3 間違えても続く → 3-4 押し合い → 3-5 のこぎり
## → 3-6 ゴーストシャークに乗る → 3-7 ゴーストシャークをよける → 3-8 ゴールと得点 → 3-9 サドンデス（使えるときだけ）
## → クリア（このコースの play_clear）。
## 人どうし（P2 はキーボード：矢印・右の Ctrl・8 9 0）と、CPU と（P2 は担当 C の PracticeCpu。監督の setup_cpu）の両方の流れを持つ。
## 人どうしの 3-6・3-7 は同時に行う（3-6 は P1 がゴースト・P2 がよける、3-7 は役を入れかえて P2 がゴースト・P1 がよける）。
## 座標はゲーム画面のもの：x は +が画面の左、z はコンベア上の前。2人の開始の位置は P1 x +1.5、P2 x −1.5（z 0）。
## 本編側（担当 A）と CPU・カード（担当 C）の道具は、約束の名前で、あるときだけ使う（ないときは時間で先へ進むか、とばす）。
## ハートと正解数は1つの回のまま持ち越す（3-8 は 3-5 が終わったときの数。まきもどしではレッスンの始めの数へ戻す）。

## 相手を選ぶカード（担当 C）。まだないときは PracticeSession.with_cpu のまま（人どうしなら右の Ctrl を待つ）。
const PICK_CARD_PATH := "res://scripts/practice/ui/practice_pick_card.gd"
## 2人の開始の位置（x、z 0）
const P1_X := 1.5
const P2_X := -1.5
## 練習の壁（①と同じ）：22m 先に落ち、毎秒 1.6m で近づく。まきもどしのあとは 12m 先から
const WALL_DISTANCE := 22.0
const RETRY_DISTANCE := 12.0
const WALL_SPEED := 1.6
const START_DELAY := 0.5
## 見えないさく（①と同じ）：左右 x ±10、うしろ z −6、前 z +8（壁のレッスンは前を外す）
const FENCE_X := 10.0
const FENCE_BACK := -6.0
const FENCE_FRONT := 8.0
const OPEN_FRONT := 1000.0
## 3-1 でハテナが降りてくる高さ
const HATENA_DROP_HEIGHT := 9.0
## 雲で飛ぶ秒数（操縦席へ・壁の前へ・ゴールの審判へ）
const CLOUD_SECONDS := 1.4
## CPU の名前の付いた動きが終わるのを待つ最長（s）。CPU がないときも、この時間で先へ進む。
const CPU_WAIT := 4.0
## 看板の壁の前で、吹き出しを上げる高さ（等倍のハテナの空間の m。パネルの上端より上に出す）
const SIGN_BUBBLE_RAISE := 0.85

## 3-5 が終わったときのハートと正解数（3-8 で使う。P1, P2）。saved が false なら、まだ取っていない。
var saved := false
var saved_hp := [QuizGameState.MAX_HP, QuizGameState.MAX_HP]
var saved_score := [0, 0]


func _init() -> void:
	id = "c3"
	lesson_ids = ["3-0", "3-1", "3-2", "3-3", "3-4", "3-5", "3-6", "3-7", "3-8"]
	# 3-9 は本編のサドンデスを遊べるとき（デバッグ版）だけ
	if QuizGameState.sudden_death_available:
		lesson_ids.append("3-9")
	# ［次のコースへ］は④（メニューに戻ってすぐ④を始める。④はオンラインの画面から。監督の _on_clear_button_pressed）
	next_course = "c4"


func build_steps() -> Array[PracticeStep]:
	var list: Array[PracticeStep] = [PickStep.new(), KeysStep.new(), RaceStep.new(), ChanceStep.new(), PushStep.new(),
		SawStep.new(), GhostStep.new("3-6"), GhostStep.new("3-7"), GoalStep.new()]
	if QuizGameState.sudden_death_available:
		list.append(SuddenDeathStep.new())
	return list


## いまのハートと正解数を取っておく（3-8 で戻す）。
func save_scores(d: PracticeDirector) -> void:
	saved = true
	saved_hp = [d.game_state.get_player_hp(1), d.game_state.get_player_hp(2)]
	saved_score = [d.player_score(1), d.player_score(2)]


# ---------- クリア（台本③のクリア） ----------

func handles_clear() -> bool:
	return true


## 0.0 ハテナがプレイヤーの前へ雲で来て「対戦のルールはこれで全部」・本番の花火。1.5 スタンプが押される（カードとボタン）。
## 3.5「次はオンライン対戦」。★はない（③はノーミスの条件を決めない）。
func play_clear(d: PracticeDirector, star: bool) -> void:
	d.hatena_follow = false
	d.bubble_point = Callable()
	d.bubble_unanchored = false
	d.close_sign()
	var front := d.player_point(1) + PracticeDirector.CLEAR_HATENA_OFFSET
	front.y = PracticeDirector.HATENA_CLOUD_Y
	if not d.hatena.visible:
		d.hatena.place_at(front + Vector3(-4.0, 6.0, 2.0))
	d.hatena.ride_cloud_to(front, 0.8)
	d.world_call(&"practice_celebrate")
	d.hatena.play(&"cheer")
	d.say("c3.clear.1")
	await d.wait(1.5)
	if d.is_leaving():
		return
	d.hatena.face_toward(d.player_point(1))
	var number := str(PracticeCatalog.find(id).get("number", ""))
	var buttons := PracticeTexts.get_parts("c3.clear.buttons")
	# 初回の案内から始めたときは［次のコースへ］を、そうでなければ［メニューに戻る］を選んでおく（①と同じ）
	var focus := 0 if PracticeSession.from_first_run else buttons.size() - 1
	d.overlay.show_clear_card(PracticeTexts.get_parts("c3.clear.card"), number, star, buttons, focus)
	await d.wait(2.0)
	if d.is_leaving():
		return
	d.hatena.play(&"wave")
	d.say("c3.clear.2")


## コース③のレッスンの土台：ルールの決まりごとと、よく使う道具。
class Course3Step extends PracticeStep:
	## もと：コンベアは止める、ハートは本番どおり（下のカード）だが 1 より減らない（3-8 まではアウトにしない）、
	## ミスは本番どおり、海はかまれても通知だけ、記録しない。
	func base_rules() -> MatchRules:
		var rules := MatchRules.new()
		rules.world_speed = 0.0
		rules.hp_enabled = true
		rules.hp_floor = 1
		rules.mistakes = MatchRules.Mistakes.NORMAL
		rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
		rules.record_results = false
		return rules

	## 見えないさく（①と同じ）：左右 x ±10、うしろ z −6、前 front_z
	func fence(rules: MatchRules, front_z: float) -> void:
		rules.fence_enabled = true
		rules.fence_min = Vector2(-FENCE_X, FENCE_BACK)
		rules.fence_max = Vector2(FENCE_X, front_z)

	## 失敗の言葉の間：コンベアを止めて操作をロックする
	func hold(d: PracticeDirector) -> void:
		d.rules.world_speed = 0.0
		d.rules.input_locked = true

	func cpu(d: PracticeDirector) -> bool:
		return d.with_cpu()

	## 2人を開始の位置へ（P1 x +1.5、P2 x −1.5、z 0）
	func place_start(d: PracticeDirector) -> void:
		d.place_player(1, P1_X, 0.0)
		d.place_player(2, P2_X, 0.0)

	## 2人とも床に立たせる（アウト・ゴーストから戻す。ハートはそのまま）
	func revive_both(d: PracticeDirector) -> void:
		for index: int in [1, 2]:
			if not d.player_standing(index) or d.game_state.is_practice_bitten(index):
				d.revive(index)

	## いまのハート（P1, P2）
	func hearts(d: PracticeDirector) -> Array:
		return [d.game_state.get_player_hp(1), d.game_state.get_player_hp(2)]

	## ハートを戻す（まきもどしで、レッスンの始めの数へ）
	func restore_hearts(d: PracticeDirector, values: Array) -> void:
		for index: int in [1, 2]:
			var hp := int(values[index - 1])
			if d.game_state.get_player_hp(index) != hp:
				d.set_hp(index, hp)

	## 回が本番どおりのルールで終わっていた（全員アウトで GAME_OVER）なら、同じルールで回を始め直し、ハートと正解数を戻す。
	func reopen_round(d: PracticeDirector, rules: MatchRules, values: Array, scores: Array) -> void:
		if d.game_state.game_state == Constants.STATE_PLAYING:
			return
		var none: Array[QuizItem] = []
		d.restart_round(none, rules)
		restore_hearts(d, values)
		for index: int in [1, 2]:
			d.set_score(index, int(scores[index - 1]))

	## 看板の壁の前（ハテナが立つ所）。看板の壁がまだないときは、P1 から 14m 先の看板の前。
	func sign_spot(d: PracticeDirector) -> Vector3:
		var z := d.sign_local_z()
		if is_nan(z):
			z = d.game_state.player_local_z + PracticeDirector.SIGN_DISTANCE
		return Vector3(PracticeDirector.HATENA_WALL_X, 0.0, z - PracticeDirector.HATENA_WALL_FRONT)

	## 看板の壁の前では、吹き出しをハテナの頭より高く出す（パネルのキーの絵にかぶらないように。看板の題の左に出る）
	func raise_bubble(d: PracticeDirector) -> void:
		d.bubble_point = func() -> Vector3:
			if d.hatena == null or not d.hatena.visible:
				return Vector3(NAN, NAN, NAN)
			return d.hatena.bubble_point(HatenaGuide.BUBBLE_HEIGHT + SIGN_BUBBLE_RAISE)

	## 看板のパネルを1枚だけ光らせる（担当 C の blink_panel。ないときは全部）
	func blink_panel(d: PracticeDirector, key: StringName) -> void:
		if d.sign_wall != null and d.sign_wall.has_method(&"blink_panel"):
			d.sign_call(&"blink_panel", [key])
		else:
			d.blink_sign()

	## ハテナが見えていなければ、空からいまの立ち位置へ降ろす。見えていれば雲を消して、いまの壁の前へ（監督の follow_walls）。
	func show_hatena(d: PracticeDirector) -> void:
		d.bubble_point = Callable()
		d.bubble_unanchored = false
		d.hatena.set_cloud(false)
		d.follow_walls()

	## ハテナを雲で spot へ飛ばして（ゲーム画面の座標。y は足の高さ）、着いたら返る。
	func fly_hatena(d: PracticeDirector, spot: Vector3, seconds := CLOUD_SECONDS) -> void:
		d.hatena_follow = false
		if not d.hatena.visible:
			d.hatena.place_at(spot + Vector3(-4.0, 6.0, -2.0))
		await d.hatena.ride_cloud_to(spot, seconds)

	## 操縦席のハテナの足もと（ゲーム画面の座標）。のこぎりがないときは NAN。
	func seat_spot(d: PracticeDirector) -> Vector3:
		var seat := d.saw_seat_point()
		if not seat.is_finite():
			return seat
		var local := d.world.to_local(seat)
		return Vector3(local.x, maxf(local.y - 0.6, 0.0), local.z)

	## 台本の問題（3章）。question_id の「／」は2行にし、choices_id はドアの番号の順に「／」で区切った文字。
	static func make_quiz(question_id: String, choices_id: String, answer: int) -> QuizItem:
		var item := QuizItem.create(PracticeTexts.get_text(question_id).replace("／", "\n"), PracticeTexts.get_parts(choices_id), answer)
		item.src = "PRACTICE"
		return item


## 3-0 相手を選ぶ（約8秒）：ゲーム画面にカード「誰と練習する？」と［2人で］［CPUと］（担当 C の PracticePickCard）。
## ［2人で］はカードが「P2は右Ctrlで参加」を出して右の Ctrl を待ち、「P2が参加」で閉じる。選んだら PracticeSession.with_cpu に入れて 3-1。
## カードのスクリプトがないときは PracticeSession.with_cpu のまま（人どうしなら「P2は右Ctrlで参加」と言って Ctrl を待つ）。
class PickStep extends Course3Step:
	## 選んでから、カードが消えていくのを待つ（s）
	const CLOSE_WAIT := 0.3

	## &"pick"・&"join"（カードがないときの P2 の参加待ち）・&"done"
	var phase := &"pick"
	var _card: CanvasLayer = null

	func _init() -> void:
		id = "3-0"

	func enter(d: PracticeDirector) -> void:
		var rules := base_rules()
		rules.input_locked = true
		fence(rules, FENCE_FRONT)
		d.set_rules(rules)
		place_start(d)
		d.hatena_follow = false
		d.hatena.visible = false
		# 選ぶまでは P2 をキーボードのまま（CPU の名札も出さない）
		d.setup_cpu(false)
		phase = &"pick"
		_open(d, d.step_serial)

	func exit(_d: PracticeDirector) -> void:
		if is_instance_valid(_card):
			_card.queue_free()
		_card = null

	func _open(d: PracticeDirector, serial: int) -> void:
		# メニューから来た画面の切り替え（ワイプ）が開き終わってから
		if not await d.until(func() -> bool: return not SceneTransition.is_transitioning(), serial):
			return
		var script := d.tool_script(PICK_CARD_PATH)
		_card = script.new() as CanvasLayer if script != null else null
		if _card == null:
			_without_card(d, serial)
			return
		_card.name = "PracticePickCard"
		if _card.has_signal(&"chosen"):
			_card.connect(&"chosen", _on_chosen.bind(d, serial), CONNECT_ONE_SHOT)
		# P2 が参加したら、画面の右下の P2 のカードが光る（本編側の practice_card_shine）
		if _card.has_signal(&"p2_joined"):
			_card.connect(&"p2_joined", func() -> void: d.world_call(&"practice_card_shine", [2]), CONNECT_ONE_SHOT)
		# カードは木に入ると開く（担当 C の open_on_ready）。開かないカードは open で開く
		d.add_child(_card)
		if _card.has_method(&"open") and _card.has_method(&"is_open") and not bool(_card.call(&"is_open")):
			_card.call(&"open")

	func _on_chosen(with_cpu: bool, d: PracticeDirector, serial: int) -> void:
		if not d.is_current(serial) or phase != &"pick":
			return
		phase = &"done"
		PracticeSession.with_cpu = with_cpu
		d.setup_cpu(with_cpu)
		# カードが消えていくのを待つ（「P2が参加」はカードが見せ終えてから chosen を出す）
		await d.wait(CLOSE_WAIT)
		if d.is_current(serial):
			d.complete_step()

	## カードがないとき：PracticeSession.with_cpu のまま。人どうしなら「P2は右Ctrlで参加」→ Ctrl（テンキーの 0 でも）→「P2が参加」。
	func _without_card(d: PracticeDirector, serial: int) -> void:
		if d.with_cpu():
			phase = &"done"
			d.setup_cpu(true)
			d.complete_step()
			return
		phase = &"join"
		d.bubble_unanchored = true
		d.say("c3.pick.join")
		if not await d.until(func() -> bool:
				return Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_KP_0), serial):
			return
		phase = &"done"
		d.play_pico()
		d.world_call(&"practice_card_shine", [2])
		await d.say("c3.pick.joined")
		d.bubble_unanchored = false
		if d.is_current(serial):
			d.complete_step()


## 3-1 2人の操作（約20秒）：コンベアは止め、見えないさく。看板「2人のときの操作」（左 P1：W A S D ＋ スペース、右 P2：↑ ↓ ← → ＋ 右 Ctrl）。
## それぞれが左右・前後に合計1.5mずつ動いて1回ジャンプすると、その人のパネルに ✓（人どうしは2人とも、CPU とでは P1 だけ）。
## CPU とで P1 が矢印キーを押したら「2人のときP1はWASDで動く」をもう一度言い、左のパネルが点滅する。
class KeysStep extends Course3Step:
	const NEED := 1.5
	## 1フレームでこれより大きく動いたら置き直し（数えない）
	const TELEPORT := 1.0
	## 矢印キーの声かけをくり返さない間（s）
	const ARROW_HINT_GAP := 5.0
	const ARROW_KEYS: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	const PANELS: Array[StringName] = [&"p1_keys", &"p2_keys"]

	## &"intro"（言葉の間。動きは数える）・&"play"・&"done"
	var phase := &"intro"
	## 人ごと（0 = P1、1 = P2）の左右・前後の合計、ジャンプ、✓
	var _side := [0.0, 0.0]
	var _depth := [0.0, 0.0]
	var _jumped := [false, false]
	var _ticked := [false, false]
	var _last := [Vector2.ZERO, Vector2.ZERO]
	var _arrow_gap := 0.0
	var _arrows_held := false

	func _init() -> void:
		id = "3-1"

	func enter(d: PracticeDirector) -> void:
		var rules := base_rules()
		fence(rules, FENCE_FRONT)
		d.set_rules(rules)
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		revive_both(d)
		place_start(d)
		phase = &"intro"
		_side = [0.0, 0.0]
		_depth = [0.0, 0.0]
		_jumped = [false, false]
		_ticked = [false, false]
		_last = [d.player_pos(1), d.player_pos(2)]
		_arrow_gap = 0.0
		_arrows_held = false
		d.open_sign(PracticeTexts.get_parts("c3.keys.sign"), [
			{"key": PANELS[0], "keys": ["W", "A", "S", "D"], "sub": "スペース", "player": 1},
			{"key": PANELS[1], "keys": ["↑", "↓", "←", "→"], "sub": "右 Ctrl", "player": 2},
		])
		d.bubble_unanchored = false
		raise_bubble(d)
		d.hatena.set_cloud(false)
		_intro(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		d.bubble_point = Callable()

	func _intro(d: PracticeDirector, serial: int) -> void:
		# ハテナが空から看板の前へ降りてくる（3-0 では隠れている）
		if not d.hatena.visible:
			var spot := sign_spot(d)
			d.hatena.place_at(spot + Vector3.UP * HATENA_DROP_HEIGHT)
			await d.hatena.hop_to(spot, 0.6)
			if not d.is_current(serial):
				return
		d.follow_walls()
		if cpu(d):
			# 「今回の相手はCPU」→ 2秒後「2人のときP1はWASDで動く」（左のパネル）→「WASDで動いてジャンプしてみて」
			# （台本の「CPU が手をふる」は、CPU のエモート枠1が手をふる動きではないのでやめた。CPU は何もしない）
			d.hatena.play(&"wave")
			d.cpu_call(&"idle")
			await d.say("c3.keys.cpu1")
			if not d.is_current(serial):
				return
			d.hatena.play(&"point")
			blink_panel(d, PANELS[0])
			await d.say("c3.keys.cpu2")
			if not d.is_current(serial):
				return
			d.say("c3.keys.cpu3")
		else:
			# 「2人のときは操作が変わる」→「P1はWASDとスペース」（左）→「P2は矢印キーと右Ctrl」（右）→「エモートはP2なら8・9・0」→「2人とも動いてみて」
			d.hatena.play(&"open_arms")
			await d.say("c3.keys.1")
			if not d.is_current(serial):
				return
			d.hatena.play(&"point")
			blink_panel(d, PANELS[0])
			await d.say("c3.keys.2")
			if not d.is_current(serial):
				return
			blink_panel(d, PANELS[1])
			await d.say("c3.keys.3")
			if not d.is_current(serial):
				return
			await d.say("c3.keys.5")
			if not d.is_current(serial):
				return
			d.hatena.play(&"wave")
			d.say("c3.keys.6")
		phase = &"play"
		_check_done(d)

	## 数える人（人どうしは2人、CPU とでは P1 だけ）
	func _players(d: PracticeDirector) -> Array[int]:
		var list: Array[int] = [1]
		if not cpu(d):
			list.append(2)
		return list

	func process(d: PracticeDirector, dt: float) -> void:
		if phase == &"done":
			return
		for index: int in _players(d):
			var i := index - 1
			var now := d.player_pos(index)
			var delta: Vector2 = now - _last[i]
			_last[i] = now
			if delta.length() > TELEPORT:
				continue
			_side[i] = float(_side[i]) + absf(delta.x)
			_depth[i] = float(_depth[i]) + absf(delta.y)
			_try_tick(d, index)
		_watch_arrows(d, dt)
		_check_done(d)

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if event == &"jumped" and phase != &"done":
			var index := int(data.player)
			if index in _players(d):
				_jumped[index - 1] = true
				_try_tick(d, index)
				_check_done(d)

	## 左右・前後に1.5mずつ動いて1回ジャンプしたら、その人のパネルに ✓
	func _try_tick(d: PracticeDirector, index: int) -> void:
		var i := index - 1
		if bool(_ticked[i]) or float(_side[i]) < NEED or float(_depth[i]) < NEED or not bool(_jumped[i]):
			return
		_ticked[i] = true
		d.tick_sign(PANELS[i])

	func _check_done(d: PracticeDirector) -> void:
		if phase != &"play":
			return
		for index: int in _players(d):
			if not bool(_ticked[index - 1]):
				return
		phase = &"done"
		_finish(d, d.step_serial)

	## CPU とで、P1 が矢印キーを押した（押し始め）：「2人のときP1はWASDで動く」と左のパネルの点滅
	func _watch_arrows(d: PracticeDirector, dt: float) -> void:
		_arrow_gap = maxf(0.0, _arrow_gap - dt)
		var held := false
		for key: Key in ARROW_KEYS:
			if Input.is_key_pressed(key):
				held = true
		var pressed := held and not _arrows_held
		_arrows_held = held
		if not cpu(d) or phase != &"play" or bool(_ticked[0]) or not pressed or _arrow_gap > 0.0:
			return
		_arrow_gap = ARROW_HINT_GAP
		d.hatena.play(&"point")
		d.say("c3.keys.cpu2")
		blink_panel(d, PANELS[0])

	func _finish(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"clap")
		await d.say("c3.keys.ok")
		if d.is_current(serial):
			d.complete_step()


## 3-2・3-3・3-5・3-8 の土台：2択の壁が 22m 先に落ち、着地から 0.5 秒でコンベアが練習の速さで動き出す。
## 先に正解した人だけ得点（本番の2人の問題）。だれも正解しないまま壁が終わったら、まきもどし（ハートはレッスンの始めの数へ）。
class WallLesson extends Course3Step:
	## &"wait"（壁が落ちてくる）・&"play"・&"talk"（言葉の間）・&"fail"・&"done"
	var phase := &"wait"
	## レッスンの始めのハート（まきもどしで戻す）
	var start_hp := [QuizGameState.MAX_HP, QuizGameState.MAX_HP]
	var start_score := [0, 0]

	## いまの壁の問題
	func quiz() -> QuizItem:
		return null

	## 正解のドアの番号
	func answer() -> int:
		return 0

	func lesson_rules(_d: PracticeDirector) -> MatchRules:
		var rules := base_rules()
		fence(rules, OPEN_FRONT)
		return rules

	## 壁を落とす（言葉はレッスンが言う）
	func drop(d: PracticeDirector, distance := WALL_DISTANCE) -> void:
		phase = &"wait"
		d.rules.world_speed = 0.0
		var quizzes: Array[QuizItem] = [quiz()]
		d.set_quizzes(quizzes)
		d.drop_wall(distance)

	## 着地から 0.5 秒（コンベアが動き出すとき。CPU を動かす）
	func on_started(_d: PracticeDirector) -> void:
		pass

	## だれかが正解した（mask は 1 = P1、2 = P2、3 = 同時）
	func on_won(_d: PracticeDirector, _serial: int, _mask: int) -> void:
		pass

	func begin_lesson(d: PracticeDirector) -> void:
		d.close_sign()
		d.set_rules(lesson_rules(d))
		# 前のレッスンで壁をくぐった所から、2人を開始の位置へ戻す（ドアの前で重ならないように）
		revive_both(d)
		place_start(d)
		start_hp = hearts(d)
		start_score = [d.player_score(1), d.player_score(2)]
		show_hatena(d)

	func rewind(d: PracticeDirector) -> void:
		var rules := lesson_rules(d)
		reopen_round(d, rules, start_hp, start_score)
		d.set_rules(rules)
		revive_both(d)
		restore_hearts(d, start_hp)
		place_start(d)
		d.cpu_call(&"idle")
		drop(d, RETRY_DISTANCE)

	func hint_door_x(d: PracticeDirector) -> float:
		return d.door_x(answer(), 2) if phase in [&"wait", &"play"] else NAN

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"wall_landed":
				if phase == &"wait":
					_start(d, d.step_serial)
			&"winner":
				if phase in [&"wait", &"play"] and int(data.mask) != 0:
					phase = &"talk"
					on_won(d, d.step_serial, int(data.mask))
			&"question_completed":
				# だれも正解しないまま壁が終わった（2人とも間違えた）
				if phase in [&"wait", &"play"] and not bool(data.correct):
					fail(d, d.step_serial, "")
			&"ocean_bitten":
				if phase in [&"wait", &"play"]:
					fail(d, d.step_serial, "")

	func _start(d: PracticeDirector, serial: int) -> void:
		await d.wait(START_DELAY)
		if not d.is_current(serial) or phase != &"wait":
			return
		phase = &"play"
		d.rules.world_speed = d.practice_speed(WALL_SPEED)
		on_started(d)

	## 失敗：コンベアを止め、line を言ってから「もう一回」→ まきもどし
	func fail(d: PracticeDirector, serial: int, line: String) -> void:
		phase = &"fail"
		hold(d)
		d.cpu_call(&"idle")
		if not line.is_empty():
			await d.say(line)
			if not d.is_current(serial):
				return
		d.fail_step("c3.any.retry")


## 3-2 早い者勝ち（約35秒）：壁1「1ダースは何個？」（青「12」が正解）。CPU とでは壁2「8 × 9 = ?」（赤「72」が正解）も。
## 人どうし：だれかが正解したら「P1の得点」（P2）→「得点は下のカードに出る」でクリア。
## CPU と：壁1は CPU がゆっくり正解へ（プレイヤーが先に着ける速さ）。壁2は CPU が前へ走って先に正解へ。壁2が終わればクリア。
class RaceStep extends WallLesson:
	## 壁1の CPU の急ぎ（プレイヤーが先に着ける）・壁2（前へ全力）
	const SLOW_HASTE := 0.1
	const FAST_HASTE := 1.0
	## 壁2の前に、CPU が P1 の横（画面の右へ 3m）へ寄る
	const CPU_SIDE := 3.0

	## 0 = 壁1、1 = 壁2（CPU とだけ）
	var wall := 0

	func _init() -> void:
		id = "3-2"

	func quiz() -> QuizItem:
		if wall == 0:
			return make_quiz("c3.race.q1", "c3.race.c1", 0)
		return make_quiz("c3.race.q2", "c3.race.c2", 1)

	func answer() -> int:
		return 0 if wall == 0 else 1

	func enter(d: PracticeDirector) -> void:
		begin_lesson(d)
		wall = 0
		drop(d)
		_opening(d, d.step_serial)

	## ジャンプで移って「先にくぐった方だけ得点」→（人どうしは）3秒後「前に出れば早く着く」
	func _opening(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"point")
		d.say("c3.race.1")
		if cpu(d):
			return
		await d.wait(3.0)
		if d.is_current(serial) and phase in [&"wait", &"play"]:
			d.say("c3.race.2")

	func on_started(d: PracticeDirector) -> void:
		if cpu(d):
			d.cpu_call(&"go_door", [answer(), SLOW_HASTE if wall == 0 else FAST_HASTE])

	func on_won(d: PracticeDirector, serial: int, mask: int) -> void:
		var p1 := (mask & 1) != 0
		if not cpu(d):
			# 「P1の得点」（または「P2の得点」）→ 下のカードを指して「得点は下のカードに出る」
			d.hatena.play(&"clap")
			await d.say("c3.race.p1" if p1 else "c3.race.p2")
			if not d.is_current(serial):
				return
			d.hatena.play(&"point")
			await d.say("c3.race.card")
			if d.is_current(serial):
				phase = &"done"
				d.complete_step()
			return
		if wall == 0:
			# 壁1：「先に取ったね」（CPU が先なら「CPUに先を越された」）→「得点は下のカードに出る」。その間に CPU が P1 の横へ寄る
			d.hatena.play(&"clap" if p1 else &"oops")
			_cpu_beside_p1(d)
			await d.say("c3.race.win" if p1 else "c3.race.lost")
			if not d.is_current(serial):
				return
			d.hatena.play(&"point")
			await d.say("c3.race.card")
			if not d.is_current(serial):
				return
			await _cpu_arrived(d, serial)
			if not d.is_current(serial):
				return
			# 壁2が来る「前に出れば早く着く」
			wall = 1
			drop(d)
			d.hatena.play(&"point")
			d.say("c3.race.2")
			return
		# 壁2：CPU が先なら「CPUに先を越された」→「速さも大事」、プレイヤーが先なら「速い」
		if p1:
			d.hatena.play(&"cheer")
			await d.say("c3.race.fast")
		else:
			d.hatena.play(&"oops")
			await d.say("c3.race.lost")
			if not d.is_current(serial):
				return
			await d.say("c3.race.speed")
		if d.is_current(serial):
			phase = &"done"
			d.complete_step()

	## 壁2の前に、CPU を P1 の横へ歩かせる（P1 のずっと後ろにいると、壁2で先に行けないので）
	func _cpu_beside_p1(d: PracticeDirector) -> void:
		var p1 := d.player_pos(1)
		var x := clampf(p1.x - CPU_SIDE, -FENCE_X + 1.0, FENCE_X - 1.0)
		d.cpu_call(&"move_to", [x, p1.y, 1.0])

	func _cpu_arrived(d: PracticeDirector, serial: int) -> void:
		if not d.has_cpu() or not d.cpu.has_method(&"is_arrived"):
			return
		var deadline := Time.get_ticks_msec() + int(CPU_WAIT * 1000.0)
		await d.until(func() -> bool: return bool(d.cpu.call(&"is_arrived")) or Time.get_ticks_msec() >= deadline, serial)



## 3-3 間違えても続く（約22秒）：壁「日本一長い川は？」（赤「信濃川」が正解）。片方が間違えても、もう1人が答えるまで問題は続く。
## CPU とでは CPU が先に青「利根川」へ走り込む（ハートが1つ減る。本番どおり）→「CPUが間違えた」→「でも問題は続く」。
## 人どうしは役を決めない：片方が先に間違えたら「でも問題は続く」。正解が出たら「もう1人が答えるまで続くよ」。
## 先に間違いが出なかったとき（先に正解した・同時に正解した）は、壁が終わったあとに「片方が間違えても」→「もう1人が答えるまで続くよ」。
class ChanceStep extends WallLesson:
	## CPU が間違いのドアへ走り込む急ぎ
	const WRONG_HASTE := 0.8

	var _wrong_seen := false

	func _init() -> void:
		id = "3-3"

	func quiz() -> QuizItem:
		return make_quiz("c3.chance.q", "c3.chance.c", 1)

	func answer() -> int:
		return 1

	func enter(d: PracticeDirector) -> void:
		begin_lesson(d)
		_wrong_seen = false
		# ジャンプで移る（監督）。壁が落ちてくる
		drop(d)

	func rewind(d: PracticeDirector) -> void:
		_wrong_seen = false
		super.rewind(d)

	func on_started(d: PracticeDirector) -> void:
		if cpu(d):
			d.cpu_call(&"go_door", [0, WRONG_HASTE])

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if event == &"wall_contact" and phase == &"play" and not bool(data.correct) and not _wrong_seen:
			_wrong(d, d.step_serial, int(data.player))
		super.on_event(d, event, data)

	## 先に間違えた人が出た：CPU なら「CPUが間違えた」→「でも問題は続く」、人どうしなら「でも問題は続く」
	func _wrong(d: PracticeDirector, serial: int, player: int) -> void:
		_wrong_seen = true
		if cpu(d) and player == 2:
			d.cpu_call(&"idle")
			d.hatena.play(&"point")
			await d.say("c3.chance.1")
			if not d.is_current(serial) or phase != &"play":
				return
		d.hatena.play(&"open_arms")
		d.say("c3.chance.2")

	func on_won(d: PracticeDirector, serial: int, _mask: int) -> void:
		d.cpu_call(&"idle")
		d.hatena.play(&"clap")
		if not _wrong_seen:
			await d.say("c3.chance.human")
			if not d.is_current(serial):
				return
		await d.say("c3.chance.3")
		if d.is_current(serial):
			phase = &"done"
			d.complete_step()


## 3-4 押し合い（約25秒）：コンベアを止め、見えないさく。看板「押し続けて踏ん張る」（2人が押し合う絵・「離す → 押す」の絵）。
## 2人を横に並べてくっつける（P1 x +0.6、P2 x −0.6）。本編の押し合い（MatchRules.local_push_enabled）。
## 押し合いになる（本編の "stalemate"）→「踏ん張ってる」✓ →「一度離して押し直すと…」→ 一押し（"hit"）→「一押しが入った」✓
## →「端で押されると海に落ちる」。CPU とでは CPU がプレイヤーのほうへ押し続け、P1 の一押しだけを数える（人どうしはどちらでも）。
class PushStep extends Course3Step:
	const PUSH_X := 0.6
	const IDLE_HINT_SECONDS := 6.0
	const PANELS: Array[StringName] = [&"push", &"push_again"]

	## &"push"（押し合いを待つ）・&"braced"（一押しを待つ）・&"done"
	var phase := &"push"
	var _idle := 0.0

	func _init() -> void:
		id = "3-4"

	func lesson_rules() -> MatchRules:
		var rules := base_rules()
		fence(rules, FENCE_FRONT)
		rules.local_push_enabled = true
		return rules

	func enter(d: PracticeDirector) -> void:
		d.set_rules(lesson_rules())
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		revive_both(d)
		d.place_player(1, PUSH_X, 0.0)
		d.place_player(2, -PUSH_X, 0.0)
		phase = &"push"
		_idle = 0.0
		d.open_sign(PracticeTexts.get_parts("c3.push.sign"), [
			{"key": PANELS[0], "picture": &"push"},
			{"key": PANELS[1], "picture": &"push_again"},
		])
		show_hatena(d)
		raise_bubble(d)
		d.hatena.play(&"point")
		d.say("c3.push.1")
		d.cpu_call(&"push_toward_p1")

	func exit(d: PracticeDirector) -> void:
		d.cpu_call(&"idle")
		d.bubble_point = Callable()

	func process(d: PracticeDirector, dt: float) -> void:
		if phase != &"push":
			return
		_idle += dt
		if _idle >= IDLE_HINT_SECONDS:
			_idle = 0.0
			d.hatena.play(&"point")
			d.say("c3.push.idle")

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if event != &"push":
			return
		match StringName(data.kind):
			&"stalemate":
				if phase == &"push":
					phase = &"braced"
					_braced(d, d.step_serial)
			&"hit":
				var player := int(data.player)
				if phase != &"done" and (player == 1 or (player == 2 and not cpu(d))):
					phase = &"done"
					_hit(d, d.step_serial)

	## 押し合いになった：「踏ん張ってる」と左のパネルに ✓ → 1秒ほどして「一度離して押し直すと…」
	## （すぐに押し合いになったときも、始めの「相手の方へ押し続けて」は言い終えてから）
	func _braced(d: PracticeDirector, serial: int) -> void:
		if not await d.until(func() -> bool: return d.saying() != "c3.push.1", serial) or phase != &"braced":
			return
		d.tick_sign(PANELS[0])
		d.hatena.play(&"clap")
		await d.say("c3.push.2")
		if not d.is_current(serial) or phase != &"braced":
			return
		d.hatena.play(&"point")
		d.say("c3.push.3")

	## 一押しが入った：右のパネルに ✓ →「一押しが入った」→「端で押されると海に落ちる」
	func _hit(d: PracticeDirector, serial: int) -> void:
		d.tick_sign(PANELS[0])
		d.tick_sign(PANELS[1])
		d.cpu_call(&"idle")
		d.hatena.play(&"cheer")
		await d.say("c3.push.4")
		if not d.is_current(serial):
			return
		d.hatena.play(&"point")
		await d.say("c3.push.5")
		if d.is_current(serial):
			d.complete_step()


## 3-5 のこぎり（約30秒）：看板の壁は空へ戻り、さくを外す。ハテナが雲でのこぎりの操縦席へ移る（案内のハテナを隠し、
## 操縦席のハテナに吹き出しを付ける）。のこぎりは本番どおり（MatchRules.saw_enabled）、捕まっても通知だけ（saw = REPORT_ONLY）。
## 壁「1時間は何分？」（青「60分」が正解）。正解が出たら「逃げ切った」でクリア（人どうしは2人とも捕まらずに、CPU とではプレイヤーが）。
## 捕まったら「捕まったね」→「もう一回」→ まきもどしで壁の始めへ（ゴーストにはしない）。
class SawStep extends WallLesson:
	## だれかののこぎりまでの近さ（m）がこれより近くなったら「前へ逃げて」→「ジャンプではよけられない」
	const NEAR := 4.0
	## CPU の急ぎ（プレイヤーに置いていかれない速さで、正解のドアへ）
	const CPU_HASTE := 0.6
	## 操縦席のハテナの吹き出しの付け根（体の真ん中から上へ、m）
	const SEAT_BUBBLE_UP := 1.1

	var _near_said := false
	var _caught := false

	func _init() -> void:
		id = "3-5"

	func quiz() -> QuizItem:
		return make_quiz("c3.saw.q", "c3.saw.c", 0)

	func answer() -> int:
		return 0

	func lesson_rules(_d: PracticeDirector) -> MatchRules:
		var rules := base_rules()
		rules.saw_enabled = true
		PracticeDirector.set_saw_report_only(rules)
		return rules

	func enter(d: PracticeDirector) -> void:
		d.close_sign()
		var rules := lesson_rules(d)
		d.set_rules(rules)
		start_hp = hearts(d)
		start_score = [d.player_score(1), d.player_score(2)]
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		revive_both(d)
		place_start(d)
		phase = &"intro"
		_near_said = false
		_caught = false
		_intro(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		# のこぎりは止めて操縦席に戻す（本番の止まり方）。吹き出しはハテナへ戻す（3-6 で雲で壁の前へ）
		if d.rules != null:
			d.rules.saw_enabled = false
		d.bubble_point = Callable()
		d.bubble_unanchored = false

	## ハテナが雲で操縦席へ →（操縦席から）「次はのこぎりが追ってくる」→ 2秒後「触れたらハートがあってもアウト」
	## → 壁が落ちてくる「カードが赤くなったら危険」
	func _intro(d: PracticeDirector, serial: int) -> void:
		await _to_seat(d, serial)
		if not d.is_current(serial):
			return
		d.say("c3.saw.1")
		await d.wait(2.0)
		if not d.is_current(serial):
			return
		await d.say("c3.saw.4")
		if not d.is_current(serial):
			return
		drop(d)
		d.say("c3.saw.5")

	## 案内のハテナが雲で操縦席へ飛び、着いたら隠れて、操縦席のハテナが出る（吹き出しは操縦席のハテナに付く）。
	## のこぎりがないときは、ハテナを隠して吹き出しを画面の上に出す。
	func _to_seat(d: PracticeDirector, serial: int) -> void:
		var spot := seat_spot(d)
		d.set_saw_operator_hidden(true)
		if spot.is_finite() and d.hatena.visible:
			d.hatena.play(&"wave")
			await fly_hatena(d, spot + Vector3(0.0, PracticeDirector.HATENA_CLOUD_Y, 0.0))
			if not d.is_current(serial):
				return
		d.hatena.set_cloud(false)
		d.hatena.visible = false
		d.hatena_follow = false
		d.set_saw_operator_hidden(false)
		if spot.is_finite():
			d.bubble_point = func() -> Vector3:
				var seat := d.saw_seat_point()
				return seat + Vector3.UP * SEAT_BUBBLE_UP if seat.is_finite() else seat
		else:
			d.bubble_unanchored = true

	func rewind(d: PracticeDirector) -> void:
		var rules := lesson_rules(d)
		reopen_round(d, rules, start_hp, start_score)
		d.set_rules(rules)
		revive_both(d)
		restore_hearts(d, start_hp)
		_reset_saw(d)
		place_start(d)
		d.cpu_call(&"idle")
		_near_said = false
		_caught = false
		drop(d, WALL_DISTANCE)

	## のこぎりを始めの所へ戻す（本編側の practice_reset_saw。ないときは、のこぎりの状態を始めに戻す）
	func _reset_saw(d: PracticeDirector) -> void:
		if d.has_practice(&"practice_reset_saw"):
			d.practice_call(&"practice_reset_saw")
			return
		d.game_state.saw.reset()
		d.game_state.p1_saw_killed = false
		d.game_state.p2_saw_killed = false

	func on_started(d: PracticeDirector) -> void:
		if cpu(d):
			d.cpu_call(&"go_door", [answer(), CPU_HASTE])

	func process(d: PracticeDirector, _dt: float) -> void:
		if phase != &"play" or _near_said:
			return
		for index: int in [1, 2]:
			if d.game_state.get_saw_clearance(index) < NEAR:
				_near_said = true
				_near(d, d.step_serial)
				return

	## だれかがのこぎりに近づいた：「前へ逃げて」→「ジャンプではよけられない」
	func _near(d: PracticeDirector, serial: int) -> void:
		await d.say("c3.saw.6")
		if d.is_current(serial) and phase == &"play":
			d.say("c3.saw.7")

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"saw_caught", &"caught_by_saw":
				if phase in [&"intro", &"wait", &"play"] and not _caught:
					_caught = true
					fail(d, d.step_serial, "c3.saw.caught")
				return
		super.on_event(d, event, data)

	## 正解が出た：「逃げ切った」→ のこぎりは止まって操縦席へ戻る。ハートと正解数を取っておく（3-8）
	func on_won(d: PracticeDirector, serial: int, _mask: int) -> void:
		d.rules.saw_enabled = false
		d.cpu_call(&"idle")
		(d.course as PracticeCourse).call(&"save_scores", d)
		await d.say("c3.saw.ok")
		if d.is_current(serial):
			phase = &"done"
			d.complete_step()


## 3-6 ゴーストシャークに乗る（約40秒）・3-7 ゴーストシャークをよける（約25秒）。本番のゴーストシャーク（MatchRules.ghost_ride_enabled）。
## CPU と：3-6 は P1 をアウトにした場面から（本番の脱落の演出 → 魂 → サメに乗る → 光の柱 → 登場）、CPU は床の上をゆっくり左右に動く。
##   突進を1回当てたらクリア（外れたら「惜しい、もう一回」）。3-7 は CPU をアウトにした場面から（演出は短く）、
##   CPU のゴーストがプレイヤーを狙って突進する。1回よけたらクリア（当たって海に落ちたら、まきもどし）。
## 人どうし：3-6 は P1 がゴースト・P2 がよける、3-7 は役を入れかえる。どちらも、1回当てて1回よけたら終わり。
## 演出は2回目から Enter で飛ばせる（監督の allow_ghost_skip）。3-6 と人どうしは、相手が海へ落ちないよう見えないさくを置く。
class GhostStep extends Course3Step:
	## ゴーストの照準・ため・突進の言葉（P1 なら「スペース長押しでためる」、P2 なら「右Ctrl長押しでためる」）
	const AIM_KEYS_P1: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D]
	const AIM_KEYS_P2: Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	## CPU の的が左右に動く幅（x）と速さ
	const WANDER := Vector2(-3.0, 3.0)
	const WANDER_SPEED := 0.4
	## ゴーストの道具（本編）がないとき、このレッスンを見せずに進むまで（s）
	const NO_GHOST_SECONDS := 1.0
	## 照準の輪が出てから、輪を動かさなくても「…長押しでためる」を言うまで（s）
	const AIM_LINE_SECONDS := 2.5
	## 置く所（ゴーストになる人・的の人）
	const GHOST_SPOT := Vector2(3.0, 0.0)
	const TARGET_SPOT := Vector2(-1.5, 1.0)

	## ゴーストになる人と的の人
	var ghost := 1
	var target := 2
	## &"intro"（演出）・&"aim"・&"play"・&"talk"・&"fail"・&"done"
	var phase := &"intro"
	var hits := 0
	var dodges := 0
	var _mount_said := false
	var _aim_said := false
	var _charge_said := false
	var _perfect_said := false
	var _brace_said := false
	var _miss_said := false
	var _cpu_attacking := false
	## 照準の輪が出てからの秒
	var _aim_clock := 0.0

	func _init(step_id: String) -> void:
		id = step_id

	## 3-6 か（人どうしは 3-6 が P1 ゴースト、3-7 が P2 ゴースト。CPU とは 3-6 が P1 ゴースト、3-7 が CPU ゴースト）
	func _first() -> bool:
		return id == "3-6"

	## 練習している人がゴースト（狙う側の言葉を出す）
	func attack_lines(d: PracticeDirector) -> bool:
		return not cpu(d) or ghost == 1

	## 練習している人が的（よける側の言葉を出す）
	func dodge_lines(d: PracticeDirector) -> bool:
		return not cpu(d) or target == 1

	## 終わる条件：CPU とでは 3-6 が1回当てる・3-7 が1回よける。人どうしは1回当てて1回よける
	func _cleared(d: PracticeDirector) -> bool:
		if cpu(d):
			return hits >= 1 if ghost == 1 else dodges >= 1
		return hits >= 1 and dodges >= 1

	## 相手が海へ落ちないよう見えないさくを置く（CPU との 3-7 だけ外す：海まで飛ばされることもある）
	func _fenced(d: PracticeDirector) -> bool:
		return not (cpu(d) and ghost == 2)

	func lesson_rules(d: PracticeDirector) -> MatchRules:
		var rules := base_rules()
		rules.ghost_ride_enabled = true
		if _fenced(d):
			fence(rules, FENCE_FRONT)
		return rules

	func enter(d: PracticeDirector) -> void:
		ghost = 1 if _first() else 2
		target = 3 - ghost
		var course := d.course as PracticeCourse
		# 3-5 をとばしたときも、3-8 のためにハートと正解数を取っておく（ゴーストでハートが変わる前に）
		if not bool(course.get(&"saved")):
			course.call(&"save_scores", d)
		d.set_rules(lesson_rules(d))
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		d.close_sign()
		_reset_flags()
		_begin(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		d.allow_ghost_skip = false
		d.cpu_call(&"idle")

	func _reset_flags() -> void:
		phase = &"intro"
		hits = 0
		dodges = 0
		_mount_said = false
		_aim_said = false
		_charge_said = false
		_perfect_said = false
		_brace_said = false
		_miss_said = false
		_cpu_attacking = false
		_aim_clock = 0.0

	## 2人とも床に戻し（3-7 は 3-6 のゴーストから戻す）、ゴーストになる人を左、的を真ん中へ置いて、ゴーストの演出を始める。
	func _begin(d: PracticeDirector, serial: int) -> void:
		revive_both(d)
		# ゴースト（ハートは 0）から戻した人のハートを、ゴーストの前の数へ（3-7 の P1 など）
		var hp: Array = (d.course as PracticeCourse).get(&"saved_hp")
		for index: int in [1, 2]:
			if d.game_state.get_player_hp(index) <= 0:
				d.set_hp(index, maxi(int(hp[index - 1]), 1))
		var ghost_spot := GHOST_SPOT if ghost == 1 else Vector2(-GHOST_SPOT.x, GHOST_SPOT.y)
		d.place_player(ghost, ghost_spot.x, ghost_spot.y)
		d.place_player(target, TARGET_SPOT.x if target == 2 else -TARGET_SPOT.x, TARGET_SPOT.y)
		d.cpu_call(&"idle")
		# 3-6 の始めは、ハテナが操縦席から雲で前へ（3-5 から）
		if _first():
			await _from_seat(d, serial)
			if not d.is_current(serial):
				return
		else:
			show_hatena(d)
		if _first():
			d.hatena.play(&"open_arms")
			d.say("c3.ghost.1")
		else:
			d.hatena.play(&"point")
			d.say("c3.dodge.1")
		# CPU との 3-7 は演出を短く（台本）。ほかは本番の演出（2回目から Enter で飛ばせる）
		var short := cpu(d) and ghost == 2
		if not d.make_ghost(ghost, short):
			# 本編側の道具がない：見せられないので、言葉だけで先へ進む
			await d.wait(NO_GHOST_SECONDS)
			if not d.is_current(serial):
				return
			await d.say("c3.ghost.2")
			if d.is_current(serial):
				phase = &"done"
				d.complete_step()
			return
		# CPU の的は床の上をゆっくり左右に動く
		if cpu(d) and target == 2:
			d.cpu_call(&"wander", [WANDER, WANDER_SPEED])

	## 操縦席から雲でプレイヤーの前へ（のこぎりがないとき・もう見えているときは、いまの立ち位置へ）
	func _from_seat(d: PracticeDirector, serial: int) -> void:
		d.bubble_point = Callable()
		d.bubble_unanchored = false
		var seat := seat_spot(d)
		if not d.hatena.visible and seat.is_finite():
			d.set_saw_operator_hidden(true)
			d.hatena.place_at(seat + Vector3(0.0, PracticeDirector.HATENA_CLOUD_Y, 0.0))
			var front := d.player_point(1) + PracticeDirector.HATENA_PLAYER_FRONT
			front.x = clampf(front.x, -PracticeDirector.HATENA_WALL_X, PracticeDirector.HATENA_WALL_X)
			front.y = PracticeDirector.HATENA_CLOUD_Y
			await fly_hatena(d, front)
			if not d.is_current(serial):
				return
		show_hatena(d)

	func process(d: PracticeDirector, dt: float) -> void:
		if phase in [&"done", &"fail"]:
			return
		var state := d.ghost_presentation(ghost)
		var stage := str(state.get("phase", ""))
		# サメに乗る「ゴーストシャークで続けられる」（3-6 の始めだけ）
		if _first() and not _mount_said and stage in ["MOUNTING", "BEAM_REVEAL", "ENTERING"]:
			_mount_said = true
			d.say("c3.ghost.2")
		# 照準の輪が出た（本編側の practice_ghost_ready がないときの代わり）
		if phase == &"intro" and stage in ["AIMING", "WINDUP", "CHARGING"]:
			_aim_ready(d)
		if phase not in [&"aim", &"play"]:
			return
		var charge := d.ghost_charge(ghost)
		var charging := float(charge.charge) > 0.05
		# 輪が動いた「スペース長押しでためる」（P2 なら「右Ctrl長押しでためる」）。輪を動かさずに狙えているとき
		# （輪が最初から相手の上にある）も、少し待つか、ため始めたら言う
		_aim_clock += dt
		if attack_lines(d) and not _aim_said and phase == &"aim" and (_aim_keys_held() or charging or _aim_clock >= AIM_LINE_SECONDS):
			_aim_line(d, d.step_serial)
		# 相手が構えた（よける側）「構えたら横へよけて」。CPU のゴーストは PracticeCpu.ghost_charging（cpu_charging）で言う。
		# 人どうしは「…長押しでためる」のすぐあと（_aim_line）。CPU の合図がないときは、ため始めたとき
		var cpu_signal := cpu(d) and d.has_cpu() and d.cpu.has_signal(&"ghost_charging")
		if cpu(d) and dodge_lines(d) and not _brace_said and charging and not cpu_signal:
			_brace_line(d)
		# メーターが光る帯に入った「光る帯で離すと強い」（狙う側。1回だけ。ほかの言葉を言っている間は待つ）
		if attack_lines(d) and _aim_said and not _perfect_said and bool(charge.perfect) and d.saying().is_empty():
			_perfect_said = true
			_charge_said = true
			d.say("c3.ghost.5")

	## 「スペース長押しでためる」（P2 なら「右Ctrl長押しでためる」）。人どうしは、続けてよける側に「構えたら横へよけて」
	func _aim_line(d: PracticeDirector, serial: int) -> void:
		_aim_said = true
		phase = &"play"
		d.hatena.play(&"point")
		await d.say("c3.ghost.4" if ghost == 1 else "c3.ghost.4b")
		if d.is_current(serial) and phase == &"play" and dodge_lines(d) and not cpu(d) and not _brace_said:
			_brace_line(d)

	func _brace_line(d: PracticeDirector) -> void:
		_brace_said = true
		d.hatena.play(&"point")
		d.say("c3.dodge.2")

	func _aim_keys_held() -> bool:
		for key: Key in (AIM_KEYS_P1 if ghost == 1 else AIM_KEYS_P2):
			if Input.is_key_pressed(key):
				return true
		return false

	## 照準の輪が出た：狙う側に「移動キーで狙う」。CPU のゴーストは狙い始める
	func _aim_ready(d: PracticeDirector) -> void:
		if phase != &"intro":
			return
		d.allow_ghost_skip = false
		phase = &"aim"
		_aim_clock = 0.0
		if attack_lines(d):
			d.hatena.play(&"point")
			d.say("c3.ghost.3")
		else:
			phase = &"play"
		if cpu(d) and ghost == 2:
			_cpu_attack(d)

	func _cpu_attack(d: PracticeDirector) -> void:
		_cpu_attacking = true
		d.cpu_call(&"ghost_attack", [1, false])

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"ghost_ready":
				if int(data.player) == ghost:
					_aim_ready(d)
			&"cpu_charging":
				if cpu(d) and ghost == 2 and dodge_lines(d) and not _brace_said and phase in [&"aim", &"play"]:
					_brace_line(d)
			&"ghost_hit":
				if int(data.attacker) == ghost and phase in [&"aim", &"play"]:
					_hit(d, d.step_serial)
			&"ghost_missed":
				if int(data.player) == ghost and phase in [&"aim", &"play"]:
					_missed(d, d.step_serial)
			&"entered_ocean":
				# CPU との 3-7：当たって海まで飛ばされた「海まで飛ばされることもある」
				if int(data.player) == target and phase in [&"aim", &"play", &"talk"]:
					phase = &"fail"
					d.hatena.play(&"oops")
					d.say("c3.dodge.sea")
			&"ocean_bitten":
				if int(data.player) == target and phase != &"done":
					phase = &"fail"
					d.fail_step("c3.any.retry")

	## 突進が当たった：狙う側「当たった」→「アウトでもまだ戦える」、よける側「当たった」（床に残ったら、もう一度）
	func _hit(d: PracticeDirector, serial: int) -> void:
		hits += 1
		phase = &"talk"
		if attack_lines(d) and hits == 1:
			d.hatena.play(&"cheer")
			await d.say("c3.ghost.6")
			if not d.is_current(serial) or phase != &"talk":
				return
			await d.say("c3.ghost.7")
		else:
			d.hatena.play(&"oops")
			await d.say("c3.dodge.hit")
			# 海まで飛ばされたかを少し見る（落ちたら entered_ocean で言い、かまれたらまきもどし）
			await d.wait(0.6)
		if not d.is_current(serial) or phase != &"talk":
			return
		_after(d, serial)

	## 外れた（よけた）：よける側「よけたね」、狙う側「惜しい、もう一回」（本番の待ち時間のあと、もう一度狙える）
	func _missed(d: PracticeDirector, serial: int) -> void:
		dodges += 1
		phase = &"talk"
		if dodge_lines(d) and dodges == 1:
			d.hatena.play(&"clap")
			await d.say("c3.dodge.ok")
			if not d.is_current(serial) or phase != &"talk":
				return
		if attack_lines(d) and not _cleared(d) and (not _miss_said or cpu(d)):
			_miss_said = true
			d.hatena.play(&"wave")
			await d.say("c3.ghost.miss")
			if not d.is_current(serial) or phase != &"talk":
				return
		_after(d, serial)

	## 1回の突進のあと：終わる条件がそろったら次へ。まだなら、もう一度（CPU のゴーストは ghost_attack のまま、待ち時間のあとにまた狙う。
	## よける側には「構えたら横へよけて」をもう一度）
	func _after(d: PracticeDirector, serial: int) -> void:
		if _cleared(d):
			phase = &"done"
			d.cpu_call(&"idle")
			d.complete_step()
			return
		phase = &"play"
		# CPU のゴーストは毎回「構えたら横へよけて」。人どうしは1回だけ（まだ言っていなければ、次の突進の前にここで）
		if cpu(d):
			_brace_said = false
		elif dodge_lines(d) and not _brace_said:
			_brace_line(d)

	## まきもどし（CPU との 3-7 で海に落ちた）：プレイヤーを床の真ん中へ戻す（CPU のゴーストは ghost_attack のまま、また狙う）
	func rewind(d: PracticeDirector) -> void:
		d.set_rules(lesson_rules(d))
		d.revive(target)
		d.place_player(target, TARGET_SPOT.x if target == 2 else -TARGET_SPOT.x, TARGET_SPOT.y)
		phase = &"play"
		_brace_said = false


## 3-8 ゴールと得点（約40秒）：2人とも生き返らせ、ハートは 3-5 が終わったときの数、正解数もそのまま（CPU は 3-3 で1つ減っている）。
## 壁1枚「100 − 36 = ?」（青「64」が正解）→ 本番のゴールレース（MatchRules.finish_with_goal）→ ゴール → スコアタワーの演出と判定。
## ハテナは「最後はゴールまで」のあと、壁が終わったらゴールの審判（本番の旗の審判）の所へ雲で先回りして隠れる（吹き出しは審判に付ける）。
## 演出の段階で「得点の計算を見ておこう」→（式）「正解数 ×（ハート ＋ 0.5）」→「ハートが残るほど有利」→（判定）「アウトの人は正解数だけ」。
## 判定まで見たらクリア。負けても、そのまま進む。2人ともアウトになったら（本番の投げ縄がないとき）まきもどし。
class GoalStep extends WallLesson:
	## CPU の急ぎ（正解のドアへ）
	const CPU_HASTE := 0.5
	## ゴールレースの間、CPU が目指す所（run_forward がないとき。ゴールラインの先、m）
	const CPU_GOAL_PAST := 3.0
	## 判定の知らせが来ないとき、ゴールの演出から先へ進むまでの最長（s）
	const CEREMONY_TIMEOUT := 30.0
	## 本番の審判（ゴールラインの子）の吹き出しの付け根（審判の足もとから上へ、m）
	const REFEREE_BUBBLE_UP := 2.6
	## 本番の旗の審判：ゴールで待つ審判と、スコアタワーの演出の審判（見えている方に吹き出しを付ける）
	const REFEREE_NODES: Array[String] = ["GoalWaitingReferee", "FinaleReferee"]
	## 審判のノードを探し直す間（s。毎フレーム木を探さない）
	const REFEREE_SEARCH_GAP := 0.5

	var _goal_said := false
	var _formula_said := false
	var _verdict_said := false
	var _cpu_running := false
	var _ceremony_clock := 0.0
	## 見つけた審判（名前 → Node3D）と、次に探してよい時刻（ms）
	var _referees := {}
	var _search_after := 0

	func _init() -> void:
		id = "3-8"

	func quiz() -> QuizItem:
		return make_quiz("c3.goal.q", "c3.goal.c", 0)

	func answer() -> int:
		return 0

	func lesson_rules(_d: PracticeDirector) -> MatchRules:
		var rules := base_rules()
		# 本番どおり：ハートが 0 になったらアウト（ゴーストシャークに乗る）
		rules.hp_floor = 0
		rules.ghost_ride_enabled = true
		rules.set(&"finish_with_goal", true)
		return rules

	func enter(d: PracticeDirector) -> void:
		d.close_sign()
		d.set_rules(lesson_rules(d))
		var course := d.course as PracticeCourse
		revive_both(d)
		if bool(course.get(&"saved")):
			var hp: Array = course.get(&"saved_hp")
			var score: Array = course.get(&"saved_score")
			restore_hearts(d, [maxi(int(hp[0]), 1), maxi(int(hp[1]), 1)])
			for index: int in [1, 2]:
				d.set_score(index, int(score[index - 1]))
		else:
			restore_hearts(d, [maxi(d.game_state.get_player_hp(1), 1), maxi(d.game_state.get_player_hp(2), 1)])
		start_hp = hearts(d)
		start_score = [d.player_score(1), d.player_score(2)]
		place_start(d)
		_reset_flags()
		show_hatena(d)
		d.hatena.play(&"point")
		d.say("c3.goal.1")
		drop(d)

	func exit(d: PracticeDirector) -> void:
		d.bubble_point = Callable()
		d.bubble_unanchored = false

	func _reset_flags() -> void:
		_goal_said = false
		_formula_said = false
		_verdict_said = false
		_cpu_running = false
		_ceremony_clock = 0.0

	func rewind(d: PracticeDirector) -> void:
		_reset_flags()
		show_hatena(d)
		super.rewind(d)

	func on_started(d: PracticeDirector) -> void:
		if cpu(d):
			d.cpu_call(&"go_door", [answer(), CPU_HASTE])

	func process(d: PracticeDirector, dt: float) -> void:
		var state := d.game_state.game_state
		if state == Constants.STATE_GOAL_RACE and cpu(d) and not _cpu_running:
			# CPU もゴールへ走る（前へ全力。担当 C の run_forward。ないときは、ゴールの先への move_to）
			_cpu_running = true
			if d.has_cpu() and d.cpu.has_method(&"run_forward"):
				d.cpu_call(&"run_forward", [1.0])
			else:
				var goal := d.game_state.goal_z - d.game_state.world_scroll_z
				d.cpu_call(&"move_to", [d.player_pos(2).x, goal + CPU_GOAL_PAST, 1.0])
		if state == Constants.STATE_RESULT_CEREMONY:
			_ceremony_clock += dt
			if _ceremony_clock >= CEREMONY_TIMEOUT and phase != &"done":
				_finish(d, d.step_serial)

	func on_won(_d: PracticeDirector, _serial: int, _mask: int) -> void:
		phase = &"goal"

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"state_changed":
				match str(data.state):
					Constants.STATE_GOAL_RACE:
						phase = &"goal"
						_to_referee(d, d.step_serial)
					Constants.STATE_RESULT_CEREMONY:
						phase = &"ceremony"
						d.cpu_call(&"idle")
				return
			&"ceremony_phase":
				_ceremony(d, d.step_serial, int(data.phase))
				return
			&"ceremony_finished":
				if phase != &"done":
					_verdict(d, d.step_serial)
				return
			&"round_lost":
				# 2人ともアウト（本番の投げ縄がないとき）：まきもどし
				if phase in [&"wait", &"play", &"goal"]:
					fail(d, d.step_serial, "")
				return
			&"quizzes_finished":
				# 本編側に finish_with_goal がないとき（ゴールレースにならない）：言葉だけで先へ
				if phase in [&"play", &"talk", &"goal"] and not (&"finish_with_goal" in d.rules):
					_finish(d, d.step_serial)
				return
		super.on_event(d, event, data)

	## 壁が終わった：ハテナが雲でゴールの審判の所へ先回りして隠れ、吹き出しは審判に付く（審判がいないときは画面の上）
	func _to_referee(d: PracticeDirector, serial: int) -> void:
		var referee := _referee(d)
		if referee != null and d.hatena.visible:
			var spot := d.world.to_local(referee.global_position)
			spot.y = PracticeDirector.HATENA_CLOUD_Y
			spot.x += 1.6
			await fly_hatena(d, spot)
			if not d.is_current(serial):
				return
		d.hatena.set_cloud(false)
		d.hatena.visible = false
		d.hatena_follow = false
		# 吹き出しは、見えている審判の頭の上（どちらも見えないときは画面の上）
		d.bubble_point = func() -> Vector3:
			var node := _referee(d)
			if node == null:
				return Vector3(NAN, NAN, NAN)
			return node.global_position + Vector3.UP * REFEREE_BUBBLE_UP

	## 見えている本番の審判（ゴールで待つ審判 → 演出の審判の順）。いなければ null。
	func _referee(d: PracticeDirector) -> Node3D:
		if d.world == null:
			return null
		var search := Time.get_ticks_msec() >= _search_after
		if search:
			_search_after = Time.get_ticks_msec() + int(REFEREE_SEARCH_GAP * 1000.0)
		for node_name: String in REFEREE_NODES:
			var node: Variant = _referees.get(node_name, null)
			if not is_instance_valid(node) and search:
				node = d.world.find_child(node_name, true, false)
				_referees[node_name] = node
			if is_instance_valid(node) and (node as Node3D).is_visible_in_tree():
				return node as Node3D
		return null

	## スコアタワーの演出：2人がタワーへ歩く「得点の計算を見ておこう」→ 式「正解数 ×（ハート ＋ 0.5）」→「ハートが残るほど有利」
	## → 判定「アウトの人は正解数だけ」
	func _ceremony(d: PracticeDirector, serial: int, stage: int) -> void:
		var steps := QuizGameState.ResultCeremonyPhase
		if stage in [steps.ASSEMBLE, steps.WALK] and not _goal_said:
			_goal_said = true
			d.say("c3.goal.2")
		elif stage == steps.SCORE_ROLL and not _formula_said:
			_formula_said = true
			await d.say("c3.goal.3")
			if d.is_current(serial) and phase != &"done":
				d.say("c3.goal.4")
		elif stage in [steps.VERDICT, steps.EFFECT, steps.WINNER] and not _verdict_said and not d.has_practice_signal(&"practice_ceremony_finished"):
			_verdict(d, serial)

	## 判定が出た「アウトの人は正解数だけ」（2人ともアウトでゴールへ運ばれたときは「2人ともアウトでもゴールへ運ぶ」も）→ 次へ
	func _verdict(d: PracticeDirector, serial: int) -> void:
		if _verdict_said:
			return
		_verdict_said = true
		if not _formula_said:
			_formula_said = true
			await d.say("c3.goal.3")
			if not d.is_current(serial):
				return
		await d.say("c3.goal.5")
		if not d.is_current(serial):
			return
		if not d.game_state.p1_alive and not d.game_state.p2_alive:
			await d.say("c3.goal.lasso")
			if not d.is_current(serial):
				return
		_finish(d, serial)

	func _finish(d: PracticeDirector, serial: int) -> void:
		if phase == &"done" or not d.is_current(serial):
			return
		phase = &"done"
		d.complete_step()


## 3-9 サドンデス（使えるときだけ。約5秒）：判定のあとに「同点ならサドンデス」→「設定でオフにもできる」と言うだけ。
class SuddenDeathStep extends Course3Step:
	func _init() -> void:
		id = "3-9"

	func enter(d: PracticeDirector) -> void:
		if not QuizGameState.sudden_death_available:
			d.complete_step()
			return
		_run(d, d.step_serial)

	func _run(d: PracticeDirector, serial: int) -> void:
		await d.say("c3.sd.1")
		if not d.is_current(serial):
			return
		await d.say("c3.sd.2")
		if d.is_current(serial):
			d.complete_step()
