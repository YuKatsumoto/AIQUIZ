# スカイゲートをつなぐ（W6）：できたこと・決めた数字・確かめ方

2026-10-19。`skygate_build_plan.md` の W6「つなぐ」。W1〜W5・W7 の部品で、引き分けから帰還までを監督（`HeliSuddenDeathDirector`）の新しい流れにした。
引き分けの種目は「ひらけ！パラシュート」から **「つきやぶれ！スカイゲート」** に替わった（パラシュートのコードは残してある）。
ユーザーが寝ている間に任されて仕上げたので、絵コンテで相談せずに決めた所がある（第6章。確認を待つ）。

## 1. ファイル

| ファイル | 中身 |
| --- | --- |
| `scripts/world/sudden_death/floatplane/floatplane_staging.gd`（新規） | `FloatplaneStaging`：水上機の場面（乗り込み・機内の巡航・降下・着地台の迎え・帰還）。機体・水路・昇降台・人の動き・カメラ |
| `scripts/world/sudden_death/heli_sudden_death_director.gd` | 場面 `BOARD`・`DROP`・`REBOARD` を足した。`descent_mode() == "floatplane"` の種目は `FloatplaneStaging` で進める。Space で飛ばす口（`can_skip`・`skip_presentation`）・カメラの口（`stage_camera`）。ヘリはヘリの種目があるときだけ作る |
| `scripts/world/sudden_death/sudden_death_presenter.gd` | 監督への口の空の実装（`round_cleared`・`begin_round`・`sky_spawn`・`fall_center`・`landing_float`・`lander_point`・`set_landers_hidden`・`hide_banner`） |
| `scripts/world/sudden_death/games/sky_gate_presenter.gd` | 監督への口（`landing_float`・`lander_point`・`set_landers_hidden`・`fall_center`・`hide_banner`）。見下ろしのカメラに問題文の看板の 4 隅を入れる |
| `scripts/world/sudden_death/floatplane/sudden_death_floatplane.gd` | `RAMP_GROUND`（1.8）：スロープを床より 20° 下まで下ろして、着地台の浮き輪に端を載せる |
| `scripts/core/game_state.gd` | `SUDDEN_DEATH_GAMES = ["sky_gate"]`、`_create_sudden_death_game` が `SkyGateGame`、問題の数は 20。`LEGACY_SUDDEN_DEATH_GAMES = ["parachute"]` と、テスト用の `debug_sudden_death_kind` |
| `scripts/world/game_world.gd` | Space を監督へ渡す（`skip_presentation()` が受けたら飲み込む） |
| `scripts/world/sudden_death/games/sky_gate_board.gd`・`assets/sudden_death/sky_gate/` | W5 の変更：問題文の帯を大きな看板 `QuestionSign` に（第4章） |
| `assets/sudden_death/sky_fx/sky_fx_islands.glb` | W7 の残り：島の作り直し（礁の外をなだらかに）をライブの Blender で行った |
| `tests/sudden_death_v2/skygate_runtime.gd`・`_bootstrap.gd`（新規） | 実ゲームの通し（第5章） |
| `tests/sudden_death_v2/parse_check.gd`（新規） | 変えたスクリプトが読み込めるか |
| `tests/sudden_death_v2/parachute_runtime.gd` | パラシュートを `debug_sudden_death_kind` で指定して動かす |

## 2. 流れ（監督の場面）

```
IDLE → BRANCH（決着演出・9.6 秒で台座の横のスタンドを持ち上げる準備）→ REVEAL（大型ビジョンで種目発表。引きは乗り込みの初めの画へ）
→ BOARD（乗り込み、約 13 秒）→ 雲の覆い → SKY（機内の巡航。準備と問題を待つ。最低 3 秒）
→ DROP（降下、約 7 秒）→ VENUE（ルールカード → 本戦）
   ├ 2 人とも突破 → presenter.round_cleared() → 暗転（1.6 秒。2026-10-20 に迎えの REBOARD をやめた）→ DROP（短い版、機内から）→ VENUE（「ROUND n」→ 3・2・1 → 次のラウンド）
   └ 決着 → presenter.finale_done() → EXTRACT（勝者のダンス 3.6 秒 → 水上機の迎え → 駆け込む）→ 雲の覆い
→ HOME（帰還：台座の上を低く通る水上機から勝者が飛び降りる。敗者は幽霊）→ 決着演出へ戻る → DONE
準備の失敗・時間切れ：SKY から雲の覆い → ABORT（今までと同じく引き分けのまま）
```

