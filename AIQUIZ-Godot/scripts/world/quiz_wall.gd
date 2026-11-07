extends Node3D

## クイズの壁 + ドア (2個 or 4個)
## Python版 renderer.py の _draw_wall_doors + _draw_labels に相当

var wall_parts: Array[MeshInstance3D] = []
var doors: Array[MeshInstance3D] = []
var door_labels: Array[Label3D] = []
## door_labels と同じ並びの扉の半幅と、全扉共通の2P拡大の倍率上限。
var _door_label_half_widths: Array[float] = []
## door_labels と同じ並びの改行を入れる前の選択肢 (表示文字列には文節の切れ目で改行を入れる)。
var _door_label_texts: Array[String] = []
var _door_label_max_scale: float = 1.0

var is_boss: bool = false
var boss_label: Label3D = null
var boss_sparks: Array[CPUParticles3D] = []

var gameplay_question_label: Label3D = null
var _gameplay_question_panel: MeshInstance3D = null
var _gameplay_question_border: MeshInstance3D = null
var _gameplay_question_text: String = ""
## 背景パネル付きラベル原点から、パネル下端を扉上へ揃えるための局所オフセット。
var _gameplay_question_anchor_offset: float = 0.0
## 問題文・選択肢の現在の拡大率 (等倍と TEXT_ENLARGED_SCALE の間を短く遷移する)。
var _text_scale: float = 1.0
## 2Pでカメラが離れて拡大表示中か。
var _text_enlarged: bool = false
var _text_scale_tween: Tween = null
var _scaled_beam_mesh: BoxMesh = null
## 文字拡大でボス見出しが押し上げられた量 (等倍レイアウトの枠取り用)。
var _boss_scale_lift: float = 0.0
var _shattered: bool = false
var _saw_collision_shapes: Dictionary = {}
## false にすると、のこぎりで飛んだ体用の当たり（SawBodyCollision）を新しく作らない。
## GameWorld がのこぎりの追跡のない試合（1P など）で切る。メニューのプレビューなどでは従来どおり作る。
var saw_collision_enabled: bool = true
## 壁・扉を作り直したあと、消えた部品の当たりの記録を次の物理フレームで片づける。
var _saw_collision_dirty: bool = false
## _ready で組む扉の数。GameWorld は add_child の前に入れ、2択で組んでから4択に作り直さないようにする。
var initial_num_choices: int = 2
## 前回 set_quiz に渡された問題と選択肢（同じなら選択肢の整形と比較を毎フレームやり直さない）。
var _set_quiz_item: QuizItem = null
var _set_quiz_choices: PackedStringArray = PackedStringArray()
## 問題文と選択肢を AI が書いているように出す演出（docs/ai_question_typing.md）。壁ごとに 1 回だけ。
var _ai_text_reveal: WallAiTextReveal = null
var _ai_text_reveal_started: bool = false

func _physics_process(_dt: float) -> void:
	# Only saw-launched bodies opt into this layer. Match each visible solid so
	# broken doors stay open and retired walls never leave an invisible barrier.
	if not saw_collision_enabled and _saw_collision_shapes.is_empty():
		return
	for mesh: MeshInstance3D in wall_parts:
		_sync_saw_collision(mesh)
	for mesh: MeshInstance3D in doors:
		_sync_saw_collision(mesh)
	if _saw_collision_dirty:
		_saw_collision_dirty = false
		for id: int in _saw_collision_shapes.keys():
			if not is_instance_valid(_saw_collision_shapes[id]):
				_saw_collision_shapes.erase(id)


func _sync_saw_collision(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh) or mesh.is_queued_for_deletion():
		return
	var mesh_id := mesh.get_instance_id()
	var bounds := mesh.get_aabb()
	if not _saw_collision_shapes.has(mesh_id):
		if not saw_collision_enabled:
			return
		var body := AnimatableBody3D.new()
		body.name = "SawBodyCollision"
		body.collision_layer = SawChaseState.WALL_COLLISION_LAYER
		body.collision_mask = 0
		body.sync_to_physics = false
		mesh.add_child(body)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bounds.size
		collision.shape = box
		collision.position = bounds.get_center()
		body.add_child(collision)
		_saw_collision_shapes[mesh_id] = collision
	var shape: CollisionShape3D = _saw_collision_shapes[mesh_id]
	var box_shape := shape.shape as BoxShape3D
	if box_shape.size != bounds.size:
		box_shape.size = bounds.size
	var disabled := not mesh.is_visible_in_tree() or _retiring_after_pass or _shattered
	if shape.disabled != disabled:
		shape.disabled = disabled



# Door colors
const DOOR_COLORS_2 := [
	Color(0.10, 0.60, 0.95),  # Left - Blue
	Color(0.90, 0.15, 0.10),  # Right - Red
]
## 3択はマイルストーン1のサドンデスの水門列用に足したもの（いまの水門列は FloodgateRow で、これは使っていない）。
const DOOR_COLORS_3 := [
	Color(0.10, 0.55, 0.95),  # A - Blue
	Color(0.15, 0.75, 0.30),  # B - Green
	Color(0.90, 0.15, 0.15),  # C - Red
]
const DOOR_COLORS_4 := [
	Color(0.10, 0.55, 0.95),  # A - Blue
	Color(0.15, 0.75, 0.30),  # B - Green
	Color(0.95, 0.60, 0.10),  # C - Orange
	Color(0.90, 0.15, 0.15),  # D - Red
]
const WALL_COLOR := Color(0.50, 0.50, 0.50)
const BOSS_WALL_COLOR := Color(0.65, 0.15, 0.15)
## 壁・扉の塗装鋼板パネル材質（albedo_color は上の色のまま。テクスチャはそれに掛ける変調）。
const WallMaterials = preload("res://scripts/world/wall_materials.gd")
## 問題文の背景パネルと縁（UNSHADED・霧なし）。スタジアムの看板（GOAL ボード）と同じ紺地に明るい鋼色の縁。
## 白文字との明暗差を灰色の地より大きく取り、パネル割りの鋼板の壁の上でも看板として浮いて見えるようにする。
const QUESTION_PANEL_COLOR := Color(0.090, 0.170, 0.360)
const QUESTION_BORDER_COLOR := Color(0.72, 0.75, 0.80)
const JAPANESE_FONT: Font = preload("res://resources/fonts/NotoSansJP-Regular.otf")
## 問題文の実寸に合わせ、上端に小さな余白だけ残す。
var wall_top_y: float = 4.05
const QUESTION_TOP_MARGIN: float = 0.180
const DOOR_TOP_Y: float = 2.38
const QUESTION_DOOR_GAP: float = 0.18
## 2P拡大表示時の問題文・選択肢の倍率。
## 長い問題文が壁幅に収まる大きさに抑える。選択肢は扉ごとの内枠に収まる倍率までしか拡大しない。
const TEXT_ENLARGED_SCALE: float = 1.5
## 選択肢の文字を収める扉の内枠 (扉の幅・床から上に見えている高さに対する比率)。遠くの壁でも読めるよう扉いっぱいに大きく出す。
const CHOICE_FIT_WIDTH_RATIO: float = 0.82
const CHOICE_FIT_HEIGHT_RATIO: float = 0.82
## 改行なしでこの文字サイズ以上に出せる選択肢は1行のまま表示し、届かない長い選択肢だけ折り返して大きくする。
const CHOICE_SINGLE_LINE_MIN_FONT_SIZE: int = 56
## 文字サイズを揃えるとき、長い選択肢に合わせてほかの選択肢をこれより小さくはしない。
const CHOICE_UNIFORM_MIN_FONT_SIZE: int = 56
## 選択肢の文字サイズの範囲。上限は1文字約1m角、下限は従来の4択 (48px × 0.006) と同じ大きさ。
const CHOICE_FONT_SIZE_MIN: int = 36
const CHOICE_FONT_SIZE_MAX: int = 120
const CHOICE_PIXEL_SIZE: float = 0.008
## 扉の下部は床 (StageConstants.FLOOR_TOP_Y) に埋まっているので、選択肢は床から上に見えている部分の中央に置く。
## (扉の中心に置くと、4〜5行の選択肢の最終行が床に隠れる。)
const CHOICE_CENTER_Y: float = (DOOR_TOP_Y + StageConstants.FLOOR_TOP_Y) * 0.5
const CHOICE_VISIBLE_DOOR_HEIGHT: float = DOOR_TOP_Y - StageConstants.FLOOR_TOP_Y
## 壁の文字はMSDFで描き、遠景での縮小や2P拡大でも輪郭をにじませない。
## MSDFは文字サイズに関係なく1字1回だけ生成されるので、選択肢ごとに文字サイズが変わっても再ラスタライズしない。
## UIと共有する元フォントの取り込み設定は変えず、壁用に別の FontFile を作る。
const WALL_FONT_MSDF_SIZE: int = 64
const WALL_FONT_MSDF_PIXEL_RANGE: int = 16
static var _wall_font: FontFile = null
## 選択肢・問題文の組版結果（文字列ごと）。壁の切り替えのフレームで組み直さないよう全壁で共有し、上限を超えたら捨てる。
const TEXT_LAYOUT_CACHE_LIMIT := 4096
static var _choice_layout_cache: Dictionary = {}
static var _choice_measure_cache: Dictionary = {}
static var _question_width_cache: Dictionary = {}
## 新しい字の MSDF は初めて組むときにメインスレッドで作られる（漢字1字で数ミリ秒）。
## 壁の切り替えのフレームに重ならないよう、これから出す字を少しずつ先に描いておく（prime_queued_wall_glyphs）。
## urgent はこれから出す問題文・選択肢の字、もう一方は試合前にまとめて描くかな・英数字。
## _glyph_prime_seen は字 → 描いたか urgent に並べたなら true、試合前の待ち行列でまだ描いていなければ false。
static var _glyph_prime_seen: Dictionary = {}
static var _glyph_prime_urgent: PackedInt32Array = PackedInt32Array()
static var _glyph_prime_urgent_cursor: int = 0
static var _glyph_prime_queue: PackedInt32Array = PackedInt32Array()
static var _glyph_prime_queue_cursor: int = 0
## 描いた字が載ったアトラスのページ（ページ番号 → そのページの字）。GPU へ送るまで覚えておく。
static var _glyph_prime_pages: Dictionary = {}
## 試合前に描いておく字の範囲（英数字・記号、ひらがな、カタカナ・長音、全角の記号と数字）と、そのほかの字。
const WALL_GLYPH_PRIME_RANGES: Array[Vector2i] = [
	Vector2i(0x21, 0x7E),
	Vector2i(0x3041, 0x3096),
	Vector2i(0x30A1, 0x30FC),
	Vector2i(0xFF01, 0xFF1F),
]
const WALL_GLYPH_PRIME_EXTRA := "、。「」『』（）〜～…×÷±≠○△□℃→⁄─⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉"
## 等倍⇔拡大表示の切り替えにかける時間 (秒)。
const TEXT_SCALE_SWITCH_DURATION: float = 0.5

