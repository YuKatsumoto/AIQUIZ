# スカイゲート本体（W4）：できたこと・決めた数字・確かめ方

> 2026-10-19 追記：時間切れの「つき破る」動き（判定はそのあと）、本戦の中のカットの廃止、ゲーム内の実演によるルールカードは
> `skygate_impact.md`。この文書の G3_Through・G4_Chain・着地のカット・ルールカードの絵（`rule_*.png`）・PASS_TIME 0.8 秒は古い。

2026-10-19。`skygate_build_plan.md` の W4「スカイゲート本体」（ルール・見せ方・HUD・図解ルールカード・空中で動く入力）。
中身は `sky_gate.md` の第2・3・8章と、計画書 1.1 節・4.5 節。乗り込み・降下・迎え・帰還と種目の入れ替えは W6。

## 1. ファイル

| ファイル | 中身 |
| --- | --- |
| `scripts/core/sudden_death/sky_gate_game.gd` | ルール `SkyGateGame`（`SuddenDeathGame` を継承、`kind = "sky_gate"`） |
| `scripts/world/sudden_death/games/sky_gate_presenter.gd` | 見せ方 `SkyGatePresenter`（`SuddenDeathPresenter` を継承） |
| `scripts/ui/sudden_death/sky_gate_hud.gd` | HUD `SkyGateHud`（図解ルールカードを含む） |
| `assets/sudden_death/sky_gate_rules/rule_*.png` | 図解ルールカードの 3 枚の絵（`make_rule_images.py` が絵コンテのコマ 03〜05 から切り出す。960×720）。2026-10-19 に削除（`skygate_impact.md` 第5章のゲーム内の実演に替えた） |
| `scripts/world/sudden_death/games/sky_gate_debug.gd`・`_bootstrap.gd` | 監督なしで遊べるデバッグの入口 `SkyGateDebug` |
| `tests/sudden_death_v2/sky_gate_unit.gd`・`_bootstrap.gd` | ルールのユニットテスト |
| `tests/sudden_death_v2/sky_gate_runtime.gd`・`_bootstrap.gd` | 実画面の通しの確認（デバッグの入口を 1 フレームずつ進めて撮る） |
| `scripts/core/game_state.gd` | 足した口：`set_sudden_death_move(player, move)` |
| `scripts/world/game_world.gd` | 足した口：`_feed_sudden_death_input` の最後で WASD（P1）と矢印（P2）の押しっぱなしを毎フレーム渡す（`_held_move`） |

## 2. ルール（`SkyGateGame`）

判定は全部ここ。見せ方は判定しない。

| 項目 | 値 |
| --- | --- |
| 時計 | `TICK` = 1/240 秒ずつ進める（フレームの長さに関係なく同じ刻み）。押しっぱなしの向きはフレームの間ずっと同じとみなす。30／60／120fps で位置も出来事もまったく同じ（テストで確かめた） |
| ラウンド | ゲート 4 枚。1 枚 8 秒（ROUND 1）・6.5 秒（ROUND 2）・5 秒（ROUND 3 以降）。5 ラウンド × 4 問 ＝ `QUESTION_COUNT` 20 問 |
| ボード | 14 × 10 m。ROUND 3 以降は 10 × 7 m（`board_size()`・`board_scale()`） |
| ボードが横へ動く | ROUND 2：振れ幅 2.0 m・周期 4.4 秒。ROUND 3 以降と延長：1.6 m・3.0 秒。前のゲートの最後のずれから続け、向きはランダム（`board_offset()`） |
| 通りすぎ | ゲートの時刻に判定 → 0.8 秒（見せ方の 0.3 倍のスロー）→ 次のゲート |
| 2 人とも同じゲートでアウト | `both_out` → 1.0 秒後に `revive`、その場から次のゲート。最後のゲートなら `revive` のあと `round_clear` |
| ROUND 5 のあと | 着地せずに `overtime`。1 枚ずつ 5 → 4 → 3 秒、以後 3 秒。3 秒のゲートで 2 人とも正解なら、正解のパネルに入ってそのまま出なかった刻みが早い方の勝ち（`by: "speed"`）。同じ刻みならもう 1 枚 |
| 動く速さ | 最高 10 m/秒（端から端 14 m を約 1.4 秒）。押すと 9/秒、離すと 11/秒でその速さへ寄る（離して 0.5 秒以内に止まる） |
| 押し合い | 2 人の体の中心は 1.2 m より近づかない。重なった分を半分ずつ押し戻し、近づく向きの速さも半分ずつ消す。ぴったり重なったら P1 を左へ |
| 動ける範囲 | 4 枚のパネルの外のふちから 0.3 m 内側（`play_rect()`）。ボードが横へ動くと範囲も動く |
| 真下のパネル | 体の中心の真下のパネル。仕切りの上なら一番近いパネル（`panel_for_local()`）。範囲の中ではかならずどれかのパネルになる |
| ラウンドの頭の位置 | P1 は (−2.0, −1.05)、P2 は (2.0, −1.05)（パネルの真ん中の高さ。縮めたボードでは縮める） |

