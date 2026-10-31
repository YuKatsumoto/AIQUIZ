extends CanvasLayer

const OFFSCREEN_PLAYER_MARKER_SCRIPT := preload("res://scripts/ui/offscreen_player_marker.gd")
const DuoTutorialOverlayScript := preload("res://scripts/ui/duo_tutorial_overlay.gd")
const SoloTutorialOverlayScript := preload("res://scripts/ui/solo_tutorial_overlay.gd")
const TutorialCompletionCardScript := preload("res://scripts/ui/tutorial_completion_card.gd")
const PLAYER_NAME_TAG_SCRIPT := preload("res://scripts/ui/player_name_tag.gd")
const ResultCeremonyOverlayScript := preload("res://scripts/ui/result_finale_hud.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
const OFFSCREEN_MARKER_EDGE_MARGIN := 78.0
const OFFSCREEN_MARKER_NEAR_SCALE := 0.82
const OFFSCREEN_MARKER_FAR_SCALE := 1.24
const OFFSCREEN_MARKER_DISTANCE_RANGE := 520.0
const OFFSCREEN_MARKER_PLAYER_HEIGHT := 1.35
# Start warning when the trailing player is this close to the 2P scroll-out
# death separation. The authoritative limit lives in QuizGameState.
const OFFSCREEN_MARKER_SCROLL_WARNING_DISTANCE := 4.0
const REAR_EDGE_WARNING_START_DISTANCE := 3.0
const REAR_EDGE_WARNING_FULL_DISTANCE := 0.45
const REAR_EDGE_WARNING_MIN_ALPHA := 0.05
const REAR_EDGE_WARNING_MAX_ALPHA := 0.34
const REAR_EDGE_WARNING_MIN_BLINK_SPEED := 4.5
const REAR_EDGE_WARNING_MAX_BLINK_SPEED := 9.0
## オンライン：頭上の名前を、帽子の付け根からこれだけ上に出す（帽子に重ならない高さ）。
const NAME_TAG_HEAD_CLEARANCE := 0.6
## オンライン：右上の ping 表示（NetOverlay）の下にスコアと連続正解を下げる量。
const ONLINE_PING_RESERVED_HEIGHT := 34.0
## 届いた数が増えたときに数字がポンと弾む長さと大きさ。
const GENERATION_COUNT_POP_SECONDS := 0.28
const GENERATION_COUNT_POP_SCALE := 0.3
const GENERATION_COUNT_COLOR := Color(0.93, 0.95, 1.0)
const GENERATION_COUNT_POP_COLOR := Color(0.38, 0.68, 1.0)
const GENERATION_COUNT_DONE_COLOR := Color(0.34, 0.86, 0.5)
const GENERATION_COUNT_FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

@onready var flash_rect: ColorRect = $FlashRect
var _shark_impact_flash: float = 0.0
var _rear_edge_warning_time: float = 0.0

## ゲーム中HUD (3Dシーン上に重ねて表示)
## Python版 hud.py の _draw_play 部分に相当

@onready var score_label: Label = $ScoreLabel
@onready var message_label: Label = $MessageLabel
@onready var progress_bar: ProgressBar = $ProgressBar

@onready var preload_panel: Panel = $PreloadPanel
@onready var preload_bg: ColorRect = $PreloadBackground
@onready var pl_title: Label = $PreloadPanel/Title
@onready var pl_subtitle: Label = $PreloadPanel/Subtitle
@onready var pl_progress: ProgressBar = $PreloadPanel/ProgressBar
@onready var pl_status: Label = $PreloadPanel/Status
@onready var start_prompt_label: Label = $PreloadPanel/StartPromptLabel
var _start_prompt_row: KeyHintRow = null
## スマホ：「Enter でスタート」の代わりに押す大きなボタン（Enter を流し込む）。
var _start_touch_button: Button = null
var _start_prompt_kind: String = ""
## 問題の生成待ちの演出：タイトルの回転アイコンと弾む数字（_create_generation_decor）。
var _generation_title_decor: GenerationTitleDecor = null
var _generation_count_label: Label = null
var _generation_count_shown := -1
var _generation_count_pop := 0.0
## "match"（ゲーム開始の準備）、"sudden_death"（サドンデスの問題待ち）、""。変わったら演出を最初から。
var _generation_phase_key := ""
var _generation_stale := true

@onready var game_over_panel: Panel = $GameOverPanel
@onready var go_title: Label = $GameOverPanel/Title
@onready var go_message: Label = $GameOverPanel/MessageBox/Message
@onready var go_rate_box: VBoxContainer = $GameOverPanel/RateBox
@onready var btn_good: Button = $GameOverPanel/RateBox/HBoxContainer/RateGoodBtn
@onready var btn_bad: Button = $GameOverPanel/RateBox/HBoxContainer/RateBadBtn
@onready var rate_feedback: Label = $GameOverPanel/RateBox/RateFeedback
@onready var btn_menu: Button = $GameOverPanel/MenuBtn
@onready var btn_retry: Button = $GameOverPanel/RetryBtn
@onready var btn_history: Button = $GameOverPanel/HistoryBtn

@onready var history_panel: Panel = $HistoryPanel
@onready var history_back_btn: Button = $HistoryPanel/HeaderBar/BackBtn
@onready var history_list: VBoxContainer = $HistoryPanel/ScrollContainer/HistoryList

var _health_hud: Control
var game_state: QuizGameState
var _go_fade_timer: float = 0.0
var _history_built: bool = false
var _stats_panel: PanelContainer = null

var _score_anim_timer: float = 0.0
## Phones: what the result card last showed. The card is rebuilt from fresh Labels each frame,
## and reshaping all that text every frame halved the results screen's frame rate on a phone.
var _result_card_key: Array = []
var _displayed_score: float = 0.0
var _target_score: int = 0
var _confetti_fired: bool = false
var _tutorial_panel: Control = null
var _tutorial_completion_card: Control = null
var _p1_offscreen_marker: Control = null
var _p2_offscreen_marker: Control = null
var _player_name_tags: Array[Control] = []
var _online_top_right_shifted := false
var _gameplay_camera: Camera3D = null
var _result_ceremony_overlay: Control = null

## 練習：リザルトのカードで &"rated"・&"history_opened"・&"history_closed"（ゲーム画面が中継する）。
signal practice_result_action(action: StringName)
## リザルトのカードの部品（_build_result_card が作るたびに入れかわる。画面のコーチが光らせる）。
var _card_score_row: Control = null
## カードの数え上げる数字（[Label, 最後の値]。練習のカードは作り直さずに、この数字だけ進める）。
var _card_score_labels: Array = []
var _card_stats_row: Control = null
var _card_explain: Control = null
## 練習のカードは中身が変わったときだけ作り直す（毎フレーム作り直すと、コーチが光らせる部品が消えてしまう）。
var _practice_card_key: Array = []


func _ready() -> void:
	game_state = QuizManager.game_state
	_health_hud = preload("res://scripts/ui/player_health_hud.gd").new()
	_health_hud.name = "PlayerHealthHUD"
	_health_hud.setup(game_state)
	add_child(_health_hud)
	message_label.visible = false
	preload_bg.visible = false
	preload_panel.visible = false
	game_over_panel.visible = false
	history_panel.visible = false
	_ensure_start_prompt_row()
	_setup_touch_layout()

	# プリロード用プログレスバーのスタイル設定（ダーク背景で見えるように）
	var pl_bg_style := StyleBoxFlat.new()
	pl_bg_style.bg_color = Color(0.12, 0.14, 0.22, 1.0)
	pl_bg_style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	pl_bg_style.set_border_width_all(1)
	pl_bg_style.set_corner_radius_all(6)
	pl_progress.add_theme_stylebox_override("background", pl_bg_style)

	var pl_fill_style := StyleBoxFlat.new()
	pl_fill_style.bg_color = Color(0.25, 0.55, 1.0, 1.0)
	pl_fill_style.set_corner_radius_all(5)
	pl_progress.add_theme_stylebox_override("fill", pl_fill_style)
	pl_progress.custom_minimum_size.y = 22.0
	_create_generation_decor()

	# フェードイン（ゲームシーン開始時）


	# Build the stats panel for game over (created once, updated per game)
	_create_stats_panel()
	_create_result_ceremony_overlay()
	_create_tutorial_overlay()
	_create_offscreen_player_markers()
	_create_player_name_tags()



	btn_good.pressed.connect(func():
		# 練習で記録しないとき（MatchRules.record_results が false）は、game_state が評価を送らない。画面の反応は本番どおり。
		game_state.rate_last_question(true)
		_show_feedback("◯ 良い問題として評価しました")
		_notify_practice(&"rated")
	)
	btn_bad.pressed.connect(func():
		game_state.rate_last_question(false)
		_show_feedback("× 悪い問題として評価しました")
		_notify_practice(&"rated")
	)
	btn_menu.pressed.connect(_return_to_main_menu)
	btn_retry.pressed.connect(_retry_game)
	btn_history.pressed.connect(func():
		_open_history()
		_notify_practice(&"history_opened")
	)
	history_back_btn.pressed.connect(func():
		_close_history()
		_notify_practice(&"history_closed")
	)


## 練習のときだけ、カードの出来事を監督へ知らせる（practice_result_action）。
func _notify_practice(action: StringName) -> void:
	if game_state != null and game_state.practice_rules != null:
		practice_result_action.emit(action)


## 練習の監督（ゲーム画面の practice_director）。練習でなければ null。
func _practice_director() -> Node:
	if game_state == null or game_state.practice_rules == null:
		return null
	var world := get_parent()
	var director: Variant = world.get("practice_director") if world != null else null
	return director as Node if director is Node and is_instance_valid(director) else null


## リザルトをワイプが覆い切るまで保持し、その後でメニュー状態へ戻す。
## 練習は監督の leave_to_menu（なければ今までどおり）。
func _return_to_main_menu() -> void:
	if SceneTransition.is_transitioning():
		return
	var director := _practice_director()
	if director != null and director.has_method("leave_to_menu"):
		director.leave_to_menu()
		return
	var online := game_state.net_online
	var wipe_style := SceneTransition.WipeStyle.DATA if online else SceneTransition.WipeStyle.CIRCLE
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, false, wipe_style)
	if not is_inside_tree():
		return
	if online:
		OnlineMenu.return_from_match(get_tree())
		return
	game_state.reset_to_menu()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


## リトライ時もリザルトをワイプが覆い切ってからゲーム状態を再初期化する。
## 練習は監督の retry_run（同じ画面のままミニ本番の始めから。なければ何もしない）。start_game は呼ばない。
func _retry_game() -> void:
	if SceneTransition.is_transitioning():
		return
	if game_state.practice_rules != null:
		var director := _practice_director()
		if director != null and director.has_method("retry_run"):
			director.retry_run()
		return
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, true)
	if not is_inside_tree():
		return
	if game_state.mode == Constants.MODE_TUTORIAL:
		game_state.restart_tutorial()
	else:
		game_state.start_game()
	game_state.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")


