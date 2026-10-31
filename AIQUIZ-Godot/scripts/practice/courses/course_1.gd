extends PracticeCourse

## コース① 基本操作（台本 docs/new_tutorial/course1_script.md v0.2、段階4の設計 docs/new_tutorial/phase4_design.md 4章）。
## 1-1 ようこそ → 1-2 移動 → 1-3 ドアをくぐる → 1-4 クイズに答える → 1-5 ハート → 1-6 床の端 → 1-7 仕上げ
## → クリア（監督の finish_course）。
## 座標はゲーム画面のもの：x は +が画面の左、z はコンベア上の前。レッスンの始め・まきもどしでプレイヤーが立つ所は x 0、z 0。
## ハテナは監督の follow_walls で、いまの壁（クイズの壁か看板の壁）の前に立つ。

## 練習の壁（台本①の 1.4・1.6）：22m 先に落ち、毎秒 1.6m で近づく。まきもどしのあと・もう一度のときは 12m 先から
const WALL_DISTANCE := 22.0
const RETRY_DISTANCE := 12.0
const WALL_SPEED := 1.6
## 壁の着地からコンベアが動き出すまで（台本①の 1-3）
const START_DELAY := 0.5
## 見えないさく（台本①の 1.5）：左右 x ±10、うしろ z −6。前は 1-2 だけ z +8（1-3 から外す）
const FENCE_X := 10.0
const FENCE_BACK := -6.0
const FENCE_FRONT := 8.0
const OPEN_FRONT := 1000.0
## 1-1 でハテナが降りてくる高さ
const HATENA_DROP_HEIGHT := 9.0
## 壁までこの距離になってもドアの前にいなければ、ハテナが声をかける（1-3・1-4）
const HINT_DISTANCE := 8.0
## 1-7：負けたとき、本番どおりの演出（体が崩れる・サメ）を見せてから話すまで
const LOST_PAUSE := 1.2
## 1-7：3枚目（番号 2）がボス壁
const FINAL_BOSS := 2


func _init() -> void:
	id = "c1"
	lesson_ids = ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6", "1-7"]
	# クリアカードの［つぎの コースへ］で②（docs/new_tutorial/phase5_design.md 6.1）
	next_course = "c2"


func build_steps() -> Array[PracticeStep]:
	var list: Array[PracticeStep] = [Welcome.new(), Move.new(), DoorStep.new(), QuizStep.new(), Hearts.new(),
		Edge.new(), Final.new()]
	return list


## コース①のレッスンの土台：ルールの決まりごとと、よく使う道具。
class Course1Step extends PracticeStep:
	## 1-1〜1-4 のもと：コンベアは止める、ハートなし、ミスは通知だけ、海はかまれても通知だけ、記録しない。
	func base_rules() -> MatchRules:
		var rules := MatchRules.new()
		rules.world_speed = 0.0
		rules.mistakes = MatchRules.Mistakes.REPORT_ONLY
		rules.ocean = MatchRules.Ocean.REPORT_AFTER_BITE
		rules.record_results = false
		return rules

	## 見えないさく（台本①の 1.5）：左右 x ±10、うしろ z −6、前 front_z
	func fence(rules: MatchRules, front_z: float) -> void:
		rules.fence_enabled = true
		rules.fence_min = Vector2(-FENCE_X, FENCE_BACK)
		rules.fence_max = Vector2(FENCE_X, front_z)

	## コンベアを止めて、操作をロックする（失敗の言葉の間。押しっぱなしで何度も壁に当たらないように）
	func hold(d: PracticeDirector) -> void:
		d.rules.world_speed = 0.0
		d.rules.input_locked = true

	## 看板の壁の前（ハテナが立つ所）。看板の壁がまだないときは、P1 から 14m 先の看板の前。
	func sign_spot(d: PracticeDirector) -> Vector3:
		var z := d.sign_local_z()
		if is_nan(z):
			z = d.game_state.player_local_z + PracticeDirector.SIGN_DISTANCE
		return Vector3(PracticeDirector.HATENA_WALL_X, 0.0, z - PracticeDirector.HATENA_WALL_FRONT)

	## 台本の問題（3章）。question_id の「／」は2行にし、choices_id はドアの番号の順に「／」で区切った文字。
	static func make_quiz(question_id: String, choices_id: String, answer: int) -> QuizItem:
		var item := QuizItem.create(PracticeTexts.get_text(question_id).replace("／", "\n"), PracticeTexts.get_parts(choices_id), answer)
		item.src = "PRACTICE"
		return item


