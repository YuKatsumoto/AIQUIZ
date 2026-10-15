# オンライン対戦 マッチング演出

「マッチング開始」を押してから、ステージ画面が開くまでの演出（乗り込み → 離陸 → 検索中の飛行 → 合流 → 並走 → VS カットイン → 読み込み → 中央の線が開く）。

| 資料 | 中身 |
|---|---|
| [仕様書 spec.md](spec.md) | 何をどう見せるか。決定記録（D1〜D17）、状態と時刻表、ショットごとのカメラ・動き・画面、カットインの見た目、通信、音、重さの予算、受け入れ基準 |
| [計画書 plan.md](plan.md) | どう作るか。使う道具（MCP・ツール）の割り当て、マイルストーン M1〜M9、ファイルの一覧、テストのコマンド、危ないところ、完了の定義、絵と音楽の頼み方 |
| 絵コンテ v2 `artifacts/storyboard/online_matching_storyboard_v2.png` | 11 コマ（Codex CLI の画像生成）。v1 は `online_matching_storyboard_v1.png` |
| ヘリの設計図 `artifacts/heli_blueprint/heli_pilot_blueprint.html` | 乗り込めるヘリと操縦士ハテナの寸法・すき間のチェック（図 1〜9） |
| ヘリの素材 `assets/vehicles/helicopter_boarding/` | 作成済みの GLB と Blender の原本、使い方 |
| 実装 `scripts/world/online_staging/`、`scripts/ui/online/cutin/` | 監督・時刻表・カメラ・飛び方・キャラ・雲・操縦士ハテナ、VS カットイン。計画書の「9. 実施の記録」に結果 |
| 確かめたもの `artifacts/online_staging/` | 場面ごとのスクリーンショット（`shots/`）、絵コンテとの比べ（`compare_storyboard.png`）、通しの動画（`animatic.mp4`）、重さ（`perf.json`）、2 人の通し（`pair_results/`） |
