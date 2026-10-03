class_name AeMotion
extends RefCounted

## After Effects compositions sampled by a sample_*.jsx script (e.g.
## assets/aiquiz_menu_stage/source/ae/sample_led.jsx), played back as Controls.
##
## Every AE layer becomes one Layer whose local space equals the AE layer space:
## position = AE position - anchor, pivot = anchor. Supported: rectangles, ellipses
## and straight open paths (fill, stroke with round or butt caps, Trim Paths Start /
## End), point text, image footage, nulls, parenting, and nested comps with their start
## offset (a nested comp clips to its bounds, as in AE). Nulls carry no opacity, as in AE, so their sampled opacity is
## available as `progress` for timing helpers. The owner fills in content through
## layer names: text, colours, textures, or a custom draw for media.

const FPS := 60.0

var data: Dictionary = {}


static func load_file(path: String) -> AeMotion:
	var motion := AeMotion.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	motion.data = parsed if parsed is Dictionary else {}
	return motion


func is_loaded() -> bool:
	return not comps().is_empty()


func comps() -> Dictionary:
	var value: Variant = data.get("comps")
	return value if value is Dictionary else {}


func has_comp(comp_name: String) -> bool:
	return comps().has(comp_name)


func duration(comp_name: String) -> float:
	return float((comps().get(comp_name, {}) as Dictionary).get("duration", 0.0))


## A playable instance of one comp. Nested comps named in `skip` are left out
## (the owner draws them itself). `images` maps footage file names to textures.
func instance(comp_name: String, font: Font, images: Dictionary = {}, skip: Array = []) -> Comp:
	var comp := Comp.new()
	comp.name = comp_name
	comp.duration = duration(comp_name)
	var record: Dictionary = comps().get(comp_name, {})
	var size: Array = record.get("size", [0, 0])
	comp.size = Vector2(float(size[0]), float(size[1]))
	comp.clip_contents = true
	comp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layers(comp, comp, record, "", 0.0, font, images, skip)
	return comp


func _build_layers(comp: Comp, holder: Control, record: Dictionary, prefix: String, offset: float,
		font: Font, images: Dictionary, skip: Array) -> void:
	var local := {}
	for layer_record: Dictionary in record.get("layers", []):
		if not bool(layer_record.get("enabled", true)) or str(layer_record.get("source", "")) in skip:
			continue
		var layer := Layer.new()
		layer.configure(layer_record, font, images)
		layer.time_offset = offset
		var parent_name: Variant = layer_record.get("parent")
		var parent: Control = local[parent_name] if parent_name != null and local.has(parent_name) else holder
		parent.add_child(layer)
		local[layer_record.name] = layer
		comp.layers.append(layer)
		comp.named[prefix + str(layer_record.name)] = layer
		if layer.kind == "precomp" and comps().has(layer.record.source):
			var nested: Dictionary = comps()[layer.record.source]
			var nested_size: Array = nested.get("size", [0, 0])
			layer.size = Vector2(float(nested_size[0]), float(nested_size[1]))
			layer.clip_contents = true
			_build_layers(comp, layer, nested, prefix + str(layer_record.name) + "/",
				offset + float(layer_record.get("start", 0.0)), font, images, skip)


## One played comp: a Control of the comp size holding the layer tree.
class Comp extends Control:
	var duration := 0.0
	var layers: Array[Layer] = []
	## "Layer" or "Precomp/Layer" -> Layer
	var named: Dictionary = {}

	func apply(time: float) -> void:
		for layer: Layer in layers:
			layer.apply(time - layer.time_offset)

	func layer(layer_name: String) -> Layer:
		return named.get(layer_name) as Layer


