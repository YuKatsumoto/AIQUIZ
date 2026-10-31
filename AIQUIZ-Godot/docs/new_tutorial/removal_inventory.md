# 旧チュートリアル撤去の一覧（下調べ v1）

2026-10-24 23:05〜23:40 に、4人のサブエージェントが読むだけで調べた結果をまとめたもの。ファイルは変えていない。
旧版の中身（レッスンの内容・文言・教え方）は書かず、「どこを、どう消すか」だけを書く。

**行番号は調べた時点のもの。** 調べている間も、ほかのセッションが `game_state.gd`・`game_world.gd`・`gameplay_hud.gd`・`audio_manager.gd` を書き換えていた。撤去のときは関数名で場所を探し、直前に rg で行番号を取り直す。

## 0. 要点

- **規模**：`game_state.gd` だけで約1,350行（ファイルの約23%）、丸ごと消す関数が70個。そのほか、共有スクリプト12本の組み込み、専用スクリプト約15本、専用テスト9本、素材・ツール・資料
- **今の作業ツリーは読み込める状態**：23:17 の Godot のログにスクリプトエラーがなく、削除済みファイルへの参照切れもない
- **ステージ済みと未ステージの変更は一体**：ステージ済みだけをコミットすると、HEAD に残る `game_state.gd`・`customize_settings.gd`・`main_menu.gd` などが、作業ツリーで削除済みのファイル（`TutorialFlowBase`・`TutorialUiStyle`・`TutorialKeyChip` など）を参照したままになり、読み込めなくなる。コミットするときは両方まとめて行う
- **型付きの参照が多い**：`game_state: QuizGameState` のような型付きの変数で呼んでいるので、`game_state.gd` の旧チュートリアルの関数を消すと、呼んでいる側がすべて読み込みエラーになり、全モードが起動しなくなる。手順は「呼ぶ側 → game_state → 定数」の順にし、どの段階でも読み込める状態を保つ
- **`tests/hp_unit.gd` の81行目が `MODE_TUTORIAL` を使っている**：35本のテストがこのファイルを読み込んでいるので、`MODE_TUTORIAL` を消す前に直す
- **撤去は、同じフォルダで動いているセッションが止まってから行う**。23:40 時点で動いていたのは「ゲームオーバー時のハテナ救出アニメーション」（`game_state`・`game_world`・`gameplay_hud`・`audio_manager` を編集中）と「HUD デザイン改善」（`gameplay_hud` を触る可能性が高い）

### 名前に tutorial があっても消してはいけないもの

| もの | 理由 | 撤去での扱い |
|---|---|---|
| `scripts/world/tutorial_key_guides_3d.gd`・`tutorial_keycap_3d.gd`（と .uid） | 本編のカウントダウン中のキー表示（`countdown_key_hints.gd`。「ゲーム開始時のキー表示」のセッションが 23:05 ごろ作った）が使っている | 残し、撤去のときに名前から tutorial を外す（3-5） |
| `game_state.allows_tutorial_ghost_ride()` | 本編では常に true。2P のゴースト搭乗の条件（`ghost_shark_ride_controller.gd` の `_base_mode_is_eligible`）が頼っている | 呼ぶ側の `and …` を消す（true 扱い）。false に置き換えると搭乗が壊れる |
| `game_world._update_walls` の壁を隠す分岐 | 両者脱落の投げ縄演出（`_elimination_course_hidden`）が同じ分岐を使っている | ブロックは残し、条件を `if _elimination_course_hidden:` にする |
| `_start_goal_race`・`_update_goal_race`（見出しは「2P tutorial legacy」） | 本編の2P 10問のゴールレースの本線 | チュートリアルの行だけ消す |
| `countdown_timer` の初期値 3.0（`TUTORIAL_COUNTDOWN_SECONDS` から来ている） | カスタマイズのプレビューや多くのテストが、タイマーを設定せずに COUNTDOWN にしている | 定数は消し、`= 3.0` の値で残す |
| `is_scroll_out_death_enabled()`・`uses_saw_chase()`・`uses_hp()`・`uses_local_result_ceremony()` | 本編の判定。HUD の危険表示なども読む | 関数は残し、チュートリアルの分岐だけ消す |
| ゴーストの `charge_resolved` シグナル、`_charge_bar_home`、`_start_hud_intro`、`_refresh_hud_controls` | MatchReel・メニューのゴースト演出・通常の HUD が使う | 残す |
| `camera_controller.get_gameplay_pose()`、`_third_person_camera_height`・`_target` | 通常の1Pカメラ・フライオーバー・ゴーストが使う | 残し、中のチュートリアル分岐だけ消す |
| `gameplay_hud._fire_confetti()`・`_apply_preload_stage_preview_layout()`・`_refresh_start_prompt` | 通常の CLEAR・サドンデスの準備・Enter の案内 | 残す |
| `get_result_formula_text()`・`result_half_points()`・`format_result_points()` | 通常の結果表示と勝敗メッセージ | 残す |
| `saw_chase_controller.preload_model()` | 設定ホールの練習場（`practice_yard.gd`）も呼ぶ | 残し、`game_world` の呼び出しだけ消す |
| `game_world` のエモートキーのビット | サドンデスにも渡している | 残し、コメントだけ直す |

## 1. 撤去の手順

0. **前提**：同じフォルダで動いているセッションが止まっている。バックアップはしない（決定済み）。行番号を rg で取り直す
1. **呼ぶ側から外す**（この段階では game_state の関数が残っているので、どこで止めても読み込める）
   - `game_world.gd`（2-2）
   - `gameplay_hud.gd`（2-3）、`result_finale_hud.gd`（2-4）
   - `main_menu.gd`（2-7。ボタンは空き枠に置き換える）、`customize_settings.gd`（2-8）
   - `camera_controller.gd`（2-5）、`ghost_shark_ride_controller.gd`（2-6）
   - `audio_manager.gd`・`net_predictor.gd`・`replay_hud.gd`（2-10）、コメントだけのファイル（2-11）
