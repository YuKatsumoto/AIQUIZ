extends Control
class_name TutorialCoachBar

## チュートリアル V7 のミッションバー。
## 細いバーを1本出し、章アイコン・章名とミッション（1行）・使うキーだけを並べる。
## クイズ中はアイコンとミッションだけの小さなピルに縮め、壁の問題を読む邪魔をしない。
## バーの外側には章ごとに区切った進行の線を引く（「STEP 3 / 10」の文字は出さない）。
## 体験した直後のルール表示（トースト）と、章を終えたときの「◯◯ CLEAR」バナーもここで出す。
##
## コースごとの差分（担当コース判定・バーの位置・キーの段）はサブクラスが受け持つ。
## 1P: res://scripts/ui/solo_tutorial_overlay.gd
## 2P: res://scripts/ui/duo_tutorial_overlay.gd（P1/P2 のキーを横一列）

const BAR_MARGIN := 30.0
const BAR_MARGIN_TOP := 34.0
const BAR_MAX_WIDTH := 1180.0
const ENTER_SECONDS := 0.3
const ENTER_RISE := 36.0
const KEY_UNIT := 32.0
const PROGRESS_INSET := 34.0
const PROGRESS_HEIGHT := 5.0
const PROGRESS_GAP := 5.0
const TOAST_IN := 0.18
const TOAST_HOLD := 1.6
const TOAST_OUT := 0.25
const TOAST_TOP_RATIO := 0.13
const TOAST_QUIZ_POSITION := Vector2(20.0, 76.0)
## 前後左右の移動キーは、配列の読み順（W A S D／↑ ← ↓ →）で並べる。
const MOVE_ORDER := {"forward": 0, "left": 1, "back": 2, "right": 3}
## 左右どちらでもよいタスク（コースの端・ドアへ向かう）は、表記のキーをすべて並べる。
const EITHER_SIDE_SLOTS := ["toward_edge", "toward_door"]
const BANNER_IN := 0.18
const BANNER_HOLD := 0.6
const BANNER_OUT := 0.22
const BANNER_HEIGHT := 104.0
const BANNER_TOP_RATIO := 0.4
const HINT_SHAKE_SECONDS := 0.32

var game_state: QuizGameState = null

var _bar: PanelContainer = null
var _row: HBoxContainer = null
var _icon_disc: Panel = null
var _icon: TutorialGlyph = null
var _chapter_label: Label = null
var _mission_label: Label = null
var _keys_root: HBoxContainer = null
var _skip_box: HBoxContainer = null
var _progress: Control = null
var _toast: PanelContainer = null
var _toast_icon: TutorialGlyph = null
var _toast_title: Label = null
var _toast_sub: Label = null
var _banner: Control = null
var _banner_name: Label = null
var _banner_next: Label = null

var _signature: String = ""
var _step_id: String = ""
var _enter_elapsed: float = -1.0
var _compact: bool = false
var _chapters: Array = []
var _chips: Dictionary = {}
var _done_state: Dictionary = {}
var _hint_text: String = ""
var _hint_shake: float = 0.0

var _toast_queue: Array[Dictionary] = []
var _toast_seen_serial: int = 0
var _toast_elapsed: float = -1.0
var _banner_seen_serial: int = 0
var _banner_elapsed: float = -1.0


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
		# 2Pのスコアタワーは本編の演出をそのまま見せ、得点の説明は結果画面側に出す。
		Constants.STATE_RESULT_CEREMONY,
	]
	if not visible:
		_step_id = ""
		_enter_elapsed = -1.0
		# 見えない間に積まれた表示は、後から古い説明として出さない。
		_skip_pending_presentations(model)
		return

	var step_id := str(model.get("step_id", ""))
	if step_id != _step_id:
		_step_id = step_id
		_enter_elapsed = 0.0

	var locked := bool(model.get("presentation_locked", false))
	# クイズ中は壁の問題文が主役なので、バーをアイコンとミッションだけに縮める。
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
		_compact = compact
		_refresh_content(model, locked, compact)

	_collect_presentations(model)
	_advance_animations(delta)


# ---------- サブクラスが差し替える部分 ----------

## このオーバーレイが担当するコースが動いているか。
func _course_is_active() -> bool:
	return false


## キャラクターを隠さないよう、バーを画面上端へ置く状態では true。
func _bar_at_top() -> bool:
	return false


