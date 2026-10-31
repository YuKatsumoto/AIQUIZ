extends CanvasLayer

## On-screen controls for touch devices (Android port).
##
## Every control injects the InputEventKey a keyboard would send (Input.parse_input_event), so
## game_world's Input.is_key_pressed / _input / _unhandled_input code keeps working unchanged:
## the stick holds W/A/S/D (P2: the arrows), jump holds Space (P2: right Ctrl), the emotes hold
## 1/2/3 (P2: 8/9/0), pause taps Escape and the contextual スタート / OK button taps Enter.
##
## Only the mobile target (GraphicsQuality.is_mobile_target(), which includes the desktop
## --mobile-preview) builds anything, and the controls only show while a match is attached
## (game_world calls attach_game_world / detach_game_world). What to show is read every frame from
## game_world.touch_context(). On desktop the layer stays empty and the key API still injects.
##
## Also shows "本体をひらいて あそんでね" over everything while the window is narrower than
## NARROW_ASPECT (Z Flip cover screen, split screen), in and out of matches.

const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const Haptics = preload("res://scripts/core/haptics.gd")
const TouchButton = preload("res://scripts/ui/touch/touch_button.gd")
const TouchStick = preload("res://scripts/ui/touch/touch_stick.gd")
const FONT_PATH := "res://resources/fonts/NotoSansJP-Bold.otf"

## Above the HUDs and NetOverlay (60), below the pause menu (100), SceneTransition (100) and the
## practice coach (105), so those stay tappable over the controls.
const LAYER := 90
const NOTICE_LAYER := 127
## Width / height below which the game asks to open the phone (cover screen 948x1048 ≈ 0.9).
const NARROW_ASPECT := 1.3

## Sizes in canvas pixels at touch_controls_scale 1.0 (the 720-high canvas shows at 1.5x on a
## 2520x1080 phone). No target goes below MobileUi.MIN_TOUCH_SIZE.
const EDGE_MARGIN := 36.0
## Gap between the bottom edge of the safe area and the lowest controls.
const BOTTOM_MARGIN := 28.0
const STICK_RADIUS := 104.0
const JUMP_RADIUS := 76.0
const EMOTE_RADIUS := 42.0
## Duo: a slightly smaller jump and compact emotes (≈62 px, MobileUi.MIN_TOUCH_SIZE_COMPACT allowed)
## so each player's cluster fits in their own outer bottom corner.
const DUO_JUMP_RADIUS := 68.0
const DUO_EMOTE_RADIUS := 31.0
const PAUSE_SIZE := 80.0
const CONFIRM_SIZE := Vector2(320.0, 100.0)
const ANSWER_SIZE := 96.0
const DUO_ANSWER_SIZE := 88.0
const ANSWER_GAP := 14.0
## Share of the safe width the stick zone covers (solo: left 40%; duo: each outer 28%).
const SOLO_STICK_ZONE := 0.4
const DUO_STICK_ZONE := 0.28
## The stick zones leave the top of the screen alone (pause button, status cards, HUD buttons).
const STICK_ZONE_TOP := 0.22
## Duo: each player's controls stay within this share of the safe width from their own edge, so the
## centre (≈30%, the track and both characters) stays free during play.
const DUO_SIDE_LIMIT := 0.35

## Same as the HUD (scripts/ui/player_health_hud.gd PLAYER_COLORS): P1 orange, P2 blue. Solo uses P1.
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
const NEUTRAL_COLOR := Color(1.0, 1.0, 1.0)
const CONFIRM_COLOR := Color(1.0, 0.82, 0.3)

## Keys each local seat sends. Stick directions follow TouchStick.LEFT / RIGHT / UP / DOWN;
## answers follow QuizGameState.SUDDEN_DEATH_KEY_LEFT / UP / DOWN / RIGHT.
const STICK_KEYS := [
	[KEY_A, KEY_D, KEY_W, KEY_S],
	[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN],
]
const ANSWER_KEYS := [
	[KEY_A, KEY_W, KEY_S, KEY_D],
	[KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT],
]
const EMOTE_KEYS := [
	[KEY_1, KEY_2, KEY_3],
	[KEY_8, KEY_9, KEY_0],
]
const ANSWER_LABELS := ["A", "B", "C", "D"]