- 種目ごとの分かれ目は `presenter.descent_mode()`：`"floatplane"`（スカイゲート）・`"skydive"`（パラシュート）・`"ladder"`。ヘリの流れはそのまま残した。
- 本戦へ渡すとき（`_handover`）、降下の 2 人（本物のアバター）は本戦の人形と同じ位置（`presenter.sky_spawn`）にいて、隠して入れ替える。カメラは切らずに 1.6 秒かけて見下ろしへ寄せる。
- 時刻表とカメラの詳しい数字は `c130_float.md` 第8章。

## 3. Space で飛ばす（c130_float.md 第6章・heli_drop.md 3.1）

| 場面 | 飛ばすと |
| --- | --- |
| 乗り込み（BOARD） | 雲の覆いへ（2 人は機内の座席でベルトを締めた姿で空へ）。スタンドは雲の中で元に戻る |
| 降下（DROP） | 本戦の見下ろしへすぐ（0.3 秒の白い閃光） |
| ~~ラウンドの間の迎え（REBOARD）~~ | 2026-10-20 にやめた（暗転のあと短い降下）。短い降下は DROP と同じく飛ばせる |

ルールカードを閉じるのは今までどおり Enter。本戦では Space はルールに渡すが、スカイゲートは使わない。

## 4. 問題文の看板（W5 の変更、sky_gate.md 第8章の決定）

- 帯（13 × 1.8 m）を、**ボードより大きな看板（17 × 6 m、白い面 16.28 × 5.28 m）** に替えた。ボードの奥の辺の上に載り、奥へ 3.6 m はみ出す。
- 吊るドローンを 4 機から **6 機** に（看板の 4 隅とボードの手前の 2 隅）。
- 文字はこれまでどおり `Label3D`。長い問題は真ん中に近い区切り（空白・かっこ・読点の後）で 2 行に分ける（Label3D の折り返しに任せると 3 行になって看板からはみ出した）。
- 見下ろしのカメラは看板の 4 隅も画に入れる。ルール（パネルの寸法・判定）は変わらない。
- 描く回数（標準の画質）はボードだけで 52 → 73 回（ドローン 2 機と看板の分）。

## 5. 確かめ方と結果

```powershell
# 実ゲームの通し（画と report.json は artifacts/sudden_death_v2/skygate_runtime/<case>/）
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/sudden_death_v2/skygate_runtime_bootstrap.gd -- case=p1
#   case=p1（ROUND 1 の 2 枚目で P2 がまちがえる）/ round2（ROUND 2 まで）/ skip（Space で乗り込みと降下を飛ばす）/ abort（準備の失敗）
# スクリプトが読み込めるか
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/sudden_death_v2/parse_check.gd
```

テストは本物のキー（`Input.parse_input_event` の WASD・矢印・Enter・Space）で操作する。自動のテストではウィンドウにフォーカスが無いことがあるので、
`GameWorld._push_focus_lost` を毎フレーム false にしている（フォーカスが無いと押しっぱなしを 0 にする作りのため）。

確かめること：場面が順に進む・勝者が合う・乗り込みで昇降台とスロープの端がつながる（0.25 m 重なる）・迎えでスロープの端が着地台の浮き輪の上（中心から 3.6 m、
海から 0.79 m）に載る・降下から本戦へ渡すとき 2 人の位置が本戦の位置と同じ・Space で乗り込みが 5 秒以内に終わる。

結果は第7章。

## 6. 決めたこと（ユーザーの確認を待つ）

