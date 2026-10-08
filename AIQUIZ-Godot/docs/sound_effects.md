# 効果音（SE）

ゲーム内の効果音の仕組みと、どの場面で何が鳴るかをまとめる。BGM は `docs/bgm_renewal.md`。

## 仕組み

- **素材**：`assets/audio/sfx/{ui,game,world,ambience}/` の Ogg Vorbis（2026-10-09 追加、101ファイル）。すべて CC0 の素材を加工したもので、出典は `assets/audio/sfx/CREDITS.md`。
- **音の一覧**：`scripts/autoload/sfx_catalog.gd`。音の名前（キュー）ごとに、ファイル（複数あればランダム）、音量、ピッチ、ピッチの揺らぎ、連打防止の間隔を書く。音量の調整はここだけで済む。
- **鳴らし方**（`AudioManager`）
  - `play_sfx(&"名前", 音量dB, ピッチ)`：2D の効果音。16音まで同時に鳴らせ、足りなければ一番古い音を止める。
  - `start_sfx_loop(キー, &"名前", 音量dB, フェード秒, 持ち主ノード)` / `stop_sfx_loop(キー)` / `set_sfx_loop_volume()` / `set_sfx_loop_pitch()`：ループ音。持ち主ノードがツリーから外れると自動で止まる。
  - `get_sfx_stream()` / `get_sfx_volume_db()`：ワールド側のスクリプトが自分の 3D 音源（AudioStreamPlayer3D）で一覧の音を使うためのもの。
- **すべて SFX バスで鳴る**ので、設定画面とポーズ画面の「効果音量」でまとめて調整できる。

## UI の自動割り当て

`AudioManager` は、ツリーに追加された Button / Slider / TabBar / TabContainer に自動で音を付ける。画面ごとのコードは不要。

| 操作 | 音 |
|---|---|
| マウスを乗せる / 矢印キー・Tab でフォーカスを移す | `ui_hover`（コードからの `grab_focus()` と、シーン切り替え直後0.35秒は鳴らさない） |
| ボタンを押す | `ui_click`。名前・表示文字に「戻る」「閉じる」「キャンセル」「メニュー」、back / close / cancel / quit / exit などを含めば `ui_back`、「スタート」「開始」「決定」「もう一度」、start / ok / retry などを含めば `ui_confirm` |
| トグルボタン | `ui_toggle_on` / `ui_toggle_off` |
| スライダー（ユーザー操作のときだけ） | `ui_slider`（値が大きいほど高い音） |
| タブ | `ui_tab` |

ボタンごとの指定：`set_meta("sfx_press", &"名前")` で押したときの音を変える。`set_meta("sfx_silent", true)` で鳴らさない（押した処理の中で別の音を鳴らすボタン用）。`set_meta("sfx_no_hover", true)` でホバー音だけ止める。

## 場面ごとの効果音

