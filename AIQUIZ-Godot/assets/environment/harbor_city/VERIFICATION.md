# 制作・導入の確認記録

2026-09-13。対象: C:/AIQUIZ/AIQUIZ-Godot、Godot 4.7.2 Forward+、Blender 5.1.2。

## 実際に実行した内容

- 開いていたBlenderに接続し、新しい「AIQUIZ U Harbor City」シーンで制作、GLB書き出し、.blend保存を実施。元のシーンを保持し、作業前のファイルも保存した。
- 前方（Godot +Z）を開け、左8街区・後方7街区・右8街区に合計368棟を配置。左右の内側岸壁はコース軸から1220 m、後方岸壁は原点から1240 m。全体は2960 × 3550 m。
- 段状の屋上、円形・八角形の塔、切妻屋根、港施設の曲面屋根、外壁と窓をBlenderで制作。地盤と岸壁をコの字型につないだ。
- 自作PNG 7枚を単体で保存し、.blendにパック、GLBにも埋め込み。必要画像の欠落なし。既定のCube、確認用の海・照明・カメラは書き出し対象外。
- GodotでGLBを再インポートし、既存のStageEnvironmentからメニュー・本編共通の座標に配置。13メッシュ、137マテリアル面、349718三角形（距離LOD適用前）。背景の影・GI・衝突判定を無効にした。
- 実際のメニュー、1人プレイ、2人プレイで昼・夜の画像を取得。1人・2人とも新しいゲームシーンで WAITING_START → FLYOVER → COUNTDOWN → PLAYING に到達し、画面遷移が終了した状態を確認した。
- 両プレイ人数で左右・後方それぞれ4個の統合メッシュ、共通地盤1個、海面Y=-9.2、前方の開放領域に街の頂点0、背景の衝突ボディ0を確認。窓の発光は昼0、夜1.25。
- 最後のスクリプト調整後にメニューを再起動。変更した3スクリプトを実行中のGodotでコンパイルし、すべてエラーコード0。街1組・13メッシュ・窓材質3種を再確認した。
- 最終実行 r22842569-31 のログ434件を確認し、実行エラー0。既存のLiveConfigManagerの取得失敗警告（result=13/code=0）が1件あった。
- 検証用プレイはオフライン問題で実施。有料API・追加ソフト・外部素材の購入は0円。

## 実際の画面から分かったこと

メニューでは後方の街並みが水平線に見える。通常の正面プレイ視点では、左右の街は遠方の観客席に大きく隠れ、後方の街は画角外になる。前方を開ける配置を維持しており、通常プレイ画像だけで街全体が見渡せる状態ではない。Blenderの俯瞰表示では三方向の配置と連続する岸壁を確認できる。

## 未確認・未実施

- Godotの編集画面でのStageEnvironment全体プレビュー。既存のGraphicsQualityが@toolではなく、編集画面からの呼び出しでplaceholder instanceエラーが発生した。実行中のゲームでは再現しなかった。この既存処理は変更していない。
- 配布用ゲームのエクスポート、Androidでの動作、長時間の性能測定。観測したFPS値は性能保証として扱わない。

## 保存した証拠と再実行

プロジェクトの `artifacts/harbor_city/` に以下を保存した。

- `blender_live_overview.png` / `blender_live_top.png`: 開いているBlenderの画面。
- `menu_return_day.png` / `menu_return_night.png`: 実際のメニュー画面。
- `gameplay_1p_day.png` / `gameplay_1p_night.png`: 1人プレイ画面。
- `gameplay_2p_day.png` / `gameplay_2p_night.png`: 2人プレイ画面。
- `runtime_sequence.json`: プレイ人数ごとの遷移と配置・昼夜検証結果、status=passed。
- `final_runtime_smoke.json`: 最終調整後の実行時コンパイルとメニュー導入結果。
- `blender_before_live_city.blend`: 作業開始前のBlenderファイル。
- `stage_environment.before.gd` / `camera_controller.before.gd`: 今回の追加直前のソース。

`tests/harbor_city_runtime.gd` は実行中のゲームに対する確認用スクリプト。`capture(stage, viewport, tag)` は実際の描画先の昼夜画像と配置検証を保存する。`exercise_rounds(tree)` はオフライン設定の本編から呼び出すと、1人・2人のリトライと開始入力を実行し、検証後にメニューへ戻る。通常ゲーム処理には接続していない。

制作データ・再生成手順・素材の条件は [README.md](README.md) と [素材一覧](source/ASSET_SOURCES.csv) を参照。
