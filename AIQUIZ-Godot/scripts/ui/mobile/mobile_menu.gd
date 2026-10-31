extends RefCounted

## メニュー画面のスマホ（タッチだけ）向けの小さな道具。デスクトップでは何もしない／元の値を返す。
##   ・もどる操作（Android の戻るジェスチャー）の判定
##   ・トップでの「ゲームを終了しますか？」（MobileLifecycle）
##   ・FPS上限の選択肢（GameManager.available_max_fps_choices）
##   ・設定の行「しんどう（バイブ）」「ボタンの大きさ」
##   ・タップの位置にある UI 部品の判定（ホバーの残りに頼らない）
##   ・ソフトキーボードの高さ（論理 px）
##
## Use: const MobileMenu = preload("res://scripts/ui/mobile/mobile_menu.gd")

const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const GameManagerScript = preload("res://scripts/autoload/game_manager.gd")

## 「ボタンの大きさ」の 小 / ふつう / 大（GameManager.touch_controls_scale）。
const TOUCH_SCALE_CHOICES: Array[float] = [0.85, 1.0, 1.2]
const TOUCH_SCALE_NAMES: Array[String] = ["小", "ふつう", "大"]
const HAPTICS_ON := 0
const HAPTICS_OFF := 1


static func is_touch_ui() -> bool:
	return MobileUi.is_touch_ui()


## もどる操作か（Esc・ui_cancel）。
## Android の戻るジェスチャーは Esc キーと ui_cancel アクションの 2 つで届く（MobileLifecycle）。
## タッチの画面では Esc キーのほうだけを数え、1 回のジェスチャーで 2 段もどらないようにする。
static func is_back_event(event: InputEvent) -> bool:
	if event == null:
		return false
	if event is InputEventAction and is_touch_ui():
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			return true
	return event.is_action_pressed("ui_cancel")


## トップ画面で何も開いていないときの「もどる」：終了の確認を出す（スマホだけ）。
static func request_quit_confirm() -> void:
	if not is_touch_ui():
		return
	var lifecycle := _root_node("MobileLifecycle")
	if lifecycle != null and lifecycle.has_method("request_quit_confirm"):
		lifecycle.call("request_quit_confirm")


## 設定画面の「FPS上限」の選択肢。スマホは 30 / 60 / 120（GameManager に任せる）。
static func max_fps_choices() -> Array[int]:
	var result: Array[int] = []
	for value: int in GameManagerScript.available_max_fps_choices():
		result.append(value)
	return result


## FPS上限の OptionButton で今の値を選ぶ。保存値が選択肢に無い（スマホで 144 など）なら 60 か先頭。
static func select_fps_item(option: OptionButton, fps: int) -> void:
	var index := option.get_item_index(fps)
	if index < 0:
		index = option.get_item_index(60)
	if index < 0 and option.item_count > 0:
		index = 0
	option.select(index)


## 画質の選択肢から「最高画質」を外すか（スマホでは高画質と同じ扱いになるため出さない）。
static func hide_ultra_quality() -> bool:
	return is_touch_ui()


## 「しんどう（バイブ）」の OptionButton（オン／オフ）を用意する。選ぶとすぐ保存する。
static func setup_haptics_option(option: OptionButton) -> void:
	option.add_item("オン", HAPTICS_ON)
	option.add_item("オフ", HAPTICS_OFF)
	var manager := _root_node("GameManager")
	var enabled := manager == null or bool(manager.get("haptics_enabled"))
	option.select(option.get_item_index(HAPTICS_ON if enabled else HAPTICS_OFF))
	option.item_selected.connect(func(index: int) -> void:
		var target := _root_node("GameManager")
		if target != null:
			target.call("set_haptics_enabled", option.get_item_id(index) == HAPTICS_ON))


## 「ボタンの大きさ」の OptionButton（小 0.85 / ふつう 1.0 / 大 1.2）を用意する。
static func setup_touch_scale_option(option: OptionButton) -> void:
	for index: int in range(TOUCH_SCALE_CHOICES.size()):
		option.add_item(TOUCH_SCALE_NAMES[index], index)
	var manager := _root_node("GameManager")
	var current := 1.0 if manager == null else float(manager.get("touch_controls_scale"))
	var best := 1
	for index: int in range(TOUCH_SCALE_CHOICES.size()):
		if absf(TOUCH_SCALE_CHOICES[index] - current) < absf(TOUCH_SCALE_CHOICES[best] - current):
			best = index
	option.select(best)
	option.item_selected.connect(func(index: int) -> void:
		var target := _root_node("GameManager")
		var id := option.get_item_id(index)
		if target != null and id >= 0 and id < TOUCH_SCALE_CHOICES.size():
			target.call("set_touch_controls_scale", TOUCH_SCALE_CHOICES[id]))


