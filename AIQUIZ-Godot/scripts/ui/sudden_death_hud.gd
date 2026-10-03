class_name SuddenDeathHud
extends CanvasLayer

## 2Pサドンデス「早押し水没リフト」のHUD（docs/sudden_death_underground.md 第8章・2.1〜2.3節・5.3節）。
## One full-screen Control paints every element from its own timeline, so each
## piece can slam, overshoot and wipe like the After Effects finale HUD
## (result_finale_hud.gd): heavy Noto Sans JP, ink outlines, hazard tape.
## Animation runs on unscaled real time (Time.get_ticks_usec), so it keeps its
## pace during the 0.5x slow motion of the decisive moment. Layout is authored on
## a 1280x720 reference and anchored to the visible rect (4:3 and 21:9 included).
## Nothing here takes mouse input. The director only calls the public methods.

const REFERENCE := Vector2(1280.0, 720.0)
## Above the gameplay HUD (5) and below the ghost shark HUD (12), pause menu and
## scene transition (100).
const HUD_LAYER := 8
const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

const INK := Color(0.043, 0.071, 0.125)
const PALE := Color(0.961, 0.969, 1.0)
const GOLD := Color(1.0, 0.824, 0.29)
const HAZARD := Color(1.0, 0.77, 0.07)
const HAZARD_DARK := Color(0.07, 0.07, 0.08)
## Sodium lamp amber of the shaft (spec 5.1, #FFA51F).
const SODIUM := Color(1.0, 0.647, 0.122)
const RED := Color(1.0, 0.23, 0.17)
const SOFT_RED := Color(1.0, 0.45, 0.38)
const BLOOD := Color(0.43, 0.02, 0.03)
## ResultFinaleStage.P1_COLOR / P2_COLOR.
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]

## Longest real-time step one frame may take; a longer stall (pause, hitch) does
## not skip whole animations.
const MAX_STEP := 0.25
## Baseline below the visual middle of a line, in em (Noto Sans JP caps and kana).
const BASELINE := 0.36
## Fade length for hide_all() of the externally driven elements.
const HIDE_FADE := 0.3
const HAZARD_TILE := 44.0

const CUT_IN_Y := 0.44
const CUT_IN_ANGLE := -6.0
const CUT_IN_CORE := 176.0
const CUT_IN_SIZE := 112
const CUT_IN_SLAM_AT := 0.1
const CUT_IN_FALL := 0.15
const CUT_IN_HOLD_END := 1.9
const CUT_IN_OUT := 0.34

const DEPTH_MAX := 70.0
const DEPTH_PANEL := Vector2(128.0, 432.0)
const DEPTH_TRACK_TOP := 58.0
const DEPTH_PX_PER_M := 3.7

## Between the two lift towers, under the question panel.
const CALLOUT_Y := 0.44
const CALLOUT_PITCH := 56.0
const CALLOUT_IN := 0.24
const CALLOUT_OUT := 0.26
const CALLOUT_HEIGHT := 62.0
const CALLOUT_SIZE := 38
## Callouts kept stacked; an older one starts fading out right away.
const CALLOUT_MAX := 2

const SHOUT_Y := 0.25
const SHOUT_SIZE := 92
const SHOUT_HOLD_END := 1.35
const SHOUT_OUT := 0.25

const RULE_Y := 0.55
const RULE_SIZE := Vector2(680.0, 246.0)
## Extra card height for the "press Enter" line of a held card (the card's top edge stays put).
const RULE_PROMPT_HEIGHT := 58.0

const COUNT_Y := 0.42
const COUNT_FALL := 0.12
const COUNT_NUMBER_LIFE := 1.5
const COUNT_GO_LIFE := 0.85

const WIN_Y := 0.31

## The buzzer duel (8): question panel at the top, choices along the bottom, lift gauges at the sides.
const QUIZ_Y := 0.03
const QUIZ_PANEL_WIDTH := 1040.0
const QUIZ_TEXT_SIZE := 30
const QUIZ_LINE := 42.0
const CHOICE_Y := 0.835
const CHOICE_HEIGHT := 62.0
const CHOICE_MAX_WIDTH := 300.0
const CHOICE_TEXT_SIZE := 26
const GAUGE_Y := 0.56
const GOOD := Color(0.42, 1.0, 0.55)
const WATER := Color(0.16, 0.36, 0.48)
## Answer key labels by QuizGameState.SUDDEN_DEATH_KEY_* (left, up, down, right): P1, P2.
const KEY_LABELS := [["A", "W", "S", "D"], ["←", "↑", "↓", "→"]]
const WIN_FALL := 0.16
const WIN_SIZE := 140

const TEXT_JA := {
	"depth": "深度", "loading": "準備中", "arrived": "到着", "generating": "問題を生成中",
	"referee": "審判", "rules": "ルール", "press": "でスタート",
}
const TEXT_EN := {
	"depth": "DEPTH", "loading": "LOADING", "arrived": "ARRIVED", "generating": "GENERATING",
	"referee": "REFEREE", "rules": "RULES", "press": "TO START",
}
## Rule card lines as [text, tone] runs: tone "w" plain, "y" key word, "r" danger.
const RULES_JA := [
	[["ジャンプキー", "y"], ["で早押し。押した人だけが答えられる", "w"]],
	[["答えは方向キー", "y"], ["（P1は W A S D、P2は ↑ ← ↓ →）", "w"]],
	[["正解", "y"], ["で相手のリフトが", "w"], ["沈む", "r"], ["。不正解なら自分が沈む", "w"]],
	[["水に沈んだら", "w"], ["負け", "r"], ["。誰も押さないと両方が少し沈む", "w"]],
]
const RULES_EN := [
	[["JUMP", "y"], [" to buzz in - only the buzzer answers", "w"]],
	[["Answer with the ", "w"], ["ARROWS", "y"], [" (P1 W A S D, P2 ↑ ← ↓ →)", "w"]],
	[["Right: the rival's lift ", "w"], ["SINKS", "r"], [". Wrong: yours does", "w"]],
	[["Under the water = ", "w"], ["OUT", "r"], [". No buzz: both sink a little", "w"]],
]


## Paints the whole HUD; the parent keeps every timeline.
class Painter extends Control:
	var hud: SuddenDeathHud

	func _draw() -> void:
		if hud != null:
			hud._paint(self)


## Tests drive the clock by hand through debug_step(); the game never sets this.
var debug_manual_clock := false

var _english := false
var _root: Control
var _danger_rect: ColorRect
var _danger_material: ShaderMaterial
var _painter: Painter
var _flash_rect: ColorRect
## Bold with tabular digits (depth readout, chips).
var _font: FontVariation
## Bold, tracked out for small labels.
var _font_wide: FontVariation
## Emboldened and slanted for every slam.
var _font_heavy: FontVariation
var _hazard_texture: ImageTexture
var _glow_texture: GradientTexture2D
var _box := StyleBoxFlat.new()
var _clock := 0.0
var _last_usec := 0
var _prewarm_pending := true
var _was_drawing := false
## Last painted screen rect of each element (viewport units), for tests.
var _rects := {}

var _flash_start := -INF
var _flash_strength := 0.0
var _flash_duration := 0.25

var _cut_on := false
var _cut_text := ""
var _cut_start := 0.0
var _cut_out_at := CUT_IN_HOLD_END

var _depth_amount := 0.0
var _depth_m := 0.0
var _depth_loading := false
## While loading: "loading" (default) or "generating" (online questions for the sudden death).
var _depth_status := "loading"
var _depth_hide_at := INF

var _letterbox := 0.0
var _letterbox_hide_at := INF

var _shout_on := false
var _shout_text := ""
var _shout_start := 0.0
var _shout_out_at := SHOUT_HOLD_END

var _rule_on := false
var _rule_start := 0.0
var _rule_duration := 2.0
## Fixed when the card is shown, so dismissing a held card early does not flip it to the short form.
var _rule_is_short := false
## A held card carries the "press Enter" line.
var _rule_prompt := false

var _count_text := ""
var _count_start := 0.0
var _count_prev_text := ""
var _count_prev_start := -INF

## {text, color, start, duration, slot}; oldest first.
var _callouts: Array[Dictionary] = []

var _danger := 0.0
var _danger_hide_at := INF
var _danger_phase := 0.0

var _winner := 0
var _winner_start := 0.0
var _winner_out_at := INF

## The buzzer duel's state from the director ({} = none), when this question's panel came in, when its
## result came in, and when it started to fade out.
var _quiz: Dictionary = {}
var _quiz_start := 0.0
var _result_start := 0.0
var _quiz_hide_at := INF


func _init() -> void:
	name = "SuddenDeathHud"
	layer = HUD_LAYER
	_build_fonts()
	_build_textures()
	_build_nodes()


# ------------------------------------------------------------------ public API

func setup(english: bool) -> void:
	_english = english
	_prewarm_pending = true
	_painter.queue_redraw()


## 2.1: a diagonal black band opens, the text slams in with a white flash, holds
## about 1.5 s, then the band closes and the text fades (2.24 s in all).
func show_cut_in(text := "SUDDEN DEATH!") -> void:
	_cut_on = true
	_cut_text = text
	_cut_start = _clock
	_cut_out_at = CUT_IN_HOLD_END
	_start_flash(0.6, 0.3, _clock + CUT_IN_SLAM_AT + CUT_IN_FALL)


## Full-screen white flash that decays over [param duration] seconds.
func flash(strength := 1.0, duration := 0.25) -> void:
	_start_flash(strength, duration, _clock)


## 5.3: depth meter on the right edge. [param depth_m] is metres below the
## surface (sign ignored). [param visible_amount] slides it in (1) and out (0).
func set_depth_meter(visible_amount: float, depth_m: float, loading: bool) -> void:
	_depth_amount = clampf(visible_amount, 0.0, 1.0)
	_depth_m = absf(depth_m)
	_depth_loading = loading
	if _depth_amount > 0.0:
		_depth_hide_at = INF