func _create_generation_decor() -> void:
	_generation_title_decor = GenerationTitleDecor.new()
	_generation_title_decor.name = "GenerationTitleDecor"
	preload_panel.add_child(_generation_title_decor)
	_generation_count_label = Label.new()
	_generation_count_label.name = "GenerationCount"
	_generation_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_generation_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_generation_count_label.add_theme_font_override("font", GENERATION_COUNT_FONT)
	_generation_count_label.add_theme_font_size_override("font_size", MobileUi.font(20))
	preload_panel.add_child(_generation_count_label)
	_set_generation_decor_visible(false)


func _create_result_ceremony_overlay() -> void:
	_result_ceremony_overlay = ResultCeremonyOverlayScript.new() as Control
	_result_ceremony_overlay.name = "ResultCeremonyOverlay"
	add_child(_result_ceremony_overlay)
	_result_ceremony_overlay.setup(
		game_state,
		Callable(self, "_retry_game"),
		Callable(self, "_open_history"),
		Callable(self, "_return_to_main_menu")
	)


var _online_markers_labelled := false


## リザルトのスコア欄の呼び名（オンラインは「じぶん」と相手のニックネーム）。
func _result_label(slot: int) -> String:
	return game_state.slot_label(slot) if _online_look() else "P%d" % slot


## オンライン対戦の見せ方か（本物のオンラインと、練習のオンラインの見せ方。コース④の 4-6）。
func _online_look() -> bool:
	return game_state.net_online or game_state.is_practice_online_look()


func _create_offscreen_player_markers() -> void:
	var p1_marker: Control = OFFSCREEN_PLAYER_MARKER_SCRIPT.new() as Control
	p1_marker.name = "P1OffscreenMarker"
	add_child(p1_marker)
	p1_marker.call("configure", "1P", Color(0.95, 0.55, 0.20))
	_p1_offscreen_marker = p1_marker

	var p2_marker: Control = OFFSCREEN_PLAYER_MARKER_SCRIPT.new() as Control
	p2_marker.name = "P2OffscreenMarker"
	add_child(p2_marker)
	p2_marker.call("configure", "2P", Color(0.20, 0.65, 0.90))
	_p2_offscreen_marker = p2_marker


func _update_offscreen_player_markers(delta: float) -> void:
	if _p1_offscreen_marker == null or _p2_offscreen_marker == null:
		return
	if _online_look() and not _online_markers_labelled:
		# オンラインは「じぶん」と相手のニックネームで示す（1P/2P はローカル用の呼び名）。
		_online_markers_labelled = true
		_p1_offscreen_marker.call("configure", game_state.slot_label(1), Color(0.95, 0.55, 0.20))
		_p2_offscreen_marker.call("configure", game_state.slot_label(2), Color(0.20, 0.65, 0.90))

	var marker_state_active: bool = (
		game_state.num_players >= 2
		and game_state.game_state in [
			Constants.STATE_COUNTDOWN,
			Constants.STATE_PLAYING,
			Constants.STATE_CORRECT,
			Constants.STATE_GOAL_RACE,
		]
	)
	if not marker_state_active:
		_hide_offscreen_player_markers()
		return

	var world_root: Node3D = get_parent() as Node3D
	if world_root == null:
		_hide_offscreen_player_markers()
		return
	if _gameplay_camera == null or not is_instance_valid(_gameplay_camera):
		_gameplay_camera = world_root.get_node_or_null("CameraController/Camera3D") as Camera3D
	if _gameplay_camera == null or not _gameplay_camera.is_inside_tree():
		_hide_offscreen_player_markers()
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= OFFSCREEN_MARKER_EDGE_MARGIN * 2.0 or viewport_size.y <= OFFSCREEN_MARKER_EDGE_MARGIN * 2.0:
		_hide_offscreen_player_markers()
		return

	var p1_local_position := Vector3(
		game_state.player_x,
		game_state.player_y + OFFSCREEN_MARKER_PLAYER_HEIGHT,
		game_state.player_local_z
	)
	var p2_local_position := Vector3(
		game_state.player2_x,
		game_state.player2_y + OFFSCREEN_MARKER_PLAYER_HEIGHT,
		game_state.player2_local_z
	)
	_update_single_offscreen_marker(
		_p1_offscreen_marker,
		world_root.to_global(p1_local_position),
		game_state.p1_alive and not game_state.p1_waiting_for_shark,
		_scroll_out_danger_ratio(1),
		viewport_size,
		delta
	)
	_update_single_offscreen_marker(
		_p2_offscreen_marker,
		world_root.to_global(p2_local_position),
		game_state.p2_alive and not game_state.p2_waiting_for_shark,
		_scroll_out_danger_ratio(2),
		viewport_size,
		delta
	)


func _update_single_offscreen_marker(
		marker: Control,
		player_world_position: Vector3,
		should_track: bool,
		warning_strength: float,
		viewport_size: Vector2,
		delta: float) -> void:
	if not should_track or _gameplay_camera.is_position_in_frustum(player_world_position):
		marker.call("hide_marker")
		return

	var viewport_center := viewport_size * 0.5
	var screen_position: Vector2 = _gameplay_camera.unproject_position(player_world_position)
	var target_direction := screen_position - viewport_center
	var is_behind: bool = _gameplay_camera.is_position_behind(player_world_position)
	if is_behind:
		target_direction = -target_direction
	if target_direction.length_squared() <= 0.0001:
		target_direction = Vector2.DOWN

	target_direction = target_direction.normalized()
	var marker_center := _marker_edge_position(viewport_center, viewport_size, target_direction)
	var clamped_screen := Vector2(
		clampf(screen_position.x, 0.0, viewport_size.x),
		clampf(screen_position.y, 0.0, viewport_size.y)
	)
	var offscreen_distance: float = screen_position.distance_to(clamped_screen)
	if is_behind:
		offscreen_distance = maxf(offscreen_distance, minf(viewport_size.x, viewport_size.y) * 0.55)
	var distance_range: float = maxf(
		OFFSCREEN_MARKER_DISTANCE_RANGE,
		minf(viewport_size.x, viewport_size.y) * 0.55
	)
	var distance_ratio: float = clampf(offscreen_distance / distance_range, 0.0, 1.0)
	var marker_scale: float = lerpf(
		OFFSCREEN_MARKER_NEAR_SCALE,
		OFFSCREEN_MARKER_FAR_SCALE,
		distance_ratio
	)
	if _health_hud != null and game_state.shows_duo_cards():
		marker_center = _health_hud.reserve_marker_center(marker_center, 60.0 * OFFSCREEN_MARKER_FAR_SCALE)
	marker.call(
		"set_marker_state",
		marker_center,
		target_direction,
		marker_scale,
		delta,
		warning_strength
	)


func _scroll_out_danger_ratio(player_index: int) -> float:
	if game_state.is_saw_visible():
		return game_state.get_saw_danger_ratio(player_index)
	# Step 4 deliberately separates the players, so do not show a false death warning.
	if not game_state.is_scroll_out_death_enabled():
		return 0.0
	var trailing_distance: float = (
		game_state.player2_z - game_state.player_z
		if player_index == 1
		else game_state.player_z - game_state.player2_z
	)
	var warning_start: float = (
		game_state.SCROLL_OUT_LIMIT
		- OFFSCREEN_MARKER_SCROLL_WARNING_DISTANCE
	)
	return clampf(
		(trailing_distance - warning_start)
		/ OFFSCREEN_MARKER_SCROLL_WARNING_DISTANCE,
		0.0,
		1.0
	)


func _marker_edge_position(
		viewport_center: Vector2,
		viewport_size: Vector2,
		direction: Vector2) -> Vector2:
	var half_extents := viewport_size * 0.5 - Vector2(
		OFFSCREEN_MARKER_EDGE_MARGIN,
		OFFSCREEN_MARKER_EDGE_MARGIN
	)
	var distance_to_edge: float = 1000000.0
	if absf(direction.x) > 0.0001:
		distance_to_edge = minf(distance_to_edge, half_extents.x / absf(direction.x))
	if absf(direction.y) > 0.0001:
		distance_to_edge = minf(distance_to_edge, half_extents.y / absf(direction.y))
	var edge_position := viewport_center + direction * distance_to_edge
	if MobileUi.is_touch_ui():
		# スマホ：カメラの穴と角丸（SafeArea）の内側にマーカーを止める。
		edge_position.x = clampf(
			edge_position.x,
			OFFSCREEN_MARKER_EDGE_MARGIN + TouchHud.safe_left(),
			viewport_size.x - OFFSCREEN_MARKER_EDGE_MARGIN - TouchHud.safe_right()
		)
		edge_position.y = clampf(
			edge_position.y,
			OFFSCREEN_MARKER_EDGE_MARGIN + TouchHud.safe_top(),
			viewport_size.y - OFFSCREEN_MARKER_EDGE_MARGIN - TouchHud.safe_bottom()
		)
	return edge_position


func _hide_offscreen_player_markers() -> void:
	if _p1_offscreen_marker != null:
		_p1_offscreen_marker.call("hide_marker")
	if _p2_offscreen_marker != null:
		_p2_offscreen_marker.call("hide_marker")


func _create_player_name_tags() -> void:
	for slot in [1, 2]:
		var tag: Control = PLAYER_NAME_TAG_SCRIPT.new() as Control
		tag.name = "P%dNameTag" % slot
		add_child(tag)
		_player_name_tags.append(tag)


## オンライン対戦：両方のキャラの頭上に名前を小さく半透明で出し続ける。
## 画面の外にいるときはオフスクリーンマーカーに任せて隠す。
## 練習の CPU（game_state.practice_p2_cpu）は、P2 の頭の上だけに同じ見た目で「CPU」と出す。
## 練習のオンラインの見せ方（コース④の 4-6）は、オンラインと同じく自分の頭の上にも自分の名前を出す。
func _update_player_name_tags(delta: float) -> void:
	if _player_name_tags.is_empty():
		return
	var practice_cpu: bool = game_state.practice_cpu_active()
	var both_tags: bool = game_state.is_practice_online_look()
	var active: bool = (
		(game_state.net_online or practice_cpu)
		and game_state.num_players >= 2
		and game_state.game_state in [
			Constants.STATE_COUNTDOWN,
			Constants.STATE_PLAYING,
			Constants.STATE_CORRECT,
			Constants.STATE_GOAL_RACE,
		]
	)
	var world_root: Node3D = get_parent() as Node3D if active else null
	var player: PlayerController = null
	if world_root != null:
		player = world_root.get_node_or_null("Player") as PlayerController
		if _gameplay_camera == null or not is_instance_valid(_gameplay_camera):
			_gameplay_camera = world_root.get_node_or_null("CameraController/Camera3D") as Camera3D
	var can_draw: bool = player != null and _gameplay_camera != null and _gameplay_camera.is_inside_tree()
	# 選択肢と問題文の画面上の範囲。名前が重なったら薄くして読むじゃまをしない。
	var avoid_rects: Array[Rect2] = []
	if can_draw and world_root.has_method("get_choice_screen_rects"):
		avoid_rects = world_root.call("get_choice_screen_rects", _gameplay_camera)
	for i in _player_name_tags.size():
		var tag: Control = _player_name_tags[i]
		var slot: int = i + 1
		var alive: bool = (
			(game_state.p1_alive if slot == 1 else game_state.p2_alive)
			and not (game_state.p1_waiting_for_shark if slot == 1 else game_state.p2_waiting_for_shark)
		)
		if not can_draw or not alive or (practice_cpu and slot != 2 and not both_tags):
			tag.call("hide_tag")
			continue
		var anchor: Vector3 = player.get_head_top_position(slot) + Vector3(0.0, NAME_TAG_HEAD_CLEARANCE, 0.0)
		if _gameplay_camera.is_position_behind(anchor) or not _gameplay_camera.is_position_in_frustum(anchor):
			tag.call("hide_tag")
			continue
		var tag_name: String = "CPU" if practice_cpu and slot == 2 else _online_player_name(slot)
		tag.call("configure", tag_name, Color(0.95, 0.55, 0.20) if slot == 1 else Color(0.20, 0.65, 0.90))
		tag.call("point_at", _gameplay_camera.unproject_position(anchor), avoid_rects, delta)


