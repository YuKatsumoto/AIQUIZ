extends RefCounted
class_name PlayerSkin

## プレイヤーの体の色（パーツごとの単色）のデータ定義。
## スキンは {part_id: Color} の Dictionary。空の {} は「そのスロットの標準色」を表す。

## この並びはオンライン／保存用のコンパクト形式の一部なので変更・並べ替え禁止。
## 左右は「キャラ自身から見た」左右（正面から見ると 左うで は画面の右側に来る）。
const PART_IDS: Array[StringName] = [
	&"head", &"chest", &"waist",
	&"l_arm", &"r_arm", &"l_hand", &"r_hand",
	&"l_leg", &"r_leg", &"l_foot", &"r_foot",
]
const ALL: StringName = &"all"
const HEAD: StringName = &"head"

const PART_LABELS := {
	&"all": "全身",
	&"head": "あたま",
	&"chest": "むね",
	&"waist": "こし",
	&"l_arm": "左うで",
	&"r_arm": "右うで",
	&"l_hand": "左手",
	&"r_hand": "右手",
	&"l_leg": "左あし",
	&"r_leg": "右あし",
	&"l_foot": "左くつ",
	&"r_foot": "右くつ",
}
## 左右の対（おすすめ・おまかせで両側を同じ色にするため）。
const MIRROR_PARTS := {
	&"l_arm": &"r_arm", &"r_arm": &"l_arm",
	&"l_hand": &"r_hand", &"r_hand": &"l_hand",
	&"l_leg": &"r_leg", &"r_leg": &"l_leg",
	&"l_foot": &"r_foot", &"r_foot": &"l_foot",
}
## 見た目の大きさの目安（似た色判定の重み）。
const PART_AREA_WEIGHTS := {
	&"head": 1.0, &"chest": 1.4, &"waist": 1.1,
	&"l_arm": 0.5, &"r_arm": 0.5, &"l_hand": 0.175, &"r_hand": 0.175,
	&"l_leg": 0.65, &"r_leg": 0.65, &"l_foot": 0.225, &"r_foot": 0.225,
}

## 現行の固定色（PlayerController.P1_* / P2_*）と同じ値。
const SLOT_COLORS := {
	1: {"body": Color(0.95, 0.55, 0.20), "head": Color(0.95, 0.65, 0.35), "limb": Color(0.85, 0.48, 0.18)},
	2: {"body": Color(0.20, 0.65, 0.90), "head": Color(0.30, 0.75, 0.95), "limb": Color(0.15, 0.55, 0.80)},
}

## version(1) + 11パーツ × RGB(3) の小文字16進。
const COMPACT_VERSION := 3
const COMPACT_HEX_LENGTH := 68
## 左右をまとめていた前の形式（version 2、7パーツ）。読み込みだけ対応する。
const LEGACY_V2_VERSION := 2
const LEGACY_V2_HEX_LENGTH := 44
const LEGACY_V2_PARTS := {
	&"head": [&"head"],
	&"chest": [&"chest"],
	&"waist": [&"waist"],
	&"arms": [&"l_arm", &"r_arm"],
	&"hands": [&"l_hand", &"r_hand"],
	&"legs": [&"l_leg", &"r_leg"],
	&"feet": [&"l_foot", &"r_foot"],
}
const LEGACY_V2_ORDER: Array[StringName] = [&"head", &"chest", &"waist", &"arms", &"hands", &"legs", &"feet"]

## しきい値未満なら「見分けにくい」とみなす（OKLab 距離の加重平均。おまかせの引き直しに使う）。
const SIMILAR_WARNING_THRESHOLD := 0.085


# ---------------------------------------------------------------------------
# 基本
# ---------------------------------------------------------------------------

static func is_part_id(value: Variant) -> bool:
	return PART_IDS.has(StringName(str(value)))


static func part_label(part_id: StringName) -> String:
	return str(PART_LABELS.get(part_id, str(part_id)))


static func quantize(color: Color) -> Color:
	return Color8(
		clampi(roundi(color.r * 255.0), 0, 255),
		clampi(roundi(color.g * 255.0), 0, 255),
		clampi(roundi(color.b * 255.0), 0, 255),
	)


static func default_skin(slot: int) -> Dictionary:
	var palette: Dictionary = SLOT_COLORS.get(2 if slot == 2 else 1)
	var skin := {}
	for part_id: StringName in PART_IDS:
		match part_id:
			&"head":
				skin[part_id] = palette.head
			&"chest", &"waist":
				skin[part_id] = palette.body
			_:
				skin[part_id] = palette.limb
	return skin


