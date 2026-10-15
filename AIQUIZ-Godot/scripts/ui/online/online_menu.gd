class_name OnlineMenu
extends Control

## オンライン対戦の専用メニュー画面。メインメニューのモード選択「オンライン対戦」から来て、
## 試合が終わるとここへ戻る（return_from_match）。
## 画面は「わく（背景・ヘッダー・ステータス）」と「ページ」に分かれていて、ページは
## scripts/ui/online/pages/ に 1 枚ずつある。ページは action_requested で頼みごとをし、
## 通信（NetworkManager）・ページの行き来・試合の開始はこの画面がまとめて受け持つ。
## 背景は 3D の海上ヘリポート（OnlineHeliportStage）。「マッチング開始」からステージが開くまでの演出
## （乗り込み → 離陸 → 検索中の飛行 → 合流 → 並走 → VS カットイン → 読み込み → 中央の線が開く）は
## 監督（OnlineStagingDirector）が 3D を動かし、この画面は UI・通信・読み込み・切り替えを受け持つ。
## 仕様は docs/online_match_staging/spec.md、画面の構成は docs/online_menu.md。

const SCENE_PATH := "res://ui/online_menu.tscn"
const MAIN_MENU_PATH := "res://ui/main_menu.tscn"
const GAME_WORLD_PATH := "res://scenes/game_world.tscn"
## 3D の背景が作れなかったときの VS の長さ（旧 VS の下の帯で始める）
const VS_CARD_SECONDS := 3.0
const PAGE_WIDTH := 520.0
const WIDE_PAGE_WIDTH := 860.0
const CHROME_SLIDE_SECONDS := 0.25
## 乗り込みが始まったとき、ヘリポートの曲を消していく長さ。
const DEPARTURE_MUSIC_FADE_SECONDS := 0.6

const HOME := &"home"
const SEARCH := &"search"
const FRIEND := &"friend"
const VERSUS := &"versus"
const SKIN := &"skin"
## 立っている自分のキャラの横に立てる「スキン設定」の看板：画面で右へ・カメラ側へ寄せる距離（m）
const SKIN_SIGN_SIDE := 2.7
const SKIN_SIGN_FORWARD := 0.35
## スキン設定で選んだパーツを 3D のキャラで光らせる長さと強さ
const SKIN_PULSE_SECONDS := 0.7
const SKIN_PULSE_STRENGTH := 0.55

## 画面の飾りの出し方：menu（ヘッダー＋左の列）、band（下の帯だけ）、staging（左下の小さな「やめる」だけ）、none（なし）
const CHROME_MENU := &"menu"
const CHROME_BAND := &"band"
const CHROME_STAGING := &"staging"
const CHROME_NONE := &"none"

var game_state: QuizGameState
var stage: OnlineHeliportStage = null
var director: OnlineStagingDirector = null
var cutin: OnlineCutin = null
var _pages: Dictionary = {}  # StringName -> OnlineMenuPage
var _stack: Array[StringName] = []
var _title: Label
var _link: Label
var _status: Label
var _back_button: Button
var _header: HBoxContainer
var _frame_root: MarginContainer
var _page_host: VBoxContainer
var _page_wrap: VBoxContainer
var _wide_spacer: Control
var _background: TextureRect
var _stage_view: SubViewportContainer
var _stage_viewport: SubViewport
var _scrim: TextureRect
var _flash: ColorRect
var _fade: ColorRect
## 3D の上だけを暗くする板（急発進のあとの暗転 → 検索中で明ける。監督の fade）。帯や文字はこの上に出る
var _stage_fade: ColorRect
var _small_cancel: Button
var _join_title: Label
var _join_sub: Label
var _chrome: StringName = CHROME_MENU
var _chrome_tween: Tween = null
var _vs_elapsed := 0.0
var _start_sent := false
var _leaving := false
var _cancelling := false
var _matched := false
## L キー（デバッグ版だけ）の仮マッチ中：通信エラーなどで演出が中断されないようにする
var _fake_match := false
## random / friend_host / friend_join
var _search_kind: StringName = &"random"
## ゲーム画面の読み込み（D9）：0 まだ、1 読み込み中、2 済み、3 失敗（change_scene_to_file に切り替える）
var _load_state := 0
var _load_progress := 0.0
var _game_packed: PackedScene = null
var _guest_start: Dictionary = {}
var _peer_waiting := false
## F7（デバッグ版だけ）：左上に演出の状態・経過時間・カメラ・読み込みを出す（仕様書 17）
var _debug_label: Label = null
## トップで、立っている自分のキャラの横の「スキン設定」の看板（3D）。クリックでスキン設定を開く
var _skin_sign_placed := false
var _skin_pulse_part: StringName = &""
var _skin_pulse_t := 0.0
## スキン設定のあいだ、カメラをキャラへ寄せてキャラをカメラへ向かせる
var _skin_closeup: OnlineSkinCloseup = null
## スキン設定で選んでいるパーツ（輪郭を光らせる）と、いま光らせているもの
var _skin_outline_part: StringName = PlayerSkin.ALL
var _skin_outline_shown: StringName = &""


func _ready() -> void:
	game_state = QuizManager.game_state
	# 前の試合で入れ替えた見た目を、メニューで選んだ自分のものへ戻す。
	game_state.reset_net_view()
	if NetworkManager.state != NetworkManager.State.OFFLINE and NetworkManager.state != NetworkManager.State.IDLE:
		# 前の試合の接続が残っていたら閉じてから始める。
		NetworkManager.disconnect_from_relay()
	if GameManager.online_nickname < 0 or GameManager.online_nickname >= NetNicknames.COUNT:
		GameManager.set_online_nickname(NetNicknames.random_id())
	if not NetNameFilter.is_ok(GameManager.online_name):
		# 初めてのときは二つ名を 1 つ振っておく（入力欄を空のまま待たせない）。
		GameManager.set_online_name(NetEpithets.roll())
	GraphicsQuality.reset_window_3d_quality(get_viewport())
	_build_frame()
	_setup_stage()
	_add_page(HOME, OnlineHomePage.new())
	_add_page(SEARCH, OnlineSearchPage.new())
	_add_page(FRIEND, OnlineFriendPage.new())
	_add_page(VERSUS, OnlineVersusPage.new())
	_add_page(SKIN, OnlineSkinPage.new())
	_build_overlays()
	_connect_network()
	_update_link(NetworkManager.state)
	go(HOME)
	# ゲーム画面の読み込みとカットインのキャラ絵の初回の描画（シェーダーの準備）は、マッチング演出の途中でやると
	# そのフレームが重くなる（早いマッチでは合流の最中になる）。この画面が開く覆いの下で先に済ませておく。
	_begin_loading()
	if cutin != null:
		cutin.prime(_cutin_info())
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)
	# VS 演出の効果音は鳴らすときに読み込むと演出が止まるので、ここで読んでおく
	AudioManager.preload_sfx(AudioManager.VERSUS_SFX_CUES)
	SceneTransition.reveal_current()