2. **`game_state.gd`**（2-1）：D（条件の単純化）→ C（ブロックの削除）→ B（関数70個の削除）→ A（宣言の削除）→ E（コメント）
3. **`game_manager.gd`**（2-9）：宣言と関数を消し、古い設定キーを読み込み時に消す処理を足す
4. **テスト**（4章）：専用テストを消し、混在しているテストを直す。`hp_unit.gd` を最初に
5. **専用ファイル・素材・ツールを削除**（3章）。3Dキーの2本は改名して残す（3-5）
6. **`Constants.MODE_TUTORIAL` を削除**（参照がすべて消えてから）
7. **資料**（5章）：旧版の資料を消し、README とほかの資料の記述を直す
8. **確かめる**（6章）：全スクリプトの読み込み、rg での残りの点検、既存テスト、実機での通常モード

## 2. ファイルごとの一覧

### 2-1 `scripts/core/game_state.gd`

"tutorial" を含む522行（ほかに「チュートリアル」だけを含む26行）を、すべて下の A〜E のどれかに入れてある。撤去後、`game_state.gd` は `GameManager` を参照しなくなる。

**A. 宣言を削除**

| 場所 | 何をするか |
|---|---|
| 4-5 | preload `DuoTutorialFlowScript`・`SoloTutorialFlowScript` を削除 |
| 108-111 | signal `tutorial_presentation_requested`・`tutorial_presentation_finished`・`tutorial_task_completed`・`tutorial_customize_handoff_requested` を削除 |
| 125-134 | enum `TutorialCeremonyStage` を削除 |
| 150-157 | `pre_tutorial_*`（6個）と `_tutorial_backup_valid` を削除 |
| 159-180 | `# --- Tutorial ---` の節を削除（`TUTORIAL_OCEAN_RECOVERY_DURATION`・`TUTORIAL_SAW_RECOVERY_DURATION`・`tutorial_ui_revision`・`tutorial_flow`・`_tutorial_safe_z`・`_tutorial_eval_wall`・`_tutorial_eval_mask`・`_tutorial_correct_mask`・`_tutorial_lesson_hint_mask`・`_pending_solo_customize_tour`・`_pending_customize_tour_course`） |
| 235、237-238 | コメントと `TUTORIAL_COUNTDOWN_SECONDS` を削除。`var countdown_timer := TUTORIAL_COUNTDOWN_SECONDS` は `= 3.0` に書き換える |
| 342-349 | `TUTORIAL_SCORE_PAUSE_MIN_SECONDS`・`tutorial_ceremony_stage`・`_tutorial_score_pause_elapsed`・`tutorial_emote_keys_p1/p2` を削除 |

**B. 関数を丸ごと削除（70個）**

これらが呼んでいる共通の部品（`_apply_hp_wall_damage`・`_hp_answerable`・`_check_player_door`・`_reset_ocean_shark_state`・`_reset_external_impulses`・`_process_dead_player_physics`・`_sink_ocean_players`・`_start_goal_race`・`_goal_wait_message`・`clear_game`・`reset_to_menu`）は残す。

| 範囲 | 関数 |
|---|---|
| 541-558 | `_install_tutorial_flow` |
| 781-852 | `_is_tutorial_mode`・`is_solo_tutorial`・`is_duo_tutorial`・`allows_tutorial_ghost_ride`・`tutorial_splits_camera`・`get_tutorial_course`・`get_tutorial_step_id`・`has_pending_solo_customize_tour`・`get_pending_customize_tour_course`・`complete_solo_customize_tour`・`abort_solo_customize_tour` |
| 952-1058 | `_on_tutorial_saw_catch`・`get_tutorial_overlay_model`・`is_tutorial_presentation_locked`・`is_tutorial_ghost_practice`・`get_tutorial_ghost_player`・`get_tutorial_wall_count`・`are_tutorial_walls_hidden`・`complete_tutorial_presentation`・`register_tutorial_ghost_aim`・`register_tutorial_ghost_charge`・`finish_tutorial_ghost_step`・`_on_tutorial_presentation_requested`・`_on_tutorial_presentation_finished`・`_on_tutorial_task_completed` |
| 1490-1767 | `start_tutorial`・`restart_tutorial`・`_advance_tutorial_step`・`_tutorial_fallen_players`・`_set_tutorial_revival_hearts`・`_reset_tutorial_wall_judgement`・`_begin_solo_customize_handoff`・`_reset_tutorial_stage`・`_tutorial_reset_z`・`_reset_tutorial_players_at`・`_reset_tutorial_players_for_step`・`_prepare_tutorial_quiz_step`・`_complete_tutorial_quiz_step` |
| 2162-2169 | `_begin_tutorial_gameplay_after_countdown` |
| 2412-2537 | `_update_tutorial_saw_lesson`・`_recover_tutorial_unexpected_ocean_entry`・`_is_expected_tutorial_ocean_entry`・`_update_tutorial_special_step`・`_revive_tutorial_player`・`_recover_tutorial_from_death` |
| 2806-2864 | `uses_tutorial_result_ceremony`・`set_tutorial_emote_keys`・`is_tutorial_score_pause_active`・`get_tutorial_score_pause_elapsed`・`can_resume_tutorial_score_pause`・`resume_tutorial_score_pause`・`_begin_tutorial_score_pause`・`_finish_tutorial_result_ceremony` |
| 3239-3277 | `_update_tutorial_goal`・`_mark_tutorial_goal_arrivals` |
| 4219-4561 | `_resolve_tutorial_collision`・`_resolve_tutorial_hp_lesson_solo`・`_tutorial_miss_hint`・`_resolve_tutorial_collision_2p`・`_resolve_tutorial_guided_wall_2p`・`_resolve_tutorial_hp_lesson_2p`・`_resolve_tutorial_hp_wall_2p`・`_try_finish_tutorial_hp_wall`・`_apply_tutorial_hp_damage`・`_apply_tutorial_lesson_damage`・`_tutorial_lesson_choice_text`・`_tutorial_player_miss_text`・`_tutorial_answer_label`・`_reset_tutorial_attempt` |

**C. 残す関数の中のブロックを削除**（どれも本編では通らない側だけ）