### 座標

ボードの座標（m）：**ボードが止まっているときの中心が原点**、x＝右、y＝前（ゴールの側＝ボードの奥）。ボードが横へ動くと、
ボードの中心は `(board_offset(), 0)` にずれる。`pos` はこの座標の空中の位置、`local_point(slot)` はボードから見た位置（縮める前の値で、
`SkyGateBoard.board_point()` にそのまま渡せる）。パネルの寸法は `SkyGateBoard.PANEL_CENTERS`・`PANEL_SIZE` をそのまま使う。

### 出来事（計画書 4.5 節の名前どおり。足したキーは後ろ）

| 出来事 | 中身 |
| --- | --- |
| `round_start` | `round`・`gates`・`gate_time`・`board_size` |
| `gate` | `round`・`index`・`question`・`choices`・`correct`・`time`（＋ `overtime`・`board_size`） |
| `gate_pass` | `index`・`panels`・`results`（＋ `round`・`correct`・`local`（2 人のボードから見た位置）・`since`（真下のパネルに入った秒）・`overtime`） |
| `out` | `player`（＋ `index`・`round`） |
| `round_clear` | `round` |
| `both_out` / `revive` | `index`（＋ `round`） |
| `overtime` | `gate_time`（＋ `round`）。延長に入ったときに 1 回 |
| `decided` | `winner`・`by`（`"out"` か `"speed"`）・`round`・`index`（＋ `overtime`・`times`） |

呼ぶ口：`start()`（カウントダウンの終わり。`QuizGameState.start_sudden_death_countdown()` から）、`begin_round()`（`round_clear` のあと、
降下が終わったら次のラウンド）、`interrupt()`（押している向きを離したことにする）。答えのキー・アクションキー（Space）は使わない。

## 3. 入力

- `QuizGameState.set_sudden_death_move(player, move)`：今のフレームの入力の辞書に `"move": [P1, P2]` を足す（長さは 1 まで）。
  サドンデス中で、導入の間（`sudden_death_presentation_lock`）でないときだけ。
- `GameWorld._feed_sudden_death_input` の最後で毎フレーム、WASD（P1）と ↑←↓→（P2）の押しっぱなしから渡す（フォーカスを失った間は 0）。
- Space：`GameWorld` はいままでどおり P1 の "buzz" として `submit_sudden_death_key` に渡すが、`SkyGateGame` は使わない。
  Space を監督へ回す（`skip_presentation()`）のは W6。

## 4. 見せ方（`SkyGatePresenter`）

- `descent_mode()` は `"floatplane"`。受け持つのは図解ルールカード（`begin_venue()` から）・カウントダウン・本戦・ラウンドの着地・決着・勝者のダンス。
- 監督への口（W6 が `SuddenDeathPresenter` に足す名前と同じ）：`round_cleared()`（2 人とも着地台に着いて「ROUND n」を出し終えた）、
  `begin_round(round)`（ルールの `begin_round()` も呼ぶ）、`sky_spawn(player)`（腹ばいの体の中心。basis の +Z が頭＝前、+Y が背中）。
- 監督なしでも動く：`setup_solo(state, game, sky, camera, common_hud, sun)`（デバッグの入口とテスト）。
- `environment()` は本戦用の空撮の環境 `SkyFallScenery.venue_environment(quality)` を返す（監督がカメラに当てる）。