## 試合のあと（結果画面・切断パネル）からこの画面へ戻る。呼ぶ側で先に画面を覆っておく。
static func return_from_match(tree: SceneTree) -> void:
	NetworkManager.leave_match()
	QuizManager.game_state.reset_to_menu()
	tree.change_scene_to_file(SCENE_PATH)


func _process(dt: float) -> void:
	_update_skin_sign()
	_update_skin_pulse(dt)
	_update_skin_closeup()
	_poll_loading()
	if _debug_label != null and _debug_label.visible and director != null:
		_debug_label.text = "%s  %.2f s
%s
load %d (%.0f%%)  fps %d" % [director.state_name(), director.state_time, director.shot_name,
			_load_state, loading_progress() * 100.0, Engine.get_frames_per_second()]
	if director != null:
		if _stage_fade != null:
			_stage_fade.color.a = director.fade
		director.loaded = _load_state >= 2
		director.peer_ok = not _peer_waiting
		if cutin != null:
			cutin.set_progress(loading_progress(), _peer_waiting)
		return
	# 3D の背景が作れなかったとき：旧 VS の下の帯で数えて始める
	if current_id() != VERSUS:
		return
	_vs_elapsed += dt
	var versus := page(VERSUS) as OnlineVersusPage
	var left := maxi(0, ceili(VS_CARD_SECONDS - _vs_elapsed))
	versus.set_info("まもなく スタート！ %d" % left if left > 0 else ("スタート！" if NetworkManager.is_host else "じゅんび中…"))
	if NetworkManager.is_host and _vs_elapsed >= VS_CARD_SECONDS and not _start_sent:
		_start_online_game()
		_transition_to_game()


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo 			and (event as InputEventKey).keycode == KEY_F7:
		_toggle_debug()
		return
	if OS.is_debug_build() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo 			and (event as InputEventKey).keycode == KEY_L:
		get_viewport().set_input_as_handled()
		_debug_fake_match()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()
	elif event.is_action_pressed("ui_accept") and director != null and director.state in [
			OnlineStagingDirector.State.BOARDING, OnlineStagingDirector.State.COCKPIT,
			OnlineStagingDirector.State.TAKEOFF, OnlineStagingDirector.State.CLIMB]:
		# Enter／A：その状態の終わりまで 2 倍速（仕様書 14）
		get_viewport().set_input_as_handled()
		director.hurry()


## L キー（デバッグ版だけ）：仮の相手とマッチしたことにして、合流 → 並走 → VS カットイン → ゲーム画面（カウントダウン）へ進む。
## 検索中（や乗り込み中・ホーム）から押せる。通信は閉じ、自分がホストの試合として始める。
func _debug_fake_match() -> void:
	if director == null or _fake_match or _matched or _leaving or _cancelling or SceneTransition.is_transitioning():
		return
	if director.is_committed() or current_id() in [FRIEND, VERSUS, SKIN]:
		return
	_fake_match = true
	_matched = true
	_start_sent = false
	_guest_start = {}
	_peer_waiting = false
	if _small_cancel != null:
		_small_cancel.visible = false
	var profile := {
		"nick": NetNicknames.random_id(),
		"name": "テストの あいて",
		"hat": randi_range(HatData.HAT_NONE + 1, HatData.HAT_COUNT - 1),
		"toon": game_state.p1_toon_preset,
		"emotes": [1, 2, 3],
		"skin": "",
	}
	NetworkManager.debug_fake_match(profile, _queue_settings())
	set_status("")
	_begin_loading()
	director.on_matched(1, NetworkManager.opponent_profile)


