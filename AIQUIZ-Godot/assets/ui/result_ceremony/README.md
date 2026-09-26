> 旧版（v1）。現在の勝敗演出は [スコアタワー・フィナーレ](../../result_finale/README.md)（その前の審判・バット演出は [Referee v3](../../animations/result_referee/README.md)）。以下は旧演出の記録として保持。

# 二人同時生存の得点発表

ローカル・通常の10問チャレンジで、二人とも生存してゴールした場合だけ使用する。到着時の正解数とHPを保存し、`正解数 × HP` の大きい方が勝利。同点では両者を残す。到着順は採点に影響しない。

## 実時間のタイムライン

時刻0は二人とも到着・接地した瞬間。最初の2秒は整列・歩行、その後の得点発表は0.75倍速。結果ボタンは約12.67秒から操作可能になる。

| 秒 | 表示・動作 |
| --- | --- |
| 0–2 | 整列、既存床上の歩行 |
| 2 | カード・正解数の登場 |
| 3.33 | 残りHP |
| 4.67–6.27 | 両者の合計点を同時カウント |
| 6.27–7.33 | 合計点確定・保持 |
| 7.33 | 中央上部の勝敗文字・集中線。色面はまだ出さない |
| 8.13 | 敗者のみ煙とパーツの爆散（HP・生死は変更しない） |
| 9.33–11.47 | 勝者へ約2.13秒かけて寄る。勝利文字は従来の斜め移動の経路を保って右へ移り、色面もこの移動から登場 |
| 12.67以降 | 得点内訳を残し「もう一度・履歴・メニュー」を操作可能にする |

引き分けは二人ショットを維持し、爆散・勝者アップ・片側の色面を出さない。この専用結果画面には「問題を評価」「＋」「−」を作成しない。床の短縮と旧草原演出は無効のまま。先着者の待機中に相手が脱落した場合は従来の一人生存時の処理へ戻る。1P・エンドレス・チュートリアル・協力・オンライン・リプレイは専用演出の対象外。

## 編集用AE

- `source/AIQUIZ_Result_Ceremony.aep`: After Effects 2026、1280×720、60fps。
- `AIQUIZ_Result_Ceremony_Delivery`: 最新プレビュー用の14秒コンポジション。編集用コンポジションをネイティブのタイムリマップで参照する。実時間0→2→14秒に対し、ソース時間0→2→11秒。
- `AIQUIZ_Result_Ceremony_v1`: 編集用の11秒コンポジション。キー・マーカーはソース時間で保持する。Godotの `QuizGameState.result_motion_time()` が同じ時計変換を行う。
- `AIQUIZ_Result_P1_Card` / `P2_Card`: 文字・シェイプによるカード。`Correct count`、`HP count`、`Total`が数値。
- `AIQUIZ_Result_Victory` / `Draw`: 勝利・引き分け文字。
- `AIQUIZ_Result_Actions`: 操作ラベルとシェイプ。
- フォント: Noto Sans JP Bold。P1 RGB `(0.95, 0.55, 0.20)`、P2 `(0.20, 0.65, 0.90)`。

AEの数値はプレビュー用（9×1と7×3）。ゲームは `QuizGameState` に確定保存した数値を描画する。文字・色を変更する場合はAEの対応レイヤーとGodotの `result_ceremony_overlay.gd` を更新する。動画をゲーム内で再生する方式ではない。

カードの左右からの登場、時間差、拡縮・傾き、数字の段階表示、得点確定時の括弧・下線、勝利文字と色面の動きをネイティブのキーで編集できる。勝利文字の始点・終点・斜めの移動経路・イージングは従来を保ち、移動時間だけを延ばしている。ボタンの短い登場は、ゲームの結果時計が止まった後も表示用時計で完了させる。

## 動作データの再書き出し

HiggsfieldローカルAEブリッジを起動し、上記AEPを開いた状態でプロジェクトルートから実行する。`source/tracks.json` がソースコンポジションのプロパティと採取区間を定義する。

```powershell
$env:AE_MCP_EXE = 'G:/adobe/Adobe After Effects 2026/Support Files/AfterFX.exe'
node assets/ui/result_ceremony/source/export_motion.mjs --request artifacts/result_ceremony/ae_resample.json
node assets/ui/result_ceremony/source/local_ae.mjs artifacts/result_ceremony/ae_resample.json artifacts/result_ceremony/ae_resample_result.json
node assets/ui/result_ceremony/source/export_motion.mjs artifacts/result_ceremony/ae_resample_result.json
```

`motion.json` は38トラック／2032サンプル。ソース時間の約60Hzで取得し、Godot側の時計変換後に線形補間する。AEには少数の編集可能なキーを保持し、密なサンプルはゲームへの受け渡しに使用する。画面は1280×720を基準に等倍比で中央配置する。

## 検証

`tests/result_ceremony_bootstrap.gd` は既定で単体検証を起動する。`-- runtime case=p2 fps=60 slower sizes` で実シーンとサイズ変更を検証し、`case=p1` / `case=draw` で他の勝敗を確認できる。録画時の `audible` はテスト中だけ音量を上げ、終了時に元の設定を復元する。`routes` は実際のリトライ・メニュー・待機中の相手脱落も検証する。

最新のAEプレビュー、音付き実機映像、場面PNG、検証JSON・ログは `artifacts/result_ceremony/slower/`。詳細は同ディレクトリの `VERIFICATION.md`。初回実装の全受け入れ検証は親ディレクトリの `VERIFICATION.md` に保存している。
