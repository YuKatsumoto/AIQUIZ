class_name ResultFinaleHud
extends Control

## Score Tower Finale HUD, played back from After Effects.
## hud_motion.json (assets/result_finale/source/sample_hud.jsx) carries every HUD_*
## precomp as native shapes/text plus 60 fps samples of each animated layer. Each AE
## layer becomes one Control whose local space equals the AE layer space:
## position = AE position - anchor, pivot = anchor. Numbers, player colours and
## localized captions are filled in here; timing and layout stay AE's.

const HUD_PATH := "res://assets/result_finale/hud_motion.json"
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const CANVAS := Vector2(1280, 720)
const FPS := 60.0
const FX_FPS := 30.0
const P_COLORS := [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]
const GOLD := Color(1.0, 0.824, 0.29)
const INK := Color(0.043, 0.071, 0.125)
const PALE := Color(0.961, 0.969, 1.0)
const LOCK_POP := 0.24
const TEXT_JA := {
	"TitleText": "スコアタワー", "RuleText": "正解数 × 残りHP で勝負！",
	"CaptionCorrect": "正解", "CaptionHp": "残りHP", "CaptionTotal": "合計",
	"VerdictSubWin": "おめでとう！", "VerdictSubDraw": "いい勝負！",
	"BtnRetryText": "もう一度", "BtnHistoryText": "履歴", "BtnMenuText": "メニュー",
}
const TEXT_EN := {
	"TitleText": "SCORE TOWER", "RuleText": "CORRECT × HP LEFT",
	"CaptionCorrect": "CORRECT", "CaptionHp": "HP LEFT", "CaptionTotal": "TOTAL",
	"VerdictSubWin": "CONGRATULATIONS!", "VerdictSubDraw": "WHAT A MATCH!",
	"BtnRetryText": "Play again", "BtnHistoryText": "History", "BtnMenuText": "Menu",
}


class AeLayer extends Control:
	var record: Dictionary
	var shape: Dictionary = {}
	var text_spec: Dictionary = {}
	var text := ""
	var fill_color: Color = Color.WHITE
	var mirror_x := false
	var extra_scale := 1.0
	var highlight := 0.0
	var font_variation: FontVariation

	func configure(value: Dictionary, base_font: Font, mirror: bool) -> void:
		record = value
		name = str(value.name)
		mirror_x = mirror
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if value.get("shape") is Dictionary:
			shape = value.shape
			if shape.has("fill"):
				fill_color = _color(shape.fill, float(shape.get("fillOpacity", 100.0)) / 100.0)
		if value.get("text") is Dictionary:
			text_spec = value.text
			text = str(text_spec.string)
			fill_color = _color(text_spec.fill, 1.0)
			font_variation = FontVariation.new()
			font_variation.base_font = base_font
			font_variation.spacing_glyph = int(round(float(text_spec.tracking) / 1000.0 * float(text_spec.size)))

	static func _color(values: Array, alpha: float) -> Color:
		return Color(float(values[0]), float(values[1]), float(values[2]), alpha)

	func sample(key: String, frame: float) -> Variant:
		var track: Variant = (record.tracks as Dictionary).get(key)
		var base: Variant = record.base[key]
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

	func apply(frame: float) -> void:
		var anchor: Vector2 = sample("anchor", frame)
		var pos: Vector2 = sample("position", frame)
		var rot: float = sample("rotation", frame)
		if mirror_x:
			pos.x = CANVAS.x - pos.x
			rot = -rot
		pivot_offset = anchor
		position = pos - anchor
		scale = (sample("scale", frame) as Vector2) / 100.0 * extra_scale
		rotation = deg_to_rad(rot)
		modulate.a = clampf(float(sample("opacity", frame)) / 100.0, 0.0, 1.0)
		if not shape.is_empty() or not text_spec.is_empty():
			queue_redraw()

	func _draw() -> void:
		if not shape.is_empty():
			var size_value := Vector2(float(shape.size[0]), float(shape.size[1]))
			var stroke_width := float(shape.get("strokeWidth", 0.0))
			if shape.kind == "ellipse":
				if shape.has("fill"):
					draw_circle(Vector2.ZERO, size_value.x * 0.5, fill_color, true, -1.0, true)
				if shape.has("stroke"):
					draw_arc(Vector2.ZERO, size_value.x * 0.5, 0.0, TAU, 64, _color(shape.stroke, 1.0), stroke_width, true)
			else:
				# AE strokes straddle the path; grow the box by half the stroke.
				var grow := stroke_width * 0.5
				var rect := Rect2(-size_value * 0.5 - Vector2.ONE * grow, size_value + Vector2.ONE * grow * 2.0)
				var box := StyleBoxFlat.new()
				box.bg_color = fill_color if shape.has("fill") else Color.TRANSPARENT
				box.set_corner_radius_all(int(minf(float(shape.get("radius", 0.0)) + grow, minf(rect.size.x, rect.size.y) * 0.5)))
				box.anti_aliasing = true
				if shape.has("stroke"):
					box.border_color = _color(shape.stroke, 1.0)
					box.set_border_width_all(int(round(stroke_width)))
				draw_style_box(box, rect)
				if highlight > 0.001:
					var ring := StyleBoxFlat.new()
					ring.bg_color = Color.TRANSPARENT
					ring.border_color = Color(GOLD, highlight)
					ring.set_border_width_all(3)
					ring.set_corner_radius_all(int(minf(float(shape.get("radius", 0.0)) + 6.0, (rect.size.y + 12.0) * 0.5)))
					draw_style_box(ring, rect.grow(6.0))
		if not text_spec.is_empty() and not text.is_empty():
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
					int(round(float(text_spec.strokeWidth))), _color(text_spec.stroke, 1.0))
			draw_string(font_variation, origin, text, alignment, width, font_size, fill_color)


