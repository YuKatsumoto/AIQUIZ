extends RefCounted

## build_cistern_scenes.gd が使う手続き生成のテクスチャ（docs/sudden_death_underground.md 6.4）。
## ・繰り返しを崩すワールド座標のノイズ（本物の部品でも使う）
## ・本物のテクスチャ（assets/environment/underground_temple/textures/）が届くまでの仮のコンクリートと床
## ・デカールの台紙が届くまでの仮の白華・錆の垂れ・水跡、柱番号（フォントから一度だけ描く）
## ・色補正の3D LUT
## 画像はすべてシード固定で、何度作っても同じになる。

const NUMBER_FONT := "res://resources/fonts/NotoSansJP-Bold.otf"


static func _noise(seed: int, frequency: float, octaves := 4, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = kind
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Seamless value map 0..1 (size x size) as a float array.
static func _field(seed: int, size: int, frequency: float, octaves := 4) -> PackedFloat32Array:
	var image := _noise(seed, frequency, octaves).get_seamless_image(size, size, false, false, 0.1, true)
	image.convert(Image.FORMAT_L8)
	var data := image.get_data()
	var field := PackedFloat32Array()
	field.resize(size * size)
	for index in range(size * size):
		field[index] = float(data[index]) / 255.0
	return field


static func _texture(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Tiling grey noise for the world-space breakup in the hall shaders (R).
static func macro_noise(size := 256) -> ImageTexture:
	var field := _field(4711, size, 4.0 / float(size), 5)
	var image := Image.create_empty(size, size, false, Image.FORMAT_L8)
	var data := PackedByteArray()
	data.resize(size * size)
	for index in range(size * size):
		data[index] = int(clampf(field[index], 0.0, 1.0) * 255.0)
	image.set_data(size, size, false, Image.FORMAT_L8, data)
	return _texture(image)


## Normal map (OpenGL, +Y up) from a height field (metres per texel scaled by strength).
static func _normal_image(height: PackedFloat32Array, size: int, strength: float) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var l := height[y * size + (x - 1 + size) % size]
			var r := height[y * size + (x + 1) % size]
			var u := height[((y - 1 + size) % size) * size + x]
			var d := height[((y + 1) % size) * size + x]
			var n := Vector3((l - r) * strength, (d - u) * strength, 1.0).normalized()
			image.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	return image


## Placeholder cast-in-place concrete, 2 m per repeat: 1 x 2 m formwork panels with joint lips,
## tie holes, pores, blotchy tone. Returns {"albedo", "normal", "orm"}.
static func concrete_set(size := 512) -> Dictionary:
	var fine := _field(11, size, 24.0 / float(size), 4)
	var blotch := _field(12, size, 3.0 / float(size), 3)
	var pores := _field(13, size, 90.0 / float(size), 1)
	var px_per_m := float(size) / 2.0
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var holes: Array[Vector2] = []
	for panel_x in range(2):
		for hy: float in [0.25, 1.0, 1.75]:
			for hx: float in [0.25, 0.75]:
				holes.append(Vector2(float(panel_x) + hx, hy) * px_per_m)
	for y in range(size):
		for x in range(size):
			var index := y * size + x
			var h := fine[index] * 0.6 + blotch[index] * 0.4
			var cavity := 0.0
			# Panel joints: every 1 m across, every 2 m down (a thin lip of grout).
			var jx := minf(float(x % int(px_per_m)), px_per_m - float(x % int(px_per_m)))
			var jy := minf(float(y), float(size - y))
			var joint := maxf(1.0 - jx / 2.5, 1.0 - jy / 2.5)
			if joint > 0.0:
				h += joint * 0.9
				cavity = maxf(cavity, joint * 0.35)
			for hole: Vector2 in holes:
				var dist := Vector2(x, y).distance_to(hole)
				if dist < 7.0:
					var dip := 1.0 - dist / 7.0
					h -= dip * 2.5
					cavity = maxf(cavity, dip)
			if pores[index] > 0.83:
				h -= 0.6
				cavity = maxf(cavity, 0.45)
			height[index] = h
			var tone := 0.50 * (0.88 + 0.2 * blotch[index]) * (0.94 + 0.12 * fine[index]) * (1.0 - cavity * 0.45)
			albedo.set_pixel(x, y, Color(tone * 1.0, tone * 0.985, tone * 0.955, 1.0))
			var rough := clampf(0.80 + 0.14 * (fine[index] - 0.5) + cavity * 0.1, 0.0, 1.0)
			orm.set_pixel(x, y, Color(1.0 - cavity * 0.6, rough, 0.0, 1.0))
	return {"albedo": _texture(albedo), "normal": _texture(_normal_image(height, size, 0.35)), "orm": _texture(orm)}


## Placeholder floor slab, 2 m per repeat: troweled tone swirls, aggregate, a puddle mask in "wet".
static func floor_set(size := 512) -> Dictionary:
	var fine := _field(21, size, 30.0 / float(size), 4)
	var swirl := _field(22, size, 2.0 / float(size), 3)
	var grit := _field(23, size, 120.0 / float(size), 1)
	var puddle := _field(24, size, 1.5 / float(size), 3)
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var wet := Image.create_empty(size, size, false, Image.FORMAT_L8)
	for y in range(size):
		for x in range(size):
			var index := y * size + x
			var speck := 1.0 if grit[index] > 0.9 else 0.0
			height[index] = fine[index] * 0.5 + swirl[index] * 0.3 - speck * 0.3
			var tone := 0.36 * (0.86 + 0.22 * swirl[index]) * (0.95 + 0.1 * fine[index]) * (1.0 - speck * 0.15)
			albedo.set_pixel(x, y, Color(tone, tone * 0.99, tone * 0.965, 1.0))
			orm.set_pixel(x, y, Color(1.0 - speck * 0.3, clampf(0.62 + 0.25 * (fine[index] - 0.5), 0.0, 1.0), 0.0, 1.0))
			wet.set_pixel(x, y, Color(puddle[index], puddle[index], puddle[index]))
	return {"albedo": _texture(albedo), "normal": _texture(_normal_image(height, size, 0.25)), "orm": _texture(orm), "wet": _texture(wet)}


## Placeholder decal sprites (albedo with alpha). Kinds: efflorescence, rust, stain.
static func decal_sprite(kind: String, w := 128, h := 512) -> ImageTexture:
	var noise := _noise(31 + kind.length() * 7, 0.035, 4)
	var streaks := _noise(41 + kind.length(), 0.09, 2)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var u := (float(x) + 0.5) / float(w)
			var v := (float(y) + 0.5) / float(h)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var column := streaks.get_noise_2d(x * 1.0, y * 0.06) * 0.5 + 0.5
			var edge := smoothstep(0.0, 0.25, u) * smoothstep(1.0, 0.75, u)
			var color := Color(0.0, 0.0, 0.0, 0.0)
			match kind:
				"efflorescence":
					# White lime bloom running down from the top, thinning out.
					var run := smoothstep(0.35, 0.7, column) * (1.0 - v) * (0.6 + 0.4 * n)
					var top := smoothstep(0.25, 0.0, v) * (0.5 + 0.5 * n)
					color = Color(0.80, 0.79, 0.74, clampf((run + top) * edge * 1.4, 0.0, 0.85))
				"rust":
					var drip := smoothstep(0.55, 0.8, column) * pow(1.0 - v, 0.6)
					var head := smoothstep(0.12, 0.0, v)
					color = Color(0.36, 0.17, 0.06, clampf((drip + head * 0.8) * edge * (0.6 + 0.6 * n), 0.0, 0.9))
				_:
					# Dark water mark with a tide line.
					var blot := smoothstep(0.38, 0.62, n) * smoothstep(0.0, 0.2, v) * smoothstep(1.0, 0.7, v)
					var tide := smoothstep(0.06, 0.0, absf(v - 0.22 - 0.05 * n)) * 0.6
					color = Color(0.10, 0.10, 0.09, clampf((blot * 0.55 + tide) * edge, 0.0, 0.7))
			image.set_pixel(x, y, color)
	return _texture(image)


## A stencilled pillar number ("12-3") from the project font, rendered through the TextServer glyph cache
## (works headless, no viewport). Worn paint: alpha broken up by noise.
static func number_texture(text: String, w := 512, h := 256, color := Color(0.88, 0.86, 0.80)) -> ImageTexture:
	var font := load(NUMBER_FONT) as Font
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(color.r, color.g, color.b, 0.0))
	if font == null:
		return _texture(image)
	var ts := TextServerManager.get_primary_interface()
	var font_size := int(h * 0.62)
	var shaped := ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, font.get_rids(), font_size)
	ts.shaped_text_shape(shaped)
	var glyphs := ts.shaped_text_get_glyphs(shaped)
	var width := ts.shaped_text_get_width(shaped)
	var ascent := ts.shaped_text_get_ascent(shaped)
	var descent := ts.shaped_text_get_descent(shaped)
	var pen := Vector2((float(w) - width) * 0.5, (float(h) - (ascent + descent)) * 0.5 + ascent)
	var wear := _noise(77 + text.hash() % 1000, 0.06, 3)
	for glyph: Dictionary in glyphs:
		var font_rid: RID = glyph.get("font_rid", RID())
		var index: int = int(glyph.get("index", 0))
		var gsize := Vector2i(int(glyph.get("font_size", font_size)), 0)
		var at := pen + Vector2(glyph.get("offset", Vector2.ZERO))
		if font_rid.is_valid():
			ts.font_render_glyph(font_rid, gsize, index)
			var texture_index := ts.font_get_glyph_texture_idx(font_rid, gsize, index)
			if texture_index >= 0:
				var uv := ts.font_get_glyph_uv_rect(font_rid, gsize, index)
				var offset := ts.font_get_glyph_offset(font_rid, gsize, index)
				var glyph_size := ts.font_get_glyph_size(font_rid, gsize, index)
				var cache := ts.font_get_texture_image(font_rid, gsize, texture_index)
				if cache != null and glyph_size.x > 0.0 and glyph_size.y > 0.0:
					var origin := at + offset
					for gy in range(int(ceil(glyph_size.y))):
						for gx in range(int(ceil(glyph_size.x))):
							var tx := int(origin.x) + gx
							var ty := int(origin.y) + gy
							if tx < 0 or ty < 0 or tx >= w or ty >= h:
								continue
							var sx := int(uv.position.x + float(gx) * uv.size.x / glyph_size.x)
							var sy := int(uv.position.y + float(gy) * uv.size.y / glyph_size.y)
							if sx < 0 or sy < 0 or sx >= cache.get_width() or sy >= cache.get_height():
								continue
							var coverage := cache.get_pixel(sx, sy).a
							if coverage <= 0.0:
								continue
							var worn := smoothstep(0.15, 0.55, wear.get_noise_2d(tx, ty) * 0.5 + 0.5)
							var alpha := coverage * (0.55 + 0.4 * worn)
							var existing := image.get_pixel(tx, ty)
							image.set_pixel(tx, ty, Color(color.r, color.g, color.b, maxf(existing.a, alpha)))
		pen.x += float(glyph.get("advance", 0.0))
	ts.free_rid(shaped)
	return _texture(image)


