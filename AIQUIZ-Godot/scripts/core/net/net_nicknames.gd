class_name NetNicknames
extends RefCounted

## Fallback names for online play, chosen by id. Shown to the opponent when a
## player's own name is missing or was rejected by NetNameFilter / the relay.

const ADJECTIVES: Array[String] = [
	"元気な", "賢い", "素早い", "優しい", "不思議な", "勇敢な", "ニコニコ", "キラキラ",
]
const ANIMALS: Array[String] = [
	"パンダ", "ペンギン", "キツネ", "ウサギ", "イルカ", "フクロウ", "ライオン", "カメ",
]
const COUNT := 64


static func name_for(id: int) -> String:
	var safe := clampi(id, 0, COUNT - 1)
	return ADJECTIVES[safe / ANIMALS.size()] + ANIMALS[safe % ANIMALS.size()]


static func random_id() -> int:
	return randi() % COUNT