# Door positions from tuning
const LEFT_DOOR_X: float = 3.5
const RIGHT_DOOR_X: float = -3.5
const DOOR4_XS: Array[float] = [-5.8, -1.95, 1.95, 5.8]
const DOOR3_XS: Array[float] = [-6.2, 0.0, 6.2]
const DOOR3_HALF_WIDTH: float = 1.6

## 壁の横幅は線路に掛からないよう StageConstants.QUIZ_WALL_HALF_WIDTH で決める。
## 壁の延長線上（壁端より外）は、いまの問題の壁だけワールドボーダー（WallWorldBorder）で塞ぐ。
var _world_border: WallWorldBorder = null

var _current_num_choices: int = 2
var _retiring_after_pass: bool = false
var _retirement_finished: bool = false

## 同じサイズ・色の箱はRIDを再利用し、枚ごとのGPUアップロードを避ける。
static var _box_mesh_cache: Dictionary = {}
static var _opaque_material_cache: Dictionary = {}
## 問題文の高さで梁の大きさは問題ごとに変わるので、エンドレスで増え続けないよう上限を超えたら作り直す
## （使用中の壁は自分のメッシュを持ち続ける）。
const BOX_MESH_CACHE_LIMIT := 512
## 通過後のフェードの出発点になる、共有の不透明材質ごとの半透明版（色はそのまま）。
## これを持ち続けると半透明のシェーダーが解放されず、壁を抜けるたびにパイプラインを作り直さない。
static var _fade_material_cache: Dictionary = {}
## 問題文の背景パネルと縁は全壁で1枚の板と色ごとの材質を共有する（大きさはノードの拡大で合わせる）。
static var _question_panel_materials: Dictionary = {}
static var _question_panel_quad: QuadMesh = null
static var _boss_spark_mesh: QuadMesh = null
## 扉・壁の破片は大きさ・色ごとに箱・当たり・材質を共有する。破片ごとに作ると転送が増え、
## 破片が消えるたびに材質のシェーダーが解放されて次の正解で作り直しになる。
## 大きさと白への寄せ具合の乱数は DEBRIS_VARIATION_STEPS 段に丸めて共有できるようにする。
const DEBRIS_VARIATION_STEPS := 8
const DEBRIS_CACHE_LIMIT := 256
static var _debris_shape_cache: Dictionary = {}
static var _debris_material_cache: Dictionary = {}

func _ready() -> void:
	wall_top_y = _minimum_wall_top_y()
	_build_doors(initial_num_choices)



func _build_wall_around_doors(num_choices: int) -> void:
	# Clear existing wall parts
	for part in wall_parts:
		if is_instance_valid(part):
			part.queue_free()
	wall_parts.clear()
	_saw_collision_dirty = true

	# Wall dimensions (matching original single box)
	var total_width: float = StageConstants.QUIZ_WALL_HALF_WIDTH * 2.0
	var min_x: float = -total_width * 0.5
	var max_x: float = total_width * 0.5
	var door_top_y := DOOR_TOP_Y
	var door_bottom_y := -2.02
	var wall_bottom_y := -3.15
	var wall_color := BOSS_WALL_COLOR if is_boss else WALL_COLOR

	# 1. Top beam
	var top_height := wall_top_y - door_top_y
	var top_beam := _create_box(Vector3(total_width / 2.0, top_height / 2.0, 0.55), wall_color)
	top_beam.position = Vector3(0, door_top_y + top_height / 2.0, 0)
	add_child(top_beam)
	wall_parts.append(top_beam)

	# 2. Bottom beam
	var bottom_height := door_bottom_y - wall_bottom_y
	var bottom_beam := _create_box(Vector3(total_width / 2.0, bottom_height / 2.0, 0.55), wall_color)
	bottom_beam.position = Vector3(0, wall_bottom_y + bottom_height / 2.0, 0)
	add_child(bottom_beam)
	wall_parts.append(bottom_beam)

	# 3. Pillars
	var pillar_height := door_top_y - door_bottom_y
	var pillar_y := door_bottom_y + pillar_height / 2.0

	var door_xs: Array[float] = []
	var door_half_widths: Array[float] = []
	if num_choices == 4:
		door_xs = DOOR4_XS
		door_half_widths = [1.45, 1.45, 1.45, 1.45]
	elif num_choices == 3:
		door_xs = DOOR3_XS
		door_half_widths = [DOOR3_HALF_WIDTH, DOOR3_HALF_WIDTH, DOOR3_HALF_WIDTH]
	else:
		door_xs = [RIGHT_DOOR_X, LEFT_DOOR_X] # Sorted by X (-3.5, 3.5)
		door_half_widths = [1.8, 1.8]

	var current_x := min_x
	for i in range(door_xs.size()):
		var dx := door_xs[i]
		var dhw := door_half_widths[i]
		var door_left := dx - dhw
		var door_right := dx + dhw
		
		var pillar_width := door_left - current_x
		if pillar_width > 0:
			var pillar := _create_box(Vector3(pillar_width / 2.0, pillar_height / 2.0, 0.55), wall_color)
			pillar.position = Vector3(current_x + pillar_width / 2.0, pillar_y, 0)
			add_child(pillar)
			wall_parts.append(pillar)
		
		current_x = door_right
	
	var final_width := max_x - current_x
	if final_width > 0:
		var pillar := _create_box(Vector3(final_width / 2.0, pillar_height / 2.0, 0.55), wall_color)
		pillar.position = Vector3(current_x + final_width / 2.0, pillar_y, 0)
		add_child(pillar)
		wall_parts.append(pillar)

func _build_doors(num_choices: int) -> void:
	_current_num_choices = num_choices
	_build_wall_around_doors(num_choices)
	
	_finish_ai_text_reveal()
	# Clear existing doors
	for d: MeshInstance3D in doors:
		d.queue_free()
	doors.clear()
	_saw_collision_dirty = true
	for l: Label3D in door_labels:
		l.queue_free()
	door_labels.clear()

	_door_label_half_widths.clear()
	_door_label_texts.clear()
	_door_label_max_scale = 1.0

	if num_choices == 4:
		for i: int in range(4):
			var door := _create_box(Vector3(1.45, 2.2, 0.60), DOOR_COLORS_4[i], i)
			door.position = Vector3(DOOR4_XS[i], 0.18, 0)
			add_child(door)
			doors.append(door)
			_add_door_label(DOOR4_XS[i], 1.45)
	elif num_choices == 3:
		for i: int in range(3):
			var door := _create_box(Vector3(DOOR3_HALF_WIDTH, 2.2, 0.60), DOOR_COLORS_3[i], i)
			door.position = Vector3(DOOR3_XS[i], 0.18, 0)
			add_child(door)
			doors.append(door)
			_add_door_label(DOOR3_XS[i], DOOR3_HALF_WIDTH)
	else:
		# Left door (Blue)
		var left_door := _create_box(Vector3(1.8, 2.2, 0.60), DOOR_COLORS_2[0], 0)
		left_door.position = Vector3(LEFT_DOOR_X, 0.18, 0)
		add_child(left_door)
		doors.append(left_door)
		_add_door_label(LEFT_DOOR_X, 1.8)

		# Right door (Red)
		var right_door := _create_box(Vector3(1.8, 2.2, 0.60), DOOR_COLORS_2[1], 1)
		right_door.position = Vector3(RIGHT_DOOR_X, 0.18, 0)
		add_child(right_door)
		doors.append(right_door)
		_add_door_label(RIGHT_DOOR_X, 1.8)