| 場面 | 中身 |
| --- | --- |
| 空中 | 2 人は空のセットの中心から 40 m 下の「落ちる点」のまわり（ボードの x → ワールドの −X、y → +Z）。空の演出の雲と景色を 40 m/秒で下から上へ流す。腹ばいは `DropMotion.pose_box`（動く速さの向きで 4 つの傾き）。2 人にマフラーと手足の風の筋。真下のパネルは自分の色の光る枠、紙の上に自分の色の輪（真下の印） |
| ボードの近づき方 | ゲートの頭は 320 m 下（海が近いときは海の 30 m 上まで）→ 1.6 秒で 26 m（読める近さ）→ ゆっくり 9 m まで → 最後の 0.9 秒で一気に 0。ボードはドローンで吊られているので、落ちる 2 人に合わせて下りながら近づく見せ方にした（2 人の落ちる速さは一定、ゲートの時刻はルールのまま） |
| G2_TopDown | 2 人の上・少し後ろから 84° で見下ろす（FOV 40°、2 人の高さから 16 m 以上離れる望遠ぎみ）。注視点は 2 人の真ん中を、近づいたボードの真ん中へ半分寄せ、2 人とボード（四隅と問題文の看板）が入る距離へ寄せる。P1 は常に画面の左 |
| G3_Through | ゲートの時刻から 0.8 秒（0.3 倍のスロー）。2 人とも正解・早い者勝ちはボードの真下から見上げ、アウトが出たら爆発が見えるボードの斜め上から |
| G4_Chain | 2 枚目以降の頭に 0.6 秒、真上から引いて下へ続くゲートを見せ、0.7 秒かけて G2 へ戻る |
| 正解・まちがい | `board.burst(panel, 位置)`・`board.boom(panel, 位置)`。アウトの人は `board.effects.player_burst`（ブロックはボードと一緒に上へ抜ける） |
| 2 人ともアウト | 0.5 秒からブロックが体へ集まり（0.45 秒）、`revive` で体が戻る |
| ラウンドの着地 | パラシュートを開いて（1.4 秒、見上げ）→ 海の高さの画にカットして 2 人とも着地台へ（左右 1.25 m）→ 顔を見合わせる → 4.8 秒に「ROUND n」→ 6.6 秒で `round_cleared()` |
| 決着 | スロー 0.8 秒のあと、勝者だけパラシュートで着地台へ（6.8 秒で `finale_done()`）。アウトの人のブロックが集まって幽霊になり、勝者の横をふわふわついていく（着地台の横の宙で待つ）。早い者勝ちで負けた方もブロックにばらけて幽霊になる |
| ダンス | `pose_winner_waiting`：`ResultWinnerDance`（1・2・3 / 8・9・0、2.5 秒で自動）。迎えのカメラは着地台のまわりを回る（パラシュートと同じ） |

- 問題文の看板：W5 が帯 `QuestionStrip` を大きな看板 `QuestionSign` に替えても、名前の違いは `_question_sign_point()` の 1 か所だけ
  （看板のノードがあればその位置、無ければ帯の寸法）。ルールはパネルの寸法しか使わないので、看板が変わっても判定は変わらない。
- 空の演出：W7 の `SkyFallScenery`（体積雲・島・海のサングリント・風切り・海鳥・飛行機雲。`assets/sudden_death/sky_fx/README.md`）。
  `_build_scenery` で落ちる点に置き、画面の上の向き（前＝+Z）を渡す。空のセットの海を `configure_sea`（描く順・太陽）、太陽はステージの太陽
  （監督のときは `stage_env.directional_light`）。毎フレーム `set_progress`（ラウンドの進み）・`set_overtime`・`set_wind`・`set_landing_point`・`advance`、
  ゲートの頭に `gate_emerge(board)`。速さの線はカメラの子に付くので、本戦の間だけ `set_camera(カメラ)`、着地の画・片づけで外す。
  空のセットの巡航の雲（`SuddenDeathSkySet.clouds`）は本戦の間は隠す。着地の画でも「近い島と着地台」の帯は残す（島・白波・サングリント）。
- マフラー：`SkyFallScarf` を 2 人の人形に付ける（見せ方の時計で進め、スローに合わせる）。空気の流れは落ちている間 30 m/秒、パラシュートの下 6、着地台の上 1.5。
  体がブロックにばらけている間はマフラーと風の筋を出さない。
- 海：空のセットの海を `SkyFallScenery.sea_depth(進み)` へ（1150 m 下 → 75 m 下、延長は 520 m）。着地の画では 20 m 下（パラシュートと同じ）。

