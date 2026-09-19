# サントリーニ街区・観客席改修の検証記録

最終確認2026-09-14。AIQUIZ-Godot の街と観客席を、白壁・青い建具・段丘・港を持つサントリーニ風の環境へ置き換えた記録。最終 R5 の GLB と `final_*` の実行記録を対象とする。

## 完成データと制作範囲

住宅だけでなく、崖から水際まで続く段丘、階段、石畳、低い塀、港、教会、植栽をまとめて制作した。メニュー背景とゲーム背景は同じ街のシーンを使用する。観客席は白い石造の4段テラスと青い椅子・手すりに変更し、背後の街が見える高さにした。

| 項目 | 最終データ |
| --- | --- |
| 街の構成 | 13街区、住宅361棟、教会3棟、風車1基、階段137、パーゴラ69、樹木319、船6隻、テラス32 |
| 街の出力 | 39メッシュ、104サーフェス、6共有マテリアル、1,488,788三角形 |
| 街のパレット | 制作用の22色を頂点色へ格納。通常の照明を受ける4材質と、窓・灯具の発光用2材質 |
| GLB | 77,803,624バイト。R5 の SHA-256 は下記 |
| 観客席1基の基本形 | 4段、椅子584脚、基準長160m、1出力メッシュ、13サーフェス、91,096三角形 |
| 実ゲームの観客 | 左495人・右508人。観客席中心 X = −28m / +28m |
| 高さ | 観客の静止姿勢上端約3.075m。観客席装飾を含む形状上端約4.2m |
| 外部アセット・費用 | 街・観客席とも独自制作。購入・外部モデル／写真テクスチャの導入なし。追加費用0円 |

```text
b4444654b3bd80d6c1e8982b1ce203611784d88e9fa7063fc46227206c530eda
```

数値の根拠は [街の生成レポート](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/source/build_report.json)、[GLB検証レポート](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/source/export_validation.json)、[観客席の生成レポート](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_grandstand/asset_report.json)。GLB の実ファイルのハッシュも上記と一致した。Blenderへの再インポートと比較レンダーも成功しているが、この検査はゲーム画面の確認とは分けて扱う。

参照したのは、ユーザー指定の [Meshworks / Unity Asset Store のキット](https://assetstore.unity.com/packages/3d/environments/fantasy/santorini-modular-stylized-greek-island-town-kit-340718)、ギリシャ政府観光局の青いドーム、現地の街全景・路地・港・夕景など。画像そのものを確認して、段丘の重なり、白壁の曲面、限られた青のアクセント、低い海辺のテラスを制作へ反映した。参照画像はゲームへ取り込んでいない。出典と画像ごとの判断は [画像資料](C:/AIQUIZ/AIQUIZ-Godot/docs/santorini_visual_references.md)、制作物の権利・費用は [ASSET_SOURCES.csv](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/source/ASSET_SOURCES.csv) に記録した。

## 配置・見え方・編集方法

街の海面基準をゲームの Y = −9.2m に合わせた。コースが進む +Z 側では、Z > −150m かつ |X| < 70m を街の立体形状が横切らない条件で検証し、交差する三角形は0。街の衝突ボディも0で、背景がプレイヤーの通行を阻害しない。左右の観客席はコース外に置き、既存のコース長への追従を維持する。実ゲームでの結果は [2Pのプレイ時スナップショット](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_playing_sample_end_snapshot.json) に保存した。

メニューは意図的に観客席を含めない構成で検証した。ゲームでは左右の観客席と観客を確認し、クイズ表示と中央の進行方向が見えることを実画面で確認した。街の建物は背景として制作しており、建物内部や街中を歩く新しいゲームモードは追加していない。

- [town_layout.tscn](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/town_layout.tscn) が Godot の配置シーン。インポートした `Districts` の編集可能な子を有効にして保存してある。
- [街の Blender ソース](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/source/aiquiz_santorini_town.blend) と [生成スクリプト](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_town/source/build_santorini_town.py) から形状を編集・再出力できる。ゲーム向けには街区ごとの地形・建築・植栽へまとめており、住宅361棟を個別の Godot ノードとして保持する構成ではない。
- [観客席の Blender ソース](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_grandstand/source/santorini_open_terrace.blend) は8区画で編集可能。出力時に1メッシュへまとめる。
- 既存の `HarborCityBackdrop` 名は統合互換のために維持し、中身を新しい街へ差し替えた。制作ソースと比較用プレビューはゲームのインポート対象から除外している。

## 実ゲームの開始・復帰

Windows / Godot 4.7.2 / Forward+ の実ゲームで、オフライン問題を使って検証した。1P・2P の通常開始では、メニューの実際の開始処理からヘリの出発と到着を通り、`WAITING_START → FLYOVER → COUNTDOWN → PLAYING` を順番に観測した。最初のプレイ区間を採取し、メニューへ戻るところまで確認している。保存済みユーザー設定は検証前後で一致した。

| 対象 | 経路・観測した状態 | 結果・記録 |
| --- | --- | --- |
| 通常1P | メニュー開始、出発ヘリ1機、到着ヘリ1機、待機→飛行→カウントダウン→プレイ→メニュー復帰 | 成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p1_sequence.json) |
| 通常2P | メニュー開始、出発ヘリ2機、到着ヘリ2機、待機→飛行→カウントダウン→プレイ→メニュー復帰 | 成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_sequence.json) |
| 2Pリトライ | HUD のリトライ処理、待機→飛行→カウントダウン→プレイ→メニュー復帰 | 成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_retry_p2_sequence.json) |
| エンドレス2P | モードを指定してゲームへ直接進入、待機→飛行→カウントダウン→プレイ→メニュー復帰 | 成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_endless_p2_sequence.json) |
| チュートリアル1P | モードを指定してゲームへ直接進入、待機→カウントダウン→プレイ→メニュー復帰 | 開始確認成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_tutorial_p1_sequence.json) |
| チュートリアル2P | モードを指定してゲームへ直接進入、待機→カウントダウン→プレイ→メニュー復帰 | 開始確認成功、エラー0。[記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_tutorial_p2_sequence.json) |

