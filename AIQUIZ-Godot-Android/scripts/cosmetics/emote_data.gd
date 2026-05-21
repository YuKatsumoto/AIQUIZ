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
## スリラー1→2→3→4を連続再生する統合エモート（旧ID 9〜12は互換用）
const EMOTE_THRILLER := 9
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

const THRILLER_PART_PATHS: Array[String] = [
	"res://assets/animations/Thriller Part 1.fbx",
	"res://assets/animations/Thriller Part 2.fbx",
	"res://assets/animations/Thriller Part 3.fbx",
	"res://assets/animations/Thriller Part 4.fbx",
]

static func is_thriller_emote(emote_id: int) -> bool:
	return normalize_emote_id(emote_id) == EMOTE_THRILLER


static func normalize_emote_id(emote_id: int) -> int:
	if emote_id in [EMOTE_THRILLER, EMOTE_THRILLER2, EMOTE_THRILLER3, EMOTE_THRILLER4, EMOTE_THRILLER1]:
		return EMOTE_THRILLER
	return emote_id


static func get_emote_list() -> Array[Dictionary]:
	return [
		{"id": EMOTE_NONE,          "name": "なし",               "icon": "—",  "desc": "微動だにしない強い意志"},
		{"id": EMOTE_STEP_HIP_HOP, "name": "ステップヒップホップ", "icon": "🕺", "desc": ""},
		{"id": EMOTE_GANGNAM,      "name": "カンナムスタイル",         "icon": "🐴", "desc": ""},
		{"id": EMOTE_SLIDE_HIP_HOP,"name": "スライドヒップホップ", "icon": "💃", "desc": ""},
		{"id": EMOTE_FLAIR,        "name": "フレア",               "icon": "🤸", "desc": ""},
		{"id": EMOTE_MOONWALK,     "name": "ムーンウォーク",       "icon": "🌙", "desc": ""},
		{"id": EMOTE_HIP_HOP,      "name": "ヒップホップ",         "icon": "🎤", "desc": ""},
		{"id": EMOTE_SILLY,        "name": "シリーダンス",         "icon": "🤪", "desc": ""},
		{"id": EMOTE_SWING,        "name": "スウィング",           "icon": "🎶", "desc": ""},
		{
			"id": EMOTE_THRILLER,
			"name": "スリラー",
			"icon": "🧟",
			"desc": "",
		},
		{"id": EMOTE_YMCA,         "name": "YMCA",                 "icon": "🔠", "desc": ""},
		{"id": EMOTE_HOUSE,        "name": "ハウスダンス",         "icon": "🏠", "desc": "足さばきで床を磨く"},
		{"id": EMOTE_HIP_HOP_1,    "name": "ヒップホップ2",        "icon": "🧢", "desc": ""},
		{"id": EMOTE_HEAD_SPINNING,"name": "ヘッドスピン",         "icon": "🌀", "desc": "頭皮へのダメージは甚大"},
		{"id": EMOTE_RUNNING_MAN,  "name": "ランニングマン",       "icon": "🏃‍♂️", "desc": ""},
	]

## FBXパスのマッピング（IDからパスへ）
static func get_emote_fbx(emote_id: int) -> String:
	var id := normalize_emote_id(emote_id)
	if id == EMOTE_THRILLER and not THRILLER_PART_PATHS.is_empty():
		return THRILLER_PART_PATHS[0]
	var paths := {
		EMOTE_STEP_HIP_HOP: "res://assets/animations/Y Bot@Step Hip Hop Dance.fbx",
		EMOTE_GANGNAM:       "res://assets/animations/Y Bot@Gangnam Style.fbx",
		EMOTE_SLIDE_HIP_HOP:"res://assets/animations/Slide Hip Hop Dance.fbx",
		EMOTE_FLAIR:         "res://assets/animations/Flair.fbx",
		EMOTE_MOONWALK:      "res://assets/animations/Moonwalk.fbx",
		EMOTE_HIP_HOP:       "res://assets/animations/Hip Hop Dancing.fbx",
		EMOTE_SILLY:         "res://assets/animations/Silly Dancing.fbx",
		EMOTE_SWING:         "res://assets/animations/Swing Dancing.fbx",
		EMOTE_YMCA:          "res://assets/animations/Ymca Dance.fbx",
		EMOTE_HOUSE:         "res://assets/animations/House Dancing.fbx",
		EMOTE_HIP_HOP_1:     "res://assets/animations/Hip Hop Dancing (1).fbx",
		EMOTE_HEAD_SPINNING: "res://assets/animations/Head Spinning.fbx",
		EMOTE_RUNNING_MAN:   "res://assets/animations/Dancing Running Man.fbx",
	}
	return paths.get(id, "")


static func get_emote_name(emote_id: int) -> String:
	var id := normalize_emote_id(emote_id)
	for entry in get_emote_list():
		if int(entry["id"]) == id:
			return "%s %s" % [entry["icon"], entry["name"]]
	return "— なし"


static func get_emote_desc(emote_id: int) -> String:
	var id := normalize_emote_id(emote_id)
	for entry in get_emote_list():
		if int(entry["id"]) == id:
			return str(entry["desc"])
	return ""