class FxSprite extends Control:
	var frames: Array[Texture2D] = []
	var index := -1
	var tint := Color.WHITE
	var draw_scale := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive

	func show_frame(value: int) -> void:
		var clamped := value if value >= 0 and value < frames.size() else -1
		if clamped != index:
			index = clamped
			queue_redraw()

	func _draw() -> void:
		if index < 0:
			return
		var texture := frames[index]
		var extent := texture.get_size() * draw_scale
		draw_texture_rect(texture, Rect2(-extent * 0.5, extent), false, tint)


var game_state: QuizGameState
var _retry_action: Callable
var _history_action: Callable
var _menu_action: Callable
var _suppressed := false
var _focused := false
var _was_active := false
var _interactive_elapsed := 0.0
var _data: Dictionary = {}
var _canvas: Control
var _root: Control
var _layers: Array[AeLayer] = []
var _named: Dictionary = {}
var _built_winner := -2
var _burst: FxSprite
var _burst_centre := Vector2(640, 196)
var _lock_rings: Array[FxSprite] = []
var _flash: ColorRect
var _buttons: Array[Button] = []
var _stats: Label
var _burst_frames: Array[Texture2D] = []
var _lock_frames: Array[Texture2D] = []


func setup(state: QuizGameState, retry_action: Callable, history_action: Callable, menu_action: Callable) -> void:
	game_state = state
	_retry_action = retry_action
	_history_action = history_action
	_menu_action = menu_action
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HUD_PATH))
	_data = parsed if parsed is Dictionary else {}
	_burst_frames = _load_frames("burst", 24)
	_lock_frames = _load_frames("lock_ring", 15)
	_canvas = Control.new()
	_canvas.name = "CeremonyCanvas"
	_canvas.size = CANVAS
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	visible = false


func _load_frames(folder: String, count: int) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in range(count):
		var path := "res://assets/result_finale/fx/%s/%s_%02d.png" % [folder, folder, index]
		if ResourceLoader.exists(path):
			frames.append(load(path) as Texture2D)
	return frames


func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	if suppressed:
		visible = false
		_focused = false


func _text(key: String) -> String:
	var table: Dictionary = TEXT_EN if game_state.use_english_ui else TEXT_JA
	return str(table.get(key, ""))


