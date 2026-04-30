extends RefCounted
class_name EmoteData

## エモート（ダンス）メタデータ定義

const EMOTE_NONE := 0
const EMOTE_STEP_HIP_HOP := 1
const EMOTE_GANGNAM := 2
const EMOTE_SLIDE_HIP_HOP := 3
const EMOTE_FLAIR := 4
const EMOTE_MOONWALK := 5
const EMOTE_HIP_HOP := 6
const EMOTE_SILLY := 7
const EMOTE_SWING := 8
const EMOTE_THRILLER2 := 9
const EMOTE_THRILLER3 := 10
const EMOTE_THRILLER4 := 11
const EMOTE_THRILLER1 := 12
const EMOTE_YMCA := 13
const EMOTE_HOUSE := 14
const EMOTE_HIP_HOP_1 := 15
const EMOTE_HEAD_SPINNING := 16
const EMOTE_RUNNING_MAN := 17

const EMOTE_COUNT := 18

static func get_emote_list() -> Array[Dictionary]:
	return [
		{"id": EMOTE_NONE,          "name": "なし",               "icon": "—",  "desc": "微動だにしない強い意志"},
		{"id": EMOTE_STEP_HIP_HOP, "name": "ステップヒップホップ", "icon": "🕺", "desc": "クラブで一番イキってるやつ"},
		{"id": EMOTE_GANGNAM,      "name": "江南スタイル",         "icon": "🐴", "desc": "乗馬スキルはゼロ"},
		{"id": EMOTE_SLIDE_HIP_HOP,"name": "スライドヒップホップ", "icon": "💃", "desc": "床にワックス塗りすぎた結果"},
		{"id": EMOTE_FLAIR,        "name": "フレア",               "icon": "🤸", "desc": "物理法則を無視した大技"},
		{"id": EMOTE_MOONWALK,     "name": "ムーンウォーク",       "icon": "🌙", "desc": "前に進みたいのに後ろに下がる病"},
		{"id": EMOTE_HIP_HOP,      "name": "ヒップホップ",         "icon": "🎤", "desc": "YO! YO! 言いたいだけ"},
		{"id": EMOTE_SILLY,        "name": "シリーダンス",         "icon": "🤪", "desc": "IQが3になる魔法の踊り"},
		{"id": EMOTE_SWING,        "name": "スウィング",           "icon": "🎶", "desc": "おじいちゃん直伝のステップ"},
		{"id": EMOTE_THRILLER2,    "name": "スリラー2",            "icon": "🧟", "desc": "深夜のテンション(初期症状)"},
		{"id": EMOTE_THRILLER3,    "name": "スリラー3",            "icon": "💀", "desc": "深夜のテンション(末期症状)"},
		{"id": EMOTE_THRILLER4,    "name": "スリラー4",            "icon": "👻", "desc": "完全に朝を迎えちゃった顔"},
		{"id": EMOTE_THRILLER1,    "name": "スリラー1",            "icon": "🧟‍♂️", "desc": "怪奇現象の始まり"},
		{"id": EMOTE_YMCA,         "name": "YMCA",                 "icon": "🔠", "desc": "文字で体を表現する喜び"},
		{"id": EMOTE_HOUSE,        "name": "ハウスダンス",         "icon": "🏠", "desc": "足さばきで床を磨く"},
		{"id": EMOTE_HIP_HOP_1,    "name": "ヒップホップ2",        "icon": "🧢", "desc": "さらにYO! YO! 言うやつ"},
		{"id": EMOTE_HEAD_SPINNING,"name": "ヘッドスピン",         "icon": "🌀", "desc": "頭皮へのダメージは甚大"},
		{"id": EMOTE_RUNNING_MAN,  "name": "ランニングマン",       "icon": "🏃‍♂️", "desc": "走ってるのに進まない"},
	]

## FBXパスのマッピング（IDからパスへ）
static func get_emote_fbx(emote_id: int) -> String:
	var paths := {
		EMOTE_STEP_HIP_HOP: "res://assets/animations/Y Bot@Step Hip Hop Dance.fbx",
		EMOTE_GANGNAM:       "res://assets/animations/Y Bot@Gangnam Style.fbx",
		EMOTE_SLIDE_HIP_HOP:"res://assets/animations/Slide Hip Hop Dance.fbx",
		EMOTE_FLAIR:         "res://assets/animations/Flair.fbx",
		EMOTE_MOONWALK:      "res://assets/animations/Moonwalk.fbx",
		EMOTE_HIP_HOP:       "res://assets/animations/Hip Hop Dancing.fbx",
		EMOTE_SILLY:         "res://assets/animations/Silly Dancing.fbx",
		EMOTE_SWING:         "res://assets/animations/Swing Dancing.fbx",
		EMOTE_THRILLER2:     "res://assets/animations/Thriller Part 2.fbx",
		EMOTE_THRILLER3:     "res://assets/animations/Thriller Part 3.fbx",
		EMOTE_THRILLER4:     "res://assets/animations/Thriller Part 4.fbx",
		EMOTE_THRILLER1:     "res://assets/animations/Thriller Part 1.fbx",
		EMOTE_YMCA:          "res://assets/animations/Ymca Dance.fbx",
		EMOTE_HOUSE:         "res://assets/animations/House Dancing.fbx",
		EMOTE_HIP_HOP_1:     "res://assets/animations/Hip Hop Dancing (1).fbx",
		EMOTE_HEAD_SPINNING: "res://assets/animations/Head Spinning.fbx",
		EMOTE_RUNNING_MAN:   "res://assets/animations/Dancing Running Man.fbx",
	}
	return paths.get(emote_id, "")

static func get_emote_name(emote_id: int) -> String:
	var list := get_emote_list()
	if emote_id >= 0 and emote_id < list.size():
		return "%s %s" % [list[emote_id]["icon"], list[emote_id]["name"]]
	return "— なし"

static func get_emote_desc(emote_id: int) -> String:
	var list := get_emote_list()
	if emote_id >= 0 and emote_id < list.size():
		return list[emote_id]["desc"]
	return ""
