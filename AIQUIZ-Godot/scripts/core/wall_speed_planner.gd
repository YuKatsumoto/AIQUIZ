extends RefCounted
class_name WallSpeedPlanner

## 自動モードの壁速度を決める。
##   壁が届くまでの秒数 = 読んで答えを決める秒数 × プレイヤーの調子 + ドアまで動く秒数 + 余裕
##   速度 = 次の壁までの実際の距離 ÷ その秒数
## AI が付ける予測解答時間(t)は大半が 4.0 / 6.0 の決め打ちで、実際の解答時間とほぼ相関がない。
## そこで問題文・選択肢・学年・計算の手数から自前で見積もり、AI の値は遅くする方向にだけ使う。
## 回のあいだに縮めるのは「余裕」だけにして、終盤の難問でも考える時間は削らない。

## 壁が届くまでの秒数の範囲（距離30なら 約3.8〜1.6 m/s）。距離が短い2人プレイの1問目も同じ秒数になる。
const FASTEST_SECONDS := 7.9
const SLOWEST_SECONDS := 19.0
## 読む速さ（文字/秒）= READ_BASE + 学年 × READ_PER_GRADE。動く壁の文字なので本よりゆっくり見積もる。
const READ_BASE := 3.5
const READ_PER_GRADE := 1.0
## 選択肢は短く見比べるだけなので、問題文より軽く数える。
const CHOICE_READ_WEIGHT := 0.8
## 先頭の【単元名】は流し読みされる。
const TAG_READ_WEIGHT := 0.4
## 英単語1語 = LATIN_WORD_UNITS + 文字数 × LATIN_LETTER_UNITS 文字分。英語の教科ではさらに遅く読む。
const LATIN_WORD_UNITS := 1.0
const LATIN_LETTER_UNITS := 0.35
const ENGLISH_READ_SCALE := 1.3
## 数字1つ = NUMBER_UNITS + 桁数 × DIGIT_UNITS 文字分。
const NUMBER_UNITS := 0.6
const DIGIT_UNITS := 0.35
## 選択肢を見比べる秒数 = CHOOSE_BASE + 選択肢数 × CHOOSE_PER_CHOICE。
const CHOOSE_BASE := 0.4
const CHOOSE_PER_CHOICE := 0.4
## 考える秒数の内訳。
const THINK_BASE := 0.8
const ADD_SECONDS := 0.9
const ADD_PER_DIGIT := 0.35
const MUL_SECONDS := 1.4
const MUL_PER_DIGIT := 0.6
const MAX_COUNTED_OPERATIONS := 4
const CARRY_SECONDS := 0.5
const UNKNOWN_BOX_SECONDS := 0.6
## 低学年ほど計算に時間がかかる（1年 ×1.3 〜 4年以上 ×1.0）。
const ARITHMETIC_GRADE_SLOWDOWN := 0.1
const FRACTION_SECONDS := 0.7
const DECIMAL_SECONDS := 0.4
const WORD_PROBLEM_FIRST := 1.2
const WORD_PROBLEM_EXTRA := 0.5
const WORD_PROBLEM_MAX := 2.4
const EXTRA_NUMBER_SECONDS := 0.5
const EXTRA_NUMBER_MAX := 1.6
const IMPLICIT_STEP_SECONDS := 1.0
const MAX_IMPLICIT_STEPS := 3
const NEGATION_SECONDS := 1.0
const REASONING_SECONDS := 0.5
const NUMERIC_CHOICES_SECONDS := 0.5
const HARD_ROUND_SECONDS := 0.8
const ENGLISH_THINK_SECONDS := 0.4
const COOP_THINK_SECONDS := 1.0
## AI の t は元の4択に付いた値なので、2択で出すときは見比べる分を引く。
const AI_HINT_TWO_CHOICE_DISCOUNT := 0.8
const ANSWER_MIN := 2.5
const ANSWER_MAX := 16.0
## ドアの前まで横に動く秒数（4択はドアが端まで並ぶ）。
const MOVE_TWO_CHOICES := 1.0
const MOVE_FOUR_CHOICES := 1.4
## 余裕は回の進み具合に合わせて MARGIN_START から MARGIN_END へ縮める。
const MARGIN_START := 1.6
const MARGIN_END := 0.6
## エンドレスで余裕を縮めきるまでの壁の枚数。
const ENDLESS_RAMP_WALLS := 20
## プレイヤーの調子（読んで答える秒数に掛ける）。次の回へは半分だけ持ち越す。
const PACE_MIN := 0.8
const PACE_MAX := 1.3
const PACE_WRONG := 0.06
const PACE_RETREAT := 0.05
const PACE_EARLY := -0.04
const PACE_CARRY_OVER := 0.5
## 壁が届く前のこの割合までに正解したら「余裕があった」とみなす。
const EARLY_RATIO := 0.55
## これより早い不正解は焦りではなく早とちりなので、時間を足さない。
const RUSHED_WRONG_RATIO := 0.5
## 後ろへ下がって時間を稼いだとみなす合計秒数。
const RETREAT_SECONDS := 0.4
const DEFAULT_DISTANCE := 30.0
const MIN_DISTANCE := 10.0

