extends Node

## コース④（オンライン対戦）の実機の通しテスト（docs/new_tutorial/phase7_design.md 2章、course4_script.md v0.2）。
## メニューのコース選択から④を始め、キー入力とクリックで通す：
##   オンラインの画面（練習の形）：4-1 → 4-2 サイコロ → 4-3 → 4-4 ともだちのページ →『← もどる』→ 4-5 3D の看板 → 帽子を変える
##   →『✓ けってい』→ 4-6『ランダムマッチ』→ マッチングの演出 → 相手（CPU）→ VS カットイン
##   ゲーム画面の練習試合：エモート → カウントダウン → 壁1（矢印キーで動く）→ Esc の「たいせんを やめますか？」（ゲームは止まらない。
##   ［やめる］は押せない）→［つづける］→ 壁2（W A S D）→ オンラインの結果のカード →『オンラインメニューへ』
##   オンラインの画面に戻ってクリア：クリアカードとスタンプ →［あとで］
## 通信しないこと：テストの間、NetworkManager は OFFLINE のまま（つなぐ・待ち行列に入る状態にならない。WebSocket を作らない）。
## 最後に、もう一度クリアから［ランダムマッチで遊ぶ］を押し、ここで初めてつなぎに行くことも確かめる（つながらないリレーにする）。
## 設定（名前・スタンプ）とスキン（帽子・色）の保存先はテスト用に差し替え、テストの後で元に戻す。撮った画面は artifacts/practice_course4/。

const OUT := "res://artifacts/practice_course4/"
const SETTINGS := "user://practice_course4_smoke_settings.json"
const SKINS := "user://practice_course4_smoke_skins.json"
const DEAD_RELAY := "ws://127.0.0.1:9"
const MAIN_MENU := "res://ui/main_menu.tscn"
const ONLINE_MENU := "res://ui/online_menu.tscn"
const GAME_WORLD := "res://scenes/game_world.tscn"

var gs: QuizGameState
var failures: Array[String] = []
var notes: Array[String] = []
var checks := 0
var _saved := {}
## 案内（オンラインの画面）と監督（ゲーム画面）が言った言葉の ID（順に）
var said: Array[String] = []
## NetworkManager がなった状態（OFFLINE 以外になったら通信を始めたということ）
var net_states: Array[int] = []
## 通信してよい（最後の［ランダムマッチで遊ぶ］から）
var _net_allowed := false
var _held := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	gs = QuizManager.game_state
	_saved = {"path": GameManager.settings_path, "stamps": GameManager.practice_stamps.duplicate(true),
		"intro": GameManager.practice_intro_seen, "name": GameManager.online_name, "nick": GameManager.online_nickname,
		"skin_path": PlayerSkinStore.path, "relay": NetworkManager.relay_url, "subject": gs.subject, "grade": gs.grade,
		"difficulty": gs.difficulty, "players": gs.num_players, "mode": gs.mode, "short": GameManager.online_staging_short}
	GameManager.settings_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	# スキンの保存先も差し替える（いまの見た目のまま、書くのはテスト用のファイル）
	PlayerSkinStore.flush()
	PlayerSkinStore.path = SKINS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	GameManager.practice_stamps = {}
	GameManager.practice_intro_seen = true
	# 本物の流れ（メニューの最初の演出は見たことにする）
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	# 練習は通信しない。まちがえてつなぎに行っても外へ出ないよう、つながらないリレーにしておく
	NetworkManager.relay_url = DEAD_RELAY
	NetworkManager.state_changed.connect(func(state: int) -> void: net_states.append(state))
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""

	var menu := await _launch()
	if menu != null:
		var guide := await _guide_of(menu)
		if guide != null:
			await _arrive(menu, guide)
			await _home(menu, guide)
			await _name(menu, guide)
			await _quiz(menu, guide)
			await _find(menu, guide)
			await _skin(menu, guide)
			var director := await _matching(menu, guide)
			if director != null:
				await _match(director)
				var back := await _back_to_online()
				if back != null:
					await _clear_later(back)
	await _play_for_real()
	await _launch_next()
	_finish()


# ---------- メニューから④へ ----------

