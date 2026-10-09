# 連結チップソー台車の編集原本（壁速度タブの収納 v2）

`linked_saw_carriage.blend` は `assets/hazards/linked_saw_carriage.glb` と `assets/hazards/linked_saw_carriage_stow.json` の編集原本。2026-09-27に、v1（はしご状ブームを拡大して伸ばす方式）から四隅の昇降塔（ダビット）方式へ作り直した。v1の原本・GLB・スクリプト・テストは `artifacts/saw_stow/v1_backup/`（Git除外）にある。

既存の `Spin_Loop`／`Advance_Demo` と、`Carriage`・`Spin_NN`・`Roll_NN`・`Slide_NN` の基準姿勢は変えていない（ハッシュと基準行列をv1と照合済み）。

## シーンとコレクション

- シーン `CUTLINE | 8-blade carriage`（24fps）。
- `SAW_Import`：台車と収納機構。収納部品には `stow_v2` が付き、ボーンに親子付けされている。
- `CTL_StowRig`：コントロール `CTL_Stow`、荷の経路カーブ `CTL_RackPath_L/R`、経路を追う `CTL_RackTarget_L/R`、桁の肉抜き穴のブーリアン用カッター。
- `CTL_StowPhysics`：リジッドボディの代理（`RB_RackL/R_*` は塔のたわみ、`RB_Blade01〜08_*` は刃の揺れ）。
- 出力しない参照：
  - `REF_GodotContext`：ベルト・壁・キャラ。
  - `REF_Conveyor`：レール・側枠・縁灯（縁灯はゲームから廃止済み）。
  - `REF_Station_Menu_parts`：メニュー姿勢の操縦席。
  - `REF_Vessel_parts`：作業船。レンダーでは非表示。
  - `REF_StowContext`：確認用カメラ（`CAM_WallSpeedTab`、`CAM_MenuMain`、`CAM_Closeup`、`CAM_GameRear` ほか）。

## 機構とリグ

座標は台車ローカル（x＝横断、y＝進行方向、z＝上、ベルト面＝0）。新しい骨はすべて+Y向き・ロール0。基準姿勢で骨のローカル軸がワールド軸と一致する。

- **刃ごと**
  - `Ram_NN`：刃の揺れ用の回転。
  - `RamA/B/C_NN`：3段ラム。段は拡大と移動で伸びる。ハウジングの中から出るのは既知の妥協。
  - `Hinge_NN`：ラムの昇降。
  - `Tilt_NN`：刃を起こす軸。
  - `Spin_NN`：Child Of 制約を2つ持つ。`Carry_Tilt`（クレビス）と `Carry_Beam`（前側の吊り桁）を、クランプ時刻に影響度を一定補間で切り替える。
- **四隅（LF/LA/RF/RA）**
  - `Davit_c`：旋回。旋回軸は x=±12.10、y=±1.76、z=0.68。
  - `DavitS2〜S6_c`：6段マストで、平行移動のみ。
  - `Knuckle_c`：水平保持の継手と吊り桁の中央胴。
  - `BeamFlyP/N_c`：伸縮するフライ。
  - `Jaw_c_1〜4`：C形クランプ。
- **ドライバー**
  - 旋回角：`atan2`。
  - マストの伸び：旋回軸から `CTL_RackTarget` までの距離から縮長を引き、5段に等分する。
  - 桁の折り畳み：`fold`。フライは `fly`、クランプは `jaw`。
  - ラム：`Hinge` の高さから求める。
  - 刃の揺れ：リジッドボディの変位から求める。
- **コントロール `CTL_Stow`**：カスタムプロパティは次の7つ。
  - `path`：経路上の位置（0〜1）。
  - `fold`、`fly`、`jaw`（0〜1）。
  - `sway`、`rock`：2次運動の効き。両端で0。
  - `sag`：荷重移行の沈み（−1〜1）。
- **経路**：`CTL_RackPath_L/R` はビューポートで編集できるベジェ。次の順にたどる。
  1. 格納位置 → 刃列の脇で待機。
  2. 真上へ0.30m → 円弧 → 高さ3.85mで水平移動（刃の下端2.40m）。
  3. x=15.33で真下へ → 刃の中心 z=−1.90。
- **2次運動**：Generic Spring（SPRING2）。塔のたわみは2.4Hz・減衰比0.22、刃の揺れは1.8Hz・0.20。ばねの支点は各クリップの開始時に物体の位置へ置く（遠いとてこになり数m遅れる）。

## アクション

| 名前 | 対象 | 内容 |
|---|---|---|
| `Stow_ctl` / `Deploy_ctl` | `CTL_Stow` | コントロールのF-カーブとイベントのマーカー。Stow：`horn`・`clamp`・`release`・`lock`・`end`。Deploy：`horn`・`unlock`・`latch`・`unclamp`・`lock`・`end` |
| `Stow_src` / `Deploy_src` | リグ | ラム・起こし・モジュールのキーと、Child Of の影響度 |
| `Stow` / `Deploy` | リグ | 全骨を24fpsで焼き込んだクリップ（直線補間、各12.42秒）。GLBへはこれだけを出す |

