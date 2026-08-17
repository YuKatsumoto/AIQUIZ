extends Control
class_name TutorialCoachBar

## チュートリアル用コーチバーの共通土台。
## 上中央カード・左下チェックリスト・スキップ行に分かれていた3枚を、
## 画面下部の1本のバーへ統合する。クイズ中は一行へ縮め、
## 上中央に出る問題文と競合させない。
##
## コースごとの差分（担当コース判定・バー幅・キーチップの段）はサブクラスが受け持つ。
## 1P: res://scripts/ui/solo_tutorial_overlay.gd（キーチップ1段）
## 2P: res://scripts/ui/duo_tutorial_overlay.gd（P1/P2を横一列）

const ACCENT := Color(1.0, 0.80, 0.25, 1.0)
const DONE_COLOR := Color(0.36, 1.0, 0.60, 1.0)
const TEXT_COLOR := Color(0.92, 0.95, 1.0, 1.0)
const MUTED_COLOR := Color(0.60, 0.68, 0.84, 1.0)

const BAR_WIDTH := 940.0
const BAR_MARGIN_BOTTOM := 26.0
const BAR_HEIGHT_FULL := 108.0
const BAR_HEIGHT_COMPACT := 66.0
const ENTER_SECONDS := 0.35
const ENTER_RISE := 46.0
const CHIP_POP_SECONDS := 0.45

var game_state: QuizGameState = null

var _bar: PanelContainer = null
var _dots_box: HBoxContainer = null
var _step_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _chip_root: BoxContainer = null
var _skip_label: Label = null

var _signature: String = ""
var _step_id: String = ""
var _enter_elapsed: float = -1.0
var _bar_height: float = BAR_HEIGHT_FULL
var _dot_count: int = 0
var _chips: Array[Control] = []
var _chip_pops: Array[float] = []
var _done_state: Dictionary = {}


func setup(state: QuizGameState) -> void:
	game_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func update_overlay(delta: float = 0.0) -> void:
	if game_state == null or not _course_is_active():
		visible = false
		return
	var model := game_state.get_tutorial_overlay_model()
	# 開始演出（待機・フライオーバー・カウントダウン）と結果画面では本編の見え方を優先。
	visible = bool(model.get("visible", false)) and game_state.game_state not in [
		Constants.STATE_CLEAR,
		Constants.STATE_GAME_OVER,
		Constants.STATE_PRELOADING,
		Constants.STATE_WAITING_START,
		Constants.STATE_FLYOVER,
		Constants.STATE_COUNTDOWN,
	]
	if not visible:
		_step_id = ""
		_enter_elapsed = -1.0
		return

	var step_id := str(model.get("step_id", ""))
	if step_id != _step_id:
		_step_id = step_id
		_enter_elapsed = 0.0
		_done_state.clear()

	var locked := bool(model.get("presentation_locked", false))
	# クイズ中は上中央の問題文が主役なので、バーを一行へ縮めて視線の競合を避ける。
	var compact: bool = (
		not locked
		and game_state.tutorial_flow != null
		and game_state.tutorial_flow.is_quiz_step()
	)

	var signature := "%d:%s:%s:%s" % [
		int(model.get("revision", 0)), str(locked), str(compact), _extra_signature()
	]
	if signature != _signature:
		_signature = signature
		_refresh_content(model, locked, compact)

	_bar_height = _bar_height_compact() if compact else _bar_height_full()
	_advance_animations(delta)


# ---------- サブクラスが差し替える部分 ----------

## このオーバーレイが担当するコースが動いているか。
func _course_is_active() -> bool:
	return false


func _bar_width() -> float:
	return BAR_WIDTH


## 画面下端からの余白。他のHUDと重なるコースでは持ち上げる。
func _bar_margin_bottom() -> float:
	return BAR_MARGIN_BOTTOM


## キャラクターや下部HUDを優先し、バーを画面上端へ逃がす状態では true。
func _bar_at_top() -> bool:
	return false


func _bar_margin_top() -> float:
	return BAR_MARGIN_BOTTOM


## バーの高さ。キーチップの段数が多いコースでは広げないとチップが切れる。
func _bar_height_full() -> float:
	return BAR_HEIGHT_FULL


