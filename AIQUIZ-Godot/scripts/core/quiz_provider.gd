extends Node
class_name QuizProvider

## オフラインクイズプロバイダー
## Python版 quiz_provider.py の OfflineQuizProvider 相当

const DEFAULT_BANK_PATH := "res://offline_bank.json"

var bank_path: String
var bank: Dictionary = {}
var external_bank_items: Array[Dictionary] = []
var _count_cache: Dictionary = {}
## get_quizzes の下ごしらえ（_pool_for）を条件ごとに覚えておく。問題の元データが変わったら捨てる。
var _pool_cache: Dictionary = {}
var _pool_cache_bank: Dictionary = {}
## 覚えておく条件の数（メニュー背景のように条件を次々に変える使い方でもメモリを使いすぎない）
const POOL_CACHE_MAX := 3

## コンパイル済みの正規表現（パターン → RegEx）。問題ごとに作り直さない。
static var _regex_cache: Dictionary = {}

## 読み込んだバンク（パス → Dictionary）。offline_bank.json は 5 MB あり、プロバイダは
## 本編・バッファ・メニュー背景などで何度も作られるので、解析は 1 回だけにして中身を共有する。
## 共有なので、bank の中身（教科・学年・問題の辞書）は書き換えないこと。
static var _bank_cache: Dictionary = {}
static var _bank_cache_mutex: Mutex = Mutex.new()

func _init(path: String = DEFAULT_BANK_PATH) -> void:
	bank_path = path
	bank = _load_bank()

func _load_bank() -> Dictionary:
	return shared_bank(bank_path)


## path のバンクを返す（2 回目からは解析済みのものを共有）。読めなければ空の辞書（キャッシュしない）。
static func shared_bank(path: String = DEFAULT_BANK_PATH) -> Dictionary:
	_bank_cache_mutex.lock()
	if not _bank_cache.has(path):
		var parsed := _parse_bank_file(path)
		if not parsed.is_empty():
			_bank_cache[path] = parsed
	var result: Dictionary = _bank_cache.get(path, {})
	_bank_cache_mutex.unlock()
	return result


static func _parse_bank_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[QuizProvider] Bank file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("[QuizProvider] Failed to open bank: %s" % path)
		return {}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_warning("[QuizProvider] JSON parse error: %s" % json.get_error_message())
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func total_count() -> int:
	var total := 0
	for subj_data: Variant in bank.values():
		if subj_data is Dictionary:
			for grade_list: Variant in subj_data.values():
				if grade_list is Array:
					total += grade_list.size()
	var external_seen: Dictionary = {}
	for item: Dictionary in external_bank_items:
		var q_text := str(item.get("q", "")).strip_edges()
		if not q_text.is_empty():
			external_seen[q_text] = true
	return total + external_seen.size()


func set_external_items(items: Array[Dictionary]) -> void:
	external_bank_items = items.duplicate(true)
	_count_cache.clear()
	_pool_cache.clear()


func offline_count_for(subject: String, grade: int, difficulty: String, mode: String) -> int:
	return count_for(subject, grade, difficulty, mode)


## メニューのストック表示用。get_quizzes と同じ条件で組んだ通常プールの件数（他難易度のフォールバックは除く）。
func count_for(subject: String, grade: int, difficulty: String, mode: String) -> int:
	var require_four := difficulty == "難しい" or mode == Constants.MODE_TEN
	var cache_key := "%s|%d|%s|%s" % [subject, grade, difficulty, require_four]
	if _count_cache.has(cache_key):
		return int(_count_cache[cache_key])
	# get_quizzes と同じ下ごしらえを使う（メニューで選んだ条件のプールがそのまま温まる）
	var unique_texts: Dictionary = {}
	for entry: Dictionary in _pool_for(subject, grade, difficulty, require_four)["bucket"]:
		unique_texts[(entry["source"] as QuizItem).q.strip_edges()] = true
	_count_cache[cache_key] = unique_texts.size()
	return unique_texts.size()


## ラウンドの準備中に、この条件のプールを作っておく（プレイ中に初回の下ごしらえが来ないように）。
func warm_pool(subject: String, grade: int, difficulty: String, mode: String) -> void:
	var require_four := difficulty == "難しい" or mode == Constants.MODE_TEN
	# 2択を4択に広げた候補があるプールは、ラウンドごとに広げ直して帯分けし直す（従来と同じ）
	var cache_key := "%s|%d|%s|%s" % [subject, grade, difficulty, require_four]
	if _pool_cache.has(cache_key) and bool(_pool_cache[cache_key]["expanded"]):
		_pool_cache.erase(cache_key)
	_pool_for(subject, grade, difficulty, require_four)

func begin_round(_subject: String, _grade: int, _difficulty: String,
		_mode: String, _target_count: int) -> void:
	pass

func end_round() -> void:
	pass

