class_name PracticeCoach
extends CanvasLayer

## 画面のコーチ（docs/new_tutorial/phase5_design.md 5.1、course2_script.md 1.2）。
## 本物の画面（ポーズ画面・リザルトのカード・メインメニュー）の上で、いま見てほしい所を光らせ（ゆっくり脈打つ枠）、
## まわりを少し暗くし、光っている所だけ押せるようにする。ハテナの吹き出しと、ハテナの小窓（担当 C の HatenaPortrait）も出す。
##   focus(targets, clickable, grab_focus) / clear_focus() / say(text, seconds, hold) -> Signal / hide_bubble() / wait(seconds)
##   set_anchor(anchor) / show_portrait(on) / portrait() / set_guard(on) / close()
## 作った時から close() まで、光っていない所はマウスでもキーボード（フォーカスの移動・Enter・スペース）でも押せない。
## 光っている所が clickable のときだけ、そこはマウスでも Enter でも押せる（スライダーは動かせる）。
## Esc で exit_requested（pass_escape が false なら Esc は下の画面に渡さない）。
## ポーズ中も動く（PROCESS_MODE_ALWAYS）。暗い幕・光る枠・押せない仕組みは layer 105、吹き出しと小窓は layer 106。
## 光らせる部品の画面の位置は get_global_transform_with_canvas で取る（部品の CanvasLayer は、ずらしたり拡大したりしない前提）。

## Esc（ポーズ画面の上では、下の画面の『ゲームに戻る』と同じ Esc）でコーチを抜けたい
signal exit_requested
## 吹き出しを出した（say に渡した ID か文字のまま）
signal said(text: String)

const LAYER := 105
const TOP_LAYER := 106
const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const PORTRAIT_PATH := "res://scripts/world/practice/hatena_portrait.gd"
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
## スマホ：右上の「スキップ」ボタンの、画面の端からの余白。
const TOUCH_SKIP_MARGIN := Vector2(20.0, 16.0)
const INK := Color(0.10, 0.13, 0.20)
const ACCENT := Color("#ffd94a")
## まわりを暗くする色（少しだけ）
const DIM := Color(0.0, 0.03, 0.10, 0.55)
## 光る枠：部品から離す幅、枠の太さ、外へにじむ光の幅、角の丸み、脈打つ速さ（ラジアン/秒。約 0.5 秒で明るくなる）
const FRAME_PAD := 6.0
const FRAME_WIDTH := 4.0
const GLOW_WIDTH := 16.0
const FRAME_RADIUS := 14.0
const PULSE_SPEED := 3.2
const MAX_TARGETS := 8
## 暗い幕と光が出る・消える秒
const FADE_SECONDS := 0.22
## 吹き出し（台本①の 1.2 の長さ：0.8秒 ＋ 1文字 0.12秒、1.8〜4.0秒）
const SAY_BASE_SECONDS := 0.8
const SAY_SECONDS_PER_CHAR := 0.12
const SAY_MIN_SECONDS := 1.8
const SAY_MAX_SECONDS := 4.0
const BUBBLE_FONT_SIZE := 28
const BUBBLE_TAIL := Vector2(26.0, 18.0)
## 吹き出しを画面の端・光っている所から離す幅
const EDGE_MARGIN := 16.0
const AVOID_MARGIN := 10.0
## 吹き出しの付け根がないときに出す高さ（画面の上から）
const NO_ANCHOR_TOP := 96.0

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_size = vec2(1280.0, 720.0);
uniform int hole_count = 0;
uniform vec4 holes[8];
uniform float radius = 14.0;
uniform vec4 dim_color : source_color = vec4(0.0, 0.03, 0.1, 0.55);
uniform vec4 frame_color : source_color = vec4(1.0, 0.85, 0.29, 1.0);
uniform float frame_width = 4.0;
uniform float glow_width = 16.0;
uniform float pulse_speed = 3.2;
uniform float strength = 1.0;

// 角の丸い四角（r = x, y, 幅, 高さ）までの距離。中はマイナス
float round_box(vec2 p, vec4 r, float rad) {
	vec2 half_size = r.zw * 0.5;
	vec2 center = r.xy + half_size;
	float k = min(rad, min(half_size.x, half_size.y));
	vec2 q = abs(p - center) - half_size + vec2(k);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - k;
}