func _add_door_label(door_x: float, door_half_width: float) -> void:
	var label := _create_label()
	label.position = Vector3(door_x, CHOICE_CENTER_Y, -0.65)
	label.pixel_size = CHOICE_PIXEL_SIZE
	label.width = door_half_width * 2.0 * CHOICE_FIT_WIDTH_RATIO / CHOICE_PIXEL_SIZE
	label.scale = Vector3.ONE * minf(_text_scale, _door_label_max_scale)
	add_child(label)
	door_labels.append(label)
	_door_label_half_widths.append(door_half_width)
	_door_label_texts.append("")


## 変わっていなければ何もしない (GameWorld は現在の壁へ毎フレーム set_quiz を呼ぶ)。
func _set_door_label_text(index: int, text: String) -> bool:
	if index >= door_labels.size() or _door_label_texts[index] == text:
		return false
	_door_label_texts[index] = text
	door_labels[index].text = text
	return true


## 選択肢の文字サイズは壁の中でなるべく揃える。各扉の内枠に収まる最大サイズのうち最小のものを全扉で使い、
## ただし極端に長い選択肢がほかを CHOICE_UNIFORM_MIN_FONT_SIZE より小さくすることはさせない
## (その長い選択肢だけが自分の枠に収まるサイズまで小さくなる)。
func _fit_door_labels() -> void:
	var boxes: Array[Vector2] = []
	for i: int in range(door_labels.size()):
		boxes.append(_door_label_box(i))
	var font: Font = door_labels[0].font if not door_labels.is_empty() else _wall_label_font()
	var fitted := _fit_choice_texts(_door_label_texts, boxes, font)
	var laid_texts: Array = fitted["texts"]
	var font_sizes: Array = fitted["font_sizes"]
	for i: int in range(door_labels.size()):
		door_labels[i].text = laid_texts[i]
		_set_choice_font_size(door_labels[i], font_sizes[i])
	_door_label_max_scale = fitted["max_scale"]
	_apply_door_label_scale()


## _fit_door_labels の計算部分: 扉ごとの表示文字列・文字サイズと、2P拡大の倍率上限を返す。
## 壁を持たずに呼べるので、GameWorld は次の問題の組版を先に済ませておける (prepare_wall_text_layout)。
static func _fit_choice_texts(texts: Array[String], boxes: Array[Vector2], font: Font) -> Dictionary:
	var fits: Array[int] = []
	var shared := CHOICE_FONT_SIZE_MAX
	for i: int in range(texts.size()):
		var text := texts[i]
		var fit := CHOICE_FONT_SIZE_MIN if text.is_empty() else int(_layout_choice(text, font, boxes[i], CHOICE_FONT_SIZE_MAX).font_size)
		fits.append(fit)
		if not text.is_empty():
			shared = mini(shared, maxi(fit, CHOICE_UNIFORM_MIN_FONT_SIZE))
	# 2P拡大も全扉で同じ倍率にし、どの選択肢も自分の枠からはみ出さない倍率までに抑える。
	var max_scale := TEXT_ENLARGED_SCALE
	var laid_texts: Array[String] = []
	var font_sizes: Array[int] = []
	for i: int in range(texts.size()):
		var text := texts[i]
		if text.is_empty():
			laid_texts.append("")
			font_sizes.append(mini(shared, fits[i]))
			continue
		# 揃えたサイズで改行位置を選び直す (小さくなったぶん1行に収まることがある)。
		var box := boxes[i]
		var laid := _layout_choice(text, font, box, mini(shared, fits[i]))
		var laid_text: String = laid.text
		var laid_size: int = laid.font_size
		laid_texts.append(laid_text)
		font_sizes.append(laid_size)
		var fitted := _measure_choice_text(laid_text, font, laid_size, box.x, true)
		max_scale = minf(max_scale, minf(box.x / maxf(fitted.x, 1.0), box.y / maxf(fitted.y, 1.0)))
	return {"texts": laid_texts, "font_sizes": font_sizes, "max_scale": maxf(max_scale, 1.0)}


## 選択肢を max_size 以下で内枠に収める: {"text": 改行を入れた表示文字列, "font_size": int}。
## 文節の切れ目で改行できない選択肢 (縦積みの分数・長い英単語など) は従来どおり Label3D の自動折り返しに任せる。
## max_size より小さい場合 (壁の中で揃えたサイズ) は、まずそのサイズちょうどで最も良い改行位置を探す。
## 結果は文字列・枠・上限ごとに覚えておく (同じ選択肢を次の壁や次の試合で組み直さない)。
static func _layout_choice(text: String, font: Font, box: Vector2, max_size: int) -> Dictionary:
	var key := "%d|%.3f|%.3f|%d|%s" % [font.get_instance_id(), box.x, box.y, max_size, text]
	var cached: Variant = _choice_layout_cache.get(key)
	if cached != null:
		return cached
	var laid := {}
	if max_size < CHOICE_FONT_SIZE_MAX:
		laid = ChoiceLineBreaker.layout(text, font, box, max_size, max_size)
	if laid.is_empty():
		laid = ChoiceLineBreaker.layout(text, font, box, CHOICE_FONT_SIZE_MIN, max_size)
	if laid.is_empty():
		laid = {"text": text, "font_size": mini(max_size, _fit_choice_size(text, font, box))}
	if _choice_layout_cache.size() >= TEXT_LAYOUT_CACHE_LIMIT:
		_choice_layout_cache.clear()
	_choice_layout_cache[key] = laid
	return laid


## 選択肢を収める扉の内枠 (幅 CHOICE_FIT_WIDTH_RATIO・高さ CHOICE_FIT_HEIGHT_RATIO、ラベルのピクセル単位)。
func _door_label_box(index: int) -> Vector2:
	return Vector2(
		_door_label_half_widths[index] * 2.0 * CHOICE_FIT_WIDTH_RATIO,
		CHOICE_VISIBLE_DOOR_HEIGHT * CHOICE_FIT_HEIGHT_RATIO
	) / door_labels[index].pixel_size


## 内枠に収まる最大の文字サイズ。
## 日本語は漢字の間でも折り返せるので、短い答えは「富|士山」のように割れないよう、
## 改行なしで CHOICE_SINGLE_LINE_MIN_FONT_SIZE 以上に出せる限り1行のまま表示する。
static func _fit_choice_size(text: String, font: Font, box: Vector2) -> int:
	var font_size := _largest_fitting_choice_size(text, font, box, false)
	if font_size < CHOICE_SINGLE_LINE_MIN_FONT_SIZE:
		font_size = _largest_fitting_choice_size(text, font, box, true)
	return font_size


static func _largest_fitting_choice_size(text: String, font: Font, box: Vector2, wrap: bool) -> int:
	var low := CHOICE_FONT_SIZE_MIN
	var high := CHOICE_FONT_SIZE_MAX
	while low < high:
		var mid := (low + high + 1) / 2
		var size := _measure_choice_text(text, font, mid, box.x, wrap)
		if size.x <= box.x and size.y <= box.y:
			low = mid
		else:
			high = mid - 1
	return low


## 輪郭を含む文字列の外寸 (ラベルのピクセル単位)。wrap=false では明示的な改行 (縦積みの分数) だけで改行する。
## wrap=true の折り返しは Label3D の AUTOWRAP_WORD_SMART と同じ規則。結果は文字列・大きさ・幅ごとに覚えておく。
static func _measure_choice_text(text: String, font: Font, font_size: int, width: float, wrap: bool) -> Vector2:
	var key := "%d|%d|%.3f|%d|%s" % [font.get_instance_id(), font_size, width if wrap else -1.0, int(wrap), text]
	var cached: Variant = _choice_measure_cache.get(key)
	if cached != null:
		return cached
	var tp := TextParagraph.new()
	tp.width = width if wrap else -1.0
	tp.break_flags = TextServer.BREAK_MANDATORY
	if wrap:
		tp.break_flags |= TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	tp.add_string(text, font, font_size)
	var measured := tp.get_size() + Vector2.ONE * _choice_outline_size(font_size) * 2.0
	if _choice_measure_cache.size() >= TEXT_LAYOUT_CACHE_LIMIT:
		_choice_measure_cache.clear()
	_choice_measure_cache[key] = measured
	return measured


func _set_choice_font_size(label: Label3D, font_size: int) -> void:
	label.font_size = font_size
	label.outline_size = _choice_outline_size(font_size)


## 等倍の 48px で 8px だった輪郭の太さを、文字サイズに比例させる。
static func _choice_outline_size(font_size: int) -> int:
	return maxi(1, roundi(float(font_size) / 6.0))


func _apply_door_label_scale() -> void:
	for label: Label3D in door_labels:
		if is_instance_valid(label):
			label.scale = Vector3.ONE * minf(_text_scale, _door_label_max_scale)