var _enabled := false
var _world: Node = null
var _active := false
var _narrow := false
var _paused_last := false
## "keycode:location" -> {"keycode", "location", "count"}: refcounted, so two controls holding the
## same key only send one press and one release.
var _held: Dictionary = {}
## tap_key: [keycode, location, frame] to let go once a later frame runs.
var _taps: Array = []
var _font: Font = null
var _mouse_as_touch := false
var _layout_key := ""
var _answer_keys: Array = []
var _skip_center_alone := Vector2.ZERO
var _skip_center_stacked := Vector2.ZERO

var _root: Control = null
var _sticks: Array[TouchStick] = [null, null]
var _jumps: Array[TouchButton] = [null, null]
## Per seat: three emote buttons, four answer buttons.
var _emotes: Array = [[], []]
var _answers: Array = [[], []]
var _pause_button: TouchButton = null
var _confirm_button: TouchButton = null
var _skip_button: TouchButton = null
var _notice_layer: CanvasLayer = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = QualityRules.is_mobile_target()
	if not _enabled:
		# Desktop builds nothing; _process only lets go of tap_key presses.
		return
	_mouse_as_touch = QualityRules.is_mobile_preview() and not DisplayServer.is_touchscreen_available()
	_font = load(FONT_PATH) as Font
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


# ---------- Public API ----------

## The touch layer is in use (mobile target, a match attached, the phone opened).
func is_active() -> bool:
	return _active


## The contextual スタート / OK / つぎへ / スキップ button (TouchRoot/ConfirmButton, taps Enter) is on screen.
func is_confirm_shown() -> bool:
	return _active and _root != null and _root.visible and _confirm_button != null and _confirm_button.visible


## The sudden-death スキップ button (TouchRoot/SkipButton, taps Space) is on screen.
func is_skip_shown() -> bool:
	return _active and _root != null and _root.visible and _skip_button != null and _skip_button.visible


func attach_game_world(world: Node) -> void:
	if _world != null and _world != world:
		release_all()
	_world = world


func detach_game_world(world: Node) -> void:
	if _world != world:
		return
	_world = null
	release_all()
	_active = false
	if _root != null:
		_root.visible = false


func press_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var id := _key_id(keycode, location)
	var entry: Dictionary = _held.get(id, {})
	if entry.is_empty():
		entry = {"keycode": keycode, "location": location, "count": 0}
		_held[id] = entry
	entry.count = int(entry.count) + 1
	if int(entry.count) == 1:
		_send_key(keycode, location, true)


func release_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var id := _key_id(keycode, location)
	if not _held.has(id):
		return
	var entry: Dictionary = _held[id]
	entry.count = int(entry.count) - 1
	if int(entry.count) <= 0:
		_held.erase(id)
		_send_key(keycode, location, false)


## Press now, let go on the next frame (Enter, Escape, an answer).
func tap_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	# A tap on a key another button holds (スキップ while ジャンプ is down, both Space) still
	# needs its own press event for _input handlers; the hold keeps the key down after it.
	if _held.has(_key_id(keycode, location)):
		_send_key(keycode, location, true)
	press_key(keycode, location)
	_taps.append([keycode, location, Engine.get_process_frames()])


## Lets go of every key the layer holds and forgets every finger (hide, pause, scene change,
## focus loss, app pause), so nothing stays stuck down.
func release_all() -> void:
	for id: String in _held.keys():
		var entry: Dictionary = _held[id]
		_send_key(entry.keycode, entry.location, false)
	_held.clear()
	_taps.clear()
	for control: Control in _all_controls():
		control.call("reset_silent")


# ---------- Frame ----------

