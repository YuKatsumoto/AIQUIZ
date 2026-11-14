# 新しい PC で試合中に固まる問題（2026-11-07）

## なぜ固まるか

新しい PC では、ゲームが初めて描くもの（材質・描き方）ごとに、グラフィックドライバーが描画の部品（パイプライン）を作り、作り終えるまで画面が止まる。部品はその PC の GPU とドライバーごとに作るしかなく、書き出しのシェーダーの焼き込み（shader baker）では防げない（焼き込みで縮まるのは初回起動の時間だけ）。

この PC ではドライバーのキャッシュに部品が残っているので、そのまま遊んでも再現しない。Godot が数える「部品を作った数」（`RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_*`）は、キャッシュがあっても増えるので、この PC でも漏れは見つけられる。

試合中に初めて出ていたもの（直す前に新品の PC 相当で測った止まり）：

| 場面 | 止まり | 初めて出ていたもの |
|---|---|---|
| 間違えてハートが減る（初回） | 1.1 秒 | 点滅で半透明にした体（`mesh.transparency`） |
| 海に落ちてサメにかまれる | 2.3〜2.4 秒 | 爆発の演出（`vfx_explosion_01`）・水柱・広がる輪（半透明にしながら消す） |
| サメのあとのゲームオーバー | 0.2〜0.26 秒 | 水柱を捨てる瞬間の待ち |
| 2 人で P2 が脱落 | 0.4 秒 | サメに立つ光の柱（GhostMountBeacon）、ゴーストの演出 |
| 2 人の結果発表 | 1.3〜1.9 秒 × 3 回 | P2 のスコアタワー（左右反転）、観客が投げる卵と中身（白身・したたり・筋） |
| カウントダウン・プレイ開始 | 小さい | 頭上のキー案内（押したときの光る枠） |

## 直したこと

- **試合開始の覆いの下で描く**（`GameWorld._prepare_world_visuals_under_cover`）
  - 半透明の点滅体・爆発の演出（`PlayerController.begin_death_render_prewarm`）
  - 粒子（正解の光・爆発・水しぶき・サメの水柱と輪）（`particle_spawner.gd` の `begin_render_prewarm`）
  - キー案内（押したときの見た目も）（`CountdownKeyHints.begin_render_prewarm`）
  - 2 人：ラグドール・ゴースト（半透明・不透明）とその演出（`PlayerController.begin_duo_render_prewarm`）、光の柱・照準の輪・乗り移られたサメ（`GhostSharkRideController.begin_return_portal_render_prewarm`）
  - 結果発表：紙吹雪・花火・勝者のスポットライト（`ResultFinaleEffects.begin_render_prewarm`）、左右両方とタワーが伸びきったあとのスコアタワー（`ResultCeremonyDirector.begin_render_prewarm`）、掲示板の顔写真（`GoalStandScoreboard.build_portrait`）
  - ゴール観客席と卵（体と床に当てる、中身の部品も）（`GameWorld._begin_goal_stand_render_prewarm`。起動してから 1 回だけ）
- **作り終えるまで待つ**：決まった 2 フレームではなく、部品を作る数が増えなくなるまで描き続けてから覆いを外す（`PipelineWatch.wait_until_settled`、上限 600 フレーム）。
- **使い捨てにしない**：爆発の演出・水柱・輪は作り置きして使い回す。試し描きした材質は、ゲームを終えるまで持ち続ける（`PipelineWatch.keep_materials`。コードで作った StandardMaterial3D は、同じ設定の材質がすべて捨てられると描き方ごと消え、次に使うときに作り直すため）。

## 見張りと確かめ方

- **開発中の警告**：試合中（覆いが開いたあと）に部品を作ると、エディタでの実行（デバッグビルド）で `[HitchRecorder] 試合中に描画の部品（パイプライン）を作りました` と出る（`scripts/autoload/hitch_recorder.gd`）。演出を足したら、遊んでこの警告が出ないことを確かめる。
- **確認テスト（画面あり）**：本物の始まり方で試合を準備し、点滅・粒子・サメにかまれる演出で部品を 1 つも作らないことを確かめる。
  `./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/fresh_pc_pipeline_runtime_bootstrap.gd`
- **新品の PC の再現（書き出した製品版で）**：まだ使っていない名前の exe（NVIDIA は exe ごとにキャッシュを分ける）と空のゲームのキャッシュで、自動プレイ 3 場面（10 問完走・間違いとサメ・2 人で 10 問）を遊ばせ、試合中に 50 ms を超えるフレームと部品作りがないかを見る。
  `python -X utf8 tools/perf/fresh_pc_probe.py`（結果は `artifacts/fresh_pc_probe/summary.json`。1 回の実行で NVIDIA のキャッシュに約 35 MB 増える。古いものはドライバーが消す）
- **どこで止まったかを調べる**：計測に `--trace_visuals=1` を付けると、部品を作ったフレームで初めて見えた物・足された物を記録に付ける。
  `./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/perf_endless_bootstrap.gd -- --players=2 --mode=ten --trace_visuals=1 --tail_seconds=45`
- **ほかの PC で止まったとき**：0.1 秒を超えたフレームは、製品版でも `%APPDATA%\Godot\app_userdata\TESTOPIA\logs\hitches.log` に、そのときの場面・状態・作った部品の数と一緒に残る。

## 結果（新品の PC 相当）

RTX 5070 / Core i7-12700F、画質「高」・60fps・1920x1080、書き出した製品版（シェーダー焼き込みあり）で `tools/perf/fresh_pc_probe.py` を実行（2026-11-07 17:05 の書き出し）。

| 場面 | 直す前 | 直したあと（試合中の最長フレーム） |
|---|---|---|
| 10 問を正解で完走（ボス壁・ゴール・クリア） | 46 ms | 46 ms |
| 3 枚目で間違い・5 枚目で海に落ちてサメ | 1.1 秒・2.3 秒・0.26 秒 | 34 ms |
| 2 人で 10 問（P2 は脱落、結果発表まで） | 0.4 秒・1.3〜1.9 秒 × 3 | 38 ms |

- 起動準備（新品の PC 相当）は約 32 秒、2 回目の起動は約 9 秒。試合開始の準備は、新品の PC で最初の 1 回だけ数秒延びる（観客席の試し描きは起動してから 1 回だけ）。
- 2 人で P2 が脱落した瞬間に毎回 0.18 秒止まっていたのは、描画の部品ではなく CPU の処理だった（サメに立つ光の柱の素材を毎回複製していた）。一度複製した物を PackedScene にして使い回すようにした（`SharkSwimmer.localized_ghost_mount_beam`）。

### 残っていること

- 部品作りは小さいものが残る（止まりにはなっていない）：10 問の最後の壁で 2D の部品 1 つ（その 1 フレームは 46 ms）、2 人でラグドール・照準の輪・結果発表の 2D の部品など（どれも 40 ms 未満）。再現テストは「部品作り 0」で判定するので、この分は FAIL と出る。
- 起動準備（覆いの下）では、新品の PC で読み込み中の絵が 1 回 5 秒ほど止まる（メニューの組み立てとその最初の描画）。遊んでいる間ではないので今回は直していない。
- AI モード（オンライン生成）での試合は、本番サーバーに費用がかかるので測っていない。
- 計測用の書き出しを自動で終了させると、終了の瞬間に異常終了（`0xC0000374`）することがある。ふつうに閉じたときに起きるかは確かめていない。
