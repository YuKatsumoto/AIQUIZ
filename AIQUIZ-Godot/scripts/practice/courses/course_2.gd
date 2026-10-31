extends PracticeCourse

## コース② 本番の流れ（台本 docs/new_tutorial/course2_script.md v0.2、段階5の設計 docs/new_tutorial/phase5_design.md 6章）。
## 2-1 ジャンプ → 2-2 エモート → 2-3 一時停止 → 2-4 ミニ本番 → 2-5 リザルト
## → メインメニューの 2-6 メニュー とクリア（担当 D のメニューのコーチ。監督の continue_in_menu で渡す）。
## ゲーム画面ではクリアカードもスタンプも出さない（メニューの上のクリアで出す）。
## 座標はゲーム画面のもの：x は +が画面の左、z はコンベア上の前。2-1 の始めにプレイヤーを x 0、z 0 に置く。
## ハテナの段階5の動き（おどりつづける。担当 C）は、ないときは今ある動きで代わりにする。
## ポーズ画面（2-3）とリザルトのカード（2-4 の負け・2-5）の上では、画面のコーチ（担当 D）が本物の部品（担当 A）を光らせる。

## 見えないさく（台本②の 2-1。①と同じ：左右 x ±10、前 z +8、うしろ z −6）。2-4 では外す
const FENCE_X := 10.0
const FENCE_BACK := -6.0
const FENCE_FRONT := 8.0
## 2-4 の壁の数と、ボス壁の番号（3枚目）
const RUN_TOTAL := 3
const RUN_BOSS := 2
## 本物のリザルトのカードが出るまで待つ長さ（ms。1人の GAME OVER は体が崩れてから約4秒。CLEAR は花火のあと）
const CARD_TIMEOUT_MS := 10000


func _init() -> void:
	id = "c2"
	lesson_ids = ["2-1", "2-2", "2-3", "2-4", "2-5", "2-6"]


func build_steps() -> Array[PracticeStep]:
	var list: Array[PracticeStep] = [JumpStep.new(), EmoteStep.new(), PauseStep.new(), RunStep.new(), ResultStep.new()]
	return list


## コース②のレッスンの土台：ルールの決まりごとと、ハテナ・看板のよく使う道具。
class Course2Step extends PracticeStep:
	## 2-1〜2-3 のもと：コンベアは止める、ハートなし、ミスは通知だけ、海はかまれても通知だけ、記録しない、見えないさく。
	func stage_rules() -> MatchRules:
		var rules := MatchRules.new()
		rules.world_speed = 0.0
		rules.mistakes = MatchRules.Mistakes.REPORT_ONLY
		rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
		rules.record_results = false
		rules.fence_enabled = true
		rules.fence_min = Vector2(-FENCE_X, FENCE_BACK)
		rules.fence_max = Vector2(FENCE_X, FENCE_FRONT)
		return rules

	## 看板の壁を出しておく（2-1 をスキップしたときなど、まだなければ落とす）。出ていれば文字とパネルを変える。
	func show_sign(d: PracticeDirector, title_id: String, panels: Array) -> void:
		if d.sign_wall == null:
			d.open_sign(PracticeTexts.get_parts(title_id), panels)
		else:
			d.set_sign(PracticeTexts.get_parts(title_id), panels)

	## おどりをくり返す（担当 C の set_dancing。ないときは客席のハテナのおどりを1回）。
	func set_dancing(d: PracticeDirector, on: bool) -> void:
		if d.hatena.has_method(&"set_dancing"):
			d.hatena_call(&"set_dancing", [on])
		elif on:
			d.hatena.play(&"dance")

	## リザルトのカードの『メニュー』：ゲーム画面のまだ済んでいないレッスンはスキップしたことにして、メニューの 2-6 へ。
	func on_leave_to_menu(d: PracticeDirector) -> bool:
		d.coach_end()
		d.skipped_steps += maxi(d.steps.size() - d.step_index, 0)
		d.continue_in_menu("2-6")
		return true