## {} を含む任意の入力を、必ず7パーツそろった形にする。
static func resolve(skin: Variant, slot: int) -> Dictionary:
	if skin is Dictionary and not (skin as Dictionary).is_empty():
		return canonicalize(skin, slot)
	return default_skin(slot)


static func canonicalize(raw: Variant, slot: int) -> Dictionary:
	var defaults := default_skin(slot)
	var source: Dictionary = raw if raw is Dictionary else {}
	var skin := {}
	for part_id: StringName in PART_IDS:
		var value: Variant = source.get(part_id, source.get(str(part_id), _legacy_value(source, part_id)))
		skin[part_id] = quantize(_to_color(value, defaults[part_id]))
	return skin


## 前の形式のキー（arms など左右まとめ）で来た値を、左右それぞれに使う。
static func _legacy_value(source: Dictionary, part_id: StringName) -> Variant:
	for legacy_id: StringName in LEGACY_V2_PARTS:
		if (LEGACY_V2_PARTS[legacy_id] as Array).has(part_id) and legacy_id != part_id:
			return source.get(legacy_id, source.get(str(legacy_id), null))
	return null


## あたまだけスロットの標準色にした見た目（ローカル2人対戦で見分けるため）。
static func with_default_head(skin: Variant, slot: int) -> Dictionary:
	var result := resolve(skin, slot)
	result[HEAD] = default_skin(slot)[HEAD]
	return result


static func part_color(skin: Dictionary, part_id: StringName) -> Color:
	var value: Variant = skin.get(part_id, Color.WHITE)
	return value if value is Color else Color.WHITE


## 全身を選んでいるときに見せる色（むねを代表にする）。
static func target_color(skin: Dictionary, target: StringName) -> Color:
	return part_color(skin, &"chest" if target == ALL else target)


static func is_slot_default(skin: Variant, slot: int) -> bool:
	if not skin is Dictionary or (skin as Dictionary).is_empty():
		return true
	return encode_compact(canonicalize(skin, slot)) == encode_compact(canonicalize(default_skin(slot), slot))


## 保存・送信用。標準色のままなら "" を返す（受け取った側でスロット既定色に展開）。
static func to_code(skin: Variant, slot: int) -> String:
	if is_slot_default(skin, slot):
		return ""
	return encode_compact(canonicalize(skin, slot))


## to_code の逆。"" や不正な文字列は {}（スロット既定）になる。
static func from_code(code: Variant) -> Dictionary:
	if not code is String or (code as String).is_empty():
		return {}
	return decode_compact(code)


static func encode_compact(skin: Dictionary) -> String:
	var bytes := PackedByteArray()
	bytes.append(COMPACT_VERSION)
	for part_id: StringName in PART_IDS:
		var color := quantize(part_color(skin, part_id))
		bytes.append(color.r8)
		bytes.append(color.g8)
		bytes.append(color.b8)
	return bytes.hex_encode()


static func decode_compact(code: String) -> Dictionary:
	if code.length() != COMPACT_HEX_LENGTH and code.length() != LEGACY_V2_HEX_LENGTH:
		return {}
	for character: String in code:
		if not "0123456789abcdef".contains(character):
			return {}
	var bytes := code.hex_decode()
	if bytes.size() * 2 != code.length():
		return {}
	var skin := {}
	if code.length() == LEGACY_V2_HEX_LENGTH:
		if bytes[0] != LEGACY_V2_VERSION:
			return {}
		for index: int in range(LEGACY_V2_ORDER.size()):
			var base := 1 + index * 3
			for part_id: StringName in LEGACY_V2_PARTS[LEGACY_V2_ORDER[index]]:
				skin[part_id] = Color8(bytes[base], bytes[base + 1], bytes[base + 2])
		return skin
	if bytes[0] != COMPACT_VERSION:
		return {}
	for index: int in range(PART_IDS.size()):
		var base := 1 + index * 3
		skin[PART_IDS[index]] = Color8(bytes[base], bytes[base + 1], bytes[base + 2])
	return skin


# ---------------------------------------------------------------------------
# 編集
# ---------------------------------------------------------------------------

## target は part_id か ALL（全身まとめて）。
static func set_color(skin: Dictionary, target: StringName, color: Color) -> Dictionary:
	var result := skin.duplicate()
	for part_id: StringName in _targets(target):
		result[part_id] = quantize(color)
	return result


static func reset_target(skin: Dictionary, target: StringName, slot: int) -> Dictionary:
	var defaults := default_skin(slot)
	var result := skin.duplicate()
	for part_id: StringName in _targets(target):
		result[part_id] = defaults[part_id]
	return result


static func _targets(target: StringName) -> Array[StringName]:
	var targets: Array[StringName] = []
	if target == ALL:
		targets.append_array(PART_IDS)
	elif is_part_id(target):
		targets.append(target)
	return targets


