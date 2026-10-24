class_name SuddenDeathCloudCover
extends CanvasLayer

## 雲の覆い（docs/sudden_death_v2/common.md 5.3節）。地上・空のセット・種目の舞台を切り替える画面推移。
## 0.8秒で、雲の模様が画面の外から覆って真っ白になり（0.30〜0.50秒は真っ白）、晴れる。
## 監督が play() で始め、真っ白の間に一度だけ swap が呼ばれる（そこで舞台を切り替える）。
## 時計は監督が advance() で進める（テストのフレーム時間と実時間のどちらでも同じ動き）。
## play_black() は暗転（黒へ落として戻す）：水上機が雲の層に入りきったところで、場所を替えるのを場面の切り替わりとして見せる
## （c130_float.md 12 章。真っ黒の間に一度だけ swap が呼ばれる）。

const SHADER := preload("res://shaders/sudden_death/cloud_cover.gdshader")
const DURATION := 0.8
const FULL_FROM := 0.30
const FULL_TO := 0.50
## 真っ白の間の切り替えの時刻。
const SWAP_AT := 0.40

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _time := -1.0
var _travel := 0.0
var _swap: Callable
var _swapped := false
## 暗転（play_black）：黒の板と時刻、[暗くなる, 黒のまま, 明ける] の秒
var _black: ColorRect = null
var _black_time := -1.0
var _black_spec := Vector3(0.45, 0.35, 0.75)


func _ready() -> void:
	layer = 6
	_rect = ColorRect.new()
	_rect.name = "CloudCover"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_black = ColorRect.new()
	_black.name = "Blackout"
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.visible = false
	add_child(_black)
	_apply(0.0)


func is_playing() -> bool:
	return _time >= 0.0 or _black_time >= 0.0


## 暗転：fade_out 秒で黒へ落とし、真っ黒の真ん中で swap を呼び、hold 秒のあと fade_in 秒で明ける。
## 黒へ落ちていく間も、呼ぶ側の場面はそのまま動いている。whoosh = false なら雲を抜ける風を鳴らさない（雲の中でない暗転）。
func play_black(swap: Callable, fade_out := 0.45, hold := 0.35, fade_in := 0.75, whoosh := true) -> void:
	_black_time = 0.0
	_black_spec = Vector3(maxf(fade_out, 0.01), maxf(hold, 0.0), maxf(fade_in, 0.01))
	_swap = swap
	_swapped = false
	_apply_black(0.0)
	# 雲を抜ける風（いちばん強い所が 0.5 秒あたり：真っ黒の間）
	if whoosh:
		AudioManager.play_sfx(&"sd_cloud_whoosh")


## 暗転の時刻 time（秒）の黒さ（0..1）。
func black_amount(time: float) -> float:
	var a := _black_spec.x
	var b := a + _black_spec.y
	var c := b + _black_spec.z
	if time <= 0.0 or time >= c:
		return 0.0
	if time < a:
		return smoothstep(0.0, a, time)
	if time <= b:
		return 1.0
	return 1.0 - smoothstep(b, c, time)


func _apply_black(value: float) -> void:
	if _black == null:
		return
	_black.visible = value > 0.001
	_black.color = Color(0.0, 0.0, 0.0, clampf(value, 0.0, 1.0))


## 覆い始める。swap は真っ白の間に一度だけ呼ばれる。
func play(swap: Callable) -> void:
	_time = 0.0
	_travel = 0.0
	_swap = swap
	_swapped = false
	_apply(0.0)
	# 雲を抜ける風（いちばん強い所が 0.5 秒あたり：真っ白の間）
	AudioManager.play_sfx(&"sd_cloud_whoosh")


## 監督が毎フレーム呼ぶ。
func advance(delta: float) -> void:
	if _black_time >= 0.0:
		_black_time += maxf(0.0, delta)
		if not _swapped and _black_time >= _black_spec.x + _black_spec.y * 0.5:
			_swapped = true
			if _swap.is_valid():
				_swap.call()
		if _black_time >= _black_spec.x + _black_spec.y + _black_spec.z:
			_black_time = -1.0
			_apply_black(0.0)
			return
		_apply_black(black_amount(_black_time))
		return
	if _time < 0.0:
		return
	_time += maxf(0.0, delta)
	_travel += maxf(0.0, delta) * 1.8
	if not _swapped and _time >= SWAP_AT:
		_swapped = true
		if _swap.is_valid():
			_swap.call()
	if _time >= DURATION:
		_time = -1.0
		_apply(0.0)
		return
	_apply(coverage(_time))


## 時刻（秒）の覆いの量（0..1）。
static func coverage(time: float) -> float:
	if time <= 0.0 or time >= DURATION:
		return 0.0
	if time < FULL_FROM:
		return smoothstep(0.0, FULL_FROM, time)
	if time <= FULL_TO:
		return 1.0
	return 1.0 - smoothstep(FULL_TO, DURATION, time)


func _apply(value: float) -> void:
	if _rect == null:
		return
	_rect.visible = value > 0.001
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	_material.set_shader_parameter("amount", value)
	_material.set_shader_parameter("travel", _travel)
	_material.set_shader_parameter("aspect", Vector2(size.x / maxf(size.y, 1.0), 1.0))