const WORD_PROBLEM_KEYS: Array[String] = [
	"割合", "百分率", "歩合", "%", "％", "比", "速さ", "時速", "分速", "秒速", "平均", "面積", "体積",
	"容積", "円周", "直径", "半径", "倍", "道のり", "残り", "のこり", "あわせて", "合わせて",
	"ちがい", "違い", "差は", "和は", "積は", "商は", "おつり", "代金", "単位", "ずつ", "等分",
	"分けると", "わけると", "たすと", "ひくと", "かけると", "わると", "分後", "分前", "時間後",
	"何時何分", "時こく", "時刻", "あまり",
]
## 数量を答えさせる言い方（文章題の手がかり）。
const QUANTITY_KEYS: Array[String] = [
	"何円", "全部で", "ぜんぶで", "みんなで", "何こ", "何個", "何本", "何人", "何まい", "何枚", "何cm", "何m", "何L",
	"何kg", "何g", "何dL", "何mL", "何km", "何さつ", "何冊", "何台", "何ひき", "何匹",
]
const ADD_OPERATORS: Array[String] = ["+", "＋", "-", "−", "－"]
const SUBTRACT_OPERATORS: Array[String] = ["-", "−", "－"]
const NEGATION_KEYS: Array[String] = [
	"ではないもの", "でないもの", "ないものは", "まちがって", "間違って", "誤って", "正しくない",
	"あてはまらない", "当てはまらない", "ふさわしくない", "まちがい", "間違い", "ちがうもの", "違うもの",
]
const REASONING_KEYS: Array[String] = [
	"なぜ", "どうして", "理由", "一番", "いちばん", "もっとも", "最も", "順番", "並べ", "すべて",
	"全部", "いくつ", "何個", "何こ", "何本", "何人",
]

static var _regex_cache: Dictionary = {}

var pace := 1.0
## 直近に決めた値（ログと検証用）。
var last_answer_seconds := 0.0
var last_budget_seconds := 0.0
var _elapsed := 0.0
var _retreat_elapsed := 0.0


## 新しい回の始まり。調子は半分だけ持ち越す。
func begin_round() -> void:
	pace = lerpf(pace, 1.0, PACE_CARRY_OVER)
	_elapsed = 0.0
	_retreat_elapsed = 0.0


func reset() -> void:
	pace = 1.0
	_elapsed = 0.0
	_retreat_elapsed = 0.0


## 問題が出た瞬間に呼ぶ。distance は答える人が壁に当たるまでの距離。progress は回の進み具合 0〜1。
func plan(quiz: QuizItem, subject: String, grade: int, difficulty: String, num_choices: int,
		distance: float, progress: float) -> float:
	last_answer_seconds = estimate_answer_seconds(quiz, subject, grade, difficulty, num_choices)
	var move := MOVE_FOUR_CHOICES if num_choices >= 4 else MOVE_TWO_CHOICES
	var margin := lerpf(MARGIN_START, MARGIN_END, clampf(progress, 0.0, 1.0))
	last_budget_seconds = clampf(last_answer_seconds * pace + move + margin, FASTEST_SECONDS, SLOWEST_SECONDS)
	_elapsed = 0.0
	_retreat_elapsed = 0.0
	return (distance if distance >= MIN_DISTANCE else DEFAULT_DISTANCE) / last_budget_seconds


## 問題が出ている間、毎フレーム呼ぶ。
func track(dt: float, retreating: bool) -> void:
	_elapsed += dt
	if retreating:
		_retreat_elapsed += dt