## 右側に並べるキーの段。
## 1段 = {"label": String, "color": Color, "tasks": Array[Dictionary], "complete": bool, "player": int}
func _key_groups(_model: Dictionary) -> Array[Dictionary]:
	return []


## モデルの revision 以外で再描画が必要な要素があるサブクラス向けの追加シグネチャ。
func _extra_signature() -> String:
	return ""


# ---------- 構築 ----------

func _build_ui() -> void:
	_progress = Control.new()
	_progress.name = "ChapterProgress"
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.draw.connect(_draw_progress)
	add_child(_progress)

	_bar = PanelContainer.new()
	_bar.name = "CoachBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 14)
	_bar.add_child(_row)

	_icon_disc = TutorialUiStyle.glyph_disc("move", 48.0, TutorialUiStyle.ACCENT, TutorialUiStyle.NAVY) as Panel
	_icon = _icon_disc.get_node("Glyph") as TutorialGlyph
	_row.add_child(_icon_disc)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(text_box)
	_chapter_label = TutorialUiStyle.make_label("", 13, TutorialUiStyle.ACCENT)
	text_box.add_child(_chapter_label)
	_mission_label = TutorialUiStyle.make_label("", 25, TutorialUiStyle.TEXT)
	_mission_label.name = "Mission"
	text_box.add_child(_mission_label)

	_keys_root = HBoxContainer.new()
	_keys_root.name = "ChipRows"
	_keys_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_root.add_theme_constant_override("separation", 16)
	_keys_root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_keys_root)

	_skip_box = HBoxContainer.new()
	_skip_box.name = "SkipRow"
	_skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_box.add_theme_constant_override("separation", 8)
	_skip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip_box.add_child(_divider())
	var enter_chip := TutorialKeyChip.new()
	enter_chip.setup("Enter", TutorialKeyChip.Look.IDLE, TutorialUiStyle.ACCENT, 24.0)
	_skip_box.add_child(enter_chip)
	_skip_box.add_child(TutorialUiStyle.make_label("スキップ", 14, TutorialUiStyle.MUTED, TutorialUiStyle.FONT_MEDIUM))
	_skip_box.visible = false
	_row.add_child(_skip_box)

	_build_toast()
	_build_banner()
	_apply_bar_style(false)


func _divider() -> Control:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = TutorialUiStyle.LINE
	line.custom_minimum_size = Vector2(1.0, 40.0)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line


func _apply_bar_style(compact: bool) -> void:
	var style := TutorialUiStyle.box(
		TutorialUiStyle.PANEL,
		Color(TutorialUiStyle.ACCENT, 0.42 if compact else 0.55),
		2,
		40
	)
	style.content_margin_left = 7.0 if compact else 9.0
	style.content_margin_right = 22.0 if compact else 18.0
	style.content_margin_top = 6.0 if compact else 9.0
	style.content_margin_bottom = 6.0 if compact else 9.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 12
	_bar.add_theme_stylebox_override("panel", style)
	var diameter := 36.0 if compact else 48.0
	_icon_disc.custom_minimum_size = Vector2(diameter, diameter)
	(_icon_disc.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(int(diameter * 0.5))
	var inset := diameter * 0.21
	_icon.offset_left = inset
	_icon.offset_top = inset
	_icon.offset_right = -inset
	_icon.offset_bottom = -inset
	_mission_label.add_theme_font_size_override("font_size", 20 if compact else 25)
	_chapter_label.visible = not compact


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "RuleToast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	_toast.add_child(row)
	_toast_icon = TutorialGlyph.new()
	_toast_icon.custom_minimum_size = Vector2(62.0, 62.0)
	_toast_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	_toast_title = TutorialUiStyle.make_label("", 36, Color.WHITE)
	column.add_child(_toast_title)
	_toast_sub = TutorialUiStyle.make_label("", 17, TutorialUiStyle.TEXT)
	column.add_child(_toast_sub)


func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "ChapterBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	var band := TextureRect.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.texture = _fade_texture(Color(TutorialUiStyle.PANEL_SOLID, 0.92))
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(band)
	# 帯の上下の縁取り（2px）。上の線は帯の上端から下へ、下の線は下端から上へ引く。
	for edge: float in [0.0, 1.0]:
		var line := TextureRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.texture = _fade_texture(Color(TutorialUiStyle.ACCENT, 0.7))
		line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		line.stretch_mode = TextureRect.STRETCH_SCALE
		line.anchor_right = 1.0
		line.anchor_top = edge
		line.anchor_bottom = edge
		line.offset_top = -2.0 * edge
		line.offset_bottom = 2.0 * (1.0 - edge)
		_banner.add_child(line)
	var center := HBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 22)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(center)
	center.add_child(TutorialUiStyle.glyph_disc("check", 58.0, TutorialUiStyle.DONE, Color("05301a")))
	_banner_name = TutorialUiStyle.make_label("", 44, Color.WHITE)
	_banner_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_banner_name)
	var clear_label := TutorialUiStyle.make_label("C L E A R", 44, TutorialUiStyle.ACCENT)
	clear_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(clear_label)
	_banner_next = TutorialUiStyle.make_label("", 15, TutorialUiStyle.MUTED)
	_banner_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_next.anchor_right = 1.0
	_banner_next.anchor_top = 1.0
	_banner_next.anchor_bottom = 1.0
	_banner_next.offset_top = 8.0
	_banner_next.offset_bottom = 30.0
	_banner.add_child(_banner_next)


