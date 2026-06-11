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