func _toggle_debug() -> void:
	if _debug_label == null:
		_debug_label = OnlineMenuStyle.label("", 16, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
		_debug_label.name = "StagingDebug"
		OnlineMenuStyle.shadow(_debug_label)
		_debug_label.position = Vector2(12, 8)
		_debug_label.visible = false
		add_child(_debug_label)
	_debug_label.visible = not _debug_label.visible


# ---------- わく（背景・ヘッダー・ステータス） ----------

func _build_frame() -> void:
	# 3D が作れなかったときの背景（3D の下に敷いておく）
	_background = TextureRect.new()
	_background.name = "Background"
	_background.texture = OnlineMenuStyle.background_texture()
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)
	_stage_view = SubViewportContainer.new()
	_stage_view.name = "StageView"
	_stage_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_view.stretch = true
	_stage_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage_view)
	_stage_viewport = SubViewport.new()
	_stage_viewport.name = "StageViewport"
	_stage_viewport.own_world_3d = true
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_stage_view.add_child(_stage_viewport)
	_stage_fade = ColorRect.new()
	_stage_fade.name = "StageFade"
	_stage_fade.color = Color(0, 0, 0, 0)
	_stage_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage_fade)
	# 左の列の文字を読みやすくする暗いぼかし（右へ透明になる）
	_scrim = TextureRect.new()
	_scrim.name = "Scrim"
	_scrim.texture = OnlineMenuStyle.scrim_texture()
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_frame_root = MarginContainer.new()
	_frame_root.name = "Frame"
	_frame_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		_frame_root.add_theme_constant_override(side, 40)
	for side in ["margin_top", "margin_bottom"]:
		_frame_root.add_theme_constant_override(side, 24)
	add_child(_frame_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_frame_root.add_child(column)

	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.add_theme_constant_override("separation", 20)
	column.add_child(_header)
	_back_button = OnlineMenuStyle.button("← もどる", Vector2(170, 50), 18)
	_back_button.pressed.connect(back)
	_header.add_child(_back_button)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(titles)
	var kicker := OnlineMenuStyle.label("ONLINE BATTLE", 14, OnlineMenuStyle.ACCENT_ONLINE, HORIZONTAL_ALIGNMENT_LEFT)
	OnlineMenuStyle.shadow(kicker)
	titles.add_child(kicker)
	_title = OnlineMenuStyle.label("", 32, OnlineMenuStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	OnlineMenuStyle.shadow(_title)
	titles.add_child(_title)
	_link = OnlineMenuStyle.label("", 15, OnlineMenuStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	OnlineMenuStyle.shadow(_link)
	_header.add_child(_link)

	# 本文：ふだんは左の列。wide_layout のページ（検索中・VS）は下のまん中の帯
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_wide_spacer = Control.new()
	_wide_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wide_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wide_spacer.visible = false
	body.add_child(_wide_spacer)
	_page_wrap = VBoxContainer.new()
	_page_wrap.name = "PageColumn"
	_page_wrap.custom_minimum_size = Vector2(PAGE_WIDTH, 0)
	_page_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_page_wrap.add_theme_constant_override("separation", 12)
	body.add_child(_page_wrap)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	_page_host = VBoxContainer.new()
	_page_host.name = "Pages"
	_page_wrap.add_child(_page_host)
	_status = OnlineMenuStyle.wrap_label("", 16, OnlineMenuStyle.WARN)
	OnlineMenuStyle.shadow(_status)
	_page_wrap.add_child(_status)


# ---------- スキン設定（立っているキャラの横の看板） ----------

func _skin_sign() -> OnlineSkinSign:
	return stage.skin_sign if stage != null else null


## トップとスキン設定のあいだ、自分のキャラの右横に看板を立てておく（押してスキン設定を開いても立ったまま）。
## 置き場所はトップで立てたときのカメラから決め、しまうまで動かさない。
func _update_skin_sign() -> void:
	var board := _skin_sign()
	if board == null:
		return
	var idle := director == null or director.state == OnlineStagingDirector.State.IDLE
	var show := (current_id() == HOME or current_id() == SKIN) and _chrome == CHROME_MENU and idle and not _leaving and not _cancelling and stage.me().is_ready() and not stage.flow_enabled
	if not show:
		_skin_sign_placed = false
		if board.is_shown():
			board.set_shown(false)
			_set_skin_sign_hover(false)
		return
	if not _skin_sign_placed:
		_place_skin_sign(board)
		_skin_sign_placed = true
	board.set_shown(true)


## キャラの足元から、画面で右へ SKIN_SIGN_SIDE・カメラ側へ SKIN_SIGN_FORWARD の床に、カメラへ向けて立てる。
func _place_skin_sign(board: OnlineSkinSign) -> void:
	var camera := stage.camera
	var pelvis := stage.me().parts().get("pelvis") as Node3D
	if camera == null or pelvis == null:
		return
	var base := pelvis.global_position
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var to_camera := camera.global_position - base
	to_camera.y = 0.0
	to_camera = to_camera.normalized() if to_camera.length_squared() > 0.0001 else Vector3.BACK
	var spot := base + right * SKIN_SIGN_SIDE + to_camera * SKIN_SIGN_FORWARD
	spot.y = stage.pad_ground.origin.y
	var face := camera.global_position - spot
	board.global_transform = Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), spot)


## マウス（タッチ）で看板を指す・押す。ページの列やボタンの上では反応しない。
func _input(event: InputEvent) -> void:
	var board := _skin_sign()
	if board == null or not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	if not board.is_shown() or current_id() != HOME:
		# 押せるのはトップのときだけ（スキン設定の間は立っているだけ）
		_set_skin_sign_hover(false)
		return
	var point := (make_input_local(event) as InputEventMouse).position
	var hit := not _pointer_over_ui() and _skin_sign_hit(point)
	_set_skin_sign_hover(hit)
	var button := event as InputEventMouseButton
	if hit and button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		get_viewport().set_input_as_handled()
		_set_skin_sign_hover(false)
		_on_page_action(&"skin", {})


## 画面の点（この画面の座標）が看板に当たるか。
func _skin_sign_hit(screen_position: Vector2) -> bool:
	var board := _skin_sign()
	if board == null or stage.camera == null or _stage_view.scale.x <= 0.0 or _stage_view.scale.y <= 0.0:
		return false
	var view_position := (screen_position - _stage_view.position) / _stage_view.scale
	return board.hit_test(stage.camera.project_ray_origin(view_position), stage.camera.project_ray_normal(view_position))


## カーソルの下が左の列（ページ）やボタンなど、触れる UI か。
func _pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered == self:
		return false
	if hovered is BaseButton or hovered is LineEdit or hovered is Range:
		return true
	return _page_wrap != null and (hovered == _page_wrap or _page_wrap.is_ancestor_of(hovered))


func _set_skin_sign_hover(value: bool) -> void:
	var board := _skin_sign()
	if board == null or board.hovered == value:
		return
	board.set_hovered(value)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if value else Input.CURSOR_ARROW)


## スキン設定のあいだだけ、カメラを寄せ、選んでいるパーツの輪郭を光らせる。
func _update_skin_closeup() -> void:
	var editing := current_id() == SKIN and not _leaving
	if _skin_closeup != null:
		_skin_closeup.active = editing
	if stage == null or not stage.me().is_ready():
		return
	var outline := _skin_outline_part if editing else &""
	if outline != _skin_outline_shown:
		_skin_outline_shown = outline
		var puppet := stage.me()
		puppet.controller.set_skin_outline(puppet.index, outline)