func set_quiz(quiz: QuizItem, num_choices: int) -> void:
	# GameWorld は現在の壁へ毎フレーム呼ぶので、前回と同じなら選択肢の整形もしない。
	if num_choices == _current_num_choices and quiz == _set_quiz_item and (quiz == null or quiz.c == _set_quiz_choices):
		return
	_set_quiz_item = quiz
	_set_quiz_choices = quiz.c.duplicate() if quiz else PackedStringArray()
	if num_choices != _current_num_choices:
		_build_doors(num_choices)

	# 扉は色で区別できるので記号 (A. など) は付けず、答えだけを扉の中央に大きく出す。
	# 分数だけの答えは縦積み、文中の分数はインライン表記。
	var changed := false
	for i: int in range(door_labels.size()):
		var text := FractionFormatter.format_choice(quiz.c[i]) if quiz and i < quiz.c.size() else ""
		changed = _set_door_label_text(i, text) or changed
	if changed:
		_fit_door_labels()

func set_labels_visible(is_visible: bool) -> void:
	for label: Label3D in door_labels:
		if is_instance_valid(label):
			label.visible = is_visible
	if not is_visible:
		set_gameplay_question_visible(false)


## Faces -Z (the player side). The menu preview turns the whole wall to show this face.
## Called repeatedly by GameWorld, so shaping only runs when the text changes.
func set_gameplay_question(text: String, is_visible: bool) -> void:
	if text.is_empty():
		set_gameplay_question_visible(false)
		return
	if not is_instance_valid(gameplay_question_label):
		gameplay_question_label = _create_label()
		gameplay_question_label.name = "GameplayQuestion"
		gameplay_question_label.position.z = -0.65
		gameplay_question_label.outline_modulate = Color(0.02, 0.05, 0.08, 0.95)
		gameplay_question_label.scale = Vector3.ONE * _text_scale
		add_child(gameplay_question_label)
	if text != _gameplay_question_text:
		_gameplay_question_text = text
		_fit_question_label_to_two_lines(gameplay_question_label, text)
		# Label3D redraws its glyph mesh in the deferred queue after text changes.
		_update_gameplay_question_panel.call_deferred()
	set_gameplay_question_visible(is_visible)


func set_gameplay_question_visible(is_visible: bool) -> void:
	if is_instance_valid(gameplay_question_label):
		gameplay_question_label.visible = is_visible and not _retiring_after_pass and not _shattered


## 問題文と選択肢を、AI がいま書いているように 1〜3 文字ずつ出す（WallAiTextReveal）。問題文と選択肢を入れてから呼ぶ。
## delay 秒は文字を隠したまま待つ（落ちてくる壁なら着地のあとから書く）。壁ごとに 1 回だけ。
## いまは PV の撮影（tests/pv_capture/pv_v3_runtime.gd）だけが使う。ゲームのプレイ画面では出さない。
func begin_ai_text_reveal(delay: float = 0.0) -> void:
	if _ai_text_reveal_started:
		return
	_ai_text_reveal_started = true
	_use_own_question_border_material()
	var question: Label3D = gameplay_question_label if is_instance_valid(gameplay_question_label) else null
	var choices: Array[Label3D] = []
	for label: Label3D in door_labels:
		if is_instance_valid(label):
			choices.append(label)
	_ai_text_reveal = WallAiTextReveal.new()
	_ai_text_reveal.name = "AiTextReveal"
	add_child(_ai_text_reveal)
	_ai_text_reveal.start(question, choices, delay)


func has_started_ai_text_reveal() -> bool:
	return _ai_text_reveal_started


## 書いている途中なら、すぐに書き終えた姿へ戻す。
func _finish_ai_text_reveal() -> void:
	if is_instance_valid(_ai_text_reveal) and not _ai_text_reveal.is_finished():
		_ai_text_reveal.finish_now()
	_ai_text_reveal = null


## A solid (navy, QUESTION_PANEL_COLOR) backing keeps the sky and scenery out of the question text.
## Child meshes inherit the label's orientation, visibility and retirement.
func _update_gameplay_question_panel() -> void:
	if not is_instance_valid(_gameplay_question_panel):
		_gameplay_question_border = _create_question_panel_quad("QuestionBorder", QUESTION_BORDER_COLOR)
		_gameplay_question_panel = _create_question_panel_quad("QuestionBackground", QUESTION_PANEL_COLOR)
		if _ai_text_reveal_started:
			_use_own_question_border_material()
	var glyph_bounds := gameplay_question_label.get_aabb()
	var center := glyph_bounds.get_center()
	var padding := Vector2(0.28, 0.18)
	var panel_size := Vector2(glyph_bounds.size.x, glyph_bounds.size.y) + padding * 2.0
	# 板は全壁で共有する 1m 角なので、大きさはノードの拡大で合わせる。
	var border_size := panel_size + Vector2.ONE * 0.05
	_gameplay_question_panel.scale = Vector3(panel_size.x, panel_size.y, 1.0)
	_gameplay_question_border.scale = Vector3(border_size.x, border_size.y, 1.0)
	# Negative local Z is behind the text, on both the -Z and +Z wall faces.
	_gameplay_question_panel.position = Vector3(center.x, center.y, -0.035)
	_gameplay_question_border.position = Vector3(center.x, center.y, -0.045)
	_gameplay_question_anchor_offset = -glyph_bounds.position.y + padding.y + 0.025
	_apply_gameplay_question_anchor()


## Anchor the visible panel edge just above the door, independent of line count
## and of the 2P text scale (the panel is a child and scales with the label).
func _apply_gameplay_question_anchor() -> void:
	gameplay_question_label.position.y = DOOR_TOP_Y + QUESTION_DOOR_GAP + _gameplay_question_anchor_offset * _text_scale
	_update_question_wall_height()


## 2P: カメラが離れている間は問題文と選択肢を拡大表示、それ以外は等倍に切り替える。
func set_text_enlarged(enlarged: bool) -> void:
	if enlarged == _text_enlarged:
		return
	_text_enlarged = enlarged
	if _text_scale_tween != null:
		_text_scale_tween.kill()
	var target := TEXT_ENLARGED_SCALE if enlarged else 1.0
	_text_scale_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_text_scale_tween.tween_method(_set_text_scale, _text_scale, target, TEXT_SCALE_SWITCH_DURATION)


func is_text_enlarged() -> bool:
	return _text_enlarged


func _set_text_scale(text_scale: float) -> void:
	text_scale = maxf(text_scale, 1.0)
	if text_scale == _text_scale:
		return
	_text_scale = text_scale
	_apply_door_label_scale()
	if not is_instance_valid(gameplay_question_label):
		return
	gameplay_question_label.scale = Vector3.ONE * _text_scale
	if is_instance_valid(_gameplay_question_panel):
		_apply_gameplay_question_anchor()


func _minimum_wall_top_y() -> float:
	# Reserve two lines at the actual question font size, plus the existing panel padding/border.
	var two_line_height := JAPANESE_FONT.get_height(QUESTION_LABEL_FONT_SIZE) * 0.008 * 2.0
	return DOOR_TOP_Y + QUESTION_DOOR_GAP + two_line_height + 0.41 + QUESTION_TOP_MARGIN


func _update_question_wall_height() -> void:
	if wall_parts.is_empty() or not is_instance_valid(wall_parts[0]):
		return
	# The panel bottom stays on this line, so everything above it scales linearly.
	var question_floor := DOOR_TOP_Y + QUESTION_DOOR_GAP
	# Keep the two-line reserve at the current text scale so one- and two-line
	# questions still share the wall height while 2P text is enlarged.
	var minimum_content_top := question_floor + (_minimum_wall_top_y() - QUESTION_TOP_MARGIN - question_floor) * _text_scale
	var content_top := minimum_content_top
	if is_instance_valid(_gameplay_question_border):
		var panel_bounds: AABB = (gameplay_question_label.transform * _gameplay_question_border.transform) * _gameplay_question_border.get_aabb()
		content_top = panel_bounds.end.y
	content_top = maxf(content_top, minimum_content_top)
	_boss_scale_lift = 0.0
	if is_boss and is_instance_valid(boss_label):
		var heading_bounds := boss_label.get_aabb().grow(boss_label.outline_size * boss_label.pixel_size)
		boss_label.position.y = content_top + QUESTION_TOP_MARGIN - heading_bounds.position.y
		var base_content_top := question_floor + (content_top - question_floor) / _text_scale
		_boss_scale_lift = content_top - base_content_top
		content_top = boss_label.position.y + heading_bounds.end.y
	wall_top_y = content_top + QUESTION_TOP_MARGIN
	var beam := wall_parts[0]
	var beam_size := (beam.mesh as BoxMesh).size
	beam_size.y = wall_top_y - DOOR_TOP_Y
	if _text_scale > 1.0:
		# The 2P enlarge switch eases over a few frames; resize a wall-owned box
		# instead of filling the shared cache with one mesh per intermediate height.
		if beam.mesh != _scaled_beam_mesh:
			_scaled_beam_mesh = BoxMesh.new()
			beam.mesh = _scaled_beam_mesh
		_scaled_beam_mesh.size = beam_size
	else:
		# Shared cached meshes are immutable; other walls keep their own height.
		beam.mesh = _shared_box_mesh(beam_size)
	beam.position.y = DOOR_TOP_Y + beam_size.y * 0.5


