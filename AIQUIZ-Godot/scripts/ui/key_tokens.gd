class_name KeyTokens
extends Object

## 操作説明に出てくるキー表記を、キーキャップ用のトークンへ分解する。
## "A / D" や "WASD"、"←↑↓→" のような省略形を統一する。

const BADGE_KEYS := ["HIT"]
const ARROW_CLUSTER := ["←", "↑", "↓", "→"]
const WASD_CLUSTER := ["W", "A", "S", "D"]


static func is_badge(spec: String) -> bool:
	return spec.strip_edges().to_upper() in BADGE_KEYS


static func display_glyph(token: String) -> String:
	var raw := token.strip_edges()
	if raw.is_empty():
		return ""
	match raw.to_lower():
		"space", "spc", "スペース":
			return "Space"
		"enter", "return":
			return "Enter"
		"esc", "escape":
			return "Esc"
		"ctrl", "control":
			return "Ctrl"
		"shift":
			return "Shift"
		"tab":
			return "Tab"
		"left", "←":
			return "←"
		"right", "→":
			return "→"
		"up", "↑":
			return "↑"
		"down", "↓":
			return "↓"
		"any", "任意", "任意のキー":
			return ""
	return raw


static func texture_stem(token: String) -> String:
	var raw := token.strip_edges()
	if raw.is_empty():
		return "keyboard_any"
	match raw.to_lower():
		"space", "spc", "スペース":
			return "keyboard_space"
		"enter", "return":
			return "keyboard_enter"
		"esc", "escape":
			return "keyboard_escape"
		"ctrl", "control":
			return "keyboard_ctrl"
		"shift":
			return "keyboard_shift"
		"tab":
			return "keyboard_tab"
		"alt":
			return "keyboard_alt"
		"left", "←":
			return "keyboard_arrow_left"
		"right", "→":
			return "keyboard_arrow_right"
		"up", "↑":
			return "keyboard_arrow_up"
		"down", "↓":
			return "keyboard_arrow_down"
		"any", "任意", "任意のキー":
			return "keyboard_any"
		"矢印", "矢印キー", "←↑↓→":
			return "keyboard_arrows"
	var glyph := display_glyph(raw)
	if glyph.length() == 1:
		var ch := glyph.to_lower()
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			return "keyboard_%s" % ch
	return "keyboard_any"


static func is_wide(token: String) -> bool:
	return display_glyph(token).length() >= 3


static func uses_cluster(spec: String) -> bool:
	var raw := spec.strip_edges()
	var lowered := raw.to_lower()
	return (
		lowered == "wasd"
		or raw in ["矢印", "矢印キー", "←↑↓→", "←↑↓→"]
	)


static func split_spec(spec: String) -> PackedStringArray:
	var raw := spec.strip_edges()
	if raw.is_empty() or is_badge(raw):
		return PackedStringArray()
	var lowered := raw.to_lower()
	if lowered == "wasd":
		return PackedStringArray(WASD_CLUSTER)
	if raw in ["矢印", "矢印キー", "←↑↓→"]:
		return PackedStringArray(["矢印"])
	if raw.find(" / ") >= 0:
		return _split_keep(raw, " / ")
	if raw.find("\u30fb") >= 0 or raw.find("・") >= 0:
		return _split_keep(raw, "・")
	if raw.find("/") >= 0:
		return _split_keep(raw, "/")
	return PackedStringArray([raw])


static func _split_keep(raw: String, delimiter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part: String in raw.split(delimiter, false):
		var token := part.strip_edges()
		if not token.is_empty():
			out.append(token)
	return out
