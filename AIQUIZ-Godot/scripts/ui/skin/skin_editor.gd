extends Node
class_name SkinEditor

## スキンの色編集（パーツごとの単色）。カスタマイズ画面「スキン」タブとオンライン画面で使う。
## 「① ぬるところ」（人型・おすすめ）、「② 色」（パレット・スライダー）、ツールバーを組み立て、
## 編集結果を PlayerSkinStore（保存）と QuizManager.game_state（ゲームで使う値）へ書く。
## 3D プレビューへの反映・帽子・カメラは呼ぶ側がシグナルで受け持つ。

signal look_changed(player: int, skin: Dictionary)
signal part_selected(player: int, part_id: StringName)
signal hat_restore_requested(player: int, hat_id: int)

## パレット：12色相 × 3段（あざやか／うすい／こい）＋ 無彩色1列。
const PALETTE_HUES: Array[float] = [0.0, 0.05, 0.10, 0.15, 0.22, 0.33, 0.45, 0.52, 0.60, 0.68, 0.78, 0.90]
const PALETTE_ROWS: Array[Vector2] = [Vector2(0.82, 0.96), Vector2(0.38, 1.0), Vector2(0.85, 0.52)]
const PALETTE_NEUTRALS: Array[Color] = [Color(0.97, 0.97, 0.96), Color(0.55, 0.57, 0.60), Color(0.12, 0.12, 0.14)]
const PALETTE_NEUTRAL_NAMES: Array[String] = ["しろ", "グレー", "くろ"]

var player: int = 1
var target: StringName = PlayerSkin.ALL
## チュートリアルの紹介中などは false にして操作を止める。
var input_enabled: bool = true
## true なら どのプレイヤーも あたまを選べない（カスタマイズ画面：ローカル2人対戦で見分けるため固定）。
## false でもプレイヤー2 のあたまは固定（オンライン画面はプレイヤー1 だけを編集し、あたまも変えられる）。
var lock_head: bool = false
var history := SkinEditHistory.new()

var _hue_memory: float = 0.0
var _syncing := false
var _rng := RandomNumberGenerator.new()

var _body_map: SkinBodyMap
var _all_button: SkinToolButton
var _target_label: Label
var _note_label: Label
var _presets: Array[SkinPresetThumb] = []
var _preset_slot: int = -1

var _color_header: HBoxContainer
var _palette: Array[SkinPaletteSwatch] = []
var _hue_slider: SkinColorSlider
var _sat_slider: SkinColorSlider
var _val_slider: SkinColorSlider

var _undo_button: SkinToolButton
var _reset_button: SkinToolButton
var _random_button: SkinToolButton
var _copy_button: SkinToolButton


func _init() -> void:
	name = "SkinEditor"
	_rng.randomize()


# ===========================================================================
# 組み立て
# ===========================================================================