## 1-1 ようこそ（約6秒）：操作はロック。看板の壁が落ち、ハテナが空から看板の前へ降りてきて、あいさつする。
## カメラは少し高い所から2秒かけてプレイヤーの後ろへ下りる（本編側の practice_camera_intro）。
class Welcome extends Course1Step:
	func _init() -> void:
		id = "1-1"

	func enter(d: PracticeDirector) -> void:
		var rules := base_rules()
		rules.input_locked = true
		# 1人のときの開始位置（z −8）は 1-2 のさくの外なので、さくを入れる前に置き直す
		d.place_player(1, 0.0, 0.0)
		fence(rules, FENCE_FRONT)
		d.set_rules(rules)
		d.hatena_follow = false
		d.hatena.set_cloud(false)
		d.hatena.visible = false
		d.world_call(&"practice_camera_intro", [2.0])
		# 0.0：看板の壁が空から落ちてくる。パネル2枚は「？」の絵
		d.open_sign(PracticeTexts.get_parts("c1.welcome.sign"), [
			{"key": &"question_left", "picture": &"question"},
			{"key": &"question_right", "picture": &"question"},
		])
		_run(d, d.step_serial)

	func _run(d: PracticeDirector, serial: int) -> void:
		await d.wait(0.2)
		if not d.is_current(serial):
			return
		# 0.8 秒：空から看板の前へ着地して、手をふる。1.4 秒から話す
		var spot := sign_spot(d)
		d.hatena.place_at(spot + Vector3.UP * HATENA_DROP_HEIGHT)
		await d.hatena.hop_to(spot, 0.6)
		if not d.is_current(serial):
			return
		d.follow_walls()
		d.hatena.play(&"wave")
		await d.wait(0.6)
		if not d.is_current(serial):
			return
		for line: Array in [[&"wave", "c1.welcome.1"], [&"open_arms", "c1.welcome.2"]]:
			d.hatena.play(line[0])
			await d.say(line[1])
			if not d.is_current(serial):
				return
		d.complete_step()


## 1-2 移動（約20秒）：左右（ステップA）、前後（ステップB）に合計1.5mずつ動く。
## 看板の壁はそのまま使い、パネル2枚が大きなキーの絵（矢印キーを大きく、A D・W S を小さく）になる。
class Move extends Course1Step:
	## 1方向あたりに動く合計（m）
	const NEED := 1.5
	## 何も押さないとき、この秒数ごとに「キーを おして みて」
	const IDLE_HINT_SECONDS := 8.0
	## 1フレームでこれより大きく動いたら置き直し（数えない）
	const TELEPORT := 1.0
	## A（よこ）が終わってから B（まえと うしろ）までと、4方向とも ✓ から 1-3 まで（秒）
	const NEXT_DELAY := 1.0

	## 0 = よこ（ステップA）、1 = まえと うしろ（ステップB）、-1 = 次へ移るあいだ
	var phase := 0
	var moved := {}
	var _last := Vector2.ZERO

	func _init() -> void:
		id = "1-2"

	func enter(d: PracticeDirector) -> void:
		var rules := base_rules()
		# 1-1 をとばしたときも、さくの中から始める
		d.place_player(1, 0.0, 0.0)
		fence(rules, FENCE_FRONT)
		d.set_rules(rules)
		d.hatena.set_cloud(false)
		d.follow_walls()
		d.hatena.play(&"wave")
		moved = {&"left": 0.0, &"right": 0.0, &"forward": 0.0, &"back": 0.0}
		_last = d.player_pos(1)
		d.idle_seconds = 0.0
		_begin_horizontal(d)

	func _begin_horizontal(d: PracticeDirector) -> void:
		phase = 0
		# 矢印キーを大きく、A D を小さく（台本①の 1-2）
		d.open_sign(PracticeTexts.get_parts("c1.move.sign_lr"), [
			{"key": &"left", "glyph": "←", "sub": "A"},
			{"key": &"right", "glyph": "→", "sub": "D"},
		])
		d.say("c1.move.1")

	func _begin_vertical(d: PracticeDirector) -> void:
		phase = 1
		_last = d.player_pos(1)
		d.idle_seconds = 0.0
		d.hatena.play(&"wave")
		d.set_sign(PracticeTexts.get_parts("c1.move.sign_fb"), [
			{"key": &"forward", "glyph": "↑", "sub": "W"},
			{"key": &"back", "glyph": "↓", "sub": "S"},
		])
		d.say("c1.move.3")

	func process(d: PracticeDirector, _dt: float) -> void:
		var now := d.player_pos(1)
		var delta := now - _last
		_last = now
		if delta.length() > TELEPORT:
			return
		match phase:
			0:
				# x は +が画面の左
				_add(d, &"left", maxf(delta.x, 0.0))
				_add(d, &"right", maxf(-delta.x, 0.0))
				if _done(&"left") and _done(&"right"):
					phase = -1
					_finish_horizontal(d, d.step_serial)
			1:
				_add(d, &"forward", maxf(delta.y, 0.0))
				_add(d, &"back", maxf(-delta.y, 0.0))
				if _done(&"forward") and _done(&"back"):
					phase = -1
					_finish_vertical(d, d.step_serial)
		# 動かないとき：パネルを指して「キーを おして みて」、パネルが点滅する。8秒ごとにくり返す
		if phase >= 0 and d.idle_seconds >= IDLE_HINT_SECONDS:
			d.idle_seconds = 0.0
			d.hatena.play(&"point")
			d.say("c1.move.idle")
			d.blink_sign()

	func _add(d: PracticeDirector, key: StringName, amount: float) -> void:
		if _done(key) or amount <= 0.0:
			return
		moved[key] = float(moved[key]) + amount
		if _done(key):
			d.tick_sign(key)

	func _done(key: StringName) -> bool:
		return float(moved.get(key, 0.0)) >= NEED

	func _finish_horizontal(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"clap")
		d.say("c1.move.2")
		await d.wait(NEXT_DELAY)
		if not d.is_current(serial):
			return
		_begin_vertical(d)

	func _finish_vertical(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"cheer")
		d.say("c1.move.4")
		await d.wait(NEXT_DELAY)
		if not d.is_current(serial):
			return
		d.complete_step()