func _process(_delta: float) -> void:
	_release_taps()
	if not _enabled:
		return
	_update_notice()
	var context: Dictionary = {}
	if is_instance_valid(_world) and _world.has_method("touch_context"):
		context = _world.call("touch_context")
	elif _world != null:
		_world = null
	var was_active := _active
	_active = not context.is_empty() and not _narrow
	if not _active:
		if was_active:
			release_all()
		_root.visible = false
		return
	_root.visible = true
	_paused_last = _paused_last and was_active
	var paused: bool = context.get("paused", false)
	if paused and not _paused_last:
		release_all()
	_paused_last = paused
	_apply_context(context, paused)
	if not paused:
		_release_gui_focus()


func _release_taps() -> void:
	if _taps.is_empty():
		return
	var frame := Engine.get_process_frames()
	var keep: Array = []
	for tap: Array in _taps:
		if frame > int(tap[2]):
			release_key(tap[0], tap[1])
		else:
			keep.append(tap)
	_taps = keep


func _apply_context(context: Dictionary, paused: bool) -> void:
	var players: int = clampi(int(context.get("local_players", 1)), 1, 2)
	var answer_keys: Array = context.get("sd_answer_keys", [])
	var answers := answer_keys.size() >= 2
	var key := "%s|%s|%.2f|%d|%s" % [
		get_viewport().get_visible_rect().size, SafeArea.rect(), _scale(), players, answer_keys,
	]
	if key != _layout_key:
		_layout_key = key
		_answer_keys = answer_keys.duplicate()
		_layout(players, answer_keys.size())
	# A card or a line that stops the play (rule card, charge tutorial, practice lines and pick
	# card) hides the seat controls, so taps reach the card's own tap-to-close below this layer.
	var controls: bool = (
		not paused
		and bool(context.get("controls", false))
		and not bool(context.get("overlay_open", false))
		and not bool(context.get("modal", false))
	)
	var ghost: Array = context.get("ghost", [false, false])
	for seat: int in range(2):
		var seat_on := controls and seat < players
		_set_shown(_sticks[seat], seat_on and not answers)
		_set_shown(_jumps[seat], seat_on)
		for button: Control in _emotes[seat]:
			_set_shown(button, seat_on and not answers)
		for index: int in range(_answers[seat].size()):
			_set_shown(_answers[seat][index], seat_on and answers and index < answer_keys.size())
		var jump := _jumps[seat]
		var jump_label := "アクション" if answers else ("ためる" if seat < ghost.size() and bool(ghost[seat]) else "ジャンプ")
		if jump.label != jump_label:
			jump.label = jump_label
			jump.queue_redraw()
	_set_shown(_pause_button, not paused and bool(context.get("can_pause", false)))
	var confirm: String = str(context.get("confirm", "")) if not paused else ""
	_set_shown(_confirm_button, not confirm.is_empty())
	if not confirm.is_empty() and _confirm_button.label != confirm:
		_confirm_button.label = confirm
		_confirm_button.queue_redraw()
	var skip_shown := not paused and bool(context.get("skip", false))
	_set_shown(_skip_button, skip_shown)
	if skip_shown:
		# Alone it takes the bottom-centre slot; with the スタート / OK button it sits just above it.
		var skip_center := _skip_center_stacked if _confirm_button.visible else _skip_center_alone
		if not _skip_button.get_rect().get_center().is_equal_approx(skip_center):
			_skip_button.place_box(skip_center, _skip_button.box_size)


## Hides a control and lets go of whatever it held.
func _set_shown(control: Control, shown: bool) -> void:
	if control.visible == shown:
		return
	if not shown and bool(control.call("is_down")):
		control.call("force_release")
	control.visible = shown


## Injected Space / Enter would press a focused Button and W/A/S/D would type into a focused
## LineEdit: inside a match nothing below this layer keeps the keyboard focus. The pause menu and
## the practice coach sit above and keep theirs.
func _release_gui_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return
	var owner_layer := focus_owner.get_canvas_layer_node()
	if owner_layer == null or owner_layer.layer < LAYER:
		get_viewport().gui_release_focus()


# ---------- Build & layout ----------

