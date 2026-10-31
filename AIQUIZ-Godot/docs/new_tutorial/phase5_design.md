# 段階5 コース② の設計（v1）

2026-10-25。[計画書](plan.md) の段階5（コース②「ほんばんへ GO」）の設計。
台本は [course2_script.md](course2_script.md)。共通の約束は [course1_script.md](course1_script.md) の1章、土台は [foundation_design.md](foundation_design.md)（段階3）と [phase4_design.md](phase4_design.md)（段階4）。旧チュートリアルは参照しない（撤去済み）。

## 0. 段階5で「できた」と言える状態

1. コース選択で②が遊べる。①のクリアカードの［つぎの コースへ］で②が始まる
2. 2-1（ジャンプで ハイタッチ）・2-2（おどろう）が台本どおりに動く（看板の壁と雲のハテナ）
3. 2-3：本物のポーズ画面の上で、画面のコーチ（光る枠・まわりを暗く・光っている所だけ押せる）が台本どおりに案内する
4. 2-4：ミニ本番が本番と同じ始まり方（開始の画面 → 空撮 → カウントダウン）で始まり、本物の CLEAR／GAME OVER のカードが出る。GAME OVER なら『リトライ』でミニ本番の始めから
5. 2-5：本物のリザルトのカードの上で、コーチが順に案内する（評価・問題履歴・『◀ 戻る』・『メニュー』）。練習の結果と評価はどこにも送らない
6. 2-6：メインメニューへ移っても②の続きが始まる。のこぎりの操縦席のハテナが雲で出てきて、モード選択と設定の画面を案内する
7. クリア：メニューの上でクリアカードとスタンプ。［ほんばんを はじめる］で本物の本番が始まる、［あとで］で設定の画面に残る
8. 本編（10問・エンドレス・2人・オンライン・リプレイ）とコース①の動きは変わらない

## 1. 担当とファイル

| 担当 | 触るファイル |
|---|---|
| A（ゲーム画面の本編側） | `scripts/core/game_state.gd`・`scripts/core/match_rules.gd`・`scripts/world/game_world.gd`・`scripts/ui/gameplay_hud.gd`・`scripts/ui/player_health_hud.gd`・`scripts/world/countdown_key_hints.gd`・`scripts/autoload/match_history.gd` などの記録の所・`tests/practice_unit.gd` |
| B（ゲーム画面の台本側） | `scripts/practice/` の下（**`ui/practice_coach.gd`・`practice_session.gd`・`menu/` の下を除く**）・新しい `scripts/practice/courses/course_2.gd`・新しいテスト `tests/practice_course2_smoke_*.gd` |
| C（舞台の小物） | `scripts/world/practice/` の下（看板の壁・ハテナ・新しいハテナの小窓） |
| D（画面のコーチとメニュー） | 新しい `scripts/practice/ui/practice_coach.gd`・新しい `scripts/practice/menu/` の下・`scripts/practice/practice_session.gd`・`scripts/ui/main_menu.gd`・`scripts/world/saw_chase_controller.gd`（操縦席のハテナを隠す所だけ）・新しいテスト `tests/practice_menu_coach_*.gd` |

- 担当どうしで同じファイルを触らない。ほかの担当の道具が要るときは、この文書の約束どおりに呼ぶ。まだないうちは、スクリプトのパスを `load` できるか・`has_method` で確かめてから呼ぶ（class_name を直接書くと、相手のファイルがまだないときに読み込みエラーになる）。約束と違うことが必要になったら、自分で相手のファイルを直さず報告に書く
- 作業ツリーには、ほかのセッション（例：サドンデスの演出）の変更も入っている。`git checkout`・`stash`・`reset`・`restore`・コミットはしない。自分のファイル以外は戻さない・整形しない
- 画面の重なり（CanvasLayer の layer）：ゲームの HUD 1、DeathWipe 5、練習のオーバーレイ 20、ポーズ画面 100、**コーチ 105**（暗くする・光る枠）、**コーチの吹き出しとハテナの小窓 106**

## 2. 共通の約束（監督役が先に入れたもの）

`scripts/practice/practice_session.gd` に、コースをまたいで渡す値を足してある（中身を使うのは B と D）：

```gdscript
## メニューに戻ったら、そのコースの続き（メニューの上のレッスン）を始める。
## 例：②の 2-6 は {"course": "c2", "step": "2-6", "star": true, "skipped": 0, "first_run": false}。メニューが始めたら消す。
static var resume_in_menu := {}
## メニューに戻ったら、このコースをすぐ始める（クリアカードの［つぎの コースへ］）。メニューが始めたら消す。
static var launch_next := ""
```