## 左右の端を透明にぼかした横帯のテクスチャ。
func _fade_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(color, 0.0), color, color, Color(color, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 1
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


# ---------- 更新 ----------

func _refresh_content(model: Dictionary, locked: bool, compact: bool) -> void:
	_apply_bar_style(compact)
	_icon.glyph = str(model.get("icon", ""))
	_chapter_label.text = str(model.get("chapter_label", ""))
	_chapter_label.visible = not compact and not _chapter_label.text.is_empty()
	var hint := str(model.get("hint", ""))
	if hint != _hint_text:
		_hint_text = hint
		_hint_shake = HINT_SHAKE_SECONDS if not hint.is_empty() else 0.0
	if hint.is_empty():
		_mission_label.text = str(model.get("mission", model.get("title", "")))
		_mission_label.add_theme_color_override("font_color", TutorialUiStyle.TEXT)
	else:
		_mission_label.text = hint
		var good := str(model.get("hint_tone", "")) == TutorialFlowBase.HINT_TONE_GOOD
		_mission_label.add_theme_color_override(
			"font_color", TutorialUiStyle.HINT_GOOD if good else TutorialUiStyle.HINT_WARN
		)
	_skip_box.visible = locked and not str(model.get("skip_text", "")).is_empty()
	_chapters = model.get("chapters", [])
	_rebuild_keys(model, locked or compact)
	_progress.set_meta("fraction", _step_fraction(model))
	_progress.queue_redraw()


func _rebuild_keys(model: Dictionary, hidden: bool) -> void:
	for child: Node in _keys_root.get_children():
		_keys_root.remove_child(child)
		child.queue_free()
	_chips.clear()
	if hidden:
		_keys_root.visible = false
		return
	var groups := _key_groups(model)
	var ordered := bool(model.get("ordered_tasks", false))
	var any := false
	_keys_root.add_child(_divider())
	for group: Dictionary in groups:
		var tasks: Array = group.get("tasks", [])
		if tasks.is_empty():
			continue
		any = true
		var accent: Color = group.get("color", TutorialUiStyle.P1)
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 8)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		_keys_root.add_child(box)
		var label := str(group.get("label", ""))
		if not label.is_empty():
			var tag := TutorialUiStyle.make_label(label, 15, accent)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(tag)
		var pending_seen := false
		for task_variant: Variant in _display_order(tasks, ordered):
			var task: Dictionary = task_variant
			var done := bool(task.get("done", false))
			var look := TutorialKeyChip.Look.DONE if done else TutorialKeyChip.Look.TARGET
			# 順番があるステップは、今やる分だけを光らせる（3Dキーと同じ）。
			if ordered and not done:
				look = TutorialKeyChip.Look.IDLE if pending_seen else TutorialKeyChip.Look.TARGET
				pending_seen = true
			var pop_key := "%s:%s" % [label, str(task.get("id", ""))]
			var texts := _display_keys(task, int(group.get("player", 1)))
			for index: int in texts.size():
				var chip := TutorialKeyChip.new()
				chip.setup(texts[index], look, accent, KEY_UNIT)
				box.add_child(chip)
				if done and not bool(_done_state.get(pop_key, false)):
					chip.pop()
				if index == 0:
					_chips[pop_key] = chip
			if done and not bool(_done_state.get(pop_key, false)):
				AudioManager.play_sfx(&"ui_click")
			_done_state[pop_key] = done
		if bool(group.get("complete", false)) and not label.is_empty():
			var ok := TutorialUiStyle.make_label("OK", 13, TutorialUiStyle.DONE)
			ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(ok)
	_keys_root.visible = any