## ① ぬるところ（全身ボタン・人型・注意書き）と、with_presets なら おすすめ。
func build_left(container: VBoxContainer, with_presets: bool = true) -> void:
	container.add_theme_constant_override(&"separation", 8)
	container.add_child(SkinUiStyle.section_header("1", "ぬるところ"))
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override(&"separation", 6)
	container.add_child(target_row)
	_all_button = SkinToolButton.new(SkinToolButton.Icon.NONE, "全身", "全身をまとめて同じ色にします")
	_all_button.name = "WholeBodyButton"
	_all_button.toggle_mode = true
	_all_button.custom_minimum_size = Vector2(64, 30)
	_all_button.pressed.connect(func() -> void: select_part(PlayerSkin.ALL))
	target_row.add_child(_all_button)
	_target_label = SkinUiStyle.label("", 13, SkinUiStyle.TEXT, true)
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_row.add_child(_target_label)

	_body_map = SkinBodyMap.new()
	_body_map.name = "SkinBodyMap"
	_body_map.custom_minimum_size = Vector2(0, 220)
	_body_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_map.part_clicked.connect(func(part_id: StringName) -> void: select_part(part_id))
	container.add_child(_body_map)

	_note_label = SkinUiStyle.label("", 12, SkinUiStyle.MUTED)
	_note_label.name = "HeadNote"
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(_note_label)

	if not with_presets:
		return
	container.add_child(SkinUiStyle.section_header("★", "おすすめ"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 5)
	container.add_child(row)
	for preset_id: StringName in PlayerSkin.PRESET_IDS:
		var thumb := SkinPresetThumb.new(preset_id)
		thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		thumb.custom_minimum_size = Vector2(0, 66)
		thumb.pressed.connect(func() -> void: _apply_preset(preset_id))
		row.add_child(thumb)
		_presets.append(thumb)


## ② 色（パレットとスライダー）。swatch_size はパレット1マスの大きさ。
func build_right(container: VBoxContainer, swatch_size: float = 24.0) -> void:
	container.add_theme_constant_override(&"separation", 8)
	_color_header = SkinUiStyle.section_header("2", "色")
	container.add_child(_color_header)

	var palette_grid := GridContainer.new()
	palette_grid.name = "Palette"
	palette_grid.columns = PALETTE_HUES.size() + 1
	palette_grid.add_theme_constant_override(&"h_separation", 4)
	palette_grid.add_theme_constant_override(&"v_separation", 4)
	container.add_child(palette_grid)
	for row: int in range(PALETTE_ROWS.size()):
		var sv := PALETTE_ROWS[row]
		for hue: float in PALETTE_HUES:
			_add_palette_swatch(palette_grid, Color.from_hsv(hue, sv.x, sv.y), "この色にする", swatch_size)
		_add_palette_swatch(palette_grid, PALETTE_NEUTRALS[row], PALETTE_NEUTRAL_NAMES[row], swatch_size)

	_hue_slider = _add_color_slider(container, "色あい", SkinColorSlider.Mode.HUE, "虹の中から色をえらびます")
	_sat_slider = _add_color_slider(container, "あざやかさ", SkinColorSlider.Mode.SATURATION, "左ほど くすんだ色、右ほど あざやかな色")
	_val_slider = _add_color_slider(container, "明るさ", SkinColorSlider.Mode.VALUE, "左ほど 暗い色、右ほど 明るい色")


## ツールバー。with_copy なら「P2にコピー」も出す（プレイヤーを切りかえられる画面だけ）。
func build_toolbar(container: HBoxContainer, with_copy: bool = true) -> void:
	container.add_theme_constant_override(&"separation", 8)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	_undo_button = SkinToolButton.new(SkinToolButton.Icon.UNDO, "もどす", "ひとつ前の状態にもどします（Ctrl+Z）")
	_reset_button = SkinToolButton.new(SkinToolButton.Icon.RESET, "はじめの色", "")
	_random_button = SkinToolButton.new(SkinToolButton.Icon.DICE, "おまかせ", "全身の色をランダムにきめます")
	_undo_button.pressed.connect(undo)
	_reset_button.pressed.connect(_reset_target)
	_random_button.pressed.connect(_randomize)
	for button: SkinToolButton in [_undo_button, _reset_button, _random_button]:
		container.add_child(button)
	if with_copy:
		_copy_button = SkinToolButton.new(SkinToolButton.Icon.COPY, "P2にコピー", "")
		_copy_button.pressed.connect(_copy_to_other)
		container.add_child(_copy_button)


func _add_palette_swatch(grid: GridContainer, color: Color, tip: String, swatch_size: float) -> void:
	var swatch := SkinPaletteSwatch.new(PlayerSkin.quantize(color), tip)
	swatch.custom_minimum_size = Vector2(swatch_size, swatch_size)
	swatch.pressed.connect(func() -> void: _set_color(swatch.swatch_color, ""))
	grid.add_child(swatch)
	_palette.append(swatch)


func _add_color_slider(container: VBoxContainer, caption: String, mode: SkinColorSlider.Mode, tip: String) -> SkinColorSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	container.add_child(row)
	var caption_label := SkinUiStyle.label(caption, 13, SkinUiStyle.MUTED)
	caption_label.custom_minimum_size = Vector2(76, 0)
	row.add_child(caption_label)
	var slider := SkinColorSlider.new(mode)
	slider.tooltip_text = tip
	slider.value_changed.connect(func(_value: float) -> void: _on_hsv_changed())
	slider.drag_ended.connect(func(_changed: bool) -> void: history.break_coalescing(player))
	row.add_child(slider)
	return slider


# ===========================================================================
# 状態
# ===========================================================================

func current_skin(for_player: int = -1) -> Dictionary:
	var slot := player if for_player < 0 else for_player
	return PlayerSkin.resolve(PlayerSkinStore.get_skin(slot), slot)


func current_color() -> Color:
	return PlayerSkin.target_color(current_skin(), target)


## 今のプレイヤーで選べないパーツか（あたまの固定）。
func is_part_locked(part_id: StringName, for_player: int = -1) -> bool:
	return part_id == PlayerSkin.HEAD and is_head_locked(for_player)


func is_head_locked(for_player: int = -1) -> bool:
	var slot := player if for_player < 0 else for_player
	return lock_head or PlayerSkinStore.is_head_locked(slot)


func _hat_of(slot: int) -> int:
	var gs := QuizManager.game_state
	return gs.p2_hat if slot == 2 else gs.p1_hat


func _snapshot(slot: int) -> Dictionary:
	return SkinEditHistory.snapshot(PlayerSkinStore.get_skin(slot), _hat_of(slot))


func set_editing_player(value: int) -> void:
	player = 2 if value == 2 else 1
	if is_part_locked(target):
		target = PlayerSkin.ALL
	refresh()


func select_part(part_id: StringName) -> void:
	if not input_enabled or is_part_locked(part_id):
		return
	target = part_id
	refresh()
	part_selected.emit(player, target)


## 3D のホバーを人型マップにも映す。
func show_hover(part_id: StringName) -> void:
	if _body_map:
		_body_map.show_hover(part_id)


# ===========================================================================
# 編集
# ===========================================================================

func _commit(new_skin: Dictionary, coalesce_key: String = "", slot: int = -1) -> void:
	var edit_slot := player if slot < 0 else slot
	if not input_enabled:
		return
	if is_head_locked(edit_slot):
		# あたまを選べないときは、全身・おすすめ・おまかせでも あたまの色はそのまま
		new_skin = new_skin.duplicate()
		new_skin[PlayerSkin.HEAD] = current_skin(edit_slot)[PlayerSkin.HEAD]
	var normalized := PlayerSkinStore.normalized(edit_slot, new_skin)
	var old_code := PlayerSkin.to_code(PlayerSkinStore.get_skin(edit_slot), edit_slot)
	if PlayerSkin.to_code(normalized, edit_slot) == old_code:
		return
	history.record(edit_slot, _snapshot(edit_slot), coalesce_key)
	_store(edit_slot, normalized)
	refresh()


func _store(slot: int, skin: Dictionary) -> void:
	PlayerSkinStore.set_skin(slot, skin)
	var stored := PlayerSkinStore.get_skin(slot)
	QuizManager.game_state.set_player_skin(slot, stored)
	look_changed.emit(slot, stored)


func _set_color(color: Color, coalesce_key: String) -> void:
	if _syncing:
		return
	_commit(PlayerSkin.set_color(current_skin(), target, color), coalesce_key)


func _on_hsv_changed() -> void:
	if _syncing:
		return
	_hue_memory = _hue_slider.value
	_set_color(Color.from_hsv(_hue_slider.value, _sat_slider.value, _val_slider.value), "hsv")


func _apply_preset(preset_id: StringName) -> void:
	_commit(PlayerSkin.resolve(PlayerSkin.preset_skin(preset_id, player), player))


func _reset_target() -> void:
	_commit(PlayerSkin.reset_target(current_skin(), target, player))


func _randomize() -> void:
	_commit(PlayerSkin.random_skin(_rng, current_skin(3 - player)))


## あたま以外の色をもう一人へ写す（あたまは2人で見分けるため、それぞれのまま）。
func _copy_to_other() -> void:
	var other := 3 - player
	var copied := current_skin(other)
	var source := current_skin()
	for part_id: StringName in PlayerSkin.PART_IDS:
		if part_id != PlayerSkin.HEAD:
			copied[part_id] = source[part_id]
	_commit(copied, "", other)
	refresh()


func undo() -> void:
	if not input_enabled:
		return
	_restore(history.undo(player, _snapshot(player)))


func redo() -> void:
	if not input_enabled:
		return
	_restore(history.redo(player, _snapshot(player)))


func _restore(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_store(player, snapshot.get("skin", {}))
	var hat := int(snapshot.get("hat", _hat_of(player)))
	if hat != _hat_of(player):
		hat_restore_requested.emit(player, hat)
	refresh()


## 呼ぶ側が帽子を変えたときに呼ぶ（帽子も「もどす」の対象）。
func record_hat_change(slot: int, old_hat: int) -> void:
	history.record(slot, SkinEditHistory.snapshot(PlayerSkinStore.get_skin(slot), old_hat))
	refresh_toolbar()


## Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z。処理したら true。
func handle_shortcut(event: InputEvent) -> bool:
	if not input_enabled or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.is_command_or_control_pressed():
		return false
	if key.keycode == KEY_Z and not key.shift_pressed:
		undo()
		return true
	if key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed):
		redo()
		return true
	return false


# ===========================================================================
# 表示の更新
# ===========================================================================

func refresh() -> void:
	if _body_map == null or _hue_slider == null:
		return
	_syncing = true
	var skin := current_skin()
	var target_name := PlayerSkin.part_label(target)

	# ① ぬるところ
	var locked: Array[StringName] = []
	if is_head_locked():
		locked.append(PlayerSkin.HEAD)
	_body_map.set_locked(locked)
	# 固定のあたまは、試合で見える標準色で描く
	_body_map.set_skin(PlayerSkin.with_default_head(skin, player) if is_head_locked() else skin)
	_body_map.set_selected(target)
	_body_map.accent = PlayerController.P1_BODY.lightened(0.25) if player == 1 else PlayerController.P2_BODY.lightened(0.25)
	_all_button.button_pressed = target == PlayerSkin.ALL
	_target_label.text = "全身をまとめて" if target == PlayerSkin.ALL else "いま：%s" % target_name
	_note_label.text = "" if locked.is_empty() else "あたまは固定（2人で見分けるため）"
	_note_label.visible = not _note_label.text.is_empty()
	if _preset_slot != player:
		_preset_slot = player
		for thumb: SkinPresetThumb in _presets:
			thumb.show_for_slot(player, is_head_locked())

	# ② 色
	_set_header_detail(_color_header, "― %s" % target_name)
	var color := current_color()
	var quantized := PlayerSkin.quantize(color)
	for swatch: SkinPaletteSwatch in _palette:
		swatch.set_current(swatch.swatch_color.to_rgba32() == quantized.to_rgba32())
	var hue := color.h if color.s > 0.02 and color.v > 0.02 else _hue_memory
	_hue_memory = hue
	_hue_slider.set_value_no_signal(hue)
	_sat_slider.set_value_no_signal(color.s)
	_val_slider.set_value_no_signal(color.v)
	for slider: SkinColorSlider in [_hue_slider, _sat_slider, _val_slider]:
		slider.set_hsv(hue, color.s, color.v)
	_syncing = false
	refresh_toolbar()


func refresh_toolbar() -> void:
	if _undo_button == null:
		return
	_undo_button.disabled = not history.can_undo(player)
	var other := 3 - player
	if _copy_button:
		_copy_button.set_text("P%dにコピー" % other)
		_copy_button.tooltip_text = "いまの色を プレイヤー%d にもコピーします（あたまと帽子はそのまま）" % other
	_reset_button.tooltip_text = (
		"全身を はじめの色（プレイヤー%dの色）にもどします" % player
		if target == PlayerSkin.ALL
		else "%s だけ はじめの色にもどします" % PlayerSkin.part_label(target)
	)


func _set_header_detail(header: HBoxContainer, text: String) -> void:
	var detail := header.get_node_or_null("Detail") as Label
	if detail:
		detail.text = text


## Tab で巡る順（呼ぶ側がフォーカスの輪につなげる）。
func focus_chain() -> Array[Control]:
	var chain: Array[Control] = []
	if _all_button == null:
		return chain
	chain.append(_all_button)
	chain.append(_body_map)
	for thumb: SkinPresetThumb in _presets:
		chain.append(thumb)
	return chain


func right_focus_chain() -> Array[Control]:
	var chain: Array[Control] = []
	for swatch: SkinPaletteSwatch in _palette:
		chain.append(swatch)
	for control: Control in [_hue_slider, _sat_slider, _val_slider]:
		chain.append(control)
	return chain


func toolbar_focus_chain() -> Array[Control]:
	var chain: Array[Control] = []
	for control: Control in [_undo_button, _reset_button, _random_button, _copy_button]:
		if control:
			chain.append(control)
	return chain
