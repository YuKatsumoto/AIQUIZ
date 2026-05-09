extends Node3D

## リプレイ再生専用シーン
## ゲームワールドを再利用し、入力を無効化してReplayPlayerから状態を注入する。

var replay_player: ReplayPlayer
var replay_camera_node: ReplayCamera
var replay_hud: CanvasLayer  # ReplayHUD

var _game_state: QuizGameState
var _game_world_scene: PackedScene
var _game_world: Node3D

func _ready() -> void:
	# QuizManager から recorder を取得
	var recorder: ReplayRecorder = QuizManager.get_meta("last_replay", null)
	if recorder == null or recorder.frame_count == 0:
		push_error("[ReplayScene] No replay data found")
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return

	# ゲーム状態を初期化（リプレイ用のダミー状態）
	_game_state = QuizManager.game_state
	_game_state.is_replay = true
	var meta := recorder.meta
	_game_state.num_players = meta.get("num_players", 1)
	_game_state.mode = meta.get("mode", Constants.MODE_TEN)
	_game_state.subject = meta.get("subject", "")
	_game_state.grade = meta.get("grade", 0)
	_game_state.difficulty = meta.get("difficulty", "")
	_game_state.target_count = meta.get("target_count", 10)
	_game_state.p1_hat = meta.get("p1_hat", 0)
	_game_state.p2_hat = meta.get("p2_hat", 0)
	_game_state.game_state = Constants.STATE_PLAYING

	# ReplayPlayer を設定
	replay_player = ReplayPlayer.new()
	replay_player.setup(recorder)

	# ゲームワールドをインスタンス化
	_game_world_scene = preload("res://scenes/game_world.tscn")
	_game_world = _game_world_scene.instantiate()
	_game_world.set_meta("replay_mode", true)  # ゲームワールドにリプレイモードを伝達
	add_child(_game_world)

	# ゲームワールド内のメインカメラを無効化
	var main_cam := _game_world.find_child("Camera3D", true, false) as Camera3D
	if main_cam:
		main_cam.current = false

	# リプレイカメラを設置
	replay_camera_node = ReplayCamera.new()
	replay_camera_node.name = "ReplayCamera"
	add_child(replay_camera_node)

	# リプレイHUDを設置
	var hud_script := preload("res://scripts/ui/replay_hud.gd")
	replay_hud = CanvasLayer.new()
	replay_hud.set_script(hud_script)
	add_child(replay_hud)
	replay_hud.setup(replay_player, replay_camera_node)

	# 最初のフレームを適用してから再生開始
	replay_player.apply_to_game_state(_game_state)
	replay_player.play()

	# マウスカーソルを表示
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(dt: float) -> void:
	if not replay_player or not replay_player.is_playing:
		return

	# 再生を進める
	replay_player.advance(dt)

	# 状態をゲームステートに注入
	replay_player.apply_to_game_state(_game_state)

	# カメラのターゲットを更新
	if replay_camera_node:
		var scroll := _game_state.world_scroll_z
		replay_camera_node.update_targets(
			Vector3(_game_state.player_x, _game_state.player_y, _game_state.player_z - scroll),
			Vector3(_game_state.player2_x, _game_state.player2_y, _game_state.player2_z - scroll)
		)
		replay_camera_node.update_camera(dt)

func _unhandled_input(event: InputEvent) -> void:
	# リプレイカメラへの入力転送
	if replay_camera_node:
		replay_camera_node.handle_input(event)

	# ESCで閉じる
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")

	# スペースで再生/停止
	if event is InputEventKey and event.keycode == KEY_SPACE and event.is_pressed() and not event.is_echo():
		if replay_player:
			if not replay_player.is_playing:
				replay_player.play()
			else:
				replay_player.pause()