## 1-3・1-4 の土台：2択のクイズ壁が 22m 先に落ち、着地から 0.5 秒でコンベアが練習の速さで動き出す。
## ミスはハートも体もそのまま（REPORT_ONLY）。違うドア・壁に当たったら、コンベアを止めてから言葉 → まきもどし
## （プレイヤーは x 0、z 0、壁は 12m 先から）。2回失敗で正解のドアへの矢印、3回失敗で壁が半分の速さ。
class DoorLesson extends Course1Step:
	## &"wait"（壁が落ちてくる）・&"play"・&"fail"（失敗の言葉の間）・&"done"
	var phase := &"wait"
	var hinted := false

	## この壁の問題
	func quiz() -> QuizItem:
		return null

	## 正解のドアの番号
	func answer() -> int:
		return 0

	## 始まりの言葉（壁が落ちてくる間）
	func opening(_d: PracticeDirector, _serial: int) -> void:
		pass

	## 着地から 0.5 秒（コンベアが動き出すとき）
	func on_started(_d: PracticeDirector) -> void:
		pass

	## 壁まで 8m でまだ答えのドアの前にいないときの声かけ（1回）。true なら声をかけた
	func hint(_d: PracticeDirector) -> bool:
		return false

	## くぐれた（正解）。言い終わったら次のレッスンへ
	func succeed(_d: PracticeDirector, _serial: int) -> void:
		pass

	## 違うドア・壁のときの言葉の ID（そのあと「もう一回」）
	func wrong_line(door: int) -> String:
		return "c1.any.wall" if door < 0 else ""

	func lesson_rules() -> MatchRules:
		var rules := base_rules()
		fence(rules, OPEN_FRONT)
		return rules

	func enter(d: PracticeDirector) -> void:
		d.set_rules(lesson_rules())
		d.close_sign()
		d.hatena.set_cloud(false)
		d.follow_walls()
		phase = &"wait"
		hinted = false
		var quizzes: Array[QuizItem] = [quiz()]
		d.set_quizzes(quizzes)
		d.drop_wall(WALL_DISTANCE)
		opening(d, d.step_serial)

	func rewind(d: PracticeDirector) -> void:
		var rules := lesson_rules()
		d.place_player(1, 0.0, 0.0)
		d.set_rules(rules)
		d.place_wall(RETRY_DISTANCE)
		hinted = false
		phase = &"play"
		rules.world_speed = d.practice_speed(WALL_SPEED)

	func hint_door_x(d: PracticeDirector) -> float:
		return d.door_x(answer(), 2) if phase in [&"wait", &"play"] else NAN

	func process(d: PracticeDirector, _dt: float) -> void:
		if phase == &"play" and not hinted and d.wall_distance() <= HINT_DISTANCE:
			hinted = hint(d)

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"wall_landed":
				if phase == &"wait":
					_start(d, d.step_serial)
			&"wall_contact":
				if int(data.player) == 1 and phase in [&"wait", &"play"]:
					if bool(data.correct):
						phase = &"done"
						succeed(d, d.step_serial)
					else:
						phase = &"fail"
						_fail(d, d.step_serial, int(data.door))

	func _start(d: PracticeDirector, serial: int) -> void:
		await d.wait(START_DELAY)
		if not d.is_current(serial) or phase != &"wait":
			return
		phase = &"play"
		d.rules.world_speed = d.practice_speed(WALL_SPEED)
		on_started(d)

	func _fail(d: PracticeDirector, serial: int, door: int) -> void:
		hold(d)
		var line := wrong_line(door)
		if not line.is_empty():
			await d.say(line)
			if not d.is_current(serial):
				return
		d.fail_step("c1.any.retry")