## 頭上に出す名前。自分は相手に見えているのと同じ名前、相手はニックネーム。
func _online_player_name(slot: int) -> String:
	if slot == game_state.local_slot:
		return OnlineMenu.shown_own_name()
	var opponent := NetworkManager.opponent_name
	return opponent if not opponent.is_empty() else "あいて"


## オンラインでは右上に ping を出すので、その下へスコアを一度だけ下げる。
func _shift_top_right_for_online_ping() -> void:
	if _online_top_right_shifted or not game_state.net_online:
		return
	_online_top_right_shifted = true
	if MobileUi.is_touch_ui():
		_apply_safe_area_layout()
		return
	score_label.offset_top += ONLINE_PING_RESERVED_HEIGHT
	score_label.offset_bottom += ONLINE_PING_RESERVED_HEIGHT


func _show_feedback(txt: String) -> void:
	btn_good.get_parent().visible = false
	rate_feedback.text = txt
	rate_feedback.visible = true

func _process(_dt: float) -> void:
	if not game_state:
		return
	_shark_impact_flash = maxf(0.0, _shark_impact_flash - _dt * 12.5)
	# Integrate frequency: multiplying total time by changing proximity jumps phase.
	var warning_speed := lerpf(REAR_EDGE_WARNING_MIN_BLINK_SPEED, REAR_EDGE_WARNING_MAX_BLINK_SPEED, _rear_edge_warning_strength())
	_rear_edge_warning_time = fposmod(_rear_edge_warning_time + _dt * warning_speed, TAU)
	_update_offscreen_player_markers(_dt)
	_update_player_name_tags(_dt)
	_shift_top_right_for_online_ping()
	if _result_ceremony_overlay != null:
		_result_ceremony_overlay.update_overlay(_dt)
	var generation_phase := _generation_phase()
	if generation_phase != _generation_phase_key:
		_generation_phase_key = generation_phase
		_generation_stale = true

	if game_state.game_state == Constants.STATE_PRELOADING:
		_show_preloading(_dt)
		_update_tutorial_overlay(_dt)
		return
	elif game_state.game_state == Constants.STATE_WAITING_START:
		_show_waiting_start(_dt)
		_update_tutorial_overlay(_dt)
		return
	elif game_state.game_state == Constants.STATE_FLYOVER:
		preload_bg.visible = false
		preload_panel.visible = false
		score_label.visible = false
		progress_bar.visible = false
		game_over_panel.visible = false
		message_label.visible = false

		_update_tutorial_overlay(_dt)
		return
	else:
		preload_bg.visible = false
		preload_panel.visible = false

	var ceremony_active := (
		game_state.result_presentation_active
		and game_state.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
	)
	# The sudden death descent waits for its questions: the match-start preparing panel.
	if not game_state.sudden_death_preparing_panel.is_empty() \
			and game_state.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_SUDDEN_DEATH]:
		_show_sudden_death_preparing(_dt)
		return
	if _sudden_death_panel_shown:
		_sudden_death_panel_shown = false
		preload_panel.visible = false
	# The sudden death draws its own HUD (SuddenDeathDirector). The elimination lasso
	# (Hatena carrying both souls to the finish) plays without the score and message.
	if ceremony_active or game_state.game_state == Constants.STATE_SUDDEN_DEATH or game_state.elimination_lasso_active:
		score_label.visible = false
		message_label.visible = false
		progress_bar.visible = false
		game_over_panel.visible = false
		_update_flash()
		_update_tutorial_overlay(_dt)
		return

	if game_state.is_elimination_result_pending() or _is_practice_loss():
		# Local 2P: no GAME OVER card; the verdict ceremony follows the wipe.
		# 練習の負けも、ゲームオーバーの画面と結果のカードを出さない（監督がやり直す）。
		_go_fade_timer = 0.0
		game_over_panel.visible = false
		history_panel.visible = false
	elif game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		_go_fade_timer += _dt
		_show_game_over()
	else:
		_go_fade_timer = 0.0
		_reset_result_card_state()
		game_over_panel.visible = false
		history_panel.visible = false

	_update_score()
	_update_message()
	_update_progress()
	_update_flash()
	_update_tutorial_overlay(_dt)

func play_shark_impact_flash() -> void:
	_shark_impact_flash = 1.0


func play_tutorial_completion_celebration() -> void:
	_fire_confetti()


func show_solo_stage_tutorial_complete(duration: float = 3.6) -> void:
	_show_tutorial_completion_card("SoloStageCompletionCard", {
		"step": "1 / 2  STAGE CLEAR",
		"title": "ステージチュートリアル完了",
		"body": "移動・ジャンプ・エモート、海の危険、ハート（HP）、2択と4択の壁を体験しました。\n本番は10問チャレンジとエンドレスで、ハート3つから始まります。",
		"progress": "✓ ステージ実践　　次はカスタマイズ",
		"footer": MobileUi.prompt(
			"自動でカスタマイズ紹介へ進みます　（ゲーム中は Esc で一時停止）",
			"自動でカスタマイズ紹介へ進みます　（ゲーム中は左上の Ⅱ で一時停止）"
		),
		"duration": duration,
	})


func show_duo_stage_tutorial_complete(duration: float = 4.2) -> void:
	_show_tutorial_completion_card("DuoStageCompletionCard", {
		"step": "1 / 2  STAGE CLEAR",
		"title": "ステージチュートリアル完了",
		"body": "2人の操作と押し合い、海とゴーストシャーク、回転のこぎり、ハートと先着の得点、4択の壁、スコアタワーの勝敗判定を体験しました。",
		"progress": _duo_score_tower_summary(),
		"footer": MobileUi.prompt(
			"自動でカスタマイズ紹介へ進みます　（ゲーム中は Esc で一時停止）",
			"自動でカスタマイズ紹介へ進みます　（ゲーム中は左上の Ⅱ で一時停止）"
		),
		"duration": duration,
	})


## 10問チャレンジの勝敗はスコアタワーで決まる。このチュートリアルの成績で計算例を見せる。
func _duo_score_tower_summary() -> String:
	var lines: Array[String] = ["スコアタワー（10問チャレンジの勝敗）＝ 正解数 ×（残りハート＋0.5）"]
	var parts: Array[String] = []
	if game_state.result_presentation_active:
		# ゴール後に実際のスコアタワーで確定した得点（脱落した人は正解数だけ）と勝敗。
		for player_index: int in [1, 2]:
			parts.append(game_state.get_result_formula_text(player_index))
		var verdict := (
			"引き分け" if game_state.result_winner == 0 else "P%dの勝ち" % game_state.result_winner
		)
		lines.append("このコースの結果　" + "　　".join(parts) + "　→ " + verdict)
		return "\n".join(lines)
	for player_index: int in [1, 2]:
		var correct: int = game_state.score if player_index == 1 else game_state.player2_score
		var hp: int = game_state.get_player_hp(player_index)
		var points := QuizGameState.result_half_points(correct, hp, true)
		parts.append("P%d  %d問 ×（%d＋0.5）＝ %s" % [
			player_index, correct, hp, QuizGameState.format_result_points(points)
		])
	lines.append("このコースでは　" + "　　".join(parts))
	return "\n".join(lines)


## コース完了カードは1P/2Pで文面だけが違う。生成と後片付けはここに集約する。
func _show_tutorial_completion_card(card_name: String, config: Dictionary) -> void:
	if _tutorial_completion_card and is_instance_valid(_tutorial_completion_card):
		return
	var card := TutorialCompletionCardScript.new() as Control
	card.name = card_name
	add_child(card)
	_tutorial_completion_card = card
	card.tree_exited.connect(func() -> void:
		if _tutorial_completion_card == card:
			_tutorial_completion_card = null
	)
	card.call("present", config)


## 練習の負け（docs/new_tutorial/phase4_design.md 2.4）：GAME_OVER でもゲームオーバーの画面を出さない。
## 本番どおりの画面（MatchRules.real_result_screens）のときは、本番と同じくカードを出す。
func _is_practice_loss() -> bool:
	return (
		game_state.practice_rules != null
		and game_state.game_state == Constants.STATE_GAME_OVER
		and not game_state.practice_rules.real_result_screens
	)


## 練習のまきもどし・やり直し：サメの画面の光とゲームオーバーの画面の続き（カード・問題履歴）を消す。
func practice_clear_flashes() -> void:
	_shark_impact_flash = 0.0
	_go_fade_timer = 0.0
	game_over_panel.visible = false
	history_panel.visible = false
	_reset_result_card_state()


## リザルトのカードの出し方を最初からにする（スコアの数え上げ・紙吹雪・問題履歴・練習のカードの中身）。
func _reset_result_card_state() -> void:
	_score_anim_timer = 0.0
	_result_card_key = []
	_displayed_score = 0.0
	_confetti_fired = false
	_history_built = false
	_practice_card_key = []


## 画面のコーチが光らせるリザルトのカードの部品（docs/new_tutorial/phase5_design.md 3.4。ゲーム画面の
## practice_coach_target から呼ぶ）。なければ null。カードの中身の部品は、カードを作り直すと入れかわる。
func practice_coach_target(id: StringName) -> Control:
	match id:
		&"result_card":
			return _stats_panel
		&"result_score":
			return _card_score_row
		&"result_stats":
			return _card_stats_row
		&"result_explain":
			return _card_explain
		&"result_rate":
			# 「この問題の評価:」と「◯ 良い」「× 悪い」。押したあとは同じ場所に評価の反応が出る。
			return go_rate_box if go_rate_box.visible else null
		&"result_history":
			return btn_history
		&"result_retry":
			return btn_retry
		&"result_menu":
			return btn_menu
		&"history_back":
			return history_back_btn
	return null