| 場面 | 出来事 | キュー | 鳴らしている場所 |
|---|---|---|---|
| 起動 | メニューが最初に表示される | `ui_shimmer` | `main_menu.gd` `_ready` |
| メニュー | 背景の環境音（波・カモメ・風） | `amb_ocean`（ループ） | `main_menu.gd` `_ready` |
| メニュー | モード選択 → 設定画面 | `ui_confirm` + `ui_swish_light` | `_assign_menu_sfx` / `_update_ui` |
| メニュー | 教科・学年・難易度のベルトが動く / 止まる | `ui_belt_start` / `ui_belt_stop` | `MenuConfigConveyor` の `motion_started` / `motion_finished` |
| メニュー | 設定・カスタマイズ・チュートリアルを開く | `ui_open` | 同上（ボタンのメタ） |
| メニュー | 「LETS'GO」：シャッター、文字の点滅2回、落下 | `ui_shutter_slam` / `ui_text_blip` / `ui_swish` | `_play_start_ui_departure` |
| メニュー | ヘリ出発のスキップ（Space） | `ui_swish` | `_skip_menu_helicopter_departure` |
| 画面切り替え | ワイプで覆う / 開く | `ui_wipe_in` / `ui_wipe_out` | `scene_transition.gd` |
| カスタマイズ | 帽子の切り替え（スライド / 着地） | `ui_swish_light` / `ui_hat_land` | `customize_settings.gd` |
| カスタマイズ | エモートを枠にセット | `ui_equip` | `_on_grid_emote_selected` |
| カスタマイズ | 紹介ツアー：開く / ページ送り / 終了 / Esc | `ui_open` / `ui_page_flip` / `ui_confirm` / `ui_back` | 同上 |
| チュートリアル導入 | コース選択・キー説明を開く、キーを押す、Esc | `ui_open` / `ui_keycap` / `ui_back` | `tutorial_course_selector.gd` / `tutorial_keyboard_intro.gd` |
| オンライン | 接続 / 相手が参加 / 開始 / 切断・失敗 / コード未入力 | `ui_confirm` / `ui_joined` / `ui_ready` / `ui_disconnect`・`ui_error` / `ui_error` | `online_lobby.gd` |
| 開始前 | 問題の壁が上空から着地（最大10枚） | `wall_slam`（カメラに近いほど大きい） | `game_world.gd` `_update_preview_walls` |
| 開始前 | 開始壁の着地 | `barrier_land` | `_update_start_barrier` |
| 開始前 | Enter で開始できるようになった | `ui_ready` | `gameplay_hud.gd` `_show_waiting_start` |
| 開始前 | Enter / 上空カメラ移動 | `ui_confirm` / `flyover` | `game_world.gd` |
| 開始前 | カウントダウン 4・3・2・1 と蒸気 | `countdown_beep` / `barrier_steam`（ループ、揺れと一緒に大きくなる） | `_update_start_barrier` |
| 開始 | GO で開始壁が爆発 | `countdown_go` + `barrier_explode` | `_explode_start_barrier` |
| プレイ中 | ベルトコンベアの音 | `amb_belt`（ループ） | `_update_state_sfx` |
| プレイ中 | 問題が出る（文字の表示から0.6秒後） / ボス問題 | `question` / `boss_warning` | `_update_wall_question` |
| プレイ中 | 正解の扉が壊れる | `door_smash`（正解チャイムに重ねる） | `_on_correct` / `_on_question_completed` |
| プレイ中 | 全員不正解（ハートは残る） | `buzzer` | `_on_question_completed` |
| プレイ中 | 不正解の扉・壁に当たる（ハートが減る） | `bonk` + `heart_lose`、残り1で `low_hp` | `_update_player_sfx` |
| プレイ中 | ハート回復（エンドレス10問ごと） | `heart_restore` | 同上 |
| プレイ中 | 連続正解（2問目から音程が上がる） | `streak` | 同上 |
| プレイ中 | ジャンプ / 着地 | `jump` / `land` | 同上 |
| プレイ中 | エモート | `emote` | 同上 |
| プレイ中 | ベルトの端から落ちる / 海に落ちる | `fall_whistle` / `splash` | 同上 / `_on_player_entered_ocean` |
| プレイ中 | 致命的な激突 / 2秒後に体が弾ける | `wall_crash` / 既存の爆発音 + `body_pieces` | `_update_player_sfx` / `_check_particles` |
| プレイ中 | 倒れた体が海に落ちる | `splash_small` | `_check_particles` |
| プレイ中 | のこぎりに捕まる（5つの部品が飛ぶ） | `saw_catch` + `limb_pop` ×5 | `_on_player_caught_by_saw` |
| プレイ中 | 画面外に取り残されて脱落 | `player_out` | `player_scrolled_out` |
| プレイ中 | 壁横のフォースフィールドに押し戻される | `force_field` | `world_border_pushed` |
| プレイ中 | のこぎり・画面後端が迫る（赤い点滅に合わせる） | `danger_beep`（近いほど大きく高く） | `gameplay_hud.gd` `_play_rear_edge_warning_beep` |
| 2P押し合い | 体当たり / 同時の体当たり / 接触 | `push_hit` / `push_clash` / `push_contact` | `_on_local_push_event` |
| ゴール | ゴールまでの競争が始まる | `whistle` | `_update_state_sfx` |
| クリア | 花火（打ち上げ / 破裂）、紙吹雪 | `firework_launch` / `firework_burst`、既存の `confetti` | `particle_spawner.gd` / `gameplay_hud.gd` `_fire_confetti` |
| 結果 | スコアの加算 / 加算の終わり | `ui_score_tick` / `ui_score_ding` | `gameplay_hud.gd` `_play_score_count_sfx` |
| 2P結果演出 | 花火4発 | `firework_burst` | `result_ceremony_director.gd` |
| ポーズ | 開く / 閉じる | `ui_pause_in` / `ui_pause_out` | `game_world.gd` `_toggle_pause` |
| チュートリアル | ミスでやり直し / 復帰 / ステージ完了の紙吹雪 | `retry` / `respawn` / `confetti` | `_check_particles` / `_on_tutorial_presentation_requested` |
| ヘリ | ローター（既存の重低音に録音を重ねた） / 着地の衝撃（同） | `heli_rotor` / `runner_land` | `helicopter_arrival_director.gd` `_layer_recorded_sfx` |
| ヘリ | 縄ばしごが下りる / 飛び降りる / 尾部ジェット点火 | `rope_unroll` / `ui_swish` / `heli_boost`（3D） | 同上 / `helicopter_boost_exhaust.gd` |
| のこぎり | 運搬船の汽笛（到着・出発） | `ship_horn`（3D） | `saw_dock_presentation.gd` |
| のこぎり | 運搬船がいないとき（2Pチュートリアル）の刃の回転音 | 既存の `dock_spindle.wav` | `saw_chase_controller.gd` `_update_fallback_spindle` |
| ロケット椅子 | ベルトが飛び出す / 着地 | `belt_zip` / `chair_touchdown`（3D） | `seat_launch_presentation.gd` |
| ゴーストシャーク | 魂の上昇 / サメに乗る / 光の柱 | `soul_rise` / `rider_land` / `beam_fire` | `ghost_shark_ride_controller.gd` |
| ゴーストシャーク | チャージ（音程が上がるループ）/ PERFECT 帯 / 突進 / ミス | `charge_loop` / `charge_perfect` / `charge_release` / `charge_miss` | 同上 |
| ゴーストシャーク | 帰りのポータルが開く / 通過する | `portal_open` / `portal_cross` | 同上 |
| プレイ中 | 環境音（波・カモメ・風） | `amb_ocean`（ループ） | `game_world.gd` `_ready` |