## 3. 担当 A：ゲーム画面の本編側

### 3.1 `MatchRules` に足す

```gdscript
## 用意した問題を全部終えたら、本番の1人の10問と同じく CLEAR にする（practice_quizzes_finished は出さない）。
var finish_with_clear := false
## GAME OVER と CLEAR を本番どおりの画面（カード・紙吹雪・死ぬ演出のあとのカード）で見せる。
## false（既定）は段階4の「練習の負け」（カードを出さない）。どちらでも practice_round_lost は出す。
var real_result_screens := false
```

`duplicate_rules()` にも足す。

### 3.2 本番と同じ始まり方（2-4）

- `start_practice_round(quizzes, 1, rules, [2], Constants.STATE_WAITING_START)` で、本番の1人の10問と同じ流れになる：
  - 開始の画面「[ Enterを押してスタート ]」（本番の HUD の表示）。開始の前の壁は本番と同じく空から落ちてくる（段階4の練習の壁の落とし方と二重にしない）
  - Enter → 空撮（3.8秒。3枚の壁の上を通って最後のボス壁まで）→ カウントダウン（4.99秒。頭の上に操作キー）→ PLAYING
  - ヘリの到着・問題の先読み・問題の生成は通らない
- 状態が変わるたびに今までどおり `state_changed` が出る（監督はこれで流れを知る）

### 3.3 本番どおりの結果の画面（2-4・2-5）

- `real_result_screens` のとき：
  - 1人の GAME OVER は本番どおり（体が崩れ、約4秒後にカード）
  - `finish_with_clear` で最後の壁を抜けたら、本番どおりの CLEAR（花火・紙吹雪・カード）
- 右上の「正解: 0  問題: 1/3」と、カードの「正解 / 3問」は、練習の問題の数（`target_count`）で出す（いまは 10 と書いてある）
- 練習のとき、カードのボタンは本番と違う所へ行く：
  - 『リトライ』：`practice_director.retry_run()` を呼ぶ（なければ何もしない）。`game_state.start_game()` は呼ばない
  - 『メニュー』：`practice_director.leave_to_menu()` を呼ぶ（なければ今までどおり）
  - 「◯ 良い」「× 悪い」：画面の反応は本番どおり、評価は送らない（`record_results` が false のとき）
  - 『問題履歴』と『◀ 戻る』は本番どおり
- 練習の試合は戦績（MatchHistory）にもハイライト（MatchReel）にも入らないことを確かめる（入っていたら止める）

### 3.4 コーチが光らせる所（`game_world.gd`）

```gdscript
## 画面のコーチが光らせる本物の部品。なければ null。
func practice_coach_target(id: StringName) -> Control
```

| id | 部品 |
|---|---|
| `&"pause_panel"` | ポーズ画面の真ん中の列全体 |
| `&"pause_bgm"`・`&"pause_sfx"` | BGM・効果音のスライダー（見出しの文字ごと） |
| `&"pause_resume"`・`&"pause_skip"`・`&"pause_title"` | 『ゲームに戻る』・『この レッスンを とばす』・『タイトルに戻る』 |
| `&"result_card"` | リザルトのカード全体 |
| `&"result_score"` | 大きな数字と「正解 / 3問」 |
| `&"result_stats"` | 「正答率」「連続正解」「時間」の3つ |
| `&"result_explain"` | 解説の文 |
| `&"result_rate"` | 「◯ 良い」「× 悪い」の2つ |
| `&"result_history"`・`&"result_retry"`・`&"result_menu"` | 『問題履歴』・『リトライ』・『メニュー』 |
| `&"history_back"` | 問題履歴の『◀ 戻る』 |

- ほかに、監督が知りたい出来事：ポーズを開いた・閉じた（`signal practice_pause_changed(paused: bool)` を `game_world.gd` に）、評価を押した・問題履歴を開いた・閉じた（`signal practice_result_action(action: StringName)`：`&"rated"`・`&"history_opened"`・`&"history_closed"`。`gameplay_hud.gd` から出して `game_world.gd` が中継してもよい）
- カードは死ぬ演出のあとに出る。カードが出たことが分かるよう `func practice_result_card_visible() -> bool` も足す

### 3.5 テスト

