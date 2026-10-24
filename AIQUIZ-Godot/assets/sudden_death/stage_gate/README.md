# 台座の横の水路の仕掛け（stage_gate）

サドンデス「つきやぶれ！スカイゲート」の乗り込み（`docs/sudden_death_v2/c130_float.md` 第4・6章、`skygate_build_plan.md` W2）。
台座の +X の側の横のスタンド 2 ブロック（40 m）を、海から上がる白い格子の塔 4 本で 14 m 持ち上げ、水上機がその下を後ろ向きにくぐる。
床の横の壁の昇降台（しまうときは床の縁から下へぶら下がって壁に沿うデッキ）が、外へ 90° 起きて床の高さの水平になり、
2 人を乗せて水上機の貨物室の床の高さまで下りる。機体はそのあと後ろ向きに寄ってきて、スロープの先をデッキの外の端の受けに載せる。
2026-10-19 作成、同じ日に昇降台を作り直した（`docs/sudden_death_v2/c130_float.md` 第10章）。

## 素材

| ファイル | 中身 |
| --- | --- |
| `stage_gate.glb` | `SG_Tower`（塔 1 本。原点＝下端の中心、高さ 40 m、1.8 m 四方の格子、頂上に機械の箱と滑車）、`SG_LiftDeck`（昇降台のデッキ。原点＝付け根の軸＝下面の壁側の辺の中心、+X へ 4.36 m、幅 3.8 m、厚み 0.26 m、黄色と黒の縞の縁、外の端にスロープの先を受ける一段低い受け 0.32 m × 深さ 0.30 m）、`SG_LiftHandrail`（手すり 1 本。原点＝付け根の軸。左右 2 本を同じ形で置き、X まわりに回して寝かせる）、`SG_LiftCarriage`（レールの中の台車 2 つとデッキの軸。原点はデッキと同じ軸）、`SG_LiftFrame`（壁の縦のレール 2 本・取り付けの金具・回転灯の腕。原点＝床の上面の高さの壁の面、下へ 6.9 m、横 ±2.2 m）、`SG_Beacon`（回転灯の光る部分） |
| `stage_gate_layout.json` | 寸法と三角形の数 |
| `source/blender/build_stage_gate.py` | ビルダー（ライブの Blender で runpy）。`stage_gate.blend` に保存する |

三角形：塔 3,016（4 本で 12,064）、デッキ 856、手すり 248（2 本で 496）、台車 240、レールと金具 1,640、回転灯 104。

## ゲーム側（Godot）

- `StandGate`（`scripts/world/sudden_death/stage_gate/stand_gate.gd`）：`setup(stage_env, podium_center, side)` → `activate()` → `set_towers(t)` / `set_lift(t)` → `restore()`。
  スタンドのブロックのメッシュは杭が海底まで伸びているので、持ち上げるときは海面より下を切った写しに替えて元を隠す（スタンドのファイルは変えない）。
  観客はブロックごとの MultiMesh（`Spectators/BlockNN`・`BlockNNProps`）を同じだけ上げる。`gap_center_z()` が水上機の中心線の z。
- `FloorEdgeLift`（同じフォルダ）：`setup(gap_z, side)`（しまった姿で置く）→ `set_target_y(下ろしたときのデッキの上面の y)` → `deploy()`（起きて手すり）→ `start_lower()`（下りる）→ `start_return()`（上がって手すりを寝かせ、ぶら下がる）。動きは `advance(delta)` で進む（回転灯も）。乗った人の足もとは `top_point()`・`deck_spot(u, z)`、体の沈みは `vertical_accel()`。テストと古い呼び方のために、すぐその姿にする `set_extend(t)`・`set_lower(t)`・`set_t(t)`・`deck_point(u)`・`set_reach(x)` も残してある。
- 確認：`tests/sudden_death_v2/stage_gate_check.gd`（引き分けの台座が出た実際のゲームで、持ち上げた杭の下端と尾翼の上のすき間 4.5 m、昇降台の端とスロープの端の重なり 0.25 m、元に戻すと観客の高さが戻ることを確かめる。画は `artifacts/sudden_death_v2/stage_gate/`）。