## 1-3 ドアをくぐる（約18秒）：「青いドアをくぐろう」。青「青」が正解、赤「赤」。
class DoorStep extends DoorLesson:
	func _init() -> void:
		id = "1-3"

	func quiz() -> QuizItem:
		return make_quiz("c1.door.q", "c1.door.c", 0)

	func answer() -> int:
		return 0

	func opening(d: PracticeDirector, _serial: int) -> void:
		# 新しい壁へジャンプ（監督）して「かべが くるよ！」
		d.say("c1.door.1")

	func on_started(d: PracticeDirector) -> void:
		d.hatena.play(&"point")
		d.say("c1.door.2")

	func hint(d: PracticeDirector) -> bool:
		# 青のドアの前（x = +1.7〜+5.3）にいない
		var center := d.door_x(0, 2)
		if absf(d.game_state.player_x - center) <= d.game_state.tuning.door_half_width:
			return false
		d.hatena.play(&"point")
		d.say("c1.door.hint")
		return true

	func succeed(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"cheer")
		await d.say("c1.door.ok")
		if d.is_current(serial):
			d.complete_step()

	func wrong_line(door: int) -> String:
		return "c1.door.red" if door == 1 else "c1.any.wall"


## 1-4 クイズに答える（約18秒）：「日本の首都は？」。赤「東京」が正解、青「大阪」（色ではなく答えで選ぶ）。
class QuizStep extends DoorLesson:
	func _init() -> void:
		id = "1-4"

	func quiz() -> QuizItem:
		return make_quiz("c1.quiz.q", "c1.quiz.c", 1)

	func answer() -> int:
		return 1

	func opening(d: PracticeDirector, serial: int) -> void:
		d.say("c1.quiz.1")
		await d.wait(2.0)
		if d.is_current(serial) and phase in [&"wait", &"play"]:
			d.say("c1.quiz.2")

	func hint(d: PracticeDirector) -> bool:
		# どのドアの前にもいない
		var half := d.game_state.tuning.door_half_width
		for door: int in [0, 1]:
			if absf(d.game_state.player_x - d.door_x(door, 2)) <= half:
				return false
		d.hatena.play(&"tilt")
		d.say("c1.quiz.hint")
		return true

	func succeed(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"clap")
		await d.say("c1.quiz.ok1")
		if not d.is_current(serial):
			return
		d.hatena.play(&"nod")
		await d.say("c1.quiz.ok2")
		if d.is_current(serial):
			d.complete_step()

	func wrong_line(door: int) -> String:
		return "c1.quiz.ng" if door == 0 else "c1.any.wall"