| 関数（行） | 何をするか |
|---|---|
| `_init` 537 | `_install_tutorial_flow(...)` の1行を削除。`tutorial_flow` は今まで常に null 以外だったので、外の `game_state.tutorial_flow` への参照も同時に外す |
| `is_boss_index` 748-750、`num_choices_for_index` 756-757 | チュートリアルの分岐を削除 |
| `uses_saw_chase` 867-869 | チュートリアルの分岐とコメントを削除 |
| `_update_saw_chase` 942-944 | `if _is_tutorial_mode(): _on_tutorial_saw_catch(...); return` を削除。後ろの全滅処理と `_try_finish_hp_question()` は残す |
| `_apply_wall_world_border` 1130-1131 | 壁を隠すときの早期 return を削除 |
| `reset_to_menu` 1780-1787 | 退避した設定を戻すブロックを削除 |
| `load_current_quiz` 1830-1835、1839-1840 | 先頭の早期 return と説明のコメントを削除（`_is_fixed_count_mode` の単純化と同時に） |
| `_recalc_wall_speed` 1901-1903 | 速度を固定する分岐を削除 |
| `update` 1973-1993 | フローの tick と入力ゲートのブロックを削除 |
| `trigger_start` 2126-2132 | 空撮を飛ばす分岐を削除 |
| `_update_countdown` 2158 | `_begin_tutorial_gameplay_after_countdown()` の呼び出しを削除 |
| `_update_playing` 2186-2213 | 入力練習・特別なステップ・速度の倍率・ゴースト練習の入力ロックを削除 |
| `_update_playing` 2270-2276、2319-2324 | 海に落ちたときのチュートリアルの if を2つ削除し、`_begin_ocean_shark_wait(1)`／`(2)` だけを残す |
| `_update_playing` 2342-2343、2356-2358、2370-2372、2384-2386 | のこぎりの練習、スクロールアウトのチュートリアル用 if（協力と通常は残す）、壁を隠す分岐を削除 |
| `_reset_result_ceremony_state` 2760-2761 | 2行を削除 |
| `_start_goal_race` 3036-3056 の4か所 | ローカル変数 `revived_players` ごと削除 |
| `_update_goal_race` 3179-3228 の6か所 | 変数 `tutorial_goal`、`elif tutorial_goal:` の分岐、到着時の処理、全滅時のやり直しを削除 |
| `_begin_result_ceremony` 3412-3421 | `if not _is_tutorial_mode(): provider.end_round()` を `provider.end_round()` にする。`uses_tutorial_result_ceremony()` のブロックは削除。外側の `if not _result_round_closed and not sudden_death_pending:` は残す |
| `_update_result_ceremony` 3521-3559 の3か所 | 得点説明の段階に関する分岐を削除（オンラインのゲストも通る関数。本編では段階が常に NONE なので動きは同じ） |
| `complete_ocean_shark_attack` 4766-4816 | `if _is_tutorial_mode(): … return` を削除。後ろの協力の失敗と全員脱落の処理は残す |
| `resolve_collision` 4977-4979 | チュートリアルへの振り分けを削除 |
| `clear_game` 5239-5250 | チュートリアル用の CLEAR ブロックを削除 |
| `refresh_status_text` 5362-5364、5421-5433 | 2つのブロックを削除 |

**D. 条件を単純化**

| 関数（行） | 書き換え |
|---|---|
| `uses_local_push` 41 | `[MODE_TEN, MODE_ENDLESS, MODE_TUTORIAL]` → `[MODE_TEN, MODE_ENDLESS]` |
| `uses_hp` 564、570 | コメントを削除し、最後の `return _is_tutorial_mode() and …` を `return false` に |
| `_is_fixed_count_mode` 779 | `or mode == Constants.MODE_TUTORIAL` を削除 |
| `is_scroll_out_death_enabled` 855-861 | `return not uses_saw_chase()` にする（関数は残す） |
| `get_floor_front_z` 1105 | `if mode == Constants.MODE_TEN:` に |
| `_prepare_quiz_choices` 1480 | `or _is_tutorial_mode()` を削除 |
| `load_current_quiz` 1873 | `and not _is_tutorial_mode()` を削除 |
| `_record_answer_timing` 1948-1949 | `wall_speed_planner.record_result(correct)` を無条件に |
| `uses_local_result_ceremony` 2799-2802 | `and mode == Constants.MODE_TEN` に |
| `uses_sudden_death` 3634、3639 | コメントと `and not _is_tutorial_mode()` を削除（`not net_online` は残す） |
| `debug_force_draw_finish` 4125 | `or _is_tutorial_mode()` を削除 |
| `advance_after_correct` 5118 | `if missing > 0:` に |
| `_end_round_all_eliminated` 5146 | `if not uses_local_result_ceremony():` に |

**E. コメントだけ直す**：1375-1376（`start_game`）、2137（`trigger_start`）、3033 の見出し（「Goal Race (2P tutorial legacy)」→「Goal Race (2P 10問)」）

### 2-2 `scripts/world/game_world.gd`

旧版の演出監督と3Dガイドを、チュートリアル以外のモードでも毎回作って毎フレーム更新している。消しても通常の見た目と入力は変わらない。