func _bar_height_compact() -> float:
	return BAR_HEIGHT_COMPACT


## 右側に並べるキーチップの段。
## 1段 = {"label": String, "color": Color, "tasks": Array[Dictionary]}
func _chip_rows(_model: Dictionary) -> Array[Dictionary]:
	return []


## P1/P2など複数のチップ行を横一列にまとめるコースでは true。
func _chip_rows_inline() -> bool:
	return false


## モデルの revision 以外で再描画が必要な要素があるサブクラス向けの追加シグネチャ。
func _extra_signature() -> String:
	return ""


# ---------- 構築 ----------

func _build_ui() -> void:
	_bar = PanelContainer.new()
	_bar.name = "CoachBar"
	_bar.add_theme_stylebox_override("panel", _bar_style())
	add_child(_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_bar.add_child(row)

	# 左: ステップ進行
	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 5)
	progress_box.custom_minimum_size.x = 132.0
	progress_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(progress_box)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 12)
	_step_label.add_theme_color_override("font_color", MUTED_COLOR)
	progress_box.add_child(_step_label)

	_dots_box = HBoxContainer.new()
	_dots_box.add_theme_constant_override("separation", 6)
	progress_box.add_child(_dots_box)

	# 中央: 見出しと一行の指示
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 3)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 21)
	_title_label.add_theme_color_override("font_color", ACCENT)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_title_label.add_theme_constant_override("outline_size", 4)
	text_box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", TEXT_COLOR)
	text_box.add_child(_body_label)

	_skip_label = Label.new()
	_skip_label.add_theme_font_size_override("font_size", 13)
	_skip_label.add_theme_color_override("font_color", MUTED_COLOR)
	text_box.add_child(_skip_label)

	# 右: キーチップ
	if _chip_rows_inline():
		_chip_root = HBoxContainer.new()
	else:
		_chip_root = VBoxContainer.new()
	_chip_root.name = "ChipRows"
	_chip_root.add_theme_constant_override("separation", 14 if _chip_rows_inline() else 6)
	_chip_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_chip_root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chip_root)

	_layout_bar(1.0)


func _bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.105, 0.90)
	style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


# ---------- 更新 ----------

func _refresh_content(model: Dictionary, locked: bool, compact: bool) -> void:
	var step_number := int(model.get("step_number", 1))
	var step_count := int(model.get("step_count", 1))
	var sub_label := str(model.get("sub_label", ""))
	_step_label.text = (
		"STEP %d / %d   %s" % [step_number, step_count, sub_label]
		if not sub_label.is_empty()
		else "STEP %d / %d" % [step_number, step_count]
	)
	_rebuild_dots(step_count, step_number)

	var hint := str(model.get("hint", ""))
	_title_label.text = str(model.get("title", "チュートリアル"))
	_title_label.visible = not compact
	_body_label.text = hint if not hint.is_empty() else str(model.get("body", ""))
	_body_label.add_theme_color_override(
		"font_color", ACCENT if not hint.is_empty() else TEXT_COLOR
	)
	_body_label.add_theme_font_size_override("font_size", 16 if compact else 15)
	_skip_label.text = str(model.get("skip_text", ""))
	_skip_label.visible = locked and not _skip_label.text.is_empty()

	_rebuild_chip_rows(_chip_rows(model), locked)


func _rebuild_dots(step_count: int, step_number: int) -> void:
	if _dot_count != step_count:
		_dot_count = step_count
		for child: Node in _dots_box.get_children():
			child.queue_free()
		for i: int in range(step_count):
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(12.0, 6.0)
			_dots_box.add_child(dot)
	var index := 0
	for child: Node in _dots_box.get_children():
		var dot := child as Panel
		if dot == null:
			continue
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(3)
		if index < step_number - 1:
			style.bg_color = Color(DONE_COLOR.r, DONE_COLOR.g, DONE_COLOR.b, 0.85)
		elif index == step_number - 1:
			style.bg_color = ACCENT
		else:
			style.bg_color = Color(0.30, 0.36, 0.48, 0.60)
		dot.add_theme_stylebox_override("panel", style)
		index += 1