func _create_question_panel_quad(node_name: String, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	panel.mesh = _shared_question_panel_quad()
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.material_override = _shared_question_panel_material(color)
	gameplay_question_label.add_child(panel)
	return panel


static func _shared_question_panel_quad() -> QuadMesh:
	if _question_panel_quad == null:
		_question_panel_quad = QuadMesh.new()
	return _question_panel_quad


## 背景パネルと縁の材質（UNSHADED・霧なし）。色ごとに1枚だけ作り、試合をまたいで持ち続ける。
static func _shared_question_panel_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	var cached: StandardMaterial3D = _question_panel_materials.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_fog = true
	_question_panel_materials[key] = material
	return material


## AI の書き出し演出（WallAiTextReveal）は縁の色を書き換えるので、この壁の縁だけ共有の材質を複製して使う。
func _use_own_question_border_material() -> void:
	if not is_instance_valid(_gameplay_question_border):
		return
	var shared := _shared_question_panel_material(QUESTION_BORDER_COLOR)
	if _gameplay_question_border.material_override == shared:
		_gameplay_question_border.material_override = shared.duplicate() as StandardMaterial3D


## Actual glyph bounds, including the outline, for camera framing.
## at_base_scale: the same layout without the 2P text scale. The saw retreat
## uses it so enlarged text never feeds back into a larger camera pull-back.
func get_gameplay_framing_points(at_base_scale: bool = false) -> PackedVector3Array:
	var points := PackedVector3Array()
	if not is_instance_valid(gameplay_question_label) or not gameplay_question_label.is_visible_in_tree():
		return points
	var question_xform := _framing_transform(gameplay_question_label, at_base_scale)
	_append_label_framing_points(points, gameplay_question_label, question_xform)
	if is_instance_valid(boss_label) and boss_label.is_visible_in_tree():
		_append_label_framing_points(points, boss_label, _framing_transform(boss_label, at_base_scale))
	if is_instance_valid(_gameplay_question_border):
		var panel_bounds := _gameplay_question_border.get_aabb()
		var panel_xform := question_xform * _gameplay_question_border.transform
		for corner: int in range(8):
			points.append(panel_xform * panel_bounds.get_endpoint(corner))
	for label: Label3D in door_labels:
		if is_instance_valid(label) and label.is_visible_in_tree():
			_append_label_framing_points(points, label, _framing_transform(label, at_base_scale))
	return points


## 選択肢（扉と選択肢の文字）と問題文パネルが画面のどこに映っているか（オンラインの頭上の名前が重なったら薄くする用）。
## 文字を消した壁（通過後など）とカメラの後ろにかかる部分は含めない。
func get_choice_screen_rects(camera: Camera3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _retiring_after_pass or camera == null:
		return rects
	for i: int in range(doors.size()):
		var label: Label3D = door_labels[i] if i < door_labels.size() else null
		if not is_instance_valid(label) or not label.is_visible_in_tree():
			continue
		var points := PackedVector3Array()
		var door := doors[i]
		if is_instance_valid(door) and door.is_visible_in_tree():
			var door_bounds := door.get_aabb()
			for corner: int in range(8):
				points.append(door.global_transform * door_bounds.get_endpoint(corner))
		_append_label_framing_points(points, label, label.global_transform)
		_append_screen_rect(rects, camera, points)
	if is_instance_valid(gameplay_question_label) and gameplay_question_label.is_visible_in_tree():
		var question_points := PackedVector3Array()
		_append_label_framing_points(question_points, gameplay_question_label, gameplay_question_label.global_transform)
		if is_instance_valid(_gameplay_question_border):
			var panel_bounds := _gameplay_question_border.get_aabb()
			for corner: int in range(8):
				question_points.append(_gameplay_question_border.global_transform * panel_bounds.get_endpoint(corner))
		_append_screen_rect(rects, camera, question_points)
	return rects


func _append_screen_rect(rects: Array[Rect2], camera: Camera3D, points: PackedVector3Array) -> void:
	if points.is_empty():
		return
	var rect := Rect2()
	for i: int in range(points.size()):
		if camera.is_position_behind(points[i]):
			return
		var screen := camera.unproject_position(points[i])
		rect = Rect2(screen, Vector2.ZERO) if i == 0 else rect.expand(screen)
	rects.append(rect)


func _framing_transform(node: Node3D, at_base_scale: bool) -> Transform3D:
	if not at_base_scale or _text_scale == 1.0:
		return node.global_transform
	var local := node.transform
	if node == boss_label:
		local.origin.y -= _boss_scale_lift
	else:
		# Door labels clamp the 2P scale to their door, so undo each node's own scale.
		local.basis = local.basis.scaled(Vector3.ONE / node.scale.x)
		if node == gameplay_question_label and is_instance_valid(_gameplay_question_panel):
			local.origin.y = DOOR_TOP_Y + QUESTION_DOOR_GAP + _gameplay_question_anchor_offset
	return global_transform * local


func _append_label_framing_points(points: PackedVector3Array, label: Label3D, xform: Transform3D) -> void:
	var bounds := label.get_aabb().grow(label.outline_size * label.pixel_size)
	for corner: int in range(8):
		points.append(xform * bounds.get_endpoint(corner))


## PV の撮影（tests/pv_capture）のときだけ true にする。通過した壁を薄れさせずに残し、
## コースの後端を越えたときに通常どおり片付ける（文字と火花は通常どおり消す）。ゲームでは常に false。
static var keep_after_pass_for_capture: bool = false

## 1P用: プレイヤーが通過した壁を、文字を残さず短くフェード退場させる。
func retire_after_player_pass(fade_duration: float = 0.28) -> void:
	if _retiring_after_pass:
		return
	_retiring_after_pass = true
	_retirement_finished = false
	_finish_ai_text_reveal()
	set_labels_visible(false)
	if is_instance_valid(boss_label):
		boss_label.visible = false
	for sparks: CPUParticles3D in boss_sparks:
		if is_instance_valid(sparks):
			sparks.emitting = false
			sparks.visible = false
	if keep_after_pass_for_capture:
		return
	# 同じ材質の部品は、この壁の中で1枚の半透明の複製と1本のTweenを共有する（どれも同じ速さで消える）。
	var fading: Dictionary = {}
	for part: MeshInstance3D in wall_parts:
		_fade_mesh_to_transparent(part, fade_duration, fading)
	for door: MeshInstance3D in doors:
		_fade_mesh_to_transparent(door, fade_duration, fading)
	var finish_tween: Tween = create_tween()
	finish_tween.tween_interval(fade_duration)
	finish_tween.tween_callback(_mark_retirement_finished)


## いまの問題の壁だけ、延長線上にワールドボーダーを立てる（見た目。押し戻しは GameState 側）。
func set_world_border_active(active: bool) -> void:
	var show := active and not _retiring_after_pass and not _shattered
	if show and _world_border == null:
		_build_world_border(true)
	if _world_border != null:
		_world_border.visible = show


## 次の問題の壁は、切り替えのフレームより前にワールドボーダーを隠したまま組んでおく
## （問題文を入れる前の壁の高さで組むので、切り替えのフレームで組むのと同じ形になる）。
func prepare_world_border() -> void:
	if _world_border == null and not _retiring_after_pass and not _shattered:
		_build_world_border(false)


func _build_world_border(shown: bool) -> void:
	_world_border = WallWorldBorder.new()
	_world_border.name = "WorldBorder"
	_world_border.visible = shown
	_world_border.build(
		StageConstants.QUIZ_WALL_HALF_WIDTH,
		StageConstants.WALL_WORLD_BORDER_OUTER_X,
		StageConstants.FLOOR_TOP_Y - 0.3,
		wall_top_y
	)
	add_child(_world_border)


func is_retiring_after_pass() -> bool:
	return _retiring_after_pass


func is_retirement_finished() -> bool:
	return _retirement_finished


## Render prewarm: gives every part the transparent material the retirement fade starts
## from (alpha 1, nothing hidden), so the textured panel's alpha variant is compiled
## before the first wall is passed instead of at that moment.
## The transparent copies are shared and kept (_shared_fade_material), so the compiled
## variant also stays alive for every later pass instead of being freed with each wall.
func prewarm_retirement_fade() -> void:
	for mesh_inst: MeshInstance3D in wall_parts + doors:
		if not is_instance_valid(mesh_inst):
			continue
		var material: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
		if material == null:
			continue
		mesh_inst.material_override = _shared_fade_material(material)


func _fade_mesh_to_transparent(mesh_inst: MeshInstance3D, fade_duration: float, fading: Dictionary) -> void:
	if not is_instance_valid(mesh_inst):
		return
	var material: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
	if material == null:
		return
	var unique_material: StandardMaterial3D = fading.get(material) as StandardMaterial3D
	if unique_material == null:
		unique_material = _shared_fade_material(material).duplicate() as StandardMaterial3D
		fading[material] = unique_material
		var color: Color = unique_material.albedo_color
		var target_color := Color(color.r, color.g, color.b, 0.0)
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(unique_material, "albedo_color", target_color, fade_duration)
	mesh_inst.material_override = unique_material


## material の半透明版（色はそのまま、alpha 1）。共有の不透明材質ごとに1枚だけ作って持ち続ける。
## もともと半透明の材質（予熱で入れたもの）はそのまま使う。
static func _shared_fade_material(material: StandardMaterial3D) -> StandardMaterial3D:
	if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		return material
	var key := material.get_instance_id()
	var cached: StandardMaterial3D = _fade_material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	cached = material.duplicate() as StandardMaterial3D
	cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_material_cache[key] = cached
	return cached


func _mark_retirement_finished() -> void:
	_retirement_finished = true


const QUESTION_LABEL_MAX_LINES := 2
## 1行でも2行でも常にこの大きさで表示する（行数によって縮小しない）
const QUESTION_LABEL_FONT_SIZE := 64
## 扉から文字の下端までの余白（ゲームでは背景パネルの実寸でも補正する）
const QUESTION_LABEL_DOOR_CLEARANCE := 0.45
## 横幅の初期値・拡張刻み・上限（壁全幅24mに対して十分小さく、省略せず全文表示するために広げる）
const QUESTION_LABEL_BASE_WIDTH := 640.0
const QUESTION_LABEL_WIDTH_STEP := 80.0
const QUESTION_LABEL_MAX_WIDTH := 1600.0
## 問題文の改行を行の区切りとして守り、行の途中では折り返さない（練習の台本の問題。本番は false）。
var keep_question_lines := false

## 問題文ラベルは1行・2行のどちらでも同じ文字サイズで表示し、省略はしない。
## 2行に収まらない場合は横幅を段階的に広げて全文を表示する（上限に達したらそこで止める）。
## 下端を扉の上端へ固定し、行数が増えたら壁面の上方向へ伸ばす。
func _fit_question_label_to_two_lines(label: Label3D, text: String) -> void:
	if not label:
		return
	var font: Font = label.font if label.font else ThemeDB.fallback_font
	var font_size := QUESTION_LABEL_FONT_SIZE
	label.font_size = font_size
	label.text = text
	label.width = _question_label_width(text, font, _question_max_lines(text, keep_question_lines))

	# 行数によらず、問題文を扉のすぐ上に揃える。
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position.y = DOOR_TOP_Y + QUESTION_LABEL_DOOR_CLEARANCE


static func _question_max_lines(text: String, keep_lines: bool) -> int:
	if keep_lines:
		return mini(text.count("\n") + 1, QUESTION_LABEL_MAX_LINES)
	return QUESTION_LABEL_MAX_LINES


## max_lines 行に収まるまで広げた問題文ラベルの幅。段落は1回だけ組み、幅を変えて行分けだけやり直す。
## 結果は問題文ごとに覚えておく (GameWorld が次の問題の分を先に求めておく)。
static func _question_label_width(text: String, font: Font, max_lines: int) -> float:
	var key := "%d|%d|%s" % [font.get_instance_id(), max_lines, text]
	var cached: Variant = _question_width_cache.get(key)
	if cached != null:
		return cached
	var tp := TextParagraph.new()
	tp.width = QUESTION_LABEL_BASE_WIDTH
	tp.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	tp.add_string(text, font, QUESTION_LABEL_FONT_SIZE)
	var width := QUESTION_LABEL_BASE_WIDTH
	while width < QUESTION_LABEL_MAX_WIDTH and maxi(1, tp.get_line_count()) > max_lines:
		width = minf(width + QUESTION_LABEL_WIDTH_STEP, QUESTION_LABEL_MAX_WIDTH)
		tp.width = width
	if _question_width_cache.size() >= TEXT_LAYOUT_CACHE_LIMIT:
		_question_width_cache.clear()
	_question_width_cache[key] = width
	return width


func set_is_boss(boss: bool) -> void:
	is_boss = boss
	var target_color = BOSS_WALL_COLOR if is_boss else WALL_COLOR
	for part in wall_parts:
		if is_instance_valid(part):
			part.material_override = _shared_opaque_material(target_color)
	
	if is_boss and not is_instance_valid(boss_label):
		boss_label = _create_label()
		boss_label.text = "BOSS問題"
		boss_label.font_size = 72
		boss_label.modulate = Color(1.0, 0.4, 0.4)
		boss_label.outline_modulate = Color(0.1, 0.1, 0.1)
		boss_label.outline_size = 12
		boss_label.position = Vector3(0, wall_top_y - 0.55, -0.65)
		boss_label.width = QUESTION_LABEL_BASE_WIDTH
		add_child(boss_label)
		
		# ボス壁のサイドに火花エフェクトを追加
		var left_spark := _create_boss_sparks(13.0)
		var right_spark := _create_boss_sparks(-13.0)
		add_child(left_spark)
		add_child(right_spark)
		boss_sparks.append(left_spark)
		boss_sparks.append(right_spark)
		
	elif not is_boss:
		if is_instance_valid(boss_label):
			boss_label.queue_free()
			boss_label = null
		for sp in boss_sparks:
			if is_instance_valid(sp):
				sp.queue_free()
		boss_sparks.clear()
	_update_question_wall_height.call_deferred()

func _create_boss_sparks(pos_x: float) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = GraphicsQuality.particle_amount(60, GameManager.graphics_quality)
	sparks.lifetime = 0.8
	sparks.explosiveness = 0.05
	sparks.randomness = 1.0
	
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 3.5, 0.5)
	
	# 外側に向かって吹き出すようにする
	sparks.direction = Vector3(sign(pos_x), 0.5, 0.5).normalized()
	sparks.spread = 25.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 10.0
	
	sparks.gravity = Vector3(0, -12.0, 0)
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.25

	sparks.mesh = _shared_boss_spark_mesh()

	sparks.position = Vector3(pos_x, 0.5, 0.0)
	return sparks


## 火花の板と材質は全ボス壁で共有する（ボス壁が消えるたびにシェーダーを解放しない）。
static func _shared_boss_spark_mesh() -> QuadMesh:
	if _boss_spark_mesh == null:
		# ピカピカ光るマテリアル
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		_boss_spark_mesh = QuadMesh.new()
		_boss_spark_mesh.material = mat
	return _boss_spark_mesh


func break_door(door_index: int) -> void:
	if door_index < 0 or door_index >= doors.size():
		return
	var door := doors[door_index]
	if not door.visible:
		return
	# global_position はツリー内でのみ有効。ツリー外で読むと identity を返し
	# !is_inside_tree() エラーを毎回吐くため、ツリー外なら破砕をスキップする。
	if not door.is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	var door_color: Color = Color.WHITE
	if door.material_override:
		door_color = door.material_override.albedo_color
	var door_pos: Vector3 = door.global_position
	var door_size: Vector3 = (door.mesh as BoxMesh).size if door.mesh is BoxMesh else Vector3(2.0, 4.0, 1.0)

	# Hide original door and label
	door.visible = false
	if door_index < door_labels.size():
		door_labels[door_index].visible = false

	# Hide boss label if it exists
	if is_instance_valid(boss_label):
		boss_label.visible = false
	
	# Stop boss sparks
	for sp in boss_sparks:
		if is_instance_valid(sp):
			sp.emitting = false

	# Spawn debris chunks — fine fragmentation
	var vp := door.get_viewport()
	var is_preview_subviewport := vp is SubViewport
	var chunks_x := 2 if is_preview_subviewport else 4
	var chunks_y := 2 if is_preview_subviewport else 5
	var chunk_size := Vector3(door_size.x / chunks_x, door_size.y / chunks_y, door_size.z)

	for cx: int in range(chunks_x):
		for cy: int in range(chunks_y):
			var chunk := RigidBody3D.new()
			chunk.mass = 0.6
			chunk.gravity_scale = 1.8

			# Collision shape
			var col := CollisionShape3D.new()
			var piece_size := chunk_size * 0.9 * _debris_variation(0.7, 1.0)
			col.shape = _shared_debris_shape(piece_size)
			chunk.add_child(col)

			# Mesh
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = _shared_box_mesh(piece_size)
			mesh_inst.material_override = _shared_debris_material(door_color, _debris_variation(0.0, 0.2))
			chunk.add_child(mesh_inst)

			# Position: offset from door center
			var offset_x: float = (cx - (chunks_x - 1) * 0.5) * chunk_size.x
			var offset_y: float = (cy - (chunks_y - 1) * 0.5) * chunk_size.y

			# Collision layers: only collide with floor (layer 1), not players
			chunk.collision_layer = 0
			chunk.collision_mask = 1

			# 先にツリーへ追加してから global_position を設定する。
			# ツリー外で global_position を書くと get_global_transform() が
			# identity を返し !is_inside_tree() エラーを毎回吐く。
			parent.add_child(chunk)
			chunk.global_position = door_pos + Vector3(offset_x, offset_y, 0)

			if is_preview_subviewport:
				# 扉欠片だけ強めに弾け、短いTweenで縮小消滅（カメラ縮小処理とは別）
				chunk.set_meta("preview_door_shard", true)
				chunk.mass = 1.22
				chunk.gravity_scale = 2.35
				chunk.linear_damp = 0.09
				chunk.angular_damp = 0.14
				chunk.collision_mask = 1
				chunk.apply_central_impulse(
					Vector3(
						randf_range(-2.35, 2.35),
						randf_range(0.45, 3.15),
						randf_range(-26.5, -14.0),
					)
				)
				chunk.apply_torque_impulse(
					Vector3(
						randf_range(-3.6, 3.6),
						randf_range(-2.5, 2.5),
						randf_range(-3.6, 3.6),
					)
				)
				var vanish_tw := chunk.create_tween()
				vanish_tw.tween_interval(0.22)
				vanish_tw.tween_property(mesh_inst, "scale", Vector3.ZERO, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				vanish_tw.tween_callback(chunk.queue_free)
			else:
				# 本番：前方に飛ばす（画面手前側、+Z方向）＋縮小で消滅
				var scatter_z: float = randf_range(5.0, 15.0)
				var impulse := Vector3(
					(randf() - 0.5) * 10.0,
					randf() * 5.0 + 1.5,
					scatter_z
				)
				chunk.apply_central_impulse(impulse)
				chunk.apply_torque_impulse(Vector3(
					(randf() - 0.5) * 12.0,
					(randf() - 0.5) * 8.0,
					(randf() - 0.5) * 12.0
				))
				var tween := chunk.create_tween()
				tween.tween_interval(1.5)
				tween.tween_property(mesh_inst, "scale", Vector3.ZERO, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				tween.tween_callback(chunk.queue_free)

func is_solid_frame_occluding_segment(segment_start: Vector3, segment_end: Vector3) -> bool:
	# Answer doors are intentionally excluded so the x-ray silhouette cannot cover choices.
	for part: MeshInstance3D in wall_parts:
		if (
			not is_instance_valid(part)
			or part.mesh == null
			or not part.is_visible_in_tree()
		):
			continue
		var inverse_transform := part.global_transform.affine_inverse()
		var local_start := inverse_transform * segment_start
		var local_end := inverse_transform * segment_end
		if part.get_aabb().intersects_segment(local_start, local_end) != null:
			return true
	return false


## door_slot: 扉なら選択肢の番号（扉ごとに別のパネル位置を当て、周りの壁と同じ模様が並ばないようにする）。壁は -1。
func _create_box(half_extents: Vector3, color: Color, door_slot: int = -1) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _shared_box_mesh(half_extents * 2.0)
	mesh_inst.material_override = _shared_opaque_material(color, door_slot)
	return mesh_inst


static func _shared_box_mesh(size: Vector3) -> BoxMesh:
	var key := "%0.4f_%0.4f_%0.4f" % [size.x, size.y, size.z]
	var cached: BoxMesh = _box_mesh_cache.get(key) as BoxMesh
	if cached != null:
		return cached
	if _box_mesh_cache.size() >= BOX_MESH_CACHE_LIMIT:
		_box_mesh_cache.clear()
	var box := BoxMesh.new()
	box.size = size
	_box_mesh_cache[key] = box
	return box


## 破片の大きさ・色の乱数 (low〜high の一様乱数) を DEBRIS_VARIATION_STEPS 段の中央値に丸める。
static func _debris_variation(low: float, high: float) -> float:
	var step := randi_range(0, DEBRIS_VARIATION_STEPS - 1)
	return lerpf(low, high, (float(step) + 0.5) / DEBRIS_VARIATION_STEPS)


## 破片の当たり。同じ大きさの破片で1つの BoxShape3D を共有する。
static func _shared_debris_shape(size: Vector3) -> BoxShape3D:
	var key := "%0.4f_%0.4f_%0.4f" % [size.x, size.y, size.z]
	var cached: BoxShape3D = _debris_shape_cache.get(key) as BoxShape3D
	if cached != null:
		return cached
	if _debris_shape_cache.size() >= DEBRIS_CACHE_LIMIT:
		_debris_shape_cache.clear()
	var shape := BoxShape3D.new()
	shape.size = size
	_debris_shape_cache[key] = shape
	return shape


## 破片の材質（元の色を白へ tint だけ寄せる）。色と寄せ具合ごとに1枚だけ作って持ち続ける。
static func _shared_debris_material(color: Color, tint: float) -> StandardMaterial3D:
	var key := "%0.4f_%0.4f_%0.4f_%0.4f_%0.4f" % [color.r, color.g, color.b, color.a, tint]
	var cached: StandardMaterial3D = _debris_material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	if _debris_material_cache.size() >= DEBRIS_CACHE_LIMIT:
		_debris_material_cache.clear()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.lerp(Color.WHITE, tint)
	mat.roughness = 0.6
	mat.metallic = 0.05
	_debris_material_cache[key] = mat
	return mat


## 色（と扉の番号・画質）ごとに1枚だけ作って共有する。画質は作成時の GameManager.graphics_quality
## （壁は試合ごとに作り直されるので、設定変更は次の壁から反映される）。
static func _shared_opaque_material(color: Color, door_slot: int = -1) -> StandardMaterial3D:
	var quality := WallMaterials.current_quality()
	var panel_shift := 0 if door_slot < 0 else door_slot + 1
	var key := "%0.4f_%0.4f_%0.4f_%0.4f_%d_%s" % [color.r, color.g, color.b, color.a, panel_shift, quality]
	var cached: StandardMaterial3D = _opaque_material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var mat := WallMaterials.panel(color, quality, panel_shift, 1.0, 0.6, 0.05)
	_opaque_material_cache[key] = mat
	return mat

func _create_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Keep the nearby answer text above the transparent shark pass while preserving depth
	# testing, so choices on farther walls do not show through nearer walls.
	label.render_priority = 20
	label.outline_render_priority = 19
	label.pixel_size = 0.008
	label.width = 280.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.1, 0.1, 0.1, 1.0)
	label.outline_size = 8
	label.font_size = 48
	label.text = ""
	label.rotation.y = PI

	label.font = _wall_label_font()

	return label


static func _wall_label_font() -> FontFile:
	if _wall_font == null:
		var source := JAPANESE_FONT as FontFile
		_wall_font = FontFile.new()
		_wall_font.data = source.data
		_wall_font.multichannel_signed_distance_field = true
		_wall_font.msdf_size = WALL_FONT_MSDF_SIZE
		_wall_font.msdf_pixel_range = WALL_FONT_MSDF_PIXEL_RANGE
		_wall_font.generate_mipmaps = true
		_wall_font.allow_system_fallback = source.allow_system_fallback
	return _wall_font


## text の字のうち、まだ壁のフォントに描いていないものを先描きの待ち行列に入れる（空白は除く）。
## urgent はこれから出す問題文・選択肢（試合前のかな・英数字より先に描く。試合前の待ち行列でまだ描いていない字も並べ直す）。
static func queue_wall_glyphs(text: String, urgent: bool = false) -> void:
	for i: int in range(text.length()):
		var codepoint := text.unicode_at(i)
		if codepoint <= 0x20 or codepoint == 0x3000 or codepoint == 0xA0 or (codepoint >= 0xD800 and codepoint <= 0xDFFF) \
				or codepoint > 0x10FFFF:
			continue
		if _glyph_prime_seen.has(codepoint) and (not urgent or bool(_glyph_prime_seen[codepoint])):
			continue
		_glyph_prime_seen[codepoint] = urgent
		if urgent:
			_glyph_prime_urgent.append(codepoint)
		else:
			_glyph_prime_queue.append(codepoint)


## 試合前にまとめて描いておく、かな・英数字・記号（WALL_GLYPH_PRIME_RANGES と WALL_GLYPH_PRIME_EXTRA）。
static func queue_wall_glyph_base_set() -> void:
	for glyph_range: Vector2i in WALL_GLYPH_PRIME_RANGES:
		for codepoint: int in range(glyph_range.x, glyph_range.y + 1):
			if not _glyph_prime_seen.has(codepoint):
				_glyph_prime_seen[codepoint] = false
				_glyph_prime_queue.append(codepoint)
	queue_wall_glyphs(WALL_GLYPH_PRIME_EXTRA)


## 待ち行列の字を budget_usec の間だけ壁のフォントに描く（1回に少なくとも1字。メインスレッドから呼ぶ）。
## これから出す問題文・選択肢の字（urgent）が残っていなければ true。
## urgent_only はプレイ中：試合前の待ち行列は描かない（問題の字のページへ書き足して、送ったページを汚したままにしない）。
static func prime_queued_wall_glyphs(budget_usec: int, urgent_only: bool = false) -> bool:
	var has_urgent := _glyph_prime_urgent_cursor < _glyph_prime_urgent.size()
	if not has_urgent and (urgent_only or _glyph_prime_queue_cursor >= _glyph_prime_queue.size()):
		# 試合前に書き足していたページが残っていれば、ここで送っておく。
		_flush_primed_glyph_pages(-1)
		return true
	var rids := _wall_label_font().get_rids()
	if rids.is_empty():
		return true
	var font_rid: RID = rids[0]
	var ts := TextServerManager.get_primary_interface()
	# MSDF は文字サイズによらず1字1回なので、どの大きさのラベルもこの1つのキャッシュを使う。
	var cache_size := Vector2i(WALL_FONT_MSDF_SIZE, 0)
	var started := Time.get_ticks_usec()
	var last_page := -1
	var rendered_urgent := false
	while Time.get_ticks_usec() - started < budget_usec:
		var codepoint := -1
		if _glyph_prime_urgent_cursor < _glyph_prime_urgent.size():
			codepoint = _glyph_prime_urgent[_glyph_prime_urgent_cursor]
			_glyph_prime_urgent_cursor += 1
			rendered_urgent = true
		elif not urgent_only and _glyph_prime_queue_cursor < _glyph_prime_queue.size():
			codepoint = _glyph_prime_queue[_glyph_prime_queue_cursor]
			_glyph_prime_queue_cursor += 1
			if bool(_glyph_prime_seen.get(codepoint, false)):
				# 問題の字として先に描いた字。
				continue
			_glyph_prime_seen[codepoint] = true
		else:
			break
		var glyph := ts.font_get_glyph_index(font_rid, WALL_FONT_MSDF_SIZE, codepoint, 0)
		ts.font_render_glyph(font_rid, cache_size, glyph)
		var page := ts.font_get_glyph_texture_idx(font_rid, cache_size, glyph)
		if page >= 0:
			_glyph_prime_pages[page] = glyph
			last_page = page
	if _glyph_prime_urgent_cursor >= _glyph_prime_urgent.size():
		_glyph_prime_urgent.clear()
		_glyph_prime_urgent_cursor = 0
	if _glyph_prime_queue_cursor >= _glyph_prime_queue.size():
		_glyph_prime_queue.clear()
		_glyph_prime_queue_cursor = 0
	var urgent_done := _glyph_prime_urgent.is_empty()
	# 書き終えたページだけを GPU へ送る（書き足し中のページは、問題の字が揃ったときか全部描き終えたときに送る）。
	var all_done := urgent_done and (urgent_only or _glyph_prime_queue.is_empty())
	_flush_primed_glyph_pages(-1 if all_done or (rendered_urgent and urgent_done) else last_page)
	return urgent_done


## 描いた字の載ったページを取り出して、TextServer に書き換えた画像を GPU へ送らせる
## （送らずにおくと、次に字を組むラベル＝切り替えのフレームでまとめて送ることになる）。keep_page は送らずに残す。
static func _flush_primed_glyph_pages(keep_page: int) -> void:
	if _glyph_prime_pages.is_empty():
		return
	var rids := _wall_label_font().get_rids()
	if rids.is_empty():
		_glyph_prime_pages.clear()
		return
	var ts := TextServerManager.get_primary_interface()
	var cache_size := Vector2i(WALL_FONT_MSDF_SIZE, 0)
	for page: int in _glyph_prime_pages.keys():
		if page == keep_page:
			continue
		ts.font_get_glyph_texture_rid(rids[0], cache_size, int(_glyph_prime_pages[page]))
		_glyph_prime_pages.erase(page)


## 次に壁へ入れる問題文と選択肢の組版を先に済ませる（結果は文字列ごとに覚えるので、壁に入れるときは計算しない）。
## choices は扉に出す整形済みの選択肢（FractionFormatter.format_choice）、keep_lines は練習の keep_question_lines。
static func prepare_wall_text_layout(question: String, choices: PackedStringArray, num_choices: int, keep_lines: bool) -> void:
	var font := _wall_label_font()
	if not question.is_empty():
		_question_label_width(question, font, _question_max_lines(question, keep_lines))
	var door_half_width := 1.8
	if num_choices == 4:
		door_half_width = 1.45
	elif num_choices == 3:
		door_half_width = DOOR3_HALF_WIDTH
	# _door_label_box と同じ内枠。
	var box := Vector2(
		door_half_width * 2.0 * CHOICE_FIT_WIDTH_RATIO,
		CHOICE_VISIBLE_DOOR_HEIGHT * CHOICE_FIT_HEIGHT_RATIO
	) / CHOICE_PIXEL_SIZE
	var texts: Array[String] = []
	var boxes: Array[Vector2] = []
	for i: int in range(num_choices):
		texts.append(choices[i] if i < choices.size() else "")
		boxes.append(box)
	_fit_choice_texts(texts, boxes, font)


## Render prewarm: 正解・通過で初めて出るもの（扉の破片の材質と、ワールドボーダーの面）を壁の手前に小さく置いて
## 描かせ、最初の壁の切り替えでシェーダーを作らないようにする。どちらの材質も共有なので、以後も解放されない。
func prewarm_pass_effects() -> void:
	var debris := MeshInstance3D.new()
	debris.name = "PrewarmDoorDebris"
	debris.mesh = _shared_box_mesh(Vector3.ONE * 0.6)
	debris.material_override = _shared_debris_material(DOOR_COLORS_2[0], 0.0)
	debris.position = Vector3(-0.8, 1.0, 0.9)
	add_child(debris)
	var border := MeshInstance3D.new()
	border.name = "PrewarmWorldBorder"
	border.mesh = WallWorldBorder.shared_quad(Vector2(1.2, 1.2))
	border.material_override = WallWorldBorder.shared_material()
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	border.position = Vector3(0.8, 1.0, 0.9)
	add_child(border)

func shatter_wall(direction_z: float = -1.0) -> void:
	_shattered = true
	_finish_ai_text_reveal()
	set_gameplay_question_visible(false)
	for part in wall_parts:
		if is_instance_valid(part) and part.visible:
			_shatter_mesh(part, direction_z)
			part.visible = false
	for door in doors:
		if is_instance_valid(door) and door.visible:
			_shatter_mesh(door, direction_z)
			door.visible = false
	for label in door_labels:
		if is_instance_valid(label):
			label.visible = false
	if is_instance_valid(boss_label):
		boss_label.visible = false

func _shatter_mesh(mesh_inst: MeshInstance3D, direction_z: float) -> void:
	if not is_instance_valid(mesh_inst): return
	var box := mesh_inst.mesh as BoxMesh
	if not box: return
	
	var base_color := WALL_COLOR
	if mesh_inst.material_override and mesh_inst.material_override is StandardMaterial3D:
		base_color = (mesh_inst.material_override as StandardMaterial3D).albedo_color
		
	# global_position はツリー内でのみ有効。ツリー外で読むと identity を返し
	# !is_inside_tree() エラーを毎回吐くため、ツリー外なら破砕をスキップする。
	if not mesh_inst.is_inside_tree(): return
	var parent := get_parent()
	if parent == null: return

	var size := box.size
	var pos := mesh_inst.global_position

	var chunks_x := maxi(1, ceili(size.x / 1.5))
	var chunks_y := maxi(1, ceili(size.y / 1.5))
	var chunk_size := Vector3(size.x / chunks_x, size.y / chunks_y, size.z)
	
	for cx: int in range(chunks_x):
		for cy: int in range(chunks_y):
			var chunk := RigidBody3D.new()
			chunk.mass = 0.5
			chunk.gravity_scale = 1.8
			chunk.collision_layer = 0
			chunk.collision_mask = 1
			
			var col := CollisionShape3D.new()
			var piece_size := chunk_size * _debris_variation(0.7, 0.95)
			col.shape = _shared_debris_shape(piece_size)
			chunk.add_child(col)

			var cmi := MeshInstance3D.new()
			cmi.mesh = _shared_box_mesh(piece_size)
			cmi.material_override = _shared_debris_material(base_color, _debris_variation(0.0, 0.2))
			chunk.add_child(cmi)
			
			var offset_x: float = (cx - (chunks_x - 1) * 0.5) * chunk_size.x
			var offset_y: float = (cy - (chunks_y - 1) * 0.5) * chunk_size.y

			# 先にツリーへ追加してから global_position を設定する。
			# ツリー外で global_position を書くと get_global_transform() が
			# identity を返し !is_inside_tree() エラーを毎回吐く。
			parent.add_child(chunk)
			chunk.global_position = pos + Vector3(offset_x, offset_y, 0)
			
			var vp := chunk.get_viewport()
			var is_preview_subviewport := vp is SubViewport
			if is_preview_subviewport:
				chunk.set_meta("preview_door_shard", true)
				chunk.mass = 1.1
				chunk.gravity_scale = 2.2
				chunk.linear_damp = 0.12
				chunk.angular_damp = 0.16
				chunk.apply_central_impulse(
					Vector3(
						randf_range(-2.8, 2.8),
						randf_range(0.5, 3.4),
						randf_range(12.0, 24.0) * direction_z,
					)
				)
				chunk.apply_torque_impulse(
					Vector3(
						randf_range(-4.0, 4.0),
						randf_range(-3.0, 3.0),
						randf_range(-4.0, 4.0),
					)
				)
				var vanish_tw := chunk.create_tween()
				vanish_tw.tween_interval(0.25)
				vanish_tw.tween_property(cmi, "scale", Vector3.ZERO, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				vanish_tw.tween_callback(chunk.queue_free)
			else:
				# 進行方向（direction_z）へ爆散させる
				var impulse_x: float = (randf() - 0.5) * 30.0 # 左右への強い散らばり
				var impulse_y: float = randf_range(5.0, 25.0) # 上方向への強い吹き飛ばし
				var impulse_z: float = randf_range(10.0, 40.0) * direction_z # 指定方向へ大きく飛ばす
				
				var impulse := Vector3(impulse_x, impulse_y, impulse_z)
				chunk.apply_central_impulse(impulse)
				chunk.apply_torque_impulse(Vector3(
					(randf() - 0.5) * 40.0,
					(randf() - 0.5) * 40.0,
					(randf() - 0.5) * 40.0
				))
				
				# 縮小しながら消滅する演出
				var tween := chunk.create_tween()
				tween.tween_interval(1.5)
				tween.tween_property(cmi, "scale", Vector3.ZERO, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				tween.tween_callback(chunk.queue_free)