## 1問が終わったら呼ぶ。下がって時間を稼いだ・焦って間違えたなら次から遅く、余裕で正解なら少し速くする。
func record_result(correct: bool) -> void:
	if last_budget_seconds <= 0.0:
		return
	var ratio := _elapsed / last_budget_seconds
	var delta := 0.0
	if _retreat_elapsed >= RETREAT_SECONDS:
		delta += PACE_RETREAT
	if not correct and ratio >= RUSHED_WRONG_RATIO:
		delta += PACE_WRONG
	elif correct and delta == 0.0 and ratio <= EARLY_RATIO:
		delta += PACE_EARLY
	pace = clampf(pace + delta, PACE_MIN, PACE_MAX)


## 対象学年の子が問題を読んで答えを決めるまでの秒数（ドアまで動く時間は含まない）。
static func estimate_answer_seconds(quiz: QuizItem, subject: String, grade: int, difficulty: String,
		num_choices: int) -> float:
	if quiz == null:
		return 4.0
	var english := subject == "英語"
	var question := quiz.coop_prompt if not quiz.coop_prompt.is_empty() else quiz.q
	var tag_match := _regex("^\\s*(【[^】]*】|\\[[^\\]]*\\])\\s*").search(question)
	var body := question
	var units := 0.0
	if tag_match != null:
		body = question.substr(tag_match.get_end())
		units += _reading_units(tag_match.get_string(), english) * TAG_READ_WEIGHT
	units += _reading_units(body, english)
	var choices := quiz.c
	var is_coop := quiz.has_coop_data()
	if is_coop:
		# 2人はそれぞれ自分の2枚を読む。遅いほうに合わせる。
		units += maxf(_choices_units(quiz.coop_p1_choices, english), _choices_units(quiz.coop_p2_choices, english))
		choices = quiz.coop_p1_choices
	else:
		units += _choices_units(choices, english)
	var read_speed := READ_BASE + READ_PER_GRADE * clampf(float(grade), 1.0, 6.0)
	var shown_choices := 2 if is_coop else maxi(num_choices, 2)
	var seconds := units / read_speed
	seconds += CHOOSE_BASE + CHOOSE_PER_CHOICE * shown_choices
	seconds += _think_seconds(body, question, choices, subject, grade, difficulty)
	var hint := quiz.estimated_seconds
	if is_coop:
		seconds += COOP_THINK_SECONDS
	elif shown_choices <= 2:
		hint -= AI_HINT_TWO_CHOICE_DISCOUNT
	return clampf(maxf(seconds, hint), ANSWER_MIN, ANSWER_MAX)


static func _choices_units(choices: PackedStringArray, english: bool) -> float:
	var units := 0.0
	for choice: String in choices:
		units += _reading_units(choice, english)
	return units * CHOICE_READ_WEIGHT


static func _reading_units(text: String, english: bool) -> float:
	var units := 0.0
	var latin := _regex("[A-Za-z]+(?:'[A-Za-z]+)?")
	for m: RegExMatch in latin.search_all(text):
		units += (LATIN_WORD_UNITS + LATIN_LETTER_UNITS * m.get_string().length()) * (ENGLISH_READ_SCALE if english else 1.0)
	var rest := latin.sub(text, "", true)
	var number := _regex("\\d+(?:[.,]\\d+)?")
	for m: RegExMatch in number.search_all(rest):
		units += NUMBER_UNITS + DIGIT_UNITS * _digit_count(m.get_string())
	rest = number.sub(rest, "", true)
	rest = _regex("\\s").sub(rest, "", true)
	return units + rest.length()


