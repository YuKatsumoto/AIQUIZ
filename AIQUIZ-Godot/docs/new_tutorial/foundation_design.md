# 段階3 土台の設計（v1）

2026-10-25。[計画書](plan.md) の段階3（`MatchRules`・台本の仕組み・オーバーレイ・コース選択・初回の案内・スタンプ・仮のハテナ）の設計。
台本は [course1_script.md](course1_script.md) 〜 [course5_script.md](course5_script.md)。旧チュートリアルは参照しない（撤去済み）。

## 0. 段階3で「できた」と言える状態

1. メインメニューの「チュートリアル」ボタン（今の空き枠 `PracticeSlot` の場所）から、コース選択が開く
2. 初めて起動したときだけ、メニューに「はじめまして！ ハテナと れんしゅう する？」が出る
3. コース①を選ぶと、ゲーム画面が練習のモードで開く。ヘリの到着・問題の生成・試合記録は通らない
4. 仮のハテナ（客席のハテナの部品＋雲）が舞台に立ち、吹き出しで話す
5. ①の 1-1（ようこそ）と 1-2（うごいてみよう）が台本どおりに動く。1-3 以降は段階4で作る
6. 最後まで行くとクリアカードとスタンプが出て保存され、メニューのコース選択へ戻る
7. 本編（10問・エンドレス・2人・オンライン・リプレイ）の動きは変わらない

## 1. 名前とファイル

| ファイル | クラス | 役目 | 担当 |
|---|---|---|---|
| `scripts/core/constants.gd` | — | `MODE_PRACTICE = "PRACTICE"` を足す | A |
| `scripts/core/match_rules.gd` | `MatchRules` | 練習のルールの切り替え口（2章） | A |
| `scripts/core/game_state.gd` | — | 練習の入口・ルールの反映・出来事の通知（3章） | A |
| `scripts/world/game_world.gd` | — | 練習のモードの始まり方・監督の作成・ポーズ画面（4章） | A |
| `scripts/world/ghost_shark_ride_controller.gd` | — | 搭乗の可否を `game_state.allows_ghost_ride()` で見る | A |
| `scripts/autoload/game_manager.gd` | — | スタンプと初回の案内の保存（5章） | A |
| `scripts/practice/practice_session.gd` | `PracticeSession` | メニューとゲーム画面の間でコースを渡す（6章） | B |
| `scripts/practice/practice_catalog.gd` | `PracticeCatalog` | 5コースの一覧 | B |
| `scripts/practice/practice_texts.gd` | `PracticeTexts` | 台本の文字の一覧（ID → 文字） | B |
| `scripts/practice/practice_director.gd` | `PracticeDirector` | 台本を進める（7章） | B |
| `scripts/practice/practice_course.gd` | `PracticeCourse` | コースの土台 | B |
| `scripts/practice/practice_step.gd` | `PracticeStep` | レッスンの土台 | B |
| `scripts/practice/courses/course_1.gd` | — | コース①（段階3では 1-1・1-2） | B |
| `scripts/practice/ui/practice_overlay.gd` | `PracticeOverlay` | 進み具合・吹き出し・チェック・クリアカード（8章） | B |
| `scripts/practice/ui/practice_course_select.gd` | `PracticeCourseSelect` | コース選択（9章） | B |
| `scripts/practice/ui/practice_intro_prompt.gd` | `PracticeIntroPrompt` | 初回の案内（9章） | B |
| `scripts/world/practice/hatena_guide.gd` | `HatenaGuide` | 仮のハテナ（10章） | B |
| `scripts/ui/main_menu.gd` | — | ボタン・コース選択・初回の案内・戻ってきたとき | B |

担当 A・B は実装を分ける単位。A と B は同じファイルを触らない。

## 2. `MatchRules`（`scripts/core/match_rules.gd`）