- `tests/practice_unit.gd`：`finish_with_clear`・`real_result_screens` の写し、練習の問題を使い切ると CLEAR になること、`record_results` が false のとき評価を送らないこと、HUD の「/3」
- 本編の既存テスト（HP・押し合い・結果の演出・横移動・ドアの選択肢・オンラインメニュー・壁の速さ）と、コース①の実機の通しテスト（`tests/practice_smoke_bootstrap.gd`）が今までどおり通ること
- ウィンドウありで、ミニ本番の始まり方（開始の画面・空撮・カウントダウン）と、練習の CLEAR・GAME OVER のカードを目で確かめる

## 4. 担当 C：舞台の小物

### 4.1 看板の壁の絵とキー

`PracticeSignWall.set_panels()` に足す：

- `{"key": &"space", "picture": &"space"}`：横長の「スペース」キー
- `{"key": &"digits", "keys": ["1", "2", "3"]}`：1枚のパネルに小さなキーを3つ。`tick_panel_key(key: StringName, index: int)` で、そのキーだけ光って ✓
- `{"key": &"esc", "glyph": "Esc"}` は今のままで出せるか確かめる（キーの文字が収まる大きさに）
- 絵：`&"pause"`（「II」の一時停止のしるし）、`&"hatena_cloud"`（雲に乗ったハテナ）、`&"hatena_dance"`（おどるハテナ）。手で描く（外のテクスチャは使わない）

### 4.2 ハテナ `HatenaGuide` に足す

```gdscript
func offer_hand(on: bool) -> void        # 片手を上に出して待つ（ハイタッチ）
func hand_point() -> Vector3             # 出している手の先の位置（ゲーム画面の座標）。雲の高さ込み
func high_five() -> void                 # 「パチン！」の音（仮の音でよい）とキラッ、手を引っこめて喜ぶ
func set_dancing(on: bool) -> void       # おどりをくり返す（止めるまで）。ポーズで木が止まると、その場でぴたっと止まる
```

- 雲に乗って浮かんだまま、横へすべるように動く（`hop_to` の雲版）：`glide_to(pos: Vector3, seconds := 0.8) -> Signal`

### 4.3 ハテナの小窓 `HatenaPortrait`（新しい `scripts/world/practice/hatena_portrait.gd`）

ポーズ画面・リザルトのカードの上では、ステージの 3D のハテナは暗い幕の下になって見えない。そこで、コーチの層（106）に、雲に乗ったハテナを小さな 3D の窓で出す（自分専用の SubViewport・World3D・カメラ・光、背景は透明）。

```gdscript
class_name HatenaPortrait extends Control   # PROCESS_MODE_ALWAYS（ポーズ中も動く）
func setup(quality: String) -> void
func slide_in(corner := &"bottom_right", seconds := 0.4) -> Signal   # 画面の端から雲で入ってくる
func slide_out(seconds := 0.3) -> Signal
func play(action: StringName) -> void    # HatenaGuide と同じ名前（&"wave"・&"point"・&"cheer"・&"clap" など）
func bubble_anchor() -> Vector2          # 頭の上の画面の位置（吹き出しの付け根）
```

- 大きさは画面の高さの約 1/4。右下の角から少し内側。光らせる部品にかからない位置は、コーチ（D）が `position` で決めてよい

### 4.4 テスト

- `tests/practice_props_preview_runtime.gd` に足して、新しい絵・キー・ハテナの動き・小窓を撮る（`artifacts/practice_props/`）。撮った画面は自分で開いて見る

## 5. 担当 D：画面のコーチとメニュー

### 5.1 画面のコーチ `PracticeCoach`（新しい `scripts/practice/ui/practice_coach.gd`）

台本②の 1.2 のとおり。ポーズ画面・リザルトのカード（ゲーム画面）と、メインメニューの両方で使う。

```gdscript
class_name PracticeCoach extends CanvasLayer   # layer 105。PROCESS_MODE_ALWAYS
signal exit_requested                          # Esc（ポーズ画面の上では『ゲームに戻る』も）でコーチを抜けたい
## targets を光らせ（ゆっくり脈打つ枠）、まわりを少し暗くする。clickable なら targets だけ押せる（ほかは押せない）。
## clickable が false なら、どれも押せない（見せるだけ）。
func focus(targets: Array, clickable := true) -> void
func clear_focus() -> void
## ハテナから吹き出しを出す。seconds < 0 は台本①の 1.2 の長さ。返り値は出し終わりの signal。
## 説明だけの段階（wait_for_press = false）は Enter・スペースで早送りできる。
func say(text: String, seconds := -1.0) -> Signal
## 吹き出しの付け根（画面の座標を返す Callable）。光っている所と重ならない位置に、画面の端で止めて出す。
func set_anchor(anchor: Callable) -> void
## ハテナの小窓（C の HatenaPortrait）を出す・しまう。ゲーム画面のコーチで使う
func show_portrait(on: bool) -> void
func portrait() -> Control
## コーチを終える（光・暗い幕・吹き出し・小窓を消し、押せない仕組みも外す）
func close() -> void
```

