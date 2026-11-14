extends HSlider

## Codex の思考ゲージを意識した、壁速度設定用の描画付き HSlider。
## 値・入力・フォーカス処理は HSlider に任せ、見た目だけを独自描画する。

const CONTROL_HEIGHT: float = 44.0
const TRACK_HEIGHT: float = 30.0
const TRACK_RADIUS: float = TRACK_HEIGHT * 0.5
const KNOB_DIAMETER: float = 38.0
const KNOB_RADIUS: float = KNOB_DIAMETER * 0.5
const PARTICLE_COUNT: int = 8
const STAR_START_SPEED: float = 5.0
const DRAW_SAFE_MARGIN_X: float = 8.0

const TRACK_COLOR := Color(0.035, 0.047, 0.071, 0.96)
const TRACK_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.07)
const KNOB_BORDER_COLOR := Color(0.78, 0.81, 0.86, 1.0)
const KNOB_COLOR := Color(0.985, 0.985, 0.98, 1.0)

## 自動モードの見た目：バーは青一色になり、つまみのランプが明滅して、つまみから波紋が広がる。
const AUTO_FILL_COLOR := Color(0.24, 0.61, 0.88, 1.0)
const AUTO_FILL_BRIGHT_COLOR := Color(0.42, 0.76, 1.0, 1.0)
const AUTO_ACCENT_COLOR := Color(0.47, 0.78, 1.0, 1.0)
## 明滅ひとまわりの秒数。波紋もこの拍で出る（数字やボタンは auto_phase / auto_pulse で合わせる）。
const AUTO_PULSE_SEC: float = 1.8
const AUTO_RIPPLE_COUNT: int = 2
## 波紋がつまみの外へ広がる距離。
const AUTO_RIPPLE_REACH: float = 17.0
## 自動に戻した瞬間に 1 回だけ出る、大きな波紋。
const AUTO_BURST_SEC: float = 0.5
const AUTO_BURST_REACH: float = 34.0
## 自動と手動の見た目が入れ替わるのにかかる秒数。
const AUTO_BLEND_SEC: float = 0.22

## x 初期位相、y 正規化位置、横移動速度、明滅位相。
const PARTICLE_SEEDS: Array[Vector4] = [
	Vector4(0.04, -0.48, 0.036, 0.2),
	Vector4(0.17, 0.36, 0.052, 1.1),
	Vector4(0.31, -0.08, 0.044, 2.5),
	Vector4(0.43, 0.58, 0.061, 3.7),
	Vector4(0.56, -0.62, 0.049, 4.4),
	Vector4(0.68, 0.12, 0.068, 5.6),
	Vector4(0.81, -0.31, 0.040, 0.9),
	Vector4(0.93, 0.47, 0.057, 2.9),
]

var _track_style := StyleBoxFlat.new()
var _shadow_style := StyleBoxFlat.new()
var _fill_style := StyleBoxFlat.new()
var _knob_style := StyleBoxFlat.new()
var _invisible_grabber: GradientTexture2D
var _elapsed: float = 0.0
var _hovered: bool = false
var _dragging: bool = false
## 0 = 手動の見た目、1 = 自動の見た目。_process でなめらかに寄せる。
var _auto_blend: float = 0.0
## 自動に戻した瞬間の大きな波紋（1 → 0 へ減る。0 = 出ていない）。
var _auto_burst: float = 0.0

## 自動モードの見た目にする。値・入力は変えない（つまみを動かせば、呼び出し側が手動へ切り替える）。
var auto_mode: bool = false:
	set(value):
		var turned_on := value and not auto_mode
		auto_mode = value
		# まだ画面に出ていないときは、切り替えの動きを見せずにその見た目で始める。
		if _elapsed <= 0.0 or not is_visible_in_tree():
			_auto_blend = 1.0 if auto_mode else 0.0
		elif turned_on:
			_auto_burst = 1.0
		queue_redraw()