```gdscript
class_name MatchRules
extends RefCounted

enum Mistakes { NORMAL, REPORT_ONLY }      # REPORT_ONLY：違うドア・壁でもハートも体もそのまま。通知だけ
enum Ocean { NORMAL, REPORT_AFTER_BITE }    # REPORT_AFTER_BITE：サメにかまれてもアウトにせず、通知だけ

var hp_enabled := false
var hp_floor := 0              # 1 にすると、ハートは 1 より減らない
var mistakes := Mistakes.NORMAL
var ocean := Ocean.NORMAL
var saw_enabled := false
var local_push_enabled := false
var scroll_out_enabled := false
var ghost_ride_enabled := false
var world_speed := -1.0        # <0：本番の自動計算、0：止める、>0：その速さ（m/s）
var fence_enabled := false     # 見えないさく
var fence_min := Vector2(-10.0, -6.0)   # (x, P1 基準のコンベア上の z)
var fence_max := Vector2(10.0, 8.0)
var input_locked := false      # 移動・ジャンプ・エモートを止める
var record_results := false    # 問題の成績・AI の改善・分析へ送るか

func duplicate_rules() -> MatchRules   # 全部の値を写した新しいもの
```

- **本編のモードでは使わない。** `game_state.practice_rules` は `MODE_PRACTICE` のときだけ入り、それ以外は `null`。本編の分岐は今のまま残す（本編の動きを変えないため）
- 台本はレッスンごとに `MatchRules` を作って `game_state.set_practice_rules()` で入れかえる

## 3. `game_state.gd` に足すもの（担当 A）

### 3.1 状態

```gdscript
var practice_rules: MatchRules = null
var practice_boss_indices: Array[int] = []

signal practice_wall_contact(player_index: int, door: int, correct: bool)  # 壁に着いた（door < 0 は壁、-2 はドアの境目）
signal practice_ocean_bitten(player_index: int)   # REPORT_AFTER_BITE のときだけ
signal practice_fence_touched(player_index: int)
signal practice_quizzes_finished                  # 用意した問題を全部終えた
```

### 3.2 入口

```gdscript
## start_game の練習版。問題の供給元を使わず、渡した問題で始める。
## mode = MODE_PRACTICE、target_count = quizzes.size()、プレイヤーとハート・のこぎり・海などを start_game と同じく初期化し、
## state は start_state（PLAYING か WAITING_START）にする。quiz_loaded / state_changed を本編と同じように出す。
func start_practice_round(quizzes: Array[QuizItem], players: int, rules: MatchRules,
		boss_indices: Array[int] = [], start_state: String = Constants.STATE_PLAYING) -> void

## 問題の差し替え（同じラウンドのまま、次の壁から新しい問題にする）。index は current_index から数え直す。
func set_practice_quizzes(quizzes: Array[QuizItem], boss_indices: Array[int] = []) -> void

func set_practice_rules(rules: MatchRules) -> void

## プレイヤーを置き直す（x、コンベア上の z）。速さ・落下・海の状態・外からの力を消す。
func practice_place_player(player_index: int, x: float, local_z: float) -> void

## いまの壁が、P1 から distance（m）先に来るように置き直す。壁は空から落ちてくる見た目でよい（段階3では瞬間移動でも可）。
func practice_place_current_wall(distance: float) -> void

func practice_set_hp(player_index: int, hp: int) -> void   # health_changed を出す（増える・減る動きが出る）
func practice_revive(player_index: int) -> void             # アウト・海・のこぎりの状態を消して生き返らせる

## 搭乗の可否。本編は true（今までどおり）、練習は practice_rules.ghost_ride_enabled。
func allows_ghost_ride() -> bool
```

### 3.3 ルールの反映（`practice_rules != null` のときだけ）

