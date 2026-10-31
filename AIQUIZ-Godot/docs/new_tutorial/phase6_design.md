# 段階6 CPU とコース③ の設計（v1）

2026-10-25。[計画書](plan.md) の段階6（CPU とコース③「2人対戦」）の設計。
台本は [course3_script.md](course3_script.md)（v0.2）。共通の約束は [course1_script.md](course1_script.md) の1章・[course2_script.md](course2_script.md) の1章、土台は [foundation_design.md](foundation_design.md)・[phase4_design.md](phase4_design.md)・[phase5_design.md](phase5_design.md)。旧チュートリアルは参照しない（撤去済み）。

## 0. 段階6で「できた」と言える状態

1. コース選択で③が遊べる。②のクリアのあと［次のコースへ］でも③が始まる（`PracticeSession.launch_next`）
2. 3-0：「誰と練習する？」で［2人で］［CPUと］を選べる。［2人で］は P2 が右の Ctrl を押して参加する
3. CPU と：3-1〜3-8 が台本どおりに通る。CPU（P2）はキーボードと同じ入力口から台本どおりに動き、頭の上に「CPU」の名札
4. 人どうし：3-1〜3-8 が「2人とも」「どちらかが」の条件で通る（3-6・3-7 は同時に行い、役を入れかえてもう一度）
5. 3-5：のこぎりが本番どおりに走り、ハテナが操縦席に座る。捕まったらゴーストにせず、まきもどし
6. 3-6・3-7：指定したプレイヤーをアウトにして、本番のゴーストの演出から始まる（2回目から Enter で飛ばせる）。突進が当たる・よけるが分かる
7. 3-8：壁1枚 → 本番のゴールレース → 本番のスコアタワーの演出と判定
8. 本編（10問・エンドレス・2人・オンライン・リプレイ）とコース①②の動きは変わらない

## 1. 担当とファイル

| 担当 | 触るファイル |
|---|---|
| A（本編側） | `scripts/core/game_state.gd`・`scripts/core/match_rules.gd`・`scripts/world/game_world.gd`・`scripts/world/ghost_shark_ride_controller.gd`（とゴーストの演出のファイル）・`scripts/world/saw_chase_controller.gd`・`scripts/world/camera_controller.gd`・`scripts/ui/gameplay_hud.gd` と 2人のカード（`duo_hud` など）・`scripts/world/result_ceremony_director.gd` などゴールとスコアタワーの所・`tests/practice_unit.gd` |
| B（台本側） | `scripts/practice/` の下（**`practice_cpu.gd`・`ui/practice_pick_card.gd` を除く**）・新しい `scripts/practice/courses/course_3.gd`・新しいテスト `tests/practice_course3_smoke_*.gd` |
| C（CPU と小物） | 新しい `scripts/practice/practice_cpu.gd`・新しい `scripts/practice/ui/practice_pick_card.gd`・`scripts/world/practice/` の下（看板の絵）・新しいテスト `tests/practice_cpu_*.gd` |

- 担当どうしで同じファイルを触らない。ほかの担当の道具が要るときは、この文書の約束どおりに呼ぶ。まだないうちは、スクリプトのパスを `load` できるか・`has_method` で確かめてから呼ぶ（class_name を直接書かない）。約束と違うことが必要になったら、自分で相手のファイルを直さず報告に書く
- 作業ツリーには、ほかのセッション（サドンデスの演出など）の変更も入っている。`git checkout`・`stash`・`reset`・`restore`・コミットはしない。共通のファイル（`game_state.gd`・`game_world.gd` など）は編集の直前に読み直す
- 文字は全部 `PracticeTexts` の ID（`c3.*`。監督役が台本 v0.2 のとおりに入れてある）。台本にない文字を作らない
- 座標はゲーム画面のもの（x は +が画面の左、z はコンベア上の前）。2人の開始の位置は P1 x = +1.5、P2 x = −1.5

## 2. 担当 A：本編側の約束

### 2.1 CPU の入力口

```gdscript
## 練習で P2 を CPU にする。true のあいだ、P2 のキーボードの入力（矢印・右の Ctrl・8 9 0）は使わず、
## practice_set_cpu_input で渡された入力を、キーボードと同じ所（移動・ジャンプ・エモート・押し合い・ゴーストの照準とため）に使う。
var practice_p2_cpu := false
## CPU の入力（毎フレーム渡す。渡さなかったフレームは前の値のまま）。
## axis：移動（x は +が画面の左、y は +が前）。jump：ジャンプのキーを押している（押した瞬間にジャンプ。
## ゴーストのときは押しているあいだためて、離すと突進）。emote：1〜3（0 = なし。押した瞬間に出す）。
func practice_set_cpu_input(axis: Vector2, jump: bool, emote := 0) -> void
```

- 人どうしのときは今までどおり P2 のキーボードで動く
- P2 の参加（右の Ctrl）は B が `Input` で見て受け付ける。A は何もしなくてよい