| 種類 | 場所 | 何をするか |
|---|---|---|
| preload を削除 | 5-7 | `TutorialPresentationDirectorScript`・`DuoTutorialGuidesScript`・`SoloTutorialGuidesScript`（8 の `CountdownKeyHintsScript` は残す） |
| 変数を削除 | 64-65、69 | `_tutorial_presentation_director`・`_tutorial_world_guides`・`_tutorial_customize_handoff_in_progress`（66 はコメントだけ直す） |
| 関数を削除 | `_is_tutorial_score_resume_key` | 呼ぶのは `_input` だけ |
| ブロックを削除 | `_input` | `if game_state.is_tutorial_score_pause_active(): … return`（後ろのサドンデスの Space は残す） |
| 条件を単純化 | `_feed_push_input`、`_host_online_push_events` | `or game_state.is_tutorial_presentation_locked()` を削除 |
| 条件を単純化 | `_ready`（MatchReel を作る条件） | `and game_state.mode != Constants.MODE_TUTORIAL` を削除 |
| ブロックを削除 | `_ready` | `if game_state.is_duo_tutorial()…: _saw_controller.preload_model()` |
| 行を削除 | `_ready` | `aim_used.connect(_on_tutorial_ghost_aim_used)`・`charge_resolved.connect(_on_tutorial_ghost_charge_resolved)`（直前の `_match_reel.watch_ghost_rides()` は残す） |
| ノード生成を削除 | `_ready` | `tutorial_presentation_requested`・`tutorial_customize_handoff_requested` の connect、演出監督と Duo/Solo ガイドの new・setup |
| 条件を単純化 | `_ready`（CountdownKeyHints を作る条件） | `if not _replay_mode and not game_state.is_solo_tutorial() and not game_state.is_duo_tutorial():` → `if not _replay_mode:` |
| 関数を削除 | `is_ghost_charge_tutorial_active`、`_on_tutorial_ghost_aim_used`、`_on_tutorial_ghost_charge_resolved`、`_finish_tutorial_ghost_practice`、`_on_tutorial_presentation_requested`、`_on_tutorial_customize_handoff_requested`、`_change_to_customize_tutorial_menu` | 隣の `get_ghost_shark_presentation`・`is_ghost_shark_control_active` は残す |
| ブロックを削除 | `_process` | 入力をゼロにする `if game_state.is_tutorial_presentation_locked():` と `set_tutorial_emote_keys(...)`。演出監督とガイドの `update(dt)`（カウントダウンの更新は残す）。コメント「チュートリアルの判定用」は直す |
| 条件を単純化 | `_debug_force_draw_finish` | `or game_state.mode == Constants.MODE_TUTORIAL` を削除 |
| ブロックを削除 | `_unhandled_input` の3か所 | 完了カードの間の入力の飲み込み、`dismiss_charge_tutorial()`、演出監督の Enter スキップ（コメント1か所も直す） |
| 条件を単純化 | `_update_walls` | 壁を隠す条件を `if _elimination_course_hidden:` に（ブロックは残す）。壁の上限を `if game_state.mode == Constants.MODE_TEN: max_wall_idx = game_state.target_count - 1` に |
| ブロックを削除 | `_update_wall_question` | MODE_TUTORIAL のときの問題文の絞り込み |
| 単純化 | `_update_goal_line` | `tutorial_goal_visible` を消し、`var should_show := challenge_goal_visible` に |
| コメントだけ直す | `_on_state_changed` | 「チュートリアル等で」を削除 |

### 2-3 `scripts/ui/gameplay_hud.gd`

| 種類 | 場所 | 何をするか |
|---|---|---|
| preload を削除 | 5-7 | 旧版のオーバーレイ2本と完了カード |
| 変数を削除 | 89-90 | `_tutorial_panel`・`_tutorial_completion_card` |
| 行を削除 | `_ready` | `_create_tutorial_overlay()` |
| 単純化 | `_retry_game` | `game_state.start_game()` だけにする |
| 行を削除 | `_process` の5か所 | `_update_tutorial_overlay(_dt)` |
| 関数を削除 | `play_tutorial_completion_celebration`・`show_solo_stage_tutorial_complete`・`show_duo_stage_tutorial_complete`・`_duo_score_tower_summary`・`_show_tutorial_completion_card`・`_create_tutorial_overlay`・`_update_tutorial_overlay`・`_build_tutorial_result`・`_add_tutorial_recap_card` | `game_world` からは has_method 経由で呼ばれているので、消す順番は自由 |
| 単純化 | `_generation_phase` | `and game_state.mode != Constants.MODE_TUTORIAL` を削除 |
| 単純化 | `_generation_by_ai` | `return game_state.llm_mode != "OFFLINE" or game_state.net_online` に |
| 単純化とブロック削除 | `_show_waiting_start` | `mode != TUTORIAL and` を削除、if を外して中身を地の文に、末尾のチュートリアル用の部分を削除 |
| 単純化 | `_refresh_start_prompt` | 引数 `is_tutorial` をなくし、"start" と「を押してスタート」に固定（呼び出しも直す） |
| ブロックを削除 | `_show_game_over` | `"TUTORIAL CLEAR!"` の分岐 |
| 単純化 | `_build_result_card` | is_tutorial の変数と早期 return を消す。vs ラベルは "vs" に固定。2P の `if is_tutorial:` を消し、次の `elif current_score != p2_score` を `if` に。1P の `elif is_tutorial:` を消す |
| ブロックを削除 | `_update_score` | 1451-1454 |

### 2-4 `scripts/ui/result_finale_hud.gd`

- 削除：TEXT_JA・TEXT_EN の Note* キー、`NOTE_RECT`、`_note`・`_note_lines`・`_note_footer`・`_note_elapsed`、`update_overlay` の2行、`_update_tutorial_note`・`_build_tutorial_note`・`_make_note_label`、`get_debug_snapshot` の "tutorial_note_*" 3キー
- `get_result_formula_text()` の利用は残す（通常の勝敗メッセージも使う）。パネルを閉じるキーは `game_world._input` 側で一緒に消える

### 2-5 `scripts/world/camera_controller.gd`

| 種類 | 場所 | 何をするか |
|---|---|---|
| 変数・定数を削除 | 35-38、94-100 | `_tutorial_override_*`（4個）、`SOLO_TUTORIAL_CAMERA_*`（2個）、`TUTORIAL_HAZARD_SPLIT_*`（5個） |
| 関数を削除 | `set_tutorial_override_pose`・`clear_tutorial_override`・`_two_player_gameplay_fov`（呼び出しも） | |
| 単純化 | `_third_person_camera_height`・`_third_person_camera_target` | それぞれ `THIRD_PERSON_BASE_HEIGHT`、`focus + Vector3.BACK * 8.0` を返すだけにする（関数は残す） |
| 単純化・ブロック削除 | `_update_camera_pose` | `or _tutorial_override_active` と override のブロックを削除。`tutorial_hazard_split` を消し、else 側（後端に寄ったときに引く処理）だけを毎フレーム通す。2P の FOV は 50 のまま |

### 2-6 `scripts/world/ghost_shark_ride_controller.gd`

ゴーストのチャージの説明表示（旧版のゴースト練習のときだけ出る）とその縮小の受け渡しを、まるごと消す。