## 移動のタスクは W A S D（↑ ← ↓ →）の順に並べ替える。順番のあるタスクはそのまま。
func _display_order(tasks: Array, ordered: bool) -> Array:
	if ordered:
		return tasks
	var sorted := tasks.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(MOVE_ORDER.get(str(a.get("id", "")), 99)) < int(MOVE_ORDER.get(str(b.get("id", "")), 99))
	)
	return sorted


## タスクの "key" 表記から、キーキャップに書く文字を選ぶ。
## 1Pの "A / ←" は同じ操作の言い換えなので代表の A だけを出す（矢印で操作すると 3D のキーが
## 矢印に切り替わる）。コースの端やドアへ向かう "A / D" は左右どちらでもよいので両方出す。
func _display_keys(task: Dictionary, player_index: int) -> Array[String]:
	var spec := str(task.get("key", ""))
	if KeyTokens.is_badge(spec):
		return ["命中"]
	var tokens := KeyTokens.split_spec(spec)
	if tokens.is_empty():
		return [spec]
	var either_side := false
	for slot: Variant in task.get("slots", []):
		either_side = either_side or str(slot) in EITHER_SIDE_SLOTS
	var picked: Array[String] = []
	for token: String in (tokens if either_side else PackedStringArray([tokens[0]])):
		if token == "Ctrl" and player_index == 2:
			picked.append("右Ctrl")
		elif token in ["矢印", "矢印キー"]:
			picked.append("矢印")
		else:
			picked.append(KeyTokens.display_glyph(token))
	return picked


## 今の章の線を、終えたステップと今のステップのタスクの進み具合だけ伸ばす。
func _step_fraction(model: Dictionary) -> float:
	var tasks: Array = model.get("tasks", [])
	if tasks.is_empty():
		return 0.0
	var done := 0
	for task_variant: Variant in tasks:
		if bool((task_variant as Dictionary).get("done", false)):
			done += 1
	return float(done) / float(tasks.size())


func _draw_progress() -> void:
	var segments: Array[Dictionary] = []
	var total := 0
	for chapter_variant: Variant in _chapters:
		var chapter: Dictionary = chapter_variant
		var steps := int(chapter.get("steps", 0))
		if steps <= 0:
			continue
		segments.append(chapter)
		total += steps
	if total <= 0:
		return
	var width := _progress.size.x - PROGRESS_GAP * float(segments.size() - 1)
	var x := 0.0
	var step_fraction := float(_progress.get_meta("fraction", 0.0))
	for chapter: Dictionary in segments:
		var steps := int(chapter.get("steps", 0))
		var seg_width := width * float(steps) / float(total)
		var rect := Rect2(x, 0.0, seg_width, PROGRESS_HEIGHT)
		var done_steps := int(chapter.get("done_steps", 0))
		var base := StyleBoxFlat.new()
		base.set_corner_radius_all(3)
		base.anti_aliasing = true
		base.bg_color = TutorialUiStyle.DONE if done_steps >= steps else Color(0.9, 0.93, 1.0, 0.42)
		_progress.draw_style_box(base, rect)
		if bool(chapter.get("current", false)) and done_steps < steps:
			var fill := (float(done_steps) + step_fraction) / float(steps)
			if fill > 0.0:
				var fill_box := base.duplicate() as StyleBoxFlat
				fill_box.bg_color = TutorialUiStyle.ACCENT
				_progress.draw_style_box(fill_box, Rect2(rect.position, Vector2(maxf(PROGRESS_HEIGHT, seg_width * fill), PROGRESS_HEIGHT)))
		x += seg_width + PROGRESS_GAP


# ---------- ルール表示と章バナー ----------