## 1-5 ハート（約20秒）：ハートが初めて出る。ルールを説明して、1問だけ解く。ここからは本番どおり（違うドア・壁で
## ハートが1つ減る。このレッスンだけ1より減らない）。正解でもミスでも先へ進み、ミスで減ったときだけ3つに戻す。
class Hearts extends Course1Step:
	## &"intro"・&"wait"（壁が落ちてくる）・&"play"・&"end"
	var phase := &"intro"

	func _init() -> void:
		id = "1-5"

	func lesson_rules() -> MatchRules:
		var rules := base_rules()
		rules.hp_enabled = true
		rules.hp_floor = 1
		rules.mistakes = MatchRules.Mistakes.NORMAL
		fence(rules, OPEN_FRONT)
		return rules

	func enter(d: PracticeDirector) -> void:
		d.set_rules(lesson_rules())
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		d.close_sign()
		d.revive(1)
		d.set_hp(1, QuizGameState.MAX_HP)
		d.hatena.set_cloud(false)
		d.follow_walls()
		phase = &"intro"
		_intro(d, d.step_serial)

	## 左上を指してルールを3つ言い（ハートがポンと出て、1つずつ光る。本編側の practice_hearts_intro）、壁を落とす
	func _intro(d: PracticeDirector, serial: int) -> void:
		d.world_call(&"practice_hearts_intro", [1])
		d.hatena.play(&"point")
		for line: String in ["c1.heart.1", "c1.heart.2", "c1.heart.3"]:
			await d.say(line)
			if not d.is_current(serial):
				return
		phase = &"wait"
		d.rules.world_speed = 0.0
		var quizzes: Array[QuizItem] = [make_quiz("c1.heart.q", "c1.heart.c", 0)]
		d.set_quizzes(quizzes)
		d.drop_wall(WALL_DISTANCE)
		d.say("c1.heart.4")

	func hint_door_x(d: PracticeDirector) -> float:
		return d.door_x(0, 2) if phase in [&"wait", &"play"] else NAN

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"wall_landed":
				if phase == &"wait":
					_landed(d, d.step_serial)
			&"wall_contact":
				if int(data.player) == 1 and phase in [&"wait", &"play"]:
					phase = &"end"
					_react(d, d.step_serial, bool(data.correct))

	func _landed(d: PracticeDirector, serial: int) -> void:
		phase = &"play"
		await d.wait(START_DELAY)
		if d.is_current(serial) and phase == &"play":
			d.rules.world_speed = d.practice_speed(WALL_SPEED)

	## 正解：「正解。ハートはそのまま」。ミス：本番どおりハートが減る →「ハートが1つ減ったね」→「練習だから戻しておくよ」
	## と、ハートを3つに戻す（増える動き）。どちらも 1-6 へ。
	func _react(d: PracticeDirector, serial: int, correct: bool) -> void:
		d.rules.world_speed = 0.0
		if correct:
			d.hatena.play(&"clap")
			await d.say("c1.heart.ok")
		else:
			d.hatena.play(&"point")
			await d.say("c1.heart.ng")
			if not d.is_current(serial):
				return
			d.hatena.play(&"nod")
			var last := d.say("c1.heart.5")
			for hp: int in range(d.game_state.get_player_hp(1) + 1, QuizGameState.MAX_HP + 1):
				await d.wait(0.35)
				if not d.is_current(serial):
					return
				d.set_hp(1, hp)
			await last
		if d.is_current(serial):
			d.complete_step()