| 種類 | 場所 | 何をするか |
|---|---|---|
| 定数を削除 | enum `ChargeTutorialDemoPhase`、`CHARGE_TUTORIAL_*` | 間の `CHARGE_AUDIO_*`・`GHOST_LONG_SFX_CUES` は残す |
| 変数を削除 | `_charge_tutorial_*`（19個） | `_charge_bar_home` は残す |
| 単純化 | `is_control_active_for_player` | `and not is_charge_tutorial_active()` を削除 |
| 関数を削除 | `is_charge_tutorial_active`・`dismiss_charge_tutorial` | `game_world` の呼び出しと同時に |
| 単純化 | `_base_mode_is_eligible` | `and game_state.allows_tutorial_ghost_ride()` とコメントを削除（true 扱い） |
| コメントだけ直す | `_can_continue` | チュートリアルの復活の1行（サドンデスの復活の行は残す） |
| ブロックを削除 | `_update_active_phase` | ENTERING の if/else をやめて `_show_aim_visuals()` と `_start_hud_intro()` だけに。AIMING の `if is_charge_tutorial_active(): … return` を削除 |
| 単純化 | `_update_charge_audio` | 説明表示の条件を削除 |
| 呼び出しを削除 | `_build_aim_visuals` | `_build_charge_tutorial_overlay()` の呼び出し（メーターを `_charge_bar_home` に入れる処理は残す） |
| 関数を削除 | `_build_charge_tutorial_overlay`・`_should_show_charge_tutorial`・`_start_charge_tutorial`・`_update_charge_tutorial`・`_set_charge_tutorial_stop_result`・`_set_charge_tutorial_result`・`_attach_charge_bar_to_slot`・`_restore_charge_bar_home`・ハンドオフの5関数（`_start_charge_tutorial_handoff` など）・`_fill_charge_tutorial_controls` | `KeyHintRow`・`KeycapChip`・`PERFECT_CHARGE_MIN/MAX`・`_set_meter` などは残す |
| ブロックを削除 | `_cleanup_ghost_ride` | `_charge_tutorial_*` のリセットと `_restore_charge_bar_home()` |
| 迷う | signal `aim_used` | 受け手は旧版だけ。完全に消すなら宣言と emit も消す（動きは同じ） |

### 2-7 `scripts/ui/main_menu.gd`（`ui/main_menu.tscn` は変更不要）

| 種類 | 場所 | 何をするか |
|---|---|---|
| preload を削除 | 3、4、6 | コース選択・キーボード説明・完了カード（5 の `MenuMetalButtonScript` は残す） |
| 変数を削除 | 65、67、68、95、97-100 | 64 の `_tutorial_row` はオンライン対戦の行なので残す（名前は変えてよい）。66 と 96 も残す |
| 単純化 | `_ready` | 初回の案内と、旧版明けのカスタマイズ紹介の分岐を消し、`reveal_current → _play_initial_entrance → _start_title_logo_intro` だけにする。行を作る処理はオンライン行として残し、`_ensure_tutorial_selector()` の呼び出しは消す |
| 単純化 | 409 | `not _pending_customize_tutorial_on_ready and` を削除 |
| ブロック・関数を削除 | カスタマイズのシグナルの接続（573-576）、紹介・完了カード・マウス復元・中断の関数（615-696）、`_on_embedded_customize_close_requested` の2行 | `request_close` の接続は残す |
| 引数を削除 | `_play_exit_and_change_scene`・`_begin_scene_change_after_helicopter`・`_begin_scene_change`・`_go_to_game` | 引数 `tutorial_course` を外す。`start_standard_round` は残す（`tests/local_push_runtime.gd` が `_go_to_game(true)` を呼ぶ） |
| 書き換え | `_ensure_tutorial_button` | チュートリアルボタンを消し、**同じ場所に 260×52 の空き枠**（Button ではない Control、mouse_filter=IGNORE）を置く。`visible=false` だと行が詰まり、オンライン対戦がエンドレスの真下からずれる。二重作成のガードは `_online_btn` を見るように変える |
| 関数を削除 | `_ensure_tutorial_selector` など（1071-1099）、`_start_tutorial_game`・`_on_tutorial_keyboard_completed`・`_start_first_run_tutorial`・`_on_tutorial_pressed` | |
| ブロック・行を削除 | `_update_ui` の2行、`_exit_tree` の1行、`_style_all_buttons` のキーボード説明を飛ばす if | `_get_all_buttons` は残す |

- フォーカス：明示の設定はなく Godot の既定の動きなので、空き枠は自動で飛ばされる。「10問から↓」と「エンドレスから Tab」の行き先がオンライン対戦になるので、実機で確かめる

### 2-8 `scripts/ui/customize_settings.gd`

- 削除：signal `tutorial_tour_completed`・`tutorial_tour_aborted`（`request_close` は残す）、`TUTORIAL_TOUR_STEPS`（3枚の画像の preload）、変数（152-166）、`_input`（関数ごと）、`_build_ui` の呼び出し1行、`_build_tutorial_tour_overlay`、`begin_tutorial_tour` からの9関数、`_exit_tree`（関数ごと）、`_prepare_embedded_close` の2行
- 単純化：`_process` の `and not _tutorial_tour_active`、`_set_section` の `if not _tutorial_tour_active:`（match を常に通す）
- `main_menu` との間は has_signal / has_method で守られているので、どちらを先に消しても読み込める

### 2-9 `scripts/autoload/game_manager.gd`

