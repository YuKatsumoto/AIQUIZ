extends PracticeCourse

## コース④ オンライン対戦（台本 docs/new_tutorial/course4_script.md v0.2、段階7の設計 docs/new_tutorial/phase7_design.md 1.2・1.3）。
## 4-1〜4-5、4-6 の始め（『ランダムマッチ』→ 本番のマッチングの演出 → VS カットイン）とクリアは、オンラインの画面の上の案内
## （scripts/practice/menu/practice_online_guide.gd）。このスクリプトは、ゲーム画面の 4-6 の練習試合だけを持つ。
## 練習試合はオンラインと同じ見せ方（game_state.practice_online_look。オンラインの画面が入れてから移ってくる）で、
## 相手は CPU（P2。監督の setup_cpu）、壁2枚・本番の自動の速さ・本番の2人のルール（のこぎり・押し合い・ゴースト）。
## 試合が終わって『オンラインメニューへ』を押したら、PracticeSession.resume_in_menu = {"course": "c4", "step": "clear", …} を
## 入れてオンラインの画面へ戻る（画面が練習の形で開いてクリアを始める）。

## ゲーム画面の 4-6 で、レッスンの並び（上の進み具合の点）のうち、いまのもの
const MATCH_STEP_ID := "4-6"


func _init() -> void:
	id = "c4"
	lesson_ids = ["4-1", "4-2", "4-3", "4-4", "4-5", "4-6"]


func build_steps() -> Array[PracticeStep]:
	var list: Array[PracticeStep] = [MatchStep.new()]
	return list