## リザルトのカードが出ているか（GAME OVER は死ぬ演出のあとのフェードが済んだら）。問題履歴を開いている間は false。
func practice_result_card_visible() -> bool:
	return (
		game_state != null
		and game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]
		and game_over_panel.visible
		and game_over_panel.modulate.a >= 0.999
		and _stats_panel != null
		and _stats_panel.visible
		and not history_panel.visible
	)


## 練習（1-5）：ハートがポンと出て光り、そのあと1つずつ順に光る。
func practice_hearts_intro(player_index := 1) -> void:
	if _health_hud != null and _health_hud.has_method("play_practice_intro"):
		_health_hud.play_practice_intro(player_index)


func _rear_edge_warning_strength() -> float:
	if game_state.is_saw_visible():
		return maxf(game_state.get_saw_danger_ratio(1), game_state.get_saw_danger_ratio(2))
	if (
		game_state.num_players != 1
		or game_state.game_state != Constants.STATE_PLAYING
		or not game_state.p1_alive
		or game_state.p1_waiting_for_shark
	):
		return 0.0
	var clearance: float = game_state.player_local_z - game_state.FLOOR_BACK_Z
	return clampf(
		(REAR_EDGE_WARNING_START_DISTANCE - clearance)
		/ (REAR_EDGE_WARNING_START_DISTANCE - REAR_EDGE_WARNING_FULL_DISTANCE),
		0.0,
		1.0
	)


func _update_flash() -> void:
	# The result ceremony owns its own explosion feedback. Suppress the legacy
	# correct/wrong full-screen tint so the grass, characters, and compact result
	# controls remain readable when STATE_CLEAR is entered.
	if game_state.result_presentation_active:
		flash_rect.visible = false
		return
	var rear_edge_strength: float = _rear_edge_warning_strength()
	if _shark_impact_flash > 0.0:
		flash_rect.color = Color(0.72, 0.94, 1.0, _shark_impact_flash * 0.78)
		flash_rect.visible = true
	elif rear_edge_strength > 0.0:
		var blink_wave: float = (sin(_rear_edge_warning_time) + 1.0) * 0.5
		var blink: float = lerpf(0.35, 1.0, blink_wave)
		var warning_alpha: float = lerpf(
			REAR_EDGE_WARNING_MIN_ALPHA,
			REAR_EDGE_WARNING_MAX_ALPHA,
			rear_edge_strength
		) * blink
		flash_rect.color = Color(1.0, 0.035, 0.02, warning_alpha)
		flash_rect.visible = true
	elif game_state.correct_flash > 0.0:
		flash_rect.color = Color(0.2, 1.0, 0.4, game_state.correct_flash * 0.4)
		flash_rect.visible = true
	elif game_state.wrong_flash > 0.0:
		flash_rect.color = Color(1.0, 0.2, 0.2, game_state.wrong_flash * 0.6)
		flash_rect.visible = true
	else:
		flash_rect.visible = false

var _displayed_progress: float = 0.0

func _show_preloading(dt: float) -> void:
	preload_bg.visible = false
	preload_panel.visible = true
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	pl_progress.visible = true
	pl_status.visible = true
	_set_start_prompt_visible(false)
	pl_subtitle.visible = true
	var target := _generation_target()
	_show_generation_progress(dt, _generation_arrived(target), target, _generation_by_ai())
	pl_status.text = game_state.status_text


## 問題の生成待ちの演出を出す場面。値が変わったら演出を最初からにする（_process）。
func _generation_phase() -> String:
	var state := game_state.game_state
	if state == Constants.STATE_PRELOADING:
		return "match"
	if state == Constants.STATE_WAITING_START and game_state.mode != Constants.MODE_TUTORIAL:
		return "match"
	if game_state.sudden_death_preparing_panel == "questions" 			and state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_SUDDEN_DEATH]:
		return "sudden_death"
	return ""


func _generation_target() -> int:
	return maxi(1, 1 if game_state.mode == Constants.MODE_ENDLESS else game_state.target_count)


## 届いた問題の数。オンラインのゲストは穴あき（null）で届くので数えない。
func _generation_arrived(target: int) -> int:
	var arrived := 0
	for quiz: QuizItem in game_state.quiz_list:
		if quiz != null:
			arrived += 1
	return mini(arrived, target)


## オンラインのAI生成か（オフラインの問題集とチュートリアルは違う）。
func _generation_by_ai() -> bool:
	return game_state.mode != Constants.MODE_TUTORIAL 		and (game_state.llm_mode != "OFFLINE" or game_state.net_online)


## 問題の生成待ちのパネル：タイトル（回転アイコンと動く点、そろったらチェック）と、バーの右の弾む数字。
## Status の文言は呼び出し側が決める。
func _show_generation_progress(dt: float, current: int, target: int, by_ai: bool) -> void:
	if _generation_stale:
		_generation_stale = false
		_generation_count_shown = -1
		_generation_count_pop = 0.0
	_apply_generation_layout()

	var english := game_state.use_english_ui
	var complete := current >= target
	if complete:
		pl_title.text = "Quizzes ready!" if english else "問題ができました！"
	elif by_ai:
		pl_title.text = "AI is writing your quizzes" if english else "AIが問題をつくっています"
	else:
		pl_title.text = "Preparing quizzes" if english else "問題を準備しています"
	pl_subtitle.text = "%s · Grade %d" % [Constants.SUBJECT_EN.get(game_state.subject, game_state.subject), game_state.grade] 		if english else "%s・%d年 の問題" % [game_state.subject, game_state.grade]
	var title_font := pl_title.get_theme_font("font")
	var title_size := pl_title.get_theme_font_size("font_size")
	_generation_title_decor.text_width = title_font.get_string_size(
		pl_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size).x
	_generation_title_decor.mode = "done" if complete else "busy"
	_generation_title_decor.advance(dt)

	pl_progress.max_value = float(target)
	_displayed_progress = clampf(_displayed_progress, 0.0, float(current))
	_displayed_progress = lerpf(_displayed_progress, float(current), clampf(dt * 10.0, 0.0, 1.0)) 		if current < target else float(target)
	pl_progress.value = _displayed_progress

	if current > _generation_count_shown and _generation_count_shown >= 0:
		_generation_count_pop = 1.0
	_generation_count_shown = current
	_generation_count_pop = maxf(0.0, _generation_count_pop - dt / GENERATION_COUNT_POP_SECONDS)
	var pop := sin(_generation_count_pop * PI)
	_generation_count_label.text = "%d/%d" % [current, target]
	_generation_count_label.pivot_offset = Vector2(0.0, _generation_count_label.size.y * 0.5)
	_generation_count_label.scale = Vector2.ONE * (1.0 + pop * GENERATION_COUNT_POP_SCALE)
	_generation_count_label.add_theme_color_override("font_color",
		(GENERATION_COUNT_DONE_COLOR if complete else GENERATION_COUNT_COLOR).lerp(GENERATION_COUNT_POP_COLOR, pop))


func _set_generation_decor_visible(visible_now: bool) -> void:
	if _generation_title_decor == null:
		return
	_generation_title_decor.visible = visible_now
	_generation_count_label.visible = visible_now


## 生成待ちの並び：パネルは 600×240 のまま、タイトルに飾りの幅を足し、バーの右に数字を置く。
func _apply_generation_layout() -> void:
	_set_generation_decor_visible(true)
	preload_panel.set_anchors_preset(Control.PRESET_CENTER)
	preload_panel.offset_left = -300.0
	preload_panel.offset_right = 300.0
	preload_panel.offset_top = -120.0
	preload_panel.offset_bottom = 120.0
	# Title と Subtitle は上辺の中央、ProgressBar と Status は下辺の中央が基準（gameplay_hud.tscn）。
	_set_offsets(pl_title, -280.0, 16.0, 280.0, 60.0)
	pl_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_offsets(pl_subtitle, -280.0, 66.0, 280.0, 92.0)
	_generation_title_decor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_set_offsets(_generation_title_decor, -280.0, 16.0, 280.0, 60.0)
	_set_offsets(pl_progress, -250.0, -86.0, 164.0, -64.0)
	_generation_count_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_set_offsets(_generation_count_label, 176.0, -94.0, 280.0, -56.0)
	_set_offsets(pl_status, -280.0, -50.0, 280.0, -20.0)
	pl_title.add_theme_font_size_override("font_size", 26)
	pl_subtitle.add_theme_font_size_override("font_size", MobileUi.font(18))
	pl_status.add_theme_font_size_override("font_size", MobileUi.font(16))