- 削除：版のコメントと `CURRENT_TUTORIAL_VERSION`（作業ツリーでは 7 から 6 に戻されている）、`LEGACY_COURSE_COMPLETED_VERSION`、`TUTORIAL_COURSE_*`、記録の変数（34-43）、関数9個（`should_show_tutorial_on_start`・`has_tutorial_update`・`mark_tutorial_course_completed`・`mark_tutorial_completed`・`is_tutorial_course_completed`・`is_tutorial_course_current`・`tutorial_course_badge`・`dismiss_tutorial`・`reset_tutorial_prompt`）、`_load_user_settings`・`_save_user_settings` の tutorial_* の読み書き
- **古い設定キーの片付け**：`_user_settings` はファイルの中身をそのまま持ち、知らないキーも書き戻す。読み書きを消すだけでは、遊んだことのある人の settings.json に tutorial_* が残り続ける。キーの一覧を定数（例 `LEGACY_TUTORIAL_SETTING_KEYS`）にして、読み込んだ直後に `_user_settings.erase(key)` で消す。消したキーがあったときだけ、最後に1回 `_save_user_settings()` を呼ぶ（8章）
  - 9つのキー：`tutorial_completed`・`tutorial_dismissed`・`tutorial_completed_version`・`tutorial_dismissed_version`・`tutorial_prompt_seen_version`・`tutorial_solo_completed`・`tutorial_local_2p_completed`・`tutorial_solo_completed_version`・`tutorial_local_2p_completed_version`（git の全履歴で書かれたキーと一致）
- autoload なので、定数を先に消すと使う側（`game_state`・`gameplay_hud`・`main_menu`・専用ファイル）が読み込めなくなる。使う側と同じ変更で消す

### 2-10 そのほかのコード

| ファイル | 何をするか |
|---|---|
| `scripts/autoload/audio_manager.gd` | `_tutorial_ducked` と `set_tutorial_ducked` を削除。`CROWD_AMBIENCES` の音量を返す行と、`if _tutorial_ducked: target_db -= 6.0` を単純化（`_sting_ducked` は別の仕組みなので残す） |
| `scripts/core/net/net_predictor.gd` | 176 を `if gs.choice_locked: return` に |
| `scripts/ui/replay_hud.gd` | 175 の `"TUTORIAL"` の腕を削除（古いリプレイはモード名が空になるだけ） |
| `scripts/core/constants.gd` | 61 の `MODE_TUTORIAL` を**最後に**削除 |

### 2-11 コメントだけ直すファイル

`scripts/world/saw_chase_controller.gd` 102、`scripts/world/match_reel/match_reel.gd` 15、`scripts/world/goal_stand/goal_stand.gd` 841-842（`tests/goal_stand_unit.gd` 150 も同じ）、`scripts/cosmetics/player_skin_store.gd` 14、`scripts/ui/skin/skin_editor.gd` 23、`scripts/world/countdown_key_hints.gd` 5-7・10（preload と型名は3Dキーの改名に追従。3-5）

## 3. 削除するファイル

### 3-1 スクリプト（それぞれの .uid も）

| ファイル | git の状態 | 行数 |
|---|---|---|
| `scripts/core/tutorial/solo_tutorial_flow.gd`・`duo_tutorial_flow.gd` | ステージ済み | 825・1006 |
| `scripts/ui/tutorial_coach_bar.gd`・`solo_tutorial_overlay.gd`・`duo_tutorial_overlay.gd` | ステージ済み | 432・18・117 |
| `scripts/ui/tutorial_completion_card.gd`・`tutorial_course_selector.gd` | ステージ済み | 228・204 |
| `scripts/ui/tutorial_keyboard_intro.gd` | ステージ済みの新規（HEAD にない） | 329 |
| `scripts/ui/tutorial_keyboard.gd`・`tutorial_demo_cursor.gd`（どこからも使われていない） | 変更なし | 543・76 |
| `scripts/ui/emote_tutorial_preview.gd.uid`（.gd のない孤立した uid） | 変更なし | 1 |
| `scripts/world/solo_tutorial_guides.gd`・`duo_tutorial_guides.gd` | 変更なし | 383・640 |
| `scripts/world/tutorial_presentation_director.gd` | ステージ済み | 196 |
| `scripts/core/tutorial/tutorial_flow_base.gd`、`scripts/ui/tutorial_glyph.gd`・`tutorial_key_chip.gd`・`tutorial_ui_style.gd` | 作業ツリーで削除済み（.uid も） | — |

**残す**：`scripts/world/tutorial_key_guides_3d.gd`・`tutorial_keycap_3d.gd` は改名して残す（3-5）。共有の `KeyHintRow`・`KeyTokens`・`KeycapChip` も残す。

### 3-2 素材・ツール

| もの | 何をするか |
|---|---|
| `assets/ui/tutorial/`（フォルダごと 4.2MB。カスタマイズ紹介の画像3枚、キーボードの画像2枚と原本の .blend、.import・.gdignore） | 削除 |
| `assets/ui/1p.png`・`2p.png`（と .import） | 削除（使っているのは旧版のコース選択だけ。8章で決定） |
| `tools/tutorial_keyboard/`（キーボード画像を作る Blender 用スクリプト） | 削除 |

旧版専用の BGM・効果音・シェーダー・モデル・アニメーションは残っていない。

### 3-3 テスト（丸ごと削除。.uid も）

`tests/tutorial_flow_accessibility_unit.gd`、`tutorial_keyboard_intro_unit.gd`、`tutorial_keyboard_unit.gd`、`tutorial_renewal_bootstrap.gd`・`_runtime.gd`、`tutorial_revision_runtime.gd`（起動役を失った孤立ファイル）、`tutorial_rules_bootstrap.gd`・`_runtime.gd`、`customize_tour_capture_bootstrap.gd`・`_runtime.gd`

### 3-4 資料（丸ごと削除）

`docs/tutorial_renewal.md`、`docs/tutorial_keyboard/`（24ファイル、5.4MB）

### 3-5 改名して残すもの

| いまの名前 | 新しい名前 | 追従する所 |
|---|---|---|
| `scripts/world/tutorial_key_guides_3d.gd`（`TutorialKeyGuides3D`） | `scripts/world/key_guides_3d.gd`（`KeyGuides3D`） | `countdown_key_hints.gd` の preload・型名・コメント、`tests/countdown_key_hints_*` |
| `scripts/world/tutorial_keycap_3d.gd`（`TutorialKeycap3D`） | `scripts/world/keycap_3d.gd`（`Keycap3D`） | `key_guides_3d.gd` の preload、`tests/countdown_key_hints_runtime.gd` の型 |
| `tests/tutorial_keycap_preview.gd` | `tests/keycap_3d_preview.gd` | 中の preload |