void fragment() {
	vec2 p = UV * view_size;
	float d = 100000.0;
	for (int i = 0; i < 8; i++) {
		if (i >= hole_count) {
			break;
		}
		d = min(d, round_box(p, holes[i], radius));
	}
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	// 光っている所の中は暗くしない
	vec4 col = vec4(dim_color.rgb, dim_color.a * smoothstep(0.0, 1.5, d));
	// 外へにじむ光（ゆっくり脈打つ）
	float glow = d > 0.0 ? exp(-d / (glow_width * (0.7 + 0.5 * pulse))) : 0.0;
	col = mix(col, vec4(frame_color.rgb, 1.0), glow * (0.3 + 0.4 * pulse));
	// 枠の線（部品の外側）。明るいときは白っぽく
	float line = 1.0 - smoothstep(frame_width * 0.5 - 0.8, frame_width * 0.5 + 0.8, abs(d - frame_width * 0.5));
	col = mix(col, vec4(mix(frame_color.rgb, vec3(1.0), 0.4 * pulse), 1.0), line);
	COLOR = vec4(col.rgb, col.a * strength);
}
"""

## true：Esc を exit_requested にしたあと、下の画面にも渡す（ポーズ画面なら Esc でそのままポーズが閉じる）。
## false（既定）：Esc は下の画面に渡さない（コーチを抜けたあとのことは呼んだ側が決める）。
var pass_escape := false
## ハテナの小窓を出す角（C の HatenaPortrait.slide_in に渡す）
var portrait_corner := &"bottom_right"
## 吹き出しを置く所を選ぶとき、小窓に重なる広さを、光っている所に重なる広さの何倍に数えるか。
## 0.5（既定）は、光っている所より小窓に重なるほうを選びやすい。光っている所が横に広い画面（⑤の設定パネル）では大きくして、
## 小窓のハテナの顔を隠さない
var portrait_avoid := 0.5

var _active := true
## false の間は、押せない仕組みを外す（暗い幕・光・吹き出しはそのまま。クリアカードのボタンを押せるように）
var _guard := true
var _targets: Array[Control] = []
## 光らせないが押せる部品（focus の also_clickable）
var _extra: Array[Control] = []
var _clickable := false
## 光っている部品の画面の四角（毎フレーム、部品の今の位置から作り直す）
var _holes: Array[Rect2] = []
var _strength := 0.0
var _strength_tween: Tween = null
var _anchor := Callable()
var _say: SayTicket = null

var _shade: ColorRect = null
var _shade_material: ShaderMaterial = null
var _blocker: Blocker = null
var _top: CanvasLayer = null
var _top_root: Control = null
var _bubble: PanelContainer = null
var _bubble_label: Label = null
var _bubble_tail: Polygon2D = null
var _bubble_tween: Tween = null
## いまの吹き出しの置き方（_bubble_spots の番号）。光っている所にかかるまで変えない
var _bubble_spot := -1
var _portrait: Control = null
var _portrait_on := false
## スマホ：Esc の代わりに案内を抜ける「スキップ」ボタン（exit_requested を受ける人がいるときだけ出す）。
var _touch_skip: Button = null


## 1つの吹き出し。出す時間が過ぎる（Enter・スペースでの早送り・次の吹き出し・hide_bubble・close）と done が来る。
class SayTicket extends RefCounted:
	signal done
	var text := ""
	var remaining := 0.0
	## 時間が過ぎても吹き出しを出したままにする（「押して みて」の段階。次の say か hide_bubble まで）
	var hold := false
	var finished := false


## 光っている所の外のマウスを止める、画面いっぱいの見えない板。光っている所（押せるとき）だけ下へ通す。
class Blocker extends Control:
	var holes: Array[Rect2] = []
	var pass_holes := false

	func _has_point(point: Vector2) -> bool:
		if pass_holes:
			for hole: Rect2 in holes:
				if hole.has_point(point):
					return false
		return true


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_shade = ColorRect.new()
	_shade.name = "CoachShade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color.WHITE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_shade_material = ShaderMaterial.new()
	_shade_material.shader = shader
	_shade_material.set_shader_parameter("dim_color", DIM)
	_shade_material.set_shader_parameter("frame_color", ACCENT)
	_shade_material.set_shader_parameter("frame_width", FRAME_WIDTH)
	_shade_material.set_shader_parameter("glow_width", GLOW_WIDTH)
	_shade_material.set_shader_parameter("radius", FRAME_RADIUS)
	_shade_material.set_shader_parameter("pulse_speed", PULSE_SPEED)
	_shade_material.set_shader_parameter("strength", 0.0)
	_shade.material = _shade_material
	_shade.visible = false
	add_child(_shade)
	_blocker = Blocker.new()
	_blocker.name = "CoachBlocker"
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.focus_mode = Control.FOCUS_NONE
	add_child(_blocker)
	_top = CanvasLayer.new()
	_top.name = "CoachTop"
	_top.layer = TOP_LAYER
	add_child(_top)
	_top_root = Control.new()
	_top_root.name = "CoachTopRoot"
	_top_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top.add_child(_top_root)
	_build_bubble()
	_build_touch_controls()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_apply_guard()


# ---------- 光らせる ----------

## targets（Control の配列。null は飛ばす）を光らせ（ゆっくり脈打つ枠）、まわりを少し暗くする。
## clickable なら targets だけ押せる（ほかは押せない）。grab_focus なら、光っている最初の押せる部品にキーボードの
## フォーカスを移す（Enter で押せる。「押して みて」の段階）。説明だけで押してもよい部品（学年の ◀ ▶ など）は
## grab_focus = false にすると、Enter・スペースは吹き出しの早送りのまま（矢印キーで部品へ移れば押せる）。
## clickable が false なら、どれも押せない（見せるだけ）。前の光は消える。止めていたコーチ（close 後）はまた始まる。
## also_clickable（clickable のときだけ）：光らせないが押せる部品（④の 4-5：光っているのはキャラ、色と帽子も選べる）。
func focus(targets: Array, clickable := true, grab_focus := true, also_clickable: Array = []) -> void:
	_activate()
	_targets.clear()
	for target: Variant in targets:
		if target is Control and is_instance_valid(target) and not _targets.has(target):
			_targets.append(target as Control)
		if _targets.size() >= MAX_TARGETS:
			break
	_extra.clear()
	if clickable:
		for extra: Variant in also_clickable:
			if extra is Control and is_instance_valid(extra) and not _targets.has(extra) and not _extra.has(extra):
				_extra.append(extra as Control)
	_clickable = clickable and not _targets.is_empty()
	_update_holes()
	_fade_shade(1.0 if not _targets.is_empty() else 0.0)
	_apply_guard()
	if _clickable and grab_focus:
		_focus_first_target.call_deferred()
	else:
		_release_focus()
	_bubble_spot = -1


## 光と暗い幕を消す。どれも押せない（コーチは続く。押せるようにするには close）。
func clear_focus() -> void:
	focus([], false)


## いま光らせている部品
func targets() -> Array[Control]:
	return _targets.duplicate()


func is_clickable() -> bool:
	return _clickable


## 光っている部品の画面の四角（枠の内側。テスト用）
func hole_rects() -> Array[Rect2]:
	return _holes.duplicate()


## point（画面の座標）をクリックしたとき、コーチが止めるか（テスト用）
func blocks_point(point: Vector2) -> bool:
	return _blocker.visible and _blocker.mouse_filter != Control.MOUSE_FILTER_IGNORE and _blocker._has_point(point)


func _update_holes() -> void:
	_holes.clear()
	for target: Control in _targets:
		if is_instance_valid(target) and target.is_visible_in_tree():
			_holes.append(_screen_rect(target).grow(FRAME_PAD))
	# マウスを下へ通す所：光っている所と、光らせないが押せる所（also_clickable）
	var passes: Array[Rect2] = _holes.duplicate()
	for extra: Control in _extra:
		if is_instance_valid(extra) and extra.is_visible_in_tree():
			passes.append(_screen_rect(extra))
	_blocker.holes = passes
	if _holes.is_empty():
		return  # 光が消えていく間は、前の光の穴のまま薄くする（画面全体が暗くならないように）
	var packed := PackedVector4Array()
	for i in range(MAX_TARGETS):
		var hole: Rect2 = _holes[i] if i < _holes.size() else Rect2()
		packed.append(Vector4(hole.position.x, hole.position.y, hole.size.x, hole.size.y))
	_shade_material.set_shader_parameter("holes", packed)
	_shade_material.set_shader_parameter("hole_count", _holes.size())
	_shade_material.set_shader_parameter("view_size", _shade.size)


## 部品の画面の四角（このコーチの層の座標。下の層もこの層も、ずらしていない前提）
static func _screen_rect(control: Control) -> Rect2:
	var xform := control.get_global_transform_with_canvas()
	return Rect2(xform.origin, control.size * xform.get_scale()).abs()


func _fade_shade(to: float) -> void:
	if _strength_tween != null:
		_strength_tween.kill()
	if to > 0.0:
		_shade.visible = true
	_strength_tween = create_tween()
	_strength_tween.tween_method(_set_strength, _strength, to, FADE_SECONDS)
	if to <= 0.0:
		_strength_tween.tween_callback(func() -> void:
			if _targets.is_empty():
				_shade.visible = false)


func _set_strength(value: float) -> void:
	_strength = value
	_shade_material.set_shader_parameter("strength", value)


# ---------- 押せない仕組み ----------

## false：押せない仕組みを外す（光・暗い幕・吹き出しはそのまま。Esc も見ない）。true で戻す。
func set_guard(on: bool) -> void:
	_guard = on
	_apply_guard()


func is_active() -> bool:
	return _active


func _activate() -> void:
	if _active:
		return
	_active = true
	_apply_guard()


func _guarding() -> bool:
	return _active and _guard


func _apply_guard() -> void:
	if _blocker == null:
		return
	var on := _guarding()
	_blocker.visible = on
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_blocker.pass_holes = _clickable
	_update_touch_skip()


## control は光っていて押せる部品（かその中。光らせないが押せる部品も）か
func _is_lit(control: Control) -> bool:
	if control == null or not _clickable:
		return false
	for target: Control in _targets + _extra:
		if is_instance_valid(target) and (target == control or target.is_ancestor_of(control)):
			return true
	return false


## 光っている部品の中で、最初にフォーカスを持てる部品（なければ null）
func _first_focusable() -> Control:
	for target: Control in _targets:
		if not is_instance_valid(target) or not target.is_visible_in_tree():
			continue
		var found := _focusable_in(target)
		if found != null:
			return found
	return null


static func _focusable_in(node: Control) -> Control:
	if node.focus_mode != Control.FOCUS_NONE and node.is_visible_in_tree() and not (node is BaseButton and (node as BaseButton).disabled):
		return node
	for child: Node in node.get_children():
		if child is Control:
			var found := _focusable_in(child as Control)
			if found != null:
				return found
	return null


func _focus_first_target() -> void:
	if not _guarding() or not _clickable:
		return
	if _is_lit(get_viewport().gui_get_focus_owner()):
		return
	var first := _first_focusable()
	if first != null:
		first.grab_focus()


func _release_focus() -> void:
	if not _guarding():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not _is_lit(owner):
		get_viewport().gui_release_focus()


## 光っていない部品にフォーカスが移ったら、光っている部品へ戻す（押せる部品がなければ外す）。
func _on_focus_changed(control: Control) -> void:
	if not _guarding() or _is_lit(control):
		return
	_restore_focus.call_deferred()


func _restore_focus() -> void:
	if not _guarding():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or _is_lit(owner):
		return
	var first := _first_focusable() if _clickable else null
	if first != null:
		first.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if not _guarding() or event.is_echo():
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return  # マウスは見えない板（Blocker）が止める
	if event.is_action_pressed(&"ui_cancel"):
		exit_requested.emit()
		if not pass_escape:
			get_viewport().set_input_as_handled()
		return
	var owner := get_viewport().gui_get_focus_owner()
	if _is_accept(event):
		if _is_lit(owner):
			return  # 光っているボタンは Enter・スペースで押せる
		if event.is_pressed():
			_fast_forward()
		get_viewport().set_input_as_handled()
		return
	var side := _navigation_side(event)
	if side == -2:
		return  # フォーカスを動かさないキーは、そのまま下へ（ゲームのキーなど）
	if not event.is_pressed():
		return
	if not _is_lit(owner):
		# 光っていない所にいる（どこにもいない）ときは、光っている部品へ連れていく
		get_viewport().set_input_as_handled()
		if _clickable:
			var first := _first_focusable()
			if first != null:
				first.grab_focus()
		return
	# スライダーは、その向きのキーで値を動かす
	if owner is HSlider and side in [SIDE_LEFT, SIDE_RIGHT]:
		return
	if owner is VSlider and side in [SIDE_TOP, SIDE_BOTTOM]:
		return
	var next: Control = null
	if side == -1:
		next = owner.find_prev_valid_focus() if event.is_action(&"ui_focus_prev") else owner.find_next_valid_focus()
	else:
		next = owner.find_valid_focus_neighbor(side)
	if next != null and not _is_lit(next):
		get_viewport().set_input_as_handled()


## Enter・スペース（と決定のボタン）か
static func _is_accept(event: InputEvent) -> bool:
	if event.is_action(&"ui_accept") or event.is_action(&"ui_select"):
		return true
	var key := event as InputEventKey
	return key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]


## フォーカスを動かすキーの向き（SIDE_*。Tab は -1、動かさないキーは -2）
static func _navigation_side(event: InputEvent) -> int:
	if event.is_action(&"ui_focus_next") or event.is_action(&"ui_focus_prev"):
		return -1
	if event.is_action(&"ui_left"):
		return SIDE_LEFT
	if event.is_action(&"ui_right"):
		return SIDE_RIGHT
	if event.is_action(&"ui_up"):
		return SIDE_TOP
	if event.is_action(&"ui_down"):
		return SIDE_BOTTOM
	return -2


# ---------- 吹き出し ----------

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "CoachBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.97)
	style.set_corner_radius_all(22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 9
	style.content_margin_bottom = 11
	style.shadow_color = Color(0.0, 0.03, 0.1, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble_label = Label.new()
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble_label.add_theme_font_override("font", FONT)
	_bubble_label.add_theme_font_size_override("font_size", MobileUi.font(BUBBLE_FONT_SIZE))
	_bubble_label.add_theme_color_override("font_color", INK)
	_bubble.add_child(_bubble_label)
	_bubble_tail = Polygon2D.new()
	_bubble_tail.color = Color(1, 1, 1, 0.97)
	_bubble_tail.polygon = PackedVector2Array([
		Vector2(-BUBBLE_TAIL.x * 0.5, 0.0), Vector2(BUBBLE_TAIL.x * 0.5, 0.0), Vector2(0.0, BUBBLE_TAIL.y)])
	_bubble.add_child(_bubble_tail)
	_bubble.visible = false
	_top_root.add_child(_bubble)


## ハテナから吹き出しを出す。text は PracticeTexts の ID（ID でなければ、そのままの文字）。
## seconds < 0 は台本①の 1.2 の長さ（0.8秒＋1文字0.12秒、1.8〜4.0秒）。返り値は、出す時間が過ぎたときの signal。
## hold = true（「押して みて」の段階）：時間が過ぎても吹き出しは次の say か hide_bubble まで残し、早送りもしない。
## hold = false（説明だけの段階）：時間が過ぎたら消える。Enter・スペースで早送りできる
## （光っている押せるボタンにフォーカスがあるときは、Enter・スペースはそのボタンが受ける）。
## 前の吹き出しを打ち切ると、それを待っていた流れは次のフレームで続く。止めていたコーチ（close 後）はまた始まる。
func say(text: String, seconds := -1.0, hold := false) -> Signal:
	_activate()
	if _say != null:
		var replaced := _say
		_say = null
		if not replaced.finished:
			replaced.finished = true
			_emit_done.call_deferred(replaced)
	var shown := _resolve_text(text)
	var ticket := SayTicket.new()
	ticket.text = shown
	ticket.remaining = seconds if seconds >= 0.0 else say_seconds(shown)
	ticket.hold = hold
	_say = ticket
	# 時間は _process で数え、ポーズ中も進むタイマーでも見張る（どちらか早いほうで終わる）
	if is_inside_tree():
		get_tree().create_timer(ticket.remaining, true).timeout.connect(_on_say_time.bind(ticket))
	_show_bubble(shown)
	_play_pop()
	said.emit(text)
	return ticket.done


## 吹き出しを出しておく秒数（台本①の 1.2）
static func say_seconds(text: String) -> float:
	return clampf(SAY_BASE_SECONDS + SAY_SECONDS_PER_CHAR * text.length(), SAY_MIN_SECONDS, SAY_MAX_SECONDS)


## いま出している吹き出しの文字（出していなければ ""）
func bubble_text() -> String:
	return _bubble_label.text if _bubble.visible else ""


## 吹き出しを消す（待っていた流れは続く）
func hide_bubble() -> void:
	if _say != null:
		var ticket := _say
		_say = null
		if not ticket.finished:
			ticket.finished = true
			_emit_done.call_deferred(ticket)
	if _bubble_tween != null:
		_bubble_tween.kill()
		_bubble_tween = null
	_bubble.visible = false
	_bubble_label.text = ""


## seconds 秒待つ（ポーズ中も進む）
func wait(seconds: float) -> Signal:
	return get_tree().create_timer(maxf(seconds, 0.0), true).timeout


## 吹き出しの付け根（画面の座標を返す Callable。Vector2.INF なら付け根なし）。
## 付け根がないときは、小窓が出ていれば小窓のハテナの頭の上、それもなければ画面の上の真ん中に出す。
func set_anchor(anchor: Callable) -> void:
	_anchor = anchor
	_bubble_spot = -1


func _resolve_text(text: String) -> String:
	if PracticeTexts.has_text(text):
		return PracticeTexts.get_text(text)
	return text


func _show_bubble(text: String) -> void:
	_bubble_label.text = text
	_bubble.reset_size()
	_bubble.visible = true
	_bubble_spot = -1
	_place_bubble()
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble.scale = Vector2(0.72, 0.72)
	_bubble.modulate.a = 0.0
	_bubble_tween = create_tween().set_parallel(true)
	_bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(_bubble, "modulate:a", 1.0, 0.1)


func _fast_forward() -> void:
	if _say == null or _say.hold or _say.finished:
		return
	_finish_say()


# ---------- スマホ（タッチ操作） ----------

## スマホだけ：吹き出し（と光っていない所）のタップで早送り、右上の「スキップ」で案内を抜ける。
func _build_touch_controls() -> void:
	if not MobileUi.is_touch_ui():
		return
	# 吹き出しをタップすると Enter・スペースと同じ早送り。光っていない所（見えない板）のタップも同じ。
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.gui_input.connect(_on_touch_tap)
	_blocker.gui_input.connect(_on_touch_tap)
	_touch_skip = TouchHud.make_button("スキップ ✕", 20)
	_touch_skip.name = "CoachSkipButton"
	_touch_skip.visible = false
	_touch_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_touch_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_touch_skip.pressed.connect(_on_touch_skip)
	_top_root.add_child(_touch_skip)
	TouchHud.on_safe_area_changed(_layout_touch_skip)
	_layout_touch_skip()


func _on_touch_tap(event: InputEvent) -> void:
	# タッチは マウスのクリックとしても届くので、クリックだけを見る（1回のタップで2つ進まないように）。
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_fast_forward()


## Esc（ui_cancel）と同じ。pass_escape のときは下の画面にも Esc を渡す（_input が exit_requested を出す）。
func _on_touch_skip() -> void:
	if not _guarding():
		return
	if pass_escape:
		TouchHud.tap_key(KEY_ESCAPE)
		return
	exit_requested.emit()


func _layout_touch_skip() -> void:
	if _touch_skip == null:
		return
	_touch_skip.offset_right = -TOUCH_SKIP_MARGIN.x - TouchHud.safe_right()
	_touch_skip.offset_left = _touch_skip.offset_right
	_touch_skip.offset_top = TOUCH_SKIP_MARGIN.y + TouchHud.safe_top()
	_touch_skip.offset_bottom = _touch_skip.offset_top


## 「スキップ」は、案内を抜ける先（exit_requested を受ける人）があって、コーチが止めている間だけ出す。
func _update_touch_skip() -> void:
	if _touch_skip == null:
		return
	_touch_skip.visible = _guarding() and not exit_requested.get_connections().is_empty()


## 時間が過ぎた：done を出す。hold でなければ吹き出しを消す。
func _finish_say() -> void:
	var ticket := _say
	if ticket == null or ticket.finished:
		return
	ticket.finished = true
	if not ticket.hold:
		_say = null
		_bubble.visible = false
		_bubble_label.text = ""
	ticket.done.emit()


func _emit_done(ticket: SayTicket) -> void:
	ticket.done.emit()


func _on_say_time(ticket: SayTicket) -> void:
	if ticket == _say and not ticket.finished:
		_finish_say()


func _anchor_point() -> Vector2:
	if _anchor.is_valid():
		var point: Variant = _anchor.call()
		if point is Vector2 and (point as Vector2).is_finite():
			return point
	if _portrait_on and _portrait != null and _portrait.visible:
		if _portrait.has_method("bubble_anchor"):
			var head: Variant = _portrait.call("bubble_anchor")
			if head is Vector2 and (head as Vector2).is_finite():
				return head
		var rect := _portrait.get_global_rect()
		return Vector2(rect.get_center().x, rect.position.y)
	return Vector2.INF


## 吹き出しの位置：しっぽの先をハテナの頭の上に合わせる。光っている所（と小窓）にかかるときは、横か下へずらす。
## 画面からはみ出す分は端で止める。
func _place_bubble() -> void:
	var view := _top_root.size
	var bubble_size := _bubble.get_combined_minimum_size()
	_bubble.size = bubble_size
	var anchor := _anchor_point()
	var has_anchor := anchor.is_finite()
	if not has_anchor:
		anchor = Vector2(view.x * 0.5, NO_ANCHOR_TOP + bubble_size.y + BUBBLE_TAIL.y)
	var avoid: Array[Rect2] = []
	for hole: Rect2 in _holes:
		avoid.append(hole.grow(AVOID_MARGIN + FRAME_WIDTH))
	var spots := _bubble_spots(anchor, bubble_size, view)
	var chosen := _bubble_spot
	if chosen < 0 or chosen >= spots.size() or _overlap(spots[chosen], bubble_size, avoid) > 0.0:
		chosen = 0
		var best := INF
		for i in range(spots.size()):
			var area := _overlap(spots[i], bubble_size, avoid)
			if area < best:
				best = area
				chosen = i
			if area <= 0.0:
				break
	_bubble_spot = chosen
	var pos: Vector2 = spots[chosen]
	_bubble.position = pos
	_bubble.pivot_offset = Vector2(bubble_size.x * 0.5, bubble_size.y)
	# しっぽは、吹き出しがハテナの頭より上にあるときだけ、ハテナのほうへ下向きに出す
	var above := pos.y + bubble_size.y <= anchor.y + 2.0
	_bubble_tail.visible = has_anchor and above
	_bubble_tail.position = Vector2(clampf(anchor.x - pos.x, 28.0, bubble_size.x - 28.0), bubble_size.y - 1.0)


## 吹き出しを置く候補（左上の位置）：頭の真上、左上、右上、左、右、下。どれも画面の端で止める。
func _bubble_spots(anchor: Vector2, bubble_size: Vector2, view: Vector2) -> Array[Vector2]:
	var up := anchor.y - bubble_size.y - BUBBLE_TAIL.y
	var raw: Array[Vector2] = [
		Vector2(anchor.x - bubble_size.x * 0.5, up),
		Vector2(anchor.x - bubble_size.x + 40.0, up),
		Vector2(anchor.x - 40.0, up),
		Vector2(anchor.x - bubble_size.x - 36.0, anchor.y - bubble_size.y * 0.5),
		Vector2(anchor.x + 36.0, anchor.y - bubble_size.y * 0.5),
		Vector2(anchor.x - bubble_size.x * 0.5, anchor.y + 40.0),
	]
	var spots: Array[Vector2] = []
	# スマホはカメラの穴と角丸（SafeArea）の内側で止める。デスクトップは 0。
	var touch := MobileUi.is_touch_ui()
	var min_x := EDGE_MARGIN + (TouchHud.safe_left() if touch else 0.0)
	var min_y := EDGE_MARGIN + (TouchHud.safe_top() if touch else 0.0)
	var max_x := view.x - bubble_size.x - EDGE_MARGIN - (TouchHud.safe_right() if touch else 0.0)
	var max_y := view.y - bubble_size.y - EDGE_MARGIN - (TouchHud.safe_bottom() if touch else 0.0)
	for pos: Vector2 in raw:
		pos.x = clampf(pos.x, min_x, maxf(min_x, max_x))
		pos.y = clampf(pos.y, min_y, maxf(min_y, max_y))
		spots.append(pos)
	return spots


func _overlap(pos: Vector2, bubble_size: Vector2, avoid: Array[Rect2]) -> float:
	var rect := Rect2(pos, bubble_size)
	var area := 0.0
	for other: Rect2 in avoid:
		var cut := rect.intersection(other)
		area += cut.get_area()
	if _portrait_on and _portrait != null and _portrait.visible:
		area += rect.intersection(_portrait.get_global_rect()).get_area() * portrait_avoid
	return area


func _play_pop() -> void:
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", &"practice_pop")  # 吹き出しの「ぽこっ」


# ---------- ハテナの小窓 ----------

## ハテナの小窓（担当 C の HatenaPortrait。scripts/world/practice/hatena_portrait.gd）を出す・しまう。
## 小窓のスクリプトがまだないときは何もしない（吹き出しは画面の上の真ん中に出る）。
func show_portrait(on: bool) -> void:
	_portrait_on = on
	if on:
		_activate()
		if _portrait == null:
			_portrait = _make_portrait()
		if _portrait == null:
			return
		_portrait.visible = true
		if _portrait.has_method("slide_in"):
			_portrait.call("slide_in", portrait_corner)
		return
	if _portrait == null or not _portrait.visible:
		return
	if _portrait.has_method("slide_out"):
		var out: Variant = _portrait.call("slide_out")
		if out is Signal:
			(out as Signal).connect(func() -> void:
				if not _portrait_on and is_instance_valid(_portrait):
					_portrait.visible = false, CONNECT_ONE_SHOT)
			return
	_portrait.visible = false


## ハテナの小窓（まだ出していない、または C の小窓がないときは null）
func portrait() -> Control:
	return _portrait


func _make_portrait() -> Control:
	if not ResourceLoader.exists(PORTRAIT_PATH):
		return null
	var script := load(PORTRAIT_PATH) as Script
	if script == null or not script.can_instantiate():
		return null
	var node: Object = script.new()
	if not (node is Control):
		if node is Node:
			(node as Node).free()
		return null
	var portrait_node := node as Control
	portrait_node.name = "HatenaPortrait"
	_top_root.add_child(portrait_node)
	if portrait_node.has_method("setup"):
		portrait_node.call("setup", _quality())
	_ignore_mouse(portrait_node)
	return portrait_node


static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse(child)


func _quality() -> String:
	var manager := get_node_or_null(^"/root/GameManager")
	return str(manager.get("graphics_quality")) if manager != null else "balanced"


# ---------- 終わり ----------

## コーチを終える：光・暗い幕・吹き出し・小窓を消し、押せない仕組みも外す（ノードは残る。消すのは呼んだ側）。
## このあと focus・say・show_portrait を呼ぶと、また始まる。
func close() -> void:
	_targets.clear()
	_extra.clear()
	_clickable = false
	_update_holes()
	_fade_shade(0.0)
	hide_bubble()
	show_portrait(false)
	_anchor = Callable()
	_active = false
	_apply_guard()


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	_update_touch_skip()
	if _say != null and not _say.finished:
		_say.remaining -= delta
		if _say.remaining <= 0.0:
			_finish_say()
	if _shade.visible or not _targets.is_empty():
		_update_holes()
	if _bubble.visible:
		_place_bubble()
