extends Node

## 結果カードの「◯ 良い」を、本物の gameplay_hud.tscn の上でマウスでクリックすると評価が記録される。
## 以前は PC でカードを毎フレーム作り直していて、ボタンが毎フレーム木から外れ、クリックが効かなかった。
## マウスの入力を GUI に届けるので、画面ありで動かす（ヘッドレスではクリックがどのコントロールにも届かない）。
## ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/result_rating_click_bootstrap.gd

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	QuizManager.player_analytics = null
	var hud: CanvasLayer = (load("res://ui/gameplay_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var provider := TestProvider.new()
	var gs := QuizGameState.new(provider)
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	var quiz := QuizItem.create("評価の確認 1+1 は？", PackedStringArray(["2", "3"]), 0, "テスト問題です。", "OFFLINE")
	gs.quiz_list.append(quiz)
	gs.current_quiz = quiz
	gs.rating_target_quiz = quiz
	# CLEAR はカードがすぐ出る（GAME OVER は 4 秒待ってから出る）
	gs.message_text = "CLEAR!"
	gs.game_state = Constants.STATE_CLEAR
	hud.set("game_state", gs)
	# 点数の数え上げ（1.5 秒ぶん）が終わるまで進める
	for frame: int in range(150):
		await get_tree().process_frame
	var good := hud.get("btn_good") as Button
	var panel := hud.get("game_over_panel") as Control
	var rate_box := hud.get("go_rate_box") as Control
	_check(good != null and good.is_visible_in_tree(), "the 良い button is on the result card", {
		"panel": panel.visible if panel else null, "rate_box": rate_box.visible if rate_box else null,
		"rate_parent": str(rate_box.get_parent().name) if rate_box and rate_box.get_parent() else "",
		"good_visible": good.visible if good else null, "good_parent": good.get_parent().visible if good else null,
		"state": gs.game_state, "pending": gs.is_elimination_result_pending()})
	if good == null or not good.is_visible_in_tree():
		_finish(provider)
		return
	var at := good.get_global_rect().get_center()
	var downs := [0]
	good.button_down.connect(func() -> void: downs[0] += 1)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	_click(at, true)
	for frame: int in range(3):
		await get_tree().process_frame
	var held := good.button_pressed
	_click(at, false)
	for frame: int in range(3):
		await get_tree().process_frame
	_check(not gs.rating_feedback.is_empty(), "clicking 良い records the rating", {
		"feedback": gs.rating_feedback, "downs": downs[0], "held": held, "at": at,
		"hovered": str(hovered.get_path()) if hovered else "none", "good": str(good.get_path()),
		"vp": get_viewport().get_visible_rect().size})
	_finish(provider)


func _click(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	get_viewport().push_input(event)


func _finish(provider: QuizProvider) -> void:
	print("RESULT_RATING_CLICK " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	provider.free()
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not ok:
		failures.append(label if detail == null else "%s: %s" % [label, str(detail)])