## What the pulsing status under the meter says while loading: &"loading" or &"generating".
func set_depth_status(status: StringName) -> void:
	_depth_status = "generating" if status == &"generating" else "loading"


## Cinematic bars, 0..1 (eased here).
func set_letterbox(amount: float) -> void:
	_letterbox = clampf(amount, 0.0, 1.0)
	if _letterbox > 0.0:
		_letterbox_hide_at = INF


## 2.2: the referee's shout with an echo trail (two fading repeats).
func show_shout(text: String) -> void:
	_shout_on = true
	_shout_text = text
	_shout_start = _clock
	_shout_out_at = SHOUT_HOLD_END


## 2.2: the three rules. [param duration] is the whole time on screen including
## the in/out animation; under 1.5 s plays the short form (no stagger). INF holds the
## card, with a "press Enter" line, until dismiss_rule_card().
func show_rule_card(duration: float) -> void:
	_rule_on = true
	_rule_start = _clock
	_rule_duration = maxf(duration, 0.5)
	_rule_is_short = _rule_duration < 1.5
	_rule_prompt = is_inf(duration)
	# The referee's caption leaves room for the card.
	if _shout_on:
		_shout_out_at = minf(_shout_out_at, maxf(_clock - _shout_start, 0.8))


## 2.2: the card (held or timed) slides out from now.
func dismiss_rule_card() -> void:
	if _rule_on:
		_rule_duration = minf(_rule_duration, _clock - _rule_start + _rule_out_time())


## 2.2: "3", "2", "1", "GO!" slams. Call on change or every frame; "" clears.
func set_countdown(text: String) -> void:
	if text == _count_text:
		return
	if _count_text != "" and _count_alpha() > 0.01:
		_count_prev_text = _count_text
		_count_prev_start = _clock
	_count_text = text
	_count_start = _clock
	if _is_go(text):
		_start_flash(0.22, 0.22, _clock + COUNT_FALL)


## Event callout ("P1 SAFE!", "閉門！" ...). A leading "P1 " / "P2 " becomes a
## player chip. Newer callouts push older ones down (three at most).
func callout(text: String, color: Color, duration := 1.2) -> void:
	# The new one takes slot 0; the others glide down from where they are.
	_callouts.append({"text": text, "color": color, "start": _clock, "duration": maxf(duration, 0.5), "slot": 0.0})
	while _callouts.size() > CALLOUT_MAX + 1:
		_callouts.remove_at(0)
	for index in range(_callouts.size() - CALLOUT_MAX):
		var entry := _callouts[index]
		entry.duration = minf(float(entry.duration), _clock - float(entry.start) + CALLOUT_OUT * 0.6)


## Red edge vignette, 0..1; it beats faster as it grows.
func set_danger(amount: float) -> void:
	_danger = clampf(amount, 0.0, 1.0)
	if _danger > 0.0:
		_danger_hide_at = INF


## 2.3: "P1 WIN!" in the player's colour with a "SUDDEN DEATH" sub-line. Stays
## until hide_all().
func show_winner(player_index: int) -> void:
	_winner = clampi(player_index, 1, 2)
	_winner_start = _clock
	_winner_out_at = INF
	_start_flash(0.45, 0.3, _clock + WIN_FALL)


## The buzzer duel (8): question, choices, timer and lift gauges. Call every frame; {} hides them.
## Keys: number, text, revealed, choices, keys (answer key per choice), phase ("intro", "reading",
## "answering", "result"), timer (0..1), timer_mode ("think", "answer", ""), buzzer, chosen, answer,
## result, margins ([P1, P2] half steps), max_margin.
func set_quiz(state: Dictionary) -> void:
	if state.is_empty():
		if not _quiz.is_empty() and is_inf(_quiz_hide_at):
			_quiz_hide_at = _clock
		return
	var number := int(state.get("number", 0))
	if _quiz.is_empty() or int(_quiz.get("number", -1)) != number or not is_inf(_quiz_hide_at):
		_quiz_start = _clock
	if str(state.get("phase", "")) == "result" and str(_quiz.get("phase", "")) != "result":
		_result_start = _clock
	_quiz = state.duplicate()
	_quiz_hide_at = INF


func hide_all(immediate := false) -> void:
	if immediate:
		_quiz = {}
		_quiz_hide_at = INF
		_cut_on = false
		_shout_on = false
		_rule_on = false
		_count_text = ""
		_count_prev_text = ""
		_callouts.clear()
		_winner = 0
		_depth_amount = 0.0
		_letterbox = 0.0
		_danger = 0.0
		_flash_strength = 0.0
		_advance(0.0)
		return
	if _cut_on:
		_cut_out_at = minf(_cut_out_at, maxf(_clock - _cut_start, CUT_IN_SLAM_AT))
	if _shout_on:
		_shout_out_at = minf(_shout_out_at, _clock - _shout_start)
	dismiss_rule_card()
	set_countdown("")
	for entry: Dictionary in _callouts:
		var t := _clock - float(entry.start)
		entry.duration = minf(float(entry.duration), t + CALLOUT_OUT)
	if _winner > 0:
		_winner_out_at = minf(_winner_out_at, _clock - _winner_start)
	_depth_hide_at = minf(_depth_hide_at, _clock)
	_letterbox_hide_at = minf(_letterbox_hide_at, _clock)
	_danger_hide_at = minf(_danger_hide_at, _clock)
	set_quiz({})


## Advances the HUD clock by hand (tests with debug_manual_clock).
func debug_step(seconds: float) -> void:
	_advance(maxf(seconds, 0.0))


func get_debug_snapshot() -> Dictionary:
	var callouts: Array = []
	for entry: Dictionary in _callouts:
		callouts.append({"text": entry.text, "color": (entry.color as Color).to_html(false),
			"alpha": snappedf(_callout_alpha(entry), 0.001), "slot": snappedf(float(entry.slot), 0.01)})
	var rules: Array[String] = []
	for line: Array in (RULES_EN if _english else RULES_JA):
		rules.append(_plain(line))
	return {
		"layer": layer, "english": _english, "clock": _clock,
		"mouse_ignored": _all_mouse_ignored(),
		"flash": snappedf(_flash_alpha(), 0.001),
		"cut_in": {"visible": _cut_alpha() > 0.01, "text": _cut_text if _cut_on else "", "phase": _cut_phase()},
		"depth_meter": {"visible": _depth_alpha() > 0.01, "amount": _depth_alpha(), "depth_m": _depth_m,
			"readout": _depth_readout(), "loading": _depth_loading,
			"status": _t(_depth_status) if _depth_loading else _t("arrived") if _depth_m >= DEPTH_MAX - 0.5 else ""},
		"letterbox": {"visible": _letterbox_amount() > 0.01, "amount": snappedf(_letterbox_amount(), 0.001),
			"bar_px": snappedf(_letterbox_px(_root.size), 0.1)},
		"shout": {"visible": _shout_alpha() > 0.01, "text": _shout_text if _shout_on else "", "tag": _t("referee")},
		"rule_card": {"visible": _rule_alpha() > 0.01, "short": _rule_on and _rule_short(),
			"hold": _rule_on and is_inf(_rule_duration),
			"title": _t("rules"), "lines": rules if _rule_on else []},
		"countdown": {"visible": _count_alpha() > 0.01, "text": _count_text},
		"callouts": callouts,
		"callout": str(_callouts.back().text) if not _callouts.is_empty() else "",
		"danger": snappedf(_danger_amount(), 0.001),
		"winner": {"visible": _winner_alpha() > 0.01, "player": _winner,
			"title": "P%d WIN!" % _winner if _winner > 0 else "", "sub": "SUDDEN DEATH" if _winner > 0 else ""},
		"quiz": {"visible": _quiz_alpha() > 0.01, "number": int(_quiz.get("number", 0)), "phase": str(_quiz.get("phase", "")),
			"revealed": int(_quiz.get("revealed", 0)), "text": str(_quiz.get("text", "")), "buzzer": int(_quiz.get("buzzer", 0)),
			"result": str(_quiz.get("result", "")), "margins": _quiz.get("margins", []), "choices": _quiz.get("choices", PackedStringArray())},
		"rects": _rects.duplicate(),
	}


# ------------------------------------------------------------------ build

func _build_fonts() -> void:
	_font = FontVariation.new()
	_font.base_font = FONT_BOLD
	_font.opentype_features = {"tnum": 1}
	_font_wide = FontVariation.new()
	_font_wide.base_font = FONT_BOLD
	_font_wide.spacing_glyph = 3
	_font_heavy = FontVariation.new()
	_font_heavy.base_font = FONT_BOLD
	_font_heavy.variation_embolden = 0.75
	_font_heavy.spacing_glyph = 1
	# Italic by shearing the outlines (see FontVariation.variation_transform).
	_font_heavy.variation_transform = Transform2D(Vector2(1.0, 0.16), Vector2(0.0, 1.0), Vector2.ZERO)


func _build_textures() -> void:
	# 45° hazard tape, two stripes per 64 px tile so it repeats seamlessly.
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var f := fposmod(float(x + y) + 1.0, 32.0)
			var distance := minf(f, 16.0 - f) if f < 16.0 else -minf(f - 16.0, 32.0 - f)
			image.set_pixel(x, y, HAZARD_DARK.lerp(HAZARD, clampf(0.5 + distance / 1.41, 0.0, 1.0)))
	_hazard_texture = ImageTexture.create_from_image(image)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.4, Color(1.0, 1.0, 1.0, 0.45))
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
	_glow_texture.width = 128
	_glow_texture.height = 128