func _set_offsets(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom

var _sudden_death_panel_shown := false


## 2Pサドンデスの降下中、サドンデス用の問題（オンライン生成）か地下神殿の準備を待っている間。
## ゲーム開始時の問題準備と同じパネル・進み具合・文言を出す（docs/sudden_death_underground.md 第5.3節）。
func _show_sudden_death_preparing(dt: float) -> void:
	if not _sudden_death_panel_shown:
		_sudden_death_panel_shown = true
		_displayed_progress = 0.0
	preload_bg.visible = false
	preload_panel.visible = true
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	pl_progress.visible = true
	pl_status.visible = true
	_set_start_prompt_visible(false)
	pl_subtitle.visible = true
	var target := QuizGameState.SUDDEN_DEATH_GENERATION_COUNT
	if game_state.sudden_death_preparing_panel == "questions":
		var current := mini(game_state.sudden_death_generation_received, target)
		_show_generation_progress(dt, current, target, true)
		pl_status.text = "Generating quizzes... (%d/%d)" % [current, target] if game_state.use_english_ui \
			else "AIクイズ生成中... (%d/%d)" % [current, target]
	else:
		_apply_preload_stage_preview_layout()
		pl_title.text = "問題を準備中..."
		pl_subtitle.text = "しばらくお待ちください"
		# 新サドンデス（docs/sudden_death_v2/common.md 第6章）：種目の舞台（第1段はビタ止めの島）の準備待ち。
		pl_status.text = "Preparing the island..." if game_state.use_english_ui else "島を準備中..."
		pl_progress.max_value = float(target)
		_displayed_progress = float(target)
		pl_progress.value = _displayed_progress
	_update_flash()


var _blink_timer: float = 0.0
func _show_waiting_start(dt: float) -> void:
	preload_bg.visible = false
	preload_panel.visible = true
	score_label.visible = false
	message_label.visible = false
	progress_bar.visible = false
	game_over_panel.visible = false
	if game_state.is_practice_online_look():
		# 練習のオンラインの見せ方：Enter では始めない（台本の言葉のあとで監督が始める）ので、準備のパネルと Enter の案内は出さない
		preload_panel.visible = false
		_set_start_prompt_visible(false)
		return
	pl_status.visible = true
	# 練習の問題は台本の手書きなので、設定の教科・学年（「算数・3年 の問題」）は出さない。
	pl_subtitle.visible = game_state.practice_rules == null
	var world := get_parent()
	var arrival_locked := (
		world != null
		and world.has_method("is_start_presentation_locked")
		and bool(world.call("is_start_presentation_locked"))
	)
	var construction_locked := (
		world != null
		and world.has_method("is_preload_construction_locked")
		and bool(world.call("is_preload_construction_locked"))
	)
	var target := _generation_target()
	if game_state.mode != Constants.MODE_TUTORIAL and (arrival_locked or construction_locked):
		# 問題はそろい、キャラクターの到着待ち。「問題ができました！」と満タンのバーを出したままにする。
		_set_start_prompt_visible(false)
		pl_progress.visible = true
		_show_generation_progress(dt, _generation_arrived(target), target, _generation_by_ai())
		if construction_locked:
			pl_status.text = game_state.status_text
		else:
			pl_status.text = "Characters arriving..." if game_state.use_english_ui else "キャラクター到着中..."
		return
	if game_state.mode == Constants.MODE_TUTORIAL:
		if not _show_tutorial_waiting_start(arrival_locked, construction_locked):
			return
	else:
		# 到着がすんでも「問題ができました！」とチェックはそのまま。バーと数字と Status の代わりに
		# Enter の案内だけを出し、同じことを言う文言（準備完了・Enterキーでスタート）は重ねない。
		_show_generation_progress(dt, _generation_arrived(target), target, _generation_by_ai())
		pl_progress.visible = false
		_generation_count_label.visible = false
		pl_status.visible = false
		_refresh_start_prompt(false)
	_blink_timer += dt
	_start_prompt_row.modulate.a = 0.5 + 0.5 * sin(_blink_timer * 6.0)
	if _start_touch_button != null:
		# ボタンは押せることが分かるよう、薄くしすぎない。
		_start_touch_button.modulate.a = 0.8 + 0.2 * sin(_blink_timer * 6.0)


## チュートリアルの開始待ち（問題の生成はない）：コース名と「Enter でチュートリアル開始」を出す。
## キャラクターの到着待ちなどで Enter の案内をまだ出さないときは false。
func _show_tutorial_waiting_start(arrival_locked: bool, construction_locked: bool) -> bool:
	_apply_preload_stage_preview_layout()
	var is_duo := game_state.get_tutorial_course() == GameManager.TUTORIAL_COURSE_LOCAL_2P
	pl_title.text = "ローカル2Pチュートリアル" if is_duo else "1Pチュートリアル"
	pl_subtitle.text = (
		"2人の操作・ゴースト・のこぎり・ハート・ゴールを順番に練習します"
		if is_duo
		else "操作・海の危険・ハート・4択の壁を順番に練習します"
	)
	if construction_locked:
		pl_status.text = game_state.status_text
		pl_progress.visible = false
		_set_start_prompt_visible(false)
		return false
	if arrival_locked:
		pl_status.text = "Characters arriving..." if game_state.use_english_ui \
			else "キャラクター到着中..."
		pl_progress.visible = false
		_set_start_prompt_visible(false)
		return false
	pl_status.text = "Ready" if game_state.use_english_ui else "準備完了"
	pl_progress.visible = false
	_refresh_start_prompt(true)
	return true


func _apply_preload_stage_preview_layout() -> void:
	_set_generation_decor_visible(false)
	pl_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	preload_panel.set_anchors_preset(Control.PRESET_CENTER)
	preload_panel.offset_left = -300.0
	preload_panel.offset_right = 300.0
	preload_panel.offset_top = -120.0
	preload_panel.offset_bottom = 120.0
	pl_title.offset_left = -150.0
	pl_title.offset_top = 20.0
	pl_title.offset_right = 150.0
	pl_title.offset_bottom = 90.0
	pl_subtitle.offset_left = -150.0
	pl_subtitle.offset_top = 75.0
	pl_subtitle.offset_right = 150.0
	pl_subtitle.offset_bottom = 100.0
	pl_progress.offset_left = -200.0
	pl_progress.offset_top = -80.0
	pl_progress.offset_right = 200.0
	pl_progress.offset_bottom = -60.0
	pl_status.offset_left = -150.0
	pl_status.offset_top = -45.0
	pl_status.offset_right = 150.0
	pl_status.offset_bottom = -15.0
	_layout_start_prompt_row()
	pl_title.add_theme_font_size_override("font_size", 26)
	pl_subtitle.add_theme_font_size_override("font_size", MobileUi.font(18))
	pl_status.add_theme_font_size_override("font_size", MobileUi.font(16))


func _ensure_start_prompt_row() -> void:
	if _start_prompt_row != null:
		return
	start_prompt_label.visible = false
	_start_prompt_row = KeyHintRow.new()
	_start_prompt_row.name = "StartPromptRow"
	_start_prompt_row.visible = false
	start_prompt_label.add_sibling(_start_prompt_row)
	_layout_start_prompt_row()


func _layout_start_prompt_row() -> void:
	if _start_prompt_row == null:
		return
	_start_prompt_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_prompt_row.offset_left = -280.0
	_start_prompt_row.offset_top = -104.0
	_start_prompt_row.offset_right = 280.0
	_start_prompt_row.offset_bottom = -58.0
	if _start_touch_button != null:
		_start_touch_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_start_touch_button.offset_left = -190.0
		_start_touch_button.offset_top = -128.0
		_start_touch_button.offset_right = 190.0
		_start_touch_button.offset_bottom = -46.0


func _set_start_prompt_visible(visible_now: bool) -> void:
	_ensure_start_prompt_row()
	start_prompt_label.visible = false
	if _start_touch_button != null:
		# スマホはキーキャップの行の代わりにボタンを出す。
		_start_prompt_row.visible = false
		# 画面のタッチ操作の層が同じ「スタート」（Enter）を下の真ん中に出しているときは重ねない（同じフレームに両方は出さない）。
		_start_touch_button.visible = TouchHud.own_button_allowed(_start_touch_button, "ConfirmButton", visible_now)
		return
	_start_prompt_row.visible = visible_now


func _refresh_start_prompt(is_tutorial: bool) -> void:
	_ensure_start_prompt_row()
	var kind := "tutorial" if is_tutorial else "start"
	if _start_prompt_kind != kind:
		_start_prompt_kind = kind
		_start_prompt_row.reset()
		_start_prompt_row.add_spec("Enter", KeycapChip.DEFAULT_ACCENT, KeycapChip.SizeClass.NORMAL)
		_start_prompt_row.add_text(
			"でチュートリアル開始" if is_tutorial else "を押してスタート",
			Color(1.0, 1.0, 0.5, 1.0),
			20
		)
		if _start_touch_button != null:
			_start_touch_button.text = "▶ チュートリアル開始" if is_tutorial else "▶ タップでスタート"
	_set_start_prompt_visible(true)


# ---------- スマホ（タッチ操作）の見せ方 ----------

## スマホだけ：文字を大きく、ボタンを指の大きさに、端の部品をカメラの穴と角丸の内側へ。
## デスクトップでは何もしない（PC の見た目は .tscn のまま）。
func _setup_touch_layout() -> void:
	if not MobileUi.is_touch_ui():
		return
	_start_touch_button = TouchHud.make_button("▶ タップでスタート", 24, Color(1.0, 1.0, 0.5, 1.0))
	_start_touch_button.name = "StartTouchButton"
	_start_touch_button.visible = false
	# 開始の条件（到着待ちなど）は今までどおりゲーム画面の Enter の処理が決める。
	_start_touch_button.pressed.connect(func() -> void: TouchHud.tap_key(KEY_ENTER))
	start_prompt_label.add_sibling(_start_touch_button)
	_layout_start_prompt_row()

	score_label.add_theme_font_size_override("font_size", MobileUi.font(20))
	pl_status.add_theme_font_size_override("font_size", MobileUi.font(16))
	pl_subtitle.add_theme_font_size_override("font_size", MobileUi.font(18))
	for button: Button in [btn_good, btn_bad, btn_menu, btn_retry, btn_history, history_back_btn]:
		MobileUi.ensure_touch_size(button)
		button.focus_mode = Control.FOCUS_NONE
	TouchHud.on_safe_area_changed(_apply_safe_area_layout)
	get_viewport().size_changed.connect(_apply_safe_area_layout)
	_apply_safe_area_layout()


## 右上のスコア・下端の進み具合・問題履歴を SafeArea の内側へ寄せる（スマホのみ）。
## 問題履歴の戻るボタンは指の大きさに広がるので、見出しの帯と一覧もその分下げる。
func _apply_safe_area_layout() -> void:
	if not MobileUi.is_touch_ui():
		return
	# ping の札もスマホでは文字が大きいので、少し多めに空ける。
	var ping_shift := ONLINE_PING_RESERVED_HEIGHT + 8.0 if _online_top_right_shifted else 0.0
	score_label.offset_right = -16.0 - TouchHud.safe_right()
	score_label.offset_left = -240.0 - TouchHud.safe_right()
	score_label.offset_top = 16.0 + TouchHud.safe_top() + ping_shift
	score_label.offset_bottom = 58.0 + TouchHud.safe_top() + ping_shift
	progress_bar.offset_left = 100.0 + TouchHud.safe_left()
	progress_bar.offset_right = -100.0 - TouchHud.safe_right()
	progress_bar.offset_top = -24.0 - TouchHud.safe_bottom()
	progress_bar.offset_bottom = -TouchHud.safe_bottom()
	var header := history_back_btn.get_parent() as Control
	if header != null:
		# 左上には TouchControls のポーズボタン（練習のリザルトでは出る）があるので、戻るボタンをその右へ。
		# 見出しが真ん中に残るよう、右も同じだけ空ける。
		var pause_room := TouchHud.pause_clearance()
		header.offset_left = 16.0 + TouchHud.safe_left() + pause_room
		header.offset_right = -16.0 - TouchHud.safe_right() - pause_room
		header.offset_top = 16.0 + TouchHud.safe_top()
		header.offset_bottom = header.offset_top + MobileUi.MIN_TOUCH_SIZE
	var scroll := history_panel.get_node_or_null("ScrollContainer") as Control
	if scroll != null:
		scroll.offset_left = 40.0 + TouchHud.safe_left()
		scroll.offset_right = -40.0 - TouchHud.safe_right()
		scroll.offset_top = 32.0 + TouchHud.safe_top() + MobileUi.MIN_TOUCH_SIZE
		scroll.offset_bottom = -16.0 - TouchHud.safe_bottom()

func _update_flyover_message() -> void:
	message_label.visible = true
	var progress := clampf(game_state.flyover_timer / game_state.flyover_duration, 0.0, 1.0)
	var wall_count := game_state.flyover_total_walls
	var showing := ceili(progress * wall_count)
	if progress < 0.15:
		message_label.text = "全%d問のコースを確認中..." % wall_count
	elif progress < 0.85:
		message_label.text = "Q%d / %d" % [wall_count - showing + 1, wall_count]
	else:
		message_label.text = "スタート準備!"
	message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	message_label.add_theme_font_size_override("font_size", 42)
	message_label.modulate.a = 1.0


# ============================================================
# Game Over / Clear スコア表示 (強化版)
# ============================================================

func _create_stats_panel() -> void:
	"""ゲームオーバー時の統合メインカードを構築"""
	# tscn側のMessageBoxとRateBoxは非表示にする（カード内に統合）
	go_message.get_parent().visible = false
	go_rate_box.visible = false

	_stats_panel = PanelContainer.new()
	_stats_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.14, 0.92)
	style.border_color = Color(0.25, 0.4, 0.8, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	_stats_panel.add_theme_stylebox_override("panel", style)
	# 画面中央に配置、タイトルの直下〜ボタンの上まで
	_stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	_stats_panel.offset_left = -340.0
	_stats_panel.offset_top = -195.0
	_stats_panel.offset_right = 340.0
	_stats_panel.offset_bottom = 195.0
	if MobileUi.is_touch_ui():
		# The bottom buttons grow upward to the 80 px touch height; lift the card clear of them.
		_stats_panel.offset_top = -235.0
		_stats_panel.offset_bottom = 155.0
	_stats_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	game_over_panel.add_child(_stats_panel)

## どちらも下部コーチバー1本。2Pはプレイヤー別チップを横一列にする。
func _create_tutorial_overlay() -> void:
	if game_state and game_state.is_duo_tutorial():
		_tutorial_panel = DuoTutorialOverlayScript.new() as Control
		_tutorial_panel.name = "DuoTutorialOverlay"
	else:
		_tutorial_panel = SoloTutorialOverlayScript.new() as Control
		_tutorial_panel.name = "SoloTutorialOverlay"
	add_child(_tutorial_panel)
	_tutorial_panel.call("setup", game_state)

func _update_tutorial_overlay(dt: float = 0.0) -> void:
	if not _tutorial_panel or not game_state:
		return
	_tutorial_panel.call("update_overlay", dt)

func _show_game_over() -> void:
	var is_clear := game_state.game_state == Constants.STATE_CLEAR
	var result_reveal_delay := 4.0
	if not is_clear and (game_state.p1_wall_impact or game_state.p2_wall_impact):
		result_reveal_delay = maxf(result_reveal_delay, QuizGameState.WALL_DEATH_SEQUENCE_DURATION)

	if not is_clear and (
		_go_fade_timer < result_reveal_delay
		or not game_state.is_wall_death_sequence_complete()
	):
		game_over_panel.visible = false
		return

	game_over_panel.visible = true
	# tscn側のMessageBox/RateBoxは常に非表示（カード内に統合済）
	go_message.get_parent().visible = false

	if not is_clear:
		var alpha := clampf((_go_fade_timer - result_reveal_delay) / 1.0, 0.0, 1.0)
		game_over_panel.modulate.a = alpha
	else:
		game_over_panel.modulate.a = 1.0
		if not _confetti_fired:
			_confetti_fired = true
			_fire_confetti()

	go_title.text = "CLEAR!" if is_clear else "GAME OVER"
	go_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_clear else Color(1, 0.3, 0.3))

	# Parse message: remove redundant GAME OVER/CLEAR text
	var raw_msg: String = game_state.message_text
	if raw_msg.begins_with("GAME OVER\n\n"):
		raw_msg = raw_msg.substr(11)
	elif raw_msg.begins_with("GAME OVER\n"):
		raw_msg = raw_msg.substr(10)
	elif raw_msg.begins_with("CLEAR!"):
		var parts = raw_msg.split("\n")
		var new_parts = []
		for p in parts:
			if not p.begins_with("CLEAR!") and not "questions done" in p and not "問完走" in p and not "Score:" in p and not "正解数:" in p:
				new_parts.append(p)
		raw_msg = "\n".join(new_parts)
	elif raw_msg.begins_with("TUTORIAL CLEAR!"):
		var tutorial_parts = raw_msg.split("\n")
		if tutorial_parts.size() > 1:
			tutorial_parts.remove_at(0)
		raw_msg = "\n".join(tutorial_parts)
	# Strip trailing score lines
	var msg_lines = raw_msg.split("\n\n")
	if msg_lines.size() > 1 and ("Score:" in msg_lines[-1] or "正解数:" in msg_lines[-1]):
		msg_lines.remove_at(msg_lines.size() - 1)
		raw_msg = "\n\n".join(msg_lines)
	raw_msg = raw_msg.strip_edges()

	# Build the unified card content
	if game_state.practice_rules != null:
		_refresh_practice_result_card(is_clear, raw_msg)
	elif not _result_card_unchanged(is_clear, raw_msg):
		_build_result_card(is_clear, raw_msg)

	# NEW RECORD display


	# Bottom buttons
	btn_history.visible = game_state.quiz_history.size() > 0
	if _online_look():
		# オンラインは同じ相手ともう一度は始められないので、オンラインメニューへ戻して さがし直す。
		# 練習のオンラインの見せ方も同じ（『オンラインメニューへ』は監督の leave_to_menu で練習の形のオンラインの画面へ）。
		btn_retry.visible = false
		btn_menu.text = "オンラインメニューへ"

