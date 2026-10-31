extends Node

## コース⑤（カスタマイズ）の実機の通しテスト（docs/new_tutorial/phase8_design.md 2章、course5_script.md v0.2）。
##   1回目：メニューのコース選択から⑤を選ぶ（画面は移らない）→ 操縦席のハテナが雲で出てくる → 5-1『10問チャレンジ』→『カスタマイズ』
##          → 5-2 帽子（『スキン』→ ▶）→ 5-3 エモート（『エモート』→ 踊りを1つ）→ 5-4 壁の速さ（『壁速度』→ スライダー → 元に戻る）
##          → 5-5『✓ 決定して戻る』→ 5-6『設定 / API状態』（小窓のハテナ）→『戻る』→ クリアカードとスタンプ →［メニューに戻る］
##   2回目：スタンプが4つある形で、Esc で 5-1〜5-6 を とばす（とばしても次の画面は練習が開く・閉じる。5-4 は動かしてから
##          とばして、壁の速さが戻る）→ クリアで「スタンプが全部そろったね！」→ Esc で［メニューに戻る］
## 光っていない所は押せないこと、帽子が保存されること、壁の速さが戻ること、ハテナの居場所（メニューは右・カスタマイズは左上）も確かめる。
## 設定（スタンプ）とスキン（帽子）の保存先はテスト用に差し替え、テストの後で元に戻す。撮った画面は artifacts/practice_course5/。

const OUT := "res://artifacts/practice_course5/"
const SETTINGS := "user://practice_course5_smoke_settings.json"
const SKINS := "user://practice_course5_smoke_skins.json"
const MAIN_MENU := "res://ui/main_menu.tscn"

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 案内が言った言葉の ID（順に）
var said: Array[String] = []
var phases: Array[StringName] = []
var _held := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "skin_path": PlayerSkinStore.path, "subject": gs.subject, "grade": gs.grade,
		"difficulty": gs.difficulty, "players": gs.num_players, "mode": gs.mode, "wall": gs.tuning.wall_speed_override,
		"p1_emotes": gs.p1_emote_slots.duplicate(), "p2_emotes": gs.p2_emote_slots.duplicate(),
		"llm": QuizManager.provider.llm_mode}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	# スキンの保存先も差し替える（いまの見た目のまま、書くのはテスト用のファイル）
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.tuning.wall_speed_override = 0.0
	gs.num_players = 1
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""

	var guide := await _launch()
	if guide != null:
		await _arrive(guide)
		if await _go(guide):
			await _hat(guide)
			await _emote(guide)
			await _speed(guide)
			await _done(guide)
			await _settings(guide)
			await _clear_back(guide)
	await _skip_all()
	_finish()


# ---------- 1回目：コース選択から⑤ ----------

func _launch() -> PracticeCustomizeGuide:
	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.find_child("PracticeBtn", true, false) != null \
			and not SceneTransition.is_transitioning(), 25000)
	check(ready, "the main menu opens")
	if not ready:
		return null
	await _seconds(1.0)
	var menu := _menu()
	var button := menu.find_child("PracticeBtn", true, false) as Button
	button.pressed.emit()
	var select := menu.find_child("PracticeCourseSelect", true, false) as PracticeCourseSelect
	check(select != null and select.is_open(), "the tutorial button opens the course select")
	if select == null:
		return null
	await _seconds(0.4)
	var card := select.card("c5")
	check(card != null and not card.disabled, "the c5 card can be chosen")
	if card == null or card.disabled:
		return null
	card.grab_focus()
	await _frames(2)
	await _shot("00_course_select")
	await _tap(KEY_ENTER)
	var started := await _wait(func() -> bool: return _guide() != null, 3000)
	check(started, "choosing c5 starts the customize guide")
	check(get_tree().current_scene == menu and not SceneTransition.is_transitioning(), "c5 stays on the main menu (no scene change)")
	check(not select.is_open(), "the course select closes")
	check(gs.mode != Constants.MODE_PRACTICE, "c5 does not switch the game to the practice mode")
	var guide := _guide()
	if guide == null:
		return null
	said.clear()
	phases.clear()
	guide.coach.said.connect(func(text: String) -> void: said.append(text))
	guide.phase_changed.connect(func(phase: StringName) -> void: phases.append(phase))
	check(guide.overlay.course_title() == "⑤ カスタマイズ" and guide.overlay.dot_count() == 6, "the header shows ⑤ with 6 dots")
	return guide