## 1-6 床の端（約30秒）：コンベアを止め、見えないさくを外す（ここから本当に落ちる）。
## 看板の壁（「波」と「サメ」の絵）が落ち、始めの約5秒（操作はロック）にカメラで床の外の海とサメを短く見せる。
## タスクA「横の端」、タスクB「うしろの端」。落ちてサメにかまれたら「落ちたね」→ そのタスクの始めへ。
class Edge extends Course1Step:
	## サメが泳いで来る海面（端から 3.5m 外。端のすぐ外は床の土台に隠れる）
	const SEA_SPOT := Vector3(-15.5, StageConstants.OCEAN_SURFACE_Y, 6.0)
	## 床の外の海とサメを映すカメラ（本編側の practice_camera_frame の目と注視点。向きを変えるだけでは海が映らない）。
	## 床と観客席の間の海の上から見る。カメラの座標なので床の上面は y −1.2。
	const SEA_EYE := Vector3(-13.8, -5.0, -1.5)
	const SEA_TARGET := Vector3(-15.5, -9.0, 7.0)
	## 海を映している秒数
	const SEA_SECONDS := 2.6
	## 床の左右の端（レール）と うしろの端（QuizGameState.FLOOR_HALF_WIDTH・FLOOR_BACK_Z）
	const FLOOR_X := QuizGameState.FLOOR_HALF_WIDTH
	const FLOOR_BACK := QuizGameState.FLOOR_BACK_Z
	## ギリギリ ゾーン：横は x ±9.5〜±12、うしろは z −10〜−12.5。横のゾーンを描く z の範囲
	const SIDE_ZONE_X := 9.5
	const BACK_ZONE_Z := -10.0
	const SIDE_ZONE_Z := Vector2(-12.5, 18.0)
	## 戻ったら ✓：横は真ん中（x −3〜+3）、うしろは z −5 より前
	const SAFE_X := 3.0
	const SAFE_BACK_Z := -5.0

	## &"demo"・&"side"（タスクA）・&"back"（タスクB）・&"fell"（落ちて、かまれるのを待つ）・&"done"
	var task := &"demo"
	## いまのタスク（&"side"・&"back"。落ちたらここへ戻る）
	var current := &"side"
	var touched := false

	func _init() -> void:
		id = "1-6"

	func lesson_rules(locked: bool) -> MatchRules:
		var rules := base_rules()
		rules.hp_enabled = true
		rules.hp_floor = 1
		rules.input_locked = locked
		return rules

	func enter(d: PracticeDirector) -> void:
		d.set_rules(lesson_rules(true))
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		d.revive(1)
		# 1-5 では前へ走って壁に当たるので、始めの位置（端は z +6、うしろの端は z −12.5 が画面に入る所）へ戻す
		d.place_player(1, 0.0, 0.0)
		d.hatena_follow = false
		task = &"demo"
		current = &"side"
		touched = false
		_demo(d, d.step_serial)

	func exit(d: PracticeDirector) -> void:
		d.world_call(&"practice_shark_cancel")
		d.world_call(&"practice_camera_release", [0.4])

	## 始め（約5秒、操作はロック）：看板の壁が落ち、カメラが床と観客席の間の海の上へ移って、サメが1匹泳いで来る。
	## カメラが戻ったら「落ちたら ハートが あっても アウト」。
	func _demo(d: PracticeDirector, serial: int) -> void:
		d.open_sign(PracticeTexts.get_parts("c1.edge.sign1"), [
			{"key": &"wave", "picture": &"wave"},
			{"key": &"shark", "picture": &"shark"},
		])
		var front := sign_spot(d)
		d.hatena.set_cloud(false)
		if d.hatena.visible:
			d.hatena.hop_to(front, 0.8)
		else:
			d.hatena.place_at(front)
		await d.wait(0.6)
		if not d.is_current(serial):
			return
		_frame_sea(d, 0.8)
		d.world_call(&"practice_shark_approach", [SEA_SPOT])
		d.say("c1.edge.1")
		await d.wait(SEA_SECONDS)
		if not d.is_current(serial):
			return
		d.world_call(&"practice_shark_cancel")
		d.world_call(&"practice_camera_release", [0.8])
		d.set_sign(PracticeTexts.get_parts("c1.edge.sign2"))
		d.hatena.play(&"point")
		await d.say("c1.edge.2")
		if not d.is_current(serial):
			return
		d.rules.input_locked = false
		d.follow_walls()
		_begin_side(d, serial)

	## 床の外の海を映す（本編側の practice_camera_frame。まだないときは、向きを変えるだけの practice_camera_look）
	func _frame_sea(d: PracticeDirector, seconds: float) -> void:
		if d.world != null and d.world.has_method(&"practice_camera_frame"):
			d.world_call(&"practice_camera_frame", [SEA_EYE, SEA_TARGET, seconds])
		else:
			d.world_call(&"practice_camera_look", [SEA_SPOT, seconds])

	## タスクA：床の左右の端が赤く光り、端の内側に黄色いギリギリ ゾーン。2秒後に看板「横の端まで行って／戻ろう」
	func _begin_side(d: PracticeDirector, serial: int) -> void:
		task = &"side"
		current = &"side"
		touched = false
		d.clear_marks()
		d.show_edge_glow([&"left", &"right"])
		var depth := SIDE_ZONE_Z.y - SIDE_ZONE_Z.x
		d.show_zones([
			Rect2(SIDE_ZONE_X, SIDE_ZONE_Z.x, FLOOR_X - SIDE_ZONE_X, depth),
			Rect2(-FLOOR_X, SIDE_ZONE_Z.x, FLOOR_X - SIDE_ZONE_X, depth),
		])
		d.hatena.play(&"point")
		d.say("c1.edge.6")
		await d.wait(2.0)
		if not d.is_current(serial) or task != &"side":
			return
		# もうゾーンに入っていたら「端の近くまで行って戻ってきて」は言わない（看板だけ変える）
		if not touched:
			d.say("c1.edge.7")
		d.set_sign(PracticeTexts.get_parts("c1.edge.sign3"))

	## タスクB：床のうしろの端が赤く光り、黄色いゾーン（z −10〜−12.5）。看板「後ろの端まで下がって／戻ろう」
	## 1人のカメラには床のうしろの端は映らない。カメラは動かさず、本番の HUD のうしろの端の警告（画面の点滅）を合図にする。
	func _begin_back(d: PracticeDirector) -> void:
		task = &"back"
		current = &"back"
		touched = false
		d.clear_marks()
		d.show_edge_glow([&"back"])
		d.show_zones([Rect2(-FLOOR_X, FLOOR_BACK, FLOOR_X * 2.0, BACK_ZONE_Z - FLOOR_BACK)])
		d.hatena.play(&"point")
		d.say("c1.edge.10")
		d.set_sign(PracticeTexts.get_parts("c1.edge.sign4"))

	func rewind(d: PracticeDirector) -> void:
		d.revive(1)
		d.place_player(1, 0.0, 0.0)
		d.set_rules(lesson_rules(false))
		if current == &"back":
			_begin_back(d)
		else:
			_begin_side(d, d.step_serial)

	func process(d: PracticeDirector, _dt: float) -> void:
		if task not in [&"side", &"back"] or not d.player_standing(1):
			return
		var pos := d.player_pos(1)
		if task == &"side":
			if not touched and absf(pos.x) >= SIDE_ZONE_X and absf(pos.x) <= FLOOR_X:
				_touch(d, 0 if pos.x > 0.0 else 1)
			elif touched and absf(pos.x) <= SAFE_X:
				_side_done(d, d.step_serial)
		else:
			if not touched and pos.y <= BACK_ZONE_Z and pos.y >= FLOOR_BACK:
				_touch(d, 0)
			elif touched and pos.y >= SAFE_BACK_Z:
				_back_done(d, d.step_serial)

	## ゾーンに入った：「ギリギリ」とピコン
	func _touch(d: PracticeDirector, zone: int) -> void:
		touched = true
		d.flash_zone(zone)
		d.play_pico()
		d.say("c1.edge.8")

	## 真ん中へ戻った：「OK」と ✓。1秒後にタスクB
	func _side_done(d: PracticeDirector, serial: int) -> void:
		task = &"wait"
		current = &"back"
		d.tick_sign(&"wave")
		d.hatena.play(&"clap")
		d.say("c1.edge.9")
		await d.wait(1.0)
		if d.is_current(serial) and task == &"wait":
			_begin_back(d)

	## z −5 より前へ戻った：「下がれば時間を稼げる」→「ただし落ちないように」と ✓ → 1-7
	func _back_done(d: PracticeDirector, serial: int) -> void:
		task = &"done"
		d.tick_sign(&"shark")
		d.hatena.play(&"cheer")
		await d.say("c1.edge.11")
		if not d.is_current(serial):
			return
		await d.say("c1.edge.12")
		if d.is_current(serial):
			d.complete_step()

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		if int(data.get("player", 1)) != 1:
			return
		match event:
			&"entered_ocean":
				# 本番の水しぶき・サメ・観客のどよめき（本編のまま）。かまれるのを待つ
				if task in [&"side", &"back", &"wait"]:
					task = &"fell"
			&"ocean_bitten":
				if task in [&"fell", &"side", &"back", &"wait"]:
					task = &"fell"
					_fell(d, d.step_serial)

	func _fell(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"oops")
		await d.say("c1.edge.13")
		if d.is_current(serial):
			d.fail_step("c1.any.retry")