| 場所 | 反映 |
|---|---|
| `uses_hp()` | `practice_rules.hp_enabled` |
| `_set_player_hp` | `hp_floor` より下げない |
| `uses_saw_chase()` | `saw_enabled and num_players == 2 and saw_transport_enabled` |
| `is_scroll_out_death_enabled()` | `scroll_out_enabled` |
| `uses_local_push()` | `local_push_enabled and num_players == 2` |
| `_update_playing` の速さ | `world_speed >= 0` ならその値（0 ならコンベアも壁も止まる） |
| `_update_playing` のあと | `fence_enabled` なら各プレイヤーの x とコンベア上の z を範囲に収め、はみ出したら `practice_fence_touched` |
| `update()` の入力 | `input_locked` なら移動・ジャンプ・エモートを 0 にする |
| `resolve_collision` | 最初に、壁に着いた人ごとに `practice_wall_contact(player, door, correct)` を出す。`REPORT_ONLY` で不正解（壁・違うドア）なら、その人を壁の 1.5m 手前へ戻すだけで終わる（ハート・体・`choice_locked` はそのまま）。正解は本編と同じ流れ |
| `complete_ocean_shark_attack` | `REPORT_AFTER_BITE` なら、アウトにせず `practice_ocean_bitten` を出す（その人は海で待ったまま。監督が `practice_revive` と `practice_place_player` で戻す） |
| `_is_fixed_count_mode()`・`get_floor_front_z()` | 練習も10問と同じく「問題の数だけ壁を出す」扱い |
| `num_choices_for_index` | 練習は、その問題の選択肢の数（`quiz.c.size()`。2 か 4） |
| `is_boss_index` | 練習は `practice_boss_indices` に入っている番号 |
| `load_current_quiz` | 練習で問題が尽きたら `clear_game()` もゴールレースもせず、`current_quiz = null` にして `practice_quizzes_finished` を出す |
| 記録 | `record_results` が false なら、`provider.submit_result`・`QuizManager.quiz_optimizer.evaluate_history`・`QuizManager.player_analytics.record` を呼ばない（`quiz_history` は残す。②のリザルトで使う） |
| `reset_to_menu()` | `practice_rules` と `practice_boss_indices` を消し、mode を `MODE_TEN` に戻す |

## 4. `game_world.gd` に足すもの（担当 A）

- `game_state.mode == MODE_PRACTICE` のとき：
  - ヘリの到着の演出を作らない（`skip_helicopter_arrival` と同じ扱いで、プレイヤーは最初から床の上）
  - `MatchReel`（戦績とハイライト）を作らない
  - `_reveal_after_transition` は問題の生成を待たずにすぐ画面を開く
  - `PracticeDirector`（`res://scripts/practice/practice_director.gd`）を作って子にし、`setup(game_state, self, camera_controller, player_node, stage_env)` を呼ぶ。`var practice_director: Node` で外から取れるようにする
  - `_update_walls` の「問題の数だけ壁を出す」上限を、10問と同じく練習にも当てる
- ポーズ画面（`_build_pause_menu`）：練習のときだけ「この レッスンを とばす」ボタンを足す（`practice_director.skip_step()` を呼んでポーズを解く）。「タイトルに戻る」は練習のとき `practice_director.quit_course()` を呼ぶ（中で `reset_to_menu` とメニューへの移動をする）
- 客席のハテナ（`StandMascot`）は、練習のときは隠す（ハテナが2人いるように見えないように。決定済み）

## 5. `game_manager.gd` に足すもの（担当 A）

```gdscript
var practice_stamps: Dictionary = {}   # コースID → {"star": bool}。押してあるコースだけ入る
var practice_intro_seen := false

func has_practice_stamp(course_id: String) -> bool
func practice_stamp_star(course_id: String) -> bool
func mark_practice_stamp(course_id: String, star: bool) -> void   # ★は一度付いたら消さない。保存する
func mark_practice_intro_seen() -> void                           # 保存する
```

- `user://settings.json` のキーは `practice_stamps`・`practice_intro_seen`。今の読み書き（`_load_user_settings`・`_save_user_settings`）に足す

## 6. コースの受け渡し（担当 B）

