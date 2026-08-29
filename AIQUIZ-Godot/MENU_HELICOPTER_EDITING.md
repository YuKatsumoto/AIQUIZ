# メインメニューのヘリアニメーション編集

Godotで `res://scenes/menu_helicopter_sequence.tscn` を開きます。

## 飛行経路

- `IntroP1Path` / `IntroP2Path`: メニュー表示時の登場・投下・退出
- `PickupP1Path` / `PickupP2Path`: ゲーム開始時の登場・回収・退出
- 各 `Path3D` の点は、0番が画面外の開始地点、1番が停止地点、2番が退出地点です。
- `Path3D` を選択し、3Dビューの点とハンドルをドラッグして形を変えます。
- `Path3D` ノード自体の位置はプレイヤー位置の基準として実行時に設定されるため、通常はノードではなくカーブの点を動かしてください。

## タイミング

`AnimationPlayer` で次のアニメーションを選択します。

- `intro_arrival`: メニュー表示時
- `start_pickup`: ゲーム開始時

タイムラインをスクラブすると、ヘリの位置、ハッチ、傾き、カメラを確認できます。キーを左右に動かすと実ゲームのタイミングにも反映されます。

主なトラック:

- `progress_ratio`: 飛行位置。値が止まっている区間はホバリングです。
- `p1_hatch` / `p2_hatch`: ハッチの開閉。
- `p1_action_progress` / `p2_action_progress`: 投下または吸い上げタイミング。
- `p1_bank_deg` / `p2_bank_deg`: 左右の傾き。
- `p1_pitch_deg` / `p2_pitch_deg`: 前後の傾き。
- `camera_fov_delta` / `camera_tilt_deg`: カメラ演出。

編集後は `F6` でこのシーンの見た目を確認し、`F5` で実際のメインメニュー演出を確認してください。