## Phones only: true once the score count-up is over and nothing on the card changed, so the
## card keeps its Labels instead of being rebuilt this frame.
func _result_card_unchanged(is_clear: bool, explanation: String) -> bool:
	if not MobileUi.is_touch_ui():
		return false
	var key: Array = [
		is_clear, explanation, game_state.score, game_state.player2_score, game_state.total_answered,
		game_state.max_streak, int(game_state.play_time), game_state.rating_feedback,
		game_state.rating_target_quiz != null, game_state.num_players, game_state.mode,
	]
	var unchanged := _score_anim_timer >= 1.5 and key == _result_card_key
	_result_card_key = key
	return unchanged


func _build_result_card(is_clear: bool, explanation: String) -> void:
	"""メインカード内に全リザルト情報を構築"""
	_stats_panel.visible = true
	for child in _stats_panel.get_children():
		child.queue_free()
	_card_score_row = null
	_card_score_labels = []
	_card_stats_row = null
	_card_explain = null

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_stats_panel.add_child(root_vbox)

	var current_score: int = game_state.score
	var p2_score: int = game_state.player2_score
	var is_2p: bool = game_state.num_players >= 2
	var is_tutorial: bool = game_state.mode == Constants.MODE_TUTORIAL
	var is_coop: bool = game_state.is_coop_mode()
	if is_tutorial:
		_build_tutorial_result(root_vbox, explanation)
		return

	# ─── Score animation ───
	_score_anim_timer += 0.016
	var anim_progress := clampf(_score_anim_timer / 1.5, 0.0, 1.0)
	anim_progress = 1.0 - pow(1.0 - anim_progress, 3.0)

	# ─── Row 1: Score display ───
	if is_coop:
		var score_row := HBoxContainer.new()
		score_row.alignment = BoxContainer.ALIGNMENT_CENTER
		score_row.add_theme_constant_override("separation", 12)
		root_vbox.add_child(score_row)
		_card_score_row = score_row

		var score_num := Label.new()
		var displayed := int(anim_progress * current_score)
		score_num.text = "%d" % displayed
		_card_score_labels.append([score_num, current_score])
		score_num.add_theme_font_size_override("font_size", 48)
		score_num.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(0.9, 0.92, 0.95))
		score_row.add_child(score_num)

		var sub := Label.new()
		sub.text = "協力成功 / %d問" % game_state.target_count
		sub.add_theme_font_size_override("font_size", MobileUi.font(16))
		sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_row.add_child(sub)

		var team_label := Label.new()
		team_label.text = "COOP CLEAR" if is_clear else "協力失敗"
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_label.add_theme_font_size_override("font_size", MobileUi.font(22))
		team_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(1.0, 0.45, 0.35))
		root_vbox.add_child(team_label)
	elif is_2p:
		var hbox_scores := HBoxContainer.new()
		hbox_scores.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox_scores.add_theme_constant_override("separation", 30)
		root_vbox.add_child(hbox_scores)
		_card_score_row = hbox_scores
		_add_player_score_column(hbox_scores, _result_label(1), current_score, anim_progress,
			current_score > p2_score)
		var vs_label := Label.new()
		vs_label.text = "vs"
		vs_label.add_theme_font_size_override("font_size", MobileUi.font(20))
		vs_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox_scores.add_child(vs_label)
		_add_player_score_column(hbox_scores, _result_label(2), p2_score, anim_progress,
			p2_score > current_score)

		# Winner
		if current_score != p2_score:
			var wl := Label.new()
			var winner_slot := 1 if current_score > p2_score else 2
			if _online_look():
				wl.text = "🏆 あなたの かち！" if game_state.is_local_slot(winner_slot) else "🏆 %s の かち" % game_state.slot_label(winner_slot)
			else:
				wl.text = "🏆 %s WIN!" % ("P1" if winner_slot == 1 else "P2")
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wl.add_theme_font_size_override("font_size", MobileUi.font(22))
			wl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			root_vbox.add_child(wl)
		else:
			var dl := Label.new()
			dl.text = "🤝 DRAW!"
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.add_theme_font_size_override("font_size", MobileUi.font(22))
			dl.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
			root_vbox.add_child(dl)
	else:
		# 1P: score big number + subtitle in an HBox for compactness
		var score_row := HBoxContainer.new()
		score_row.alignment = BoxContainer.ALIGNMENT_CENTER
		score_row.add_theme_constant_override("separation", 12)
		root_vbox.add_child(score_row)
		_card_score_row = score_row

		var score_num := Label.new()
		var displayed := int(anim_progress * current_score)
		score_num.text = "%d" % displayed
		score_num.add_theme_font_size_override("font_size", 48)
		score_num.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_clear else Color(0.9, 0.92, 0.95))
		score_row.add_child(score_num)
		_card_score_labels.append([score_num, current_score])

		if game_state.mode == Constants.MODE_TEN or game_state.practice_rules != null:
			var sub := Label.new()
			# 練習は練習の問題の数（コース②のミニ本番は「正解 / 3問」）。
			sub.text = "正解 / %d問" % (game_state.target_count if game_state.practice_rules != null else 10)
			sub.add_theme_font_size_override("font_size", MobileUi.font(16))
			sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
			sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			score_row.add_child(sub)

	# ─── Separator ───
	_add_separator(root_vbox)

	# ─── Row 2: Stats (横並びの4つのミニカード) ───
	var stats_hbox := HBoxContainer.new()
	stats_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(stats_hbox)
	_card_stats_row = stats_hbox

	var total := game_state.total_answered
	var correct_count := maxi(current_score, p2_score) if is_2p else current_score
	var rate_pct: float = (float(correct_count) / float(total) * 100.0) if total > 0 else 0.0
	var rate_color := Color(0.3, 1.0, 0.5) if rate_pct >= 80.0 else (
		Color(1.0, 0.85, 0.3) if rate_pct >= 50.0 else Color(1.0, 0.4, 0.3))
	_add_mini_stat(stats_hbox, "正答率", "%.0f%%" % rate_pct, rate_color)

	var streak_color := Color(1.0, 0.6, 0.2) if game_state.max_streak >= 3 else Color(0.75, 0.78, 0.85)
	_add_mini_stat(stats_hbox, "連続正解", "%d 🔥" % game_state.max_streak, streak_color)

	var mins := int(game_state.play_time) / 60
	var secs := int(game_state.play_time) % 60
	_add_mini_stat(stats_hbox, "時間", "%d:%02d" % [mins, secs], Color(0.65, 0.7, 0.82))


	# ─── Row 3: Explanation (if any) ───
	if not explanation.is_empty():
		_add_separator(root_vbox)

		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 110)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_vbox.add_child(scroll)
		_card_explain = scroll

		var exp_vbox := VBoxContainer.new()
		exp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(exp_vbox)

		var exp_label := Label.new()
		exp_label.text = explanation
		exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		exp_label.add_theme_font_size_override("font_size", MobileUi.font(18))
		exp_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		exp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		exp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_vbox.add_child(exp_label)

	# ─── Row 4: Rating (if applicable) ───
	if game_state.rating_target_quiz:
		_add_separator(root_vbox)
		if game_state.rating_feedback.is_empty():
			# Show buttons
			go_rate_box.visible = true
			btn_good.get_parent().visible = true
			rate_feedback.visible = false
			# Reparent RateBox into the card
			if go_rate_box.get_parent() != root_vbox:
				go_rate_box.get_parent().remove_child(go_rate_box)
				root_vbox.add_child(go_rate_box)
		else:
			go_rate_box.visible = true
			_show_feedback(game_state.rating_feedback)
			if go_rate_box.get_parent() != root_vbox:
				go_rate_box.get_parent().remove_child(go_rate_box)
				root_vbox.add_child(go_rate_box)
	else:
		go_rate_box.visible = false