## 既存の動きを変えたところ

- **不正解の爆発音のタイミング**：これまでは不正解の通知（`wrong_answer`）で爆発音を鳴らしていたため、体が弾ける2秒前の激突の瞬間に鳴り、ラウンドが終わるときにしか鳴らなかった。今は激突の瞬間に `wall_crash`、体が弾けた瞬間に既存の爆発音を鳴らす。チュートリアルの軽いのけぞりにも、本編と同じ `bonk` が鳴る。
- **メニュー背景の 3D 音**：背景を描く SubViewport で `audio_listener_enable_3d` を有効にした。これまで鳴っていなかった運搬船・のこぎり格納・ロケット椅子・ヘリ出発の 3D 音が聞こえるようになる。
- **結果演出の「swish」**：存在しないキュー名を呼んでいて無音だったので、`hero_swish.ogg` を登録した。
- **結果演出の花火**：紙吹雪の音を流用していたのを `firework_burst` に替えた。共有の効果音プールで鳴るので、シンバルや残念トロンボーンが途中で切れにくくなった。
- **ゴール観客の声**：同時発音を5から8に増やし、空いている音源を優先するようにした。卵の音で長い歓声・ブーイングが切れにくくなった。

## BGM 計画との関係

`docs/bgm_renewal.md` の単発素材（`sting_countdown`、`ceremony_build`、`sting_verdict`、`jingle_clear`、`jingle_gameover`）は音楽として BGM 側で作るので、効果音では作っていない。

- カウントダウンには短い電子音だけを入れた。`sting_countdown` を入れて重なるときは、`sfx_catalog.gd` の `countdown_beep` / `countdown_go` の音量を下げるか、`game_world.gd` `_update_start_barrier` の呼び出しを外す。
- 結果演出の静寂（6.3秒の hush）には何も足していない。

## 入れていないもの

- 足音：ベルトの上で常に走っているので、鳴らし続けると耳障りになる。ベルトの環境音で代わりにした。
- 観客のざわめきのループ：CC0 で使える素材が拍手ばかりだったので見送った（歓声などの単発音は既存）。
- メニュー背景のプレビュー（壁の合体、CPU の激突など）、ヘリのハッチ・ウインチ、運搬船の細かい機械音、結果演出の歩き・ひざまずき：優先度が低いので見送った。
- サドンデス、設定ホール、リプレイ、協力モード、単独のカスタマイズ画面：通常のプレイでは開けないので触っていない。
