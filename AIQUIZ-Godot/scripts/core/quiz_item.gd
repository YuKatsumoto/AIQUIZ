extends Resource
class_name QuizItem

## クイズ1問分のデータクラス

@export var q: String = ""           # 問題文
@export var c: PackedStringArray = [] # 選択肢
@export var a: int = 0               # 正解インデックス
@export var e: String = ""           # 解説
@export var src: String = "OFFLINE"  # ソース (OFFLINE / ONLINE / FALLBACK)
@export var genre: String = ""       # ジャンル/単元ラベル（出題順分散に使用）
@export var img: String = ""         # 画像パス
@export var choice_img: PackedStringArray = [] # 選択肢画像
@export var estimated_seconds: float = 4.0  # AI予測解答時間（秒）
@export var validated: bool = false  # LLM正解検証済み

# 協力モード用: P1/P2 が式・根拠カードと答えカードを分担して選ぶ
@export var coop_prompt: String = ""
@export var coop_p1_label: String = ""
@export var coop_p2_label: String = ""
@export var coop_p1_choices: PackedStringArray = []
@export var coop_p2_choices: PackedStringArray = []
@export var coop_p1_answer: int = -1
@export var coop_p2_answer: int = -1



static func create(question: String, choices: PackedStringArray, answer: int,
		explanation: String = "", source: String = "OFFLINE",
		image: String = "", choice_images: PackedStringArray = [],
		est_seconds: float = 4.0) -> QuizItem:
	var item := QuizItem.new()
	item.q = question
	item.c = choices
	item.a = answer
	item.e = explanation
	item.src = source
	item.img = image
	item.choice_img = choice_images
	item.estimated_seconds = est_seconds
	return item

func has_coop_data() -> bool:
	return coop_p1_choices.size() == 2 \
		and coop_p2_choices.size() == 2 \
		and coop_p1_answer >= 0 \
		and coop_p1_answer < coop_p1_choices.size() \
		and coop_p2_answer >= 0 \
		and coop_p2_answer < coop_p2_choices.size()


func to_pool_dict() -> Dictionary:
	return {
		"q": q,
		"c": Array(c),
		"a": a,
		"e": e,
		"src": src if not src.is_empty() else "GEMINI_POOL",
		"genre": genre,
		"estimated_seconds": estimated_seconds,
		"validated": validated,
		"stored_at": int(Time.get_unix_time_from_system()),
	}


static func from_pool_dict(raw: Dictionary) -> QuizItem:
	var item := QuizItem.new()
	item.q = str(raw.get("q", "")).strip_edges()
	var choices: PackedStringArray = PackedStringArray()
	var raw_c: Variant = raw.get("c", [])
	if raw_c is Array:
		for choice in raw_c:
			var text := str(choice).strip_edges()
			if not text.is_empty():
				choices.append(text)
	item.c = choices
	var answer: Variant = raw.get("a", 0)
	if typeof(answer) == TYPE_FLOAT or typeof(answer) == TYPE_INT:
		item.a = int(answer)
	elif typeof(answer) == TYPE_STRING and (answer as String).is_valid_int():
		item.a = int(answer)
	item.e = str(raw.get("e", "")).strip_edges()
	var src_text := str(raw.get("src", "GEMINI_POOL")).strip_edges()
	if src_text.is_empty() or src_text.begins_with("OFFLINE"):
		src_text = "GEMINI_POOL"
	item.src = src_text
	item.genre = str(raw.get("genre", raw.get("g", ""))).strip_edges()
	var est: Variant = raw.get("estimated_seconds", 4.0)
	if typeof(est) == TYPE_FLOAT or typeof(est) == TYPE_INT:
		item.estimated_seconds = clampf(float(est), 1.5, 10.0)
	item.validated = bool(raw.get("validated", false))
	return item