### 2.2 2人の練習の見た目

- `start_practice_round(quizzes, 2, rules, ...)` で、本番の2人のカメラ・左下と右下のカード（得点・連続正解の炎・ハート・OUT）・大きい壁の文字になる（練習でも）
- `practice_p2_cpu` のとき、P2 の頭の上に「CPU」の名札（オンラインの名札と同じ見た目）
- 2人のとき、練習の HUD の「正解: 0 問題: 1/3」は出さない（2人のカードを使う）

### 2.3 のこぎり（3-5）

- `MatchRules.saw_enabled` で、練習の中でのこぎりが本番どおりに走る（入ってくる・加速・14m 後ろまで迫る・最初の2秒は待つ・危険の色）。操縦席のハテナも本番どおり座っている
- `MatchRules` に足す：

```gdscript
enum Saw { NORMAL, REPORT_ONLY }
## REPORT_ONLY：のこぎりに捕まっても、ゴーストにもアウトの判定にもしない（体がばらばらになる演出は本番どおり）。
## practice_saw_caught(player_index) を出すだけ。監督が practice_revive と practice_place_player で戻す。
var saw := Saw.NORMAL
```

- signal `practice_saw_caught(player_index: int)`
- `saw_enabled` を false に戻したら、のこぎりは本番の「止まって操縦席に戻る」動きで片づく

### 2.4 ゴースト（3-6・3-7）

```gdscript
## player_index をアウトにして、本番の脱落の演出からゴーストシャークに乗せる（ghost_ride_enabled のとき）。
## skip_intro なら、演出を短くして（または飛ばして）すぐ乗れる状態にする。
func practice_make_ghost(player_index: int, skip_intro := false) -> void
```

- signal：`practice_ghost_ready(player_index)`（照準を動かせるようになった）、`practice_ghost_dash(player_index)`（突進した）、`practice_ghost_hit(attacker, victim)`（当たった）、`practice_ghost_missed(player_index)`（外れた・突進が終わった）
- 本番の演出の途中、Enter で飛ばせる（`skip_intro` が false でも、2回目からは監督が `practice_skip_ghost_intro()` を呼ぶ）
- CPU のゴーストは 2.1 の入力口で動く（axis で照準、jump の長押しでため、離して突進）
- `practice_revive` でゴーストから普通のプレイヤーに戻せる（サメ・照準・メーターの見た目も片づく）
- 練習の中で、ゴーストに当てられた相手が海へ落ちないよう、`MatchRules.fence_enabled` のさくはゴーストの吹き飛ばしにも効く

### 2.5 ゴールとスコアタワー（3-8）

```gdscript
## 用意した問題を全部終えたら、本番の2人の10問と同じく、ゴールレース（GOAL へ走れ）→ ゴール → スコアタワーの演出と判定へ進む。
var finish_with_goal := false   # MatchRules に足す
```

- ゴールラインとゴールのスタンドを、最後の壁の後ろに本番と同じ形で出す（練習でも）
- 判定までの本番の流れ（状態 GOAL_RACE → RESULT_CEREMONY、スコアタワーの式、勝ち負け）をそのまま使う。判定が出たら signal `practice_ceremony_finished(winner: int)`（0 = 引き分け）。判定のあとのカード・メニューへの移動は出さない（監督がクリアへ進む）
- ハートと正解数の持ち越し：`practice_set_score(player_index, correct: int)` を足す（ハートは `practice_set_hp`）

### 2.6 テスト

- `tests/practice_unit.gd`：`practice_p2_cpu` と `practice_set_cpu_input` で P2 が動く・跳ぶ、`saw = REPORT_ONLY` で捕まってもアウトにならず知らせが出る、`practice_make_ghost`、`finish_with_goal` でゴールレースへ進む、`practice_set_score`
- 本編の既存テスト（HP・押し合い・結果の演出・横移動・ドアの選択肢・オンラインメニュー・壁の速さ・のこぎり・ゴースト）と、コース①②の通しテストが今までどおり通ること

## 3. 担当 C：CPU と小物

### 3.1 CPU `PracticeCpu`（新しい `scripts/practice/practice_cpu.gd`、Node）

監督が作って子にする。毎フレーム、いまの「やること」に合わせて A の `practice_set_cpu_input` を呼ぶ。台本にない動きはしない。

```gdscript
class_name PracticeCpu extends Node
func setup(game_state: QuizGameState) -> void
func idle() -> void                                   # 何もしない（入力 0）
func wave() -> void                                   # その場で手をふる（エモート1を1回）
func move_to(x: float, z: float, speed := 1.0) -> void   # その位置へ動いて止まる（speed は 0〜1。1 が全力）
func go_door(door: int, haste := 0.5) -> void          # いまの壁のそのドアの前へ寄り、壁へ向かって進む（haste 0 = ゆっくり〜1 = 前へ全力）
func wander(x_range: Vector2, speed := 0.4) -> void    # 床の上を左右にゆっくり行き来する（ゴーストの的）
func push_toward_p1() -> void                         # P1 のほうへ押し続ける（押し合い）
func practice_moves(p1_like := true) -> void           # 左右・前後に少しずつ動いて、1回ジャンプする（3-1 のお手本）
func ghost_attack(target_player := 1, perfect := false) -> void  # ゴーストのとき：相手を狙い、ためて、突進する（よけられる速さ）
func is_arrived() -> bool
signal finished(action: StringName)                    # move_to・go_door などが終わった
```