func _build_tutorial_result(root: VBoxContainer, checklist_text: String) -> void:
	btn_retry.text = "同じコースをもう一度"
	btn_menu.text = "メニューへ"
	btn_history.visible = false
	go_rate_box.visible = false
	var is_duo := game_state.get_tutorial_course() == GameManager.TUTORIAL_COURSE_LOCAL_2P
	var course_title := Label.new()
	course_title.text = "ローカル2Pコース COMPLETE" if is_duo else "1Pコース COMPLETE"
	course_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	course_title.add_theme_font_size_override("font_size", 28)
	course_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22))
	root.add_child(course_title)

	var checklist := Label.new()
	checklist.text = checklist_text
	checklist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	checklist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	checklist.add_theme_font_size_override("font_size", MobileUi.font(18))
	checklist.add_theme_color_override("font_color", Color(0.82, 0.95, 0.88))
	root.add_child(checklist)

	_add_separator(root)
	var badges := Label.new()
	var badge_text := {"done": "✓ 完了", "updated": "更新あり", "todo": "未完了"}
	badges.text = "1P %s     ローカル2P %s" % [
		badge_text[GameManager.tutorial_course_badge(GameManager.TUTORIAL_COURSE_SOLO)],
		badge_text[GameManager.tutorial_course_badge(GameManager.TUTORIAL_COURSE_LOCAL_2P)],
	]
	badges.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badges.add_theme_font_size_override("font_size", MobileUi.font(17))
	badges.add_theme_color_override("font_color", Color(0.58, 0.78, 1.0))
	root.add_child(badges)

	var recap_title := Label.new()
	recap_title.text = "次に試せる遊び方"
	recap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recap_title.add_theme_font_size_override("font_size", MobileUi.font(17))
	recap_title.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	root.add_child(recap_title)
	var recap := HBoxContainer.new()
	recap.alignment = BoxContainer.ALIGNMENT_CENTER
	recap.add_theme_constant_override("separation", 12)
	root.add_child(recap)
	_add_tutorial_recap_card(recap, "10問チャレンジ", "10問を走り切る")
	_add_tutorial_recap_card(recap, "エンドレス", "オフライン問題で挑戦")
	_add_tutorial_recap_card(recap, "カスタマイズ", "スキン・帽子・エモート")


func _add_tutorial_recap_card(parent: HBoxContainer, title: String, detail: String) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(184.0, 72.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.20, 0.92)
	style.border_color = Color(0.25, 0.48, 0.84, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", MobileUi.font(16))
	title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	box.add_child(title_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.add_theme_font_size_override("font_size", MobileUi.font(12))
	detail_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.88))
	box.add_child(detail_label)


## 練習のリザルトのカード：中身（CLEAR か・解説・スコア・統計・評価の的）が変わったときだけ作り直し、変わらない
## フレームはスコアの数え上げと評価の欄だけ進める（本番の毎フレームの作り直しと同じ見た目のまま、部品を残す）。
func _refresh_practice_result_card(is_clear: bool, explanation: String) -> void:
	var key := [is_clear, explanation, game_state.score, game_state.player2_score, game_state.total_answered,
		game_state.max_streak, int(game_state.play_time), game_state.target_count, game_state.num_players,
		game_state.rating_target_quiz]
	if key != _practice_card_key:
		_practice_card_key = key
		# 評価の欄は、作り直すカードへ移す。評価の的がないときに、消える前のカードといっしょに消えないよう先に外へ出す。
		if go_rate_box.get_parent() != game_over_panel:
			go_rate_box.get_parent().remove_child(go_rate_box)
			game_over_panel.add_child(go_rate_box)
		_build_result_card(is_clear, explanation)
		return
	_score_anim_timer += 0.016
	var anim_progress := clampf(_score_anim_timer / 1.5, 0.0, 1.0)
	anim_progress = 1.0 - pow(1.0 - anim_progress, 3.0)
	for entry: Array in _card_score_labels:
		var label: Variant = entry[0]
		if is_instance_valid(label):
			(label as Label).text = "%d" % int(anim_progress * int(entry[1]))
	if game_state.rating_target_quiz:
		go_rate_box.visible = true
		if game_state.rating_feedback.is_empty():
			btn_good.get_parent().visible = true
			rate_feedback.visible = false
		else:
			_show_feedback(game_state.rating_feedback)
	else:
		go_rate_box.visible = false


func _add_mini_stat(parent: HBoxContainer, title: String, value: String, color: Color) -> void:
	"""統計ミニカード: タイトル + 値の縦並び"""
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", MobileUi.font(20))
	val_lbl.add_theme_color_override("font_color", color)
	col.add_child(val_lbl)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", MobileUi.font(12))
	title_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
	col.add_child(title_lbl)

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.35, 0.5, 0.3))
	parent.add_child(sep)

func _add_player_score_column(parent: HBoxContainer, label_text: String, score_val: int,
		anim_progress: float, is_winner: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", MobileUi.font(16))
	name_label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if is_winner else Color(0.6, 0.65, 0.75))
	col.add_child(name_label)

	var val_label := Label.new()
	var displayed := int(anim_progress * score_val)
	val_label.text = "%d" % displayed
	_card_score_labels.append([val_label, score_val])
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.add_theme_font_size_override("font_size", 40)
	val_label.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.2) if is_winner else Color(0.85, 0.88, 0.92))
	col.add_child(val_label)

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color: Color) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", MobileUi.font(17))
	lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	grid.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", MobileUi.font(18))
	val.add_theme_color_override("font_color", value_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val)


func _update_score() -> void:
	# Normal 2P scores live directly above each player's HP in the corner cards.
	# 練習の2人もカードを使う（右上の「正解・問題」は出さない）。
	if game_state.shows_duo_cards():
		score_label.visible = false
		return
	# チュートリアルの進行はコーチバー側で表示するため、スコア表示は出さない。
	if game_state.mode == Constants.MODE_TUTORIAL:
		score_label.visible = false
		return
	# 練習は、ルールで出すと決めたとき（コース②のミニ本番）だけ出す。
	if game_state.practice_rules != null and not game_state.practice_rules.show_score:
		score_label.visible = false
		return
	if game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT, Constants.STATE_GOAL_RACE]:
		score_label.visible = true
		if game_state.num_players >= 2:
			if game_state.is_coop_mode():
				score_label.text = "協力: %d/%d" % [game_state.score, game_state.target_count]
			else:
				if game_state.net_online:
					# 自分のスコアを先に出す。
					var mine := game_state.local_slot
					var theirs := game_state.remote_slot()
					score_label.text = "%s: %d  %s: %d" % [
						game_state.slot_label(mine), game_state.score if mine == 1 else game_state.player2_score,
						game_state.slot_label(theirs), game_state.score if theirs == 1 else game_state.player2_score,
					]
				else:
					score_label.text = "P1: %d  P2: %d" % [game_state.score, game_state.player2_score]
		else:
			if game_state.mode == Constants.MODE_TEN:
				score_label.text = "正解: %d  問題: %d/10" % [game_state.score, game_state.current_index + 1]
			elif game_state.practice_rules != null:
				# 練習は練習の問題の数（コース②のミニ本番は「問題: 1/3」）。問題を使い切ったら最後の番号のまま。
				var count := game_state.target_count
				score_label.text = "正解: %d  問題: %d/%d" % [game_state.score, mini(game_state.current_index + 1, maxi(count, 1)), count]
			else:
				score_label.text = "正解: %d" % game_state.score
	else:
		score_label.visible = false

func _update_message() -> void:
	if game_state.game_state == Constants.STATE_GOAL_RACE:
		message_label.visible = true
		message_label.text = game_state.message_text
		# Pulsating gold text
		var pulse: float = (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
		message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15 + pulse * 0.2))
		message_label.add_theme_font_size_override("font_size", 48)
		message_label.modulate.a = 1.0
	elif game_state.correct_flash > 0.0 and game_state.message_text:
		message_label.visible = true
		message_label.text = game_state.message_text
		message_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		message_label.add_theme_font_size_override("font_size", 36)
		message_label.modulate.a = clampf(game_state.correct_flash * 2.0, 0.0, 1.0)
	else:
		message_label.visible = false

func _update_progress() -> void:
	if game_state.mode == Constants.MODE_TEN and \
			game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		progress_bar.visible = true
		progress_bar.max_value = 10
		progress_bar.value = game_state.current_index
	elif game_state.practice_rules != null and game_state.practice_rules.show_score and game_state.num_players == 1 \
			and game_state.target_count > 0 and game_state.game_state in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]:
		# 練習で右上の数字を出すとき（コース②のミニ本番）は、本番の1人のときと同じく下の進み具合も出す。
		progress_bar.visible = true
		progress_bar.max_value = game_state.target_count
		progress_bar.value = game_state.current_index
	else:
		progress_bar.visible = false


# ============================================================
# 問題履歴パネル
# ============================================================