func _build(winner: int) -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_layers.clear()
	_named.clear()
	_buttons.clear()
	_lock_rings.clear()
	_built_winner = winner
	_root = Control.new()
	_root.name = "FinaleHud"
	_root.size = CANVAS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_root)
	var master_name := "FINALE_HUD_Draw" if winner == 0 else "FINALE_HUD_Win"
	var comps: Dictionary = _data.get("comps", {})
	if not comps.has(master_name):
		return
	var mirror := winner == 2
	var master_nodes := {}
	for record: Dictionary in comps[master_name].layers:
		if record.name == "BurstPreview":
			# AE previews the rendered burst here; Godot plays the PNG frames at the same spot.
			var centre: Array = record.base.position
			_burst_centre = Vector2(float(centre[0]), float(centre[1]))
			continue
		if not bool(record.get("enabled", true)):
			continue
		if record.name == "Verdict":
			_burst = FxSprite.new()
			_burst.name = "VerdictBurst"
			_burst.frames = _burst_frames
			_burst.draw_scale = 1.7
			_burst.tint = Color(GOLD, 0.95)
			_root.add_child(_burst)
		var source := str(record.get("source", ""))
		if winner == 2 and source == "HUD_CardP1":
			source = "HUD_CardP2"
		elif winner == 2 and source == "HUD_CardP2":
			source = "HUD_CardP1"
		var layer := _make_layer(record, mirror and record.parent == null, "")
		var parent_name: Variant = record.get("parent")
		var holder: Control = master_nodes[parent_name] if parent_name != null and master_nodes.has(parent_name) else _root
		holder.add_child(layer)
		master_nodes[record.name] = layer
		if source != "" and comps.has(source):
			_add_precomp_children(layer, comps[source], record.name)
	for index in range(2):
		var ring := FxSprite.new()
		ring.name = "LockRingP%d" % (index + 1)
		ring.frames = _lock_frames
		ring.draw_scale = 1.1
		ring.tint = Color(P_COLORS[index], 1.0)
		_root.add_child(ring)
		_lock_rings.append(ring)
	_flash = ColorRect.new()
	_flash.name = "VerdictFlash"
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = CANVAS
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.position = Vector2(48, 692)
	_stats.size = Vector2(520, 24)
	_stats.add_theme_font_override("font", FONT)
	_stats.add_theme_font_size_override("font_size", 14)
	_stats.add_theme_color_override("font_color", PALE)
	_stats.add_theme_color_override("font_outline_color", INK)
	_stats.add_theme_constant_override("outline_size", 4)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stats)
	_configure_content(winner)


func _make_layer(record: Dictionary, mirror: bool, prefix: String) -> AeLayer:
	var layer := AeLayer.new()
	layer.configure(record, FONT, mirror)
	_layers.append(layer)
	_named[prefix + str(record.name)] = layer
	return layer


func _add_precomp_children(holder: Control, comp: Dictionary, prefix: String) -> void:
	var local_nodes := {}
	for record: Dictionary in comp.layers:
		var layer := _make_layer(record, false, prefix + "/")
		var parent_name: Variant = record.get("parent")
		(local_nodes[parent_name] if parent_name != null and local_nodes.has(parent_name) else holder).add_child(layer)
		local_nodes[record.name] = layer
		if record.name in ["BtnRetry", "BtnHistory", "BtnMenu"]:
			_add_button(layer, str(record.name))


func _add_button(layer: AeLayer, button_name: String) -> void:
	var button := Button.new()
	button.name = button_name
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(style, empty)
	var size_value := Vector2(float(layer.shape.size[0]), float(layer.shape.size[1]))
	button.position = -size_value * 0.5
	button.size = size_value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var action: Callable = _retry_action if button_name == "BtnRetry" else (_history_action if button_name == "BtnHistory" else _menu_action)
	button.pressed.connect(action)
	button.visible = false
	layer.add_child(button)
	_buttons.append(button)


func _configure_content(winner: int) -> void:
	for key: String in _named:
		var layer := _named[key] as AeLayer
		var short := key.get_slice("/", key.get_slice_count("/") - 1)
		if short in ["TitleText", "RuleText", "CaptionCorrect", "CaptionHp", "CaptionTotal", "BtnRetryText", "BtnHistoryText", "BtnMenuText"]:
			layer.text = _text(short)
		elif short == "VerdictSub":
			layer.text = _text("VerdictSubDraw" if winner == 0 else "VerdictSubWin")
	if winner > 0:
		var chip := _named.get("Verdict/PlayerChip") as AeLayer
		if chip != null:
			chip.fill_color = Color(P_COLORS[winner - 1], 1.0)
		var chip_text := _named.get("Verdict/PlayerChipText") as AeLayer
		if chip_text != null:
			chip_text.text = "P%d" % winner


## Master layer names for each player's card ("CardP1" is the winner role).
func _card_prefix(player_index: int) -> String:
	if _built_winner == 2:
		return "CardP1" if player_index == 2 else "CardP2"
	return "CardP%d" % player_index