func stop() -> void:
	pass

func submit_result(_quiz: QuizItem, _correct: bool) -> void:
	pass

# ---------- Normalize ----------

func _normalize(raw: Variant) -> QuizItem:
	if not raw is Dictionary:
		return null
	var q_text: String = str(raw.get("q", "")).strip_edges()
	var c_raw: Variant = raw.get("c", [])
	var a_raw: Variant = raw.get("a", null)

	if q_text.is_empty() or not c_raw is Array:
		return null
	if c_raw.size() != 2 and c_raw.size() != 4:
		return null

	var a_int: int
	if a_raw is float:
		a_int = int(a_raw)
	elif a_raw is int:
		a_int = a_raw
	elif a_raw is String and a_raw.is_valid_int():
		a_int = int(a_raw)
	else:
		return null

	if a_int < 0 or a_int >= c_raw.size():
		return null

	var e_text: String = str(raw.get("e", raw.get("exp", ""))).strip_edges()
	var src_text: String = str(raw.get("src", "OFFLINE")).strip_edges()
	if src_text.is_empty():
		src_text = "OFFLINE"

	var cleaned := PackedStringArray()
	for x: Variant in c_raw:
		var s := str(x).strip_edges()
		if s.is_empty():
			return null
		cleaned.append(s)

	var img_text: String = str(raw.get("img", "")).strip_edges()
	var ci_raw: Variant = raw.get("choice_img", raw.get("choiceImg", []))
	var choice_imgs := PackedStringArray()
	if ci_raw is Array:
		for ci: Variant in ci_raw:
			choice_imgs.append(str(ci))

	var item := QuizItem.create(q_text, cleaned, a_int, e_text, src_text, img_text, choice_imgs)
	item.genre = str(raw.get("genre", raw.get("g", ""))).strip_edges()
	var estimated := float(raw.get("estimated_seconds", raw.get("t", 4.0)))
	item.estimated_seconds = clampf(estimated, 1.5, 10.0)
	return item

static func _regex(pattern: String) -> RegEx:
	var cached: RegEx = _regex_cache.get(pattern)
	if cached == null:
		cached = RegEx.create_from_string(pattern)
		_regex_cache[pattern] = cached
	return cached

# ---------- Estimated solving time (heuristic for offline) ----------

func _estimate_seconds(item: QuizItem, subject: String, difficulty: String) -> float:
	## オフライン問題のAI予測解答時間をヒューリスティクスで推定する
	var base: float
	match difficulty:
		"簡単": base = 2.5
		"普通": base = 3.5
		"難しい": base = 5.0
		_: base = 3.5
	
	# テキスト量補正（35文字基準、1文字あたり+0.04秒）
	var total_chars: int = item.q.length()
	for ch: String in item.c:
		total_chars += ch.length()
	base += maxf(0.0, float(total_chars - 35)) * 0.04
	
	# 教科ごとの思考時間加算
	if subject == "算数":
		# 計算記号が含まれる場合は+1秒
		if _regex("[＋\\+\\-×÷＝]").search(item.q):
			base += 1.0
	elif subject == "国語":
		# 漢字の読み問題は速い
		if "読み" in item.q:
			base -= 0.5
	elif subject == "英語":
		# 英文は日本語より読み取りに時間がかかるため、複数語の文だけ少し加算する。
		var english_text := "%s %s" % [item.q, " ".join(item.c)]
		var english_word_count := _regex("[A-Za-z]+(?:'[A-Za-z]+)?").search_all(english_text).size()
		if english_word_count >= 4:
			base += minf(1.2, float(english_word_count - 3) * 0.15)
	
	# 4択は2択より+0.8秒
	if item.c.size() == 4:
		base += 0.8
	
	return clampf(base, 1.5, 10.0)

# ---------- Difficulty bucketing ----------