func _launch() -> OnlineMenu:
	get_tree().change_scene_to_file(MAIN_MENU)
	var ready := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == MAIN_MENU and scene.find_child("PracticeBtn", true, false) != null \
			and not SceneTransition.is_transitioning(), 25000)
	check(ready, "the main menu opens")
	if not ready:
		return null
	await _seconds(1.0)
	var button := get_tree().current_scene.find_child("PracticeBtn", true, false) as Button
	button.pressed.emit()
	var select := get_tree().current_scene.find_child("PracticeCourseSelect", true, false) as PracticeCourseSelect
	check(select != null and select.is_open(), "the tutorial button opens the course select")
	if select == null:
		return null
	await _seconds(0.4)
	var card := select.card("c4")
	check(card != null and not card.disabled, "the c4 card can be chosen")
	if card == null or card.disabled:
		return null
	card.grab_focus()
	await _frames(2)
	await _shot("00_course_select")
	await _tap(KEY_ENTER)
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == ONLINE_MENU, 20000)
	check(arrived, "choosing c4 opens the online menu (not the game world)")
	if not arrived:
		return null
	var menu := get_tree().current_scene as OnlineMenu
	check(menu.practice, "the online menu opens in the practice form")
	check(PracticeSession.resume_in_menu.is_empty(), "the online menu consumes resume_in_menu")
	check(gs.mode != Constants.MODE_PRACTICE, "the online menu part does not switch the game to the practice mode yet")
	return menu


func _guide_of(menu: OnlineMenu) -> PracticeOnlineGuide:
	var started := await _wait(func() -> bool: return menu.practice_guide() != null, 5000)
	check(started, "the online menu starts the practice guide")
	var guide := menu.practice_guide()
	if guide == null:
		return null
	said.clear()
	guide.coach.said.connect(func(text: String) -> void: said.append(text))
	return guide