func update_overlay(delta: float) -> void:
	var active := game_state != null and game_state.result_presentation_active and game_state.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
	visible = active and not _suppressed
	if not active:
		_was_active = false
		_focused = false
		_interactive_elapsed = 0.0
		return
	if not _was_active or _built_winner != game_state.result_winner:
		_build(game_state.result_winner)
	_was_active = true
	var viewport_size := get_viewport_rect().size
	size = viewport_size
	var fit := minf(viewport_size.x / CANVAS.x, viewport_size.y / CANVAS.y)
	_canvas.scale = Vector2.ONE * fit
	_canvas.position = (viewport_size - CANVAS * fit) * 0.5
	var interactive := game_state.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.INTERACTIVE
	_interactive_elapsed = _interactive_elapsed + maxf(0.0, delta) if interactive else 0.0
	var time := game_state.result_ceremony_elapsed + _interactive_elapsed
	_update_numbers(time)
	var frame := time * FPS
	for layer: AeLayer in _layers:
		layer.apply(frame)
	_update_fx(time)
	for button: Button in _buttons:
		button.visible = interactive
		var layer := button.get_parent() as AeLayer
		layer.highlight = 1.0 if interactive and (button.has_focus() or button.is_hovered()) else 0.0
	_stats.visible = interactive
	if interactive:
		_stats.modulate.a = smoothstep(0.1, 0.5, _interactive_elapsed)
		_stats.text = ("10 questions finished   •   %.1f sec" if game_state.use_english_ui else "10問完走   •   プレイ時間 %.1f 秒") % game_state.play_time
		if not _focused and not _suppressed and not _buttons.is_empty():
			_buttons[0].grab_focus()
			_focused = true


func _totals() -> Array[int]:
	return [game_state.result_p1_score, game_state.result_p2_score]


func _update_numbers(time: float) -> void:
	var totals := _totals()
	var max_total := maxi(totals[0], totals[1])
	for player_index in [1, 2]:
		var prefix := _card_prefix(player_index)
		var correct := game_state.result_p1_correct_count if player_index == 1 else game_state.result_p2_correct_count
		var hp := game_state.result_p1_hp if player_index == 1 else game_state.result_p2_hp
		var total: int = totals[player_index - 1]
		var correct_layer := _named.get(prefix + "/CorrectValue") as AeLayer
		var hp_layer := _named.get(prefix + "/HpValue") as AeLayer
		var total_layer := _named.get(prefix + "/TotalValue") as AeLayer
		if correct_layer != null:
			correct_layer.text = str(correct)
		if hp_layer != null:
			hp_layer.text = str(hp)
		if total_layer != null:
			var shown := total if time >= Motion.VERDICT else Motion.display_count(total, max_total, time)
			total_layer.text = str(shown)
			var lock := Motion.lock_time(total, max_total)
			var u := clampf((time - lock) / LOCK_POP, 0.0, 1.0)
			total_layer.extra_scale = 1.0 + (0.3 * sin(u * PI) if time >= lock else 0.0)


func _update_fx(time: float) -> void:
	var totals := _totals()
	var max_total := maxi(totals[0], totals[1])
	for index in range(_lock_rings.size()):
		var ring := _lock_rings[index]
		var lock := Motion.lock_time(totals[index], max_total)
		var total_layer := _named.get(_card_prefix(index + 1) + "/TotalValue") as AeLayer
		if total_layer != null:
			var local := _root.get_global_transform().affine_inverse() * total_layer.get_global_transform()
			ring.position = local * total_layer.pivot_offset
			ring.scale = Vector2.ONE * local.get_scale().x
		ring.show_frame(int(floor((time - lock) * FX_FPS)) if time >= lock else -1)
	if _burst != null:
		_burst.position = _burst_centre
		_burst.show_frame(int(floor((time - Motion.VERDICT) * FX_FPS)) if time >= Motion.VERDICT else -1)
	if _flash != null:
		var u := time - Motion.VERDICT
		_flash.color.a = 0.0 if u < 0.0 else 0.42 * (1.0 - smoothstep(0.0, 0.28, u))


func get_debug_snapshot() -> Dictionary:
	var totals: Array[String] = []
	for player_index in [1, 2]:
		var total_layer := _named.get(_card_prefix(player_index) + "/TotalValue") as AeLayer
		totals.append(total_layer.text if total_layer != null else "")
	var verdict := _named.get("Verdict") as AeLayer
	var word := _named.get("Verdict/VerdictWord") as AeLayer
	var cards := {}
	for player_index in [1, 2]:
		var card := _named.get(_card_prefix(player_index)) as AeLayer
		if card != null:
			cards[player_index] = {"rect": card.get_global_rect(), "opacity": card.modulate.a, "scale": card.scale.x}
	return {"motion_loaded": not _data.is_empty(), "layers": _layers.size(), "winner_built": _built_winner,
		"actions_visible": not _buttons.is_empty() and _buttons[0].visible,
		"buttons": _buttons.map(func(button: Button): return button.name),
		"totals": totals, "verdict": word.text if word != null else "",
		"verdict_visible": verdict != null and verdict.modulate.a > 0.5,
		"verdict_rect": verdict.get_global_rect() if verdict != null else Rect2(),
		"cards": cards, "burst_frame": _burst.index if _burst != null else -1,
		"lock_frames": _lock_rings.map(func(ring: FxSprite): return ring.index),
		"canvas_rect": _canvas.get_global_rect()}