func _open_history() -> void:
	if not _history_built:
		_build_history_items()
		_history_built = true

	game_over_panel.visible = false
	if _result_ceremony_overlay != null:
		_result_ceremony_overlay.set_suppressed(true)
	history_panel.visible = true
	history_panel.modulate.a = 1.0
	history_panel.position.x = 0.0

func _close_history() -> void:
	history_panel.visible = false
	if game_state.result_presentation_active:
		game_over_panel.visible = false
		if _result_ceremony_overlay != null:
			_result_ceremony_overlay.set_suppressed(false)
	else:
		game_over_panel.visible = true
		game_over_panel.modulate.a = 1.0

func _build_history_items() -> void:
	# Clear existing items
	for child in history_list.get_children():
		child.queue_free()

	if game_state.quiz_history.is_empty():
		var empty_label := Label.new()
		empty_label.text = "出題された問題はありません"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", MobileUi.font(20))
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		history_list.add_child(empty_label)
		return

	for i: int in range(game_state.quiz_history.size()):
		var entry: Dictionary = game_state.quiz_history[i]
		var quiz: QuizItem = entry["quiz"]
		var correct: bool = entry["correct"]
		var rated: String = entry.get("rated", "")

		var card := _create_history_card(i, quiz, correct, rated)
		history_list.add_child(card)

func _create_history_card(index: int, quiz: QuizItem, correct: bool, rated: String) -> PanelContainer:
	var card := PanelContainer.new()

	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.16, 0.9)
	style.border_color = Color(0.3, 0.7, 0.4, 0.8) if correct else Color(0.8, 0.3, 0.2, 0.8)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# --- Header: Q number + result icon + question text ---
	var header := Label.new()
	var icon: String = "◯" if correct else "✗"
	var icon_color_tag: String
	if correct:
		icon_color_tag = "Q%d  %s" % [index + 1, icon]
	else:
		icon_color_tag = "Q%d  %s" % [index + 1, icon]
	var question_text := quiz.coop_prompt if quiz.has_coop_data() and not quiz.coop_prompt.is_empty() else quiz.q
	header.text = "%s  %s" % [icon_color_tag, FractionFormatter.format_question(question_text)]
	header.add_theme_font_size_override("font_size", MobileUi.font(20))
	header.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5) if correct else Color(1.0, 0.4, 0.3))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(header)

	var entry: Dictionary = game_state.quiz_history[index]

	# --- Choices ---
	var choices_box := VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 2)
	vbox.add_child(choices_box)

	if quiz.has_coop_data():
		_add_coop_history_choices(choices_box, quiz, entry)
	else:
		var labels_4 := ["A", "B", "C", "D"]
		for ci: int in range(quiz.c.size()):
			var choice_label := Label.new()
			var prefix: String
			if quiz.c.size() <= 2:
				prefix = "左" if ci == 0 else "右"
			else:
				prefix = labels_4[ci] if ci < 4 else str(ci)

			var is_correct_choice := (ci == quiz.a)
			choice_label.text = "  %s: %s %s" % [prefix, FractionFormatter.to_inline(quiz.c[ci]), "✓" if is_correct_choice else ""]
			choice_label.add_theme_font_size_override("font_size", MobileUi.font(17))
			if is_correct_choice:
				choice_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			else:
				choice_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
			choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			choices_box.add_child(choice_label)

	# --- Explanation ---
	if not quiz.e.is_empty():
		var explain_label := Label.new()
		explain_label.text = "📝 %s" % FractionFormatter.to_inline(quiz.e)
		explain_label.add_theme_font_size_override("font_size", MobileUi.font(16))
		explain_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
		explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(explain_label)

	# --- Rating buttons ---
	var rate_container := HBoxContainer.new()
	rate_container.alignment = BoxContainer.ALIGNMENT_END
	rate_container.add_theme_constant_override("separation", 12)
	vbox.add_child(rate_container)

	var player_rated: bool = entry.get("player_rated", false)
	if not player_rated:
		# Show rating buttons, optionally mentioning AI's rating if any
		var rate_label := Label.new()
		if rated == "good":
			rate_label.text = "AI評価:良い | あなたの評価:"
		elif rated == "bad":
			rate_label.text = "AI評価:悪い | あなたの評価:"
		else:
			rate_label.text = "この問題の評価:"
		rate_label.add_theme_font_size_override("font_size", MobileUi.font(15))
		rate_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		rate_container.add_child(rate_label)

		var good_btn := Button.new()
		good_btn.text = "◯ 良い"
		good_btn.custom_minimum_size = Vector2(100, MobileUi.touch(36))
		good_btn.add_theme_font_size_override("font_size", MobileUi.font(16))
		good_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		rate_container.add_child(good_btn)

		var bad_btn := Button.new()
		bad_btn.text = "× 悪い"
		bad_btn.custom_minimum_size = Vector2(100, MobileUi.touch(36))
		bad_btn.add_theme_font_size_override("font_size", MobileUi.font(16))
		bad_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		rate_container.add_child(bad_btn)

		# Capture index for closure
		var idx := index
		good_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, true)
			_replace_rate_buttons(rate_container, true)
		)
		bad_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, false)
			_replace_rate_buttons(rate_container, false)
		)
	else:
		# Already rated by player manually — show feedback
		var feedback := Label.new()
		if rated == "good":
			feedback.text = "◯ 良い問題として評価しました"
			feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			feedback.text = "× 悪い問題として評価しました"
			feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		feedback.add_theme_font_size_override("font_size", MobileUi.font(15))
		rate_container.add_child(feedback)

	return card

func _add_coop_history_choices(choices_box: VBoxContainer, quiz: QuizItem, entry: Dictionary) -> void:
	var p1_chosen: int = int(entry.get("p1_choice", -99))
	var p2_chosen: int = int(entry.get("p2_choice", -99))
	_add_coop_history_role(choices_box, quiz.coop_p1_label, quiz.coop_p1_choices, quiz.coop_p1_answer, p1_chosen)
	_add_coop_history_role(choices_box, quiz.coop_p2_label, quiz.coop_p2_choices, quiz.coop_p2_answer, p2_chosen)

func _add_coop_history_role(choices_box: VBoxContainer, title: String,
		choices: PackedStringArray, answer: int, chosen: int) -> void:
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", MobileUi.font(16))
	title_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	choices_box.add_child(title_label)

	var names := ["A", "B"]
	for ci: int in range(mini(2, choices.size())):
		var choice_label := Label.new()
		var is_correct_choice := ci == answer
		var picked := " / 選択" if ci == chosen else ""
		choice_label.text = "  %s: %s%s %s" % [
			names[ci],
			FractionFormatter.to_inline(choices[ci]),
			picked,
			"✓" if is_correct_choice else ""
		]
		choice_label.add_theme_font_size_override("font_size", MobileUi.font(17))
		choice_label.add_theme_color_override("font_color",
			Color(0.3, 1.0, 0.5) if is_correct_choice else Color(0.65, 0.7, 0.75))
		choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choices_box.add_child(choice_label)

func _replace_rate_buttons(container: HBoxContainer, good: bool) -> void:
	# Remove all children
	for child in container.get_children():
		child.queue_free()

	# Add feedback label
	var feedback := Label.new()
	if good:
		feedback.text = "◯ 良い問題として評価しました"
		feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		feedback.text = "× 悪い問題として評価しました"
		feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	feedback.add_theme_font_size_override("font_size", MobileUi.font(15))
	container.add_child(feedback)

func _fire_confetti() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	# Center position (assuming CLEAR! text is somewhat central, slightly top)
	var center_pos = Vector2(viewport_size.x / 2.0, viewport_size.y * 0.3)

	# Create two emitters (left and right) to burst from center outwards
	var angles = [200.0, 340.0]  # Slightly upwards left and right
	var colors = [Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.MAGENTA, Color.WHITE, Color.ORANGE]

	for i in range(2):
		var emitter = CPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.8
		emitter.amount = GraphicsQuality.particle_amount(60, GameManager.graphics_quality)
		emitter.lifetime = 3.0

		# Position relative to go_title or screen center
		emitter.position = go_title.global_position + Vector2(go_title.size.x / 2.0, go_title.size.y / 2.0)

		# Emission shape
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(40.0, 20.0)

		# Movement
		emitter.direction = Vector2.UP.rotated(deg_to_rad(angles[i] - 270.0))
		if i == 0:
			emitter.direction = Vector2(-1, -0.5).normalized()
		else:
			emitter.direction = Vector2(1, -0.5).normalized()

		emitter.spread = 35.0
		emitter.gravity = Vector2(0, 900.0)
		emitter.initial_velocity_min = 400.0
		emitter.initial_velocity_max = 750.0
		emitter.angular_velocity_min = -360.0
		emitter.angular_velocity_max = 360.0

		# Size and scale
		emitter.scale_amount_min = 6.0
		emitter.scale_amount_max = 12.0

		# Color curve for fading out
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1, 1, 1, 1))
		gradient.add_point(0.7, Color(1, 1, 1, 1))
		gradient.add_point(1.0, Color(1, 1, 1, 0))
		emitter.color_ramp = gradient

		# Random colors from preset
		emitter.color_initial_ramp = Gradient.new()
		emitter.color_initial_ramp.set_color(0, colors[randi() % colors.size()])
		emitter.color_initial_ramp.set_color(1, colors[randi() % colors.size()])

		# Actually, CPUParticles2D doesn't support multiple discrete colors easily without a texture.
		# Let's make multiple small emitters to get different colors.
		pass

	# Better approach for discrete colors: multiple small emitters
	for col in colors:
		var emitter = CPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.9
		emitter.amount = GraphicsQuality.particle_amount(15, GameManager.graphics_quality)
		emitter.lifetime = 2.5

		if go_title.is_inside_tree():
			emitter.position = go_title.global_position + Vector2(go_title.size.x / 2.0, go_title.size.y / 2.0)
		else:
			emitter.position = center_pos

		emitter.direction = Vector2(0, -1)
		emitter.spread = 75.0
		emitter.gravity = Vector2(0, 800.0)
		emitter.initial_velocity_min = 350.0
		emitter.initial_velocity_max = 850.0
		emitter.angular_velocity_min = -720.0
		emitter.angular_velocity_max = 720.0

		emitter.scale_amount_min = 8.0
		emitter.scale_amount_max = 16.0
		emitter.color = col

		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1, 1, 1, 1))
		gradient.add_point(0.7, Color(1, 1, 1, 1))
		gradient.add_point(1.0, Color(1, 1, 1, 0))
		emitter.color_ramp = gradient

		add_child(emitter)
		emitter.emitting = true

		# Self destruct timer
		var timer = get_tree().create_timer(3.0)
		# メソッドへ直接つなぐ。シーン切り替えで先に消えた場合は接続ごと外れる。
		timer.timeout.connect(emitter.queue_free)


# ============================================================
# ローディング演出（プリロード中のアニメーション強化）