func _build() -> void:
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	for seat: int in range(2):
		var seat_color := P1_COLOR if seat == 0 else P2_COLOR
		var stick := TouchStick.new()
		stick.name = "Stick%d" % (seat + 1)
		stick.color = seat_color
		stick.font = _font
		stick.mouse_as_touch = _mouse_as_touch
		stick.direction_changed.connect(_on_stick_direction.bind(seat))
		_root.add_child(stick)
		_sticks[seat] = stick
		for slot: int in range(3):
			var emote := _make_button("Emote%d_%d" % [seat + 1, slot + 1], str(slot + 1), seat_color)
			emote.caption = "エモート"
			var emote_key: Key = EMOTE_KEYS[seat][slot]
			emote.pressed_changed.connect(_on_hold_button.bind(emote_key, KEY_LOCATION_UNSPECIFIED))
			_emotes[seat].append(emote)
		for index: int in range(4):
			var answer := _make_button("Answer%d_%d" % [seat + 1, index + 1], ANSWER_LABELS[index], seat_color)
			answer.pressed_changed.connect(_on_answer_button.bind(seat, index))
			_answers[seat].append(answer)
		var jump := _make_button("Jump%d" % (seat + 1), "ジャンプ", seat_color)
		if seat == 0:
			jump.pressed_changed.connect(_on_hold_button.bind(KEY_SPACE, KEY_LOCATION_UNSPECIFIED))
		else:
			jump.pressed_changed.connect(_on_hold_button.bind(KEY_CTRL, KEY_LOCATION_RIGHT))
		_jumps[seat] = jump
	_skip_button = _make_button("SkipButton", "スキップ", NEUTRAL_COLOR)
	_skip_button.pressed_changed.connect(_on_tap_button.bind(KEY_SPACE))
	_confirm_button = _make_button("ConfirmButton", "スタート", CONFIRM_COLOR)
	_confirm_button.pressed_changed.connect(_on_tap_button.bind(KEY_ENTER))
	# Added last: drawn and hit-tested above the stick zone it overlaps.
	_pause_button = _make_button("PauseButton", "", NEUTRAL_COLOR)
	_pause_button.icon = "pause"
	_pause_button.pressed_changed.connect(_on_tap_button.bind(KEY_ESCAPE))
	for control: Control in _all_controls():
		control.visible = false

	_notice_layer = CanvasLayer.new()
	_notice_layer.name = "OpenPhoneNotice"
	_notice_layer.layer = NOTICE_LAYER
	_notice_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_notice_layer.visible = false
	add_child(_notice_layer)
	var cover := ColorRect.new()
	cover.color = Color(0.04, 0.05, 0.09, 0.96)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notice_layer.add_child(cover)
	var notice := Label.new()
	notice.text = "本体をひらいて あそんでね"
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.set_anchors_preset(Control.PRESET_FULL_RECT)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		notice.add_theme_font_override("font", _font)
	notice.add_theme_font_size_override("font_size", MobileUi.font(44))
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	notice.add_theme_constant_override("outline_size", 8)
	cover.add_child(notice)


func _make_button(node_name: String, text: String, button_color: Color) -> TouchButton:
	var button := TouchButton.new()
	button.name = node_name
	button.label = text
	button.color = button_color
	button.font = _font
	button.mouse_as_touch = _mouse_as_touch
	_root.add_child(button)
	return button


func _all_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if _root == null:
		return controls
	for child: Node in _root.get_children():
		if child is Control:
			controls.append(child as Control)
	return controls


func _scale() -> float:
	return clampf(float(GameManager.touch_controls_scale), 0.8, 1.3)


func _size(base: float) -> float:
	return maxf(base * _scale(), MobileUi.MIN_TOUCH_SIZE * 0.5)