各シーケンスは開始直後の短い検証であり、10問完走、エンドレスの長時間連続プレイ、チュートリアル全課程の完了を証明するものではない。エンドレス・チュートリアルの記録は通常1P／2Pと異なりメニューの出発演出を含まない。チュートリアルでは元の開始経路どおり飛行状態を通らず、専用UIと背景の表示を実画面で確認した。エンドレス2Pでは実際の観客席長934.5m、倍率5.840625で、配置条件と街の見通しを確認した。

代表画面は [2Pメニュー](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_menu.png)、[2Pヘリ到着](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_WAITING_START_arrival_1.png)、[1Pプレイ](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p1_playing_sample_end.png)、[2Pプレイ](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_playing_sample_end.png)。各画像と同名の `_snapshot.json` にカメラ、形状、材質、観客、描画情報を併記している。

### 通常落下・サメ死亡の限定確認

リトライ後に `PLAYING` へ到達し、Aキーを約2秒間押してコースの端から落下させた。[入力・状態記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_edge_input.json) は入力後の位置 X = 15.821m、Y = −2.009m と、`PLAYING → GAME_OVER` を記録しており、撮影エラーは0。[落下中の画面](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_edge_fall_03.png) で新しい観客席の横を落下する様子を、[死亡結果の画面](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_edge_fall_10.png) で「海でサメに襲われた！」と `GAME OVER` の表示を確認した。その後のメニュー復帰は実行担当が確認した。JSONの状態記録は `GAME_OVER` までである。

この試行では新しい街・観客席に遮られず、通常の落下からサメ死亡・結果表示まで進んだ。ただし追従カメラが既存のコンベア床下へ移動し、噛みつきの大部分は床に隠れたため、サメ演出全体の構図確認には含めない。落下を撮り逃して既に `GAME_OVER` だった `final_edge_shark` の画像は、この確認の根拠として採用しない。

## 時刻・描画品質

1P／2P × Low／Balanced／High × 昼／夕方／夜の18条件を撮影した。ゲームの更新と物理更新を一時停止して同じカメラ・プレイヤー位置を保ち、撮影後は品質・時刻・更新状態を復元した。両方の [1Pマトリクス記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p1_matrix_matrix.json)・[2Pマトリクス記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_matrix_matrix.json) は成功し、設定の不変とゲーム状態の保持も確認した。この18条件は静止状態の見た目の検証で、各条件の動作性能を測ったものではない。

High の代表画像: [昼](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_matrix_high_day.png)、[夕方](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_matrix_high_sunset.png)、[夜](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_matrix_high_night.png)。白壁は環境光を受け、夜は窓と灯具だけが暖色で発光する。

GLB インポート時の共有材質フラグにより頂点色が無効になるケースを修正した。[santorini_vertex_palette.gd](C:/AIQUIZ/AIQUIZ-Godot/scripts/world/santorini_vertex_palette.gd) を `@tool` とし、対象のパレット材質に `vertex_color_use_as_albedo = true` と `albedo_color = Color.WHITE` を設定する。元の GLB は白い材質倍率と完全な頂点色を持つが、エディターの共有材質に単色が折り込まれる場合があるため、二重乗算を防ぐ。配置シーンへ取り付け、エディターと実行時の両方に同じ色を反映する。

2026-09-14の最終確認で、エディターの4パレットすべてが白い材質倍率・頂点色有効になり、3Dプレビューの白壁と青い観客席を目視確認した。[材質の確認記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_editor_validation.json)。`game_world.tscn` を明示保存し、今回の確認前のファイルと SHA-256 が一致した。新規ゲームプロセスでも通常2Pの開始からメニュー復帰を再実行し、エラー0・保存設定不変を確認した。[再実行記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_p2_sequence.json)。追加の9条件も成功し、状態と設定を復元した。[再撮影記録](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_p2_matrix_matrix.json)。最終の代表画面は [昼](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_p2_matrix_high_day.png)、[夕方](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_p2_matrix_high_sunset.png)、[夜](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_palette_p2_matrix_high_night.png)。

