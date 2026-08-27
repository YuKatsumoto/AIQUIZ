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
const HAT_SOMBRERO := 9
const HAT_FROG := 10
const HAT_PROPELLER := 11
const HAT_FOX := 12
const HAT_CHICKEN := 13
const HAT_BOUSI := 14
const HAT_GRADUATION_CAP := 15
const HAT_PIRATE := 16

const HAT_COUNT := 17

static func get_hat_list() -> Array[Dictionary]:
	return [
		{"id": HAT_NONE,      "name": "なし",           "icon": "—",  "desc": "帽子なし"},
		{"id": HAT_TOP_HAT,   "name": "シルクハット",   "icon": "🎩", "desc": "紳士のたしなみ"},
		{"id": HAT_CROWN,     "name": "王冠",           "icon": "👑", "desc": "キング・オブ・クイズ"},
		{"id": HAT_CAP,       "name": "キャップ",       "icon": "🧢", "desc": "スポーティーな一品"},
		{"id": HAT_SANTA,     "name": "サンタ帽",       "icon": "🎄", "desc": "メリークリスマス！"},
		{"id": HAT_COWBOY,    "name": "カウボーイ",     "icon": "🤠", "desc": "荒野の挑戦者"},
		{"id": HAT_HELMET,    "name": "ヘルメット",     "icon": "🪖", "desc": "安全第一！"},
		{"id": HAT_WIZARD,    "name": "魔法使い",       "icon": "🧙", "desc": "知識の魔術師"},
		{"id": HAT_CONE,      "name": "コーン",         "icon": "🚧", "desc": "工事中注意！"},
		{"id": HAT_SOMBRERO,  "name": "ソンブレロ",     "icon": "🌮", "desc": "アリバ！フィエスタ！"},
		{"id": HAT_FROG,      "name": "カエル帽",       "icon": "🐸", "desc": "ケロケロ！"},
		{"id": HAT_PROPELLER, "name": "プロペラ帽",     "icon": "🌀", "desc": "ぶんぶん回る！"},
		{"id": HAT_FOX,       "name": "キツネ帽",       "icon": "🦊", "desc": "コンコン！もふもふ"},
		{"id": HAT_CHICKEN,   "name": "チキン",         "icon": "🐔", "desc": "コケコッコー！"},
		{"id": HAT_BOUSI,     "name": "ぼうし",         "icon": "🧢", "desc": "おしゃれな帽子！"},
		{"id": HAT_GRADUATION_CAP, "name": "卒業帽",     "icon": "🎓", "desc": "知識を極めた証！"},
		{"id": HAT_PIRATE,    "name": "海賊帽",         "icon": "🏴‍☠️", "desc": "知識の海へ出航！"},
	]

static func get_hat_name(hat_id: int) -> String:
	var list := get_hat_list()
	if hat_id >= 0 and hat_id < list.size():
		return "%s %s" % [list[hat_id]["icon"], list[hat_id]["name"]]
	return "— なし"