func _arrive(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	var link := menu.practice_coach_target(&"status") as Label
	check(link != null and link.text == PracticeTexts.get_text("c4.status"), "the link label reads c4.status (%s)" % (link.text if link != null else "-"))
	check(guide.overlay.course_title() == "④ オンライン対戦" and guide.overlay.dot_count() == 6, "the header shows ④ with 6 dots")
	var pilot := menu.practice_pilot()
	check(pilot != null, "the helicopter has the pilot Hatena")
	var left := await _wait(func() -> bool: return guide.hatena != null and guide.hatena.visible and guide.is_pilot_hidden(), 10000)
	check(left, "the pilot Hatena takes the guide's place in the cockpit (seat hidden, guide shown)")
	# 立ち上がって、ドアを押し上げて降り、ドアを閉めて、雲に跳び乗る（PracticeSeatMoves.heli_leave。約 10 秒）
	var heli := menu.practice_stage().my_heli
	var opened := await _wait(func() -> bool: return heli.door_openness("L") > 0.9, 12000)
	check(opened, "the Hatena pushes the door open to get off")
	await _seconds(0.6)
	await _shot("01_leave_cockpit")
	check(await _wait(func() -> bool: return guide.phase == &"4-1", 25000), "after getting off and flying, 4-1 starts")
	check(heli.door_openness("L") < 0.05, "the door is closed again")
	if guide.hatena != null:
		check(guide.hatena.has_cloud(), "the Hatena rides a cloud")
	var head := _hatena_screen(menu, guide)
	check(head.x > 860.0 and head.x < 1280.0 and head.y > 0.0 and head.y < 720.0,
		"the Hatena floats on the right side, off the online UI (%s)" % head)
	_check_offline("4-1")


# ---------- 4-1〜4-5 ----------

func _home(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	check(await _wait_said("c4.home.1", 5000), "4-1 ここがオンラインの画面")
	await _seconds(0.4)
	await _shot("02_home_hello")
	# 何も光っていない間は押せない
	await _click(menu.practice_coach_target(&"random_match"))
	await _frames(5)
	check(menu.director == null or menu.director.state == OnlineStagingDirector.State.IDLE, "the random match is blocked while Hatena talks")
	check(await _wait_said("c4.home.2", 6000), "4-1 離れた相手と対戦できる")
	check(await _wait_said("c4.home.3", 6000), "4-1 練習ではつながないよ")
	check(_lit(guide) == [menu.practice_coach_target(&"status")], "the link label is lit")
	await _seconds(0.4)
	await _shot("03_home_status")


func _name(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	check(await _wait_said("c4.name.1", 6000), "4-2 相手に見える名前")
	check(_lit(guide) == [menu.practice_coach_target(&"name_field")] and guide.coach.is_clickable(), "the name field is lit (typing allowed)")
	await _seconds(0.3)
	await _shot("04_name_field")
	check(await _wait_said("c4.name.2", 6000), "4-2 本名は入れないで")
	check(await _wait_said("c4.name.3", 6000), "4-2 サイコロでも決められる")
	var dice := menu.practice_coach_target(&"name_dice")
	check(_lit(guide) == [dice] and guide.coach.is_clickable(), "the dice is lit and pressable")
	await _seconds(0.6)
	check(guide.coach.bubble_text() == PracticeTexts.get_text("c4.name.3"), "the ask stays until the dice is pressed")
	await _shot("05_name_dice")
	var before := GameManager.online_name
	await _click(dice)
	check(await _wait_said("c4.name.4", 3000), "pressing the dice brings OK")
	check(GameManager.online_name != before and NetNameFilter.is_ok(GameManager.online_name),
		"the dice gives a new valid epithet (%s → %s)" % [before, GameManager.online_name])
	await _seconds(0.5)
	var stored: Variant = _read_json(SETTINGS).get("online_name", "")
	check(str(stored) == GameManager.online_name, "the name is saved as a real setting (%s)" % stored)
	check(await _wait_said("c4.name.5", 6000), "4-2 不適切な言葉は使えない")


func _quiz(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	check(await _wait_said("c4.quiz.1", 6000), "4-3 ここで問題を選ぶ")
	check(_lit(guide) == [menu.practice_coach_target(&"quiz_box")], "あそぶ もんだい is lit")
	await _seconds(0.4)
	await _shot("06_quiz_box")
	check(await _wait_said("c4.quiz.2", 6000), "4-3 近い学年の相手と組まれる")
	check(_lit(guide) == [menu.practice_coach_target(&"grade")], "がくねん is lit")


func _find(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	check(await _wait_said("c4.find.1", 6000), "4-4 知らない相手と対戦するならここ")
	var random := menu.practice_coach_target(&"random_match")
	check(_lit(guide) == [random] and not guide.coach.is_clickable(), "ランダムマッチ is lit (show only)")
	await _seconds(0.4)
	await _shot("07_find_random")
	await _click(random)
	await _frames(5)
	check(menu.director == null or menu.director.state == OnlineStagingDirector.State.IDLE, "the show-only ランダムマッチ cannot be pressed")
	check(await _wait_said("c4.find.2", 6000), "4-4 友だちと遊ぶときは")
	var friends := menu.practice_coach_target(&"friends")
	check(_lit(guide) == [friends] and guide.coach.is_clickable(), "ともだちと あそぶ is lit and pressable")
	await _seconds(0.4)
	await _shot("08_find_friends")
	await _click(friends)
	check(await _wait(func() -> bool: return menu.current_id() == OnlineMenu.FRIEND, 2000), "ともだちと あそぶ opens the friend page")
	check(await _wait_said("c4.find.3", 4000), "4-4 コードを作って相手に伝える")
	var make := menu.practice_coach_target(&"code_make")
	check(_lit(guide) == [make] and not guide.coach.is_clickable(), "コードを つくる is lit (show only)")
	await _seconds(0.4)
	await _shot("09_friend_make")
	await _click(make)
	await _frames(5)
	check(menu.director == null or menu.director.state == OnlineStagingDirector.State.IDLE, "コードを つくる cannot be pressed")
	check(await _wait_said("c4.find.4", 6000), "4-4 相手のコードを入れて参加")
	check(_lit(guide) == [menu.practice_coach_target(&"code_enter")], "コードを いれる is lit")
	check(await _wait_said("c4.find.5", 6000), "4-4 コードは5文字")
	check(_lit(guide).size() == 1 and _lit(guide)[0] is LineEdit, "the code field is lit")
	await _seconds(0.4)
	await _shot("10_friend_code")
	check(await _wait_said("c4.find.6", 6000), "4-4 『← もどる』でトップへ")
	var back := menu.practice_coach_target(&"back")
	check(_lit(guide) == [back] and guide.coach.is_clickable(), "← もどる is lit and pressable")
	await _seconds(0.3)
	await _shot("11_friend_back")
	await _click(back)
	check(await _wait(func() -> bool: return menu.current_id() == OnlineMenu.HOME, 2000), "← もどる goes back to the top")
	_check_offline("4-4")


func _skin(menu: OnlineMenu, guide: PracticeOnlineGuide) -> void:
	check(await _wait_said("c4.skin.1", 6000), "4-5 看板からスキンを変えられる")
	var sign := menu.practice_coach_target(&"skin_sign")
	check(sign != null and _lit(guide) == [sign] and guide.coach.is_clickable(), "the 3D sign is lit (%s)" % [sign.get_global_rect() if sign != null else "-"])
	await _seconds(0.5)
	await _shot("12_skin_sign")
	if sign == null:
		return
	await _click(sign)
	check(await _wait(func() -> bool: return menu.current_id() == OnlineMenu.SKIN, 2000), "clicking the 3D sign opens スキン設定")
	check(await _wait_said("c4.skin.2", 4000), "4-5 帽子と体の色を選べる")
	var hat_row := menu.practice_coach_target(&"skin_hat")
	check(_lit(guide) == [hat_row], "the hat ◀ ▶ row is lit")
	await _seconds(0.5)
	await _shot("13_skin_hat")
	check(await _wait_said("c4.skin.3", 6000), "4-5 キャラをクリックしてもいい")
	var character := menu.practice_coach_target(&"skin_character")
	check(character != null and _lit(guide) == [character], "the standing character is lit (%s)" % [character.get_global_rect() if character != null else "-"])
	await _seconds(0.5)
	await _shot("14_skin_character")
	# 帽子を ▶ で1つ変える（光っていないが押せる）
	var hat_before := gs.p1_hat
	var next := hat_row.get_child(hat_row.get_child_count() - 1) as Button if hat_row != null else null
	await _click(next)
	check(await _wait(func() -> bool: return gs.p1_hat != hat_before, 1500), "the hat ▶ changes the hat (%d → %d)" % [hat_before, gs.p1_hat])
	check(await _wait_said("c4.skin.4", 3000), "a change brings いいね")
	check(await _wait_said("c4.skin.5", 6000), "4-5 『✓ けってい』で戻る")
	var done := menu.practice_coach_target(&"skin_done")
	check(_lit(guide) == [done] and guide.coach.is_clickable(), "✓ けってい is lit and pressable")
	await _seconds(0.4)
	await _shot("15_skin_done")
	await _click(done)
	check(await _wait(func() -> bool: return menu.current_id() == OnlineMenu.HOME, 2000), "✓ けってい goes back to the top")
	await _seconds(0.6)
	var stored: Dictionary = _read_json(SKINS)
	var players: Variant = stored.get("players", {})
	var hat_saved := int((players as Dictionary).get("1", {}).get("hat", -1)) if players is Dictionary else -1
	check(hat_saved == gs.p1_hat, "the hat is saved as a real setting (%d)" % hat_saved)


# ---------- 4-6：マッチングの演出 ----------

func _matching(menu: OnlineMenu, guide: PracticeOnlineGuide) -> PracticeDirector:
	# 先にハテナがヘリへ乗りこんで座ってから（PracticeSeatMoves.heli_board。約 10 秒）、操縦席から「押して」
	check(await _wait_said("c4.match.1", 30000), "4-6 『ランダムマッチ』を押して")
	check(menu.practice_pilot() != null and menu.practice_pilot().visible and not guide.hatena.visible,
		"the Hatena has boarded the helicopter before the press")
	var random := menu.practice_coach_target(&"random_match")
	check(_lit(guide) == [random] and guide.coach.is_clickable(), "ランダムマッチ is lit and pressable")
	await _seconds(0.4)
	await _shot("16_match_press")
	await _click(random)
	check(await _wait(func() -> bool: return menu.director != null and menu.director.state != OnlineStagingDirector.State.IDLE, 2000),
		"ランダムマッチ starts the real matching staging")
	check(menu.director != null and menu.director.short_mode, "the staging is the short form")
	await _seconds(0.8)
	await _shot("17_match_boarding")
	var searching := await _wait(func() -> bool: return menu.current_id() == OnlineMenu.SEARCH, 15000)
	check(searching, "the search band appears")
	var search_start := Time.get_ticks_msec()
	if searching:
		var texts := _label_texts(menu.page(OnlineMenu.SEARCH))
		var found := false
		for text: String in texts:
			if text.begins_with("あいてを さがしています…"):
				found = true
		check(found, "the band reads あいてを さがしています… (%s)" % [texts])
	check(await _wait_said("c4.match.2", 3000), "4-6 相手を探しているところ")
	await _seconds(0.8)
	await _shot("18_match_search")
	_check_offline("search")
	var joined := await _wait(func() -> bool: return menu.director != null and menu.director.state >= OnlineStagingDirector.State.JOIN, 8000)
	var waited := (Time.get_ticks_msec() - search_start) / 1000.0
	check(joined and waited > 2.4 and waited < 4.5, "the CPU is found about 3 s after the search starts (%.1f s)" % waited)
	await _seconds(0.5)
	await _shot("19_match_found")
	check(await _wait(func() -> bool: return menu.director != null and menu.director.state >= OnlineStagingDirector.State.CUTIN_IN, 8000), "the VS cut-in plays")
	check(await _wait_said("c4.match.3", 3000), "4-6 今回の相手はCPU")
	await _seconds(0.6)
	var cut_texts := _label_texts(menu.cutin) if menu.cutin != null else []
	check(cut_texts.has("CPU") and cut_texts.has(GameManager.online_name), "the cut-in shows the name and CPU (%s)" % [cut_texts])
	await _shot("20_match_cutin")
	_check_offline("cutin")
	var arrived := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == GAME_WORLD, 15000)
	check(arrived, "the cut-in opens the game world")
	if not arrived:
		return null
	var world := get_tree().current_scene
	var ready := await _wait(func() -> bool:
		var d := world.get("practice_director") as PracticeDirector
		return d != null and d.step != null, 15000)
	check(ready, "the practice director starts in the game world")
	if not ready:
		return null
	var director := world.get("practice_director") as PracticeDirector
	director.said.connect(func(text_id: String) -> void: said.append(text_id))
	check(director.course.id == "c4" and director.step.id == "4-6", "the director plays c4 at 4-6")
	check(director.overlay.dot_count() == 6 and director.overlay.progress_index() == 5, "the header shows 4-6 as the current dot")
	check(gs.mode == Constants.MODE_PRACTICE and gs.num_players == 2 and gs.is_practice_online_look(), "the match is a 2-player practice round with the online look")
	check(bool(gs.get(&"practice_p2_cpu")) and director.has_cpu(), "P2 is the CPU")
	check(not gs.net_online, "the practice match is not a networked match")
	return director


# ---------- 4-6：ゲーム画面の練習試合 ----------

func _match(d: PracticeDirector) -> void:
	var world := get_tree().current_scene
	check(await _wait_said("c4.match.4", 8000), "4-6 試合前はエモートであいさつできる")
	check(gs.game_state == Constants.STATE_WAITING_START, "the round waits at the start (%s)" % gs.game_state)
	await _tap(KEY_1)
	check(await _wait(func() -> bool: return gs.p1_emote > 0, 1500), "the emote key 1 greets before the start")
	await _seconds(0.5)
	var saw := world.get_node_or_null(^"SawChaseController")
	if saw == null:
		saw = world.find_child("SawChase*", true, false)
	if saw != null and saw.has_method(&"is_operator_hidden"):
		check(bool(saw.call(&"is_operator_hidden")), "the saw's seat Hatena hides while the guide Hatena is on the stage")
	await _shot("21_game_greet")
	# Enter では始めない（オンラインと同じ）
	await _tap(KEY_ENTER)
	await _frames(5)
	check(gs.game_state == Constants.STATE_WAITING_START, "Enter does not start the online-look round")
	check(await _wait_said("c4.match.5", 8000), "4-6 ルールは2人対戦と同じ")
	check(await _wait(func() -> bool: return gs.game_state == Constants.STATE_FLYOVER, 3000), "the real start flow (flyover) begins")
	check(await _wait(func() -> bool: return gs.game_state == Constants.STATE_COUNTDOWN, 6000), "the real countdown follows")
	await _seconds(1.5)
	await _shot("22_game_countdown")
	var cards := _duo_badges(world)
	check(cards.has("じぶん") and cards.has("あいて"), "the 2-player cards read じぶん / あいて (%s)" % [cards])
	check(await _wait(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 8000), "the round starts")
	await _seconds(0.3)
	var tags := _name_tags(world)
	check(tags.has(GameManager.online_name) and tags.has("CPU"), "the name tags show my name and CPU (%s)" % [tags])
	# 壁1：矢印キーで青「42」のドアへ（オンラインと同じく矢印でも動く）
	var x0 := gs.player_x
	await _hold_until(KEY_LEFT, func() -> bool: return gs.player_x >= 3.3, 2500)
	check(gs.player_x > x0 + 1.0, "the arrow keys move P1 (%.2f → %.2f)" % [x0, gs.player_x])
	await _shot("23_game_wall1")
	_press(KEY_UP)
	var passed := await _wait(func() -> bool: return gs.current_wall_index >= 1, 15000)
	_release(KEY_UP)
	check(passed, "wall 1 is done")
	check(await _wait_said("c4.match.6", 4000), "4-6 オンラインでは一時停止できない")
	check(await _wait_said("c4.match.7", 5000), "4-6 Escを押してみて")
	# 吹き出しが出きってから撮る
	await _seconds(0.3)
	await _shot("24_game_esc_ask")
	await _tap(KEY_ESCAPE)
	var opened := await _wait(func() -> bool: return bool(world.call("practice_quit_confirm_open")), 1500)
	check(opened, "Esc opens the real たいせんを やめますか？")
	check(not get_tree().paused and gs.game_state == Constants.STATE_PLAYING, "Esc does not pause the game")
	var scroll := gs.world_scroll_z
	await _seconds(0.5)
	check(gs.world_scroll_z > scroll + 0.3, "the belt keeps moving under the dialog (%.2f → %.2f)" % [scroll, gs.world_scroll_z])
	var leave := world.call("practice_coach_target", &"quit_leave") as Button
	var keep := world.call("practice_coach_target", &"quit_continue") as Button
	check(leave != null and leave.disabled and leave.text == "やめる", "やめる is shown but cannot be pressed")
	check(keep != null and keep.text == "つづける", "つづける is shown")
	check(await _wait_said("c4.match.8", 3000), "4-6 やめると相手の勝ちになる")
	# 壁2の正解（赤「東」）の前へ、W A S D で寄っておく（ダイアログの間も動ける）。押しっぱなしにすると床の外（海）まで行く
	var x_before := gs.player_x
	var at_door := await _hold_until(KEY_D, func() -> bool: return gs.player_x <= -3.3, 2500)
	check(at_door and gs.player_x > -6.0, "W A S D move P1 under the dialog (%.2f → %.2f)" % [x_before, gs.player_x])
	await _shot("25_game_quit_confirm")
	check(await _wait_said("c4.match.9", 4000), "4-6 『つづける』を押して")
	await _frames(3)
	check(_coach_lit(d) == [keep] and bool(d.coach.call(&"is_clickable")), "つづける is lit and pressable (やめる is not lit)")
	await _shot("26_game_continue")
	await _click(leave)
	await _frames(4)
	check(get_tree().current_scene == world and bool(world.call("practice_quit_confirm_open")), "やめる does nothing in practice")
	await _click(keep)
	check(await _wait(func() -> bool: return not bool(world.call("practice_quit_confirm_open")), 1500), "つづける closes the dialog")
	check(await _wait_said("c4.match.10", 3000), "4-6 最後まで続けよう")
	_press(KEY_W)
	var finished := await _wait(func() -> bool: return gs.game_state in [Constants.STATE_CLEAR, Constants.STATE_GAME_OVER], 20000)
	_release(KEY_W)
	check(finished, "wall 2 ends the match (%s)" % gs.game_state)
	check(gs.p1_alive, "P1 gets through wall 2 without going out")
	var card := await _wait(func() -> bool: return d.result_card_visible(), 15000)
	check(card, "the real online result card is shown")
	if not card:
		return
	var hud := world.get_node_or_null("GameplayHUD")
	var texts := _label_texts(hud)
	var verdict := ""
	for text: String in texts:
		if text.begins_with("🏆") or text.begins_with("🤝"):
			verdict = text
	check(verdict in ["🏆 あなたの かち！", "🏆 CPU の かち", "🤝 DRAW!"], "the card has the online verdict (%s)" % verdict)
	notes.append("match result: %s (P1 %d / CPU %d)" % [verdict, gs.score, gs.player2_score])
	var menu_button := world.call("practice_coach_target", &"result_menu") as Button
	var retry := world.call("practice_coach_target", &"result_retry") as Button
	check(menu_button != null and menu_button.text == "オンラインメニューへ", "the card button reads オンラインメニューへ")
	check(retry == null or not retry.visible, "リトライ is hidden like online")
	check(await _wait_said("c4.match.11", 4000), "4-6 終わるとこの画面に戻る")
	await _frames(3)
	check(_coach_lit(d) == [menu_button], "オンラインメニューへ is lit")
	# 得点の数え上げ（約1.5秒）が終わってから撮る
	await _seconds(1.8)
	await _shot("27_game_result")
	_check_offline("result")
	await _click(menu_button)


func _back_to_online() -> OnlineMenu:
	var back := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == ONLINE_MENU, 15000)
	check(back, "オンラインメニューへ returns to the online menu")
	if not back:
		return null
	var menu := get_tree().current_scene as OnlineMenu
	check(menu.practice, "the online menu opens in the practice form again")
	check(gs.mode != Constants.MODE_PRACTICE and not gs.practice_online_look, "the practice match state is cleared")
	return menu


# ---------- クリア ----------

func _clear_later(menu: OnlineMenu) -> void:
	var guide := await _guide_of(menu)
	if guide == null:
		return
	# ヘリから降りて（約 10 秒）飛んできてから「完了」
	check(await _wait_said("c4.clear.1", 30000), "クリア オンラインの準備はこれで完了")
	await _seconds(0.5)
	await _shot("28_clear_hatena")
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 5000)
	check(shown, "the clear card is shown")
	if not shown:
		return
	check(GameManager.has_practice_stamp("c4") and not GameManager.practice_stamp_star("c4"), "c4 gets a stamp (no star)")
	var stamps: Variant = _read_json(SETTINGS).get("practice_stamps", {})
	check(stamps is Dictionary and (stamps as Dictionary).has("c4"), "the c4 stamp is saved (%s)" % [stamps])
	var buttons := guide.overlay.clear_buttons()
	check(buttons.size() == 2 and buttons[0].text == "ランダムマッチで遊ぶ" and buttons[1].text == "あとで",
		"the card has ランダムマッチで遊ぶ / あとで")
	var labels := _label_texts(guide.overlay)
	check(labels.has("④ オンライン対戦") and labels.has("クリア"), "the card reads ④ オンライン対戦 / クリア")
	check(await _wait_said("c4.clear.2", 5000), "クリア マナーを守って楽しんで")
	await _seconds(0.5)
	await _shot("29_clear_card")
	if buttons.size() == 2:
		await _click(buttons[1])
	# ハテナがヘリへ乗りこんで座ってから（約 10 秒）、練習の形を終える
	var done := await _wait(func() -> bool: return menu.practice_guide() == null and not menu.practice, 25000)
	check(done, "あとで ends the practice form")
	check(get_tree().current_scene == menu and menu.current_id() == OnlineMenu.HOME, "あとで stays on the online menu")
	var pilot := menu.practice_pilot()
	check(pilot != null and pilot.visible, "the Hatena is back in the cockpit")
	var link := menu.practice_coach_target(&"status") as Label
	check(link != null and link.text == "● オフライン", "the link label is back to the real one (%s)" % (link.text if link != null else "-"))
	await _seconds(0.5)
	await _shot("30_after_later")
	_check_offline("after later")


## もう一度クリアから［ランダムマッチで遊ぶ］：練習の形を終えて本物の『ランダムマッチ』（ここで初めてつなぎに行く）
func _play_for_real() -> void:
	PracticeSession.resume_in_menu = {"course": "c4", "step": "clear", "first_run": true}
	get_tree().change_scene_to_file(ONLINE_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).practice_guide() != null, 15000)
	check(opened, "resume clear opens the practice form again")
	if not opened:
		return
	var menu := get_tree().current_scene as OnlineMenu
	var guide := menu.practice_guide()
	var shown := await _wait(func() -> bool: return guide.overlay.clear_card_visible(), 30000)
	check(shown, "the clear card is shown again")
	if not shown:
		return
	var buttons := guide.overlay.clear_buttons()
	await _seconds(0.8)
	if buttons.size() == 2:
		check(get_viewport().gui_get_focus_owner() == buttons[0], "ランダムマッチで遊ぶ is selected after the first-run start")
	_check_offline("before the real match")
	_net_allowed = true
	await _tap(KEY_ENTER)
	# ハテナがヘリへ乗りこんで座ってから（約 10 秒）、本物のマッチングへ
	var connecting := await _wait(func() -> bool: return net_states.has(NetworkManager.State.CONNECTING), 25000)
	check(connecting, "ランダムマッチで遊ぶ starts the real matching (connects to the relay)")
	check(not menu.practice, "the practice form ended")
	await _seconds(0.5)
	await _shot("31_real_match")
	# つながらないリレーなので、待機へ戻るまで待つ
	await _wait(func() -> bool: return menu.director == null or menu.director.state == OnlineStagingDirector.State.IDLE, 12000)


## ③のクリアカードの［次のコースへ］と同じ（PracticeSession.launch_next = "c4"）：メニューからすぐ④（オンラインの画面の練習の形）
func _launch_next() -> void:
	NetworkManager.disconnect_from_relay()
	await _frames(2)
	var mark := net_states.size()
	PracticeSession.launch_next = "c4"
	PracticeSession.from_first_run = false
	get_tree().change_scene_to_file(MAIN_MENU)
	var opened := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).practice_guide() != null, 30000)
	check(opened, "launch_next c4 opens the online menu in the practice form")
	check(PracticeSession.launch_next.is_empty(), "the menu consumes launch_next")
	if not opened:
		return
	var menu := get_tree().current_scene as OnlineMenu
	var guide := menu.practice_guide()
	check(await _wait(func() -> bool: return guide.phase == &"4-1", 30000), "the course starts at 4-1 again")
	await _seconds(0.3)
	await _shot("32_launch_next")
	var states := net_states.slice(mark)
	check(not states.has(NetworkManager.State.CONNECTING), "no network after launch_next (%s)" % [states])