| 項目 | 決めたこと | 理由 |
| --- | --- | --- |
| 乗り込みの飛んでくる高さ | 台座の上を床から 5.8 m、持ち上がったスタンドの下をくぐる | 床の 20 m 上だと持ち上げたスタンドにぶつかる |
| 乗り込みの 06 のカメラ | 水路の上の高めから（P1 は奥） | 床の高さからは昇降台が床の縁に隠れる |
| ラウンドの間の迎え | 着地台の上を越えて着水 → 後ろ向きに戻ってスロープを浮き輪に下ろす（約 6.5 秒） | 乗り込みと同じ「後ろ向きで寄せる」形にそろえた |
| 勝者の迎え | ダンスのあと同じ迎え。勝者だけ駆け込む | |
| 帰還の向き | ゴールの側から入り、コースの側へ抜ける。勝者は台のゴールの側に着地して振り返って跳び乗る | ゴールへ向かって通ると、すぐ前の観客席をよけられない |
| 降下の高さ | 機体は空のセットの下の雲の層の少し上。2 人は雲の層をつき抜けて本戦の位置へ（約 26 m） | 巡航の画で機体の下がすぐ海に見えないように |
| 巡航の海 | 落ちる点の 200 m 下。降下の間に 900 m 下（本戦の初め）へ下げる | 海の板（4 km 四方）のふちが見えないように |

## 7. 結果（2026-10-19）

実ゲームの通し（`skygate_runtime.gd`、1280×720・60fps 固定・画質「標準」）。4 通りとも失敗 0。

| case | 場面と長さ（秒） | 勝者 |
| --- | --- | --- |
| p1 | 分岐 11.0 → 発表 3.4 → 乗り込み 13.2 → 巡航 3.0 → 降下 7.2 → 本戦 27.2 → 勝者の迎え 10.2 → 帰還 8.7 → 決着演出 | P1 |
| round2 | …降下 7.2 → 本戦（ROUND 1）44.6 → ラウンドの迎え 6.9 → 短い降下 3.9 → 本戦（ROUND 2）14.1 → 勝者の迎え 10.2 → 帰還 8.4 | P2 |
| skip | 乗り込みの 2.0 秒で Space → 雲の覆い（乗り込みは 2.5 秒で終わる）、降下の 0.8 秒で Space → 見下ろし | P1 |
| abort | 準備の失敗：乗り込み → 巡航 0.4 秒 → 雲の覆いで台座へ → 引き分けのまま | 引き分け |

- 乗り込み：昇降台の外の端（x 16.40）とスロープの端（x 16.15）が 0.25 m 重なり、高さの差 0.02 m。
- ラウンドの迎え：スロープの端は着地台の中心から 3.60 m、海から 0.79 m（浮き輪の上面 0.8 m）。
- 降下から本戦へ渡すとき、2 人の腰と本戦の人形の位置の差は 0.00 m（Space で飛ばしたときは白い閃光で隠す）。
- そのほか：`sky_gate_unit`（176 の確かめ、失敗 0）、`parachute_unit`（29、失敗 0）、`parachute_runtime` case=p1（ヘリの流れが今までどおり動くか。42、失敗 0）、`stage_gate_check`（すき間 4.5 m、失敗 0）、W4 の `sky_gate_runtime` case=main（19、失敗 0）、`parse_check`（読み込めないスクリプト 0）。

## 8. 残っていること・気になる所

- 第6章の決めごとはユーザーの確認を待つ（絵コンテで相談していない）。
- ~~音は今ある音で代用（スタンドが上がる＝`countdown_rumble`、着水＝`wall_land`、逆推力＝`rotor_spool`、緑のランプ＝`countdown_beep` など）。水上機のエンジンの音はない。~~ → 2026-10-20 に専用の音と水上機のエンジンの音を入れた（`docs/sound_effects.md`「サドンデス」）。
- 巡航の外の画では、空のセットの海の板（4 km 四方）の端が地平線の少し下に見えることがある。
- 帰還の初め、ゴールの観客席の上空から下りてくる機体がカメラのすぐ上を通る（迫力として残した）。
- 製品版（リリースのビルド）では今までどおりサドンデスは切ってある（`QuizGameState.sudden_death_available = OS.is_debug_build()`）。