## スキン設定で選んだパーツを、立っているキャラの上で短く光らせる。
func _update_skin_pulse(dt: float) -> void:
	if _skin_pulse_t <= 0.0 or stage == null or not stage.me().is_ready():
		return
	_skin_pulse_t = maxf(_skin_pulse_t - dt, 0.0)
	var phase := _skin_pulse_t / SKIN_PULSE_SECONDS
	var puppet := stage.me()
	puppet.controller.set_skin_highlight_map(puppet.index, {_skin_pulse_part: SKIN_PULSE_STRENGTH * phase * phase})


## 演出の上に載せるもの：左下の小さな「やめる」、合流の文字、カットイン、暗転。
func _build_overlays() -> void:
	_small_cancel = OnlineMenuStyle.button("やめる", Vector2(130, 46), 18)
	_small_cancel.name = "StagingCancel"
	_small_cancel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_small_cancel.position = Vector2(32, -78)
	_small_cancel.anchor_top = 1.0
	_small_cancel.anchor_bottom = 1.0
	_small_cancel.offset_top = -78
	_small_cancel.offset_bottom = -32
	_small_cancel.offset_left = 32
	_small_cancel.offset_right = 162
	_small_cancel.visible = false
	_small_cancel.pressed.connect(cancel_search)
	add_child(_small_cancel)
	_join_title = OnlineMenuStyle.label("あいてが みつかった！", 56, OnlineMenuStyle.ACCENT)
	_join_title.name = "JoinTitle"
	OnlineMenuStyle.shadow(_join_title)
	_join_title.add_theme_constant_override("outline_size", 14)
	_join_title.add_theme_color_override("font_outline_color", Color("#1b2a41"))
	_join_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_join_title.anchor_left = 0.0
	_join_title.anchor_right = 1.0
	_join_title.offset_top = 70
	_join_title.offset_bottom = 150
	_join_title.visible = false
	add_child(_join_title)
	_join_sub = OnlineMenuStyle.label("きみは ブルー", 34, PlayerController.P2_BODY.lightened(0.25))
	_join_sub.name = "JoinSub"
	OnlineMenuStyle.shadow(_join_sub)
	_join_sub.add_theme_constant_override("outline_size", 10)
	_join_sub.add_theme_color_override("font_outline_color", Color("#1b2a41"))
	_join_sub.anchor_left = 0.0
	_join_sub.anchor_right = 1.0
	_join_sub.offset_top = 150
	_join_sub.offset_bottom = 200
	_join_sub.visible = false
	add_child(_join_sub)
	if director != null:
		cutin = OnlineCutin.new()
		cutin.name = "Cutin"
		cutin.set_anchors_preset(Control.PRESET_FULL_RECT)
		cutin.visible = false
		add_child(cutin)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


## 3D の背景（海上ヘリポート）と演出の監督。作れなければ 2D の背景のまま（旧 VS の流れ）。
func _setup_stage() -> void:
	stage = OnlineHeliportStage.new()
	stage.name = "Heliport"
	_stage_viewport.add_child(stage)
	if not stage.build(GameManager.graphics_quality):
		stage.queue_free()
		stage = null
		_stage_view.visible = false
		_scrim.visible = false
		return
	director = OnlineStagingDirector.new()
	director.name = "StagingDirector"
	add_child(director)
	director.short_mode = _short_staging()
	director.setup(stage)
	director.departure_started.connect(_on_departure_started)
	director.cruise_started.connect(_on_cruise_started)
	director.join_started.connect(_on_join_started)
	director.cutin_started.connect(_on_cutin_started)
	director.hold_started.connect(_on_hold_started)
	director.swap_ready.connect(_on_swap_ready)
	director.requeue_finished.connect(_on_requeue_finished)
	_skin_closeup = OnlineSkinCloseup.new()
	_skin_closeup.stage = stage
	_skin_closeup.director = director
	add_child(_skin_closeup)
	_update_stage_viewport_quality()
	get_window().size_changed.connect(_update_stage_viewport_quality)
	if not GameManager.graphics_quality_changed.is_connected(_on_graphics_quality_changed):
		GameManager.graphics_quality_changed.connect(_on_graphics_quality_changed)


## 設定「オンラインの えんしゅつ：みじかい」（D11）。
func _short_staging() -> bool:
	return GameManager.online_staging_short


## 3D の背景を画面の実解像度で描く（メインメニューと同じ。大きすぎる画面は上限まで）。
func _update_stage_viewport_quality() -> void:
	if _stage_view == null or _stage_viewport == null or stage == null:
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	if logical.x <= 0.0 or logical.y <= 0.0:
		return
	var target: Vector2 = logical * get_window().get_final_transform().get_scale()
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var max_w: float = 1280.0 if is_mobile else 3840.0
	if target.x > max_w:
		target *= max_w / target.x
	target.x = maxf(target.x, 640.0)
	target.y = maxf(target.y, 360.0)
	_stage_view.stretch_shrink = 1
	_stage_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_stage_view.position = Vector2.ZERO
	_stage_view.size = target
	_stage_view.scale = logical / target
	GraphicsQuality.apply_text_viewport(_stage_viewport, GameManager.graphics_quality)


func _on_graphics_quality_changed(quality: String) -> void:
	if stage != null:
		stage.apply_graphics_quality(quality)
	_update_stage_viewport_quality()


## ページの置き方：ふだんは左の列、wide はまん中の下の帯（左のぼかしも消す）。
func _apply_layout(wide: bool) -> void:
	_wide_spacer.visible = wide
	_page_wrap.custom_minimum_size.x = WIDE_PAGE_WIDTH if wide else PAGE_WIDTH
	_page_wrap.size_flags_vertical = Control.SIZE_SHRINK_END if wide else Control.SIZE_SHRINK_CENTER
	_set_chrome(CHROME_BAND if wide else CHROME_MENU)