func _complexity_score(item: QuizItem, subject: String, grade: int) -> float:
	var text: String = "%s %s %s" % [item.q, " ".join(PackedStringArray(item.c)), item.e]
	var q_text: String = item.q

	var score: float = 0.0
	score += float(q_text.length()) / 40.0
	score += float(item.e.length()) / 80.0

	# Count digits
	score += _regex("\\d").search_all(text).size() * 0.08

	# Count operators
	score += _regex("[\\+\\-\\*/÷×%]").search_all(text).size() * 0.25

	# Count brackets
	score += _regex("[()（）]").search_all(text).size() * 0.2

	# 英語3年は「応」「基」をまだ習わないので、ひらがなのタグを使う
	var is_advanced := "【応用】" in q_text or "【おうよう】" in q_text
	var is_basic := "【基本】" in q_text or "【きほん】" in q_text
	if is_advanced:
		score += 1.2
	if is_basic:
		score -= 0.6

	if subject == "算数":
		for token: String in ["割合", "比", "速さ", "体積", "平均", "合同", "比例", "反比例"]:
			if token in text:
				score += 0.9
		# 概念理解・思考力系のキーワードにボーナス（暗算で解けつつ難しい問題）
		for token: String in ["なぜ", "どちら", "正しい", "間違い", "性質", "規則", "関係", "条件"]:
			if token in text:
				score += 0.5
		# 3桁以上の数字を含む問題は暗算困難 → ハードバケットから除外
		var big_matches := _regex("\\d{3,}").search_all(text)
		if big_matches.size() > 0:
			# 大きな数が多いほどペナルティを強くする
			score -= big_matches.size() * 1.5
	elif subject == "理科":
		for token: String in ["実験", "観察", "原因", "結果", "規則", "電磁石", "水溶液", "燃焼", "光合成"]:
			if token in text:
				score += 0.7
	elif subject == "国語":
		for token: String in ["敬語", "四字熟語", "古典", "短歌", "俳句", "歴史的仮名遣い", "比喩"]:
			if token in text:
				score += 0.9
	elif subject == "社会":
		for token: String in ["歴史", "公民", "憲法", "三権分立", "貿易", "工業", "農業", "地層", "気候"]:
			if token in text:
				score += 0.8
	elif subject == "英語":
		for token: String in ["会話", "語順", "空欄", "文脈", "自然な", "答え方", "過去", "将来", "理由"]:
			if token in text:
				score += 0.7
		if is_basic:
			score -= 1.0
		elif is_advanced:
			score += 1.0

	score -= maxf(0.0, float(grade - 1)) * 0.08
	return score

func _bucket_by_difficulty(items: Array[QuizItem], subject: String,
		grade: int, difficulty: String) -> Array[QuizItem]:
	if items.size() <= 2:
		return items

	var bucket: Array[QuizItem] = []
	for i: int in _bucket_indices(items, subject, grade, difficulty):
		bucket.append(items[i])

	return bucket if not bucket.is_empty() else items


## _bucket_by_difficulty と同じ帯分けを、items の添字で返す（2問以下・帯が空なら全部）。
func _bucket_indices(items: Array[QuizItem], subject: String,
		grade: int, difficulty: String) -> PackedInt32Array:
	var indices := PackedInt32Array()
	if items.size() > 2:
		# Score and sort
		var scored: Array = []
		for i: int in range(items.size()):
			scored.append({"score": _complexity_score(items[i], subject, grade), "index": i})
		scored.sort_custom(func(a_val: Dictionary, b_val: Dictionary) -> bool:
			return a_val["score"] < b_val["score"])

		var n: int = scored.size()
		var low_end: int = maxi(1, n / 3)
		var high_start: int = maxi(low_end, (2 * n) / 3)

		if difficulty == "簡単":
			for i: int in range(low_end):
				indices.append(int(scored[i]["index"]))
		elif difficulty == "難しい":
			for i: int in range(high_start, n):
				indices.append(int(scored[i]["index"]))
		else:
			for i: int in range(low_end, high_start):
				indices.append(int(scored[i]["index"]))

	if indices.is_empty():
		for i: int in range(items.size()):
			indices.append(i)
	return indices

# ---------- Hard distractor enhancement ----------

func _is_numeric_choice(text: String) -> bool:
	## Check if a choice text is essentially a number (with optional unit suffix)
	var stripped := text.strip_edges()
	# Remove common unit suffixes for checking
	var units := ["cm", "c㎡", "m", "km", "kg", "g", "L", "dL", "mL", "mm",
		"度", "個", "こ", "人", "台", "本", "枚", "まい", "匹", "冊", "円",
		"時間", "分", "秒", "わ", "箱"]
	for u: String in units:
		if stripped.ends_with(u):
			stripped = stripped.substr(0, stripped.length() - u.length()).strip_edges()
			break
	# Check if remaining part is a valid number
	if stripped.is_valid_int() or stripped.is_valid_float():
		return true
	return false

func _extract_number(text: String) -> float:
	## Extract the numeric portion from a choice text
	var stripped := text.strip_edges()
	var units := ["cm", "c㎡", "m", "km", "kg", "g", "L", "dL", "mL", "mm",
		"度", "個", "こ", "人", "台", "本", "枚", "まい", "匹", "冊", "円",
		"時間", "分", "秒", "わ", "箱"]
	for u: String in units:
		if stripped.ends_with(u):
			stripped = stripped.substr(0, stripped.length() - u.length()).strip_edges()
			break
	if stripped.is_valid_float():
		return float(stripped)
	if stripped.is_valid_int():
		return float(int(stripped))
	return 0.0

func _extract_unit(text: String) -> String:
	## Extract the unit suffix from a choice text
	var stripped := text.strip_edges()
	var units := ["c㎡", "cm", "km", "kg", "dL", "mL", "mm", "m", "g", "L",
		"度", "個", "こ", "人", "台", "本", "枚", "まい", "匹", "冊", "円",
		"時間", "分", "秒", "わ", "箱"]
	for u: String in units:
		if stripped.ends_with(u):
			return u
	return ""

