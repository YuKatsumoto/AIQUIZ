class_name SkyGateDebug
extends Node3D

## 「つきやぶれ！スカイゲート」を監督なしで遊ぶデバッグの入口（docs/sudden_death_v2/skygate_build_plan.md 3.2 の W4）。
## 乗り込み・降下（W6）は飛ばして、図解ルールカードから始まる。2人とも突破したら着地台へ降り、そのまま次のラウンドへ
## （水上機の迎えと降下は飛ばす）。決着のあとは勝者のダンス（1・2・3 / 8・9・0）。
##
##   ./Godot_v4.7.2-stable_win64.exe --path . --script res://scripts/world/sudden_death/games/sky_gate_debug_bootstrap.gd
##   （後ろに -- を付けて：quality=low|balanced|high、round=3（そのラウンドから）、p1=right|wrong|none、p2=…（自動で動かす）、english）
##
## キー：P1 は W・A・S・D、P2 は ↑・←・↓・→。Enter でルールカードを閉じる。R でやり直し、Esc で終わる。
## テスト（tests/sudden_death_v2/sky_gate_runtime.gd）は manual を true にして step_frame() で 1 フレームずつ進める。

## ラウンドのあと、着地台で「ROUND n」を見せ終えてから次のラウンドの空へ戻るまで（水上機の迎えの代わり）。
const REBOARD_WAIT := 1.0
const DANCE_TIME := 12.0

## 自動で動かす：{1: "right" / "wrong" / "none" / ""（キー）, 2: …}。
var autopilot := {1: "", 2: ""}
## true なら _process で進めない（テストが step_frame を呼ぶ）。
var manual := false
var quality := ""
var start_round := 1
var english := false
var auto_confirm := false

var game: SkyGateGame = null
var presenter: SkyGatePresenter = null
var state: QuizGameState = null
var sky: SuddenDeathSkySet = null
var camera: Camera3D = null
var common_hud: SuddenDeathHud = null
var frame_count := 0
var clock := 0.0

var _sun: DirectionalLight3D = null
var _env: WorldEnvironment = null
var _ready_to_play := false
var _prep: Array[Callable] = []
var _wait := 0.0
var _dance_t := -1.0
var _jumped := false
var _help: Label = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		match pair[0]:
			"quality":
				quality = pair[1] if pair.size() > 1 else ""
			"round":
				start_round = clampi(int(pair[1]), 1, SkyGateGame.ROUNDS) if pair.size() > 1 else 1
			"p1", "p2":
				autopilot[1 if pair[0] == "p1" else 2] = pair[1] if pair.size() > 1 else "right"
			"english":
				english = true
			"auto":
				auto_confirm = true
	if not manual:
		build()


## 場面を作る（空・光・空のセット・カメラ・共通の HUD・見せ方）。見せ方の組み立ては start() までに全部済ませる。
func build() -> void:
	if quality == "":
		quality = String(GameManager.graphics_quality)
	_make_environment()
	camera = Camera3D.new()
	camera.name = "SkyGateCamera"
	camera.near = 0.1
	camera.far = 5000.0
	camera.fov = SkyGatePresenter.MAIN_FOV
	add_child(camera)
	camera.make_current()
	sky = SuddenDeathSkySet.new()
	sky.name = "SuddenDeathSky"
	add_child(sky)
	sky.position = HeliSuddenDeathDirector.SKY_ORIGIN
	sky.build(quality, _sun.global_basis.z)
	common_hud = SuddenDeathHud.new()
	add_child(common_hud)
	common_hud.setup(english)
	state = QuizGameState.new()
	state.use_english_ui = english
	presenter = SkyGatePresenter.new()
	presenter.name = "SkyGatePresenter"
	add_child(presenter)
	_new_game()
	for step: Callable in presenter.preparation_steps():
		step.call()
	# 監督と同じく、見せ方の環境（本戦用の空撮の環境）をカメラに当てる
	camera.environment = presenter.environment()
	if not manual:
		_help = Label.new()
		_help.text = "P1: WASD   P2: ←↑↓→   Enter: ルールカードを閉じる   R: やり直し   Esc: 終わる"
		_help.position = Vector2(12, 698)
		_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		_help.add_theme_font_size_override("font_size", 13)
		var layer := CanvasLayer.new()
		layer.layer = 20
		layer.add_child(_help)
		add_child(layer)
	start()


func _new_game() -> void:
	game = SkyGateGame.new()
	game.setup(sample_questions(), 20261019)
	game.extra_question = func() -> QuizItem:
		return _math_question(game.rng)
	state.sudden_death_game = game
	presenter.setup_solo(state, game, sky, camera, common_hud, _sun)


## 図解ルールカードから始める。
func start() -> void:
	_dance_t = -1.0
	_wait = 0.0
	_jumped = false
	frame_count = 0
	clock = 0.0
	presenter.begin_venue()
	_ready_to_play = true


## やり直し（R）。
func restart() -> void:
	presenter.teardown()
	_new_game()
	start()


func _process(delta: float) -> void:
	if manual or not _ready_to_play:
		return
	step_frame(delta)


func _unhandled_input(event: InputEvent) -> void:
	if manual or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key in [KEY_ENTER, KEY_KP_ENTER]:
		presenter.confirm_rules()
	elif key == KEY_R:
		restart()
	elif key == KEY_ESCAPE:
		get_tree().quit()


## 1 フレーム：入力 → ルール → 出来事を見せ方へ → 見せ方 → カメラ。
func step_frame(dt: float) -> void:
	frame_count += 1
	clock += dt
	if auto_confirm and presenter.phase_name() == "rules" and clock > 1.0:
		presenter.confirm_rules()
	game.step(dt, {"move": [_move(1), _move(2)]})
	_flush_events()
	presenter.update_venue(dt)
	_flush_events()
	if start_round > 1 and not _jumped and game.is_running() and game.current_round == 1:
		_jump_to_round(start_round)
	if presenter.round_cleared():
		_wait += dt
		if _wait >= REBOARD_WAIT:
			_wait = 0.0
			presenter.begin_round(game.current_round + 1)
			_flush_events()
	var view := presenter.venue_camera()
	if presenter.finale_done() or _dance_t >= 0.0:
		if _dance_t < 0.0:
			_dance_t = 0.0
		_dance_t += dt
		presenter.set_solo_emote_keys(_emote_mask(1), _emote_mask(2))
		presenter.pose_winner_waiting(presenter.winner(), _dance_t)
		view = presenter.extract_camera(presenter.winner(), Vector3(0.0, 0.0, 0.0))
		if _dance_t > DANCE_TIME and not manual:
			restart()
			return
	if not view.is_empty():
		camera.global_transform = view.transform
		camera.fov = float(view.get("fov", camera.fov))
	if manual:
		presenter.debug_step_clock(dt)
		common_hud.debug_manual_clock = true
		common_hud.debug_step(dt)


func _flush_events() -> void:
	for event: Dictionary in game.events:
		presenter.on_event(event)
	game.events.clear()


## round=N：ROUND 1 の頭から、着地したことにして N ラウンド目へ（ルールの数字だけ進める）。
func _jump_to_round(number: int) -> void:
	_jumped = true
	game.events.clear()
	game.current_round = number - 1
	game.phase = "landing"
	presenter.begin_round(number)
	_flush_events()


## 押しっぱなしの向き（x＝右、y＝前）。自動のときは正解（または外れ）のパネルへ向かう。
func _move(player: int) -> Vector2:
	var mode := str(autopilot.get(player, ""))
	if mode != "":
		return autopilot_move(player, mode)
	var keys := [KEY_W, KEY_A, KEY_S, KEY_D] if player == 1 else [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]
	var x := (1.0 if Input.is_key_pressed(keys[3]) else 0.0) - (1.0 if Input.is_key_pressed(keys[1]) else 0.0)
	var y := (1.0 if Input.is_key_pressed(keys[0]) else 0.0) - (1.0 if Input.is_key_pressed(keys[2]) else 0.0)
	return Vector2(x, y).limit_length(1.0)


func autopilot_move(player: int, mode: String) -> Vector2:
	if game == null or game.phase != "gate" or mode == "none":
		return Vector2.ZERO
	var right := game.correct_choice()
	var panel := right if mode == "right" else (right + 3) % 4
	# 判断の間（ゲートの頭 1.2 秒）は少し迷ってから向かう
	if game.gate_clock() < 1.2:
		return Vector2(sin(game.gate_clock() * 3.0 + float(player)) * 0.3, 0.0)
	var side := Vector2(-0.7 if player == 1 else 0.7, 0.0) * game.board_scale()
	var target := SkyGateBoard.PANEL_CENTERS[panel] * game.board_scale() + Vector2(game.board_offset(), 0.0) + side
	var d := target - game.pos[player - 1]
	if d.length() < 0.25:
		return Vector2.ZERO
	return d.normalized() * clampf(d.length() / 1.5, 0.35, 1.0)


func _emote_mask(player: int) -> int:
	if manual:
		return 0
	var keys := [KEY_1, KEY_2, KEY_3] if player == 1 else [KEY_8, KEY_9, KEY_0]
	var mask := 0
	for i in range(3):
		if Input.is_key_pressed(keys[i]):
			mask |= 1 << i
	return mask


## ステージと同じ空と太陽（StageEnvironment の設定と同じ。W7 のデバッグの入口 sky_fx_debug.gd と同じ作り）。
## 本戦の画はカメラに見せ方の環境（SkyFallScenery.venue_environment）を当てる。
func _make_environment() -> void:
	var env := Environment.new()
	StageEnvironment.configure_stage_environment(env)
	GraphicsQuality.apply_environment(env, GraphicsQuality.normalize(quality))
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-50, -20, 0)
	_sun.light_color = Color(0.90, 0.92, 0.95)
	_sun.light_energy = 1.2
	GraphicsQuality.configure_directional_shadow(_sun, quality)
	_sun.shadow_enabled = GraphicsQuality.gameplay_shadow_enabled(quality)
	add_child(_sun)


# ------------------------------------------------------------------ questions

## 見本の問題（算数・ことば）。本番は QuizGameState が用意した 20 問。
static func sample_questions() -> Array[QuizItem]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var out: Array[QuizItem] = [
		QuizItem.create("8 + 7 = ?", PackedStringArray(["13", "15", "16", "14"]), 1, "", "DEBUG"),
		QuizItem.create("日本で一番高い山は？", PackedStringArray(["富士山", "北岳", "槍ヶ岳", "穂高岳"]), 0, "", "DEBUG"),
		QuizItem.create("3 × 4 = ?", PackedStringArray(["12", "7", "34", "16"]), 0, "", "DEBUG"),
		QuizItem.create("水がこおる温度は？", PackedStringArray(["10℃", "100℃", "0℃", "-10℃"]), 2, "", "DEBUG"),
	]
	while out.size() < SkyGateGame.QUESTION_COUNT:
		out.append(_math_question(rng))
	return out


static func _math_question(rng: RandomNumberGenerator) -> QuizItem:
	var a := rng.randi_range(2, 19)
	var b := rng.randi_range(2, 9)
	var plus := rng.randf() < 0.5
	var answer := a + b if plus else a * b
	var wrongs: Array[int] = []
	for delta: int in [1, -1, 2, -2, 10, -10, 3]:
		var w := answer + delta
		if w > 0 and not wrongs.has(w) and wrongs.size() < 3:
			wrongs.append(w)
	var at := rng.randi_range(0, 3)
	var choices := PackedStringArray()
	var k := 0
	for i in range(4):
		if i == at:
			choices.append(str(answer))
		else:
			choices.append(str(wrongs[k]))
			k += 1
	return QuizItem.create("%d %s %d = ?" % [a, "+" if plus else "×", b], choices, at, "", "DEBUG")