## body は【単元名】を除いた問題文（数や式を数える）。question は単元名込み（言葉の手がかりを探す）。
static func _think_seconds(body: String, question: String, choices: PackedStringArray, subject: String,
		grade: int, difficulty: String) -> float:
	var seconds := THINK_BASE
	var operations := _operations(body)
	seconds += _arithmetic_seconds(operations, body, grade)
	seconds += mini(3, _regex("\\d+\\s*[/／]\\s*\\d+|\\d+\\s*分の\\s*\\d+").search_all(body).size()) * FRACTION_SECONDS
	seconds += mini(3, _regex("\\d+\\.\\d+").search_all(body).size()) * DECIMAL_SECONDS
	var word_hits := _count_keys(question, WORD_PROBLEM_KEYS)
	if word_hits > 0:
		seconds += minf(WORD_PROBLEM_MAX, WORD_PROBLEM_FIRST + WORD_PROBLEM_EXTRA * (word_hits - 1))
	var numbers := _regex("\\d+(?:\\.\\d+)?").search_all(body).size()
	if operations.is_empty() and numbers >= 2 and (word_hits > 0 or _count_keys(question, QUANTITY_KEYS) > 0):
		# 式の記号がない文章題は、出てくる数をつなぐ計算を頭の中で組み立てる。
		seconds += IMPLICIT_STEP_SECONDS * mini(numbers - 1, MAX_IMPLICIT_STEPS) * _arithmetic_slowdown(grade)
	elif numbers >= 3 and operations.size() < 2:
		seconds += minf(EXTRA_NUMBER_MAX, EXTRA_NUMBER_SECONDS * (numbers - 2))
	if _count_keys(question, NEGATION_KEYS) > 0:
		seconds += NEGATION_SECONDS
	if _count_keys(question, REASONING_KEYS) > 0:
		seconds += REASONING_SECONDS
	if choices.size() >= 4 and _all_numeric(choices):
		# 近い数が並ぶと、最後まで計算しないと選べない。
		seconds += NUMERIC_CHOICES_SECONDS
	if difficulty == "難しい":
		seconds += HARD_ROUND_SECONDS
	if subject == "英語":
		seconds += ENGLISH_THINK_SECONDS
	return seconds


## 式の「数 記号 数」を左から拾う（□ は求める数）。
static func _operations(body: String) -> Array[RegExMatch]:
	var found: Array[RegExMatch] = []
	var pattern := "(\\d+(?:\\.\\d+)?|[□○◯])\\s*([+＋\\-−－×xX＊*÷])\\s*(?=(\\d+(?:\\.\\d+)?|[□○◯]))"
	for m: RegExMatch in _regex(pattern).search_all(body):
		found.append(m)
		if found.size() >= MAX_COUNTED_OPERATIONS:
			break
	return found


static func _arithmetic_seconds(operations: Array[RegExMatch], body: String, grade: int) -> float:
	var seconds := 0.0
	for m: RegExMatch in operations:
		var left := m.get_string(1)
		var right := m.get_string(3)
		var op := m.get_string(2)
		var digits := maxi(_digit_count(left), _digit_count(right))
		if op in ADD_OPERATORS:
			seconds += ADD_SECONDS + ADD_PER_DIGIT * (digits - 1)
			if _needs_carry(left, right, op in SUBTRACT_OPERATORS):
				seconds += CARRY_SECONDS
		else:
			seconds += MUL_SECONDS + MUL_PER_DIGIT * (digits - 1)
	if not operations.is_empty() and _regex("[□○◯]").search(body) != null:
		# □を求める問題は、式を逆にたどる。
		seconds += UNKNOWN_BOX_SECONDS
	return seconds * _arithmetic_slowdown(grade)


static func _arithmetic_slowdown(grade: int) -> float:
	return 1.0 + ARITHMETIC_GRADE_SLOWDOWN * clampf(4.0 - float(grade), 0.0, 3.0)


## 繰り上がり（足し算）・繰り下がり（引き算）がある整数の計算か。
static func _needs_carry(left: String, right: String, subtract: bool) -> bool:
	if not left.is_valid_int() or not right.is_valid_int():
		return false
	var a := absi(int(left))
	var b := absi(int(right))
	if subtract and b > a:
		var swap := a
		a = b
		b = swap
	while a > 0 or b > 0:
		var da := a % 10
		var db := b % 10
		if (da < db) if subtract else (da + db >= 10):
			return true
		a = int(a / 10.0)
		b = int(b / 10.0)
	return false


static func _all_numeric(choices: PackedStringArray) -> bool:
	var digits := _regex("\\d")
	for choice: String in choices:
		if digits.search(choice) == null:
			return false
	return true


static func _count_keys(text: String, keys: Array[String]) -> int:
	var hits := 0
	for key: String in keys:
		if key in text:
			hits += 1
	return hits


static func _digit_count(text: String) -> int:
	var count := 0
	for ch: String in text:
		if ch >= "0" and ch <= "9":
			count += 1
	return maxi(count, 1)


static func _regex(pattern: String) -> RegEx:
	var cached: RegEx = _regex_cache.get(pattern)
	if cached == null:
		cached = RegEx.create_from_string(pattern)
		_regex_cache[pattern] = cached
	return cached