func _arrive(guide: PracticeCustomizeGuide) -> void:
	var saw := _menu().call("practice_menu_saw") as SawChaseController
	check(saw != null, "the menu has the saw carriage")
	var left := await _wait(func() -> bool: return guide.hatena != null and guide.hatena.visible and saw != null and saw.is_operator_hidden(), 10000)
	check(left, "the guide Hatena takes the seat Hatena's place (seat hidden, guide shown)")
	# 立ち上がって、呼んだ雲に跳び乗り、メニューの右側へ飛んでくる（PracticeSeatMoves.saw_leave。約 4 秒）
	await _seconds(1.6)
	await _shot("01_leave_seat")
	check(await _wait(func() -> bool: return guide.phase == &"5-1", 12000), "after the flight 5-1 starts")
	if guide.hatena != null:
		check(guide.hatena.has_cloud(), "the Hatena rides a cloud")
	var head := _hatena_screen(guide)
	check(head.x > 760.0 and head.x < 1280.0 and head.y > 0.0 and head.y < 720.0, "the Hatena floats on the right side of the menu (%s)" % head)


## 5-1：『10問チャレンジ』（マウス）→『カスタマイズ』（Enter）
func _go(guide: PracticeCustomizeGuide) -> bool:
	check(await _wait_said("c5.go.1", 4000), "5-1 自分らしく飾ってみよう")
	await _seconds(0.3)
	await _shot("02_go_hello")
	# 何も光っていない間は押せない
	await _click(_target(&"mode_endless"))
	await _frames(5)
	check(gs.menu_step == Constants.MENU_STEP_MODE, "the menu is blocked while Hatena talks")
	check(await _wait_said("c5.go.2", 5000), "5-1『10問チャレンジ』を押してみて")
	await _frames(3)
	check(_lit(guide) == [_target(&"mode_ten")] and guide.coach.is_clickable(), "10問チャレンジ is lit and pressable")
	await _click(_target(&"mode_endless"))
	await _frames(5)
	check(gs.menu_step == Constants.MENU_STEP_MODE, "エンドレス (not lit) cannot be pressed")
	await _shot("03_go_ten")
	await _click(_target(&"mode_ten"))
	if not await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 2000):
		check(false, "10問チャレンジ opens the config screen")
		return false
	check(await _wait_said("c5.go.3", 5000), "5-1『カスタマイズ』を押してみて")
	await _frames(3)
	check(_lit(guide) == [_target(&"customize")], "カスタマイズ is lit")
	await _click(_target(&"start"))
	await _frames(5)
	check(get_tree().current_scene == _menu() and not bool(_menu().call("practice_customize_open")), "ゲーム開始 (not lit) cannot be pressed")
	await _seconds(0.3)
	await _shot("04_go_customize")
	# キーボードでも押せる（光っている『カスタマイズ』にフォーカスがある）
	await _tap(KEY_ENTER)
	var opened := await _wait(func() -> bool: return bool(_menu().call("practice_customize_open")), 2000)
	check(opened, "Enter on カスタマイズ opens the customize screen")
	return opened


