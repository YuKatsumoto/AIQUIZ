# 椅子だけのロケット発射・着地

ローカル2Pの10問・エンドレスで、メニューのスタートからゴドーくんの椅子だけを発射する。既存の引きカメラとローディングを使用する。

## モデル

`OperatorStation/OP_SeatFlightRoot` に座面、背もたれ、縁取り、既存の16ボーンのゴドーくん、腰ベルト、2基の噴射口をまとめた。操作盤・レバー・ペダル・床・支持部は固定側。`OP_SeatSocket` が固定側の着地基準。材質別メッシュ結合も親階層を保持し、ベルトのモーフメッシュを結合対象から除外する。

新しい参考画像は `assets/hazards/saw_operator/references/seat_rebuild/chair_only_reference.png`。HiggsfieldはBasicプラン制限でジョブ作成前に失敗したため、指定された内蔵画像生成へ切り替えた。生成記録は同フォルダーのJSON。

`source/saw_operator.blend` は既存操縦アニメーションを保持する原本。`source/chair_transfer_preview.blend` は今回のGodotの姿勢を焼いた別の確認用ファイル（60fps、445フレーム）。ゲームへのGLBはアニメーションなしで、Godot側を動作の基準とする。

## 動作

1. 台座の既存の展開が終わってから、2.6秒かけて腰ベルトを本人の左から右へ引く。短い手で途中を持ち替え、1.95秒で右腰のバックルに差し込み音を鳴らす。
2. `HelicopterArrivalDirector.menu_boost_launched` がヘリと椅子の共通発射イベント。装着完了の確認ができるまでヘリも発射しない。椅子は上向きに加速し、手足は操作盤から離れる。
3. FireVFXの炎は噴射口に追従。SmokeVFXはワールド座標で発生済みの粒子を残す。元素材は変更せず、設定・材質を複製する。煙用シェーダーだけはビルボード時の粒子サイズを維持する派生版を使用する。
4. `QuizManager` の一度だけ消費するメタデータでゲーム側へ渡す。ロード中は可動側の椅子だけを隠す。画面の開示と台座の展開後、1.8秒で降下し、逆噴射、0.3秒の接地収束、1秒のベルト解除を行う。
5. 手足が操作部へ戻り、既存のプレイヤー到着も完了してから開始入力を解放する。

キャンセルは姿勢と飛行状態を消去する。メニューのスキップは飛行済み状態、到着側のスキップは着席済み状態へ進める。既存ワイプの終了がヘリの完了通知より先になる経路も引き継ぐ。リトライは到着を再生しない。1P・チュートリアル・オンライン・リプレイは対象外。

効果音は `SFX` バスを使用。`tools/seat_launch/build_audio.py` で作成した波形を使用する。

## 検証と復元

```powershell
godot --headless --path . --script res://tests/seat_launch_bootstrap.gd
godot --path . --resolution 1280x720 --script res://tests/seat_launch_bootstrap.gd -- --full --capture --label=review --fps=60
```

`--fps=30/60/120`、`--endless`、`--players=1`、`--delay=秒`、`--scenario=skip/skip_buckle/skip_flight/cancel/cancel_flight/arrival_skip/retry` を指定できる。実際のStart入口を呼び、発射フレーム、固定側の全変換、実測着地誤差、入力ロック、重複、状態消費を確認する。

Blenderのプレビュー更新は `tests/seat_launch_export.gd` を実行し、Higgsfield Bridgeで `tools/seat_launch/bake_preview.py` を実行する。元のアクションは保持される。

退避と検証資料は `artifacts/seat_launch_rebuild/`。`previous/` に前実装、`before_recovery.blend` に未保存シーンを含む復元前状態、`restored.blend` に旧追加物の除去後、`chair_blockout.blend` と `chair_detail.blend` に制作段階の復元データを保存した。5スクリプトの復元元は `artifacts/seat_launch/baseline/`。これらを使う際も無関係な作業差分を一括リセットしない。