## 画面の飾りを切り替える。menu ⇄ staging は左へすべって消える（0.25 秒）。
func _set_chrome(mode: StringName) -> void:
	if mode == _chrome:
		return
	var previous := _chrome
	_chrome = mode
	if _chrome_tween != null:
		_chrome_tween.kill()
	_header.visible = mode == CHROME_MENU
	if _scrim != null:
		_scrim.visible = mode == CHROME_MENU and stage != null
	if _small_cancel != null:
		_small_cancel.visible = mode == CHROME_STAGING and not _matched
	match mode:
		CHROME_MENU, CHROME_BAND:
			_frame_root.visible = true
			_frame_root.position = Vector2.ZERO
			_frame_root.modulate.a = 1.0
			if mode == CHROME_BAND and previous != CHROME_MENU:
				# 下の帯は下から 0.3 秒で出る
				_frame_root.position = Vector2(0, 80)
				_frame_root.modulate.a = 0.0
				_chrome_tween = create_tween().set_parallel(true)
				_chrome_tween.tween_property(_frame_root, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_chrome_tween.tween_property(_frame_root, "modulate:a", 1.0, 0.3)
		CHROME_STAGING, CHROME_NONE:
			if not _frame_root.visible:
				return
			_chrome_tween = create_tween().set_parallel(true)
			if previous == CHROME_BAND:
				_chrome_tween.tween_property(_frame_root, "position:y", 80.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				_chrome_tween.tween_property(_frame_root, "modulate:a", 0.0, 0.3)
			else:
				_chrome_tween.tween_property(_frame_root, "position:x", -220.0, CHROME_SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				_chrome_tween.tween_property(_frame_root, "modulate:a", 0.0, CHROME_SLIDE_SECONDS)
			_chrome_tween.chain().tween_callback(func() -> void: _frame_root.visible = false)


func chrome() -> StringName:
	return _chrome


func _add_page(id: StringName, new_page: OnlineMenuPage) -> void:
	new_page.name = String(id).capitalize().replace(" ", "") + "Page"
	new_page.visible = false
	new_page.action_requested.connect(_on_page_action)
	_page_host.add_child(new_page)
	_pages[id] = new_page


func set_status(text: String) -> void:
	_status.text = text


func _update_link(state: int) -> void:
	var text := "● オフライン"
	var color := OnlineMenuStyle.MUTED
	match state:
		NetworkManager.State.CONNECTING:
			text = "● つないでいます…"
			color = OnlineMenuStyle.WARN
		NetworkManager.State.RECONNECTING:
			text = "● つなぎなおしています…"
			color = OnlineMenuStyle.WARN
		NetworkManager.State.IDLE, NetworkManager.State.QUEUED, NetworkManager.State.IN_LOBBY, NetworkManager.State.IN_GAME:
			text = "● サーバーと つながっています"
			color = OnlineMenuStyle.ACCENT_ONLINE
	_link.text = text
	_link.add_theme_color_override("font_color", color)


# ---------- ページの行き来 ----------

func page(id: StringName) -> OnlineMenuPage:
	return _pages.get(id) as OnlineMenuPage


func current_id() -> StringName:
	return _stack[-1] if not _stack.is_empty() else &""


## id のページを出す。すでに通ってきたページなら、そこまで戻る。
func go(id: StringName, args: Dictionary = {}) -> void:
	var at := _stack.find(id)
	if at >= 0:
		_stack.resize(at + 1)
	else:
		_stack.append(id)
	for key: StringName in _pages:
		var each := _pages[key] as OnlineMenuPage
		if each.visible and key != id:
			each.leave()
		each.visible = key == id
	var shown := page(id)
	_title.text = shown.page_title()
	_status.text = ""
	_apply_layout(shown.wide_layout())
	shown.enter(args)
	var focus := shown.default_focus()
	if focus != null:
		focus.grab_focus.call_deferred()


## ホームからやり直す（さがすのを やめた・あいてが いなくなった など）。
func go_home(status: String = "") -> void:
	_stack.clear()
	go(HOME)
	_status.text = status
	# 検索をやめた・失敗した・時間切れで戻るときは、ヘリポートのトップの曲（メニュー曲）を元の音量で流す。
	AudioManager.set_music_track(AudioManager.MUSIC_TRACK_MENU)
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)


func back() -> void:
	if _leaving or _cancelling or SceneTransition.is_transitioning():
		return
	if director != null and director.state != OnlineStagingDirector.State.IDLE:
		# 演出中：合流より前なら「やめる」、合流のあとは受け付けない（仕様書 14）
		if not _matched and not director.is_committed():
			cancel_search()
		return
	var shown := page(current_id())
	if shown != null and shown.handle_back():
		return
	if current_id() == VERSUS:
		NetworkManager.leave_match()
		go_home()
		return
	if _stack.size() > 1:
		go(_stack[-2])
		return
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	_leaving = true
	if NetworkManager.is_in_match():
		NetworkManager.leave_match()
	else:
		NetworkManager.disconnect_from_relay()
	game_state.back_to_mode_select()
	SceneTransition.change_scene(MAIN_MENU_PATH, Color.BLACK, SceneTransition.WipeStyle.DATA)


func _on_page_action(action: StringName, data: Dictionary) -> void:
	match action:
		&"find":
			find_match()
		&"friend":
			go(FRIEND)
		&"friend_create":
			create_friend_room()
		&"friend_join":
			join_friend_room(str(data.get("code", "")))
		&"cancel":
			cancel_search()
		&"skin":
			_skin_outline_part = PlayerSkin.ALL
			go(SKIN)
		&"skin_done":
			go_home()
		&"skin_look":
			if stage != null:
				stage.me().set_skin(data.get("skin", {}))
		&"skin_hat":
			if stage != null:
				stage.me().set_hat(int(data.get("hat", HatData.HAT_NONE)))
		&"skin_part":
			_skin_pulse_part = StringName(str(data.get("part", "")))
			_skin_pulse_t = SKIN_PULSE_SECONDS
			_skin_outline_part = _skin_pulse_part


# ---------- マッチング ----------

func find_match() -> void:
	_search_kind = &"random"
	_begin_departure()
	set_status("サーバーに つないでいます…")
	NetworkManager.find_match(_queue_settings(), _local_profile())


func create_friend_room() -> void:
	_search_kind = &"friend_host"
	NetworkManager.friend_code = ""
	_begin_departure()
	set_status("コードを つくっています…")
	NetworkManager.create_friend_room(_queue_settings(), _local_profile())


func join_friend_room(code: String) -> void:
	if code.length() != OnlineFriendPage.CODE_LENGTH:
		set_status("コードは %dもじ です" % OnlineFriendPage.CODE_LENGTH)
		return
	_search_kind = &"friend_join"
	_begin_departure()
	set_status("さがしています…")
	NetworkManager.join_friend_room(code, _local_profile())


## マッチング開始：3D があれば乗り込みの演出から、なければ検索のページへ。
func _begin_departure() -> void:
	_matched = false
	_fake_match = false
	_start_sent = false
	_guest_start = {}
	_peer_waiting = false
	if director == null:
		# 3D の演出が作れないときは、乗り込みなしでそのまま検索中の画面へ（待機用の曲を流す）。
		_play_match_music()
		if _search_kind == &"friend_host":
			go(SEARCH, {"friend": true, "code": NetworkManager.friend_code})
		else:
			go(SEARCH, {"friend": _search_kind != &"random"})
		return
	director.short_mode = _short_staging()
	director.begin_departure()


func cancel_search() -> void:
	_cancel_staging("")


## やめる・失敗・時間切れ：0.35 秒の暗転でヘリポートの待機へ戻す（D4。逆再生はしない）。
func _cancel_staging(status: String) -> void:
	if _cancelling:
		return
	if NetworkManager.is_in_match():
		NetworkManager.leave_match()
	else:
		NetworkManager.cancel_search()
	_matched = false
	_fake_match = false
	if director == null or director.state == OnlineStagingDirector.State.IDLE:
		go_home(status)
		return
	_cancelling = true
	var half := OnlineStagingTimeline.CANCEL_FADE_SECONDS * 0.43
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, half)
	tween.tween_callback(func() -> void:
		director.reset_to_idle()
		_hide_staging_texts()
		if cutin != null:
			cutin.hide_now()
		go_home(status))
	tween.tween_property(_fade, "color:a", 0.0, OnlineStagingTimeline.CANCEL_FADE_SECONDS - half)
	tween.tween_callback(func() -> void: _cancelling = false)


func _queue_settings() -> Dictionary:
	var difficulty := Constants.DIFFICULTY_LEVELS.find(game_state.difficulty)
	return {
		"subject": game_state.subject,
		"grade": game_state.grade,
		"difficulty": maxi(difficulty, 0),
		"mode": Constants.MODE_TEN,
	}


func _local_profile() -> Dictionary:
	return {
		"nick": GameManager.online_nickname,
		"name": GameManager.online_name,
		"hat": game_state.p1_hat,
		"toon": game_state.p1_toon_preset,
		"emotes": Array(game_state.p1_emote_slots),
		# 体の塗り。ゲーム状態は試合中に相手の見た目で上書きされるので保存側から取る（標準色は ""）。
		"skin": PlayerSkinStore.get_skin_code(1),
	}


## 相手に見える自分のなまえ（リレーが使えないと判断したらニックネームになる）。
func shown_own_name() -> String:
	var mine: Dictionary = NetworkManager.match_you
	var accepted := str(mine.get("name", GameManager.online_name))
	return accepted if not accepted.is_empty() else NetNicknames.name_for(GameManager.online_nickname)


func rules_text() -> String:
	var s := NetworkManager.match_settings
	return "%s ・ %d年 ・ %s" % [s.get("subject", game_state.subject), int(s.get("grade", game_state.grade)),
		_difficulty_name(int(s.get("difficulty", 1)))]


# ---------- 演出の合図 ----------

func _on_departure_started() -> void:
	_set_chrome(CHROME_STAGING)
	# 乗り込みから離陸・急発進して暗転しきるまでは、BGM を止めずに音量を下げて、ヘリの効果音を聞かせる。
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_ONLINE_STAGING, DEPARTURE_MUSIC_FADE_SECONDS)


