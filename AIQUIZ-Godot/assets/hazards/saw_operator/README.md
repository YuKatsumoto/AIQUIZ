# 連結チップソー操縦席

進行方向の左端に取り付ける、ゴドーくん着席済みの操縦席。既存台車・キャラクターのGLBを基準に追加制作した。元の台車GLBとゴドーくんの形状・16ボーンは変更していない。

## 素材

| ファイル | 内容 |
|---|---|
| `saw_operator.glb` | 実行時素材。94オブジェクト、57メッシュ、約5.2MB。操作部と飛行する椅子を別階層に保持 |
| `source/saw_operator.blend` | 編集用原本。分割メッシュ、カーブ、文字、既存リグ、配線、固定金具、材質。テクスチャを内包 |
| `source/evaluated_poses.json` | ゲームと同じ評価器から出力した60fps・961フレームの検証姿勢 |
| `references/v2/01_layout.png` | 台車全体と配置の参考画像 |
| `references/v2/02_controls.png` | 操作盤の詳細参考画像 |
| `references/v2/03_seated_side.png` | 着席側面の参考画像 |
| `references/v2/generation_record.json` | 生成元、モデル・設定の取得可否、Higgsfieldの見積もりと失敗理由 |

Higgsfieldの画像生成は契約制限によりジョブ作成前に失敗。ユーザー指定に従い、別の画像生成機能で3枚を制作した。Higgsfieldの予定モデルは `gpt_image_2`、high／2k／16:9、見積もりは1枚6.5クレジット（3枚19.5）。代替生成の内部モデル名・請求額はツールから返されていないため未記載。参考画像の人型に近い身体比率は採用せず、実際のゴドーくんの短い手足に操作部を合わせた。

v2の3枚を基準に、独立した銀色の可動溝・中立指標、ゴムブーツ、軸受、ボルト、配線固定具、計器の枠、整備ハッチを制作した。計器面は実際の操縦者へ向けている。v1画像は過去の制作資料として残す。

キャラクターの出典は既存の `assets/characters/godot_plush/CREDITS.md` を参照。

## 表示と動作

`SawOperatorPresentation` は台車表示の子として配置される。1.64m×1.74mのデッキ、銀色の金具、暗色の操作盤、ゴムグリップ、クッション座面で構成する。

- 本編の格納中心は `(10.7, 0, 0)`、展開中心は `(12.95, -0.628274, 0)`。刃列の左端の外側フレームに固定し、座席・操作盤・操縦者を90度回して右側の刃列へ向ける。逆方向へ搬出するメニューでは左右と向きを反転する。
- 格納時は台車上に収まり、船の前縁を通過する搬出後半（5.40〜5.90秒）に左へ2.25m展開し、5.90〜6.20秒に床を0.628274m下げる。展開後の床上面は静止した刃の底面（台車ローカル高さ0.341726m）に揃う。固定支持部と伸縮レールを分離し、昇降する刃の円柱状の可動領域から退避する。
- 外周の黄色い柵・下段柵・取付脚を削除。船のシャッターはゲーム内で除去し、開閉動作と作動音を廃止した。昇降量と搬出の時間は維持する。
- 着地と台車配置が完了した既存の始動時刻でボタンを押し、保護カバー、スイッチ、ダイヤルの順に約4秒の加速に合わせて操作する。
- 左レバー・ペダルは符号付き走行速度、右レバー・ペダルは刃の昇降速度を入力とする。高さ保持中は右側が中立へ戻り、右計器は高さを示す。刃の変位が最も大きい対象を選び、同量は左側を優先する。対象切り替えの反対操作は最長0.24秒で連続的に移行する。
- 手首・肘・足首を既存リグの2関節IKで解き、接触点へ合わせる。頭と上体に操作状態に応じた視線・傾きを加える。
- ポーズと結果表示では姿勢を保持。リトライ・スキップは配置済み状態、リプレイは記録時間と隣接記録の車輪移動・プレイヤー位置から再評価する。シーク順に依存せず、刃の高さと操縦入力を復元する。

衝突、追走速度、対象モード、34項目の録画形式、既存カメラは変更していない。追走時は左端が既存カメラの画面外になる。ユーザー確認により、搬出・開始前・メニューでの見やすさを優先する。

## 原本の編集と再出力

Blenderでは `SawOperator_Workbench` を選択する。1〜961フレーム／60fps。タイムラインに格納・搬出・ボタン・カバー・スイッチ・ダイヤル・前進・上昇・保持・後退・下降・中立のマーカーがある。ボーンの元のIK制約はミュート状態で残し、検証用ポーズをキーフレーム化している。実行時GLBはアニメーションを含まず、Godotが評価する。

`tools/saw_operator/build_station.py` は `operator_stage = 'blockout' / 'contact' / 'detail' / 'export'` を指定し、接続中のBlenderで実行する段階別制作スクリプト。原本の既存パーツを編集する場合はblockout/detailを再実行せず、exportだけを実行する。複製を材質と親ごとに結合して出力し、編集原本は分割状態を保つ。

表示コードを変更した後は以下を実行し、続いてBridgeから `tools/saw_operator/bake_source.py` を実行する。Godotの姿勢をBlenderへ反映できる。

```powershell
godot --headless --path . --script res://tests/saw_operator_export_poses.gd
```

`source/` と `references/` は `.gdignore` で実行時インポート対象から除外している。

## 検証

椅子だけのロケット発射・着地の追加仕様は `docs/seat_launch.md`。参考画像は `references/seat_rebuild/`、今回の動きの編集用プレビューは `source/chair_transfer_preview.blend`、実機動画・最新検証は `artifacts/seat_launch_rebuild/` に保存する。原本の既存操縦動作は保持する。

最新の結果と映像は `artifacts/saw_operator/v2_report.md`、比較画面は同フォルダーの `review_v2.html`。画像・動画・一時検証GLBは既存Git除外のartifacts内にあり、別環境へ渡す際は一緒にコピーする。

```powershell
godot --headless --path . --script res://tests/saw_operator_acceptance_bootstrap.gd
godot --headless --path . --script res://tests/saw_chase_bootstrap.gd
godot --headless --path . --script res://tests/saw_dock_bootstrap.gd
godot --headless --path . --script res://tests/menu_saw_unit_bootstrap.gd
godot --path . --resolution 1600x900 --script res://tests/menu_saw_runtime_bootstrap.gd
godot --path . --script res://tests/menu_saw_edges_bootstrap.gd
godot --path . --resolution 1280x900 --script res://tests/saw_operator_runtime_bootstrap.gd
godot --path . --resolution 1600x900 --script res://tests/saw_operator_scene_bootstrap.gd -- mode=menu
godot --path . --resolution 1600x900 --script res://tests/saw_operator_lifecycle_bootstrap.gd
```

検証用ワーカーは別プロセスで実行する。`scene_bootstrap` は `mode=game`、`retry`、`menu_return` も受け付ける。テストは実ゲーム状態を操作するため、作業中のプレイへ接続して実行しない。