func _collect_presentations(model: Dictionary) -> void:
	for toast_variant: Variant in model.get("toasts", []):
		var toast: Dictionary = toast_variant
		var serial := int(toast.get("serial", 0))
		if serial <= _toast_seen_serial:
			continue
		_toast_seen_serial = serial
		_toast_queue.append(toast)
	var banner: Dictionary = model.get("banner", {})
	var banner_serial := int(banner.get("serial", 0))
	if banner_serial > _banner_seen_serial:
		_banner_seen_serial = banner_serial
		_show_banner(banner)
	if _toast_elapsed < 0.0 and not _toast_queue.is_empty():
		_show_toast(_toast_queue.pop_front())


func _skip_pending_presentations(model: Dictionary) -> void:
	for toast_variant: Variant in model.get("toasts", []):
		_toast_seen_serial = maxi(_toast_seen_serial, int((toast_variant as Dictionary).get("serial", 0)))
	var banner: Dictionary = model.get("banner", {})
	_banner_seen_serial = maxi(_banner_seen_serial, int(banner.get("serial", 0)))
	_toast_queue.clear()
	_toast_elapsed = -1.0
	_banner_elapsed = -1.0
	_toast.visible = false
	_banner.visible = false


func _show_toast(toast: Dictionary) -> void:
	var tone := str(toast.get("tone", "info"))
	var border := TutorialUiStyle.ACCENT
	var bg := Color(TutorialUiStyle.PANEL_SOLID, 0.94)
	var sub_color := TutorialUiStyle.TEXT
	var icon_color := TutorialUiStyle.ACCENT
	match tone:
		"danger":
			border = TutorialUiStyle.DANGER
			bg = Color(0.25, 0.04, 0.06, 0.93)
			sub_color = Color("ffd2cd")
			icon_color = TutorialUiStyle.DANGER
		"good":
			border = TutorialUiStyle.DONE
			bg = Color(0.03, 0.18, 0.11, 0.93)
			sub_color = Color("c9ffde")
			icon_color = TutorialUiStyle.DONE
		"boss":
			border = TutorialUiStyle.ACCENT
			bg = Color(0.17, 0.09, 0.02, 0.94)
			sub_color = Color("ffe6a6")
	var style := TutorialUiStyle.box(bg, Color(border, 0.8), 2, 20, 0.0, 14.0)
	style.content_margin_left = 20.0
	style.content_margin_right = 32.0
	style.shadow_color = Color(border, 0.28)
	style.shadow_size = 22
	_toast.add_theme_stylebox_override("panel", style)
	_toast_icon.glyph = str(toast.get("icon", ""))
	_toast_icon.color = icon_color
	_toast_icon.cut_color = bg
	_toast_title.text = str(toast.get("title", ""))
	_toast_sub.text = str(toast.get("sub", ""))
	_toast_sub.add_theme_color_override("font_color", sub_color)
	_toast_sub.visible = not _toast_sub.text.is_empty()
	_toast.reset_size()
	_toast.visible = true
	_toast_elapsed = 0.0


func _show_banner(banner: Dictionary) -> void:
	_banner_name.text = str(banner.get("label", ""))
	var next_label := str(banner.get("next_label", ""))
	_banner_next.text = ("次の章：%s" % next_label) if not next_label.is_empty() else ""
	_banner.visible = true
	_banner_elapsed = 0.0
	AudioManager.play_sfx(&"door_correct", 0.0, 1.12)


# ---------- アニメーション・配置 ----------

func _advance_animations(delta: float) -> void:
	var weight := 1.0
	if _enter_elapsed >= 0.0:
		_enter_elapsed = minf(ENTER_SECONDS, _enter_elapsed + delta)
		weight = 1.0 - pow(1.0 - clampf(_enter_elapsed / ENTER_SECONDS, 0.0, 1.0), 3.0)
		if _enter_elapsed >= ENTER_SECONDS:
			_enter_elapsed = -1.0
	_hint_shake = maxf(0.0, _hint_shake - delta)
	_layout_bar(weight)
	_layout_toast(delta)
	_layout_banner(delta)