- 押せない仕組みは、マウス（クリック）だけでなくキーボード（フォーカスの移動・Enter）も止める。光っている部品のボタンは Enter でも押せる
- ポーズ画面の上（`get_tree().paused`）でも動く。スライダーは光っている間は動かせる

### 5.2 メニューの続き（2-6 とクリア）

- メインメニューが開いたとき：
  - `PracticeSession.launch_next` が空でなければ、そのコースをすぐ始める（`PracticeSession.launch`）。値は消す
  - `PracticeSession.resume_in_menu` が `{"course": "c2", "step": "2-6", ...}` なら、メニューのコーチ `PracticeMenuGuide`（新しい `scripts/practice/menu/practice_menu_guide.gd`）を作って 2-6 を始める。値は消す
- **ハテナ**：メニューの 3D の背景（LiveViewport の世界）にいる、のこぎりの操縦席のハテナが雲に乗って出てきて、画面の右側（メニューの UI にかからない所）に浮かぶ。C の `HatenaGuide` を背景の世界に置き、出てくる間は操縦席のハテナを隠す（`saw_chase_controller.gd` に `set_operator_hidden(hidden: bool)` と、操縦席の位置を返す道具を足す）。終わったら雲で席へ戻り、席のハテナを出す。吹き出しは背景のカメラで頭の上を画面の座標に直して付ける（SubViewportContainer の大きさ・位置も入れる）
- **2-6**：台本どおり。光らせる部品は `main_menu.gd` に `func practice_coach_target(id: StringName) -> Control` を足して返す：
  - モード選択：`&"mode_ten"`（10問チャレンジ）・`&"mode_endless"`・`&"mode_online"`
  - 設定：`&"subject"`（教科の ◀ ▶ と文字）・`&"grade"`・`&"difficulty"`・`&"llm"`（出題）・`&"players"`・`&"customize"`・`&"start"`（ゲーム開始）
  - 「10問チャレンジ」を押したら本物の設定の画面に変わり、教科を変えたら次へ（メニューの今の動きをそのまま使う）
- **クリア**（メニューの設定の画面の上）：ハテナが雲で真ん中の手前へ →「これで じゅんび ばっちり！」→ クリアカードとスタンプ（`GameManager.mark_practice_stamp("c2", star)`。★は `resume_in_menu.star`）→「さあ ほんばん！ がんばってね」。カードは B の `PracticeOverlay.show_clear_card` を使ってよい（ファイルは直さない）
  - ［ほんばんを はじめる］：今の設定のまま『ゲーム開始』を押したのと同じ（`_on_start_pressed` と同じ流れ。本物の出発の演出）
  - ［あとで］：設定の画面のまま残る。コーチを終え、ハテナは席へ戻る
  - 初回の案内から始めたとき（`resume_in_menu.first_run`）は［ほんばんを はじめる］が選ばれた状態
- Esc でいつでもコーチを抜けられる。抜けたら 2-6 を とばしたことにして、クリアへ進む
- 文字は全部 `PracticeTexts` の ID（`c2.menu.*`・`c2.clear.*`）

### 5.3 テスト

- `tests/practice_menu_coach_bootstrap.gd`（ウィンドウあり）：`PracticeSession.resume_in_menu` を入れてメニューを開き、2-6 からクリア、［あとで］まで通す。もう1回［ほんばんを はじめる］でゲーム画面へ移ることも確かめる。設定の保存先はテスト用に差し替え、教科などの設定はテストの後で元に戻す。要所を `artifacts/practice_menu/` に撮って、自分で開いて見る

## 6. 担当 B：ゲーム画面の台本側

### 6.1 レッスン（`scripts/practice/courses/course_2.gd`）

[course2_script.md](course2_script.md) の 2-1〜2-5 を台本どおりに作る。文字は `PracticeTexts` の ID（`c2.*`）。

