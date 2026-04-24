extends RefCounted
class_name HatData

## 帽子メタデータ定義

const HAT_NONE := 0
const HAT_TOP_HAT := 1
const HAT_CROWN := 2
const HAT_CAP := 3
const HAT_SANTA := 4
const HAT_COWBOY := 5
const HAT_HELMET := 6
const HAT_WIZARD := 7
const HAT_CONE := 8

const HAT_COUNT := 9

static func get_hat_list() -> Array[Dictionary]:
	return [
		{"id": HAT_NONE,    "name": "なし",         "icon": "—",  "desc": "帽子なし"},
		{"id": HAT_TOP_HAT, "name": "シルクハット", "icon": "🎩", "desc": "紳士のたしなみ"},
		{"id": HAT_CROWN,   "name": "王冠",         "icon": "👑", "desc": "キング・オブ・クイズ"},
		{"id": HAT_CAP,     "name": "キャップ",     "icon": "🧢", "desc": "スポーティーな一品"},
		{"id": HAT_SANTA,   "name": "サンタ帽",     "icon": "🎄", "desc": "メリークリスマス！"},
		{"id": HAT_COWBOY,  "name": "カウボーイ",   "icon": "🤠", "desc": "荒野の挑戦者"},
		{"id": HAT_HELMET,  "name": "ヘルメット",   "icon": "🪖", "desc": "安全第一！"},
		{"id": HAT_WIZARD,  "name": "魔法使い",     "icon": "🧙", "desc": "知識の魔術師"},
		{"id": HAT_CONE,    "name": "コーン",       "icon": "🚧", "desc": "工事中注意！"},
	]

static func get_hat_name(hat_id: int) -> String:
	var list := get_hat_list()
	if hat_id >= 0 and hat_id < list.size():
		return "%s %s" % [list[hat_id]["icon"], list[hat_id]["name"]]
	return "— なし"