func _on_cruise_started() -> void:
	if _matched:
		return
	# 暗転が明けてマッチング待機（検索中）に入ったら、待機用の曲を元の音量で流す。
	_play_match_music()
	if _search_kind == &"friend_host":
		go(SEARCH, {"friend": true, "code": NetworkManager.friend_code})
	else:
		go(SEARCH, {"friend": _search_kind == &"friend_join"})
	_begin_loading()


func _on_join_started(is_guest: bool) -> void:
	_set_chrome(CHROME_NONE)
	_begin_loading()
	# カットインのキャラ絵をここで先に描いておく（カットインの入りのフレームを軽くする）
	if cutin != null:
		cutin.prime(_cutin_info())
	var j: Dictionary = OnlineStagingTimeline.JOIN
	_pop_text(_join_title, float(j.title_in), float(j.title_out))
	if is_guest:
		_pop_text(_join_sub, float(j.you_blue_in), float(j.you_blue_out))


func _on_cutin_started() -> void:
	if cutin == null:
		return
	cutin.play(_cutin_info())


## カットインに渡す中身（名前・ルール・帽子・スキン・ポーズ）。
func _cutin_info() -> Dictionary:
	return {
		"me": shown_own_name(),
		"them": NetworkManager.opponent_name,
		"rules": rules_text(),
		"my_slot": director.my_slot,
		"my_hat": game_state.p1_hat,
		"their_hat": int(NetworkManager.opponent_profile.get("hat", 0)),
		"my_skin": PlayerSkinStore.get_skin(1),
		"their_skin": PlayerSkin.from_code(NetworkManager.opponent_skin_code),
		"short": director.short_mode,
	}


func _on_hold_started() -> void:
	if NetworkManager.is_host:
		_start_online_game()
		director.start_ready = true
	else:
		director.start_ready = not _guest_start.is_empty()


func _on_swap_ready() -> void:
	if not NetworkManager.is_host and not _guest_start.is_empty():
		_apply_guest_start(_guest_start)
	if cutin != null and cutin.visible:
		# 覆い（静止画と、その上で動き続けるカットイン）を「準備ができた」絵にするため、
		# ゲージを満たして 1 回描いてから写す
		cutin.show_ready()
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
	_transition_to_game()