func _rebuild_chip_rows(rows: Array[Dictionary], locked: bool) -> void:
	for child: Node in _chip_root.get_children():
		child.queue_free()
	_chips.clear()
	_chip_pops.clear()
	if locked:
		_chip_root.visible = false
		return
	var has_any_chip := false
	for row_data: Dictionary in rows:
		var tasks: Array = row_data.get("tasks", [])
		if tasks.is_empty():
			continue
		has_any_chip = true
		var row_label := str(row_data.get("label", ""))
		var accent: Color = row_data.get("color", ACCENT)
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 8)
		row_box.alignment = BoxContainer.ALIGNMENT_END
		_chip_root.add_child(row_box)
		if not row_label.is_empty():
			var label := Label.new()
			label.text = row_label
			label.custom_minimum_size.x = 30.0
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 15)
			label.add_theme_color_override("font_color", accent)
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
			label.add_theme_constant_override("outline_size", 4)
			row_box.add_child(label)
		for task_variant: Variant in tasks:
			var task: Dictionary = task_variant
			var done := bool(task.get("done", false))
			var pop_key := "%s:%s" % [row_label, str(task.get("id", ""))]
			var chip := _create_chip(
				str(task.get("key", "")), str(task.get("caption", "")), done, accent
			)
			row_box.add_child(chip)
			_chips.append(chip)
			# 達成した瞬間だけポップさせる。毎フレーム跳ねさせない。
			_chip_pops.append(1.0 if done and not bool(_done_state.get(pop_key, false)) else 0.0)
			_done_state[pop_key] = done
	_chip_root.visible = has_any_chip


func _create_chip(key_text: String, caption: String, done: bool, accent: Color) -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var key_panel := PanelContainer.new()
	var display_key := ("✓ " + key_text) if done else key_text
	key_panel.custom_minimum_size = Vector2(
		clampf(float(display_key.length()) * 10.0 + 22.0, 52.0, 138.0), 32.0
	)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(7)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	if done:
		style.bg_color = Color(0.08, 0.32, 0.20, 0.92)
		style.border_color = DONE_COLOR
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.08, 0.11, 0.20, 0.92)
		style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
		style.set_border_width_all(2)
	key_panel.add_theme_stylebox_override("panel", style)
	stack.add_child(key_panel)

	var key_label := Label.new()
	key_label.text = display_key
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 15 if display_key.length() <= 8 else 13)
	key_label.add_theme_color_override(
		"font_color", Color(0.78, 1.0, 0.86) if done else Color.WHITE
	)
	key_panel.add_child(key_label)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 11)
	caption_label.add_theme_color_override(
		"font_color", DONE_COLOR if done else MUTED_COLOR
	)
	stack.add_child(caption_label)
	return stack


# ---------- アニメーション ----------

func _advance_animations(delta: float) -> void:
	var weight := 1.0
	if _enter_elapsed >= 0.0:
		_enter_elapsed = minf(ENTER_SECONDS, _enter_elapsed + delta)
		weight = 1.0 - pow(1.0 - clampf(_enter_elapsed / ENTER_SECONDS, 0.0, 1.0), 3.0)
		if _enter_elapsed >= ENTER_SECONDS:
			_enter_elapsed = -1.0
	_layout_bar(weight)

	for i: int in range(_chips.size()):
		if _chip_pops[i] <= 0.0:
			continue
		_chip_pops[i] = maxf(0.0, _chip_pops[i] - delta / CHIP_POP_SECONDS)
		var chip := _chips[i]
		var pop := sin(_chip_pops[i] * PI) * 0.18
		chip.pivot_offset = chip.size * 0.5
		chip.scale = Vector2.ONE * (1.0 + pop)


func _layout_bar(weight: float) -> void:
	if _bar == null:
		return
	var width := _bar_width()
	_bar.offset_left = -width * 0.5
	_bar.offset_right = width * 0.5
	var rise := (1.0 - weight) * ENTER_RISE
	if _bar_at_top():
		_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_bar.offset_top = _bar_margin_top() - rise
		_bar.offset_bottom = _bar.offset_top + _bar_height
	else:
		_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_bar.offset_bottom = -_bar_margin_bottom() + rise
		_bar.offset_top = _bar.offset_bottom - _bar_height
	_bar.modulate.a = lerpf(0.0, 1.0, weight)
