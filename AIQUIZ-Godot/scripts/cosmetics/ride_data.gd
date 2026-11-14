extends RefCounted
class_name RideData

## 乗り物（スキンのシークレット）のメタデータ定義。
## 番号は保存とオンラインの送受信に使うので、変更・並べ替え禁止（足すときは末尾に）。

const RIDE_NONE := 0
const RIDE_MAMACHARI := 1

const RIDE_COUNT := 2

## 乗り物 → 解放の ID（UnlockStore）。ここに無い乗り物は、はじめから選べる。
const UNLOCK_IDS := {
	RIDE_MAMACHARI: &"mamachari",
}
const NAMES := {
	RIDE_NONE: "なし",
	RIDE_MAMACHARI: "ママチャリ",
}


static func is_valid(ride_id: int) -> bool:
	return ride_id >= 0 and ride_id < RIDE_COUNT


static func ride_name(ride_id: int) -> String:
	return str(NAMES.get(ride_id, NAMES[RIDE_NONE]))


## その乗り物の解放の ID（解放の要らない乗り物は &""）。
static func unlock_id(ride_id: int) -> StringName:
	return UNLOCK_IDS.get(ride_id, &"")


static func is_unlocked(ride_id: int) -> bool:
	var id := unlock_id(ride_id)
	return id == &"" or UnlockStore.is_unlocked(id)


## このPCで選べるか（番号が正しく、解放済み）。
static func is_selectable(ride_id: int) -> bool:
	return is_valid(ride_id) and is_unlocked(ride_id)