func _on_requeue_finished() -> void:
	go(SEARCH, {"friend": false})
	_play_match_music()


## マッチング待機の曲に替えて、音量を元に戻す。曲を先に替えるのは、新しい曲を下げた音量から立ち上げるため。
func _play_match_music() -> void:
	AudioManager.set_music_track(AudioManager.MUSIC_TRACK_MATCH)
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)


## 文字をぽんと出して（縮尺 0.6 → 1.08 → 1.0）、out 秒で消す。時刻は呼んだときから。
func _pop_text(label: Label, at: float, out: float) -> void:
	label.visible = true
	label.modulate.a = 0.0
	label.pivot_offset = Vector2(label.size.x * 0.5, label.size.y * 0.5)
	label.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_interval(at)
	tween.tween_property(label, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(label, "scale", Vector2(1.08, 1.08), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15)
	tween.tween_interval(maxf(0.0, out - at - 0.35))
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void: label.visible = false)


func _hide_staging_texts() -> void:
	for label: Label in [_join_title, _join_sub]:
		label.visible = false


# ---------- 読み込み（D9） ----------

func _begin_loading() -> void:
	if _load_state != 0:
		return
	# 副スレッドは使わない（use_sub_threads = true だと、スクリプトの preload が別スレッドの読み込みと競合して失敗する）
	if ResourceLoader.load_threaded_request(GAME_WORLD_PATH, "PackedScene", false) == OK:
		_load_state = 1
	else:
		_load_state = 3


func _poll_loading() -> void:
	if _load_state != 1:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_WORLD_PATH, progress)
	if not progress.is_empty():
		_load_progress = float(progress[0])
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_game_packed = ResourceLoader.load_threaded_get(GAME_WORLD_PATH) as PackedScene
			_load_state = 2 if _game_packed != null else 3
			_load_progress = 1.0
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_state = 3


## ゲージの進み（仕様書 S9）：読み込み 0〜60%、開始の合図まで 90%（数字は出さない）。
func loading_progress() -> float:
	var p := 0.6 * (_load_progress if _load_state == 1 else (1.0 if _load_state >= 2 else 0.0))
	if _load_state == 3:
		p = 0.6
	if director != null and director.start_ready:
		p = maxf(p, 0.6) + 0.3 if _load_state >= 2 else p
	return clampf(p, 0.0, 0.9)


func is_game_loaded() -> bool:
	return _load_state >= 2


# ---------- 通信 ----------

func _connect_network() -> void:
	for pair in _network_handlers():
		(pair[0] as Signal).connect(pair[1])


func _exit_tree() -> void:
	# 看板を指したまま画面を離れても、指の形のカーソルを残さない
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	for pair in _network_handlers():
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _network_handlers() -> Array:
	return [
		[NetworkManager.state_changed, _update_link],
		[NetworkManager.connection_failed, _on_connection_failed],
		[NetworkManager.queued, _on_queued],
		[NetworkManager.queue_timeout, _on_queue_timeout],
		[NetworkManager.friend_code_received, _on_friend_code],
		[NetworkManager.matched, _on_matched],
		[NetworkManager.error_received, _on_error],
		[NetworkManager.peer_paused, _on_peer_paused],
		[NetworkManager.peer_resumed, _on_peer_resumed],
		[NetworkManager.peer_left, _on_peer_left],
		[NetworkManager.forfeit_received, _on_forfeit],
		[NetworkManager.reconnect_failed, _on_reconnect_failed],
		[NetworkManager.relay_message, _on_relay_message],
	]


func _staging() -> bool:
	return director != null and director.state != OnlineStagingDirector.State.IDLE


func _on_connection_failed(reason: String) -> void:
	if _fake_match:
		return
	if _staging():
		_cancel_staging(reason)
	else:
		go_home(reason)


func _on_queued() -> void:
	set_status("")


func _on_queue_timeout() -> void:
	if _fake_match:
		return
	var text := "いまは あいてが いないみたい。また あとで ためしてね"
	if _staging():
		_cancel_staging(text)
	else:
		go_home(text)


func _on_friend_code(code: String) -> void:
	(page(SEARCH) as OnlineSearchPage).show_code(code)
	set_status("")


func _on_error(code: String) -> void:
	if _fake_match:
		return
	var text := ""
	match code:
		"friend_not_found":
			text = "その コードの へやは みつかりません"
		"bad_settings":
			text = "この せっていでは たいせんできません"
		"too_many_connections", "rate_limited":
			text = "いまは こみあっています。すこし まってね"
		_:
			set_status("エラー: %s" % code)
			return
	if _staging():
		_cancel_staging(text)
	else:
		go_home(text)


func _on_matched(info: Dictionary) -> void:
	_matched = true
	_start_sent = false
	_vs_elapsed = 0.0
	_guest_start = {}
	_peer_waiting = false
	if _small_cancel != null:
		_small_cancel.visible = false
	var you: Dictionary = info.get("you", {})
	if director == null:
		_stack.assign([HOME])
		go(VERSUS, {"me": shown_own_name(), "them": NetworkManager.opponent_name, "rules": rules_text(), "arriving": false})
	else:
		# 早めのマッチ（検索中の飛行より前）は、ここで読み込みを始める（D9。合流まで待つと開くのが遅れる）
		_begin_loading()
		director.on_matched(1 if NetworkManager.is_host else 2, NetworkManager.opponent_profile)
	if not GameManager.online_name.is_empty() and str(you.get("name", "")).is_empty():
		set_status("なまえが つかえなかったので「%s」に なったよ" % shown_own_name())


func _on_peer_paused(_who: String, _grace: float) -> void:
	_peer_waiting = true
	if director == null and current_id() == VERSUS:
		(page(VERSUS) as OnlineVersusPage).set_info("あいての つうしんを まっています…")


