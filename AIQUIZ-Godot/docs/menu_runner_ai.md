# メインメニュー背景のランナー AI

メインメニューの背景では、2 人（1P 表示なら 1 人）のランナーがコンベアの上を走り、流れてくるクイズ壁の正解の扉をくぐる。
このドキュメントは、その AI・見た目・ゴーストライダーの作りをまとめる。

## ファイル

| ファイル | 受け持ち |
|---|---|
| `scripts/ui/menu_wall_background_preview.gd` | 舞台（壁・ノコギリ・押し合い・出発演出・カメラ・破片）と、部品が読み書きする共有の状態（`_preview_gs`・`_p1_ai`・`_p2_ai`・`_ai_time`） |
| `scripts/ui/menu_preview_actor_ai_state.gd` | ランナー 1 人ぶんの状態（状態・事故・速度・ゴースト関連） |
| `scripts/ui/menu_preview_door_learner.gd` | 扉の上達（くぐれた割合が skill。ミスの揺らぎ） |
| `scripts/ui/menu_preview/menu_actor_ai.gd` | 状態の切り替え・行動・移動・ジャンプ・吹き飛び・海への落下・復活 |
| `scripts/ui/menu_preview/menu_runner_motor.gd` | 吹き飛び・空中の計算（純粋な計算） |
| `scripts/ui/menu_preview/menu_actor_emotes.gd` | エモートと、相手が死んだときの煽り |
| `scripts/ui/menu_preview/menu_actor_accidents.gd` | 潜伏型の事故（ノコギリのヒヤリ・事故）の後始末 |
| `scripts/ui/menu_preview/menu_door_learning.gd` | 近づく壁の扉へ向かう |
| `scripts/ui/menu_preview/menu_ghost_ride_director.gd` / `menu_ghost_rider_brain.gd` | 2P のゴーストライダー |
| `scripts/ui/menu_preview/menu_preview_geometry.gd` | コンベアと壁の寸法（持ち主と部品の両方が使う） |

部品は持ち主の `_init` で作る。`_ready` を呼ばずに `MenuWallBackgroundPreview.new()` するテストの fixture でも動く。
テストが直接呼ぶ非公開の名前（`_update_depth_shift`・`_clear_pending_accident`・`AI_STATE_NORMAL` など）は、持ち主に転送の関数・定数として残してある。

## 行動と動き

1.1〜2.6 秒ごとに次の行動を 1 つ選ぶ（2P は P1 と P2 で間隔をずらす）。横と前後の新しい目標へ走る／前へ・後ろへ踏み出す／ジャンプ／アクロバット。
横と前後は一定の速さで目標へ動き、両方着いたらすぐ次の目標へ走り出す（立ち止まらない）。
壁への激突・海への転落を AI がわざと選ぶことはない。死ぬのは扉のミスとノコギリだけ。

壁が近づくと（18 m 以内）正解の扉へ向かう。ミスは `MenuPreviewDoorLearner` の揺らぎから起きる。
正解の扉を 3 回くぐるごとに踊る（踊りながらも動き続ける）。

## 見た目

描画は本編と同じ `PlayerController.update_from_state` のまま（走り・エモート・空中の姿勢・押し合い）。
走りのアニメの速さは 2P で個体差を付け、前（壁の方）へ踏み出すあいだだけ速める。

## ゴーストライダー（2P だけ）

壁への激突か海への転落で死んだとき、3 回に 1 回くらい、本編と同じゴーストシャークに乗って生き残った方を襲う。
演出は本編の `GhostSharkRideController` をそのまま使う：死亡 → 魂がサメへ → 乗る → 光の柱 → 登場 → 照準・突進。死亡から照準まで約 11 秒。

- **乗る条件**：
  - メニューを開いて 15 秒後から。前回のライドから 50 秒あける
  - ノコギリでの死亡と 2P の取り外しは対象外
- **死んだ側の入力**：`MenuGhostRiderBrain`。考えてから狙い、作戦を決めて離す（PERFECT 55%・弱め 30%・溜めすぎ 15%）。ときどき大きく外す。考えているあいだにサメの上で踊ることもある
- **生き残った側**：
  - 乗るまでは煽る。乗ったら見物（WATCH）し、サメが来たら警戒（ALERT。エモート・アクロ・事故はしない）
  - 突進の構えを見て 35% で横へ跳びのいてよける
- **命中**：本編の吹き飛び（`apply_external_impulse`）を取り出し、0.6 倍でメニューの吹き飛びへ直す。コンベアの後端を越えたら海へ落ちて死ぬ
- **終わり**：2〜3 回突進したら帰り、死んだ側が 0.7 秒後に空から降ってくる
- **途中で畳む場面**：生き残った方の死亡・1P への切り替え・カスタマイズ・出発（Start）・メニューを離れるとき
- **ノコギリ**：ライド中は持ち場で待つ。終わると GRACE から追跡に戻る
- **壁**：2P で片方が死んでいるあいだ（ライド中も）は、死んでいる方はくぐったものとして扱い、生きている方がくぐれば壁を砕く
- **画面の構図**：サメの待つ場所と光の柱が、メニューの UI にかからない画面右に収まる奥行きを、実際のカメラで投影して選ぶ
- **本編への追加**：`GhostSharkRideController` に足したメニュー用の差し込み口は、既定値なら本編と同じ動き
  - プロパティ：`auto_detect_deaths`・`hover_*`・`rendezvous_*`・`heroic_follow_survivor`・`view_camera`
  - メソッド：`begin_for_dead_player`・`set_hud_enabled`・`rebind_player_controller`・`retire_ride`

## スイッチ（テスト・PV 撮影用）

| スイッチ | 止めると |
|---|---|
| `MenuGhostRideDirector.globally_enabled` | ゴーストライダーが出ない |

PV 撮影（`tests/pv_capture/pv_s04_s05_runtime.gd`・`pv_s23_runtime.gd`）はゴーストを止めて、撮影済みの素材と同じ見た目で撮る。
ノコギリのテスト（`menu_saw_runtime`・`menu_saw_edges`・`menu_saw_frequency_runtime`）はゴーストだけ止める。

## テスト

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/menu_runner_motor_bootstrap.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/menu_ghost_rider_brain_bootstrap.gd
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/menu_ghost_ride_bootstrap.gd
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/menu_push_bootstrap.gd
```

`class_name` のスクリプトを足したら、先に `--headless --path . --import` でクラスの一覧を更新する。