## 5-2：『スキン』→ 帽子の ▶ → 似合ってる → プレイヤー１・２ → 右ドラッグ
func _hat(guide: PracticeCustomizeGuide) -> void:
	check(await _wait(func() -> bool: return guide.phase == &"5-2", 5000), "5-2 starts when the customize screen opens")
	check(await _wait_said("c5.hat.1", 6000), "5-2『スキン』を押して帽子を選ぼう")
	await _frames(3)
	var head := _hatena_screen(guide)
	check(head.x > 0.0 and head.x < 420.0 and head.y > 0.0 and head.y < 420.0, "on the customize screen the Hatena floats at the upper left (%s)" % head)
	check(guide.hatena.scale.x < PracticeCustomizeGuide.HATENA_SCALE * 0.5, "near the camera the Hatena is drawn smaller (%.2f)" % guide.hatena.scale.x)
	check(guide.overlay.header_visible(), "the course header is shown on the customize screen")
	check(_lit(guide) == [_cust(&"tab_skin")], "スキン is lit")
	await _seconds(0.4)
	await _shot("05_hat_tab")
	await _click(_cust(&"tab_emote"))
	await _frames(5)
	check(_section() == &"wall", "エモート (not lit) cannot be pressed")
	await _click(_cust(&"tab_skin"))
	check(await _wait(func() -> bool: return _section() == &"skin", 2000), "スキン opens the skin tab")
	check(await _wait_said("c5.hat.2", 4000), "5-2 ◀ ▶で変えてみて")
	await _frames(3)
	check(_lit(guide) == [_cust(&"skin_hat")], "the hat ◀ ▶ row is lit")
	await _seconds(0.5)
	await _shot("06_hat_arrows")
	var before := gs.p1_hat
	var next := _cust(&"skin_hat").get_child(2) as Button
	await _click(next)
	check(await _wait(func() -> bool: return gs.p1_hat != before, 2000), "▶ changes the P1 hat (%d → %d)" % [before, gs.p1_hat])
	var line := "c5.hat.propeller" if gs.p1_hat == HatData.HAT_PROPELLER else "c5.hat.3"
	check(await _wait_said(line, 3000), "5-2 %s after the change" % line)
	PlayerSkinStore.flush()
	var skins := _read_json(SKINS)
	check(str(skins).contains(str(gs.p1_hat)), "the new hat is saved (%s)" % [skins])
	check(await _wait_said("c5.hat.4", 5000), "5-2 P2の帽子も選べる")
	await _frames(3)
	check(_lit(guide) == [_cust(&"skin_players")] and guide.coach.is_clickable(), "プレイヤー１・２ are lit and pressable")
	await _seconds(0.3)
	await _shot("07_hat_players")
	check(await _wait_said("c5.hat.5", 5000), "5-2 右ドラッグで回せる")
	await _frames(3)
	check(_lit(guide) == [_cust(&"preview")], "the preview is lit")
	check(not guide.coach.blocks_point(_center(_cust(&"preview"))), "the preview takes the mouse (right drag)")
	await _seconds(0.3)
	await _shot("08_hat_preview")


## 5-3：『エモート』→ 踊りを1つ（1番の枠に入る）→ 1番は勝ったときのダンス → 1・2・3
func _emote(guide: PracticeCustomizeGuide) -> void:
	check(await _wait(func() -> bool: return guide.phase == &"5-3", 8000), "5-3 starts")
	check(await _wait_said("c5.emote.1", 4000), "5-3 次は『エモート』を押してみて")
	await _frames(3)
	check(_lit(guide) == [_cust(&"tab_emote")], "エモート is lit")
	await _click(_cust(&"tab_emote"))
	check(await _wait(func() -> bool: return _section() == &"emote", 2000), "エモート opens the emote tab")
	check(await _wait_said("c5.emote.2", 4000), "5-3 枠を選んで踊りを入れてみよう")
	await _frames(3)
	check(_lit(guide) == [_cust(&"emote_slots"), _cust(&"emote_grid")], "the slots and the dance list are lit")
	await _seconds(0.5)
	await _shot("09_emote_pick")
	var pick: Button = null
	for child: Node in _cust(&"emote_grid").get_children():
		var id := int(child.get_meta("emote_id", 0))
		if id > 0 and not gs.p1_emote_slots.has(id):
			pick = child as Button
			break
	check(pick != null, "a dance not in the slots exists")
	if pick == null:
		return
	var picked_id := int(pick.get_meta("emote_id"))
	await _click(pick)
	check(await _wait(func() -> bool: return gs.p1_emote_slots[0] == picked_id, 2000), "the picked dance goes into slot 1 (%s)" % [gs.p1_emote_slots])
	check(await _wait_said("c5.emote.3", 3000), "5-3 いい踊りだね")
	check(await _wait_said("c5.emote.4", 5000), "5-3 1番は勝ったときのダンス")
	await _frames(3)
	check(_lit(guide) == [_cust(&"emote_slot1")] and not guide.coach.is_clickable(), "slot 1 is lit (look only)")
	await _seconds(0.3)
	await _shot("10_emote_slot1")
	check(await _wait_said("c5.emote.5", 5000), "5-3 ゲーム中は1・2・3キー")