func _on_peer_resumed(_who: String) -> void:
	_peer_waiting = false
	if NetworkManager.is_host and _start_sent:
		# 開始通知を受け取れなかったかもしれないので送り直す。
		NetworkManager.send("start", _start_payload())


func _on_peer_left(_who: String) -> void:
	_on_opponent_gone()


func _on_forfeit(_winner: String, _reason: String) -> void:
	_on_opponent_gone()


## 試合が始まる前に相手がいなくなった：ランダムマッチなら空のまま 1 回だけ探し直す（D12）。
func _on_opponent_gone() -> void:
	if _fake_match:
		return
	if director != null and director.is_committed() and director.state < OnlineStagingDirector.State.SWAP \
			and _search_kind == &"random" and director.requeue():
		NetworkManager.leave_match()
		_matched = false
		_start_sent = false
		_guest_start = {}
		_peer_waiting = false
		if cutin != null:
			cutin.hide_now()
		_hide_staging_texts()
		NetworkManager.find_match(_queue_settings(), _local_profile())
		return
	if director != null and director.state >= OnlineStagingDirector.State.SWAP:
		return
	NetworkManager.disconnect_from_relay()
	if _staging():
		_cancel_staging("あいてが いなくなりました")
	else:
		go_home("あいてが いなくなりました")


func _on_reconnect_failed(reason: String) -> void:
	if _leaving or _fake_match:
		return
	if _staging():
		_cancel_staging(reason)
	else:
		go_home(reason)


func _on_relay_message(msg_type: String, data: Dictionary) -> void:
	if msg_type != "start" or NetworkManager.is_host:
		return
	_guest_start = data
	if director == null:
		_apply_guest_start(data)
		_transition_to_game()
	elif director.state >= OnlineStagingDirector.State.CUTIN_HOLD:
		director.start_ready = true


# ---------- 試合の開始 ----------

func _start_payload() -> Dictionary:
	return {
		"subject": game_state.subject,
		"grade": game_state.grade,
		"difficulty": game_state.difficulty,
		"mode": game_state.mode,
		"llm_mode": game_state.llm_mode,
	}


func _apply_match_settings() -> void:
	var s := NetworkManager.match_settings
	game_state.num_players = 2
	game_state.select_mode_and_continue(Constants.MODE_TEN)
	game_state.subject = str(s.get("subject", game_state.subject))
	game_state.grade = Constants.normalize_grade_for_subject(game_state.subject, int(s.get("grade", game_state.grade)))
	var difficulty_index := clampi(int(s.get("difficulty", 1)), 0, Constants.DIFFICULTY_LEVELS.size() - 1)
	game_state.difficulty = Constants.DIFFICULTY_LEVELS[difficulty_index]


## ホスト：開始の合図を送る。問題の準備は VS のあいだには始めず、ゲーム画面へ切り替えるとき（_transition_to_game）に始める。
func _start_online_game() -> void:
	if _start_sent:
		return
	_start_sent = true
	_apply_match_settings()
	game_state.llm_mode = QuizManager.provider.llm_mode
	NetworkManager.send("start", _start_payload())


func _apply_guest_start(data: Dictionary) -> void:
	_apply_match_settings()
	game_state.subject = str(data.get("subject", game_state.subject))
	game_state.grade = Constants.normalize_grade_for_subject(
		game_state.subject, int(data.get("grade", game_state.grade)))
	game_state.difficulty = str(data.get("difficulty", game_state.difficulty))
	game_state.mode = str(data.get("mode", game_state.mode))
	game_state.llm_mode = str(data.get("llm_mode", game_state.llm_mode))
	game_state.quiz_list.clear()
	game_state.current_quiz = null
	game_state.game_state = Constants.STATE_PRELOADING
	if game_state.provider is BufferedQuizProvider:
		var buffered_provider := game_state.provider as BufferedQuizProvider
		buffered_provider.current_mode = game_state.mode
		buffered_provider.set_llm_mode(game_state.llm_mode)
	game_state.provider.end_round()


func _transition_to_game() -> void:
	if NetworkManager.is_host:
		# ホストだけが問題生成をし、ゲストは同期された問題を受け取る。VS のあいだはステージの読み込みだけにする。
		# ここでは試合の状態だけを整え、問題生成はゲーム画面の覆いが開ききってから始める（GameWorld）。
		game_state.start_game(true)
	# スロットは入れ替えない（ホスト = 1、ゲスト = 2）。見た目だけ各スロットへ入れる。
	var mine := _local_profile()
	var theirs := NetworkManager.opponent_profile
	if NetworkManager.is_host:
		game_state.apply_net_cosmetics({2: theirs})
	else:
		game_state.apply_net_cosmetics({1: theirs, 2: mine})
	# 画面を組み立てる前から自分の視点（スロット）を分かるようにしておく（HUD の呼び名など）。
	game_state.net_online = true
	game_state.net_authority = NetworkManager.is_host
	game_state.local_slot = 1 if NetworkManager.is_host else 2
	NetworkManager.enter_game()
	if director != null and cutin != null and cutin.visible:
		# SWAP：カットインの今の画面を写し、稲妻の線で割れて開く覆いにする（ゲーム画面が開示するときに開く）。
		# カットインの層そのものも覆いへ移し、ゲーム画面を組み立てて開くまでのあいだもホールドの動きを続ける
		# （静止画だけだと、読み込みが終わってから開くまで止まって見える）。溜めの音もそのあいだ鳴り続ける。
		AudioManager.play_sfx(&"versus_charge")
		var shot := get_viewport().get_texture().get_image()
		if shot != null and not shot.is_empty():
			cutin.detach_actors()
			SceneTransition.hold_versus_split(ImageTexture.create_from_image(shot), cutin.seam_points(), director.duration("REVEAL"), cutin.side_colors(), cutin)
	if _game_packed != null:
		get_tree().change_scene_to_packed(_game_packed)
	else:
		get_tree().change_scene_to_file(GAME_WORLD_PATH)


func _difficulty_name(index: int) -> String:
	return Constants.DIFFICULTY_LEVELS[clampi(index, 0, Constants.DIFFICULTY_LEVELS.size() - 1)]