## 選択肢の数から性質や大きさで選ばせる問題（「〜でない数はどれ」「3の倍数はどれ」「いちばん大きい」「およそ」など）。
## 誤答を「正解±数」に置き換えると、置き換えた数も条件に当てはまり、正解がいくつもある問題になる
## （例：「16と40の公約数でない数はどれ」が 13・15・16・18 になると、4つとも公約数でない）。
const HARDEN_SKIP_WORDS: Array[String] = [
	"どれ", "どの", "でない", "ではない", "じゃない", "ちがう", "違う", "まちがい", "間違", "正しくない",
	"いちばん", "一番", "最も", "もっとも", "およそ", "約", "がい数", "概数", "倍数", "約数", "偶数", "奇数",
	"素数", "四捨五入", "切り上げ", "切り捨て", "以上", "以下", "未満", "より大きい", "より小さい",
]


static func _is_selection_question(text: String) -> bool:
	for word: String in HARDEN_SKIP_WORDS:
		if text.contains(word):
			return true
	return false


func _harden_distractors(item: QuizItem) -> QuizItem:
	## Replace obviously wrong choices with more plausible near-miss values
	if item.c.size() < 4 or not item.choice_img.is_empty():
		return item  # Image choices must retain their original labels and order.
	if _is_selection_question(item.q):
		return item  # 選ばせ方の問題は、作った人の選択肢のまま（近い数で正解が増えないように）。

	var correct_text: String = item.c[item.a]

	# Check if all choices are numeric
	var all_numeric := true
	for ch: String in item.c:
		if not _is_numeric_choice(ch):
			all_numeric = false
			break

	if not all_numeric:
		# For text-based questions, just shuffle the order to prevent positional bias
		return item

	# For numeric questions: generate near-miss distractors
	var correct_val: float = _extract_number(correct_text)
	var unit: String = _extract_unit(correct_text)
	var is_integer: bool = correct_text.strip_edges().replace(unit, "").strip_edges().is_valid_int()

	# Collect current wrong values
	var wrong_vals: Array[float] = []
	for i: int in range(item.c.size()):
		if i != item.a:
			wrong_vals.append(_extract_number(item.c[i]))

	# Check if any wrong answer is "too far" from correct (more than 30% deviation or >10 absolute)
	var needs_replacement := false
	for wv: float in wrong_vals:
		var diff: float = absf(wv - correct_val)
		var relative_diff: float = diff / maxf(absf(correct_val), 1.0)
		if relative_diff > 0.4 or (diff > 10.0 and relative_diff > 0.25):
			needs_replacement = true
			break

	if not needs_replacement:
		return item  # Choices are already close enough

	# Generate new near-miss distractors
	var new_wrongs: Array[float] = []
	var attempts := 0
	while new_wrongs.size() < 3 and attempts < 50:
		attempts += 1
		var offset: float
		if is_integer:
			# For integers: ±1 to ±3, occasionally ±4~5
			var range_options := [-3, -2, -1, 1, 2, 3]
			if absf(correct_val) >= 20:
				range_options.append_array([-5, -4, 4, 5])
			if absf(correct_val) >= 100:
				range_options.append_array([-10, -8, 8, 10])
			offset = float(range_options.pick_random())
		else:
			# For decimals: ±0.1 to ±0.5
			offset = [-0.3, -0.2, -0.1, 0.1, 0.2, 0.3, 0.4, 0.5].pick_random()

		var candidate: float = correct_val + offset
		# Don't allow negative results for elementary school
		if candidate < 0:
			continue
		# Don't duplicate correct answer
		if absf(candidate - correct_val) < 0.001:
			continue
		# Don't duplicate existing new wrongs
		var is_dup := false
		for nw: float in new_wrongs:
			if absf(nw - candidate) < 0.001:
				is_dup = true
				break
		if is_dup:
			continue
		new_wrongs.append(candidate)

	if new_wrongs.size() < 3:
		return item  # Couldn't generate enough, keep original

	# Build new choices array
	new_wrongs.shuffle()
	var new_choices := PackedStringArray()
	var new_a: int = 0

	# Mix correct and wrong answers, randomize correct position
	var all_vals: Array[float] = [correct_val]
	all_vals.append_array(new_wrongs)

	# Sort numerically for natural presentation
	all_vals.sort()
	new_a = all_vals.find(correct_val)

	for v: float in all_vals:
		if is_integer:
			new_choices.append("%d%s" % [int(v), unit])
		else:
			new_choices.append("%s%s" % [str(v), unit])

	var hardened := item.duplicate(true) as QuizItem
	hardened.c = new_choices
	hardened.a = new_a
	return hardened