- 2-1：コンベアを止める・見えないさく（①と同じ）。看板（`&"space"` と `&"hatena_cloud"`）。ハテナは雲でプレイヤーの3m前、手は床から約2.4m（立ったままでは届かず、ジャンプで届く。実画面で合わせる）。ハイタッチは「プレイヤーが空中にいて、手の真下（横に 1.0m 以内）」。3か所（x 0 → +4 → −4）。6秒スペースなしで点滅と「スペースを おして！」
- 2-2：看板（`&"digits"` と `&"hatena_dance"`）。1・2・3 のエモートで、そのキーに ✓。ハテナもいっしょにおどる。6秒なにも押さないとき
- 2-3：看板（`Esc` と `&"pause"`）。ハテナはおどりつづける。Esc でポーズ画面 → D のコーチ（A の `practice_coach_target`・C の小窓）で台本どおり。『ゲームに戻る』（Esc でもよい）で ✓。8秒 Esc なしのとき
- 2-4：`finish_with_clear`・`real_result_screens`・`hp_enabled`・本番どおり・`show_score`・`record_results = false`。`start_practice_round(..., STATE_WAITING_START)`。ハテナはいまの壁の前（①と同じ）、続けて正解した数を数える。GAME OVER なら「ざんねん！」→ コーチで『リトライ』だけ光らせ「『リトライ』で もういちど」→ A の `retry_run()` で開始の画面から。3回失敗で `slow_auto_speed`。ノーミス（ハートが減らない）で★
- 2-5：CLEAR のカードの上で、コーチが順に案内。『メニュー』を押したら（A の `leave_to_menu()`）、`PracticeSession.resume_in_menu = {"course": "c2", "step": "2-6", "star": ★, "skipped": とばした数, "first_run": from_first_run}` を入れてメニューへ
- 監督（`PracticeDirector`）に `retry_run()`・`leave_to_menu()` を足す。ポーズ中もコーチと吹き出しが動くこと（監督の進め方を PAUSABLE のままにするなら、コーチの間だけ ALWAYS にするなど）
- ①のクリアカードの［つぎの コースへ］：`PracticeSession.launch_next = "c2"` を入れてメニューへ（メニューがすぐ②を始める。D）
- `PracticeCatalog` の c2 を `available = true` に

### 6.2 テスト

- 新しい `tests/practice_course2_smoke_bootstrap.gd`（ウィンドウあり）：②を 2-1 から 2-5 の『メニュー』まで、キー入力とクリックで通す（2-4 は一度わざと負けて『リトライ』、もう一度でクリア）。D のメニューの続きができていれば、2-6 からクリアの［あとで］まで続ける。要所を `artifacts/practice_course2/` に撮って、自分で開いて見る
- コース①の通しテスト（`tests/practice_smoke_bootstrap.gd`）も通ること

## 7. 作りながら決めたこと（2026-10-25）

- **大人向けに書き直した**（ユーザーの指示「セリフと内容が幼稚すぎるので、もっと大人向けに」）：文字は漢字かな交じり、ハテナはくだけた口調（だ・よ）、子どもっぽい演出を外して短く、練習の問題は一般常識くらい。台本①②は v0.2。③〜⑤は実装の前に同じ方針で書き直す（コース名とクリアカードの文字は先に直した）
- **2-1**：ハテナとのハイタッチ3回をやめ、浮いた的に1回タッチ。的は正面だと看板の文字に重なるので、画面の右（x = −2.6）に置く。C の `offer_hand`・`hand_point`・`high_five`・`glide_to` は使わなくなった（道具は残してある）
- **2-2**：1・2・3 を全部出す・ハテナもいっしょにおどる、をやめ、エモートを1つ出せば終わり
- **2-4 の問題に解説**：本物のリザルトのカードと問題履歴に出るので、短い解説（`c2.run.e1`〜`e3`）を付けた。解説がないと GAME OVER のカードに「解説を読み込み中…」が出たままになっていた
- **ハテナが画面の外のとき**（①の 1-6 で海を映している間など）は、吹き出しをしっぽなしで画面の上の真ん中に出す
- **コーチ（D）**：`focus` の第3引数 `grab_focus`、`say` の `hold`（押すまで残す）を足した。2-6 で押せるのは『10問チャレンジ』・教科・学年だけ（むずかしさ・出題・人数・カスタマイズ・ゲーム開始は見せるだけ。途中でオンライン出題に変わったりカスタマイズが開いたりしないように）
- **本編側（A）**：開始の画面で Enter を押せるかは `game_world.practice_start_ready()`。練習のときは CLEAR のカードにも最後の問題の解説を出す
- **担当 B は途中で止まった**（安全確認の仕組みが応答しなくなったため）。残りは監督役が仕上げた

## 8. 進め方

1. A・B・C・D は並行して作る
2. それぞれ自分のテストを流して報告する
3. 最後に監督役が全部をそろえ、②の通しテスト・①の通しテスト・本編のテストを流し、スクリーンショットで確かめる