## 5-4：『壁速度』→ 自動がおすすめ → スライダー（キー）→ 元に戻る（自動）
func _speed(guide: PracticeCustomizeGuide) -> void:
	check(await _wait(func() -> bool: return guide.phase == &"5-4", 8000), "5-4 starts")
	check(await _wait_said("c5.speed.1", 4000), "5-4『壁速度』で速さを変えてみよう")
	await _frames(3)
	await _click(_cust(&"tab_wall"))
	check(await _wait(func() -> bool: return _section() == &"wall", 2000), "壁速度 opens the wall speed tab")
	check(await _wait_said("c5.speed.2", 4000), "5-4 ふだんは自動がおすすめ")
	await _frames(3)
	check(_lit(guide) == [_cust(&"wall_mode")], "the 自動モード label is lit")
	await _seconds(0.3)
	await _shot("11_speed_auto")
	check(await _wait_said("c5.speed.3", 5000), "5-4 スライダーを動かしてみて")
	await _frames(3)
	var slider := _cust(&"wall_slider") as Range
	check(_lit(guide) == [slider] and get_viewport().gui_get_focus_owner() == slider, "the slider is lit and has the focus")
	for i in range(5):
		await _tap(KEY_RIGHT)
	check(gs.tuning.wall_speed_override > 0.0, "the arrow keys move the slider (manual %.1f)" % gs.tuning.wall_speed_override)
	await _seconds(0.2)
	await _shot("12_speed_manual")
	check(await _wait_said("c5.speed.4", 3000), "5-4 速すぎたらゆっくり")
	check(await _wait_said("c5.speed.5", 5000), "5-4 元に戻しておくね")
	await _frames(3)
	check(gs.tuning.wall_speed_override == 0.0, "the wall speed is back to auto (%.1f)" % gs.tuning.wall_speed_override)
	check((_cust(&"wall_mode") as Label).text == "自動モード", "the label reads 自動モード again")
	check(_lit(guide) == [_cust(&"wall_reset")] and not guide.coach.is_clickable(), "自動モードに戻す is shown (look only)")
	await _seconds(0.3)
	await _shot("13_speed_reset")


## 5-5：『✓ 決定して戻る』→ 設定の画面、ハテナは右へ戻る
func _done(guide: PracticeCustomizeGuide) -> void:
	check(await _wait(func() -> bool: return guide.phase == &"5-5", 8000), "5-5 starts")
	check(await _wait_said("c5.done.1", 4000), "5-5『✓ 決定して戻る』を押してね")
	await _frames(3)
	check(_lit(guide) == [_cust(&"done")], "✓ 決定して戻る is lit")
	await _shot("14_done")
	await _click(_cust(&"done"))
	check(await _wait(func() -> bool: return not bool(_menu().call("practice_customize_open")), 2000), "✓ 決定して戻る closes the customize screen")
	check(await _wait(func() -> bool: return guide.phase == &"5-6", 6000), "5-6 starts after the customize screen closes")
	check(gs.menu_step == Constants.MENU_STEP_CONFIG, "back on the config screen")