```gdscript
class_name PracticeSession
extends RefCounted

static var course_id := ""            # 例 "c1"
static var with_cpu := false
static var from_first_run := false    # 初回の案内から始めた
static var return_to_select := false  # メニューに戻ったらコース選択を開く

static func launch(menu: Node, id: String, cpu := false, first_run := false) -> void
## game_state.mode = MODE_PRACTICE、num_players をコースに合わせ、
## メニューの `_play_exit_and_change_scene("res://scenes/game_world.tscn", false)` でゲーム画面へ移る
```

- `PracticeCatalog.COURSES`：`[{id, number, title, players, minutes, course_script, available}]`。5コース（c1〜c5。台本の番号と同じ）。段階3では c1 だけ `available = true`
- `PracticeCatalog.next_recommended() -> String`：スタンプのない最初のコース
- `PracticeTexts.get_text(id) -> String`：台本の4章の一覧（c1〜c5 の全部）をそのまま入れる。ない ID は `"[id]"` を返して警告を出す

## 7. 台本の仕組み（担当 B）

### 7.1 コースとレッスン

```gdscript
class_name PracticeCourse
extends RefCounted
var id := ""
func build_steps() -> Array[PracticeStep]        # レッスンの並び

class_name PracticeStep
extends RefCounted
var id := ""                  # "1-1" など
func enter(d: PracticeDirector) -> void          # ルール・位置・壁・ハテナを整えて始める
func process(d: PracticeDirector, dt: float) -> void
func on_event(d: PracticeDirector, event: StringName, data: Dictionary) -> void
func exit(d: PracticeDirector) -> void
func rewind(d: PracticeDirector) -> void         # まきもどし（既定は enter をやり直す）
```

### 7.2 監督 `PracticeDirector`（Node）

- `setup(game_state, world, camera_controller, player_node, stage_env)` で `PracticeSession.course_id` のコースを読み、オーバーレイとハテナを作り、`start_practice_round` を呼んで最初のレッスンを始める
- `game_state` の signal（`practice_*`・`correct_answer`・`health_changed`・`player_entered_ocean` など）を受けて、いまのレッスンの `on_event` に渡す。ジャンプ・エモート・位置は毎フレーム見て、`&"jumped"`・`&"emoted"` などの出来事にして渡す
- レッスンが使う道具：
  - `say(id) -> Signal`：吹き出しを出す。終わったら返る signal（`await d.say(...)`）。時間は台本①の 1.2（0.8秒＋1文字0.12秒、1.8〜4.0秒）
  - `set_rules(rules)`、`place_player(...)`、`place_wall(distance)`、`set_hp(...)`、`revive(...)`
  - `hatena`（`HatenaGuide`）、`overlay`（`PracticeOverlay`）
  - `complete_step()`：次のレッスンへ。最後なら `finish_course(star)`
  - `fail_step(line_id := "")`：まきもどし。失敗の回数を数える（2回で矢印のヒント、3回で壁を半分の速さ。段階3では回数を数えるところまで）
  - `skip_step()`（ポーズ画面から）、`quit_course()`（メニューへ。スタンプなし）
- `finish_course(star)`：クリアカードとスタンプ → `GameManager.mark_practice_stamp` → ボタン［つぎの コースへ］［メニューに もどる］。どちらも `PracticeSession.return_to_select = true` にしてメニューへ戻る（段階3では、つぎのコースは選択画面で選ぶ）

## 8. オーバーレイ `PracticeOverlay`（CanvasLayer、担当 B）

- 画面の上の真ん中：コース名と進み具合の点（●○○）
- 吹き出し：ハテナの頭の画面位置（カメラで投影）に付いて動く 2D の吹き出し。画面の端で止める。1行・大きめの文字（NotoSansJP-Bold）
- チェック：1-2 のような「← ✓」「→ ✓」の小さなカード（段階3は 2D で画面の下に。看板の壁は段階4）
- クリアカード：コース名・「クリア！」・スタンプ（★付き）・ボタン2つ
- ポーズ中も動く（`process_mode = PROCESS_MODE_ALWAYS`）