## point（ビューポートの座標）が、root の下の見えている「さわれる UI」（ボタン・入力欄・スライダー、
## と extra_areas に渡した領域）に重なっているか。タッチではホバーが最後に触れた所に残るので、
## gui_get_hovered_control() の代わりにこれで調べる。
static func point_over_controls(root: Node, point: Vector2, extra_areas: Array = []) -> bool:
	for area: Variant in extra_areas:
		var control := area as Control
		if control != null and is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return _point_over_interactive(root, point)


static func _point_over_interactive(node: Node, point: Vector2) -> bool:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return false
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	if node is Viewport and node != node.get_tree().root:
		# 3D の背景などの SubViewport の中は、画面の座標と合わないので見ない
		return false
	if node is Control:
		var control := node as Control
		if (control is BaseButton or control is LineEdit or control is Range) \
				and control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and control.get_global_rect().has_point(point):
			return true
	for child: Node in node.get_children():
		if _point_over_interactive(child, point):
			return true
	return false


## 出ているソフトキーボードの高さ（画面の論理 px）。出ていなければ 0。
static func virtual_keyboard_height(viewport: Viewport) -> float:
	if not is_touch_ui() or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var physical := float(DisplayServer.virtual_keyboard_get_height())
	if physical <= 0.0 or viewport == null:
		return 0.0
	var window := viewport.get_window()
	var scale := window.get_final_transform().get_scale().y if window != null else 1.0
	return physical / maxf(scale, 0.001)


## ボタン・スライダー・選択肢をまとめて押しやすい大きさにする（スマホだけ）。
## スライダーは 56（つまみを大きく描く）、ボタンは 80。compact_options なら OptionButton も 56（行の多い縦の列）。
static func grow_touch_targets(node: Node, compact_options: bool = false) -> void:
	if not is_touch_ui() or node == null:
		return
	if node is Slider:
		# ProgressBar・ScrollBar も Range なので、つまみのあるスライダーだけ
		MobileUi.ensure_touch_size(node as Control, true)
		if node is HSlider:
			enlarge_slider_grabber(node as HSlider)
	elif node is BaseButton:
		MobileUi.ensure_touch_size(node as Control, compact_options and node is OptionButton)
	for child: Node in node.get_children():
		grow_touch_targets(child, compact_options)


## 既定の見た目の HSlider のつまみと溝を、指でつかめる大きさにする（独自描画のスライダーには使わない）。
static func enlarge_slider_grabber(slider: HSlider) -> void:
	if not is_touch_ui() or slider == null:
		return
	var grabber := _circle_texture(36, Color(0.96, 0.97, 1.0))
	var grabber_hot := _circle_texture(36, Color(1.0, 0.88, 0.25))
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber_hot)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.20, 0.24, 0.32)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("slider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(0.36, 0.58, 0.92)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)


static func _circle_texture(diameter: int, color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	gradient.add_point(0.86, color)
	gradient.add_point(0.92, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = diameter
	texture.height = diameter
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	return texture


static func _root_node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))


## SafeArea オートロードの余白（論理 px。"left" / "top" / "right" / "bottom"）。デスクトップと、オートロードが無いときは 0。
## オートロード名を直接書かないのは、エディタがまだ SafeArea を読み込んでいなくてもスクリプトが通るようにするため。
static func safe_inset(side: StringName) -> float:
	var area := _root_node("SafeArea")
	if area == null:
		return 0.0
	return float(area.get(side))


## SafeArea.changed に callback をつなぐ（つないであれば何もしない。オートロードが無ければ何もしない）。
static func connect_safe_area(callback: Callable) -> void:
	var area := _root_node("SafeArea")
	if area != null and area.has_signal("changed") and not area.is_connected("changed", callback):
		area.connect("changed", callback)


static func disconnect_safe_area(callback: Callable) -> void:
	var area := _root_node("SafeArea")
	if area != null and area.is_connected("changed", callback):
		area.disconnect("changed", callback)