- .uid はファイルといっしょに移し、uid の値は変えない。改名のあとでクラスの一覧（`--import`）を作り直す
- 使っている側の「ゲーム開始時のキー表示」のセッションが止まっているときに行う

## 4. 直すテスト・ツール

| ファイル | 何をするか |
|---|---|
| **`tests/hp_unit.gd` 81-83（最優先）** | `MODE_TUTORIAL` を回すループから外す。35本のテストが読み込んでいる |
| `tests/local_push_unit.gd` 225、257-260 | 対象外モードの一覧から TUTORIAL を外す（撤去後は期待どおりにならず失敗する）。duo flow の load を消す |
| `tests/local_push_runtime.gd` 78-79、136-137、328-339 | TUTORIAL のケースを外す（`emote_push_runtime.gd`・`player_vault_runtime.gd` が extends している） |
| `tools/test_lateral_movement.gd` 11、92-128 | 呼び出しと `_test_tutorial_tasks`・`_step_task_ids` を消す |
| `tests/duo_hud_runtime.gd` 118-120、`tests/result_ceremony_unit.gd` 123、`tests/seat_launch_acceptance.gd` 141-142 | TUTORIAL のケースを外す |
| `tests/ghost_hud_runtime.gd` 116-125 | `_start_charge_tutorial` を呼ぶ段落を消す |
| `tests/net/net_match_runtime.gd` 469 | `and not ghost.is_charge_tutorial_active()` を外す（`run_pair.py` の全シナリオが使う） |
| `tests/net/online_menu_runtime.gd` 55-56 | 行の名前とボタンの確認を、空き枠に合わせて直す |
| のこぎり系：`saw_chase_unit.gd` 150、`saw_chase_modes_runtime.gd` 11-12、`saw_dock_regression.gd` 38、`saw_camera_acceptance.gd` 102、`saw_operator_acceptance.gd` 174 | TUTORIAL のケースを外す |
| `tests/startup_loading_acceptance.gd` 38 | 初回案内を止めるために版を書いている行を消す |
| `tests/santorini_environment_runtime.gd` 149-197、280、291 | チュートリアルの経路を外す（`deep_ocean_runtime.gd`・`santorini_waterfront_runtime.gd` が extends、`santorini_environment_comparison.gd` が preload） |
| `tests/wall_question_regression.gd` 29、50-51、255-268 | TUTORIAL の分岐を外す |
| PV 撮影：`tests/pv_capture/pv_s04_s05_runtime.gd` 89・118-119・145・432、`pv_s20_runtime.gd` 47・87-88・106・177、`pv_s20_skin_runtime.gd` 50・85・240、`pv_s23_runtime.gd` 27・43-44・71・105 | 初回案内を止める版の書き込みと、`has_pending_solo_customize_tour` を外す |
| `tests/countdown_key_hints_*`（新規・未追跡） | 3Dキーの改名に追従する（3-5） |

## 5. 直す資料

- `README.md` 43（モード一覧）、96（モード表の「チュートリアル V2」の行）
- `docs/local_push_duel.md` 3・29・41・59-60・62、`docs/hp_system.md` 9・29、`docs/bgm_renewal.md` 17・39・43・183・712-717・856-857・897、`docs/sound_effects.md` 35・44-45・104・166、`docs/ghost_rider_mount.md` 82、`docs/saw_chase.md` 3・78、`docs/seat_launch.md` 25、`docs/menu_led.md` 21・61、`docs/online_menu.md` 12、`docs/online_versus.md` 8（ボタンの位置を「チュートリアルの右／横」で説明している）、`docs/startup_loading.md` 17、`docs/santorini_town_renovation_plan.md` 56、`docs/santorini_town_verification.md` 49-52、`docs/sudden_death_underground.md` 19、`docs/sudden_death_v2/common.md` 33・69
- `assets/ui/duo_hud/README.md` 27、`assets/ui/result_ceremony/README.md` 23、`assets/animations/result_referee/source/SCENE_PASSPORT.md` 13
- 関係ないもの（直さない）：`docs/menu_led.md` 47（外部の講座の題名）、`assets/environment/harbor_city/README.md` 25、`addons/Tripo3d_Godot_Bridge/README.md`

## 6. 撤去後の確認

### 6-1 機械的な確認

- 全スクリプトが読み込める（クラスの一覧を作り直してからエラーがないこと）
- `rg -i "tutorial|MODE_TUTORIAL|TUTORIAL_COURSE|customize_tour"` で残りを点検する。残ってよいのは `docs/new_tutorial/` だけ（3Dキーは改名するので残らない）

### 6-2 既存テスト

すべてプロジェクト直下で `./Godot_v4.7.2-stable_win64_console.exe` に続けて書く。「※」は4章の修正のあとで流すもの。