func _layout(players: int, answer_count: int) -> void:
	var safe: Rect2 = SafeArea.rect()
	var view := get_viewport().get_visible_rect().size
	var ui_scale := _scale()
	var margin := EDGE_MARGIN * ui_scale
	var bottom := safe.end.y - BOTTOM_MARGIN * ui_scale
	var duo := players >= 2
	var stick_r := _size(STICK_RADIUS)
	var jump_r := _size(DUO_JUMP_RADIUS if duo else JUMP_RADIUS)
	var emote_r := _size(EMOTE_RADIUS)
	if duo:
		emote_r = maxf(DUO_EMOTE_RADIUS * ui_scale, MobileUi.MIN_TOUCH_SIZE_COMPACT * 0.5)
	var emote_gap := jump_r + emote_r + (10.0 if duo else 14.0) * ui_scale
	var cluster_gap := 14.0 * ui_scale
	var answer_side := maxf((DUO_ANSWER_SIZE if duo else ANSWER_SIZE) * ui_scale, MobileUi.MIN_TOUCH_SIZE)
	var answer_gap := (12.0 if duo else ANSWER_GAP) * ui_scale
	var row_width := answer_count * answer_side + maxi(answer_count - 1, 0) * answer_gap
	# Stick zones cover only the lower part of the screen: the pause button, the status cards and
	# the HUD buttons at the top stay tappable.
	var zone_top := maxf(safe.position.y + safe.size.y * STICK_ZONE_TOP, view.y * STICK_ZONE_TOP)
	zone_top = minf(zone_top, bottom - stick_r * 2.0)
	var side_limit := safe.size.x * DUO_SIDE_LIMIT

	for seat: int in range(2):
		var right_side := duo and seat == 1
		# Distances are measured from the seat's own screen edge towards the centre.
		var outer_x := safe.end.x if right_side else safe.position.x
		var inward := -1.0 if right_side else 1.0

		var stick := _sticks[seat]
		var zone_width := safe.size.x * (DUO_STICK_ZONE if duo else SOLO_STICK_ZONE)
		if duo:
			zone_width = minf(zone_width, side_limit)
		var zone_x := safe.end.x - zone_width if right_side else safe.position.x
		stick.position = Vector2(zone_x, zone_top)
		stick.size = Vector2(zone_width, maxf(safe.end.y - zone_top, stick_r * 2.0))
		stick.radius = stick_r
		stick.font_size = int(22.0 * ui_scale)
		# Rest ring in the bottom outer corner.
		var rest := Vector2(outer_x + inward * (margin + stick_r), bottom - stick_r)
		stick.rest_center = rest - stick.position
		stick.queue_redraw()

		var jump_center: Vector2
		if duo:
			if answer_count >= 2:
				# Sudden death: the answer row in the outer corner, the アクション button just inside it.
				var row_reach := margin + row_width + cluster_gap + jump_r * 2.0
				if row_reach <= side_limit:
					jump_center = Vector2(outer_x + inward * (row_reach - jump_r), bottom - jump_r)
				else:
					# Narrow screen: on top of the row's outer end instead of further in.
					jump_center = Vector2(outer_x + inward * (margin + jump_r), bottom - answer_side - cluster_gap - jump_r)
			else:
				# Beside the stick's rest ring, emotes on the arc above and towards the centre.
				var reach := margin + stick_r * 2.0 + cluster_gap + jump_r + emote_gap + emote_r
				var pull := maxf(reach - side_limit, 0.0)
				var jump_d := margin + stick_r * 2.0 + cluster_gap + jump_r - pull
				jump_center = Vector2(outer_x + inward * jump_d, bottom - jump_r)
		else:
			# Solo: the bottom-right corner.
			jump_center = Vector2(safe.end.x - margin - jump_r, bottom - jump_r)
		var jump := _jumps[seat]
		jump.place_round(jump_center, jump_r)
		jump.font_size = int((24.0 if duo else 26.0) * ui_scale)

		# Emotes on an arc around the jump button: above it, then towards the centre (duo) or away
		# from the right edge (solo).
		var angles: Array[float] = [180.0, 225.0, 270.0]
		if right_side:
			angles = [270.0, 225.0, 180.0]
		elif duo:
			angles = [270.0, 315.0, 0.0]
		for slot: int in range(3):
			var angle := deg_to_rad(angles[slot])
			var emote: TouchButton = _emotes[seat][slot]
			emote.place_round(jump_center + Vector2(cos(angle), sin(angle)) * emote_gap, emote_r)
			emote.font_size = int((24.0 if duo else 28.0) * ui_scale)
			# The compact duo emotes are too small for the second line.
			emote.caption = "" if duo else "エモート"

		# Sudden-death answers: one row per seat in its outer corner, choices read left to right (A, B, C, D).
		var row_x := safe.position.x + margin
		if right_side:
			row_x = safe.end.x - margin - row_width
		for index: int in range(4):
			var answer: TouchButton = _answers[seat][index]
			var center := Vector2(row_x + answer_side * 0.5 + index * (answer_side + answer_gap), bottom - answer_side * 0.5)
			answer.place_box(center, Vector2(answer_side, answer_side))
			answer.font_size = int((36.0 if duo else 40.0) * ui_scale)

	# スタート / OK / つぎへ / スキップ: bottom centre in every layout (between the two players'
	# clusters in duo, below the HUD's centre message panel).
	var confirm_size := Vector2(CONFIRM_SIZE.x * ui_scale, maxf(CONFIRM_SIZE.y * ui_scale, MobileUi.MIN_TOUCH_SIZE))
	if duo:
		confirm_size.x = minf(confirm_size.x, maxf(safe.size.x * (1.0 - DUO_SIDE_LIMIT * 2.0) - margin, MobileUi.MIN_TOUCH_SIZE * 2.0))
	var confirm_center := Vector2(safe.get_center().x, bottom - confirm_size.y * 0.5)
	_confirm_button.place_box(confirm_center, confirm_size)
	_confirm_button.font_size = int(34.0 * ui_scale)
	var skip_size := Vector2(220.0 * ui_scale, maxf(80.0 * ui_scale, MobileUi.MIN_TOUCH_SIZE))
	_skip_center_alone = Vector2(confirm_center.x, bottom - skip_size.y * 0.5)
	_skip_center_stacked = confirm_center - Vector2(0.0, (confirm_size.y + skip_size.y) * 0.5 + 14.0 * ui_scale)
	_skip_button.place_box(_skip_center_stacked if _confirm_button.visible else _skip_center_alone, skip_size)
	_skip_button.font_size = int(28.0 * ui_scale)
	var pause_side := maxf(PAUSE_SIZE * ui_scale, MobileUi.MIN_TOUCH_SIZE)
	_pause_button.place_box(safe.position + Vector2.ONE * (margin * 0.5 + pause_side * 0.5), Vector2(pause_side, pause_side))