## 2-1 ジャンプ（約12秒）：コンベアは止め、見えないさく。看板の壁「スペースでジャンプ」（スペースのキーと的の絵）。
## プレイヤーの3m前、立ったままでは届かずジャンプで届く高さに、光る的が浮かぶ。空中で的の真下（横に 1.0m 以内）を
## 通るとタッチ（1回でよい）。6秒スペースが押されなければ、看板のスペースが点滅して「スペースキーでジャンプ」。
class JumpStep extends Course2Step:
	## 的の所（プレイヤーの始めの位置 x 0、z 0 から）。高さは的の真ん中（床から、m。立ったプレイヤーの帽子の上が約 2.3m、
	## 本番のジャンプは頂点で +1.36m）。正面だと看板の文字に重なるので、画面の右へずらす（右のパネルは的の絵）
	const TARGET_SPOT := Vector3(-2.6, 2.9, 3.0)
	## 的の大きさ（舞台の小物の的のマークは、壁に付ける大きさ。半径 1.25m → 約 0.45m）
	const TARGET_SCALE := 0.36
	## タッチ：プレイヤーの足がこの高さより上（空中）で、的から横にこの距離（m）以内
	const AIR_MIN := 0.25
	const REACH := 1.0
	const IDLE_HINT_SECONDS := 6.0
	## 的がふわふわ上下する幅（m）と速さ
	const BOB := 0.08
	const BOB_SPEED := 1.6

	## &"intro"・&"wait"（タッチを待つ）・&"done"
	var phase := &"intro"
	var _since_jump := 0.0
	var _clock := 0.0
	var _target: Node3D = null

	func _init() -> void:
		id = "2-1"

	func enter(d: PracticeDirector) -> void:
		d.place_player(1, 0.0, 0.0)
		d.set_rules(stage_rules())
		phase = &"intro"
		_since_jump = 0.0
		_clock = 0.0
		show_sign(d, "c2.jump.sign", [
			{"key": &"space", "picture": &"space"},
			{"key": &"target", "glyph": "◎"},
		])
		d.hatena.set_cloud(false)
		d.follow_walls()
		_intro(d, d.step_serial)

	func exit(_d: PracticeDirector) -> void:
		_drop_target()

	## 開始：「次はジャンプ」と的が浮かぶ。1.5秒後に「浮いている的にタッチしよう」。
	## メニューから来た画面の切り替え（ワイプ）が開き終わってから始める。
	func _intro(d: PracticeDirector, serial: int) -> void:
		if not await d.until(func() -> bool: return not SceneTransition.is_transitioning(), serial):
			return
		_make_target(d)
		d.hatena.play(&"wave")
		d.say("c2.jump.1")
		await d.wait(1.5)
		if not d.is_current(serial):
			return
		d.hatena.play(&"point")
		d.say("c2.jump.2")
		phase = &"wait"
		_since_jump = 0.0

	## 的（舞台の小物の的のマークを小さくして浮かべる。プレイヤーのほうを向いている）
	func _make_target(d: PracticeDirector) -> void:
		_drop_target()
		_target = d.make_target_mark()
		if _target == null:
			return
		_target.name = "PracticeJumpTarget"
		_target.scale = Vector3.ONE * TARGET_SCALE
		d.world.add_child(_target)
		_target.position = TARGET_SPOT

	func _drop_target() -> void:
		if is_instance_valid(_target):
			_target.queue_free()
		_target = null

	func process(d: PracticeDirector, dt: float) -> void:
		if is_instance_valid(_target) and phase != &"done":
			_clock += dt
			_target.position.y = TARGET_SPOT.y + sin(_clock * TAU / BOB_SPEED) * BOB
		if phase != &"wait":
			return
		_since_jump += dt
		if _since_jump >= IDLE_HINT_SECONDS:
			_since_jump = 0.0
			d.say("c2.jump.idle")
			if d.sign_wall != null and d.sign_wall.has_method(&"blink_panel"):
				d.sign_call(&"blink_panel", [&"space"])
			else:
				d.blink_sign()
		if _touching(d):
			_touched(d, d.step_serial)

	func on_event(_d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if event == &"jumped" and int(data.player) == 1:
			_since_jump = 0.0

	## 的の真ん中（ゲーム画面の座標。テストで使う）
	func target_point() -> Vector3:
		return TARGET_SPOT

	## プレイヤーが空中にいて、的の真下（横に REACH 以内）にいる。
	func _touching(d: PracticeDirector) -> bool:
		if not d.game_state.p1_alive or d.game_state.player_y < AIR_MIN:
			return false
		var player := d.player_point(1)
		return Vector2(player.x - TARGET_SPOT.x, player.z - TARGET_SPOT.z).length() <= REACH

	## タッチ：的が光ってはじける（ピコン）、スペースのパネルに ✓ →「OK」→ 2-2。
	func _touched(d: PracticeDirector, serial: int) -> void:
		phase = &"done"
		d.play_pico()
		AudioManager.play_sfx(&"door_correct")
		d.tick_sign(&"space")
		d.tick_sign(&"target")
		if is_instance_valid(_target):
			var target := _target
			_target = null
			var tween := target.create_tween()
			tween.tween_property(target, "scale", Vector3.ONE * TARGET_SCALE * 1.6, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(target.queue_free)
		d.hatena.play(&"clap")
		await d.say("c2.jump.ok")
		if d.is_current(serial):
			d.complete_step()


## 2-2 エモート（約8秒）：看板「1・2・3でエモート」（1・2・3 のキーとおどるハテナの絵）。
## 1・2・3 のどれかでエモートを1回出すと、そのキーに ✓ →「いいね」→「種類はカスタマイズで変えられる」→ 2-3。
## 6秒なにも押さなければ「数字の1・2・3キーだよ」。
class EmoteStep extends Course2Step:
	const IDLE_HINT_SECONDS := 6.0
	const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]

	## &"play"・&"done"
	var phase := &"play"

	func _init() -> void:
		id = "2-2"

	func enter(d: PracticeDirector) -> void:
		d.set_rules(stage_rules())
		phase = &"play"
		show_sign(d, "c2.emote.sign", [
			{"key": &"digits", "keys": ["1", "2", "3"]},
			{"key": &"hatena_dance", "picture": &"hatena_dance"},
		])
		d.hatena.set_cloud(false)
		d.follow_walls()
		d.idle_seconds = 0.0
		d.hatena.play(&"point")
		d.say("c2.emote.1")

	func process(d: PracticeDirector, _dt: float) -> void:
		if phase == &"play" and d.idle_seconds >= IDLE_HINT_SECONDS:
			d.idle_seconds = 0.0
			d.hatena.play(&"point")
			d.say("c2.emote.idle")

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if event != &"emoted" or int(data.player) != 1 or phase != &"play":
			return
		phase = &"done"
		var slot := _slot(d, int(data.emote))
		d.play_pico()
		if slot >= 0 and d.sign_wall != null and d.sign_wall.has_method(&"tick_panel_key"):
			d.sign_call(&"tick_panel_key", [&"digits", slot])
		else:
			d.tick_sign(&"digits")
		d.tick_sign(&"hatena_dance")
		_finish(d, d.step_serial)

	## エモートを出したキー（0 = 1、1 = 2、2 = 3）。押しているキーで決め、分からなければエモートの枠から探す。
	func _slot(d: PracticeDirector, emote: int) -> int:
		for i in range(DIGIT_KEYS.size()):
			if Input.is_key_pressed(DIGIT_KEYS[i]):
				return i
		return d.game_state.p1_emote_slots.find(emote)

	func _finish(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"clap")
		await d.say("c2.emote.2")
		if not d.is_current(serial):
			return
		d.hatena.play(&"point")
		await d.say("c2.emote.3")
		if d.is_current(serial):
			d.complete_step()


## 2-3 一時停止（約18秒）：看板「Escで一時停止」（Esc のキーと「II」）。ハテナは看板の前で体をゆらしつづける（止まったことが分かるように）。
## Esc で本番と同じポーズ画面 → ハテナが止まる → 画面のコーチ（担当 D）が、BGM と効果音のスライダー・『タイトルに戻る』
## （見せるだけ）・『ゲームに戻る』（押すまで待つ）を順に光らせる。『ゲームに戻る』（Esc でもよい）で戻ると「OK」✓。
## コーチのとちゅうでポーズ画面を閉じたら、このレッスンをスキップしたことにする（台本②の 1.2）。8秒 Esc なしで「Escはキーボードの左上」。
class PauseStep extends Course2Step:
	const IDLE_HINT_SECONDS := 8.0

	## &"wait"（Esc を待つ）・&"coach"（ポーズ画面の上の説明）・&"resume"（『ゲームに戻る』を待つ）・&"back"・&"done"
	var phase := &"wait"
	var _idle := 0.0

	func _init() -> void:
		id = "2-3"

	func enter(d: PracticeDirector) -> void:
		d.set_rules(stage_rules())
		phase = &"wait"
		_idle = 0.0
		show_sign(d, "c2.pause.sign", [
			{"key": &"esc", "glyph": "Esc"},
			{"key": &"pause", "picture": &"pause"},
		])
		d.hatena.set_cloud(false)
		d.follow_walls()
		set_dancing(d, true)
		d.say("c2.pause.1")

	func exit(d: PracticeDirector) -> void:
		set_dancing(d, false)

	func process(d: PracticeDirector, dt: float) -> void:
		if phase != &"wait":
			return
		_idle += dt
		if _idle >= IDLE_HINT_SECONDS:
			_idle = 0.0
			d.blink_sign()
			d.say("c2.pause.idle")

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"pause_changed":
				if bool(data.paused) and phase == &"wait":
					_paused(d, d.step_serial)
				elif not bool(data.paused) and phase in [&"coach", &"resume"]:
					_resumed(d, d.step_serial)
			&"coach_exit":
				if phase in [&"coach", &"resume"]:
					d.resume_from_pause()
					if not d.get_tree().paused:
						_resumed(d, d.step_serial)

	## ポーズ画面が出た：ハテナの小窓が右下から「これがポーズ画面」→ スライダー → 『タイトルに戻る』→『ゲームに戻る』
	func _paused(d: PracticeDirector, serial: int) -> void:
		phase = &"coach"
		d.coach_begin(true)
		d.coach_play(&"wave")
		await d.say("c2.pause.2")
		if not _coaching(d, serial):
			return
		d.coach_focus([&"pause_bgm", &"pause_sfx"], true)
		d.coach_play(&"point")
		await d.say("c2.pause.3")
		if not _coaching(d, serial):
			return
		d.coach_focus([&"pause_title"], false)
		await d.say("c2.pause.4")
		if not _coaching(d, serial):
			return
		phase = &"resume"
		d.coach_focus([&"pause_resume"], true)
		d.say("c2.pause.5", true)

	func _coaching(d: PracticeDirector, serial: int) -> bool:
		return d.is_current(serial) and phase == &"coach" and d.get_tree().paused

	## ポーズ画面が閉じた：『ゲームに戻る』を待っていたら「OK」✓ → 2-4。とちゅうなら、スキップしたことにする。
	func _resumed(d: PracticeDirector, serial: int) -> void:
		if phase not in [&"coach", &"resume"]:
			return
		var ok := phase == &"resume"
		phase = &"back"
		d.coach_end()
		if not ok:
			d.skip_step()
			return
		# ハテナは止まっていたおどりから動き出す（ポーズが解けると、そのまま続く）
		d.tick_sign(&"esc")
		d.tick_sign(&"pause")
		await d.say("c2.pause.6")
		if d.is_current(serial):
			phase = &"done"
			d.complete_step()


## 2-4 ミニ本番（約60秒）：本番どおり（ハート3つ・0でアウト、海に落ちたらアウト、本番の自動の速さ、右上の「正解・問題」）。
## 看板の壁が空へ戻り、3枚の壁が本番と同じく空から落ちる → 開始の画面（Enter）→ 空撮 → カウントダウン（5秒）→ 3枚（3枚目はボス）。
## ハテナはいまの壁の前に立ち、続けて正解した数を数える。ボス壁を突破すると本番の CLEAR（花火・紙吹雪・カード）→ 2-5。
## 開始の画面と空撮の間は、いまの壁がカウントダウンの壁のうしろで見えないので、ハテナは隠して吹き出しを画面の上に出す。
## カウントダウンでプレイヤーの左前に出てきて「カウントダウンのあと開始」、スタートでいまの壁の前へ跳ぶ。
## 負けたら本番の GAME OVER（約4秒後にカード）→「残念」→ コーチが『リトライ』だけ光らせる → 押すと開始の画面から。
## 3回失敗で、自動の速さの調子を一番遅い値に（MatchRules.slow_auto_speed）。ハートが減らずにクリアしたら★。
class RunStep extends Course2Step:
	## 壁がそろう（開始の画面で Enter を押せるようになる）のを待つ長さ（ms）
	const READY_TIMEOUT_MS := 6000
	## 本編側に本物の結果の画面がないとき：負けてから話すまで（①の しあげと同じ）
	const LOST_PAUSE := 1.2
	## カウントダウンの間にハテナが立つ所（プレイヤーから。x は +が画面の左）
	const COUNT_SPOT := Vector3(4.5, 0.0, 4.0)
	## 壁1 を突破してから「右上は正解数と何問目か」まで（s）
	const HUD_LINE_DELAY := 1.0

	## &"ready"（開始の画面）・&"flyover"・&"count"・&"play"・&"lost"・&"done"
	var phase := &"ready"
	var streak := 0
	var lost_heart := false
	var boss_said := false

	func _init() -> void:
		id = "2-4"

	func quizzes() -> Array[QuizItem]:
		var list: Array[QuizItem] = [
			make_quiz("c2.run.q1", "c2.run.c1", 1, "c2.run.e1"),
			make_quiz("c2.run.q2", "c2.run.c2", 0, "c2.run.e2"),
			make_quiz("c2.run.q3", "c2.run.c3", 2, "c2.run.e3"),
		]
		return list

	## 台本の問題（3章）。question_id の「／」は2行にし、choices_id はドアの番号の順に「／」で区切った文字。
	## explain_id は解説（本物のリザルトのカードと問題履歴に出る）。
	static func make_quiz(question_id: String, choices_id: String, answer: int, explain_id := "") -> QuizItem:
		var explain := PracticeTexts.get_text(explain_id) if not explain_id.is_empty() else ""
		var item := QuizItem.create(PracticeTexts.get_text(question_id).replace("／", "
"), PracticeTexts.get_parts(choices_id), answer, explain)
		item.src = "PRACTICE"
		return item

	## 本番どおりのルール。結果は記録しない。本編側（担当 A）の段階5の切り替え（finish_with_clear・real_result_screens）は、
	## まだないときは何もしない（set は知らない名前を無視する）。
	func run_rules(d: PracticeDirector) -> MatchRules:
		var rules := MatchRules.new()
		rules.hp_enabled = true
		rules.mistakes = MatchRules.Mistakes.NORMAL
		rules.ocean = MatchRules.Ocean.NORMAL
		rules.world_speed = -1.0
		rules.record_results = false
		rules.show_score = true
		rules.set(&"finish_with_clear", true)
		rules.set(&"real_result_screens", true)
		rules.set(&"slow_auto_speed", d.slow_hint_active())
		return rules

	func enter(d: PracticeDirector) -> void:
		set_dancing(d, false)
		d.hatena.set_cloud(false)
		d.hatena.play(&"cheer")
		d.say("c2.run.1")
		d.close_sign()
		_start_run(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		d.bubble_unanchored = false

	## ミニ本番の回を始める（やり直しも）：本番と同じ開始の画面（壁は空から落ちる）。壁がそろったら「本番はEnterでスタート」。
	func _start_run(d: PracticeDirector, serial: int) -> void:
		phase = &"ready"
		streak = 0
		lost_heart = false
		boss_said = false
		var bosses: Array[int] = [RUN_BOSS]
		d.restart_round(quizzes(), run_rules(d), bosses, Constants.STATE_WAITING_START)
		# 開始の画面と空撮の間は、ハテナを隠して吹き出しを画面の上に出す
		d.hatena_follow = false
		d.hatena.visible = false
		d.bubble_unanchored = true
		var deadline := Time.get_ticks_msec() + READY_TIMEOUT_MS
		var ready := await d.until(func() -> bool:
			return Time.get_ticks_msec() >= deadline or _can_start(d), serial)
		if ready and phase == &"ready":
			d.hatena.play(&"point")
			d.say("c2.run.2")

	## 開始の画面で Enter を押せる（ゲーム画面の開始の条件。もう始まっていても true）。
	func _can_start(d: PracticeDirector) -> bool:
		if d.game_state.game_state != Constants.STATE_WAITING_START:
			return true
		if d.world != null and d.world.has_method(&"practice_start_ready"):
			return bool(d.world.call(&"practice_start_ready"))
		return false

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"state_changed":
				_state_changed(d, str(data.state))
			&"health_changed":
				if int(data.player) == 1 and int(data.hp) < int(data.previous) and phase == &"play":
					lost_heart = true
			&"question_completed":
				if phase == &"play":
					_passed(d, d.step_serial, int(data.wall_index), bool(data.correct))
			&"round_lost":
				if phase in [&"count", &"play"]:
					_lost(d, d.step_serial)
			&"quizzes_finished":
				# 本編側に finish_with_clear がないとき（CLEAR にならず、問題を使い切った知らせが来る）の代わり
				if phase in [&"play", &"done"]:
					phase = &"done"
					d.star_earned = not lost_heart
					d.complete_step()
			&"coach_exit":
				# 負けのカードの上でコーチを抜けた：このレッスンをスキップしたことにする（台本②の 1.2）
				if phase == &"lost":
					d.coach_end()
					d.skip_step()

	func _state_changed(d: PracticeDirector, state: String) -> void:
		match state:
			Constants.STATE_FLYOVER:
				if phase == &"ready":
					phase = &"flyover"
			Constants.STATE_COUNTDOWN:
				if phase in [&"ready", &"flyover"]:
					# 空撮が終わる：ハテナがプレイヤーの左前に出てきて「カウントダウンのあと開始」
					phase = &"count"
					var spot := d.player_point(1) + COUNT_SPOT
					spot.y = 0.0
					d.hatena.place_at(spot)
					d.hatena.face_toward(d.player_point(1))
					d.hatena.play(&"wave")
					d.bubble_unanchored = false
					d.say("c2.run.3")
			Constants.STATE_PLAYING:
				if phase in [&"ready", &"flyover", &"count"]:
					# スタート：ハテナはいまの壁の前へ跳ぶ（①と同じ）
					phase = &"play"
					d.bubble_unanchored = false
					d.follow_walls()
			Constants.STATE_GAME_OVER:
				# 本編側に practice_round_lost がないときの代わり
				if not d.has_round_lost_signal() and phase == &"play":
					_lost(d, d.step_serial)

	## 壁を突破した（ハートが残っていれば、正解でもミスでも）。続けて正解した数をハテナが数える。
	func _passed(d: PracticeDirector, serial: int, wall_index: int, correct: bool) -> void:
		streak = streak + 1 if correct else 0
		if wall_index >= RUN_BOSS:
			# ボス壁を突破：本番の CLEAR の演出（本編）→ 2-5。3問とも正解なら「3問連続。パーフェクト」
			phase = &"done"
			d.star_earned = not lost_heart
			if streak >= RUN_TOTAL:
				d.hatena.play(&"cheer")
				await d.say("c2.run.streak3")
				if not d.is_current(serial):
					return
			await d.until(func() -> bool: return d.game_state.game_state != Constants.STATE_PLAYING, serial)
			if d.is_current(serial) and d.game_state.game_state == Constants.STATE_CLEAR:
				d.complete_step()
			return
		var line := ""
		if wall_index == 0:
			line = "c2.run.streak1" if correct else "c2.run.miss"
		elif streak >= 2:
			line = "c2.run.streak2"
		else:
			line = "c2.run.ok" if correct else "c2.run.miss"
		d.hatena.play(&"clap" if correct else &"wave")
		var said := d.say(line)
		if wall_index == 0:
			# その1秒後：右上を指して「右上は正解数と何問目か」
			await d.wait(HUD_LINE_DELAY)
			if not d.is_current(serial) or phase != &"play":
				return
			d.hatena.play(&"point")
			said = d.say("c2.run.hud")
		await said
		if not d.is_current(serial) or phase != &"play":
			return
		# ボス壁が、いまの壁になった
		if not boss_said and d.game_state.current_wall_index == RUN_BOSS:
			boss_said = true
			d.hatena.play(&"point")
			d.say("c2.run.boss")

	## 負けた：本番の GAME OVER のカードが出たら「残念」→ コーチが『リトライ』だけ光らせて「『リトライ』でもう一回」。
	## 押すまで待つ（本編側が retry_run を呼ぶ → on_retry）。本編側に本物の結果の画面がないときは、言葉のあとにやり直す。
	func _lost(d: PracticeDirector, serial: int) -> void:
		phase = &"lost"
		d.count_failure()
		if d.has_result_screens():
			var deadline := Time.get_ticks_msec() + CARD_TIMEOUT_MS
			await d.until(func() -> bool: return d.result_card_visible() or Time.get_ticks_msec() >= deadline, serial)
			if not d.is_current(serial) or phase != &"lost":
				return
			d.coach_begin(true)
			d.coach_play(&"wave")
			await d.say("c2.run.fail")
			if not d.is_current(serial) or phase != &"lost":
				return
			d.coach_focus([&"result_retry"], true)
			d.coach_play(&"point")
			d.say("c2.run.retry", true)
			return
		await d.wait(LOST_PAUSE)
		if not d.is_current(serial):
			return
		await d.say("c2.run.fail")
		if not d.is_current(serial):
			return
		await d.say("c2.run.retry")
		if d.is_current(serial) and phase == &"lost":
			_retry(d)

	## 『リトライ』：開始の画面から（ハート3つ）
	func on_retry(d: PracticeDirector) -> void:
		if phase == &"lost":
			_retry(d)

	func _retry(d: PracticeDirector) -> void:
		d.coach_end()
		d.step_serial += 1
		_start_run(d, d.step_serial)


## 2-5 リザルト（約35秒）：本番の CLEAR のカード（1人の形）の上で、コーチ（担当 D）が順に光らせる。
## 大きな数字 → 3つの小さなカード → 解説 → 評価（押すまで待つ。練習なので送らない）→ 問題履歴（押すまで待つ）→『◀ 戻る』
## （押すまで待つ）→『リトライ』（見せるだけ）→『メニュー』（押すまで待つ）。『メニュー』でメインメニューの 2-6 へ。
## ミニ本番をスキップしたなど、CLEAR のカードがないときは、このレッスンもスキップしてメニューへ。Esc でコーチを抜けても、スキップしてメニューへ。
class ResultStep extends Course2Step:
	## &"card"（カードを待つ）・&"tour"（説明）・&"rate"・&"history"・&"back"・&"menu"（『メニュー』を待つ）・&"done"
	var phase := &"card"
	var _rated := false
	var _history_opened := false
	var _history_closed := false

	func _init() -> void:
		id = "2-5"

	func enter(d: PracticeDirector) -> void:
		d.hatena_follow = false
		phase = &"card"
		_rated = false
		_history_opened = false
		_history_closed = false
		if d.game_state.game_state != Constants.STATE_CLEAR:
			_skip(d)
			return
		_tour(d, d.step_serial)

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"result_action":
				match StringName(data.action):
					&"rated":
						_rated = true
					&"history_opened":
						_history_opened = true
					&"history_closed":
						_history_closed = true
			&"coach_exit":
				if phase != &"done":
					_skip(d)

	func _going(d: PracticeDirector, serial: int) -> bool:
		return d.is_current(serial) and phase != &"done"

	## 押すまで待つ（ゲーム画面にリザルトの出来事の signal がないときは待たない）。
	func _await_flag(d: PracticeDirector, serial: int, flag: StringName) -> bool:
		if not d.has_result_actions():
			return _going(d, serial)
		await d.until(func() -> bool: return bool(get(flag)) or phase == &"done", serial)
		return _going(d, serial)

	func _tour(d: PracticeDirector, serial: int) -> void:
		var deadline := Time.get_ticks_msec() + CARD_TIMEOUT_MS
		await d.until(func() -> bool: return d.result_card_visible() or Time.get_ticks_msec() >= deadline, serial)
		if not _going(d, serial):
			return
		phase = &"tour"
		# カードが出る「これが結果の画面」（ハテナは画面の右下の小窓に雲で浮かぶ）
		d.coach_begin(true)
		d.coach_play(&"cheer")
		await d.say("c2.result.1")
		if not _going(d, serial):
			return
		for entry: Array in [[&"result_score", "c2.result.2"], [&"result_stats", "c2.result.3"], [&"result_explain", "c2.result.4"]]:
			# 解説の文がない問題（台本の問題には解説がない）は、カードに解説の欄が出ないので、その言葉はとばす
			if entry[0] == &"result_explain" and d.has_result_screens() and d.coach_target(&"result_explain") == null:
				continue
			d.coach_focus([entry[0]], false)
			d.coach_play(&"point")
			await d.say(entry[1])
			if not _going(d, serial):
				return
		# 「問題の良し悪しを評価できる」→ 押すまで待つ
		phase = &"rate"
		d.coach_focus([&"result_rate"], true)
		d.say("c2.result.5", true)
		if not await _await_flag(d, serial, &"_rated"):
			return
		# 「ありがとう」→「評価はAIの問題づくりに役立つ」（評価の反応は本番どおり。練習なので送らない）
		phase = &"tour"
		d.coach_focus([&"result_rate"], false)
		d.coach_play(&"clap")
		await d.say("c2.result.6")
		if not _going(d, serial):
			return
		await d.say("c2.result.7")
		if not _going(d, serial):
			return
		# 「全問の振り返りはここ」→ 押すまで待つ
		phase = &"history"
		d.coach_focus([&"result_history"], true)
		d.coach_play(&"point")
		d.say("c2.result.8", true)
		if not await _await_flag(d, serial, &"_history_opened"):
			return
		# 問題履歴が開く「解説も読める」→「見終わったら『◀ 戻る』」→ 押すまで待つ
		phase = &"back"
		d.coach_focus([&"history_back"], true)
		await d.say("c2.result.9")
		if not _going(d, serial):
			return
		if not _history_closed:
			d.say("c2.result.10", true)
			if not await _await_flag(d, serial, &"_history_closed"):
				return
		# 戻る「『リトライ』でもう一度遊べる」（見せるだけ）→「『メニュー』へ進もう」→ 押すまで待つ（on_leave_to_menu）
		phase = &"tour"
		d.coach_focus([&"result_retry"], false)
		await d.say("c2.result.11")
		if not _going(d, serial):
			return
		phase = &"menu"
		d.coach_focus([&"result_menu"], true)
		d.coach_play(&"wave")
		d.say("c2.result.12", true)

	## 『メニュー』：メインメニューの 2-6 へ（案内のとちゅうなら、このレッスンはスキップしたことにする）。
	func on_leave_to_menu(d: PracticeDirector) -> bool:
		if phase == &"done":
			return true
		var toured := phase == &"menu"
		phase = &"done"
		d.coach_end()
		if not toured:
			d.skipped_steps += 1
		d.continue_in_menu("2-6")
		return true

	## 『リトライ』（ふだんは見せるだけで押せない）：ミニ本番をもう一度
	func on_retry(d: PracticeDirector) -> void:
		if phase == &"done":
			return
		phase = &"done"
		d.restart_from("2-4")

	func _skip(d: PracticeDirector) -> void:
		phase = &"done"
		d.coach_end()
		d.skipped_steps += 1
		d.continue_in_menu("2-6")