## 5-6：『設定 / API状態』→ サウンド・画面・（ゲーム）・接続状態（小窓のハテナ）→『戻る』
func _settings(guide: PracticeCustomizeGuide) -> void:
	var menu := _menu()
	check(await _wait_said("c5.set.1", 4000), "5-6 次はメニューの設定を見よう")
	var head := _hatena_screen(guide)
	check(head.x > 760.0 and head.x < 1280.0 and head.y > 0.0 and head.y < 720.0, "the Hatena is back on the right side (%s)" % head)
	check(absf(guide.hatena.scale.x - PracticeCustomizeGuide.HATENA_SCALE) < 0.01, "back to the menu size (%.2f)" % guide.hatena.scale.x)
	check(await _wait_said("c5.set.3", 5000), "5-6『設定 / API状態』を押してね")
	await _frames(3)
	check(_lit(guide) == [_target(&"settings")], "設定 / API状態 is lit")
	await _seconds(0.3)
	await _shot("15_settings_button")
	await _click(_target(&"settings"))
	check(await _wait(func() -> bool: return bool(menu.call("practice_settings_open")), 2000), "設定 / API状態 opens the settings panel")
	check(await _wait_said("c5.set.4", 4000), "5-6 音の大きさはここ")
	await _frames(3)
	var portrait := guide.coach.portrait()
	check(portrait != null and portrait.visible, "the Hatena portrait is shown over the settings panel")
	check(not guide.overlay.header_visible(), "the course header hides over the settings panel title")
	check(_lit(guide) == [_target(&"set_bgm"), _target(&"set_sfx")] and guide.coach.is_clickable(), "BGM・効果音 are lit and can be moved")
	await _seconds(0.5)
	await _shot("16_settings_sound")
	check(await _wait_said("c5.set.5", 5000), "5-6 画質を下げると軽くなる")
	await _frames(3)
	check(_lit(guide) == [_target(&"set_resolution"), _target(&"set_fps"), _target(&"set_quality")] and not guide.coach.is_clickable(),
		"解像度・FPS上限・画質 are lit (look only)")
	var quality := _target(&"set_quality").find_child("GraphicsQualityOption", true, false) as OptionButton
	var quality_before := GameManager.graphics_quality
	await _click(quality)
	await _frames(5)
	check(quality != null and not quality.get_popup().visible and GameManager.graphics_quality == quality_before, "画質 cannot be opened in practice")
	await _seconds(0.3)
	await _shot("17_settings_screen")
	var sudden := _target(&"set_sudden")
	if sudden != null and sudden.is_visible_in_tree():
		check(await _wait_said("c5.set.6", 5000), "5-6 サドンデスのオン・オフ（the row is shown）")
		await _frames(3)
		check(_lit(guide) == [sudden], "the sudden death row is lit")
		await _shot("18_settings_game")
	else:
		notes.append("no sudden death row")
	check(await _wait_said("c5.set.7", 5000), "5-6 AIの状態も分かる")
	await _frames(3)
	check(_lit(guide) == [_target(&"set_connection")], "the connection status is lit")
	var dashboard := menu.find_child("OpenDashboardBtn", true, false) as Control
	check(dashboard != null and guide.coach.blocks_point(_center(dashboard)), "管理ダッシュボードを開く cannot be pressed")
	await _seconds(0.3)
	await _shot("19_settings_connection")
	check(await _wait_said("c5.set.8", 5000), "5-6 閉じてメニューへ戻ろう")
	await _frames(3)
	check(_lit(guide) == [_target(&"set_back")], "戻る is lit")
	await _shot("20_settings_back")
	await _click(_target(&"set_back"))
	check(await _wait(func() -> bool: return not bool(menu.call("practice_settings_open")), 2000), "戻る closes the settings panel")
	check(await _wait(func() -> bool: return portrait == null or not portrait.visible, 2000), "the portrait goes away")
	check(guide.overlay.header_visible(), "the course header is back after the settings panel")