class Layer extends Control:
	var record: Dictionary
	var kind := ""
	var shape: Dictionary = {}
	var text_spec: Dictionary = {}
	var text := ""
	var fill_color := Color.WHITE
	var stroke_color := Color.WHITE
	var texture: Texture2D
	## Seconds between the top comp's clock and this layer's comp clock.
	var time_offset := 0.0
	## A null's sampled opacity, 0..1 (timing helper).
	var progress := 0.0
	## Trim Paths End, 0..1, times this factor (e.g. a percentage shown by a ring).
	var trim_scale := 1.0
	## Replaces the layer's own drawing: func(layer: Layer) -> void.
	var custom_draw: Callable
	## Extra uniform scale on top of AE's (fitting content the owner changed).
	var extra_scale := 1.0
	## Overrides for rect width (e.g. a pill fitted to its text), 0 = AE's.
	var width_override := 0.0
	## Hidden by the owner whatever the in/out points say.
	var forced_hidden := false
	## A straight path's end point x, NAN = AE's (e.g. a band fitted to its words).
	var line_end_x := NAN
	var font_variation: FontVariation
	var trim_start := 0.0
	var trim_end := 1.0

	func configure(value: Dictionary, base_font: Font, images: Dictionary) -> void:
		record = value
		name = str(value.name)
		kind = str(value.get("type", "other"))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if value.get("shape") is Dictionary:
			shape = value.shape
			if shape.has("fill"):
				fill_color = _color(shape.fill, float(shape.get("fillOpacity", 100.0)) / 100.0)
			if shape.has("stroke"):
				stroke_color = _color(shape.stroke, 1.0)
			if shape.get("trim") is Dictionary:
				trim_start = float(shape.trim.get("start", 0.0)) / 100.0
				trim_end = float(shape.trim.get("end", 100.0)) / 100.0
		if value.get("text") is Dictionary:
			text_spec = value.text
			text = str(text_spec.string)
			fill_color = _color(text_spec.fill, 1.0)
			if text_spec.has("stroke"):
				stroke_color = _color(text_spec.stroke, 1.0)
			font_variation = FontVariation.new()
			font_variation.base_font = base_font
			font_variation.spacing_glyph = int(round(float(text_spec.tracking) / 1000.0 * float(text_spec.size)))
		if value.get("image") is Dictionary:
			texture = images.get(str(value.image.file)) as Texture2D
			var image_size: Array = value.image.get("size", [0, 0])
			size = Vector2(float(image_size[0]), float(image_size[1]))

	static func _color(values: Array, alpha: float) -> Color:
		return Color(float(values[0]), float(values[1]), float(values[2]), alpha)

	## Changes an unanimated transform value (position, anchor, rotation...) of this
	## instance only; the motion data other instances share stays AE's.
	func override_base(key: String, value: Variant) -> void:
		if not has_meta("own_record"):
			record = record.duplicate(true)
			set_meta("own_record", true)
		(record.base as Dictionary)[key] = value

	static func sample_track(track: Variant, base: Variant, frame: float) -> Variant:
		if not track is Dictionary:
			return _as_value(base)
		var values: Array = track.values
		var f := clampf(frame - float(track.start), 0.0, float(values.size() - 1))
		var index := int(f)
		var a: Variant = _as_value(values[index])
		var b: Variant = _as_value(values[mini(index + 1, values.size() - 1)])
		if a is Vector2:
			return (a as Vector2).lerp(b, f - float(index))
		return lerpf(float(a), float(b), f - float(index))

	static func _as_value(value: Variant) -> Variant:
		if value is Array:
			return Vector2(float(value[0]), float(value[1]))
		return float(value)

	func sample(key: String, frame: float) -> Variant:
		return sample_track((record.tracks as Dictionary).get(key), record.base[key], frame)

	## time: seconds on the clock of the comp holding this layer.
	func apply(time: float) -> void:
		visible = not forced_hidden and time >= float(record.get("inPoint", 0.0)) and time < float(record.get("outPoint", INF))
		if not visible:
			return
		var frame := time * FPS
		var anchor: Vector2 = sample("anchor", frame)
		pivot_offset = anchor
		position = (sample("position", frame) as Vector2) - anchor
		scale = (sample("scale", frame) as Vector2) / 100.0 * extra_scale
		rotation = deg_to_rad(float(sample("rotation", frame)))
		var opacity := clampf(float(sample("opacity", frame)) / 100.0, 0.0, 1.0)
		if kind == "null":
			progress = opacity
		else:
			modulate.a = opacity
		if shape.get("trim") is Dictionary:
			var trim: Dictionary = shape.trim
			trim_end = float(sample_track(trim.get("track"), trim.get("end", 100.0), frame)) / 100.0
			trim_start = float(sample_track(trim.get("startTrack"), trim.get("start", 0.0), frame)) / 100.0
		if kind in ["shape", "text", "image"] or custom_draw.is_valid():
			queue_redraw()

	func _draw() -> void:
		if custom_draw.is_valid():
			custom_draw.call(self)
			return
		if not shape.is_empty():
			_draw_shape()
		elif not text_spec.is_empty() and not text.is_empty():
			_draw_text()
		elif texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)

	func shape_size() -> Vector2:
		var value := Vector2(float(shape.size[0]), float(shape.size[1]))
		if width_override > 0.0:
			value.x = width_override
		return value

	func _draw_shape() -> void:
		var stroke_width := float(shape.get("strokeWidth", 0.0))
		if shape.kind == "line":
			_draw_line(stroke_width)
			return
		var size_value := shape_size()
		if shape.kind == "ellipse":
			var radius := size_value.x * 0.5
			if shape.has("fill"):
				draw_circle(Vector2.ZERO, radius, fill_color, true, -1.0, true)
			if shape.has("stroke"):
				var from := 0.0
				var sweep := 1.0
				if shape.get("trim") is Dictionary:
					from = minf(trim_start, trim_end)
					sweep = clampf((maxf(trim_start, trim_end) - from) * trim_scale, 0.0, 1.0)
				if sweep > 0.001:
					# AE ellipse paths start at 12 o'clock and run clockwise.
					var start := -PI * 0.5 + TAU * from + deg_to_rad(float((shape.get("trim", {}) as Dictionary).get("offset", 0.0)))
					var points := maxi(8, int(96.0 * sweep))
					draw_arc(Vector2.ZERO, radius, start, start + TAU * sweep, points, stroke_color, stroke_width, true)
			return
		# AE strokes straddle the path; grow the box by half the stroke.
		var grow := stroke_width * 0.5
		var rect := Rect2(-size_value * 0.5 - Vector2.ONE * grow, size_value + Vector2.ONE * grow * 2.0)
		var box := StyleBoxFlat.new()
		box.bg_color = fill_color if shape.has("fill") else Color.TRANSPARENT
		box.set_corner_radius_all(int(minf(float(shape.get("radius", 0.0)) + grow, minf(rect.size.x, rect.size.y) * 0.5)))
		box.anti_aliasing = true
		if shape.has("stroke"):
			box.border_color = stroke_color
			box.set_border_width_all(int(round(stroke_width)))
		draw_style_box(box, rect)

	## The visible part of a trimmed straight path, as AE strokes it (caps on both ends).
	func _draw_line(width: float) -> void:
		var points: Array = shape.points
		var p0 := Vector2(float(points[0][0]), float(points[0][1]))
		var p1 := Vector2(float(points[1][0]), float(points[1][1]))
		if not is_nan(line_end_x):
			p1.x = line_end_x
		var from := clampf(minf(trim_start, trim_end), 0.0, 1.0)
		var to := clampf(maxf(trim_start, trim_end), 0.0, 1.0)
		if to - from < 0.0005 or width <= 0.0:
			return
		var a := p0.lerp(p1, from)
		var b := p0.lerp(p1, to)
		draw_line(a, b, stroke_color, width, true)
		if shape.get("cap", "butt") == "round":
			draw_circle(a, width * 0.5, stroke_color, true, -1.0, true)
			draw_circle(b, width * 0.5, stroke_color, true, -1.0, true)

	func text_width() -> float:
		return font_variation.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(float(text_spec.size)))).x

	func _draw_text() -> void:
		var font_size := int(round(float(text_spec.size)))
		var width := 4000.0
		var alignment := HORIZONTAL_ALIGNMENT_CENTER
		var origin := Vector2(-width * 0.5, 0.0)
		if text_spec.justification == "left":
			alignment = HORIZONTAL_ALIGNMENT_LEFT
			origin.x = 0.0
		elif text_spec.justification == "right":
			alignment = HORIZONTAL_ALIGNMENT_RIGHT
			origin.x = -width
		if text_spec.has("stroke"):
			draw_string_outline(font_variation, origin, text, alignment, width, font_size,
				int(round(float(text_spec.strokeWidth))), stroke_color)
		draw_string(font_variation, origin, text, alignment, width, font_size, fill_color)