描画品質の計算は [graphics_quality.gd](C:/AIQUIZ/AIQUIZ-Godot/scripts/core/graphics_quality.gd) の静的関数にし、環境側では `QualityRules` を明示的に preload する。エディターの Autoload が非 `@tool` のプレースホルダーでも品質規則を使えるようにした。方向光の影距離は Low 100m、Balanced 280m、High 420m。街の影は Low で無効、Balanced／High で有効にする。

[エディター検証](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/quality_editor_verification.json) と [実行時検証](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/quality_runtime_verification.json) はそれぞれ68項目成功。変更した環境スクリプトと検証スクリプト7本は、Autoload を登録した実行中のプロジェクトで読み込み・インスタンス生成可能なことを確認した。[実プロジェクトのスクリプト検証](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/project_runtime_script_validation.json)

単独の `--headless --check-only --script` は、このプロジェクトの Autoload 識別子を登録しない実行方法では `GameManager` / `QuizManager` を解決できない。その終了値を環境全体の検証成功の根拠にはしていない。

## 性能測定と旧環境との比較

測定条件は1280×720、Forward+、High、240fps上限の検証セッション。フレーム間隔は実時間差で測り、PNG の読み戻し・保存を計測区間から除外した。描画待ちとフレーム制御を含む間隔であり、GPU専用タイマーの値ではない。

| 最終版・実プレイ中 | 計測長／標本数 | フレーム間隔 p50 | p95 | p99 |
| --- | --- | --- | --- | --- |
| 通常1P | 約2.5秒／602 | 4.146ms | 5.000ms | 5.397ms |
| 通常2P | 約2.5秒／602 | 4.153ms | 4.991ms | 5.402ms |

根拠: [1Pの実プレイ計測](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p1_playing_performance.json)、[2Pの実プレイ計測](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_playing_performance.json)。計測後に画像を撮り、放置による失敗状態を記録へ混ぜずメニューへ戻した。

別に、2P の `WAITING_START` でゲーム更新・物理更新を固定し、元の街＋元の観客席＋元の観客と新環境を同じカメラ・時刻・品質で比較した。元のソースは改修前に保存した `.gd.before` から再構築し、当時の観客席モデル・中心 ±32m・影設定を使用する。新しい観客席の中心は ±28m。コースに対応する長さは共通に保った。

| 静止描画 A/B/A | 手順 | フレーム間隔 p95 |
| --- | --- | --- |
| A1: 旧環境 | 30フレーム準備後、約2.5秒計測 | 4.945ms |
| B: 新環境 | 同条件 | 4.908ms |
| A2: 旧環境を再表示 | 同条件 | 5.000ms |

[比較レポート](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_ab_comparison.json)、[旧環境A1](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_ab_baseline_a1.png)、[新環境B](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_ab_after_b.png)、[旧環境A2](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation/final_p2_ab_baseline_a2.png)。カメラ・天候・品質・ゲーム状態の不変、終了後の旧比較ノード破棄と表示・更新状態の復元、保存設定の不変はすべて成功した。

この A/B/A は **静止描画の比較（STATIC_RENDER_COMPARISON）**。実プレイ中の CPU 負荷を比較したものではなく、旧版と新版を同時にメモリへ保持するためメモリ比較にも使えない。約4.9～5.0msの同程度の範囲だったことを示す短時間の結果であり、新版の高速化、全端末・全品質の性能、常時240fpsを保証しない。街の出力は約149万三角形あるため、他の解像度や端末の性能をこの1セッションから推定しない。

## 観客席の追加検査と変更範囲

[観客配置の検証](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_grandstand/seating_validation.json) は、4段の着座位置、通路の空き、左右の向き、長さ変更時の配置、身体比率、バッチ境界、姿勢・服の色を検査して成功した。複数の乱数種と長さ倍率0.5／1.0／2.5を対象にしている。[観客の動き](C:/AIQUIZ/AIQUIZ-Godot/assets/environment/santorini_grandstand/motion_validation.json) は固定カメラ・固定環境の単独観客席で確認した。508人を表示し、約1.08秒後の画像に変化があり、着座した観客のアニメーションが描画される。単独観客席の検査と本編の実画面は別の証拠として保持した。

環境統合の主要変更は `harbor_city_backdrop.gd`、`stage_environment.gd`、`grandstand_crowd.gd`、`graphics_quality.gd` と新規パレット補助スクリプト・街／観客席アセット。変更前の4スクリプトは [検証フォルダー](C:/AIQUIZ/AIQUIZ-Godot/artifacts/santorini_renovation) の `.gd.before` に保存し、静止比較に使った版のハッシュも比較レポートへ記録した。検証ハーネスは [実行・撮影用](C:/AIQUIZ/AIQUIZ-Godot/tests/santorini_environment_runtime.gd) と [旧新比較用](C:/AIQUIZ/AIQUIZ-Godot/tests/santorini_environment_comparison.gd) に分けている。

この文書の完成画像の根拠は最終 R5 と一致する `final_*` に限定する。旧インポートが残っていた `r4` ラベルの記録は最終版の証拠として採用しない。
