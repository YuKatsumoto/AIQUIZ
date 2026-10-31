extends Node3D
class_name CountdownKeyHints

## 本編のスタート前カウントダウンのあいだ、キャラクターの頭上に操作キー（移動キーとジャンプ）をうっすら小さく浮かべる。
## ジャンプキーは移動キーの横に置く（P1 の Space は D の右、P2 の右Ctrl は ← の左）。
## キーの形・並べ方・押し込みは KeyGuides3D
## （res://scripts/world/key_guides_3d.gd）を半透明にして使い、ここでは出すタイミングと濃さだけを決める。
## - ローカル1P: WASD（矢印キーを押せば矢印）+ Space
## - ローカル2P: P1 = WASD + Space、P2 = 矢印キー + 右Ctrl
## - オンライン: 自分のキャラクターの上にだけ WASD / 矢印キー + Space
## GO の後もそのまま残し、そのプレイヤーが移動キーかジャンプキーを押したら、その人の分だけじんわり消す。
## 押さないまま走行が終わった（最初の壁に着いた・脱落した）ときも同じように消す。

const KeyGuidesScript = preload("res://scripts/world/key_guides_3d.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")

## いちばん濃いときの不透明度。
const MAX_OPACITY := 0.4
const FADE_IN_SECONDS := 0.5
## 操作キーを押してから消えきるまでの時間。
const FADE_OUT_SECONDS := 0.35

## KeyGuides3D の標準の大きさに対する倍率。
const KEY_SCALE := 0.6

const MODEL_SLOTS := ["left", "right", "up", "down", "jump"]

var game_state: QuizGameState = null

var _key_guides: KeyGuides3D = null
## プレイヤー番号 → 濃さ（0〜1）。
var _fades: Dictionary = {}
## プレイヤー番号 → 消し始めたか。
var _dismissed: Dictionary = {}


## online_slot はオンラインの自分のスロット（ローカルプレイは 0）。
func setup(state: QuizGameState, online_slot: int = 0) -> void:
	game_state = state
	_key_guides = KeyGuidesScript.new()
	_key_guides.name = "KeyGuides3D"
	add_child(_key_guides)
	_key_guides.setup(state, state.num_players >= 2, online_slot, true, true)
	_key_guides.set_opacity(0.0)
	for player_index: int in _key_guides.get_players():
		_fades[player_index] = 0.0
		_dismissed[player_index] = true


func update(delta: float) -> void:
	if game_state == null:
		return
	if MobileUi.is_touch_ui():
		# スマホ：画面のスティックとボタンがいつも見えているので、頭上のキーは出さない。
		_key_guides.update(delta, _model(), false)
		return
	var counting := game_state.game_state == Constants.STATE_COUNTDOWN
	var playing := game_state.game_state == Constants.STATE_PLAYING
	var any_shown := false
	for player_index: int in _fades.keys():
		var fade: float = _fades[player_index]
		if counting:
			_dismissed[player_index] = false
			fade = move_toward(fade, 1.0, delta / FADE_IN_SECONDS)
		else:
			if not _dismissed[player_index] and (not playing or _key_guides.is_player_pressing(player_index)):
				_dismissed[player_index] = true
			if _dismissed[player_index]:
				fade = move_toward(fade, 0.0, delta / FADE_OUT_SECONDS)
		_fades[player_index] = fade
		_key_guides.set_opacity(MAX_OPACITY * fade, player_index)
		any_shown = any_shown or fade > 0.0
	_key_guides.update(delta, _model(), any_shown)


## 検証用。
func get_key_guides() -> KeyGuides3D:
	return _key_guides


## 検証用。そのプレイヤーのキーの濃さ（0〜1、MAX_OPACITY を掛ける前）。
func get_fade(player_index: int) -> float:
	return float(_fades.get(player_index, 0.0))


func _model() -> Dictionary:
	var tasks := [{"slots": MODEL_SLOTS, "done": false}]
	# 消えきったプレイヤーのキーは並べない。
	var players: Array = []
	for player_index: int in _fades.keys():
		if float(_fades[player_index]) > 0.0:
			players.append({"player": player_index, "tasks": tasks})
	return {
		"key_layout": KeyGuides3D.LAYOUT_CLUSTER,
		"plain_keys": true,
		"key_scale": KEY_SCALE,
		"players": players,
	}