## 9. メニュー（担当 B）

- `main_menu.gd` の `PracticeSlot`（260×52 の空き枠）を、同じ大きさの金属ボタン「チュートリアル」（`MenuMetalButton`、compact）に戻す。押すとコース選択を開く。オンライン対戦がエンドレスの真下にある並びは変えない
- コース選択 `PracticeCourseSelect`：メニューの上に重ねるパネル。5枚のカード（番号・名前・人数「1人」／「2人・CPU」・目安時間・スタンプ）、おすすめのカードに「つぎは これ」。`available = false` のカードは「じゅんびちゅう」で押せない。「← もどる」と Esc で閉じる。矢印キーと Enter でも選べる
- 初回の案内 `PracticeIntroPrompt`：`GameManager.practice_intro_seen` が false のとき、メニューが出たあとに出す。［する］で①を始める（`from_first_run = true`）、［あとで］で閉じる。どちらでも `mark_practice_intro_seen()`
- メニューに戻ってきたとき `PracticeSession.return_to_select` が true なら、コース選択を開いてフラグを消す
- `tests/net/online_menu_runtime.gd` の「左は押せない空き枠」の確認を、「左はチュートリアルのボタン」に直す

## 10. 仮のハテナ `HatenaGuide`（Node3D、担当 B）

- 体と動き：`StandMascot`（`scripts/world/crowd/stand_mascot.gd`）をそのまま使う。動きの名前は台本の動きに当てる（手をふる→`idle`、ばんざい→`cheer`、拍手→`clap`、おどる→`dance`、指す→`point`、胸をはる・両手を広げる→`hold_card`。足りない動きは段階10で作る）
- 雲：`assets/characters/aiquiz_mascot/mascot_cloud.glb` と `mascot_cloud.gdshader`（使い方は `scripts/world/elimination_lasso/lasso_cloud_rider.gd` の `_setup_cloud` を見る）。`set_cloud(true)` で足もとに出す
- 道具：`place_at(pos, facing)`、`hop_to(pos, seconds)`（放物線）、`play(action)`、`set_cloud(on)`、`bubble_anchor(camera) -> Vector2`（頭の上の画面位置）
- 大きさ：舞台で見えるよう、等倍の 1.3 倍を目安にする（実機で合わせる）

## 11. コース①（段階3の範囲）

- 1-1 ようこそ：コンベアを止め、入力を止める。ハテナが前方に立ち（段階3は看板の壁なし）、`c1.welcome.1〜3` を言う。終わったら入力を戻して 1-2
- 1-2 うごいてみよう：見えないさく（x ±10、z −6〜+8）。オーバーレイのチェック「← → ↑ ↓」。左右・前後に合計1.5mずつ動くと ✓。8秒なにも押さないと `c1.move.idle`。4つそろったら `c1.move.4` → コースの終わり（段階3では、ここで `finish_course`）
- 問題はまだ使わない（`start_practice_round` には空の問題で入る）

## 12. 確かめ方

- 単体テスト `tests/practice_unit_bootstrap.gd`（ヘッドレス）：`MatchRules` の写し、スタンプと初回の案内の保存（`settings_path` をテスト用に差し替える）、`PracticeCatalog`、`PracticeTexts` に台本の全 ID があること、`game_state` のルールの反映（ハートの下限、`REPORT_ONLY` でハートが減らず通知が出る、`world_speed = 0` でコンベアが止まる、さく、`record_results = false` で記録が呼ばれない）
- 実機のテスト `tests/practice_smoke_bootstrap.gd`：メニューからコース①を始め、キー入力で 1-2 を終え、スタンプが付いてメニューのコース選択に戻ることを確かめ、要所の画面を `artifacts/practice_smoke/` に撮る
- 本編の既存テスト（HP・押し合い・結果の演出・横移動・ドアの選択肢）が今までどおり通ること
