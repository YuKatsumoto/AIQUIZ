extends RefCounted

## 黒板に書く文字の線（assets/settings_hall/glyph_strokes.json、tools/settings_hall/glyph_strokes.py が作る）。
## 字の枠は 0..1（y は上向き）。layout() で文字列を黒板の面の上のメートルの線（画の順）に並べる。
## 線のない文字（データにない字）は飛ばして送り幅だけ進める。

const PATH := "res://assets/settings_hall/glyph_strokes.json"
## 字と字の間（字の高さに対する割合）。チョークの手書きは少し詰まる。
const TRACKING := -0.02

var _glyphs: Dictionary = {}


func _init() -> void:
	if not FileAccess.file_exists(PATH):
		push_warning("GlyphBook: %s is missing" % PATH)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary and (data as Dictionary).get("glyphs") is Dictionary:
		_glyphs = (data as Dictionary).glyphs


func has_glyph(ch: String) -> bool:
	return _glyphs.has(ch)


## 文字列の幅（m）。
func measure(text: String, height_m: float) -> float:
	var w := 0.0
	for ch in text:
		w += _advance(ch) * height_m + TRACKING * height_m
	return maxf(0.0, w - TRACKING * height_m)


## 文字列を、左下 origin（m、黒板の面の u 右へ・v 上へ）・字の高さ height_m で並べる。
## 返す値: 字ごとの配列 [{"ch": 字, "strokes": [PackedVector2Array, ...], "center": Vector2}]。
## jitter（0..1）で 1 画ごとに少し揺らす（手書きらしさ。字ごとに同じ乱数）。
## style: "drift"（1 字ごとに下がる量、m。右下がりの字）、"grow"（1 字ごとに大きくなる割合）、
## "limit"（右端の u、m。はみ出す分は最後の字を縮めて詰め込む）。
func layout(text: String, origin: Vector2, height_m: float, jitter := 0.5, seed := 0, style := {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(text)
	var out: Array = []
	var x := origin.x
	var drift := float(style.get("drift", 0.0))
	var grow := float(style.get("grow", 0.0))
	var limit := float(style.get("limit", INF))
	var count := text.length()
	var index := -1
	for ch in text:
		index += 1
		var h := height_m * (1.0 + grow * index)
		# 右端に入りきらないときは、残りの字が入る大きさまで縮める
		var rest_width := 0.0
		for k in range(index, count):
			rest_width += _advance(text[k]) * height_m * (1.0 + grow * k)
		if x + rest_width > limit:
			h = maxf(height_m * 0.25, h * (limit - x) / maxf(0.01, rest_width))
		var adv := _advance(ch) * h
		var base_v := origin.y - drift * index
		var glyph: Dictionary = _glyphs.get(ch, {})
		var strokes: Array = []
		# 字ごとの傾き・大きさの揺れ（手書き）
		var slant := rng.randf_range(-0.04, 0.04) * jitter
		var scale := 1.0 + rng.randf_range(-0.05, 0.04) * jitter
		var lift := rng.randf_range(-0.03, 0.03) * jitter * h
		for raw: Array in glyph.get("strokes", []):
			var line := PackedVector2Array()
			var dx := rng.randf_range(-0.012, 0.012) * jitter
			var dy := rng.randf_range(-0.012, 0.012) * jitter
			for p: Array in raw:
				var gx := (float(p[0]) - 0.5) * scale + 0.5 + dx
				var gy := (float(p[1]) - 0.5) * scale + 0.5 + dy
				gx += (gy - 0.5) * slant
				line.append(Vector2(x + gx * h, base_v + lift + gy * h))
			if line.size() >= 2:
				strokes.append(line)
		out.append({"ch": ch, "strokes": strokes, "center": Vector2(x + adv * 0.5, base_v + h * 0.5), "h": h})
		x += adv + TRACKING * h
	return out


func _advance(ch: String) -> float:
	var glyph: Dictionary = _glyphs.get(ch, {})
	if glyph.has("advance"):
		return float(glyph.advance)
	return 1.0 if ch.unicode_at(0) > 0x2000 else 0.55