func _layout_bar(weight: float) -> void:
	var view := get_viewport_rect().size
	var bar_size := _bar.get_combined_minimum_size()
	bar_size.x = minf(bar_size.x, BAR_MAX_WIDTH)
	_bar.size = bar_size
	var shake := sin(_hint_shake * 60.0) * 5.0 * (_hint_shake / HINT_SHAKE_SECONDS)
	var rise := (1.0 - weight) * ENTER_RISE
	var x := (view.x - bar_size.x) * 0.5 + shake
	var y := 0.0
	var top := _bar_at_top() and not _compact
	if top:
		y = BAR_MARGIN_TOP - rise
	else:
		y = view.y - BAR_MARGIN - bar_size.y + rise
	_bar.position = Vector2(x, y)
	_bar.modulate.a = weight
	_progress.position = Vector2(x + PROGRESS_INSET, y + bar_size.y + 8.0 if top else y - 8.0 - PROGRESS_HEIGHT)
	_progress.size = Vector2(maxf(0.0, bar_size.x - PROGRESS_INSET * 2.0), PROGRESS_HEIGHT)
	_progress.modulate.a = weight
	_progress.queue_redraw()


func _layout_toast(delta: float) -> void:
	if _toast_elapsed < 0.0:
		_toast.visible = false
		return
	_toast_elapsed += delta
	var total := TOAST_IN + TOAST_HOLD + TOAST_OUT
	if _toast_elapsed >= total:
		_toast_elapsed = -1.0
		_toast.visible = false
		if not _toast_queue.is_empty():
			_show_toast(_toast_queue.pop_front())
		return
	var alpha := 1.0
	var drop := 0.0
	if _toast_elapsed < TOAST_IN:
		var t := _toast_elapsed / TOAST_IN
		alpha = t
		drop = (1.0 - t) * -18.0
	elif _toast_elapsed > TOAST_IN + TOAST_HOLD:
		alpha = 1.0 - (_toast_elapsed - TOAST_IN - TOAST_HOLD) / TOAST_OUT
	var view := get_viewport_rect().size
	var toast_size := _toast.get_combined_minimum_size()
	_toast.size = toast_size
	if _compact:
		# クイズ中は壁の上の問題文を隠さないよう、左上（ハートの表示の下）へ出す。
		_toast.position = Vector2(TOAST_QUIZ_POSITION.x + drop, TOAST_QUIZ_POSITION.y)
	else:
		var top := view.y * TOAST_TOP_RATIO
		if _bar_at_top():
			# 2Pでバーが上にあるときは、バーと進行の線の下へ出す。
			top = maxf(top, _bar.position.y + _bar.size.y + 30.0)
		_toast.position = Vector2((view.x - toast_size.x) * 0.5, top + drop)
	_toast.modulate.a = clampf(alpha, 0.0, 1.0)


## テスト用。今のバー・ルール表示・バナーの見え方をまとめて返す。
func get_debug_snapshot() -> Dictionary:
	var keys: Array[Dictionary] = []
	for pop_key: Variant in _chips.keys():
		var chip: TutorialKeyChip = _chips[pop_key]
		if is_instance_valid(chip):
			keys.append({"id": str(pop_key), "text": chip.label_text, "look": int(chip.look)})
	return {
		"visible": visible and _bar.visible,
		"mission": _mission_label.text,
		"chapter": _chapter_label.text,
		"compact": _compact,
		"keys": keys,
		"bar_rect": Rect2(_bar.position, _bar.size),
		"toast_visible": _toast.visible,
		"toast_title": _toast_title.text,
		"banner_visible": _banner.visible,
		"banner_label": _banner_name.text,
	}


func _layout_banner(delta: float) -> void:
	if _banner_elapsed < 0.0:
		_banner.visible = false
		return
	_banner_elapsed += delta
	var total := BANNER_IN + BANNER_HOLD + BANNER_OUT
	if _banner_elapsed >= total:
		_banner_elapsed = -1.0
		_banner.visible = false
		return
	var view := get_viewport_rect().size
	var slide := 0.0
	var alpha := 1.0
	if _banner_elapsed < BANNER_IN:
		var t := _banner_elapsed / BANNER_IN
		slide = -(1.0 - t * (2.0 - t)) * view.x * 0.35
		alpha = t
	elif _banner_elapsed > BANNER_IN + BANNER_HOLD:
		var t := (_banner_elapsed - BANNER_IN - BANNER_HOLD) / BANNER_OUT
		slide = t * t * view.x * 0.35
		alpha = 1.0 - t
	_banner.position = Vector2(slide, view.y * BANNER_TOP_RATIO - BANNER_HEIGHT * 0.5)
	_banner.size = Vector2(view.x, BANNER_HEIGHT)
	_banner.modulate.a = clampf(alpha, 0.0, 1.0)