func _ready() -> void:
	custom_minimum_size.y = CONTROL_HEIGHT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_draw_styles()
	_hide_native_slider_visuals()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	drag_started.connect(_on_drag_started)
	drag_ended.connect(_on_drag_ended)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed = fmod(_elapsed + delta, 1000.0)
	_auto_blend = move_toward(_auto_blend, 1.0 if auto_mode else 0.0, delta / AUTO_BLEND_SEC)
	_auto_burst = move_toward(_auto_burst, 0.0, delta / AUTO_BURST_SEC)
	queue_redraw()


func _value_changed(_new_value: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var center_y := size.y * 0.5
	var track_rect := Rect2(
		DRAW_SAFE_MARGIN_X,
		center_y - TRACK_HEIGHT * 0.5,
		maxf(0.0, size.x - DRAW_SAFE_MARGIN_X * 2.0),
		TRACK_HEIGHT
	)
	var normalized_value := _value_ratio()
	var knob_x := (
		track_rect.position.x
		+ KNOB_RADIUS
		+ normalized_value * maxf(0.0, track_rect.size.x - KNOB_DIAMETER)
	)
	var fill_width := maxf(0.0, knob_x - track_rect.position.x)
	var fill_rect := Rect2(track_rect.position, Vector2(fill_width, TRACK_HEIGHT))
	var pulse := auto_pulse()
	var auto_color := AUTO_FILL_COLOR.lerp(AUTO_FILL_BRIGHT_COLOR, pulse)
	# バーそのものは明滅させない（光るのは、つまみのランプと波紋だけ）。
	var fill_color := _fill_color_for_value(value).lerp(AUTO_FILL_COLOR, _auto_blend)
	draw_set_transform(_current_shake_offset())

	# 奥行きを感じる控えめな影と、暗い未到達トラック。
	var shadow_rect := track_rect
	shadow_rect.position.y += 2.0
	draw_style_box(_shadow_style, shadow_rect)
	draw_style_box(_track_style, track_rect)

	# 数字ごとの速度色で塗り、上側にごく薄いハイライトを重ねる。
	if fill_rect.size.x > 0.0:
		_fill_style.bg_color = fill_color
		draw_style_box(_fill_style, fill_rect)
		var highlight_rect := Rect2(
			fill_rect.position + Vector2(2.0, 2.0),
			Vector2(maxf(0.0, fill_rect.size.x - 4.0), TRACK_HEIGHT * 0.38)
		)
		if highlight_rect.size.x > 0.0:
			var highlight_color := fill_color.lightened(0.42)
			highlight_color.a = 0.18
			draw_rect(highlight_rect, highlight_color, true)
		_draw_fill_particles(fill_rect, center_y)

	var knob_center := Vector2(knob_x, center_y)
	var active := _hovered or _dragging or has_focus()
	if active:
		draw_circle(knob_center, KNOB_RADIUS + 6.0, Color(fill_color, 0.18), true, -1.0, true)
		draw_arc(knob_center, KNOB_RADIUS + 4.0, 0.0, TAU, 96, Color(fill_color, 0.72), 1.25, true)

	# 白面・境界線・影を一体の高精細な丸角スタイルで描き、輪郭のずれを防ぐ。
	var knob_rect := Rect2(
		knob_center - Vector2(KNOB_RADIUS, KNOB_RADIUS),
		Vector2(KNOB_DIAMETER, KNOB_DIAMETER)
	)
	if _auto_blend > 0.0 or _auto_burst > 0.0:
		_draw_auto_ripples(knob_center)
	_knob_style.border_color = KNOB_BORDER_COLOR.lerp(AUTO_ACCENT_COLOR, _auto_blend)
	_knob_style.set_border_width_all(2 if _auto_blend >= 0.5 else 1)
	draw_style_box(_knob_style, knob_rect)
	draw_circle(knob_center + Vector2(-4.5, -5.0), KNOB_RADIUS * 0.38, Color(1.0, 1.0, 1.0, 0.22), true, -1.0, true)
	if _auto_blend > 0.0:
		# 自動モード：つまみの真ん中に、バーと同じ拍で光るランプ。
		draw_circle(
			knob_center, 6.5 + 2.0 * pulse, Color(AUTO_ACCENT_COLOR, 0.28 * _auto_blend), true, -1.0, true
		)
		draw_circle(knob_center, 4.5, Color(auto_color, _auto_blend), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _value_ratio() -> float:
	var span := max_value - min_value
	if is_zero_approx(span):
		return 0.0
	return clampf((value - min_value) / span, 0.0, 1.0)


func _fill_color_for_value(speed_value: float) -> Color:
	# 数字表示と同じ補間式にして、数値とバーの色を常に一致させる。
	var span := max_value - min_value
	var color_ratio := 0.0 if is_zero_approx(span) else (speed_value - min_value) / span
	return Color(0.3, 1.0, 0.5).lerp(Color(1.0, 0.3, 0.2), color_ratio)


## 自動モードの明滅の位相（0〜1 をくり返す）。時計から決めるので、ほかの部品も同じ拍で動かせる。
func auto_phase() -> float:
	return fposmod(float(Time.get_ticks_msec()) / 1000.0 / AUTO_PULSE_SEC, 1.0)


## 自動モードの明滅の強さ（0 = いちばん暗い、1 = いちばん明るい。位相 0.5 で最大）。
func auto_pulse() -> float:
	return 0.5 - 0.5 * cos(TAU * auto_phase())


## 自動モード：つまみから外へ広がって消える波紋。バーがいちばん明るい瞬間に 1 つめが出る。
func _draw_auto_ripples(knob_center: Vector2) -> void:
	var phase := auto_phase()
	for ripple_index: int in range(AUTO_RIPPLE_COUNT):
		var travel := fposmod(phase - 0.5 + float(ripple_index) / float(AUTO_RIPPLE_COUNT), 1.0)
		var reach := 1.0 - pow(1.0 - travel, 2.0)
		var alpha := 0.75 * pow(1.0 - travel, 1.6) * _auto_blend
		draw_arc(
			knob_center,
			KNOB_RADIUS + 1.0 + AUTO_RIPPLE_REACH * reach,
			0.0,
			TAU,
			64,
			Color(AUTO_ACCENT_COLOR, alpha),
			lerpf(2.6, 1.0, travel),
			true
		)
	if _auto_burst > 0.0:
		var burst_travel := 1.0 - _auto_burst
		var burst_radius := KNOB_RADIUS + 2.0 + AUTO_BURST_REACH * (1.0 - pow(1.0 - burst_travel, 3.0))
		draw_circle(knob_center, burst_radius, Color(AUTO_ACCENT_COLOR, 0.16 * _auto_burst), true, -1.0, true)
		draw_arc(
			knob_center,
			burst_radius,
			0.0,
			TAU,
			96,
			Color(AUTO_ACCENT_COLOR.lightened(0.3), 0.9 * _auto_burst),
			lerpf(4.0, 1.0, burst_travel),
			true
		)


func _draw_fill_particles(fill_rect: Rect2, center_y: float) -> void:
	var star_energy := clampf(
		(value - STAR_START_SPEED) / maxf(max_value - STAR_START_SPEED, 0.001),
		0.0,
		1.0
	)
	if star_energy <= 0.0:
		return

	var left_padding := TRACK_RADIUS * 0.58
	var right_padding := KNOB_RADIUS * 0.92
	var available_width := fill_rect.size.x - left_padding - right_padding
	if available_width < 12.0:
		return

	var active_count := clampi(ceili(star_energy * float(PARTICLE_COUNT)), 1, PARTICLE_COUNT)
	var speed_multiplier := lerpf(0.48, 3.35, star_energy)
	for index: int in range(active_count):
		var particle_seed := PARTICLE_SEEDS[index]
		var travel := fposmod(
			particle_seed.x + _elapsed * particle_seed.z * speed_multiplier,
			1.0
		)
		var px := fill_rect.position.x + left_padding + travel * available_width
		var py := center_y + particle_seed.y * TRACK_HEIGHT * 0.30
		py += sin(_elapsed * (1.1 + speed_multiplier * 0.34) + particle_seed.w) * 0.55
		var pulse := 0.5 + 0.5 * sin(_elapsed * (1.7 + speed_multiplier * 0.55) + particle_seed.w)
		var alpha := (0.28 + pulse * 0.62) * lerpf(0.42, 1.0, star_energy)
		var radius := 1.15 + float(index % 3) * 0.36
		var particle_color := Color(0.83, 0.93, 1.0, alpha)
		draw_circle(Vector2(px, py), radius * 2.3, Color(0.72, 0.88, 1.0, alpha * 0.11), true, -1.0, true)
		_draw_star(Vector2(px, py), radius, particle_color)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for point_index: int in range(8):
		var angle := -PI * 0.5 + float(point_index) * PI * 0.25
		var point_radius := radius if point_index % 2 == 0 else radius * 0.34
		points.append(center + Vector2.from_angle(angle) * point_radius)
	draw_colored_polygon(points, color)


func _current_shake_offset() -> Vector2:
	var reached_maximum := value >= max_value - maxf(step * 0.5, 0.001)
	if not reached_maximum:
		return Vector2.ZERO
	# 最大値の間だけ、入力判定位置は動かさず高速で細かく揺らし続ける。
	var raw_offset := Vector2(
		sin(_elapsed * 105.0) * 1.2 + sin(_elapsed * 173.0) * 0.35,
		cos(_elapsed * 137.0) * 0.55
	)
	return Vector2(snappedf(raw_offset.x, 0.25), snappedf(raw_offset.y, 0.25))


func _build_draw_styles() -> void:
	_track_style.bg_color = TRACK_COLOR
	_track_style.border_color = TRACK_BORDER_COLOR
	_track_style.set_border_width_all(1)
	_track_style.set_corner_radius_all(int(TRACK_RADIUS))
	_shadow_style.bg_color = Color(0.0, 0.0, 0.0, 0.28)
	_shadow_style.set_corner_radius_all(int(TRACK_RADIUS))

	_fill_style.bg_color = _fill_color_for_value(value)
	_fill_style.set_corner_radius_all(int(TRACK_RADIUS))

	_knob_style.bg_color = KNOB_COLOR
	_knob_style.border_color = KNOB_BORDER_COLOR
	_knob_style.set_border_width_all(1)
	_knob_style.set_corner_radius_all(int(KNOB_RADIUS))
	_knob_style.corner_detail = 16
	_knob_style.anti_aliasing = true
	_knob_style.anti_aliasing_size = 0.8
	_knob_style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	_knob_style.shadow_size = 2
	_knob_style.shadow_offset = Vector2(0.0, 1.0)


func _hide_native_slider_visuals() -> void:
	add_theme_stylebox_override(&"slider", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"grabber_area", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"grabber_area_highlight", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

	var transparent_gradient := Gradient.new()
	transparent_gradient.set_color(0, Color.TRANSPARENT)
	transparent_gradient.set_color(1, Color.TRANSPARENT)
	_invisible_grabber = GradientTexture2D.new()
	_invisible_grabber.width = int(KNOB_DIAMETER)
	_invisible_grabber.height = int(KNOB_DIAMETER)
	_invisible_grabber.gradient = transparent_gradient
	for icon_name: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		add_theme_icon_override(icon_name, _invisible_grabber)


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _on_drag_started() -> void:
	_dragging = true
	queue_redraw()


func _on_drag_ended(_did_change: bool) -> void:
	_dragging = false
	queue_redraw()