## Subtle grade for the cistern (display-referred, applied after AgX): cool shadows, slightly warm
## highlights, a little less saturation in the mids, a soft S-curve. Returned as a strip image
## (size * size wide, size high; blue slice b at x = b * size): the headless dummy renderer keeps no
## Texture3D data, so CisternStage builds the ImageTexture3D from the strip when it makes the environment.
static func grade_lut_strip(size := 32) -> Image:
	var image := Image.create_empty(size * size, size, false, Image.FORMAT_RGB8)
	for b in range(size):
		for g in range(size):
			for r in range(size):
				var c := Vector3(float(r), float(g), float(b)) / float(size - 1)
				var lum := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				c = Vector3(lum, lum, lum).lerp(c, 0.9)
				var shadow := (1.0 - lum) * (1.0 - lum)
				var light := lum * lum
				c += Vector3(-0.010, 0.002, 0.014) * shadow + Vector3(0.016, 0.006, -0.012) * light
				var s := Vector3(smoothstep(0.0, 1.0, c.x), smoothstep(0.0, 1.0, c.y), smoothstep(0.0, 1.0, c.z))
				c = c.lerp(s, 0.14)
				c = c.clamp(Vector3.ZERO, Vector3.ONE)
				image.set_pixel(b * size + r, g, Color(c.x, c.y, c.z))
	return image