# ---------- 道具 ----------

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


## ここまで通信していない（NetworkManager は OFFLINE のまま。WebSocket も作っていない）
func _check_offline(where: String) -> void:
	if _net_allowed:
		return
	var started := false
	for state: int in net_states:
		if state != NetworkManager.State.OFFLINE:
			started = true
	check(not started and NetworkManager.state == NetworkManager.State.OFFLINE and NetworkManager.get("_ws") == null,
		"no network at %s (states %s)" % [where, net_states])


func _lit(guide: PracticeOnlineGuide) -> Array:
	return Array(guide.coach.targets())


func _coach_lit(d: PracticeDirector) -> Array:
	return Array(d.coach.call(&"targets")) if d.coach != null else []


func _hatena_screen(menu: OnlineMenu, guide: PracticeOnlineGuide) -> Vector2:
	var head := guide.hatena.bubble_anchor(menu.practice_camera()) if guide.hatena != null else Vector2.INF
	return menu.practice_to_screen(head) if head.is_finite() else head


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


## 2人のカードのバッジの文字（「じぶん」「あいて」）
func _duo_badges(world: Node) -> Array[String]:
	var texts: Array[String] = []
	for index: int in [1, 2]:
		var card := world.find_child("P%dStatusCard" % index, true, false)
		if card == null:
			continue
		var label := card.find_child("Player", true, false) as Label
		if label != null:
			texts.append(label.text)
	return texts