# ---------- Control callbacks ----------

func _on_stick_direction(direction: int, down: bool, seat: int) -> void:
	var keycode: Key = STICK_KEYS[seat][direction]
	if down:
		press_key(keycode)
	else:
		release_key(keycode)


func _on_hold_button(down: bool, keycode: Key, location: KeyLocation) -> void:
	if down:
		Haptics.pulse(Haptics.TAP)
		press_key(keycode, location)
	else:
		release_key(keycode, location)


func _on_tap_button(down: bool, keycode: Key) -> void:
	if not down:
		return
	Haptics.pulse(Haptics.TAP)
	tap_key(keycode)


func _on_answer_button(down: bool, seat: int, index: int) -> void:
	if not down or index >= _answer_keys.size():
		return
	var answer_key := int(_answer_keys[index])
	if answer_key < 0 or answer_key > 3:
		return
	Haptics.pulse(Haptics.TAP)
	tap_key(ANSWER_KEYS[seat][answer_key])


# ---------- Cover screen / split screen ----------

func _update_notice() -> void:
	var view := get_viewport().get_visible_rect().size
	var narrow := view.y > 0.0 and view.x / view.y < NARROW_ASPECT
	if narrow != _narrow:
		_narrow = narrow
		_notice_layer.visible = narrow
		if narrow:
			release_all()
	# Every frame while covered: a match in FLYOVER/CORRECT cannot pause yet and would
	# otherwise run on into PLAYING behind the notice. Pausing twice is a no-op.
	if _narrow and is_instance_valid(_world) and _world.has_method("pause_for_background"):
		_world.call("pause_for_background")


# ---------- Key injection ----------

static func _key_id(keycode: Key, location: KeyLocation) -> String:
	return "%d:%d" % [keycode, location]


func _send_key(keycode: Key, location: KeyLocation, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)