## クリア：カードとスタンプ（★なし）→［メニューに戻る］（マウス）でモード選択へ、ハテナは席へ
func _clear_back(guide: PracticeCustomizeGuide) -> void:
	check(await _wait_said("c5.clear.1", 6000), "クリア 自分だけのスタイル")
	await _seconds(0.5)
	await _shot("21_clear_hatena")
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 5000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	check(GameManager.has_practice_stamp("c5") and not GameManager.practice_stamp_star("c5"), "c5 gets a stamp (no star)")
	var stamps: Variant = _read_json(SETTINGS).get("practice_stamps", {})
	check(stamps is Dictionary and (stamps as Dictionary).has("c5"), "the c5 stamp is saved (%s)" % [stamps])
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 1 and buttons[0].text == "メニューに戻る", "the card has メニューに戻る")
	var labels := _label_texts(guide.overlay)
	check(labels.has("⑤ カスタマイズ") and labels.has("クリア"), "the card reads ⑤ カスタマイズ / クリア")
	check(await _wait_said("c5.clear.2", 6000), "クリア 楽しんでね")
	check(not said.has("c5.clear.all"), "not all stamps yet: no スタンプが全部そろった")
	await _seconds(0.5)
	await _shot("22_clear_card")
	if buttons.size() == 1:
		await _click(buttons[0])
	var done := await _wait(func() -> bool: return _guide() == null, 9000)
	check(done, "メニューに戻る ends the course")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "メニューに戻る goes back to the mode select")
	var saw := _menu().call("practice_menu_saw") as SawChaseController
	check(saw != null and not saw.is_operator_hidden(), "the Hatena is back in the seat")
	await _seconds(0.5)
	await _shot("23_after_back")
	# 本物のメニューの操作が戻っている（コーチの押せない仕組みが残っていない）
	await _click(_target(&"mode_ten"))
	check(await _wait(func() -> bool: return gs.menu_step == Constants.MENU_STEP_CONFIG, 2000), "the real menu works again after the course")
	_menu().call("practice_menu_show_mode")
	await _seconds(0.6)


# ---------- 2回目：Esc で とばす ----------

func _skip_all() -> void:
	for id: String in ["c1", "c2", "c3", "c4"]:
		GameManager.practice_stamps[id] = {"star": false}
	GameManager.practice_stamps.erase("c5")
	var menu := _menu()
	if menu == null:
		check(false, "the menu is still there for the second run")
		return
	PracticeSession.launch(menu, "c5")
	var started := await _wait(func() -> bool: return _guide() != null, 3000)
	check(started, "PracticeSession.launch starts c5 on the menu")
	if not started:
		return
	var guide := _guide()
	said.clear()
	guide.coach.said.connect(func(text: String) -> void: said.append(text))
	check(await _wait_said("c5.go.1", 12000), "skip run: 5-1 begins")
	await _tap(KEY_ESCAPE)
	# 5-1 をとばすと、練習がカスタマイズを開く
	check(await _wait(func() -> bool: return guide.phase == &"5-2", 3000), "Esc skips 5-1")
	check(await _wait(func() -> bool: return bool(menu.call("practice_customize_ready")), 5000), "the practice opens the customize screen after skipping 5-1")
	check(await _wait_said("c5.hat.1", 5000), "skip run: 5-2 begins on the customize screen")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.phase == &"5-3", 3000), "Esc skips 5-2")
	check(await _wait_said("c5.emote.1", 5000), "skip run: 5-3 begins")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.phase == &"5-4", 3000), "Esc skips 5-3")
	# 5-4：スライダーを動かしてからとばしても、壁の速さは元に戻る（5-2・5-3 をすぐとばしたので、タブは『壁速度』のまま。
	# 開いているタブを押す一言はとばす）
	check(_section() == &"wall", "skip run: the wall speed tab is still open")
	check(await _wait_said("c5.speed.3", 8000), "skip run: スライダーを動かしてみて")
	check(not said.has("c5.speed.1"), "skip run: no 『壁速度』を押して when the tab is already open")
	await _frames(3)
	for i in range(4):
		await _tap(KEY_RIGHT)
	check(gs.tuning.wall_speed_override > 0.0, "skip run: the slider moved (manual)")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.phase == &"5-5", 3000), "Esc skips 5-4")
	check(gs.tuning.wall_speed_override == 0.0, "skipping 5-4 still puts the wall speed back to auto")
	check(await _wait_said("c5.done.1", 5000), "skip run: 5-5 begins")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.phase == &"5-6", 5000), "Esc skips 5-5")
	check(not bool(menu.call("practice_customize_open")) and gs.menu_step == Constants.MENU_STEP_CONFIG,
		"the practice closes the customize screen after skipping 5-5")
	check(await _wait_said("c5.set.3", 8000), "skip run: 5-6 設定 / API状態")
	await _click(_target(&"settings"))
	check(await _wait_said("c5.set.4", 4000), "skip run: the settings panel lesson")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return guide.phase == &"clear", 3000), "Esc skips 5-6")
	check(await _wait(func() -> bool: return not bool(menu.call("practice_settings_open")), 2000), "the practice closes the settings panel after skipping 5-6")
	check(guide.skipped == 6, "six lessons skipped (%d)" % guide.skipped)
	check(await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 6000), "skip run: the clear card")
	check(await _wait_said("c5.clear.all", 5000), "all five stamps: スタンプが全部そろったね")
	check(guide.all_stamps(), "all five stamps are set")
	await _seconds(0.3)
	await _shot("24_all_stamps")
	check(await _wait_said("c5.clear.2", 5000), "skip run: 楽しんでね")
	await _tap(KEY_ESCAPE)
	check(await _wait(func() -> bool: return _guide() == null, 5000), "Esc on the card is メニューに戻る")
	check(gs.menu_step == Constants.MENU_STEP_MODE, "skip run: back on the mode select")