- 保存状態では `Stow_src` を割り当て、NLAトラック（`Spin_Loop`、`Advance_Demo`、`Stow`、`Deploy`）はミュートしている。
- `Deploy` は `Stow` の運動学を時間反転したもの。2次運動は展開の時間順で計算し直している。
- 空のクレビスの動きは両クリップで鏡像にした。展開では荷が来る前に起き、収納では荷が離れてから縮む。このため、同じ位置での両クリップの差は2次運動の分だけになる（最大4.5cm・1.6°）。

## 再生成

`tools/saw_stow/build_stow.py` の段階を順に実行する。各段階は冪等。寸法・速度上限・タイミングは先頭の定数で変える。

| 段階 | 内容 |
|---|---|
| `bones` | 骨の追加と基準姿勢 |
| `detail` | 収納部品。断面ロフト、ベベル、Weighted Normal、ブーリアン |
| `rig` | 経路・Follow Path・ドライバー・Child Of |
| `motion` | ジャーク制限のS字、F-カーブ、マーカー |
| `dynamics` | リジッドボディの代理とばね |
| `bake` | 2クリップの物理を計算して焼き込み、NLAへ置く |
| `export` | GLBの書き出し |
| `sidecar` | JSONの書き出し |
| `audit` | BVHによる干渉・速度・離隔。`AUDIT_CLIP='Stow'`/`'Deploy'` で焼き込み済みを検査 |
| `verify` | 既存データの不変性、両端の一致、StowとDeployの差 |
| `transport` | 作業船との干渉 |

ライブのBlenderで実行する場合：

```python
STAGE = 'motion,dynamics,bake,export,sidecar'
exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_stow/build_stow.py', encoding='utf-8').read())
```

重い段階は、復旧コピーを開いた背景処理で実行する。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background <file.blend> --python-expr "STAGE='audit'; AUDIT_TAG='baked_stow'; AUDIT_CLIP='Stow'; exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_stow/build_stow.py', encoding='utf-8').read())"
```

`transport` を実行する前に、Godotで作業船の三角形を書き出す。

```powershell
godot --headless --path . --script res://tests/saw_stow_dock_export.gd
```

結果の保存先：

- `artifacts/saw_stow/v2/blender_validation.json`
- `artifacts/saw_stow/v2/transport_clearance.json`
- 復旧コピー：`artifacts/saw_stow/v2/blender/checkpoints/`

## 出力と取り込みの注意

- **fps**：シーンは24fpsのまま。変えると `Spin_Loop`（3.333秒）の長さが変わり、ゲーム内の刃の回転速度がずれる。
- **書き出し時の状態**：`ExportState` で、ドライバーと制約をミュートし、骨を四元数にし、焼き込んだクリップ以外の骨を基準姿勢に置く。ブーリアンは書き出しの間だけ評価する。EXACTは毎フレーム解き直すため、普段は `show_viewport=False` にしている。
- **メッシュ**：収納部品（280個）は、モディファイア適用後に1つのスキンメッシュ `SAW_StowSkinned` に結合して出す。骨ごとの頂点グループを使い、材質ごとに7サーフェス。台車全体は257サーフェス（v1は294）。
- **glTF書き出し**：`use_active_scene=True` が必須。出力時は全NLAトラックのミュートを一時解除する。
- **Godotの取り込み**：`linked_saw_carriage.glb.import` で `AnimationPlayer` のアニメーション最適化を無効にしている。既定の最適化は焼き込みキーを299→222へ間引き、刃の速度を0.7m/s跳ばせていた。
- **背景処理のBlender**：`--factory-startup` や `read_factory_settings()` は使わない。この環境では拡張機能のwheelが削除される（2026-09-27に発生し、`addon_utils.extensions_refresh(ensure_wheels=True)` で復旧）。

## 寸法の制約

| 対象 | 範囲 | この設計での扱い |
|---|---|---|
| 問題壁 | \|x\|≤11.9 | 格納状態の塔は x 11.97以上 |
| 作業船の昇降区画の角柱 | \|x\|≥12.275、\|y\| 1.14〜1.66、上端 z 0.605（上昇完了時） | 上昇中は柱の平面範囲に、搬出中は柱の頂部より下に、x 12.26を超える部品を置かない |
| コンベア側枠 | x≤12.0、上端 z 0.08 | 展開完了時、塔は旋回軸から真下へ吊り下がる（Godotの `SawChaseController`、外側へ3°）。下端 z −0.95、側枠との隙間1.3cm。縁灯は2026-09-27に廃止 |
| 膝ブラケット | 内側の側板（\|y\| 1.645〜1.672）とスタブ軸だけでドラムを支える | マストのy範囲（\|y\| 1.675〜1.845）の下には何も置かない。ドラムから台車へ下りるホースは廃止 |
| 操縦席（メニュー） | x 12.01〜13.85、\|y\|<0.85 | 上空を通るのは刃だけで、刃の下端は2.40m以上 |

`.gdignore` により、このフォルダーはGodotの取り込み対象外。