## 2択問題を4択に拡張する。数値選択肢のみ生成できる。失敗時は元の QuizItem を返す。
func expand_to_four_choices(item: QuizItem) -> QuizItem:
	if item == null or item.c.size() >= 4:
		return item
	if item.c.size() != 2 or item.a < 0 or item.a > 1:
		return item
	var correct_text: String = item.c[item.a]
	var wrong_text: String = item.c[1 - item.a]
	if not _is_numeric_choice(correct_text):
		return item
	var extras := _numeric_near_misses(correct_text, PackedStringArray([correct_text, wrong_text]), 2)
	if extras.size() < 2:
		return item
	var new_c := PackedStringArray([correct_text, wrong_text, extras[0], extras[1]])
	for i: int in range(new_c.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp: String = new_c[i]
		new_c[i] = new_c[j]
		new_c[j] = tmp
	var new_a: int = 0
	for i: int in range(new_c.size()):
		if new_c[i] == correct_text:
			new_a = i
			break
	var expanded: QuizItem = item.duplicate(true) as QuizItem
	if expanded == null:
		expanded = QuizItem.create(
			item.q, new_c, new_a, item.e, item.src, item.img, item.choice_img, item.estimated_seconds
		)
		expanded.genre = item.genre
		expanded.validated = item.validated
		return expanded
	expanded.c = new_c
	expanded.a = new_a
	expanded.estimated_seconds = clampf(item.estimated_seconds + 0.8, 1.5, 10.0)
	return expanded


func _numeric_near_misses(correct_text: String, banned: PackedStringArray, needed: int) -> PackedStringArray:
	var correct_val: float = _extract_number(correct_text)
	var unit: String = _extract_unit(correct_text)
	var is_integer: bool = correct_text.strip_edges().replace(unit, "").strip_edges().is_valid_int()
	var result: PackedStringArray = PackedStringArray()
	var attempts := 0
	while result.size() < needed and attempts < 60:
		attempts += 1
		var offset: float
		if is_integer:
			var range_options := [-3, -2, -1, 1, 2, 3]
			if absf(correct_val) >= 20.0:
				range_options.append_array([-5, -4, 4, 5])
			offset = float(range_options.pick_random())
		else:
			offset = [-0.3, -0.2, -0.1, 0.1, 0.2, 0.3, 0.4, 0.5].pick_random()
		var candidate: float = correct_val + offset
		if candidate < 0.0:
			continue
		var text: String = ("%d%s" % [int(candidate), unit]) if is_integer else ("%s%s" % [str(candidate), unit])
		var dup := false
		for b: String in banned:
			if b == text:
				dup = true
				break
		if dup:
			continue
		for existing: String in result:
			if existing == text:
				dup = true
				break
		if dup:
			continue
		result.append(text)
	return result

## Prepare a copy with the exact door count while retaining the answer and images.
## Text-only binary questions cannot safely invent two extra distractors.
func prepare_choice_count(item: QuizItem, expected: int) -> QuizItem:
	if item == null or item.a < 0 or item.a >= item.c.size():
		return null
	if item.c.size() not in [2, 4] or expected not in [2, 4]:
		return null
	var seen: Dictionary = {}
	for choice: String in item.c:
		var key := choice.strip_edges()
		if key.is_empty() or seen.has(key):
			return null
		seen[key] = true
	if item.c.size() == expected:
		return item
	if expected == 4:
		if not item.choice_img.is_empty():
			return null
		var expanded := expand_to_four_choices(item)
		return expanded if expanded != null and expanded.c.size() == 4 else null
	var wrong_indices: Array[int] = []
	for i: int in range(item.c.size()):
		if i != item.a:
			wrong_indices.append(i)
	var indices: Array[int] = [item.a, wrong_indices.pick_random()]
	indices.shuffle()
	var result := item.duplicate(true) as QuizItem
	result.c = PackedStringArray()
	result.choice_img = PackedStringArray()
	for source_index: int in indices:
		result.c.append(item.c[source_index])
		if not item.choice_img.is_empty():
			result.choice_img.append(item.choice_img[source_index] if source_index < item.choice_img.size() else "")
	result.a = indices.find(item.a)
	return result


## 2Pサドンデス用。指定の教科・学年のオフライン問題を、難易度の帯に絞って返す。
## 選択肢の数は元のまま（列の数への縮小は SuddenDeathQuestions が行う）。通信しない。
## 2Pサドンデスの問題を新しく生成する（オンライン生成のプロバイダーだけ）。生成しないなら false。
## on_progress(届いた数, 欲しい数)、on_done(Array[QuizItem]) は BufferedQuizProvider を参照。
func request_sudden_death_quizzes(_count: int, _exclude_texts: Array[String], _on_progress: Callable,
		_on_done: Callable) -> bool:
	return false


func offline_candidates(subject: String, grade: int, difficulty: String) -> Array[QuizItem]:
	var items: Array[QuizItem] = []
	var subj_data: Variant = bank.get(subject, {})
	var raw_items: Variant = (subj_data as Dictionary).get(str(grade), []) if subj_data is Dictionary else []
	if raw_items is Array:
		for raw: Variant in raw_items:
			var item := _normalize(raw)
			if item != null:
				item.estimated_seconds = _estimate_seconds(item, subject, difficulty)
				items.append(item)
	return _bucket_by_difficulty(items, subject, grade, difficulty)


## 2Pサドンデス用。問題が尽きたときの算数の自動生成（4択）。
func fallback_question(subject: String, grade: int) -> QuizItem:
	return _fallback_question(subject, grade, true)


func _four_choice_pool(items: Array[QuizItem]) -> Array[QuizItem]:
	var result: Array[QuizItem] = []
	for item: QuizItem in items:
		var prepared := prepare_choice_count(item, 4)
		if prepared != null:
			result.append(prepared)
	return result


# ---------- Fallback ----------

func _fallback_question(subject: String, grade: int, four_choices: bool = false) -> QuizItem:
	var a_val: int = randi_range(2, 20)
	var b_val: int = randi_range(1, 10)
	var ans: int = a_val + b_val
	if four_choices:
		var used: Dictionary = {ans: true}
		var choices: Array[String] = [str(ans)]
		var offsets := [-4, -3, -2, -1, 1, 2, 3, 4]
		offsets.shuffle()
		for offset: int in offsets:
			var wrong_val: int = ans + offset
			if wrong_val < 0 or used.has(wrong_val):
				continue
			used[wrong_val] = true
			choices.append(str(wrong_val))
			if choices.size() >= 4:
				break
		while choices.size() < 4:
			var extra: int = ans + choices.size() + 1
			if not used.has(extra):
				used[extra] = true
				choices.append(str(extra))
		choices.shuffle()
		var four_idx: int = choices.find(str(ans))
		return QuizItem.create(
			"[%s%d年] %d+%d はどれ？" % [subject, grade, a_val, b_val],
			PackedStringArray(choices),
			four_idx,
			"%d+%d=%d" % [a_val, b_val, ans],
			"FALLBACK"
		)
	var wrong: int = ans + [-2, -1, 1, 2].pick_random()
	var two_choices: Array[String] = [str(ans), str(wrong)]
	two_choices.shuffle()
	var ans_idx: int = two_choices.find(str(ans))
	return QuizItem.create(
		"[%s%d年] %d+%d はどちら？" % [subject, grade, a_val, b_val],
		PackedStringArray(two_choices),
		ans_idx,
		"%d+%d=%d" % [a_val, b_val, ans],
		"FALLBACK"
	)

## オンラインモードで新作以外の枠を埋める問題（フェーズ C1）。tier ごとに取り出す。
##   "shared"       … 共有バンク（Claude 確認済み）で、指定の難易度のもの
##   "builtin"      … ゲーム同梱の問題（共有バンクが足りないときだけ使う）
##   "shared_other" … 共有バンクの別の難易度のもの（最後の補い）
## exclude_texts と同じ問題文は除く。足りなくても算数の自動生成では埋めない。
func bank_candidates(subject: String, grade: int, difficulty: String, mode: String,
		count: int, exclude_texts: Array[String], tier: String) -> Array[QuizItem]:
	var excluded := QuizDedup.make_exact_index(exclude_texts)
	var items: Array[QuizItem] = []
	if tier == "builtin":
		items = offline_candidates(subject, grade, difficulty)
	else:
		for raw: Dictionary in external_bank_items:
			if str(raw.get("subject", "")) != subject or int(raw.get("grade", 0)) != grade:
				continue
			var same_difficulty := str(raw.get("difficulty", "")) == difficulty
			if same_difficulty != (tier == "shared"):
				continue
			var n := _normalize(raw)
			if n == null:
				continue
			n.src = "OFFLINE_FIREBASE"
			n.estimated_seconds = _estimate_seconds(n, subject, difficulty)
			items.append(n)
	if difficulty == "難しい" or mode == Constants.MODE_TEN:
		items = _four_choice_pool(items)
	items.shuffle()
	var picked: Array[QuizItem] = []
	var seen := {}
	for item: QuizItem in items:
		var key := QuizDedup.exact_key(item.q)
		if excluded.has(key) or seen.has(key):
			continue
		seen[key] = true
		picked.append(_harden_distractors(item) if difficulty == "難しい" else item)
		if picked.size() >= count:
			break
	return picked


# ---------- Main API ----------

func get_quizzes(subject: String, grade: int, difficulty: String,
		mode: String, count: int, exclude_texts: Array[String] = []) -> Array[QuizItem]:
	# オフラインバンクは有限。同じ書式の計算問題を残し、問題文の一致だけを高速に除外する。
	var excluded := QuizDedup.make_exact_index(exclude_texts)
	# Keep canonical four-choice candidates for hard rounds and the final boss.
	# Reduce normal/easy questions only after their final position is known.
	var require_four := difficulty == "難しい" or mode == Constants.MODE_TEN
	# 正規化・解答時間の推定・難易度の帯分けは条件ごとに覚えたもの（_pool_for）を使う。
	# 候補は {source, sample, key} で、払い出す問題だけを _pool_item で複製して作る。
	var prepared := _pool_for(subject, grade, difficulty, require_four)
	var entries: Array[Dictionary] = prepared["entries"]
	var bucket: Array[Dictionary] = prepared["bucket"]
	var fallback_entries: Array[Dictionary] = prepared["fallback"]
	var items: Array[Dictionary] = entries.duplicate()
	var external_fallback: Array[Dictionary] = fallback_entries.duplicate()

	if items.is_empty() and external_fallback.is_empty():
		if mode == Constants.MODE_TEN:
			var fallbacks: Array[QuizItem] = []
			for i: int in range(maxi(1, count)):
				fallbacks.append(_fallback_question(subject, grade, require_four or i == count - 1))
			return fallbacks
		var single: Array[QuizItem] = [_fallback_question(subject, grade, require_four)]
		return single

	var pool: Array[Dictionary] = bucket.duplicate()
	pool.shuffle()
	external_fallback.shuffle()
	pool.append_array(external_fallback)
	# 候補が2問以下で帯分けしないときは、プールと全体が同じ配列なので
	# 別難易度の控えが2回ずつ入る（従来の選ばれやすさをそのまま保つ）。
	if bool(prepared["unbucketed"]):
		pool.append_array(external_fallback)
	items.append_array(external_fallback)
	var has_fresh := true
	if exclude_texts.size() > 0:
		var filtered: Array[Dictionary] = []
		for entry: Dictionary in pool:
			if excluded.has(entry["key"]):
				continue
			filtered.append(entry)
		if not filtered.is_empty():
			pool = filtered
		else:
			has_fresh = false

	# 難しい難易度の場合、選択肢をより紛らわしくする（払い出す問題ごとに _pool_item で行う）

	if mode == Constants.MODE_TEN:
		var uniq: Array[QuizItem] = []
		var seen: Dictionary = {}
		for entry: Dictionary in pool:
			var q_text: String = (entry["source"] as QuizItem).q
			if q_text in seen:
				continue
			if excluded.has(entry["key"]):
				continue
			seen[q_text] = true
			uniq.append(_pool_item(entry, require_four, difficulty))
			if uniq.size() >= count:
				break
		# Also check from full items if pool was too small
		if uniq.size() < count:
			for entry: Dictionary in items:
				var q_text: String = (entry["source"] as QuizItem).q
				if q_text in seen:
					continue
				if excluded.has(entry["key"]):
					continue
				seen[q_text] = true
				uniq.append(_pool_item(entry, require_four, difficulty))
				if uniq.size() >= count:
					break
		while uniq.size() < count:
			uniq.append(_fallback_question(subject, grade, require_four or uniq.size() == count - 1))

		# Make the hardest question the "Boss" (last question), and keep it 4-choice.
		if uniq.size() > 1:
			var max_score := -100.0
			var max_idx := -1
			for i: int in range(uniq.size()):
				var score := _complexity_score(uniq[i], subject, grade)
				if score > max_score:
					max_score = score
					max_idx = i
			if max_idx >= 0 and max_idx != uniq.size() - 1:
				var hardest: QuizItem = uniq[max_idx]
				uniq.remove_at(max_idx)
				uniq.append(hardest)
		if not uniq.is_empty():
			var last_idx: int = uniq.size() - 1
			if uniq[last_idx].c.size() < 4:
				uniq[last_idx] = expand_to_four_choices(uniq[last_idx])
			if uniq[last_idx].c.size() < 4:
				for i: int in range(last_idx - 1, -1, -1):
					if uniq[i].c.size() >= 4:
						var swapped: QuizItem = uniq[last_idx]
						uniq[last_idx] = uniq[i]
						uniq[i] = swapped
						break

		return uniq

	# エンドレスの補充は1回で count 問まで返す。1問ずつ返して、選んだ問題を除外に足しながら
	# 呼び直すのと同じ選び方（除外されていない候補から、同じ問題文を重ねずに一様に選ぶ）。
	if mode == Constants.MODE_ENDLESS and count > 1 and has_fresh:
		var picked: Array[QuizItem] = []
		var picked_keys: Dictionary = {}
		for i: int in range(pool.size()):
			if picked.size() >= count:
				break
			var j := randi_range(i, pool.size() - 1)
			var entry: Dictionary = pool[j]
			pool[j] = pool[i]
			pool[i] = entry
			if picked_keys.has(entry["key"]):
				continue
			picked_keys[entry["key"]] = true
			picked.append(_pool_item(entry, require_four, difficulty))
		return picked

	var result: Array[QuizItem] = []
	if pool.size() > 0:
		result.append(_pool_item(pool.pick_random(), require_four, difficulty))
	else:
		result.append(_fallback_question(subject, grade, require_four))
	return result


## get_quizzes の下ごしらえを条件ごとに1回だけ行って覚えておく。
##   entries  … 通常の候補（同梱の問題＋指定の難易度の共有バンク）。並びは元データの順
##   bucket   … entries のうち、難易度の帯に入るもの
##   fallback … 共有バンクの別の難易度（少ない条件の補い）
##   expanded … 2択を乱数で4択に広げた候補がある（warm_pool でラウンドごとに作り直す）
## 候補は {source: 正規化した QuizItem, sample: 4択にしたもの（4択が要らなければ source）,
## key: 問題文の一致キー}。中の QuizItem は共有なので、払い出すときは _pool_item で複製する。
func _pool_for(subject: String, grade: int, difficulty: String, require_four: bool) -> Dictionary:
	# offline_bank.json の中身は書き換えない約束なので、差し替えられたときだけ捨てる
	if not is_same(_pool_cache_bank, bank):
		_pool_cache.clear()
		_pool_cache_bank = bank
	var cache_key := "%s|%d|%s|%s" % [subject, grade, difficulty, require_four]
	if _pool_cache.has(cache_key):
		return _pool_cache[cache_key]

	var entries: Array[Dictionary] = []
	var subj_data: Variant = bank.get(subject, {})
	var raw_items_data: Variant = (subj_data as Dictionary).get(str(grade), []) if subj_data is Dictionary else []
	if raw_items_data is Array:
		for raw: Variant in raw_items_data:
			var n := _normalize(raw)
			if n:
				# オフライン問題にはヒューリスティクスで解答時間を推定
				n.estimated_seconds = _estimate_seconds(n, subject, difficulty)
				_append_pool_entry(entries, n, require_four)

	# Firebase cache items with the exact requested difficulty join the normal
	# shuffled pool. Other difficulties remain a fallback for sparse categories.
	var external_fallback: Array[Dictionary] = []
	for raw: Dictionary in external_bank_items:
		if str(raw.get("subject", "")) != subject or int(raw.get("grade", 0)) != grade:
			continue
		var n := _normalize(raw)
		if n == null:
			continue
		n.src = "OFFLINE_FIREBASE"
		if str(raw.get("difficulty", "")) == difficulty:
			_append_pool_entry(entries, n, require_four)
		else:
			_append_pool_entry(external_fallback, n, require_four)

	# 帯分けは表示する形（4択なら4択にしたもの）で採点する
	var samples: Array[QuizItem] = []
	for entry: Dictionary in entries:
		samples.append(entry["sample"])
	var bucket: Array[Dictionary] = []
	for i: int in _bucket_indices(samples, subject, grade, difficulty):
		bucket.append(entries[i])
	# 帯に入るかが広げ方で変わるので、乱数で4択に広げた候補があるかを覚えておく
	var expanded := false
	for entry: Dictionary in entries:
		if not is_same(entry["sample"], entry["source"]):
			expanded = true
			break

	var prepared := {
		"entries": entries,
		"bucket": bucket,
		"fallback": external_fallback,
		"unbucketed": entries.size() <= 2,
		"expanded": expanded,
	}
	if _pool_cache.size() >= POOL_CACHE_MAX:
		_pool_cache.erase(_pool_cache.keys()[0])
	_pool_cache[cache_key] = prepared
	return prepared


## 4択が要る条件では、4択にできる問題だけを候補にする（_four_choice_pool と同じ判定）。
func _append_pool_entry(entries: Array[Dictionary], source: QuizItem, require_four: bool) -> void:
	var sample := source
	if require_four:
		sample = prepare_choice_count(source, 4)
		if sample == null:
			return
	entries.append({"source": source, "sample": sample, "key": QuizDedup.exact_key(source.q)})


## 候補から払い出す1問を作る。呼び出し側が genre・src などを書き換えるので必ず複製する。
## 4択への拡張と紛らわしい選択肢づくりは乱数を使うので、覚えておかずに毎回ここで行う。
func _pool_item(entry: Dictionary, require_four: bool, difficulty: String) -> QuizItem:
	var item := (entry["source"] as QuizItem).duplicate(true) as QuizItem
	if require_four:
		var four := prepare_choice_count(item, 4)
		item = four if four != null else (entry["sample"] as QuizItem).duplicate(true) as QuizItem
	if difficulty == "難しい":
		item = _harden_distractors(item)
	return item