## 1-7 仕上げ（約45秒）：本番どおり（ハート3つ・0でアウト、海に落ちたらアウト、本番の自動の速さ）。
## 看板の壁が空へ戻る → 3秒のカウントダウン → 壁3枚（30m 間隔。3枚目はボス壁・4択）。負けたら「惜しい」→「もう一回」
## → 仕上げの最初から（ハート3つ）。3回失敗したら、自動の速さの調子を一番遅い値に（MatchRules.slow_auto_speed）。
class Final extends Course1Step:
	const TOTAL := 3
	## &"intro"・&"count"（カウントダウン）・&"play"・&"lost"・&"done"
	var phase := &"intro"
	var lost_heart := false
	var boss_said := false

	func _init() -> void:
		id = "1-7"

	func quizzes() -> Array[QuizItem]:
		var list: Array[QuizItem] = [
			make_quiz("c1.final.q1", "c1.final.c1", 0),
			make_quiz("c1.final.q2", "c1.final.c2", 1),
			make_quiz("c1.final.q3", "c1.final.c3", 1),
		]
		return list

	## カウントダウンが終わるまでは、コンベアを止めて操作もロックする（本番のカウントダウンと同じく、動かずに待つ）
	func lesson_rules(d: PracticeDirector) -> MatchRules:
		var rules := MatchRules.new()
		rules.hp_enabled = true
		rules.mistakes = MatchRules.Mistakes.NORMAL
		rules.ocean = MatchRules.Ocean.NORMAL
		rules.world_speed = 0.0
		rules.input_locked = true
		rules.record_results = false
		# 本編側の MatchRules.slow_auto_speed（まだないときは何もしない）
		rules.set(&"slow_auto_speed", d.slow_hint_active())
		return rules

	## 台本の文字は「仕上げ 1/3」なので、数のところだけ入れかえる（台本の 1-7 の「仕上げ 2/3」「仕上げ 3/3」）
	static func round_text(number: int) -> String:
		return PracticeTexts.get_text("c1.final.hud").replace("1/%d" % TOTAL, "%d/%d" % [number, TOTAL])

	func enter(d: PracticeDirector) -> void:
		phase = &"intro"
		d.set_rules(lesson_rules(d))
		var none: Array[QuizItem] = []
		d.set_quizzes(none)
		d.revive(1)
		d.hatena.set_cloud(false)
		d.follow_walls()
		_intro(d, d.step_serial)

	func _intro(d: PracticeDirector, serial: int) -> void:
		d.hatena.play(&"cheer")
		d.say("c1.final.1")
		d.close_sign()
		await d.wait(2.0)
		if not d.is_current(serial):
			return
		d.say("c1.final.2")
		await d.wait(2.0)
		if d.is_current(serial):
			_start_round(d, serial)

	## 仕上げの回を始める（やり直しも）：壁3枚が空から落ち、カウントダウンのあとに本番の自動の速さで進む。
	func _start_round(d: PracticeDirector, serial: int) -> void:
		phase = &"count"
		lost_heart = false
		boss_said = false
		var rules := lesson_rules(d)
		var bosses: Array[int] = [FINAL_BOSS]
		d.restart_round(quizzes(), rules, bosses)
		d.place_player(1, 0.0, 0.0)
		d.overlay.set_round_label(round_text(1))
		await d.countdown("c1.final.count")
		if not d.is_current(serial) or phase != &"count":
			return
		phase = &"play"
		rules.world_speed = -1.0
		rules.input_locked = false

	func rewind(d: PracticeDirector) -> void:
		_start_round(d, d.step_serial)

	func hint_door_x(d: PracticeDirector) -> float:
		return d.answer_door_x() if phase in [&"count", &"play"] else NAN

	func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void:
		match event:
			&"health_changed":
				if int(data.player) == 1 and int(data.hp) < int(data.previous) and phase == &"play":
					lost_heart = true
			&"question_completed":
				if phase == &"play":
					_passed(d, d.step_serial, int(data.wall_index), bool(data.correct))
			&"round_lost":
				if phase in [&"count", &"play"]:
					_lost(d, d.step_serial)
			&"state_changed":
				# 本編側に practice_round_lost がないときの代わり（ゲームオーバーになったら負け）
				if not d.has_round_lost_signal() and str(data.state) == Constants.STATE_GAME_OVER and phase == &"play":
					_lost(d, d.step_serial)

	## 壁を突破した（ハートが残っていれば、正解でもミスでも）。ボス壁を突破したらクリアへ。
	func _passed(d: PracticeDirector, serial: int, wall_index: int, correct: bool) -> void:
		if wall_index >= FINAL_BOSS:
			phase = &"done"
			d.star_earned = not lost_heart
			d.complete_step()
			return
		d.overlay.set_round_label(round_text(wall_index + 2))
		d.hatena.play(&"clap" if correct else &"oops")
		await d.say("c1.final.ok" if correct else "c1.final.miss")
		if not d.is_current(serial) or phase != &"play":
			return
		# ボス壁が、いまの壁になった
		if not boss_said and d.game_state.current_wall_index == FINAL_BOSS:
			boss_said = true
			d.hatena.play(&"point")
			d.say("c1.final.boss")

	func _lost(d: PracticeDirector, serial: int) -> void:
		phase = &"lost"
		await d.wait(LOST_PAUSE)
		if not d.is_current(serial):
			return
		d.hatena.play(&"oops")
		await d.say("c1.final.ng")
		if d.is_current(serial):
			d.fail_step("c1.any.retry")