func _build_nodes() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float beat = 0.0;
uniform vec4 tint : source_color = vec4(0.92, 0.07, 0.04, 1.0);
void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	// Rounded-rectangle falloff so every edge glows evenly at any aspect.
	float edge = mix(length(p) * 0.7071, max(p.x, p.y), 0.55);
	float a = smoothstep(0.55, 1.05, edge);
	COLOR = vec4(tint.rgb, tint.a * a * amount * (0.45 + 0.45 * beat));
}
"""
	_danger_material = ShaderMaterial.new()
	_danger_material.shader = shader
	_danger_rect = ColorRect.new()
	_danger_rect.name = "Danger"
	_danger_rect.material = _danger_material
	_danger_rect.visible = false
	_add_full_rect(_danger_rect)
	_painter = Painter.new()
	_painter.name = "Painter"
	_painter.hud = self
	_painter.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_add_full_rect(_painter)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.visible = false
	_add_full_rect(_flash_rect)


func _add_full_rect(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.focus_mode = Control.FOCUS_NONE
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(control)


# ------------------------------------------------------------------ clock

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
	var step := clampf(float(now - _last_usec) / 1000000.0, 0.0, MAX_STEP)
	_last_usec = now
	if not debug_manual_clock:
		_advance(step)


func _advance(dt: float) -> void:
	_clock += dt
	_danger_phase += dt * lerpf(1.1, 2.4, _danger)
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _callouts:
		if _clock - float(entry.start) < float(entry.duration):
			keep.append(entry)
	_callouts = keep
	var smoothing := 1.0 - exp(-dt * 16.0)
	for index in range(_callouts.size()):
		# A callout pushed past the stack fades where the last slot is.
		var target := float(mini(_callouts.size() - 1 - index, CALLOUT_MAX - 1))
		_callouts[index].slot = lerpf(float(_callouts[index].slot), target, smoothing)
	if _cut_on and _clock - _cut_start > _cut_out_at + CUT_IN_OUT:
		_cut_on = false
	if _shout_on and _clock - _shout_start > _shout_out_at + SHOUT_OUT:
		_shout_on = false
	if _rule_on and _clock - _rule_start > _rule_duration:
		_rule_on = false
	if _winner > 0 and _clock - _winner_start > _winner_out_at + 0.3:
		_winner = 0
	if _count_text != "" and _count_alpha() <= 0.0 and _clock - _count_start > 0.5:
		_count_text = ""
	if not _quiz.is_empty() and not is_inf(_quiz_hide_at) and _clock - _quiz_hide_at > HIDE_FADE:
		_quiz = {}
		_quiz_hide_at = INF
	var flash_alpha := _flash_alpha()
	_flash_rect.visible = flash_alpha > 0.001
	_flash_rect.color.a = flash_alpha
	var danger := _danger_amount()
	_danger_rect.visible = danger > 0.001
	if _danger_rect.visible:
		var beat := pow(0.5 + 0.5 * sin(_danger_phase * TAU), 2.0)
		_danger_material.set_shader_parameter("amount", danger)
		_danger_material.set_shader_parameter("beat", beat)
	var drawing := _any_painted()
	if drawing or _was_drawing or _prewarm_pending:
		_painter.queue_redraw()
	_was_drawing = drawing


func _any_painted() -> bool:
	return _cut_on or _shout_on or _rule_on or _winner > 0 or not _quiz.is_empty() \
		or not _callouts.is_empty() or _depth_alpha() > 0.0 or _letterbox_amount() > 0.0 \
		or _count_text != "" or _clock - _count_prev_start < 0.25


# ------------------------------------------------------------------ element state

func _t(key: String) -> String:
	return str((TEXT_EN if _english else TEXT_JA).get(key, key))


func _start_flash(strength: float, duration: float, start: float) -> void:
	if start <= _clock and _flash_alpha() > strength:
		return
	_flash_start = start
	_flash_strength = clampf(strength, 0.0, 1.0)
	_flash_duration = maxf(duration, 0.01)


func _flash_alpha() -> float:
	var p := (_clock - _flash_start) / _flash_duration
	if p < 0.0 or p >= 1.0:
		return 0.0
	return _flash_strength * pow(1.0 - p, 2.0)


func _hide_fade(hide_at: float) -> float:
	return 1.0 - smoothstep(0.0, HIDE_FADE, _clock - hide_at) if hide_at < INF else 1.0


func _cut_phase() -> String:
	if not _cut_on:
		return ""
	var t := _clock - _cut_start
	if t < CUT_IN_SLAM_AT + CUT_IN_FALL:
		return "in"
	return "hold" if t < _cut_out_at else "out"


func _cut_alpha() -> float:
	if not _cut_on:
		return 0.0
	var out := clampf((_clock - _cut_start - _cut_out_at) / CUT_IN_OUT, 0.0, 1.0)
	return 1.0 - out


func _depth_alpha() -> float:
	return _depth_amount * _hide_fade(_depth_hide_at)


func _depth_readout() -> String:
	var metres := int(round(minf(_depth_m, 999.0)))
	return "0m" if metres == 0 else "−%dm" % metres


func _letterbox_amount() -> float:
	return _letterbox * _hide_fade(_letterbox_hide_at)


## Bar height that frames the shot near 2.39:1, kept sane on 4:3 and 21:9.
func _letterbox_px(viewport: Vector2) -> float:
	var full := clampf((viewport.y - viewport.x / 2.39) * 0.5, viewport.y * 0.07, viewport.y * 0.14)
	return full * smoothstep(0.0, 1.0, _letterbox_amount())


func _danger_amount() -> float:
	return _danger * _hide_fade(_danger_hide_at)


func _shout_alpha() -> float:
	if not _shout_on:
		return 0.0
	var t := _clock - _shout_start
	return clampf(t / 0.05, 0.0, 1.0) * (1.0 - clampf((t - _shout_out_at) / SHOUT_OUT, 0.0, 1.0))


func _rule_short() -> bool:
	return _rule_is_short


func _rule_in_time() -> float:
	return 0.18 if _rule_short() else 0.3


func _rule_out_time() -> float:
	return 0.16 if _rule_short() else 0.24


func _rule_alpha() -> float:
	if not _rule_on:
		return 0.0
	var t := _clock - _rule_start
	var out := clampf((t - (_rule_duration - _rule_out_time())) / _rule_out_time(), 0.0, 1.0)
	return clampf(t / 0.08, 0.0, 1.0) * (1.0 - out)


func _is_go(text: String) -> bool:
	return text.to_upper().begins_with("GO")


func _count_life(text: String) -> float:
	return COUNT_GO_LIFE if _is_go(text) else COUNT_NUMBER_LIFE


func _count_alpha() -> float:
	if _count_text == "":
		return 0.0
	var t := _clock - _count_start
	var out := clampf((t - _count_life(_count_text)) / 0.2, 0.0, 1.0)
	return clampf(t / 0.05, 0.0, 1.0) * (1.0 - out)


func _callout_alpha(entry: Dictionary) -> float:
	var t := _clock - float(entry.start)
	var duration := float(entry.duration)
	var out := clampf((t - (duration - CALLOUT_OUT)) / CALLOUT_OUT, 0.0, 1.0)
	return clampf(t / 0.06, 0.0, 1.0) * (1.0 - out) * lerpf(1.0, 0.72, minf(float(entry.slot), 1.0))


func _winner_alpha() -> float:
	if _winner <= 0:
		return 0.0
	var t := _clock - _winner_start
	return clampf(t / 0.06, 0.0, 1.0) * (1.0 - clampf((t - _winner_out_at) / 0.3, 0.0, 1.0))


func _all_mouse_ignored() -> bool:
	for control: Control in [_root, _danger_rect, _painter, _flash_rect]:
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


# ------------------------------------------------------------------ paint

func _paint(ci: Control) -> void:
	var viewport := ci.size
	var u := minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y)
	_rects.clear()
	if _prewarm_pending:
		_prewarm_pending = false
		_prewarm(ci)
	_paint_winner_rays(ci, viewport, u)
	_paint_letterbox(ci, viewport)
	_paint_depth(ci, viewport, u)
	_paint_quiz(ci, viewport, u)
	_paint_callouts(ci, viewport, u)
	_paint_rule_card(ci, viewport, u)
	_paint_shout(ci, viewport, u)
	_paint_countdown(ci, viewport, u)
	_paint_winner(ci, viewport, u)
	_paint_cut_in(ci, viewport, u)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Rasterises the big glyphs once (invisible) so the first slam does not hitch.
func _prewarm(ci: Control) -> void:
	var hidden := Color(1.0, 1.0, 1.0, 0.0)
	var at := Vector2(-4000.0, -4000.0)
	var items := [
		[_font_heavy, "SUDDEN DEATH!", CUT_IN_SIZE, [22]],
		[_font_heavy, "0123456789", 190, [24]],
		[_font_heavy, "GO!", 150, [24]],
		[_font_heavy, "P12 WIN!", WIN_SIZE, [24, 10]],
		[_font_heavy, "サドンデス！SUDDEN DEATH!", SHOUT_SIZE, [22, 12, 5]],
		[_font_heavy, "P12 SAFE!OUT!不正解！閉門！", CALLOUT_SIZE, [8]],
		[_font_heavy, "早押し！正解不正解時間切れ答えられず沈む水没CORRECTWRONGTIMEUP", CALLOUT_SIZE, [8]],
		[_font_heavy, "第0123456789問 早押しクイズ わかったら回答中", 26, [0]],
		[_font_heavy, "ABCD AWSD ←↑↓→ …", 26, [0]],
	]
	for item: Array in items:
		var font := item[0] as Font
		ci.draw_string(font, at, str(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(item[2]), hidden)
		for outline: int in item[3]:
			ci.draw_string_outline(font, at, str(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(item[2]), outline, hidden)


func _paint_letterbox(ci: Control, viewport: Vector2) -> void:
	var bar := _letterbox_px(viewport)
	if bar <= 0.05:
		return
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	ci.draw_rect(Rect2(0.0, 0.0, viewport.x, bar), Color.BLACK)
	ci.draw_rect(Rect2(0.0, viewport.y - bar, viewport.x, bar), Color.BLACK)
	_rects["letterbox_top"] = Rect2(0.0, 0.0, viewport.x, bar)
	_rects["letterbox_bottom"] = Rect2(0.0, viewport.y - bar, viewport.x, bar)


# ---------------------------------------------------------------- cut-in (2.1)

func _paint_cut_in(ci: Control, viewport: Vector2, u: float) -> void:
	if not _cut_on:
		return
	var t := _clock - _cut_start
	var out := maxf(0.0, t - _cut_out_at)
	var centre := Vector2(viewport.x * 0.5, viewport.y * CUT_IN_Y)
	var band := Transform2D(deg_to_rad(CUT_IN_ANGLE), Vector2(u, u), 0.0, centre)
	ci.draw_set_transform_matrix(band)
	var reach := viewport.length() / u * 0.62
	var open := _ease_out_back(clampf((t - 0.04) / 0.26, 0.0, 1.0), 2.4) * (1.0 - _ease_in_cubic(out / (CUT_IN_OUT * 0.85)))
	var core_half := CUT_IN_CORE * 0.5 * open
	if core_half > 0.5:
		ci.draw_rect(Rect2(-reach, -core_half, reach * 2.0, core_half * 2.0), _fade(INK, 0.95))
		ci.draw_line(Vector2(-reach, -core_half), Vector2(reach, -core_half), RED, 4.0, true)
		ci.draw_line(Vector2(-reach, core_half), Vector2(reach, core_half), RED, 4.0, true)
	var slam_t := t - CUT_IN_SLAM_AT
	if slam_t <= 0.0:
		return
	var segments := _two_tone(_cut_text, PALE, RED)
	var width := _segments_width(_font_heavy, segments, CUT_IN_SIZE)
	var fit := minf(1.0, (viewport.x / u * 0.9) / maxf(width, 1.0))
	var text_alpha := clampf(slam_t / 0.06, 0.0, 1.0) * (1.0 - _ease_in_cubic(out / (CUT_IN_OUT * 0.7)))
	var slam_scale := _slam(slam_t, 2.7, CUT_IN_FALL) * fit
	var local := Transform2D(0.0, Vector2(slam_scale, slam_scale), 0.0, Vector2(0.0, -16.0))
	ci.draw_set_transform_matrix(band * local)
	_segments(ci, _font_heavy, segments, Vector2.ZERO, CUT_IN_SIZE, 22, INK, text_alpha, Vector2(6.0, 8.0), BLOOD)
	_record("cut_in", band * local, Rect2(-width * 0.5, -CUT_IN_SIZE * 0.5, width, CUT_IN_SIZE))


# ---------------------------------------------------------------- depth meter (5.3)

func _paint_depth(ci: Control, viewport: Vector2, u: float) -> void:
	var amount := _depth_alpha()
	if amount <= 0.001:
		return
	var slide := _ease_out_cubic(amount)
	var a := clampf(amount * 1.5, 0.0, 1.0)
	var panel := DEPTH_PANEL
	var origin := Vector2(viewport.x - (panel.x + 18.0) * u + (1.0 - slide) * (panel.x + 40.0) * u,
		viewport.y * 0.5 - panel.y * 0.5 * u)
	var xf := Transform2D(0.0, Vector2(u, u), 0.0, origin)
	ci.draw_set_transform_matrix(xf)
	_record("depth_meter", xf, Rect2(Vector2.ZERO, panel))
	_round_box(ci, Rect2(Vector2(3.0, 6.0), panel), 18.0, _fade(Color.BLACK, 0.3 * a))
	_round_box(ci, Rect2(Vector2.ZERO, panel), 18.0, _fade(INK, 0.86 * a), _fade(PALE, 0.16 * a), 2.0)
	_hazard_strip(ci, 18.0, panel.x - 18.0, 9.0, 16.0, a, _clock * 26.0)
	_text(ci, _font_wide, _t("depth"), Vector2(panel.x * 0.5, 34.0), 15, _fade(PALE, 0.7 * a))
	var track_x := 86.0
	var top := DEPTH_TRACK_TOP
	var bottom := top + DEPTH_MAX * DEPTH_PX_PER_M
	var depth := clampf(_depth_m, 0.0, DEPTH_MAX)
	var marker_y := top + depth * DEPTH_PX_PER_M
	ci.draw_line(Vector2(track_x, top), Vector2(track_x, bottom), _fade(PALE, 0.16 * a), 4.0)
	for metres in range(0, int(DEPTH_MAX) + 1, 5):
		var y := top + float(metres) * DEPTH_PX_PER_M
		var passed := float(metres) <= depth + 0.01
		var major := metres % 10 == 0
		var tick_color := _fade(SODIUM if passed else PALE, (0.95 if passed else 0.4) * a)
		ci.draw_line(Vector2(track_x - (17.0 if major else 10.0), y), Vector2(track_x - 5.0, y), tick_color, 2.0 if major else 1.5)
		if major:
			var label := "0" if metres == 0 else "−%d" % metres
			_text(ci, _font, label, Vector2(track_x - 23.0, y), 14, tick_color, 0, INK, 1)
	# Travelled part of the shaft glows sodium amber.
	if marker_y > top + 0.5:
		ci.draw_line(Vector2(track_x, top), Vector2(track_x, marker_y), _fade(SODIUM, a), 4.0)
	var glow := 40.0
	ci.draw_texture_rect(_glow_texture, Rect2(track_x - glow, marker_y - glow, glow * 2.0, glow * 2.0), false, _fade(SODIUM, 0.55 * a))
	var chevron := PackedVector2Array([Vector2(track_x + 5.0, marker_y), Vector2(track_x + 21.0, marker_y - 10.0), Vector2(track_x + 21.0, marker_y + 10.0)])
	_poly(ci, chevron, _fade(SODIUM, a))
	ci.draw_line(Vector2(track_x - 8.0, marker_y), Vector2(track_x + 8.0, marker_y), _fade(PALE, a), 3.0)
	# Big readout: digits right-aligned so they do not wobble while counting.
	# Big readout, centred as a group; tabular digits keep it steady while counting.
	var readout_y := bottom + 50.0
	var metres_text := _depth_readout().trim_suffix("m")
	var number_width := _font.get_string_size(metres_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var unit_width := _font.get_string_size("m", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var left := panel.x * 0.5 - (number_width + 3.0 + unit_width) * 0.5
	_text(ci, _font, metres_text, Vector2(left, readout_y), 40, _fade(PALE, a), 0, INK, -1)
	_text(ci, _font, "m", Vector2(left + number_width + 3.0, readout_y + 7.0), 20, _fade(SODIUM, a), 0, INK, -1)
	var status_y := panel.y - 24.0
	if _depth_loading:
		var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(_clock * TAU * 1.1))
		# The label and its three dots stay inside the panel (the generating label is longer).
		var status_text := _t(_depth_status)
		var status_size := 14
		if _font_wide.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, status_size).x > panel.x - 44.0:
			status_size = 12
		var dot_step := 6.0 if status_size < 14 else 7.0
		var label_center := panel.x * 0.5 - (dot_step * 3.0) * 0.5 - 1.0
		var label_width := _text(ci, _font_wide, status_text, Vector2(label_center, status_y), status_size, _fade(SODIUM, pulse * a))
		for dot in range(3):
			var lit := 0.3 + 0.7 * clampf(sin((_clock * 2.4 - float(dot) * 0.22) * TAU) * 0.5 + 0.5, 0.0, 1.0)
			ci.draw_circle(Vector2(label_center + label_width * 0.5 + dot_step + dot * dot_step, status_y + 3.0), 2.0, _fade(SODIUM, lit * a), true, -1.0, true)
	elif depth >= DEPTH_MAX - 0.5:
		_text(ci, _font_wide, _t("arrived"), Vector2(panel.x * 0.5, status_y), 14, _fade(SODIUM, a))


# ---------------------------------------------------------------- callouts (8)

func _paint_callouts(ci: Control, viewport: Vector2, u: float) -> void:
	for entry: Dictionary in _callouts:
		var alpha := _callout_alpha(entry)
		if alpha <= 0.001:
			continue
		var t := _clock - float(entry.start)
		var duration := float(entry.duration)
		var out := clampf((t - (duration - CALLOUT_OUT)) / CALLOUT_OUT, 0.0, 1.0)
		var slot := float(entry.slot)
		var color := entry.color as Color
		var text := str(entry.text)
		var player := 0
		if text.length() > 3 and (text.begins_with("P1 ") or text.begins_with("P2 ")):
			player = int(text.substr(1, 1))
			text = text.substr(3)
		var text_width := _font_heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CALLOUT_SIZE).x
		var chip_width := 66.0 if player > 0 else 0.0
		var width := text_width + chip_width + 64.0
		var fit := minf(1.0, (viewport.x / u * 0.92) / width)
		var pop := lerpf(0.25, 1.0, _ease_out_back(t / CALLOUT_IN, 2.6))
		var depth_scale := lerpf(1.0, 0.76, minf(slot, 1.0))
		var centre := Vector2(viewport.x * 0.5, viewport.y * CALLOUT_Y + (slot * CALLOUT_PITCH - out * 16.0) * u)
		var s := u * fit * depth_scale
		var xf := Transform2D(0.0, Vector2(s * pop, s * lerpf(1.0, 0.85, out)), 0.0, centre)
		ci.draw_set_transform_matrix(xf)
		var half := Vector2(width * 0.5, CALLOUT_HEIGHT * 0.5)
		var skew := 14.0
		_poly(ci, _skewed(Vector2(6.0, 7.0), half * 2.0, skew), _fade(Color.BLACK, 0.32 * alpha))
		_poly(ci, _skewed(Vector2.ZERO, half * 2.0, skew), _fade(INK, 0.93 * alpha))
		_poly(ci, _skewed(Vector2(-half.x + 6.0, 0.0), Vector2(12.0, CALLOUT_HEIGHT), skew), _fade(color, alpha))
		_poly(ci, _skewed(Vector2(half.x - 6.0, 0.0), Vector2(12.0, CALLOUT_HEIGHT), skew), _fade(color, alpha))
		var flash_a := 0.85 * (1.0 - clampf(t / 0.16, 0.0, 1.0))
		if flash_a > 0.0:
			_poly(ci, _skewed(Vector2.ZERO, half * 2.0, skew), _fade(Color.WHITE, flash_a * alpha))
		var x := -(text_width + chip_width) * 0.5
		if player > 0:
			var chip_color := PLAYER_COLORS[player - 1]
			_round_box(ci, Rect2(x, -20.0, 56.0, 40.0), 20.0, _fade(chip_color, alpha), _fade(INK, alpha), 3.0)
			_text(ci, _font_heavy, "P%d" % player, Vector2(x + 28.0, 0.0), 24, _fade(INK, alpha))
			x += chip_width
		_text(ci, _font_heavy, text, Vector2(x, 0.0), CALLOUT_SIZE, _fade(color, alpha), 8, _fade(INK, alpha), -1)
		_record("callout_%d" % int(round(slot)), xf, Rect2(-half - Vector2(skew, 0.0), half * 2.0 + Vector2(skew * 2.0, 0.0)))


# ---------------------------------------------------------------- shout (2.2)

func _paint_shout(ci: Control, viewport: Vector2, u: float) -> void:
	var alpha := _shout_alpha()
	if alpha <= 0.001:
		return
	var t := _clock - _shout_start
	var out := clampf((t - _shout_out_at) / SHOUT_OUT, 0.0, 1.0)
	var width := _font_heavy.get_string_size(_shout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SHOUT_SIZE).x
	var fit := minf(1.0, (viewport.x / u * 0.86) / maxf(width, 1.0))
	var centre := Vector2(viewport.x * 0.5, viewport.y * SHOUT_Y)
	# The megaphone rattles the caption for the first half second.
	var rattle := Vector2(sin(t * 113.0), cos(t * 89.0)) * 3.5 * (1.0 - smoothstep(0.1, 0.6, t))
	var pop := lerpf(0.45, 1.0, _ease_out_back(t / 0.22, 2.2)) * (1.0 + 0.08 * out)
	var base := Transform2D(deg_to_rad(-3.0), Vector2(u, u) * fit, 0.0, centre + rattle * u)
	# Echo trail: two hollow repeats that drift up and fade like the hall's reverb.
	for echo: int in [2, 1]:
		var echo_t := t - 0.14 * float(echo)
		if echo_t <= 0.0:
			continue
		var p := clampf(echo_t / 0.8, 0.0, 1.0)
		var echo_alpha := (0.5 if echo == 1 else 0.28) * pow(1.0 - p, 1.4) * (1.0 - out)
		if echo_alpha <= 0.001:
			continue
		var grow := 1.0 + (0.05 + 0.09 * _ease_out_cubic(p)) * float(echo)
		var offset := Vector2(12.0, -8.0) * float(echo) * _ease_out_cubic(p)
		ci.draw_set_transform_matrix(base * Transform2D(0.0, Vector2.ONE * grow, 0.0, offset))
		_text_outline(ci, _font_heavy, _shout_text, Vector2.ZERO, SHOUT_SIZE, 5, _fade(HAZARD, echo_alpha))
	var main := base * Transform2D(0.0, Vector2.ONE * pop, 0.0, Vector2.ZERO)
	ci.draw_set_transform_matrix(main)
	_text_outline(ci, _font_heavy, _shout_text, Vector2(5.0, 7.0), SHOUT_SIZE, 22, _fade(BLOOD, alpha))
	_text_outline(ci, _font_heavy, _shout_text, Vector2.ZERO, SHOUT_SIZE, 22, _fade(INK, alpha))
	_text_outline(ci, _font_heavy, _shout_text, Vector2.ZERO, SHOUT_SIZE, 12, _fade(RED, alpha))
	_text(ci, _font_heavy, _shout_text, Vector2.ZERO, SHOUT_SIZE, _fade(PALE, alpha))
	_record("shout", main, Rect2(-width * 0.5, -SHOUT_SIZE * 0.55, width, SHOUT_SIZE * 1.1))
	# Speaker tag with a little megaphone.
	var tag := _t("referee")
	var tag_width := _font_wide.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 46.0
	var tag_centre := Vector2(-width * 0.5 + tag_width * 0.5 - 6.0, -SHOUT_SIZE * 0.5 - 30.0)
	_round_box(ci, Rect2(tag_centre - Vector2(tag_width * 0.5, 15.0), Vector2(tag_width, 30.0)), 15.0, _fade(INK, 0.92 * alpha), _fade(HAZARD, alpha), 2.0)
	var horn := tag_centre + Vector2(-tag_width * 0.5 + 18.0, 0.0)
	_poly(ci, PackedVector2Array([horn + Vector2(-6.0, -3.0), horn + Vector2(4.0, -8.0), horn + Vector2(4.0, 8.0), horn + Vector2(-6.0, 3.0)]), _fade(HAZARD, alpha))
	ci.draw_arc(horn + Vector2(6.0, 0.0), 5.0, -0.9, 0.9, 8, _fade(HAZARD, alpha), 1.5, true)
	_text(ci, _font_wide, tag, tag_centre + Vector2(10.0, 0.0), 16, _fade(HAZARD, alpha))


# ---------------------------------------------------------------- rule card (2.2)

func _paint_rule_card(ci: Control, viewport: Vector2, u: float) -> void:
	var alpha := _rule_alpha()
	if alpha <= 0.001:
		return
	var t := _clock - _rule_start
	var short := _rule_short()
	var out := clampf((t - (_rule_duration - _rule_out_time())) / _rule_out_time(), 0.0, 1.0)
	var lines: Array = RULES_EN if _english else RULES_JA
	var text_size := 22 if _english else 25
	var card := RULE_SIZE
	card.y += 56.0 * float(lines.size() - 3)
	var base_height := card.y
	var extra := RULE_PROMPT_HEIGHT if _rule_prompt else 0.0
	card.y += extra
	var widest := 0.0
	for line: Array in lines:
		widest = maxf(widest, _segments_width(_font, _tone_runs(line), text_size))
	card.x = maxf(card.x, widest + 120.0)
	var fit := minf(1.0, (viewport.x / u * 0.94) / card.x)
	var s := lerpf(0.72, 1.0, _ease_out_back(t / _rule_in_time(), 1.8)) * (1.0 - 0.08 * out) * fit
	# The prompt line grows the card downward: the top edge stays where the plain card's is.
	var centre := Vector2(viewport.x * 0.5, viewport.y * RULE_Y + (extra * 0.5 + 26.0 * out) * u)
	var xf := Transform2D(0.0, Vector2(u * s, u * s), 0.0, centre)
	ci.draw_set_transform_matrix(xf)
	var rect := Rect2(-card * 0.5, card)
	_record("rule_card", xf, rect)
	_round_box(ci, Rect2(rect.position + Vector2(0.0, 9.0), rect.size), 18.0, _fade(Color.BLACK, 0.35 * alpha))
	_round_box(ci, rect, 18.0, _fade(INK, 0.95 * alpha), _fade(HAZARD, alpha), 3.0)
	# Header: title, tag and a strip of hazard tape.
	var header_y := rect.position.y + 30.0
	_text(ci, _font_heavy, _t("rules"), Vector2(rect.position.x + 30.0, header_y), 28, _fade(HAZARD, alpha), 0, INK, -1)
	_segments(ci, _font_heavy, _two_tone("SUDDEN DEATH", PALE, RED), Vector2(rect.end.x - 30.0, header_y), 18, 0, INK, alpha, Vector2.ZERO, Color(0, 0, 0, 0), 1)
	_hazard_strip(ci, rect.position.x + 3.0, rect.end.x - 3.0, rect.position.y + 56.0, rect.position.y + 64.0, alpha, _clock * 24.0)
	var row_h := 56.0
	for index in range(lines.size()):
		var start := (0.05 + 0.03 * float(index)) if short else (0.12 + 0.1 * float(index))
		var row_t := t - start
		if row_t <= 0.0:
			continue
		var p := _ease_out_cubic(row_t / (0.16 if short else 0.24))
		var row_alpha := clampf(row_t / 0.1, 0.0, 1.0) * alpha
		var y := rect.position.y + 64.0 + 8.0 + row_h * (float(index) + 0.5)
		if index > 0:
			ci.draw_line(Vector2(rect.position.x + 24.0, y - row_h * 0.5), Vector2(rect.end.x - 24.0, y - row_h * 0.5), _fade(PALE, 0.08 * alpha), 1.0)
		var badge := Vector2(rect.position.x + 48.0, y)
		var badge_pop := lerpf(0.3, 1.0, _ease_out_back(row_t / 0.22, 2.6))
		ci.draw_circle(badge, 18.0 * badge_pop, _fade(HAZARD, row_alpha), true, -1.0, true)
		_text(ci, _font_heavy, str(index + 1), badge, 22, _fade(INK, row_alpha))
		_segments(ci, _font, _tone_runs(lines[index]), Vector2(rect.position.x + 84.0 - 34.0 * (1.0 - p), y), text_size, 0, INK, row_alpha, Vector2.ZERO, Color(0, 0, 0, 0), -1)
	if _rule_prompt:
		_paint_rule_prompt(ci, rect, t, alpha, base_height)


## The held card's last line: a key cap and what it does. It breathes so a card that waits looks alive.
func _paint_rule_prompt(ci: Control, rect: Rect2, t: float, alpha: float, base_height: float) -> void:
	# After the last rule has landed (staggered in over 0.12 + 0.1 * 2 s).
	var appear := alpha * smoothstep(0.45, 0.75, t)
	if appear <= 0.001:
		return
	var tone := appear * (0.78 + 0.22 * sin(t * TAU * 0.9))
	var top := rect.position.y + base_height
	ci.draw_line(Vector2(rect.position.x + 24.0, top - 2.0), Vector2(rect.end.x - 24.0, top - 2.0), _fade(PALE, 0.08 * appear), 1.0)
	var y := top + RULE_PROMPT_HEIGHT * 0.5 - 3.0
	var cap := "ENTER"
	var cap_width := _font_wide.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 30.0
	var label := _t("press")
	var label_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var x := -(cap_width + 14.0 + label_width) * 0.5
	_round_box(ci, Rect2(x, y - 17.0, cap_width, 34.0), 8.0, _fade(HAZARD, 0.16 * tone), _fade(HAZARD, tone), 2.0)
	_text(ci, _font_wide, cap, Vector2(x + cap_width * 0.5, y), 17, _fade(HAZARD, tone))
	_text(ci, _font, label, Vector2(x + cap_width + 14.0, y), 24, _fade(PALE, tone), 0, INK, -1)


# ---------------------------------------------------------------- countdown (2.2)

func _paint_countdown(ci: Control, viewport: Vector2, u: float) -> void:
	var centre := Vector2(viewport.x * 0.5, viewport.y * COUNT_Y)
	var prev_t := _clock - _count_prev_start
	if _count_prev_text != "" and prev_t < 0.2:
		var p := prev_t / 0.2
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE * u * (1.0 + 0.7 * p), 0.0, centre))
		_count_glyphs(ci, _count_prev_text, pow(1.0 - p, 2.0) * 0.8)
	var alpha := _count_alpha()
	if alpha <= 0.001:
		return
	var t := _clock - _count_start
	var go := _is_go(_count_text)
	var out := clampf((t - _count_life(_count_text)) / 0.2, 0.0, 1.0)
	if t > COUNT_FALL:
		var p := (t - COUNT_FALL) / 0.42
		if p < 1.0:
			ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(u, u), 0.0, centre))
			var radius := 96.0 + 170.0 * _ease_out_cubic(p)
			ci.draw_circle(Vector2.ZERO, radius, _fade(HAZARD if go else SODIUM, 0.85 * (1.0 - p)), false, 3.0 + 14.0 * (1.0 - p), true)
		if go:
			var ray_alpha := (1.0 - out) * clampf((t - COUNT_FALL) / 0.1, 0.0, 1.0) * 0.55
			ci.draw_set_transform_matrix(Transform2D(t * 0.5, Vector2(u, u), 0.0, centre))
			_rays(ci, 14, 330.0 * _ease_out_cubic(clampf((t - COUNT_FALL) / 0.3, 0.0, 1.0)), 0.09, _fade(HAZARD, ray_alpha))
	var s := _slam(t, 2.3, COUNT_FALL) * (1.0 + 0.5 * out)
	if not go:
		s *= 1.0 - 0.06 * smoothstep(0.35, 0.6, t)
	var wobble := deg_to_rad(7.0) * (1.0 if absi(hash(_count_text)) % 2 == 0 else -1.0)
	var settle := maxf(t - COUNT_FALL, 0.0)
	var tilt := wobble * exp(-settle * 8.0) * cos(settle * 22.0)
	var xf := Transform2D(tilt, Vector2(u * s, u * s), 0.0, centre)
	ci.draw_set_transform_matrix(xf)
	_count_glyphs(ci, _count_text, alpha)
	var size := 150 if go else 190
	var width := _font_heavy.get_string_size(_count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_record("countdown", xf, Rect2(-width * 0.5, -size * 0.5, width, size))


func _count_glyphs(ci: Control, text: String, alpha: float) -> void:
	if _is_go(text):
		_text_outline(ci, _font_heavy, text, Vector2(6.0, 10.0), 150, 24, _fade(BLOOD, alpha))
		_text(ci, _font_heavy, text, Vector2(6.0, 10.0), 150, _fade(RED, alpha))
		_text(ci, _font_heavy, text, Vector2.ZERO, 150, _fade(HAZARD, alpha), 24, _fade(INK, alpha))
	else:
		_text_outline(ci, _font_heavy, text, Vector2(6.0, 10.0), 190, 24, _fade(BLOOD, alpha))
		_text(ci, _font_heavy, text, Vector2(6.0, 10.0), 190, _fade(SODIUM.darkened(0.25), alpha))
		_text(ci, _font_heavy, text, Vector2.ZERO, 190, _fade(PALE, alpha), 24, _fade(INK, alpha))


# ---------------------------------------------------------------- winner (2.3)

func _paint_winner(ci: Control, viewport: Vector2, u: float) -> void:
	var alpha := _winner_alpha()
	if alpha <= 0.001:
		return
	var t := _clock - _winner_start
	var out := clampf((t - _winner_out_at) / 0.3, 0.0, 1.0)
	var color := PLAYER_COLORS[_winner - 1]
	var centre := Vector2(viewport.x * 0.5, viewport.y * WIN_Y)
	var title := "P%d WIN!" % _winner
	var width := _font_heavy.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, WIN_SIZE).x
	var fit := minf(1.0, (viewport.x / u * 0.88) / maxf(width, 1.0))
	var s := _slam(t, 1.8, WIN_FALL) * fit * (1.0 - 0.1 * out)
	if t > 0.9:
		s *= 1.0 + 0.012 * sin((t - 0.9) * 3.2)
	var tilt := 0.0
	if t < WIN_FALL:
		tilt = deg_to_rad(lerpf(-10.0, 2.0, pow(t / WIN_FALL, 2.0)))
	else:
		tilt = deg_to_rad(2.0) * exp(-(t - WIN_FALL) * 7.0) * cos((t - WIN_FALL) * 18.0)
	var xf := Transform2D(tilt, Vector2(u * s, u * s), 0.0, centre)
	ci.draw_set_transform_matrix(xf)
	_text_outline(ci, _font_heavy, title, Vector2(7.0, 11.0), WIN_SIZE, 24, _fade(INK, alpha))
	_text(ci, _font_heavy, title, Vector2(7.0, 11.0), WIN_SIZE, _fade(color.darkened(0.55), alpha))
	_text_outline(ci, _font_heavy, title, Vector2.ZERO, WIN_SIZE, 24, _fade(INK, alpha))
	_text_outline(ci, _font_heavy, title, Vector2.ZERO, WIN_SIZE, 10, _fade(PALE, alpha))
	_text(ci, _font_heavy, title, Vector2.ZERO, WIN_SIZE, _fade(color, alpha))
	_record("winner", xf, Rect2(-width * 0.5, -WIN_SIZE * 0.5, width, WIN_SIZE))
	# "SUDDEN DEATH" sub-line on a hazard-capped chip.
	var sub_t := t - 0.3
	if sub_t > 0.0:
		var p := _ease_out_back(sub_t / 0.3, 1.6)
		var sub_alpha := clampf(sub_t / 0.12, 0.0, 1.0) * alpha
		var sub := _two_tone("SUDDEN DEATH", PALE, RED)
		var sub_width := _segments_width(_font_heavy, sub, 28) + 96.0
		var sub_xf := Transform2D(0.0, Vector2(u, u) * fit, 0.0, centre + Vector2(0.0, (104.0 + 30.0 * (1.0 - p)) * u * fit))
		ci.draw_set_transform_matrix(sub_xf)
		var chip := Rect2(-sub_width * 0.5, -22.0, sub_width, 44.0)
		_poly(ci, _skewed(Vector2(4.0, 5.0), chip.size, 12.0), _fade(Color.BLACK, 0.3 * sub_alpha))
		_poly(ci, _skewed(Vector2.ZERO, chip.size, 12.0), _fade(INK, 0.94 * sub_alpha))
		_hazard_strip(ci, chip.position.x + 6.0, chip.position.x + 34.0, -16.0, 16.0, sub_alpha, _clock * 20.0)
		_hazard_strip(ci, chip.end.x - 34.0, chip.end.x - 6.0, -16.0, 16.0, sub_alpha, -_clock * 20.0)
		_segments(ci, _font_heavy, sub, Vector2.ZERO, 28, 0, INK, sub_alpha)
		_record("winner_sub", sub_xf, chip)


## Rays and glow behind the winner title, painted under the letterbox bars.
func _paint_winner_rays(ci: Control, viewport: Vector2, u: float) -> void:
	if _winner_alpha() <= 0.001:
		return
	var t := _clock - _winner_start
	var out := clampf((t - _winner_out_at) / 0.3, 0.0, 1.0)
	var ray_alpha := smoothstep(WIN_FALL, WIN_FALL + 0.35, t) * (1.0 - out)
	if ray_alpha <= 0.0:
		return
	var color := PLAYER_COLORS[_winner - 1]
	var centre := Vector2(viewport.x * 0.5, viewport.y * WIN_Y)
	ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(u, u), 0.0, centre))
	ci.draw_texture_rect(_glow_texture, Rect2(-480.0, -200.0, 960.0, 400.0), false, _fade(color, 0.42 * ray_alpha))
	ci.draw_set_transform_matrix(Transform2D(t * 0.22, Vector2(u, u), 0.0, centre))
	_rays(ci, 18, 600.0 * _ease_out_cubic((t - WIN_FALL) / 0.5), 0.065, _fade(color.lerp(GOLD, 0.35), 0.26 * ray_alpha))


# ---------------------------------------------------------------- the buzzer duel (8)

## The question panel at the top, the choices along the bottom with each player's answer keys, and each
## player's lift gauge at their side of the screen. The director passes the state every frame.
func _paint_quiz(ci: Control, viewport: Vector2, u: float) -> void:
	var amount := _quiz_alpha()
	if amount <= 0.001 or _quiz.is_empty():
		return
	var a := amount
	var text := str(_quiz.get("text", ""))
	var revealed := clampi(int(_quiz.get("revealed", 0)), 0, text.length())
	var phase := str(_quiz.get("phase", ""))
	var buzzer := int(_quiz.get("buzzer", 0))
	var result := str(_quiz.get("result", ""))
	var t := _clock - _quiz_start
	# ---- question panel
	var panel := Vector2(QUIZ_PANEL_WIDTH, 0.0)
	var lines := _wrap(text, _font, QUIZ_TEXT_SIZE, panel.x - 64.0)
	panel.y = 92.0 + float(maxi(lines.size(), 1)) * QUIZ_LINE + 22.0
	var fit := minf(1.0, (viewport.x / u * 0.96) / panel.x)
	var drop := (1.0 - _ease_out_cubic(clampf(t / 0.28, 0.0, 1.0))) * 40.0
	var centre := Vector2(viewport.x * 0.5, viewport.y * QUIZ_Y + (panel.y * 0.5 - drop) * u * fit)
	var xf := Transform2D(0.0, Vector2(u, u) * fit, 0.0, centre)
	ci.draw_set_transform_matrix(xf)
	var rect := Rect2(-panel * 0.5, panel)
	_record("quiz_panel", xf, rect)
	var edge := PLAYER_COLORS[buzzer - 1] if buzzer > 0 and phase == "answering" else HAZARD
	_round_box(ci, Rect2(rect.position + Vector2(0.0, 8.0), rect.size), 16.0, _fade(Color.BLACK, 0.35 * a))
	_round_box(ci, rect, 16.0, _fade(INK, 0.93 * a), _fade(edge, a), 3.0)
	_hazard_strip(ci, rect.position.x + 3.0, rect.end.x - 3.0, rect.position.y + 3.0, rect.position.y + 11.0, a, _clock * 22.0)
	# Number chip.
	var number := int(_quiz.get("number", 1))
	var chip_text := ("Q%d" % number) if _english else ("第%d問" % number)
	var chip_width := _font_heavy.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 34.0
	var chip := Rect2(rect.position.x + 22.0, rect.position.y + 22.0, chip_width, 40.0)
	_round_box(ci, chip, 10.0, _fade(HAZARD, a))
	_text(ci, _font_heavy, chip_text, chip.get_center(), 26, _fade(INK, a))
	var status := _quiz_status(phase, buzzer, result)
	if not status.is_empty():
		var status_color := PLAYER_COLORS[buzzer - 1] if buzzer > 0 and phase == "answering" else PALE
		if phase == "result":
			status_color = GOOD if result == "correct" else (SOFT_RED if result in ["wrong", "late"] else SODIUM)
		_text(ci, _font_heavy, status, Vector2(chip.end.x + 18.0, chip.get_center().y), 24, _fade(status_color, a), 0, INK, -1)
	# Question text, revealed character by character, with a caret while it is still coming.
	var y := rect.position.y + 92.0 + QUIZ_LINE * 0.5 - 6.0
	var shown := revealed
	var caret_at := Vector2.ZERO
	for line: String in lines:
		var visible := line.substr(0, clampi(shown, 0, line.length()))
		shown -= line.length()
		var x := rect.position.x + 32.0
		if not visible.is_empty():
			_text(ci, _font, visible, Vector2(x, y), QUIZ_TEXT_SIZE, _fade(PALE, a), 0, INK, -1)
		if shown <= 0 and caret_at == Vector2.ZERO:
			caret_at = Vector2(x + _font.get_string_size(visible, HORIZONTAL_ALIGNMENT_LEFT, -1, QUIZ_TEXT_SIZE).x + 4.0, y)
		y += QUIZ_LINE
	if phase == "reading" and revealed < text.length() and caret_at != Vector2.ZERO:
		var blink := 0.5 + 0.5 * sin(_clock * TAU * 3.0)
		ci.draw_rect(Rect2(caret_at + Vector2(0.0, -15.0), Vector2(4.0, 30.0)), _fade(HAZARD, a * blink))
	elif phase == "answering" and revealed < text.length() and caret_at != Vector2.ZERO:
		# Stopped by the buzz: the rest of the question is hidden.
		_text(ci, _font_heavy, "…", caret_at + Vector2(10.0, 0.0), QUIZ_TEXT_SIZE, _fade(PLAYER_COLORS[buzzer - 1], a), 0, INK, -1)
	# Timer bar along the bottom edge of the panel.
	var timer := clampf(float(_quiz.get("timer", 1.0)), 0.0, 1.0)
	var mode := str(_quiz.get("timer_mode", ""))
	if mode in ["think", "answer"]:
		var bar := Rect2(rect.position.x + 22.0, rect.end.y - 18.0, rect.size.x - 44.0, 8.0)
		_round_box(ci, bar, 4.0, _fade(PALE, 0.12 * a))
		var fill_color := PLAYER_COLORS[buzzer - 1] if mode == "answer" and buzzer > 0 else SODIUM.lerp(RED, 1.0 - smoothstep(0.15, 0.5, timer))
		if timer > 0.001:
			_round_box(ci, Rect2(bar.position, Vector2(bar.size.x * timer, bar.size.y)), 4.0, _fade(fill_color, a))
	# ---- choices along the bottom
	_paint_choices(ci, viewport, u, a, phase, buzzer, result)
	# ---- lift gauges
	var margins: Array = _quiz.get("margins", [0, 0])
	var full := maxi(int(_quiz.get("max_margin", 4)), 1)
	for player_index in [1, 2]:
		_paint_gauge(ci, viewport, u, a, player_index, int(margins[player_index - 1]), full, buzzer == player_index and phase == "answering")


func _paint_choices(ci: Control, viewport: Vector2, u: float, a: float, phase: String, buzzer: int, result: String) -> void:
	var choices: PackedStringArray = _quiz.get("choices", PackedStringArray())
	var keys: Array = _quiz.get("keys", [])
	var count := choices.size()
	if count <= 0:
		return
	var answer := int(_quiz.get("answer", -1))
	var chosen := int(_quiz.get("chosen", -1))
	var t := _clock - _quiz_start
	var gap := 18.0
	var box := Vector2(minf(CHOICE_MAX_WIDTH, (QUIZ_PANEL_WIDTH + 120.0 - gap * float(count - 1)) / float(count)), CHOICE_HEIGHT)
	var total := box.x * float(count) + gap * float(count - 1)
	var fit := minf(1.0, (viewport.x / u * 0.96) / total)
	var origin := Vector2(viewport.x * 0.5, viewport.y * CHOICE_Y)
	var xf := Transform2D(0.0, Vector2(u, u) * fit, 0.0, origin)
	ci.draw_set_transform_matrix(xf)
	_record("choices", xf, Rect2(-total * 0.5, -box.y * 0.5, total, box.y + 44.0))
	for index in range(count):
		var appear := _ease_out_back(clampf((t - 0.08 * float(index)) / 0.3, 0.0, 1.0), 1.6)
		if appear <= 0.0:
			continue
		var x := -total * 0.5 + float(index) * (box.x + gap)
		var rect := Rect2(Vector2(x, -box.y * 0.5 + (1.0 - appear) * 30.0), box)
		var fill := INK
		var border := _fade(PALE, 0.35)
		var text_color := PALE
		if phase == "result":
			if index == answer:
				fill = GOOD.darkened(0.55)
				border = GOOD
			elif index == chosen:
				fill = RED.darkened(0.6)
				border = RED
				text_color = SOFT_RED
			else:
				text_color = _fade(PALE, 0.45)
		elif phase == "answering" and buzzer > 0:
			border = _fade(PLAYER_COLORS[buzzer - 1], 0.9)
		if phase == "result" and index == chosen and chosen != answer:
			rect.position.x += sin(_clock * 70.0) * 4.0 * (1.0 - smoothstep(0.0, 0.4, _clock - _result_start))
		_round_box(ci, Rect2(rect.position + Vector2(0.0, 6.0), rect.size), 12.0, _fade(Color.BLACK, 0.3 * a * appear))
		_round_box(ci, rect, 12.0, _fade(fill, 0.8 * a * appear), _fade(border, a * appear), 2.5)
		var label := char(65 + index)
		_text(ci, _font_heavy, label, rect.position + Vector2(24.0, box.y * 0.5), 26, _fade(HAZARD, a * appear))
		var choice := choices[index]
		var size := CHOICE_TEXT_SIZE
		var room := box.x - 60.0
		while size > 16 and _font.get_string_size(choice, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
			size -= 2
		_text(ci, _font, choice, rect.position + Vector2(46.0 + room * 0.5, box.y * 0.5), size, _fade(text_color, a * appear))
		# Answer keys under the box: both players' until someone buzzes, then only the answerer's.
		var key := int(keys[index]) if index < keys.size() else -1
		var caps_y := rect.end.y + 22.0
		if phase == "answering" and buzzer > 0:
			_key_cap(ci, Vector2(rect.get_center().x, caps_y), buzzer, key, 1.15, a * appear)
		elif phase != "result":
			_key_cap(ci, Vector2(rect.get_center().x - 24.0, caps_y), 1, key, 0.85, a * appear * 0.8)
			_key_cap(ci, Vector2(rect.get_center().x + 24.0, caps_y), 2, key, 0.85, a * appear * 0.8)


## A key cap in the player's colour: P1 A/W/S/D, P2 ←/↑/↓/→ (key = QuizGameState.SUDDEN_DEATH_KEY_*).
func _key_cap(ci: Control, centre: Vector2, player_index: int, key: int, scale: float, a: float) -> void:
	if key < 0 or a <= 0.001:
		return
	var labels: Array = KEY_LABELS[player_index - 1]
	var label := str(labels[clampi(key, 0, 3)])
	var size := Vector2(36.0, 30.0) * scale
	var rect := Rect2(centre - size * 0.5, size)
	var color := PLAYER_COLORS[player_index - 1]
	_round_box(ci, rect, 7.0 * scale, _fade(color, 0.22 * a), _fade(color, a), 2.0)
	_text(ci, _font_heavy, label, centre, int(18.0 * scale), _fade(PALE, a))


## A player's lift over the water: one pip per half step of margin, the water below them.
func _paint_gauge(ci: Control, viewport: Vector2, u: float, a: float, player_index: int, margin: int, full: int, lit: bool) -> void:
	var side := -1.0 if player_index == 1 else 1.0
	var size := Vector2(78.0, 64.0 + 34.0 * float(full))
	var centre := Vector2(viewport.x * 0.5 + side * (viewport.x * 0.5 - (size.x * 0.5 + 18.0) * u), viewport.y * GAUGE_Y)
	var xf := Transform2D(0.0, Vector2(u, u), 0.0, centre)
	ci.draw_set_transform_matrix(xf)
	var rect := Rect2(-size * 0.5, size)
	_record("gauge_p%d" % player_index, xf, rect)
	var color := PLAYER_COLORS[player_index - 1]
	var pulse := (0.65 + 0.35 * sin(_clock * TAU * 2.4)) if lit else 0.0
	_round_box(ci, Rect2(rect.position + Vector2(0.0, 6.0), rect.size), 14.0, _fade(Color.BLACK, 0.3 * a))
	_round_box(ci, rect, 14.0, _fade(INK, 0.9 * a), _fade(color, a * (0.55 + 0.45 * pulse)), 2.0 + 3.0 * pulse)
	_round_box(ci, Rect2(rect.position + Vector2(13.0, 12.0), Vector2(size.x - 26.0, 30.0)), 15.0, _fade(color, a))
	_text(ci, _font_heavy, "P%d" % player_index, rect.position + Vector2(size.x * 0.5, 27.0), 20, _fade(INK, a))
	var pip := Vector2(size.x - 30.0, 26.0)
	for index in range(full):
		# Pips stack up from the water line: the lowest is the last half step above it.
		var top := rect.end.y - 16.0 - pip.y - float(index) * (pip.y + 8.0)
		var on := index < margin
		var pip_rect := Rect2(Vector2(-pip.x * 0.5, top), pip)
		_round_box(ci, pip_rect, 6.0, _fade(color if on else WATER, (1.0 if on else 0.35) * a), _fade(PALE, 0.12 * a), 1.0)
	# The water line under the pips.
	var water_y := rect.end.y - 10.0
	ci.draw_line(Vector2(rect.position.x + 10.0, water_y), Vector2(rect.end.x - 10.0, water_y), _fade(WATER.lightened(0.3), a), 3.0)


func _quiz_status(phase: String, buzzer: int, result: String) -> String:
	match phase:
		"intro":
			return "READY" if _english else "早押しクイズ"
		"reading":
			return "BUZZ IN!" if _english else "わかったら早押し！"
		"answering":
			return ("P%d ANSWERS" if _english else "P%d 回答中") % buzzer
		"result":
			match result:
				"correct":
					return ("P%d CORRECT!" if _english else "P%d 正解！") % buzzer
				"wrong":
					return ("P%d WRONG" if _english else "P%d 不正解") % buzzer
				"late":
					return ("P%d TOO LATE" if _english else "P%d 答えられず") % buzzer
				"timeout":
					return "TIME UP" if _english else "時間切れ"
	return ""


## Wraps [param text] to lines no wider than [param width] (characters for Japanese, words for English).
func _wrap(text: String, font: Font, size: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var english := text.count(" ") >= 3 and text.length() > 0 and text.unicode_at(0) < 0x3000
	var current := ""
	if english:
		for word: String in text.split(" "):
			var trial := word if current.is_empty() else current + " " + word
			if not current.is_empty() and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				lines.append(current + " ")
				current = word
			else:
				current = trial
	else:
		for index in range(text.length()):
			var character := text[index]
			var trial := current + character
			# Keep closing punctuation on the line it closes.
			if not current.is_empty() and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width \
					and not character in ["、", "。", "？", "！", "」", "）", "?", "!", ")"]:
				lines.append(current)
				current = character
			else:
				current = trial
	if not current.is_empty():
		lines.append(current)
	return lines


func _quiz_alpha() -> float:
	if _quiz.is_empty():
		return 0.0
	return clampf((_clock - _quiz_start) / 0.12, 0.0, 1.0) * _hide_fade(_quiz_hide_at)


# ------------------------------------------------------------------ drawing helpers

## Draws [param text] with its visual middle on at.y; [param align] -1 puts its
## left edge on at.x, 0 centres it, 1 puts its right edge there. Returns the width.
func _text(ci: CanvasItem, font: Font, text: String, at: Vector2, size: int, fill: Color,
		outline_size := 0, outline: Color = INK, align := 0) -> float:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(at.x - width * 0.5 * float(align + 1), at.y + float(size) * BASELINE)
	if outline_size > 0 and outline.a > 0.0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, outline)
	if fill.a > 0.0:
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)
	return width


func _text_outline(ci: CanvasItem, font: Font, text: String, at: Vector2, size: int, outline_size: int, color: Color) -> void:
	if color.a <= 0.0:
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(at.x - width * 0.5, at.y + float(size) * BASELINE)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, color)


## "SUDDEN DEATH!" -> white "SUDDEN ", red "DEATH!" (the last word is the hot one).
func _two_tone(text: String, first: Color, last: Color) -> Array:
	var clean := text.strip_edges()
	var split := clean.rfind(" ")
	if split <= 0:
		return [[clean, last]]
	return [[clean.substr(0, split + 1), first], [clean.substr(split + 1), last]]


func _tone_runs(line: Array) -> Array:
	var runs: Array = []
	for run: Array in line:
		var tone := str(run[1])
		runs.append([str(run[0]), HAZARD if tone == "y" else SOFT_RED if tone == "r" else PALE])
	return runs


func _plain(line: Array) -> String:
	var text := ""
	for run: Array in line:
		text += str(run[0])
	return text


func _segments_width(font: Font, segments: Array, size: int) -> float:
	var total := 0.0
	for segment: Array in segments:
		total += font.get_string_size(str(segment[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return total


## Multi-colour line of [[text, Color], ...] centred like _text(). Shadows and
## outlines of every run go under all fills so the colours butt cleanly.
func _segments(ci: CanvasItem, font: Font, segments: Array, at: Vector2, size: int, outline_size: int,
		outline: Color, alpha := 1.0, shadow := Vector2.ZERO, shadow_color := Color(0, 0, 0, 0), align := 0) -> float:
	var widths: Array[float] = []
	var total := 0.0
	for segment: Array in segments:
		var width := font.get_string_size(str(segment[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		widths.append(width)
		total += width
	var x0 := at.x - total * 0.5 * float(align + 1)
	var baseline := at.y + float(size) * BASELINE
	for pass_index in range(3):
		var x := x0
		for index in range(segments.size()):
			var text := str(segments[index][0])
			var pos := Vector2(x, baseline)
			if pass_index == 0 and shadow_color.a > 0.0:
				if outline_size > 0:
					ci.draw_string_outline(font, pos + shadow, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, _fade(outline, alpha))
				ci.draw_string(font, pos + shadow, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _fade(shadow_color, alpha))
			elif pass_index == 1 and outline_size > 0:
				ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, _fade(outline, alpha))
			elif pass_index == 2:
				ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _fade(segments[index][1] as Color, alpha))
			x += widths[index]
	return total


## Hazard tape between x0..x1 and y0..y1 (local units); [param scroll] crawls it.
func _hazard_strip(ci: CanvasItem, x0: float, x1: float, y0: float, y1: float, alpha: float, scroll: float) -> void:
	if x1 - x0 <= 0.5 or alpha <= 0.0:
		return
	var points := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(Vector2((point.x + scroll) / HAZARD_TILE, (point.y - y0) / HAZARD_TILE))
	ci.draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha), uvs, _hazard_texture)
	# Soft long edges: textured polygons are not antialiased (rotated bands).
	var edge := _fade(HAZARD_DARK, 0.6 * alpha)
	ci.draw_line(points[0], points[1], edge, 1.2, true)
	ci.draw_line(points[3], points[2], edge, 1.2, true)


## Filled polygon with an antialiased rim (Godot polygons are not antialiased).
func _poly(ci: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	if color.a <= 0.0:
		return
	ci.draw_colored_polygon(points, color)
	var rim := points.duplicate()
	rim.append(points[0])
	ci.draw_polyline(rim, color, 1.0, true)


func _skewed(centre: Vector2, size: Vector2, skew: float) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([centre + Vector2(-half.x + skew, -half.y), centre + Vector2(half.x + skew, -half.y),
		centre + Vector2(half.x - skew, half.y), centre + Vector2(-half.x - skew, half.y)])


func _round_box(ci: CanvasItem, rect: Rect2, radius: float, fill: Color, border := Color(0, 0, 0, 0), border_width := 0.0) -> void:
	_box.bg_color = fill
	_box.draw_center = fill.a > 0.0
	_box.set_corner_radius_all(int(minf(radius, minf(rect.size.x, rect.size.y) * 0.5)))
	_box.border_color = border
	_box.set_border_width_all(int(round(border_width)) if border.a > 0.0 else 0)
	_box.anti_aliasing = true
	ci.draw_style_box(_box, rect)


## Fan of tapering rays around the origin.
func _rays(ci: CanvasItem, count: int, radius: float, half_width: float, color: Color) -> void:
	if radius <= 1.0 or color.a <= 0.0:
		return
	var clear := Color(color.r, color.g, color.b, 0.0)
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var points := PackedVector2Array([Vector2.ZERO, Vector2.from_angle(angle - half_width) * radius, Vector2.from_angle(angle + half_width) * radius])
		ci.draw_polygon(points, PackedColorArray([color, clear, clear]))


func _record(key: String, xf: Transform2D, rect: Rect2) -> void:
	var corners := [xf * rect.position, xf * Vector2(rect.end.x, rect.position.y), xf * rect.end, xf * Vector2(rect.position.x, rect.end.y)]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		bounds = bounds.expand(corner)
	_rects[key] = bounds


static func _fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))


static func _ease_out_cubic(x: float) -> float:
	var v := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - v * v * v


static func _ease_in_cubic(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return v * v * v


static func _ease_out_back(x: float, overshoot := 1.70158) -> float:
	var v := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + (overshoot + 1.0) * v * v * v + overshoot * v * v


## Slam scale: falls from [param from] into an undershoot at [param fall]
## seconds, then rings out to 1 (the AE verdict curve: 170% -> 92% -> 104% -> 100%).
static func _slam(t: float, from: float, fall: float) -> float:
	if t <= 0.0:
		return from
	if t < fall:
		return lerpf(from, 0.9, pow(t / fall, 2.0))
	var settle := t - fall
	return 1.0 - 0.1 * exp(-settle * 9.0) * cos(settle * 24.0)