## 頭の上の名札の文字（見えているもの）
func _name_tags(world: Node) -> Array[String]:
	var texts: Array[String] = []
	for index: int in [1, 2]:
		var tag := world.find_child("P%dNameTag" % index, true, false) as Control
		if tag == null or not tag.visible:
			continue
		for label: Node in tag.find_children("*", "Label", true, false):
			if (label as Label).visible:
				texts.append((label as Label).text)
		if tag.has_method("tag_text"):
			texts.append(str(tag.call("tag_text")))
		var text: Variant = tag.get("text")
		if text is String:
			texts.append(text)
		var shown: Variant = tag.get("_text")
		if shown is String:
			texts.append(shown)
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


func _hold_until(keycode: Key, condition: Callable, timeout_ms: int) -> bool:
	_press(keycode)
	var ok := await _wait(condition, timeout_ms)
	_release(keycode)
	await _frames(3)
	return ok


func _press(keycode: Key) -> void:
	if not _held.get(keycode, false):
		_key(keycode, true)


func _release(keycode: Key) -> void:
	if _held.get(keycode, false):
		_key(keycode, false)


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
	var center := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point := get_viewport().get_final_transform() * center
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
	NetworkManager.disconnect_from_relay()
	NetworkManager.relay_url = str(_saved.relay)
	GameManager.settings_path = str(_saved.path)
	GameManager.practice_stamps = _saved.stamps
	GameManager.practice_intro_seen = bool(_saved.intro)
	GameManager.online_name = str(_saved.name)
	GameManager.online_nickname = int(_saved.nick)
	GameManager.online_staging_short = bool(_saved.short)
	# スキンは保存先を戻して、ファイルの見た目を読み直す（テストで変えた帽子をメモリにも残さない）
	PlayerSkinStore.path = str(_saved.skin_path)
	PlayerSkinStore.load_into(gs)
	gs.subject = str(_saved.subject)
	gs.grade = int(_saved.grade)
	gs.difficulty = str(_saved.difficulty)
	gs.num_players = int(_saved.players)
	gs.mode = str(_saved.mode)
	gs.practice_online_look = false
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	PracticeSession.launch_next = ""
	PracticeSession.with_cpu = false
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKINS))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "notes": notes, "said": said, "net": net_states}
	print("PRACTICE_COURSE4_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