# ---------------------------------------------------------------------------
# 色の評価
# ---------------------------------------------------------------------------

## 2人の見た目の近さ（OKLab 距離の面積加重平均。小さいほど似ている）。
static func distance(skin_a: Dictionary, skin_b: Dictionary) -> float:
	var total := 0.0
	var weight_sum := 0.0
	for part_id: StringName in PART_IDS:
		var weight: float = PART_AREA_WEIGHTS.get(part_id, 1.0)
		var a := srgb_to_oklab(part_color(skin_a, part_id))
		var b := srgb_to_oklab(part_color(skin_b, part_id))
		total += a.distance_to(b) * weight
		weight_sum += weight
	return total / maxf(weight_sum, 0.0001)


static func looks_similar(skin_a: Dictionary, skin_b: Dictionary) -> bool:
	return distance(skin_a, skin_b) < SIMILAR_WARNING_THRESHOLD


static func srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func srgb_to_oklab(color: Color) -> Vector3:
	var r := srgb_to_linear(color.r)
	var g := srgb_to_linear(color.g)
	var b := srgb_to_linear(color.b)
	var l := pow(maxf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 0.0), 1.0 / 3.0)
	var m := pow(maxf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 0.0), 1.0 / 3.0)
	var s := pow(maxf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 0.0), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
	)


# ---------------------------------------------------------------------------
# おすすめ・おまかせ
# ---------------------------------------------------------------------------

const PRESET_IDS: Array[StringName] = [&"standard", &"rival", &"forest", &"panda"]
const PRESET_LABELS := {
	&"standard": "いつもの色",
	&"rival": "あいての色",
	&"forest": "もり",
	&"panda": "パンダ",
}


static func preset_label(preset_id: StringName) -> String:
	return str(PRESET_LABELS.get(preset_id, str(preset_id)))


static func preset_skin(preset_id: StringName, slot: int) -> Dictionary:
	match preset_id:
		&"rival":
			return default_skin(1 if slot == 2 else 2)
		&"forest":
			var forest := _uniform_skin(Color8(74, 128, 62))
			forest[&"head"] = Color8(232, 196, 150)
			forest[&"waist"] = Color8(110, 78, 46)
			_set_pair(forest, &"l_hand", Color8(232, 196, 150))
			_set_pair(forest, &"l_leg", Color8(110, 78, 46))
			_set_pair(forest, &"l_foot", Color8(60, 40, 26))
			return forest
		&"panda":
			var panda := _uniform_skin(Color8(245, 245, 240))
			_set_pair(panda, &"l_arm", Color8(30, 30, 34))
			_set_pair(panda, &"l_leg", Color8(30, 30, 34))
			_set_pair(panda, &"l_foot", Color8(30, 30, 34))
			return panda
	return default_skin(slot)


## 左右の両方に同じ色を入れる。
static func _set_pair(skin: Dictionary, part_id: StringName, color: Color) -> void:
	skin[part_id] = color
	if MIRROR_PARTS.has(part_id):
		skin[MIRROR_PARTS[part_id]] = color


static func _uniform_skin(color: Color) -> Dictionary:
	var skin := {}
	for part_id: StringName in PART_IDS:
		skin[part_id] = color
	return skin


## 配色が破綻しにくい「おまかせ」。avoid に近い見た目は数回まで引き直す。
static func random_skin(rng: RandomNumberGenerator, avoid: Dictionary = {}) -> Dictionary:
	var best := {}
	var best_distance := -1.0
	for attempt: int in range(6):
		var skin := _random_skin_once(rng)
		if avoid.is_empty():
			return skin
		var d := distance(skin, avoid)
		if d > best_distance:
			best = skin
			best_distance = d
		if d >= SIMILAR_WARNING_THRESHOLD * 2.0:
			break
	return best


static func _random_skin_once(rng: RandomNumberGenerator) -> Dictionary:
	var base_hue := rng.randf()
	var main := Color.from_hsv(base_hue, rng.randf_range(0.45, 0.85), rng.randf_range(0.6, 0.95))
	var accent := Color.from_hsv(fmod(base_hue + rng.randf_range(0.3, 0.7), 1.0), rng.randf_range(0.45, 0.85), rng.randf_range(0.55, 0.95))
	var skin := _uniform_skin(main)
	skin[&"head"] = main.lightened(0.25)
	skin[&"waist"] = accent
	_set_pair(skin, &"l_hand", main.lightened(0.15))
	_set_pair(skin, &"l_leg", accent)
	_set_pair(skin, &"l_foot", Color.from_hsv(base_hue, 0.15, rng.randf_range(0.15, 0.3)))
	return skin


static func _to_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback
