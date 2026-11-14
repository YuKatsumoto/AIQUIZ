extends "res://tests/submission_video/take_base.gd"

## プレイ動画 F（サドンデス「つきやぶれ！スカイゲート」。開発中の機能で、書き出した版には入っていない）。
## ローカル 2 人の 10 問を始め、デバッグの入口（F9 と同じ GameWorld._debug_force_draw_finish）でスコアタワーを引き分けにする。
## そこから本物の流れ：DRAW → SUDDEN DEATH の分岐 → 種目発表 → 水上機で空へ → ルールカード（Enter）→ 本戦
## （P1 は W・A・S・D、P2 は矢印キーで正しいパネルの上へ動く）→ 決着 → 勝者のダンス → 帰還 → 勝者の演出。
## 動画は引き分けの判定が出る少し前から使う（report の marks の "draw"）。
## 操作はボット：ROUND 1 は 2 人とも 4 枚を突破、ROUND 2 の 2 枚目で P2 がまちがえて P1 の勝ち。
## 読む間・行き過ぎ・立ち直しを入れる。設定とスキンの保存先は撮影用のファイルに替える。
##   python -X utf8 tests/submission_video/record_take.py sudden_death <出力フォルダ>

const GAME_WORLD := "res://scenes/game_world.tscn"
## P2 がまちがえるゲート（ラウンド, 何枚目）
const P2_WRONG := Vector2i(2, 1)
const MOVE_KEYS := [[KEY_W, KEY_A, KEY_S, KEY_D], [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]]

var gs: QuizGameState
var world: Node
var director: HeliSuddenDeathDirector
var _acts: Array = []
var _gate_key := ""
var _plans := [{}, {}]
var _dance_taps := 0
var _dance_next := 0.0
var _rules_at := -1.0


func run() -> void:
	rng.seed = 20261113
	gs = QuizManager.game_state
	use_capture_settings("sudden_death")
	QuizManager.provider.set_llm_mode("OFFLINE")
	QuizGameState.sudden_death_available = true
	GameManager.sudden_death_enabled = true
	gs.sudden_death_enabled = true
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.subject = "算数"
	gs.grade = 3
	gs.difficulty = "普通"
	# メニューの『ゲーム開始』と同じ順：覆ってから試合の状態を作り、ゲームの画面へ
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, true)
	gs.start_game_under_transition()
	gs.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file(GAME_WORLD)
	if not await wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == GAME_WORLD and bool(scene.call("_can_trigger_start")), 180.0):
		finish("the round was never ready to start (state %s)" % gs.game_state)
		return
	world = get_tree().current_scene
	director = world.get("_sudden_death_director") as HeliSuddenDeathDirector
	await sleep(1.0)
	tap(KEY_ENTER, 0.1)
	if not await wait_until(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 40.0):
		finish("never reached PLAYING (state %s)" % gs.game_state)
		return
	report["uses_sudden_death"] = gs.uses_sudden_death()
	await sleep(1.5)
	# F9 と同じ：ゴールで引き分けにして、スコアタワーの決着演出から見せる
	world.call("_debug_force_draw_finish")
	if not await wait_until(func() -> bool: return gs.result_presentation_active and not SceneTransition.is_transitioning(), 20.0):
		finish("the forced draw did not start the finale")
		return
	mark("draw")
	report["draw"] = {"winner": gs.result_winner, "pending": gs.sudden_death_pending, "kind": gs.sudden_death_kind}
	shot_once("sudden_death_draw", 7.4)
	shot_once("sudden_death_cut_in", 8.9)
	if not await wait_until(func() -> bool: return gs.game_state == Constants.STATE_SUDDEN_DEATH, 90.0):
		finish("the sudden death never started (act %s, state %s)" % [director.act_name() if director else "?", gs.game_state])
		return
	mark("sudden_death")
	# 決着して、地上で勝者の演出が終わり、ボタンが出るまで
	if not await wait_until(func() -> bool:
			return gs.game_state != Constants.STATE_SUDDEN_DEATH and gs.result_presentation_active \
				and QuizGameState.ResultCeremonyPhase.keys()[gs.result_ceremony_phase] == "INTERACTIVE", 400.0):
		finish("the sudden death did not come back to the finale (act %s, state %s)" % [director.act_name(), gs.game_state])
		return
	mark("interactive")
	report["winner"] = gs.result_winner
	release_all()
	await sleep(5.0)
	mark("end")
	finish()


func brain(_delta: float) -> void:
	if director == null or world == null or not is_instance_valid(world):
		return
	var act := director.act_name()
	if _acts.is_empty() or _acts[-1] != act:
		_acts.append(act)
		report["acts"] = _acts
		mark("act_" + act + "_%d" % _acts.size())
		shot_once("sudden_death_act_%02d_%s" % [_acts.size(), act.to_lower()], 2.0)
	if gs.game_state != Constants.STATE_SUDDEN_DEATH:
		return
	# 窓がフォーカスを失っていても、キーの向きを読ませる（撮影の窓は画面の外にあって、フォーカスを持たない）
	world.set("_push_focus_lost", false)
	# ルールカード：少し読んでから Enter
	if director.is_rules_card_waiting():
		if _rules_at < 0.0:
			_rules_at = t
			shot_once("sudden_death_rules", 2.5)
		elif t - _rules_at > 6.0 and not is_held(KEY_ENTER):
			tap(KEY_ENTER, 0.1)
			_rules_at = t - 4.5
		return
	var presenter := director.presenter()
	var phase := str(presenter.get("_phase")) if presenter != null else ""
	if phase == "dance":
		_release_moves()
		shot_once("sudden_death_dance", 2.5)
		# 勝者（P1）がエモートのキーで踊る
		if _dance_taps < 3 and t > _dance_next:
			_dance_next = t + rng.randf_range(2.2, 3.0)
			tap([KEY_2, KEY_3, KEY_1][_dance_taps], 0.15)
			_dance_taps += 1
		return
	var game := gs.sudden_death_game as SkyGateGame
	if game == null or not game.is_running() or game.phase != "gate":
		_release_moves()
		return
	var key := "%d-%d" % [game.current_round, game.gate_index]
	if key != _gate_key:
		_gate_key = key
		for i in range(2):
			_plans[i] = {"read": rng.randf_range(1.3, 2.4) + (0.3 if i == 1 else 0.0), "wobble": Vector2.ZERO,
				"wobble_at": 0.0, "next": 0.0, "dir": Vector2.ZERO}
		if game.gate_index == 0:
			shot_once("sudden_death_round%d_board" % game.current_round, 3.0)
	if game.time_to_contact() < 0.9:
		shot_once("sudden_death_gate_%s" % key)
	for i in range(2):
		_steer(game, i)


## 正しい（P2 は決めたゲートだけ、まちがった）パネルの上へ、キーで動く。
func _steer(game: SkyGateGame, index: int) -> void:
	var plan: Dictionary = _plans[index]
	var keys: Array = MOVE_KEYS[index]
	if game.gate_clock() < float(plan.read):
		_set_move(keys, Vector2.ZERO)
		return
	if t < float(plan.next):
		return
	plan.next = t + rng.randf_range(0.06, 0.12)
	var right := game.correct_choice()
	var panel := right
	if index == 1 and Vector2i(game.current_round, game.gate_index) == P2_WRONG:
		panel = (right + 3) % 4
	if t > float(plan.wobble_at) and game.time_to_contact() > 1.5:
		plan.wobble_at = t + rng.randf_range(1.2, 2.4)
		plan.wobble = Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
	var side := Vector2(-0.8 if index == 0 else 0.8, 0.0) * game.board_scale()
	var target: Vector2 = SkyGateBoard.PANEL_CENTERS[panel] * game.board_scale() + Vector2(game.board_offset(), 0.0) + side
	if game.time_to_contact() > 1.5:
		target += plan.wobble
	var d: Vector2 = target - game.pos[index]
	var dead := 0.45 if game.time_to_contact() < 1.5 else 0.7
	_set_move(keys, Vector2(signf(d.x) if absf(d.x) > dead else 0.0, signf(d.y) if absf(d.y) > dead else 0.0))


## keys は [前, 左, 後, 右]。direction は x＝右、y＝前。
func _set_move(keys: Array, direction: Vector2) -> void:
	hold(keys[0], direction.y > 0.0)
	hold(keys[2], direction.y < 0.0)
	hold(keys[3], direction.x > 0.0)
	hold(keys[1], direction.x < 0.0)


func _release_moves() -> void:
	for keys: Array in MOVE_KEYS:
		_set_move(keys, Vector2.ZERO)