## 4-6 練習試合（ゲーム画面の分。約50秒）：ステージに着く「試合前はエモートであいさつできる」→「ルールは2人対戦と同じ」と
## 本番の始まり方（空撮 → カウントダウン → スタート）。壁1「13 + 29 = ?」（青「42」が正解）が終わったら
## 「オンラインでは一時停止できない」→「Escを押してみて」→ Esc で本番の「たいせんを やめますか？」（ゲームは止まらない）→
## 「やめると相手の勝ちになる」→「『つづける』を押して」→［つづける］で「最後まで続けよう」。壁2「太陽が昇る方角は？」
## （赤「東」が正解）が終わると本番のオンラインの結果のカード →「終わるとこの画面に戻る」→『オンラインメニューへ』。
## 負けたとき（自分がアウト・2人ともアウト）は「惜しい」と言ってから同じように進む（やり直しはしない）。
class MatchStep extends PracticeStep:
	## CPU はふつうの速さで正解へ向かう（押し合いはしない。PracticeCpu.go_door の急ぎ）
	const CPU_HASTE := 0.5
	## Esc の案内の間は、CPU は壁2の正解のドアの前で P1 より前に出ない（先に壁2を取って試合が終わらないように）
	const WAIT_HASTE := 0.0
	## 始まる前（開始の前の壁の手前）に立つ所：P1 の左の少し前（x は +が画面の左）。壁の前だと開始の前の壁に隠れる
	const OPENING_SPOT := Vector3(4.2, 0.0, 2.5)
	## 覆い（VS の稲妻）が開いてから、最初の言葉までの間（s）
	const ARRIVE_PAUSE := 0.6
	## エモートであいさつする間（「試合前はエモートであいさつできる」のあと、s）
	const GREET_SECONDS := 1.6
	## 「Escを押してみて」をくり返すまでの秒（押していないとき）
	const ESC_REPEAT_SECONDS := 5.0
	## 結果のカードが出るのを待つ最長（ms）
	const CARD_TIMEOUT_MS := 15000

	## &"arrive"・&"talk"・&"start"・&"wall1"・&"esc_talk"・&"esc_wait"・&"esc_coach"・&"esc_press"・&"wall2"・&"result"・&"menu"・&"done"
	var phase := &"arrive"
	## CPU を壁2へ向かわせた
	var _cpu_wall2 := false
	## Esc の案内を済ませた（または壁2が来て間に合わなかった）
	var _esc_done := false
	var _esc_idle := 0.0

	func _init() -> void:
		id = MATCH_STEP_ID

	## 本番の2人の10問と同じルール（docs/new_tutorial/phase7_design.md 1.2）。壁2枚を終えたら本番の CLEAR のカード。
	## 結果の画面は本番どおり（GAME OVER・CLEAR のカード）。記録はしない。
	static func match_rules() -> MatchRules:
		var rules := MatchRules.new()
		rules.world_speed = -1.0
		rules.hp_enabled = true
		rules.hp_floor = 0
		rules.mistakes = MatchRules.Mistakes.NORMAL
		rules.ocean = MatchRules.Ocean.NORMAL
		rules.saw_enabled = true
		rules.local_push_enabled = true
		rules.ghost_ride_enabled = true
		rules.record_results = false
		rules.finish_with_clear = true
		rules.real_result_screens = true
		return rules

	## 台本の問題（3章）
	static func make_quiz(question_id: String, choices_id: String, answer: int) -> QuizItem:
		var item := QuizItem.create(PracticeTexts.get_text(question_id).replace("／", "\n"), PracticeTexts.get_parts(choices_id), answer)
		item.src = "PRACTICE"
		return item

	static func quizzes() -> Array[QuizItem]:
		var list: Array[QuizItem] = [make_quiz("c4.match.q1", "c4.match.c1", 0), make_quiz("c4.match.q2", "c4.match.c2", 1)]
		return list

	func enter(d: PracticeDirector) -> void:
		phase = &"arrive"
		_cpu_wall2 = false
		_esc_done = false
		_esc_idle = 0.0
		d.setup_cpu(true)
		# 本番と同じ始まり方（開始の前の壁が落ちて、空撮 → カウントダウン）。Enter では始めない（オンラインと同じ）
		d.restart_round(quizzes(), match_rules(), [], Constants.STATE_WAITING_START)
		d.cpu_call(&"idle")
		d.bubble_point = Callable()
		d.bubble_unanchored = false
		d.hatena.set_cloud(false)
		# 始まるまでは2人の近く（壁の前は開始の前の壁に隠れる）。スタートしたら、いまの壁の前へ（①〜③と同じ）
		d.hatena_follow = false
		d.hatena.place_at(OPENING_SPOT, PI)
		# 案内のハテナが舞台にいる間は、のこぎりの操縦席のハテナを隠す（ハテナが2人に見えないように）
		d.set_saw_operator_hidden(true)
		_opening(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		d.coach_end()
		d.set_saw_operator_hidden(false)

	## ステージに着く「試合前はエモートであいさつできる」→「ルールは2人対戦と同じ」と同時に、本番の始まり方へ
	func _opening(d: PracticeDirector, serial: int) -> void:
		if not await d.until(func() -> bool: return not SceneTransition.is_transitioning(), serial):
			return
		d.set_saw_operator_hidden(true)
		await d.wait(ARRIVE_PAUSE)
		if not d.is_current(serial):
			return
		phase = &"talk"
		d.hatena.play(&"wave")
		await d.say("c4.match.4")
		if not d.is_current(serial):
			return
		await d.wait(GREET_SECONDS)
		if not d.is_current(serial):
			return
		# 開始の前の壁とバリアがそろってから（本番と同じ。そろわないときも少し待って始める）
		var deadline := Time.get_ticks_msec() + 6000
		if not await d.until(func() -> bool:
				return bool(d.world_call(&"practice_start_ready")) or Time.get_ticks_msec() >= deadline, serial):
			return
		phase = &"start"
		d.hatena.play(&"point")
		d.say("c4.match.5")
		d.game_state.trigger_start()

	func process(d: PracticeDirector, dt: float) -> void:
		var state := d.game_state.game_state
		if state != Constants.STATE_PLAYING:
			return
		# 壁2が今の壁になったら、CPU も壁2の正解（赤）へ（Esc の案内が済むまでは P1 より前に出ない）
		if not _cpu_wall2 and d.game_state.current_wall_index >= 1 and d.game_state.current_quiz != null:
			_cpu_wall2 = true
			d.cpu_call(&"go_door", [1, CPU_HASTE if _esc_done else WAIT_HASTE])
		# 「Escを押してみて」のあと押さないときは、ときどき言い直す
		if phase == &"esc_wait":
			_esc_idle += dt
			if _esc_idle >= ESC_REPEAT_SECONDS:
				_esc_idle = 0.0
				d.say("c4.match.7")

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"state_changed":
				match str(data.state):
					Constants.STATE_PLAYING:
						if phase in [&"talk", &"start"]:
							phase = &"wall1"
							d.follow_walls()
							d.cpu_call(&"go_door", [0, CPU_HASTE])
					Constants.STATE_CLEAR, Constants.STATE_GAME_OVER:
						_result(d, d.step_serial)
			&"question_completed":
				# 壁1が終わった：壁と壁の間の落ち着いた所で Esc を教える
				if int(data.wall_index) == 0 and phase == &"wall1" and not _esc_done:
					_esc_lesson(d, d.step_serial)
			&"quit_confirm":
				if bool(data.open):
					if phase in [&"esc_talk", &"esc_wait"]:
						_esc_coach(d, d.step_serial)
				elif phase in [&"esc_coach", &"esc_press"]:
					_continued(d, d.step_serial)
			&"coach_exit":
				# コーチの上の Esc は下の画面にも渡す（「やめる？」が閉じる＝［つづける］と同じ）。結果のカードでは何もしない
				pass

	## 壁1が終わる「オンラインでは一時停止できない」→「Escを押してみて」→ 押すまで待つ
	func _esc_lesson(d: PracticeDirector, serial: int) -> void:
		phase = &"esc_talk"
		d.hatena.play(&"cross")
		await d.say("c4.match.6")
		if not d.is_current(serial) or phase != &"esc_talk":
			return
		phase = &"esc_wait"
		_esc_idle = 0.0
		d.hatena.play(&"point")
		d.say("c4.match.7")

	## Esc を押した：本番の「たいせんを やめますか？」の上で「やめると相手の勝ちになる」→「『つづける』を押して」（［やめる］は押せない）
	func _esc_coach(d: PracticeDirector, serial: int) -> void:
		phase = &"esc_coach"
		d.coach_begin(true)
		# コーチの上の Esc も本番どおり「やめる？」を閉じる（［つづける］と同じ）
		if d.coach != null:
			d.coach.set(&"pass_escape", true)
		d.coach_call(&"clear_focus")
		d.coach_play(&"tilt")
		await d.say("c4.match.8")
		if not d.is_current(serial) or phase != &"esc_coach":
			return
		phase = &"esc_press"
		d.coach_focus([&"quit_continue"], true)
		d.coach_play(&"point")
		d.say("c4.match.9", true)

	## ［つづける］（か Esc）で「やめる？」が閉じた「最後まで続けよう」
	func _continued(d: PracticeDirector, serial: int) -> void:
		_esc_done = true
		phase = &"wall2"
		d.coach_end()
		if d.game_state.game_state != Constants.STATE_PLAYING:
			return
		# CPU もふつうの速さで壁2の正解へ
		if _cpu_wall2:
			d.cpu_call(&"go_door", [1, CPU_HASTE])
		d.hatena.play(&"cheer")
		await d.say("c4.match.10")
		if not d.is_current(serial):
			return

	## 壁2が終わった（か負けた）：本番のオンラインの結果のカード →（負けたら「惜しい」）→「終わるとこの画面に戻る」→『オンラインメニューへ』
	func _result(d: PracticeDirector, serial: int) -> void:
		if phase in [&"result", &"menu", &"done"]:
			return
		var was_coaching := phase in [&"esc_coach", &"esc_press"]
		phase = &"result"
		_esc_done = true
		if was_coaching:
			d.coach_end()
		d.cpu_call(&"idle")
		# 自分がアウト（ハート0・海・のこぎり）になった、または2人ともアウトで終わった
		var lost := d.game_state.game_state == Constants.STATE_GAME_OVER or not d.game_state.p1_alive
		if lost:
			d.hatena.play(&"oops")
			d.say("c4.match.fail")
		var deadline := Time.get_ticks_msec() + CARD_TIMEOUT_MS
		if not await d.until(func() -> bool: return d.result_card_visible() or Time.get_ticks_msec() >= deadline, serial):
			return
		phase = &"menu"
		d.coach_begin(true)
		d.coach_play(&"wave")
		d.coach_focus([&"result_menu"], true)
		d.say("c4.match.11", true)

	## 『オンラインメニューへ』：練習の形のオンラインの画面へ戻って、クリアを始めてもらう
	func on_leave_to_menu(d: PracticeDirector) -> bool:
		if phase == &"done":
			return true
		if phase != &"menu":
			d.skipped_steps += 1
		phase = &"done"
		d.coach_end()
		d.continue_in_menu("clear", str(PracticeCatalog.find("c4").get("scene", PracticeDirector.MAIN_MENU_SCENE)))
		return true