- 人どうしのときは使わない（`practice_p2_cpu` は false）
- ゴーストの狙いは、構えたあとは向きを変えない（本番どおり）。ためは約1.2秒、PERFECT は狙わない（よけられる強さ）

### 3.2 相手を選ぶカード `PracticePickCard`（新しい `scripts/practice/ui/practice_pick_card.gd`、CanvasLayer）

- 「誰と練習する？」と［2人で］［CPUと］。矢印キーと Enter・マウスで選べる。Esc は［CPUと］
- ［2人で］を選んだら「P2は右Ctrlで参加」を出して待つ。右の Ctrl（`KEY_CTRL` で右側。テンキーの 0 でも受けてよい）が押されたら「P2が参加」を出して閉じる
- signal `chosen(with_cpu: bool)`。文字は `c3.pick.*`

### 3.3 看板の絵（`scripts/world/practice/sign_wall.gd`）

- `{"key": &"p1_keys", "keys": ["W", "A", "S", "D"], "sub": "スペース"}` のように、キーの組とその下の小さな文字を出せるようにする（P1：W A S D ＋ スペース、P2：↑ ↓ ← → ＋ 右 Ctrl）
- 絵：`&"push"`（2人が押し合う）、`&"push_again"`（離す → 押す）

### 3.4 テスト

- `tests/practice_cpu_bootstrap.gd`（ウィンドウあり）：練習の2人の場で、CPU の各動き（move_to・go_door・push_toward_p1・wander・ghost_attack）を A の入力口で動かし、思った位置へ着く・押し合いになる・ゴーストが突進することを確かめて撮る（`artifacts/practice_cpu/`）。A の入力口がまだないときは、何が足りないかを報告に書く
- 新しい看板の絵を `tests/practice_props_preview_runtime.gd` に足して撮る

## 4. 担当 B：台本側

### 4.1 レッスン（`scripts/practice/courses/course_3.gd`）

[course3_script.md](course3_script.md)（v0.2）の 3-0〜3-9 とクリアを台本どおりに作る。人どうし・CPU との両方の流れを作る。

- 3-0：C の `PracticePickCard`。選んだ結果を `PracticeSession.with_cpu` に入れる（コース選択の段階で決まっていればそれを使う）。ゲーム画面で出す
- 3-1：コンベアを止める・さく。看板（C の `p1_keys`・`p2_keys`）。P1 が矢印キーを押したら「2人のときP1はWASDで動く」と左のパネルの点滅
- 3-2〜3-3：練習の壁（①と同じ速さ）。早い者勝ちの得点と、CPU の go_door の haste で台本の勝ち負けを作る
- 3-4：さく、2人を並べる、押し合い（`local_push_enabled`）。一押しは本編の知らせ（押し合いの出来事）で見る
- 3-5：`saw_enabled`・`saw = REPORT_ONLY`。案内役のハテナは雲で操縦席へ移ったように見せる（案内役を隠して、操縦席のハテナに吹き出しを付ける。吹き出しの付け根は A に道具があれば使い、なければ画面の上）
- 3-6・3-7：`ghost_ride_enabled`・`practice_make_ghost`。2回目から Enter で飛ばせる
- 3-8：`finish_with_goal`・ハートと正解数の持ち越し。ハテナはゴールの審判（スタンドの前へ雲で）
- 3-9：`sudden_death_available` のときだけ一言
- クリア：①と同じクリアカード（★なし）。［次のコースへ］は④がまだ遊べないので、コース選択へ戻る
- `PracticeCatalog` の c3 を遊べるように。②の［次のコースへ］が③を始めるように（`launch_next = "c3"`）

### 4.2 テスト

- 新しい `tests/practice_course3_smoke_bootstrap.gd`（ウィンドウあり）：CPU とで 3-0〜クリアまで、キー入力で通す（3-5 で一度捕まってまきもどし、3-6 で一度外して当てる）。人どうしは P2 の入力をテストから送って、3-1・3-2・3-4 と 3-6/3-7 の役の入れかえを通す。要所を `artifacts/practice_course3/` に撮って、自分で開いて見る
- コース①②の通しテストも通ること

## 5. 進め方

1. A・B・C は並行して作る。B と C は A の道具が来るまで、約束の名前で呼ぶ形にしておく
2. それぞれ自分のテストを流して報告する
3. 最後に監督役が全部をそろえ、③の通しテスト（CPU と・人どうし）・①②の通しテスト・本編のテストを流し、スクリーンショットで確かめる