# ---------- 道具 ----------

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _menu() -> Control:
	var scene := get_tree().current_scene
	return scene as Control if scene != null and scene.scene_file_path == MAIN_MENU else null


func _guide() -> PracticeCustomizeGuide:
	var menu := _menu()
	return menu.call("practice_customize_guide") as PracticeCustomizeGuide if menu != null else null


func _target(id: StringName) -> Control:
	return _menu().call("practice_coach_target", id) as Control


func _cust(id: StringName) -> Control:
	var customize := _menu().call("practice_customize") as Control
	return customize.call("practice_coach_target", id) as Control if customize != null else null


func _section() -> StringName:
	var customize := _menu().call("practice_customize") as Control
	return StringName(customize.call("practice_section")) if customize != null else &""


func _lit(guide: PracticeCustomizeGuide) -> Array:
	return Array(guide.coach.targets())


func _hatena_screen(guide: PracticeCustomizeGuide) -> Vector2:
	var menu := _menu()
	if guide.hatena == null or not guide.hatena.visible:
		return Vector2.INF
	var head := guide.hatena.bubble_anchor(menu.call("practice_menu_camera") as Camera3D)
	return menu.call("practice_menu_to_screen", head) if head.is_finite() else head


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _wait_said(text_id: String, timeout_ms: int) -> bool:
	var ok := await _wait(func() -> bool: return said.has(text_id), timeout_ms)
	if not ok:
		notes.append("waiting %s: said %s" % [text_id, said])
	return ok


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node == null:
		return texts
	for label: Node in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _read_json(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed if parsed is Dictionary else {}


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(3)
	_key(keycode, false)
	await _frames(3)


func _key(keycode: Key, pressed: bool) -> void:
	_held[keycode] = pressed
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


## 部品の真ん中を、本物のマウスの動きと左クリックで押す。
func _click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		check(false, "click target exists")
		return
	var point := get_viewport().get_final_transform() * _center(control)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.position = point
		button.global_position = point
		Input.parse_input_event(button)
		await _frames(2)
	await _frames(2)


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	for keycode: Variant in _held.keys():
		if _held[keycode]:
			_key(keycode, false)
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	# スキンは保存先を戻して、ファイルの見た目を読み直す（テストで変えた帽子をメモリにも残さない）
	PlayerSkinStore.path = str(_saved.skin_path)
	PlayerSkinStore.load_into(gs)
	gs.subject = str(_saved.subject)
	gs.grade = int(_saved.grade)
	gs.difficulty = str(_saved.difficulty)
	gs.num_players = int(_saved.players)
	gs.mode = str(_saved.mode)
	gs.tuning.wall_speed_override = float(_saved.wall)
	gs.p1_emote_slots.assign(_saved.p1_emotes)
	gs.p2_emote_slots.assign(_saved.p2_emotes)
	QuizManager.provider.set_llm_mode(str(_saved.llm))
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said, "phases": phases}
	print("PRACTICE_COURSE5_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