### W6 へ（つなぐときにすること）

> 2026-10-19：下の 4 つはすべて W6 でつないだ（`skygate_w6.md`）。勝者の迎えは縄ばしごではなく水上機（着地台にスロープを下ろす）。

- `HeliSuddenDeathDirector._create_presenter` に `"sky_gate"` → `SkyGatePresenter.new()`、`QuizGameState` の `SUDDEN_DEATH_GAMES`・
  `_create_sudden_death_game`（`SkyGateGame.new()`）・`sudden_death_question_target()`（`SkyGateGame.QUESTION_COUNT`）。
- 降下が終わったら `begin_venue()`（ルールカードから）。降下のカメラは `sky_spawn()` の位置へつなぐ。
- `round_cleared()` が true になったら迎え（REBOARD）と短い降下 → `begin_round(round)`。その間、見せ方は 2 人を着地台の上に立たせておく。
- `extract_point()`・`extract_camera()`・`release_avatar()` はパラシュートと同じ（着地台と縄ばしご）。水上機の迎えに合わせて W6 が直す。

## 5. HUD（`SkyGateHud`）

上の真ん中に ROUND・ゲートの数（4 つの印）・残りの帯（残り 3/8 で赤く点滅）、延長は「延長」「1枚ずつ n 秒」。左上と右上に 2 人の札
（「15 の上」・「セーフ！」・「ドカン！」・「アウト」・「復活！」・「勝ち！」・「おそい…」）。下に小さく「P1 W A S D　P2 ↑ ← ↓ → で動く」。
大きな見出し（「ROUND 2」・「延長戦！」）と小さな知らせ（「ボードが動く！」・「ボードが小さく・速く！」・「早い者勝ち！」）。
**問題文は出さない**（ボードの看板だけ）。図解ルールカードは `sky_gate.md` 3.1 のとおり（3 枚の絵・一番下の帯・「Enter でスタート」、
出てから 0.6 秒は受け付けない）。カウントダウンは共通の `SuddenDeathHud`。英語も同じ文字の表（`TEXT_EN`）。

## 6. 確かめ方

```powershell
# ルール（30／60／120fps・正解・まちがい・時間切れの位置・押し合い・範囲・2 人ともアウトの復活・ラウンド・延長と早い者勝ち・入力の口）
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/sudden_death_v2/sky_gate_unit_bootstrap.gd
# 実画面の通し（画は artifacts/sudden_death_v2/sky_gate_play/）
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/sudden_death_v2/sky_gate_runtime_bootstrap.gd -- case=main
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tests/sudden_death_v2/sky_gate_runtime_bootstrap.gd -- case=small
# 遊ぶ（監督なし。-- round=3 でそのラウンドから、p2=right / wrong で P2 を自動に）
./Godot_v4.7.2-stable_win64.exe --path . --script res://scripts/world/sudden_death/games/sky_gate_debug_bootstrap.gd
```

## 7. 案から変えたこと・決めたこと（ユーザーの確認を待つ）

計画書第4章の約束（名前・関数・出来事）は変えていない（足しただけ）。`sky_gate.md` の「提案」・「案」から次を決めた。

| 項目 | 決めたこと | 理由 |
| --- | --- | --- |
| 見下ろしの角度 | 75°・上 6 m → 84°・16 m 以上（FOV 40°）と真下の印 | 75° で近くからだと、ボードが下にある間、体と真下のパネルが遠近で大きくずれて見え、体がボードを隠して、どのパネルの上か分かりにくかった |
| ボードの近づき方 | 一定の速さで近づくのではなく、1.6 秒で読める近さへ → ゆっくり寄る → 最後の 0.9 秒で一気に | 320 m から一定の速さだと、問題文が読める近さに来るのは最後の 1 秒ほどしかない |
| 動ける範囲 | ボード全体ではなく 4 枚のパネルの外のふち | 問題文の看板（帯）の上で判定されると、どのパネルでもなくなるため |
| 通りすぎたボード | 次のゲートの頭で片づける | 上へ抜けていく間、見下ろしのカメラをふさぐため |
| 早い者勝ちで負けた方 | ブロックにばらけて幽霊になる | 敗者は幽霊で帰る（common.md）に合わせた |