| 分野 | コマンド（引数） |
|---|---|
| HP | `--headless --path . --script tests/hp_bootstrap.gd`※、`--path . --script tests/hp_bootstrap.gd --fixed-fps 60 -- runtime case=duo`（case は solo / duo / both / stagger / recovery / goal / replay） |
| 押し合い | `--headless --path . --script res://tests/local_push_unit.gd`※、`--headless --path . --script res://tools/test_lateral_movement.gd`※、`--headless --path . --script res://tools/test_choice_contract.gd`、`--path . --resolution 1600x900 --script res://tests/menu_push_bootstrap.gd` |
| のこぎり | `--headless --path . --script res://tests/saw_chase_bootstrap.gd`※、`saw_dock_bootstrap.gd`、`saw_stow_unit_bootstrap.gd`、`--path . --resolution 1600x900 --script res://tests/saw_stow_runtime_bootstrap.gd` |
| ゴースト | `--path . --script res://tests/ghost_hud_bootstrap.gd`※、`ghost_shark_audio_bootstrap.gd`（ウィンドウが必要）、`--path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/ghost_mount_capture_bootstrap.gd -- tag=check death=ocean`、`shark_contact_bootstrap.gd`（既定・`player=2`・`case=back`・`case=close`） |
| 結果の演出 | `--headless --path . --script tests/result_ceremony_bootstrap.gd`※、`--path . --resolution 1280x720 --fixed-fps 60 --script tests/result_ceremony_bootstrap.gd -- runtime case=p1 fps=60 out=crowd_extras`、`goal_stand_bootstrap.gd`、`match_reel_bootstrap.gd`、`--path . --resolution 1280x720 --fixed-fps 60 --script res://tests/elimination_lasso_bootstrap.gd -- fps=60 quality=high` |
| サドンデス | `--headless --path . --script res://tests/sudden_death_bootstrap.gd`、同 `--fixed-fps 60 -- runtime case=gate`（case=correct も）、`tests/sudden_death_v2/` の parse_check・sky_gate・skygate・ghost_revive、`sudden_death_settings_reel_bootstrap.gd` |
| オンライン | `--headless --path . --script res://tests/net/net_names_unit.gd`、`--path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd`※、`python tests/net/run_pair.py --headless`（`--scenario` push / ghost / ghost_host / result / result_elim / staging）※、`--path . --script res://tests/online_skin_bootstrap.gd -- --fresh-profile` |
| メニュー | `menu_runner_motor_bootstrap.gd`、`menu_ghost_rider_brain_bootstrap.gd`、`--path . --resolution 1600x900 --script res://tests/menu_ghost_ride_bootstrap.gd`、`menu_led_bootstrap.gd`、`menu_harbor_stage_bootstrap.gd`、`menu_skip_cover_bootstrap.gd`、`startup_loading_bootstrap.gd`※、`title_logo_geometry_check.gd` |
| カスタマイズ・設定 | `--headless --path . --script res://tests/player_skin_bootstrap.gd -- --fresh-profile`、`skin_editor_bootstrap.gd`、`--path . --resolution 1280x720 --script res://tests/wall_speed_bootstrap.gd -- runtime`、`max_fps_settings_bootstrap.gd` |
| 壁の文字 | `wall_text_far_bootstrap.gd`、`choice_line_breaker_unit.gd`、`wall_world_border_bootstrap.gd`、`wall_world_border_visual_bootstrap.gd`、`wall_recoil_bootstrap.gd`、`wall_question_regression.gd`※ |
| そのほか | `crowd_extras_bootstrap.gd`、`side_stand_blocks_bootstrap.gd`、`seat_launch_bootstrap.gd`※、`gameplay_sfx_bootstrap.gd`、`bgm_track_bootstrap.gd`、`helicopter_boarding_check.gd`、`mascot_rig_check.gd`、`countdown_key_hints_bootstrap.gd` |

### 6-3 実機で確かめる通常モード

- **起動**：settings.json がなくても旧版の案内が出ず、ロゴの演出とメニューの入場が出る。tutorial_* の入った今の settings.json でも、画質・FPS 上限・サドンデス・オンラインの名前が今までどおり読まれ、tutorial_* だけが消える
- **メニュー**：モード選択の並び（オンライン対戦がエンドレスの真下）、Tab・矢印・Enter、設定へ進んで開始（ヘリの出発、Space でのスキップ）、1人・2人の切り替え、オンライン対戦メニューの行き来、カスタマイズの開閉と閉じたあとのボタン、ゲームから戻ったときの入場、設定パネル
- **1P 10問**：空撮 → 4.99秒のカウントダウン（頭上のキー表示が出て GO で消える）、壁の速さの自動調整、ハート3つ、最後の4択のボス壁、CLEAR と GAME OVER、ステータス文、リトライ（ヘリを省略）
- **1P エンドレス**：途中の先読み、10問ごとのハートの回復、床の延長
- **2P ローカル 10問**：押し合い、のこぎりと刃による脱落（のこぎり中はスクロールアウトなし）、HUD の危険表示、海 → サメ → ゴーストシャーク（照準の輪と HUD がスライドで出る、長押しと離す、PERFECT の色、唸り音）、ゴールレース → スコアタワー → 引き分けでサドンデス、両者脱落の投げ縄（壁が消える）→ 結果、F9
- **2P エンドレス**：のこぎり、全滅
- **2人協力**（メニューに出ていないので、テストで確かめる）：2+2 のドア、スクロールアウトや海での協力失敗、COOP CLEAR、ハートなし
- **オンライン（ホストとゲスト）**：カウントダウンの同期、ゲストの壁の予測、結果発表、サドンデスへ進まない、ゴースト搭乗の同期
- **リプレイ**：押し合いとのこぎりの通信が無効、結果発表なし
- **カメラ**：1P の三人称（プレイ中・死亡時）、フライオーバーの終点、2P の俯瞰と後端での引き、のこぎりが近いときの引き
- **音**：メニュー・プレイ中・ポーズの BGM と観客の声の音量（演出の途中で抜けたときに下がったままになる旧版の不具合も、撤去でなくなる）

## 7. プロジェクトの外・対象外（触らない）

- リポジトリ直下の `_backup_tutorial_qubo_20261001/`（600ファイル。`.git/info/exclude` で git から除外）
- `tutorial_hud.txt`・`tutorial_commit_hud.txt`（gitignore 済み）
- 別プロジェクト `AIQUIZ-Godot-Android/`（旧チュートリアルのコピー29ファイルを git で管理している）
- `artifacts/tutorial_*`（残すと決定済み）。`artifacts/` には .gdignore がないので、Godot がこの中の画像も取り込んでいる（撤去とは別の話）
- `artifacts/main_menu_max_fps/probe.gd` 17 が `GameManager.dismiss_tutorial()` を呼んでいる（型なしの呼び出しなので、実行したときだけ失敗する）
- 設定ホールの黒板の授業（`scripts/world/settings_hall/lesson_builder.gd`・`lecture_director.gd`・`lessons/lesson_03.json`）は旧チュートリアルと関係ない

## 8. 決まったこと（2026-10-24。5つともおすすめどおり）

1. **3Dキーの2本**：撤去のときに名前から tutorial を外して残す（`key_guides_3d.gd`／`KeyGuides3D`、`keycap_3d.gd`／`Keycap3D`。3-5）
2. **新しいコードの名前**：`practice`（`lesson` は設定ホールの授業と紛らわしいため）
3. **`assets/ui/1p.png`・`2p.png`**：消す
4. **古い設定キーの片付け**：読み込んだ直後に消し、消したキーがあったときだけ1回保存する
5. **7章のもの**：触らない
