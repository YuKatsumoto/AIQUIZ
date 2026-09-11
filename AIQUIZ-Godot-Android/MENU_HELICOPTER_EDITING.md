# メインメニューのヘリアニメーション編集

Godotで `res://scenes/menu_helicopter_sequence.tscn` を開きます。このシーンの既定は、スタートボタン後のキャラ回収です。

## 飛行経路

- `PickupP1Path` / `PickupP2Path`: ゲーム開始時の登場・はしご投下・回収・退出（編集の主対象）
- `IntroP1Path` / `IntroP2Path`: メニュー表示時の登場・投下・退出（残してあります。`show_intro_preview` をオンにすると見えます）
- 各 `Path3D` の点は、0番が画面外の開始地点、1番がホバー地点、2番が退出地点です。回収のホバー高さは点1の Y=10.2（地面 -1.2 のときワールド Y≈9.0）です。
- `Path3D` を選択し、3Dビューの点とハンドルをドラッグして形を変えます。
- `Path3D` ノード自体の位置はプレイヤー位置の基準として実行時に設定されるため、通常はノードではなくカーブの点を動かしてください。

`PreviewCamera` はメインメニューと同じ位置・画角です。F6 はこのカメラで `start_pickup` を再生します。

## タイミング

`AnimationPlayer` の autoplay は `start_pickup` です。

- `start_pickup`: ゲーム開始時の回収（F6）
- `intro_arrival`: メニュー表示時の投下

タイムラインをスクラブすると、ヘリの位置、ハッチ、巻いてあったロープのはしご、キャラ掴み、傾き、カメラを確認できます。キーを左右に動かすと実ゲームのタイミングにも反映されます。

`start_pickup` の目安:

| 秒 | 内容 |
| --- | --- |
| 0.0 | 画面外から接近 |
| 1.3 | ホバー定着 |
| 1.45 | ハッチ開放 |
| 1.50 / 1.68 | P1 / P2 はしご投下（`p1_ladder_deploy` / `p2_ladder_deploy`） |
| 2.25 / 2.48 | P1 / P2 掴み開始（`p1_action_progress` / `p2_action_progress`） |
| 3.25 / 3.48 | 掴み完了 |
| 3.45 | 離脱開始 |
| 6.4 | 画面外 |

主なトラック:

- `progress_ratio`: 飛行位置。値が止まっている区間はホバリングです。
- `p1_hatch` / `p2_hatch`: ハッチの開閉。
- `p1_ladder_deploy` / `p2_ladder_deploy`: 巻いてあったロープのはしご投下。実ゲームの投下タイミングのソースです。
- `p1_action_progress` / `p2_action_progress`: キャラの吸い上げタイミング。
- `p1_bank_deg` / `p2_bank_deg`: 左右の傾き。
- `p1_pitch_deg` / `p2_pitch_deg`: 前後の傾き。
- `camera_fov_delta` / `camera_tilt_deg`: カメラ演出。

オレンジ / 青のカプセルは回収されるプレイヤーの参照です。床マーカー `P1Ground` / `P2Ground` は非表示にしてあります。

編集後は `F6` でこのシーンの回収を確認し、`F5` で実際のメインメニュー演出を確認してください。
